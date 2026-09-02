-- Real, executable test evidence for ATW-017 (CG-S10-ATW-017, Prompt 236 WMS
-- Picking) -- run via `pnpm run db:test` against a real, disposable Postgres
-- database.

\set ON_ERROR_STOP on

\echo '>> setup: one tenant (wmspick1), a company org unit, a rep (OPS:Create/Edit/View), a second rep for claim/allocation-race checks, a supervisor (OPS:Create/Edit/View/Override), an OPS:View-only viewer, a global Supreme Admin, two owner accounts (Alpha, Beta) under tenant1 via the full CRM->Job Order pipeline, a customer_user-layer actor scoped to Account Alpha only (mirrors advanced-tms-lot-batch-serial-expiry.sql''s own cross-owner pattern), two warehouses (WH-PICK-1 with a full source/destination location taxonomy, WH-PICK-2 with one rack for cross-warehouse checks), and item masters (plain, lot-controlled, serial-controlled, two substitution-compatible items, one wrong-UOM item, one race-dedicated item, one Beta-owned item). Tenant2 (wmspick2): an isolated rep, for cross-tenant leakage checks.'
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
  v_account_alpha app.accounts;
  v_account_beta app.accounts;
  v_warehouse app.warehouses;
  v_warehouse2 app.warehouses;
begin
  insert into auth.users (id, email) values
    ('00000000-0000-0000-0000-000000180101', 'admin@wmspick1.test'),
    ('00000000-0000-0000-0000-000000180102', 'rep@wmspick1.test'),
    ('00000000-0000-0000-0000-000000180103', 'viewer@wmspick1.test'),
    ('00000000-0000-0000-0000-000000180104', 'supervisor@wmspick1.test'),
    ('00000000-0000-0000-0000-000000180105', 'supreme@wmspick1.test'),
    ('00000000-0000-0000-0000-000000180106', 'admin2@wmspick2.test'),
    ('00000000-0000-0000-0000-000000180107', 'rep2b@wmspick2.test'),
    ('00000000-0000-0000-0000-000000180108', 'rep2@wmspick1.test'),
    ('00000000-0000-0000-0000-000000180109', 'customer-alpha@wmspick1.test');

  perform app.grant_principal_membership('00000000-0000-0000-0000-000000180105', 'supreme_admin', null, null, 'tester');

  perform app.provision_tenant('wmspick1', 'WMS Picking Tenant One', 'idem-wmspick1', 'tester');
  v_tenant1 := (select id from app.tenants where slug = 'wmspick1');
  perform app.transition_tenant_status(v_tenant1, 'active', 'setup', 'tester');
  perform app.create_org_unit(v_tenant1, 'company', null, 'WMSPICK1-CO', 'WMS Picking Tenant One Co', 'tester');
  v_company := (select id from app.org_units where tenant_id = v_tenant1 and code = 'WMSPICK1-CO');

  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000180101', 'admin@wmspick1.test', 'WmsPick Admin', v_company, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'admin@wmspick1.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000180101', 'tenant_admin', v_tenant1, null, 'tester');

  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000180102', 'rep@wmspick1.test', 'WmsPick Rep', v_company, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'rep@wmspick1.test'), 'active', 'onboarded', 'tester');

  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000180108', 'rep2@wmspick1.test', 'WmsPick Rep Two', v_company, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'rep2@wmspick1.test'), 'active', 'onboarded', 'tester');

  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000180103', 'viewer@wmspick1.test', 'WmsPick Viewer', v_company, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'viewer@wmspick1.test'), 'active', 'onboarded', 'tester');

  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000180104', 'supervisor@wmspick1.test', 'WmsPick Supervisor', v_company, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'supervisor@wmspick1.test'), 'active', 'onboarded', 'tester');

  -- The rep role holds OPS Create/Edit/View together -- app.generate_wms_pick_task
  -- composes app.reserve_inventory (OPS:Edit) and app.list_allocation_candidates
  -- (OPS:View) internally, on top of its own OPS:Create top-level gate, so a rep
  -- must hold all three for generation to fully succeed (a disclosed, reasonable
  -- role-composition dependency -- see the migration's own header).
  v_rep_role := (app.create_role(v_tenant1, 'WmsPick Rep Role', 'full commercial + ops create/edit/view', 'tester')).id;
  v_rep_draft := app.create_role_version(v_rep_role, 'tester');
  perform app.set_role_version_permissions(
    v_rep_draft.id,
    array(select id from app.permissions where (resource_module_code = 'COM' and action in ('Create', 'Edit', 'Approve', 'View', 'View cost'))
      or (resource_module_code = 'OPS' and action in ('Create', 'Edit', 'View'))),
    'tester'
  );
  perform app.publish_role_version(v_rep_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_rep_role and status = 'published'), '00000000-0000-0000-0000-000000180102', '00000000-0000-0000-0000-000000180101', 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_rep_role and status = 'published'), '00000000-0000-0000-0000-000000180108', '00000000-0000-0000-0000-000000180101', 'tester');

  v_supervisor_role := (app.create_role(v_tenant1, 'WmsPick Supervisor Role', 'ops create/edit/view/override', 'tester')).id;
  v_supervisor_draft := app.create_role_version(v_supervisor_role, 'tester');
  perform app.set_role_version_permissions(
    v_supervisor_draft.id,
    array(select id from app.permissions where resource_module_code = 'OPS' and action in ('Create', 'Edit', 'View', 'Override')),
    'tester'
  );
  perform app.publish_role_version(v_supervisor_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_supervisor_role and status = 'published'), '00000000-0000-0000-0000-000000180104', '00000000-0000-0000-0000-000000180101', 'tester');

  v_viewer_role := (app.create_role(v_tenant1, 'WmsPick Viewer Role', 'OPS:View only', 'tester')).id;
  v_viewer_draft := app.create_role_version(v_viewer_role, 'tester');
  perform app.set_role_version_permissions(v_viewer_draft.id, array(select id from app.permissions where resource_module_code = 'OPS' and action = 'View'), 'tester');
  perform app.publish_role_version(v_viewer_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_viewer_role and status = 'published'), '00000000-0000-0000-0000-000000180103', '00000000-0000-0000-0000-000000180101', 'tester');

  v_warehouse := app.create_warehouse(v_tenant1, v_company, 'WH-PICK-1', 'WMS Picking Warehouse 1', 'Jl. Picking 1', 'Asia/Jakarta', null, array['land']::text[], '00000000-0000-0000-0000-000000180102', 'rep');
  declare
    v_rack_a app.warehouse_locations;
    v_rack_b app.warehouse_locations;
    v_rack_notenabled app.warehouse_locations;
    v_stage1 app.warehouse_locations;
    v_stage_cap app.warehouse_locations;
  begin
    v_rack_a := app.create_warehouse_location(v_warehouse.id, null, null, 'RACK-PICK-A', 'Picking Rack A', 'rack', 1, null, null, null, null, null, true, false, '00000000-0000-0000-0000-000000180102', 'rep');
    perform app.set_warehouse_location_status(v_rack_a.id, 'active', null, v_rack_a.record_version, '00000000-0000-0000-0000-000000180102', 'rep');
    v_rack_b := app.create_warehouse_location(v_warehouse.id, null, null, 'RACK-PICK-B', 'Picking Rack B', 'rack', 2, null, null, null, null, null, true, false, '00000000-0000-0000-0000-000000180102', 'rep');
    perform app.set_warehouse_location_status(v_rack_b.id, 'active', null, v_rack_b.record_version, '00000000-0000-0000-0000-000000180102', 'rep');
    v_rack_notenabled := app.create_warehouse_location(v_warehouse.id, null, null, 'RACK-PICK-NOTENABLED', 'Picking Rack Not Pick-Enabled', 'rack', 3, null, null, null, null, null, false, false, '00000000-0000-0000-0000-000000180102', 'rep');
    perform app.set_warehouse_location_status(v_rack_notenabled.id, 'active', null, v_rack_notenabled.record_version, '00000000-0000-0000-0000-000000180102', 'rep');
    -- RACK-PICK-INACTIVE is deliberately left in its default draft status -- the
    -- blocked_location test at generation time feeds off exactly this.
    perform app.create_warehouse_location(v_warehouse.id, null, null, 'RACK-PICK-INACTIVE', 'Picking Rack Inactive', 'rack', 4, null, null, null, null, null, true, false, '00000000-0000-0000-0000-000000180102', 'rep');
    v_stage1 := app.create_warehouse_location(v_warehouse.id, null, null, 'STAGE-PICK-1', 'Picking Staging 1', 'staging', 5, null, null, null, null, null, false, false, '00000000-0000-0000-0000-000000180102', 'rep');
    perform app.set_warehouse_location_status(v_stage1.id, 'active', null, v_stage1.record_version, '00000000-0000-0000-0000-000000180102', 'rep');
    v_stage_cap := app.create_warehouse_location(v_warehouse.id, null, null, 'STAGE-PICK-CAP', 'Picking Staging Capacity-Limited', 'staging', 6, 5, 'units', null, null, null, false, false, '00000000-0000-0000-0000-000000180102', 'rep');
    perform app.set_warehouse_location_status(v_stage_cap.id, 'active', null, v_stage_cap.record_version, '00000000-0000-0000-0000-000000180102', 'rep');
    -- STAGE-PICK-INACTIVE is deliberately left draft -- the blocked_destination test at
    -- confirm time feeds off exactly this.
    perform app.create_warehouse_location(v_warehouse.id, null, null, 'STAGE-PICK-INACTIVE', 'Picking Staging Inactive', 'staging', 7, null, null, null, null, null, false, false, '00000000-0000-0000-0000-000000180102', 'rep');
  end;

  v_warehouse2 := app.create_warehouse(v_tenant1, v_company, 'WH-PICK-2', 'WMS Picking Warehouse 2', 'Jl. Picking 2', 'Asia/Jakarta', null, array['land']::text[], '00000000-0000-0000-0000-000000180102', 'rep');
  declare
    v_rack_wh2 app.warehouse_locations;
  begin
    v_rack_wh2 := app.create_warehouse_location(v_warehouse2.id, null, null, 'RACK-PICK-WH2', 'Picking Rack (Warehouse 2)', 'rack', 1, null, null, null, null, null, true, false, '00000000-0000-0000-0000-000000180102', 'rep');
    perform app.set_warehouse_location_status(v_rack_wh2.id, 'active', null, v_rack_wh2.record_version, '00000000-0000-0000-0000-000000180102', 'rep');
  end;

  -- Account Alpha, via the full CRM->Job Order pipeline (mirrors advanced-tms-
  -- wms-outbound-order.sql's own precedent; no Job Order/Shipment is needed here since
  -- outbound orders in THIS fixture are all manual).
  perform app.capture_lead(v_tenant1, 'manual', null, 'WmsPick Customer Alpha', 'Alice WmsPick', 'alice@wmspick236.test', '0811',
    '00000000-0000-0000-0000-000000180102', v_company, '00000000-0000-0000-0000-000000180102', 'tester');
  select * into v_lead from app.leads where email = 'alice@wmspick236.test';
  perform app.qualify_lead(v_lead.id, v_lead.record_version, '00000000-0000-0000-0000-000000180102', 'tester');
  select * into v_lead from app.leads where id = v_lead.id;
  perform app.convert_lead_to_prospect(v_lead.id, 'WmsPick Customer Alpha', 'WMSPICK236A', '11.111.111.14-111.000',
    jsonb_build_object('line1', 'Jl. Picking Alpha 12', 'city', 'Jakarta', 'country', 'ID'),
    '00000000-0000-0000-0000-000000180102', 'tester');
  select * into v_prospect from app.prospects where lead_id = v_lead.id;
  select * into v_contact from app.create_contact(v_tenant1, 'Alice WmsPick Ops', 'Ops Lead', 'alice@wmspick236.test', '0811', '00000000-0000-0000-0000-000000180102', v_company, '00000000-0000-0000-0000-000000180102', 'tester');
  perform app.link_contact_to_record(v_contact.id, 'prospect', v_prospect.id, 'primary', true, '00000000-0000-0000-0000-000000180102', 'tester');
  select * into v_opportunity from app.create_opportunity(
    v_tenant1, v_prospect.id, 'WMSPICK236 Alpha lane',
    jsonb_build_object('service_type', 'land_freight', 'cargo_description', 'General cargo', 'origin', 'Jakarta', 'destination', 'Surabaya', 'target_ready_date', '2026-08-01'),
    '00000000-0000-0000-0000-000000180102', v_company, '00000000-0000-0000-0000-000000180102', 'tester'
  );
  select * into v_request from app.request_costing(v_opportunity.id, '[]'::jsonb, null, '00000000-0000-0000-0000-000000180102', 'tester');
  select * into v_rate from app.create_rate_version(
    v_tenant1, 'VENDOR-WMSPICK236-A', 'Contoso WmsPick236 Line', 'land_freight', 'FTL', 'Jakarta', 'Surabaya', '20ft',
    null, null, null, null, 'IDR', 5000000, null, '[]'::jsonb, now(), null, null, '00000000-0000-0000-0000-000000180101', 'tester'
  );
  perform app.approve_rate_version(v_rate.id, v_rate.record_version, '00000000-0000-0000-0000-000000180101', 'tester');
  select * into v_selection from app.select_vendor_rate(v_request.id, v_rate.id, false, null, null, null, '00000000-0000-0000-0000-000000180102', 'tester');
  v_rule := app.create_margin_rule_version(v_tenant1, 20.00, 'half_up', '00000000-0000-0000-0000-000000180102', 'tester');
  perform app.publish_margin_rule_version(v_rule.id, v_rule.record_version, null, '00000000-0000-0000-0000-000000180102', 'tester');
  perform app.calculate_margin(v_selection.id, 6000000, 'IDR', 0, '00000000-0000-0000-0000-000000180102', 'tester');
  select id into v_calc_id from app.margin_calculations where rate_selection_id = v_selection.id and is_current;
  select * into v_quote from app.create_quotation_draft(v_tenant1, v_opportunity.id, 'IDR', now() + interval '14 days', v_contact.id, null, null, '00000000-0000-0000-0000-000000180102', 'tester');
  perform app.add_quotation_line(v_quote.id, v_quote.record_version, 'service', 'WMSPICK236 Alpha lane', v_calc_id, 1, 6000000, 0, 0, '00000000-0000-0000-0000-000000180102', 'tester');
  select * into v_quote from app.quotations where id = v_quote.id;
  perform app.submit_quotation(v_quote.id, v_quote.record_version, '00000000-0000-0000-0000-000000180102', 'tester');
  select * into v_send from app.send_quotation_for_acceptance(v_quote.id, null, 'email', '00000000-0000-0000-0000-000000180102', 'tester');
  perform app.record_quotation_customer_decision(v_send.raw_token, 'accepted', 'Alice WmsPick Ops', null, null, null, null, null);
  select * into v_quote from app.quotations where id = v_quote.id;
  select * into v_account_alpha from app.convert_quotation_to_account(v_quote.id, null, null, '00000000-0000-0000-0000-000000180102', 'rep');

  -- Account Beta, a second owner account in the SAME tenant -- cross-owner isolation.
  perform app.capture_lead(v_tenant1, 'manual', null, 'WmsPick Customer Beta', 'Bob WmsPick', 'bob@wmspick236.test', '0812',
    '00000000-0000-0000-0000-000000180102', v_company, '00000000-0000-0000-0000-000000180102', 'tester');
  select * into v_lead from app.leads where email = 'bob@wmspick236.test';
  perform app.qualify_lead(v_lead.id, v_lead.record_version, '00000000-0000-0000-0000-000000180102', 'tester');
  select * into v_lead from app.leads where id = v_lead.id;
  perform app.convert_lead_to_prospect(v_lead.id, 'WmsPick Customer Beta', 'WMSPICK236B', '11.111.111.15-111.000',
    jsonb_build_object('line1', 'Jl. Picking Beta 13', 'city', 'Jakarta', 'country', 'ID'),
    '00000000-0000-0000-0000-000000180102', 'tester');
  select * into v_prospect from app.prospects where lead_id = v_lead.id;
  select * into v_contact from app.create_contact(v_tenant1, 'Bob WmsPick Ops', 'Ops Lead', 'bob@wmspick236.test', '0812', '00000000-0000-0000-0000-000000180102', v_company, '00000000-0000-0000-0000-000000180102', 'tester');
  perform app.link_contact_to_record(v_contact.id, 'prospect', v_prospect.id, 'primary', true, '00000000-0000-0000-0000-000000180102', 'tester');
  select * into v_opportunity from app.create_opportunity(
    v_tenant1, v_prospect.id, 'WMSPICK236 Beta lane',
    jsonb_build_object('service_type', 'land_freight', 'cargo_description', 'General cargo', 'origin', 'Jakarta', 'destination', 'Surabaya', 'target_ready_date', '2026-08-01'),
    '00000000-0000-0000-0000-000000180102', v_company, '00000000-0000-0000-0000-000000180102', 'tester'
  );
  select * into v_request from app.request_costing(v_opportunity.id, '[]'::jsonb, null, '00000000-0000-0000-0000-000000180102', 'tester');
  select * into v_rate from app.create_rate_version(
    v_tenant1, 'VENDOR-WMSPICK236-B', 'Contoso WmsPick236 Line B', 'land_freight', 'FTL', 'Jakarta', 'Surabaya', '20ft',
    null, null, null, null, 'IDR', 5000000, null, '[]'::jsonb, now(), null, null, '00000000-0000-0000-0000-000000180101', 'tester'
  );
  perform app.approve_rate_version(v_rate.id, v_rate.record_version, '00000000-0000-0000-0000-000000180101', 'tester');
  select * into v_selection from app.select_vendor_rate(v_request.id, v_rate.id, false, null, null, null, '00000000-0000-0000-0000-000000180102', 'tester');
  perform app.calculate_margin(v_selection.id, 6000000, 'IDR', 0, '00000000-0000-0000-0000-000000180102', 'tester');
  select id into v_calc_id from app.margin_calculations where rate_selection_id = v_selection.id and is_current;
  select * into v_quote from app.create_quotation_draft(v_tenant1, v_opportunity.id, 'IDR', now() + interval '14 days', v_contact.id, null, null, '00000000-0000-0000-0000-000000180102', 'tester');
  perform app.add_quotation_line(v_quote.id, v_quote.record_version, 'service', 'WMSPICK236 Beta lane', v_calc_id, 1, 6000000, 0, 0, '00000000-0000-0000-0000-000000180102', 'tester');
  select * into v_quote from app.quotations where id = v_quote.id;
  perform app.submit_quotation(v_quote.id, v_quote.record_version, '00000000-0000-0000-0000-000000180102', 'tester');
  select * into v_send from app.send_quotation_for_acceptance(v_quote.id, null, 'email', '00000000-0000-0000-0000-000000180102', 'tester');
  perform app.record_quotation_customer_decision(v_send.raw_token, 'accepted', 'Bob WmsPick Ops', null, null, null, null, null);
  select * into v_quote from app.quotations where id = v_quote.id;
  select * into v_account_beta from app.convert_quotation_to_account(v_quote.id, null, null, '00000000-0000-0000-0000-000000180102', 'rep');

  perform app.create_item_master(v_tenant1, v_account_alpha.id, 'SKU-PICK-PLAIN', 'Pick Plain Widget', null, 'PCS', false, false, false, '00000000-0000-0000-0000-000000180102', 'rep');
  perform app.create_item_master(v_tenant1, v_account_alpha.id, 'SKU-PICK-LOT', 'Pick Lot Widget', null, 'PCS', true, false, true, '00000000-0000-0000-0000-000000180102', 'rep');
  perform app.create_item_master(v_tenant1, v_account_alpha.id, 'SKU-PICK-SERIAL', 'Pick Serial Widget', null, 'PCS', false, true, false, '00000000-0000-0000-0000-000000180102', 'rep');
  perform app.create_item_master(v_tenant1, v_account_alpha.id, 'SKU-PICK-SUB-FROM', 'Pick Substitution Source', null, 'PCS', false, false, false, '00000000-0000-0000-0000-000000180102', 'rep');
  perform app.create_item_master(v_tenant1, v_account_alpha.id, 'SKU-PICK-SUB-TO', 'Pick Substitution Target', null, 'PCS', false, false, false, '00000000-0000-0000-0000-000000180102', 'rep');
  perform app.create_item_master(v_tenant1, v_account_alpha.id, 'SKU-PICK-SUB-WRONGUOM', 'Pick Substitution Wrong UOM', null, 'KG', false, false, false, '00000000-0000-0000-0000-000000180102', 'rep');
  perform app.create_item_master(v_tenant1, v_account_alpha.id, 'SKU-PICK-RACE', 'Pick Race Widget', null, 'PCS', false, false, false, '00000000-0000-0000-0000-000000180102', 'rep');
  perform app.create_item_master(v_tenant1, v_account_beta.id, 'SKU-PICK-BETA', 'Pick Beta Widget', null, 'PCS', false, false, false, '00000000-0000-0000-0000-000000180102', 'rep');

  -- The customer_user-layer actor is invited with a NULL org_unit_id -- the ONLY path
  -- by which it can ever pass app.can_access_record's row filter is real org-unit
  -- membership it does not have here, so app.actor_can_view_owner_scoped_row's own
  -- customer_account_ref match (ATW-016) is the real, sole gate tested below.
  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000180109', 'customer-alpha@wmspick1.test', 'Customer Alpha Portal', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'customer-alpha@wmspick1.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000180109', 'customer_user', v_tenant1, v_account_alpha.id::text, 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_viewer_role and status = 'published'), '00000000-0000-0000-0000-000000180109', '00000000-0000-0000-0000-000000180101', 'tester');

  -- Tenant2: fully isolated -- exists only to prove cross-tenant scope safety.
  perform app.provision_tenant('wmspick2', 'WMS Picking Tenant Two', 'idem-wmspick2', 'tester');
  v_tenant2 := (select id from app.tenants where slug = 'wmspick2');
  perform app.transition_tenant_status(v_tenant2, 'active', 'setup', 'tester');
  perform app.create_org_unit(v_tenant2, 'company', null, 'WMSPICK2-CO', 'WMS Picking Tenant Two Co', 'tester');
  v_company2 := (select id from app.org_units where tenant_id = v_tenant2 and code = 'WMSPICK2-CO');
  perform app.invite_user(v_tenant2, '00000000-0000-0000-0000-000000180106', 'admin2@wmspick2.test', 'Tenant2 Admin', v_company2, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'admin2@wmspick2.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000180106', 'tenant_admin', v_tenant2, null, 'tester');
  perform app.invite_user(v_tenant2, '00000000-0000-0000-0000-000000180107', 'rep2b@wmspick2.test', 'Tenant2 Rep', v_company2, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'rep2b@wmspick2.test'), 'active', 'onboarded', 'tester');
  v_rep2_role := (app.create_role(v_tenant2, 'Tenant2 Rep Role', 'ops create/edit/view', 'tester')).id;
  v_rep2_draft := app.create_role_version(v_rep2_role, 'tester');
  perform app.set_role_version_permissions(v_rep2_draft.id, array(select id from app.permissions where resource_module_code = 'OPS' and action in ('Create', 'Edit', 'View')), 'tester');
  perform app.publish_role_version(v_rep2_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant2, (select id from app.role_versions where role_id = v_rep2_role and status = 'published'), '00000000-0000-0000-0000-000000180107', '00000000-0000-0000-0000-000000180106', 'tester');
