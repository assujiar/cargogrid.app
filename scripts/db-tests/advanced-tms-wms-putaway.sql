-- Real, executable test evidence for ATW-014 (CG-S10-ATW-014, Prompt 233 WMS
-- Putaway) -- run via `pnpm run db:test` against a real, disposable Postgres
-- database.

\set ON_ERROR_STOP on

\echo '>> setup: one tenant (wmsput1), a company org unit, a rep (OPS:Create/Edit/View), a second rep for claim-race/reassign-target checks, a supervisor (OPS:Create/Edit/View/Override), an OPS:View-only viewer, a global Supreme Admin, two warehouses (WH-PUT-1 with a dock/staging receiving pair plus a full destination taxonomy -- eligible rack/shelf/bin, a capacity-limited rack, an inactive rack, a not-putaway-enabled rack; WH-PUT-2 with one rack, for wrong-warehouse checks), one customer account (Account Alpha via the full CRM->Job Order pipeline), and three item masters (plain, lot-controlled, serial-controlled). Tenant2 (wmsput2): an isolated rep, for cross-tenant leakage checks.'
do $$
declare
  v_tenant1 uuid;
  v_tenant2 uuid;
  v_company uuid;
  v_company2 uuid;
  v_rep_role uuid;
  v_rep_draft app.role_versions;
  v_supervisor_role uuid;
  v_supervisor_draft app.role_versions;
  v_viewer_role uuid;
  v_viewer_draft app.role_versions;
  v_rep2_role uuid;
  v_rep2_draft app.role_versions;
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
  v_warehouse app.warehouses;
  v_warehouse2 app.warehouses;
begin
  insert into auth.users (id, email) values
    ('00000000-0000-0000-0000-000000120101', 'admin@wmsput1.test'),
    ('00000000-0000-0000-0000-000000120102', 'rep@wmsput1.test'),
    ('00000000-0000-0000-0000-000000120103', 'viewer@wmsput1.test'),
    ('00000000-0000-0000-0000-000000120104', 'supervisor@wmsput1.test'),
    ('00000000-0000-0000-0000-000000120105', 'supreme@wmsput1.test'),
    ('00000000-0000-0000-0000-000000120106', 'admin2@wmsput2.test'),
    ('00000000-0000-0000-0000-000000120107', 'rep2b@wmsput2.test'),
    ('00000000-0000-0000-0000-000000120108', 'rep2@wmsput1.test');

  perform app.grant_principal_membership('00000000-0000-0000-0000-000000120105', 'supreme_admin', null, null, 'tester');

  perform app.provision_tenant('wmsput1', 'WMS Putaway Tenant One', 'idem-wmsput1', 'tester');
  v_tenant1 := (select id from app.tenants where slug = 'wmsput1');
  perform app.transition_tenant_status(v_tenant1, 'active', 'setup', 'tester');
  perform app.create_org_unit(v_tenant1, 'company', null, 'WMSPUT1-CO', 'WMS Putaway Tenant One Co', 'tester');
  v_company := (select id from app.org_units where tenant_id = v_tenant1 and code = 'WMSPUT1-CO');

  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000120101', 'admin@wmsput1.test', 'WmsPut Admin', v_company, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'admin@wmsput1.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000120101', 'tenant_admin', v_tenant1, null, 'tester');

  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000120102', 'rep@wmsput1.test', 'WmsPut Rep', v_company, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'rep@wmsput1.test'), 'active', 'onboarded', 'tester');

  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000120108', 'rep2@wmsput1.test', 'WmsPut Rep Two', v_company, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'rep2@wmsput1.test'), 'active', 'onboarded', 'tester');

  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000120103', 'viewer@wmsput1.test', 'WmsPut Viewer', v_company, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'viewer@wmsput1.test'), 'active', 'onboarded', 'tester');

  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000120104', 'supervisor@wmsput1.test', 'WmsPut Supervisor', v_company, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'supervisor@wmsput1.test'), 'active', 'onboarded', 'tester');

  v_rep_role := (app.create_role(v_tenant1, 'WmsPut Rep Role', 'full commercial + ops create/edit/view', 'tester')).id;
  v_rep_draft := app.create_role_version(v_rep_role, 'tester');
  perform app.set_role_version_permissions(
    v_rep_draft.id,
    array(select id from app.permissions where (resource_module_code = 'COM' and action in ('Create', 'Edit', 'Approve', 'View', 'View cost'))
      or (resource_module_code = 'OPS' and action in ('Create', 'Edit', 'View'))),
    'tester'
  );
  perform app.publish_role_version(v_rep_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_rep_role and status = 'published'), '00000000-0000-0000-0000-000000120102', '00000000-0000-0000-0000-000000120101', 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_rep_role and status = 'published'), '00000000-0000-0000-0000-000000120108', '00000000-0000-0000-0000-000000120101', 'tester');

  v_supervisor_role := (app.create_role(v_tenant1, 'WmsPut Supervisor Role', 'ops create/edit/view/override', 'tester')).id;
  v_supervisor_draft := app.create_role_version(v_supervisor_role, 'tester');
  perform app.set_role_version_permissions(
    v_supervisor_draft.id,
    array(select id from app.permissions where resource_module_code = 'OPS' and action in ('Create', 'Edit', 'View', 'Override')),
    'tester'
  );
  perform app.publish_role_version(v_supervisor_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_supervisor_role and status = 'published'), '00000000-0000-0000-0000-000000120104', '00000000-0000-0000-0000-000000120101', 'tester');

  v_viewer_role := (app.create_role(v_tenant1, 'WmsPut Viewer Role', 'OPS:View only', 'tester')).id;
  v_viewer_draft := app.create_role_version(v_viewer_role, 'tester');
  perform app.set_role_version_permissions(v_viewer_draft.id, array(select id from app.permissions where resource_module_code = 'OPS' and action = 'View'), 'tester');
  perform app.publish_role_version(v_viewer_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_viewer_role and status = 'published'), '00000000-0000-0000-0000-000000120103', '00000000-0000-0000-0000-000000120101', 'tester');

  v_warehouse := app.create_warehouse(v_tenant1, v_company, 'WH-PUT-1', 'WMS Putaway Warehouse 1', 'Jl. Putaway 1', 'Asia/Jakarta', null, array['land']::text[], '00000000-0000-0000-0000-000000120102', 'rep');
  declare
    v_dock1 app.warehouse_locations;
    v_stage1 app.warehouse_locations;
    v_rack1 app.warehouse_locations;
    v_shelf1 app.warehouse_locations;
    v_bin1 app.warehouse_locations;
    v_rack_cap app.warehouse_locations;
    v_rack_notenabled app.warehouse_locations;
  begin
    v_dock1 := app.create_warehouse_location(v_warehouse.id, null, null, 'DOCK-PUT-1', 'Putaway Receiving Dock 1', 'dock', 1, null, null, null, null, null, false, false, '00000000-0000-0000-0000-000000120102', 'rep');
    perform app.set_warehouse_location_status(v_dock1.id, 'active', null, v_dock1.record_version, '00000000-0000-0000-0000-000000120102', 'rep');
    v_stage1 := app.create_warehouse_location(v_warehouse.id, null, null, 'STAGE-PUT-1', 'Putaway Staging Area 1', 'staging', 2, null, null, null, null, null, false, false, '00000000-0000-0000-0000-000000120102', 'rep');
    perform app.set_warehouse_location_status(v_stage1.id, 'active', null, v_stage1.record_version, '00000000-0000-0000-0000-000000120102', 'rep');
    v_rack1 := app.create_warehouse_location(v_warehouse.id, null, null, 'RACK-PUT-1', 'Putaway Rack 1', 'rack', 3, null, null, null, null, null, true, true, '00000000-0000-0000-0000-000000120102', 'rep');
    perform app.set_warehouse_location_status(v_rack1.id, 'active', null, v_rack1.record_version, '00000000-0000-0000-0000-000000120102', 'rep');
    v_shelf1 := app.create_warehouse_location(v_warehouse.id, null, null, 'SHELF-PUT-1', 'Putaway Shelf 1', 'shelf', 4, null, null, null, null, null, true, true, '00000000-0000-0000-0000-000000120102', 'rep');
    perform app.set_warehouse_location_status(v_shelf1.id, 'active', null, v_shelf1.record_version, '00000000-0000-0000-0000-000000120102', 'rep');
    v_bin1 := app.create_warehouse_location(v_warehouse.id, null, null, 'BIN-PUT-1', 'Putaway Bin 1', 'bin', 5, null, null, null, null, null, true, true, '00000000-0000-0000-0000-000000120102', 'rep');
    perform app.set_warehouse_location_status(v_bin1.id, 'active', null, v_bin1.record_version, '00000000-0000-0000-0000-000000120102', 'rep');
    v_rack_cap := app.create_warehouse_location(v_warehouse.id, null, null, 'RACK-PUT-CAP', 'Putaway Capacity-Limited Rack', 'rack', 6, 5, 'units', null, null, null, true, true, '00000000-0000-0000-0000-000000120102', 'rep');
    perform app.set_warehouse_location_status(v_rack_cap.id, 'active', null, v_rack_cap.record_version, '00000000-0000-0000-0000-000000120102', 'rep');
    -- RACK-PUT-INACTIVE is deliberately left in its default draft status (not 'active')
    -- -- the blocked_destination test feeds off exactly this.
    perform app.create_warehouse_location(v_warehouse.id, null, null, 'RACK-PUT-INACTIVE', 'Putaway Inactive Rack', 'rack', 7, null, null, null, null, null, true, true, '00000000-0000-0000-0000-000000120102', 'rep');
    v_rack_notenabled := app.create_warehouse_location(v_warehouse.id, null, null, 'RACK-PUT-NOTENABLED', 'Putaway Not-Enabled Rack', 'rack', 8, null, null, null, null, null, true, false, '00000000-0000-0000-0000-000000120102', 'rep');
    perform app.set_warehouse_location_status(v_rack_notenabled.id, 'active', null, v_rack_notenabled.record_version, '00000000-0000-0000-0000-000000120102', 'rep');
  end;

  v_warehouse2 := app.create_warehouse(v_tenant1, v_company, 'WH-PUT-2', 'WMS Putaway Warehouse 2', 'Jl. Putaway 2', 'Asia/Jakarta', null, array['land']::text[], '00000000-0000-0000-0000-000000120102', 'rep');
  declare
    v_rack_wh2 app.warehouse_locations;
  begin
    v_rack_wh2 := app.create_warehouse_location(v_warehouse2.id, null, null, 'RACK-PUT-WH2', 'Putaway Rack (Warehouse 2)', 'rack', 1, null, null, null, null, null, true, true, '00000000-0000-0000-0000-000000120102', 'rep');
    perform app.set_warehouse_location_status(v_rack_wh2.id, 'active', null, v_rack_wh2.record_version, '00000000-0000-0000-0000-000000120102', 'rep');
  end;

  perform app.capture_lead(v_tenant1, 'manual', null, 'WmsPut Customer Alpha', 'Alice WmsPut', 'alice@wmsput233.test', '0811',
    '00000000-0000-0000-0000-000000120102', v_company, '00000000-0000-0000-0000-000000120102', 'tester');
  select * into v_lead from app.leads where email = 'alice@wmsput233.test';
  perform app.qualify_lead(v_lead.id, v_lead.record_version, '00000000-0000-0000-0000-000000120102', 'tester');
  select * into v_lead from app.leads where id = v_lead.id;
  perform app.convert_lead_to_prospect(v_lead.id, 'WmsPut Customer Alpha', 'WMSPUT233A', '11.111.111.13-111.000',
    jsonb_build_object('line1', 'Jl. Putaway Alpha 12', 'city', 'Jakarta', 'country', 'ID'),
    '00000000-0000-0000-0000-000000120102', 'tester');
  select * into v_prospect from app.prospects where lead_id = v_lead.id;
  select * into v_contact from app.create_contact(v_tenant1, 'Alice WmsPut Ops', 'Ops Lead', 'alice@wmsput233.test', '0811', '00000000-0000-0000-0000-000000120102', v_company, '00000000-0000-0000-0000-000000120102', 'tester');
  perform app.link_contact_to_record(v_contact.id, 'prospect', v_prospect.id, 'primary', true, '00000000-0000-0000-0000-000000120102', 'tester');
  select * into v_opportunity from app.create_opportunity(
    v_tenant1, v_prospect.id, 'WMSPUT233 Alpha lane',
    jsonb_build_object('service_type', 'land_freight', 'cargo_description', 'General cargo', 'origin', 'Jakarta', 'destination', 'Surabaya', 'target_ready_date', '2026-08-01'),
    '00000000-0000-0000-0000-000000120102', v_company, '00000000-0000-0000-0000-000000120102', 'tester'
  );
  select * into v_request from app.request_costing(v_opportunity.id, '[]'::jsonb, null, '00000000-0000-0000-0000-000000120102', 'tester');
  select * into v_rate from app.create_rate_version(
    v_tenant1, 'VENDOR-WMSPUT233-A', 'Contoso WmsPut233 Line', 'land_freight', 'FTL', 'Jakarta', 'Surabaya', '20ft',
    null, null, null, null, 'IDR', 5000000, null, '[]'::jsonb, now(), null, null, '00000000-0000-0000-0000-000000120101', 'tester'
  );
  perform app.approve_rate_version(v_rate.id, v_rate.record_version, '00000000-0000-0000-0000-000000120101', 'tester');
  select * into v_selection from app.select_vendor_rate(v_request.id, v_rate.id, false, null, null, null, '00000000-0000-0000-0000-000000120102', 'tester');
  v_rule := app.create_margin_rule_version(v_tenant1, 20.00, 'half_up', '00000000-0000-0000-0000-000000120102', 'tester');
  perform app.publish_margin_rule_version(v_rule.id, v_rule.record_version, null, '00000000-0000-0000-0000-000000120102', 'tester');
  perform app.calculate_margin(v_selection.id, 6000000, 'IDR', 0, '00000000-0000-0000-0000-000000120102', 'tester');
  select id into v_calc_id from app.margin_calculations where rate_selection_id = v_selection.id and is_current;
  select * into v_quote from app.create_quotation_draft(v_tenant1, v_opportunity.id, 'IDR', now() + interval '14 days', v_contact.id, null, null, '00000000-0000-0000-0000-000000120102', 'tester');
  perform app.add_quotation_line(v_quote.id, v_quote.record_version, 'service', 'WMSPUT233 Alpha lane', v_calc_id, 1, 6000000, 0, 0, '00000000-0000-0000-0000-000000120102', 'tester');
  select * into v_quote from app.quotations where id = v_quote.id;
  perform app.submit_quotation(v_quote.id, v_quote.record_version, '00000000-0000-0000-0000-000000120102', 'tester');
  select * into v_send from app.send_quotation_for_acceptance(v_quote.id, null, 'email', '00000000-0000-0000-0000-000000120102', 'tester');
  perform app.record_quotation_customer_decision(v_send.raw_token, 'accepted', 'Alice WmsPut Ops', null, null, null, null, null);
  select * into v_quote from app.quotations where id = v_quote.id;
  select * into v_account from app.convert_quotation_to_account(v_quote.id, null, null, '00000000-0000-0000-0000-000000120102', 'rep');

  perform app.create_item_master(v_tenant1, v_account.id, 'SKU-PUT-PLAIN', 'Put Plain Widget', null, 'PCS', false, false, false, '00000000-0000-0000-0000-000000120102', 'rep');
  perform app.create_item_master(v_tenant1, v_account.id, 'SKU-PUT-LOT', 'Put Lot Widget', null, 'PCS', true, false, false, '00000000-0000-0000-0000-000000120102', 'rep');
  perform app.create_item_master(v_tenant1, v_account.id, 'SKU-PUT-SERIAL', 'Put Serial Widget', null, 'PCS', false, true, false, '00000000-0000-0000-0000-000000120102', 'rep');

  -- Tenant2: fully isolated -- exists only to prove cross-tenant scope safety.
  perform app.provision_tenant('wmsput2', 'WMS Putaway Tenant Two', 'idem-wmsput2', 'tester');
  v_tenant2 := (select id from app.tenants where slug = 'wmsput2');
  perform app.transition_tenant_status(v_tenant2, 'active', 'setup', 'tester');
  perform app.create_org_unit(v_tenant2, 'company', null, 'WMSPUT2-CO', 'WMS Putaway Tenant Two Co', 'tester');
  v_company2 := (select id from app.org_units where tenant_id = v_tenant2 and code = 'WMSPUT2-CO');
  perform app.invite_user(v_tenant2, '00000000-0000-0000-0000-000000120106', 'admin2@wmsput2.test', 'Tenant2 Admin', v_company2, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'admin2@wmsput2.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000120106', 'tenant_admin', v_tenant2, null, 'tester');
  perform app.invite_user(v_tenant2, '00000000-0000-0000-0000-000000120107', 'rep2b@wmsput2.test', 'Tenant2 Rep', v_company2, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'rep2b@wmsput2.test'), 'active', 'onboarded', 'tester');
  v_rep2_role := (app.create_role(v_tenant2, 'Tenant2 Rep Role', 'ops create/edit/view', 'tester')).id;
  v_rep2_draft := app.create_role_version(v_rep2_role, 'tester');
  perform app.set_role_version_permissions(v_rep2_draft.id, array(select id from app.permissions where resource_module_code = 'OPS' and action in ('Create', 'Edit', 'View')), 'tester');
  perform app.publish_role_version(v_rep2_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant2, (select id from app.role_versions where role_id = v_rep2_role and status = 'published'), '00000000-0000-0000-0000-000000120107', '00000000-0000-0000-0000-000000120106', 'tester');
