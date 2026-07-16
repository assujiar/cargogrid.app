-- Real, executable test evidence for PLT-116 (Audit Trail Foundation, CG-S6-PLT-013).

\set ON_ERROR_STOP on

\echo '>> setup: two tenants, a tenant_admin for each, a regular org_user, a global Supreme Admin, and a support agent for the representative-integration test'
do $$
declare
  v_tenant_id uuid;
  v_other_tenant_id uuid;
  v_org_unit_id uuid;
begin
  insert into auth.users (id, email) values
    ('00000000-0000-0000-0000-000000000801', 'tenantadminaud@example.test'),
    ('00000000-0000-0000-0000-000000000802', 'regularuseraud@example.test'),
    ('00000000-0000-0000-0000-000000000803', 'supremeaud@example.test'),
    ('00000000-0000-0000-0000-000000000804', 'othertenantadminaud@example.test'),
    ('00000000-0000-0000-0000-000000000805', 'supportagentaud@example.test');

  perform app.provision_tenant('acmeaud', 'Acme Audit Co', 'idem-acmeaud', 'tester');
  v_tenant_id := (select id from app.tenants where slug = 'acmeaud');
  perform app.transition_tenant_status(v_tenant_id, 'active', 'setup', 'tester');
  perform app.create_org_unit(v_tenant_id, 'company', null, 'ACMEAUD-CO', 'Acme Audit Co HQ', 'tester');
  v_org_unit_id := (select id from app.org_units where tenant_id = v_tenant_id and code = 'ACMEAUD-CO');

  perform app.invite_user(v_tenant_id, '00000000-0000-0000-0000-000000000801', 'tenantadminaud@example.test', 'Tenant Admin', v_org_unit_id, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'tenantadminaud@example.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000000801', 'tenant_admin', v_tenant_id, null, 'tester');

  perform app.invite_user(v_tenant_id, '00000000-0000-0000-0000-000000000802', 'regularuseraud@example.test', 'Regular User', v_org_unit_id, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'regularuseraud@example.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000000802', 'org_user', v_tenant_id, null, 'tester');

  perform app.grant_principal_membership('00000000-0000-0000-0000-000000000803', 'supreme_admin', null, null, 'tester');

  perform app.provision_tenant('gizmoaud', 'Gizmo Audit Co', 'idem-gizmoaud', 'tester');
  v_other_tenant_id := (select id from app.tenants where slug = 'gizmoaud');
  perform app.transition_tenant_status(v_other_tenant_id, 'active', 'setup', 'tester');
  perform app.invite_user(v_other_tenant_id, '00000000-0000-0000-0000-000000000804', 'othertenantadminaud@example.test', 'Other Tenant Admin', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'othertenantadminaud@example.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000000804', 'tenant_admin', v_other_tenant_id, null, 'tester');
end;
$$;

\echo '>> app.capture_audit_event: basic insert, auto-generated correlation_id when omitted'
do $$
declare
  v_tenant_id uuid;
  v_row app.audit_logs;
begin
  v_tenant_id := (select id from app.tenants where slug = 'acmeaud');
  v_row := app.capture_audit_event(v_tenant_id, '00000000-0000-0000-0000-000000000801', 'tenant admin', 'update', 'app.tenants', v_tenant_id, 'success', 'routine update');
  if v_row.id is null or v_row.correlation_id is null then
    raise exception 'assertion failed: expected a captured row with a generated id and correlation_id';
  end if;
  if v_row.result <> 'success' then
    raise exception 'assertion failed: expected result=success, got %', v_row.result;
  end if;
end;
$$;

\echo '>> app.capture_audit_event: an invalid result value is rejected by the check constraint'
do $$
declare
  v_tenant_id uuid;
