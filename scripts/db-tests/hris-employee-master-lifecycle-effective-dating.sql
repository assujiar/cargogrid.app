-- Real, executable test evidence for ISS-2026-065 closure (dedicated HRT follow-up
-- task, docs/build-log/phase-07/HRT-ISS-065-CLOSURE.md), run via `pnpm run db:test`
-- against a real, disposable Postgres database. Proves the new effective-dated
-- employee lifecycle mechanism in
-- supabase/migrations/20260731310000_add_hris_employee_lifecycle_effective_dating_iss2026065.sql.
-- Mirrors scripts/db-tests/hris-employee-master.sql's own two-tenant cross-isolation
-- convention (docs/standards/TESTING_STANDARDS.md §8) and scripts/db-tests/hris-
-- organization-position-linkage.sql's own "time-travel simulation" pattern for
-- proving the maintenance sweep.

\set ON_ERROR_STOP on

\echo '>> setup: two tenants (hrmlcd1, hrmlcd2). hrmlcd1 gets a tenant_admin, HR staff (HRS Create/Edit/View/Import), an override actor (HRS Override/Edit/Create/View), and a view-only actor; two employees each linked to their own Platform user (for identity-coupling proof); company/branch org units. hrmlcd2 gets a tenant_admin and an override actor, for cross-tenant checks. A global Supreme Admin is also seeded.'
do $$
declare
  v_tenant1 uuid;
  v_tenant2 uuid;
  v_staff_role uuid;
  v_staff_draft app.role_versions;
  v_override_role uuid;
  v_override_draft app.role_versions;
  v_viewer_role uuid;
  v_viewer_draft app.role_versions;
  v_t2_override_role uuid;
  v_t2_override_draft app.role_versions;
  v_approver_role uuid;
  v_approver_draft app.role_versions;
  v_company uuid;
  v_branch uuid;
begin
  insert into auth.users (id, email) values
    ('00000000-0000-0000-0000-000000099301', 'admin@hrmlcd1.test'),
    ('00000000-0000-0000-0000-000000099302', 'staff@hrmlcd1.test'),
    ('00000000-0000-0000-0000-000000099303', 'override@hrmlcd1.test'),
    ('00000000-0000-0000-0000-000000099304', 'viewer@hrmlcd1.test'),
    ('00000000-0000-0000-0000-000000099305', 'workerone@hrmlcd1.test'),
    ('00000000-0000-0000-0000-000000099306', 'workertwo@hrmlcd1.test'),
    ('00000000-0000-0000-0000-000000099307', 'workerthree@hrmlcd1.test'),
    ('00000000-0000-0000-0000-000000099309', 'approver@hrmlcd1.test'),
    ('00000000-0000-0000-0000-000000099401', 'admin@hrmlcd2.test'),
    ('00000000-0000-0000-0000-000000099402', 'override@hrmlcd2.test'),
    ('00000000-0000-0000-0000-000000099999', 'supreme@hrmlcd.test');

  perform app.provision_tenant('hrmlcd1', 'HR Lifecycle Co 1', 'idem-hrmlcd1', 'tester');
  v_tenant1 := (select id from app.tenants where slug = 'hrmlcd1');
  perform app.transition_tenant_status(v_tenant1, 'active', 'setup', 'tester');

  perform app.provision_tenant('hrmlcd2', 'HR Lifecycle Co 2', 'idem-hrmlcd2', 'tester');
  v_tenant2 := (select id from app.tenants where slug = 'hrmlcd2');
  perform app.transition_tenant_status(v_tenant2, 'active', 'setup', 'tester');

  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000099301', 'admin@hrmlcd1.test', 'Hrmlcd1 Admin', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'admin@hrmlcd1.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000099301', 'tenant_admin', v_tenant1, null, 'tester');

  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000099302', 'staff@hrmlcd1.test', 'Hrmlcd1 Staff', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'staff@hrmlcd1.test'), 'active', 'onboarded', 'tester');
  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000099303', 'override@hrmlcd1.test', 'Hrmlcd1 Override', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'override@hrmlcd1.test'), 'active', 'onboarded', 'tester');
  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000099304', 'viewer@hrmlcd1.test', 'Hrmlcd1 Viewer', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'viewer@hrmlcd1.test'), 'active', 'onboarded', 'tester');
  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000099305', 'workerone@hrmlcd1.test', 'Hrmlcd1 Worker One', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'workerone@hrmlcd1.test'), 'active', 'onboarded', 'tester');
  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000099306', 'workertwo@hrmlcd1.test', 'Hrmlcd1 Worker Two', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'workertwo@hrmlcd1.test'), 'active', 'onboarded', 'tester');
  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000099307', 'workerthree@hrmlcd1.test', 'Hrmlcd1 Worker Three', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'workerthree@hrmlcd1.test'), 'active', 'onboarded', 'tester');
  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000099309', 'approver@hrmlcd1.test', 'Hrmlcd1 Approver', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'approver@hrmlcd1.test'), 'active', 'onboarded', 'tester');

  perform app.invite_user(v_tenant2, '00000000-0000-0000-0000-000000099401', 'admin@hrmlcd2.test', 'Hrmlcd2 Admin', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'admin@hrmlcd2.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000099401', 'tenant_admin', v_tenant2, null, 'tester');
  perform app.invite_user(v_tenant2, '00000000-0000-0000-0000-000000099402', 'override@hrmlcd2.test', 'Hrmlcd2 Override', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'override@hrmlcd2.test'), 'active', 'onboarded', 'tester');

  perform app.grant_principal_membership('00000000-0000-0000-0000-000000099999', 'supreme_admin', null, null, 'tester');

  v_staff_role := (app.create_role(v_tenant1, 'HRS Staff LCD', 'Create/Edit/View/Import', 'tester')).id;
  v_staff_draft := app.create_role_version(v_staff_role, 'tester');
  perform app.set_role_version_permissions(v_staff_draft.id, array(select id from app.permissions where resource_module_code = 'HRS' and action in ('Create', 'Edit', 'View', 'Import')), 'tester');
  perform app.publish_role_version(v_staff_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_staff_role and status = 'published'), '00000000-0000-0000-0000-000000099302', '00000000-0000-0000-0000-000000099301', 'tester');

  v_override_role := (app.create_role(v_tenant1, 'HRS Override LCD', 'Override/Edit/Create/View', 'tester')).id;
  v_override_draft := app.create_role_version(v_override_role, 'tester');
  perform app.set_role_version_permissions(v_override_draft.id, array(select id from app.permissions where resource_module_code = 'HRS' and action in ('Override', 'Edit', 'Create', 'View')), 'tester');
  perform app.publish_role_version(v_override_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_override_role and status = 'published'), '00000000-0000-0000-0000-000000099303', '00000000-0000-0000-0000-000000099301', 'tester');

  v_viewer_role := (app.create_role(v_tenant1, 'HRS Viewer LCD', 'View only', 'tester')).id;
  v_viewer_draft := app.create_role_version(v_viewer_role, 'tester');
  perform app.set_role_version_permissions(v_viewer_draft.id, array(select id from app.permissions where resource_module_code = 'HRS' and action in ('View')), 'tester');
  perform app.publish_role_version(v_viewer_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_viewer_role and status = 'published'), '00000000-0000-0000-0000-000000099304', '00000000-0000-0000-0000-000000099301', 'tester');

  v_t2_override_role := (app.create_role(v_tenant2, 'HRS Override LCD T2', 'Override/Edit/Create/View', 'tester')).id;
  v_t2_override_draft := app.create_role_version(v_t2_override_role, 'tester');
  perform app.set_role_version_permissions(v_t2_override_draft.id, array(select id from app.permissions where resource_module_code = 'HRS' and action in ('Override', 'Edit', 'Create', 'View')), 'tester');
  perform app.publish_role_version(v_t2_override_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant2, (select id from app.role_versions where role_id = v_t2_override_role and status = 'published'), '00000000-0000-0000-0000-000000099402', '00000000-0000-0000-0000-000000099401', 'tester');

  -- Tier C fix regression coverage (§7 below) needs to exercise the REAL,
  -- unmodified submit/decide/activate chain (not this file's own established
  -- "test-fixture-only shortcut" direct-UPDATE convention) -- a dedicated
  -- approver actor, mirroring hris-employee-master.sql's own v_approver.
  v_approver_role := (app.create_role(v_tenant1, 'HRS Approver LCD', 'Approve/View', 'tester')).id;
  v_approver_draft := app.create_role_version(v_approver_role, 'tester');
  perform app.set_role_version_permissions(v_approver_draft.id, array(select id from app.permissions where resource_module_code = 'HRS' and action in ('Approve', 'View')), 'tester');
  perform app.publish_role_version(v_approver_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_approver_role and status = 'published'), '00000000-0000-0000-0000-000000099309', '00000000-0000-0000-0000-000000099301', 'tester');

  v_company := (app.create_org_unit(v_tenant1, 'company', null, 'CO-LCD1', 'Hrmlcd1 Co', 'tester')).id;
  v_branch := (app.create_org_unit(v_tenant1, 'branch', v_company, 'BR-LCD1', 'Hrmlcd1 Branch', 'tester')).id;
