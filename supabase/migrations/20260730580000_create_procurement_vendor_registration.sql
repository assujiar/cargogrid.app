-- Procurement capability PRC-251 (Vendor Registration and Onboarding, CG-S11-PRC-002)
-- The first real Phase 6 domain capability. Builds app.vendor_profiles as a governed
-- 1:1 extension of app.master_records where master_type_code='vendor' -- the single
-- canonical vendor identity ratified by ADR-0020 (docs/adr/ADR-0020-phase6-vendor-
-- identity-reconciliation-and-authority.md). Never a second vendor master, never a
-- touch to app.master_records/app.master_types/app.vendor_rate_versions themselves
-- (Prompt 251 §12/§24, ADR-0020 Consequences).
--
-- Design decisions, disclosed rather than left implicit:
--
-- 1. **RBAC seed, per ADR-0020.** Five new app.permissions rows for resource_module_code
--    'PRC': ('Reject','PRC','workflow',false), ('Override','PRC','workflow',false),
--    ('Download','PRC','standard',false), ('Import','PRC','standard',false),
--    ('View personal data','PRC','sensitive',true). All five action values already exist
--    in the fixed permissions_action_check CHECK constraint -- only new seed rows, the
--    CHECK constraint itself is never touched.
--
-- 2. **Authority routes exclusively through app.evaluate_permission(..., 'PRC', ...).**
--    ADR-0020 is explicit: "No Phase 6 RPC may rely on is_support_grant_authority
--    alone." app.create_master_record/app.update_master_record (PLT-120) gate on
--    app.is_support_grant_authority (tenant_admin/Supreme only) -- calling them from
--    inside a vendor-profile RPC would force every ordinary Procurement staff member
--    (holding only PRC:Create) to also be tenant_admin, contradicting Prompt 251 §26
--    ("Procurement staff maintain drafts"). This migration therefore does NOT call
--    app.create_master_record: app.create_vendor_profile_draft inserts directly into
--    app.master_records from inside its own SECURITY DEFINER body, after its own
--    PRC:Create evaluate_permission check has already passed -- the same "this
--    capability's own authority gate, not master_records' interim gate" posture
--    ADR-0020's Security consequence describes. The master_type_code='vendor'
--    constraint, the (master_type_code, tenant_id, code) uniqueness, and
--    app.enforce_master_record_scope all still apply structurally, unchanged --
--    only the AUTHORITY check is Phase-6-owned, not the referential integrity.
--
-- 3. **Numbering.** app.master_records.code is the stable vendor identity code
--    (docs/architecture convention, mirrors every other master type). A small
--    one-row-per-tenant counter (app.vendor_code_counters/app.next_vendor_code),
--    reusing app.next_quotation_number's own atomic INSERT ... ON CONFLICT ... DO
--    UPDATE ... RETURNING shape (COM-151) -- deliberately NOT granted to
--    `authenticated` directly (ISS-2026-033's own lesson about app.next_quotation_
--    number: a bare grant lets any authenticated session burn another tenant's
--    sequence with no authority check of its own). It is only ever called from
--    inside this migration's own already-authorized SECURITY DEFINER functions.
--
-- 4. **tenant_id is duplicated directly on every new table**, not resolved solely via
--    a join through master_records -- the same choice COM-149's own
--    app.vendor_rate_versions already made (disclosed in that migration's own header:
--    "vendor rates are tenant-wide reference data"), required for the hardened RLS
--    default-deny form (pattern (3)) to reference tenant_id directly in each policy's
--    qual, and for direct tenant-scoped indexing. A BEFORE INSERT/UPDATE trigger
--    (app.enforce_vendor_profile_identity) keeps app.vendor_profiles.tenant_id and the
--    referenced master_records row's own tenant_id, and master_type_code='vendor',
--    aligned structurally -- never merely a convention.
--
-- 5. **Lifecycle**, per docs/build-log/phase-06/00_PROCUREMENT_VENDOR_WBS.md §9:
--    draft -> submitted -> under_review -> approved -> active <-> suspended -> archived,
--    plus rejected (submitted/under_review -> draft, with revision_reason, never a
--    separate terminal status) and blacklisted (active/suspended only, reason+evidence+
--    approval required). One RPC per transition, each carrying the mandatory
--    pre-check/post-check record_version optimistic-concurrency shape verbatim from
--    supabase/migrations/20260730520000_harden_stale_version_no_op_and_swallowed_
--    idempotency_guard.sql. `begin_vendor_profile_review` (submitted -> under_review)
--    is one genuinely additional transition beyond the eight the task package names by
--    example ("create_vendor_profile_draft, submit_vendor_profile_for_review,
--    decide_vendor_profile_review, activate..., suspend..., reactivate..., archive...,
--    blacklist...") -- without it, under_review (a real, separately named state in the
--    WBS's own arrow chain) would never be reachable by any RPC. decide_vendor_profile_
--    review accepts a submission from either 'submitted' or 'under_review' (a reviewer
--    is not required to formally claim review before deciding), so begin_review is an
--    optional, not mandatory, step for a reviewer who wants to signal "in progress."
--    archive_vendor_profile is reachable only from 'suspended', matching the WBS's own
--    literal arrow chain ("active <-> suspended -> archived", archive hangs off
--    suspended, not active, in that notation) -- an active vendor must be suspended
--    first, with its own required reason, before it can be archived.
--
-- 6. **PRC action mapping** (the only seven-plus-five actions PRC actually holds --
--    View/Create/Edit/Delete/Approve/Export/View cost plus this migration's own five):
--    create draft = Create; submit/child CRUD = Edit; begin_review/decide-approve/
--    activate = Approve; decide-reject = Reject (using the actual seeded Reject action
--    for something other than Approve, rather than overloading Approve for both
--    directions); suspend/reactivate/blacklist = Override (all three are governed
--    exceptions to the normal flow); archive = Edit (administrative closure, PRC has no
--    Close/Reopen action the way OPS/FIN do); issuing an intake token = Create.
--
-- 7. **Duplicate review never auto-merges** (Prompt 251 §24's own binding rule,
--    reiterated in the WBS). app.vendor_duplicate_candidates records a decision
--    (linked/dismissed) with reason/actor/timestamp -- 'linked' documents that a human
--    reviewer determined two registrations describe the same real-world vendor; it does
--    NOT invoke app.merge_master_records (PLT-120, tenant_admin-gated, out of this
--    capability's own authority model) or write any data. A real data merge, if ever
--    needed, remains a deliberate follow-on action a tenant_admin performs through
--    PLT-120's own existing tooling. app.search_vendor_duplicate_candidates is
--    trigram-based (pg_trgm, newly enabled by this migration) over app.vendor_profiles.
--    legal_name/trade_name -- deliberately NOT over app.master_records (touching that
--    table, even to add a supporting index, is out of this capability's forbidden-files
--    scope) -- so no GIN index exists on master_records; matching is a sequential-scan
--    similarity() comparison, disclosed as a real, bounded (per-tenant, no live
--    production data yet) performance characteristic rather than fabricated as O(1).
--    submit_vendor_profile_for_review blocks submission while any 'pending'
--    vendor_duplicate_candidates row still points at this registration (exception flow
--    §23: "Block duplicate ambiguity").
--
-- 8. **Intake tokens** follow app.shipment_tracking_tokens' own proven shape (OPS-180):
--    token_hash is a one-way sha256 digest, the raw token is returned exactly once by
--    app.create_vendor_intake_token and never stored. The token-redemption RPC
--    (app.redeem_vendor_intake_token_and_submit) and the config-flag-gated
--    self-registration RPC (app.submit_vendor_profile_self_registration) are BOTH
--    genuinely anonymous entry points with no actor/session -- per this migration's own
--    mandatory-pattern instruction, they open with a comment explaining why no
--    evaluate_permission call exists, mirroring app.lookup_public_shipment_tracking's
--    own "never raise, return a status column" shape so a rate-limit attempt-log insert
--    always survives to commit even on a rejected attempt. UNLIKE app.lookup_public_
--    shipment_tracking, neither is granted to `anon` -- both are `service_role`-only.
--    The public Next.js route that fronts them (app/(public)/vendor-intake/[token]/)
--    is itself server-rendered and its Server Actions use the service-role Supabase
--    client (lib/supabase/service-role.ts), never a browser-side anon client -- the raw
--    token (or the tenant's own published self-registration config flag) remains the
--    entire authorization surface either way, so no new `anon` Postgres grant was
--    necessary, keeping this repository's standing "anon holds zero EXECUTE" convention
--    (ERR-2026-004) intact beyond its one already-disclosed, unrelated exception.
--    Self-registration re-uses the existing Configuration Engine (PLT-121, 'feature'
--    config_type, already seeded) rather than a new table -- the exact ATW-226A
--    precedent (`app.resolve_tenant_tracking_package`) for a tenant-scoped boolean
--    entitlement flag, key 'procurement.vendor_self_registration.enabled', defaulting
--    to false/disabled per BP-A08's "never globally public by default."
--
-- 9. **Field masking.** Vendor contact email/phone are personal data of a named
--    individual, not the vendor's own corporate identity -- app.has_prc_view_personal_data
--    (mirrors app.has_view_cost's own one-line SELECT-wrapped-evaluate_permission
--    shape) gates them in app.list_vendor_contacts' own projection; a caller without
--    PRC:View personal data still sees the contact row (name/title/is_primary) with
--    email/phone nulled, never a withheld row.
--
-- 10. **Out of scope, left to later Phase 6 prompts** (Prompt 251 §"WHAT NOT TO BUILD"):
--     no bank/tax/NPWP/payment-instrument column (PRC-252/254 own scope); no
--     assessment/scoring/corrective-action table (PRC-252); no compliance-document-
--     expiry tracking (PRC-253) -- a company-registration document, if attached, uses
--     the existing Document/File Engine directly (app.initiate_file_upload,
--     record_type='vendor_profile', record_id=vendor's own master_record_id), never a
--     second file table; no rate/pricelist table, and app.vendor_rate_versions is
--     never touched (PRC-255's own additive vendor_master_id column, not this
--     migration's job); no RFQ/PO/contract/capacity/assignment/performance/invoice-
--     matching (PRC-256..271).
--
-- 11. No REST/GraphQL adapter exists for any business domain yet (confirmed by direct
--     repository inspection, `app/api/` holds only the two GPS Gateway/webhook
--     routes) -- this capability follows the identical, already-disclosed Phase 5
--     precedent (ATW-229 et al.): domain service layer + Next.js Server Actions only.
--
-- Per ERR-2026-004 (docs/runtime/ERROR_LEDGER.md): this migration carries its own
-- explicit REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA app FROM PUBLIC statement before
-- its final grants, the standing per-migration convention since PLT-118.

create extension if not exists pg_trgm;

-- ===========================================================================
-- 1. RBAC seed additions (ADR-0020) -- new (action, module) rows only, the fixed
--    permissions_action_check CHECK constraint is never altered.
-- ===========================================================================

insert into app.permissions (action, resource_module_code, category, protected) values
  ('Reject', 'PRC', 'workflow', false),
  ('Override', 'PRC', 'workflow', false),
  ('Download', 'PRC', 'standard', false),
  ('Import', 'PRC', 'standard', false),
  ('View personal data', 'PRC', 'sensitive', true);

-- ===========================================================================
-- 2. Vendor code numbering (design note 3) -- internal-only, never granted to
--    `authenticated` (ISS-2026-033's own lesson).
-- ===========================================================================

create table app.vendor_code_counters (
  tenant_id uuid primary key references app.tenants (id),
  last_seq integer not null default 0
);

comment on table app.vendor_code_counters is
  'PRC-251: one atomic, tenant-scoped monotonic counter for app.next_vendor_code(), mirroring app.quotation_number_counters (COM-151). Never reused.';

create function app.next_vendor_code(p_tenant_id uuid)
returns text
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_seq integer;
begin
  insert into app.vendor_code_counters (tenant_id, last_seq)
  values (p_tenant_id, 1)
  on conflict (tenant_id) do update set last_seq = app.vendor_code_counters.last_seq + 1
  returning last_seq into v_seq;

  return 'VND-' || to_char(now(), 'YYYY') || '-' || lpad(v_seq::text, 6, '0');
end;
$$;

comment on function app.next_vendor_code is
  'PRC-251: internal-only (no authenticated grant) -- called exclusively from inside this migration''s already-authorized SECURITY DEFINER functions, never callable directly.';

-- ===========================================================================
-- 3. Self-registration entitlement flag -- Configuration Engine reuse (design note 8).
-- ===========================================================================

create function app.is_vendor_self_registration_enabled(p_tenant_id uuid)
returns boolean
language sql
stable
as $$
  select coalesce((r.items ->> 'procurement.vendor_self_registration.enabled')::boolean, false)
  from (select 1) as _one
  left join app.resolve_config('feature', p_tenant_id) r on true;
$$;

comment on function app.is_vendor_self_registration_enabled is
  'PRC-251: reads the tenant-scoped procurement.vendor_self_registration.enabled item from the existing feature config_type (PLT-121, ATW-226A precedent). Honest default false (BP-A08: never globally public by default) when no tenant admin has ever published a value.';

-- Anonymous-safe tenant-slug resolver for the genuinely public self-registration
-- page (app/(public)/vendor-intake/register/[tenantSlug]/) -- added during
-- adversarial review to close a real "self-registration is built but never
-- reachable from any public route" gap. app.tenants itself carries no
-- authenticated/anon SELECT grant or policy at all (service_role-only), so this
-- narrow, single-purpose function is the only way an anonymous visitor's tenant
-- slug can ever resolve to a tenant_id. Collapses "slug does not exist", "tenant is
-- not active", and "self-registration is not enabled for this tenant" into the
-- SAME uniform (null, false) response -- never distinguishing them -- so this
-- cannot be used to enumerate valid tenant slugs or their configuration state.
create function app.resolve_vendor_self_registration_target(p_tenant_slug text)
returns table (tenant_id uuid, self_registration_enabled boolean)
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_tenant_id uuid;
begin
  select id into v_tenant_id from app.tenants where slug = p_tenant_slug and canonical_status = 'active';
  if v_tenant_id is null then
    return query select null::uuid, false;
    return;
  end if;
  if not app.is_vendor_self_registration_enabled(v_tenant_id) then
    return query select null::uuid, false;
    return;
  end if;
  return query select v_tenant_id, true;
end;
$$;

comment on function app.resolve_vendor_self_registration_target is 'PRC-251: genuinely anonymous, service_role-only. The one and only slug->tenant_id resolution path for the public self-registration page -- returns (null, false) uniformly for a nonexistent slug, an inactive tenant, AND a tenant that has not enabled self-registration, so no enumeration signal escapes.';

-- ===========================================================================
-- 4. app.vendor_profiles -- governed 1:1 extension of app.master_records
--    (master_type_code='vendor'), per ADR-0020.
-- ===========================================================================

create table app.vendor_profiles (
  master_record_id uuid primary key references app.master_records (id),
  tenant_id uuid not null references app.tenants (id),
  legal_name text not null,
  trade_name text,
  legal_entity_type text,
  business_registration_number text,
  vendor_category text,
  payment_term_days integer,
  intake_source text not null,
  lifecycle_status text not null default 'draft',
  revision_reason text,
  suspend_reason text,
  blacklist_reason text,
  blacklist_evidence_ref text,
  idempotency_key text,
  record_version integer not null default 1,
  created_by text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint vendor_profiles_legal_name_check check (length(trim(legal_name)) > 0),
  constraint vendor_profiles_intake_source_check check (intake_source in ('staff_created', 'invited', 'self_registered', 'bulk_import')),
  constraint vendor_profiles_lifecycle_status_check check (
    lifecycle_status in ('draft', 'submitted', 'under_review', 'approved', 'active', 'suspended', 'archived', 'blacklisted')
  ),
  constraint vendor_profiles_payment_term_check check (payment_term_days is null or payment_term_days >= 0),
  constraint vendor_profiles_suspend_reason_check check (lifecycle_status <> 'suspended' or (suspend_reason is not null and length(trim(suspend_reason)) > 0)),
  constraint vendor_profiles_blacklist_reason_check check (
    lifecycle_status <> 'blacklisted' or (blacklist_reason is not null and length(trim(blacklist_reason)) > 0 and blacklist_evidence_ref is not null and length(trim(blacklist_evidence_ref)) > 0)
  )
);

comment on table app.vendor_profiles is
  'PRC-251: governed 1:1 extension of app.master_records where master_type_code=''vendor'' (ADR-0020) -- the single canonical vendor identity Commercial''s vendor_rate lookup, Operations'' resource_assignments, and Finance''s AP/vendor-bill/settlement chain all ultimately resolve to via master_record_id. tenant_id is duplicated from the referenced master_records row (enforced by app.enforce_vendor_profile_identity, never merely a convention) for direct RLS/index use, matching app.vendor_rate_versions'' own established choice.';

create index vendor_profiles_tenant_status_idx on app.vendor_profiles (tenant_id, lifecycle_status);
create index vendor_profiles_tenant_category_idx on app.vendor_profiles (tenant_id, vendor_category);
create unique index vendor_profiles_idempotency_key_unique on app.vendor_profiles (tenant_id, idempotency_key) where idempotency_key is not null;
create index vendor_profiles_legal_name_trgm_idx on app.vendor_profiles using gin (legal_name gin_trgm_ops);
create index vendor_profiles_trade_name_trgm_idx on app.vendor_profiles using gin (trade_name gin_trgm_ops) where trade_name is not null;

create function app.enforce_vendor_profile_identity()
returns trigger
language plpgsql
as $$
declare
  v_master app.master_records;
begin
  select * into v_master from app.master_records where id = new.master_record_id;
  if not found then
    raise exception 'master_record_not_found: no master record %', new.master_record_id using errcode = 'foreign_key_violation';
  end if;
  if v_master.master_type_code <> 'vendor' then
    raise exception 'invalid_vendor_identity: master record % is master_type_code %, expected vendor', new.master_record_id, v_master.master_type_code
      using errcode = 'check_violation';
  end if;
  if v_master.tenant_id is distinct from new.tenant_id then
    raise exception 'invalid_vendor_identity: master record % belongs to tenant %, not %', new.master_record_id, v_master.tenant_id, new.tenant_id
      using errcode = 'check_violation';
  end if;
  return new;
end;
$$;

create trigger vendor_profiles_enforce_identity
  before insert or update of master_record_id, tenant_id on app.vendor_profiles
  for each row
  execute function app.enforce_vendor_profile_identity();

-- ===========================================================================
-- 5. Child tables.
-- ===========================================================================

create table app.vendor_contacts (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  master_record_id uuid not null references app.vendor_profiles (master_record_id),
  name text not null,
  title text,
  email text,
  phone text,
  is_primary boolean not null default false,
  status text not null default 'active',
  record_version integer not null default 1,
  created_by text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint vendor_contacts_name_check check (length(trim(name)) > 0),
  constraint vendor_contacts_status_check check (status in ('active', 'removed')),
  constraint vendor_contacts_email_check check (email is null or email ~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$')
);

comment on table app.vendor_contacts is 'PRC-251: one row per contact person for a vendor profile. Soft-deleted (status=''removed''), never physically deleted, preserving lineage for the lifecycle/audit trail.';
create index vendor_contacts_master_record_idx on app.vendor_contacts (master_record_id) where status = 'active';
create unique index vendor_contacts_one_primary_idx on app.vendor_contacts (master_record_id) where status = 'active' and is_primary;

create table app.vendor_addresses (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  master_record_id uuid not null references app.vendor_profiles (master_record_id),
  address_type text not null,
  street text not null,
  city text not null,
  province text,
  postal_code text,
  country text not null,
  status text not null default 'active',
  record_version integer not null default 1,
  created_by text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint vendor_addresses_address_type_check check (address_type in ('legal', 'billing', 'operational')),
  constraint vendor_addresses_status_check check (status in ('active', 'removed')),
  constraint vendor_addresses_street_check check (length(trim(street)) > 0),
  constraint vendor_addresses_city_check check (length(trim(city)) > 0),
  constraint vendor_addresses_country_check check (length(trim(country)) > 0)
);

comment on table app.vendor_addresses is 'PRC-251: one row per address (legal/billing/operational) for a vendor profile. Soft-deleted, never physically deleted.';
create index vendor_addresses_master_record_idx on app.vendor_addresses (master_record_id) where status = 'active';

create table app.vendor_services (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  master_record_id uuid not null references app.vendor_profiles (master_record_id),
  service_type text not null,
  status text not null default 'active',
  record_version integer not null default 1,
  created_by text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint vendor_services_service_type_check check (length(trim(service_type)) > 0),
  constraint vendor_services_status_check check (status in ('active', 'removed'))
);

comment on table app.vendor_services is 'PRC-251: one row per service the vendor offers -- service_type is free text, mirroring app.vendor_rate_versions'' own established free-text service_type/mode convention (no Operations service-catalogue master exists yet).';
create index vendor_services_master_record_idx on app.vendor_services (master_record_id) where status = 'active';
create unique index vendor_services_unique_active_idx on app.vendor_services (master_record_id, service_type) where status = 'active';

create table app.vendor_coverage (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  master_record_id uuid not null references app.vendor_profiles (master_record_id),
  origin_lane text not null,
  destination_lane text,
  status text not null default 'active',
  record_version integer not null default 1,
  created_by text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint vendor_coverage_origin_lane_check check (length(trim(origin_lane)) > 0),
  constraint vendor_coverage_status_check check (status in ('active', 'removed'))
);

comment on table app.vendor_coverage is 'PRC-251: one row per lane or region the vendor covers -- origin_lane/destination_lane free text, mirroring app.vendor_rate_versions'' own origin_lane/destination_lane convention. destination_lane is nullable for a whole-region coverage declaration (origin_lane then holds the region label).';
create index vendor_coverage_master_record_idx on app.vendor_coverage (master_record_id) where status = 'active';

-- Shared touch trigger for the four simple child tables above (identical shape:
-- record_version += 1, updated_at := now()) -- one function, four attachments,
-- rather than four near-identical copies.
create function app.touch_vendor_profile_child_row()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  new.record_version := old.record_version + 1;
  return new;
end;
$$;

create trigger vendor_contacts_touch_row before update on app.vendor_contacts for each row execute function app.touch_vendor_profile_child_row();
create trigger vendor_addresses_touch_row before update on app.vendor_addresses for each row execute function app.touch_vendor_profile_child_row();
create trigger vendor_services_touch_row before update on app.vendor_services for each row execute function app.touch_vendor_profile_child_row();
create trigger vendor_coverage_touch_row before update on app.vendor_coverage for each row execute function app.touch_vendor_profile_child_row();

-- ===========================================================================
-- 6. Lifecycle event history (append-only) -- backs app.get_vendor_lifecycle_history.
-- ===========================================================================

create table app.vendor_profile_lifecycle_events (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  master_record_id uuid not null references app.vendor_profiles (master_record_id),
  from_status text not null,
  to_status text not null,
  reason text,
  evidence_ref text,
  actor_auth_user_id uuid,
  actor_label text,
  occurred_at timestamptz not null default now()
);

comment on table app.vendor_profile_lifecycle_events is 'PRC-251: append-only lifecycle transition history, one row per real transition, written by every lifecycle RPC in the same transaction as the state change itself. Distinct from app.audit_logs (compliance-wide who-changed-what) -- this is the domain-shaped timeline app.get_vendor_lifecycle_history/the vendor detail UI reads directly, never re-derived from audit_logs.';
create index vendor_profile_lifecycle_events_master_record_idx on app.vendor_profile_lifecycle_events (master_record_id, occurred_at);

-- ===========================================================================
-- 7. Duplicate-review candidates -- never auto-merged (design note 7).
-- ===========================================================================

create table app.vendor_duplicate_candidates (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  source_master_record_id uuid not null references app.vendor_profiles (master_record_id),
  candidate_master_record_id uuid not null references app.vendor_profiles (master_record_id),
  similarity_basis text not null,
  similarity_score numeric,
  decision text not null default 'pending',
  decided_by text,
  decided_at timestamptz,
  decided_reason text,
  record_version integer not null default 1,
  created_by text,
  created_at timestamptz not null default now(),
  constraint vendor_duplicate_candidates_not_self_check check (source_master_record_id <> candidate_master_record_id),
  constraint vendor_duplicate_candidates_similarity_basis_check check (length(trim(similarity_basis)) > 0),
  constraint vendor_duplicate_candidates_decision_check check (decision in ('pending', 'linked', 'dismissed')),
  constraint vendor_duplicate_candidates_decided_shape_check check (
    (decision = 'pending' and decided_at is null and decided_by is null and decided_reason is null) or
    (decision <> 'pending' and decided_at is not null and decided_by is not null and decided_reason is not null and length(trim(decided_reason)) > 0)
  )
);

comment on table app.vendor_duplicate_candidates is 'PRC-251: source registration -> candidate existing vendor identity pairing, flagged for human review. decision=''linked'' documents a reviewer''s finding that the two registrations are the same real-world vendor -- it never triggers an automatic merge (Prompt 251 §24''s own binding rule); any real data consolidation remains a deliberate, separate PLT-120 app.merge_master_records action a tenant_admin performs.';
create index vendor_duplicate_candidates_source_idx on app.vendor_duplicate_candidates (source_master_record_id);
create index vendor_duplicate_candidates_source_pending_idx on app.vendor_duplicate_candidates (source_master_record_id) where decision = 'pending';

-- ===========================================================================
-- 8. Intake tokens (invitation flow) -- design note 8.
-- ===========================================================================

create table app.vendor_intake_tokens (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  token_hash text not null,
  status text not null default 'pending',
  intended_email text not null,
  expires_at timestamptz not null,
  idempotency_key text,
  created_by_auth_user_id uuid,
  created_by text,
  created_at timestamptz not null default now(),
  redeemed_at timestamptz,
  redeemed_master_record_id uuid references app.master_records (id),
  revoked_at timestamptz,
  revoked_reason text,
  record_version integer not null default 1,
  constraint vendor_intake_tokens_status_check check (status in ('pending', 'redeemed', 'revoked', 'expired')),
  constraint vendor_intake_tokens_intended_email_check check (intended_email ~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$'),
  constraint vendor_intake_tokens_token_hash_unique unique (token_hash)
);

comment on table app.vendor_intake_tokens is 'PRC-251: one hashed, single-use bearer token per invited vendor, mirroring app.shipment_tracking_tokens (OPS-180). token_hash is a one-way sha256 digest; the raw value is returned exactly once by app.create_vendor_intake_token and never stored. Redemption reads only its own row -- never any other tenant/vendor data (Prompt 251 §16).';
create index vendor_intake_tokens_tenant_idx on app.vendor_intake_tokens (tenant_id);
create unique index vendor_intake_tokens_idempotency_key_unique on app.vendor_intake_tokens (tenant_id, idempotency_key) where idempotency_key is not null;

-- Append-only anti-enumeration evidence for the two anonymous entry points, mirroring
-- app.tracking_lookup_attempts (OPS-180) exactly.
create table app.vendor_intake_attempts (
  id uuid primary key default gen_random_uuid(),
  client_key text not null,
  kind text not null,
  result text not null,
  occurred_at timestamptz not null default now(),
  constraint vendor_intake_attempts_kind_check check (kind in ('token_redeem', 'self_register')),
  constraint vendor_intake_attempts_result_check check (result in ('success', 'not_found', 'invalid', 'rate_limited', 'disabled', 'conflict'))
);

comment on table app.vendor_intake_attempts is 'PRC-251: append-only anti-enumeration/anti-abuse evidence for app.redeem_vendor_intake_token_and_submit and app.submit_vendor_profile_self_registration, mirroring app.tracking_lookup_attempts (OPS-180). client_key is a hash of the caller''s own IP/session, computed by the calling Server Action.';
create index vendor_intake_attempts_client_key_idx on app.vendor_intake_attempts (client_key, occurred_at desc);

-- ===========================================================================
-- 9. Field masking helper (design note 9).
-- ===========================================================================

create function app.has_prc_view_personal_data(p_tenant_id uuid, p_auth_user_id uuid default auth.uid())
returns boolean
language sql
stable
security definer
set search_path = app, pg_temp
as $$
  select (app.evaluate_permission(p_auth_user_id, p_tenant_id, 'PRC', 'View personal data')).allowed;
$$;

comment on function app.has_prc_view_personal_data is 'PRC-251: field-masking gate mirroring app.has_view_cost''s own shape -- true if the caller holds the real, seeded PRC:View personal data permission for the given tenant.';

-- ===========================================================================
-- 10. Lifecycle RPCs.
-- ===========================================================================

create function app.create_vendor_profile_draft(
  p_tenant_id uuid,
  p_legal_name text,
  p_trade_name text,
  p_legal_entity_type text,
  p_business_registration_number text,
  p_vendor_category text,
  p_payment_term_days integer,
  p_intake_source text,
  p_idempotency_key text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.vendor_profiles
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_existing app.vendor_profiles;
  v_code text;
  v_master app.master_records;
  v_profile app.vendor_profiles;
begin
  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'PRC', 'Create');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:Create (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if p_legal_name is null or length(trim(p_legal_name)) = 0 then
    raise exception 'invalid_legal_name: legal_name must not be empty' using errcode = 'check_violation';
  end if;
  if p_intake_source not in ('staff_created', 'bulk_import') then
    raise exception 'invalid_intake_source: % is not valid for staff-initiated draft creation', p_intake_source using errcode = 'check_violation';
  end if;
  if p_payment_term_days is not null and p_payment_term_days < 0 then
    raise exception 'invalid_payment_term: payment_term_days must not be negative' using errcode = 'check_violation';
  end if;

  if p_idempotency_key is not null then
    select vp.* into v_existing
    from app.vendor_profiles vp
    where vp.tenant_id = p_tenant_id and vp.idempotency_key = p_idempotency_key;
    if found then
      if v_existing.legal_name is distinct from p_legal_name then
        raise exception 'idempotency_key_conflict: idempotency key % was already used for a different vendor registration (legal_name %)', p_idempotency_key, v_existing.legal_name
          using errcode = 'unique_violation';
      end if;
      return v_existing;
    end if;
  end if;

  v_code := app.next_vendor_code(p_tenant_id);

  insert into app.master_records (master_type_code, tenant_id, code, name, aliases, attributes, created_by)
  values ('vendor', p_tenant_id, v_code, p_legal_name, '[]'::jsonb, '{}'::jsonb, p_actor_label)
  returning * into v_master;

  -- Nested begin/exception unique_violation recovery (mirrors app.create_cycle_count_plan/
  -- app.reserve_vehicle_capacity, 20260730390000): two callers racing the SAME
  -- idempotency_key both pass the pre-check above and both reach this INSERT; the
  -- loser must gracefully return the winner's row (a genuine retry), not surface a
  -- raw, unclassified unique_violation. The same target-mismatch discipline as the
  -- pre-check applies to the race-recovery read.
  begin
    insert into app.vendor_profiles (
      master_record_id, tenant_id, legal_name, trade_name, legal_entity_type,
      business_registration_number, vendor_category, payment_term_days, intake_source,
      idempotency_key, created_by
    )
    values (
      v_master.id, p_tenant_id, p_legal_name, p_trade_name, p_legal_entity_type,
      p_business_registration_number, p_vendor_category, p_payment_term_days, p_intake_source,
      p_idempotency_key, p_actor_label
    )
    returning * into v_profile;
  exception
    when unique_violation then
      select vp.* into v_existing from app.vendor_profiles vp where vp.tenant_id = p_tenant_id and vp.idempotency_key = p_idempotency_key;
      if not found then
        raise;
      end if;
      if v_existing.legal_name is distinct from p_legal_name then
        raise exception 'idempotency_key_conflict: idempotency key % was already used for a different vendor registration (legal_name %)', p_idempotency_key, v_existing.legal_name
          using errcode = 'unique_violation';
      end if;
      return v_existing;
  end;

  insert into app.vendor_profile_lifecycle_events (tenant_id, master_record_id, from_status, to_status, actor_auth_user_id, actor_label)
  values (p_tenant_id, v_profile.master_record_id, 'none', 'draft', p_actor_auth_user_id, p_actor_label);

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'create_vendor_profile_draft',
    'app.vendor_profiles', v_profile.master_record_id, 'success', null, null, to_jsonb(v_profile)
  );

  return v_profile;
end;
$$;

comment on function app.create_vendor_profile_draft is 'PRC-251: creates the canonical master_records row (master_type_code=''vendor'') and its vendor_profiles extension together, in one transaction. Does NOT call app.create_master_record (design note 2) -- gates exclusively on PRC:Create.';

create function app.submit_vendor_profile_for_review(
  p_master_record_id uuid,
  p_expected_version integer,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.vendor_profiles
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_profile app.vendor_profiles;
  v_contact_count integer;
  v_legal_address_count integer;
  v_service_count integer;
  v_pending_dupes integer;
begin
  select * into v_profile from app.vendor_profiles where master_record_id = p_master_record_id;
  if not found then
    raise exception 'vendor_profile_not_found: %', p_master_record_id using errcode = 'no_data_found';
  end if;
  if v_profile.record_version <> p_expected_version then
    raise exception 'stale_version: vendor profile % expected version % but found %', p_master_record_id, p_expected_version, v_profile.record_version
      using errcode = 'serialization_failure';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_profile.tenant_id, 'PRC', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_profile.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_profile.lifecycle_status <> 'draft' then
    raise exception 'invalid_transition: vendor profile % is % and cannot be submitted for review', p_master_record_id, v_profile.lifecycle_status
      using errcode = 'check_violation';
  end if;

  select count(*) into v_contact_count from app.vendor_contacts where master_record_id = p_master_record_id and status = 'active';
  if v_contact_count = 0 then
    raise exception 'missing_required_contact: vendor profile % has no active contact', p_master_record_id using errcode = 'check_violation';
  end if;

  select count(*) into v_legal_address_count from app.vendor_addresses where master_record_id = p_master_record_id and status = 'active' and address_type = 'legal';
  if v_legal_address_count = 0 then
    raise exception 'missing_required_address: vendor profile % has no active legal address', p_master_record_id using errcode = 'check_violation';
  end if;

  select count(*) into v_service_count from app.vendor_services where master_record_id = p_master_record_id and status = 'active';
  if v_service_count = 0 then
    raise exception 'missing_required_service: vendor profile % has no active service', p_master_record_id using errcode = 'check_violation';
  end if;

  select count(*) into v_pending_dupes from app.vendor_duplicate_candidates where source_master_record_id = p_master_record_id and decision = 'pending';
  if v_pending_dupes > 0 then
    raise exception 'unresolved_duplicate_candidates: vendor profile % has % unresolved duplicate candidate(s)', p_master_record_id, v_pending_dupes
      using errcode = 'check_violation';
  end if;

  update app.vendor_profiles
  set lifecycle_status = 'submitted', record_version = record_version + 1, updated_at = now()
  where master_record_id = p_master_record_id and record_version = p_expected_version
  returning * into v_profile;
  if not found then
    raise exception 'stale_version: vendor profile % target row was concurrently modified (expected version %)', p_master_record_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  insert into app.vendor_profile_lifecycle_events (tenant_id, master_record_id, from_status, to_status, actor_auth_user_id, actor_label)
  values (v_profile.tenant_id, p_master_record_id, 'draft', 'submitted', p_actor_auth_user_id, p_actor_label);

  perform app.capture_audit_event(
    v_profile.tenant_id, p_actor_auth_user_id, p_actor_label, 'submit_vendor_profile_for_review',
    'app.vendor_profiles', p_master_record_id, 'success', null, null, jsonb_build_object('lifecycle_status', v_profile.lifecycle_status)
  );

  return v_profile;
end;
$$;

create function app.begin_vendor_profile_review(
  p_master_record_id uuid,
  p_expected_version integer,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.vendor_profiles
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_profile app.vendor_profiles;
begin
  select * into v_profile from app.vendor_profiles where master_record_id = p_master_record_id;
  if not found then
    raise exception 'vendor_profile_not_found: %', p_master_record_id using errcode = 'no_data_found';
  end if;
  if v_profile.record_version <> p_expected_version then
    raise exception 'stale_version: vendor profile % expected version % but found %', p_master_record_id, p_expected_version, v_profile.record_version
      using errcode = 'serialization_failure';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_profile.tenant_id, 'PRC', 'Approve');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:Approve (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_profile.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_profile.lifecycle_status <> 'submitted' then
    raise exception 'invalid_transition: vendor profile % is % and cannot begin review', p_master_record_id, v_profile.lifecycle_status
      using errcode = 'check_violation';
  end if;

  update app.vendor_profiles
  set lifecycle_status = 'under_review', record_version = record_version + 1, updated_at = now()
  where master_record_id = p_master_record_id and record_version = p_expected_version
  returning * into v_profile;
  if not found then
    raise exception 'stale_version: vendor profile % target row was concurrently modified (expected version %)', p_master_record_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  insert into app.vendor_profile_lifecycle_events (tenant_id, master_record_id, from_status, to_status, actor_auth_user_id, actor_label)
  values (v_profile.tenant_id, p_master_record_id, 'submitted', 'under_review', p_actor_auth_user_id, p_actor_label);

  perform app.capture_audit_event(
    v_profile.tenant_id, p_actor_auth_user_id, p_actor_label, 'begin_vendor_profile_review',
    'app.vendor_profiles', p_master_record_id, 'success', null, null, '{}'::jsonb
  );

  return v_profile;
end;
$$;

create function app.decide_vendor_profile_review(
  p_master_record_id uuid,
  p_expected_version integer,
  p_decision text,
  p_reason text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.vendor_profiles
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_profile app.vendor_profiles;
  v_new_status text;
  v_from_status text;
  v_action text;
begin
  if p_decision not in ('approve', 'reject') then
    raise exception 'invalid_decision: % is not approve or reject', p_decision using errcode = 'check_violation';
  end if;
  if p_decision = 'reject' and (p_reason is null or length(trim(p_reason)) = 0) then
    raise exception 'reason_required: a non-empty reason is required to reject a vendor profile' using errcode = 'check_violation';
  end if;

  select * into v_profile from app.vendor_profiles where master_record_id = p_master_record_id;
  if not found then
    raise exception 'vendor_profile_not_found: %', p_master_record_id using errcode = 'no_data_found';
  end if;
  if v_profile.record_version <> p_expected_version then
    raise exception 'stale_version: vendor profile % expected version % but found %', p_master_record_id, p_expected_version, v_profile.record_version
      using errcode = 'serialization_failure';
  end if;

  v_action := case p_decision when 'approve' then 'Approve' else 'Reject' end;
  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_profile.tenant_id, 'PRC', v_action);
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:% (%) for tenant %', p_actor_auth_user_id, v_action, v_decision.reason, v_profile.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_profile.lifecycle_status not in ('submitted', 'under_review') then
    raise exception 'invalid_transition: vendor profile % is % and cannot be decided', p_master_record_id, v_profile.lifecycle_status
      using errcode = 'check_violation';
  end if;

  v_new_status := case p_decision when 'approve' then 'approved' else 'draft' end;
  -- Capture the row's REAL prior status before the UPDATE overwrites v_profile --
  -- begin_vendor_profile_review is optional (design note 5), so a decision can
  -- legitimately be made directly from 'submitted', skipping 'under_review'. A
  -- hardcoded 'under_review' literal here would corrupt the append-only audit
  -- timeline the vendor detail UI reads directly (found in adversarial review).
  v_from_status := v_profile.lifecycle_status;

  update app.vendor_profiles
  set lifecycle_status = v_new_status,
      revision_reason = case when p_decision = 'reject' then p_reason else revision_reason end,
      record_version = record_version + 1,
      updated_at = now()
  where master_record_id = p_master_record_id and record_version = p_expected_version
  returning * into v_profile;
  if not found then
    raise exception 'stale_version: vendor profile % target row was concurrently modified (expected version %)', p_master_record_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  insert into app.vendor_profile_lifecycle_events (tenant_id, master_record_id, from_status, to_status, reason, actor_auth_user_id, actor_label)
  values (v_profile.tenant_id, p_master_record_id, v_from_status, v_new_status, p_reason, p_actor_auth_user_id, p_actor_label);

  perform app.capture_audit_event(
    v_profile.tenant_id, p_actor_auth_user_id, p_actor_label, 'decide_vendor_profile_review',
    'app.vendor_profiles', p_master_record_id, 'success', p_reason, null, jsonb_build_object('decision', p_decision, 'lifecycle_status', v_new_status)
  );

  return v_profile;
end;
$$;

comment on function app.decide_vendor_profile_review is 'PRC-251: approve (-> approved, PRC:Approve) or reject (-> draft with revision_reason set, PRC:Reject, reason mandatory) -- reachable from submitted or under_review. Rejection is modeled as a transition back to draft, never a separate terminal status, per docs/build-log/phase-06/00_PROCUREMENT_VENDOR_WBS.md §9.';

create function app.activate_vendor_profile(
  p_master_record_id uuid,
  p_expected_version integer,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.vendor_profiles
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_profile app.vendor_profiles;
begin
  select * into v_profile from app.vendor_profiles where master_record_id = p_master_record_id;
  if not found then
    raise exception 'vendor_profile_not_found: %', p_master_record_id using errcode = 'no_data_found';
  end if;
  if v_profile.record_version <> p_expected_version then
    raise exception 'stale_version: vendor profile % expected version % but found %', p_master_record_id, p_expected_version, v_profile.record_version
      using errcode = 'serialization_failure';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_profile.tenant_id, 'PRC', 'Approve');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:Approve (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_profile.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_profile.lifecycle_status <> 'approved' then
    raise exception 'invalid_transition: vendor profile % is % and cannot be activated', p_master_record_id, v_profile.lifecycle_status
      using errcode = 'check_violation';
  end if;

  update app.vendor_profiles
  set lifecycle_status = 'active', record_version = record_version + 1, updated_at = now()
  where master_record_id = p_master_record_id and record_version = p_expected_version
  returning * into v_profile;
  if not found then
    raise exception 'stale_version: vendor profile % target row was concurrently modified (expected version %)', p_master_record_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  insert into app.vendor_profile_lifecycle_events (tenant_id, master_record_id, from_status, to_status, actor_auth_user_id, actor_label)
  values (v_profile.tenant_id, p_master_record_id, 'approved', 'active', p_actor_auth_user_id, p_actor_label);

  perform app.capture_audit_event(
    v_profile.tenant_id, p_actor_auth_user_id, p_actor_label, 'activate_vendor_profile',
    'app.vendor_profiles', p_master_record_id, 'success', null, null, '{}'::jsonb
  );

  return v_profile;
end;
$$;

create function app.suspend_vendor_profile(
  p_master_record_id uuid,
  p_expected_version integer,
  p_reason text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.vendor_profiles
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_profile app.vendor_profiles;
begin
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'reason_required: a non-empty reason is required to suspend a vendor profile' using errcode = 'check_violation';
  end if;

  select * into v_profile from app.vendor_profiles where master_record_id = p_master_record_id;
  if not found then
    raise exception 'vendor_profile_not_found: %', p_master_record_id using errcode = 'no_data_found';
  end if;
  if v_profile.record_version <> p_expected_version then
    raise exception 'stale_version: vendor profile % expected version % but found %', p_master_record_id, p_expected_version, v_profile.record_version
      using errcode = 'serialization_failure';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_profile.tenant_id, 'PRC', 'Override');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:Override (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_profile.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_profile.lifecycle_status <> 'active' then
    raise exception 'invalid_transition: vendor profile % is % and cannot be suspended', p_master_record_id, v_profile.lifecycle_status
      using errcode = 'check_violation';
  end if;

  update app.vendor_profiles
  set lifecycle_status = 'suspended', suspend_reason = p_reason, record_version = record_version + 1, updated_at = now()
  where master_record_id = p_master_record_id and record_version = p_expected_version
  returning * into v_profile;
  if not found then
    raise exception 'stale_version: vendor profile % target row was concurrently modified (expected version %)', p_master_record_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  insert into app.vendor_profile_lifecycle_events (tenant_id, master_record_id, from_status, to_status, reason, actor_auth_user_id, actor_label)
  values (v_profile.tenant_id, p_master_record_id, 'active', 'suspended', p_reason, p_actor_auth_user_id, p_actor_label);

  perform app.capture_audit_event(
    v_profile.tenant_id, p_actor_auth_user_id, p_actor_label, 'suspend_vendor_profile',
    'app.vendor_profiles', p_master_record_id, 'success', p_reason, null, '{}'::jsonb
  );

  return v_profile;
end;
$$;

create function app.reactivate_vendor_profile(
  p_master_record_id uuid,
  p_expected_version integer,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.vendor_profiles
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_profile app.vendor_profiles;
begin
  select * into v_profile from app.vendor_profiles where master_record_id = p_master_record_id;
  if not found then
    raise exception 'vendor_profile_not_found: %', p_master_record_id using errcode = 'no_data_found';
  end if;
  if v_profile.record_version <> p_expected_version then
    raise exception 'stale_version: vendor profile % expected version % but found %', p_master_record_id, p_expected_version, v_profile.record_version
      using errcode = 'serialization_failure';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_profile.tenant_id, 'PRC', 'Override');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:Override (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_profile.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_profile.lifecycle_status <> 'suspended' then
    raise exception 'invalid_transition: vendor profile % is % and cannot be reactivated', p_master_record_id, v_profile.lifecycle_status
      using errcode = 'check_violation';
  end if;

  update app.vendor_profiles
  set lifecycle_status = 'active', suspend_reason = null, record_version = record_version + 1, updated_at = now()
  where master_record_id = p_master_record_id and record_version = p_expected_version
  returning * into v_profile;
  if not found then
    raise exception 'stale_version: vendor profile % target row was concurrently modified (expected version %)', p_master_record_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  insert into app.vendor_profile_lifecycle_events (tenant_id, master_record_id, from_status, to_status, actor_auth_user_id, actor_label)
  values (v_profile.tenant_id, p_master_record_id, 'suspended', 'active', p_actor_auth_user_id, p_actor_label);

  perform app.capture_audit_event(
    v_profile.tenant_id, p_actor_auth_user_id, p_actor_label, 'reactivate_vendor_profile',
    'app.vendor_profiles', p_master_record_id, 'success', null, null, '{}'::jsonb
  );

  return v_profile;
end;
$$;

create function app.archive_vendor_profile(
  p_master_record_id uuid,
  p_expected_version integer,
  p_reason text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.vendor_profiles
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_profile app.vendor_profiles;
begin
  select * into v_profile from app.vendor_profiles where master_record_id = p_master_record_id;
  if not found then
    raise exception 'vendor_profile_not_found: %', p_master_record_id using errcode = 'no_data_found';
  end if;
  if v_profile.record_version <> p_expected_version then
    raise exception 'stale_version: vendor profile % expected version % but found %', p_master_record_id, p_expected_version, v_profile.record_version
      using errcode = 'serialization_failure';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_profile.tenant_id, 'PRC', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_profile.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_profile.lifecycle_status <> 'suspended' then
    raise exception 'invalid_transition: vendor profile % is % and cannot be archived (must be suspended first)', p_master_record_id, v_profile.lifecycle_status
      using errcode = 'check_violation';
  end if;

  update app.vendor_profiles
  set lifecycle_status = 'archived', record_version = record_version + 1, updated_at = now()
  where master_record_id = p_master_record_id and record_version = p_expected_version
  returning * into v_profile;
  if not found then
    raise exception 'stale_version: vendor profile % target row was concurrently modified (expected version %)', p_master_record_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  insert into app.vendor_profile_lifecycle_events (tenant_id, master_record_id, from_status, to_status, reason, actor_auth_user_id, actor_label)
  values (v_profile.tenant_id, p_master_record_id, 'suspended', 'archived', p_reason, p_actor_auth_user_id, p_actor_label);

  perform app.capture_audit_event(
    v_profile.tenant_id, p_actor_auth_user_id, p_actor_label, 'archive_vendor_profile',
    'app.vendor_profiles', p_master_record_id, 'success', p_reason, null, '{}'::jsonb
  );

  return v_profile;
end;
$$;

comment on function app.archive_vendor_profile is 'PRC-251: reachable only from suspended, per docs/build-log/phase-06/00_PROCUREMENT_VENDOR_WBS.md §9''s literal arrow chain (active <-> suspended -> archived) -- an active vendor must be suspended (with its own required reason) before it can be archived.';

create function app.blacklist_vendor_profile(
  p_master_record_id uuid,
  p_expected_version integer,
  p_reason text,
  p_evidence_ref text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.vendor_profiles
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_profile app.vendor_profiles;
  v_from_status text;
begin
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'reason_required: a non-empty reason is required to blacklist a vendor profile' using errcode = 'check_violation';
  end if;
  if p_evidence_ref is null or length(trim(p_evidence_ref)) = 0 then
    raise exception 'evidence_required: evidence is required to blacklist a vendor profile' using errcode = 'check_violation';
  end if;

  select * into v_profile from app.vendor_profiles where master_record_id = p_master_record_id;
  if not found then
    raise exception 'vendor_profile_not_found: %', p_master_record_id using errcode = 'no_data_found';
  end if;
  if v_profile.record_version <> p_expected_version then
    raise exception 'stale_version: vendor profile % expected version % but found %', p_master_record_id, p_expected_version, v_profile.record_version
      using errcode = 'serialization_failure';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_profile.tenant_id, 'PRC', 'Override');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:Override (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_profile.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_profile.lifecycle_status not in ('active', 'suspended') then
    raise exception 'invalid_transition: vendor profile % is % and cannot be blacklisted', p_master_record_id, v_profile.lifecycle_status
      using errcode = 'check_violation';
  end if;
  v_from_status := v_profile.lifecycle_status;

  update app.vendor_profiles
  set lifecycle_status = 'blacklisted', blacklist_reason = p_reason, blacklist_evidence_ref = p_evidence_ref,
      record_version = record_version + 1, updated_at = now()
  where master_record_id = p_master_record_id and record_version = p_expected_version
  returning * into v_profile;
  if not found then
    raise exception 'stale_version: vendor profile % target row was concurrently modified (expected version %)', p_master_record_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  insert into app.vendor_profile_lifecycle_events (tenant_id, master_record_id, from_status, to_status, reason, evidence_ref, actor_auth_user_id, actor_label)
  values (v_profile.tenant_id, p_master_record_id, v_from_status, 'blacklisted', p_reason, p_evidence_ref, p_actor_auth_user_id, p_actor_label);

  perform app.capture_audit_event(
    v_profile.tenant_id, p_actor_auth_user_id, p_actor_label, 'blacklist_vendor_profile',
    'app.vendor_profiles', p_master_record_id, 'success', p_reason, null, jsonb_build_object('evidence_ref', p_evidence_ref)
  );

  return v_profile;
end;
$$;

-- ===========================================================================
-- 11. Child-record CRUD -- draft-only (design default per Prompt 251's own
--     "draft-only unless the prompt's own business rules say otherwise" guidance;
--     no business rule in the source package names a post-draft child-edit
--     allowance, so this migration does not invent one).
-- ===========================================================================

create function app.assert_vendor_profile_editable(p_master_record_id uuid, p_actor_auth_user_id uuid, out v_profile app.vendor_profiles)
language plpgsql
as $$
declare
  v_decision app.rbac_decision;
begin
  -- `for update`: closes a real TOCTOU race found in adversarial review -- without a
  -- row lock here, a lifecycle transition (e.g. submit_vendor_profile_for_review,
  -- whose own UPDATE only takes the row lock at UPDATE time) could commit
  -- draft->submitted concurrently with a child-CRUD call that already read
  -- lifecycle_status='draft' a moment earlier, letting a contact/address/service/
  -- coverage row be added after the profile left draft. Every lifecycle RPC's
  -- terminal UPDATE acquires this same row's lock, so contending on it here fully
  -- serializes the two paths: whichever transaction locks first wins, and the loser
  -- re-reads the post-commit status, matching a single sequential run.
  select * into v_profile from app.vendor_profiles where master_record_id = p_master_record_id for update;
  if not found then
    raise exception 'vendor_profile_not_found: %', p_master_record_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_profile.tenant_id, 'PRC', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_profile.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_profile.lifecycle_status <> 'draft' then
    raise exception 'vendor_profile_not_draft: vendor profile % is % -- child records may only be edited while draft', p_master_record_id, v_profile.lifecycle_status
      using errcode = 'check_violation';
  end if;
end;
$$;

comment on function app.assert_vendor_profile_editable is 'PRC-251: shared authority+state precondition for every child-record CRUD RPC below -- PRC:Edit plus lifecycle_status=draft, under a `for update` row lock so it serializes against every lifecycle-transition RPC''s own terminal UPDATE on the same row (closes a real concurrent-edit-after-submit race found in adversarial review). Not itself callable by anyone but the SECURITY DEFINER functions that call it (SECURITY INVOKER, executes with the definer caller''s already-elevated privilege).';

create function app.add_vendor_contact(
  p_master_record_id uuid, p_name text, p_title text, p_email text, p_phone text, p_is_primary boolean,
  p_actor_auth_user_id uuid, p_actor_label text
)
returns app.vendor_contacts
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_profile app.vendor_profiles;
  v_contact app.vendor_contacts;
begin
  v_profile := app.assert_vendor_profile_editable(p_master_record_id, p_actor_auth_user_id);

  if p_name is null or length(trim(p_name)) = 0 then
    raise exception 'invalid_contact: name must not be empty' using errcode = 'check_violation';
  end if;

  if coalesce(p_is_primary, false) then
    update app.vendor_contacts set is_primary = false where master_record_id = p_master_record_id and status = 'active' and is_primary;
  end if;

  insert into app.vendor_contacts (tenant_id, master_record_id, name, title, email, phone, is_primary, created_by)
  values (v_profile.tenant_id, p_master_record_id, p_name, p_title, p_email, p_phone, coalesce(p_is_primary, false), p_actor_label)
  returning * into v_contact;

  perform app.capture_audit_event(
    v_profile.tenant_id, p_actor_auth_user_id, p_actor_label, 'add_vendor_contact',
    'app.vendor_contacts', v_contact.id, 'success', null, null, to_jsonb(v_contact)
  );

  return v_contact;
end;
$$;

create function app.update_vendor_contact(
  p_contact_id uuid, p_expected_version integer, p_name text, p_title text, p_email text, p_phone text, p_is_primary boolean,
  p_actor_auth_user_id uuid, p_actor_label text
)
returns app.vendor_contacts
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_contact app.vendor_contacts;
  v_profile app.vendor_profiles;
begin
  select * into v_contact from app.vendor_contacts where id = p_contact_id and status = 'active';
  if not found then
    raise exception 'contact_not_found: %', p_contact_id using errcode = 'no_data_found';
  end if;
  if v_contact.record_version <> p_expected_version then
    raise exception 'stale_version: vendor contact % expected version % but found %', p_contact_id, p_expected_version, v_contact.record_version
      using errcode = 'serialization_failure';
  end if;

  v_profile := app.assert_vendor_profile_editable(v_contact.master_record_id, p_actor_auth_user_id);

  if p_name is null or length(trim(p_name)) = 0 then
    raise exception 'invalid_contact: name must not be empty' using errcode = 'check_violation';
  end if;

  if coalesce(p_is_primary, false) then
    update app.vendor_contacts set is_primary = false where master_record_id = v_contact.master_record_id and status = 'active' and is_primary and id <> p_contact_id;
  end if;

  update app.vendor_contacts
  set name = p_name, title = p_title, email = p_email, phone = p_phone, is_primary = coalesce(p_is_primary, false)
  where id = p_contact_id and record_version = p_expected_version
  returning * into v_contact;
  if not found then
    raise exception 'stale_version: vendor contact % target row was concurrently modified (expected version %)', p_contact_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_profile.tenant_id, p_actor_auth_user_id, p_actor_label, 'update_vendor_contact',
    'app.vendor_contacts', v_contact.id, 'success', null, null, to_jsonb(v_contact)
  );

  return v_contact;
end;
$$;

create function app.remove_vendor_contact(p_contact_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text)
returns app.vendor_contacts
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_contact app.vendor_contacts;
  v_profile app.vendor_profiles;
begin
  select * into v_contact from app.vendor_contacts where id = p_contact_id and status = 'active';
  if not found then
    raise exception 'contact_not_found: %', p_contact_id using errcode = 'no_data_found';
  end if;
  if v_contact.record_version <> p_expected_version then
    raise exception 'stale_version: vendor contact % expected version % but found %', p_contact_id, p_expected_version, v_contact.record_version
      using errcode = 'serialization_failure';
  end if;

  v_profile := app.assert_vendor_profile_editable(v_contact.master_record_id, p_actor_auth_user_id);

  update app.vendor_contacts
  set status = 'removed', is_primary = false
  where id = p_contact_id and record_version = p_expected_version
  returning * into v_contact;
  if not found then
    raise exception 'stale_version: vendor contact % target row was concurrently modified (expected version %)', p_contact_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_profile.tenant_id, p_actor_auth_user_id, p_actor_label, 'remove_vendor_contact',
    'app.vendor_contacts', v_contact.id, 'success', null, null, '{}'::jsonb
  );

  return v_contact;
end;
$$;

create function app.add_vendor_address(
  p_master_record_id uuid, p_address_type text, p_street text, p_city text, p_province text, p_postal_code text, p_country text,
  p_actor_auth_user_id uuid, p_actor_label text
)
returns app.vendor_addresses
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_profile app.vendor_profiles;
  v_address app.vendor_addresses;
begin
  v_profile := app.assert_vendor_profile_editable(p_master_record_id, p_actor_auth_user_id);

  if p_address_type not in ('legal', 'billing', 'operational') then
    raise exception 'invalid_address_type: %', p_address_type using errcode = 'check_violation';
  end if;
  if p_street is null or length(trim(p_street)) = 0 or p_city is null or length(trim(p_city)) = 0 or p_country is null or length(trim(p_country)) = 0 then
    raise exception 'invalid_address: street, city and country are required' using errcode = 'check_violation';
  end if;

  insert into app.vendor_addresses (tenant_id, master_record_id, address_type, street, city, province, postal_code, country, created_by)
  values (v_profile.tenant_id, p_master_record_id, p_address_type, p_street, p_city, p_province, p_postal_code, p_country, p_actor_label)
  returning * into v_address;

  perform app.capture_audit_event(
    v_profile.tenant_id, p_actor_auth_user_id, p_actor_label, 'add_vendor_address',
    'app.vendor_addresses', v_address.id, 'success', null, null, to_jsonb(v_address)
  );

  return v_address;
end;
$$;

create function app.update_vendor_address(
  p_address_id uuid, p_expected_version integer, p_address_type text, p_street text, p_city text, p_province text, p_postal_code text, p_country text,
  p_actor_auth_user_id uuid, p_actor_label text
)
returns app.vendor_addresses
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_address app.vendor_addresses;
  v_profile app.vendor_profiles;
begin
  select * into v_address from app.vendor_addresses where id = p_address_id and status = 'active';
  if not found then
    raise exception 'address_not_found: %', p_address_id using errcode = 'no_data_found';
  end if;
  if v_address.record_version <> p_expected_version then
    raise exception 'stale_version: vendor address % expected version % but found %', p_address_id, p_expected_version, v_address.record_version
      using errcode = 'serialization_failure';
  end if;

  v_profile := app.assert_vendor_profile_editable(v_address.master_record_id, p_actor_auth_user_id);

  if p_address_type not in ('legal', 'billing', 'operational') then
    raise exception 'invalid_address_type: %', p_address_type using errcode = 'check_violation';
  end if;
  if p_street is null or length(trim(p_street)) = 0 or p_city is null or length(trim(p_city)) = 0 or p_country is null or length(trim(p_country)) = 0 then
    raise exception 'invalid_address: street, city and country are required' using errcode = 'check_violation';
  end if;

  update app.vendor_addresses
  set address_type = p_address_type, street = p_street, city = p_city, province = p_province, postal_code = p_postal_code, country = p_country
  where id = p_address_id and record_version = p_expected_version
  returning * into v_address;
  if not found then
    raise exception 'stale_version: vendor address % target row was concurrently modified (expected version %)', p_address_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_profile.tenant_id, p_actor_auth_user_id, p_actor_label, 'update_vendor_address',
    'app.vendor_addresses', v_address.id, 'success', null, null, to_jsonb(v_address)
  );

  return v_address;
end;
$$;

create function app.remove_vendor_address(p_address_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text)
returns app.vendor_addresses
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_address app.vendor_addresses;
  v_profile app.vendor_profiles;
begin
  select * into v_address from app.vendor_addresses where id = p_address_id and status = 'active';
  if not found then
    raise exception 'address_not_found: %', p_address_id using errcode = 'no_data_found';
  end if;
  if v_address.record_version <> p_expected_version then
    raise exception 'stale_version: vendor address % expected version % but found %', p_address_id, p_expected_version, v_address.record_version
      using errcode = 'serialization_failure';
  end if;

  v_profile := app.assert_vendor_profile_editable(v_address.master_record_id, p_actor_auth_user_id);

  update app.vendor_addresses
  set status = 'removed'
  where id = p_address_id and record_version = p_expected_version
  returning * into v_address;
  if not found then
    raise exception 'stale_version: vendor address % target row was concurrently modified (expected version %)', p_address_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_profile.tenant_id, p_actor_auth_user_id, p_actor_label, 'remove_vendor_address',
    'app.vendor_addresses', v_address.id, 'success', null, null, '{}'::jsonb
  );

  return v_address;
end;
$$;

create function app.add_vendor_service(p_master_record_id uuid, p_service_type text, p_actor_auth_user_id uuid, p_actor_label text)
returns app.vendor_services
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_profile app.vendor_profiles;
  v_service app.vendor_services;
begin
  v_profile := app.assert_vendor_profile_editable(p_master_record_id, p_actor_auth_user_id);

  if p_service_type is null or length(trim(p_service_type)) = 0 then
    raise exception 'invalid_service: service_type must not be empty' using errcode = 'check_violation';
  end if;

  insert into app.vendor_services (tenant_id, master_record_id, service_type, created_by)
  values (v_profile.tenant_id, p_master_record_id, p_service_type, p_actor_label)
  returning * into v_service;

  perform app.capture_audit_event(
    v_profile.tenant_id, p_actor_auth_user_id, p_actor_label, 'add_vendor_service',
    'app.vendor_services', v_service.id, 'success', null, null, to_jsonb(v_service)
  );

  return v_service;
exception
  when unique_violation then
    raise exception 'duplicate_service: vendor profile % already offers service %', p_master_record_id, p_service_type using errcode = 'unique_violation';
end;
$$;

create function app.update_vendor_service(p_service_id uuid, p_expected_version integer, p_service_type text, p_actor_auth_user_id uuid, p_actor_label text)
returns app.vendor_services
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_service app.vendor_services;
  v_profile app.vendor_profiles;
begin
  select * into v_service from app.vendor_services where id = p_service_id and status = 'active';
  if not found then
    raise exception 'service_not_found: %', p_service_id using errcode = 'no_data_found';
  end if;
  if v_service.record_version <> p_expected_version then
    raise exception 'stale_version: vendor service % expected version % but found %', p_service_id, p_expected_version, v_service.record_version
      using errcode = 'serialization_failure';
  end if;

  v_profile := app.assert_vendor_profile_editable(v_service.master_record_id, p_actor_auth_user_id);

  if p_service_type is null or length(trim(p_service_type)) = 0 then
    raise exception 'invalid_service: service_type must not be empty' using errcode = 'check_violation';
  end if;

  update app.vendor_services
  set service_type = p_service_type
  where id = p_service_id and record_version = p_expected_version
  returning * into v_service;
  if not found then
    raise exception 'stale_version: vendor service % target row was concurrently modified (expected version %)', p_service_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_profile.tenant_id, p_actor_auth_user_id, p_actor_label, 'update_vendor_service',
    'app.vendor_services', v_service.id, 'success', null, null, to_jsonb(v_service)
  );

  return v_service;
exception
  when unique_violation then
    raise exception 'duplicate_service: vendor profile already offers service %', p_service_type using errcode = 'unique_violation';
end;
$$;

create function app.remove_vendor_service(p_service_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text)
returns app.vendor_services
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_service app.vendor_services;
  v_profile app.vendor_profiles;
begin
  select * into v_service from app.vendor_services where id = p_service_id and status = 'active';
  if not found then
    raise exception 'service_not_found: %', p_service_id using errcode = 'no_data_found';
  end if;
  if v_service.record_version <> p_expected_version then
    raise exception 'stale_version: vendor service % expected version % but found %', p_service_id, p_expected_version, v_service.record_version
      using errcode = 'serialization_failure';
  end if;

  v_profile := app.assert_vendor_profile_editable(v_service.master_record_id, p_actor_auth_user_id);

  update app.vendor_services
  set status = 'removed'
  where id = p_service_id and record_version = p_expected_version
  returning * into v_service;
  if not found then
    raise exception 'stale_version: vendor service % target row was concurrently modified (expected version %)', p_service_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_profile.tenant_id, p_actor_auth_user_id, p_actor_label, 'remove_vendor_service',
    'app.vendor_services', v_service.id, 'success', null, null, '{}'::jsonb
  );

  return v_service;
end;
$$;

create function app.add_vendor_coverage(p_master_record_id uuid, p_origin_lane text, p_destination_lane text, p_actor_auth_user_id uuid, p_actor_label text)
returns app.vendor_coverage
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_profile app.vendor_profiles;
  v_coverage app.vendor_coverage;
begin
  v_profile := app.assert_vendor_profile_editable(p_master_record_id, p_actor_auth_user_id);

  if p_origin_lane is null or length(trim(p_origin_lane)) = 0 then
    raise exception 'invalid_coverage: origin_lane must not be empty' using errcode = 'check_violation';
  end if;

  insert into app.vendor_coverage (tenant_id, master_record_id, origin_lane, destination_lane, created_by)
  values (v_profile.tenant_id, p_master_record_id, p_origin_lane, p_destination_lane, p_actor_label)
  returning * into v_coverage;

  perform app.capture_audit_event(
    v_profile.tenant_id, p_actor_auth_user_id, p_actor_label, 'add_vendor_coverage',
    'app.vendor_coverage', v_coverage.id, 'success', null, null, to_jsonb(v_coverage)
  );

  return v_coverage;
end;
$$;

create function app.update_vendor_coverage(p_coverage_id uuid, p_expected_version integer, p_origin_lane text, p_destination_lane text, p_actor_auth_user_id uuid, p_actor_label text)
returns app.vendor_coverage
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_coverage app.vendor_coverage;
  v_profile app.vendor_profiles;
begin
  select * into v_coverage from app.vendor_coverage where id = p_coverage_id and status = 'active';
  if not found then
    raise exception 'coverage_not_found: %', p_coverage_id using errcode = 'no_data_found';
  end if;
  if v_coverage.record_version <> p_expected_version then
    raise exception 'stale_version: vendor coverage % expected version % but found %', p_coverage_id, p_expected_version, v_coverage.record_version
      using errcode = 'serialization_failure';
  end if;

  v_profile := app.assert_vendor_profile_editable(v_coverage.master_record_id, p_actor_auth_user_id);

  if p_origin_lane is null or length(trim(p_origin_lane)) = 0 then
    raise exception 'invalid_coverage: origin_lane must not be empty' using errcode = 'check_violation';
  end if;

  update app.vendor_coverage
  set origin_lane = p_origin_lane, destination_lane = p_destination_lane
  where id = p_coverage_id and record_version = p_expected_version
  returning * into v_coverage;
  if not found then
    raise exception 'stale_version: vendor coverage % target row was concurrently modified (expected version %)', p_coverage_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_profile.tenant_id, p_actor_auth_user_id, p_actor_label, 'update_vendor_coverage',
    'app.vendor_coverage', v_coverage.id, 'success', null, null, to_jsonb(v_coverage)
  );

  return v_coverage;
end;
$$;

create function app.remove_vendor_coverage(p_coverage_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text)
returns app.vendor_coverage
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_coverage app.vendor_coverage;
  v_profile app.vendor_profiles;
begin
  select * into v_coverage from app.vendor_coverage where id = p_coverage_id and status = 'active';
  if not found then
    raise exception 'coverage_not_found: %', p_coverage_id using errcode = 'no_data_found';
  end if;
  if v_coverage.record_version <> p_expected_version then
    raise exception 'stale_version: vendor coverage % expected version % but found %', p_coverage_id, p_expected_version, v_coverage.record_version
      using errcode = 'serialization_failure';
  end if;

  v_profile := app.assert_vendor_profile_editable(v_coverage.master_record_id, p_actor_auth_user_id);

  update app.vendor_coverage
  set status = 'removed'
  where id = p_coverage_id and record_version = p_expected_version
  returning * into v_coverage;
  if not found then
    raise exception 'stale_version: vendor coverage % target row was concurrently modified (expected version %)', p_coverage_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_profile.tenant_id, p_actor_auth_user_id, p_actor_label, 'remove_vendor_coverage',
    'app.vendor_coverage', v_coverage.id, 'success', null, null, '{}'::jsonb
  );

  return v_coverage;
end;
$$;

-- ===========================================================================
-- 12. Duplicate review RPCs -- never auto-merge (design note 7).
-- ===========================================================================

create function app.flag_vendor_duplicate_candidate(
  p_source_master_record_id uuid, p_candidate_master_record_id uuid, p_similarity_basis text, p_similarity_score numeric,
  p_actor_auth_user_id uuid, p_actor_label text
)
returns app.vendor_duplicate_candidates
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_source app.vendor_profiles;
  v_candidate app.vendor_duplicate_candidates;
begin
  select * into v_source from app.vendor_profiles where master_record_id = p_source_master_record_id;
  if not found then
    raise exception 'vendor_profile_not_found: %', p_source_master_record_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_source.tenant_id, 'PRC', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_source.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if not exists (select 1 from app.vendor_profiles where master_record_id = p_candidate_master_record_id and tenant_id = v_source.tenant_id) then
    raise exception 'vendor_profile_not_found: candidate %', p_candidate_master_record_id using errcode = 'no_data_found';
  end if;
  if p_source_master_record_id = p_candidate_master_record_id then
    raise exception 'invalid_candidate: a vendor profile cannot be flagged as its own duplicate' using errcode = 'check_violation';
  end if;
  if p_similarity_basis is null or length(trim(p_similarity_basis)) = 0 then
    raise exception 'invalid_candidate: similarity_basis must not be empty' using errcode = 'check_violation';
  end if;

  insert into app.vendor_duplicate_candidates (tenant_id, source_master_record_id, candidate_master_record_id, similarity_basis, similarity_score, created_by)
  values (v_source.tenant_id, p_source_master_record_id, p_candidate_master_record_id, p_similarity_basis, p_similarity_score, p_actor_label)
  returning * into v_candidate;

  perform app.capture_audit_event(
    v_source.tenant_id, p_actor_auth_user_id, p_actor_label, 'flag_vendor_duplicate_candidate',
    'app.vendor_duplicate_candidates', v_candidate.id, 'success', null, null, to_jsonb(v_candidate)
  );

  return v_candidate;
end;
$$;

create function app.decide_vendor_duplicate_candidate(
  p_candidate_id uuid, p_expected_version integer, p_decision text, p_reason text, p_actor_auth_user_id uuid, p_actor_label text
)
returns app.vendor_duplicate_candidates
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_candidate app.vendor_duplicate_candidates;
begin
  if p_decision not in ('linked', 'dismissed') then
    raise exception 'invalid_decision: % is not linked or dismissed', p_decision using errcode = 'check_violation';
  end if;
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'reason_required: a non-empty reason is required to decide a duplicate candidate' using errcode = 'check_violation';
  end if;

  select * into v_candidate from app.vendor_duplicate_candidates where id = p_candidate_id;
  if not found then
    raise exception 'candidate_not_found: %', p_candidate_id using errcode = 'no_data_found';
  end if;
  if v_candidate.record_version <> p_expected_version then
    raise exception 'stale_version: duplicate candidate % expected version % but found %', p_candidate_id, p_expected_version, v_candidate.record_version
      using errcode = 'serialization_failure';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_candidate.tenant_id, 'PRC', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_candidate.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_candidate.decision <> 'pending' then
    raise exception 'invalid_transition: duplicate candidate % is already %', p_candidate_id, v_candidate.decision using errcode = 'check_violation';
  end if;

  update app.vendor_duplicate_candidates
  set decision = p_decision, decided_by = p_actor_label, decided_at = now(), decided_reason = p_reason, record_version = record_version + 1
  where id = p_candidate_id and record_version = p_expected_version
  returning * into v_candidate;
  if not found then
    raise exception 'stale_version: duplicate candidate % target row was concurrently modified (expected version %)', p_candidate_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_candidate.tenant_id, p_actor_auth_user_id, p_actor_label, 'decide_vendor_duplicate_candidate',
    'app.vendor_duplicate_candidates', v_candidate.id, 'success', p_reason, null, jsonb_build_object('decision', p_decision)
  );

  return v_candidate;
end;
$$;

comment on function app.decide_vendor_duplicate_candidate is 'PRC-251: records a reviewer''s linked/dismissed finding only -- NEVER invokes app.merge_master_records or writes to any other table (design note 7''s own binding "never auto-merge" rule).';

-- ===========================================================================
-- 13. Intake token issuance/revocation (staff-facing, authenticated).
-- ===========================================================================

create function app.create_vendor_intake_token(
  p_tenant_id uuid, p_intended_email text, p_validity_days integer, p_idempotency_key text,
  p_actor_auth_user_id uuid, p_actor_label text
)
returns table (token_id uuid, raw_token text, expires_at timestamptz, intended_email text)
language plpgsql
security definer
set search_path = app, public, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_existing app.vendor_intake_tokens;
  v_raw_token text;
  v_token_hash text;
  v_expires_at timestamptz;
  v_token app.vendor_intake_tokens;
begin
  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'PRC', 'Create');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:Create (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if p_intended_email is null or p_intended_email !~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$' then
    raise exception 'invalid_email: % is not a valid email address', p_intended_email using errcode = 'check_violation';
  end if;
  if coalesce(p_validity_days, 0) <= 0 then
    raise exception 'invalid_validity: validity_days must be positive' using errcode = 'check_violation';
  end if;

  if p_idempotency_key is not null then
    select * into v_existing from app.vendor_intake_tokens where tenant_id = p_tenant_id and idempotency_key = p_idempotency_key;
    if found then
      if v_existing.intended_email is distinct from p_intended_email then
        raise exception 'idempotency_key_conflict: idempotency key % was already used for a different intended_email (%)', p_idempotency_key, v_existing.intended_email
          using errcode = 'unique_violation';
      end if;
      return query select v_existing.id, null::text, v_existing.expires_at, v_existing.intended_email;
      return;
    end if;
  end if;

  v_raw_token := encode(gen_random_bytes(32), 'hex');
  v_token_hash := encode(digest(v_raw_token, 'sha256'), 'hex');
  v_expires_at := now() + (p_validity_days || ' days')::interval;

  -- Nested begin/exception unique_violation recovery (mirrors app.create_cycle_count_plan/
  -- app.reserve_vehicle_capacity, 20260730390000) -- see create_vendor_profile_draft's
  -- own identical comment above for the full rationale.
  begin
    insert into app.vendor_intake_tokens (tenant_id, token_hash, intended_email, expires_at, idempotency_key, created_by_auth_user_id, created_by)
    values (p_tenant_id, v_token_hash, p_intended_email, v_expires_at, p_idempotency_key, p_actor_auth_user_id, p_actor_label)
    returning * into v_token;
  exception
    when unique_violation then
      select * into v_existing from app.vendor_intake_tokens where tenant_id = p_tenant_id and idempotency_key = p_idempotency_key;
      if not found then
        raise;
      end if;
      if v_existing.intended_email is distinct from p_intended_email then
        raise exception 'idempotency_key_conflict: idempotency key % was already used for a different intended_email (%)', p_idempotency_key, v_existing.intended_email
          using errcode = 'unique_violation';
      end if;
      return query select v_existing.id, null::text, v_existing.expires_at, v_existing.intended_email;
      return;
  end;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'create_vendor_intake_token',
    'app.vendor_intake_tokens', v_token.id, 'success', null, null, jsonb_build_object('intended_email', p_intended_email, 'expires_at', v_expires_at)
  );

  return query select v_token.id, v_raw_token, v_token.expires_at, v_token.intended_email;
end;
$$;

comment on function app.create_vendor_intake_token is 'PRC-251: raw_token is returned exactly once (this call) and never stored -- only its sha256 digest persists. A replayed idempotency_key returns raw_token=null (the true replay case has already handed the caller the real value once; re-issuing it would defeat the one-time-visible guarantee).';

create function app.revoke_vendor_intake_token(p_token_id uuid, p_reason text, p_actor_auth_user_id uuid, p_actor_label text)
returns app.vendor_intake_tokens
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_token app.vendor_intake_tokens;
  v_prior_version integer;
begin
  select * into v_token from app.vendor_intake_tokens where id = p_token_id;
  if not found then
    raise exception 'token_not_found: %', p_token_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_token.tenant_id, 'PRC', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_token.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'reason_required: a non-empty reason is required to revoke an intake token' using errcode = 'check_violation';
  end if;
  if v_token.status <> 'pending' then
    raise exception 'invalid_transition: intake token % is % and cannot be revoked', p_token_id, v_token.status using errcode = 'check_violation';
  end if;

  -- v_prior_version is captured before the UPDATE: a zero-row RETURNING INTO nulls
  -- out the whole v_token composite (found in adversarial review -- the exact
  -- "fabricated NULL composite" failure mode 20260730520000 itself exists to
  -- eliminate), so referencing v_token.record_version in the error message below
  -- would otherwise always print NULL instead of the real prior version.
  v_prior_version := v_token.record_version;
  update app.vendor_intake_tokens
  set status = 'revoked', revoked_at = now(), revoked_reason = p_reason, record_version = record_version + 1
  where id = p_token_id and record_version = v_prior_version
  returning * into v_token;
  if not found then
    raise exception 'stale_version: intake token % target row was concurrently modified (expected version %)', p_token_id, v_prior_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_token.tenant_id, p_actor_auth_user_id, p_actor_label, 'revoke_vendor_intake_token',
    'app.vendor_intake_tokens', v_token.id, 'success', p_reason, null, '{}'::jsonb
  );

  return v_token;
end;
$$;

-- ===========================================================================
-- 14. Anonymous intake entry points (design note 8) -- no actor, no session.
--     Neither calls app.evaluate_permission: there is no session identity to
--     evaluate. Authorization is the raw token (redemption) or the tenant's own
--     published self-registration flag (self-registration). Both follow app.
--     lookup_public_shipment_tracking's own "never raise once the client_key
--     rate-limit check has passed -- return a status column" shape, so the
--     attempt-log insert always survives to commit.
-- ===========================================================================

create function app.redeem_vendor_intake_token_and_submit(
  p_raw_token text,
  p_client_key text,
  p_legal_name text,
  p_trade_name text,
  p_legal_entity_type text,
  p_business_registration_number text,
  p_vendor_category text,
  p_payment_term_days integer,
  p_contact_name text,
  p_contact_email text,
  p_contact_phone text
)
returns table (submit_status text, master_record_id uuid)
language plpgsql
security definer
set search_path = app, public, pg_temp
as $$
declare
  v_recent_bad_count integer;
  v_hash text;
  v_token app.vendor_intake_tokens;
  v_token_id uuid;
  v_code text;
  v_master app.master_records;
  v_profile app.vendor_profiles;
begin
  if p_client_key is null or length(trim(p_client_key)) = 0 then
    raise exception 'intake_client_key_required: a client_key is required' using errcode = 'check_violation';
  end if;

  select count(*) into v_recent_bad_count
  from app.vendor_intake_attempts
  where client_key = p_client_key and kind = 'token_redeem' and result in ('not_found', 'invalid') and occurred_at > now() - interval '15 minutes';
  if v_recent_bad_count >= 10 then
    insert into app.vendor_intake_attempts (client_key, kind, result) values (p_client_key, 'token_redeem', 'rate_limited');
    return query select 'rate_limited'::text, null::uuid;
    return;
  end if;

  if p_raw_token is null or length(p_raw_token) = 0 or p_legal_name is null or length(trim(p_legal_name)) = 0 then
    insert into app.vendor_intake_attempts (client_key, kind, result) values (p_client_key, 'token_redeem', 'invalid');
    return query select 'invalid'::text, null::uuid;
    return;
  end if;

  v_hash := encode(digest(p_raw_token, 'sha256'), 'hex');
  -- `for update`: closes a real concurrency defect found in adversarial review --
  -- without a row lock, two concurrent redemptions of the SAME single-use token both
  -- read status='pending' and both proceed to create a separate vendor_profiles row,
  -- with the token's own idempotent-replay branch below never engaging for the loser.
  -- Locking here serializes the two calls onto this exact row: whichever call locks
  -- first runs to completion (including the terminal UPDATE below, on the same row),
  -- and the second call blocks until the first commits, then re-reads the
  -- now-'redeemed' status and correctly takes the idempotent-replay branch instead.
  select * into v_token from app.vendor_intake_tokens where token_hash = v_hash for update;

  if not found or v_token.status = 'revoked' or v_token.status = 'expired' or (v_token.status = 'pending' and v_token.expires_at <= now()) then
    insert into app.vendor_intake_attempts (client_key, kind, result) values (p_client_key, 'token_redeem', 'not_found');
    return query select 'not_found'::text, null::uuid;
    return;
  end if;

  if not exists (select 1 from app.tenants where id = v_token.tenant_id and canonical_status = 'active') then
    insert into app.vendor_intake_attempts (client_key, kind, result) values (p_client_key, 'token_redeem', 'not_found');
    return query select 'not_found'::text, null::uuid;
    return;
  end if;

  -- Natural, token-scoped idempotent replay: a token is single-use by construction. A
  -- second redemption attempt with the SAME content returns the same resulting
  -- identity; a second attempt with DIFFERENT content is a conflict, never silently
  -- overwritten (the same target-mismatch discipline every idempotency-keyed RPC in
  -- this repository follows, keyed here by the token itself rather than a separate
  -- p_idempotency_key parameter).
  if v_token.status = 'redeemed' then
    select * into v_profile from app.vendor_profiles vp where vp.master_record_id = v_token.redeemed_master_record_id;
    if found and v_profile.legal_name = p_legal_name then
      insert into app.vendor_intake_attempts (client_key, kind, result) values (p_client_key, 'token_redeem', 'success');
      return query select 'ok'::text, v_token.redeemed_master_record_id;
      return;
    end if;
    insert into app.vendor_intake_attempts (client_key, kind, result) values (p_client_key, 'token_redeem', 'conflict');
    return query select 'conflict'::text, null::uuid;
    return;
  end if;

  insert into app.vendor_intake_attempts (client_key, kind, result) values (p_client_key, 'token_redeem', 'success');

  v_code := app.next_vendor_code(v_token.tenant_id);

  insert into app.master_records (master_type_code, tenant_id, code, name, aliases, attributes, created_by)
  values ('vendor', v_token.tenant_id, v_code, p_legal_name, '[]'::jsonb, '{}'::jsonb, 'vendor_intake_token')
  returning * into v_master;

  insert into app.vendor_profiles (
    master_record_id, tenant_id, legal_name, trade_name, legal_entity_type,
    business_registration_number, vendor_category, payment_term_days, intake_source,
    lifecycle_status, created_by
  )
  values (
    v_master.id, v_token.tenant_id, p_legal_name, p_trade_name, p_legal_entity_type,
    p_business_registration_number, p_vendor_category, p_payment_term_days, 'invited',
    'submitted', 'vendor_intake_token'
  )
  returning * into v_profile;

  if p_contact_name is not null and length(trim(p_contact_name)) > 0 then
    insert into app.vendor_contacts (tenant_id, master_record_id, name, email, phone, is_primary, created_by)
    values (v_token.tenant_id, v_profile.master_record_id, p_contact_name, p_contact_email, p_contact_phone, true, 'vendor_intake_token');
  end if;

  insert into app.vendor_profile_lifecycle_events (tenant_id, master_record_id, from_status, to_status, actor_label)
  values (v_token.tenant_id, v_profile.master_record_id, 'none', 'submitted', 'vendor_intake_token');

  -- `and status = 'pending'` is defense-in-depth on top of the `for update` lock above
  -- (which already makes this unreachable with a non-'pending' row under normal
  -- concurrency) -- the post-UPDATE re-check still follows the mandatory hardened
  -- pattern (20260730520000) so a violation is a loud error, never a silent no-op.
  -- v_token_id is captured before the UPDATE: a zero-row RETURNING INTO would
  -- otherwise null out the whole v_token composite, including the id this error
  -- message needs (the exact "fabricated NULL composite" failure mode 20260730520000
  -- itself was written to eliminate).
  v_token_id := v_token.id;
  update app.vendor_intake_tokens
  set status = 'redeemed', redeemed_at = now(), redeemed_master_record_id = v_profile.master_record_id, record_version = record_version + 1
  where id = v_token_id and status = 'pending'
  returning * into v_token;
  if not found then
    raise exception 'stale_version: intake token % target row was concurrently modified during redemption', v_token_id
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_token.tenant_id, null, 'vendor_intake_token', 'redeem_vendor_intake_token_and_submit',
    'app.vendor_profiles', v_profile.master_record_id, 'success', null, null, jsonb_build_object('intake_source', 'invited')
  );

  return query select 'ok'::text, v_profile.master_record_id;
end;
$$;

comment on function app.redeem_vendor_intake_token_and_submit is 'PRC-251: genuinely anonymous -- no p_actor_auth_user_id parameter exists, no evaluate_permission call, by design. The raw bearer token is the entire authorization surface (verified by hash match, status, and expiry), exactly like app.lookup_public_shipment_tracking (OPS-180). Reads only its own token row and the resulting vendor_profiles row it itself creates -- never any other tenant/vendor data (Prompt 251 §16). Never raises after the rate-limit check passes, so the attempt-log insert always commits.';

create function app.submit_vendor_profile_self_registration(
  p_tenant_id uuid,
  p_client_key text,
  p_legal_name text,
  p_trade_name text,
  p_legal_entity_type text,
  p_business_registration_number text,
  p_vendor_category text,
  p_payment_term_days integer,
  p_contact_name text,
  p_contact_email text,
  p_contact_phone text,
  p_idempotency_key text
)
returns table (submit_status text, master_record_id uuid)
language plpgsql
security definer
set search_path = app, public, pg_temp
as $$
declare
  v_recent_bad_count integer;
  v_existing app.vendor_profiles;
  v_code text;
  v_master app.master_records;
  v_profile app.vendor_profiles;
begin
  if p_client_key is null or length(trim(p_client_key)) = 0 then
    raise exception 'intake_client_key_required: a client_key is required' using errcode = 'check_violation';
  end if;

  select count(*) into v_recent_bad_count
  from app.vendor_intake_attempts
  where client_key = p_client_key and kind = 'self_register' and result in ('not_found', 'invalid', 'disabled') and occurred_at > now() - interval '15 minutes';
  if v_recent_bad_count >= 10 then
    insert into app.vendor_intake_attempts (client_key, kind, result) values (p_client_key, 'self_register', 'rate_limited');
    return query select 'rate_limited'::text, null::uuid;
    return;
  end if;

  if p_tenant_id is null or p_legal_name is null or length(trim(p_legal_name)) = 0 then
    insert into app.vendor_intake_attempts (client_key, kind, result) values (p_client_key, 'self_register', 'invalid');
    return query select 'invalid'::text, null::uuid;
    return;
  end if;

  if not exists (select 1 from app.tenants where id = p_tenant_id and canonical_status = 'active') then
    insert into app.vendor_intake_attempts (client_key, kind, result) values (p_client_key, 'self_register', 'not_found');
    return query select 'not_found'::text, null::uuid;
    return;
  end if;

  if not app.is_vendor_self_registration_enabled(p_tenant_id) then
    insert into app.vendor_intake_attempts (client_key, kind, result) values (p_client_key, 'self_register', 'disabled');
    return query select 'disabled'::text, null::uuid;
    return;
  end if;

  if p_idempotency_key is not null then
    select vp.* into v_existing from app.vendor_profiles vp where vp.tenant_id = p_tenant_id and vp.idempotency_key = p_idempotency_key;
    if found then
      if v_existing.legal_name is distinct from p_legal_name then
        insert into app.vendor_intake_attempts (client_key, kind, result) values (p_client_key, 'self_register', 'conflict');
        return query select 'conflict'::text, null::uuid;
        return;
      end if;
      insert into app.vendor_intake_attempts (client_key, kind, result) values (p_client_key, 'self_register', 'success');
      return query select 'ok'::text, v_existing.master_record_id;
      return;
    end if;
  end if;

  insert into app.vendor_intake_attempts (client_key, kind, result) values (p_client_key, 'self_register', 'success');

  v_code := app.next_vendor_code(p_tenant_id);

  insert into app.master_records (master_type_code, tenant_id, code, name, aliases, attributes, created_by)
  values ('vendor', p_tenant_id, v_code, p_legal_name, '[]'::jsonb, '{}'::jsonb, 'vendor_self_registration')
  returning * into v_master;

  -- Nested begin/exception unique_violation recovery (mirrors app.create_cycle_count_plan/
  -- app.reserve_vehicle_capacity, 20260730390000) -- see create_vendor_profile_draft's
  -- own identical comment above for the full rationale. This anonymous entry point
  -- cannot raise once the rate-limit check passes (design note 8), so a mismatch here
  -- returns 'conflict' via the shared status-column shape rather than raising.
  begin
    insert into app.vendor_profiles (
      master_record_id, tenant_id, legal_name, trade_name, legal_entity_type,
      business_registration_number, vendor_category, payment_term_days, intake_source,
      lifecycle_status, idempotency_key, created_by
    )
    values (
      v_master.id, p_tenant_id, p_legal_name, p_trade_name, p_legal_entity_type,
      p_business_registration_number, p_vendor_category, p_payment_term_days, 'self_registered',
      'submitted', p_idempotency_key, 'vendor_self_registration'
    )
    returning * into v_profile;
  exception
    when unique_violation then
      select vp.* into v_existing from app.vendor_profiles vp where vp.tenant_id = p_tenant_id and vp.idempotency_key = p_idempotency_key;
      if not found then
        raise;
      end if;
      if v_existing.legal_name is distinct from p_legal_name then
        insert into app.vendor_intake_attempts (client_key, kind, result) values (p_client_key, 'self_register', 'conflict');
        return query select 'conflict'::text, null::uuid;
        return;
      end if;
      insert into app.vendor_intake_attempts (client_key, kind, result) values (p_client_key, 'self_register', 'success');
      return query select 'ok'::text, v_existing.master_record_id;
      return;
  end;

  if p_contact_name is not null and length(trim(p_contact_name)) > 0 then
    insert into app.vendor_contacts (tenant_id, master_record_id, name, email, phone, is_primary, created_by)
    values (p_tenant_id, v_profile.master_record_id, p_contact_name, p_contact_email, p_contact_phone, true, 'vendor_self_registration');
  end if;

  insert into app.vendor_profile_lifecycle_events (tenant_id, master_record_id, from_status, to_status, actor_label)
  values (p_tenant_id, v_profile.master_record_id, 'none', 'submitted', 'vendor_self_registration');

  perform app.capture_audit_event(
    p_tenant_id, null, 'vendor_self_registration', 'submit_vendor_profile_self_registration',
    'app.vendor_profiles', v_profile.master_record_id, 'success', null, null, jsonb_build_object('intake_source', 'self_registered')
  );

  return query select 'ok'::text, v_profile.master_record_id;
end;
$$;

comment on function app.submit_vendor_profile_self_registration is 'PRC-251: genuinely anonymous, gated only by app.is_vendor_self_registration_enabled(p_tenant_id) (Configuration Engine, defaults false -- BP-A08). Writes only its own staged submission -- never reads any other tenant/vendor row. Never raises once the rate-limit check passes.';

-- ===========================================================================
-- 15. Read RPCs.
-- ===========================================================================

create function app.get_vendor_profile(p_master_record_id uuid, p_actor_auth_user_id uuid)
returns table (
  master_record_id uuid, tenant_id uuid, vendor_code text, legal_name text, trade_name text,
  legal_entity_type text, business_registration_number text, vendor_category text, payment_term_days integer,
  intake_source text, lifecycle_status text, revision_reason text, suspend_reason text, blacklist_reason text,
  blacklist_evidence_ref text, record_version integer, created_by text, created_at timestamptz, updated_at timestamptz,
  contact_count integer, address_count integer, service_count integer, coverage_count integer, pending_duplicate_count integer
)
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_profile app.vendor_profiles;
begin
  select * into v_profile from app.vendor_profiles vp where vp.master_record_id = p_master_record_id;
  if not found then
    raise exception 'vendor_profile_not_found: %', p_master_record_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_profile.tenant_id, 'PRC', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_profile.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  return query
  select
    v_profile.master_record_id, v_profile.tenant_id, m.code, v_profile.legal_name, v_profile.trade_name,
    v_profile.legal_entity_type, v_profile.business_registration_number, v_profile.vendor_category, v_profile.payment_term_days,
    v_profile.intake_source, v_profile.lifecycle_status, v_profile.revision_reason, v_profile.suspend_reason, v_profile.blacklist_reason,
    v_profile.blacklist_evidence_ref, v_profile.record_version, v_profile.created_by, v_profile.created_at, v_profile.updated_at,
    (select count(*)::integer from app.vendor_contacts c where c.master_record_id = p_master_record_id and c.status = 'active'),
    (select count(*)::integer from app.vendor_addresses a where a.master_record_id = p_master_record_id and a.status = 'active'),
    (select count(*)::integer from app.vendor_services s where s.master_record_id = p_master_record_id and s.status = 'active'),
    (select count(*)::integer from app.vendor_coverage cv where cv.master_record_id = p_master_record_id and cv.status = 'active'),
    (select count(*)::integer from app.vendor_duplicate_candidates d where d.source_master_record_id = p_master_record_id and d.decision = 'pending')
  from app.master_records m
  where m.id = p_master_record_id;
end;
$$;

create function app.list_vendor_profiles(
  p_tenant_id uuid, p_actor_auth_user_id uuid, p_status_filter text default null, p_search text default null,
  p_limit integer default 50, p_after_code text default null
)
returns table (
  master_record_id uuid, vendor_code text, legal_name text, trade_name text, vendor_category text,
  lifecycle_status text, intake_source text, record_version integer, created_at timestamptz, updated_at timestamptz
)
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
begin
  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'PRC', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if p_status_filter is not null and p_status_filter not in ('draft', 'submitted', 'under_review', 'approved', 'active', 'suspended', 'archived', 'blacklisted') then
    raise exception 'invalid_status_filter: %', p_status_filter using errcode = 'check_violation';
  end if;

  return query
  select vp.master_record_id, m.code, vp.legal_name, vp.trade_name, vp.vendor_category, vp.lifecycle_status,
         vp.intake_source, vp.record_version, vp.created_at, vp.updated_at
  from app.vendor_profiles vp
  join app.master_records m on m.id = vp.master_record_id
  where vp.tenant_id = p_tenant_id
    and (p_status_filter is null or vp.lifecycle_status = p_status_filter)
    and (p_search is null or m.code ilike '%' || p_search || '%' or vp.legal_name ilike '%' || p_search || '%' or vp.trade_name ilike '%' || p_search || '%')
    and (p_after_code is null or m.code > p_after_code)
  order by m.code
  limit least(coalesce(p_limit, 50), 200);
end;
$$;

create function app.list_vendor_contacts(p_master_record_id uuid, p_actor_auth_user_id uuid)
returns table (id uuid, master_record_id uuid, name text, title text, email text, phone text, is_primary boolean, record_version integer, created_at timestamptz)
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_profile app.vendor_profiles;
  v_masked boolean;
begin
  select * into v_profile from app.vendor_profiles vp where vp.master_record_id = p_master_record_id;
  if not found then
    raise exception 'vendor_profile_not_found: %', p_master_record_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_profile.tenant_id, 'PRC', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_profile.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  v_masked := not app.has_prc_view_personal_data(v_profile.tenant_id, p_actor_auth_user_id);

  return query
  select c.id, c.master_record_id, c.name, c.title,
         case when v_masked then null else c.email end,
         case when v_masked then null else c.phone end,
         c.is_primary, c.record_version, c.created_at
  from app.vendor_contacts c
  where c.master_record_id = p_master_record_id and c.status = 'active'
  order by c.is_primary desc, c.created_at;
end;
$$;

create function app.list_vendor_addresses(p_master_record_id uuid, p_actor_auth_user_id uuid)
returns setof app.vendor_addresses
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_profile app.vendor_profiles;
begin
  select * into v_profile from app.vendor_profiles where master_record_id = p_master_record_id;
  if not found then
    raise exception 'vendor_profile_not_found: %', p_master_record_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_profile.tenant_id, 'PRC', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_profile.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  return query select * from app.vendor_addresses where master_record_id = p_master_record_id and status = 'active' order by address_type, created_at;
end;
$$;

create function app.list_vendor_services(p_master_record_id uuid, p_actor_auth_user_id uuid)
returns setof app.vendor_services
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_profile app.vendor_profiles;
begin
  select * into v_profile from app.vendor_profiles where master_record_id = p_master_record_id;
  if not found then
    raise exception 'vendor_profile_not_found: %', p_master_record_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_profile.tenant_id, 'PRC', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_profile.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  return query select * from app.vendor_services where master_record_id = p_master_record_id and status = 'active' order by service_type;
end;
$$;

create function app.list_vendor_coverage(p_master_record_id uuid, p_actor_auth_user_id uuid)
returns setof app.vendor_coverage
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_profile app.vendor_profiles;
begin
  select * into v_profile from app.vendor_profiles where master_record_id = p_master_record_id;
  if not found then
    raise exception 'vendor_profile_not_found: %', p_master_record_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_profile.tenant_id, 'PRC', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_profile.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  return query select * from app.vendor_coverage where master_record_id = p_master_record_id and status = 'active' order by origin_lane;
end;
$$;

create function app.list_vendor_duplicate_candidates(p_master_record_id uuid, p_actor_auth_user_id uuid)
returns setof app.vendor_duplicate_candidates
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_profile app.vendor_profiles;
begin
  select * into v_profile from app.vendor_profiles where master_record_id = p_master_record_id;
  if not found then
    raise exception 'vendor_profile_not_found: %', p_master_record_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_profile.tenant_id, 'PRC', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_profile.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  return query select * from app.vendor_duplicate_candidates where source_master_record_id = p_master_record_id order by created_at desc;
end;
$$;

create function app.search_vendor_duplicate_candidates(p_tenant_id uuid, p_legal_name text, p_trade_name text, p_actor_auth_user_id uuid, p_limit integer default 10)
returns table (master_record_id uuid, vendor_code text, legal_name text, trade_name text, similarity_score real)
language plpgsql
security definer
set search_path = app, public, pg_temp
as $$
declare
  v_decision app.rbac_decision;
begin
  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'PRC', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if p_legal_name is null or length(trim(p_legal_name)) = 0 then
    raise exception 'invalid_legal_name: legal_name must not be empty' using errcode = 'check_violation';
  end if;

  return query
  select vp.master_record_id, m.code, vp.legal_name, vp.trade_name,
         greatest(similarity(vp.legal_name, p_legal_name), coalesce(similarity(vp.trade_name, coalesce(p_trade_name, p_legal_name)), 0)) as score
  from app.vendor_profiles vp
  join app.master_records m on m.id = vp.master_record_id
  where vp.tenant_id = p_tenant_id
    and (vp.legal_name % p_legal_name or (p_trade_name is not null and vp.trade_name % p_trade_name))
  order by score desc
  limit least(coalesce(p_limit, 10), 50);
end;
$$;

comment on function app.search_vendor_duplicate_candidates is 'PRC-251: trigram-based (pg_trgm) fuzzy match over app.vendor_profiles.legal_name/trade_name only -- never over app.master_records (out of this capability''s forbidden-files scope, design note 7). No supporting GIN index exists on master_records; matching here uses vendor_profiles'' own GIN trigram indexes.';

create function app.get_vendor_lifecycle_history(p_master_record_id uuid, p_actor_auth_user_id uuid)
returns setof app.vendor_profile_lifecycle_events
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_profile app.vendor_profiles;
begin
  select * into v_profile from app.vendor_profiles where master_record_id = p_master_record_id;
  if not found then
    raise exception 'vendor_profile_not_found: %', p_master_record_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_profile.tenant_id, 'PRC', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_profile.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  return query select * from app.vendor_profile_lifecycle_events where master_record_id = p_master_record_id order by occurred_at;
end;
$$;

-- ===========================================================================
-- 16. RLS -- default-deny form (pattern (3)): tenant membership AND NOT a
--     customer_user-layer principal, OR Supreme Admin. Vendor data is
--     Procurement-internal; a customer_user-layer principal must never read it.
-- ===========================================================================

-- app.vendor_code_counters carries no `authenticated`/`anon` grant (design note 3,
-- ISS-2026-033's own lesson) so this deny-all policy is not independently
-- exploitable today -- it is the same belt-and-suspenders layer
-- app.quotation_number_counters_none (COM-151) applies to its own numbering counter,
-- restored here after adversarial review found this migration had dropped it.
alter table app.vendor_code_counters enable row level security;

create policy vendor_code_counters_none on app.vendor_code_counters
  for select to authenticated
  using (false);

alter table app.vendor_profiles enable row level security;
alter table app.vendor_contacts enable row level security;
alter table app.vendor_addresses enable row level security;
alter table app.vendor_services enable row level security;
alter table app.vendor_coverage enable row level security;
alter table app.vendor_profile_lifecycle_events enable row level security;
alter table app.vendor_duplicate_candidates enable row level security;
alter table app.vendor_intake_tokens enable row level security;

create policy vendor_profiles_select_scoped on app.vendor_profiles
  for select to authenticated
  using ((app.has_active_tenant_membership(tenant_id) and not app.actor_holds_customer_user_layer(tenant_id)) or app.is_supreme_admin());

create policy vendor_contacts_select_scoped on app.vendor_contacts
  for select to authenticated
  using ((app.has_active_tenant_membership(tenant_id) and not app.actor_holds_customer_user_layer(tenant_id)) or app.is_supreme_admin());

create policy vendor_addresses_select_scoped on app.vendor_addresses
  for select to authenticated
  using ((app.has_active_tenant_membership(tenant_id) and not app.actor_holds_customer_user_layer(tenant_id)) or app.is_supreme_admin());

create policy vendor_services_select_scoped on app.vendor_services
  for select to authenticated
  using ((app.has_active_tenant_membership(tenant_id) and not app.actor_holds_customer_user_layer(tenant_id)) or app.is_supreme_admin());

create policy vendor_coverage_select_scoped on app.vendor_coverage
  for select to authenticated
  using ((app.has_active_tenant_membership(tenant_id) and not app.actor_holds_customer_user_layer(tenant_id)) or app.is_supreme_admin());

create policy vendor_profile_lifecycle_events_select_scoped on app.vendor_profile_lifecycle_events
  for select to authenticated
  using ((app.has_active_tenant_membership(tenant_id) and not app.actor_holds_customer_user_layer(tenant_id)) or app.is_supreme_admin());

create policy vendor_duplicate_candidates_select_scoped on app.vendor_duplicate_candidates
  for select to authenticated
  using ((app.has_active_tenant_membership(tenant_id) and not app.actor_holds_customer_user_layer(tenant_id)) or app.is_supreme_admin());

create policy vendor_intake_tokens_select_scoped on app.vendor_intake_tokens
  for select to authenticated
  using ((app.has_active_tenant_membership(tenant_id) and not app.actor_holds_customer_user_layer(tenant_id)) or app.is_supreme_admin());

-- ===========================================================================
-- 17. Grants.
-- ===========================================================================

revoke execute on all functions in schema app from public;

grant select on app.vendor_profiles to authenticated, service_role;
grant insert, update, delete on app.vendor_profiles to service_role;
grant select on app.vendor_contacts to authenticated, service_role;
grant insert, update, delete on app.vendor_contacts to service_role;
grant select on app.vendor_addresses to authenticated, service_role;
grant insert, update, delete on app.vendor_addresses to service_role;
grant select on app.vendor_services to authenticated, service_role;
grant insert, update, delete on app.vendor_services to service_role;
grant select on app.vendor_coverage to authenticated, service_role;
grant insert, update, delete on app.vendor_coverage to service_role;
grant select on app.vendor_profile_lifecycle_events to authenticated, service_role;
grant insert on app.vendor_profile_lifecycle_events to service_role;
grant select on app.vendor_duplicate_candidates to authenticated, service_role;
grant insert, update on app.vendor_duplicate_candidates to service_role;
grant select on app.vendor_intake_tokens to authenticated, service_role;
grant insert, update on app.vendor_intake_tokens to service_role;
grant select, insert on app.vendor_intake_attempts to service_role;
grant select, insert, update on app.vendor_code_counters to service_role;

grant execute on function app.is_vendor_self_registration_enabled(uuid) to authenticated, service_role;
grant execute on function app.resolve_vendor_self_registration_target(text) to service_role;
grant execute on function app.has_prc_view_personal_data(uuid, uuid) to authenticated, service_role;

grant execute on function app.create_vendor_profile_draft(uuid, text, text, text, text, text, integer, text, text, uuid, text) to authenticated, service_role;
grant execute on function app.submit_vendor_profile_for_review(uuid, integer, uuid, text) to authenticated, service_role;
grant execute on function app.begin_vendor_profile_review(uuid, integer, uuid, text) to authenticated, service_role;
grant execute on function app.decide_vendor_profile_review(uuid, integer, text, text, uuid, text) to authenticated, service_role;
grant execute on function app.activate_vendor_profile(uuid, integer, uuid, text) to authenticated, service_role;
grant execute on function app.suspend_vendor_profile(uuid, integer, text, uuid, text) to authenticated, service_role;
grant execute on function app.reactivate_vendor_profile(uuid, integer, uuid, text) to authenticated, service_role;
grant execute on function app.archive_vendor_profile(uuid, integer, text, uuid, text) to authenticated, service_role;
grant execute on function app.blacklist_vendor_profile(uuid, integer, text, text, uuid, text) to authenticated, service_role;

grant execute on function app.add_vendor_contact(uuid, text, text, text, text, boolean, uuid, text) to authenticated, service_role;
grant execute on function app.update_vendor_contact(uuid, integer, text, text, text, text, boolean, uuid, text) to authenticated, service_role;
grant execute on function app.remove_vendor_contact(uuid, integer, uuid, text) to authenticated, service_role;
grant execute on function app.add_vendor_address(uuid, text, text, text, text, text, text, uuid, text) to authenticated, service_role;
grant execute on function app.update_vendor_address(uuid, integer, text, text, text, text, text, text, uuid, text) to authenticated, service_role;
grant execute on function app.remove_vendor_address(uuid, integer, uuid, text) to authenticated, service_role;
grant execute on function app.add_vendor_service(uuid, text, uuid, text) to authenticated, service_role;
grant execute on function app.update_vendor_service(uuid, integer, text, uuid, text) to authenticated, service_role;
grant execute on function app.remove_vendor_service(uuid, integer, uuid, text) to authenticated, service_role;
grant execute on function app.add_vendor_coverage(uuid, text, text, uuid, text) to authenticated, service_role;
grant execute on function app.update_vendor_coverage(uuid, integer, text, text, uuid, text) to authenticated, service_role;
grant execute on function app.remove_vendor_coverage(uuid, integer, uuid, text) to authenticated, service_role;

grant execute on function app.flag_vendor_duplicate_candidate(uuid, uuid, text, numeric, uuid, text) to authenticated, service_role;
grant execute on function app.decide_vendor_duplicate_candidate(uuid, integer, text, text, uuid, text) to authenticated, service_role;

grant execute on function app.create_vendor_intake_token(uuid, text, integer, text, uuid, text) to authenticated, service_role;
grant execute on function app.revoke_vendor_intake_token(uuid, text, uuid, text) to authenticated, service_role;

-- Anonymous entry points -- service_role only (design note 8): the public Next.js
-- route calls these via the service-role Supabase client server-side, never via a
-- browser-side anon client, so no `anon` Postgres grant is added.
grant execute on function app.redeem_vendor_intake_token_and_submit(text, text, text, text, text, text, text, integer, text, text, text) to service_role;
grant execute on function app.submit_vendor_profile_self_registration(uuid, text, text, text, text, text, text, integer, text, text, text, text) to service_role;

grant execute on function app.get_vendor_profile(uuid, uuid) to authenticated, service_role;
grant execute on function app.list_vendor_profiles(uuid, uuid, text, text, integer, text) to authenticated, service_role;
grant execute on function app.list_vendor_contacts(uuid, uuid) to authenticated, service_role;
grant execute on function app.list_vendor_addresses(uuid, uuid) to authenticated, service_role;
grant execute on function app.list_vendor_services(uuid, uuid) to authenticated, service_role;
grant execute on function app.list_vendor_coverage(uuid, uuid) to authenticated, service_role;
grant execute on function app.list_vendor_duplicate_candidates(uuid, uuid) to authenticated, service_role;
grant execute on function app.search_vendor_duplicate_candidates(uuid, text, text, uuid, integer) to authenticated, service_role;
grant execute on function app.get_vendor_lifecycle_history(uuid, uuid) to authenticated, service_role;
