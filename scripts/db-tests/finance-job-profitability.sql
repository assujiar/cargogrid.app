-- Real, executable test evidence for FIN-212 (Job, Customer and Service
-- Profitability, CG-S9-FIN-023) -- run via `pnpm run db:test` against a real,
-- disposable Postgres database.
-- Proves: billed-revenue (FIN-197 issued invoices) minus approved actual cost
-- (OPS-178) reconciles to an exact profit/margin; blocked_reason surfaces for
-- no_billed_revenue/no_approved_cost/mixed_currency rather than a fabricated
-- figure; recalculation requires a reason; FIN:Edit + FIN:View margin gate
-- calculation and FIN:View margin alone gates every read (deny outright, no
-- partial result); customer/branch/service aggregation sums only calculated
-- facts and excludes a blocked one; cross-tenant isolation; schema-privilege
-- defense in depth; audit trail.

\set ON_ERROR_STOP on

\echo '>> setup: one tenant, a Full Pipeline Rep (COM/OPS/FIN incl. OPS:View cost/View margin), a Finance Manager (FIN:Create/Edit/Approve/View + FIN:View margin), a Finance Editor (FIN:Edit/View only, no View margin, no Approve), a Plain User with no FIN grant, a second tenant with its own Finance Manager, and six open fiscal periods for tenant A'
do $$
declare
  v_tenant1 uuid;
  v_tenant2 uuid;
  v_team_a uuid;
  v_team_b uuid;
  v_branch_x uuid;
  v_branch_y uuid;
  v_full_role uuid;
  v_full_draft app.role_versions;
  v_fin_manager_role uuid;
  v_fin_manager_draft app.role_versions;
  v_fin_editor_role uuid;
  v_fin_editor_draft app.role_versions;
  v_fin_manager2_role uuid;
  v_fin_manager2_draft app.role_versions;
begin
  insert into auth.users (id, email) values
    ('00000000-0000-0000-0000-000000037001', 'admin@acmeprofita.test'),
    ('00000000-0000-0000-0000-000000037002', 'repa@acmeprofita.test'),
    ('00000000-0000-0000-0000-000000037003', 'financemanagera@acmeprofita.test'),
    ('00000000-0000-0000-0000-000000037004', 'financeeditora@acmeprofita.test'),
    ('00000000-0000-0000-0000-000000037005', 'plainusera@acmeprofita.test'),
    ('00000000-0000-0000-0000-000000037006', 'financemanagerb@acmeprofita.test'),
    ('00000000-0000-0000-0000-000000037007', 'adminb@acmeprofita.test');

  perform app.provision_tenant('acmeprofita', 'Acme Profitability A', 'idem-acmeprofita', 'tester');
  v_tenant1 := (select id from app.tenants where slug = 'acmeprofita');
  perform app.transition_tenant_status(v_tenant1, 'active', 'setup', 'tester');
  perform app.create_org_unit(v_tenant1, 'company', null, 'ACMEPROFITA-CO', 'Acme Profitability A', 'tester');
  v_team_a := (select id from app.org_units where tenant_id = v_tenant1 and code = 'ACMEPROFITA-CO');
  perform app.create_org_unit(v_tenant1, 'branch', v_team_a, 'ACMEPROFITA-BRX', 'Branch X', 'tester');
  v_branch_x := (select id from app.org_units where tenant_id = v_tenant1 and code = 'ACMEPROFITA-BRX');
  perform app.create_org_unit(v_tenant1, 'branch', v_team_a, 'ACMEPROFITA-BRY', 'Branch Y', 'tester');
  v_branch_y := (select id from app.org_units where tenant_id = v_tenant1 and code = 'ACMEPROFITA-BRY');

  perform app.provision_tenant('acmeprofitb', 'Acme Profitability B', 'idem-acmeprofitb', 'tester');
  v_tenant2 := (select id from app.tenants where slug = 'acmeprofitb');
  perform app.transition_tenant_status(v_tenant2, 'active', 'setup', 'tester');
  perform app.create_org_unit(v_tenant2, 'company', null, 'ACMEPROFITB-CO', 'Acme Profitability B', 'tester');
  v_team_b := (select id from app.org_units where tenant_id = v_tenant2 and code = 'ACMEPROFITB-CO');

  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000037001', 'admin@acmeprofita.test', 'Admin A', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'admin@acmeprofita.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000037001', 'tenant_admin', v_tenant1, null, 'tester');

  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000037002', 'repa@acmeprofita.test', 'Rep A', v_team_a, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'repa@acmeprofita.test'), 'active', 'onboarded', 'tester');

  v_full_role := (app.create_role(v_tenant1, 'Full Pipeline Rep', 'full COM/OPS/FIN access to build the fixture', 'tester')).id;
  v_full_draft := app.create_role_version(v_full_role, 'tester');
  perform app.set_role_version_permissions(
    v_full_draft.id,
    array(select id from app.permissions where (resource_module_code = 'COM' and action in ('Create', 'Edit', 'Approve', 'View', 'View selling price', 'View cost'))
      or (resource_module_code = 'OPS' and action in ('Create', 'Edit', 'Override', 'View', 'View cost', 'View margin'))
      or (resource_module_code = 'FIN' and action in ('Create', 'Edit', 'Approve', 'View'))),
    'tester'
  );
  perform app.publish_role_version(v_full_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_full_role and status = 'published'), '00000000-0000-0000-0000-000000037002', '00000000-0000-0000-0000-000000037001', 'tester');

  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000037003', 'financemanagera@acmeprofita.test', 'Finance Manager A', v_team_a, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'financemanagera@acmeprofita.test'), 'active', 'onboarded', 'tester');
  v_fin_manager_role := (app.create_role(v_tenant1, 'Finance Manager', 'profitability authority', 'tester')).id;
  v_fin_manager_draft := app.create_role_version(v_fin_manager_role, 'tester');
  perform app.set_role_version_permissions(v_fin_manager_draft.id, array(select id from app.permissions where resource_module_code = 'FIN' and action in ('Create', 'Edit', 'Approve', 'View', 'View margin')), 'tester');
  perform app.publish_role_version(v_fin_manager_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_fin_manager_role and status = 'published'), '00000000-0000-0000-0000-000000037003', '00000000-0000-0000-0000-000000037001', 'tester');

  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000037004', 'financeeditora@acmeprofita.test', 'Finance Editor A', v_team_a, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'financeeditora@acmeprofita.test'), 'active', 'onboarded', 'tester');
  v_fin_editor_role := (app.create_role(v_tenant1, 'Finance Editor', 'edit only, no approve, no view margin', 'tester')).id;
  v_fin_editor_draft := app.create_role_version(v_fin_editor_role, 'tester');
  perform app.set_role_version_permissions(v_fin_editor_draft.id, array(select id from app.permissions where resource_module_code = 'FIN' and action in ('Edit', 'View')), 'tester');
  perform app.publish_role_version(v_fin_editor_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_fin_editor_role and status = 'published'), '00000000-0000-0000-0000-000000037004', '00000000-0000-0000-0000-000000037001', 'tester');

  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000037005', 'plainusera@acmeprofita.test', 'Plain User A', v_team_a, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'plainusera@acmeprofita.test'), 'active', 'onboarded', 'tester');

  perform app.invite_user(v_tenant2, '00000000-0000-0000-0000-000000037007', 'adminb@acmeprofita.test', 'Admin B', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'adminb@acmeprofita.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000037007', 'tenant_admin', v_tenant2, null, 'tester');

  perform app.invite_user(v_tenant2, '00000000-0000-0000-0000-000000037006', 'financemanagerb@acmeprofita.test', 'Finance Manager B', v_team_b, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'financemanagerb@acmeprofita.test'), 'active', 'onboarded', 'tester');
  v_fin_manager2_role := (app.create_role(v_tenant2, 'Finance Manager', 'profitability authority', 'tester')).id;
  v_fin_manager2_draft := app.create_role_version(v_fin_manager2_role, 'tester');
  perform app.set_role_version_permissions(v_fin_manager2_draft.id, array(select id from app.permissions where resource_module_code = 'FIN' and action in ('Create', 'Edit', 'Approve', 'View', 'View margin')), 'tester');
  perform app.publish_role_version(v_fin_manager2_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant2, (select id from app.role_versions where role_id = v_fin_manager2_role and status = 'published'), '00000000-0000-0000-0000-000000037006', '00000000-0000-0000-0000-000000037007', 'tester');

  perform app.generate_finance_fiscal_calendar(v_tenant1, null, 'FY2026', 'FY2026 Monthly', '2026-01-01'::date, 6, '00000000-0000-0000-0000-000000037003', 'financemanagera');
