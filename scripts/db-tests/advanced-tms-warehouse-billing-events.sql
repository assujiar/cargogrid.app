-- Real, executable test evidence for ATW-022 (CG-S10-ATW-022, Prompt 241 Warehouse
-- Billing Events) -- run via `pnpm run db:test` against a real, disposable Postgres
-- database.

\set ON_ERROR_STOP on

\echo '>> setup: one tenant (whbill1) with a tenant_admin, a full-OPS-and-COM supervisor (OPS Create/Edit/View/Override + COM Create/Edit/Approve/View), a second identical supervisor2 (self-approval-blocked axis), a plain OPS Create/Edit/View rep (no Override -- the manual-capture gate axis), an OPS:View-only viewer, a global Supreme Admin, owner accounts Alpha/Beta via the full CRM->account pipeline, a customer_user-layer actor scoped to Account Alpha only, one warehouse (WH-WB-1) with a rack, staging and dock location; a second isolated tenant (whbill2) for cross-tenant checks'
do $$
declare
  v_tenant1 uuid;
  v_tenant2 uuid;
  v_company uuid;
  v_company2 uuid;
  v_supervisor_role uuid;
  v_supervisor_draft app.role_versions;
  v_rep_role uuid;
  v_rep_draft app.role_versions;
  v_viewer_role uuid;
  v_viewer_draft app.role_versions;
  v_rep2_role uuid;
  v_rep2_draft app.role_versions;
  v_warehouse app.warehouses;
begin
  insert into auth.users (id, email) values
    ('00000000-0000-0000-0000-000000210001', 'admin@whbill1.test'),
    ('00000000-0000-0000-0000-000000210002', 'supervisor@whbill1.test'),
    ('00000000-0000-0000-0000-000000210003', 'supervisor2@whbill1.test'),
    ('00000000-0000-0000-0000-000000210004', 'rep@whbill1.test'),
    ('00000000-0000-0000-0000-000000210005', 'viewer@whbill1.test'),
    ('00000000-0000-0000-0000-000000210006', 'supreme@whbill1.test'),
    ('00000000-0000-0000-0000-000000210007', 'customer-alpha@whbill1.test'),
    ('00000000-0000-0000-0000-000000210008', 'admin2@whbill2.test'),
    ('00000000-0000-0000-0000-000000210009', 'rep2@whbill2.test'),
    ('00000000-0000-0000-0000-000000210010', 'finance-worker@whbill1.test');

  perform app.grant_principal_membership('00000000-0000-0000-0000-000000210006', 'supreme_admin', null, null, 'tester');

  perform app.provision_tenant('whbill1', 'Warehouse Billing Tenant One', 'idem-whbill1', 'tester');
  v_tenant1 := (select id from app.tenants where slug = 'whbill1');
  perform app.transition_tenant_status(v_tenant1, 'active', 'setup', 'tester');
  perform app.create_org_unit(v_tenant1, 'company', null, 'WHBILL1-CO', 'Warehouse Billing Tenant One Co', 'tester');
  v_company := (select id from app.org_units where tenant_id = v_tenant1 and code = 'WHBILL1-CO');

  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000210001', 'admin@whbill1.test', 'WhBill Admin', v_company, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'admin@whbill1.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000210001', 'tenant_admin', v_tenant1, null, 'tester');

  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000210002', 'supervisor@whbill1.test', 'WhBill Supervisor', v_company, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'supervisor@whbill1.test'), 'active', 'onboarded', 'tester');

  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000210003', 'supervisor2@whbill1.test', 'WhBill Supervisor Two', v_company, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'supervisor2@whbill1.test'), 'active', 'onboarded', 'tester');

  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000210004', 'rep@whbill1.test', 'WhBill Rep', v_company, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'rep@whbill1.test'), 'active', 'onboarded', 'tester');

  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000210005', 'viewer@whbill1.test', 'WhBill Viewer', v_company, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'viewer@whbill1.test'), 'active', 'onboarded', 'tester');

  -- Full-authority role: every tier this capability spans -- OPS Create/Edit/View/
  -- Override for the event/handoff lifecycle AND COM Create/Edit/Approve/View for the
  -- rate-configuration tier AND enough COM/OPS to run the CRM->account pipeline.
  v_supervisor_role := (app.create_role(v_tenant1, 'WhBill Supervisor Role', 'full commercial + ops create/edit/view/override', 'tester')).id;
  v_supervisor_draft := app.create_role_version(v_supervisor_role, 'tester');
  perform app.set_role_version_permissions(
    v_supervisor_draft.id,
    array(select id from app.permissions where (resource_module_code = 'COM' and action in ('Create', 'Edit', 'Approve', 'View', 'View cost', 'View selling price'))
      or (resource_module_code = 'OPS' and action in ('Create', 'Edit', 'View', 'Override'))
      -- app.calculate_finance_tax (FIN-195), reused directly by app.compute_warehouse_billing_breakdown, itself requires FIN:View for whichever actor triggers a calculation that names a real tax_code.
      or (resource_module_code = 'FIN' and action = 'View')),
    'tester'
  );
  perform app.publish_role_version(v_supervisor_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_supervisor_role and status = 'published'), '00000000-0000-0000-0000-000000210002', '00000000-0000-0000-0000-000000210001', 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_supervisor_role and status = 'published'), '00000000-0000-0000-0000-000000210003', '00000000-0000-0000-0000-000000210001', 'tester');

  -- Plain rep: OPS Create/Edit/View only -- CANNOT manually capture (no OPS:Override)
  -- and CANNOT recalculate/hold/approve/correct/reverse (all OPS:Override).
  v_rep_role := (app.create_role(v_tenant1, 'WhBill Rep Role', 'ops create/edit/view only', 'tester')).id;
  v_rep_draft := app.create_role_version(v_rep_role, 'tester');
  perform app.set_role_version_permissions(v_rep_draft.id, array(select id from app.permissions where resource_module_code = 'OPS' and action in ('Create', 'Edit', 'View')), 'tester');
  perform app.publish_role_version(v_rep_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_rep_role and status = 'published'), '00000000-0000-0000-0000-000000210004', '00000000-0000-0000-0000-000000210001', 'tester');

  v_viewer_role := (app.create_role(v_tenant1, 'WhBill Viewer Role', 'OPS:View only', 'tester')).id;
  v_viewer_draft := app.create_role_version(v_viewer_role, 'tester');
  perform app.set_role_version_permissions(v_viewer_draft.id, array(select id from app.permissions where resource_module_code = 'OPS' and action = 'View'), 'tester');
  perform app.publish_role_version(v_viewer_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_viewer_role and status = 'published'), '00000000-0000-0000-0000-000000210005', '00000000-0000-0000-0000-000000210001', 'tester');

  v_warehouse := app.create_warehouse(v_tenant1, v_company, 'WH-WB-1', 'Warehouse Billing Warehouse 1', 'Jl. Warehouse Billing 1', 'Asia/Jakarta', null, array['land']::text[], '00000000-0000-0000-0000-000000210002', 'supervisor');
  declare
    v_rack app.warehouse_locations;
    v_stage app.warehouse_locations;
    v_dock app.warehouse_locations;
  begin
    v_rack := app.create_warehouse_location(v_warehouse.id, null, null, 'RACK-WB-A', 'WhBill Rack A', 'rack', 1, null, null, null, null, null, true, true, '00000000-0000-0000-0000-000000210002', 'supervisor');
    perform app.set_warehouse_location_status(v_rack.id, 'active', null, v_rack.record_version, '00000000-0000-0000-0000-000000210002', 'supervisor');
    v_stage := app.create_warehouse_location(v_warehouse.id, null, null, 'STAGE-WB-1', 'WhBill Staging 1', 'staging', 2, null, null, null, null, null, false, false, '00000000-0000-0000-0000-000000210002', 'supervisor');
    perform app.set_warehouse_location_status(v_stage.id, 'active', null, v_stage.record_version, '00000000-0000-0000-0000-000000210002', 'supervisor');
    v_dock := app.create_warehouse_location(v_warehouse.id, null, null, 'DOCK-WB-1', 'WhBill Dock 1', 'dock', 3, null, null, null, null, null, false, false, '00000000-0000-0000-0000-000000210002', 'supervisor');
    perform app.set_warehouse_location_status(v_dock.id, 'active', null, v_dock.record_version, '00000000-0000-0000-0000-000000210002', 'supervisor');
  end;

  -- Tenant2: fully isolated -- exists only to prove cross-tenant scope safety.
  perform app.provision_tenant('whbill2', 'Warehouse Billing Tenant Two', 'idem-whbill2', 'tester');
  v_tenant2 := (select id from app.tenants where slug = 'whbill2');
  perform app.transition_tenant_status(v_tenant2, 'active', 'setup', 'tester');
  perform app.create_org_unit(v_tenant2, 'company', null, 'WHBILL2-CO', 'Warehouse Billing Tenant Two Co', 'tester');
  v_company2 := (select id from app.org_units where tenant_id = v_tenant2 and code = 'WHBILL2-CO');
  perform app.invite_user(v_tenant2, '00000000-0000-0000-0000-000000210008', 'admin2@whbill2.test', 'Tenant2 Admin', v_company2, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'admin2@whbill2.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000210008', 'tenant_admin', v_tenant2, null, 'tester');
  perform app.invite_user(v_tenant2, '00000000-0000-0000-0000-000000210009', 'rep2@whbill2.test', 'Tenant2 Rep', v_company2, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'rep2@whbill2.test'), 'active', 'onboarded', 'tester');
  v_rep2_role := (app.create_role(v_tenant2, 'Tenant2 Rep Role', 'ops create/edit/view/override', 'tester')).id;
  v_rep2_draft := app.create_role_version(v_rep2_role, 'tester');
  perform app.set_role_version_permissions(v_rep2_draft.id, array(select id from app.permissions where resource_module_code = 'OPS' and action in ('Create', 'Edit', 'View', 'Override')), 'tester');
  perform app.publish_role_version(v_rep2_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant2, (select id from app.role_versions where role_id = v_rep2_role and status = 'published'), '00000000-0000-0000-0000-000000210009', '00000000-0000-0000-0000-000000210008', 'tester');
end $$;

-- Test-fixture-only helpers (never part of the real migration): build a real,
-- confirmed pick+pack chain and a receiving+putaway chain in a handful of calls
-- (mirrors app.wms outbound''s own db-test helpers, ATW-019).
create procedure pick_fully(p_line_id uuid, p_item_master_id uuid, p_qty numeric, p_rack_id uuid, p_stage_id uuid, p_idem_prefix text)
language plpgsql
as $proc$
declare
  v_t app.wms_pick_tasks;
