-- Real, executable test evidence for ATW-013 (CG-S10-ATW-013, Prompt 232 WMS
-- Receiving) -- run via `pnpm run db:test` against a real, disposable Postgres
-- database.

\set ON_ERROR_STOP on

\echo '>> setup: one tenant (wmsrecv1), a company org unit, a rep (OPS:Create/Edit/View), a supervisor (OPS:Create/Edit/View/Override), an OPS:View-only viewer, a global Supreme Admin, two warehouses (WH-RECV-1 with DOCK-1/STAGE-1/BIN-1, WH-RECV-2 with DOCK-2 only, for wrong-warehouse checks), one customer account (Account Alpha via the full CRM->Job Order pipeline), and five item masters (plain, lot-controlled, expiry-controlled, serial-controlled, and a second plain item reserved for the item-deactivation-mid-flow test). Tenant2 (wmsrecv2): an isolated rep and its own warehouse, for cross-tenant leakage checks.'
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
    ('00000000-0000-0000-0000-000000110101', 'admin@wmsrecv1.test'),
    ('00000000-0000-0000-0000-000000110102', 'rep@wmsrecv1.test'),
    ('00000000-0000-0000-0000-000000110103', 'viewer@wmsrecv1.test'),
    ('00000000-0000-0000-0000-000000110104', 'supervisor@wmsrecv1.test'),
    ('00000000-0000-0000-0000-000000110105', 'supreme@wmsrecv1.test'),
    ('00000000-0000-0000-0000-000000110106', 'admin2@wmsrecv2.test'),
    ('00000000-0000-0000-0000-000000110107', 'rep2@wmsrecv2.test');

  perform app.grant_principal_membership('00000000-0000-0000-0000-000000110105', 'supreme_admin', null, null, 'tester');

  perform app.provision_tenant('wmsrecv1', 'WMS Receiving Tenant One', 'idem-wmsrecv1', 'tester');
  v_tenant1 := (select id from app.tenants where slug = 'wmsrecv1');
  perform app.transition_tenant_status(v_tenant1, 'active', 'setup', 'tester');
  perform app.create_org_unit(v_tenant1, 'company', null, 'WMSRECV1-CO', 'WMS Receiving Tenant One Co', 'tester');
  v_company := (select id from app.org_units where tenant_id = v_tenant1 and code = 'WMSRECV1-CO');

  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000110101', 'admin@wmsrecv1.test', 'WmsRecv Admin', v_company, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'admin@wmsrecv1.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000110101', 'tenant_admin', v_tenant1, null, 'tester');

  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000110102', 'rep@wmsrecv1.test', 'WmsRecv Rep', v_company, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'rep@wmsrecv1.test'), 'active', 'onboarded', 'tester');

  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000110103', 'viewer@wmsrecv1.test', 'WmsRecv Viewer', v_company, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'viewer@wmsrecv1.test'), 'active', 'onboarded', 'tester');

  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000110104', 'supervisor@wmsrecv1.test', 'WmsRecv Supervisor', v_company, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'supervisor@wmsrecv1.test'), 'active', 'onboarded', 'tester');

  v_rep_role := (app.create_role(v_tenant1, 'WmsRecv Rep Role', 'full commercial + ops create/edit/view', 'tester')).id;
  v_rep_draft := app.create_role_version(v_rep_role, 'tester');
  perform app.set_role_version_permissions(
    v_rep_draft.id,
    array(select id from app.permissions where (resource_module_code = 'COM' and action in ('Create', 'Edit', 'Approve', 'View', 'View cost'))
      or (resource_module_code = 'OPS' and action in ('Create', 'Edit', 'View'))),
    'tester'
  );
  perform app.publish_role_version(v_rep_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_rep_role and status = 'published'), '00000000-0000-0000-0000-000000110102', '00000000-0000-0000-0000-000000110101', 'tester');

  v_supervisor_role := (app.create_role(v_tenant1, 'WmsRecv Supervisor Role', 'ops create/edit/view/override', 'tester')).id;
  v_supervisor_draft := app.create_role_version(v_supervisor_role, 'tester');
  perform app.set_role_version_permissions(
    v_supervisor_draft.id,
    array(select id from app.permissions where resource_module_code = 'OPS' and action in ('Create', 'Edit', 'View', 'Override')),
    'tester'
  );
  perform app.publish_role_version(v_supervisor_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_supervisor_role and status = 'published'), '00000000-0000-0000-0000-000000110104', '00000000-0000-0000-0000-000000110101', 'tester');

  v_viewer_role := (app.create_role(v_tenant1, 'WmsRecv Viewer Role', 'OPS:View only', 'tester')).id;
  v_viewer_draft := app.create_role_version(v_viewer_role, 'tester');
  perform app.set_role_version_permissions(v_viewer_draft.id, array(select id from app.permissions where resource_module_code = 'OPS' and action = 'View'), 'tester');
  perform app.publish_role_version(v_viewer_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_viewer_role and status = 'published'), '00000000-0000-0000-0000-000000110103', '00000000-0000-0000-0000-000000110101', 'tester');

  v_warehouse := app.create_warehouse(v_tenant1, v_company, 'WH-RECV-1', 'WMS Receiving Warehouse 1', 'Jl. Receiving 1', 'Asia/Jakarta', null, array['land']::text[], '00000000-0000-0000-0000-000000110102', 'rep');
  declare
    v_dock1 app.warehouse_locations;
    v_stage1 app.warehouse_locations;
    v_bin1 app.warehouse_locations;
    v_dock2 app.warehouse_locations;
  begin
    v_dock1 := app.create_warehouse_location(v_warehouse.id, null, null, 'DOCK-1', 'Receiving Dock 1', 'dock', 1, null, null, null, null, null, false, false, '00000000-0000-0000-0000-000000110102', 'rep');
    perform app.set_warehouse_location_status(v_dock1.id, 'active', null, v_dock1.record_version, '00000000-0000-0000-0000-000000110102', 'rep');
    v_stage1 := app.create_warehouse_location(v_warehouse.id, null, null, 'STAGE-1', 'Staging Area 1', 'staging', 2, null, null, null, null, null, false, false, '00000000-0000-0000-0000-000000110102', 'rep');
    perform app.set_warehouse_location_status(v_stage1.id, 'active', null, v_stage1.record_version, '00000000-0000-0000-0000-000000110102', 'rep');
    -- BIN-1 is deliberately left in its default draft status -- the wrong-location-type
    -- test it feeds (bin, not dock/staging) fails on location_type before status is
    -- ever reached, so an inactive bin is not a confound.
    v_bin1 := app.create_warehouse_location(v_warehouse.id, null, null, 'BIN-1', 'Storage Bin 1', 'bin', 3, 100, 'units', null, null, null, true, true, '00000000-0000-0000-0000-000000110102', 'rep');
  end;

  v_warehouse2 := app.create_warehouse(v_tenant1, v_company, 'WH-RECV-2', 'WMS Receiving Warehouse 2', 'Jl. Receiving 2', 'Asia/Jakarta', null, array['land']::text[], '00000000-0000-0000-0000-000000110102', 'rep');
  declare
    v_dock2 app.warehouse_locations;
  begin
    v_dock2 := app.create_warehouse_location(v_warehouse2.id, null, null, 'DOCK-2', 'Receiving Dock 2', 'dock', 1, null, null, null, null, null, false, false, '00000000-0000-0000-0000-000000110102', 'rep');
    perform app.set_warehouse_location_status(v_dock2.id, 'active', null, v_dock2.record_version, '00000000-0000-0000-0000-000000110102', 'rep');
  end;

  perform app.capture_lead(v_tenant1, 'manual', null, 'WmsRecv Customer Alpha', 'Alice WmsRecv', 'alice@wmsrecv232.test', '0811',
    '00000000-0000-0000-0000-000000110102', v_company, '00000000-0000-0000-0000-000000110102', 'tester');
  select * into v_lead from app.leads where email = 'alice@wmsrecv232.test';
  perform app.qualify_lead(v_lead.id, v_lead.record_version, '00000000-0000-0000-0000-000000110102', 'tester');
  select * into v_lead from app.leads where id = v_lead.id;
  perform app.convert_lead_to_prospect(v_lead.id, 'WmsRecv Customer Alpha', 'WMSRECV232A', '11.111.111.12-111.000',
    jsonb_build_object('line1', 'Jl. Receiving Alpha 12', 'city', 'Jakarta', 'country', 'ID'),
    '00000000-0000-0000-0000-000000110102', 'tester');
  select * into v_prospect from app.prospects where lead_id = v_lead.id;
  select * into v_contact from app.create_contact(v_tenant1, 'Alice WmsRecv Ops', 'Ops Lead', 'alice@wmsrecv232.test', '0811', '00000000-0000-0000-0000-000000110102', v_company, '00000000-0000-0000-0000-000000110102', 'tester');
  perform app.link_contact_to_record(v_contact.id, 'prospect', v_prospect.id, 'primary', true, '00000000-0000-0000-0000-000000110102', 'tester');
  select * into v_opportunity from app.create_opportunity(
    v_tenant1, v_prospect.id, 'WMSRECV232 Alpha lane',
    jsonb_build_object('service_type', 'land_freight', 'cargo_description', 'General cargo', 'origin', 'Jakarta', 'destination', 'Surabaya', 'target_ready_date', '2026-08-01'),
    '00000000-0000-0000-0000-000000110102', v_company, '00000000-0000-0000-0000-000000110102', 'tester'
  );
  select * into v_request from app.request_costing(v_opportunity.id, '[]'::jsonb, null, '00000000-0000-0000-0000-000000110102', 'tester');
  select * into v_rate from app.create_rate_version(
    v_tenant1, 'VENDOR-WMSRECV232-A', 'Contoso WmsRecv232 Line', 'land_freight', 'FTL', 'Jakarta', 'Surabaya', '20ft',
    null, null, null, null, 'IDR', 5000000, null, '[]'::jsonb, now(), null, null, '00000000-0000-0000-0000-000000110101', 'tester'
  );
  perform app.approve_rate_version(v_rate.id, v_rate.record_version, '00000000-0000-0000-0000-000000110101', 'tester');
  select * into v_selection from app.select_vendor_rate(v_request.id, v_rate.id, false, null, null, null, '00000000-0000-0000-0000-000000110102', 'tester');
  v_rule := app.create_margin_rule_version(v_tenant1, 20.00, 'half_up', '00000000-0000-0000-0000-000000110102', 'tester');
  perform app.publish_margin_rule_version(v_rule.id, v_rule.record_version, null, '00000000-0000-0000-0000-000000110102', 'tester');
  perform app.calculate_margin(v_selection.id, 6000000, 'IDR', 0, '00000000-0000-0000-0000-000000110102', 'tester');
  select id into v_calc_id from app.margin_calculations where rate_selection_id = v_selection.id and is_current;
  select * into v_quote from app.create_quotation_draft(v_tenant1, v_opportunity.id, 'IDR', now() + interval '14 days', v_contact.id, null, null, '00000000-0000-0000-0000-000000110102', 'tester');
  perform app.add_quotation_line(v_quote.id, v_quote.record_version, 'service', 'WMSRECV232 Alpha lane', v_calc_id, 1, 6000000, 0, 0, '00000000-0000-0000-0000-000000110102', 'tester');
  select * into v_quote from app.quotations where id = v_quote.id;
  perform app.submit_quotation(v_quote.id, v_quote.record_version, '00000000-0000-0000-0000-000000110102', 'tester');
  select * into v_send from app.send_quotation_for_acceptance(v_quote.id, null, 'email', '00000000-0000-0000-0000-000000110102', 'tester');
  perform app.record_quotation_customer_decision(v_send.raw_token, 'accepted', 'Alice WmsRecv Ops', null, null, null, null, null);
  select * into v_quote from app.quotations where id = v_quote.id;
  select * into v_account from app.convert_quotation_to_account(v_quote.id, null, null, '00000000-0000-0000-0000-000000110102', 'rep');

  perform app.create_item_master(v_tenant1, v_account.id, 'SKU-RECV-PLAIN', 'Recv Plain Widget', null, 'PCS', false, false, false, '00000000-0000-0000-0000-000000110102', 'rep');
  perform app.create_item_master(v_tenant1, v_account.id, 'SKU-RECV-PLAIN2', 'Recv Plain Widget Two', null, 'PCS', false, false, false, '00000000-0000-0000-0000-000000110102', 'rep');
  perform app.create_item_master(v_tenant1, v_account.id, 'SKU-RECV-LOT', 'Recv Lot Widget', null, 'PCS', true, false, false, '00000000-0000-0000-0000-000000110102', 'rep');
  perform app.create_item_master(v_tenant1, v_account.id, 'SKU-RECV-EXPIRY', 'Recv Expiry Widget', null, 'PCS', false, false, true, '00000000-0000-0000-0000-000000110102', 'rep');
  perform app.create_item_master(v_tenant1, v_account.id, 'SKU-RECV-SERIAL', 'Recv Serial Widget', null, 'PCS', false, true, false, '00000000-0000-0000-0000-000000110102', 'rep');

  -- Tenant2: fully isolated -- exists only to prove cross-tenant scope safety.
  perform app.provision_tenant('wmsrecv2', 'WMS Receiving Tenant Two', 'idem-wmsrecv2', 'tester');
  v_tenant2 := (select id from app.tenants where slug = 'wmsrecv2');
  perform app.transition_tenant_status(v_tenant2, 'active', 'setup', 'tester');
  perform app.create_org_unit(v_tenant2, 'company', null, 'WMSRECV2-CO', 'WMS Receiving Tenant Two Co', 'tester');
  v_company2 := (select id from app.org_units where tenant_id = v_tenant2 and code = 'WMSRECV2-CO');
  perform app.invite_user(v_tenant2, '00000000-0000-0000-0000-000000110106', 'admin2@wmsrecv2.test', 'Tenant2 Admin', v_company2, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'admin2@wmsrecv2.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000110106', 'tenant_admin', v_tenant2, null, 'tester');
  perform app.invite_user(v_tenant2, '00000000-0000-0000-0000-000000110107', 'rep2@wmsrecv2.test', 'Tenant2 Rep', v_company2, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'rep2@wmsrecv2.test'), 'active', 'onboarded', 'tester');
  v_rep2_role := (app.create_role(v_tenant2, 'Tenant2 Rep Role', 'ops create/edit/view', 'tester')).id;
  v_rep2_draft := app.create_role_version(v_rep2_role, 'tester');
  perform app.set_role_version_permissions(v_rep2_draft.id, array(select id from app.permissions where resource_module_code = 'OPS' and action in ('Create', 'Edit', 'View')), 'tester');
  perform app.publish_role_version(v_rep2_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant2, (select id from app.role_versions where role_id = v_rep2_role and status = 'published'), '00000000-0000-0000-0000-000000110107', '00000000-0000-0000-0000-000000110106', 'tester');
