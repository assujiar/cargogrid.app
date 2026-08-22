-- Real, executable test evidence for IAE-033 (Multi-Region and Data
-- Residency, Prompt 361) -- run via `pnpm run db:test` against a real,
-- disposable Postgres database. Scoped to this checkpoint's own additive
-- migration (supabase/migrations/20260808100000_create_intelligence_multi_region_data_residency.sql),
-- plus its own real composition with IAE-032's own dedicated-deployment
-- lifecycle (supabase/migrations/20260808000000_create_intelligence_dedicated_enterprise_deployment.sql).
-- Fresh, distinctive tenant fixture (iaeres), fixture id range
-- 00000000-0000-0000-0000-000036xxxxxx.

\set ON_ERROR_STOP on

\echo '>> setup: tenant iaeres with admin1 (tenant_admin + DEPLOY:Configure/View), approver1 (DEPLOY:Approve/View), viewer1 (DEPLOY:View only), rep1 (plain org_user, no DEPLOY grants); a second tenant iaeres2 with admin2 (tenant_admin + DEPLOY:Configure/View/Approve) for cross-tenant isolation; a platform-wide supreme admin'
do $$
declare
  v_tenant1 uuid;
  v_tenant2 uuid;
  v_supreme uuid := '00000000-0000-0000-0000-000036000000';
  v_admin1 uuid := '00000000-0000-0000-0000-000036000001';
  v_viewer1 uuid := '00000000-0000-0000-0000-000036000002';
  v_rep1 uuid := '00000000-0000-0000-0000-000036000003';
  v_admin2 uuid := '00000000-0000-0000-0000-000036000004';
  v_approver1 uuid := '00000000-0000-0000-0000-000036000005';
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
    (v_supreme, 'supreme@iaeres.test'),
    (v_admin1, 'admin@iaeres.test'),
    (v_viewer1, 'viewer@iaeres.test'),
    (v_rep1, 'rep@iaeres.test'),
    (v_admin2, 'admin@iaeres2.test'),
    (v_approver1, 'approver@iaeres.test');

  perform app.grant_principal_membership(v_supreme, 'supreme_admin', null, null, 'tester');

  perform app.provision_tenant('iaeres', 'IaeRes Co', 'idem-iaeres', 'tester');
  v_tenant1 := (select id from app.tenants where slug = 'iaeres');
  perform app.transition_tenant_status(v_tenant1, 'active', 'setup', 'tester');

  perform app.provision_tenant('iaeres2', 'IaeRes2 Co', 'idem-iaeres2', 'tester');
  v_tenant2 := (select id from app.tenants where slug = 'iaeres2');
  perform app.transition_tenant_status(v_tenant2, 'active', 'setup', 'tester');

  perform app.invite_user(v_tenant1, v_admin1, 'admin@iaeres.test', 'Admin One', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'admin@iaeres.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership(v_admin1, 'tenant_admin', v_tenant1, null, 'tester');

  perform app.invite_user(v_tenant1, v_viewer1, 'viewer@iaeres.test', 'Viewer One', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'viewer@iaeres.test'), 'active', 'onboarded', 'tester');

  perform app.invite_user(v_tenant1, v_rep1, 'rep@iaeres.test', 'Rep One', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'rep@iaeres.test'), 'active', 'onboarded', 'tester');

  perform app.invite_user(v_tenant1, v_approver1, 'approver@iaeres.test', 'Approver One', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'approver@iaeres.test'), 'active', 'onboarded', 'tester');

  perform app.invite_user(v_tenant2, v_admin2, 'admin@iaeres2.test', 'Admin Two', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'admin@iaeres2.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership(v_admin2, 'tenant_admin', v_tenant2, null, 'tester');

  v_admin1_role := (app.create_role(v_tenant1, 'IaeRes Admin', 'DEPLOY:Configure/View', 'tester')).id;
  v_admin1_draft := app.create_role_version(v_admin1_role, 'tester');
  perform app.set_role_version_permissions(v_admin1_draft.id, array(select id from app.permissions where resource_module_code = 'DEPLOY' and action in ('Configure', 'View')), 'tester');
  perform app.publish_role_version(v_admin1_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_admin1_role and status = 'published'), v_admin1, v_supreme, 'supreme');

  v_viewer_role := (app.create_role(v_tenant1, 'IaeRes Viewer', 'DEPLOY:View only', 'tester')).id;
  v_viewer_draft := app.create_role_version(v_viewer_role, 'tester');
  perform app.set_role_version_permissions(v_viewer_draft.id, array(select id from app.permissions where resource_module_code = 'DEPLOY' and action = 'View'), 'tester');
  perform app.publish_role_version(v_viewer_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_viewer_role and status = 'published'), v_viewer1, v_supreme, 'supreme');

  v_approver_role := (app.create_role(v_tenant1, 'IaeRes Approver', 'DEPLOY:Approve/View', 'tester')).id;
  v_approver_draft := app.create_role_version(v_approver_role, 'tester');
  perform app.set_role_version_permissions(v_approver_draft.id, array(select id from app.permissions where resource_module_code = 'DEPLOY' and action in ('Approve', 'View')), 'tester');
  perform app.publish_role_version(v_approver_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_approver_role and status = 'published'), v_approver1, v_supreme, 'supreme');

  v_admin2_role := (app.create_role(v_tenant2, 'IaeRes2 Admin', 'DEPLOY:Configure/View/Approve -- tenant2 cross-check probe actor', 'tester')).id;
  v_admin2_draft := app.create_role_version(v_admin2_role, 'tester');
  perform app.set_role_version_permissions(v_admin2_draft.id, array(select id from app.permissions where resource_module_code = 'DEPLOY' and action in ('Configure', 'View', 'Approve')), 'tester');
  perform app.publish_role_version(v_admin2_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant2, (select id from app.role_versions where role_id = v_admin2_role and status = 'published'), v_admin2, v_supreme, 'supreme');

  raise notice 'FIXTURE OK tenant1=%, tenant2=%', v_tenant1, v_tenant2;
