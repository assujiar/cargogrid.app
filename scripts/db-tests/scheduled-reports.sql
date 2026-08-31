-- Real, executable test evidence for IAE-006 (Scheduled Reports, Prompt 334,
-- CG-S14-IAE-006) -- run via `pnpm run db:test` against a real, disposable
-- Postgres database.
--
-- Fixture identifier range: 00000000-0000-0000-0000-000008000001..006.
-- Grep-verified unclaimed against every other *.sql fixture in this
-- directory before use. Uses finance_billing_summary (empty schema, never
-- retired by any fixture) plus a self-registered/self-retired test report
-- type, mirroring the lesson IAE-004's own fixture already applied: never
-- depend on another file's own incidental report-type state.
--
-- Tier C fix pass (Batch 1 IAE-002..006 review): 000008000006 added below
-- (a customer_user-layer portal actor in iaeschedco) plus a tenant_admin
-- grant reused on the existing 000008000005 fixture user, both feeding the
-- new regression blocks this Tier C pass added -- see the two new \echo
-- sections after the original re-trigger/duplicate-delivery block.

\set ON_ERROR_STOP on

\echo '>> setup: one tenant (iaeschedco), a global Supreme Admin, a configurer (REP:Configure), two recipients (tenant members), a second tenant (iaeschedco2) for cross-tenant isolation, and a retired test report type'
do $$
declare
  v_tenant1 uuid;
  v_tenant2 uuid;
  v_configurer_role uuid;
  v_configurer_draft app.role_versions;
begin
  insert into auth.users (id, email) values
    ('00000000-0000-0000-0000-000008000001', 'supreme@iaeschedco.test'),
    ('00000000-0000-0000-0000-000008000002', 'configurer@iaeschedco.test'),
    ('00000000-0000-0000-0000-000008000003', 'recipienta@iaeschedco.test'),
    ('00000000-0000-0000-0000-000008000004', 'recipientb@iaeschedco.test'),
    ('00000000-0000-0000-0000-000008000005', 'member@iaeschedco2.test'),
    ('00000000-0000-0000-0000-000008000006', 'portal@iaeschedco.test');

  perform app.grant_principal_membership('00000000-0000-0000-0000-000008000001', 'supreme_admin', null, null, 'tester');

  perform app.provision_tenant('iaeschedco', 'IAE Scheduled Co', 'idem-iaeschedco', 'tester');
  v_tenant1 := (select id from app.tenants where slug = 'iaeschedco');
  perform app.transition_tenant_status(v_tenant1, 'active', 'setup', 'tester');

  perform app.provision_tenant('iaeschedco2', 'IAE Scheduled Co 2', 'idem-iaeschedco2', 'tester');
  v_tenant2 := (select id from app.tenants where slug = 'iaeschedco2');
  perform app.transition_tenant_status(v_tenant2, 'active', 'setup', 'tester');

  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000008000002', 'configurer@iaeschedco.test', 'Configurer', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'configurer@iaeschedco.test'), 'active', 'onboarded', 'tester');
  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000008000003', 'recipienta@iaeschedco.test', 'Recipient A', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'recipienta@iaeschedco.test'), 'active', 'onboarded', 'tester');
  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000008000004', 'recipientb@iaeschedco.test', 'Recipient B', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'recipientb@iaeschedco.test'), 'active', 'onboarded', 'tester');

  perform app.invite_user(v_tenant2, '00000000-0000-0000-0000-000008000005', 'member@iaeschedco2.test', 'Beta Member', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'member@iaeschedco2.test'), 'active', 'onboarded', 'tester');
  -- Tier C fix regression fixture: this SAME tenant2 member is ALSO granted
  -- tenant_admin support-grant authority -- exactly the ordinary,
  -- already-shipped authority (app.is_support_grant_authority) the Critical
  -- config_version-scoping finding used to publish a rogue cross-tenant
  -- override via the already-shipped, generic Configuration Engine RPCs, no
  -- special privilege needed.
  perform app.grant_principal_membership('00000000-0000-0000-0000-000008000005', 'tenant_admin', v_tenant2, null, 'tester');

  -- Tier C fix regression fixture: a genuine customer_user-layer (portal)
  -- principal in tenant1, with real active tenant membership -- used to
  -- prove app.add_scheduled_report_recipient/app.run_scheduled_report now
  -- both exclude this layer from "internal tenant member" recipient status.
  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000008000006', 'portal@iaeschedco.test', 'Portal Customer', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'portal@iaeschedco.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000008000006', 'customer_user', v_tenant1, 'iae-sched-portal-ref', 'tester');

  v_configurer_role := (app.create_role(v_tenant1, 'Report Scheduler', 'REP:Configure', 'tester')).id;
  v_configurer_draft := app.create_role_version(v_configurer_role, 'tester');
  perform app.set_role_version_permissions(
    v_configurer_draft.id,
    array(select id from app.permissions where resource_module_code = 'REP' and action = 'Configure'),
    'tester'
  );
  perform app.publish_role_version(v_configurer_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_configurer_role and status = 'published'),
    '00000000-0000-0000-0000-000008000002', '00000000-0000-0000-0000-000008000001', 'tester');

  perform app.register_report_type(
    'iae_sched_retired_report', 'IAE Scheduled Retired Report', 'retired for IAE-006 testing only',
    'get_dashboard_lead_aging', '00000000-0000-0000-0000-000008000001', 'tester'
  );
  perform app.retire_report_type('iae_sched_retired_report', '00000000-0000-0000-0000-000008000001', 'tester');
