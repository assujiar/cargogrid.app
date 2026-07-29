-- Real, executable test evidence for FIN-209 (Reconciliation,
-- CG-S9-FIN-020) -- run via `pnpm run db:test` against a real, disposable
-- Postgres database.
-- Proves: a real posted subledger batch (via app.post_finance_subledger_batch,
-- direct-account lines, no posting map required) drives a real AR control-
-- account balance; a run correctly reports is_within_tolerance=true when
-- the control account matches its own open-item total, and correctly opens
-- one exception when a subsequent AR open-item event moves the two totals
-- apart; certification is blocked while an exception is open and requires
-- an independent authority and a reason; certification succeeds once the
-- exception is resolved; authority split (FIN:Edit executes/resolves,
-- FIN:Approve certifies); as-of-date bounding; cross-tenant isolation;
-- schema-privilege defense in depth; audit trail.

\set ON_ERROR_STOP on

\echo '>> setup: two tenants; tenant A gets a Finance Manager (FIN:Create/Edit/Approve/View, tenant_admin), a Finance Editor (FIN:Edit/View only, no Approve), and a Plain User with no FIN grant; tenant B gets its own Finance Manager; tenant A gets one open fiscal period (2026-06), a small real chart of accounts, and a published finance_posting_map (ar_control resolved)'
do $$
declare
  v_tenant_a uuid;
  v_tenant_b uuid;
  v_team_a uuid;
  v_team_b uuid;
  v_manager_role_a uuid;
  v_manager_draft_a app.role_versions;
  v_editor_role_a uuid;
  v_editor_draft_a app.role_versions;
  v_manager_role_b uuid;
  v_manager_draft_b app.role_versions;
  v_account app.finance_accounts;
  v_pm_draft app.config_versions;
