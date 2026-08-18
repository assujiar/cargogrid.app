-- Phase 8 capability CPL-302 (CG-S13-CPL-004, Prompt 302, "Request Quotation").
-- Read docs/adr/ADR-0024-phase8-customer-portal-access-and-transport-pattern.md
-- and supabase/migrations/20260801010000_create_customer_portal_account_scope.sql
-- (CPL-300) in full before this migration was written -- this is the first
-- Phase 8 capability that ADR-0024 Part B (customer writes) actually governs
-- end to end: a new portal-owned intake table, never a direct write into the
-- canonical app.quotations (COM-151, 20260724210000_create_commercial_
-- quotation_builder.sql), and staff conversion stays a real, RBAC-gated,
-- separate acknowledgement RPC, never opened to a customer caller.
--
-- ===========================================================================
-- Design decisions (cited, not re-derived)
-- ===========================================================================
--
-- 1. **A new portal-owned request/intent table, never app.quotations.**
--    app.quotations (COM-151) stays byte-for-byte untouched -- its own RLS is
--    never widened, its own staff-only app.create_quotation_draft is never
--    called from here. app.customer_portal_quote_requests carries NO tariff,
--    margin, or tax field of any kind (source prompt §24: "Customer cannot
--    override customer, account, site, tariff, margin, tax or approval
--    fields") -- this is a request FOR a quote, never a rated quote itself.
--    `linked_quotation_id` is the only bridge to the canonical record, set
--    exactly once, only by the staff-gated app.link_customer_quote_request_
--    to_quotation below (decision 6).
-- 2. **origin/destination are bounded jsonb snapshots, not a location
--    master.** No canonical address/lane/service master exists yet in this
--    repository (the same disclosed boundary COM-151's own header names for
--    app.quotations.customer_snapshot) -- a free-form, small jsonb object
--    (`{label, addressLine, city, country}`-shaped, but not schema-enforced
--    beyond "is a JSON object", matching customer_snapshot's own precedent)
--    is the simplest honest shape for a REQUEST, never a rated/geocoded
--    location. `service_type` stays a plain text field for the identical
--    reason -- no canonical service-catalog master exists yet either.
-- 3. **Two distinct idempotency keys, not one reused column.** Tier C
--    correction: this bullet previously attributed the literal phrases
--    "idempotency_key on every create" / "idempotency_key unique per
--    tenant+account" to "the source prompt's own RPC list" -- neither
--    phrase appears anywhere in 302_REQUEST_QUOTATION_PROMPT.md (confirmed
--    by direct grep); the general CPL-300 idempotency-on-every-create house
--    style and the tenant+account uniqueness requirement were in fact the
--    orchestrating task's own instruction, not a source-prompt quotation --
--    corrected here to avoid mis-citing a document that does not carry this
--    text, mirroring how CPL-303/304's own design decisions correctly
--    attribute equivalent instructions to "the orchestrating task." Reusing
--    a single `idempotency_key` column for both stages
--    would let a genuine retry of the ORIGINAL create call (e.g. a network
--    retry arriving after the row has already been submitted) fail to find
--    its own match once that column had been overwritten by the submit
--    stage, and insert a duplicate draft -- a real, live-reproducible
--    double-submission bug. `idempotency_key` (create-stage, unique per
--    tenant) and `submitted_idempotency_key` (submit-stage, unique per
--    tenant+account, exactly as specified) are therefore two separate,
--    independently-unique columns -- disclosed, not a silent deviation from
--    the given column list, which named idempotency as a concept, not a
--    literal single-column constraint.
-- 4. **File attachments reuse the Platform Document/File Engine (PLT-128)
--    exactly as instructed -- record_type='customer_portal_quote_request',
--    record_id=the request id -- with two small, necessary, disclosed
--    additions, not a parallel file table:**
--    (a) a new app.document_types/app.config_types row
--    (`quote_request_attachment`, owner_primitive_code='CPT') registered by
--    direct INSERT ... ON CONFLICT DO NOTHING at migration-apply time --
--    migration-apply context has no live actor session to satisfy app.
--    register_document_type's own Supreme-Admin gate, mirroring app.tickets'
--    own established `ticket_attachment` precedent
--    (20260731060000_create_ticketing_internal.sql design decision 8)
--    exactly, including that a tenant must still separately draft+publish a
--    real MIME/size/retention/classification definition before any upload
--    against this code succeeds -- a standing, disclosed, repository-wide
--    Document/File Engine precondition, not unique to this capability.
--    (b) `app.check_file_action_authority` (PLT-128, service_role-only,
--    never reachable directly by `authenticated`) is widened by `create or
--    replace` (identical signature, grants therefore untouched) to also
--    recognize an active customer_user-layer principal (app.actor_holds_
--    customer_user_layer) alongside its existing has_active_tenant_
--    membership/is_supreme_admin checks. Verified necessary, not assumed: a
--    customer_user-layer identity's own app.tenant_user_identities row is
--    linked by app.link_auth_identity at status='invited' (CPL-300's own
--    invite/accept/bootstrap flow) and is NEVER transitioned to 'active' by
--    any function in this repository (only app.transition_user_status does
--    that, the staff-only onboarding path) -- so app.has_active_tenant_
--    membership, and therefore the UNWIDENED app.check_file_action_
--    authority, is unconditionally false for every customer_user identity
--    that has ever existed in this repository. Leaving app.initiate_file_
--    upload's own gate unwidened would make a "real" customer-attributed
--    upload permanently, silently impossible -- exactly the "no placeholder/
--    fake persistence" failure mode AGENTS.md forbids -- while widening it
--    is safe: every function that composes it (initiate_file_upload/record_
--    file_scan_result/authorize_file_access) is granted to `service_role`
--    only, never `authenticated`, so this widening only changes which
--    ALREADY-SERVER-MEDIATED calls succeed; it opens no new direct-client
--    attack surface. The real per-request/per-account authorization decision
--    (does THIS customer identity own THIS specific draft request) is made
--    by this capability's own server-side wrapper (server/mutations/
--    customer-quote-request.ts) BEFORE it ever calls initiateFileUpload --
--    check_file_action_authority only answers the coarser "is this a
--    standing customer_user of this tenant at all" question, the same
--    granularity has_active_tenant_membership already answers for staff.
--    **Tier C correction**: an earlier draft of this migration disclosed
--    "app.submit_customer_quote_request does NOT gate on attachment
--    malware-scan status" and attributed that omission to "the source
--    prompt's own explicit escape hatch, 'a minimal but real attachment
--    list... is sufficient'" -- that quoted text does not exist anywhere in
--    302_REQUEST_QUOTATION_PROMPT.md (confirmed by direct grep), and the
--    prompt in fact says the opposite: §23 "Block ... unscanned file", §24
--    "Files remain private, scanned and scope-bound before any download or
--    handoff." A submitted request IS this capability's own handoff moment
--    (§20: "...internal Commercial handoff"). Fixed at the root, not merely
--    re-disclosed: app.submit_customer_quote_request now raises
--    unscanned_attachment if any active attachment on the request has not
--    cleared malware scanning (malware_scan_status <> 'clean'). (ii) app.
--    authorize_file_access remains deliberately NOT composed from the
--    customer portal at all -- live
--    inspection of its own record-scope branch (app.can_access_record,
--    PLT-114) shows it ALSO hard-requires has_active_tenant_membership
--    (`... and (has_active_tenant_membership(...) and (...))`), so even
--    after this migration's own check_file_action_authority widening, a
--    customer co-worker who did not personally upload a given file would be
--    incorrectly denied by app.can_access_record's own customer_account_ref
--    branch (which is reachable in principle but never satisfiable in
--    practice for the identical has_active_tenant_membership reason). This
--    is a genuine, pre-existing, cross-cutting Platform primitive gap (PLT-
--    114/PLT-128), not caused by this migration and not in this capability's
--    own allowed file scope to fix (fixing app.can_access_record's own
--    customer_account_ref branch is a repository-wide Platform hardening
--    task). This capability's own new app.list_customer_quote_request_files
--    below is therefore the ONLY sanctioned attachment-metadata read path
--    for a customer -- a SECURITY DEFINER RPC composing this capability's
--    own account-scope resolver directly, never app.can_access_record --
--    exactly the ADR-0024 Part A shape, and, unlike authorize_file_access,
--    genuinely correct for every account member, not only the uploader.
-- 5. **RLS: authenticated holds ZERO direct grant**, mirroring CPL-300's own
--    app.customer_portal_account_memberships convention exactly (enable RLS,
--    grant all four DML verbs to service_role only). Every one of the 7
--    customer-facing RPCs below is the sanctioned access path.
-- 6. **Staff conversion acknowledgement is the ONLY place this migration
--    touches staff RBAC** -- app.link_customer_quote_request_to_quotation,
--    gated by the real, already-existing app.evaluate_permission(actor,
--    tenant, 'COM', 'Edit') (the same module/action app.add_quotation_line/
--    app.submit_quotation already require -- reused, never a new module/
--    action). This mirrors CPL-300's own one deliberate bootstrap-RPC
--    exception shape (app.grant_initial_customer_portal_account_admin, CPT:
--    Create) exactly: every OTHER function in this migration is Layer-4-only
--    per ADR-0024 Part B. Tier C correction: this bullet's closing line
--    previously quoted "Staff-side conversion acknowledgement, minimal" as
--    the source prompt's own framing -- that phrase does not appear in
--    302_REQUEST_QUOTATION_PROMPT.md (confirmed by direct grep); it was the
--    orchestrating task's own instruction, not a source-prompt quotation --
--    corrected here for the same reason as design decision 3 above.
--    **Disclosed scope boundary**: app.quotations
--    (COM-151) has no app.accounts/customer reference at all (only
--    opportunity_id -> prospect_id, predating COM-155's own account
--    conversion) -- there is therefore no structural way for this function
--    to verify the linked quotation belongs to the SAME customer/account as
--    the request being converted. The COM:Edit-holding staff actor's own
--    authority (the same authority app.add_quotation_line/app.
--    submit_quotation already trust unconditionally for editing that exact
--    quotation) is relied on, matching this capability's own scope --
--    "Staff-side conversion acknowledgement, minimal" (the orchestrating
--    task's own instruction, not a source-prompt quotation -- see the Tier C
--    correction above).
-- 7. **Status machine**: draft -> submitted | cancelled; submitted ->
--    cancelled | converted; cancelled and converted are both terminal.
--    Enforced by a `before update of status` trigger, mirroring app.
--    enforce_customer_portal_account_membership_transition (CPL-300)
--    exactly. A single combined touch trigger (updated_at + record_version)
--    mirrors app.touch_customer_portal_account_membership_row exactly --
--    every mutation below relies on it rather than setting those two
--    columns by hand, and every optimistic-concurrency check below follows
--    CPL-300's own `select ... for update` + explicit raise shape (never a
--    redundant `record_version = p_expected_version` predicate repeated in
--    the UPDATE, since the row lock already makes that safe -- verified
--    against scripts/db-tests/rbac-enforcement.sql's own optimistic-
--    concurrency sweep, which accepts EITHER shape).
-- 8. **Anti-enumeration**: app.get_customer_quote_request raises the
--    identical `record_not_found` (errcode no_data_found) whether the id
--    genuinely does not exist, belongs to another tenant, or exists but its
--    account is outside this identity's scope -- mirrors ATW-242's app.get_
--    customer_inventory_balance exactly (ADR-0024 Part A's own named
--    precedent). app.update_customer_quote_request_draft/app.submit_
--    customer_quote_request/app.cancel_customer_quote_request reuse the
--    SAME message/errcode for the identical reason (a forged id for
--    another customer's request must not disclose whether it exists).
--    List/files RPCs use the sibling "empty result, never an error"
--    deny-by-default convention CPL-300's own list function already
--    established, since a list is not a get-by-id.
-- 9. **Scope grain is the account, not the original requester.** Any active
--    member of the account (account_admin or member, CPL-300's own grant
--    table) may view/edit/submit/cancel a draft/submitted request on that
--    account, mirroring HRT-287's own "any account member sees the
--    account's tickets" precedent exactly (app.resolve_customer_owner_
--    account_scope-based, not restricted to the ticket's own requester).
--    `requested_by_auth_user_id` is informational/audit provenance only,
--    never an authorization gate.
-- 10. **REST/GraphQL transport (ADR-0024 Part C)**: this checkpoint builds
--    server/contracts + server/queries + server/mutations + Server
--    Actions + UI only, no app/api/ HTTP route -- identical in kind to
--    CPL-300's and CPL-301's own disclosed residual gap, itself identical
--    to every Phase 1-7 capability's own standing disclosure (no REST/
--    GraphQL adapter exists anywhere in this repository for any internal
--    or portal workflow; every one goes through Server Actions/RSC
--    fetches over the same typed service layer). Not a new exception this
--    checkpoint invents.
-- 11. Per ERR-2026-004 (docs/runtime/ERROR_LEDGER.md): this migration
--    carries its own explicit `revoke execute on all functions in schema
--    app from public` before its final grants.

