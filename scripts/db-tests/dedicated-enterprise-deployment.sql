-- Real, executable test evidence for IAE-032 (Dedicated Enterprise
-- Deployment, Prompt 360) -- run via `pnpm run db:test` against a real,
-- disposable Postgres database. Scoped to this checkpoint's own additive
-- migration (supabase/migrations/20260808000000_create_intelligence_dedicated_enterprise_deployment.sql).
-- Fresh, distinctive tenant fixture (iaedep), fixture id range
-- 00000000-0000-0000-0000-000035xxxxxx.

\set ON_ERROR_STOP on

\echo '>> setup: tenant iaedep with admin1 (tenant_admin + DEPLOY:Configure/View), approver1 (DEPLOY:Approve/View), viewer1 (DEPLOY:View only), rep1 (plain org_user, no DEPLOY grants); a second tenant iaedep2 with admin2 (tenant_admin + DEPLOY:Configure/View/Approve) for cross-tenant isolation'
do $$
declare
  v_tenant1 uuid;
  v_tenant2 uuid;
  v_supreme uuid := '00000000-0000-0000-0000-000035000000';
  v_admin1 uuid := '00000000-0000-0000-0000-000035000001';
  v_viewer1 uuid := '00000000-0000-0000-0000-000035000002';
  v_rep1 uuid := '00000000-0000-0000-0000-000035000003';
  v_admin2 uuid := '00000000-0000-0000-0000-000035000004';
  v_approver1 uuid := '00000000-0000-0000-0000-000035000005';
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
    (v_supreme, 'supreme@iaedep.test'),
    (v_admin1, 'admin@iaedep.test'),
    (v_viewer1, 'viewer@iaedep.test'),
    (v_rep1, 'rep@iaedep.test'),
    (v_admin2, 'admin@iaedep2.test'),
    (v_approver1, 'approver@iaedep.test');

  perform app.grant_principal_membership(v_supreme, 'supreme_admin', null, null, 'tester');

  perform app.provision_tenant('iaedep', 'IaeDep Co', 'idem-iaedep', 'tester');
  v_tenant1 := (select id from app.tenants where slug = 'iaedep');
  perform app.transition_tenant_status(v_tenant1, 'active', 'setup', 'tester');

  perform app.provision_tenant('iaedep2', 'IaeDep2 Co', 'idem-iaedep2', 'tester');
  v_tenant2 := (select id from app.tenants where slug = 'iaedep2');
  perform app.transition_tenant_status(v_tenant2, 'active', 'setup', 'tester');

  perform app.invite_user(v_tenant1, v_admin1, 'admin@iaedep.test', 'Admin One', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'admin@iaedep.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership(v_admin1, 'tenant_admin', v_tenant1, null, 'tester');

  perform app.invite_user(v_tenant1, v_viewer1, 'viewer@iaedep.test', 'Viewer One', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'viewer@iaedep.test'), 'active', 'onboarded', 'tester');

  perform app.invite_user(v_tenant1, v_rep1, 'rep@iaedep.test', 'Rep One', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'rep@iaedep.test'), 'active', 'onboarded', 'tester');

  perform app.invite_user(v_tenant1, v_approver1, 'approver@iaedep.test', 'Approver One', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'approver@iaedep.test'), 'active', 'onboarded', 'tester');

  perform app.invite_user(v_tenant2, v_admin2, 'admin@iaedep2.test', 'Admin Two', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'admin@iaedep2.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership(v_admin2, 'tenant_admin', v_tenant2, null, 'tester');

  v_admin1_role := (app.create_role(v_tenant1, 'IaeDep Admin', 'DEPLOY:Configure/View', 'tester')).id;
  v_admin1_draft := app.create_role_version(v_admin1_role, 'tester');
  perform app.set_role_version_permissions(v_admin1_draft.id, array(select id from app.permissions where resource_module_code = 'DEPLOY' and action in ('Configure', 'View')), 'tester');
  perform app.publish_role_version(v_admin1_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_admin1_role and status = 'published'), v_admin1, v_supreme, 'supreme');

  v_viewer_role := (app.create_role(v_tenant1, 'IaeDep Viewer', 'DEPLOY:View only', 'tester')).id;
  v_viewer_draft := app.create_role_version(v_viewer_role, 'tester');
  perform app.set_role_version_permissions(v_viewer_draft.id, array(select id from app.permissions where resource_module_code = 'DEPLOY' and action = 'View'), 'tester');
  perform app.publish_role_version(v_viewer_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_viewer_role and status = 'published'), v_viewer1, v_supreme, 'supreme');

  v_approver_role := (app.create_role(v_tenant1, 'IaeDep Approver', 'DEPLOY:Approve/View', 'tester')).id;
  v_approver_draft := app.create_role_version(v_approver_role, 'tester');
  perform app.set_role_version_permissions(v_approver_draft.id, array(select id from app.permissions where resource_module_code = 'DEPLOY' and action in ('Approve', 'View')), 'tester');
  perform app.publish_role_version(v_approver_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_approver_role and status = 'published'), v_approver1, v_supreme, 'supreme');

  v_admin2_role := (app.create_role(v_tenant2, 'IaeDep2 Admin', 'DEPLOY:Configure/View/Approve -- tenant2 cross-check probe actor', 'tester')).id;
  v_admin2_draft := app.create_role_version(v_admin2_role, 'tester');
  perform app.set_role_version_permissions(v_admin2_draft.id, array(select id from app.permissions where resource_module_code = 'DEPLOY' and action in ('Configure', 'View', 'Approve')), 'tester');
  perform app.publish_role_version(v_admin2_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant2, (select id from app.role_versions where role_id = v_admin2_role and status = 'published'), v_admin2, v_supreme, 'supreme');

  raise notice 'FIXTURE OK tenant1=%, tenant2=%', v_tenant1, v_tenant2;