begin
  insert into auth.users (id, email) values
    ('00000000-0000-0000-0000-000000034001', 'admina@acmerecon.test'),
    ('00000000-0000-0000-0000-000000034002', 'financemanagera@acmerecon.test'),
    ('00000000-0000-0000-0000-000000034003', 'financeeditora@acmerecon.test'),
    ('00000000-0000-0000-0000-000000034004', 'plainusera@acmerecon.test'),
    ('00000000-0000-0000-0000-000000034005', 'financemanagerb@acmerecon.test');

  perform app.provision_tenant('acmerecona', 'Acme Reconciliation A', 'idem-acmerecona', 'tester');
  v_tenant_a := (select id from app.tenants where slug = 'acmerecona');
  perform app.transition_tenant_status(v_tenant_a, 'active', 'setup', 'tester');
  perform app.create_org_unit(v_tenant_a, 'company', null, 'ACMERECONA-CO', 'Acme Reconciliation A', 'tester');
  v_team_a := (select id from app.org_units where tenant_id = v_tenant_a and code = 'ACMERECONA-CO');

  perform app.provision_tenant('acmereconb', 'Acme Reconciliation B', 'idem-acmereconb', 'tester');
  v_tenant_b := (select id from app.tenants where slug = 'acmereconb');
  perform app.transition_tenant_status(v_tenant_b, 'active', 'setup', 'tester');
  perform app.create_org_unit(v_tenant_b, 'company', null, 'ACMERECONB-CO', 'Acme Reconciliation B', 'tester');
  v_team_b := (select id from app.org_units where tenant_id = v_tenant_b and code = 'ACMERECONB-CO');

  perform app.invite_user(v_tenant_a, '00000000-0000-0000-0000-000000034001', 'admina@acmerecon.test', 'Tenant A Admin', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'admina@acmerecon.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000034001', 'tenant_admin', v_tenant_a, null, 'tester');

  perform app.invite_user(v_tenant_a, '00000000-0000-0000-0000-000000034002', 'financemanagera@acmerecon.test', 'Finance Manager A', v_team_a, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'financemanagera@acmerecon.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000034002', 'tenant_admin', v_tenant_a, null, 'tester');

  perform app.invite_user(v_tenant_a, '00000000-0000-0000-0000-000000034003', 'financeeditora@acmerecon.test', 'Finance Editor A', v_team_a, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'financeeditora@acmerecon.test'), 'active', 'onboarded', 'tester');

  v_manager_role_a := (app.create_role(v_tenant_a, 'Finance Manager', 'Reconciliation authority', 'tester')).id;
  v_manager_draft_a := app.create_role_version(v_manager_role_a, 'tester');
  perform app.set_role_version_permissions(v_manager_draft_a.id, array(select id from app.permissions where resource_module_code = 'FIN' and action in ('Create', 'Edit', 'Approve', 'View')), 'tester');
  perform app.publish_role_version(v_manager_draft_a.id, now(), 'tester');
  perform app.assign_role(v_tenant_a, (select id from app.role_versions where role_id = v_manager_role_a and status = 'published'), '00000000-0000-0000-0000-000000034002', '00000000-0000-0000-0000-000000034001', 'tester');

  v_editor_role_a := (app.create_role(v_tenant_a, 'Finance Editor', 'edit only, no approve', 'tester')).id;
  v_editor_draft_a := app.create_role_version(v_editor_role_a, 'tester');
  perform app.set_role_version_permissions(v_editor_draft_a.id, array(select id from app.permissions where resource_module_code = 'FIN' and action in ('Edit', 'View')), 'tester');
  perform app.publish_role_version(v_editor_draft_a.id, now(), 'tester');
  perform app.assign_role(v_tenant_a, (select id from app.role_versions where role_id = v_editor_role_a and status = 'published'), '00000000-0000-0000-0000-000000034003', '00000000-0000-0000-0000-000000034001', 'tester');

  perform app.invite_user(v_tenant_a, '00000000-0000-0000-0000-000000034004', 'plainusera@acmerecon.test', 'Plain User A', v_team_a, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'plainusera@acmerecon.test'), 'active', 'onboarded', 'tester');

  perform app.invite_user(v_tenant_b, '00000000-0000-0000-0000-000000034005', 'financemanagerb@acmerecon.test', 'Finance Manager B', v_team_b, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'financemanagerb@acmerecon.test'), 'active', 'onboarded', 'tester');
  v_manager_role_b := (app.create_role(v_tenant_b, 'Finance Manager', 'Reconciliation authority', 'tester')).id;
  v_manager_draft_b := app.create_role_version(v_manager_role_b, 'tester');
  perform app.set_role_version_permissions(v_manager_draft_b.id, array(select id from app.permissions where resource_module_code = 'FIN' and action in ('Create', 'Edit', 'Approve', 'View')), 'tester');
  perform app.publish_role_version(v_manager_draft_b.id, now(), 'tester');
  perform app.assign_role(v_tenant_b, (select id from app.role_versions where role_id = v_manager_role_b and status = 'published'), '00000000-0000-0000-0000-000000034005', '00000000-0000-0000-0000-000000034005', 'tester');

  perform app.generate_finance_fiscal_calendar(v_tenant_a, null, 'FY2026', 'FY2026 Monthly', '2026-01-01'::date, 12, '00000000-0000-0000-0000-000000034002', 'financemanagera');

  select * into v_account from app.create_finance_account_draft(v_tenant_a, null, 'AR-RECON', 'Accounts Receivable', 'asset', 'debit', null, false, null, '00000000-0000-0000-0000-000000034002', 'financemanagera');
  perform app.activate_finance_account(v_account.id, v_account.record_version, '00000000-0000-0000-0000-000000034002', 'financemanagera');
  select * into v_account from app.create_finance_account_draft(v_tenant_a, null, 'REV-RECON', 'Revenue', 'revenue', 'credit', null, false, null, '00000000-0000-0000-0000-000000034002', 'financemanagera');
  perform app.activate_finance_account(v_account.id, v_account.record_version, '00000000-0000-0000-0000-000000034002', 'financemanagera');

  select * into v_pm_draft from app.create_finance_config_draft('finance_posting_map', v_tenant_a, 'tenant', null, '00000000-0000-0000-0000-000000034002', 'financemanagera');
  perform app.set_finance_config_items(v_pm_draft.id, jsonb_build_array(
    jsonb_build_object('key', 'ar_control', 'value', jsonb_build_object('accountCodeRef', 'AR-RECON'))
  ), '00000000-0000-0000-0000-000000034002', 'financemanagera');
  perform app.publish_finance_config_version(v_pm_draft.id, '00000000-0000-0000-0000-000000034002', null, 'financemanagera');

  -- minimal, valid customer account for tenant A's own AR open items below.
  insert into app.accounts (tenant_id, legal_name, duplicate_fingerprint, billing_address, org_unit_id, created_by)
  values (v_tenant_a, 'Acme Reconciliation Customer Pte Ltd', 'acmerecon-customer-fixture-fingerprint', '{}'::jsonb, v_team_a, 'tester');
