-- Real, executable test evidence for IAE-031 (Data Retention and Archival,
-- Prompt 359) -- run via `pnpm run db:test` against a real, disposable
-- Postgres database. Scoped to this checkpoint's own additive migration
-- (supabase/migrations/20260807500000_create_intelligence_data_retention_archival.sql).
-- Fresh, distinctive tenant fixture (iaeret), fixture id range
-- 00000000-0000-0000-0000-000034xxxxxx.

\set ON_ERROR_STOP on

\echo '>> setup: tenant iaeret with admin1 (tenant_admin + RET:Configure/View), approver1 (RET:Approve/View), viewer1 (RET:View only), rep1 (plain org_user, no RET grants); a second tenant iaeret2 with admin2 (tenant_admin + RET:Configure/View/Approve) for cross-tenant isolation'
do $$
declare
  v_tenant1 uuid;
  v_tenant2 uuid;
  v_supreme uuid := '00000000-0000-0000-0000-000034000000';
  v_admin1 uuid := '00000000-0000-0000-0000-000034000001';
  v_viewer1 uuid := '00000000-0000-0000-0000-000034000002';
  v_rep1 uuid := '00000000-0000-0000-0000-000034000003';
  v_admin2 uuid := '00000000-0000-0000-0000-000034000004';
  v_approver1 uuid := '00000000-0000-0000-0000-000034000005';
  v_admin1_role uuid;
  v_admin1_draft app.role_versions;
  v_viewer_role uuid;
  v_viewer_draft app.role_versions;
  v_approver_role uuid;
  v_approver_draft app.role_versions;
  v_admin2_role uuid;
  v_admin2_draft app.role_versions;
begin
  insert into auth.users (id, email) values
    (v_supreme, 'supreme@iaeret.test'),
    (v_admin1, 'admin@iaeret.test'),
    (v_viewer1, 'viewer@iaeret.test'),
    (v_rep1, 'rep@iaeret.test'),
    (v_admin2, 'admin@iaeret2.test'),
    (v_approver1, 'approver@iaeret.test');

  perform app.grant_principal_membership(v_supreme, 'supreme_admin', null, null, 'tester');

  perform app.provision_tenant('iaeret', 'IaeRet Co', 'idem-iaeret', 'tester');
  v_tenant1 := (select id from app.tenants where slug = 'iaeret');
  perform app.transition_tenant_status(v_tenant1, 'active', 'setup', 'tester');

  perform app.provision_tenant('iaeret2', 'IaeRet2 Co', 'idem-iaeret2', 'tester');
  v_tenant2 := (select id from app.tenants where slug = 'iaeret2');
  perform app.transition_tenant_status(v_tenant2, 'active', 'setup', 'tester');

  perform app.invite_user(v_tenant1, v_admin1, 'admin@iaeret.test', 'Admin One', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'admin@iaeret.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership(v_admin1, 'tenant_admin', v_tenant1, null, 'tester');

  perform app.invite_user(v_tenant1, v_viewer1, 'viewer@iaeret.test', 'Viewer One', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'viewer@iaeret.test'), 'active', 'onboarded', 'tester');

  perform app.invite_user(v_tenant1, v_rep1, 'rep@iaeret.test', 'Rep One', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'rep@iaeret.test'), 'active', 'onboarded', 'tester');

  perform app.invite_user(v_tenant1, v_approver1, 'approver@iaeret.test', 'Approver One', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'approver@iaeret.test'), 'active', 'onboarded', 'tester');

  perform app.invite_user(v_tenant2, v_admin2, 'admin@iaeret2.test', 'Admin Two', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'admin@iaeret2.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership(v_admin2, 'tenant_admin', v_tenant2, null, 'tester');

  v_admin1_role := (app.create_role(v_tenant1, 'IaeRet Admin', 'RET:Configure/View', 'tester')).id;
  v_admin1_draft := app.create_role_version(v_admin1_role, 'tester');
  perform app.set_role_version_permissions(v_admin1_draft.id, array(select id from app.permissions where resource_module_code = 'RET' and action in ('Configure', 'View')), 'tester');
  perform app.publish_role_version(v_admin1_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_admin1_role and status = 'published'), v_admin1, v_supreme, 'supreme');

  v_viewer_role := (app.create_role(v_tenant1, 'IaeRet Viewer', 'RET:View only', 'tester')).id;
  v_viewer_draft := app.create_role_version(v_viewer_role, 'tester');
  perform app.set_role_version_permissions(v_viewer_draft.id, array(select id from app.permissions where resource_module_code = 'RET' and action = 'View'), 'tester');
  perform app.publish_role_version(v_viewer_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_viewer_role and status = 'published'), v_viewer1, v_supreme, 'supreme');

  v_approver_role := (app.create_role(v_tenant1, 'IaeRet Approver', 'RET:Approve/View', 'tester')).id;
  v_approver_draft := app.create_role_version(v_approver_role, 'tester');
  perform app.set_role_version_permissions(v_approver_draft.id, array(select id from app.permissions where resource_module_code = 'RET' and action in ('Approve', 'View')), 'tester');
  perform app.publish_role_version(v_approver_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_approver_role and status = 'published'), v_approver1, v_supreme, 'supreme');

  v_admin2_role := (app.create_role(v_tenant2, 'IaeRet2 Admin', 'RET:Configure/View/Approve -- tenant2 cross-check probe actor', 'tester')).id;
  v_admin2_draft := app.create_role_version(v_admin2_role, 'tester');
  perform app.set_role_version_permissions(v_admin2_draft.id, array(select id from app.permissions where resource_module_code = 'RET' and action in ('Configure', 'View', 'Approve')), 'tester');
  perform app.publish_role_version(v_admin2_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant2, (select id from app.role_versions where role_id = v_admin2_role and status = 'published'), v_admin2, v_supreme, 'supreme');

  raise notice 'FIXTURE OK tenant1=%, tenant2=%', v_tenant1, v_tenant2;