-- ===========================================================================
-- 1. app.customer_portal_quote_requests
-- ===========================================================================

create table app.customer_portal_quote_requests (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  account_id uuid not null references app.accounts (id),
  requested_by_auth_user_id uuid not null references auth.users (id),
  status text not null default 'draft',
  cargo_description text,
  origin jsonb not null default '{}'::jsonb,
  destination jsonb not null default '{}'::jsonb,
  service_type text,
  requested_pickup_date date,
  requested_delivery_date date,
  notes text,
  idempotency_key text,
  submitted_idempotency_key text,
  linked_quotation_id uuid references app.quotations (id),
  record_version integer not null default 1,
  created_by text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  submitted_at timestamptz,
  cancelled_at timestamptz,
  cancelled_reason text,
  constraint cpqr_status_check check (status in ('draft', 'submitted', 'cancelled', 'converted')),
  constraint cpqr_origin_check check (jsonb_typeof(origin) = 'object'),
  constraint cpqr_destination_check check (jsonb_typeof(destination) = 'object'),
  constraint cpqr_dates_check check (
    requested_pickup_date is null or requested_delivery_date is null or requested_delivery_date >= requested_pickup_date
  ),
  constraint cpqr_cancelled_reason_check check (
    (status = 'cancelled' and cancelled_reason is not null and length(trim(cancelled_reason)) > 0)
    or (status <> 'cancelled')
  ),
  constraint cpqr_converted_requires_link check ((status = 'converted') = (linked_quotation_id is not null))
);