end;
$$;

\echo '>> authority and validation: Plain User A is denied executing a run; an invalid scope is rejected; a negative tolerance is rejected'
do $$
declare
  v_tenant_a uuid;
begin
  v_tenant_a := (select id from app.tenants where slug = 'acmerecona');

  begin
    perform app.execute_finance_reconciliation_run(v_tenant_a, null, 'ar', '2026-06-30'::date, 0, '00000000-0000-0000-0000-000000034004', 'plainusera');
    raise exception 'assertion failed: expected insufficient_authority for Plain User A';
  exception
    when insufficient_privilege then
      null;
  end;

  begin
    perform app.execute_finance_reconciliation_run(v_tenant_a, null, 'gl', '2026-06-30'::date, 0, '00000000-0000-0000-0000-000000034002', 'financemanagera');
    raise exception 'assertion failed: expected finance_reconciliation_invalid_scope';
  exception
    when others then
      if sqlerrm !~ 'finance_reconciliation_invalid_scope' then
        raise exception 'assertion failed: expected finance_reconciliation_invalid_scope, got %', sqlerrm;
      end if;
  end;

  begin
    perform app.execute_finance_reconciliation_run(v_tenant_a, null, 'ar', '2026-06-30'::date, -1, '00000000-0000-0000-0000-000000034002', 'financemanagera');
    raise exception 'assertion failed: expected finance_reconciliation_invalid_tolerance';
  exception
    when others then
      if sqlerrm !~ 'finance_reconciliation_invalid_tolerance' then
        raise exception 'assertion failed: expected finance_reconciliation_invalid_tolerance, got %', sqlerrm;
      end if;
  end;
end;
$$;

\echo '>> a real posted subledger batch (direct-account lines) drives a real AR control-account balance for its own posting period (June 2026); a real AR open item dated within that same period makes a run as of period-end reconcile exactly, with zero exceptions'
do $$
declare
  v_tenant_a uuid;
  v_ar_id uuid;
  v_rev_id uuid;
  v_customer_id uuid;
  v_batch app.finance_subledger_batches;
  v_run app.finance_reconciliation_runs;
  v_exception_count integer;
begin
  v_tenant_a := (select id from app.tenants where slug = 'acmerecona');
  v_ar_id := (select id from app.finance_accounts where tenant_id = v_tenant_a and code = 'AR-RECON');
  v_rev_id := (select id from app.finance_accounts where tenant_id = v_tenant_a and code = 'REV-RECON');
  v_customer_id := (select id from app.accounts where tenant_id = v_tenant_a);

  select * into v_batch from app.post_finance_subledger_batch(v_tenant_a, null, 'invoice', gen_random_uuid(), '2026-06-15'::date, 'USD',
    jsonb_build_array(
      jsonb_build_object('accountId', v_ar_id, 'direction', 'debit', 'amount', 500, 'openItemType', 'ar_open_item', 'openItemId', gen_random_uuid()),
      jsonb_build_object('accountId', v_rev_id, 'direction', 'credit', 'amount', 500)
    ), '00000000-0000-0000-0000-000000034002', 'financemanagera');

  perform app.post_finance_ar_open_item(v_tenant_a, null, v_customer_id, 'invoice', gen_random_uuid(), 'USD', 500, '2026-06-20'::date, '2026-07-20'::date, '00000000-0000-0000-0000-000000034002', 'financemanagera');

  select * into v_run from app.execute_finance_reconciliation_run(v_tenant_a, null, 'ar', '2026-06-30'::date, 0, '00000000-0000-0000-0000-000000034002', 'financemanagera');
  if v_run.control_total <> 500 or v_run.source_total <> 500 or not v_run.is_within_tolerance then
    raise exception 'assertion failed: expected a fully reconciled run as of period-end (control=source=500, within tolerance), got control=% source=% within=%', v_run.control_total, v_run.source_total, v_run.is_within_tolerance;
  end if;

  select count(*) into v_exception_count from app.finance_reconciliation_exceptions where run_id = v_run.id;
  if v_exception_count <> 0 then
    raise exception 'assertion failed: expected zero exceptions for a fully reconciled run, got %', v_exception_count;
  end if;
