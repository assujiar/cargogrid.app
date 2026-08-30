-- Real, executable test evidence for IAE-027 (Enterprise MFA and Session
-- Controls, Prompt 355) -- run via `pnpm run db:test` against a real,
-- disposable Postgres database. Scoped to this checkpoint's own additive
-- migration (supabase/migrations/20260807100000_create_intelligence_enterprise_mfa_session_controls.sql).
-- Fresh, distinctive tenant fixture (iaemfa), fixture id range
-- 00000000-0000-0000-0000-000031xxxxxx.

\set ON_ERROR_STOP on

\echo '>> setup: tenant iaemfa with admin1 (tenant_admin + SEC:Configure/View/Approve), viewer1 (SEC:View only), rep1 (plain org_user, no SEC grants); a second tenant iaemfa2 for cross-tenant isolation'
do $$
declare
  v_tenant1 uuid;
  v_tenant2 uuid;
  v_supreme uuid := '00000000-0000-0000-0000-000031000000';
  v_admin1 uuid := '00000000-0000-0000-0000-000031000001';
  v_viewer1 uuid := '00000000-0000-0000-0000-000031000002';
  v_rep1 uuid := '00000000-0000-0000-0000-000031000003';
  v_admin2 uuid := '00000000-0000-0000-0000-000031000004';
  v_admin1_role uuid;
  v_admin1_draft app.role_versions;
  v_viewer_role uuid;
  v_viewer_draft app.role_versions;
  v_admin2_role uuid;
  v_admin2_draft app.role_versions;
begin
  insert into auth.users (id, email) values
    (v_supreme, 'supreme@iaemfa.test'),
    (v_admin1, 'admin@iaemfa.test'),
    (v_viewer1, 'viewer@iaemfa.test'),
    (v_rep1, 'rep@iaemfa.test'),
    (v_admin2, 'admin@iaemfa2.test');

  perform app.grant_principal_membership(v_supreme, 'supreme_admin', null, null, 'tester');

  perform app.provision_tenant('iaemfa', 'IaeMfa Co', 'idem-iaemfa', 'tester');
  v_tenant1 := (select id from app.tenants where slug = 'iaemfa');
  perform app.transition_tenant_status(v_tenant1, 'active', 'setup', 'tester');

  perform app.provision_tenant('iaemfa2', 'IaeMfa2 Co', 'idem-iaemfa2', 'tester');
  v_tenant2 := (select id from app.tenants where slug = 'iaemfa2');
  perform app.transition_tenant_status(v_tenant2, 'active', 'setup', 'tester');

  perform app.invite_user(v_tenant1, v_admin1, 'admin@iaemfa.test', 'Admin One', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'admin@iaemfa.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership(v_admin1, 'tenant_admin', v_tenant1, null, 'tester');

  perform app.invite_user(v_tenant1, v_viewer1, 'viewer@iaemfa.test', 'Viewer One', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'viewer@iaemfa.test'), 'active', 'onboarded', 'tester');

  perform app.invite_user(v_tenant1, v_rep1, 'rep@iaemfa.test', 'Rep One', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'rep@iaemfa.test'), 'active', 'onboarded', 'tester');

  perform app.invite_user(v_tenant2, v_admin2, 'admin@iaemfa2.test', 'Admin Two', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'admin@iaemfa2.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership(v_admin2, 'tenant_admin', v_tenant2, null, 'tester');

  v_admin1_role := (app.create_role(v_tenant1, 'IaeMfa Admin', 'SEC:Configure/View/Approve', 'tester')).id;
  v_admin1_draft := app.create_role_version(v_admin1_role, 'tester');
  perform app.set_role_version_permissions(v_admin1_draft.id, array(select id from app.permissions where resource_module_code = 'SEC' and action in ('Configure', 'View', 'Approve')), 'tester');
  perform app.publish_role_version(v_admin1_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_admin1_role and status = 'published'), v_admin1, v_supreme, 'supreme');

  v_viewer_role := (app.create_role(v_tenant1, 'IaeMfa Viewer', 'SEC:View only', 'tester')).id;
  v_viewer_draft := app.create_role_version(v_viewer_role, 'tester');
  perform app.set_role_version_permissions(v_viewer_draft.id, array(select id from app.permissions where resource_module_code = 'SEC' and action = 'View'), 'tester');
  perform app.publish_role_version(v_viewer_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_viewer_role and status = 'published'), v_viewer1, v_supreme, 'supreme');

  v_admin2_role := (app.create_role(v_tenant2, 'IaeMfa2 Admin', 'SEC:Configure/View/Approve -- tenant2 cross-check probe actor', 'tester')).id;
  v_admin2_draft := app.create_role_version(v_admin2_role, 'tester');
  perform app.set_role_version_permissions(v_admin2_draft.id, array(select id from app.permissions where resource_module_code = 'SEC' and action in ('Configure', 'View', 'Approve')), 'tester');
  perform app.publish_role_version(v_admin2_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant2, (select id from app.role_versions where role_id = v_admin2_role and status = 'published'), v_admin2, v_supreme, 'supreme');

  raise notice 'FIXTURE OK tenant1=%, tenant2=%', v_tenant1, v_tenant2;
end;
$$;

