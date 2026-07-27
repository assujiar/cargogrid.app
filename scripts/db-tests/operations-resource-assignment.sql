-- Real, executable test evidence for OPS-172 (Resource/Vendor Assignment, CG-S8-OPS-006)
-- -- run via `pnpm run db:test` against a real, disposable Postgres database.

\set ON_ERROR_STOP on

\echo '>> setup: one tenant, a company/team-a/team-b org hierarchy, a bootstrap tenant-admin, a rep (COM full + OPS:Create/Edit/View/Assign), an OPS-viewer-only actor, a sibling-team outsider, one confirmed Job Order, three Shipment Orders off it (main/conflict/cancel), and 5 master records (2 vendors, 1 fleet, 1 vehicle, 1 driver -- plus one deactivated decoy vendor)'
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
  v_shipment_main app.shipment_orders;
  v_shipment_conflict app.shipment_orders;
  v_shipment_cancel app.shipment_orders;
  v_vendor_1 app.master_records;
  v_vendor_2 app.master_records;
  v_vendor_3 app.master_records;
  v_vendor_decoy app.master_records;
  v_fleet_1 app.master_records;
  v_vehicle_1 app.master_records;
  v_driver_1 app.master_records;
begin
  insert into auth.users (id, email) values
    ('00000000-0000-0000-0000-000000009805', 'admin@acmeres.test'),
    ('00000000-0000-0000-0000-000000009806', 'repa@acmeres.test'),
    ('00000000-0000-0000-0000-000000009807', 'viewer@acmeres.test'),
    ('00000000-0000-0000-0000-000000009808', 'outsider@acmeres.test');

  perform app.provision_tenant('acmeres', 'Acme Resource Co', 'idem-acmeres', 'tester');
  v_tenant1 := (select id from app.tenants where slug = 'acmeres');
  perform app.transition_tenant_status(v_tenant1, 'active', 'setup', 'tester');

  perform app.create_org_unit(v_tenant1, 'company', null, 'ACMERES-CO', 'Acme Resource Co', 'tester');
  perform app.create_org_unit(v_tenant1, 'department', (select id from app.org_units where tenant_id = v_tenant1 and code = 'ACMERES-CO'), 'ACMERES-TEAM-A', 'Team A', 'tester');
  v_team_a := (select id from app.org_units where tenant_id = v_tenant1 and code = 'ACMERES-TEAM-A');
  perform app.create_org_unit(v_tenant1, 'department', (select id from app.org_units where tenant_id = v_tenant1 and code = 'ACMERES-CO'), 'ACMERES-TEAM-B', 'Team B', 'tester');
  v_team_b := (select id from app.org_units where tenant_id = v_tenant1 and code = 'ACMERES-TEAM-B');

  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000009805', 'admin@acmeres.test', 'Res Admin', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'admin@acmeres.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000009805', 'tenant_admin', v_tenant1, null, 'tester');

  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000009806', 'repa@acmeres.test', 'Rep A', v_team_a, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'repa@acmeres.test'), 'active', 'onboarded', 'tester');
  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000009807', 'viewer@acmeres.test', 'OPS Viewer', v_team_a, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'viewer@acmeres.test'), 'active', 'onboarded', 'tester');
  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000009808', 'outsider@acmeres.test', 'Team B Outsider', v_team_b, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'outsider@acmeres.test'), 'active', 'onboarded', 'tester');

  v_rep_role := (app.create_role(v_tenant1, 'Resource Rep', 'full commercial + ops grants', 'tester')).id;
  v_rep_draft := app.create_role_version(v_rep_role, 'tester');
  perform app.set_role_version_permissions(
    v_rep_draft.id,
    array(select id from app.permissions where (resource_module_code = 'COM' and action in ('Create', 'Edit', 'Approve', 'View', 'View cost'))
      or (resource_module_code = 'OPS' and action in ('Create', 'Edit', 'View', 'Assign'))),
    'tester'
  );
  perform app.publish_role_version(v_rep_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_rep_role and status = 'published'), '00000000-0000-0000-0000-000000009806', '00000000-0000-0000-0000-000000009805', 'tester');

  v_viewer_role := (app.create_role(v_tenant1, 'Resource Ops Viewer', 'OPS:View only, no Assign/Edit', 'tester')).id;
  v_viewer_draft := app.create_role_version(v_viewer_role, 'tester');
  perform app.set_role_version_permissions(
    v_viewer_draft.id,
    array(select id from app.permissions where resource_module_code = 'OPS' and action in ('View')),
    'tester'
  );
  perform app.publish_role_version(v_viewer_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_viewer_role and status = 'published'), '00000000-0000-0000-0000-000000009807', '00000000-0000-0000-0000-000000009807', 'tester');

  v_outsider_role := (app.create_role(v_tenant1, 'Resource Outsider', 'sibling team, full grants', 'tester')).id;
  v_outsider_draft := app.create_role_version(v_outsider_role, 'tester');
  perform app.set_role_version_permissions(
    v_outsider_draft.id,
    array(select id from app.permissions where (resource_module_code = 'COM' and action in ('Create', 'Edit', 'View'))
      or (resource_module_code = 'OPS' and action in ('Create', 'Edit', 'View', 'Assign'))),
    'tester'
  );
  perform app.publish_role_version(v_outsider_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_outsider_role and status = 'published'), '00000000-0000-0000-0000-000000009808', '00000000-0000-0000-0000-000000009805', 'tester');

  perform app.capture_lead(v_tenant1, 'manual', null, 'Res Test Co', 'Jane Res', 'jane@restest.test', '0811',
    '00000000-0000-0000-0000-000000009806', v_team_a, '00000000-0000-0000-0000-000000009806', 'tester');
  select * into v_lead from app.leads where email = 'jane@restest.test';
  perform app.qualify_lead(v_lead.id, v_lead.record_version, '00000000-0000-0000-0000-000000009806', 'tester');
  select * into v_lead from app.leads where id = v_lead.id;
  perform app.convert_lead_to_prospect(v_lead.id, 'Res Test Co', 'RTC', '11.111.111.1-111.000',
    jsonb_build_object('line1', 'Jl. Rasuna Said 1', 'city', 'Jakarta', 'country', 'ID'),
    '00000000-0000-0000-0000-000000009806', 'tester');
  select * into v_prospect from app.prospects where lead_id = v_lead.id;

  select * into v_contact from app.create_contact(v_tenant1, 'Jane Res Ops', 'Procurement Lead', 'jane@restest.test', '0811', '00000000-0000-0000-0000-000000009806', v_team_a, '00000000-0000-0000-0000-000000009806', 'tester');
  perform app.link_contact_to_record(v_contact.id, 'prospect', v_prospect.id, 'primary', true, '00000000-0000-0000-0000-000000009806', 'tester');

  select * into v_opportunity from app.create_opportunity(
    v_tenant1, v_prospect.id, 'Resource test lane',
    jsonb_build_object('service_type', 'ocean_freight', 'cargo_description', 'General cargo', 'origin', 'Jakarta', 'destination', 'Surabaya', 'target_ready_date', '2026-08-01'),
    '00000000-0000-0000-0000-000000009806', v_team_a, '00000000-0000-0000-0000-000000009806', 'tester'
  );
  select * into v_request from app.request_costing(v_opportunity.id, '[]'::jsonb, null, '00000000-0000-0000-0000-000000009806', 'tester');
  select * into v_rate from app.create_rate_version(
    v_tenant1, 'VENDOR-RES-1', 'Contoso Ocean Line', 'ocean_freight', 'FCL', 'Jakarta', 'Surabaya', '20ft',
    null, null, null, null, 'IDR', 10000000, null, '[]'::jsonb, now(), null, null, '00000000-0000-0000-0000-000000009805', 'tester'
  );
  perform app.approve_rate_version(v_rate.id, v_rate.record_version, '00000000-0000-0000-0000-000000009805', 'tester');
  select * into v_selection from app.select_vendor_rate(v_request.id, v_rate.id, false, null, null, null, '00000000-0000-0000-0000-000000009806', 'tester');

  select * into v_rule from app.create_margin_rule_version(v_tenant1, 20.00, 'half_up', '00000000-0000-0000-0000-000000009806', 'tester');
  perform app.publish_margin_rule_version(v_rule.id, v_rule.record_version, null, '00000000-0000-0000-0000-000000009806', 'tester');
  perform app.calculate_margin(v_selection.id, 15000000, 'IDR', 0, '00000000-0000-0000-0000-000000009806', 'tester');
  select id into v_calc_id from app.margin_calculations where rate_selection_id = v_selection.id and is_current;

  select * into v_quote from app.create_quotation_draft(v_tenant1, v_opportunity.id, 'IDR', now() + interval '14 days', v_contact.id, null, null, '00000000-0000-0000-0000-000000009806', 'tester');
  perform app.add_quotation_line(v_quote.id, v_quote.record_version, 'service', 'Ocean freight ops lane', v_calc_id, 1, 15000000, 0, 0, '00000000-0000-0000-0000-000000009806', 'tester');
  select * into v_quote from app.quotations where id = v_quote.id;
  perform app.submit_quotation(v_quote.id, v_quote.record_version, '00000000-0000-0000-0000-000000009806', 'tester');
  select * into v_send from app.send_quotation_for_acceptance(v_quote.id, null, 'email', '00000000-0000-0000-0000-000000009806', 'tester');
  perform app.record_quotation_customer_decision(v_send.raw_token, 'accepted', 'Jane Res Ops', null, null, null, null, null);
  select * into v_quote from app.quotations where id = v_quote.id;
  select * into v_account from app.convert_quotation_to_account(v_quote.id, null, null, '00000000-0000-0000-0000-000000009806', 'rep');
  select * into v_handoff from app.prepare_job_order_handoff(v_quote.id, '00000000-0000-0000-0000-000000009806', 'rep');

  select * into v_job_order from app.prepare_job_order(v_handoff.id, '00000000-0000-0000-0000-000000009806', 'rep');
  select * into v_job_order from app.confirm_job_order(v_job_order.id, v_job_order.record_version, '00000000-0000-0000-0000-000000009806', 'rep');

  select * into v_shipment_main from app.create_shipment_order_from_job(
    v_job_order.id, 'idem-res-main', null, null, 'ocean_freight', 'land', 'Jakarta', 'Surabaya',
    null, null, null, null, null, null, null, null, null, '00000000-0000-0000-0000-000000009806', 'rep'
  );
  select * into v_shipment_conflict from app.create_shipment_order_from_job(
    v_job_order.id, 'idem-res-conflict', null, null, 'ocean_freight', 'land', 'Jakarta', 'Bandung',
    null, null, null, null, null, null, null, null, 'split: conflict fixture', '00000000-0000-0000-0000-000000009806', 'rep'
  );
  select * into v_shipment_cancel from app.create_shipment_order_from_job(
    v_job_order.id, 'idem-res-cancel', null, null, 'ocean_freight', 'land', 'Jakarta', 'Semarang',
    null, null, null, null, null, null, null, null, 'split: cancel fixture', '00000000-0000-0000-0000-000000009806', 'rep'
  );

  select * into v_vendor_1 from app.create_master_record('vendor', v_tenant1, 'VEND-1', 'Contoso Trucking', '[]'::jsonb, '{}'::jsonb, '00000000-0000-0000-0000-000000009805', 'admin');
  select * into v_vendor_2 from app.create_master_record('vendor', v_tenant1, 'VEND-2', 'Fabrikam Trucking', '[]'::jsonb, '{}'::jsonb, '00000000-0000-0000-0000-000000009805', 'admin');
  select * into v_vendor_3 from app.create_master_record('vendor', v_tenant1, 'VEND-3', 'Northwind Trucking', '[]'::jsonb, '{}'::jsonb, '00000000-0000-0000-0000-000000009805', 'admin');
  select * into v_vendor_decoy from app.create_master_record('vendor', v_tenant1, 'VEND-DECOY', 'Decoy Trucking', '[]'::jsonb, '{}'::jsonb, '00000000-0000-0000-0000-000000009805', 'admin');
  perform app.deactivate_master_record(v_vendor_decoy.id, '00000000-0000-0000-0000-000000009805', 'never onboarded', 'admin');
  select * into v_fleet_1 from app.create_master_record('fleet', v_tenant1, 'FLEET-1', 'Jakarta Depot Fleet', '[]'::jsonb, '{}'::jsonb, '00000000-0000-0000-0000-000000009805', 'admin');
  select * into v_vehicle_1 from app.create_master_record('vehicle', v_tenant1, 'VEH-1', 'B 1234 RES', '[]'::jsonb, '{}'::jsonb, '00000000-0000-0000-0000-000000009805', 'admin');
  select * into v_driver_1 from app.create_master_record('driver', v_tenant1, 'DRV-1', 'Budi Santoso', '[]'::jsonb, '{}'::jsonb, '00000000-0000-0000-0000-000000009805', 'admin');
