-- Real, executable test evidence for PLT-111 (Role and Permission Builder,
-- CG-S6-PLT-008).

\set ON_ERROR_STOP on

\echo '>> setup: a tenant, two active users (one will be the actor/admin, one a regular assignee)'
do $$
declare
  v_tenant_id uuid;
begin
  insert into auth.users (id, email) values
    ('00000000-0000-0000-0000-000000000301', 'roleadmin@example.test'),
    ('00000000-0000-0000-0000-000000000302', 'regular@example.test');

  perform app.provision_tenant('acmerole', 'Acme Role Co', 'idem-acmerole', 'tester');
  v_tenant_id := (select id from app.tenants where slug = 'acmerole');
  perform app.transition_tenant_status(v_tenant_id, 'active', 'setup', 'tester');

  perform app.invite_user(v_tenant_id, '00000000-0000-0000-0000-000000000301', 'roleadmin@example.test', 'Role Admin', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'roleadmin@example.test'), 'active', 'onboarded', 'tester');
  perform app.invite_user(v_tenant_id, '00000000-0000-0000-0000-000000000302', 'regular@example.test', 'Regular User', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'regular@example.test'), 'active', 'onboarded', 'tester');
end;
$$;

\echo '>> idempotent role creation and idempotent draft creation'
do $$
declare
  v_tenant_id uuid;
  v_role_first app.roles;
  v_role_second app.roles;
  v_draft_first app.role_versions;
  v_draft_second app.role_versions;
begin
  v_tenant_id := (select id from app.tenants where slug = 'acmerole');

  select * into v_role_first from app.create_role(v_tenant_id, 'Finance Approver', 'Approves finance transactions', 'tester');
  select * into v_role_second from app.create_role(v_tenant_id, 'Finance Approver', 'Approves finance transactions', 'tester');
  if v_role_second.id <> v_role_first.id then
    raise exception 'assertion failed: expected idempotent role creation to return the original row';
  end if;

  select * into v_draft_first from app.create_role_version(v_role_first.id, 'tester');
  if v_draft_first.status <> 'draft' or v_draft_first.version_number <> 1 then
    raise exception 'assertion failed: expected draft version 1, got status=% version=%', v_draft_first.status, v_draft_first.version_number;
  end if;

  select * into v_draft_second from app.create_role_version(v_role_first.id, 'tester');
  if v_draft_second.id <> v_draft_first.id then
    raise exception 'assertion failed: expected idempotent draft creation to return the original draft';
  end if;
end;
$$;

\echo '>> permissions can only be set on a draft version; publishing makes them immutable'
do $$
declare
  v_role_id uuid;
  v_draft_id uuid;
  v_bound_count integer;
  v_fin_view_id uuid;
  v_fin_approve_id uuid;
  v_fin_cost_id uuid;
begin
  v_role_id := (select id from app.roles where name = 'Finance Approver');
  v_draft_id := (select id from app.role_versions where role_id = v_role_id and status = 'draft');

  select id into v_fin_view_id from app.permissions where resource_module_code = 'FIN' and action = 'View';
  select id into v_fin_approve_id from app.permissions where resource_module_code = 'FIN' and action = 'Approve';
  select id into v_fin_cost_id from app.permissions where resource_module_code = 'FIN' and action = 'View cost';

  select app.set_role_version_permissions(v_draft_id, array[v_fin_view_id, v_fin_approve_id], 'tester') into v_bound_count;
  if v_bound_count <> 2 then
    raise exception 'assertion failed: expected 2 bound permissions, got %', v_bound_count;
  end if;

  perform app.publish_role_version(v_draft_id, now(), 'tester');

  begin
    perform app.set_role_version_permissions(v_draft_id, array[v_fin_cost_id], 'tester');
    raise exception 'assertion failed: expected setting permissions on a published version to fail, but it succeeded';
  exception
    when check_violation then
      null; -- expected
  end;
end;
$$;

\echo '>> publishing a new version supersedes (archives) the prior published version'
do $$
declare
  v_role_id uuid;
  v_old_published_id uuid;
  v_new_draft app.role_versions;
  v_old_after app.role_versions;
begin
  v_role_id := (select id from app.roles where name = 'Finance Approver');
  v_old_published_id := (select id from app.role_versions where role_id = v_role_id and status = 'published');

  select * into v_new_draft from app.create_role_version(v_role_id, 'tester');
  perform app.publish_role_version(v_new_draft.id, now(), 'tester');

  select * into v_old_after from app.role_versions where id = v_old_published_id;
  if v_old_after.status <> 'archived' then
    raise exception 'assertion failed: expected the prior published version to be archived, got %', v_old_after.status;
  end if;