end;
$$;

\echo '>> app.resolve_tenant_deployment_type: RPD-011''s own real default -- ''shared'' for every tenant with zero deployment record rows'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'iaedep');
begin
  if app.resolve_tenant_deployment_type(v_tenant1) <> 'shared' then
    raise exception 'assertion failed: expected the RPD-011 default of shared with no deployment record, got %', app.resolve_tenant_deployment_type(v_tenant1);
  end if;
end;
$$;

\echo '>> app.request_dedicated_deployment_qualification: rep1 (no DEPLOY:Configure) rejected; empty reason rejected; admin1 (Configure) succeeds -- a real pending_qualification, deployment_type=dedicated row; a second request for the SAME tenant is rejected with a real unique_violation (never a silent second parallel lifecycle)'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'iaedep');
  v_admin1 uuid := '00000000-0000-0000-0000-000035000001';
  v_rep1 uuid := '00000000-0000-0000-0000-000035000003';
  v_record app.tenant_deployment_records;
begin
  begin
    perform app.request_dedicated_deployment_qualification(v_tenant1, 'expansion into APAC', 'MSA-2026-001', v_rep1, 'rep1');
    raise exception 'assertion failed: expected insufficient_authority for rep1, the call unexpectedly succeeded';
  exception when insufficient_privilege then
    null;
  end;

  begin
    perform app.request_dedicated_deployment_qualification(v_tenant1, '', 'MSA-2026-001', v_admin1, 'admin1');
    raise exception 'assertion failed: expected deployment_qualification_reason_required, the call unexpectedly succeeded';
  exception when check_violation then
    null;
  end;

  v_record := app.request_dedicated_deployment_qualification(v_tenant1, 'expansion into APAC, dedicated instance contractually required', 'MSA-2026-001', v_admin1, 'admin1');
  if v_record.status <> 'pending_qualification' or v_record.deployment_type <> 'dedicated' or v_record.tenant_id <> v_tenant1 then
    raise exception 'assertion failed: expected status=pending_qualification deployment_type=dedicated tenant_id=%, got status=% type=% tenant=%', v_tenant1, v_record.status, v_record.deployment_type, v_record.tenant_id;
  end if;

  begin
    perform app.request_dedicated_deployment_qualification(v_tenant1, 'a second, competing qualification attempt', 'MSA-2026-002', v_admin1, 'admin1');
    raise exception 'assertion failed: expected a real unique_violation for a second deployment record on the same tenant, the call unexpectedly succeeded';
  exception when unique_violation then
    null;
  end;

  if app.resolve_tenant_deployment_type(v_tenant1) <> 'shared' then
    raise exception 'assertion failed: expected still shared while merely pending_qualification (not yet active), got %', app.resolve_tenant_deployment_type(v_tenant1);
  end if;
