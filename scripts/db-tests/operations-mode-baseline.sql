-- Real, executable test evidence for OPS-171 (Land, Air and Sea Baseline, CG-S8-OPS-005)
-- -- run via `pnpm run db:test` against a real, disposable Postgres database.

\set ON_ERROR_STOP on

\echo '>> setup: one tenant, a company/team-a/team-b org hierarchy, a bootstrap tenant-admin, a rep (COM:Create/Edit/Approve/View/View cost + OPS:Create/Edit), an OPS-viewer-only actor, a sibling-team outsider, one confirmed Job Order, and five Shipment Orders off it (land/air/sea/land-for-mode-change/land-for-cancel), all draft'
do $$
declare
  v_tenant1 uuid;
  v_team_a uuid;
  v_team_b uuid;
  v_rep_role uuid;
  v_rep_draft app.role_versions;
  v_viewer_role uuid;
  v_viewer_draft app.role_versions;
  v_outsider_role uuid;
  v_outsider_draft app.role_versions;
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
  v_handoff app.job_order_handoffs;
  v_job_order app.job_orders;
  v_shipment_land app.shipment_orders;
  v_shipment_air app.shipment_orders;
  v_shipment_sea app.shipment_orders;
  v_shipment_mode_change app.shipment_orders;
  v_shipment_cancel app.shipment_orders;