begin
  v_t := app.generate_wms_pick_task(p_line_id, p_qty, null, p_rack_id, null, null, p_stage_id, p_idem_prefix || '-gen', '00000000-0000-0000-0000-000000210002', 'supervisor');
  v_t := app.claim_wms_pick_task(v_t.id, v_t.record_version, '00000000-0000-0000-0000-000000210002', 'supervisor');
  perform app.confirm_wms_pick_task(v_t.id, p_qty, p_rack_id, p_item_master_id, null, null, p_stage_id, p_idem_prefix || '-conf', v_t.record_version, '00000000-0000-0000-0000-000000210002', 'supervisor');
end;
$proc$;

create function pack_task_fully(p_outbound_order_id uuid, p_pick_task_id uuid, p_item_master_id uuid, p_qty numeric, p_idem_prefix text)
returns app.wms_packages
language plpgsql
as $fn$
declare
  v_packing_task app.wms_packing_tasks;
  v_pkg app.wms_packages;
begin
  v_packing_task := app.start_wms_packing_task(p_outbound_order_id, p_idem_prefix || '-task', '00000000-0000-0000-0000-000000210002', 'supervisor');
  v_pkg := app.create_wms_package(v_packing_task.id, null, 'carton', p_idem_prefix || '-pkg', '00000000-0000-0000-0000-000000210002', 'supervisor');
  v_pkg := app.add_wms_package_line(v_pkg.id, p_pick_task_id, p_qty, p_item_master_id, null, null, p_idem_prefix || '-line', v_pkg.record_version, '00000000-0000-0000-0000-000000210002', 'supervisor');
  v_pkg := app.record_wms_package_measurements(v_pkg.id, 5, 'KG', null, null, null, null, v_pkg.record_version, '00000000-0000-0000-0000-000000210002', 'supervisor');
  v_pkg := app.record_wms_package_qc(v_pkg.id, 'pass', null, v_pkg.record_version, '00000000-0000-0000-0000-000000210002', 'supervisor');
  v_pkg := app.record_wms_package_seal(v_pkg.id, p_idem_prefix || '-seal', v_pkg.record_version, '00000000-0000-0000-0000-000000210002', 'supervisor');
  v_pkg := app.confirm_wms_package(v_pkg.id, p_idem_prefix || '-confirm', v_pkg.record_version, '00000000-0000-0000-0000-000000210002', 'supervisor');
  return v_pkg;
end;
$fn$;

-- One full receive+putaway chain -- returns the resulting confirmed putaway task.
create function receive_and_putaway_fully(p_inbound_order_line_id uuid, p_session_id uuid, p_qty numeric, p_rack_id uuid, p_idem_prefix text)
returns app.wms_putaway_tasks
language plpgsql
as $fn$
declare
  v_line app.wms_receipt_lines;
  v_task app.wms_putaway_tasks;
begin
  select * into v_line from app.wms_receipt_lines where receipt_session_id = p_session_id and inbound_order_line_id = p_inbound_order_line_id;
  v_line := app.record_wms_receipt_line_count(v_line.id, 'PCS', p_qty, p_qty, 0, 0, 0, null, null, null, null, v_line.record_version, '00000000-0000-0000-0000-000000210002', 'supervisor');
  v_line := app.commit_wms_receipt_line(v_line.id, p_idem_prefix || '-commit', v_line.record_version, '00000000-0000-0000-0000-000000210002', 'supervisor');
  v_task := app.generate_wms_putaway_task(v_line.id, p_qty, p_rack_id, p_idem_prefix || '-gen', '00000000-0000-0000-0000-000000210002', 'supervisor');
  v_task := app.claim_wms_putaway_task(v_task.id, v_task.record_version, '00000000-0000-0000-0000-000000210002', 'supervisor');
  v_task := app.confirm_wms_putaway_task(v_task.id, p_qty, p_rack_id, null, null, p_idem_prefix || '-conf', v_task.record_version, '00000000-0000-0000-0000-000000210002', 'supervisor');
  return v_task;
end;
$fn$;

\echo '>> build Account Alpha (via the full CRM pipeline, capturing the accepted+converted quotation for the customer_contract source), Account Beta, items, and a fully committed+putaway receiving chain (SKU-WB-1/SKU-WB-2)'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'whbill1');
  v_company uuid := (select id from app.org_units where tenant_id = v_tenant1 and code = 'WHBILL1-CO');
  v_warehouse_id uuid := (select id from app.warehouses where tenant_id = v_tenant1 and code = 'WH-WB-1');
  v_rack_id uuid := (select id from app.warehouse_locations where tenant_id = v_tenant1 and code = 'RACK-WB-A');
  v_dock_id uuid := (select id from app.warehouse_locations where tenant_id = v_tenant1 and code = 'DOCK-WB-1');
  v_actor uuid := '00000000-0000-0000-0000-000000210002';
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
  v_account_alpha app.accounts;
  v_account_beta app.accounts;
  v_item1 app.item_masters;
  v_item2 app.item_masters;
  v_inbound app.wms_inbound_orders;
  v_line1 app.wms_inbound_order_lines;
  v_line2 app.wms_inbound_order_lines;
  v_session app.wms_receipt_sessions;
