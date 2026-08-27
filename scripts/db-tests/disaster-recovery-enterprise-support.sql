-- Real, executable test evidence for IAE-035 (Disaster Recovery and
-- Enterprise Support, Prompt 363) -- run via `pnpm run db:test` against a
-- real, disposable Postgres database. Scoped to this checkpoint's own
-- additive migration
-- (supabase/migrations/20260808300000_create_intelligence_disaster_recovery_enterprise_support.sql),
-- plus its own real composition with IAE-032's own dedicated-deployment
-- lifecycle, IAE-026's own enterprise SSO connections, IAE-008's own
-- generic integration connections, and the Platform's own API key
-- primitive. Fresh, distinctive tenant fixture (iaedr), fixture id range
-- 00000000-0000-0000-0000-000038xxxxxx.

\set ON_ERROR_STOP on

-- ISS-2026-257: fixed test-only key for app.integration_secrets_encryption_key() --
-- production key provisioning/rotation/custody is a disclosed, out-of-scope
-- infrastructure concern (mirrors app.vendor_financial_encryption_keys own pattern).
select set_config('app.integration_secrets_encryption_key', 'test-only-key-not-for-production', false);

\echo '>> setup: tenant iaedr with admin1 (tenant_admin + SUP:Configure/View + DEPLOY:Configure/Approve/View + INTHUB:Configure), approver1 (SUP:Approve/View), viewer1 (SUP:View only), rep1 (plain org_user, no SUP grants); a second tenant iaedr2 with admin2 (tenant_admin + SUP:Configure/View) for cross-tenant isolation; a platform-wide supreme admin'
do $$
declare
  v_tenant1 uuid;
  v_tenant2 uuid;
  v_supreme uuid := '00000000-0000-0000-0000-000038000000';
  v_admin1 uuid := '00000000-0000-0000-0000-000038000001';
  v_viewer1 uuid := '00000000-0000-0000-0000-000038000002';
  v_rep1 uuid := '00000000-0000-0000-0000-000038000003';
  v_admin2 uuid := '00000000-0000-0000-0000-000038000004';
  v_approver1 uuid := '00000000-0000-0000-0000-000038000005';
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
    (v_supreme, 'supreme@iaedr.test'),
    (v_admin1, 'admin@iaedr.test'),
    (v_viewer1, 'viewer@iaedr.test'),
    (v_rep1, 'rep@iaedr.test'),
    (v_admin2, 'admin@iaedr2.test'),
    (v_approver1, 'approver@iaedr.test');

  perform app.grant_principal_membership(v_supreme, 'supreme_admin', null, null, 'tester');

  perform app.provision_tenant('iaedr', 'IaeDr Co', 'idem-iaedr', 'tester');
  v_tenant1 := (select id from app.tenants where slug = 'iaedr');
  perform app.transition_tenant_status(v_tenant1, 'active', 'setup', 'tester');

  perform app.provision_tenant('iaedr2', 'IaeDr2 Co', 'idem-iaedr2', 'tester');
  v_tenant2 := (select id from app.tenants where slug = 'iaedr2');
  perform app.transition_tenant_status(v_tenant2, 'active', 'setup', 'tester');

  perform app.invite_user(v_tenant1, v_admin1, 'admin@iaedr.test', 'Admin One', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'admin@iaedr.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership(v_admin1, 'tenant_admin', v_tenant1, null, 'tester');

  perform app.invite_user(v_tenant1, v_viewer1, 'viewer@iaedr.test', 'Viewer One', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'viewer@iaedr.test'), 'active', 'onboarded', 'tester');

  perform app.invite_user(v_tenant1, v_rep1, 'rep@iaedr.test', 'Rep One', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'rep@iaedr.test'), 'active', 'onboarded', 'tester');

  perform app.invite_user(v_tenant1, v_approver1, 'approver@iaedr.test', 'Approver One', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'approver@iaedr.test'), 'active', 'onboarded', 'tester');

  perform app.invite_user(v_tenant2, v_admin2, 'admin@iaedr2.test', 'Admin Two', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'admin@iaedr2.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership(v_admin2, 'tenant_admin', v_tenant2, null, 'tester');

  v_admin1_role := (app.create_role(v_tenant1, 'IaeDr Admin', 'SUP:Configure/View + DEPLOY:Configure/Approve/View + INTHUB:Configure -- the latter two needed only to drive IAE-032/IAE-026''s own composition for this checkpoint''s own tests', 'tester')).id;
  v_admin1_draft := app.create_role_version(v_admin1_role, 'tester');
  perform app.set_role_version_permissions(v_admin1_draft.id, array(
    select id from app.permissions
    where (resource_module_code = 'SUP' and action in ('Configure', 'View'))
       or (resource_module_code = 'DEPLOY' and action in ('Configure', 'Approve', 'View'))
       or (resource_module_code = 'INTHUB' and action = 'Configure')
  ), 'tester');
  perform app.publish_role_version(v_admin1_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_admin1_role and status = 'published'), v_admin1, v_supreme, 'supreme');

  v_viewer_role := (app.create_role(v_tenant1, 'IaeDr Viewer', 'SUP:View only', 'tester')).id;
  v_viewer_draft := app.create_role_version(v_viewer_role, 'tester');
  perform app.set_role_version_permissions(v_viewer_draft.id, array(select id from app.permissions where resource_module_code = 'SUP' and action = 'View'), 'tester');
  perform app.publish_role_version(v_viewer_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_viewer_role and status = 'published'), v_viewer1, v_supreme, 'supreme');

  v_approver_role := (app.create_role(v_tenant1, 'IaeDr Approver', 'SUP:Approve/View', 'tester')).id;
  v_approver_draft := app.create_role_version(v_approver_role, 'tester');
  perform app.set_role_version_permissions(v_approver_draft.id, array(select id from app.permissions where resource_module_code = 'SUP' and action in ('Approve', 'View')), 'tester');
  perform app.publish_role_version(v_approver_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_approver_role and status = 'published'), v_approver1, v_supreme, 'supreme');

  v_admin2_role := (app.create_role(v_tenant2, 'IaeDr2 Admin', 'SUP:Configure/View -- tenant2 cross-check probe actor', 'tester')).id;
  v_admin2_draft := app.create_role_version(v_admin2_role, 'tester');
  perform app.set_role_version_permissions(v_admin2_draft.id, array(select id from app.permissions where resource_module_code = 'SUP' and action in ('Configure', 'View')), 'tester');
  perform app.publish_role_version(v_admin2_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant2, (select id from app.role_versions where role_id = v_admin2_role and status = 'published'), v_admin2, v_supreme, 'supreme');

  raise notice 'FIXTURE OK tenant1=%, tenant2=%', v_tenant1, v_tenant2;
end;
$$;

\echo '>> app.record_dr_restore_test: rep1 (no SUP:Configure) rejected; invalid deployment_type/component_scope/status rejected; a passed result with no rpo/rto rejected; a failed result with no failure_reason/recovery_steps/retest_scheduled_at rejected; a failed result with a hollow EMPTY-STRING (not null) failure_reason/recovery_steps also rejected; a passed result with NEGATIVE or NaN rpo/rto rejected; a failed result with a PAST retest_scheduled_at rejected; admin1 (Configure) succeeds for a real shared/database passed test and a real shared/jobs_integrations FAILED test'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'iaedr');
  v_admin1 uuid := '00000000-0000-0000-0000-000038000001';
  v_rep1 uuid := '00000000-0000-0000-0000-000038000003';
  v_passed app.dr_restore_tests;
  v_failed app.dr_restore_tests;
