-- Real, executable test evidence for ATW-016 (CG-S10-ATW-016, Prompt 235 Lot, Batch,
-- Serial and Expiry) -- run via `pnpm run db:test` against a real, disposable Postgres
-- database.

\set ON_ERROR_STOP on

\echo '>> setup: one tenant (lbs1), a company org unit, a rep (OPS:Create/Edit/View), a supervisor (OPS:Create/Edit/View/Override), an OPS:View-only viewer, a global Supreme Admin, one warehouse (WH-LBS-1, a dock plus two storage racks), one customer account (Account Alpha via the full CRM->Job Order pipeline), and four item masters (plain/uncontrolled, lot-controlled, serial-controlled, lot+expiry-controlled). Tenant2 (lbs2): an isolated rep, for cross-tenant leakage and RBAC-before-short-circuit checks.'
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
  v_dock app.warehouse_locations;
  v_rack_a app.warehouse_locations;
  v_rack_b app.warehouse_locations;
begin
  insert into auth.users (id, email) values
    ('00000000-0000-0000-0000-000000160101', 'admin@lbs1.test'),
    ('00000000-0000-0000-0000-000000160102', 'rep@lbs1.test'),
    ('00000000-0000-0000-0000-000000160103', 'viewer@lbs1.test'),
    ('00000000-0000-0000-0000-000000160104', 'supervisor@lbs1.test'),
    ('00000000-0000-0000-0000-000000160105', 'supreme@lbs1.test'),
    ('00000000-0000-0000-0000-000000160106', 'admin2@lbs2.test'),
    ('00000000-0000-0000-0000-000000160107', 'rep2b@lbs2.test');

  perform app.grant_principal_membership('00000000-0000-0000-0000-000000160105', 'supreme_admin', null, null, 'tester');

  perform app.provision_tenant('lbs1', 'Lot Batch Serial Tenant One', 'idem-lbs1', 'tester');
  v_tenant1 := (select id from app.tenants where slug = 'lbs1');
  perform app.transition_tenant_status(v_tenant1, 'active', 'setup', 'tester');
  perform app.create_org_unit(v_tenant1, 'company', null, 'LBS1-CO', 'Lot Batch Serial Tenant One Co', 'tester');
  v_company := (select id from app.org_units where tenant_id = v_tenant1 and code = 'LBS1-CO');

  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000160101', 'admin@lbs1.test', 'Lbs Admin', v_company, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'admin@lbs1.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000160101', 'tenant_admin', v_tenant1, null, 'tester');

  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000160102', 'rep@lbs1.test', 'Lbs Rep', v_company, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'rep@lbs1.test'), 'active', 'onboarded', 'tester');

  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000160103', 'viewer@lbs1.test', 'Lbs Viewer', v_company, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'viewer@lbs1.test'), 'active', 'onboarded', 'tester');

  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000160104', 'supervisor@lbs1.test', 'Lbs Supervisor', v_company, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'supervisor@lbs1.test'), 'active', 'onboarded', 'tester');

  v_rep_role := (app.create_role(v_tenant1, 'Lbs Rep Role', 'full commercial + ops create/edit/view', 'tester')).id;
  v_rep_draft := app.create_role_version(v_rep_role, 'tester');
  perform app.set_role_version_permissions(
    v_rep_draft.id,
    array(select id from app.permissions where (resource_module_code = 'COM' and action in ('Create', 'Edit', 'Approve', 'View', 'View cost'))
      or (resource_module_code = 'OPS' and action in ('Create', 'Edit', 'View'))),
    'tester'
  );
  perform app.publish_role_version(v_rep_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_rep_role and status = 'published'), '00000000-0000-0000-0000-000000160102', '00000000-0000-0000-0000-000000160101', 'tester');

  v_supervisor_role := (app.create_role(v_tenant1, 'Lbs Supervisor Role', 'ops create/edit/view/override', 'tester')).id;
  v_supervisor_draft := app.create_role_version(v_supervisor_role, 'tester');
  perform app.set_role_version_permissions(
    v_supervisor_draft.id,
    array(select id from app.permissions where resource_module_code = 'OPS' and action in ('Create', 'Edit', 'View', 'Override')),
    'tester'
  );
  perform app.publish_role_version(v_supervisor_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_supervisor_role and status = 'published'), '00000000-0000-0000-0000-000000160104', '00000000-0000-0000-0000-000000160101', 'tester');

  v_viewer_role := (app.create_role(v_tenant1, 'Lbs Viewer Role', 'OPS:View only', 'tester')).id;
  v_viewer_draft := app.create_role_version(v_viewer_role, 'tester');
  perform app.set_role_version_permissions(v_viewer_draft.id, array(select id from app.permissions where resource_module_code = 'OPS' and action = 'View'), 'tester');
  perform app.publish_role_version(v_viewer_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_viewer_role and status = 'published'), '00000000-0000-0000-0000-000000160103', '00000000-0000-0000-0000-000000160101', 'tester');

  v_warehouse := app.create_warehouse(v_tenant1, v_company, 'WH-LBS-1', 'Lot Batch Serial Warehouse 1', 'Jl. Lbs 1', 'Asia/Jakarta', null, array['land']::text[], '00000000-0000-0000-0000-000000160102', 'rep');
  v_dock := app.create_warehouse_location(v_warehouse.id, null, null, 'DOCK-LBS-1', 'Lbs Dock 1', 'dock', 1, null, null, null, null, null, false, false, '00000000-0000-0000-0000-000000160102', 'rep');
  perform app.set_warehouse_location_status(v_dock.id, 'active', null, v_dock.record_version, '00000000-0000-0000-0000-000000160102', 'rep');
  v_rack_a := app.create_warehouse_location(v_warehouse.id, null, null, 'RACK-LBS-A', 'Lbs Rack A', 'rack', 2, null, null, null, null, null, true, true, '00000000-0000-0000-0000-000000160102', 'rep');
  perform app.set_warehouse_location_status(v_rack_a.id, 'active', null, v_rack_a.record_version, '00000000-0000-0000-0000-000000160102', 'rep');
  v_rack_b := app.create_warehouse_location(v_warehouse.id, null, null, 'RACK-LBS-B', 'Lbs Rack B', 'rack', 3, null, null, null, null, null, true, true, '00000000-0000-0000-0000-000000160102', 'rep');
  perform app.set_warehouse_location_status(v_rack_b.id, 'active', null, v_rack_b.record_version, '00000000-0000-0000-0000-000000160102', 'rep');

  perform app.capture_lead(v_tenant1, 'manual', null, 'Lbs Customer Alpha', 'Alice Lbs', 'alice@lbs235.test', '0811',
    '00000000-0000-0000-0000-000000160102', v_company, '00000000-0000-0000-0000-000000160102', 'tester');
  select * into v_lead from app.leads where email = 'alice@lbs235.test';
  perform app.qualify_lead(v_lead.id, v_lead.record_version, '00000000-0000-0000-0000-000000160102', 'tester');
  select * into v_lead from app.leads where id = v_lead.id;
  perform app.convert_lead_to_prospect(v_lead.id, 'Lbs Customer Alpha', 'LBS235A', '11.111.111.16-111.000',
    jsonb_build_object('line1', 'Jl. Lbs Alpha 12', 'city', 'Jakarta', 'country', 'ID'),
    '00000000-0000-0000-0000-000000160102', 'tester');
  select * into v_prospect from app.prospects where lead_id = v_lead.id;
  select * into v_contact from app.create_contact(v_tenant1, 'Alice Lbs Ops', 'Ops Lead', 'alice@lbs235.test', '0811', '00000000-0000-0000-0000-000000160102', v_company, '00000000-0000-0000-0000-000000160102', 'tester');
  perform app.link_contact_to_record(v_contact.id, 'prospect', v_prospect.id, 'primary', true, '00000000-0000-0000-0000-000000160102', 'tester');
  select * into v_opportunity from app.create_opportunity(
    v_tenant1, v_prospect.id, 'LBS235 Alpha lane',
    jsonb_build_object('service_type', 'land_freight', 'cargo_description', 'General cargo', 'origin', 'Jakarta', 'destination', 'Surabaya', 'target_ready_date', '2026-08-01'),
    '00000000-0000-0000-0000-000000160102', v_company, '00000000-0000-0000-0000-000000160102', 'tester'
  );
  select * into v_request from app.request_costing(v_opportunity.id, '[]'::jsonb, null, '00000000-0000-0000-0000-000000160102', 'tester');
  select * into v_rate from app.create_rate_version(
    v_tenant1, 'VENDOR-LBS235-A', 'Contoso Lbs235 Line', 'land_freight', 'FTL', 'Jakarta', 'Surabaya', '20ft',
    null, null, null, null, 'IDR', 5000000, null, '[]'::jsonb, now(), null, null, '00000000-0000-0000-0000-000000160101', 'tester'
  );
  perform app.approve_rate_version(v_rate.id, v_rate.record_version, '00000000-0000-0000-0000-000000160101', 'tester');
  select * into v_selection from app.select_vendor_rate(v_request.id, v_rate.id, false, null, null, null, '00000000-0000-0000-0000-000000160102', 'tester');
  v_rule := app.create_margin_rule_version(v_tenant1, 20.00, 'half_up', '00000000-0000-0000-0000-000000160102', 'tester');
  perform app.publish_margin_rule_version(v_rule.id, v_rule.record_version, null, '00000000-0000-0000-0000-000000160102', 'tester');
  perform app.calculate_margin(v_selection.id, 6000000, 'IDR', 0, '00000000-0000-0000-0000-000000160102', 'tester');
  select id into v_calc_id from app.margin_calculations where rate_selection_id = v_selection.id and is_current;
  select * into v_quote from app.create_quotation_draft(v_tenant1, v_opportunity.id, 'IDR', now() + interval '14 days', v_contact.id, null, null, '00000000-0000-0000-0000-000000160102', 'tester');
  perform app.add_quotation_line(v_quote.id, v_quote.record_version, 'service', 'LBS235 Alpha lane', v_calc_id, 1, 6000000, 0, 0, '00000000-0000-0000-0000-000000160102', 'tester');
  select * into v_quote from app.quotations where id = v_quote.id;
  perform app.submit_quotation(v_quote.id, v_quote.record_version, '00000000-0000-0000-0000-000000160102', 'tester');
  select * into v_send from app.send_quotation_for_acceptance(v_quote.id, null, 'email', '00000000-0000-0000-0000-000000160102', 'tester');
  perform app.record_quotation_customer_decision(v_send.raw_token, 'accepted', 'Alice Lbs Ops', null, null, null, null, null);
  select * into v_quote from app.quotations where id = v_quote.id;
  select * into v_account from app.convert_quotation_to_account(v_quote.id, null, null, '00000000-0000-0000-0000-000000160102', 'rep');

  perform app.create_item_master(v_tenant1, v_account.id, 'SKU-LBS-PLAIN', 'Lbs Plain Widget', null, 'PCS', false, false, false, '00000000-0000-0000-0000-000000160102', 'rep');
  perform app.create_item_master(v_tenant1, v_account.id, 'SKU-LBS-LOT', 'Lbs Lot Widget', null, 'PCS', true, false, false, '00000000-0000-0000-0000-000000160102', 'rep');
  perform app.create_item_master(v_tenant1, v_account.id, 'SKU-LBS-SERIAL', 'Lbs Serial Widget', null, 'PCS', false, true, false, '00000000-0000-0000-0000-000000160102', 'rep');
  perform app.create_item_master(v_tenant1, v_account.id, 'SKU-LBS-EXP', 'Lbs Lot+Expiry Widget', null, 'PCS', true, false, true, '00000000-0000-0000-0000-000000160102', 'rep');

  -- Tenant2: fully isolated -- exists only to prove cross-tenant scope safety and the
  -- RBAC-before-idempotent-short-circuit ordering.
  perform app.provision_tenant('lbs2', 'Lot Batch Serial Tenant Two', 'idem-lbs2', 'tester');
  v_tenant2 := (select id from app.tenants where slug = 'lbs2');
  perform app.transition_tenant_status(v_tenant2, 'active', 'setup', 'tester');
  perform app.create_org_unit(v_tenant2, 'company', null, 'LBS2-CO', 'Lot Batch Serial Tenant Two Co', 'tester');
  v_company2 := (select id from app.org_units where tenant_id = v_tenant2 and code = 'LBS2-CO');
  perform app.invite_user(v_tenant2, '00000000-0000-0000-0000-000000160106', 'admin2@lbs2.test', 'Tenant2 Admin', v_company2, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'admin2@lbs2.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000160106', 'tenant_admin', v_tenant2, null, 'tester');
  perform app.invite_user(v_tenant2, '00000000-0000-0000-0000-000000160107', 'rep2b@lbs2.test', 'Tenant2 Rep', v_company2, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'rep2b@lbs2.test'), 'active', 'onboarded', 'tester');
  v_rep2_role := (app.create_role(v_tenant2, 'Tenant2 Rep Role', 'ops create/edit/view', 'tester')).id;
  v_rep2_draft := app.create_role_version(v_rep2_role, 'tester');
  perform app.set_role_version_permissions(v_rep2_draft.id, array(select id from app.permissions where resource_module_code = 'OPS' and action in ('Create', 'Edit', 'View')), 'tester');
  perform app.publish_role_version(v_rep2_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant2, (select id from app.role_versions where role_id = v_rep2_role and status = 'published'), '00000000-0000-0000-0000-000000160107', '00000000-0000-0000-0000-000000160106', 'tester');
