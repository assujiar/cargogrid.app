-- Real, executable test evidence for ATW-011A (CG-S10-ATW-011A, Item/SKU and UOM
-- Master) -- run via `pnpm run db:test` against a real, disposable Postgres database.

\set ON_ERROR_STOP on

\echo '>> setup: two tenants. Tenant1 (itemuom1): a company org unit, a tenant_admin, an OPS:Create/Edit/View rep, an OPS:View-only viewer, and two customer accounts (Account A, Account B -- via the full lead->prospect->contact->opportunity->costing->rate->margin->quotation->account pipeline, which was the only path to a real app.accounts row when this file was written) proving one tenant can hold the same SKU code under two different owners. Tenant2 (itemuom2): an isolated rep and its own single account, for cross-tenant leakage checks. A global Supreme Admin.'
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
begin
  insert into auth.users (id, email) values
    ('00000000-0000-0000-0000-000000080101', 'admin@itemuom1.test'),
    ('00000000-0000-0000-0000-000000080102', 'rep@itemuom1.test'),
    ('00000000-0000-0000-0000-000000080103', 'viewer@itemuom1.test'),
    ('00000000-0000-0000-0000-000000080105', 'supreme@itemuom1.test'),
    ('00000000-0000-0000-0000-000000080106', 'admin2@itemuom2.test'),
    ('00000000-0000-0000-0000-000000080107', 'rep2@itemuom2.test');

  perform app.grant_principal_membership('00000000-0000-0000-0000-000000080105', 'supreme_admin', null, null, 'tester');

  perform app.provision_tenant('itemuom1', 'ItemUOM Tenant One', 'idem-itemuom1', 'tester');
  v_tenant1 := (select id from app.tenants where slug = 'itemuom1');
  perform app.transition_tenant_status(v_tenant1, 'active', 'setup', 'tester');
  perform app.create_org_unit(v_tenant1, 'company', null, 'ITEMUOM1-CO', 'ItemUOM Tenant One Co', 'tester');
  v_company := (select id from app.org_units where tenant_id = v_tenant1 and code = 'ITEMUOM1-CO');

  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000080101', 'admin@itemuom1.test', 'ItemUOM Admin', v_company, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'admin@itemuom1.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000080101', 'tenant_admin', v_tenant1, null, 'tester');

  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000080102', 'rep@itemuom1.test', 'ItemUOM Rep', v_company, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'rep@itemuom1.test'), 'active', 'onboarded', 'tester');

  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000080103', 'viewer@itemuom1.test', 'ItemUOM Viewer', v_company, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'viewer@itemuom1.test'), 'active', 'onboarded', 'tester');

  v_rep_role := (app.create_role(v_tenant1, 'ItemUOM Rep Role', 'full commercial + ops create/edit/view', 'tester')).id;
  v_rep_draft := app.create_role_version(v_rep_role, 'tester');
  perform app.set_role_version_permissions(
    v_rep_draft.id,
    array(select id from app.permissions where (resource_module_code = 'COM' and action in ('Create', 'Edit', 'Approve', 'View', 'View cost'))
      or (resource_module_code = 'OPS' and action in ('Create', 'Edit', 'View'))),
    'tester'
  );
  perform app.publish_role_version(v_rep_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_rep_role and status = 'published'), '00000000-0000-0000-0000-000000080102', '00000000-0000-0000-0000-000000080101', 'tester');

  v_viewer_role := (app.create_role(v_tenant1, 'ItemUOM Viewer Role', 'OPS:View only', 'tester')).id;
  v_viewer_draft := app.create_role_version(v_viewer_role, 'tester');
  perform app.set_role_version_permissions(v_viewer_draft.id, array(select id from app.permissions where resource_module_code = 'OPS' and action = 'View'), 'tester');
  perform app.publish_role_version(v_viewer_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_viewer_role and status = 'published'), '00000000-0000-0000-0000-000000080103', '00000000-0000-0000-0000-000000080101', 'tester');

  -- Account A, via the full CRM pipeline. That was the ONLY path to app.accounts when this
  -- file was written; ISS-2026-274 has since added app.create_customer_account_direct (a
  -- second real creation path at the same COM:Approve authority, for tenants migrating an
  -- existing customer book at cutover with no quotation to convert). This fixture
  -- deliberately keeps using the conversion pipeline: exercising the original path is
  -- exactly what makes it a regression guard for it.
  perform app.capture_lead(v_tenant1, 'manual', null, 'Customer Alpha Co', 'Alice Alpha', 'alice@alpha011a.test', '0811',
    '00000000-0000-0000-0000-000000080102', v_company, '00000000-0000-0000-0000-000000080102', 'tester');
  select * into v_lead from app.leads where email = 'alice@alpha011a.test';
  perform app.qualify_lead(v_lead.id, v_lead.record_version, '00000000-0000-0000-0000-000000080102', 'tester');
  select * into v_lead from app.leads where id = v_lead.id;
  perform app.convert_lead_to_prospect(v_lead.id, 'Customer Alpha Co', 'ALPHA011A', '11.111.111.7-111.000',
    jsonb_build_object('line1', 'Jl. Sudirman 7', 'city', 'Jakarta', 'country', 'ID'),
    '00000000-0000-0000-0000-000000080102', 'tester');
  select * into v_prospect from app.prospects where lead_id = v_lead.id;
  select * into v_contact from app.create_contact(v_tenant1, 'Alice Alpha Ops', 'Ops Lead', 'alice@alpha011a.test', '0811', '00000000-0000-0000-0000-000000080102', v_company, '00000000-0000-0000-0000-000000080102', 'tester');
  perform app.link_contact_to_record(v_contact.id, 'prospect', v_prospect.id, 'primary', true, '00000000-0000-0000-0000-000000080102', 'tester');
  select * into v_opportunity from app.create_opportunity(
    v_tenant1, v_prospect.id, 'ItemUOM011A Alpha lane',
    jsonb_build_object('service_type', 'land_freight', 'cargo_description', 'General cargo', 'origin', 'Jakarta', 'destination', 'Surabaya', 'target_ready_date', '2026-08-01'),
    '00000000-0000-0000-0000-000000080102', v_company, '00000000-0000-0000-0000-000000080102', 'tester'
  );
  select * into v_request from app.request_costing(v_opportunity.id, '[]'::jsonb, null, '00000000-0000-0000-0000-000000080102', 'tester');
  select * into v_rate from app.create_rate_version(
    v_tenant1, 'VENDOR-ITEMUOM011A-A', 'Contoso ItemUOM011A Line', 'land_freight', 'FTL', 'Jakarta', 'Surabaya', '20ft',
    null, null, null, null, 'IDR', 5000000, null, '[]'::jsonb, now(), null, null, '00000000-0000-0000-0000-000000080101', 'tester'
  );
  perform app.approve_rate_version(v_rate.id, v_rate.record_version, '00000000-0000-0000-0000-000000080101', 'tester');
  select * into v_selection from app.select_vendor_rate(v_request.id, v_rate.id, false, null, null, null, '00000000-0000-0000-0000-000000080102', 'tester');
  v_rule := app.create_margin_rule_version(v_tenant1, 20.00, 'half_up', '00000000-0000-0000-0000-000000080102', 'tester');
  perform app.publish_margin_rule_version(v_rule.id, v_rule.record_version, null, '00000000-0000-0000-0000-000000080102', 'tester');
  perform app.calculate_margin(v_selection.id, 6000000, 'IDR', 0, '00000000-0000-0000-0000-000000080102', 'tester');
  select id into v_calc_id from app.margin_calculations where rate_selection_id = v_selection.id and is_current;
  select * into v_quote from app.create_quotation_draft(v_tenant1, v_opportunity.id, 'IDR', now() + interval '14 days', v_contact.id, null, null, '00000000-0000-0000-0000-000000080102', 'tester');
  perform app.add_quotation_line(v_quote.id, v_quote.record_version, 'service', 'ItemUOM011A Alpha lane', v_calc_id, 1, 6000000, 0, 0, '00000000-0000-0000-0000-000000080102', 'tester');
  select * into v_quote from app.quotations where id = v_quote.id;
  perform app.submit_quotation(v_quote.id, v_quote.record_version, '00000000-0000-0000-0000-000000080102', 'tester');
  select * into v_send from app.send_quotation_for_acceptance(v_quote.id, null, 'email', '00000000-0000-0000-0000-000000080102', 'tester');
  perform app.record_quotation_customer_decision(v_send.raw_token, 'accepted', 'Alice Alpha Ops', null, null, null, null, null);
  select * into v_quote from app.quotations where id = v_quote.id;
  select * into v_account from app.convert_quotation_to_account(v_quote.id, null, null, '00000000-0000-0000-0000-000000080102', 'rep');

  -- Account B, same tenant, same pipeline, different customer -- the second owner
  -- app.item_masters' own (tenant_id, owner_account_id, code) unique index needs to
  -- prove "two owners, same code" is legal (design note 2's own reason app.master_records
  -- could never support this: its unique index has no owner dimension at all).
  perform app.capture_lead(v_tenant1, 'manual', null, 'Customer Beta Co', 'Bob Beta', 'bob@beta011a.test', '0812',
    '00000000-0000-0000-0000-000000080102', v_company, '00000000-0000-0000-0000-000000080102', 'tester');
  select * into v_lead from app.leads where email = 'bob@beta011a.test';
  perform app.qualify_lead(v_lead.id, v_lead.record_version, '00000000-0000-0000-0000-000000080102', 'tester');
  select * into v_lead from app.leads where id = v_lead.id;
  perform app.convert_lead_to_prospect(v_lead.id, 'Customer Beta Co', 'BETA011A', '11.111.111.8-111.000',
    jsonb_build_object('line1', 'Jl. Thamrin 8', 'city', 'Jakarta', 'country', 'ID'),
    '00000000-0000-0000-0000-000000080102', 'tester');
  select * into v_prospect from app.prospects where lead_id = v_lead.id;
  select * into v_contact from app.create_contact(v_tenant1, 'Bob Beta Ops', 'Ops Lead', 'bob@beta011a.test', '0812', '00000000-0000-0000-0000-000000080102', v_company, '00000000-0000-0000-0000-000000080102', 'tester');
  perform app.link_contact_to_record(v_contact.id, 'prospect', v_prospect.id, 'primary', true, '00000000-0000-0000-0000-000000080102', 'tester');
  select * into v_opportunity from app.create_opportunity(
    v_tenant1, v_prospect.id, 'ItemUOM011A Beta lane',
    jsonb_build_object('service_type', 'land_freight', 'cargo_description', 'General cargo', 'origin', 'Jakarta', 'destination', 'Surabaya', 'target_ready_date', '2026-08-01'),
    '00000000-0000-0000-0000-000000080102', v_company, '00000000-0000-0000-0000-000000080102', 'tester'
  );
  select * into v_request from app.request_costing(v_opportunity.id, '[]'::jsonb, null, '00000000-0000-0000-0000-000000080102', 'tester');
  select * into v_rate from app.create_rate_version(
    v_tenant1, 'VENDOR-ITEMUOM011A-B', 'Contoso ItemUOM011A Line B', 'land_freight', 'FTL', 'Jakarta', 'Surabaya', '20ft',
    null, null, null, null, 'IDR', 5000000, null, '[]'::jsonb, now(), null, null, '00000000-0000-0000-0000-000000080101', 'tester'
  );
  perform app.approve_rate_version(v_rate.id, v_rate.record_version, '00000000-0000-0000-0000-000000080101', 'tester');
  select * into v_selection from app.select_vendor_rate(v_request.id, v_rate.id, false, null, null, null, '00000000-0000-0000-0000-000000080102', 'tester');
  perform app.calculate_margin(v_selection.id, 6000000, 'IDR', 0, '00000000-0000-0000-0000-000000080102', 'tester');
  select id into v_calc_id from app.margin_calculations where rate_selection_id = v_selection.id and is_current;
  select * into v_quote from app.create_quotation_draft(v_tenant1, v_opportunity.id, 'IDR', now() + interval '14 days', v_contact.id, null, null, '00000000-0000-0000-0000-000000080102', 'tester');
  perform app.add_quotation_line(v_quote.id, v_quote.record_version, 'service', 'ItemUOM011A Beta lane', v_calc_id, 1, 6000000, 0, 0, '00000000-0000-0000-0000-000000080102', 'tester');
  select * into v_quote from app.quotations where id = v_quote.id;
  perform app.submit_quotation(v_quote.id, v_quote.record_version, '00000000-0000-0000-0000-000000080102', 'tester');
  select * into v_send from app.send_quotation_for_acceptance(v_quote.id, null, 'email', '00000000-0000-0000-0000-000000080102', 'tester');
  perform app.record_quotation_customer_decision(v_send.raw_token, 'accepted', 'Bob Beta Ops', null, null, null, null, null);
  select * into v_quote from app.quotations where id = v_quote.id;
  perform app.convert_quotation_to_account(v_quote.id, null, null, '00000000-0000-0000-0000-000000080102', 'rep');

  -- Tenant2: fully isolated -- exists only to prove cross-tenant scope safety.
  perform app.provision_tenant('itemuom2', 'ItemUOM Tenant Two', 'idem-itemuom2', 'tester');
  v_tenant2 := (select id from app.tenants where slug = 'itemuom2');
  perform app.transition_tenant_status(v_tenant2, 'active', 'setup', 'tester');
  perform app.create_org_unit(v_tenant2, 'company', null, 'ITEMUOM2-CO', 'ItemUOM Tenant Two Co', 'tester');
  v_company2 := (select id from app.org_units where tenant_id = v_tenant2 and code = 'ITEMUOM2-CO');
  perform app.invite_user(v_tenant2, '00000000-0000-0000-0000-000000080106', 'admin2@itemuom2.test', 'Tenant2 Admin', v_company2, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'admin2@itemuom2.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000080106', 'tenant_admin', v_tenant2, null, 'tester');
  perform app.invite_user(v_tenant2, '00000000-0000-0000-0000-000000080107', 'rep2@itemuom2.test', 'Tenant2 Rep', v_company2, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'rep2@itemuom2.test'), 'active', 'onboarded', 'tester');
  v_rep2_role := (app.create_role(v_tenant2, 'Tenant2 Rep Role', 'ops create/edit/view', 'tester')).id;
  v_rep2_draft := app.create_role_version(v_rep2_role, 'tester');
  perform app.set_role_version_permissions(v_rep2_draft.id, array(select id from app.permissions where resource_module_code = 'OPS' and action in ('Create', 'Edit', 'View')), 'tester');
  perform app.publish_role_version(v_rep2_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant2, (select id from app.role_versions where role_id = v_rep2_role and status = 'published'), '00000000-0000-0000-0000-000000080107', '00000000-0000-0000-0000-000000080106', 'tester');