begin
  insert into auth.users (id, email) values
    ('00000000-0000-0000-0000-000000009990', 'admin@acmemode.test'),
    ('00000000-0000-0000-0000-000000009991', 'repa@acmemode.test'),
    ('00000000-0000-0000-0000-000000009992', 'viewer@acmemode.test'),
    ('00000000-0000-0000-0000-000000009993', 'outsider@acmemode.test');

  perform app.provision_tenant('acmemode', 'Acme Mode Co', 'idem-acmemode', 'tester');
  v_tenant1 := (select id from app.tenants where slug = 'acmemode');
  perform app.transition_tenant_status(v_tenant1, 'active', 'setup', 'tester');

  perform app.create_org_unit(v_tenant1, 'company', null, 'ACMEMODE-CO', 'Acme Mode Co', 'tester');
  perform app.create_org_unit(v_tenant1, 'department', (select id from app.org_units where tenant_id = v_tenant1 and code = 'ACMEMODE-CO'), 'ACMEMODE-TEAM-A', 'Team A', 'tester');
  v_team_a := (select id from app.org_units where tenant_id = v_tenant1 and code = 'ACMEMODE-TEAM-A');
  perform app.create_org_unit(v_tenant1, 'department', (select id from app.org_units where tenant_id = v_tenant1 and code = 'ACMEMODE-CO'), 'ACMEMODE-TEAM-B', 'Team B', 'tester');
  v_team_b := (select id from app.org_units where tenant_id = v_tenant1 and code = 'ACMEMODE-TEAM-B');

  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000009990', 'admin@acmemode.test', 'Mode Admin', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'admin@acmemode.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000009990', 'tenant_admin', v_tenant1, null, 'tester');

  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000009991', 'repa@acmemode.test', 'Rep A', v_team_a, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'repa@acmemode.test'), 'active', 'onboarded', 'tester');
  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000009992', 'viewer@acmemode.test', 'OPS Viewer', v_team_a, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'viewer@acmemode.test'), 'active', 'onboarded', 'tester');
  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000009993', 'outsider@acmemode.test', 'Team B Outsider', v_team_b, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'outsider@acmemode.test'), 'active', 'onboarded', 'tester');

  v_rep_role := (app.create_role(v_tenant1, 'Mode Rep', 'full commercial + ops grants', 'tester')).id;
  v_rep_draft := app.create_role_version(v_rep_role, 'tester');
  perform app.set_role_version_permissions(
    v_rep_draft.id,
    array(select id from app.permissions where (resource_module_code = 'COM' and action in ('Create', 'Edit', 'Approve', 'View', 'View cost'))
      or (resource_module_code = 'OPS' and action in ('Create', 'Edit', 'View'))),
    'tester'
  );
  perform app.publish_role_version(v_rep_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_rep_role and status = 'published'), '00000000-0000-0000-0000-000000009991', '00000000-0000-0000-0000-000000009990', 'tester');

  v_viewer_role := (app.create_role(v_tenant1, 'Mode Ops Viewer', 'OPS:View only, no Edit', 'tester')).id;
  v_viewer_draft := app.create_role_version(v_viewer_role, 'tester');
  perform app.set_role_version_permissions(
    v_viewer_draft.id,
    array(select id from app.permissions where resource_module_code = 'OPS' and action in ('View')),
    'tester'
  );
  perform app.publish_role_version(v_viewer_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_viewer_role and status = 'published'), '00000000-0000-0000-0000-000000009992', '00000000-0000-0000-0000-000000009992', 'tester');

  v_outsider_role := (app.create_role(v_tenant1, 'Mode Outsider', 'sibling team, full grants', 'tester')).id;
  v_outsider_draft := app.create_role_version(v_outsider_role, 'tester');
  perform app.set_role_version_permissions(
    v_outsider_draft.id,
    array(select id from app.permissions where (resource_module_code = 'COM' and action in ('Create', 'Edit', 'View'))
      or (resource_module_code = 'OPS' and action in ('Create', 'Edit', 'View'))),
    'tester'
  );
  perform app.publish_role_version(v_outsider_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_outsider_role and status = 'published'), '00000000-0000-0000-0000-000000009993', '00000000-0000-0000-0000-000000009991', 'tester');

  perform app.capture_lead(v_tenant1, 'manual', null, 'Mode Test Co', 'Jane Mode', 'jane@modetest.test', '0811',
    '00000000-0000-0000-0000-000000009991', v_team_a, '00000000-0000-0000-0000-000000009991', 'tester');
  select * into v_lead from app.leads where email = 'jane@modetest.test';
  perform app.qualify_lead(v_lead.id, v_lead.record_version, '00000000-0000-0000-0000-000000009991', 'tester');
  select * into v_lead from app.leads where id = v_lead.id;
  perform app.convert_lead_to_prospect(v_lead.id, 'Mode Test Co', 'MTC', '11.111.111.1-111.000',
    jsonb_build_object('line1', 'Jl. Rasuna Said 1', 'city', 'Jakarta', 'country', 'ID'),
    '00000000-0000-0000-0000-000000009991', 'tester');
  select * into v_prospect from app.prospects where lead_id = v_lead.id;

  select * into v_contact from app.create_contact(v_tenant1, 'Jane Mode Ops', 'Procurement Lead', 'jane@modetest.test', '0811', '00000000-0000-0000-0000-000000009991', v_team_a, '00000000-0000-0000-0000-000000009991', 'tester');
  perform app.link_contact_to_record(v_contact.id, 'prospect', v_prospect.id, 'primary', true, '00000000-0000-0000-0000-000000009991', 'tester');

  select * into v_opportunity from app.create_opportunity(
    v_tenant1, v_prospect.id, 'Mode test lane',
    jsonb_build_object('service_type', 'ocean_freight', 'cargo_description', 'General cargo', 'origin', 'Jakarta', 'destination', 'Surabaya', 'target_ready_date', '2026-08-01'),
    '00000000-0000-0000-0000-000000009991', v_team_a, '00000000-0000-0000-0000-000000009991', 'tester'
  );
  select * into v_request from app.request_costing(v_opportunity.id, '[]'::jsonb, null, '00000000-0000-0000-0000-000000009991', 'tester');
  select * into v_rate from app.create_rate_version(
    v_tenant1, 'VENDOR-MODE-1', 'Contoso Ocean Line', 'ocean_freight', 'FCL', 'Jakarta', 'Surabaya', '20ft',
    null, null, null, null, 'IDR', 10000000, null, '[]'::jsonb, now(), null, null, '00000000-0000-0000-0000-000000009990', 'tester'
  );
  perform app.approve_rate_version(v_rate.id, v_rate.record_version, '00000000-0000-0000-0000-000000009990', 'tester');
  select * into v_selection from app.select_vendor_rate(v_request.id, v_rate.id, false, null, null, null, '00000000-0000-0000-0000-000000009991', 'tester');

  select * into v_rule from app.create_margin_rule_version(v_tenant1, 20.00, 'half_up', '00000000-0000-0000-0000-000000009991', 'tester');
  perform app.publish_margin_rule_version(v_rule.id, v_rule.record_version, null, '00000000-0000-0000-0000-000000009991', 'tester');
  perform app.calculate_margin(v_selection.id, 15000000, 'IDR', 0, '00000000-0000-0000-0000-000000009991', 'tester');
  select id into v_calc_id from app.margin_calculations where rate_selection_id = v_selection.id and is_current;

  select * into v_quote from app.create_quotation_draft(v_tenant1, v_opportunity.id, 'IDR', now() + interval '14 days', v_contact.id, null, null, '00000000-0000-0000-0000-000000009991', 'tester');
  perform app.add_quotation_line(v_quote.id, v_quote.record_version, 'service', 'Ocean freight ops lane', v_calc_id, 1, 15000000, 0, 0, '00000000-0000-0000-0000-000000009991', 'tester');
  select * into v_quote from app.quotations where id = v_quote.id;
  perform app.submit_quotation(v_quote.id, v_quote.record_version, '00000000-0000-0000-0000-000000009991', 'tester');
  select * into v_send from app.send_quotation_for_acceptance(v_quote.id, null, 'email', '00000000-0000-0000-0000-000000009991', 'tester');
  perform app.record_quotation_customer_decision(v_send.raw_token, 'accepted', 'Jane Mode Ops', null, null, null, null, null);
  select * into v_quote from app.quotations where id = v_quote.id;
  select * into v_account from app.convert_quotation_to_account(v_quote.id, null, null, '00000000-0000-0000-0000-000000009991', 'rep');
  select * into v_handoff from app.prepare_job_order_handoff(v_quote.id, '00000000-0000-0000-0000-000000009991', 'rep');

  select * into v_job_order from app.prepare_job_order(v_handoff.id, '00000000-0000-0000-0000-000000009991', 'rep');
  select * into v_job_order from app.confirm_job_order(v_job_order.id, v_job_order.record_version, '00000000-0000-0000-0000-000000009991', 'rep');

  select * into v_shipment_land from app.create_shipment_order_from_job(
    v_job_order.id, 'idem-mode-land', null, null, 'ocean_freight', 'land', 'Jakarta', 'Surabaya',
    null, null, null, null, null, null, null, null, null, '00000000-0000-0000-0000-000000009991', 'rep'
  );
  select * into v_shipment_air from app.create_shipment_order_from_job(
    v_job_order.id, 'idem-mode-air', null, null, 'air_freight', 'air', 'Jakarta', 'Denpasar',
    null, null, null, null, null, null, null, null, 'split: air leg', '00000000-0000-0000-0000-000000009991', 'rep'
  );
  select * into v_shipment_sea from app.create_shipment_order_from_job(
    v_job_order.id, 'idem-mode-sea', null, null, 'ocean_freight', 'sea', 'Jakarta', 'Singapore',
    null, null, null, null, null, null, null, null, 'split: sea leg', '00000000-0000-0000-0000-000000009991', 'rep'
  );
  select * into v_shipment_mode_change from app.create_shipment_order_from_job(
    v_job_order.id, 'idem-mode-change', null, null, 'ocean_freight', 'land', 'Jakarta', 'Bandung',
    null, null, null, null, null, null, null, null, 'split: mode-change fixture', '00000000-0000-0000-0000-000000009991', 'rep'
  );
  select * into v_shipment_cancel from app.create_shipment_order_from_job(
    v_job_order.id, 'idem-mode-cancel', null, null, 'ocean_freight', 'land', 'Jakarta', 'Semarang',
    null, null, null, null, null, null, null, null, 'split: cancel fixture', '00000000-0000-0000-0000-000000009991', 'rep'
  );