end;
$$;

\echo '>> app.resolve_tenant_region: RPD-013''s own real default -- ''apac'' for every tenant with zero region assignment rows'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'iaeres');
begin
  if app.resolve_tenant_region(v_tenant1) <> 'apac' then
    raise exception 'assertion failed: expected the RPD-013 default of apac with no region assignment, got %', app.resolve_tenant_region(v_tenant1);
  end if;
end;
$$;

\echo '>> app.request_region_assignment: rep1 (no DEPLOY:Configure) rejected; the default apac rejected as a meaningless explicit assignment; empty reason rejected; admin1 (Configure) succeeds for americas -- a real pending_review row; a second request for the SAME tenant rejected with a real unique_violation'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'iaeres');
  v_admin1 uuid := '00000000-0000-0000-0000-000036000001';
  v_rep1 uuid := '00000000-0000-0000-0000-000036000003';
  v_record app.tenant_region_assignments;
begin
  begin
    perform app.request_region_assignment(v_tenant1, 'americas', 'expansion into the Americas market', 'MSA-2026-002', v_rep1, 'rep1');
    raise exception 'assertion failed: expected insufficient_authority for rep1, the call unexpectedly succeeded';
  exception when insufficient_privilege then
    null;
  end;

  begin
    perform app.request_region_assignment(v_tenant1, 'apac', 'redundant explicit default', null, v_admin1, 'admin1');
    raise exception 'assertion failed: expected region_invalid_code for the already-default apac, the call unexpectedly succeeded';
  exception when check_violation then
    null;
  end;

  begin
    perform app.request_region_assignment(v_tenant1, 'americas', '', 'MSA-2026-002', v_admin1, 'admin1');
    raise exception 'assertion failed: expected region_qualification_reason_required, the call unexpectedly succeeded';
  exception when check_violation then
    null;
  end;

  v_record := app.request_region_assignment(v_tenant1, 'americas', 'expansion into the Americas market', 'MSA-2026-002', v_admin1, 'admin1');
  if v_record.status <> 'pending_review' or v_record.region_code <> 'americas' or v_record.tenant_id <> v_tenant1 then
    raise exception 'assertion failed: expected status=pending_review region_code=americas tenant_id=%, got status=% region=% tenant=%', v_tenant1, v_record.status, v_record.region_code, v_record.tenant_id;
  end if;

  begin
    perform app.request_region_assignment(v_tenant1, 'emea', 'a second, competing region request', 'MSA-2026-003', v_admin1, 'admin1');
    raise exception 'assertion failed: expected a real unique_violation for a second region assignment on the same tenant, the call unexpectedly succeeded';
  exception when unique_violation then
    null;
  end;
