-- Real, executable test evidence for ATW-018 (CG-S10-ATW-018, Prompt 237 WMS
-- Packing) -- run via `pnpm run db:test` against a real, disposable Postgres
-- database.

\set ON_ERROR_STOP on

\echo '>> setup: one tenant (wmspack1), a company org unit, a rep (OPS:Create/Edit/View), a second rep for the concurrency race, a supervisor (OPS:Create/Edit/View/Override), an OPS:View-only viewer, a global Supreme Admin, two owner accounts (Alpha, Beta) under tenant1 via the full CRM->Job Order pipeline, a customer_user-layer actor scoped to Account Alpha only (mirrors advanced-tms-wms-picking.sql''s own cross-owner pattern), one warehouse (WH-PACK-1) with a pick-enabled rack and a staging location, and item masters (plain, lot-controlled, serial-controlled, one Beta-owned item). Tenant2 (wmspack2): an isolated rep, for cross-tenant leakage checks.'
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
    ('00000000-0000-0000-0000-000000190201', 'admin@wmspack1.test'),
    ('00000000-0000-0000-0000-000000190202', 'rep@wmspack1.test'),
    ('00000000-0000-0000-0000-000000190203', 'rep2@wmspack1.test'),
    ('00000000-0000-0000-0000-000000190204', 'supervisor@wmspack1.test'),
    ('00000000-0000-0000-0000-000000190205', 'viewer@wmspack1.test'),
    ('00000000-0000-0000-0000-000000190206', 'supreme@wmspack1.test'),
    ('00000000-0000-0000-0000-000000190207', 'customer-alpha@wmspack1.test'),
    ('00000000-0000-0000-0000-000000190208', 'admin2@wmspack2.test'),
    ('00000000-0000-0000-0000-000000190209', 'rep2b@wmspack2.test');

  perform app.grant_principal_membership('00000000-0000-0000-0000-000000190206', 'supreme_admin', null, null, 'tester');

  perform app.provision_tenant('wmspack1', 'WMS Packing Tenant One', 'idem-wmspack1', 'tester');
  v_tenant1 := (select id from app.tenants where slug = 'wmspack1');
  perform app.transition_tenant_status(v_tenant1, 'active', 'setup', 'tester');
  perform app.create_org_unit(v_tenant1, 'company', null, 'WMSPACK1-CO', 'WMS Packing Tenant One Co', 'tester');
  v_company := (select id from app.org_units where tenant_id = v_tenant1 and code = 'WMSPACK1-CO');

  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000190201', 'admin@wmspack1.test', 'WmsPack Admin', v_company, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'admin@wmspack1.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000190201', 'tenant_admin', v_tenant1, null, 'tester');

  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000190202', 'rep@wmspack1.test', 'WmsPack Rep', v_company, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'rep@wmspack1.test'), 'active', 'onboarded', 'tester');

  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000190203', 'rep2@wmspack1.test', 'WmsPack Rep Two', v_company, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'rep2@wmspack1.test'), 'active', 'onboarded', 'tester');

  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000190205', 'viewer@wmspack1.test', 'WmsPack Viewer', v_company, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'viewer@wmspack1.test'), 'active', 'onboarded', 'tester');

  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000190204', 'supervisor@wmspack1.test', 'WmsPack Supervisor', v_company, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'supervisor@wmspack1.test'), 'active', 'onboarded', 'tester');

  -- The rep role holds OPS Create/Edit/View together -- every packing mutation this
  -- migration defines composes at least one of these three top-level gates, and
  -- app.generate_wms_pick_task/app.confirm_wms_pick_task (this fixture's own upstream,
  -- ATW-017) require the identical trio to build up real picked_quantity to pack.
  v_rep_role := (app.create_role(v_tenant1, 'WmsPack Rep Role', 'full commercial + ops create/edit/view', 'tester')).id;
  v_rep_draft := app.create_role_version(v_rep_role, 'tester');
  perform app.set_role_version_permissions(
    v_rep_draft.id,
    array(select id from app.permissions where (resource_module_code = 'COM' and action in ('Create', 'Edit', 'Approve', 'View', 'View cost'))
      or (resource_module_code = 'OPS' and action in ('Create', 'Edit', 'View'))),
    'tester'
  );
  perform app.publish_role_version(v_rep_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_rep_role and status = 'published'), '00000000-0000-0000-0000-000000190202', '00000000-0000-0000-0000-000000190201', 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_rep_role and status = 'published'), '00000000-0000-0000-0000-000000190203', '00000000-0000-0000-0000-000000190201', 'tester');

  v_supervisor_role := (app.create_role(v_tenant1, 'WmsPack Supervisor Role', 'ops create/edit/view/override', 'tester')).id;
  v_supervisor_draft := app.create_role_version(v_supervisor_role, 'tester');
  perform app.set_role_version_permissions(
    v_supervisor_draft.id,
    array(select id from app.permissions where resource_module_code = 'OPS' and action in ('Create', 'Edit', 'View', 'Override')),
    'tester'
  );
  perform app.publish_role_version(v_supervisor_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_supervisor_role and status = 'published'), '00000000-0000-0000-0000-000000190204', '00000000-0000-0000-0000-000000190201', 'tester');

  v_viewer_role := (app.create_role(v_tenant1, 'WmsPack Viewer Role', 'OPS:View only', 'tester')).id;
  v_viewer_draft := app.create_role_version(v_viewer_role, 'tester');
  perform app.set_role_version_permissions(v_viewer_draft.id, array(select id from app.permissions where resource_module_code = 'OPS' and action = 'View'), 'tester');
  perform app.publish_role_version(v_viewer_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_viewer_role and status = 'published'), '00000000-0000-0000-0000-000000190205', '00000000-0000-0000-0000-000000190201', 'tester');

  v_warehouse := app.create_warehouse(v_tenant1, v_company, 'WH-PACK-1', 'WMS Packing Warehouse 1', 'Jl. Packing 1', 'Asia/Jakarta', null, array['land']::text[], '00000000-0000-0000-0000-000000190202', 'rep');
  declare
    v_rack app.warehouse_locations;
    v_stage app.warehouse_locations;
  begin
    v_rack := app.create_warehouse_location(v_warehouse.id, null, null, 'RACK-PACK-A', 'Packing Source Rack A', 'rack', 1, null, null, null, null, null, true, false, '00000000-0000-0000-0000-000000190202', 'rep');
    perform app.set_warehouse_location_status(v_rack.id, 'active', null, v_rack.record_version, '00000000-0000-0000-0000-000000190202', 'rep');
    v_stage := app.create_warehouse_location(v_warehouse.id, null, null, 'STAGE-PACK-1', 'Packing Staging 1', 'staging', 2, null, null, null, null, null, false, false, '00000000-0000-0000-0000-000000190202', 'rep');
    perform app.set_warehouse_location_status(v_stage.id, 'active', null, v_stage.record_version, '00000000-0000-0000-0000-000000190202', 'rep');
  end;

  -- Account Alpha, via the full CRM->Job Order pipeline (mirrors advanced-tms-wms-
  -- picking.sql''s own precedent).
  perform app.capture_lead(v_tenant1, 'manual', null, 'WmsPack Customer Alpha', 'Alice WmsPack', 'alice@wmspack237.test', '0811',
    '00000000-0000-0000-0000-000000190202', v_company, '00000000-0000-0000-0000-000000190202', 'tester');
  select * into v_lead from app.leads where email = 'alice@wmspack237.test';
  perform app.qualify_lead(v_lead.id, v_lead.record_version, '00000000-0000-0000-0000-000000190202', 'tester');
  select * into v_lead from app.leads where id = v_lead.id;
  perform app.convert_lead_to_prospect(v_lead.id, 'WmsPack Customer Alpha', 'WMSPACK237A', '11.111.111.16-111.000',
    jsonb_build_object('line1', 'Jl. Packing Alpha 12', 'city', 'Jakarta', 'country', 'ID'),
    '00000000-0000-0000-0000-000000190202', 'tester');
  select * into v_prospect from app.prospects where lead_id = v_lead.id;
  select * into v_contact from app.create_contact(v_tenant1, 'Alice WmsPack Ops', 'Ops Lead', 'alice@wmspack237.test', '0811', '00000000-0000-0000-0000-000000190202', v_company, '00000000-0000-0000-0000-000000190202', 'tester');
  perform app.link_contact_to_record(v_contact.id, 'prospect', v_prospect.id, 'primary', true, '00000000-0000-0000-0000-000000190202', 'tester');
  select * into v_opportunity from app.create_opportunity(
    v_tenant1, v_prospect.id, 'WMSPACK237 Alpha lane',
    jsonb_build_object('service_type', 'land_freight', 'cargo_description', 'General cargo', 'origin', 'Jakarta', 'destination', 'Surabaya', 'target_ready_date', '2026-08-01'),
    '00000000-0000-0000-0000-000000190202', v_company, '00000000-0000-0000-0000-000000190202', 'tester'
  );
  select * into v_request from app.request_costing(v_opportunity.id, '[]'::jsonb, null, '00000000-0000-0000-0000-000000190202', 'tester');
  select * into v_rate from app.create_rate_version(
    v_tenant1, 'VENDOR-WMSPACK237-A', 'Contoso WmsPack237 Line', 'land_freight', 'FTL', 'Jakarta', 'Surabaya', '20ft',
    null, null, null, null, 'IDR', 5000000, null, '[]'::jsonb, now(), null, null, '00000000-0000-0000-0000-000000190201', 'tester'
  );
  perform app.approve_rate_version(v_rate.id, v_rate.record_version, '00000000-0000-0000-0000-000000190201', 'tester');
  select * into v_selection from app.select_vendor_rate(v_request.id, v_rate.id, false, null, null, null, '00000000-0000-0000-0000-000000190202', 'tester');
  v_rule := app.create_margin_rule_version(v_tenant1, 20.00, 'half_up', '00000000-0000-0000-0000-000000190202', 'tester');
  perform app.publish_margin_rule_version(v_rule.id, v_rule.record_version, null, '00000000-0000-0000-0000-000000190202', 'tester');
  perform app.calculate_margin(v_selection.id, 6000000, 'IDR', 0, '00000000-0000-0000-0000-000000190202', 'tester');
  select id into v_calc_id from app.margin_calculations where rate_selection_id = v_selection.id and is_current;
  select * into v_quote from app.create_quotation_draft(v_tenant1, v_opportunity.id, 'IDR', now() + interval '14 days', v_contact.id, null, null, '00000000-0000-0000-0000-000000190202', 'tester');
  perform app.add_quotation_line(v_quote.id, v_quote.record_version, 'service', 'WMSPACK237 Alpha lane', v_calc_id, 1, 6000000, 0, 0, '00000000-0000-0000-0000-000000190202', 'tester');
  select * into v_quote from app.quotations where id = v_quote.id;
  perform app.submit_quotation(v_quote.id, v_quote.record_version, '00000000-0000-0000-0000-000000190202', 'tester');
  select * into v_send from app.send_quotation_for_acceptance(v_quote.id, null, 'email', '00000000-0000-0000-0000-000000190202', 'tester');
  perform app.record_quotation_customer_decision(v_send.raw_token, 'accepted', 'Alice WmsPack Ops', null, null, null, null, null);
  select * into v_quote from app.quotations where id = v_quote.id;
  select * into v_account_alpha from app.convert_quotation_to_account(v_quote.id, null, null, '00000000-0000-0000-0000-000000190202', 'rep');

  -- Account Beta, a second owner account in the SAME tenant -- cross-owner isolation.
  perform app.capture_lead(v_tenant1, 'manual', null, 'WmsPack Customer Beta', 'Bob WmsPack', 'bob@wmspack237.test', '0812',
    '00000000-0000-0000-0000-000000190202', v_company, '00000000-0000-0000-0000-000000190202', 'tester');
  select * into v_lead from app.leads where email = 'bob@wmspack237.test';
  perform app.qualify_lead(v_lead.id, v_lead.record_version, '00000000-0000-0000-0000-000000190202', 'tester');
  select * into v_lead from app.leads where id = v_lead.id;
  perform app.convert_lead_to_prospect(v_lead.id, 'WmsPack Customer Beta', 'WMSPACK237B', '11.111.111.17-111.000',
    jsonb_build_object('line1', 'Jl. Packing Beta 13', 'city', 'Jakarta', 'country', 'ID'),
    '00000000-0000-0000-0000-000000190202', 'tester');
  select * into v_prospect from app.prospects where lead_id = v_lead.id;
  select * into v_contact from app.create_contact(v_tenant1, 'Bob WmsPack Ops', 'Ops Lead', 'bob@wmspack237.test', '0812', '00000000-0000-0000-0000-000000190202', v_company, '00000000-0000-0000-0000-000000190202', 'tester');
  perform app.link_contact_to_record(v_contact.id, 'prospect', v_prospect.id, 'primary', true, '00000000-0000-0000-0000-000000190202', 'tester');
  select * into v_opportunity from app.create_opportunity(
    v_tenant1, v_prospect.id, 'WMSPACK237 Beta lane',
    jsonb_build_object('service_type', 'land_freight', 'cargo_description', 'General cargo', 'origin', 'Jakarta', 'destination', 'Surabaya', 'target_ready_date', '2026-08-01'),
    '00000000-0000-0000-0000-000000190202', v_company, '00000000-0000-0000-0000-000000190202', 'tester'
  );
  select * into v_request from app.request_costing(v_opportunity.id, '[]'::jsonb, null, '00000000-0000-0000-0000-000000190202', 'tester');
  select * into v_rate from app.create_rate_version(
    v_tenant1, 'VENDOR-WMSPACK237-B', 'Contoso WmsPack237 Line B', 'land_freight', 'FTL', 'Jakarta', 'Surabaya', '20ft',
    null, null, null, null, 'IDR', 5000000, null, '[]'::jsonb, now(), null, null, '00000000-0000-0000-0000-000000190201', 'tester'
  );
  perform app.approve_rate_version(v_rate.id, v_rate.record_version, '00000000-0000-0000-0000-000000190201', 'tester');
  select * into v_selection from app.select_vendor_rate(v_request.id, v_rate.id, false, null, null, null, '00000000-0000-0000-0000-000000190202', 'tester');
  perform app.calculate_margin(v_selection.id, 6000000, 'IDR', 0, '00000000-0000-0000-0000-000000190202', 'tester');
  select id into v_calc_id from app.margin_calculations where rate_selection_id = v_selection.id and is_current;
  select * into v_quote from app.create_quotation_draft(v_tenant1, v_opportunity.id, 'IDR', now() + interval '14 days', v_contact.id, null, null, '00000000-0000-0000-0000-000000190202', 'tester');
  perform app.add_quotation_line(v_quote.id, v_quote.record_version, 'service', 'WMSPACK237 Beta lane', v_calc_id, 1, 6000000, 0, 0, '00000000-0000-0000-0000-000000190202', 'tester');
  select * into v_quote from app.quotations where id = v_quote.id;
  perform app.submit_quotation(v_quote.id, v_quote.record_version, '00000000-0000-0000-0000-000000190202', 'tester');
  select * into v_send from app.send_quotation_for_acceptance(v_quote.id, null, 'email', '00000000-0000-0000-0000-000000190202', 'tester');
  perform app.record_quotation_customer_decision(v_send.raw_token, 'accepted', 'Bob WmsPack Ops', null, null, null, null, null);
  select * into v_quote from app.quotations where id = v_quote.id;
  select * into v_account_beta from app.convert_quotation_to_account(v_quote.id, null, null, '00000000-0000-0000-0000-000000190202', 'rep');

  perform app.create_item_master(v_tenant1, v_account_alpha.id, 'SKU-PACK-PLAIN', 'Pack Plain Widget', null, 'PCS', false, false, false, '00000000-0000-0000-0000-000000190202', 'rep');
  perform app.create_item_master(v_tenant1, v_account_alpha.id, 'SKU-PACK-LOT', 'Pack Lot Widget', null, 'PCS', true, false, true, '00000000-0000-0000-0000-000000190202', 'rep');
  perform app.create_item_master(v_tenant1, v_account_alpha.id, 'SKU-PACK-SERIAL', 'Pack Serial Widget', null, 'PCS', false, true, false, '00000000-0000-0000-0000-000000190202', 'rep');
  perform app.create_item_master(v_tenant1, v_account_beta.id, 'SKU-PACK-BETA', 'Pack Beta Widget', null, 'PCS', false, false, false, '00000000-0000-0000-0000-000000190202', 'rep');

  -- The customer_user-layer actor is invited with a NULL org_unit_id -- the ONLY path
  -- by which it can ever pass app.can_access_record's row filter is real org-unit
  -- membership it does not have here, so app.actor_can_view_owner_scoped_row's own
  -- customer_account_ref match (ATW-016) is the real, sole gate tested below.
  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000190207', 'customer-alpha@wmspack1.test', 'Customer Alpha Portal', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'customer-alpha@wmspack1.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000190207', 'customer_user', v_tenant1, v_account_alpha.id::text, 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_viewer_role and status = 'published'), '00000000-0000-0000-0000-000000190207', '00000000-0000-0000-0000-000000190201', 'tester');

  -- Tenant2: fully isolated -- exists only to prove cross-tenant scope safety.
  perform app.provision_tenant('wmspack2', 'WMS Packing Tenant Two', 'idem-wmspack2', 'tester');
  v_tenant2 := (select id from app.tenants where slug = 'wmspack2');
  perform app.transition_tenant_status(v_tenant2, 'active', 'setup', 'tester');
  perform app.create_org_unit(v_tenant2, 'company', null, 'WMSPACK2-CO', 'WMS Packing Tenant Two Co', 'tester');
  v_company2 := (select id from app.org_units where tenant_id = v_tenant2 and code = 'WMSPACK2-CO');
  perform app.invite_user(v_tenant2, '00000000-0000-0000-0000-000000190208', 'admin2@wmspack2.test', 'Tenant2 Admin', v_company2, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'admin2@wmspack2.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000190208', 'tenant_admin', v_tenant2, null, 'tester');
  perform app.invite_user(v_tenant2, '00000000-0000-0000-0000-000000190209', 'rep2b@wmspack2.test', 'Tenant2 Rep', v_company2, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'rep2b@wmspack2.test'), 'active', 'onboarded', 'tester');
  v_rep2_role := (app.create_role(v_tenant2, 'Tenant2 Rep Role', 'ops create/edit/view', 'tester')).id;
  v_rep2_draft := app.create_role_version(v_rep2_role, 'tester');
  perform app.set_role_version_permissions(v_rep2_draft.id, array(select id from app.permissions where resource_module_code = 'OPS' and action in ('Create', 'Edit', 'View')), 'tester');
  perform app.publish_role_version(v_rep2_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant2, (select id from app.role_versions where role_id = v_rep2_role and status = 'published'), '00000000-0000-0000-0000-000000190209', '00000000-0000-0000-0000-000000190208', 'tester');