end;
$$;

\echo '>> app.approve_dedicated_deployment_qualification: viewer1 (View only) rejected; admin1 (Configure, not Approve) rejected -- DEPLOY:Approve is a real, separate authority tier, self-approval by the requester is impossible without it; admin2 (tenant2''s own DEPLOY:Approve, wrong tenant) rejected while the record is still genuinely pending_qualification; approver1 (Approve) succeeds; a second approval on the now-qualified record is rejected (deployment_record_not_pending_qualification)'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'iaedep');
  v_admin1 uuid := '00000000-0000-0000-0000-000035000001';
  v_viewer1 uuid := '00000000-0000-0000-0000-000035000002';
  v_admin2 uuid := '00000000-0000-0000-0000-000035000004';
  v_approver1 uuid := '00000000-0000-0000-0000-000035000005';
  v_record_id uuid;
  v_approved app.tenant_deployment_records;
begin
  select id into v_record_id from app.tenant_deployment_records where tenant_id = v_tenant1;

  begin
    perform app.approve_dedicated_deployment_qualification(v_record_id, v_viewer1, 'viewer1');
    raise exception 'assertion failed: expected insufficient_authority for viewer1 (View only), the call unexpectedly succeeded';
  exception when insufficient_privilege then
    null;
  end;

  begin
    perform app.approve_dedicated_deployment_qualification(v_record_id, v_admin1, 'admin1');
    raise exception 'assertion failed: expected insufficient_authority for admin1 (Configure, not Approve) -- the requester cannot also approve without a real Approve grant, the call unexpectedly succeeded';
  exception when insufficient_privilege then
    null;
  end;

  begin
    perform app.approve_dedicated_deployment_qualification(v_record_id, v_admin2, 'admin2');
    raise exception 'assertion failed: expected insufficient_authority for admin2 (tenant2''s own DEPLOY:Approve does not reach tenant1''s own record), the call unexpectedly succeeded';
  exception when insufficient_privilege then
    null;
  end;

  v_approved := app.approve_dedicated_deployment_qualification(v_record_id, v_approver1, 'approver1');
  if v_approved.status <> 'qualified' or v_approved.approved_by <> 'approver1' or v_approved.approved_by_auth_user_id <> v_approver1 then
    raise exception 'assertion failed: expected status=qualified approved_by=approver1, got status=% approved_by=% approved_by_id=%', v_approved.status, v_approved.approved_by, v_approved.approved_by_auth_user_id;
  end if;
  if v_approved.record_version <> 2 then
    raise exception 'assertion failed: expected record_version=2 after the touch trigger''s first real update, got %', v_approved.record_version;
  end if;

  begin
    perform app.approve_dedicated_deployment_qualification(v_record_id, v_approver1, 'approver1');
    raise exception 'assertion failed: expected deployment_record_not_pending_qualification on a second approval attempt, the call unexpectedly succeeded';
  exception when no_data_found then
    null;
  end;
end;
$$;

\echo '>> self-approval regression: admin2 (tenant iaedep2''s own DEPLOY:Configure/View/Approve -- holds BOTH tiers) cannot approve a deployment qualification they themselves requested, live-reproduced against a genuinely pending_qualification record; a different actor holding Approve can'
do $$
declare
  v_tenant2 uuid := (select id from app.tenants where slug = 'iaedep2');
  v_admin2 uuid := '00000000-0000-0000-0000-000035000004';
  v_record2_id uuid;
begin
  perform app.request_dedicated_deployment_qualification(v_tenant2, 'expansion into APAC for tenant2', 'MSA-2026-003', v_admin2, 'admin2');
  select id into v_record2_id from app.tenant_deployment_records where tenant_id = v_tenant2;

  begin
    perform app.approve_dedicated_deployment_qualification(v_record2_id, v_admin2, 'admin2');
    raise exception 'assertion failed: expected deployment_self_approval_forbidden for admin2 approving their own request (despite holding a real DEPLOY:Approve grant), the call unexpectedly succeeded';
  exception when insufficient_privilege then
    null;
  end;

  -- A raw-SQL bypass attempt is independently blocked by the CHECK constraint itself.
  begin
    update app.tenant_deployment_records set approved_by_auth_user_id = created_by_auth_user_id where id = v_record2_id;
    raise exception 'assertion failed: expected tenant_deployment_records_no_self_approval CHECK violation on a raw-SQL bypass attempt, the update unexpectedly succeeded';
  exception when check_violation then
    null;
  end;
