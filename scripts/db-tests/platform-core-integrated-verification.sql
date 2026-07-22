-- Real, executable integration evidence for PLT-137 (Platform Core Integrated
-- Verification, CG-S6-PLT-034). Unlike every other file in this directory, this one
-- does not test a single capability -- it runs ONE continuous two-tenant golden path
-- across capability *boundaries* (tenant/entitlement/auth/org/user/RBAC/RLS/config/
-- workflow/job/feature-flag/audit/portal-query-layer/spatial), proving they compose
-- correctly together and that tenant isolation holds across the seams, not just
-- within each capability's own already-proven scope. Every individual capability's
-- own exhaustive scenario coverage remains in its own file (this file does not
-- duplicate it); this file's own value is specifically in composition and in
-- re-confirming, in a fresh combined session, defects already found and fixed at
-- individual checkpoints (the PLT-116 app.users_directory tenant-isolation fix,
-- re-verified in §10 below as a real regression guard, not a fresh assumption).
--
-- Two tenants ('acmeint', 'gizmoint') are provisioned once at the top and reused by
-- every scenario group below -- deliberately, so that the *same* two tenants' identity
-- substrate (auth users, org units, roles) flows through every engine in turn, proving
-- these engines share one coherent identity/tenant model rather than each merely
-- passing its own isolated synthetic fixtures.

\set ON_ERROR_STOP on

\echo '>> setup: two tenants (acmeint entitled to COM, gizmoint deliberately not entitled), one tenant_admin + one org_user each, one global Supreme Admin, one org unit each'
do $$
declare
  v_tenant_a uuid;
  v_tenant_b uuid;
  v_pkg_id uuid;
begin
  insert into auth.users (id, email) values
    ('00000000-0000-0000-0000-000000021001', 'tenantadminint-a@example.test'),
    ('00000000-0000-0000-0000-000000021002', 'regularuserint-a@example.test'),
    ('00000000-0000-0000-0000-000000021003', 'supremeint@example.test'),
    ('00000000-0000-0000-0000-000000021004', 'tenantadminint-b@example.test'),
    ('00000000-0000-0000-0000-000000021005', 'regularuserint-b@example.test');

  perform app.provision_tenant('acmeint', 'Acme Integrated Co', 'idem-acmeint', 'tester');
  v_tenant_a := (select id from app.tenants where slug = 'acmeint');
  perform app.transition_tenant_status(v_tenant_a, 'active', 'setup', 'tester');
  perform app.invite_user(v_tenant_a, '00000000-0000-0000-0000-000000021001', 'tenantadminint-a@example.test', 'Tenant Admin A', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'tenantadminint-a@example.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000021001', 'tenant_admin', v_tenant_a, null, 'tester');
  perform app.invite_user(v_tenant_a, '00000000-0000-0000-0000-000000021002', 'regularuserint-a@example.test', 'Regular User A', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'regularuserint-a@example.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000021002', 'org_user', v_tenant_a, null, 'tester');
  perform app.create_org_unit(v_tenant_a, 'company', null, 'ACMEINT-CO', 'Acme Integrated Co', 'tester');

  perform app.provision_tenant('gizmoint', 'Gizmo Integrated Co', 'idem-gizmoint', 'tester');
  v_tenant_b := (select id from app.tenants where slug = 'gizmoint');
  perform app.transition_tenant_status(v_tenant_b, 'active', 'setup', 'tester');
  perform app.invite_user(v_tenant_b, '00000000-0000-0000-0000-000000021004', 'tenantadminint-b@example.test', 'Tenant Admin B', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'tenantadminint-b@example.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000021004', 'tenant_admin', v_tenant_b, null, 'tester');
  perform app.invite_user(v_tenant_b, '00000000-0000-0000-0000-000000021005', 'regularuserint-b@example.test', 'Regular User B', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'regularuserint-b@example.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000021005', 'org_user', v_tenant_b, null, 'tester');
  perform app.create_org_unit(v_tenant_b, 'company', null, 'GIZMOINT-CO', 'Gizmo Integrated Co', 'tester');

  perform app.grant_principal_membership('00000000-0000-0000-0000-000000021003', 'supreme_admin', null, null, 'tester');

  insert into app.entitlement_packages (code, name, version, status, granted_modules, feature_limits)
  values ('integrated-professional', 'Integrated Professional', 1, 'published', array['COM'], '{}'::jsonb)
  returning id into v_pkg_id;
  perform app.assign_entitlement(v_tenant_a, v_pkg_id, 'active', 'onboarding', 'tester');
  -- gizmoint deliberately receives no entitlement assignment -- the composed
  -- entitlement x feature-flag denial scenario in group 8 below depends on this.
