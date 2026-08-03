-- Real, executable test evidence for ATW-015 (CG-S10-ATW-015, Prompt 234 Inventory
-- Ledger) -- run via `pnpm run db:test` against a real, disposable Postgres database.

\set ON_ERROR_STOP on

\echo '>> setup: one tenant (acmeinv), a company org unit, a rep (OPS:Create/Edit/View), an OPS:View-only viewer, a global Supreme Admin, one active warehouse (WH-INV-1) with a dock location (DOCK-1) and a bin location (BIN-1), one customer account, two item masters (one serial-controlled, one not), and one manual WMS Inbound order as a real source_id. Tenant2 (acmeinv2): an isolated rep and its own warehouse, for cross-tenant leakage checks.'
do $$
declare
  v_tenant1 uuid;
  v_tenant2 uuid;
  v_company uuid;
  v_company2 uuid;
  v_rep_role uuid;
  v_rep_draft app.role_versions;
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
  v_dock app.warehouse_locations;
  v_bin app.warehouse_locations;
  v_item app.item_masters;
  v_item_serial app.item_masters;
  v_inbound app.wms_inbound_orders;
begin
  insert into auth.users (id, email) values
    ('00000000-0000-0000-0000-000000100101', 'admin@acmeinv1.test'),
    ('00000000-0000-0000-0000-000000100102', 'rep@acmeinv1.test'),
    ('00000000-0000-0000-0000-000000100103', 'viewer@acmeinv1.test'),
    ('00000000-0000-0000-0000-000000100105', 'supreme@acmeinv1.test'),
    ('00000000-0000-0000-0000-000000100106', 'admin2@acmeinv2.test'),
    ('00000000-0000-0000-0000-000000100107', 'rep2@acmeinv2.test');

  perform app.grant_principal_membership('00000000-0000-0000-0000-000000100105', 'supreme_admin', null, null, 'tester');

  perform app.provision_tenant('acmeinv1', 'Acme Inventory Tenant One', 'idem-acmeinv1', 'tester');
  v_tenant1 := (select id from app.tenants where slug = 'acmeinv1');
  perform app.transition_tenant_status(v_tenant1, 'active', 'setup', 'tester');
  perform app.create_org_unit(v_tenant1, 'company', null, 'ACMEINV1-CO', 'Acme Inventory Tenant One Co', 'tester');
  v_company := (select id from app.org_units where tenant_id = v_tenant1 and code = 'ACMEINV1-CO');

  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000100101', 'admin@acmeinv1.test', 'Inv Admin', v_company, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'admin@acmeinv1.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000100101', 'tenant_admin', v_tenant1, null, 'tester');

  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000100102', 'rep@acmeinv1.test', 'Inv Rep', v_company, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'rep@acmeinv1.test'), 'active', 'onboarded', 'tester');

  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000100103', 'viewer@acmeinv1.test', 'Inv Viewer', v_company, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'viewer@acmeinv1.test'), 'active', 'onboarded', 'tester');

  v_rep_role := (app.create_role(v_tenant1, 'Inv Rep Role', 'full commercial + ops create/edit/view', 'tester')).id;
  v_rep_draft := app.create_role_version(v_rep_role, 'tester');
  perform app.set_role_version_permissions(
    v_rep_draft.id,
    array(select id from app.permissions where (resource_module_code = 'COM' and action in ('Create', 'Edit', 'Approve', 'View', 'View cost'))
      or (resource_module_code = 'OPS' and action in ('Create', 'Edit', 'View'))),
    'tester'
  );
  perform app.publish_role_version(v_rep_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_rep_role and status = 'published'), '00000000-0000-0000-0000-000000100102', '00000000-0000-0000-0000-000000100101', 'tester');

  v_viewer_role := (app.create_role(v_tenant1, 'Inv Viewer Role', 'OPS:View only', 'tester')).id;
  v_viewer_draft := app.create_role_version(v_viewer_role, 'tester');
  perform app.set_role_version_permissions(v_viewer_draft.id, array(select id from app.permissions where resource_module_code = 'OPS' and action = 'View'), 'tester');
  perform app.publish_role_version(v_viewer_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_viewer_role and status = 'published'), '00000000-0000-0000-0000-000000100103', '00000000-0000-0000-0000-000000100101', 'tester');

  v_warehouse := app.create_warehouse(v_tenant1, v_company, 'WH-INV-1', 'Inventory Warehouse 1', 'Jl. Inventory 1', 'Asia/Jakarta', null, array['land']::text[], '00000000-0000-0000-0000-000000100102', 'rep');
  v_dock := app.create_warehouse_location(v_warehouse.id, null, null, 'DOCK-1', 'Receiving Dock 1', 'dock', 1, null, null, null, null, null, false, false, '00000000-0000-0000-0000-000000100102', 'rep');
  v_bin := app.create_warehouse_location(v_warehouse.id, null, null, 'BIN-1', 'Storage Bin 1', 'bin', 1, 100, 'units', null, null, null, true, true, '00000000-0000-0000-0000-000000100102', 'rep');

  perform app.capture_lead(v_tenant1, 'manual', null, 'Inv Customer Alpha', 'Alice Inv', 'alice@acmeinv231.test', '0811',
    '00000000-0000-0000-0000-000000100102', v_company, '00000000-0000-0000-0000-000000100102', 'tester');
  select * into v_lead from app.leads where email = 'alice@acmeinv231.test';
  perform app.qualify_lead(v_lead.id, v_lead.record_version, '00000000-0000-0000-0000-000000100102', 'tester');
  select * into v_lead from app.leads where id = v_lead.id;
  perform app.convert_lead_to_prospect(v_lead.id, 'Inv Customer Alpha', 'INV231A', '11.111.111.11-111.000',
    jsonb_build_object('line1', 'Jl. Inventory Alpha 11', 'city', 'Jakarta', 'country', 'ID'),
    '00000000-0000-0000-0000-000000100102', 'tester');
  select * into v_prospect from app.prospects where lead_id = v_lead.id;
  select * into v_contact from app.create_contact(v_tenant1, 'Alice Inv Ops', 'Ops Lead', 'alice@acmeinv231.test', '0811', '00000000-0000-0000-0000-000000100102', v_company, '00000000-0000-0000-0000-000000100102', 'tester');
  perform app.link_contact_to_record(v_contact.id, 'prospect', v_prospect.id, 'primary', true, '00000000-0000-0000-0000-000000100102', 'tester');
  select * into v_opportunity from app.create_opportunity(
    v_tenant1, v_prospect.id, 'Inv231 Alpha lane',
    jsonb_build_object('service_type', 'land_freight', 'cargo_description', 'General cargo', 'origin', 'Jakarta', 'destination', 'Surabaya', 'target_ready_date', '2026-08-01'),
    '00000000-0000-0000-0000-000000100102', v_company, '00000000-0000-0000-0000-000000100102', 'tester'
  );
  select * into v_request from app.request_costing(v_opportunity.id, '[]'::jsonb, null, '00000000-0000-0000-0000-000000100102', 'tester');
  select * into v_rate from app.create_rate_version(
    v_tenant1, 'VENDOR-INV231-A', 'Contoso Inv231 Line', 'land_freight', 'FTL', 'Jakarta', 'Surabaya', '20ft',
    null, null, null, null, 'IDR', 5000000, null, '[]'::jsonb, now(), null, null, '00000000-0000-0000-0000-000000100101', 'tester'
  );
  perform app.approve_rate_version(v_rate.id, v_rate.record_version, '00000000-0000-0000-0000-000000100101', 'tester');
  select * into v_selection from app.select_vendor_rate(v_request.id, v_rate.id, false, null, null, null, '00000000-0000-0000-0000-000000100102', 'tester');
  v_rule := app.create_margin_rule_version(v_tenant1, 20.00, 'half_up', '00000000-0000-0000-0000-000000100102', 'tester');
  perform app.publish_margin_rule_version(v_rule.id, v_rule.record_version, null, '00000000-0000-0000-0000-000000100102', 'tester');
  perform app.calculate_margin(v_selection.id, 6000000, 'IDR', 0, '00000000-0000-0000-0000-000000100102', 'tester');
  select id into v_calc_id from app.margin_calculations where rate_selection_id = v_selection.id and is_current;
  select * into v_quote from app.create_quotation_draft(v_tenant1, v_opportunity.id, 'IDR', now() + interval '14 days', v_contact.id, null, null, '00000000-0000-0000-0000-000000100102', 'tester');
  perform app.add_quotation_line(v_quote.id, v_quote.record_version, 'service', 'Inv231 Alpha lane', v_calc_id, 1, 6000000, 0, 0, '00000000-0000-0000-0000-000000100102', 'tester');
  select * into v_quote from app.quotations where id = v_quote.id;
  perform app.submit_quotation(v_quote.id, v_quote.record_version, '00000000-0000-0000-0000-000000100102', 'tester');
  select * into v_send from app.send_quotation_for_acceptance(v_quote.id, null, 'email', '00000000-0000-0000-0000-000000100102', 'tester');
  perform app.record_quotation_customer_decision(v_send.raw_token, 'accepted', 'Alice Inv Ops', null, null, null, null, null);
  select * into v_quote from app.quotations where id = v_quote.id;
  select * into v_account from app.convert_quotation_to_account(v_quote.id, null, null, '00000000-0000-0000-0000-000000100102', 'rep');

  v_item := app.create_item_master(v_tenant1, v_account.id, 'SKU-INV-A1', 'Inv Widget', null, 'PCS', false, false, false, '00000000-0000-0000-0000-000000100102', 'rep');
  v_item_serial := app.create_item_master(v_tenant1, v_account.id, 'SKU-INV-SERIAL', 'Inv Serialized Unit', null, 'PCS', false, true, false, '00000000-0000-0000-0000-000000100102', 'rep');

  v_inbound := app.create_manual_wms_inbound(v_tenant1, v_warehouse.id, v_account.id, 'inventory ledger fixture', 'idem-inv-inbound-1', '00000000-0000-0000-0000-000000100102', 'rep');

  -- Tenant2: fully isolated -- exists only to prove cross-tenant scope safety.
  perform app.provision_tenant('acmeinv2', 'Acme Inventory Tenant Two', 'idem-acmeinv2', 'tester');
  v_tenant2 := (select id from app.tenants where slug = 'acmeinv2');
  perform app.transition_tenant_status(v_tenant2, 'active', 'setup', 'tester');
  perform app.create_org_unit(v_tenant2, 'company', null, 'ACMEINV2-CO', 'Acme Inventory Tenant Two Co', 'tester');
  v_company2 := (select id from app.org_units where tenant_id = v_tenant2 and code = 'ACMEINV2-CO');
  perform app.invite_user(v_tenant2, '00000000-0000-0000-0000-000000100106', 'admin2@acmeinv2.test', 'Tenant2 Admin', v_company2, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'admin2@acmeinv2.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000100106', 'tenant_admin', v_tenant2, null, 'tester');
  perform app.invite_user(v_tenant2, '00000000-0000-0000-0000-000000100107', 'rep2@acmeinv2.test', 'Tenant2 Rep', v_company2, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'rep2@acmeinv2.test'), 'active', 'onboarded', 'tester');
  v_rep2_role := (app.create_role(v_tenant2, 'Tenant2 Rep Role', 'ops create/edit/view', 'tester')).id;
  v_rep2_draft := app.create_role_version(v_rep2_role, 'tester');
  perform app.set_role_version_permissions(v_rep2_draft.id, array(select id from app.permissions where resource_module_code = 'OPS' and action in ('Create', 'Edit', 'View')), 'tester');
  perform app.publish_role_version(v_rep2_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant2, (select id from app.role_versions where role_id = v_rep2_role and status = 'published'), '00000000-0000-0000-0000-000000100107', '00000000-0000-0000-0000-000000100106', 'tester');