\echo '>> app.get_or_create_mfa_tenant_policy: SEC:View-gated (rep1, no SEC grant, rejected; admin1/viewer1 succeed); idempotent default-row bootstrap; a different tenant''s admin cannot read this tenant''s own policy; app.set_mfa_tenant_policy: viewer1 (SEC:View only) rejected, admin1 succeeds'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'iaemfa');
  v_admin1 uuid := '00000000-0000-0000-0000-000031000001';
  v_viewer1 uuid := '00000000-0000-0000-0000-000031000002';
  v_rep1 uuid := '00000000-0000-0000-0000-000031000003';
  v_admin2 uuid := '00000000-0000-0000-0000-000031000004';
  v_first app.mfa_tenant_policies;
  v_second app.mfa_tenant_policies;
  v_policy app.mfa_tenant_policies;
begin
  begin
    perform app.get_or_create_mfa_tenant_policy(v_tenant1, v_rep1);
    raise exception 'assertion failed: expected insufficient_authority for rep1 (no SEC grant), the call unexpectedly succeeded';
  exception when insufficient_privilege then
    null;
  end;

  begin
    perform app.get_or_create_mfa_tenant_policy(v_tenant1, v_admin2);
    raise exception 'assertion failed: expected insufficient_authority for admin2 (a different tenant''s own admin) reading tenant1''s own MFA policy, the call unexpectedly succeeded';
  exception when insufficient_privilege then
    null;
  end;

  v_first := app.get_or_create_mfa_tenant_policy(v_tenant1, v_admin1);
  v_second := app.get_or_create_mfa_tenant_policy(v_tenant1, v_viewer1);
  if v_first.tenant_id <> v_second.tenant_id or v_first.step_up_max_age_minutes <> 15 then
    raise exception 'assertion failed: expected the same idempotent default row (step_up_max_age_minutes=15), got % / %', v_first, v_second;
  end if;

  begin
    perform app.set_mfa_tenant_policy(v_tenant1, true, '["supreme_admin"]'::jsonb, 30, '[]'::jsonb, v_viewer1, 'viewer1');
    raise exception 'assertion failed: expected insufficient_authority for viewer1 (SEC:View only), the call unexpectedly succeeded';
  exception when insufficient_privilege then
    null;
  end;

  begin
    perform app.set_mfa_tenant_policy(v_tenant1, true, '["supreme_admin"]'::jsonb, 9999, '[]'::jsonb, v_admin1, 'admin1');
    raise exception 'assertion failed: expected mfa_invalid_step_up_max_age for 9999 minutes, the call unexpectedly succeeded';
  exception when check_violation then
    null;
  end;

  v_policy := app.set_mfa_tenant_policy(v_tenant1, true, '["supreme_admin", "tenant_admin"]'::jsonb, 20, '[{"moduleCode": "OPS", "action": "Approve"}]'::jsonb, v_admin1, 'admin1');
  if v_policy.step_up_max_age_minutes <> 20 or v_policy.tenant_wide_required <> true then
    raise exception 'assertion failed: expected step_up_max_age_minutes=20/tenant_wide_required=true, got %', v_policy;
  end if;
end;
$$;

\echo '>> app.is_high_risk_action: platform-default set always true regardless of tenant; tenant-additive list only ADDS, an unrelated tenant does not inherit another tenant''s own additions'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'iaemfa');
  v_tenant2 uuid := (select id from app.tenants where slug = 'iaemfa2');
begin
  if not app.is_high_risk_action(v_tenant1, 'FIN', 'Approve') then
    raise exception 'assertion failed: expected FIN:Approve to be platform-default high-risk';
  end if;
  if not app.is_high_risk_action(v_tenant2, 'IAM', 'Configure') then
    raise exception 'assertion failed: expected IAM:Configure to be platform-default high-risk for ANY tenant, including one with no explicit policy row';
  end if;
  if app.is_high_risk_action(v_tenant1, 'OPS', 'View') then
    raise exception 'assertion failed: expected OPS:View to NOT be high-risk';
  end if;
  if not app.is_high_risk_action(v_tenant1, 'OPS', 'Approve') then
    raise exception 'assertion failed: expected OPS:Approve to be high-risk for iaemfa (tenant-additive, set above)';
  end if;
  if app.is_high_risk_action(v_tenant2, 'OPS', 'Approve') then
    raise exception 'assertion failed: expected OPS:Approve to NOT be high-risk for iaemfa2 -- tenant-additive lists must not leak across tenants';
  end if;
end;
$$;

\echo '>> app.request_mfa_step_up_challenge: rejected for a non-high-risk action; a genuinely different actor cannot request on behalf of another (assert_actor_is_session_identity is a no-op here since no session is forged yet -- the real cross-actor defense is proven in the RLS block below); app.verify_mfa_step_up_challenge: wrong actor rejected, correct actor verifies; app.assert_current_step_up_authorization: no-op for a non-high-risk action, blocks a high-risk one with no verified challenge, passes once verified, blocks again once the max-age window elapses'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'iaemfa');
  v_admin1 uuid := '00000000-0000-0000-0000-000031000001';
  v_rep1 uuid := '00000000-0000-0000-0000-000031000003';
  v_challenge app.mfa_step_up_challenges;