end;
$$;

\echo '>> app.create_scheduled_report: REP:Configure-gated; rejects unknown/retired codes, invalid timezone, dom+dow both set, and unsafe filters; a real daily schedule computes a real next_run_at'
do $$
declare
  v_tenant1 uuid;
  v_row app.scheduled_reports;
begin
  v_tenant1 := (select id from app.tenants where slug = 'iaeschedco');

  begin
    perform app.create_scheduled_report(v_tenant1, 'finance_billing_summary', 'Should be denied', null, 0, 9, null, null, 'Asia/Jakarta', '{}'::jsonb, '00000000-0000-0000-0000-000008000003', 'tester');
    raise exception 'assertion failed: expected insufficient_privilege -- recipient A lacks REP:Configure';
  exception
    when insufficient_privilege then null;
  end;

  begin
    perform app.create_scheduled_report(v_tenant1, 'not_a_real_report', 'x', null, 0, 9, null, null, 'Asia/Jakarta', '{}'::jsonb, '00000000-0000-0000-0000-000008000002', 'tester');
    raise exception 'assertion failed: expected report_type_unknown';
  exception
    when no_data_found then null;
  end;

  begin
    perform app.create_scheduled_report(v_tenant1, 'iae_sched_retired_report', 'x', null, 0, 9, null, null, 'Asia/Jakarta', '{}'::jsonb, '00000000-0000-0000-0000-000008000002', 'tester');
    raise exception 'assertion failed: expected report_type_retired';
  exception
    when check_violation then null;
  end;

  begin
    perform app.create_scheduled_report(v_tenant1, 'finance_billing_summary', 'x', null, 0, 9, null, null, 'Not/A_Real_Zone', '{}'::jsonb, '00000000-0000-0000-0000-000008000002', 'tester');
    raise exception 'assertion failed: expected scheduled_report_invalid_timezone';
  exception
    when check_violation then null;
  end;

  begin
    perform app.create_scheduled_report(v_tenant1, 'finance_billing_summary', 'x', null, 0, 9, 15, 1, 'Asia/Jakarta', '{}'::jsonb, '00000000-0000-0000-0000-000008000002', 'tester');
    raise exception 'assertion failed: expected scheduled_report_invalid_cron for both dom and dow set';
  exception
    when check_violation then null;
  end;

  select * into v_row from app.create_scheduled_report(
    v_tenant1, 'finance_billing_summary', 'Daily Billing Summary', 'a real test schedule',
    30, 9, null, null, 'Asia/Jakarta', '{}'::jsonb, '00000000-0000-0000-0000-000008000002', 'tester'
  );
  if v_row.status <> 'active' or v_row.next_run_at is null then
    raise exception 'assertion failed: expected a real active schedule with a computed next_run_at';
  end if;
end;
$$;

