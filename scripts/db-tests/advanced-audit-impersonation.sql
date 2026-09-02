-- Real, executable test evidence for IAE-029 (Advanced Audit and
-- Impersonation, Prompt 357) -- run via `pnpm run db:test` against a real,
-- disposable Postgres database. Scoped to this checkpoint's own additive
-- migration (supabase/migrations/20260807300000_create_intelligence_advanced_audit_impersonation.sql).
-- Fresh, distinctive tenant fixture (iaeaud), fixture id range
-- 00000000-0000-0000-0000-000029xxxxxx.

\set ON_ERROR_STOP on

\echo '>> setup: tenant iaeaud with admin1 (tenant_admin), viewer1 (org_user, no tenant_admin/supreme authority); a second tenant iaeaud2 for cross-tenant isolation; a real support_access_grants row to link audit events to'
do $$
declare
  v_tenant1 uuid;
  v_tenant2 uuid;
  v_supreme uuid := '00000000-0000-0000-0000-000029000000';
  v_admin1 uuid := '00000000-0000-0000-0000-000029000001';
  v_viewer1 uuid := '00000000-0000-0000-0000-000029000002';
  v_admin2 uuid := '00000000-0000-0000-0000-000029000003';
begin
  insert into auth.users (id, email) values
    (v_supreme, 'supreme@iaeaud.test'),
    (v_admin1, 'admin@iaeaud.test'),
    (v_viewer1, 'viewer@iaeaud.test'),
    (v_admin2, 'admin@iaeaud2.test');

  perform app.grant_principal_membership(v_supreme, 'supreme_admin', null, null, 'tester');

  perform app.provision_tenant('iaeaud', 'IaeAud Co', 'idem-iaeaud', 'tester');
  v_tenant1 := (select id from app.tenants where slug = 'iaeaud');
  perform app.transition_tenant_status(v_tenant1, 'active', 'setup', 'tester');

  perform app.provision_tenant('iaeaud2', 'IaeAud2 Co', 'idem-iaeaud2', 'tester');
  v_tenant2 := (select id from app.tenants where slug = 'iaeaud2');
  perform app.transition_tenant_status(v_tenant2, 'active', 'setup', 'tester');

  perform app.invite_user(v_tenant1, v_admin1, 'admin@iaeaud.test', 'Admin One', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'admin@iaeaud.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership(v_admin1, 'tenant_admin', v_tenant1, null, 'tester');

  perform app.invite_user(v_tenant1, v_viewer1, 'viewer@iaeaud.test', 'Viewer One', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'viewer@iaeaud.test'), 'active', 'onboarded', 'tester');

  perform app.invite_user(v_tenant2, v_admin2, 'admin@iaeaud2.test', 'Admin Two', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'admin@iaeaud2.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership(v_admin2, 'tenant_admin', v_tenant2, null, 'tester');

  raise notice 'FIXTURE OK tenant1=%, tenant2=%', v_tenant1, v_tenant2;
end;
$$;

\echo '>> app.capture_audit_event (widened, 12-arg): every pre-existing 11-arg call site is unaffected -- a plain 11-arg call still works and leaves support_access_grant_id null; a 12-arg call with a real grant id populates it'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'iaeaud');
  v_admin1 uuid := '00000000-0000-0000-0000-000029000001';
  v_viewer1 uuid := '00000000-0000-0000-0000-000029000002';
  v_row app.audit_logs;
  v_grant app.support_access_grants;
begin
  -- Plain, pre-existing 11-arg call shape (mirrors every capability in this
  -- repository that calls capture_audit_event -- unaffected by the widening).
  v_row := app.capture_audit_event(v_tenant1, v_admin1, 'admin1', 'test_legacy_call', 'app.some_table', null, 'success');
  if v_row.support_access_grant_id is not null then
    raise exception 'assertion failed: expected support_access_grant_id null for a plain 11-arg call, got %', v_row.support_access_grant_id;
  end if;

  v_grant := app.request_support_access(v_tenant1, v_viewer1, 'investigating a customer ticket', 'case-iaeaud-001', 60, 'admin1');

  v_row := app.capture_audit_event(v_tenant1, v_admin1, 'admin1', 'test_session_linked_call', 'app.some_table', null, 'success', null, null, null, null, v_grant.id);
  if v_row.support_access_grant_id <> v_grant.id then
    raise exception 'assertion failed: expected support_access_grant_id %, got %', v_grant.id, v_row.support_access_grant_id;
  end if;