end $$;

\echo '>> app.uoms / app.validate_uom_code / app.convert_uom_quantity: seeded catalogue, category-scoped conversion, direct and inverse factor resolution, honest not-found'
do $$
declare
  v_result numeric;
begin
  if not app.validate_uom_code('KG') then
    raise exception 'assertion failed: expected KG to be a registered active UOM';
  end if;
  if app.validate_uom_code('NOPE') then
    raise exception 'assertion failed: expected NOPE to be rejected -- not a registered UOM code';
  end if;

  if app.convert_uom_quantity(5, 'KG', 'KG') <> 5 then
    raise exception 'assertion failed: expected same-code passthrough to return the identical quantity';
  end if;

  v_result := app.convert_uom_quantity(2, 'KG', 'G');
  if v_result <> 2000 then
    raise exception 'assertion failed: expected 2 KG -> G to equal 2000, got %', v_result;
  end if;

  v_result := app.convert_uom_quantity(2000, 'G', 'KG');
  if v_result <> 2 then
    raise exception 'assertion failed: expected 2000 G -> KG (inverse factor resolution) to equal 2, got %', v_result;
  end if;

  begin
    perform app.convert_uom_quantity(1, 'KG', 'L');
    raise exception 'assertion failed: expected uom_conversion_not_registered -- KG (weight) and L (volume) share no registered path';
  exception
    when others then
      if sqlerrm not like 'uom_conversion_not_registered%' then raise; end if;
  end;