end $$;

\echo '>> build the main confirmed inbound order (WH-RECV-1, Account Alpha) with 14 lines, one per outcome scenario, and a separate not-yet-confirmed order for the inbound_not_confirmed check'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'wmsrecv1');
  v_warehouse_id uuid := (select id from app.warehouses where tenant_id = v_tenant1 and code = 'WH-RECV-1');
  v_account_id uuid := (select id from app.accounts where tenant_id = v_tenant1 and legal_name = 'WmsRecv Customer Alpha');
  v_plain_id uuid := (select id from app.item_masters where tenant_id = v_tenant1 and code = 'SKU-RECV-PLAIN');
  v_plain2_id uuid := (select id from app.item_masters where tenant_id = v_tenant1 and code = 'SKU-RECV-PLAIN2');
  v_lot_id uuid := (select id from app.item_masters where tenant_id = v_tenant1 and code = 'SKU-RECV-LOT');
  v_expiry_id uuid := (select id from app.item_masters where tenant_id = v_tenant1 and code = 'SKU-RECV-EXPIRY');
  v_serial_id uuid := (select id from app.item_masters where tenant_id = v_tenant1 and code = 'SKU-RECV-SERIAL');
  v_order app.wms_inbound_orders;
  v_not_confirmed app.wms_inbound_orders;
  v_lines app.wms_inbound_order_lines[];
begin
  v_order := app.create_manual_wms_inbound(v_tenant1, v_warehouse_id, v_account_id, 'main receiving fixture', 'idem-recv-main', '00000000-0000-0000-0000-000000110102', 'rep');

  select array_agg(l) into v_lines from app.add_wms_inbound_order_lines(
    v_order.id,
    jsonb_build_array(
      jsonb_build_object('item_master_id', v_plain_id, 'expected_uom_code', 'PCS', 'expected_quantity', 100, 'notes', 'L1 exact'),
      jsonb_build_object('item_master_id', v_plain_id, 'expected_uom_code', 'PCS', 'expected_quantity', 50, 'notes', 'L2 short'),
      jsonb_build_object('item_master_id', v_plain_id, 'expected_uom_code', 'PCS', 'expected_quantity', 40, 'notes', 'L3 over'),
      jsonb_build_object('item_master_id', v_plain_id, 'expected_uom_code', 'PCS', 'expected_quantity', 20, 'notes', 'L4 damage'),
      jsonb_build_object('item_master_id', v_plain_id, 'expected_uom_code', 'PCS', 'expected_quantity', 10, 'notes', 'L5 hold-release'),
      jsonb_build_object('item_master_id', v_plain_id, 'expected_uom_code', 'PCS', 'expected_quantity', 10, 'notes', 'L6 hold-damage'),
      jsonb_build_object('item_master_id', v_plain_id, 'expected_uom_code', 'PCS', 'expected_quantity', 10, 'notes', 'L7 reject'),
      jsonb_build_object('item_master_id', v_lot_id, 'expected_uom_code', 'PCS', 'expected_quantity', 5, 'notes', 'L8 lot required'),
      jsonb_build_object('item_master_id', v_expiry_id, 'expected_uom_code', 'PCS', 'expected_quantity', 5, 'notes', 'L9 expiry required'),
      jsonb_build_object('item_master_id', v_serial_id, 'expected_uom_code', 'PCS', 'expected_quantity', 1, 'notes', 'L10 serial A'),
      jsonb_build_object('item_master_id', v_serial_id, 'expected_uom_code', 'PCS', 'expected_quantity', 1, 'notes', 'L11 serial dup'),
      jsonb_build_object('item_master_id', v_plain2_id, 'expected_uom_code', 'PCS', 'expected_quantity', 5, 'notes', 'L12 item deactivated mid-flow'),
      jsonb_build_object('item_master_id', v_plain_id, 'expected_uom_code', 'PCS', 'expected_quantity', 12, 'notes', 'L13 uom conversion'),
      jsonb_build_object('item_master_id', v_plain_id, 'expected_uom_code', 'PCS', 'expected_quantity', 5, 'notes', 'L14 validation sandbox')
    ),
    '00000000-0000-0000-0000-000000110102', 'rep'
  ) l;
  if array_length(v_lines, 1) <> 14 then
    raise exception 'assertion failed: expected exactly 14 lines on the main inbound order, got %', array_length(v_lines, 1);
  end if;

  v_order := app.schedule_wms_inbound_appointment(v_order.id, now() + interval '1 day', now() + interval '1 day' + interval '2 hours', v_order.record_version, '00000000-0000-0000-0000-000000110102', 'rep');
  v_order := app.confirm_wms_inbound(v_order.id, v_order.record_version, '00000000-0000-0000-0000-000000110102', 'rep');
  if v_order.status <> 'confirmed' then
    raise exception 'assertion failed: expected the main inbound order to be confirmed, got %', v_order.status;
  end if;

  -- A second inbound order, deliberately left scheduled (never confirmed) for the
  -- inbound_not_confirmed exception check below.
  v_not_confirmed := app.create_manual_wms_inbound(v_tenant1, v_warehouse_id, v_account_id, 'not-confirmed fixture', 'idem-recv-notconfirmed', '00000000-0000-0000-0000-000000110102', 'rep');
  perform app.add_wms_inbound_order_line(v_not_confirmed.id, v_plain_id, 'PCS', 5, null, '00000000-0000-0000-0000-000000110102', 'rep');
  perform app.schedule_wms_inbound_appointment(v_not_confirmed.id, now() + interval '1 day', now() + interval '1 day' + interval '2 hours', v_not_confirmed.record_version, '00000000-0000-0000-0000-000000110102', 'rep');