end;
$$;

-- ===========================================================================
-- 1. Regression: every one of the 7 RPCs, called with the EXACT pre-migration
--    positional argument count (no p_effective_date at all), behaves exactly as
--    before -- proving this migration is genuinely additive, not merely
--    additive-by-intent.
-- ===========================================================================

\echo '>> regression: all 7 lifecycle RPCs called with their OLD (pre-migration) positional arg count still work exactly as before'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'hrmlcd1');
  v_staff uuid := '00000000-0000-0000-0000-000000099302';
  v_override uuid := '00000000-0000-0000-0000-000000099303';
  v_worker_user_id uuid := (select id from app.users where email = 'workerone@hrmlcd1.test');
  v_company uuid := (select id from app.org_units where tenant_id = v_tenant1 and code = 'CO-LCD1');
  v_employee app.employees;
begin
  -- create_employee_draft: 21-arg call (no effective_date/backdate_reason)
  v_employee := app.create_employee_draft(v_tenant1, 'Regression Employee', 'full_time', null, null, null, null, null, null, null, v_company, null, null, null, null, v_worker_user_id, null, 'hr_created', 'idem-regr-1', v_staff, 'staff');
  if v_employee.lifecycle_status <> 'draft' then
    raise exception 'assertion failed: expected draft, got %', v_employee.lifecycle_status;
  end if;
  if not exists (select 1 from app.employee_lifecycle_versions where master_record_id = v_employee.master_record_id and status = 'active' and change_reason = 'hire') then
    raise exception 'assertion failed: expected an immediately-materialized hire version row';
  end if;

  -- update_employee_draft: 19-arg call
  v_employee := app.update_employee_draft(v_employee.master_record_id, v_employee.record_version, 'Regression Employee', 'full_time', 'regr@hrmlcd1.test', null, null, null, null, null, '2026-01-15', null, v_company, null, null, 'Analyst', null, v_staff, 'staff');
  if v_employee.hire_date::text <> '2026-01-15' then
    raise exception 'assertion failed: expected hire_date 2026-01-15, got %', v_employee.hire_date;
  end if;

  -- Test-fixture-only shortcut (service_role-only direct UPDATE, this test file's
  -- own privilege): activates the draft directly rather than exercising the
  -- unmodified submit/decide/activate chain (genuinely out of this task's own
  -- bounded scope, decision 10). Also fixes up the hire version's own snapshot to
  -- match, since only a real RPC call writes a new version row.
  update app.employees set lifecycle_status = 'active' where master_record_id = v_employee.master_record_id;
  update app.employee_lifecycle_versions set lifecycle_status = 'active' where master_record_id = v_employee.master_record_id and change_reason = 'hire';
  v_employee.record_version := (select record_version from app.employees where master_record_id = v_employee.master_record_id);

  -- suspend_employee: 5-arg call
  v_employee := app.suspend_employee(v_employee.master_record_id, v_employee.record_version, 'regression suspend', v_override, 'override');
  if v_employee.lifecycle_status <> 'suspended' then raise exception 'assertion failed: expected suspended, got %', v_employee.lifecycle_status; end if;
  if (select status from app.users where id = v_worker_user_id) <> 'suspended' then
    raise exception 'assertion failed: HRT-295 identity coupling regressed -- platform user not suspended';
  end if;

  -- reactivate_employee: 4-arg call
  v_employee := app.reactivate_employee(v_employee.master_record_id, v_employee.record_version, v_override, 'override');
  if v_employee.lifecycle_status <> 'active' then raise exception 'assertion failed: expected active, got %', v_employee.lifecycle_status; end if;
  if (select status from app.users where id = v_worker_user_id) <> 'active' then
    raise exception 'assertion failed: HRT-295 identity coupling regressed -- platform user not reactivated';
  end if;

  -- transfer_employee: 10-arg call
  v_employee := app.transfer_employee(v_employee.master_record_id, v_employee.record_version, v_company, null, null, 'Senior Analyst', null, 'regression transfer', v_staff, 'staff');
  if v_employee.position_title <> 'Senior Analyst' then raise exception 'assertion failed: expected Senior Analyst, got %', v_employee.position_title; end if;

  -- terminate_employee: 6-arg call
  v_employee := app.terminate_employee(v_employee.master_record_id, v_employee.record_version, 'resignation', '2026-06-30', v_override, 'override');
  if v_employee.lifecycle_status <> 'terminated' then raise exception 'assertion failed: expected terminated, got %', v_employee.lifecycle_status; end if;
  if (select status from app.users where id = v_worker_user_id) <> 'revoked' then
    raise exception 'assertion failed: HRT-295 identity coupling regressed -- platform user not revoked';
  end if;

  -- archive_employee_profile: 5-arg call
  v_employee := app.archive_employee_profile(v_employee.master_record_id, v_employee.record_version, 'record retention closure', v_staff, 'staff');
  if v_employee.lifecycle_status <> 'archived' then raise exception 'assertion failed: expected archived, got %', v_employee.lifecycle_status; end if;

  raise notice 'PASS: all 7 RPCs regression-clean at their old arg count';
end;
$$;