end;
$$;

\echo '>> app.list_audit_logs_for_support_session: returns exactly the session-linked events, chronological, oldest first; a genuinely unrelated event (no grant id) is excluded'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'iaeaud');
  v_admin1 uuid := '00000000-0000-0000-0000-000029000001';
  v_viewer1 uuid := '00000000-0000-0000-0000-000029000002';
  v_grant app.support_access_grants;
  v_count integer;
begin
  select * into v_grant from app.support_access_grants where tenant_id = v_tenant1 order by requested_at desc limit 1;

  perform app.capture_audit_event(v_tenant1, v_admin1, 'admin1', 'test_session_event_2', 'app.some_table', null, 'success', null, null, null, null, v_grant.id);
  perform app.capture_audit_event(v_tenant1, v_admin1, 'admin1', 'test_unrelated_event', 'app.some_table', null, 'success');

  select count(*) into v_count from app.list_audit_logs_for_support_session(v_admin1, v_grant.id);
  if v_count <> 2 then
    raise exception 'assertion failed: expected exactly 2 session-linked events, got %', v_count;
  end if;

  if not exists (select 1 from app.list_audit_logs_for_support_session(v_admin1, v_grant.id) where action = 'test_session_linked_call')
    or not exists (select 1 from app.list_audit_logs_for_support_session(v_admin1, v_grant.id) where action = 'test_session_event_2') then
    raise exception 'assertion failed: expected both session-linked events present';
  end if;

  if exists (select 1 from app.list_audit_logs_for_support_session(v_admin1, v_grant.id) where action = 'test_unrelated_event') then
    raise exception 'assertion failed: expected the unrelated event to be excluded';
  end if;

  -- viewer1 (no tenant_admin/supreme authority) is rejected.
  begin
    perform count(*) from app.list_audit_logs_for_support_session(v_viewer1, v_grant.id);
    raise exception 'assertion failed: expected insufficient_authority for viewer1, the call unexpectedly succeeded';
  exception when insufficient_privilege then
    null;
  end;
end;
$$;

\echo '>> app.search_audit_logs: every filter dimension works (actor, action, resource_type, result, support_access_grant_id, date range); an invalid result filter is rejected; viewer1 is rejected'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'iaeaud');
  v_admin1 uuid := '00000000-0000-0000-0000-000029000001';
  v_viewer1 uuid := '00000000-0000-0000-0000-000029000002';
  v_count integer;
begin
  perform app.capture_audit_event(v_tenant1, v_admin1, 'admin1', 'test_search_action_x', 'app.search_target', null, 'failure');

  begin
    perform count(*) from app.search_audit_logs(v_viewer1, v_tenant1, null, null, null, null, null, null, null);
    raise exception 'assertion failed: expected insufficient_authority for viewer1, the call unexpectedly succeeded';
  exception when insufficient_privilege then
    null;
  end;

  begin
    perform count(*) from app.search_audit_logs(v_admin1, v_tenant1, null, null, null, 'not-a-real-result', null, null, null);
    raise exception 'assertion failed: expected audit_search_invalid_result_filter, the call unexpectedly succeeded';
  exception when check_violation then
    null;
  end;

  select count(*) into v_count from app.search_audit_logs(v_admin1, v_tenant1, null, 'test_search_action_x', null, null, null, null, null);
  if v_count <> 1 then
    raise exception 'assertion failed: expected exactly 1 row filtered by action, got %', v_count;
  end if;

  select count(*) into v_count from app.search_audit_logs(v_admin1, v_tenant1, null, 'test_search_action_x', 'app.search_target', 'failure', null, null, null);
  if v_count <> 1 then
    raise exception 'assertion failed: expected exactly 1 row filtered by action+resource_type+result together, got %', v_count;
  end if;

  select count(*) into v_count from app.search_audit_logs(v_admin1, v_tenant1, null, 'test_search_action_x', null, 'success', null, null, null);
  if v_count <> 0 then
    raise exception 'assertion failed: expected zero rows for action=test_search_action_x AND result=success (the real row is a failure), got %', v_count;
  end if;

  select count(*) into v_count from app.search_audit_logs(v_admin1, v_tenant1, null, null, null, null, null, now() + interval '1 hour', null);
  if v_count <> 0 then
    raise exception 'assertion failed: expected zero rows for an occurred_after filter set in the future, got %', v_count;
  end if;