\echo '>> app.add_scheduled_report_recipient: REP:Configure-gated, rejects a non-member, succeeds for a real member'
do $$
declare
  v_tenant1 uuid;
  v_schedule_id uuid;
begin
  v_tenant1 := (select id from app.tenants where slug = 'iaeschedco');
  v_schedule_id := (select id from app.scheduled_reports where tenant_id = v_tenant1 and name = 'Daily Billing Summary');

  begin
    perform app.add_scheduled_report_recipient(v_schedule_id, '00000000-0000-0000-0000-000008000005', '00000000-0000-0000-0000-000008000002', 'tester');
    raise exception 'assertion failed: expected scheduled_report_recipient_not_member -- tenant2''s own member has no membership in tenant1';
  exception
    when check_violation then null;
  end;

  perform app.add_scheduled_report_recipient(v_schedule_id, '00000000-0000-0000-0000-000008000003', '00000000-0000-0000-0000-000008000002', 'tester');
  perform app.add_scheduled_report_recipient(v_schedule_id, '00000000-0000-0000-0000-000008000004', '00000000-0000-0000-0000-000008000002', 'tester');

  if (select count(*) from app.scheduled_report_recipients where scheduled_report_id = v_schedule_id) <> 2 then
    raise exception 'assertion failed: expected exactly 2 recipients';
  end if;
end;
$$;

\echo '>> app.run_scheduled_report: gated, reauthorizes recipients at run time (a revoked recipient is excluded, never a hard failure), delivers a real notification, advances next_run_at, and never double-enqueues the SAME due occurrence'
do $$
declare
  v_tenant1 uuid;
  v_schedule_id uuid;
  v_schedule_before app.scheduled_reports;
  v_schedule_after app.scheduled_reports;
  v_run app.scheduled_report_runs;
  v_run2 app.scheduled_report_runs;
  v_job_count integer;
  v_notification_count integer;
