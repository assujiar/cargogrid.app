-- Real, executable integrated-verification evidence for FIN-215 (Finance
-- Integrated Verification, CG-S9-FIN-026) -- run via `pnpm run db:test` against a
-- real, disposable Postgres database, at the same checkpoint as every other
-- Finance db-test file.
--
-- Purpose (Prompt 215 §4/§21): detect cross-capability defects that each
-- capability's own isolated db-test cannot see, by driving ONE continuous,
-- realistic fixture through the full order-to-cash + source-to-GL critical flow
-- and cross-checking every downstream read (aging, cash, close/reconciliation,
-- profitability, billing) against independently-known-correct expected values --
-- never re-deriving what each capability's own db-test file already proves in
-- isolation (FIN-191..214, all independently `VERIFIED`, confirmed passing at
-- this same checkpoint).
--
-- Flow covered (order-to-cash + source-to-GL, mirrors OPS-185's own precedent
-- shape): accepted quote -> Job Order -> Shipment Order -> approved actual cost
-- -> billing readiness override/handoff -> invoice (draft -> submitted ->
-- approved -> issued, with a real PPN tax line) -> AR open item -> receipt
-- captured and PARTIALLY allocated (posts a real FIN-202 subledger batch:
-- debit cash_default, credit ar_control) -> bank statement imported and matched
-- to that receipt -> profitability calculated -> fiscal period locked ->
-- AR reconciliation run executed.
--
-- Disclosed scope boundary (not silently omitted): the procure-to-pay
-- (vendor bill/settlement/AP) flow is **not** driven through this fixture. Every
-- AP function (FIN-199/FIN-200/FIN-201) is already independently `VERIFIED` by
-- its own db-test file, and no capability built after AP (FIN-210's own AP
-- aging widget aside) reads AP data through a cross-capability path this
-- fixture would newly exercise -- unlike AR, which feeds the Dashboard's cash,
-- billing, close and profitability widgets simultaneously. This fixture instead
-- proves the AP aging widget reports an honest, non-fabricated *empty* result
-- for a tenant with zero AP activity (the same "no data, not a fabricated
-- figure" property FIN-213's own db-test already proved for a fresh tenant).
--
-- Outcome: zero production-code cross-capability defect found -- every real
-- integration point (AR-control-vs-open-item reconciliation, statement-vs-GL
-- cash matching, billing/aging reflecting a post-allocation remaining balance,
-- the Dashboard widgets reflecting the exact same figures the underlying
-- capability-level queries produce) held on the first fully-corrected run. Three
-- fixture-authoring defects were found and fixed before commit (never a
-- production-code change) -- full account in
-- `docs/build-log/phase-04/FIN-215.md` §3.1/§errors.

\set ON_ERROR_STOP on

\echo '>> setup: one tenant, a Full Pipeline Rep (COM/OPS/FIN incl. FIN:View margin), a Finance Manager (FIN:Create/Edit/Approve/Export/View + View margin, tenant_admin), a Plain User with no FIN grant, a second tenant (isolation only) with its own Finance Manager; chart of accounts (Cash, AR control, Revenue, Tax payable) with a published posting map (cash_default, ar_control, revenue_default, tax_payable_default); 8 open fiscal periods for tenant A'
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
  v_cash_account app.finance_accounts;
  v_ar_account app.finance_accounts;
  v_revenue_account app.finance_accounts;
  v_tax_account app.finance_accounts;
  v_pm_draft app.config_versions;
begin
  insert into auth.users (id, email) values
    ('00000000-0000-0000-0000-000000038501', 'admin@acmefinintega.test'),
    ('00000000-0000-0000-0000-000000038502', 'repa@acmefinintega.test'),
    ('00000000-0000-0000-0000-000000038503', 'financemanagera@acmefinintega.test'),
    ('00000000-0000-0000-0000-000000038504', 'plainusera@acmefinintega.test'),
    ('00000000-0000-0000-0000-000000038505', 'financemanagerb@acmefinintega.test'),
    ('00000000-0000-0000-0000-000000038506', 'adminb@acmefinintegb.test');

  perform app.provision_tenant('acmefinintega', 'Acme Finance Integration A', 'idem-acmefinintega', 'tester');
  v_tenant_a := (select id from app.tenants where slug = 'acmefinintega');
  perform app.transition_tenant_status(v_tenant_a, 'active', 'setup', 'tester');
  perform app.create_org_unit(v_tenant_a, 'company', null, 'ACMEFININTEGA-CO', 'Acme Finance Integration A', 'tester');
  v_team_a := (select id from app.org_units where tenant_id = v_tenant_a and code = 'ACMEFININTEGA-CO');

  perform app.provision_tenant('acmefinintegb', 'Acme Finance Integration B', 'idem-acmefinintegb', 'tester');
  v_tenant_b := (select id from app.tenants where slug = 'acmefinintegb');
  perform app.transition_tenant_status(v_tenant_b, 'active', 'setup', 'tester');
  perform app.create_org_unit(v_tenant_b, 'company', null, 'ACMEFININTEGB-CO', 'Acme Finance Integration B', 'tester');
  v_team_b := (select id from app.org_units where tenant_id = v_tenant_b and code = 'ACMEFININTEGB-CO');

  perform app.invite_user(v_tenant_a, '00000000-0000-0000-0000-000000038501', 'admin@acmefinintega.test', 'Admin A', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'admin@acmefinintega.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000038501', 'tenant_admin', v_tenant_a, null, 'tester');

  perform app.invite_user(v_tenant_a, '00000000-0000-0000-0000-000000038502', 'repa@acmefinintega.test', 'Rep A', v_team_a, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'repa@acmefinintega.test'), 'active', 'onboarded', 'tester');

  v_full_role := (app.create_role(v_tenant_a, 'Full Pipeline Rep', 'full COM/OPS/FIN access to build the fixture', 'tester')).id;
  v_full_draft := app.create_role_version(v_full_role, 'tester');
  perform app.set_role_version_permissions(
    v_full_draft.id,
    array(select id from app.permissions where (resource_module_code = 'COM' and action in ('Create', 'Edit', 'Approve', 'View', 'View selling price', 'View cost'))
      or (resource_module_code = 'OPS' and action in ('Create', 'Edit', 'Override', 'View', 'View cost'))
      or (resource_module_code = 'FIN' and action in ('Create', 'Edit', 'Approve', 'View', 'View margin'))),
    'tester'
  );
  perform app.publish_role_version(v_full_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant_a, (select id from app.role_versions where role_id = v_full_role and status = 'published'), '00000000-0000-0000-0000-000000038502', '00000000-0000-0000-0000-000000038501', 'tester');

  perform app.invite_user(v_tenant_a, '00000000-0000-0000-0000-000000038503', 'financemanagera@acmefinintega.test', 'Finance Manager A', v_team_a, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'financemanagera@acmefinintega.test'), 'active', 'onboarded', 'tester');
  v_fin_manager_role := (app.create_role(v_tenant_a, 'Finance Manager', 'integrated verification authority', 'tester')).id;
  v_fin_manager_draft := app.create_role_version(v_fin_manager_role, 'tester');
  perform app.set_role_version_permissions(v_fin_manager_draft.id, array(select id from app.permissions where resource_module_code = 'FIN' and action in ('Create', 'Edit', 'Approve', 'Export', 'View', 'View margin')), 'tester');
  perform app.publish_role_version(v_fin_manager_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant_a, (select id from app.role_versions where role_id = v_fin_manager_role and status = 'published'), '00000000-0000-0000-0000-000000038503', '00000000-0000-0000-0000-000000038501', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000038503', 'tenant_admin', v_tenant_a, null, 'tester');

  perform app.invite_user(v_tenant_a, '00000000-0000-0000-0000-000000038504', 'plainusera@acmefinintega.test', 'Plain User A', v_team_a, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'plainusera@acmefinintega.test'), 'active', 'onboarded', 'tester');

  perform app.invite_user(v_tenant_b, '00000000-0000-0000-0000-000000038506', 'adminb@acmefinintegb.test', 'Admin B', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'adminb@acmefinintegb.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000038506', 'tenant_admin', v_tenant_b, null, 'tester');

  perform app.invite_user(v_tenant_b, '00000000-0000-0000-0000-000000038505', 'financemanagerb@acmefinintega.test', 'Finance Manager B', v_team_b, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'financemanagerb@acmefinintega.test'), 'active', 'onboarded', 'tester');
  v_fin_manager2_role := (app.create_role(v_tenant_b, 'Finance Manager', 'isolation-check authority', 'tester')).id;
  v_fin_manager2_draft := app.create_role_version(v_fin_manager2_role, 'tester');
  perform app.set_role_version_permissions(v_fin_manager2_draft.id, array(select id from app.permissions where resource_module_code = 'FIN' and action in ('Create', 'Edit', 'Approve', 'View', 'View margin')), 'tester');
  perform app.publish_role_version(v_fin_manager2_draft.id, now(), 'tester');
  -- FIN-212's own precedent: a role version carrying a protected permission (FIN:View margin) cannot be self-assigned (app.assign_role's own self_escalation guard) -- a distinct Admin B actor performs the assignment.
  perform app.assign_role(v_tenant_b, (select id from app.role_versions where role_id = v_fin_manager2_role and status = 'published'), '00000000-0000-0000-0000-000000038505', '00000000-0000-0000-0000-000000038506', 'tester');

  perform app.generate_finance_fiscal_calendar(v_tenant_a, null, 'FY2026', 'FY2026 Monthly', '2026-01-01'::date, 8, '00000000-0000-0000-0000-000000038503', 'financemanagera');

  select * into v_cash_account from app.create_finance_account_draft(v_tenant_a, null, 'CASH-INTEGA', 'Cash', 'asset', 'debit', null, false, null, '00000000-0000-0000-0000-000000038503', 'financemanagera');
  perform app.activate_finance_account(v_cash_account.id, v_cash_account.record_version, '00000000-0000-0000-0000-000000038503', 'financemanagera');
  select * into v_ar_account from app.create_finance_account_draft(v_tenant_a, null, 'AR-INTEGA', 'Accounts Receivable', 'asset', 'debit', null, false, null, '00000000-0000-0000-0000-000000038503', 'financemanagera');
  perform app.activate_finance_account(v_ar_account.id, v_ar_account.record_version, '00000000-0000-0000-0000-000000038503', 'financemanagera');
  select * into v_revenue_account from app.create_finance_account_draft(v_tenant_a, null, 'REV-INTEGA', 'Freight Revenue', 'revenue', 'credit', null, false, null, '00000000-0000-0000-0000-000000038503', 'financemanagera');
  perform app.activate_finance_account(v_revenue_account.id, v_revenue_account.record_version, '00000000-0000-0000-0000-000000038503', 'financemanagera');
  select * into v_tax_account from app.create_finance_account_draft(v_tenant_a, null, 'TAX-INTEGA', 'PPN Payable', 'liability', 'credit', null, false, null, '00000000-0000-0000-0000-000000038503', 'financemanagera');
  perform app.activate_finance_account(v_tax_account.id, v_tax_account.record_version, '00000000-0000-0000-0000-000000038503', 'financemanagera');

  select * into v_pm_draft from app.create_finance_config_draft('finance_posting_map', v_tenant_a, 'tenant', null, '00000000-0000-0000-0000-000000038503', 'financemanagera');
  perform app.set_finance_config_items(v_pm_draft.id, jsonb_build_array(
    jsonb_build_object('key', 'cash_default', 'value', jsonb_build_object('accountCodeRef', 'CASH-INTEGA')),
    jsonb_build_object('key', 'ar_control', 'value', jsonb_build_object('accountCodeRef', 'AR-INTEGA')),
    jsonb_build_object('key', 'revenue_default', 'value', jsonb_build_object('accountCodeRef', 'REV-INTEGA')),
    jsonb_build_object('key', 'tax_payable_default', 'value', jsonb_build_object('accountCodeRef', 'TAX-INTEGA'))
  ), '00000000-0000-0000-0000-000000038503', 'financemanagera');
  perform app.publish_finance_config_version(v_pm_draft.id, '00000000-0000-0000-0000-000000038503', null, 'financemanagera');