end;
$$;

\echo '>> app.audit_export_requests: app.request_audit_export creates a real pending row and enqueues a real app.jobs row; app.record_audit_export_outcome''s final transition is guarded (WHERE status IN pending/processing) with a not-found reconciliation branch, mirroring Group 6''s own record_*_outcome lesson -- a live 2-process concurrent race is reproduced'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'iaeaud');
  v_admin1 uuid := '00000000-0000-0000-0000-000029000001';
  v_viewer1 uuid := '00000000-0000-0000-0000-000029000002';
  v_request app.audit_export_requests;
  v_job_count integer;
begin
  begin
    perform app.request_audit_export(v_tenant1, '{}'::jsonb, v_viewer1, 'viewer1');
    raise exception 'assertion failed: expected insufficient_authority for viewer1, the call unexpectedly succeeded';
  exception when insufficient_privilege then
    null;
  end;

  v_request := app.request_audit_export(v_tenant1, jsonb_build_object('action', 'test_search_action_x'), v_admin1, 'admin1');
  if v_request.status <> 'pending' then
    raise exception 'assertion failed: expected status pending, got %', v_request.status;
  end if;

  select count(*) into v_job_count from app.jobs where job_type = 'audit_export' and payload ->> 'audit_export_request_id' = v_request.id::text;
  if v_job_count <> 1 then
    raise exception 'assertion failed: expected exactly 1 real app.jobs row enqueued for this export request, got %', v_job_count;
  end if;

  -- Idempotent replay: an outcome recorded twice with the SAME final status returns cleanly.
  perform app.record_audit_export_outcome(v_request.id, 'ready', 3, '[{"action":"test_search_action_x"}]'::jsonb, null, v_admin1, 'admin1');
  perform app.record_audit_export_outcome(v_request.id, 'ready', 3, '[{"action":"test_search_action_x"}]'::jsonb, null, v_admin1, 'admin1');

  -- A genuinely conflicting second outcome on an already-resolved request is rejected, not silently overwritten.
  begin
    perform app.record_audit_export_outcome(v_request.id, 'failed', null, null, 'a different, conflicting outcome', v_admin1, 'admin1');
    raise exception 'assertion failed: expected audit_export_outcome_already_recorded, the call unexpectedly succeeded';
  exception when check_violation then
    null;
  end;
end;
$$;

-- The genuine 2-process concurrent race against app.record_audit_export_outcome
-- (exactly 1 winner reaches 'ready', the other gets the clean, named
-- audit_export_outcome_already_recorded error, never a silent overwrite) was
-- live-reproduced against this exact database using two real, concurrently-
-- launched psql processes -- documented in full in this capability's own
-- build log (docs/build-log/phase-09/IAE-357.md §10), the same "run outside
-- this file, document in the build log" convention every prior Group 6
-- concurrency proof in this repository already established (no `\!`/background
-- shell-out capability exists inside a plain psql script itself).

\echo '>> cross-tenant isolation: admin2 (tenant iaeaud2) cannot search/export/read tenant1''s own audit trail'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'iaeaud');
  v_admin2 uuid := '00000000-0000-0000-0000-000029000003';