end;
$$;

\echo '>> app.set_deployment_provisioning_status: the real, ordered transition graph -- qualified cannot skip straight to active; provisioning cannot skip straight to decommissioned; viewer1 (no Configure) rejected; admin1 (Configure) drives qualified->provisioning->active->decommissioned; app.resolve_tenant_deployment_type flips to dedicated ONLY at active, and back to shared once decommissioned'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'iaedep');
  v_admin1 uuid := '00000000-0000-0000-0000-000035000001';
  v_viewer1 uuid := '00000000-0000-0000-0000-000035000002';
  v_record_id uuid;
  v_updated app.tenant_deployment_records;
begin
  select id into v_record_id from app.tenant_deployment_records where tenant_id = v_tenant1;

  begin
    perform app.set_deployment_provisioning_status(v_record_id, 'active', v_admin1, 'admin1');
    raise exception 'assertion failed: expected deployment_invalid_transition for qualified->active (skipping provisioning), the call unexpectedly succeeded';
  exception when check_violation then
    null;
  end;

  begin
    perform app.set_deployment_provisioning_status(v_record_id, 'provisioning', v_viewer1, 'viewer1');
    raise exception 'assertion failed: expected insufficient_authority for viewer1 (View only), the call unexpectedly succeeded';
  exception when insufficient_privilege then
    null;
  end;

  v_updated := app.set_deployment_provisioning_status(v_record_id, 'provisioning', v_admin1, 'admin1');
  if v_updated.status <> 'provisioning' then
    raise exception 'assertion failed: expected status=provisioning, got %', v_updated.status;
  end if;

  begin
    perform app.set_deployment_provisioning_status(v_record_id, 'decommissioned', v_admin1, 'admin1');
    raise exception 'assertion failed: expected deployment_invalid_transition for provisioning->decommissioned (skipping active), the call unexpectedly succeeded';
  exception when check_violation then
    null;
  end;

  if app.resolve_tenant_deployment_type(v_tenant1) <> 'shared' then
    raise exception 'assertion failed: expected still shared while merely provisioning (not yet active), got %', app.resolve_tenant_deployment_type(v_tenant1);
  end if;

  v_updated := app.set_deployment_provisioning_status(v_record_id, 'active', v_admin1, 'admin1');
  if v_updated.status <> 'active' or v_updated.provisioned_at is null then
    raise exception 'assertion failed: expected status=active with provisioned_at set, got status=% provisioned_at=%', v_updated.status, v_updated.provisioned_at;
  end if;

  if app.resolve_tenant_deployment_type(v_tenant1) <> 'dedicated' then
    raise exception 'assertion failed: expected dedicated now that the record has genuinely reached active, got %', app.resolve_tenant_deployment_type(v_tenant1);
  end if;

  v_updated := app.set_deployment_provisioning_status(v_record_id, 'decommissioned', v_admin1, 'admin1');
  if v_updated.status <> 'decommissioned' or v_updated.decommissioned_at is null then
    raise exception 'assertion failed: expected status=decommissioned with decommissioned_at set, got status=% decommissioned_at=%', v_updated.status, v_updated.decommissioned_at;
  end if;

  if app.resolve_tenant_deployment_type(v_tenant1) <> 'shared' then
    raise exception 'assertion failed: expected shared again once decommissioned, got %', app.resolve_tenant_deployment_type(v_tenant1);
  end if;

  begin
    perform app.set_deployment_provisioning_status(v_record_id, 'provisioning', v_admin1, 'admin1');
    raise exception 'assertion failed: expected deployment_invalid_transition for decommissioned->provisioning (terminal state), the call unexpectedly succeeded';
  exception when check_violation then
    null;
  end;
end;
$$;

\echo '>> app.set_deployment_environment_ref: viewer1 (no Configure) rejected; invalid category rejected; empty reference_value rejected; admin1 succeeds for all four categories; a second call for the SAME category upserts the SAME row (never a duplicate)'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'iaedep');
  v_admin1 uuid := '00000000-0000-0000-0000-000035000001';
  v_viewer1 uuid := '00000000-0000-0000-0000-000035000002';
  v_record_id uuid;
  v_first app.tenant_deployment_environment_refs;
  v_second app.tenant_deployment_environment_refs;
  v_count integer;