end $$;

\echo '>> build the main confirmed Alpha outbound order (16 lines, one per picking scenario) plus one confirmed Beta outbound order (1 line, cross-owner isolation), and seed real opening_balance inventory for every item at RACK-PICK-A/B -- exact quantities matching each line''s own scenario'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'wmspick1');
  v_warehouse_id uuid := (select id from app.warehouses where tenant_id = v_tenant1 and code = 'WH-PICK-1');
  v_rack_a_id uuid := (select id from app.warehouse_locations where tenant_id = v_tenant1 and code = 'RACK-PICK-A');
  v_rack_b_id uuid := (select id from app.warehouse_locations where tenant_id = v_tenant1 and code = 'RACK-PICK-B');
  v_account_alpha_id uuid := (select id from app.accounts where tenant_id = v_tenant1 and legal_name = 'WmsPick Customer Alpha');
  v_account_beta_id uuid := (select id from app.accounts where tenant_id = v_tenant1 and legal_name = 'WmsPick Customer Beta');
  v_plain_id uuid := (select id from app.item_masters where tenant_id = v_tenant1 and code = 'SKU-PICK-PLAIN');
  v_lot_id uuid := (select id from app.item_masters where tenant_id = v_tenant1 and code = 'SKU-PICK-LOT');
  v_serial_id uuid := (select id from app.item_masters where tenant_id = v_tenant1 and code = 'SKU-PICK-SERIAL');
  v_subfrom_id uuid := (select id from app.item_masters where tenant_id = v_tenant1 and code = 'SKU-PICK-SUB-FROM');
  v_subto_id uuid := (select id from app.item_masters where tenant_id = v_tenant1 and code = 'SKU-PICK-SUB-TO');
  v_race_id uuid := (select id from app.item_masters where tenant_id = v_tenant1 and code = 'SKU-PICK-RACE');
  v_beta_item_id uuid := (select id from app.item_masters where tenant_id = v_tenant1 and code = 'SKU-PICK-BETA');
  v_order app.wms_outbound_orders;
  v_beta_order app.wms_outbound_orders;
  v_lines app.wms_outbound_order_lines[];
begin
  v_order := app.create_manual_wms_outbound_order(v_tenant1, v_warehouse_id, v_account_alpha_id, 'main picking fixture', 'idem-pick-main', null, '00000000-0000-0000-0000-000000180102', 'rep');

  select array_agg(l) into v_lines from app.add_wms_outbound_order_lines(
    v_order.id,
    jsonb_build_array(
      jsonb_build_object('item_master_id', v_plain_id, 'requested_uom_code', 'PCS', 'requested_quantity', 100, 'notes', 'L1 single full confirm'),
      jsonb_build_object('item_master_id', v_plain_id, 'requested_uom_code', 'PCS', 'requested_quantity', 30, 'notes', 'L2 partial then full'),
      jsonb_build_object('item_master_id', v_plain_id, 'requested_uom_code', 'PCS', 'requested_quantity', 20, 'notes', 'L3 short then remainder picked'),
      jsonb_build_object('item_master_id', v_plain_id, 'requested_uom_code', 'PCS', 'requested_quantity', 10, 'notes', 'L4 over-pick hard rejection'),
      jsonb_build_object('item_master_id', v_plain_id, 'requested_uom_code', 'PCS', 'requested_quantity', 10, 'notes', 'L5 concurrent claim race'),
      jsonb_build_object('item_master_id', v_race_id, 'requested_uom_code', 'PCS', 'requested_quantity', 10, 'notes', 'L6 concurrent double-allocation race'),
      jsonb_build_object('item_master_id', v_lot_id, 'requested_uom_code', 'PCS', 'requested_quantity', 8, 'notes', 'L7 lot-controlled scan verification'),
      jsonb_build_object('item_master_id', v_serial_id, 'requested_uom_code', 'PCS', 'requested_quantity', 1, 'notes', 'L8 serial-controlled scan verification'),
      jsonb_build_object('item_master_id', v_subfrom_id, 'requested_uom_code', 'PCS', 'requested_quantity', 10, 'notes', 'L9 substitution approval success'),
      jsonb_build_object('item_master_id', v_subfrom_id, 'requested_uom_code', 'PCS', 'requested_quantity', 5, 'notes', 'L10 substitution rejections'),
      jsonb_build_object('item_master_id', v_plain_id, 'requested_uom_code', 'PCS', 'requested_quantity', 15, 'notes', 'L11 cancel task (zero progress)'),
      jsonb_build_object('item_master_id', v_plain_id, 'requested_uom_code', 'PCS', 'requested_quantity', 1000, 'notes', 'L12 no eligible stock / insufficient remaining'),
      jsonb_build_object('item_master_id', v_plain_id, 'requested_uom_code', 'PCS', 'requested_quantity', 20, 'notes', 'L13 wave batching A'),
      jsonb_build_object('item_master_id', v_plain_id, 'requested_uom_code', 'PCS', 'requested_quantity', 25, 'notes', 'L14 wave batching B'),
      jsonb_build_object('item_master_id', v_plain_id, 'requested_uom_code', 'PCS', 'requested_quantity', 5, 'notes', 'L15 destination capacity/blocked/incompatible'),
      jsonb_build_object('item_master_id', v_plain_id, 'requested_uom_code', 'PCS', 'requested_quantity', 5, 'notes', 'L16 exception + supervisor reassign/release')
    ),
    '00000000-0000-0000-0000-000000180102', 'rep'
  ) l;
  if array_length(v_lines, 1) <> 16 then
    raise exception 'assertion failed: expected exactly 16 lines on the main outbound order, got %', array_length(v_lines, 1);
  end if;

  v_order := app.confirm_wms_outbound_order(v_order.id, v_order.record_version, '00000000-0000-0000-0000-000000180102', 'rep');
  if v_order.status <> 'confirmed' then
    raise exception 'assertion failed: expected the main outbound order to be confirmed, got %', v_order.status;
  end if;

  v_beta_order := app.create_manual_wms_outbound_order(v_tenant1, v_warehouse_id, v_account_beta_id, 'beta picking fixture', 'idem-pick-beta', null, '00000000-0000-0000-0000-000000180102', 'rep');
  perform app.add_wms_outbound_order_line(v_beta_order.id, v_beta_item_id, 'PCS', 12, 'Beta L1', '00000000-0000-0000-0000-000000180102', 'rep');
  v_beta_order := app.confirm_wms_outbound_order(v_beta_order.id, v_beta_order.record_version, '00000000-0000-0000-0000-000000180102', 'rep');
  if v_beta_order.status <> 'confirmed' then
    raise exception 'assertion failed: expected the beta outbound order to be confirmed, got %', v_beta_order.status;
  end if;

  -- Real opening_balance inventory -- enough for every scenario line above except L12
  -- (deliberately left with zero stock anywhere -- no_eligible_pick_location /
  -- insufficient_remaining_quantity at generation).
  perform app.post_inventory_movement(v_tenant1, v_warehouse_id, 'opening_balance', 'opening_balance', null, 'idem-pick-open-plain-a', 'opening balance fixture',
    jsonb_build_array(jsonb_build_object('owner_account_id', v_account_alpha_id, 'item_master_id', v_plain_id, 'location_id', v_rack_a_id, 'uom_code', 'PCS', 'signed_quantity', 300, 'status', 'on_hand')),
    '00000000-0000-0000-0000-000000180102', 'rep');

  perform app.post_inventory_movement(v_tenant1, v_warehouse_id, 'opening_balance', 'opening_balance', null, 'idem-pick-open-race-a', 'opening balance fixture',
    jsonb_build_array(jsonb_build_object('owner_account_id', v_account_alpha_id, 'item_master_id', v_race_id, 'location_id', v_rack_a_id, 'uom_code', 'PCS', 'signed_quantity', 10, 'status', 'on_hand')),
    '00000000-0000-0000-0000-000000180102', 'rep');
  perform app.post_inventory_movement(v_tenant1, v_warehouse_id, 'opening_balance', 'opening_balance', null, 'idem-pick-open-race-b', 'opening balance fixture',
    jsonb_build_array(jsonb_build_object('owner_account_id', v_account_alpha_id, 'item_master_id', v_race_id, 'location_id', v_rack_b_id, 'uom_code', 'PCS', 'signed_quantity', 10, 'status', 'on_hand')),
    '00000000-0000-0000-0000-000000180102', 'rep');

  perform app.post_inventory_movement(v_tenant1, v_warehouse_id, 'opening_balance', 'opening_balance', null, 'idem-pick-open-lot-a', 'opening balance fixture',
    jsonb_build_array(jsonb_build_object('owner_account_id', v_account_alpha_id, 'item_master_id', v_lot_id, 'location_id', v_rack_a_id, 'uom_code', 'PCS', 'signed_quantity', 8, 'lot_number', 'LOT-PICK-A', 'expiry_date', (current_date + 30)::text, 'status', 'on_hand')),
    '00000000-0000-0000-0000-000000180102', 'rep');

  perform app.post_inventory_movement(v_tenant1, v_warehouse_id, 'opening_balance', 'opening_balance', null, 'idem-pick-open-serial-a', 'opening balance fixture',
    jsonb_build_array(jsonb_build_object('owner_account_id', v_account_alpha_id, 'item_master_id', v_serial_id, 'location_id', v_rack_a_id, 'uom_code', 'PCS', 'signed_quantity', 1, 'serial_number', 'SN-PICK-A', 'status', 'on_hand')),
    '00000000-0000-0000-0000-000000180102', 'rep');

  perform app.post_inventory_movement(v_tenant1, v_warehouse_id, 'opening_balance', 'opening_balance', null, 'idem-pick-open-subfrom-a', 'opening balance fixture',
    jsonb_build_array(jsonb_build_object('owner_account_id', v_account_alpha_id, 'item_master_id', v_subfrom_id, 'location_id', v_rack_a_id, 'uom_code', 'PCS', 'signed_quantity', 15, 'status', 'on_hand')),
    '00000000-0000-0000-0000-000000180102', 'rep');
  perform app.post_inventory_movement(v_tenant1, v_warehouse_id, 'opening_balance', 'opening_balance', null, 'idem-pick-open-subto-a', 'opening balance fixture',
    jsonb_build_array(jsonb_build_object('owner_account_id', v_account_alpha_id, 'item_master_id', v_subto_id, 'location_id', v_rack_a_id, 'uom_code', 'PCS', 'signed_quantity', 15, 'status', 'on_hand')),
    '00000000-0000-0000-0000-000000180102', 'rep');

  perform app.post_inventory_movement(v_tenant1, v_warehouse_id, 'opening_balance', 'opening_balance', null, 'idem-pick-open-beta', 'opening balance fixture',
    jsonb_build_array(jsonb_build_object('owner_account_id', v_account_beta_id, 'item_master_id', v_beta_item_id, 'location_id', v_rack_a_id, 'uom_code', 'PCS', 'signed_quantity', 12, 'status', 'on_hand')),
    '00000000-0000-0000-0000-000000180102', 'rep');
end $$;

\echo '>> app.create_wms_pick_wave: viewer rejected; idempotent replay; app.generate_wms_pick_task (L1): viewer rejected; outbound_order_line_not_found; invalid_quantity; wave_not_found; caller-supplied location_not_eligible (not pick_enabled), blocked_location (inactive); success auto-selects RACK-PICK-A (only eligible location); idempotent on idempotency_key; insufficient_remaining_quantity on a second attempt against the now-fully-allocated line'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'wmspick1');
  v_warehouse_id uuid := (select id from app.warehouses where tenant_id = v_tenant1 and code = 'WH-PICK-1');
  v_rack_a_id uuid := (select id from app.warehouse_locations where tenant_id = v_tenant1 and code = 'RACK-PICK-A');
  v_rack_notenabled_id uuid := (select id from app.warehouse_locations where tenant_id = v_tenant1 and code = 'RACK-PICK-NOTENABLED');
  v_rack_inactive_id uuid := (select id from app.warehouse_locations where tenant_id = v_tenant1 and code = 'RACK-PICK-INACTIVE');
  v_order_id uuid := (select id from app.wms_outbound_orders where tenant_id = v_tenant1 and idempotency_key = 'idem-pick-main');
  v_line1 app.wms_outbound_order_lines;
  v_wave app.wms_pick_waves;
  v_wave_replay app.wms_pick_waves;
  v_task app.wms_pick_tasks;
  v_replay app.wms_pick_tasks;
begin
  select * into v_line1 from app.wms_outbound_order_lines where outbound_order_id = v_order_id and line_number = 1;

  begin
    perform app.create_wms_pick_wave(v_tenant1, v_warehouse_id, 'idem-wave-viewer', '00000000-0000-0000-0000-000000180103', 'viewer');
    raise exception 'assertion failed: expected insufficient_authority -- viewer holds OPS:View only';
  exception
    when others then
      if sqlerrm not like 'insufficient_authority%' then raise; end if;
  end;

  v_wave := app.create_wms_pick_wave(v_tenant1, v_warehouse_id, 'idem-wave-1', '00000000-0000-0000-0000-000000180102', 'rep');
  v_wave_replay := app.create_wms_pick_wave(v_tenant1, v_warehouse_id, 'idem-wave-1', '00000000-0000-0000-0000-000000180102', 'rep');
  if v_wave_replay.id <> v_wave.id then
    raise exception 'assertion failed: expected the same-idempotency-key wave replay to return the identical wave';
  end if;

  begin
    perform app.generate_wms_pick_task(v_line1.id, 100, null, null, null, null, null, 'idem-gen-viewer', '00000000-0000-0000-0000-000000180103', 'viewer');
    raise exception 'assertion failed: expected insufficient_authority -- viewer holds OPS:View only';
  exception
    when others then
      if sqlerrm not like 'insufficient_authority%' then raise; end if;
  end;

  begin
    perform app.generate_wms_pick_task(gen_random_uuid(), 100, null, null, null, null, null, 'idem-gen-badline', '00000000-0000-0000-0000-000000180102', 'rep');
    raise exception 'assertion failed: expected outbound_order_line_not_found';
  exception
    when others then
      if sqlerrm not like 'outbound_order_line_not_found%' then raise; end if;
  end;

  begin
    perform app.generate_wms_pick_task(v_line1.id, 0, null, null, null, null, null, 'idem-gen-zeroqty', '00000000-0000-0000-0000-000000180102', 'rep');
    raise exception 'assertion failed: expected invalid_quantity -- zero quantity';
  exception
    when others then
      if sqlerrm not like 'invalid_quantity%' then raise; end if;
  end;

  begin
    perform app.generate_wms_pick_task(v_line1.id, 100, gen_random_uuid(), null, null, null, null, 'idem-gen-badwave', '00000000-0000-0000-0000-000000180102', 'rep');
    raise exception 'assertion failed: expected wave_not_found';
  exception
    when others then
      if sqlerrm not like 'wave_not_found%' then raise; end if;
  end;

  begin
    perform app.generate_wms_pick_task(v_line1.id, 10, null, v_rack_notenabled_id, null, null, null, 'idem-gen-notenabled', '00000000-0000-0000-0000-000000180102', 'rep');
    raise exception 'assertion failed: expected location_not_eligible -- RACK-PICK-NOTENABLED is not pick_enabled';
  exception
    when others then
      if sqlerrm not like 'location_not_eligible%' then raise; end if;
  end;

  begin
    perform app.generate_wms_pick_task(v_line1.id, 10, null, v_rack_inactive_id, null, null, null, 'idem-gen-inactiveloc', '00000000-0000-0000-0000-000000180102', 'rep');
    raise exception 'assertion failed: expected blocked_location -- RACK-PICK-INACTIVE is not active';
  exception
    when others then
      if sqlerrm not like 'blocked_location%' then raise; end if;
  end;

  -- Auto-select: only RACK-PICK-A holds SKU-PICK-PLAIN stock (RACK-PICK-B has none),
  -- so it must be the resolved source.
  v_task := app.generate_wms_pick_task(v_line1.id, 100, null, null, null, null, null, 'idem-gen-l1', '00000000-0000-0000-0000-000000180102', 'rep');
  if v_task.status <> 'unclaimed' or v_task.task_quantity <> 100 or v_task.source_location_id <> v_rack_a_id then
    raise exception 'assertion failed: expected an unclaimed 100-unit task sourced from RACK-PICK-A, got status=%/qty=%/source=%', v_task.status, v_task.task_quantity, v_task.source_location_id;
  end if;
  if v_task.item_master_id <> v_line1.item_master_id or v_task.owner_account_id is null or v_task.uom_code <> v_line1.requested_uom_code then
    raise exception 'assertion failed: expected the task to snapshot its item/owner/uom from the outbound order line/header exactly';
  end if;

  v_replay := app.generate_wms_pick_task(v_line1.id, 100, null, null, null, null, null, 'idem-gen-l1', '00000000-0000-0000-0000-000000180102', 'rep');
  if v_replay.id <> v_task.id then
    raise exception 'assertion failed: expected the same-idempotency-key replay to return the identical task';
  end if;

  -- Structural proof generation can never over-allocate a line -- L1''s full 100
  -- units are already allocated to the task above.
  begin
    perform app.generate_wms_pick_task(v_line1.id, 1, null, null, null, null, null, 'idem-gen-l1-overflow', '00000000-0000-0000-0000-000000180102', 'rep');
    raise exception 'assertion failed: expected insufficient_remaining_quantity -- L1''s full 100 units are already allocated';
  exception
    when others then
      if sqlerrm not like 'insufficient_remaining_quantity%' then raise; end if;
  end;

  -- The real reservation exists and reserved the real balance.
  if not exists (
    select 1 from app.inventory_balances where location_id = v_rack_a_id and reserved = 100
  ) then
    raise exception 'assertion failed: expected RACK-PICK-A''s own balance to show reserved=100 after generation';
  end if;