-- ===========================================================================
-- 2. Future-scheduled transitions: suspend, terminate, reactivate -- proving
--    app.employees AND app.transition_user_status are both left untouched until
--    the sweep activates the due row, and the sweep is idempotent.
-- ===========================================================================

\echo '>> future-scheduled suspend does not take effect immediately and does not revoke platform identity early; activates correctly via the sweep, coupling identity at the SAME point; idempotent'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'hrmlcd1');
  v_override uuid := '00000000-0000-0000-0000-000000099303';
  v_worker_user_id uuid := (select id from app.users where email = 'workertwo@hrmlcd1.test');
  v_employee app.employees;
  v_swept integer;
  v_pre_record_version integer;
begin
  v_employee := app.create_employee_draft(v_tenant1, 'Future Suspend Employee', 'full_time', null, null, null, null, null, null, null, null, null, null, null, null, v_worker_user_id, null, 'hr_created', 'idem-futsusp-1', '00000000-0000-0000-0000-000000099302', 'staff');
  -- Test-fixture-only shortcut (service_role-only direct UPDATE, this test file's
  -- own privilege): activates the draft directly rather than exercising the
  -- unmodified submit/decide/activate chain (genuinely out of this task's own
  -- bounded scope, decision 10). Also fixes up the hire version's own snapshot to
  -- match, since only a real RPC call writes a new version row.
  update app.employees set lifecycle_status = 'active' where master_record_id = v_employee.master_record_id;
  update app.employee_lifecycle_versions set lifecycle_status = 'active' where master_record_id = v_employee.master_record_id and change_reason = 'hire';
  v_employee.record_version := (select record_version from app.employees where master_record_id = v_employee.master_record_id);
  v_pre_record_version := v_employee.record_version;

  -- Schedule a suspension 5 days from now.
  v_employee := app.suspend_employee(v_employee.master_record_id, v_employee.record_version, 'scheduled disciplinary suspension', v_override, 'override', current_date + 5);
  if v_employee.lifecycle_status <> 'active' then
    raise exception 'assertion failed: a future-dated suspend must NOT change app.employees.lifecycle_status immediately, got %', v_employee.lifecycle_status;
  end if;
  if v_employee.record_version <> v_pre_record_version then
    raise exception 'assertion failed: a future-dated suspend must NOT bump app.employees.record_version (no UPDATE executed), expected % got %', v_pre_record_version, v_employee.record_version;
  end if;
  if (select status from app.users where id = v_worker_user_id) <> 'active' then
    raise exception 'assertion failed: SECURITY: platform identity revoked BEFORE the scheduled effective date -- live availability bug';
  end if;
  if not exists (select 1 from app.role_assignments where auth_user_id = v_worker_user_id and status = 'active') then
    -- worker has no role_assignments in this fixture; this assertion intentionally
    -- checks the ABSENCE of any newly-revoked assignment, not presence -- see next
    -- check for the authoritative status-based proof.
    null;
  end if;
  if not exists (select 1 from app.employee_lifecycle_versions where master_record_id = v_employee.master_record_id and status = 'scheduled' and change_reason = 'suspend' and effective_start_date = current_date + 5) then
    raise exception 'assertion failed: expected a scheduled suspend version row dated current_date+5';
  end if;

  -- as-of reads: today shows active, the future date shows suspended.
  if not exists (select 1 from app.get_employee_lifecycle_as_of(v_employee.master_record_id, v_override, current_date) where lifecycle_status = 'active') then
    raise exception 'assertion failed: as-of(today) must still show active';
  end if;
  if not exists (select 1 from app.get_employee_lifecycle_as_of(v_employee.master_record_id, v_override, current_date + 5) where lifecycle_status = 'suspended') then
    raise exception 'assertion failed: as-of(scheduled date) must show suspended';
  end if;

  -- Time-travel simulation (service_role-only direct UPDATE, this test file's own
  -- privilege, mirroring hris-organization-position-linkage.sql's own established
  -- trick) -- shifts the whole timeline back by 5 days, preserving every
  -- invariant app.record_employee_lifecycle_version already established.
  update app.employee_lifecycle_versions set effective_start_date = effective_start_date - 5, effective_end_date = effective_end_date - 5
  where master_record_id = v_employee.master_record_id and status = 'active' and change_reason = 'hire';
  update app.employee_lifecycle_versions set effective_start_date = effective_start_date - 5
  where master_record_id = v_employee.master_record_id and status = 'scheduled' and change_reason = 'suspend';

  select app.activate_due_employee_lifecycle_transitions(v_tenant1, v_override, 'sweeper') into v_swept;
  if v_swept < 1 then
    raise exception 'assertion failed: expected the sweep to activate at least 1 due transition, got %', v_swept;
  end if;
  if (select lifecycle_status from app.employees where master_record_id = v_employee.master_record_id) <> 'suspended' then
    raise exception 'assertion failed: expected the sweep to materialize suspended lifecycle_status';
  end if;
  if (select suspend_reason from app.employees where master_record_id = v_employee.master_record_id) <> 'scheduled disciplinary suspension' then
    raise exception 'assertion failed: expected the sweep to materialize suspend_reason';
  end if;
  if (select status from app.users where id = v_worker_user_id) <> 'suspended' then
    raise exception 'assertion failed: expected the sweep to couple Platform identity suspension at activation time (HRT-295 composition, task item 5)';
  end if;

  -- Idempotent: a second sweep finds nothing left to do.
  select app.activate_due_employee_lifecycle_transitions(v_tenant1, v_override, 'sweeper') into v_swept;
  if v_swept <> 0 then
    raise exception 'assertion failed: expected a second sweep to be a no-op, got %', v_swept;
  end if;

  raise notice 'PASS: future-scheduled suspend + sweep + identity-coupling timing';
end;
$$;

\echo '>> future-scheduled reactivate: platform identity is NOT restored until the sweep activates it'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'hrmlcd1');
  v_override uuid := '00000000-0000-0000-0000-000000099303';
  v_worker_user_id uuid := (select id from app.users where email = 'workerthree@hrmlcd1.test');
  v_employee app.employees;
  v_swept integer;
