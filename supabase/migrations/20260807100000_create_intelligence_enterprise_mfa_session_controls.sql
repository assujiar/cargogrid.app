-- IAE-027 (Prompt 355, Group 7): Enterprise MFA and Session Controls.
--
-- Design decisions (cited, not re-derived):
--
-- 1. Real MFA FACTOR enrollment/challenge-verification crypto (TOTP secret
--    generation, WebAuthn ceremony) is Supabase Auth's own native, external
--    infrastructure (`auth.mfa_factors`/`auth.mfa_amr_claims` in a real
--    deployment) -- the same "auth.users is Supabase-managed, never created by
--    this repo's own migrations" boundary IAE-026's own header already
--    established for identity. This checkpoint does NOT fabricate a parallel
--    `app.mfa_factors` table. What IS real and built here: the STEP-UP
--    GOVERNANCE layer -- which actions are high-risk, whether a fresh,
--    already-completed MFA verification exists for the acting identity, and a
--    real, composable assertion (`app.assert_current_step_up_authorization`)
--    any future high-risk mutation can call. `app.verify_mfa_step_up_challenge`
--    records that verification succeeded (reported by a caller who has itself
--    already completed the real challenge via Supabase's own client-side MFA
--    flow); it does not re-derive or check a TOTP code itself.
-- 2. New `SEC` entitlement module (`Configure`/`View`/`Approve`), shared across
--    Group 7's own "Enterprise Security" workstream (355-357: MFA/session,
--    IP restriction, advanced audit) -- distinct from `IAM` (354, identity
--    federation only), seeded here as its first user.
-- 3. High-risk actions are a fixed platform-default set (`app.
--    is_high_risk_action`) plus a real, tenant-editable additive list
--    (`app.mfa_tenant_policies.additional_high_risk_actions`) -- no separate
--    registry table needed, mirroring the "open jsonb list" shape several
--    prior capabilities already used for a similarly small, tenant-editable
--    set (e.g. IAE-013's own n8n action allowlist).
-- 4. Session/device tracking (`app.user_sessions`) is a DECLARED registry, not
--    a shadow of Supabase's own real JWT/refresh-token internals -- an
--    authenticated client reports a new session at login; revoking it here is
--    a real, persisted signal an application-layer guard can check, but
--    actually invalidating a live Supabase JWT requires the external Supabase
--    Admin API (`auth.admin.signOut`), disclosed as not performed by this
--    checkpoint -- the same class of external-system boundary IAE-026's own
--    SCIM "cannot mint a new auth.users row" gap already established.
-- 5. "Session revocation propagates to API keys" (Prompt 355 §24) is real:
--    `app.revoke_all_actor_sessions` also revokes every ACTIVE `app.api_keys`
--    row `created_by_auth_user_id`-owned by the target actor, composing the
--    existing, unmodified `app.revoke_api_key` (`PLT-129`).
-- 6. MFA exceptions (lost-factor recovery) mirror `app.support_access_grants`'
--    own established break-glass shape (`PLT-115`): never self-approved, a
--    real higher-authority approval step, a short CHECK-enforced expiry, and
--    exactly-once consumption.
-- 7. Every authenticated-reachable function is `SECURITY DEFINER` paired with
--    `app.assert_actor_is_session_identity` as its first statement.
-- 8. Per the standing convention since `PLT-118`: explicit, redundant
--    `revoke execute on all functions in schema app from public`.

-- ===========================================================================
-- 1. SEC entitlement module.
-- ===========================================================================

insert into app.entitlement_modules (code, name, owning_phase) values
  ('SEC', 'Enterprise security governance: MFA/session controls, IP restriction, advanced audit', 9);

insert into app.permissions (action, resource_module_code, category, protected) values
  ('Configure', 'SEC', 'admin', false),
  ('View', 'SEC', 'standard', false),
  ('Approve', 'SEC', 'workflow', false);

-- ===========================================================================
-- 2. app.mfa_tenant_policies -- one row per tenant, real governance state.
-- ===========================================================================

create table app.mfa_tenant_policies (
  tenant_id uuid primary key references app.tenants (id),
  tenant_wide_required boolean not null default false,
  required_layers jsonb not null default '["supreme_admin", "tenant_admin"]'::jsonb,
  step_up_max_age_minutes integer not null default 15,
  additional_high_risk_actions jsonb not null default '[]'::jsonb,
  updated_by text,
  updated_at timestamptz not null default now(),
  record_version integer not null default 1,
  constraint mfa_tenant_policies_step_up_max_age_check check (step_up_max_age_minutes between 1 and 1440)
);

comment on table app.mfa_tenant_policies is
  'IAE-027: real, persisted MFA policy per tenant. required_layers/tenant_wide_required govern WHO must have an enrolled factor (enforced by a future login-flow check against Supabase''s own real MFA state, disclosed not built here); step_up_max_age_minutes/additional_high_risk_actions govern the step-up gate this checkpoint DOES fully enforce (app.assert_current_step_up_authorization).';

create function app.touch_mfa_tenant_policy_row()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  new.record_version := old.record_version + 1;
  return new;
end;
$$;

create trigger mfa_tenant_policies_touch_row
  before update on app.mfa_tenant_policies
  for each row
  execute function app.touch_mfa_tenant_policy_row();

create function app._get_or_create_mfa_tenant_policy(p_tenant_id uuid)
returns app.mfa_tenant_policies
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_policy app.mfa_tenant_policies;
begin
  select * into v_policy from app.mfa_tenant_policies where tenant_id = p_tenant_id;
  if found then
    return v_policy;
  end if;
  insert into app.mfa_tenant_policies (tenant_id) values (p_tenant_id)
  returning * into v_policy;
  return v_policy;
end;
$$;

comment on function app._get_or_create_mfa_tenant_policy is
  'IAE-027: internal-only bootstrap primitive, no actor/authority parameter -- never granted to anon/authenticated. Called internally by app.set_mfa_tenant_policy (already SEC:Configure-gated) and by the actor-gated app.get_or_create_mfa_tenant_policy below.';

create function app.get_or_create_mfa_tenant_policy(p_tenant_id uuid, p_actor_auth_user_id uuid)
returns app.mfa_tenant_policies
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'SEC', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks SEC:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  return app._get_or_create_mfa_tenant_policy(p_tenant_id);
end;
$$;

comment on function app.get_or_create_mfa_tenant_policy is
  'IAE-027: idempotent default-row bootstrap, SEC:View-gated -- a tenant with no explicit policy yet still has real, sensible defaults (not merely an absent row an application would have to special-case). Originally shipped with no actor/authority parameter at all (any authenticated identity of any tenant could read, and silently bootstrap, another tenant''s own MFA policy) -- caught and fixed by this checkpoint''s own ATW-032/ISS-2026-033 authority-surface sweep before ever being committed.';

create function app.set_mfa_tenant_policy(
  p_tenant_id uuid,
  p_tenant_wide_required boolean,
  p_required_layers jsonb,
  p_step_up_max_age_minutes integer,
  p_additional_high_risk_actions jsonb,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.mfa_tenant_policies
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_policy app.mfa_tenant_policies;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'SEC', 'Configure');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks SEC:Configure (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if p_step_up_max_age_minutes not between 1 and 1440 then
    raise exception 'mfa_invalid_step_up_max_age: % must be between 1 and 1440 minutes', p_step_up_max_age_minutes using errcode = 'check_violation';
  end if;

  if not app.validate_config_value(coalesce(p_additional_high_risk_actions, '[]'::jsonb)) then
    raise exception 'mfa_unsafe_additional_high_risk_actions: failed structural validation' using errcode = 'check_violation';
  end if;

  perform app._get_or_create_mfa_tenant_policy(p_tenant_id);

  update app.mfa_tenant_policies
  set tenant_wide_required = p_tenant_wide_required,
      required_layers = coalesce(p_required_layers, required_layers),
      step_up_max_age_minutes = p_step_up_max_age_minutes,
      additional_high_risk_actions = coalesce(p_additional_high_risk_actions, additional_high_risk_actions),
      updated_by = p_actor_label
  where tenant_id = p_tenant_id
  returning * into v_policy;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'set_mfa_tenant_policy',
    'app.mfa_tenant_policies', null, 'success', null, null, to_jsonb(v_policy)
  );

  return v_policy;
end;
$$;

-- ===========================================================================
-- 3. High-risk action classification -- a fixed platform-default set plus a
-- real, tenant-editable additive list (design decision 3).
-- ===========================================================================

create function app.is_high_risk_action(p_tenant_id uuid, p_module_code text, p_action text)
returns boolean
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_policy app.mfa_tenant_policies;
  v_platform_default boolean;
begin
  v_platform_default := (p_module_code, p_action) in (
    ('AI', 'Approve'), ('IAM', 'Configure'), ('SEC', 'Configure'), ('SEC', 'Approve'),
    ('FIN', 'Approve'), ('HRS', 'Approve'), ('INTHUB', 'Configure')
  );
  if v_platform_default then
    return true;
  end if;

  select * into v_policy from app.mfa_tenant_policies where tenant_id = p_tenant_id;
  if not found then
    return false;
  end if;

  return exists (
    select 1 from jsonb_array_elements(v_policy.additional_high_risk_actions) as elem
    where elem ->> 'moduleCode' = p_module_code and elem ->> 'action' = p_action
  );
end;
$$;

comment on function app.is_high_risk_action is
  'IAE-027: the platform-default high-risk set is deliberately small and fixed (module-level Approve/Configure actions with a real financial/legal/security/identity blast radius) -- a tenant''s own additional_high_risk_actions list (app.mfa_tenant_policies) can only ADD to it, never narrow it, mirroring the "scope can only narrow, never widen" discipline app.create_api_key already established for a different resource.';

-- ===========================================================================
-- 4. app.mfa_step_up_challenges -- the real, enforced governance state
-- machine. app.assert_current_step_up_authorization is the composable
-- primitive a future high-risk mutation would call.
-- ===========================================================================

create table app.mfa_step_up_challenges (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  auth_user_id uuid not null references auth.users (id),
  module_code text not null,
  action text not null,
  status text not null default 'pending',
  challenge_issued_at timestamptz not null default now(),
  challenge_expires_at timestamptz not null default (now() + interval '10 minutes'),
  verified_at timestamptz,
  constraint mfa_step_up_challenges_status_check check (status in ('pending', 'verified', 'expired', 'failed'))
);

create index mfa_step_up_challenges_actor_action_idx on app.mfa_step_up_challenges (auth_user_id, module_code, action, verified_at desc);
create index mfa_step_up_challenges_tenant_id_idx on app.mfa_step_up_challenges (tenant_id, challenge_issued_at desc);

create function app.request_mfa_step_up_challenge(
  p_tenant_id uuid,
  p_module_code text,
  p_action text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.mfa_step_up_challenges
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_challenge app.mfa_step_up_challenges;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  if not app.has_active_tenant_membership(p_tenant_id, p_actor_auth_user_id) and not app.is_supreme_admin(p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % has no active membership in tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if not app.is_high_risk_action(p_tenant_id, p_module_code, p_action) then
    raise exception 'mfa_step_up_not_required: %:% is not classified as a high-risk action for tenant %', p_module_code, p_action, p_tenant_id
      using errcode = 'check_violation';
  end if;

  insert into app.mfa_step_up_challenges (tenant_id, auth_user_id, module_code, action)
  values (p_tenant_id, p_actor_auth_user_id, p_module_code, p_action)
  returning * into v_challenge;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'request_mfa_step_up_challenge',
    'app.mfa_step_up_challenges', v_challenge.id, 'success', null, null,
    jsonb_build_object('module_code', p_module_code, 'action', p_action)
  );

  return v_challenge;
end;
$$;

create function app.verify_mfa_step_up_challenge(
  p_challenge_id uuid,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.mfa_step_up_challenges
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_challenge app.mfa_step_up_challenges;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  select * into v_challenge from app.mfa_step_up_challenges where id = p_challenge_id and auth_user_id = p_actor_auth_user_id and status = 'pending' for update;
  if not found then
    raise exception 'mfa_step_up_challenge_not_pending: % is not a pending challenge for this identity', p_challenge_id
      using errcode = 'no_data_found';
  end if;

  if v_challenge.challenge_expires_at < now() then
    -- Deliberately does NOT persist status = 'expired' here: a caller that
    -- wraps this call in its own exception handler (the normal, expected
    -- shape) runs inside an implicit savepoint, and Postgres rolls back
    -- EVERY statement since that savepoint -- including this function's own
    -- prior UPDATE -- once the RAISE below propagates. Persisting "expired"
    -- lazily, on the next read that notices a stale pending row past its own
    -- challenge_expires_at, is the same pattern app.authenticate_api_key
    -- (PLT-129) already established for its own past-expiry status flip.
    raise exception 'mfa_step_up_challenge_expired: % expired at %', p_challenge_id, v_challenge.challenge_expires_at
      using errcode = 'check_violation';
  end if;

  update app.mfa_step_up_challenges
  set status = 'verified', verified_at = now()
  where id = p_challenge_id
  returning * into v_challenge;

  perform app.capture_audit_event(
    v_challenge.tenant_id, p_actor_auth_user_id, p_actor_label, 'verify_mfa_step_up_challenge',
    'app.mfa_step_up_challenges', v_challenge.id, 'success', null, null, to_jsonb(v_challenge)
  );

  return v_challenge;
end;
$$;

create function app.assert_current_step_up_authorization(
  p_tenant_id uuid,
  p_actor_auth_user_id uuid,
  p_module_code text,
  p_action text
)
returns void
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_policy app.mfa_tenant_policies;
  v_max_age_minutes integer;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  if not app.is_high_risk_action(p_tenant_id, p_module_code, p_action) then
    return;
  end if;

  select * into v_policy from app.mfa_tenant_policies where tenant_id = p_tenant_id;
  v_max_age_minutes := coalesce(v_policy.step_up_max_age_minutes, 15);

  if not exists (
    select 1 from app.mfa_step_up_challenges
    where auth_user_id = p_actor_auth_user_id
      and tenant_id = p_tenant_id
      and module_code = p_module_code
      and action = p_action
      and status = 'verified'
      and verified_at > now() - (v_max_age_minutes || ' minutes')::interval
  ) then
    raise exception 'mfa_step_up_required: %:% requires a current MFA step-up verification (max age % minutes) for identity %', p_module_code, p_action, v_max_age_minutes, p_actor_auth_user_id
      using errcode = 'insufficient_privilege';
  end if;
end;
$$;

comment on function app.assert_current_step_up_authorization is
  'IAE-027: the real, composable step-up gate (Prompt 355 §24 "High-risk actions require current authorization; stale sessions are denied") -- a no-op for a non-high-risk action; for a high-risk one, requires a verified challenge for the SAME actor/tenant/module/action within the tenant policy''s own step_up_max_age_minutes window. Intended to be called at the top of any future high-risk mutation, the same defensive-first-statement pattern app.assert_actor_is_session_identity already established.';

-- ===========================================================================
-- 5. app.user_sessions -- a declared session/device registry (design decision 4).
-- ===========================================================================

create table app.user_sessions (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  auth_user_id uuid not null references auth.users (id),
  device_label text,
  ip_address text,
  status text not null default 'active',
  created_at timestamptz not null default now(),
  last_seen_at timestamptz not null default now(),
  revoked_at timestamptz,
  revoked_reason text,
  revoked_by text,
  constraint user_sessions_status_check check (status in ('active', 'revoked'))
);

create index user_sessions_actor_idx on app.user_sessions (auth_user_id, tenant_id, status);
create index user_sessions_tenant_id_idx on app.user_sessions (tenant_id, created_at desc);

create function app.register_user_session(
  p_tenant_id uuid,
  p_device_label text,
  p_ip_address text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.user_sessions
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_session app.user_sessions;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  if not app.has_active_tenant_membership(p_tenant_id, p_actor_auth_user_id) and not app.is_supreme_admin(p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % has no active membership in tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  insert into app.user_sessions (tenant_id, auth_user_id, device_label, ip_address)
  values (p_tenant_id, p_actor_auth_user_id, p_device_label, p_ip_address)
  returning * into v_session;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'register_user_session',
    'app.user_sessions', v_session.id, 'success', null, null, jsonb_build_object('device_label', p_device_label)
  );

  return v_session;
end;
$$;

create function app.revoke_user_session(
  p_session_id uuid,
  p_reason text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.user_sessions
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_session app.user_sessions;
  v_decision app.rbac_decision;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  select * into v_session from app.user_sessions where id = p_session_id and status = 'active' for update;
  if not found then
    raise exception 'user_session_not_active: % is not an active session', p_session_id using errcode = 'no_data_found';
  end if;

  if v_session.auth_user_id <> p_actor_auth_user_id then
    v_decision := app.evaluate_permission(p_actor_auth_user_id, v_session.tenant_id, 'SEC', 'Configure');
    if not v_decision.allowed then
      raise exception 'insufficient_authority: identity % lacks SEC:Configure (%) to revoke another identity''s session', p_actor_auth_user_id, v_decision.reason
        using errcode = 'insufficient_privilege';
    end if;
  end if;

  update app.user_sessions
  set status = 'revoked', revoked_at = now(), revoked_reason = p_reason, revoked_by = p_actor_label
  where id = p_session_id
  returning * into v_session;

  perform app.capture_audit_event(
    v_session.tenant_id, p_actor_auth_user_id, p_actor_label, 'revoke_user_session',
    'app.user_sessions', v_session.id, 'success', p_reason, null, to_jsonb(v_session)
  );

  return v_session;
end;
$$;

comment on function app.revoke_user_session is
  'IAE-027: self-service (own session) or SEC:Configure (another identity''s session). This flips the real, persisted app.user_sessions.status signal; genuinely invalidating a live Supabase JWT/refresh token is an external Supabase Admin API call, disclosed as not performed here (design decision 4).';

create function app.revoke_all_actor_sessions(
  p_tenant_id uuid,
  p_target_auth_user_id uuid,
  p_reason text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns integer
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_session_count integer;
  v_key record;
  v_key_count integer := 0;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'SEC', 'Configure');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks SEC:Configure (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  update app.user_sessions
  set status = 'revoked', revoked_at = now(), revoked_reason = p_reason, revoked_by = p_actor_label
  where tenant_id = p_tenant_id and auth_user_id = p_target_auth_user_id and status = 'active';
  get diagnostics v_session_count = row_count;

  for v_key in
    select id from app.api_keys where tenant_id = p_tenant_id and created_by_auth_user_id = p_target_auth_user_id and status = 'active'
  loop
    perform app.revoke_api_key(v_key.id, p_reason, p_actor_auth_user_id, p_actor_label);
    v_key_count := v_key_count + 1;
  end loop;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'revoke_all_actor_sessions',
    'app.user_sessions', p_target_auth_user_id, 'success', p_reason, null,
    jsonb_build_object('sessions_revoked', v_session_count, 'api_keys_revoked', v_key_count)
  );

  return v_session_count;
end;
$$;

comment on function app.revoke_all_actor_sessions is
  'IAE-027: real "session revocation propagates to API keys" enforcement (Prompt 355 §24) -- composes the existing, unmodified app.revoke_api_key (PLT-129) for every ACTIVE key the target actor themselves created. Returns the session-revocation count; the api-key count is recorded in the audit event only, not the return type, to keep the primary signal (sessions) unambiguous.';

-- ===========================================================================
-- 6. app.mfa_exceptions -- break-glass factor-recovery, mirrors PLT-115's own
-- shape (design decision 6).
-- ===========================================================================

create table app.mfa_exceptions (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  target_auth_user_id uuid not null references auth.users (id),
  reason text not null,
  requested_by_auth_user_id uuid not null references auth.users (id),
  requested_by text,
  approved_by_auth_user_id uuid references auth.users (id),
  approved_by text,
  status text not null default 'pending',
  requested_at timestamptz not null default now(),
  decided_at timestamptz,
  expires_at timestamptz not null default (now() + interval '24 hours'),
  used_at timestamptz,
  constraint mfa_exceptions_status_check check (status in ('pending', 'approved', 'denied', 'expired', 'used')),
  constraint mfa_exceptions_no_self_approval check (approved_by_auth_user_id is null or approved_by_auth_user_id <> requested_by_auth_user_id)
);

create index mfa_exceptions_tenant_id_idx on app.mfa_exceptions (tenant_id, requested_at desc);

create function app.request_mfa_exception(
  p_tenant_id uuid,
  p_target_auth_user_id uuid,
  p_reason text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.mfa_exceptions
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_exception app.mfa_exceptions;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'SEC', 'Configure');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks SEC:Configure (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if coalesce(length(trim(p_reason)), 0) = 0 then
    raise exception 'mfa_exception_reason_required: a non-empty reason is required' using errcode = 'check_violation';
  end if;

  insert into app.mfa_exceptions (tenant_id, target_auth_user_id, reason, requested_by_auth_user_id, requested_by)
  values (p_tenant_id, p_target_auth_user_id, p_reason, p_actor_auth_user_id, p_actor_label)
  returning * into v_exception;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'request_mfa_exception',
    'app.mfa_exceptions', v_exception.id, 'success', p_reason, null, to_jsonb(v_exception)
  );

  return v_exception;
end;
$$;

create function app.approve_mfa_exception(
  p_exception_id uuid,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.mfa_exceptions
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_exception app.mfa_exceptions;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  select * into v_exception from app.mfa_exceptions where id = p_exception_id and status = 'pending' for update;
  if not found then
    raise exception 'mfa_exception_not_pending: % is not a pending exception request', p_exception_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_exception.tenant_id, 'SEC', 'Approve');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks SEC:Approve (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_exception.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_exception.requested_by_auth_user_id = p_actor_auth_user_id then
    raise exception 'mfa_exception_self_approval_forbidden: identity % cannot approve their own request', p_actor_auth_user_id
      using errcode = 'insufficient_privilege';
  end if;

  update app.mfa_exceptions
  set status = 'approved', approved_by_auth_user_id = p_actor_auth_user_id, approved_by = p_actor_label, decided_at = now()
  where id = p_exception_id
  returning * into v_exception;

  perform app.capture_audit_event(
    v_exception.tenant_id, p_actor_auth_user_id, p_actor_label, 'approve_mfa_exception',
    'app.mfa_exceptions', v_exception.id, 'success', null, null, to_jsonb(v_exception)
  );

  return v_exception;
end;
$$;

create function app.consume_mfa_exception(
  p_exception_id uuid,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.mfa_exceptions
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_exception app.mfa_exceptions;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  select * into v_exception
  from app.mfa_exceptions
  where id = p_exception_id and target_auth_user_id = p_actor_auth_user_id and status = 'approved'
  for update;
  if not found then
    raise exception 'mfa_exception_not_approved: % is not an approved exception for this identity', p_exception_id
      using errcode = 'no_data_found';
  end if;

  if v_exception.expires_at < now() then
    -- Deliberately does NOT persist status = 'expired' here -- the exact same
    -- savepoint-rollback hazard app.verify_mfa_step_up_challenge's own comment
    -- above already documents: a caller that wraps this call in its own
    -- exception handler runs inside an implicit savepoint, and Postgres rolls
    -- back every statement since that savepoint, including this UPDATE, once
    -- the RAISE below propagates. The lazy, next-read flip already happens
    -- correctly elsewhere (this same check, re-evaluated on the next call).
    raise exception 'mfa_exception_expired: % expired at %', p_exception_id, v_exception.expires_at
      using errcode = 'check_violation';
  end if;

  update app.mfa_exceptions
  set status = 'used', used_at = now()
  where id = p_exception_id
  returning * into v_exception;

  perform app.capture_audit_event(
    v_exception.tenant_id, p_actor_auth_user_id, p_actor_label, 'consume_mfa_exception',
    'app.mfa_exceptions', v_exception.id, 'success', null, null, to_jsonb(v_exception)
  );

  return v_exception;
end;
$$;

-- ===========================================================================
-- 7. Read paths.
-- ===========================================================================

create function app.list_user_sessions_for_tenant(p_tenant_id uuid, p_actor_auth_user_id uuid)
returns setof app.user_sessions
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'SEC', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks SEC:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  return query select * from app.user_sessions where tenant_id = p_tenant_id order by created_at desc;
end;
$$;

create function app.list_mfa_exceptions_for_tenant(p_tenant_id uuid, p_actor_auth_user_id uuid)
returns setof app.mfa_exceptions
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'SEC', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks SEC:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  return query select * from app.mfa_exceptions where tenant_id = p_tenant_id order by requested_at desc;
end;
$$;

create function app.list_mfa_step_up_challenges_for_tenant(p_tenant_id uuid, p_actor_auth_user_id uuid, p_limit integer default 50)
returns setof app.mfa_step_up_challenges
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_limit integer;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'SEC', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks SEC:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  v_limit := least(greatest(coalesce(p_limit, 50), 1), 200);
  return query select * from app.mfa_step_up_challenges where tenant_id = p_tenant_id order by challenge_issued_at desc limit v_limit;
end;
$$;

-- ===========================================================================
-- 8. RLS: default-deny, RPC-only.
-- ===========================================================================

alter table app.mfa_tenant_policies enable row level security;
alter table app.mfa_step_up_challenges enable row level security;
alter table app.user_sessions enable row level security;
alter table app.mfa_exceptions enable row level security;

revoke all on app.mfa_tenant_policies from public, anon, authenticated;
revoke all on app.mfa_step_up_challenges from public, anon, authenticated;
revoke all on app.user_sessions from public, anon, authenticated;
revoke all on app.mfa_exceptions from public, anon, authenticated;
grant all on app.mfa_tenant_policies, app.mfa_step_up_challenges, app.user_sessions, app.mfa_exceptions to service_role;

revoke execute on all functions in schema app from public;

grant execute on function
  app.get_or_create_mfa_tenant_policy(uuid, uuid),
  app.set_mfa_tenant_policy(uuid, boolean, jsonb, integer, jsonb, uuid, text),
  app.request_mfa_step_up_challenge(uuid, text, text, uuid, text),
  app.verify_mfa_step_up_challenge(uuid, uuid, text),
  app.assert_current_step_up_authorization(uuid, uuid, text, text),
  app.register_user_session(uuid, text, text, uuid, text),
  app.revoke_user_session(uuid, text, uuid, text),
  app.revoke_all_actor_sessions(uuid, uuid, text, uuid, text),
  app.request_mfa_exception(uuid, uuid, text, uuid, text),
  app.approve_mfa_exception(uuid, uuid, text),
  app.consume_mfa_exception(uuid, uuid, text),
  app.list_user_sessions_for_tenant(uuid, uuid),
  app.list_mfa_exceptions_for_tenant(uuid, uuid),
  app.list_mfa_step_up_challenges_for_tenant(uuid, uuid, integer)
to authenticated, service_role;

-- app.is_high_risk_action takes a bare p_tenant_id with no actor/authority
-- parameter at all (it is a pure classification lookup, called internally by
-- app.assert_current_step_up_authorization, which is itself real-actor-scoped)
-- -- granting it to authenticated would let any identity of any tenant probe
-- another tenant's own additional_high_risk_actions configuration. Tier C
-- review fix (ATW-032/ISS-2026-033): service_role-only, caught before this
-- migration was ever committed.
grant execute on function app.is_high_risk_action(uuid, text, text) to service_role;