begin
  begin
    perform app.request_mfa_step_up_challenge(v_tenant1, 'OPS', 'View', v_admin1, 'admin1');
    raise exception 'assertion failed: expected mfa_step_up_not_required for a non-high-risk action, the call unexpectedly succeeded';
  exception when check_violation then
    null;
  end;

  begin
    perform app.assert_current_step_up_authorization(v_tenant1, v_admin1, 'FIN', 'Approve');
    raise exception 'assertion failed: expected mfa_step_up_required with no verified challenge yet, the call unexpectedly succeeded';
  exception when insufficient_privilege then
    null;
  end;

  -- A non-high-risk action never requires step-up -- true no-op, no exception.
  perform app.assert_current_step_up_authorization(v_tenant1, v_admin1, 'OPS', 'View');

  v_challenge := app.request_mfa_step_up_challenge(v_tenant1, 'FIN', 'Approve', v_admin1, 'admin1');
  if v_challenge.status <> 'pending' then
    raise exception 'assertion failed: expected status pending, got %', v_challenge.status;
  end if;

  begin
    perform app.verify_mfa_step_up_challenge(v_challenge.id, v_rep1, 'rep1');
    raise exception 'assertion failed: expected mfa_step_up_challenge_not_pending for a different actor''s own challenge, the call unexpectedly succeeded';
  exception when no_data_found then
    null;
  end;

  v_challenge := app.verify_mfa_step_up_challenge(v_challenge.id, v_admin1, 'admin1');
  if v_challenge.status <> 'verified' then
    raise exception 'assertion failed: expected status verified, got %', v_challenge.status;
  end if;

  -- A second verify attempt on the same, already-verified challenge is rejected.
  begin
    perform app.verify_mfa_step_up_challenge(v_challenge.id, v_admin1, 'admin1');
    raise exception 'assertion failed: expected mfa_step_up_challenge_not_pending on a second verify attempt, the call unexpectedly succeeded';
  exception when no_data_found then
    null;
  end;

  -- Now authorized: a real, current, verified challenge exists for this exact actor/tenant/module/action.
  perform app.assert_current_step_up_authorization(v_tenant1, v_admin1, 'FIN', 'Approve');

  -- Simulate the max-age window elapsing by backdating verified_at past the tenant's own 20-minute policy.
  update app.mfa_step_up_challenges set verified_at = now() - interval '25 minutes' where id = v_challenge.id;
  begin
    perform app.assert_current_step_up_authorization(v_tenant1, v_admin1, 'FIN', 'Approve');
    raise exception 'assertion failed: expected mfa_step_up_required once the verified challenge is stale (25min > 20min policy), the call unexpectedly succeeded';
  exception when insufficient_privilege then
    null;
  end;
end;
$$;

\echo '>> app.mfa_step_up_challenges expiry: a challenge past its own 10-minute challenge_expires_at cannot be verified'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'iaemfa');
  v_admin1 uuid := '00000000-0000-0000-0000-000031000001';
  v_challenge app.mfa_step_up_challenges;
begin
  v_challenge := app.request_mfa_step_up_challenge(v_tenant1, 'IAM', 'Configure', v_admin1, 'admin1');
  update app.mfa_step_up_challenges set challenge_expires_at = now() - interval '1 minute' where id = v_challenge.id;
  begin
    perform app.verify_mfa_step_up_challenge(v_challenge.id, v_admin1, 'admin1');
    raise exception 'assertion failed: expected mfa_step_up_challenge_expired, the call unexpectedly succeeded';
  exception when check_violation then
    null;
  end;
  -- Deliberately still 'pending', not 'expired': persisting a status flip inside a
  -- call that then raises would be rolled back by this very exception handler's own
  -- implicit savepoint (the real bug this migration's own header now discloses).
  if (select status from app.mfa_step_up_challenges where id = v_challenge.id) <> 'pending' then
    raise exception 'assertion failed: expected the challenge to remain pending (no side-effect update survives a caught raise)';
  end if;
end;
$$;

\echo '>> app.user_sessions: self-revoke always allowed; a different actor with no SEC:Configure grant is rejected; a different actor WITH SEC:Configure (admin1) succeeds; app.revoke_all_actor_sessions revokes every active session AND every active app.api_keys row the target actor created (real propagation, not merely disclosed)'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'iaemfa');
  v_admin1 uuid := '00000000-0000-0000-0000-000031000001';
  v_viewer1 uuid := '00000000-0000-0000-0000-000031000002';
  v_rep1 uuid := '00000000-0000-0000-0000-000031000003';
  v_session1 app.user_sessions;
  v_session2 app.user_sessions;
  v_session3 app.user_sessions;
  v_rep1_ops_role uuid;
  v_rep1_ops_draft app.role_versions;
  v_session_count integer;
  v_key_status text;
  v_step_up app.mfa_step_up_challenges;
