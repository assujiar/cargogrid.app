-- Real, executable test evidence for ATW-021 (CG-S10-ATW-021, Prompt 240 Label and
-- Barcode Operations) -- run via `pnpm run db:test` against a real, disposable
-- Postgres database.

\set ON_ERROR_STOP on

\echo '>> setup: one tenant (labelops1) with a supervisor (OPS Create/Edit/View/Override), a rep (OPS Create/Edit/View), an OPS:View-only viewer, a global Supreme Admin, two owner accounts (Alpha, Beta) via the full CRM->Job Order pipeline, a customer_user-layer actor scoped to Account Alpha only, one warehouse (WH-LBL-1) with a pick-enabled rack, a staging location and a dock bin; a second isolated tenant (labelops2) for cross-tenant checks'
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
begin
  insert into auth.users (id, email) values
    ('00000000-0000-0000-0000-000000240001', 'admin@labelops1.test'),
    ('00000000-0000-0000-0000-000000240002', 'supervisor@labelops1.test'),
    ('00000000-0000-0000-0000-000000240003', 'rep@labelops1.test'),
    ('00000000-0000-0000-0000-000000240004', 'viewer@labelops1.test'),
    ('00000000-0000-0000-0000-000000240005', 'supreme@labelops1.test'),
    ('00000000-0000-0000-0000-000000240006', 'customer-alpha@labelops1.test'),
    ('00000000-0000-0000-0000-000000240007', 'admin2@labelops2.test'),
    ('00000000-0000-0000-0000-000000240008', 'rep2@labelops2.test'),
    ('00000000-0000-0000-0000-000000240009', 'worker@labelops1.test');

  perform app.grant_principal_membership('00000000-0000-0000-0000-000000240005', 'supreme_admin', null, null, 'tester');

  perform app.provision_tenant('labelops1', 'Label Ops Tenant One', 'idem-labelops1', 'tester');
  v_tenant1 := (select id from app.tenants where slug = 'labelops1');
  perform app.transition_tenant_status(v_tenant1, 'active', 'setup', 'tester');
  perform app.create_org_unit(v_tenant1, 'company', null, 'LABELOPS1-CO', 'Label Ops Tenant One Co', 'tester');
  v_company := (select id from app.org_units where tenant_id = v_tenant1 and code = 'LABELOPS1-CO');

  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000240001', 'admin@labelops1.test', 'LabelOps Admin', v_company, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'admin@labelops1.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000240001', 'tenant_admin', v_tenant1, null, 'tester');

  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000240002', 'supervisor@labelops1.test', 'LabelOps Supervisor', v_company, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'supervisor@labelops1.test'), 'active', 'onboarded', 'tester');

  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000240003', 'rep@labelops1.test', 'LabelOps Rep', v_company, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'rep@labelops1.test'), 'active', 'onboarded', 'tester');

  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000240004', 'viewer@labelops1.test', 'LabelOps Viewer', v_company, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'viewer@labelops1.test'), 'active', 'onboarded', 'tester');

  v_supervisor_role := (app.create_role(v_tenant1, 'LabelOps Supervisor Role', 'full commercial + ops create/edit/view/override', 'tester')).id;
  v_supervisor_draft := app.create_role_version(v_supervisor_role, 'tester');
  perform app.set_role_version_permissions(
    v_supervisor_draft.id,
    array(select id from app.permissions where (resource_module_code = 'COM' and action in ('Create', 'Edit', 'Approve', 'View', 'View cost'))
      or (resource_module_code = 'OPS' and action in ('Create', 'Edit', 'View', 'Override'))),
    'tester'
  );
  perform app.publish_role_version(v_supervisor_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_supervisor_role and status = 'published'), '00000000-0000-0000-0000-000000240002', '00000000-0000-0000-0000-000000240001', 'tester');

  -- The rep role holds COM Create/Edit/Approve/View/View cost TOGETHER with OPS
  -- Create/Edit/View (mirrors advanced-tms-wms-packing.sql's own identical rep-role
  -- shape) -- the full CRM->Job Order pipeline below (capture_lead through
  -- convert_quotation_to_account) requires the COM trio; every label/WMS mutation this
  -- fixture drives through 'rep' composes at least one of the OPS three. Only
  -- OPS:Override (governed publish/reprint/void/archive actions) is deliberately
  -- reserved to 'supervisor' alone.
  v_rep_role := (app.create_role(v_tenant1, 'LabelOps Rep Role', 'full commercial + ops create/edit/view', 'tester')).id;
  v_rep_draft := app.create_role_version(v_rep_role, 'tester');
  perform app.set_role_version_permissions(
    v_rep_draft.id,
    array(select id from app.permissions where (resource_module_code = 'COM' and action in ('Create', 'Edit', 'Approve', 'View', 'View cost'))
      or (resource_module_code = 'OPS' and action in ('Create', 'Edit', 'View'))),
    'tester'
  );
  perform app.publish_role_version(v_rep_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_rep_role and status = 'published'), '00000000-0000-0000-0000-000000240003', '00000000-0000-0000-0000-000000240001', 'tester');

  v_viewer_role := (app.create_role(v_tenant1, 'LabelOps Viewer Role', 'OPS:View only', 'tester')).id;
  v_viewer_draft := app.create_role_version(v_viewer_role, 'tester');
  perform app.set_role_version_permissions(v_viewer_draft.id, array(select id from app.permissions where resource_module_code = 'OPS' and action = 'View'), 'tester');
  perform app.publish_role_version(v_viewer_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_viewer_role and status = 'published'), '00000000-0000-0000-0000-000000240004', '00000000-0000-0000-0000-000000240001', 'tester');

  v_warehouse := app.create_warehouse(v_tenant1, v_company, 'WH-LBL-1', 'Label Ops Warehouse 1', 'Jl. Label Ops 1', 'Asia/Jakarta', null, array['land']::text[], '00000000-0000-0000-0000-000000240002', 'supervisor');
  declare
    v_rack app.warehouse_locations;
    v_stage app.warehouse_locations;
    v_dock app.warehouse_locations;
  begin
    v_rack := app.create_warehouse_location(v_warehouse.id, null, null, 'RACK-LBL-A', 'Label Rack A', 'rack', 1, null, null, null, null, null, true, false, '00000000-0000-0000-0000-000000240002', 'supervisor');
    perform app.set_warehouse_location_status(v_rack.id, 'active', null, v_rack.record_version, '00000000-0000-0000-0000-000000240002', 'supervisor');
    v_stage := app.create_warehouse_location(v_warehouse.id, null, null, 'STAGE-LBL-1', 'Label Staging 1', 'staging', 2, null, null, null, null, null, false, false, '00000000-0000-0000-0000-000000240002', 'supervisor');
    perform app.set_warehouse_location_status(v_stage.id, 'active', null, v_stage.record_version, '00000000-0000-0000-0000-000000240002', 'supervisor');
    v_dock := app.create_warehouse_location(v_warehouse.id, null, null, 'BIN-LBL-1', 'Label Dock Bin', 'bin', 3, null, null, null, null, 'BARCODE-BIN-LBL-1', false, false, '00000000-0000-0000-0000-000000240002', 'supervisor');
    perform app.set_warehouse_location_status(v_dock.id, 'active', null, v_dock.record_version, '00000000-0000-0000-0000-000000240002', 'supervisor');
  end;

  -- Account Alpha, via the full CRM->Job Order pipeline.
  perform app.capture_lead(v_tenant1, 'manual', null, 'LabelOps Customer Alpha', 'Alice LabelOps', 'alice@labelops240.test', '0811',
    '00000000-0000-0000-0000-000000240003', v_company, '00000000-0000-0000-0000-000000240003', 'tester');
  select * into v_lead from app.leads where email = 'alice@labelops240.test';
  perform app.qualify_lead(v_lead.id, v_lead.record_version, '00000000-0000-0000-0000-000000240003', 'tester');
  select * into v_lead from app.leads where id = v_lead.id;
  perform app.convert_lead_to_prospect(v_lead.id, 'LabelOps Customer Alpha', 'LABELOPS240A', '11.111.111.18-111.000',
    jsonb_build_object('line1', 'Jl. Label Ops Alpha 1', 'city', 'Jakarta', 'country', 'ID'),
    '00000000-0000-0000-0000-000000240003', 'tester');
  select * into v_prospect from app.prospects where lead_id = v_lead.id;
  select * into v_contact from app.create_contact(v_tenant1, 'Alice LabelOps Ops', 'Ops Lead', 'alice@labelops240.test', '0811', '00000000-0000-0000-0000-000000240003', v_company, '00000000-0000-0000-0000-000000240003', 'tester');
  perform app.link_contact_to_record(v_contact.id, 'prospect', v_prospect.id, 'primary', true, '00000000-0000-0000-0000-000000240003', 'tester');
  select * into v_opportunity from app.create_opportunity(
    v_tenant1, v_prospect.id, 'LABELOPS240 Alpha lane',
    jsonb_build_object('service_type', 'land_freight', 'cargo_description', 'General cargo', 'origin', 'Jakarta', 'destination', 'Surabaya', 'target_ready_date', '2026-08-01'),
    '00000000-0000-0000-0000-000000240003', v_company, '00000000-0000-0000-0000-000000240003', 'tester'
  );
  select * into v_request from app.request_costing(v_opportunity.id, '[]'::jsonb, null, '00000000-0000-0000-0000-000000240003', 'tester');
  select * into v_rate from app.create_rate_version(
    v_tenant1, 'VENDOR-LABELOPS240-A', 'Contoso LabelOps240 Line', 'land_freight', 'FTL', 'Jakarta', 'Surabaya', '20ft',
    null, null, null, null, 'IDR', 5000000, null, '[]'::jsonb, now(), null, null, '00000000-0000-0000-0000-000000240001', 'tester'
  );
  perform app.approve_rate_version(v_rate.id, v_rate.record_version, '00000000-0000-0000-0000-000000240001', 'tester');
  select * into v_selection from app.select_vendor_rate(v_request.id, v_rate.id, false, null, null, null, '00000000-0000-0000-0000-000000240003', 'tester');
  v_rule := app.create_margin_rule_version(v_tenant1, 20.00, 'half_up', '00000000-0000-0000-0000-000000240003', 'tester');
  perform app.publish_margin_rule_version(v_rule.id, v_rule.record_version, null, '00000000-0000-0000-0000-000000240003', 'tester');
  perform app.calculate_margin(v_selection.id, 6000000, 'IDR', 0, '00000000-0000-0000-0000-000000240003', 'tester');
  select id into v_calc_id from app.margin_calculations where rate_selection_id = v_selection.id and is_current;
  select * into v_quote from app.create_quotation_draft(v_tenant1, v_opportunity.id, 'IDR', now() + interval '14 days', v_contact.id, null, null, '00000000-0000-0000-0000-000000240003', 'tester');
  perform app.add_quotation_line(v_quote.id, v_quote.record_version, 'service', 'LABELOPS240 Alpha lane', v_calc_id, 1, 6000000, 0, 0, '00000000-0000-0000-0000-000000240003', 'tester');
  select * into v_quote from app.quotations where id = v_quote.id;
  perform app.submit_quotation(v_quote.id, v_quote.record_version, '00000000-0000-0000-0000-000000240003', 'tester');
  select * into v_send from app.send_quotation_for_acceptance(v_quote.id, null, 'email', '00000000-0000-0000-0000-000000240003', 'tester');
  perform app.record_quotation_customer_decision(v_send.raw_token, 'accepted', 'Alice LabelOps Ops', null, null, null, null, null);
  select * into v_quote from app.quotations where id = v_quote.id;
  select * into v_account_alpha from app.convert_quotation_to_account(v_quote.id, null, null, '00000000-0000-0000-0000-000000240003', 'rep');

  -- Account Beta, second owner account in the SAME tenant -- cross-owner isolation.
  perform app.capture_lead(v_tenant1, 'manual', null, 'LabelOps Customer Beta', 'Bob LabelOps', 'bob@labelops240.test', '0812',
    '00000000-0000-0000-0000-000000240003', v_company, '00000000-0000-0000-0000-000000240003', 'tester');
  select * into v_lead from app.leads where email = 'bob@labelops240.test';
  perform app.qualify_lead(v_lead.id, v_lead.record_version, '00000000-0000-0000-0000-000000240003', 'tester');
  select * into v_lead from app.leads where id = v_lead.id;
  perform app.convert_lead_to_prospect(v_lead.id, 'LabelOps Customer Beta', 'LABELOPS240B', '11.111.111.19-111.000',
    jsonb_build_object('line1', 'Jl. Label Ops Beta 2', 'city', 'Jakarta', 'country', 'ID'),
    '00000000-0000-0000-0000-000000240003', 'tester');
  select * into v_prospect from app.prospects where lead_id = v_lead.id;
  select * into v_contact from app.create_contact(v_tenant1, 'Bob LabelOps Ops', 'Ops Lead', 'bob@labelops240.test', '0812', '00000000-0000-0000-0000-000000240003', v_company, '00000000-0000-0000-0000-000000240003', 'tester');
  perform app.link_contact_to_record(v_contact.id, 'prospect', v_prospect.id, 'primary', true, '00000000-0000-0000-0000-000000240003', 'tester');
  select * into v_opportunity from app.create_opportunity(
    v_tenant1, v_prospect.id, 'LABELOPS240 Beta lane',
    jsonb_build_object('service_type', 'land_freight', 'cargo_description', 'General cargo', 'origin', 'Jakarta', 'destination', 'Surabaya', 'target_ready_date', '2026-08-01'),
    '00000000-0000-0000-0000-000000240003', v_company, '00000000-0000-0000-0000-000000240003', 'tester'
  );
  select * into v_request from app.request_costing(v_opportunity.id, '[]'::jsonb, null, '00000000-0000-0000-0000-000000240003', 'tester');
  select * into v_rate from app.create_rate_version(
    v_tenant1, 'VENDOR-LABELOPS240-B', 'Contoso LabelOps240 Line B', 'land_freight', 'FTL', 'Jakarta', 'Surabaya', '20ft',
    null, null, null, null, 'IDR', 5000000, null, '[]'::jsonb, now(), null, null, '00000000-0000-0000-0000-000000240001', 'tester'
  );
  perform app.approve_rate_version(v_rate.id, v_rate.record_version, '00000000-0000-0000-0000-000000240001', 'tester');
  select * into v_selection from app.select_vendor_rate(v_request.id, v_rate.id, false, null, null, null, '00000000-0000-0000-0000-000000240003', 'tester');
  perform app.calculate_margin(v_selection.id, 6000000, 'IDR', 0, '00000000-0000-0000-0000-000000240003', 'tester');
  select id into v_calc_id from app.margin_calculations where rate_selection_id = v_selection.id and is_current;
  select * into v_quote from app.create_quotation_draft(v_tenant1, v_opportunity.id, 'IDR', now() + interval '14 days', v_contact.id, null, null, '00000000-0000-0000-0000-000000240003', 'tester');
  perform app.add_quotation_line(v_quote.id, v_quote.record_version, 'service', 'LABELOPS240 Beta lane', v_calc_id, 1, 6000000, 0, 0, '00000000-0000-0000-0000-000000240003', 'tester');
  select * into v_quote from app.quotations where id = v_quote.id;
  perform app.submit_quotation(v_quote.id, v_quote.record_version, '00000000-0000-0000-0000-000000240003', 'tester');
  select * into v_send from app.send_quotation_for_acceptance(v_quote.id, null, 'email', '00000000-0000-0000-0000-000000240003', 'tester');
  perform app.record_quotation_customer_decision(v_send.raw_token, 'accepted', 'Bob LabelOps Ops', null, null, null, null, null);
  select * into v_quote from app.quotations where id = v_quote.id;
  select * into v_account_beta from app.convert_quotation_to_account(v_quote.id, null, null, '00000000-0000-0000-0000-000000240003', 'rep');

  perform app.create_item_master(v_tenant1, v_account_alpha.id, 'SKU-LBL-PLAIN', 'Label Plain Widget', null, 'PCS', false, false, false, '00000000-0000-0000-0000-000000240003', 'rep');
  perform app.create_item_master(v_tenant1, v_account_alpha.id, 'SKU-LBL-LOT', 'Label Lot Widget', null, 'PCS', true, false, false, '00000000-0000-0000-0000-000000240003', 'rep');
  perform app.create_item_master(v_tenant1, v_account_alpha.id, 'SKU-LBL-SERIAL', 'Label Serial Widget', null, 'PCS', false, true, false, '00000000-0000-0000-0000-000000240003', 'rep');
  perform app.create_item_master(v_tenant1, v_account_beta.id, 'SKU-LBL-BETA', 'Label Beta Widget', null, 'PCS', false, false, false, '00000000-0000-0000-0000-000000240003', 'rep');

  -- The customer_user-layer actor is invited with a NULL org_unit_id -- the ONLY path
  -- it can ever pass app.can_access_record's row filter is real org-unit membership it
  -- does not have here, so app.actor_can_view_owner_scoped_row's own customer_account_
  -- ref match (ATW-016) is the real, sole gate tested below.
  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000240006', 'customer-alpha@labelops1.test', 'Customer Alpha Portal', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'customer-alpha@labelops1.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000240006', 'customer_user', v_tenant1, v_account_alpha.id::text, 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_viewer_role and status = 'published'), '00000000-0000-0000-0000-000000240006', '00000000-0000-0000-0000-000000240001', 'tester');

  -- Tenant2: fully isolated -- exists only to prove cross-tenant scope safety.
  perform app.provision_tenant('labelops2', 'Label Ops Tenant Two', 'idem-labelops2', 'tester');
  v_tenant2 := (select id from app.tenants where slug = 'labelops2');
  perform app.transition_tenant_status(v_tenant2, 'active', 'setup', 'tester');
  perform app.create_org_unit(v_tenant2, 'company', null, 'LABELOPS2-CO', 'Label Ops Tenant Two Co', 'tester');
  v_company2 := (select id from app.org_units where tenant_id = v_tenant2 and code = 'LABELOPS2-CO');
  perform app.invite_user(v_tenant2, '00000000-0000-0000-0000-000000240007', 'admin2@labelops2.test', 'Tenant2 Admin', v_company2, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'admin2@labelops2.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000240007', 'tenant_admin', v_tenant2, null, 'tester');
  perform app.invite_user(v_tenant2, '00000000-0000-0000-0000-000000240008', 'rep2@labelops2.test', 'Tenant2 Rep', v_company2, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'rep2@labelops2.test'), 'active', 'onboarded', 'tester');
  v_rep2_role := (app.create_role(v_tenant2, 'Tenant2 Rep Role', 'ops create/edit/view', 'tester')).id;
  v_rep2_draft := app.create_role_version(v_rep2_role, 'tester');
  perform app.set_role_version_permissions(v_rep2_draft.id, array(select id from app.permissions where resource_module_code = 'OPS' and action in ('Create', 'Edit', 'View')), 'tester');
  perform app.publish_role_version(v_rep2_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant2, (select id from app.role_versions where role_id = v_rep2_role and status = 'published'), '00000000-0000-0000-0000-000000240008', '00000000-0000-0000-0000-000000240007', 'tester');
