-- Real, executable test evidence for ATW-019 (CG-S10-ATW-019, Prompt 238 WMS Outbound
-- -- the REMAINDER of Prompt 238's own scope, staging/dock/load/custody/ship-confirm/
-- billing-eligibility, layered on top of ATW-016A/017/018's own already-applied
-- demand/pick/pack contracts) -- run via `pnpm run db:test` against a real, disposable
-- Postgres database.

\set ON_ERROR_STOP on

\echo '>> setup: one tenant (wmsoutx1), a company org unit, a rep (OPS:Create/Edit/View), a second rep for the concurrency race, a supervisor (OPS:Create/Edit/View/Override), an OPS:View-only viewer, a global Supreme Admin, two owner accounts (Alpha, Beta) under tenant1 via the full CRM->Job Order pipeline, a customer_user-layer actor scoped to Account Alpha only, one warehouse (WH-OUTX-1) with a pick-enabled rack, a staging location, and two dock locations (one active, one inactive), and item masters. Tenant2 (wmsoutx2): an isolated rep, for cross-tenant leakage checks.'
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
begin
  insert into auth.users (id, email) values
    ('00000000-0000-0000-0000-000000200201', 'admin@wmsoutx1.test'),
    ('00000000-0000-0000-0000-000000200202', 'rep@wmsoutx1.test'),
    ('00000000-0000-0000-0000-000000200203', 'rep2@wmsoutx1.test'),
    ('00000000-0000-0000-0000-000000200204', 'supervisor@wmsoutx1.test'),
    ('00000000-0000-0000-0000-000000200205', 'viewer@wmsoutx1.test'),
    ('00000000-0000-0000-0000-000000200206', 'supreme@wmsoutx1.test'),
    ('00000000-0000-0000-0000-000000200207', 'customer-alpha@wmsoutx1.test'),
    ('00000000-0000-0000-0000-000000200208', 'admin2@wmsoutx2.test'),
    ('00000000-0000-0000-0000-000000200209', 'rep2b@wmsoutx2.test');

  perform app.grant_principal_membership('00000000-0000-0000-0000-000000200206', 'supreme_admin', null, null, 'tester');

  perform app.provision_tenant('wmsoutx1', 'WMS Outbound Tenant One', 'idem-wmsoutx1', 'tester');
  v_tenant1 := (select id from app.tenants where slug = 'wmsoutx1');
  perform app.transition_tenant_status(v_tenant1, 'active', 'setup', 'tester');
  perform app.create_org_unit(v_tenant1, 'company', null, 'WMSOUTX1-CO', 'WMS Outbound Tenant One Co', 'tester');
  v_company := (select id from app.org_units where tenant_id = v_tenant1 and code = 'WMSOUTX1-CO');

  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000200201', 'admin@wmsoutx1.test', 'WmsOut Admin', v_company, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'admin@wmsoutx1.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000200201', 'tenant_admin', v_tenant1, null, 'tester');

  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000200202', 'rep@wmsoutx1.test', 'WmsOut Rep', v_company, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'rep@wmsoutx1.test'), 'active', 'onboarded', 'tester');

  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000200203', 'rep2@wmsoutx1.test', 'WmsOut Rep Two', v_company, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'rep2@wmsoutx1.test'), 'active', 'onboarded', 'tester');

  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000200205', 'viewer@wmsoutx1.test', 'WmsOut Viewer', v_company, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'viewer@wmsoutx1.test'), 'active', 'onboarded', 'tester');

  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000200204', 'supervisor@wmsoutx1.test', 'WmsOut Supervisor', v_company, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'supervisor@wmsoutx1.test'), 'active', 'onboarded', 'tester');

  -- The rep role holds OPS Create/Edit/View together -- every mutation this migration
  -- defines composes at least one of these three top-level gates, and the upstream
  -- ATW-017/018 fixture calls below need the identical trio.
  v_rep_role := (app.create_role(v_tenant1, 'WmsOut Rep Role', 'full commercial + ops create/edit/view', 'tester')).id;
  v_rep_draft := app.create_role_version(v_rep_role, 'tester');
  perform app.set_role_version_permissions(
    v_rep_draft.id,
    array(select id from app.permissions where (resource_module_code = 'COM' and action in ('Create', 'Edit', 'Approve', 'View', 'View cost'))
      or (resource_module_code = 'OPS' and action in ('Create', 'Edit', 'View'))),
    'tester'
  );
  perform app.publish_role_version(v_rep_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_rep_role and status = 'published'), '00000000-0000-0000-0000-000000200202', '00000000-0000-0000-0000-000000200201', 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_rep_role and status = 'published'), '00000000-0000-0000-0000-000000200203', '00000000-0000-0000-0000-000000200201', 'tester');

  v_supervisor_role := (app.create_role(v_tenant1, 'WmsOut Supervisor Role', 'ops create/edit/view/override', 'tester')).id;
  v_supervisor_draft := app.create_role_version(v_supervisor_role, 'tester');
  perform app.set_role_version_permissions(
    v_supervisor_draft.id,
    array(select id from app.permissions where resource_module_code = 'OPS' and action in ('Create', 'Edit', 'View', 'Override')),
    'tester'
  );
  perform app.publish_role_version(v_supervisor_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_supervisor_role and status = 'published'), '00000000-0000-0000-0000-000000200204', '00000000-0000-0000-0000-000000200201', 'tester');

  v_viewer_role := (app.create_role(v_tenant1, 'WmsOut Viewer Role', 'OPS:View only', 'tester')).id;
  v_viewer_draft := app.create_role_version(v_viewer_role, 'tester');
  perform app.set_role_version_permissions(v_viewer_draft.id, array(select id from app.permissions where resource_module_code = 'OPS' and action = 'View'), 'tester');
  perform app.publish_role_version(v_viewer_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_viewer_role and status = 'published'), '00000000-0000-0000-0000-000000200205', '00000000-0000-0000-0000-000000200201', 'tester');

  v_warehouse := app.create_warehouse(v_tenant1, v_company, 'WH-OUTX-1', 'WMS Outbound Warehouse 1', 'Jl. Outbound 1', 'Asia/Jakarta', null, array['land']::text[], '00000000-0000-0000-0000-000000200202', 'rep');
  declare
    v_rack app.warehouse_locations;
    v_stage app.warehouse_locations;
    v_dock app.warehouse_locations;
    v_dock2 app.warehouse_locations;
    v_dock_inactive app.warehouse_locations;
  begin
    v_rack := app.create_warehouse_location(v_warehouse.id, null, null, 'RACK-OUTX-A', 'Outbound Source Rack A', 'rack', 1, null, null, null, null, null, true, false, '00000000-0000-0000-0000-000000200202', 'rep');
    perform app.set_warehouse_location_status(v_rack.id, 'active', null, v_rack.record_version, '00000000-0000-0000-0000-000000200202', 'rep');
    v_stage := app.create_warehouse_location(v_warehouse.id, null, null, 'STAGE-OUTX-1', 'Outbound Staging 1', 'staging', 2, null, null, null, null, null, false, false, '00000000-0000-0000-0000-000000200202', 'rep');
    perform app.set_warehouse_location_status(v_stage.id, 'active', null, v_stage.record_version, '00000000-0000-0000-0000-000000200202', 'rep');
    v_dock := app.create_warehouse_location(v_warehouse.id, null, null, 'DOCK-OUTX-1', 'Outbound Dock 1', 'dock', 3, null, null, null, null, null, false, false, '00000000-0000-0000-0000-000000200202', 'rep');
    perform app.set_warehouse_location_status(v_dock.id, 'active', null, v_dock.record_version, '00000000-0000-0000-0000-000000200202', 'rep');
    v_dock2 := app.create_warehouse_location(v_warehouse.id, null, null, 'DOCK-OUTX-2', 'Outbound Dock 2', 'dock', 4, null, null, null, null, null, false, false, '00000000-0000-0000-0000-000000200202', 'rep');
    perform app.set_warehouse_location_status(v_dock2.id, 'active', null, v_dock2.record_version, '00000000-0000-0000-0000-000000200202', 'rep');
    v_dock_inactive := app.create_warehouse_location(v_warehouse.id, null, null, 'DOCK-OUTX-3', 'Outbound Dock 3 (inactive)', 'dock', 5, null, null, null, null, null, false, false, '00000000-0000-0000-0000-000000200202', 'rep');
    -- Left in 'draft' (never activated) -- the blocked_destination fixture.
  end;

  -- Account Alpha, via the full CRM->Job Order pipeline.
  perform app.capture_lead(v_tenant1, 'manual', null, 'WmsOut Customer Alpha', 'Alice WmsOut', 'alice@wmsoutx238.test', '0811',
    '00000000-0000-0000-0000-000000200202', v_company, '00000000-0000-0000-0000-000000200202', 'tester');
  select * into v_lead from app.leads where email = 'alice@wmsoutx238.test';
  perform app.qualify_lead(v_lead.id, v_lead.record_version, '00000000-0000-0000-0000-000000200202', 'tester');
  select * into v_lead from app.leads where id = v_lead.id;
  perform app.convert_lead_to_prospect(v_lead.id, 'WmsOut Customer Alpha', 'WMSOUTX238RACEA', '11.111.111.28-111.000',
    jsonb_build_object('line1', 'Jl. Outbound Alpha 12', 'city', 'Jakarta', 'country', 'ID'),
    '00000000-0000-0000-0000-000000200202', 'tester');
  select * into v_prospect from app.prospects where lead_id = v_lead.id;
  select * into v_contact from app.create_contact(v_tenant1, 'Alice WmsOut Ops', 'Ops Lead', 'alice@wmsoutx238.test', '0811', '00000000-0000-0000-0000-000000200202', v_company, '00000000-0000-0000-0000-000000200202', 'tester');
  perform app.link_contact_to_record(v_contact.id, 'prospect', v_prospect.id, 'primary', true, '00000000-0000-0000-0000-000000200202', 'tester');
  select * into v_opportunity from app.create_opportunity(
    v_tenant1, v_prospect.id, 'WMSOUTX238RACE Alpha lane',
    jsonb_build_object('service_type', 'land_freight', 'cargo_description', 'General cargo', 'origin', 'Jakarta', 'destination', 'Surabaya', 'target_ready_date', '2026-08-01'),
    '00000000-0000-0000-0000-000000200202', v_company, '00000000-0000-0000-0000-000000200202', 'tester'
  );
  select * into v_request from app.request_costing(v_opportunity.id, '[]'::jsonb, null, '00000000-0000-0000-0000-000000200202', 'tester');
  select * into v_rate from app.create_rate_version(
    v_tenant1, 'VENDOR-WMSOUTX238RACE-A', 'Contoso WmsOut238 Line', 'land_freight', 'FTL', 'Jakarta', 'Surabaya', '20ft',
    null, null, null, null, 'IDR', 5000000, null, '[]'::jsonb, now(), null, null, '00000000-0000-0000-0000-000000200201', 'tester'
  );
  perform app.approve_rate_version(v_rate.id, v_rate.record_version, '00000000-0000-0000-0000-000000200201', 'tester');
  select * into v_selection from app.select_vendor_rate(v_request.id, v_rate.id, false, null, null, null, '00000000-0000-0000-0000-000000200202', 'tester');
  v_rule := app.create_margin_rule_version(v_tenant1, 20.00, 'half_up', '00000000-0000-0000-0000-000000200202', 'tester');
  perform app.publish_margin_rule_version(v_rule.id, v_rule.record_version, null, '00000000-0000-0000-0000-000000200202', 'tester');
  perform app.calculate_margin(v_selection.id, 6000000, 'IDR', 0, '00000000-0000-0000-0000-000000200202', 'tester');
  select id into v_calc_id from app.margin_calculations where rate_selection_id = v_selection.id and is_current;
  select * into v_quote from app.create_quotation_draft(v_tenant1, v_opportunity.id, 'IDR', now() + interval '14 days', v_contact.id, null, null, '00000000-0000-0000-0000-000000200202', 'tester');
  perform app.add_quotation_line(v_quote.id, v_quote.record_version, 'service', 'WMSOUTX238RACE Alpha lane', v_calc_id, 1, 6000000, 0, 0, '00000000-0000-0000-0000-000000200202', 'tester');
  select * into v_quote from app.quotations where id = v_quote.id;
  perform app.submit_quotation(v_quote.id, v_quote.record_version, '00000000-0000-0000-0000-000000200202', 'tester');
  select * into v_send from app.send_quotation_for_acceptance(v_quote.id, null, 'email', '00000000-0000-0000-0000-000000200202', 'tester');
  perform app.record_quotation_customer_decision(v_send.raw_token, 'accepted', 'Alice WmsOut Ops', null, null, null, null, null);
  select * into v_quote from app.quotations where id = v_quote.id;
  select * into v_account_alpha from app.convert_quotation_to_account(v_quote.id, null, null, '00000000-0000-0000-0000-000000200202', 'rep');

  -- Account Beta, a second owner account in the SAME tenant -- cross-owner isolation.
  perform app.capture_lead(v_tenant1, 'manual', null, 'WmsOut Customer Beta', 'Bob WmsOut', 'bob@wmsoutx238.test', '0812',
    '00000000-0000-0000-0000-000000200202', v_company, '00000000-0000-0000-0000-000000200202', 'tester');
  select * into v_lead from app.leads where email = 'bob@wmsoutx238.test';
  perform app.qualify_lead(v_lead.id, v_lead.record_version, '00000000-0000-0000-0000-000000200202', 'tester');
  select * into v_lead from app.leads where id = v_lead.id;
  perform app.convert_lead_to_prospect(v_lead.id, 'WmsOut Customer Beta', 'WMSOUTX238RACEB', '11.111.111.29-111.000',
    jsonb_build_object('line1', 'Jl. Outbound Beta 13', 'city', 'Jakarta', 'country', 'ID'),
    '00000000-0000-0000-0000-000000200202', 'tester');
  select * into v_prospect from app.prospects where lead_id = v_lead.id;
  select * into v_contact from app.create_contact(v_tenant1, 'Bob WmsOut Ops', 'Ops Lead', 'bob@wmsoutx238.test', '0812', '00000000-0000-0000-0000-000000200202', v_company, '00000000-0000-0000-0000-000000200202', 'tester');
  perform app.link_contact_to_record(v_contact.id, 'prospect', v_prospect.id, 'primary', true, '00000000-0000-0000-0000-000000200202', 'tester');
  select * into v_opportunity from app.create_opportunity(
    v_tenant1, v_prospect.id, 'WMSOUTX238RACE Beta lane',
    jsonb_build_object('service_type', 'land_freight', 'cargo_description', 'General cargo', 'origin', 'Jakarta', 'destination', 'Surabaya', 'target_ready_date', '2026-08-01'),
    '00000000-0000-0000-0000-000000200202', v_company, '00000000-0000-0000-0000-000000200202', 'tester'
  );
  select * into v_request from app.request_costing(v_opportunity.id, '[]'::jsonb, null, '00000000-0000-0000-0000-000000200202', 'tester');
  select * into v_rate from app.create_rate_version(
    v_tenant1, 'VENDOR-WMSOUTX238RACE-B', 'Contoso WmsOut238 Line B', 'land_freight', 'FTL', 'Jakarta', 'Surabaya', '20ft',
    null, null, null, null, 'IDR', 5000000, null, '[]'::jsonb, now(), null, null, '00000000-0000-0000-0000-000000200201', 'tester'
  );
  perform app.approve_rate_version(v_rate.id, v_rate.record_version, '00000000-0000-0000-0000-000000200201', 'tester');
  select * into v_selection from app.select_vendor_rate(v_request.id, v_rate.id, false, null, null, null, '00000000-0000-0000-0000-000000200202', 'tester');
  perform app.calculate_margin(v_selection.id, 6000000, 'IDR', 0, '00000000-0000-0000-0000-000000200202', 'tester');
  select id into v_calc_id from app.margin_calculations where rate_selection_id = v_selection.id and is_current;
  select * into v_quote from app.create_quotation_draft(v_tenant1, v_opportunity.id, 'IDR', now() + interval '14 days', v_contact.id, null, null, '00000000-0000-0000-0000-000000200202', 'tester');
  perform app.add_quotation_line(v_quote.id, v_quote.record_version, 'service', 'WMSOUTX238RACE Beta lane', v_calc_id, 1, 6000000, 0, 0, '00000000-0000-0000-0000-000000200202', 'tester');
  select * into v_quote from app.quotations where id = v_quote.id;
  perform app.submit_quotation(v_quote.id, v_quote.record_version, '00000000-0000-0000-0000-000000200202', 'tester');
  select * into v_send from app.send_quotation_for_acceptance(v_quote.id, null, 'email', '00000000-0000-0000-0000-000000200202', 'tester');
  perform app.record_quotation_customer_decision(v_send.raw_token, 'accepted', 'Bob WmsOut Ops', null, null, null, null, null);
  select * into v_quote from app.quotations where id = v_quote.id;
  select * into v_account_beta from app.convert_quotation_to_account(v_quote.id, null, null, '00000000-0000-0000-0000-000000200202', 'rep');

  perform app.create_item_master(v_tenant1, v_account_alpha.id, 'SKU-OUTX-PLAIN', 'Outbound Plain Widget', null, 'PCS', false, false, false, '00000000-0000-0000-0000-000000200202', 'rep');
  perform app.create_item_master(v_tenant1, v_account_beta.id, 'SKU-OUTX-BETA', 'Outbound Beta Widget', null, 'PCS', false, false, false, '00000000-0000-0000-0000-000000200202', 'rep');

  -- The customer_user-layer actor is invited with a NULL org_unit_id.
  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000200207', 'customer-alpha@wmsoutx1.test', 'Customer Alpha Portal', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'customer-alpha@wmsoutx1.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000200207', 'customer_user', v_tenant1, v_account_alpha.id::text, 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_viewer_role and status = 'published'), '00000000-0000-0000-0000-000000200207', '00000000-0000-0000-0000-000000200201', 'tester');

  -- Tenant2: fully isolated -- exists only to prove cross-tenant scope safety.
  perform app.provision_tenant('wmsoutx2', 'WMS Outbound Tenant Two', 'idem-wmsoutx2', 'tester');
  v_tenant2 := (select id from app.tenants where slug = 'wmsoutx2');
  perform app.transition_tenant_status(v_tenant2, 'active', 'setup', 'tester');
  perform app.create_org_unit(v_tenant2, 'company', null, 'WMSOUTX2-CO', 'WMS Outbound Tenant Two Co', 'tester');
  v_company2 := (select id from app.org_units where tenant_id = v_tenant2 and code = 'WMSOUTX2-CO');
  perform app.invite_user(v_tenant2, '00000000-0000-0000-0000-000000200208', 'admin2@wmsoutx2.test', 'Tenant2 Admin', v_company2, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'admin2@wmsoutx2.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000200208', 'tenant_admin', v_tenant2, null, 'tester');
  perform app.invite_user(v_tenant2, '00000000-0000-0000-0000-000000200209', 'rep2b@wmsoutx2.test', 'Tenant2 Rep', v_company2, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'rep2b@wmsoutx2.test'), 'active', 'onboarded', 'tester');
  v_rep2_role := (app.create_role(v_tenant2, 'Tenant2 Rep Role', 'ops create/edit/view', 'tester')).id;
  v_rep2_draft := app.create_role_version(v_rep2_role, 'tester');
  perform app.set_role_version_permissions(v_rep2_draft.id, array(select id from app.permissions where resource_module_code = 'OPS' and action in ('Create', 'Edit', 'View')), 'tester');
  perform app.publish_role_version(v_rep2_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant2, (select id from app.role_versions where role_id = v_rep2_role and status = 'published'), '00000000-0000-0000-0000-000000200209', '00000000-0000-0000-0000-000000200208', 'tester');
