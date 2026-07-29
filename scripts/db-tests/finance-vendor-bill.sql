-- Real, executable test evidence for FIN-200 (Vendor Bill, CG-S9-FIN-011) --
-- run via `pnpm run db:test` against a real, disposable Postgres database.
-- Proves: idempotent preparation from a verified, approved actual cost,
-- summing only the requested vendor's own components; basic-match variance
-- (within tolerance and requiring approval); tax-line integration; the
-- draft -> submitted -> approved -> posted lifecycle with the correct
-- FIN:Edit/FIN:Approve authority split; idempotent, period-aware post that
-- posts exactly one FIN-199 AP open item; discard boundary; cross-tenant
-- isolation; schema-privilege defense in depth; audit trail.

\set ON_ERROR_STOP on

\echo '>> setup: one tenant, full Commercial->Operations pipeline through a confirmed Job Order, a Shipment Order with an approved actual cost carrying one vendor-sourced freight component (10,250,000 IDR) and one internal handling component (excluded from the bill), a Finance Manager, a Finance Editor (no Approve), a Plain User, a second tenant''s own Finance Manager, six fiscal periods, and one approved PPN tax rule (FIN-195)'
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
  v_fin_editor_role uuid;
  v_fin_editor_draft app.role_versions;
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
  v_handoff app.job_order_handoffs;
  v_job_order app.job_orders;
  v_vendor app.master_records;
  v_vendor2 app.master_records;
  v_vendor3 app.master_records;
  v_shipment app.shipment_orders;
  v_assignment app.resource_assignments;
  v_cost app.shipment_actual_costs;
  v_shipment2 app.shipment_orders;
  v_assignment2 app.resource_assignments;
  v_cost2 app.shipment_actual_costs;
  v_shipment3 app.shipment_orders;
  v_assignment3 app.resource_assignments;
  v_cost3 app.shipment_actual_costs;
  v_ppn_code_id uuid;
  v_tax_rule app.finance_tax_rule_versions;
