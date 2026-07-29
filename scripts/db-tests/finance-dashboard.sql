-- Real, executable test evidence for FIN-213 (Finance Dashboard and Reports,
-- CG-S9-FIN-024) -- run via `pnpm run db:test` against a real, disposable
-- Postgres database.
-- Proves: the billing summary groups real invoices by status/currency
-- exactly; the reconciliation summary reflects the most recent real run per
-- scope, reusing FIN-209's own computed variance; the cash summary composes
-- FIN-211's own per-account cash position across every bank account,
-- grouped by currency; FIN:View gates every new function; cross-tenant
-- isolation; schema-privilege defense in depth; zero raw per-row export.

\set ON_ERROR_STOP on

\echo '>> setup: one tenant, a Full Pipeline Rep (COM/OPS/FIN), a Finance Manager (FIN:Create/Edit/Approve/View, tenant_admin), a Plain User with no FIN grant, a second tenant with its own Finance Manager, six open fiscal periods, a chart of accounts (AR-CTRL/REV-DEFAULT/TAX-PAYABLE-DEFAULT/CASH-BANK), and a published finance_posting_map (ar_control/revenue_default/tax_payable_default/cash_default)'
do $$
declare
  v_tenant1 uuid;
  v_tenant2 uuid;
  v_team_a uuid;
  v_team_b uuid;
  v_full_role uuid;
  v_full_draft app.role_versions;
  v_fin_manager_role uuid;
  v_fin_manager_draft app.role_versions;
  v_fin_manager2_role uuid;
  v_fin_manager2_draft app.role_versions;
  v_account app.finance_accounts;
  v_pm_draft app.config_versions;