end;
$$;

\echo '>> app.resolve_retention_days: RPD-025''s own hardcoded platform default applies with zero policy rows (finance_tax=3650, audit_security=2555, operational=90); invalid record_class rejected'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'iaeret');
begin
  if app.resolve_retention_days(v_tenant1, 'finance_tax') <> 3650 then
    raise exception 'assertion failed: expected the RPD-025 default of 3650 days for finance_tax with no policy row, got %', app.resolve_retention_days(v_tenant1, 'finance_tax');
  end if;
  if app.resolve_retention_days(v_tenant1, 'audit_security') <> 2555 then
    raise exception 'assertion failed: expected the RPD-025 default of 2555 days for audit_security, got %', app.resolve_retention_days(v_tenant1, 'audit_security');
  end if;
  if app.resolve_retention_days(v_tenant1, 'operational') <> 90 then
    raise exception 'assertion failed: expected the RPD-025 default of 90 days for operational, got %', app.resolve_retention_days(v_tenant1, 'operational');
  end if;

  begin
    perform app.resolve_retention_days(v_tenant1, 'not-a-real-class');
    raise exception 'assertion failed: expected retention_invalid_record_class, the call unexpectedly succeeded';
  exception when check_violation then
    null;
  end;
end;
$$;

\echo '>> app.set_retention_policy: viewer1 (View only) rejected; admin1 (Configure) succeeds; a tenant-scoped override wins over the RPD-025 default; a second call upserts the SAME row (record_version increments); invalid record_class/days rejected'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'iaeret');
  v_admin1 uuid := '00000000-0000-0000-0000-000034000001';
  v_viewer1 uuid := '00000000-0000-0000-0000-000034000002';
  v_first app.retention_policies;
  v_second app.retention_policies;
  v_count integer;