begin
  v_tenant_id := (select id from app.tenants where slug = 'acmeaud');
  begin
    perform app.capture_audit_event(v_tenant_id, '00000000-0000-0000-0000-000000000801', 'tenant admin', 'update', 'app.tenants', v_tenant_id, 'maybe');
    raise exception 'assertion failed: expected an invalid result value to be rejected';
  exception
    when check_violation then
      null; -- expected
  end;
end;
$$;

\echo '>> app.capture_audit_event: an explicit correlation_id propagates unchanged; two calls with identical arguments still produce two distinct rows (not deduplicated)'
do $$
declare
  v_tenant_id uuid;
  v_correlation_id uuid := gen_random_uuid();
  v_row1 app.audit_logs;
  v_row2 app.audit_logs;
begin
  v_tenant_id := (select id from app.tenants where slug = 'acmeaud');
  v_row1 := app.capture_audit_event(v_tenant_id, '00000000-0000-0000-0000-000000000801', 'tenant admin', 'create', 'app.org_units', null, 'success', null, null, null, v_correlation_id);
  v_row2 := app.capture_audit_event(v_tenant_id, '00000000-0000-0000-0000-000000000801', 'tenant admin', 'create', 'app.org_units', null, 'success', null, null, null, v_correlation_id);

  if v_row1.correlation_id <> v_correlation_id or v_row2.correlation_id <> v_correlation_id then
    raise exception 'assertion failed: expected the explicit correlation_id to propagate unchanged on both rows';
  end if;
  if v_row1.id = v_row2.id then
    raise exception 'assertion failed: expected two distinct rows even with identical arguments';
  end if;
end;
$$;

\echo '>> app.redact_audit_payload: sensitive key names are redacted (top-level and nested); ordinary keys pass through unchanged'
do $$
declare
  v_tenant_id uuid;
  v_row app.audit_logs;
begin
  v_tenant_id := (select id from app.tenants where slug = 'acmeaud');
  v_row := app.capture_audit_event(
    v_tenant_id, '00000000-0000-0000-0000-000000000801', 'tenant admin', 'update', 'app.users', null, 'success', 'password reset',
    jsonb_build_object('password', 'hunter2', 'display_name', 'Old Name', 'nested', jsonb_build_object('api_key', 'sk-abc123', 'ok_field', 'kept')),
    jsonb_build_object('password', 'hunter3', 'display_name', 'New Name')
  );

  if v_row.before_value->>'password' <> '[REDACTED]' then
    raise exception 'assertion failed: expected top-level password to be redacted, got %', v_row.before_value->>'password';
  end if;
  if v_row.before_value->>'display_name' <> 'Old Name' then
    raise exception 'assertion failed: expected display_name to pass through unchanged, got %', v_row.before_value->>'display_name';
  end if;
  if v_row.before_value#>>'{nested,api_key}' <> '[REDACTED]' then
    raise exception 'assertion failed: expected a nested api_key to be redacted, got %', v_row.before_value#>>'{nested,api_key}';
  end if;
  if v_row.before_value#>>'{nested,ok_field}' <> 'kept' then
    raise exception 'assertion failed: expected a nested non-sensitive field to pass through unchanged, got %', v_row.before_value#>>'{nested,ok_field}';
  end if;
  if v_row.after_value->>'password' <> '[REDACTED]' then
    raise exception 'assertion failed: expected after_value password to be redacted too';
  end if;
end;
$$;

\echo '>> RPD-022: only Supreme Admin may mutate an existing audit_logs row; the mutation itself is captured with before/after values (06_RLS_RBAC_WORKSTREAM.md §10 test #9)'
do $$
declare
  v_tenant_id uuid;
  v_target app.audit_logs;
  v_mutated app.audit_logs;
  v_self_audit_count integer;