end $$;

\echo '>> build the main confirmed inbound order (WH-PUT-1, Account Alpha) with 13 lines, one per putaway scenario, receive it fully (committing every line except L13, which is left uncounted for the receipt_line_not_committed check), so every line''s accepted_quantity is on_hand at DOCK-PUT-1 before any putaway task is generated'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'wmsput1');
  v_warehouse_id uuid := (select id from app.warehouses where tenant_id = v_tenant1 and code = 'WH-PUT-1');
  v_dock1_id uuid := (select id from app.warehouse_locations where tenant_id = v_tenant1 and code = 'DOCK-PUT-1');
  v_account_id uuid := (select id from app.accounts where tenant_id = v_tenant1 and legal_name = 'WmsPut Customer Alpha');
  v_plain_id uuid := (select id from app.item_masters where tenant_id = v_tenant1 and code = 'SKU-PUT-PLAIN');
  v_lot_id uuid := (select id from app.item_masters where tenant_id = v_tenant1 and code = 'SKU-PUT-LOT');
  v_serial_id uuid := (select id from app.item_masters where tenant_id = v_tenant1 and code = 'SKU-PUT-SERIAL');
  v_order app.wms_inbound_orders;
  v_lines app.wms_inbound_order_lines[];
  v_session app.wms_receipt_sessions;
  v_line app.wms_receipt_lines;
  i integer;
  v_qty numeric;
  v_qtys numeric[] := array[100, 60, 30, 20, 10, 5, 1, 30, 15, 10, 10, 5, 8];
begin
  v_order := app.create_manual_wms_inbound(v_tenant1, v_warehouse_id, v_account_id, 'main putaway fixture', 'idem-put-main', '00000000-0000-0000-0000-000000120102', 'rep');

  select array_agg(l) into v_lines from app.add_wms_inbound_order_lines(
    v_order.id,
    jsonb_build_array(
      jsonb_build_object('item_master_id', v_plain_id, 'expected_uom_code', 'PCS', 'expected_quantity', 100, 'notes', 'L1 single full confirm'),
      jsonb_build_object('item_master_id', v_plain_id, 'expected_uom_code', 'PCS', 'expected_quantity', 60, 'notes', 'L2 split across two destinations'),
      jsonb_build_object('item_master_id', v_plain_id, 'expected_uom_code', 'PCS', 'expected_quantity', 30, 'notes', 'L3 partial putaway + destination_mismatch'),
      jsonb_build_object('item_master_id', v_plain_id, 'expected_uom_code', 'PCS', 'expected_quantity', 20, 'notes', 'L4 capacity/destination_full'),
      jsonb_build_object('item_master_id', v_plain_id, 'expected_uom_code', 'PCS', 'expected_quantity', 10, 'notes', 'L5 destination eligibility rejections'),
      jsonb_build_object('item_master_id', v_lot_id, 'expected_uom_code', 'PCS', 'expected_quantity', 5, 'notes', 'L6 lot-controlled'),
      jsonb_build_object('item_master_id', v_serial_id, 'expected_uom_code', 'PCS', 'expected_quantity', 1, 'notes', 'L7 serial-controlled'),
      jsonb_build_object('item_master_id', v_plain_id, 'expected_uom_code', 'PCS', 'expected_quantity', 30, 'notes', 'L8 exception + supervisor reassign/release'),
      jsonb_build_object('item_master_id', v_plain_id, 'expected_uom_code', 'PCS', 'expected_quantity', 15, 'notes', 'L9 cancel task'),
      jsonb_build_object('item_master_id', v_plain_id, 'expected_uom_code', 'PCS', 'expected_quantity', 10, 'notes', 'L10 insufficient_remaining_quantity at generation'),
      jsonb_build_object('item_master_id', v_plain_id, 'expected_uom_code', 'PCS', 'expected_quantity', 10, 'notes', 'L11 real insufficient_stock at confirm time'),
      jsonb_build_object('item_master_id', v_plain_id, 'expected_uom_code', 'PCS', 'expected_quantity', 5, 'notes', 'L12 validation sandbox'),
      jsonb_build_object('item_master_id', v_plain_id, 'expected_uom_code', 'PCS', 'expected_quantity', 8, 'notes', 'L13 left uncommitted for receipt_line_not_committed')
    ),
    '00000000-0000-0000-0000-000000120102', 'rep'
  ) l;
  if array_length(v_lines, 1) <> 13 then
    raise exception 'assertion failed: expected exactly 13 lines on the main inbound order, got %', array_length(v_lines, 1);
  end if;

  v_order := app.schedule_wms_inbound_appointment(v_order.id, now() + interval '1 day', now() + interval '1 day' + interval '2 hours', v_order.record_version, '00000000-0000-0000-0000-000000120102', 'rep');
  v_order := app.confirm_wms_inbound(v_order.id, v_order.record_version, '00000000-0000-0000-0000-000000120102', 'rep');
  if v_order.status <> 'confirmed' then
    raise exception 'assertion failed: expected the main inbound order to be confirmed, got %', v_order.status;
  end if;

  v_session := app.start_wms_receipt_session(v_order.id, v_dock1_id, 'idem-put-recvsession', '00000000-0000-0000-0000-000000120102', 'rep');

  -- Receive and commit L1..L12 (accepted = expected exactly, no over/damage/hold).
  -- L6 (lot) and L7 (serial) need real lot/serial identity to satisfy ATW-013's own
  -- missing_lot/missing_serial gates at record time. L13 is deliberately skipped
  -- entirely -- it stays 'pending', feeding the receipt_line_not_committed check.
  for i in 1..12 loop
    select * into v_line from app.wms_receipt_lines where receipt_session_id = v_session.id and line_number = i;
    v_qty := v_qtys[i];
    if i = 6 then
      v_line := app.record_wms_receipt_line_count(v_line.id, null, v_qty, v_qty, 0, 0, 0, 'LOT-PUT-001', null, null, 'lot fixture', v_line.record_version, '00000000-0000-0000-0000-000000120102', 'rep');
    elsif i = 7 then
      v_line := app.record_wms_receipt_line_count(v_line.id, null, v_qty, v_qty, 0, 0, 0, null, 'SN-PUT-001', null, 'serial fixture', v_line.record_version, '00000000-0000-0000-0000-000000120102', 'rep');
    else
      v_line := app.record_wms_receipt_line_count(v_line.id, null, v_qty, v_qty, 0, 0, 0, null, null, null, 'exact receipt', v_line.record_version, '00000000-0000-0000-0000-000000120102', 'rep');
    end if;
    v_line := app.commit_wms_receipt_line(v_line.id, 'idem-put-commit-l' || i, v_line.record_version, '00000000-0000-0000-0000-000000120102', 'rep');
    if v_line.status <> 'committed' then
      raise exception 'assertion failed: expected receipt line % to commit, got status=%', i, v_line.status;
    end if;
  end loop;