end $$;

\echo '>> app.start_wms_receipt_session: viewer rejected; unknown order/location not found; wrong warehouse and wrong location-type (bin, not dock/staging) both rejected as incompatible_location; not-yet-confirmed order rejected; idempotent on both idempotency_key and inbound_order_id; auto-creates 14 receipt lines'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'wmsrecv1');
  v_warehouse_id uuid := (select id from app.warehouses where tenant_id = v_tenant1 and code = 'WH-RECV-1');
  v_dock1_id uuid := (select id from app.warehouse_locations where tenant_id = v_tenant1 and code = 'DOCK-1');
  v_bin1_id uuid := (select id from app.warehouse_locations where tenant_id = v_tenant1 and code = 'BIN-1');
  v_dock2_id uuid := (select id from app.warehouse_locations where tenant_id = v_tenant1 and code = 'DOCK-2');
  v_order_id uuid := (select id from app.wms_inbound_orders where tenant_id = v_tenant1 and idempotency_key = 'idem-recv-main');
  v_not_confirmed_id uuid := (select id from app.wms_inbound_orders where tenant_id = v_tenant1 and idempotency_key = 'idem-recv-notconfirmed');
  v_session app.wms_receipt_sessions;
  v_replay app.wms_receipt_sessions;
  v_replay2 app.wms_receipt_sessions;
  v_count integer;
begin
  begin
    perform app.start_wms_receipt_session(v_order_id, v_dock1_id, 'idem-start-viewer', '00000000-0000-0000-0000-000000110103', 'viewer');
    raise exception 'assertion failed: expected insufficient_authority -- viewer holds OPS:View only';
  exception
    when others then
      if sqlerrm not like 'insufficient_authority%' then raise; end if;
  end;

  begin
    perform app.start_wms_receipt_session(gen_random_uuid(), v_dock1_id, 'idem-start-badorder', '00000000-0000-0000-0000-000000110102', 'rep');
    raise exception 'assertion failed: expected inbound_order_not_found';
  exception
    when others then
      if sqlerrm not like 'inbound_order_not_found%' then raise; end if;
  end;

  begin
    perform app.start_wms_receipt_session(v_order_id, gen_random_uuid(), 'idem-start-badloc', '00000000-0000-0000-0000-000000110102', 'rep');
    raise exception 'assertion failed: expected location_not_found';
  exception
    when others then
      if sqlerrm not like 'location_not_found%' then raise; end if;
  end;

  begin
    perform app.start_wms_receipt_session(v_order_id, v_dock2_id, 'idem-start-wrongwh', '00000000-0000-0000-0000-000000110102', 'rep');
    raise exception 'assertion failed: expected incompatible_location -- DOCK-2 belongs to WH-RECV-2, not WH-RECV-1';
  exception
    when others then
      if sqlerrm not like 'incompatible_location%' then raise; end if;
  end;

  begin
    perform app.start_wms_receipt_session(v_order_id, v_bin1_id, 'idem-start-wrongtype', '00000000-0000-0000-0000-000000110102', 'rep');
    raise exception 'assertion failed: expected incompatible_location -- BIN-1 is a bin, not a dock/staging location';
  exception
    when others then
      if sqlerrm not like 'incompatible_location%' then raise; end if;
  end;

  begin
    perform app.start_wms_receipt_session(v_not_confirmed_id, v_dock1_id, 'idem-start-notconfirmed', '00000000-0000-0000-0000-000000110102', 'rep');
    raise exception 'assertion failed: expected inbound_not_confirmed';
  exception
    when others then
      if sqlerrm not like 'inbound_not_confirmed%' then raise; end if;
  end;

  v_session := app.start_wms_receipt_session(v_order_id, v_dock1_id, 'idem-start-main', '00000000-0000-0000-0000-000000110102', 'rep');
  if v_session.status <> 'in_progress' or v_session.receiving_location_id <> v_dock1_id then
    raise exception 'assertion failed: expected an in_progress session at DOCK-1, got status=%/location=%', v_session.status, v_session.receiving_location_id;
  end if;

  v_replay := app.start_wms_receipt_session(v_order_id, v_dock1_id, 'idem-start-main', '00000000-0000-0000-0000-000000110102', 'rep');
  if v_replay.id <> v_session.id then
    raise exception 'assertion failed: expected the same-idempotency-key replay to return the identical session';
  end if;

  v_replay2 := app.start_wms_receipt_session(v_order_id, v_dock1_id, 'idem-start-main-retry-different-key', '00000000-0000-0000-0000-000000110102', 'rep');
  if v_replay2.id <> v_session.id then
    raise exception 'assertion failed: expected a same-inbound-order retry (different idempotency key) to still return the identical session, never a second one';
  end if;

  select count(*) into v_count from app.wms_receipt_lines where receipt_session_id = v_session.id;
  if v_count <> 14 then
    raise exception 'assertion failed: expected exactly 14 auto-created receipt lines, got %', v_count;
  end if;
end $$;

\echo '>> app.record_wms_receipt_line_count: viewer rejected; negative quantity, unbalanced equation, invalid UOM all rejected; repeated identical scan is idempotent (overwrite, not accumulate); stale version rejected'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'wmsrecv1');
  v_session_id uuid := (select id from app.wms_receipt_sessions where tenant_id = v_tenant1 and idempotency_key = 'idem-start-main');
  v_line1 app.wms_receipt_lines;
begin
  select * into v_line1 from app.wms_receipt_lines where receipt_session_id = v_session_id and line_number = 1;

  begin
    perform app.record_wms_receipt_line_count(v_line1.id, null, 100, 100, 0, 0, 0, null, null, null, null, v_line1.record_version, '00000000-0000-0000-0000-000000110103', 'viewer');
    raise exception 'assertion failed: expected insufficient_authority -- viewer holds OPS:View only';
  exception
    when others then
      if sqlerrm not like 'insufficient_authority%' then raise; end if;
  end;

  begin
    perform app.record_wms_receipt_line_count(v_line1.id, null, -1, 0, 0, 0, 0, null, null, null, null, v_line1.record_version, '00000000-0000-0000-0000-000000110102', 'rep');
    raise exception 'assertion failed: expected invalid_quantity -- negative counted_quantity';
  exception
    when others then
      if sqlerrm not like 'invalid_quantity%' then raise; end if;
  end;

  begin
    perform app.record_wms_receipt_line_count(v_line1.id, null, 100, 40, 0, 0, 0, null, null, null, null, v_line1.record_version, '00000000-0000-0000-0000-000000110102', 'rep');
    raise exception 'assertion failed: expected invalid_equation -- accepted (40) does not equal counted (100)';
  exception
    when others then
      if sqlerrm not like 'invalid_equation%' then raise; end if;
  end;

  begin
    perform app.record_wms_receipt_line_count(v_line1.id, 'NOPE', 100, 100, 0, 0, 0, null, null, null, null, v_line1.record_version, '00000000-0000-0000-0000-000000110102', 'rep');
    raise exception 'assertion failed: expected invalid_uom';
  exception
    when others then
      if sqlerrm not like 'invalid_uom%' then raise; end if;
  end;

  v_line1 := app.record_wms_receipt_line_count(v_line1.id, null, 100, 100, 0, 0, 0, null, null, null, 'exact receipt', v_line1.record_version, '00000000-0000-0000-0000-000000110102', 'rep');
  if v_line1.counted_quantity <> 100 or v_line1.accepted_quantity <> 100 or v_line1.status <> 'counted' or v_line1.over_quantity <> 0 or v_line1.short_quantity <> 0 then
    raise exception 'assertion failed: expected an exact count of 100/100 with over=0/short=0, got counted=%/accepted=%/over=%/short=%', v_line1.counted_quantity, v_line1.accepted_quantity, v_line1.over_quantity, v_line1.short_quantity;
  end if;

  -- Repeated identical scan (duplicate scan, Prompt 232 section 17 "repeated scans
  -- idempotent") -- overwrite semantics, never accumulates.
  v_line1 := app.record_wms_receipt_line_count(v_line1.id, null, 100, 100, 0, 0, 0, null, null, null, 'exact receipt (rescanned)', v_line1.record_version, '00000000-0000-0000-0000-000000110102', 'rep');
  if v_line1.counted_quantity <> 100 then
    raise exception 'assertion failed: expected a repeated identical scan to leave counted_quantity at 100 (never 200), got %', v_line1.counted_quantity;
  end if;

  begin
    perform app.record_wms_receipt_line_count(v_line1.id, null, 100, 100, 0, 0, 0, null, null, null, null, v_line1.record_version - 1, '00000000-0000-0000-0000-000000110102', 'rep');
    raise exception 'assertion failed: expected stale_version';
  exception
    when others then
      if sqlerrm not like 'stale_version%' then raise; end if;
  end;
end $$;

\echo '>> app.commit_wms_receipt_line (L1 exact): posts a real receipt movement to on_hand at DOCK-1; idempotent replay on the same idempotency_key does not double-post; line_not_counted / stale_version rejected'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'wmsrecv1');
  v_session_id uuid := (select id from app.wms_receipt_sessions where tenant_id = v_tenant1 and idempotency_key = 'idem-start-main');
  v_warehouse_id uuid := (select id from app.warehouses where tenant_id = v_tenant1 and code = 'WH-RECV-1');
  v_dock1_id uuid := (select id from app.warehouse_locations where tenant_id = v_tenant1 and code = 'DOCK-1');
  v_account_id uuid := (select id from app.accounts where tenant_id = v_tenant1 and legal_name = 'WmsRecv Customer Alpha');
  v_plain_id uuid := (select id from app.item_masters where tenant_id = v_tenant1 and code = 'SKU-RECV-PLAIN');
  v_line1 app.wms_receipt_lines;
  v_line3 app.wms_receipt_lines;
  v_replay app.wms_receipt_lines;
  v_balance app.inventory_balances;