begin
  begin
    perform app.record_dr_restore_test(v_tenant1, 'shared', 'database', 'passed', 30, 60, null, null, null, null, null, v_rep1, 'rep1');
    raise exception 'assertion failed: expected insufficient_authority for rep1, the call unexpectedly succeeded';
  exception when insufficient_privilege then
    null;
  end;

  begin
    perform app.record_dr_restore_test(v_tenant1, 'not-a-real-type', 'database', 'passed', 30, 60, null, null, null, null, null, v_admin1, 'admin1');
    raise exception 'assertion failed: expected dr_test_invalid_deployment_type, the call unexpectedly succeeded';
  exception when check_violation then
    null;
  end;

  begin
    perform app.record_dr_restore_test(v_tenant1, 'shared', 'not-a-real-scope', 'passed', 30, 60, null, null, null, null, null, v_admin1, 'admin1');
    raise exception 'assertion failed: expected dr_test_invalid_component_scope, the call unexpectedly succeeded';
  exception when check_violation then
    null;
  end;

  begin
    perform app.record_dr_restore_test(v_tenant1, 'shared', 'database', 'not-a-real-status', 30, 60, null, null, null, null, null, v_admin1, 'admin1');
    raise exception 'assertion failed: expected dr_test_invalid_status, the call unexpectedly succeeded';
  exception when check_violation then
    null;
  end;

  begin
    perform app.record_dr_restore_test(v_tenant1, 'shared', 'database', 'passed', null, null, null, null, null, null, null, v_admin1, 'admin1');
    raise exception 'assertion failed: expected the passed-evidence CHECK constraint (no rpo/rto), the call unexpectedly succeeded';
  exception when check_violation then
    null;
  end;

  begin
    perform app.record_dr_restore_test(v_tenant1, 'shared', 'jobs_integrations', 'failed', null, null, null, null, null, null, null, v_admin1, 'admin1');
    raise exception 'assertion failed: expected the failed-evidence CHECK constraint (no failure_reason/recovery_steps/retest_scheduled_at), the call unexpectedly succeeded';
  exception when check_violation then
    null;
  end;

  begin
    perform app.record_dr_restore_test(v_tenant1, 'shared', 'jobs_integrations', 'failed', null, null, '', '', now() + interval '3 days', null, null, v_admin1, 'admin1');
    raise exception 'assertion failed: expected dr_test_failure_evidence_required for a hollow EMPTY-STRING (not null) failure_reason/recovery_steps, the call unexpectedly succeeded';
  exception when check_violation then
    null;
  end;

  -- Tier C review fix (correctness/concurrency lens): a passed result must
  -- report a genuine, non-negative, finite RPO/RTO -- neither a negative
  -- value nor Postgres's own numeric NaN (which is NOT NULL and previously
  -- satisfied the passed-evidence CHECK undetected) is real evidence.
  begin
    perform app.record_dr_restore_test(v_tenant1, 'shared', 'database', 'passed', -10, -20, null, null, null, null, null, v_admin1, 'admin1');
    raise exception 'assertion failed: expected the passed-evidence CHECK constraint to reject a NEGATIVE rpo/rto, the call unexpectedly succeeded';
  exception when check_violation then
    null;
  end;

  begin
    perform app.record_dr_restore_test(v_tenant1, 'shared', 'database', 'passed', 'NaN'::numeric, 'NaN'::numeric, null, null, null, null, null, v_admin1, 'admin1');
    raise exception 'assertion failed: expected the passed-evidence CHECK constraint to reject NaN rpo/rto, the call unexpectedly succeeded';
  exception when check_violation then
    null;
  end;

  -- Tier C review fix (correctness/concurrency lens): a failed result's own
  -- retest_scheduled_at must be a genuine, forward-looking commitment, not a
  -- date already in the past.
  begin
    perform app.record_dr_restore_test(v_tenant1, 'shared', 'database', 'failed', null, null, 'genuine failure', 'genuine recovery steps', now() - interval '10 days', null, null, v_admin1, 'admin1');
    raise exception 'assertion failed: expected dr_test_retest_schedule_must_be_future for a retest_scheduled_at already in the past, the call unexpectedly succeeded';
  exception when check_violation then
    null;
  end;

  v_passed := app.record_dr_restore_test(v_tenant1, 'shared', 'database', 'passed', 30, 60, null, null, null, null, null, v_admin1, 'admin1');
  if v_passed.status <> 'passed' or v_passed.observed_rpo_minutes <> 30 or v_passed.observed_rto_minutes <> 60 then
    raise exception 'assertion failed: expected a real passed row with rpo=30 rto=60, got status=% rpo=% rto=%', v_passed.status, v_passed.observed_rpo_minutes, v_passed.observed_rto_minutes;
  end if;

  v_failed := app.record_dr_restore_test(
    v_tenant1, 'shared', 'jobs_integrations', 'failed', null, null,
    'queue replay lost 12 minutes of events', 'restore from the pre-failure snapshot and manually replay the gap', now() + interval '3 days',
    v_admin1, 'admin1', v_admin1, 'admin1'
  );
  if v_failed.status <> 'failed' or v_failed.retest_scheduled_at is null then
    raise exception 'assertion failed: expected a real failed row with a real retest_scheduled_at, got status=% retest=%', v_failed.status, v_failed.retest_scheduled_at;
  end if;
end;
$$;

\echo '>> app.record_dr_restore_test dedicated-deployment composition: a dedicated-scoped test is rejected (dr_test_deployment_mismatch) while tenant1 has no active dedicated deployment; succeeds once IAE-032''s own lifecycle genuinely reaches active; platform-wide (tenant_id null) requires Supreme Admin, and tenant_id null + deployment_type=dedicated is rejected by a real table CHECK constraint'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'iaedr');
  v_admin1 uuid := '00000000-0000-0000-0000-000038000001';
  v_supreme uuid := '00000000-0000-0000-0000-000038000000';
  v_deployment_id uuid;
  v_dedicated_test app.dr_restore_tests;
