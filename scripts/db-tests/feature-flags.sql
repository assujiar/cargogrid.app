-- Real, executable test evidence for PLT-133 (Feature Flags, CG-S6-PLT-030) -- see
-- scripts/db-tests/config.sql's own header for the general pattern this file follows.

\set ON_ERROR_STOP on

\echo '>> setup: two tenants each with a tenant_admin and a regular org_user, a global Supreme Admin, and a published entitlement package granting only COM to acmeflag'
do $$
declare
  v_tenant_id uuid;
  v_other_tenant_id uuid;
  v_pkg_id uuid;
begin
  insert into auth.users (id, email) values
    ('00000000-0000-0000-0000-000000005001', 'tenantadminflag@example.test'),
    ('00000000-0000-0000-0000-000000005002', 'regularuserflag@example.test'),
    ('00000000-0000-0000-0000-000000005003', 'supremeflag@example.test'),
    ('00000000-0000-0000-0000-000000005004', 'othertenantadminflag@example.test');

  perform app.provision_tenant('acmeflag', 'Acme Flag Co', 'idem-acmeflag', 'tester');
  v_tenant_id := (select id from app.tenants where slug = 'acmeflag');
  perform app.transition_tenant_status(v_tenant_id, 'active', 'setup', 'tester');
  perform app.invite_user(v_tenant_id, '00000000-0000-0000-0000-000000005001', 'tenantadminflag@example.test', 'Tenant Admin', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'tenantadminflag@example.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000005001', 'tenant_admin', v_tenant_id, null, 'tester');

  perform app.invite_user(v_tenant_id, '00000000-0000-0000-0000-000000005002', 'regularuserflag@example.test', 'Regular User', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'regularuserflag@example.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000005002', 'org_user', v_tenant_id, null, 'tester');

  perform app.grant_principal_membership('00000000-0000-0000-0000-000000005003', 'supreme_admin', null, null, 'tester');

  perform app.provision_tenant('gizmoflag', 'Gizmo Flag Co', 'idem-gizmoflag', 'tester');
  v_other_tenant_id := (select id from app.tenants where slug = 'gizmoflag');
  perform app.transition_tenant_status(v_other_tenant_id, 'active', 'setup', 'tester');
  perform app.invite_user(v_other_tenant_id, '00000000-0000-0000-0000-000000005004', 'othertenantadminflag@example.test', 'Other Tenant Admin', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'othertenantadminflag@example.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000005004', 'tenant_admin', v_other_tenant_id, null, 'tester');

  insert into app.entitlement_packages (code, name, version, status, granted_modules, feature_limits)
  values ('flag-professional', 'Flag Professional', 1, 'published', array['COM'], '{}'::jsonb)
  returning id into v_pkg_id;
  perform app.assign_entitlement(v_tenant_id, v_pkg_id, 'active', 'onboarding', 'tester');
  -- gizmoflag deliberately receives no entitlement assignment at all (module_not_entitled coverage).
end;
$$;

\echo '>> app.register_feature_flag: Supreme-Admin-only, idempotent, rejects an unknown module_code'
do $$
declare
  v_registered1 app.feature_flags;
  v_registered2 app.feature_flags;
begin
  begin
    perform app.register_feature_flag('platform.example_rollout', 'Example Rollout', 'synthetic example flag', null, '00000000-0000-0000-0000-000000005001', 'tenant admin');
    raise exception 'assertion failed: expected a tenant_admin (not Supreme Admin) to be denied registering a feature flag';
  exception
    when insufficient_privilege then
      null;
  end;

  begin
    perform app.register_feature_flag('platform.bad_module', 'Bad Module', null, 'NOPE', '00000000-0000-0000-0000-000000005003', 'supreme admin');
    raise exception 'assertion failed: expected an unknown module_code to be rejected';
  exception
    when no_data_found then
      null;
  end;

  v_registered1 := app.register_feature_flag('platform.example_rollout', 'Example Rollout', 'synthetic example flag', null, '00000000-0000-0000-0000-000000005003', 'supreme admin');
  v_registered2 := app.register_feature_flag('platform.example_rollout', 'Example Rollout', 'synthetic example flag', null, '00000000-0000-0000-0000-000000005003', 'supreme admin');
  if v_registered1.flag_key <> v_registered2.flag_key then
    raise exception 'assertion failed: expected a repeated registration to be idempotent';
  end if;

  if not exists (select 1 from app.config_types where code = 'feature:platform.example_rollout') then
    raise exception 'assertion failed: expected register_feature_flag to mint its own dedicated config_type';
  end if;

  perform app.register_feature_flag('platform.entitled_rollout', 'Entitled Rollout', 'gated by COM entitlement', 'COM', '00000000-0000-0000-0000-000000005003', 'supreme admin');