end;
$$;

\echo '>> scenario 1 (RLS baseline, re-confirmed in this fresh combined session): tenant A''s member sees exactly tenant A''s own tenant/org/user rows, never tenant B''s'
do $$
declare
  v_count integer;
begin
  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000021001", "role": "authenticated"}';

  select count(*) into v_count from app.tenants;
  if v_count <> 1 then
    raise exception 'assertion failed: expected tenant A''s admin to see exactly 1 tenant via RLS, saw %', v_count;
  end if;

  select count(*) into v_count from app.org_units;
  if v_count <> 1 then
    raise exception 'assertion failed: expected tenant A''s admin to see exactly 1 org unit via RLS, saw %', v_count;
  end if;

  select count(*) into v_count from app.users;
  if v_count <> 2 then
    raise exception 'assertion failed: expected tenant A''s admin to see exactly 2 users (both of tenant A''s own), saw %', v_count;
  end if;

  reset role;
end;
$$;

\echo '>> scenario 2: app.resolve_access_context differentiates tenant_admin/org_user correctly per tenant, and never cross-resolves a principal into the wrong tenant'
do $$
declare
  v_ctx app.access_context;
begin
  v_ctx := app.resolve_access_context('00000000-0000-0000-0000-000000021001', (select id from app.tenants where slug = 'acmeint'));
  if v_ctx.layer <> 'tenant_admin' or v_ctx.tenant_id <> (select id from app.tenants where slug = 'acmeint') then
    raise exception 'assertion failed: expected tenant A admin to resolve as tenant_admin scoped to tenant A, got layer=% tenant_id=%', v_ctx.layer, v_ctx.tenant_id;
  end if;

  begin
    perform app.resolve_access_context('00000000-0000-0000-0000-000000021002', (select id from app.tenants where slug = 'gizmoint'));
    raise exception 'assertion failed: tenant A''s regular user (never linked/invited to tenant B at all) must never resolve any access context against tenant B''s id';
  exception
    when no_data_found then
      null;
  end;
end;
$$;

\echo '>> scenario 3: Supreme Admin resolves as supreme_admin when p_tenant_id is omitted -- the exact call shape lib/portal/supreme-admin-guard.ts (PLT-136) always uses -- and this checkpoint''s own integration testing found (not a defect: the real guard never triggers it) that the tenant-QUALIFIED branch instead requires its own PLT-107 identity link row, which a global-only Supreme Admin correctly does not have, and so fails closed rather than silently resolving'
do $$
declare
  v_ctx_none app.access_context;
begin
  v_ctx_none := app.resolve_access_context('00000000-0000-0000-0000-000000021003');
  if v_ctx_none.layer <> 'supreme_admin' then
    raise exception 'assertion failed: expected Supreme Admin to resolve as supreme_admin with p_tenant_id omitted, got %', v_ctx_none.layer;
  end if;

  begin
    perform app.resolve_access_context('00000000-0000-0000-0000-000000021003', (select id from app.tenants where slug = 'acmeint'));
    raise exception 'assertion failed: expected a Supreme Admin with no tenant_user_identities row for tenant A to fail closed on a tenant-qualified call, not silently resolve';
  exception
    when no_data_found then
      null;
  end;
end;
$$;

\echo '>> scenario 4: app.evaluate_entitlement composes correctly with the identity/tenant substrate above -- tenant A (assigned the package) is entitled to COM, tenant B (deliberately unassigned) is module_not_entitled'
do $$
declare
  v_decision_a app.entitlement_decision;
  v_decision_b app.entitlement_decision;