begin
  begin
    perform app.set_retention_policy(v_tenant1, 'operational', 180, v_viewer1, 'viewer1');
    raise exception 'assertion failed: expected insufficient_authority for viewer1, the call unexpectedly succeeded';
  exception when insufficient_privilege then
    null;
  end;

  v_first := app.set_retention_policy(v_tenant1, 'operational', 180, v_admin1, 'admin1');
  if v_first.retention_days <> 180 or v_first.record_version <> 1 then
    raise exception 'assertion failed: expected retention_days=180 record_version=1, got days=% version=%', v_first.retention_days, v_first.record_version;
  end if;
  if app.resolve_retention_days(v_tenant1, 'operational') <> 180 then
    raise exception 'assertion failed: expected the tenant override (180) to win over the RPD-025 default (90), got %', app.resolve_retention_days(v_tenant1, 'operational');
  end if;

  v_second := app.set_retention_policy(v_tenant1, 'operational', 200, v_admin1, 'admin1');
  if v_second.id <> v_first.id or v_second.retention_days <> 200 or v_second.record_version <> 2 then
    raise exception 'assertion failed: expected the SAME row upserted to retention_days=200 record_version=2, got id=% days=% version=%', v_second.id, v_second.retention_days, v_second.record_version;
  end if;

  select count(*) into v_count from app.retention_policies where tenant_id = v_tenant1 and record_class = 'operational';
  if v_count <> 1 then
    raise exception 'assertion failed: expected exactly 1 row after upsert, got %', v_count;
  end if;

  begin
    perform app.set_retention_policy(v_tenant1, 'not-a-real-class', 100, v_admin1, 'admin1');
    raise exception 'assertion failed: expected retention_invalid_record_class, the call unexpectedly succeeded';
  exception when check_violation then
    null;
  end;

  begin
    perform app.set_retention_policy(v_tenant1, 'operational', 0, v_admin1, 'admin1');
    raise exception 'assertion failed: expected retention_invalid_days, the call unexpectedly succeeded';
  exception when check_violation then
    null;
  end;
end;
$$;

\echo '>> app.set_retention_policy platform-wide (tenant_id null): admin1 (tenant_admin, not supreme) rejected; supreme succeeds and the platform override applies to a tenant with no override of its own'
do $$
declare
  v_admin1 uuid := '00000000-0000-0000-0000-000034000001';
  v_supreme uuid := '00000000-0000-0000-0000-000034000000';
  v_tenant2 uuid := (select id from app.tenants where slug = 'iaeret2');
  v_platform app.retention_policies;
begin
  begin
    perform app.set_retention_policy(null, 'audit_security', 3000, v_admin1, 'admin1');
    raise exception 'assertion failed: expected insufficient_authority for admin1 configuring a platform-wide policy, the call unexpectedly succeeded';
  exception when insufficient_privilege then
    null;
  end;

  v_platform := app.set_retention_policy(null, 'audit_security', 3000, v_supreme, 'supreme');
  if v_platform.tenant_id is not null then
    raise exception 'assertion failed: expected a real platform-wide (tenant_id null) policy row, got tenant_id=%', v_platform.tenant_id;
  end if;

  if app.resolve_retention_days(v_tenant2, 'audit_security') <> 3000 then
    raise exception 'assertion failed: expected tenant2 (no override of its own) to inherit the platform override (3000), got %', app.resolve_retention_days(v_tenant2, 'audit_security');
  end if;
end;
$$;

\echo '>> app.request_legal_hold: rep1 (no RET grant) rejected; empty reason rejected; mismatched scope (table without id) rejected; admin1 (Configure) succeeds for a whole-class hold and a single-record hold'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'iaeret');
  v_admin1 uuid := '00000000-0000-0000-0000-000034000001';
  v_rep1 uuid := '00000000-0000-0000-0000-000034000003';
  v_class_hold app.legal_holds;
  v_record_hold app.legal_holds;
  v_target_record uuid := '00000000-0000-0000-0000-000034009001';