begin
  insert into auth.users (id, email) values
    ('00000000-0000-0000-0000-000000038001', 'admin@acmedasha.test'),
    ('00000000-0000-0000-0000-000000038002', 'repa@acmedasha.test'),
    ('00000000-0000-0000-0000-000000038003', 'financemanagera@acmedasha.test'),
    ('00000000-0000-0000-0000-000000038004', 'plainusera@acmedasha.test'),
    ('00000000-0000-0000-0000-000000038005', 'financemanagerb@acmedasha.test');

  perform app.provision_tenant('acmedasha', 'Acme Dashboard A', 'idem-acmedasha', 'tester');
  v_tenant1 := (select id from app.tenants where slug = 'acmedasha');
  perform app.transition_tenant_status(v_tenant1, 'active', 'setup', 'tester');
  perform app.create_org_unit(v_tenant1, 'company', null, 'ACMEDASHA-CO', 'Acme Dashboard A', 'tester');
  v_team_a := (select id from app.org_units where tenant_id = v_tenant1 and code = 'ACMEDASHA-CO');

  perform app.provision_tenant('acmedashb', 'Acme Dashboard B', 'idem-acmedashb', 'tester');
  v_tenant2 := (select id from app.tenants where slug = 'acmedashb');
  perform app.transition_tenant_status(v_tenant2, 'active', 'setup', 'tester');
  perform app.create_org_unit(v_tenant2, 'company', null, 'ACMEDASHB-CO', 'Acme Dashboard B', 'tester');
  v_team_b := (select id from app.org_units where tenant_id = v_tenant2 and code = 'ACMEDASHB-CO');

  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000038001', 'admin@acmedasha.test', 'Admin A', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'admin@acmedasha.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000038001', 'tenant_admin', v_tenant1, null, 'tester');

  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000038002', 'repa@acmedasha.test', 'Rep A', v_team_a, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'repa@acmedasha.test'), 'active', 'onboarded', 'tester');

  v_full_role := (app.create_role(v_tenant1, 'Full Pipeline Rep', 'full COM/OPS/FIN access to build the fixture', 'tester')).id;
  v_full_draft := app.create_role_version(v_full_role, 'tester');
  perform app.set_role_version_permissions(
    v_full_draft.id,
    array(select id from app.permissions where (resource_module_code = 'COM' and action in ('Create', 'Edit', 'Approve', 'View', 'View selling price', 'View cost'))
      or (resource_module_code = 'OPS' and action in ('Create', 'Edit', 'Override', 'View'))
      or (resource_module_code = 'FIN' and action in ('Create', 'Edit', 'Approve', 'View'))),
    'tester'
  );
  perform app.publish_role_version(v_full_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_full_role and status = 'published'), '00000000-0000-0000-0000-000000038002', '00000000-0000-0000-0000-000000038001', 'tester');

  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000038003', 'financemanagera@acmedasha.test', 'Finance Manager A', v_team_a, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'financemanagera@acmedasha.test'), 'active', 'onboarded', 'tester');
  v_fin_manager_role := (app.create_role(v_tenant1, 'Finance Manager', 'dashboard authority', 'tester')).id;
  v_fin_manager_draft := app.create_role_version(v_fin_manager_role, 'tester');
  perform app.set_role_version_permissions(v_fin_manager_draft.id, array(select id from app.permissions where resource_module_code = 'FIN' and action in ('Create', 'Edit', 'Approve', 'View')), 'tester');
  perform app.publish_role_version(v_fin_manager_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_fin_manager_role and status = 'published'), '00000000-0000-0000-0000-000000038003', '00000000-0000-0000-0000-000000038001', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000038003', 'tenant_admin', v_tenant1, null, 'tester');

  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000038004', 'plainusera@acmedasha.test', 'Plain User A', v_team_a, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'plainusera@acmedasha.test'), 'active', 'onboarded', 'tester');

  perform app.invite_user(v_tenant2, '00000000-0000-0000-0000-000000038005', 'financemanagerb@acmedasha.test', 'Finance Manager B', v_team_b, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'financemanagerb@acmedasha.test'), 'active', 'onboarded', 'tester');
  v_fin_manager2_role := (app.create_role(v_tenant2, 'Finance Manager', 'dashboard authority', 'tester')).id;
  v_fin_manager2_draft := app.create_role_version(v_fin_manager2_role, 'tester');
  perform app.set_role_version_permissions(v_fin_manager2_draft.id, array(select id from app.permissions where resource_module_code = 'FIN' and action in ('Create', 'Edit', 'Approve', 'View')), 'tester');
  perform app.publish_role_version(v_fin_manager2_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant2, (select id from app.role_versions where role_id = v_fin_manager2_role and status = 'published'), '00000000-0000-0000-0000-000000038005', '00000000-0000-0000-0000-000000038005', 'tester');

  perform app.generate_finance_fiscal_calendar(v_tenant1, null, 'FY2026', 'FY2026 Monthly', '2026-01-01'::date, 6, '00000000-0000-0000-0000-000000038003', 'financemanagera');

  select * into v_account from app.create_finance_account_draft(v_tenant1, null, 'AR-CTRL', 'Accounts Receivable Control', 'asset', 'debit', null, false, null, '00000000-0000-0000-0000-000000038003', 'financemanagera');
  perform app.activate_finance_account(v_account.id, v_account.record_version, '00000000-0000-0000-0000-000000038003', 'financemanagera');
  select * into v_account from app.create_finance_account_draft(v_tenant1, null, 'REV-DEFAULT', 'Default Revenue', 'revenue', 'credit', null, false, null, '00000000-0000-0000-0000-000000038003', 'financemanagera');
  perform app.activate_finance_account(v_account.id, v_account.record_version, '00000000-0000-0000-0000-000000038003', 'financemanagera');
  select * into v_account from app.create_finance_account_draft(v_tenant1, null, 'TAX-PAYABLE-DEFAULT', 'Default Tax Payable', 'liability', 'credit', null, false, null, '00000000-0000-0000-0000-000000038003', 'financemanagera');
  perform app.activate_finance_account(v_account.id, v_account.record_version, '00000000-0000-0000-0000-000000038003', 'financemanagera');
  select * into v_account from app.create_finance_account_draft(v_tenant1, null, 'CASH-BANK', 'Cash at Bank', 'asset', 'debit', null, false, null, '00000000-0000-0000-0000-000000038003', 'financemanagera');
  perform app.activate_finance_account(v_account.id, v_account.record_version, '00000000-0000-0000-0000-000000038003', 'financemanagera');

  select * into v_pm_draft from app.create_finance_config_draft('finance_posting_map', v_tenant1, 'tenant', null, '00000000-0000-0000-0000-000000038003', 'financemanagera');
  perform app.set_finance_config_items(v_pm_draft.id, jsonb_build_array(
    jsonb_build_object('key', 'ar_control', 'value', jsonb_build_object('accountCodeRef', 'AR-CTRL')),
    jsonb_build_object('key', 'revenue_default', 'value', jsonb_build_object('accountCodeRef', 'REV-DEFAULT')),
    jsonb_build_object('key', 'tax_payable_default', 'value', jsonb_build_object('accountCodeRef', 'TAX-PAYABLE-DEFAULT')),
    jsonb_build_object('key', 'cash_default', 'value', jsonb_build_object('accountCodeRef', 'CASH-BANK'))
  ), '00000000-0000-0000-0000-000000038003', 'financemanagera');
  perform app.publish_finance_config_version(v_pm_draft.id, '00000000-0000-0000-0000-000000038003', null, 'financemanagera');