begin
  insert into auth.users (id, email) values
    ('00000000-0000-0000-0000-000000030501', 'admin@acmevbill.test'),
    ('00000000-0000-0000-0000-000000030502', 'repa@acmevbill.test'),
    ('00000000-0000-0000-0000-000000030503', 'financemanagera@acmevbill.test'),
    ('00000000-0000-0000-0000-000000030504', 'financeeditora@acmevbill.test'),
    ('00000000-0000-0000-0000-000000030505', 'plainusera@acmevbill.test'),
    ('00000000-0000-0000-0000-000000030506', 'financemanagerb@acmevbill.test');

  perform app.provision_tenant('acmevbilla', 'Acme Vendor Bill A', 'idem-acmevbilla', 'tester');
  v_tenant1 := (select id from app.tenants where slug = 'acmevbilla');
  perform app.transition_tenant_status(v_tenant1, 'active', 'setup', 'tester');
  perform app.create_org_unit(v_tenant1, 'company', null, 'ACMEVBILLA-CO', 'Acme Vendor Bill A', 'tester');
  v_team_a := (select id from app.org_units where tenant_id = v_tenant1 and code = 'ACMEVBILLA-CO');

  perform app.provision_tenant('acmevbillb', 'Acme Vendor Bill B', 'idem-acmevbillb', 'tester');
  v_tenant2 := (select id from app.tenants where slug = 'acmevbillb');
  perform app.transition_tenant_status(v_tenant2, 'active', 'setup', 'tester');
  perform app.create_org_unit(v_tenant2, 'company', null, 'ACMEVBILLB-CO', 'Acme Vendor Bill B', 'tester');
  v_team_b := (select id from app.org_units where tenant_id = v_tenant2 and code = 'ACMEVBILLB-CO');

  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000030501', 'admin@acmevbill.test', 'Admin A', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'admin@acmevbill.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000030501', 'tenant_admin', v_tenant1, null, 'tester');

  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000030502', 'repa@acmevbill.test', 'Rep A', v_team_a, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'repa@acmevbill.test'), 'active', 'onboarded', 'tester');

  v_full_role := (app.create_role(v_tenant1, 'Full Pipeline Rep', 'full COM/OPS/FIN access to build the fixture', 'tester')).id;
  v_full_draft := app.create_role_version(v_full_role, 'tester');
  perform app.set_role_version_permissions(
    v_full_draft.id,
    array(select id from app.permissions where (resource_module_code = 'COM' and action in ('Create', 'Edit', 'Approve', 'View', 'View selling price', 'View cost'))
      or (resource_module_code = 'OPS' and action in ('Create', 'Edit', 'Assign', 'Override', 'View', 'View cost'))
      or (resource_module_code = 'FIN' and action in ('Create', 'Edit', 'Approve', 'View'))),
    'tester'
  );
  perform app.publish_role_version(v_full_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_full_role and status = 'published'), '00000000-0000-0000-0000-000000030502', '00000000-0000-0000-0000-000000030501', 'tester');

  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000030503', 'financemanagera@acmevbill.test', 'Finance Manager A', v_team_a, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'financemanagera@acmevbill.test'), 'active', 'onboarded', 'tester');
  v_fin_manager_role := (app.create_role(v_tenant1, 'Finance Manager', 'vendor bill authority', 'tester')).id;
  v_fin_manager_draft := app.create_role_version(v_fin_manager_role, 'tester');
  perform app.set_role_version_permissions(v_fin_manager_draft.id, array(select id from app.permissions where resource_module_code = 'FIN' and action in ('Create', 'Edit', 'Approve', 'View')), 'tester');
  perform app.publish_role_version(v_fin_manager_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_fin_manager_role and status = 'published'), '00000000-0000-0000-0000-000000030503', '00000000-0000-0000-0000-000000030501', 'tester');

  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000030504', 'financeeditora@acmevbill.test', 'Finance Editor A', v_team_a, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'financeeditora@acmevbill.test'), 'active', 'onboarded', 'tester');
  v_fin_editor_role := (app.create_role(v_tenant1, 'Finance Editor', 'edit only, no approve', 'tester')).id;
  v_fin_editor_draft := app.create_role_version(v_fin_editor_role, 'tester');
  perform app.set_role_version_permissions(v_fin_editor_draft.id, array(select id from app.permissions where resource_module_code = 'FIN' and action in ('Edit', 'View')), 'tester');
  perform app.publish_role_version(v_fin_editor_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_fin_editor_role and status = 'published'), '00000000-0000-0000-0000-000000030504', '00000000-0000-0000-0000-000000030501', 'tester');

  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000030505', 'plainusera@acmevbill.test', 'Plain User A', v_team_a, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'plainusera@acmevbill.test'), 'active', 'onboarded', 'tester');

  perform app.invite_user(v_tenant2, '00000000-0000-0000-0000-000000030506', 'financemanagerb@acmevbill.test', 'Finance Manager B', v_team_b, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'financemanagerb@acmevbill.test'), 'active', 'onboarded', 'tester');
  v_fin_manager2_role := (app.create_role(v_tenant2, 'Finance Manager', 'vendor bill authority', 'tester')).id;
  v_fin_manager2_draft := app.create_role_version(v_fin_manager2_role, 'tester');
  perform app.set_role_version_permissions(v_fin_manager2_draft.id, array(select id from app.permissions where resource_module_code = 'FIN' and action in ('Create', 'Edit', 'Approve', 'View')), 'tester');
  perform app.publish_role_version(v_fin_manager2_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant2, (select id from app.role_versions where role_id = v_fin_manager2_role and status = 'published'), '00000000-0000-0000-0000-000000030506', '00000000-0000-0000-0000-000000030506', 'tester');

  -- Full Commercial->Operations pipeline through a confirmed Job Order.
  perform app.capture_lead(v_tenant1, 'manual', null, 'Vendor Bill Test Co', 'Jane Bill', 'jane@vbilltest.test', '0811',
    '00000000-0000-0000-0000-000000030502', v_team_a, '00000000-0000-0000-0000-000000030502', 'tester');
  select * into v_lead from app.leads where email = 'jane@vbilltest.test';
  perform app.qualify_lead(v_lead.id, v_lead.record_version, '00000000-0000-0000-0000-000000030502', 'tester');
  select * into v_lead from app.leads where id = v_lead.id;
  perform app.convert_lead_to_prospect(v_lead.id, 'Vendor Bill Test Co', 'VBT', '66.666.666.8-888.000',
    jsonb_build_object('line1', 'Jl. Thamrin 1', 'city', 'Jakarta', 'country', 'ID'),
    '00000000-0000-0000-0000-000000030502', 'tester');
  select * into v_prospect from app.prospects where lead_id = v_lead.id;

  select * into v_contact from app.create_contact(v_tenant1, 'Jane Bill', 'Procurement Lead', 'jane@vbilltest.test', '0811', '00000000-0000-0000-0000-000000030502', v_team_a, '00000000-0000-0000-0000-000000030502', 'tester');
  perform app.link_contact_to_record(v_contact.id, 'prospect', v_prospect.id, 'primary', true, '00000000-0000-0000-0000-000000030502', 'tester');

  select * into v_opportunity from app.create_opportunity(
    v_tenant1, v_prospect.id, 'Vendor bill test lane',
    jsonb_build_object('service_type', 'ocean_freight', 'cargo_description', 'General cargo', 'origin', 'Jakarta', 'destination', 'Surabaya', 'target_ready_date', '2026-08-01'),
    '00000000-0000-0000-0000-000000030502', v_team_a, '00000000-0000-0000-0000-000000030502', 'tester'
  );
  select * into v_request from app.request_costing(v_opportunity.id, '[]'::jsonb, null, '00000000-0000-0000-0000-000000030502', 'tester');
  select * into v_rate from app.create_rate_version(
    v_tenant1, 'VENDOR-VBILL-1', 'Contoso Ocean Line', 'ocean_freight', 'FCL', 'Jakarta', 'Surabaya', '20ft',
    null, null, null, null, 'IDR', 10000000, null, '[]'::jsonb, now(), null, null, '00000000-0000-0000-0000-000000030501', 'tester'
  );
  perform app.approve_rate_version(v_rate.id, v_rate.record_version, '00000000-0000-0000-0000-000000030501', 'tester');
  select * into v_selection from app.select_vendor_rate(v_request.id, v_rate.id, false, null, null, null, '00000000-0000-0000-0000-000000030502', 'tester');

  select * into v_rule from app.create_margin_rule_version(v_tenant1, 20.00, 'half_up', '00000000-0000-0000-0000-000000030502', 'tester');
  perform app.publish_margin_rule_version(v_rule.id, v_rule.record_version, null, '00000000-0000-0000-0000-000000030502', 'tester');
  perform app.calculate_margin(v_selection.id, 15000000, 'IDR', 0, '00000000-0000-0000-0000-000000030502', 'tester');
  select id into v_calc_id from app.margin_calculations where rate_selection_id = v_selection.id and is_current;

  select * into v_quote from app.create_quotation_draft(v_tenant1, v_opportunity.id, 'IDR', now() + interval '14 days', v_contact.id, null, null, '00000000-0000-0000-0000-000000030502', 'tester');
  perform app.add_quotation_line(v_quote.id, v_quote.record_version, 'service', 'Ocean freight vendor bill lane', v_calc_id, 1, 15000000, 0, 0, '00000000-0000-0000-0000-000000030502', 'tester');
  select * into v_quote from app.quotations where id = v_quote.id;
  perform app.submit_quotation(v_quote.id, v_quote.record_version, '00000000-0000-0000-0000-000000030502', 'tester');
  select * into v_send from app.send_quotation_for_acceptance(v_quote.id, null, 'email', '00000000-0000-0000-0000-000000030502', 'tester');
  perform app.record_quotation_customer_decision(v_send.raw_token, 'accepted', 'Jane Bill', null, null, null, null, null);
  select * into v_quote from app.quotations where id = v_quote.id;
  select * into v_account from app.convert_quotation_to_account(v_quote.id, null, null, '00000000-0000-0000-0000-000000030502', 'rep');
  select * into v_handoff from app.prepare_job_order_handoff(v_quote.id, '00000000-0000-0000-0000-000000030502', 'rep');

  select * into v_job_order from app.prepare_job_order(v_handoff.id, '00000000-0000-0000-0000-000000030502', 'rep');
  select * into v_job_order from app.confirm_job_order(v_job_order.id, v_job_order.record_version, '00000000-0000-0000-0000-000000030502', 'rep');

  select * into v_vendor from app.create_master_record('vendor', v_tenant1, 'VEND-VBILL-1', 'Contoso Trucking', '[]'::jsonb, '{}'::jsonb, '00000000-0000-0000-0000-000000030501', 'admin');
  -- A distinct vendor per extra shipment below, since a resource cannot be actively assigned to two shipments at once.
  select * into v_vendor2 from app.create_master_record('vendor', v_tenant1, 'VEND-VBILL-2', 'Contoso Trucking 2', '[]'::jsonb, '{}'::jsonb, '00000000-0000-0000-0000-000000030501', 'admin');
  select * into v_vendor3 from app.create_master_record('vendor', v_tenant1, 'VEND-VBILL-3', 'Contoso Trucking 3', '[]'::jsonb, '{}'::jsonb, '00000000-0000-0000-0000-000000030501', 'admin');

  select * into v_shipment from app.create_shipment_order_from_job(
    v_job_order.id, 'idem-vbill-a', null, null, 'ocean_freight', 'sea', 'Jakarta', 'Surabaya',
    now() + interval '1 day', now() + interval '10 days', null, null, null, null, null, null, null, '00000000-0000-0000-0000-000000030502', 'rep'
  );
  select * into v_shipment from app.confirm_shipment_order(v_shipment.id, v_shipment.record_version, '00000000-0000-0000-0000-000000030502', 'rep');
  select * into v_shipment from app.transition_shipment_order(v_shipment.id, 'planned', v_shipment.record_version, null, null, 'idem-vbill-a-planned', '00000000-0000-0000-0000-000000030502', 'rep');
  select * into v_shipment from app.transition_shipment_order(v_shipment.id, 'assigned', v_shipment.record_version, null, null, 'idem-vbill-a-assigned', '00000000-0000-0000-0000-000000030502', 'rep');
  select * into v_assignment from app.assign_resource(v_shipment.id, 'vendor', v_vendor.id, '00000000-0000-0000-0000-000000030502', 'rep');

  -- Actual cost: one vendor-sourced freight component (1 * 9,500,000 vs minimum 10,000,000 -> minimum wins; + 250,000 surcharge = 10,250,000.00), one internal handling component (excluded from any vendor bill).
  v_cost := app.create_actual_cost_draft(v_tenant1, v_shipment.id, 'IDR', null, '00000000-0000-0000-0000-000000030502', 'rep');
  perform app.add_actual_cost_component(v_cost.id, 'freight', 'vendor', v_vendor.id, v_assignment.id, null, 'Ocean freight', 1, 'shipment', 9500000, 10000000, 250000, 'idem-vbill-comp-1', '00000000-0000-0000-0000-000000030502', 'rep');
  perform app.add_actual_cost_component(v_cost.id, 'handling', 'internal', null, null, null, 'Warehouse handling', 5, 'ton', 200000, null, 0, 'idem-vbill-comp-2', '00000000-0000-0000-0000-000000030502', 'rep');
  select * into v_cost from app.shipment_actual_costs where id = v_cost.id;
  v_cost := app.submit_actual_cost(v_cost.id, v_cost.record_version, '00000000-0000-0000-0000-000000030502', 'rep');
  v_cost := app.decide_actual_cost(v_cost.id, 'approved', null, v_cost.record_version, '00000000-0000-0000-0000-000000030502', 'rep');

  -- A second and third shipment from the same confirmed Job Order, each with its own approved actual cost,
  -- solely so the "basic match" scenario group below can exercise both a real explicit within_tolerance
  -- vendor_stated_amount and a real requires_approval vendor_stated_amount end-to-end against distinct
  -- (actual_cost, vendor) pairs -- the FIN-200 unique constraint is per (actual_cost_id, vendor_master_id),
  -- so the first shipment's already-prepared bill cannot be reused to exercise these two branches.
  select * into v_shipment2 from app.create_shipment_order_from_job(
    v_job_order.id, 'idem-vbill-a-2', null, null, 'ocean_freight', 'sea', 'Jakarta', 'Surabaya',
    now() + interval '1 day', now() + interval '10 days', null, null, null, null, null, null, 'FIN-200 db-test: second shipment for basic-match within-tolerance fixture', '00000000-0000-0000-0000-000000030502', 'rep'
  );
  select * into v_shipment2 from app.confirm_shipment_order(v_shipment2.id, v_shipment2.record_version, '00000000-0000-0000-0000-000000030502', 'rep');
  select * into v_shipment2 from app.transition_shipment_order(v_shipment2.id, 'planned', v_shipment2.record_version, null, null, 'idem-vbill-a-2-planned', '00000000-0000-0000-0000-000000030502', 'rep');
  select * into v_shipment2 from app.transition_shipment_order(v_shipment2.id, 'assigned', v_shipment2.record_version, null, null, 'idem-vbill-a-2-assigned', '00000000-0000-0000-0000-000000030502', 'rep');
  select * into v_assignment2 from app.assign_resource(v_shipment2.id, 'vendor', v_vendor2.id, '00000000-0000-0000-0000-000000030502', 'rep');

  -- Actual cost 2: one vendor-sourced component of exactly 5,000,000.00 -- used with an explicit
  -- vendor_stated_amount of 5,000,000.50 (variance 0.50, inside the 1.00 tolerance) below.
  v_cost2 := app.create_actual_cost_draft(v_tenant1, v_shipment2.id, 'IDR', null, '00000000-0000-0000-0000-000000030502', 'rep');
  perform app.add_actual_cost_component(v_cost2.id, 'freight', 'vendor', v_vendor2.id, v_assignment2.id, null, 'Ocean freight 2', 1, 'shipment', 5000000, null, 0, 'idem-vbill-comp-2a', '00000000-0000-0000-0000-000000030502', 'rep');
  select * into v_cost2 from app.shipment_actual_costs where id = v_cost2.id;
  v_cost2 := app.submit_actual_cost(v_cost2.id, v_cost2.record_version, '00000000-0000-0000-0000-000000030502', 'rep');
  v_cost2 := app.decide_actual_cost(v_cost2.id, 'approved', null, v_cost2.record_version, '00000000-0000-0000-0000-000000030502', 'rep');

  select * into v_shipment3 from app.create_shipment_order_from_job(
    v_job_order.id, 'idem-vbill-a-3', null, null, 'ocean_freight', 'sea', 'Jakarta', 'Surabaya',
    now() + interval '1 day', now() + interval '10 days', null, null, null, null, null, null, 'FIN-200 db-test: third shipment for basic-match requires-approval fixture', '00000000-0000-0000-0000-000000030502', 'rep'
  );
  select * into v_shipment3 from app.confirm_shipment_order(v_shipment3.id, v_shipment3.record_version, '00000000-0000-0000-0000-000000030502', 'rep');
  select * into v_shipment3 from app.transition_shipment_order(v_shipment3.id, 'planned', v_shipment3.record_version, null, null, 'idem-vbill-a-3-planned', '00000000-0000-0000-0000-000000030502', 'rep');
  select * into v_shipment3 from app.transition_shipment_order(v_shipment3.id, 'assigned', v_shipment3.record_version, null, null, 'idem-vbill-a-3-assigned', '00000000-0000-0000-0000-000000030502', 'rep');
  select * into v_assignment3 from app.assign_resource(v_shipment3.id, 'vendor', v_vendor3.id, '00000000-0000-0000-0000-000000030502', 'rep');

  -- Actual cost 3: one vendor-sourced component of exactly 5,000,000.00 -- used with an explicit
  -- vendor_stated_amount of 5,050,000.00 (variance 50,000.00, materially above the 1.00 tolerance) below.
  v_cost3 := app.create_actual_cost_draft(v_tenant1, v_shipment3.id, 'IDR', null, '00000000-0000-0000-0000-000000030502', 'rep');
  perform app.add_actual_cost_component(v_cost3.id, 'freight', 'vendor', v_vendor3.id, v_assignment3.id, null, 'Ocean freight 3', 1, 'shipment', 5000000, null, 0, 'idem-vbill-comp-3a', '00000000-0000-0000-0000-000000030502', 'rep');
  select * into v_cost3 from app.shipment_actual_costs where id = v_cost3.id;
  v_cost3 := app.submit_actual_cost(v_cost3.id, v_cost3.record_version, '00000000-0000-0000-0000-000000030502', 'rep');
  v_cost3 := app.decide_actual_cost(v_cost3.id, 'approved', null, v_cost3.record_version, '00000000-0000-0000-0000-000000030502', 'rep');

  -- FIN-193: six open fiscal periods (Jan-Jun 2026).
  perform app.generate_finance_fiscal_calendar(v_tenant1, null, 'FY2026', 'FY2026 Monthly', '2026-01-01'::date, 6, '00000000-0000-0000-0000-000000030503', 'financemanagera');

  -- FIN-195: one approved PPN tax rule, so this fixture's own tax-line test can exercise a real calculation.
  v_ppn_code_id := (select id from app.finance_tax_codes where tenant_id is null and code = 'PPN');
  select * into v_tax_rule from app.create_finance_tax_rule_draft(v_tenant1, v_ppn_code_id, 'percentage', 0.11, null, null, null, '2026-01-01'::date, null, '00000000-0000-0000-0000-000000030503', 'financemanagera');
  select * into v_tax_rule from app.attach_finance_tax_rule_evidence(v_tax_rule.id, v_tax_rule.record_version, null, 'fixture evidence note for FIN-200''s own tax-line integration test', '00000000-0000-0000-0000-000000030503', 'financemanagera');
  perform app.approve_finance_tax_rule(v_tax_rule.id, v_tax_rule.record_version, '00000000-0000-0000-0000-000000030503', 'financemanagera');
