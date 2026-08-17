-- Phase 8 capability CPL-314 (CG-S13-CPL-016, Prompt 314, "Customer Profile").
-- Read docs/adr/ADR-0024-phase8-customer-portal-access-and-transport-pattern.md,
-- supabase/migrations/20260801010000_create_customer_portal_account_scope.sql
-- (CPL-300), supabase/migrations/20260801030000_create_customer_portal_quote_
-- requests.sql (CPL-302, the shape this migration mirrors -- the sole prior
-- Phase-8-internal precedent for a "portal-owned request record, staff decides,
-- a single staff-gated RPC applies the change to the real canonical record")
-- and supabase/migrations/20260724290000_create_commercial_customer_account_
-- conversion.sql (COM-155/ADR-0018, app.accounts, the one canonical customer/
-- account/site master this migration's own change-request path targets) in
-- full before writing any code here.
--
-- ===========================================================================
-- Design decisions
-- ===========================================================================
--
-- 1. **A new portal-owned change-REQUEST table, never a direct write into
--    app.accounts from a customer-initiated RPC** (ADR-0024 Part B, mirrors
--    CPL-302's app.customer_portal_quote_requests exactly). app.accounts
--    (COM-155) stays byte-for-byte untouched by any Layer-4-only function in
--    this migration -- the ONLY place this migration ever writes to
--    app.accounts is app.decide_customer_profile_change_request, staff-gated
--    (COM:Approve), applying an already-reviewed change in the SAME
--    transaction as the request's own approval.
-- 2. **Writable field set is deliberately narrow: trade_name and
--    billing_address only** -- the two app.accounts fields genuinely safe for
--    a customer admin to propose a change to. Explicitly, deliberately
--    EXCLUDED from the writable set (source prompt §24: "Billing, tax/legal
--    and credit fields require configured authorization/approval";
--    "Customer profile edits cannot silently overwrite canonical customer
--    master data"):
--      - legal_name/tax_id -- legal identity/KYC fields. Changing a
--        registered legal name or tax id has compliance implications outside
--        this prompt's bounded mandate (this capability's own charter is
--        "customer profile maintenance," not a KYC/legal-entity-change
--        workflow). Disclosed as a residual gap, not silently dropped --
--        docs/runtime/KNOWN_ISSUES.md ISS-2026-123.
--      - parent_account_id/merged_into_id/org_unit_id/owner_user_id --
--        structural/staff-only fields (tenant org structure, staff CRM
--        ownership, account hierarchy/merge lineage) with zero customer-
--        facing meaning; never customer-touchable, no disclosure needed.
--      - credit fields -- app.accounts carries NO credit column at all.
--        Credit lives on the separate, staff-only app.credit_profiles table
--        (COM-157, 20260724310000_create_commercial_credit_commercial_
--        control.sql), entirely out of this prompt's own scope -- confirmed
--        by direct read of app.accounts' full column list before writing
--        this table, not assumed.
--    The table-level `cppcr_field_name_check` CHECK constraint enforces this
--    at the database, not merely the UI or the RPC's own application-level
--    validation -- `field_name` is never an open text column naming an
--    arbitrary field (the batch's own standing mandate).
-- 3. **legal_name/tax_id ARE included in the READ projection
--    (app.get_customer_portal_account_profile), deliberately, disclosed.**
--    A customer's own registered legal name and tax id are that customer's
--    own already-known identity, not proprietary CargoGrid data -- hiding
--    them from a "profile" screen the customer already partially controls
--    would be a confusing, broken UX (the source prompt's own §15 UI/UX
--    impact explicitly asks for "denied/locked states for the non-editable
--    fields," which presupposes those fields are still SHOWN, just
--    non-editable). customer_status is also included per the source prompt's
--    own explicit naming. Never included: any credit/margin/internal-risk
--    field (none exist on app.accounts, confirmed above), and never
--    org_unit_id/owner_user_id/duplicate_fingerprint/normalized_*/
--    parent_account_id/merged_into_id/status(active|merged, the internal
--    merge-lifecycle flag, distinct from customer_status) -- internal
--    structural fields with no customer-facing meaning.
-- 4. **Contacts: a read-only projection, no change-request path -- a
--    deliberate, disclosed scope decision, not a silent skip.** app.accounts
--    has no inline contact columns (confirmed by direct read of its full
--    column list); contacts are the separate, already-polymorphic app.
--    contact_links table (related_type now includes 'account', added by
--    COM-155 itself). This migration adds ONE new read-only RPC,
--    app.list_customer_portal_account_contacts, projecting a customer's own
--    account's contact_links rows (full_name/title/email/phone/role/
--    is_primary) -- satisfying the source prompt's own "contact... profile
--    screen" requirement per ADR-0024 Part A's read/write split (Part A
--    governs every NEW read; nothing requires a new read to also grow a
--    write path). A customer-initiated contact CHANGE-REQUEST path
--    (add/edit/remove a contact with staff approval) is explicitly NOT built
--    here: app.contact_links rows are Commercial-owned CRM data with their
--    own existing staff-only mutation surface (app.link_contact_to_record,
--    COM-145), and inventing a second, portal-owned contact-change-request
--    table mirroring this migration's own account-profile shape would be a
--    genuinely new, capability-sized addition beyond this prompt's own
--    bounded scope (normally 5-15 files, at most 1-3 additive migrations).
--    Disclosed as ISS-2026-123 alongside the legal_name/tax_id boundary.
-- 5. **Confirmed, not assumed: no Commercial/Operations/Finance table
--    denormalizes account name/address instead of referencing account_id**
--    (source prompt §24: "do not rewrite historical shipment/invoice
--    records" -- this migration's own required confirmation step). Direct
--    read before writing this migration: app.quotations.customer_snapshot
--    (COM-151, 20260724210000_create_commercial_quotation_builder.sql:99) is
--    copied from app.prospects at DRAFT time and never re-derived from
--    app.accounts afterward; app.job_orders/app.shipment_orders inherit that
--    SAME frozen customer_snapshot (or reference shipper_account_id by id,
--    20260727100000_create_operations_shipment_order.sql); app.
--    finance_invoices (20260729110000_create_finance_invoice.sql:84)
--    references customer_account_id only, carries no denormalized name/
--    address column at all. This migration's own UPDATE to app.accounts
--    (inside app.decide_customer_profile_change_request, approve path only)
--    therefore cannot and does not rewrite any historical record anywhere in
--    this repository -- the business rule holds structurally, not merely by
--    convention.
-- 6. **This migration is the FIRST mutator of app.accounts.trade_name/
--    billing_address anywhere in this repository, post row-creation** --
--    confirmed by grep (zero `set trade_name`/`set billing_address` against
--    app.accounts anywhere in supabase/migrations/ before this file).
--    Disclosed, not a defect: app.accounts' own pre-existing
--    accounts_touch_row trigger (20260724290000, `new.updated_at := now();
--    new.record_version := old.record_version + 1;`) already provides the
--    "effective version" the source prompt's own business rule requires
--    ("Changes carry effective version") -- no new versioning column is
--    invented; app.accounts.record_version itself is the effective-version
--    ledger, exactly as it already is for every other staff-side mutation of
--    that table.
-- 7. **Every actor-taking function calls app.assert_actor_is_session_identity
--    as its own literal first statement** -- the batch's own single most
--    common Critical defect class, applied from the first draft.
-- 8. **Idempotency (app.submit_customer_profile_change_request)**: the scope
--    check (does this identity's own resolved account scope include the
--    target account) runs BEFORE the idempotent short-circuit SELECT --
--    an unowned/forged account_id must never let a caller probe for an
--    existing idempotency_key's own outcome before their own authority over
--    the account is established. The INSERT itself is wrapped in a real
--    `exception when unique_violation` handler (not merely a pre-check), so
--    a genuine concurrent double-submit under the identical key converges on
--    one row, mirroring app.create_customer_quote_request_draft (CPL-302)
--    exactly.
-- 9. **Anti-enumeration (C-05)**: app.get_customer_portal_account_profile and
--    app.withdraw_customer_profile_change_request both raise the IDENTICAL
--    record_not_found (errcode no_data_found) whether the target id
--    genuinely does not exist, belongs to a different tenant, or exists but
--    is outside this identity's resolved account scope. app.decide_
--    customer_profile_change_request (staff-only) folds a standing check
--    (has_active_tenant_membership OR the row's own account being in the
--    caller's own resolved customer scope -- mirroring app.link_customer_
--    quote_request_to_quotation's identical dual-reachability fold, CPL-302)
--    into its own not-found branch, BEFORE the COM:Approve check, so a
--    caller with zero standing in this row's own tenant learns nothing
--    beyond "this id does not exist," while a genuine customer who already
--    knows this row exists (they may have submitted it themselves) correctly
--    reaches the informative insufficient_authority branch instead of a
--    confusing not-found.
-- 10. **Self-approval is blocked structurally as defense-in-depth, even
--    though not currently reachable** -- mirrors app.decide_payroll_
--    reimbursement_request's own C-18 self-approval guard (HRT-282) exactly.
--    requested_by_actor_auth_user_id is set ONLY by app.submit_customer_
--    profile_change_request, which has no staff caller (a customer_user
--    identity's own app.tenant_user_identities row is never 'active', so
--    app.has_active_tenant_membership -- and therefore COM:Approve -- is
--    unconditionally false for it, consistent with ISS-2026-040's own
--    "not currently exploitable under this repository's own current
--    role-assignment discipline" standing status). Retained, tested, and
--    disclosed rather than omitted as "impossible."
-- 11. **Status machine**: pending -> approved | rejected | withdrawn;
--    approved/rejected/withdrawn are all terminal. Enforced by a
--    `before update of status` trigger, mirroring app.enforce_customer_
--    portal_quote_request_transition (CPL-302) exactly. A single combined
--    touch trigger (updated_at + record_version) mirrors the same file's
--    own touch trigger exactly.
-- 12. **Scope grain is the account, not the original requester** -- any
--    active member of the account (account_admin or member, CPL-300's own
--    grant table) may submit/withdraw a profile change request on that
--    account, mirroring CPL-302's own "any account member" precedent
--    exactly. requested_by_actor_auth_user_id is informational/audit
--    provenance only, never an authorization gate.
-- 13. **review_reason is mandatory for BOTH approve and reject** (not only
--    reject) -- mirrors app.decide_payroll_reimbursement_request's own
--    unconditional reason requirement, a real audit trail for why a
--    proposed master-data change was accepted, not only why it was refused.
--    Never routed into app.capture_audit_event's own before/after jsonb
--    unredacted (mirrors HRT-282's own Tier C fix, applied here from the
--    first draft rather than retrofitted) -- only `status`/`field_name` are
--    captured in the "after" snapshot.
-- 14. **withdraw carries no separate reason column** -- the table's own given
--    column list (this task's own explicit schema) has no
--    "withdrawn_reason" field; a customer's own withdrawal is not a staff
--    review and is fully evidenced by the row's own status/updated_at/
--    record_version plus the standard app.capture_audit_event before/after
--    snapshot. Disclosed as a deliberate, bounded simplification matching
--    the literal given column list, not an oversight.
-- 15. **RLS: authenticated holds ZERO direct grant** on the new table,
--    mirroring CPL-300/CPL-302 exactly (enable RLS, grant all four DML verbs
--    to service_role only). Every one of the 6 RPCs below is the sanctioned
--    access path. app.accounts' own RLS is untouched by this migration.
-- 16. **REST/GraphQL transport (ADR-0024 Part C)**: service layer + Server
--    Actions + UI only, no new app/api/ HTTP route -- identical in kind to
--    every prior Phase 8 capability's own disclosed residual gap.
-- 17. **No edit to scripts/db-tests/rbac-enforcement.sql required** -- every
--    new function calls app.assert_actor_is_session_identity directly as its
--    own first statement, and every other authority primitive composed
--    (app.resolve_customer_account_scope, app.has_active_tenant_membership,
--    app.evaluate_permission) is already a recognized keyword in that file's
--    own closure sweep (unchanged since CPL-300/CPL-309's own identical
--    disclosure) -- confirmed live in this checkpoint's own scratch-database
--    run, not merely assumed.
-- 18. Per ERR-2026-004 (docs/runtime/ERROR_LEDGER.md): this migration carries
--    its own explicit `revoke execute on all functions in schema app from
--    public` statement before its final grants.

-- ===========================================================================
-- 1. app.customer_portal_profile_change_requests
-- ===========================================================================

create table app.customer_portal_profile_change_requests (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  account_id uuid not null references app.accounts (id),
  requested_by_actor_auth_user_id uuid not null references auth.users (id),
  field_name text not null,
  proposed_value jsonb not null,
  status text not null default 'pending',
  reviewed_by text,
  reviewed_at timestamptz,
  review_reason text,
  idempotency_key text,
  record_version integer not null default 1,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint cppcr_field_name_check check (field_name in ('trade_name', 'billing_address')),
  constraint cppcr_proposed_value_shape_check check (
    (field_name = 'trade_name' and jsonb_typeof(proposed_value) = 'string')
    or (field_name = 'billing_address' and jsonb_typeof(proposed_value) = 'object')
  ),
  constraint cppcr_status_check check (status in ('pending', 'approved', 'rejected', 'withdrawn')),
  constraint cppcr_review_fields_check check (
    (status in ('approved', 'rejected')) = (reviewed_by is not null and reviewed_at is not null)
  ),
  constraint cppcr_review_reason_check check (
    (status in ('approved', 'rejected') and review_reason is not null and length(trim(review_reason)) > 0)
    or (status not in ('approved', 'rejected'))
  )
);

comment on table app.customer_portal_profile_change_requests is
  'CPL-314: the portal-owned customer profile change REQUEST -- never a direct write into app.accounts (COM-155) from a customer-initiated RPC (ADR-0024 Part B). field_name is CHECK-constrained to exactly {trade_name, billing_address} (design decision 2); proposed_value is shaped per field (design decision, cppcr_proposed_value_shape_check). RLS enabled, authenticated holds zero direct grant (design decision 15) -- the 6 RPCs below are the only sanctioned access path.';

create unique index cppcr_tenant_idempotency_key_uq
  on app.customer_portal_profile_change_requests (tenant_id, idempotency_key)
  where idempotency_key is not null;

create index cppcr_tenant_updated_id_idx
  on app.customer_portal_profile_change_requests (tenant_id, updated_at desc, id desc);

create index cppcr_account_idx on app.customer_portal_profile_change_requests (account_id);

create index cppcr_account_pending_idx
  on app.customer_portal_profile_change_requests (account_id, status, created_at desc)
  where status = 'pending';

-- ===========================================================================
-- 2. Triggers -- mirror app.customer_portal_quote_requests' own triggers
-- (CPL-302) exactly (design decision 11)
-- ===========================================================================

create function app.enforce_customer_portal_profile_change_request_transition()
returns trigger
language plpgsql
as $$
begin
  if new.status = old.status then
    return new;
  end if;

  if old.status <> 'pending' then
    raise exception 'invalid_cppcr_transition: profile change request % is % and is terminal, no further transition is allowed', old.id, old.status
      using errcode = 'check_violation';
  end if;

  if new.status not in ('approved', 'rejected', 'withdrawn') then
    raise exception 'invalid_cppcr_transition: pending -> % is not a canonical transition', new.status
      using errcode = 'check_violation';
  end if;

  return new;
end;
$$;

create trigger customer_portal_profile_change_requests_enforce_transition
  before update of status on app.customer_portal_profile_change_requests
  for each row
  execute function app.enforce_customer_portal_profile_change_request_transition();

create function app.touch_customer_portal_profile_change_request_row()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  new.record_version := old.record_version + 1;
  return new;
end;
$$;

create trigger customer_portal_profile_change_requests_touch_row
  before update on app.customer_portal_profile_change_requests
  for each row
  execute function app.touch_customer_portal_profile_change_request_row();

-- ===========================================================================
-- 3. app.submit_customer_profile_change_request
-- ===========================================================================

create function app.submit_customer_profile_change_request(
  p_tenant_id uuid,
  p_account_id uuid,
  p_field_name text,
  p_proposed_value jsonb,
  p_idempotency_key text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.customer_portal_profile_change_requests
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_existing app.customer_portal_profile_change_requests;
  v_request app.customer_portal_profile_change_requests;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  if p_field_name not in ('trade_name', 'billing_address') then
    raise exception 'invalid_field_name: % is not a field a customer may propose a change to', p_field_name using errcode = 'check_violation';
  end if;

  -- Scope/authority check BEFORE the idempotent short-circuit (design decision 8).
  if not (p_account_id = any (app.resolve_customer_account_scope(p_actor_auth_user_id, p_tenant_id))) then
    raise exception 'account_not_available: % is not an account this identity may propose a profile change for', p_account_id using errcode = 'no_data_found';
  end if;

  if p_idempotency_key is not null then
    select * into v_existing from app.customer_portal_profile_change_requests where tenant_id = p_tenant_id and idempotency_key = p_idempotency_key;
    if found then
      if v_existing.account_id = p_account_id then
        return v_existing;
      end if;
      raise exception 'idempotency_key_conflict: key % was already used for a different account''s profile change request %', p_idempotency_key, v_existing.id
        using errcode = 'unique_violation';
    end if;
  end if;

  if p_field_name = 'trade_name' then
    if jsonb_typeof(p_proposed_value) <> 'string' or length(trim(coalesce(p_proposed_value #>> '{}', ''))) = 0 then
      raise exception 'invalid_proposed_value: trade_name must be proposed as a non-empty JSON string' using errcode = 'check_violation';
    end if;
  elsif p_field_name = 'billing_address' then
    if jsonb_typeof(p_proposed_value) <> 'object' then
      raise exception 'invalid_proposed_value: billing_address must be proposed as a JSON object' using errcode = 'check_violation';
    end if;
  end if;

  -- Real exception handler, not merely a pre-check (design decision 8) -- a
  -- genuine concurrent double-submit under the identical key converges on
  -- one row, mirroring app.create_customer_quote_request_draft (CPL-302).
  begin
    insert into app.customer_portal_profile_change_requests (
      tenant_id, account_id, requested_by_actor_auth_user_id, field_name, proposed_value, idempotency_key
    ) values (
      p_tenant_id, p_account_id, p_actor_auth_user_id, p_field_name, p_proposed_value, p_idempotency_key
    )
    returning * into v_request;
  exception
    when unique_violation then
      if p_idempotency_key is null then
        raise;
      end if;
      select * into v_request from app.customer_portal_profile_change_requests where tenant_id = p_tenant_id and idempotency_key = p_idempotency_key;
      if not found or v_request.account_id <> p_account_id then
        raise;
      end if;
      return v_request;
  end;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'submit_customer_profile_change_request',
    'app.customer_portal_profile_change_requests', v_request.id, 'success', null, null, to_jsonb(v_request)
  );

  return v_request;
end;
$$;

comment on function app.submit_customer_profile_change_request is
  'CPL-314: creates a pending profile change request for exactly one of {trade_name, billing_address}. p_account_id must already be in app.resolve_customer_account_scope(actor, tenant) -- checked BEFORE the idempotent short-circuit (design decision 8). Idempotent on (tenant_id, idempotency_key) when a key is supplied; the INSERT itself carries a real unique_violation handler, not only a pre-check.';

-- ===========================================================================
-- 4. app.withdraw_customer_profile_change_request -- pending -> withdrawn
-- ===========================================================================

create function app.withdraw_customer_profile_change_request(
  p_request_id uuid,
  p_expected_version integer,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.customer_portal_profile_change_requests
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_request app.customer_portal_profile_change_requests;
  v_updated app.customer_portal_profile_change_requests;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  select * into v_request from app.customer_portal_profile_change_requests where id = p_request_id for update;
  if not found or not (v_request.account_id = any (app.resolve_customer_account_scope(p_actor_auth_user_id, v_request.tenant_id))) then
    raise exception 'record_not_found: no permitted profile change request exists for %', p_request_id using errcode = 'no_data_found';
  end if;

  if v_request.record_version <> p_expected_version then
    raise exception 'stale_version: profile change request % expected version % but found %', p_request_id, p_expected_version, v_request.record_version
      using errcode = 'serialization_failure';
  end if;

  if v_request.status <> 'pending' then
    raise exception 'invalid_transition: profile change request % is % and can no longer be withdrawn', p_request_id, v_request.status
      using errcode = 'check_violation';
  end if;

  update app.customer_portal_profile_change_requests
  set status = 'withdrawn'
  where id = p_request_id
  returning * into v_updated;

  perform app.capture_audit_event(
    v_updated.tenant_id, p_actor_auth_user_id, p_actor_label, 'withdraw_customer_profile_change_request',
    'app.customer_portal_profile_change_requests', v_updated.id, 'success', null, null, to_jsonb(v_updated)
  );

  return v_updated;
end;
$$;

comment on function app.withdraw_customer_profile_change_request is
  'CPL-314: pending -> withdrawn only. Any active member of the request''s own account may withdraw it (design decision 12), not only its original requester. Optimistic concurrency (stale_version) checked before the status check, so a genuine retry against an already-decided row surfaces the more informative error first.';

-- ===========================================================================
-- 5. app.list_customer_portal_profile_change_requests -- keyset paginated
-- ===========================================================================

create function app.list_customer_portal_profile_change_requests(
  p_tenant_id uuid,
  p_actor_auth_user_id uuid,
  p_account_id uuid default null,
  p_status text default null,
  p_cursor_updated_at timestamptz default null,
  p_cursor_id uuid default null,
  p_limit integer default 50
)
returns setof app.customer_portal_profile_change_requests
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_scope uuid[];
  v_limit integer;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  if p_cursor_id is not null and p_cursor_updated_at is null then
    raise exception 'invalid_cursor: p_cursor_updated_at is required when p_cursor_id is supplied' using errcode = 'invalid_parameter_value';
  end if;

  v_scope := app.resolve_customer_account_scope(p_actor_auth_user_id, p_tenant_id);
  if array_length(v_scope, 1) is null then
    return;
  end if;
  if p_account_id is not null and not (p_account_id = any (v_scope)) then
    return;
  end if;

  v_limit := least(greatest(coalesce(p_limit, 50), 1), 200);

  return query
  select r.*
  from app.customer_portal_profile_change_requests r
  where r.tenant_id = p_tenant_id
    and r.account_id = any (v_scope)
    and (p_account_id is null or r.account_id = p_account_id)
    and (p_status is null or r.status = p_status)
    and (p_cursor_id is null or (r.updated_at, r.id) < (p_cursor_updated_at, p_cursor_id))
  order by r.updated_at desc, r.id desc
  limit v_limit;
end;
$$;

comment on function app.list_customer_portal_profile_change_requests is
  'CPL-314: keyset-paginated (tenant_id, updated_at desc, id desc), never OFFSET, hard-capped at 200 -- mirrors app.list_customer_quote_requests (CPL-302) exactly. Deny-by-default: zero scope or an out-of-scope p_account_id both return an empty result, never an error.';

-- ===========================================================================
-- 6. app.get_customer_portal_account_profile -- read-only current-state
-- projection + pending change-request summary (design decision 3)
-- ===========================================================================

create function app.get_customer_portal_account_profile(
  p_tenant_id uuid,
  p_actor_auth_user_id uuid,
  p_account_id uuid
)
returns table (
  account_id uuid,
  legal_name text,
  trade_name text,
  tax_id text,
  billing_address jsonb,
  customer_status text,
  record_version integer,
  updated_at timestamptz,
  pending_change_request_count integer,
  latest_pending_change_request_id uuid,
  latest_pending_change_request_field text,
  latest_pending_change_request_submitted_at timestamptz
)
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_account app.accounts;
  v_pending_count integer;
  v_latest_id uuid;
  v_latest_field text;
  v_latest_created_at timestamptz;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  -- Explicit alias (a0), never a bare column reference -- this function's own
  -- RETURNS TABLE column list auto-declares a PL/pgSQL variable named
  -- `account_id`, which would otherwise make an unqualified reference
  -- ambiguous against app.accounts.id/app.customer_portal_profile_change_
  -- requests.account_id (the exact defect class CPL-300's own header warns
  -- "made 7 RPCs 100% non-functional" in an earlier checkpoint).
  select * into v_account from app.accounts a0 where a0.id = p_account_id and a0.tenant_id = p_tenant_id;
  if not found or not (v_account.id = any (app.resolve_customer_account_scope(p_actor_auth_user_id, p_tenant_id))) then
    raise exception 'record_not_found: no permitted account exists for %', p_account_id using errcode = 'no_data_found';
  end if;

  select count(*) into v_pending_count
  from app.customer_portal_profile_change_requests r0
  where r0.account_id = v_account.id and r0.status = 'pending';

  select r1.id, r1.field_name, r1.created_at into v_latest_id, v_latest_field, v_latest_created_at
  from app.customer_portal_profile_change_requests r1
  where r1.account_id = v_account.id and r1.status = 'pending'
  order by r1.created_at desc
  limit 1;

  return query
  select
    v_account.id,
    v_account.legal_name,
    v_account.trade_name,
    v_account.tax_id,
    v_account.billing_address,
    v_account.customer_status,
    v_account.record_version,
    v_account.updated_at,
    v_pending_count,
    v_latest_id,
    v_latest_field,
    v_latest_created_at;
end;
$$;

comment on function app.get_customer_portal_account_profile is
  'CPL-314: anti-enumerating get-by-id (ADR-0024 Part A) -- raises the IDENTICAL record_not_found (errcode no_data_found) whether p_account_id genuinely does not exist, belongs to a different tenant, or exists but is outside this identity''s resolved scope. legal_name/tax_id are included READ-ONLY (design decision 3) -- never writable via app.submit_customer_profile_change_request''s own field_name CHECK. Never exposes parent_account_id/merged_into_id/org_unit_id/owner_user_id/duplicate_fingerprint/normalized_*/status(active|merged) or any credit-adjacent field (none exist on app.accounts). pending_change_request_count/latest_pending_change_request_* summarize this account''s own OPEN change requests only -- never another account''s.';

-- ===========================================================================
-- 7. app.list_customer_portal_account_contacts -- read-only contacts
-- projection (design decision 4)
-- ===========================================================================

create function app.list_customer_portal_account_contacts(
  p_tenant_id uuid,
  p_actor_auth_user_id uuid,
  p_account_id uuid
)
returns table (
  contact_id uuid,
  full_name text,
  title text,
  email text,
  phone text,
  role text,
  is_primary boolean
)
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  -- Deny-by-default, empty result rather than an error (list convention, not
  -- get-by-id) -- mirrors app.list_customer_quote_request_files (CPL-302).
  if not (p_account_id = any (app.resolve_customer_account_scope(p_actor_auth_user_id, p_tenant_id))) then
    return;
  end if;

  return query
  select c.id, c.full_name, c.title, c.email, c.phone, cl.role, cl.is_primary
  from app.contact_links cl
  join app.contacts c on c.id = cl.contact_id
  where cl.related_type = 'account'
    and cl.related_id = p_account_id
    and cl.tenant_id = p_tenant_id
    and c.tenant_id = p_tenant_id
    and c.status = 'active'
  order by cl.is_primary desc, c.full_name;
end;
$$;

comment on function app.list_customer_portal_account_contacts is
  'CPL-314: read-only projection of this account''s own app.contact_links rows (related_type=''account'', COM-155). No customer-initiated write path exists for contacts (design decision 4, disclosed ISS-2026-123) -- app.contact_links remains Commercial-owned CRM data via its own existing staff-only app.link_contact_to_record (COM-145). Deny-by-default: an out-of-scope or nonexistent account returns an empty result, never an error.';

-- ===========================================================================
-- 8. app.decide_customer_profile_change_request -- staff, COM:Approve
-- (design decision 1, the ONLY place this migration writes to app.accounts)
-- ===========================================================================

create function app.decide_customer_profile_change_request(
  p_request_id uuid,
  p_expected_version integer,
  p_decision text,
  p_review_reason text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.customer_portal_profile_change_requests
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_request app.customer_portal_profile_change_requests;
  v_decision app.rbac_decision;
  v_account app.accounts;
  v_updated app.customer_portal_profile_change_requests;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  select * into v_request from app.customer_portal_profile_change_requests where id = p_request_id for update;
  -- C-05 fold (design decision 9): a caller with zero standing in this row's
  -- own tenant (neither staff, nor a customer_user with real scope over the
  -- row's own account) gets the identical not-found a missing row would
  -- produce. A genuine customer who already knows this row exists (they may
  -- have submitted it) instead reaches the informative insufficient_authority
  -- branch below -- mirrors app.link_customer_quote_request_to_quotation
  -- (CPL-302) exactly.
  if not found or not (
    app.has_active_tenant_membership(v_request.tenant_id, p_actor_auth_user_id)
    or (v_request.account_id = any (app.resolve_customer_account_scope(p_actor_auth_user_id, v_request.tenant_id)))
  ) then
    raise exception 'profile_change_request_not_found: %', p_request_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_request.tenant_id, 'COM', 'Approve');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks COM:Approve (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_request.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  -- Defense-in-depth, structurally unreachable today (design decision 10):
  -- requested_by_actor_auth_user_id is only ever set by app.submit_customer_
  -- profile_change_request, which has no staff caller (a customer_user
  -- identity's app.tenant_user_identities row is never 'active', so
  -- app.has_active_tenant_membership -- and therefore COM:Approve -- is
  -- unconditionally false for it). Retained and tested anyway, mirroring
  -- app.decide_payroll_reimbursement_request's own C-18 guard (HRT-282).
  if v_request.requested_by_actor_auth_user_id = p_actor_auth_user_id then
    raise exception 'self_approval_not_permitted: an actor may not decide their own profile change request' using errcode = 'insufficient_privilege';
  end if;

  if p_decision not in ('approve', 'reject') then
    raise exception 'invalid_decision: % must be approve or reject', p_decision using errcode = 'check_violation';
  end if;

  if p_review_reason is null or length(trim(p_review_reason)) = 0 then
    raise exception 'reason_required: a reason is required to decide a profile change request' using errcode = 'not_null_violation';
  end if;

  if v_request.record_version <> p_expected_version then
    raise exception 'stale_version: profile change request % expected version % but found %', p_request_id, p_expected_version, v_request.record_version
      using errcode = 'serialization_failure';
  end if;

  if v_request.status <> 'pending' then
    raise exception 'invalid_transition: profile change request % is % and cannot be decided', p_request_id, v_request.status
      using errcode = 'check_violation';
  end if;

  if p_decision = 'approve' then
    -- Applies the already-reviewed change to the real canonical row, in the
    -- SAME transaction as the request's own approval (design decision 1).
    -- app.accounts' own pre-existing accounts_touch_row trigger bumps
    -- record_version/updated_at -- the "effective version" (design decision
    -- 6), no separate versioning column is invented here.
    select * into v_account from app.accounts where id = v_request.account_id for update;
    if v_request.field_name = 'trade_name' then
      update app.accounts set trade_name = (v_request.proposed_value #>> '{}') where id = v_account.id;
    elsif v_request.field_name = 'billing_address' then
      update app.accounts set billing_address = v_request.proposed_value where id = v_account.id;
    end if;
  end if;

  update app.customer_portal_profile_change_requests
  set status = case p_decision when 'approve' then 'approved' else 'rejected' end,
      reviewed_by = p_actor_label, reviewed_at = now(), review_reason = p_review_reason
  where id = p_request_id
  returning * into v_updated;

  -- p_review_reason is never routed into the audit before/after jsonb
  -- unredacted (design decision 13, HRT-282's own established fix, applied
  -- from the first draft here).
  perform app.capture_audit_event(
    v_updated.tenant_id, p_actor_auth_user_id, p_actor_label, 'decide_customer_profile_change_request',
    'app.customer_portal_profile_change_requests', v_updated.id, 'success', null,
    jsonb_build_object('status', v_request.status, 'field_name', v_request.field_name),
    jsonb_build_object('status', v_updated.status, 'field_name', v_updated.field_name)
  );

  return v_updated;
end;
$$;

comment on function app.decide_customer_profile_change_request is
  'CPL-314: staff-only (COM:Approve) -- pending -> approved | rejected. review_reason is mandatory for BOTH outcomes (design decision 13), never persisted into the audit before/after snapshot unredacted. On approve, applies the change to the real app.accounts row (trade_name or billing_address, matching the request''s own field_name) in the SAME transaction -- the ONLY place this migration writes to app.accounts. On reject, app.accounts is left completely untouched. Self-approval is structurally blocked (design decision 10), though not currently reachable by any real caller in this repository.';

-- ===========================================================================
-- 9. RLS -- enable, grant service_role only (design decision 15)
-- ===========================================================================

alter table app.customer_portal_profile_change_requests enable row level security;

grant select, insert, update, delete on app.customer_portal_profile_change_requests to service_role;

-- Per ERR-2026-004 (docs/runtime/ERROR_LEDGER.md): explicit, directly-provable
-- revoke of PostgreSQL's PUBLIC-execute default before any role-specific grant.
revoke execute on all functions in schema app from public;

grant execute on function app.submit_customer_profile_change_request(uuid, uuid, text, jsonb, text, uuid, text) to authenticated, service_role;
grant execute on function app.withdraw_customer_profile_change_request(uuid, integer, uuid, text) to authenticated, service_role;
grant execute on function app.list_customer_portal_profile_change_requests(uuid, uuid, uuid, text, timestamptz, uuid, integer) to authenticated, service_role;
grant execute on function app.get_customer_portal_account_profile(uuid, uuid, uuid) to authenticated, service_role;
grant execute on function app.list_customer_portal_account_contacts(uuid, uuid, uuid) to authenticated, service_role;
grant execute on function app.decide_customer_profile_change_request(uuid, integer, text, text, uuid, text) to authenticated, service_role;