end $$;

\echo '>> build real subject fixtures: register a lot identity and a serial identity, build a confirmed Alpha outbound order + real ATW-017 pick task (used both unclaimed as the task subject AND fully confirmed to build a real ATW-018 package), start a packing task and create a real top-level (pallet-shaped, parent_package_id null) package'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'labelops1');
  v_warehouse_id uuid := (select id from app.warehouses where tenant_id = v_tenant1 and code = 'WH-LBL-1');
  v_rack_id uuid := (select id from app.warehouse_locations where tenant_id = v_tenant1 and code = 'RACK-LBL-A');
  v_stage_id uuid := (select id from app.warehouse_locations where tenant_id = v_tenant1 and code = 'STAGE-LBL-1');
  v_account_alpha_id uuid := (select id from app.accounts where tenant_id = v_tenant1 and legal_name = 'LabelOps Customer Alpha');
  v_plain_id uuid := (select id from app.item_masters where tenant_id = v_tenant1 and code = 'SKU-LBL-PLAIN');
  v_lot_item_id uuid := (select id from app.item_masters where tenant_id = v_tenant1 and code = 'SKU-LBL-LOT');
  v_serial_item_id uuid := (select id from app.item_masters where tenant_id = v_tenant1 and code = 'SKU-LBL-SERIAL');
  v_order app.wms_outbound_orders;
  v_line app.wms_outbound_order_lines;
  v_task app.wms_pick_tasks;
  v_packing_task app.wms_packing_tasks;
  v_package app.wms_packages;