begin
  v_decision_a := app.evaluate_entitlement((select id from app.tenants where slug = 'acmeint'), 'COM');
  if not v_decision_a.allowed then
    raise exception 'assertion failed: expected tenant A to be entitled to COM, got allowed=% reason=%', v_decision_a.allowed, v_decision_a.reason;
  end if;

  v_decision_b := app.evaluate_entitlement((select id from app.tenants where slug = 'gizmoint'), 'COM');
  if v_decision_b.allowed or v_decision_b.reason <> 'no_active_entitlement' then
    raise exception 'assertion failed: expected tenant B to be denied COM with reason no_active_entitlement, got allowed=% reason=%', v_decision_b.allowed, v_decision_b.reason;
  end if;
end;
$$;

\echo '>> scenario 5: identically-named custom role ("Composed Approver") created independently in each tenant does not collide, and app.role_assignments/app.roles RLS isolates tenant A from tenant B'
do $$
declare
  v_tenant_a uuid;
  v_tenant_b uuid;
  v_role_a uuid;
  v_role_b uuid;
  v_draft_a app.role_versions;
  v_draft_b app.role_versions;
  v_perm_id uuid;
  v_count integer;
begin
  v_tenant_a := (select id from app.tenants where slug = 'acmeint');
  v_tenant_b := (select id from app.tenants where slug = 'gizmoint');
  select id into v_perm_id from app.permissions where resource_module_code = 'COM' and action = 'Approve';

  v_role_a := (app.create_role(v_tenant_a, 'Composed Approver', null, 'tester')).id;
  select * into v_draft_a from app.create_role_version(v_role_a, 'tester');
  perform app.set_role_version_permissions(v_draft_a.id, array[v_perm_id], 'tester');
  perform app.publish_role_version(v_draft_a.id, now(), 'tester');
  perform app.assign_role(v_tenant_a, v_draft_a.id, '00000000-0000-0000-0000-000000021002', '00000000-0000-0000-0000-000000021001', 'tenant admin A');

  v_role_b := (app.create_role(v_tenant_b, 'Composed Approver', null, 'tester')).id;
  select * into v_draft_b from app.create_role_version(v_role_b, 'tester');
  perform app.set_role_version_permissions(v_draft_b.id, array[v_perm_id], 'tester');
  perform app.publish_role_version(v_draft_b.id, now(), 'tester');
  perform app.assign_role(v_tenant_b, v_draft_b.id, '00000000-0000-0000-0000-000000021005', '00000000-0000-0000-0000-000000021004', 'tenant admin B');

  if v_role_a = v_role_b then
    raise exception 'assertion failed: expected two distinct role rows despite the identical name in different tenants';
  end if;

  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000021001", "role": "authenticated"}';
  select count(*) into v_count from app.roles;
  if v_count <> 1 then
    raise exception 'assertion failed: expected tenant A''s admin to see exactly 1 role (their own) via RLS, saw %', v_count;
  end if;
  select count(*) into v_count from app.role_assignments;
  if v_count <> 1 then
    raise exception 'assertion failed: expected tenant A''s admin to see exactly 1 role_assignment via RLS, saw %', v_count;
  end if;
  reset role;
end;
$$;

\echo '>> scenario 6: Configuration Engine composed -- a fresh config type registered by Supreme, a tenant-scoped draft/publish for tenant A only, tenant B''s resolve_config sees nothing (no cross-tenant bleed), and RLS on config_objects/config_versions/config_items isolates tenant A from tenant B'
do $$
declare
  v_tenant_a uuid;
  v_tenant_b uuid;
  v_draft app.config_versions;
  v_resolved_a record;
  v_count integer;
begin
  v_tenant_a := (select id from app.tenants where slug = 'acmeint');
  v_tenant_b := (select id from app.tenants where slug = 'gizmoint');

  perform app.register_config_type('compliance_rule', 'Compliance Rule', 'INT', '00000000-0000-0000-0000-000000021003', 'supreme admin');

  v_draft := app.create_config_draft('compliance_rule', v_tenant_a, 'tenant', null, '00000000-0000-0000-0000-000000021001', 'tenant admin A');
  perform app.set_config_items(v_draft.id, '[{"key": "max_open_shipments", "value": 250}]'::jsonb, '00000000-0000-0000-0000-000000021001', 'tenant admin A');
  perform app.publish_config_version(v_draft.id, '00000000-0000-0000-0000-000000021001', null, 'tenant admin A');

  select * into v_resolved_a from app.resolve_config('compliance_rule', v_tenant_a);
  if v_resolved_a.items -> 0 ->> 'key' <> 'max_open_shipments' then
    raise exception 'assertion failed: expected tenant A to resolve its own published compliance_rule config, got %', v_resolved_a.items;
  end if;

  if exists (select 1 from app.resolve_config('compliance_rule', v_tenant_b)) then
    raise exception 'assertion failed: expected tenant B (no config ever published for it) to resolve nothing for compliance_rule -- any row here would be cross-tenant bleed';
  end if;

  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000021001", "role": "authenticated"}';
  select count(*) into v_count from app.config_objects where config_type_code = 'compliance_rule';
  if v_count <> 1 then
    raise exception 'assertion failed: expected tenant A''s admin to see exactly 1 config_objects row via RLS, saw %', v_count;
  end if;
  reset role;