end $$;

-- Test-fixture-only helper (never part of the real migration): generates, claims and
-- fully confirms one real ATW-017 pick task in one call, so the fixture below can build
-- up genuine picked_quantity across many lines without repeating the same three-call
-- sequence ten times. PL/pgSQL does not support a procedure/function declared inline
-- inside a DO block's own declare section, so this is a real, disposable top-level
-- procedure created before the DO block that calls it (dropped implicitly with the
-- disposable test database itself).
create procedure pick_fully(p_line_id uuid, p_item_master_id uuid, p_qty numeric, p_lot text, p_serial text, p_rack_id uuid, p_stage_id uuid, p_idem_prefix text)
language plpgsql
as $proc$
declare
  v_t app.wms_pick_tasks;
begin
  v_t := app.generate_wms_pick_task(p_line_id, p_qty, null, p_rack_id, p_lot, p_serial, p_stage_id, p_idem_prefix || '-gen', '00000000-0000-0000-0000-000000190202', 'rep');
  v_t := app.claim_wms_pick_task(v_t.id, v_t.record_version, '00000000-0000-0000-0000-000000190202', 'rep');
  perform app.confirm_wms_pick_task(v_t.id, p_qty, p_rack_id, p_item_master_id, p_lot, p_serial, p_stage_id, p_idem_prefix || '-conf', v_t.record_version, '00000000-0000-0000-0000-000000190202', 'rep');
end;
$proc$;

\echo '>> build confirmed Alpha/Beta outbound orders, generate/claim/confirm real ATW-017 pick tasks to produce genuine picked_quantity to pack against, plus one draft (never confirmed) Alpha order for the outbound_order_not_confirmed test'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'wmspack1');
  v_warehouse_id uuid := (select id from app.warehouses where tenant_id = v_tenant1 and code = 'WH-PACK-1');
  v_rack_id uuid := (select id from app.warehouse_locations where tenant_id = v_tenant1 and code = 'RACK-PACK-A');
  v_stage_id uuid := (select id from app.warehouse_locations where tenant_id = v_tenant1 and code = 'STAGE-PACK-1');
  v_account_alpha_id uuid := (select id from app.accounts where tenant_id = v_tenant1 and legal_name = 'WmsPack Customer Alpha');
  v_account_beta_id uuid := (select id from app.accounts where tenant_id = v_tenant1 and legal_name = 'WmsPack Customer Beta');
  v_plain_id uuid := (select id from app.item_masters where tenant_id = v_tenant1 and code = 'SKU-PACK-PLAIN');
  v_lot_id uuid := (select id from app.item_masters where tenant_id = v_tenant1 and code = 'SKU-PACK-LOT');
  v_serial_id uuid := (select id from app.item_masters where tenant_id = v_tenant1 and code = 'SKU-PACK-SERIAL');
  v_beta_item_id uuid := (select id from app.item_masters where tenant_id = v_tenant1 and code = 'SKU-PACK-BETA');
  v_order app.wms_outbound_orders;
  v_second_order app.wms_outbound_orders;
  v_beta_order app.wms_outbound_orders;
  v_draft_order app.wms_outbound_orders;
  v_lines app.wms_outbound_order_lines[];
  v_line app.wms_outbound_order_lines;
  v_line_id uuid;
  v_task app.wms_pick_tasks;