begin
  v_tenant_id := (select id from app.tenants where slug = 'acmeaud');
  v_target := app.capture_audit_event(v_tenant_id, '00000000-0000-0000-0000-000000000801', 'tenant admin', 'create', 'app.org_units', null, 'success', 'original reason');

  begin
    perform app.supreme_admin_mutate_audit_log('00000000-0000-0000-0000-000000000801', v_target.id, 'tampered reason', true, 'litigation hold', 'attempted non-admin mutation');
    raise exception 'assertion failed: expected a non-Supreme-Admin mutation attempt to be rejected';
  exception
    when insufficient_privilege then
      null; -- expected
  end;

  v_mutated := app.supreme_admin_mutate_audit_log('00000000-0000-0000-0000-000000000803', v_target.id, 'corrected reason', true, 'litigation hold', 'operator-confirmed correction');
  if v_mutated.reason <> 'corrected reason' or v_mutated.legal_hold is not true then
    raise exception 'assertion failed: expected the Supreme Admin mutation to apply';
  end if;

  select count(*) into v_self_audit_count
  from app.audit_logs
  where action = 'supreme_admin_mutate_audit_log' and resource_id = v_target.id;
  if v_self_audit_count <> 1 then
    raise exception 'assertion failed: expected exactly one self-audit entry for this mutation, saw %', v_self_audit_count;
  end if;

  if (
    select (before_value->>'reason') = 'original reason' and (after_value->>'reason') = 'corrected reason'
    from app.audit_logs
    where action = 'supreme_admin_mutate_audit_log' and resource_id = v_target.id
  ) is not true then
    raise exception 'assertion failed: expected the self-audit entry to carry accurate before/after reason values';
  end if;
end;
$$;

\echo '>> RPD-022: only Supreme Admin may delete an audit_logs row; the deletion itself is captured, preserving the before-image'
do $$
declare
  v_tenant_id uuid;
  v_target app.audit_logs;
  v_still_exists boolean;
  v_delete_audit app.audit_logs;
begin
  v_tenant_id := (select id from app.tenants where slug = 'acmeaud');
  v_target := app.capture_audit_event(v_tenant_id, '00000000-0000-0000-0000-000000000801', 'tenant admin', 'create', 'app.org_units', null, 'success', 'to be deleted');

  begin
    perform app.supreme_admin_delete_audit_log('00000000-0000-0000-0000-000000000801', v_target.id, 'attempted non-admin delete');
    raise exception 'assertion failed: expected a non-Supreme-Admin delete attempt to be rejected';
  exception
    when insufficient_privilege then
      null; -- expected
  end;

  perform app.supreme_admin_delete_audit_log('00000000-0000-0000-0000-000000000803', v_target.id, 'operator-confirmed erasure request');

  select exists(select 1 from app.audit_logs where id = v_target.id) into v_still_exists;
  if v_still_exists then
    raise exception 'assertion failed: expected the target row to actually be deleted';
  end if;

  select * into v_delete_audit
  from app.audit_logs
  where action = 'supreme_admin_delete_audit_log' and resource_id = v_target.id;
  if v_delete_audit.id is null then
    raise exception 'assertion failed: expected the deletion itself to be captured';
  end if;
  if v_delete_audit.before_value->>'reason' <> 'to be deleted' then
    raise exception 'assertion failed: expected the deletion''s self-audit entry to preserve the deleted row''s before-image';
  end if;
end;
$$;

\echo '>> app.query_audit_logs: authority is Supreme Admin or the target tenant''s own tenant_admin -- a regular org_user is denied'
do $$
declare
  v_tenant_id uuid;
begin
  v_tenant_id := (select id from app.tenants where slug = 'acmeaud');
  begin
    perform app.query_audit_logs('00000000-0000-0000-0000-000000000802', v_tenant_id, 10);
    raise exception 'assertion failed: expected a regular org_user to be denied query authority';
  exception
    when insufficient_privilege then
      null; -- expected
  end;

  perform app.query_audit_logs('00000000-0000-0000-0000-000000000801', v_tenant_id, 10);
  perform app.query_audit_logs('00000000-0000-0000-0000-000000000803', v_tenant_id, 10);