end $$;

-- Test-fixture-only helpers (never part of the real migration): build a real, fully
-- confirmed pick+pack chain in a handful of calls, so the fixture below can assemble
-- many shipment scenarios without repeating the same eight-call sequence a dozen times.
create procedure pick_fully(p_line_id uuid, p_item_master_id uuid, p_qty numeric, p_rack_id uuid, p_stage_id uuid, p_idem_prefix text)
language plpgsql
as $proc$
declare
  v_t app.wms_pick_tasks;
begin
  v_t := app.generate_wms_pick_task(p_line_id, p_qty, null, p_rack_id, null, null, p_stage_id, p_idem_prefix || '-gen', '00000000-0000-0000-0000-000000200202', 'rep');
  v_t := app.claim_wms_pick_task(v_t.id, v_t.record_version, '00000000-0000-0000-0000-000000200202', 'rep');
  perform app.confirm_wms_pick_task(v_t.id, p_qty, p_rack_id, p_item_master_id, null, null, p_stage_id, p_idem_prefix || '-conf', v_t.record_version, '00000000-0000-0000-0000-000000200202', 'rep');
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
  v_packing_task := app.start_wms_packing_task(p_outbound_order_id, p_idem_prefix || '-task', '00000000-0000-0000-0000-000000200202', 'rep');
  v_pkg := app.create_wms_package(v_packing_task.id, null, 'carton', p_idem_prefix || '-pkg', '00000000-0000-0000-0000-000000200202', 'rep');
  v_pkg := app.add_wms_package_line(v_pkg.id, p_pick_task_id, p_qty, p_item_master_id, null, null, p_idem_prefix || '-line', v_pkg.record_version, '00000000-0000-0000-0000-000000200202', 'rep');
  v_pkg := app.record_wms_package_measurements(v_pkg.id, 5, 'KG', null, null, null, null, v_pkg.record_version, '00000000-0000-0000-0000-000000200202', 'rep');
  v_pkg := app.record_wms_package_qc(v_pkg.id, 'pass', null, v_pkg.record_version, '00000000-0000-0000-0000-000000200202', 'rep');
  v_pkg := app.record_wms_package_seal(v_pkg.id, p_idem_prefix || '-seal', v_pkg.record_version, '00000000-0000-0000-0000-000000200202', 'rep');
  v_pkg := app.confirm_wms_package(v_pkg.id, p_idem_prefix || '-confirm', v_pkg.record_version, '00000000-0000-0000-0000-000000200202', 'rep');
  return v_pkg;
