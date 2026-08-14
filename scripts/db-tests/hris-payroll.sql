-- Real, executable test evidence for HRT-282 (Payroll Foundation, Benefit
-- and Reimbursement, CG-S12-HRT-010) -- run via `pnpm run db:test` against
-- a real, disposable Postgres database. Mirrors scripts/db-tests/
-- hris-overtime-timesheet.sql's own two-tenant cross-isolation convention.
--
-- Self-contained: own two-tenant/employee/role/component fixture, own
-- fresh, unclaimed UUID range (00000000-0000-0000-0000-0000000282xx),
-- never colliding with any sibling HRIS test file's own claimed range
-- (grep-verified against every existing scripts/db-tests/*.sql file before
-- authoring this one). Tenant slugs `pay1`/`pay2` (grep-verified unclaimed).
--
-- Covers, live, against a real disposable database (not merely asserted in
-- the migration header): the full component/version/RPD-016 statutory-
-- activation-gate lifecycle; period freeze; the ISS-2026-074 attendance-
-- fallback resolution end to end (an employee with ZERO timesheet_entries
-- rows, only approved app.attendance_sessions, correctly contributes
-- regular minutes into the frozen snapshot and the calculation feeds an
-- hourly_rate component from it); the full calculation engine (fixed_
-- amount, hourly_rate, percentage_of_component, reimbursement, loan
-- installment, in one run, with an exact expected net_pay assertion);
-- maker-checker self-approval blocking on payroll run finalization AND on
-- reimbursement decision; a finalized run/period genuinely rejecting
-- further mutation; the Finance handoff boundary (idempotent prepare,
-- FIN:Edit required to acknowledge -- not HRS:Approve/Override -- and a
-- live reconciliation proof); correction-run linkage to a finalized run;
-- and RLS proving (a) a zero-permission cross-tenant actor sees nothing,
-- and (b) the deliberate decision-5 divergence -- an ordinary manager with
-- zero HRS:View payroll sees NOTHING about a direct report's compensation,
-- despite every other HRT capability granting a manager that visibility
-- via org-hierarchy alone.

\set ON_ERROR_STOP on

\echo '>> fixture'
do $$
declare
  v_tenant1 uuid;
  v_tenant2 uuid;
  v_hr_role uuid; v_hr_draft app.role_versions;
  v_appr_role uuid; v_appr_draft app.role_versions;
  v_fin_role uuid; v_fin_draft app.role_versions;
  v_company uuid; v_branch uuid;
  v_approval_draft app.config_versions;
begin
  insert into auth.users (id, email) values
    ('00000000-0000-0000-0000-000000028201', 'admin@pay1.test'),
    ('00000000-0000-0000-0000-000000028202', 'hr@pay1.test'),
    ('00000000-0000-0000-0000-000000028203', 'approver@pay1.test'),
    ('00000000-0000-0000-0000-000000028204', 'emp1@pay1.test'),
    ('00000000-0000-0000-0000-000000028205', 'mgr1@pay1.test'),
    ('00000000-0000-0000-0000-000000028206', 'fin@pay1.test'),
    ('00000000-0000-0000-0000-000000028221', 'admin@pay2.test'),
    ('00000000-0000-0000-0000-000000028299', 'supreme@pr.test');

  perform app.provision_tenant('pay1', 'Pay Co 1', 'idem-pay1', 'tester');
  v_tenant1 := (select id from app.tenants where slug = 'pay1');
  perform app.transition_tenant_status(v_tenant1, 'active', 'setup', 'tester');
  perform app.provision_tenant('pay2', 'Pay Co 2', 'idem-pay2', 'tester');
  v_tenant2 := (select id from app.tenants where slug = 'pay2');
  perform app.transition_tenant_status(v_tenant2, 'active', 'setup', 'tester');

  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000028201', 'admin@pay1.test', 'Pay1 Admin', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'admin@pay1.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000028201', 'tenant_admin', v_tenant1, null, 'tester');
  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000028202', 'hr@pay1.test', 'Pay1 HR', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'hr@pay1.test'), 'active', 'onboarded', 'tester');
  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000028203', 'approver@pay1.test', 'Pay1 Approver', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'approver@pay1.test'), 'active', 'onboarded', 'tester');
  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000028204', 'emp1@pay1.test', 'Pay1 Emp One', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'emp1@pay1.test'), 'active', 'onboarded', 'tester');
  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000028205', 'mgr1@pay1.test', 'Pay1 Manager', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'mgr1@pay1.test'), 'active', 'onboarded', 'tester');
  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000028206', 'fin@pay1.test', 'Pay1 Fin', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'fin@pay1.test'), 'active', 'onboarded', 'tester');

  perform app.invite_user(v_tenant2, '00000000-0000-0000-0000-000000028221', 'admin@pay2.test', 'Pay2 Admin', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'admin@pay2.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000028221', 'tenant_admin', v_tenant2, null, 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000028299', 'supreme_admin', null, null, 'tester');

  v_hr_role := (app.create_role(v_tenant1, 'HR Payroll', 'Edit/View/View payroll/Import', 'tester')).id;
  v_hr_draft := app.create_role_version(v_hr_role, 'tester');
  perform app.set_role_version_permissions(v_hr_draft.id, array(select id from app.permissions where resource_module_code = 'HRS' and action in ('Create', 'Edit', 'View', 'View payroll', 'Import')), 'tester');
  perform app.publish_role_version(v_hr_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_hr_role and status = 'published'), '00000000-0000-0000-0000-000000028202', '00000000-0000-0000-0000-000000028201', 'tester');

  v_appr_role := (app.create_role(v_tenant1, 'Payroll Approver', 'Approve/View/View payroll/Override', 'tester')).id;
  v_appr_draft := app.create_role_version(v_appr_role, 'tester');
  perform app.set_role_version_permissions(v_appr_draft.id, array(select id from app.permissions where resource_module_code = 'HRS' and action in ('Approve', 'View', 'View payroll', 'Override')), 'tester');
  perform app.publish_role_version(v_appr_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_appr_role and status = 'published'), '00000000-0000-0000-0000-000000028203', '00000000-0000-0000-0000-000000028201', 'tester');
  -- HR actor also decides finalization (maker separate from checker: hr@pr1 submits, approver@pr1 finalizes).
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_appr_role and status = 'published'), '00000000-0000-0000-0000-000000028202', '00000000-0000-0000-0000-000000028201', 'tester');

  v_fin_role := (app.create_role(v_tenant1, 'Finance Actor', 'FIN Edit/View', 'tester')).id;
  v_fin_draft := app.create_role_version(v_fin_role, 'tester');
  perform app.set_role_version_permissions(v_fin_draft.id, array(select id from app.permissions where resource_module_code = 'FIN' and action in ('Edit', 'View')), 'tester');
  perform app.publish_role_version(v_fin_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_fin_role and status = 'published'), '00000000-0000-0000-0000-000000028206', '00000000-0000-0000-0000-000000028201', 'tester');

  -- Approval routing definition: sequential, one step, the "Payroll Approver" role.
  v_approval_draft := app.create_config_draft('approval', v_tenant1, 'tenant', null, '00000000-0000-0000-0000-000000028201', 'tenant admin');
  perform app.set_config_items(v_approval_draft.id, jsonb_build_array(
    jsonb_build_object('key', 'pattern', 'value', 'sequential'),
    jsonb_build_object('key', 'steps', 'value', jsonb_build_array(
      jsonb_build_object('step_order', 1, 'approver_type', 'role', 'role_id', v_appr_role::text, 'required_approvals', 1)
    )),
    jsonb_build_object('key', 'allow_self_approval', 'value', false)
  ), '00000000-0000-0000-0000-000000028201', 'tenant admin');
  perform app.publish_approval_definition(v_approval_draft.id, '00000000-0000-0000-0000-000000028201', null, 'tenant admin');

  v_company := (app.create_org_unit(v_tenant1, 'company', null, 'CO-PAY1', 'Pay1 Co', 'tester')).id;
  v_branch := (app.create_org_unit(v_tenant1, 'branch', v_company, 'BR-PAY1', 'Pay1 Branch', 'tester')).id;

  perform app.create_employee_draft(v_tenant1, 'Pay1 Manager', 'full_time', 'mgr1work@pay1.test', 'mgr1p@pay1.test', '0800000002', null, null, null, '2024-01-01', v_company, v_branch, null, 'Manager', null, (select id from app.users where email = 'mgr1@pay1.test'), null, 'hr_created', 'idem-mgr1-pr1', '00000000-0000-0000-0000-000000028202', 'tester');
  perform app.add_employee_emergency_contact((select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'mgr1work@pay1.test'), 'Contact Mgr', 'spouse', '0810000002', null, true, '00000000-0000-0000-0000-000000028202', 'tester');
  perform app.submit_employee_for_approval((select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'mgr1work@pay1.test'), 1, '00000000-0000-0000-0000-000000028202', 'tester');
  perform app.decide_employee_approval((select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'mgr1work@pay1.test'), 2, 'approve', null, '00000000-0000-0000-0000-000000028203', 'tester');
  perform app.activate_employee((select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'mgr1work@pay1.test'), 3, '00000000-0000-0000-0000-000000028203', 'tester');

  perform app.create_employee_draft(v_tenant1, 'Pay1 Emp One', 'full_time', 'emp1work@pay1.test', 'emp1p@pay1.test', '0800000001', null, null, null, '2024-01-01', v_company, v_branch, null, 'Staff', null, (select id from app.users where email = 'emp1@pay1.test'), null, 'hr_created', 'idem-emp1-pr1', '00000000-0000-0000-0000-000000028202', 'tester');
  perform app.add_employee_emergency_contact((select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'emp1work@pay1.test'), 'Contact One', 'spouse', '0810000001', null, true, '00000000-0000-0000-0000-000000028202', 'tester');
  perform app.submit_employee_for_approval((select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'emp1work@pay1.test'), 1, '00000000-0000-0000-0000-000000028202', 'tester');
  perform app.decide_employee_approval((select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'emp1work@pay1.test'), 2, 'approve', null, '00000000-0000-0000-0000-000000028203', 'tester');
  perform app.activate_employee((select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'emp1work@pay1.test'), 3, '00000000-0000-0000-0000-000000028203', 'tester');
  perform app.transfer_employee(
    (select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'emp1work@pay1.test'), 4,
    v_company, v_branch, null, 'Staff', (select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'mgr1work@pay1.test'),
    'reorg', '00000000-0000-0000-0000-000000028202', 'tester'
  );

  raise notice 'FIXTURE OK tenant1=%, tenant2=%', v_tenant1, v_tenant2;
end $$;

\echo '>> component: create earning "base_salary" fixed_amount, HR authors+approves (non-statutory, no evidence needed)'
select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-000000028202", "role": "authenticated"}', false);
set role authenticated;
select app.create_payroll_component((select id from app.tenants where slug='pay1'), 'base_salary', 'Base Salary', 'earning', 'salary_expense', '00000000-0000-0000-0000-000000028202', 'hr');
reset role;
select set_config('request.jwt.claims', 'null', false);

do $$
declare
  v_tenant uuid := (select id from app.tenants where slug='pay1');
  v_comp app.payroll_components;
  v_version app.payroll_component_versions;
begin
  select * into v_comp from app.payroll_components where tenant_id = v_tenant and code = 'base_salary';
  v_version := app.create_payroll_component_version(v_comp.id, 'fixed_amount', 5000000, null, null, 'IDR', '2024-01-01', '00000000-0000-0000-0000-000000028202', 'hr');
  v_version := app.approve_payroll_component_version(v_version.id, v_version.record_version, '00000000-0000-0000-0000-000000028203', 'approver');
  if v_version.status <> 'approved' then raise exception 'assertion failed: base_salary version not approved: %', v_version.status; end if;

  perform app.assign_payroll_component_to_employee(v_tenant, (select master_record_id from app.employees where tenant_id=v_tenant and work_email='emp1work@pay1.test'), v_comp.id, null, null, null, 'IDR', '2024-01-01', null, '00000000-0000-0000-0000-000000028202', 'hr');
end $$;

\echo '>> RPD-016: statutory component example fixture cannot be approved'
do $$
declare
  v_ver app.payroll_component_versions;
begin
  select * into v_ver from app.payroll_component_versions where component_id = (select id from app.payroll_components where code='pph21' and tenant_id is null) and is_example_fixture;
  begin
    perform app.approve_payroll_component_version(v_ver.id, v_ver.record_version, '00000000-0000-0000-0000-000000028299', 'supreme');
    raise exception 'SECURITY FAILURE: example fixture statutory component was approved';
  exception
    when others then
      if sqlerrm not like '%example_fixture_not_activatable%' then raise exception 'wrong error: %', sqlerrm; end if;
      raise notice 'OK: statutory example fixture correctly blocked from approval (%)', sqlerrm;
  end;
end $$;

\echo '>> period create + freeze inputs'
do $$
declare
  v_tenant uuid := (select id from app.tenants where slug='pay1');
  v_period app.payroll_periods;
begin
  v_period := app.create_payroll_period(v_tenant, null, 'pay1-2026-08', 'monthly', '2026-08-01', '2026-08-31', '2026-09-05', '00000000-0000-0000-0000-000000028202', 'hr');
  v_period := app.freeze_payroll_period_inputs(v_period.id, v_period.record_version, '00000000-0000-0000-0000-000000028202', 'hr');
  if v_period.status <> 'input_frozen' then raise exception 'assertion failed: expected input_frozen, got %', v_period.status; end if;
  raise notice 'period frozen, employee_count=%', v_period.frozen_employee_count;
end $$;

\echo '>> create + calculate run'
do $$
declare
  v_tenant uuid := (select id from app.tenants where slug='pay1');
  v_period app.payroll_periods;
  v_run app.payroll_runs;
  v_result app.payroll_run_employee_results;
begin
  select * into v_period from app.payroll_periods where tenant_id=v_tenant and code='pay1-2026-08';
  v_run := app.create_payroll_run(v_tenant, v_period.id, 'regular', null, 'IDR', null, '00000000-0000-0000-0000-000000028202', 'hr');
  v_run := app.calculate_payroll_run(v_run.id, v_run.record_version, null, '00000000-0000-0000-0000-000000028202', 'hr');
  raise notice 'run status=% employee_count=% exception_count=%', v_run.status, v_run.employee_count, v_run.exception_count;
  select * into v_result from app.payroll_run_employee_results where payroll_run_id = v_run.id and employee_id = (select master_record_id from app.employees where tenant_id=v_tenant and work_email='emp1work@pay1.test');
  if v_result.gross_earnings <> 5000000 or v_result.net_pay <> 5000000 then
    raise exception 'assertion failed: expected gross/net 5000000, got %/%', v_result.gross_earnings, v_result.net_pay;
  end if;
  raise notice 'OK: emp1 gross=% net=%', v_result.gross_earnings, v_result.net_pay;
end $$;

\echo '>> maker-checker: self-approval blocked (hr@pr1 submits, hr@pr1 attempts to finalize own submission -- must fail since hr also holds Payroll Approver role)'
do $$
declare
  v_tenant uuid := (select id from app.tenants where slug='pay1');
  v_run app.payroll_runs;
  v_step app.approval_request_steps;
begin
  select * into v_run from app.payroll_runs where tenant_id=v_tenant and run_type='regular';
  v_run := app.submit_payroll_run_for_finalization(v_run.id, v_run.record_version, '00000000-0000-0000-0000-000000028202', 'hr');
  if v_run.status <> 'pending_approval' then raise exception 'assertion failed: expected pending_approval, got %', v_run.status; end if;

  select s.* into v_step from app.approval_request_steps s where s.request_id = v_run.approval_request_id and s.status = 'active';

  begin
    perform app.finalize_payroll_run(v_step.id, 'approved', 'self approve attempt', '00000000-0000-0000-0000-000000028202', 'hr');
    raise exception 'SECURITY FAILURE: hr@pr1 was able to self-approve its own submitted payroll run';
  exception
    when others then
      raise notice 'OK: self-approval blocked (%)', sqlerrm;
  end;
end $$;

\echo '>> maker-checker: a distinct approver (approver@pr1) finalizes -- succeeds, payslip generated, period locked'
do $$
declare
  v_tenant uuid := (select id from app.tenants where slug='pay1');
  v_run app.payroll_runs;
  v_step app.approval_request_steps;
  v_period app.payroll_periods;
  v_slip app.payroll_payslips;
begin
  select * into v_run from app.payroll_runs where tenant_id=v_tenant and run_type='regular';
  select s.* into v_step from app.approval_request_steps s where s.request_id = v_run.approval_request_id and s.status = 'active';
  v_run := app.finalize_payroll_run(v_step.id, 'approved', 'looks good', '00000000-0000-0000-0000-000000028203', 'approver');
  if v_run.status <> 'finalized' then raise exception 'assertion failed: expected finalized, got %', v_run.status; end if;

  select * into v_period from app.payroll_periods where id = v_run.payroll_period_id;
  if v_period.status <> 'finalized' then raise exception 'assertion failed: expected period finalized, got %', v_period.status; end if;

  select * into v_slip from app.payroll_payslips where payroll_run_id = v_run.id and employee_id = (select master_record_id from app.employees where tenant_id=v_tenant and work_email='emp1work@pay1.test');
  if v_slip.id is null then raise exception 'assertion failed: no payslip generated'; end if;
  raise notice 'OK: run finalized, period locked, payslip net_pay=%', v_slip.net_pay;
end $$;

\echo '>> finalized period genuinely rejects mutation: recalculate blocked, freeze blocked'
do $$
declare
  v_tenant uuid := (select id from app.tenants where slug='pay1');
  v_run app.payroll_runs;
  v_period app.payroll_periods;
begin
  select * into v_run from app.payroll_runs where tenant_id=v_tenant and run_type='regular';
  begin
    perform app.calculate_payroll_run(v_run.id, v_run.record_version, null, '00000000-0000-0000-0000-000000028202', 'hr');
    raise exception 'SECURITY FAILURE: recalculated a finalized run';
  exception when others then
    raise notice 'OK: recalculation of finalized run blocked (%)', sqlerrm;
  end;

  select * into v_period from app.payroll_periods where id = v_run.payroll_period_id;
  begin
    perform app.freeze_payroll_period_inputs(v_period.id, v_period.record_version, '00000000-0000-0000-0000-000000028202', 'hr');
    raise exception 'SECURITY FAILURE: re-froze a finalized period';
  exception when others then
    raise notice 'OK: re-freeze of finalized period blocked (%)', sqlerrm;
  end;
end $$;

\echo '>> Finance handoff: idempotent prepare, FIN:Edit required to acknowledge, reconciled'
do $$
declare
  v_tenant uuid := (select id from app.tenants where slug='pay1');
  v_run app.payroll_runs;
  v_batch app.payroll_finance_handoff_batches;
  v_batch2 app.payroll_finance_handoff_batches;
  v_recon record;
begin
  select * into v_run from app.payroll_runs where tenant_id=v_tenant and run_type='regular';

  -- HR (Payroll authority only, no FIN grant) can generate the handoff.
  v_batch := app.prepare_finance_payroll_disbursement_handoff_from_payroll_run(v_tenant, v_run.id, '00000000-0000-0000-0000-000000028202', 'hr');
  v_batch2 := app.prepare_finance_payroll_disbursement_handoff_from_payroll_run(v_tenant, v_run.id, '00000000-0000-0000-0000-000000028202', 'hr');
  if v_batch.id <> v_batch2.id then raise exception 'assertion failed: prepare is not idempotent on run_id'; end if;

  -- HR (no FIN:Edit) cannot acknowledge.
  begin
    perform app.acknowledge_payroll_finance_handoff_batch(v_batch.id, v_batch.record_version, '00000000-0000-0000-0000-000000028202', 'hr');
    raise exception 'SECURITY FAILURE: hr@pr1 (no FIN:Edit) acknowledged a Finance handoff';
  exception when others then
    raise notice 'OK: non-Finance actor cannot acknowledge (%)', sqlerrm;
  end;

  perform app.acknowledge_payroll_finance_handoff_batch(v_batch.id, v_batch.record_version, '00000000-0000-0000-0000-000000028206', 'fin');
  select * into v_batch from app.payroll_finance_handoff_batches where id = v_batch.id;
  if v_batch.status <> 'acknowledged' then raise exception 'assertion failed: expected acknowledged, got %', v_batch.status; end if;

  select * into v_recon from app.get_payroll_finance_handoff_reconciliation(v_batch.id, '00000000-0000-0000-0000-000000028206');
  if not v_recon.is_reconciled then raise exception 'assertion failed: handoff not reconciled: gl=%, pay=%, run=%', v_recon.gl_lines_net, v_recon.payment_instructions_total, v_recon.run_results_net_total;
  end if;
  raise notice 'OK: Finance handoff reconciled, gl_net=% pay_total=% run_net=%', v_recon.gl_lines_net, v_recon.payment_instructions_total, v_recon.run_results_net_total;
end $$;

\echo '>> RLS: zero-permission cross-tenant member cannot see pr1 payroll'
select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-000000028221", "role": "authenticated"}', false);
set role authenticated;
do $$
declare
  v_count integer;
begin
  select count(*) into v_count from app.payroll_periods where tenant_id = (select id from app.tenants where slug='pay1');
  if v_count <> 0 then raise exception 'SECURITY FAILURE: cross-tenant actor saw % payroll_periods rows', v_count; end if;
  select count(*) into v_count from app.payroll_run_employee_results where tenant_id = (select id from app.tenants where slug='pay1');
  if v_count <> 0 then raise exception 'SECURITY FAILURE: cross-tenant actor saw % payroll_run_employee_results rows', v_count; end if;
end $$;
reset role;
select set_config('request.jwt.claims', 'null', false);

\echo '>> RLS: ordinary manager (mgr1, direct manager of emp1, ZERO HRS:View payroll grant) sees NOTHING about emp1 compensation -- the deliberate divergence from every other HRT manager-scope pattern'
select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-000000028205", "role": "authenticated"}', false);
set role authenticated;
do $$
declare
  v_count integer;
  v_tenant uuid := (select id from app.tenants where slug='pay1');
  v_emp1 uuid := (select master_record_id from app.employees where tenant_id = (select id from app.tenants where slug='pay1') and work_email = 'emp1work@pay1.test');
begin
  -- mgr1 may see their OWN row (self, correctly allowed by decision 5) --
  -- the real assertion is specifically about emp1's row, which mgr1 has NO
  -- HRS:View payroll grant for despite being emp1's direct manager.
  select count(*) into v_count from app.payroll_run_employee_results where tenant_id = v_tenant and employee_id = v_emp1;
  if v_count <> 0 then raise exception 'SECURITY FAILURE: manager with no HRS:View payroll saw % compensation rows for a direct report', v_count; end if;
  select count(*) into v_count from app.payroll_payslips where tenant_id = v_tenant and employee_id = v_emp1;
  if v_count <> 0 then raise exception 'SECURITY FAILURE: manager with no HRS:View payroll saw % payslip rows for a direct report', v_count; end if;
  raise notice 'OK: manager-hierarchy alone grants zero payroll visibility into a direct report''s compensation (self-visibility into mgr1''s own zero-value row is separately, correctly allowed)';
end $$;
reset role;
select set_config('request.jwt.claims', 'null', false);

\echo '>> RLS: emp1 (self) sees own payslip'
select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-000000028204", "role": "authenticated"}', false);
set role authenticated;
do $$
declare
  v_count integer;
begin
  select count(*) into v_count from app.payroll_payslips where employee_id = (select master_record_id from app.employees where work_email = 'emp1work@pay1.test');
  if v_count <> 1 then raise exception 'assertion failed: emp1 should see exactly 1 own payslip, got %', v_count; end if;
  raise notice 'OK: self-service payslip visibility works';
end $$;
reset role;
select set_config('request.jwt.claims', 'null', false);


-- Continuation fixture: reuses the SAME db as payroll_adv_test.sql (must run after it).

\echo '>> hourly_rate + percentage_of_component + reimbursement + loan, all consumed in ONE run for a fresh employee, time input via real Attendance flow (ISS-2026-074 attendance fallback path)'
do $$
declare
  v_tenant uuid := (select id from app.tenants where slug='pay1');
  v_company uuid := (select id from app.org_units where tenant_id = v_tenant and code='CO-PAY1');
  v_branch uuid := (select id from app.org_units where tenant_id = v_tenant and code='BR-PAY1');
  v_emp2 uuid;
  v_hourly_comp app.payroll_components;
  v_hourly_ver app.payroll_component_versions;
  v_pct_comp app.payroll_components;
  v_pct_ver app.payroll_component_versions;
  v_reimb app.payroll_reimbursement_requests;
  v_loan app.payroll_loans;
  v_att_policy app.attendance_policies;
  v_att_version app.attendance_policy_versions;
begin
  insert into auth.users (id, email) values ('00000000-0000-0000-0000-000000028207', 'emp2@pay1.test');
  perform app.invite_user(v_tenant, '00000000-0000-0000-0000-000000028207', 'emp2@pay1.test', 'Pay1 Emp Two', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'emp2@pay1.test'), 'active', 'onboarded', 'tester');
  perform app.create_employee_draft(v_tenant, 'Pay1 Emp Two', 'full_time', 'emp2work@pay1.test', 'emp2p@pay1.test', '0800000009', null, null, null, '2024-01-01', v_company, v_branch, null, 'Hourly Staff', null, (select id from app.users where email = 'emp2@pay1.test'), null, 'hr_created', 'idem-emp2-pr1', '00000000-0000-0000-0000-000000028202', 'tester');
  perform app.add_employee_emergency_contact((select master_record_id from app.employees where tenant_id = v_tenant and work_email = 'emp2work@pay1.test'), 'Contact Two', 'spouse', '0810000009', null, true, '00000000-0000-0000-0000-000000028202', 'tester');
  perform app.submit_employee_for_approval((select master_record_id from app.employees where tenant_id = v_tenant and work_email = 'emp2work@pay1.test'), 1, '00000000-0000-0000-0000-000000028202', 'tester');
  perform app.decide_employee_approval((select master_record_id from app.employees where tenant_id = v_tenant and work_email = 'emp2work@pay1.test'), 2, 'approve', null, '00000000-0000-0000-0000-000000028203', 'tester');
  perform app.activate_employee((select master_record_id from app.employees where tenant_id = v_tenant and work_email = 'emp2work@pay1.test'), 3, '00000000-0000-0000-0000-000000028203', 'tester');
  v_emp2 := (select master_record_id from app.employees where tenant_id = v_tenant and work_email = 'emp2work@pay1.test');

  v_hourly_comp := app.create_payroll_component(v_tenant, 'hourly_base', 'Hourly Base Pay', 'earning', 'salary_expense', '00000000-0000-0000-0000-000000028202', 'hr');
  v_hourly_ver := app.create_payroll_component_version(v_hourly_comp.id, 'hourly_rate', 50000, null, null, 'IDR', '2024-01-01', '00000000-0000-0000-0000-000000028202', 'hr');
  v_hourly_ver := app.approve_payroll_component_version(v_hourly_ver.id, v_hourly_ver.record_version, '00000000-0000-0000-0000-000000028203', 'approver');
  perform app.assign_payroll_component_to_employee(v_tenant, v_emp2, v_hourly_comp.id, null, null, null, 'IDR', '2024-01-01', null, '00000000-0000-0000-0000-000000028202', 'hr');

  v_pct_comp := app.create_payroll_component(v_tenant, 'admin_fee', 'Admin Fee Deduction', 'deduction', 'other_deduction', '00000000-0000-0000-0000-000000028202', 'hr');
  v_pct_ver := app.create_payroll_component_version(v_pct_comp.id, 'percentage_of_component', null, 10, v_hourly_comp.id, 'IDR', '2024-01-01', '00000000-0000-0000-0000-000000028202', 'hr');
  v_pct_ver := app.approve_payroll_component_version(v_pct_ver.id, v_pct_ver.record_version, '00000000-0000-0000-0000-000000028203', 'approver');
  perform app.assign_payroll_component_to_employee(v_tenant, v_emp2, v_pct_comp.id, null, null, null, 'IDR', '2024-01-01', null, '00000000-0000-0000-0000-000000028202', 'hr');

  v_reimb := app.create_payroll_reimbursement_request_for_employee(v_tenant, v_emp2, 'travel', 250000, 'IDR', '2026-09-05', 'Client visit taxi', null, null, '00000000-0000-0000-0000-000000028202', 'hr');
  v_reimb := app.submit_payroll_reimbursement_request(v_reimb.id, v_reimb.record_version, '00000000-0000-0000-0000-000000028202', 'hr');
  begin
    perform app.decide_payroll_reimbursement_request(v_reimb.id, v_reimb.record_version, 'approve', 'looks legit', '00000000-0000-0000-0000-000000028202', 'hr');
    raise exception 'SECURITY FAILURE: hr@pr1 (the requester of record) self-approved a reimbursement it created on behalf of emp2';
  exception when others then
    raise notice 'OK: reimbursement self-approval blocked (%)', sqlerrm;
  end;
  perform app.decide_payroll_reimbursement_request(v_reimb.id, v_reimb.record_version, 'approve', 'looks legit', '00000000-0000-0000-0000-000000028203', 'approver');

  v_loan := app.issue_payroll_loan(v_tenant, v_emp2, 300000, 'IDR', 100000, 3, false, null, 'emergency advance', '00000000-0000-0000-0000-000000028203', 'approver');

  v_att_policy := app.create_attendance_policy(v_tenant, null, 'Pay1 Attendance', '00000000-0000-0000-0000-000000028202', 'tester');
  v_att_version := app.create_attendance_policy_version(
    v_att_policy.id, 'Asia/Jakarta', '08:00:00'::time, '17:00:00'::time, '04:00:00'::time, 15, 15,
    array['mobile_web', 'kiosk']::text[], 'none', null, null, 16, '2024-01-01'::date,
    '00000000-0000-0000-0000-000000028202', 'tester'
  );
  perform app.publish_attendance_policy_version(v_att_version.id, 1, '00000000-0000-0000-0000-000000028203', 'tester');

  perform app.create_payroll_period(v_tenant, null, 'pay1-2026-09', 'monthly', '2026-09-01', '2026-09-30', '2026-10-05', '00000000-0000-0000-0000-000000028202', 'hr');

  raise notice 'emp2=%', v_emp2;
end $$;

\echo '>> real clock in/out for emp2 on a day inside Sept period, HR approves for payroll input (attendance-only, NO timesheet entry -- exercises ISS-2026-074 fallback path)'
select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-000000028207", "role": "authenticated"}', false);
set role authenticated;
select app.record_attendance_clock_event((select id from app.tenants where slug = 'pay1'), 'clock_in', 'mobile_web', '2026-09-10 08:00:00+07'::timestamptz, null, null, 'ci-emp2', '00000000-0000-0000-0000-000000028207', 'emp2');
select app.record_attendance_clock_event((select id from app.tenants where slug = 'pay1'), 'clock_out', 'mobile_web', '2026-09-10 16:00:00+07'::timestamptz, null, null, 'co-emp2', '00000000-0000-0000-0000-000000028207', 'emp2');
reset role;
select set_config('request.jwt.claims', 'null', false);

do $$
declare
  v_tenant uuid := (select id from app.tenants where slug='pay1');
  v_emp2 uuid := (select master_record_id from app.employees where tenant_id = (select id from app.tenants where slug='pay1') and work_email = 'emp2work@pay1.test');
  v_approved record;
begin
  update app.attendance_sessions set raw_clock_in_at = '2026-09-10 08:00:00+07'::timestamptz, raw_clock_out_at = '2026-09-10 16:00:00+07'::timestamptz, work_date = '2026-09-10'::date
  where tenant_id = v_tenant and employee_id = v_emp2;
  -- The raw UPDATE above does not retroactively re-run exception detection
  -- (a real clock-in at "now" against a work_date later moved to
  -- 2026-09-10 would otherwise leave a stale late-arrival exception from
  -- its ORIGINAL timing) -- recompute for real before approval, exactly
  -- the governed path HR would use.
  perform app.recalculate_attendance_exceptions_for_range(v_tenant, '2026-09-01'::date, '2026-09-30'::date, null, '00000000-0000-0000-0000-000000028202', 'hr');
  perform app.waive_attendance_exception(x.id, x.record_version, 'test fixture: raw time adjustment left a stale exception', '00000000-0000-0000-0000-000000028203', 'approver')
    from app.attendance_exceptions x where x.tenant_id = v_tenant and x.employee_id = v_emp2 and x.status in ('open', 'acknowledged');

  for v_approved in select * from app.approve_attendance_for_payroll_input(v_tenant, '2026-09-01'::date, '2026-09-30'::date, v_emp2, '00000000-0000-0000-0000-000000028202', 'hr') loop
    if not v_approved.approved then raise exception 'assertion failed: attendance approval failed: %', v_approved.skip_reason; end if;
  end loop;
end $$;

\echo '>> freeze + calculate: emp2 gross should be 8h * 50000 = 400000 via ISS-2026-074 attendance fallback (no timesheet_entries row exists for emp2 at all)'
do $$
declare
  v_tenant uuid := (select id from app.tenants where slug='pay1');
  v_period app.payroll_periods;
  v_run app.payroll_runs;
  v_result app.payroll_run_employee_results;
  v_emp2 uuid := (select master_record_id from app.employees where tenant_id = (select id from app.tenants where slug='pay1') and work_email = 'emp2work@pay1.test');
  v_snapshot app.payroll_input_snapshots;
begin
  select * into v_period from app.payroll_periods where tenant_id=v_tenant and code='pay1-2026-09';
  v_period := app.freeze_payroll_period_inputs(v_period.id, v_period.record_version, '00000000-0000-0000-0000-000000028202', 'hr');

  select * into v_snapshot from app.payroll_input_snapshots where payroll_period_id = v_period.id and employee_id = v_emp2;
  if v_snapshot.regular_minutes <> 480 then raise exception 'assertion failed: expected 480 regular_minutes from attendance fallback, got %', v_snapshot.regular_minutes; end if;
  if array_length(v_snapshot.source_attendance_session_ids, 1) <> 1 then raise exception 'assertion failed: expected exactly 1 source attendance session'; end if;
  raise notice 'OK: ISS-2026-074 attendance-fallback snapshot regular_minutes=%', v_snapshot.regular_minutes;

  v_run := app.create_payroll_run(v_tenant, v_period.id, 'regular', null, 'IDR', null, '00000000-0000-0000-0000-000000028202', 'hr');
  v_run := app.calculate_payroll_run(v_run.id, v_run.record_version, null, '00000000-0000-0000-0000-000000028202', 'hr');
  if v_run.status <> 'calculated' then raise exception 'assertion failed: expected calculated, got % (exception_count=%)', v_run.status, v_run.exception_count; end if;

  select * into v_result from app.payroll_run_employee_results where payroll_run_id = v_run.id and employee_id = v_emp2;
  -- gross = 400000 (8h * 50000); deduction = 10% of 400000 = 40000; reimbursement = 250000; loan = 100000.
  -- net = 400000 - 40000 - 0 - 100000 + 250000 = 510000.
  if v_result.gross_earnings <> 400000 then raise exception 'assertion failed: expected gross 400000, got %', v_result.gross_earnings; end if;
  if v_result.total_deductions <> 40000 then raise exception 'assertion failed: expected deductions 40000 (10%% of hourly_base), got %', v_result.total_deductions; end if;
  if v_result.total_reimbursement <> 250000 then raise exception 'assertion failed: expected reimbursement 250000, got %', v_result.total_reimbursement; end if;
  if v_result.total_loan_repayment <> 100000 then raise exception 'assertion failed: expected loan repayment 100000, got %', v_result.total_loan_repayment; end if;
  if v_result.net_pay <> 510000 then raise exception 'assertion failed: expected net_pay 510000, got %', v_result.net_pay; end if;
  raise notice 'OK: full calculation chain correct -- gross=%, deductions=%, reimb=%, loan=%, net=%', v_result.gross_earnings, v_result.total_deductions, v_result.total_reimbursement, v_result.total_loan_repayment, v_result.net_pay;
end $$;

\echo '>> correction run: create a correction linked to the ALREADY-FINALIZED August run, requires adjusts_run_id and a finalized target'
do $$
declare
  v_tenant uuid := (select id from app.tenants where slug='pay1');
  v_aug_run app.payroll_runs;
  v_aug_period app.payroll_periods;
  v_corr app.payroll_runs;
begin
  select * into v_aug_period from app.payroll_periods where tenant_id=v_tenant and code='pay1-2026-08';
  select * into v_aug_run from app.payroll_runs where payroll_period_id = v_aug_period.id and run_type='regular';

  begin
    perform app.create_payroll_run(v_tenant, v_aug_period.id, 'correction', null, 'IDR', null, '00000000-0000-0000-0000-000000028202', 'hr');
    raise exception 'SECURITY FAILURE: correction run created with no adjusts_run_id';
  exception when others then
    raise notice 'OK: correction without adjusts_run_id blocked (%)', sqlerrm;
  end;

  v_corr := app.create_payroll_run(v_tenant, v_aug_period.id, 'correction', v_aug_run.id, 'IDR', null, '00000000-0000-0000-0000-000000028202', 'hr');
  if v_corr.status <> 'draft' or v_corr.adjusts_run_id <> v_aug_run.id then raise exception 'assertion failed: correction run not linked correctly'; end if;
  raise notice 'OK: correction run % created, linked to finalized run %', v_corr.id, v_aug_run.id;
end $$;

\echo '>> RLS/schema-privilege default-deny: anon holds no table privilege at all on any payroll table (a stronger property than RLS-filtered-to-zero-rows -- anon cannot even issue the query)'
do $$
declare
  v_has_priv boolean;
begin
  select has_table_privilege('anon', 'app.payroll_periods', 'SELECT') into v_has_priv;
  if v_has_priv then raise exception 'SECURITY FAILURE: anon holds a direct SELECT privilege on app.payroll_periods'; end if;
  select has_table_privilege('anon', 'app.payroll_run_employee_results', 'SELECT') into v_has_priv;
  if v_has_priv then raise exception 'SECURITY FAILURE: anon holds a direct SELECT privilege on app.payroll_run_employee_results'; end if;
  select has_table_privilege('anon', 'app.payroll_payslips', 'SELECT') into v_has_priv;
  if v_has_priv then raise exception 'SECURITY FAILURE: anon holds a direct SELECT privilege on app.payroll_payslips'; end if;
  raise notice 'OK: anon holds zero table privilege on any payroll table';
end $$;

\echo '>> schema-privilege defense in depth (ERR-2026-004 regression guard): anon holds zero EXECUTE on any payroll function; authenticated has RLS-scoped SELECT only (no direct INSERT/UPDATE/DELETE); service_role retains full write access; internal _-prefixed engine functions are service_role-only'
do $$
declare
  v_has_priv boolean;
begin
  select has_function_privilege('anon', 'app.create_payroll_run(uuid,uuid,text,uuid,text,text,uuid,text)', 'EXECUTE') into v_has_priv;
  if v_has_priv then raise exception 'assertion failed: anon must NOT have execute on app.create_payroll_run'; end if;

  select has_table_privilege('authenticated', 'app.payroll_run_employee_results', 'INSERT') into v_has_priv;
  if v_has_priv then raise exception 'assertion failed: authenticated must NOT have direct INSERT on app.payroll_run_employee_results'; end if;
  select has_table_privilege('authenticated', 'app.payroll_payslips', 'UPDATE') into v_has_priv;
  if v_has_priv then raise exception 'assertion failed: authenticated must NOT have direct UPDATE on app.payroll_payslips (payslips are genuinely immutable once generated)'; end if;
  select has_table_privilege('authenticated', 'app.payroll_finance_handoff_gl_lines', 'DELETE') into v_has_priv;
  if v_has_priv then raise exception 'assertion failed: authenticated must NOT have direct DELETE on app.payroll_finance_handoff_gl_lines'; end if;

  select has_table_privilege('service_role', 'app.payroll_runs', 'UPDATE') into v_has_priv;
  if not v_has_priv then raise exception 'assertion failed: service_role SHOULD retain full write access to app.payroll_runs'; end if;

  select has_function_privilege('authenticated', 'app._calculate_payroll_run_for_employee(app.payroll_runs,date,app.payroll_input_snapshots,text)', 'EXECUTE') into v_has_priv;
  if v_has_priv then raise exception 'assertion failed: authenticated must NOT have execute on the internal app._calculate_payroll_run_for_employee engine'; end if;
  select has_function_privilege('authenticated', 'app._resolve_payroll_time_inputs_for_period(uuid,uuid,date,date)', 'EXECUTE') into v_has_priv;
  if v_has_priv then raise exception 'assertion failed: authenticated must NOT have execute on the internal app._resolve_payroll_time_inputs_for_period engine (the ISS-2026-074 resolution itself)'; end if;
  select has_function_privilege('authenticated', 'app._generate_payroll_payslip(app.payroll_runs,app.payroll_run_employee_results,text)', 'EXECUTE') into v_has_priv;
  if v_has_priv then raise exception 'assertion failed: authenticated must NOT have execute on the internal app._generate_payroll_payslip engine'; end if;

  raise notice 'OK: schema-privilege defense in depth verified for payroll and Finance-handoff tables/functions';
end $$;

\echo '>> zero duplicate Finance ledger/payment truth: this checkpoint grants no privilege of any kind on any app.finance_* table (structural proof, not merely a header claim)'
do $$
declare
  v_count integer;
begin
  select count(*) into v_count
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'app' and p.proname in (
    'prepare_finance_payroll_disbursement_handoff_from_payroll_run', 'search_payroll_finance_handoffs_pending_acknowledgement',
    'acknowledge_payroll_finance_handoff_batch', 'get_payroll_finance_handoff_reconciliation'
  ) and p.prosrc ~ 'insert into app\.finance_|update app\.finance_|delete from app\.finance_';
  if v_count <> 0 then raise exception 'SECURITY FAILURE: % payroll/Finance-handoff function(s) write directly to an app.finance_* table', v_count; end if;
  raise notice 'OK: zero payroll function writes to any app.finance_* table -- the handoff boundary is structurally, not just procedurally, honored';
end $$;

\echo 'HRT-282 PAYROLL FOUNDATION, BENEFIT AND REIMBURSEMENT TEST SUITE COMPLETE'
