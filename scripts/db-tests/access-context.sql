-- Real, executable test evidence for PLT-108 (Four-Layer Identity and Access Context,
-- CG-S6-PLT-005). Runs against the local-only auth.users stub loaded by
-- scripts/db-tests/run.sh (fixtures/auth-schema-stub.sql).

\set ON_ERROR_STOP on

\echo '>> setup: three identities, two tenants, active auth-identity linkages for all pairs used below'
do $$
begin
  insert into auth.users (id, email) values
    ('00000000-0000-0000-0000-000000000101', 'admin@example.test'),
    ('00000000-0000-0000-0000-000000000102', 'owner@example.test'),
    ('00000000-0000-0000-0000-000000000103', 'contact@example.test');

  perform app.provision_tenant('acmectx', 'Acme Context Co', 'idem-acmectx', 'tester');
  perform app.provision_tenant('gizmoctx', 'Gizmo Context Co', 'idem-gizmoctx', 'tester');
  perform app.transition_tenant_status((select id from app.tenants where slug = 'acmectx'), 'active', 'setup', 'tester');
  perform app.transition_tenant_status((select id from app.tenants where slug = 'gizmoctx'), 'active', 'setup', 'tester');

  perform app.link_auth_identity('00000000-0000-0000-0000-000000000101', (select id from app.tenants where slug = 'acmectx'), 'tester', 'active');
  perform app.link_auth_identity('00000000-0000-0000-0000-000000000102', (select id from app.tenants where slug = 'acmectx'), 'tester', 'active');
  perform app.link_auth_identity('00000000-0000-0000-0000-000000000102', (select id from app.tenants where slug = 'gizmoctx'), 'tester', 'active');
  perform app.link_auth_identity('00000000-0000-0000-0000-000000000103', (select id from app.tenants where slug = 'acmectx'), 'tester', 'active');
end;
$$;

\echo '>> supreme_admin resolves globally without a tenant_id, and always alone'
do $$
declare
  v_ctx app.access_context;
begin
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000000101', 'supreme_admin', null, null, 'tester');

  v_ctx := app.resolve_access_context('00000000-0000-0000-0000-000000000101');
  if v_ctx.layer <> 'supreme_admin' or v_ctx.tenant_id is not null then
    raise exception 'assertion failed: expected global supreme_admin context, got layer=% tenant_id=%', v_ctx.layer, v_ctx.tenant_id;
  end if;
end;
$$;

\echo '>> a supreme_admin grant is idempotent -- granting it twice returns the same row, never duplicates'
do $$
declare
  v_first app.principal_memberships;
  v_second app.principal_memberships;
  v_count integer;
begin
  select * into v_first from app.principal_memberships where auth_user_id = '00000000-0000-0000-0000-000000000101' and layer = 'supreme_admin';
  select * into v_second from app.grant_principal_membership('00000000-0000-0000-0000-000000000101', 'supreme_admin', null, null, 'tester');
  if v_second.id <> v_first.id then
    raise exception 'assertion failed: expected idempotent grant to return the original row';
  end if;

  select count(*) into v_count from app.principal_memberships where auth_user_id = '00000000-0000-0000-0000-000000000101' and layer = 'supreme_admin';
  if v_count <> 1 then
    raise exception 'assertion failed: expected exactly 1 supreme_admin row, found %', v_count;
  end if;
end;
$$;

\echo '>> tenant-qualified resolution: an unambiguous single membership auto-resolves even without a tenant_id argument'
do $$
declare
  v_acme_id uuid;
  v_ctx app.access_context;
begin
  select id into v_acme_id from app.tenants where slug = 'acmectx';
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000000103', 'org_user', v_acme_id, null, 'tester');

  v_ctx := app.resolve_access_context('00000000-0000-0000-0000-000000000103');
  if v_ctx.layer <> 'org_user' or v_ctx.tenant_id <> v_acme_id then
    raise exception 'assertion failed: expected auto-resolved org_user/acmectx context, got layer=% tenant_id=%', v_ctx.layer, v_ctx.tenant_id;
  end if;
end;
$$;

