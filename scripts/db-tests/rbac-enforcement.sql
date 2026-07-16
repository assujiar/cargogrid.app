-- Real, executable test evidence for PLT-112 (RBAC Enforcement, CG-S6-PLT-009).

\set ON_ERROR_STOP on

\echo '>> setup: a tenant, two active users, and a published "Finance Approver" role granting FIN:Approve'
do $$
declare
  v_tenant_id uuid;
  v_role_id uuid;
  v_draft app.role_versions;
  v_permission_id uuid;
begin
  insert into auth.users (id, email) values
    ('00000000-0000-0000-0000-000000000401', 'grantee@example.test'),
    ('00000000-0000-0000-0000-000000000402', 'nobody@example.test');

  perform app.provision_tenant('acmerbac', 'Acme RBAC Co', 'idem-acmerbac', 'tester');
  v_tenant_id := (select id from app.tenants where slug = 'acmerbac');
  perform app.transition_tenant_status(v_tenant_id, 'active', 'setup', 'tester');

  perform app.invite_user(v_tenant_id, '00000000-0000-0000-0000-000000000401', 'grantee@example.test', 'Grantee', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'grantee@example.test'), 'active', 'onboarded', 'tester');
  perform app.invite_user(v_tenant_id, '00000000-0000-0000-0000-000000000402', 'nobody@example.test', 'Nobody', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'nobody@example.test'), 'active', 'onboarded', 'tester');

  select id into v_role_id from app.create_role(v_tenant_id, 'RBAC Finance Approver', null, 'tester');
  select * into v_draft from app.create_role_version(v_role_id, 'tester');
  select id into v_permission_id from app.permissions where resource_module_code = 'FIN' and action = 'Approve';
  perform app.set_role_version_permissions(v_draft.id, array[v_permission_id], 'tester');
  perform app.publish_role_version(v_draft.id, now(), 'tester');

  perform app.assign_role(
    v_tenant_id,
    (select id from app.role_versions where role_id = v_role_id and status = 'published'),
    '00000000-0000-0000-0000-000000000401',
    '00000000-0000-0000-0000-000000000401',
    'tester'
  );
end;
$$;

\echo '>> a granted permission evaluates allowed=true with the role/version traced in the decision'
do $$
declare
  v_tenant_id uuid;
  v_decision app.rbac_decision;
begin
  v_tenant_id := (select id from app.tenants where slug = 'acmerbac');
  v_decision := app.evaluate_permission('00000000-0000-0000-0000-000000000401', v_tenant_id, 'FIN', 'Approve');
  if not v_decision.allowed or v_decision.reason <> 'role_grant' or v_decision.role_version_id is null then
    raise exception 'assertion failed: expected allowed=true reason=role_grant with a role_version_id, got allowed=% reason=%', v_decision.allowed, v_decision.reason;
  end if;
end;
$$;

\echo '>> an ungranted permission for the same identity fails closed with a distinct reason from "no assignment at all"'
do $$
declare
  v_tenant_id uuid;
  v_decision app.rbac_decision;
begin
  v_tenant_id := (select id from app.tenants where slug = 'acmerbac');
  v_decision := app.evaluate_permission('00000000-0000-0000-0000-000000000401', v_tenant_id, 'FIN', 'Reject');
  if v_decision.allowed or v_decision.reason <> 'no_granting_role' then
    raise exception 'assertion failed: expected allowed=false reason=no_granting_role, got allowed=% reason=%', v_decision.allowed, v_decision.reason;
  end if;
end;
$$;

\echo '>> an identity with no role assignment at all fails closed with its own distinct reason'
do $$
declare
  v_tenant_id uuid;
  v_decision app.rbac_decision;
begin
  v_tenant_id := (select id from app.tenants where slug = 'acmerbac');
  v_decision := app.evaluate_permission('00000000-0000-0000-0000-000000000402', v_tenant_id, 'FIN', 'Approve');
  if v_decision.allowed or v_decision.reason <> 'no_active_assignment' then
    raise exception 'assertion failed: expected allowed=false reason=no_active_assignment, got allowed=% reason=%', v_decision.allowed, v_decision.reason;
  end if;
end;
$$;

\echo '>> an unknown module/action pair fails closed rather than raising'
do $$
declare
  v_tenant_id uuid;
  v_decision app.rbac_decision;
begin
  v_tenant_id := (select id from app.tenants where slug = 'acmerbac');
  v_decision := app.evaluate_permission('00000000-0000-0000-0000-000000000401', v_tenant_id, 'FIN', 'Teleport');
  if v_decision.allowed or v_decision.reason <> 'unknown_permission' then
    raise exception 'assertion failed: expected allowed=false reason=unknown_permission, got allowed=% reason=%', v_decision.allowed, v_decision.reason;
  end if;