begin
  v_tenant1 := (select id from app.tenants where slug = 'iaeschedco');
  v_schedule_id := (select id from app.scheduled_reports where tenant_id = v_tenant1 and name = 'Daily Billing Summary');
  select * into v_schedule_before from app.scheduled_reports where id = v_schedule_id;

  -- revoke recipient B's own tenant membership BEFORE the run -- must be
  -- excluded live, never only checked at add-time.
  update app.tenant_user_identities set status = 'revoked'
  where tenant_id = v_tenant1 and auth_user_id = '00000000-0000-0000-0000-000008000004';

  begin
    perform app.run_scheduled_report(v_schedule_id, '00000000-0000-0000-0000-000008000003', 'tester');
    raise exception 'assertion failed: expected insufficient_privilege -- recipient A lacks REP:Configure to trigger a run';
  exception
    when insufficient_privilege then null;
  end;

  select * into v_run from app.run_scheduled_report(v_schedule_id, '00000000-0000-0000-0000-000008000002', 'tester');
  if v_run.recipients_total <> 2 or v_run.recipients_reauthorized <> 1 or v_run.recipients_denied <> 1 then
    raise exception 'assertion failed: expected 2 total / 1 reauthorized / 1 denied, got total=% reauth=% denied=%', v_run.recipients_total, v_run.recipients_reauthorized, v_run.recipients_denied;
  end if;
  if v_run.job_id is null then
    raise exception 'assertion failed: expected a real app.jobs row linked via job_id';
  end if;

  select * into v_schedule_after from app.scheduled_reports where id = v_schedule_id;
  -- ISS-2026-314: this assertion used to demand that next_run_at ADVANCE here, and that was
  -- asserting the defect. app.create_scheduled_report computes next_run_at as the next FUTURE
  -- occurrence, so this trigger is early -- and advancing past a future occurrence means that
  -- scheduled delivery never happens. An early trigger borrows the occurrence; it must not
  -- swallow it. last_run_at is still stamped, because the run genuinely did happen.
  if v_schedule_after.next_run_at <> v_schedule_before.next_run_at then
    raise exception 'assertion failed: an EARLY trigger moved next_run_at from % to % -- that silently skips a real scheduled delivery (ISS-2026-314)', v_schedule_before.next_run_at, v_schedule_after.next_run_at;
  end if;
  if v_schedule_after.last_run_at is null then
    raise exception 'assertion failed: expected last_run_at to be stamped even for an early trigger -- the run really did happen';
  end if;


  select count(*) into v_notification_count from app.notifications
  where recipient_auth_user_id = '00000000-0000-0000-0000-000008000003' and notification_type_code = 'scheduled_report_ready';
  if v_notification_count <> 1 then
    raise exception 'assertion failed: expected exactly one real notification queued for the reauthorized recipient, got %', v_notification_count;
  end if;
  select count(*) into v_notification_count from app.notifications
  where recipient_auth_user_id = '00000000-0000-0000-0000-000008000004' and notification_type_code = 'scheduled_report_ready';
  if v_notification_count <> 0 then
    raise exception 'assertion failed: expected zero notifications for the revoked recipient';
  end if;

  -- duplicate-delivery prevention: force next_run_at back to the SAME due
  -- occurrence that was just triggered, then run again -- the underlying
  -- app.jobs row must NOT be duplicated (same idempotency_key).
  update app.scheduled_reports set next_run_at = v_schedule_before.next_run_at where id = v_schedule_id;
  select * into v_run2 from app.run_scheduled_report(v_schedule_id, '00000000-0000-0000-0000-000008000002', 'tester');
  if v_run2.job_id <> v_run.job_id then
    raise exception 'assertion failed: expected the SAME app.jobs row (idempotency key match) for a re-triggered due occurrence, got a different job_id';
  end if;

  select count(*) into v_job_count from app.jobs
  where job_type = 'report_generation' and (payload ->> 'scheduled_report_id')::uuid = v_schedule_id;
  if v_job_count <> 1 then
    raise exception 'assertion failed: expected exactly ONE app.jobs row across both triggers of the same due occurrence, got %', v_job_count;
  end if;

  -- Tier C fix regression (finding 2, spec-compliance): the re-triggered
  -- call for the SAME occurrence must reuse the SAME scheduled_report_runs
  -- row (occurrence-scoped upsert), not create a second run-history row.
  if v_run2.id <> v_run.id then
    raise exception 'assertion failed: expected the SAME scheduled_report_runs row (occurrence-scoped upsert) on a re-trigger of the identical due occurrence, got a different run id (% vs %)', v_run2.id, v_run.id;
  end if;
  select count(*) into v_job_count from app.scheduled_report_runs where scheduled_report_id = v_schedule_id and job_id = v_run.job_id;
  if v_job_count <> 1 then
    raise exception 'assertion failed: expected exactly ONE scheduled_report_runs row across both triggers of the same due occurrence, got %', v_job_count;
  end if;

  -- Tier C fix regression (finding 2, spec-compliance): the re-triggered
  -- call must NOT re-notify the already-notified recipient -- the dedupe key
  -- is now occurrence-scoped, not keyed off the (previously ephemeral)
  -- v_run.id.
  select count(*) into v_notification_count from app.notifications
  where recipient_auth_user_id = '00000000-0000-0000-0000-000008000003' and notification_type_code = 'scheduled_report_ready';
  if v_notification_count <> 1 then
    raise exception 'assertion failed: expected STILL exactly one real notification for the reauthorized recipient after a re-triggered call for the SAME occurrence (no duplicate delivery), got %', v_notification_count;
  end if;

  -- Tier C fix regression (finding 6, cross-prompt-integration): the run is
  -- now linked into the SAME app.report_runs evidence trail IAE-002's
  -- Report Library and IAE-005's mv_report_usage_daily already read --
  -- exactly one row, idempotent on job_id across both triggers.
  select count(*) into v_job_count from app.report_runs where job_id = v_run.job_id and tenant_id = v_tenant1 and report_type_code = 'finance_billing_summary';
  if v_job_count <> 1 then
    raise exception 'assertion failed: expected exactly ONE app.report_runs row linked to this schedule''s own job_id (idempotent across both triggers), got %', v_job_count;
  end if;
end;
$$;

\echo '>> ISS-2026-314: the other half -- an occurrence that HAS arrived still advances next_run_at by exactly one real step, so the schedule keeps moving; only an EARLY trigger leaves it alone'
do $$
declare
  v_schedule_id uuid := (select id from app.scheduled_reports where tenant_id = (select id from app.tenants where slug = 'iaeschedco') and name = 'Daily Billing Summary');
  v_before app.scheduled_reports;
  v_after app.scheduled_reports;