begin
  begin
    perform app.record_dr_restore_test(v_tenant1, 'dedicated', 'database', 'passed', 15, 30, null, null, null, null, null, v_admin1, 'admin1');
    raise exception 'assertion failed: expected dr_test_deployment_mismatch with no active dedicated deployment, the call unexpectedly succeeded';
  exception when check_violation then
    null;
  end;

  perform app.request_dedicated_deployment_qualification(v_tenant1, 'dedicated instance required for DR isolation testing', 'MSA-2026-006', v_admin1, 'admin1');
  select id into v_deployment_id from app.tenant_deployment_records where tenant_id = v_tenant1;
  -- Approved by supreme (a different actor from admin1, the requester) -- admin1 also
  -- holds DEPLOY:Approve in this fixture, but self-approval is now correctly forbidden
  -- (IAE-032's own self-approval regression fix), so the requester cannot double as approver.
  perform app.approve_dedicated_deployment_qualification(v_deployment_id, v_supreme, 'supreme');
  perform app.set_deployment_provisioning_status(v_deployment_id, 'provisioning', v_admin1, 'admin1');
  perform app.set_deployment_provisioning_status(v_deployment_id, 'active', v_admin1, 'admin1');

  if app.resolve_tenant_deployment_type(v_tenant1) <> 'dedicated' then
    raise exception 'assertion failed: expected tenant1 to now have an active dedicated deployment, got %', app.resolve_tenant_deployment_type(v_tenant1);
  end if;

  v_dedicated_test := app.record_dr_restore_test(v_tenant1, 'dedicated', 'database', 'passed', 15, 30, null, null, null, null, null, v_admin1, 'admin1');
  if v_dedicated_test.deployment_type <> 'dedicated' then
    raise exception 'assertion failed: expected a real dedicated-scoped test now that tenant1 genuinely has one, got %', v_dedicated_test.deployment_type;
  end if;

  begin
    perform app.record_dr_restore_test(null, 'shared', 'secrets', 'passed', 10, 20, null, null, null, null, null, v_admin1, 'admin1');
    raise exception 'assertion failed: expected insufficient_authority for admin1 (not supreme) recording a platform-wide test, the call unexpectedly succeeded';
  exception when insufficient_privilege then
    null;
  end;

  perform app.record_dr_restore_test(null, 'shared', 'secrets', 'passed', 10, 20, null, null, null, null, null, v_supreme, 'supreme');
  perform app.record_dr_restore_test(null, 'shared', 'backup', 'passed', 10, 20, null, null, null, null, null, v_supreme, 'supreme');
  perform app.record_dr_restore_test(null, 'shared', 'observability', 'passed', 10, 20, null, null, null, null, null, v_supreme, 'supreme');

  begin
    perform app.record_dr_restore_test(null, 'dedicated', 'jobs_integrations', 'passed', 10, 20, null, null, null, null, null, v_supreme, 'supreme');
    raise exception 'assertion failed: expected a real dr_restore_tests_scope_check violation for tenant_id null + deployment_type=dedicated, the call unexpectedly succeeded';
  exception when check_violation then
    null;
  end;
end;
$$;

\echo '>> app.resolve_latest_dr_restore_status: tenant1''s own latest test always wins over the platform fallback; secrets/backup/observability fall back to the platform-wide passed tests since tenant1 has none of its own; jobs_integrations still reflects tenant1''s own most recent FAILED test even though a platform-wide passed test does not exist for it'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'iaedr');
begin
  if app.resolve_latest_dr_restore_status(v_tenant1, 'database') <> 'passed' then
    raise exception 'assertion failed: expected tenant1''s own latest database test (dedicated, passed) to win, got %', app.resolve_latest_dr_restore_status(v_tenant1, 'database');
  end if;
  if app.resolve_latest_dr_restore_status(v_tenant1, 'secrets') <> 'passed' then
    raise exception 'assertion failed: expected the platform-wide fallback for secrets, got %', app.resolve_latest_dr_restore_status(v_tenant1, 'secrets');
  end if;
  if app.resolve_latest_dr_restore_status(v_tenant1, 'jobs_integrations') <> 'failed' then
    raise exception 'assertion failed: expected tenant1''s own FAILED jobs_integrations test to win over any fallback, got %', app.resolve_latest_dr_restore_status(v_tenant1, 'jobs_integrations');
  end if;
end;
$$;

\echo '>> app.set_support_entitlement: rep1 (no SUP:Configure) rejected; invalid tier rejected; enterprise_24_7 without a real escalation_contact_email/p1_response_minutes rejected; IAE-037 Tier C fix: enterprise_24_7 without a real contract_reference also rejected (app layer and a raw-SQL CHECK-constraint bypass attempt); admin1 succeeds for standard, then upserts to enterprise_24_7 with a real escalation contact and contract reference (record_version increments)'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'iaedr');
  v_admin1 uuid := '00000000-0000-0000-0000-000038000001';
  v_rep1 uuid := '00000000-0000-0000-0000-000038000003';
  v_first app.support_entitlements;
  v_second app.support_entitlements;
begin
  begin
    perform app.set_support_entitlement(v_tenant1, 'standard', null, null, null, null, v_rep1, 'rep1');
    raise exception 'assertion failed: expected insufficient_authority for rep1, the call unexpectedly succeeded';
  exception when insufficient_privilege then
    null;
  end;

  begin
    perform app.set_support_entitlement(v_tenant1, 'not-a-real-tier', null, null, null, null, v_admin1, 'admin1');
    raise exception 'assertion failed: expected support_entitlement_invalid_tier, the call unexpectedly succeeded';
  exception when check_violation then
    null;
  end;

  begin
    perform app.set_support_entitlement(v_tenant1, 'enterprise_24_7', 'MSA-2026-006', 'NOC Team', null, null, v_admin1, 'admin1');
    raise exception 'assertion failed: expected support_entitlement_24_7_requires_escalation with no email/response minutes, the call unexpectedly succeeded';
  exception when check_violation then
    null;
  end;

  -- IAE-037 Tier C fix, live-reproduced: enterprise_24_7 with a REAL
  -- escalation contact and p1_response_minutes but NO contract_reference
  -- must now also be rejected -- previously an ordinary tenant-side
  -- SUP:Configure actor could self-declare the premium tier with zero
  -- contract evidence.
  begin
    perform app.set_support_entitlement(v_tenant1, 'enterprise_24_7', null, 'NOC Team', 'noc@iaedr-support.test', 15, v_admin1, 'admin1');
    raise exception 'assertion failed: expected support_entitlement_24_7_requires_contract_reference with a null contract_reference, the call unexpectedly succeeded';
  exception when check_violation then
    if sqlerrm !~ 'support_entitlement_24_7_requires_contract_reference' then raise; end if;
  end;
  begin
    perform app.set_support_entitlement(v_tenant1, 'enterprise_24_7', '   ', 'NOC Team', 'noc@iaedr-support.test', 15, v_admin1, 'admin1');
    raise exception 'assertion failed: expected support_entitlement_24_7_requires_contract_reference with a hollow whitespace-only contract_reference, the call unexpectedly succeeded';
  exception when check_violation then
    if sqlerrm !~ 'support_entitlement_24_7_requires_contract_reference' then raise; end if;
  end;
  -- Also enforced structurally, at the table CHECK-constraint level (a raw
  -- SQL bypass attempt, not merely the app-layer guard above).
  begin
    insert into app.support_entitlements (tenant_id, tier, contract_reference, escalation_contact_name, escalation_contact_email, p1_response_minutes, created_by)
    values (v_tenant1, 'enterprise_24_7', null, 'NOC Team', 'noc@iaedr-support.test', 15, 'raw-bypass-attempt')
    on conflict (tenant_id) do nothing;
    raise exception 'assertion failed: expected the support_entitlements_24_7_requires_contract_check CHECK constraint to reject a raw-SQL insert with no contract_reference';
  exception when check_violation then
    null;
  end;

  v_first := app.set_support_entitlement(v_tenant1, 'standard', 'MSA-2026-006', null, null, null, v_admin1, 'admin1');
  if v_first.tier <> 'standard' or v_first.record_version <> 1 then
    raise exception 'assertion failed: expected tier=standard record_version=1, got tier=% version=%', v_first.tier, v_first.record_version;
  end if;

  v_second := app.set_support_entitlement(v_tenant1, 'enterprise_24_7', 'MSA-2026-006', 'NOC Team', 'noc@iaedr-support.test', 15, v_admin1, 'admin1');
  if v_second.id <> v_first.id or v_second.tier <> 'enterprise_24_7' or v_second.record_version <> 2 then
    raise exception 'assertion failed: expected the SAME row upserted to tier=enterprise_24_7 record_version=2, got id=% tier=% version=%', v_second.id, v_second.tier, v_second.record_version;
  end if;
end;
$$;

\echo '>> app.verify_onboarding_checklist_item: rep1 (no SUP:Configure) rejected; invalid item rejected; viewer1 (View only) and admin1 (Configure, not Approve) both rejected for hypercare_plan_acknowledged -- SUP:Approve is a real, separate, higher authority tier; sso/api/integrations_verified are all FALSE before any real connection/key exists'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'iaedr');
  v_admin1 uuid := '00000000-0000-0000-0000-000038000001';
  v_viewer1 uuid := '00000000-0000-0000-0000-000038000002';
  v_rep1 uuid := '00000000-0000-0000-0000-000038000003';
  v_checklist app.enterprise_onboarding_checklists;