end;
$fn$;

\echo '>> build confirmed Alpha outbound orders A (full-ship), B (partial/backorder, two lines), C (concurrency), E (validation fixtures), F (cancel fixture) and Beta order D (cross-owner), each fully picked and packed into real, confirmed ATW-018 packages'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'wmsoutx1');
  v_warehouse_id uuid := (select id from app.warehouses where tenant_id = v_tenant1 and code = 'WH-OUTX-1');
  v_rack_id uuid := (select id from app.warehouse_locations where tenant_id = v_tenant1 and code = 'RACK-OUTX-A');
  v_stage_id uuid := (select id from app.warehouse_locations where tenant_id = v_tenant1 and code = 'STAGE-OUTX-1');
  v_account_alpha_id uuid := (select id from app.accounts where tenant_id = v_tenant1 and legal_name = 'WmsOut Customer Alpha');
  v_account_beta_id uuid := (select id from app.accounts where tenant_id = v_tenant1 and legal_name = 'WmsOut Customer Beta');
  v_plain_id uuid := (select id from app.item_masters where tenant_id = v_tenant1 and code = 'SKU-OUTX-PLAIN');
  v_beta_item_id uuid := (select id from app.item_masters where tenant_id = v_tenant1 and code = 'SKU-OUTX-BETA');
  v_order_a app.wms_outbound_orders;
  v_order_b app.wms_outbound_orders;
  v_order_c app.wms_outbound_orders;
  v_order_d app.wms_outbound_orders;
  v_order_e app.wms_outbound_orders;
  v_order_f app.wms_outbound_orders;
  v_line_id uuid;
  v_line2_id uuid;
  v_task app.wms_pick_tasks;
begin
  -- Order A: full-ship fixture (one line, one package covers 100%).
  v_order_a := app.create_manual_wms_outbound_order(v_tenant1, v_warehouse_id, v_account_alpha_id, 'order A full-ship fixture', 'idem-out-a', null, '00000000-0000-0000-0000-000000200202', 'rep');
  perform app.add_wms_outbound_order_line(v_order_a.id, v_plain_id, 'PCS', 30, 'A-L1', '00000000-0000-0000-0000-000000200202', 'rep');
  v_order_a := app.confirm_wms_outbound_order(v_order_a.id, v_order_a.record_version, '00000000-0000-0000-0000-000000200202', 'rep');

  -- Order B: partial/backorder fixture (two lines, two separate packages).
  v_order_b := app.create_manual_wms_outbound_order(v_tenant1, v_warehouse_id, v_account_alpha_id, 'order B partial fixture', 'idem-out-b', null, '00000000-0000-0000-0000-000000200202', 'rep');
  perform app.add_wms_outbound_order_line(v_order_b.id, v_plain_id, 'PCS', 20, 'B-L1', '00000000-0000-0000-0000-000000200202', 'rep');
  perform app.add_wms_outbound_order_line(v_order_b.id, v_plain_id, 'PCS', 15, 'B-L2', '00000000-0000-0000-0000-000000200202', 'rep');
  v_order_b := app.confirm_wms_outbound_order(v_order_b.id, v_order_b.record_version, '00000000-0000-0000-0000-000000200202', 'rep');

  -- Order C: double-ship-confirm concurrency fixture.
  v_order_c := app.create_manual_wms_outbound_order(v_tenant1, v_warehouse_id, v_account_alpha_id, 'order C concurrency fixture', 'idem-out-c', null, '00000000-0000-0000-0000-000000200202', 'rep');
  perform app.add_wms_outbound_order_line(v_order_c.id, v_plain_id, 'PCS', 25, 'C-L1', '00000000-0000-0000-0000-000000200202', 'rep');
  v_order_c := app.confirm_wms_outbound_order(v_order_c.id, v_order_c.record_version, '00000000-0000-0000-0000-000000200202', 'rep');

  -- Order D: Beta-owned cross-owner isolation fixture.
  v_order_d := app.create_manual_wms_outbound_order(v_tenant1, v_warehouse_id, v_account_beta_id, 'order D beta fixture', 'idem-out-d', null, '00000000-0000-0000-0000-000000200202', 'rep');
  perform app.add_wms_outbound_order_line(v_order_d.id, v_beta_item_id, 'PCS', 10, 'D-L1', '00000000-0000-0000-0000-000000200202', 'rep');
  v_order_d := app.confirm_wms_outbound_order(v_order_d.id, v_order_d.record_version, '00000000-0000-0000-0000-000000200202', 'rep');

  -- Order E: wrong_order/package_not_confirmed validation fixture (package deliberately
  -- left unconfirmed for one line).
  v_order_e := app.create_manual_wms_outbound_order(v_tenant1, v_warehouse_id, v_account_alpha_id, 'order E validation fixture', 'idem-out-e', null, '00000000-0000-0000-0000-000000200202', 'rep');
  perform app.add_wms_outbound_order_line(v_order_e.id, v_plain_id, 'PCS', 8, 'E-L1', '00000000-0000-0000-0000-000000200202', 'rep');
  v_order_e := app.confirm_wms_outbound_order(v_order_e.id, v_order_e.record_version, '00000000-0000-0000-0000-000000200202', 'rep');

  -- Order F: cancel-shipment / reopen-after-remove fixture.
  v_order_f := app.create_manual_wms_outbound_order(v_tenant1, v_warehouse_id, v_account_alpha_id, 'order F cancel fixture', 'idem-out-f', null, '00000000-0000-0000-0000-000000200202', 'rep');
  perform app.add_wms_outbound_order_line(v_order_f.id, v_plain_id, 'PCS', 6, 'F-L1', '00000000-0000-0000-0000-000000200202', 'rep');
  v_order_f := app.confirm_wms_outbound_order(v_order_f.id, v_order_f.record_version, '00000000-0000-0000-0000-000000200202', 'rep');

  -- Real opening_balance inventory, enough for every scenario.
  perform app.post_inventory_movement(v_tenant1, v_warehouse_id, 'opening_balance', 'opening_balance', null, 'idem-out-open-alpha', 'opening balance fixture',
    jsonb_build_array(jsonb_build_object('owner_account_id', v_account_alpha_id, 'item_master_id', v_plain_id, 'location_id', v_rack_id, 'uom_code', 'PCS', 'signed_quantity', 200, 'status', 'on_hand')),
    '00000000-0000-0000-0000-000000200202', 'rep');
  perform app.post_inventory_movement(v_tenant1, v_warehouse_id, 'opening_balance', 'opening_balance', null, 'idem-out-open-beta', 'opening balance fixture',
    jsonb_build_array(jsonb_build_object('owner_account_id', v_account_beta_id, 'item_master_id', v_beta_item_id, 'location_id', v_rack_id, 'uom_code', 'PCS', 'signed_quantity', 20, 'status', 'on_hand')),
    '00000000-0000-0000-0000-000000200202', 'rep');

  -- Order A: pick + pack L1 (30 units) into one confirmed root package (P-A1).
  select l.id into v_line_id from app.wms_outbound_order_lines l where outbound_order_id = v_order_a.id and line_number = 1;
  call pick_fully(v_line_id, v_plain_id, 30, v_rack_id, v_stage_id, 'idem-out-pick-a1');
  v_task := (select t from app.wms_pick_tasks t where outbound_order_line_id = v_line_id);
  perform pack_task_fully(v_order_a.id, v_task.id, v_plain_id, 30, 'idem-out-pack-a1');

  -- Order B: pick + pack L1 (20) into P-B1, L2 (15) into P-B2 -- two SEPARATE packages.
  select l.id into v_line_id from app.wms_outbound_order_lines l where outbound_order_id = v_order_b.id and line_number = 1;
  call pick_fully(v_line_id, v_plain_id, 20, v_rack_id, v_stage_id, 'idem-out-pick-b1');
  v_task := (select t from app.wms_pick_tasks t where outbound_order_line_id = v_line_id);
  perform pack_task_fully(v_order_b.id, v_task.id, v_plain_id, 20, 'idem-out-pack-b1');

  select l.id into v_line2_id from app.wms_outbound_order_lines l where outbound_order_id = v_order_b.id and line_number = 2;
  call pick_fully(v_line2_id, v_plain_id, 15, v_rack_id, v_stage_id, 'idem-out-pick-b2');
  v_task := (select t from app.wms_pick_tasks t where outbound_order_line_id = v_line2_id);
  perform pack_task_fully(v_order_b.id, v_task.id, v_plain_id, 15, 'idem-out-pack-b2');

  -- Order C: pick + pack L1 (25) into P-C1.
  select l.id into v_line_id from app.wms_outbound_order_lines l where outbound_order_id = v_order_c.id and line_number = 1;
  call pick_fully(v_line_id, v_plain_id, 25, v_rack_id, v_stage_id, 'idem-out-pick-c1');
  v_task := (select t from app.wms_pick_tasks t where outbound_order_line_id = v_line_id);
  perform pack_task_fully(v_order_c.id, v_task.id, v_plain_id, 25, 'idem-out-pack-c1');

  -- Order D (Beta): pick + pack L1 (10) into P-D1.
  select l.id into v_line_id from app.wms_outbound_order_lines l where outbound_order_id = v_order_d.id and line_number = 1;
  call pick_fully(v_line_id, v_beta_item_id, 10, v_rack_id, v_stage_id, 'idem-out-pick-d1');
  v_task := (select t from app.wms_pick_tasks t where outbound_order_line_id = v_line_id);
  perform pack_task_fully(v_order_d.id, v_task.id, v_beta_item_id, 10, 'idem-out-pack-d1');

  -- Order E: pick + pack L1 (8) but leave the package UNCONFIRMED (open) -- the
  -- package_not_confirmed fixture.
  select l.id into v_line_id from app.wms_outbound_order_lines l where outbound_order_id = v_order_e.id and line_number = 1;
  call pick_fully(v_line_id, v_plain_id, 8, v_rack_id, v_stage_id, 'idem-out-pick-e1');
  v_task := (select t from app.wms_pick_tasks t where outbound_order_line_id = v_line_id);
  declare
    v_packing_task app.wms_packing_tasks;
    v_pkg app.wms_packages;
  begin
    v_packing_task := app.start_wms_packing_task(v_order_e.id, 'idem-out-pack-e1-task', '00000000-0000-0000-0000-000000200202', 'rep');
    v_pkg := app.create_wms_package(v_packing_task.id, null, 'carton', 'idem-out-pack-e1-pkg', '00000000-0000-0000-0000-000000200202', 'rep');
    v_pkg := app.add_wms_package_line(v_pkg.id, v_task.id, 8, v_plain_id, null, null, 'idem-out-pack-e1-line', v_pkg.record_version, '00000000-0000-0000-0000-000000200202', 'rep');
    -- Deliberately never measured/QC'd/sealed/confirmed.
  end;

  -- Order F: pick + pack L1 (6) into a confirmed package P-F1 -- the cancel-shipment
  -- fixture.
  select l.id into v_line_id from app.wms_outbound_order_lines l where outbound_order_id = v_order_f.id and line_number = 1;
  call pick_fully(v_line_id, v_plain_id, 6, v_rack_id, v_stage_id, 'idem-out-pick-f1');
  v_task := (select t from app.wms_pick_tasks t where outbound_order_line_id = v_line_id);
  perform pack_task_fully(v_order_f.id, v_task.id, v_plain_id, 6, 'idem-out-pack-f1');
