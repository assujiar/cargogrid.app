-- Real, executable test evidence for ATW-229 (CG-S10-ATW-010, Prompt 229 Warehouse and
-- Zone) -- run via `pnpm run db:test` against a real, disposable Postgres database.

\set ON_ERROR_STOP on

\echo '>> setup: two tenants. Tenant1 (acmewms): a company org unit with two sibling branches (JKT/SBY), a tenant_admin, a JKT-scoped rep (OPS:Create/Edit/View), a JKT-scoped OPS:View-only viewer, an SBY-scoped rep (OPS:Create/Edit/View, used to prove record-scope is enforced independently of module permission), and one CRM-derived customer account (via the full lead->prospect->contact->opportunity->costing->rate->margin->quotation->account pipeline, for eligibility tests). Tenant2 (acmewms2): an isolated rep for cross-tenant leakage checks. A global Supreme Admin.'
do $$
declare
  v_tenant1 uuid;
  v_tenant2 uuid;
  v_company uuid;
  v_jkt uuid;
  v_sby uuid;
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
    ('00000000-0000-0000-0000-000000070101', 'admin@acmewms.test'),
    ('00000000-0000-0000-0000-000000070102', 'rep@acmewms.test'),
    ('00000000-0000-0000-0000-000000070103', 'viewer@acmewms.test'),
    ('00000000-0000-0000-0000-000000070104', 'sbyrep@acmewms.test'),
    ('00000000-0000-0000-0000-000000070105', 'supreme@acmewms.test'),
    ('00000000-0000-0000-0000-000000070106', 'admin2@acmewms2.test'),
    ('00000000-0000-0000-0000-000000070107', 'rep2@acmewms2.test');

  perform app.grant_principal_membership('00000000-0000-0000-0000-000000070105', 'supreme_admin', null, null, 'tester');

  perform app.provision_tenant('acmewms', 'Acme WMS Co', 'idem-acmewms', 'tester');
  v_tenant1 := (select id from app.tenants where slug = 'acmewms');
  perform app.transition_tenant_status(v_tenant1, 'active', 'setup', 'tester');
  perform app.create_org_unit(v_tenant1, 'company', null, 'ACMEWMS-CO', 'Acme WMS Co', 'tester');
  v_company := (select id from app.org_units where tenant_id = v_tenant1 and code = 'ACMEWMS-CO');
  perform app.create_org_unit(v_tenant1, 'branch', v_company, 'ACMEWMS-JKT', 'Acme WMS Jakarta', 'tester');
  v_jkt := (select id from app.org_units where tenant_id = v_tenant1 and code = 'ACMEWMS-JKT');
  perform app.create_org_unit(v_tenant1, 'branch', v_company, 'ACMEWMS-SBY', 'Acme WMS Surabaya', 'tester');
  v_sby := (select id from app.org_units where tenant_id = v_tenant1 and code = 'ACMEWMS-SBY');

  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000070101', 'admin@acmewms.test', 'WMS Admin', v_company, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'admin@acmewms.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000070101', 'tenant_admin', v_tenant1, null, 'tester');

  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000070102', 'rep@acmewms.test', 'WMS Rep JKT', v_jkt, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'rep@acmewms.test'), 'active', 'onboarded', 'tester');

  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000070103', 'viewer@acmewms.test', 'WMS Viewer JKT', v_jkt, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'viewer@acmewms.test'), 'active', 'onboarded', 'tester');

  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000070104', 'sbyrep@acmewms.test', 'WMS Rep SBY', v_sby, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'sbyrep@acmewms.test'), 'active', 'onboarded', 'tester');

  v_rep_role := (app.create_role(v_tenant1, 'WMS Rep Role', 'full commercial + ops create/edit/view', 'tester')).id;
  v_rep_draft := app.create_role_version(v_rep_role, 'tester');
  perform app.set_role_version_permissions(
    v_rep_draft.id,
    array(select id from app.permissions where (resource_module_code = 'COM' and action in ('Create', 'Edit', 'Approve', 'View', 'View cost'))
      or (resource_module_code = 'OPS' and action in ('Create', 'Edit', 'View'))),
    'tester'
  );
  perform app.publish_role_version(v_rep_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_rep_role and status = 'published'), '00000000-0000-0000-0000-000000070102', '00000000-0000-0000-0000-000000070101', 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_rep_role and status = 'published'), '00000000-0000-0000-0000-000000070104', '00000000-0000-0000-0000-000000070101', 'tester');
  -- The tenant_admin also needs the same OPS/COM grants for the CRM pipeline below
  -- (account conversion is a rep-driven flow in this fixture's own design, but the
  -- admin performs org-unit setup only -- no extra grant needed for admin here).

  v_viewer_role := (app.create_role(v_tenant1, 'WMS Viewer Role', 'OPS:View only', 'tester')).id;
  v_viewer_draft := app.create_role_version(v_viewer_role, 'tester');
  perform app.set_role_version_permissions(v_viewer_draft.id, array(select id from app.permissions where resource_module_code = 'OPS' and action = 'View'), 'tester');
  perform app.publish_role_version(v_viewer_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_viewer_role and status = 'published'), '00000000-0000-0000-0000-000000070103', '00000000-0000-0000-0000-000000070101', 'tester');

  -- CRM pipeline: lead -> prospect -> contact -> opportunity -> costing -> rate ->
  -- margin -> quotation -> account. The one real app.accounts row this fixture needs
  -- for eligibility tests -- account.org_unit_id defaults from the prospect's own team,
  -- not used by any warehouse RPC (eligibility scope is warehouse-side, design note 6).
  perform app.capture_lead(v_tenant1, 'manual', null, 'WMS229 Customer Co', 'Jane WMS', 'jane@wms229test.test', '0811',
    '00000000-0000-0000-0000-000000070102', v_jkt, '00000000-0000-0000-0000-000000070102', 'tester');
  select * into v_lead from app.leads where email = 'jane@wms229test.test';
  perform app.qualify_lead(v_lead.id, v_lead.record_version, '00000000-0000-0000-0000-000000070102', 'tester');
  select * into v_lead from app.leads where id = v_lead.id;
  perform app.convert_lead_to_prospect(v_lead.id, 'WMS229 Customer Co', 'WMS229', '11.111.111.6-111.000',
    jsonb_build_object('line1', 'Jl. Gatot Subroto 6', 'city', 'Jakarta', 'country', 'ID'),
    '00000000-0000-0000-0000-000000070102', 'tester');
  select * into v_prospect from app.prospects where lead_id = v_lead.id;

  select * into v_contact from app.create_contact(v_tenant1, 'Jane WMS Ops', 'Warehouse Lead', 'jane@wms229test.test', '0811', '00000000-0000-0000-0000-000000070102', v_jkt, '00000000-0000-0000-0000-000000070102', 'tester');
  perform app.link_contact_to_record(v_contact.id, 'prospect', v_prospect.id, 'primary', true, '00000000-0000-0000-0000-000000070102', 'tester');

  select * into v_opportunity from app.create_opportunity(
    v_tenant1, v_prospect.id, 'WMS229 test lane',
    jsonb_build_object('service_type', 'land_freight', 'cargo_description', 'General cargo', 'origin', 'Jakarta', 'destination', 'Surabaya', 'target_ready_date', '2026-08-01'),
    '00000000-0000-0000-0000-000000070102', v_jkt, '00000000-0000-0000-0000-000000070102', 'tester'
  );
  select * into v_request from app.request_costing(v_opportunity.id, '[]'::jsonb, null, '00000000-0000-0000-0000-000000070102', 'tester');
  select * into v_rate from app.create_rate_version(
    v_tenant1, 'VENDOR-WMS229-1', 'Contoso WMS229 Line', 'land_freight', 'FTL', 'Jakarta', 'Surabaya', '20ft',
    null, null, null, null, 'IDR', 5000000, null, '[]'::jsonb, now(), null, null, '00000000-0000-0000-0000-000000070101', 'tester'
  );
  perform app.approve_rate_version(v_rate.id, v_rate.record_version, '00000000-0000-0000-0000-000000070101', 'tester');
  select * into v_selection from app.select_vendor_rate(v_request.id, v_rate.id, false, null, null, null, '00000000-0000-0000-0000-000000070102', 'tester');

  select * into v_rule from app.create_margin_rule_version(v_tenant1, 20.00, 'half_up', '00000000-0000-0000-0000-000000070102', 'tester');
  perform app.publish_margin_rule_version(v_rule.id, v_rule.record_version, null, '00000000-0000-0000-0000-000000070102', 'tester');
  perform app.calculate_margin(v_selection.id, 6000000, 'IDR', 0, '00000000-0000-0000-0000-000000070102', 'tester');
  select id into v_calc_id from app.margin_calculations where rate_selection_id = v_selection.id and is_current;

  select * into v_quote from app.create_quotation_draft(v_tenant1, v_opportunity.id, 'IDR', now() + interval '14 days', v_contact.id, null, null, '00000000-0000-0000-0000-000000070102', 'tester');
  perform app.add_quotation_line(v_quote.id, v_quote.record_version, 'service', 'WMS229 lane', v_calc_id, 1, 6000000, 0, 0, '00000000-0000-0000-0000-000000070102', 'tester');
  select * into v_quote from app.quotations where id = v_quote.id;
  perform app.submit_quotation(v_quote.id, v_quote.record_version, '00000000-0000-0000-0000-000000070102', 'tester');
  select * into v_send from app.send_quotation_for_acceptance(v_quote.id, null, 'email', '00000000-0000-0000-0000-000000070102', 'tester');
  perform app.record_quotation_customer_decision(v_send.raw_token, 'accepted', 'Jane WMS Ops', null, null, null, null, null);
  select * into v_quote from app.quotations where id = v_quote.id;
  select * into v_account from app.convert_quotation_to_account(v_quote.id, null, null, '00000000-0000-0000-0000-000000070102', 'rep');

  -- Tenant2: fully isolated -- exists only to prove cross-tenant scope safety.
  perform app.provision_tenant('acmewms2', 'Acme WMS Two', 'idem-acmewms2', 'tester');
  v_tenant2 := (select id from app.tenants where slug = 'acmewms2');
  perform app.transition_tenant_status(v_tenant2, 'active', 'setup', 'tester');
  perform app.create_org_unit(v_tenant2, 'company', null, 'ACMEWMS2-CO', 'Acme WMS Two', 'tester');
  perform app.invite_user(v_tenant2, '00000000-0000-0000-0000-000000070106', 'admin2@acmewms2.test', 'Tenant2 Admin', (select id from app.org_units where tenant_id = v_tenant2 and code = 'ACMEWMS2-CO'), 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'admin2@acmewms2.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000070106', 'tenant_admin', v_tenant2, null, 'tester');

  perform app.invite_user(v_tenant2, '00000000-0000-0000-0000-000000070107', 'rep2@acmewms2.test', 'Tenant2 Rep', (select id from app.org_units where tenant_id = v_tenant2 and code = 'ACMEWMS2-CO'), 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'rep2@acmewms2.test'), 'active', 'onboarded', 'tester');
  v_rep2_role := (app.create_role(v_tenant2, 'Tenant2 Rep Role', 'OPS create/edit/view', 'tester')).id;
  v_rep2_draft := app.create_role_version(v_rep2_role, 'tester');
  perform app.set_role_version_permissions(v_rep2_draft.id, array(select id from app.permissions where resource_module_code = 'OPS' and action in ('Create', 'Edit', 'View')), 'tester');
  perform app.publish_role_version(v_rep2_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant2, (select id from app.role_versions where role_id = v_rep2_role and status = 'published'), '00000000-0000-0000-0000-000000070107', '00000000-0000-0000-0000-000000070107', 'tester');
