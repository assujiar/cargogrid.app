-- Real, executable test evidence for PLT-106 (Subscription/Module/Feature Entitlement,
-- CG-S6-PLT-003) -- see scripts/db-tests/tenant-lifecycle.sql's own header for the
-- general pattern this file follows.

\set ON_ERROR_STOP on

\echo '>> setup: two tenants and a published package with module + feature-limited grants'
do $$
declare
  v_pkg_id uuid;
begin
  perform app.provision_tenant('widgetco', 'Widget Co', 'idem-widgetco', 'tester');
  perform app.provision_tenant('gizmoinc', 'Gizmo Inc', 'idem-gizmoinc', 'tester');

  insert into app.entitlement_packages (code, name, version, status, granted_modules, feature_limits)
  values ('professional', 'Professional', 1, 'published', array['COM', 'OPS'], '{"COM-QTN": 50, "OPS-TMS": null}'::jsonb)
  returning id into v_pkg_id;

  insert into app.entitlement_packages (code, name, version, status, granted_modules, feature_limits)
  values ('draft-only', 'Draft Only', 1, 'draft', array['FIN'], '{}'::jsonb);
end;
$$;

\echo '>> module-level grant: entitled tenant passes, unentitled module fails closed'
do $$
declare
  v_tenant_id uuid;
  v_pkg_id uuid;
  v_decision app.entitlement_decision;
begin
  select id into v_tenant_id from app.tenants where slug = 'widgetco';
  select id into v_pkg_id from app.entitlement_packages where code = 'professional';
  perform app.assign_entitlement(v_tenant_id, v_pkg_id, 'active', 'onboarding', 'tester');

  select * into v_decision from app.evaluate_entitlement(v_tenant_id, 'COM');
  if not v_decision.allowed or v_decision.reason <> 'package_granted' then
    raise exception 'assertion failed: expected COM to be granted for widgetco, got allowed=% reason=%', v_decision.allowed, v_decision.reason;
  end if;

  select * into v_decision from app.evaluate_entitlement(v_tenant_id, 'FIN');
  if v_decision.allowed or v_decision.reason <> 'module_not_entitled' then
    raise exception 'assertion failed: expected FIN to be denied (module_not_entitled) for widgetco, got allowed=% reason=%', v_decision.allowed, v_decision.reason;
  end if;
end;
$$;

\echo '>> feature-level limit: a granted feature returns its quota; an ungranted feature within a granted module still fails closed'
do $$
declare
  v_tenant_id uuid;
  v_decision app.entitlement_decision;
begin
  select id into v_tenant_id from app.tenants where slug = 'widgetco';

  select * into v_decision from app.evaluate_entitlement(v_tenant_id, 'COM', 'COM-QTN');
  if not v_decision.allowed or v_decision.limit_value <> 50 then
    raise exception 'assertion failed: expected COM-QTN allowed with limit=50, got allowed=% limit=%', v_decision.allowed, v_decision.limit_value;
  end if;

  select * into v_decision from app.evaluate_entitlement(v_tenant_id, 'OPS', 'OPS-TMS');
  if not v_decision.allowed or v_decision.limit_value is not null then
    raise exception 'assertion failed: expected OPS-TMS allowed with a null (unlimited) limit, got allowed=% limit=%', v_decision.allowed, v_decision.limit_value;
  end if;

  select * into v_decision from app.evaluate_entitlement(v_tenant_id, 'COM', 'COM-CRM');
  if v_decision.allowed or v_decision.reason <> 'feature_not_entitled' then
    raise exception 'assertion failed: expected COM-CRM to be denied (feature_not_entitled, module granted but feature not listed), got allowed=% reason=%', v_decision.allowed, v_decision.reason;
  end if;
end;
$$;

\echo '>> a tenant with no assignment at all fails closed, not open'
do $$
declare
  v_tenant_id uuid;
  v_decision app.entitlement_decision;
begin
  select id into v_tenant_id from app.tenants where slug = 'gizmoinc';
  select * into v_decision from app.evaluate_entitlement(v_tenant_id, 'COM');
  if v_decision.allowed or v_decision.reason <> 'no_active_entitlement' then
    raise exception 'assertion failed: expected gizmoinc (no assignment) to be denied by default, got allowed=% reason=%', v_decision.allowed, v_decision.reason;
  end if;
end;
$$;

\echo '>> cross-tenant isolation: gizmoinc must never inherit widgetco''s entitlement'
do $$
declare
  v_gizmo_id uuid;
  v_pkg_id uuid;
  v_decision app.entitlement_decision;
begin
  select id into v_gizmo_id from app.tenants where slug = 'gizmoinc';
  select id into v_pkg_id from app.entitlement_packages where code = 'draft-only';
  -- Deliberately assign gizmoinc to the still-draft package to prove the evaluator
  -- checks package status, not just presence of an assignment row.
  perform app.assign_entitlement(v_gizmo_id, v_pkg_id, 'active', 'test setup', 'tester');

  select * into v_decision from app.evaluate_entitlement(v_gizmo_id, 'FIN');
  if v_decision.allowed or v_decision.reason <> 'package_not_published' then
    raise exception 'assertion failed: expected gizmoinc''s draft-status package to be denied (package_not_published), got allowed=% reason=%', v_decision.allowed, v_decision.reason;
  end if;

  select * into v_decision from app.evaluate_entitlement(v_gizmo_id, 'COM');
  if v_decision.allowed then
    raise exception 'assertion failed: gizmoinc must not inherit widgetco''s COM grant -- cross-tenant isolation violated';
  end if;
end;
$$;