end $$;

\echo '>> app.claim_wms_pick_task (L1): viewer rejected; task_not_found; claim succeeds; idempotent same-claimant re-claim (no version bump); a different rep is rejected task_already_claimed; stale_version on a genuinely fresh task (L11)'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'wmspick1');
  v_task app.wms_pick_tasks;
  v_replay app.wms_pick_tasks;
begin
  select * into v_task from app.wms_pick_tasks where tenant_id = v_tenant1 and idempotency_key = 'idem-gen-l1';

  begin
    perform app.claim_wms_pick_task(v_task.id, v_task.record_version, '00000000-0000-0000-0000-000000180103', 'viewer');
    raise exception 'assertion failed: expected insufficient_authority -- viewer holds OPS:View only';
  exception
    when others then
      if sqlerrm not like 'insufficient_authority%' then raise; end if;
  end;

  begin
    perform app.claim_wms_pick_task(gen_random_uuid(), 1, '00000000-0000-0000-0000-000000180102', 'rep');
    raise exception 'assertion failed: expected task_not_found';
  exception
    when others then
      if sqlerrm not like 'task_not_found%' then raise; end if;
  end;

  v_task := app.claim_wms_pick_task(v_task.id, v_task.record_version, '00000000-0000-0000-0000-000000180102', 'rep');
  if v_task.status <> 'claimed' or v_task.claimed_by_auth_user_id <> '00000000-0000-0000-0000-000000180102' then
    raise exception 'assertion failed: expected the task to be claimed by rep, got status=%/claimed_by=%', v_task.status, v_task.claimed_by_auth_user_id;
  end if;

  v_replay := app.claim_wms_pick_task(v_task.id, v_task.record_version, '00000000-0000-0000-0000-000000180102', 'rep');
  if v_replay.record_version <> v_task.record_version then
    raise exception 'assertion failed: expected a same-claimant re-claim to be a true no-op (no version bump)';
  end if;

  begin
    perform app.claim_wms_pick_task(v_task.id, v_task.record_version, '00000000-0000-0000-0000-000000180108', 'rep2');
    raise exception 'assertion failed: expected task_already_claimed -- rep2 must not be able to claim a task rep already holds';
  exception
    when others then
      if sqlerrm not like 'task_already_claimed%' then raise; end if;
  end;

  declare
    v_order_id uuid := (select id from app.wms_outbound_orders where tenant_id = v_tenant1 and idempotency_key = 'idem-pick-main');
    v_line11 app.wms_outbound_order_lines;
    v_fresh_task app.wms_pick_tasks;
  begin
    select * into v_line11 from app.wms_outbound_order_lines where outbound_order_id = v_order_id and line_number = 11;

    begin
      perform app.generate_wms_pick_task(v_line11.id, 15, null, null, null, null, null, '', '00000000-0000-0000-0000-000000180102', 'rep');
      raise exception 'assertion failed: expected invalid_idempotency_key -- empty key';
    exception
      when others then
        if sqlerrm not like 'invalid_idempotency_key%' then raise; end if;
    end;

    v_fresh_task := app.generate_wms_pick_task(v_line11.id, 15, null, null, null, null, null, 'idem-gen-l11', '00000000-0000-0000-0000-000000180102', 'rep');

    begin
      perform app.claim_wms_pick_task(v_fresh_task.id, v_fresh_task.record_version + 999, '00000000-0000-0000-0000-000000180102', 'rep');
      raise exception 'assertion failed: expected stale_version on a genuinely fresh unclaimed task';
    exception
      when others then
        if sqlerrm not like 'stale_version%' then raise; end if;
    end;
  end;
end $$;

\echo '>> app.confirm_wms_pick_task (L1, single full confirm): not_task_claimant rejected; invalid_quantity; exceeds_remaining_quantity (over-pick hard rejection); location_mismatch (wrong scanned source); posts a real balanced transfer (source RACK-PICK-A decreases, destination STAGE-PICK-1 increases); reserved decreases by exactly the picked amount at the SAME time (design note 4); status becomes picked; idempotent replay does not double-post; a genuinely new confirm on an already-resolved task is rejected task_already_resolved'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'wmspick1');
  v_warehouse_id uuid := (select id from app.warehouses where tenant_id = v_tenant1 and code = 'WH-PICK-1');
  v_rack_a_id uuid := (select id from app.warehouse_locations where tenant_id = v_tenant1 and code = 'RACK-PICK-A');
  v_rack_b_id uuid := (select id from app.warehouse_locations where tenant_id = v_tenant1 and code = 'RACK-PICK-B');
  v_stage1_id uuid := (select id from app.warehouse_locations where tenant_id = v_tenant1 and code = 'STAGE-PICK-1');
  v_account_alpha_id uuid := (select id from app.accounts where tenant_id = v_tenant1 and legal_name = 'WmsPick Customer Alpha');
  v_plain_id uuid := (select id from app.item_masters where tenant_id = v_tenant1 and code = 'SKU-PICK-PLAIN');
  v_wrong_item_id uuid := (select id from app.item_masters where tenant_id = v_tenant1 and code = 'SKU-PICK-LOT');
  v_task app.wms_pick_tasks;
  v_replay app.wms_pick_tasks;
  v_source_balance_before numeric;
  v_source_balance_after numeric;
  v_source_reserved_before numeric;
  v_source_reserved_after numeric;
  v_dest_balance app.inventory_balances;
begin
  select * into v_task from app.wms_pick_tasks where tenant_id = v_tenant1 and idempotency_key = 'idem-gen-l1';

  begin
    perform app.confirm_wms_pick_task(v_task.id, 100, v_rack_a_id, v_task.item_master_id, null, null, v_stage1_id, 'idem-confirm-l1-rep2', v_task.record_version, '00000000-0000-0000-0000-000000180108', 'rep2');
    raise exception 'assertion failed: expected not_task_claimant -- rep2 never claimed this task';
  exception
    when others then
      if sqlerrm not like 'not_task_claimant%' then raise; end if;
  end;

  begin
    perform app.confirm_wms_pick_task(v_task.id, 0, v_rack_a_id, v_task.item_master_id, null, null, v_stage1_id, 'idem-confirm-l1-zero', v_task.record_version, '00000000-0000-0000-0000-000000180102', 'rep');
    raise exception 'assertion failed: expected invalid_quantity -- zero confirm quantity';
  exception
    when others then
      if sqlerrm not like 'invalid_quantity%' then raise; end if;
  end;

  begin
    perform app.confirm_wms_pick_task(v_task.id, 101, v_rack_a_id, v_task.item_master_id, null, null, v_stage1_id, 'idem-confirm-l1-toomuch', v_task.record_version, '00000000-0000-0000-0000-000000180102', 'rep');
    raise exception 'assertion failed: expected exceeds_remaining_quantity -- task only holds 100 units (over-pick hard rejection)';
  exception
    when others then
      if sqlerrm not like 'exceeds_remaining_quantity%' then raise; end if;
  end;

  begin
    perform app.confirm_wms_pick_task(v_task.id, 100, v_rack_b_id, v_task.item_master_id, null, null, v_stage1_id, 'idem-confirm-l1-wrongsrc', v_task.record_version, '00000000-0000-0000-0000-000000180102', 'rep');
    raise exception 'assertion failed: expected location_mismatch -- scanned RACK-PICK-B does not match the task''s own source RACK-PICK-A';
  exception
    when others then
      if sqlerrm not like 'location_mismatch%' then raise; end if;
  end;

  -- Real defect found and fixed by adversarial review: the picker scans the CORRECT
  -- location but physically grabs the WRONG item sitting in the same non-item-dedicated
  -- bin (RACK-PICK-A carries balances for several distinct items in this fixture) --
  -- item_mismatch must be rejected exactly like location/lot/serial (Prompt 236 section
  -- 21 "scans exact location/item/control IDs" / section 23 "block ... wrong
  -- location/item/lot/serial/owner").
  begin
    perform app.confirm_wms_pick_task(v_task.id, 100, v_rack_a_id, v_wrong_item_id, null, null, v_stage1_id, 'idem-confirm-l1-wrongitem', v_task.record_version, '00000000-0000-0000-0000-000000180102', 'rep');
    raise exception 'assertion failed: expected item_mismatch -- scanned item SKU-PICK-LOT does not match the task''s own item SKU-PICK-PLAIN';
  exception
    when others then
      if sqlerrm not like 'item_mismatch%' then raise; end if;
  end;

  select on_hand, reserved into v_source_balance_before, v_source_reserved_before from app.inventory_balances
    where tenant_id = v_tenant1 and warehouse_id = v_warehouse_id and owner_account_id = v_account_alpha_id and item_master_id = v_plain_id
      and location_id = v_rack_a_id and lot_number is null and serial_number is null and status = 'on_hand';

  v_task := app.confirm_wms_pick_task(v_task.id, 100, v_rack_a_id, v_task.item_master_id, null, null, v_stage1_id, 'idem-confirm-l1', v_task.record_version, '00000000-0000-0000-0000-000000180102', 'rep');
  if v_task.status <> 'picked' or v_task.picked_quantity <> 100 or v_task.remaining_quantity <> 0 or v_task.actual_destination_location_id <> v_stage1_id then
    raise exception 'assertion failed: expected task fully picked to STAGE-PICK-1, got status=%/picked=%/remaining=%/actual=%', v_task.status, v_task.picked_quantity, v_task.remaining_quantity, v_task.actual_destination_location_id;
  end if;

  select on_hand, reserved into v_source_balance_after, v_source_reserved_after from app.inventory_balances
    where tenant_id = v_tenant1 and warehouse_id = v_warehouse_id and owner_account_id = v_account_alpha_id and item_master_id = v_plain_id
      and location_id = v_rack_a_id and lot_number is null and serial_number is null and status = 'on_hand';
  if v_source_balance_after <> v_source_balance_before - 100 then
    raise exception 'assertion failed: expected source on_hand to decrease by exactly 100, before=%/after=%', v_source_balance_before, v_source_balance_after;
  end if;
  if v_source_reserved_after <> v_source_reserved_before - 100 then
    raise exception 'assertion failed: expected source reserved to decrease by exactly 100 (design note 4), before=%/after=%', v_source_reserved_before, v_source_reserved_after;
  end if;
  -- The CHECK constraint itself is the real, structural proof reserved+held<=on_hand
  -- held throughout -- if it had ever been violated, the confirm above would have
  -- raised a constraint-violation error instead of succeeding.

  select * into v_dest_balance from app.inventory_balances
    where tenant_id = v_tenant1 and warehouse_id = v_warehouse_id and owner_account_id = v_account_alpha_id and item_master_id = v_plain_id
      and location_id = v_stage1_id and lot_number is null and serial_number is null and status = 'on_hand';
  if v_dest_balance.on_hand <> 100 then
    raise exception 'assertion failed: expected exactly 100 units on_hand at STAGE-PICK-1 after L1 pick, got %', v_dest_balance.on_hand;
  end if;

  -- The reservation itself is now released (design note 5) -- never consumed (no
  -- negative consumption movement -- stock has not left the warehouse).
  if not exists (select 1 from app.inventory_reservations where id = v_task.reservation_id and status = 'released') then
    raise exception 'assertion failed: expected the task''s own reservation to be released once fully picked';
  end if;
  if exists (select 1 from app.inventory_movements where source_type = 'reservation' and source_id = v_task.reservation_id and movement_type = 'consumption') then
    raise exception 'assertion failed: a pick-confirm transfer must never post a consumption movement -- stock has not left the warehouse';
  end if;

  -- Idempotent replay on the exact same idempotency_key does not double-post.
  v_replay := app.confirm_wms_pick_task(v_task.id, 100, v_rack_a_id, v_task.item_master_id, null, null, v_stage1_id, 'idem-confirm-l1', v_task.record_version, '00000000-0000-0000-0000-000000180102', 'rep');
  if v_replay.picked_quantity <> 100 then
    raise exception 'assertion failed: expected the exact-same-key replay to return the task unchanged at picked_quantity=100, got %', v_replay.picked_quantity;
  end if;
  select on_hand into v_source_balance_after from app.inventory_balances
    where tenant_id = v_tenant1 and warehouse_id = v_warehouse_id and owner_account_id = v_account_alpha_id and item_master_id = v_plain_id
      and location_id = v_rack_a_id and lot_number is null and serial_number is null and status = 'on_hand';
  if v_source_balance_after <> v_source_balance_before - 100 then
    raise exception 'assertion failed: expected the idempotent replay to post no additional movement (balance unchanged)';
  end if;

  -- A genuinely new confirm attempt (a new idempotency_key) against an already-fully-
  -- resolved task is a real, distinct rejection.
  begin
    perform app.confirm_wms_pick_task(v_task.id, 1, v_rack_a_id, v_task.item_master_id, null, null, v_stage1_id, 'idem-confirm-l1-genuinely-new', v_task.record_version, '00000000-0000-0000-0000-000000180102', 'rep');
    raise exception 'assertion failed: expected task_already_resolved';
  exception
    when others then
      if sqlerrm not like 'task_already_resolved%' then raise; end if;
  end;
end $$;

\echo '>> L2 partial then full pick: confirm 10 of 30 (status partial), a genuinely new confirm event for another 20 completes the task (status picked), each confirm posts its own real transfer'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'wmspick1');
  v_order_id uuid := (select id from app.wms_outbound_orders where tenant_id = v_tenant1 and idempotency_key = 'idem-pick-main');
  v_rack_a_id uuid := (select id from app.warehouse_locations where tenant_id = v_tenant1 and code = 'RACK-PICK-A');
  v_stage1_id uuid := (select id from app.warehouse_locations where tenant_id = v_tenant1 and code = 'STAGE-PICK-1');
  v_line2 app.wms_outbound_order_lines;
  v_task app.wms_pick_tasks;
begin
  select * into v_line2 from app.wms_outbound_order_lines where outbound_order_id = v_order_id and line_number = 2;
  v_task := app.generate_wms_pick_task(v_line2.id, 30, null, null, null, null, null, 'idem-gen-l2', '00000000-0000-0000-0000-000000180102', 'rep');
  v_task := app.claim_wms_pick_task(v_task.id, v_task.record_version, '00000000-0000-0000-0000-000000180102', 'rep');

  v_task := app.confirm_wms_pick_task(v_task.id, 10, v_rack_a_id, v_task.item_master_id, null, null, v_stage1_id, 'idem-confirm-l2-part1', v_task.record_version, '00000000-0000-0000-0000-000000180102', 'rep');
  if v_task.status <> 'partial' or v_task.picked_quantity <> 10 or v_task.remaining_quantity <> 20 then
    raise exception 'assertion failed: expected L2 partial at picked=10/remaining=20, got status=%/picked=%/remaining=%', v_task.status, v_task.picked_quantity, v_task.remaining_quantity;
  end if;

  v_task := app.confirm_wms_pick_task(v_task.id, 20, v_rack_a_id, v_task.item_master_id, null, null, v_stage1_id, 'idem-confirm-l2-part2', v_task.record_version, '00000000-0000-0000-0000-000000180102', 'rep');
  if v_task.status <> 'picked' or v_task.picked_quantity <> 30 then
    raise exception 'assertion failed: expected L2 fully picked at 30 units, got status=%/picked=%', v_task.status, v_task.picked_quantity;
  end if;

  if (select count(*) from app.wms_pick_task_confirmations where task_id = v_task.id) <> 2 then
    raise exception 'assertion failed: expected exactly 2 distinct confirmation evidence rows for L2''s own task';
  end if;
end $$;

\echo '>> L3 short then remainder picked: record a short of 5 (status partial); a second short beyond remaining_quantity is rejected exceeds_remaining_quantity; recording a short with no reason is rejected invalid_reason; recording a short on an unclaimed/wrong-actor task is rejected as appropriate; the remaining 15 is then picked (status short, since short_quantity>0); the short quantity is released from reserved'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'wmspick1');
  v_warehouse_id uuid := (select id from app.warehouses where tenant_id = v_tenant1 and code = 'WH-PICK-1');
  v_order_id uuid := (select id from app.wms_outbound_orders where tenant_id = v_tenant1 and idempotency_key = 'idem-pick-main');
  v_account_alpha_id uuid := (select id from app.accounts where tenant_id = v_tenant1 and legal_name = 'WmsPick Customer Alpha');
  v_plain_id uuid := (select id from app.item_masters where tenant_id = v_tenant1 and code = 'SKU-PICK-PLAIN');
  v_rack_a_id uuid := (select id from app.warehouse_locations where tenant_id = v_tenant1 and code = 'RACK-PICK-A');
  v_stage1_id uuid := (select id from app.warehouse_locations where tenant_id = v_tenant1 and code = 'STAGE-PICK-1');
  v_line3 app.wms_outbound_order_lines;
  v_task app.wms_pick_tasks;
  v_reserved_before numeric;
  v_reserved_after numeric;