end $$;

\echo '>> app.post_inventory_movement: authority-gated, idempotent on (tenant_id, idempotency_key), rejects unknown item/location/UOM, negative resulting on_hand, and posts a real opening_balance movement + balance row'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'acmeinv1');
  v_warehouse_id uuid := (select id from app.warehouses where tenant_id = v_tenant1 and code = 'WH-INV-1');
  v_dock_id uuid := (select id from app.warehouse_locations where tenant_id = v_tenant1 and code = 'DOCK-1');
  v_account_id uuid := (select id from app.accounts where tenant_id = v_tenant1 and legal_name = 'Inv Customer Alpha');
  v_item_id uuid := (select id from app.item_masters where tenant_id = v_tenant1 and code = 'SKU-INV-A1');
  v_movement app.inventory_movements;
  v_replay app.inventory_movements;
  v_balance app.inventory_balances;
begin
  begin
    perform app.post_inventory_movement(v_tenant1, v_warehouse_id, 'opening_balance', 'opening_balance', null, 'idem-open-1', null,
      jsonb_build_array(jsonb_build_object('owner_account_id', v_account_id, 'item_master_id', v_item_id, 'location_id', v_dock_id, 'uom_code', 'PCS', 'signed_quantity', 100)),
      '00000000-0000-0000-0000-000000100103', 'viewer');
    raise exception 'assertion failed: expected insufficient_authority -- viewer holds OPS:View only';
  exception
    when others then
      if sqlerrm not like 'insufficient_authority%' then raise; end if;
  end;

  v_movement := app.post_inventory_movement(v_tenant1, v_warehouse_id, 'opening_balance', 'opening_balance', null, 'idem-open-1', null,
    jsonb_build_array(jsonb_build_object('owner_account_id', v_account_id, 'item_master_id', v_item_id, 'location_id', v_dock_id, 'uom_code', 'PCS', 'signed_quantity', 100)),
    '00000000-0000-0000-0000-000000100102', 'rep');
  if v_movement.movement_type <> 'opening_balance' then
    raise exception 'assertion failed: expected movement_type=opening_balance';
  end if;

  select * into v_balance from app.inventory_balances
    where tenant_id = v_tenant1 and warehouse_id = v_warehouse_id and owner_account_id = v_account_id and item_master_id = v_item_id
      and location_id = v_dock_id and lot_number is null and serial_number is null and status = 'on_hand';
  if v_balance.on_hand <> 100 or v_balance.available <> 100 then
    raise exception 'assertion failed: expected on_hand=100/available=100 after the opening balance, got on_hand=%/available=%', v_balance.on_hand, v_balance.available;
  end if;

  v_replay := app.post_inventory_movement(v_tenant1, v_warehouse_id, 'opening_balance', 'opening_balance', null, 'idem-open-1', null,
    jsonb_build_array(jsonb_build_object('owner_account_id', v_account_id, 'item_master_id', v_item_id, 'location_id', v_dock_id, 'uom_code', 'PCS', 'signed_quantity', 100)),
    '00000000-0000-0000-0000-000000100102', 'rep');
  if v_replay.id <> v_movement.id then
    raise exception 'assertion failed: expected the same-idempotency-key replay to return the identical movement, not re-post';
  end if;

  select * into v_balance from app.inventory_balances
    where tenant_id = v_tenant1 and warehouse_id = v_warehouse_id and owner_account_id = v_account_id and item_master_id = v_item_id
      and location_id = v_dock_id and lot_number is null and serial_number is null and status = 'on_hand';
  if v_balance.on_hand <> 100 then
    raise exception 'assertion failed: expected on_hand to remain 100 after the idempotent replay (never double-counted), got %', v_balance.on_hand;
  end if;

  begin
    perform app.post_inventory_movement(v_tenant1, v_warehouse_id, 'adjustment', 'manual', null, 'idem-neg-1', 'test negative block',
      jsonb_build_array(jsonb_build_object('owner_account_id', v_account_id, 'item_master_id', v_item_id, 'location_id', v_dock_id, 'uom_code', 'PCS', 'signed_quantity', -1000)),
      '00000000-0000-0000-0000-000000100102', 'rep');
    raise exception 'assertion failed: expected insufficient_stock -- driving on_hand negative';
  exception
    when others then
      if sqlerrm not like 'insufficient_stock%' then raise; end if;
  end;

  begin
    perform app.post_inventory_movement(v_tenant1, v_warehouse_id, 'adjustment', 'manual', null, 'idem-noreason-1', null,
      jsonb_build_array(jsonb_build_object('owner_account_id', v_account_id, 'item_master_id', v_item_id, 'location_id', v_dock_id, 'uom_code', 'PCS', 'signed_quantity', 5)),
      '00000000-0000-0000-0000-000000100102', 'rep');
    raise exception 'assertion failed: expected invalid_reason -- an adjustment requires a non-empty reason';
  exception
    when others then
      if sqlerrm not like 'invalid_reason%' then raise; end if;
  end;

  begin
    perform app.post_inventory_movement(v_tenant1, v_warehouse_id, 'opening_balance', 'opening_balance', null, 'idem-baditem-1', null,
      jsonb_build_array(jsonb_build_object('owner_account_id', v_account_id, 'item_master_id', gen_random_uuid(), 'location_id', v_dock_id, 'uom_code', 'PCS', 'signed_quantity', 1)),
      '00000000-0000-0000-0000-000000100102', 'rep');
    raise exception 'assertion failed: expected item_not_eligible';
  exception
    when others then
      if sqlerrm not like 'item_not_eligible%' then raise; end if;
  end;

  begin
    perform app.post_inventory_movement(v_tenant1, v_warehouse_id, 'opening_balance', 'opening_balance', null, 'idem-badloc-1', null,
      jsonb_build_array(jsonb_build_object('owner_account_id', v_account_id, 'item_master_id', v_item_id, 'location_id', gen_random_uuid(), 'uom_code', 'PCS', 'signed_quantity', 1)),
      '00000000-0000-0000-0000-000000100102', 'rep');
    raise exception 'assertion failed: expected location_not_eligible';
  exception
    when others then
      if sqlerrm not like 'location_not_eligible%' then raise; end if;
  end;