end;
$$;

\echo '>> FIN-202 fixture prerequisite: a published finance_posting_map so app.issue_finance_invoice''s own subledger effect can resolve real accounts (ar_control, revenue_default)'
do $$
declare
  v_tenant1 uuid;
  v_account app.finance_accounts;
  v_pm_draft app.config_versions;
begin
  v_tenant1 := (select id from app.tenants where slug = 'acmeprofita');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000037003', 'tenant_admin', v_tenant1, null, 'tester');

  select * into v_account from app.create_finance_account_draft(v_tenant1, null, 'AR-CTRL', 'Accounts Receivable Control', 'asset', 'debit', null, false, null, '00000000-0000-0000-0000-000000037003', 'financemanagera');
  perform app.activate_finance_account(v_account.id, v_account.record_version, '00000000-0000-0000-0000-000000037003', 'financemanagera');
  select * into v_account from app.create_finance_account_draft(v_tenant1, null, 'REV-DEFAULT', 'Default Revenue', 'revenue', 'credit', null, false, null, '00000000-0000-0000-0000-000000037003', 'financemanagera');
  perform app.activate_finance_account(v_account.id, v_account.record_version, '00000000-0000-0000-0000-000000037003', 'financemanagera');
  select * into v_account from app.create_finance_account_draft(v_tenant1, null, 'TAX-PAYABLE-DEFAULT', 'Default Tax Payable', 'liability', 'credit', null, false, null, '00000000-0000-0000-0000-000000037003', 'financemanagera');
  perform app.activate_finance_account(v_account.id, v_account.record_version, '00000000-0000-0000-0000-000000037003', 'financemanagera');

  select * into v_pm_draft from app.create_finance_config_draft('finance_posting_map', v_tenant1, 'tenant', null, '00000000-0000-0000-0000-000000037003', 'financemanagera');
  perform app.set_finance_config_items(v_pm_draft.id, jsonb_build_array(
    jsonb_build_object('key', 'ar_control', 'value', jsonb_build_object('accountCodeRef', 'AR-CTRL')),
    jsonb_build_object('key', 'revenue_default', 'value', jsonb_build_object('accountCodeRef', 'REV-DEFAULT')),
    jsonb_build_object('key', 'tax_payable_default', 'value', jsonb_build_object('accountCodeRef', 'TAX-PAYABLE-DEFAULT'))
  ), '00000000-0000-0000-0000-000000037003', 'financemanagera');
  perform app.publish_finance_config_version(v_pm_draft.id, '00000000-0000-0000-0000-000000037003', null, 'financemanagera');
end;
$$;

\echo '>> fixture: one prospect/account (Customer One), two Job Orders (Branch X / ocean_freight) each with an issued invoice and an approved IDR actual cost -- the shared-dimension pair the summary aggregation test will sum'
do $$
declare
  v_tenant1 uuid;
  v_branch_x uuid;
  v_lead app.leads;
  v_prospect app.prospects;
  v_contact app.contacts;
  v_spec record;
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
  v_br_handoff app.billing_readiness_handoffs;
  v_invoice app.finance_invoices;
  v_shipment app.shipment_orders;
  v_cost app.shipment_actual_costs;
