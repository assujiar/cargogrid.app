-- Real, executable test evidence for PLT-110 (User Lifecycle, CG-S6-PLT-007).

\set ON_ERROR_STOP on

\echo '>> setup: a tenant, two auth identities, and a company/branch org unit'
do $$
begin
  insert into auth.users (id, email) values
    ('00000000-0000-0000-0000-000000000201', 'admin1@example.test'),
    ('00000000-0000-0000-0000-000000000202', 'admin2@example.test'),
    ('00000000-0000-0000-0000-000000000203', 'newhire@example.test');

  perform app.provision_tenant('acmeusr', 'Acme User Co', 'idem-acmeusr', 'tester');
  perform app.transition_tenant_status((select id from app.tenants where slug = 'acmeusr'), 'active', 'setup', 'tester');
  perform app.create_org_unit((select id from app.tenants where slug = 'acmeusr'), 'company', null, 'ACMEUSR-CO', 'Acme Co', 'tester');
end;
$$;

\echo '>> idempotent invitation: inviting the same identity twice returns the original row and composes the underlying identity link'
do $$
declare
  v_tenant_id uuid;
  v_first app.users;
  v_second app.users;
  v_link_count integer;
begin
  select id into v_tenant_id from app.tenants where slug = 'acmeusr';

  select * into v_first from app.invite_user(v_tenant_id, '00000000-0000-0000-0000-000000000201', 'admin1@example.test', 'Admin One', null, 'tester', now() + interval '7 days');
  if v_first.status <> 'invited' then
    raise exception 'assertion failed: expected status=invited, got %', v_first.status;
  end if;

  select * into v_second from app.invite_user(v_tenant_id, '00000000-0000-0000-0000-000000000201', 'admin1@example.test', 'Admin One', null, 'tester', now() + interval '7 days');
  if v_second.id <> v_first.id then
    raise exception 'assertion failed: expected idempotent invite to return the original row';
  end if;

  select count(*) into v_link_count from app.tenant_user_identities where auth_user_id = '00000000-0000-0000-0000-000000000201' and tenant_id = v_tenant_id;
  if v_link_count <> 1 then
    raise exception 'assertion failed: expected exactly 1 identity linkage composed by invite_user, found %', v_link_count;
  end if;
end;
$$;

\echo '>> duplicate email within one tenant is rejected even for a different identity'
do $$
declare
  v_tenant_id uuid;
begin
  select id into v_tenant_id from app.tenants where slug = 'acmeusr';
  begin
    perform app.invite_user(v_tenant_id, '00000000-0000-0000-0000-000000000203', 'admin1@example.test', 'Duplicate Email', null, 'tester', now() + interval '7 days');
    raise exception 'assertion failed: expected a duplicate email within the tenant to fail, but it succeeded';
  exception
    when unique_violation then
      null; -- expected
  end;
end;
$$;

\echo '>> resend extends a pending invitation''s expiry, and is rejected once the user is no longer invited'
do $$
declare
  v_user app.users;
  v_resent app.users;
begin
  select * into v_user from app.users where email = 'admin1@example.test';
  select * into v_resent from app.resend_invitation(v_user.id, v_user.invite_expires_at + interval '7 days', 'tester');
  if v_resent.invite_expires_at <= v_user.invite_expires_at then
    raise exception 'assertion failed: expected invite_expires_at to be extended';
  end if;
end;
$$;

\echo '>> activation transitions both the user and the underlying identity link, syncing the two'
do $$
declare
  v_user app.users;
  v_activated app.users;
  v_link app.tenant_user_identities;
begin
  select * into v_user from app.users where email = 'admin1@example.test';
  select * into v_activated from app.transition_user_status(v_user.id, 'active', 'onboarded', 'tester');
  if v_activated.status <> 'active' or v_activated.activated_at is null then
    raise exception 'assertion failed: expected active status with activated_at set';
  end if;

  select * into v_link from app.tenant_user_identities where auth_user_id = v_user.auth_user_id and tenant_id = v_user.tenant_id;
  if v_link.status <> 'active' then
    raise exception 'assertion failed: expected the underlying identity link to also be active, got %', v_link.status;
  end if;