begin
  select * into v_line1 from app.wms_receipt_lines where receipt_session_id = v_session_id and line_number = 1;
  select * into v_line3 from app.wms_receipt_lines where receipt_session_id = v_session_id and line_number = 3;

  begin
    perform app.commit_wms_receipt_line(v_line3.id, 'idem-commit-l3-precount', v_line3.record_version, '00000000-0000-0000-0000-000000110102', 'rep');
    raise exception 'assertion failed: expected line_not_counted -- L3 has not been counted yet';
  exception
    when others then
      if sqlerrm not like 'line_not_counted%' then raise; end if;
  end;

  begin
    perform app.commit_wms_receipt_line(v_line1.id, 'idem-commit-l1', v_line1.record_version + 1, '00000000-0000-0000-0000-000000110102', 'rep');
    raise exception 'assertion failed: expected stale_version';
  exception
    when others then
      if sqlerrm not like 'stale_version%' then raise; end if;
  end;

  v_line1 := app.commit_wms_receipt_line(v_line1.id, 'idem-commit-l1', v_line1.record_version, '00000000-0000-0000-0000-000000110102', 'rep');
  if v_line1.status <> 'committed' or v_line1.movement_id is null then
    raise exception 'assertion failed: expected L1 to be committed with a real movement_id';
  end if;

  select * into v_balance from app.inventory_balances
    where tenant_id = v_tenant1 and warehouse_id = v_warehouse_id and owner_account_id = v_account_id and item_master_id = v_plain_id
      and location_id = v_dock1_id and lot_number is null and serial_number is null and status = 'on_hand';
  if v_balance.on_hand <> 100 then
    raise exception 'assertion failed: expected on_hand=100 after L1 commits, got %', v_balance.on_hand;
  end if;

  -- Idempotent retry (network-ambiguous re-send) -- short-circuits on status=committed
  -- only after OPS:Edit/tenant-scope authority is confirmed (design note 5). No
  -- second movement, no double-post.
  v_replay := app.commit_wms_receipt_line(v_line1.id, 'idem-commit-l1-different-key', v_line1.record_version + 999, '00000000-0000-0000-0000-000000110102', 'rep');
  if v_replay.id <> v_line1.id or v_replay.movement_id <> v_line1.movement_id then
    raise exception 'assertion failed: expected an already-committed line to return unchanged regardless of idempotency key or stale expected_version';
  end if;

  select * into v_balance from app.inventory_balances
    where tenant_id = v_tenant1 and warehouse_id = v_warehouse_id and owner_account_id = v_account_id and item_master_id = v_plain_id
      and location_id = v_dock1_id and lot_number is null and serial_number is null and status = 'on_hand';
  if v_balance.on_hand <> 100 then
    raise exception 'assertion failed: expected on_hand to remain 100 after the idempotent replay (never double-posted), got %', v_balance.on_hand;
  end if;

  -- Regression (adversarial review finding): the idempotent status=committed
  -- short-circuit must never be reachable ahead of authorization. Tenant2's rep
  -- holds zero membership in tenant1 and must be rejected, never handed tenant1's
  -- already-committed line row, even though it supplies a wildly wrong
  -- idempotency_key/expected_version (exactly the shape a same-record-id probe
  -- would use).
  -- ISS-2026-146: the refusal itself is unchanged, but its TEXT is. This actor
  -- (tenant2's rep) has zero membership in tenant1, so app.commit_wms_receipt_line now
  -- folds the membership check into its own row-miss branch and answers with the generic
  -- line_not_found a nonexistent line id already produced -- instead of an
  -- insufficient_authority message carrying tenant1's real tenant_id. The
  -- short-circuit-before-authorization property this regression exists to protect is
  -- untouched and still asserted: the call is still refused before any replay.
  begin
    perform app.commit_wms_receipt_line(v_line1.id, 'attacker-key', 999999, '00000000-0000-0000-0000-000000110107', 'rep2-attacker');
    raise exception 'assertion failed: expected line_not_found -- tenant2''s rep has no membership in tenant1 and must not reach the idempotent-replay short-circuit on an already-committed tenant1 line';
  exception
    when others then
      if sqlerrm not like 'line_not_found%' then raise; end if;
      if sqlerrm like ('%' || v_tenant1::text || '%') then
        raise exception 'assertion failed: ISS-2026-146 regression -- the denial still discloses tenant1''s real tenant_id: %', sqlerrm;
      end if;
  end;
end $$;

\echo '>> L2 short: counted below expected, all accepted, short_quantity computed exactly, commits cleanly with no approval needed'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'wmsrecv1');
  v_session_id uuid := (select id from app.wms_receipt_sessions where tenant_id = v_tenant1 and idempotency_key = 'idem-start-main');
  v_line2 app.wms_receipt_lines;
begin
  select * into v_line2 from app.wms_receipt_lines where receipt_session_id = v_session_id and line_number = 2;
  v_line2 := app.record_wms_receipt_line_count(v_line2.id, null, 30, 30, 0, 0, 0, null, null, null, 'short delivery', v_line2.record_version, '00000000-0000-0000-0000-000000110102', 'rep');
  if v_line2.short_quantity <> 20 or v_line2.over_quantity <> 0 then
    raise exception 'assertion failed: expected short_quantity=20 (expected 50 - counted 30) and over_quantity=0, got short=%/over=%', v_line2.short_quantity, v_line2.over_quantity;
  end if;
  v_line2 := app.commit_wms_receipt_line(v_line2.id, 'idem-commit-l2', v_line2.record_version, '00000000-0000-0000-0000-000000110102', 'rep');
  if v_line2.status <> 'committed' then
    raise exception 'assertion failed: expected L2 (short, no overage) to commit without any approval step';
  end if;
end $$;

\echo '>> L3 over: unapproved overage blocks commit; a plain rep cannot approve (lacks OPS:Override); approving a line with no overage is rejected; supervisor approval unblocks the identical commit'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'wmsrecv1');
  v_session_id uuid := (select id from app.wms_receipt_sessions where tenant_id = v_tenant1 and idempotency_key = 'idem-start-main');
  v_line3 app.wms_receipt_lines;
  v_line14 app.wms_receipt_lines;