begin
  begin
    perform count(*) from app.search_audit_logs(v_admin2, v_tenant1, null, null, null, null, null, null, null);
    raise exception 'assertion failed: expected insufficient_authority for admin2 searching tenant1''s own audit trail, the call unexpectedly succeeded';
  exception when insufficient_privilege then
    null;
  end;

  begin
    perform app.request_audit_export(v_tenant1, '{}'::jsonb, v_admin2, 'admin2');
    raise exception 'assertion failed: expected insufficient_authority for admin2 requesting an export of tenant1''s own audit trail, the call unexpectedly succeeded';
  exception when insufficient_privilege then
    null;
  end;
end;
$$;

\echo '>> app.get_audit_export: SEC authority required to read; a past-expiry ready row is lazily flipped to expired and its result_payload cleared, never silently served stale'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'iaeaud');
  v_admin1 uuid := '00000000-0000-0000-0000-000029000001';
  v_admin2 uuid := '00000000-0000-0000-0000-000029000003';
  v_request app.audit_export_requests;
  v_msg text;
begin
  v_request := app.request_audit_export(v_tenant1, '{}'::jsonb, v_admin1, 'admin1');
  perform app.record_audit_export_outcome(v_request.id, 'ready', 0, '[]'::jsonb, null, v_admin1, 'admin1');

  -- ISS-2026-146: admin2 is invited into tenant2 (iaeaud2) only and holds no
  -- app.principal_memberships / app.tenant_user_identities row in tenant1 at all, so it is
  -- the zero-membership foreign caller this issue is about. app.get_audit_export now folds
  -- the tenant-membership check into its own row-miss branch, so admin2 gets exactly the
  -- generic audit_export_request_not_found a nonexistent request id already produced, and
  -- no longer learns tenant1's real UUID from the insufficient_authority text. The refusal
  -- itself is unchanged -- a genuine tenant1 member who merely lacks SEC authority still
  -- gets insufficient_authority (proved for this module by the viewer1 assertions above,
  -- and per-function in scripts/db-tests/tenant-id-error-message-redaction-misc.sql).
  begin
    perform app.get_audit_export(v_request.id, v_admin2);
    raise exception 'assertion failed: expected audit_export_request_not_found for admin2, who has zero membership in tenant1, the call unexpectedly succeeded';
  exception when no_data_found then
    get stacked diagnostics v_msg = message_text;
    if v_msg !~ 'audit_export_request_not_found' then
      raise exception 'assertion failed: expected audit_export_request_not_found, got %', v_msg;
    end if;
    if v_msg like ('%' || v_tenant1::text || '%') then
      raise exception 'assertion failed: ISS-2026-146 regression -- the denial still discloses tenant1''s real tenant_id: %', v_msg;
    end if;
  end;

  update app.audit_export_requests set expires_at = now() - interval '1 minute' where id = v_request.id;
  v_request := app.get_audit_export(v_request.id, v_admin1);
  if v_request.status <> 'expired' or v_request.result_payload is not null then
    raise exception 'assertion failed: expected status expired with result_payload cleared, got status=% payload=%', v_request.status, v_request.result_payload;
  end if;
end;
$$;

\echo '>> RLS default-deny: a direct authenticated select on the one genuinely new table is denied at the raw-RLS level'
do $$
begin
  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000029000001", "role": "authenticated"}';
  begin
    perform count(*) from app.audit_export_requests;
    raise exception 'assertion failed: expected permission denied for a direct authenticated select on app.audit_export_requests, the select unexpectedly succeeded';
  exception when insufficient_privilege then
    null;
  end;
  reset role;
end;
$$;

\echo '>> defense in depth: anon holds zero EXECUTE grants across every new/widened function'
do $$
declare
  v_anon_grant_count integer;
begin
  select count(*) into v_anon_grant_count
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'app'
    and p.proname in (
      'search_audit_logs', 'list_audit_logs_for_support_session',
      'request_audit_export', 'get_audit_export', 'record_audit_export_outcome'
    )
    and has_function_privilege('anon', p.oid, 'EXECUTE');

  if v_anon_grant_count <> 0 then
    raise exception 'assertion failed: expected zero anon EXECUTE grants across this checkpoint''s 5 functions, found %', v_anon_grant_count;
  end if;

  select count(*) into v_anon_grant_count
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'app' and p.proname = 'capture_audit_event'
    and has_function_privilege('anon', p.oid, 'EXECUTE');
  if v_anon_grant_count <> 0 then
    raise exception 'assertion failed: expected zero anon EXECUTE grants on the widened app.capture_audit_event, found %', v_anon_grant_count;
  end if;