end;
$$;

\echo '>> fixture: full Commercial->Operations pipeline to one confirmed Job Order, two BillingReadinessHandoffs off it -- one invoice issued, one left draft, both carrying the identical 16,000,000 IDR revenue_snapshot (FIN-197''s own disclosed one-summary-charge-line-per-invoice design reads the same Job Order snapshot regardless of which handoff sourced it) -- plus one bank account with no transactions'
do $$
declare
  v_tenant1 uuid;
  v_team_a uuid;
  v_lead app.leads;
  v_prospect app.prospects;
  v_contact app.contacts;
  v_opportunity app.opportunities;
  v_request app.costing_requests;
  v_rate app.vendor_rate_versions;
  v_selection app.rate_selections;
  v_rule app.margin_rule_versions;
  v_calc_id uuid;
  v_quote app.quotations;
  v_send record;
  v_account app.accounts;
  v_handoff app.job_order_handoffs;
  v_job app.job_orders;
  v_evaluation app.billing_readiness_evaluations;
  v_br_handoff1 app.billing_readiness_handoffs;
  v_br_handoff2 app.billing_readiness_handoffs;
  v_invoice1 app.finance_invoices;
  v_invoice2 app.finance_invoices;
  v_bank_gl app.finance_accounts;
  v_bank app.finance_bank_accounts;