begin
  v_order := app.create_manual_wms_outbound_order(v_tenant1, v_warehouse_id, v_account_alpha_id, 'main packing fixture', 'idem-pack-main', null, '00000000-0000-0000-0000-000000190202', 'rep');
  select array_agg(l) into v_lines from app.add_wms_outbound_order_lines(
    v_order.id,
    jsonb_build_array(
      jsonb_build_object('item_master_id', v_plain_id, 'requested_uom_code', 'PCS', 'requested_quantity', 50, 'notes', 'L1 main confirm flow (root + nested child)'),
      jsonb_build_object('item_master_id', v_plain_id, 'requested_uom_code', 'PCS', 'requested_quantity', 20, 'notes', 'L2 concurrency race'),
      jsonb_build_object('item_master_id', v_plain_id, 'requested_uom_code', 'PCS', 'requested_quantity', 5, 'notes', 'L3 over-pack rejection'),
      jsonb_build_object('item_master_id', v_lot_id, 'requested_uom_code', 'PCS', 'requested_quantity', 8, 'notes', 'L4 lot-controlled scan verification'),
      jsonb_build_object('item_master_id', v_serial_id, 'requested_uom_code', 'PCS', 'requested_quantity', 1, 'notes', 'L5 serial-controlled scan verification'),
      jsonb_build_object('item_master_id', v_plain_id, 'requested_uom_code', 'PCS', 'requested_quantity', 20, 'notes', 'L6 partial pick (only 10 of 20) -- remove-line tests'),
      jsonb_build_object('item_master_id', v_plain_id, 'requested_uom_code', 'PCS', 'requested_quantity', 5, 'notes', 'L7 nested child package contents'),
      jsonb_build_object('item_master_id', v_plain_id, 'requested_uom_code', 'PCS', 'requested_quantity', 5, 'notes', 'L8 hierarchy-chain package contents'),
      jsonb_build_object('item_master_id', v_plain_id, 'requested_uom_code', 'PCS', 'requested_quantity', 3, 'notes', 'L9 staged-confirm-rejection package contents')
    ),
    '00000000-0000-0000-0000-000000190202', 'rep'
  ) l;
  if array_length(v_lines, 1) <> 9 then
    raise exception 'assertion failed: expected exactly 9 lines on the main outbound order, got %', array_length(v_lines, 1);
  end if;
  v_order := app.confirm_wms_outbound_order(v_order.id, v_order.record_version, '00000000-0000-0000-0000-000000190202', 'rep');

  v_second_order := app.create_manual_wms_outbound_order(v_tenant1, v_warehouse_id, v_account_alpha_id, 'second alpha order (wrong_order fixture)', 'idem-pack-second', null, '00000000-0000-0000-0000-000000190202', 'rep');
  v_line := app.add_wms_outbound_order_line(v_second_order.id, v_plain_id, 'PCS', 5, 'S1 wrong_order fixture', '00000000-0000-0000-0000-000000190202', 'rep');
  v_second_order := app.confirm_wms_outbound_order(v_second_order.id, v_second_order.record_version, '00000000-0000-0000-0000-000000190202', 'rep');

  v_beta_order := app.create_manual_wms_outbound_order(v_tenant1, v_warehouse_id, v_account_beta_id, 'beta packing fixture', 'idem-pack-beta', null, '00000000-0000-0000-0000-000000190202', 'rep');
  v_line := app.add_wms_outbound_order_line(v_beta_order.id, v_beta_item_id, 'PCS', 12, 'B1 cross-owner fixture', '00000000-0000-0000-0000-000000190202', 'rep');
  v_beta_order := app.confirm_wms_outbound_order(v_beta_order.id, v_beta_order.record_version, '00000000-0000-0000-0000-000000190202', 'rep');

  -- Never confirmed -- the outbound_order_not_confirmed fixture for app.start_wms_packing_task.
  v_draft_order := app.create_manual_wms_outbound_order(v_tenant1, v_warehouse_id, v_account_alpha_id, 'never confirmed', 'idem-pack-draft', null, '00000000-0000-0000-0000-000000190202', 'rep');
  perform app.add_wms_outbound_order_line(v_draft_order.id, v_plain_id, 'PCS', 1, null, '00000000-0000-0000-0000-000000190202', 'rep');

  -- Real opening_balance inventory, enough for every scenario line.
  perform app.post_inventory_movement(v_tenant1, v_warehouse_id, 'opening_balance', 'opening_balance', null, 'idem-pack-open-plain', 'opening balance fixture',
    jsonb_build_array(jsonb_build_object('owner_account_id', v_account_alpha_id, 'item_master_id', v_plain_id, 'location_id', v_rack_id, 'uom_code', 'PCS', 'signed_quantity', 200, 'status', 'on_hand')),
    '00000000-0000-0000-0000-000000190202', 'rep');
  perform app.post_inventory_movement(v_tenant1, v_warehouse_id, 'opening_balance', 'opening_balance', null, 'idem-pack-open-lot', 'opening balance fixture',
    jsonb_build_array(jsonb_build_object('owner_account_id', v_account_alpha_id, 'item_master_id', v_lot_id, 'location_id', v_rack_id, 'uom_code', 'PCS', 'signed_quantity', 8, 'lot_number', 'LOT-PACK-A', 'expiry_date', (current_date + 30)::text, 'status', 'on_hand')),
    '00000000-0000-0000-0000-000000190202', 'rep');
  perform app.post_inventory_movement(v_tenant1, v_warehouse_id, 'opening_balance', 'opening_balance', null, 'idem-pack-open-serial', 'opening balance fixture',
    jsonb_build_array(jsonb_build_object('owner_account_id', v_account_alpha_id, 'item_master_id', v_serial_id, 'location_id', v_rack_id, 'uom_code', 'PCS', 'signed_quantity', 1, 'serial_number', 'SN-PACK-A', 'status', 'on_hand')),
    '00000000-0000-0000-0000-000000190202', 'rep');
  perform app.post_inventory_movement(v_tenant1, v_warehouse_id, 'opening_balance', 'opening_balance', null, 'idem-pack-open-beta', 'opening balance fixture',
    jsonb_build_array(jsonb_build_object('owner_account_id', v_account_beta_id, 'item_master_id', v_beta_item_id, 'location_id', v_rack_id, 'uom_code', 'PCS', 'signed_quantity', 12, 'status', 'on_hand')),
    '00000000-0000-0000-0000-000000190202', 'rep');

  -- Real ATW-017 generate/claim/confirm, producing genuine picked_quantity.
  select l.id into v_line_id from app.wms_outbound_order_lines l where outbound_order_id = v_order.id and line_number = 1;
  call pick_fully(v_line_id, v_plain_id, 50, null, null, v_rack_id, v_stage_id, 'idem-pack-pick-l1');
  select l.id into v_line_id from app.wms_outbound_order_lines l where outbound_order_id = v_order.id and line_number = 2;
  call pick_fully(v_line_id, v_plain_id, 20, null, null, v_rack_id, v_stage_id, 'idem-pack-pick-l2');
  select l.id into v_line_id from app.wms_outbound_order_lines l where outbound_order_id = v_order.id and line_number = 3;
  call pick_fully(v_line_id, v_plain_id, 5, null, null, v_rack_id, v_stage_id, 'idem-pack-pick-l3');
  select l.id into v_line_id from app.wms_outbound_order_lines l where outbound_order_id = v_order.id and line_number = 4;
  call pick_fully(v_line_id, v_lot_id, 8, 'LOT-PACK-A', null, v_rack_id, v_stage_id, 'idem-pack-pick-l4');
  select l.id into v_line_id from app.wms_outbound_order_lines l where outbound_order_id = v_order.id and line_number = 5;
  call pick_fully(v_line_id, v_serial_id, 1, null, 'SN-PACK-A', v_rack_id, v_stage_id, 'idem-pack-pick-l5');
  select l.id into v_line_id from app.wms_outbound_order_lines l where outbound_order_id = v_order.id and line_number = 7;
  call pick_fully(v_line_id, v_plain_id, 5, null, null, v_rack_id, v_stage_id, 'idem-pack-pick-l7');
  select l.id into v_line_id from app.wms_outbound_order_lines l where outbound_order_id = v_order.id and line_number = 8;
  call pick_fully(v_line_id, v_plain_id, 5, null, null, v_rack_id, v_stage_id, 'idem-pack-pick-l8');
  select l.id into v_line_id from app.wms_outbound_order_lines l where outbound_order_id = v_order.id and line_number = 9;
  call pick_fully(v_line_id, v_plain_id, 3, null, null, v_rack_id, v_stage_id, 'idem-pack-pick-l9');
  select l.id into v_line_id from app.wms_outbound_order_lines l where outbound_order_id = v_second_order.id and line_number = 1;
  call pick_fully(v_line_id, v_plain_id, 5, null, null, v_rack_id, v_stage_id, 'idem-pack-pick-s1');
  select l.id into v_line_id from app.wms_outbound_order_lines l where outbound_order_id = v_beta_order.id and line_number = 1;
  call pick_fully(v_line_id, v_beta_item_id, 12, null, null, v_rack_id, v_stage_id, 'idem-pack-pick-b1');

  -- L6: only 10 of the requested 20 is actually picked -- a real partial pick, used to
  -- exercise remaining-packable precision and remove-line tests.
  v_line := (select l from app.wms_outbound_order_lines l where outbound_order_id = v_order.id and line_number = 6);
  v_task := app.generate_wms_pick_task(v_line.id, 20, null, v_rack_id, null, null, v_stage_id, 'idem-pack-pick-l6-gen', '00000000-0000-0000-0000-000000190202', 'rep');
  v_task := app.claim_wms_pick_task(v_task.id, v_task.record_version, '00000000-0000-0000-0000-000000190202', 'rep');
  v_task := app.confirm_wms_pick_task(v_task.id, 10, v_rack_id, v_plain_id, null, null, v_stage_id, 'idem-pack-pick-l6-conf', v_task.record_version, '00000000-0000-0000-0000-000000190202', 'rep');
  if v_task.picked_quantity <> 10 or v_task.status <> 'partial' then
    raise exception 'assertion failed: expected L6''s own task to be a real partial pick (picked=10 of 20), got picked=%/status=%', v_task.picked_quantity, v_task.status;
  end if;
end $$;

\echo '>> app.start_wms_packing_task: viewer rejected; outbound_order_not_found; outbound_order_not_confirmed (draft order); success; idempotent on idempotency_key AND on unique (tenant_id, outbound_order_id) -- one packing task per order'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'wmspack1');
  v_order_id uuid := (select id from app.wms_outbound_orders where tenant_id = v_tenant1 and idempotency_key = 'idem-pack-main');
  v_draft_order_id uuid := (select id from app.wms_outbound_orders where tenant_id = v_tenant1 and idempotency_key = 'idem-pack-draft');
  v_task app.wms_packing_tasks;
  v_replay app.wms_packing_tasks;
  v_replay_other_key app.wms_packing_tasks;
begin
  begin
    perform app.start_wms_packing_task(v_order_id, 'idem-packtask-viewer', '00000000-0000-0000-0000-000000190205', 'viewer');
    raise exception 'assertion failed: expected insufficient_authority -- viewer holds OPS:View only';
  exception
    when others then
      if sqlerrm not like 'insufficient_authority%' then raise; end if;
  end;

  begin
    perform app.start_wms_packing_task(gen_random_uuid(), 'idem-packtask-badorder', '00000000-0000-0000-0000-000000190202', 'rep');
    raise exception 'assertion failed: expected outbound_order_not_found';
  exception
    when others then
      if sqlerrm not like 'outbound_order_not_found%' then raise; end if;
  end;

  begin
    perform app.start_wms_packing_task(v_draft_order_id, 'idem-packtask-draft', '00000000-0000-0000-0000-000000190202', 'rep');
    raise exception 'assertion failed: expected outbound_order_not_confirmed -- the draft order was never confirmed';
  exception
    when others then
      if sqlerrm not like 'outbound_order_not_confirmed%' then raise; end if;
  end;

  v_task := app.start_wms_packing_task(v_order_id, 'idem-packtask-main', '00000000-0000-0000-0000-000000190202', 'rep');
  if v_task.outbound_order_id <> v_order_id or v_task.packing_task_number is null then
    raise exception 'assertion failed: expected a real packing task against the main order with a real packing_task_number';
  end if;

  v_replay := app.start_wms_packing_task(v_order_id, 'idem-packtask-main', '00000000-0000-0000-0000-000000190202', 'rep');
  if v_replay.id <> v_task.id then
    raise exception 'assertion failed: expected the same-idempotency-key replay to return the identical packing task';
  end if;

  -- Design note 1: one packing task per order -- a DIFFERENT idempotency key against
  -- the SAME order must still return the original task, never create a second one.
  v_replay_other_key := app.start_wms_packing_task(v_order_id, 'idem-packtask-main-again', '00000000-0000-0000-0000-000000190202', 'rep');
  if v_replay_other_key.id <> v_task.id then
    raise exception 'assertion failed: expected the one-packing-task-per-order guard to return the identical task under a different idempotency key';
  end if;
  if (select count(*) from app.wms_packing_tasks where outbound_order_id = v_order_id) <> 1 then
    raise exception 'assertion failed: expected exactly one packing task to ever exist for this order';
  end if;