end $$;

\echo '>> app.uom_conversions_same_category_check: a cross-category conversion row (weight -> volume) is rejected structurally, not merely left unregistered'
do $$
begin
  begin
    insert into app.uom_conversions (from_uom_code, to_uom_code, factor) values ('KG', 'L', 1);
    raise exception 'assertion failed: expected uom_conversions_same_category_check to reject a weight -> volume conversion row';
  exception
    when others then
      if sqlerrm not like '%uom_conversions_same_category_check%' then raise; end if;
  end;
end $$;

\echo '>> app.create_item_master: authority-gated (OPS:Create), owner account must be an active account of the same tenant, base UOM must be registered, idempotent replay, and the same code is legal under two different owners in the same tenant (the exact invariant app.master_records could never support)'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'itemuom1');
  v_tenant2 uuid := (select id from app.tenants where slug = 'itemuom2');
  v_account_a uuid := (select id from app.accounts where tenant_id = v_tenant1 and legal_name = 'Customer Alpha Co');
  v_account_b uuid := (select id from app.accounts where tenant_id = v_tenant1 and legal_name = 'Customer Beta Co');
  v_item_a app.item_masters;
  v_item_a_replay app.item_masters;
  v_item_b app.item_masters;
begin
  begin
    perform app.create_item_master(v_tenant1, v_account_a, 'SKU-100', 'Test Widget', null, 'PCS', false, false, false, '00000000-0000-0000-0000-000000080103', 'viewer');
    raise exception 'assertion failed: expected insufficient_authority -- viewer holds OPS:View only, not OPS:Create';
  exception
    when others then
      if sqlerrm not like 'insufficient_authority%' then raise; end if;
  end;

  begin
    perform app.create_item_master(v_tenant1, gen_random_uuid(), 'SKU-100', 'Test Widget', null, 'PCS', false, false, false, '00000000-0000-0000-0000-000000080102', 'rep');
    raise exception 'assertion failed: expected owner_account_not_found -- a random uuid is not a real app.accounts row';
  exception
    when others then
      if sqlerrm not like 'owner_account_not_found%' then raise; end if;
  end;

  begin
    perform app.create_item_master(v_tenant1, v_account_a, 'SKU-100', 'Test Widget', null, 'NOPE', false, false, false, '00000000-0000-0000-0000-000000080102', 'rep');
    raise exception 'assertion failed: expected invalid_base_uom -- NOPE is not a registered UOM code';
  exception
    when others then
      if sqlerrm not like 'invalid_base_uom%' then raise; end if;
  end;

  v_item_a := app.create_item_master(v_tenant1, v_account_a, 'SKU-100', 'Test Widget', 'A test widget', 'PCS', true, false, true, '00000000-0000-0000-0000-000000080102', 'rep');
  if v_item_a.status <> 'active' or v_item_a.base_uom_code <> 'PCS' or not v_item_a.lot_controlled or not v_item_a.expiry_controlled or v_item_a.serial_controlled then
    raise exception 'assertion failed: expected SKU-100/Account A to be created active, PCS, lot+expiry controlled, not serial controlled';
  end if;

  v_item_a_replay := app.create_item_master(v_tenant1, v_account_a, 'SKU-100', 'Test Widget', 'A test widget', 'PCS', true, false, true, '00000000-0000-0000-0000-000000080102', 'rep');
  if v_item_a_replay.id <> v_item_a.id or v_item_a_replay.record_version <> v_item_a.record_version then
    raise exception 'assertion failed: expected the same (tenant, owner, code) replay to return the identical, unchanged row';
  end if;

  -- The key structural proof (design note 2): the identical code SKU-100, same tenant,
  -- a DIFFERENT owner account -- must succeed as a second, distinct row.
  v_item_b := app.create_item_master(v_tenant1, v_account_b, 'SKU-100', 'Test Widget (Beta-owned)', null, 'KG', false, false, false, '00000000-0000-0000-0000-000000080102', 'rep');
  if v_item_b.id = v_item_a.id then
    raise exception 'assertion failed: expected SKU-100/Account B to be a distinct row from SKU-100/Account A';
  end if;
  if (select count(*) from app.item_masters where tenant_id = v_tenant1 and code = 'SKU-100') <> 2 then
    raise exception 'assertion failed: expected exactly 2 SKU-100 rows in tenant1, one per owner';
  end if;

  begin
    perform app.create_item_master(v_tenant2, v_account_a, 'SKU-200', 'Cross-tenant probe', null, 'PCS', false, false, false, '00000000-0000-0000-0000-000000080107', 'rep2');
    raise exception 'assertion failed: expected owner_account_not_found -- Account A belongs to tenant1, not tenant2';
  exception
    when others then
      if sqlerrm not like 'owner_account_not_found%' then raise; end if;
  end;
