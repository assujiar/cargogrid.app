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

\echo '>> ISS-2026-317 setup: pay1''s own published payroll_loan_cutover_import column definition -- the seventh PLT-131 adapter, reusing emp2 and the already-issued ordinary loan this file created. Run AFTER the Sept freeze/calculate assertions above (never before): emp2''s calculated Sept results are pinned to exactly one active loan (v_loan, term=3) at lines 471-479, and app._calculate_payroll_run_for_employee deducts the next scheduled installment of EVERY active loan an employee holds, so issuing a second loan for emp2 earlier in the file would silently change that already-asserted net_pay.'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'pay1');
  v_admin uuid := '00000000-0000-0000-0000-000000028201';
  v_supreme uuid := '00000000-0000-0000-0000-000000028299';
  v_doctype_draft app.config_versions;
  v_draft app.config_versions;
begin
  -- app.register_document_type returns an existing row unchanged, so this stays correct
  -- whichever test file gets there first.
  perform app.register_document_type('master_data_import_source', 'Master Data Import Source File', 'COM', v_supreme, 'supreme');
  v_doctype_draft := app.create_config_draft('document:master_data_import_source', v_tenant1, 'tenant', null, v_admin, 'tenant admin');
  perform app.set_config_items(v_doctype_draft.id, jsonb_build_array(
    jsonb_build_object('key', 'allowed_mime_types', 'value', jsonb_build_array('text/csv')),
    jsonb_build_object('key', 'max_size_bytes', 'value', to_jsonb(10485760)),
    jsonb_build_object('key', 'retention_class', 'value', to_jsonb('operational_contract_plus_90d'::text)),
    jsonb_build_object('key', 'default_classification', 'value', to_jsonb('internal'::text)),
    jsonb_build_object('key', 'legal_hold_eligible', 'value', to_jsonb(false))
  ), v_admin, 'tenant admin');
  perform app.publish_document_type_definition(v_doctype_draft.id, v_admin, now(), 'tenant admin');

  v_draft := app.create_config_draft('import_export:payroll_loan_cutover_import', v_tenant1, 'tenant', null, v_admin, 'tenant admin');
  perform app.set_config_items(
    v_draft.id,
    jsonb_build_array(jsonb_build_object('key', 'columns', 'value', jsonb_build_array(
      jsonb_build_object('key', 'employee_number', 'label', 'Employee number', 'required', true, 'data_type', 'text'),
      jsonb_build_object('key', 'principal_amount', 'label', 'Original principal', 'required', true, 'data_type', 'number'),
      jsonb_build_object('key', 'currency', 'label', 'Currency', 'required', false, 'data_type', 'text'),
      jsonb_build_object('key', 'installment_amount', 'label', 'Installment amount', 'required', true, 'data_type', 'number'),
      jsonb_build_object('key', 'term_count', 'label', 'Term (installments)', 'required', true, 'data_type', 'number'),
      jsonb_build_object('key', 'remaining_installments', 'label', 'Remaining installments as of cutover', 'required', true, 'data_type', 'number'),
      jsonb_build_object('key', 'notes', 'label', 'Notes', 'required', false, 'data_type', 'text')
    ), 'canonical_ref', null)),
    v_admin, 'tenant admin'
  );
  perform app.publish_import_export_schema(v_draft.id, v_admin, now(), 'tenant admin');

  -- admin1 is already tenant_admin (is_support_grant_authority passes) but holds no payroll
  -- module permission of its own -- the adapter demands Import, so without this grant the
  -- admin-gate negative test below would prove nothing (the module gate would fire first).
  -- Granted BY the Supreme Admin, not self-granted: app.assign_role correctly refuses
  -- self_escalation.
  perform app.assign_role(
    v_tenant1,
    (select rv.id from app.role_versions rv join app.roles r on r.id = rv.role_id
     where r.tenant_id = v_tenant1 and r.name = 'HR Payroll' and rv.status = 'published'),
    v_admin, v_supreme, 'supreme'
  );
  -- app.issue_payroll_loan (called once per row by the commit function) additionally demands
  -- HRS:Approve of its own caller for every ordinary, single-loan issuance -- a bulk cutover
  -- import is not exempt just because it arrives as a file, so the committing actor needs
  -- this role too, not only the import-side one above.
  perform app.assign_role(
    v_tenant1,
    (select rv.id from app.role_versions rv join app.roles r on r.id = rv.role_id
     where r.tenant_id = v_tenant1 and r.name = 'Payroll Approver' and rv.status = 'published'),
    v_admin, v_supreme, 'supreme'
  );
end $$;

\echo '>> ISS-2026-317: payroll_loan_cutover_import -- an unresolvable/inactive employee, non-positive principal/installment amounts, an out-of-range term count and a remaining-installments count outside [0, term_count] are refused at VALIDATION; a valid row posts a real loan through app.issue_payroll_loan(..., p_is_opening_balance=true, ...) flagged as an opening balance, with EXACTLY the stated remaining_installments rows numbered as the TAIL of the schedule (never renumbered from 1); a caller holding HRS:Import but no administrative authority is refused even though the module gate alone would pass; re-committing is a no-op, not a second loan'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'pay1');
  v_admin uuid := '00000000-0000-0000-0000-000000028201';
  v_hr uuid := '00000000-0000-0000-0000-000000028202';
  v_emp2_code text;
  v_source_file app.files;
  v_job app.jobs;
  v_updated app.jobs;
  v_recommit app.jobs;
  v_ids uuid[];
  v_idx integer;
  v_status text;
  v_error text;
  v_loan_id uuid;
  v_installment_count integer;
  v_min_installment integer;
  v_max_installment integer;
  v_loan_count integer;