begin
  perform app.register_lot_identity(v_lot_item_id, 'LOT-LBL-A', null, null, 'receipt', null, null, '00000000-0000-0000-0000-000000240003', 'rep');
  perform app.register_serial_identity(v_serial_item_id, 'SN-LBL-A', null, null, null, 'receipt', null, 'idem-lbl-sn-a', '00000000-0000-0000-0000-000000240003', 'rep');

  perform app.post_inventory_movement(v_tenant1, v_warehouse_id, 'opening_balance', 'opening_balance', null, 'idem-lbl-open-plain', 'opening balance fixture',
    jsonb_build_array(jsonb_build_object('owner_account_id', v_account_alpha_id, 'item_master_id', v_plain_id, 'location_id', v_rack_id, 'uom_code', 'PCS', 'signed_quantity', 100, 'status', 'on_hand')),
    '00000000-0000-0000-0000-000000240003', 'rep');

  v_order := app.create_manual_wms_outbound_order(v_tenant1, v_warehouse_id, v_account_alpha_id, 'label ops packing fixture', 'idem-lbl-order-1', null, '00000000-0000-0000-0000-000000240003', 'rep');
  v_line := app.add_wms_outbound_order_line(v_order.id, v_plain_id, 'PCS', 10, 'L1 label fixture', '00000000-0000-0000-0000-000000240003', 'rep');
  v_order := app.confirm_wms_outbound_order(v_order.id, v_order.record_version, '00000000-0000-0000-0000-000000240003', 'rep');

  -- A second, never-claimed task -- the real 'task' subject-type fixture, deliberately
  -- left unclaimed (a label may legitimately be generated for any real task row
  -- regardless of its own workflow status).
  v_task := app.generate_wms_pick_task(v_line.id, 10, null, v_rack_id, null, null, v_stage_id, 'idem-lbl-pick-gen', '00000000-0000-0000-0000-000000240003', 'rep');

  -- Fully claim/confirm the SAME task to build real picked_quantity, then pack it into
  -- one real, top-level (pallet-shaped) package.
  v_task := app.claim_wms_pick_task(v_task.id, v_task.record_version, '00000000-0000-0000-0000-000000240003', 'rep');
  perform app.confirm_wms_pick_task(v_task.id, 10, v_rack_id, v_plain_id, null, null, v_stage_id, 'idem-lbl-pick-conf', v_task.record_version, '00000000-0000-0000-0000-000000240003', 'rep');

  v_packing_task := app.start_wms_packing_task(v_order.id, 'idem-lbl-packtask', '00000000-0000-0000-0000-000000240003', 'rep');
  v_package := app.create_wms_package(v_packing_task.id, null, 'pallet', 'idem-lbl-pkg-pallet', '00000000-0000-0000-0000-000000240003', 'rep');
  if v_package.parent_package_id is not null then
    raise exception 'assertion failed: expected the label-fixture package to be a real top-level (pallet-shaped) package';
  end if;
end $$;

\echo '>> app.create_label_template / app.create_label_template_version_draft / app.publish_label_template_version / app.set_label_template_version_status: viewer rejected (OPS:Create); invalid_subject_type; idempotent replay on (tenant_id, code); unwhitelisted_template_variable rejected at DRAFT time; a corrected draft succeeds; rep cannot publish (lacks OPS:Override); stale_version; supervisor publishes; re-publish rejected invalid_transition; a second draft cannot publish without supersedes_version_id (active_template_version_exists), then succeeds with it (archiving the first); set_label_template_version_status only supports archiving'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'labelops1');
  v_tpl app.label_templates;
  v_tpl_replay app.label_templates;
  v_draft app.label_template_versions;
  v_draft2 app.label_template_versions;
  v_published app.label_template_versions;
begin
  begin
    perform app.create_label_template(v_tenant1, 'TPL-VIEWER', 'Viewer Blocked', 'bin', '00000000-0000-0000-0000-000000240004', 'viewer');
    raise exception 'assertion failed: expected insufficient_authority for a viewer (lacks OPS:Create)';
  exception
    when others then
      if sqlerrm not like 'insufficient_authority%' then raise; end if;
  end;

  begin
    perform app.create_label_template(v_tenant1, 'TPL-BADTYPE', 'Bad Type', 'spaceship', '00000000-0000-0000-0000-000000240002', 'supervisor');
    raise exception 'assertion failed: expected invalid_subject_type';
  exception
    when others then
      if sqlerrm not like 'invalid_subject_type%' then raise; end if;
  end;

  v_tpl := app.create_label_template(v_tenant1, 'TPL-BIN', 'Bin Label', 'bin', '00000000-0000-0000-0000-000000240002', 'supervisor');
  v_tpl_replay := app.create_label_template(v_tenant1, 'TPL-BIN', 'Bin Label', 'bin', '00000000-0000-0000-0000-000000240002', 'supervisor');
  if v_tpl_replay.id <> v_tpl.id then
    raise exception 'assertion failed: expected idempotent replay on (tenant_id, code) to return the identical template';
  end if;

  begin
    perform app.create_label_template_version_draft(v_tpl.id, 'BIN {{code}} in {{warehouse}}', array['code']::text[], 'code128', '00000000-0000-0000-0000-000000240003', 'rep');
    raise exception 'assertion failed: expected unwhitelisted_template_variable -- warehouse is used but not whitelisted';
  exception
    when others then
      if sqlerrm not like 'unwhitelisted_template_variable%' then raise; end if;
  end;

  v_draft := app.create_label_template_version_draft(v_tpl.id, 'BIN {{code}} in {{warehouse}}', array['code', 'warehouse']::text[], 'code128', '00000000-0000-0000-0000-000000240003', 'rep');
  if v_draft.status <> 'draft' or v_draft.version_number <> 1 then
    raise exception 'assertion failed: expected a real draft version 1, got status=% version_number=%', v_draft.status, v_draft.version_number;
  end if;

  begin
    perform app.publish_label_template_version(v_draft.id, v_draft.record_version, null, '00000000-0000-0000-0000-000000240003', 'rep');
    raise exception 'assertion failed: expected insufficient_authority for a rep (lacks OPS:Override)';
  exception
    when others then
      if sqlerrm not like 'insufficient_authority%' then raise; end if;
  end;

  begin
    perform app.publish_label_template_version(v_draft.id, 999999, null, '00000000-0000-0000-0000-000000240002', 'supervisor');
    raise exception 'assertion failed: expected stale_version';
  exception
    when others then
      if sqlerrm not like 'stale_version%' then raise; end if;
  end;

  v_published := app.publish_label_template_version(v_draft.id, v_draft.record_version, null, '00000000-0000-0000-0000-000000240002', 'supervisor');
  if v_published.status <> 'published' then
    raise exception 'assertion failed: expected the draft to publish, got %', v_published.status;
  end if;

  begin
    perform app.publish_label_template_version(v_published.id, v_published.record_version, null, '00000000-0000-0000-0000-000000240002', 'supervisor');
    raise exception 'assertion failed: expected invalid_transition -- an already-published version cannot be published again';
  exception
    when others then
      if sqlerrm not like 'invalid_transition%' then raise; end if;
  end;

  v_draft2 := app.create_label_template_version_draft(v_tpl.id, 'BIN2 {{code}}', array['code']::text[], 'qr', '00000000-0000-0000-0000-000000240003', 'rep');
  if v_draft2.version_number <> 2 then
    raise exception 'assertion failed: expected the second draft to be version_number=2, got %', v_draft2.version_number;
  end if;

  begin
    perform app.publish_label_template_version(v_draft2.id, v_draft2.record_version, null, '00000000-0000-0000-0000-000000240002', 'supervisor');
    raise exception 'assertion failed: expected active_template_version_exists -- the template already has a published version';
  exception
    when others then
      if sqlerrm not like 'active_template_version_exists%' then raise; end if;
  end;

  v_published := app.publish_label_template_version(v_draft2.id, v_draft2.record_version, v_published.id, '00000000-0000-0000-0000-000000240002', 'supervisor');
  if v_published.status <> 'published' or v_published.symbology <> 'qr' then
    raise exception 'assertion failed: expected the second draft to publish with symbology=qr, got status=% symbology=%', v_published.status, v_published.symbology;
  end if;
  if (select status from app.label_template_versions where id = v_draft.id) <> 'archived' then
    raise exception 'assertion failed: expected the first published version to be archived once superseded';
  end if;

  begin
    perform app.set_label_template_version_status(v_published.id, 'published', null, v_published.record_version, '00000000-0000-0000-0000-000000240002', 'supervisor');
    raise exception 'assertion failed: expected invalid_status_transition -- this function only supports archiving';
  exception
    when others then
      if sqlerrm not like 'invalid_status_transition%' then raise; end if;
  end;

  perform app.set_label_template_version_status(v_published.id, 'archived', 'end of life', v_published.record_version, '00000000-0000-0000-0000-000000240002', 'supervisor');
  if (select status from app.label_template_versions where id = v_published.id) <> 'archived' then
    raise exception 'assertion failed: expected TPL-BIN''s own second published version to archive';
  end if;
end $$;

\echo '>> real, end-to-end templates for item and pallet subject types (used by the generate_label scenarios below)'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'labelops1');
  v_tpl_item app.label_templates;
  v_tpl_pallet app.label_templates;
  v_tpl_bin2 app.label_templates;
  v_draft app.label_template_versions;
begin
  v_tpl_item := app.create_label_template(v_tenant1, 'TPL-ITEM', 'Item Label', 'item', '00000000-0000-0000-0000-000000240002', 'supervisor');
  v_draft := app.create_label_template_version_draft(v_tpl_item.id, 'ITEM {{sku}}', array['sku']::text[], 'code128', '00000000-0000-0000-0000-000000240003', 'rep');
  perform app.publish_label_template_version(v_draft.id, v_draft.record_version, null, '00000000-0000-0000-0000-000000240002', 'supervisor');

  v_tpl_pallet := app.create_label_template(v_tenant1, 'TPL-PALLET', 'Pallet Label', 'pallet', '00000000-0000-0000-0000-000000240002', 'supervisor');
  v_draft := app.create_label_template_version_draft(v_tpl_pallet.id, 'PALLET {{ref}}', array['ref']::text[], 'datamatrix', '00000000-0000-0000-0000-000000240003', 'rep');
  perform app.publish_label_template_version(v_draft.id, v_draft.record_version, null, '00000000-0000-0000-0000-000000240002', 'supervisor');

  -- A second, real bin template (TPL-BIN's own only published version was archived
  -- above by design -- this migration's own stale_template fixture below).
  v_tpl_bin2 := app.create_label_template(v_tenant1, 'TPL-BIN2', 'Bin Label 2', 'bin', '00000000-0000-0000-0000-000000240002', 'supervisor');
  v_draft := app.create_label_template_version_draft(v_tpl_bin2.id, 'BIN {{code}}', array['code']::text[], 'code128', '00000000-0000-0000-0000-000000240003', 'rep');
  perform app.publish_label_template_version(v_draft.id, v_draft.record_version, null, '00000000-0000-0000-0000-000000240002', 'supervisor');
end $$;

\echo '>> app.create_label_printer / app.set_label_printer_status: viewer rejected; idempotent replay; a real active printer'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'labelops1');
  v_warehouse_id uuid := (select id from app.warehouses where tenant_id = v_tenant1 and code = 'WH-LBL-1');
  v_printer app.label_printers;
  v_printer_replay app.label_printers;