end;
$$;

\echo '>> order-to-cash: lead -> prospect -> opportunity -> costing -> rate -> margin -> quotation -> acceptance -> account -> job order -> confirm -> shipment order -> approved actual cost (8,000,000 IDR) -> billing readiness override/handoff -> invoice (15,000,000 subtotal + PPN tax) -> submit -> approve -> issue (real AR open item + real GL: debit AR 16,650,000, credit revenue 15,000,000, credit tax payable 1,650,000)'
do $$
declare
  v_tenant_a uuid;
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
  v_job_handoff app.job_order_handoffs;
  v_job app.job_orders;
  v_shipment app.shipment_orders;
  v_cost app.shipment_actual_costs;
  v_evaluation app.billing_readiness_evaluations;
  v_handoff app.billing_readiness_handoffs;
  v_invoice app.finance_invoices;
  v_ppn_code_id uuid;
  v_tax_rule app.finance_tax_rule_versions;
begin
  v_tenant_a := (select id from app.tenants where slug = 'acmefinintega');
  v_team_a := (select id from app.org_units where tenant_id = v_tenant_a and code = 'ACMEFININTEGA-CO');

  -- FIN-195: one approved PPN tax rule for tenant A, covering today -- prepare_finance_invoice_from_readiness resolves the applicable rule as of the current date, not a caller-supplied one.
  v_ppn_code_id := (select id from app.finance_tax_codes where tenant_id is null and code = 'PPN');
  select * into v_tax_rule from app.create_finance_tax_rule_draft(v_tenant_a, v_ppn_code_id, 'percentage', 0.11, null, null, null, '2026-01-01'::date, null, '00000000-0000-0000-0000-000000038503', 'financemanagera');
  select * into v_tax_rule from app.attach_finance_tax_rule_evidence(v_tax_rule.id, v_tax_rule.record_version, null, 'fixture evidence note for FIN-215''s own integrated verification', '00000000-0000-0000-0000-000000038503', 'financemanagera');
  perform app.approve_finance_tax_rule(v_tax_rule.id, v_tax_rule.record_version, '00000000-0000-0000-0000-000000038503', 'financemanagera');

  perform app.capture_lead(v_tenant_a, 'manual', null, 'Integrated Verification Co', 'Jane Integrated', 'jane@finintegtest.test', '0811',
    '00000000-0000-0000-0000-000000038502', v_team_a, '00000000-0000-0000-0000-000000038502', 'tester');
  select * into v_lead from app.leads where email = 'jane@finintegtest.test';
  perform app.qualify_lead(v_lead.id, v_lead.record_version, '00000000-0000-0000-0000-000000038502', 'tester');
  select * into v_lead from app.leads where id = v_lead.id;
  perform app.convert_lead_to_prospect(v_lead.id, 'Integrated Verification Co', 'IVC', '66.666.666.7-780.000',
    jsonb_build_object('line1', 'Jl. Sudirman 1', 'city', 'Jakarta', 'country', 'ID'),
    '00000000-0000-0000-0000-000000038502', 'tester');
  select * into v_prospect from app.prospects where lead_id = v_lead.id;

  select * into v_contact from app.create_contact(v_tenant_a, 'Jane Integrated', 'Procurement Lead', 'jane@finintegtest.test', '0811', '00000000-0000-0000-0000-000000038502', v_team_a, '00000000-0000-0000-0000-000000038502', 'tester');
  perform app.link_contact_to_record(v_contact.id, 'prospect', v_prospect.id, 'primary', true, '00000000-0000-0000-0000-000000038502', 'tester');

  select * into v_opportunity from app.create_opportunity(
    v_tenant_a, v_prospect.id, 'Integrated verification lane',
    jsonb_build_object('service_type', 'ocean_freight', 'cargo_description', 'General cargo', 'origin', 'Jakarta', 'destination', 'Surabaya', 'target_ready_date', '2026-08-01'),
    '00000000-0000-0000-0000-000000038502', v_team_a, '00000000-0000-0000-0000-000000038502', 'tester'
  );
  select * into v_request from app.request_costing(v_opportunity.id, '[]'::jsonb, null, '00000000-0000-0000-0000-000000038502', 'tester');
  select * into v_rate from app.create_rate_version(
    v_tenant_a, 'VENDOR-FININTEG-1', 'Contoso Ocean Line', 'ocean_freight', 'FCL', 'Jakarta', 'Surabaya', '20ft',
    null, null, null, null, 'IDR', 8000000, null, '[]'::jsonb, now(), null, null, '00000000-0000-0000-0000-000000038501', 'tester'
  );
  perform app.approve_rate_version(v_rate.id, v_rate.record_version, '00000000-0000-0000-0000-000000038501', 'tester');
  select * into v_selection from app.select_vendor_rate(v_request.id, v_rate.id, false, null, null, null, '00000000-0000-0000-0000-000000038502', 'tester');

  select * into v_rule from app.create_margin_rule_version(v_tenant_a, 20.00, 'half_up', '00000000-0000-0000-0000-000000038502', 'tester');
  perform app.publish_margin_rule_version(v_rule.id, v_rule.record_version, null, '00000000-0000-0000-0000-000000038502', 'tester');
  perform app.calculate_margin(v_selection.id, 15000000, 'IDR', 0, '00000000-0000-0000-0000-000000038502', 'tester');
  select id into v_calc_id from app.margin_calculations where rate_selection_id = v_selection.id and is_current;

  select * into v_quote from app.create_quotation_draft(v_tenant_a, v_opportunity.id, 'IDR', now() + interval '14 days', v_contact.id, null, null, '00000000-0000-0000-0000-000000038502', 'tester');
  perform app.add_quotation_line(v_quote.id, v_quote.record_version, 'service', 'Ocean freight integrated verification lane', v_calc_id, 1, 15000000, 0, 0, '00000000-0000-0000-0000-000000038502', 'tester');
  select * into v_quote from app.quotations where id = v_quote.id;
  perform app.submit_quotation(v_quote.id, v_quote.record_version, '00000000-0000-0000-0000-000000038502', 'tester');
  select * into v_send from app.send_quotation_for_acceptance(v_quote.id, null, 'email', '00000000-0000-0000-0000-000000038502', 'tester');
  perform app.record_quotation_customer_decision(v_send.raw_token, 'accepted', 'Jane Integrated', null, null, null, null, null);

  select * into v_account from app.convert_quotation_to_account(v_quote.id, null, null, '00000000-0000-0000-0000-000000038502', 'rep');
  select * into v_job_handoff from app.prepare_job_order_handoff(v_quote.id, '00000000-0000-0000-0000-000000038502', 'rep');
  select * into v_job from app.prepare_job_order(v_job_handoff.id, '00000000-0000-0000-0000-000000038502', 'rep');
  select * into v_job from app.confirm_job_order(v_job.id, v_job.record_version, '00000000-0000-0000-0000-000000038502', 'rep');

  select * into v_shipment from app.create_shipment_order_from_job(
    v_job.id, 'fininteg-shipment-1', null, null, 'ocean_freight', 'sea', 'Jakarta', 'Surabaya',
    now() + interval '1 day', now() + interval '10 days', null, null, null, null, null, null, null,
    '00000000-0000-0000-0000-000000038502', 'rep'
  );

  select * into v_cost from app.create_actual_cost_draft(v_tenant_a, v_shipment.id, 'IDR', null, '00000000-0000-0000-0000-000000038502', 'rep');
  perform app.add_actual_cost_component(v_cost.id, 'freight', 'internal', null, null, null, 'Ocean freight', 1, 'shipment', 8000000, null, 0, 'fininteg-cost-freight-1', '00000000-0000-0000-0000-000000038502', 'rep');
  select * into v_cost from app.shipment_actual_costs where id = v_cost.id;
  v_cost := app.submit_actual_cost(v_cost.id, v_cost.record_version, '00000000-0000-0000-0000-000000038502', 'rep');
  perform app.decide_actual_cost(v_cost.id, 'approved', null, v_cost.record_version, '00000000-0000-0000-0000-000000038502', 'rep');

  select * into v_evaluation from app.evaluate_billing_readiness(v_job.id, null, '00000000-0000-0000-0000-000000038502', 'rep');
  select * into v_evaluation from app.override_billing_readiness(v_job.id, v_evaluation.record_version, 'fixture: FIN-215 integrated verification, bypassing full shipment/epod/document evidence chain, out of this checkpoint''s own scope', '00000000-0000-0000-0000-000000038502', 'rep');
  select * into v_handoff from app.handoff_billing_readiness(v_job.id, 'fininteg-billing-handoff-1', '00000000-0000-0000-0000-000000038502', 'rep');

  select * into v_invoice from app.prepare_finance_invoice_from_readiness(v_tenant_a, v_handoff.id, 30, 'PPN', '00000000-0000-0000-0000-000000038503', 'financemanagera');
  perform app.submit_finance_invoice_for_approval(v_invoice.id, v_invoice.record_version, '00000000-0000-0000-0000-000000038503', 'financemanagera');
  select * into v_invoice from app.finance_invoices where id = v_invoice.id;
  perform app.approve_finance_invoice(v_invoice.id, v_invoice.record_version, '00000000-0000-0000-0000-000000038503', 'financemanagera');
  select * into v_invoice from app.finance_invoices where id = v_invoice.id;
  perform app.issue_finance_invoice(v_invoice.id, v_invoice.record_version, '2026-07-10'::date, '00000000-0000-0000-0000-000000038503', 'financemanagera');
  select * into v_invoice from app.finance_invoices where id = v_invoice.id;

  if v_invoice.total_amount <> 16650000 then
    raise exception 'assertion failed: expected invoice total 16,650,000 (15,000,000 subtotal + 11%% PPN), got %', v_invoice.total_amount;
  end if;
