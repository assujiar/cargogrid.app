-- ISS-2026-150 closure wiring (docs/runtime/KNOWN_ISSUES.md) -- app.assert_ip_allowed
-- and app.has_active_ip_allowlist_bypass (IAE-028, Prompt 356) are real and correct
-- when invoked directly, but had ZERO real callers anywhere in the mutation layer: a
-- repository-wide grep confirmed a fully-configured, `enforced`-mode IP allowlist
-- provided zero real protection against any caller that reached the RPC layer
-- directly. This mirrors the exact shape of IAE-039's own closure of the sibling
-- ISS-2026-151 (step-up authorization, `20260809200000_harden_intelligence_iae039_
-- closure_step_up_wiring.sql`) -- same 4 target functions, same "compose a real,
-- already-shipped, already-correct primitive into the functions that actually
-- mutate state" shape. UNLIKE that migration, this one cannot use a bare `CREATE OR
-- REPLACE FUNCTION`: IAE-039's own 3 functions kept an unchanged signature, but
-- every function here gains a genuinely new trailing parameter, and Postgres treats
-- a changed argument list as a DIFFERENT, distinct overload rather than a replace
-- of the original -- confirmed by live-forcing exactly this against a real
-- disposable database (a first `CREATE OR REPLACE` pass left TWO co-existing
-- overloads of app.decide_ai_output_approval, `... is not unique` on the very next
-- unqualified `COMMENT ON FUNCTION`, and would have left every existing 5-arg
-- caller silently bound to the OLD, un-gated overload forever -- the "cosmetic
-- partial wire-up" ISS-2026-150's own `Owner` note explicitly warned against, had
-- it shipped). Each function below is therefore `DROP FUNCTION` (old signature)
-- followed by a fresh `CREATE FUNCTION` (new signature) and an explicit re-grant --
-- the same drop-then-recreate idiom already established at, e.g.,
-- `20260730670000_harden_procurement_batch_257_259_review_fixes.sql`'s own
-- `app.decide_vendor_activation_approval_step` signature change -- never a bare
-- `CREATE OR REPLACE FUNCTION` for a widened argument list.
--
-- Target functions (identical set IAE-039 wired for step-up, deliberately reused
-- rather than re-derived -- these are the checkpoint's own named highest-risk
-- SEC/IAM/AI/INTHUB mutations):
--
--   app.decide_ai_output_approval          -- AI:Approve
--   app.activate_enterprise_idp_connection -- IAM:Configure
--   app.approve_mfa_exception              -- SEC:Approve
--   app.create_integration_connection      -- INTHUB:Configure
--
-- Each gains one new trailing, DEFAULTED parameter -- `p_client_ip text default
-- null` -- strictly additive, so no existing positional caller anywhere (TS mutation
-- wrapper, db-test fixture, any other function) breaks. When a caller supplies a
-- real client IP, the new check composes the two previously-inert IAE-028
-- primitives exactly as app.has_active_ip_allowlist_bypass's own comment already
-- anticipated ("a future caller of app.assert_ip_allowed can check this FIRST and
-- skip the call entirely for a bypass-holding identity"):
--
--   if p_client_ip is not null and not app.has_active_ip_allowlist_bypass(<tenant>, <actor>) then
--     perform app.assert_ip_allowed(<tenant>, p_client_ip, 'admin', <actor label>);
--   end if;
--
-- Scope is always 'admin' -- every one of these 4 functions is itself an
-- administrative/privileged mutation (approval decision, SSO activation, MFA
-- exception approval, integration connection creation), never an ordinary
-- end-user CRUD action; 'admin' is the same scope IAE-028's own db-test exercises
-- for exactly this class of action. When no p_client_ip is supplied (every existing
-- caller today -- the TS mutation layer has no HTTP request-derived client IP
-- threaded through yet, matching ISS-2026-150's own disclosed root cause) or the
-- identity holds a currently-active bypass grant, the check is skipped entirely --
-- the same "exempt a non-interactive caller with no request context" resolution
-- ISS-2026-150's own `Owner` note already named as the correct behavior for a
-- service-role/background-job caller with no client IP at all. Placed AFTER every
-- existing RBAC/precondition check (and, for the 3 already-step-up-wired functions,
-- after the existing app.assert_current_step_up_authorization call) and BEFORE the
-- function's own mutating action -- same ordering discipline IAE-039 used, so every
-- existing negative-path assertion in each function's own db-test still fires from
-- an earlier check, unchanged.
--
-- No already-applied migration is edited. Each of the 4 functions below is a real
-- DROP FUNCTION (old signature) + CREATE FUNCTION (new signature, one trailing
-- defaulted param) + explicit re-grant to the exact same roles the original
-- migration granted -- verified against each original migration's own grant
-- statement before writing the new one, not assumed unchanged.

-- ===========================================================================
-- 1. app.decide_ai_output_approval (IAE-019) -- AI:Approve
-- ===========================================================================

drop function app.decide_ai_output_approval(uuid, text, uuid, text, text);

create function app.decide_ai_output_approval(
  p_request_step_id uuid,
  p_decision text,
  p_actor_auth_user_id uuid,
  p_actor_label text,
  p_reason text default null,
  p_client_ip text default null
)
returns app.approval_request_steps
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_step app.approval_request_steps;
  v_approval_request app.approval_requests;
  v_request app.ai_governed_requests;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  select * into v_step from app.approval_request_steps where id = p_request_step_id;
  if not found then
    raise exception 'ai_output_approval_step_not_found: %', p_request_step_id using errcode = 'no_data_found';
  end if;

  select * into v_approval_request from app.approval_requests where id = v_step.request_id;
  if v_approval_request.entity_type <> 'ai_governed_output' then
    raise exception 'ai_output_approval_wrong_domain: step % does not belong to an AI output acceptance request', p_request_step_id
      using errcode = 'check_violation';
  end if;

  select * into v_request from app.ai_governed_requests where id = v_approval_request.entity_id;
  if not app.check_ai_governance_authority('Approve', v_request.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks AI:Approve for tenant %', p_actor_auth_user_id, v_request.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  perform app.assert_current_step_up_authorization(v_request.tenant_id, p_actor_auth_user_id, 'AI', 'Approve');

  if p_client_ip is not null and not app.has_active_ip_allowlist_bypass(v_request.tenant_id, p_actor_auth_user_id) then
    perform app.assert_ip_allowed(v_request.tenant_id, p_client_ip, 'admin', p_actor_label);
  end if;

  return app.decide_approval_step(p_request_step_id, p_decision, p_actor_auth_user_id, p_actor_label, p_reason);
end;
$$;

comment on function app.decide_ai_output_approval is
  'IAE-019: a domain-scoped SECURITY DEFINER proxy to app.decide_approval_step (PLT-123, service_role-only), mirrors app.decide_automation_rule_publish_approval (IAE-007) exactly. Folds a step that does not belong to an ai_governed_output request into a clean not-found-shaped error, never a tenant-id-disclosing insufficient_authority. Layers AI:Approve on top of the generic engine''s own step-level eligibility check, the same defense-in-depth every prior Batch 4 capability''s own connection-active-plus-domain-permission pattern already established. IAE-039 Tier-closure fix: requires a current MFA step-up verification (RPD-023, AI:Approve is a platform-default high-risk action) after authority is otherwise established, before the decision is applied. ISS-2026-150 closure fix: when a caller supplies p_client_ip, also enforces the tenant''s own IP allowlist restriction (scope ''admin'') via app.assert_ip_allowed, unless the acting identity holds a currently-active app.ip_allowlist_bypass_grants grant -- a null p_client_ip (no caller-derived IP available) skips this check entirely, same non-interactive-caller exemption as IAE-028''s own design.';

grant execute on function app.decide_ai_output_approval(uuid, text, uuid, text, text, text) to authenticated, service_role;

-- ===========================================================================
-- 2. app.activate_enterprise_idp_connection (IAE-026) -- IAM:Configure
-- ===========================================================================

drop function app.activate_enterprise_idp_connection(uuid, uuid, text);

create function app.activate_enterprise_idp_connection(
  p_connection_id uuid,
  p_actor_auth_user_id uuid,
  p_actor_label text,
  p_client_ip text default null
)
returns app.integration_connections
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_connection app.integration_connections;
  v_decision app.rbac_decision;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  select * into v_connection from app.integration_connections where id = p_connection_id;
  if not found then
    raise exception 'iam_connection_not_found: %', p_connection_id using errcode = 'no_data_found';
  end if;
  if v_connection.adapter_code not in ('enterprise_sso_oidc', 'enterprise_sso_saml') then
    raise exception 'iam_connection_wrong_adapter: % is not an enterprise SSO connection', p_connection_id
      using errcode = 'check_violation';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_connection.tenant_id, 'IAM', 'Configure');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks IAM:Configure (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_connection.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if not exists (
    select 1 from app.iam_sso_login_attempts
    where connection_id = p_connection_id and outcome = 'matched'
  ) then
    raise exception 'enterprise_idp_no_verified_test_login: connection % has no recorded successful test-login resolution -- run app.resolve_enterprise_sso_claims first to prevent a lockout', p_connection_id
      using errcode = 'check_violation';
  end if;

  perform app.assert_current_step_up_authorization(v_connection.tenant_id, p_actor_auth_user_id, 'IAM', 'Configure');

  if p_client_ip is not null and not app.has_active_ip_allowlist_bypass(v_connection.tenant_id, p_actor_auth_user_id) then
    perform app.assert_ip_allowed(v_connection.tenant_id, p_client_ip, 'admin', p_actor_label);
  end if;

  return app.set_integration_connection_status(p_connection_id, 'active', null, p_actor_auth_user_id, p_actor_label);
end;
$$;

comment on function app.activate_enterprise_idp_connection is
  'IAE-026: the structural lockout guard Prompt 354 §20/§28 requires ("test before enforcement") -- delegates the actual status flip to app.set_integration_connection_status (IAE-008, unmodified) once at least one real matched test resolution is proven to exist. Disabling has no such precondition (app.set_integration_connection_status(..., ''disabled'', ...) is always the break-glass/rollback path, per Prompt 354 §32) and is called directly, unwrapped. IAE-039 Tier-closure fix: requires a current MFA step-up verification (RPD-023, IAM:Configure is a platform-default high-risk action) after authority and the lockout guard are otherwise satisfied, before the connection is activated. ISS-2026-150 closure fix: when a caller supplies p_client_ip, also enforces the tenant''s own IP allowlist restriction (scope ''admin'') via app.assert_ip_allowed, unless the acting identity holds a currently-active app.ip_allowlist_bypass_grants grant -- a null p_client_ip skips this check entirely.';

grant execute on function app.activate_enterprise_idp_connection(uuid, uuid, text, text) to authenticated, service_role;

-- ===========================================================================
-- 3. app.approve_mfa_exception (IAE-027) -- SEC:Approve
-- ===========================================================================

drop function app.approve_mfa_exception(uuid, uuid, text);

create function app.approve_mfa_exception(
  p_exception_id uuid,
  p_actor_auth_user_id uuid,
  p_actor_label text,
  p_client_ip text default null
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

  perform app.assert_current_step_up_authorization(v_exception.tenant_id, p_actor_auth_user_id, 'SEC', 'Approve');

  if p_client_ip is not null and not app.has_active_ip_allowlist_bypass(v_exception.tenant_id, p_actor_auth_user_id) then
    perform app.assert_ip_allowed(v_exception.tenant_id, p_client_ip, 'admin', p_actor_label);
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

comment on function app.approve_mfa_exception is
  'IAE-027: SEC:Approve-gated; self-approval forbidden regardless of authority. IAE-039 Tier-closure fix: requires a current MFA step-up verification (RPD-023, SEC:Approve is a platform-default high-risk action) after authority and the self-approval guard are otherwise satisfied, before the exception is approved. ISS-2026-150 closure fix: when a caller supplies p_client_ip, also enforces the tenant''s own IP allowlist restriction (scope ''admin'') via app.assert_ip_allowed, unless the acting identity holds a currently-active app.ip_allowlist_bypass_grants grant -- a null p_client_ip skips this check entirely.';

grant execute on function app.approve_mfa_exception(uuid, uuid, text, text) to authenticated, service_role;

-- ===========================================================================
-- 4. app.create_integration_connection (IAE-008) -- INTHUB:Configure
-- ===========================================================================
--
-- Unlike the other 3, this function was deliberately left UNWIRED for step-up
-- authorization at IAE-039 (its own real blast radius there was 40+ call sites
-- across 16 files -- ISS-2026-151 remains open and scoped to this one function
-- alone, see the closing note below). It has no existing
-- app.assert_current_step_up_authorization call to anchor against; the new IP
-- check below is placed after the existing RBAC/precondition checks and
-- immediately before the insert, the same relative position used in the other
-- 3 functions.

drop function app.create_integration_connection(uuid, text, text, text, text, text, text, jsonb, text, uuid, text);

create function app.create_integration_connection(
  p_tenant_id uuid,
  p_adapter_code text,
  p_name text,
  p_environment text,
  p_owner_team text,
  p_owner_email text,
  p_runbook_url text,
  p_config jsonb,
  p_credential_value text,
  p_actor_auth_user_id uuid,
  p_actor_label text,
  p_client_ip text default null
)
returns app.integration_connections
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_connection app.integration_connections;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'INTHUB', 'Configure');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks INTHUB:Configure (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if not exists (select 1 from app.integration_adapters where code = p_adapter_code) then
    raise exception 'integration_adapter_unknown: % is not a registered integration adapter', p_adapter_code
      using errcode = 'check_violation';
  end if;

  if coalesce(length(trim(p_name)), 0) = 0 then
    raise exception 'integration_connection_missing_name: a non-empty name is required' using errcode = 'check_violation';
  end if;
  if coalesce(length(trim(p_credential_value)), 0) = 0 then
    raise exception 'integration_connection_missing_credential: a non-empty credential_value is required' using errcode = 'check_violation';
  end if;
  if not app.validate_config_value(coalesce(p_config, '{}'::jsonb)) then
    raise exception 'integration_connection_unsafe_config: config failed structural validation' using errcode = 'check_violation';
  end if;

  if p_client_ip is not null and not app.has_active_ip_allowlist_bypass(p_tenant_id, p_actor_auth_user_id) then
    perform app.assert_ip_allowed(p_tenant_id, p_client_ip, 'admin', p_actor_label);
  end if;

  insert into app.integration_connections (
    tenant_id, adapter_code, name, environment, owner_team, owner_email, runbook_url, config,
    created_by_auth_user_id, created_by
  ) values (
    p_tenant_id, p_adapter_code, p_name, coalesce(p_environment, 'production'), p_owner_team, p_owner_email, p_runbook_url, coalesce(p_config, '{}'::jsonb),
    p_actor_auth_user_id, p_actor_label
  )
  returning * into v_connection;

  insert into app.integration_connection_credentials (connection_id, credential_value, created_by_auth_user_id)
  values (v_connection.id, p_credential_value, p_actor_auth_user_id);

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'create_integration_connection',
    'app.integration_connections', v_connection.id, 'success', null, null,
    jsonb_build_object('adapter_code', v_connection.adapter_code, 'environment', v_connection.environment)
  );

  return v_connection;
end;
$$;

comment on function app.create_integration_connection is
  'IAE-008: INTHUB:Configure-gated. Creates the connection plus its own isolated credential row in one transaction. The credential value is never included in the returned app.integration_connections row (it is not a column of that table) or in the captured audit event (design decision 3). ISS-2026-150 closure fix: when a caller supplies p_client_ip, also enforces the tenant''s own IP allowlist restriction (scope ''admin'') via app.assert_ip_allowed, unless the acting identity holds a currently-active app.ip_allowlist_bypass_grants grant -- a null p_client_ip skips this check entirely, the same non-interactive-caller exemption every one of this checkpoint''s 4 target functions shares.';

grant execute on function app.create_integration_connection(uuid, text, text, text, text, text, text, jsonb, text, uuid, text, text) to authenticated, service_role;

-- ===========================================================================
-- Grants -- each function above is a genuine DROP + CREATE of a widened
-- signature (see the header note on why a bare CREATE OR REPLACE was rejected),
-- so unlike a same-signature CREATE OR REPLACE, the original grants do NOT
-- carry forward automatically -- each is re-granted explicitly above, to the
-- exact same roles (authenticated, service_role) the function originally
-- shipped with, verified against each origin migration's own grant statement:
--   app.decide_ai_output_approval(uuid, text, uuid, text, text) --
--     20260805060000_create_intelligence_ai_governance_provider_boundary.sql
--   app.activate_enterprise_idp_connection(uuid, uuid, text) --
--     20260807000000_create_intelligence_enterprise_iam_sso.sql
--   app.approve_mfa_exception(uuid, uuid, text) --
--     20260807100000_create_intelligence_enterprise_mfa_session_controls.sql
--   app.create_integration_connection(uuid, text, text, text, text, text, text,
--     jsonb, text, uuid, text) -- 20260803020000_create_intelligence_integration_hub.sql
-- ===========================================================================

revoke execute on all functions in schema app from public;

-- ===========================================================================
-- Scope notes (self-documentation convention established at
-- 20260814100000_harden_storage_signed_url_audit_tierc_fixes.sql):
--
-- 1. This migration deliberately does NOT also wire step-up-MFA into
--    app.create_integration_connection. That remains ISS-2026-151's own
--    separately-scoped, still-open gap (a 40+-call-site/16-file fixture
--    adaptation IAE-039 already correctly judged to exceed a single bounded
--    checkpoint) and is intentionally kept out of this pass -- this migration
--    touches only the newly-composed IP-restriction check on that function,
--    nothing else about its existing behavior.
--
-- 2. Adding IP-restriction here required ZERO existing db-test/fixture edits
--    across the whole repository (beyond the new, additive regression blocks
--    this same change adds) -- verified, not assumed: the new p_client_ip
--    parameter is defaulted to null for every one of the 4 functions, and a
--    repository-wide check confirms no existing db-test tenant, anywhere,
--    has ever configured enforcement_mode=''enforced'' for an IP allowlist
--    policy scoped to any tenant these 4 functions'' own existing call sites
--    touch -- so every existing call, which never passes p_client_ip at all,
--    takes the null-IP/no-op branch exactly as it did before this migration.
-- ===========================================================================