begin
  v_tenant1 := (select id from app.tenants where slug = 'acmeprofita');
  v_branch_x := (select id from app.org_units where tenant_id = v_tenant1 and code = 'ACMEPROFITA-BRX');

  perform app.capture_lead(v_tenant1, 'manual', null, 'Customer One Logistics', 'Jane One', 'jane@custone.test', '0811',
    '00000000-0000-0000-0000-000000037002', v_branch_x, '00000000-0000-0000-0000-000000037002', 'tester');
  select * into v_lead from app.leads where email = 'jane@custone.test';
  perform app.qualify_lead(v_lead.id, v_lead.record_version, '00000000-0000-0000-0000-000000037002', 'tester');
  select * into v_lead from app.leads where id = v_lead.id;
  perform app.convert_lead_to_prospect(v_lead.id, 'Customer One Logistics', 'C1L', '11.111.111.1-111.000',
    jsonb_build_object('line1', 'Jl. Thamrin 1', 'city', 'Jakarta', 'country', 'ID'),
    '00000000-0000-0000-0000-000000037002', 'tester');
  select * into v_prospect from app.prospects where lead_id = v_lead.id;

  select * into v_contact from app.create_contact(v_tenant1, 'Jane One', 'Procurement Lead', 'jane@custone.test', '0811', '00000000-0000-0000-0000-000000037002', v_branch_x, '00000000-0000-0000-0000-000000037002', 'tester');
  perform app.link_contact_to_record(v_contact.id, 'prospect', v_prospect.id, 'primary', true, '00000000-0000-0000-0000-000000037002', 'tester');

  select * into v_rule from app.create_margin_rule_version(v_tenant1, 20.00, 'half_up', '00000000-0000-0000-0000-000000037002', 'tester');
  perform app.publish_margin_rule_version(v_rule.id, v_rule.record_version, null, '00000000-0000-0000-0000-000000037002', 'tester');

  for v_spec in
    select * from (values
      (1, 'idem-profit-job1', 'ocean-a1', 15000000::numeric, 8000000::numeric, 1000000::numeric),
      (2, 'idem-profit-job3', 'ocean-a3', 10000000::numeric, 5000000::numeric, 1000000::numeric)
    ) as t(seq, quote_idem, shipment_idem, revenue, freight_cost, handling_cost)
  loop
    select * into v_opportunity from app.create_opportunity(
      v_tenant1, v_prospect.id, 'Customer One lane ' || v_spec.seq,
      jsonb_build_object('service_type', 'ocean_freight', 'cargo_description', 'General cargo', 'origin', 'Jakarta', 'destination', 'Surabaya', 'target_ready_date', '2026-08-01'),
      '00000000-0000-0000-0000-000000037002', v_branch_x, '00000000-0000-0000-0000-000000037002', 'tester'
    );
    select * into v_request from app.request_costing(v_opportunity.id, '[]'::jsonb, null, '00000000-0000-0000-0000-000000037002', 'tester');
    select * into v_rate from app.create_rate_version(
      v_tenant1, 'VENDOR-PROFIT-' || v_spec.seq, 'Contoso Ocean Line', 'ocean_freight', 'FCL', 'Jakarta', 'Surabaya', '20ft',
      null, null, null, null, 'IDR', v_spec.freight_cost, null, '[]'::jsonb, now(), null, null, '00000000-0000-0000-0000-000000037001', 'tester'
    );
    perform app.approve_rate_version(v_rate.id, v_rate.record_version, '00000000-0000-0000-0000-000000037001', 'tester');
    select * into v_selection from app.select_vendor_rate(v_request.id, v_rate.id, false, null, null, null, '00000000-0000-0000-0000-000000037002', 'tester');

    perform app.calculate_margin(v_selection.id, v_spec.revenue, 'IDR', 0, '00000000-0000-0000-0000-000000037002', 'tester');
    select id into v_calc_id from app.margin_calculations where rate_selection_id = v_selection.id and is_current;

    select * into v_quote from app.create_quotation_draft(v_tenant1, v_opportunity.id, 'IDR', now() + interval '14 days', v_contact.id, null, null, '00000000-0000-0000-0000-000000037002', 'tester');
    perform app.add_quotation_line(v_quote.id, v_quote.record_version, 'service', 'Ocean freight lane ' || v_spec.seq, v_calc_id, 1, v_spec.revenue, 0, 0, '00000000-0000-0000-0000-000000037002', 'tester');
    select * into v_quote from app.quotations where id = v_quote.id;
    perform app.submit_quotation(v_quote.id, v_quote.record_version, '00000000-0000-0000-0000-000000037002', 'tester');
    select * into v_send from app.send_quotation_for_acceptance(v_quote.id, null, 'email', '00000000-0000-0000-0000-000000037002', 'tester');
    perform app.record_quotation_customer_decision(v_send.raw_token, 'accepted', 'Jane One', null, null, null, null, null);

    select * into v_account from app.convert_quotation_to_account(v_quote.id, null, null, '00000000-0000-0000-0000-000000037002', 'rep');
    select * into v_handoff from app.prepare_job_order_handoff(v_quote.id, '00000000-0000-0000-0000-000000037002', 'rep');
    select * into v_job from app.prepare_job_order(v_handoff.id, '00000000-0000-0000-0000-000000037002', 'rep');
    select * into v_job from app.confirm_job_order(v_job.id, v_job.record_version, '00000000-0000-0000-0000-000000037002', 'rep');

    select * into v_shipment from app.create_shipment_order_from_job(
      v_job.id, v_spec.shipment_idem, null, null, 'ocean_freight', 'sea', 'Jakarta', 'Surabaya',
      now() + interval '1 day', now() + interval '10 days', null, null, null, null, null, null, null,
      '00000000-0000-0000-0000-000000037002', 'rep'
    );

    select * into v_cost from app.create_actual_cost_draft(v_tenant1, v_shipment.id, 'IDR', null, '00000000-0000-0000-0000-000000037002', 'rep');
    perform app.add_actual_cost_component(v_cost.id, 'freight', 'internal', null, null, null, 'Ocean freight', 1, 'shipment', v_spec.freight_cost, null, 0, 'idem-profit-cost-freight-' || v_spec.seq, '00000000-0000-0000-0000-000000037002', 'rep');
    perform app.add_actual_cost_component(v_cost.id, 'handling', 'internal', null, null, null, 'Warehouse handling', 5, 'ton', v_spec.handling_cost / 5, null, 0, 'idem-profit-cost-handling-' || v_spec.seq, '00000000-0000-0000-0000-000000037002', 'rep');
    select * into v_cost from app.shipment_actual_costs where id = v_cost.id;
    v_cost := app.submit_actual_cost(v_cost.id, v_cost.record_version, '00000000-0000-0000-0000-000000037002', 'rep');
    perform app.decide_actual_cost(v_cost.id, 'approved', null, v_cost.record_version, '00000000-0000-0000-0000-000000037002', 'rep');

    select * into v_evaluation from app.evaluate_billing_readiness(v_job.id, null, '00000000-0000-0000-0000-000000037002', 'rep');
    select * into v_evaluation from app.override_billing_readiness(v_job.id, v_evaluation.record_version, 'fixture: bypassing full evidence chain, out of FIN-212''s own test scope', '00000000-0000-0000-0000-000000037002', 'rep');
    select * into v_br_handoff from app.handoff_billing_readiness(v_job.id, 'profit-fixture-handoff-' || v_spec.seq, '00000000-0000-0000-0000-000000037002', 'rep');

    select * into v_invoice from app.prepare_finance_invoice_from_readiness(v_tenant1, v_br_handoff.id, 30, null, '00000000-0000-0000-0000-000000037003', 'financemanagera');
    select * into v_invoice from app.submit_finance_invoice_for_approval(v_invoice.id, v_invoice.record_version, '00000000-0000-0000-0000-000000037003', 'financemanagera');
    select * into v_invoice from app.approve_finance_invoice(v_invoice.id, v_invoice.record_version, '00000000-0000-0000-0000-000000037003', 'financemanagera');
    perform app.issue_finance_invoice(v_invoice.id, v_invoice.record_version, '2026-03-01'::date, '00000000-0000-0000-0000-000000037003', 'financemanagera');
  end loop;