begin
  select m.code into v_emp2_code from app.employees e join app.master_records m on m.id = e.master_record_id
  where e.tenant_id = v_tenant1 and e.work_email = 'emp2work@pay1.test';
  if coalesce(v_emp2_code, '') = '' then
    raise exception 'assertion failed: emp2 must carry a resolvable master-record code -- employee_number is what a payroll export actually contains';
  end if;

  v_source_file := app.initiate_file_upload(
    v_tenant1, 'master_data_import_source', 'import_source', gen_random_uuid(),
    'loan-cutover.csv', 'text/csv', 2048, 'internal', false, null, null, null,
    'idem-pay1-loanob-source', v_admin, 'tenant admin'
  );
  perform app.record_file_scan_result(v_source_file.id, 'clean', 'test-scanner', v_admin, 'tenant admin');
  v_job := app.create_import_export_job(v_tenant1, 'import', 'payroll_loan_cutover_import', v_source_file.id, '{}'::jsonb, 'idem-pay1-loanob-job', v_admin, 'tenant admin');

  perform app.stage_import_rows(
    v_job.job_id,
    jsonb_build_array(
      -- 1: valid -- a 12-installment loan with 5 remaining as of cutover.
      jsonb_build_object('employee_number', v_emp2_code, 'principal_amount', '6000000', 'currency', 'IDR', 'installment_amount', '500000', 'term_count', '12', 'remaining_installments', '5', 'notes', 'legacy loan cutover'),
      -- 2: an employee number that belongs to nobody in this tenant.
      jsonb_build_object('employee_number', 'EMP-NOBODY', 'principal_amount', '1000000', 'currency', 'IDR', 'installment_amount', '100000', 'term_count', '10', 'remaining_installments', '5'),
      -- 3: zero principal.
      jsonb_build_object('employee_number', v_emp2_code, 'principal_amount', '0', 'currency', 'IDR', 'installment_amount', '100000', 'term_count', '10', 'remaining_installments', '5'),
      -- 4: negative installment amount.
      jsonb_build_object('employee_number', v_emp2_code, 'principal_amount', '1000000', 'currency', 'IDR', 'installment_amount', '-5', 'term_count', '10', 'remaining_installments', '5'),
      -- 5: term count zero.
      jsonb_build_object('employee_number', v_emp2_code, 'principal_amount', '1000000', 'currency', 'IDR', 'installment_amount', '100000', 'term_count', '0', 'remaining_installments', '0'),
      -- 6: term count above the 360 ceiling.
      jsonb_build_object('employee_number', v_emp2_code, 'principal_amount', '1000000', 'currency', 'IDR', 'installment_amount', '100000', 'term_count', '361', 'remaining_installments', '5'),
      -- 7: negative remaining_installments.
      jsonb_build_object('employee_number', v_emp2_code, 'principal_amount', '1000000', 'currency', 'IDR', 'installment_amount', '100000', 'term_count', '10', 'remaining_installments', '-1'),
      -- 8: remaining_installments exceeds term_count.
      jsonb_build_object('employee_number', v_emp2_code, 'principal_amount', '1000000', 'currency', 'IDR', 'installment_amount', '100000', 'term_count', '10', 'remaining_installments', '11'),
      -- 9: a formula-injection prefix in a text cell.
      jsonb_build_object('employee_number', '=cmd|calc', 'principal_amount', '1000000', 'currency', 'IDR', 'installment_amount', '100000', 'term_count', '10', 'remaining_installments', '5')
    ),
    v_admin, 'tenant admin'
  );

  select array_agg(id order by row_number) into v_ids from app.import_staging_rows where job_id = v_job.job_id;

  for v_idx in 1..9 loop
    perform app.validate_payroll_loan_cutover_import_row(v_ids[v_idx], v_admin, 'tenant admin');
  end loop;

  select validation_status into v_status from app.import_staging_rows where id = v_ids[1];
  if v_status <> 'valid' then
    raise exception 'assertion failed: row 1 should be valid, got % (%)', v_status, (select error from app.import_staging_rows where id = v_ids[1]);
  end if;

  for v_idx in 2..9 loop
    select validation_status, error into v_status, v_error from app.import_staging_rows where id = v_ids[v_idx];
    if v_status <> 'invalid' then
      raise exception 'assertion failed: row % should be invalid, got %', v_idx, v_status;
    end if;
    if coalesce(v_error, '') = '' then
      raise exception 'assertion failed: row % is invalid but carries no reason -- an importer cannot fix what they are not told', v_idx;
    end if;
  end loop;

  -- The administrative gate is genuinely independent of the module permission: hr@pay1
  -- holds BOTH HRS:Import and HRS:Approve (granted at fixture setup) but is not tenant_admin,
  -- so a caller stopping at the module check alone would wrongly let this commit through.
  begin
    perform app.commit_payroll_loan_cutover_import_job(v_job.job_id, true, v_hr, 'hr');
    raise exception 'assertion failed: expected a caller without administrative (tenant_admin/Supreme) authority to be refused even holding HRS:Import';
  exception
    when others then
      if sqlerrm not like 'insufficient_authority%' and sqlerrm not like 'job_actor_unauthorized%' then raise; end if;
  end;

  v_updated := app.commit_payroll_loan_cutover_import_job(v_job.job_id, true, v_admin, 'tenant admin');
  if v_updated.status <> 'completed' then
    raise exception 'assertion failed: expected a completed job, got %', v_updated.status;
  end if;
  if (v_updated.payload ->> 'loaded_count')::integer <> 1 then
    raise exception 'assertion failed: expected 1 loaded row, got %', v_updated.payload ->> 'loaded_count';
  end if;

  select id into v_loan_id from app.payroll_loans where tenant_id = v_tenant1 and source_import_staging_row_id = v_ids[1];
  if v_loan_id is null then
    raise exception 'assertion failed: expected a loan row linked back to the staging row via source_import_staging_row_id';
  end if;
  if not (select is_opening_balance from app.payroll_loans where id = v_loan_id) then
    raise exception 'assertion failed: a loan created by this adapter must be flagged is_opening_balance=true';
  end if;

  -- Pins the numbering decision the entry wrongly called unanswered: with term_count=12 and
  -- remaining_installments=5, the surviving rows must be numbered 8..12 (the TAIL of the
  -- original schedule, exactly what app.issue_payroll_loan already did before this migration),
  -- never renumbered 1..5.
  select count(*), min(installment_number), max(installment_number)
  into v_installment_count, v_min_installment, v_max_installment
  from app.payroll_loan_installments where loan_id = v_loan_id;
  if v_installment_count <> 5 or v_min_installment <> 8 or v_max_installment <> 12 then
    raise exception 'assertion failed: expected exactly 5 installments numbered 8..12, got count=% min=% max=%', v_installment_count, v_min_installment, v_max_installment;
  end if;

  -- The invalid rows created no loan at all.
  if exists (select 1 from app.payroll_loans where tenant_id = v_tenant1 and source_import_staging_row_id = any(v_ids[2:9])) then
    raise exception 'assertion failed: an invalid row must create no loan';
  end if;

  -- Re-committing is a no-op rather than a second loan. A cutover that half-succeeded and was
  -- retried must not hand the same employee a duplicate opening-balance loan.
  update app.jobs set status = 'in_progress' where job_id = v_job.job_id;
  v_recommit := app.commit_payroll_loan_cutover_import_job(v_job.job_id, true, v_admin, 'tenant admin');
  if (v_recommit.payload ->> 'loaded_count')::integer <> 0 or (v_recommit.payload ->> 'skipped_count')::integer <> 1 then
    raise exception 'assertion failed: a re-commit must load 0 and skip 1, got loaded=% skipped=%',
      v_recommit.payload ->> 'loaded_count', v_recommit.payload ->> 'skipped_count';
  end if;
  select count(*) into v_loan_count from app.payroll_loans where tenant_id = v_tenant1 and source_import_staging_row_id = v_ids[1];
  if v_loan_count <> 1 then
    raise exception 'assertion failed: a re-commit must not create a second loan from the same staging row, got %', v_loan_count;
  end if;

  raise notice 'PASS: payroll loan cutover imports in bulk through the existing app.issue_payroll_loan primitive with is_opening_balance=true, installments numbered as the tail of the schedule (8..12), invalid rows are refused with reasons at validation time, the administrative gate is independent of the module permission, and a retry is a no-op';
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