end;
$$;

\echo '>> source-to-GL: a receipt is captured for half the invoice total and PARTIALLY allocated to the AR open item -- posts a real FIN-202 subledger batch (debit cash 8,325,000, credit AR control 8,325,000); the AR open item status moves to partial with a real remaining open_amount of 8,325,000, never a fabricated figure'
do $$
declare
  v_tenant_a uuid;
  v_invoice app.finance_invoices;
  v_open_item app.finance_ar_open_items;
  v_receipt app.finance_receipts;
begin
  v_tenant_a := (select id from app.tenants where slug = 'acmefinintega');
  select * into v_invoice from app.finance_invoices where tenant_id = v_tenant_a and status = 'issued';
  select * into v_open_item from app.finance_ar_open_items where id = v_invoice.ar_open_item_id;

  select * into v_receipt from app.capture_finance_receipt(
    v_tenant_a, null, v_invoice.customer_account_id, 'finteg-receipt-ref-1', '2026-07-15'::date, 'Jane Integrated', 'Acme Bank ****4321',
    'IDR', 8325000, 'finteg-receipt-idem-1', '00000000-0000-0000-0000-000000038503', 'financemanagera'
  );
  perform app.allocate_finance_receipt(
    v_receipt.id, 'finteg-allocate-idem-1',
    jsonb_build_array(jsonb_build_object('arOpenItemId', v_open_item.id, 'amount', 8325000)),
    '00000000-0000-0000-0000-000000038503', 'financemanagera'
  );

  select * into v_open_item from app.finance_ar_open_items where id = v_open_item.id;
  if v_open_item.status <> 'partial' or v_open_item.open_amount <> 8325000 then
    raise exception 'assertion failed: expected AR open item status=partial, open_amount=8,325,000, got status=% open_amount=%', v_open_item.status, v_open_item.open_amount;
  end if;