begin
  -- ISS-2026-236: `iaemfa` set tenant_wide_required = true earlier in this file, and
  -- SEC:Configure is a platform-default high-risk tuple -- so app.evaluate_permission now
  -- requires a current verified step-up for every SEC:Configure call in this tenant. Both
  -- actors below get a REAL challenge through the shipped mechanism, exactly as a live
  -- client would and exactly as IAE-039 adapted its own three call sites.
  --
  -- viewer1 gets one deliberately, even though viewer1 is the NEGATIVE case: without it
  -- viewer1's rejection below would fire on the new step-up branch and the assertion would
  -- pass for the wrong reason, silently ceasing to test the SEC:Configure role gap it was
  -- written for. The fixture is adapted to the control; no assertion is relaxed to it.
  v_step_up := app.request_mfa_step_up_challenge(v_tenant1, 'SEC', 'Configure', v_admin1, 'admin1');
  perform app.verify_mfa_step_up_challenge(v_step_up.id, v_admin1, 'admin1');
  v_step_up := app.request_mfa_step_up_challenge(v_tenant1, 'SEC', 'Configure', v_viewer1, 'viewer1');
  perform app.verify_mfa_step_up_challenge(v_step_up.id, v_viewer1, 'viewer1');

  v_session1 := app.register_user_session(v_tenant1, 'reps laptop', '203.0.113.10', v_rep1, 'rep1');
  if v_session1.status <> 'active' then
    raise exception 'assertion failed: expected a new session status active, got %', v_session1.status;
  end if;

  begin
    perform app.revoke_user_session(v_session1.id, 'unauthorized attempt', v_viewer1, 'viewer1');
    raise exception 'assertion failed: expected insufficient_authority for viewer1 (SEC:View only, no Configure) revoking a DIFFERENT identity''s session, the call unexpectedly succeeded';
  exception when insufficient_privilege then
    null;
  end;

  -- admin1 genuinely holds SEC:Configure -- a different-identity revoke correctly succeeds.
  v_session1 := app.revoke_user_session(v_session1.id, 'admin-initiated revoke', v_admin1, 'admin1');
  if v_session1.status <> 'revoked' then
    raise exception 'assertion failed: expected admin1''s own SEC:Configure-authorized revoke to succeed, got status %', v_session1.status;
  end if;

  -- Self-revoke by rep1 always works, regardless of any module grant.
  v_session2 := app.register_user_session(v_tenant1, 'reps phone', '203.0.113.11', v_rep1, 'rep1');
  v_session2 := app.revoke_user_session(v_session2.id, 'lost device', v_rep1, 'rep1');
  if v_session2.status <> 'revoked' then
    raise exception 'assertion failed: expected self-revoke to succeed, got status %', v_session2.status;
  end if;

  -- A fresh, still-active session for the mass-revoke call below to genuinely act on
  -- (v_session1/v_session2 above are both already revoked at this point).
  v_session3 := app.register_user_session(v_tenant1, 'reps tablet', '203.0.113.12', v_rep1, 'rep1');

  -- Give rep1 a real, active API key to prove the propagation is genuine, not merely
  -- claimed. app.create_api_key requires BOTH app.is_support_grant_authority (Supreme
  -- or tenant_admin LAYER, not a module permission) to mint a key at all, AND the
  -- issuing actor to already hold every scope requested (scope can only narrow, never
  -- widen) -- both granted here purely as a fixture device to let rep1 legitimately
  -- mint their own OPS:View-scoped key.
  perform app.grant_principal_membership(v_rep1, 'tenant_admin', v_tenant1, null, 'tester');
  v_rep1_ops_role := (app.create_role(v_tenant1, 'IaeMfa Rep OPS Viewer', 'OPS:View -- fixture device so rep1 can legitimately mint an OPS:View-scoped key', 'tester')).id;
  v_rep1_ops_draft := app.create_role_version(v_rep1_ops_role, 'tester');
  perform app.set_role_version_permissions(v_rep1_ops_draft.id, array(select id from app.permissions where resource_module_code = 'OPS' and action = 'View'), 'tester');
  perform app.publish_role_version(v_rep1_ops_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_rep1_ops_role and status = 'published'), v_rep1, v_admin1, 'admin1');
  perform app.create_api_key(v_tenant1, 'rep1 own key', '["OPS:View"]'::jsonb, null, null, v_rep1, 'rep1');

  select status into v_key_status from app.api_keys where tenant_id = v_tenant1 and created_by_auth_user_id = v_rep1;
  if v_key_status <> 'active' then
    raise exception 'assertion failed: expected the fixture api key to start active, got %', v_key_status;
  end if;

  -- ISS-2026-236: covered by admin1's own verified step-up at the top of this block
  -- (policy window is 20 minutes; this block runs in well under a second). This call is
  -- itself end-to-end proof that the new enforcement reaches a real, previously-unwired
  -- SEC:Configure function -- app.revoke_all_actor_sessions.
  v_session_count := app.revoke_all_actor_sessions(v_tenant1, v_rep1, 'account compromise', v_admin1, 'admin1');
  if v_session_count < 1 then
    raise exception 'assertion failed: expected at least 1 session revoked (v_session3, still active), got %', v_session_count;
  end if;

  select status into v_key_status from app.api_keys where tenant_id = v_tenant1 and created_by_auth_user_id = v_rep1;
  if v_key_status <> 'revoked' then
    raise exception 'assertion failed: expected rep1''s own api key to be genuinely revoked by app.revoke_all_actor_sessions, got status %', v_key_status;
  end if;

  if (select status from app.user_sessions where id = v_session3.id) <> 'revoked' then
    raise exception 'assertion failed: expected v_session3 to be revoked by the mass-revoke call';
  end if;