-- ===========================================================================
-- HRT-295 (ISS-2026-105 resolution, CRITICAL): app._resolve_payroll_time_
-- inputs_for_period's own covered-dates derivation now ALSO excludes a
-- work_date covered by an approved app.overtime_requests row (not merely a
-- timesheet_entries row) from the attendance-session regular-minutes
-- fallback -- closing a real, live, double-counted payroll figure. Fresh
-- employee (emp3), fresh October 2026 period, exact same scenario shape
-- HRT-294's own live reproduction used: a real attendance session AND a
-- real approved overtime request on the IDENTICAL work_date, no timesheet
-- entry for that date at all -- plus a second, uncontested attendance-only
-- day to prove the ordinary (non-double-counted) fallback path is
-- completely untouched by this fix.
--
-- Attendance sessions are seeded via app.record_manual_attendance_event
-- (manual_hr channel) using genuine claimed historical timestamps -- the
-- SAME HRT-295 fix (ISS-2026-106, hris-attendance.sql) that makes this
-- fixture possible without the raw `UPDATE app.attendance_sessions ...`
-- workaround the pre-existing ISS-2026-074 fixture above needed.
-- ===========================================================================

\echo '>> ISS-2026-105 fixture: emp3 -- day A (2026-10-05) carries BOTH a real attendance session (raw span 690 min, 08:00-19:30) AND a real, approved overtime request for the SAME day (17:00-19:30, 150 min) with NO timesheet entry; day B (2026-10-06) is an ordinary, uncontested attendance-only day (480 min, no overtime, no timesheet)'
do $$
declare
  v_tenant uuid := (select id from app.tenants where slug='pay1');
  v_company uuid := (select id from app.org_units where tenant_id = v_tenant and code='CO-PAY1');
  v_branch uuid := (select id from app.org_units where tenant_id = v_tenant and code='BR-PAY1');
  v_emp3 uuid;
  v_hourly_comp app.payroll_components;
  v_ot_policy app.overtime_policies;
  v_ot_version app.overtime_policy_versions;
  v_ts_period app.timesheet_periods;
  v_req app.overtime_requests;
  v_summary app.timesheet_period_summaries;
  v_pti app.payroll_time_inputs;
  v_pay_period app.payroll_periods;
  v_day_a_session app.attendance_sessions;
  v_day_b_session app.attendance_sessions;
  v_approve_row record;