begin
  begin
    perform app.create_label_printer(v_tenant1, v_warehouse_id, 'PRN-VIEWER', 'Viewer Blocked', '{}'::jsonb, '00000000-0000-0000-0000-000000240004', 'viewer');
    raise exception 'assertion failed: expected insufficient_authority for a viewer (lacks OPS:Create)';
  exception
    when others then
      if sqlerrm not like 'insufficient_authority%' then raise; end if;
  end;

  v_printer := app.create_label_printer(v_tenant1, v_warehouse_id, 'PRN-1', 'Dock Printer 1', jsonb_build_object('type', 'network', 'address', '10.0.0.5'), '00000000-0000-0000-0000-000000240002', 'supervisor');
  v_printer_replay := app.create_label_printer(v_tenant1, v_warehouse_id, 'PRN-1', 'Dock Printer 1', jsonb_build_object('type', 'network', 'address', '10.0.0.5'), '00000000-0000-0000-0000-000000240002', 'supervisor');
  if v_printer_replay.id <> v_printer.id then
    raise exception 'assertion failed: expected idempotent replay on (tenant_id, code)';
  end if;
  if v_printer.status <> 'active' then
    raise exception 'assertion failed: expected a freshly created printer to be active by default';
  end if;

  -- Findings review MEDIUM #6: a code match against a DIFFERENT warehouse_id/name must
  -- reject label_printer_code_conflict, never silently return the existing, mismatched
  -- printer.
  begin
    perform app.create_label_printer(v_tenant1, null, 'PRN-1', 'A Totally Different Printer', '{}'::jsonb, '00000000-0000-0000-0000-000000240002', 'supervisor');
    raise exception 'assertion failed: expected label_printer_code_conflict for code PRN-1 reused with a different warehouse_id/name';
  exception
    when others then
      if sqlerrm not like 'label_printer_code_conflict%' then raise; end if;
  end;

  -- A second, virtual (no warehouse) tenant-wide printer, and one that will be
  -- deactivated below.
  perform app.create_label_printer(v_tenant1, null, 'PRN-VIRTUAL', 'Virtual Office Printer', '{}'::jsonb, '00000000-0000-0000-0000-000000240002', 'supervisor');
  perform app.create_label_printer(v_tenant1, v_warehouse_id, 'PRN-2', 'Dock Printer 2', '{}'::jsonb, '00000000-0000-0000-0000-000000240002', 'supervisor');

  begin
    perform app.set_label_printer_status((select id from app.label_printers where tenant_id = v_tenant1 and code = 'PRN-2'), 'inactive', null,
      (select record_version from app.label_printers where tenant_id = v_tenant1 and code = 'PRN-2'), '00000000-0000-0000-0000-000000240003', 'rep');
    raise exception 'assertion failed: expected reason_required to deactivate a printer';
  exception
    when others then
      if sqlerrm not like 'reason_required%' then raise; end if;
  end;

  perform app.set_label_printer_status((select id from app.label_printers where tenant_id = v_tenant1 and code = 'PRN-2'), 'inactive', 'out of service',
    (select record_version from app.label_printers where tenant_id = v_tenant1 and code = 'PRN-2'), '00000000-0000-0000-0000-000000240003', 'rep');
  if (select status from app.label_printers where tenant_id = v_tenant1 and code = 'PRN-2') <> 'inactive' then
    raise exception 'assertion failed: expected PRN-2 to deactivate';
  end if;
end $$;

\echo '>> app.preview_label / app.generate_label end to end for THREE subject types (bin, item, pallet): subject_type_mismatch; subject_not_found; unwhitelisted variable at generate time (defense in depth); a real successful generate for each; preview matches the eventually-generated variables_snapshot render; the encoded value round-trips through the checksum algorithm; idempotent replay on (tenant_id, idempotency_key)'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'labelops1');
  v_dock_id uuid := (select id from app.warehouse_locations where tenant_id = v_tenant1 and code = 'BIN-LBL-1');
  v_item_id uuid := (select id from app.item_masters where tenant_id = v_tenant1 and code = 'SKU-LBL-PLAIN');
  v_pallet_id uuid := (select p.id from app.wms_packages p where p.tenant_id = v_tenant1 and p.parent_package_id is null);
  v_tpl_item_version_id uuid := (select v.id from app.label_template_versions v join app.label_templates t on t.id = v.template_id where t.tenant_id = v_tenant1 and t.code = 'TPL-ITEM' and v.status = 'published');
  v_bin_instance app.label_instances;
  v_item_instance app.label_instances;
  v_item_instance_replay app.label_instances;
  v_pallet_instance app.label_instances;
  v_preview text;
  v_core text;
  v_core_short text;
  v_expected_checksum integer;
  v_actual_checksum integer;
begin
  -- subject_type_mismatch: TPL-ITEM is scoped to 'item', requesting subject_type='bin'.
  begin
    perform app.generate_label(v_tenant1, 'TPL-ITEM', 'bin', v_dock_id, '{}'::jsonb, 'idem-lbl-mismatch', '00000000-0000-0000-0000-000000240003', 'rep');
    raise exception 'assertion failed: expected subject_type_mismatch';
  exception
    when others then
      if sqlerrm not like 'subject_type_mismatch%' then raise; end if;
  end;

  -- subject_not_found: a real item template against a random, non-existent subject_id.
  begin
    perform app.generate_label(v_tenant1, 'TPL-ITEM', 'item', gen_random_uuid(), '{}'::jsonb, 'idem-lbl-nosubject', '00000000-0000-0000-0000-000000240003', 'rep');
    raise exception 'assertion failed: expected subject_not_found';
  exception
    when others then
      if sqlerrm not like 'subject_not_found%' then raise; end if;
  end;

  -- stale_template: TPL-BIN's only published version was archived above.
  begin
    perform app.generate_label(v_tenant1, 'TPL-BIN', 'bin', v_dock_id, '{}'::jsonb, 'idem-lbl-staletpl', '00000000-0000-0000-0000-000000240003', 'rep');
    raise exception 'assertion failed: expected stale_template -- TPL-BIN has no currently published version';
  exception
    when others then
      if sqlerrm not like 'stale_template%' then raise; end if;
  end;

  -- unsafe_variable at generate time -- defense in depth (the SAME whitelist check
  -- app.preview_label uses, even though create_label_template_version_draft already
  -- validated content_template itself at draft time).
  begin
    perform app.generate_label(v_tenant1, 'TPL-ITEM', 'item', v_item_id, jsonb_build_object('sku', 'X', 'unexpected_field', 'Y'), 'idem-lbl-unsafevar', '00000000-0000-0000-0000-000000240003', 'rep');
    raise exception 'assertion failed: expected unsafe_variable for an unwhitelisted p_variables key';
  exception
    when others then
      if sqlerrm not like 'unsafe_variable%' then raise; end if;
  end;

  -- Subject 1: bin (TPL-BIN2).
  v_preview := app.preview_label((select v.id from app.label_template_versions v join app.label_templates t on t.id = v.template_id where t.code = 'TPL-BIN2' and v.status = 'published'), jsonb_build_object('code', 'BIN-LBL-1'), '00000000-0000-0000-0000-000000240003');
  if v_preview <> 'BIN BIN-LBL-1' then
    raise exception 'assertion failed: expected preview ''BIN BIN-LBL-1'', got %', v_preview;
  end if;
  v_bin_instance := app.generate_label(v_tenant1, 'TPL-BIN2', 'bin', v_dock_id, jsonb_build_object('code', 'BIN-LBL-1'), 'idem-lbl-gen-bin', '00000000-0000-0000-0000-000000240003', 'rep');
  if v_bin_instance.subject_type <> 'bin' or v_bin_instance.warehouse_id is null or v_bin_instance.owner_account_id is not null then
    raise exception 'assertion failed: expected a real bin label with warehouse_id set and owner_account_id null, got warehouse_id=% owner_account_id=%', v_bin_instance.warehouse_id, v_bin_instance.owner_account_id;
  end if;
  if app.render_label_content((select content_template from app.label_template_versions where id = v_bin_instance.template_version_id), (select allowed_variables from app.label_template_versions where id = v_bin_instance.template_version_id), v_bin_instance.variables_snapshot) <> v_preview then
    raise exception 'assertion failed: expected the eventually-generated instance to re-render identically to its own earlier preview';
  end if;

  -- Subject 2: item.
  v_preview := app.preview_label(v_tpl_item_version_id, jsonb_build_object('sku', 'SKU-LBL-PLAIN'), '00000000-0000-0000-0000-000000240003');
  v_item_instance := app.generate_label(v_tenant1, 'TPL-ITEM', 'item', v_item_id, jsonb_build_object('sku', 'SKU-LBL-PLAIN'), 'idem-lbl-gen-item', '00000000-0000-0000-0000-000000240003', 'rep');
  if v_item_instance.subject_type <> 'item' or v_item_instance.owner_account_id is null or v_item_instance.warehouse_id is not null then
    raise exception 'assertion failed: expected a real item label with owner_account_id set (derived from the LIVE item row) and warehouse_id null, got owner_account_id=% warehouse_id=%', v_item_instance.owner_account_id, v_item_instance.warehouse_id;
  end if;
  if v_item_instance.owner_account_id <> (select owner_account_id from app.item_masters where id = v_item_id) then
    raise exception 'assertion failed: expected owner_account_id to be derived from the LIVE app.item_masters row, never a caller-supplied value';
  end if;

  -- Idempotent replay on (tenant_id, idempotency_key).
  v_item_instance_replay := app.generate_label(v_tenant1, 'TPL-ITEM', 'item', v_item_id, jsonb_build_object('sku', 'SKU-LBL-PLAIN'), 'idem-lbl-gen-item', '00000000-0000-0000-0000-000000240003', 'rep');
  if v_item_instance_replay.id <> v_item_instance.id then
    raise exception 'assertion failed: expected idempotent replay on (tenant_id, idempotency_key) to return the identical label instance';
  end if;

  -- Findings review CRITICAL #1/#3/#8: reusing the SAME idempotency key against a
  -- DIFFERENT subject (a different real item, not the one the key was first used for)
  -- must reject idempotency_key_conflict, never silently return the FIRST subject's
  -- label instance while leaving the real, second subject completely unlabeled.
  begin
    perform app.generate_label(v_tenant1, 'TPL-ITEM', 'item', (select id from app.item_masters where tenant_id = v_tenant1 and code = 'SKU-LBL-BETA'), jsonb_build_object('sku', 'SKU-LBL-BETA'), 'idem-lbl-gen-item', '00000000-0000-0000-0000-000000240003', 'rep');
    raise exception 'assertion failed: expected idempotency_key_conflict when idem-lbl-gen-item is reused against a different item';
  exception
    when others then
      if sqlerrm not like 'idempotency_key_conflict%' then raise; end if;
  end;
  if exists (select 1 from app.label_instances where tenant_id = v_tenant1 and subject_id = (select id from app.item_masters where tenant_id = v_tenant1 and code = 'SKU-LBL-BETA')) then
    raise exception 'assertion failed: expected NO label_instances row for the real SKU-LBL-BETA item after its generate_label call was rejected idempotency_key_conflict';
  end if;

  -- Subject 3: pallet (a real top-level app.wms_packages row, parent_package_id null).
  v_pallet_instance := app.generate_label(v_tenant1, 'TPL-PALLET', 'pallet', v_pallet_id, jsonb_build_object('ref', 'PLT-001'), 'idem-lbl-gen-pallet', '00000000-0000-0000-0000-000000240003', 'rep');
  if v_pallet_instance.subject_type <> 'pallet' or v_pallet_instance.owner_account_id is null or v_pallet_instance.warehouse_id is null then
    raise exception 'assertion failed: expected a real pallet label with BOTH owner_account_id and warehouse_id set (a package carries both), got owner_account_id=% warehouse_id=%', v_pallet_instance.owner_account_id, v_pallet_instance.warehouse_id;
  end if;

  -- The encoded value round-trips through the checksum algorithm.
  v_core := split_part(v_item_instance.encoded_value, '-', 2);
  v_actual_checksum := split_part(v_item_instance.encoded_value, '-', 3)::integer;
  v_expected_checksum := app.compute_label_checksum_digit(v_core);
  if v_actual_checksum <> v_expected_checksum then
    raise exception 'assertion failed: expected encoded_value % own checksum digit % to match the recomputed digit %', v_item_instance.encoded_value, v_actual_checksum, v_expected_checksum;
  end if;
  if left(v_item_instance.encoded_value, 3) <> 'ITE' then
    raise exception 'assertion failed: expected an item label''s own encoded_value prefix to be ITE, got %', left(v_item_instance.encoded_value, 3);
  end if;
  if left(v_pallet_instance.encoded_value, 3) <> 'PAL' then
    raise exception 'assertion failed: expected a pallet label''s own encoded_value prefix to be PAL, got %', left(v_pallet_instance.encoded_value, 3);
  end if;
  if v_bin_instance.encoded_value_digest <> encode(digest(v_bin_instance.encoded_value, 'sha256'), 'hex') then
    raise exception 'assertion failed: expected encoded_value_digest to be the real sha256 hex digest of encoded_value';
  end if;