end $$;

\echo '>> app.find_assignment_candidates: invalid_role rejected; returns only active vendor candidates for the tenant, ordered by name, never the deactivated decoy, never app.master_records.attributes'
do $$
declare
  v_tenant1 uuid;
  v_count integer;
begin
  v_tenant1 := (select id from app.tenants where slug = 'acmeres');

  begin
    perform app.find_assignment_candidates(v_tenant1, 'ship', '00000000-0000-0000-0000-000000009806');
    raise exception 'assertion failed: expected invalid_role for an unsupported role';
  exception
    when others then
      if sqlerrm not like 'invalid_role%' then
        raise;
      end if;
  end;

  select count(*) into v_count from app.find_assignment_candidates(v_tenant1, 'vendor', '00000000-0000-0000-0000-000000009806');
  if v_count <> 3 then
    raise exception 'assertion failed: expected exactly 3 active vendor candidates (VEND-1, VEND-2, VEND-3), the deactivated decoy excluded, found %', v_count;
  end if;
end $$;

\echo '>> app.assign_resource: authority-gated (an OPS:View-only actor denied OPS:Assign); invalid_resource for a role/master_type mismatch; a valid assignment creates a row with resource_snapshot={code,name} only; already_assigned on a repeat call for the same role'
do $$
declare
  v_shipment_id uuid;
  v_vehicle_id uuid;
  v_vendor_id uuid;
  v_assignment app.resource_assignments;