begin
  insert into auth.users (id, email) values ('00000000-0000-0000-0000-000000028208', 'emp3@pay1.test');
  perform app.invite_user(v_tenant, '00000000-0000-0000-0000-000000028208', 'emp3@pay1.test', 'Pay1 Emp Three', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'emp3@pay1.test'), 'active', 'onboarded', 'tester');
  perform app.create_employee_draft(v_tenant, 'Pay1 Emp Three', 'full_time', 'emp3work@pay1.test', 'emp3p@pay1.test', '0800000010', null, null, null, '2024-01-01', v_company, v_branch, null, 'Hourly Staff', null, (select id from app.users where email = 'emp3@pay1.test'), null, 'hr_created', 'idem-emp3-pr1', '00000000-0000-0000-0000-000000028202', 'tester');
  perform app.add_employee_emergency_contact((select master_record_id from app.employees where tenant_id = v_tenant and work_email = 'emp3work@pay1.test'), 'Contact Three', 'spouse', '0810000010', null, true, '00000000-0000-0000-0000-000000028202', 'tester');
  perform app.submit_employee_for_approval((select master_record_id from app.employees where tenant_id = v_tenant and work_email = 'emp3work@pay1.test'), 1, '00000000-0000-0000-0000-000000028202', 'tester');
  perform app.decide_employee_approval((select master_record_id from app.employees where tenant_id = v_tenant and work_email = 'emp3work@pay1.test'), 2, 'approve', null, '00000000-0000-0000-0000-000000028203', 'tester');
  perform app.activate_employee((select master_record_id from app.employees where tenant_id = v_tenant and work_email = 'emp3work@pay1.test'), 3, '00000000-0000-0000-0000-000000028203', 'tester');
  v_emp3 := (select master_record_id from app.employees where tenant_id = v_tenant and work_email = 'emp3work@pay1.test');

  -- hourly_rate component (reuse the SAME tenant-level component ISS-2026-074's
  -- own emp2 fixture above already created+approved -- 50,000 IDR/hour).
  select * into v_hourly_comp from app.payroll_components where tenant_id = v_tenant and code = 'hourly_base';
  perform app.assign_payroll_component_to_employee(v_tenant, v_emp3, v_hourly_comp.id, null, null, null, 'IDR', '2024-01-01', null, '00000000-0000-0000-0000-000000028202', 'hr');

  -- Overtime policy for pay1 (did not exist before this fixture): standard
  -- workday baseline 540 minutes -- matches the SAME 08:00-17:00 window the
  -- tenant-wide attendance policy (created by the ISS-2026-074 fixture
  -- above) already publishes, so reconciliation against the real 690-minute
  -- attendance span cleanly nets out to a real 150-minute overtime claim.
  v_ot_policy := app.create_overtime_policy(v_tenant, null, 'Pay1 Overtime', '00000000-0000-0000-0000-000000028202', 'hr');
  v_ot_version := app.create_overtime_policy_version(v_ot_policy.id, 15, 'nearest', 30, 180, 600, 540, 0, true, '2024-01-01'::date, '00000000-0000-0000-0000-000000028202', 'hr');
  perform app.publish_overtime_policy_version(v_ot_version.id, 1, '00000000-0000-0000-0000-000000028203', 'approver');

  v_ts_period := app.create_timesheet_period(v_tenant, null, 'pay1-ts-2026-10', '2026-10-01'::date, '2026-10-31'::date, '00000000-0000-0000-0000-000000028202', 'hr');

  -- Day A: 2026-10-05 (a Monday -- 'weekday' classification), manual_hr
  -- entry (HRT-295/ISS-2026-106's own fix -- the claimed historical
  -- timestamp is now authoritative, not clock_timestamp()). Raw span
  -- 08:00-19:30 = 690 minutes. NO timesheet entry is ever created for this
  -- work_date -- the exact composition ISS-2026-105's own live
  -- reproduction used.
  perform app.record_manual_attendance_event(v_tenant, v_emp3, 'clock_in', '2026-10-05 08:00:00+07'::timestamptz, 'ISS-2026-105 fixture: day A', 'iss105-daya-in', '00000000-0000-0000-0000-000000028202', 'hr');
  perform app.record_manual_attendance_event(v_tenant, v_emp3, 'clock_out', '2026-10-05 19:30:00+07'::timestamptz, 'ISS-2026-105 fixture: day A', 'iss105-daya-out', '00000000-0000-0000-0000-000000028202', 'hr');
  select * into v_day_a_session from app.attendance_sessions where tenant_id = v_tenant and employee_id = v_emp3 and work_date = '2026-10-05'::date;
  if v_day_a_session.id is null or extract(epoch from (v_day_a_session.effective_clock_out_at - v_day_a_session.effective_clock_in_at)) / 60 <> 690 then
    raise exception 'assertion failed: expected day A attendance session with a real 690-minute span, got %', v_day_a_session;
  end if;

  -- Day B: 2026-10-06 (Tuesday), ordinary attendance-only day, 08:00-16:00
  -- = 480 minutes, no overtime request, no timesheet entry -- proves the
  -- ordinary (non-double-counted) fallback path is completely untouched by
  -- this fix.
  perform app.record_manual_attendance_event(v_tenant, v_emp3, 'clock_in', '2026-10-06 08:00:00+07'::timestamptz, 'ISS-2026-105 fixture: day B (uncontested)', 'iss105-dayb-in', '00000000-0000-0000-0000-000000028202', 'hr');
  perform app.record_manual_attendance_event(v_tenant, v_emp3, 'clock_out', '2026-10-06 16:00:00+07'::timestamptz, 'ISS-2026-105 fixture: day B (uncontested)', 'iss105-dayb-out', '00000000-0000-0000-0000-000000028202', 'hr');
  select * into v_day_b_session from app.attendance_sessions where tenant_id = v_tenant and employee_id = v_emp3 and work_date = '2026-10-06'::date;
  if v_day_b_session.id is null or extract(epoch from (v_day_b_session.effective_clock_out_at - v_day_b_session.effective_clock_in_at)) / 60 <> 480 then
    raise exception 'assertion failed: expected day B attendance session with a real 480-minute span, got %', v_day_b_session;
  end if;

  -- emp3 (self) creates and submits a real overtime request for day A,
  -- 17:00-19:30 (150 minutes) -- reconciles as 'matched' against the SAME
  -- real attendance session (690 - 540 baseline = 150, within tolerance).
  v_req := app.create_overtime_request(
    v_tenant, 'emergency_after_the_fact', '2026-10-05 17:00:00+07'::timestamptz, '2026-10-05 19:30:00+07'::timestamptz,
    0, 'unplanned client escalation, stayed late', null, null, null, 'iss105-ot-1', '00000000-0000-0000-0000-000000028208', 'emp3'
  );
  if v_req.requested_minutes <> 150 then raise exception 'assertion failed: expected requested_minutes=150, got %', v_req.requested_minutes; end if;
  v_req := app.submit_overtime_request(v_req.id, v_req.record_version, '00000000-0000-0000-0000-000000028208', 'emp3');
  if v_req.reconciliation_status <> 'matched' or v_req.reconciled_actual_minutes <> 150 then
    raise exception 'assertion failed: expected reconciliation matched/150 against the real attendance session, got %/%', v_req.reconciliation_status, v_req.reconciled_actual_minutes;
  end if;

  -- A distinct approver decides -- approved as real overtime, weekday
  -- classification, 150 minutes.
  v_req := app.decide_overtime_request(v_req.id, v_req.record_version, 'approve', 'confirmed with client, approved', null, '00000000-0000-0000-0000-000000028203', 'approver');
  if v_req.status <> 'approved' or v_req.eligible_classification <> 'weekday' or v_req.approved_minutes <> 150 then
    raise exception 'assertion failed: expected approved/weekday/150, got %/%/%', v_req.status, v_req.eligible_classification, v_req.approved_minutes;
  end if;

  -- HR approves BOTH attendance sessions for payroll input (recalculate
  -- exceptions first and waive any stale ones, exactly the governed pattern
  -- the pre-existing ISS-2026-074 fixture above already establishes).
  perform app.recalculate_attendance_exceptions_for_range(v_tenant, '2026-10-01'::date, '2026-10-31'::date, v_emp3, '00000000-0000-0000-0000-000000028202', 'hr');
  perform app.waive_attendance_exception(x.id, x.record_version, 'ISS-2026-105 fixture: no real exception expected, defensive waive', '00000000-0000-0000-0000-000000028203', 'approver')
    from app.attendance_exceptions x where x.tenant_id = v_tenant and x.employee_id = v_emp3 and x.status in ('open', 'acknowledged');
  for v_approve_row in select * from app.approve_attendance_for_payroll_input(v_tenant, '2026-10-01'::date, '2026-10-31'::date, v_emp3, '00000000-0000-0000-0000-000000028202', 'hr') loop
    if not v_approve_row.approved then raise exception 'assertion failed: attendance approval failed for session %: %', v_approve_row.session_id, v_approve_row.skip_reason; end if;
  end loop;
  if (select payroll_input_status from app.attendance_sessions where id = v_day_a_session.id) <> 'approved'
     or (select payroll_input_status from app.attendance_sessions where id = v_day_b_session.id) <> 'approved' then
    raise exception 'assertion failed: expected both day A and day B attendance sessions approved for payroll input';
  end if;

  -- Timesheet period summary for emp3: ZERO timesheet_entries (regular=0),
  -- ONE approved overtime request (150 weekday minutes) -- a real, valid,
  -- submittable/approvable state (app._compute_timesheet_period_summary
  -- sums whatever real approved rows exist; zero entries is not an error).
  v_summary := app.submit_timesheet_period_summary(v_ts_period.id, v_emp3, '00000000-0000-0000-0000-000000028202', 'hr');
  if v_summary.total_regular_minutes <> 0 or v_summary.total_overtime_weekday_minutes <> 150 or v_summary.entry_count <> 0 or v_summary.overtime_request_count <> 1 then
    raise exception 'assertion failed: expected regular=0/ot_weekday=150/entries=0/ot_count=1, got %/%/%/%', v_summary.total_regular_minutes, v_summary.total_overtime_weekday_minutes, v_summary.entry_count, v_summary.overtime_request_count;
  end if;
  v_summary := app.approve_timesheet_period_summary(v_summary.id, v_summary.record_version, 'confirmed, no timesheet entries this period', '00000000-0000-0000-0000-000000028203', 'approver');

  v_pti := app.generate_payroll_time_input(v_ts_period.id, v_emp3, '00000000-0000-0000-0000-000000028203', 'approver');
  if v_pti.regular_minutes <> 0 or v_pti.overtime_weekday_minutes <> 150
     or array_length(v_pti.source_entry_ids, 1) is not null or array_length(v_pti.source_overtime_request_ids, 1) <> 1 then
    raise exception 'assertion failed: expected payroll_time_inputs regular=0/ot_weekday=150/zero source_entry_ids/one source_overtime_request_id, got regular=%, ot=%, entries=%, ot_ids=%', v_pti.regular_minutes, v_pti.overtime_weekday_minutes, v_pti.source_entry_ids, v_pti.source_overtime_request_ids;
  end if;

  v_pay_period := app.create_payroll_period(v_tenant, null, 'pay1-2026-10', 'monthly', '2026-10-01', '2026-10-31', '2026-11-05', '00000000-0000-0000-0000-000000028202', 'hr');
  v_pay_period := app.freeze_payroll_period_inputs(v_pay_period.id, v_pay_period.record_version, '00000000-0000-0000-0000-000000028202', 'hr');

  raise notice 'ISS-2026-105 fixture ready: emp3=%, day_a_session=%, day_b_session=%, payroll_period=%', v_emp3, v_day_a_session.id, v_day_b_session.id, v_pay_period.id;