end;
$$;

\echo '>> app.create_feature_flag_draft: rejects an unknown flag_key and any scope beyond global/tenant; authority-gated (Supreme for global, tenant_admin/Supreme for tenant)'
do $$
declare
  v_tenant_id uuid;
begin
  v_tenant_id := (select id from app.tenants where slug = 'acmeflag');

  begin
    perform app.create_feature_flag_draft('platform.does_not_exist', null, 'global', '00000000-0000-0000-0000-000000005003', 'supreme admin');
    raise exception 'assertion failed: expected an unknown flag_key to be rejected';
  exception
    when no_data_found then
      null;
  end;

  begin
    perform app.create_feature_flag_draft('platform.example_rollout', v_tenant_id, 'role', '00000000-0000-0000-0000-000000005003', 'supreme admin');
    raise exception 'assertion failed: expected a scope_level outside global/tenant to be rejected';
  exception
    when check_violation then
      null;
  end;

  begin
    perform app.create_feature_flag_draft('platform.example_rollout', null, 'global', '00000000-0000-0000-0000-000000005001', 'tenant admin');
    raise exception 'assertion failed: expected a tenant_admin (not Supreme Admin) to be denied a global-scope draft';
  exception
    when insufficient_privilege then
      null;
  end;

  begin
    perform app.create_feature_flag_draft('platform.example_rollout', v_tenant_id, 'tenant', '00000000-0000-0000-0000-000000005002', 'regular user');
    raise exception 'assertion failed: expected a regular org_user to be denied a tenant-scope draft';
  exception
    when insufficient_privilege then
      null;
  end;
end;
$$;

\echo '>> app.set_feature_flag_items: global scope requires a full validated dimension set; kill_switch/environments are structurally rejected at tenant scope'
do $$
declare
  v_tenant_id uuid;
  v_global_draft app.config_versions;
  v_tenant_draft app.config_versions;
  v_count integer;
begin
  v_tenant_id := (select id from app.tenants where slug = 'acmeflag');

  v_global_draft := app.create_feature_flag_draft('platform.example_rollout', null, 'global', '00000000-0000-0000-0000-000000005003', 'supreme admin');

  begin
    perform app.set_feature_flag_items(v_global_draft.id, '00000000-0000-0000-0000-000000005003', 'supreme admin', p_rollout_percentage => 150);
    raise exception 'assertion failed: expected rollout_percentage=150 to be rejected';
  exception
    when check_violation then
      null;
  end;

  begin
    perform app.set_feature_flag_items(v_global_draft.id, '00000000-0000-0000-0000-000000005003', 'supreme admin', p_environments => array['moon_base']);
    raise exception 'assertion failed: expected an unknown environment to be rejected';
  exception
    when check_violation then
      null;
  end;

  begin
    perform app.set_feature_flag_items(v_global_draft.id, '00000000-0000-0000-0000-000000005003', 'supreme admin', p_tenant_state => 'allow');
    raise exception 'assertion failed: expected tenant_state to be rejected at global scope';
  exception
    when check_violation then
      null;
  end;

  v_count := app.set_feature_flag_items(
    v_global_draft.id, '00000000-0000-0000-0000-000000005003', 'supreme admin',
    p_kill_switch => false, p_environments => array['production', 'staging'], p_rollout_percentage => 0, p_cohorts => array[]::text[]
  );
  if v_count <> 4 then
    raise exception 'assertion failed: expected exactly 4 global dimension items, saw %', v_count;
  end if;
  perform app.publish_config_version(v_global_draft.id, '00000000-0000-0000-0000-000000005003', null, 'supreme admin');

  v_tenant_draft := app.create_feature_flag_draft('platform.example_rollout', v_tenant_id, 'tenant', '00000000-0000-0000-0000-000000005001', 'tenant admin');

  begin
    perform app.set_feature_flag_items(v_tenant_draft.id, '00000000-0000-0000-0000-000000005001', 'tenant admin', p_kill_switch => true);
    raise exception 'assertion failed: expected kill_switch to be structurally rejected at tenant scope';
  exception
    when check_violation then
      null;
  end;

  begin
    perform app.set_feature_flag_items(v_tenant_draft.id, '00000000-0000-0000-0000-000000005001', 'tenant admin', p_environments => array['production']);
    raise exception 'assertion failed: expected environments to be structurally rejected at tenant scope';
  exception
    when check_violation then
      null;
  end;

  begin
    perform app.set_feature_flag_items(v_tenant_draft.id, '00000000-0000-0000-0000-000000005001', 'tenant admin', p_tenant_state => 'sideways');
    raise exception 'assertion failed: expected an invalid tenant_state to be rejected';
  exception
    when check_violation then
      null;
  end;

  perform app.discard_config_draft(v_tenant_draft.id, '00000000-0000-0000-0000-000000005001', 'cleanup, exercised structural rejection only', 'tenant admin');