end $$;

\echo '>> app.generate_wms_putaway_task: viewer rejected; receipt_line_not_found; receipt_line_not_committed (L13); invalid_quantity; insufficient_remaining_quantity; incompatible_location for a wrong-warehouse caller-supplied suggestion; caller-supplied same-warehouse suggestion accepted (decision support only); idempotent on idempotency_key; auto-suggest picks the first eligible capacity-headroom rack/shelf/bin when no suggestion is given'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'wmsput1');
  v_session_id uuid := (select id from app.wms_receipt_sessions where tenant_id = v_tenant1 and idempotency_key = 'idem-put-recvsession');
  v_rack1_id uuid := (select id from app.warehouse_locations where tenant_id = v_tenant1 and code = 'RACK-PUT-1');
  v_rack_wh2_id uuid := (select id from app.warehouse_locations where tenant_id = v_tenant1 and code = 'RACK-PUT-WH2');
  v_line1 app.wms_receipt_lines;
  v_line13 app.wms_receipt_lines;
  v_task app.wms_putaway_tasks;
  v_replay app.wms_putaway_tasks;
begin
  select * into v_line1 from app.wms_receipt_lines where receipt_session_id = v_session_id and line_number = 1;
  select * into v_line13 from app.wms_receipt_lines where receipt_session_id = v_session_id and line_number = 13;

  begin
    perform app.generate_wms_putaway_task(v_line1.id, 100, null, 'idem-gen-viewer', '00000000-0000-0000-0000-000000120103', 'viewer');
    raise exception 'assertion failed: expected insufficient_authority -- viewer holds OPS:View only';
  exception
    when others then
      if sqlerrm not like 'insufficient_authority%' then raise; end if;
  end;

  begin
    perform app.generate_wms_putaway_task(gen_random_uuid(), 100, null, 'idem-gen-badline', '00000000-0000-0000-0000-000000120102', 'rep');
    raise exception 'assertion failed: expected receipt_line_not_found';
  exception
    when others then
      if sqlerrm not like 'receipt_line_not_found%' then raise; end if;
  end;

  begin
    perform app.generate_wms_putaway_task(v_line13.id, 8, null, 'idem-gen-notcommitted', '00000000-0000-0000-0000-000000120102', 'rep');
    raise exception 'assertion failed: expected receipt_line_not_committed -- L13 was never counted or committed';
  exception
    when others then
      if sqlerrm not like 'receipt_line_not_committed%' then raise; end if;
  end;

  begin
    perform app.generate_wms_putaway_task(v_line1.id, 0, null, 'idem-gen-zeroqty', '00000000-0000-0000-0000-000000120102', 'rep');
    raise exception 'assertion failed: expected invalid_quantity -- zero quantity';
  exception
    when others then
      if sqlerrm not like 'invalid_quantity%' then raise; end if;
  end;

  begin
    perform app.generate_wms_putaway_task(v_line1.id, 101, null, 'idem-gen-toomuch', '00000000-0000-0000-0000-000000120102', 'rep');
    raise exception 'assertion failed: expected insufficient_remaining_quantity -- L1 only has 100 accepted units';
  exception
    when others then
      if sqlerrm not like 'insufficient_remaining_quantity%' then raise; end if;
  end;

  begin
    perform app.generate_wms_putaway_task(v_line1.id, 100, v_rack_wh2_id, 'idem-gen-wrongwh', '00000000-0000-0000-0000-000000120102', 'rep');
    raise exception 'assertion failed: expected incompatible_location -- RACK-PUT-WH2 belongs to WH-PUT-2, not WH-PUT-1';
  exception
    when others then
      if sqlerrm not like 'incompatible_location%' then raise; end if;
  end;

  -- A caller-supplied suggestion is decision support only (design note 5) -- it is
  -- sanity-checked for same-warehouse existence only, not full eligibility. Supplying
  -- RACK-PUT-1 explicitly here is accepted even though full eligibility is deferred to
  -- confirm time.
  v_task := app.generate_wms_putaway_task(v_line1.id, 100, v_rack1_id, 'idem-gen-l1', '00000000-0000-0000-0000-000000120102', 'rep');
  if v_task.status <> 'unclaimed' or v_task.task_quantity <> 100 or v_task.suggested_location_id <> v_rack1_id or v_task.suggested_reason <> 'caller_supplied' then
    raise exception 'assertion failed: expected an unclaimed 100-unit task suggesting RACK-PUT-1 (caller_supplied), got status=%/qty=%/suggested=%/reason=%', v_task.status, v_task.task_quantity, v_task.suggested_location_id, v_task.suggested_reason;
  end if;
  if v_task.item_master_id <> v_line1.item_master_id or v_task.owner_account_id <> v_line1.owner_account_id or v_task.uom_code <> v_line1.expected_uom_code then
    raise exception 'assertion failed: expected the task to snapshot its item/owner/uom from the receipt line exactly';
  end if;

  v_replay := app.generate_wms_putaway_task(v_line1.id, 100, v_rack1_id, 'idem-gen-l1', '00000000-0000-0000-0000-000000120102', 'rep');
  if v_replay.id <> v_task.id then
    raise exception 'assertion failed: expected the same-idempotency-key replay to return the identical task';
  end if;

  -- A second generation call for the exact same line/quantity but a different
  -- idempotency_key must now fail (remaining is fully allocated by the task above) --
  -- structural proof that generation can never over-allocate a receipt line, the
  -- generation-time half of "insufficient source balance" (Prompt 233 section 25).
  begin
    perform app.generate_wms_putaway_task(v_line1.id, 1, null, 'idem-gen-l1-overflow', '00000000-0000-0000-0000-000000120102', 'rep');
    raise exception 'assertion failed: expected insufficient_remaining_quantity -- L1''s full 100 units are already allocated to the task above';
  exception
    when others then
      if sqlerrm not like 'insufficient_remaining_quantity%' then raise; end if;
  end;
end $$;

\echo '>> app.generate_wms_putaway_task auto-suggest: with no caller-supplied destination, picks the first active/putaway_enabled/capacity-headroom rack-shelf-bin ordered by sequence (RACK-PUT-1)'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'wmsput1');
  v_session_id uuid := (select id from app.wms_receipt_sessions where tenant_id = v_tenant1 and idempotency_key = 'idem-put-recvsession');
  v_rack1_id uuid := (select id from app.warehouse_locations where tenant_id = v_tenant1 and code = 'RACK-PUT-1');
  v_line10 app.wms_receipt_lines;
  v_task app.wms_putaway_tasks;
begin
  select * into v_line10 from app.wms_receipt_lines where receipt_session_id = v_session_id and line_number = 10;
  v_task := app.generate_wms_putaway_task(v_line10.id, 10, null, 'idem-gen-l10-autosuggest', '00000000-0000-0000-0000-000000120102', 'rep');
  if v_task.suggested_location_id <> v_rack1_id or v_task.suggested_reason <> 'auto_suggested_first_eligible_capacity_headroom' then
    raise exception 'assertion failed: expected auto-suggest to pick RACK-PUT-1 (first eligible, lowest sequence), got suggested=%/reason=%', v_task.suggested_location_id, v_task.suggested_reason;
  end if;
  -- Left unclaimed deliberately -- this task exists purely to prove the auto-suggest
  -- decision-support outcome; RACK-PUT-1's own on_hand balance is exercised precisely
  -- by the L1/L2/L3/L4/L5 confirm sections below, and confirming this one too would
  -- make those exact-balance assertions depend on section ordering.
end $$;

\echo '>> app.claim_wms_putaway_task: viewer rejected; task_not_found; claim succeeds; idempotent same-claimant re-claim; real concurrent-claim-race guard (a different rep is rejected task_already_claimed once the first claim has landed -- ISS-2026-014 discloses no multi-session harness exists yet to prove this under true concurrent load, so this is a sequential proof of the guard''s own outcome, the identical disclosed boundary ATW-015 already used for its own balance-upsert race-safety); stale_version'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'wmsput1');
  v_task app.wms_putaway_tasks;
  v_replay app.wms_putaway_tasks;
begin
  select * into v_task from app.wms_putaway_tasks where tenant_id = v_tenant1 and idempotency_key = 'idem-gen-l1';

  begin
    perform app.claim_wms_putaway_task(v_task.id, v_task.record_version, '00000000-0000-0000-0000-000000120103', 'viewer');
    raise exception 'assertion failed: expected insufficient_authority -- viewer holds OPS:View only';
  exception
    when others then
      if sqlerrm not like 'insufficient_authority%' then raise; end if;
  end;

  begin
    perform app.claim_wms_putaway_task(gen_random_uuid(), 1, '00000000-0000-0000-0000-000000120102', 'rep');
    raise exception 'assertion failed: expected task_not_found';
  exception
    when others then
      if sqlerrm not like 'task_not_found%' then raise; end if;
  end;

  v_task := app.claim_wms_putaway_task(v_task.id, v_task.record_version, '00000000-0000-0000-0000-000000120102', 'rep');
  if v_task.status <> 'claimed' or v_task.claimed_by_auth_user_id <> '00000000-0000-0000-0000-000000120102' then
    raise exception 'assertion failed: expected the task to be claimed by rep, got status=%/claimed_by=%', v_task.status, v_task.claimed_by_auth_user_id;
  end if;

  v_replay := app.claim_wms_putaway_task(v_task.id, v_task.record_version, '00000000-0000-0000-0000-000000120102', 'rep');
  if v_replay.record_version <> v_task.record_version then
    raise exception 'assertion failed: expected a same-claimant re-claim to be a true no-op (no version bump)';
  end if;

  begin
    perform app.claim_wms_putaway_task(v_task.id, v_task.record_version, '00000000-0000-0000-0000-000000120108', 'rep2');
    raise exception 'assertion failed: expected task_already_claimed -- rep2 must not be able to claim a task rep already holds';
  exception
    when others then
      if sqlerrm not like 'task_already_claimed%' then raise; end if;
  end;

  -- The dedicated stale_version proof needs a genuinely fresh, still-unclaimed task
  -- (the idempotent same-claimant short-circuit above never even reaches the version
  -- check) -- L12 is reserved for exactly this validation-sandbox purpose.
  declare
    v_session_id uuid := (select id from app.wms_receipt_sessions where tenant_id = v_tenant1 and idempotency_key = 'idem-put-recvsession');
    v_line12 app.wms_receipt_lines;
    v_fresh_task app.wms_putaway_tasks;
  begin
    select * into v_line12 from app.wms_receipt_lines where receipt_session_id = v_session_id and line_number = 12;

    begin
      perform app.generate_wms_putaway_task(v_line12.id, 5, null, '', '00000000-0000-0000-0000-000000120102', 'rep');
      raise exception 'assertion failed: expected invalid_idempotency_key -- empty key';
    exception
      when others then
        if sqlerrm not like 'invalid_idempotency_key%' then raise; end if;
    end;

    v_fresh_task := app.generate_wms_putaway_task(v_line12.id, 5, null, 'idem-gen-l12', '00000000-0000-0000-0000-000000120102', 'rep');

    begin
      perform app.claim_wms_putaway_task(v_fresh_task.id, v_fresh_task.record_version + 999, '00000000-0000-0000-0000-000000120102', 'rep');
      raise exception 'assertion failed: expected stale_version on a genuinely fresh unclaimed task';
    exception
      when others then
        if sqlerrm not like 'stale_version%' then raise; end if;
    end;

    v_fresh_task := app.claim_wms_putaway_task(v_fresh_task.id, v_fresh_task.record_version, '00000000-0000-0000-0000-000000120102', 'rep');
    if v_fresh_task.status <> 'claimed' then
      raise exception 'assertion failed: expected L12''s task to claim cleanly once the correct version was supplied';
    end if;
  end;
end $$;