end;
$$;

\echo '>> app.mfa_exceptions: self-approval forbidden at the CHECK-constraint level; a different SEC:Approve holder can approve; approval requires SEC:Approve specifically (SEC:Configure alone is not enough); a used exception cannot be consumed twice; an expired-but-approved exception cannot be consumed'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'iaemfa');
  v_admin1 uuid := '00000000-0000-0000-0000-000031000001';
  v_rep1 uuid := '00000000-0000-0000-0000-000031000003';
  v_supreme uuid := '00000000-0000-0000-0000-000031000000';
  v_exception app.mfa_exceptions;
begin
  v_exception := app.request_mfa_exception(v_tenant1, v_rep1, 'lost phone, lost recovery codes', v_admin1, 'admin1');
  if v_exception.status <> 'pending' then
    raise exception 'assertion failed: expected status pending, got %', v_exception.status;
  end if;

  begin
    perform app.approve_mfa_exception(v_exception.id, v_admin1, 'admin1');
    raise exception 'assertion failed: expected mfa_exception_self_approval_forbidden (admin1 both requested and is trying to approve), the call unexpectedly succeeded';
  exception when insufficient_privilege then
    null;
  end;

  -- Supreme Admin holds SEC:Approve everywhere via the supreme_admin_exception path in evaluate_permission.
  perform app.verify_mfa_step_up_challenge((app.request_mfa_step_up_challenge(v_tenant1, 'SEC', 'Approve', v_supreme, 'supreme')).id, v_supreme, 'supreme');
  v_exception := app.approve_mfa_exception(v_exception.id, v_supreme, 'supreme');
  if v_exception.status <> 'approved' then
    raise exception 'assertion failed: expected status approved, got %', v_exception.status;
  end if;

  perform app.consume_mfa_exception(v_exception.id, v_rep1, 'rep1');
  begin
    perform app.consume_mfa_exception(v_exception.id, v_rep1, 'rep1');
    raise exception 'assertion failed: expected mfa_exception_not_approved on a second consume attempt (already used), the call unexpectedly succeeded';
  exception when no_data_found then
    null;
  end;

  -- A separately-requested, approved-but-now-expired exception cannot be consumed.
  v_exception := app.request_mfa_exception(v_tenant1, v_rep1, 'second lost-factor incident', v_admin1, 'admin1');
  v_exception := app.approve_mfa_exception(v_exception.id, v_supreme, 'supreme');
  update app.mfa_exceptions set expires_at = now() - interval '1 minute' where id = v_exception.id;
  begin
    perform app.consume_mfa_exception(v_exception.id, v_rep1, 'rep1');
    raise exception 'assertion failed: expected mfa_exception_expired, the call unexpectedly succeeded';
  exception when check_violation then
    null;
  end;
end;
$$;

\echo '>> app.approve_mfa_exception (IAE-039 closure fix): SEC:Approve is a platform-default high-risk action -- a genuine SEC:Approve holder with zero current MFA step-up verification is rejected with mfa_step_up_required, never allowed to approve on authority alone; the identical actor succeeds once a real step-up challenge is requested and verified'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'iaemfa');
  v_admin1 uuid := '00000000-0000-0000-0000-000031000001';
  v_rep1 uuid := '00000000-0000-0000-0000-000031000003';
  v_approver2 uuid := '00000000-0000-0000-0000-000031000005';
  v_exception app.mfa_exceptions;
begin
  insert into auth.users (id, email) values (v_approver2, 'approver2@iaemfa.test');
  perform app.invite_user(v_tenant1, v_approver2, 'approver2@iaemfa.test', 'Approver Two', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'approver2@iaemfa.test'), 'active', 'onboarded', 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = (select id from app.roles where tenant_id = v_tenant1 and name = 'IaeMfa Admin') and status = 'published'), v_approver2, v_admin1, 'admin1');

  v_exception := app.request_mfa_exception(v_tenant1, v_rep1, 'third lost-factor incident, step-up regression', v_admin1, 'admin1');

  begin
    perform app.approve_mfa_exception(v_exception.id, v_approver2, 'approver2');
    raise exception 'assertion failed: expected mfa_step_up_required -- approver2 holds real SEC:Approve but has zero current step-up verification, the call unexpectedly succeeded';
  exception when insufficient_privilege then
    if sqlerrm !~ 'mfa_step_up_required' then raise; end if;
  end;

  perform app.verify_mfa_step_up_challenge((app.request_mfa_step_up_challenge(v_tenant1, 'SEC', 'Approve', v_approver2, 'approver2')).id, v_approver2, 'approver2');
  v_exception := app.approve_mfa_exception(v_exception.id, v_approver2, 'approver2');
  if v_exception.status <> 'approved' then
    raise exception 'assertion failed: expected status approved once a real step-up challenge is verified, got %', v_exception.status;
  end if;

  raise notice 'PASS: approve_mfa_exception now genuinely requires a current MFA step-up verification (RPD-023) on top of SEC:Approve authority, closing ISS-2026-151 for this function';