end $$;

\echo '>> app.create_item_control_policy_version_draft / app.publish_item_control_policy_version: viewer rejected (OPS:Create); fefo/near_expiry_warning_days rejected on a non-expiry-controlled item (uncontrolled items avoid unnecessary fields); a real draft succeeds for the lot+expiry item; rep cannot publish (lacks OPS:Override); supervisor publishes; stale_version; a second draft cannot publish without supersedes_version_id (active_policy_exists), then succeeds with it (archiving the first); re-publishing an already-published row is rejected invalid_transition'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'lbs1');
  v_exp_id uuid := (select id from app.item_masters where tenant_id = v_tenant1 and code = 'SKU-LBS-EXP');
  v_plain_id uuid := (select id from app.item_masters where tenant_id = v_tenant1 and code = 'SKU-LBS-PLAIN');
  v_draft app.item_control_policy_versions;
  v_draft2 app.item_control_policy_versions;
  v_published app.item_control_policy_versions;
begin
  begin
    perform app.create_item_control_policy_version_draft(v_exp_id, 'fifo', true, null, null, '00000000-0000-0000-0000-000000160103', 'viewer');
    raise exception 'assertion failed: expected insufficient_authority for a viewer (lacks OPS:Create)';
  exception
    when others then
      if sqlerrm not like 'insufficient_authority%' then raise; end if;
  end;

  begin
    perform app.create_item_control_policy_version_draft(v_plain_id, 'fefo', true, null, null, '00000000-0000-0000-0000-000000160102', 'rep');
    raise exception 'assertion failed: expected invalid_allocation_rule -- fefo requires an expiry-controlled item';
  exception
    when others then
      if sqlerrm not like 'invalid_allocation_rule%' then raise; end if;
  end;

  begin
    perform app.create_item_control_policy_version_draft(v_plain_id, 'fifo', true, 10, null, '00000000-0000-0000-0000-000000160102', 'rep');
    raise exception 'assertion failed: expected invalid_near_expiry_warning_days on a non-expiry-controlled item';
  exception
    when others then
      if sqlerrm not like 'invalid_near_expiry_warning_days%' then raise; end if;
  end;

  v_draft := app.create_item_control_policy_version_draft(v_exp_id, 'fefo', true, 10, null, '00000000-0000-0000-0000-000000160102', 'rep');
  if v_draft.status <> 'draft' or v_draft.allocation_rule <> 'fefo' or v_draft.near_expiry_warning_days <> 10 then
    raise exception 'assertion failed: expected a real fefo draft with near_expiry_warning_days=10, got status=% allocation_rule=% near_expiry=%', v_draft.status, v_draft.allocation_rule, v_draft.near_expiry_warning_days;
  end if;

  begin
    perform app.publish_item_control_policy_version(v_draft.id, v_draft.record_version, null, '00000000-0000-0000-0000-000000160102', 'rep');
    raise exception 'assertion failed: expected insufficient_authority for a rep (lacks OPS:Override)';
  exception
    when others then
      if sqlerrm not like 'insufficient_authority%' then raise; end if;
  end;

  begin
    perform app.publish_item_control_policy_version(v_draft.id, 999999, null, '00000000-0000-0000-0000-000000160104', 'supervisor');
    raise exception 'assertion failed: expected stale_version';
  exception
    when others then
      if sqlerrm not like 'stale_version%' then raise; end if;
  end;

  v_published := app.publish_item_control_policy_version(v_draft.id, v_draft.record_version, null, '00000000-0000-0000-0000-000000160104', 'supervisor');
  if v_published.status <> 'published' then
    raise exception 'assertion failed: expected the draft to be published, got %', v_published.status;
  end if;

  begin
    perform app.publish_item_control_policy_version(v_published.id, v_published.record_version, null, '00000000-0000-0000-0000-000000160104', 'supervisor');
    raise exception 'assertion failed: expected invalid_transition -- an already-published policy cannot be published again';
  exception
    when others then
      if sqlerrm not like 'invalid_transition%' then raise; end if;
  end;

  v_draft2 := app.create_item_control_policy_version_draft(v_exp_id, 'fifo', false, 5, null, '00000000-0000-0000-0000-000000160102', 'rep');

  begin
    perform app.publish_item_control_policy_version(v_draft2.id, v_draft2.record_version, null, '00000000-0000-0000-0000-000000160104', 'supervisor');
    raise exception 'assertion failed: expected active_policy_exists -- the item already has a published policy';
  exception
    when others then
      if sqlerrm not like 'active_policy_exists%' then raise; end if;
  end;

  v_published := app.publish_item_control_policy_version(v_draft2.id, v_draft2.record_version, v_published.id, '00000000-0000-0000-0000-000000160104', 'supervisor');
  if v_published.status <> 'published' or v_published.allocation_rule <> 'fifo' then
    raise exception 'assertion failed: expected the second draft to publish with allocation_rule=fifo, got status=% allocation_rule=%', v_published.status, v_published.allocation_rule;
  end if;
  if (select status from app.item_control_policy_versions where id = v_draft.id) <> 'archived' then
    raise exception 'assertion failed: expected the first published policy to be archived once superseded';
  end if;

  if (app.get_item_control_policy(v_exp_id, '00000000-0000-0000-0000-000000160102')).id <> v_published.id then
    raise exception 'assertion failed: expected app.get_item_control_policy to return the currently published version';
  end if;
end $$;

\echo '>> app.register_lot_identity: viewer rejected; item_not_lot_controlled on the plain item; invalid_lot_number; item_master_not_found; a real registration on SKU-LBS-LOT (no published policy yet) defaults to status=held (hold_on_unknown_lot safe default); idempotent replay on the identical natural key; invalid_date_order; genealogy split (parent_lot_not_found, genealogy_mismatch across items, then a real successful split with parent_lot_id set)'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'lbs1');
  v_lot_id uuid := (select id from app.item_masters where tenant_id = v_tenant1 and code = 'SKU-LBS-LOT');
  v_plain_id uuid := (select id from app.item_masters where tenant_id = v_tenant1 and code = 'SKU-LBS-PLAIN');
  v_exp_id uuid := (select id from app.item_masters where tenant_id = v_tenant1 and code = 'SKU-LBS-EXP');
  v_lot app.lot_identities;
  v_lot_replay app.lot_identities;
  v_parent app.lot_identities;
  v_child app.lot_identities;