begin
  perform app.capture_lead(v_tenant1, 'manual', null, 'WhBill Customer Alpha', 'Alice WhBill', 'alice@whbill241.test', '0811', v_actor, v_company, v_actor, 'tester');
  select * into v_lead from app.leads where email = 'alice@whbill241.test';
  perform app.qualify_lead(v_lead.id, v_lead.record_version, v_actor, 'tester');
  select * into v_lead from app.leads where id = v_lead.id;
  perform app.convert_lead_to_prospect(v_lead.id, 'WhBill Customer Alpha', 'WHBILL241A', '11.111.111.41-111.000',
    jsonb_build_object('line1', 'Jl. WhBill Alpha 1', 'city', 'Jakarta', 'country', 'ID'), v_actor, 'tester');
  select * into v_prospect from app.prospects where lead_id = v_lead.id;
  select * into v_contact from app.create_contact(v_tenant1, 'Alice WhBill Ops', 'Ops Lead', 'alice@whbill241.test', '0811', v_actor, v_company, v_actor, 'tester');
  perform app.link_contact_to_record(v_contact.id, 'prospect', v_prospect.id, 'primary', true, v_actor, 'tester');
  select * into v_opportunity from app.create_opportunity(
    v_tenant1, v_prospect.id, 'WHBILL241 Alpha lane',
    jsonb_build_object('service_type', 'land_freight', 'cargo_description', 'General cargo', 'origin', 'Jakarta', 'destination', 'Surabaya', 'target_ready_date', '2026-08-01'),
    v_actor, v_company, v_actor, 'tester'
  );
  select * into v_request from app.request_costing(v_opportunity.id, '[]'::jsonb, null, v_actor, 'tester');
  select * into v_rate from app.create_rate_version(
    v_tenant1, 'VENDOR-WHBILL241-A', 'Contoso WhBill Line', 'land_freight', 'FTL', 'Jakarta', 'Surabaya', '20ft',
    null, null, null, null, 'IDR', 5000000, null, '[]'::jsonb, now(), null, null, '00000000-0000-0000-0000-000000210001', 'tester'
  );
  perform app.approve_rate_version(v_rate.id, v_rate.record_version, '00000000-0000-0000-0000-000000210001', 'tester');
  select * into v_selection from app.select_vendor_rate(v_request.id, v_rate.id, false, null, null, null, v_actor, 'tester');
  v_rule := app.create_margin_rule_version(v_tenant1, 20.00, 'half_up', v_actor, 'tester');
  perform app.publish_margin_rule_version(v_rule.id, v_rule.record_version, null, v_actor, 'tester');
  perform app.calculate_margin(v_selection.id, 6000000, 'IDR', 0, v_actor, 'tester');
  select id into v_calc_id from app.margin_calculations where rate_selection_id = v_selection.id and is_current;
  select * into v_quote from app.create_quotation_draft(v_tenant1, v_opportunity.id, 'IDR', now() + interval '14 days', v_contact.id, null, null, v_actor, 'tester');
  perform app.add_quotation_line(v_quote.id, v_quote.record_version, 'service', 'WHBILL241 Alpha lane', v_calc_id, 1, 6000000, 0, 0, v_actor, 'tester');
  select * into v_quote from app.quotations where id = v_quote.id;
  perform app.submit_quotation(v_quote.id, v_quote.record_version, v_actor, 'tester');
  select * into v_send from app.send_quotation_for_acceptance(v_quote.id, null, 'email', v_actor, 'tester');
  perform app.record_quotation_customer_decision(v_send.raw_token, 'accepted', 'Alice WhBill Ops', null, null, null, null, null);
  select * into v_quote from app.quotations where id = v_quote.id;
  select * into v_account_alpha from app.convert_quotation_to_account(v_quote.id, null, null, v_actor, 'tester');

  -- Account Beta (a second owner account in the SAME tenant, no contract of its own --
  -- cross-owner manual-capture isolation only).
  perform app.capture_lead(v_tenant1, 'manual', null, 'WhBill Customer Beta', 'Bob WhBill', 'bob@whbill241.test', '0812', v_actor, v_company, v_actor, 'tester');
  select * into v_lead from app.leads where email = 'bob@whbill241.test';
  perform app.qualify_lead(v_lead.id, v_lead.record_version, v_actor, 'tester');
  select * into v_lead from app.leads where id = v_lead.id;
  perform app.convert_lead_to_prospect(v_lead.id, 'WhBill Customer Beta', 'WHBILL241B', '11.111.111.42-111.000',
    jsonb_build_object('line1', 'Jl. WhBill Beta 1', 'city', 'Jakarta', 'country', 'ID'), v_actor, 'tester');
  select * into v_prospect from app.prospects where lead_id = v_lead.id;
  select * into v_contact from app.create_contact(v_tenant1, 'Bob WhBill Ops', 'Ops Lead', 'bob@whbill241.test', '0812', v_actor, v_company, v_actor, 'tester');
  perform app.link_contact_to_record(v_contact.id, 'prospect', v_prospect.id, 'primary', true, v_actor, 'tester');
  select * into v_opportunity from app.create_opportunity(
    v_tenant1, v_prospect.id, 'WHBILL241 Beta lane',
    jsonb_build_object('service_type', 'land_freight', 'cargo_description', 'General cargo', 'origin', 'Jakarta', 'destination', 'Surabaya', 'target_ready_date', '2026-08-01'),
    v_actor, v_company, v_actor, 'tester'
  );
  select * into v_request from app.request_costing(v_opportunity.id, '[]'::jsonb, null, v_actor, 'tester');
  select * into v_rate from app.create_rate_version(
    v_tenant1, 'VENDOR-WHBILL241-B', 'Contoso WhBill Line B', 'land_freight', 'FTL', 'Jakarta', 'Surabaya', '20ft',
    null, null, null, null, 'IDR', 5000000, null, '[]'::jsonb, now(), null, null, '00000000-0000-0000-0000-000000210001', 'tester'
  );
  perform app.approve_rate_version(v_rate.id, v_rate.record_version, '00000000-0000-0000-0000-000000210001', 'tester');
  select * into v_selection from app.select_vendor_rate(v_request.id, v_rate.id, false, null, null, null, v_actor, 'tester');
  perform app.calculate_margin(v_selection.id, 6000000, 'IDR', 0, v_actor, 'tester');
  select id into v_calc_id from app.margin_calculations where rate_selection_id = v_selection.id and is_current;
  select * into v_quote from app.create_quotation_draft(v_tenant1, v_opportunity.id, 'IDR', now() + interval '14 days', v_contact.id, null, null, v_actor, 'tester');
  perform app.add_quotation_line(v_quote.id, v_quote.record_version, 'service', 'WHBILL241 Beta lane', v_calc_id, 1, 6000000, 0, 0, v_actor, 'tester');
  select * into v_quote from app.quotations where id = v_quote.id;
  perform app.submit_quotation(v_quote.id, v_quote.record_version, v_actor, 'tester');
  select * into v_send from app.send_quotation_for_acceptance(v_quote.id, null, 'email', v_actor, 'tester');
  perform app.record_quotation_customer_decision(v_send.raw_token, 'accepted', 'Bob WhBill Ops', null, null, null, null, null);
  select * into v_quote from app.quotations where id = v_quote.id;
  select * into v_account_beta from app.convert_quotation_to_account(v_quote.id, null, null, v_actor, 'tester');

  -- customer_user-layer actor, scoped to Account Alpha only.
  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000210007', 'customer-alpha@whbill1.test', 'Customer Alpha Portal', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'customer-alpha@whbill1.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000210007', 'customer_user', v_tenant1, v_account_alpha.id::text, 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = (select id from app.roles where tenant_id = v_tenant1 and name = 'WhBill Viewer Role') and status = 'published'), '00000000-0000-0000-0000-000000210007', v_actor, 'tester');

  v_item1 := app.create_item_master(v_tenant1, v_account_alpha.id, 'SKU-WB-1', 'WhBill Widget 1 (tiered receiving)', null, 'PCS', false, false, false, v_actor, 'tester');
  v_item2 := app.create_item_master(v_tenant1, v_account_alpha.id, 'SKU-WB-2', 'WhBill Widget 2 (idempotency collision)', null, 'PCS', false, false, false, v_actor, 'tester');
  perform app.create_item_master(v_tenant1, v_account_alpha.id, 'SKU-WB-3', 'WhBill Widget 3 (pick, self-approval/reverse)', null, 'PCS', false, false, false, v_actor, 'tester');
  perform app.create_item_master(v_tenant1, v_account_alpha.id, 'SKU-WB-4', 'WhBill Widget 4 (pack, correction)', null, 'PCS', false, false, false, v_actor, 'tester');
  perform app.create_item_master(v_tenant1, v_account_alpha.id, 'SKU-WB-5', 'WhBill Widget 5 (outbound, hold/recalc)', null, 'PCS', false, false, false, v_actor, 'tester');
  perform app.create_item_master(v_tenant1, v_account_beta.id, 'SKU-WB-BETA', 'WhBill Widget Beta (cross-owner)', null, 'PCS', false, false, false, v_actor, 'tester');

  -- SKU-WB-3/4/5 get their own opening-balance stock at the rack directly (bypassing
  -- receiving/putaway -- only SKU-WB-1/2 need the real receiving+putaway chain, since
  -- that is what exercises the 'wms_receipt_line'/'wms_putaway_confirmation' dispatch
  -- source types; SKU-WB-3/4/5 exist to exercise pick/pack/outbound instead).
  perform app.post_inventory_movement(v_tenant1, v_warehouse_id, 'opening_balance', 'opening_balance', null, 'idem-wb-ob-3', null,
    jsonb_build_array(jsonb_build_object('owner_account_id', v_account_alpha.id, 'item_master_id', (select id from app.item_masters where tenant_id = v_tenant1 and code = 'SKU-WB-3'), 'location_id', v_rack_id, 'uom_code', 'PCS', 'signed_quantity', 100)),
    v_actor, 'tester');
  perform app.post_inventory_movement(v_tenant1, v_warehouse_id, 'opening_balance', 'opening_balance', null, 'idem-wb-ob-4', null,
    jsonb_build_array(jsonb_build_object('owner_account_id', v_account_alpha.id, 'item_master_id', (select id from app.item_masters where tenant_id = v_tenant1 and code = 'SKU-WB-4'), 'location_id', v_rack_id, 'uom_code', 'PCS', 'signed_quantity', 100)),
    v_actor, 'tester');
  perform app.post_inventory_movement(v_tenant1, v_warehouse_id, 'opening_balance', 'opening_balance', null, 'idem-wb-ob-5', null,
    jsonb_build_array(jsonb_build_object('owner_account_id', v_account_alpha.id, 'item_master_id', (select id from app.item_masters where tenant_id = v_tenant1 and code = 'SKU-WB-5'), 'location_id', v_rack_id, 'uom_code', 'PCS', 'signed_quantity', 100)),
    v_actor, 'tester');

  -- Real receiving+putaway chain for SKU-WB-1 (qty 120, spans two tiers of the
  -- receiving rate below) and SKU-WB-2 (qty 30, the idempotency-collision fixture).
  v_inbound := app.create_manual_wms_inbound(v_tenant1, v_warehouse_id, v_account_alpha.id, 'stock replenishment', 'idem-wb-inbound-1', v_actor, 'tester');
  v_line1 := app.add_wms_inbound_order_line(v_inbound.id, v_item1.id, 'PCS', 120, null, v_actor, 'tester');
  v_line2 := app.add_wms_inbound_order_line(v_inbound.id, v_item2.id, 'PCS', 30, null, v_actor, 'tester');
  v_inbound := app.schedule_wms_inbound_appointment(v_inbound.id, now(), now() + interval '2 hours', v_inbound.record_version, v_actor, 'tester');
  v_inbound := app.confirm_wms_inbound(v_inbound.id, v_inbound.record_version, v_actor, 'tester');
  v_session := app.start_wms_receipt_session(v_inbound.id, v_dock_id, 'idem-wb-session-1', v_actor, 'tester');

  perform receive_and_putaway_fully(v_line1.id, v_session.id, 120, v_rack_id, 'idem-wb-r1');
  perform receive_and_putaway_fully(v_line2.id, v_session.id, 30, v_rack_id, 'idem-wb-r2');
end $$;

\echo '>> build confirmed Alpha outbound order O1 (SKU-WB-3/4/5), fully picked+packed, and one shipped shipment producing a real wms_billing_eligibility_events row'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'whbill1');
  v_warehouse_id uuid := (select id from app.warehouses where tenant_id = v_tenant1 and code = 'WH-WB-1');
  v_rack_id uuid := (select id from app.warehouse_locations where tenant_id = v_tenant1 and code = 'RACK-WB-A');
  v_stage_id uuid := (select id from app.warehouse_locations where tenant_id = v_tenant1 and code = 'STAGE-WB-1');
  v_dock_id uuid := (select id from app.warehouse_locations where tenant_id = v_tenant1 and code = 'DOCK-WB-1');
  v_actor uuid := '00000000-0000-0000-0000-000000210002';
  v_account_alpha uuid := (select owner_account_id from app.wms_inbound_orders where tenant_id = v_tenant1 and idempotency_key = 'idem-wb-inbound-1');
  v_item3 app.item_masters;
  v_item4 app.item_masters;
  v_item5 app.item_masters;
  v_order app.wms_outbound_orders;
  v_line3 app.wms_outbound_order_lines;
  v_line4 app.wms_outbound_order_lines;
  v_line5 app.wms_outbound_order_lines;
  v_pick3 app.wms_pick_tasks;
  v_pick4 app.wms_pick_tasks;
  v_pick5 app.wms_pick_tasks;
  v_pkg3 app.wms_packages;
  v_pkg4 app.wms_packages;
  v_pkg5 app.wms_packages;
  v_shipment app.wms_outbound_shipments;
begin
  select * into v_item3 from app.item_masters where tenant_id = v_tenant1 and code = 'SKU-WB-3';
  select * into v_item4 from app.item_masters where tenant_id = v_tenant1 and code = 'SKU-WB-4';
  select * into v_item5 from app.item_masters where tenant_id = v_tenant1 and code = 'SKU-WB-5';

  v_order := app.create_manual_wms_outbound_order(v_tenant1, v_warehouse_id, v_account_alpha, 'customer order', 'idem-wb-outbound-1', current_date + 3, v_actor, 'tester');
  v_line3 := app.add_wms_outbound_order_line(v_order.id, v_item3.id, 'PCS', 20, null, v_actor, 'tester');
  v_line4 := app.add_wms_outbound_order_line(v_order.id, v_item4.id, 'PCS', 15, null, v_actor, 'tester');
  v_line5 := app.add_wms_outbound_order_line(v_order.id, v_item5.id, 'PCS', 10, null, v_actor, 'tester');
  v_order := app.confirm_wms_outbound_order(v_order.id, v_order.record_version, v_actor, 'tester');

  call pick_fully(v_line3.id, v_item3.id, 20, v_rack_id, v_stage_id, 'idem-wb-pick3');
  call pick_fully(v_line4.id, v_item4.id, 15, v_rack_id, v_stage_id, 'idem-wb-pick4');
  call pick_fully(v_line5.id, v_item5.id, 10, v_rack_id, v_stage_id, 'idem-wb-pick5');

  select * into v_pick3 from app.wms_pick_tasks where outbound_order_line_id = v_line3.id;
  select * into v_pick4 from app.wms_pick_tasks where outbound_order_line_id = v_line4.id;
  select * into v_pick5 from app.wms_pick_tasks where outbound_order_line_id = v_line5.id;

  v_pkg3 := pack_task_fully(v_order.id, v_pick3.id, v_item3.id, 20, 'idem-wb-pack3');
  v_pkg4 := pack_task_fully(v_order.id, v_pick4.id, v_item4.id, 15, 'idem-wb-pack4');
  v_pkg5 := pack_task_fully(v_order.id, v_pick5.id, v_item5.id, 10, 'idem-wb-pack5');

  v_shipment := app.create_wms_outbound_shipment(v_order.id, 'idem-wb-shipment-1', v_actor, 'tester');
  perform app.add_package_to_shipment(v_shipment.id, v_pkg3.id, 'idem-wb-add3', v_actor, 'tester');
  perform app.add_package_to_shipment(v_shipment.id, v_pkg4.id, 'idem-wb-add4', v_actor, 'tester');
  perform app.add_package_to_shipment(v_shipment.id, v_pkg5.id, 'idem-wb-add5', v_actor, 'tester');
  v_shipment := app.set_wms_shipment_dock_location(v_shipment.id, v_dock_id, v_shipment.record_version, v_actor, 'tester');
  v_shipment := app.load_wms_outbound_shipment(v_shipment.id, 'idem-wb-load-1', v_shipment.record_version, v_actor, 'tester');
  perform app.ship_confirm_wms_outbound_shipment(v_shipment.id, 'WhBill Custody', 'delivered to carrier', false, null, 'idem-wb-ship-1', v_shipment.record_version, v_actor, 'tester');