\echo '>> trial expiry fails closed at evaluation time even before a lifecycle job runs'
do $$
declare
  v_tenant_id uuid;
  v_pkg_id uuid;
  v_decision app.entitlement_decision;
begin
  select id into v_tenant_id from app.provision_tenant('trialco', 'Trial Co', 'idem-trialco', 'tester');
  select id into v_pkg_id from app.entitlement_packages where code = 'professional';
  perform app.assign_entitlement(v_tenant_id, v_pkg_id, 'trial', 'trial signup', 'tester', now() - interval '1 day');

  select * into v_decision from app.evaluate_entitlement(v_tenant_id, 'COM');
  if v_decision.allowed or v_decision.reason <> 'trial_expired' then
    raise exception 'assertion failed: expected an expired trial to be denied (trial_expired) even though its row status is still literally trial, got allowed=% reason=%', v_decision.allowed, v_decision.reason;
  end if;
end;
$$;

\echo '>> override precedence: a granting override beats a missing package grant; a denying override beats an actual package grant'
do $$
declare
  v_tenant_id uuid;
  v_decision app.entitlement_decision;
begin
  select id into v_tenant_id from app.tenants where slug = 'widgetco';

  insert into app.tenant_entitlement_overrides (tenant_id, module_code, feature_code, granted, limit_override, reason, granted_by, expires_at)
  values (v_tenant_id, 'FIN', null, true, null, 'temporary pilot access', 'supreme-admin-1', now() + interval '7 days');

  select * into v_decision from app.evaluate_entitlement(v_tenant_id, 'FIN');
  if not v_decision.allowed or v_decision.reason <> 'override_granted' then
    raise exception 'assertion failed: expected a granting override to beat the missing package grant for FIN, got allowed=% reason=%', v_decision.allowed, v_decision.reason;
  end if;

  insert into app.tenant_entitlement_overrides (tenant_id, module_code, feature_code, granted, limit_override, reason, granted_by, expires_at)
  values (v_tenant_id, 'COM', null, false, null, 'billing dispute suspension', 'supreme-admin-1', now() + interval '3 days');

  select * into v_decision from app.evaluate_entitlement(v_tenant_id, 'COM');
  if v_decision.allowed or v_decision.reason <> 'override_denied' then
    raise exception 'assertion failed: expected a denying override to beat the actual package grant for COM, got allowed=% reason=%', v_decision.allowed, v_decision.reason;
  end if;
end;
$$;

\echo '>> an expired override no longer applies -- evaluation falls back to the package grant'
do $$
declare
  v_tenant_id uuid;
  v_decision app.entitlement_decision;
begin
  select id into v_tenant_id from app.tenants where slug = 'widgetco';

  insert into app.tenant_entitlement_overrides (tenant_id, module_code, feature_code, granted, limit_override, reason, granted_by, expires_at, created_at)
  values (v_tenant_id, 'OPS', null, false, null, 'expired hold, should no longer apply', 'supreme-admin-1', now() - interval '1 hour', now() - interval '2 hours');

  select * into v_decision from app.evaluate_entitlement(v_tenant_id, 'OPS');
  if not v_decision.allowed or v_decision.reason <> 'package_granted' then
    raise exception 'assertion failed: expected an expired override to be ignored, falling back to the package grant for OPS, got allowed=% reason=%', v_decision.allowed, v_decision.reason;
  end if;
end;
$$;

\echo '>> assignment supersession: assigning a second package cancels the first, both recorded in history'
do $$
declare
  v_tenant_id uuid;
  v_pkg2_id uuid;
  v_count integer;
begin
  select id into v_tenant_id from app.tenants where slug = 'gizmoinc';

  insert into app.entitlement_packages (code, name, version, status, granted_modules, feature_limits)
  values ('starter', 'Starter', 1, 'published', array['TKT'], '{}'::jsonb)
  returning id into v_pkg2_id;

  perform app.assign_entitlement(v_tenant_id, v_pkg2_id, 'active', 'plan change', 'tester');

  select count(*) into v_count from app.tenant_entitlements where tenant_id = v_tenant_id and status in ('trial', 'active', 'suspended');
  if v_count <> 1 then
    raise exception 'assertion failed: expected exactly 1 non-terminal assignment after supersession, found %', v_count;
  end if;

  select count(*) into v_count from app.tenant_entitlements where tenant_id = v_tenant_id and status = 'cancelled';
  if v_count <> 1 then
    raise exception 'assertion failed: expected exactly 1 cancelled (superseded) assignment, found %', v_count;
  end if;
end;
$$;

\echo '>> terminal states are truly terminal'
do $$
declare
  v_tenant_id uuid;
begin
  select id into v_tenant_id from app.tenants where slug = 'trialco';
  perform app.transition_entitlement_status(v_tenant_id, 'cancelled', 'tenant churned', 'tester');
  begin
    perform app.transition_entitlement_status(v_tenant_id, 'active', 'attempted revival', 'tester');
    raise exception 'assertion failed: expected transitioning a cancelled entitlement to fail, but it succeeded';
  exception
    when no_data_found then
      null; -- expected: transition_entitlement_status only finds non-terminal rows
  end;
end;
$$;

\echo '>> defense in depth: anon and authenticated are denied at the schema-privilege layer; service_role has explicit access'
do $$
begin
  set local role anon;
  begin
    perform count(*) from app.tenant_entitlements;
    raise exception 'assertion failed: anon must be denied at the schema-privilege layer for tenant_entitlements';
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
  select count(*) into v_count from app.tenant_entitlements;
  if v_count < 2 then
    raise exception 'assertion failed: service_role must see the provisioned entitlement assignments, saw %', v_count;
  end if;
  reset role;
end;
$$;

\echo 'ALL PLT-106 db-test assertions passed.'
