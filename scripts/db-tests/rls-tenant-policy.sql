-- Real, executable test evidence for PLT-113 (RLS Tenant Policy Foundation,
-- CG-S6-PLT-010). Simulates a real authenticated PostgREST/Supabase session by setting
-- `request.jwt.claims` and switching to the `authenticated` role -- the same mechanism a
-- real Supabase deployment uses (see fixtures/auth-schema-stub.sql's auth.uid()/auth.role()).

\set ON_ERROR_STOP on

\echo '>> setup: two tenants, a member of each, and a global Supreme Admin'
do $$
declare
  v_tenant_a uuid;
  v_tenant_b uuid;
begin
  insert into auth.users (id, email) values
    ('00000000-0000-0000-0000-000000000501', 'membera@example.test'),
    ('00000000-0000-0000-0000-000000000502', 'memberb@example.test'),
    ('00000000-0000-0000-0000-000000000503', 'supremerls@example.test'),
    ('00000000-0000-0000-0000-000000000504', 'nomember@example.test');

  perform app.provision_tenant('acmerls', 'Acme RLS Co', 'idem-acmerls', 'tester');
  perform app.provision_tenant('gizmorls', 'Gizmo RLS Co', 'idem-gizmorls', 'tester');
  v_tenant_a := (select id from app.tenants where slug = 'acmerls');
  v_tenant_b := (select id from app.tenants where slug = 'gizmorls');
  perform app.transition_tenant_status(v_tenant_a, 'active', 'setup', 'tester');
  perform app.transition_tenant_status(v_tenant_b, 'active', 'setup', 'tester');

  perform app.invite_user(v_tenant_a, '00000000-0000-0000-0000-000000000501', 'membera@example.test', 'Member A', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'membera@example.test'), 'active', 'onboarded', 'tester');
  perform app.invite_user(v_tenant_b, '00000000-0000-0000-0000-000000000502', 'memberb@example.test', 'Member B', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'memberb@example.test'), 'active', 'onboarded', 'tester');

  perform app.grant_principal_membership('00000000-0000-0000-0000-000000000503', 'supreme_admin', null, null, 'tester');

  perform app.create_org_unit(v_tenant_a, 'company', null, 'ACMERLS-CO', 'Acme RLS Co', 'tester');
  perform app.create_org_unit(v_tenant_b, 'company', null, 'GIZMORLS-CO', 'Gizmo RLS Co', 'tester');
end;
$$;

\echo '>> tenant A''s member sees only tenant A''s row via app.tenants RLS, never tenant B''s'
do $$
declare
  v_count integer;
  v_slug text;
begin
  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000000501", "role": "authenticated"}';

  select count(*) into v_count from app.tenants;
  if v_count <> 1 then
    raise exception 'assertion failed: expected member A to see exactly 1 tenant via RLS, saw %', v_count;
  end if;

  select slug into v_slug from app.tenants limit 1;
  if v_slug <> 'acmerls' then
    raise exception 'assertion failed: expected the visible tenant to be acmerls, got %', v_slug;
  end if;

  reset role;
end;
$$;

\echo '>> tenant A''s member sees only tenant A''s org units, users, and roles -- never tenant B''s'
do $$
declare
  v_org_count integer;
  v_user_count integer;
begin
  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000000501", "role": "authenticated"}';

  select count(*) into v_org_count from app.org_units;
  if v_org_count <> 1 then
    raise exception 'assertion failed: expected member A to see exactly 1 org unit (their own tenant''s), saw %', v_org_count;
  end if;

  select count(*) into v_user_count from app.users;
  if v_user_count <> 1 then
    raise exception 'assertion failed: expected member A to see exactly 1 user (themselves), saw %', v_user_count;
  end if;

  reset role;
end;
$$;

\echo '>> tenant A''s member sees tenant A''s role/role_version/role_assignment rows, not tenant B''s'
do $$
declare
  v_tenant_a uuid;
  v_tenant_b uuid;
  v_role_a uuid;
  v_role_b uuid;
  v_draft_a app.role_versions;
  v_draft_b app.role_versions;
  v_permission_id uuid;
  v_role_count integer;
  v_version_count integer;