begin
  -- Its own block, deliberately: it triggers a second real run, which would otherwise break the
  -- earlier block's "exactly one notification" count. Forcing next_run_at into the past is the
  -- ONLY difference from the early trigger above -- everything else about the call is identical,
  -- so this isolates the due/not-due decision and nothing else.
  update app.scheduled_reports set next_run_at = date_trunc('minute', now()) - interval '5 minutes' where id = v_schedule_id;
  select * into v_before from app.scheduled_reports where id = v_schedule_id;

  perform app.run_scheduled_report(v_schedule_id, '00000000-0000-0000-0000-000008000002', 'tester');
  select * into v_after from app.scheduled_reports where id = v_schedule_id;

  if v_after.next_run_at <= v_before.next_run_at then
    raise exception 'assertion failed: a DUE occurrence must advance next_run_at forward, got %/% -- otherwise the schedule would never move at all', v_before.next_run_at, v_after.next_run_at;
  end if;
  if v_after.next_run_at <> app.compute_scheduled_report_next_run(
    v_before.cron_minute, v_before.cron_hour, v_before.cron_day_of_month, v_before.cron_day_of_week, v_before.timezone, v_before.next_run_at
  ) then
    raise exception 'assertion failed: a due occurrence must advance by EXACTLY one real step, got %', v_after.next_run_at;
  end if;

  raise notice 'PASS: ISS-2026-314 -- a due occurrence advances by exactly one step, an early trigger advances not at all';
end;
$$;

\echo '>> Tier C fix regression (finding 4, security-rls-tenant): a customer_user-layer (portal) principal is never a valid scheduled-report recipient -- rejected at add-time, and excluded even if present at run-time (defense in depth for pre-existing rows)'
do $$
declare
  v_tenant1 uuid;
  v_schedule_id uuid;
  v_run app.scheduled_report_runs;
  v_notification_count integer;
begin
  v_tenant1 := (select id from app.tenants where slug = 'iaeschedco');
  v_schedule_id := (select id from app.scheduled_reports where tenant_id = v_tenant1 and name = 'Daily Billing Summary');

  begin
    perform app.add_scheduled_report_recipient(v_schedule_id, '00000000-0000-0000-0000-000008000006', '00000000-0000-0000-0000-000008000002', 'tester');
    raise exception 'assertion failed: expected scheduled_report_recipient_not_member -- a customer_user-layer (portal) principal has real active tenant membership but must never be added as an internal-report recipient';
  exception
    when check_violation then null;
  end;

  -- Defense in depth: even if a portal-layer recipient row already exists
  -- (e.g. pre-dating this fix, or a layer change after add-time), the LIVE
  -- reauthorization loop in app.run_scheduled_report must exclude them at
  -- EVERY run, never just at add time -- direct fixture insert, bypassing
  -- the (now correctly rejecting) RPC, mirrors this repository's own
  -- "Direct fixture inserts" precedent for simulating pre-existing state.
  insert into app.scheduled_report_recipients (scheduled_report_id, recipient_auth_user_id, added_by_auth_user_id)
  values (v_schedule_id, '00000000-0000-0000-0000-000008000006', '00000000-0000-0000-0000-000008000002');

  select * into v_run from app.run_scheduled_report(v_schedule_id, '00000000-0000-0000-0000-000008000002', 'tester');
  -- recipients: A (active, real member), B (revoked earlier in this file), portal (customer_user-layer)
  if v_run.recipients_total <> 3 or v_run.recipients_reauthorized <> 1 or v_run.recipients_denied <> 2 then
    raise exception 'assertion failed: expected total=3/reauth=1/denied=2 (B revoked + portal customer_user-layer both denied), got total=% reauth=% denied=%', v_run.recipients_total, v_run.recipients_reauthorized, v_run.recipients_denied;
  end if;

  select count(*) into v_notification_count from app.notifications
  where recipient_auth_user_id = '00000000-0000-0000-0000-000008000006' and notification_type_code = 'scheduled_report_ready';
  if v_notification_count <> 0 then
    raise exception 'assertion failed: expected ZERO notifications ever queued to a customer_user-layer recipient, got %', v_notification_count;
  end if;

  delete from app.scheduled_report_recipients where scheduled_report_id = v_schedule_id and recipient_auth_user_id = '00000000-0000-0000-0000-000008000006';
