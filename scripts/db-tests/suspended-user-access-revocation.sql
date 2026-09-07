-- CG-AUDIT-2026-09-02 D3b remediation. Real, executable evidence that suspending a user
-- through the governed RPC (app.transition_user_status) genuinely cuts their access --
-- reproducing the audit's own live probe exactly (§4 D3b): before this fix,
-- app.resolve_access_context still returned the suspended user's real layer,
-- app.has_active_tenant_membership still returned true, and an RLS-gated read under the
-- suspended user's own JWT still returned rows, because neither function read
-- app.users.status at all (they key off app.tenant_user_identities.status = 'active' alone,
-- which transition_user_status never touched on suspend -- only on revoke).
--
-- Asserts: (1) before suspend, access resolves normally; (2) after suspend,
-- resolve_access_context fails closed (inactive_identity_link), has_active_tenant_membership
-- returns false, and a real RLS-gated read under the suspended user's own simulated session
-- returns zero rows; (3) reactivating restores access exactly as before; (4) an identity
-- with NO app.users row at all (a customer_user-layer portal principal, which this table's
-- own HRIS-flavored lifecycle was never written for) is entirely unaffected -- the fix uses
-- NOT EXISTS, never a JOIN, specifically to preserve this.

\set ON_ERROR_STOP on

\echo '>> setup: a tenant with two active tenant_admins (transition_user_status refuses to suspend a tenant''s only remaining admin)'
do $$
declare
  v_tenant uuid;
begin
  insert into auth.users (id, email) values
    ('00000000-0000-0000-0000-000000098801', 'suspendme-d3b@example.test'),
    ('00000000-0000-0000-0000-000000098803', 'secondadmin-d3b@example.test');

  perform app.provision_tenant('d3bsuspend', 'D3B Suspend Co', 'idem-d3bsuspend', 'tester');
  v_tenant := (select id from app.tenants where slug = 'd3bsuspend');
  perform app.transition_tenant_status(v_tenant, 'active', 'setup', 'tester');

  perform app.invite_user(v_tenant, '00000000-0000-0000-0000-000000098801', 'suspendme-d3b@example.test', 'Suspend Me', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'suspendme-d3b@example.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000098801', 'tenant_admin', v_tenant, null, 'tester');

  perform app.invite_user(v_tenant, '00000000-0000-0000-0000-000000098803', 'secondadmin-d3b@example.test', 'Second Admin', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'secondadmin-d3b@example.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000098803', 'tenant_admin', v_tenant, null, 'tester');
end;
$$;

\echo '>> case 1: before suspend, resolve_access_context returns tenant_admin and has_active_tenant_membership is true'
do $$
declare
  v_tenant uuid;
  v_ctx app.access_context;
begin
  v_tenant := (select id from app.tenants where slug = 'd3bsuspend');
  v_ctx := app.resolve_access_context('00000000-0000-0000-0000-000000098801', v_tenant);
  if v_ctx.layer <> 'tenant_admin' then
    raise exception 'assertion failed: expected tenant_admin before suspend, got %', v_ctx.layer;
  end if;
  if not app.has_active_tenant_membership(v_tenant, '00000000-0000-0000-0000-000000098801') then
    raise exception 'assertion failed: expected has_active_tenant_membership true before suspend';
  end if;
end;
$$;

\echo '>> suspend the user via the governed RPC'
do $$
begin
  perform app.transition_user_status((select id from app.users where email = 'suspendme-d3b@example.test'), 'suspended', 'D3B regression', 'tester');
end;
$$;

\echo '>> case 2: after suspend, resolve_access_context fails closed, has_active_tenant_membership is false, and a real RLS-gated read under the suspended user''s own session returns zero rows'
do $$
declare
  v_tenant uuid;
  v_count integer;
begin
  v_tenant := (select id from app.tenants where slug = 'd3bsuspend');

  begin
    perform app.resolve_access_context('00000000-0000-0000-0000-000000098801', v_tenant);
    raise exception 'assertion failed: expected inactive_identity_link after suspend, resolve_access_context succeeded instead';
  exception
    when others then
      if sqlerrm not like 'inactive_identity_link%' then
        raise exception 'assertion failed: expected inactive_identity_link, got: %', sqlerrm;
      end if;
  end;

  if app.has_active_tenant_membership(v_tenant, '00000000-0000-0000-0000-000000098801') then
    raise exception 'assertion failed: expected has_active_tenant_membership false after suspend, still true';
  end if;

  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000098801", "role": "authenticated"}';
  select count(*) into v_count from app.tenants where id = v_tenant;
  reset role;
  if v_count <> 0 then
    raise exception 'assertion failed: expected zero RLS-visible rows for the suspended user, got %', v_count;
  end if;
end;
$$;

\echo '>> case 3: reactivating restores access exactly as before'
do $$
declare
  v_tenant uuid;
  v_ctx app.access_context;
begin
  v_tenant := (select id from app.tenants where slug = 'd3bsuspend');
  perform app.transition_user_status((select id from app.users where email = 'suspendme-d3b@example.test'), 'active', 'D3B regression reactivate', 'tester');

  v_ctx := app.resolve_access_context('00000000-0000-0000-0000-000000098801', v_tenant);
  if v_ctx.layer <> 'tenant_admin' then
    raise exception 'assertion failed: expected tenant_admin restored after reactivate, got %', v_ctx.layer;
  end if;
  if not app.has_active_tenant_membership(v_tenant, '00000000-0000-0000-0000-000000098801') then
    raise exception 'assertion failed: expected has_active_tenant_membership true after reactivate';
  end if;
end;
$$;

\echo '>> case 4: an identity with no app.users row at all (a customer_user-layer principal) is entirely unaffected -- NOT EXISTS, never a JOIN'
do $$
declare
  v_tenant uuid;
begin
  v_tenant := (select id from app.tenants where slug = 'd3bsuspend');
  insert into auth.users (id, email) values ('00000000-0000-0000-0000-000000098802', 'customer-d3b@example.test');
  perform app.invite_user(v_tenant, '00000000-0000-0000-0000-000000098802', 'customer-d3b@example.test', 'Customer D3B', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'customer-d3b@example.test'), 'active', 'onboarded', 'tester');
  -- Delete the app.users row entirely -- a customer_user-layer principal need not have one;
  -- tenant_user_identities is the only linkage such a principal genuinely needs.
  delete from app.users where email = 'customer-d3b@example.test';
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000098802', 'customer_user', v_tenant, 'CUST-D3B-01', 'tester');

  if not app.has_active_tenant_membership(v_tenant, '00000000-0000-0000-0000-000000098802') then
    raise exception 'assertion failed: expected has_active_tenant_membership true for an identity with no app.users row at all';
  end if;
end;
$$;

\echo 'ALL suspended-user-access-revocation db-test assertions passed.'