end $$;

\echo '>> app.create_wms_package/app.reparent_wms_package: viewer rejected; packing_task_not_found; invalid_package_type; success (root + nested child); parent_package_not_found; parent_package_confirmed; cycle_rejected (self-parent and multi-level); a real, legitimate reparent success'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'wmspack1');
  v_packing_task_id uuid := (select id from app.wms_packing_tasks where tenant_id = v_tenant1 and idempotency_key = 'idem-packtask-main');
  v_p1 app.wms_packages;
  v_p1a app.wms_packages;
  v_p1_replay app.wms_packages;
  v_p2 app.wms_packages;
  v_p3 app.wms_packages;
  v_p4 app.wms_packages;
  v_p6 app.wms_packages;
  v_l8 app.wms_pick_tasks;
begin
  begin
    perform app.create_wms_package(v_packing_task_id, null, 'carton', 'idem-pkg-viewer', '00000000-0000-0000-0000-000000190205', 'viewer');
    raise exception 'assertion failed: expected insufficient_authority -- viewer holds OPS:View only';
  exception
    when others then
      if sqlerrm not like 'insufficient_authority%' then raise; end if;
  end;

  begin
    perform app.create_wms_package(gen_random_uuid(), null, 'carton', 'idem-pkg-badtask', '00000000-0000-0000-0000-000000190202', 'rep');
    raise exception 'assertion failed: expected packing_task_not_found';
  exception
    when others then
      if sqlerrm not like 'packing_task_not_found%' then raise; end if;
  end;

  begin
    perform app.create_wms_package(v_packing_task_id, null, 'spaceship', 'idem-pkg-badtype', '00000000-0000-0000-0000-000000190202', 'rep');
    raise exception 'assertion failed: expected invalid_package_type';
  exception
    when others then
      if sqlerrm not like 'invalid_package_type%' then raise; end if;
  end;

  v_p1 := app.create_wms_package(v_packing_task_id, null, 'carton', 'idem-pkg-p1', '00000000-0000-0000-0000-000000190202', 'rep');
  if v_p1.status <> 'open' or v_p1.owner_account_id is null or v_p1.parent_package_id is not null then
    raise exception 'assertion failed: expected a real open root package with a derived owner_account_id';
  end if;

  v_p1_replay := app.create_wms_package(v_packing_task_id, null, 'carton', 'idem-pkg-p1', '00000000-0000-0000-0000-000000190202', 'rep');
  if v_p1_replay.id <> v_p1.id then
    raise exception 'assertion failed: expected the same-idempotency-key replay to return the identical package';
  end if;

  v_p1a := app.create_wms_package(v_packing_task_id, v_p1.id, 'box', 'idem-pkg-p1a', '00000000-0000-0000-0000-000000190202', 'rep');
  if v_p1a.parent_package_id <> v_p1.id then
    raise exception 'assertion failed: expected P1a to nest under P1';
  end if;

  begin
    perform app.create_wms_package(v_packing_task_id, gen_random_uuid(), 'box', 'idem-pkg-badparent', '00000000-0000-0000-0000-000000190202', 'rep');
    raise exception 'assertion failed: expected parent_package_not_found';
  exception
    when others then
      if sqlerrm not like 'parent_package_not_found%' then raise; end if;
  end;

  -- Hierarchy chain P2 -> P3 -> P4, with L8''s real picked stock packed into P4 so it
  -- can be confirmed (P4''s own parent is P3, not null, so no seal is required -- the
  -- nested-child seal exemption, design note 5).
  v_p2 := app.create_wms_package(v_packing_task_id, null, 'pallet', 'idem-pkg-p2', '00000000-0000-0000-0000-000000190202', 'rep');
  v_p3 := app.create_wms_package(v_packing_task_id, v_p2.id, 'crate', 'idem-pkg-p3', '00000000-0000-0000-0000-000000190202', 'rep');
  v_p4 := app.create_wms_package(v_packing_task_id, v_p3.id, 'box', 'idem-pkg-p4', '00000000-0000-0000-0000-000000190202', 'rep');

  select t.* into v_l8 from app.wms_pick_tasks t where t.tenant_id = v_tenant1 and t.idempotency_key = 'idem-pack-pick-l8-gen';
  v_p4 := app.add_wms_package_line(v_p4.id, v_l8.id, 5, v_l8.item_master_id, null, null, 'idem-pkgline-p4', v_p4.record_version, '00000000-0000-0000-0000-000000190202', 'rep');
  v_p4 := app.record_wms_package_measurements(v_p4.id, 1.5, 'KG', null, null, null, null, v_p4.record_version, '00000000-0000-0000-0000-000000190202', 'rep');
  v_p4 := app.record_wms_package_qc(v_p4.id, 'pass', null, v_p4.record_version, '00000000-0000-0000-0000-000000190202', 'rep');
  v_p4 := app.confirm_wms_package(v_p4.id, 'idem-pkg-p4-confirm', v_p4.record_version, '00000000-0000-0000-0000-000000190202', 'rep');
  if v_p4.status <> 'confirmed' or v_p4.seal_number is not null then
    raise exception 'assertion failed: expected P4 to confirm without a seal (nested child exemption, design note 5), got status=%/seal=%', v_p4.status, v_p4.seal_number;
  end if;

  begin
    perform app.create_wms_package(v_packing_task_id, v_p4.id, 'box', 'idem-pkg-p6-blocked', '00000000-0000-0000-0000-000000190202', 'rep');
    raise exception 'assertion failed: expected parent_package_confirmed -- P4 has already been confirmed';
  exception
    when others then
      if sqlerrm not like 'parent_package_confirmed%' then raise; end if;
  end;

  -- Governed reopen (supervisor) unblocks nesting a new child again.
  v_p4 := app.reopen_wms_package(v_p4.id, 'need to add another item', v_p4.record_version, '00000000-0000-0000-0000-000000190204', 'supervisor');
  v_p6 := app.create_wms_package(v_packing_task_id, v_p4.id, 'box', 'idem-pkg-p6', '00000000-0000-0000-0000-000000190202', 'rep');

  begin
    perform app.reparent_wms_package(v_p2.id, v_p2.id, v_p2.record_version, '00000000-0000-0000-0000-000000190202', 'rep');
    raise exception 'assertion failed: expected cycle_rejected -- a package cannot be its own parent';
  exception
    when others then
      if sqlerrm not like 'cycle_rejected%' then raise; end if;
  end;

  begin
    -- P2 is an ancestor of P6 (P2 -> P3 -> P4 -> P6) -- moving P2 under P6 would cycle.
    perform app.reparent_wms_package(v_p2.id, v_p6.id, v_p2.record_version, '00000000-0000-0000-0000-000000190202', 'rep');
    raise exception 'assertion failed: expected cycle_rejected -- a real multi-level cycle (P2 -> P3 -> P4 -> P6 -> P2)';
  exception
    when others then
      if sqlerrm not like 'cycle_rejected%' then raise; end if;
  end;

  -- A real, legitimate reparent -- detach P6 from P4 and move it to be a direct child
  -- of P2 instead (no cycle: P6 is not an ancestor of P2).
  v_p6 := app.reparent_wms_package(v_p6.id, v_p2.id, v_p6.record_version, '00000000-0000-0000-0000-000000190202', 'rep');
  if v_p6.parent_package_id <> v_p2.id then
    raise exception 'assertion failed: expected P6 to have been legitimately reparented under P2';
  end if;
end $$;

\echo '>> app.add_wms_package_line: viewer rejected; package_not_found; stale_version; task_not_found; wrong_order (cross-order, same-owner task); item_mismatch; lot missing/mismatch/success; serial missing/mismatch/success; over_pack_rejected; idempotent replay never double-counts; confirmed_package_edit_rejected'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'wmspack1');
  v_packing_task_id uuid := (select id from app.wms_packing_tasks where tenant_id = v_tenant1 and idempotency_key = 'idem-packtask-main');
  v_p1 app.wms_packages := (select p from app.wms_packages p where p.tenant_id = v_tenant1 and p.idempotency_key = 'idem-pkg-p1');
  v_second_order_task app.wms_pick_tasks := (select t from app.wms_pick_tasks t where t.tenant_id = v_tenant1 and t.idempotency_key = 'idem-pack-pick-s1-gen');
  v_l1_task app.wms_pick_tasks := (select t from app.wms_pick_tasks t where t.tenant_id = v_tenant1 and t.idempotency_key = 'idem-pack-pick-l1-gen');
  v_l3_task app.wms_pick_tasks := (select t from app.wms_pick_tasks t where t.tenant_id = v_tenant1 and t.idempotency_key = 'idem-pack-pick-l3-gen');
  v_l4_task app.wms_pick_tasks := (select t from app.wms_pick_tasks t where t.tenant_id = v_tenant1 and t.idempotency_key = 'idem-pack-pick-l4-gen');
  v_l5_task app.wms_pick_tasks := (select t from app.wms_pick_tasks t where t.tenant_id = v_tenant1 and t.idempotency_key = 'idem-pack-pick-l5-gen');
  v_p_over app.wms_packages;
  v_p_lot app.wms_packages;
  v_p_serial app.wms_packages;