end $$;

\echo '>> app.set_shipment_mode_profile: authority-gated (an OPS:View-only actor denied); missing_required_reference for an incomplete land profile; a valid land profile is created with every irrelevant (air/sea) column structurally null; idempotent update in place'
do $$
declare
  v_shipment_id uuid;
  v_profile app.shipment_mode_profiles;
begin
  select id into v_shipment_id from app.shipment_orders where idempotency_key = 'idem-mode-land';

  begin
    perform app.set_shipment_mode_profile(
      v_shipment_id, 'TRK-001', 'VENDOR-TRK-1', 'Jl. Gudang 1, Jakarta', 'Jl. Pasar 1, Surabaya',
      null, null, null, null, null, null, null, null, null, null, null,
      '00000000-0000-0000-0000-000000009992', 'viewer'
    );
    raise exception 'assertion failed: expected insufficient_authority for an OPS:View-only actor';
  exception
    when others then
      if sqlerrm not like 'insufficient_authority%' then
        raise;
      end if;
  end;

  begin
    perform app.set_shipment_mode_profile(
      v_shipment_id, 'TRK-001', null, 'Jl. Gudang 1, Jakarta', 'Jl. Pasar 1, Surabaya',
      null, null, null, null, null, null, null, null, null, null, null,
      '00000000-0000-0000-0000-000000009991', 'rep'
    );
    raise exception 'assertion failed: expected missing_required_reference for a land profile missing vendor_ref';
  exception
    when others then
      if sqlerrm not like 'missing_required_reference%' then
        raise;
      end if;
  end;

  select * into v_profile from app.set_shipment_mode_profile(
    v_shipment_id, 'TRK-001', 'VENDOR-TRK-1', 'Jl. Gudang 1, Jakarta', 'Jl. Pasar 1, Surabaya',
    null, null, null, null, null, null, null, null, null, null, null,
    '00000000-0000-0000-0000-000000009991', 'rep'
  );
  if v_profile.mode <> 'land' or v_profile.land_vehicle_ref <> 'TRK-001' then
    raise exception 'assertion failed: expected a real land profile with land_vehicle_ref=TRK-001';
  end if;
  if v_profile.air_awb_number is not null or v_profile.sea_bl_number is not null then
    raise exception 'assertion failed: expected air/sea columns to stay structurally null on a land profile';
  end if;

  select * into v_profile from app.set_shipment_mode_profile(
    v_shipment_id, 'TRK-001', 'VENDOR-TRK-1', 'Jl. Gudang 1, Jakarta', 'Jl. Pasar 2, Surabaya (updated)',
    null, null, null, null, null, null, null, null, null, null, null,
    '00000000-0000-0000-0000-000000009991', 'rep'
  );
  if v_profile.land_delivery_address <> 'Jl. Pasar 2, Surabaya (updated)' then
    raise exception 'assertion failed: expected the idempotent upsert to update the delivery address in place';
  end if;
  if (select count(*) from app.shipment_mode_profiles where shipment_order_id = v_shipment_id) <> 1 then
    raise exception 'assertion failed: expected exactly one profile row after the idempotent update';
  end if;
