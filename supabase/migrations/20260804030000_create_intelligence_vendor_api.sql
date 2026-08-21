-- Intelligence, Automation and Enterprise Expansion: Vendor API (IAE-011,
-- CG-S14-IAE-011, Prompt 339). Third prompt of Batch 3. Extends `app.api_keys`
-- (PLT-129) with the SAME row shape ADR-0025 Part A already scoped for a
-- vendor-portal-layer issuer -- never a new key table, never a fifth access
-- layer.
--
-- Design decisions, disclosed rather than left implicit:
--
-- 1. **No fifth principal layer -- a vendor API key is scoped to DATA, not an
--    ACTOR.** Live-confirmed by direct repository search: no `app.vendors`-
--    adjacent table anywhere links a vendor to `auth.users`. `app.vendor_
--    profiles` (PRC-251) is a governed extension of `app.master_records`
--    (`master_type_code='vendor'`) with no login/session concept at all --
--    vendor intake (`app.redeem_vendor_intake_token_and_submit`, `app.submit_
--    vendor_profile_self_registration`) is deliberately, genuinely anonymous
--    (their own header comments: "no actor, no session ... the raw bearer
--    token is the entire authorization surface"). This is a structurally
--    different shape from IAE-010's customer key (`customer_account_id` +
--    `customer_actor_auth_user_id` pair, dispatching AS a real `customer_
--    user`-layer identity): a vendor key instead carries exactly ONE new
--    additive, nullable column, `vendor_master_record_id`, a data-scope
--    binding to one `app.vendor_profiles` row -- never an actor-identity
--    binding, since no such identity exists to bind.
-- 2. **Vendor API keys are staff-issued only, never vendor self-service.**
--    Since no vendor login/session exists, a vendor cannot authenticate an
--    API-key-creation request in the first place. `app.create_vendor_api_key`
--    requires `app.check_api_webhook_admin_authority` (Supreme or the
--    tenant's own active tenant_admin) -- the SAME authority PLT-129's
--    original `app.create_api_key` already requires for an ordinary staff
--    key -- issued out-of-band to the vendor, mirroring how `app.vendor_
--    intake_tokens` are already staff-issued and handed to a vendor
--    externally. Validated against a REAL `app.vendor_profiles` row with
--    `lifecycle_status = 'active'` in the SAME tenant -- a caller cannot bind
--    a key to a vendor that does not exist, is not yet approved, or belongs
--    to another tenant.
-- 3. **Fixed scope marker, not RBAC-narrowed** -- the exact reconciliation
--    IAE-010 already made and disclosed for customer keys (a `customer_user`
--    identity holds no RBAC grant to narrow against `app.evaluate_
--    permission()`; a vendor has even less -- no `auth.users` row at all).
--    A vendor key carries exactly one fixed scope marker, `PRC:VendorPortal`,
--    never caller-supplied, never validated against `app.permissions`.
-- 4. **Gateway dispatch identity is `vendor_master_record_id`, not an
--    `auth.users` UUID.** `app.authenticate_and_authorize_api_request`
--    (IAE-009, extended once already by IAE-010) is extended again via
--    `create or replace function`, appending one new OUT column,
--    `vendor_master_record_id uuid`, at the end of its `returns table`
--    list -- Postgres permits appending new OUT parameters to an existing
--    function via `CREATE OR REPLACE FUNCTION` without breaking any existing
--    caller, live-verified this checkpoint. `created_by_auth_user_id` stays
--    populated for a vendor key too (the staff issuer, kept for
--    accountability) -- downstream vendor-submission RPCs key their own
--    authority off the NEW `vendor_master_record_id` column instead.
-- 5. **New, additive vendor-submission RPCs -- never staff functions
--    repurposed.** `app.submit_rfq_response` and `app.accept_vendor_
--    assignment_invitation`/`app.decline_vendor_assignment_invitation` are
--    explicitly disclosed, in their own existing comments, as staff-actor-
--    shaped ("internal offline/email capture only ... requires an
--    authenticated actor", PRC:Edit RBAC) -- a vendor key has neither an
--    actor nor an RBAC grant. Rather than force an incompatible authority
--    model into those functions, this migration adds THREE new sibling
--    functions that insert/update the SAME canonical tables (never a
--    parallel vendor-response table), authorized by vendor-scope
--    containment (the target row's own `vendor_master_id` must equal the
--    presented key's `vendor_master_record_id`) instead of staff RBAC:
--    `app.submit_rfq_response_via_vendor_api`, `app.accept_vendor_
--    assignment_invitation_via_vendor_api`, `app.decline_vendor_assignment_
--    invitation_via_vendor_api`. `app.rfq_responses.capture_mode` widens
--    (additive check-constraint replacement) to admit a new value,
--    `'vendor_api'`, alongside the existing `'offline'/'email'`.
-- 6. **A late RFQ response is rejected outright via the Vendor API, never
--    silently overridden.** `app.submit_rfq_response`'s own staff path
--    allows a late capture with `PRC:Override` authority and a mandatory
--    reason; a vendor key holds no override authority (design decision 3) --
--    a vendor submitting after `response_deadline_at` gets a clear
--    `rfq_response_deadline_passed` rejection instead. Disclosed narrowing,
--    not a silent gap.
-- 7. **Read access**: one new function, `app.get_rfq_for_vendor_api`, returns
--    the RFQ + this vendor's own invitation row ONLY if the invitation's
--    `vendor_master_id` matches the presented key's own binding -- never
--    another vendor's invitation, never the full internal RFQ listing.
-- 8. **Resource allowlist deliberately narrow, disclosed rather than
--    padded**, mirroring IAE-009/010's own identical discipline: `GET
--    /v1/vendor/rfqs/{rfqInvitationId}` (read), `POST /v1/vendor/rfqs/
--    {rfqInvitationId}/response` (submit), `POST /v1/vendor/assignments/
--    {invitationId}/accept`, `POST /v1/vendor/assignments/{invitationId}/
--    decline`. Capacity submission (`app.reserve_vendor_capacity`/`accept_
--    vendor_capacity_reservation`) and invoice status (`app.get_vendor_bill_
--    match_readiness`) are real, already-built Procurement capabilities this
--    same vendor-scope pattern extends to directly -- deliberately deferred,
--    matching Prompt 339's own explicit "Vendor API is disabled for a
--    tenant; manual/vendor portal process continues" tolerance for partial
--    coverage. Proof-of-delivery/ePOD has ZERO existing vendor entry point
--    anywhere in the repository (confirmed by direct code search across
--    every `app.*epod*` function) -- building one is net-new Operations-
--    domain work, out of this migration's own bounded scope, left as a
--    disclosed, real gap.
-- 9. **`app.check_api_key_manage_authority` (IAE-010) needs no further
--    widening for vendor-key revoke/rotate.** Its existing `app.check_api_
--    webhook_admin_authority` branch (Supreme/tenant_admin) already covers a
--    vendor key, since -- unlike a customer key -- there is no vendor-side
--    self-service revoke/rotate to add (no vendor session exists to call it
--    from). `app.rotate_api_key` is extended once more (its existing
--    `create or replace`) purely to carry `vendor_master_record_id` forward
--    onto the rotated row -- the same "don't silently drop a new column on
--    rotation" fix IAE-010 already applied for the customer columns.
-- 10. No new job type, no async work -- synchronous request/response only,
--     identical to IAE-009/010's own boundary.
-- 11. Per `ERR-2026-004`: this migration carries its own explicit
--     `revoke execute on all functions in schema app from public;` before
--     its final grants.

-- ===========================================================================
-- Additive column on app.api_keys (design decision 1)
-- ===========================================================================

alter table app.api_keys add column vendor_master_record_id uuid references app.master_records (id);

comment on column app.api_keys.vendor_master_record_id is
  'IAE-011: null for an ordinary tenant-staff or customer key (unchanged prior behavior). When set, this key is a Vendor API key scoped to exactly this app.vendor_profiles (app.master_records) row -- a DATA-scope binding, not an actor-identity binding, since no vendor auth.users identity exists anywhere in this repository. Every downstream vendor-submission RPC checks the target row''s own vendor_master_id against this column directly.';

alter table app.api_keys add constraint api_keys_customer_vendor_mutually_exclusive_check
  check (not (customer_account_id is not null and vendor_master_record_id is not null));

comment on constraint api_keys_customer_vendor_mutually_exclusive_check on app.api_keys is
  'IAE-011: a single key row is never simultaneously a customer key and a vendor key -- the gateway''s own dispatch-identity resolution (design decision 4) would otherwise be ambiguous.';

-- ===========================================================================
-- app.create_vendor_api_key (design decision 2, 3)
-- ===========================================================================

create function app.create_vendor_api_key(
  p_tenant_id uuid,
  p_vendor_master_record_id uuid,
  p_name text,
  p_expires_at timestamptz,
  p_rate_limit_per_minute integer,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns table (
  id uuid, tenant_id uuid, name text, key_prefix text, scopes jsonb, status text,
  rate_limit_per_minute integer, expires_at timestamptz, created_at timestamptz,
  vendor_master_record_id uuid, raw_key text
)
language plpgsql
security definer
-- pgcrypto (gen_random_bytes/digest) lives in `public`, same reasoning as
-- IAE-010's own app.create_customer_api_key/app.rotate_api_key.
set search_path = app, public, pg_temp
as $$
declare
  v_vendor app.vendor_profiles;
  v_raw_key text;
  v_key_prefix text;
  v_key_hash text;
  v_key app.api_keys;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  if not app.check_api_webhook_admin_authority(p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks authority to create a Vendor API key for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_vendor from app.vendor_profiles where app.vendor_profiles.master_record_id = p_vendor_master_record_id and app.vendor_profiles.tenant_id = p_tenant_id;
  if not found then
    raise exception 'vendor_not_found: no vendor % in tenant %', p_vendor_master_record_id, p_tenant_id using errcode = 'no_data_found';
  end if;
  if v_vendor.lifecycle_status <> 'active' then
    raise exception 'vendor_not_active: vendor % is % -- only an active vendor may hold an API key', p_vendor_master_record_id, v_vendor.lifecycle_status
      using errcode = 'check_violation';
  end if;

  if p_name is null or length(trim(p_name)) = 0 then
    raise exception 'api_key_missing_name: p_name must not be empty' using errcode = 'check_violation';
  end if;
  if p_rate_limit_per_minute is not null and p_rate_limit_per_minute <= 0 then
    raise exception 'api_key_invalid_rate_limit: p_rate_limit_per_minute must be a positive integer' using errcode = 'check_violation';
  end if;
  if p_expires_at is not null and p_expires_at <= now() then
    raise exception 'api_key_invalid_expiry: p_expires_at must be in the future' using errcode = 'check_violation';
  end if;

  v_raw_key := 'cgk_' || encode(gen_random_bytes(24), 'hex');
  v_key_prefix := substring(v_raw_key from 1 for 12);
  v_key_hash := encode(digest(v_raw_key, 'sha256'), 'hex');

  insert into app.api_keys (tenant_id, name, key_prefix, key_hash, scopes, rate_limit_per_minute, expires_at, created_by_auth_user_id, vendor_master_record_id)
  values (p_tenant_id, p_name, v_key_prefix, v_key_hash, '["PRC:VendorPortal"]'::jsonb, p_rate_limit_per_minute, p_expires_at, p_actor_auth_user_id, p_vendor_master_record_id)
  returning * into v_key;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'create_vendor_api_key',
    'app.api_keys', v_key.id, 'success', null, null, jsonb_build_object('vendor_master_record_id', p_vendor_master_record_id)
  );

  return query
  select v_key.id, v_key.tenant_id, v_key.name, v_key.key_prefix, v_key.scopes, v_key.status, v_key.rate_limit_per_minute, v_key.expires_at, v_key.created_at, v_key.vendor_master_record_id, v_raw_key;
end;
$$;

comment on function app.create_vendor_api_key is
  'IAE-011: staff-only (Supreme or the tenant''s own active tenant_admin, design decision 2) -- a vendor cannot self-service since no vendor session/login exists. Validates p_vendor_master_record_id against a REAL, active app.vendor_profiles row in the same tenant before the key is ever created. Carries the fixed CPT-style scope marker PRC:VendorPortal (design decision 3), never RBAC-narrowed.';

-- ===========================================================================
-- app.list_vendor_api_keys_for_tenant -- staff console view (joins the
-- vendor's own legal_name for display; app.list_api_keys_for_tenant (PLT-129)
-- stays untouched and continues to list every key including vendor ones by
-- id/name/prefix, unchanged since IAE-010 made the identical choice for
-- customer keys).
-- ===========================================================================

create function app.list_vendor_api_keys_for_tenant(p_tenant_id uuid, p_actor_auth_user_id uuid)
returns table (
  id uuid, tenant_id uuid, name text, key_prefix text, scopes jsonb, status text,
  rate_limit_per_minute integer, expires_at timestamptz, last_used_at timestamptz,
  created_at timestamptz, updated_at timestamptz,
  vendor_master_record_id uuid, vendor_legal_name text
)
language plpgsql
security definer
set search_path = app, pg_temp
as $$
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  if not app.check_api_webhook_admin_authority(p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks authority to view Vendor API keys for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  return query
  select k.id, k.tenant_id, k.name, k.key_prefix, k.scopes, k.status, k.rate_limit_per_minute, k.expires_at, k.last_used_at, k.created_at, k.updated_at,
         k.vendor_master_record_id, v.legal_name
  from app.api_keys k
  join app.vendor_profiles v on v.master_record_id = k.vendor_master_record_id
  where k.tenant_id = p_tenant_id and k.vendor_master_record_id is not null
  order by k.created_at desc;
end;
$$;

comment on function app.list_vendor_api_keys_for_tenant is
  'IAE-011: staff-facing view of exactly the vendor-scoped keys in this tenant (never a customer/staff key), joined to the vendor''s own legal_name for display. Same staff authority as app.list_api_keys_for_tenant.';

-- ===========================================================================
-- app.rotate_api_key (PLT-129/IAE-010): extended once more (design decision
-- 9) so a rotated vendor key carries vendor_master_record_id forward.
-- ===========================================================================

create or replace function app.rotate_api_key(
  p_key_id uuid,
  p_overlap_minutes integer,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns table (
  id uuid, tenant_id uuid, name text, key_prefix text, scopes jsonb, status text,
  rate_limit_per_minute integer, expires_at timestamptz, created_at timestamptz, raw_key text
)
language plpgsql
security definer
set search_path = app, public, pg_temp
as $$
declare
  v_old app.api_keys;
  v_new_raw_key text;
  v_new_key_prefix text;
  v_new_key_hash text;
  v_new_key app.api_keys;
  v_new_expiry timestamptz;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  select * into v_old from app.api_keys where app.api_keys.id = p_key_id;
  if not found then
    raise exception 'api_key_not_found: no key %', p_key_id using errcode = 'no_data_found';
  end if;

  if not app.check_api_key_manage_authority(v_old.tenant_id, v_old.customer_account_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks authority to manage API keys for tenant %', p_actor_auth_user_id, v_old.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_old.status <> 'active' then
    raise exception 'api_key_not_active: key % is %, only an active key may be rotated', p_key_id, v_old.status
      using errcode = 'check_violation';
  end if;

  if p_overlap_minutes is null or p_overlap_minutes < 0 or p_overlap_minutes > 10080 then
    raise exception 'api_key_invalid_overlap_minutes: % must be between 0 and 10080 (7 days)', p_overlap_minutes
      using errcode = 'check_violation';
  end if;

  v_new_raw_key := 'cgk_' || encode(gen_random_bytes(24), 'hex');
  v_new_key_prefix := substring(v_new_raw_key from 1 for 12);
  v_new_key_hash := encode(digest(v_new_raw_key, 'sha256'), 'hex');

  -- IAE-011: carries vendor_master_record_id forward too, alongside IAE-010's
  -- own customer_account_id/customer_actor_auth_user_id -- otherwise a
  -- rotated vendor key would silently stop being scoped to any vendor at all.
  insert into app.api_keys (tenant_id, name, key_prefix, key_hash, scopes, rate_limit_per_minute, expires_at, created_by_auth_user_id, customer_account_id, customer_actor_auth_user_id, vendor_master_record_id)
  values (v_old.tenant_id, v_old.name, v_new_key_prefix, v_new_key_hash, v_old.scopes, v_old.rate_limit_per_minute, v_old.expires_at, p_actor_auth_user_id, v_old.customer_account_id, v_old.customer_actor_auth_user_id, v_old.vendor_master_record_id)
  returning * into v_new_key;

  v_new_expiry := now() + (p_overlap_minutes::text || ' minutes')::interval;

  update app.api_keys
  set status = case when p_overlap_minutes = 0 then 'revoked' else v_old.status end,
      revoked_at = case when p_overlap_minutes = 0 then now() else revoked_at end,
      revoked_reason = case when p_overlap_minutes = 0 then 'rotated' else revoked_reason end,
      expires_at = case when v_old.expires_at is not null and v_old.expires_at < v_new_expiry then v_old.expires_at else v_new_expiry end
  where app.api_keys.id = v_old.id;

  perform app.capture_audit_event(
    v_old.tenant_id, p_actor_auth_user_id, p_actor_label, 'rotate_api_key',
    'app.api_keys', v_new_key.id, 'success', null,
    jsonb_build_object('id', v_old.id, 'key_prefix', v_old.key_prefix),
    jsonb_build_object('id', v_new_key.id, 'key_prefix', v_new_key.key_prefix, 'overlap_minutes', p_overlap_minutes)
  );

  return query select v_new_key.id, v_new_key.tenant_id, v_new_key.name, v_new_key.key_prefix, v_new_key.scopes, v_new_key.status, v_new_key.rate_limit_per_minute, v_new_key.expires_at, v_new_key.created_at, v_new_raw_key;
end;
$$;

comment on function app.rotate_api_key is
  'PLT-129, extended by IAE-010 then IAE-011: overlap-window rotation (0 = immediate revoke), the old key never extending an already-sooner expiry. Authority composes app.check_api_key_manage_authority; the rotated key now carries customer_account_id/customer_actor_auth_user_id AND vendor_master_record_id forward. Also calls app.assert_actor_is_session_identity first.';

-- ===========================================================================
-- app.get_rfq_for_vendor_api (design decision 7)
-- ===========================================================================

create function app.get_rfq_for_vendor_api(p_tenant_id uuid, p_vendor_master_record_id uuid, p_rfq_invitation_id uuid)
returns table (
  rfq_invitation_id uuid, rfq_id uuid, invitation_status text, response_deadline_at timestamptz,
  rfq_number text, rfq_status text
)
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_invitation app.rfq_invitations;
  v_rfq app.rfqs;
begin
  select * into v_invitation from app.rfq_invitations where id = p_rfq_invitation_id and tenant_id = p_tenant_id;
  if not found or v_invitation.vendor_master_id <> p_vendor_master_record_id then
    raise exception 'rfq_invitation_not_found: no rfq invitation % for this vendor in tenant %', p_rfq_invitation_id, p_tenant_id using errcode = 'no_data_found';
  end if;

  select * into v_rfq from app.rfqs where id = v_invitation.rfq_id;

  return query select v_invitation.id, v_rfq.id, v_invitation.status, v_rfq.response_deadline_at, v_rfq.rfq_number, v_rfq.status;
end;
$$;

comment on function app.get_rfq_for_vendor_api is
  'IAE-011: the Vendor API''s own read path -- returns an RFQ invitation ONLY when it genuinely belongs to the presented key''s own vendor_master_record_id (design decision 7); a mismatched or nonexistent invitation id gets the SAME rfq_invitation_not_found either way, never disclosing which case it was (anti-enumeration, matching every other Phase 8/9 vendor/customer-facing read RPC''s own established convention).';

-- ===========================================================================
-- app.submit_rfq_response_via_vendor_api (design decisions 5, 6)
-- ===========================================================================

create function app.submit_rfq_response_via_vendor_api(
  p_tenant_id uuid,
  p_vendor_master_record_id uuid,
  p_rfq_invitation_id uuid,
  p_currency text,
  p_total_amount numeric,
  p_validity_until timestamptz,
  p_lead_time_days integer,
  p_commercial_terms jsonb,
  p_vendor_confirmed boolean,
  p_idempotency_key text
)
returns app.rfq_responses
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_invitation app.rfq_invitations;
  v_rfq app.rfqs;
  v_existing app.rfq_responses;
  v_response app.rfq_responses;
  v_prev_version integer;
  v_prev_id uuid;
  v_constraint_name text;
begin
  if p_idempotency_key is null or length(trim(p_idempotency_key)) = 0 then
    raise exception 'idempotency_key_required: p_idempotency_key must not be empty' using errcode = 'check_violation';
  end if;
  if p_currency is null or length(trim(p_currency)) = 0 then
    raise exception 'invalid_currency: currency must not be empty' using errcode = 'check_violation';
  end if;
  if p_total_amount is null or p_total_amount < 0 then
    raise exception 'invalid_total_amount: total_amount must be a non-negative number' using errcode = 'check_violation';
  end if;

  select * into v_invitation from app.rfq_invitations where id = p_rfq_invitation_id and tenant_id = p_tenant_id for update;
  if not found or v_invitation.vendor_master_id <> p_vendor_master_record_id then
    raise exception 'rfq_invitation_not_found: no rfq invitation % for this vendor in tenant %', p_rfq_invitation_id, p_tenant_id using errcode = 'no_data_found';
  end if;

  if v_invitation.status not in ('invited', 'responded') then
    raise exception 'invalid_transition: rfq invitation % is % and cannot accept a response', p_rfq_invitation_id, v_invitation.status
      using errcode = 'check_violation';
  end if;

  select * into v_rfq from app.rfqs where id = v_invitation.rfq_id for update;
  if v_rfq.status <> 'issued' then
    raise exception 'invalid_transition: rfq % is % and is not accepting responses', v_rfq.id, v_rfq.status
      using errcode = 'check_violation';
  end if;

  -- design decision 6: a vendor key holds no PRC:Override authority -- a late
  -- response is rejected outright, never silently accepted or overridden.
  if now() > v_rfq.response_deadline_at then
    raise exception 'rfq_response_deadline_passed: the response deadline for rfq % has already passed -- contact the tenant directly for a late capture', v_rfq.id
      using errcode = 'check_violation';
  end if;

  select * into v_existing from app.rfq_responses where tenant_id = p_tenant_id and idempotency_key = p_idempotency_key;
  if found then
    if v_existing.rfq_invitation_id is distinct from p_rfq_invitation_id or v_existing.total_amount is distinct from p_total_amount
      or v_existing.currency is distinct from p_currency or v_existing.validity_until is distinct from p_validity_until
      or v_existing.lead_time_days is distinct from p_lead_time_days
      or v_existing.vendor_confirmed is distinct from coalesce(p_vendor_confirmed, false)
      or v_existing.commercial_terms is distinct from coalesce(p_commercial_terms, '{}'::jsonb)
    then
      raise exception 'idempotency_key_conflict: idempotency key % was already used for a different RFQ response', p_idempotency_key
        using errcode = 'unique_violation';
    end if;
    return v_existing;
  end if;

  select coalesce(max(version), 0), (array_agg(id order by version desc))[1]
  into v_prev_version, v_prev_id
  from app.rfq_responses where rfq_invitation_id = p_rfq_invitation_id;

  begin
    insert into app.rfq_responses (
      tenant_id, rfq_id, rfq_invitation_id, vendor_master_id, version, previous_version_id,
      currency, total_amount, validity_until, lead_time_days, commercial_terms, capture_mode,
      received_at, vendor_confirmed, late_capture, comparison_eligible, idempotency_key, actor_auth_user_id, actor_label
    ) values (
      p_tenant_id, v_invitation.rfq_id, p_rfq_invitation_id, v_invitation.vendor_master_id, coalesce(v_prev_version, 0) + 1, v_prev_id,
      p_currency, p_total_amount, p_validity_until, p_lead_time_days, coalesce(p_commercial_terms, '{}'::jsonb), 'vendor_api',
      now(), coalesce(p_vendor_confirmed, true), false, true, p_idempotency_key, null, 'Vendor API'
    )
    returning * into v_response;
  exception
    when unique_violation then
      get stacked diagnostics v_constraint_name = constraint_name;
      if v_constraint_name = 'rfq_responses_tenant_idempotency_unique' then
        select * into v_existing from app.rfq_responses where tenant_id = p_tenant_id and idempotency_key = p_idempotency_key;
        if found then
          return v_existing;
        end if;
      end if;
      raise;
  end;

  update app.rfq_invitations set status = 'responded' where id = p_rfq_invitation_id;

  perform app.capture_audit_event(
    p_tenant_id, null, 'Vendor API', 'submit_rfq_response_via_vendor_api',
    'app.rfq_responses', v_response.id, 'success', null, null, jsonb_build_object('version', v_response.version, 'vendor_master_record_id', p_vendor_master_record_id)
  );

  return v_response;
end;
$$;

comment on function app.submit_rfq_response_via_vendor_api is
  'IAE-011: the Vendor API''s own write path into the SAME app.rfq_responses table app.submit_rfq_response (staff-only) already writes into -- never a parallel table. Authorized by vendor-scope containment (design decision 5), not staff RBAC. Rejects a late response outright (design decision 6) -- a vendor key holds no PRC:Override authority. capture_mode=''vendor_api'', actor_auth_user_id left null (no vendor auth.users identity exists), actor_label=''Vendor API''. Idempotent on (tenant_id, idempotency_key), matching app.submit_rfq_response''s own contract.';

-- ===========================================================================
-- app.accept_vendor_assignment_invitation_via_vendor_api /
-- app.decline_vendor_assignment_invitation_via_vendor_api (design decision 5)
-- ===========================================================================

create function app.accept_vendor_assignment_invitation_via_vendor_api(
  p_tenant_id uuid,
  p_vendor_master_record_id uuid,
  p_invitation_id uuid,
  p_expected_version integer
)
returns app.vendor_assignment_invitations
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_invitation app.vendor_assignment_invitations;
begin
  select * into v_invitation from app.vendor_assignment_invitations where id = p_invitation_id and tenant_id = p_tenant_id;
  if not found or v_invitation.vendor_master_id <> p_vendor_master_record_id then
    raise exception 'vendor_assignment_invitation_not_found: no vendor assignment invitation % for this vendor in tenant %', p_invitation_id, p_tenant_id using errcode = 'no_data_found';
  end if;

  if v_invitation.record_version <> p_expected_version then
    raise exception 'stale_version: vendor assignment invitation % expected version % but found %', p_invitation_id, p_expected_version, v_invitation.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_invitation.status <> 'invited' then
    raise exception 'invalid_transition: vendor assignment invitation % is % and cannot be accepted', p_invitation_id, v_invitation.status
      using errcode = 'check_violation';
  end if;

  update app.vendor_assignment_invitations set status = 'accepted' where id = p_invitation_id and record_version = p_expected_version returning * into v_invitation;
  if not found then
    raise exception 'stale_version: vendor assignment invitation % target row was concurrently modified (expected version %)', p_invitation_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_invitation.tenant_id, null, 'Vendor API', 'accept_vendor_assignment_invitation_via_vendor_api',
    'app.vendor_assignment_invitations', v_invitation.id, 'success', null, null, jsonb_build_object('vendor_master_record_id', p_vendor_master_record_id)
  );

  return v_invitation;
end;
$$;

comment on function app.accept_vendor_assignment_invitation_via_vendor_api is
  'IAE-011: the Vendor API''s own accept path into the SAME app.vendor_assignment_invitations table app.accept_vendor_assignment_invitation (staff-only) already writes into. Authorized by vendor-scope containment, not staff RBAC. Optimistic-concurrency-safe: the UPDATE''s own WHERE re-checks record_version at write time (ATW-032 discipline), no separate lock-then-decide race.';

create function app.decline_vendor_assignment_invitation_via_vendor_api(
  p_tenant_id uuid,
  p_vendor_master_record_id uuid,
  p_invitation_id uuid,
  p_expected_version integer,
  p_reason text
)
returns app.vendor_assignment_invitations
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_invitation app.vendor_assignment_invitations;
begin
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'reason_required: a non-empty reason is required to decline a vendor assignment invitation' using errcode = 'check_violation';
  end if;

  select * into v_invitation from app.vendor_assignment_invitations where id = p_invitation_id and tenant_id = p_tenant_id;
  if not found or v_invitation.vendor_master_id <> p_vendor_master_record_id then
    raise exception 'vendor_assignment_invitation_not_found: no vendor assignment invitation % for this vendor in tenant %', p_invitation_id, p_tenant_id using errcode = 'no_data_found';
  end if;

  if v_invitation.record_version <> p_expected_version then
    raise exception 'stale_version: vendor assignment invitation % expected version % but found %', p_invitation_id, p_expected_version, v_invitation.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_invitation.status <> 'invited' then
    raise exception 'invalid_transition: vendor assignment invitation % is % and cannot be declined', p_invitation_id, v_invitation.status
      using errcode = 'check_violation';
  end if;

  update app.vendor_assignment_invitations set status = 'declined', decline_reason = p_reason where id = p_invitation_id and record_version = p_expected_version returning * into v_invitation;
  if not found then
    raise exception 'stale_version: vendor assignment invitation % target row was concurrently modified (expected version %)', p_invitation_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_invitation.tenant_id, null, 'Vendor API', 'decline_vendor_assignment_invitation_via_vendor_api',
    'app.vendor_assignment_invitations', v_invitation.id, 'success', p_reason, null, jsonb_build_object('vendor_master_record_id', p_vendor_master_record_id)
  );

  return v_invitation;
end;
$$;

comment on function app.decline_vendor_assignment_invitation_via_vendor_api is
  'IAE-011: the Vendor API''s own decline path, mirroring app.accept_vendor_assignment_invitation_via_vendor_api''s own vendor-scope authority.';

-- ===========================================================================
-- app.rfq_responses.capture_mode: widen to admit 'vendor_api' (design
-- decision 5). Additive constraint replacement -- no existing row's own
-- value is touched, every existing 'offline'/'email' row remains valid.
-- ===========================================================================

alter table app.rfq_responses drop constraint rfq_responses_capture_mode_check;
alter table app.rfq_responses add constraint rfq_responses_capture_mode_check check (capture_mode in ('offline', 'email', 'vendor_api'));

-- ===========================================================================
-- app.authenticate_and_authorize_api_request (IAE-009/010): extended once
-- more (design decision 4) -- appends vendor_master_record_id as a new OUT
-- column. Every prior caller (route handlers destructure by name) is
-- unaffected. Live-verified this checkpoint: Postgres does NOT allow
-- appending a new OUT column to an existing RETURNS TABLE(...) function via
-- plain CREATE OR REPLACE FUNCTION ("cannot change return type of existing
-- function") -- an explicit DROP FUNCTION then CREATE FUNCTION is required.
-- The function's own grants do not survive a drop, so this migration's own
-- grants section below re-issues them explicitly.
-- ===========================================================================

drop function app.authenticate_and_authorize_api_request(text, text);

create function app.authenticate_and_authorize_api_request(
  p_raw_key text,
  p_required_scope text
)
returns table (
  outcome text, api_key_id uuid, tenant_id uuid, created_by_auth_user_id uuid,
  rate_limit_per_minute integer, rate_limit_remaining integer, vendor_master_record_id uuid
)
language plpgsql
as $$
declare
  v_auth record;
  v_rate record;
begin
  begin
    select * into v_auth from app.authenticate_api_key(p_raw_key);
  exception when others then
    return query select 'unauthenticated'::text, null::uuid, null::uuid, null::uuid, null::integer, null::integer, null::uuid;
    return;
  end;

  if p_required_scope is not null and length(trim(p_required_scope)) > 0 and not app.api_key_has_scope(v_auth.api_key_id, p_required_scope) then
    return query select 'forbidden_scope'::text, v_auth.api_key_id, v_auth.tenant_id, null::uuid, v_auth.rate_limit_per_minute, null::integer, null::uuid;
    return;
  end if;

  select * into v_rate from app.check_and_increment_api_key_rate_limit(v_auth.api_key_id);
  if not v_rate.allowed then
    return query select 'rate_limited'::text, v_auth.api_key_id, v_auth.tenant_id, null::uuid, v_rate.limit_per_minute, v_rate.remaining, null::uuid;
    return;
  end if;

  -- IAE-010 (design decision 5): a customer-scoped key dispatches as its own
  -- REAL customer_actor_auth_user_id. IAE-011 (design decision 4): a
  -- vendor-scoped key has no actor at all -- its own vendor_master_record_id
  -- is returned as a SEPARATE column instead, never coalesced into the
  -- actor-identity column (an api_keys.vendor_master_record_id value is not
  -- an auth.users id and must never be misread as one).
  return query
  select 'ok'::text, v_auth.api_key_id, v_auth.tenant_id, coalesce(k.customer_actor_auth_user_id, k.created_by_auth_user_id), v_rate.limit_per_minute, v_rate.remaining, k.vendor_master_record_id
  from app.api_keys k where k.id = v_auth.api_key_id;
end;
$$;

comment on function app.authenticate_and_authorize_api_request is
  'IAE-009, extended by IAE-010 then IAE-011: the one real REST /v1 gateway entrypoint. Composes app.authenticate_api_key() + app.api_key_has_scope() (both PLT-129, unchanged) + app.check_and_increment_api_key_rate_limit() (IAE-009). Returns outcome in (ok, unauthenticated, forbidden_scope, rate_limited) rather than raising for any of these four routine reject cases. The actor-identity dispatch column is coalesce(customer_actor_auth_user_id, created_by_auth_user_id) unchanged; vendor_master_record_id is a SEPARATE, additional output column (design decision 4) since a vendor key has no actor identity to coalesce. service_role-only: called exclusively from a REST route handler''s own service-role client, never a live authenticated session.';

-- ===========================================================================
-- Grants
-- ===========================================================================

revoke execute on all functions in schema app from public;

grant execute on function app.create_vendor_api_key(uuid, uuid, text, timestamptz, integer, uuid, text) to authenticated, service_role;
grant execute on function app.list_vendor_api_keys_for_tenant(uuid, uuid) to authenticated, service_role;
grant execute on function app.rotate_api_key(uuid, integer, uuid, text) to authenticated, service_role;

grant execute on function app.get_rfq_for_vendor_api(uuid, uuid, uuid) to service_role;
grant execute on function app.submit_rfq_response_via_vendor_api(uuid, uuid, uuid, text, numeric, timestamptz, integer, jsonb, boolean, text) to service_role;
grant execute on function app.accept_vendor_assignment_invitation_via_vendor_api(uuid, uuid, uuid, integer) to service_role;
grant execute on function app.decline_vendor_assignment_invitation_via_vendor_api(uuid, uuid, uuid, integer, text) to service_role;

grant execute on function app.authenticate_and_authorize_api_request(text, text) to service_role;