end;
$$;

\echo '>> fixture: a second, distinct customer/branch/service Job Order (Customer Two, Branch Y, air_freight) progressed through three states to exercise every blocked_reason: no_billed_revenue (no invoice yet), no_approved_cost (invoice issued, cost still submitted), and mixed_currency (cost approved but recorded in USD against an IDR invoice) -- deliberately left blocked, proving the summary aggregation excludes it'
do $$
declare
  v_tenant1 uuid;
  v_branch_y uuid;
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
  v_br_handoff app.billing_readiness_handoffs;
  v_invoice app.finance_invoices;
  v_shipment app.shipment_orders;
  v_cost app.shipment_actual_costs;
  v_fact app.finance_job_profitability_facts;
begin
  v_tenant1 := (select id from app.tenants where slug = 'acmeprofita');
  v_branch_y := (select id from app.org_units where tenant_id = v_tenant1 and code = 'ACMEPROFITA-BRY');

  perform app.capture_lead(v_tenant1, 'manual', null, 'Customer Two Freight', 'Jill Two', 'jill@custtwo.test', '0812',
    '00000000-0000-0000-0000-000000037002', v_branch_y, '00000000-0000-0000-0000-000000037002', 'tester');
  select * into v_lead from app.leads where email = 'jill@custtwo.test';
  perform app.qualify_lead(v_lead.id, v_lead.record_version, '00000000-0000-0000-0000-000000037002', 'tester');
  select * into v_lead from app.leads where id = v_lead.id;
  perform app.convert_lead_to_prospect(v_lead.id, 'Customer Two Freight', 'C2F', '22.222.222.2-222.000',
    jsonb_build_object('line1', 'Jl. Gatot Subroto 2', 'city', 'Jakarta', 'country', 'ID'),
    '00000000-0000-0000-0000-000000037002', 'tester');
  select * into v_prospect from app.prospects where lead_id = v_lead.id;

  select * into v_contact from app.create_contact(v_tenant1, 'Jill Two', 'Procurement Lead', 'jill@custtwo.test', '0812', '00000000-0000-0000-0000-000000037002', v_branch_y, '00000000-0000-0000-0000-000000037002', 'tester');
  perform app.link_contact_to_record(v_contact.id, 'prospect', v_prospect.id, 'primary', true, '00000000-0000-0000-0000-000000037002', 'tester');

  select * into v_opportunity from app.create_opportunity(
    v_tenant1, v_prospect.id, 'Customer Two lane',
    jsonb_build_object('service_type', 'air_freight', 'cargo_description', 'Express cargo', 'origin', 'Jakarta', 'destination', 'Singapore', 'target_ready_date', '2026-08-01'),
    '00000000-0000-0000-0000-000000037002', v_branch_y, '00000000-0000-0000-0000-000000037002', 'tester'
  );
  select * into v_request from app.request_costing(v_opportunity.id, '[]'::jsonb, null, '00000000-0000-0000-0000-000000037002', 'tester');
  select * into v_rate from app.create_rate_version(
    v_tenant1, 'VENDOR-PROFIT-2', 'Contoso Air Line', 'air_freight', 'FCL', 'Jakarta', 'Singapore', null,
    null, null, null, null, 'IDR', 4000000, null, '[]'::jsonb, now(), null, null, '00000000-0000-0000-0000-000000037001', 'tester'
  );
  perform app.approve_rate_version(v_rate.id, v_rate.record_version, '00000000-0000-0000-0000-000000037001', 'tester');
  select * into v_selection from app.select_vendor_rate(v_request.id, v_rate.id, false, null, null, null, '00000000-0000-0000-0000-000000037002', 'tester');

  perform app.calculate_margin(v_selection.id, 8000000, 'IDR', 0, '00000000-0000-0000-0000-000000037002', 'tester');
  select id into v_calc_id from app.margin_calculations where rate_selection_id = v_selection.id and is_current;

  select * into v_quote from app.create_quotation_draft(v_tenant1, v_opportunity.id, 'IDR', now() + interval '14 days', v_contact.id, null, null, '00000000-0000-0000-0000-000000037002', 'tester');
  perform app.add_quotation_line(v_quote.id, v_quote.record_version, 'service', 'Air freight lane', v_calc_id, 1, 8000000, 0, 0, '00000000-0000-0000-0000-000000037002', 'tester');
  select * into v_quote from app.quotations where id = v_quote.id;
  perform app.submit_quotation(v_quote.id, v_quote.record_version, '00000000-0000-0000-0000-000000037002', 'tester');
  select * into v_send from app.send_quotation_for_acceptance(v_quote.id, null, 'email', '00000000-0000-0000-0000-000000037002', 'tester');
  perform app.record_quotation_customer_decision(v_send.raw_token, 'accepted', 'Jill Two', null, null, null, null, null);

  select * into v_account from app.convert_quotation_to_account(v_quote.id, null, null, '00000000-0000-0000-0000-000000037002', 'rep');
  select * into v_handoff from app.prepare_job_order_handoff(v_quote.id, '00000000-0000-0000-0000-000000037002', 'rep');
  select * into v_job from app.prepare_job_order(v_handoff.id, '00000000-0000-0000-0000-000000037002', 'rep');
  select * into v_job from app.confirm_job_order(v_job.id, v_job.record_version, '00000000-0000-0000-0000-000000037002', 'rep');

  select * into v_shipment from app.create_shipment_order_from_job(
    v_job.id, 'idem-profit-job2', null, null, 'air_freight', 'air', 'Jakarta', 'Singapore',
    now() + interval '1 day', now() + interval '3 days', null, null, null, null, null, null, null,
    '00000000-0000-0000-0000-000000037002', 'rep'
  );

  -- Stage 1: neither invoice nor approved cost exists yet -- calculate must
  -- report no_billed_revenue (revenue is resolved first).
  v_fact := app.calculate_finance_job_profitability(v_job.id, null, '00000000-0000-0000-0000-000000037003', 'financemanagera');
  if v_fact.status <> 'unavailable' or v_fact.blocked_reason <> 'no_billed_revenue' then
    raise exception 'assertion failed: expected status=unavailable blocked_reason=no_billed_revenue with no invoice issued yet, got status=% blocked_reason=%', v_fact.status, v_fact.blocked_reason;
  end if;

  select * into v_evaluation from app.evaluate_billing_readiness(v_job.id, null, '00000000-0000-0000-0000-000000037002', 'rep');
  select * into v_evaluation from app.override_billing_readiness(v_job.id, v_evaluation.record_version, 'fixture: bypassing full evidence chain, out of FIN-212''s own test scope', '00000000-0000-0000-0000-000000037002', 'rep');
  select * into v_br_handoff from app.handoff_billing_readiness(v_job.id, 'profit-fixture-handoff-2', '00000000-0000-0000-0000-000000037002', 'rep');

  select * into v_invoice from app.prepare_finance_invoice_from_readiness(v_tenant1, v_br_handoff.id, 30, null, '00000000-0000-0000-0000-000000037003', 'financemanagera');
  select * into v_invoice from app.submit_finance_invoice_for_approval(v_invoice.id, v_invoice.record_version, '00000000-0000-0000-0000-000000037003', 'financemanagera');
  select * into v_invoice from app.approve_finance_invoice(v_invoice.id, v_invoice.record_version, '00000000-0000-0000-0000-000000037003', 'financemanagera');
  perform app.issue_finance_invoice(v_invoice.id, v_invoice.record_version, '2026-03-01'::date, '00000000-0000-0000-0000-000000037003', 'financemanagera');

  select * into v_cost from app.create_actual_cost_draft(v_tenant1, v_shipment.id, 'USD', null, '00000000-0000-0000-0000-000000037002', 'rep');
  perform app.add_actual_cost_component(v_cost.id, 'freight', 'internal', null, null, null, 'Air freight', 1, 'shipment', 3000, null, 0, 'idem-profit-cost-freight-2', '00000000-0000-0000-0000-000000037002', 'rep');
  select * into v_cost from app.shipment_actual_costs where id = v_cost.id;

  -- Stage 2: invoice is now issued (billed revenue resolved), but the cost is
  -- still only submitted, not approved -- calculate must report no_approved_cost.
  v_cost := app.submit_actual_cost(v_cost.id, v_cost.record_version, '00000000-0000-0000-0000-000000037002', 'rep');
  v_fact := app.calculate_finance_job_profitability(v_job.id, 'fixture: invoice now issued, re-checking cost availability', '00000000-0000-0000-0000-000000037003', 'financemanagera');
  if v_fact.status <> 'unavailable' or v_fact.blocked_reason <> 'no_approved_cost' then
    raise exception 'assertion failed: expected status=unavailable blocked_reason=no_approved_cost with the actual cost still only submitted, got status=% blocked_reason=%', v_fact.status, v_fact.blocked_reason;
  end if;

  -- Stage 3: the cost is now approved, but recorded in USD against an IDR
  -- invoice -- calculate must report mixed_currency, and this Job Order is
  -- deliberately left in this blocked state for the summary-exclusion test.
  perform app.decide_actual_cost(v_cost.id, 'approved', null, v_cost.record_version, '00000000-0000-0000-0000-000000037002', 'rep');
  v_fact := app.calculate_finance_job_profitability(v_job.id, 'fixture: cost now approved, re-checking currency reconciliation', '00000000-0000-0000-0000-000000037003', 'financemanagera');
  if v_fact.status <> 'unavailable' or v_fact.blocked_reason <> 'mixed_currency' then
    raise exception 'assertion failed: expected status=unavailable blocked_reason=mixed_currency with an approved USD cost against an IDR invoice, got status=% blocked_reason=%', v_fact.status, v_fact.blocked_reason;
  end if;