begin
  begin
    perform app.register_lot_identity(v_lot_id, 'LOT-VIEWER-1', null, null, 'receipt', null, null, '00000000-0000-0000-0000-000000160103', 'viewer');
    raise exception 'assertion failed: expected insufficient_authority for a viewer (lacks OPS:Create)';
  exception
    when others then
      if sqlerrm not like 'insufficient_authority%' then raise; end if;
  end;

  begin
    perform app.register_lot_identity(v_plain_id, 'LOT-PLAIN-1', null, null, 'receipt', null, null, '00000000-0000-0000-0000-000000160102', 'rep');
    raise exception 'assertion failed: expected item_not_lot_controlled on the plain item';
  exception
    when others then
      if sqlerrm not like 'item_not_lot_controlled%' then raise; end if;
  end;

  begin
    perform app.register_lot_identity(v_lot_id, '   ', null, null, 'receipt', null, null, '00000000-0000-0000-0000-000000160102', 'rep');
    raise exception 'assertion failed: expected invalid_lot_number for a blank lot number';
  exception
    when others then
      if sqlerrm not like 'invalid_lot_number%' then raise; end if;
  end;

  begin
    perform app.register_lot_identity('00000000-0000-0000-0000-000000000000', 'LOT-NOPE', null, null, 'receipt', null, null, '00000000-0000-0000-0000-000000160102', 'rep');
    raise exception 'assertion failed: expected item_master_not_found';
  exception
    when others then
      if sqlerrm not like 'item_master_not_found%' then raise; end if;
  end;

  v_lot := app.register_lot_identity(v_lot_id, 'LOT-DEFAULT-HOLD', null, null, 'receipt', null, null, '00000000-0000-0000-0000-000000160102', 'rep');
  if v_lot.status <> 'held' or v_lot.hold_reason <> 'hold_on_unknown_lot_policy_default' then
    raise exception 'assertion failed: expected a lot registered with no published policy to default to held, got status=% hold_reason=%', v_lot.status, v_lot.hold_reason;
  end if;

  v_lot_replay := app.register_lot_identity(v_lot_id, 'LOT-DEFAULT-HOLD', '2026-01-01', null, 'receipt', null, null, '00000000-0000-0000-0000-000000160102', 'rep');
  if v_lot_replay.id <> v_lot.id or v_lot_replay.manufacture_date is not null then
    raise exception 'assertion failed: expected a natural-key replay to return the identical, unchanged row (manufacture_date must still be null)';
  end if;

  begin
    perform app.register_lot_identity(v_exp_id, 'LOT-BADDATES', '2026-08-01', '2026-01-01', 'receipt', null, null, '00000000-0000-0000-0000-000000160102', 'rep');
    raise exception 'assertion failed: expected invalid_date_order (expiry precedes manufacture)';
  exception
    when others then
      if sqlerrm not like 'invalid_date_order%' then raise; end if;
  end;

  begin
    perform app.register_lot_identity(v_lot_id, 'LOT-EXPNA-1', null, '2026-12-31', 'receipt', null, null, '00000000-0000-0000-0000-000000160102', 'rep');
    raise exception 'assertion failed: expected expiry_date_not_applicable (own, distinct error code, not invalid_near_expiry_warning_days) -- SKU-LBS-LOT is not expiry-controlled';
  exception
    when others then
      if sqlerrm not like 'expiry_date_not_applicable%' then raise; end if;
  end;

  begin
    perform app.register_lot_identity(v_exp_id, 'LOT-BADPARENT', null, null, 'split', null, '00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-000000160102', 'rep');
    raise exception 'assertion failed: expected parent_lot_not_found';
  exception
    when others then
      if sqlerrm not like 'parent_lot_not_found%' then raise; end if;
  end;

  begin
    perform app.register_lot_identity(v_exp_id, 'LOT-CROSSITEM-CHILD', null, null, 'split', null, v_lot.id, '00000000-0000-0000-0000-000000160102', 'rep');
    raise exception 'assertion failed: expected genealogy_mismatch -- parent lot belongs to a different item';
  exception
    when others then
      if sqlerrm not like 'genealogy_mismatch%' then raise; end if;
  end;

  v_parent := app.register_lot_identity(v_exp_id, 'LOT-PARENT-1', current_date - 30, current_date + 300, 'receipt', null, null, '00000000-0000-0000-0000-000000160102', 'rep');

  begin
    perform app.register_lot_identity(v_exp_id, 'LOT-CHILD-BADSOURCE', null, null, 'receipt', null, v_parent.id, '00000000-0000-0000-0000-000000160102', 'rep');
    raise exception 'assertion failed: expected genealogy_mismatch -- a parent_lot_id requires source_type=split';
  exception
    when others then
      if sqlerrm not like 'genealogy_mismatch%' then raise; end if;
  end;

  v_child := app.register_lot_identity(v_exp_id, 'LOT-CHILD-1', current_date - 10, current_date + 300, 'split', null, v_parent.id, '00000000-0000-0000-0000-000000160102', 'rep');
  if v_child.parent_lot_id <> v_parent.id or v_child.source_type <> 'split' then
    raise exception 'assertion failed: expected the child lot to reference its own real parent_lot_id';
  end if;
end $$;

\echo '>> app.register_lot_identity honors a published hold_on_unknown_lot=false policy: publishing a policy for SKU-LBS-LOT with hold_on_unknown_lot=false, then a NEW lot registration comes back status=active immediately (no hold)'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'lbs1');
  v_lot_id uuid := (select id from app.item_masters where tenant_id = v_tenant1 and code = 'SKU-LBS-LOT');
  v_draft app.item_control_policy_versions;
  v_lot app.lot_identities;
begin
  v_draft := app.create_item_control_policy_version_draft(v_lot_id, 'fifo', false, null, null, '00000000-0000-0000-0000-000000160102', 'rep');
  perform app.publish_item_control_policy_version(v_draft.id, v_draft.record_version, null, '00000000-0000-0000-0000-000000160104', 'supervisor');

  v_lot := app.register_lot_identity(v_lot_id, 'LOT-NOHOLD-1', null, null, 'receipt', null, null, '00000000-0000-0000-0000-000000160102', 'rep');
  if v_lot.status <> 'active' or v_lot.hold_reason is not null then
    raise exception 'assertion failed: expected a new lot to register active with hold_on_unknown_lot=false, got status=% hold_reason=%', v_lot.status, v_lot.hold_reason;
  end if;
end $$;

\echo '>> app.register_serial_identity: viewer rejected; item_not_serial_controlled on the plain item; invalid_serial_number; invalid_idempotency_key; a real registration on SKU-LBS-SERIAL (no published policy yet) defaults to status=held; idempotent replay on the identical idempotency_key; duplicate_serial on a DIFFERENT idempotency_key colliding on the real governed-scope unique index; item_not_lot_controlled when a lot_number is attached to a non-lot-controlled item; a published hold_on_unknown_lot=false policy makes a new serial register active immediately'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'lbs1');
  v_serial_id uuid := (select id from app.item_masters where tenant_id = v_tenant1 and code = 'SKU-LBS-SERIAL');
  v_plain_id uuid := (select id from app.item_masters where tenant_id = v_tenant1 and code = 'SKU-LBS-PLAIN');
  v_serial app.serial_identities;
  v_serial_replay app.serial_identities;
  v_draft app.item_control_policy_versions;
  v_serial2 app.serial_identities;
begin
  begin
    perform app.register_serial_identity(v_serial_id, 'SN-VIEWER-1', null, null, null, 'receipt', null, 'idem-sn-viewer-1', '00000000-0000-0000-0000-000000160103', 'viewer');
    raise exception 'assertion failed: expected insufficient_authority for a viewer (lacks OPS:Create)';
  exception
    when others then
      if sqlerrm not like 'insufficient_authority%' then raise; end if;
  end;

  begin
    perform app.register_serial_identity(v_plain_id, 'SN-PLAIN-1', null, null, null, 'receipt', null, 'idem-sn-plain-1', '00000000-0000-0000-0000-000000160102', 'rep');
    raise exception 'assertion failed: expected item_not_serial_controlled on the plain item';
  exception
    when others then
      if sqlerrm not like 'item_not_serial_controlled%' then raise; end if;
  end;

  begin
    perform app.register_serial_identity(v_serial_id, '  ', null, null, null, 'receipt', null, 'idem-sn-blank-1', '00000000-0000-0000-0000-000000160102', 'rep');
    raise exception 'assertion failed: expected invalid_serial_number for a blank serial number';
  exception
    when others then
      if sqlerrm not like 'invalid_serial_number%' then raise; end if;
  end;

  begin
    perform app.register_serial_identity(v_serial_id, 'SN-NOIDEM-1', null, null, null, 'receipt', null, '', '00000000-0000-0000-0000-000000160102', 'rep');
    raise exception 'assertion failed: expected invalid_idempotency_key for an empty idempotency key';
  exception
    when others then
      if sqlerrm not like 'invalid_idempotency_key%' then raise; end if;
  end;

  begin
    perform app.register_serial_identity(v_serial_id, 'SN-EXPNA-1', null, null, '2026-12-31', 'receipt', null, 'idem-sn-expna-1', '00000000-0000-0000-0000-000000160102', 'rep');
    raise exception 'assertion failed: expected expiry_date_not_applicable (own, distinct error code, not invalid_near_expiry_warning_days) -- SKU-LBS-SERIAL is not expiry-controlled';
  exception
    when others then
      if sqlerrm not like 'expiry_date_not_applicable%' then raise; end if;
  end;

  v_serial := app.register_serial_identity(v_serial_id, 'SN-DEFAULT-HOLD', null, null, null, 'receipt', null, 'idem-sn-default-hold', '00000000-0000-0000-0000-000000160102', 'rep');
  if v_serial.status <> 'held' or v_serial.hold_reason <> 'hold_on_unknown_lot_policy_default' then
    raise exception 'assertion failed: expected a serial registered with no published policy to default to held, got status=% hold_reason=%', v_serial.status, v_serial.hold_reason;
  end if;

  v_serial_replay := app.register_serial_identity(v_serial_id, 'SN-DEFAULT-HOLD', null, null, null, 'receipt', null, 'idem-sn-default-hold', '00000000-0000-0000-0000-000000160102', 'rep');
  if v_serial_replay.id <> v_serial.id then
    raise exception 'assertion failed: expected an identical-idempotency-key replay to return the identical row';
  end if;

  begin
    perform app.register_serial_identity(v_serial_id, 'SN-DEFAULT-HOLD', null, null, null, 'receipt', null, 'idem-sn-duplicate-attempt', '00000000-0000-0000-0000-000000160102', 'rep');
    raise exception 'assertion failed: expected duplicate_serial -- a different idempotency key colliding on the real governed-scope unique index (tenant, item, serial_number)';
  exception
    when others then
      if sqlerrm not like 'duplicate_serial%' then raise; end if;
  end;

  begin
    perform app.register_serial_identity(v_serial_id, 'SN-WITHLOT-1', 'LOT-DOESNT-MATTER', null, null, 'receipt', null, 'idem-sn-withlot-1', '00000000-0000-0000-0000-000000160102', 'rep');
    raise exception 'assertion failed: expected item_not_lot_controlled -- SKU-LBS-SERIAL is not lot-controlled';
  exception
    when others then
      if sqlerrm not like 'item_not_lot_controlled%' then raise; end if;
  end;

  v_draft := app.create_item_control_policy_version_draft(v_serial_id, 'fifo', false, null, null, '00000000-0000-0000-0000-000000160102', 'rep');
  perform app.publish_item_control_policy_version(v_draft.id, v_draft.record_version, null, '00000000-0000-0000-0000-000000160104', 'supervisor');

  v_serial2 := app.register_serial_identity(v_serial_id, 'SN-NOHOLD-1', null, null, null, 'receipt', null, 'idem-sn-nohold-1', '00000000-0000-0000-0000-000000160102', 'rep');
  if v_serial2.status <> 'active' then
    raise exception 'assertion failed: expected a new serial to register active with hold_on_unknown_lot=false, got status=%', v_serial2.status;
  end if;