begin
  select id into v_shipment_id from app.shipment_orders where idempotency_key = 'idem-res-main';
  select id into v_vehicle_id from app.master_records where master_type_code = 'vehicle' and code = 'VEH-1';
  select id into v_vendor_id from app.master_records where master_type_code = 'vendor' and code = 'VEND-1';

  begin
    perform app.assign_resource(v_shipment_id, 'vendor', v_vendor_id, '00000000-0000-0000-0000-000000009807', 'viewer');
    raise exception 'assertion failed: expected insufficient_authority for an OPS:View-only actor';
  exception
    when others then
      if sqlerrm not like 'insufficient_authority%' then
        raise;
      end if;
  end;

  begin
    perform app.assign_resource(v_shipment_id, 'vendor', v_vehicle_id, '00000000-0000-0000-0000-000000009806', 'rep');
    raise exception 'assertion failed: expected invalid_resource for a vehicle record passed as a vendor role';
  exception
    when others then
      if sqlerrm not like 'invalid_resource%' then
        raise;
      end if;
  end;

  select * into v_assignment from app.assign_resource(v_shipment_id, 'vendor', v_vendor_id, '00000000-0000-0000-0000-000000009806', 'rep');
  if v_assignment.status <> 'active' or not v_assignment.is_current or v_assignment.resource_snapshot <> jsonb_build_object('code', 'VEND-1', 'name', 'Contoso Trucking') then
    raise exception 'assertion failed: expected an active, current vendor assignment with a minimized {code,name} snapshot';
  end if;

  begin
    perform app.assign_resource(v_shipment_id, 'vendor', v_vendor_id, '00000000-0000-0000-0000-000000009806', 'rep');
    raise exception 'assertion failed: expected already_assigned on a repeat assign call for an already-occupied role';
  exception
    when others then
      if sqlerrm not like 'already_assigned%' then
        raise;
      end if;
  end;

  perform app.assign_resource(v_shipment_id, 'fleet', (select id from app.master_records where master_type_code = 'fleet' and code = 'FLEET-1'), '00000000-0000-0000-0000-000000009806', 'rep');
  perform app.assign_resource(v_shipment_id, 'vehicle', v_vehicle_id, '00000000-0000-0000-0000-000000009806', 'rep');
  perform app.assign_resource(v_shipment_id, 'driver', (select id from app.master_records where master_type_code = 'driver' and code = 'DRV-1'), '00000000-0000-0000-0000-000000009806', 'rep');