end;
$$;

\echo '>> app.query_audit_logs / app.export_audit_logs self-log their own invocation with distinct action labels -- "privileged access itself audited"'
do $$
declare
  v_tenant_id uuid;
  v_query_count_before integer;
  v_query_count_after integer;
  v_export_count_before integer;
  v_export_count_after integer;
begin
  v_tenant_id := (select id from app.tenants where slug = 'acmeaud');

  select count(*) into v_query_count_before from app.audit_logs where tenant_id = v_tenant_id and action = 'query_audit_logs';
  perform app.query_audit_logs('00000000-0000-0000-0000-000000000801', v_tenant_id, 10);
  select count(*) into v_query_count_after from app.audit_logs where tenant_id = v_tenant_id and action = 'query_audit_logs';
  if v_query_count_after <> v_query_count_before + 1 then
    raise exception 'assertion failed: expected exactly one new query_audit_logs self-audit row, before=% after=%', v_query_count_before, v_query_count_after;
  end if;

  select count(*) into v_export_count_before from app.audit_logs where tenant_id = v_tenant_id and action = 'export_audit_logs';
  perform app.export_audit_logs('00000000-0000-0000-0000-000000000801', v_tenant_id, 10);
  select count(*) into v_export_count_after from app.audit_logs where tenant_id = v_tenant_id and action = 'export_audit_logs';
  if v_export_count_after <> v_export_count_before + 1 then
    raise exception 'assertion failed: expected exactly one new export_audit_logs self-audit row, before=% after=%', v_export_count_before, v_export_count_after;
  end if;
end;
$$;

\echo '>> cross-tenant isolation: tenant A''s tenant_admin cannot query tenant B''s audit trail'
do $$
declare
  v_other_tenant_id uuid;
begin
  v_other_tenant_id := (select id from app.tenants where slug = 'gizmoaud');
  begin
    perform app.query_audit_logs('00000000-0000-0000-0000-000000000801', v_other_tenant_id, 10);
    raise exception 'assertion failed: expected tenant A''s tenant_admin to be denied query authority for tenant B';
  exception
    when insufficient_privilege then
      null; -- expected
  end;
end;
$$;

\echo '>> keyset pagination: paging through with the returned cursor never returns the same row twice'
do $$
declare
  v_tenant_id uuid;
  v_page1 uuid[];
  v_page2 uuid[];
  v_page3 uuid[];
  v_last1 record;
  v_last2 record;
  v_all_ids uuid[];
  v_distinct_count integer;
  v_total_count integer;
begin
  v_tenant_id := (select id from app.tenants where slug = 'acmeaud');

  perform app.capture_audit_event(v_tenant_id, '00000000-0000-0000-0000-000000000801', 'tenant admin', 'pagetest', 'app.org_units', null, 'success', 'pagetest-1');
  perform app.capture_audit_event(v_tenant_id, '00000000-0000-0000-0000-000000000801', 'tenant admin', 'pagetest', 'app.org_units', null, 'success', 'pagetest-2');
  perform app.capture_audit_event(v_tenant_id, '00000000-0000-0000-0000-000000000801', 'tenant admin', 'pagetest', 'app.org_units', null, 'success', 'pagetest-3');
  perform app.capture_audit_event(v_tenant_id, '00000000-0000-0000-0000-000000000801', 'tenant admin', 'pagetest', 'app.org_units', null, 'success', 'pagetest-4');
  perform app.capture_audit_event(v_tenant_id, '00000000-0000-0000-0000-000000000801', 'tenant admin', 'pagetest', 'app.org_units', null, 'success', 'pagetest-5');

  select array_agg(id) into v_page1 from (select id, occurred_at from app.query_audit_logs('00000000-0000-0000-0000-000000000801', v_tenant_id, 2) order by occurred_at desc, id desc) s;
  select occurred_at, id into v_last1 from app.audit_logs where id = v_page1[array_length(v_page1, 1)];

  select array_agg(id) into v_page2 from (select id, occurred_at from app.query_audit_logs('00000000-0000-0000-0000-000000000801', v_tenant_id, 2, v_last1.occurred_at, v_last1.id) order by occurred_at desc, id desc) s;
  select occurred_at, id into v_last2 from app.audit_logs where id = v_page2[array_length(v_page2, 1)];

  select array_agg(id) into v_page3 from (select id, occurred_at from app.query_audit_logs('00000000-0000-0000-0000-000000000801', v_tenant_id, 2, v_last2.occurred_at, v_last2.id) order by occurred_at desc, id desc) s;

  v_all_ids := v_page1 || v_page2 || v_page3;
  select count(*), count(distinct x) into v_total_count, v_distinct_count from unnest(v_all_ids) x;
  if v_total_count <> v_distinct_count then
    raise exception 'assertion failed: expected zero overlap across keyset pages, total=% distinct=%', v_total_count, v_distinct_count;
  end if;