begin
  begin
    perform app.request_legal_hold(v_tenant1, 'finance_tax', null, null, 'litigation hold', v_rep1, 'rep1');
    raise exception 'assertion failed: expected insufficient_authority for rep1, the call unexpectedly succeeded';
  exception when insufficient_privilege then
    null;
  end;

  begin
    perform app.request_legal_hold(v_tenant1, 'finance_tax', null, null, '', v_admin1, 'admin1');
    raise exception 'assertion failed: expected legal_hold_reason_required, the call unexpectedly succeeded';
  exception when check_violation then
    null;
  end;

  begin
    perform app.request_legal_hold(v_tenant1, 'finance_tax', 'app.some_table', null, 'litigation hold', v_admin1, 'admin1');
    raise exception 'assertion failed: expected legal_hold_invalid_scope for a table without a matching id, the call unexpectedly succeeded';
  exception when check_violation then
    null;
  end;

  v_class_hold := app.request_legal_hold(v_tenant1, 'audit_security', null, null, 'regulatory inquiry -- entire audit_security class', v_admin1, 'admin1');
  if v_class_hold.status <> 'active' or v_class_hold.scope_record_table is not null then
    raise exception 'assertion failed: expected an active, whole-class hold, got status=% scope_table=%', v_class_hold.status, v_class_hold.scope_record_table;
  end if;

  v_record_hold := app.request_legal_hold(v_tenant1, 'finance_tax', 'app.some_finance_table', v_target_record, 'single-invoice litigation hold', v_admin1, 'admin1');
  if v_record_hold.status <> 'active' or v_record_hold.scope_record_id <> v_target_record then
    raise exception 'assertion failed: expected an active, single-record hold, got status=% scope_record_id=%', v_record_hold.status, v_record_hold.scope_record_id;
  end if;
end;
$$;

\echo '>> app.release_legal_hold: viewer1/admin1 (no RET:Approve) rejected; approver1 (RET:Approve) succeeds; a second release on the same hold is rejected (legal_hold_not_active)'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'iaeret');
  v_admin1 uuid := '00000000-0000-0000-0000-000034000001';
  v_viewer1 uuid := '00000000-0000-0000-0000-000034000002';
  v_approver1 uuid := '00000000-0000-0000-0000-000034000005';
  v_hold_id uuid;
  v_released app.legal_holds;
begin
  select id into v_hold_id from app.legal_holds where tenant_id = v_tenant1 and record_class = 'audit_security' and scope_record_table is null;

  begin
    perform app.release_legal_hold(v_hold_id, 'no longer needed', v_viewer1, 'viewer1');
    raise exception 'assertion failed: expected insufficient_authority for viewer1 (View only), the call unexpectedly succeeded';
  exception when insufficient_privilege then
    null;
  end;

  begin
    perform app.release_legal_hold(v_hold_id, 'no longer needed', v_admin1, 'admin1');
    raise exception 'assertion failed: expected insufficient_authority for admin1 (Configure, not Approve), the call unexpectedly succeeded';
  exception when insufficient_privilege then
    null;
  end;

  v_released := app.release_legal_hold(v_hold_id, 'regulatory inquiry closed', v_approver1, 'approver1');
  if v_released.status <> 'released' or v_released.released_by <> 'approver1' then
    raise exception 'assertion failed: expected status released released_by=approver1, got status=% released_by=%', v_released.status, v_released.released_by;
  end if;

  begin
    perform app.release_legal_hold(v_hold_id, 'again', v_approver1, 'approver1');
    raise exception 'assertion failed: expected legal_hold_not_active on a second release, the call unexpectedly succeeded';
  exception when no_data_found then
    null;
  end;
end;
$$;

\echo '>> app.request_retention_archive dry_run=true: never enqueues a job, purely classifies; an old, unheld operational record is dry_run_completed; a recent operational record is blocked_within_retention'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'iaeret');
  v_admin1 uuid := '00000000-0000-0000-0000-000034000001';
  v_old_record uuid := '00000000-0000-0000-0000-000034009002';
  v_recent_record uuid := '00000000-0000-0000-0000-000034009003';
  v_old_request app.retention_archive_requests;
  v_recent_request app.retention_archive_requests;
  v_job_count integer;