end;
$$;

\echo '>> authority: Plain User A and Finance Editor A (no FIN:View margin) are both denied app.calculate_finance_job_profitability; Finance Manager A calculates Job 1 (revenue 15,000,000 - cost 9,000,000 = profit 6,000,000, margin 40.0000%), needs no reason the first time, is rejected without a reason on recalculation, and succeeds with one'
do $$
declare
  v_job1 app.job_orders;
  v_fact app.finance_job_profitability_facts;
begin
  select jo.* into v_job1 from app.job_orders jo join app.shipment_orders so on so.job_order_id = jo.id where so.idempotency_key = 'ocean-a1';

  begin
    perform app.calculate_finance_job_profitability(v_job1.id, null, '00000000-0000-0000-0000-000000037005', 'plainusera');
    raise exception 'assertion failed: expected insufficient_authority for Plain User A (no FIN grant)';
  exception
    when insufficient_privilege then
      null;
  end;

  begin
    perform app.calculate_finance_job_profitability(v_job1.id, null, '00000000-0000-0000-0000-000000037004', 'financeeditora');
    raise exception 'assertion failed: expected insufficient_authority for Finance Editor A (lacks FIN:View margin)';
  exception
    when insufficient_privilege then
      null;
  end;

  v_fact := app.calculate_finance_job_profitability(v_job1.id, null, '00000000-0000-0000-0000-000000037003', 'financemanagera');
  if v_fact.status <> 'calculated' or v_fact.revenue_amount <> 15000000 or v_fact.cost_amount <> 9000000 or v_fact.profit_amount <> 6000000 or v_fact.margin_percent <> 40.0000 or v_fact.revenue_basis <> 'billed' or v_fact.version_number <> 1 then
    raise exception 'assertion failed: expected calculated version 1, basis billed, revenue=15,000,000 cost=9,000,000 profit=6,000,000 margin=40.0000, got status=% basis=% revenue=% cost=% profit=% margin=% version=%',
      v_fact.status, v_fact.revenue_basis, v_fact.revenue_amount, v_fact.cost_amount, v_fact.profit_amount, v_fact.margin_percent, v_fact.version_number;
  end if;

  begin
    perform app.calculate_finance_job_profitability(v_job1.id, null, '00000000-0000-0000-0000-000000037003', 'financemanagera');
    raise exception 'assertion failed: expected finance_profitability_recalculation_reason_required for a reasonless recalculation';
  exception
    when others then
      if sqlerrm !~ 'finance_profitability_recalculation_reason_required' then
        raise exception 'assertion failed: expected finance_profitability_recalculation_reason_required, got %', sqlerrm;
      end if;
  end;

  v_fact := app.calculate_finance_job_profitability(v_job1.id, 'fixture: proving recalculation with a reason succeeds', '00000000-0000-0000-0000-000000037003', 'financemanagera');
  if v_fact.version_number <> 2 or v_fact.status <> 'calculated' or v_fact.profit_amount <> 6000000 then
    raise exception 'assertion failed: expected a stable recalculation to version 2 with the same profit 6,000,000, got version=% status=% profit=%', v_fact.version_number, v_fact.status, v_fact.profit_amount;
  end if;