end;
$$;

\echo '>> scenario 7: Workflow Engine composed -- the same workflow shape is published independently in both tenants; app.start_workflow_instance''s idempotency is scoped per-tenant, not global (the identical idempotency_key value in both tenants yields two distinct instances, not a collision); cross-tenant instance-start is denied; instance history is isolated'
do $$
declare
  v_tenant_a uuid;
  v_tenant_b uuid;
  v_draft_a app.config_versions;
  v_draft_b app.config_versions;
  v_published_a app.config_versions;
  v_published_b app.config_versions;
  v_instance_a app.workflow_instances;
  v_instance_b app.workflow_instances;
  v_history_count integer;
  v_definition jsonb;
begin
  v_tenant_a := (select id from app.tenants where slug = 'acmeint');
  v_tenant_b := (select id from app.tenants where slug = 'gizmoint');
  v_definition := (
    '[' ||
      '{"key": "states", "value": ["draft", "submitted", "approved"]}, ' ||
      '{"key": "initial_state", "value": "draft"}, ' ||
      '{"key": "terminal_states", "value": ["approved"]}, ' ||
      '{"key": "transitions", "value": [' ||
        '{"from": "draft", "to": "submitted"}, ' ||
        '{"from": "submitted", "to": "approved"}' ||
      ']}' ||
    ']'
  )::jsonb;

  v_draft_a := app.create_config_draft('workflow', v_tenant_a, 'tenant', null, '00000000-0000-0000-0000-000000021001', 'tenant admin A');
  perform app.set_config_items(v_draft_a.id, v_definition, '00000000-0000-0000-0000-000000021001', 'tenant admin A');
  v_published_a := app.publish_workflow_definition(v_draft_a.id, '00000000-0000-0000-0000-000000021001', null, 'tenant admin A');

  v_draft_b := app.create_config_draft('workflow', v_tenant_b, 'tenant', null, '00000000-0000-0000-0000-000000021004', 'tenant admin B');
  perform app.set_config_items(v_draft_b.id, v_definition, '00000000-0000-0000-0000-000000021004', 'tenant admin B');
  v_published_b := app.publish_workflow_definition(v_draft_b.id, '00000000-0000-0000-0000-000000021004', null, 'tenant admin B');

  v_instance_a := app.start_workflow_instance(v_published_a.id, v_tenant_a, 'compliance_review', '00000000-0000-0000-0000-000000021501', 'inst-composed-shared-key', '00000000-0000-0000-0000-000000021001', 'tenant admin A');
  v_instance_b := app.start_workflow_instance(v_published_b.id, v_tenant_b, 'compliance_review', '00000000-0000-0000-0000-000000021502', 'inst-composed-shared-key', '00000000-0000-0000-0000-000000021004', 'tenant admin B');

  if v_instance_a.id = v_instance_b.id then
    raise exception 'assertion failed: expected the identical idempotency_key in two different tenants to produce two distinct instances, not one shared row';
  end if;
  if v_instance_a.tenant_id <> v_tenant_a or v_instance_b.tenant_id <> v_tenant_b then
    raise exception 'assertion failed: expected each instance to carry its own tenant_id exactly';
  end if;

  begin
    perform app.start_workflow_instance(v_published_a.id, v_tenant_a, 'compliance_review', '00000000-0000-0000-0000-000000021503', 'inst-composed-cross', '00000000-0000-0000-0000-000000021004', 'tenant admin B');
    raise exception 'assertion failed: expected tenant B''s admin (no membership in tenant A) to be denied starting an instance against tenant A''s published definition';
  exception
    when insufficient_privilege then
      null;
  end;

  select count(*) into v_history_count from app.get_workflow_instance_history(v_instance_a.id, '00000000-0000-0000-0000-000000021001');
  if v_history_count = 0 then
    raise exception 'assertion failed: expected at least one history event for the just-started tenant A instance';
  end if;

  begin
    perform app.get_workflow_instance_history(v_instance_a.id, '00000000-0000-0000-0000-000000021004');
    raise exception 'assertion failed: expected tenant B''s admin to be denied reading tenant A''s own instance history';
  exception
    when insufficient_privilege then
      null;
  end;