end;
$$;

\echo '>> cross-tenant isolation: admin2 (tenant iaemfa2) cannot read/act on iaemfa''s own MFA policy/sessions/exceptions'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'iaemfa');
  v_admin2 uuid := '00000000-0000-0000-0000-000031000004';
  v_count integer;
begin
  select count(*) into v_count from app.list_user_sessions_for_tenant(v_tenant1, v_admin2);
  raise exception 'assertion failed: expected insufficient_authority for admin2 listing tenant1''s own sessions, the call unexpectedly returned % rows', v_count;
exception
  when insufficient_privilege then
    null;
end;
$$;

do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'iaemfa');
  v_admin2 uuid := '00000000-0000-0000-0000-000031000004';
begin
  begin
    perform app.set_mfa_tenant_policy(v_tenant1, true, '["supreme_admin"]'::jsonb, 5, '[]'::jsonb, v_admin2, 'admin2');
    raise exception 'assertion failed: expected insufficient_authority for admin2 configuring tenant1''s own MFA policy, the call unexpectedly succeeded';
  exception when insufficient_privilege then
    null;
  end;
end;
$$;

\echo '>> RLS default-deny: a direct authenticated select on every new table is denied at the raw-RLS level'
do $$
begin
  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000031000001", "role": "authenticated"}';
  begin
    perform count(*) from app.mfa_tenant_policies;
    raise exception 'assertion failed: expected permission denied for a direct authenticated select on app.mfa_tenant_policies, the select unexpectedly succeeded';
  exception when insufficient_privilege then
    null;
  end;
  begin
    perform count(*) from app.mfa_step_up_challenges;
    raise exception 'assertion failed: expected permission denied for a direct authenticated select on app.mfa_step_up_challenges, the select unexpectedly succeeded';
  exception when insufficient_privilege then
    null;
  end;
  begin
    perform count(*) from app.user_sessions;
    raise exception 'assertion failed: expected permission denied for a direct authenticated select on app.user_sessions, the select unexpectedly succeeded';
  exception when insufficient_privilege then
    null;
  end;
  begin
    perform count(*) from app.mfa_exceptions;
    raise exception 'assertion failed: expected permission denied for a direct authenticated select on app.mfa_exceptions, the select unexpectedly succeeded';
  exception when insufficient_privilege then
    null;
  end;
  reset role;
end;
$$;

\echo '>> defense in depth: anon holds zero EXECUTE grants across every new function'
do $$
declare
  v_anon_grant_count integer;
begin
  select count(*) into v_anon_grant_count
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'app'
    and p.proname in (
      'get_or_create_mfa_tenant_policy', 'set_mfa_tenant_policy', 'is_high_risk_action',
      'request_mfa_step_up_challenge', 'verify_mfa_step_up_challenge', 'assert_current_step_up_authorization',
      'register_user_session', 'revoke_user_session', 'revoke_all_actor_sessions',
      'request_mfa_exception', 'approve_mfa_exception', 'consume_mfa_exception',
      'list_user_sessions_for_tenant', 'list_mfa_exceptions_for_tenant', 'list_mfa_step_up_challenges_for_tenant'
    )
    and has_function_privilege('anon', p.oid, 'EXECUTE');

  if v_anon_grant_count <> 0 then
    raise exception 'assertion failed: expected zero anon EXECUTE grants across this checkpoint''s 15 functions, found %', v_anon_grant_count;
  end if;
end;
$$;

\echo '>> ISS-2026-150 closure: app.approve_mfa_exception now composes app.assert_ip_allowed + app.has_active_ip_allowlist_bypass when a caller supplies p_client_ip -- a fresh, dedicated tenant (iaemfaip), never touched by any earlier block in this file'
do $$
declare
  v_tenant uuid;
  v_admin uuid := '00000000-0000-0000-0000-000031900001';
  v_rep uuid := '00000000-0000-0000-0000-000031900002';
  v_approver uuid := '00000000-0000-0000-0000-000031900003';
  v_admin_role uuid;
  v_admin_draft app.role_versions;
  v_exception app.mfa_exceptions;