end $$;

\echo '>> app.create_wms_outbound_shipment: viewer rejected; outbound_order_not_found; outbound_order_not_confirmed; success; idempotent replay'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'wmsoutx1');
  v_order_a_id uuid := (select id from app.wms_outbound_orders where tenant_id = v_tenant1 and idempotency_key = 'idem-out-a');
  v_warehouse_id uuid := (select id from app.warehouses where tenant_id = v_tenant1 and code = 'WH-OUTX-1');
  v_account_alpha_id uuid := (select id from app.accounts where tenant_id = v_tenant1 and legal_name = 'WmsOut Customer Alpha');
  v_draft_order app.wms_outbound_orders;
  v_ship app.wms_outbound_shipments;
  v_replay app.wms_outbound_shipments;
begin
  begin
    perform app.create_wms_outbound_shipment(v_order_a_id, 'idem-ship-viewer', '00000000-0000-0000-0000-000000200205', 'viewer');
    raise exception 'assertion failed: expected insufficient_authority -- viewer holds OPS:View only';
  exception
    when others then
      if sqlerrm not like 'insufficient_authority%' then raise; end if;
  end;

  begin
    perform app.create_wms_outbound_shipment(gen_random_uuid(), 'idem-ship-badorder', '00000000-0000-0000-0000-000000200202', 'rep');
    raise exception 'assertion failed: expected outbound_order_not_found';
  exception
    when others then
      if sqlerrm not like 'outbound_order_not_found%' then raise; end if;
  end;

  v_draft_order := app.create_manual_wms_outbound_order(v_tenant1, v_warehouse_id, v_account_alpha_id, 'never confirmed', 'idem-out-draft-only', null, '00000000-0000-0000-0000-000000200202', 'rep');
  begin
    perform app.create_wms_outbound_shipment(v_draft_order.id, 'idem-ship-draft', '00000000-0000-0000-0000-000000200202', 'rep');
    raise exception 'assertion failed: expected outbound_order_not_confirmed';
  exception
    when others then
      if sqlerrm not like 'outbound_order_not_confirmed%' then raise; end if;
  end;

  v_ship := app.create_wms_outbound_shipment(v_order_a_id, 'idem-ship-a', '00000000-0000-0000-0000-000000200202', 'rep');
  if v_ship.outbound_order_id <> v_order_a_id or v_ship.status <> 'staging' or v_ship.shipment_number is null then
    raise exception 'assertion failed: expected a real staging shipment against order A with a real shipment_number';
  end if;

  v_replay := app.create_wms_outbound_shipment(v_order_a_id, 'idem-ship-a', '00000000-0000-0000-0000-000000200202', 'rep');
  if v_replay.id <> v_ship.id then
    raise exception 'assertion failed: expected the same-idempotency-key replay to return the identical shipment';
  end if;
end $$;

\echo '>> full SH-A flow: dock_location_not_set -> empty_shipment_rejected -> add package (wrong_order/package_not_confirmed rejected first) -> incompatible_location on a rack -> load success (real transfer, on-hand moves rack-staging -> dock) -> shipment_not_staging on further add/remove/dock-set -> vehicle_ref settable while loaded -> custody_required -> stale_version -> ship-confirm success (non-partial, real consumption movement, billing-eligibility event, issue-line traceability) -> idempotent replay -> invalid_transition on a genuine second confirm attempt with a new key'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'wmsoutx1');
  v_ship_id uuid := (select id from app.wms_outbound_shipments where tenant_id = v_tenant1 and idempotency_key = 'idem-ship-a');
  v_order_a_id uuid := (select id from app.wms_outbound_orders where tenant_id = v_tenant1 and idempotency_key = 'idem-out-a');
  v_order_e_id uuid := (select id from app.wms_outbound_orders where tenant_id = v_tenant1 and idempotency_key = 'idem-out-e');
  v_pkg_a1_id uuid := (select id from app.wms_packages where tenant_id = v_tenant1 and idempotency_key = 'idem-out-pack-a1-pkg');
  v_pkg_e1_id uuid := (select id from app.wms_packages where tenant_id = v_tenant1 and idempotency_key = 'idem-out-pack-e1-pkg');
  v_pkg_b1_id uuid := (select id from app.wms_packages where tenant_id = v_tenant1 and idempotency_key = 'idem-out-pack-b1-pkg');
  v_rack_id uuid := (select id from app.warehouse_locations where tenant_id = v_tenant1 and code = 'RACK-OUTX-A');
  v_dock_id uuid := (select id from app.warehouse_locations where tenant_id = v_tenant1 and code = 'DOCK-OUTX-1');
  v_ship app.wms_outbound_shipments;
  v_before_rack numeric;
  v_before_dock numeric;
  v_after_rack numeric;
  v_after_dock numeric;
  v_before_on_hand numeric;
  v_after_on_hand numeric;
  v_issue_line_count integer;
  v_event app.wms_billing_eligibility_events;
  v_confirm_count integer;
  v_movement_count integer;