end;
$$;

\echo '>> Tier C fix regression (Critical, finding 1, security-rls-tenant): app.run_scheduled_report resolves the notification config_version via the tenant-scoped app.resolve_config -- a rogue tenant-scoped override published by an ORDINARY tenant_admin in a completely unrelated tenant (iaeschedco2, using already-shipped, generic Configuration Engine RPCs, no special privilege needed) must NEVER be picked up by iaeschedco''s own schedule'
do $$
declare
  v_tenant1 uuid;
  v_tenant2 uuid;
  v_draft app.config_versions;
  v_schedule_id uuid;
  v_run app.scheduled_report_runs;
  v_notif app.notifications;
begin
  v_tenant1 := (select id from app.tenants where slug = 'iaeschedco');
  v_tenant2 := (select id from app.tenants where slug = 'iaeschedco2');

  select * into v_draft from app.create_config_draft(
    'notification:scheduled_report_ready', v_tenant2, 'tenant', null,
    '00000000-0000-0000-0000-000008000005', 'tester'
  );
  perform app.set_config_items(
    v_draft.id,
    jsonb_build_array(
      jsonb_build_object('key', 'channels', 'value', '["in_app"]'::jsonb),
      jsonb_build_object('key', 'default_locale', 'value', '"en"'::jsonb),
      jsonb_build_object('key', 'templates', 'value', jsonb_build_object('en', jsonb_build_object('subject', 'TIER-C-LEAK-MARKER-TENANT2', 'body', 'this must never reach tenant1')))
    ),
    '00000000-0000-0000-0000-000008000005', 'tester'
  );
  perform app.publish_config_version(v_draft.id, '00000000-0000-0000-0000-000008000005', now(), 'tester');

  v_schedule_id := (select id from app.scheduled_reports where tenant_id = v_tenant1 and name = 'Daily Billing Summary');
  select * into v_run from app.run_scheduled_report(v_schedule_id, '00000000-0000-0000-0000-000008000002', 'tester');

  select * into v_notif from app.notifications
  where recipient_auth_user_id = '00000000-0000-0000-0000-000008000003' and notification_type_code = 'scheduled_report_ready'
  order by created_at desc limit 1;
  if v_notif.subject = 'TIER-C-LEAK-MARKER-TENANT2' then
    raise exception 'assertion failed: tenant1''s own recipient received tenant2''s own rogue, unscoped config_version override -- the Critical config-scoping fix has regressed';
  end if;
  if v_notif.subject <> 'Your scheduled report is ready' then
    raise exception 'assertion failed: expected tenant1''s own recipient to still receive the real, global template subject, got %', v_notif.subject;
  end if;
end;
$$;

\echo '>> Tier C fix regression (finding 3, correctness-concurrency): real, genuinely concurrent OS-process run race for the SAME due occurrence -- exactly one occurrence is ever processed (never a silent double-advance that skips the real next due date, as a live two-session reproduction against the pre-fix function once showed)'

-- ISS-2026-314: force the occurrence genuinely DUE before racing it. Previously this raced a
-- FUTURE occurrence, where the old function advanced unconditionally and the outcome depended on
-- whether the second caller's unlocked pre-read landed before the winner committed -- which is
-- exactly why this assertion failed intermittently and read as a flake. Racing a due occurrence
-- tests the property the block claims to test ("the SAME due occurrence"), and now does so
-- deterministically.
update app.scheduled_reports set next_run_at = date_trunc('minute', now()) - interval '5 minutes'
where tenant_id = (select id from app.tenants where slug = 'iaeschedco') and name = 'Daily Billing Summary';

select id as sched_race_schedule_id, next_run_at as sched_race_before_next_run_at
from app.scheduled_reports
where tenant_id = (select id from app.tenants where slug = 'iaeschedco') and name = 'Daily Billing Summary'
\gset

select current_database() as pg_test_db \gset