begin
  begin
    perform app.verify_onboarding_checklist_item(v_tenant1, 'sso_verified', null, v_rep1, 'rep1');
    raise exception 'assertion failed: expected insufficient_authority for rep1, the call unexpectedly succeeded';
  exception when insufficient_privilege then
    null;
  end;

  begin
    perform app.verify_onboarding_checklist_item(v_tenant1, 'not-a-real-item', null, v_admin1, 'admin1');
    raise exception 'assertion failed: expected onboarding_invalid_item, the call unexpectedly succeeded';
  exception when check_violation then
    null;
  end;

  begin
    perform app.verify_onboarding_checklist_item(v_tenant1, 'hypercare_plan_acknowledged', true, v_viewer1, 'viewer1');
    raise exception 'assertion failed: expected insufficient_authority for viewer1 (View only), the call unexpectedly succeeded';
  exception when insufficient_privilege then
    null;
  end;

  begin
    perform app.verify_onboarding_checklist_item(v_tenant1, 'hypercare_plan_acknowledged', true, v_admin1, 'admin1');
    raise exception 'assertion failed: expected insufficient_authority for admin1 (Configure, not Approve) on the higher-tier hypercare item, the call unexpectedly succeeded';
  exception when insufficient_privilege then
    null;
  end;

  v_checklist := app.verify_onboarding_checklist_item(v_tenant1, 'sso_verified', null, v_admin1, 'admin1');
  if v_checklist.sso_verified <> false or v_checklist.status <> 'in_progress' then
    raise exception 'assertion failed: expected sso_verified=false status=in_progress with no real SSO connection yet, got sso=% status=%', v_checklist.sso_verified, v_checklist.status;
  end if;
end;
$$;

\echo '>> composing real cross-capability signals: a real active enterprise SSO connection (IAE-026), a real active non-SSO integration connection (IAE-008), and a real active API key together flip sso_verified/integrations_verified/api_verified to true; dr_evidence_verified stays FALSE while jobs_integrations'' own latest test is still the earlier FAILED one'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'iaedr');
  v_admin1 uuid := '00000000-0000-0000-0000-000038000001';
  v_checklist app.enterprise_onboarding_checklists;
begin
  perform app.create_integration_connection(v_tenant1, 'enterprise_sso_oidc', 'Okta OIDC', 'production', null, null, null, '{"issuer": "https://iaedr.okta.com"}'::jsonb, 'okta-secret-value', v_admin1, 'admin1');
  v_checklist := app.verify_onboarding_checklist_item(v_tenant1, 'sso_verified', null, v_admin1, 'admin1');
  if v_checklist.sso_verified <> true or v_checklist.sso_verified_at is null then
    raise exception 'assertion failed: expected sso_verified=true with a real active enterprise_sso_oidc connection, got sso=% at=%', v_checklist.sso_verified, v_checklist.sso_verified_at;
  end if;

  perform app.create_integration_connection(v_tenant1, 'email_smtp', 'Transactional Email', 'production', null, null, null, '{}'::jsonb, 'smtp-secret-value', v_admin1, 'admin1');
  v_checklist := app.verify_onboarding_checklist_item(v_tenant1, 'integrations_verified', null, v_admin1, 'admin1');
  if v_checklist.integrations_verified <> true then
    raise exception 'assertion failed: expected integrations_verified=true with a real active non-SSO connection, got %', v_checklist.integrations_verified;
  end if;

  perform app.create_api_key(v_tenant1, 'DR Test Key', '["SUP:View"]'::jsonb, null, null, v_admin1, 'admin1');
  v_checklist := app.verify_onboarding_checklist_item(v_tenant1, 'api_verified', null, v_admin1, 'admin1');
  if v_checklist.api_verified <> true then
    raise exception 'assertion failed: expected api_verified=true with a real active API key, got %', v_checklist.api_verified;
  end if;

  v_checklist := app.verify_onboarding_checklist_item(v_tenant1, 'dr_evidence_verified', null, v_admin1, 'admin1');
  if v_checklist.dr_evidence_verified <> false then
    raise exception 'assertion failed: expected dr_evidence_verified=false while jobs_integrations'' own latest test is still failed, got %', v_checklist.dr_evidence_verified;
  end if;

  v_checklist := app.verify_onboarding_checklist_item(v_tenant1, 'support_entitlement_verified', null, v_admin1, 'admin1');
  if v_checklist.support_entitlement_verified <> true then
    raise exception 'assertion failed: expected support_entitlement_verified=true with a real support entitlement row, got %', v_checklist.support_entitlement_verified;
  end if;
end;
$$;

\echo '>> Prompt 363''s own alternative flow (retest): a NEW passing jobs_integrations test supersedes the earlier failed one; dr_evidence_verified now flips to true; approver1 (SUP:Approve) acknowledges the final human-attested hypercare item, reaching status=ready_for_production; re-running with p_human_acknowledged=false correctly flips it back to in_progress (a real, live recompute, never a one-way ratchet)'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'iaedr');
  v_admin1 uuid := '00000000-0000-0000-0000-000038000001';
  v_approver1 uuid := '00000000-0000-0000-0000-000038000005';
  v_checklist app.enterprise_onboarding_checklists;
begin
  perform app.record_dr_restore_test(v_tenant1, 'shared', 'jobs_integrations', 'passed', 20, 40, null, null, null, null, null, v_admin1, 'admin1');

  v_checklist := app.verify_onboarding_checklist_item(v_tenant1, 'dr_evidence_verified', null, v_admin1, 'admin1');
  if v_checklist.dr_evidence_verified <> true then
    raise exception 'assertion failed: expected dr_evidence_verified=true once the retest superseded the earlier failure, got %', v_checklist.dr_evidence_verified;
  end if;

  v_checklist := app.verify_onboarding_checklist_item(v_tenant1, 'hypercare_plan_acknowledged', true, v_approver1, 'approver1');
  if v_checklist.hypercare_plan_acknowledged <> true or v_checklist.hypercare_plan_acknowledged_by <> 'approver1' then
    raise exception 'assertion failed: expected hypercare_plan_acknowledged=true acknowledged_by=approver1, got ack=% by=%', v_checklist.hypercare_plan_acknowledged, v_checklist.hypercare_plan_acknowledged_by;
  end if;
  if v_checklist.status <> 'ready_for_production' then
    raise exception 'assertion failed: expected status=ready_for_production with all six items true, got %', v_checklist.status;
  end if;

  v_checklist := app.verify_onboarding_checklist_item(v_tenant1, 'hypercare_plan_acknowledged', false, v_approver1, 'approver1');
  if v_checklist.hypercare_plan_acknowledged <> false or v_checklist.status <> 'in_progress' then
    raise exception 'assertion failed: expected a real, live recompute back to hypercare_plan_acknowledged=false status=in_progress, got ack=% status=%', v_checklist.hypercare_plan_acknowledged, v_checklist.status;
  end if;
end;
$$;

\echo '>> Tier C review fix (cross-prompt integration lens): app.resolve_latest_dr_restore_status goes stale no longer -- a fresh, third tenant''s own DEDICATED-scoped passed test stops counting the instant its underlying dedicated deployment is separately decommissioned, correctly falling back to the platform-wide SHARED test instead; the row itself is left unchanged as real historical evidence'
do $$
declare
  v_tenant1 uuid;
  v_supreme uuid := '00000000-0000-0000-0000-000038000000';
  v_admin3 uuid := '00000000-0000-0000-0000-000038000006';
  v_deployment_id uuid;
  v_admin3_role uuid;
  v_admin3_draft app.role_versions;
  v_raw_status text;