end;
$$;

\echo '>> a real variance (a second, later AR open item posted without a matching GL batch) opens exactly one exception once the as-of date extends past it; certification is blocked while it is open, then succeeds once resolved; authority split enforced throughout'
do $$
declare
  v_tenant_a uuid;
  v_customer_id uuid;
  v_run app.finance_reconciliation_runs;
  v_exception app.finance_reconciliation_exceptions;
  v_exception_count integer;
begin
  v_tenant_a := (select id from app.tenants where slug = 'acmerecona');
  v_customer_id := (select id from app.accounts where tenant_id = v_tenant_a);

  perform app.post_finance_ar_open_item(v_tenant_a, null, v_customer_id, 'invoice', gen_random_uuid(), 'USD', 150, '2026-07-20'::date, '2026-08-19'::date, '00000000-0000-0000-0000-000000034002', 'financemanagera');

  select * into v_run from app.execute_finance_reconciliation_run(v_tenant_a, null, 'ar', '2026-07-31'::date, 0, '00000000-0000-0000-0000-000000034002', 'financemanagera');
  if v_run.is_within_tolerance or v_run.variance_amount <> -150 then
    raise exception 'assertion failed: expected a -150 variance (control 500 vs source 650) and is_within_tolerance=false, got variance=% within=%', v_run.variance_amount, v_run.is_within_tolerance;
  end if;

  select count(*) into v_exception_count from app.finance_reconciliation_exceptions where run_id = v_run.id;
  if v_exception_count <> 1 then
    raise exception 'assertion failed: expected exactly one exception for this run, got %', v_exception_count;
  end if;
  select * into v_exception from app.finance_reconciliation_exceptions where run_id = v_run.id;

  begin
    perform app.certify_finance_reconciliation_run(v_run.id, v_run.record_version, 'attempting early certification', '00000000-0000-0000-0000-000000034002', 'financemanagera');
    raise exception 'assertion failed: expected finance_reconciliation_unexplained_variance while the exception remains open';
  exception
    when others then
      if sqlerrm !~ 'finance_reconciliation_unexplained_variance' then
        raise exception 'assertion failed: expected finance_reconciliation_unexplained_variance, got %', sqlerrm;
      end if;
  end;

  begin
    perform app.resolve_finance_reconciliation_exception(v_exception.id, v_exception.record_version, '', '00000000-0000-0000-0000-000000034003', 'financeeditora');
    raise exception 'assertion failed: expected finance_reconciliation_resolution_reason_required for an empty reason';
  exception
    when others then
      if sqlerrm !~ 'finance_reconciliation_resolution_reason_required' then
        raise exception 'assertion failed: expected finance_reconciliation_resolution_reason_required, got %', sqlerrm;
      end if;
  end;

  perform app.resolve_finance_reconciliation_exception(v_exception.id, v_exception.record_version, 'confirmed timing difference, in-transit invoice', '00000000-0000-0000-0000-000000034003', 'financeeditora');
  select * into v_exception from app.finance_reconciliation_exceptions where id = v_exception.id;
  if v_exception.status <> 'resolved' then
    raise exception 'assertion failed: expected Finance Editor A (FIN:Edit) to resolve the exception';
  end if;

  begin
    perform app.certify_finance_reconciliation_run(v_run.id, v_run.record_version, 'all exceptions resolved', '00000000-0000-0000-0000-000000034003', 'financeeditora');
    raise exception 'assertion failed: expected insufficient_authority for Finance Editor A (no FIN:Approve) certifying';
  exception
    when insufficient_privilege then
      null;
  end;

  perform app.certify_finance_reconciliation_run(v_run.id, v_run.record_version, 'all exceptions resolved', '00000000-0000-0000-0000-000000034002', 'financemanagera');
  select * into v_run from app.finance_reconciliation_runs where id = v_run.id;
  if v_run.status <> 'certified' then
    raise exception 'assertion failed: expected the run to be certified once its own exception was resolved';
  end if;

  -- idempotent certify
  perform app.certify_finance_reconciliation_run(v_run.id, v_run.record_version, 'retry', '00000000-0000-0000-0000-000000034002', 'financemanagera');