begin
  select * into v_line3 from app.wms_receipt_lines where receipt_session_id = v_session_id and line_number = 3;
  select * into v_line14 from app.wms_receipt_lines where receipt_session_id = v_session_id and line_number = 14;

  v_line3 := app.record_wms_receipt_line_count(v_line3.id, null, 50, 50, 0, 0, 0, null, null, null, 'more pallets than ordered', v_line3.record_version, '00000000-0000-0000-0000-000000110102', 'rep');
  if v_line3.over_quantity <> 10 then
    raise exception 'assertion failed: expected over_quantity=10 (counted 50 - expected 40), got %', v_line3.over_quantity;
  end if;

  begin
    perform app.commit_wms_receipt_line(v_line3.id, 'idem-commit-l3', v_line3.record_version, '00000000-0000-0000-0000-000000110102', 'rep');
    raise exception 'assertion failed: expected unapproved_overage';
  exception
    when others then
      if sqlerrm not like 'unapproved_overage%' then raise; end if;
  end;

  -- L14 is still pending (uncounted) at this point in the fixture -- expected_quantity
  -- 5, counted_quantity still its default 0, so over_quantity is 0 (no overage yet).
  begin
    perform app.approve_wms_receipt_overage(v_line14.id, 'no overage on this line', v_line14.record_version, '00000000-0000-0000-0000-000000110104', 'supervisor');
    raise exception 'assertion failed: expected no_overage_to_approve -- L14 has over_quantity=0';
  exception
    when others then
      if sqlerrm not like 'no_overage_to_approve%' then raise; end if;
  end;

  begin
    perform app.approve_wms_receipt_overage(v_line3.id, 'customer confirmed the extra pallet by phone', v_line3.record_version, '00000000-0000-0000-0000-000000110102', 'rep');
    raise exception 'assertion failed: expected insufficient_authority -- rep lacks OPS:Override';
  exception
    when others then
      if sqlerrm not like 'insufficient_authority%' then raise; end if;
  end;

  v_line3 := app.approve_wms_receipt_overage(v_line3.id, 'customer confirmed the extra pallet by phone', v_line3.record_version, '00000000-0000-0000-0000-000000110104', 'supervisor');
  if not v_line3.over_approved or v_line3.over_approved_by <> 'supervisor' then
    raise exception 'assertion failed: expected over_approved=true, approved_by=supervisor';
  end if;

  v_line3 := app.commit_wms_receipt_line(v_line3.id, 'idem-commit-l3', v_line3.record_version, '00000000-0000-0000-0000-000000110102', 'rep');
  if v_line3.status <> 'committed' then
    raise exception 'assertion failed: expected L3 to commit once the overage was approved';
  end if;
end $$;

\echo '>> L4 damage: partial accept + partial damage on the same line, posted as two distinct balance-status lines from one commit'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'wmsrecv1');
  v_session_id uuid := (select id from app.wms_receipt_sessions where tenant_id = v_tenant1 and idempotency_key = 'idem-start-main');
  v_warehouse_id uuid := (select id from app.warehouses where tenant_id = v_tenant1 and code = 'WH-RECV-1');
  v_dock1_id uuid := (select id from app.warehouse_locations where tenant_id = v_tenant1 and code = 'DOCK-1');
  v_account_id uuid := (select id from app.accounts where tenant_id = v_tenant1 and legal_name = 'WmsRecv Customer Alpha');
  v_plain_id uuid := (select id from app.item_masters where tenant_id = v_tenant1 and code = 'SKU-RECV-PLAIN');
  v_line4 app.wms_receipt_lines;
  v_damaged_balance app.inventory_balances;
begin
  select * into v_line4 from app.wms_receipt_lines where receipt_session_id = v_session_id and line_number = 4;
  v_line4 := app.record_wms_receipt_line_count(v_line4.id, null, 20, 15, 5, 0, 0, null, null, null, 'forklift puncture on 5 units', v_line4.record_version, '00000000-0000-0000-0000-000000110102', 'rep');
  v_line4 := app.commit_wms_receipt_line(v_line4.id, 'idem-commit-l4', v_line4.record_version, '00000000-0000-0000-0000-000000110102', 'rep');
  if v_line4.status <> 'committed' then
    raise exception 'assertion failed: expected L4 to commit';
  end if;

  select * into v_damaged_balance from app.inventory_balances
    where tenant_id = v_tenant1 and warehouse_id = v_warehouse_id and owner_account_id = v_account_id and item_master_id = v_plain_id
      and location_id = v_dock1_id and lot_number is null and serial_number is null and status = 'damaged';
  if v_damaged_balance.on_hand <> 5 then
    raise exception 'assertion failed: expected the damaged-status balance to be 5 after L4 alone, got %', v_damaged_balance.on_hand;
  end if;
end $$;

\echo '>> L5/L6 QC hold: held quantity posts under status=held; a plain rep cannot resolve a hold (lacks OPS:Override); resolving with no held quantity is rejected; supervisor resolves L5 to on_hand and L6 to damaged, each via a real two-line adjustment movement; a repeat resolve is an idempotent no-op'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'wmsrecv1');
  v_session_id uuid := (select id from app.wms_receipt_sessions where tenant_id = v_tenant1 and idempotency_key = 'idem-start-main');
  v_warehouse_id uuid := (select id from app.warehouses where tenant_id = v_tenant1 and code = 'WH-RECV-1');
  v_dock1_id uuid := (select id from app.warehouse_locations where tenant_id = v_tenant1 and code = 'DOCK-1');
  v_account_id uuid := (select id from app.accounts where tenant_id = v_tenant1 and legal_name = 'WmsRecv Customer Alpha');
  v_plain_id uuid := (select id from app.item_masters where tenant_id = v_tenant1 and code = 'SKU-RECV-PLAIN');
  v_line1 app.wms_receipt_lines;
  v_line5 app.wms_receipt_lines;
  v_line6 app.wms_receipt_lines;
  v_replay app.wms_receipt_lines;
  v_held_balance app.inventory_balances;
begin
  select * into v_line1 from app.wms_receipt_lines where receipt_session_id = v_session_id and line_number = 1;
  select * into v_line5 from app.wms_receipt_lines where receipt_session_id = v_session_id and line_number = 5;
  select * into v_line6 from app.wms_receipt_lines where receipt_session_id = v_session_id and line_number = 6;

  v_line5 := app.record_wms_receipt_line_count(v_line5.id, null, 10, 0, 0, 10, 0, null, null, null, 'suspected temperature excursion -- QC hold', v_line5.record_version, '00000000-0000-0000-0000-000000110102', 'rep');
  v_line5 := app.commit_wms_receipt_line(v_line5.id, 'idem-commit-l5', v_line5.record_version, '00000000-0000-0000-0000-000000110102', 'rep');

  v_line6 := app.record_wms_receipt_line_count(v_line6.id, null, 10, 0, 0, 10, 0, null, null, null, 'suspected contamination -- QC hold', v_line6.record_version, '00000000-0000-0000-0000-000000110102', 'rep');
  v_line6 := app.commit_wms_receipt_line(v_line6.id, 'idem-commit-l6', v_line6.record_version, '00000000-0000-0000-0000-000000110102', 'rep');

  select * into v_held_balance from app.inventory_balances
    where tenant_id = v_tenant1 and warehouse_id = v_warehouse_id and owner_account_id = v_account_id and item_master_id = v_plain_id
      and location_id = v_dock1_id and lot_number is null and serial_number is null and status = 'held';
  if v_held_balance.on_hand <> 20 then
    raise exception 'assertion failed: expected held-status balance=20 (10 from L5 + 10 from L6), got %', v_held_balance.on_hand;
  end if;

  begin
    perform app.resolve_wms_receipt_hold(v_line5.id, 'release_to_stock', 'QC passed', 'idem-hold-l5-rep', '00000000-0000-0000-0000-000000110102', 'rep');
    raise exception 'assertion failed: expected insufficient_authority -- rep lacks OPS:Override';
  exception
    when others then
      if sqlerrm not like 'insufficient_authority%' then raise; end if;
  end;

  begin
    perform app.resolve_wms_receipt_hold(v_line1.id, 'release_to_stock', 'nothing held here', 'idem-hold-l1', '00000000-0000-0000-0000-000000110104', 'supervisor');
    raise exception 'assertion failed: expected no_held_quantity -- L1 has no held quantity';
  exception
    when others then
      if sqlerrm not like 'no_held_quantity%' then raise; end if;
  end;

  begin
    perform app.resolve_wms_receipt_hold(v_line5.id, 'scrap', 'x', 'idem-hold-l5-badres', '00000000-0000-0000-0000-000000110104', 'supervisor');
    raise exception 'assertion failed: expected invalid_resolution';
  exception
    when others then
      if sqlerrm not like 'invalid_resolution%' then raise; end if;
  end;

  v_line5 := app.resolve_wms_receipt_hold(v_line5.id, 'release_to_stock', 'QC passed on re-inspection', 'idem-hold-l5', '00000000-0000-0000-0000-000000110104', 'supervisor');
  if not v_line5.hold_resolved or v_line5.hold_resolution <> 'release_to_stock' or v_line5.resolution_movement_id is null then
    raise exception 'assertion failed: expected L5 hold resolved to release_to_stock with a real resolution_movement_id';
  end if;

  v_line6 := app.resolve_wms_receipt_hold(v_line6.id, 'confirm_damaged', 'contamination confirmed by QC', 'idem-hold-l6', '00000000-0000-0000-0000-000000110104', 'supervisor');
  if not v_line6.hold_resolved or v_line6.hold_resolution <> 'confirm_damaged' then
    raise exception 'assertion failed: expected L6 hold resolved to confirm_damaged';
  end if;

  select * into v_held_balance from app.inventory_balances
    where tenant_id = v_tenant1 and warehouse_id = v_warehouse_id and owner_account_id = v_account_id and item_master_id = v_plain_id
      and location_id = v_dock1_id and lot_number is null and serial_number is null and status = 'held';
  if v_held_balance.on_hand <> 0 then
    raise exception 'assertion failed: expected held-status balance to return to 0 after both resolutions, got %', v_held_balance.on_hand;
  end if;

  -- Idempotent retry -- short-circuits on hold_resolved only after OPS:Override/
  -- tenant-scope authority is confirmed.
  v_replay := app.resolve_wms_receipt_hold(v_line5.id, 'confirm_damaged', 'different resolution attempt', 'idem-hold-l5-retry', '00000000-0000-0000-0000-000000110104', 'supervisor');
  if v_replay.hold_resolution <> 'release_to_stock' then
    raise exception 'assertion failed: expected an already-resolved hold to be a no-op regardless of the new resolution argument';
  end if;

  -- Regression (adversarial review finding): the idempotent hold_resolved
  -- short-circuit must never be reachable ahead of authorization. Tenant2's rep
  -- holds zero membership in tenant1 and must be rejected, never handed tenant1's
  -- real prior hold resolution.
  begin
    perform app.resolve_wms_receipt_hold(v_line5.id, 'confirm_damaged', 'malicious-probe-reason', 'exploit-key-3', '00000000-0000-0000-0000-000000110107', 'rep2-attacker');
    raise exception 'assertion failed: expected insufficient_authority -- tenant2''s rep has no membership in tenant1 and must not reach the idempotent-replay short-circuit on an already-resolved tenant1 hold';
  exception
    when others then
      if sqlerrm not like 'insufficient_authority%' then raise; end if;
  end;