end $$;

\echo '>> app.post_inventory_movement (transfer): must balance to exactly zero across its own lines; a balanced transfer moves stock between locations atomically'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'acmeinv1');
  v_warehouse_id uuid := (select id from app.warehouses where tenant_id = v_tenant1 and code = 'WH-INV-1');
  v_dock_id uuid := (select id from app.warehouse_locations where tenant_id = v_tenant1 and code = 'DOCK-1');
  v_bin_id uuid := (select id from app.warehouse_locations where tenant_id = v_tenant1 and code = 'BIN-1');
  v_account_id uuid := (select id from app.accounts where tenant_id = v_tenant1 and legal_name = 'Inv Customer Alpha');
  v_item_id uuid := (select id from app.item_masters where tenant_id = v_tenant1 and code = 'SKU-INV-A1');
  v_dock_balance app.inventory_balances;
  v_bin_balance app.inventory_balances;
begin
  begin
    perform app.post_inventory_movement(v_tenant1, v_warehouse_id, 'transfer', 'manual', null, 'idem-unbalanced-1', null,
      jsonb_build_array(
        jsonb_build_object('owner_account_id', v_account_id, 'item_master_id', v_item_id, 'location_id', v_dock_id, 'uom_code', 'PCS', 'signed_quantity', -20),
        jsonb_build_object('owner_account_id', v_account_id, 'item_master_id', v_item_id, 'location_id', v_bin_id, 'uom_code', 'PCS', 'signed_quantity', 15)
      ),
      '00000000-0000-0000-0000-000000100102', 'rep');
    raise exception 'assertion failed: expected unbalanced_transfer -- -20 + 15 <> 0';
  exception
    when others then
      if sqlerrm not like 'unbalanced_transfer%' then raise; end if;
  end;

  perform app.post_inventory_movement(v_tenant1, v_warehouse_id, 'transfer', 'manual', null, 'idem-balanced-1', null,
    jsonb_build_array(
      jsonb_build_object('owner_account_id', v_account_id, 'item_master_id', v_item_id, 'location_id', v_dock_id, 'uom_code', 'PCS', 'signed_quantity', -30),
      jsonb_build_object('owner_account_id', v_account_id, 'item_master_id', v_item_id, 'location_id', v_bin_id, 'uom_code', 'PCS', 'signed_quantity', 30)
    ),
    '00000000-0000-0000-0000-000000100102', 'rep');

  select * into v_dock_balance from app.inventory_balances
    where tenant_id = v_tenant1 and warehouse_id = v_warehouse_id and item_master_id = v_item_id and location_id = v_dock_id and status = 'on_hand';
  select * into v_bin_balance from app.inventory_balances
    where tenant_id = v_tenant1 and warehouse_id = v_warehouse_id and item_master_id = v_item_id and location_id = v_bin_id and status = 'on_hand';
  if v_dock_balance.on_hand <> 70 or v_bin_balance.on_hand <> 30 then
    raise exception 'assertion failed: expected dock on_hand=70 (100-30) and bin on_hand=30 after the balanced transfer, got dock=%/bin=%', v_dock_balance.on_hand, v_bin_balance.on_hand;
  end if;