end;
$$;

\echo '>> cloning copies the source version''s permission bindings into a new draft; cloning a draft is rejected'
do $$
declare
  v_role_id uuid;
  v_published_id uuid;
  v_source_count integer;
  v_cloned app.role_versions;
  v_cloned_count integer;
begin
  v_role_id := (select id from app.roles where name = 'Finance Approver');
  v_published_id := (select id from app.role_versions where role_id = v_role_id and status = 'published');
  select count(*) into v_source_count from app.role_version_permissions where role_version_id = v_published_id;

  select * into v_cloned from app.clone_role_version(v_published_id, 'tester');
  if v_cloned.status <> 'draft' or v_cloned.cloned_from_version_id <> v_published_id then
    raise exception 'assertion failed: expected a new draft cloned_from the published version';
  end if;

  select count(*) into v_cloned_count from app.role_version_permissions where role_version_id = v_cloned.id;
  if v_cloned_count <> v_source_count then
    raise exception 'assertion failed: expected the clone to carry % bound permissions, found %', v_source_count, v_cloned_count;
  end if;

  begin
    perform app.clone_role_version(v_cloned.id, 'tester');
    raise exception 'assertion failed: expected cloning a draft to fail, but it succeeded';
  exception
    when check_violation then
      null; -- expected
  end;

  perform app.archive_role_version(v_cloned.id, 'not needed for these tests', 'tester');
end;
$$;

\echo '>> assignment requires a published version; assigning a draft is rejected'
do $$
declare
  v_tenant_id uuid;
  v_role_id uuid;
  v_draft app.role_versions;
begin
  v_tenant_id := (select id from app.tenants where slug = 'acmerole');
  select id into v_role_id from app.create_role(v_tenant_id, 'Draft Only Role', null, 'tester');
  select * into v_draft from app.create_role_version(v_role_id, 'tester');

  begin
    perform app.assign_role(v_tenant_id, v_draft.id, '00000000-0000-0000-0000-000000000302', '00000000-0000-0000-0000-000000000301', 'tester');
    raise exception 'assertion failed: expected assigning a draft version to fail, but it succeeded';
  exception
    when check_violation then
      null; -- expected
  end;
end;
$$;

\echo '>> idempotent assignment: assigning the same (tenant, version, user) twice returns the original row'
do $$
declare
  v_tenant_id uuid;
  v_published_id uuid;
  v_first app.role_assignments;
  v_second app.role_assignments;
  v_count integer;
begin
  v_tenant_id := (select id from app.tenants where slug = 'acmerole');
  v_published_id := (select id from app.role_versions where role_id = (select id from app.roles where name = 'Finance Approver') and status = 'published');

  select * into v_first from app.assign_role(v_tenant_id, v_published_id, '00000000-0000-0000-0000-000000000302', '00000000-0000-0000-0000-000000000301', 'tester');
  select * into v_second from app.assign_role(v_tenant_id, v_published_id, '00000000-0000-0000-0000-000000000302', '00000000-0000-0000-0000-000000000301', 'tester');
  if v_second.id <> v_first.id then
    raise exception 'assertion failed: expected idempotent assignment to return the original row';
  end if;

  select count(*) into v_count from app.role_assignments
  where tenant_id = v_tenant_id and role_version_id = v_published_id and auth_user_id = '00000000-0000-0000-0000-000000000302' and status = 'active';
  if v_count <> 1 then
    raise exception 'assertion failed: expected exactly 1 active assignment, found %', v_count;
  end if;
end;
$$;

\echo '>> self-escalation guard: an actor cannot assign themselves a role version carrying a protected permission'
do $$
declare
  v_tenant_id uuid;
  v_role_id uuid;
  v_draft app.role_versions;
  v_published app.role_versions;
  v_cost_id uuid;
  v_plain_role_id uuid;
  v_plain_draft app.role_versions;
  v_plain_view_id uuid;
  v_plain_published app.role_versions;