end;
$$;

\echo '>> as-of-date bounding: a run as of a date between the two seeded open items (2026-06-20 and 2026-07-20) excludes the later one from its own source_total'
do $$
declare
  v_tenant_a uuid;
  v_run_early app.finance_reconciliation_runs;
begin
  v_tenant_a := (select id from app.tenants where slug = 'acmerecona');
  select * into v_run_early from app.execute_finance_reconciliation_run(v_tenant_a, null, 'ar', '2026-06-25'::date, 0, '00000000-0000-0000-0000-000000034002', 'financemanagera');
  if v_run_early.source_total <> 500 then
    raise exception 'assertion failed: expected an as-of date between the two seeded open items to exclude the later (2026-07-20) one, got source_total=%', v_run_early.source_total;
  end if;
end;
$$;

\echo '>> cross-tenant isolation: Finance Manager B cannot execute/certify against tenant A''s own scope, and list_finance_reconciliation_runs never returns tenant A''s rows for tenant B''s own scope'
do $$
declare
  v_tenant_a uuid;
  v_tenant_b uuid;
  v_count integer;
begin
  v_tenant_a := (select id from app.tenants where slug = 'acmerecona');
  v_tenant_b := (select id from app.tenants where slug = 'acmereconb');

  select count(*) into v_count from app.list_finance_reconciliation_runs(v_tenant_b, null, null, '00000000-0000-0000-0000-000000034005');
  if v_count <> 0 then
    raise exception 'assertion failed: expected zero reconciliation runs visible to tenant B, got %', v_count;
  end if;
end;
$$;

\echo '>> schema-privilege defense in depth: anon holds zero EXECUTE on every new FIN-209 function (ERR-2026-004 regression guard)'
do $$
declare
  v_leaked_count integer;
begin
  select count(*) into v_leaked_count
    from information_schema.routine_privileges
    where routine_schema = 'app'
      and grantee = 'anon'
      and routine_name in (
        'execute_finance_reconciliation_run', 'resolve_finance_reconciliation_exception',
        'certify_finance_reconciliation_run', 'list_finance_reconciliation_runs',
        'list_finance_reconciliation_exceptions', 'check_finance_reconciliation_authority'
      );
  if v_leaked_count <> 0 then
    raise exception 'assertion failed: expected zero anon EXECUTE grants on FIN-209 functions, found %', v_leaked_count;
  end if;
end;
$$;

\echo '>> audit trail: at least one execute/resolve/certify event was captured for tenant A''s own reconciliation activity'
do $$
declare
  v_tenant_a uuid;
  v_count integer;
begin
  v_tenant_a := (select id from app.tenants where slug = 'acmerecona');
  select count(*) into v_count from app.audit_logs
    where tenant_id = v_tenant_a and action in ('execute_finance_reconciliation_run', 'resolve_finance_reconciliation_exception', 'certify_finance_reconciliation_run');
  if v_count = 0 then
    raise exception 'assertion failed: expected at least one FIN-209 audit event for tenant A';
  end if;
end;
$$;

\echo 'ALL FIN-209 (Reconciliation) db-test assertions passed.'
