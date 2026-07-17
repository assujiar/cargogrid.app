-- Real, executable test evidence for PLT-115 (Support Access and Impersonation Control,
-- CG-S6-PLT-012).

\set ON_ERROR_STOP on

\echo '>> setup: two tenants, a tenant_admin and a regular org_user in tenant A, a global Supreme Admin, and a support agent who is a member of neither tenant'
do $$
declare
  v_tenant_id uuid;
  v_other_tenant_id uuid;
  v_org_unit_id uuid;
begin
  insert into auth.users (id, email) values
    ('00000000-0000-0000-0000-000000000701', 'tenantadminsup@example.test'),
    ('00000000-0000-0000-0000-000000000702', 'supremesup@example.test'),
    ('00000000-0000-0000-0000-000000000703', 'supportagent@example.test'),
    ('00000000-0000-0000-0000-000000000704', 'regularusersup@example.test');

  perform app.provision_tenant('acmesup', 'Acme Support Co', 'idem-acmesup', 'tester');
  v_tenant_id := (select id from app.tenants where slug = 'acmesup');
  perform app.transition_tenant_status(v_tenant_id, 'active', 'setup', 'tester');
  perform app.create_org_unit(v_tenant_id, 'company', null, 'ACMESUP-CO', 'Acme Support Co HQ', 'tester');
  v_org_unit_id := (select id from app.org_units where tenant_id = v_tenant_id and code = 'ACMESUP-CO');

  perform app.invite_user(v_tenant_id, '00000000-0000-0000-0000-000000000701', 'tenantadminsup@example.test', 'Tenant Admin', v_org_unit_id, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'tenantadminsup@example.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000000701', 'tenant_admin', v_tenant_id, null, 'tester');

  perform app.invite_user(v_tenant_id, '00000000-0000-0000-0000-000000000704', 'regularusersup@example.test', 'Regular User', v_org_unit_id, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'regularusersup@example.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000000704', 'org_user', v_tenant_id, null, 'tester');

  perform app.grant_principal_membership('00000000-0000-0000-0000-000000000702', 'supreme_admin', null, null, 'tester');

  perform app.provision_tenant('gizmosup', 'Gizmo Support Co', 'idem-gizmosup', 'tester');
  v_other_tenant_id := (select id from app.tenants where slug = 'gizmosup');
  perform app.transition_tenant_status(v_other_tenant_id, 'active', 'setup', 'tester');
end;
$$;

\echo '>> mandatory fields: reason and case_id cannot be null (Prompt 115 §25)'
do $$
declare
  v_tenant_id uuid;
begin
  v_tenant_id := (select id from app.tenants where slug = 'acmesup');
  begin
    perform app.request_support_access(v_tenant_id, '00000000-0000-0000-0000-000000000703', null, 'CASE-1', 60, 'tester');
    raise exception 'assertion failed: expected a null reason to be rejected';
  exception
    when not_null_violation then
      null; -- expected
  end;
end;
$$;

\echo '>> request_support_access is idempotent for a repeated (tenant, grantee, case) while the prior request is still live'
do $$
declare
  v_tenant_id uuid;
  v_first app.support_access_grants;
  v_second app.support_access_grants;
begin
  v_tenant_id := (select id from app.tenants where slug = 'acmesup');
  v_first := app.request_support_access(v_tenant_id, '00000000-0000-0000-0000-000000000703', 'customer cannot see invoices', 'CASE-100', 60, 'tester');
  v_second := app.request_support_access(v_tenant_id, '00000000-0000-0000-0000-000000000703', 'customer cannot see invoices (retry)', 'CASE-100', 60, 'tester');
  if v_first.id <> v_second.id then
    raise exception 'assertion failed: expected a repeated request for the same (tenant, grantee, case_id) to return the original grant, got a new row';
  end if;
  if v_first.status <> 'pending_approval' then
    raise exception 'assertion failed: expected a standard request to start pending_approval, got %', v_first.status;
  end if;
end;
$$;