begin
  select * into v_ship from app.wms_outbound_shipments where id = v_ship_id;

  -- dock_location_not_set.
  begin
    perform app.load_wms_outbound_shipment(v_ship_id, 'idem-ship-a-load-nodock', v_ship.record_version, '00000000-0000-0000-0000-000000200202', 'rep');
    raise exception 'assertion failed: expected dock_location_not_set';
  exception
    when others then
      if sqlerrm not like 'dock_location_not_set%' then raise; end if;
  end;

  perform app.set_wms_shipment_dock_location(v_ship_id, v_dock_id, v_ship.record_version, '00000000-0000-0000-0000-000000200202', 'rep');
  select * into v_ship from app.wms_outbound_shipments where id = v_ship_id;

  -- invalid dock: a rack location.
  begin
    perform app.set_wms_shipment_dock_location(v_ship_id, v_rack_id, v_ship.record_version, '00000000-0000-0000-0000-000000200202', 'rep');
    raise exception 'assertion failed: expected incompatible_location -- RACK-OUTX-A is a rack, not a dock';
  exception
    when others then
      if sqlerrm not like 'incompatible_location%' then raise; end if;
  end;

  -- empty_shipment_rejected: dock set, but no packages staged yet.
  begin
    perform app.load_wms_outbound_shipment(v_ship_id, 'idem-ship-a-load-empty', v_ship.record_version, '00000000-0000-0000-0000-000000200202', 'rep');
    raise exception 'assertion failed: expected empty_shipment_rejected';
  exception
    when others then
      if sqlerrm not like 'empty_shipment_rejected%' then raise; end if;
  end;

  -- wrong_order: P-B1 is a real, CONFIRMED package, but belongs to order B, not order A.
  begin
    perform app.add_package_to_shipment(v_ship_id, v_pkg_b1_id, 'idem-ship-a-add-wrongorder', '00000000-0000-0000-0000-000000200202', 'rep');
    raise exception 'assertion failed: expected wrong_order';
  exception
    when others then
      if sqlerrm not like 'wrong_order%' then raise; end if;
  end;

  -- package_not_confirmed: P-E1 was deliberately left unconfirmed -- re-target it under
  -- order E''s own shipment instead, to isolate this specific rejection from wrong_order.
  declare
    v_ship_e app.wms_outbound_shipments;
  begin
    v_ship_e := app.create_wms_outbound_shipment(v_order_e_id, 'idem-ship-e-probe', '00000000-0000-0000-0000-000000200202', 'rep');
    begin
      perform app.add_package_to_shipment(v_ship_e.id, v_pkg_e1_id, 'idem-ship-e-add-notconfirmed', '00000000-0000-0000-0000-000000200202', 'rep');
      raise exception 'assertion failed: expected package_not_confirmed';
    exception
      when others then
        if sqlerrm not like 'package_not_confirmed%' then raise; end if;
    end;
  end;

  -- viewer rejected on add.
  begin
    perform app.add_package_to_shipment(v_ship_id, v_pkg_a1_id, 'idem-ship-a-add-viewer', '00000000-0000-0000-0000-000000200205', 'viewer');
    raise exception 'assertion failed: expected insufficient_authority';
  exception
    when others then
      if sqlerrm not like 'insufficient_authority%' then raise; end if;
  end;

  -- Real success: add P-A1.
  perform app.add_package_to_shipment(v_ship_id, v_pkg_a1_id, 'idem-ship-a-add', '00000000-0000-0000-0000-000000200202', 'rep');
  if (select count(*) from app.wms_shipment_packages where shipment_id = v_ship_id) <> 1 then
    raise exception 'assertion failed: expected exactly one staged package on SH-A';
  end if;

  -- Idempotent replay on the SAME add key never double-counts.
  perform app.add_package_to_shipment(v_ship_id, v_pkg_a1_id, 'idem-ship-a-add', '00000000-0000-0000-0000-000000200202', 'rep');
  if (select count(*) from app.wms_shipment_packages where shipment_id = v_ship_id) <> 1 then
    raise exception 'assertion failed: idempotent replay must never double-stage a package';
  end if;

  select coalesce(sum(on_hand), 0) into v_before_rack from app.inventory_balances b join app.warehouse_locations l on l.id = b.location_id where l.code = 'STAGE-OUTX-1' and l.tenant_id = v_tenant1;
  select coalesce(sum(on_hand), 0) into v_before_dock from app.inventory_balances b join app.warehouse_locations l on l.id = b.location_id where l.code = 'DOCK-OUTX-1' and l.tenant_id = v_tenant1;

  -- Real load success.
  select * into v_ship from app.wms_outbound_shipments where id = v_ship_id;
  v_ship := app.load_wms_outbound_shipment(v_ship_id, 'idem-ship-a-load', v_ship.record_version, '00000000-0000-0000-0000-000000200202', 'rep');
  if v_ship.status <> 'loaded' or v_ship.load_movement_id is null then
    raise exception 'assertion failed: expected SH-A to be loaded with a real load_movement_id';
  end if;

  select coalesce(sum(on_hand), 0) into v_after_rack from app.inventory_balances b join app.warehouse_locations l on l.id = b.location_id where l.code = 'STAGE-OUTX-1' and l.tenant_id = v_tenant1;
  select coalesce(sum(on_hand), 0) into v_after_dock from app.inventory_balances b join app.warehouse_locations l on l.id = b.location_id where l.code = 'DOCK-OUTX-1' and l.tenant_id = v_tenant1;
  if v_after_rack <> v_before_rack - 30 or v_after_dock <> v_before_dock + 30 then
    raise exception 'assertion failed: expected a real 30-unit transfer staging -> dock (staging %->%, dock %->%)', v_before_rack, v_after_rack, v_before_dock, v_after_dock;
  end if;

  -- Idempotent replay on the SAME load key is a clean no-op (no second movement).
  select count(*) into v_movement_count from app.inventory_movements where source_id = v_order_a_id and movement_type = 'transfer';
  perform app.load_wms_outbound_shipment(v_ship_id, 'idem-ship-a-load', v_ship.record_version, '00000000-0000-0000-0000-000000200202', 'rep');
  if (select count(*) from app.inventory_movements where source_id = v_order_a_id and movement_type = 'transfer') <> v_movement_count then
    raise exception 'assertion failed: idempotent load replay must never post a second transfer movement';
  end if;

  -- shipment_not_staging on add/remove/set-dock now that SH-A is loaded.
  begin
    perform app.add_package_to_shipment(v_ship_id, v_pkg_a1_id, 'idem-ship-a-add-loaded', '00000000-0000-0000-0000-000000200202', 'rep');
    raise exception 'assertion failed: expected shipment_not_staging on add after loaded';
  exception
    when others then
      if sqlerrm not like 'shipment_not_staging%' then raise; end if;
  end;
  begin
    perform app.remove_package_from_shipment(v_ship_id, v_pkg_a1_id, 'test removal after load', '00000000-0000-0000-0000-000000200202', 'rep');
    raise exception 'assertion failed: expected shipment_not_staging on remove after loaded';
  exception
    when others then
      if sqlerrm not like 'shipment_not_staging%' then raise; end if;
  end;
  begin
    perform app.set_wms_shipment_dock_location(v_ship_id, v_dock_id, v_ship.record_version, '00000000-0000-0000-0000-000000200202', 'rep');
    raise exception 'assertion failed: expected shipment_not_staging on dock change after loaded';
  exception
    when others then
      if sqlerrm not like 'shipment_not_staging%' then raise; end if;
  end;

  -- vehicle_ref remains settable while loaded (the "change vehicle before confirm" alt-flow).
  select * into v_ship from app.wms_outbound_shipments where id = v_ship_id;
  v_ship := app.set_wms_shipment_vehicle_ref(v_ship_id, 'TRUCK-A-001', v_ship.record_version, '00000000-0000-0000-0000-000000200202', 'rep');
  if v_ship.vehicle_ref <> 'TRUCK-A-001' then
    raise exception 'assertion failed: expected vehicle_ref to be settable while loaded';
  end if;

  -- custody_required.
  begin
    perform app.ship_confirm_wms_outbound_shipment(v_ship_id, null, 'handoff to carrier', false, null, 'idem-ship-a-confirm-nocustody', v_ship.record_version, '00000000-0000-0000-0000-000000200202', 'rep');
    raise exception 'assertion failed: expected custody_required with no custody label';
  exception
    when others then
      if sqlerrm not like 'custody_required%' then raise; end if;
  end;

  -- stale_version.
  begin
    perform app.ship_confirm_wms_outbound_shipment(v_ship_id, 'Driver Joko', 'handoff to carrier', false, null, 'idem-ship-a-confirm-stale', v_ship.record_version + 99, '00000000-0000-0000-0000-000000200202', 'rep');
    raise exception 'assertion failed: expected stale_version';
  exception
    when others then
      if sqlerrm not like 'stale_version%' then raise; end if;
  end;

  select coalesce(sum(on_hand), 0) into v_before_on_hand from app.inventory_balances b join app.warehouse_locations l on l.id = b.location_id where l.code = 'DOCK-OUTX-1' and l.tenant_id = v_tenant1;

  -- Real ship-confirm success: SH-A is the ONLY shipment for order A, and it includes
  -- the order''s only confirmed package -- non-partial.
  v_ship := app.ship_confirm_wms_outbound_shipment(v_ship_id, 'Driver Joko', 'handoff to carrier, POD collected', false, null, 'idem-ship-a-confirm', v_ship.record_version, '00000000-0000-0000-0000-000000200202', 'rep');
  if v_ship.status <> 'shipped' or v_ship.is_partial_fulfillment <> false or v_ship.consumption_movement_id is null or v_ship.custody_confirmed_by_label <> 'Driver Joko' then
    raise exception 'assertion failed: expected SH-A to be shipped, non-partial, with real custody/consumption evidence';
  end if;

  select coalesce(sum(on_hand), 0) into v_after_on_hand from app.inventory_balances b join app.warehouse_locations l on l.id = b.location_id where l.code = 'DOCK-OUTX-1' and l.tenant_id = v_tenant1;
  if v_after_on_hand <> v_before_on_hand - 30 then
    raise exception 'assertion failed: expected a real 30-unit consumption at the dock location (before=%, after=%)', v_before_on_hand, v_after_on_hand;
  end if;

  select count(*) into v_issue_line_count from app.wms_shipment_issue_lines where shipment_id = v_ship_id;
  if v_issue_line_count <> 1 then
    raise exception 'assertion failed: expected exactly one traceable issue line on SH-A, got %', v_issue_line_count;
  end if;
  if not exists (
    select 1 from app.wms_shipment_issue_lines il
    join app.wms_pick_tasks pt on pt.id = il.pick_task_id
    where il.shipment_id = v_ship_id and il.reservation_id = pt.reservation_id and il.quantity = 30
  ) then
    raise exception 'assertion failed: expected the issue line to carry a real pick_task_id/reservation_id traceable back to ATW-017''s own allocation';
  end if;

  select * into v_event from app.wms_billing_eligibility_events where shipment_id = v_ship_id;
  if v_event.package_count <> 1 or v_event.line_count <> 1 or v_event.total_quantity <> 30 or (v_event.weight_by_uom ->> 'KG')::numeric <> 5 then
    raise exception 'assertion failed: expected a real billing-eligibility event (package_count=1, line_count=1, total_quantity=30, weight_by_uom.KG=5), got %', v_event;
  end if;

  -- Idempotent replay on the SAME confirm key -- no double-issue.
  select count(*) into v_confirm_count from app.wms_shipment_confirmations where shipment_id = v_ship_id;
  select count(*) into v_movement_count from app.inventory_movements where source_id = v_order_a_id and movement_type = 'consumption';
  v_ship := app.ship_confirm_wms_outbound_shipment(v_ship_id, 'Driver Joko', 'handoff to carrier, POD collected', false, null, 'idem-ship-a-confirm', v_ship.record_version, '00000000-0000-0000-0000-000000200202', 'rep');
  if (select count(*) from app.wms_shipment_confirmations where shipment_id = v_ship_id) <> v_confirm_count
     or (select count(*) from app.inventory_movements where source_id = v_order_a_id and movement_type = 'consumption') <> v_movement_count then
    raise exception 'assertion failed: idempotent ship-confirm replay must never double-issue';
  end if;

  -- A genuine retry with a DIFFERENT idempotency key against an already-shipped
  -- shipment is a hard rejection, never a second issue.
  begin
    perform app.ship_confirm_wms_outbound_shipment(v_ship_id, 'Driver Joko', 'second attempt', false, null, 'idem-ship-a-confirm-second', v_ship.record_version, '00000000-0000-0000-0000-000000200202', 'rep');
    raise exception 'assertion failed: expected invalid_transition on a genuine second confirm attempt';
  exception
    when others then
      if sqlerrm not like 'invalid_transition%' then raise; end if;
  end;