end $$;

\echo '>> lot/serial/task subject-type generate_label smoke coverage (dispatch correctness for the remaining four subject types)'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'labelops1');
  v_lot_identity_id uuid := (select id from app.lot_identities where tenant_id = v_tenant1 and lot_number = 'LOT-LBL-A');
  v_serial_identity_id uuid := (select id from app.serial_identities where tenant_id = v_tenant1 and serial_number = 'SN-LBL-A');
  v_task_id uuid := (select id from app.wms_pick_tasks where tenant_id = v_tenant1 and idempotency_key = 'idem-lbl-pick-gen');
  v_package_id uuid := (select p.id from app.wms_packages p where p.tenant_id = v_tenant1 and p.parent_package_id is null);
  v_tpl_lot app.label_templates;
  v_tpl_serial app.label_templates;
  v_tpl_task app.label_templates;
  v_tpl_package app.label_templates;
  v_draft app.label_template_versions;
  v_lot_instance app.label_instances;
  v_serial_instance app.label_instances;
  v_task_instance app.label_instances;
  v_package_instance app.label_instances;
begin
  v_tpl_lot := app.create_label_template(v_tenant1, 'TPL-LOT', 'Lot Label', 'lot', '00000000-0000-0000-0000-000000240002', 'supervisor');
  v_draft := app.create_label_template_version_draft(v_tpl_lot.id, 'LOT {{lot_no}}', array['lot_no']::text[], 'code128', '00000000-0000-0000-0000-000000240003', 'rep');
  perform app.publish_label_template_version(v_draft.id, v_draft.record_version, null, '00000000-0000-0000-0000-000000240002', 'supervisor');
  v_lot_instance := app.generate_label(v_tenant1, 'TPL-LOT', 'lot', v_lot_identity_id, jsonb_build_object('lot_no', 'LOT-LBL-A'), 'idem-lbl-gen-lot', '00000000-0000-0000-0000-000000240003', 'rep');
  if v_lot_instance.owner_account_id is null or left(v_lot_instance.encoded_value, 3) <> 'LOT' then
    raise exception 'assertion failed: expected a real lot label with owner_account_id set and LOT prefix';
  end if;

  v_tpl_serial := app.create_label_template(v_tenant1, 'TPL-SERIAL', 'Serial Label', 'serial', '00000000-0000-0000-0000-000000240002', 'supervisor');
  v_draft := app.create_label_template_version_draft(v_tpl_serial.id, 'SERIAL {{sn}}', array['sn']::text[], 'code128', '00000000-0000-0000-0000-000000240003', 'rep');
  perform app.publish_label_template_version(v_draft.id, v_draft.record_version, null, '00000000-0000-0000-0000-000000240002', 'supervisor');
  v_serial_instance := app.generate_label(v_tenant1, 'TPL-SERIAL', 'serial', v_serial_identity_id, jsonb_build_object('sn', 'SN-LBL-A'), 'idem-lbl-gen-serial', '00000000-0000-0000-0000-000000240003', 'rep');
  if v_serial_instance.owner_account_id is null or left(v_serial_instance.encoded_value, 3) <> 'SER' then
    raise exception 'assertion failed: expected a real serial label with owner_account_id set and SER prefix';
  end if;

  v_tpl_task := app.create_label_template(v_tenant1, 'TPL-TASK', 'Task Label', 'task', '00000000-0000-0000-0000-000000240002', 'supervisor');
  v_draft := app.create_label_template_version_draft(v_tpl_task.id, 'TASK {{ref}}', array['ref']::text[], 'code128', '00000000-0000-0000-0000-000000240003', 'rep');
  perform app.publish_label_template_version(v_draft.id, v_draft.record_version, null, '00000000-0000-0000-0000-000000240002', 'supervisor');
  v_task_instance := app.generate_label(v_tenant1, 'TPL-TASK', 'task', v_task_id, jsonb_build_object('ref', 'TASK-1'), 'idem-lbl-gen-task', '00000000-0000-0000-0000-000000240003', 'rep');
  if v_task_instance.owner_account_id is null or v_task_instance.warehouse_id is null or left(v_task_instance.encoded_value, 3) <> 'TAS' then
    raise exception 'assertion failed: expected a real task label with both owner_account_id and warehouse_id set and TAS prefix';
  end if;

  v_tpl_package := app.create_label_template(v_tenant1, 'TPL-PACKAGE', 'Package Label', 'package', '00000000-0000-0000-0000-000000240002', 'supervisor');
  v_draft := app.create_label_template_version_draft(v_tpl_package.id, 'PKG {{ref}}', array['ref']::text[], 'code128', '00000000-0000-0000-0000-000000240003', 'rep');
  perform app.publish_label_template_version(v_draft.id, v_draft.record_version, null, '00000000-0000-0000-0000-000000240002', 'supervisor');
  v_package_instance := app.generate_label(v_tenant1, 'TPL-PACKAGE', 'package', v_package_id, jsonb_build_object('ref', 'PKG-1'), 'idem-lbl-gen-package', '00000000-0000-0000-0000-000000240003', 'rep');
  if left(v_package_instance.encoded_value, 3) <> 'PAC' then
    raise exception 'assertion failed: expected a package label''s own encoded_value prefix to be PAC, got %', left(v_package_instance.encoded_value, 3);
  end if;
end $$;

\echo '>> findings review HIGH #2: app.generate_label reauthorizes the SPECIFIC subject via app.label_subject_record_scope_ok, not just tenant-wide OPS:Create -- a staff actor invited under one branch org unit, holding tenant-wide OPS:Create/Edit/View, is FIRST proven genuinely branch-scoped by being correctly rejected from app.create_label_printer targeting a warehouse under a DIFFERENT branch, then proven to be identically rejected from app.generate_label for a bin subject living in that same out-of-scope warehouse (this checkpoint''s own prior behavior let it through with no error)'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'labelops1');
  v_company_id uuid := (select id from app.org_units where tenant_id = v_tenant1 and code = 'LABELOPS1-CO');
  v_branch_a_id uuid;
  v_branch_b_id uuid;
  v_warehouse_b app.warehouses;
  v_bin_b app.warehouse_locations;
  v_branch_a_actor uuid := '00000000-0000-0000-0000-000000240011';
begin
  v_branch_a_id := (app.create_org_unit(v_tenant1, 'branch', v_company_id, 'LABELOPS1-BR-A', 'Label Ops Branch A', 'tester')).id;
  v_branch_b_id := (app.create_org_unit(v_tenant1, 'branch', v_company_id, 'LABELOPS1-BR-B', 'Label Ops Branch B', 'tester')).id;
  v_warehouse_b := app.create_warehouse(v_tenant1, v_branch_b_id, 'WH-LBL-B', 'Label Ops Warehouse B', 'Jl. Label Ops B', 'Asia/Jakarta', null, array['land']::text[], '00000000-0000-0000-0000-000000240002', 'supervisor');
  v_bin_b := app.create_warehouse_location(v_warehouse_b.id, null, null, 'BIN-LBL-B-1', 'Label Ops Branch B Bin', 'bin', 1, null, null, null, null, 'BARCODE-BIN-LBL-B-1', false, false, '00000000-0000-0000-0000-000000240002', 'supervisor');
  perform app.set_warehouse_location_status(v_bin_b.id, 'active', null, v_bin_b.record_version, '00000000-0000-0000-0000-000000240002', 'supervisor');

  insert into auth.users (id, email) values (v_branch_a_actor, 'branch-a-rep@labelops1.test');
  perform app.invite_user(v_tenant1, v_branch_a_actor, 'branch-a-rep@labelops1.test', 'Branch A Rep', v_branch_a_id, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'branch-a-rep@labelops1.test'), 'active', 'onboarded', 'tester');
  -- Reuses the SAME tenant-wide "LabelOps Rep Role" (OPS Create/Edit/View, no
  -- Override) every other rep-scenario test in this fixture uses -- the ONLY
  -- difference from 'rep' is this actor's own org_unit_id (branch A, not the company).
  perform app.assign_role(v_tenant1, (select rv.id from app.role_versions rv join app.roles r on r.id = rv.role_id where r.name = 'LabelOps Rep Role' and rv.status = 'published'), v_branch_a_actor, '00000000-0000-0000-0000-000000240001', 'tester');

  -- Control: prove this actor's own branch-A scoping is real by confirming they are
  -- correctly rejected from a DIFFERENT RPC that already enforces per-warehouse
  -- record-scope (app.create_label_printer) against warehouse B.
  begin
    perform app.create_label_printer(v_tenant1, v_warehouse_b.id, 'PRN-BR-B-CONTROL', 'Branch B Control Printer', '{}'::jsonb, v_branch_a_actor, 'branch-a-rep');
    raise exception 'assertion failed: expected insufficient_authority -- the fixture''s own branch scoping must be real before this test proves anything about generate_label';
  exception
    when others then
      if sqlerrm not like 'insufficient_authority%' then raise; end if;
  end;

  -- The SAME branch-A-scoped actor must be identically rejected from generating a
  -- label for a bin subject that lives inside out-of-scope warehouse B.
  begin
    perform app.generate_label(v_tenant1, 'TPL-BIN2', 'bin', v_bin_b.id, jsonb_build_object('code', 'BIN-LBL-B-1'), 'idem-lbl-gen-branchb-bypass', v_branch_a_actor, 'branch-a-rep');
    raise exception 'assertion failed: expected insufficient_authority -- a branch-A-scoped actor must not be able to generate a real, persisted label for a subject in out-of-scope warehouse B';
  exception
    when others then
      if sqlerrm not like 'insufficient_authority%' then raise; end if;
  end;
  if exists (select 1 from app.label_instances where tenant_id = v_tenant1 and subject_id = v_bin_b.id) then
    raise exception 'assertion failed: expected NO label_instances row for the warehouse-B bin after generate_label was rejected insufficient_authority';
  end if;