end;
$$;

\echo '>> app.evaluate_feature_flag: unknown flag and unconfigured (registered, never published) both fail safe-default closed'
do $$
declare
  v_tenant_id uuid;
  v_decision app.feature_flag_decision;
begin
  v_tenant_id := (select id from app.tenants where slug = 'acmeflag');

  v_decision := app.evaluate_feature_flag('platform.does_not_exist', v_tenant_id, 'production');
  if v_decision.enabled or v_decision.reason <> 'unknown_flag' then
    raise exception 'assertion failed: expected unknown_flag, got enabled=% reason=%', v_decision.enabled, v_decision.reason;
  end if;

  perform app.register_feature_flag('platform.never_published', 'Never Published', null, null, '00000000-0000-0000-0000-000000005003', 'supreme admin');
  v_decision := app.evaluate_feature_flag('platform.never_published', v_tenant_id, 'production');
  if v_decision.enabled or v_decision.reason <> 'unconfigured' then
    raise exception 'assertion failed: expected unconfigured, got enabled=% reason=%', v_decision.enabled, v_decision.reason;
  end if;
end;
$$;

\echo '>> app.evaluate_feature_flag: environment gate, then deterministic rollout bucketing at 100%% and 0%%'
do $$
declare
  v_tenant_id uuid;
  v_decision app.feature_flag_decision;
  v_draft app.config_versions;
begin
  v_tenant_id := (select id from app.tenants where slug = 'acmeflag');

  v_decision := app.evaluate_feature_flag('platform.example_rollout', v_tenant_id, 'sandbox');
  if v_decision.enabled or v_decision.reason <> 'environment_gate' then
    raise exception 'assertion failed: expected environment_gate for an environment outside {production, staging}, got enabled=% reason=%', v_decision.enabled, v_decision.reason;
  end if;

  v_decision := app.evaluate_feature_flag('platform.example_rollout', v_tenant_id, 'production');
  if v_decision.enabled or v_decision.reason <> 'default' then
    raise exception 'assertion failed: expected reason=default at rollout_percentage=0, got enabled=% reason=%', v_decision.enabled, v_decision.reason;
  end if;

  v_draft := app.create_feature_flag_draft('platform.example_rollout', null, 'global', '00000000-0000-0000-0000-000000005003', 'supreme admin');
  perform app.set_feature_flag_items(v_draft.id, '00000000-0000-0000-0000-000000005003', 'supreme admin', p_kill_switch => false, p_environments => array['production', 'staging'], p_rollout_percentage => 100, p_cohorts => array[]::text[]);
  perform app.publish_config_version(v_draft.id, '00000000-0000-0000-0000-000000005003', null, 'supreme admin');

  v_decision := app.evaluate_feature_flag('platform.example_rollout', v_tenant_id, 'production');
  if not v_decision.enabled or v_decision.reason <> 'rollout_bucket' or v_decision.resolved_scope_level <> 'global' then
    raise exception 'assertion failed: expected enabled=true reason=rollout_bucket scope=global at rollout_percentage=100, got enabled=% reason=% scope=%', v_decision.enabled, v_decision.reason, v_decision.resolved_scope_level;
  end if;

  -- Determinism: repeated evaluation for the same tenant+flag always buckets identically.
  if v_decision.enabled <> (app.evaluate_feature_flag('platform.example_rollout', v_tenant_id, 'production')).enabled then
    raise exception 'assertion failed: expected repeated evaluation to be deterministic';
  end if;
  if app.feature_flag_bucket(v_tenant_id, 'platform.example_rollout') < 0 or app.feature_flag_bucket(v_tenant_id, 'platform.example_rollout') > 99 then
    raise exception 'assertion failed: expected feature_flag_bucket in [0, 99]';
  end if;