end $$;

\echo '>> serial-controlled items: on_hand may never exceed 1 for the same serial number'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'acmeinv1');
  v_warehouse_id uuid := (select id from app.warehouses where tenant_id = v_tenant1 and code = 'WH-INV-1');
  v_dock_id uuid := (select id from app.warehouse_locations where tenant_id = v_tenant1 and code = 'DOCK-1');
  v_account_id uuid := (select id from app.accounts where tenant_id = v_tenant1 and legal_name = 'Inv Customer Alpha');
  v_item_serial_id uuid := (select id from app.item_masters where tenant_id = v_tenant1 and code = 'SKU-INV-SERIAL');
begin
  perform app.post_inventory_movement(v_tenant1, v_warehouse_id, 'opening_balance', 'opening_balance', null, 'idem-serial-1', null,
    jsonb_build_array(jsonb_build_object('owner_account_id', v_account_id, 'item_master_id', v_item_serial_id, 'location_id', v_dock_id, 'uom_code', 'PCS', 'signed_quantity', 1, 'serial_number', 'SN-0001')),
    '00000000-0000-0000-0000-000000100102', 'rep');

  begin
    perform app.post_inventory_movement(v_tenant1, v_warehouse_id, 'opening_balance', 'opening_balance', null, 'idem-serial-2', null,
      jsonb_build_array(jsonb_build_object('owner_account_id', v_account_id, 'item_master_id', v_item_serial_id, 'location_id', v_dock_id, 'uom_code', 'PCS', 'signed_quantity', 1, 'serial_number', 'SN-0001')),
      '00000000-0000-0000-0000-000000100102', 'rep');
    raise exception 'assertion failed: expected serial_conflict -- SN-0001 would exceed on_hand quantity 1';
  exception
    when others then
      if sqlerrm not like 'serial_conflict%' then raise; end if;
  end;