begin
  v_tenant1 := (select id from app.tenants where slug = 'acmedasha');
  v_team_a := (select id from app.org_units where tenant_id = v_tenant1 and code = 'ACMEDASHA-CO');

  perform app.capture_lead(v_tenant1, 'manual', null, 'Dashboard Test Co', 'Jane Dash', 'jane@dashtest.test', '0811',
    '00000000-0000-0000-0000-000000038002', v_team_a, '00000000-0000-0000-0000-000000038002', 'tester');
  select * into v_lead from app.leads where email = 'jane@dashtest.test';
  perform app.qualify_lead(v_lead.id, v_lead.record_version, '00000000-0000-0000-0000-000000038002', 'tester');
  select * into v_lead from app.leads where id = v_lead.id;
  perform app.convert_lead_to_prospect(v_lead.id, 'Dashboard Test Co', 'DTC', '33.333.333.3-333.000',
    jsonb_build_object('line1', 'Jl. Rasuna Said 1', 'city', 'Jakarta', 'country', 'ID'),
    '00000000-0000-0000-0000-000000038002', 'tester');
  select * into v_prospect from app.prospects where lead_id = v_lead.id;

  select * into v_contact from app.create_contact(v_tenant1, 'Jane Dash', 'Procurement Lead', 'jane@dashtest.test', '0811', '00000000-0000-0000-0000-000000038002', v_team_a, '00000000-0000-0000-0000-000000038002', 'tester');
  perform app.link_contact_to_record(v_contact.id, 'prospect', v_prospect.id, 'primary', true, '00000000-0000-0000-0000-000000038002', 'tester');

  select * into v_opportunity from app.create_opportunity(
    v_tenant1, v_prospect.id, 'Dashboard test lane',
    jsonb_build_object('service_type', 'ocean_freight', 'cargo_description', 'General cargo', 'origin', 'Jakarta', 'destination', 'Surabaya', 'target_ready_date', '2026-08-01'),
    '00000000-0000-0000-0000-000000038002', v_team_a, '00000000-0000-0000-0000-000000038002', 'tester'
  );
  select * into v_request from app.request_costing(v_opportunity.id, '[]'::jsonb, null, '00000000-0000-0000-0000-000000038002', 'tester');
  select * into v_rate from app.create_rate_version(
    v_tenant1, 'VENDOR-DASH-1', 'Contoso Ocean Line', 'ocean_freight', 'FCL', 'Jakarta', 'Surabaya', '20ft',
    null, null, null, null, 'IDR', 10000000, null, '[]'::jsonb, now(), null, null, '00000000-0000-0000-0000-000000038001', 'tester'
  );
  perform app.approve_rate_version(v_rate.id, v_rate.record_version, '00000000-0000-0000-0000-000000038001', 'tester');
  select * into v_selection from app.select_vendor_rate(v_request.id, v_rate.id, false, null, null, null, '00000000-0000-0000-0000-000000038002', 'tester');

  select * into v_rule from app.create_margin_rule_version(v_tenant1, 20.00, 'half_up', '00000000-0000-0000-0000-000000038002', 'tester');
  perform app.publish_margin_rule_version(v_rule.id, v_rule.record_version, null, '00000000-0000-0000-0000-000000038002', 'tester');
  perform app.calculate_margin(v_selection.id, 16000000, 'IDR', 0, '00000000-0000-0000-0000-000000038002', 'tester');
  select id into v_calc_id from app.margin_calculations where rate_selection_id = v_selection.id and is_current;

  select * into v_quote from app.create_quotation_draft(v_tenant1, v_opportunity.id, 'IDR', now() + interval '14 days', v_contact.id, null, null, '00000000-0000-0000-0000-000000038002', 'tester');
  perform app.add_quotation_line(v_quote.id, v_quote.record_version, 'service', 'Ocean freight lane', v_calc_id, 1, 16000000, 0, 0, '00000000-0000-0000-0000-000000038002', 'tester');
  select * into v_quote from app.quotations where id = v_quote.id;
  perform app.submit_quotation(v_quote.id, v_quote.record_version, '00000000-0000-0000-0000-000000038002', 'tester');
  select * into v_send from app.send_quotation_for_acceptance(v_quote.id, null, 'email', '00000000-0000-0000-0000-000000038002', 'tester');
  perform app.record_quotation_customer_decision(v_send.raw_token, 'accepted', 'Jane Dash', null, null, null, null, null);

  select * into v_account from app.convert_quotation_to_account(v_quote.id, null, null, '00000000-0000-0000-0000-000000038002', 'rep');
  select * into v_handoff from app.prepare_job_order_handoff(v_quote.id, '00000000-0000-0000-0000-000000038002', 'rep');
  select * into v_job from app.prepare_job_order(v_handoff.id, '00000000-0000-0000-0000-000000038002', 'rep');

  -- First handoff -> invoice #1: prepare, submit, approve, issue (16,000,000 IDR, no tax).
  select * into v_evaluation from app.evaluate_billing_readiness(v_job.id, null, '00000000-0000-0000-0000-000000038002', 'rep');
  select * into v_evaluation from app.override_billing_readiness(v_job.id, v_evaluation.record_version, 'fixture: bypassing full evidence chain, out of FIN-213''s own test scope', '00000000-0000-0000-0000-000000038002', 'rep');
  select * into v_br_handoff1 from app.handoff_billing_readiness(v_job.id, 'dashboard-fixture-handoff-1', '00000000-0000-0000-0000-000000038002', 'rep');

  select * into v_invoice1 from app.prepare_finance_invoice_from_readiness(v_tenant1, v_br_handoff1.id, 30, null, '00000000-0000-0000-0000-000000038003', 'financemanagera');
  select * into v_invoice1 from app.submit_finance_invoice_for_approval(v_invoice1.id, v_invoice1.record_version, '00000000-0000-0000-0000-000000038003', 'financemanagera');
  select * into v_invoice1 from app.approve_finance_invoice(v_invoice1.id, v_invoice1.record_version, '00000000-0000-0000-0000-000000038003', 'financemanagera');
  perform app.issue_finance_invoice(v_invoice1.id, v_invoice1.record_version, '2026-03-01'::date, '00000000-0000-0000-0000-000000038003', 'financemanagera');

  -- Second, distinct handoff on the same Job Order -> invoice #2: prepared, left draft (16,000,000 IDR -- the identical job-level revenue_snapshot, since a second invoice off the same Job Order reads the same snapshot).
  select * into v_evaluation from app.evaluate_billing_readiness(v_job.id, 'fixture: second handoff for FIN-213''s own billing-summary draft-row test', '00000000-0000-0000-0000-000000038002', 'rep');
  select * into v_evaluation from app.override_billing_readiness(v_job.id, v_evaluation.record_version, 'fixture: second override', '00000000-0000-0000-0000-000000038002', 'rep');
  select * into v_br_handoff2 from app.handoff_billing_readiness(v_job.id, 'dashboard-fixture-handoff-2', '00000000-0000-0000-0000-000000038002', 'rep');
  select * into v_invoice2 from app.prepare_finance_invoice_from_readiness(v_tenant1, v_br_handoff2.id, 30, null, '00000000-0000-0000-0000-000000038003', 'financemanagera');

  -- One bank account, no transactions -- cash summary should reconcile to exactly zero.
  select * into v_bank_gl from app.finance_accounts where tenant_id = v_tenant1 and code = 'CASH-BANK';
  select * into v_bank from app.create_finance_bank_account(v_tenant1, null, 'Main Operating Account', 'Bank Mandiri', '1234', 'IDR', v_bank_gl.id, '00000000-0000-0000-0000-000000038003', 'financemanagera');

  -- One reconciliation run for scope ar -- the GL side (from invoice #1's own FIN-202 posting) and the open-item side (from the same invoice's own FIN-196 AR open item) derive from the identical event, so this must reconcile exactly.
  perform app.execute_finance_reconciliation_run(v_tenant1, null, 'ar', '2026-04-01'::date, 0, '00000000-0000-0000-0000-000000038003', 'financemanagera');
end;
$$;

\echo '>> app.get_finance_dashboard_billing_summary: FIN:View-gated, denies Plain User A and tenant B''s own Finance Manager, groups exactly the two real invoices by status/currency'
do $$
declare
  v_tenant1 uuid;
  v_rows record;
  v_count integer;
begin
  v_tenant1 := (select id from app.tenants where slug = 'acmedasha');

  begin
    perform app.get_finance_dashboard_billing_summary(v_tenant1, null, '00000000-0000-0000-0000-000000038004');
    raise exception 'assertion failed: expected insufficient_authority for Plain User A (no FIN grant)';
  exception
    when insufficient_privilege then
      null;
  end;

  begin
    perform app.get_finance_dashboard_billing_summary(v_tenant1, null, '00000000-0000-0000-0000-000000038005');
    raise exception 'assertion failed: expected insufficient_authority for Finance Manager B (no FIN grant for tenant A)';
  exception
    when insufficient_privilege then
      null;
  end;

  select count(*) into v_count from app.get_finance_dashboard_billing_summary(v_tenant1, null, '00000000-0000-0000-0000-000000038003');
  if v_count <> 2 then
    raise exception 'assertion failed: expected exactly 2 grouped rows (draft, issued), found %', v_count;
  end if;

  select * into v_rows from app.get_finance_dashboard_billing_summary(v_tenant1, null, '00000000-0000-0000-0000-000000038003') where status = 'issued';
  if v_rows.currency <> 'IDR' or v_rows.invoice_count <> 1 or v_rows.total_amount <> 16000000 then
    raise exception 'assertion failed: expected 1 issued IDR invoice totalling 16,000,000, got currency=% count=% total=%', v_rows.currency, v_rows.invoice_count, v_rows.total_amount;
  end if;

  select * into v_rows from app.get_finance_dashboard_billing_summary(v_tenant1, null, '00000000-0000-0000-0000-000000038003') where status = 'draft';
  if v_rows.currency <> 'IDR' or v_rows.invoice_count <> 1 or v_rows.total_amount <> 16000000 then
    raise exception 'assertion failed: expected 1 draft IDR invoice totalling 16,000,000 (the same Job Order revenue_snapshot as the issued invoice), got currency=% count=% total=%', v_rows.currency, v_rows.invoice_count, v_rows.total_amount;
  end if;
end;
$$;

\echo '>> app.get_finance_dashboard_reconciliation_summary: FIN:View-gated, reflects the one real ar run exactly (in tolerance, zero variance -- the GL and open-item sides derive from the identical posting event)'
do $$
declare
  v_tenant1 uuid;
  v_rows record;
begin
  v_tenant1 := (select id from app.tenants where slug = 'acmedasha');

  begin
    perform app.get_finance_dashboard_reconciliation_summary(v_tenant1, null, '00000000-0000-0000-0000-000000038004');
    raise exception 'assertion failed: expected insufficient_authority for Plain User A';
  exception
    when insufficient_privilege then
      null;
  end;

  select * into v_rows from app.get_finance_dashboard_reconciliation_summary(v_tenant1, null, '00000000-0000-0000-0000-000000038003') where scope = 'ar';
  if v_rows.status <> 'completed' or v_rows.is_within_tolerance <> true or v_rows.variance_amount <> 0 then
    raise exception 'assertion failed: expected the ar run to be completed/in-tolerance/zero-variance, got status=% within_tolerance=% variance=%', v_rows.status, v_rows.is_within_tolerance, v_rows.variance_amount;
  end if;
end;
$$;

\echo '>> app.get_finance_dashboard_cash_summary: FIN:View-gated, composes exactly one bank account (no transactions, no GL activity) into a single zero-balance IDR row'
do $$
declare
  v_tenant1 uuid;
  v_rows record;
begin
  v_tenant1 := (select id from app.tenants where slug = 'acmedasha');

  begin
    perform app.get_finance_dashboard_cash_summary(v_tenant1, null, '2026-04-01'::date, '00000000-0000-0000-0000-000000038004');
    raise exception 'assertion failed: expected insufficient_authority for Plain User A';
  exception
    when insufficient_privilege then
      null;
  end;

  select * into v_rows from app.get_finance_dashboard_cash_summary(v_tenant1, null, '2026-04-01'::date, '00000000-0000-0000-0000-000000038003');
  if v_rows.currency <> 'IDR' or v_rows.account_count <> 1 or v_rows.statement_balance <> 0 or v_rows.gl_balance <> 0 or v_rows.variance_amount <> 0 then
    raise exception 'assertion failed: expected exactly 1 IDR account, zero statement/gl/variance, got currency=% count=% statement=% gl=% variance=%',
      v_rows.currency, v_rows.account_count, v_rows.statement_balance, v_rows.gl_balance, v_rows.variance_amount;
  end if;
end;
$$;

\echo '>> cross-tenant isolation: tenant B''s own dashboard reads are authority-gated to tenant B and return zero rows against its own empty data'
do $$
declare
  v_tenant2 uuid;
  v_count integer;
begin
  v_tenant2 := (select id from app.tenants where slug = 'acmedashb');

  select count(*) into v_count from app.get_finance_dashboard_billing_summary(v_tenant2, null, '00000000-0000-0000-0000-000000038005');
  if v_count <> 0 then
    raise exception 'assertion failed: expected tenant B''s own billing summary to be empty, found % rows', v_count;
  end if;

  select count(*) into v_count from app.get_finance_dashboard_reconciliation_summary(v_tenant2, null, '00000000-0000-0000-0000-000000038005');
  if v_count <> 0 then
    raise exception 'assertion failed: expected tenant B''s own reconciliation summary to be empty, found % rows', v_count;
  end if;

  select count(*) into v_count from app.get_finance_dashboard_cash_summary(v_tenant2, null, '2026-04-01'::date, '00000000-0000-0000-0000-000000038005');
  if v_count <> 0 then
    raise exception 'assertion failed: expected tenant B''s own cash summary to be empty, found % rows', v_count;
  end if;
end;
$$;

\echo '>> schema-privilege defense in depth: anon holds zero EXECUTE on every new FIN-213 function (ERR-2026-004 regression guard)'
do $$
declare
  v_fn text;
  v_anon_has boolean;
begin
  for v_fn in select unnest(array[
    'check_finance_dashboard_authority', 'get_finance_dashboard_billing_summary',
    'get_finance_dashboard_reconciliation_summary', 'get_finance_dashboard_cash_summary'
  ]) loop
    select bool_or(has_function_privilege('anon', p.oid, 'EXECUTE'))
      into v_anon_has
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'app' and p.proname = v_fn;
    if coalesce(v_anon_has, false) then
      raise exception 'assertion failed: expected anon to hold zero EXECUTE on app.%, found at least one overload granted', v_fn;
    end if;
  end loop;
end;
$$;