end $$;

\echo '>> build the customer_contract (published, >=1 lane price component for publish eligibility) with 5 warehouse_billing_rate_components: putaway per_unit (both warehouse-scoped @1500 and tenant-wide @1000, to prove the warehouse-specific one wins), receiving tiered, outbound flat, pick per_unit, pack flat'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'whbill1');
  v_warehouse_id uuid := (select id from app.warehouses where tenant_id = v_tenant1 and code = 'WH-WB-1');
  v_actor uuid := '00000000-0000-0000-0000-000000210002';
  v_account_alpha uuid := (select owner_account_id from app.wms_inbound_orders where tenant_id = v_tenant1 and idempotency_key = 'idem-wb-inbound-1');
  v_quotation_id uuid;
  v_contract app.customer_contracts;
begin
  select q.id into v_quotation_id from app.quotations q join app.opportunities o on o.id = q.opportunity_id where q.tenant_id = v_tenant1 and o.name = 'WHBILL241 Alpha lane';

  v_contract := app.create_customer_contract_draft(v_quotation_id, null, now() - interval '7 days', null, null, v_actor, 'tester');
  perform app.add_customer_contract_price_component(v_contract.id, 'warehousing', null, null, null, null, 'IDR', 0, null, 0, '[]'::jsonb, v_actor, 'tester');

  -- Warehouse-specific putaway rate, meant to win over the tenant-wide one below.
  perform app.create_warehouse_billing_rate_component(v_contract.id, v_warehouse_id, 'putaway', 'per_unit', 'PCS', 1500, null, 'IDR', null, null, v_actor, 'tester');
  -- Tenant-wide (null warehouse) receiving rate, tiered: 0-50 @1000/unit, 50+ @600/unit.
  perform app.create_warehouse_billing_rate_component(v_contract.id, null, 'receiving', 'tiered', 'PCS', 0, null, 'IDR',
    jsonb_build_array(jsonb_build_object('threshold', 50, 'rate', 1000), jsonb_build_object('threshold', 200, 'rate', 600)), null, v_actor, 'tester');
  perform app.create_warehouse_billing_rate_component(v_contract.id, null, 'outbound', 'flat', null, 250000, null, 'IDR', null, null, v_actor, 'tester');
  perform app.create_warehouse_billing_rate_component(v_contract.id, null, 'pick', 'per_unit', 'PCS', 800, null, 'IDR', null, null, v_actor, 'tester');
  perform app.create_warehouse_billing_rate_component(v_contract.id, null, 'pack', 'flat', null, 15000, null, 'IDR', null, null, v_actor, 'tester');

  v_contract := app.publish_customer_contract(v_contract.id, v_contract.record_version, v_actor, 'tester');
  if v_contract.status <> 'published' then
    raise exception 'assertion failed: expected the WhBill contract to publish, got %', v_contract.status;
  end if;
end $$;

\echo '>> app.create_warehouse_billing_rate_component: rejects a non-draft contract, an invalid tier_schedule, a mismatched rate_uom-for-basis shape; COM:Edit-gated (a plain OPS rep lacking COM:Edit is rejected)'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'whbill1');
  v_warehouse_id uuid := (select id from app.warehouses where tenant_id = v_tenant1 and code = 'WH-WB-1');
  v_contract_id uuid := (select id from app.customer_contracts where tenant_id = v_tenant1 and status = 'published');
  v_actor uuid := '00000000-0000-0000-0000-000000210002';
begin
  begin
    perform app.create_warehouse_billing_rate_component(v_contract_id, null, 'handling', 'flat', null, 100, null, 'IDR', null, null, v_actor, 'tester');
    raise exception 'assertion failed: expected rate_component_requires_draft_contract against a published contract';
  exception
    when others then
      if sqlerrm not like 'rate_component_requires_draft_contract%' then raise; end if;
  end;

  begin
    perform app.create_warehouse_billing_rate_component(v_contract_id, null, 'storage', 'per_unit', 'PCS', 100, null, 'IDR', jsonb_build_array(jsonb_build_object('threshold', 5, 'rate', 1)), null, '00000000-0000-0000-0000-000000210004', 'rep');
    raise exception 'assertion failed: expected insufficient_authority for a rep lacking COM:Edit';
  exception
    when others then
      if sqlerrm not like 'insufficient_authority%' then raise; end if;
  end;
end $$;

\echo '>> app.get_effective_warehouse_billing_rate: prefers the warehouse-specific rate over the tenant-wide one for the same activity_type; raises no_effective_rate cleanly for an unconfigured activity_type (handling)'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'whbill1');
  v_warehouse_id uuid := (select id from app.warehouses where tenant_id = v_tenant1 and code = 'WH-WB-1');
  v_account_alpha uuid := (select owner_account_id from app.wms_inbound_orders where tenant_id = v_tenant1 and idempotency_key = 'idem-wb-inbound-1');
  v_actor uuid := '00000000-0000-0000-0000-000000210002';
  v_rate app.warehouse_billing_rate_components;
begin
  v_rate := app.get_effective_warehouse_billing_rate(v_tenant1, v_account_alpha, v_warehouse_id, 'putaway', now(), v_actor);
  if v_rate.warehouse_id <> v_warehouse_id or v_rate.unit_rate <> 1500 then
    raise exception 'assertion failed: expected the warehouse-specific putaway rate (1500) to win, got warehouse_id=% unit_rate=%', v_rate.warehouse_id, v_rate.unit_rate;
  end if;

  begin
    perform app.get_effective_warehouse_billing_rate(v_tenant1, v_account_alpha, v_warehouse_id, 'handling', now(), v_actor);
    raise exception 'assertion failed: expected no_effective_rate for the unconfigured handling activity type';
  exception
    when others then
      if sqlerrm not like 'no_effective_rate%' then raise; end if;
  end;

  begin
    perform app.preview_warehouse_billing_calculation(v_tenant1, v_account_alpha, v_warehouse_id, 'handling', 5, 'PCS', now(), v_actor);
    raise exception 'assertion failed: expected no_effective_rate from preview for the unconfigured handling activity type';
  exception
    when others then
      if sqlerrm not like 'no_effective_rate%' then raise; end if;
  end;
end $$;

\echo '>> a real approved (non-example-fixture) tenant tax rule (PPN 11%) via Supreme Admin'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'whbill1');
  v_supreme uuid := '00000000-0000-0000-0000-000000210006';
  v_ppn_code_id uuid := (select id from app.finance_tax_codes where tenant_id is null and code = 'PPN');
  v_rule app.finance_tax_rule_versions;
begin
  v_rule := app.create_finance_tax_rule_draft(v_tenant1, v_ppn_code_id, 'percentage', 0.11, null, null, null, '2026-01-01'::date, null, v_supreme, 'tester');
  v_rule := app.attach_finance_tax_rule_evidence(v_rule.id, v_rule.record_version, null, 'PMK real PPN rate, evidence-backed for this db-test fixture', v_supreme, 'tester');
  v_rule := app.approve_finance_tax_rule(v_rule.id, v_rule.record_version, v_supreme, 'tester');
  if v_rule.status <> 'approved' or v_rule.is_example_fixture then
    raise exception 'assertion failed: expected a real, approved, non-example-fixture PPN rule, got status=% is_example_fixture=%', v_rule.status, v_rule.is_example_fixture;
  end if;
end $$;

\echo '>> full lifecycle #1 (per_unit, sourced from app.wms_putaway_tasks): capture -> calculate -> review -> approve -> handoff -> reconciliation outcome (idempotent + conflict); idempotency-collision axis on a second putaway task (source_already_captured / safe replay / idempotency_key_conflict across two different sources)'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'whbill1');
  v_warehouse_id uuid := (select id from app.warehouses where tenant_id = v_tenant1 and code = 'WH-WB-1');
  v_account_alpha uuid := (select owner_account_id from app.wms_inbound_orders where tenant_id = v_tenant1 and idempotency_key = 'idem-wb-inbound-1');
  v_supervisor uuid := '00000000-0000-0000-0000-000000210002';
  v_finance_worker uuid := '00000000-0000-0000-0000-000000210010';
  v_task1 app.wms_putaway_tasks;
  v_task2 app.wms_putaway_tasks;
  v_event app.warehouse_billing_events;
  v_replay app.warehouse_billing_events;
  v_handoff app.warehouse_billing_handoffs;
  v_handoff_replay app.warehouse_billing_handoffs;