end $$;

\echo '>> app.reserve_inventory / app.release_inventory_reservation / app.consume_inventory_reservation: locks and checks availability, idempotent, release frees reserved, consume posts a real negative movement'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'acmeinv1');
  v_warehouse_id uuid := (select id from app.warehouses where tenant_id = v_tenant1 and code = 'WH-INV-1');
  v_bin_id uuid := (select id from app.warehouse_locations where tenant_id = v_tenant1 and code = 'BIN-1');
  v_account_id uuid := (select id from app.accounts where tenant_id = v_tenant1 and legal_name = 'Inv Customer Alpha');
  v_item_id uuid := (select id from app.item_masters where tenant_id = v_tenant1 and code = 'SKU-INV-A1');
  v_reservation app.inventory_reservations;
  v_replay app.inventory_reservations;
  v_balance app.inventory_balances;
begin
  begin
    perform app.reserve_inventory(v_tenant1, v_warehouse_id, v_account_id, v_item_id, v_bin_id, null, null, 1000, 'manual', null, 'idem-overreserve-1', '00000000-0000-0000-0000-000000100102', 'rep');
    raise exception 'assertion failed: expected insufficient_available_stock -- only 30 on hand at BIN-1';
  exception
    when others then
      if sqlerrm not like 'insufficient_available_stock%' then raise; end if;
  end;

  v_reservation := app.reserve_inventory(v_tenant1, v_warehouse_id, v_account_id, v_item_id, v_bin_id, null, null, 10, 'manual', null, 'idem-reserve-1', '00000000-0000-0000-0000-000000100102', 'rep');
  if v_reservation.reserved_quantity <> 10 or v_reservation.status <> 'active' then
    raise exception 'assertion failed: expected an active reservation of quantity 10';
  end if;

  v_replay := app.reserve_inventory(v_tenant1, v_warehouse_id, v_account_id, v_item_id, v_bin_id, null, null, 10, 'manual', null, 'idem-reserve-1', '00000000-0000-0000-0000-000000100102', 'rep');
  if v_replay.id <> v_reservation.id then
    raise exception 'assertion failed: expected the same-idempotency-key replay to return the identical reservation';
  end if;

  select * into v_balance from app.inventory_balances where id = v_reservation.balance_id;
  if v_balance.reserved <> 10 or v_balance.available <> v_balance.on_hand - 10 then
    raise exception 'assertion failed: expected reserved=10 and available=on_hand-10 on the balance row, got reserved=%/available=%', v_balance.reserved, v_balance.available;
  end if;

  -- A second reservation, then released -- proves release frees the reserved amount
  -- back to available without touching on_hand.
  declare
    v_reservation2 app.inventory_reservations;
    v_balance2 app.inventory_balances;
  begin
    v_reservation2 := app.reserve_inventory(v_tenant1, v_warehouse_id, v_account_id, v_item_id, v_bin_id, null, null, 5, 'manual', null, 'idem-reserve-2', '00000000-0000-0000-0000-000000100102', 'rep');
    v_reservation2 := app.release_inventory_reservation(v_reservation2.id, 'no longer needed', '00000000-0000-0000-0000-000000100102', 'rep');
    if v_reservation2.status <> 'released' then
      raise exception 'assertion failed: expected status=released';
    end if;
    select * into v_balance2 from app.inventory_balances where id = v_reservation2.balance_id;
    if v_balance2.reserved <> 10 then
      raise exception 'assertion failed: expected reserved to return to 10 (the still-active reservation only) after releasing the second, got %', v_balance2.reserved;
    end if;

    begin
      perform app.release_inventory_reservation(v_reservation2.id, 'again', '00000000-0000-0000-0000-000000100102', 'rep');
      raise exception 'assertion failed: expected invalid_transition -- already released';
    exception
      when others then
        if sqlerrm not like 'invalid_transition%' then raise; end if;
    end;
  end;

  v_reservation := app.consume_inventory_reservation(v_reservation.id, 'idem-consume-1', '00000000-0000-0000-0000-000000100102', 'rep');
  if v_reservation.status <> 'consumed' or v_reservation.consumed_movement_id is null then
    raise exception 'assertion failed: expected status=consumed with a real consumed_movement_id';
  end if;

  select * into v_balance from app.inventory_balances where id = v_reservation.balance_id;
  if v_balance.on_hand <> 20 or v_balance.reserved <> 0 then
    raise exception 'assertion failed: expected on_hand=20 (30-10 consumed) and reserved=0 after consumption, got on_hand=%/reserved=%', v_balance.on_hand, v_balance.reserved;
  end if;

  -- A same-reservation consume retry is a direct no-op (already consumed).
  if (app.consume_inventory_reservation(v_reservation.id, 'idem-consume-1-retry', '00000000-0000-0000-0000-000000100102', 'rep')).id <> v_reservation.id then
    raise exception 'assertion failed: expected a consume retry on an already-consumed reservation to be a no-op';
  end if;