end;
$$;

\echo '>> cash: a bank account (linked to the same cash_default GL account) receives an imported statement line for the exact receipt amount, matched to the receipt -- app.get_finance_cash_position and app.get_finance_dashboard_cash_summary both report a real, non-zero, exactly-reconciled balance (statement=GL=8,325,000, variance=0), never a fabricated match'
do $$
declare
  v_tenant_a uuid;
  v_invoice app.finance_invoices;
  v_receipt app.finance_receipts;
  v_bank_account app.finance_bank_accounts;
  v_batch app.finance_bank_statement_batches;
  v_transaction app.finance_bank_transactions;
  v_position record;
  v_dash_row record;
begin
  v_tenant_a := (select id from app.tenants where slug = 'acmefinintega');
  select * into v_receipt from app.finance_receipts where tenant_id = v_tenant_a and idempotency_key = 'finteg-receipt-idem-1';

  select * into v_bank_account from app.create_finance_bank_account(v_tenant_a, null, 'Main Operating', 'Acme Bank', '4321', 'IDR', (select id from app.finance_accounts where tenant_id = v_tenant_a and code = 'CASH-INTEGA'), '00000000-0000-0000-0000-000000038503', 'financemanagera');
  select * into v_batch from app.import_finance_bank_statement(v_tenant_a, v_bank_account.id, 'finteg-stmt-1', jsonb_build_array(
    jsonb_build_object('transactionDate', '2026-07-15', 'direction', 'debit', 'amount', 8325000, 'reference', 'FINTEG-REF-1')
  ), '00000000-0000-0000-0000-000000038503', 'financemanagera');
  select * into v_transaction from app.finance_bank_transactions where bank_account_id = v_bank_account.id and reference = 'FINTEG-REF-1';
  perform app.match_finance_bank_transaction(v_transaction.id, v_transaction.record_version, 'receipt', v_receipt.id, '00000000-0000-0000-0000-000000038503', 'financemanagera');

  select * into v_position from app.get_finance_cash_position(v_tenant_a, v_bank_account.id, '2026-07-31'::date, '00000000-0000-0000-0000-000000038503');
  if v_position.statement_balance <> 8325000 or v_position.gl_balance <> 8325000 or v_position.variance_amount <> 0 then
    raise exception 'assertion failed: expected a real exactly-reconciled cash position (statement=gl=8,325,000, variance=0), got statement=% gl=% variance=%', v_position.statement_balance, v_position.gl_balance, v_position.variance_amount;
  end if;

  select * into v_dash_row from app.get_finance_dashboard_cash_summary(v_tenant_a, null, '2026-07-31'::date, '00000000-0000-0000-0000-000000038503');
  if v_dash_row.statement_balance <> 8325000 or v_dash_row.gl_balance <> 8325000 or v_dash_row.variance_amount <> 0 then
    raise exception 'assertion failed: Finance Dashboard cash widget does not reflect the same real reconciled position the underlying FIN-211 query reports -- statement=% gl=% variance=%', v_dash_row.statement_balance, v_dash_row.gl_balance, v_dash_row.variance_amount;
  end if;