end $$;

\echo '>> L7 reject: fully rejected quantity posts no inventory movement at all (movement_id stays null)'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'wmsrecv1');
  v_session_id uuid := (select id from app.wms_receipt_sessions where tenant_id = v_tenant1 and idempotency_key = 'idem-start-main');
  v_line7 app.wms_receipt_lines;
begin
  select * into v_line7 from app.wms_receipt_lines where receipt_session_id = v_session_id and line_number = 7;
  v_line7 := app.record_wms_receipt_line_count(v_line7.id, null, 10, 0, 0, 0, 10, null, null, null, 'wrong item entirely -- refused at the door', v_line7.record_version, '00000000-0000-0000-0000-000000110102', 'rep');
  v_line7 := app.commit_wms_receipt_line(v_line7.id, 'idem-commit-l7', v_line7.record_version, '00000000-0000-0000-0000-000000110102', 'rep');
  if v_line7.status <> 'committed' or v_line7.movement_id is not null then
    raise exception 'assertion failed: expected L7 (fully rejected) to commit with movement_id null (nothing physically received), got movement_id=%', v_line7.movement_id;
  end if;
end $$;

\echo '>> L8 lot-controlled / L9 expiry-controlled: missing_lot / missing_expiry rejected on a non-zero count, then succeed once supplied'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'wmsrecv1');
  v_session_id uuid := (select id from app.wms_receipt_sessions where tenant_id = v_tenant1 and idempotency_key = 'idem-start-main');
  v_line8 app.wms_receipt_lines;
  v_line9 app.wms_receipt_lines;
begin
  select * into v_line8 from app.wms_receipt_lines where receipt_session_id = v_session_id and line_number = 8;
  select * into v_line9 from app.wms_receipt_lines where receipt_session_id = v_session_id and line_number = 9;

  begin
    perform app.record_wms_receipt_line_count(v_line8.id, null, 5, 5, 0, 0, 0, null, null, null, null, v_line8.record_version, '00000000-0000-0000-0000-000000110102', 'rep');
    raise exception 'assertion failed: expected missing_lot';
  exception
    when others then
      if sqlerrm not like 'missing_lot%' then raise; end if;
  end;
  v_line8 := app.record_wms_receipt_line_count(v_line8.id, null, 5, 5, 0, 0, 0, 'LOT-RECV-001', null, null, null, v_line8.record_version, '00000000-0000-0000-0000-000000110102', 'rep');
  v_line8 := app.commit_wms_receipt_line(v_line8.id, 'idem-commit-l8', v_line8.record_version, '00000000-0000-0000-0000-000000110102', 'rep');
  if v_line8.status <> 'committed' or v_line8.lot_number <> 'LOT-RECV-001' then
    raise exception 'assertion failed: expected L8 to commit with lot_number=LOT-RECV-001';
  end if;

  begin
    perform app.record_wms_receipt_line_count(v_line9.id, null, 5, 5, 0, 0, 0, null, null, null, null, v_line9.record_version, '00000000-0000-0000-0000-000000110102', 'rep');
    raise exception 'assertion failed: expected missing_expiry';
  exception
    when others then
      if sqlerrm not like 'missing_expiry%' then raise; end if;
  end;
  v_line9 := app.record_wms_receipt_line_count(v_line9.id, null, 5, 5, 0, 0, 0, null, null, (current_date + interval '180 days')::date, null, v_line9.record_version, '00000000-0000-0000-0000-000000110102', 'rep');
  v_line9 := app.commit_wms_receipt_line(v_line9.id, 'idem-commit-l9', v_line9.record_version, '00000000-0000-0000-0000-000000110102', 'rep');
  if v_line9.status <> 'committed' or v_line9.expiry_date is null then
    raise exception 'assertion failed: expected L9 to commit with a real expiry_date';
  end if;
end $$;

\echo '>> L10/L11 serial-controlled: missing_serial and serial_quantity_exceeded rejected; L10 commits SN-RECV-DUP-1 cleanly; L11 with the identical serial is blocked by app.post_inventory_movement''s own serial_conflict at commit time; correcting to a distinct serial then commits'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'wmsrecv1');
  v_session_id uuid := (select id from app.wms_receipt_sessions where tenant_id = v_tenant1 and idempotency_key = 'idem-start-main');
  v_line10 app.wms_receipt_lines;
  v_line11 app.wms_receipt_lines;
begin
  select * into v_line10 from app.wms_receipt_lines where receipt_session_id = v_session_id and line_number = 10;
  select * into v_line11 from app.wms_receipt_lines where receipt_session_id = v_session_id and line_number = 11;

  begin
    perform app.record_wms_receipt_line_count(v_line10.id, null, 1, 1, 0, 0, 0, null, null, null, null, v_line10.record_version, '00000000-0000-0000-0000-000000110102', 'rep');
    raise exception 'assertion failed: expected missing_serial';
  exception
    when others then
      if sqlerrm not like 'missing_serial%' then raise; end if;
  end;

  begin
    perform app.record_wms_receipt_line_count(v_line10.id, null, 2, 2, 0, 0, 0, null, 'SN-RECV-DUP-1', null, null, v_line10.record_version, '00000000-0000-0000-0000-000000110102', 'rep');
    raise exception 'assertion failed: expected serial_quantity_exceeded -- at most 1 unit per line for a serial-controlled item';
  exception
    when others then
      if sqlerrm not like 'serial_quantity_exceeded%' then raise; end if;
  end;

  v_line10 := app.record_wms_receipt_line_count(v_line10.id, null, 1, 1, 0, 0, 0, null, 'SN-RECV-DUP-1', null, null, v_line10.record_version, '00000000-0000-0000-0000-000000110102', 'rep');
  v_line10 := app.commit_wms_receipt_line(v_line10.id, 'idem-commit-l10', v_line10.record_version, '00000000-0000-0000-0000-000000110102', 'rep');
  if v_line10.status <> 'committed' then
    raise exception 'assertion failed: expected L10 to commit with serial SN-RECV-DUP-1';
  end if;

  v_line11 := app.record_wms_receipt_line_count(v_line11.id, null, 1, 1, 0, 0, 0, null, 'SN-RECV-DUP-1', null, null, v_line11.record_version, '00000000-0000-0000-0000-000000110102', 'rep');
  begin
    perform app.commit_wms_receipt_line(v_line11.id, 'idem-commit-l11', v_line11.record_version, '00000000-0000-0000-0000-000000110102', 'rep');
    raise exception 'assertion failed: expected serial_conflict -- SN-RECV-DUP-1 already on hand at quantity 1';
  exception
    when others then
      if sqlerrm not like 'serial_conflict%' then raise; end if;
  end;

  select * into v_line11 from app.wms_receipt_lines where id = v_line11.id;
  if v_line11.status <> 'counted' then
    raise exception 'assertion failed: expected L11 to remain counted (not committed) after the blocked duplicate-serial commit attempt';
  end if;

  v_line11 := app.record_wms_receipt_line_count(v_line11.id, null, 1, 1, 0, 0, 0, null, 'SN-RECV-DUP-2', null, 'corrected serial after duplicate rejection', v_line11.record_version, '00000000-0000-0000-0000-000000110102', 'rep');
  v_line11 := app.commit_wms_receipt_line(v_line11.id, 'idem-commit-l11-corrected', v_line11.record_version, '00000000-0000-0000-0000-000000110102', 'rep');
  if v_line11.status <> 'committed' then
    raise exception 'assertion failed: expected L11 to commit once corrected to a distinct serial';
  end if;
end $$;

\echo '>> L12 item deactivated mid-flow: a legitimate count that later fails commit once the referenced item master is deactivated (item_not_eligible, bubbled up from app.post_inventory_movement); reactivating the item lets the identical commit succeed; app.wms_inbound_orders.status is untouched by any of this receiving flow (design note 1)'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'wmsrecv1');
  v_session_id uuid := (select id from app.wms_receipt_sessions where tenant_id = v_tenant1 and idempotency_key = 'idem-start-main');
  v_order_id uuid := (select id from app.wms_inbound_orders where tenant_id = v_tenant1 and idempotency_key = 'idem-recv-main');
  v_plain2 app.item_masters;
  v_line12 app.wms_receipt_lines;
  v_order app.wms_inbound_orders;