\echo '>> app.confirm_wms_putaway_task (L1, single full confirm): not_task_claimant rejected; invalid_quantity; exceeds_remaining_quantity; posts a real balanced transfer (source DOCK-PUT-1 decreases, destination RACK-PUT-1 increases by the identical amount); status becomes confirmed; idempotent replay on the same idempotency_key does not double-post; a genuinely new confirm attempt on an already-confirmed task is rejected task_already_confirmed'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'wmsput1');
  v_warehouse_id uuid := (select id from app.warehouses where tenant_id = v_tenant1 and code = 'WH-PUT-1');
  v_dock1_id uuid := (select id from app.warehouse_locations where tenant_id = v_tenant1 and code = 'DOCK-PUT-1');
  v_rack1_id uuid := (select id from app.warehouse_locations where tenant_id = v_tenant1 and code = 'RACK-PUT-1');
  v_account_id uuid := (select id from app.accounts where tenant_id = v_tenant1 and legal_name = 'WmsPut Customer Alpha');
  v_plain_id uuid := (select id from app.item_masters where tenant_id = v_tenant1 and code = 'SKU-PUT-PLAIN');
  v_task app.wms_putaway_tasks;
  v_replay app.wms_putaway_tasks;
  v_source_balance app.inventory_balances;
  v_dest_balance app.inventory_balances;
begin
  select * into v_task from app.wms_putaway_tasks where tenant_id = v_tenant1 and idempotency_key = 'idem-gen-l1';

  begin
    perform app.confirm_wms_putaway_task(v_task.id, 100, v_rack1_id, null, null, 'idem-confirm-l1-rep2', v_task.record_version, '00000000-0000-0000-0000-000000120108', 'rep2');
    raise exception 'assertion failed: expected not_task_claimant -- rep2 never claimed this task';
  exception
    when others then
      if sqlerrm not like 'not_task_claimant%' then raise; end if;
  end;

  begin
    perform app.confirm_wms_putaway_task(v_task.id, 0, v_rack1_id, null, null, 'idem-confirm-l1-zero', v_task.record_version, '00000000-0000-0000-0000-000000120102', 'rep');
    raise exception 'assertion failed: expected invalid_quantity -- zero confirm quantity';
  exception
    when others then
      if sqlerrm not like 'invalid_quantity%' then raise; end if;
  end;

  begin
    perform app.confirm_wms_putaway_task(v_task.id, 101, v_rack1_id, null, null, 'idem-confirm-l1-toomuch', v_task.record_version, '00000000-0000-0000-0000-000000120102', 'rep');
    raise exception 'assertion failed: expected exceeds_remaining_quantity -- task only holds 100 units';
  exception
    when others then
      if sqlerrm not like 'exceeds_remaining_quantity%' then raise; end if;
  end;

  select * into v_source_balance from app.inventory_balances
    where tenant_id = v_tenant1 and warehouse_id = v_warehouse_id and owner_account_id = v_account_id and item_master_id = v_plain_id
      and location_id = v_dock1_id and lot_number is null and serial_number is null and status = 'on_hand';
  if v_source_balance.on_hand < 100 then
    raise exception 'assertion failed: expected at least 100 units on_hand at DOCK-PUT-1 before putaway, got %', v_source_balance.on_hand;
  end if;

  v_task := app.confirm_wms_putaway_task(v_task.id, 100, v_rack1_id, null, null, 'idem-confirm-l1', v_task.record_version, '00000000-0000-0000-0000-000000120102', 'rep');
  if v_task.status <> 'confirmed' or v_task.confirmed_quantity <> 100 or v_task.remaining_quantity <> 0 or v_task.actual_location_id <> v_rack1_id then
    raise exception 'assertion failed: expected task fully confirmed at RACK-PUT-1, got status=%/confirmed=%/remaining=%/actual=%', v_task.status, v_task.confirmed_quantity, v_task.remaining_quantity, v_task.actual_location_id;
  end if;

  select * into v_source_balance from app.inventory_balances
    where tenant_id = v_tenant1 and warehouse_id = v_warehouse_id and owner_account_id = v_account_id and item_master_id = v_plain_id
      and location_id = v_dock1_id and lot_number is null and serial_number is null and status = 'on_hand';
  select * into v_dest_balance from app.inventory_balances
    where tenant_id = v_tenant1 and warehouse_id = v_warehouse_id and owner_account_id = v_account_id and item_master_id = v_plain_id
      and location_id = v_rack1_id and lot_number is null and serial_number is null and status = 'on_hand';
  if v_dest_balance.on_hand <> 100 then
    raise exception 'assertion failed: expected exactly 100 units on_hand at RACK-PUT-1 after L1 putaway, got %', v_dest_balance.on_hand;
  end if;
end $$;

\echo '>> app.confirm_wms_putaway_task idempotent replay proof (exact same idempotency_key) and task_already_confirmed proof (a genuinely new key on an already-confirmed task)'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'wmsput1');
  v_rack1_id uuid := (select id from app.warehouse_locations where tenant_id = v_tenant1 and code = 'RACK-PUT-1');
  v_task app.wms_putaway_tasks;
  v_replay app.wms_putaway_tasks;
  v_dest_balance_before numeric;
  v_dest_balance_after numeric;
  v_warehouse_id uuid := (select id from app.warehouses where tenant_id = v_tenant1 and code = 'WH-PUT-1');
  v_account_id uuid := (select id from app.accounts where tenant_id = v_tenant1 and legal_name = 'WmsPut Customer Alpha');
  v_plain_id uuid := (select id from app.item_masters where tenant_id = v_tenant1 and code = 'SKU-PUT-PLAIN');
begin
  select * into v_task from app.wms_putaway_tasks where tenant_id = v_tenant1 and idempotency_key = 'idem-gen-l1';

  select on_hand into v_dest_balance_before from app.inventory_balances
    where tenant_id = v_tenant1 and warehouse_id = v_warehouse_id and owner_account_id = v_account_id and item_master_id = v_plain_id
      and location_id = v_rack1_id and lot_number is null and serial_number is null and status = 'on_hand';

  -- The exact same idempotency_key as the original successful confirm -- a true
  -- duplicate-scan/duplicate-commit retry (Prompt 233 section 23).
  v_replay := app.confirm_wms_putaway_task(v_task.id, 100, v_rack1_id, null, null, 'idem-confirm-l1', v_task.record_version, '00000000-0000-0000-0000-000000120102', 'rep');
  if v_replay.confirmed_quantity <> 100 then
    raise exception 'assertion failed: expected the exact-same-key replay to return the task unchanged at confirmed_quantity=100, got %', v_replay.confirmed_quantity;
  end if;

  select on_hand into v_dest_balance_after from app.inventory_balances
    where tenant_id = v_tenant1 and warehouse_id = v_warehouse_id and owner_account_id = v_account_id and item_master_id = v_plain_id
      and location_id = v_rack1_id and lot_number is null and serial_number is null and status = 'on_hand';
  if v_dest_balance_after <> v_dest_balance_before then
    raise exception 'assertion failed: expected the idempotent replay to post no additional movement (balance unchanged), got before=%/after=%', v_dest_balance_before, v_dest_balance_after;
  end if;

  -- A genuinely new confirm attempt (a new idempotency_key) against an already-fully-
  -- confirmed task is a real, distinct rejection -- never silently accepted.
  begin
    perform app.confirm_wms_putaway_task(v_task.id, 1, v_rack1_id, null, null, 'idem-confirm-l1-genuinely-new', v_task.record_version, '00000000-0000-0000-0000-000000120102', 'rep');
    raise exception 'assertion failed: expected task_already_confirmed';
  exception
    when others then
      if sqlerrm not like 'task_already_confirmed%' then raise; end if;
  end;
end $$;

\echo '>> L2 split across two destinations: two tasks generated for the same receipt line (40 to RACK-PUT-1, 20 to SHELF-PUT-1), each claimed and confirmed independently, both landing at their own real destination'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'wmsput1');
  v_session_id uuid := (select id from app.wms_receipt_sessions where tenant_id = v_tenant1 and idempotency_key = 'idem-put-recvsession');
  v_warehouse_id uuid := (select id from app.warehouses where tenant_id = v_tenant1 and code = 'WH-PUT-1');
  v_rack1_id uuid := (select id from app.warehouse_locations where tenant_id = v_tenant1 and code = 'RACK-PUT-1');
  v_shelf1_id uuid := (select id from app.warehouse_locations where tenant_id = v_tenant1 and code = 'SHELF-PUT-1');
  v_account_id uuid := (select id from app.accounts where tenant_id = v_tenant1 and legal_name = 'WmsPut Customer Alpha');
  v_plain_id uuid := (select id from app.item_masters where tenant_id = v_tenant1 and code = 'SKU-PUT-PLAIN');
  v_line2 app.wms_receipt_lines;
  v_task_a app.wms_putaway_tasks;
  v_task_b app.wms_putaway_tasks;
  v_shelf_balance app.inventory_balances;
begin
  select * into v_line2 from app.wms_receipt_lines where receipt_session_id = v_session_id and line_number = 2;

  v_task_a := app.generate_wms_putaway_task(v_line2.id, 40, v_rack1_id, 'idem-gen-l2a', '00000000-0000-0000-0000-000000120102', 'rep');
  v_task_b := app.generate_wms_putaway_task(v_line2.id, 20, v_shelf1_id, 'idem-gen-l2b', '00000000-0000-0000-0000-000000120102', 'rep');
  if v_task_a.id = v_task_b.id then
    raise exception 'assertion failed: expected two genuinely distinct tasks for the split';
  end if;

  -- The split must exactly exhaust the line''s own accepted_quantity -- a third
  -- generation call for even 1 more unit must now fail.
  begin
    perform app.generate_wms_putaway_task(v_line2.id, 1, null, 'idem-gen-l2c-overflow', '00000000-0000-0000-0000-000000120102', 'rep');
    raise exception 'assertion failed: expected insufficient_remaining_quantity -- L2''s full 60 units are already split across two tasks';
  exception
    when others then
      if sqlerrm not like 'insufficient_remaining_quantity%' then raise; end if;
  end;

  v_task_a := app.claim_wms_putaway_task(v_task_a.id, v_task_a.record_version, '00000000-0000-0000-0000-000000120102', 'rep');
  v_task_a := app.confirm_wms_putaway_task(v_task_a.id, 40, v_rack1_id, null, null, 'idem-confirm-l2a', v_task_a.record_version, '00000000-0000-0000-0000-000000120102', 'rep');
  if v_task_a.status <> 'confirmed' then
    raise exception 'assertion failed: expected task A (40 units) to confirm fully at RACK-PUT-1';
  end if;

  v_task_b := app.claim_wms_putaway_task(v_task_b.id, v_task_b.record_version, '00000000-0000-0000-0000-000000120108', 'rep2');
  v_task_b := app.confirm_wms_putaway_task(v_task_b.id, 20, v_shelf1_id, null, null, 'idem-confirm-l2b', v_task_b.record_version, '00000000-0000-0000-0000-000000120108', 'rep2');
  if v_task_b.status <> 'confirmed' then
    raise exception 'assertion failed: expected task B (20 units) to confirm fully at SHELF-PUT-1';
  end if;

  select * into v_shelf_balance from app.inventory_balances
    where tenant_id = v_tenant1 and warehouse_id = v_warehouse_id and owner_account_id = v_account_id and item_master_id = v_plain_id
      and location_id = v_shelf1_id and lot_number is null and serial_number is null and status = 'on_hand';
  if v_shelf_balance.on_hand <> 20 then
    raise exception 'assertion failed: expected exactly 20 units on_hand at SHELF-PUT-1, got %', v_shelf_balance.on_hand;
  end if;
end $$;

\echo '>> L3 partial putaway + destination_mismatch: confirm 10 of 30 (status partial), duplicate-scan idempotent replay of that partial confirm leaves confirmed_quantity unchanged, a different destination on the second real confirm is rejected destination_mismatch, then the remaining 20 confirms at the original destination (status confirmed)'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'wmsput1');
  v_session_id uuid := (select id from app.wms_receipt_sessions where tenant_id = v_tenant1 and idempotency_key = 'idem-put-recvsession');
  v_rack1_id uuid := (select id from app.warehouse_locations where tenant_id = v_tenant1 and code = 'RACK-PUT-1');
  v_rack_cap_id uuid := (select id from app.warehouse_locations where tenant_id = v_tenant1 and code = 'RACK-PUT-CAP');
  v_line3 app.wms_receipt_lines;
  v_task app.wms_putaway_tasks;
  v_replay app.wms_putaway_tasks;