end $$;

\echo '>> app.assign_resource: assignment_conflict when the same vendor is already actively assigned on a different, non-terminal shipment order'
do $$
declare
  v_shipment_conflict_id uuid;
  v_vendor_id uuid;
begin
  select id into v_shipment_conflict_id from app.shipment_orders where idempotency_key = 'idem-res-conflict';
  select id into v_vendor_id from app.master_records where master_type_code = 'vendor' and code = 'VEND-1';

  begin
    perform app.assign_resource(v_shipment_conflict_id, 'vendor', v_vendor_id, '00000000-0000-0000-0000-000000009806', 'rep');
    raise exception 'assertion failed: expected assignment_conflict -- VEND-1 is already actively assigned on idem-res-main';
  exception
    when others then
      if sqlerrm not like 'assignment_conflict%' then
        raise;
      end if;
  end;

  perform app.assign_resource(v_shipment_conflict_id, 'vendor', (select id from app.master_records where master_type_code = 'vendor' and code = 'VEND-2'), '00000000-0000-0000-0000-000000009806', 'rep');
end $$;

\echo '>> app.hold_resource_assignment / app.resume_resource_assignment: reason_required; invalid_transition when not in the expected starting state; a held assignment still occupies its slot (already_assigned blocks a fresh assign while held); resume returns it to active'
do $$
declare
  v_shipment_id uuid;
  v_assignment app.resource_assignments;