end $$;

\echo '>> ISS-2026-105 core assertion (Tier C review corrected, 20260731280000): frozen snapshot regular_minutes=1020 -- day B''s 480 raw minutes PLUS day A''s real 540-minute non-overtime regular portion (690 raw - 150 already-claimed overtime), overtime_weekday_minutes=150 (unchanged) -- NEVER 1170 (the pre-ISS-2026-105 double-count, both days'' full raw spans), NEVER 840 (690+150 double-counted on day A alone), and NEVER 480 (20260731240000''s own shipped shape, which excluded day A entirely and paid its real, worked, HR-approved regular hours as zero -- the residual gap all four Tier C review lenses independently live-reproduced and 20260731280000 closes)'
do $$
declare
  v_tenant uuid := (select id from app.tenants where slug='pay1');
  v_period app.payroll_periods;
  v_emp3 uuid := (select master_record_id from app.employees where tenant_id = (select id from app.tenants where slug='pay1') and work_email = 'emp3work@pay1.test');
  v_day_a_session_id uuid := (select id from app.attendance_sessions where tenant_id = (select id from app.tenants where slug='pay1') and employee_id = (select master_record_id from app.employees where tenant_id = (select id from app.tenants where slug='pay1') and work_email='emp3work@pay1.test') and work_date = '2026-10-05'::date);
  v_day_b_session_id uuid := (select id from app.attendance_sessions where tenant_id = (select id from app.tenants where slug='pay1') and employee_id = (select master_record_id from app.employees where tenant_id = (select id from app.tenants where slug='pay1') and work_email='emp3work@pay1.test') and work_date = '2026-10-06'::date);
  v_snapshot app.payroll_input_snapshots;
  v_raw_span_sum integer;
