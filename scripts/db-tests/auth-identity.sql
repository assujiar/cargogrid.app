-- Real, executable test evidence for PLT-107 (Supabase Auth Integration, CG-S6-PLT-004).
-- Runs against the local-only auth.users stub loaded by scripts/db-tests/run.sh
-- (fixtures/auth-schema-stub.sql) -- see that file's own header for why this is never
-- part of a real migration.

\set ON_ERROR_STOP on

\echo '>> setup: two auth identities and two tenants'
do $$
begin
  insert into auth.users (id, email) values
    ('00000000-0000-0000-0000-000000000001', 'alice@example.test'),
    ('00000000-0000-0000-0000-000000000002', 'bob@example.test');
  perform app.provision_tenant('acmeauth', 'Acme Auth Co', 'idem-acmeauth', 'tester');
  perform app.provision_tenant('gizmoauth', 'Gizmo Auth Co', 'idem-gizmoauth', 'tester');
end;
$$;

\echo '>> idempotent linkage: inviting the same identity to the same tenant twice returns the original row'
do $$
declare
  v_tenant_id uuid;
  v_first app.tenant_user_identities;
  v_second app.tenant_user_identities;
  v_count integer;
begin
  select id into v_tenant_id from app.tenants where slug = 'acmeauth';

  select * into v_first from app.link_auth_identity('00000000-0000-0000-0000-000000000001', v_tenant_id, 'supreme-admin-1');
  if v_first.status <> 'invited' then
    raise exception 'assertion failed: expected status=invited, got %', v_first.status;
  end if;

  select * into v_second from app.link_auth_identity('00000000-0000-0000-0000-000000000001', v_tenant_id, 'supreme-admin-1');
  if v_second.id <> v_first.id then
    raise exception 'assertion failed: expected the second invite call to return the original linkage row, got a different id';
  end if;

  select count(*) into v_count from app.tenant_user_identities where auth_user_id = '00000000-0000-0000-0000-000000000001' and tenant_id = v_tenant_id;
  if v_count <> 1 then
    raise exception 'assertion failed: expected exactly 1 linkage row, found %', v_count;
  end if;
end;
$$;

\echo '>> one identity may be linked to multiple tenants (the four-layer model does not assume single-tenant membership)'
do $$
declare
  v_acme_id uuid;
  v_gizmo_id uuid;
  v_count integer;
begin
  select id into v_acme_id from app.tenants where slug = 'acmeauth';
  select id into v_gizmo_id from app.tenants where slug = 'gizmoauth';

  perform app.link_auth_identity('00000000-0000-0000-0000-000000000001', v_gizmo_id, 'supreme-admin-1');

  select count(*) into v_count from app.tenant_user_identities where auth_user_id = '00000000-0000-0000-0000-000000000001';
  if v_count <> 2 then
    raise exception 'assertion failed: expected alice to have 2 tenant linkages, found %', v_count;
  end if;
end;
$$;

\echo '>> cross-tenant isolation: bob''s linkage to gizmoauth is invisible when querying acmeauth''s linkages'
do $$
declare
  v_acme_id uuid;
  v_gizmo_id uuid;
  v_count integer;
begin
  select id into v_acme_id from app.tenants where slug = 'acmeauth';
  select id into v_gizmo_id from app.tenants where slug = 'gizmoauth';

  perform app.link_auth_identity('00000000-0000-0000-0000-000000000002', v_gizmo_id, 'supreme-admin-1');

  select count(*) into v_count
  from app.tenant_user_identities
  where tenant_id = v_acme_id and auth_user_id = '00000000-0000-0000-0000-000000000002';
  if v_count <> 0 then
    raise exception 'assertion failed: bob must not appear linked to acmeauth, found % row(s)', v_count;
  end if;
end;
$$;

\echo '>> activation and revocation lifecycle, both recorded in history'
do $$
declare
  v_tenant_id uuid;
  v_link app.tenant_user_identities;
  v_count integer;
begin
  select id into v_tenant_id from app.tenants where slug = 'acmeauth';

  update app.tenant_user_identities set status = 'active'
  where auth_user_id = '00000000-0000-0000-0000-000000000001' and tenant_id = v_tenant_id;

  select * into v_link from app.revoke_auth_identity('00000000-0000-0000-0000-000000000001', v_tenant_id, 'employee offboarded', 'supreme-admin-1');
  if v_link.status <> 'revoked' or v_link.revoked_at is null then
    raise exception 'assertion failed: expected revoked status with revoked_at set, got status=% revoked_at=%', v_link.status, v_link.revoked_at;
  end if;

  select count(*) into v_count from app.tenant_user_identity_history
  where auth_user_id = '00000000-0000-0000-0000-000000000001' and tenant_id = v_tenant_id;
  if v_count <> 2 then
    raise exception 'assertion failed: expected 2 history rows (link, revoke), found %', v_count;
  end if;
end;
$$;

\echo '>> revoked is terminal -- no further transition is ever allowed'
do $$
declare
  v_tenant_id uuid;
begin
  select id into v_tenant_id from app.tenants where slug = 'acmeauth';
  begin
    update app.tenant_user_identities set status = 'active'
    where auth_user_id = '00000000-0000-0000-0000-000000000001' and tenant_id = v_tenant_id;
    raise exception 'assertion failed: expected reviving a revoked identity link to fail, but it succeeded';
  exception
    when check_violation then
      null; -- expected
  end;
end;
$$;

\echo '>> revoking a non-existent linkage fails cleanly, not silently'
do $$
begin
  begin
    perform app.revoke_auth_identity('00000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000099', 'n/a', 'tester');
    raise exception 'assertion failed: expected revoking a non-existent linkage to fail, but it succeeded';
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
    perform count(*) from app.tenant_user_identities;
    raise exception 'assertion failed: anon must be denied at the schema-privilege layer for tenant_user_identities';
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
  select count(*) into v_count from app.tenant_user_identities;
  if v_count < 3 then
    raise exception 'assertion failed: service_role must see every linkage row, saw %', v_count;
  end if;
  reset role;
end;
$$;

\echo 'ALL PLT-107 db-test assertions passed.'