end;
$$;

\echo '>> billing/aging cross-check: app.get_finance_dashboard_billing_summary reports the issued invoice''s own real REMAINING open_amount (8,325,000, post-partial-allocation), never the stale original total (16,650,000); app.get_finance_aging_summary (ar) shows the same 8,325,000 in the current bucket; app.get_finance_aging_summary (ap) is honestly empty for this tenant (disclosed scope boundary -- no AP activity was ever created)'
do $$
declare
  v_tenant_a uuid;
  v_billing_row record;
  v_aging_row record;
  v_ap_count integer;
begin
  v_tenant_a := (select id from app.tenants where slug = 'acmefinintega');

  select * into v_billing_row from app.get_finance_dashboard_billing_summary(v_tenant_a, null, '00000000-0000-0000-0000-000000038503') where status = 'issued';
  if v_billing_row.open_amount <> 8325000 then
    raise exception 'assertion failed: Finance Dashboard billing widget reports open_amount=%, expected the real post-allocation remaining balance 8,325,000 (not the stale full invoice total)', v_billing_row.open_amount;
  end if;

  select * into v_aging_row from app.get_finance_aging_summary(v_tenant_a, null, 'ar', '2026-07-31'::date, true, '00000000-0000-0000-0000-000000038503') where bucket_label = 'current';
  if v_aging_row.open_amount <> 8325000 then
    raise exception 'assertion failed: AR aging summary current bucket reports %, expected the same real remaining balance 8,325,000 as the billing widget above (cross-capability consistency)', v_aging_row.open_amount;
  end if;

  select count(*) into v_ap_count from app.get_finance_aging_summary(v_tenant_a, null, 'ap', '2026-07-31'::date, true, '00000000-0000-0000-0000-000000038503');
  if v_ap_count <> 0 then
    raise exception 'assertion failed: expected zero AP aging rows for a tenant with no AP activity (honest empty, never fabricated), got %', v_ap_count;
  end if;