end $$;

\echo '>> Order B partial/backorder flow (Prompt 238 section 26: supervisor approves partial/backorder/override): a plain rep (OPS:Create/Edit/View, no OPS:Override) is rejected insufficient_authority on SH-B1 (only P-B1 staged) regardless of acknowledgment/reason; the supervisor (OPS:Override) ship-confirms SH-B1 without acknowledgment -> partial_fulfillment_not_acknowledged; with acknowledgment but no reason -> invalid_reason; with a real reason -> success, is_partial_fulfillment=true; a later SH-B2 (P-B2) ship-confirm by the plain rep with p_is_partial_fulfillment=false now succeeds as non-partial (the order is now fully covered, no supervisor approval needed)'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'wmsoutx1');
  v_order_b_id uuid := (select id from app.wms_outbound_orders where tenant_id = v_tenant1 and idempotency_key = 'idem-out-b');
  v_pkg_b1_id uuid := (select id from app.wms_packages where tenant_id = v_tenant1 and idempotency_key = 'idem-out-pack-b1-pkg');
  v_pkg_b2_id uuid := (select id from app.wms_packages where tenant_id = v_tenant1 and idempotency_key = 'idem-out-pack-b2-pkg');
  v_dock_id uuid := (select id from app.warehouse_locations where tenant_id = v_tenant1 and code = 'DOCK-OUTX-1');
  v_ship_b1 app.wms_outbound_shipments;
  v_ship_b2 app.wms_outbound_shipments;
begin
  v_ship_b1 := app.create_wms_outbound_shipment(v_order_b_id, 'idem-ship-b1', '00000000-0000-0000-0000-000000200202', 'rep');
  perform app.add_package_to_shipment(v_ship_b1.id, v_pkg_b1_id, 'idem-ship-b1-add', '00000000-0000-0000-0000-000000200202', 'rep');
  perform app.set_wms_shipment_dock_location(v_ship_b1.id, v_dock_id, v_ship_b1.record_version, '00000000-0000-0000-0000-000000200202', 'rep');
  select * into v_ship_b1 from app.wms_outbound_shipments where id = v_ship_b1.id;
  v_ship_b1 := app.load_wms_outbound_shipment(v_ship_b1.id, 'idem-ship-b1-load', v_ship_b1.record_version, '00000000-0000-0000-0000-000000200202', 'rep');

  -- A plain rep holds OPS:Edit but never OPS:Override -- rejected on the real partial
  -- path (v_is_partial, derived from the aggregate) regardless of the acknowledgment
  -- flag or reason supplied; a staff actor may never unilaterally approve a
  -- partial/backorder ship.
  begin
    perform app.ship_confirm_wms_outbound_shipment(v_ship_b1.id, 'Driver Sari', 'first leg', false, null, 'idem-ship-b1-confirm-rep-noack', v_ship_b1.record_version, '00000000-0000-0000-0000-000000200202', 'rep');
    raise exception 'assertion failed: expected insufficient_authority -- a plain rep may not approve a partial/backorder ship';
  exception
    when others then
      if sqlerrm not like 'insufficient_authority%' then raise; end if;
  end;
  begin
    perform app.ship_confirm_wms_outbound_shipment(v_ship_b1.id, 'Driver Sari', 'first leg', true, 'customer requested early partial dispatch of L1', 'idem-ship-b1-confirm-rep-ack', v_ship_b1.record_version, '00000000-0000-0000-0000-000000200202', 'rep');
    raise exception 'assertion failed: expected insufficient_authority -- a plain rep may not approve a partial/backorder ship even with a real acknowledgment+reason';
  exception
    when others then
      if sqlerrm not like 'insufficient_authority%' then raise; end if;
  end;

  begin
    perform app.ship_confirm_wms_outbound_shipment(v_ship_b1.id, 'Driver Sari', 'first leg', false, null, 'idem-ship-b1-confirm-noack', v_ship_b1.record_version, '00000000-0000-0000-0000-000000200204', 'supervisor');
    raise exception 'assertion failed: expected partial_fulfillment_not_acknowledged -- P-B2 remains unshipped';
  exception
    when others then
      if sqlerrm not like 'partial_fulfillment_not_acknowledged%' then raise; end if;
  end;

  begin
    perform app.ship_confirm_wms_outbound_shipment(v_ship_b1.id, 'Driver Sari', 'first leg', true, null, 'idem-ship-b1-confirm-noreason', v_ship_b1.record_version, '00000000-0000-0000-0000-000000200204', 'supervisor');
    raise exception 'assertion failed: expected invalid_reason -- partial ack requires a non-empty reason';
  exception
    when others then
      if sqlerrm not like 'invalid_reason%' then raise; end if;
  end;

  v_ship_b1 := app.ship_confirm_wms_outbound_shipment(v_ship_b1.id, 'Driver Sari', 'first leg', true, 'customer requested early partial dispatch of L1', 'idem-ship-b1-confirm', v_ship_b1.record_version, '00000000-0000-0000-0000-000000200204', 'supervisor');
  if v_ship_b1.status <> 'shipped' or v_ship_b1.is_partial_fulfillment <> true or v_ship_b1.partial_fulfillment_reason is null then
    raise exception 'assertion failed: expected SH-B1 to ship as a real, acknowledged partial fulfillment';
  end if;

  -- SH-B2 (P-B2) now completes the order -- no acknowledgment required.
  v_ship_b2 := app.create_wms_outbound_shipment(v_order_b_id, 'idem-ship-b2', '00000000-0000-0000-0000-000000200202', 'rep');
  perform app.add_package_to_shipment(v_ship_b2.id, v_pkg_b2_id, 'idem-ship-b2-add', '00000000-0000-0000-0000-000000200202', 'rep');
  perform app.set_wms_shipment_dock_location(v_ship_b2.id, v_dock_id, v_ship_b2.record_version, '00000000-0000-0000-0000-000000200202', 'rep');
  select * into v_ship_b2 from app.wms_outbound_shipments where id = v_ship_b2.id;
  v_ship_b2 := app.load_wms_outbound_shipment(v_ship_b2.id, 'idem-ship-b2-load', v_ship_b2.record_version, '00000000-0000-0000-0000-000000200202', 'rep');
  v_ship_b2 := app.ship_confirm_wms_outbound_shipment(v_ship_b2.id, 'Driver Sari', 'second leg, completes order B', false, null, 'idem-ship-b2-confirm', v_ship_b2.record_version, '00000000-0000-0000-0000-000000200202', 'rep');
  if v_ship_b2.status <> 'shipped' or v_ship_b2.is_partial_fulfillment <> false then
    raise exception 'assertion failed: expected SH-B2 to ship as non-partial -- order B is now fully covered across SH-B1+SH-B2';
  end if;

  -- shipment_not_cancellable on an already-shipped shipment.
  begin
    perform app.cancel_wms_outbound_shipment(v_ship_b1.id, 'test cancel after ship', v_ship_b1.record_version, '00000000-0000-0000-0000-000000200202', 'rep');
    raise exception 'assertion failed: expected shipment_not_cancellable on a shipped shipment';
  exception
    when others then
      if sqlerrm not like 'shipment_not_cancellable%' then raise; end if;
  end;
end $$;

\echo '>> package_already_staged: a package staged into one shipment cannot be added to a second, different shipment for the same order'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'wmsoutx1');
  v_order_a_id uuid := (select id from app.wms_outbound_orders where tenant_id = v_tenant1 and idempotency_key = 'idem-out-a');
  v_pkg_a1_id uuid := (select id from app.wms_packages where tenant_id = v_tenant1 and idempotency_key = 'idem-out-pack-a1-pkg');
  v_ship2 app.wms_outbound_shipments;
begin
  v_ship2 := app.create_wms_outbound_shipment(v_order_a_id, 'idem-ship-a-second', '00000000-0000-0000-0000-000000200202', 'rep');
  begin
    perform app.add_package_to_shipment(v_ship2.id, v_pkg_a1_id, 'idem-ship-a-second-add', '00000000-0000-0000-0000-000000200202', 'rep');
    raise exception 'assertion failed: expected package_already_staged -- P-A1 already belongs to (shipped) SH-A';
  exception
    when others then
      if sqlerrm not like 'package_already_staged%' then raise; end if;
  end;
end $$;

\echo '>> app.reopen_wms_package widening (design note 6): package_staged_for_shipment on a package already staged (even after it has SHIPPED) -- reused via P-C1 once SH-C ships below; cancel-and-reopen fixture on order F (P-F1): staged -> package_staged_for_shipment -> cancel shipment (staging only) -> reopen succeeds -> re-add to a fresh shipment succeeds'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'wmsoutx1');
  v_order_f_id uuid := (select id from app.wms_outbound_orders where tenant_id = v_tenant1 and idempotency_key = 'idem-out-f');
  v_pkg_f1_id uuid := (select id from app.wms_packages where tenant_id = v_tenant1 and idempotency_key = 'idem-out-pack-f1-pkg');
  v_pkg app.wms_packages;
  v_ship app.wms_outbound_shipments;