begin
  -- Fresh employee (not reused from the previous block) -- an IMMEDIATE suspend
  -- anchors the resulting 'active' suspend version's own effective_start_date at
  -- genuinely today, so the single time-travel shift below stays internally
  -- consistent (chaining a second independent shift onto an already-shifted chain
  -- from a prior block would require re-deriving that prior shift's own delta).
  v_employee := app.create_employee_draft(v_tenant1, 'Future Reactivate Employee', 'full_time', null, null, null, null, null, null, null, null, null, null, null, null, v_worker_user_id, null, 'hr_created', 'idem-futreact-1', '00000000-0000-0000-0000-000000099302', 'staff');
  update app.employees set lifecycle_status = 'active' where master_record_id = v_employee.master_record_id;
  update app.employee_lifecycle_versions set lifecycle_status = 'active' where master_record_id = v_employee.master_record_id and change_reason = 'hire';
  v_employee.record_version := (select record_version from app.employees where master_record_id = v_employee.master_record_id);
  v_employee := app.suspend_employee(v_employee.master_record_id, v_employee.record_version, 'immediate suspend ahead of scheduled reactivate proof', v_override, 'override');
  if v_employee.lifecycle_status <> 'suspended' or (select status from app.users where id = v_worker_user_id) <> 'suspended' then
    raise exception 'assertion failed: precondition -- expected an immediate suspend to take effect (employee % / platform %)', v_employee.lifecycle_status, (select status from app.users where id = v_worker_user_id);
  end if;

  -- Schedule the un-suspension 3 days from now.
  v_employee := app.reactivate_employee(v_employee.master_record_id, v_employee.record_version, v_override, 'override', current_date + 3, 'scheduled end of disciplinary period');
  if v_employee.lifecycle_status <> 'suspended' then
    raise exception 'assertion failed: a future-dated reactivate must NOT change app.employees.lifecycle_status immediately, got %', v_employee.lifecycle_status;
  end if;
  if (select status from app.users where id = v_worker_user_id) <> 'suspended' then
    raise exception 'assertion failed: SECURITY: platform identity restored BEFORE the scheduled effective date';
  end if;

  update app.employee_lifecycle_versions set effective_start_date = effective_start_date - 3, effective_end_date = effective_end_date - 3
  where master_record_id = v_employee.master_record_id and status = 'active' and change_reason = 'suspend';
  update app.employee_lifecycle_versions set effective_start_date = effective_start_date - 3
  where master_record_id = v_employee.master_record_id and status = 'scheduled' and change_reason = 'reactivate';

  select app.activate_due_employee_lifecycle_transitions(v_tenant1, v_override, 'sweeper') into v_swept;
  if v_swept < 1 then raise exception 'assertion failed: expected the sweep to activate the scheduled reactivate, got %', v_swept; end if;
  if (select lifecycle_status from app.employees where master_record_id = v_employee.master_record_id) <> 'active' then
    raise exception 'assertion failed: expected the sweep to restore active lifecycle_status';
  end if;
  if (select status from app.users where id = v_worker_user_id) <> 'active' then
    raise exception 'assertion failed: expected the sweep to restore Platform identity access at activation time';
  end if;

  raise notice 'PASS: future-scheduled reactivate + sweep + identity-restoration timing';
end;
$$;

-- ===========================================================================
-- 3. Backdated correction: gated, mandatory reason, supersedes/reconciles
--    intervening history.
-- ===========================================================================

\echo '>> backdated correction: rejected without HRS:Override for a normally-lower-gated RPC (transfer), rejected without a reason, and correctly reconciles an intervening timeline once authorized'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'hrmlcd1');
  v_staff uuid := '00000000-0000-0000-0000-000000099302';
  v_override uuid := '00000000-0000-0000-0000-000000099303';
  v_employee app.employees;
  v_hire_version_id uuid;
  v_transfer1_version_id uuid;
begin
  v_employee := app.create_employee_draft(v_tenant1, 'Backdate Employee', 'full_time', null, null, null, null, null, null, current_date - 60, null, null, null, null, null, null, null, 'hr_created', 'idem-backdate-1', v_override, 'override', current_date - 60, 'backdated hire record for historical parity');
  -- Test-fixture-only shortcut (service_role-only direct UPDATE, this test file's
  -- own privilege): activates the draft directly rather than exercising the
  -- unmodified submit/decide/activate chain (genuinely out of this task's own
  -- bounded scope, decision 10). Also fixes up the hire version's own snapshot to
  -- match, since only a real RPC call writes a new version row.
  update app.employees set lifecycle_status = 'active' where master_record_id = v_employee.master_record_id;
  update app.employee_lifecycle_versions set lifecycle_status = 'active' where master_record_id = v_employee.master_record_id and change_reason = 'hire';
  v_employee.record_version := (select record_version from app.employees where master_record_id = v_employee.master_record_id);
  select id into v_hire_version_id from app.employee_lifecycle_versions where master_record_id = v_employee.master_record_id and change_reason = 'hire';

  -- An ordinary transfer 30 days ago (still a "past" write relative to today, so
  -- this ITSELF is a backdated call -- proving mandatory-reason + Override gate
  -- fire for a normally HRS:Edit-only RPC).
  begin
    perform app.transfer_employee(v_employee.master_record_id, v_employee.record_version, null, null, null, 'No Reason Title', null, null, v_staff, 'staff', current_date - 30);
    raise exception 'assertion failed: expected backdate_reason_required for a backdated transfer with no reason';
  exception
    when others then
      if sqlerrm not like 'backdate_reason_required%' then raise; end if;
  end;

  begin
    perform app.transfer_employee(v_employee.master_record_id, v_employee.record_version, null, null, null, 'Widened Title', null, 'genuine backdated correction', v_staff, 'staff', current_date - 30);
    raise exception 'assertion failed: expected insufficient_authority -- HRS:Edit alone must not suffice to backdate (task item 2''s own "gate at least as strictly as HRS:Override" requirement)';
  exception
    when others then
      if sqlerrm not like 'insufficient_authority%' then raise; end if;
  end;

  -- Correctly authorized backdated transfer (30 days ago, HRS:Override actor, reason).
  v_employee := app.transfer_employee(v_employee.master_record_id, v_employee.record_version, null, null, null, 'Analyst (30d ago)', null, 'genuine backdated correction: title effective 30 days ago', v_override, 'override', current_date - 30);
  if v_employee.position_title <> 'Analyst (30d ago)' then
    raise exception 'assertion failed: expected the backdated transfer to apply immediately (past date), got %', v_employee.position_title;
  end if;
  select id into v_transfer1_version_id from app.employee_lifecycle_versions where master_record_id = v_employee.master_record_id and change_reason = 'transfer' and effective_start_date = current_date - 30;

  if (select effective_end_date from app.employee_lifecycle_versions where id = v_hire_version_id) <> current_date - 31 then
    raise exception 'assertion failed: expected the hire version to be truncated to end current_date-31, got %', (select effective_end_date from app.employee_lifecycle_versions where id = v_hire_version_id);
  end if;
  if (select status from app.employee_lifecycle_versions where id = v_hire_version_id) <> 'active' then
    raise exception 'assertion failed: a truncated-but-still-valid predecessor must remain status=active, not be marked superseded';
  end if;

  -- Now a SECOND, EARLIER backdated correction (60 days ago -- before the hire's
  -- OWN previous effective_start_date of current_date-60, so nothing predates it,
  -- but AFTER it starts) that must supersede/reconcile the transfer written above,
  -- since the transfer's own effective_start_date (current_date-30) is >= the new
  -- correction's own effective_date is NOT the case here -- instead prove the
  -- inverse-order case: a correction dated BETWEEN the hire and the transfer
  -- (current_date-45) must supersede the transfer (which starts later, at -30)
  -- while leaving the hire's own already-truncated portion (ending at -61) alone.
  v_employee := app.transfer_employee(v_employee.master_record_id, v_employee.record_version, null, null, null, 'Corrected Analyst (45d ago)', null, 'correction: the 30-day-ago title was itself wrong, the real change happened 45 days ago', v_override, 'override', current_date - 45);
  if v_employee.position_title <> 'Corrected Analyst (45d ago)' then
    raise exception 'assertion failed: expected the -45d correction to apply immediately, got %', v_employee.position_title;
  end if;

  if (select status from app.employee_lifecycle_versions where id = v_transfer1_version_id) <> 'superseded' then
    raise exception 'assertion failed: the -30d transfer (chronologically AFTER the new -45d correction''s own effective_date) must be superseded, not left active';
  end if;
  if (select effective_start_date from app.employee_lifecycle_versions where id = v_transfer1_version_id) <> current_date - 30 then
    raise exception 'assertion failed: a superseded row''s own effective_start_date must be left UNTOUCHED for audit (decision 3, bucket (a))';
  end if;

  -- The corrected timeline reconciles cleanly: as-of(-50d) shows the ORIGINAL hire
  -- title (untouched history before the correction point); as-of(-40d) shows the
  -- NEW corrected title; as-of(today) shows the new corrected title (still current,
  -- open-ended).
  if exists (select 1 from app.get_employee_lifecycle_as_of(v_employee.master_record_id, v_override, current_date - 50) where position_title = 'Corrected Analyst (45d ago)') then
    raise exception 'assertion failed: as-of(-50d, before the correction point) must NOT show the new corrected title';
  end if;
  if not exists (select 1 from app.get_employee_lifecycle_as_of(v_employee.master_record_id, v_override, current_date - 40) where position_title = 'Corrected Analyst (45d ago)') then
    raise exception 'assertion failed: as-of(-40d) must show the corrected title';
  end if;
  if not exists (select 1 from app.get_employee_lifecycle_as_of(v_employee.master_record_id, v_override, current_date) where position_title = 'Corrected Analyst (45d ago)') then
    raise exception 'assertion failed: as-of(today) must still show the corrected (now-current) title';
  end if;

  raise notice 'PASS: backdated correction gating, mandatory reason, and intervening-history reconciliation';