begin
  select * into v_line3 from app.wms_outbound_order_lines where outbound_order_id = v_order_id and line_number = 3;
  v_task := app.generate_wms_pick_task(v_line3.id, 20, null, null, null, null, null, 'idem-gen-l3', '00000000-0000-0000-0000-000000180102', 'rep');

  begin
    perform app.record_wms_pick_task_short(v_task.id, 5, 'shelf empty', 'idem-short-l3-unclaimed', v_task.record_version, '00000000-0000-0000-0000-000000180108', 'rep2');
    raise exception 'assertion failed: expected invalid_transition -- L3''s task is still unclaimed';
  exception
    when others then
      if sqlerrm not like 'invalid_transition%' then raise; end if;
  end;

  v_task := app.claim_wms_pick_task(v_task.id, v_task.record_version, '00000000-0000-0000-0000-000000180102', 'rep');

  begin
    perform app.record_wms_pick_task_short(v_task.id, 5, '', 'idem-short-l3-noreason', v_task.record_version, '00000000-0000-0000-0000-000000180102', 'rep');
    raise exception 'assertion failed: expected invalid_reason -- empty reason';
  exception
    when others then
      if sqlerrm not like 'invalid_reason%' then raise; end if;
  end;

  begin
    perform app.record_wms_pick_task_short(v_task.id, 21, 'too much', 'idem-short-l3-toomuch', v_task.record_version, '00000000-0000-0000-0000-000000180102', 'rep');
    raise exception 'assertion failed: expected exceeds_remaining_quantity -- 21 exceeds the task''s own 20-unit remaining';
  exception
    when others then
      if sqlerrm not like 'exceeds_remaining_quantity%' then raise; end if;
  end;

  begin
    perform app.record_wms_pick_task_short(v_task.id, 5, 'not my task', 'idem-short-l3-wrongactor', v_task.record_version, '00000000-0000-0000-0000-000000180108', 'rep2');
    raise exception 'assertion failed: expected insufficient_authority -- rep2 neither claimed the task nor holds OPS:Override';
  exception
    when others then
      if sqlerrm not like 'insufficient_authority%' then raise; end if;
  end;

  select reserved into v_reserved_before from app.inventory_balances
    where tenant_id = v_tenant1 and warehouse_id = v_warehouse_id and owner_account_id = v_account_alpha_id and item_master_id = v_plain_id
      and location_id = v_rack_a_id and lot_number is null and serial_number is null and status = 'on_hand';

  v_task := app.record_wms_pick_task_short(v_task.id, 5, 'shelf empty', 'idem-short-l3', v_task.record_version, '00000000-0000-0000-0000-000000180102', 'rep');
  if v_task.status <> 'partial' or v_task.short_quantity <> 5 or v_task.remaining_quantity <> 15 then
    raise exception 'assertion failed: expected L3 partial at short=5/remaining=15, got status=%/short=%/remaining=%', v_task.status, v_task.short_quantity, v_task.remaining_quantity;
  end if;

  select reserved into v_reserved_after from app.inventory_balances
    where tenant_id = v_tenant1 and warehouse_id = v_warehouse_id and owner_account_id = v_account_alpha_id and item_master_id = v_plain_id
      and location_id = v_rack_a_id and lot_number is null and serial_number is null and status = 'on_hand';
  if v_reserved_after <> v_reserved_before - 5 then
    raise exception 'assertion failed: expected reserved to decrease by exactly the short quantity (5), before=%/after=%', v_reserved_before, v_reserved_after;
  end if;

  -- Idempotent replay of the exact same short event does not double-release.
  perform app.record_wms_pick_task_short(v_task.id, 5, 'shelf empty', 'idem-short-l3', v_task.record_version, '00000000-0000-0000-0000-000000180102', 'rep');
  select reserved into v_reserved_after from app.inventory_balances
    where tenant_id = v_tenant1 and warehouse_id = v_warehouse_id and owner_account_id = v_account_alpha_id and item_master_id = v_plain_id
      and location_id = v_rack_a_id and lot_number is null and serial_number is null and status = 'on_hand';
  if v_reserved_after <> v_reserved_before - 5 then
    raise exception 'assertion failed: expected the idempotent short replay to release no additional quantity';
  end if;

  v_task := app.confirm_wms_pick_task(v_task.id, 15, v_rack_a_id, v_task.item_master_id, null, null, v_stage1_id, 'idem-confirm-l3-remainder', v_task.record_version, '00000000-0000-0000-0000-000000180102', 'rep');
  if v_task.status <> 'short' or v_task.picked_quantity <> 15 or v_task.short_quantity <> 5 or v_task.remaining_quantity <> 0 then
    raise exception 'assertion failed: expected L3 closed out as short (picked=15/short=5), got status=%/picked=%/short=%/remaining=%', v_task.status, v_task.picked_quantity, v_task.short_quantity, v_task.remaining_quantity;
  end if;

  if not exists (select 1 from app.inventory_reservations where id = v_task.reservation_id and status = 'released') then
    raise exception 'assertion failed: expected L3''s own reservation to be released once fully resolved (picked+short=task_quantity)';
  end if;
end $$;

\echo '>> L7 lot-controlled scan verification: missing_lot / lot_mismatch rejected; correct scan succeeds; L8 serial-controlled scan verification: missing_serial / serial_mismatch rejected; correct scan succeeds'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'wmspick1');
  v_order_id uuid := (select id from app.wms_outbound_orders where tenant_id = v_tenant1 and idempotency_key = 'idem-pick-main');
  v_rack_a_id uuid := (select id from app.warehouse_locations where tenant_id = v_tenant1 and code = 'RACK-PICK-A');
  v_stage1_id uuid := (select id from app.warehouse_locations where tenant_id = v_tenant1 and code = 'STAGE-PICK-1');
  v_line7 app.wms_outbound_order_lines;
  v_line8 app.wms_outbound_order_lines;
  v_task app.wms_pick_tasks;
begin
  select * into v_line7 from app.wms_outbound_order_lines where outbound_order_id = v_order_id and line_number = 7;
  v_task := app.generate_wms_pick_task(v_line7.id, 8, null, null, null, null, null, 'idem-gen-l7', '00000000-0000-0000-0000-000000180102', 'rep');
  if v_task.lot_number <> 'LOT-PICK-A' or not v_task.lot_controlled then
    raise exception 'assertion failed: expected L7''s task to resolve lot LOT-PICK-A (lot_controlled snapshot true), got lot=%/lot_controlled=%', v_task.lot_number, v_task.lot_controlled;
  end if;
  v_task := app.claim_wms_pick_task(v_task.id, v_task.record_version, '00000000-0000-0000-0000-000000180102', 'rep');

  begin
    perform app.confirm_wms_pick_task(v_task.id, 8, v_rack_a_id, v_task.item_master_id, null, null, v_stage1_id, 'idem-confirm-l7-missinglot', v_task.record_version, '00000000-0000-0000-0000-000000180102', 'rep');
    raise exception 'assertion failed: expected missing_lot -- no lot scanned for a lot-controlled task';
  exception
    when others then
      if sqlerrm not like 'missing_lot%' then raise; end if;
  end;

  begin
    perform app.confirm_wms_pick_task(v_task.id, 8, v_rack_a_id, v_task.item_master_id, 'LOT-WRONG', null, v_stage1_id, 'idem-confirm-l7-wronglot', v_task.record_version, '00000000-0000-0000-0000-000000180102', 'rep');
    raise exception 'assertion failed: expected lot_mismatch -- scanned lot does not match the task''s own lot';
  exception
    when others then
      if sqlerrm not like 'lot_mismatch%' then raise; end if;
  end;

  v_task := app.confirm_wms_pick_task(v_task.id, 8, v_rack_a_id, v_task.item_master_id, 'LOT-PICK-A', null, v_stage1_id, 'idem-confirm-l7', v_task.record_version, '00000000-0000-0000-0000-000000180102', 'rep');
  if v_task.status <> 'picked' then
    raise exception 'assertion failed: expected L7 fully picked with the correct lot scan, got status=%', v_task.status;
  end if;

  select * into v_line8 from app.wms_outbound_order_lines where outbound_order_id = v_order_id and line_number = 8;
  v_task := app.generate_wms_pick_task(v_line8.id, 1, null, null, null, null, null, 'idem-gen-l8', '00000000-0000-0000-0000-000000180102', 'rep');
  if v_task.serial_number <> 'SN-PICK-A' or not v_task.serial_controlled then
    raise exception 'assertion failed: expected L8''s task to resolve serial SN-PICK-A (serial_controlled snapshot true), got serial=%/serial_controlled=%', v_task.serial_number, v_task.serial_controlled;
  end if;
  v_task := app.claim_wms_pick_task(v_task.id, v_task.record_version, '00000000-0000-0000-0000-000000180102', 'rep');

  begin
    perform app.confirm_wms_pick_task(v_task.id, 1, v_rack_a_id, v_task.item_master_id, null, null, v_stage1_id, 'idem-confirm-l8-missingserial', v_task.record_version, '00000000-0000-0000-0000-000000180102', 'rep');
    raise exception 'assertion failed: expected missing_serial -- no serial scanned for a serial-controlled task';
  exception
    when others then
      if sqlerrm not like 'missing_serial%' then raise; end if;
  end;

  begin
    perform app.confirm_wms_pick_task(v_task.id, 1, v_rack_a_id, v_task.item_master_id, null, 'SN-WRONG', v_stage1_id, 'idem-confirm-l8-wrongserial', v_task.record_version, '00000000-0000-0000-0000-000000180102', 'rep');
    raise exception 'assertion failed: expected serial_mismatch -- scanned serial does not match the task''s own serial';
  exception
    when others then
      if sqlerrm not like 'serial_mismatch%' then raise; end if;
  end;

  v_task := app.confirm_wms_pick_task(v_task.id, 1, v_rack_a_id, v_task.item_master_id, null, 'SN-PICK-A', v_stage1_id, 'idem-confirm-l8', v_task.record_version, '00000000-0000-0000-0000-000000180102', 'rep');
  if v_task.status <> 'picked' then
    raise exception 'assertion failed: expected L8 fully picked with the correct serial scan, got status=%', v_task.status;
  end if;
end $$;

\echo '>> L15 destination validation: incompatible_location (a rack, not staging); blocked_destination (STAGE-PICK-INACTIVE); destination_mismatch on a second confirm targeting a different location once picking has begun; successful confirm fully occupies STAGE-PICK-CAP (capacity=5) exactly; a fresh 1-unit task from L16''s own line then genuinely overflows STAGE-PICK-CAP (destination_full), and is instead confirmed cleanly at STAGE-PICK-1'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'wmspick1');
  v_order_id uuid := (select id from app.wms_outbound_orders where tenant_id = v_tenant1 and idempotency_key = 'idem-pick-main');
  v_rack_a_id uuid := (select id from app.warehouse_locations where tenant_id = v_tenant1 and code = 'RACK-PICK-A');
  v_rack_notenabled_id uuid := (select id from app.warehouse_locations where tenant_id = v_tenant1 and code = 'RACK-PICK-NOTENABLED');
  v_stage1_id uuid := (select id from app.warehouse_locations where tenant_id = v_tenant1 and code = 'STAGE-PICK-1');
  v_stage_cap_id uuid := (select id from app.warehouse_locations where tenant_id = v_tenant1 and code = 'STAGE-PICK-CAP');
  v_stage_inactive_id uuid := (select id from app.warehouse_locations where tenant_id = v_tenant1 and code = 'STAGE-PICK-INACTIVE');
  v_line15 app.wms_outbound_order_lines;
  v_line16 app.wms_outbound_order_lines;
  v_task app.wms_pick_tasks;
  v_overflow_task app.wms_pick_tasks;
begin
  select * into v_line15 from app.wms_outbound_order_lines where outbound_order_id = v_order_id and line_number = 15;
  v_task := app.generate_wms_pick_task(v_line15.id, 5, null, null, null, null, null, 'idem-gen-l15', '00000000-0000-0000-0000-000000180102', 'rep');
  v_task := app.claim_wms_pick_task(v_task.id, v_task.record_version, '00000000-0000-0000-0000-000000180102', 'rep');

  begin
    perform app.confirm_wms_pick_task(v_task.id, 5, v_rack_a_id, v_task.item_master_id, null, null, v_rack_notenabled_id, 'idem-confirm-l15-notstaging', v_task.record_version, '00000000-0000-0000-0000-000000180102', 'rep');
    raise exception 'assertion failed: expected incompatible_location -- a rack is not a valid pick destination';
  exception
    when others then
      if sqlerrm not like 'incompatible_location%' then raise; end if;
  end;

  begin
    perform app.confirm_wms_pick_task(v_task.id, 5, v_rack_a_id, v_task.item_master_id, null, null, v_stage_inactive_id, 'idem-confirm-l15-inactive', v_task.record_version, '00000000-0000-0000-0000-000000180102', 'rep');
    raise exception 'assertion failed: expected blocked_destination -- STAGE-PICK-INACTIVE is not active';
  exception
    when others then
      if sqlerrm not like 'blocked_destination%' then raise; end if;
  end;

  -- STAGE-PICK-CAP starts empty and has capacity=5 -- a 5-unit confirm exactly fills
  -- it (at, not over, the limit), succeeding.
  v_task := app.confirm_wms_pick_task(v_task.id, 5, v_rack_a_id, v_task.item_master_id, null, null, v_stage_cap_id, 'idem-confirm-l15', v_task.record_version, '00000000-0000-0000-0000-000000180102', 'rep');
  if v_task.status <> 'picked' or v_task.actual_destination_location_id <> v_stage_cap_id then
    raise exception 'assertion failed: expected L15 fully picked to STAGE-PICK-CAP (exactly at capacity), got status=%/actual=%', v_task.status, v_task.actual_destination_location_id;
  end if;

  -- destination_mismatch: a second (already-fully-resolved, but exercised via a fresh
  -- generation below to keep this a genuine new-task exercise of the same guard) task
  -- that has already begun at one destination cannot switch destinations mid-flight.
  select * into v_line16 from app.wms_outbound_order_lines where outbound_order_id = v_order_id and line_number = 16;
  v_overflow_task := app.generate_wms_pick_task(v_line16.id, 2, null, null, null, null, null, 'idem-gen-l16-overflow', '00000000-0000-0000-0000-000000180102', 'rep');
  v_overflow_task := app.claim_wms_pick_task(v_overflow_task.id, v_overflow_task.record_version, '00000000-0000-0000-0000-000000180102', 'rep');

  -- STAGE-PICK-CAP is now exactly full (5/5) -- even a genuinely different, otherwise
  -- eligible task cannot land there (destination_full is race-safe across different
  -- tasks, mirrors app.confirm_wms_putaway_task's own design note).
  begin
    perform app.confirm_wms_pick_task(v_overflow_task.id, 1, v_rack_a_id, v_overflow_task.item_master_id, null, null, v_stage_cap_id, 'idem-confirm-l16-full', v_overflow_task.record_version, '00000000-0000-0000-0000-000000180102', 'rep');
    raise exception 'assertion failed: expected destination_full -- STAGE-PICK-CAP is already exactly at its own 5-unit capacity';
  exception
    when others then
      if sqlerrm not like 'destination_full%' then raise; end if;
  end;

  v_overflow_task := app.confirm_wms_pick_task(v_overflow_task.id, 1, v_rack_a_id, v_overflow_task.item_master_id, null, null, v_stage1_id, 'idem-confirm-l16-1of2', v_overflow_task.record_version, '00000000-0000-0000-0000-000000180102', 'rep');
  if v_overflow_task.status <> 'partial' or v_overflow_task.actual_destination_location_id <> v_stage1_id then
    raise exception 'assertion failed: expected the first 1-unit confirm to land at STAGE-PICK-1 (still partial, 1 of 2 remaining), got status=%/actual=%', v_overflow_task.status, v_overflow_task.actual_destination_location_id;
  end if;

  -- destination_mismatch: this task has now begun at STAGE-PICK-1 -- a later confirm
  -- against a different (even otherwise-valid) destination is rejected.
  begin
    perform app.confirm_wms_pick_task(v_overflow_task.id, 1, v_rack_a_id, v_overflow_task.item_master_id, null, null, v_stage_cap_id, 'idem-confirm-l16-mismatch', v_overflow_task.record_version, '00000000-0000-0000-0000-000000180102', 'rep');
    raise exception 'assertion failed: expected destination_mismatch -- L16''s own task has already begun at STAGE-PICK-1';
  exception
    when others then
      if sqlerrm not like 'destination_mismatch%' then raise; end if;
  end;

  v_overflow_task := app.confirm_wms_pick_task(v_overflow_task.id, 1, v_rack_a_id, v_overflow_task.item_master_id, null, null, v_stage1_id, 'idem-confirm-l16-2of2', v_overflow_task.record_version, '00000000-0000-0000-0000-000000180102', 'rep');
  if v_overflow_task.status <> 'picked' then
    raise exception 'assertion failed: expected L16''s overflow task to fully resolve, got status=%', v_overflow_task.status;
  end if;
end $$;

\echo '>> exception + supervisor reassign/release (a fresh task against L16''s own remaining 3 units): claimant marks exception; wrong-actor rejected; idempotent no-op; supervisor reassigns to rep2 (resumes claimed); rep2 partially picks; supervisor releases back to unclaimed (exception_reason cleared); rep re-claims and finishes'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'wmspick1');
  v_order_id uuid := (select id from app.wms_outbound_orders where tenant_id = v_tenant1 and idempotency_key = 'idem-pick-main');
  v_rack_a_id uuid := (select id from app.warehouse_locations where tenant_id = v_tenant1 and code = 'RACK-PICK-A');
  v_stage1_id uuid := (select id from app.warehouse_locations where tenant_id = v_tenant1 and code = 'STAGE-PICK-1');
  v_line16 app.wms_outbound_order_lines;
  v_task app.wms_pick_tasks;