end;
$$;

\echo '>> app.approve_region_assignment BEFORE any dedicated deployment exists: approver1 (Approve) is rejected with region_requires_dedicated_deployment -- RPD-013''s own real, structural composition with IAE-032'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'iaeres');
  v_viewer1 uuid := '00000000-0000-0000-0000-000036000002';
  v_admin1 uuid := '00000000-0000-0000-0000-000036000001';
  v_approver1 uuid := '00000000-0000-0000-0000-000036000005';
  v_assignment_id uuid;
begin
  select id into v_assignment_id from app.tenant_region_assignments where tenant_id = v_tenant1;

  begin
    perform app.approve_region_assignment(v_assignment_id, v_viewer1, 'viewer1');
    raise exception 'assertion failed: expected insufficient_authority for viewer1 (View only), the call unexpectedly succeeded';
  exception when insufficient_privilege then
    null;
  end;

  begin
    perform app.approve_region_assignment(v_assignment_id, v_admin1, 'admin1');
    raise exception 'assertion failed: expected insufficient_authority for admin1 (Configure, not Approve), the call unexpectedly succeeded';
  exception when insufficient_privilege then
    null;
  end;

  begin
    perform app.approve_region_assignment(v_assignment_id, v_approver1, 'approver1');
    raise exception 'assertion failed: expected region_requires_dedicated_deployment with no dedicated deployment yet, the call unexpectedly succeeded';
  exception when check_violation then
    null;
  end;
end;
$$;

\echo '>> composing IAE-032''s own dedicated-deployment lifecycle end to end so tenant1 genuinely reaches an active dedicated deployment'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'iaeres');
  v_admin1 uuid := '00000000-0000-0000-0000-000036000001';
  v_approver1 uuid := '00000000-0000-0000-0000-000036000005';
  v_deployment_id uuid;
begin
  perform app.request_dedicated_deployment_qualification(v_tenant1, 'dedicated instance required for regional expansion', 'MSA-2026-002', v_admin1, 'admin1');
  select id into v_deployment_id from app.tenant_deployment_records where tenant_id = v_tenant1;
  perform app.approve_dedicated_deployment_qualification(v_deployment_id, v_approver1, 'approver1');
  perform app.set_deployment_provisioning_status(v_deployment_id, 'provisioning', v_admin1, 'admin1');
  perform app.set_deployment_provisioning_status(v_deployment_id, 'active', v_admin1, 'admin1');

  if app.resolve_tenant_deployment_type(v_tenant1) <> 'dedicated' then
    raise exception 'assertion failed: expected tenant1 to now have an active dedicated deployment, got %', app.resolve_tenant_deployment_type(v_tenant1);
  end if;
end;
$$;

\echo '>> app.approve_region_assignment with dedicated deployment now active, but no capability exceptions yet: rejected with region_capability_gap_unresolved (deterministic, first missing category)'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'iaeres');
  v_approver1 uuid := '00000000-0000-0000-0000-000036000005';
  v_assignment_id uuid;
begin
  select id into v_assignment_id from app.tenant_region_assignments where tenant_id = v_tenant1;

  begin
    perform app.approve_region_assignment(v_assignment_id, v_approver1, 'approver1');
    raise exception 'assertion failed: expected region_capability_gap_unresolved with zero exceptions registered, the call unexpectedly succeeded';
  exception when check_violation then
    null;
  end;