end $$;

\echo '>> RBAC-before-short-circuit regression on app.register_lot_identity/app.register_serial_identity: tenant2''s rep, who holds zero membership in tenant1, is rejected insufficient_authority attempting the identical natural-key/idempotency-key replay against tenant1''s real already-registered identities -- never handed live business data off either idempotent short-circuit'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'lbs1');
  v_lot_id uuid := (select id from app.item_masters where tenant_id = v_tenant1 and code = 'SKU-LBS-LOT');
  v_serial_id uuid := (select id from app.item_masters where tenant_id = v_tenant1 and code = 'SKU-LBS-SERIAL');
begin
  begin
    perform app.register_lot_identity(v_lot_id, 'LOT-DEFAULT-HOLD', null, null, 'receipt', null, null, '00000000-0000-0000-0000-000000160107', 'rep2b-attacker');
    raise exception 'assertion failed: expected insufficient_authority -- tenant2''s rep must not reach app.register_lot_identity''s own idempotent replay short-circuit on tenant1''s real lot';
  exception
    when others then
      if sqlerrm not like 'insufficient_authority%' then raise; end if;
  end;

  begin
    perform app.register_serial_identity(v_serial_id, 'SN-DEFAULT-HOLD', null, null, null, 'receipt', null, 'idem-sn-default-hold', '00000000-0000-0000-0000-000000160107', 'rep2b-attacker');
    raise exception 'assertion failed: expected insufficient_authority -- tenant2''s rep must not reach app.register_serial_identity''s own idempotent replay short-circuit on tenant1''s real serial';
  exception
    when others then
      if sqlerrm not like 'insufficient_authority%' then raise; end if;
  end;
end $$;

\echo '>> app.set_lot_identity_status / app.set_serial_identity_status: viewer and rep both rejected (OPS:Override required); invalid_status; stale_version; a real release (held -> active, no reason required); an idempotent no-op replay (even under a deliberately WRONG expected_version, proving the no-op short-circuit runs before the version check); invalid_reason (a non-active target requires a reason); consumed is terminal (invalid_transition back to active)'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'lbs1');
  v_lot_id uuid := (select id from app.item_masters where tenant_id = v_tenant1 and code = 'SKU-LBS-LOT');
  v_serial_id uuid := (select id from app.item_masters where tenant_id = v_tenant1 and code = 'SKU-LBS-SERIAL');
  v_lot app.lot_identities;
  v_lot_replay app.lot_identities;
  v_serial app.serial_identities;
begin
  select * into v_lot from app.lot_identities where tenant_id = v_tenant1 and item_master_id = v_lot_id and lot_number = 'LOT-DEFAULT-HOLD';
  select * into v_serial from app.serial_identities where tenant_id = v_tenant1 and item_master_id = v_serial_id and serial_number = 'SN-DEFAULT-HOLD';

  begin
    perform app.set_lot_identity_status(v_lot.id, 'active', null, v_lot.record_version, '00000000-0000-0000-0000-000000160103', 'viewer');
    raise exception 'assertion failed: expected insufficient_authority for a viewer (lacks OPS:Override)';
  exception
    when others then
      if sqlerrm not like 'insufficient_authority%' then raise; end if;
  end;

  begin
    perform app.set_lot_identity_status(v_lot.id, 'active', null, v_lot.record_version, '00000000-0000-0000-0000-000000160102', 'rep');
    raise exception 'assertion failed: expected insufficient_authority for a rep (lacks OPS:Override)';
  exception
    when others then
      if sqlerrm not like 'insufficient_authority%' then raise; end if;
  end;

  begin
    perform app.set_lot_identity_status(v_lot.id, 'shipped', null, v_lot.record_version, '00000000-0000-0000-0000-000000160104', 'supervisor');
    raise exception 'assertion failed: expected invalid_status for an unrecognized status';
  exception
    when others then
      if sqlerrm not like 'invalid_status%' then raise; end if;
  end;

  begin
    perform app.set_lot_identity_status(v_lot.id, 'active', null, 999999, '00000000-0000-0000-0000-000000160104', 'supervisor');
    raise exception 'assertion failed: expected stale_version';
  exception
    when others then
      if sqlerrm not like 'stale_version%' then raise; end if;
  end;

  v_lot := app.set_lot_identity_status(v_lot.id, 'active', null, v_lot.record_version, '00000000-0000-0000-0000-000000160104', 'supervisor');
  if v_lot.status <> 'active' or v_lot.hold_reason is not null then
    raise exception 'assertion failed: expected the lot to release to active with no reason required, got status=% hold_reason=%', v_lot.status, v_lot.hold_reason;
  end if;

  -- Idempotent no-op replay -- a deliberately wrong expected_version (999999) is
  -- supplied to prove the same-status short-circuit runs BEFORE the stale_version
  -- check, not after.
  v_lot_replay := app.set_lot_identity_status(v_lot.id, 'active', null, 999999, '00000000-0000-0000-0000-000000160104', 'supervisor');
  if v_lot_replay.id <> v_lot.id or v_lot_replay.record_version <> v_lot.record_version then
    raise exception 'assertion failed: expected the same-status no-op replay to return the row unchanged despite a mismatched expected_version';
  end if;

  begin
    perform app.set_lot_identity_status(v_lot.id, 'held', null, v_lot.record_version, '00000000-0000-0000-0000-000000160104', 'supervisor');
    raise exception 'assertion failed: expected invalid_reason -- a non-active target status requires a non-empty reason';
  exception
    when others then
      if sqlerrm not like 'invalid_reason%' then raise; end if;
  end;

  v_lot := app.set_lot_identity_status(v_lot.id, 'consumed', 'fully allocated and shipped out', v_lot.record_version, '00000000-0000-0000-0000-000000160104', 'supervisor');
  if v_lot.status <> 'consumed' then
    raise exception 'assertion failed: expected the lot to transition to consumed';
  end if;

  begin
    perform app.set_lot_identity_status(v_lot.id, 'active', 'attempted revival', v_lot.record_version, '00000000-0000-0000-0000-000000160104', 'supervisor');
    raise exception 'assertion failed: expected invalid_transition -- consumed is terminal';
  exception
    when others then
      if sqlerrm not like 'invalid_transition%' then raise; end if;
  end;

  -- Mirror the identical shape once for app.set_serial_identity_status.
  v_serial := app.set_serial_identity_status(v_serial.id, 'active', null, v_serial.record_version, '00000000-0000-0000-0000-000000160104', 'supervisor');
  if v_serial.status <> 'active' then
    raise exception 'assertion failed: expected the serial to release to active';
  end if;
  v_serial := app.set_serial_identity_status(v_serial.id, 'held', 'quality recheck requested', v_serial.record_version, '00000000-0000-0000-0000-000000160104', 'supervisor');
  if v_serial.status <> 'held' or v_serial.hold_reason <> 'quality recheck requested' then
    raise exception 'assertion failed: expected the serial to hold with its own real reason';
  end if;
end $$;

\echo '>> RBAC-before-short-circuit regression on app.set_lot_identity_status/app.set_serial_identity_status: tenant2''s rep is rejected insufficient_authority attempting the identical same-status no-op replay against tenant1''s real already-active records'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'lbs1');
  v_lot_id uuid := (select id from app.item_masters where tenant_id = v_tenant1 and code = 'SKU-LBS-LOT');
  v_serial_id uuid := (select id from app.item_masters where tenant_id = v_tenant1 and code = 'SKU-LBS-SERIAL');
  v_lot app.lot_identities;
  v_serial app.serial_identities;