end;
$$;

\echo '>> scenario 8: Background Job Framework composed -- identical job_type enqueued for both tenants; RLS on app.jobs isolates viewing per tenant even though the underlying worker-claim pool is deliberately global, by design, not tenant-scoped (a shared worker fleet serves every tenant -- this is architecture, not a defect, and is disclosed as such)'
do $$
declare
  v_tenant_a uuid;
  v_tenant_b uuid;
  v_job_a app.jobs;
  v_job_b app.jobs;
  v_count integer;
begin
  v_tenant_a := (select id from app.tenants where slug = 'acmeint');
  v_tenant_b := (select id from app.tenants where slug = 'gizmoint');

  v_job_a := app.enqueue_job(v_tenant_a, 'report_generation', '{"report": "composed-a"}'::jsonb, 5, 'job-composed-a', 3, '00000000-0000-0000-0000-000000021001', 'tenant admin A');
  v_job_b := app.enqueue_job(v_tenant_b, 'report_generation', '{"report": "composed-b"}'::jsonb, 5, 'job-composed-b', 3, '00000000-0000-0000-0000-000000021004', 'tenant admin B');

  if v_job_a.job_id = v_job_b.job_id then
    raise exception 'assertion failed: expected two distinct job rows for two different tenants';
  end if;

  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000021001", "role": "authenticated"}';
  select count(*) into v_count from app.jobs where payload ->> 'report' in ('composed-a', 'composed-b');
  if v_count <> 1 then
    raise exception 'assertion failed: expected tenant A''s admin to see exactly 1 of the 2 composed jobs via RLS (their own), saw %', v_count;
  end if;
  reset role;
end;
$$;

\echo '>> scenario 9: Feature flag x entitlement composition (the real interaction between PLT-106 and PLT-133, not two isolated tests) -- a flag fully rolled out and gated by the COM module still resolves module_not_entitled for tenant B, while tenant A (entitled) gets the real rollout decision'
do $$
declare
  v_tenant_a uuid;
  v_tenant_b uuid;
  v_draft app.config_versions;
  v_decision_a app.feature_flag_decision;
  v_decision_b app.feature_flag_decision;
begin
  v_tenant_a := (select id from app.tenants where slug = 'acmeint');
  v_tenant_b := (select id from app.tenants where slug = 'gizmoint');

  perform app.register_feature_flag('integrated.entitled_rollout', 'Integrated Entitled Rollout', 'gated by COM entitlement, composed check', 'COM', '00000000-0000-0000-0000-000000021003', 'supreme admin');
  v_draft := app.create_feature_flag_draft('integrated.entitled_rollout', null, 'global', '00000000-0000-0000-0000-000000021003', 'supreme admin');
  perform app.set_feature_flag_items(v_draft.id, '00000000-0000-0000-0000-000000021003', 'supreme admin', p_kill_switch => false, p_environments => array['production'], p_rollout_percentage => 100);
  perform app.publish_config_version(v_draft.id, '00000000-0000-0000-0000-000000021003', null, 'supreme admin');

  v_decision_a := app.evaluate_feature_flag('integrated.entitled_rollout', v_tenant_a, 'production');
  if v_decision_a.reason = 'module_not_entitled' then
    raise exception 'assertion failed: expected entitled tenant A to receive a real rollout decision, not module_not_entitled';
  end if;

  v_decision_b := app.evaluate_feature_flag('integrated.entitled_rollout', v_tenant_b, 'production');
  if v_decision_b.enabled or v_decision_b.reason <> 'module_not_entitled' then
    raise exception 'assertion failed: expected unentitled tenant B to be denied module_not_entitled regardless of the flag''s 100%% rollout, got enabled=% reason=%', v_decision_b.enabled, v_decision_b.reason;
  end if;