begin
  insert into auth.users (id, email) values (v_admin3, 'admin3@iaedr.test');

  perform app.provision_tenant('iaedr3', 'IaeDr3 Co', 'idem-iaedr3', 'tester');
  v_tenant1 := (select id from app.tenants where slug = 'iaedr3');
  perform app.transition_tenant_status(v_tenant1, 'active', 'setup', 'tester');

  perform app.invite_user(v_tenant1, v_admin3, 'admin3@iaedr.test', 'Admin Three', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'admin3@iaedr.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership(v_admin3, 'tenant_admin', v_tenant1, null, 'tester');

  v_admin3_role := (app.create_role(v_tenant1, 'IaeDr3 Admin', 'SUP:Configure/View + DEPLOY:Configure/Approve/View -- staleness-regression probe actor', 'tester')).id;
  v_admin3_draft := app.create_role_version(v_admin3_role, 'tester');
  perform app.set_role_version_permissions(v_admin3_draft.id, array(
    select id from app.permissions
    where (resource_module_code = 'SUP' and action in ('Configure', 'View'))
       or (resource_module_code = 'DEPLOY' and action in ('Configure', 'View', 'Approve'))
  ), 'tester');
  perform app.publish_role_version(v_admin3_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_admin3_role and status = 'published'), v_admin3, v_supreme, 'supreme');

  perform app.request_dedicated_deployment_qualification(v_tenant1, 'dedicated instance for staleness regression', 'MSA-2026-008', v_admin3, 'admin3');
  select id into v_deployment_id from app.tenant_deployment_records where tenant_id = v_tenant1;
  perform app.approve_dedicated_deployment_qualification(v_deployment_id, v_supreme, 'supreme');
  perform app.set_deployment_provisioning_status(v_deployment_id, 'provisioning', v_admin3, 'admin3');
  perform app.set_deployment_provisioning_status(v_deployment_id, 'active', v_admin3, 'admin3');

  perform app.record_dr_restore_test(v_tenant1, 'dedicated', 'database', 'passed', 5, 10, null, null, null, null, null, v_admin3, 'admin3');
  if app.resolve_latest_dr_restore_status(v_tenant1, 'database') <> 'passed' then
    raise exception 'assertion failed: expected passed while the dedicated deployment is genuinely active, got %', app.resolve_latest_dr_restore_status(v_tenant1, 'database');
  end if;

  perform app.record_dr_restore_test(null, 'shared', 'database', 'failed', null, null, 'shared baseline not yet re-verified', 'schedule a real shared restore test', now() + interval '5 days', null, null, v_supreme, 'supreme');

  perform app.set_deployment_provisioning_status(v_deployment_id, 'decommissioned', v_admin3, 'admin3');

  select status into v_raw_status from app.dr_restore_tests where tenant_id = v_tenant1 and component_scope = 'database' order by tested_at desc limit 1;
  if v_raw_status <> 'passed' then
    raise exception 'assertion failed: expected the dedicated-scoped test ROW ITSELF to remain status=passed (real historical evidence, never retroactively falsified), got %', v_raw_status;
  end if;

  if app.resolve_latest_dr_restore_status(v_tenant1, 'database') <> 'failed' then
    raise exception 'assertion failed: expected resolve_latest_dr_restore_status to stop counting the now-stale dedicated-scoped passed test and fall back to the platform-wide shared test (failed) instead, got %', app.resolve_latest_dr_restore_status(v_tenant1, 'database');
  end if;
end;
$$;

\echo '>> IAE-036 Tier C fix (Integrated Verification, cross-capability flow lens): app.get_enterprise_onboarding_checklist is no longer a one-way ratchet -- sso_verified/integrations_verified/dr_evidence_verified are re-derived LIVE on every read from the composed capabilities'' own CURRENT state, never trusted from the stored row alone; revoking an already-verified SSO connection/integration, or decommissioning the dedicated deployment behind a passed DR test, is reflected immediately on the very next read, with zero explicit re-verify call and zero row ever falsified'
do $$
declare
  v_tenant1 uuid;
  v_supreme uuid := '00000000-0000-0000-0000-000038000000';
  v_admin4 uuid := '00000000-0000-0000-0000-000038000007';
  v_admin4_role uuid;
  v_admin4_draft app.role_versions;
  v_sso_connection_id uuid;
  v_other_connection_id uuid;
  v_deployment_id uuid;
  v_checklist app.enterprise_onboarding_checklists;
  v_raw_sso_verified boolean;