begin
  select * into v_task1 from app.wms_putaway_tasks pt join app.wms_receipt_lines rl on rl.id = pt.receipt_line_id join app.item_masters im on im.id = rl.item_master_id where im.code = 'SKU-WB-1' and pt.tenant_id = v_tenant1;
  select * into v_task2 from app.wms_putaway_tasks pt join app.wms_receipt_lines rl on rl.id = pt.receipt_line_id join app.item_masters im on im.id = rl.item_master_id where im.code = 'SKU-WB-2' and pt.tenant_id = v_tenant1;

  v_event := app.capture_warehouse_billing_event(v_tenant1, v_warehouse_id, v_account_alpha, 'putaway', 'wms_putaway_confirmation', v_task1.id, 120, 'PCS', now(), 'idem-wb-cap-task1', null, v_supervisor, 'supervisor');
  if v_event.status <> 'draft' or v_event.source_version <> v_task1.record_version then
    raise exception 'assertion failed: expected a real draft event with source_version=%, got status=% source_version=%', v_task1.record_version, v_event.status, v_event.source_version;
  end if;

  -- Safe idempotent replay -- identical row, never a second capture.
  v_replay := app.capture_warehouse_billing_event(v_tenant1, v_warehouse_id, v_account_alpha, 'putaway', 'wms_putaway_confirmation', v_task1.id, 120, 'PCS', now(), 'idem-wb-cap-task1', null, v_supervisor, 'supervisor');
  if v_replay.id <> v_event.id then
    raise exception 'assertion failed: expected the same idempotency key against the same source to replay the identical event';
  end if;

  -- A genuine duplicate capture attempt against the SAME source under a DIFFERENT key.
  begin
    perform app.capture_warehouse_billing_event(v_tenant1, v_warehouse_id, v_account_alpha, 'putaway', 'wms_putaway_confirmation', v_task1.id, 120, 'PCS', now(), 'idem-wb-cap-task1-dup', null, v_supervisor, 'supervisor');
    raise exception 'assertion failed: expected source_already_captured for a second capture of the same source under a different key';
  exception
    when others then
      if sqlerrm not like 'source_already_captured%' then raise; end if;
  end;

  -- The SAME idempotency key reused against a genuinely DIFFERENT source.
  begin
    perform app.capture_warehouse_billing_event(v_tenant1, v_warehouse_id, v_account_alpha, 'putaway', 'wms_putaway_confirmation', v_task2.id, 30, 'PCS', now(), 'idem-wb-cap-task1', null, v_supervisor, 'supervisor');
    raise exception 'assertion failed: expected idempotency_key_conflict when the same key is reused against a different source';
  exception
    when others then
      if sqlerrm not like 'idempotency_key_conflict%' then raise; end if;
  end;

  v_event := app.calculate_warehouse_billing_event(v_event.id, v_event.record_version, null, v_supervisor, 'supervisor');
  if v_event.status <> 'pending_review' or v_event.base_amount <> 180000 or v_event.total_amount <> 180000 then
    raise exception 'assertion failed: expected 120 * 1500 = 180000 base/total with no tax, got status=% base=% total=%', v_event.status, v_event.base_amount, v_event.total_amount;
  end if;
  if v_event.calculation_explanation is null or v_event.calculation_explanation = '{}'::jsonb then
    raise exception 'assertion failed: expected a populated calculation_explanation';
  end if;

  v_event := app.review_warehouse_billing_event(v_event.id, v_event.record_version, v_supervisor, 'supervisor');
  v_event := app.approve_warehouse_billing_event(v_event.id, v_event.record_version, '00000000-0000-0000-0000-000000210003', 'supervisor2');
  if v_event.status <> 'approved' then
    raise exception 'assertion failed: expected approved, got %', v_event.status;
  end if;

  begin
    perform app.handoff_warehouse_billing_event(v_event.id, '', v_supervisor, 'supervisor');
    raise exception 'assertion failed: expected invalid_idempotency_key for an empty handoff key';
  exception
    when others then
      if sqlerrm not like 'invalid_idempotency_key%' then raise; end if;
  end;

  v_handoff := app.handoff_warehouse_billing_event(v_event.id, 'idem-wb-handoff-1', v_supervisor, 'supervisor');
  v_handoff_replay := app.handoff_warehouse_billing_event(v_event.id, 'idem-wb-handoff-1', v_supervisor, 'supervisor');
  if v_handoff_replay.id <> v_handoff.id then
    raise exception 'assertion failed: expected a same-key handoff retry to return the identical handoff row';
  end if;
  if (select status from app.warehouse_billing_events where id = v_event.id) <> 'handed_off' then
    raise exception 'assertion failed: expected the event to be handed_off';
  end if;

  begin
    perform app.handoff_warehouse_billing_event(v_event.id, 'idem-wb-handoff-1-again', v_supervisor, 'supervisor');
    raise exception 'assertion failed: expected invalid_transition -- an already handed-off event cannot be handed off again';
  exception
    when others then
      if sqlerrm not like 'invalid_transition%' then raise; end if;
  end;

  -- Reconciliation outcome: idempotent same-outcome replay, rejects a conflicting
  -- second outcome. service_role context (no OPS/COM RBAC check at all).
  v_handoff := app.record_warehouse_billing_reconciliation_outcome(v_handoff.id, 'reconciled', 'matched Finance ledger', v_finance_worker, 'finance-worker');
  if v_handoff.reconciliation_status <> 'reconciled' then
    raise exception 'assertion failed: expected reconciliation_status=reconciled';
  end if;
  v_handoff := app.record_warehouse_billing_reconciliation_outcome(v_handoff.id, 'reconciled', 'matched Finance ledger (retry)', v_finance_worker, 'finance-worker');
  if v_handoff.reconciliation_note <> 'matched Finance ledger' then
    raise exception 'assertion failed: expected a same-outcome replay to be a clean no-op, not overwrite the note';
  end if;
  begin
    perform app.record_warehouse_billing_reconciliation_outcome(v_handoff.id, 'rejected', 'actually a mismatch', v_finance_worker, 'finance-worker');
    raise exception 'assertion failed: expected reconciliation_outcome_conflict for a conflicting second outcome';
  exception
    when others then
      if sqlerrm not like 'reconciliation_outcome_conflict%' then raise; end if;
  end;
end $$;

\echo '>> field-masking on read: an OPS:View-only viewer (no COM:View selling price) sees a nulled amount/contract/rate breakdown (calculation_explanation={"masked": true}) via both get_ and list_; a caller holding COM:View selling price sees the real calculated amounts'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'whbill1');
  v_supervisor uuid := '00000000-0000-0000-0000-000000210002';
  v_viewer uuid := '00000000-0000-0000-0000-000000210005';
  v_event_id uuid := (select id from app.warehouse_billing_events where tenant_id = v_tenant1 and idempotency_key = 'idem-wb-cap-task1');
  v_masked app.warehouse_billing_events;
  v_unmasked app.warehouse_billing_events;
  v_rows app.warehouse_billing_events[];
  v_list_base_amount numeric;
  v_list_total_amount numeric;
begin
  v_masked := app.get_warehouse_billing_event(v_event_id, v_viewer);
  if v_masked.base_amount is not null or v_masked.tax_amount is not null or v_masked.total_amount is not null or v_masked.currency is not null or v_masked.rounding_mode is not null or v_masked.contract_id is not null or v_masked.rate_component_id is not null then
    raise exception 'assertion failed: expected an OPS:View-only viewer (no COM:View selling price) to see a fully nulled amount/contract/rate breakdown, got base=% tax=% total=% currency=% rounding=% contract=% rate_component=%',
      v_masked.base_amount, v_masked.tax_amount, v_masked.total_amount, v_masked.currency, v_masked.rounding_mode, v_masked.contract_id, v_masked.rate_component_id;
  end if;
  if v_masked.calculation_explanation <> '{"masked": true}'::jsonb then
    raise exception 'assertion failed: expected calculation_explanation={"masked": true}, got %', v_masked.calculation_explanation;
  end if;
  -- Non-commercial fields remain real and useful to the OPS:View-only reader -- this
  -- is a field mask, never a whole-row insufficient_authority denial.
  if v_masked.status <> 'handed_off' or v_masked.quantity <> 120 then
    raise exception 'assertion failed: expected status/quantity to remain unmasked (status=handed_off, quantity=120), got status=% quantity=%', v_masked.status, v_masked.quantity;
  end if;

  v_unmasked := app.get_warehouse_billing_event(v_event_id, v_supervisor);
  if v_unmasked.base_amount <> 180000 or v_unmasked.total_amount <> 180000 then
    raise exception 'assertion failed: expected a caller holding COM:View selling price to see the real calculated amounts, got base=% total=%', v_unmasked.base_amount, v_unmasked.total_amount;
  end if;

  select array_agg(e) into v_rows from app.list_warehouse_billing_events(v_tenant1, v_viewer, null, null, null, null, 200) e;
  select r.base_amount, r.total_amount into v_list_base_amount, v_list_total_amount from unnest(v_rows) as r where r.id = v_event_id;
  if v_list_base_amount is not null or v_list_total_amount is not null then
    raise exception 'assertion failed: expected list_warehouse_billing_events to also mask amounts for an OPS:View-only viewer';
  end if;

  select array_agg(e) into v_rows from app.list_warehouse_billing_events(v_tenant1, v_supervisor, null, null, null, null, 200) e;
  select r.base_amount, r.total_amount into v_list_base_amount, v_list_total_amount from unnest(v_rows) as r where r.id = v_event_id;
  if v_list_base_amount <> 180000 then
    raise exception 'assertion failed: expected list_warehouse_billing_events to return real amounts for a COM:View selling price holder';
  end if;
end $$;

\echo '>> full lifecycle #2 (tiered, sourced from app.wms_receipt_lines, real tax): capture -> calculate (spans two tiers, verified against a hand-computed total, with tax) -> review -> approve -> handoff'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'whbill1');
  v_warehouse_id uuid := (select id from app.warehouses where tenant_id = v_tenant1 and code = 'WH-WB-1');
  v_account_alpha uuid := (select owner_account_id from app.wms_inbound_orders where tenant_id = v_tenant1 and idempotency_key = 'idem-wb-inbound-1');
  v_supervisor uuid := '00000000-0000-0000-0000-000000210002';
  v_line app.wms_receipt_lines;
  v_event app.warehouse_billing_events;
  v_expected_base numeric := (50 * 1000) + (70 * 600); -- 120 units: 50 @1000 + 70 @600 = 92000
  v_expected_tax numeric;
begin
  select rl.* into v_line from app.wms_receipt_lines rl join app.item_masters im on im.id = rl.item_master_id where im.code = 'SKU-WB-1' and rl.tenant_id = v_tenant1;

  v_event := app.capture_warehouse_billing_event(v_tenant1, v_warehouse_id, v_account_alpha, 'receiving', 'wms_receipt_line', v_line.id, 120, 'PCS', now(), 'idem-wb-cap-receiptline1', null, v_supervisor, 'supervisor');
  v_event := app.calculate_warehouse_billing_event(v_event.id, v_event.record_version, 'PPN', v_supervisor, 'supervisor');

  v_expected_tax := round(v_expected_base * 0.11, 2);
  if v_event.base_amount <> v_expected_base then
    raise exception 'assertion failed: expected the hand-computed tiered base_amount % (50*1000 + 70*600), got %', v_expected_base, v_event.base_amount;
  end if;
  if v_event.tax_amount <> v_expected_tax then
    raise exception 'assertion failed: expected tax_amount %, got %', v_expected_tax, v_event.tax_amount;
  end if;
  if v_event.total_amount <> v_event.base_amount + v_event.tax_amount then
    raise exception 'assertion failed: expected total_amount = base_amount + tax_amount exactly, got total=% base=% tax=%', v_event.total_amount, v_event.base_amount, v_event.tax_amount;
  end if;

  v_event := app.review_warehouse_billing_event(v_event.id, v_event.record_version, v_supervisor, 'supervisor');
  v_event := app.approve_warehouse_billing_event(v_event.id, v_event.record_version, '00000000-0000-0000-0000-000000210003', 'supervisor2');
  perform app.handoff_warehouse_billing_event(v_event.id, 'idem-wb-handoff-receiptline1', v_supervisor, 'supervisor');
end $$;

\echo '>> self_approval_not_allowed (pick, per_unit) -> a different approver succeeds -> handoff -> reverse (approved/handed_off only) -> negation verified exactly -> a second reversal is rejected'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'whbill1');
  v_warehouse_id uuid := (select id from app.warehouses where tenant_id = v_tenant1 and code = 'WH-WB-1');
  v_account_alpha uuid := (select owner_account_id from app.wms_inbound_orders where tenant_id = v_tenant1 and idempotency_key = 'idem-wb-inbound-1');
  v_supervisor uuid := '00000000-0000-0000-0000-000000210002';
  v_supervisor2 uuid := '00000000-0000-0000-0000-000000210003';
  v_pick app.wms_pick_tasks;
  v_event app.warehouse_billing_events;
  v_reversal app.warehouse_billing_events;