end;
$$;

\echo '>> Job 3 calculates cleanly (revenue 10,000,000 - cost 6,000,000 = profit 4,000,000, margin 40.0000%), the same customer/branch/service as Job 1'
do $$
declare
  v_job3 app.job_orders;
  v_fact app.finance_job_profitability_facts;
begin
  select jo.* into v_job3 from app.job_orders jo join app.shipment_orders so on so.job_order_id = jo.id where so.idempotency_key = 'ocean-a3';
  v_fact := app.calculate_finance_job_profitability(v_job3.id, null, '00000000-0000-0000-0000-000000037003', 'financemanagera');
  if v_fact.status <> 'calculated' or v_fact.revenue_amount <> 10000000 or v_fact.cost_amount <> 6000000 or v_fact.profit_amount <> 4000000 or v_fact.margin_percent <> 40.0000 then
    raise exception 'assertion failed: expected calculated revenue=10,000,000 cost=6,000,000 profit=4,000,000 margin=40.0000, got status=% revenue=% cost=% profit=% margin=%',
      v_fact.status, v_fact.revenue_amount, v_fact.cost_amount, v_fact.profit_amount, v_fact.margin_percent;
  end if;
end;
$$;

\echo '>> app.get_finance_job_profitability: deny outright (no partial result) without FIN:View margin; Finance Manager A reads Job 1''s own current fact unchanged'
do $$
declare
  v_job1 app.job_orders;
  v_rows app.finance_job_profitability_facts[];
begin
  select jo.* into v_job1 from app.job_orders jo join app.shipment_orders so on so.job_order_id = jo.id where so.idempotency_key = 'ocean-a1';

  begin
    perform app.get_finance_job_profitability(v_job1.id, '00000000-0000-0000-0000-000000037005');
    raise exception 'assertion failed: expected insufficient_authority for Plain User A';
  exception
    when insufficient_privilege then
      null;
  end;

  begin
    perform app.get_finance_job_profitability(v_job1.id, '00000000-0000-0000-0000-000000037004');
    raise exception 'assertion failed: expected insufficient_authority for Finance Editor A (lacks FIN:View margin)';
  exception
    when insufficient_privilege then
      null;
  end;

  select array_agg(r) into v_rows from app.get_finance_job_profitability(v_job1.id, '00000000-0000-0000-0000-000000037003') r;
  if array_length(v_rows, 1) <> 1 or v_rows[1].profit_amount <> 6000000 or v_rows[1].version_number <> 2 then
    raise exception 'assertion failed: expected exactly one current fact (version 2, profit 6,000,000) for Finance Manager A, got %', v_rows;
  end if;