end $$;

\echo '>> app.update_item_master / app.set_item_master_status: optimistic concurrency, mutable-fields-only, reason required to deactivate, same-status no-op'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'itemuom1');
  v_account_a uuid := (select id from app.accounts where tenant_id = v_tenant1 and legal_name = 'Customer Alpha Co');
  v_item app.item_masters;
begin
  select * into v_item from app.item_masters where tenant_id = v_tenant1 and owner_account_id = v_account_a and code = 'SKU-100';

  begin
    perform app.update_item_master(v_item.id, 'Renamed', null, true, false, true, v_item.record_version + 1, '00000000-0000-0000-0000-000000080102', 'rep');
    raise exception 'assertion failed: expected stale_version';
  exception
    when others then
      if sqlerrm not like 'stale_version%' then raise; end if;
  end;

  v_item := app.update_item_master(v_item.id, 'Renamed Widget', 'updated description', true, true, true, v_item.record_version, '00000000-0000-0000-0000-000000080102', 'rep');
  if v_item.name <> 'Renamed Widget' or v_item.record_version <> 2 or v_item.base_uom_code <> 'PCS' then
    raise exception 'assertion failed: expected name/control flags to change, record_version to advance to 2, and base_uom_code (immutable, not a parameter) to stay PCS, got name=% version=% uom=%', v_item.name, v_item.record_version, v_item.base_uom_code;
  end if;

  begin
    perform app.set_item_master_status(v_item.id, 'inactive', null, v_item.record_version, '00000000-0000-0000-0000-000000080102', 'rep');
    raise exception 'assertion failed: expected invalid_reason -- a reason is required to deactivate';
  exception
    when others then
      if sqlerrm not like 'invalid_reason%' then raise; end if;
  end;

  v_item := app.set_item_master_status(v_item.id, 'inactive', 'discontinued', v_item.record_version, '00000000-0000-0000-0000-000000080102', 'rep');
  if v_item.status <> 'inactive' or v_item.record_version <> 3 then
    raise exception 'assertion failed: expected the item to deactivate and record_version to advance to 3';
  end if;

  -- Same-status transition is a silent no-op returning the current row, not an error.
  if (app.set_item_master_status(v_item.id, 'inactive', null, v_item.record_version, '00000000-0000-0000-0000-000000080102', 'rep')).record_version <> v_item.record_version then
    raise exception 'assertion failed: expected a same-status transition to be a no-op';
  end if;

  v_item := app.set_item_master_status(v_item.id, 'active', 'reinstated', v_item.record_version, '00000000-0000-0000-0000-000000080102', 'rep');
  if v_item.status <> 'active' then
    raise exception 'assertion failed: expected the item to reactivate';
  end if;