begin
  begin
    perform app.add_wms_package_line(v_p1.id, v_l1_task.id, 50, v_l1_task.item_master_id, null, null, 'idem-pkgline-viewer', v_p1.record_version, '00000000-0000-0000-0000-000000190205', 'viewer');
    raise exception 'assertion failed: expected insufficient_authority -- viewer holds OPS:View only';
  exception
    when others then
      if sqlerrm not like 'insufficient_authority%' then raise; end if;
  end;

  begin
    perform app.add_wms_package_line(gen_random_uuid(), v_l1_task.id, 50, v_l1_task.item_master_id, null, null, 'idem-pkgline-badpkg', 1, '00000000-0000-0000-0000-000000190202', 'rep');
    raise exception 'assertion failed: expected package_not_found';
  exception
    when others then
      if sqlerrm not like 'package_not_found%' then raise; end if;
  end;

  begin
    perform app.add_wms_package_line(v_p1.id, v_l1_task.id, 50, v_l1_task.item_master_id, null, null, 'idem-pkgline-staleversion', 999999, '00000000-0000-0000-0000-000000190202', 'rep');
    raise exception 'assertion failed: expected stale_version';
  exception
    when others then
      if sqlerrm not like 'stale_version%' then raise; end if;
  end;

  begin
    perform app.add_wms_package_line(v_p1.id, gen_random_uuid(), 1, v_l1_task.item_master_id, null, null, 'idem-pkgline-badtask', v_p1.record_version, '00000000-0000-0000-0000-000000190202', 'rep');
    raise exception 'assertion failed: expected task_not_found';
  exception
    when others then
      if sqlerrm not like 'task_not_found%' then raise; end if;
  end;

  begin
    -- Same owner (Alpha), but a DIFFERENT outbound order than P1''s own packing task.
    perform app.add_wms_package_line(v_p1.id, v_second_order_task.id, 5, v_second_order_task.item_master_id, null, null, 'idem-pkgline-wrongorder', v_p1.record_version, '00000000-0000-0000-0000-000000190202', 'rep');
    raise exception 'assertion failed: expected wrong_order -- the second order''s own task does not belong to P1''s own outbound order';
  exception
    when others then
      if sqlerrm not like 'wrong_order%' then raise; end if;
  end;

  begin
    perform app.add_wms_package_line(v_p1.id, v_l1_task.id, 1, v_l4_task.item_master_id, null, null, 'idem-pkgline-itemmismatch', v_p1.record_version, '00000000-0000-0000-0000-000000190202', 'rep');
    raise exception 'assertion failed: expected item_mismatch -- scanned item does not match the task''s own item';
  exception
    when others then
      if sqlerrm not like 'item_mismatch%' then raise; end if;
  end;

  -- Success: the main flow (P1 gets its own real 50 units from L1) -- idempotent
  -- replay must never double-count.
  v_p1 := app.add_wms_package_line(v_p1.id, v_l1_task.id, 50, v_l1_task.item_master_id, null, null, 'idem-pkgline-p1', v_p1.record_version, '00000000-0000-0000-0000-000000190202', 'rep');
  if v_p1.line_count <> 1 or v_p1.total_packed_quantity <> 50 then
    raise exception 'assertion failed: expected P1 to hold exactly 1 line / 50 units after adding L1''s own full picked quantity, got line_count=%/total=%', v_p1.line_count, v_p1.total_packed_quantity;
  end if;
  v_p1 := app.add_wms_package_line(v_p1.id, v_l1_task.id, 50, v_l1_task.item_master_id, null, null, 'idem-pkgline-p1', v_p1.record_version, '00000000-0000-0000-0000-000000190202', 'rep');
  if v_p1.total_packed_quantity <> 50 then
    raise exception 'assertion failed: expected the same-idempotency-key replay to never double-count, got total=%', v_p1.total_packed_quantity;
  end if;

  -- Over-pack rejection: L3''s own task has exactly 5 units picked.
  v_p_over := app.create_wms_package(v_packing_task_id, null, 'carton', 'idem-pkg-over', '00000000-0000-0000-0000-000000190202', 'rep');
  begin
    perform app.add_wms_package_line(v_p_over.id, v_l3_task.id, 10, v_l3_task.item_master_id, null, null, 'idem-pkgline-overpack', v_p_over.record_version, '00000000-0000-0000-0000-000000190202', 'rep');
    raise exception 'assertion failed: expected over_pack_rejected -- L3''s own task only has 5 units picked';
  exception
    when others then
      if sqlerrm not like 'over_pack_rejected%' then raise; end if;
  end;
  v_p_over := app.add_wms_package_line(v_p_over.id, v_l3_task.id, 5, v_l3_task.item_master_id, null, null, 'idem-pkgline-overpack-ok', v_p_over.record_version, '00000000-0000-0000-0000-000000190202', 'rep');
  begin
    perform app.add_wms_package_line(v_p_over.id, v_l3_task.id, 1, v_l3_task.item_master_id, null, null, 'idem-pkgline-overpack-2', v_p_over.record_version, '00000000-0000-0000-0000-000000190202', 'rep');
    raise exception 'assertion failed: expected over_pack_rejected -- L3''s own task now has zero remaining unpacked quantity';
  exception
    when others then
      if sqlerrm not like 'over_pack_rejected%' then raise; end if;
  end;

  -- Lot-controlled scan verification (L4, lot LOT-PACK-A, 8 units picked).
  v_p_lot := app.create_wms_package(v_packing_task_id, null, 'carton', 'idem-pkg-lot', '00000000-0000-0000-0000-000000190202', 'rep');
  begin
    perform app.add_wms_package_line(v_p_lot.id, v_l4_task.id, 8, v_l4_task.item_master_id, null, null, 'idem-pkgline-lot-missing', v_p_lot.record_version, '00000000-0000-0000-0000-000000190202', 'rep');
    raise exception 'assertion failed: expected missing_lot -- L4 is lot-controlled';
  exception
    when others then
      if sqlerrm not like 'missing_lot%' then raise; end if;
  end;
  begin
    perform app.add_wms_package_line(v_p_lot.id, v_l4_task.id, 8, v_l4_task.item_master_id, 'LOT-PACK-WRONG', null, 'idem-pkgline-lot-mismatch', v_p_lot.record_version, '00000000-0000-0000-0000-000000190202', 'rep');
    raise exception 'assertion failed: expected lot_mismatch';
  exception
    when others then
      if sqlerrm not like 'lot_mismatch%' then raise; end if;
  end;
  v_p_lot := app.add_wms_package_line(v_p_lot.id, v_l4_task.id, 8, v_l4_task.item_master_id, 'LOT-PACK-A', null, 'idem-pkgline-lot-ok', v_p_lot.record_version, '00000000-0000-0000-0000-000000190202', 'rep');
  if v_p_lot.total_packed_quantity <> 8 then
    raise exception 'assertion failed: expected the exact-matching lot scan to succeed';
  end if;

  -- Serial-controlled scan verification (L5, serial SN-PACK-A, 1 unit picked).
  v_p_serial := app.create_wms_package(v_packing_task_id, null, 'carton', 'idem-pkg-serial', '00000000-0000-0000-0000-000000190202', 'rep');
  begin
    perform app.add_wms_package_line(v_p_serial.id, v_l5_task.id, 1, v_l5_task.item_master_id, null, null, 'idem-pkgline-serial-missing', v_p_serial.record_version, '00000000-0000-0000-0000-000000190202', 'rep');
    raise exception 'assertion failed: expected missing_serial -- L5 is serial-controlled';
  exception
    when others then
      if sqlerrm not like 'missing_serial%' then raise; end if;
  end;
  begin
    perform app.add_wms_package_line(v_p_serial.id, v_l5_task.id, 1, v_l5_task.item_master_id, null, 'SN-PACK-WRONG', 'idem-pkgline-serial-mismatch', v_p_serial.record_version, '00000000-0000-0000-0000-000000190202', 'rep');
    raise exception 'assertion failed: expected serial_mismatch';
  exception
    when others then
      if sqlerrm not like 'serial_mismatch%' then raise; end if;
  end;
  v_p_serial := app.add_wms_package_line(v_p_serial.id, v_l5_task.id, 1, v_l5_task.item_master_id, null, 'SN-PACK-A', 'idem-pkgline-serial-ok', v_p_serial.record_version, '00000000-0000-0000-0000-000000190202', 'rep');
  if v_p_serial.total_packed_quantity <> 1 then
    raise exception 'assertion failed: expected the exact-matching serial scan to succeed';
  end if;
end $$;

\echo '>> app.remove_wms_package_line: invalid_reason; line_not_found; exceeds_line_quantity; partial remove; full remove (row deleted, empty_package_rejected on confirm)'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'wmspack1');
  v_packing_task_id uuid := (select id from app.wms_packing_tasks where tenant_id = v_tenant1 and idempotency_key = 'idem-packtask-main');
  v_l6_task app.wms_pick_tasks := (select t from app.wms_pick_tasks t where t.tenant_id = v_tenant1 and t.idempotency_key = 'idem-pack-pick-l6-gen');
  v_p11 app.wms_packages;
begin
  v_p11 := app.create_wms_package(v_packing_task_id, null, 'carton', 'idem-pkg-p11', '00000000-0000-0000-0000-000000190202', 'rep');
  v_p11 := app.add_wms_package_line(v_p11.id, v_l6_task.id, 10, v_l6_task.item_master_id, null, null, 'idem-pkgline-p11', v_p11.record_version, '00000000-0000-0000-0000-000000190202', 'rep');

  begin
    perform app.remove_wms_package_line(v_p11.id, v_l6_task.id, 1, '', 'idem-pkgline-rm-emptyreason', v_p11.record_version, '00000000-0000-0000-0000-000000190202', 'rep');
    raise exception 'assertion failed: expected invalid_reason -- an empty reason must be rejected';
  exception
    when others then
      if sqlerrm not like 'invalid_reason%' then raise; end if;
  end;

  begin
    perform app.remove_wms_package_line(v_p11.id, gen_random_uuid(), 1, 'test', 'idem-pkgline-rm-notfound', v_p11.record_version, '00000000-0000-0000-0000-000000190202', 'rep');
    raise exception 'assertion failed: expected line_not_found';
  exception
    when others then
      if sqlerrm not like 'line_not_found%' then raise; end if;
  end;

  begin
    perform app.remove_wms_package_line(v_p11.id, v_l6_task.id, 100, 'test', 'idem-pkgline-rm-exceeds', v_p11.record_version, '00000000-0000-0000-0000-000000190202', 'rep');
    raise exception 'assertion failed: expected exceeds_line_quantity';
  exception
    when others then
      if sqlerrm not like 'exceeds_line_quantity%' then raise; end if;
  end;

  v_p11 := app.remove_wms_package_line(v_p11.id, v_l6_task.id, 4, 'partial removal, damaged unit', 'idem-pkgline-rm-partial', v_p11.record_version, '00000000-0000-0000-0000-000000190202', 'rep');
  if v_p11.total_packed_quantity <> 6 or v_p11.line_count <> 1 then
    raise exception 'assertion failed: expected 6 units remaining after removing 4 of 10, got total=%/line_count=%', v_p11.total_packed_quantity, v_p11.line_count;
  end if;

  v_p11 := app.remove_wms_package_line(v_p11.id, v_l6_task.id, 6, 'removing the rest', 'idem-pkgline-rm-full', v_p11.record_version, '00000000-0000-0000-0000-000000190202', 'rep');
  if v_p11.total_packed_quantity <> 0 or v_p11.line_count <> 0 then
    raise exception 'assertion failed: expected the line row to be fully removed, got total=%/line_count=%', v_p11.total_packed_quantity, v_p11.line_count;
  end if;

  begin
    perform app.confirm_wms_package(v_p11.id, 'idem-pkg-p11-confirm', v_p11.record_version, '00000000-0000-0000-0000-000000190202', 'rep');
    raise exception 'assertion failed: expected empty_package_rejected -- every line was removed';
  exception
    when others then
      if sqlerrm not like 'empty_package_rejected%' then raise; end if;
  end;
end $$;

\echo '>> app.record_wms_package_measurements: invalid_weight; invalid_uom; invalid_uom_category; invalid_dimensions (partial); success (weight-only and full dimensions)'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'wmspack1');
  v_p1 app.wms_packages := (select p from app.wms_packages p where p.tenant_id = v_tenant1 and p.idempotency_key = 'idem-pkg-p1');
begin
  begin
    perform app.record_wms_package_measurements(v_p1.id, -1, 'KG', null, null, null, null, v_p1.record_version, '00000000-0000-0000-0000-000000190202', 'rep');
    raise exception 'assertion failed: expected invalid_weight';
  exception
    when others then
      if sqlerrm not like 'invalid_weight%' then raise; end if;
  end;

  begin
    perform app.record_wms_package_measurements(v_p1.id, 5, 'NOT-A-UOM', null, null, null, null, v_p1.record_version, '00000000-0000-0000-0000-000000190202', 'rep');
    raise exception 'assertion failed: expected invalid_uom';
  exception
    when others then
      if sqlerrm not like 'invalid_uom%' then raise; end if;
  end;

  begin
    perform app.record_wms_package_measurements(v_p1.id, 5, 'PCS', null, null, null, null, v_p1.record_version, '00000000-0000-0000-0000-000000190202', 'rep');
    raise exception 'assertion failed: expected invalid_uom_category -- PCS is a count UOM, not weight';
  exception
    when others then
      if sqlerrm not like 'invalid_uom_category%' then raise; end if;
  end;

  begin
    perform app.record_wms_package_measurements(v_p1.id, 5, 'KG', 30, null, null, 'CM', v_p1.record_version, '00000000-0000-0000-0000-000000190202', 'rep');
    raise exception 'assertion failed: expected invalid_dimensions -- length/width/height must be supplied together';
  exception
    when others then
      if sqlerrm not like 'invalid_dimensions%' then raise; end if;
  end;

  v_p1 := app.record_wms_package_measurements(v_p1.id, 12.5, 'KG', 30, 20, 15, 'CM', v_p1.record_version, '00000000-0000-0000-0000-000000190202', 'rep');
  if v_p1.weight_value <> 12.5 or v_p1.length_value <> 30 or v_p1.dimension_uom_code <> 'CM' then
    raise exception 'assertion failed: expected the full measurement set to be recorded, got weight=%/length=%/dim_uom=%', v_p1.weight_value, v_p1.length_value, v_p1.dimension_uom_code;
  end if;