end;
$$;

\echo '>> app.set_region_service_capability: viewer1 (not Supreme Admin) rejected; supreme admin marks americas/ai_provider as genuinely supported; invalid region/category rejected'
do $$
declare
  v_supreme uuid := '00000000-0000-0000-0000-000036000000';
  v_viewer1 uuid := '00000000-0000-0000-0000-000036000002';
  v_row app.region_service_capabilities;
begin
  begin
    perform app.set_region_service_capability('americas', 'ai_provider', true, 'viewer1 should not be able to do this', v_viewer1, 'viewer1');
    raise exception 'assertion failed: expected insufficient_authority for viewer1 (not Supreme Admin), the call unexpectedly succeeded';
  exception when insufficient_privilege then
    null;
  end;

  v_row := app.set_region_service_capability('americas', 'ai_provider', true, 'provider capacity now available', v_supreme, 'supreme');
  if v_row.supported <> true then
    raise exception 'assertion failed: expected americas/ai_provider to now be supported, got %', v_row.supported;
  end if;

  begin
    perform app.set_region_service_capability('not-a-real-region', 'ai_provider', true, 'x', v_supreme, 'supreme');
    raise exception 'assertion failed: expected region_invalid_code, the call unexpectedly succeeded';
  exception when check_violation then
    null;
  end;

  begin
    perform app.set_region_service_capability('americas', 'not-a-real-category', true, 'x', v_supreme, 'supreme');
    raise exception 'assertion failed: expected region_invalid_service_category, the call unexpectedly succeeded';
  exception when check_violation then
    null;
  end;
end;
$$;

\echo '>> app.register_region_capability_exception: rep1 (no DEPLOY:Approve) rejected; ai_provider now rejected as region_capability_exception_not_needed (already supported); the remaining 4 genuinely-unsupported categories registered successfully by approver1; a second call for the SAME category upserts the SAME row'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'iaeres');
  v_rep1 uuid := '00000000-0000-0000-0000-000036000003';
  v_approver1 uuid := '00000000-0000-0000-0000-000036000005';
  v_assignment_id uuid;
  v_first app.region_capability_exceptions;
  v_second app.region_capability_exceptions;
  v_count integer;
begin
  select id into v_assignment_id from app.tenant_region_assignments where tenant_id = v_tenant1;

  begin
    perform app.register_region_capability_exception(v_assignment_id, 'database', 'accepted risk', v_rep1, 'rep1');
    raise exception 'assertion failed: expected insufficient_authority for rep1 (no DEPLOY:Approve), the call unexpectedly succeeded';
  exception when insufficient_privilege then
    null;
  end;

  begin
    perform app.register_region_capability_exception(v_assignment_id, 'ai_provider', 'should not be needed', v_approver1, 'approver1');
    raise exception 'assertion failed: expected region_capability_exception_not_needed for ai_provider (already supported), the call unexpectedly succeeded';
  exception when check_violation then
    null;
  end;

  v_first := app.register_region_capability_exception(v_assignment_id, 'database', 'contractually accepted risk pending regional buildout', v_approver1, 'approver1');
  perform app.register_region_capability_exception(v_assignment_id, 'secrets', 'contractually accepted risk pending regional buildout', v_approver1, 'approver1');
  perform app.register_region_capability_exception(v_assignment_id, 'backup', 'contractually accepted risk pending regional buildout', v_approver1, 'approver1');
  perform app.register_region_capability_exception(v_assignment_id, 'observability', 'contractually accepted risk pending regional buildout', v_approver1, 'approver1');

  v_second := app.register_region_capability_exception(v_assignment_id, 'database', 'updated accepted-risk reason', v_approver1, 'approver1');
  if v_second.id <> v_first.id or v_second.reason <> 'updated accepted-risk reason' then
    raise exception 'assertion failed: expected the SAME row upserted with the new reason, got id=% (was %) reason=%', v_second.id, v_first.id, v_second.reason;
  end if;

  select count(*) into v_count from app.region_capability_exceptions where region_assignment_id = v_assignment_id;
  if v_count <> 4 then
    raise exception 'assertion failed: expected exactly 4 exception rows (database/secrets/backup/observability, never a duplicate), got %', v_count;
  end if;