begin
  select * into v_line3 from app.wms_receipt_lines where receipt_session_id = v_session_id and line_number = 3;
  v_task := app.generate_wms_putaway_task(v_line3.id, 30, v_rack1_id, 'idem-gen-l3', '00000000-0000-0000-0000-000000120102', 'rep');
  v_task := app.claim_wms_putaway_task(v_task.id, v_task.record_version, '00000000-0000-0000-0000-000000120102', 'rep');

  v_task := app.confirm_wms_putaway_task(v_task.id, 10, v_rack1_id, null, null, 'idem-confirm-l3-part1', v_task.record_version, '00000000-0000-0000-0000-000000120102', 'rep');
  if v_task.status <> 'partial' or v_task.confirmed_quantity <> 10 or v_task.remaining_quantity <> 20 then
    raise exception 'assertion failed: expected task L3 partial at confirmed=10/remaining=20, got status=%/confirmed=%/remaining=%', v_task.status, v_task.confirmed_quantity, v_task.remaining_quantity;
  end if;

  -- Duplicate-scan idempotent replay of the exact same partial confirm event.
  v_replay := app.confirm_wms_putaway_task(v_task.id, 10, v_rack1_id, null, null, 'idem-confirm-l3-part1', v_task.record_version, '00000000-0000-0000-0000-000000120102', 'rep');
  if v_replay.confirmed_quantity <> 10 then
    raise exception 'assertion failed: expected the duplicate-scan replay to leave confirmed_quantity at 10 (never 20), got %', v_replay.confirmed_quantity;
  end if;

  begin
    perform app.confirm_wms_putaway_task(v_task.id, 20, v_rack_cap_id, null, null, 'idem-confirm-l3-part2-wrongdest', v_task.record_version, '00000000-0000-0000-0000-000000120102', 'rep');
    raise exception 'assertion failed: expected destination_mismatch -- the task already began putaway at RACK-PUT-1';
  exception
    when others then
      if sqlerrm not like 'destination_mismatch%' then raise; end if;
  end;

  v_task := app.confirm_wms_putaway_task(v_task.id, 20, v_rack1_id, null, null, 'idem-confirm-l3-part2', v_task.record_version, '00000000-0000-0000-0000-000000120102', 'rep');
  if v_task.status <> 'confirmed' or v_task.confirmed_quantity <> 30 then
    raise exception 'assertion failed: expected task L3 fully confirmed at 30 units, got status=%/confirmed=%', v_task.status, v_task.confirmed_quantity;
  end if;
end $$;

\echo '>> L4 capacity/destination_full: confirming 20 units to a capacity-5 rack is rejected destination_full; the same task then confirms cleanly at an uncapped destination'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'wmsput1');
  v_session_id uuid := (select id from app.wms_receipt_sessions where tenant_id = v_tenant1 and idempotency_key = 'idem-put-recvsession');
  v_rack1_id uuid := (select id from app.warehouse_locations where tenant_id = v_tenant1 and code = 'RACK-PUT-1');
  v_rack_cap_id uuid := (select id from app.warehouse_locations where tenant_id = v_tenant1 and code = 'RACK-PUT-CAP');
  v_line4 app.wms_receipt_lines;
  v_task app.wms_putaway_tasks;
begin
  select * into v_line4 from app.wms_receipt_lines where receipt_session_id = v_session_id and line_number = 4;
  v_task := app.generate_wms_putaway_task(v_line4.id, 20, v_rack_cap_id, 'idem-gen-l4', '00000000-0000-0000-0000-000000120102', 'rep');
  v_task := app.claim_wms_putaway_task(v_task.id, v_task.record_version, '00000000-0000-0000-0000-000000120102', 'rep');

  begin
    perform app.confirm_wms_putaway_task(v_task.id, 20, v_rack_cap_id, null, null, 'idem-confirm-l4-full', v_task.record_version, '00000000-0000-0000-0000-000000120102', 'rep');
    raise exception 'assertion failed: expected destination_full -- RACK-PUT-CAP only has capacity 5';
  exception
    when others then
      if sqlerrm not like 'destination_full%' then raise; end if;
  end;

  v_task := app.confirm_wms_putaway_task(v_task.id, 20, v_rack1_id, null, null, 'idem-confirm-l4-ok', v_task.record_version, '00000000-0000-0000-0000-000000120102', 'rep');
  if v_task.status <> 'confirmed' then
    raise exception 'assertion failed: expected task L4 to confirm cleanly once redirected to RACK-PUT-1';
  end if;
end $$;

\echo '>> L4b cross-task capacity aggregation at RACK-PUT-CAP: the destination_full check sums on_hand across every task/item sharing the bin, never just the confirming task''s own contribution -- two different tasks (from two different receipt lines, claimed by two different reps) both targeting the same capacity-5 rack: the first confirms 3 units cleanly, the second is rejected destination_full for 3 more (3+3 > 5), then succeeds for exactly the remaining 2. app.confirm_wms_putaway_task now locks the destination app.warehouse_locations row (SELECT ... FOR UPDATE) before this aggregate read specifically so this stays correct under real concurrent confirms to the same destination, not only this sequential ordering -- ISS-2026-014 discloses no multi-session harness exists yet in this test runner to prove the lock''s serialization empirically (the identical disclosed boundary already used above for app.claim_wms_putaway_task''s own concurrent-claim-race guard); this sequential case at least proves the guard''s own outcome (aggregate, cross-task, cross-item occupancy) is exactly right.'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'wmsput1');
  v_warehouse_id uuid := (select id from app.warehouses where tenant_id = v_tenant1 and code = 'WH-PUT-1');
  v_dock1_id uuid := (select id from app.warehouse_locations where tenant_id = v_tenant1 and code = 'DOCK-PUT-1');
  v_account_id uuid := (select id from app.accounts where tenant_id = v_tenant1 and legal_name = 'WmsPut Customer Alpha');
  v_plain_id uuid := (select id from app.item_masters where tenant_id = v_tenant1 and code = 'SKU-PUT-PLAIN');
  v_rack_cap_id uuid := (select id from app.warehouse_locations where tenant_id = v_tenant1 and code = 'RACK-PUT-CAP');
  v_order app.wms_inbound_orders;
  v_lines app.wms_inbound_order_lines[];
  v_session app.wms_receipt_sessions;
  v_lineA app.wms_receipt_lines;
  v_lineB app.wms_receipt_lines;
  v_taskA app.wms_putaway_tasks;
  v_taskB app.wms_putaway_tasks;
begin
  v_order := app.create_manual_wms_inbound(v_tenant1, v_warehouse_id, v_account_id, 'L4b cross-task capacity fixture', 'idem-put-l4b', '00000000-0000-0000-0000-000000120102', 'rep');
  select array_agg(l) into v_lines from app.add_wms_inbound_order_lines(
    v_order.id,
    jsonb_build_array(
      jsonb_build_object('item_master_id', v_plain_id, 'expected_uom_code', 'PCS', 'expected_quantity', 3, 'notes', 'L4b task A'),
      jsonb_build_object('item_master_id', v_plain_id, 'expected_uom_code', 'PCS', 'expected_quantity', 3, 'notes', 'L4b task B')
    ),
    '00000000-0000-0000-0000-000000120102', 'rep'
  ) l;

  v_order := app.schedule_wms_inbound_appointment(v_order.id, now() + interval '1 day', now() + interval '1 day' + interval '2 hours', v_order.record_version, '00000000-0000-0000-0000-000000120102', 'rep');
  v_order := app.confirm_wms_inbound(v_order.id, v_order.record_version, '00000000-0000-0000-0000-000000120102', 'rep');

  v_session := app.start_wms_receipt_session(v_order.id, v_dock1_id, 'idem-put-l4b-session', '00000000-0000-0000-0000-000000120102', 'rep');
  select * into v_lineA from app.wms_receipt_lines where receipt_session_id = v_session.id and line_number = 1;
  select * into v_lineB from app.wms_receipt_lines where receipt_session_id = v_session.id and line_number = 2;
  v_lineA := app.record_wms_receipt_line_count(v_lineA.id, null, 3, 3, 0, 0, 0, null, null, null, 'L4b fixture A', v_lineA.record_version, '00000000-0000-0000-0000-000000120102', 'rep');
  v_lineB := app.record_wms_receipt_line_count(v_lineB.id, null, 3, 3, 0, 0, 0, null, null, null, 'L4b fixture B', v_lineB.record_version, '00000000-0000-0000-0000-000000120102', 'rep');
  v_lineA := app.commit_wms_receipt_line(v_lineA.id, 'idem-put-l4b-commitA', v_lineA.record_version, '00000000-0000-0000-0000-000000120102', 'rep');
  v_lineB := app.commit_wms_receipt_line(v_lineB.id, 'idem-put-l4b-commitB', v_lineB.record_version, '00000000-0000-0000-0000-000000120102', 'rep');

  v_taskA := app.generate_wms_putaway_task(v_lineA.id, 3, v_rack_cap_id, 'idem-gen-l4b-A', '00000000-0000-0000-0000-000000120102', 'rep');
  v_taskB := app.generate_wms_putaway_task(v_lineB.id, 3, v_rack_cap_id, 'idem-gen-l4b-B', '00000000-0000-0000-0000-000000120102', 'rep');
  v_taskA := app.claim_wms_putaway_task(v_taskA.id, v_taskA.record_version, '00000000-0000-0000-0000-000000120102', 'rep');
  v_taskB := app.claim_wms_putaway_task(v_taskB.id, v_taskB.record_version, '00000000-0000-0000-0000-000000120108', 'rep2');

  -- Task A fully consumes 3 of RACK-PUT-CAP's 5-unit capacity.
  v_taskA := app.confirm_wms_putaway_task(v_taskA.id, 3, v_rack_cap_id, null, null, 'idem-confirm-l4b-A', v_taskA.record_version, '00000000-0000-0000-0000-000000120102', 'rep');
  if v_taskA.status <> 'confirmed' then
    raise exception 'assertion failed: expected task L4b-A to confirm cleanly (3 of 5 capacity), got status=%', v_taskA.status;
  end if;

  -- Task B -- a wholly different task, item lot, and claimant -- must still be
  -- rejected destination_full: 3 (A's own on-hand) + 3 (B's request) > 5. This is the
  -- exact aggregate the destination-lock fix protects: it is never just "this task's
  -- own prior contribution" but every real on_hand unit at the location.
  begin
    perform app.confirm_wms_putaway_task(v_taskB.id, 3, v_rack_cap_id, null, null, 'idem-confirm-l4b-B-full', v_taskB.record_version, '00000000-0000-0000-0000-000000120108', 'rep2');
    raise exception 'assertion failed: expected destination_full -- task A already occupies 3 of RACK-PUT-CAP''s 5-unit capacity';
  exception
    when others then
      if sqlerrm not like 'destination_full%' then raise; end if;
  end;

  -- Exactly the remaining 2 units succeeds.
  v_taskB := app.confirm_wms_putaway_task(v_taskB.id, 2, v_rack_cap_id, null, null, 'idem-confirm-l4b-B-partial', v_taskB.record_version, '00000000-0000-0000-0000-000000120108', 'rep2');
  if v_taskB.confirmed_quantity <> 2 or v_taskB.status <> 'partial' then
    raise exception 'assertion failed: expected task L4b-B partially confirmed at exactly 2 units (the remaining headroom), got confirmed=%/status=%', v_taskB.confirmed_quantity, v_taskB.status;
  end if;

  if (select coalesce(sum(on_hand), 0) from app.inventory_balances where location_id = v_rack_cap_id and status = 'on_hand') <> 5 then
    raise exception 'assertion failed: expected RACK-PUT-CAP to sit at exactly its 5-unit capacity after both tasks'' confirms';
  end if;