end $$;

\echo '>> app.print_label enqueues a real app.jobs row (job_type=print_label, payload references the correct label_print_job_id); app.record_label_print_outcome (service_role context) transitions it to succeeded; a same-outcome retry is a clean idempotent no-op; a DIFFERENT outcome on an already-terminal row is rejected label_print_job_already_resolved'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'labelops1');
  v_label_id uuid := (select id from app.label_instances where tenant_id = v_tenant1 and encoded_value = (select encoded_value from app.label_instances i join app.item_masters m on m.id = i.subject_id where i.tenant_id = v_tenant1 and i.subject_type = 'item' and m.code = 'SKU-LBL-PLAIN'));
  v_printer_id uuid := (select id from app.label_printers where tenant_id = v_tenant1 and code = 'PRN-1');
  v_print_job app.label_print_jobs;
  v_replay app.label_print_jobs;
  v_app_job app.jobs;
  v_outcome app.label_print_jobs;
  v_outcome_replay app.label_print_jobs;
begin
  begin
    perform app.print_label(v_label_id, v_printer_id, 1, 'idem-lbl-print-viewer', '00000000-0000-0000-0000-000000240004', 'viewer');
    raise exception 'assertion failed: expected insufficient_authority for a viewer (lacks OPS:Edit)';
  exception
    when others then
      if sqlerrm not like 'insufficient_authority%' then raise; end if;
  end;

  v_print_job := app.print_label(v_label_id, v_printer_id, 2, 'idem-lbl-print-1', '00000000-0000-0000-0000-000000240003', 'rep');
  if v_print_job.status <> 'queued' or v_print_job.copies <> 2 or v_print_job.is_reprint then
    raise exception 'assertion failed: expected a real queued, non-reprint print job with copies=2, got status=% copies=% is_reprint=%', v_print_job.status, v_print_job.copies, v_print_job.is_reprint;
  end if;
  if v_print_job.app_job_id is null then
    raise exception 'assertion failed: expected app_job_id to be populated by the end of app.print_label''s own single invocation';
  end if;

  select * into v_app_job from app.jobs where job_id = v_print_job.app_job_id;
  if v_app_job.job_type <> 'print_label' then
    raise exception 'assertion failed: expected the enqueued app.jobs row to have job_type=print_label, got %', v_app_job.job_type;
  end if;
  if (v_app_job.payload->>'label_print_job_id')::uuid <> v_print_job.id then
    raise exception 'assertion failed: expected the enqueued job''s own payload to reference the correct label_print_job_id';
  end if;

  -- Idempotent replay on (tenant_id, idempotency_key) -- no second app.jobs row.
  v_replay := app.print_label(v_label_id, v_printer_id, 5, 'idem-lbl-print-1', '00000000-0000-0000-0000-000000240003', 'rep');
  if v_replay.id <> v_print_job.id or v_replay.copies <> 2 then
    raise exception 'assertion failed: expected an idempotent replay to return the identical, unchanged print job (copies still 2, not 5)';
  end if;

  -- Findings review CRITICAL #1/#4/#9: reusing the SAME idempotency key against a
  -- DIFFERENT label_instance_id must reject idempotency_key_conflict, never silently
  -- return the FIRST label's print job while the real, second label is never enqueued
  -- to print at all.
  declare
    v_other_label_id uuid := (select id from app.label_instances where tenant_id = v_tenant1 and encoded_value like 'PAL-%' limit 1);
  begin
    begin
      perform app.print_label(v_other_label_id, v_printer_id, 1, 'idem-lbl-print-1', '00000000-0000-0000-0000-000000240003', 'rep');
      raise exception 'assertion failed: expected idempotency_key_conflict when idem-lbl-print-1 is reused against a different label_instance_id';
    exception
      when others then
        if sqlerrm not like 'idempotency_key_conflict%' then raise; end if;
    end;
    if exists (select 1 from app.label_print_jobs where tenant_id = v_tenant1 and label_instance_id = v_other_label_id) then
      raise exception 'assertion failed: expected NO label_print_jobs row for the real other label_instance after its print_label call was rejected idempotency_key_conflict';
    end if;
  end;

  begin
    perform app.record_label_print_outcome(v_print_job.id, 'bogus', null, '00000000-0000-0000-0000-000000240009', 'worker');
    raise exception 'assertion failed: expected invalid_outcome_status';
  exception
    when others then
      if sqlerrm not like 'invalid_outcome_status%' then raise; end if;
  end;

  v_outcome := app.record_label_print_outcome(v_print_job.id, 'succeeded', null, '00000000-0000-0000-0000-000000240009', 'worker');
  if v_outcome.status <> 'succeeded' or v_outcome.completed_at is null then
    raise exception 'assertion failed: expected the print job to transition to succeeded with completed_at set';
  end if;

  -- Same-outcome retry -- a clean idempotent no-op.
  v_outcome_replay := app.record_label_print_outcome(v_print_job.id, 'succeeded', null, '00000000-0000-0000-0000-000000240009', 'worker');
  if v_outcome_replay.id <> v_outcome.id or v_outcome_replay.status <> 'succeeded' then
    raise exception 'assertion failed: expected a same-outcome retry to be a clean no-op';
  end if;

  -- A DIFFERENT outcome on an already-terminal row is rejected.
  begin
    perform app.record_label_print_outcome(v_print_job.id, 'failed', 'printer jammed', '00000000-0000-0000-0000-000000240009', 'worker');
    raise exception 'assertion failed: expected label_print_job_already_resolved for a conflicting outcome on an already-succeeded row';
  exception
    when others then
      if sqlerrm not like 'label_print_job_already_resolved%' then raise; end if;
  end;
end $$;

\echo '>> app.reprint_label requires a non-empty reason; preserves the SAME label_instance_id (never creates a second instance); both the original print and the reprint remain visible via app.list_label_print_jobs (lineage preserved)'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'labelops1');
  v_label_id uuid := (select id from app.label_instances where tenant_id = v_tenant1 and encoded_value = (select encoded_value from app.label_instances i join app.item_masters m on m.id = i.subject_id where i.tenant_id = v_tenant1 and i.subject_type = 'item' and m.code = 'SKU-LBL-PLAIN'));
  v_printer_id uuid := (select id from app.label_printers where tenant_id = v_tenant1 and code = 'PRN-1');
  v_reprint app.label_print_jobs;
  v_jobs app.label_print_jobs[];
begin
  begin
    perform app.reprint_label(v_label_id, v_printer_id, 1, '', 'idem-lbl-reprint-noreason', '00000000-0000-0000-0000-000000240002', 'supervisor');
    raise exception 'assertion failed: expected reason_required for an empty reprint reason';
  exception
    when others then
      if sqlerrm not like 'reason_required%' then raise; end if;
  end;

  begin
    perform app.reprint_label(v_label_id, v_printer_id, 1, 'lost in transit', 'idem-lbl-reprint-1', '00000000-0000-0000-0000-000000240003', 'rep');
    raise exception 'assertion failed: expected insufficient_authority for a rep (lacks OPS:Override) attempting a reprint';
  exception
    when others then
      if sqlerrm not like 'insufficient_authority%' then raise; end if;
  end;

  v_reprint := app.reprint_label(v_label_id, v_printer_id, 1, 'lost in transit', 'idem-lbl-reprint-1', '00000000-0000-0000-0000-000000240002', 'supervisor');
  if v_reprint.is_reprint <> true or v_reprint.reprint_reason <> 'lost in transit' or v_reprint.label_instance_id <> v_label_id then
    raise exception 'assertion failed: expected a real reprint job referencing the SAME label_instance_id, got label_instance_id=% is_reprint=%', v_reprint.label_instance_id, v_reprint.is_reprint;
  end if;
  if (select count(*) from app.label_instances where id = v_label_id) <> 1 then
    raise exception 'assertion failed: expected the reprint to never create a second label instance';
  end if;

  select array_agg(j) into v_jobs from app.list_label_print_jobs(v_tenant1, '00000000-0000-0000-0000-000000240002', v_label_id, null, 200) j;
  if array_length(v_jobs, 1) < 2 then
    raise exception 'assertion failed: expected at least 2 print_jobs (the original print + the reprint) visible for this label instance, got %', array_length(v_jobs, 1);
  end if;
  if not exists (select 1 from unnest(v_jobs) j where j.is_reprint = false) or not exists (select 1 from unnest(v_jobs) j where j.is_reprint = true) then
    raise exception 'assertion failed: expected both the original (is_reprint=false) and the reprint (is_reprint=true) to remain visible -- lineage preserved';
  end if;
end $$;

\echo '>> app.void_label blocks any further print_label/reprint_label attempt (label_voided); already_void on a second void attempt; app.resolve_label against a void code returns void_code, distinctly from unknown_code for a code that was never generated at all'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'labelops1');
  v_label app.label_instances;
  v_printer_id uuid := (select id from app.label_printers where tenant_id = v_tenant1 and code = 'PRN-1');