end $$;

\echo '>> app.set_shipment_mode_profile: a valid air profile and a valid sea profile (with and without optional container fields), each with every irrelevant column structurally null'
do $$
declare
  v_shipment_air_id uuid;
  v_shipment_sea_id uuid;
  v_profile app.shipment_mode_profiles;
begin
  select id into v_shipment_air_id from app.shipment_orders where idempotency_key = 'idem-mode-air';
  select * into v_profile from app.set_shipment_mode_profile(
    v_shipment_air_id, null, null, null, null,
    'AWB-12345678', 'GA-402', 'CGK', 'DPS',
    null, null, null, null, null, null, null,
    '00000000-0000-0000-0000-000000009991', 'rep'
  );
  if v_profile.mode <> 'air' or v_profile.air_awb_number <> 'AWB-12345678' then
    raise exception 'assertion failed: expected a real air profile with air_awb_number=AWB-12345678';
  end if;
  if v_profile.land_vehicle_ref is not null or v_profile.sea_bl_number is not null then
    raise exception 'assertion failed: expected land/sea columns to stay structurally null on an air profile';
  end if;

  select id into v_shipment_sea_id from app.shipment_orders where idempotency_key = 'idem-mode-sea';
  select * into v_profile from app.set_shipment_mode_profile(
    v_shipment_sea_id, null, null, null, null,
    null, null, null, null,
    'BL-2026-0001', 'BOOK-2026-0001', 'MV Contoso Star', 'IDJKT', 'SGSIN', null, null,
    '00000000-0000-0000-0000-000000009991', 'rep'
  );
  if v_profile.mode <> 'sea' or v_profile.sea_bl_number <> 'BL-2026-0001' or v_profile.sea_container_number is not null then
    raise exception 'assertion failed: expected a real sea profile with no container reference (LCL, optional)';
  end if;
end $$;

\echo '>> app.set_shipment_mode_profile: blocked once the shipment is cancelled'
do $$
declare
  v_shipment app.shipment_orders;