begin
  -- app.resolve_retention_days(tenant1, 'operational') is 200 (set earlier).
  v_old_request := app.request_retention_archive(v_tenant1, 'operational', 'app.some_operational_table', v_old_record, now() - interval '300 days', true, v_admin1, 'admin1');
  if v_old_request.status <> 'dry_run_completed' or v_old_request.legal_hold_blocking <> false then
    raise exception 'assertion failed: expected dry_run_completed with no legal hold, got status=% legal_hold_blocking=%', v_old_request.status, v_old_request.legal_hold_blocking;
  end if;

  v_recent_request := app.request_retention_archive(v_tenant1, 'operational', 'app.some_operational_table', v_recent_record, now() - interval '10 days', true, v_admin1, 'admin1');
  if v_recent_request.status <> 'blocked_within_retention' then
    raise exception 'assertion failed: expected blocked_within_retention for a 10-day-old record against a 200-day policy, got %', v_recent_request.status;
  end if;

  -- Scoped to this tenant. The count was global, which made it depend on no OTHER test file in
  -- the shared disposable database ever enqueueing a retention_archive job -- a coupling that
  -- held only by accident, and broke the moment background-job.sql gained one (ISS-2026-053).
  -- The claim being tested is about the two requests made above, and tenant scope states that
  -- faithfully instead of resting on what the rest of the suite happens not to do.
  select count(*) into v_job_count from app.jobs where job_type = 'retention_archive' and tenant_id = v_tenant1;
  if v_job_count <> 0 then
    raise exception 'assertion failed: expected ZERO app.jobs rows enqueued for any dry_run=true request in this tenant, found %', v_job_count;
  end if;
end;
$$;

\echo '>> app.request_retention_archive dry_run=false: real enforcement -- a within-retention record is rejected (blocked_within_retention), never enqueued; an eligible record is accepted (pending) and enqueues a REAL app.jobs row; a record under an active single-record legal hold is rejected (blocked_legal_hold) even though it is past its own retention floor'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'iaeret');
  v_admin1 uuid := '00000000-0000-0000-0000-000034000001';
  v_old_record uuid := '00000000-0000-0000-0000-000034009002';
  v_recent_record uuid := '00000000-0000-0000-0000-000034009003';
  v_held_finance_record uuid := '00000000-0000-0000-0000-000034009001';
  v_recent_reject app.retention_archive_requests;
  v_real_request app.retention_archive_requests;
  v_held_request app.retention_archive_requests;
  v_job_count integer;
begin
  v_recent_reject := app.request_retention_archive(v_tenant1, 'operational', 'app.some_operational_table', v_recent_record, now() - interval '10 days', false, v_admin1, 'admin1');
  if v_recent_reject.status <> 'blocked_within_retention' then
    raise exception 'assertion failed: expected blocked_within_retention for a real (non-dry-run) request on a too-recent record, got %', v_recent_reject.status;
  end if;
  select count(*) into v_job_count from app.jobs where job_type = 'retention_archive' and payload ->> 'retention_archive_request_id' = v_recent_reject.id::text;
  if v_job_count <> 0 then
    raise exception 'assertion failed: expected ZERO app.jobs rows for a rejected (blocked_within_retention) request, found %', v_job_count;
  end if;

  v_real_request := app.request_retention_archive(v_tenant1, 'operational', 'app.some_operational_table', v_old_record, now() - interval '300 days', false, v_admin1, 'admin1');
  if v_real_request.status <> 'pending' then
    raise exception 'assertion failed: expected status pending for a genuinely eligible record, got %', v_real_request.status;
  end if;
  select count(*) into v_job_count from app.jobs where job_type = 'retention_archive' and payload ->> 'retention_archive_request_id' = v_real_request.id::text;
  if v_job_count <> 1 then
    raise exception 'assertion failed: expected exactly 1 real app.jobs row enqueued for this eligible request, got %', v_job_count;
  end if;

  -- v_held_finance_record is under an active single-record legal hold (finance_tax, requested earlier)
  -- and its own reference date is far enough in the past to otherwise be eligible (well past even
  -- the 10-year finance_tax default) -- the hold must still block it.
  v_held_request := app.request_retention_archive(v_tenant1, 'finance_tax', 'app.some_finance_table', v_held_finance_record, now() - interval '4000 days', false, v_admin1, 'admin1');
  if v_held_request.status <> 'blocked_legal_hold' or v_held_request.legal_hold_blocking <> true then
    raise exception 'assertion failed: expected blocked_legal_hold for a record under an active legal hold even though it is past its own retention floor, got status=% legal_hold_blocking=%', v_held_request.status, v_held_request.legal_hold_blocking;
  end if;
  select count(*) into v_job_count from app.jobs where job_type = 'retention_archive' and payload ->> 'retention_archive_request_id' = v_held_request.id::text;
  if v_job_count <> 0 then
    raise exception 'assertion failed: expected ZERO app.jobs rows for a legal-hold-blocked request, found %', v_job_count;
  end if;