end;
$$;

\echo '>> app.approve_region_assignment now succeeds: dedicated deployment active, ai_provider genuinely supported, all 4 remaining gaps covered by real exceptions; a second approval attempt on the now-approved record is rejected (region_assignment_not_pending_review)'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'iaeres');
  v_approver1 uuid := '00000000-0000-0000-0000-000036000005';
  v_assignment_id uuid;
  v_approved app.tenant_region_assignments;
begin
  select id into v_assignment_id from app.tenant_region_assignments where tenant_id = v_tenant1;

  v_approved := app.approve_region_assignment(v_assignment_id, v_approver1, 'approver1');
  if v_approved.status <> 'approved' or v_approved.approved_by <> 'approver1' then
    raise exception 'assertion failed: expected status=approved approved_by=approver1, got status=% approved_by=%', v_approved.status, v_approved.approved_by;
  end if;

  begin
    perform app.approve_region_assignment(v_assignment_id, v_approver1, 'approver1');
    raise exception 'assertion failed: expected region_assignment_not_pending_review on a second approval attempt, the call unexpectedly succeeded';
  exception when no_data_found then
    null;
  end;
end;
$$;

\echo '>> app.set_region_assignment_status: the real, ordered transition graph -- approved cannot skip straight to decommissioned; viewer1 (no Configure) rejected; admin1 drives approved->active; app.resolve_tenant_region flips to americas ONLY at active, and back to apac once decommissioned'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'iaeres');
  v_admin1 uuid := '00000000-0000-0000-0000-000036000001';
  v_viewer1 uuid := '00000000-0000-0000-0000-000036000002';
  v_assignment_id uuid;
  v_updated app.tenant_region_assignments;
begin
  select id into v_assignment_id from app.tenant_region_assignments where tenant_id = v_tenant1;

  begin
    perform app.set_region_assignment_status(v_assignment_id, 'decommissioned', null, v_admin1, 'admin1');
    raise exception 'assertion failed: expected region_invalid_transition for approved->decommissioned (skipping active), the call unexpectedly succeeded';
  exception when check_violation then
    null;
  end;

  begin
    perform app.set_region_assignment_status(v_assignment_id, 'active', null, v_viewer1, 'viewer1');
    raise exception 'assertion failed: expected insufficient_authority for viewer1 (View only), the call unexpectedly succeeded';
  exception when insufficient_privilege then
    null;
  end;

  if app.resolve_tenant_region(v_tenant1) <> 'apac' then
    raise exception 'assertion failed: expected still apac while merely approved (not yet active), got %', app.resolve_tenant_region(v_tenant1);
  end if;

  v_updated := app.set_region_assignment_status(v_assignment_id, 'active', null, v_admin1, 'admin1');
  if v_updated.status <> 'active' or v_updated.activated_at is null then
    raise exception 'assertion failed: expected status=active with activated_at set, got status=% activated_at=%', v_updated.status, v_updated.activated_at;
  end if;

  if app.resolve_tenant_region(v_tenant1) <> 'americas' then
    raise exception 'assertion failed: expected americas now that the assignment has genuinely reached active, got %', app.resolve_tenant_region(v_tenant1);
  end if;

  v_updated := app.set_region_assignment_status(v_assignment_id, 'decommissioned', null, v_admin1, 'admin1');
  if v_updated.status <> 'decommissioned' or v_updated.decommissioned_at is null then
    raise exception 'assertion failed: expected status=decommissioned with decommissioned_at set, got status=% decommissioned_at=%', v_updated.status, v_updated.decommissioned_at;
  end if;

  if app.resolve_tenant_region(v_tenant1) <> 'apac' then
    raise exception 'assertion failed: expected apac again once decommissioned, got %', app.resolve_tenant_region(v_tenant1);
  end if;