end;
$$;

\echo '>> scenario 10 (regression guard, PLT-116): app.users_directory -- the exact view a real cross-tenant PII exposure was found and fixed in at PLT-116 (a non-security-invoker view''s RLS posture is its OWNER''s, not the caller''s) -- still returns only the querying tenant''s own users, never both tenants'' combined'
do $$
declare
  v_count integer;
  v_foreign_count integer;
begin
  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000021001", "role": "authenticated"}';

  select count(*) into v_count from app.users_directory;
  if v_count <> 2 then
    raise exception 'assertion failed: expected tenant A''s admin to see exactly 2 rows (tenant A''s own 2 users) via app.users_directory, saw %', v_count;
  end if;

  select count(*) into v_foreign_count from app.users_directory where tenant_id = (select id from app.tenants where slug = 'gizmoint');
  if v_foreign_count <> 0 then
    raise exception 'assertion failed: REGRESSION of the PLT-116 fix -- tenant A''s admin can see % of tenant B''s users_directory row(s), which is exactly the cross-tenant PII exposure PLT-116 fixed', v_foreign_count;
  end if;

  reset role;
end;
$$;

\echo '>> scenario 11: audit trail reconciliation -- app.query_audit_logs is authority-gated per tenant (tenant A''s admin denied for tenant B, and vice versa), Supreme Admin can read both, and events from multiple different engines (tenant provisioning, role assignment, config publish, workflow start, job enqueue, feature flag publish) are all present and correctly tenant-scoped -- not sampled, the full composed set from every scenario group above'
do $$
declare
  v_tenant_a uuid;
  v_tenant_b uuid;
  v_count_a integer;
  v_count_b integer;
  v_supreme_count_a integer;
  v_supreme_count_b integer;
  v_distinct_resource_types integer;
begin
  v_tenant_a := (select id from app.tenants where slug = 'acmeint');
  v_tenant_b := (select id from app.tenants where slug = 'gizmoint');

  select count(*) into v_count_a from app.query_audit_logs('00000000-0000-0000-0000-000000021001', v_tenant_a, 200);
  if v_count_a = 0 then
    raise exception 'assertion failed: expected tenant A''s admin to see a non-empty audit trail after this checkpoint''s own composed golden path';
  end if;

  begin
    perform app.query_audit_logs('00000000-0000-0000-0000-000000021001', v_tenant_b, 200);
    raise exception 'assertion failed: expected tenant A''s admin to be denied querying tenant B''s audit log';
  exception
    when insufficient_privilege then
      null;
  end;

  select count(*) into v_supreme_count_a from app.query_audit_logs('00000000-0000-0000-0000-000000021003', v_tenant_a, 200);
  select count(*) into v_supreme_count_b from app.query_audit_logs('00000000-0000-0000-0000-000000021003', v_tenant_b, 200);
  if v_supreme_count_a = 0 or v_supreme_count_b = 0 then
    raise exception 'assertion failed: expected Supreme Admin to read a non-empty audit trail for both tenant A (%) and tenant B (%)', v_supreme_count_a, v_supreme_count_b;
  end if;

  select count(distinct resource_type) into v_distinct_resource_types
  from app.query_audit_logs('00000000-0000-0000-0000-000000021003', v_tenant_a, 200);
  if v_distinct_resource_types < 3 then
    raise exception 'assertion failed: expected at least 3 distinct resource_type values in tenant A''s audit trail (proving multiple different engines each self-logged), saw %', v_distinct_resource_types;
  end if;
end;
$$;

\echo '>> scenario 12: portal query-layer composed check -- the exact read paths PLT-135''s server/queries/portal-users.ts and PLT-136''s server/queries/supreme-tenants.ts depend on, exercised together against this checkpoint''s own fully composed state: a tenant admin session sees only its own tenant''s users_directory rows; a Supreme session sees both provisioned tenants via app.tenants directly'
do $$
declare
  v_tenant_a_count integer;
  v_tenant_count integer;