begin
  select * into v_line16 from app.wms_outbound_order_lines where outbound_order_id = v_order_id and line_number = 16;
  v_task := app.generate_wms_pick_task(v_line16.id, 3, null, null, null, null, null, 'idem-gen-l16-exception', '00000000-0000-0000-0000-000000180102', 'rep');
  v_task := app.claim_wms_pick_task(v_task.id, v_task.record_version, '00000000-0000-0000-0000-000000180102', 'rep');

  begin
    perform app.mark_wms_pick_task_exception(v_task.id, 'shelf damaged', v_task.record_version, '00000000-0000-0000-0000-000000180108', 'rep2');
    raise exception 'assertion failed: expected insufficient_authority -- rep2 neither claimed the task nor holds OPS:Override';
  exception
    when others then
      if sqlerrm not like 'insufficient_authority%' then raise; end if;
  end;

  v_task := app.mark_wms_pick_task_exception(v_task.id, 'shelf damaged', v_task.record_version, '00000000-0000-0000-0000-000000180102', 'rep');
  if v_task.status <> 'exception' or v_task.exception_reason <> 'shelf damaged' then
    raise exception 'assertion failed: expected task to be marked exception, got status=%/reason=%', v_task.status, v_task.exception_reason;
  end if;

  declare
    v_replay app.wms_pick_tasks;
  begin
    v_replay := app.mark_wms_pick_task_exception(v_task.id, 'a different reason', v_task.record_version, '00000000-0000-0000-0000-000000180102', 'rep');
    if v_replay.record_version <> v_task.record_version then
      raise exception 'assertion failed: expected an already-exception task to be a true idempotent no-op';
    end if;
  end;

  begin
    perform app.confirm_wms_pick_task(v_task.id, 1, v_rack_a_id, v_task.item_master_id, null, null, v_stage1_id, 'idem-confirm-l16-underexception', v_task.record_version, '00000000-0000-0000-0000-000000180102', 'rep');
    raise exception 'assertion failed: expected task_exception -- an unresolved exception blocks confirmation';
  exception
    when others then
      if sqlerrm not like 'task_exception%' then raise; end if;
  end;

  begin
    perform app.reassign_wms_pick_task(v_task.id, '00000000-0000-0000-0000-000000180108', 'rep2', 'handoff', v_task.record_version, '00000000-0000-0000-0000-000000180102', 'rep');
    raise exception 'assertion failed: expected insufficient_authority -- reassign requires OPS:Override';
  exception
    when others then
      if sqlerrm not like 'insufficient_authority%' then raise; end if;
  end;

  v_task := app.reassign_wms_pick_task(v_task.id, '00000000-0000-0000-0000-000000180108', 'rep2', 'handoff to rep2', v_task.record_version, '00000000-0000-0000-0000-000000180104', 'supervisor');
  if v_task.status <> 'claimed' or v_task.claimed_by_auth_user_id <> '00000000-0000-0000-0000-000000180108' then
    raise exception 'assertion failed: expected task reassigned to rep2 (resumed as claimed, zero progress), got status=%/claimed_by=%', v_task.status, v_task.claimed_by_auth_user_id;
  end if;

  v_task := app.confirm_wms_pick_task(v_task.id, 1, v_rack_a_id, v_task.item_master_id, null, null, v_stage1_id, 'idem-confirm-l16-rep2', v_task.record_version, '00000000-0000-0000-0000-000000180108', 'rep2');
  if v_task.status <> 'partial' or v_task.picked_quantity <> 1 then
    raise exception 'assertion failed: expected rep2''s own partial pick, got status=%/picked=%', v_task.status, v_task.picked_quantity;
  end if;

  v_task := app.reassign_wms_pick_task(v_task.id, null, null, 'rep2 went home', v_task.record_version, '00000000-0000-0000-0000-000000180104', 'supervisor');
  if v_task.status <> 'unclaimed' or v_task.claimed_by_auth_user_id is not null then
    raise exception 'assertion failed: expected the task released back to unclaimed, got status=%/claimed_by=%', v_task.status, v_task.claimed_by_auth_user_id;
  end if;

  v_task := app.claim_wms_pick_task(v_task.id, v_task.record_version, '00000000-0000-0000-0000-000000180102', 'rep');
  v_task := app.confirm_wms_pick_task(v_task.id, 2, v_rack_a_id, v_task.item_master_id, null, null, v_stage1_id, 'idem-confirm-l16-finish', v_task.record_version, '00000000-0000-0000-0000-000000180102', 'rep');
  if v_task.status <> 'picked' or v_task.picked_quantity <> 3 then
    raise exception 'assertion failed: expected the task to finish fully picked at 3 units, got status=%/picked=%', v_task.status, v_task.picked_quantity;
  end if;
end $$;

\echo '>> app.cancel_wms_pick_task (L4, over-pick line reused for cancel since it holds fresh unallocated stock): viewer/wrong-role rejected via OPS:Edit; a task with any progress cannot be cancelled (has_pick_progress); a genuinely zero-progress task cancels cleanly, releasing its own reservation in full and freeing the line''s own requested_quantity for a fresh generation call'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'wmspick1');
  v_warehouse_id uuid := (select id from app.warehouses where tenant_id = v_tenant1 and code = 'WH-PICK-1');
  v_account_alpha_id uuid := (select id from app.accounts where tenant_id = v_tenant1 and legal_name = 'WmsPick Customer Alpha');
  v_plain_id uuid := (select id from app.item_masters where tenant_id = v_tenant1 and code = 'SKU-PICK-PLAIN');
  v_rack_a_id uuid := (select id from app.warehouse_locations where tenant_id = v_tenant1 and code = 'RACK-PICK-A');
  v_stage1_id uuid := (select id from app.warehouse_locations where tenant_id = v_tenant1 and code = 'STAGE-PICK-1');
  v_order_id uuid := (select id from app.wms_outbound_orders where tenant_id = v_tenant1 and idempotency_key = 'idem-pick-main');
  v_line4 app.wms_outbound_order_lines;
  v_task app.wms_pick_tasks;
  v_task2 app.wms_pick_tasks;
  v_reserved_before numeric;
  v_reserved_after numeric;
begin
  select * into v_line4 from app.wms_outbound_order_lines where outbound_order_id = v_order_id and line_number = 4;
  v_task := app.generate_wms_pick_task(v_line4.id, 10, null, null, null, null, null, 'idem-gen-l4', '00000000-0000-0000-0000-000000180102', 'rep');
  v_task := app.claim_wms_pick_task(v_task.id, v_task.record_version, '00000000-0000-0000-0000-000000180102', 'rep');
  v_task := app.confirm_wms_pick_task(v_task.id, 4, v_rack_a_id, v_task.item_master_id, null, null, v_stage1_id, 'idem-confirm-l4-partial', v_task.record_version, '00000000-0000-0000-0000-000000180102', 'rep');

  begin
    perform app.cancel_wms_pick_task(v_task.id, 'duplicate task', v_task.record_version, '00000000-0000-0000-0000-000000180102', 'rep');
    raise exception 'assertion failed: expected has_pick_progress -- 4 units already picked';
  exception
    when others then
      if sqlerrm not like 'has_pick_progress%' then raise; end if;
  end;

  -- Confirm the remaining 6 units here to close L4 out cleanly (the over-pick hard
  -- rejection itself was already proven above, against L1''s own task).
  v_task := app.confirm_wms_pick_task(v_task.id, 6, v_rack_a_id, v_task.item_master_id, null, null, v_stage1_id, 'idem-confirm-l4-rest', v_task.record_version, '00000000-0000-0000-0000-000000180102', 'rep');
  if v_task.status <> 'picked' then
    raise exception 'assertion failed: expected L4''s own task to finish fully picked';
  end if;

  select reserved into v_reserved_before from app.inventory_balances
    where tenant_id = v_tenant1 and warehouse_id = v_warehouse_id and owner_account_id = v_account_alpha_id and item_master_id = v_plain_id
      and location_id = v_rack_a_id and lot_number is null and serial_number is null and status = 'on_hand';

  -- L12 requests 1000 units, none available anywhere -- a fresh, small, genuinely
  -- zero-progress task generated deliberately for the cancel test (a small slice of
  -- L12's own remaining is fine since L12 itself is never fully allocated in this
  -- fixture).
  declare
    v_line12 app.wms_outbound_order_lines;
  begin
    select * into v_line12 from app.wms_outbound_order_lines where outbound_order_id = v_order_id and line_number = 12;
    v_task2 := app.generate_wms_pick_task(v_line12.id, 7, null, v_rack_a_id, null, null, null, 'idem-gen-l12-cancel', '00000000-0000-0000-0000-000000180102', 'rep');
  end;

  begin
    perform app.cancel_wms_pick_task(v_task2.id, 'test cancel', v_task2.record_version, '00000000-0000-0000-0000-000000180103', 'viewer');
    raise exception 'assertion failed: expected insufficient_authority -- viewer holds OPS:View only';
  exception
    when others then
      if sqlerrm not like 'insufficient_authority%' then raise; end if;
  end;

  v_task2 := app.cancel_wms_pick_task(v_task2.id, 'test cancel', v_task2.record_version, '00000000-0000-0000-0000-000000180102', 'rep');
  if v_task2.status <> 'cancelled' then
    raise exception 'assertion failed: expected the zero-progress task to cancel cleanly, got status=%', v_task2.status;
  end if;
  if not exists (select 1 from app.inventory_reservations where id = v_task2.reservation_id and status = 'released') then
    raise exception 'assertion failed: expected the cancelled task''s own reservation to be released in full';
  end if;

  select reserved into v_reserved_after from app.inventory_balances
    where tenant_id = v_tenant1 and warehouse_id = v_warehouse_id and owner_account_id = v_account_alpha_id and item_master_id = v_plain_id
      and location_id = v_rack_a_id and lot_number is null and serial_number is null and status = 'on_hand';
  if v_reserved_after <> v_reserved_before then
    raise exception 'assertion failed: expected cancel to fully release the temporary +7 reservation back to its pre-generation baseline, before=%/after=%', v_reserved_before, v_reserved_after;
  end if;

  -- Idempotent no-op re-cancel.
  perform app.cancel_wms_pick_task(v_task2.id, 'test cancel again', v_task2.record_version, '00000000-0000-0000-0000-000000180102', 'rep');

  -- Cancelling freed L12's own line for a fresh generation call at the identical
  -- quantity (bug class e's own aggregate correctly excludes the cancelled task).
  perform app.generate_wms_pick_task(
    (select id from app.wms_outbound_order_lines where outbound_order_id = v_order_id and line_number = 12),
    7, null, v_rack_a_id, null, null, null, 'idem-gen-l12-recancel-reuse', '00000000-0000-0000-0000-000000180102', 'rep'
  );
end $$;

\echo '>> app.approve_wms_pick_substitution (L9, success): non-supervisor rejected (OPS:Override); same-item rejected invalid_substitution; wrong-owner/inactive item rejected substitute_item_not_eligible; wrong-UOM item rejected; success releases the original reservation and reserves the substitute, recording one real approval row and re-pointing the task''s own item/source/reservation; the original reservation is genuinely released (not double-released)'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'wmspick1');
  v_warehouse_id uuid := (select id from app.warehouses where tenant_id = v_tenant1 and code = 'WH-PICK-1');
  v_account_alpha_id uuid := (select id from app.accounts where tenant_id = v_tenant1 and legal_name = 'WmsPick Customer Alpha');
  v_account_beta_id uuid := (select id from app.accounts where tenant_id = v_tenant1 and legal_name = 'WmsPick Customer Beta');
  v_order_id uuid := (select id from app.wms_outbound_orders where tenant_id = v_tenant1 and idempotency_key = 'idem-pick-main');
  v_subfrom_id uuid := (select id from app.item_masters where tenant_id = v_tenant1 and code = 'SKU-PICK-SUB-FROM');
  v_subto_id uuid := (select id from app.item_masters where tenant_id = v_tenant1 and code = 'SKU-PICK-SUB-TO');
  v_wrong_uom_id uuid := (select id from app.item_masters where tenant_id = v_tenant1 and code = 'SKU-PICK-SUB-WRONGUOM');
  v_beta_item_id uuid := (select id from app.item_masters where tenant_id = v_tenant1 and code = 'SKU-PICK-BETA');
  v_inactive_item_id uuid;
  v_rack_a_id uuid := (select id from app.warehouse_locations where tenant_id = v_tenant1 and code = 'RACK-PICK-A');
  v_line9 app.wms_outbound_order_lines;
  v_task app.wms_pick_tasks;
  v_original_reservation_id uuid;
  v_approvals_count integer;
begin
  select * into v_line9 from app.wms_outbound_order_lines where outbound_order_id = v_order_id and line_number = 9;
  v_task := app.generate_wms_pick_task(v_line9.id, 10, null, null, null, null, null, 'idem-gen-l9', '00000000-0000-0000-0000-000000180102', 'rep');
  v_original_reservation_id := v_task.reservation_id;

  perform app.create_item_master(v_tenant1, v_account_alpha_id, 'SKU-PICK-SUB-INACTIVE', 'Pick Substitution Inactive', null, 'PCS', false, false, false, '00000000-0000-0000-0000-000000180102', 'rep');
  select id into v_inactive_item_id from app.item_masters where tenant_id = v_tenant1 and code = 'SKU-PICK-SUB-INACTIVE';
  perform app.set_item_master_status(v_inactive_item_id, 'inactive', 'test fixture', (select record_version from app.item_masters where id = v_inactive_item_id), '00000000-0000-0000-0000-000000180102', 'rep');

  begin
    perform app.approve_wms_pick_substitution(v_task.id, v_subto_id, null, null, null, 'supply shortage', 'idem-sub-l9-nonsup', v_task.record_version, '00000000-0000-0000-0000-000000180102', 'rep');
    raise exception 'assertion failed: expected insufficient_authority -- substitution requires OPS:Override';
  exception
    when others then
      if sqlerrm not like 'insufficient_authority%' then raise; end if;
  end;

  begin
    perform app.approve_wms_pick_substitution(v_task.id, v_subfrom_id, null, null, null, 'no-op', 'idem-sub-l9-sameitem', v_task.record_version, '00000000-0000-0000-0000-000000180104', 'supervisor');
    raise exception 'assertion failed: expected invalid_substitution -- substitute must differ from the task''s own current item';
  exception
    when others then
      if sqlerrm not like 'invalid_substitution%' then raise; end if;
  end;

  begin
    perform app.approve_wms_pick_substitution(v_task.id, v_beta_item_id, null, null, null, 'wrong owner', 'idem-sub-l9-wrongowner', v_task.record_version, '00000000-0000-0000-0000-000000180104', 'supervisor');
    raise exception 'assertion failed: expected substitute_item_not_eligible -- SKU-PICK-BETA is owned by a different account';
  exception
    when others then
      if sqlerrm not like 'substitute_item_not_eligible%' then raise; end if;
  end;

  begin
    perform app.approve_wms_pick_substitution(v_task.id, v_inactive_item_id, null, null, null, 'inactive item', 'idem-sub-l9-inactive', v_task.record_version, '00000000-0000-0000-0000-000000180104', 'supervisor');
    raise exception 'assertion failed: expected substitute_item_not_eligible -- the substitute item is inactive';
  exception
    when others then
      if sqlerrm not like 'substitute_item_not_eligible%' then raise; end if;
  end;

  begin
    perform app.approve_wms_pick_substitution(v_task.id, v_wrong_uom_id, null, null, null, 'wrong uom', 'idem-sub-l9-wronguom', v_task.record_version, '00000000-0000-0000-0000-000000180104', 'supervisor');
    raise exception 'assertion failed: expected substitute_item_not_eligible -- base UOM mismatch (KG vs PCS)';
  exception
    when others then
      if sqlerrm not like 'substitute_item_not_eligible%' then raise; end if;
  end;

  begin
    perform app.approve_wms_pick_substitution(v_task.id, v_subto_id, null, null, null, '', 'idem-sub-l9-noreason', v_task.record_version, '00000000-0000-0000-0000-000000180104', 'supervisor');
    raise exception 'assertion failed: expected invalid_reason -- empty reason';
  exception
    when others then
      if sqlerrm not like 'invalid_reason%' then raise; end if;
  end;

  v_task := app.approve_wms_pick_substitution(v_task.id, v_subto_id, null, null, null, 'supply shortage on SUB-FROM', 'idem-sub-l9', v_task.record_version, '00000000-0000-0000-0000-000000180104', 'supervisor');
  if v_task.item_master_id <> v_subto_id or v_task.substituted_from_item_master_id <> v_subfrom_id then
    raise exception 'assertion failed: expected the task to now reference SKU-PICK-SUB-TO with substituted_from=SKU-PICK-SUB-FROM, got item=%/from=%', v_task.item_master_id, v_task.substituted_from_item_master_id;
  end if;
  if v_task.reservation_id = v_original_reservation_id then
    raise exception 'assertion failed: expected a genuinely NEW reservation after substitution';
  end if;

  if not exists (select 1 from app.inventory_reservations where id = v_original_reservation_id and status = 'released') then
    raise exception 'assertion failed: expected the original reservation to be released';
  end if;
  if not exists (select 1 from app.inventory_reservations where id = v_task.reservation_id and status = 'active') then
    raise exception 'assertion failed: expected the new substitute reservation to be active';
  end if;

  select count(*) into v_approvals_count from app.wms_pick_substitution_approvals where task_id = v_task.id;
  if v_approvals_count <> 1 then
    raise exception 'assertion failed: expected exactly 1 real, auditable substitution approval row, got %', v_approvals_count;
  end if;

  -- Idempotent replay on the exact same idempotency_key does not re-substitute.
  perform app.approve_wms_pick_substitution(v_task.id, v_subto_id, null, null, null, 'supply shortage on SUB-FROM', 'idem-sub-l9', v_task.record_version, '00000000-0000-0000-0000-000000180104', 'supervisor');
  select count(*) into v_approvals_count from app.wms_pick_substitution_approvals where task_id = v_task.id;
  if v_approvals_count <> 1 then
    raise exception 'assertion failed: expected the idempotent replay to insert no additional approval row, got %', v_approvals_count;
  end if;

  -- Finish the task to prove the substituted item genuinely picks (source location/
  -- lot/serial/uom were re-pointed correctly).
  v_task := app.claim_wms_pick_task(v_task.id, v_task.record_version, '00000000-0000-0000-0000-000000180102', 'rep');
  v_task := app.confirm_wms_pick_task(v_task.id, 10, v_task.source_location_id, v_task.item_master_id, null, null,
    (select id from app.warehouse_locations where tenant_id = v_tenant1 and code = 'STAGE-PICK-1'),
    'idem-confirm-l9-sub', v_task.record_version, '00000000-0000-0000-0000-000000180102', 'rep');
  if v_task.status <> 'picked' then
    raise exception 'assertion failed: expected the substituted L9 task to pick cleanly to completion, got status=%', v_task.status;
  end if;
end $$;

\echo '>> app.approve_wms_pick_substitution (L10, substitution_not_allowed once progress exists): a task with any picked/short progress may never be substituted'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'wmspick1');
  v_order_id uuid := (select id from app.wms_outbound_orders where tenant_id = v_tenant1 and idempotency_key = 'idem-pick-main');
  v_subfrom_id uuid := (select id from app.item_masters where tenant_id = v_tenant1 and code = 'SKU-PICK-SUB-FROM');
  v_subto_id uuid := (select id from app.item_masters where tenant_id = v_tenant1 and code = 'SKU-PICK-SUB-TO');
  v_rack_a_id uuid := (select id from app.warehouse_locations where tenant_id = v_tenant1 and code = 'RACK-PICK-A');
  v_stage1_id uuid := (select id from app.warehouse_locations where tenant_id = v_tenant1 and code = 'STAGE-PICK-1');
  v_line10 app.wms_outbound_order_lines;
  v_task app.wms_pick_tasks;
begin
  select * into v_line10 from app.wms_outbound_order_lines where outbound_order_id = v_order_id and line_number = 10;
  v_task := app.generate_wms_pick_task(v_line10.id, 5, null, null, null, null, null, 'idem-gen-l10', '00000000-0000-0000-0000-000000180102', 'rep');
  v_task := app.claim_wms_pick_task(v_task.id, v_task.record_version, '00000000-0000-0000-0000-000000180102', 'rep');
  v_task := app.confirm_wms_pick_task(v_task.id, 2, v_rack_a_id, v_task.item_master_id, null, null, v_stage1_id, 'idem-confirm-l10-part', v_task.record_version, '00000000-0000-0000-0000-000000180102', 'rep');

  begin
    perform app.approve_wms_pick_substitution(v_task.id, v_subto_id, null, null, null, 'too late', 'idem-sub-l10', v_task.record_version, '00000000-0000-0000-0000-000000180104', 'supervisor');
    raise exception 'assertion failed: expected substitution_not_allowed -- L10''s own task already has real progress (picked=2)';
  exception
    when others then
      if sqlerrm not like 'substitution_not_allowed%' then raise; end if;
  end;