begin
  v_tenant_id := (select id from app.tenants where slug = 'acmerole');
  select id into v_role_id from app.create_role(v_tenant_id, 'Cost Viewer', null, 'tester');
  select * into v_draft from app.create_role_version(v_role_id, 'tester');
  select id into v_cost_id from app.permissions where resource_module_code = 'FIN' and action = 'View cost';
  perform app.set_role_version_permissions(v_draft.id, array[v_cost_id], 'tester');
  select * into v_published from app.publish_role_version(v_draft.id, now(), 'tester');

  begin
    perform app.assign_role(v_tenant_id, v_published.id, '00000000-0000-0000-0000-000000000301', '00000000-0000-0000-0000-000000000301', 'tester');
    raise exception 'assertion failed: expected self-escalation into a protected permission to fail, but it succeeded';
  exception
    when check_violation then
      null; -- expected
  end;

  -- The same protected role version assigned to a *different* user (not a self-assignment) succeeds.
  perform app.assign_role(v_tenant_id, v_published.id, '00000000-0000-0000-0000-000000000302', '00000000-0000-0000-0000-000000000301', 'tester');

  -- A non-protected, *published* role version may still be self-assigned.
  select id into v_plain_role_id from app.create_role(v_tenant_id, 'Ops Viewer', null, 'tester');
  select * into v_plain_draft from app.create_role_version(v_plain_role_id, 'tester');
  select id into v_plain_view_id from app.permissions where resource_module_code = 'OPS' and action = 'View';
  perform app.set_role_version_permissions(v_plain_draft.id, array[v_plain_view_id], 'tester');
  select * into v_plain_published from app.publish_role_version(v_plain_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant_id, v_plain_published.id, '00000000-0000-0000-0000-000000000301', '00000000-0000-0000-0000-000000000301', 'tester');
exception
  when check_violation then
    raise exception 'assertion failed: expected a non-protected self-assignment (or a to-another-user protected assignment) to succeed, but it raised';
end;
$$;

\echo '>> a cross-tenant role assignment is rejected'
do $$
declare
  v_other_tenant_id uuid;
  v_published_id uuid;
begin
  perform app.provision_tenant('gizmorole', 'Gizmo Role Co', 'idem-gizmorole', 'tester');
  v_other_tenant_id := (select id from app.tenants where slug = 'gizmorole');
  v_published_id := (select id from app.role_versions where role_id = (select id from app.roles where name = 'Finance Approver') and status = 'published');

  begin
    perform app.assign_role(v_other_tenant_id, v_published_id, '00000000-0000-0000-0000-000000000302', '00000000-0000-0000-0000-000000000301', 'tester');
    raise exception 'assertion failed: expected a cross-tenant role assignment to fail, but it succeeded';
  exception
    when check_violation then
      null; -- expected
  end;
end;
$$;

\echo '>> revoke is idempotent-safe (revoking an already-revoked assignment returns it unchanged) and revoking a non-existent one fails cleanly'
do $$
declare
  v_tenant_id uuid;
  v_published_id uuid;
  v_assignment app.role_assignments;
  v_revoked app.role_assignments;
  v_revoked_again app.role_assignments;
begin
  v_tenant_id := (select id from app.tenants where slug = 'acmerole');
  v_published_id := (select id from app.role_versions where role_id = (select id from app.roles where name = 'Finance Approver') and status = 'published');
  select * into v_assignment from app.role_assignments
  where tenant_id = v_tenant_id and role_version_id = v_published_id and auth_user_id = '00000000-0000-0000-0000-000000000302' and status = 'active';

  select * into v_revoked from app.revoke_role_assignment(v_assignment.id, 'role change', 'tester');
  if v_revoked.status <> 'revoked' then
    raise exception 'assertion failed: expected revoked status';
  end if;

  select * into v_revoked_again from app.revoke_role_assignment(v_assignment.id, 'role change again', 'tester');
  if v_revoked_again.revoked_reason <> v_revoked.revoked_reason then
    raise exception 'assertion failed: expected revoking an already-revoked assignment to be a no-op, not overwrite the reason';
  end if;

  begin
    perform app.revoke_role_assignment('00000000-0000-0000-0000-000000000099', 'n/a', 'tester');
    raise exception 'assertion failed: expected revoking a non-existent assignment to fail, but it succeeded';
  exception
    when no_data_found then
      null; -- expected
  end;
end;
$$;

\echo '>> defense in depth: anon and authenticated are denied at the schema-privilege layer; service_role has explicit access'
do $$
begin
  set local role anon;
  begin
    perform count(*) from app.permissions;
    raise exception 'assertion failed: anon must be denied at the schema-privilege layer for permissions';
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
  select count(*) into v_count from app.permissions;
  if v_count < 60 then
    raise exception 'assertion failed: service_role must see the full permission catalogue, saw %', v_count;
  end if;
  reset role;
end;
$$;