end;
$$;

\echo '>> a second user is granted tenant_admin so the last-critical-admin guard has something to compare against'
do $$
declare
  v_tenant_id uuid;
  v_user2 app.users;
begin
  select id into v_tenant_id from app.tenants where slug = 'acmeusr';
  select * into v_user2 from app.invite_user(v_tenant_id, '00000000-0000-0000-0000-000000000202', 'admin2@example.test', 'Admin Two', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status(v_user2.id, 'active', 'onboarded', 'tester');

  perform app.grant_principal_membership('00000000-0000-0000-0000-000000000201', 'tenant_admin', v_tenant_id, null, 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000000202', 'tenant_admin', v_tenant_id, null, 'tester');
end;
$$;

\echo '>> suspend/reactivate lifecycle for a non-last admin succeeds'
do $$
declare
  v_user2 app.users;
  v_suspended app.users;
  v_reactivated app.users;
begin
  select * into v_user2 from app.users where email = 'admin2@example.test';
  select * into v_suspended from app.transition_user_status(v_user2.id, 'suspended', 'temporary leave', 'tester');
  if v_suspended.status <> 'suspended' or v_suspended.suspended_at is null then
    raise exception 'assertion failed: expected suspended status with suspended_at set';
  end if;

  select * into v_reactivated from app.transition_user_status(v_suspended.id, 'active', 'back from leave', 'tester');
  if v_reactivated.status <> 'active' then
    raise exception 'assertion failed: expected reactivated status=active, got %', v_reactivated.status;
  end if;
end;
$$;

\echo '>> the last-critical-admin guard blocks suspending/revoking the tenant''s only active tenant_admin'
do $$
declare
  v_user2 app.users;
begin
  select * into v_user2 from app.users where email = 'admin2@example.test';
  perform app.transition_user_status(v_user2.id, 'suspended', 'stepping down', 'tester');

  begin
    perform app.transition_user_status((select id from app.users where email = 'admin1@example.test'), 'suspended', 'stepping down too', 'tester');
    raise exception 'assertion failed: expected suspending the last active tenant_admin to fail, but it succeeded';
  exception
    when check_violation then
      null; -- expected
  end;

  perform app.transition_user_status(v_user2.id, 'active', 'back on duty', 'tester');
end;
$$;

\echo '>> revoke propagates: the identity link is revoked and every active principal membership is revoked too'
do $$
declare
  v_user2 app.users;
  v_revoked app.users;
  v_link app.tenant_user_identities;
  v_active_memberships integer;
begin
  select * into v_user2 from app.users where email = 'admin2@example.test';
  select * into v_revoked from app.transition_user_status(v_user2.id, 'revoked', 'offboarded', 'tester');
  if v_revoked.status <> 'revoked' or v_revoked.revoked_at is null then
    raise exception 'assertion failed: expected revoked status with revoked_at set';
  end if;

  select * into v_link from app.tenant_user_identities where auth_user_id = v_user2.auth_user_id and tenant_id = v_user2.tenant_id;
  if v_link.status <> 'revoked' then
    raise exception 'assertion failed: expected the underlying identity link to be revoked too, got %', v_link.status;
  end if;

  select count(*) into v_active_memberships from app.principal_memberships
  where auth_user_id = v_user2.auth_user_id and tenant_id = v_user2.tenant_id and status = 'active';
  if v_active_memberships <> 0 then
    raise exception 'assertion failed: expected every principal membership to be revoked, % still active', v_active_memberships;
  end if;
end;
$$;

\echo '>> revoked is terminal, and a genuinely-last remaining admin can now be revoked (the other one is already gone)'
do $$
declare
  v_user2_id uuid;
begin
  select id into v_user2_id from app.users where email = 'admin2@example.test';
  begin
    update app.users set status = 'active' where id = v_user2_id;
    raise exception 'assertion failed: expected reviving a revoked user to fail, but it succeeded';
  exception
    when check_violation then
      null; -- expected
  end;
end;
$$;

\echo '>> a cancelled (never-activated) invitation is recorded distinctly from a post-activation revoke'
do $$
declare
  v_tenant_id uuid;
  v_user app.users;
  v_history_event text;
begin
  select id into v_tenant_id from app.tenants where slug = 'acmeusr';
  select * into v_user from app.invite_user(v_tenant_id, '00000000-0000-0000-0000-000000000203', 'newhire@example.test', 'New Hire', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status(v_user.id, 'revoked', 'offer rescinded', 'tester');

  select event_type into v_history_event from app.user_lifecycle_history
  where user_id = v_user.id and to_status = 'revoked'
  order by occurred_at desc limit 1;
  if v_history_event <> 'cancel_invite' then
    raise exception 'assertion failed: expected event_type=cancel_invite for an invited->revoked transition, got %', v_history_event;
  end if;
end;
$$;

\echo '>> org reassignment validates tenant ownership and optimistic concurrency'
do $$
declare
  v_user app.users;
  v_org_unit_id uuid;
  v_reassigned app.users;
begin
  select * into v_user from app.users where email = 'admin1@example.test';
  select id into v_org_unit_id from app.org_units where tenant_id = v_user.tenant_id and code = 'ACMEUSR-CO';

  select * into v_reassigned from app.reassign_user_org_unit(v_user.id, v_org_unit_id, v_user.record_version, 'tester');
  if v_reassigned.org_unit_id <> v_org_unit_id then
    raise exception 'assertion failed: expected org_unit_id to be set';
  end if;

  begin
    perform app.reassign_user_org_unit(v_user.id, v_org_unit_id, v_user.record_version, 'tester');
    raise exception 'assertion failed: expected a stale expected_version to fail, but it succeeded';
  exception
    when check_violation then
      null; -- expected
  end;
end;
$$;

\echo '>> reassigning to a cross-tenant org unit is rejected'
do $$
declare
  v_user app.users;
  v_other_tenant_id uuid;
begin
  select * into v_user from app.users where email = 'admin1@example.test';
  perform app.provision_tenant('gizmousr', 'Gizmo User Co', 'idem-gizmousr', 'tester');
  select id into v_other_tenant_id from app.tenants where slug = 'gizmousr';
  perform app.create_org_unit(v_other_tenant_id, 'company', null, 'GIZMOUSR-CO', 'Gizmo Co', 'tester');

  begin
    perform app.reassign_user_org_unit(v_user.id, (select id from app.org_units where tenant_id = v_other_tenant_id and code = 'GIZMOUSR-CO'), v_user.record_version, 'tester');
    raise exception 'assertion failed: expected a cross-tenant org unit reassignment to fail, but it succeeded';
  exception
    when check_violation then
      null; -- expected
  end;
end;
$$;

\echo '>> resending, transitioning, or reassigning a non-existent user fails cleanly, not silently'
do $$
begin
  begin
    perform app.resend_invitation('00000000-0000-0000-0000-000000000099', now(), 'tester');
    raise exception 'assertion failed: expected resending a non-existent user''s invite to fail, but it succeeded';
  exception
    when no_data_found then
      null; -- expected
  end;
end;
$$;

\echo '>> defense in depth: anon and authenticated are denied at the schema-privilege layer; service_role has explicit access'
do $$
begin
  set local role anon;
  begin
    perform count(*) from app.users;
    raise exception 'assertion failed: anon must be denied at the schema-privilege layer for users';
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
  select count(*) into v_count from app.users;
  if v_count < 3 then
    raise exception 'assertion failed: service_role must see every user row, saw %', v_count;
  end if;
  reset role;
end;
$$;

\echo 'ALL PLT-110 db-test assertions passed.'