begin
  select * into v_plain2 from app.item_masters where tenant_id = v_tenant1 and code = 'SKU-RECV-PLAIN2';
  select * into v_line12 from app.wms_receipt_lines where receipt_session_id = v_session_id and line_number = 12;

  v_line12 := app.record_wms_receipt_line_count(v_line12.id, null, 5, 5, 0, 0, 0, null, null, null, null, v_line12.record_version, '00000000-0000-0000-0000-000000110102', 'rep');

  perform app.set_item_master_status(v_plain2.id, 'inactive', 'discontinued mid-receiving', v_plain2.record_version, '00000000-0000-0000-0000-000000110102', 'rep');

  begin
    perform app.commit_wms_receipt_line(v_line12.id, 'idem-commit-l12', v_line12.record_version, '00000000-0000-0000-0000-000000110102', 'rep');
    raise exception 'assertion failed: expected item_not_eligible -- the referenced item master was deactivated';
  exception
    when others then
      if sqlerrm not like 'item_not_eligible%' then raise; end if;
  end;

  select * into v_plain2 from app.item_masters where id = v_plain2.id;
  perform app.set_item_master_status(v_plain2.id, 'active', 'reactivated for testing', v_plain2.record_version, '00000000-0000-0000-0000-000000110102', 'rep');

  select * into v_line12 from app.wms_receipt_lines where id = v_line12.id;
  v_line12 := app.commit_wms_receipt_line(v_line12.id, 'idem-commit-l12', v_line12.record_version, '00000000-0000-0000-0000-000000110102', 'rep');
  if v_line12.status <> 'committed' then
    raise exception 'assertion failed: expected L12 to commit once the item was reactivated';
  end if;

  select * into v_order from app.wms_inbound_orders where id = v_order_id;
  if v_order.status <> 'confirmed' then
    raise exception 'assertion failed: expected the inbound order''s own status to remain confirmed throughout receiving (design note 1 -- never widened/touched), got %', v_order.status;
  end if;
end $$;

\echo '>> L13 uom conversion: a count entered in DOZ is converted into the line''s own immutable expected_uom_code (PCS) before storage/equation-check/posting -- exact UOM (Prompt 232 section 24)'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'wmsrecv1');
  v_session_id uuid := (select id from app.wms_receipt_sessions where tenant_id = v_tenant1 and idempotency_key = 'idem-start-main');
  v_line13 app.wms_receipt_lines;
begin
  select * into v_line13 from app.wms_receipt_lines where receipt_session_id = v_session_id and line_number = 13;
  v_line13 := app.record_wms_receipt_line_count(v_line13.id, 'DOZ', 1, 1, 0, 0, 0, null, null, null, '1 dozen counted at the dock', v_line13.record_version, '00000000-0000-0000-0000-000000110102', 'rep');
  if v_line13.counted_uom_code <> 'DOZ' or v_line13.counted_quantity <> 12 or v_line13.accepted_quantity <> 12 or v_line13.over_quantity <> 0 then
    raise exception 'assertion failed: expected 1 DOZ to convert to counted_quantity=12/accepted_quantity=12 PCS with over_quantity=0 (expected was 12), got counted=%/accepted=%/over=%', v_line13.counted_quantity, v_line13.accepted_quantity, v_line13.over_quantity;
  end if;
  v_line13 := app.commit_wms_receipt_line(v_line13.id, 'idem-commit-l13', v_line13.record_version, '00000000-0000-0000-0000-000000110102', 'rep');
  if v_line13.status <> 'committed' then
    raise exception 'assertion failed: expected L13 to commit';
  end if;
end $$;

\echo '>> L14 + session-level: app.complete_wms_receipt_session blocked by lines_not_committed while L14 remains uncommitted; app.cancel_wms_inbound is blocked by has_receipt_progress once a real receipt session exists; L14 recorded and committed; app.complete_wms_receipt_session then succeeds; the final reconciled on_hand/damaged/held totals for SKU-RECV-PLAIN at DOCK-1 match exactly (Prompt 232 section 33 acceptance criterion)'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'wmsrecv1');
  v_warehouse_id uuid := (select id from app.warehouses where tenant_id = v_tenant1 and code = 'WH-RECV-1');
  v_dock1_id uuid := (select id from app.warehouse_locations where tenant_id = v_tenant1 and code = 'DOCK-1');
  v_account_id uuid := (select id from app.accounts where tenant_id = v_tenant1 and legal_name = 'WmsRecv Customer Alpha');
  v_plain_id uuid := (select id from app.item_masters where tenant_id = v_tenant1 and code = 'SKU-RECV-PLAIN');
  v_session app.wms_receipt_sessions;
  v_order app.wms_inbound_orders;
  v_line14 app.wms_receipt_lines;
  v_on_hand_balance app.inventory_balances;
  v_damaged_balance app.inventory_balances;
  v_held_balance app.inventory_balances;
begin
  select * into v_session from app.wms_receipt_sessions where tenant_id = v_tenant1 and idempotency_key = 'idem-start-main';
  select * into v_order from app.wms_inbound_orders where tenant_id = v_tenant1 and idempotency_key = 'idem-recv-main';

  begin
    perform app.complete_wms_receipt_session(v_session.id, v_session.record_version, '00000000-0000-0000-0000-000000110102', 'rep');
    raise exception 'assertion failed: expected lines_not_committed -- L14 has not been counted or committed yet';
  exception
    when others then
      if sqlerrm not like 'lines_not_committed%' then raise; end if;
  end;

  begin
    perform app.cancel_wms_inbound(v_order.id, 'trying to cancel mid-receiving', v_order.record_version, '00000000-0000-0000-0000-000000110102', 'rep');
    raise exception 'assertion failed: expected has_receipt_progress -- a real in_progress receipt session already exists for this inbound order';
  exception
    when others then
      if sqlerrm not like 'has_receipt_progress%' then raise; end if;
  end;

  begin
    perform app.cancel_wms_receipt_session(v_session.id, 'abandoning mid-flow', v_session.record_version, '00000000-0000-0000-0000-000000110102', 'rep');
    raise exception 'assertion failed: expected has_committed_lines -- several lines on this session have already posted real inventory';
  exception
    when others then
      if sqlerrm not like 'has_committed_lines%' then raise; end if;
  end;

  select * into v_line14 from app.wms_receipt_lines where receipt_session_id = v_session.id and line_number = 14;
  v_line14 := app.record_wms_receipt_line_count(v_line14.id, null, 5, 5, 0, 0, 0, null, null, null, 'final line', v_line14.record_version, '00000000-0000-0000-0000-000000110102', 'rep');
  v_line14 := app.commit_wms_receipt_line(v_line14.id, 'idem-commit-l14', v_line14.record_version, '00000000-0000-0000-0000-000000110102', 'rep');
  if v_line14.status <> 'committed' then
    raise exception 'assertion failed: expected L14 to commit';
  end if;

  select * into v_session from app.wms_receipt_sessions where id = v_session.id;
  v_session := app.complete_wms_receipt_session(v_session.id, v_session.record_version, '00000000-0000-0000-0000-000000110102', 'rep');
  if v_session.status <> 'completed' or v_session.completed_at is null then
    raise exception 'assertion failed: expected the session to complete once every line was committed';
  end if;

  -- Idempotent no-op re-complete.
  if (app.complete_wms_receipt_session(v_session.id, v_session.record_version, '00000000-0000-0000-0000-000000110102', 'rep')).status <> 'completed' then
    raise exception 'assertion failed: expected an already-completed session to remain completed on retry';
  end if;

  -- Regression (adversarial review finding): the idempotent status=completed
  -- short-circuit must never be reachable ahead of authorization. Tenant2's rep
  -- holds zero membership in tenant1 and must be rejected, never handed tenant1's
  -- already-completed session row, even with an implausible expected_version.
  begin
    perform app.complete_wms_receipt_session(v_session.id, -1, '00000000-0000-0000-0000-000000110107', 'rep2-attacker');
    raise exception 'assertion failed: expected insufficient_authority -- tenant2''s rep has no membership in tenant1 and must not reach the idempotent-replay short-circuit on an already-completed tenant1 session';
  exception
    when others then
      if sqlerrm not like 'insufficient_authority%' then raise; end if;
  end;

  -- Reconciliation: L1(100) + L2(30) + L3(50) + L4(15) + L13(12) + L14(5) directly
  -- accepted, plus L5's 10 released from hold to on_hand = 222. Damaged: L4(5) direct
  -- + L6's 10 confirmed-damaged from hold = 15. Held returns to exactly 0.
  select * into v_on_hand_balance from app.inventory_balances
    where tenant_id = v_tenant1 and warehouse_id = v_warehouse_id and owner_account_id = v_account_id and item_master_id = v_plain_id
      and location_id = v_dock1_id and lot_number is null and serial_number is null and status = 'on_hand';
  select * into v_damaged_balance from app.inventory_balances
    where tenant_id = v_tenant1 and warehouse_id = v_warehouse_id and owner_account_id = v_account_id and item_master_id = v_plain_id
      and location_id = v_dock1_id and lot_number is null and serial_number is null and status = 'damaged';
  select * into v_held_balance from app.inventory_balances
    where tenant_id = v_tenant1 and warehouse_id = v_warehouse_id and owner_account_id = v_account_id and item_master_id = v_plain_id
      and location_id = v_dock1_id and lot_number is null and serial_number is null and status = 'held';

  if v_on_hand_balance.on_hand <> 222 then
    raise exception 'assertion failed: expected the reconciled on_hand total for SKU-RECV-PLAIN at DOCK-1 to be exactly 222, got %', v_on_hand_balance.on_hand;
  end if;
  if v_damaged_balance.on_hand <> 15 then
    raise exception 'assertion failed: expected the reconciled damaged total for SKU-RECV-PLAIN at DOCK-1 to be exactly 15, got %', v_damaged_balance.on_hand;
  end if;
  if v_held_balance.on_hand <> 0 then
    raise exception 'assertion failed: expected the reconciled held total for SKU-RECV-PLAIN at DOCK-1 to return to exactly 0, got %', v_held_balance.on_hand;
  end if;