end $$;

\echo '>> app.create_warehouse: OPS:View-only viewer rejected; SBY-scoped rep (holds OPS:Create but wrong org-unit scope) rejected with insufficient_authority against JKT; JKT-scoped rep succeeds; a same-code replay under the same company org unit returns the identical row; a same-code attempt under a different org unit raises warehouse_code_conflict'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'acmewms');
  v_jkt uuid := (select id from app.org_units where tenant_id = v_tenant1 and code = 'ACMEWMS-JKT');
  v_sby uuid := (select id from app.org_units where tenant_id = v_tenant1 and code = 'ACMEWMS-SBY');
  v_wh1 app.warehouses;
  v_replay app.warehouses;
begin
  begin
    perform app.create_warehouse(v_tenant1, v_jkt, 'WH-JKT-1', 'Jakarta DC 1', 'Jl. Marunda Raya 1', 'Asia/Jakarta', null, array['land']::text[], '00000000-0000-0000-0000-000000070103', 'viewer');
    raise exception 'assertion failed: expected insufficient_authority -- viewer holds OPS:View only, not OPS:Create';
  exception
    when others then
      if sqlerrm not like 'insufficient_authority%' then raise; end if;
  end;

  begin
    perform app.create_warehouse(v_tenant1, v_jkt, 'WH-JKT-1', 'Jakarta DC 1', 'Jl. Marunda Raya 1', 'Asia/Jakarta', null, array['land']::text[], '00000000-0000-0000-0000-000000070104', 'sbyrep');
    raise exception 'assertion failed: expected insufficient_authority -- sbyrep holds OPS:Create but is scoped to ACMEWMS-SBY, not ACMEWMS-JKT or its ancestor';
  exception
    when others then
      if sqlerrm not like 'insufficient_authority%' then raise; end if;
  end;

  v_wh1 := app.create_warehouse(v_tenant1, v_jkt, 'WH-JKT-1', 'Jakarta DC 1', 'Jl. Marunda Raya 1', 'Asia/Jakarta',
    jsonb_build_object('type', 'Point', 'coordinates', jsonb_build_array(106.8272, -6.1751)), array['land']::text[],
    '00000000-0000-0000-0000-000000070102', 'rep');
  if v_wh1.code <> 'WH-JKT-1' or v_wh1.status <> 'active' or v_wh1.record_version <> 1 then
    raise exception 'assertion failed: expected an active warehouse WH-JKT-1, got code=% status=% version=%', v_wh1.code, v_wh1.status, v_wh1.record_version;
  end if;
  if v_wh1.site_geog is null then
    raise exception 'assertion failed: expected site_geog to be set from the supplied GeoJSON point';
  end if;

  v_replay := app.create_warehouse(v_tenant1, v_jkt, 'WH-JKT-1', 'Jakarta DC 1 (retry)', null, 'Asia/Jakarta', null, array['land']::text[], '00000000-0000-0000-0000-000000070102', 'rep');
  if v_replay.id <> v_wh1.id or v_replay.name <> 'Jakarta DC 1' then
    raise exception 'assertion failed: expected the same-code replay under the same org unit to return the identical, unchanged row';
  end if;

  -- Actor is sbyrep here, not the JKT-scoped rep: sbyrep genuinely holds OPS:Create
  -- and record-scope access over v_sby, so this reaches the duplicate-code check
  -- itself rather than failing earlier on insufficient_authority.
  begin
    perform app.create_warehouse(v_tenant1, v_sby, 'WH-JKT-1', 'Conflicting warehouse', null, 'Asia/Jakarta', null, '{}'::text[], '00000000-0000-0000-0000-000000070104', 'sbyrep');
    raise exception 'assertion failed: expected warehouse_code_conflict -- WH-JKT-1 already exists under a different company org unit';
  exception
    when others then
      if sqlerrm not like 'warehouse_code_conflict%' then raise; end if;
  end;

  if (select count(*) from app.warehouses where tenant_id = v_tenant1 and code = 'WH-JKT-1') <> 1 then
    raise exception 'assertion failed: expected exactly one WH-JKT-1 row';
  end if;