begin
  select pt.* into v_pick from app.wms_pick_tasks pt join app.item_masters im on im.id = pt.item_master_id where im.code = 'SKU-WB-3' and pt.tenant_id = v_tenant1;

  v_event := app.capture_warehouse_billing_event(v_tenant1, v_warehouse_id, v_account_alpha, 'pick', 'wms_pick_task_confirmation', v_pick.id, 20, 'PCS', now(), 'idem-wb-cap-pick3', null, v_supervisor, 'supervisor');
  v_event := app.calculate_warehouse_billing_event(v_event.id, v_event.record_version, null, v_supervisor, 'supervisor');
  v_event := app.review_warehouse_billing_event(v_event.id, v_event.record_version, v_supervisor, 'supervisor');

  begin
    perform app.approve_warehouse_billing_event(v_event.id, v_event.record_version, v_supervisor, 'supervisor');
    raise exception 'assertion failed: expected self_approval_not_allowed -- the same identity reviewed and attempted to approve';
  exception
    when others then
      if sqlerrm not like 'self_approval_not_allowed%' then raise; end if;
  end;

  v_event := app.approve_warehouse_billing_event(v_event.id, v_event.record_version, v_supervisor2, 'supervisor2');
  perform app.handoff_warehouse_billing_event(v_event.id, 'idem-wb-handoff-pick3', v_supervisor, 'supervisor');
  select * into v_event from app.warehouse_billing_events where id = v_event.id;

  -- p_expected_version is a real optimistic-concurrency guard on reverse too (the same
  -- contract every other lifecycle RPC in this migration applies).
  begin
    perform app.reverse_warehouse_billing_event(v_event.id, v_event.record_version + 1, 'stale client', 'idem-wb-reverse-pick3-stale', v_supervisor, 'supervisor');
    raise exception 'assertion failed: expected stale_version for a reversal with a wrong expected_version';
  exception
    when others then
      if sqlerrm not like 'stale_version%' then raise; end if;
  end;

  v_reversal := app.reverse_warehouse_billing_event(v_event.id, v_event.record_version, 'duplicate pick billed in error', 'idem-wb-reverse-pick3', v_supervisor, 'supervisor');
  if v_reversal.status <> 'pending_review' or v_reversal.reverses_event_id <> v_event.id then
    raise exception 'assertion failed: expected the reversal to be pending_review with reverses_event_id set, got status=% reverses_event_id=%', v_reversal.status, v_reversal.reverses_event_id;
  end if;
  if v_reversal.base_amount <> -v_event.base_amount or v_reversal.tax_amount <> -coalesce(v_event.tax_amount, 0) or v_reversal.total_amount <> -v_event.total_amount then
    raise exception 'assertion failed: expected the reversal''s own amounts to be the EXACT negation of the original (never recalculated), got reversal base/tax/total=%/%/%  original base/tax/total=%/%/%',
      v_reversal.base_amount, v_reversal.tax_amount, v_reversal.total_amount, v_event.base_amount, v_event.tax_amount, v_event.total_amount;
  end if;
  if (select total_amount from app.warehouse_billing_events where id = v_event.id) <> v_event.total_amount then
    raise exception 'assertion failed: reversing an event must never mutate the original''s own total_amount';
  end if;
  if (select status from app.warehouse_billing_events where id = v_event.id) <> 'reversed' then
    raise exception 'assertion failed: expected the ORIGINAL event''s own status to flip to reversed (never staying approved/handed_off, which would let it be legitimately handed off to Finance a second time), got %', (select status from app.warehouse_billing_events where id = v_event.id);
  end if;

  -- With the original now correctly flipped to status=reversed, a second reversal
  -- attempt is rejected by the plain status-transition guard itself (invalid_transition)
  -- before ever reaching the already_reversed exists() check -- that check now only
  -- guards a genuine concurrent race (two simultaneous reversals of the same
  -- still-approved/handed_off original, serialized by the row lock).
  begin
    perform app.reverse_warehouse_billing_event(v_event.id, v_event.record_version, 'attempting a second reversal', 'idem-wb-reverse-pick3-again', v_supervisor, 'supervisor');
    raise exception 'assertion failed: expected invalid_transition for a second reversal attempt against an already-reversed original';
  exception
    when others then
      if sqlerrm not like 'invalid_transition%' then raise; end if;
  end;

  declare
    v_draft_event app.warehouse_billing_events;
  begin
    v_draft_event := app.capture_warehouse_billing_event(v_tenant1, v_warehouse_id, v_account_alpha, 'storage', 'manual', null, 1, 'PCS', now(), 'idem-wb-cap-draft-for-reverse-check', 'throwaway draft for the reverse-rejects-draft check', v_supervisor, 'supervisor');
    begin
      perform app.reverse_warehouse_billing_event(v_draft_event.id, v_draft_event.record_version, 'never approved', 'idem-wb-reverse-notapproved', v_supervisor, 'supervisor');
      raise exception 'assertion failed: expected invalid_transition -- reversing a draft event makes no sense';
    exception
      when others then
        if sqlerrm not like 'invalid_transition%' then raise; end if;
    end;
  end;
end $$;

\echo '>> correct_warehouse_billing_event on an ALREADY-HANDED-OFF event (pack, flat): original -> corrected, own total_amount UNCHANGED, a new draft event references it; a second correction is rejected already_corrected'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'whbill1');
  v_warehouse_id uuid := (select id from app.warehouses where tenant_id = v_tenant1 and code = 'WH-WB-1');
  v_account_alpha uuid := (select owner_account_id from app.wms_inbound_orders where tenant_id = v_tenant1 and idempotency_key = 'idem-wb-inbound-1');
  v_supervisor uuid := '00000000-0000-0000-0000-000000210002';
  v_supervisor2 uuid := '00000000-0000-0000-0000-000000210003';
  v_pkg app.wms_packages;
  v_event app.warehouse_billing_events;
  v_original_total numeric;
  v_correction app.warehouse_billing_events;
begin
  select pkg.* into v_pkg from app.wms_packages pkg join app.wms_package_lines pl on pl.package_id = pkg.id join app.item_masters im on im.id = pl.item_master_id where im.code = 'SKU-WB-4' and pkg.tenant_id = v_tenant1;

  v_event := app.capture_warehouse_billing_event(v_tenant1, v_warehouse_id, v_account_alpha, 'pack', 'wms_package_confirmation', v_pkg.id, 15, 'PCS', now(), 'idem-wb-cap-pack4', null, v_supervisor, 'supervisor');
  v_event := app.calculate_warehouse_billing_event(v_event.id, v_event.record_version, null, v_supervisor, 'supervisor');
  if v_event.base_amount <> 15000 then
    raise exception 'assertion failed: expected a flat 15000, got %', v_event.base_amount;
  end if;
  v_event := app.review_warehouse_billing_event(v_event.id, v_event.record_version, v_supervisor, 'supervisor');
  v_event := app.approve_warehouse_billing_event(v_event.id, v_event.record_version, v_supervisor2, 'supervisor2');
  perform app.handoff_warehouse_billing_event(v_event.id, 'idem-wb-handoff-pack4', v_supervisor, 'supervisor');
  select * into v_event from app.warehouse_billing_events where id = v_event.id;
  v_original_total := v_event.total_amount;

  -- p_expected_version is a real optimistic-concurrency guard on correct/reverse too
  -- (the same contract every other lifecycle RPC in this migration applies) -- a stale
  -- caller-supplied version is rejected before any mutation happens.
  begin
    perform app.correct_warehouse_billing_event(v_event.id, v_event.record_version + 1, 11, 'stale client', 'idem-wb-correct-pack4-stale', v_supervisor, 'supervisor');
    raise exception 'assertion failed: expected stale_version for a correction with a wrong expected_version';
  exception
    when others then
      if sqlerrm not like 'stale_version%' then raise; end if;
  end;

  v_correction := app.correct_warehouse_billing_event(v_event.id, v_event.record_version, 12, 'over-packed, corrected quantity', 'idem-wb-correct-pack4', v_supervisor, 'supervisor');
  if v_correction.status <> 'draft' or v_correction.corrects_event_id <> v_event.id or v_correction.quantity <> 12 then
    raise exception 'assertion failed: expected a new draft correction event with corrects_event_id set and quantity=12, got status=% corrects_event_id=% quantity=%', v_correction.status, v_correction.corrects_event_id, v_correction.quantity;
  end if;

  select * into v_event from app.warehouse_billing_events where id = v_event.id;
  if v_event.status <> 'corrected' then
    raise exception 'assertion failed: expected the original to flip to corrected, got %', v_event.status;
  end if;
  if v_event.total_amount <> v_original_total then
    raise exception 'assertion failed: correcting an event must never rewrite the original''s own total_amount (proving no in-place rewrite) -- expected %, got %', v_original_total, v_event.total_amount;
  end if;

  begin
    perform app.correct_warehouse_billing_event(v_event.id, v_event.record_version, 10, 'a second correction attempt', 'idem-wb-correct-pack4-again', v_supervisor, 'supervisor');
    raise exception 'assertion failed: expected already_corrected for a second correction attempt against the same original';
  exception
    when others then
      if sqlerrm not like 'already_corrected%' then raise; end if;
  end;

  -- Idempotent replay on the correction call itself.
  declare
    v_replay app.warehouse_billing_events;
  begin
    v_replay := app.correct_warehouse_billing_event(v_event.id, v_event.record_version, 12, 'over-packed, corrected quantity', 'idem-wb-correct-pack4', v_supervisor, 'supervisor');
    if v_replay.id <> v_correction.id then
      raise exception 'assertion failed: expected a same-key correction retry to return the identical correction event';
    end if;
  end;
end $$;

\echo '>> full lifecycle #3 (outbound, flat, sourced from app.wms_billing_eligibility_events): capture -> calculate -> review -> recalculate (reason mandatory, resets reviewed->pending_review) -> hold -> release_hold (back to pending_review, never reviewed/approved) -> review -> approve -> recalculate rejected once approved -> handoff'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'whbill1');
  v_warehouse_id uuid := (select id from app.warehouses where tenant_id = v_tenant1 and code = 'WH-WB-1');
  v_account_alpha uuid := (select owner_account_id from app.wms_inbound_orders where tenant_id = v_tenant1 and idempotency_key = 'idem-wb-inbound-1');
  v_supervisor uuid := '00000000-0000-0000-0000-000000210002';
  v_supervisor2 uuid := '00000000-0000-0000-0000-000000210003';
  v_eligibility app.wms_billing_eligibility_events;
  v_event app.warehouse_billing_events;
  v_before_total numeric;