end;
$$;

\echo '>> app.evaluate_feature_flag: cohort targeting -- a non-empty cohort list requires an intersection with the caller''s cohorts'
do $$
declare
  v_tenant_id uuid;
  v_draft app.config_versions;
  v_decision app.feature_flag_decision;
begin
  v_tenant_id := (select id from app.tenants where slug = 'acmeflag');

  v_draft := app.create_feature_flag_draft('platform.example_rollout', null, 'global', '00000000-0000-0000-0000-000000005003', 'supreme admin');
  perform app.set_feature_flag_items(v_draft.id, '00000000-0000-0000-0000-000000005003', 'supreme admin', p_kill_switch => false, p_environments => array['production', 'staging'], p_rollout_percentage => 100, p_cohorts => array['beta_testers']);
  perform app.publish_config_version(v_draft.id, '00000000-0000-0000-0000-000000005003', null, 'supreme admin');

  v_decision := app.evaluate_feature_flag('platform.example_rollout', v_tenant_id, 'production', array['general']::text[]);
  if v_decision.enabled or v_decision.reason <> 'cohort_mismatch' then
    raise exception 'assertion failed: expected cohort_mismatch when caller cohorts do not intersect the flag''s cohorts, got enabled=% reason=%', v_decision.enabled, v_decision.reason;
  end if;

  v_decision := app.evaluate_feature_flag('platform.example_rollout', v_tenant_id, 'production', array['beta_testers']::text[]);
  if not v_decision.enabled or v_decision.reason <> 'rollout_bucket' then
    raise exception 'assertion failed: expected an intersecting cohort to pass through to rollout bucketing, got enabled=% reason=%', v_decision.enabled, v_decision.reason;
  end if;

  -- Restore an unrestricted-cohort published version for the tests below.
  v_draft := app.create_feature_flag_draft('platform.example_rollout', null, 'global', '00000000-0000-0000-0000-000000005003', 'supreme admin');
  perform app.set_feature_flag_items(v_draft.id, '00000000-0000-0000-0000-000000005003', 'supreme admin', p_kill_switch => false, p_environments => array['production', 'staging'], p_rollout_percentage => 100, p_cohorts => array[]::text[]);
  perform app.publish_config_version(v_draft.id, '00000000-0000-0000-0000-000000005003', null, 'supreme admin');
end;
$$;

\echo '>> app.evaluate_feature_flag: tenant override -- deny/allow win over rollout; cross-tenant isolation; kill_switch is non-overridable at tenant scope'
do $$
declare
  v_tenant_id uuid;
  v_other_tenant_id uuid;
  v_tenant_draft app.config_versions;
  v_decision app.feature_flag_decision;
  v_kill_draft app.config_versions;