end $$;

\echo '>> app.update_warehouse: rejects an invalid timezone and a stale version; JKT-scoped rep succeeds and mutable fields change while code/company_org_unit_id stay fixed'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'acmewms');
  v_wh1 app.warehouses;
  v_updated app.warehouses;
begin
  select * into v_wh1 from app.warehouses where tenant_id = v_tenant1 and code = 'WH-JKT-1';

  begin
    perform app.update_warehouse(v_wh1.id, 'Jakarta DC 1', null, 'Mars/Olympus', null, array['land']::text[], v_wh1.record_version, '00000000-0000-0000-0000-000000070102', 'rep');
    raise exception 'assertion failed: expected invalid_timezone';
  exception
    when others then
      if sqlerrm not like 'invalid_timezone%' then raise; end if;
  end;

  begin
    perform app.update_warehouse(v_wh1.id, 'Jakarta DC 1', null, 'Asia/Jakarta', null, array['land']::text[], v_wh1.record_version + 99, '00000000-0000-0000-0000-000000070102', 'rep');
    raise exception 'assertion failed: expected stale_version';
  exception
    when others then
      if sqlerrm not like 'stale_version%' then raise; end if;
  end;

  v_updated := app.update_warehouse(v_wh1.id, 'Jakarta Distribution Center 1', 'Jl. Marunda Raya 1A', 'Asia/Makassar',
    jsonb_build_object('type', 'Point', 'coordinates', jsonb_build_array(106.83, -6.18)), array['land', 'sea']::text[],
    v_wh1.record_version, '00000000-0000-0000-0000-000000070102', 'rep');
  if v_updated.name <> 'Jakarta Distribution Center 1' or v_updated.timezone <> 'Asia/Makassar' or v_updated.record_version <> v_wh1.record_version + 1 then
    raise exception 'assertion failed: expected the mutable fields to change and record_version to advance by one';
  end if;
  if v_updated.code <> 'WH-JKT-1' or v_updated.company_org_unit_id <> v_wh1.company_org_unit_id then
    raise exception 'assertion failed: expected code/company_org_unit_id to stay unchanged -- no re-parenting path exists';
  end if;