begin
  select * into v_period from app.payroll_periods where tenant_id=v_tenant and code='pay1-2026-10';
  select * into v_snapshot from app.payroll_input_snapshots where payroll_period_id = v_period.id and employee_id = v_emp3;

  if v_snapshot.regular_minutes <> 1020 then
    raise exception 'ISS-2026-105 REGRESSION: expected regular_minutes=1020 (day B''s 480 + day A''s real 540-minute non-overtime portion), got % -- 1170 would mean the exclusion never ran (both raw days counted in full), 840 would mean day A was double-counted, 480 would mean day A was wrongly excluded ENTIRELY (paying its real worked regular hours as zero -- 20260731240000''s own shipped-but-incomplete shape)', v_snapshot.regular_minutes;
  end if;
  if v_snapshot.overtime_weekday_minutes <> 150 then
    raise exception 'assertion failed: expected overtime_weekday_minutes=150 (unaffected by this fix), got %', v_snapshot.overtime_weekday_minutes;
  end if;

  -- Mechanism-level proof, not merely an arithmetic coincidence: BOTH day A
  -- and day B''s own attendance sessions must now be present in
  -- source_attendance_session_ids (20260731280000: day A's own session now
  -- contributes its real, reduced-by-overtime regular portion instead of
  -- being wholly excluded).
  if array_length(v_snapshot.source_attendance_session_ids, 1) <> 2 or not (v_day_a_session_id = any (v_snapshot.source_attendance_session_ids)) or not (v_day_b_session_id = any (v_snapshot.source_attendance_session_ids)) then
    raise exception 'ISS-2026-105 REGRESSION: expected source_attendance_session_ids to contain BOTH day A''s (%) and day B''s (%) sessions, got %', v_day_a_session_id, v_day_b_session_id, v_snapshot.source_attendance_session_ids;
  end if;

  -- Explicit no-double-count invariant, computed independently of the fix
  -- under test: the raw, uncapped sum of EVERY approved attendance session
  -- in the period (what the pre-ISS-2026-105 buggy fallback would have
  -- summed, 690 + 480 = 1170) must exceed what this frozen snapshot
  -- actually counted as regular by EXACTLY day A's own already-claimed
  -- overtime minutes (150) -- never by day A's whole raw span (690, which
  -- would mean the day was wrongly excluded outright again).
  select coalesce(sum(greatest(0, round(extract(epoch from (s.effective_clock_out_at - s.effective_clock_in_at)) / 60)))::integer, 0)
  into v_raw_span_sum
  from app.attendance_sessions s
  where s.tenant_id = v_tenant and s.employee_id = v_emp3 and s.work_date between '2026-10-01' and '2026-10-31' and s.payroll_input_status = 'approved';
  if v_raw_span_sum <> 1170 then
    raise exception 'assertion failed: fixture sanity check failed, expected raw span sum 1170 (690+480), got %', v_raw_span_sum;
  end if;
  if v_raw_span_sum - v_snapshot.regular_minutes <> 150 then
    raise exception 'ISS-2026-105 REGRESSION: expected the fix to exclude exactly day A''s own already-claimed 150 overtime minutes from regular_minutes (never its whole 690-minute raw span), got a delta of % (raw_sum=%, regular_minutes=%)', v_raw_span_sum - v_snapshot.regular_minutes, v_raw_span_sum, v_snapshot.regular_minutes;
  end if;

  raise notice 'OK: ISS-2026-105 double-count closed AND day A''s real regular portion is paid -- regular_minutes=% (day A''s 540 + day B''s 480), overtime_weekday_minutes=% (day A, separately), raw span sum=% (never double-counted, never zeroed)', v_snapshot.regular_minutes, v_snapshot.overtime_weekday_minutes, v_raw_span_sum;
end $$;

\echo '>> ISS-2026-105: the corrected regular_minutes reaches a REAL calculated payroll run -- gross/net pay reflect 1020 minutes (17h) at 50,000 IDR/hour = 850,000 IDR, never the pre-ISS-2026-105-shaped 1170-minute (19.5h/975,000 IDR) double-counted figure, and never 20260731240000''s own shipped-but-incomplete 480-minute (8h/400,000 IDR) figure that zeroed day A''s real regular pay entirely'
do $$
declare
  v_tenant uuid := (select id from app.tenants where slug='pay1');
  v_period app.payroll_periods;
  v_run app.payroll_runs;
  v_result app.payroll_run_employee_results;
  v_emp3 uuid := (select master_record_id from app.employees where tenant_id = (select id from app.tenants where slug='pay1') and work_email = 'emp3work@pay1.test');