end;
$$;

\echo '>> app.set_region_assignment_status rejection path (a fresh, second tenant''s own request): empty rejection reason rejected; admin2 (Configure) rejects tenant2''s own request with a real reason; rejected is terminal'
do $$
declare
  v_tenant2 uuid := (select id from app.tenants where slug = 'iaeres2');
  v_admin2 uuid := '00000000-0000-0000-0000-000036000004';
  v_assignment_id uuid;
  v_rejected app.tenant_region_assignments;
begin
  perform app.request_region_assignment(v_tenant2, 'emea', 'exploring EMEA expansion', 'MSA-2026-004', v_admin2, 'admin2');
  select id into v_assignment_id from app.tenant_region_assignments where tenant_id = v_tenant2;

  begin
    perform app.set_region_assignment_status(v_assignment_id, 'rejected', null, v_admin2, 'admin2');
    raise exception 'assertion failed: expected region_rejection_reason_required, the call unexpectedly succeeded';
  exception when check_violation then
    null;
  end;

  v_rejected := app.set_region_assignment_status(v_assignment_id, 'rejected', 'no provider capability and no contract exception -- blocking per Prompt 361 alternative flow', v_admin2, 'admin2');
  if v_rejected.status <> 'rejected' or v_rejected.rejection_reason is null then
    raise exception 'assertion failed: expected status=rejected with a real rejection_reason, got status=% reason=%', v_rejected.status, v_rejected.rejection_reason;
  end if;

  begin
    perform app.set_region_assignment_status(v_assignment_id, 'approved', null, v_admin2, 'admin2');
    raise exception 'assertion failed: expected region_invalid_transition out of the terminal rejected state, the call unexpectedly succeeded';
  exception when check_violation then
    null;
  end;
end;
$$;

\echo '>> cross-tenant isolation: admin2 (tenant iaeres2, its own DEPLOY:Configure/View/Approve) cannot set status/register exception/read tenant1''s own (decommissioned) region assignment, and cannot list platform capabilities under tenant1''s own scope'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'iaeres');
  v_admin2 uuid := '00000000-0000-0000-0000-000036000004';
  v_assignment_id uuid;
begin
  select id into v_assignment_id from app.tenant_region_assignments where tenant_id = v_tenant1;

  begin
    perform app.set_region_assignment_status(v_assignment_id, 'active', null, v_admin2, 'admin2');
    raise exception 'assertion failed: expected insufficient_authority for admin2 changing tenant1''s own region assignment status, the call unexpectedly succeeded';
  exception when insufficient_privilege then
    null;
  end;

  begin
    perform app.register_region_capability_exception(v_assignment_id, 'database', 'hijacked exception', v_admin2, 'admin2');
    raise exception 'assertion failed: expected insufficient_authority for admin2 registering an exception on tenant1''s own assignment, the call unexpectedly succeeded';
  exception when insufficient_privilege then
    null;
  end;

  begin
    perform app.get_tenant_region_assignment(v_tenant1, v_admin2);
    raise exception 'assertion failed: expected insufficient_authority for admin2 reading tenant1''s own region assignment, the call unexpectedly succeeded';
  exception when insufficient_privilege then
    null;
  end;

  begin
    perform count(*) from app.list_region_capability_exceptions_for_tenant(v_tenant1, v_admin2);
    raise exception 'assertion failed: expected insufficient_authority for admin2 listing tenant1''s own exceptions, the call unexpectedly succeeded';
  exception when insufficient_privilege then
    null;
  end;

  begin
    perform count(*) from app.list_region_service_capabilities(v_tenant1, v_admin2);
    raise exception 'assertion failed: expected insufficient_authority for admin2 passing tenant1 (not their own tenant) to the platform-wide capability read, the call unexpectedly succeeded';
  exception when insufficient_privilege then
    null;
  end;