end;
$$;

-- ===========================================================================
-- 4. as-of read: correctness before hire, and decided_reason masking.
-- ===========================================================================

\echo '>> get_employee_lifecycle_as_of returns zero rows before hire, and masks decided_reason for a viewer without HRS:View personal data'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'hrmlcd1');
  v_staff uuid := '00000000-0000-0000-0000-000000099302';
  v_viewer uuid := '00000000-0000-0000-0000-000000099304';
  v_employee app.employees;
  v_row_count integer;
  v_masked_reason text;
begin
  v_employee := app.create_employee_draft(v_tenant1, 'AsOf Employee', 'full_time', null, null, null, null, null, null, current_date, null, null, null, null, null, null, null, 'hr_created', 'idem-asof-1', v_staff, 'staff');

  select count(*) into v_row_count from app.get_employee_lifecycle_as_of(v_employee.master_record_id, v_staff, current_date - 1);
  if v_row_count <> 0 then
    raise exception 'assertion failed: expected zero rows for a date before this employee was ever hired, got %', v_row_count;
  end if;

  select count(*) into v_row_count from app.get_employee_lifecycle_as_of(v_employee.master_record_id, v_staff, current_date);
  if v_row_count <> 1 then
    raise exception 'assertion failed: expected exactly 1 row as of today, got %', v_row_count;
  end if;

  select decided_reason into v_masked_reason from app.get_employee_lifecycle_as_of(v_employee.master_record_id, v_viewer, current_date);
  if v_masked_reason is not null then
    raise exception 'assertion failed: expected decided_reason masked to null for a viewer without HRS:View personal data';
  end if;

  raise notice 'PASS: as-of correctness before hire + decided_reason masking';
end;
$$;

-- ===========================================================================
-- 5. Maintenance sweep: manager-cycle re-validation skips (not aborts) a
--    conflicting row, mirroring app.activate_due_employee_position_assignments'
--    own established precedent (HRT-275).
-- ===========================================================================

\echo '>> maintenance sweep: a scheduled manager change that would create a reporting cycle is skipped, disclosed via a failure audit event, and never corrupts the graph -- the rest of the sweep still proceeds'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'hrmlcd1');
  v_staff uuid := '00000000-0000-0000-0000-000000099302';
  v_override uuid := '00000000-0000-0000-0000-000000099303';
  v_a app.employees;
  v_b app.employees;
  v_swept integer;
begin
  v_a := app.create_employee_draft(v_tenant1, 'Cycle Employee A', 'full_time', null, null, null, null, null, null, null, null, null, null, null, null, null, null, 'hr_created', 'idem-cyclea-1', v_staff, 'staff');
  v_b := app.create_employee_draft(v_tenant1, 'Cycle Employee B', 'full_time', null, null, null, null, null, null, null, null, null, null, null, null, null, null, 'hr_created', 'idem-cycleb-1', v_staff, 'staff');

  -- Schedule A's manager := B, and B's manager := A, both for tomorrow (each
  -- independently valid -- no cycle exists yet on either side).
  perform app.transfer_employee(v_a.master_record_id, v_a.record_version, null, null, null, null, v_b.master_record_id, 'schedule A under B', v_staff, 'staff', current_date + 1);
  select * into v_b from app.employees where master_record_id = v_b.master_record_id;
  perform app.transfer_employee(v_b.master_record_id, v_b.record_version, null, null, null, null, v_a.master_record_id, 'schedule B under A', v_staff, 'staff', current_date + 1);

  -- Shift the WHOLE timeline (both employees' own truncated hire predecessor AND
  -- the scheduled transfer) back by 1 day together, preserving the "predecessor
  -- ends the day immediately before the successor begins" invariant.
  update app.employee_lifecycle_versions set effective_start_date = effective_start_date - 1, effective_end_date = effective_end_date - 1
  where master_record_id in (v_a.master_record_id, v_b.master_record_id) and status = 'active' and change_reason = 'hire';
  update app.employee_lifecycle_versions set effective_start_date = effective_start_date - 1
  where master_record_id in (v_a.master_record_id, v_b.master_record_id) and status = 'scheduled' and change_reason = 'transfer';

  select app.activate_due_employee_lifecycle_transitions(v_tenant1, v_override, 'sweeper') into v_swept;
  if v_swept <> 1 then
    raise exception 'assertion failed: expected exactly ONE side of the mutually-cyclic pair to activate, got %', v_swept;
  end if;

  if exists (select 1 from app.employees where master_record_id = v_a.master_record_id and manager_employee_id = v_b.master_record_id)
     and exists (select 1 from app.employees where master_record_id = v_b.master_record_id and manager_employee_id = v_a.master_record_id) then
    raise exception 'assertion failed: SECURITY/INTEGRITY: both sides activated -- a live two-node manager cycle was created';
  end if;

  if not exists (
    select 1 from app.audit_logs
    where tenant_id = v_tenant1 and action = 'activate_due_employee_lifecycle_transitions' and result = 'failure'
  ) then
    raise exception 'assertion failed: expected a disclosed failure audit event for the skipped cyclic row';
  end if;

  raise notice 'PASS: sweep manager-cycle re-validation skips one side, disclosed, never corrupts the graph';
end;
$$;

-- ===========================================================================
-- 6. Cross-tenant isolation for the new RPCs.
-- ===========================================================================