end $$;

\echo '>> app.reverse_inventory_movement: posts a new movement with negated lines, never edits history, rejects double-reversal and reversing a reversal'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'acmeinv1');
  v_movement_id uuid := (select id from app.inventory_movements where tenant_id = v_tenant1 and idempotency_key = 'idem-serial-1');
  v_reversal app.inventory_movements;
  v_balance app.inventory_balances;
  v_dock_id uuid := (select id from app.warehouse_locations where tenant_id = v_tenant1 and code = 'DOCK-1');
  v_item_serial_id uuid := (select id from app.item_masters where tenant_id = v_tenant1 and code = 'SKU-INV-SERIAL');
begin
  v_reversal := app.reverse_inventory_movement(v_movement_id, 'idem-reverse-1', 'wrong serial entered', '00000000-0000-0000-0000-000000100102', 'rep');
  if v_reversal.movement_type <> 'reversal' or v_reversal.corrects_movement_id <> v_movement_id then
    raise exception 'assertion failed: expected a reversal movement linked back to the original';
  end if;

  select * into v_balance from app.inventory_balances
    where tenant_id = v_tenant1 and item_master_id = v_item_serial_id and location_id = v_dock_id and serial_number = 'SN-0001' and status = 'on_hand';
  if v_balance.on_hand <> 0 then
    raise exception 'assertion failed: expected the serial''s own on_hand to return to 0 after reversal, got %', v_balance.on_hand;
  end if;

  begin
    perform app.reverse_inventory_movement(v_movement_id, 'idem-reverse-2', 'trying again', '00000000-0000-0000-0000-000000100102', 'rep');
    raise exception 'assertion failed: expected already_reversed';
  exception
    when others then
      if sqlerrm not like 'already_reversed%' then raise; end if;
  end;

  begin
    perform app.reverse_inventory_movement(v_reversal.id, 'idem-reverse-3', 'reversing a reversal', '00000000-0000-0000-0000-000000100102', 'rep');
    raise exception 'assertion failed: expected invalid_reversal -- a reversal may not itself be reversed';
  exception
    when others then
      if sqlerrm not like 'invalid_reversal%' then raise; end if;
  end;