begin
  select id into v_record_id from app.tenant_deployment_records where tenant_id = v_tenant1;

  begin
    perform app.set_deployment_environment_ref(v_record_id, 'database', 'pg-dedicated-iaedep-01', v_viewer1, 'viewer1');
    raise exception 'assertion failed: expected insufficient_authority for viewer1 (View only), the call unexpectedly succeeded';
  exception when insufficient_privilege then
    null;
  end;

  begin
    perform app.set_deployment_environment_ref(v_record_id, 'not-a-real-category', 'x', v_admin1, 'admin1');
    raise exception 'assertion failed: expected deployment_invalid_environment_category, the call unexpectedly succeeded';
  exception when check_violation then
    null;
  end;

  begin
    perform app.set_deployment_environment_ref(v_record_id, 'database', '', v_admin1, 'admin1');
    raise exception 'assertion failed: expected deployment_reference_value_required, the call unexpectedly succeeded';
  exception when check_violation then
    null;
  end;

  v_first := app.set_deployment_environment_ref(v_record_id, 'database', 'pg-dedicated-iaedep-01', v_admin1, 'admin1');
  perform app.set_deployment_environment_ref(v_record_id, 'secrets', 'vault://iaedep/dedicated', v_admin1, 'admin1');
  perform app.set_deployment_environment_ref(v_record_id, 'backup', 's3://iaedep-dedicated-backups', v_admin1, 'admin1');
  perform app.set_deployment_environment_ref(v_record_id, 'observability', 'grafana://iaedep-dedicated', v_admin1, 'admin1');

  v_second := app.set_deployment_environment_ref(v_record_id, 'database', 'pg-dedicated-iaedep-01-replacement', v_admin1, 'admin1');
  if v_second.id <> v_first.id or v_second.reference_value <> 'pg-dedicated-iaedep-01-replacement' then
    raise exception 'assertion failed: expected the SAME row upserted with the new reference_value, got id=% (was %) reference_value=%', v_second.id, v_first.id, v_second.reference_value;
  end if;

  select count(*) into v_count from app.tenant_deployment_environment_refs where deployment_record_id = v_record_id;
  if v_count <> 4 then
    raise exception 'assertion failed: expected exactly 4 environment ref rows (one per category, no duplicates), got %', v_count;
  end if;
end;
$$;

\echo '>> app.get_tenant_deployment_record / app.list_deployment_environment_refs: rep1 (no DEPLOY:View) rejected; viewer1 (View) succeeds, refs ordered by category asc'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'iaedep');
  v_viewer1 uuid := '00000000-0000-0000-0000-000035000002';
  v_rep1 uuid := '00000000-0000-0000-0000-000035000003';
  v_record_id uuid;
  v_record app.tenant_deployment_records;
  v_categories text[];
begin
  select id into v_record_id from app.tenant_deployment_records where tenant_id = v_tenant1;

  begin
    perform app.get_tenant_deployment_record(v_tenant1, v_rep1);
    raise exception 'assertion failed: expected insufficient_authority for rep1 (no DEPLOY:View), the call unexpectedly succeeded';
  exception when insufficient_privilege then
    null;
  end;

  v_record := app.get_tenant_deployment_record(v_tenant1, v_viewer1);
  if v_record.id <> v_record_id or v_record.status <> 'decommissioned' then
    raise exception 'assertion failed: expected the real, decommissioned deployment record for tenant1, got id=% status=%', v_record.id, v_record.status;
  end if;

  begin
    perform count(*) from app.list_deployment_environment_refs(v_record_id, v_rep1);
    raise exception 'assertion failed: expected insufficient_authority for rep1 listing environment refs, the call unexpectedly succeeded';
  exception when insufficient_privilege then
    null;
  end;

  select array_agg(environment_category order by environment_category asc) into v_categories from app.list_deployment_environment_refs(v_record_id, v_viewer1);
  if v_categories <> array['backup', 'database', 'observability', 'secrets'] then
    raise exception 'assertion failed: expected all 4 categories ordered asc, got %', v_categories;
  end if;
end;
$$;