end;
$$;

\echo '>> profitability and close/reconciliation cross-check: app.calculate_finance_job_profitability reports revenue 15,000,000 (billed subtotal, excluding the 1,650,000 tax) minus approved cost 8,000,000 = profit 7,000,000, margin 46.6667%%, and the Dashboard profitability widget reflects the identical fact; the invoice''s own posting period is locked (FIN-207) and the AR reconciliation run (FIN-209) reports is_within_tolerance=true (the real posted AR-control subledger balance -- net of the partial allocation -- exactly matches the real remaining AR open-item total)'
do $$
declare
  v_tenant_a uuid;
  v_job app.job_orders;
  v_fact app.finance_job_profitability_facts;
  v_dash_row record;
  v_period record;
  v_lock app.finance_period_locks;
  v_recon app.finance_reconciliation_runs;
  v_close_row record;
begin
  v_tenant_a := (select id from app.tenants where slug = 'acmefinintega');
  select * into v_job from app.job_orders where tenant_id = v_tenant_a;

  select * into v_fact from app.calculate_finance_job_profitability(v_job.id, null, '00000000-0000-0000-0000-000000038503', 'financemanagera');
  if v_fact.status <> 'calculated' or v_fact.revenue_amount <> 15000000 or v_fact.cost_amount <> 8000000 or v_fact.profit_amount <> 7000000 or v_fact.margin_percent <> 46.6667 then
    raise exception 'assertion failed: expected a real calculated fact (revenue=15,000,000 cost=8,000,000 profit=7,000,000 margin=46.6667%%), got status=% revenue=% cost=% profit=% margin=%', v_fact.status, v_fact.revenue_amount, v_fact.cost_amount, v_fact.profit_amount, v_fact.margin_percent;
  end if;

  select * into v_dash_row from app.get_finance_profitability_summary(v_tenant_a, 'customer', '00000000-0000-0000-0000-000000038503');
  if v_dash_row.profit_amount <> 7000000 then
    raise exception 'assertion failed: Finance Dashboard profitability widget reports profit_amount=%, expected the same real 7,000,000 the direct calculation above just produced', v_dash_row.profit_amount;
  end if;

  select * into v_period from app.resolve_finance_period_for_date(v_tenant_a, null, '2026-07-10'::date);
  select * into v_lock from app.lock_finance_period(v_tenant_a, null, v_period.period_id, 'ar', 'fixture: FIN-215 integrated verification close/reconciliation evidence', null, '00000000-0000-0000-0000-000000038503', 'financemanagera');
  select * into v_recon from app.execute_finance_reconciliation_run(v_tenant_a, null, 'ar', '2026-07-31'::date, 0, '00000000-0000-0000-0000-000000038503', 'financemanagera');
  if v_recon.is_within_tolerance <> true then
    raise exception 'assertion failed: expected the real AR-control-vs-open-item reconciliation to be within tolerance (control_total=% source_total=%) after the real partial allocation''s own GL credit', v_recon.control_total, v_recon.source_total;
  end if;

  select * into v_close_row from app.get_finance_dashboard_close_status(v_tenant_a, null, '00000000-0000-0000-0000-000000038503') where period_id = v_period.period_id;
  if v_close_row.lock_status <> 'locked' or v_close_row.reconciliation_status <> 'completed' or v_close_row.reconciliation_within_tolerance <> true then
    raise exception 'assertion failed: Finance Dashboard close/reconciliation widget does not reflect the real lock/reconciliation state just established -- lock_status=% reconciliation_status=% within_tolerance=%', v_close_row.lock_status, v_close_row.reconciliation_status, v_close_row.reconciliation_within_tolerance;
  end if;