begin
  insert into auth.users (id, email) values (v_admin4, 'admin4@iaedr.test');

  perform app.provision_tenant('iaedr4', 'IaeDr4 Co', 'idem-iaedr4', 'tester');
  v_tenant1 := (select id from app.tenants where slug = 'iaedr4');
  perform app.transition_tenant_status(v_tenant1, 'active', 'setup', 'tester');

  perform app.invite_user(v_tenant1, v_admin4, 'admin4@iaedr.test', 'Admin Four', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'admin4@iaedr.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership(v_admin4, 'tenant_admin', v_tenant1, null, 'tester');

  v_admin4_role := (app.create_role(v_tenant1, 'IaeDr4 Admin', 'SUP:Configure/View + DEPLOY:Configure/View/Approve + INTHUB:Configure/View -- onboarding-checklist staleness regression probe actor', 'tester')).id;
  v_admin4_draft := app.create_role_version(v_admin4_role, 'tester');
  perform app.set_role_version_permissions(v_admin4_draft.id, array(
    select id from app.permissions
    where (resource_module_code = 'SUP' and action in ('Configure', 'View'))
       or (resource_module_code = 'DEPLOY' and action in ('Configure', 'View', 'Approve'))
       or (resource_module_code = 'INTHUB' and action in ('Configure', 'View'))
  ), 'tester');
  perform app.publish_role_version(v_admin4_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_admin4_role and status = 'published'), v_admin4, v_supreme, 'supreme');

  -- Build a real, active dedicated deployment + a passed dedicated-scoped DR
  -- test so dr_evidence_verified starts genuinely true (composing IAE-032).
  perform app.request_dedicated_deployment_qualification(v_tenant1, 'dedicated instance for onboarding-checklist staleness regression', 'MSA-2026-009', v_admin4, 'admin4');
  select id into v_deployment_id from app.tenant_deployment_records where tenant_id = v_tenant1;
  perform app.approve_dedicated_deployment_qualification(v_deployment_id, v_supreme, 'supreme');
  perform app.set_deployment_provisioning_status(v_deployment_id, 'provisioning', v_admin4, 'admin4');
  perform app.set_deployment_provisioning_status(v_deployment_id, 'active', v_admin4, 'admin4');

  perform app.record_dr_restore_test(v_tenant1, 'dedicated', 'database', 'passed', 5, 10, null, null, null, null, null, v_admin4, 'admin4');
  perform app.record_dr_restore_test(v_tenant1, 'dedicated', 'secrets', 'passed', 5, 10, null, null, null, null, null, v_admin4, 'admin4');
  perform app.record_dr_restore_test(v_tenant1, 'dedicated', 'backup', 'passed', 5, 10, null, null, null, null, null, v_admin4, 'admin4');
  perform app.record_dr_restore_test(v_tenant1, 'dedicated', 'observability', 'passed', 5, 10, null, null, null, null, null, v_admin4, 'admin4');
  perform app.record_dr_restore_test(v_tenant1, 'dedicated', 'jobs_integrations', 'passed', 5, 10, null, null, null, null, null, v_admin4, 'admin4');

  -- Build a real, active SSO connection (composing IAE-008) and verify it.
  v_sso_connection_id := (app.create_integration_connection(
    v_tenant1, 'enterprise_sso_oidc', 'Iaedr4 Okta OIDC', 'production', 'Platform Team', 'platform@iaedr4.test',
    null, '{}'::jsonb, 'client-secret-value', v_admin4, 'admin4'
  )).id;
  perform app.set_integration_connection_status(v_sso_connection_id, 'active', null, v_admin4, 'admin4');
  v_checklist := app.verify_onboarding_checklist_item(v_tenant1, 'sso_verified', null, v_admin4, 'admin4');
  if v_checklist.sso_verified <> true then
    raise exception 'assertion failed: expected sso_verified=true once the SSO connection is genuinely active, got %', v_checklist.sso_verified;
  end if;

  -- Build a real, active non-SSO integration connection and verify it.
  v_other_connection_id := (app.create_integration_connection(
    v_tenant1, 'email_smtp', 'Iaedr4 Notification Email', 'production', 'Platform Team', 'platform@iaedr4.test',
    null, '{}'::jsonb, 'smtp-secret-value', v_admin4, 'admin4'
  )).id;
  perform app.set_integration_connection_status(v_other_connection_id, 'active', null, v_admin4, 'admin4');
  v_checklist := app.verify_onboarding_checklist_item(v_tenant1, 'integrations_verified', null, v_admin4, 'admin4');
  if v_checklist.integrations_verified <> true then
    raise exception 'assertion failed: expected integrations_verified=true once a non-SSO integration connection is genuinely active, got %', v_checklist.integrations_verified;
  end if;

  v_checklist := app.verify_onboarding_checklist_item(v_tenant1, 'dr_evidence_verified', null, v_admin4, 'admin4');
  if v_checklist.dr_evidence_verified <> true then
    raise exception 'assertion failed: expected dr_evidence_verified=true with all five categories genuinely passed on the active dedicated deployment, got %', v_checklist.dr_evidence_verified;
  end if;

  -- Confirm the read path agrees with the write path right after a genuine
  -- explicit verify: all three items true via the READ function, not just
  -- the WRITE function's own return value.
  v_checklist := app.get_enterprise_onboarding_checklist(v_tenant1, v_admin4);
  if not (v_checklist.sso_verified and v_checklist.integrations_verified and v_checklist.dr_evidence_verified) then
    raise exception 'assertion failed: expected get_enterprise_onboarding_checklist to report sso_verified=true, integrations_verified=true, dr_evidence_verified=true immediately after a genuine verify, got sso=% integrations=% dr=%', v_checklist.sso_verified, v_checklist.integrations_verified, v_checklist.dr_evidence_verified;
  end if;

  -- Now corrupt all three underlying composed states WITHOUT ever calling
  -- verify_onboarding_checklist_item again.
  perform app.set_integration_connection_status(v_sso_connection_id, 'disabled', 'staleness regression probe', v_admin4, 'admin4');
  perform app.set_integration_connection_status(v_other_connection_id, 'disabled', 'staleness regression probe', v_admin4, 'admin4');
  perform app.set_deployment_provisioning_status(v_deployment_id, 'decommissioned', v_admin4, 'admin4');

  -- The STORED row itself must remain exactly what it was -- real
  -- historical evidence of a real, once-true confirmation, never
  -- retroactively falsified.
  select sso_verified into v_raw_sso_verified from app.enterprise_onboarding_checklists where tenant_id = v_tenant1;
  if v_raw_sso_verified <> true then
    raise exception 'assertion failed: expected the STORED sso_verified column to remain true (historical evidence, never retroactively falsified), got %', v_raw_sso_verified;
  end if;

  -- But the READ path must now reflect live reality: zero active SSO
  -- connection, zero active non-SSO integration, and the dedicated DR
  -- evidence no longer eligible since its own deployment is decommissioned.
  v_checklist := app.get_enterprise_onboarding_checklist(v_tenant1, v_admin4);
  if v_checklist.sso_verified <> false then
    raise exception 'assertion failed: expected get_enterprise_onboarding_checklist to report sso_verified=false live after the SSO connection was disabled with zero explicit re-verify call (one-way-ratchet bug), got %', v_checklist.sso_verified;
  end if;
  if v_checklist.integrations_verified <> false then
    raise exception 'assertion failed: expected get_enterprise_onboarding_checklist to report integrations_verified=false live after the integration connection was disabled with zero explicit re-verify call, got %', v_checklist.integrations_verified;
  end if;
  if v_checklist.dr_evidence_verified <> false then
    raise exception 'assertion failed: expected get_enterprise_onboarding_checklist to report dr_evidence_verified=false live once the dedicated deployment behind the passed evidence was decommissioned, got %', v_checklist.dr_evidence_verified;
  end if;
  if v_checklist.status <> 'in_progress' then
    raise exception 'assertion failed: expected status=in_progress once the read path correctly reflects live reality, got %', v_checklist.status;
  end if;
end;
$$;

\echo '>> cross-tenant isolation: admin2 (tenant iaedr2, its own SUP:Configure/View) cannot record a DR test/set the entitlement/verify a checklist item/read tenant1''s own DR tests/entitlement/checklist'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'iaedr');
  v_admin2 uuid := '00000000-0000-0000-0000-000038000004';
begin
  begin
    perform app.record_dr_restore_test(v_tenant1, 'shared', 'database', 'passed', 5, 5, null, null, null, null, null, v_admin2, 'admin2');
    raise exception 'assertion failed: expected insufficient_authority for admin2 recording a DR test for tenant1, the call unexpectedly succeeded';
  exception when insufficient_privilege then
    null;
  end;

  begin
    perform app.set_support_entitlement(v_tenant1, 'standard', null, null, null, null, v_admin2, 'admin2');
    raise exception 'assertion failed: expected insufficient_authority for admin2 setting tenant1''s own support entitlement, the call unexpectedly succeeded';
  exception when insufficient_privilege then
    null;
  end;

  begin
    perform app.verify_onboarding_checklist_item(v_tenant1, 'sso_verified', null, v_admin2, 'admin2');
    raise exception 'assertion failed: expected insufficient_authority for admin2 verifying tenant1''s own checklist item, the call unexpectedly succeeded';
  exception when insufficient_privilege then
    null;
  end;

  begin
    perform count(*) from app.list_dr_restore_tests_for_tenant(v_tenant1, v_admin2);
    raise exception 'assertion failed: expected insufficient_authority for admin2 listing tenant1''s own DR tests, the call unexpectedly succeeded';
  exception when insufficient_privilege then
    null;
  end;

  begin
    perform app.get_support_entitlement(v_tenant1, v_admin2);
    raise exception 'assertion failed: expected insufficient_authority for admin2 reading tenant1''s own support entitlement, the call unexpectedly succeeded';
  exception when insufficient_privilege then
    null;
  end;

  begin
    perform app.get_enterprise_onboarding_checklist(v_tenant1, v_admin2);
    raise exception 'assertion failed: expected insufficient_authority for admin2 reading tenant1''s own onboarding checklist, the call unexpectedly succeeded';
  exception when insufficient_privilege then
    null;
  end;
end;
$$;

\echo '>> app.list_dr_restore_tests_for_tenant / app.get_support_entitlement / app.get_enterprise_onboarding_checklist: rep1 (no SUP:View) rejected; viewer1 (View) succeeds'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'iaedr');
  v_viewer1 uuid := '00000000-0000-0000-0000-000038000002';
  v_rep1 uuid := '00000000-0000-0000-0000-000038000003';
  v_count integer;
  v_entitlement app.support_entitlements;
  v_checklist app.enterprise_onboarding_checklists;