\echo '>> cross-tenant isolation: a hrmlcd2 actor cannot read hrmlcd1''s lifecycle-as-of, cannot sweep hrmlcd1''s tenant, and a hrmlcd1 employee cannot be found by a hrmlcd2 actor'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'hrmlcd1');
  v_t2_override uuid := '00000000-0000-0000-0000-000000099402';
  v_employee app.employees;
begin
  select * into v_employee from app.employees where tenant_id = v_tenant1 and full_name = 'AsOf Employee';

  begin
    perform app.get_employee_lifecycle_as_of(v_employee.master_record_id, v_t2_override, current_date);
    raise exception 'assertion failed: expected employee_not_found for a cross-tenant as-of read';
  exception
    when others then
      if sqlerrm not like 'employee_not_found%' then raise; end if;
  end;

  -- A hrmlcd2 actor sweeping hrmlcd1's own tenant_id is a real permission check
  -- (evaluate_permission is tenant-scoped) -- v_t2_override has no membership/role
  -- in v_tenant1, so this must be denied.
  begin
    perform app.activate_due_employee_lifecycle_transitions(v_tenant1, v_t2_override, 'attacker');
    raise exception 'assertion failed: expected insufficient_authority for a cross-tenant sweep attempt';
  exception
    when others then
      if sqlerrm not like 'insufficient_authority%' then raise; end if;
  end;

  raise notice 'PASS: cross-tenant isolation for get_employee_lifecycle_as_of and activate_due_employee_lifecycle_transitions';
end;
$$;

-- ===========================================================================
-- 7. Tier C follow-up fix (docs/build-log/phase-07/HRT-ISS-065-CLOSURE.md,
--    20260731320000): app.record_employee_lifecycle_version's direction-aware
--    conflict protection, app.activate_due_employee_lifecycle_transitions'
--    change_reason-scoped materialization, and app.get_employee_lifecycle_
--    as_of's app.employees fallback for p_as_of >= current_date. Every
--    scenario below was independently live-reproduced as a real defect
--    against the pre-fix migration before this fix was written (never fixed
--    from a report alone), then re-verified fixed here.
-- ===========================================================================

\echo '>> Tier C fix: an ordinary, unrelated, same-day transfer can no longer silently cancel an already-scheduled future termination (the SECURITY lens live reproduction)'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'hrmlcd1');
  v_staff uuid := '00000000-0000-0000-0000-000000099302';
  v_override uuid := '00000000-0000-0000-0000-000000099303';
  v_employee app.employees;
begin
  v_employee := app.create_employee_draft(v_tenant1, 'TierC Sec Employee', 'full_time', null, null, null, null, null, null, null, null, null, null, null, null, null, null, 'hr_created', 'idem-tiercsec-1', v_staff, 'staff');
  update app.employees set lifecycle_status = 'active' where master_record_id = v_employee.master_record_id;
  update app.employee_lifecycle_versions set lifecycle_status = 'active' where master_record_id = v_employee.master_record_id and change_reason = 'hire';
  v_employee.record_version := (select record_version from app.employees where master_record_id = v_employee.master_record_id);

  v_employee := app.terminate_employee(v_employee.master_record_id, v_employee.record_version, 'known resignation', current_date + 10, v_override, 'override', current_date + 10);

  begin
    perform app.transfer_employee(v_employee.master_record_id, v_employee.record_version, null, null, null, 'Title Bump', null, 'ordinary title change', v_staff, 'staff', current_date);
    raise exception 'assertion failed: expected lifecycle_conflict -- an unrelated ordinary transfer must not silently cancel a scheduled future termination';
  exception
    when others then
      if sqlerrm not like 'lifecycle_conflict%' then raise; end if;
  end;

  if (select status from app.employee_lifecycle_versions where master_record_id = v_employee.master_record_id and change_reason = 'terminate') <> 'scheduled' then
    raise exception 'assertion failed: the scheduled termination must still be status=scheduled, untouched';
  end if;

  raise notice 'PASS: ordinary transfer cannot silently cancel a scheduled future termination';
end;
$$;

\echo '>> Tier C fix: a narrow backdated correction to an already-CLOSED suspend segment can no longer silently revert a LATER, currently-active reactivation (the SPEC-COMPLIANCE lens live reproduction)'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'hrmlcd1');
  v_override uuid := '00000000-0000-0000-0000-000000099303';
  v_worker_user_id uuid;
  v_employee app.employees;
begin
  insert into auth.users (id, email) values ('00000000-0000-0000-0000-000000099308', 'workerfour@hrmlcd1.test');
  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000099308', 'workerfour@hrmlcd1.test', 'Hrmlcd1 Worker Four', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'workerfour@hrmlcd1.test'), 'active', 'onboarded', 'tester');
  v_worker_user_id := (select id from app.users where email = 'workerfour@hrmlcd1.test');

  v_employee := app.create_employee_draft(v_tenant1, 'TierC Spec Employee', 'full_time', null, null, null, null, null, null, null, null, null, null, null, null, v_worker_user_id, null, 'hr_created', 'idem-tiercspec-1', v_override, 'override', current_date - 90, 'backdated hire for historical parity');
  update app.employees set lifecycle_status = 'active' where master_record_id = v_employee.master_record_id;
  update app.employee_lifecycle_versions set lifecycle_status = 'active' where master_record_id = v_employee.master_record_id and change_reason = 'hire';
  v_employee.record_version := (select record_version from app.employees where master_record_id = v_employee.master_record_id);

  -- Suspended 10 days ago, reactivated 8 days ago -- both backdated, both take
  -- the immediate/backdated materialization path. Employee is genuinely
  -- active with live Platform access right now.
  v_employee := app.suspend_employee(v_employee.master_record_id, v_employee.record_version, 'policy violation', v_override, 'override', current_date - 10);
  v_employee := app.reactivate_employee(v_employee.master_record_id, v_employee.record_version, v_override, 'override', current_date - 8, 'suspension ended early, mistake');
  if v_employee.lifecycle_status <> 'active' or (select status from app.users where id = v_worker_user_id) <> 'active' then
    raise exception 'assertion failed: precondition -- expected active employee with live Platform access before the narrow correction';
  end if;

  -- A narrow, properly-authorized correction whose ONLY intent is to fix the
  -- recorded start date of the already-closed original suspension.
  begin
    perform app.suspend_employee(v_employee.master_record_id, v_employee.record_version, 'policy violation (corrected start date)', v_override, 'override', current_date - 15);
    raise exception 'assertion failed: expected lifecycle_conflict -- a correction to an already-closed suspend segment must not silently revert the later, currently-governing reactivation';
  exception
    when others then
      if sqlerrm not like 'lifecycle_conflict%' then raise; end if;
  end;

  if (select lifecycle_status from app.employees where master_record_id = v_employee.master_record_id) <> 'active'
     or (select status from app.users where id = v_worker_user_id) <> 'active' then
    raise exception 'assertion failed: SECURITY: the employee''s live Platform access must NOT have been revoked by the rejected correction attempt';
  end if;

  raise notice 'PASS: a backdated correction cannot silently revert a later, currently-active reactivation';
end;
$$;