end $$;

\echo '>> app.record_wms_package_qc / app.override_wms_package_qc_hold / app.record_wms_package_seal: invalid_qc_status; invalid_reason (fail with no reason); invalid_transition (nothing to override); insufficient_authority (rep cannot override); success pass; invalid_seal (empty); success seal'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'wmspack1');
  v_p1 app.wms_packages := (select p from app.wms_packages p where p.tenant_id = v_tenant1 and p.idempotency_key = 'idem-pkg-p1');
  v_p12 app.wms_packages;
begin
  begin
    perform app.record_wms_package_qc(v_p1.id, 'maybe', null, v_p1.record_version, '00000000-0000-0000-0000-000000190202', 'rep');
    raise exception 'assertion failed: expected invalid_qc_status';
  exception
    when others then
      if sqlerrm not like 'invalid_qc_status%' then raise; end if;
  end;

  begin
    perform app.record_wms_package_qc(v_p1.id, 'fail', null, v_p1.record_version, '00000000-0000-0000-0000-000000190202', 'rep');
    raise exception 'assertion failed: expected invalid_reason -- a fail outcome requires a non-empty reason';
  exception
    when others then
      if sqlerrm not like 'invalid_reason%' then raise; end if;
  end;

  -- Nothing to override yet -- P1''s own qc_status is still the default pending.
  v_p12 := app.create_wms_package((select id from app.wms_packing_tasks where tenant_id = v_tenant1 and idempotency_key = 'idem-packtask-main'), null, 'carton', 'idem-pkg-p12-override-fixture', '00000000-0000-0000-0000-000000190202', 'rep');
  begin
    perform app.override_wms_package_qc_hold(v_p12.id, 'n/a', v_p12.record_version, '00000000-0000-0000-0000-000000190204', 'supervisor');
    raise exception 'assertion failed: expected invalid_transition -- qc_status is pending, nothing to override';
  exception
    when others then
      if sqlerrm not like 'invalid_transition%' then raise; end if;
  end;

  v_p1 := app.record_wms_package_qc(v_p1.id, 'pass', null, v_p1.record_version, '00000000-0000-0000-0000-000000190202', 'rep');
  if v_p1.qc_status <> 'pass' or v_p1.qc_at is null then
    raise exception 'assertion failed: expected qc_status=pass to be recorded';
  end if;

  begin
    perform app.record_wms_package_seal(v_p1.id, '', v_p1.record_version, '00000000-0000-0000-0000-000000190202', 'rep');
    raise exception 'assertion failed: expected invalid_seal -- an empty seal number must be rejected';
  exception
    when others then
      if sqlerrm not like 'invalid_seal%' then raise; end if;
  end;

  v_p1 := app.record_wms_package_seal(v_p1.id, 'SEAL-P1-0001', v_p1.record_version, '00000000-0000-0000-0000-000000190202', 'rep');
  if v_p1.seal_number <> 'SEAL-P1-0001' or v_p1.sealed_at is null then
    raise exception 'assertion failed: expected the seal to be recorded';
  end if;
end $$;

\echo '>> app.confirm_wms_package / app.reopen_wms_package: full success on P1; idempotent replay; package_already_confirmed on a fresh key; confirmed_package_edit_rejected on every other mutation; insufficient_authority for a non-supervisor reopen attempt; not_confirmed on an open package; a real governed reopen resets QC/seal (missing_qc immediately after), preserves contents, and requires a fresh QC/seal before a second confirm'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'wmspack1');
  v_p1 app.wms_packages := (select p from app.wms_packages p where p.tenant_id = v_tenant1 and p.idempotency_key = 'idem-pkg-p1');
  v_l1_task app.wms_pick_tasks := (select t from app.wms_pick_tasks t where t.tenant_id = v_tenant1 and t.idempotency_key = 'idem-pack-pick-l1-gen');
  v_p_open app.wms_packages := (select p from app.wms_packages p where p.tenant_id = v_tenant1 and p.idempotency_key = 'idem-pkg-p2');
  v_confirmations app.wms_package_confirmations[];
begin
  v_p1 := app.confirm_wms_package(v_p1.id, 'idem-pkg-p1-confirm', v_p1.record_version, '00000000-0000-0000-0000-000000190202', 'rep');
  if v_p1.status <> 'confirmed' or v_p1.confirmed_at is null or v_p1.confirmed_by_auth_user_id is null then
    raise exception 'assertion failed: expected P1 to confirm cleanly with real evidence, got status=%', v_p1.status;
  end if;

  -- Idempotent replay (same key) -- no-op, still confirmed.
  v_p1 := app.confirm_wms_package(v_p1.id, 'idem-pkg-p1-confirm', v_p1.record_version, '00000000-0000-0000-0000-000000190202', 'rep');
  if v_p1.status <> 'confirmed' then
    raise exception 'assertion failed: expected the same-idempotency-key confirm replay to remain a clean no-op';
  end if;

  begin
    perform app.confirm_wms_package(v_p1.id, 'idem-pkg-p1-confirm-freshkey', v_p1.record_version, '00000000-0000-0000-0000-000000190202', 'rep');
    raise exception 'assertion failed: expected package_already_confirmed -- a genuinely different idempotency key against an already-confirmed package';
  exception
    when others then
      if sqlerrm not like 'package_already_confirmed%' then raise; end if;
  end;

  select array_agg(c) into v_confirmations from app.list_wms_package_confirmations(v_p1.id, '00000000-0000-0000-0000-000000190202') c;
  if array_length(v_confirmations, 1) <> 1 then
    raise exception 'assertion failed: expected exactly one real confirmation evidence row for P1';
  end if;

  begin
    perform app.add_wms_package_line(v_p1.id, v_l1_task.id, 1, v_l1_task.item_master_id, null, null, 'idem-pkgline-p1-postconfirm', v_p1.record_version, '00000000-0000-0000-0000-000000190202', 'rep');
    raise exception 'assertion failed: expected confirmed_package_edit_rejected on add-line';
  exception
    when others then
      if sqlerrm not like 'confirmed_package_edit_rejected%' then raise; end if;
  end;
  begin
    perform app.record_wms_package_measurements(v_p1.id, 1, 'KG', null, null, null, null, v_p1.record_version, '00000000-0000-0000-0000-000000190202', 'rep');
    raise exception 'assertion failed: expected confirmed_package_edit_rejected on re-measuring';
  exception
    when others then
      if sqlerrm not like 'confirmed_package_edit_rejected%' then raise; end if;
  end;
  begin
    perform app.record_wms_package_qc(v_p1.id, 'pass', null, v_p1.record_version, '00000000-0000-0000-0000-000000190202', 'rep');
    raise exception 'assertion failed: expected confirmed_package_edit_rejected on re-QC';
  exception
    when others then
      if sqlerrm not like 'confirmed_package_edit_rejected%' then raise; end if;
  end;
  begin
    perform app.record_wms_package_seal(v_p1.id, 'SEAL-X', v_p1.record_version, '00000000-0000-0000-0000-000000190202', 'rep');
    raise exception 'assertion failed: expected confirmed_package_edit_rejected on re-sealing';
  exception
    when others then
      if sqlerrm not like 'confirmed_package_edit_rejected%' then raise; end if;
  end;

  begin
    perform app.reopen_wms_package(v_p1.id, 'attempted reopen by non-supervisor', v_p1.record_version, '00000000-0000-0000-0000-000000190202', 'rep');
    raise exception 'assertion failed: expected insufficient_authority -- reopen requires OPS:Override (supervisor-only)';
  exception
    when others then
      if sqlerrm not like 'insufficient_authority%' then raise; end if;
  end;

  begin
    perform app.reopen_wms_package(v_p_open.id, 'attempted reopen of an open package', v_p_open.record_version, '00000000-0000-0000-0000-000000190204', 'supervisor');
    raise exception 'assertion failed: expected not_confirmed -- P2 was never confirmed';
  exception
    when others then
      if sqlerrm not like 'not_confirmed%' then raise; end if;
  end;

  v_p1 := app.reopen_wms_package(v_p1.id, 'wrong measurement, needs correction', v_p1.record_version, '00000000-0000-0000-0000-000000190204', 'supervisor');
  if v_p1.status <> 'open' or v_p1.qc_status <> 'pending' or v_p1.seal_number is not null or v_p1.reopen_count <> 1 then
    raise exception 'assertion failed: expected reopen to reset status=open/qc_status=pending/seal_number=null and bump reopen_count, got status=%/qc=%/seal=%/reopen_count=%', v_p1.status, v_p1.qc_status, v_p1.seal_number, v_p1.reopen_count;
  end if;
  if v_p1.line_count <> 1 or v_p1.total_packed_quantity <> 50 then
    raise exception 'assertion failed: expected reopen to PRESERVE the packed line contents, got line_count=%/total=%', v_p1.line_count, v_p1.total_packed_quantity;
  end if;

  begin
    perform app.confirm_wms_package(v_p1.id, 'idem-pkg-p1-reconfirm-attempt', v_p1.record_version, '00000000-0000-0000-0000-000000190202', 'rep');
    raise exception 'assertion failed: expected missing_qc -- reopen resets qc_status to pending, a fresh QC pass is required before re-confirming';
  exception
    when others then
      if sqlerrm not like 'missing_qc%' then raise; end if;
  end;

  v_p1 := app.record_wms_package_qc(v_p1.id, 'pass', null, v_p1.record_version, '00000000-0000-0000-0000-000000190202', 'rep');
  v_p1 := app.record_wms_package_seal(v_p1.id, 'SEAL-P1-0002', v_p1.record_version, '00000000-0000-0000-0000-000000190202', 'rep');
  v_p1 := app.confirm_wms_package(v_p1.id, 'idem-pkg-p1-reconfirm', v_p1.record_version, '00000000-0000-0000-0000-000000190202', 'rep');
  if v_p1.status <> 'confirmed' then
    raise exception 'assertion failed: expected P1 to confirm a second time after a fresh QC pass and seal';
  end if;
end $$;

\echo '>> staged confirm-precondition chain on one package (P14): empty_package_rejected -> missing_measurement -> missing_qc -> qc_hold_unresolved (hold outcome) -> override -> missing_seal -> success'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'wmspack1');
  v_packing_task_id uuid := (select id from app.wms_packing_tasks where tenant_id = v_tenant1 and idempotency_key = 'idem-packtask-main');
  v_l9_task app.wms_pick_tasks := (select t from app.wms_pick_tasks t where t.tenant_id = v_tenant1 and t.idempotency_key = 'idem-pack-pick-l9-gen');
  v_p14 app.wms_packages;