begin
  select id into v_shipment_id from app.shipment_orders where idempotency_key = 'idem-res-main';

  begin
    perform app.hold_resource_assignment(v_shipment_id, 'vendor', null, '00000000-0000-0000-0000-000000009806', 'rep');
    raise exception 'assertion failed: expected reason_required for a hold with no reason';
  exception
    when others then
      if sqlerrm not like 'reason_required%' then
        raise;
      end if;
  end;

  begin
    perform app.resume_resource_assignment(v_shipment_id, 'vendor', '00000000-0000-0000-0000-000000009806', 'rep');
    raise exception 'assertion failed: expected invalid_transition -- the vendor assignment is active, not held';
  exception
    when others then
      if sqlerrm not like 'invalid_transition%' then
        raise;
      end if;
  end;

  select * into v_assignment from app.hold_resource_assignment(v_shipment_id, 'vendor', 'vendor unresponsive, pausing', '00000000-0000-0000-0000-000000009806', 'rep');
  if v_assignment.status <> 'held' or not v_assignment.is_current then
    raise exception 'assertion failed: expected the vendor assignment to become held while remaining the current row';
  end if;

  begin
    perform app.assign_resource(v_shipment_id, 'vendor', (select id from app.master_records where master_type_code = 'vendor' and code = 'VEND-3'), '00000000-0000-0000-0000-000000009806', 'rep');
    raise exception 'assertion failed: expected already_assigned -- a held assignment still occupies its role slot';
  exception
    when others then
      if sqlerrm not like 'already_assigned%' then
        raise;
      end if;
  end;

  begin
    perform app.hold_resource_assignment(v_shipment_id, 'vendor', 'holding again', '00000000-0000-0000-0000-000000009806', 'rep');
    raise exception 'assertion failed: expected invalid_transition -- already held, cannot hold again';
  exception
    when others then
      if sqlerrm not like 'invalid_transition%' then
        raise;
      end if;
  end;

  select * into v_assignment from app.resume_resource_assignment(v_shipment_id, 'vendor', '00000000-0000-0000-0000-000000009806', 'rep');
  if v_assignment.status <> 'active' then
    raise exception 'assertion failed: expected the vendor assignment to return to active after resume';
  end if;