begin
  select * into v_lot from app.lot_identities where tenant_id = v_tenant1 and item_master_id = v_lot_id and lot_number = 'LOT-DEFAULT-HOLD';
  select * into v_serial from app.serial_identities where tenant_id = v_tenant1 and item_master_id = v_serial_id and serial_number = 'SN-DEFAULT-HOLD';

  begin
    perform app.set_lot_identity_status(v_lot.id, v_lot.status, null, v_lot.record_version, '00000000-0000-0000-0000-000000160107', 'rep2b-attacker');
    raise exception 'assertion failed: expected insufficient_authority -- tenant2''s rep must not reach app.set_lot_identity_status''s own no-op short-circuit on tenant1''s real lot';
  exception
    when others then
      if sqlerrm not like 'insufficient_authority%' then raise; end if;
  end;

  begin
    perform app.set_serial_identity_status(v_serial.id, v_serial.status, null, v_serial.record_version, '00000000-0000-0000-0000-000000160107', 'rep2b-attacker');
    raise exception 'assertion failed: expected insufficient_authority -- tenant2''s rep must not reach app.set_serial_identity_status''s own no-op short-circuit on tenant1''s real serial';
  exception
    when others then
      if sqlerrm not like 'insufficient_authority%' then raise; end if;
  end;
end $$;

\echo '>> FIFO/FEFO allocation candidates: real opening_balance inventory is posted for SKU-LBS-EXP across two active lots (LOT-B registered first with a LATER expiry, LOT-A registered second with a NEARER expiry) plus one held lot and one expired-but-active-status lot, and for SKU-LBS-SERIAL across one active and one held serial; app.list_allocation_candidates excludes the held and the truly-expired rows in every case, resolves fefo automatically from the item''s own published policy (LOT-A before LOT-B, nearer expiry first), an explicit p_allocation_rule=fifo override instead orders by registration order (LOT-B before LOT-A), near_expiry is computed from the policy''s own near_expiry_warning_days, and invalid_allocation_rule/warehouse_not_found are both rejected'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'lbs1');
  v_warehouse_id uuid := (select id from app.warehouses where tenant_id = v_tenant1 and code = 'WH-LBS-1');
  v_rack_a_id uuid := (select id from app.warehouse_locations where tenant_id = v_tenant1 and code = 'RACK-LBS-A');
  v_account_id uuid := (select id from app.accounts where tenant_id = v_tenant1 and legal_name = 'Lbs Customer Alpha');
  v_exp_id uuid := (select id from app.item_masters where tenant_id = v_tenant1 and code = 'SKU-LBS-EXP');
  v_serial_id uuid := (select id from app.item_masters where tenant_id = v_tenant1 and code = 'SKU-LBS-SERIAL');
  v_lot_b app.lot_identities;
  v_lot_a app.lot_identities;
  v_lot_held app.lot_identities;
  v_lot_expired app.lot_identities;
  v_serial_active app.serial_identities;
  v_serial_held app.serial_identities;
  v_candidates record;
  v_rows record;
  v_count integer;
  v_order text[];
begin
  -- LOT-B first (later expiry), then LOT-A (nearer expiry) -- registration order is
  -- deliberately the REVERSE of expiry order, so fifo vs fefo produce provably
  -- different orderings below. SKU-LBS-EXP's own currently published policy already
  -- has hold_on_unknown_lot=false (set in the policy-lifecycle test above), so every
  -- one of these registers status=active immediately -- v_lot_held is explicitly put
  -- back on hold afterward, and the truly-expired lot is left active on purpose (its
  -- real expiry_date, not its status, is what must exclude it from candidates).
  v_lot_b := app.register_lot_identity(v_exp_id, 'LOT-CAND-B', current_date - 5, current_date + 200, 'receipt', null, null, '00000000-0000-0000-0000-000000160102', 'rep');
  v_lot_a := app.register_lot_identity(v_exp_id, 'LOT-CAND-A', current_date - 5, current_date + 5, 'receipt', null, null, '00000000-0000-0000-0000-000000160102', 'rep');
  v_lot_held := app.register_lot_identity(v_exp_id, 'LOT-CAND-HELD', current_date - 5, current_date + 100, 'receipt', null, null, '00000000-0000-0000-0000-000000160102', 'rep');
  v_lot_expired := app.register_lot_identity(v_exp_id, 'LOT-CAND-EXPIRED', current_date - 400, current_date - 1, 'receipt', null, null, '00000000-0000-0000-0000-000000160102', 'rep');

  if v_lot_b.status <> 'active' or v_lot_a.status <> 'active' or v_lot_expired.status <> 'active' then
    raise exception 'assertion failed: expected LOT-CAND-B/A/EXPIRED to register active by default (SKU-LBS-EXP''s published policy has hold_on_unknown_lot=false)';
  end if;

  perform app.set_lot_identity_status(v_lot_held.id, 'held', 'quality hold fixture', v_lot_held.record_version, '00000000-0000-0000-0000-000000160104', 'supervisor');

  perform app.post_inventory_movement(
    v_tenant1, v_warehouse_id, 'opening_balance', 'opening_balance', null, 'idem-cand-open-b', 'opening balance fixture',
    jsonb_build_array(jsonb_build_object('owner_account_id', v_account_id, 'item_master_id', v_exp_id, 'location_id', v_rack_a_id, 'uom_code', 'PCS', 'signed_quantity', 10, 'lot_number', 'LOT-CAND-B', 'status', 'on_hand')),
    '00000000-0000-0000-0000-000000160102', 'rep'
  );
  perform app.post_inventory_movement(
    v_tenant1, v_warehouse_id, 'opening_balance', 'opening_balance', null, 'idem-cand-open-a', 'opening balance fixture',
    jsonb_build_array(jsonb_build_object('owner_account_id', v_account_id, 'item_master_id', v_exp_id, 'location_id', v_rack_a_id, 'uom_code', 'PCS', 'signed_quantity', 10, 'lot_number', 'LOT-CAND-A', 'status', 'on_hand')),
    '00000000-0000-0000-0000-000000160102', 'rep'
  );
  perform app.post_inventory_movement(
    v_tenant1, v_warehouse_id, 'opening_balance', 'opening_balance', null, 'idem-cand-open-held', 'opening balance fixture',
    jsonb_build_array(jsonb_build_object('owner_account_id', v_account_id, 'item_master_id', v_exp_id, 'location_id', v_rack_a_id, 'uom_code', 'PCS', 'signed_quantity', 5, 'lot_number', 'LOT-CAND-HELD', 'status', 'on_hand')),
    '00000000-0000-0000-0000-000000160102', 'rep'
  );
  perform app.post_inventory_movement(
    v_tenant1, v_warehouse_id, 'opening_balance', 'opening_balance', null, 'idem-cand-open-expired', 'opening balance fixture',
    jsonb_build_array(jsonb_build_object('owner_account_id', v_account_id, 'item_master_id', v_exp_id, 'location_id', v_rack_a_id, 'uom_code', 'PCS', 'signed_quantity', 5, 'lot_number', 'LOT-CAND-EXPIRED', 'status', 'on_hand')),
    '00000000-0000-0000-0000-000000160102', 'rep'
  );

  -- SKU-LBS-SERIAL's own currently published policy already has hold_on_unknown_lot=
  -- false too (set in the register_serial_identity test above), so both register
  -- status=active immediately -- v_serial_held is explicitly put back on hold after.
  v_serial_active := app.register_serial_identity(v_serial_id, 'SN-CAND-ACTIVE', null, null, null, 'receipt', null, 'idem-sn-cand-active', '00000000-0000-0000-0000-000000160102', 'rep');
  v_serial_held := app.register_serial_identity(v_serial_id, 'SN-CAND-HELD', null, null, null, 'receipt', null, 'idem-sn-cand-held', '00000000-0000-0000-0000-000000160102', 'rep');
  if v_serial_active.status <> 'active' then
    raise exception 'assertion failed: expected SN-CAND-ACTIVE to register active by default (SKU-LBS-SERIAL''s published policy has hold_on_unknown_lot=false)';
  end if;
  perform app.set_serial_identity_status(v_serial_held.id, 'held', 'quality hold fixture', v_serial_held.record_version, '00000000-0000-0000-0000-000000160104', 'supervisor');

  perform app.post_inventory_movement(
    v_tenant1, v_warehouse_id, 'opening_balance', 'opening_balance', null, 'idem-cand-open-sn-active', 'opening balance fixture',
    jsonb_build_array(jsonb_build_object('owner_account_id', v_account_id, 'item_master_id', v_serial_id, 'location_id', v_rack_a_id, 'uom_code', 'PCS', 'signed_quantity', 1, 'serial_number', 'SN-CAND-ACTIVE', 'status', 'on_hand')),
    '00000000-0000-0000-0000-000000160102', 'rep'
  );
  perform app.post_inventory_movement(
    v_tenant1, v_warehouse_id, 'opening_balance', 'opening_balance', null, 'idem-cand-open-sn-held', 'opening balance fixture',
    jsonb_build_array(jsonb_build_object('owner_account_id', v_account_id, 'item_master_id', v_serial_id, 'location_id', v_rack_a_id, 'uom_code', 'PCS', 'signed_quantity', 1, 'serial_number', 'SN-CAND-HELD', 'status', 'on_hand')),
    '00000000-0000-0000-0000-000000160102', 'rep'
  );

  -- Default (no p_allocation_rule) resolves the item's own published policy (fefo) --
  -- LOT-A (nearer expiry) must rank before LOT-B; the held and truly-expired lots must
  -- never appear.
  select count(*) into v_count from app.list_allocation_candidates(v_tenant1, v_warehouse_id, v_exp_id, null, '00000000-0000-0000-0000-000000160102', null, 50);
  if v_count <> 2 then
    raise exception 'assertion failed: expected exactly 2 lot candidates (LOT-A, LOT-B), got %', v_count;
  end if;

  select array_agg(c.lot_number order by c.expiry_date) into v_order from app.list_allocation_candidates(v_tenant1, v_warehouse_id, v_exp_id, null, '00000000-0000-0000-0000-000000160102', null, 50) c;
  if v_order[1] <> 'LOT-CAND-A' or v_order[2] <> 'LOT-CAND-B' then
    raise exception 'assertion failed: expected fefo default ordering LOT-CAND-A before LOT-CAND-B by expiry_date, got %', v_order;
  end if;

  select array_agg(c.lot_number) into v_order from (
    select * from app.list_allocation_candidates(v_tenant1, v_warehouse_id, v_exp_id, null, '00000000-0000-0000-0000-000000160102', 'fifo', 50)
  ) c;
  if v_order[1] <> 'LOT-CAND-B' or v_order[2] <> 'LOT-CAND-A' then
    raise exception 'assertion failed: expected an explicit fifo override to order by registration order (LOT-CAND-B before LOT-CAND-A), got %', v_order;
  end if;

  select c.near_expiry into v_candidates from app.list_allocation_candidates(v_tenant1, v_warehouse_id, v_exp_id, null, '00000000-0000-0000-0000-000000160102', null, 50) c where c.lot_number = 'LOT-CAND-A';
  if v_candidates.near_expiry is distinct from true then
    raise exception 'assertion failed: expected LOT-CAND-A (expiry in 5 days, near_expiry_warning_days=10) to be flagged near_expiry';
  end if;
  select c.near_expiry into v_candidates from app.list_allocation_candidates(v_tenant1, v_warehouse_id, v_exp_id, null, '00000000-0000-0000-0000-000000160102', null, 50) c where c.lot_number = 'LOT-CAND-B';
  if v_candidates.near_expiry is distinct from false then
    raise exception 'assertion failed: expected LOT-CAND-B (expiry in 200 days) not to be flagged near_expiry';
  end if;

  select count(*) into v_count from app.list_allocation_candidates(v_tenant1, v_warehouse_id, v_serial_id, null, '00000000-0000-0000-0000-000000160102', null, 50);
  if v_count <> 1 then
    raise exception 'assertion failed: expected exactly 1 serial candidate (SN-CAND-ACTIVE, held excluded), got %', v_count;
  end if;

  begin
    perform app.list_allocation_candidates(v_tenant1, v_warehouse_id, v_exp_id, null, '00000000-0000-0000-0000-000000160102', 'lifo', 50);
    raise exception 'assertion failed: expected invalid_allocation_rule for lifo';
  exception
    when others then
      if sqlerrm not like 'invalid_allocation_rule%' then raise; end if;
  end;

  begin
    perform app.list_allocation_candidates(v_tenant1, '00000000-0000-0000-0000-000000000000', v_exp_id, null, '00000000-0000-0000-0000-000000160102', null, 50);
    raise exception 'assertion failed: expected warehouse_not_found';
  exception
    when others then
      if sqlerrm not like 'warehouse_not_found%' then raise; end if;
  end;