end;
$$;

\echo '>> a revoked role assignment fails closed even though the role version is still published'
do $$
declare
  v_tenant_id uuid;
  v_assignment app.role_assignments;
  v_decision app.rbac_decision;
begin
  v_tenant_id := (select id from app.tenants where slug = 'acmerbac');
  select * into v_assignment from app.role_assignments where tenant_id = v_tenant_id and auth_user_id = '00000000-0000-0000-0000-000000000401' and status = 'active';
  perform app.revoke_role_assignment(v_assignment.id, 'test revoke', 'tester');

  v_decision := app.evaluate_permission('00000000-0000-0000-0000-000000000401', v_tenant_id, 'FIN', 'Approve');
  if v_decision.allowed then
    raise exception 'assertion failed: expected a revoked assignment to deny, but it allowed';
  end if;

  -- re-grant for the remaining tests in this file
  perform app.assign_role(
    v_tenant_id,
    (select id from app.role_versions where role_id = (select id from app.roles where name = 'RBAC Finance Approver') and status = 'published'),
    '00000000-0000-0000-0000-000000000401',
    '00000000-0000-0000-0000-000000000401',
    'tester'
  );
end;
$$;

\echo '>> a stale assignment (still active, but pointing at a now-archived, superseded role version) fails closed -- PLT-112 §23''s "stale permission fails closed"'
do $$
declare
  v_tenant_id uuid;
  v_role_id uuid;
  v_new_draft app.role_versions;
  v_decision app.rbac_decision;
begin
  v_tenant_id := (select id from app.tenants where slug = 'acmerbac');
  v_role_id := (select id from app.roles where name = 'RBAC Finance Approver');

  -- Publish a *new* version of the same role -- this archives (supersedes) the version
  -- the existing assignment still points to, without touching app.role_assignments itself.
  select * into v_new_draft from app.create_role_version(v_role_id, 'tester');
  perform app.set_role_version_permissions(v_new_draft.id, array[(select id from app.permissions where resource_module_code = 'FIN' and action = 'Approve')], 'tester');
  perform app.publish_role_version(v_new_draft.id, now(), 'tester');

  v_decision := app.evaluate_permission('00000000-0000-0000-0000-000000000401', v_tenant_id, 'FIN', 'Approve');
  if v_decision.allowed or v_decision.reason <> 'no_granting_role' then
    raise exception 'assertion failed: expected the stale assignment to deny (reason=no_granting_role), got allowed=% reason=%', v_decision.allowed, v_decision.reason;
  end if;

  -- re-assigning to the newly published version restores access -- proving the denial
  -- above was caused by staleness, not by some other unrelated breakage.
  perform app.assign_role(
    v_tenant_id, v_new_draft.id,
    '00000000-0000-0000-0000-000000000401', '00000000-0000-0000-0000-000000000401', 'tester'
  );
  v_decision := app.evaluate_permission('00000000-0000-0000-0000-000000000401', v_tenant_id, 'FIN', 'Approve');
  if not v_decision.allowed then
    raise exception 'assertion failed: expected access restored once re-assigned to the newly published version';
  end if;
end;
$$;

\echo '>> role names never authorize: a role literally named to sound like a bypass, with no matching permission, still denies'
do $$
declare
  v_tenant_id uuid;
  v_role_id uuid;
  v_draft app.role_versions;
  v_unrelated_permission_id uuid;
  v_decision app.rbac_decision;
begin
  v_tenant_id := (select id from app.tenants where slug = 'acmerbac');
  select id into v_role_id from app.create_role(v_tenant_id, 'SuperAdminBypassAllChecks', 'A role whose *name* implies unlimited access', 'tester');
  select * into v_draft from app.create_role_version(v_role_id, 'tester');
  select id into v_unrelated_permission_id from app.permissions where resource_module_code = 'TKT' and action = 'View';
  perform app.set_role_version_permissions(v_draft.id, array[v_unrelated_permission_id], 'tester');
  perform app.publish_role_version(v_draft.id, now(), 'tester');
  perform app.assign_role(
    v_tenant_id,
    (select id from app.role_versions where role_id = v_role_id and status = 'published'),
    '00000000-0000-0000-0000-000000000402',
    '00000000-0000-0000-0000-000000000401',
    'tester'
  );

  v_decision := app.evaluate_permission('00000000-0000-0000-0000-000000000402', v_tenant_id, 'FIN', 'Approve');
  if v_decision.allowed then
    raise exception 'assertion failed: expected a role whose name implies bypass, but whose bindings do not grant FIN:Approve, to deny -- got allowed=true';
  end if;

  -- the same identity IS granted the one permission actually bound to that role
  v_decision := app.evaluate_permission('00000000-0000-0000-0000-000000000402', v_tenant_id, 'TKT', 'View');
  if not v_decision.allowed then
    raise exception 'assertion failed: expected the actually-bound permission to be granted regardless of the role''s name';
  end if;