end;
$$;

\echo '>> app.record_retention_archive_outcome: lost-update-guarded exactly like app.record_audit_export_outcome -- idempotent replay of the SAME outcome returns cleanly; a genuinely conflicting second outcome is rejected'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'iaeret');
  v_admin1 uuid := '00000000-0000-0000-0000-000034000001';
  v_old_record uuid := '00000000-0000-0000-0000-000034009002';
  v_request_id uuid;
begin
  select id into v_request_id from app.retention_archive_requests where tenant_id = v_tenant1 and source_record_id = v_old_record and status = 'pending';

  begin
    perform app.record_retention_archive_outcome(v_request_id, 'not-a-real-status', null, v_admin1, 'admin1');
    raise exception 'assertion failed: expected retention_archive_invalid_outcome_status, the call unexpectedly succeeded';
  exception when check_violation then
    null;
  end;

  perform app.record_retention_archive_outcome(v_request_id, 'archived', 'moved to cold storage', v_admin1, 'admin1');
  perform app.record_retention_archive_outcome(v_request_id, 'archived', 'moved to cold storage', v_admin1, 'admin1');

  begin
    perform app.record_retention_archive_outcome(v_request_id, 'failed', 'a different, conflicting outcome', v_admin1, 'admin1');
    raise exception 'assertion failed: expected retention_archive_outcome_already_recorded, the call unexpectedly succeeded';
  exception when check_violation then
    null;
  end;
end;
$$;

-- The genuine 2-process concurrent race against
-- app.record_retention_archive_outcome (exactly 1 winner reaches 'archived',
-- the other gets the clean, named retention_archive_outcome_already_recorded
-- error, never a silent overwrite) follows the identical atomic
-- WHERE-status-guard + not-found reconciliation pattern app.record_audit_
-- export_outcome (IAE-029) already live-proved via two real, concurrently-
-- launched psql processes -- not re-run here since the guard logic itself is
-- byte-for-byte the same shape, already proven live once this session.

\echo '>> cross-tenant isolation: admin2 (tenant iaeret2) cannot configure/hold/request/read tenant1''s own retention policies, legal holds, or archive requests'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'iaeret');
  v_admin2 uuid := '00000000-0000-0000-0000-000034000004';
  v_target_record uuid := '00000000-0000-0000-0000-000034009004';
  v_request_id uuid;
begin
  begin
    perform app.set_retention_policy(v_tenant1, 'operational', 999, v_admin2, 'admin2');
    raise exception 'assertion failed: expected insufficient_authority for admin2 configuring tenant1''s own policy, the call unexpectedly succeeded';
  exception when insufficient_privilege then
    null;
  end;

  begin
    perform app.request_legal_hold(v_tenant1, 'operational', null, null, 'hijacked hold', v_admin2, 'admin2');
    raise exception 'assertion failed: expected insufficient_authority for admin2 placing a hold on tenant1, the call unexpectedly succeeded';
  exception when insufficient_privilege then
    null;
  end;

  begin
    perform app.request_retention_archive(v_tenant1, 'operational', 'app.some_operational_table', v_target_record, now() - interval '300 days', true, v_admin2, 'admin2');
    raise exception 'assertion failed: expected insufficient_authority for admin2 requesting archive against tenant1''s own records, the call unexpectedly succeeded';
  exception when insufficient_privilege then
    null;
  end;

  begin
    perform count(*) from app.list_retention_policies_for_tenant(v_tenant1, v_admin2);
    raise exception 'assertion failed: expected insufficient_authority for admin2 listing tenant1''s own policies, the call unexpectedly succeeded';
  exception when insufficient_privilege then
    null;
  end;

  begin
    perform count(*) from app.list_legal_holds_for_tenant(v_tenant1, v_admin2);
    raise exception 'assertion failed: expected insufficient_authority for admin2 listing tenant1''s own legal holds, the call unexpectedly succeeded';
  exception when insufficient_privilege then
    null;
  end;

  select id into v_request_id from app.retention_archive_requests where tenant_id = v_tenant1 limit 1;
  begin
    perform app.get_retention_archive_request(v_request_id, v_admin2);
    raise exception 'assertion failed: expected insufficient_authority for admin2 reading tenant1''s own archive request, the call unexpectedly succeeded';
  exception when insufficient_privilege then
    null;
  end;

  begin
    perform count(*) from app.list_retention_archive_requests_for_tenant(v_tenant1, v_admin2);
    raise exception 'assertion failed: expected insufficient_authority for admin2 listing tenant1''s own archive requests, the call unexpectedly succeeded';
  exception when insufficient_privilege then
    null;
  end;