end $$;

\echo '>> trace reads: app.get_lot_trace / app.get_serial_trace return every real app.inventory_movement_lines row referencing the given lot/serial dimension, in chronological order (a real transfer additionally traced), and are RBAC-gated'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'lbs1');
  v_warehouse_id uuid := (select id from app.warehouses where tenant_id = v_tenant1 and code = 'WH-LBS-1');
  v_rack_a_id uuid := (select id from app.warehouse_locations where tenant_id = v_tenant1 and code = 'RACK-LBS-A');
  v_rack_b_id uuid := (select id from app.warehouse_locations where tenant_id = v_tenant1 and code = 'RACK-LBS-B');
  v_account_id uuid := (select id from app.accounts where tenant_id = v_tenant1 and legal_name = 'Lbs Customer Alpha');
  v_exp_id uuid := (select id from app.item_masters where tenant_id = v_tenant1 and code = 'SKU-LBS-EXP');
  v_serial_id uuid := (select id from app.item_masters where tenant_id = v_tenant1 and code = 'SKU-LBS-SERIAL');
  v_lot_a app.lot_identities;
  v_serial_active app.serial_identities;
  v_count integer;
begin
  select * into v_lot_a from app.lot_identities where tenant_id = v_tenant1 and item_master_id = v_exp_id and lot_number = 'LOT-CAND-A';
  select * into v_serial_active from app.serial_identities where tenant_id = v_tenant1 and item_master_id = v_serial_id and serial_number = 'SN-CAND-ACTIVE';

  -- A real balanced transfer of LOT-CAND-A's own stock (RACK-LBS-A -> RACK-LBS-B) adds
  -- two more movement lines to its trace.
  perform app.post_inventory_movement(
    v_tenant1, v_warehouse_id, 'transfer', 'manual', null, 'idem-trace-transfer-a', 'trace fixture transfer',
    jsonb_build_array(
      jsonb_build_object('owner_account_id', v_account_id, 'item_master_id', v_exp_id, 'location_id', v_rack_a_id, 'uom_code', 'PCS', 'signed_quantity', -3, 'lot_number', 'LOT-CAND-A', 'status', 'on_hand'),
      jsonb_build_object('owner_account_id', v_account_id, 'item_master_id', v_exp_id, 'location_id', v_rack_b_id, 'uom_code', 'PCS', 'signed_quantity', 3, 'lot_number', 'LOT-CAND-A', 'status', 'on_hand')
    ),
    '00000000-0000-0000-0000-000000160102', 'rep'
  );

  select count(*) into v_count from app.get_lot_trace(v_lot_a.id, '00000000-0000-0000-0000-000000160102', 50);
  if v_count <> 3 then
    raise exception 'assertion failed: expected 3 trace rows for LOT-CAND-A (1 opening_balance + 2 transfer lines), got %', v_count;
  end if;

  select count(*) into v_count from app.get_serial_trace(v_serial_active.id, '00000000-0000-0000-0000-000000160102', 50);
  if v_count <> 1 then
    raise exception 'assertion failed: expected exactly 1 trace row for SN-CAND-ACTIVE, got %', v_count;
  end if;

  begin
    perform app.get_lot_trace(v_lot_a.id, '00000000-0000-0000-0000-000000160107');
    raise exception 'assertion failed: expected insufficient_authority -- tenant2''s rep has no membership in tenant1';
  exception
    when others then
      if sqlerrm not like 'insufficient_authority%' then raise; end if;
  end;
end $$;

\echo '>> bounded/filtered reads and cross-tenant isolation: app.list_item_control_policy_versions / app.list_lot_identities / app.list_serial_identities, all p_limit-clamped and status/item-filtered; tenant2 sees zero of tenant1''s rows'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'lbs1');
  v_tenant2 uuid := (select id from app.tenants where slug = 'lbs2');
  v_exp_id uuid := (select id from app.item_masters where tenant_id = v_tenant1 and code = 'SKU-LBS-EXP');
  v_count integer;
begin
  select count(*) into v_count from app.list_item_control_policy_versions(v_tenant1, '00000000-0000-0000-0000-000000160102', v_exp_id, null, 200);
  if v_count < 2 then
    raise exception 'assertion failed: expected at least 2 policy versions for SKU-LBS-EXP (draft + published), got %', v_count;
  end if;

  select count(*) into v_count from app.list_item_control_policy_versions(v_tenant1, '00000000-0000-0000-0000-000000160102', v_exp_id, 'archived', 200);
  if v_count <> 1 then
    raise exception 'assertion failed: expected exactly 1 archived policy version for SKU-LBS-EXP, got %', v_count;
  end if;

  select count(*) into v_count from app.list_lot_identities(v_tenant1, '00000000-0000-0000-0000-000000160102', v_exp_id, null, 'active', 200);
  if v_count < 3 then
    raise exception 'assertion failed: expected at least 3 active lots on SKU-LBS-EXP, got %', v_count;
  end if;

  select count(*) into v_count from app.list_lot_identities(v_tenant1, '00000000-0000-0000-0000-000000160102', v_exp_id, null, 'held', 200);
  if v_count <> 1 then
    raise exception 'assertion failed: expected exactly 1 held lot on SKU-LBS-EXP, got %', v_count;
  end if;

  select count(*) into v_count from app.list_lot_identities(v_tenant1, '00000000-0000-0000-0000-000000160102', null, null, null, 1);
  if v_count <> 1 then
    raise exception 'assertion failed: expected p_limit=1 to clamp the result to exactly 1 row, got %', v_count;
  end if;

  select count(*) into v_count from app.list_serial_identities(v_tenant1, '00000000-0000-0000-0000-000000160102', null, null, 'held', 200);
  if v_count < 1 then
    raise exception 'assertion failed: expected at least 1 held serial, got %', v_count;
  end if;

  select count(*) into v_count from app.list_item_control_policy_versions(v_tenant2, '00000000-0000-0000-0000-000000160107', null, null, 200);
  if v_count <> 0 then
    raise exception 'assertion failed: expected tenant2 to see zero policy versions (none created there), got %', v_count;
  end if;

  select count(*) into v_count from app.list_lot_identities(v_tenant2, '00000000-0000-0000-0000-000000160107', null, null, null, 200);
  if v_count <> 0 then
    raise exception 'assertion failed: expected tenant2 to see zero lot identities (none created there), got %', v_count;
  end if;

  select count(*) into v_count from app.list_serial_identities(v_tenant2, '00000000-0000-0000-0000-000000160107', null, null, null, 200);
  if v_count <> 0 then
    raise exception 'assertion failed: expected tenant2 to see zero serial identities (none created there), got %', v_count;
  end if;
end $$;