end;
$$;

\echo '>> idempotent preparation: Plain User A is denied; an unknown/not-approved actual cost and a vendor with no matching component are each rejected; Finance Manager A prepares a draft summing only the vendor''s own component (10,250,000 IDR) plus a PPN tax line, and a retried call for the same (actual cost, vendor) pair returns the same bill unchanged'
do $$
declare
  v_tenant_a uuid;
  v_actual_cost_id uuid;
  v_vendor_id uuid;
  v_bill app.finance_vendor_bills;
  v_retry app.finance_vendor_bills;
  v_line_count integer;
begin
  v_tenant_a := (select id from app.tenants where slug = 'acmevbilla');
  v_actual_cost_id := (select ac.id from app.shipment_actual_costs ac join app.shipment_actual_cost_components c on c.actual_cost_id = ac.id where ac.tenant_id = v_tenant_a and c.description = 'Ocean freight' and ac.is_current);
  v_vendor_id := (select id from app.master_records where tenant_id = v_tenant_a and code = 'VEND-VBILL-1');

  begin
    perform app.prepare_finance_vendor_bill_from_actual_cost(v_tenant_a, v_actual_cost_id, v_vendor_id, 'VBILL-REF-001', '2026-03-15'::date, 30, null, null, '00000000-0000-0000-0000-000000030505', 'plainusera');
    raise exception 'assertion failed: expected insufficient_authority for Plain User A';
  exception
    when insufficient_privilege then
      null;
  end;

  begin
    perform app.prepare_finance_vendor_bill_from_actual_cost(v_tenant_a, gen_random_uuid(), v_vendor_id, 'VBILL-REF-BAD', '2026-03-15'::date, 30, null, null, '00000000-0000-0000-0000-000000030503', 'financemanagera');
    raise exception 'assertion failed: expected finance_vendor_bill_actual_cost_not_found';
  exception
    when others then
      if sqlerrm !~ 'finance_vendor_bill_actual_cost_not_found' then
        raise exception 'assertion failed: expected finance_vendor_bill_actual_cost_not_found, got %', sqlerrm;
      end if;
  end;

  begin
    perform app.prepare_finance_vendor_bill_from_actual_cost(v_tenant_a, v_actual_cost_id, gen_random_uuid(), 'VBILL-REF-BAD2', '2026-03-15'::date, 30, null, null, '00000000-0000-0000-0000-000000030503', 'financemanagera');
    raise exception 'assertion failed: expected finance_vendor_bill_vendor_not_found';
  exception
    when others then
      if sqlerrm !~ 'finance_vendor_bill_vendor_not_found' then
        raise exception 'assertion failed: expected finance_vendor_bill_vendor_not_found, got %', sqlerrm;
      end if;
  end;

  select * into v_bill from app.prepare_finance_vendor_bill_from_actual_cost(v_tenant_a, v_actual_cost_id, v_vendor_id, 'VBILL-REF-001', '2026-03-15'::date, 30, null, 'PPN', '00000000-0000-0000-0000-000000030503', 'financemanagera');
  if v_bill.status <> 'draft' or v_bill.subtotal_amount <> 10250000 or v_bill.tax_amount <> 1127500 or v_bill.total_amount <> 11377500 then
    raise exception 'assertion failed: expected a draft bill of subtotal 10,250,000 + tax 1,127,500 (PPN 11%%) = 11,377,500, got subtotal=% tax=% total=%', v_bill.subtotal_amount, v_bill.tax_amount, v_bill.total_amount;
  end if;
  if v_bill.variance_status <> 'within_tolerance' or v_bill.variance_amount <> 0 then
    raise exception 'assertion failed: expected within_tolerance/0 variance with no vendor_stated_amount supplied, got status=% amount=%', v_bill.variance_status, v_bill.variance_amount;
  end if;

  select count(*) into v_line_count from app.finance_vendor_bill_lines where bill_id = v_bill.id;
  if v_line_count <> 2 then
    raise exception 'assertion failed: expected exactly 2 lines (1 cost from the vendor-sourced component, 1 tax) -- the internal handling component must never appear, found %', v_line_count;
  end if;

  select * into v_retry from app.prepare_finance_vendor_bill_from_actual_cost(v_tenant_a, v_actual_cost_id, v_vendor_id, 'VBILL-REF-IGNORED', '2026-04-01'::date, 999, null, 'PPN', '00000000-0000-0000-0000-000000030503', 'financemanagera');
  if v_retry.id <> v_bill.id or v_retry.payment_term_days <> 30 then
    raise exception 'assertion failed: expected a retried prepare for the same (actual cost, vendor) pair to return the original bill unchanged (idempotent), got id=% payment_term_days=%', v_retry.id, v_retry.payment_term_days;
  end if;