end $$;

\echo '>> wave batching (L13/L14): app.create_wms_pick_wave groups two independently generated tasks under one real wave_id; app.list_wms_pick_tasks(p_wave_id=...) returns exactly those two; a wave from a DIFFERENT warehouse is rejected wave_not_found when supplied to generate; app.list_wms_pick_waves is bounded and warehouse-scoped'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'wmspick1');
  v_warehouse_id uuid := (select id from app.warehouses where tenant_id = v_tenant1 and code = 'WH-PICK-1');
  v_warehouse2_id uuid := (select id from app.warehouses where tenant_id = v_tenant1 and code = 'WH-PICK-2');
  v_order_id uuid := (select id from app.wms_outbound_orders where tenant_id = v_tenant1 and idempotency_key = 'idem-pick-main');
  v_line13 app.wms_outbound_order_lines;
  v_line14 app.wms_outbound_order_lines;
  v_wave app.wms_pick_waves;
  v_wave_wh2 app.wms_pick_waves;
  v_task_a app.wms_pick_tasks;
  v_task_b app.wms_pick_tasks;
  v_wave_tasks app.wms_pick_tasks[];
begin
  v_wave := app.create_wms_pick_wave(v_tenant1, v_warehouse_id, 'idem-wave-batch', '00000000-0000-0000-0000-000000180102', 'rep');
  v_wave_wh2 := app.create_wms_pick_wave(v_tenant1, v_warehouse2_id, 'idem-wave-wh2', '00000000-0000-0000-0000-000000180102', 'rep');

  select * into v_line13 from app.wms_outbound_order_lines where outbound_order_id = v_order_id and line_number = 13;
  select * into v_line14 from app.wms_outbound_order_lines where outbound_order_id = v_order_id and line_number = 14;

  begin
    perform app.generate_wms_pick_task(v_line13.id, 20, v_wave_wh2.id, null, null, null, null, 'idem-gen-l13-wrongwh', '00000000-0000-0000-0000-000000180102', 'rep');
    raise exception 'assertion failed: expected wave_not_found -- the supplied wave belongs to WH-PICK-2, not WH-PICK-1';
  exception
    when others then
      if sqlerrm not like 'wave_not_found%' then raise; end if;
  end;

  v_task_a := app.generate_wms_pick_task(v_line13.id, 20, v_wave.id, null, null, null, null, 'idem-gen-l13', '00000000-0000-0000-0000-000000180102', 'rep');
  v_task_b := app.generate_wms_pick_task(v_line14.id, 25, v_wave.id, null, null, null, null, 'idem-gen-l14', '00000000-0000-0000-0000-000000180102', 'rep');
  if v_task_a.wave_id <> v_wave.id or v_task_b.wave_id <> v_wave.id then
    raise exception 'assertion failed: expected both L13/L14 tasks to carry the real wave_id';
  end if;

  select array_agg(t) into v_wave_tasks from app.list_wms_pick_tasks(v_tenant1, '00000000-0000-0000-0000-000000180102', null, null, null, v_wave.id, null, null, null, 50) t;
  if array_length(v_wave_tasks, 1) <> 2 then
    raise exception 'assertion failed: expected exactly 2 tasks grouped under the wave, got %', array_length(v_wave_tasks, 1);
  end if;

  if (select count(*) from app.list_wms_pick_waves(v_tenant1, '00000000-0000-0000-0000-000000180102', v_warehouse_id, 50)) < 1 then
    raise exception 'assertion failed: expected at least one wave listed for WH-PICK-1';
  end if;
  if exists (select 1 from app.list_wms_pick_waves(v_tenant1, '00000000-0000-0000-0000-000000180102', v_warehouse_id, 50) w where w.id = v_wave_wh2.id) then
    raise exception 'assertion failed: expected the WH-PICK-2 wave to be excluded from a WH-PICK-1-filtered list';
  end if;
end $$;

\echo '>> FIFO/FEFO allocation candidate selection composes directly against ATW-016''s own app.list_allocation_candidates (a dedicated expiry-controlled item, published fefo policy): two active lots (LOT-PICKFEFO-LATER registered first with a later expiry, LOT-PICKFEFO-NEARER registered second with a nearer expiry) plus one held lot and one truly-expired-but-active-status lot; auto-select generation correctly resolves the nearer-expiry lot, structurally skipping the held/expired ones'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'wmspick1');
  v_warehouse_id uuid := (select id from app.warehouses where tenant_id = v_tenant1 and code = 'WH-PICK-1');
  v_rack_a_id uuid := (select id from app.warehouse_locations where tenant_id = v_tenant1 and code = 'RACK-PICK-A');
  v_account_alpha_id uuid := (select id from app.accounts where tenant_id = v_tenant1 and legal_name = 'WmsPick Customer Alpha');
  v_fefo_item_id uuid;
  v_policy app.item_control_policy_versions;
  v_lot_later app.lot_identities;
  v_lot_nearer app.lot_identities;
  v_lot_held app.lot_identities;
  v_lot_expired app.lot_identities;
  v_order app.wms_outbound_orders;
  v_line app.wms_outbound_order_lines;
  v_task app.wms_pick_tasks;
begin
  perform app.create_item_master(v_tenant1, v_account_alpha_id, 'SKU-PICK-FEFO', 'Pick FEFO Widget', null, 'PCS', true, false, true, '00000000-0000-0000-0000-000000180102', 'rep');
  select id into v_fefo_item_id from app.item_masters where tenant_id = v_tenant1 and code = 'SKU-PICK-FEFO';

  v_policy := app.create_item_control_policy_version_draft(v_fefo_item_id, 'fefo', false, 30, null, '00000000-0000-0000-0000-000000180102', 'rep');
  perform app.publish_item_control_policy_version(v_policy.id, v_policy.record_version, null, '00000000-0000-0000-0000-000000180104', 'supervisor');

  v_lot_later := app.register_lot_identity(v_fefo_item_id, 'LOT-PICKFEFO-LATER', current_date - 5, current_date + 200, 'receipt', null, null, '00000000-0000-0000-0000-000000180102', 'rep');
  v_lot_nearer := app.register_lot_identity(v_fefo_item_id, 'LOT-PICKFEFO-NEARER', current_date - 5, current_date + 5, 'receipt', null, null, '00000000-0000-0000-0000-000000180102', 'rep');
  v_lot_held := app.register_lot_identity(v_fefo_item_id, 'LOT-PICKFEFO-HELD', current_date - 5, current_date + 1, 'receipt', null, null, '00000000-0000-0000-0000-000000180102', 'rep');
  v_lot_expired := app.register_lot_identity(v_fefo_item_id, 'LOT-PICKFEFO-EXPIRED', current_date - 400, current_date - 1, 'receipt', null, null, '00000000-0000-0000-0000-000000180102', 'rep');
  perform app.set_lot_identity_status(v_lot_held.id, 'held', 'quality hold fixture', v_lot_held.record_version, '00000000-0000-0000-0000-000000180104', 'supervisor');

  perform app.post_inventory_movement(v_tenant1, v_warehouse_id, 'opening_balance', 'opening_balance', null, 'idem-pick-fefo-later', 'opening balance fixture',
    jsonb_build_array(jsonb_build_object('owner_account_id', v_account_alpha_id, 'item_master_id', v_fefo_item_id, 'location_id', v_rack_a_id, 'uom_code', 'PCS', 'signed_quantity', 10, 'lot_number', 'LOT-PICKFEFO-LATER', 'status', 'on_hand')),
    '00000000-0000-0000-0000-000000180102', 'rep');
  perform app.post_inventory_movement(v_tenant1, v_warehouse_id, 'opening_balance', 'opening_balance', null, 'idem-pick-fefo-nearer', 'opening balance fixture',
    jsonb_build_array(jsonb_build_object('owner_account_id', v_account_alpha_id, 'item_master_id', v_fefo_item_id, 'location_id', v_rack_a_id, 'uom_code', 'PCS', 'signed_quantity', 10, 'lot_number', 'LOT-PICKFEFO-NEARER', 'status', 'on_hand')),
    '00000000-0000-0000-0000-000000180102', 'rep');
  perform app.post_inventory_movement(v_tenant1, v_warehouse_id, 'opening_balance', 'opening_balance', null, 'idem-pick-fefo-held', 'opening balance fixture',
    jsonb_build_array(jsonb_build_object('owner_account_id', v_account_alpha_id, 'item_master_id', v_fefo_item_id, 'location_id', v_rack_a_id, 'uom_code', 'PCS', 'signed_quantity', 10, 'lot_number', 'LOT-PICKFEFO-HELD', 'status', 'on_hand')),
    '00000000-0000-0000-0000-000000180102', 'rep');
  perform app.post_inventory_movement(v_tenant1, v_warehouse_id, 'opening_balance', 'opening_balance', null, 'idem-pick-fefo-expired', 'opening balance fixture',
    jsonb_build_array(jsonb_build_object('owner_account_id', v_account_alpha_id, 'item_master_id', v_fefo_item_id, 'location_id', v_rack_a_id, 'uom_code', 'PCS', 'signed_quantity', 10, 'lot_number', 'LOT-PICKFEFO-EXPIRED', 'status', 'on_hand')),
    '00000000-0000-0000-0000-000000180102', 'rep');

  -- Real decision support -- verify app.list_allocation_candidates itself excludes
  -- held/expired (composed directly, never re-queried a second way).
  if (select count(*) from app.list_allocation_candidates(v_tenant1, v_warehouse_id, v_fefo_item_id, v_account_alpha_id, '00000000-0000-0000-0000-000000180102', null, 50)) <> 2 then
    raise exception 'assertion failed: expected exactly 2 eligible FEFO candidates (LATER, NEARER)';
  end if;

  v_order := app.create_manual_wms_outbound_order(v_tenant1, v_warehouse_id, v_account_alpha_id, 'fefo fixture', 'idem-pick-fefo-order', null, '00000000-0000-0000-0000-000000180102', 'rep');
  v_line := app.add_wms_outbound_order_line(v_order.id, v_fefo_item_id, 'PCS', 10, 'fefo line', '00000000-0000-0000-0000-000000180102', 'rep');
  v_order := app.confirm_wms_outbound_order(v_order.id, v_order.record_version, '00000000-0000-0000-0000-000000180102', 'rep');

  v_task := app.generate_wms_pick_task(v_line.id, 10, null, null, null, null, null, 'idem-gen-fefo', '00000000-0000-0000-0000-000000180102', 'rep');
  if v_task.lot_number <> 'LOT-PICKFEFO-NEARER' then
    raise exception 'assertion failed: expected auto-select to resolve the nearer-expiry active lot (fefo policy), got %', v_task.lot_number;
  end if;
end $$;

\echo '>> REAL two-process concurrent double-allocation race (Prompt 236''s own headline acceptance criterion, "concurrent orders cannot double-allocate stock"): L6''s own line requests exactly 10 units; SKU-PICK-RACE has 10 units at RACK-PICK-A AND a SEPARATE 10 units at RACK-PICK-B (two DIFFERENT balance rows -- deliberately proving the LINE-row lock, design note 3, not merely app.reserve_inventory''s own narrower per-balance lock, ATW-015). Two genuinely independent psql client processes each attempt to generate a full 10-unit pick task against the SAME line, targeting the two DIFFERENT locations, launched via scripts/db-tests/wms-picking-concurrency-helper.sh. Exactly one must succeed; the other must be rejected insufficient_remaining_quantity; the line''s own total allocated quantity must never exceed 10'
select l.id as race_line6_id
from app.wms_outbound_order_lines l
join app.wms_outbound_orders o on o.id = l.outbound_order_id
join app.tenants t on t.id = o.tenant_id
where t.slug = 'wmspick1' and o.idempotency_key = 'idem-pick-main' and l.line_number = 6
\gset
select id as race_rack_a_id from app.warehouse_locations where tenant_id = (select id from app.tenants where slug = 'wmspick1') and code = 'RACK-PICK-A' \gset
select id as race_rack_b_id from app.warehouse_locations where tenant_id = (select id from app.tenants where slug = 'wmspick1') and code = 'RACK-PICK-B' \gset
select current_database() as pg_test_db \gset
-- ISS-2026-023 fix (CG-S10-ATW-027): race output paths are suffixed with this psql
-- session's own real backend PID so two concurrent `db:test` invocations on the same
-- machine never clobber each other's race-process output files (each invocation's own
-- top-level session has a distinct, real OS/Postgres-assigned PID; captured once here,
-- reused by every race block below via psql's own :variable interpolation, which applies
-- inside \setenv values, do $$ ... $$ bodies, and plain SQL text alike).
select pg_backend_pid()::text as race_bpid \gset