\echo '>> schema-privilege defense in depth (ERR-2026-004): anon holds no direct table/EXECUTE access; authenticated has RLS-scoped SELECT but no direct INSERT/UPDATE/DELETE; only service_role may write directly'
do $$
begin
  if has_table_privilege('anon', 'app.item_control_policy_versions', 'SELECT') then
    raise exception 'assertion failed: anon must not have direct SELECT on app.item_control_policy_versions';
  end if;
  if has_table_privilege('anon', 'app.lot_identities', 'SELECT') then
    raise exception 'assertion failed: anon must not have direct SELECT on app.lot_identities';
  end if;
  if has_table_privilege('anon', 'app.serial_identities', 'SELECT') then
    raise exception 'assertion failed: anon must not have direct SELECT on app.serial_identities';
  end if;
  if has_function_privilege('anon', 'app.register_lot_identity(uuid, text, date, date, text, uuid, uuid, uuid, text)', 'EXECUTE') then
    raise exception 'assertion failed: anon must not have EXECUTE on app.register_lot_identity';
  end if;
  if has_function_privilege('anon', 'app.register_serial_identity(uuid, text, text, date, date, text, uuid, text, uuid, text)', 'EXECUTE') then
    raise exception 'assertion failed: anon must not have EXECUTE on app.register_serial_identity';
  end if;
  if has_function_privilege('anon', 'app.publish_item_control_policy_version(uuid, integer, uuid, uuid, text)', 'EXECUTE') then
    raise exception 'assertion failed: anon must not have EXECUTE on app.publish_item_control_policy_version';
  end if;

  if not has_table_privilege('authenticated', 'app.lot_identities', 'SELECT') then
    raise exception 'assertion failed: authenticated must have RLS-scoped SELECT on app.lot_identities';
  end if;
  if has_table_privilege('authenticated', 'app.lot_identities', 'INSERT') then
    raise exception 'assertion failed: authenticated must not have direct INSERT on app.lot_identities -- mutation must go through the SECURITY DEFINER RPCs only';
  end if;
  if has_table_privilege('authenticated', 'app.serial_identities', 'UPDATE') then
    raise exception 'assertion failed: authenticated must not have direct UPDATE on app.serial_identities';
  end if;
  if has_table_privilege('authenticated', 'app.item_control_policy_versions', 'DELETE') then
    raise exception 'assertion failed: authenticated must not have direct DELETE on app.item_control_policy_versions';
  end if;

  if not has_table_privilege('service_role', 'app.lot_identities', 'INSERT') then
    raise exception 'assertion failed: service_role must retain direct table access to app.lot_identities';
  end if;
  if not has_table_privilege('service_role', 'app.serial_identities', 'INSERT') then
    raise exception 'assertion failed: service_role must retain direct table access to app.serial_identities';
  end if;
  if not has_table_privilege('service_role', 'app.item_control_policy_versions', 'INSERT') then
    raise exception 'assertion failed: service_role must retain direct table access to app.item_control_policy_versions';
  end if;
end $$;

\echo '>> app.get_item_control_policy honors effective_from (Prompt 235 section 25 "policy version matches owner/item/effective time"): a policy published with a FUTURE effective_from is not yet in effect (policy_version_not_found) even though it is genuinely published'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'lbs1');
  v_plain_id uuid := (select id from app.item_masters where tenant_id = v_tenant1 and code = 'SKU-LBS-PLAIN');
  v_draft app.item_control_policy_versions;
  v_published app.item_control_policy_versions;
begin
  v_draft := app.create_item_control_policy_version_draft(v_plain_id, 'fifo', true, null, now() + interval '30 days', '00000000-0000-0000-0000-000000160102', 'rep');
  v_published := app.publish_item_control_policy_version(v_draft.id, v_draft.record_version, null, '00000000-0000-0000-0000-000000160104', 'supervisor');
  if v_published.status <> 'published' then
    raise exception 'assertion failed: expected the future-effective draft to publish successfully -- publishing is always allowed, only APPLYING it early is not';
  end if;

  begin
    perform app.get_item_control_policy(v_plain_id, '00000000-0000-0000-0000-000000160102');
    raise exception 'assertion failed: expected policy_version_not_found -- the only published policy''s effective_from is still 30 days in the future, so it is not yet in effect';
  exception
    when others then
      if sqlerrm not like 'policy_version_not_found%' then raise; end if;
  end;
end $$;

\echo '>> owner-account read scoping (Prompt 235 section 26/27, design note 6b): a second owner account (Lbs Customer Beta) under tenant1, its own item master, lot, serial and control policy, plus a customer_user-layer actor granted OPS:View and scoped to Owner Alpha only (principal_memberships.customer_account_ref = Owner Alpha''s own app.accounts.id in text form). Setup only in this block -- assertions follow in the next.'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'lbs1');
  v_company uuid := (select id from app.org_units where tenant_id = v_tenant1 and code = 'LBS1-CO');
  v_viewer_role uuid := (select id from app.roles where tenant_id = v_tenant1 and name = 'Lbs Viewer Role');
  v_account_alpha uuid := (select id from app.accounts where tenant_id = v_tenant1 and legal_name = 'Lbs Customer Alpha');
  v_warehouse_id uuid := (select id from app.warehouses where tenant_id = v_tenant1 and code = 'WH-LBS-1');
  v_rack_a_id uuid := (select id from app.warehouse_locations where tenant_id = v_tenant1 and code = 'RACK-LBS-A');
  v_lead app.leads;
  v_prospect app.prospects;
  v_contact app.contacts;
  v_opportunity app.opportunities;
  v_request app.costing_requests;
  v_rate app.vendor_rate_versions;
  v_selection app.rate_selections;
  v_calc_id uuid;
  v_quote app.quotations;
  v_send record;
  v_account_beta app.accounts;
  v_beta_item_id uuid;
  v_beta_draft app.item_control_policy_versions;
  v_beta_lot app.lot_identities;
  v_beta_serial app.serial_identities;
begin
  insert into auth.users (id, email) values
    ('00000000-0000-0000-0000-000000160108', 'customer-alpha@lbs1.test');

  -- The customer_user-layer actor is invited with a NULL org_unit_id (app.invite_user
  -- allows this, mirroring PLT-114's own "outsider" fixture) -- app.assign_role requires
  -- a real active app.users row to assign OPS:View at all, but this actor deliberately
  -- gets no org_unit assignment, so the ONLY path by which they can ever pass
  -- app.can_access_record's row filter is the real customer_account_ref match (design
  -- note 6b), never incidental org-unit sharing.
  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000160108', 'customer-alpha@lbs1.test', 'Customer Alpha Portal', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'customer-alpha@lbs1.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000160108', 'customer_user', v_tenant1, v_account_alpha::text, 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_viewer_role and status = 'published'), '00000000-0000-0000-0000-000000160108', '00000000-0000-0000-0000-000000160101', 'tester');

  -- A second owner account (Owner Beta) under the SAME tenant, via the identical
  -- CRM->quote->account pipeline this file''s own first setup block already used for
  -- Owner Alpha -- reusing tenant1''s already-published margin rule (COM-150''s own
  -- one-published-rule-per-TENANT shape, not per-owner).
  perform app.capture_lead(v_tenant1, 'manual', null, 'Lbs Customer Beta', 'Bob Lbs', 'bob@lbs235b.test', '0822',
    '00000000-0000-0000-0000-000000160102', v_company, '00000000-0000-0000-0000-000000160102', 'tester');
  select * into v_lead from app.leads where email = 'bob@lbs235b.test';
  perform app.qualify_lead(v_lead.id, v_lead.record_version, '00000000-0000-0000-0000-000000160102', 'tester');
  select * into v_lead from app.leads where id = v_lead.id;
  perform app.convert_lead_to_prospect(v_lead.id, 'Lbs Customer Beta', 'LBS235B', '11.111.111.16-222.000',
    jsonb_build_object('line1', 'Jl. Lbs Beta 12', 'city', 'Jakarta', 'country', 'ID'),
    '00000000-0000-0000-0000-000000160102', 'tester');
  select * into v_prospect from app.prospects where lead_id = v_lead.id;
  select * into v_contact from app.create_contact(v_tenant1, 'Bob Lbs Ops', 'Ops Lead', 'bob@lbs235b.test', '0822', '00000000-0000-0000-0000-000000160102', v_company, '00000000-0000-0000-0000-000000160102', 'tester');
  perform app.link_contact_to_record(v_contact.id, 'prospect', v_prospect.id, 'primary', true, '00000000-0000-0000-0000-000000160102', 'tester');
  select * into v_opportunity from app.create_opportunity(
    v_tenant1, v_prospect.id, 'LBS235B Beta lane',
    jsonb_build_object('service_type', 'land_freight', 'cargo_description', 'General cargo', 'origin', 'Jakarta', 'destination', 'Bandung', 'target_ready_date', '2026-08-01'),
    '00000000-0000-0000-0000-000000160102', v_company, '00000000-0000-0000-0000-000000160102', 'tester'
  );
  select * into v_request from app.request_costing(v_opportunity.id, '[]'::jsonb, null, '00000000-0000-0000-0000-000000160102', 'tester');
  select * into v_rate from app.create_rate_version(
    v_tenant1, 'VENDOR-LBS235-B', 'Contoso Lbs235B Line', 'land_freight', 'FTL', 'Jakarta', 'Bandung', '20ft',
    null, null, null, null, 'IDR', 4000000, null, '[]'::jsonb, now(), null, null, '00000000-0000-0000-0000-000000160101', 'tester'
  );
  perform app.approve_rate_version(v_rate.id, v_rate.record_version, '00000000-0000-0000-0000-000000160101', 'tester');
  select * into v_selection from app.select_vendor_rate(v_request.id, v_rate.id, false, null, null, null, '00000000-0000-0000-0000-000000160102', 'tester');
  perform app.calculate_margin(v_selection.id, 4800000, 'IDR', 0, '00000000-0000-0000-0000-000000160102', 'tester');
  select id into v_calc_id from app.margin_calculations where rate_selection_id = v_selection.id and is_current;
  select * into v_quote from app.create_quotation_draft(v_tenant1, v_opportunity.id, 'IDR', now() + interval '14 days', v_contact.id, null, null, '00000000-0000-0000-0000-000000160102', 'tester');
  perform app.add_quotation_line(v_quote.id, v_quote.record_version, 'service', 'LBS235B Beta lane', v_calc_id, 1, 4800000, 0, 0, '00000000-0000-0000-0000-000000160102', 'tester');
  select * into v_quote from app.quotations where id = v_quote.id;
  perform app.submit_quotation(v_quote.id, v_quote.record_version, '00000000-0000-0000-0000-000000160102', 'tester');
  select * into v_send from app.send_quotation_for_acceptance(v_quote.id, null, 'email', '00000000-0000-0000-0000-000000160102', 'tester');
  perform app.record_quotation_customer_decision(v_send.raw_token, 'accepted', 'Bob Lbs Ops', null, null, null, null, null);
  select * into v_quote from app.quotations where id = v_quote.id;
  select * into v_account_beta from app.convert_quotation_to_account(v_quote.id, null, null, '00000000-0000-0000-0000-000000160102', 'rep');

  perform app.create_item_master(v_tenant1, v_account_beta.id, 'SKU-LBS-BETA', 'Lbs Beta Widget', null, 'PCS', true, true, true, '00000000-0000-0000-0000-000000160102', 'rep');
  v_beta_item_id := (select id from app.item_masters where tenant_id = v_tenant1 and code = 'SKU-LBS-BETA');

  v_beta_draft := app.create_item_control_policy_version_draft(v_beta_item_id, 'fifo', false, null, null, '00000000-0000-0000-0000-000000160102', 'rep');
  perform app.publish_item_control_policy_version(v_beta_draft.id, v_beta_draft.record_version, null, '00000000-0000-0000-0000-000000160104', 'supervisor');

  v_beta_lot := app.register_lot_identity(v_beta_item_id, 'LOT-BETA-1', current_date - 5, current_date + 200, 'receipt', null, null, '00000000-0000-0000-0000-000000160102', 'rep');
  v_beta_serial := app.register_serial_identity(v_beta_item_id, 'SN-BETA-1', null, null, null, 'receipt', null, 'idem-sn-beta-1', '00000000-0000-0000-0000-000000160102', 'rep');

  perform app.post_inventory_movement(
    v_tenant1, v_warehouse_id, 'opening_balance', 'opening_balance', null, 'idem-cand-open-beta', 'owner-scope fixture',
    jsonb_build_array(jsonb_build_object('owner_account_id', v_account_beta.id, 'item_master_id', v_beta_item_id, 'location_id', v_rack_a_id, 'uom_code', 'PCS', 'signed_quantity', 5, 'lot_number', 'LOT-BETA-1', 'status', 'on_hand')),
    '00000000-0000-0000-0000-000000160102', 'rep'
  );
  perform app.post_inventory_movement(
    v_tenant1, v_warehouse_id, 'opening_balance', 'opening_balance', null, 'idem-cand-open-beta-sn', 'owner-scope fixture',
    jsonb_build_array(jsonb_build_object('owner_account_id', v_account_beta.id, 'item_master_id', v_beta_item_id, 'location_id', v_rack_a_id, 'uom_code', 'PCS', 'signed_quantity', 1, 'serial_number', 'SN-BETA-1', 'status', 'on_hand')),
    '00000000-0000-0000-0000-000000160102', 'rep'
  );