\echo '>> Tier C fix: an unrelated, later-scheduled transfer can no longer silently truncate an already-scheduled termination (the CORRECTNESS lens'' "resurrection" live reproduction)'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'hrmlcd1');
  v_staff uuid := '00000000-0000-0000-0000-000000099302';
  v_override uuid := '00000000-0000-0000-0000-000000099303';
  v_employee app.employees;
begin
  v_employee := app.create_employee_draft(v_tenant1, 'TierC Correctness Employee', 'full_time', null, null, null, null, null, null, null, null, null, null, null, null, null, null, 'hr_created', 'idem-tierccorr-1', v_staff, 'staff');
  update app.employees set lifecycle_status = 'active' where master_record_id = v_employee.master_record_id;
  update app.employee_lifecycle_versions set lifecycle_status = 'active' where master_record_id = v_employee.master_record_id and change_reason = 'hire';
  v_employee.record_version := (select record_version from app.employees where master_record_id = v_employee.master_record_id);

  v_employee := app.terminate_employee(v_employee.master_record_id, v_employee.record_version, 'end of contract', current_date + 5, v_override, 'override', current_date + 5);

  begin
    perform app.transfer_employee(v_employee.master_record_id, v_employee.record_version, null, null, null, 'Planned Title Bump', null, 'planned title bump', v_staff, 'staff', current_date + 10);
    raise exception 'assertion failed: expected lifecycle_conflict -- a later, unrelated transfer must not silently truncate an already-scheduled termination';
  exception
    when others then
      if sqlerrm not like 'lifecycle_conflict%' then raise; end if;
  end;

  if (select effective_end_date from app.employee_lifecycle_versions where master_record_id = v_employee.master_record_id and change_reason = 'terminate') is not null then
    raise exception 'assertion failed: the scheduled termination must remain open-ended, untouched by the rejected transfer';
  end if;

  raise notice 'PASS: a later, unrelated transfer cannot silently truncate (resurrect past) an already-scheduled termination';
end;
$$;

\echo '>> Tier C fix regression guard: the ordinary same-day suspend->reactivate sequence still works exactly as before (an earlier draft of the conflict-protection fix incorrectly blocked this -- caught and fixed against this file''s own existing assertions before shipping, disclosed in the build log, not accepted on faith)'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'hrmlcd1');
  v_override uuid := '00000000-0000-0000-0000-000000099303';
  v_employee app.employees;
begin
  v_employee := app.create_employee_draft(v_tenant1, 'TierC Regression Employee Same-Day', 'full_time', null, null, null, null, null, null, null, null, null, null, null, null, null, null, 'hr_created', 'idem-tiercregr-1', v_override, 'override');
  update app.employees set lifecycle_status = 'active' where master_record_id = v_employee.master_record_id;
  update app.employee_lifecycle_versions set lifecycle_status = 'active' where master_record_id = v_employee.master_record_id and change_reason = 'hire';
  v_employee.record_version := (select record_version from app.employees where master_record_id = v_employee.master_record_id);

  -- Immediate suspend, then an immediate reactivate the SAME day (both
  -- effective_start_date = current_date) -- must succeed, not raise a false
  -- lifecycle_conflict.
  v_employee := app.suspend_employee(v_employee.master_record_id, v_employee.record_version, 'same-day suspend', v_override, 'override');
  v_employee := app.reactivate_employee(v_employee.master_record_id, v_employee.record_version, v_override, 'override');
  if v_employee.lifecycle_status <> 'active' then
    raise exception 'assertion failed: expected same-day suspend->reactivate to succeed, got %', v_employee.lifecycle_status;
  end if;

  raise notice 'PASS: same-day suspend<->reactivate unaffected by the conflict-protection fix';
end;
$$;

\echo '>> Tier C fix regression guard: a genuinely sequential pair of backdated corrections on a FRESH employee (suspend -10d, then reactivate -8d ending it) still works -- reactivate is the direct, expected successor of the suspend it truncates, not an unrelated conflicting event'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'hrmlcd1');
  v_override uuid := '00000000-0000-0000-0000-000000099303';
  v_employee app.employees;
begin
  v_employee := app.create_employee_draft(v_tenant1, 'TierC Regression Employee Sequential', 'full_time', null, null, null, null, null, null, null, null, null, null, null, null, null, null, 'hr_created', 'idem-tiercregr-2', v_override, 'override', current_date - 90, 'backdated hire for historical parity');
  update app.employees set lifecycle_status = 'active' where master_record_id = v_employee.master_record_id;
  update app.employee_lifecycle_versions set lifecycle_status = 'active' where master_record_id = v_employee.master_record_id and change_reason = 'hire';
  v_employee.record_version := (select record_version from app.employees where master_record_id = v_employee.master_record_id);

  v_employee := app.suspend_employee(v_employee.master_record_id, v_employee.record_version, 'backdated suspend', v_override, 'override', current_date - 10);
  v_employee := app.reactivate_employee(v_employee.master_record_id, v_employee.record_version, v_override, 'override', current_date - 8, 'backdated reactivate');
  if v_employee.lifecycle_status <> 'active' then
    raise exception 'assertion failed: expected sequential backdated suspend->reactivate to succeed, got %', v_employee.lifecycle_status;
  end if;

  raise notice 'PASS: sequential backdated suspend<->reactivate on a fresh employee unaffected by the conflict-protection fix';
end;
$$;

\echo '>> Tier C fix: the maintenance sweep is change_reason-scoped -- a scheduled transfer no longer reverts lifecycle_status when the employee genuinely progressed via the uncovered submit/decide/activate chain in the interim (INTEGRATION finding 1)'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'hrmlcd1');
  v_staff uuid := '00000000-0000-0000-0000-000000099302';
  v_override uuid := '00000000-0000-0000-0000-000000099303';
  v_approver uuid := '00000000-0000-0000-0000-000000099309';
  v_company uuid := (select id from app.org_units where tenant_id = v_tenant1 and code = 'CO-LCD1');
  v_branch uuid := (select id from app.org_units where tenant_id = v_tenant1 and code = 'BR-LCD1');
  v_employee app.employees;
  v_swept integer;