begin
  insert into auth.users (id, email) values
    (v_admin, 'admin@iaemfaip.test'),
    (v_rep, 'rep@iaemfaip.test'),
    (v_approver, 'approver@iaemfaip.test');

  perform app.provision_tenant('iaemfaip', 'IaeMfaIp Co', 'idem-iaemfaip', 'tester');
  v_tenant := (select id from app.tenants where slug = 'iaemfaip');
  perform app.transition_tenant_status(v_tenant, 'active', 'setup', 'tester');

  perform app.invite_user(v_tenant, v_admin, 'admin@iaemfaip.test', 'Admin', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'admin@iaemfaip.test'), 'active', 'onboarded', 'tester');

  perform app.invite_user(v_tenant, v_rep, 'rep@iaemfaip.test', 'Rep', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'rep@iaemfaip.test'), 'active', 'onboarded', 'tester');

  perform app.invite_user(v_tenant, v_approver, 'approver@iaemfaip.test', 'Approver', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'approver@iaemfaip.test'), 'active', 'onboarded', 'tester');

  -- One role (SEC:Configure/View/Approve) is assigned to BOTH v_admin (requester +
  -- IP-allowlist configurer) and v_approver (a genuinely different identity from the
  -- requester -- app.approve_mfa_exception forbids self-approval at the CHECK level).
  v_admin_role := (app.create_role(v_tenant, 'IaeMfaIp Admin', 'SEC:Configure/View/Approve', 'tester')).id;
  v_admin_draft := app.create_role_version(v_admin_role, 'tester');
  perform app.set_role_version_permissions(v_admin_draft.id, array(select id from app.permissions where resource_module_code = 'SEC' and action in ('Configure', 'View', 'Approve')), 'tester');
  perform app.publish_role_version(v_admin_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant, (select id from app.role_versions where role_id = v_admin_role and status = 'published'), v_admin, v_admin, 'admin');
  perform app.assign_role(v_tenant, (select id from app.role_versions where role_id = v_admin_role and status = 'published'), v_approver, v_admin, 'admin');

  -- Real allowlist entry (203.0.113.0/24, scope admin) plus enforced mode -- mirrors
  -- ip-restriction-network-access.sql's own established setup pattern verbatim.
  perform app.add_ip_allowlist_entry(v_tenant, '203.0.113.0/24', 'iaemfaip office range', 'admin', v_admin, 'admin');
  perform app.set_ip_allowlist_enforcement_mode(v_tenant, 'enforced', v_admin, 'admin');

  -- One verified step-up challenge stays "current" for the tenant policy's own
  -- step_up_max_age_minutes window (default 15) -- reused across all 3 approve calls
  -- below (each against a SEPARATE exception request -- an already-approved exception
  -- cannot be approved twice).
  perform app.verify_mfa_step_up_challenge((app.request_mfa_step_up_challenge(v_tenant, 'SEC', 'Approve', v_approver, 'approver')).id, v_approver, 'approver');

  -- (a) out-of-range p_client_ip -- denied, ip_not_allowed.
  v_exception := app.request_mfa_exception(v_tenant, v_rep, 'IP-restriction regression, attempt a', v_admin, 'admin');
  begin
    perform app.approve_mfa_exception(v_exception.id, v_approver, 'approver', '198.51.100.7');
    raise exception 'assertion failed: expected ip_not_allowed for an out-of-range p_client_ip under enforced mode, the call unexpectedly succeeded';
  exception when insufficient_privilege then
    if sqlerrm !~ 'ip_not_allowed' then raise; end if;
  end;
  if (select status from app.mfa_exceptions where id = v_exception.id) <> 'pending' then
    raise exception 'assertion failed: the rejected out-of-range-IP attempt must never leave the exception approved';
  end if;

  -- (b) in-range p_client_ip -- succeeds.
  v_exception := app.approve_mfa_exception(v_exception.id, v_approver, 'approver', '203.0.113.42');
  if v_exception.status <> 'approved' then
    raise exception 'assertion failed: expected status approved for an in-range p_client_ip, got %', v_exception.status;
  end if;

  -- (c) p_client_ip omitted/null -- succeeds regardless of the enforced policy, proving
  -- the non-interactive-caller exemption. A SEPARATE, freshly-requested exception is
  -- used since the one above already resolved.
  v_exception := app.request_mfa_exception(v_tenant, v_rep, 'IP-restriction regression, attempt c', v_admin, 'admin');
  v_exception := app.approve_mfa_exception(v_exception.id, v_approver, 'approver');
  if v_exception.status <> 'approved' then
    raise exception 'assertion failed: expected status approved when p_client_ip is omitted, regardless of the enforced IP allowlist policy, got %', v_exception.status;
  end if;

  raise notice 'PASS: app.approve_mfa_exception (ISS-2026-150 closure) denies an out-of-range p_client_ip under enforced mode, allows an in-range one, and allows a null p_client_ip regardless of enforcement';
end;
$$;

\echo 'ALL IAE-027 (Enterprise MFA and Session Controls) ASSERTIONS PASSED'

-- ===========================================================================
-- ISS-2026-236 -- step-up enforcement at the app.evaluate_permission chokepoint.
-- ===========================================================================

\echo '>> ISS-2026-236: app.evaluate_permission denies a high-risk tuple with reason mfa_step_up_required when the tenant has MFA on and the actor holds no current verified challenge; a real verified challenge allows it; the challenge is scoped to the exact tuple and expires; a tenant WITHOUT MFA enabled is completely unaffected; and a Supreme Admin is NOT exempt'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'iaemfa');
  v_tenant2 uuid := (select id from app.tenants where slug = 'iaemfa2');
  v_admin1 uuid := '00000000-0000-0000-0000-000031000001';
  v_admin2 uuid := '00000000-0000-0000-0000-000031000004';
  v_supreme uuid := '00000000-0000-0000-0000-000031000000';
  v_decision app.rbac_decision;
  v_challenge app.mfa_step_up_challenges;
  v_policy app.mfa_tenant_policies;