end $$;

\echo '>> owner-account read scoping assertions: the Owner-Alpha-scoped customer_user actor CAN read Owner Alpha''s own policy/lot/serial/trace data through every one of the six owner-scoped read RPCs plus both trace RPCs, and CANNOT read Owner Beta''s -- either a hard insufficient_authority rejection (single-row reads) or a silent zero-row result (list/trace reads), never Beta''s real data'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'lbs1');
  v_customer_alpha uuid := '00000000-0000-0000-0000-000000160108';
  v_exp_id uuid := (select id from app.item_masters where tenant_id = v_tenant1 and code = 'SKU-LBS-EXP');
  v_beta_item_id uuid := (select id from app.item_masters where tenant_id = v_tenant1 and code = 'SKU-LBS-BETA');
  v_alpha_policy_id uuid := (select id from app.item_control_policy_versions where item_master_id = v_exp_id and status = 'published');
  v_beta_policy_id uuid := (select id from app.item_control_policy_versions where item_master_id = v_beta_item_id and status = 'published');
  v_alpha_lot_id uuid := (select id from app.lot_identities where tenant_id = v_tenant1 and item_master_id = v_exp_id and lot_number = 'LOT-CAND-A');
  v_beta_lot_id uuid := (select id from app.lot_identities where tenant_id = v_tenant1 and item_master_id = v_beta_item_id and lot_number = 'LOT-BETA-1');
  v_alpha_serial_id uuid := (select id from app.serial_identities where tenant_id = v_tenant1 and item_master_id = (select id from app.item_masters where tenant_id = v_tenant1 and code = 'SKU-LBS-SERIAL') and serial_number = 'SN-CAND-ACTIVE');
  v_beta_serial_id uuid := (select id from app.serial_identities where tenant_id = v_tenant1 and item_master_id = v_beta_item_id and serial_number = 'SN-BETA-1');
  v_count integer;
begin
  -- 1/6: app.get_item_control_policy -- own owner succeeds, other owner rejected.
  if (app.get_item_control_policy(v_exp_id, v_customer_alpha)).id <> v_alpha_policy_id then
    raise exception 'assertion failed: expected the Alpha-scoped customer actor to read Owner Alpha''s own published control policy';
  end if;
  begin
    perform app.get_item_control_policy(v_beta_item_id, v_customer_alpha);
    raise exception 'assertion failed: expected insufficient_authority -- the Alpha-scoped customer actor must not read Owner Beta''s control policy';
  exception
    when others then
      if sqlerrm not like 'insufficient_authority%' then raise; end if;
  end;

  -- 2/6: app.list_item_control_policy_versions -- Beta's row silently excluded.
  select count(*) into v_count from app.list_item_control_policy_versions(v_tenant1, v_customer_alpha, null, null, 200) v where v.id = v_alpha_policy_id;
  if v_count <> 1 then
    raise exception 'assertion failed: expected the Alpha-scoped customer actor''s list to include Owner Alpha''s own published policy';
  end if;
  select count(*) into v_count from app.list_item_control_policy_versions(v_tenant1, v_customer_alpha, null, null, 200) v where v.id = v_beta_policy_id;
  if v_count <> 0 then
    raise exception 'assertion failed: expected the Alpha-scoped customer actor''s list to exclude Owner Beta''s published policy, got % rows', v_count;
  end if;

  -- 3/6: app.get_lot_identity.
  if (app.get_lot_identity(v_alpha_lot_id, v_customer_alpha)).id <> v_alpha_lot_id then
    raise exception 'assertion failed: expected the Alpha-scoped customer actor to read Owner Alpha''s own lot identity';
  end if;
  begin
    perform app.get_lot_identity(v_beta_lot_id, v_customer_alpha);
    raise exception 'assertion failed: expected insufficient_authority -- the Alpha-scoped customer actor must not read Owner Beta''s lot identity';
  exception
    when others then
      if sqlerrm not like 'insufficient_authority%' then raise; end if;
  end;

  -- 4/6: app.list_lot_identities.
  select count(*) into v_count from app.list_lot_identities(v_tenant1, v_customer_alpha, null, null, null, 200) v where v.id = v_alpha_lot_id;
  if v_count <> 1 then
    raise exception 'assertion failed: expected the Alpha-scoped customer actor''s lot list to include Owner Alpha''s own lot';
  end if;
  select count(*) into v_count from app.list_lot_identities(v_tenant1, v_customer_alpha, null, null, null, 200) v where v.id = v_beta_lot_id;
  if v_count <> 0 then
    raise exception 'assertion failed: expected the Alpha-scoped customer actor''s lot list to exclude Owner Beta''s lot, got % rows', v_count;
  end if;

  -- 5/6: app.get_serial_identity.
  if (app.get_serial_identity(v_alpha_serial_id, v_customer_alpha)).id <> v_alpha_serial_id then
    raise exception 'assertion failed: expected the Alpha-scoped customer actor to read Owner Alpha''s own serial identity';
  end if;
  begin
    perform app.get_serial_identity(v_beta_serial_id, v_customer_alpha);
    raise exception 'assertion failed: expected insufficient_authority -- the Alpha-scoped customer actor must not read Owner Beta''s serial identity';
  exception
    when others then
      if sqlerrm not like 'insufficient_authority%' then raise; end if;
  end;

  -- 6/6: app.list_serial_identities.
  select count(*) into v_count from app.list_serial_identities(v_tenant1, v_customer_alpha, null, null, null, 200) v where v.id = v_alpha_serial_id;
  if v_count <> 1 then
    raise exception 'assertion failed: expected the Alpha-scoped customer actor''s serial list to include Owner Alpha''s own serial';
  end if;
  select count(*) into v_count from app.list_serial_identities(v_tenant1, v_customer_alpha, null, null, null, 200) v where v.id = v_beta_serial_id;
  if v_count <> 0 then
    raise exception 'assertion failed: expected the Alpha-scoped customer actor''s serial list to exclude Owner Beta''s serial, got % rows', v_count;
  end if;

  -- Trace RPCs: no hard reject (this migration's own pre-existing row-filtered-query
  -- shape, design note 8), but Beta's real trace rows must never come back for the
  -- Alpha-scoped actor -- a silent zero-row result, never Beta's data.
  select count(*) into v_count from app.get_lot_trace(v_alpha_lot_id, v_customer_alpha, 50);
  if v_count = 0 then
    raise exception 'assertion failed: expected the Alpha-scoped customer actor to see at least one real trace row for Owner Alpha''s own lot';
  end if;
  select count(*) into v_count from app.get_lot_trace(v_beta_lot_id, v_customer_alpha, 50);
  if v_count <> 0 then
    raise exception 'assertion failed: expected ZERO trace rows for Owner Beta''s lot when read by the Alpha-scoped customer actor, got %', v_count;
  end if;

  select count(*) into v_count from app.get_serial_trace(v_alpha_serial_id, v_customer_alpha, 50);
  if v_count = 0 then
    raise exception 'assertion failed: expected the Alpha-scoped customer actor to see at least one real trace row for Owner Alpha''s own serial';
  end if;
  select count(*) into v_count from app.get_serial_trace(v_beta_serial_id, v_customer_alpha, 50);
  if v_count <> 0 then
    raise exception 'assertion failed: expected ZERO trace rows for Owner Beta''s serial when read by the Alpha-scoped customer actor, got %', v_count;
  end if;
end $$;