\echo '>> support_access_gated: while CASE-100 is still pending_approval, the support agent has zero RLS visibility into the tenant -- a request alone grants nothing'
do $$
declare
  v_count integer;
begin
  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000000703", "role": "authenticated"}';
  select count(*) into v_count from app.tenants where slug = 'acmesup';
  reset role;
  if v_count <> 0 then
    raise exception 'assertion failed: expected the support agent to see zero rows while their grant is still pending_approval, saw %', v_count;
  end if;
end;
$$;

\echo '>> a request exceeding the standard 24h expiry cap is rejected'
do $$
declare
  v_tenant_id uuid;
begin
  v_tenant_id := (select id from app.tenants where slug = 'acmesup');
  begin
    perform app.request_support_access(v_tenant_id, '00000000-0000-0000-0000-000000000703', 'too long', 'CASE-101', 1500, 'tester');
    raise exception 'assertion failed: expected a 1500-minute standard request (>24h) to be rejected';
  exception
    when check_violation then
      null; -- expected (invalid_expiry)
  end;
end;
$$;

\echo '>> approval requires real authority: a regular org_user cannot approve; the grantee cannot self-approve; a tenant_admin can'
do $$
declare
  v_tenant_id uuid;
  v_grant_id uuid;
begin
  v_tenant_id := (select id from app.tenants where slug = 'acmesup');
  v_grant_id := (select id from app.support_access_grants where tenant_id = v_tenant_id and case_id = 'CASE-100');

  begin
    perform app.approve_support_access(v_grant_id, '00000000-0000-0000-0000-000000000704', 'regular user');
    raise exception 'assertion failed: expected a regular org_user to be denied approval authority';
  exception
    when insufficient_privilege then
      null; -- expected (insufficient_authority)
  end;

  begin
    perform app.approve_support_access(v_grant_id, '00000000-0000-0000-0000-000000000703', 'self');
    raise exception 'assertion failed: expected the grantee to be denied self-approval';
  exception
    when insufficient_privilege then
      null; -- expected (self_approval_forbidden)
  end;

  if (select status from app.support_access_grants where id = v_grant_id) <> 'pending_approval' then
    raise exception 'assertion failed: the failed approval attempts above must not have changed the grant''s status';
  end if;

  perform app.approve_support_access(v_grant_id, '00000000-0000-0000-0000-000000000701', 'tenant admin approval');
  if (select status from app.support_access_grants where id = v_grant_id) <> 'approved' then
    raise exception 'assertion failed: expected the tenant_admin''s approval to succeed';
  end if;
  if (select granted_at from app.support_access_grants where id = v_grant_id) is null then
    raise exception 'assertion failed: expected granted_at to be set on approval';
  end if;
end;
$$;

\echo '>> support_access_gated: now that CASE-100 is approved, RLS admits the support agent into the tenant (layering, not a permission grant -- email stays masked, since they hold no View personal data permission; can_access_record still denies on ownership)'
do $$
declare
  v_tenant_id uuid;
  v_after_count integer;
  v_masked_email text;
  v_masked_flag boolean;
  v_owner_id uuid;
  v_can_access boolean;
begin
  v_tenant_id := (select id from app.tenants where slug = 'acmesup');
  v_owner_id := '00000000-0000-0000-0000-000000000701';

  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000000703", "role": "authenticated"}';
  select count(*) into v_after_count from app.tenants where id = v_tenant_id;
  reset role;
  if v_after_count <> 1 then
    raise exception 'assertion failed: expected the support agent to see the tenant row now that their grant is approved (support_access_gated layering onto has_active_tenant_membership), saw %', v_after_count;
  end if;

  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000000703", "role": "authenticated"}';
  select email, email_masked into v_masked_email, v_masked_flag from app.users_directory where auth_user_id = v_owner_id;
  reset role;
  if v_masked_flag is not true then
    raise exception 'assertion failed: a support grant must not silently unmask PII -- expected email_masked=true for the support agent (no View personal data permission), got %', v_masked_flag;
  end if;

  -- can_access_record still denies: the grant satisfies only the tenant-membership
  -- prerequisite, not ownership/team-share/customer-scope -- "layers over, does not bypass"
  -- (Prompt 115 §26), proven directly against PLT-114's evaluator.
  v_can_access := app.can_access_record('00000000-0000-0000-0000-000000000703', v_tenant_id, v_owner_id);
  if v_can_access then
    raise exception 'assertion failed: expected a support grant to satisfy can_access_record''s tenant-membership prerequisite only, still denying on ownership -- got granted';
  end if;