begin
  v_p14 := app.create_wms_package(v_packing_task_id, null, 'carton', 'idem-pkg-p14', '00000000-0000-0000-0000-000000190202', 'rep');

  begin
    perform app.confirm_wms_package(v_p14.id, 'idem-pkg-p14-confirm-1', v_p14.record_version, '00000000-0000-0000-0000-000000190202', 'rep');
    raise exception 'assertion failed: expected empty_package_rejected';
  exception
    when others then
      if sqlerrm not like 'empty_package_rejected%' then raise; end if;
  end;

  v_p14 := app.add_wms_package_line(v_p14.id, v_l9_task.id, 3, v_l9_task.item_master_id, null, null, 'idem-pkgline-p14', v_p14.record_version, '00000000-0000-0000-0000-000000190202', 'rep');

  begin
    perform app.confirm_wms_package(v_p14.id, 'idem-pkg-p14-confirm-2', v_p14.record_version, '00000000-0000-0000-0000-000000190202', 'rep');
    raise exception 'assertion failed: expected missing_measurement';
  exception
    when others then
      if sqlerrm not like 'missing_measurement%' then raise; end if;
  end;

  v_p14 := app.record_wms_package_measurements(v_p14.id, 1.0, 'KG', null, null, null, null, v_p14.record_version, '00000000-0000-0000-0000-000000190202', 'rep');

  begin
    perform app.confirm_wms_package(v_p14.id, 'idem-pkg-p14-confirm-3', v_p14.record_version, '00000000-0000-0000-0000-000000190202', 'rep');
    raise exception 'assertion failed: expected missing_qc';
  exception
    when others then
      if sqlerrm not like 'missing_qc%' then raise; end if;
  end;

  v_p14 := app.record_wms_package_qc(v_p14.id, 'hold', 'awaiting supervisor review', v_p14.record_version, '00000000-0000-0000-0000-000000190202', 'rep');

  begin
    perform app.confirm_wms_package(v_p14.id, 'idem-pkg-p14-confirm-4', v_p14.record_version, '00000000-0000-0000-0000-000000190202', 'rep');
    raise exception 'assertion failed: expected qc_hold_unresolved';
  exception
    when others then
      if sqlerrm not like 'qc_hold_unresolved%' then raise; end if;
  end;

  v_p14 := app.override_wms_package_qc_hold(v_p14.id, 'supervisor accepted risk after manual review', v_p14.record_version, '00000000-0000-0000-0000-000000190204', 'supervisor');
  if v_p14.qc_override_at is null or v_p14.qc_status <> 'hold' then
    raise exception 'assertion failed: expected the override to record evidence WITHOUT silently overwriting the original hold outcome, got qc_status=%/override_at=%', v_p14.qc_status, v_p14.qc_override_at;
  end if;

  begin
    perform app.confirm_wms_package(v_p14.id, 'idem-pkg-p14-confirm-5', v_p14.record_version, '00000000-0000-0000-0000-000000190202', 'rep');
    raise exception 'assertion failed: expected missing_seal -- P14 is a root package';
  exception
    when others then
      if sqlerrm not like 'missing_seal%' then raise; end if;
  end;

  v_p14 := app.record_wms_package_seal(v_p14.id, 'SEAL-P14-0001', v_p14.record_version, '00000000-0000-0000-0000-000000190202', 'rep');
  v_p14 := app.confirm_wms_package(v_p14.id, 'idem-pkg-p14-confirm-6', v_p14.record_version, '00000000-0000-0000-0000-000000190202', 'rep');
  if v_p14.status <> 'confirmed' then
    raise exception 'assertion failed: expected P14 to confirm successfully once every precondition (contents/weight/qc[overridden]/seal) is satisfied';
  end if;
end $$;

\echo '>> REAL two-process concurrent double-pack-prevention race (this checkpoint''s own headline acceptance criterion): L2''s own task has exactly 20 units picked. Two genuinely independent psql client processes each attempt to add 15 units of it into TWO DIFFERENT packages (deliberately proving the TASK-row lock, design note 3, not merely a narrower per-package lock), launched via scripts/db-tests/wms-picking-concurrency-helper.sh (reused directly, generic PG_TEST_DB/RACE_SQL_A/B/RACE_OUT_A/B contract). 15+15=30 exceeds 20 -- exactly one must succeed; the other must be rejected over_pack_rejected; the task''s own total packed quantity must never exceed 20'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'wmspack1');
  v_packing_task_id uuid := (select id from app.wms_packing_tasks where tenant_id = v_tenant1 and idempotency_key = 'idem-packtask-main');
  v_pkg_a app.wms_packages;
  v_pkg_b app.wms_packages;
begin
  v_pkg_a := app.create_wms_package(v_packing_task_id, null, 'carton', 'idem-pkg-race-a', '00000000-0000-0000-0000-000000190202', 'rep');
  v_pkg_b := app.create_wms_package(v_packing_task_id, null, 'carton', 'idem-pkg-race-b', '00000000-0000-0000-0000-000000190202', 'rep');
end $$;

select p.id as race_pkg_a_id, p.record_version as race_pkg_a_version from app.wms_packages p where p.tenant_id = (select id from app.tenants where slug = 'wmspack1') and p.idempotency_key = 'idem-pkg-race-a' \gset
select p.id as race_pkg_b_id, p.record_version as race_pkg_b_version from app.wms_packages p where p.tenant_id = (select id from app.tenants where slug = 'wmspack1') and p.idempotency_key = 'idem-pkg-race-b' \gset
select t.id as race_l2_task_id, t.item_master_id as race_l2_item_id from app.wms_pick_tasks t where t.tenant_id = (select id from app.tenants where slug = 'wmspack1') and t.idempotency_key = 'idem-pack-pick-l2-gen' \gset
select current_database() as pg_test_db \gset