end;
$$;

\echo '>> representative platform-event integration: PLT-115''s revoke_support_access() kill switch now also leaves a canonical app.audit_logs entry'
do $$
declare
  v_tenant_id uuid;
  v_grant app.support_access_grants;
  v_audit_count integer;
  v_audit_row app.audit_logs;
begin
  v_tenant_id := (select id from app.tenants where slug = 'acmeaud');
  v_grant := app.request_support_access(v_tenant_id, '00000000-0000-0000-0000-000000000805', 'audit integration test', 'CASE-AUD-1', 60, 'tester');
  perform app.approve_support_access(v_grant.id, '00000000-0000-0000-0000-000000000801', 'tenant admin approval');

  select count(*) into v_audit_count from app.audit_logs where action = 'revoke_support_access' and resource_id = v_grant.id;
  if v_audit_count <> 0 then
    raise exception 'assertion failed: expected zero revoke_support_access audit entries before the grant is actually revoked';
  end if;

  perform app.revoke_support_access(v_grant.id, '00000000-0000-0000-0000-000000000801', 'tenant admin', 'audit integration test revoke');

  select * into v_audit_row from app.audit_logs where action = 'revoke_support_access' and resource_id = v_grant.id;
  if v_audit_row.id is null then
    raise exception 'assertion failed: expected exactly one revoke_support_access audit entry after the kill switch fired';
  end if;
  if v_audit_row.resource_type <> 'app.support_access_grants' then
    raise exception 'assertion failed: expected resource_type=app.support_access_grants, got %', v_audit_row.resource_type;
  end if;
  if (v_audit_row.before_value->>'status') <> 'approved' or (v_audit_row.after_value->>'status') <> 'revoked' then
    raise exception 'assertion failed: expected before/after status values to show the approved->revoked transition, got before=% after=%', v_audit_row.before_value->>'status', v_audit_row.after_value->>'status';
  end if;
end;
$$;

\echo '>> defense in depth: anon and authenticated are denied direct table access to app.audit_logs; service_role has explicit access'
do $$
begin
  set local role anon;
  begin
    perform count(*) from app.audit_logs;
    raise exception 'assertion failed: anon must be denied on app.audit_logs';
  exception
    when insufficient_privilege then
      null; -- expected
  end;
  reset role;
end;
$$;

do $$
begin
  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000000803", "role": "authenticated"}';
  begin
    perform count(*) from app.audit_logs;
    raise exception 'assertion failed: authenticated must be denied direct table access to app.audit_logs, even for a Supreme Admin -- the only path is app.query_audit_logs()/app.export_audit_logs()';
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
  select count(*) into v_count from app.audit_logs;
  if v_count < 15 then
    raise exception 'assertion failed: expected service_role to see every audit_logs row created in this test run, saw %', v_count;
  end if;
  reset role;
end;
$$;

\echo 'ALL PLT-116 db-test assertions passed.'