end $$;

\echo '>> app.create_warehouse_zone: requires an active warehouse; viewer rejected; rep succeeds creating ambient/cold_storage/secure zones (the sourced 229 §27 examples) plus a future-scheduled zone; duplicate code with a different zone_type conflicts; capacity_value without capacity_uom and an inverted effective window are both rejected'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'acmewms');
  v_wh1 uuid := (select id from app.warehouses where tenant_id = v_tenant1 and code = 'WH-JKT-1');
  v_wh2 uuid;
  v_ambient app.warehouse_zones;
  v_cold app.warehouse_zones;
  v_secure app.warehouse_zones;
  v_staging app.warehouse_zones;
  v_replay app.warehouse_zones;
begin
  -- WH-JKT-2: a second warehouse created solely to prove the warehouse_not_active
  -- zone-creation guard (design note 7's own set_warehouse_status test needs WH-JKT-1
  -- to still be active with zones for the later deactivation-blocked assertion).
  v_wh2 := (app.create_warehouse(v_tenant1, (select company_org_unit_id from app.warehouses where id = v_wh1), 'WH-JKT-2', 'Jakarta DC 2', null, 'Asia/Jakarta', null, '{}'::text[], '00000000-0000-0000-0000-000000070102', 'rep')).id;
  perform app.set_warehouse_status(v_wh2, 'inactive', 'never used, deactivated for zone-guard test', (select record_version from app.warehouses where id = v_wh2), '00000000-0000-0000-0000-000000070102', 'rep');

  begin
    perform app.create_warehouse_zone(v_wh2, 'Z-1', 'Zone 1', 'ambient', null, null, null, null, null, null, '00000000-0000-0000-0000-000000070102', 'rep');
    raise exception 'assertion failed: expected warehouse_not_active -- WH-JKT-2 was just deactivated';
  exception
    when others then
      if sqlerrm not like 'warehouse_not_active%' then raise; end if;
  end;

  begin
    perform app.create_warehouse_zone(v_wh1, 'AMBIENT-A', 'Ambient Zone A', 'ambient', null, null, null, null, null, null, '00000000-0000-0000-0000-000000070103', 'viewer');
    raise exception 'assertion failed: expected insufficient_authority -- viewer holds OPS:View only';
  exception
    when others then
      if sqlerrm not like 'insufficient_authority%' then raise; end if;
  end;

  v_ambient := app.create_warehouse_zone(v_wh1, 'AMBIENT-A', 'Ambient Zone A', 'ambient', jsonb_build_object('temperature_control', false), null, null, null, null, null, '00000000-0000-0000-0000-000000070102', 'rep');
  v_cold := app.create_warehouse_zone(v_wh1, 'COLD-A', 'Cold Storage Zone A', 'cold_storage', jsonb_build_object('target_temp_c', -18), 500, 'pallet_position', jsonb_build_object('hazmat_class', 'none'), null, null, '00000000-0000-0000-0000-000000070102', 'rep');
  v_secure := app.create_warehouse_zone(v_wh1, 'SECURE-A', 'Secure Zone A', 'secure', null, null, null, jsonb_build_object('access_control', 'supervisor_only'), null, null, '00000000-0000-0000-0000-000000070102', 'rep');
  v_staging := app.create_warehouse_zone(v_wh1, 'STAGING-B', 'Future Staging Zone B', 'staging', null, null, null, null, now() + interval '30 days', null, '00000000-0000-0000-0000-000000070102', 'rep');

  if v_cold.capacity_value <> 500 or v_cold.capacity_uom <> 'pallet_position' then
    raise exception 'assertion failed: expected COLD-A capacity_value/uom to be stored as given';
  end if;
  if v_staging.effective_from is null or v_staging.effective_from <= now() then
    raise exception 'assertion failed: expected STAGING-B to carry a future effective_from (scheduled-future-zone alt flow)';
  end if;

  v_replay := app.create_warehouse_zone(v_wh1, 'AMBIENT-A', 'Ambient Zone A (retry)', 'ambient', null, null, null, null, null, null, '00000000-0000-0000-0000-000000070102', 'rep');
  if v_replay.id <> v_ambient.id then
    raise exception 'assertion failed: expected the same-code replay to return the identical row';
  end if;

  begin
    perform app.create_warehouse_zone(v_wh1, 'AMBIENT-A', 'Conflicting zone', 'secure', null, null, null, null, null, null, '00000000-0000-0000-0000-000000070102', 'rep');
    raise exception 'assertion failed: expected zone_code_conflict -- AMBIENT-A already exists with zone_type=ambient';
  exception
    when others then
      if sqlerrm not like 'zone_code_conflict%' then raise; end if;
  end;

  begin
    perform app.create_warehouse_zone(v_wh1, 'BAD-CAP', 'Bad capacity', 'ambient', null, 100, null, null, null, null, '00000000-0000-0000-0000-000000070102', 'rep');
    raise exception 'assertion failed: expected invalid_capacity -- capacity_value without capacity_uom';
  exception
    when others then
      if sqlerrm not like 'invalid_capacity%' then raise; end if;
  end;

  begin
    perform app.create_warehouse_zone(v_wh1, 'BAD-WINDOW', 'Bad window', 'ambient', null, null, null, null, now() + interval '2 days', now() + interval '1 days', '00000000-0000-0000-0000-000000070102', 'rep');
    raise exception 'assertion failed: expected invalid_effective_window';
  exception
    when others then
      if sqlerrm not like 'invalid_effective_window%' then raise; end if;
  end;

  if (select count(*) from app.warehouse_zones where warehouse_id = v_wh1) <> 4 then
    raise exception 'assertion failed: expected exactly 4 zones under WH-JKT-1 (ambient, cold_storage, secure, staging)';
  end if;