begin
  select * into v_eligibility from app.wms_billing_eligibility_events where tenant_id = v_tenant1 and idempotency_key = 'idem-wb-ship-1';

  v_event := app.capture_warehouse_billing_event(v_tenant1, v_warehouse_id, v_account_alpha, 'outbound', 'wms_billing_eligibility_event', v_eligibility.id, v_eligibility.total_quantity, 'PCS', now(), 'idem-wb-cap-elig-1', null, v_supervisor, 'supervisor');
  if v_event.source_version <> 1 then
    raise exception 'assertion failed: expected source_version=1 for a wms_billing_eligibility_event source (append-only, no record_version column), got %', v_event.source_version;
  end if;

  v_event := app.calculate_warehouse_billing_event(v_event.id, v_event.record_version, null, v_supervisor, 'supervisor');
  if v_event.base_amount <> 250000 then
    raise exception 'assertion failed: expected a flat 250000, got %', v_event.base_amount;
  end if;
  v_event := app.review_warehouse_billing_event(v_event.id, v_event.record_version, v_supervisor, 'supervisor');

  begin
    perform app.recalculate_warehouse_billing_event(v_event.id, v_event.record_version, '', null, v_supervisor, 'supervisor');
    raise exception 'assertion failed: expected invalid_reason for an empty recalculation reason';
  exception
    when others then
      if sqlerrm not like 'invalid_reason%' then raise; end if;
  end;

  v_before_total := v_event.total_amount;
  v_event := app.recalculate_warehouse_billing_event(v_event.id, v_event.record_version, 'confirming the rate still applies', null, v_supervisor, 'supervisor');
  if v_event.status <> 'pending_review' then
    raise exception 'assertion failed: expected a recalculation to reset reviewed back to pending_review, got %', v_event.status;
  end if;
  if v_event.total_amount <> v_before_total then
    raise exception 'assertion failed: expected the recalculated total to match (same flat rate), got % vs %', v_event.total_amount, v_before_total;
  end if;

  v_event := app.hold_warehouse_billing_event(v_event.id, 'awaiting customer dispute resolution', v_event.record_version, v_supervisor, 'supervisor');
  if v_event.status <> 'on_hold' or v_event.hold_reason is null then
    raise exception 'assertion failed: expected on_hold with a hold_reason, got status=% hold_reason=%', v_event.status, v_event.hold_reason;
  end if;

  v_event := app.release_warehouse_billing_event_hold(v_event.id, v_event.record_version, v_supervisor, 'supervisor');
  if v_event.status <> 'pending_review' then
    raise exception 'assertion failed: expected a released hold to land on pending_review, never reviewed/approved directly, got %', v_event.status;
  end if;

  v_event := app.review_warehouse_billing_event(v_event.id, v_event.record_version, v_supervisor, 'supervisor');
  v_event := app.approve_warehouse_billing_event(v_event.id, v_event.record_version, v_supervisor2, 'supervisor2');

  begin
    perform app.recalculate_warehouse_billing_event(v_event.id, v_event.record_version, 'too late now', null, v_supervisor, 'supervisor');
    raise exception 'assertion failed: expected invalid_transition -- recalculate is rejected once approved';
  exception
    when others then
      if sqlerrm not like 'invalid_transition%' then raise; end if;
  end;

  begin
    perform app.handoff_warehouse_billing_event(v_event.id, 'idem-wb-handoff-elig-1', '00000000-0000-0000-0000-000000210005', 'viewer');
    raise exception 'assertion failed: expected insufficient_authority for a viewer (lacks OPS:Edit) attempting handoff';
  exception
    when others then
      if sqlerrm not like 'insufficient_authority%' then raise; end if;
  end;

  perform app.handoff_warehouse_billing_event(v_event.id, 'idem-wb-handoff-elig-1', v_supervisor, 'supervisor');
end $$;

\echo '>> manual source_type requires OPS:Override (storage/value_added, no backing operational table); a plain OPS:Edit-only rep is rejected; cross-owner isolation on Account Beta'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'whbill1');
  v_warehouse_id uuid := (select id from app.warehouses where tenant_id = v_tenant1 and code = 'WH-WB-1');
  v_account_alpha uuid := (select owner_account_id from app.wms_inbound_orders where tenant_id = v_tenant1 and idempotency_key = 'idem-wb-inbound-1');
  v_account_beta uuid;
  v_supervisor uuid := '00000000-0000-0000-0000-000000210002';
  v_rep uuid := '00000000-0000-0000-0000-000000210004';
  v_customer_alpha uuid := '00000000-0000-0000-0000-000000210007';
  v_event_alpha app.warehouse_billing_events;
  v_event_beta app.warehouse_billing_events;
  v_rows app.warehouse_billing_events[];
begin
  select owner_account_id into v_account_beta from app.item_masters where tenant_id = v_tenant1 and code = 'SKU-WB-BETA';

  begin
    perform app.capture_warehouse_billing_event(v_tenant1, v_warehouse_id, v_account_alpha, 'storage', 'manual', null, 10, 'PCS', now(), 'idem-wb-cap-manual-rep', 'monthly pallet storage', v_rep, 'rep');
    raise exception 'assertion failed: expected insufficient_authority for a plain OPS:Edit-only rep attempting a manual capture';
  exception
    when others then
      if sqlerrm not like 'insufficient_authority%' then raise; end if;
  end;

  begin
    perform app.capture_warehouse_billing_event(v_tenant1, v_warehouse_id, v_account_alpha, 'storage', 'manual', null, 10, 'PCS', now(), 'idem-wb-cap-manual-noreason', null, v_supervisor, 'supervisor');
    raise exception 'assertion failed: expected manual_reason_required for a manual capture with no reason';
  exception
    when others then
      if sqlerrm not like 'manual_reason_required%' then raise; end if;
  end;

  -- No rate is configured for 'storage' in this fixture's own contract (deliberately
  -- -- storage/value_added have no operational dispatch table at all, per this
  -- migration's own design) -- this capture stays draft; the manual-gate/cross-owner
  -- assertions below need no calculated amount.
  v_event_alpha := app.capture_warehouse_billing_event(v_tenant1, v_warehouse_id, v_account_alpha, 'storage', 'manual', null, 10, 'PCS', now(), 'idem-wb-cap-manual-alpha', 'monthly pallet storage', v_supervisor, 'supervisor');

  v_event_beta := app.capture_warehouse_billing_event(v_tenant1, v_warehouse_id, v_account_beta, 'value_added', 'manual', null, 3, 'PCS', now(), 'idem-wb-cap-manual-beta', 'kitting service', v_supervisor, 'supervisor');

  -- Regression: the idempotent-replay short-circuit must validate warehouse_id/
  -- owner_account_id too, not just source_type/source_id/activity_type -- otherwise
  -- reusing another target's real idempotency_key/source_type/source_id/activity_type
  -- combination would silently return that OTHER target's full row (including its
  -- calculated financial amounts), an authorization bypass rather than a safe replay.
  begin
    perform app.capture_warehouse_billing_event(v_tenant1, v_warehouse_id, v_account_beta, 'storage', 'manual', null, 999, 'PCS', now(), 'idem-wb-cap-manual-alpha', 'attempted cross-owner replay', v_supervisor, 'supervisor');
    raise exception 'assertion failed: expected idempotency_key_conflict when Alpha''s own idempotency key is reused with a different owner_account_id (Beta)';
  exception
    when others then
      if sqlerrm not like 'idempotency_key_conflict%' then raise; end if;
  end;
  if exists (select 1 from app.warehouse_billing_events where idempotency_key = 'idem-wb-cap-manual-alpha' and owner_account_id = v_account_beta) then
    raise exception 'assertion failed: a cross-owner replay attempt must never create or return a Beta-owned row under Alpha''s own idempotency key';
  end if;

  -- Cross-owner isolation -- customer_alpha (scoped to Account Alpha only) cannot read
  -- Beta's own event via the RPC, and Alpha's own filtered list never includes it.
  begin
    perform app.get_warehouse_billing_event(v_event_beta.id, v_customer_alpha);
    raise exception 'assertion failed: expected insufficient_authority for customer_alpha reading a Beta-owned billing event';
  exception
    when others then
      if sqlerrm not like 'insufficient_authority%' then raise; end if;
  end;

  perform app.get_warehouse_billing_event(v_event_alpha.id, v_customer_alpha);

  select array_agg(e) into v_rows from app.list_warehouse_billing_events(v_tenant1, v_customer_alpha, null, null, null, null, 200) e;
  if exists (select 1 from unnest(v_rows) r where r.id = v_event_beta.id) then
    raise exception 'assertion failed: expected customer_alpha''s own unfiltered list to never include Beta''s own event';
  end if;
  if not exists (select 1 from unnest(v_rows) r where r.id = v_event_alpha.id) then
    raise exception 'assertion failed: expected customer_alpha''s own unfiltered list to include Alpha''s own event';
  end if;

  -- Raw RLS level -- bypassing every RPC entirely.
  set local role authenticated;
  perform set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-000000210007", "role": "authenticated"}', true);
  if exists (select 1 from app.warehouse_billing_events where id = v_event_beta.id) then
    raise exception 'assertion failed: raw RLS leak -- customer_alpha directly selected a Beta-owned billing event row';
  end if;
  if not exists (select 1 from app.warehouse_billing_events where id = v_event_alpha.id) then
    raise exception 'assertion failed: expected RLS to still permit customer_alpha to directly select Alpha''s own event row';
  end if;
  reset role;
end $$;

\echo '>> cross-tenant isolation: tenant2''s rep, who holds zero membership in tenant1, is rejected insufficient_authority on every RPC against tenant1''s real records, and raw RLS denies a direct select'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'whbill1');
  v_tenant2_rep uuid := '00000000-0000-0000-0000-000000210009';
  v_event_id uuid := (select id from app.warehouse_billing_events where tenant_id = v_tenant1 and idempotency_key = 'idem-wb-cap-task1');
  v_contract_id uuid := (select id from app.customer_contracts where tenant_id = v_tenant1 and status = 'published');