begin
  select * into v_pkg from app.wms_packages where id = v_pkg_f1_id;
  v_ship := app.create_wms_outbound_shipment(v_order_f_id, 'idem-ship-f', '00000000-0000-0000-0000-000000200202', 'rep');
  perform app.add_package_to_shipment(v_ship.id, v_pkg_f1_id, 'idem-ship-f-add', '00000000-0000-0000-0000-000000200202', 'rep');

  begin
    perform app.reopen_wms_package(v_pkg_f1_id, 'attempt reopen while staged', v_pkg.record_version, '00000000-0000-0000-0000-000000200204', 'supervisor');
    raise exception 'assertion failed: expected package_staged_for_shipment while P-F1 is staged for SH-F';
  exception
    when others then
      if sqlerrm not like 'package_staged_for_shipment%' then raise; end if;
  end;

  select * into v_ship from app.wms_outbound_shipments where id = v_ship.id;
  perform app.cancel_wms_outbound_shipment(v_ship.id, 'test cancel to free P-F1', v_ship.record_version, '00000000-0000-0000-0000-000000200202', 'rep');
  if exists (select 1 from app.wms_shipment_packages where package_id = v_pkg_f1_id) then
    raise exception 'assertion failed: expected cancel to delete SH-F''s own package membership row, freeing P-F1';
  end if;

  -- Reopen now succeeds -- the guard is reachable-and-false once un-staged.
  select * into v_pkg from app.wms_packages where id = v_pkg_f1_id;
  v_pkg := app.reopen_wms_package(v_pkg_f1_id, 'genuine correction after cancel', v_pkg.record_version, '00000000-0000-0000-0000-000000200204', 'supervisor');
  if v_pkg.status <> 'open' then
    raise exception 'assertion failed: expected P-F1 to reopen successfully once no longer staged';
  end if;
end $$;

\echo '>> REAL two-process concurrent double-ship-confirm-prevention race (this checkpoint''s own headline acceptance criterion): SH-C is loaded with P-C1 (25 units). Two genuinely independent psql client processes each attempt app.ship_confirm_wms_outbound_shipment against the SAME shipment under TWO DIFFERENT idempotency keys, launched via scripts/db-tests/wms-picking-concurrency-helper.sh (reused directly). Exactly one must succeed; the other must be rejected invalid_transition; inventory must be issued exactly once, never twice.'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'wmsoutx1');
  v_order_c_id uuid := (select id from app.wms_outbound_orders where tenant_id = v_tenant1 and idempotency_key = 'idem-out-c');
  v_pkg_c1_id uuid := (select id from app.wms_packages where tenant_id = v_tenant1 and idempotency_key = 'idem-out-pack-c1-pkg');
  v_dock_id uuid := (select id from app.warehouse_locations where tenant_id = v_tenant1 and code = 'DOCK-OUTX-2');
  v_ship app.wms_outbound_shipments;
begin
  v_ship := app.create_wms_outbound_shipment(v_order_c_id, 'idem-ship-c', '00000000-0000-0000-0000-000000200202', 'rep');
  perform app.add_package_to_shipment(v_ship.id, v_pkg_c1_id, 'idem-ship-c-add', '00000000-0000-0000-0000-000000200202', 'rep');
  perform app.set_wms_shipment_dock_location(v_ship.id, v_dock_id, v_ship.record_version, '00000000-0000-0000-0000-000000200202', 'rep');
  select * into v_ship from app.wms_outbound_shipments where id = v_ship.id;
  v_ship := app.load_wms_outbound_shipment(v_ship.id, 'idem-ship-c-load', v_ship.record_version, '00000000-0000-0000-0000-000000200202', 'rep');
end $$;

select s.id as race_ship_id, s.record_version as race_ship_version
  from app.wms_outbound_shipments s join app.wms_outbound_orders o on o.id = s.outbound_order_id
  where o.idempotency_key = 'idem-out-c' \gset
select current_database() as pg_test_db \gset