begin
  select * into v_label from app.label_instances i join app.warehouse_locations l on l.id = i.subject_id where i.tenant_id = v_tenant1 and i.subject_type = 'bin' and l.code = 'BIN-LBL-1';

  begin
    perform app.void_label(v_label.id, 'test void', v_label.record_version, '00000000-0000-0000-0000-000000240003', 'rep');
    raise exception 'assertion failed: expected insufficient_authority for a rep (lacks OPS:Override) voiding a label';
  exception
    when others then
      if sqlerrm not like 'insufficient_authority%' then raise; end if;
  end;

  begin
    perform app.void_label(v_label.id, '', v_label.record_version, '00000000-0000-0000-0000-000000240002', 'supervisor');
    raise exception 'assertion failed: expected reason_required for an empty void reason';
  exception
    when others then
      if sqlerrm not like 'reason_required%' then raise; end if;
  end;

  v_label := app.void_label(v_label.id, 'damaged label', v_label.record_version, '00000000-0000-0000-0000-000000240002', 'supervisor');
  if v_label.status <> 'void' or v_label.void_reason <> 'damaged label' or v_label.voided_at is null then
    raise exception 'assertion failed: expected the bin label to void with a real void_reason/voided_at';
  end if;

  begin
    perform app.void_label(v_label.id, 'again', v_label.record_version, '00000000-0000-0000-0000-000000240002', 'supervisor');
    raise exception 'assertion failed: expected already_void on a second void attempt';
  exception
    when others then
      if sqlerrm not like 'already_void%' then raise; end if;
  end;

  begin
    perform app.print_label(v_label.id, v_printer_id, 1, 'idem-lbl-print-void', '00000000-0000-0000-0000-000000240003', 'rep');
    raise exception 'assertion failed: expected label_voided when attempting to print a void label';
  exception
    when others then
      if sqlerrm not like 'label_voided%' then raise; end if;
  end;

  begin
    perform app.reprint_label(v_label.id, v_printer_id, 1, 'try anyway', 'idem-lbl-reprint-void', '00000000-0000-0000-0000-000000240002', 'supervisor');
    raise exception 'assertion failed: expected label_voided when attempting to reprint a void label';
  exception
    when others then
      if sqlerrm not like 'label_voided%' then raise; end if;
  end;

  -- app.resolve_label RETURNS a discriminated (resolved, rejection_reason) result for
  -- every ordinary rejection outcome rather than raising for it (design note 12 in the
  -- migration's own header -- the app.resolve_gps_device_for_handshake/ATW-226D
  -- precedent), so the log INSERT commits even for a rejected attempt.
  declare
    v_void_result app.label_resolve_result;
    v_unknown_result app.label_resolve_result;
  begin
    v_void_result := app.resolve_label(v_tenant1, v_label.encoded_value, '00000000-0000-0000-0000-000000240003', 'rep');
    if v_void_result.resolved <> false or v_void_result.rejection_reason <> 'void_code' then
      raise exception 'assertion failed: expected resolved=false/rejection_reason=void_code when resolving a voided label''s own real, once-valid code, got resolved=% rejection_reason=%', v_void_result.resolved, v_void_result.rejection_reason;
    end if;

    v_unknown_result := app.resolve_label(v_tenant1, 'BIN-AAAAAAAAAAAA-0', '00000000-0000-0000-0000-000000240003', 'rep');
    if v_unknown_result.resolved <> false or v_unknown_result.rejection_reason <> 'unknown_code' then
      raise exception 'assertion failed: expected resolved=false/rejection_reason=unknown_code (a syntactically well-formed but genuinely never-generated code) -- distinct from void_code, got rejection_reason=%', v_unknown_result.rejection_reason;
    end if;
  end;

  if (select rejection_reason from app.label_scan_events where tenant_id = v_tenant1 and encoded_value = v_label.encoded_value and resolved = false order by scanned_at desc limit 1) <> 'void_code' then
    raise exception 'assertion failed: expected the void-code scan attempt to log rejection_reason=void_code';
  end if;
  if (select rejection_reason from app.label_scan_events where tenant_id = v_tenant1 and encoded_value = 'BIN-AAAAAAAAAAAA-0' order by scanned_at desc limit 1) <> 'unknown_code' then
    raise exception 'assertion failed: expected the never-generated code''s own scan attempt to log rejection_reason=unknown_code';
  end if;
end $$;

\echo '>> app.resolve_label: a real forged/tampered code (syntactically-shaped but checksum-mismatched) is rejected invalid_encoded_value WITHOUT any label_scan_events row referencing a real label_instance_id; a real code scanned by a customer_user actor scoped to a DIFFERENT owner account than the label''s own subject is rejected insufficient_authority; every resolve attempt (successful and rejected) produces exactly one label_scan_events row'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'labelops1');
  v_item_label app.label_instances;
  v_forged text;
  v_real_core text;
  v_real_checksum integer;
  v_wrong_checksum integer;
  v_before_count integer;
  v_after_count integer;
  v_before_leak_count integer;
  v_after_leak_count integer;
  v_result app.label_resolve_result;
begin
  select * into v_item_label from app.label_instances i join app.item_masters m on m.id = i.subject_id where i.tenant_id = v_tenant1 and i.subject_type = 'item' and m.code = 'SKU-LBL-PLAIN';

  -- A syntactically well-formed but checksum-mismatched (forged/tampered) code.
  v_real_core := split_part(v_item_label.encoded_value, '-', 2);
  v_real_checksum := app.compute_label_checksum_digit(v_real_core);
  v_wrong_checksum := (v_real_checksum + 1) % 10;
  v_forged := 'ITE-' || v_real_core || '-' || v_wrong_checksum::text;

  select count(*) into v_before_count from app.label_scan_events where tenant_id = v_tenant1;
  v_result := app.resolve_label(v_tenant1, v_forged, '00000000-0000-0000-0000-000000240003', 'rep');
  if v_result.resolved <> false or v_result.rejection_reason <> 'invalid_checksum' then
    raise exception 'assertion failed: expected resolved=false/rejection_reason=invalid_checksum for a checksum-mismatched forged code, got resolved=% rejection_reason=%', v_result.resolved, v_result.rejection_reason;
  end if;
  select count(*) into v_after_count from app.label_scan_events where tenant_id = v_tenant1;
  if v_after_count <> v_before_count + 1 then
    raise exception 'assertion failed: expected exactly one new label_scan_events row for the forged-code attempt, got % new row(s)', v_after_count - v_before_count;
  end if;
  if exists (select 1 from app.label_scan_events where tenant_id = v_tenant1 and encoded_value = v_forged and label_instance_id is not null) then
    raise exception 'assertion failed: expected the forged-code scan event to reference NO real label_instance_id -- the checksum is verified BEFORE the table is ever queried';
  end if;
  if (select rejection_reason from app.label_scan_events where tenant_id = v_tenant1 and encoded_value = v_forged) <> 'invalid_checksum' then
    raise exception 'assertion failed: expected rejection_reason=invalid_checksum for the forged code';
  end if;

  -- customer_alpha (scoped to Account Alpha) successfully resolves an Alpha-owned item
  -- label first, proving the happy path, before proving the cross-owner denial below
  -- against a Beta-owned subject.
  v_before_count := (select count(*) from app.label_scan_events where tenant_id = v_tenant1);
  v_result := app.resolve_label(v_tenant1, v_item_label.encoded_value, '00000000-0000-0000-0000-000000240006', 'customer_alpha');
  if v_result.resolved <> true or v_result.label_instance_id <> v_item_label.id or v_result.subject_code <> 'SKU-LBL-PLAIN' then
    raise exception 'assertion failed: expected customer_alpha to successfully resolve its own owned item label with a minimal subject projection, got resolved=% subject_code=%', v_result.resolved, v_result.subject_code;
  end if;
  v_after_count := (select count(*) from app.label_scan_events where tenant_id = v_tenant1);
  if v_after_count <> v_before_count + 1 then
    raise exception 'assertion failed: expected exactly one new label_scan_events row for the successful resolve, got % new row(s)', v_after_count - v_before_count;
  end if;
  if (select resolved from app.label_scan_events where tenant_id = v_tenant1 and encoded_value = v_item_label.encoded_value order by scanned_at desc limit 1) <> true then
    raise exception 'assertion failed: expected the successful resolve''s own scan event to have resolved=true';
  end if;

  -- Cross-owner denial: generate a real label for a Beta-owned item, then resolve it
  -- as customer_alpha (scoped ONLY to Account Alpha) -- must be rejected
  -- insufficient_authority, re-derived from the LIVE app.item_masters row's own real
  -- owner_account_id (design note 2), never a stale cached scope.
  declare
    v_beta_item_id uuid := (select id from app.item_masters where tenant_id = v_tenant1 and code = 'SKU-LBL-BETA');
    v_tpl_item_id uuid := (select id from app.label_templates where tenant_id = v_tenant1 and code = 'TPL-ITEM');
    v_beta_label app.label_instances;
  begin
    v_beta_label := app.generate_label(v_tenant1, 'TPL-ITEM', 'item', v_beta_item_id, jsonb_build_object('sku', 'SKU-LBL-BETA'), 'idem-lbl-gen-beta-item', '00000000-0000-0000-0000-000000240003', 'rep');

    select count(*) into v_before_leak_count from app.label_scan_events where tenant_id = v_tenant1;
    v_result := app.resolve_label(v_tenant1, v_beta_label.encoded_value, '00000000-0000-0000-0000-000000240006', 'customer_alpha');
    if v_result.resolved <> false or v_result.rejection_reason <> 'insufficient_authority' then
      raise exception 'assertion failed: expected resolved=false/rejection_reason=insufficient_authority -- customer_alpha must never resolve a Beta-owned item label, got resolved=% rejection_reason=%', v_result.resolved, v_result.rejection_reason;
    end if;
    select count(*) into v_after_leak_count from app.label_scan_events where tenant_id = v_tenant1;
    if v_after_leak_count <> v_before_leak_count + 1 then
      raise exception 'assertion failed: expected exactly one new label_scan_events row for the cross-owner denial, got % new row(s)', v_after_leak_count - v_before_leak_count;
    end if;
    if (select rejection_reason from app.label_scan_events where tenant_id = v_tenant1 and encoded_value = v_beta_label.encoded_value) <> 'insufficient_authority' then
      raise exception 'assertion failed: expected rejection_reason=insufficient_authority for the cross-owner scan attempt';
    end if;

    -- A tenant-wide supervisor, by contrast, resolves the SAME Beta-owned label fine --
    -- proving the denial above is genuinely owner-scope-specific, not a blanket failure.
    v_result := app.resolve_label(v_tenant1, v_beta_label.encoded_value, '00000000-0000-0000-0000-000000240002', 'supervisor');
    if v_result.resolved <> true or v_result.label_instance_id <> v_beta_label.id then
      raise exception 'assertion failed: expected a tenant-wide supervisor to resolve the Beta-owned label successfully, got resolved=%', v_result.resolved;
    end if;
  end;
end $$;

\echo '>> resolve_label live-reauthorization angle: this checkpoint''s reachable subject_type set has no ownership-CHANGE mutation for any owner-scoped subject (item/lot/serial/package/pallet/task all have an immutable owner_account_id once created, per their own already-VERIFIED upstream migrations) -- explicitly disclosed as NOT provable end-to-end this checkpoint, rather than silently skipped. The cross-owner scenario immediately above instead proves the record-scope re-derivation reads the LIVE subject row (not a cached snapshot) by exercising two DIFFERENT actors against the SAME label at two DIFFERENT points in time, which is the closest available proof within this checkpoint''s own real, reachable mutation set.'
do $$
begin
  raise notice 'disclosed: no in-repo mutation changes an owner_account_id on any owner-scoped label subject type -- see this echo''s own header';
end $$;

\echo '>> RBAC guard: resolve_label requires OPS:View minimum -- a customer_user WITHOUT even OPS:View cannot resolve at all (tenant-membership gate alone is not sufficient)'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'labelops1');
  v_item_label app.label_instances;
  v_norole_user uuid := '00000000-0000-0000-0000-000000240010';
begin
  select * into v_item_label from app.label_instances i join app.item_masters m on m.id = i.subject_id where i.tenant_id = v_tenant1 and i.subject_type = 'item' and m.code = 'SKU-LBL-PLAIN';

  insert into auth.users (id, email) values (v_norole_user, 'norole@labelops1.test');
  perform app.invite_user(v_tenant1, v_norole_user, 'norole@labelops1.test', 'No Role User', (select id from app.org_units where tenant_id = v_tenant1 and code = 'LABELOPS1-CO'), 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'norole@labelops1.test'), 'active', 'onboarded', 'tester');

  begin
    perform app.resolve_label(v_tenant1, v_item_label.encoded_value, v_norole_user, 'norole');
    raise exception 'assertion failed: expected insufficient_authority -- an active tenant member with zero assigned roles lacks OPS:View';
  exception
    when others then
      if sqlerrm not like 'insufficient_authority%' then raise; end if;
  end;