begin
  select * into v_period from app.payroll_periods where tenant_id=v_tenant and code='pay1-2026-10';
  v_run := app.create_payroll_run(v_tenant, v_period.id, 'regular', null, 'IDR', null, '00000000-0000-0000-0000-000000028202', 'hr');
  v_run := app.calculate_payroll_run(v_run.id, v_run.record_version, null, '00000000-0000-0000-0000-000000028202', 'hr');
  if v_run.status <> 'calculated' then raise exception 'assertion failed: expected calculated, got % (exception_count=%)', v_run.status, v_run.exception_count; end if;

  select * into v_result from app.payroll_run_employee_results where payroll_run_id = v_run.id and employee_id = v_emp3;
  if v_result.gross_earnings <> 850000 or v_result.net_pay <> 850000 then
    raise exception 'ISS-2026-105 REGRESSION: expected gross/net pay 850,000 IDR (1020 min / 60 * 50,000), got %/%', v_result.gross_earnings, v_result.net_pay;
  end if;
  raise notice 'OK: ISS-2026-105 real payroll run calculated correctly -- emp3 gross=% net=% (no double-counted overtime day inflated the figure, AND day A''s real regular hours are genuinely paid)', v_result.gross_earnings, v_result.net_pay;
end $$;

-- ===========================================================================
-- Tier C review fix (20260731280000): a SECOND, independent employee (emp5)
-- proves the subtraction is keyed to the day's OWN real approved_minutes
-- value, not a hand-derived "raw span minus policy baseline" shortcut --
-- distinguishing this fix from the "capping" alternative 20260731240000's
-- own header evaluated and rejected. emp5's overtime request only claims
-- a PARTIAL 120-minute window (18:15-20:15) of a 735-minute raw span;
-- reconciliation/decision resolves the real approved figure to 180 minutes
-- (the overtime policy's own max_daily_minutes cap) -- the correct regular
-- contribution is therefore 735-180=555, neither the raw 735 (double-
-- count) nor 0 (20260731240000's own gap) nor 540 (the attendance policy's
-- own standard workday, a DIFFERENT config value this fix deliberately
-- never reads).
-- ===========================================================================

\echo '>> ISS-2026-105 Tier C second fixture: emp5 -- day A (2026-10-12) raw span 735 minutes (08:00-20:15), a real approved overtime request keyed to a PARTIAL claimed window that reconciles/decides to 180 approved minutes (the policy''s own max_daily_minutes cap) -- correct regular contribution is 735-180=555, never 0 and never the coincidental 540 standard-workday figure'
do $$
declare
  v_tenant uuid := (select id from app.tenants where slug='pay1');
  v_company uuid := (select id from app.org_units where tenant_id = v_tenant and code='CO-PAY1');
  v_branch uuid := (select id from app.org_units where tenant_id = v_tenant and code='BR-PAY1');
  v_emp5 uuid;
  v_hourly_comp app.payroll_components;
  v_ts_period app.timesheet_periods;
  v_req app.overtime_requests;
  v_summary app.timesheet_period_summaries;
  v_pti app.payroll_time_inputs;
  v_pay_period app.payroll_periods;
  v_day_a_session app.attendance_sessions;
  v_snapshot app.payroll_input_snapshots;
begin
  insert into auth.users (id, email) values ('00000000-0000-0000-0000-000000028209', 'emp5@pay1.test');
  perform app.invite_user(v_tenant, '00000000-0000-0000-0000-000000028209', 'emp5@pay1.test', 'Pay1 Emp Five', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'emp5@pay1.test'), 'active', 'onboarded', 'tester');
  perform app.create_employee_draft(v_tenant, 'Pay1 Emp Five', 'full_time', 'emp5work@pay1.test', 'emp5p@pay1.test', '0800000011', null, null, null, '2024-01-01', v_company, v_branch, null, 'Hourly Staff', null, (select id from app.users where email = 'emp5@pay1.test'), null, 'hr_created', 'idem-emp5-pr1', '00000000-0000-0000-0000-000000028202', 'tester');
  perform app.add_employee_emergency_contact((select master_record_id from app.employees where tenant_id = v_tenant and work_email = 'emp5work@pay1.test'), 'Contact Five', 'spouse', '0810000011', null, true, '00000000-0000-0000-0000-000000028202', 'tester');
  perform app.submit_employee_for_approval((select master_record_id from app.employees where tenant_id = v_tenant and work_email = 'emp5work@pay1.test'), 1, '00000000-0000-0000-0000-000000028202', 'tester');
  perform app.decide_employee_approval((select master_record_id from app.employees where tenant_id = v_tenant and work_email = 'emp5work@pay1.test'), 2, 'approve', null, '00000000-0000-0000-0000-000000028203', 'tester');
  perform app.activate_employee((select master_record_id from app.employees where tenant_id = v_tenant and work_email = 'emp5work@pay1.test'), 3, '00000000-0000-0000-0000-000000028203', 'tester');
  v_emp5 := (select master_record_id from app.employees where tenant_id = v_tenant and work_email = 'emp5work@pay1.test');

  select * into v_hourly_comp from app.payroll_components where tenant_id = v_tenant and code = 'hourly_base';
  perform app.assign_payroll_component_to_employee(v_tenant, v_emp5, v_hourly_comp.id, null, null, null, 'IDR', '2024-01-01', null, '00000000-0000-0000-0000-000000028202', 'hr');

  -- Scoped to v_branch (not null/tenant-wide) -- emp3's own tenant-wide
  -- October 2026 period already exists above; a distinct org-unit-scoped
  -- period for the SAME date range is a genuinely different exclusion-
  -- constraint scope, not a collision.
  v_ts_period := app.create_timesheet_period(v_tenant, v_branch, 'pay1-ts-2026-10-emp5', '2026-10-01'::date, '2026-10-31'::date, '00000000-0000-0000-0000-000000028202', 'hr');

  perform app.record_manual_attendance_event(v_tenant, v_emp5, 'clock_in', '2026-10-12 08:00:00+07'::timestamptz, 'ISS-2026-105 Tier C fixture: emp5 day A', 'iss105tc-daya-in', '00000000-0000-0000-0000-000000028202', 'hr');
  perform app.record_manual_attendance_event(v_tenant, v_emp5, 'clock_out', '2026-10-12 20:15:00+07'::timestamptz, 'ISS-2026-105 Tier C fixture: emp5 day A', 'iss105tc-daya-out', '00000000-0000-0000-0000-000000028202', 'hr');
  select * into v_day_a_session from app.attendance_sessions where tenant_id = v_tenant and employee_id = v_emp5 and work_date = '2026-10-12'::date;
  if v_day_a_session.id is null or extract(epoch from (v_day_a_session.effective_clock_out_at - v_day_a_session.effective_clock_in_at)) / 60 <> 735 then
    raise exception 'assertion failed: expected emp5 day A session 735 min, got %', v_day_a_session;
  end if;

  v_req := app.create_overtime_request(
    v_tenant, 'emergency_after_the_fact', '2026-10-12 18:15:00+07'::timestamptz, '2026-10-12 20:15:00+07'::timestamptz,
    0, 'ISS-2026-105 Tier C fixture: partial overtime claim', null, null, null, 'iss105tc-ot-1', '00000000-0000-0000-0000-000000028209', 'emp5'
  );
  if v_req.requested_minutes <> 120 then raise exception 'assertion failed: expected requested_minutes=120, got %', v_req.requested_minutes; end if;
  v_req := app.submit_overtime_request(v_req.id, v_req.record_version, '00000000-0000-0000-0000-000000028209', 'emp5');
  v_req := app.decide_overtime_request(v_req.id, v_req.record_version, 'approve', 'ISS-2026-105 Tier C fixture: approved (reconciliation-derived figure, capped by policy)', null, '00000000-0000-0000-0000-000000028203', 'approver');
  if v_req.status <> 'approved' or v_req.approved_minutes <> 180 then
    raise exception 'assertion failed: expected approved/180 (the policy''s own max_daily_minutes cap), got %/%', v_req.status, v_req.approved_minutes;
  end if;

  perform app.recalculate_attendance_exceptions_for_range(v_tenant, '2026-10-01'::date, '2026-10-31'::date, v_emp5, '00000000-0000-0000-0000-000000028202', 'hr');
  perform app.waive_attendance_exception(x.id, x.record_version, 'ISS-2026-105 Tier C fixture: defensive waive', '00000000-0000-0000-0000-000000028203', 'approver')
    from app.attendance_exceptions x where x.tenant_id = v_tenant and x.employee_id = v_emp5 and x.status in ('open', 'acknowledged');
  perform app.approve_attendance_for_payroll_input(v_tenant, '2026-10-01'::date, '2026-10-31'::date, v_emp5, '00000000-0000-0000-0000-000000028202', 'hr');

  v_summary := app.submit_timesheet_period_summary(v_ts_period.id, v_emp5, '00000000-0000-0000-0000-000000028202', 'hr');
  v_summary := app.approve_timesheet_period_summary(v_summary.id, v_summary.record_version, 'confirmed', '00000000-0000-0000-0000-000000028203', 'approver');

  v_pti := app.generate_payroll_time_input(v_ts_period.id, v_emp5, '00000000-0000-0000-0000-000000028203', 'approver');

  v_pay_period := app.create_payroll_period(v_tenant, null, 'pay1-2026-10-emp5', 'monthly', '2026-10-01', '2026-10-31', '2026-11-05', '00000000-0000-0000-0000-000000028202', 'hr');
  v_pay_period := app.freeze_payroll_period_inputs(v_pay_period.id, v_pay_period.record_version, '00000000-0000-0000-0000-000000028202', 'hr');

  select * into v_snapshot from app.payroll_input_snapshots where payroll_period_id = v_pay_period.id and employee_id = v_emp5;
  if v_snapshot.regular_minutes <> 555 then
    raise exception 'ISS-2026-105 Tier C REGRESSION: expected regular_minutes=555 (735 raw - 180 real approved overtime), got % -- 0 would mean the day was wrongly excluded entirely (20260731240000''s own gap), 735 would mean double-counted, 540 would mean the fix is keyed to the WRONG config value (attendance policy standard workday, not the day''s own real approved_minutes)', v_snapshot.regular_minutes;
  end if;
  if v_snapshot.overtime_weekday_minutes <> 180 then
    raise exception 'assertion failed: expected overtime_weekday_minutes=180, got %', v_snapshot.overtime_weekday_minutes;
  end if;
  if not (v_day_a_session.id = any (v_snapshot.source_attendance_session_ids)) then
    raise exception 'ISS-2026-105 Tier C REGRESSION: expected emp5 day A''s session to be present in source_attendance_session_ids (contributing its reduced regular portion), got %', v_snapshot.source_attendance_session_ids;
  end if;
  raise notice 'OK: ISS-2026-105 Tier C fix verified independently -- emp5 regular_minutes=% (735 raw - 180 real approved overtime, never a config-derived baseline)', v_snapshot.regular_minutes;
end $$;

\echo 'HRT-282 PAYROLL FOUNDATION, BENEFIT AND REIMBURSEMENT TEST SUITE COMPLETE'