begin
  select * into v_shipment from app.shipment_orders where idempotency_key = 'idem-mode-cancel';
  select * into v_shipment from app.transition_shipment_order(v_shipment.id, 'cancelled', v_shipment.record_version, 'no longer needed', null, 'idem-mode-cancel-transition', '00000000-0000-0000-0000-000000009991', 'rep');

  begin
    perform app.set_shipment_mode_profile(
      v_shipment.id, 'TRK-002', 'VENDOR-TRK-2', 'Jl. A', 'Jl. B',
      null, null, null, null, null, null, null, null, null, null, null,
      '00000000-0000-0000-0000-000000009991', 'rep'
    );
    raise exception 'assertion failed: expected invalid_transition -- a cancelled shipment''s mode profile can no longer be set';
  exception
    when others then
      if sqlerrm not like 'invalid_transition%' then
        raise;
      end if;
  end;
end $$;

\echo '>> app.change_shipment_mode: invalid_mode rejected; stale_version rejected; a valid draft mode change (land -> air) reconciles by deleting the prior land profile; confirmed_mode_change_blocked once the shipment leaves draft'
do $$
declare
  v_shipment app.shipment_orders;
  v_profile app.shipment_mode_profiles;
begin
  select * into v_shipment from app.shipment_orders where idempotency_key = 'idem-mode-change';

  perform app.set_shipment_mode_profile(
    v_shipment.id, 'TRK-003', 'VENDOR-TRK-3', 'Jl. C', 'Jl. D',
    null, null, null, null, null, null, null, null, null, null, null,
    '00000000-0000-0000-0000-000000009991', 'rep'
  );
  select * into v_shipment from app.shipment_orders where id = v_shipment.id;

  begin
    perform app.change_shipment_mode(v_shipment.id, 'rail', v_shipment.record_version, '00000000-0000-0000-0000-000000009991', 'rep');
    raise exception 'assertion failed: expected invalid_mode for an unsupported mode';
  exception
    when others then
      if sqlerrm not like 'invalid_mode%' then
        raise;
      end if;
  end;

  begin
    perform app.change_shipment_mode(v_shipment.id, 'air', v_shipment.record_version + 99, '00000000-0000-0000-0000-000000009991', 'rep');
    raise exception 'assertion failed: expected stale_version to be rejected';
  exception
    when others then
      if sqlerrm not like 'stale_version%' then
        raise;
      end if;
  end;

  select * into v_shipment from app.change_shipment_mode(v_shipment.id, 'air', v_shipment.record_version, '00000000-0000-0000-0000-000000009991', 'rep');
  if v_shipment.mode <> 'air' then
    raise exception 'assertion failed: expected the shipment''s own mode to become air';
  end if;
  if exists (select 1 from app.shipment_mode_profiles where shipment_order_id = v_shipment.id) then
    raise exception 'assertion failed: expected the prior (now-incompatible) land profile to be reconciled away by the mode change';
  end if;

  select * into v_shipment from app.confirm_shipment_order(v_shipment.id, v_shipment.record_version, '00000000-0000-0000-0000-000000009991', 'rep');
  begin
    perform app.change_shipment_mode(v_shipment.id, 'sea', v_shipment.record_version, '00000000-0000-0000-0000-000000009991', 'rep');
    raise exception 'assertion failed: expected confirmed_mode_change_blocked once the shipment is no longer draft';
  exception
    when others then
      if sqlerrm not like 'confirmed_mode_change_blocked%' then
        raise;
      end if;
  end;
end $$;

\echo '>> record-scope: a sibling-team outsider (different org unit, no ownership stake) cannot access the shipment via app.set_shipment_mode_profile/app.change_shipment_mode despite holding full OPS/COM permissions'
do $$
declare
  v_shipment app.shipment_orders;