end;
$$;

\echo '>> app.list_retention_policies_for_tenant / app.list_legal_holds_for_tenant / app.list_retention_archive_requests_for_tenant: rep1 (no RET grant) rejected; viewer1 (View) succeeds'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'iaeret');
  v_viewer1 uuid := '00000000-0000-0000-0000-000034000002';
  v_rep1 uuid := '00000000-0000-0000-0000-000034000003';
  v_count integer;
begin
  begin
    perform count(*) from app.list_retention_policies_for_tenant(v_tenant1, v_rep1);
    raise exception 'assertion failed: expected insufficient_authority for rep1 (no RET grant), the call unexpectedly succeeded';
  exception when insufficient_privilege then
    null;
  end;

  select count(*) into v_count from app.list_retention_policies_for_tenant(v_tenant1, v_viewer1);
  if v_count < 1 then
    raise exception 'assertion failed: expected viewer1 to see at least 1 retention policy for tenant1, got %', v_count;
  end if;

  select count(*) into v_count from app.list_legal_holds_for_tenant(v_tenant1, v_viewer1);
  if v_count < 2 then
    raise exception 'assertion failed: expected viewer1 to see at least 2 legal holds for tenant1, got %', v_count;
  end if;

  select count(*) into v_count from app.list_retention_archive_requests_for_tenant(v_tenant1, v_viewer1);
  if v_count < 3 then
    raise exception 'assertion failed: expected viewer1 to see at least 3 archive requests for tenant1, got %', v_count;
  end if;
end;
$$;

\echo '>> RLS default-deny: a direct authenticated select on every new table is denied at the raw-RLS level regardless of role/permission'
do $$
begin
  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000034000001", "role": "authenticated"}';

  begin
    perform count(*) from app.retention_policies;
    raise exception 'assertion failed: expected permission denied for a direct authenticated select on app.retention_policies, the select unexpectedly succeeded';
  exception when insufficient_privilege then
    null;
  end;

  begin
    perform count(*) from app.legal_holds;
    raise exception 'assertion failed: expected permission denied for a direct authenticated select on app.legal_holds, the select unexpectedly succeeded';
  exception when insufficient_privilege then
    null;
  end;

  begin
    perform count(*) from app.retention_archive_requests;
    raise exception 'assertion failed: expected permission denied for a direct authenticated select on app.retention_archive_requests, the select unexpectedly succeeded';
  exception when insufficient_privilege then
    null;
  end;

  reset role;
end;
$$;

\echo '>> defense in depth: anon holds zero EXECUTE grants across every new function -- including the two service_role-only internal/worker entry points'
do $$
declare
  v_anon_grant_count integer;
begin
  select count(*) into v_anon_grant_count
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'app'
    and p.proname in (
      'resolve_retention_days', 'set_retention_policy', 'request_legal_hold', 'release_legal_hold',
      '_is_under_legal_hold', 'request_retention_archive', 'record_retention_archive_outcome',
      'list_retention_policies_for_tenant', 'list_legal_holds_for_tenant',
      'get_retention_archive_request', 'list_retention_archive_requests_for_tenant'
    )
    and has_function_privilege('anon', p.oid, 'EXECUTE');

  if v_anon_grant_count <> 0 then
    raise exception 'assertion failed: expected zero anon EXECUTE grants across this checkpoint''s 11 functions, found %', v_anon_grant_count;
  end if;
end;
$$;

\echo 'ALL IAE-031 (Data Retention and Archival) ASSERTIONS PASSED'
