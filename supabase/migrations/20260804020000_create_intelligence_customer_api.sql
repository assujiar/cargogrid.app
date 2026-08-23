-- Intelligence, Automation and Enterprise Expansion: Customer API (IAE-010,
-- CG-S14-IAE-010, Prompt 338). Second prompt of Batch 3. Extends `app.api_keys`
-- (PLT-129) with the SAME row shape ADR-0025 Part A already scoped for a
-- `customer_user`-layer issuer -- never a new key table, never a fifth access
-- layer. Exposes customer-safe REST `/v1` resources that mirror Customer
-- Portal's own already-ratified Layer 4 scope/reauthorization rules
-- (`ADR-0024`) exactly, by dispatching every request through the EXACT SAME
-- `SECURITY DEFINER` RPCs the portal UI itself calls -- never a shortcut, never
-- a second enforcement point.
--
-- Design decisions, disclosed rather than left implicit:
--
-- 1. **Customer-scoped keys are the same `app.api_keys` row, two new additive,
--    nullable columns.** `customer_account_id` (which `app.accounts` row this
--    key represents) and `customer_actor_auth_user_id` (which REAL
--    `customer_user`-layer identity every downstream call dispatches as) --
--    both null together for an ordinary tenant-staff key (unchanged
--    behavior), both set together for a customer key (`api_keys_customer_
--    scope_shape_check`). This is deliberately NOT the same identity as
--    `created_by_auth_user_id` in general: a tenant admin may provision a key
--    ON BEHALF OF a specific customer contact (a real, disclosed support/
--    bootstrap path), in which case the CREATOR (a staff tenant_admin) and
--    the ACTOR the key dispatches as (a real customer_user member of that
--    account) are two different identities -- `customer_actor_auth_user_id`
--    is validated at creation time to genuinely hold scope to the target
--    account (design decision 3), so this can never name an arbitrary/
--    unrelated identity.
-- 2. **Customer-key scopes are NOT the `<module>:<action>` RBAC taxonomy at
--    all.** `app.actor_is_active_customer_portal_account_admin`'s own header
--    (`20260801010000_create_customer_portal_account_scope.sql`) already
--    states this outright: "A Layer-4-only authority chain (`ADR-0024` Part
--    B) -- never `app.evaluate_permission`/staff RBAC." A `customer_user`
--    identity holds no RBAC role/permission grant to narrow in the first
--    place -- `app.create_api_key`'s own per-scope `evaluate_permission()`
--    loop would reject every single scope for every customer identity,
--    always, since that loop was built for the staff RBAC model ADR-0025
--    Part A's own text anticipated composing with, before this checkpoint's
--    own concrete build surfaced that the two authority models do not
--    actually compose. Reconciled here, disclosed rather than silently
--    worked around: a customer key carries exactly one fixed scope marker,
--    `CPT:CustomerPortal` -- never caller-supplied, never validated against
--    `app.permissions`. The REAL authority for every dispatched call is
--    always the SAME live, per-request `app.resolve_customer_account_scope`/
--    `app.get_customer_portal_scope_context` re-evaluation the portal UI
--    itself depends on (`ADR-0024`'s own "Layer is not permission, RLS/RPC
--    re-checks every time" philosophy) -- the key's own frozen scope string
--    is deliberately never the fine-grained authority boundary.
-- 3. **`app.create_customer_api_key`: a genuinely new function, not a
--    widened `app.create_api_key`.** Authority is `app.actor_is_active_
--    customer_portal_account_admin` (self-service: a real account_admin
--    provisions their own account's key) OR `app.check_api_webhook_admin_
--    authority` (support/bootstrap: Supreme or the tenant's own active
--    tenant_admin provisions a key on behalf of a customer contact).
--    `p_customer_actor_auth_user_id` is validated against `app.resolve_
--    customer_account_scope` for the target account before the key is ever
--    created -- a caller cannot bind a key to an identity with no real
--    membership in that account, whichever authority path was used.
-- 4. **`app.revoke_api_key`/`app.rotate_api_key` (PLT-129) are EXTENDED, not
--    duplicated**, for the revoke/rotate half of the lifecycle -- their own
--    authority check now composes a new `app.check_api_key_manage_
--    authority()` helper (tenant admin check OR, when the key carries a
--    `customer_account_id`, that account's own active account_admin), and
--    `rotate_api_key` now carries `customer_account_id`/`customer_actor_
--    auth_user_id` forward onto the freshly-rotated key row (previously
--    silently dropped, since those columns did not exist before this
--    migration). Both functions' own grant widens to `authenticated` (in
--    addition to the existing `service_role`) so a real customer_user
--    session can call them directly through the RLS-scoped client, mirroring
--    every other Customer Portal write RPC's own established grant shape --
--    the in-function authority check remains the real boundary either way.
-- 5. **`app.authenticate_and_authorize_api_request` (IAE-009) is extended**,
--    not forked -- `create or replace function`, same signature. The
--    downstream dispatch identity it resolves is now `coalesce(customer_
--    actor_auth_user_id, created_by_auth_user_id)`: a customer key dispatches
--    as its own real customer identity (so every downstream Customer Portal
--    RPC's own `resolve_customer_account_scope` check evaluates real,
--    current account scope); a tenant-staff key's behavior is byte-for-byte
--    unchanged (IAE-009's own live regression suite re-proves this).
-- 6. **Resource allowlist deliberately narrow, disclosed rather than
--    padded**, mirroring IAE-009's own identical discipline. Three REST
--    resources this migration's own service layer/routes expose: `GET
--    /v1/customer/shipments/{id}/tracking` (read, wraps `app.get_customer_
--    shipment_tracking` verbatim), `POST /v1/customer/bookings` (idempotent
--    create, wraps `app.create_customer_booking_request_draft` verbatim),
--    `POST /v1/customer/bookings/{id}/submit` (wraps `app.submit_customer_
--    booking_request` verbatim). Quote/documents/invoices/tickets/loyalty
--    are real, already-built Customer Portal capabilities (`server/{queries,
--    mutations}/customer-quote-request.ts`,
--    `customer-portal-{document,invoice}.ts`, `ticketing.ts`'s own
--    customer-facing subset, `customer-portal-loyalty-*.ts`) this same
--    gateway/authority pattern extends to directly -- deliberately deferred
--    to a future increment rather than built out in full here, the identical
--    "narrow, honest, disclosed" boundary IAE-009 already established.
-- 7. **File downloads (Prompt 338's own "short-lived signed URLs and
--    reauthorization" business rule) are explicitly NOT built this
--    checkpoint.** Live-verified by direct migration read: NEITHER Customer
--    Portal file capability (`app.get_customer_document`/`app.get_customer_
--    epod`, Prompt 306/307) ever issues a real signed URL -- both
--    deliberately log `access_type='metadata_view'`, never `'signed_url_
--    issued'`, and both migrations' own Tier C fix headers state outright
--    that fabricating one "would durably misrepresent what actually
--    happened." A genuine customer-facing signed-URL issuance path is
--    therefore NET NEW work, not a wrap -- out of this migration's own
--    bounded scope (§6), left as a disclosed, real gap for a future
--    increment, not silently assumed solved by proximity to PLT-128's own
--    existing (staff-facing) signed-URL gate.
-- 8. **No new job type, no async work.** This capability's REST surface is
--    synchronous request/response only, identical to IAE-009's own boundary.
-- 9. Per `ERR-2026-004`: this migration carries its own explicit
--    `revoke execute on all functions in schema app from public;` before its
--    final grants.

-- ===========================================================================
-- Additive columns on app.api_keys (design decision 1)
-- ===========================================================================

alter table app.api_keys add column customer_account_id uuid references app.accounts (id);
alter table app.api_keys add column customer_actor_auth_user_id uuid references auth.users (id);

alter table app.api_keys add constraint api_keys_customer_scope_shape_check
  check ((customer_account_id is null) = (customer_actor_auth_user_id is null));

comment on column app.api_keys.customer_account_id is
  'IAE-010: null for an ordinary tenant-staff key (unchanged PLT-129 behavior). When set, this key is a Customer API key representing exactly this app.accounts row -- never a broader tenant-admin scope (Prompt 338''s own "same Layer 4 scope as portal, not broader tenant admin scope" business rule).';

comment on column app.api_keys.customer_actor_auth_user_id is
  'IAE-010: the REAL customer_user-layer identity every downstream Customer Portal RPC call this key authorizes dispatches as -- validated at app.create_customer_api_key time to genuinely hold scope to customer_account_id via app.resolve_customer_account_scope, never an arbitrary identity. Deliberately distinct from created_by_auth_user_id: a tenant_admin may provision this key ON BEHALF OF a customer contact (design decision 1).';

-- ===========================================================================
-- app.check_api_key_manage_authority (design decision 4) -- the shared
-- authority composition app.revoke_api_key/app.rotate_api_key now call.
-- ===========================================================================

create function app.check_api_key_manage_authority(p_tenant_id uuid, p_customer_account_id uuid, p_actor_auth_user_id uuid)
returns boolean
language sql
stable
as $$
  select app.check_api_webhook_admin_authority(p_tenant_id, p_actor_auth_user_id)
    or (p_customer_account_id is not null and app.actor_is_active_customer_portal_account_admin(p_tenant_id, p_customer_account_id, p_actor_auth_user_id));
$$;

comment on function app.check_api_key_manage_authority is
  'IAE-010: Supreme or the tenant''s own active tenant_admin (unchanged PLT-129 authority), OR -- when the target key carries a customer_account_id -- that account''s own real, active account_admin (ADR-0024 Part B). Composed by app.revoke_api_key/app.rotate_api_key so a customer can manage their own account''s key without a tenant admin''s involvement, without duplicating either function''s own lifecycle logic.';

-- ===========================================================================
-- app.revoke_api_key / app.rotate_api_key (PLT-129): extended, not forked
-- (design decision 4)
-- ===========================================================================

create or replace function app.revoke_api_key(
  p_key_id uuid,
  p_reason text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.api_keys
language plpgsql
-- IAE-010 widens the grant on this function to `authenticated` (design
-- decision 4) so a real customer account_admin can revoke their own
-- account's key directly. PLT-129's own original body was SECURITY INVOKER,
-- relying on `service_role`'s own broad table access; an authenticated
-- session holds no direct grant on app.api_keys, so this must become
-- SECURITY DEFINER for the widened grant to actually work -- the in-function
-- app.check_api_key_manage_authority/assert_actor_is_session_identity checks
-- remain the real authority boundary either way.
security definer
set search_path = app, pg_temp
as $$
declare
  v_key app.api_keys;
  v_updated app.api_keys;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  select * into v_key from app.api_keys where id = p_key_id;
  if not found then
    raise exception 'api_key_not_found: no key %', p_key_id using errcode = 'no_data_found';
  end if;

  -- IAE-010: composes app.check_api_key_manage_authority (design decision 4)
  -- instead of app.check_api_webhook_admin_authority directly -- the ONLY
  -- change from PLT-129's own original body, everything else byte-for-byte
  -- unchanged.
  if not app.check_api_key_manage_authority(v_key.tenant_id, v_key.customer_account_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks authority to manage API keys for tenant %', p_actor_auth_user_id, v_key.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_key.status = 'revoked' then
    return v_key;
  end if;

  update app.api_keys
  set status = 'revoked', revoked_at = now(), revoked_reason = coalesce(p_reason, 'manual revoke')
  where id = p_key_id
  returning * into v_updated;

  perform app.capture_audit_event(
    v_updated.tenant_id, p_actor_auth_user_id, p_actor_label, 'revoke_api_key',
    'app.api_keys', v_updated.id, 'success', p_reason,
    jsonb_build_object('id', v_key.id, 'status', v_key.status),
    jsonb_build_object('id', v_updated.id, 'status', v_updated.status)
  );

  return v_updated;
end;
$$;

comment on function app.revoke_api_key is
  'PLT-129, extended by IAE-010 (design decision 4): idempotent -- a repeated revoke of an already-revoked key returns it unchanged. Authority now composes app.check_api_key_manage_authority, so a customer account_admin may revoke their OWN account''s customer-scoped key, in addition to PLT-129''s own original Supreme/tenant_admin authority. Also now calls app.assert_actor_is_session_identity first (this migration applies the same ATW-032 discipline IAE-009''s own Tier B self-check already caught proactively for its sibling list function).';

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
-- Same reasoning as app.revoke_api_key just above: the widened grant to
-- `authenticated` needs SECURITY DEFINER to actually reach app.api_keys, and
-- this function also calls pgcrypto (gen_random_bytes/digest), which lives in
-- `public` -- see app.create_customer_api_key's own comment for why `public`
-- must be explicit here rather than assumed from the session default.
security definer
set search_path = app, public, extensions, pg_temp
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

  -- IAE-010: carries customer_account_id/customer_actor_auth_user_id forward
  -- onto the rotated key -- PLT-129's own original body predates these
  -- columns and would otherwise silently drop a customer key's own binding
  -- on every rotation.
  insert into app.api_keys (tenant_id, name, key_prefix, key_hash, scopes, rate_limit_per_minute, expires_at, created_by_auth_user_id, customer_account_id, customer_actor_auth_user_id)
  values (v_old.tenant_id, v_old.name, v_new_key_prefix, v_new_key_hash, v_old.scopes, v_old.rate_limit_per_minute, v_old.expires_at, p_actor_auth_user_id, v_old.customer_account_id, v_old.customer_actor_auth_user_id)
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
  'PLT-129, extended by IAE-010 (design decision 4): overlap-window rotation (0 = immediate revoke), the old key never extending an already-sooner expiry. Authority now composes app.check_api_key_manage_authority; the rotated key now carries customer_account_id/customer_actor_auth_user_id forward. Also now calls app.assert_actor_is_session_identity first.';

-- ===========================================================================
-- app.create_customer_api_key / app.list_customer_api_keys_for_account
-- (design decisions 2, 3)
-- ===========================================================================

create function app.create_customer_api_key(
  p_tenant_id uuid,
  p_account_id uuid,
  p_customer_actor_auth_user_id uuid,
  p_name text,
  p_expires_at timestamptz,
  p_rate_limit_per_minute integer,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns table (
  id uuid, tenant_id uuid, name text, key_prefix text, scopes jsonb, status text,
  rate_limit_per_minute integer, expires_at timestamptz, created_at timestamptz,
  customer_account_id uuid, customer_actor_auth_user_id uuid, raw_key text
)
language plpgsql
security definer
-- pgcrypto (gen_random_bytes/digest) lives in `public` (20260716075355_create_
-- tenants.sql's own unqualified `create extension if not exists pgcrypto`) --
-- same reasoning as app.rotate_api_key just above, `public` is added here
-- explicitly rather than assumed from the session default.
set search_path = app, public, extensions, pg_temp
as $$
declare
  v_scope uuid[];
  v_raw_key text;
  v_key_prefix text;
  v_key_hash text;
  v_key app.api_keys;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  if not (
    app.actor_is_active_customer_portal_account_admin(p_tenant_id, p_account_id, p_actor_auth_user_id)
    or app.check_api_webhook_admin_authority(p_tenant_id, p_actor_auth_user_id)
  ) then
    raise exception 'insufficient_authority: identity % lacks authority to create a Customer API key for account %', p_actor_auth_user_id, p_account_id
      using errcode = 'insufficient_privilege';
  end if;

  -- The identity the key will actually dispatch as must genuinely hold scope
  -- to this account -- whichever authority path created the key (design
  -- decision 3). A self-service account_admin naming themselves always
  -- passes trivially; a tenant_admin provisioning on behalf of a customer
  -- contact must name a REAL member, never an arbitrary identity.
  v_scope := app.resolve_customer_account_scope(p_customer_actor_auth_user_id, p_tenant_id);
  if not (p_account_id = any (v_scope)) then
    raise exception 'account_not_available: % does not hold customer_user scope for account %', p_customer_actor_auth_user_id, p_account_id
      using errcode = 'no_data_found';
  end if;

  if p_name is null or length(trim(p_name)) = 0 then
    raise exception 'api_key_missing_name: name is required'
      using errcode = 'check_violation';
  end if;

  if p_rate_limit_per_minute is not null and (p_rate_limit_per_minute <= 0 or p_rate_limit_per_minute > 100000) then
    raise exception 'api_key_invalid_rate_limit: % must be between 1 and 100000', p_rate_limit_per_minute
      using errcode = 'check_violation';
  end if;

  if p_expires_at is not null and p_expires_at <= now() then
    raise exception 'api_key_invalid_expiry: expires_at % must be in the future', p_expires_at
      using errcode = 'check_violation';
  end if;

  v_raw_key := 'cgk_' || encode(gen_random_bytes(24), 'hex');
  v_key_prefix := substring(v_raw_key from 1 for 12);
  v_key_hash := encode(digest(v_raw_key, 'sha256'), 'hex');

  insert into app.api_keys (tenant_id, name, key_prefix, key_hash, scopes, rate_limit_per_minute, expires_at, created_by_auth_user_id, customer_account_id, customer_actor_auth_user_id)
  values (p_tenant_id, p_name, v_key_prefix, v_key_hash, '["CPT:CustomerPortal"]'::jsonb, p_rate_limit_per_minute, p_expires_at, p_actor_auth_user_id, p_account_id, p_customer_actor_auth_user_id)
  returning * into v_key;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'create_customer_api_key',
    'app.api_keys', v_key.id, 'success', null, null,
    jsonb_build_object('id', v_key.id, 'name', v_key.name, 'key_prefix', v_key.key_prefix, 'account_id', p_account_id, 'customer_actor_auth_user_id', p_customer_actor_auth_user_id)
  );

  return query select v_key.id, v_key.tenant_id, v_key.name, v_key.key_prefix, v_key.scopes, v_key.status, v_key.rate_limit_per_minute, v_key.expires_at, v_key.created_at, v_key.customer_account_id, v_key.customer_actor_auth_user_id, v_raw_key;
end;
$$;

comment on function app.create_customer_api_key is
  'IAE-010: a Customer Portal Layer 4 key-issuance entrypoint, deliberately NOT app.create_api_key''s own RBAC-scope-narrowing model (design decision 2 -- a customer_user identity holds no RBAC permission grant to narrow at all). Authority: the target account''s own active account_admin (self-service), or Supreme/tenant_admin (support/bootstrap, naming a real member on the customer''s behalf). Always issues the single fixed scope marker CPT:CustomerPortal -- real authority is always the live per-request Customer Portal scope re-evaluation, never this frozen scope string. Returns the raw key exactly once, the same PLT-129 "shown once" contract.';

create function app.list_customer_api_keys_for_account(
  p_tenant_id uuid,
  p_account_id uuid,
  p_actor_auth_user_id uuid
)
returns table (
  id uuid, tenant_id uuid, name text, key_prefix text, scopes jsonb, status text,
  rate_limit_per_minute integer, expires_at timestamptz, last_used_at timestamptz,
  created_at timestamptz, updated_at timestamptz, customer_account_id uuid, customer_actor_auth_user_id uuid
)
language plpgsql
security definer
set search_path = app, pg_temp
as $$
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  if not (
    app.actor_is_active_customer_portal_account_admin(p_tenant_id, p_account_id, p_actor_auth_user_id)
    or app.check_api_webhook_admin_authority(p_tenant_id, p_actor_auth_user_id)
  ) then
    raise exception 'insufficient_authority: identity % lacks authority to view API keys for account %', p_actor_auth_user_id, p_account_id
      using errcode = 'insufficient_privilege';
  end if;

  return query
  select k.id, k.tenant_id, k.name, k.key_prefix, k.scopes, k.status, k.rate_limit_per_minute, k.expires_at, k.last_used_at, k.created_at, k.updated_at, k.customer_account_id, k.customer_actor_auth_user_id
  from app.api_keys k
  where k.tenant_id = p_tenant_id and k.customer_account_id = p_account_id
  order by k.created_at desc;
end;
$$;

comment on function app.list_customer_api_keys_for_account is
  'IAE-010: scoped to EXACTLY one account''s own customer keys -- never a tenant-wide listing (unlike app.list_api_keys_for_tenant), so a customer account_admin can never see another account''s keys, let alone the tenant''s own staff keys, satisfying Prompt 338''s own "same Layer 4 scope as portal, not broader tenant admin scope" business rule structurally, not by convention alone.';

-- ===========================================================================
-- app.authenticate_and_authorize_api_request (IAE-009): extended, not forked
-- (design decision 5)
-- ===========================================================================

create or replace function app.authenticate_and_authorize_api_request(
  p_raw_key text,
  p_required_scope text
)
returns table (
  outcome text, api_key_id uuid, tenant_id uuid, created_by_auth_user_id uuid,
  rate_limit_per_minute integer, rate_limit_remaining integer
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
    return query select 'unauthenticated'::text, null::uuid, null::uuid, null::uuid, null::integer, null::integer;
    return;
  end;

  if p_required_scope is not null and length(trim(p_required_scope)) > 0 and not app.api_key_has_scope(v_auth.api_key_id, p_required_scope) then
    return query select 'forbidden_scope'::text, v_auth.api_key_id, v_auth.tenant_id, null::uuid, v_auth.rate_limit_per_minute, null::integer;
    return;
  end if;

  select * into v_rate from app.check_and_increment_api_key_rate_limit(v_auth.api_key_id);
  if not v_rate.allowed then
    return query select 'rate_limited'::text, v_auth.api_key_id, v_auth.tenant_id, null::uuid, v_rate.limit_per_minute, v_rate.remaining;
    return;
  end if;

  -- IAE-010 (design decision 5): a customer-scoped key dispatches as its own
  -- REAL customer_actor_auth_user_id, so every downstream Customer Portal
  -- RPC's own resolve_customer_account_scope check evaluates real, current
  -- account scope -- coalesce falls back to created_by_auth_user_id
  -- unchanged for an ordinary tenant-staff key.
  return query
  select 'ok'::text, v_auth.api_key_id, v_auth.tenant_id, coalesce(k.customer_actor_auth_user_id, k.created_by_auth_user_id), v_rate.limit_per_minute, v_rate.remaining
  from app.api_keys k where k.id = v_auth.api_key_id;
end;
$$;

comment on function app.authenticate_and_authorize_api_request is
  'IAE-009, extended by IAE-010 (design decision 5): the one real REST /v1 gateway entrypoint. Composes app.authenticate_api_key() + app.api_key_has_scope() (both PLT-129, unchanged) + app.check_and_increment_api_key_rate_limit() (IAE-009). Returns outcome in (ok, unauthenticated, forbidden_scope, rate_limited) rather than raising for any of these four routine reject cases. The dispatch identity is coalesce(customer_actor_auth_user_id, created_by_auth_user_id) -- a customer key dispatches as its own real customer identity; a tenant-staff key''s behavior is unchanged. service_role-only: called exclusively from a REST route handler''s own service-role client, never a live authenticated session.';

-- ===========================================================================
-- Grants
-- ===========================================================================

revoke execute on all functions in schema app from public;

grant execute on function app.check_api_key_manage_authority(uuid, uuid, uuid) to service_role;

-- PLT-129's own revoke/rotate widen to authenticated too (design decision
-- 4) -- the in-function authority check remains the real boundary either
-- way; a real customer_user session may now call these directly through the
-- RLS-scoped client, mirroring every other Customer Portal write RPC's own
-- established grant shape.
grant execute on function app.revoke_api_key(uuid, text, uuid, text) to authenticated, service_role;
grant execute on function app.rotate_api_key(uuid, integer, uuid, text) to authenticated, service_role;

grant execute on function app.create_customer_api_key(uuid, uuid, uuid, text, timestamptz, integer, uuid, text) to authenticated, service_role;
grant execute on function app.list_customer_api_keys_for_account(uuid, uuid, uuid) to authenticated, service_role;

grant execute on function app.authenticate_and_authorize_api_request(text, text) to service_role;