begin
  v_tenant_id := (select id from app.tenants where slug = 'acmeflag');
  v_other_tenant_id := (select id from app.tenants where slug = 'gizmoflag');

  -- gizmoflag has no tenant-level override; it sees the plain global result.
  v_decision := app.evaluate_feature_flag('platform.example_rollout', v_other_tenant_id, 'production');
  if not v_decision.enabled or v_decision.resolved_scope_level <> 'global' then
    raise exception 'assertion failed: expected gizmoflag to see the unmodified global rollout, got enabled=% scope=%', v_decision.enabled, v_decision.resolved_scope_level;
  end if;

  v_tenant_draft := app.create_feature_flag_draft('platform.example_rollout', v_tenant_id, 'tenant', '00000000-0000-0000-0000-000000005001', 'tenant admin');
  perform app.set_feature_flag_items(v_tenant_draft.id, '00000000-0000-0000-0000-000000005001', 'tenant admin', p_tenant_state => 'deny');
  perform app.publish_config_version(v_tenant_draft.id, '00000000-0000-0000-0000-000000005001', null, 'tenant admin');

  v_decision := app.evaluate_feature_flag('platform.example_rollout', v_tenant_id, 'production');
  if v_decision.enabled or v_decision.reason <> 'tenant_override_deny' or v_decision.resolved_scope_level <> 'tenant' then
    raise exception 'assertion failed: expected acmeflag''s tenant_state=deny to win over a 100%% global rollout, got enabled=% reason=% scope=%', v_decision.enabled, v_decision.reason, v_decision.resolved_scope_level;
  end if;

  -- gizmoflag remains unaffected by acmeflag's own tenant override (cross-tenant isolation).
  v_decision := app.evaluate_feature_flag('platform.example_rollout', v_other_tenant_id, 'production');
  if not v_decision.enabled or v_decision.resolved_scope_level <> 'global' then
    raise exception 'assertion failed: expected gizmoflag to remain unaffected by acmeflag''s own tenant-scoped deny override';
  end if;

  -- Even a global kill_switch cannot be un-killed by any tenant_state=allow override.
  v_kill_draft := app.create_feature_flag_draft('platform.example_rollout', null, 'global', '00000000-0000-0000-0000-000000005003', 'supreme admin');
  perform app.set_feature_flag_items(v_kill_draft.id, '00000000-0000-0000-0000-000000005003', 'supreme admin', p_kill_switch => true, p_environments => array['production', 'staging'], p_rollout_percentage => 100, p_cohorts => array[]::text[]);
  perform app.publish_config_version(v_kill_draft.id, '00000000-0000-0000-0000-000000005003', null, 'supreme admin');

  v_tenant_draft := app.create_feature_flag_draft('platform.example_rollout', v_tenant_id, 'tenant', '00000000-0000-0000-0000-000000005001', 'tenant admin');
  perform app.set_feature_flag_items(v_tenant_draft.id, '00000000-0000-0000-0000-000000005001', 'tenant admin', p_tenant_state => 'allow');
  perform app.publish_config_version(v_tenant_draft.id, '00000000-0000-0000-0000-000000005001', null, 'tenant admin');

  v_decision := app.evaluate_feature_flag('platform.example_rollout', v_tenant_id, 'production');
  if v_decision.enabled or v_decision.reason <> 'kill_switch' then
    raise exception 'assertion failed: expected the global kill_switch to win over acmeflag''s own tenant_state=allow override, got enabled=% reason=%', v_decision.enabled, v_decision.reason;
  end if;

  -- Restore a live (non-killed, 100%%, unrestricted) global version for the remaining tests.
  v_kill_draft := app.create_feature_flag_draft('platform.example_rollout', null, 'global', '00000000-0000-0000-0000-000000005003', 'supreme admin');
  perform app.set_feature_flag_items(v_kill_draft.id, '00000000-0000-0000-0000-000000005003', 'supreme admin', p_kill_switch => false, p_environments => array['production', 'staging'], p_rollout_percentage => 100, p_cohorts => array[]::text[]);
  perform app.publish_config_version(v_kill_draft.id, '00000000-0000-0000-0000-000000005003', null, 'supreme admin');
end;
$$;

\echo '>> app.evaluate_feature_flag: module-gated flags fail closed for a tenant with no entitlement for that module'
do $$
declare
  v_tenant_id uuid;
  v_other_tenant_id uuid;
  v_draft app.config_versions;
  v_decision app.feature_flag_decision;