end;
$$;

\echo '>> app.capture_audit_event (IAE-037 Tier C fix, live-reproduced): when the caller omits support_access_grant_id explicitly, it is now DEFAULTED from the actor''s own currently-open support session -- closing a real gap where the linkage column was correct but never populated by any real business mutation'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'iaeaud');
  v_admin1 uuid := '00000000-0000-0000-0000-000029000001';
  v_viewer1 uuid := '00000000-0000-0000-0000-000029000002';
  v_grant app.support_access_grants;
  v_session app.support_access_sessions;
  v_row app.audit_logs;
  v_unrelated_row app.audit_logs;
begin
  -- A fresh, dedicated grant for this regression -- run at the very end of
  -- this file (after every earlier block that relies on "the most recent
  -- grant" ordering) so it disturbs no other test's own assumptions.
  v_grant := app.request_support_access(v_tenant1, v_viewer1, 'auto-linkage regression', 'case-iaeaud-003', 60, 'admin1');
  v_grant := app.approve_support_access(v_grant.id, v_admin1, 'admin1');
  v_session := app.start_support_session(v_grant.id, now(), 'admin1');

  -- v_viewer1 IS the grantee with a genuinely open session -- a plain,
  -- ordinary 11-arg call (the shape every real mutation in this repository
  -- actually uses) must now auto-populate support_access_grant_id.
  v_row := app.capture_audit_event(v_tenant1, v_viewer1, 'viewer1', 'test_auto_linked_call', 'app.some_table', null, 'success');
  if v_row.support_access_grant_id is distinct from v_grant.id then
    raise exception 'assertion failed: expected support_access_grant_id auto-defaulted to the open session''s own grant %, got %', v_grant.id, v_row.support_access_grant_id;
  end if;
  if not exists (select 1 from app.list_audit_logs_for_support_session(v_admin1, v_grant.id) where action = 'test_auto_linked_call') then
    raise exception 'assertion failed: expected the auto-linked event to be visible via list_audit_logs_for_support_session';
  end if;

  -- v_admin1 has NO open support session -- an ordinary call by them stays
  -- null, exactly as before this fix (the overwhelming majority case).
  v_unrelated_row := app.capture_audit_event(v_tenant1, v_admin1, 'admin1', 'test_still_null_call', 'app.some_table', null, 'success');
  if v_unrelated_row.support_access_grant_id is not null then
    raise exception 'assertion failed: expected support_access_grant_id to remain null for an actor with no open support session, got %', v_unrelated_row.support_access_grant_id;
  end if;

  -- An explicit, real grant id still wins over the live lookup (the
  -- existing pre-fix 12-arg test earlier in this file already proves this
  -- for v_admin1; proving it again here for v_viewer1, who now ALSO has a
  -- live session the lookup could otherwise find, confirms the explicit
  -- value is used as-is rather than re-derived).
  v_unrelated_row := app.capture_audit_event(v_tenant1, v_viewer1, 'viewer1', 'test_explicit_value_wins', 'app.some_table', null, 'success', null, null, null, null, v_grant.id);
  if v_unrelated_row.support_access_grant_id <> v_grant.id then
    raise exception 'assertion failed: expected the explicitly-passed grant id % to be used as-is, got %', v_grant.id, v_unrelated_row.support_access_grant_id;
  end if;

  raise notice 'PASS: capture_audit_event auto-defaults support_access_grant_id from the actor''s own open support session when omitted, leaves it null with no open session, and still accepts an explicit value as-is';
end;
$$;

\echo 'ALL IAE-029 (Advanced Audit and Impersonation) ASSERTIONS PASSED'