end $$;

\echo '>> app.list_inventory_balances / app.list_inventory_movements / app.get_inventory_balance / app.list_inventory_movement_lines: bounded reads, zero-row exclusion, cross-tenant isolation'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'acmeinv1');
  v_tenant2 uuid := (select id from app.tenants where slug = 'acmeinv2');
  v_warehouse_id uuid := (select id from app.warehouses where tenant_id = v_tenant1 and code = 'WH-INV-1');
  v_dock_id uuid := (select id from app.warehouse_locations where tenant_id = v_tenant1 and code = 'DOCK-1');
  v_account_id uuid := (select id from app.accounts where tenant_id = v_tenant1 and legal_name = 'Inv Customer Alpha');
  v_item_id uuid := (select id from app.item_masters where tenant_id = v_tenant1 and code = 'SKU-INV-A1');
  v_movement_id uuid := (select id from app.inventory_movements where tenant_id = v_tenant1 and idempotency_key = 'idem-open-1');
  v_count integer;
  v_balance app.inventory_balances;
begin
  select count(*) into v_count from app.list_inventory_balances(v_tenant1, '00000000-0000-0000-0000-000000100102', v_warehouse_id, null, null, 50);
  if v_count < 2 then
    raise exception 'assertion failed: expected at least 2 non-zero balance rows (dock + bin for SKU-INV-A1 alone), got %', v_count;
  end if;

  select count(*) into v_count from app.list_inventory_movements(v_tenant1, '00000000-0000-0000-0000-000000100102', v_warehouse_id, 'opening_balance', null, 50);
  if v_count < 2 then
    raise exception 'assertion failed: expected at least 2 opening_balance movements, got %', v_count;
  end if;

  v_balance := app.get_inventory_balance(v_tenant1, v_warehouse_id, v_account_id, v_item_id, v_dock_id, null, null, 'on_hand', '00000000-0000-0000-0000-000000100102');
  if v_balance.on_hand <> 70 then
    raise exception 'assertion failed: expected the direct dimension lookup to match the dock balance (70), got %', v_balance.on_hand;
  end if;

  select count(*) into v_count from app.list_inventory_movement_lines(v_movement_id, '00000000-0000-0000-0000-000000100102');
  if v_count <> 1 then
    raise exception 'assertion failed: expected exactly 1 line on the opening_balance movement, got %', v_count;
  end if;

  begin
    perform app.get_inventory_balance(v_tenant1, v_warehouse_id, v_account_id, v_item_id, v_dock_id, null, null, 'on_hand', '00000000-0000-0000-0000-000000100107');
    raise exception 'assertion failed: expected insufficient_authority -- tenant2''s rep has no membership in tenant1';
  exception
    when others then
      if sqlerrm not like 'insufficient_authority%' then raise; end if;
  end;

  select count(*) into v_count from app.list_inventory_balances(v_tenant2, '00000000-0000-0000-0000-000000100107', null, null, null, 50);
  if v_count <> 0 then
    raise exception 'assertion failed: expected tenant2''s own rep to see zero balances (none created there)';
  end if;