end;
$$;

\echo '>> app.get_finance_profitability_summary: customer/branch/service aggregation sums only calculated facts (Job 1 + Job 3 = revenue 25,000,000, cost 15,000,000, profit 10,000,000, margin 40.0000%, job_count 2); the blocked Job 2 (Customer Two / Branch Y / air_freight) never appears; an invalid group_by is rejected; the summary is denied outright without FIN:View margin'
do $$
declare
  v_tenant1 uuid;
  v_rows record;
  v_count integer;
begin
  v_tenant1 := (select id from app.tenants where slug = 'acmeprofita');

  begin
    perform app.get_finance_profitability_summary(v_tenant1, 'customer', '00000000-0000-0000-0000-000000037004');
    raise exception 'assertion failed: expected insufficient_authority for Finance Editor A (lacks FIN:View margin)';
  exception
    when insufficient_privilege then
      null;
  end;

  begin
    perform app.get_finance_profitability_summary(v_tenant1, 'region', '00000000-0000-0000-0000-000000037003');
    raise exception 'assertion failed: expected finance_profitability_invalid_group_by for an unsupported dimension';
  exception
    when others then
      if sqlerrm !~ 'finance_profitability_invalid_group_by' then
        raise exception 'assertion failed: expected finance_profitability_invalid_group_by, got %', sqlerrm;
      end if;
  end;

  select count(*) into v_count from app.get_finance_profitability_summary(v_tenant1, 'customer', '00000000-0000-0000-0000-000000037003');
  if v_count <> 1 then
    raise exception 'assertion failed: expected exactly one customer group (Customer Two is blocked, excluded), found %', v_count;
  end if;
  select * into v_rows from app.get_finance_profitability_summary(v_tenant1, 'customer', '00000000-0000-0000-0000-000000037003') limit 1;
  if v_rows.dimension_label <> 'Customer One Logistics' or v_rows.job_count <> 2 or v_rows.revenue_amount <> 25000000 or v_rows.cost_amount <> 15000000 or v_rows.profit_amount <> 10000000 or v_rows.margin_percent <> 40.0000 then
    raise exception 'assertion failed: expected Customer One Logistics job_count=2 revenue=25,000,000 cost=15,000,000 profit=10,000,000 margin=40.0000, got label=% job_count=% revenue=% cost=% profit=% margin=%',
      v_rows.dimension_label, v_rows.job_count, v_rows.revenue_amount, v_rows.cost_amount, v_rows.profit_amount, v_rows.margin_percent;
  end if;

  select count(*) into v_count from app.get_finance_profitability_summary(v_tenant1, 'branch', '00000000-0000-0000-0000-000000037003');
  if v_count <> 1 then
    raise exception 'assertion failed: expected exactly one branch group (Branch Y is blocked, excluded), found %', v_count;
  end if;
  select * into v_rows from app.get_finance_profitability_summary(v_tenant1, 'branch', '00000000-0000-0000-0000-000000037003') limit 1;
  if v_rows.dimension_label <> 'Branch X' or v_rows.job_count <> 2 or v_rows.profit_amount <> 10000000 then
    raise exception 'assertion failed: expected Branch X job_count=2 profit=10,000,000, got label=% job_count=% profit=%', v_rows.dimension_label, v_rows.job_count, v_rows.profit_amount;
  end if;

  select count(*) into v_count from app.get_finance_profitability_summary(v_tenant1, 'service', '00000000-0000-0000-0000-000000037003');
  if v_count <> 1 then
    raise exception 'assertion failed: expected exactly one service group (air_freight is blocked, excluded), found %', v_count;
  end if;
  select * into v_rows from app.get_finance_profitability_summary(v_tenant1, 'service', '00000000-0000-0000-0000-000000037003') limit 1;
  if v_rows.dimension_label <> 'ocean_freight' or v_rows.job_count <> 2 or v_rows.profit_amount <> 10000000 then
    raise exception 'assertion failed: expected ocean_freight job_count=2 profit=10,000,000, got label=% job_count=% profit=%', v_rows.dimension_label, v_rows.job_count, v_rows.profit_amount;
  end if;
end;
$$;

\echo '>> cross-tenant isolation: Finance Manager B cannot calculate/read tenant A''s own Job 1 (no FIN grant for tenant A), and tenant B''s own summary is empty (no facts calculated for tenant B)'
do $$
declare
  v_tenant2 uuid;
  v_job1 app.job_orders;
  v_count integer;
  v_msg text;
begin
  v_tenant2 := (select id from app.tenants where slug = 'acmeprofitb');
  select jo.* into v_job1 from app.job_orders jo join app.shipment_orders so on so.job_order_id = jo.id where so.idempotency_key = 'ocean-a1';

  -- ISS-2026-146: Finance Manager B is invited into tenant B only and holds no membership at
  -- all in tenant A, so both calls below are made by the zero-membership foreign caller this
  -- issue is about. Both functions now fold the tenant-membership check into their own
  -- row-miss branch and answer with the identical generic job_order_not_found an unknown job
  -- id already produced, so tenant A's real tenant_id is no longer readable out of the
  -- insufficient_authority text. Neither refusal itself changed: a genuine tenant A member
  -- lacking FIN:Edit / FIN:View margin still reaches the insufficient_authority raise below
  -- the guard, which this file already asserts for tenant A's own viewer.
  begin
    perform app.calculate_finance_job_profitability(v_job1.id, 'intruder attempt', '00000000-0000-0000-0000-000000037006', 'financemanagerb');
    raise exception 'assertion failed: expected job_order_not_found -- Finance Manager B holds zero membership in tenant A';
  exception
    when no_data_found then
      get stacked diagnostics v_msg = message_text;
      if v_msg !~ 'job_order_not_found' then
        raise exception 'assertion failed: expected job_order_not_found, got %', v_msg;
      end if;
      if v_msg like ('%' || v_job1.tenant_id::text || '%') then
        raise exception 'assertion failed: ISS-2026-146 regression -- the denial still discloses tenant A''s real tenant_id: %', v_msg;
      end if;
  end;

  begin
    perform app.get_finance_job_profitability(v_job1.id, '00000000-0000-0000-0000-000000037006');
    raise exception 'assertion failed: expected job_order_not_found -- Finance Manager B holds zero membership in tenant A';
  exception
    when no_data_found then
      get stacked diagnostics v_msg = message_text;
      if v_msg !~ 'job_order_not_found' then
        raise exception 'assertion failed: expected job_order_not_found, got %', v_msg;
      end if;
      if v_msg like ('%' || v_job1.tenant_id::text || '%') then
        raise exception 'assertion failed: ISS-2026-146 regression -- the denial still discloses tenant A''s real tenant_id: %', v_msg;
      end if;
  end;

  select count(*) into v_count from app.get_finance_profitability_summary(v_tenant2, 'customer', '00000000-0000-0000-0000-000000037006');
  if v_count <> 0 then
    raise exception 'assertion failed: expected tenant B''s own summary to be empty (no facts calculated for tenant B), found % rows', v_count;
  end if;