end $$;

\echo '>> L5 destination eligibility rejections: location_not_found; incompatible_location for a wrong-warehouse actual destination; incompatible_location for a dock/staging actual destination (must be rack/shelf/bin); blocked_destination for an inactive rack; incompatible_location for a not-putaway-enabled rack; then a real eligible destination succeeds'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'wmsput1');
  v_session_id uuid := (select id from app.wms_receipt_sessions where tenant_id = v_tenant1 and idempotency_key = 'idem-put-recvsession');
  v_stage1_id uuid := (select id from app.warehouse_locations where tenant_id = v_tenant1 and code = 'STAGE-PUT-1');
  v_rack1_id uuid := (select id from app.warehouse_locations where tenant_id = v_tenant1 and code = 'RACK-PUT-1');
  v_rack_wh2_id uuid := (select id from app.warehouse_locations where tenant_id = v_tenant1 and code = 'RACK-PUT-WH2');
  v_rack_inactive_id uuid := (select id from app.warehouse_locations where tenant_id = v_tenant1 and code = 'RACK-PUT-INACTIVE');
  v_rack_notenabled_id uuid := (select id from app.warehouse_locations where tenant_id = v_tenant1 and code = 'RACK-PUT-NOTENABLED');
  v_line5 app.wms_receipt_lines;
  v_task app.wms_putaway_tasks;
begin
  select * into v_line5 from app.wms_receipt_lines where receipt_session_id = v_session_id and line_number = 5;
  v_task := app.generate_wms_putaway_task(v_line5.id, 10, null, 'idem-gen-l5', '00000000-0000-0000-0000-000000120102', 'rep');
  v_task := app.claim_wms_putaway_task(v_task.id, v_task.record_version, '00000000-0000-0000-0000-000000120102', 'rep');

  begin
    perform app.confirm_wms_putaway_task(v_task.id, 10, gen_random_uuid(), null, null, 'idem-confirm-l5-badloc', v_task.record_version, '00000000-0000-0000-0000-000000120102', 'rep');
    raise exception 'assertion failed: expected location_not_found';
  exception
    when others then
      if sqlerrm not like 'location_not_found%' then raise; end if;
  end;

  begin
    perform app.confirm_wms_putaway_task(v_task.id, 10, v_rack_wh2_id, null, null, 'idem-confirm-l5-wrongwh', v_task.record_version, '00000000-0000-0000-0000-000000120102', 'rep');
    raise exception 'assertion failed: expected incompatible_location -- RACK-PUT-WH2 belongs to WH-PUT-2';
  exception
    when others then
      if sqlerrm not like 'incompatible_location%' then raise; end if;
  end;

  begin
    perform app.confirm_wms_putaway_task(v_task.id, 10, v_stage1_id, null, null, 'idem-confirm-l5-dock', v_task.record_version, '00000000-0000-0000-0000-000000120102', 'rep');
    raise exception 'assertion failed: expected incompatible_location -- STAGE-PUT-1 is staging, not rack/shelf/bin';
  exception
    when others then
      if sqlerrm not like 'incompatible_location%' then raise; end if;
  end;

  begin
    perform app.confirm_wms_putaway_task(v_task.id, 10, v_rack_inactive_id, null, null, 'idem-confirm-l5-inactive', v_task.record_version, '00000000-0000-0000-0000-000000120102', 'rep');
    raise exception 'assertion failed: expected blocked_destination -- RACK-PUT-INACTIVE is not active';
  exception
    when others then
      if sqlerrm not like 'blocked_destination%' then raise; end if;
  end;

  begin
    perform app.confirm_wms_putaway_task(v_task.id, 10, v_rack_notenabled_id, null, null, 'idem-confirm-l5-notenabled', v_task.record_version, '00000000-0000-0000-0000-000000120102', 'rep');
    raise exception 'assertion failed: expected incompatible_location -- RACK-PUT-NOTENABLED is not putaway_enabled';
  exception
    when others then
      if sqlerrm not like 'incompatible_location%' then raise; end if;
  end;

  v_task := app.confirm_wms_putaway_task(v_task.id, 10, v_rack1_id, null, null, 'idem-confirm-l5-ok', v_task.record_version, '00000000-0000-0000-0000-000000120102', 'rep');
  if v_task.status <> 'confirmed' then
    raise exception 'assertion failed: expected task L5 to confirm cleanly at RACK-PUT-1 once a real eligible destination was used';
  end if;
end $$;

\echo '>> L6 lot-controlled: missing_lot and lot_mismatch rejected; a matching lot succeeds. L7 serial-controlled: missing_serial and serial_mismatch rejected; a matching serial succeeds -- these are the owner/item/lot/serial mismatch rejections named in Prompt 233 section 25 (owner/item are never caller-supplied at confirm time, so a snapshot-based lot/serial identity mismatch is this design''s own real analogue)'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'wmsput1');
  v_session_id uuid := (select id from app.wms_receipt_sessions where tenant_id = v_tenant1 and idempotency_key = 'idem-put-recvsession');
  v_rack1_id uuid := (select id from app.warehouse_locations where tenant_id = v_tenant1 and code = 'RACK-PUT-1');
  v_bin1_id uuid := (select id from app.warehouse_locations where tenant_id = v_tenant1 and code = 'BIN-PUT-1');
  v_line6 app.wms_receipt_lines;
  v_line7 app.wms_receipt_lines;
  v_task6 app.wms_putaway_tasks;
  v_task7 app.wms_putaway_tasks;
begin
  select * into v_line6 from app.wms_receipt_lines where receipt_session_id = v_session_id and line_number = 6;
  select * into v_line7 from app.wms_receipt_lines where receipt_session_id = v_session_id and line_number = 7;

  v_task6 := app.generate_wms_putaway_task(v_line6.id, 5, null, 'idem-gen-l6', '00000000-0000-0000-0000-000000120102', 'rep');
  v_task6 := app.claim_wms_putaway_task(v_task6.id, v_task6.record_version, '00000000-0000-0000-0000-000000120102', 'rep');

  begin
    perform app.confirm_wms_putaway_task(v_task6.id, 5, v_rack1_id, null, null, 'idem-confirm-l6-missinglot', v_task6.record_version, '00000000-0000-0000-0000-000000120102', 'rep');
    raise exception 'assertion failed: expected missing_lot';
  exception
    when others then
      if sqlerrm not like 'missing_lot%' then raise; end if;
  end;

  begin
    perform app.confirm_wms_putaway_task(v_task6.id, 5, v_rack1_id, 'LOT-PUT-WRONG', null, 'idem-confirm-l6-wronglot', v_task6.record_version, '00000000-0000-0000-0000-000000120102', 'rep');
    raise exception 'assertion failed: expected lot_mismatch';
  exception
    when others then
      if sqlerrm not like 'lot_mismatch%' then raise; end if;
  end;

  v_task6 := app.confirm_wms_putaway_task(v_task6.id, 5, v_rack1_id, 'LOT-PUT-001', null, 'idem-confirm-l6-ok', v_task6.record_version, '00000000-0000-0000-0000-000000120102', 'rep');
  if v_task6.status <> 'confirmed' then
    raise exception 'assertion failed: expected task L6 to confirm with the matching lot number';
  end if;

  v_task7 := app.generate_wms_putaway_task(v_line7.id, 1, null, 'idem-gen-l7', '00000000-0000-0000-0000-000000120102', 'rep');
  v_task7 := app.claim_wms_putaway_task(v_task7.id, v_task7.record_version, '00000000-0000-0000-0000-000000120102', 'rep');

  begin
    perform app.confirm_wms_putaway_task(v_task7.id, 1, v_bin1_id, null, null, 'idem-confirm-l7-missingserial', v_task7.record_version, '00000000-0000-0000-0000-000000120102', 'rep');
    raise exception 'assertion failed: expected missing_serial';
  exception
    when others then
      if sqlerrm not like 'missing_serial%' then raise; end if;
  end;

  begin
    perform app.confirm_wms_putaway_task(v_task7.id, 1, v_bin1_id, null, 'SN-PUT-WRONG', 'idem-confirm-l7-wrongserial', v_task7.record_version, '00000000-0000-0000-0000-000000120102', 'rep');
    raise exception 'assertion failed: expected serial_mismatch';
  exception
    when others then
      if sqlerrm not like 'serial_mismatch%' then raise; end if;
  end;

  v_task7 := app.confirm_wms_putaway_task(v_task7.id, 1, v_bin1_id, null, 'SN-PUT-001', 'idem-confirm-l7-ok', v_task7.record_version, '00000000-0000-0000-0000-000000120102', 'rep');
  if v_task7.status <> 'confirmed' then
    raise exception 'assertion failed: expected task L7 to confirm with the matching serial number';
  end if;
end $$;

\echo '>> L8 exception + supervisor reassign/release: a plain rep cannot reassign (lacks OPS:Override); confirming an exception task is rejected task_exception; supervisor reassigns to rep2, who then confirms; a second, separate task is released (reassign to null claimant) back to unclaimed and re-claimed by a different rep'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'wmsput1');
  v_session_id uuid := (select id from app.wms_receipt_sessions where tenant_id = v_tenant1 and idempotency_key = 'idem-put-recvsession');
  v_rack1_id uuid := (select id from app.warehouse_locations where tenant_id = v_tenant1 and code = 'RACK-PUT-1');
  v_line8 app.wms_receipt_lines;
  v_task_a app.wms_putaway_tasks;
  v_task_b app.wms_putaway_tasks;