end;
$$;

\echo '>> app.list_region_service_capabilities: platform-wide data, identical regardless of tenant -- rep1 (no DEPLOY:View anywhere) rejected; viewer1 and admin2 (each gated only against their OWN tenant) both see the SAME full 15-row matrix'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'iaeres');
  v_tenant2 uuid := (select id from app.tenants where slug = 'iaeres2');
  v_viewer1 uuid := '00000000-0000-0000-0000-000036000002';
  v_rep1 uuid := '00000000-0000-0000-0000-000036000003';
  v_admin2 uuid := '00000000-0000-0000-0000-000036000004';
  v_count1 integer;
  v_count2 integer;
begin
  begin
    perform count(*) from app.list_region_service_capabilities(v_tenant1, v_rep1);
    raise exception 'assertion failed: expected insufficient_authority for rep1 (no DEPLOY:View anywhere), the call unexpectedly succeeded';
  exception when insufficient_privilege then
    null;
  end;

  select count(*) into v_count1 from app.list_region_service_capabilities(v_tenant1, v_viewer1);
  select count(*) into v_count2 from app.list_region_service_capabilities(v_tenant2, v_admin2);
  if v_count1 <> 15 or v_count2 <> 15 then
    raise exception 'assertion failed: expected both actors to see the SAME 15-row platform-wide matrix regardless of their own tenant, got %/%', v_count1, v_count2;
  end if;
end;
$$;

\echo '>> RLS default-deny: a direct authenticated select on every new table is denied at the raw-RLS level regardless of role/permission'
do $$
begin
  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000036000001", "role": "authenticated"}';

  begin
    perform count(*) from app.region_service_capabilities;
    raise exception 'assertion failed: expected permission denied for a direct authenticated select on app.region_service_capabilities, the select unexpectedly succeeded';
  exception when insufficient_privilege then
    null;
  end;

  begin
    perform count(*) from app.tenant_region_assignments;
    raise exception 'assertion failed: expected permission denied for a direct authenticated select on app.tenant_region_assignments, the select unexpectedly succeeded';
  exception when insufficient_privilege then
    null;
  end;

  begin
    perform count(*) from app.region_capability_exceptions;
    raise exception 'assertion failed: expected permission denied for a direct authenticated select on app.region_capability_exceptions, the select unexpectedly succeeded';
  exception when insufficient_privilege then
    null;
  end;

  reset role;
end;
$$;

\echo '>> defense in depth: anon holds zero EXECUTE grants across every new function; authenticated holds zero EXECUTE on app.resolve_tenant_region specifically (service_role-only) while service_role does'
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
      'set_region_service_capability', 'request_region_assignment', 'approve_region_assignment',
      'register_region_capability_exception', 'set_region_assignment_status', 'resolve_tenant_region',
      'get_tenant_region_assignment', 'list_region_service_capabilities', 'list_region_capability_exceptions_for_tenant'
    )
    and has_function_privilege('anon', p.oid, 'EXECUTE');

  if v_anon_grant_count <> 0 then
    raise exception 'assertion failed: expected zero anon EXECUTE grants across this checkpoint''s 9 functions, found %', v_anon_grant_count;
  end if;

  select has_function_privilege('authenticated', 'app.resolve_tenant_region(uuid)', 'EXECUTE') into v_authenticated_on_resolve;
  if v_authenticated_on_resolve then
    raise exception 'assertion failed: expected authenticated to hold ZERO EXECUTE on app.resolve_tenant_region (bare p_tenant_id, no actor param -- service_role-only), found a grant';
  end if;

  select has_function_privilege('service_role', 'app.resolve_tenant_region(uuid)', 'EXECUTE') into v_service_role_on_resolve;
  if not v_service_role_on_resolve then
    raise exception 'assertion failed: expected service_role to hold EXECUTE on app.resolve_tenant_region, found none';
  end if;
end;
$$;

\echo 'ALL IAE-033 (Multi-Region and Data Residency) ASSERTIONS PASSED'