begin
  v_tenant_a := (select id from app.tenants where slug = 'acmerls');
  v_tenant_b := (select id from app.tenants where slug = 'gizmorls');
  select id into v_permission_id from app.permissions where resource_module_code = 'TKT' and action = 'View';

  select id into v_role_a from app.create_role(v_tenant_a, 'RLS Ticket Viewer A', null, 'tester');
  select * into v_draft_a from app.create_role_version(v_role_a, 'tester');
  perform app.set_role_version_permissions(v_draft_a.id, array[v_permission_id], 'tester');
  perform app.publish_role_version(v_draft_a.id, now(), 'tester');
  perform app.assign_role(v_tenant_a, (select id from app.role_versions where role_id = v_role_a and status = 'published'), '00000000-0000-0000-0000-000000000501', '00000000-0000-0000-0000-000000000501', 'tester');

  select id into v_role_b from app.create_role(v_tenant_b, 'RLS Ticket Viewer B', null, 'tester');
  select * into v_draft_b from app.create_role_version(v_role_b, 'tester');
  perform app.set_role_version_permissions(v_draft_b.id, array[v_permission_id], 'tester');
  perform app.publish_role_version(v_draft_b.id, now(), 'tester');
  perform app.assign_role(v_tenant_b, (select id from app.role_versions where role_id = v_role_b and status = 'published'), '00000000-0000-0000-0000-000000000502', '00000000-0000-0000-0000-000000000502', 'tester');

  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000000501", "role": "authenticated"}';

  select count(*) into v_role_count from app.roles where name in ('RLS Ticket Viewer A', 'RLS Ticket Viewer B');
  if v_role_count <> 1 then
    raise exception 'assertion failed: expected member A to see exactly 1 of the two roles (their own tenant''s), saw %', v_role_count;
  end if;

  select count(*) into v_version_count from app.role_versions rv join app.roles r on r.id = rv.role_id where r.name in ('RLS Ticket Viewer A', 'RLS Ticket Viewer B');
  if v_version_count <> 1 then
    raise exception 'assertion failed: expected member A to see exactly 1 role_version (via the role_id join to their own tenant), saw %', v_version_count;
  end if;

  reset role;
end;
$$;

\echo '>> a Supreme Admin sees rows across every tenant, not just one'
do $$
declare
  v_tenant_count integer;
  v_org_count integer;
begin
  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000000503", "role": "authenticated"}';

  select count(*) into v_tenant_count from app.tenants;
  if v_tenant_count < 2 then
    raise exception 'assertion failed: expected the Supreme Admin to see at least 2 tenants across the whole platform, saw %', v_tenant_count;
  end if;

  select count(*) into v_org_count from app.org_units;
  if v_org_count < 2 then
    raise exception 'assertion failed: expected the Supreme Admin to see org units from more than one tenant, saw %', v_org_count;
  end if;

  reset role;
end;
$$;

\echo '>> the Supreme Admin''s own global principal_memberships row is visible to itself, but not to an ordinary member'
do $$
declare
  v_visible_to_self integer;
  v_visible_to_other integer;
begin
  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000000503", "role": "authenticated"}';
  select count(*) into v_visible_to_self from app.principal_memberships where auth_user_id = '00000000-0000-0000-0000-000000000503' and layer = 'supreme_admin';
  reset role;
  if v_visible_to_self <> 1 then
    raise exception 'assertion failed: expected the Supreme Admin to see their own global membership row, saw %', v_visible_to_self;
  end if;

  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000000501", "role": "authenticated"}';
  select count(*) into v_visible_to_other from app.principal_memberships where auth_user_id = '00000000-0000-0000-0000-000000000503' and layer = 'supreme_admin';
  reset role;
  if v_visible_to_other <> 0 then
    raise exception 'assertion failed: an ordinary tenant member must never see another identity''s global supreme_admin row (would leak who is a platform Supreme Admin), saw %', v_visible_to_other;
  end if;
end;
$$;

\echo '>> an identity with zero tenant memberships anywhere sees zero rows across every RLS-governed table'
do $$
declare
  v_tenant_count integer;
  v_org_count integer;
  v_user_count integer;
begin
  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000000504", "role": "authenticated"}';

  select count(*) into v_tenant_count from app.tenants;
  select count(*) into v_org_count from app.org_units;
  select count(*) into v_user_count from app.users;
  if v_tenant_count <> 0 or v_org_count <> 0 or v_user_count <> 0 then
    raise exception 'assertion failed: expected zero visible rows everywhere for a never-invited identity, saw tenants=% org_units=% users=%', v_tenant_count, v_org_count, v_user_count;
  end if;

  reset role;
end;
$$;

\echo '>> authenticated has no write grant anywhere -- every INSERT/UPDATE/DELETE remains RPC-only, mediated by service_role'
do $$
begin
  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000000501", "role": "authenticated"}';
  begin
    insert into app.tenants (slug, name, idempotency_key, requested_by) values ('rls-bypass-attempt', 'Bypass Attempt', 'idem-bypass', 'attacker');
    raise exception 'assertion failed: authenticated must never be able to INSERT directly into app.tenants, but it succeeded';
  exception
    when insufficient_privilege then
      null; -- expected -- no INSERT grant exists for authenticated on any table in this migration
  end;
  reset role;
end;
$$;

\echo '>> anon remains fully denied at the schema-privilege layer -- PLT-113 only ever widened authenticated, never anon'
do $$
begin
  set local role anon;
  begin
    perform count(*) from app.tenants;
    raise exception 'assertion failed: anon must still be denied at the schema-privilege layer for app.tenants after PLT-113';
  exception
    when insufficient_privilege then
      null; -- expected
  end;
  reset role;
end;
$$;

\echo '>> service_role is unaffected -- still sees every row across every tenant, bypassing RLS as before'
do $$
declare
  v_count integer;
begin
  set local role service_role;
  select count(*) into v_count from app.tenants;
  if v_count < 2 then
    raise exception 'assertion failed: service_role must still see every tenant row regardless of RLS, saw %', v_count;
  end if;
  reset role;
end;
$$;

\echo 'ALL PLT-113 db-test assertions passed.'