begin
  begin
    perform count(*) from app.list_dr_restore_tests_for_tenant(v_tenant1, v_rep1);
    raise exception 'assertion failed: expected insufficient_authority for rep1 (no SUP:View), the call unexpectedly succeeded';
  exception when insufficient_privilege then
    null;
  end;

  select count(*) into v_count from app.list_dr_restore_tests_for_tenant(v_tenant1, v_viewer1);
  if v_count < 4 then
    raise exception 'assertion failed: expected viewer1 to see at least 4 DR restore tests for tenant1, got %', v_count;
  end if;

  v_entitlement := app.get_support_entitlement(v_tenant1, v_viewer1);
  if v_entitlement.tier <> 'enterprise_24_7' then
    raise exception 'assertion failed: expected viewer1 to see the real enterprise_24_7 entitlement, got %', v_entitlement.tier;
  end if;

  v_checklist := app.get_enterprise_onboarding_checklist(v_tenant1, v_viewer1);
  if v_checklist.sso_verified <> true then
    raise exception 'assertion failed: expected viewer1 to see the real, already-verified sso_verified=true, got %', v_checklist.sso_verified;
  end if;
end;
$$;

\echo '>> RLS default-deny: a direct authenticated select on every new table is denied at the raw-RLS level regardless of role/permission'
do $$
begin
  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000038000001", "role": "authenticated"}';

  begin
    perform count(*) from app.dr_restore_tests;
    raise exception 'assertion failed: expected permission denied for a direct authenticated select on app.dr_restore_tests, the select unexpectedly succeeded';
  exception when insufficient_privilege then
    null;
  end;

  begin
    perform count(*) from app.support_entitlements;
    raise exception 'assertion failed: expected permission denied for a direct authenticated select on app.support_entitlements, the select unexpectedly succeeded';
  exception when insufficient_privilege then
    null;
  end;

  begin
    perform count(*) from app.enterprise_onboarding_checklists;
    raise exception 'assertion failed: expected permission denied for a direct authenticated select on app.enterprise_onboarding_checklists, the select unexpectedly succeeded';
  exception when insufficient_privilege then
    null;
  end;

  reset role;
end;
$$;

\echo '>> defense in depth: anon holds zero EXECUTE grants across every new function; authenticated holds zero EXECUTE on app.resolve_latest_dr_restore_status specifically (service_role-only) while service_role does'
do $$
declare
  v_anon_grant_count integer;
  v_authenticated_on_resolve boolean;
  v_service_role_on_resolve boolean;
begin
  select count(*) into v_anon_grant_count
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'app'
    and p.proname in (
      'record_dr_restore_test', 'resolve_latest_dr_restore_status', 'set_support_entitlement',
      'verify_onboarding_checklist_item', 'list_dr_restore_tests_for_tenant',
      'get_support_entitlement', 'get_enterprise_onboarding_checklist',
      'record_migration_rehearsal_test'
    )
    and has_function_privilege('anon', p.oid, 'EXECUTE');

  if v_anon_grant_count <> 0 then
    raise exception 'assertion failed: expected zero anon EXECUTE grants across this checkpoint''s 8 functions (ISS-2026-272 added record_migration_rehearsal_test), found %', v_anon_grant_count;
  end if;

  select has_function_privilege('authenticated', 'app.resolve_latest_dr_restore_status(uuid, text)', 'EXECUTE') into v_authenticated_on_resolve;
  if v_authenticated_on_resolve then
    raise exception 'assertion failed: expected authenticated to hold ZERO EXECUTE on app.resolve_latest_dr_restore_status (bare p_tenant_id, no actor param -- service_role-only), found a grant';
  end if;

  select has_function_privilege('service_role', 'app.resolve_latest_dr_restore_status(uuid, text)', 'EXECUTE') into v_service_role_on_resolve;
  if not v_service_role_on_resolve then
    raise exception 'assertion failed: expected service_role to hold EXECUTE on app.resolve_latest_dr_restore_status, found none';
  end if;
end;
$$;

-- ISS-2026-272 (Step 16 historical-issue-backlog remediation): app.migration_rehearsal_
-- tests/app.record_migration_rehearsal_test, and the 7th checklist item
-- (migration_rehearsal_verified) on app.verify_onboarding_checklist_item -- mirroring
-- app.dr_restore_tests/app.record_dr_restore_test's own honesty discipline. Deliberately
-- NOT wired into the status='ready_for_production' composite gate (the business rule is
-- "where contracted" and no contract-flag exists yet) -- proved directly below, not
-- merely asserted in a comment.
\echo '>> ISS-2026-272 regression: app.record_migration_rehearsal_test/app.verify_onboarding_checklist_item(''migration_rehearsal_verified'', ...) -- SUP:Configure-gated, requires >=2 passed rehearsals, real failure-evidence discipline, and does NOT participate in the status=ready_for_production gate'
do $$
declare
  v_tenant1 uuid;
  v_admin1 uuid := '00000000-0000-0000-0000-000038000001';
  v_rep1 uuid := '00000000-0000-0000-0000-000038000003';
  v_checklist_before app.enterprise_onboarding_checklists;
  v_checklist app.enterprise_onboarding_checklists;
  v_rehearsal app.migration_rehearsal_tests;