\echo '>> cross-tenant isolation: admin2 (tenant iaedep2, its own DEPLOY:Configure/View/Approve) cannot request/set status/set env ref/read tenant1''s own deployment record (approve''s own cross-tenant rejection was already proven above, against a genuinely pending_qualification record)'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'iaedep');
  v_admin2 uuid := '00000000-0000-0000-0000-000035000004';
  v_record_id uuid;
begin
  select id into v_record_id from app.tenant_deployment_records where tenant_id = v_tenant1;

  begin
    perform app.request_dedicated_deployment_qualification(v_tenant1, 'hijacked qualification attempt', 'FAKE', v_admin2, 'admin2');
    raise exception 'assertion failed: expected insufficient_authority for admin2 requesting qualification on tenant1, the call unexpectedly succeeded';
  exception when insufficient_privilege then
    null;
  end;

  begin
    perform app.set_deployment_provisioning_status(v_record_id, 'provisioning', v_admin2, 'admin2');
    raise exception 'assertion failed: expected insufficient_authority for admin2 changing tenant1''s own provisioning status, the call unexpectedly succeeded';
  exception when insufficient_privilege then
    null;
  end;

  begin
    perform app.set_deployment_environment_ref(v_record_id, 'database', 'hijacked', v_admin2, 'admin2');
    raise exception 'assertion failed: expected insufficient_authority for admin2 setting an env ref on tenant1''s own record, the call unexpectedly succeeded';
  exception when insufficient_privilege then
    null;
  end;

  begin
    perform app.get_tenant_deployment_record(v_tenant1, v_admin2);
    raise exception 'assertion failed: expected insufficient_authority for admin2 reading tenant1''s own deployment record, the call unexpectedly succeeded';
  exception when insufficient_privilege then
    null;
  end;

  begin
    perform count(*) from app.list_deployment_environment_refs(v_record_id, v_admin2);
    raise exception 'assertion failed: expected insufficient_authority for admin2 listing tenant1''s own environment refs, the call unexpectedly succeeded';
  exception when insufficient_privilege then
    null;
  end;
end;
$$;

\echo '>> RLS default-deny: a direct authenticated select on every new table is denied at the raw-RLS level regardless of role/permission'
do $$
begin
  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000035000001", "role": "authenticated"}';

  begin
    perform count(*) from app.tenant_deployment_records;
    raise exception 'assertion failed: expected permission denied for a direct authenticated select on app.tenant_deployment_records, the select unexpectedly succeeded';
  exception when insufficient_privilege then
    null;
  end;

  begin
    perform count(*) from app.tenant_deployment_environment_refs;
    raise exception 'assertion failed: expected permission denied for a direct authenticated select on app.tenant_deployment_environment_refs, the select unexpectedly succeeded';
  exception when insufficient_privilege then
    null;
  end;

  reset role;
end;
$$;

\echo '>> defense in depth: anon holds zero EXECUTE grants across every new function; authenticated holds zero EXECUTE on app.resolve_tenant_deployment_type specifically (service_role-only, the exact bare-tenant-id authority gap Group 7''s own Tier C review taught) while service_role does'
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
      'request_dedicated_deployment_qualification', 'approve_dedicated_deployment_qualification',
      'set_deployment_provisioning_status', 'resolve_tenant_deployment_type',
      'set_deployment_environment_ref', 'get_tenant_deployment_record', 'list_deployment_environment_refs'
    )
    and has_function_privilege('anon', p.oid, 'EXECUTE');

  if v_anon_grant_count <> 0 then
    raise exception 'assertion failed: expected zero anon EXECUTE grants across this checkpoint''s 7 functions, found %', v_anon_grant_count;
  end if;

  select has_function_privilege('authenticated', 'app.resolve_tenant_deployment_type(uuid)', 'EXECUTE') into v_authenticated_on_resolve;
  if v_authenticated_on_resolve then
    raise exception 'assertion failed: expected authenticated to hold ZERO EXECUTE on app.resolve_tenant_deployment_type (bare p_tenant_id, no actor param -- service_role-only), found a grant';
  end if;

  select has_function_privilege('service_role', 'app.resolve_tenant_deployment_type(uuid)', 'EXECUTE') into v_service_role_on_resolve;
  if not v_service_role_on_resolve then
    raise exception 'assertion failed: expected service_role to hold EXECUTE on app.resolve_tenant_deployment_type, found none';
  end if;
end;
$$;

\echo 'ALL IAE-032 (Dedicated Enterprise Deployment) ASSERTIONS PASSED'