comment on table app.customer_portal_quote_requests is
  'CPL-302: the portal-owned quote REQUEST -- never app.quotations (COM-151), no tariff/margin/tax field of any kind. linked_quotation_id is set exactly once, only by app.link_customer_quote_request_to_quotation below, and only alongside status=converted (cpqr_converted_requires_link). RLS enabled, authenticated holds zero direct grant (design decision 5) -- the 7 customer-facing RPCs plus the 1 staff-gated RPC below are the only sanctioned access path.';

create unique index cpqr_tenant_idempotency_key_uq
  on app.customer_portal_quote_requests (tenant_id, idempotency_key)
  where idempotency_key is not null;

create unique index cpqr_tenant_account_submit_idem_uq
  on app.customer_portal_quote_requests (tenant_id, account_id, submitted_idempotency_key)
  where submitted_idempotency_key is not null;

-- The one covering index every RPC below actually needs (source prompt's own
-- required shape: tenant_id, updated_at desc, id desc, never OFFSET) --
-- account_id is filtered via the scope array, not a leading index column,
-- since the list RPC must range across every account in scope at once.
create index cpqr_tenant_updated_id_idx
  on app.customer_portal_quote_requests (tenant_id, updated_at desc, id desc);

create index cpqr_account_idx on app.customer_portal_quote_requests (account_id);
create index cpqr_linked_quotation_idx on app.customer_portal_quote_requests (linked_quotation_id) where linked_quotation_id is not null;

-- ===========================================================================
-- 2. Triggers -- mirror CPL-300's app.customer_portal_account_memberships
--    triggers exactly (design decision 7)
-- ===========================================================================