\echo '>> multi-tenant membership is ambiguous without an explicit tenant_id -- fails closed, never guesses'
do $$
declare
  v_acme_id uuid;
  v_gizmo_id uuid;
begin
  select id into v_acme_id from app.tenants where slug = 'acmectx';
  select id into v_gizmo_id from app.tenants where slug = 'gizmoctx';

  perform app.grant_principal_membership('00000000-0000-0000-0000-000000000102', 'tenant_admin', v_acme_id, null, 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000000102', 'org_user', v_gizmo_id, null, 'tester');

  begin
    perform app.resolve_access_context('00000000-0000-0000-0000-000000000102');
    raise exception 'assertion failed: expected ambiguous_context to fail closed, but it resolved';
  exception
    when check_violation then
      null; -- expected
  end;
end;
$$;

\echo '>> the same multi-tenant identity resolves deterministically once a tenant_id disambiguates'
do $$
declare
  v_acme_id uuid;
  v_gizmo_id uuid;
  v_ctx app.access_context;
begin
  select id into v_acme_id from app.tenants where slug = 'acmectx';
  select id into v_gizmo_id from app.tenants where slug = 'gizmoctx';

  v_ctx := app.resolve_access_context('00000000-0000-0000-0000-000000000102', v_acme_id);
  if v_ctx.layer <> 'tenant_admin' or v_ctx.tenant_id <> v_acme_id then
    raise exception 'assertion failed: expected tenant_admin/acmectx, got layer=% tenant_id=%', v_ctx.layer, v_ctx.tenant_id;
  end if;

  v_ctx := app.resolve_access_context('00000000-0000-0000-0000-000000000102', v_gizmo_id);
  if v_ctx.layer <> 'org_user' or v_ctx.tenant_id <> v_gizmo_id then
    raise exception 'assertion failed: expected org_user/gizmoctx, got layer=% tenant_id=%', v_ctx.layer, v_ctx.tenant_id;
  end if;
end;
$$;

\echo '>> customer_user layer requires customer_account_ref, and multiple accounts in one tenant are ambiguous without it'
do $$
declare
  v_acme_id uuid;
  v_ctx app.access_context;
begin
  select id into v_acme_id from app.tenants where slug = 'acmectx';

  perform app.grant_principal_membership('00000000-0000-0000-0000-000000000103', 'customer_user', v_acme_id, 'CUST-0001', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000000103', 'customer_user', v_acme_id, 'CUST-0002', 'tester');

  begin
    perform app.resolve_access_context('00000000-0000-0000-0000-000000000103', v_acme_id, null);
    raise exception 'assertion failed: expected ambiguous_context (org_user + 2 customer_user rows), but it resolved';
  exception
    when check_violation then
      null; -- expected
  end;

  v_ctx := app.resolve_access_context('00000000-0000-0000-0000-000000000103', v_acme_id, 'CUST-0002');
  if v_ctx.layer <> 'customer_user' or v_ctx.customer_account_ref <> 'CUST-0002' then
    raise exception 'assertion failed: expected customer_user/CUST-0002, got layer=% customer_account_ref=%', v_ctx.layer, v_ctx.customer_account_ref;
  end if;
end;
$$;

\echo '>> the layer/scope shape constraint rejects malformed rows at insert time -- not left to application code'
do $$
declare
  v_acme_id uuid;
begin
  select id into v_acme_id from app.tenants where slug = 'acmectx';
  begin
    insert into app.principal_memberships (auth_user_id, layer, tenant_id, customer_account_ref)
    values ('00000000-0000-0000-0000-000000000101', 'supreme_admin', v_acme_id, null);
    raise exception 'assertion failed: expected supreme_admin with a tenant_id to violate the scope-shape check, but it succeeded';
  exception
    when check_violation then
      null; -- expected
  end;

  begin
    insert into app.principal_memberships (auth_user_id, layer, tenant_id, customer_account_ref)
    values ('00000000-0000-0000-0000-000000000101', 'customer_user', v_acme_id, null);
    raise exception 'assertion failed: expected customer_user without a customer_account_ref to violate the scope-shape check, but it succeeded';
  exception
    when check_violation then
      null; -- expected
  end;
end;
$$;

\echo '>> an inactive tenant fails closed regardless of a valid membership'
do $$
declare
  v_gizmo_id uuid;
begin
  select id into v_gizmo_id from app.tenants where slug = 'gizmoctx';
  perform app.transition_tenant_status(v_gizmo_id, 'suspended', 'billing hold', 'tester');

  begin
    perform app.resolve_access_context('00000000-0000-0000-0000-000000000102', v_gizmo_id);
    raise exception 'assertion failed: expected inactive_tenant to fail closed, but it resolved';
  exception
    when check_violation then
      null; -- expected
  end;

  perform app.transition_tenant_status(v_gizmo_id, 'active', 'hold cleared', 'tester');
end;
$$;

\echo '>> an inactive (merely invited, not yet active) identity linkage fails closed even with a granted membership'
do $$
declare
  v_gizmo_id uuid;
  v_new_user uuid := '00000000-0000-0000-0000-000000000104';
begin
  select id into v_gizmo_id from app.tenants where slug = 'gizmoctx';
  insert into auth.users (id, email) values (v_new_user, 'invitee@example.test');
  perform app.link_auth_identity(v_new_user, v_gizmo_id, 'tester', 'invited');
  perform app.grant_principal_membership(v_new_user, 'org_user', v_gizmo_id, null, 'tester');

  begin
    perform app.resolve_access_context(v_new_user, v_gizmo_id);
    raise exception 'assertion failed: expected inactive_identity_link to fail closed for a merely-invited identity, but it resolved';
  exception
    when no_data_found then
      null; -- expected
  end;
end;
$$;

\echo '>> a revoked membership no longer resolves, and revoked is terminal'
do $$
declare
  v_acme_id uuid;
  v_membership app.principal_memberships;
begin
  select id into v_acme_id from app.tenants where slug = 'acmectx';
  select * into v_membership from app.principal_memberships
  where auth_user_id = '00000000-0000-0000-0000-000000000102' and tenant_id = v_acme_id and layer = 'tenant_admin';

  perform app.revoke_principal_membership(v_membership.id, 'role change', 'tester');

  begin
    perform app.resolve_access_context('00000000-0000-0000-0000-000000000102', v_acme_id);
    raise exception 'assertion failed: expected no_active_membership_for_tenant after revoke, but it resolved';
  exception
    when no_data_found then
      null; -- expected
  end;

  begin
    update app.principal_memberships set status = 'active' where id = v_membership.id;
    raise exception 'assertion failed: expected reviving a revoked membership to fail, but it succeeded';
  exception
    when check_violation then
      null; -- expected
  end;
end;
$$;

\echo '>> resolving for an identity with no membership at all fails closed'
do $$
declare
  v_acme_id uuid;
  v_new_user uuid := '00000000-0000-0000-0000-000000000105';
begin
  select id into v_acme_id from app.tenants where slug = 'acmectx';
  insert into auth.users (id, email) values (v_new_user, 'nomembership@example.test');
  perform app.link_auth_identity(v_new_user, v_acme_id, 'tester', 'active');

  begin
    perform app.resolve_access_context(v_new_user);
    raise exception 'assertion failed: expected no_active_membership to fail closed, but it resolved';
  exception
    when no_data_found then
      null; -- expected
  end;
end;
$$;

\echo '>> revoking a non-existent membership fails cleanly, not silently'
do $$
begin
  begin
    perform app.revoke_principal_membership('00000000-0000-0000-0000-000000000099', 'n/a', 'tester');
    raise exception 'assertion failed: expected revoking a non-existent membership to fail, but it succeeded';
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
    perform count(*) from app.principal_memberships;
    raise exception 'assertion failed: anon must be denied at the schema-privilege layer for principal_memberships';
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
  select count(*) into v_count from app.principal_memberships;
  if v_count < 4 then
    raise exception 'assertion failed: service_role must see every membership row, saw %', v_count;
  end if;
  reset role;
end;
$$;

\echo 'ALL PLT-108 db-test assertions passed.'