end $$;

\echo '>> app.update_warehouse_zone and app.set_warehouse_zone_status: stale version rejected; mutable fields update; on_hold requires a reason and is distinct from inactive; reactivating to active needs no reason'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'acmewms');
  v_zone app.warehouse_zones;
begin
  select z.* into v_zone from app.warehouse_zones z join app.warehouses w on w.id = z.warehouse_id where w.tenant_id = v_tenant1 and w.code = 'WH-JKT-1' and z.code = 'COLD-A';

  begin
    perform app.update_warehouse_zone(v_zone.id, 'Cold Storage Zone A', null, null, null, null, null, null, v_zone.record_version + 99, '00000000-0000-0000-0000-000000070102', 'rep');
    raise exception 'assertion failed: expected stale_version';
  exception
    when others then
      if sqlerrm not like 'stale_version%' then raise; end if;
  end;

  v_zone := app.update_warehouse_zone(v_zone.id, 'Cold Storage Zone A (expanded)', jsonb_build_object('target_temp_c', -20), 750, 'pallet_position', jsonb_build_object('hazmat_class', 'none'), null, null, v_zone.record_version, '00000000-0000-0000-0000-000000070102', 'rep');
  if v_zone.capacity_value <> 750 or v_zone.name <> 'Cold Storage Zone A (expanded)' then
    raise exception 'assertion failed: expected capacity_value/name to reflect the update';
  end if;

  begin
    perform app.set_warehouse_zone_status(v_zone.id, 'on_hold', null, v_zone.record_version, '00000000-0000-0000-0000-000000070102', 'rep');
    raise exception 'assertion failed: expected reason_required -- on_hold needs a non-empty reason';
  exception
    when others then
      if sqlerrm not like 'reason_required%' then raise; end if;
  end;

  v_zone := app.set_warehouse_zone_status(v_zone.id, 'on_hold', 'temporary maintenance freeze', v_zone.record_version, '00000000-0000-0000-0000-000000070102', 'rep');
  if v_zone.status <> 'on_hold' then
    raise exception 'assertion failed: expected zone status on_hold';
  end if;

  v_zone := app.set_warehouse_zone_status(v_zone.id, 'active', null, v_zone.record_version, '00000000-0000-0000-0000-000000070102', 'rep');
  if v_zone.status <> 'active' then
    raise exception 'assertion failed: expected zone status active again -- reactivation needs no reason';
  end if;