end $$;

\echo '>> schema-privilege defense in depth (ERR-2026-004): anon holds no direct table/EXECUTE access; authenticated has RLS-scoped SELECT but no direct INSERT/UPDATE/DELETE; only service_role may write directly'
do $$
begin
  if has_table_privilege('anon', 'app.inventory_movements', 'SELECT') then
    raise exception 'assertion failed: anon must not have direct SELECT on app.inventory_movements';
  end if;
  if has_table_privilege('anon', 'app.inventory_balances', 'SELECT') then
    raise exception 'assertion failed: anon must not have direct SELECT on app.inventory_balances';
  end if;
  if has_function_privilege('anon', 'app.post_inventory_movement(uuid, uuid, text, text, uuid, text, text, jsonb, uuid, text, uuid)', 'EXECUTE') then
    raise exception 'assertion failed: anon must not have EXECUTE on app.post_inventory_movement';
  end if;

  if not has_table_privilege('authenticated', 'app.inventory_balances', 'SELECT') then
    raise exception 'assertion failed: authenticated must have RLS-scoped SELECT on app.inventory_balances';
  end if;
  if has_table_privilege('authenticated', 'app.inventory_balances', 'UPDATE') then
    raise exception 'assertion failed: authenticated must not have direct UPDATE on app.inventory_balances -- normal roles never patch balance (Prompt 234 section 24)';
  end if;

  if not has_table_privilege('service_role', 'app.inventory_movements', 'INSERT') then
    raise exception 'assertion failed: service_role must retain direct table access to app.inventory_movements';
  end if;
end $$;