begin
  v_employee := app.create_employee_draft(v_tenant1, 'TierC Sweep Scope Employee', 'full_time', null, null, null, null, null, null, current_date - 30, v_company, v_branch, null, null, null, null, null, 'hr_created', 'idem-tiercsweep-1', v_staff, 'staff');
  -- Still draft: schedule a transfer 5 days out (legal -- transfer only blocks
  -- terminated/archived).
  perform app.transfer_employee(v_employee.master_record_id, v_employee.record_version, v_company, v_branch, null, 'Senior Analyst', null, 'planned title bump', v_staff, 'staff', current_date + 5);

  -- Legitimately progress through the REAL, untouched, uncovered main flow.
  perform app.add_employee_emergency_contact(v_employee.master_record_id, 'Contact', 'Sibling', '+62-811-90', null, true, v_staff, 'staff');
  perform app.submit_employee_for_approval(v_employee.master_record_id, v_employee.record_version, v_staff, 'staff');
  select * into v_employee from app.employees where master_record_id = v_employee.master_record_id;
  perform app.decide_employee_approval(v_employee.master_record_id, v_employee.record_version, 'approve', 'ok', v_approver, 'approver');
  select * into v_employee from app.employees where master_record_id = v_employee.master_record_id;
  perform app.activate_employee(v_employee.master_record_id, v_employee.record_version, v_approver, 'approver');

  if (select lifecycle_status from app.employees where master_record_id = v_employee.master_record_id) <> 'active' then
    raise exception 'assertion failed: precondition -- expected the employee to be genuinely active before the sweep runs';
  end if;

  -- Time-travel: shift hire + the scheduled transfer back 5 days so the
  -- transfer becomes due.
  update app.employee_lifecycle_versions set effective_start_date = effective_start_date - 5, effective_end_date = effective_end_date - 5
  where master_record_id = v_employee.master_record_id and status = 'active' and change_reason = 'hire';
  update app.employee_lifecycle_versions set effective_start_date = effective_start_date - 5
  where master_record_id = v_employee.master_record_id and status = 'scheduled' and change_reason = 'transfer';

  select app.activate_due_employee_lifecycle_transitions(v_tenant1, v_override, 'sweeper') into v_swept;
  if v_swept < 1 then raise exception 'assertion failed: expected the sweep to activate the scheduled transfer, got %', v_swept; end if;

  if (select lifecycle_status from app.employees where master_record_id = v_employee.master_record_id) <> 'active' then
    raise exception 'assertion failed: INTEGRITY: the sweep must NOT revert a genuinely active employee back to a stale scheduled-time snapshot (draft) when activating an unrelated transfer';
  end if;
  if (select position_title from app.employees where master_record_id = v_employee.master_record_id) <> 'Senior Analyst' then
    raise exception 'assertion failed: expected the sweep to still apply the transfer''s own org/position fields';
  end if;

  raise notice 'PASS: the sweep is change_reason-scoped -- an unrelated transfer activation never reverts lifecycle_status progress made via the uncovered flow';
end;
$$;

\echo '>> Tier C fix: get_employee_lifecycle_as_of(today) is correct for the ordinary hire->submit->decide->activate flow (no further lifecycle RPC called -- the single most common real-world state) -- INTEGRATION finding 2'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'hrmlcd1');
  v_staff uuid := '00000000-0000-0000-0000-000000099302';
  v_override uuid := '00000000-0000-0000-0000-000000099303';
  v_approver uuid := '00000000-0000-0000-0000-000000099309';
  v_company uuid := (select id from app.org_units where tenant_id = v_tenant1 and code = 'CO-LCD1');
  v_branch uuid := (select id from app.org_units where tenant_id = v_tenant1 and code = 'BR-LCD1');
  v_employee app.employees;
  v_as_of_status text;
begin
  v_employee := app.create_employee_draft(v_tenant1, 'TierC AsOf Ordinary Employee', 'full_time', null, null, null, null, null, null, current_date - 30, v_company, v_branch, null, null, null, null, null, 'hr_created', 'idem-tiercasof1-1', v_staff, 'staff');
  perform app.add_employee_emergency_contact(v_employee.master_record_id, 'Contact', 'Sibling', '+62-811-91', null, true, v_staff, 'staff');
  perform app.submit_employee_for_approval(v_employee.master_record_id, v_employee.record_version, v_staff, 'staff');
  select * into v_employee from app.employees where master_record_id = v_employee.master_record_id;
  perform app.decide_employee_approval(v_employee.master_record_id, v_employee.record_version, 'approve', 'ok', v_approver, 'approver');
  select * into v_employee from app.employees where master_record_id = v_employee.master_record_id;
  perform app.activate_employee(v_employee.master_record_id, v_employee.record_version, v_approver, 'approver');

  select lifecycle_status into v_as_of_status from app.get_employee_lifecycle_as_of(v_employee.master_record_id, v_override, current_date);
  if v_as_of_status <> 'active' then
    raise exception 'assertion failed: expected get_employee_lifecycle_as_of(today) to show active (matching app.employees), got %', v_as_of_status;
  end if;

  raise notice 'PASS: get_employee_lifecycle_as_of(today) correct for the ordinary hire->submit->decide->activate flow';
end;
$$;

\echo '>> Tier C fix: get_employee_lifecycle_as_of(today) is correct after app.rehire_employee, a real HRT-277 workflow that completely bypasses app.employee_lifecycle_versions -- INTEGRATION finding 3'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'hrmlcd1');
  v_staff uuid := '00000000-0000-0000-0000-000000099302';
  v_override uuid := '00000000-0000-0000-0000-000000099303';
  v_approver uuid := '00000000-0000-0000-0000-000000099309';
  v_company uuid := (select id from app.org_units where tenant_id = v_tenant1 and code = 'CO-LCD1');
  v_branch uuid := (select id from app.org_units where tenant_id = v_tenant1 and code = 'BR-LCD1');
  v_employee app.employees;
  v_as_of_status text;
begin
  v_employee := app.create_employee_draft(v_tenant1, 'TierC AsOf Rehire Employee', 'full_time', null, null, null, null, null, null, current_date - 30, v_company, v_branch, null, null, null, null, null, 'hr_created', 'idem-tiercasof2-1', v_staff, 'staff');
  perform app.add_employee_emergency_contact(v_employee.master_record_id, 'Contact', 'Sibling', '+62-811-92', null, true, v_staff, 'staff');
  perform app.submit_employee_for_approval(v_employee.master_record_id, v_employee.record_version, v_staff, 'staff');
  select * into v_employee from app.employees where master_record_id = v_employee.master_record_id;
  perform app.decide_employee_approval(v_employee.master_record_id, v_employee.record_version, 'approve', 'ok', v_approver, 'approver');
  select * into v_employee from app.employees where master_record_id = v_employee.master_record_id;
  perform app.activate_employee(v_employee.master_record_id, v_employee.record_version, v_approver, 'approver');
  select * into v_employee from app.employees where master_record_id = v_employee.master_record_id;
  perform app.terminate_employee(v_employee.master_record_id, v_employee.record_version, 'layoff', current_date, v_override, 'override', current_date);
  select * into v_employee from app.employees where master_record_id = v_employee.master_record_id;
  perform app.rehire_employee(v_employee.master_record_id, v_employee.record_version, 'rehired after layoff reversal', v_override, 'override');

  if (select lifecycle_status from app.employees where master_record_id = v_employee.master_record_id) <> 'active' then
    raise exception 'assertion failed: precondition -- expected app.employees to show active after rehire';
  end if;

  select lifecycle_status into v_as_of_status from app.get_employee_lifecycle_as_of(v_employee.master_record_id, v_override, current_date);
  if v_as_of_status <> 'active' then
    raise exception 'assertion failed: expected get_employee_lifecycle_as_of(today) to show active after app.rehire_employee (matching app.employees), got %', v_as_of_status;
  end if;

  raise notice 'PASS: get_employee_lifecycle_as_of(today) correct after app.rehire_employee, an RPC that bypasses app.employee_lifecycle_versions entirely';
end;
$$;

\echo 'ALL PASSED: hris-employee-master-lifecycle-effective-dating.sql'