end $$;

\echo '>> app.get_item_master / app.resolve_item_master_by_code: honest not-found, RBAC-gated read'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'itemuom1');
  v_account_a uuid := (select id from app.accounts where tenant_id = v_tenant1 and legal_name = 'Customer Alpha Co');
  v_item app.item_masters;
begin
  select * into v_item from app.item_masters where tenant_id = v_tenant1 and owner_account_id = v_account_a and code = 'SKU-100';

  if (app.get_item_master(v_item.id, '00000000-0000-0000-0000-000000080103')).code <> 'SKU-100' then
    raise exception 'assertion failed: expected the OPS:View-only viewer to read SKU-100 by id';
  end if;

  if (app.resolve_item_master_by_code(v_tenant1, v_account_a, 'SKU-100', '00000000-0000-0000-0000-000000080102')).id <> v_item.id then
    raise exception 'assertion failed: expected resolve_item_master_by_code to return the identical row by (tenant, owner, code)';
  end if;

  begin
    perform app.resolve_item_master_by_code(v_tenant1, v_account_a, 'NO-SUCH-CODE', '00000000-0000-0000-0000-000000080102');
    raise exception 'assertion failed: expected item_master_not_found for an unregistered code';
  exception
    when others then
      if sqlerrm not like 'item_master_not_found%' then raise; end if;
  end;

  begin
    perform app.get_item_master(gen_random_uuid(), '00000000-0000-0000-0000-000000080102');
    raise exception 'assertion failed: expected item_master_not_found for a random id';
  exception
    when others then
      if sqlerrm not like 'item_master_not_found%' then raise; end if;
  end;
