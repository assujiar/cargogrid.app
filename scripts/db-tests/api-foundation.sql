-- Real, executable test evidence for PLT-130 (REST and GraphQL Platform API
-- Foundation, CG-S6-PLT-027).

\set ON_ERROR_STOP on

\echo '>> setup: a tenant, a user, and an API key to reference from api_logs rows'
do $$
declare
  v_tenant_id uuid;
begin
  insert into auth.users (id, email) values
    ('00000000-0000-0000-0000-000000002201', 'apiuser@example.test'),
    ('00000000-0000-0000-0000-000000002202', 'apitenantadmin@example.test'),
    ('00000000-0000-0000-0000-000000002203', 'apisupreme@example.test');

  perform app.provision_tenant('acmeapi', 'Acme API Co', 'idem-acmeapi', 'tester');
  v_tenant_id := (select id from app.tenants where slug = 'acmeapi');
  perform app.transition_tenant_status(v_tenant_id, 'active', 'setup', 'tester');
  perform app.invite_user(v_tenant_id, '00000000-0000-0000-0000-000000002201', 'apiuser@example.test', 'API User', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'apiuser@example.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000002201', 'org_user', v_tenant_id, null, 'tester');

  perform app.invite_user(v_tenant_id, '00000000-0000-0000-0000-000000002202', 'apitenantadmin@example.test', 'API Tenant Admin', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'apitenantadmin@example.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000002202', 'tenant_admin', v_tenant_id, null, 'tester');

  perform app.grant_principal_membership('00000000-0000-0000-0000-000000002203', 'supreme_admin', null, null, 'tester');
end;
$$;

\echo '>> app.record_api_request: invalid actor_type/interface/result rejected; a real REST success row records correctly'
do $$
declare
  v_tenant_id uuid;
  v_log app.api_logs;
begin
  v_tenant_id := (select id from app.tenants where slug = 'acmeapi');

  begin
    perform app.record_api_request(gen_random_uuid(), v_tenant_id, '00000000-0000-0000-0000-000000002201', 'not-a-type', null, 'rest', 'GET /v1/tenants', 'GET', '/v1/tenants', null, 200, 'success', null, null, 42);
    raise exception 'assertion failed: expected api_log_invalid_actor_type';
  exception
    when check_violation then
      if sqlerrm !~ 'api_log_invalid_actor_type' then raise; end if;
  end;

  begin
    perform app.record_api_request(gen_random_uuid(), v_tenant_id, '00000000-0000-0000-0000-000000002201', 'user', null, 'soap', 'GET /v1/tenants', 'GET', '/v1/tenants', null, 200, 'success', null, null, 42);
    raise exception 'assertion failed: expected api_log_invalid_interface';
  exception
    when check_violation then
      if sqlerrm !~ 'api_log_invalid_interface' then raise; end if;
  end;

  begin
    perform app.record_api_request(gen_random_uuid(), v_tenant_id, '00000000-0000-0000-0000-000000002201', 'user', null, 'rest', 'GET /v1/tenants', 'GET', '/v1/tenants', null, 200, 'maybe', null, null, 42);
    raise exception 'assertion failed: expected api_log_invalid_result';
  exception
    when check_violation then
      if sqlerrm !~ 'api_log_invalid_result' then raise; end if;
  end;

  v_log := app.record_api_request(gen_random_uuid(), v_tenant_id, '00000000-0000-0000-0000-000000002201', 'user', null, 'rest', 'GET /v1/tenants', 'GET', '/v1/tenants', null, 200, 'success', null, null, 42);
  if v_log.interface <> 'rest' or v_log.status_code <> 200 or v_log.duration_ms <> 42 then
    raise exception 'assertion failed: unexpected recorded row %', v_log;
  end if;
end;
$$;

\echo '>> app.api_logs schema-level shape constraints: an api_key actor requires api_key_id; a user actor requires actor_auth_user_id; a rest row rejects graphql_operation_name; a graphql row rejects http_method/path'
do $$
declare
  v_tenant_id uuid;
  v_key record;
begin
  v_tenant_id := (select id from app.tenants where slug = 'acmeapi');
  select * into v_key from app.create_api_key(v_tenant_id, 'API foundation test key', '["HRS:View"]'::jsonb, null, null, '00000000-0000-0000-0000-000000002203', 'supreme admin');

  begin
    insert into app.api_logs (correlation_id, tenant_id, actor_type, api_key_id, interface, operation, result)
    values (gen_random_uuid(), v_tenant_id, 'api_key', null, 'rest', 'GET /v1/tenants', 'success');
    raise exception 'assertion failed: expected api_logs_actor_shape_check to reject an api_key actor with no api_key_id';
  exception
    when check_violation then
      null;
  end;

  begin
    insert into app.api_logs (correlation_id, tenant_id, actor_type, interface, operation, result)
    values (gen_random_uuid(), v_tenant_id, 'user', 'rest', 'GET /v1/tenants', 'success');
    raise exception 'assertion failed: expected api_logs_actor_shape_check to reject a user actor with no actor_auth_user_id';
  exception
    when check_violation then
      null;
  end;

  begin
    insert into app.api_logs (correlation_id, tenant_id, actor_type, api_key_id, interface, operation, graphql_operation_name, result)
    values (gen_random_uuid(), v_tenant_id, 'api_key', v_key.id, 'rest', 'GET /v1/tenants', 'resolveTenant', 'success');
    raise exception 'assertion failed: expected api_logs_interface_fields_check to reject a rest row carrying graphql_operation_name';
  exception
    when check_violation then
      null;
  end;

  begin
    insert into app.api_logs (correlation_id, tenant_id, actor_type, api_key_id, interface, operation, http_method, result)
    values (gen_random_uuid(), v_tenant_id, 'api_key', v_key.id, 'graphql', 'query resolveTenant', 'GET', 'success');
    raise exception 'assertion failed: expected api_logs_interface_fields_check to reject a graphql row carrying http_method';
  exception
    when check_violation then
      null;
  end;

  insert into app.api_logs (correlation_id, tenant_id, actor_type, api_key_id, interface, operation, graphql_operation_name, result)
  values (gen_random_uuid(), v_tenant_id, 'api_key', v_key.id, 'graphql', 'query resolveTenant', 'resolveTenant', 'success');
end;
$$;

\echo '>> schema-privilege defense in depth: authenticated has no direct table access to app.api_logs; anon holds no EXECUTE on app.record_api_request'
do $$
begin
  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000002201", "role": "authenticated"}';
  begin
    perform 1 from app.api_logs limit 1;
    raise exception 'assertion failed: authenticated must be denied SELECT on app.api_logs entirely, but the query succeeded';
  exception
    when insufficient_privilege then
      null;
  end;
  reset role;

  set local role anon;
  begin
    perform app.record_api_request(gen_random_uuid(), null, null, 'anon', null, 'rest', 'GET /v1/health', 'GET', '/v1/health', null, 200, 'success', null, null, 5);
    raise exception 'assertion failed: anon must be denied EXECUTE on app.record_api_request entirely, but the call succeeded';
  exception
    when insufficient_privilege then
      null;
  end;
  reset role;
end;
$$;

\echo '>> PLT-130 (REST and GraphQL Platform API Foundation) test suite passed'