end;
$$;

\echo '>> basic match: an explicit vendor-stated amount within 1.00 of the computed subtotal is within_tolerance with the exact nonzero variance recorded; a materially different vendor-stated amount sets variance_status=requires_approval with the exact variance recorded, disclosed to the approver but not itself blocking approval'
do $$
declare
  v_tenant_a uuid;
  v_actual_cost2_id uuid;
  v_actual_cost3_id uuid;
  v_vendor2_id uuid;
  v_vendor3_id uuid;
  v_bill2 app.finance_vendor_bills;
  v_bill3 app.finance_vendor_bills;
begin
  v_tenant_a := (select id from app.tenants where slug = 'acmevbilla');
  v_vendor2_id := (select id from app.master_records where tenant_id = v_tenant_a and code = 'VEND-VBILL-2');
  v_vendor3_id := (select id from app.master_records where tenant_id = v_tenant_a and code = 'VEND-VBILL-3');
  v_actual_cost2_id := (select ac.id from app.shipment_actual_costs ac
    join app.shipment_actual_cost_components c on c.actual_cost_id = ac.id
    where ac.tenant_id = v_tenant_a and c.description = 'Ocean freight 2' and ac.is_current);
  v_actual_cost3_id := (select ac.id from app.shipment_actual_costs ac
    join app.shipment_actual_cost_components c on c.actual_cost_id = ac.id
    where ac.tenant_id = v_tenant_a and c.description = 'Ocean freight 3' and ac.is_current);

  -- Computed subtotal is 5,000,000.00; a vendor-stated amount of 5,000,000.50 differs by 0.50, inside the 1.00 tolerance.
  select * into v_bill2 from app.prepare_finance_vendor_bill_from_actual_cost(v_tenant_a, v_actual_cost2_id, v_vendor2_id, 'VBILL-REF-002', '2026-03-15'::date, 30, 5000000.50, null, '00000000-0000-0000-0000-000000030503', 'financemanagera');
  if v_bill2.subtotal_amount <> 5000000 then
    raise exception 'assertion failed: fixture precondition failed, expected subtotal 5,000,000.00 for actual cost 2, got %', v_bill2.subtotal_amount;
  end if;
  if v_bill2.variance_status <> 'within_tolerance' or v_bill2.variance_amount <> 0.50 then
    raise exception 'assertion failed: expected within_tolerance with variance 0.50 for a vendor-stated amount 0.50 off subtotal, got status=% amount=%', v_bill2.variance_status, v_bill2.variance_amount;
  end if;

  -- Computed subtotal is 5,000,000.00; a vendor-stated amount of 5,050,000.00 differs by 50,000.00, materially above the 1.00 tolerance.
  select * into v_bill3 from app.prepare_finance_vendor_bill_from_actual_cost(v_tenant_a, v_actual_cost3_id, v_vendor3_id, 'VBILL-REF-003', '2026-03-15'::date, 30, 5050000, null, '00000000-0000-0000-0000-000000030503', 'financemanagera');
  if v_bill3.subtotal_amount <> 5000000 then
    raise exception 'assertion failed: fixture precondition failed, expected subtotal 5,000,000.00 for actual cost 3, got %', v_bill3.subtotal_amount;
  end if;
  if v_bill3.variance_status <> 'requires_approval' or v_bill3.variance_amount <> 50000.00 then
    raise exception 'assertion failed: expected requires_approval with variance 50,000.00 for a materially different vendor-stated amount, got status=% amount=%', v_bill3.variance_status, v_bill3.variance_amount;
  end if;

  -- A requires_approval variance does not itself block approval: Finance Manager A can still approve bill 3 directly from draft-via-submit.
  select * into v_bill3 from app.submit_finance_vendor_bill_for_approval(v_bill3.id, v_bill3.record_version, '00000000-0000-0000-0000-000000030503', 'financemanagera');
  select * into v_bill3 from app.approve_finance_vendor_bill(v_bill3.id, v_bill3.record_version, '00000000-0000-0000-0000-000000030503', 'financemanagera');
  if v_bill3.status <> 'approved' or v_bill3.variance_status <> 'requires_approval' then
    raise exception 'assertion failed: expected a requires_approval-variance bill to still reach approved status (variance discloses, does not block), got status=% variance=%', v_bill3.status, v_bill3.variance_status;
  end if;