\set sched_race_sql_a 'select (app.run_scheduled_report(''' :sched_race_schedule_id ''', ''00000000-0000-0000-0000-000008000002'', ''tester'')).id;'
\set sched_race_sql_b 'select (app.run_scheduled_report(''' :sched_race_schedule_id ''', ''00000000-0000-0000-0000-000008000002'', ''tester'')).id;'

\setenv PG_TEST_DB :pg_test_db
\setenv RACE_SQL_A :sched_race_sql_a
\setenv RACE_SQL_B :sched_race_sql_b
\setenv RACE_OUT_A /tmp/cargogrid-scheduled-report-run-race-a.out
\setenv RACE_OUT_B /tmp/cargogrid-scheduled-report-run-race-b.out

\! bash scripts/db-tests/wms-picking-concurrency-helper.sh

-- psql does not interpolate :variables inside a do $$ ... $$ body (confirmed
-- empirically, matches advanced-tms-wms-picking.sql's own identical
-- disclosure) -- stash the pre-race next_run_at into a session GUC via
-- set_config (a plain, non-do-block statement, where :'var' interpolation
-- does apply), then read it back with current_setting inside the do block.
select set_config('cargogrid.sched_race_before_next_run_at', :'sched_race_before_next_run_at', false);

do $$
declare
  v_schedule_id uuid := (select id from app.scheduled_reports where tenant_id = (select id from app.tenants where slug = 'iaeschedco') and name = 'Daily Billing Summary');
  v_before_next_run_at timestamptz := current_setting('cargogrid.sched_race_before_next_run_at')::timestamptz;
  v_schedule app.scheduled_reports;
  v_run_count_for_occurrence integer;
  v_job_count_for_occurrence integer;
  v_expected_next_run_at timestamptz;
begin
  select * into v_schedule from app.scheduled_reports where id = v_schedule_id;

  select count(*) into v_run_count_for_occurrence from app.scheduled_report_runs
  where scheduled_report_id = v_schedule_id and occurrence_at = v_before_next_run_at;
  if v_run_count_for_occurrence <> 1 then
    raise exception 'CRITICAL: two genuinely concurrent OS psql processes racing to run the SAME due occurrence (%) produced % scheduled_report_runs rows for it, expected exactly 1 -- see the helper''s own printed output above for both processes'' own captured outcome', v_before_next_run_at, v_run_count_for_occurrence;
  end if;

  select count(*) into v_job_count_for_occurrence from app.jobs
  where job_type = 'report_generation'
    and idempotency_key = 'scheduled-report-' || v_schedule_id || '-' || to_char(v_before_next_run_at, 'YYYYMMDDHH24MI');
  if v_job_count_for_occurrence <> 1 then
    raise exception 'CRITICAL: two genuinely concurrent OS psql processes racing to run the SAME due occurrence (%) produced % app.jobs rows for it, expected exactly 1', v_before_next_run_at, v_job_count_for_occurrence;
  end if;

  v_expected_next_run_at := app.compute_scheduled_report_next_run(
    v_schedule.cron_minute, v_schedule.cron_hour, v_schedule.cron_day_of_month, v_schedule.cron_day_of_week, v_schedule.timezone, v_before_next_run_at
  );
  if v_schedule.next_run_at <> v_expected_next_run_at then
    raise exception 'CRITICAL: two genuinely concurrent OS psql processes racing to run the SAME due occurrence (%) advanced next_run_at to % instead of exactly one real step forward (%) -- a silent double-advance would skip a real due occurrence entirely', v_before_next_run_at, v_schedule.next_run_at, v_expected_next_run_at;
  end if;

  raise notice 'PASS: two genuinely concurrent OS psql processes raced to trigger app.run_scheduled_report for the SAME due occurrence (%) -- exactly one scheduled_report_runs row, exactly one app.jobs row, next_run_at advanced by exactly one real step (never silently double-advanced/skipped); see the helper''s own printed output above for both processes'' own captured output', v_before_next_run_at;
end;
$$;

\echo '>> app.set_scheduled_report_status: pause/resume/archive, REP:Configure-gated; a paused schedule may not run'
do $$
declare
  v_tenant1 uuid;
  v_schedule_id uuid;
begin
  v_tenant1 := (select id from app.tenants where slug = 'iaeschedco');
  v_schedule_id := (select id from app.scheduled_reports where tenant_id = v_tenant1 and name = 'Daily Billing Summary');

  perform app.set_scheduled_report_status(v_schedule_id, 'paused', '00000000-0000-0000-0000-000008000002', 'tester');

  begin
    perform app.run_scheduled_report(v_schedule_id, '00000000-0000-0000-0000-000008000002', 'tester');
    raise exception 'assertion failed: expected scheduled_report_not_active for a paused schedule';
  exception
    when check_violation then null;
  end;

  perform app.set_scheduled_report_status(v_schedule_id, 'active', '00000000-0000-0000-0000-000008000002', 'tester');
  if (select status from app.scheduled_reports where id = v_schedule_id) <> 'active' then
    raise exception 'assertion failed: expected resume to restore status=active';
  end if;
end;
$$;

\echo '>> cross-tenant isolation: tenant2''s own actor cannot read/manage tenant1''s own schedule'
do $$
declare
  v_tenant1 uuid;
  v_schedule_id uuid;
begin
  v_tenant1 := (select id from app.tenants where slug = 'iaeschedco');
  v_schedule_id := (select id from app.scheduled_reports where tenant_id = v_tenant1 and name = 'Daily Billing Summary');

  -- Tier C fix (C-05 discipline): tenant2's own actor has ZERO relationship
  -- to tenant1's own schedule, so this now raises the SAME
  -- scheduled_report_not_found a genuinely missing id would produce, never
  -- a tenant-id-disclosing insufficient_authority.
  begin
    perform app.set_scheduled_report_status(v_schedule_id, 'paused', '00000000-0000-0000-0000-000008000005', 'tester');
    raise exception 'assertion failed: expected no_data_found -- a tenant-2 actor with zero relationship to tenant-1 must see the same not_found a missing id would produce, never a disclosing insufficient_authority';
  exception
    when no_data_found then null;
  end;
end;
$$;

\echo '>> schema-privilege defense in depth: anon holds zero EXECUTE on any new IAE-006 function; authenticated has no direct INSERT/UPDATE/DELETE on any of the three new tables'
do $$
declare
  v_bad_grant record;
begin
  for v_bad_grant in
    select routine_name from information_schema.routine_privileges
    where routine_schema = 'app'
      and routine_name in ('create_scheduled_report', 'set_scheduled_report_status', 'add_scheduled_report_recipient', 'remove_scheduled_report_recipient', 'run_scheduled_report')
      and grantee = 'anon'
  loop
    raise exception 'assertion failed: anon must not hold EXECUTE on app.%', v_bad_grant.routine_name;
  end loop;

  for v_bad_grant in
    select privilege_type from information_schema.role_table_grants
    where table_schema = 'app' and table_name in ('scheduled_reports', 'scheduled_report_recipients', 'scheduled_report_runs')
      and grantee = 'authenticated' and privilege_type in ('INSERT', 'UPDATE', 'DELETE')
  loop
    raise exception 'assertion failed: authenticated must not hold direct % on the new scheduled-report tables', v_bad_grant.privilege_type;
  end loop;
end;
$$;

\echo '>> audit trail: create/status-change/recipient-add/run each recorded a real app.audit_logs event'
do $$
declare
  v_count integer;
begin
  select count(*) into v_count from app.audit_logs where resource_type = 'app.scheduled_reports' and action = 'create_scheduled_report';
  if v_count = 0 then raise exception 'assertion failed: expected a create_scheduled_report audit event'; end if;

  select count(*) into v_count from app.audit_logs where resource_type = 'app.scheduled_report_recipients' and action = 'add_scheduled_report_recipient';
  if v_count = 0 then raise exception 'assertion failed: expected an add_scheduled_report_recipient audit event'; end if;

  select count(*) into v_count from app.audit_logs where resource_type = 'app.scheduled_report_runs' and action = 'run_scheduled_report';
  if v_count = 0 then raise exception 'assertion failed: expected a run_scheduled_report audit event'; end if;
end;
$$;

\echo 'ALL IAE-006 (Scheduled Reports) db-test assertions passed.'