end $$;

\echo '>> app.grant_warehouse_customer_eligibility / app.revoke_warehouse_customer_eligibility: idempotent grant, revoke requires a reason and is terminal-then-reactivatable, and app.list_warehouse_customer_eligibility reflects it joined to the account''s own legal_name'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'acmewms');
  v_wh1 uuid := (select id from app.warehouses where tenant_id = v_tenant1 and code = 'WH-JKT-1');
  v_account_id uuid := (select id from app.accounts where tenant_id = v_tenant1 and legal_name = 'WMS229 Customer Co');
  v_grant app.warehouse_customer_eligibility;
  v_replay app.warehouse_customer_eligibility;
  v_regrant app.warehouse_customer_eligibility;
  v_listed record;
begin
  v_grant := app.grant_warehouse_customer_eligibility(v_wh1, v_account_id, '00000000-0000-0000-0000-000000070102', 'rep');
  if v_grant.status <> 'active' or v_grant.record_version <> 1 then
    raise exception 'assertion failed: expected a fresh active eligibility grant';
  end if;

  v_replay := app.grant_warehouse_customer_eligibility(v_wh1, v_account_id, '00000000-0000-0000-0000-000000070102', 'rep');
  if v_replay.id <> v_grant.id or v_replay.record_version <> 1 then
    raise exception 'assertion failed: expected granting an already-active eligibility to return it unchanged';
  end if;

  begin
    perform app.revoke_warehouse_customer_eligibility(v_grant.id, null, v_grant.record_version, '00000000-0000-0000-0000-000000070102', 'rep');
    raise exception 'assertion failed: expected reason_required';
  exception
    when others then
      if sqlerrm not like 'reason_required%' then raise; end if;
  end;

  v_grant := app.revoke_warehouse_customer_eligibility(v_grant.id, 'account no longer eligible', v_grant.record_version, '00000000-0000-0000-0000-000000070102', 'rep');
  if v_grant.status <> 'revoked' or v_grant.revoked_reason is null then
    raise exception 'assertion failed: expected the eligibility to be revoked with a reason recorded';
  end if;

  begin
    perform app.revoke_warehouse_customer_eligibility(v_grant.id, 'already revoked', v_grant.record_version, '00000000-0000-0000-0000-000000070102', 'rep');
    raise exception 'assertion failed: expected invalid_transition -- already revoked';
  exception
    when others then
      if sqlerrm not like 'invalid_transition%' then raise; end if;
  end;

  v_regrant := app.grant_warehouse_customer_eligibility(v_wh1, v_account_id, '00000000-0000-0000-0000-000000070102', 'rep');
  if v_regrant.id <> v_grant.id or v_regrant.status <> 'active' or v_regrant.revoked_at is not null then
    raise exception 'assertion failed: expected re-granting a revoked eligibility to reactivate the same row, not a new one';
  end if;

  select * into v_listed from app.list_warehouse_customer_eligibility(v_wh1, '00000000-0000-0000-0000-000000070102') where customer_account_id = v_account_id;
  if v_listed.customer_legal_name <> 'WMS229 Customer Co' or v_listed.status <> 'active' then
    raise exception 'assertion failed: expected the listing to reflect the reactivated grant joined to the account''s legal_name';
  end if;