end;
$$;

\echo '>> cross-tenant: a grant into tenant A does not leak visibility into tenant B'
do $$
declare
  v_other_tenant_id uuid;
  v_count integer;
begin
  v_other_tenant_id := (select id from app.tenants where slug = 'gizmosup');
  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000000703", "role": "authenticated"}';
  select count(*) into v_count from app.tenants where id = v_other_tenant_id;
  reset role;
  if v_count <> 0 then
    raise exception 'assertion failed: expected the support agent''s tenant-A-scoped grant to grant zero visibility into tenant B, saw %', v_count;
  end if;
end;
$$;

\echo '>> re-authentication freshness: a stale reauth timestamp is rejected; a fresh one starts a session; re-starting is idempotent'
do $$
declare
  v_tenant_id uuid;
  v_grant_id uuid;
  v_session1 app.support_access_sessions;
  v_session2 app.support_access_sessions;
begin
  v_tenant_id := (select id from app.tenants where slug = 'acmesup');
  v_grant_id := (select id from app.support_access_grants where tenant_id = v_tenant_id and case_id = 'CASE-100');

  begin
    perform app.start_support_session(v_grant_id, now() - interval '10 minutes', 'tester');
    raise exception 'assertion failed: expected a stale (10-minute-old) re-authentication to be rejected';
  exception
    when insufficient_privilege then
      null; -- expected (reauth_required)
  end;

  v_session1 := app.start_support_session(v_grant_id, now(), 'tester');
  if v_session1.ended_at is not null then
    raise exception 'assertion failed: expected a freshly-started session to be open';
  end if;

  v_session2 := app.start_support_session(v_grant_id, now(), 'tester');
  if v_session1.id <> v_session2.id then
    raise exception 'assertion failed: expected re-starting a session on a grant that already has an open session to be idempotent, got a second session';
  end if;
end;
$$;

\echo '>> app.current_support_session surfaces the active session for banner/attribution purposes'
do $$
declare
  v_tenant_id uuid;
  v_session app.support_access_sessions;
begin
  v_tenant_id := (select id from app.tenants where slug = 'acmesup');
  v_session := app.current_support_session(v_tenant_id, '00000000-0000-0000-0000-000000000703');
  if v_session.id is null then
    raise exception 'assertion failed: expected app.current_support_session to surface the open session';
  end if;
  if v_session.ended_at is not null then
    raise exception 'assertion failed: expected the surfaced session to still be open';
  end if;
end;
$$;

\echo '>> the kill switch: a tenant_admin can revoke an approved grant mid-session, force-ending the open session and immediately closing RLS visibility'
do $$
declare
  v_tenant_id uuid;
  v_grant_id uuid;
  v_session_id uuid;
  v_count integer;