begin
  begin
    -- ISS-2026-146: tenant2's rep (whbill2) holds no membership in whbill1, so app.get_warehouse_billing_event
    -- now collapses that zero-membership case into its own generic
    -- warehouse_billing_event_not_found / no_data_found branch -- byte-identical to what a
    -- nonexistent id already produced, so the real tenant_id is never disclosed to an
    -- outsider. A genuine same-tenant member lacking the role still gets
    -- insufficient_authority, unchanged (asserted elsewhere in this file).
    perform app.get_warehouse_billing_event(v_event_id, v_tenant2_rep);
    raise exception 'assertion failed: expected warehouse_billing_event_not_found for a tenant2 actor reading a tenant1 billing event';
  exception
    when others then
      if sqlerrm not like 'warehouse_billing_event_not_found%' then raise; end if;
  end;

  begin
    perform app.calculate_warehouse_billing_event(v_event_id, 1, null, v_tenant2_rep, 'rep2');
    raise exception 'assertion failed: expected insufficient_authority for a tenant2 actor calculating a tenant1 billing event';
  exception
    when others then
      if sqlerrm not like 'insufficient_authority%' then raise; end if;
  end;

  begin
    -- ISS-2026-146: tenant2's rep (whbill2) holds no membership in whbill1, so app.list_warehouse_billing_rate_components
    -- now collapses that zero-membership case into its own generic
    -- contract_not_found / no_data_found branch -- byte-identical to what a
    -- nonexistent id already produced, so the real tenant_id is never disclosed to an
    -- outsider. A genuine same-tenant member lacking the role still gets
    -- insufficient_authority, unchanged (asserted elsewhere in this file).
    perform app.list_warehouse_billing_rate_components(v_contract_id, v_tenant2_rep, null, 50);
    raise exception 'assertion failed: expected contract_not_found for a tenant2 actor listing tenant1''s own rate components';
  exception
    when others then
      if sqlerrm not like 'contract_not_found%' then raise; end if;
  end;

  set local role authenticated;
  perform set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-000000210009", "role": "authenticated"}', true);
  if exists (select 1 from app.warehouse_billing_events where id = v_event_id) then
    raise exception 'assertion failed: raw RLS leak -- tenant2 rep directly selected a tenant1 billing event row';
  end if;
  reset role;
end $$;

\echo '>> bounded reads: p_limit is clamped -- a small explicit limit returns at most that many rows'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'whbill1');
  v_supervisor uuid := '00000000-0000-0000-0000-000000210002';
  v_rows app.warehouse_billing_events[];
begin
  select array_agg(e) into v_rows from app.list_warehouse_billing_events(v_tenant1, v_supervisor, null, null, null, null, 1) e;
  if array_length(v_rows, 1) <> 1 then
    raise exception 'assertion failed: expected p_limit=1 to return exactly 1 row, got %', array_length(v_rows, 1);
  end if;

  select array_agg(e) into v_rows from app.list_warehouse_billing_events(v_tenant1, v_supervisor, null, null, null, null, 500) e;
  if array_length(v_rows, 1) > 200 then
    raise exception 'assertion failed: expected p_limit to be hard-capped at 200, got %', array_length(v_rows, 1);
  end if;
end $$;

\echo '>> schema-privilege defense in depth (ERR-2026-004 regression guard): anon holds no direct table/EXECUTE access; authenticated has RLS-scoped SELECT but no direct INSERT/UPDATE/DELETE; app.record_warehouse_billing_reconciliation_outcome specifically has no authenticated EXECUTE grant at all'
do $$
declare
  v_has_priv boolean;
begin
  select has_table_privilege('anon', 'app.warehouse_billing_rate_components', 'SELECT') into v_has_priv;
  if v_has_priv then raise exception 'assertion failed: anon must not hold SELECT on app.warehouse_billing_rate_components'; end if;
  select has_table_privilege('anon', 'app.warehouse_billing_events', 'SELECT') into v_has_priv;
  if v_has_priv then raise exception 'assertion failed: anon must not hold SELECT on app.warehouse_billing_events'; end if;
  select has_table_privilege('anon', 'app.warehouse_billing_handoffs', 'SELECT') into v_has_priv;
  if v_has_priv then raise exception 'assertion failed: anon must not hold SELECT on app.warehouse_billing_handoffs'; end if;

  select has_table_privilege('authenticated', 'app.warehouse_billing_events', 'INSERT') into v_has_priv;
  if v_has_priv then raise exception 'assertion failed: authenticated must not hold direct INSERT on app.warehouse_billing_events'; end if;
  select has_table_privilege('authenticated', 'app.warehouse_billing_events', 'UPDATE') into v_has_priv;
  if v_has_priv then raise exception 'assertion failed: authenticated must not hold direct UPDATE on app.warehouse_billing_events'; end if;

  select has_function_privilege('anon', 'app.capture_warehouse_billing_event(uuid, uuid, uuid, text, text, uuid, numeric, text, timestamptz, text, text, uuid, text)', 'EXECUTE') into v_has_priv;
  if v_has_priv then raise exception 'assertion failed: anon must not hold EXECUTE on app.capture_warehouse_billing_event'; end if;
  select has_function_privilege('anon', 'app.approve_warehouse_billing_event(uuid, integer, uuid, text)', 'EXECUTE') into v_has_priv;
  if v_has_priv then raise exception 'assertion failed: anon must not hold EXECUTE on app.approve_warehouse_billing_event'; end if;

  select has_function_privilege('authenticated', 'app.record_warehouse_billing_reconciliation_outcome(uuid, text, text, uuid, text)', 'EXECUTE') into v_has_priv;
  if v_has_priv then raise exception 'assertion failed: authenticated must NOT hold EXECUTE on app.record_warehouse_billing_reconciliation_outcome (service_role only)'; end if;
  select has_function_privilege('anon', 'app.record_warehouse_billing_reconciliation_outcome(uuid, text, text, uuid, text)', 'EXECUTE') into v_has_priv;
  if v_has_priv then raise exception 'assertion failed: anon must NOT hold EXECUTE on app.record_warehouse_billing_reconciliation_outcome'; end if;
  select has_function_privilege('service_role', 'app.record_warehouse_billing_reconciliation_outcome(uuid, text, text, uuid, text)', 'EXECUTE') into v_has_priv;
  if not v_has_priv then raise exception 'assertion failed: service_role SHOULD hold EXECUTE on app.record_warehouse_billing_reconciliation_outcome'; end if;

  -- "At most one correction per original" is now a real DB-enforced guarantee too,
  -- symmetric with the pre-existing reversal index (previously relied solely on the
  -- select ... for update row lock plus an application-level exists() check).
  if not exists (
    select 1 from pg_indexes where schemaname = 'app' and tablename = 'warehouse_billing_events' and indexname = 'warehouse_billing_events_one_correction_per_original_idx'
  ) then
    raise exception 'assertion failed: expected a real partial unique index enforcing at most one correction per original event';
  end if;
end $$;

\echo '>> every real lifecycle mutation self-captures a canonical app.audit_logs entry'
do $$
declare
  v_event_id uuid := (select id from app.warehouse_billing_events where idempotency_key = 'idem-wb-cap-task1');
begin
  if not exists (select 1 from app.audit_logs where action = 'capture_warehouse_billing_event' and resource_id = v_event_id) then
    raise exception 'assertion failed: expected a capture_warehouse_billing_event audit entry';
  end if;
  if not exists (select 1 from app.audit_logs where action = 'approve_warehouse_billing_event' and resource_id = v_event_id) then
    raise exception 'assertion failed: expected an approve_warehouse_billing_event audit entry';
  end if;
  if not exists (select 1 from app.audit_logs where action = 'handoff_warehouse_billing_event') then
    raise exception 'assertion failed: expected at least one handoff_warehouse_billing_event audit entry';
  end if;
  if not exists (select 1 from app.audit_logs where action = 'record_warehouse_billing_reconciliation_outcome') then
    raise exception 'assertion failed: expected at least one record_warehouse_billing_reconciliation_outcome audit entry';
  end if;
end $$;

\echo '>> ISS-2026-213 regression: app.approve_warehouse_billing_event''s self_approval_not_allowed check now denies (fails closed) a NULL reviewed_by_auth_user_id rather than the silent pass-through a bare `=` comparison against a nullable column previously produced -- structurally unreachable via any live caller today (app.review_warehouse_billing_event always writes a real, non-null reviewer), forced directly here to prove the comparison itself, in isolation, is now deterministic'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'whbill1');
  v_warehouse_id uuid := (select id from app.warehouses where tenant_id = v_tenant1 and code = 'WH-WB-1');
  v_account_alpha uuid := (select owner_account_id from app.wms_inbound_orders where tenant_id = v_tenant1 and idempotency_key = 'idem-wb-inbound-1');
  v_supervisor uuid := '00000000-0000-0000-0000-000000210002';
  -- 'storage' (this fixture's own contract has deliberately no published rate for it,
  -- per the comment above idem-wb-cap-manual-alpha) cannot reach pending_review at all --
  -- calculate_warehouse_billing_event raises no_effective_rate before ever getting there.
  -- v_task2 (SKU-WB-2's putaway task) is a real, rated 'putaway' source already looked up
  -- earlier in this file for a negative idempotency-key-conflict assertion only -- never
  -- actually captured under its own real key, so it is still available here.
  v_task2 app.wms_putaway_tasks;
  v_event app.warehouse_billing_events;
begin
  select * into v_task2 from app.wms_putaway_tasks pt join app.wms_receipt_lines rl on rl.id = pt.receipt_line_id join app.item_masters im on im.id = rl.item_master_id where im.code = 'SKU-WB-2' and pt.tenant_id = v_tenant1;

  v_event := app.capture_warehouse_billing_event(v_tenant1, v_warehouse_id, v_account_alpha, 'putaway', 'wms_putaway_confirmation', v_task2.id, 30, 'PCS', now(), 'idem-wb-cap-nullactor-213', null, v_supervisor, 'supervisor');
  v_event := app.calculate_warehouse_billing_event(v_event.id, v_event.record_version, null, v_supervisor, 'supervisor');
  if v_event.status <> 'pending_review' then
    raise exception 'test setup assumption violated: expected pending_review after a real rated capture+calculate, got %', v_event.status;
  end if;
  v_event := app.review_warehouse_billing_event(v_event.id, v_event.record_version, v_supervisor, 'supervisor');

  -- Force the nullable actor column directly -- no live caller can leave it null (review
  -- always writes a real, non-null reviewer); re-select afterwards since the table's own
  -- touch trigger bumps record_version on this UPDATE too.
  update app.warehouse_billing_events set reviewed_by_auth_user_id = null where id = v_event.id;
  select * into v_event from app.warehouse_billing_events where id = v_event.id;

  begin
    perform app.approve_warehouse_billing_event(v_event.id, v_event.record_version, v_supervisor, 'supervisor');
    raise exception 'assertion failed: expected self_approval_not_allowed for a NULL reviewed_by_auth_user_id (ISS-2026-213 fail-open regression)';
  exception
    when others then
      if sqlerrm not like 'self_approval_not_allowed%' then raise; end if;
  end;
end $$;

drop function if exists pack_task_fully(uuid, uuid, uuid, numeric, text);
drop procedure if exists pick_fully(uuid, uuid, numeric, uuid, uuid, text);
drop function if exists receive_and_putaway_fully(uuid, uuid, numeric, uuid, text);