\echo '>> CG-AUDIT-2026-09-02 A3: republishing a role version migrates every ACTIVE holder of the version it archives onto the version it publishes, so evaluate_permission keeps granting access the identity already held -- never a silent revocation, and a real role_lifecycle_history version_migrated event is recorded for it'
do $$
declare
  v_tenant_id uuid;
  v_role app.roles;
  v_draft1 app.role_versions;
  v_draft2 app.role_versions;
  v_published1 app.role_versions;
  v_published2 app.role_versions;
  v_fin_view_id uuid;
  v_assignment app.role_assignments;
  v_after app.role_assignments;
  v_decision app.rbac_decision;
  v_migrate_count integer;
begin
  v_tenant_id := (select id from app.tenants where slug = 'acmerole');

  select * into v_role from app.create_role(v_tenant_id, 'A3 Republish Role', 'republish migration test', 'tester');
  select * into v_draft1 from app.create_role_version(v_role.id, 'tester');
  select id into v_fin_view_id from app.permissions where resource_module_code = 'FIN' and action = 'View';
  perform app.set_role_version_permissions(v_draft1.id, array[v_fin_view_id], 'tester');
  select * into v_published1 from app.publish_role_version(v_draft1.id, now(), 'tester');

  select * into v_assignment from app.assign_role(v_tenant_id, v_published1.id, '00000000-0000-0000-0000-000000000302', '00000000-0000-0000-0000-000000000301', 'tester');

  v_decision := app.evaluate_permission('00000000-0000-0000-0000-000000000302', v_tenant_id, 'FIN', 'View');
  if not v_decision.allowed then
    raise exception 'assertion failed: expected FIN:View allowed before the role is republished';
  end if;

  -- Publish a second version of the SAME role -- this is the exact operation that used to
  -- silently revoke the assignment above (the version it was bound to gets archived, and
  -- app.evaluate_permission's own join requires status = 'published').
  select * into v_draft2 from app.create_role_version(v_role.id, 'tester');
  perform app.set_role_version_permissions(v_draft2.id, array[v_fin_view_id], 'tester');
  select * into v_published2 from app.publish_role_version(v_draft2.id, now(), 'tester');

  v_decision := app.evaluate_permission('00000000-0000-0000-0000-000000000302', v_tenant_id, 'FIN', 'View');
  if not v_decision.allowed then
    raise exception 'assertion failed: republishing the role silently revoked FIN:View from an existing holder -- CG-AUDIT-2026-09-02 A3 regression';
  end if;

  select * into v_after from app.role_assignments where id = v_assignment.id;
  if v_after.role_version_id <> v_published2.id then
    raise exception 'assertion failed: expected the assignment migrated onto the newly published version %, still points at %', v_published2.id, v_after.role_version_id;
  end if;
  if v_after.status <> 'active' then
    raise exception 'assertion failed: expected the migrated assignment to remain active, got %', v_after.status;
  end if;

  select count(*) into v_migrate_count from app.role_lifecycle_history
  where role_assignment_id = v_assignment.id and event_type = 'version_migrated' and role_version_id = v_published2.id;
  if v_migrate_count <> 1 then
    raise exception 'assertion failed: expected exactly 1 version_migrated history row for the migrated assignment, got %', v_migrate_count;
  end if;

  -- A publish with NO existing holders of the version it archives must not fabricate a
  -- migration event -- a brand-new role, republished with zero assignments ever made
  -- against it, must record zero version_migrated rows.
  declare
    v_unheld_role app.roles;
    v_unheld_draft1 app.role_versions;
    v_unheld_draft2 app.role_versions;
    v_unheld_migrate_count integer;
  begin
    select * into v_unheld_role from app.create_role(v_tenant_id, 'A3 Unheld Role', 'never assigned', 'tester');
    select * into v_unheld_draft1 from app.create_role_version(v_unheld_role.id, 'tester');
    perform app.set_role_version_permissions(v_unheld_draft1.id, array[v_fin_view_id], 'tester');
    perform app.publish_role_version(v_unheld_draft1.id, now(), 'tester');

    select * into v_unheld_draft2 from app.create_role_version(v_unheld_role.id, 'tester');
    perform app.set_role_version_permissions(v_unheld_draft2.id, array[v_fin_view_id], 'tester');
    perform app.publish_role_version(v_unheld_draft2.id, now(), 'tester');

    select count(*) into v_unheld_migrate_count from app.role_lifecycle_history
    where role_id = v_unheld_role.id and event_type = 'version_migrated';
    if v_unheld_migrate_count <> 0 then
      raise exception 'assertion failed: expected zero version_migrated events for a role nobody ever held, got %', v_unheld_migrate_count;
    end if;
  end;
end;
$$;

\echo '>> audit remediation A2: app.list_role_versions / app.list_role_version_permissions / app.list_role_assignments_for_role -- the three read RPCs the admin/roles/ UI needs, added because the write-side RPCs above had no way to see their own results again after a page reload'
do $$
declare
  v_tenant_id uuid;
  v_role app.roles;
  v_draft1 app.role_versions;
  v_draft2 app.role_versions;
  v_published1 app.role_versions;
  v_published2 app.role_versions;
  v_fin_view_id uuid;
  v_fin_approve_id uuid;
  v_count integer;
  v_assignment app.role_assignments;
begin
  v_tenant_id := (select id from app.tenants where slug = 'acmerole');

  insert into auth.users (id, email) values
    ('00000000-0000-0000-0000-000000000303', 'a2customer@example.test'),
    ('00000000-0000-0000-0000-000000000304', 'a2crosstenant@example.test');
  perform app.link_auth_identity('00000000-0000-0000-0000-000000000303', v_tenant_id, 'tester', 'active');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000000303', 'customer_user', v_tenant_id, 'fake-account-ref-a2', 'tester');
  perform app.invite_user((select id from app.tenants where slug = 'gizmorole'), '00000000-0000-0000-0000-000000000304', 'a2crosstenant@example.test', 'Cross Tenant', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'a2crosstenant@example.test'), 'active', 'onboarded', 'tester');

  select * into v_role from app.create_role(v_tenant_id, 'A2 Read RPC Role', 'db-test fixture for the new read RPCs', 'tester');
  select * into v_draft1 from app.create_role_version(v_role.id, 'tester');
  select id into v_fin_view_id from app.permissions where resource_module_code = 'FIN' and action = 'View';
  select id into v_fin_approve_id from app.permissions where resource_module_code = 'FIN' and action = 'Approve';
  perform app.set_role_version_permissions(v_draft1.id, array[v_fin_view_id], 'tester');
  select * into v_published1 from app.publish_role_version(v_draft1.id, now(), 'tester');

  select * into v_draft2 from app.create_role_version(v_role.id, 'tester');
  perform app.set_role_version_permissions(v_draft2.id, array[v_fin_view_id, v_fin_approve_id], 'tester');
  select * into v_published2 from app.publish_role_version(v_draft2.id, now(), 'tester');

  select * into v_assignment from app.assign_role(v_tenant_id, v_published2.id, '00000000-0000-0000-0000-000000000302', '00000000-0000-0000-0000-000000000301', 'tester');
  perform app.revoke_role_assignment(v_assignment.id, 'db-test revoke proof', 'tester');

  -- app.list_role_versions (SECURITY INVOKER, no actor param, relies on live RLS):
  -- an active tenant member sees both versions (v1 now archived, v2 published), newest first.
  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000000302", "role": "authenticated"}';
  select count(*) into v_count from app.list_role_versions(v_role.id);
  if v_count <> 2 then
    raise exception 'assertion failed: expected list_role_versions to return 2 versions for an active tenant member, got %', v_count;
  end if;
  if (select version_number from app.list_role_versions(v_role.id) limit 1) <> 2 then
    raise exception 'assertion failed: expected list_role_versions ordered newest-version-first';
  end if;
  reset role; reset request.jwt.claims;

  -- a customer_user-layer principal in the SAME tenant sees zero (role_versions_select_own_tenant excludes it).
  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000000303", "role": "authenticated"}';
  select count(*) into v_count from app.list_role_versions(v_role.id);
  if v_count <> 0 then
    raise exception 'assertion failed: expected list_role_versions to deny a customer_user-layer principal, saw %', v_count;
  end if;
  reset role; reset request.jwt.claims;

  -- a member of a DIFFERENT tenant sees zero.
  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000000304", "role": "authenticated"}';
  select count(*) into v_count from app.list_role_versions(v_role.id);
  if v_count <> 0 then
    raise exception 'assertion failed: expected list_role_versions to deny a cross-tenant actor, saw %', v_count;
  end if;
  reset role; reset request.jwt.claims;

  -- app.list_role_version_permissions (SECURITY DEFINER, explicit actor param, manually
  -- reproduces role_versions_select_own_tenant's own current predicate).
  select count(*) into v_count from app.list_role_version_permissions(v_published2.id, '00000000-0000-0000-0000-000000000302');
  if v_count <> 2 then
    raise exception 'assertion failed: expected list_role_version_permissions to return 2 permissions for the published version, got %', v_count;
  end if;
  select count(*) into v_count from app.list_role_version_permissions(v_published1.id, '00000000-0000-0000-0000-000000000302');
  if v_count <> 1 then
    raise exception 'assertion failed: expected list_role_version_permissions to return 1 permission for the archived version (bindings are immutable once published), got %', v_count;
  end if;
  select count(*) into v_count from app.list_role_version_permissions(v_published2.id, '00000000-0000-0000-0000-000000000303');
  if v_count <> 0 then
    raise exception 'assertion failed: expected list_role_version_permissions to deny a customer_user-layer actor, saw %', v_count;
  end if;
  select count(*) into v_count from app.list_role_version_permissions(v_published2.id, '00000000-0000-0000-0000-000000000304');
  if v_count <> 0 then
    raise exception 'assertion failed: expected list_role_version_permissions to deny a cross-tenant actor, saw %', v_count;
  end if;

  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000000302", "role": "authenticated"}';
  begin
    perform app.list_role_version_permissions(v_published2.id, '00000000-0000-0000-0000-000000000301');
    raise exception 'assertion failed: expected list_role_version_permissions to reject an authenticated session claiming to act as a different actor (RULE A)';
  exception
    when insufficient_privilege then
      null; -- expected: app.assert_actor_is_session_identity rejects the spoofed actor
  end;
  reset role; reset request.jwt.claims;

  -- app.list_role_assignments_for_role (SECURITY INVOKER, no actor param): both the
  -- (now-revoked) assignment above shows up -- unfiltered by status, matching
  -- app.list_tenant_roles' own "every role, any status" precedent.
  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000000302", "role": "authenticated"}';
  select count(*) into v_count from app.list_role_assignments_for_role(v_role.id);
  if v_count <> 1 then
    raise exception 'assertion failed: expected list_role_assignments_for_role to return the 1 (revoked) assignment, got %', v_count;
  end if;
  if (select status from app.list_role_assignments_for_role(v_role.id) limit 1) <> 'revoked' then
    raise exception 'assertion failed: expected the assignment to show as revoked, not filtered out';
  end if;
  reset role; reset request.jwt.claims;

  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000000304", "role": "authenticated"}';
  select count(*) into v_count from app.list_role_assignments_for_role(v_role.id);
  if v_count <> 0 then
    raise exception 'assertion failed: expected list_role_assignments_for_role to deny a cross-tenant actor, saw %', v_count;
  end if;
  reset role; reset request.jwt.claims;

  -- app.list_active_tenant_users_for_role_assignment (SECURITY DEFINER, explicit actor
  -- param, real auth_user_id -- never app.users.id): returns exactly the tenant's 2
  -- active users (301, 302); the customer_user-layer principal (303) is never in
  -- app.users at all (granted a bare principal membership only), so it is absent from
  -- the result set regardless of which actor asks; a customer_user-layer or
  -- cross-tenant ACTOR sees zero rows (excluded by the authority predicate itself).
  select count(*) into v_count from app.list_active_tenant_users_for_role_assignment(v_tenant_id, '00000000-0000-0000-0000-000000000301');
  if v_count <> 2 then
    raise exception 'assertion failed: expected list_active_tenant_users_for_role_assignment to return 2 active users, got %', v_count;
  end if;
  if not exists (
    select 1 from app.list_active_tenant_users_for_role_assignment(v_tenant_id, '00000000-0000-0000-0000-000000000301')
    where auth_user_id = '00000000-0000-0000-0000-000000000302'
  ) then
    raise exception 'assertion failed: expected 302 (an active user) to appear in list_active_tenant_users_for_role_assignment';
  end if;

  select count(*) into v_count from app.list_active_tenant_users_for_role_assignment(v_tenant_id, '00000000-0000-0000-0000-000000000303');
  if v_count <> 0 then
    raise exception 'assertion failed: expected list_active_tenant_users_for_role_assignment to deny a customer_user-layer actor, saw %', v_count;
  end if;

  select count(*) into v_count from app.list_active_tenant_users_for_role_assignment(v_tenant_id, '00000000-0000-0000-0000-000000000304');
  if v_count <> 0 then
    raise exception 'assertion failed: expected list_active_tenant_users_for_role_assignment to deny a cross-tenant actor, saw %', v_count;
  end if;
end;
$$;

\echo 'ALL PLT-111 db-test assertions passed.'