end $$;

\echo '>> app.list_item_masters: bounded by default (limit 50), owner/status/search filters, limit clamp (0 -> 1, 500 -> 200), and cross-tenant isolation'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'itemuom1');
  v_tenant2 uuid := (select id from app.tenants where slug = 'itemuom2');
  v_account_a uuid := (select id from app.accounts where tenant_id = v_tenant1 and legal_name = 'Customer Alpha Co');
  v_count integer;
begin
  select count(*) into v_count from app.list_item_masters(v_tenant1, '00000000-0000-0000-0000-000000080102', null, null, null, 50);
  if v_count <> 2 then
    raise exception 'assertion failed: expected 2 item masters tenant-wide (SKU-100 x2 owners), got %', v_count;
  end if;

  select count(*) into v_count from app.list_item_masters(v_tenant1, '00000000-0000-0000-0000-000000080102', v_account_a, null, null, 50);
  if v_count <> 1 then
    raise exception 'assertion failed: expected exactly 1 item master owned by Account A, got %', v_count;
  end if;

  select count(*) into v_count from app.list_item_masters(v_tenant1, '00000000-0000-0000-0000-000000080102', null, 'inactive', null, 50);
  if v_count <> 0 then
    raise exception 'assertion failed: expected zero inactive item masters (both are active again), got %', v_count;
  end if;

  select count(*) into v_count from app.list_item_masters(v_tenant1, '00000000-0000-0000-0000-000000080102', null, null, 'Beta-owned', 50);
  if v_count <> 1 then
    raise exception 'assertion failed: expected exactly 1 item master matching search term "Beta-owned", got %', v_count;
  end if;

  select count(*) into v_count from app.list_item_masters(v_tenant1, '00000000-0000-0000-0000-000000080102', null, null, null, 0);
  if v_count <> 1 then
    raise exception 'assertion failed: expected p_limit=0 to clamp up to 1, got %', v_count;
  end if;

  select count(*) into v_count from app.list_item_masters(v_tenant1, '00000000-0000-0000-0000-000000080102', null, null, null, 500);
  if v_count <> 2 then
    raise exception 'assertion failed: expected p_limit=500 to clamp down to 200 (still returning only the 2 real rows), got %', v_count;
  end if;

  begin
    perform app.list_item_masters(v_tenant2, '00000000-0000-0000-0000-000000080102', null, null, null, 50);
    raise exception 'assertion failed: expected insufficient_authority -- tenant1''s rep has no membership in tenant2';
  exception
    when others then
      if sqlerrm not like 'insufficient_authority%' then raise; end if;
  end;

  select count(*) into v_count from app.list_item_masters(v_tenant2, '00000000-0000-0000-0000-000000080107', null, null, null, 50);
  if v_count <> 0 then
    raise exception 'assertion failed: expected tenant2''s own rep to see zero item masters (none created there)';
  end if;