end;
$$;

\echo '>> lifecycle authority split: Finance Editor A (no Approve) submits but cannot approve; Finance Manager A approves and posts; posting is idempotent and posts exactly one FIN-199 AP open item for the exact total'
do $$
declare
  v_tenant_a uuid;
  v_actual_cost_id uuid;
  v_vendor_id uuid;
  v_bill app.finance_vendor_bills;
  v_ap_item app.finance_ap_open_items;
  v_ap_count integer;
begin
  v_tenant_a := (select id from app.tenants where slug = 'acmevbilla');
  v_actual_cost_id := (select ac.id from app.shipment_actual_costs ac join app.shipment_actual_cost_components c on c.actual_cost_id = ac.id where ac.tenant_id = v_tenant_a and c.description = 'Ocean freight' and ac.is_current);
  v_vendor_id := (select id from app.master_records where tenant_id = v_tenant_a and code = 'VEND-VBILL-1');
  select * into v_bill from app.finance_vendor_bills where tenant_id = v_tenant_a and actual_cost_id = v_actual_cost_id and vendor_master_id = v_vendor_id;

  begin
    perform app.approve_finance_vendor_bill(v_bill.id, v_bill.record_version, '00000000-0000-0000-0000-000000030504', 'financeeditora');
    raise exception 'assertion failed: expected insufficient_authority -- Finance Editor A lacks FIN:Approve (authority is checked before status)';
  exception
    when insufficient_privilege then
      null;
  end;

  select * into v_bill from app.submit_finance_vendor_bill_for_approval(v_bill.id, v_bill.record_version, '00000000-0000-0000-0000-000000030504', 'financeeditora');
  if v_bill.status <> 'submitted' then
    raise exception 'assertion failed: expected status submitted, got %', v_bill.status;
  end if;

  select * into v_bill from app.approve_finance_vendor_bill(v_bill.id, v_bill.record_version, '00000000-0000-0000-0000-000000030503', 'financemanagera');
  if v_bill.status <> 'approved' then
    raise exception 'assertion failed: expected status approved, got %', v_bill.status;
  end if;

  select * into v_bill from app.post_finance_vendor_bill(v_bill.id, v_bill.record_version, '00000000-0000-0000-0000-000000030503', 'financemanagera');
  if v_bill.status <> 'posted' or v_bill.bill_number !~ '^BILL-2026-[0-9]{6}$' then
    raise exception 'assertion failed: expected status posted and a real bill_number, got status=% number=%', v_bill.status, v_bill.bill_number;
  end if;

  select * into v_ap_item from app.finance_ap_open_items where id = v_bill.ap_open_item_id;
  if v_ap_item.original_amount <> 11377500 or v_ap_item.source_document_type <> 'vendor_bill' or v_ap_item.source_document_id <> v_bill.id then
    raise exception 'assertion failed: expected exactly one FIN-199 AP open item of 11,377,500 sourced from this bill, got amount=% source_type=% source_id=%', v_ap_item.original_amount, v_ap_item.source_document_type, v_ap_item.source_document_id;
  end if;

  select * into v_bill from app.post_finance_vendor_bill(v_bill.id, v_bill.record_version, '00000000-0000-0000-0000-000000030503', 'financemanagera');
  select count(*) into v_ap_count from app.finance_ap_open_items where source_document_type = 'vendor_bill' and source_document_id = v_bill.id;
  if v_ap_count <> 1 then
    raise exception 'assertion failed: expected a retried post to never post a second AP open item, found %', v_ap_count;
  end if;

  begin
    perform app.discard_finance_vendor_bill_draft(v_bill.id, v_bill.record_version, 'too late', '00000000-0000-0000-0000-000000030503', 'financemanagera');
    raise exception 'assertion failed: expected finance_vendor_bill_not_cancellable for a posted bill';
  exception
    when others then
      if sqlerrm !~ 'finance_vendor_bill_not_cancellable' then
        raise exception 'assertion failed: expected finance_vendor_bill_not_cancellable, got %', sqlerrm;
      end if;
  end;
