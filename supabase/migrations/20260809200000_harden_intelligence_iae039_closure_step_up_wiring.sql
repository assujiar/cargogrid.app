-- IAE-039 (Prompt 367, Intelligence/Enterprise Closure Verification) -- resolves
-- the majority of ISS-2026-151 (docs/runtime/KNOWN_ISSUES.md), the mandatory
-- RPD-023 step-up-authorization ruling IAE-037 built, live-tested, found to
-- break 17 already-VERIFIED fixtures across all 4 of its own target functions
-- unconditionally, and deliberately reverted rather than ship half-adapted.
--
-- This checkpoint's own closure-verification lenses independently re-measured
-- the REAL blast radius per target function rather than treating IAE-037's
-- own "17 fixtures across 5 groups" figure as a single monolithic block:
--
--   app.decide_ai_output_approval          -- 3 call sites, 1 file
--   app.activate_enterprise_idp_connection -- 3 call sites, 1 file
--   app.approve_mfa_exception              -- 3 call sites, 1 file
--   app.create_integration_connection      -- 40+ call sites, 16 files
--
-- The first three are genuinely bounded (3 call sites each, entirely within
-- their own capability's own db-test file) -- wired here, with each file's
-- own real-success-path call site adapted to request+verify a real MFA
-- step-up challenge first, exactly the same real mechanism a live client
-- would use (app.request_mfa_step_up_challenge / app.verify_mfa_step_up_
-- challenge, both already shipped and unmodified at IAE-027). Every
-- authority-failure/precondition-failure negative-path assertion in these
-- 3 files fires from an earlier check (RBAC, self-approval, lockout guard)
-- BEFORE the newly-added step-up check is ever reached, so none of them
-- needed adaptation -- confirmed by reading each call site's own expected
-- error before touching anything, not assumed.
--
-- app.create_integration_connection (INTHUB:Configure) is deliberately left
-- UNWIRED here: its own blast radius (40+ call sites across 16 already-
-- VERIFIED capability files, most using it as a one-line fixture-setup
-- helper for an unrelated capability under test) is the genuinely large,
-- cross-capability adaptation IAE-037 itself already correctly judged to
-- exceed any single bounded checkpoint's charter -- attempting it under
-- this same time-boxed closure checkpoint would trade a real, disclosed gap
-- for a real risk of a rushed, under-tested 16-file edit, which is a worse
-- outcome, not a better one. ISS-2026-151 is updated (not deleted) to
-- narrow its own remaining scope to this one function/module tuple alone.
--
-- No already-applied migration is edited. Each of the 3 functions below is
-- an unchanged-signature CREATE OR REPLACE (no DROP FUNCTION needed -- same
-- parameter count/types as originally shipped).

-- ===========================================================================
-- 1. app.decide_ai_output_approval (IAE-019) -- AI:Approve
-- ===========================================================================

create or replace function app.decide_ai_output_approval(
  p_request_step_id uuid,
  p_decision text,
  p_actor_auth_user_id uuid,
  p_actor_label text,
  p_reason text default null
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

  return app.decide_approval_step(p_request_step_id, p_decision, p_actor_auth_user_id, p_actor_label, p_reason);
end;
$$;

comment on function app.decide_ai_output_approval is
  'IAE-019: a domain-scoped SECURITY DEFINER proxy to app.decide_approval_step (PLT-123, service_role-only), mirrors app.decide_automation_rule_publish_approval (IAE-007) exactly. Folds a step that does not belong to an ai_governed_output request into a clean not-found-shaped error, never a tenant-id-disclosing insufficient_authority. Layers AI:Approve on top of the generic engine''s own step-level eligibility check, the same defense-in-depth every prior Batch 4 capability''s own connection-active-plus-domain-permission pattern already established. IAE-039 Tier-closure fix: requires a current MFA step-up verification (RPD-023, AI:Approve is a platform-default high-risk action) after authority is otherwise established, before the decision is applied.';

-- ===========================================================================
-- 2. app.activate_enterprise_idp_connection (IAE-026) -- IAM:Configure
-- ===========================================================================

create or replace function app.activate_enterprise_idp_connection(
  p_connection_id uuid,
  p_actor_auth_user_id uuid,
  p_actor_label text
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

  return app.set_integration_connection_status(p_connection_id, 'active', null, p_actor_auth_user_id, p_actor_label);
end;
$$;

comment on function app.activate_enterprise_idp_connection is
  'IAE-026: the structural lockout guard Prompt 354 §20/§28 requires ("test before enforcement") -- delegates the actual status flip to app.set_integration_connection_status (IAE-008, unmodified) once at least one real matched test resolution is proven to exist. Disabling has no such precondition (app.set_integration_connection_status(..., ''disabled'', ...) is always the break-glass/rollback path, per Prompt 354 §32) and is called directly, unwrapped. IAE-039 Tier-closure fix: requires a current MFA step-up verification (RPD-023, IAM:Configure is a platform-default high-risk action) after authority and the lockout guard are otherwise satisfied, before the connection is activated.';

-- ===========================================================================
-- 3. app.approve_mfa_exception (IAE-027) -- SEC:Approve
-- ===========================================================================

create or replace function app.approve_mfa_exception(
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

  perform app.assert_current_step_up_authorization(v_exception.tenant_id, p_actor_auth_user_id, 'SEC', 'Approve');

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
  'IAE-027: SEC:Approve-gated; self-approval forbidden regardless of authority. IAE-039 Tier-closure fix: requires a current MFA step-up verification (RPD-023, SEC:Approve is a platform-default high-risk action) after authority and the self-approval guard are otherwise satisfied, before the exception is approved.';

-- ===========================================================================
-- Grants -- every function above is a create-or-replace of an unchanged
-- signature; nothing new to grant (each already carries its own prior
-- authenticated/service_role grant, unaffected by CREATE OR REPLACE).
-- ===========================================================================

revoke execute on all functions in schema app from public;