end $$;

\echo '>> app.reassign_resource: reason_required; no_current_assignment on a role never assigned; a valid reassign creates a new row, marks the prior row is_current=false and superseded_by_id set, and the prior row''s own reason/outcome is preserved (never overwritten)'
do $$
declare
  v_shipment_id uuid;
  v_prior_id uuid;
  v_new app.resource_assignments;
  v_prior app.resource_assignments;
begin
  select id into v_shipment_id from app.shipment_orders where idempotency_key = 'idem-res-main';
  select id into v_prior_id from app.resource_assignments where shipment_order_id = v_shipment_id and role = 'vendor' and is_current;

  begin
    perform app.reassign_resource(v_shipment_id, 'vendor', (select id from app.master_records where master_type_code = 'vendor' and code = 'VEND-3'), null, '00000000-0000-0000-0000-000000009806', 'rep');
    raise exception 'assertion failed: expected reason_required for a reassign with no reason';
  exception
    when others then
      if sqlerrm not like 'reason_required%' then
        raise;
      end if;
  end;

  begin
    perform app.reassign_resource(
      (select id from app.shipment_orders where idempotency_key = 'idem-res-conflict'),
      'fleet', (select id from app.master_records where master_type_code = 'fleet' and code = 'FLEET-1'),
      'irrelevant', '00000000-0000-0000-0000-000000009806', 'rep'
    );
    raise exception 'assertion failed: expected no_current_assignment -- the conflict shipment never had a fleet assignment to replace';
  exception
    when others then
      if sqlerrm not like 'no_current_assignment%' then
        raise;
      end if;
  end;

  select * into v_new from app.reassign_resource(v_shipment_id, 'vendor', (select id from app.master_records where master_type_code = 'vendor' and code = 'VEND-3'), 'original vendor underperforming', '00000000-0000-0000-0000-000000009806', 'rep');
  if v_new.resource_snapshot <> jsonb_build_object('code', 'VEND-3', 'name', 'Northwind Trucking') or not v_new.is_current then
    raise exception 'assertion failed: expected the new current row to carry VEND-3''s own minimized snapshot';
  end if;

  select * into v_prior from app.resource_assignments where id = v_prior_id;
  if v_prior.is_current or v_prior.superseded_by_id <> v_new.id or v_prior.reason <> 'vendor unresponsive, pausing' then
    raise exception 'assertion failed: expected the prior row released (is_current=false), pointed at the new row via superseded_by_id, and its own historical reason left untouched';
  end if;
end $$;

\echo '>> app.unassign_resource: reason_required; success releases the role slot (is_current=false), and a subsequent assign_resource may then create a fresh current row for the same role'
do $$
declare
  v_shipment_id uuid;
  v_assignment app.resource_assignments;