create function app.enforce_customer_portal_quote_request_transition()
returns trigger
language plpgsql
as $$
begin
  if new.status = old.status then
    return new;
  end if;

  if old.status in ('cancelled', 'converted') then
    raise exception 'invalid_cpqr_transition: quote request % is % and is terminal, no further transition is allowed', old.id, old.status
      using errcode = 'check_violation';
  end if;

  if not (
    (old.status = 'draft' and new.status in ('submitted', 'cancelled'))
    or (old.status = 'submitted' and new.status in ('cancelled', 'converted'))
  ) then
    raise exception 'invalid_cpqr_transition: % -> % is not a canonical transition', old.status, new.status
      using errcode = 'check_violation';
  end if;

  return new;
end;
$$;

create trigger customer_portal_quote_requests_enforce_transition
  before update of status on app.customer_portal_quote_requests
  for each row
  execute function app.enforce_customer_portal_quote_request_transition();

create function app.touch_customer_portal_quote_request_row()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  new.record_version := old.record_version + 1;
  return new;
end;
$$;

create trigger customer_portal_quote_requests_touch_row
  before update on app.customer_portal_quote_requests
  for each row
  execute function app.touch_customer_portal_quote_request_row();

-- ===========================================================================
-- 3. app.create_customer_quote_request_draft
-- ===========================================================================

create function app.create_customer_quote_request_draft(
  p_tenant_id uuid,
  p_account_id uuid,
  p_cargo_description text,
  p_origin jsonb,
  p_destination jsonb,
  p_service_type text,
  p_requested_pickup_date date,
  p_requested_delivery_date date,
  p_notes text,
  p_idempotency_key text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.customer_portal_quote_requests
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_existing app.customer_portal_quote_requests;
  v_request app.customer_portal_quote_requests;
  v_origin jsonb := coalesce(p_origin, '{}'::jsonb);
  v_destination jsonb := coalesce(p_destination, '{}'::jsonb);
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  if not (p_account_id = any (app.resolve_customer_account_scope(p_actor_auth_user_id, p_tenant_id))) then
    raise exception 'account_not_available: % is not an account this identity may request a quotation for', p_account_id using errcode = 'no_data_found';
  end if;

  -- Tier C fix (C-01 discipline): the idempotent short-circuit must verify
  -- the found row actually belongs to the SAME account this call targets
  -- before ever returning it. A colliding key belonging to a DIFFERENT
  -- account -- whether guessed, or a genuine same-actor multi-account
  -- collision (a dual-scoped identity racing two real submissions under the
  -- same millisecond-derived key) -- is a real idempotency_key_conflict,
  -- never a silent cross-account disclosure of another account's cargo/
  -- notes.
  if p_idempotency_key is not null then
    select * into v_existing from app.customer_portal_quote_requests where tenant_id = p_tenant_id and idempotency_key = p_idempotency_key;
    if found then
      if v_existing.account_id = p_account_id then
        return v_existing;
      end if;
      raise exception 'idempotency_key_conflict: key % was already used for a different account''s quote request %', p_idempotency_key, v_existing.id
        using errcode = 'unique_violation';
    end if;
  end if;

  if jsonb_typeof(v_origin) <> 'object' or jsonb_typeof(v_destination) <> 'object' then
    raise exception 'invalid_location: origin/destination must each be a JSON object' using errcode = 'check_violation';
  end if;

  if p_requested_pickup_date is not null and p_requested_delivery_date is not null and p_requested_delivery_date < p_requested_pickup_date then
    raise exception 'invalid_dates: requested_delivery_date cannot be before requested_pickup_date' using errcode = 'check_violation';
  end if;

  -- Tier C fix (C-01 discipline): a REAL exception handler, not merely a
  -- pre-check select -- two genuinely concurrent calls carrying the
  -- identical key can both pass the pre-check above before either commits;
  -- the race LOSER's own INSERT must recover via the SAME account-scoped
  -- re-select, never surface a raw unique_violation to the caller. Mirrors
  -- app._create_ticket (HRT-286) exactly.
  begin
    insert into app.customer_portal_quote_requests (
      tenant_id, account_id, requested_by_auth_user_id, cargo_description, origin, destination,
      service_type, requested_pickup_date, requested_delivery_date, notes, idempotency_key, created_by
    ) values (
      p_tenant_id, p_account_id, p_actor_auth_user_id, p_cargo_description, v_origin, v_destination,
      p_service_type, p_requested_pickup_date, p_requested_delivery_date, p_notes, p_idempotency_key, p_actor_label
    )
    returning * into v_request;
  exception
    when unique_violation then
      if p_idempotency_key is null then
        raise;
      end if;
      select * into v_request from app.customer_portal_quote_requests where tenant_id = p_tenant_id and idempotency_key = p_idempotency_key;
      if not found or v_request.account_id <> p_account_id then
        raise;
      end if;
      -- Race LOSER recovering onto the WINNER's already-committed row: return
      -- it as-is, exactly like the pre-check idempotent-return path above --
      -- never fall through to a second, spurious create_customer_quote_
      -- request_draft audit event for a row this call did not actually
      -- create. Mirrors app._create_ticket (HRT-286) exactly.
      return v_request;
  end;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'create_customer_quote_request_draft',
    'app.customer_portal_quote_requests', v_request.id, 'success', null, null, to_jsonb(v_request)
  );

  return v_request;
end;
$$;

comment on function app.create_customer_quote_request_draft is
  'CPL-302: creates a draft quote request. p_account_id must already be in app.resolve_customer_account_scope(actor, tenant) -- a forged/unowned id is rejected with the same account_not_available a nonexistent id would produce (mirrors app.create_customer_ticket, HRT-287). Idempotent on (tenant_id, idempotency_key) when a key is supplied -- a repeated call for the SAME account returns the existing row unchanged, regardless of its current status; the SAME key against a DIFFERENT account is a real idempotency_key_conflict, never a silent cross-account return (Tier C fix, C-01 discipline). The INSERT itself is wrapped in a real unique_violation handler, not only a pre-check, so a genuine two-process race on the same key converges on one row (Tier C fix).';