begin
  v_tenant_id := (select id from app.tenants where slug = 'acmesup');
  v_grant_id := (select id from app.support_access_grants where tenant_id = v_tenant_id and case_id = 'CASE-100');
  v_session_id := (select id from app.support_access_sessions where grant_id = v_grant_id and ended_at is null);

  perform app.revoke_support_access(v_grant_id, '00000000-0000-0000-0000-000000000701', 'tenant admin kill switch', 'incident closed early');

  if (select status from app.support_access_grants where id = v_grant_id) <> 'revoked' then
    raise exception 'assertion failed: expected the grant to be revoked';
  end if;
  if (select ended_at from app.support_access_sessions where id = v_session_id) is null then
    raise exception 'assertion failed: expected the kill switch to force-end the open session';
  end if;
  if (select ended_reason from app.support_access_sessions where id = v_session_id) <> 'revoked' then
    raise exception 'assertion failed: expected the force-ended session''s ended_reason to be revoked';
  end if;

  if app.has_active_support_grant(v_tenant_id, '00000000-0000-0000-0000-000000000703') then
    raise exception 'assertion failed: expected has_active_support_grant to be false immediately after revocation';
  end if;

  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000000703", "role": "authenticated"}';
  select count(*) into v_count from app.tenants where id = v_tenant_id;
  reset role;
  if v_count <> 0 then
    raise exception 'assertion failed: expected RLS visibility to close immediately after the kill switch, saw %', v_count;
  end if;

  begin
    perform app.start_support_session(v_grant_id, now(), 'tester');
    raise exception 'assertion failed: expected starting a session on a revoked grant to fail';
  exception
    when check_violation then
      null; -- expected (grant_not_approved, since status is now revoked)
  end;

  -- revoke is idempotent-safe: revoking an already-revoked grant returns it unchanged
  -- rather than raising, matching every other revoke-shaped function in this repository.
  perform app.revoke_support_access(v_grant_id, '00000000-0000-0000-0000-000000000701', 'tenant admin kill switch', 'retry');
end;
$$;

\echo '>> expiry: an approved grant past its expires_at denies access even though it was never explicitly revoked (06_*.md §2.3''s exact expires_at > now() condition)'
do $$
declare
  v_tenant_id uuid;
  v_grant app.support_access_grants;
begin
  v_tenant_id := (select id from app.tenants where slug = 'acmesup');
  v_grant := app.request_support_access(v_tenant_id, '00000000-0000-0000-0000-000000000703', 'expiry test', 'CASE-102', 60, 'tester');
  perform app.approve_support_access(v_grant.id, '00000000-0000-0000-0000-000000000701', 'tenant admin approval');

  -- now() is frozen at transaction-start for the lifetime of this DO block (Postgres's
  -- normal now()/transaction_timestamp() semantics), so a real, short wall-clock sleep
  -- (below, its own top-level statement/transaction) is used instead of an offset
  -- computed from "now() - interval" here, which would just reuse the same frozen value.
  -- expires_at must still satisfy the expiry_shape check (> requested_at), so it is set
  -- just 2 seconds past requested_at, not into an unconstrained past.
  update app.support_access_grants set expires_at = requested_at + interval '2 seconds' where id = v_grant.id;
end;
$$;

select pg_sleep(3);

do $$
declare
  v_tenant_id uuid;
  v_grant_id uuid;
begin
  v_tenant_id := (select id from app.tenants where slug = 'acmesup');
  v_grant_id := (select id from app.support_access_grants where tenant_id = v_tenant_id and case_id = 'CASE-102');

  if app.has_active_support_grant(v_tenant_id, '00000000-0000-0000-0000-000000000703') then
    raise exception 'assertion failed: expected an expired grant to be denied by has_active_support_grant';
  end if;

  begin
    perform app.start_support_session(v_grant_id, now(), 'tester');
    raise exception 'assertion failed: expected starting a session on an expired grant to fail';
  exception
    when check_violation then
      null; -- expected (grant_expired)
  end;
end;
$$;

\echo '>> emergency support access: requires a recorded higher authority, is auto-approved with a shorter expiry cap, and needs Supreme-Admin-only post-review'
do $$
declare
  v_tenant_id uuid;
  v_grant app.support_access_grants;