\set race_sql_a 'select app.ship_confirm_wms_outbound_shipment(''' :race_ship_id ''', ''Driver Race A'', ''race leg A'', false, null, ''idem-ship-c-confirm-A'', ' :race_ship_version ', ''00000000-0000-0000-0000-000000200202'', ''rep'');'
\set race_sql_b 'select app.ship_confirm_wms_outbound_shipment(''' :race_ship_id ''', ''Driver Race B'', ''race leg B'', false, null, ''idem-ship-c-confirm-B'', ' :race_ship_version ', ''00000000-0000-0000-0000-000000200203'', ''rep2'');'

\setenv PG_TEST_DB :pg_test_db
\setenv RACE_SQL_A :race_sql_a
\setenv RACE_SQL_B :race_sql_b
\setenv RACE_OUT_A /tmp/cargogrid-wms-outbound-race-a.out
\setenv RACE_OUT_B /tmp/cargogrid-wms-outbound-race-b.out

\! bash scripts/db-tests/wms-picking-concurrency-helper.sh

-- RGL-BLK-005 fix: pg_read_file() reads the *server's* filesystem, but the helper
-- above writes its two race-output files on the *client's* -- identical locally
-- (same host), genuinely different in CI (Postgres runs in its own Docker service
-- container). \set's own backtick form runs the shell command on the CLIENT, the
-- same host the helper script just wrote to, sidestepping the mismatch entirely.
-- Bridged into the upcoming do block via a session-level GUC, the same pattern
-- already established for paths (advanced-tms-wms-picking.sql, automation-rule-
-- engine.sql) -- psql does not interpolate :variables inside a do $$ ... $$ body.
\set loser_out `cat "$RACE_OUT_A" "$RACE_OUT_B"`
select set_config('cargogrid.loser_out', :'loser_out', false);

\echo '>> asserting the concurrent double-ship-confirm race resolved to exactly one winner'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'wmsoutx1');
  v_ship_id uuid := (select s.id from app.wms_outbound_shipments s join app.wms_outbound_orders o on o.id = s.outbound_order_id where o.idempotency_key = 'idem-out-c');
  v_confirm_count integer;
  v_movement_count integer;
  v_loser_out text;
  v_pkg_c1_id uuid := (select id from app.wms_packages where tenant_id = v_tenant1 and idempotency_key = 'idem-out-pack-c1-pkg');
  v_ship app.wms_outbound_shipments;
begin
  select * into v_ship from app.wms_outbound_shipments where id = v_ship_id;
  if v_ship.status <> 'shipped' then
    raise exception 'assertion failed: expected SH-C to have reached shipped status after the race, got %', v_ship.status;
  end if;

  select count(*) into v_confirm_count from app.wms_shipment_confirmations where shipment_id = v_ship_id;
  if v_confirm_count <> 1 then
    raise exception 'assertion failed: expected exactly ONE winning ship-confirm evidence row, got %', v_confirm_count;
  end if;

  select count(*) into v_movement_count from app.inventory_movements where source_id = (select outbound_order_id from app.wms_outbound_shipments where id = v_ship_id) and movement_type = 'consumption';
  if v_movement_count <> 1 then
    raise exception 'assertion failed: expected exactly ONE consumption movement for order C, got % -- a double-issue occurred', v_movement_count;
  end if;

  if (select count(*) from app.wms_shipment_issue_lines where shipment_id = v_ship_id) <> 1 then
    raise exception 'assertion failed: expected exactly one issue-line row for SH-C';
  end if;

  v_loser_out := current_setting('cargogrid.loser_out');
  if v_loser_out not like '%invalid_transition%' then
    raise exception 'assertion failed: expected the losing process''s own output to carry a clean invalid_transition error, got: %', v_loser_out;
  end if;

  raise notice 'concurrent double-ship-confirm-prevention race proof: exactly ONE winner committed status=shipped/1 confirmation/1 consumption movement -- the shipment-header lock (design note 5) correctly serialized two real, independent psql processes';

  -- The widened app.reopen_wms_package guard also blocks a SHIPPED (not merely staged)
  -- package permanently.
  begin
    perform app.reopen_wms_package(v_pkg_c1_id, 'attempt reopen after ship', (select record_version from app.wms_packages where id = v_pkg_c1_id), '00000000-0000-0000-0000-000000200204', 'supervisor');
    raise exception 'assertion failed: expected package_staged_for_shipment on a SHIPPED package';
  exception
    when others then
      if sqlerrm not like 'package_staged_for_shipment%' then raise; end if;
  end;
end $$;

\echo '>> cross-owner read isolation: the customer_user actor (scoped to Account Alpha only) can read SH-A (Alpha) but is rejected on SH-D (Beta), insufficient_authority; a rep (staff, unrestricted) can read both; app.list_wms_outbound_shipments/app.list_wms_billing_eligibility_events for the customer_user actor return only Alpha rows, never Beta, even unfiltered'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'wmsoutx1');
  v_ship_a_id uuid := (select id from app.wms_outbound_shipments where tenant_id = v_tenant1 and idempotency_key = 'idem-ship-a');
  v_order_d_id uuid := (select id from app.wms_outbound_orders where tenant_id = v_tenant1 and idempotency_key = 'idem-out-d');
  v_pkg_d1_id uuid := (select id from app.wms_packages where tenant_id = v_tenant1 and idempotency_key = 'idem-out-pack-d1-pkg');
  v_dock_id uuid := (select id from app.warehouse_locations where tenant_id = v_tenant1 and code = 'DOCK-OUTX-1');
  v_ship_d app.wms_outbound_shipments;
  v_row app.wms_outbound_shipments;
  v_rows app.wms_outbound_shipments[];
  v_events app.wms_billing_eligibility_events[];
begin
  v_ship_d := app.create_wms_outbound_shipment(v_order_d_id, 'idem-ship-d', '00000000-0000-0000-0000-000000200202', 'rep');
  perform app.add_package_to_shipment(v_ship_d.id, v_pkg_d1_id, 'idem-ship-d-add', '00000000-0000-0000-0000-000000200202', 'rep');
  perform app.set_wms_shipment_dock_location(v_ship_d.id, v_dock_id, v_ship_d.record_version, '00000000-0000-0000-0000-000000200202', 'rep');
  select * into v_ship_d from app.wms_outbound_shipments where id = v_ship_d.id;
  v_ship_d := app.load_wms_outbound_shipment(v_ship_d.id, 'idem-ship-d-load', v_ship_d.record_version, '00000000-0000-0000-0000-000000200202', 'rep');
  v_ship_d := app.ship_confirm_wms_outbound_shipment(v_ship_d.id, 'Driver Beta', 'beta handoff', false, null, 'idem-ship-d-confirm', v_ship_d.record_version, '00000000-0000-0000-0000-000000200202', 'rep');

  v_row := app.get_wms_outbound_shipment(v_ship_a_id, '00000000-0000-0000-0000-000000200207');
  if v_row.id <> v_ship_a_id then
    raise exception 'assertion failed: expected the customer_alpha actor to read SH-A (owned by Alpha)';
  end if;

  begin
    perform app.get_wms_outbound_shipment(v_ship_d.id, '00000000-0000-0000-0000-000000200207');
    raise exception 'assertion failed: expected insufficient_authority -- customer_alpha may not view Beta''s SH-D';
  exception
    when others then
      if sqlerrm not like 'insufficient_authority%' then raise; end if;
  end;

  -- A rep (staff, unrestricted) can read both.
  v_row := app.get_wms_outbound_shipment(v_ship_a_id, '00000000-0000-0000-0000-000000200202');
  v_row := app.get_wms_outbound_shipment(v_ship_d.id, '00000000-0000-0000-0000-000000200202');

  select array_agg(s) into v_rows from app.list_wms_outbound_shipments(v_tenant1, '00000000-0000-0000-0000-000000200207') s;
  if exists (select 1 from unnest(v_rows) r where r.id = v_ship_d.id) then
    raise exception 'assertion failed: expected an unfiltered list for customer_alpha to never include Beta''s SH-D';
  end if;
  if not exists (select 1 from unnest(v_rows) r where r.id = v_ship_a_id) then
    raise exception 'assertion failed: expected an unfiltered list for customer_alpha to include Alpha''s own SH-A';
  end if;

  select array_agg(e) into v_events from app.list_wms_billing_eligibility_events(v_tenant1, '00000000-0000-0000-0000-000000200207') e;
  if exists (select 1 from unnest(v_events) r where r.shipment_id = v_ship_d.id) then
    raise exception 'assertion failed: expected billing-eligibility events for customer_alpha to never include Beta''s own event';
  end if;
end $$;

\echo '>> raw RLS regression proof: as the authenticated customer_alpha identity, a direct SELECT against app.wms_outbound_shipments/app.wms_billing_eligibility_events (bypassing every RPC) returns only Alpha rows, never Beta -- app.wms_pick_record_scope_ok (ATW-017) reused directly. Shipment/event ids are resolved by their OWN idempotency_key/shipment_id columns BEFORE the role switch below (never via a join through app.wms_outbound_orders under the customer_alpha session itself) -- 20260730311000 (CG-S10-ATW-023 hardening) denies a customer_user-layer actor''s raw-table read on app.wms_outbound_orders outright, so a join requiring that table to be readable under this role would no longer resolve, independent of this test''s own wms_outbound_shipments/wms_billing_eligibility_events isolation guarantee, which is unaffected (those two tables carry their own warehouse_id/owner_account_id columns and were never gated through app.wms_outbound_orders'' own RLS to begin with).'
do $$
declare
  v_ship_a_id uuid := (select id from app.wms_outbound_shipments where idempotency_key = 'idem-ship-a');
  v_ship_d_id uuid := (select id from app.wms_outbound_shipments where idempotency_key = 'idem-ship-d');
begin
  set local role authenticated;
  perform set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-000000200207", "role": "authenticated"}', true);

  if exists (select 1 from app.wms_outbound_shipments where id = v_ship_d_id) then
    raise exception 'assertion failed: raw RLS leak -- customer_alpha directly selected a Beta-owned shipment row';
  end if;
  if not exists (select 1 from app.wms_outbound_shipments where id = v_ship_a_id) then
    raise exception 'assertion failed: expected RLS to still permit customer_alpha to directly select Alpha''s own SH-A row';
  end if;
  if exists (select 1 from app.wms_billing_eligibility_events where shipment_id = v_ship_d_id) then
    raise exception 'assertion failed: raw RLS leak on app.wms_billing_eligibility_events -- customer_alpha directly selected a Beta-owned event row';
  end if;

  reset role;
end $$;

\echo '>> cross-tenant isolation: tenant2''s rep, who holds zero membership in tenant1, is rejected insufficient_authority on every mutation/read against tenant1''s real records; regression: every idempotent-replay short-circuit runs strictly after authority/tenant-scope is confirmed (bug class a)'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'wmsoutx1');
  v_order_a_id uuid := (select id from app.wms_outbound_orders where tenant_id = v_tenant1 and idempotency_key = 'idem-out-a');
  v_ship_a_id uuid := (select id from app.wms_outbound_shipments where tenant_id = v_tenant1 and idempotency_key = 'idem-ship-a');
  v_pkg_a1_id uuid := (select id from app.wms_packages where tenant_id = v_tenant1 and idempotency_key = 'idem-out-pack-a1-pkg');
  v_tenant2_rep uuid := '00000000-0000-0000-0000-000000200209';
begin
  begin
    -- Reuses a REAL, already-consumed tenant1 idempotency key -- must still be rejected
    -- on authority grounds, never silently short-circuited into tenant1's real data
    -- (bug class a regression).
    perform app.create_wms_outbound_shipment(v_order_a_id, 'idem-ship-a', v_tenant2_rep, 'rep2b');
    raise exception 'assertion failed: expected insufficient_authority for a tenant2 actor against a tenant1 order';
  exception
    when others then
      if sqlerrm not like 'insufficient_authority%' then raise; end if;
  end;

  begin
    perform app.add_package_to_shipment(v_ship_a_id, v_pkg_a1_id, 'idem-ship-a-add', v_tenant2_rep, 'rep2b');
    raise exception 'assertion failed: expected insufficient_authority for a tenant2 actor';
  exception
    when others then
      if sqlerrm not like 'insufficient_authority%' then raise; end if;
  end;

  begin
    -- ISS-2026-146: tenant2's rep (wmsoutx2) holds no membership in wmsoutx1, so app.get_wms_outbound_shipment
    -- now collapses that zero-membership case into its own generic
    -- shipment_not_found / no_data_found branch -- byte-identical to what a
    -- nonexistent id already produced, so the real tenant_id is never disclosed to an
    -- outsider. A genuine same-tenant member lacking the role still gets
    -- insufficient_authority, unchanged (asserted elsewhere in this file).
    perform app.get_wms_outbound_shipment(v_ship_a_id, v_tenant2_rep);
    raise exception 'assertion failed: expected shipment_not_found for a tenant2 actor reading a tenant1 shipment';
  exception
    when others then
      if sqlerrm not like 'shipment_not_found%' then raise; end if;
  end;
end $$;

\echo '>> bounded/filtered reads: app.list_wms_outbound_shipments p_limit defaults to 50 and hard-caps at 200; explicit status/outbound_order filters narrow correctly'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'wmsoutx1');
  v_order_a_id uuid := (select id from app.wms_outbound_orders where tenant_id = v_tenant1 and idempotency_key = 'idem-out-a');
  v_rows app.wms_outbound_shipments[];
begin
  select array_agg(s) into v_rows from app.list_wms_outbound_shipments(v_tenant1, '00000000-0000-0000-0000-000000200202', null, null, null, null, 500) s;
  if array_length(v_rows, 1) > 200 then
    raise exception 'assertion failed: expected the hard cap of 200 rows to apply even when p_limit=500';
  end if;

  select array_agg(s) into v_rows from app.list_wms_outbound_shipments(v_tenant1, '00000000-0000-0000-0000-000000200202', v_order_a_id, null, null, 'shipped') s;
  if array_length(v_rows, 1) <> 1 or v_rows[1].outbound_order_id <> v_order_a_id then
    raise exception 'assertion failed: expected exactly one shipped shipment for order A under the explicit filter';
  end if;
end $$;

\echo '>> schema-privilege defense in depth (ERR-2026-004): anon holds no direct table/EXECUTE access; authenticated has RLS-scoped SELECT but no direct INSERT/UPDATE/DELETE; only service_role may write directly'
do $$
declare
  v_has_priv boolean;
begin
  select has_table_privilege('anon', 'app.wms_outbound_shipments', 'SELECT') into v_has_priv;
  if v_has_priv then
    raise exception 'assertion failed: anon must not hold SELECT on app.wms_outbound_shipments';
  end if;

  select has_function_privilege('anon', 'app.ship_confirm_wms_outbound_shipment(uuid, text, text, boolean, text, text, integer, uuid, text)', 'EXECUTE') into v_has_priv;
  if v_has_priv then
    raise exception 'assertion failed: anon must not hold EXECUTE on app.ship_confirm_wms_outbound_shipment';
  end if;

  select has_table_privilege('authenticated', 'app.wms_outbound_shipments', 'SELECT') into v_has_priv;
  if not v_has_priv then
    raise exception 'assertion failed: authenticated must hold RLS-scoped SELECT on app.wms_outbound_shipments';
  end if;
  select has_table_privilege('authenticated', 'app.wms_outbound_shipments', 'INSERT') into v_has_priv;
  if v_has_priv then
    raise exception 'assertion failed: authenticated must NOT hold direct INSERT on app.wms_outbound_shipments -- writes only via SECURITY DEFINER RPCs';
  end if;

  select has_table_privilege('service_role', 'app.wms_outbound_shipments', 'INSERT') into v_has_priv;
  if not v_has_priv then
    raise exception 'assertion failed: service_role must hold direct INSERT on app.wms_outbound_shipments';
  end if;
end $$;