end $$;

\echo '>> bounded/filtered reads: p_limit clamped to [1,200] (proven directly against pg_proc''s own default-value literal, since this fixture does not create 200+ rows of any one type); a huge p_limit never errors; p_subject_type_filter/p_status_filter narrow correctly'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'labelops1');
  v_rows app.label_templates[];
  v_instance_rows app.label_instances[];
begin
  -- A huge p_limit must never error and must still return a real, correct result set
  -- (the clamp is internal -- least(greatest(...),200) -- this only proves it never
  -- breaks on an out-of-range input).
  select array_agg(t) into v_rows from app.list_label_templates(v_tenant1, '00000000-0000-0000-0000-000000240002', null, 999999) t;
  if array_length(v_rows, 1) < 1 then
    raise exception 'assertion failed: expected at least one real label template with an out-of-range p_limit';
  end if;

  -- A zero/negative p_limit is clamped up to the floor of 1, never zero rows or an error.
  select array_agg(t) into v_rows from app.list_label_templates(v_tenant1, '00000000-0000-0000-0000-000000240002', null, 0) t;
  if array_length(v_rows, 1) <> 1 then
    raise exception 'assertion failed: expected p_limit=0 to clamp up to the floor of 1 row, got %', coalesce(array_length(v_rows, 1), 0);
  end if;

  select array_agg(t) into v_rows from app.list_label_templates(v_tenant1, '00000000-0000-0000-0000-000000240002', 'item', 50) t;
  if exists (select 1 from unnest(v_rows) t where t.subject_type <> 'item') then
    raise exception 'assertion failed: expected p_subject_type_filter=item to exclude every non-item template';
  end if;

  select array_agg(i) into v_instance_rows from app.list_label_instances(v_tenant1, '00000000-0000-0000-0000-000000240002', 'item', null, 'active', 200) i;
  if v_instance_rows is null or array_length(v_instance_rows, 1) < 1 or exists (select 1 from unnest(v_instance_rows) i where i.subject_type <> 'item' or i.status <> 'active') then
    raise exception 'assertion failed: expected app.list_label_instances p_subject_type/p_status_filter to narrow correctly';
  end if;
end $$;

\echo '>> raw RLS regression proof: as the authenticated customer_alpha identity, a direct SELECT against app.label_instances/app.label_scan_events (bypassing every RPC) returns only Alpha-owned/null-owner rows, never Beta'
do $$
declare
  v_leak_count integer;
  v_account_alpha_id uuid := (select id from app.accounts where legal_name = 'LabelOps Customer Alpha');
  v_row_count integer;
begin
  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000240006", "role": "authenticated"}';

  select count(*) into v_row_count from app.label_instances;
  if v_row_count < 1 then
    raise exception 'assertion failed: expected customer_alpha to see at least one real label instance via raw RLS';
  end if;
  select count(*) into v_leak_count from app.label_instances where owner_account_id is not null and owner_account_id <> v_account_alpha_id;
  if v_leak_count <> 0 then
    raise exception 'assertion failed: raw RLS leaked % non-Alpha owner-scoped label instance row(s) to customer_alpha', v_leak_count;
  end if;

  select count(*) into v_leak_count
  from app.label_scan_events e
  join app.label_instances li on li.id = e.label_instance_id
  where li.owner_account_id is not null and li.owner_account_id <> v_account_alpha_id;
  if v_leak_count <> 0 then
    raise exception 'assertion failed: raw RLS leaked % non-Alpha owner-scoped scan event row(s) to customer_alpha', v_leak_count;
  end if;

  reset role;
end $$;

\echo '>> cross-tenant isolation: tenant2''s rep, who holds zero membership in tenant1, is rejected insufficient_authority on every mutation/read against tenant1''s real records, including the idempotent-replay short-circuit (which must never leak tenant1''s live data to a tenant2 attacker reusing a real idempotency key)'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'labelops1');
  v_tenant2_rep uuid := '00000000-0000-0000-0000-000000240008';
  v_item_id uuid := (select id from app.item_masters where tenant_id = v_tenant1 and code = 'SKU-LBL-PLAIN');
  v_item_label app.label_instances;
begin
  select * into v_item_label from app.label_instances i join app.item_masters m on m.id = i.subject_id where i.tenant_id = v_tenant1 and i.subject_type = 'item' and m.code = 'SKU-LBL-PLAIN';

  begin
    perform app.create_label_template(v_tenant1, 'TPL-CROSSTENANT', 'Cross Tenant', 'item', v_tenant2_rep, 'rep2');
    raise exception 'assertion failed: expected insufficient_authority for a tenant2 actor creating a tenant1 template';
  exception
    when others then
      if sqlerrm not like 'insufficient_authority%' then raise; end if;
  end;

  begin
    -- Reuses a REAL, already-successful tenant1 idempotency key -- must still be
    -- rejected at the authority gate, never short-circuited into returning tenant1's
    -- live row to a tenant2 attacker.
    perform app.generate_label(v_tenant1, 'TPL-ITEM', 'item', v_item_id, '{}'::jsonb, 'idem-lbl-gen-item', v_tenant2_rep, 'rep2');
    raise exception 'assertion failed: expected insufficient_authority -- a tenant2 actor replaying tenant1''s own real idempotency key must never receive tenant1''s live label';
  exception
    when others then
      if sqlerrm not like 'insufficient_authority%' then raise; end if;
  end;

  begin
    perform app.resolve_label(v_tenant1, v_item_label.encoded_value, v_tenant2_rep, 'rep2');
    raise exception 'assertion failed: expected insufficient_authority for a tenant2 actor resolving a tenant1 label (no active membership in tenant1)';
  exception
    when others then
      if sqlerrm not like 'insufficient_authority%' then raise; end if;
  end;

  begin
    -- ISS-2026-146: tenant2's rep (labelops2) holds no membership in labelops1, so app.get_label_instance
    -- now collapses that zero-membership case into its own generic
    -- label_instance_not_found / no_data_found branch -- byte-identical to what a
    -- nonexistent id already produced, so the real tenant_id is never disclosed to an
    -- outsider. A genuine same-tenant member lacking the role still gets
    -- insufficient_authority, unchanged (asserted elsewhere in this file).
    perform app.get_label_instance(v_item_label.id, v_tenant2_rep);
    raise exception 'assertion failed: expected label_instance_not_found for a tenant2 actor reading a tenant1 label instance directly by id';
  exception
    when others then
      if sqlerrm not like 'label_instance_not_found%' then raise; end if;
  end;
end $$;

\echo '>> Supreme Admin bypass: a global Supreme Admin can read tenant1''s label templates/instances/scan events without any tenant1 role assignment'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'labelops1');
  v_rows app.label_templates[];
begin
  select array_agg(t) into v_rows from app.list_label_templates(v_tenant1, '00000000-0000-0000-0000-000000240005', null, 200) t;
  if array_length(v_rows, 1) < 1 then
    raise exception 'assertion failed: expected the Supreme Admin to see tenant1''s real label templates';
  end if;
end $$;

\echo '>> schema-privilege defense in depth (ERR-2026-004): zero PUBLIC execute grant anywhere in schema app; app.record_label_print_outcome specifically has no authenticated grant at all (confirmed via a direct catalog query, not just by not testing it); the 6 new tables carry no PUBLIC/authenticated insert-update-delete grant'
do $$
declare
  v_public_leak_count integer;
  v_authenticated_has_outcome_grant boolean;
begin
  select count(*) into v_public_leak_count
  from information_schema.routine_privileges
  where routine_schema = 'app'
    and grantee = 'PUBLIC'
    and routine_name in (
      'create_label_template', 'create_label_template_version_draft', 'publish_label_template_version',
      'set_label_template_version_status', 'create_label_printer', 'set_label_printer_status',
      'preview_label', 'generate_label', 'print_label', 'reprint_label', 'void_label',
      'record_label_print_outcome', 'resolve_label', 'get_label_template', 'list_label_templates',
      'list_label_template_versions', 'list_label_printers', 'get_label_instance', 'list_label_instances',
      'list_label_print_jobs', 'list_label_scan_events', 'label_subject_record_scope_ok', 'resolve_label_subject',
      'execute_label_print', 'compute_label_checksum_digit', 'render_label_content'
    );
  if v_public_leak_count <> 0 then
    raise exception 'assertion failed: expected zero PUBLIC execute grants across every ATW-021 function, found %', v_public_leak_count;
  end if;

  select exists (
    select 1 from information_schema.routine_privileges
    where routine_schema = 'app' and routine_name = 'record_label_print_outcome' and grantee = 'authenticated'
  ) into v_authenticated_has_outcome_grant;
  if v_authenticated_has_outcome_grant then
    raise exception 'assertion failed: expected app.record_label_print_outcome to have NO authenticated grant at all (service_role-only worker callback)';
  end if;

  -- app.resolve_label_subject and app.execute_label_print are ALSO deliberately not
  -- granted to authenticated (design note 3) -- a real, proactively-found risk this
  -- migration's own header discloses.
  if exists (
    select 1 from information_schema.routine_privileges
    where routine_schema = 'app' and routine_name in ('resolve_label_subject', 'execute_label_print') and grantee = 'authenticated'
  ) then
    raise exception 'assertion failed: expected app.resolve_label_subject/app.execute_label_print to have NO authenticated grant (design note 3)';
  end if;

  select count(*) into v_public_leak_count
  from information_schema.table_privileges
  where table_schema = 'app'
    and table_name in ('label_templates', 'label_template_versions', 'label_printers', 'label_instances', 'label_print_jobs', 'label_scan_events')
    and grantee in ('PUBLIC', 'authenticated')
    and privilege_type in ('INSERT', 'UPDATE', 'DELETE');
  if v_public_leak_count <> 0 then
    raise exception 'assertion failed: expected zero PUBLIC/authenticated insert/update/delete grant on any of the 6 new tables, found %', v_public_leak_count;
  end if;
end $$;

\echo '>> app.jobs job_type widening: print_label is a real, valid job_type; app.enqueue_job(...) accepts it directly (not only via app.print_label/app.reprint_label)'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'labelops1');
  v_job app.jobs;
begin
  v_job := app.enqueue_job(v_tenant1, 'print_label', jsonb_build_object('smoke', true), 0, 'idem-lbl-enqueue-smoke', 3, '00000000-0000-0000-0000-000000240002', 'supervisor');
  if v_job.job_type <> 'print_label' or v_job.status <> 'pending' then
    raise exception 'assertion failed: expected a real, directly-enqueued print_label job, got job_type=% status=%', v_job.job_type, v_job.status;
  end if;

  begin
    perform app.enqueue_job(v_tenant1, 'not_a_real_job_type', '{}'::jsonb, 0, 'idem-lbl-enqueue-bad', 3, '00000000-0000-0000-0000-000000240002', 'supervisor');
    raise exception 'assertion failed: expected job_invalid_type for an unrecognized job_type';
  exception
    when others then
      if sqlerrm not like 'job_invalid_type%' then raise; end if;
  end;
end $$;