begin
  v_tenant_id := (select id from app.tenants where slug = 'acmeflag');
  v_other_tenant_id := (select id from app.tenants where slug = 'gizmoflag');

  v_draft := app.create_feature_flag_draft('platform.entitled_rollout', null, 'global', '00000000-0000-0000-0000-000000005003', 'supreme admin');
  perform app.set_feature_flag_items(v_draft.id, '00000000-0000-0000-0000-000000005003', 'supreme admin', p_kill_switch => false, p_environments => array['production'], p_rollout_percentage => 100, p_cohorts => array[]::text[]);
  perform app.publish_config_version(v_draft.id, '00000000-0000-0000-0000-000000005003', null, 'supreme admin');

  -- acmeflag holds an active COM entitlement (setup) -- the flag evaluates normally.
  v_decision := app.evaluate_feature_flag('platform.entitled_rollout', v_tenant_id, 'production');
  if not v_decision.enabled or v_decision.reason <> 'rollout_bucket' then
    raise exception 'assertion failed: expected acmeflag (COM entitled) to pass through to rollout bucketing, got enabled=% reason=%', v_decision.enabled, v_decision.reason;
  end if;

  -- gizmoflag holds no entitlement assignment at all -- module_not_entitled must fail closed regardless of a 100%% rollout.
  v_decision := app.evaluate_feature_flag('platform.entitled_rollout', v_other_tenant_id, 'production');
  if v_decision.enabled or v_decision.reason <> 'module_not_entitled' then
    raise exception 'assertion failed: expected gizmoflag (no COM entitlement) to be denied module_not_entitled even at a 100%% rollout, got enabled=% reason=%', v_decision.enabled, v_decision.reason;
  end if;
end;
$$;

\echo '>> app.kill_feature_flag: Supreme-Admin-only; forces kill_switch=true while preserving the other published dimensions'
do $$
declare
  v_tenant_id uuid;
  v_before app.feature_flag_decision;
  v_result app.config_versions;
  v_after app.feature_flag_decision;
  v_environments jsonb;
begin
  v_tenant_id := (select id from app.tenants where slug = 'gizmoflag');

  v_before := app.evaluate_feature_flag('platform.example_rollout', v_tenant_id, 'production');
  if not v_before.enabled then
    raise exception 'assertion failed (test setup bug): expected platform.example_rollout to be enabled for gizmoflag before the kill';
  end if;

  begin
    perform app.kill_feature_flag('platform.example_rollout', '00000000-0000-0000-0000-000000005001', 'incident', 'tenant admin');
    raise exception 'assertion failed: expected a tenant_admin (not Supreme Admin) to be denied killing a global feature flag';
  exception
    when insufficient_privilege then
      null;
  end;

  v_result := app.kill_feature_flag('platform.example_rollout', '00000000-0000-0000-0000-000000005003', 'incident: unexpected error rate spike', 'supreme admin');
  if v_result.status <> 'published' then
    raise exception 'assertion failed: expected kill_feature_flag to publish a new version, got status=%', v_result.status;
  end if;

  select ci.value into v_environments from app.config_items ci where ci.config_version_id = v_result.id and ci.key = 'environments';
  if v_environments <> '["production", "staging"]'::jsonb then
    raise exception 'assertion failed: expected kill_feature_flag to preserve the prior published environments, saw %', v_environments;
  end if;

  v_after := app.evaluate_feature_flag('platform.example_rollout', v_tenant_id, 'production');
  if v_after.enabled or v_after.reason <> 'kill_switch' then
    raise exception 'assertion failed: expected the flag to be disabled (kill_switch) for every tenant immediately after kill_feature_flag, got enabled=% reason=%', v_after.enabled, v_after.reason;
  end if;

  -- app.rollback_config_version (reused from PLT-121) un-kills by publishing a fresh
  -- version cloned from the pre-kill snapshot -- never mutating either version.
  perform app.rollback_config_version(v_before.resolved_version_id, '00000000-0000-0000-0000-000000005003', 'incident resolved, reverting the kill', 'supreme admin');
  v_after := app.evaluate_feature_flag('platform.example_rollout', v_tenant_id, 'production');
  if not v_after.enabled or v_after.reason <> 'rollout_bucket' then
    raise exception 'assertion failed: expected the rollback to restore the pre-kill enabled state, got enabled=% reason=%', v_after.enabled, v_after.reason;
  end if;
end;
$$;

\echo '>> app.debug_feature_flag: privileged, authority-gated identically to app.check_config_object_authority''s own split; returns the same decision as app.evaluate_feature_flag'
do $$
declare
  v_tenant_id uuid;
  v_expected app.feature_flag_decision;
  v_debug app.feature_flag_decision;