begin
  select * into v_shipment from app.shipment_orders where idempotency_key = 'idem-mode-land';

  begin
    perform app.set_shipment_mode_profile(
      v_shipment.id, 'TRK-999', 'VENDOR-999', 'Jl. X', 'Jl. Y',
      null, null, null, null, null, null, null, null, null, null, null,
      '00000000-0000-0000-0000-000000009993', 'outsider'
    );
    raise exception 'assertion failed: expected the sibling-team outsider to be denied by record scope';
  exception
    when others then
      if sqlerrm not like 'insufficient_authority%' then
        raise;
      end if;
  end;

  begin
    perform app.change_shipment_mode(v_shipment.id, 'air', v_shipment.record_version, '00000000-0000-0000-0000-000000009993', 'outsider');
    raise exception 'assertion failed: expected the sibling-team outsider to be denied by record scope';
  exception
    when others then
      if sqlerrm not like 'insufficient_authority%' then
        raise;
      end if;
  end;
end $$;

\echo '>> cross-tenant isolation: app.set_shipment_mode_profile/app.change_shipment_mode fail closed for an identity with no membership in the Shipment Order''s own tenant'
do $$
declare
  v_tenant2 uuid;
  v_shipment app.shipment_orders;
begin
  insert into auth.users (id, email) values ('00000000-0000-0000-0000-000000009994', 'admin2@acmemode2.test');
  perform app.provision_tenant('acmemode2', 'Acme Mode Co 2', 'idem-acmemode2', 'tester');
  v_tenant2 := (select id from app.tenants where slug = 'acmemode2');
  perform app.transition_tenant_status(v_tenant2, 'active', 'setup', 'tester');
  perform app.invite_user(v_tenant2, '00000000-0000-0000-0000-000000009994', 'admin2@acmemode2.test', 'Tenant 2 Admin', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'admin2@acmemode2.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000009994', 'tenant_admin', v_tenant2, null, 'tester');

  select * into v_shipment from app.shipment_orders where idempotency_key = 'idem-mode-land';

  begin
    perform app.set_shipment_mode_profile(
      v_shipment.id, 'TRK-XX', 'VENDOR-XX', 'Jl. XX', 'Jl. YY',
      null, null, null, null, null, null, null, null, null, null, null,
      '00000000-0000-0000-0000-000000009994', 'tenant2-admin'
    );
    raise exception 'assertion failed: expected insufficient_privilege -- tenant 2''s admin holds no OPS:Edit in tenant 1';
  exception
    when others then
      if sqlerrm not like 'insufficient_authority%' then
        raise;
      end if;
  end;

  begin
    perform app.change_shipment_mode(v_shipment.id, 'air', v_shipment.record_version, '00000000-0000-0000-0000-000000009994', 'tenant2-admin');
    raise exception 'assertion failed: expected insufficient_privilege -- tenant 2''s admin holds no OPS:Edit in tenant 1';
  exception
    when others then
      if sqlerrm not like 'insufficient_authority%' then
        raise;
      end if;
  end;
end $$;

\echo '>> schema-privilege defense in depth: anon holds no EXECUTE on either new Land/Air/Sea Baseline function (ERR-2026-004 regression guard)'
do $$
declare
  v_count integer;
begin
  select count(*) into v_count
  from information_schema.routine_privileges
  where routine_schema = 'app'
    and grantee = 'anon'
    and routine_name in ('set_shipment_mode_profile', 'change_shipment_mode');
  if v_count <> 0 then
    raise exception 'assertion failed: expected zero anon EXECUTE grants on the 2 new Land/Air/Sea Baseline functions, found %', v_count;
  end if;
end $$;

\echo '>> audit trail: every real set_shipment_mode_profile/change_shipment_mode call recorded a real app.audit_logs event, tenant-scoped'
do $$
declare
  v_tenant1 uuid;
  v_profile_count integer;
  v_mode_change_count integer;
begin
  v_tenant1 := (select id from app.tenants where slug = 'acmemode');
  select count(*) into v_profile_count
  from app.audit_logs
  where tenant_id = v_tenant1 and resource_type = 'app.shipment_mode_profiles' and action = 'set_shipment_mode_profile';
  if v_profile_count <> 5 then
    raise exception 'assertion failed: expected exactly 5 set_shipment_mode_profile audit events (land created + land updated + air + sea + mode-change fixture''s own land profile), found %', v_profile_count;
  end if;

  select count(*) into v_mode_change_count
  from app.audit_logs
  where tenant_id = v_tenant1 and resource_type = 'app.shipment_orders' and action = 'change_shipment_mode';
  if v_mode_change_count <> 1 then
    raise exception 'assertion failed: expected exactly 1 change_shipment_mode audit event, found %', v_mode_change_count;
  end if;
end $$;