\set race_sql_a 'select app.generate_wms_pick_task(''' :race_line6_id ''', 10, null, ''' :race_rack_a_id ''', null, null, null, ''idem-gen-l6-race-a'', ''00000000-0000-0000-0000-000000180102'', ''rep'');'
\set race_sql_b 'select app.generate_wms_pick_task(''' :race_line6_id ''', 10, null, ''' :race_rack_b_id ''', null, null, null, ''idem-gen-l6-race-b'', ''00000000-0000-0000-0000-000000180108'', ''rep2'');'

\setenv PG_TEST_DB :pg_test_db
\setenv RACE_SQL_A :race_sql_a
\setenv RACE_SQL_B :race_sql_b
\setenv RACE_OUT_A /tmp/cargogrid-wms-pick-race-l6-a-:race_bpid.out
\setenv RACE_OUT_B /tmp/cargogrid-wms-pick-race-l6-b-:race_bpid.out

\! bash scripts/db-tests/wms-picking-concurrency-helper.sh

do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'wmspick1');
  v_line6_id uuid;
  v_task_count integer;
  v_total_allocated numeric;
  v_reserved_a numeric;
  v_reserved_b numeric;
begin
  select l.id into v_line6_id
    from app.wms_outbound_order_lines l join app.wms_outbound_orders o on o.id = l.outbound_order_id
    where o.tenant_id = v_tenant1 and o.idempotency_key = 'idem-pick-main' and l.line_number = 6;

  select count(*) into v_task_count from app.wms_pick_tasks where outbound_order_line_id = v_line6_id and status <> 'cancelled';
  if v_task_count <> 1 then
    raise exception 'assertion failed: expected exactly ONE real pick task to have won the concurrent race for L6, got % -- see the RACE_OUT_A/RACE_OUT_B process output captured above', v_task_count;
  end if;

  select coalesce(sum(task_quantity - short_quantity), 0) into v_total_allocated from app.wms_pick_tasks where outbound_order_line_id = v_line6_id and status <> 'cancelled';
  if v_total_allocated <> 10 then
    raise exception 'assertion failed: expected exactly 10 units allocated to L6 (never 20 -- the double-allocation this whole proof exists to rule out), got %', v_total_allocated;
  end if;

  -- The loser''s own balance row was never touched -- reserved stayed at exactly 0 on
  -- whichever of RACK-PICK-A/B did not win.
  select reserved into v_reserved_a from app.inventory_balances
    where tenant_id = v_tenant1 and item_master_id = (select id from app.item_masters where tenant_id = v_tenant1 and code = 'SKU-PICK-RACE')
      and location_id = (select id from app.warehouse_locations where tenant_id = v_tenant1 and code = 'RACK-PICK-A') and lot_number is null and serial_number is null and status = 'on_hand';
  select reserved into v_reserved_b from app.inventory_balances
    where tenant_id = v_tenant1 and item_master_id = (select id from app.item_masters where tenant_id = v_tenant1 and code = 'SKU-PICK-RACE')
      and location_id = (select id from app.warehouse_locations where tenant_id = v_tenant1 and code = 'RACK-PICK-B') and lot_number is null and serial_number is null and status = 'on_hand';
  if coalesce(v_reserved_a, 0) + coalesce(v_reserved_b, 0) <> 10 then
    raise exception 'assertion failed: expected exactly 10 total reserved across RACK-PICK-A/B combined (never both reserving 10 each), got a=%/b=%', v_reserved_a, v_reserved_b;
  end if;
  if coalesce(v_reserved_a, 0) <> 0 and coalesce(v_reserved_b, 0) <> 0 then
    raise exception 'assertion failed: expected exactly ONE of RACK-PICK-A/B to hold the real 10-unit reservation, never both';
  end if;

  raise notice 'concurrent double-allocation race proof: exactly 1 task / 10 units allocated (reserved_a=%, reserved_b=%) -- the line-row lock (design note 3) correctly serialized two real, independent psql processes', v_reserved_a, v_reserved_b;
end $$;

\echo '>> REAL two-process regression proof (adversarial-review finding): a caller-supplied idempotency_key reused across two genuinely DIFFERENT operations (different outbound_order_lines, different balance dimensions, no shared FOR UPDATE lock to serialize them) must never surface a raw, uncaught duplicate-key error from app.reserve_inventory -- the loser must fail cleanly with idempotency_key_conflict. Two dedicated items/lines/balances (no contention with any other fixture data) are generated against concurrently, sharing one idempotency_key.'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'wmspick1');
  v_warehouse_id uuid := (select id from app.warehouses where tenant_id = v_tenant1 and code = 'WH-PICK-1');
  v_rack_a_id uuid := (select id from app.warehouse_locations where tenant_id = v_tenant1 and code = 'RACK-PICK-A');
  v_rack_b_id uuid := (select id from app.warehouse_locations where tenant_id = v_tenant1 and code = 'RACK-PICK-B');
  v_account_alpha_id uuid := (select id from app.accounts where tenant_id = v_tenant1 and legal_name = 'WmsPick Customer Alpha');
  v_item_x app.item_masters;
  v_item_y app.item_masters;
  v_order_x app.wms_outbound_orders;
  v_order_y app.wms_outbound_orders;
  v_line_x app.wms_outbound_order_lines;
  v_line_y app.wms_outbound_order_lines;
begin
  v_item_x := app.create_item_master(v_tenant1, v_account_alpha_id, 'SKU-PICK-KEYRACE-X', 'Pick Idempotency Key Race Item X', null, 'PCS', false, false, false, '00000000-0000-0000-0000-000000180102', 'rep');
  v_item_y := app.create_item_master(v_tenant1, v_account_alpha_id, 'SKU-PICK-KEYRACE-Y', 'Pick Idempotency Key Race Item Y', null, 'PCS', false, false, false, '00000000-0000-0000-0000-000000180102', 'rep');

  perform app.post_inventory_movement(
    v_tenant1, v_warehouse_id, 'opening_balance', 'manual', null, 'idem-pick-keyrace-open-x', 'keyrace opening x',
    jsonb_build_array(jsonb_build_object('owner_account_id', v_account_alpha_id, 'item_master_id', v_item_x.id, 'location_id', v_rack_a_id, 'uom_code', 'PCS', 'signed_quantity', 5, 'status', 'on_hand')),
    '00000000-0000-0000-0000-000000180102', 'rep'
  );
  perform app.post_inventory_movement(
    v_tenant1, v_warehouse_id, 'opening_balance', 'manual', null, 'idem-pick-keyrace-open-y', 'keyrace opening y',
    jsonb_build_array(jsonb_build_object('owner_account_id', v_account_alpha_id, 'item_master_id', v_item_y.id, 'location_id', v_rack_b_id, 'uom_code', 'PCS', 'signed_quantity', 5, 'status', 'on_hand')),
    '00000000-0000-0000-0000-000000180102', 'rep'
  );

  v_order_x := app.create_manual_wms_outbound_order(v_tenant1, v_warehouse_id, v_account_alpha_id, 'keyrace order x', 'idem-pick-keyrace-order-x', null, '00000000-0000-0000-0000-000000180102', 'rep');
  v_line_x := app.add_wms_outbound_order_line(v_order_x.id, v_item_x.id, 'PCS', 5, null, '00000000-0000-0000-0000-000000180102', 'rep');
  perform app.confirm_wms_outbound_order(v_order_x.id, v_order_x.record_version, '00000000-0000-0000-0000-000000180102', 'rep');

  v_order_y := app.create_manual_wms_outbound_order(v_tenant1, v_warehouse_id, v_account_alpha_id, 'keyrace order y', 'idem-pick-keyrace-order-y', null, '00000000-0000-0000-0000-000000180102', 'rep');
  v_line_y := app.add_wms_outbound_order_line(v_order_y.id, v_item_y.id, 'PCS', 5, null, '00000000-0000-0000-0000-000000180102', 'rep');
  perform app.confirm_wms_outbound_order(v_order_y.id, v_order_y.record_version, '00000000-0000-0000-0000-000000180102', 'rep');
end $$;

select l.id as keyrace_line_x_id from app.wms_outbound_order_lines l join app.item_masters im on im.id = l.item_master_id where im.code = 'SKU-PICK-KEYRACE-X' \gset
select l.id as keyrace_line_y_id from app.wms_outbound_order_lines l join app.item_masters im on im.id = l.item_master_id where im.code = 'SKU-PICK-KEYRACE-Y' \gset
select current_database() as pg_test_db \gset

\set race_sql_a 'select app.generate_wms_pick_task(''' :keyrace_line_x_id ''', 5, null, null, null, null, null, ''idem-gen-keyrace-samekey'', ''00000000-0000-0000-0000-000000180102'', ''rep'');'
\set race_sql_b 'select app.generate_wms_pick_task(''' :keyrace_line_y_id ''', 5, null, null, null, null, null, ''idem-gen-keyrace-samekey'', ''00000000-0000-0000-0000-000000180102'', ''rep'');'

\set race_out_keyrace_a /tmp/cargogrid-wms-pick-race-keyrace-a-:race_bpid.out
\set race_out_keyrace_b /tmp/cargogrid-wms-pick-race-keyrace-b-:race_bpid.out
\setenv PG_TEST_DB :pg_test_db
\setenv RACE_SQL_A :race_sql_a
\setenv RACE_SQL_B :race_sql_b
\setenv RACE_OUT_A :race_out_keyrace_a
\setenv RACE_OUT_B :race_out_keyrace_b

\! bash scripts/db-tests/wms-picking-concurrency-helper.sh

-- psql does not interpolate :variables inside a do $$ ... $$ body (confirmed empirically
-- during the ISS-2026-023 fix, CG-S10-ATW-027 -- the same limitation the L5 block's own
-- comment below already documented). Smuggle the captured content into the upcoming do
-- block via a session-level GUC instead, read back with current_setting().
--
-- RGL-BLK-005 fix: this used to smuggle the two PID-suffixed PATHS and read them with
-- pg_read_file() inside the do block -- but pg_read_file() reads the *server's*
-- filesystem, while the helper above writes its race-output files on the *client's*.
-- Identical locally (same host), genuinely different in CI (Postgres in its own Docker
-- service container). \set's backtick form runs client-side, so it is captured here,
-- before the do block, and the already-established GUC bridge now carries the CONTENT
-- rather than the path.
\set loser_out `cat "$RACE_OUT_A" "$RACE_OUT_B"`
select set_config('cargogrid.loser_out', :'loser_out', false);

do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'wmspick1');
  v_line_x_id uuid := (select l.id from app.wms_outbound_order_lines l join app.item_masters im on im.id = l.item_master_id where im.code = 'SKU-PICK-KEYRACE-X');
  v_line_y_id uuid := (select l.id from app.wms_outbound_order_lines l join app.item_masters im on im.id = l.item_master_id where im.code = 'SKU-PICK-KEYRACE-Y');
  v_task_count_x integer;
  v_task_count_y integer;
  v_winner_count integer;
  v_loser_out text;
begin
  select count(*) into v_task_count_x from app.wms_pick_tasks where outbound_order_line_id = v_line_x_id and status <> 'cancelled';
  select count(*) into v_task_count_y from app.wms_pick_tasks where outbound_order_line_id = v_line_y_id and status <> 'cancelled';
  v_winner_count := v_task_count_x + v_task_count_y;

  -- Exactly one of the two genuinely different operations wins the shared idempotency
  -- key; the other is rejected, never both silently succeed and never does either process
  -- crash with a raw, unclassified error.
  if v_winner_count <> 1 then
    raise exception 'assertion failed: expected exactly ONE of the two different-line requests to win the shared idempotency key, got % (x=%/y=%) -- see the RACE_OUT_A/RACE_OUT_B process output captured above', v_winner_count, v_task_count_x, v_task_count_y;
  end if;

  -- The loser's own process output must carry the clean, classified error -- never the
  -- raw, uncaught Postgres constraint-violation message this migration used to leak.
  -- Content read back via current_setting(), not psql :interpolation (does not reach
  -- inside a dollar-quoted do body -- see the set_config() call immediately before this
  -- do block, which now carries the captured content, not a path -- RGL-BLK-005 fix).
  v_loser_out := current_setting('cargogrid.loser_out');
  if v_loser_out not like '%idempotency_key_conflict%' then
    raise exception 'assertion failed: expected the losing process''s own output to carry a clean idempotency_key_conflict error, got: %', v_loser_out;
  end if;
  if v_loser_out like '%duplicate key value violates unique constraint%' then
    raise exception 'assertion failed: the losing process leaked a raw, uncaught Postgres constraint-violation message instead of a clean, classified error: %', v_loser_out;
  end if;

  raise notice 'idempotency-key-reuse-across-different-operations race proof: exactly 1 of 2 different-line requests won (x=%/y=%), the loser failed cleanly with idempotency_key_conflict, never a raw uncaught error', v_task_count_x, v_task_count_y;
end $$;

\echo '>> ATW-030 DETERMINISTIC regression proof (no race window required): one idempotency key reused across two genuinely DIFFERENT outbound order lines must raise idempotency_key_conflict, and the SAME key against the SAME line must still replay identically. This is the real defect ISS-2026-024 previously mis-recorded as a timing flake: app.generate_wms_pick_task carried no content-mismatch check at all, so whenever the second request simply arrived AFTER the first committed -- the ordinary, non-racing case -- it silently received the FIRST line''s own task, a different item and potentially a different customer, with no error whatsoever. The two-process proof above only ever exercised the unique-index collision path, which is why the defect survived every prior checkpoint.'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'wmspick1');
  v_warehouse_id uuid := (select id from app.warehouses where tenant_id = v_tenant1 and code = 'WH-PICK-1');
  v_rack_a_id uuid := (select id from app.warehouse_locations where tenant_id = v_tenant1 and code = 'RACK-PICK-A');
  v_rack_b_id uuid := (select id from app.warehouse_locations where tenant_id = v_tenant1 and code = 'RACK-PICK-B');
  v_account_alpha_id uuid := (select id from app.accounts where tenant_id = v_tenant1 and legal_name = 'WmsPick Customer Alpha');
  v_item_p app.item_masters;
  v_item_q app.item_masters;
  v_order_p app.wms_outbound_orders;
  v_order_q app.wms_outbound_orders;
  v_line_p app.wms_outbound_order_lines;
  v_line_q app.wms_outbound_order_lines;
  v_first app.wms_pick_tasks;
  v_replay app.wms_pick_tasks;
  v_conflict_raised boolean := false;
  v_q_task_count integer;
begin
  -- Two fully independent targets: different items, different orders, different lines,
  -- different source racks -- nothing about them contends, so nothing but the shared
  -- idempotency key can relate the two requests.
  v_item_p := app.create_item_master(v_tenant1, v_account_alpha_id, 'SKU-PICK-ATW030-P', 'ATW-030 Deterministic Target P', null, 'PCS', false, false, false, '00000000-0000-0000-0000-000000180102', 'rep');
  v_item_q := app.create_item_master(v_tenant1, v_account_alpha_id, 'SKU-PICK-ATW030-Q', 'ATW-030 Deterministic Target Q', null, 'PCS', false, false, false, '00000000-0000-0000-0000-000000180102', 'rep');

  perform app.post_inventory_movement(
    v_tenant1, v_warehouse_id, 'opening_balance', 'manual', null, 'idem-atw030-open-p', 'atw030 opening p',
    jsonb_build_array(jsonb_build_object('owner_account_id', v_account_alpha_id, 'item_master_id', v_item_p.id, 'location_id', v_rack_a_id, 'uom_code', 'PCS', 'signed_quantity', 4, 'status', 'on_hand')),
    '00000000-0000-0000-0000-000000180102', 'rep'
  );
  perform app.post_inventory_movement(
    v_tenant1, v_warehouse_id, 'opening_balance', 'manual', null, 'idem-atw030-open-q', 'atw030 opening q',
    jsonb_build_array(jsonb_build_object('owner_account_id', v_account_alpha_id, 'item_master_id', v_item_q.id, 'location_id', v_rack_b_id, 'uom_code', 'PCS', 'signed_quantity', 4, 'status', 'on_hand')),
    '00000000-0000-0000-0000-000000180102', 'rep'
  );

  v_order_p := app.create_manual_wms_outbound_order(v_tenant1, v_warehouse_id, v_account_alpha_id, 'atw030 order p', 'idem-atw030-order-p', null, '00000000-0000-0000-0000-000000180102', 'rep');
  v_line_p := app.add_wms_outbound_order_line(v_order_p.id, v_item_p.id, 'PCS', 4, null, '00000000-0000-0000-0000-000000180102', 'rep');
  perform app.confirm_wms_outbound_order(v_order_p.id, v_order_p.record_version, '00000000-0000-0000-0000-000000180102', 'rep');

  v_order_q := app.create_manual_wms_outbound_order(v_tenant1, v_warehouse_id, v_account_alpha_id, 'atw030 order q', 'idem-atw030-order-q', null, '00000000-0000-0000-0000-000000180102', 'rep');
  v_line_q := app.add_wms_outbound_order_line(v_order_q.id, v_item_q.id, 'PCS', 4, null, '00000000-0000-0000-0000-000000180102', 'rep');
  perform app.confirm_wms_outbound_order(v_order_q.id, v_order_q.record_version, '00000000-0000-0000-0000-000000180102', 'rep');

  -- 1. The first, legitimate request claims the key for line P.
  v_first := app.generate_wms_pick_task(v_line_p.id, 4, null, null, null, null, null, 'idem-atw030-shared-key', '00000000-0000-0000-0000-000000180102', 'rep');
  if v_first.outbound_order_line_id <> v_line_p.id then
    raise exception 'assertion failed: the first request must produce a task for its own line P, got %', v_first.outbound_order_line_id;
  end if;

  -- 2. A genuine retry -- same key, SAME line -- must still replay identically. The
  --    repair must not break real idempotency, only cross-target misattribution.
  v_replay := app.generate_wms_pick_task(v_line_p.id, 4, null, null, null, null, null, 'idem-atw030-shared-key', '00000000-0000-0000-0000-000000180102', 'rep');
  if v_replay.id <> v_first.id then
    raise exception 'assertion failed: a same-key/same-target retry must replay the identical task (% expected, got %)', v_first.id, v_replay.id;
  end if;

  -- 3. The defect itself: same key, DIFFERENT line, no race, no concurrency. This must
  --    raise, never silently hand back line P''s own task.
  begin
    perform app.generate_wms_pick_task(v_line_q.id, 4, null, null, null, null, null, 'idem-atw030-shared-key', '00000000-0000-0000-0000-000000180102', 'rep');
  exception when unique_violation then
    if sqlerrm not like '%idempotency_key_conflict%' then
      raise exception 'assertion failed: expected a classified idempotency_key_conflict, got: %', sqlerrm;
    end if;
    v_conflict_raised := true;
  end;

  if not v_conflict_raised then
    raise exception 'assertion failed: reusing one idempotency key across two DIFFERENT outbound order lines silently succeeded -- line Q''s request was misattributed to line P''s task instead of being rejected';
  end if;

  -- 4. And the rejected request left no trace: line Q has no task, so the caller is never
  --    left believing work was allocated against it.
  select count(*) into v_q_task_count from app.wms_pick_tasks where outbound_order_line_id = v_line_q.id and status <> 'cancelled';
  if v_q_task_count <> 0 then
    raise exception 'assertion failed: the rejected cross-target request must leave line Q with zero pick tasks, got %', v_q_task_count;
  end if;

  raise notice 'ATW-030 deterministic proof: same-key/same-target replays identically; same-key/different-target raises idempotency_key_conflict and allocates nothing -- no race window required in either direction';
end $$;

\echo '>> REAL two-process concurrent claim race (L5): two genuinely independent psql client processes (rep and rep2) both attempt to claim the SAME real unclaimed task at (as close to) the same wall-clock time -- exactly one must win; the other must be rejected task_already_claimed, never both'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'wmspick1');
  v_order_id uuid := (select id from app.wms_outbound_orders where tenant_id = v_tenant1 and idempotency_key = 'idem-pick-main');
  v_line5 app.wms_outbound_order_lines;
  v_task app.wms_pick_tasks;
begin
  select * into v_line5 from app.wms_outbound_order_lines where outbound_order_id = v_order_id and line_number = 5;
  v_task := app.generate_wms_pick_task(v_line5.id, 10, null, null, null, null, null, 'idem-gen-l5', '00000000-0000-0000-0000-000000180102', 'rep');
end $$;

select t.id as race_task5_id, t.record_version as race_task5_version
from app.wms_pick_tasks t
join app.wms_outbound_order_lines l on l.id = t.outbound_order_line_id
join app.wms_outbound_orders o on o.id = l.outbound_order_id
where o.tenant_id = (select id from app.tenants where slug = 'wmspick1') and o.idempotency_key = 'idem-pick-main' and l.line_number = 5
\gset
select current_database() as pg_test_db \gset

\set race_sql_a 'select app.claim_wms_pick_task(''' :race_task5_id ''', ' :race_task5_version ', ''00000000-0000-0000-0000-000000180102'', ''rep'');'
\set race_sql_b 'select app.claim_wms_pick_task(''' :race_task5_id ''', ' :race_task5_version ', ''00000000-0000-0000-0000-000000180108'', ''rep2'');'

\setenv PG_TEST_DB :pg_test_db
\setenv RACE_SQL_A :race_sql_a
\setenv RACE_SQL_B :race_sql_b
\setenv RACE_OUT_A /tmp/cargogrid-wms-pick-race-l5-a-:race_bpid.out
\setenv RACE_OUT_B /tmp/cargogrid-wms-pick-race-l5-b-:race_bpid.out

\! bash scripts/db-tests/wms-picking-concurrency-helper.sh

do $$
declare
  v_task app.wms_pick_tasks;
begin
  -- Re-derived by line lookup, not by interpolating the captured psql variable
  -- directly into a dollar-quoted DO body -- psql variable substitution does not
  -- reach inside a dollar-quoted block body (a real constraint discovered while
  -- authoring this test, disclosed in the completion report).
  select t.* into v_task
    from app.wms_pick_tasks t
    join app.wms_outbound_order_lines l on l.id = t.outbound_order_line_id
    join app.wms_outbound_orders o on o.id = l.outbound_order_id
    where o.tenant_id = (select id from app.tenants where slug = 'wmspick1') and o.idempotency_key = 'idem-pick-main' and l.line_number = 5;
  if v_task.status <> 'claimed' or v_task.claimed_by_auth_user_id is null then
    raise exception 'assertion failed: expected exactly one real process to have won the claim race, got status=%/claimed_by=%', v_task.status, v_task.claimed_by_auth_user_id;
  end if;
  if v_task.claimed_by_auth_user_id not in ('00000000-0000-0000-0000-000000180102', '00000000-0000-0000-0000-000000180108') then
    raise exception 'assertion failed: expected the winning claimant to be one of the two real racing actors, got %', v_task.claimed_by_auth_user_id;
  end if;
  raise notice 'concurrent claim race proof: task claimed by exactly one real process (claimant=%) -- see the RACE_OUT_A/RACE_OUT_B process output captured above', v_task.claimed_by_label;
end $$;

\echo '>> cross-owner read isolation: the customer_user actor (scoped to Account Alpha only) can read an Alpha task via app.get_wms_pick_task/app.list_wms_pick_task_confirmations but is rejected on the Beta task (insufficient_authority, bug class f); a rep (staff, unrestricted) can read both; app.list_wms_pick_tasks for the customer_user actor returns only Alpha rows, never the Beta row, even unfiltered'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'wmspick1');
  v_beta_order_id uuid := (select id from app.wms_outbound_orders where tenant_id = v_tenant1 and idempotency_key = 'idem-pick-beta');
  v_beta_line app.wms_outbound_order_lines;
  v_beta_task app.wms_pick_tasks;
  v_alpha_task app.wms_pick_tasks;
  v_alpha_confirmations app.wms_pick_task_confirmations[];
  v_customer_rows app.wms_pick_tasks[];
begin
  select * into v_beta_line from app.wms_outbound_order_lines where outbound_order_id = v_beta_order_id and line_number = 1;
  v_beta_task := app.generate_wms_pick_task(v_beta_line.id, 12, null, null, null, null, null, 'idem-gen-beta', '00000000-0000-0000-0000-000000180102', 'rep');

  select * into v_alpha_task from app.wms_pick_tasks where tenant_id = v_tenant1 and idempotency_key = 'idem-gen-l1';

  -- The customer_user actor can read its own owner''s (Alpha) task and confirmation
  -- evidence.
  perform app.get_wms_pick_task(v_alpha_task.id, '00000000-0000-0000-0000-000000180109');
  select array_agg(c) into v_alpha_confirmations from app.list_wms_pick_task_confirmations(v_alpha_task.id, '00000000-0000-0000-0000-000000180109') c;
  if array_length(v_alpha_confirmations, 1) is null or array_length(v_alpha_confirmations, 1) < 1 then
    raise exception 'assertion failed: expected the customer_user actor to see at least 1 real confirmation on its own Alpha task';
  end if;

  -- The customer_user actor is rejected on the Beta task -- cross-owner isolation.
  begin
    perform app.get_wms_pick_task(v_beta_task.id, '00000000-0000-0000-0000-000000180109');
    raise exception 'assertion failed: expected insufficient_authority -- the customer_user actor is scoped to Account Alpha only, never Account Beta';
  exception
    when others then
      if sqlerrm not like 'insufficient_authority%' then raise; end if;
  end;

  -- Staff (rep, unrestricted) can read both.
  perform app.get_wms_pick_task(v_alpha_task.id, '00000000-0000-0000-0000-000000180102');
  perform app.get_wms_pick_task(v_beta_task.id, '00000000-0000-0000-0000-000000180102');

  -- app.list_wms_pick_tasks for the customer_user actor never returns the Beta row,
  -- even completely unfiltered.
  select array_agg(t) into v_customer_rows from app.list_wms_pick_tasks(v_tenant1, '00000000-0000-0000-0000-000000180109', null, null, null, null, null, null, null, 200) t;
  if array_length(v_customer_rows, 1) is null then
    raise exception 'assertion failed: expected the customer_user actor to see at least its own Alpha rows';
  end if;
  if exists (select 1 from unnest(v_customer_rows) t where t.id = v_beta_task.id) then
    raise exception 'assertion failed: the customer_user actor must never see the Beta-owned task, even unfiltered';
  end if;
  if exists (select 1 from unnest(v_customer_rows) t where t.owner_account_id <> (select id from app.accounts where tenant_id = v_tenant1 and legal_name = 'WmsPick Customer Alpha')) then
    raise exception 'assertion failed: every row returned to the customer_user actor must be owned by Account Alpha';
  end if;

  -- Filtering by the Beta owner_account_id explicitly is also correctly empty for the
  -- customer_user actor (record-scope AND owner-scope both apply per row).
  if exists (select 1 from app.list_wms_pick_tasks(v_tenant1, '00000000-0000-0000-0000-000000180109', null, null, null, null, (select id from app.accounts where tenant_id = v_tenant1 and legal_name = 'WmsPick Customer Beta'), null, null, 50)) then
    raise exception 'assertion failed: expected zero rows when the customer_user actor explicitly filters by the Beta owner_account_id';
  end if;
end $$;

\echo '>> cross-tenant isolation: tenant2''s rep, who holds zero membership in tenant1, is rejected insufficient_authority on every mutation/read against tenant1''s real records; a tenant1 outbound order line/task id supplied by a tenant2 caller never leaks state'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'wmspick1');
  v_task_l1 app.wms_pick_tasks;
  v_line1 app.wms_outbound_order_lines;
begin
  select * into v_task_l1 from app.wms_pick_tasks where tenant_id = v_tenant1 and idempotency_key = 'idem-gen-l1';
  select * into v_line1 from app.wms_outbound_order_lines where id = v_task_l1.outbound_order_line_id;

  begin
    -- ISS-2026-146: the probing actor is rep2b-attacker 180107 (tenant2's rep, zero membership in wmspick1).
    -- app.generate_wms_pick_task now folds a caller with zero
    -- membership in the probed record's own tenant into the SAME generic outbound_order_line_not_found
    -- a nonexistent id already produced, instead of an insufficient_authority message
    -- carrying that tenant's real tenant_id. The refusal itself is unchanged.
    perform app.generate_wms_pick_task(v_line1.id, 1, null, null, null, null, null, 'idem-gen-attacker', '00000000-0000-0000-0000-000000180107', 'rep2b-attacker');
    raise exception 'assertion failed: expected outbound_order_line_not_found (ISS-2026-146) -- tenant2''s rep must not generate a pick task against tenant1''s real line';
  exception
    when others then
      if sqlerrm not like 'outbound_order_line_not_found%' then raise; end if;
  end;

  begin
    -- ISS-2026-146: tenant2's rep (wmspick2) holds no membership in wmspick1, so app.claim_wms_pick_task
    -- now collapses that zero-membership case into its own generic
    -- task_not_found / no_data_found branch -- byte-identical to what a
    -- nonexistent id already produced, so the real tenant_id is never disclosed to an
    -- outsider. A genuine same-tenant member lacking the role still gets
    -- insufficient_authority, unchanged (asserted elsewhere in this file).
    perform app.claim_wms_pick_task(v_task_l1.id, v_task_l1.record_version, '00000000-0000-0000-0000-000000180107', 'rep2b-attacker');
    raise exception 'assertion failed: expected task_not_found -- tenant2''s rep must not claim tenant1''s real task';
  exception
    when others then
      if sqlerrm not like 'task_not_found%' then raise; end if;
  end;

  begin
    -- ISS-2026-146: tenant2's rep (wmspick2) holds no membership in wmspick1, so app.get_wms_pick_task
    -- now collapses that zero-membership case into its own generic
    -- task_not_found / no_data_found branch -- byte-identical to what a
    -- nonexistent id already produced, so the real tenant_id is never disclosed to an
    -- outsider. A genuine same-tenant member lacking the role still gets
    -- insufficient_authority, unchanged (asserted elsewhere in this file).
    perform app.get_wms_pick_task(v_task_l1.id, '00000000-0000-0000-0000-000000180107');
    raise exception 'assertion failed: expected task_not_found -- tenant2''s rep must not read tenant1''s real task';
  exception
    when others then
      if sqlerrm not like 'task_not_found%' then raise; end if;
  end;

  if exists (select 1 from app.list_wms_pick_tasks((select id from app.tenants where slug = 'wmspick2'), '00000000-0000-0000-0000-000000180107', null, null, null, null, null, null, null, 200)) then
    raise exception 'assertion failed: expected zero pick tasks visible under tenant2''s own scope (it has none of its own)';
  end if;
end $$;

\echo '>> regression: every idempotent-replay short-circuit runs strictly after authority/tenant-scope is confirmed -- tenant2''s rep is rejected insufficient_authority on tenant1''s real already-generated/claimed/confirmed/exception/cancelled records, never handed live business data off any of them (bug class a)'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'wmspick1');
  v_task_l1 app.wms_pick_tasks;
  v_task_l16 app.wms_pick_tasks;
begin
  select * into v_task_l1 from app.wms_pick_tasks where tenant_id = v_tenant1 and idempotency_key = 'idem-gen-l1';
  select * into v_task_l16 from app.wms_pick_tasks where tenant_id = v_tenant1 and idempotency_key = 'idem-gen-l16-exception';

  begin
    -- ISS-2026-146: the probing actor is rep2b-attacker 180107 (tenant2's rep, zero membership in wmspick1).
    -- app.generate_wms_pick_task now folds a caller with zero
    -- membership in the probed record's own tenant into the SAME generic outbound_order_line_not_found
    -- a nonexistent id already produced, instead of an insufficient_authority message
    -- carrying that tenant's real tenant_id. The refusal itself is unchanged.
    perform app.generate_wms_pick_task(v_task_l1.outbound_order_line_id, 100, null, null, null, null, null, 'idem-gen-l1', '00000000-0000-0000-0000-000000180107', 'rep2b-attacker');
    raise exception 'assertion failed: expected outbound_order_line_not_found (ISS-2026-146) -- tenant2''s rep must not reach the idempotent-replay short-circuit on tenant1''s real line';
  exception
    when others then
      if sqlerrm not like 'outbound_order_line_not_found%' then raise; end if;
  end;

  begin
    -- ISS-2026-146: tenant2's rep (wmspick2) holds no membership in wmspick1, so app.claim_wms_pick_task
    -- now collapses that zero-membership case into its own generic
    -- task_not_found / no_data_found branch -- byte-identical to what a
    -- nonexistent id already produced, so the real tenant_id is never disclosed to an
    -- outsider. A genuine same-tenant member lacking the role still gets
    -- insufficient_authority, unchanged (asserted elsewhere in this file).
    perform app.claim_wms_pick_task(v_task_l1.id, 999999, '00000000-0000-0000-0000-000000180107', 'rep2b-attacker');
    raise exception 'assertion failed: expected task_not_found -- tenant2''s rep must not reach the claim short-circuit on tenant1''s already-claimed task';
  exception
    when others then
      if sqlerrm not like 'task_not_found%' then raise; end if;
  end;

  begin
    -- ISS-2026-146: the probing actor is rep2b-attacker 180107 (tenant2's rep, zero membership in wmspick1).
    -- app.confirm_wms_pick_task now folds a caller with zero
    -- membership in the probed record's own tenant into the SAME generic task_not_found
    -- a nonexistent id already produced, instead of an insufficient_authority message
    -- carrying that tenant's real tenant_id. The refusal itself is unchanged.
    perform app.confirm_wms_pick_task(v_task_l1.id, 1, v_task_l1.source_location_id, v_task_l1.item_master_id, null, null, v_task_l1.actual_destination_location_id, 'attacker-key', 999999, '00000000-0000-0000-0000-000000180107', 'rep2b-attacker');
    raise exception 'assertion failed: expected task_not_found (ISS-2026-146) -- tenant2''s rep must not reach the confirm short-circuit on tenant1''s already-confirmed task';
  exception
    when others then
      if sqlerrm not like 'task_not_found%' then raise; end if;
  end;

  begin
    -- ISS-2026-146: tenant2's rep (wmspick2) holds no membership in wmspick1, so app.mark_wms_pick_task_exception
    -- now collapses that zero-membership case into its own generic
    -- task_not_found / no_data_found branch -- byte-identical to what a
    -- nonexistent id already produced, so the real tenant_id is never disclosed to an
    -- outsider. A genuine same-tenant member lacking the role still gets
    -- insufficient_authority, unchanged (asserted elsewhere in this file).
    perform app.mark_wms_pick_task_exception(v_task_l16.id, 'malicious-probe-reason', 999999, '00000000-0000-0000-0000-000000180107', 'rep2b-attacker');
    raise exception 'assertion failed: expected task_not_found -- tenant2''s rep must not reach the exception short-circuit on tenant1''s task';
  exception
    when others then
      if sqlerrm not like 'task_not_found%' then raise; end if;
  end;

  begin
    -- ISS-2026-146: tenant2's rep (wmspick2) holds no membership in wmspick1, so app.cancel_wms_pick_task
    -- now collapses that zero-membership case into its own generic
    -- task_not_found / no_data_found branch -- byte-identical to what a
    -- nonexistent id already produced, so the real tenant_id is never disclosed to an
    -- outsider. A genuine same-tenant member lacking the role still gets
    -- insufficient_authority, unchanged (asserted elsewhere in this file).
    perform app.cancel_wms_pick_task(v_task_l1.id, 'malicious-probe-reason', 999999, '00000000-0000-0000-0000-000000180107', 'rep2b-attacker');
    raise exception 'assertion failed: expected task_not_found -- tenant2''s rep must not reach the cancel short-circuit on tenant1''s already-picked task';
  exception
    when others then
      if sqlerrm not like 'task_not_found%' then raise; end if;
  end;

  begin
    -- ISS-2026-146: the probing actor is rep2b-attacker 180107 (tenant2's rep, zero membership in wmspick1).
    -- app.approve_wms_pick_substitution now folds a caller with zero
    -- membership in the probed record's own tenant into the SAME generic task_not_found
    -- a nonexistent id already produced, instead of an insufficient_authority message
    -- carrying that tenant's real tenant_id. The refusal itself is unchanged.
    perform app.approve_wms_pick_substitution(v_task_l1.id, v_task_l1.item_master_id, null, null, null, 'malicious-probe-reason', 'attacker-sub-key', 999999, '00000000-0000-0000-0000-000000180107', 'rep2b-attacker');
    raise exception 'assertion failed: expected task_not_found (ISS-2026-146) -- tenant2''s rep must not reach the substitution short-circuit on tenant1''s task';
  exception
    when others then
      if sqlerrm not like 'task_not_found%' then raise; end if;
  end;
end $$;

\echo '>> bounded/filtered reads: app.list_wms_pick_tasks p_limit defaults to 50 and hard-caps at 200; explicit status/warehouse/claimed_by filters narrow correctly'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'wmspick1');
  v_warehouse_id uuid := (select id from app.warehouses where tenant_id = v_tenant1 and code = 'WH-PICK-1');
  v_rows app.wms_pick_tasks[];
begin
  select array_agg(t) into v_rows from app.list_wms_pick_tasks(v_tenant1, '00000000-0000-0000-0000-000000180102', null, null, null, null, null, null, null, 999999) t;
  if array_length(v_rows, 1) > 200 then
    raise exception 'assertion failed: expected p_limit to be hard-capped at 200 regardless of a caller-supplied larger value, got %', array_length(v_rows, 1);
  end if;

  select array_agg(t) into v_rows from app.list_wms_pick_tasks(v_tenant1, '00000000-0000-0000-0000-000000180102', v_warehouse_id, null, null, null, null, 'picked', null, 50) t;
  if v_rows is null or array_length(v_rows, 1) < 1 then
    raise exception 'assertion failed: expected at least one status=picked task under WH-PICK-1';
  end if;
  if exists (select 1 from unnest(v_rows) t where t.status <> 'picked') then
    raise exception 'assertion failed: expected every row to have status=picked when explicitly filtered';
  end if;

  select array_agg(t) into v_rows from app.list_wms_pick_tasks(v_tenant1, '00000000-0000-0000-0000-000000180102', null, null, null, null, null, null, '00000000-0000-0000-0000-000000180108', 50) t;
  if exists (select 1 from unnest(v_rows) t where t.claimed_by_auth_user_id <> '00000000-0000-0000-0000-000000180108') then
    raise exception 'assertion failed: expected every row to be claimed by rep2 when explicitly filtered by claimed_by_auth_user_id';
  end if;
end $$;

\echo '>> schema-privilege defense in depth (ERR-2026-004): anon holds no direct table/EXECUTE access; authenticated has RLS-scoped SELECT but no direct INSERT/UPDATE/DELETE; only service_role may write directly'
do $$
begin
  if has_table_privilege('anon', 'app.wms_pick_tasks', 'SELECT') then
    raise exception 'assertion failed: anon must not have direct SELECT on app.wms_pick_tasks';
  end if;
  if has_table_privilege('anon', 'app.wms_pick_task_confirmations', 'SELECT') then
    raise exception 'assertion failed: anon must not have direct SELECT on app.wms_pick_task_confirmations';
  end if;
  if has_table_privilege('anon', 'app.wms_pick_substitution_approvals', 'SELECT') then
    raise exception 'assertion failed: anon must not have direct SELECT on app.wms_pick_substitution_approvals';
  end if;
  if has_function_privilege('anon', 'app.generate_wms_pick_task(uuid, numeric, uuid, uuid, text, text, uuid, text, uuid, text)', 'EXECUTE') then
    raise exception 'assertion failed: anon must not have EXECUTE on app.generate_wms_pick_task';
  end if;
  if has_function_privilege('anon', 'app.confirm_wms_pick_task(uuid, numeric, uuid, uuid, text, text, uuid, text, integer, uuid, text)', 'EXECUTE') then
    raise exception 'assertion failed: anon must not have EXECUTE on app.confirm_wms_pick_task';
  end if;
  if has_function_privilege('anon', 'app.approve_wms_pick_substitution(uuid, uuid, uuid, text, text, text, text, integer, uuid, text)', 'EXECUTE') then
    raise exception 'assertion failed: anon must not have EXECUTE on app.approve_wms_pick_substitution';
  end if;

  if not has_table_privilege('authenticated', 'app.wms_pick_tasks', 'SELECT') then
    raise exception 'assertion failed: authenticated must have RLS-scoped SELECT on app.wms_pick_tasks';
  end if;
  if has_table_privilege('authenticated', 'app.wms_pick_tasks', 'INSERT') then
    raise exception 'assertion failed: authenticated must not have direct INSERT on app.wms_pick_tasks -- mutation must go through the SECURITY DEFINER RPCs only';
  end if;
  if has_table_privilege('authenticated', 'app.wms_pick_task_confirmations', 'UPDATE') then
    raise exception 'assertion failed: authenticated must not have direct UPDATE on app.wms_pick_task_confirmations';
  end if;
  if has_table_privilege('authenticated', 'app.wms_pick_substitution_approvals', 'DELETE') then
    raise exception 'assertion failed: authenticated must not have direct DELETE on app.wms_pick_substitution_approvals';
  end if;

  if not has_table_privilege('service_role', 'app.wms_pick_tasks', 'INSERT') then
    raise exception 'assertion failed: service_role must retain direct table access to app.wms_pick_tasks';
  end if;
  if not has_table_privilege('service_role', 'app.wms_pick_task_confirmations', 'INSERT') then
    raise exception 'assertion failed: service_role must retain direct table access to app.wms_pick_task_confirmations';
  end if;
  if not has_table_privilege('service_role', 'app.wms_pick_substitution_approvals', 'INSERT') then
    raise exception 'assertion failed: service_role must retain direct table access to app.wms_pick_substitution_approvals';
  end if;

  -- ATW-016A's own app.cancel_wms_outbound_order retains its original grant after this
  -- migration's own same-signature CREATE OR REPLACE (design note 13) -- unaffected by
  -- this migration's own blanket revoke-from-public.
  if not has_function_privilege('authenticated', 'app.cancel_wms_outbound_order(uuid, text, integer, uuid, text)', 'EXECUTE') then
    raise exception 'assertion failed: expected app.cancel_wms_outbound_order to retain its authenticated EXECUTE grant after being widened';
  end if;
  if has_function_privilege('anon', 'app.cancel_wms_outbound_order(uuid, text, integer, uuid, text)', 'EXECUTE') then
    raise exception 'assertion failed: anon must not have EXECUTE on app.cancel_wms_outbound_order';
  end if;
end $$;

\echo '>> app.cancel_wms_outbound_order widening (design note 13): a confirmed outbound order with any non-cancelled pick task is blocked has_pick_progress; cancelling every pick task first then allows the order itself to cancel'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'wmspick1');
  v_warehouse_id uuid := (select id from app.warehouses where tenant_id = v_tenant1 and code = 'WH-PICK-1');
  v_account_alpha_id uuid := (select id from app.accounts where tenant_id = v_tenant1 and legal_name = 'WmsPick Customer Alpha');
  v_plain_id uuid := (select id from app.item_masters where tenant_id = v_tenant1 and code = 'SKU-PICK-PLAIN');
  v_order app.wms_outbound_orders;
  v_line app.wms_outbound_order_lines;
  v_task app.wms_pick_tasks;
begin
  v_order := app.create_manual_wms_outbound_order(v_tenant1, v_warehouse_id, v_account_alpha_id, 'cancel-widen fixture', 'idem-pick-cancelwiden', null, '00000000-0000-0000-0000-000000180102', 'rep');
  v_line := app.add_wms_outbound_order_line(v_order.id, v_plain_id, 'PCS', 5, null, '00000000-0000-0000-0000-000000180102', 'rep');
  v_order := app.confirm_wms_outbound_order(v_order.id, v_order.record_version, '00000000-0000-0000-0000-000000180102', 'rep');

  v_task := app.generate_wms_pick_task(v_line.id, 5, null, null, null, null, null, 'idem-gen-cancelwiden', '00000000-0000-0000-0000-000000180102', 'rep');

  begin
    perform app.cancel_wms_outbound_order(v_order.id, 'no longer needed', v_order.record_version, '00000000-0000-0000-0000-000000180102', 'rep');
    raise exception 'assertion failed: expected has_pick_progress -- a real, non-cancelled pick task still references this order''s own line';
  exception
    when others then
      if sqlerrm not like 'has_pick_progress%' then raise; end if;
  end;

  v_task := app.cancel_wms_pick_task(v_task.id, 'reversing fixture', v_task.record_version, '00000000-0000-0000-0000-000000180102', 'rep');

  v_order := app.cancel_wms_outbound_order(v_order.id, 'no longer needed', v_order.record_version, '00000000-0000-0000-0000-000000180102', 'rep');
  if v_order.status <> 'cancelled' then
    raise exception 'assertion failed: expected the outbound order to cancel cleanly once its own pick task was cancelled first, got status=%', v_order.status;
  end if;
end $$;