end $$;

\echo '>> schema-privilege defense in depth (ERR-2026-004): anon holds no direct table/EXECUTE access; authenticated has RLS-scoped SELECT but no direct INSERT/UPDATE/DELETE; only service_role may write directly'
do $$
begin
  if has_table_privilege('anon', 'app.item_masters', 'SELECT') then
    raise exception 'assertion failed: anon must not have direct SELECT on app.item_masters';
  end if;
  if has_table_privilege('anon', 'app.uoms', 'SELECT') then
    raise exception 'assertion failed: anon must not have direct SELECT on app.uoms';
  end if;
  if has_function_privilege('anon', 'app.create_item_master(uuid, uuid, text, text, text, text, boolean, boolean, boolean, uuid, text)', 'EXECUTE') then
    raise exception 'assertion failed: anon must not have EXECUTE on app.create_item_master';
  end if;

  if not has_table_privilege('authenticated', 'app.item_masters', 'SELECT') then
    raise exception 'assertion failed: authenticated must have RLS-scoped SELECT on app.item_masters';
  end if;
  if has_table_privilege('authenticated', 'app.item_masters', 'INSERT') then
    raise exception 'assertion failed: authenticated must not have direct INSERT on app.item_masters -- mutation must go through the SECURITY DEFINER RPCs only';
  end if;
  if not has_table_privilege('authenticated', 'app.uoms', 'SELECT') then
    raise exception 'assertion failed: authenticated must have SELECT on app.uoms (global reference catalogue)';
  end if;
  if has_table_privilege('authenticated', 'app.uoms', 'INSERT') then
    raise exception 'assertion failed: authenticated must not have direct INSERT on app.uoms';
  end if;

  if not has_table_privilege('service_role', 'app.item_masters', 'INSERT') then
    raise exception 'assertion failed: service_role must retain direct table access to app.item_masters';
  end if;
  if not has_table_privilege('service_role', 'app.uoms', 'INSERT') then
    raise exception 'assertion failed: service_role must retain direct table access to app.uoms';
  end if;
end $$;