end;
$$;

\echo '>> cross-tenant isolation: Finance Manager B cannot mutate tenant A''s own bill, and list_finance_vendor_bills never returns tenant A''s rows for tenant B''s own scope'
do $$
declare
  v_tenant_a uuid;
  v_tenant_b uuid;
  v_bill app.finance_vendor_bills;
  v_rows app.finance_vendor_bills[];
begin
  v_tenant_a := (select id from app.tenants where slug = 'acmevbilla');
  v_tenant_b := (select id from app.tenants where slug = 'acmevbillb');
  select * into v_bill from app.finance_vendor_bills where tenant_id = v_tenant_a and status = 'posted';

  begin
    perform app.discard_finance_vendor_bill_draft(v_bill.id, v_bill.record_version, 'intruder attempt', '00000000-0000-0000-0000-000000030506', 'financemanagerb');
    raise exception 'assertion failed: expected insufficient_authority -- Finance Manager B holds no FIN grant for tenant A';
  exception
    when insufficient_privilege then
      null;
  end;

  select array_agg(r) into v_rows from app.list_finance_vendor_bills(v_tenant_b, null, null, null, '00000000-0000-0000-0000-000000030506') r;
  if v_rows is not null and exists (select 1 from unnest(v_rows) r where r.tenant_id = v_tenant_a) then
    raise exception 'assertion failed: expected tenant B''s own list_finance_vendor_bills to never return a tenant A row';
  end if;