end $$;

\echo '>> app.cancel_wms_receipt_session: succeeds while in_progress with zero committed lines; idempotent no-op re-cancel; a cancelled session frees its own inbound_order_id slot for a fresh session (mirrors app.wms_inbound_orders'' own freed-source precedent, ATW-012); the fresh session then blocks app.cancel_wms_inbound via has_receipt_progress'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'wmsrecv1');
  v_warehouse_id uuid := (select id from app.warehouses where tenant_id = v_tenant1 and code = 'WH-RECV-1');
  v_dock1_id uuid := (select id from app.warehouse_locations where tenant_id = v_tenant1 and code = 'DOCK-1');
  v_account_id uuid := (select id from app.accounts where tenant_id = v_tenant1 and legal_name = 'WmsRecv Customer Alpha');
  v_plain_id uuid := (select id from app.item_masters where tenant_id = v_tenant1 and code = 'SKU-RECV-PLAIN');
  v_order app.wms_inbound_orders;
  v_session app.wms_receipt_sessions;
  v_fresh_session app.wms_receipt_sessions;
begin
  v_order := app.create_manual_wms_inbound(v_tenant1, v_warehouse_id, v_account_id, 'cancel-session fixture', 'idem-recv-cancelfixture', '00000000-0000-0000-0000-000000110102', 'rep');
  perform app.add_wms_inbound_order_line(v_order.id, v_plain_id, 'PCS', 5, null, '00000000-0000-0000-0000-000000110102', 'rep');
  v_order := app.schedule_wms_inbound_appointment(v_order.id, now() + interval '1 day', now() + interval '1 day' + interval '2 hours', v_order.record_version, '00000000-0000-0000-0000-000000110102', 'rep');
  v_order := app.confirm_wms_inbound(v_order.id, v_order.record_version, '00000000-0000-0000-0000-000000110102', 'rep');

  v_session := app.start_wms_receipt_session(v_order.id, v_dock1_id, 'idem-start-cancelfixture', '00000000-0000-0000-0000-000000110102', 'rep');

  begin
    perform app.cancel_wms_receipt_session(v_session.id, null, v_session.record_version, '00000000-0000-0000-0000-000000110102', 'rep');
    raise exception 'assertion failed: expected invalid_reason';
  exception
    when others then
      if sqlerrm not like 'invalid_reason%' then raise; end if;
  end;

  v_session := app.cancel_wms_receipt_session(v_session.id, 'appointment rescheduled to next week', v_session.record_version, '00000000-0000-0000-0000-000000110102', 'rep');
  if v_session.status <> 'cancelled' then
    raise exception 'assertion failed: expected the session to cancel with zero committed lines';
  end if;

  if (app.cancel_wms_receipt_session(v_session.id, 'again', v_session.record_version, '00000000-0000-0000-0000-000000110102', 'rep')).record_version <> v_session.record_version then
    raise exception 'assertion failed: expected an already-cancelled session to be a no-op regardless of the reason argument';
  end if;

  -- The freed (tenant_id, inbound_order_id) slot may now be reused by a fresh session.
  v_fresh_session := app.start_wms_receipt_session(v_order.id, v_dock1_id, 'idem-start-cancelfixture-retry', '00000000-0000-0000-0000-000000110102', 'rep');
  if v_fresh_session.id = v_session.id then
    raise exception 'assertion failed: expected a genuinely new session, not the cancelled one';
  end if;

  begin
    perform app.cancel_wms_inbound(v_order.id, 'now blocked by the fresh session', v_order.record_version, '00000000-0000-0000-0000-000000110102', 'rep');
    raise exception 'assertion failed: expected has_receipt_progress -- the fresh, non-cancelled session blocks cancellation even though a prior cancelled one exists';
  exception
    when others then
      if sqlerrm not like 'has_receipt_progress%' then raise; end if;
  end;
end $$;

\echo '>> reads: app.list_wms_receipt_sessions / app.list_wms_receipt_lines / app.get_wms_receipt_session: bounded, filtered, ordered by line_number, cross-tenant isolation'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'wmsrecv1');
  v_tenant2 uuid := (select id from app.tenants where slug = 'wmsrecv2');
  v_warehouse_id uuid := (select id from app.warehouses where tenant_id = v_tenant1 and code = 'WH-RECV-1');
  v_session_id uuid := (select id from app.wms_receipt_sessions where tenant_id = v_tenant1 and idempotency_key = 'idem-start-main');
  v_lines app.wms_receipt_lines[];
  v_count integer;
  i integer;
begin
  select count(*) into v_count from app.list_wms_receipt_sessions(v_tenant1, '00000000-0000-0000-0000-000000110102', v_warehouse_id, null, null, 50);
  if v_count < 3 then
    raise exception 'assertion failed: expected at least 3 receipt sessions under WH-RECV-1 (main + cancelled + fresh fixtures), got %', v_count;
  end if;

  select count(*) into v_count from app.list_wms_receipt_sessions(v_tenant1, '00000000-0000-0000-0000-000000110102', v_warehouse_id, null, 'completed', 50);
  if v_count <> 1 then
    raise exception 'assertion failed: expected exactly 1 completed session, got %', v_count;
  end if;

  select count(*) into v_count from app.list_wms_receipt_sessions(v_tenant1, '00000000-0000-0000-0000-000000110102', v_warehouse_id, null, null, 0);
  if v_count <> 1 then
    raise exception 'assertion failed: expected p_limit=0 to clamp up to 1, got %', v_count;
  end if;

  select array_agg(l order by l.line_number) into v_lines from app.list_wms_receipt_lines(v_session_id, '00000000-0000-0000-0000-000000110102') l;
  if array_length(v_lines, 1) <> 14 then
    raise exception 'assertion failed: expected exactly 14 lines back from list_wms_receipt_lines, got %', array_length(v_lines, 1);
  end if;
  for i in 1..14 loop
    if v_lines[i].line_number <> i then
      raise exception 'assertion failed: expected list_wms_receipt_lines to be ordered by line_number, position % had line_number %', i, v_lines[i].line_number;
    end if;
  end loop;

  if (app.get_wms_receipt_session(v_session_id, '00000000-0000-0000-0000-000000110102')).id <> v_session_id then
    raise exception 'assertion failed: expected get_wms_receipt_session to return the identical row';
  end if;

  begin
    perform app.get_wms_receipt_session(v_session_id, '00000000-0000-0000-0000-000000110107');
    raise exception 'assertion failed: expected insufficient_authority -- tenant2''s rep has no membership in tenant1';
  exception
    when others then
      if sqlerrm not like 'insufficient_authority%' then raise; end if;
  end;

  select count(*) into v_count from app.list_wms_receipt_sessions(v_tenant2, '00000000-0000-0000-0000-000000110107', null, null, null, 50);
  if v_count <> 0 then
    raise exception 'assertion failed: expected tenant2''s own rep to see zero receipt sessions (none created there)';
  end if;
end $$;

\echo '>> schema-privilege defense in depth (ERR-2026-004): anon holds no direct table/EXECUTE access; authenticated has RLS-scoped SELECT but no direct INSERT/UPDATE/DELETE; only service_role may write directly'
do $$
begin
  if has_table_privilege('anon', 'app.wms_receipt_sessions', 'SELECT') then
    raise exception 'assertion failed: anon must not have direct SELECT on app.wms_receipt_sessions';
  end if;
  if has_table_privilege('anon', 'app.wms_receipt_lines', 'SELECT') then
    raise exception 'assertion failed: anon must not have direct SELECT on app.wms_receipt_lines';
  end if;
  if has_function_privilege('anon', 'app.start_wms_receipt_session(uuid, uuid, text, uuid, text)', 'EXECUTE') then
    raise exception 'assertion failed: anon must not have EXECUTE on app.start_wms_receipt_session';
  end if;
  if has_function_privilege('anon', 'app.commit_wms_receipt_line(uuid, text, integer, uuid, text)', 'EXECUTE') then
    raise exception 'assertion failed: anon must not have EXECUTE on app.commit_wms_receipt_line';
  end if;

  if not has_table_privilege('authenticated', 'app.wms_receipt_sessions', 'SELECT') then
    raise exception 'assertion failed: authenticated must have RLS-scoped SELECT on app.wms_receipt_sessions';
  end if;
  if has_table_privilege('authenticated', 'app.wms_receipt_lines', 'INSERT') then
    raise exception 'assertion failed: authenticated must not have direct INSERT on app.wms_receipt_lines -- mutation must go through the SECURITY DEFINER RPCs only';
  end if;
  if has_table_privilege('authenticated', 'app.wms_receipt_sessions', 'UPDATE') then
    raise exception 'assertion failed: authenticated must not have direct UPDATE on app.wms_receipt_sessions';
  end if;

  if not has_table_privilege('service_role', 'app.wms_receipt_sessions', 'INSERT') then
    raise exception 'assertion failed: service_role must retain direct table access to app.wms_receipt_sessions';
  end if;
  if not has_table_privilege('service_role', 'app.wms_receipt_lines', 'INSERT') then
    raise exception 'assertion failed: service_role must retain direct table access to app.wms_receipt_lines';
  end if;
end $$;