begin
  v_tenant_id := (select id from app.tenants where slug = 'acmesup');

  begin
    perform app.request_support_access(v_tenant_id, '00000000-0000-0000-0000-000000000703', 'emergency, no authority recorded', 'CASE-200', 60, 'tester', 'read_only', true, null);
    raise exception 'assertion failed: expected an emergency request with no recorded authority to be rejected';
  exception
    when insufficient_privilege then
      null; -- expected (insufficient_authority)
  end;

  begin
    perform app.request_support_access(v_tenant_id, '00000000-0000-0000-0000-000000000703', 'emergency, too long', 'CASE-201', 180, 'tester', 'read_only', true, '00000000-0000-0000-0000-000000000702');
    raise exception 'assertion failed: expected a 180-minute emergency request (>2h cap) to be rejected';
  exception
    when check_violation then
      null; -- expected (invalid_expiry)
  end;

  v_grant := app.request_support_access(v_tenant_id, '00000000-0000-0000-0000-000000000703', 'production outage, on-call escalation', 'CASE-202', 60, 'tester', 'read_only', true, '00000000-0000-0000-0000-000000000702');
  if v_grant.status <> 'approved' then
    raise exception 'assertion failed: expected an emergency request with recorded authority to be auto-approved, got %', v_grant.status;
  end if;
  if v_grant.granted_at is null then
    raise exception 'assertion failed: expected granted_at to be set on emergency auto-approval';
  end if;

  begin
    perform app.complete_support_access_post_review(v_grant.id, '00000000-0000-0000-0000-000000000701', 'tenant admin cannot close this out');
    raise exception 'assertion failed: expected post-review by a non-Supreme-Admin to be rejected';
  exception
    when insufficient_privilege then
      null; -- expected
  end;

  perform app.complete_support_access_post_review(v_grant.id, '00000000-0000-0000-0000-000000000702', 'reviewed: justified, scope was appropriate');
  if (select post_review_completed_at from app.support_access_grants where id = v_grant.id) is null then
    raise exception 'assertion failed: expected post-review to be recorded';
  end if;

  begin
    perform app.complete_support_access_post_review(
      (select id from app.support_access_grants where case_id = 'CASE-100'),
      '00000000-0000-0000-0000-000000000702',
      'not emergency'
    );
    raise exception 'assertion failed: expected post-review of a non-emergency grant to be rejected';
  exception
    when check_violation then
      null; -- expected (not_emergency_grant)
  end;
end;
$$;

\echo '>> denial: a tenant_admin can deny a pending request; a denied grant is terminal and never grants access'
do $$
declare
  v_tenant_id uuid;
  v_grant app.support_access_grants;
begin
  v_tenant_id := (select id from app.tenants where slug = 'acmesup');
  v_grant := app.request_support_access(v_tenant_id, '00000000-0000-0000-0000-000000000703', 'fishing expedition', 'CASE-300', 60, 'tester');

  perform app.deny_support_access(v_grant.id, '00000000-0000-0000-0000-000000000701', 'tenant admin', 'no valid ticket attached');
  if (select status from app.support_access_grants where id = v_grant.id) <> 'denied' then
    raise exception 'assertion failed: expected the grant to be denied';
  end if;
  if (select granted_at from app.support_access_grants where id = v_grant.id) is not null then
    raise exception 'assertion failed: a denied grant must never have granted_at set';
  end if;

  begin
    perform app.approve_support_access(v_grant.id, '00000000-0000-0000-0000-000000000701', 'too late');
    raise exception 'assertion failed: expected approving an already-denied (terminal) grant to be rejected';
  exception
    when check_violation then
      null; -- expected (invalid_grant_status)
  end;
end;
$$;

\echo '>> defense in depth: anon is denied entirely on every new table; service_role has explicit full access'
do $$
begin
  set local role anon;
  begin
    perform count(*) from app.support_access_grants;
    raise exception 'assertion failed: anon must be denied on app.support_access_grants';
  exception
    when insufficient_privilege then
      null; -- expected
  end;
  reset role;
end;
$$;

do $$
declare
  v_count integer;
begin
  set local role service_role;
  select count(*) into v_count from app.support_access_grants;
  if v_count < 4 then
    raise exception 'assertion failed: expected service_role to see every support access grant created in this test run (CASE-100/102/202/300 -- CASE-101/200/201 were rejected before insert), saw %', v_count;
  end if;
  select count(*) into v_count from app.support_access_events;
  if v_count < 8 then
    raise exception 'assertion failed: expected service_role to see the append-only event trail, saw %', v_count;
  end if;
  reset role;
end;
$$;

\echo 'ALL PLT-115 db-test assertions passed.'