end;
$$;

\echo '>> schema-privilege defense in depth: anon holds zero EXECUTE on every new FIN-200 function (ERR-2026-004 regression guard)'
do $$
declare
  v_fn text;
  v_anon_has boolean;
begin
  for v_fn in select unnest(array[
    'touch_finance_vendor_bill_row', 'check_finance_vendor_bill_authority', 'prepare_finance_vendor_bill_from_actual_cost',
    'submit_finance_vendor_bill_for_approval', 'discard_finance_vendor_bill_draft', 'approve_finance_vendor_bill',
    'post_finance_vendor_bill', 'list_finance_vendor_bills', 'get_finance_vendor_bill_lines'
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

\echo '>> audit trail: at least one prepare/approve/post event was captured for tenant A''s own vendor bill activity'
do $$
declare
  v_tenant_a uuid;
  v_count integer;
begin
  v_tenant_a := (select id from app.tenants where slug = 'acmevbilla');
  select count(*) into v_count from app.audit_logs where tenant_id = v_tenant_a and action in
    ('prepare_finance_vendor_bill_from_actual_cost', 'approve_finance_vendor_bill', 'post_finance_vendor_bill');
  if v_count < 3 then
    raise exception 'assertion failed: expected at least 3 audit events across this fixture''s own prepare/approve/post calls, found %', v_count;
  end if;
end;
$$;