end;
$$;

\echo '>> schema-privilege defense in depth: anon holds zero EXECUTE on every new FIN-212 function (ERR-2026-004 regression guard)'
do $$
declare
  v_fn text;
  v_anon_has boolean;
begin
  for v_fn in select unnest(array[
    'touch_finance_job_profitability_facts_row', 'has_view_finance_margin', 'check_finance_profitability_authority',
    'calculate_finance_job_profitability', 'get_finance_job_profitability', 'get_finance_profitability_summary'
  ]) loop
    select bool_or(has_function_privilege('anon', p.oid, 'EXECUTE'))
      into v_anon_has
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'app' and p.proname = v_fn;
    if coalesce(v_anon_has, false) then
      raise exception 'assertion failed: expected anon to hold zero EXECUTE on app.%, found at least one overload granted', v_fn;
    end if;
  end loop;

  if has_table_privilege('authenticated', 'app.finance_job_profitability_facts', 'SELECT') then
    raise exception 'assertion failed: expected authenticated to hold zero direct SELECT on app.finance_job_profitability_facts (deny outright, this migration''s own header)';
  end if;
end;
$$;

\echo '>> audit trail: at least five calculate_finance_job_profitability events were captured for tenant A''s own profitability activity'
do $$
declare
  v_tenant1 uuid;
  v_count integer;
begin
  v_tenant1 := (select id from app.tenants where slug = 'acmeprofita');
  select count(*) into v_count from app.audit_logs where tenant_id = v_tenant1 and action = 'calculate_finance_job_profitability';
  if v_count < 5 then
    raise exception 'assertion failed: expected at least 5 calculate_finance_job_profitability audit events, found %', v_count;
  end if;
end;
$$;

\echo '>> FIN-214 (Financial Field-Level Security) regression guard: Admin A (tenant_admin, holds no FIN:View margin grant -- confirmed by the fixture setup above) can read this tenant''s own calculate_finance_job_profitability audit events via app.query_audit_logs (gated on is_support_grant_authority alone, never FIN:View margin), but every one of at least 5 such events carries only the safe allowlisted keys -- never revenue_amount/cost_amount/profit_amount/margin_percent/source_invoice_ids/source_cost_version_ids, closing the log-channel inference leak app.audit_logs.after_value previously carried (fixed in 20260729280000_create_finance_field_level_security.sql, a create-or-replace of the identical FIN-212 function)'
do $$
declare
  v_tenant1 uuid;
  v_row app.audit_logs;
  v_checked_count integer := 0;
  v_has_calculated_fact boolean;
begin
  v_tenant1 := (select id from app.tenants where slug = 'acmeprofita');

  select exists(
    select 1 from app.finance_job_profitability_facts where tenant_id = v_tenant1 and status = 'calculated' and revenue_amount > 0
  ) into v_has_calculated_fact;
  if not v_has_calculated_fact then
    raise exception 'assertion failed: expected at least one real calculated fact with a positive revenue_amount for this negative check to be meaningful (not vacuously true against all-null figures)';
  end if;

  for v_row in
    select * from app.query_audit_logs('00000000-0000-0000-0000-000000037001', v_tenant1, 50, null, null) where action = 'calculate_finance_job_profitability'
  loop
    v_checked_count := v_checked_count + 1;
    if v_row.after_value ? 'revenue_amount' or v_row.after_value ? 'cost_amount' or v_row.after_value ? 'profit_amount'
      or v_row.after_value ? 'margin_percent' or v_row.after_value ? 'source_invoice_ids' or v_row.after_value ? 'source_cost_version_ids' then
      raise exception 'assertion failed: audit event % (as read by a tenant_admin with no FIN:View margin grant) leaks a margin-sensitive key: %', v_row.id, v_row.after_value;
    end if;
    if not (v_row.after_value ? 'id' and v_row.after_value ? 'job_order_id' and v_row.after_value ? 'status' and v_row.after_value ? 'blocked_reason') then
      raise exception 'assertion failed: audit event % is missing an expected safe key: %', v_row.id, v_row.after_value;
    end if;
  end loop;
  if v_checked_count < 5 then
    raise exception 'assertion failed: expected to read at least 5 calculate_finance_job_profitability events via app.query_audit_logs, read %', v_checked_count;
  end if;

  -- Confirm the perimeter itself is unchanged by this fix: Admin A (tenant_admin, no FIN:View margin) is still denied outright on the real read/calculate RPCs -- app.query_audit_logs is the one channel this checkpoint closed, not a general FIN:View margin bypass.
  begin
    perform app.get_finance_profitability_summary(v_tenant1, 'customer', '00000000-0000-0000-0000-000000037001');
    raise exception 'assertion failed: expected insufficient_authority for Admin A on app.get_finance_profitability_summary (no FIN:View margin grant)';
  exception
    when insufficient_privilege then
      null;
  end;
end;
$$;