end;
$$;

\echo '>> multiple granted roles combine additively (union): a second role grants a second, distinct permission'
do $$
declare
  v_tenant_id uuid;
  v_role_id uuid;
  v_draft app.role_versions;
  v_permission_id uuid;
  v_decision_fin app.rbac_decision;
  v_decision_tkt app.rbac_decision;
begin
  v_tenant_id := (select id from app.tenants where slug = 'acmerbac');
  select id into v_role_id from app.create_role(v_tenant_id, 'Ticket Closer', null, 'tester');
  select * into v_draft from app.create_role_version(v_role_id, 'tester');
  select id into v_permission_id from app.permissions where resource_module_code = 'TKT' and action = 'Close';
  perform app.set_role_version_permissions(v_draft.id, array[v_permission_id], 'tester');
  perform app.publish_role_version(v_draft.id, now(), 'tester');
  perform app.assign_role(
    v_tenant_id,
    (select id from app.role_versions where role_id = v_role_id and status = 'published'),
    '00000000-0000-0000-0000-000000000402',
    '00000000-0000-0000-0000-000000000401',
    'tester'
  );

  v_decision_tkt := app.evaluate_permission('00000000-0000-0000-0000-000000000402', v_tenant_id, 'TKT', 'Close');
  v_decision_fin := app.evaluate_permission('00000000-0000-0000-0000-000000000402', v_tenant_id, 'TKT', 'View');
  if not v_decision_tkt.allowed or not v_decision_fin.allowed then
    raise exception 'assertion failed: expected both roles'' distinct grants to independently allow, got Close=% View=%', v_decision_tkt.allowed, v_decision_fin.allowed;
  end if;
end;
$$;

\echo '>> cross-tenant isolation: a role assignment in one tenant grants nothing when evaluated against another tenant'
do $$
declare
  v_other_tenant_id uuid;
  v_decision app.rbac_decision;
begin
  perform app.provision_tenant('gizmorbac', 'Gizmo RBAC Co', 'idem-gizmorbac', 'tester');
  v_other_tenant_id := (select id from app.tenants where slug = 'gizmorbac');
  perform app.transition_tenant_status(v_other_tenant_id, 'active', 'setup', 'tester');

  v_decision := app.evaluate_permission('00000000-0000-0000-0000-000000000401', v_other_tenant_id, 'FIN', 'Approve');
  if v_decision.allowed then
    raise exception 'assertion failed: expected a grant in acmerbac to never apply to gizmorbac, but it allowed';
  end if;
end;
$$;

\echo '>> the Supreme Admin exception (RPD-022) bypasses the role/permission lookup entirely, even with zero role assignments'
do $$
declare
  v_tenant_id uuid;
  v_new_identity uuid := '00000000-0000-0000-0000-000000000403';
  v_decision app.rbac_decision;
begin
  v_tenant_id := (select id from app.tenants where slug = 'acmerbac');
  insert into auth.users (id, email) values (v_new_identity, 'supreme@example.test');
  perform app.grant_principal_membership(v_new_identity, 'supreme_admin', null, null, 'tester');

  v_decision := app.evaluate_permission(v_new_identity, v_tenant_id, 'FIN', 'Approve');
  if not v_decision.allowed or v_decision.reason <> 'supreme_admin_exception' then
    raise exception 'assertion failed: expected allowed=true reason=supreme_admin_exception, got allowed=% reason=%', v_decision.allowed, v_decision.reason;
  end if;
end;
$$;

\echo '>> defense in depth: anon and authenticated cannot call the evaluator; service_role can'
do $$
begin
  set local role anon;
  begin
    perform app.evaluate_permission('00000000-0000-0000-0000-000000000401', (select id from app.tenants where slug = 'acmerbac'), 'FIN', 'Approve');
    raise exception 'assertion failed: anon must be denied execute privilege on app.evaluate_permission';
  exception
    when insufficient_privilege then
      null; -- expected
  end;
  reset role;
end;
$$;

do $$
declare
  v_decision app.rbac_decision;
begin
  set local role service_role;
  v_decision := app.evaluate_permission('00000000-0000-0000-0000-000000000401', (select id from app.tenants where slug = 'acmerbac'), 'FIN', 'Approve');
  if not v_decision.allowed then
    raise exception 'assertion failed: service_role must be able to evaluate and get the expected allowed result';
  end if;
  reset role;
end;
$$;

\echo 'ALL PLT-112 db-test assertions passed.'