begin
  v_tenant1 := (select id from app.tenants where slug = 'iaedr');

  begin
    perform app.record_migration_rehearsal_test(v_tenant1, 'passed', 'reference data + employee import', null, null, null, v_admin1, 'admin1', v_rep1, 'rep1');
    raise exception 'assertion failed: expected rep1 (no SUP:Configure) to be denied';
  exception
    when others then
      if sqlerrm not like 'insufficient_authority%' then raise; end if;
  end;

  begin
    perform app.record_migration_rehearsal_test(v_tenant1, 'invalid_status', 'x', null, null, null, v_admin1, 'admin1', v_admin1, 'admin1');
    raise exception 'assertion failed: expected an invalid status to be rejected';
  exception
    when others then
      if sqlerrm not like 'migration_rehearsal_invalid_status%' then raise; end if;
  end;

  begin
    perform app.record_migration_rehearsal_test(v_tenant1, 'passed', '   ', null, null, null, v_admin1, 'admin1', v_admin1, 'admin1');
    raise exception 'assertion failed: expected a blank scope_summary to be rejected';
  exception
    when others then
      if sqlerrm not like 'migration_rehearsal_scope_summary_required%' then raise; end if;
  end;

  begin
    perform app.record_migration_rehearsal_test(v_tenant1, 'failed', 'reference data', null, null, null, v_admin1, 'admin1', v_admin1, 'admin1');
    raise exception 'assertion failed: expected a failed result with no failure_reason/recovery_steps/retest_scheduled_at to be rejected';
  exception
    when others then
      if sqlerrm not like 'migration_rehearsal_failure_evidence_required%' then raise; end if;
  end;

  begin
    perform app.record_migration_rehearsal_test(v_tenant1, 'failed', 'reference data', 'collision on seeded currency codes', 'use app.import_reference_currency instead', now() - interval '1 day', v_admin1, 'admin1', v_admin1, 'admin1');
    raise exception 'assertion failed: expected a past retest_scheduled_at to be rejected';
  exception
    when others then
      if sqlerrm not like 'migration_rehearsal_retest_schedule_must_be_future%' then raise; end if;
  end;

  -- A real, well-formed failed rehearsal is accepted.
  select * into v_rehearsal from app.record_migration_rehearsal_test(v_tenant1, 'failed', 'financial opening balances', 'no bulk GL-journal path exists', 'wait for the bulk import mechanism', now() + interval '30 days', v_admin1, 'admin1', v_admin1, 'admin1');
  if v_rehearsal.status <> 'failed' then
    raise exception 'assertion failed: expected the well-formed failed rehearsal to be accepted, got status=%', v_rehearsal.status;
  end if;

  -- Capture the checklist's current status BEFORE touching migration_rehearsal_verified
  -- at all, to prove this item never changes it (the whole point of this fix).
  select * into v_checklist_before from app.enterprise_onboarding_checklists where tenant_id = v_tenant1;

  -- Exactly 1 passed rehearsal: not yet >= 2, so the item stays false.
  perform app.record_migration_rehearsal_test(v_tenant1, 'passed', 'reference data + employee import', null, null, null, v_admin1, 'admin1', v_admin1, 'admin1');
  v_checklist := app.verify_onboarding_checklist_item(v_tenant1, 'migration_rehearsal_verified', null, v_admin1, 'admin1');
  if v_checklist.migration_rehearsal_verified <> false then
    raise exception 'assertion failed: expected migration_rehearsal_verified=false with only 1 passed rehearsal, got %', v_checklist.migration_rehearsal_verified;
  end if;
  if v_checklist.status <> v_checklist_before.status then
    raise exception 'assertion failed: expected status to be completely unaffected by migration_rehearsal_verified (still false here), got % (was %)', v_checklist.status, v_checklist_before.status;
  end if;

  -- A 2nd passed rehearsal flips the item live, on the very next verify call -- no
  -- caller-asserted rubber stamp, a real recompute from app.migration_rehearsal_tests.
  perform app.record_migration_rehearsal_test(v_tenant1, 'passed', 'master data', null, null, null, v_admin1, 'admin1', v_admin1, 'admin1');
  v_checklist := app.verify_onboarding_checklist_item(v_tenant1, 'migration_rehearsal_verified', null, v_admin1, 'admin1');
  if v_checklist.migration_rehearsal_verified <> true or v_checklist.migration_rehearsal_verified_at is null then
    raise exception 'assertion failed: expected migration_rehearsal_verified=true (with a real timestamp) after 2 passed rehearsals, got %/%', v_checklist.migration_rehearsal_verified, v_checklist.migration_rehearsal_verified_at;
  end if;

  -- The whole point of this fix, proved directly rather than merely asserted in a
  -- comment: flipping this item from false to true did NOT change status at all --
  -- it is not part of the status='ready_for_production' composite gate.
  if v_checklist.status <> v_checklist_before.status then
    raise exception 'assertion failed: expected status to remain completely unaffected by migration_rehearsal_verified flipping to true (this item must never gate readiness), got % (was %)', v_checklist.status, v_checklist_before.status;
  end if;

  -- A real, persisted audit event records each genuinely-recorded rehearsal.
  if not exists (
    select 1 from app.audit_logs
    where action = 'record_migration_rehearsal_test' and resource_type = 'app.migration_rehearsal_tests'
      and tenant_id = v_tenant1
  ) then
    raise exception 'assertion failed: expected a real audit_logs event for a recorded migration rehearsal';
  end if;

  raise notice 'ISS-2026-272 proof: app.record_migration_rehearsal_test is SUP:Configure-gated with real failure-evidence discipline mirroring app.record_dr_restore_test, migration_rehearsal_verified correctly requires >=2 passed rehearsals and recomputes live, and -- the whole point of this fix -- flipping it never changes status=ready_for_production, proving it is deliberately not part of that composite gate';
end;
$$;

\echo '>> ISS-2026-272 regression evidence complete'

\echo '>> ISS-2026-260 regression: app.record_dr_restore_test''s new, optional, trailing p_dr_scenario parameter (default null) records one of Prompt 384''s own 4 named DR scenarios alongside (never instead of) the existing component_scope; an invalid scenario value is rejected with a distinct named exception; every pre-existing 13-argument call site keeps working completely unchanged'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'iaedr');
  v_admin1 uuid := '00000000-0000-0000-0000-000038000001';
  v_test app.dr_restore_tests;
  v_legacy app.dr_restore_tests;
  v_raised boolean := false;
begin
  -- A pre-existing, 13-argument call site (no p_dr_scenario at all) keeps working
  -- completely unchanged -- the new parameter defaults to null, never breaking an
  -- existing caller.
  v_legacy := app.record_dr_restore_test(v_tenant1, 'shared', 'database', 'passed', 12, 24, null, null, null, null, null, v_admin1, 'admin1');
  if v_legacy.dr_scenario is not null then
    raise exception 'assertion failed: expected a legacy 13-argument call to leave dr_scenario null, got %', v_legacy.dr_scenario;
  end if;

  -- A scenario this repository's own component taxonomy has no natural slot for
  -- (security_incident) can now be recorded, alongside a real component_scope.
  v_test := app.record_dr_restore_test(v_tenant1, 'shared', 'secrets', 'passed', 5, 10, null, null, null, null, null, v_admin1, 'admin1', 'security_incident');
  if v_test.dr_scenario <> 'security_incident' or v_test.component_scope <> 'secrets' then
    raise exception 'assertion failed: expected dr_scenario=security_incident alongside component_scope=secrets, got dr_scenario=%, component_scope=%', v_test.dr_scenario, v_test.component_scope;
  end if;

  -- Each of the other 2 previously-unrepresentable scenarios is also accepted.
  perform app.record_dr_restore_test(v_tenant1, 'shared', 'observability', 'passed', 5, 10, null, null, null, null, null, v_admin1, 'admin1', 'provider_failure');
  perform app.record_dr_restore_test(v_tenant1, 'shared', 'jobs_integrations', 'passed', 5, 10, null, null, null, null, null, v_admin1, 'admin1', 'major_outage');

  -- An invalid scenario value is rejected with a distinct named exception, never
  -- silently accepted or coerced.
  begin
    perform app.record_dr_restore_test(v_tenant1, 'shared', 'database', 'passed', 5, 10, null, null, null, null, null, v_admin1, 'admin1', 'not-a-real-scenario');
    raise exception 'assertion failed: expected dr_test_invalid_dr_scenario to reject an unrecognized scenario value, but the call succeeded';
  exception
    when others then
      if sqlerrm !~ '^dr_test_invalid_dr_scenario' then
        raise;
      end if;
      v_raised := true;
  end;
  if not v_raised then
    raise exception 'assertion failed: expected dr_test_invalid_dr_scenario, got none';
  end if;

  -- The underlying table-level CHECK constraint itself (independent of the RPC's own
  -- explicit check) also rejects an invalid scenario value, defense in depth.
  v_raised := false;
  begin
    insert into app.dr_restore_tests (tenant_id, deployment_type, component_scope, status, observed_rpo_minutes, observed_rto_minutes, dr_scenario, tested_by_auth_user_id, tested_by)
    values (v_tenant1, 'shared', 'database', 'passed', 5, 10, 'not-a-real-scenario', v_admin1, 'admin1');
    raise exception 'assertion failed: expected dr_restore_tests_dr_scenario_check to reject an invalid scenario at the table layer, but the insert succeeded';
  exception
    when others then
      if sqlerrm !~ 'dr_restore_tests_dr_scenario_check' then
        raise;
      end if;
      v_raised := true;
  end;
  if not v_raised then
    raise exception 'assertion failed: expected a dr_restore_tests_dr_scenario_check violation, got none';
  end if;

  raise notice 'ISS-2026-260 proof: app.record_dr_restore_test''s new p_dr_scenario parameter records all 4 named DR scenarios alongside the existing component_scope, is rejected when invalid (both at the RPC and the table layer), and every pre-existing call site is unaffected';
end;
$$;

\echo '>> ISS-2026-260 regression evidence complete'

\echo 'ALL IAE-035 (Disaster Recovery and Enterprise Support) ASSERTIONS PASSED'