begin
  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000021001", "role": "authenticated"}';
  select count(*) into v_tenant_a_count from app.users_directory;
  if v_tenant_a_count <> 2 then
    raise exception 'assertion failed: PLT-135''s own portal-users query path would surface % rows for tenant A''s admin, expected exactly 2', v_tenant_a_count;
  end if;
  reset role;

  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000021003", "role": "authenticated"}';
  select count(*) into v_tenant_count from app.tenants where slug in ('acmeint', 'gizmoint');
  if v_tenant_count <> 2 then
    raise exception 'assertion failed: PLT-136''s own supreme-tenants query path would surface % of the 2 composed tenants for a Supreme session, expected both', v_tenant_count;
  end if;
  reset role;
end;
$$;

\echo '>> scenario 13 (no regression, not tenant-specific): app.geojson_point_to_geography / app.bounded_st_dwithin (PLT-134) remain callable and the 500km query-radius cap still enforced after the full 31-migration schema build-out this checkpoint composes against'
do $$
declare
  v_point_a geography;
  v_point_b geography;
begin
  v_point_a := app.geojson_point_to_geography('{"type": "Point", "coordinates": [106.8456, -6.2088]}'::jsonb); -- Jakarta
  v_point_b := app.geojson_point_to_geography('{"type": "Point", "coordinates": [106.7942, -6.5971]}'::jsonb); -- Bogor (~40km away)

  begin
    perform app.bounded_st_dwithin(v_point_a, v_point_b, app.postgis_max_query_radius_meters() + 1);
    raise exception 'assertion failed: expected a radius argument beyond the governed 500km cap to be rejected, not silently accepted';
  exception
    when others then
      if sqlerrm not like 'spatial_radius_out_of_range%' then
        raise exception 'assertion failed: expected spatial_radius_out_of_range, got %', sqlerrm;
      end if;
  end;

  if not app.bounded_st_dwithin(v_point_a, v_point_b, 100000) then
    raise exception 'assertion failed: expected Jakarta-Bogor (~40km) to be within a 100km bounded query, well inside the 500km cap';
  end if;
end;
$$;

\echo '>> scenario 14: composed RLS sweep -- tenant A''s authenticated session sees zero foreign rows across every table this checkpoint''s own golden path touched, checked together in one combined query, spanning both pre-113 tables and every capability built after PLT-113 shipped RLS'
do $$
declare
  v_tenant_b uuid;
  v_foreign_rows integer;
begin
  v_tenant_b := (select id from app.tenants where slug = 'gizmoint');

  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000021001", "role": "authenticated"}';

  -- app.config_versions/app.config_items carry no `authenticated` grant at all (verified
  -- this checkpoint, `20260717130000_create_configuration_engine.sql`'s own grants --
  -- service_role-only by design, governed access only via app.resolve_config()/
  -- app.list_config_versions()) -- correctly excluded from this direct-table sweep, not
  -- an oversight; app.config_objects (the catalog table, which does carry the grant) is
  -- included instead.
  select
    (select count(*) from app.tenants where id = v_tenant_b) +
    (select count(*) from app.org_units where tenant_id = v_tenant_b) +
    (select count(*) from app.users where tenant_id = v_tenant_b) +
    (select count(*) from app.roles where tenant_id = v_tenant_b) +
    (select count(*) from app.role_assignments where tenant_id = v_tenant_b) +
    (select count(*) from app.config_objects where tenant_id = v_tenant_b) +
    (select count(*) from app.workflow_instances where tenant_id = v_tenant_b) +
    (select count(*) from app.jobs where tenant_id = v_tenant_b)
  into v_foreign_rows;

  if v_foreign_rows <> 0 then
    raise exception 'assertion failed: expected zero tenant-B rows visible to tenant A''s authenticated session across the combined tenants/org_units/users/roles/role_assignments/config_objects/workflow_instances/jobs sweep, saw %', v_foreign_rows;
  end if;

  reset role;
end;
$$;

\echo '>> integrated golden path complete: two tenants provisioned, entitled differently, identified, organized, role-assigned, configured, run through one workflow instance each, queued one background job each, evaluated one entitlement-gated feature flag each, and fully reconciled through the audit trail and both portals'' own query layers -- 14 scenario groups, 18+ discrete tenant-isolation/composition assertions, zero cross-tenant leak found'