begin
  v_tenant_id := (select id from app.tenants where slug = 'acmeflag');

  begin
    perform app.debug_feature_flag('platform.example_rollout', v_tenant_id, 'production', array[]::text[], '00000000-0000-0000-0000-000000005002', 'regular user');
    raise exception 'assertion failed: expected a regular org_user to be denied tenant-scoped debug access';
  exception
    when insufficient_privilege then
      null;
  end;

  begin
    perform app.debug_feature_flag('platform.example_rollout', null, 'production', array[]::text[], '00000000-0000-0000-0000-000000005001', 'tenant admin');
    raise exception 'assertion failed: expected a tenant_admin to be denied platform-wide (tenant_id null) debug access';
  exception
    when insufficient_privilege then
      null;
  end;

  v_expected := app.evaluate_feature_flag('platform.example_rollout', v_tenant_id, 'production');
  v_debug := app.debug_feature_flag('platform.example_rollout', v_tenant_id, 'production', array[]::text[], '00000000-0000-0000-0000-000000005001', 'tenant admin');
  if v_debug.enabled <> v_expected.enabled or v_debug.reason <> v_expected.reason then
    raise exception 'assertion failed: expected debug_feature_flag to return the identical decision app.evaluate_feature_flag would, got enabled=%/% reason=%/%', v_debug.enabled, v_expected.enabled, v_debug.reason, v_expected.reason;
  end if;

  v_debug := app.debug_feature_flag('platform.example_rollout', v_tenant_id, 'production', array[]::text[], '00000000-0000-0000-0000-000000005003', 'supreme admin');
  if v_debug.enabled <> v_expected.enabled then
    raise exception 'assertion failed: expected Supreme Admin to also be able to debug a tenant-scoped evaluation';
  end if;
end;
$$;

\echo '>> every privileged/lifecycle action self-captures a canonical app.audit_logs entry'
do $$
declare
  v_actions text[] := array['register_feature_flag', 'set_feature_flag_items', 'kill_feature_flag', 'debug_feature_flag'];
  v_action text;
  v_count integer;
begin
  foreach v_action in array v_actions loop
    select count(*) into v_count from app.audit_logs where action = v_action;
    if v_count = 0 then
      raise exception 'assertion failed: expected at least one app.audit_logs entry for action=%, saw none', v_action;
    end if;
  end loop;
end;
$$;

\echo '>> schema-privilege defense in depth: authenticated has no direct access to draft-bearing config tables; anon is denied entirely; anon holds no EXECUTE on service_role-only mutations'
do $$
declare
  v_has_privilege boolean;
begin
  select has_table_privilege('authenticated', 'app.feature_flags', 'SELECT') into v_has_privilege;
  if not v_has_privilege then
    raise exception 'assertion failed: expected authenticated to hold SELECT on app.feature_flags (platform reference data)';
  end if;

  select has_table_privilege('anon', 'app.feature_flags', 'SELECT') into v_has_privilege;
  if v_has_privilege then
    raise exception 'assertion failed: expected anon to hold no privilege on app.feature_flags at all';
  end if;

  select has_function_privilege('authenticated', 'app.evaluate_feature_flag(text, uuid, text, text[], timestamptz)', 'EXECUTE') into v_has_privilege;
  if not v_has_privilege then
    raise exception 'assertion failed: expected authenticated to hold EXECUTE on app.evaluate_feature_flag';
  end if;

  select has_function_privilege('anon', 'app.evaluate_feature_flag(text, uuid, text, text[], timestamptz)', 'EXECUTE') into v_has_privilege;
  if v_has_privilege then
    raise exception 'assertion failed: expected anon to hold no EXECUTE on app.evaluate_feature_flag (no pre-authentication use case)';
  end if;

  select has_function_privilege('anon', 'app.kill_feature_flag(text, uuid, text, text)', 'EXECUTE') into v_has_privilege;
  if v_has_privilege then
    raise exception 'assertion failed: expected anon to hold no EXECUTE on the service_role-only app.kill_feature_flag (ERR-2026-004 regression guard)';
  end if;

  select has_function_privilege('anon', 'app.set_feature_flag_items(uuid, uuid, text, boolean, text[], integer, text[], text)', 'EXECUTE') into v_has_privilege;
  if v_has_privilege then
    raise exception 'assertion failed: expected anon to hold no EXECUTE on the service_role-only app.set_feature_flag_items (ERR-2026-004 regression guard)';
  end if;
end;
$$;
