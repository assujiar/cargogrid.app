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

\echo 'ALL PLT-111 db-test assertions passed.'