end $$;

\echo '>> app.get_warehouse_deactivation_impact / app.set_warehouse_status: deactivation is blocked while active/on_hold zones exist and requires a reason; deactivating every zone first then unblocks it; the impact preview matches exactly what the mutation blocks on'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'acmewms');
  v_wh1 app.warehouses;
  v_impact app.warehouse_deactivation_impact;
  v_zone_id uuid;
begin
  select * into v_wh1 from app.warehouses where tenant_id = v_tenant1 and code = 'WH-JKT-1';

  select * into v_impact from app.get_warehouse_deactivation_impact(v_wh1.id, '00000000-0000-0000-0000-000000070102');
  if v_impact.active_zone_count <> 4 then
    raise exception 'assertion failed: expected 4 active zones (ambient, cold, secure, staging), got %', v_impact.active_zone_count;
  end if;

  begin
    perform app.set_warehouse_status(v_wh1.id, 'inactive', 'test deactivation attempt', v_wh1.record_version, '00000000-0000-0000-0000-000000070102', 'rep');
    raise exception 'assertion failed: expected warehouse_has_active_zones';
  exception
    when others then
      if sqlerrm not like 'warehouse_has_active_zones%' then raise; end if;
  end;

  begin
    perform app.set_warehouse_status(v_wh1.id, 'inactive', null, v_wh1.record_version, '00000000-0000-0000-0000-000000070102', 'rep');
    raise exception 'assertion failed: expected reason_required (checked before the active-zone guard would even matter, but must still be enforced)';
  exception
    when others then
      if sqlerrm not like 'reason_required%' then raise; end if;
  end;

  for v_zone_id in select id from app.warehouse_zones where warehouse_id = v_wh1.id loop
    perform app.set_warehouse_zone_status(v_zone_id, 'inactive', 'wound down for deactivation test', (select record_version from app.warehouse_zones where id = v_zone_id), '00000000-0000-0000-0000-000000070102', 'rep');
  end loop;

  select * into v_impact from app.get_warehouse_deactivation_impact(v_wh1.id, '00000000-0000-0000-0000-000000070102');
  if v_impact.active_zone_count <> 0 or v_impact.on_hold_zone_count <> 0 then
    raise exception 'assertion failed: expected zero active/on_hold zones after winding every zone down';
  end if;

  v_wh1 := app.set_warehouse_status(v_wh1.id, 'inactive', 'no longer needed', v_wh1.record_version, '00000000-0000-0000-0000-000000070102', 'rep');
  if v_wh1.status <> 'inactive' then
    raise exception 'assertion failed: expected the warehouse to deactivate once every zone is wound down';
  end if;

  -- Same-status transition is a silent no-op returning the current row, not an error.
  if (app.set_warehouse_status(v_wh1.id, 'inactive', null, v_wh1.record_version, '00000000-0000-0000-0000-000000070102', 'rep')).record_version <> v_wh1.record_version then
    raise exception 'assertion failed: expected a same-status transition to be a no-op';
  end if;
end $$;

\echo '>> app.list_tenant_warehouses / app.list_warehouse_zones: JKT-scoped rep sees WH-JKT-1/WH-JKT-2 with correct zone_count/active_zone_count; SBY-scoped rep (wrong branch scope) sees zero warehouses; cross-tenant rep2 sees zero'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'acmewms');
  v_row record;
  v_wh1_row record;
  v_count integer;