begin
  select * into v_line8 from app.wms_receipt_lines where receipt_session_id = v_session_id and line_number = 8;

  -- Task A (20 units): claim -> exception -> supervisor reassigns to rep2 -> rep2 confirms.
  v_task_a := app.generate_wms_putaway_task(v_line8.id, 20, null, 'idem-gen-l8a', '00000000-0000-0000-0000-000000120102', 'rep');
  v_task_a := app.claim_wms_putaway_task(v_task_a.id, v_task_a.record_version, '00000000-0000-0000-0000-000000120102', 'rep');

  begin
    perform app.mark_wms_putaway_task_exception(v_task_a.id, '', v_task_a.record_version, '00000000-0000-0000-0000-000000120102', 'rep');
    raise exception 'assertion failed: expected invalid_reason -- empty reason';
  exception
    when others then
      if sqlerrm not like 'invalid_reason%' then raise; end if;
  end;

  v_task_a := app.mark_wms_putaway_task_exception(v_task_a.id, 'RACK-PUT-1 aisle blocked by a forklift', v_task_a.record_version, '00000000-0000-0000-0000-000000120102', 'rep');
  if v_task_a.status <> 'exception' or v_task_a.exception_reason is null then
    raise exception 'assertion failed: expected task A under exception with a real reason recorded';
  end if;

  -- Idempotent no-op re-mark, only after authority is confirmed.
  if (app.mark_wms_putaway_task_exception(v_task_a.id, 'different reason', v_task_a.record_version, '00000000-0000-0000-0000-000000120102', 'rep')).exception_reason <> v_task_a.exception_reason then
    raise exception 'assertion failed: expected an already-exception task to be a no-op regardless of the new reason argument';
  end if;

  begin
    perform app.confirm_wms_putaway_task(v_task_a.id, 20, v_rack1_id, null, null, 'idem-confirm-l8a-blocked', v_task_a.record_version, '00000000-0000-0000-0000-000000120102', 'rep');
    raise exception 'assertion failed: expected task_exception -- task A is under an unresolved exception';
  exception
    when others then
      if sqlerrm not like 'task_exception%' then raise; end if;
  end;

  begin
    perform app.reassign_wms_putaway_task(v_task_a.id, '00000000-0000-0000-0000-000000120108', 'rep2', 'rep2 will finish this one', v_task_a.record_version, '00000000-0000-0000-0000-000000120102', 'rep');
    raise exception 'assertion failed: expected insufficient_authority -- rep lacks OPS:Override';
  exception
    when others then
      if sqlerrm not like 'insufficient_authority%' then raise; end if;
  end;

  v_task_a := app.reassign_wms_putaway_task(v_task_a.id, '00000000-0000-0000-0000-000000120108', 'rep2', 'aisle cleared, reassigning to rep2 to finish', v_task_a.record_version, '00000000-0000-0000-0000-000000120104', 'supervisor');
  if v_task_a.status <> 'claimed' or v_task_a.claimed_by_auth_user_id <> '00000000-0000-0000-0000-000000120108' then
    raise exception 'assertion failed: expected task A reassigned to rep2 and back to claimed, got status=%/claimed_by=%', v_task_a.status, v_task_a.claimed_by_auth_user_id;
  end if;

  begin
    perform app.confirm_wms_putaway_task(v_task_a.id, 20, v_rack1_id, null, null, 'idem-confirm-l8a-original-rep', v_task_a.record_version, '00000000-0000-0000-0000-000000120102', 'rep');
    raise exception 'assertion failed: expected not_task_claimant -- rep is no longer the assigned claimant after reassignment';
  exception
    when others then
      if sqlerrm not like 'not_task_claimant%' then raise; end if;
  end;

  v_task_a := app.confirm_wms_putaway_task(v_task_a.id, 20, v_rack1_id, null, null, 'idem-confirm-l8a-rep2', v_task_a.record_version, '00000000-0000-0000-0000-000000120108', 'rep2');
  if v_task_a.status <> 'confirmed' then
    raise exception 'assertion failed: expected task A to confirm once rep2 held the reassigned claim';
  end if;

  -- Task B (10 units): claim -> release (reassign to null claimant) -> re-claimed by a
  -- different rep, resuming from unclaimed (Prompt 233 section 32: release uncommitted task).
  v_task_b := app.generate_wms_putaway_task(v_line8.id, 10, null, 'idem-gen-l8b', '00000000-0000-0000-0000-000000120102', 'rep');
  v_task_b := app.claim_wms_putaway_task(v_task_b.id, v_task_b.record_version, '00000000-0000-0000-0000-000000120102', 'rep');
  v_task_b := app.reassign_wms_putaway_task(v_task_b.id, null, null, 'rep called in sick, releasing the task', v_task_b.record_version, '00000000-0000-0000-0000-000000120104', 'supervisor');
  if v_task_b.status <> 'unclaimed' or v_task_b.claimed_by_auth_user_id is not null then
    raise exception 'assertion failed: expected task B released back to unclaimed with no claimant, got status=%/claimed_by=%', v_task_b.status, v_task_b.claimed_by_auth_user_id;
  end if;

  v_task_b := app.claim_wms_putaway_task(v_task_b.id, v_task_b.record_version, '00000000-0000-0000-0000-000000120108', 'rep2');
  v_task_b := app.confirm_wms_putaway_task(v_task_b.id, 10, v_rack1_id, null, null, 'idem-confirm-l8b', v_task_b.record_version, '00000000-0000-0000-0000-000000120108', 'rep2');
  if v_task_b.status <> 'confirmed' then
    raise exception 'assertion failed: expected task B to confirm once re-claimed by rep2';
  end if;

  begin
    perform app.reassign_wms_putaway_task(v_task_b.id, '00000000-0000-0000-0000-000000120102', 'rep', 'too late, already confirmed', v_task_b.record_version, '00000000-0000-0000-0000-000000120104', 'supervisor');
    raise exception 'assertion failed: expected invalid_transition -- a confirmed task may never be reassigned';
  exception
    when others then
      if sqlerrm not like 'invalid_transition%' then raise; end if;
  end;
end $$;

\echo '>> L9 cancel task: an unclaimed/claimed task with zero confirmed_quantity cancels cleanly, freeing the receipt line''s own remaining quantity for a fresh generation call; a task with any real confirmed_quantity cannot be cancelled (has_confirmed_quantity)'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'wmsput1');
  v_session_id uuid := (select id from app.wms_receipt_sessions where tenant_id = v_tenant1 and idempotency_key = 'idem-put-recvsession');
  v_rack1_id uuid := (select id from app.warehouse_locations where tenant_id = v_tenant1 and code = 'RACK-PUT-1');
  v_line9 app.wms_receipt_lines;
  v_task_a app.wms_putaway_tasks;
  v_task_b app.wms_putaway_tasks;
  v_fresh app.wms_putaway_tasks;
begin
  select * into v_line9 from app.wms_receipt_lines where receipt_session_id = v_session_id and line_number = 9;

  v_task_a := app.generate_wms_putaway_task(v_line9.id, 10, null, 'idem-gen-l9a', '00000000-0000-0000-0000-000000120102', 'rep');
  v_task_a := app.claim_wms_putaway_task(v_task_a.id, v_task_a.record_version, '00000000-0000-0000-0000-000000120102', 'rep');

  begin
    perform app.cancel_wms_putaway_task(v_task_a.id, '', v_task_a.record_version, '00000000-0000-0000-0000-000000120102', 'rep');
    raise exception 'assertion failed: expected invalid_reason';
  exception
    when others then
      if sqlerrm not like 'invalid_reason%' then raise; end if;
  end;

  v_task_a := app.cancel_wms_putaway_task(v_task_a.id, 'generated against the wrong line by mistake', v_task_a.record_version, '00000000-0000-0000-0000-000000120102', 'rep');
  if v_task_a.status <> 'cancelled' then
    raise exception 'assertion failed: expected task A cancelled';
  end if;

  -- Idempotent no-op re-cancel.
  if (app.cancel_wms_putaway_task(v_task_a.id, 'again', v_task_a.record_version, '00000000-0000-0000-0000-000000120102', 'rep')).record_version <> v_task_a.record_version then
    raise exception 'assertion failed: expected an already-cancelled task to be a no-op regardless of the reason argument';
  end if;

  -- The freed 10 units may now be reallocated by a fresh generation call for the full
  -- remaining 15 (10 cancelled + 5 never allocated).
  v_fresh := app.generate_wms_putaway_task(v_line9.id, 15, null, 'idem-gen-l9-fresh', '00000000-0000-0000-0000-000000120102', 'rep');
  if v_fresh.id = v_task_a.id or v_fresh.task_quantity <> 15 then
    raise exception 'assertion failed: expected a genuinely new 15-unit task, not the cancelled one';
  end if;

  v_task_b := app.claim_wms_putaway_task(v_fresh.id, v_fresh.record_version, '00000000-0000-0000-0000-000000120102', 'rep');
  v_task_b := app.confirm_wms_putaway_task(v_task_b.id, 5, v_rack1_id, null, null, 'idem-confirm-l9-partial', v_task_b.record_version, '00000000-0000-0000-0000-000000120102', 'rep');
  if v_task_b.status <> 'partial' or v_task_b.confirmed_quantity <> 5 then
    raise exception 'assertion failed: expected task B partial at confirmed_quantity=5';
  end if;

  begin
    perform app.cancel_wms_putaway_task(v_task_b.id, 'changed my mind after already confirming', v_task_b.record_version, '00000000-0000-0000-0000-000000120102', 'rep');
    raise exception 'assertion failed: expected has_confirmed_quantity -- task B already has 5 real confirmed units';
  exception
    when others then
      if sqlerrm not like 'has_confirmed_quantity%' then raise; end if;
  end;

  -- Finish it off cleanly instead.
  v_task_b := app.confirm_wms_putaway_task(v_task_b.id, 10, v_rack1_id, null, null, 'idem-confirm-l9-rest', v_task_b.record_version, '00000000-0000-0000-0000-000000120102', 'rep');
  if v_task_b.status <> 'confirmed' then
    raise exception 'assertion failed: expected task B to finish confirming';
  end if;
end $$;

\echo '>> L12 validation sandbox wrap-up: app.confirm_wms_putaway_task rejects an empty idempotency_key, then the task claimed earlier finishes confirming cleanly'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'wmsput1');
  v_rack1_id uuid := (select id from app.warehouse_locations where tenant_id = v_tenant1 and code = 'RACK-PUT-1');
  v_task app.wms_putaway_tasks;
begin
  select * into v_task from app.wms_putaway_tasks where tenant_id = v_tenant1 and idempotency_key = 'idem-gen-l12';

  begin
    perform app.confirm_wms_putaway_task(v_task.id, 5, v_rack1_id, null, null, '', v_task.record_version, '00000000-0000-0000-0000-000000120102', 'rep');
    raise exception 'assertion failed: expected invalid_idempotency_key -- empty key';
  exception
    when others then
      if sqlerrm not like 'invalid_idempotency_key%' then raise; end if;
  end;

  v_task := app.confirm_wms_putaway_task(v_task.id, 5, v_rack1_id, null, null, 'idem-confirm-l12', v_task.record_version, '00000000-0000-0000-0000-000000120102', 'rep');
  if v_task.status <> 'confirmed' then
    raise exception 'assertion failed: expected L12''s task to confirm cleanly once a real idempotency_key was supplied';
  end if;
end $$;

\echo '>> L11 real insufficient_stock at confirm time (run last among the confirm sections -- it deliberately drains DOCK-PUT-1''s own shared plain-item balance to exactly 4, so it must not run before any other section still relying on that pooled balance): a task is generated for the full accepted quantity, then a legitimate governed adjustment (e.g. damage discovered at the dock after generation but before putaway) reduces the real on-hand balance below what the task still needs -- app.post_inventory_movement''s own insufficient_stock guard rejects the confirm, the defense-in-depth safety net behind the generation-time insufficient_remaining_quantity gate'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'wmsput1');
  v_session_id uuid := (select id from app.wms_receipt_sessions where tenant_id = v_tenant1 and idempotency_key = 'idem-put-recvsession');
  v_warehouse_id uuid := (select id from app.warehouses where tenant_id = v_tenant1 and code = 'WH-PUT-1');
  v_dock1_id uuid := (select id from app.warehouse_locations where tenant_id = v_tenant1 and code = 'DOCK-PUT-1');
  v_rack1_id uuid := (select id from app.warehouse_locations where tenant_id = v_tenant1 and code = 'RACK-PUT-1');
  v_account_id uuid := (select id from app.accounts where tenant_id = v_tenant1 and legal_name = 'WmsPut Customer Alpha');
  v_plain_id uuid := (select id from app.item_masters where tenant_id = v_tenant1 and code = 'SKU-PUT-PLAIN');
  v_line11 app.wms_receipt_lines;
  v_task app.wms_putaway_tasks;
  v_current_dock_balance numeric;
begin
  select * into v_line11 from app.wms_receipt_lines where receipt_session_id = v_session_id and line_number = 11;
  v_task := app.generate_wms_putaway_task(v_line11.id, 10, null, 'idem-gen-l11', '00000000-0000-0000-0000-000000120102', 'rep');
  v_task := app.claim_wms_putaway_task(v_task.id, v_task.record_version, '00000000-0000-0000-0000-000000120102', 'rep');

  -- DOCK-PUT-1's own on_hand for this item/owner dimension is a real pooled balance
  -- shared across every plain-item receipt line put through it (design note 6, ATW-015)
  -- -- not per-receipt-line -- so the adjustment below is computed against the actual
  -- current pooled balance, driving it down to exactly 4 regardless of how much of it
  -- other sections have already confirmed away by this point in the script.
  select on_hand into v_current_dock_balance from app.inventory_balances
    where tenant_id = v_tenant1 and warehouse_id = v_warehouse_id and owner_account_id = v_account_id and item_master_id = v_plain_id
      and location_id = v_dock1_id and lot_number is null and serial_number is null and status = 'on_hand';
  if v_current_dock_balance < 10 then
    raise exception 'assertion failed: test fixture invariant broken -- expected at least 10 units still on-hand at DOCK-PUT-1 for L11''s own task, got %', v_current_dock_balance;
  end if;

  -- Damage discovered at the dock after the task was generated -- a real, separate,
  -- governed adjustment movement (never a bare balance edit) drops on-hand to exactly 4.
  perform app.post_inventory_movement(
    v_tenant1, v_warehouse_id, 'adjustment', 'manual', null, 'idem-l11-damage-adjustment', 'damage discovered on the dock floor after putaway task generation',
    jsonb_build_array(jsonb_build_object(
      'owner_account_id', v_account_id, 'item_master_id', v_plain_id, 'location_id', v_dock1_id,
      'uom_code', 'PCS', 'signed_quantity', -(v_current_dock_balance - 4), 'status', 'on_hand'
    )),
    '00000000-0000-0000-0000-000000120104', 'supervisor'
  );

  begin
    perform app.confirm_wms_putaway_task(v_task.id, 10, v_rack1_id, null, null, 'idem-confirm-l11-insufficient', v_task.record_version, '00000000-0000-0000-0000-000000120102', 'rep');
    raise exception 'assertion failed: expected insufficient_stock -- only 4 units remain on-hand at DOCK-PUT-1 after the adjustment';
  exception
    when others then
      if sqlerrm not like 'insufficient_stock%' then raise; end if;
  end;

  v_task := app.confirm_wms_putaway_task(v_task.id, 4, v_rack1_id, null, null, 'idem-confirm-l11-whatsleft', v_task.record_version, '00000000-0000-0000-0000-000000120102', 'rep');
  if v_task.status <> 'partial' or v_task.confirmed_quantity <> 4 then
    raise exception 'assertion failed: expected task L11 partial at confirmed_quantity=4 (the real remaining dock balance)';
  end if;