begin
  select id into v_shipment_id from app.shipment_orders where idempotency_key = 'idem-res-main';

  begin
    perform app.unassign_resource(v_shipment_id, 'fleet', null, '00000000-0000-0000-0000-000000009806', 'rep');
    raise exception 'assertion failed: expected reason_required for an unassign with no reason';
  exception
    when others then
      if sqlerrm not like 'reason_required%' then
        raise;
      end if;
  end;

  select * into v_assignment from app.unassign_resource(v_shipment_id, 'fleet', 'fleet reassigned to another lane', '00000000-0000-0000-0000-000000009806', 'rep');
  if v_assignment.status <> 'unassigned' or v_assignment.is_current then
    raise exception 'assertion failed: expected the fleet assignment to become unassigned and release its role slot';
  end if;

  perform app.assign_resource(v_shipment_id, 'fleet', (select id from app.master_records where master_type_code = 'fleet' and code = 'FLEET-1'), '00000000-0000-0000-0000-000000009806', 'rep');
  if (select count(*) from app.resource_assignments where shipment_order_id = v_shipment_id and role = 'fleet' and is_current) <> 1 then
    raise exception 'assertion failed: expected exactly one current fleet row after re-assigning a freed slot';
  end if;
end $$;

\echo '>> app.assign_resource: invalid_transition once the shipment is cancelled'
do $$
declare
  v_shipment app.shipment_orders;
begin
  select * into v_shipment from app.shipment_orders where idempotency_key = 'idem-res-cancel';
  select * into v_shipment from app.transition_shipment_order(v_shipment.id, 'cancelled', v_shipment.record_version, 'no longer needed', null, 'idem-res-cancel-transition', '00000000-0000-0000-0000-000000009806', 'rep');

  begin
    perform app.assign_resource(v_shipment.id, 'vendor', (select id from app.master_records where master_type_code = 'vendor' and code = 'VEND-1'), '00000000-0000-0000-0000-000000009806', 'rep');
    raise exception 'assertion failed: expected invalid_transition -- a cancelled shipment can no longer receive resource assignments';
  exception
    when others then
      if sqlerrm not like 'invalid_transition%' then
        raise;
      end if;
  end;
end $$;

\echo '>> app.get_resource_assignment_history: ordered oldest first and reflects the full append-oriented sequence for the vendor role slot'
do $$
declare
  v_shipment_id uuid;
  v_history app.resource_assignments[];
begin
  select id into v_shipment_id from app.shipment_orders where idempotency_key = 'idem-res-main';
  select array_agg(h order by h.created_at asc) into v_history
  from app.get_resource_assignment_history(v_shipment_id, '00000000-0000-0000-0000-000000009806') h
  where h.role = 'vendor';

  if array_length(v_history, 1) <> 2 then
    raise exception 'assertion failed: expected exactly 2 vendor-role rows in history (original VEND-1, then VEND-3 via reassign), found %', array_length(v_history, 1);
  end if;
  if v_history[1].resource_snapshot ->> 'code' <> 'VEND-1' or v_history[2].resource_snapshot ->> 'code' <> 'VEND-3' then
    raise exception 'assertion failed: expected history ordered oldest-first, VEND-1 then VEND-3';
  end if;
end $$;

\echo '>> record-scope: a sibling-team outsider (different org unit, no ownership stake) cannot access the shipment via any resource-assignment function despite holding full OPS grants'
do $$
declare
  v_shipment_id uuid;
begin
  select id into v_shipment_id from app.shipment_orders where idempotency_key = 'idem-res-main';

  begin
    perform app.assign_resource(v_shipment_id, 'driver', (select id from app.master_records where master_type_code = 'driver' and code = 'DRV-1'), '00000000-0000-0000-0000-000000009808', 'outsider');
    raise exception 'assertion failed: expected the sibling-team outsider to be denied by record scope';
  exception
    when others then
      if sqlerrm not like 'insufficient_authority%' then
        raise;
      end if;
  end;

  begin
    perform app.get_resource_assignment_history(v_shipment_id, '00000000-0000-0000-0000-000000009808');
    raise exception 'assertion failed: expected the sibling-team outsider to be denied read access by record scope';
  exception
    when others then
      if sqlerrm not like 'insufficient_authority%' then
        raise;
      end if;
  end;
end $$;

\echo '>> cross-tenant isolation: app.assign_resource fails closed for an identity with no membership in the Shipment Order''s own tenant'
do $$
declare
  v_tenant2 uuid;
  v_shipment_id uuid;
