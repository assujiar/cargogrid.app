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

\echo '>> ISS-2026-177: PLT-115''s start_support_session() also now leaves a canonical app.audit_logs entry at session-open, not only revoke_support_access -- and re-starting an already-open session (idempotent no-op) does not double-log'
do $$
declare
  v_tenant_id uuid;
  v_grant app.support_access_grants;
  v_session1 app.support_access_sessions;
  v_session2 app.support_access_sessions;
  v_audit_count integer;
  v_audit_row app.audit_logs;
begin
  v_tenant_id := (select id from app.tenants where slug = 'acmeaud');
  v_grant := app.request_support_access(v_tenant_id, '00000000-0000-0000-0000-000000000805', 'session-open audit integration test', 'CASE-AUD-2', 60, 'tester');
  perform app.approve_support_access(v_grant.id, '00000000-0000-0000-0000-000000000801', 'tenant admin approval');

  select count(*) into v_audit_count from app.audit_logs where action = 'start_support_session' and tenant_id = v_tenant_id and actor_auth_user_id = '00000000-0000-0000-0000-000000000805';
  if v_audit_count <> 0 then
    raise exception 'assertion failed: expected zero start_support_session audit entries for this grantee before any session is started, saw %', v_audit_count;
  end if;

  v_session1 := app.start_support_session(v_grant.id, now(), 'support agent');

  select * into v_audit_row from app.audit_logs where action = 'start_support_session' and resource_id = v_session1.id;
  if v_audit_row.id is null then
    raise exception 'assertion failed: expected exactly one start_support_session audit entry after the session opened, found none';
  end if;
  if v_audit_row.resource_type <> 'app.support_access_sessions' then
    raise exception 'assertion failed: expected resource_type=app.support_access_sessions, got %', v_audit_row.resource_type;
  end if;
  if v_audit_row.tenant_id <> v_tenant_id then
    raise exception 'assertion failed: expected the audit row''s tenant_id to match the grant''s own tenant';
  end if;
  if v_audit_row.actor_auth_user_id <> '00000000-0000-0000-0000-000000000805' then
    raise exception 'assertion failed: expected actor_auth_user_id to be the grantee, got %', v_audit_row.actor_auth_user_id;
  end if;
  -- app.capture_audit_event's own IAE-037 auto-default (the actor's currently-open
  -- support session for this tenant) should populate the grant linkage even though this
  -- call site never passes it explicitly, the same behavior revoke_support_access relies on.
  if v_audit_row.support_access_grant_id <> v_grant.id then
    raise exception 'assertion failed: expected support_access_grant_id auto-defaulted to %, got %', v_grant.id, v_audit_row.support_access_grant_id;
  end if;

  -- Idempotent re-start (grant already has an open session) must not double-log --
  -- nothing new actually happened.
  v_session2 := app.start_support_session(v_grant.id, now(), 'support agent retry');
  if v_session1.id <> v_session2.id then
    raise exception 'assertion failed: expected re-starting an already-open session to be idempotent';
  end if;

  select count(*) into v_audit_count from app.audit_logs where action = 'start_support_session' and resource_id = v_session1.id;
  if v_audit_count <> 1 then
    raise exception 'assertion failed: expected exactly one start_support_session audit entry after an idempotent re-start, got %', v_audit_count;
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

\echo '>> HDN-386 (Full-System Hardening Integrated Verification) regression, closing HDN-BLK-020 (Critical): app.audit_logs.legal_hold (native) and a generic (IAE-031) app.legal_holds hold on scope app.audit_logs both now block physical deletion at the schema level, not just at the RPC layer -- and a raw DELETE with no session-bound actor (the exact bypass HDN-377''s own Tier C live-forced) is blocked outright'
do $$
declare
  v_tenant_id uuid;
  v_row_native app.audit_logs;
  v_row_generic app.audit_logs;