-- ===========================================================================
-- 4. app.update_customer_quote_request_draft -- draft-only
-- ===========================================================================

create function app.update_customer_quote_request_draft(
  p_request_id uuid,
  p_expected_version integer,
  p_cargo_description text,
  p_origin jsonb,
  p_destination jsonb,
  p_service_type text,
  p_requested_pickup_date date,
  p_requested_delivery_date date,
  p_notes text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.customer_portal_quote_requests
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_request app.customer_portal_quote_requests;
  v_updated app.customer_portal_quote_requests;
  v_origin jsonb := coalesce(p_origin, '{}'::jsonb);
  v_destination jsonb := coalesce(p_destination, '{}'::jsonb);
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  select * into v_request from app.customer_portal_quote_requests where id = p_request_id for update;
  if not found or not (v_request.account_id = any (app.resolve_customer_account_scope(p_actor_auth_user_id, v_request.tenant_id))) then
    raise exception 'record_not_found: no permitted quote request exists for %', p_request_id using errcode = 'no_data_found';
  end if;

  if v_request.status <> 'draft' then
    raise exception 'invalid_transition: quote request % is % and can no longer be edited', p_request_id, v_request.status
      using errcode = 'check_violation';
  end if;

  if v_request.record_version <> p_expected_version then
    raise exception 'stale_version: quote request % expected version % but found %', p_request_id, p_expected_version, v_request.record_version
      using errcode = 'serialization_failure';
  end if;

  if jsonb_typeof(v_origin) <> 'object' or jsonb_typeof(v_destination) <> 'object' then
    raise exception 'invalid_location: origin/destination must each be a JSON object' using errcode = 'check_violation';
  end if;

  if p_requested_pickup_date is not null and p_requested_delivery_date is not null and p_requested_delivery_date < p_requested_pickup_date then
    raise exception 'invalid_dates: requested_delivery_date cannot be before requested_pickup_date' using errcode = 'check_violation';
  end if;

  update app.customer_portal_quote_requests
  set cargo_description = p_cargo_description,
      origin = v_origin,
      destination = v_destination,
      service_type = p_service_type,
      requested_pickup_date = p_requested_pickup_date,
      requested_delivery_date = p_requested_delivery_date,
      notes = p_notes
  where id = p_request_id
  returning * into v_updated;

  perform app.capture_audit_event(
    v_updated.tenant_id, p_actor_auth_user_id, p_actor_label, 'update_customer_quote_request_draft',
    'app.customer_portal_quote_requests', v_updated.id, 'success', null, to_jsonb(v_request), to_jsonb(v_updated)
  );

  return v_updated;
end;
$$;

comment on function app.update_customer_quote_request_draft is
  'CPL-302: draft-only edit of cargo/route/service/dates/notes. Any active member of the request''s own account may edit it (design decision 9), not only its original requester. Optimistic concurrency via select ... for update + explicit stale_version raise (CPL-300''s own shape, no redundant WHERE predicate needed).';

-- ===========================================================================
-- 5. app.submit_customer_quote_request -- draft -> submitted
-- ===========================================================================

create function app.submit_customer_quote_request(
  p_request_id uuid,
  p_expected_version integer,
  p_idempotency_key text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.customer_portal_quote_requests
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_request app.customer_portal_quote_requests;
  v_updated app.customer_portal_quote_requests;
  v_conflict_id uuid;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  if p_idempotency_key is null or length(trim(p_idempotency_key)) = 0 then
    raise exception 'idempotency_key_required: a non-empty idempotency key is required to submit a quote request' using errcode = 'not_null_violation';
  end if;

  select * into v_request from app.customer_portal_quote_requests where id = p_request_id for update;
  if not found or not (v_request.account_id = any (app.resolve_customer_account_scope(p_actor_auth_user_id, v_request.tenant_id))) then
    raise exception 'record_not_found: no permitted quote request exists for %', p_request_id using errcode = 'no_data_found';
  end if;

  -- Idempotent retry: a repeated submit call carrying the SAME idempotency key
  -- this exact row already recorded returns it unchanged, regardless of the
  -- caller's own (now-stale) p_expected_version -- protects a genuine
  -- double-click/network-retry from a spurious stale_version/invalid_transition
  -- error (design decision 3).
  if v_request.status = 'submitted' and v_request.submitted_idempotency_key = p_idempotency_key then
    return v_request;
  end if;

  select id into v_conflict_id
  from app.customer_portal_quote_requests
  where tenant_id = v_request.tenant_id and account_id = v_request.account_id
    and submitted_idempotency_key = p_idempotency_key and id <> p_request_id;
  if found then
    raise exception 'idempotency_conflict: idempotency key already used by a different quote request % on this account', v_conflict_id
      using errcode = 'unique_violation';
  end if;

  if v_request.status <> 'draft' then
    raise exception 'invalid_transition: quote request % is % and cannot be submitted', p_request_id, v_request.status
      using errcode = 'check_violation';
  end if;

  if v_request.record_version <> p_expected_version then
    raise exception 'stale_version: quote request % expected version % but found %', p_request_id, p_expected_version, v_request.record_version
      using errcode = 'serialization_failure';
  end if;

  -- Tier C fix (spec-compliance): source prompt §23 ("Block ... unscanned
  -- file") and §24 ("Files remain private, scanned and scope-bound before
  -- any download or handoff") -- submission IS this capability's own
  -- "internal Commercial handoff" moment (source prompt §20). Checked only
  -- for a genuine draft -> submitted transition (after the status/version
  -- gates above), never ahead of a caller's own invalid_transition/
  -- stale_version error. Any attachment still pending/infected/error scan
  -- status blocks submission; a clean scan, or no attachment at all, does
  -- not.
  if exists (
    select 1 from app.files
    where record_type = 'customer_portal_quote_request'
      and record_id = p_request_id
      and tenant_id = v_request.tenant_id
      and lifecycle_status = 'active'
      and malware_scan_status <> 'clean'
  ) then
    raise exception 'unscanned_attachment: quote request % has an attachment that has not cleared malware scanning', p_request_id
      using errcode = 'check_violation';
  end if;

  update app.customer_portal_quote_requests
  set status = 'submitted', submitted_at = now(), submitted_idempotency_key = p_idempotency_key
  where id = p_request_id
  returning * into v_updated;

  perform app.capture_audit_event(
    v_updated.tenant_id, p_actor_auth_user_id, p_actor_label, 'submit_customer_quote_request',
    'app.customer_portal_quote_requests', v_updated.id, 'success', null, null, to_jsonb(v_updated)
  );

  return v_updated;
end;
$$;

comment on function app.submit_customer_quote_request is
  'CPL-302: draft -> submitted. p_idempotency_key is mandatory and unique per (tenant_id, account_id) -- a repeated call with the SAME key on the SAME already-submitted row is a no-op idempotent return; the SAME key against a DIFFERENT row on the same account is a real idempotency_conflict, never a silent overwrite. This is not a rated quote or price commitment (source prompt §24) -- it only hands the request to Commercial''s own intake queue for staff review. Tier C fix (spec-compliance): submission now blocks (unscanned_attachment) if any active attachment on this request has not cleared malware scanning (source prompt §23/§24) -- submission is this capability''s own "handoff" moment.';

-- ===========================================================================
-- 6. app.cancel_customer_quote_request -- draft | submitted -> cancelled
-- ===========================================================================

create function app.cancel_customer_quote_request(
  p_request_id uuid,
  p_expected_version integer,
  p_reason text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.customer_portal_quote_requests
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_request app.customer_portal_quote_requests;
  v_updated app.customer_portal_quote_requests;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'reason_required: a non-empty reason is required to cancel a quote request' using errcode = 'not_null_violation';
  end if;

  select * into v_request from app.customer_portal_quote_requests where id = p_request_id for update;
  if not found or not (v_request.account_id = any (app.resolve_customer_account_scope(p_actor_auth_user_id, v_request.tenant_id))) then
    raise exception 'record_not_found: no permitted quote request exists for %', p_request_id using errcode = 'no_data_found';
  end if;

  if v_request.status not in ('draft', 'submitted') then
    raise exception 'invalid_transition: quote request % is % and can no longer be cancelled', p_request_id, v_request.status
      using errcode = 'check_violation';
  end if;

  if v_request.record_version <> p_expected_version then
    raise exception 'stale_version: quote request % expected version % but found %', p_request_id, p_expected_version, v_request.record_version
      using errcode = 'serialization_failure';
  end if;

  update app.customer_portal_quote_requests
  set status = 'cancelled', cancelled_at = now(), cancelled_reason = p_reason
  where id = p_request_id
  returning * into v_updated;

  perform app.capture_audit_event(
    v_updated.tenant_id, p_actor_auth_user_id, p_actor_label, 'cancel_customer_quote_request',
    'app.customer_portal_quote_requests', v_updated.id, 'success', null, null, to_jsonb(v_updated)
  );

  return v_updated;
end;
$$;

comment on function app.cancel_customer_quote_request is
  'CPL-302: draft or submitted -> cancelled, mandatory non-empty reason. Cancellation before internal (staff) acceptance is always available to any account-scoped member -- once app.link_customer_quote_request_to_quotation has converted a request, it is terminal and this function correctly refuses it (invalid_transition).';

-- ===========================================================================
-- 7. app.get_customer_quote_request -- anti-enumerating get-by-id
-- ===========================================================================

create function app.get_customer_quote_request(p_tenant_id uuid, p_request_id uuid, p_actor_auth_user_id uuid)
returns app.customer_portal_quote_requests
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_request app.customer_portal_quote_requests;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  select * into v_request from app.customer_portal_quote_requests where id = p_request_id and tenant_id = p_tenant_id;
  if not found or not (v_request.account_id = any (app.resolve_customer_account_scope(p_actor_auth_user_id, p_tenant_id))) then
    raise exception 'record_not_found: no permitted quote request exists for %', p_request_id using errcode = 'no_data_found';
  end if;

  return v_request;
end;
$$;

comment on function app.get_customer_quote_request is
  'CPL-302: anti-enumerating get-by-id (ADR-0024 Part A) -- raises the IDENTICAL record_not_found (errcode no_data_found) whether p_request_id genuinely does not exist, belongs to a different tenant, or exists but its account is outside this identity''s resolved scope. Mirrors ATW-242''s app.get_customer_inventory_balance exactly.';

-- ===========================================================================
-- 8. app.list_customer_quote_requests -- keyset paginated
-- ===========================================================================

create function app.list_customer_quote_requests(
  p_tenant_id uuid,
  p_actor_auth_user_id uuid,
  p_account_id uuid default null,
  p_status text default null,
  p_cursor_updated_at timestamptz default null,
  p_cursor_id uuid default null,
  p_limit integer default 50
)
returns setof app.customer_portal_quote_requests
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
  from app.customer_portal_quote_requests r
  where r.tenant_id = p_tenant_id
    and r.account_id = any (v_scope)
    and (p_account_id is null or r.account_id = p_account_id)
    and (p_status is null or r.status = p_status)
    and (p_cursor_id is null or (r.updated_at, r.id) < (p_cursor_updated_at, p_cursor_id))
  order by r.updated_at desc, r.id desc
  limit v_limit;
end;
$$;

comment on function app.list_customer_quote_requests is
  'CPL-302: keyset-paginated (tenant_id, updated_at desc, id desc), never OFFSET, hard-capped at 200 -- mirrors app.list_customer_portal_account_memberships (CPL-300) exactly. Deny-by-default: zero scope or an out-of-scope p_account_id both return an empty result, never an error.';

-- ===========================================================================
-- 9. app.link_customer_quote_request_to_quotation -- staff, COM:Edit
--    (design decision 6, the ONLY staff-RBAC touchpoint in this migration)
-- ===========================================================================

create function app.link_customer_quote_request_to_quotation(
  p_request_id uuid,
  p_quotation_id uuid,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.customer_portal_quote_requests
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_request app.customer_portal_quote_requests;
  v_quotation app.quotations;
  v_decision app.rbac_decision;
  v_updated app.customer_portal_quote_requests;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  select * into v_request from app.customer_portal_quote_requests where id = p_request_id for update;
  -- Tier C fix (C-05 discipline): fold a tenant-standing check into the SAME
  -- not-found branch, BEFORE the specific-permission check, so an identity
  -- with zero relationship to this row's own tenant learns nothing beyond
  -- "this id does not exist" -- it never reaches a branch that echoes the
  -- row's real tenant_id. Mirrors app.get_rfq's own established fix
  -- (supabase/migrations/20260730670000_harden_procurement_batch_257_259_
  -- review_fixes.sql). "Standing" here is deliberately wider than app.
  -- get_rfq's own staff-only has_active_tenant_membership check alone: this
  -- RPC is reachable by BOTH a staff caller (has_active_tenant_membership)
  -- AND a genuine customer_user-layer caller with real portal scope in this
  -- tenant (resolve_customer_account_scope) -- that identity's own app.
  -- tenant_user_identities row is deliberately NEVER 'active' (design
  -- decision 4(b)), so has_active_tenant_membership alone would incorrectly
  -- treat every real customer identity as a non-member and leak nothing
  -- (fails closed) but ALSO wrongly hide insufficient_authority from a
  -- customer who is genuinely a member of this tenant, breaking a
  -- live-tested case (a customer, Layer 4, not staff, must still get
  -- insufficient_authority, never not_found). A caller satisfying EITHER
  -- predicate still reaches the informative insufficient_authority branch
  -- below (their own tenant_id is not new information to them); a caller
  -- satisfying NEITHER (e.g. a customer_user of a completely different
  -- tenant) gets the identical not-found error a missing row would produce.
  if not found or not (
    app.has_active_tenant_membership(v_request.tenant_id, p_actor_auth_user_id)
    or array_length(app.resolve_customer_account_scope(p_actor_auth_user_id, v_request.tenant_id), 1) is not null
  ) then
    raise exception 'quote_request_not_found: %', p_request_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_request.tenant_id, 'COM', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks COM:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_request.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_quotation from app.quotations where id = p_quotation_id and tenant_id = v_request.tenant_id;
  if not found then
    raise exception 'quotation_not_found: no quotation % in tenant %', p_quotation_id, v_request.tenant_id using errcode = 'no_data_found';
  end if;

  -- Idempotent: re-acknowledging the SAME (request, quotation) pair is a
  -- no-op return; converting an already-converted request to a DIFFERENT
  -- quotation is a real conflict, never a silent overwrite of canonical
  -- linkage evidence (source prompt §24: "never re-enters data silently").
  if v_request.status = 'converted' then
    if v_request.linked_quotation_id = p_quotation_id then
      return v_request;
    end if;
    raise exception 'already_converted: quote request % is already linked to quotation %, not %', p_request_id, v_request.linked_quotation_id, p_quotation_id
      using errcode = 'check_violation';
  end if;

  if v_request.status <> 'submitted' then
    raise exception 'invalid_transition: quote request % is % and cannot be converted (only a submitted request may be)', p_request_id, v_request.status
      using errcode = 'check_violation';
  end if;

  update app.customer_portal_quote_requests
  set status = 'converted', linked_quotation_id = p_quotation_id
  where id = p_request_id
  returning * into v_updated;

  perform app.capture_audit_event(
    v_updated.tenant_id, p_actor_auth_user_id, p_actor_label, 'link_customer_quote_request_to_quotation',
    'app.customer_portal_quote_requests', v_updated.id, 'success', null, to_jsonb(v_request), to_jsonb(v_updated)
  );

  return v_updated;
end;
$$;

comment on function app.link_customer_quote_request_to_quotation is
  'CPL-302: staff-only (COM:Edit), the sole conversion acknowledgement -- a submitted request becomes converted, linked_quotation_id set exactly once (cpqr_converted_requires_link enforces the pairing at the row level). Idempotent for the SAME (request, quotation) pair; a different quotation on an already-converted request is a real already_converted conflict. Disclosed scope boundary (design decision 6): app.quotations carries no app.accounts reference, so this function cannot structurally verify the linked quotation belongs to the same customer -- it relies on the COM:Edit-holding staff actor''s own authority over that quotation, the same trust app.add_quotation_line/app.submit_quotation already extend unconditionally. Tier C fix (C-05 discipline): the not-found branch now also requires has_active_tenant_membership on the row''s own tenant, BEFORE the COM:Edit check runs, so a non-member cannot learn the row''s real tenant_id from a distinguishable insufficient_authority error.';

-- ===========================================================================
-- 10. Attachments -- reuse PLT-128 (design decision 4)
-- ===========================================================================

insert into app.document_types (code, name, owner_primitive_code, registered_by)
values ('quote_request_attachment', 'Quote Request Attachment', 'CPT', 'system')
on conflict (code) do nothing;

insert into app.config_types (code, name, owner_primitive_code, registered_by)
values ('document:quote_request_attachment', 'Quote Request Attachment', 'CPT', 'system')
on conflict (code) do nothing;

-- Widen the existing (service_role-only) authority gate every PLT-128
-- mutating function composes -- identical signature, so its existing grant
-- is untouched by this CREATE OR REPLACE. See design decision 4(b) for why
-- this widening is both necessary (the unwidened gate is unconditionally
-- false for every customer_user identity) and safe (never reachable
-- directly by `authenticated`).
create or replace function app.check_file_action_authority(p_tenant_id uuid, p_actor_auth_user_id uuid)
returns boolean
language sql
stable
as $$
  select
    app.has_active_tenant_membership(p_tenant_id, p_actor_auth_user_id)
    or app.is_supreme_admin(p_actor_auth_user_id)
    or app.actor_holds_customer_user_layer(p_tenant_id, p_actor_auth_user_id);
$$;

comment on function app.check_file_action_authority is
  'PLT-128, widened by CPL-302 (design decision 4(b)): true for an active staff tenant member, a Supreme Admin, OR (new) an active customer_user-layer principal (app.actor_holds_customer_user_layer) -- necessary because a customer_user''s own app.tenant_user_identities row never reaches status=active (only the staff-only app.transition_user_status flips that), so the unwidened predicate was unconditionally false for every customer identity. Still service_role-only (grant unchanged by this CREATE OR REPLACE) -- never reachable directly by `authenticated`; the real per-record authorization decision is always made by the calling capability''s own server-side code before it reaches this function.';

create function app.list_customer_quote_request_files(p_tenant_id uuid, p_request_id uuid, p_actor_auth_user_id uuid)
returns table (
  id uuid,
  original_filename text,
  mime_type text,
  size_bytes bigint,
  malware_scan_status text,
  uploaded_by_auth_user_id uuid,
  created_at timestamptz
)
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_request app.customer_portal_quote_requests;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  -- Explicit alias (r0), never a bare column reference -- this function's own
  -- RETURNS TABLE column list auto-declares a PL/pgSQL variable named `id`,
  -- which would otherwise make `where id = ...` ambiguous against app.
  -- customer_portal_quote_requests.id (the exact defect class CPL-300's own
  -- header warns "made 7 RPCs 100% non-functional" in an earlier checkpoint).
  select * into v_request from app.customer_portal_quote_requests r0 where r0.id = p_request_id and r0.tenant_id = p_tenant_id;
  if not found or not (v_request.account_id = any (app.resolve_customer_account_scope(p_actor_auth_user_id, p_tenant_id))) then
    return;
  end if;

  return query
  select f.id, f.original_filename, f.mime_type, f.size_bytes, f.malware_scan_status, f.uploaded_by_auth_user_id, f.created_at
  from app.files f
  where f.record_type = 'customer_portal_quote_request'
    and f.record_id = p_request_id
    and f.tenant_id = p_tenant_id
    and f.lifecycle_status = 'active'
  order by f.created_at desc;
end;
$$;

comment on function app.list_customer_quote_request_files is
  'CPL-302: the ONLY sanctioned customer-facing attachment-metadata read path (design decision 4(b) -- app.authorize_file_access/app.can_access_record are deliberately NOT composed here, see that decision''s own disclosed rationale). SECURITY DEFINER, bypasses app.files'' own RLS directly (which a customer_user could never pass anyway) -- gated purely by this capability''s own account-scope resolver. Deny-by-default: an out-of-scope or nonexistent request returns an empty result, never an error (list convention, not get-by-id).';

-- ===========================================================================
-- 11. RLS -- enable, grant service_role only (design decision 5)
-- ===========================================================================

alter table app.customer_portal_quote_requests enable row level security;

grant select, insert, update, delete on app.customer_portal_quote_requests to service_role;

-- Per ERR-2026-004: explicit, directly-provable revoke of PostgreSQL's
-- PUBLIC-execute default before any role-specific grant (standing
-- per-migration convention since PLT-118).
revoke execute on all functions in schema app from public;

grant execute on function app.create_customer_quote_request_draft(uuid, uuid, text, jsonb, jsonb, text, date, date, text, text, uuid, text) to authenticated, service_role;
grant execute on function app.update_customer_quote_request_draft(uuid, integer, text, jsonb, jsonb, text, date, date, text, uuid, text) to authenticated, service_role;
grant execute on function app.submit_customer_quote_request(uuid, integer, text, uuid, text) to authenticated, service_role;
grant execute on function app.cancel_customer_quote_request(uuid, integer, text, uuid, text) to authenticated, service_role;
grant execute on function app.get_customer_quote_request(uuid, uuid, uuid) to authenticated, service_role;
grant execute on function app.list_customer_quote_requests(uuid, uuid, uuid, text, timestamptz, uuid, integer) to authenticated, service_role;
grant execute on function app.link_customer_quote_request_to_quotation(uuid, uuid, uuid, text) to authenticated, service_role;
grant execute on function app.list_customer_quote_request_files(uuid, uuid, uuid) to authenticated, service_role;