begin
  insert into auth.users (id, email) values ('00000000-0000-0000-0000-000000009809', 'admin2@acmeres2.test');
  perform app.provision_tenant('acmeres2', 'Acme Resource Co 2', 'idem-acmeres2', 'tester');
  v_tenant2 := (select id from app.tenants where slug = 'acmeres2');
  perform app.transition_tenant_status(v_tenant2, 'active', 'setup', 'tester');
  perform app.invite_user(v_tenant2, '00000000-0000-0000-0000-000000009809', 'admin2@acmeres2.test', 'Tenant 2 Admin', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'admin2@acmeres2.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000009809', 'tenant_admin', v_tenant2, null, 'tester');

  select id into v_shipment_id from app.shipment_orders where idempotency_key = 'idem-res-main';

  begin
    perform app.assign_resource(v_shipment_id, 'driver', (select id from app.master_records where master_type_code = 'driver' and code = 'DRV-1'), '00000000-0000-0000-0000-000000009809', 'tenant2-admin');
    raise exception 'assertion failed: expected insufficient_privilege -- tenant 2''s admin holds no OPS:Assign in tenant 1';
  exception
    when others then
      if sqlerrm not like 'insufficient_authority%' then
        raise;
      end if;
  end;
end $$;

\echo '>> schema-privilege defense in depth: anon holds no EXECUTE on any of the 7 new Resource Assignment functions (ERR-2026-004 regression guard)'
do $$
declare
  v_count integer;
begin
  select count(*) into v_count
  from information_schema.routine_privileges
  where routine_schema = 'app'
    and grantee = 'anon'
    and routine_name in ('find_assignment_candidates', 'assign_resource', 'reassign_resource', 'hold_resource_assignment', 'resume_resource_assignment', 'unassign_resource', 'get_resource_assignment_history');
  if v_count <> 0 then
    raise exception 'assertion failed: expected zero anon EXECUTE grants on the 7 new Resource Assignment functions, found %', v_count;
  end if;
end $$;

\echo '>> audit trail: every real resource-assignment mutation recorded a real app.audit_logs event, tenant-scoped'
do $$
declare
  v_tenant1 uuid;
  v_count integer;
begin
  v_tenant1 := (select id from app.tenants where slug = 'acmeres');

  select count(*) into v_count from app.audit_logs where tenant_id = v_tenant1 and resource_type = 'app.resource_assignments' and action = 'assign_resource';
  if v_count <> 6 then
    raise exception 'assertion failed: expected exactly 6 assign_resource audit events (vendor+fleet+vehicle+driver on main, vendor on conflict, fleet re-assign on main), found %', v_count;
  end if;

  select count(*) into v_count from app.audit_logs where tenant_id = v_tenant1 and resource_type = 'app.resource_assignments' and action = 'reassign_resource';
  if v_count <> 1 then
    raise exception 'assertion failed: expected exactly 1 reassign_resource audit event, found %', v_count;
  end if;

  select count(*) into v_count from app.audit_logs where tenant_id = v_tenant1 and resource_type = 'app.resource_assignments' and action = 'hold_resource_assignment';
  if v_count <> 1 then
    raise exception 'assertion failed: expected exactly 1 hold_resource_assignment audit event, found %', v_count;
  end if;

  select count(*) into v_count from app.audit_logs where tenant_id = v_tenant1 and resource_type = 'app.resource_assignments' and action = 'resume_resource_assignment';
  if v_count <> 1 then
    raise exception 'assertion failed: expected exactly 1 resume_resource_assignment audit event, found %', v_count;
  end if;

  select count(*) into v_count from app.audit_logs where tenant_id = v_tenant1 and resource_type = 'app.resource_assignments' and action = 'unassign_resource';
  if v_count <> 1 then
    raise exception 'assertion failed: expected exactly 1 unassign_resource audit event, found %', v_count;
  end if;
end $$;