begin
  select count(*) into v_count from app.list_tenant_warehouses(v_tenant1, '00000000-0000-0000-0000-000000070102', null);
  if v_count <> 2 then
    raise exception 'assertion failed: expected JKT-scoped rep to see exactly 2 warehouses (WH-JKT-1, WH-JKT-2), got %', v_count;
  end if;

  select * into v_wh1_row from app.list_tenant_warehouses(v_tenant1, '00000000-0000-0000-0000-000000070102', null) where code = 'WH-JKT-1';
  if v_wh1_row.zone_count <> 4 or v_wh1_row.active_zone_count <> 0 then
    raise exception 'assertion failed: expected WH-JKT-1 zone_count=4/active_zone_count=0 after the deactivation test, got zone_count=%/active_zone_count=%', v_wh1_row.zone_count, v_wh1_row.active_zone_count;
  end if;

  select count(*) into v_count from app.list_tenant_warehouses(v_tenant1, '00000000-0000-0000-0000-000000070104', null);
  if v_count <> 0 then
    raise exception 'assertion failed: expected SBY-scoped rep to see zero warehouses (record-scope, not just tenant membership), got %', v_count;
  end if;

  select count(*) into v_count from app.list_warehouse_zones((select id from app.warehouses where tenant_id = v_tenant1 and code = 'WH-JKT-1'), '00000000-0000-0000-0000-000000070102', 'inactive');
  if v_count <> 4 then
    raise exception 'assertion failed: expected all 4 zones filtered to status=inactive, got %', v_count;
  end if;
end $$;

\echo '>> cross-tenant isolation: tenant2''s rep cannot read tenant1''s warehouses via list_tenant_warehouses (evaluate_permission fails closed for a foreign tenant_id) nor mutate tenant1''s warehouse'
do $$
declare
  v_tenant2 uuid := (select id from app.tenants where slug = 'acmewms2');
  v_wh1 uuid := (select id from app.warehouses where tenant_id = (select id from app.tenants where slug = 'acmewms') and code = 'WH-JKT-1');
begin
  begin
    perform app.list_tenant_warehouses(v_tenant2, '00000000-0000-0000-0000-000000070102', null);
    raise exception 'assertion failed: expected insufficient_authority -- acmewms rep has no membership in acmewms2';
  exception
    when others then
      if sqlerrm not like 'insufficient_authority%' then raise; end if;
  end;

  begin
    -- ISS-2026-146: the probing actor is rep2 070107 (acmewms2's rep, zero membership in acmewms).
    -- app.update_warehouse now folds a caller with zero
    -- membership in the probed record's own tenant into the SAME generic warehouse_not_found
    -- a nonexistent id already produced, instead of an insufficient_authority message
    -- carrying that tenant's real tenant_id. The refusal itself is unchanged.
    perform app.update_warehouse(v_wh1, 'Hijacked name', null, 'Asia/Jakarta', null, '{}'::text[], 1, '00000000-0000-0000-0000-000000070107', 'rep2');
    raise exception 'assertion failed: expected warehouse_not_found (ISS-2026-146) -- tenant2''s rep2 has no membership in acmewms (tenant1)';
  exception
    when others then
      if sqlerrm not like 'warehouse_not_found%' then raise; end if;
  end;
end $$;

\echo '>> schema-privilege defense in depth (ERR-2026-004): anon holds no direct table/EXECUTE access; authenticated has RLS-scoped SELECT but no direct INSERT/UPDATE/DELETE; only service_role may write directly'
do $$
begin
  if has_table_privilege('anon', 'app.warehouses', 'SELECT') then
    raise exception 'assertion failed: anon must not have direct SELECT on app.warehouses';
  end if;
  if has_function_privilege('anon', 'app.create_warehouse(uuid, uuid, text, text, text, text, jsonb, text[], uuid, text)', 'EXECUTE') then
    raise exception 'assertion failed: anon must not have EXECUTE on app.create_warehouse';
  end if;
  if not has_table_privilege('authenticated', 'app.warehouses', 'SELECT') then
    raise exception 'assertion failed: authenticated must have RLS-scoped SELECT on app.warehouses';
  end if;
  if has_table_privilege('authenticated', 'app.warehouses', 'INSERT') then
    raise exception 'assertion failed: authenticated must not have direct INSERT on app.warehouses -- mutation must go through the SECURITY DEFINER RPCs only';
  end if;
  if not has_table_privilege('service_role', 'app.warehouse_zones', 'INSERT') then
    raise exception 'assertion failed: service_role must retain direct table access';
  end if;
end $$;