end $$;

\echo '>> reads: app.list_wms_putaway_tasks / app.get_wms_putaway_task / app.list_wms_putaway_task_confirmations: bounded, filtered by status/receipt_line/claimed_by, cross-tenant isolation'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'wmsput1');
  v_tenant2 uuid := (select id from app.tenants where slug = 'wmsput2');
  v_warehouse_id uuid := (select id from app.warehouses where tenant_id = v_tenant1 and code = 'WH-PUT-1');
  v_task_l1 app.wms_putaway_tasks;
  v_confirmations app.wms_putaway_confirmations[];
  v_count integer;
begin
  select * into v_task_l1 from app.wms_putaway_tasks where tenant_id = v_tenant1 and idempotency_key = 'idem-gen-l1';

  select count(*) into v_count from app.list_wms_putaway_tasks(v_tenant1, '00000000-0000-0000-0000-000000120102', v_warehouse_id, null, null, null, 200);
  if v_count < 10 then
    raise exception 'assertion failed: expected at least 10 putaway tasks under WH-PUT-1, got %', v_count;
  end if;

  select count(*) into v_count from app.list_wms_putaway_tasks(v_tenant1, '00000000-0000-0000-0000-000000120102', v_warehouse_id, null, 'cancelled', null, 50);
  if v_count <> 1 then
    raise exception 'assertion failed: expected exactly 1 cancelled task (L9 task A), got %', v_count;
  end if;

  select count(*) into v_count from app.list_wms_putaway_tasks(v_tenant1, '00000000-0000-0000-0000-000000120102', v_warehouse_id, v_task_l1.receipt_line_id, null, null, 50);
  if v_count <> 1 then
    raise exception 'assertion failed: expected exactly 1 task against L1''s own receipt line, got %', v_count;
  end if;

  select count(*) into v_count from app.list_wms_putaway_tasks(v_tenant1, '00000000-0000-0000-0000-000000120102', v_warehouse_id, null, null, null, 0);
  if v_count <> 1 then
    raise exception 'assertion failed: expected p_limit=0 to clamp up to 1, got %', v_count;
  end if;

  if (app.get_wms_putaway_task(v_task_l1.id, '00000000-0000-0000-0000-000000120102')).id <> v_task_l1.id then
    raise exception 'assertion failed: expected get_wms_putaway_task to return the identical row';
  end if;

  select array_agg(c order by c.confirmed_at) into v_confirmations from app.list_wms_putaway_task_confirmations(v_task_l1.id, '00000000-0000-0000-0000-000000120102') c;
  if array_length(v_confirmations, 1) <> 1 or v_confirmations[1].quantity <> 100 then
    raise exception 'assertion failed: expected exactly 1 confirmation of 100 units on task L1, got count=%', array_length(v_confirmations, 1);
  end if;

  begin
    -- ISS-2026-146: tenant2's rep (wmsput2) holds no membership in wmsput1, so app.get_wms_putaway_task
    -- now collapses that zero-membership case into its own generic
    -- task_not_found / no_data_found branch -- byte-identical to what a
    -- nonexistent id already produced, so the real tenant_id is never disclosed to an
    -- outsider. A genuine same-tenant member lacking the role still gets
    -- insufficient_authority, unchanged (asserted elsewhere in this file).
    perform app.get_wms_putaway_task(v_task_l1.id, '00000000-0000-0000-0000-000000120107');
    raise exception 'assertion failed: expected task_not_found -- tenant2''s rep has no membership in tenant1';
  exception
    when others then
      if sqlerrm not like 'task_not_found%' then raise; end if;
  end;

  select count(*) into v_count from app.list_wms_putaway_tasks(v_tenant2, '00000000-0000-0000-0000-000000120107', null, null, null, null, 50);
  if v_count <> 0 then
    raise exception 'assertion failed: expected tenant2''s own rep to see zero putaway tasks (none created there)';
  end if;
end $$;

\echo '>> regression: every idempotent-replay short-circuit runs strictly after authority/tenant-scope is confirmed -- tenant2''s rep, who holds zero membership in tenant1, is rejected insufficient_authority on tenant1''s real already-generated/claimed/confirmed/exception/cancelled records, never handed live business data off any of them'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'wmsput1');
  v_task_l1 app.wms_putaway_tasks;
  v_task_l8a app.wms_putaway_tasks;
  v_task_l9_cancelled app.wms_putaway_tasks;
begin
  select * into v_task_l1 from app.wms_putaway_tasks where tenant_id = v_tenant1 and idempotency_key = 'idem-gen-l1';
  select * into v_task_l8a from app.wms_putaway_tasks where tenant_id = v_tenant1 and idempotency_key = 'idem-gen-l8a';
  select * into v_task_l9_cancelled from app.wms_putaway_tasks where tenant_id = v_tenant1 and idempotency_key = 'idem-gen-l9a';

  -- app.generate_wms_putaway_task's own idempotent short-circuit keys off
  -- (tenant_id, idempotency_key) resolved from the *receipt line's own tenant*, not
  -- the caller -- an attacker supplying tenant1's real receipt_line_id and idempotency
  -- key must still be rejected on authority before ever reaching it.
  begin
    perform app.generate_wms_putaway_task(v_task_l1.receipt_line_id, 100, null, 'idem-gen-l1', '00000000-0000-0000-0000-000000120107', 'rep2b-attacker');
    raise exception 'assertion failed: expected insufficient_authority -- tenant2''s rep must not reach the idempotent-replay short-circuit on tenant1''s real receipt line';
  exception
    when others then
      if sqlerrm not like 'insufficient_authority%' then raise; end if;
  end;

  begin
    -- ISS-2026-146: tenant2's rep (wmsput2) holds no membership in wmsput1, so app.claim_wms_putaway_task
    -- now collapses that zero-membership case into its own generic
    -- task_not_found / no_data_found branch -- byte-identical to what a
    -- nonexistent id already produced, so the real tenant_id is never disclosed to an
    -- outsider. A genuine same-tenant member lacking the role still gets
    -- insufficient_authority, unchanged (asserted elsewhere in this file).
    perform app.claim_wms_putaway_task(v_task_l1.id, 999999, '00000000-0000-0000-0000-000000120107', 'rep2b-attacker');
    raise exception 'assertion failed: expected task_not_found -- tenant2''s rep must not reach the claim short-circuit on tenant1''s already-claimed task';
  exception
    when others then
      if sqlerrm not like 'task_not_found%' then raise; end if;
  end;

  begin
    perform app.confirm_wms_putaway_task(v_task_l1.id, 1, v_task_l1.actual_location_id, null, null, 'attacker-key', 999999, '00000000-0000-0000-0000-000000120107', 'rep2b-attacker');
    raise exception 'assertion failed: expected insufficient_authority -- tenant2''s rep must not reach the confirm short-circuit on tenant1''s already-confirmed task';
  exception
    when others then
      if sqlerrm not like 'insufficient_authority%' then raise; end if;
  end;

  begin
    -- ISS-2026-146: tenant2's rep (wmsput2) holds no membership in wmsput1, so app.mark_wms_putaway_task_exception
    -- now collapses that zero-membership case into its own generic
    -- task_not_found / no_data_found branch -- byte-identical to what a
    -- nonexistent id already produced, so the real tenant_id is never disclosed to an
    -- outsider. A genuine same-tenant member lacking the role still gets
    -- insufficient_authority, unchanged (asserted elsewhere in this file).
    perform app.mark_wms_putaway_task_exception(v_task_l8a.id, 'malicious-probe-reason', 999999, '00000000-0000-0000-0000-000000120107', 'rep2b-attacker');
    raise exception 'assertion failed: expected task_not_found -- tenant2''s rep must not reach the exception short-circuit on tenant1''s task';
  exception
    when others then
      if sqlerrm not like 'task_not_found%' then raise; end if;
  end;

  begin
    -- ISS-2026-146: tenant2's rep (wmsput2) holds no membership in wmsput1, so app.cancel_wms_putaway_task
    -- now collapses that zero-membership case into its own generic
    -- task_not_found / no_data_found branch -- byte-identical to what a
    -- nonexistent id already produced, so the real tenant_id is never disclosed to an
    -- outsider. A genuine same-tenant member lacking the role still gets
    -- insufficient_authority, unchanged (asserted elsewhere in this file).
    perform app.cancel_wms_putaway_task(v_task_l9_cancelled.id, 'malicious-probe-reason', 999999, '00000000-0000-0000-0000-000000120107', 'rep2b-attacker');
    raise exception 'assertion failed: expected task_not_found -- tenant2''s rep must not reach the cancel short-circuit on tenant1''s already-cancelled task';
  exception
    when others then
      if sqlerrm not like 'task_not_found%' then raise; end if;
  end;
end $$;

\echo '>> schema-privilege defense in depth (ERR-2026-004): anon holds no direct table/EXECUTE access; authenticated has RLS-scoped SELECT but no direct INSERT/UPDATE/DELETE; only service_role may write directly'
do $$
begin
  if has_table_privilege('anon', 'app.wms_putaway_tasks', 'SELECT') then
    raise exception 'assertion failed: anon must not have direct SELECT on app.wms_putaway_tasks';
  end if;
  if has_table_privilege('anon', 'app.wms_putaway_confirmations', 'SELECT') then
    raise exception 'assertion failed: anon must not have direct SELECT on app.wms_putaway_confirmations';
  end if;
  if has_function_privilege('anon', 'app.generate_wms_putaway_task(uuid, numeric, uuid, text, uuid, text)', 'EXECUTE') then
    raise exception 'assertion failed: anon must not have EXECUTE on app.generate_wms_putaway_task';
  end if;
  if has_function_privilege('anon', 'app.confirm_wms_putaway_task(uuid, numeric, uuid, text, text, text, integer, uuid, text)', 'EXECUTE') then
    raise exception 'assertion failed: anon must not have EXECUTE on app.confirm_wms_putaway_task';
  end if;

  if not has_table_privilege('authenticated', 'app.wms_putaway_tasks', 'SELECT') then
    raise exception 'assertion failed: authenticated must have RLS-scoped SELECT on app.wms_putaway_tasks';
  end if;
  if has_table_privilege('authenticated', 'app.wms_putaway_tasks', 'INSERT') then
    raise exception 'assertion failed: authenticated must not have direct INSERT on app.wms_putaway_tasks -- mutation must go through the SECURITY DEFINER RPCs only';
  end if;
  if has_table_privilege('authenticated', 'app.wms_putaway_confirmations', 'UPDATE') then
    raise exception 'assertion failed: authenticated must not have direct UPDATE on app.wms_putaway_confirmations';
  end if;

  if not has_table_privilege('service_role', 'app.wms_putaway_tasks', 'INSERT') then
    raise exception 'assertion failed: service_role must retain direct table access to app.wms_putaway_tasks';
  end if;
  if not has_table_privilege('service_role', 'app.wms_putaway_confirmations', 'INSERT') then
    raise exception 'assertion failed: service_role must retain direct table access to app.wms_putaway_confirmations';
  end if;
end $$;