end;
$$;

\echo '>> cross-tenant isolation: Finance Manager B (tenant B, zero Finance activity of its own) reads zero rows from every dashboard widget above for tenant B''s own scope -- never tenant A''s real data'
do $$
declare
  v_tenant_b uuid;
  v_count integer;
begin
  v_tenant_b := (select id from app.tenants where slug = 'acmefinintegb');

  select count(*) into v_count from app.get_finance_dashboard_billing_summary(v_tenant_b, null, '00000000-0000-0000-0000-000000038505');
  if v_count <> 0 then
    raise exception 'assertion failed: expected zero billing rows for tenant B, got %', v_count;
  end if;

  select count(*) into v_count from app.get_finance_dashboard_cash_summary(v_tenant_b, null, '2026-07-31'::date, '00000000-0000-0000-0000-000000038505');
  if v_count <> 0 then
    raise exception 'assertion failed: expected zero cash rows for tenant B, got %', v_count;
  end if;

  select count(*) into v_count from app.get_finance_profitability_summary(v_tenant_b, 'customer', '00000000-0000-0000-0000-000000038505');
  if v_count <> 0 then
    raise exception 'assertion failed: expected zero profitability rows for tenant B, got %', v_count;
  end if;
end;
$$;

\echo 'ALL FIN-215 (Finance Integrated Verification) assertions passed.'