\set race_sql_a 'select app.add_wms_package_line(''' :race_pkg_a_id ''', ''' :race_l2_task_id ''', 15, ''' :race_l2_item_id ''', null, null, ''idem-pkgline-race-a'', ' :race_pkg_a_version ', ''00000000-0000-0000-0000-000000190202'', ''rep'');'
\set race_sql_b 'select app.add_wms_package_line(''' :race_pkg_b_id ''', ''' :race_l2_task_id ''', 15, ''' :race_l2_item_id ''', null, null, ''idem-pkgline-race-b'', ' :race_pkg_b_version ', ''00000000-0000-0000-0000-000000190203'', ''rep2'');'

\setenv PG_TEST_DB :pg_test_db
\setenv RACE_SQL_A :race_sql_a
\setenv RACE_SQL_B :race_sql_b
\setenv RACE_OUT_A /tmp/cargogrid-wms-pack-race-a.out
\setenv RACE_OUT_B /tmp/cargogrid-wms-pack-race-b.out

\! bash scripts/db-tests/wms-picking-concurrency-helper.sh

-- RGL-BLK-005 fix: pg_read_file() reads the server's filesystem, but the helper
-- above writes its race-output files on the client's -- identical locally,
-- genuinely different in CI (Postgres in its own Docker service container). \set's
-- backtick form runs client-side, sidestepping the mismatch. Bridged into the
-- do block via a session-level GUC (psql does not interpolate :variables inside
-- a do $$ ... $$ body).
\set loser_out `cat "$RACE_OUT_A" "$RACE_OUT_B"`
select set_config('cargogrid.loser_out', :'loser_out', false);

do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'wmspack1');
  v_l2_task_id uuid := (select t.id from app.wms_pick_tasks t where t.tenant_id = v_tenant1 and t.idempotency_key = 'idem-pack-pick-l2-gen');
  v_total_packed numeric;
  v_line_count integer;
  v_loser_out text;
begin
  select coalesce(sum(quantity), 0), count(*) into v_total_packed, v_line_count from app.wms_package_lines where pick_task_id = v_l2_task_id;
  if v_total_packed <> 15 then
    raise exception 'assertion failed: expected exactly 15 total units packed for L2''s own task (never 30 -- the double-pack this whole proof exists to rule out), got %', v_total_packed;
  end if;
  if v_total_packed > 20 then
    raise exception 'assertion failed: total packed quantity % must never exceed the task''s own picked_quantity (20)', v_total_packed;
  end if;
  if v_line_count <> 1 then
    raise exception 'assertion failed: expected exactly ONE of the two concurrent 15-unit requests to have won, got % real package lines', v_line_count;
  end if;

  v_loser_out := current_setting('cargogrid.loser_out');
  if v_loser_out not like '%over_pack_rejected%' then
    raise exception 'assertion failed: expected the losing process''s own output to carry a clean over_pack_rejected error, got: %', v_loser_out;
  end if;

  raise notice 'concurrent double-pack-prevention race proof: exactly 15 units / 1 line packed for the SAME task (never 30) -- the task-row lock (design note 3) correctly serialized two real, independent psql processes';
end $$;

\echo '>> cross-owner read isolation: the customer_user actor (scoped to Account Alpha only) can read the Alpha packing task/package but is rejected on the Beta packing task/package (insufficient_authority, bug class f); a rep (staff, unrestricted) can read both; app.list_wms_packages/app.list_wms_packing_tasks for the customer_user actor return only Alpha rows, never Beta, even unfiltered'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'wmspack1');
  v_beta_order_id uuid := (select id from app.wms_outbound_orders where tenant_id = v_tenant1 and idempotency_key = 'idem-pack-beta');
  v_beta_task app.wms_packing_tasks;
  v_beta_pkg app.wms_packages;
  v_alpha_task app.wms_packing_tasks := (select t from app.wms_packing_tasks t where t.tenant_id = v_tenant1 and t.idempotency_key = 'idem-packtask-main');
  v_alpha_pkg app.wms_packages := (select p from app.wms_packages p where p.tenant_id = v_tenant1 and p.idempotency_key = 'idem-pkg-p1');
  v_customer_task_rows app.wms_packing_tasks[];
  v_customer_pkg_rows app.wms_packages[];
begin
  v_beta_task := app.start_wms_packing_task(v_beta_order_id, 'idem-packtask-beta', '00000000-0000-0000-0000-000000190202', 'rep');
  v_beta_pkg := app.create_wms_package(v_beta_task.id, null, 'carton', 'idem-pkg-beta', '00000000-0000-0000-0000-000000190202', 'rep');

  -- customer_alpha reads its own owner's rows fine.
  perform app.get_wms_packing_task(v_alpha_task.id, '00000000-0000-0000-0000-000000190207');
  perform app.get_wms_package(v_alpha_pkg.id, '00000000-0000-0000-0000-000000190207');

  begin
    perform app.get_wms_packing_task(v_beta_task.id, '00000000-0000-0000-0000-000000190207');
    raise exception 'assertion failed: expected insufficient_authority -- customer_alpha is scoped to Account Alpha only, never Account Beta';
  exception
    when others then
      if sqlerrm not like 'insufficient_authority%' then raise; end if;
  end;
  begin
    perform app.get_wms_package(v_beta_pkg.id, '00000000-0000-0000-0000-000000190207');
    raise exception 'assertion failed: expected insufficient_authority -- customer_alpha is scoped to Account Alpha only, never Account Beta';
  exception
    when others then
      if sqlerrm not like 'insufficient_authority%' then raise; end if;
  end;

  -- A rep (staff, unrestricted) can read both.
  perform app.get_wms_packing_task(v_beta_task.id, '00000000-0000-0000-0000-000000190202');
  perform app.get_wms_package(v_beta_pkg.id, '00000000-0000-0000-0000-000000190202');

  select array_agg(t) into v_customer_task_rows from app.list_wms_packing_tasks(v_tenant1, '00000000-0000-0000-0000-000000190207', null, null, 200) t;
  if v_customer_task_rows is null or array_length(v_customer_task_rows, 1) < 1 then
    raise exception 'assertion failed: expected customer_alpha to see at least its own Alpha packing task';
  end if;
  if exists (select 1 from unnest(v_customer_task_rows) t where t.id = v_beta_task.id) then
    raise exception 'assertion failed: customer_alpha must never see the Beta packing task, even unfiltered';
  end if;

  select array_agg(p) into v_customer_pkg_rows from app.list_wms_packages(v_tenant1, '00000000-0000-0000-0000-000000190207', null, null, null, null, null, 200) p;
  if exists (select 1 from unnest(v_customer_pkg_rows) p where p.id = v_beta_pkg.id) then
    raise exception 'assertion failed: customer_alpha must never see the Beta package, even unfiltered';
  end if;
  if exists (select 1 from unnest(v_customer_pkg_rows) p where p.owner_account_id <> (select id from app.accounts where tenant_id = v_tenant1 and legal_name = 'WmsPack Customer Alpha')) then
    raise exception 'assertion failed: every package row returned to customer_alpha must be owned by Account Alpha';
  end if;
end $$;

\echo '>> raw RLS regression proof (mirrors ATW-017''s own live-proof lens): as the authenticated customer_alpha identity, a direct SELECT against app.wms_packages/app.wms_packing_tasks (bypassing every RPC) returns only Alpha rows, never Beta -- app.wms_pick_record_scope_ok (ATW-017) reused directly closes the identical latent gap its own review already found once'
do $$
declare
  v_row_count integer;
  v_beta_leak_count integer;
  v_account_alpha_id uuid := (select id from app.accounts where legal_name = 'WmsPack Customer Alpha');
begin
  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000190207", "role": "authenticated"}';

  select count(*) into v_row_count from app.wms_packages;
  if v_row_count < 1 then
    raise exception 'assertion failed: expected customer_alpha to see at least one real package row via raw RLS';
  end if;
  select count(*) into v_beta_leak_count from app.wms_packages where owner_account_id <> v_account_alpha_id;
  if v_beta_leak_count <> 0 then
    raise exception 'assertion failed: raw RLS leaked % non-Alpha package row(s) to customer_alpha', v_beta_leak_count;
  end if;

  select count(*) into v_beta_leak_count from app.wms_packing_tasks where owner_account_id <> v_account_alpha_id;
  if v_beta_leak_count <> 0 then
    raise exception 'assertion failed: raw RLS leaked % non-Alpha packing task row(s) to customer_alpha', v_beta_leak_count;
  end if;

  reset role;
end $$;

\echo '>> cross-tenant isolation: tenant2''s rep, who holds zero membership in tenant1, is rejected insufficient_authority on every mutation/read against tenant1''s real records; regression: every idempotent-replay short-circuit runs strictly after authority/tenant-scope is confirmed (bug class a) -- tenant1''s real already-created/confirmed records never leak live data to a tenant2 attacker reusing a real idempotency key'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'wmspack1');
  v_order_id uuid := (select id from app.wms_outbound_orders where tenant_id = v_tenant1 and idempotency_key = 'idem-pack-main');
  v_packing_task_id uuid := (select id from app.wms_packing_tasks where tenant_id = v_tenant1 and idempotency_key = 'idem-packtask-main');
  v_p1 app.wms_packages := (select p from app.wms_packages p where p.tenant_id = v_tenant1 and p.idempotency_key = 'idem-pkg-p1');
  v_l1_task app.wms_pick_tasks := (select t from app.wms_pick_tasks t where t.tenant_id = v_tenant1 and t.idempotency_key = 'idem-pack-pick-l1-gen');
begin
  begin
    -- ISS-2026-146: the probing actor is rep2b-attacker 190209 (tenant2's rep, zero membership in wmspack1).
    -- app.start_wms_packing_task now folds a caller with zero
    -- membership in the probed record's own tenant into the SAME generic outbound_order_not_found
    -- a nonexistent id already produced, instead of an insufficient_authority message
    -- carrying that tenant's real tenant_id. The refusal itself is unchanged.
    perform app.start_wms_packing_task(v_order_id, 'idem-packtask-attacker', '00000000-0000-0000-0000-000000190209', 'rep2b-attacker');
    raise exception 'assertion failed: expected outbound_order_not_found (ISS-2026-146) -- tenant2''s rep must not start a packing task against tenant1''s real order';
  exception
    when others then
      if sqlerrm not like 'outbound_order_not_found%' then raise; end if;
  end;

  -- bug class (a): reusing tenant1's REAL already-used idempotency key must still fail
  -- closed with insufficient_authority, never silently hand tenant1's real record back.
  begin
    -- ISS-2026-146: the probing actor is rep2b-attacker 190209 (tenant2's rep, zero membership in wmspack1).
    -- app.start_wms_packing_task now folds a caller with zero
    -- membership in the probed record's own tenant into the SAME generic outbound_order_not_found
    -- a nonexistent id already produced, instead of an insufficient_authority message
    -- carrying that tenant's real tenant_id. The refusal itself is unchanged.
    perform app.start_wms_packing_task(v_order_id, 'idem-packtask-main', '00000000-0000-0000-0000-000000190209', 'rep2b-attacker');
    raise exception 'assertion failed: expected outbound_order_not_found (ISS-2026-146) -- must never reach the idempotent-replay short-circuit for a tenant2 attacker';
  exception
    when others then
      if sqlerrm not like 'outbound_order_not_found%' then raise; end if;
  end;

  begin
    -- ISS-2026-146: the probing actor is rep2b-attacker 190209 (tenant2's rep, zero membership in wmspack1).
    -- app.create_wms_package now folds a caller with zero
    -- membership in the probed record's own tenant into the SAME generic packing_task_not_found
    -- a nonexistent id already produced, instead of an insufficient_authority message
    -- carrying that tenant's real tenant_id. The refusal itself is unchanged.
    perform app.create_wms_package(v_packing_task_id, null, 'carton', 'idem-pkg-p1', '00000000-0000-0000-0000-000000190209', 'rep2b-attacker');
    raise exception 'assertion failed: expected packing_task_not_found (ISS-2026-146) on create_wms_package replay-key reuse';
  exception
    when others then
      if sqlerrm not like 'packing_task_not_found%' then raise; end if;
  end;

  begin
    -- ISS-2026-146: the probing actor is rep2b-attacker 190209 (tenant2's rep, zero membership in wmspack1).
    -- app.add_wms_package_line now folds a caller with zero
    -- membership in the probed record's own tenant into the SAME generic package_not_found
    -- a nonexistent id already produced, instead of an insufficient_authority message
    -- carrying that tenant's real tenant_id. The refusal itself is unchanged.
    perform app.add_wms_package_line(v_p1.id, v_l1_task.id, 1, v_l1_task.item_master_id, null, null, 'idem-pkgline-p1', 999999, '00000000-0000-0000-0000-000000190209', 'rep2b-attacker');
    raise exception 'assertion failed: expected package_not_found (ISS-2026-146) on add_wms_package_line replay-key reuse';
  exception
    when others then
      if sqlerrm not like 'package_not_found%' then raise; end if;
  end;

  begin
    -- ISS-2026-146: the probing actor is rep2b-attacker 190209 (tenant2's rep, zero membership in wmspack1).
    -- app.confirm_wms_package now folds a caller with zero
    -- membership in the probed record's own tenant into the SAME generic package_not_found
    -- a nonexistent id already produced, instead of an insufficient_authority message
    -- carrying that tenant's real tenant_id. The refusal itself is unchanged.
    perform app.confirm_wms_package(v_p1.id, 'idem-pkg-p1-confirm', 999999, '00000000-0000-0000-0000-000000190209', 'rep2b-attacker');
    raise exception 'assertion failed: expected package_not_found (ISS-2026-146) on confirm_wms_package replay-key reuse';
  exception
    when others then
      if sqlerrm not like 'package_not_found%' then raise; end if;
  end;

  begin
    -- ISS-2026-146: tenant2's rep (wmspack2) holds no membership in wmspack1, so app.get_wms_package
    -- now collapses that zero-membership case into its own generic
    -- package_not_found / no_data_found branch -- byte-identical to what a
    -- nonexistent id already produced, so the real tenant_id is never disclosed to an
    -- outsider. A genuine same-tenant member lacking the role still gets
    -- insufficient_authority, unchanged (asserted elsewhere in this file).
    perform app.get_wms_package(v_p1.id, '00000000-0000-0000-0000-000000190209');
    raise exception 'assertion failed: expected package_not_found -- tenant2''s rep must not read tenant1''s real package';
  exception
    when others then
      if sqlerrm not like 'package_not_found%' then raise; end if;
  end;

  if exists (select 1 from app.list_wms_packages((select id from app.tenants where slug = 'wmspack2'), '00000000-0000-0000-0000-000000190209', null, null, null, null, null, 200)) then
    raise exception 'assertion failed: expected zero packages visible under tenant2''s own scope (it has none of its own)';
  end if;
end $$;

\echo '>> bounded/filtered reads: app.list_wms_packages p_limit defaults to 50 and hard-caps at 200; explicit status/parent filters narrow correctly'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'wmspack1');
  v_rows app.wms_packages[];
begin
  select array_agg(p) into v_rows from app.list_wms_packages(v_tenant1, '00000000-0000-0000-0000-000000190202', null, null, null, null, null, 999999) p;
  if array_length(v_rows, 1) > 200 then
    raise exception 'assertion failed: expected p_limit to be hard-capped at 200 regardless of a caller-supplied larger value, got %', array_length(v_rows, 1);
  end if;

  select array_agg(p) into v_rows from app.list_wms_packages(v_tenant1, '00000000-0000-0000-0000-000000190202', null, null, null, null, 'confirmed', 50) p;
  if v_rows is null or array_length(v_rows, 1) < 1 then
    raise exception 'assertion failed: expected at least one status=confirmed package';
  end if;
  if exists (select 1 from unnest(v_rows) p where p.status <> 'confirmed') then
    raise exception 'assertion failed: expected every row to have status=confirmed when explicitly filtered';
  end if;
end $$;

\echo '>> schema-privilege defense in depth (ERR-2026-004): anon holds no direct table/EXECUTE access; authenticated has RLS-scoped SELECT but no direct INSERT/UPDATE/DELETE; only service_role may write directly'
do $$
begin
  if has_table_privilege('anon', 'app.wms_packing_tasks', 'SELECT') then
    raise exception 'assertion failed: anon must not have direct SELECT on app.wms_packing_tasks';
  end if;
  if has_table_privilege('anon', 'app.wms_packages', 'SELECT') then
    raise exception 'assertion failed: anon must not have direct SELECT on app.wms_packages';
  end if;
  if has_table_privilege('anon', 'app.wms_package_lines', 'SELECT') then
    raise exception 'assertion failed: anon must not have direct SELECT on app.wms_package_lines';
  end if;
  if has_table_privilege('anon', 'app.wms_package_line_scans', 'SELECT') then
    raise exception 'assertion failed: anon must not have direct SELECT on app.wms_package_line_scans';
  end if;
  if has_table_privilege('anon', 'app.wms_package_confirmations', 'SELECT') then
    raise exception 'assertion failed: anon must not have direct SELECT on app.wms_package_confirmations';
  end if;
  if has_function_privilege('anon', 'app.confirm_wms_package(uuid, text, integer, uuid, text)', 'EXECUTE') then
    raise exception 'assertion failed: anon must not have EXECUTE on app.confirm_wms_package';
  end if;
  if has_function_privilege('anon', 'app.reopen_wms_package(uuid, text, integer, uuid, text)', 'EXECUTE') then
    raise exception 'assertion failed: anon must not have EXECUTE on app.reopen_wms_package';
  end if;

  if not has_table_privilege('authenticated', 'app.wms_packages', 'SELECT') then
    raise exception 'assertion failed: authenticated must have RLS-scoped SELECT on app.wms_packages';
  end if;
  if has_table_privilege('authenticated', 'app.wms_packages', 'INSERT') then
    raise exception 'assertion failed: authenticated must not have direct INSERT on app.wms_packages -- mutation must go through the SECURITY DEFINER RPCs only';
  end if;
  if has_table_privilege('authenticated', 'app.wms_package_confirmations', 'UPDATE') then
    raise exception 'assertion failed: authenticated must not have direct UPDATE on app.wms_package_confirmations';
  end if;
  if has_table_privilege('authenticated', 'app.wms_package_line_scans', 'DELETE') then
    raise exception 'assertion failed: authenticated must not have direct DELETE on app.wms_package_line_scans';
  end if;

  if not has_table_privilege('service_role', 'app.wms_packages', 'INSERT') then
    raise exception 'assertion failed: service_role must retain direct table access to app.wms_packages';
  end if;
  if not has_table_privilege('service_role', 'app.wms_package_lines', 'INSERT') then
    raise exception 'assertion failed: service_role must retain direct table access to app.wms_package_lines';
  end if;
  if not has_table_privilege('service_role', 'app.wms_package_confirmations', 'INSERT') then
    raise exception 'assertion failed: service_role must retain direct table access to app.wms_package_confirmations';
  end if;
end $$;