begin
  v_tenant_id := (select id from app.tenants where slug = 'acmeaud');

  -- Direction A: native flag, set via app.supreme_admin_mutate_audit_log, then a raw
  -- DELETE with no session-bound actor (request.jwt.claims cleared, mirroring
  -- document-file.sql''s own established pattern for this exact bypass shape) must be
  -- blocked -- this is the schema-level backstop for a service_role write that never
  -- goes through app.supreme_admin_delete_audit_log at all.
  v_row_native := app.capture_audit_event(v_tenant_id, '00000000-0000-0000-0000-000000000803', 'supreme admin', 'hdn386_bridge_fixture_native', 'app.audit_logs', gen_random_uuid(), 'success', 'HDN-386 bridge regression fixture', null, null);
  perform app.supreme_admin_mutate_audit_log('00000000-0000-0000-0000-000000000803', v_row_native.id, null, true, 'HDN-386 bridge regression', 'placing native hold');

  perform set_config('request.jwt.claims', 'null', true);
  begin
    delete from app.audit_logs where id = v_row_native.id;
    raise exception 'assertion failed: expected a raw DELETE of a natively-held audit_logs row with no session-bound actor to be blocked, but it succeeded';
  exception
    when others then
      if sqlerrm !~ 'audit_log_legal_hold_blocks_deletion' then raise; end if;
  end;

  -- Direction B: a generic (IAE-031) hold placed on scope app.audit_logs (no native
  -- flag ever set) must ALSO block a raw DELETE -- this is the read-side bridge in
  -- app._is_under_legal_hold, not the native column.
  v_row_generic := app.capture_audit_event(v_tenant_id, '00000000-0000-0000-0000-000000000803', 'supreme admin', 'hdn386_bridge_fixture_generic', 'app.audit_logs', gen_random_uuid(), 'success', 'HDN-386 bridge regression fixture', null, null);
  perform app.request_legal_hold(v_tenant_id, 'audit_security', 'app.audit_logs', v_row_generic.id, 'HDN-386 bridge regression', '00000000-0000-0000-0000-000000000803', 'supreme admin');

  perform set_config('request.jwt.claims', 'null', true);
  begin
    delete from app.audit_logs where id = v_row_generic.id;
    raise exception 'assertion failed: expected a raw DELETE of a generically-held (app.legal_holds) audit_logs row to be blocked, but it succeeded';
  exception
    when others then
      if sqlerrm !~ 'audit_log_legal_hold_blocks_deletion' then raise; end if;
  end;

  -- Direction C: RPD-022's disclosed residual risk is unchanged, not eliminated -- a
  -- genuine Supreme Admin session may still override and physically delete a held row
  -- (this codebase never claims audit records are immutable or tamper-proof). What
  -- HDN-BLK-020 actually closes is the silence: the override must now leave a second,
  -- distinct, honestly-labeled audit trace beyond app.supreme_admin_delete_audit_log's
  -- own generic event.
  perform set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-000000000803", "role": "authenticated"}', true);
  perform app.supreme_admin_delete_audit_log('00000000-0000-0000-0000-000000000803', v_row_native.id, 'HDN-386 regression: deliberate Supreme Admin override of an active legal hold');
  perform set_config('request.jwt.claims', 'null', true);

  if not exists (
    select 1 from app.audit_logs
    where resource_type = 'app.audit_logs' and resource_id = v_row_native.id
      and action = 'delete_legally_held_audit_log' and actor_label = 'supreme_admin_absolute_crud'
  ) then
    raise exception 'assertion failed: expected a distinct delete_legally_held_audit_log/supreme_admin_absolute_crud audit event capturing the Supreme Admin override, none found';
  end if;
end;
$$;

\echo '>> HDN-386 Tier C regression, closing the attack-surface lens own live-reproduced gap: a raw UPDATE of a held app.audit_logs row (clearing legal_hold itself, or nulling before_value/after_value/reason) is now blocked at the schema level, not just the physical DELETE path -- the exact UPDATE-then-DELETE bypass the first round''s own DELETE-only trigger missed'
do $$
declare
  v_tenant_id uuid;
  v_row_native app.audit_logs;
  v_row_generic app.audit_logs;
begin
  v_tenant_id := (select id from app.tenants where slug = 'acmeaud');

  -- Direction A: a raw UPDATE clearing the native legal_hold flag itself must be
  -- blocked -- this is the exact move that, before this fix, silently defeated the
  -- DELETE trigger for a follow-up DELETE.
  v_row_native := app.capture_audit_event(v_tenant_id, '00000000-0000-0000-0000-000000000803', 'supreme admin', 'hdn386_tierc_fixture_native', 'app.audit_logs', gen_random_uuid(), 'success', 'HDN-386 Tier C regression fixture', null, null);
  perform app.supreme_admin_mutate_audit_log('00000000-0000-0000-0000-000000000803', v_row_native.id, null, true, 'HDN-386 Tier C regression', 'placing native hold');

  perform set_config('request.jwt.claims', 'null', true);
  begin
    update app.audit_logs set legal_hold = false where id = v_row_native.id;
    raise exception 'assertion failed: expected a raw UPDATE clearing legal_hold on a held row to be blocked, but it succeeded';
  exception
    when others then
      if sqlerrm !~ 'audit_log_legal_hold_blocks_deletion' then raise; end if;
  end;

  -- Direction B: a raw UPDATE nulling out the row's own informational content
  -- (before_value/after_value/reason) must also be blocked, whether the hold is
  -- native or generic -- content corruption, not just outright deletion, is the
  -- attack-surface lens's own headline finding.
  v_row_generic := app.capture_audit_event(v_tenant_id, '00000000-0000-0000-0000-000000000803', 'supreme admin', 'hdn386_tierc_fixture_generic', 'app.audit_logs', gen_random_uuid(), 'success', 'HDN-386 Tier C regression fixture', null, null);
  perform app.request_legal_hold(v_tenant_id, 'audit_security', 'app.audit_logs', v_row_generic.id, 'HDN-386 Tier C regression', '00000000-0000-0000-0000-000000000803', 'supreme admin');

  perform set_config('request.jwt.claims', 'null', true);
  begin
    update app.audit_logs set before_value = null, after_value = null, reason = 'CORRUPTED' where id = v_row_generic.id;
    raise exception 'assertion failed: expected a raw UPDATE nulling a generically-held row''s own content to be blocked, but it succeeded';
  exception
    when others then
      if sqlerrm !~ 'audit_log_legal_hold_blocks_deletion' then raise; end if;
  end;

  -- Direction C: confirm the flag genuinely never cleared and the row survives a
  -- follow-up DELETE attempt too -- the full original attack chain is closed end to
  -- end, not just its first step.
  perform 1 from app.audit_logs where id = v_row_native.id and legal_hold = true;
  if not found then
    raise exception 'assertion failed: expected the native row''s own legal_hold flag to remain true after the blocked UPDATE attempt';
  end if;
  begin
    delete from app.audit_logs where id = v_row_native.id;
    raise exception 'assertion failed: expected the follow-up DELETE to still be blocked (the flag was never actually cleared), but it succeeded';
  exception
    when others then
      if sqlerrm !~ 'audit_log_legal_hold_blocks_deletion' then raise; end if;
  end;
  perform set_config('request.jwt.claims', 'null', true);
end;
$$;

\echo 'ALL PLT-116 db-test assertions passed.'
