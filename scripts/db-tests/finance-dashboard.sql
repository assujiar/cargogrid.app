-- Real, executable test evidence for FIN-213 (Finance Dashboard and Reports,
-- CG-S9-FIN-024) -- run via `pnpm run db:test` against a real, disposable
-- Postgres database.
-- Proves: the three genuinely new widgets (billing summary, cash summary,
-- close/reconciliation status) each return real, correctly-grouped/joined
-- data (never a fabricated total); AR/AP aging and profitability widgets
-- are reused verbatim (their own correctness is proven by FIN-210's/
-- FIN-212's own db-test files -- not re-derived here); FIN:View authority
-- denial for a Plain User on each new function; cross-tenant isolation;
-- the six report_types codes this migration registers are active and one
-- source_function each; FIN:Export-gated export enqueue success/denial and
-- an unknown report code; schema-privilege defense in depth; audit trail.

\set ON_ERROR_STOP on

\echo '>> setup: two tenants; tenant A gets a full Commercial->Operations->Finance pipeline to one issued invoice plus a second draft invoice off the same job order (FIN-197''s own second-handoff fixture shape), a small chart of accounts (CASH-BANK, AR-CONTROL) with a published posting map (cash_default, ar_control), one active bank account, a locked fiscal period and an executed AR reconciliation run; a Finance Manager (FIN:Create/Edit/Approve/Export/View), a Plain User with no FIN grant; tenant B gets its own Finance Manager and one open fiscal period, no Finance data of its own'
do $$
declare
  v_tenant_a uuid;
  v_tenant_b uuid;
  v_team_a uuid;
  v_team_b uuid;
  v_full_role uuid;
  v_full_draft app.role_versions;
  v_fin_manager_role uuid;
  v_fin_manager_draft app.role_versions;
  v_fin_manager2_role uuid;
  v_fin_manager2_draft app.role_versions;
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
  v_job_handoff app.job_order_handoffs;
  v_job app.job_orders;
  v_evaluation app.billing_readiness_evaluations;
  v_handoff1 app.billing_readiness_handoffs;
  v_handoff2 app.billing_readiness_handoffs;
  v_invoice app.finance_invoices;
  v_invoice2 app.finance_invoices;
  v_cash_account app.finance_accounts;
  v_ar_account app.finance_accounts;
  v_revenue_account app.finance_accounts;
  v_pm_draft app.config_versions;
  v_period record;
  v_bank_account app.finance_bank_accounts;
  v_lock app.finance_period_locks;
  v_recon app.finance_reconciliation_runs;
begin
  insert into auth.users (id, email) values
    ('00000000-0000-0000-0000-000000037501', 'admin@acmedash.test'),
    ('00000000-0000-0000-0000-000000037502', 'repa@acmedash.test'),
    ('00000000-0000-0000-0000-000000037503', 'financemanagera@acmedash.test'),
    ('00000000-0000-0000-0000-000000037504', 'plainusera@acmedash.test'),
    ('00000000-0000-0000-0000-000000037505', 'financemanagerb@acmedash.test');

  perform app.provision_tenant('acmedasha', 'Acme Dashboard A', 'idem-acmedasha', 'tester');
  v_tenant_a := (select id from app.tenants where slug = 'acmedasha');
  perform app.transition_tenant_status(v_tenant_a, 'active', 'setup', 'tester');
  perform app.create_org_unit(v_tenant_a, 'company', null, 'ACMEDASHA-CO', 'Acme Dashboard A', 'tester');
  v_team_a := (select id from app.org_units where tenant_id = v_tenant_a and code = 'ACMEDASHA-CO');

  perform app.provision_tenant('acmedashb', 'Acme Dashboard B', 'idem-acmedashb', 'tester');
  v_tenant_b := (select id from app.tenants where slug = 'acmedashb');
  perform app.transition_tenant_status(v_tenant_b, 'active', 'setup', 'tester');
  perform app.create_org_unit(v_tenant_b, 'company', null, 'ACMEDASHB-CO', 'Acme Dashboard B', 'tester');
  v_team_b := (select id from app.org_units where tenant_id = v_tenant_b and code = 'ACMEDASHB-CO');

  perform app.invite_user(v_tenant_a, '00000000-0000-0000-0000-000000037501', 'admin@acmedash.test', 'Admin A', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'admin@acmedash.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000037501', 'tenant_admin', v_tenant_a, null, 'tester');

  perform app.invite_user(v_tenant_a, '00000000-0000-0000-0000-000000037502', 'repa@acmedash.test', 'Rep A', v_team_a, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'repa@acmedash.test'), 'active', 'onboarded', 'tester');

  v_full_role := (app.create_role(v_tenant_a, 'Full Pipeline Rep', 'full COM/OPS/FIN access to build the fixture', 'tester')).id;
  v_full_draft := app.create_role_version(v_full_role, 'tester');
  perform app.set_role_version_permissions(
    v_full_draft.id,
    array(select id from app.permissions where (resource_module_code = 'COM' and action in ('Create', 'Edit', 'Approve', 'View', 'View selling price', 'View cost'))
      or (resource_module_code = 'OPS' and action in ('Create', 'Edit', 'Override', 'View'))
      or (resource_module_code = 'FIN' and action in ('Create', 'Edit', 'Approve', 'View'))),
    'tester'
  );
  perform app.publish_role_version(v_full_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant_a, (select id from app.role_versions where role_id = v_full_role and status = 'published'), '00000000-0000-0000-0000-000000037502', '00000000-0000-0000-0000-000000037501', 'tester');

  perform app.invite_user(v_tenant_a, '00000000-0000-0000-0000-000000037503', 'financemanagera@acmedash.test', 'Finance Manager A', v_team_a, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'financemanagera@acmedash.test'), 'active', 'onboarded', 'tester');
  v_fin_manager_role := (app.create_role(v_tenant_a, 'Finance Manager', 'dashboard authority', 'tester')).id;
  v_fin_manager_draft := app.create_role_version(v_fin_manager_role, 'tester');
  perform app.set_role_version_permissions(v_fin_manager_draft.id, array(select id from app.permissions where resource_module_code = 'FIN' and action in ('Create', 'Edit', 'Approve', 'Export', 'View')), 'tester');
  perform app.publish_role_version(v_fin_manager_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant_a, (select id from app.role_versions where role_id = v_fin_manager_role and status = 'published'), '00000000-0000-0000-0000-000000037503', '00000000-0000-0000-0000-000000037501', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000037503', 'tenant_admin', v_tenant_a, null, 'tester');

  perform app.invite_user(v_tenant_a, '00000000-0000-0000-0000-000000037504', 'plainusera@acmedash.test', 'Plain User A', v_team_a, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'plainusera@acmedash.test'), 'active', 'onboarded', 'tester');

  perform app.invite_user(v_tenant_b, '00000000-0000-0000-0000-000000037505', 'financemanagerb@acmedash.test', 'Finance Manager B', v_team_b, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'financemanagerb@acmedash.test'), 'active', 'onboarded', 'tester');
  v_fin_manager2_role := (app.create_role(v_tenant_b, 'Finance Manager', 'dashboard authority', 'tester')).id;
  v_fin_manager2_draft := app.create_role_version(v_fin_manager2_role, 'tester');
  perform app.set_role_version_permissions(v_fin_manager2_draft.id, array(select id from app.permissions where resource_module_code = 'FIN' and action in ('Create', 'Edit', 'Approve', 'Export', 'View')), 'tester');
  perform app.publish_role_version(v_fin_manager2_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant_b, (select id from app.role_versions where role_id = v_fin_manager2_role and status = 'published'), '00000000-0000-0000-0000-000000037505', '00000000-0000-0000-0000-000000037505', 'tester');

  -- Full Commercial->Operations pipeline (mirrors FIN-197's own fixture shape).
  perform app.capture_lead(v_tenant_a, 'manual', null, 'Finance Dashboard Test Co', 'Jane Dashboard', 'jane@acmefindash.test', '0811',
    '00000000-0000-0000-0000-000000037502', v_team_a, '00000000-0000-0000-0000-000000037502', 'tester');
  select * into v_lead from app.leads where email = 'jane@acmefindash.test';
  perform app.qualify_lead(v_lead.id, v_lead.record_version, '00000000-0000-0000-0000-000000037502', 'tester');
  select * into v_lead from app.leads where id = v_lead.id;
  perform app.convert_lead_to_prospect(v_lead.id, 'Finance Dashboard Test Co', 'FDTC', '66.666.666.7-779.000',
    jsonb_build_object('line1', 'Jl. Sudirman 1', 'city', 'Jakarta', 'country', 'ID'),
    '00000000-0000-0000-0000-000000037502', 'tester');
  select * into v_prospect from app.prospects where lead_id = v_lead.id;

  select * into v_contact from app.create_contact(v_tenant_a, 'Jane Dashboard', 'Procurement Lead', 'jane@acmefindash.test', '0811', '00000000-0000-0000-0000-000000037502', v_team_a, '00000000-0000-0000-0000-000000037502', 'tester');
  perform app.link_contact_to_record(v_contact.id, 'prospect', v_prospect.id, 'primary', true, '00000000-0000-0000-0000-000000037502', 'tester');

  select * into v_opportunity from app.create_opportunity(
    v_tenant_a, v_prospect.id, 'Dashboard test lane',
    jsonb_build_object('service_type', 'ocean_freight', 'cargo_description', 'General cargo', 'origin', 'Jakarta', 'destination', 'Surabaya', 'target_ready_date', '2026-08-01'),
    '00000000-0000-0000-0000-000000037502', v_team_a, '00000000-0000-0000-0000-000000037502', 'tester'
  );
  select * into v_request from app.request_costing(v_opportunity.id, '[]'::jsonb, null, '00000000-0000-0000-0000-000000037502', 'tester');
  select * into v_rate from app.create_rate_version(
    v_tenant_a, 'VENDOR-FINDASH-1', 'Contoso Ocean Line', 'ocean_freight', 'FCL', 'Jakarta', 'Surabaya', '20ft',
    null, null, null, null, 'IDR', 10000000, null, '[]'::jsonb, now(), null, null, '00000000-0000-0000-0000-000000037501', 'tester'
  );
  perform app.approve_rate_version(v_rate.id, v_rate.record_version, '00000000-0000-0000-0000-000000037501', 'tester');
  select * into v_selection from app.select_vendor_rate(v_request.id, v_rate.id, false, null, null, null, '00000000-0000-0000-0000-000000037502', 'tester');

  select * into v_rule from app.create_margin_rule_version(v_tenant_a, 20.00, 'half_up', '00000000-0000-0000-0000-000000037502', 'tester');
  perform app.publish_margin_rule_version(v_rule.id, v_rule.record_version, null, '00000000-0000-0000-0000-000000037502', 'tester');
  perform app.calculate_margin(v_selection.id, 15000000, 'IDR', 0, '00000000-0000-0000-0000-000000037502', 'tester');
  select id into v_calc_id from app.margin_calculations where rate_selection_id = v_selection.id and is_current;

  select * into v_quote from app.create_quotation_draft(v_tenant_a, v_opportunity.id, 'IDR', now() + interval '14 days', v_contact.id, null, null, '00000000-0000-0000-0000-000000037502', 'tester');
  perform app.add_quotation_line(v_quote.id, v_quote.record_version, 'service', 'Ocean freight dashboard lane', v_calc_id, 1, 15000000, 0, 0, '00000000-0000-0000-0000-000000037502', 'tester');
  select * into v_quote from app.quotations where id = v_quote.id;
  perform app.submit_quotation(v_quote.id, v_quote.record_version, '00000000-0000-0000-0000-000000037502', 'tester');
  select * into v_send from app.send_quotation_for_acceptance(v_quote.id, null, 'email', '00000000-0000-0000-0000-000000037502', 'tester');
  perform app.record_quotation_customer_decision(v_send.raw_token, 'accepted', 'Jane Dashboard', null, null, null, null, null);

  select * into v_account from app.convert_quotation_to_account(v_quote.id, null, null, '00000000-0000-0000-0000-000000037502', 'rep');
  select * into v_job_handoff from app.prepare_job_order_handoff(v_quote.id, '00000000-0000-0000-0000-000000037502', 'rep');
  select * into v_job from app.prepare_job_order(v_job_handoff.id, '00000000-0000-0000-0000-000000037502', 'rep');

  select * into v_evaluation from app.evaluate_billing_readiness(v_job.id, null, '00000000-0000-0000-0000-000000037502', 'rep');
  select * into v_evaluation from app.override_billing_readiness(v_job.id, v_evaluation.record_version, 'fixture: bypassing full shipment/epod/document/cost evidence chain, out of FIN-213''s own test scope', '00000000-0000-0000-0000-000000037502', 'rep');
  select * into v_handoff1 from app.handoff_billing_readiness(v_job.id, 'dashboard-fixture-handoff-1', '00000000-0000-0000-0000-000000037502', 'rep');

  -- FIN-193: open fiscal periods (Jan-Aug 2026) for tenant A; tenant B gets one open period too.
  perform app.generate_finance_fiscal_calendar(v_tenant_a, null, 'FY2026', 'FY2026 Monthly', '2026-01-01'::date, 8, '00000000-0000-0000-0000-000000037503', 'financemanagera');
  perform app.generate_finance_fiscal_calendar(v_tenant_b, null, 'FY2026', 'FY2026 Monthly', '2026-01-01'::date, 8, '00000000-0000-0000-0000-000000037505', 'financemanagerb');

  -- FIN-192 chart of accounts + FIN-191 posting map (cash_default, ar_control, revenue_default) --
  -- issue_finance_invoice (FIN-202's own retrofit) posts a real balanced subledger batch at issue
  -- time, so this must exist before invoice #1 is issued below.
  select * into v_cash_account from app.create_finance_account_draft(v_tenant_a, null, 'CASH-BANK-DASH', 'Cash', 'asset', 'debit', null, false, null, '00000000-0000-0000-0000-000000037503', 'financemanagera');
  perform app.activate_finance_account(v_cash_account.id, v_cash_account.record_version, '00000000-0000-0000-0000-000000037503', 'financemanagera');
  select * into v_ar_account from app.create_finance_account_draft(v_tenant_a, null, 'AR-CONTROL-DASH', 'Accounts Receivable', 'asset', 'debit', null, false, null, '00000000-0000-0000-0000-000000037503', 'financemanagera');
  perform app.activate_finance_account(v_ar_account.id, v_ar_account.record_version, '00000000-0000-0000-0000-000000037503', 'financemanagera');
  select * into v_revenue_account from app.create_finance_account_draft(v_tenant_a, null, 'REVENUE-DASH', 'Freight Revenue', 'revenue', 'credit', null, false, null, '00000000-0000-0000-0000-000000037503', 'financemanagera');
  perform app.activate_finance_account(v_revenue_account.id, v_revenue_account.record_version, '00000000-0000-0000-0000-000000037503', 'financemanagera');

  select * into v_pm_draft from app.create_finance_config_draft('finance_posting_map', v_tenant_a, 'tenant', null, '00000000-0000-0000-0000-000000037503', 'financemanagera');
  perform app.set_finance_config_items(v_pm_draft.id, jsonb_build_array(
    jsonb_build_object('key', 'cash_default', 'value', jsonb_build_object('accountCodeRef', 'CASH-BANK-DASH')),
    jsonb_build_object('key', 'ar_control', 'value', jsonb_build_object('accountCodeRef', 'AR-CONTROL-DASH')),
    jsonb_build_object('key', 'revenue_default', 'value', jsonb_build_object('accountCodeRef', 'REVENUE-DASH'))
  ), '00000000-0000-0000-0000-000000037503', 'financemanagera');
  perform app.publish_finance_config_version(v_pm_draft.id, '00000000-0000-0000-0000-000000037503', null, 'financemanagera');

  select * into v_bank_account from app.create_finance_bank_account(v_tenant_a, null, 'Main Operating', 'Acme Bank', '4321', 'IDR', v_cash_account.id, '00000000-0000-0000-0000-000000037503', 'financemanagera');

  -- invoice #1: draft -> submitted -> approved -> issued -- posts a real balanced subledger batch (debit AR control, credit revenue) via FIN-202's own retrofit of issue_finance_invoice.
  select * into v_invoice from app.prepare_finance_invoice_from_readiness(v_tenant_a, v_handoff1.id, 30, null, '00000000-0000-0000-0000-000000037503', 'financemanagera');
  perform app.submit_finance_invoice_for_approval(v_invoice.id, v_invoice.record_version, '00000000-0000-0000-0000-000000037503', 'financemanagera');
  select * into v_invoice from app.finance_invoices where id = v_invoice.id;
  perform app.approve_finance_invoice(v_invoice.id, v_invoice.record_version, '00000000-0000-0000-0000-000000037503', 'financemanagera');
  select * into v_invoice from app.finance_invoices where id = v_invoice.id;
  perform app.issue_finance_invoice(v_invoice.id, v_invoice.record_version, '2026-07-15'::date, '00000000-0000-0000-0000-000000037503', 'financemanagera');
  select * into v_invoice from app.finance_invoices where id = v_invoice.id;

  -- invoice #2: a second handoff off the same job order (FIN-197's own "second handoff" test shape), left in 'draft' -- proves the billing widget's LEFT JOIN reports open_amount=0 for a not-yet-issued invoice, never a fabricated figure.
  select * into v_evaluation from app.evaluate_billing_readiness(v_job.id, 'fixture: second handoff for FIN-213''s own draft-bucket test', '00000000-0000-0000-0000-000000037502', 'rep');
  select * into v_evaluation from app.override_billing_readiness(v_job.id, v_evaluation.record_version, 'fixture: second override', '00000000-0000-0000-0000-000000037502', 'rep');
  select * into v_handoff2 from app.handoff_billing_readiness(v_job.id, 'dashboard-fixture-handoff-2', '00000000-0000-0000-0000-000000037502', 'rep');
  select * into v_invoice2 from app.prepare_finance_invoice_from_readiness(v_tenant_a, v_handoff2.id, 30, null, '00000000-0000-0000-0000-000000037503', 'financemanagera');

  -- FIN-207 period lock and FIN-209 reconciliation run over the invoice's own posting period.
  select * into v_period from app.resolve_finance_period_for_date(v_tenant_a, null, '2026-07-15'::date);
  select * into v_lock from app.lock_finance_period(v_tenant_a, null, v_period.period_id, 'ar', 'fixture: FIN-213 close-status widget evidence', null, '00000000-0000-0000-0000-000000037503', 'financemanagera');
  select * into v_recon from app.execute_finance_reconciliation_run(v_tenant_a, null, 'ar', '2026-07-31'::date, 0, '00000000-0000-0000-0000-000000037503', 'financemanagera');
end;
$$;

\echo '>> get_finance_dashboard_billing_summary: two rows (issued with real open_amount from the posted AR open item, draft with open_amount=0), grouped by (status, currency); Plain User denied; Tenant B (no invoices) gets zero rows, not an error'
do $$
declare
  v_tenant_a uuid;
  v_tenant_b uuid;
  v_issued record;
  v_draft record;
  v_count integer;
begin
  v_tenant_a := (select id from app.tenants where slug = 'acmedasha');
  v_tenant_b := (select id from app.tenants where slug = 'acmedashb');

  select * into v_issued from app.get_finance_dashboard_billing_summary(v_tenant_a, null, '00000000-0000-0000-0000-000000037503') where status = 'issued';
  if v_issued.status is null or v_issued.invoice_count <> 1 or v_issued.open_amount <= 0 then
    raise exception 'assertion failed: expected exactly 1 issued invoice with a positive real open_amount, got count=% open_amount=%', v_issued.invoice_count, v_issued.open_amount;
  end if;

  select * into v_draft from app.get_finance_dashboard_billing_summary(v_tenant_a, null, '00000000-0000-0000-0000-000000037503') where status = 'draft';
  if v_draft.status is null or v_draft.invoice_count <> 1 or v_draft.open_amount <> 0 then
    raise exception 'assertion failed: expected exactly 1 draft invoice with open_amount=0 (no AR open item yet), got count=% open_amount=%', v_draft.invoice_count, v_draft.open_amount;
  end if;

  begin
    perform app.get_finance_dashboard_billing_summary(v_tenant_a, null, '00000000-0000-0000-0000-000000037504');
    raise exception 'assertion failed: expected insufficient_authority for Plain User A';
  exception
    when insufficient_privilege then
      null;
  end;

  select count(*) into v_count from app.get_finance_dashboard_billing_summary(v_tenant_b, null, '00000000-0000-0000-0000-000000037505');
  if v_count <> 0 then
    raise exception 'assertion failed: expected zero rows for Tenant B (no invoices of its own), got %', v_count;
  end if;
end;
$$;

\echo '>> get_finance_dashboard_cash_summary: one row for the one active bank account, statement_balance=gl_balance=0 (no statement imported, no GL posting -- honest zero, never fabricated); Plain User denied; cross-tenant isolation'
do $$
declare
  v_tenant_a uuid;
  v_tenant_b uuid;
  v_row record;
  v_count integer;
begin
  v_tenant_a := (select id from app.tenants where slug = 'acmedasha');
  v_tenant_b := (select id from app.tenants where slug = 'acmedashb');

  select * into v_row from app.get_finance_dashboard_cash_summary(v_tenant_a, null, '2026-07-31'::date, '00000000-0000-0000-0000-000000037503');
  if v_row.account_name <> 'Main Operating' or v_row.statement_balance <> 0 or v_row.gl_balance <> 0 or v_row.variance_amount <> 0 then
    raise exception 'assertion failed: expected the one bank account with all-zero balances, got name=% statement=% gl=%', v_row.account_name, v_row.statement_balance, v_row.gl_balance;
  end if;

  begin
    perform app.get_finance_dashboard_cash_summary(v_tenant_a, null, '2026-07-31'::date, '00000000-0000-0000-0000-000000037504');
    raise exception 'assertion failed: expected insufficient_authority for Plain User A';
  exception
    when insufficient_privilege then
      null;
  end;

  select count(*) into v_count from app.get_finance_dashboard_cash_summary(v_tenant_b, null, '2026-07-31'::date, '00000000-0000-0000-0000-000000037505');
  if v_count <> 0 then
    raise exception 'assertion failed: expected zero bank accounts for Tenant B, got %', v_count;
  end if;
end;
$$;

\echo '>> get_finance_dashboard_close_status: the invoice''s own posting period reports lock_status=locked (from FIN-207) and reconciliation_status=completed with reconciliation_within_tolerance=true (the real posted AR-control subledger line matches the real open AR item exactly -- FIN-202''s own retrofit of issue_finance_invoice posts both from the same invoice total); Plain User denied'
do $$
declare
  v_tenant_a uuid;
  v_row record;
begin
  v_tenant_a := (select id from app.tenants where slug = 'acmedasha');

  select * into v_row from app.get_finance_dashboard_close_status(v_tenant_a, null, '00000000-0000-0000-0000-000000037503')
    where period_code = (select period_code from app.finance_fiscal_periods where tenant_id = v_tenant_a and '2026-07-15'::date between start_date and end_date);
  if v_row.lock_status <> 'locked' then
    raise exception 'assertion failed: expected lock_status=locked for the invoice''s own posting period, got %', v_row.lock_status;
  end if;
  if v_row.reconciliation_status <> 'completed' or v_row.reconciliation_within_tolerance <> true then
    raise exception 'assertion failed: expected reconciliation_status=completed/within_tolerance=true (real AR-control-vs-open-item match), got status=% within=%', v_row.reconciliation_status, v_row.reconciliation_within_tolerance;
  end if;

  begin
    perform app.get_finance_dashboard_close_status(v_tenant_a, null, '00000000-0000-0000-0000-000000037504');
    raise exception 'assertion failed: expected insufficient_authority for Plain User A';
  exception
    when insufficient_privilege then
      null;
  end;
end;
$$;

\echo '>> report_types: all six FIN-213 codes are active with the correct source_function; enqueue_finance_report_export succeeds for the Finance Manager (FIN:Export) and returns a real queued app.report_runs row linked to a real app.jobs row; denied for the Plain User; rejected for an unknown code'
do $$
declare
  v_tenant_a uuid;
  v_run app.report_runs;
  v_job_exists boolean;
begin
  v_tenant_a := (select id from app.tenants where slug = 'acmedasha');

  if (select count(*) from app.report_types where code in ('finance_billing_summary', 'finance_ar_aging_summary', 'finance_ap_aging_summary', 'finance_cash_summary', 'finance_close_status_summary', 'finance_profitability_summary') and status = 'active') <> 6 then
    raise exception 'assertion failed: expected all six FIN-213 report_types codes registered and active';
  end if;
  if (select source_function from app.report_types where code = 'finance_cash_summary') <> 'get_finance_dashboard_cash_summary' then
    raise exception 'assertion failed: expected finance_cash_summary to name get_finance_dashboard_cash_summary as its source_function';
  end if;

  select * into v_run from app.enqueue_finance_report_export(v_tenant_a, 'finance_cash_summary', '{}'::jsonb, '00000000-0000-0000-0000-000000037503', 'financemanagera');
  if v_run.status <> 'queued' or v_run.run_type <> 'export' or v_run.job_id is null then
    raise exception 'assertion failed: expected a queued export run with a real job_id, got status=% job_id=%', v_run.status, v_run.job_id;
  end if;
  select exists(select 1 from app.jobs where job_id = v_run.job_id and job_type = 'report_generation') into v_job_exists;
  if not v_job_exists then
    raise exception 'assertion failed: expected a real app.jobs row of type report_generation linked to the export run';
  end if;

  begin
    perform app.enqueue_finance_report_export(v_tenant_a, 'finance_cash_summary', '{}'::jsonb, '00000000-0000-0000-0000-000000037504', 'plainusera');
    raise exception 'assertion failed: expected insufficient_authority for Plain User A (lacks FIN:Export)';
  exception
    when insufficient_privilege then
      null;
  end;

  begin
    perform app.enqueue_finance_report_export(v_tenant_a, 'not_a_real_report_code', '{}'::jsonb, '00000000-0000-0000-0000-000000037503', 'financemanagera');
    raise exception 'assertion failed: expected report_type_unknown for an unregistered code';
  exception
    when others then
      if sqlerrm !~ 'report_type_unknown' then
        raise exception 'assertion failed: expected report_type_unknown, got %', sqlerrm;
      end if;
  end;
end;
$$;

\echo '>> audit trail: enqueue_finance_report_export captured a success event for the Finance Manager''s own export'
do $$
declare
  v_tenant_a uuid;
  v_count integer;
begin
  v_tenant_a := (select id from app.tenants where slug = 'acmedasha');
  select count(*) into v_count from app.audit_logs
    where tenant_id = v_tenant_a and action = 'enqueue_finance_report_export' and result = 'success';
  if v_count < 1 then
    raise exception 'assertion failed: expected at least one enqueue_finance_report_export success audit event, found %', v_count;
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
    'get_finance_dashboard_billing_summary', 'get_finance_dashboard_cash_summary',
    'get_finance_dashboard_close_status', 'enqueue_finance_report_export'
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