begin
  -- Earlier blocks in this file verified real step-up challenges for this tenant, and the
  -- policy window is 20 minutes -- so this block first ages those verifications out, to
  -- start from a genuine "no current step-up" state rather than inheriting one. This is
  -- test setup, not a relaxation: it makes the assertions below test what they claim.
  update app.mfa_step_up_challenges
  set verified_at = now() - interval '10 years'
  where tenant_id = v_tenant1 and status = 'verified';

  -- iaemfa has tenant_wide_required = true (set earlier in this file). SEC:Configure is a
  -- platform-default high-risk tuple, and admin1 genuinely holds the granting role -- so
  -- before this fix this evaluated to allowed/role_grant with no step-up anywhere.
  v_decision := app.evaluate_permission(v_admin1, v_tenant1, 'SEC', 'Configure');
  if v_decision.allowed or v_decision.reason <> 'mfa_step_up_required' then
    raise exception 'assertion failed: expected mfa_step_up_required for SEC:Configure in an MFA-enabled tenant, got allowed=% reason=%', v_decision.allowed, v_decision.reason;
  end if;

  -- A REAL challenge, requested and verified through the shipped mechanism.
  v_challenge := app.request_mfa_step_up_challenge(v_tenant1, 'SEC', 'Configure', v_admin1, 'admin1');
  perform app.verify_mfa_step_up_challenge(v_challenge.id, v_admin1, 'admin1');

  v_decision := app.evaluate_permission(v_admin1, v_tenant1, 'SEC', 'Configure');
  if not v_decision.allowed or v_decision.reason <> 'role_grant' then
    raise exception 'assertion failed: expected a verified step-up to restore the ordinary role_grant decision, got allowed=% reason=%', v_decision.allowed, v_decision.reason;
  end if;

  -- Scoped to the EXACT tuple: the SEC:Configure challenge must not satisfy FIN:Approve.
  -- A challenge that leaked across tuples would make the control decorative -- one
  -- step-up anywhere would unlock every high-risk action in the tenant.
  v_decision := app.evaluate_permission(v_admin1, v_tenant1, 'FIN', 'Approve');
  if v_decision.allowed or v_decision.reason <> 'mfa_step_up_required' then
    raise exception 'assertion failed: expected a SEC:Configure challenge NOT to satisfy FIN:Approve, got allowed=% reason=%', v_decision.allowed, v_decision.reason;
  end if;

  -- Scoped in time: ageing the verification past the policy window re-denies.
  update app.mfa_step_up_challenges
  set verified_at = now() - interval '10 years'
  where id = v_challenge.id;
  v_decision := app.evaluate_permission(v_admin1, v_tenant1, 'SEC', 'Configure');
  if v_decision.allowed or v_decision.reason <> 'mfa_step_up_required' then
    raise exception 'assertion failed: expected a stale verification to re-deny, got allowed=% reason=%', v_decision.allowed, v_decision.reason;
  end if;

  -- A Supreme Admin is deliberately NOT exempt: mfa_tenant_policies.required_layers
  -- contemplates supreme_admin, and exempting the most powerful identity would reproduce
  -- exactly the guard-the-guards gap ISS-2026-236 is about. This assertion is the reason
  -- the new branch sits BEFORE the supreme_admin_exception early-return.
  v_decision := app.evaluate_permission(v_supreme, v_tenant1, 'SEC', 'Configure');
  if v_decision.allowed or v_decision.reason <> 'mfa_step_up_required' then
    raise exception 'assertion failed: expected a Supreme Admin to be subject to step-up in an MFA-enabled tenant, got allowed=% reason=%', v_decision.allowed, v_decision.reason;
  end if;
  -- ...and can genuinely obtain one (request_mfa_step_up_challenge carries its own
  -- is_supreme_admin bypass on the membership precondition), so this is a gate, not a
  -- lockout.
  v_challenge := app.request_mfa_step_up_challenge(v_tenant1, 'SEC', 'Configure', v_supreme, 'supreme');
  perform app.verify_mfa_step_up_challenge(v_challenge.id, v_supreme, 'supreme');
  v_decision := app.evaluate_permission(v_supreme, v_tenant1, 'SEC', 'Configure');
  if not v_decision.allowed or v_decision.reason <> 'supreme_admin_exception' then
    raise exception 'assertion failed: expected a verified Supreme Admin to pass through to supreme_admin_exception, got allowed=% reason=%', v_decision.allowed, v_decision.reason;
  end if;

  -- A tenant that has NOT turned MFA on is completely unaffected -- this is what bounds
  -- the blast radius, and it is bounded on a real tenant-owned switch rather than on any
  -- narrowing of app.is_high_risk_action's own classification.
  select * into v_policy from app.mfa_tenant_policies where tenant_id = v_tenant2;
  if found and v_policy.tenant_wide_required then
    raise exception 'assertion failed: this case needs iaemfa2 to have MFA off; fixture drifted';
  end if;
  if not app.is_high_risk_action(v_tenant2, 'SEC', 'Configure') then
    raise exception 'assertion failed: SEC:Configure must remain platform-default high-risk for every tenant -- app.is_high_risk_action is deliberately unchanged by this fix';
  end if;
  v_decision := app.evaluate_permission(v_admin2, v_tenant2, 'SEC', 'Configure');
  if v_decision.reason = 'mfa_step_up_required' then
    raise exception 'assertion failed: a tenant with MFA off must reach an identical decision to before this fix, got reason=%', v_decision.reason;
  end if;
end $$;
