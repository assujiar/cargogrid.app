-- Real, executable test evidence for ATW-224 (CG-S10-ATW-005, Prompt 224 Route and
-- Load Planning Using Canonical Position) -- run via `pnpm run db:test` against a
-- real, disposable Postgres database.

\set ON_ERROR_STOP on

\echo '>> setup: one tenant, a company/team-a/team-b org hierarchy, a rep (OPS:Create/Edit/View), a manager (adds OPS:Override), an OPS-viewer-only actor, a sibling-team outsider, a global Supreme Admin, two active vehicle + two active driver operational profiles, and three confirmed land-freight Shipment Orders via the real Commercial pipeline'
do $$
declare
  v_tenant1 uuid;
  v_team_a uuid;
  v_team_b uuid;
  v_rep_role uuid;
  v_rep_draft app.role_versions;
  v_manager_role uuid;
  v_manager_draft app.role_versions;
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
  v_shipment_feasible app.shipment_orders;
  v_shipment_infeasible app.shipment_orders;
  v_shipment_legs_done app.shipment_orders;
  v_vehicle_a app.vehicle_operational_profiles;
  v_vehicle_b app.vehicle_operational_profiles;
  v_driver_a app.driver_operational_profiles;
  v_driver_b app.driver_operational_profiles;
begin
  insert into auth.users (id, email) values
    ('00000000-0000-0000-0000-000000039301', 'admin@acmeplan.test'),
    ('00000000-0000-0000-0000-000000039302', 'repa@acmeplan.test'),
    ('00000000-0000-0000-0000-000000039303', 'manager@acmeplan.test'),
    ('00000000-0000-0000-0000-000000039304', 'viewer@acmeplan.test'),
    ('00000000-0000-0000-0000-000000039305', 'outsider@acmeplan.test'),
    ('00000000-0000-0000-0000-000000039306', 'supreme@acmeplan.test');

  perform app.grant_principal_membership('00000000-0000-0000-0000-000000039306', 'supreme_admin', null, null, 'tester');

  perform app.provision_tenant('acmeplan', 'Acme Planning Co', 'idem-acmeplan', 'tester');
  v_tenant1 := (select id from app.tenants where slug = 'acmeplan');
  perform app.transition_tenant_status(v_tenant1, 'active', 'setup', 'tester');

  perform app.create_org_unit(v_tenant1, 'company', null, 'ACMEPLAN-CO', 'Acme Planning Co', 'tester');
  perform app.create_org_unit(v_tenant1, 'department', (select id from app.org_units where tenant_id = v_tenant1 and code = 'ACMEPLAN-CO'), 'ACMEPLAN-TEAM-A', 'Team A', 'tester');
  v_team_a := (select id from app.org_units where tenant_id = v_tenant1 and code = 'ACMEPLAN-TEAM-A');
  perform app.create_org_unit(v_tenant1, 'department', (select id from app.org_units where tenant_id = v_tenant1 and code = 'ACMEPLAN-CO'), 'ACMEPLAN-TEAM-B', 'Team B', 'tester');
  v_team_b := (select id from app.org_units where tenant_id = v_tenant1 and code = 'ACMEPLAN-TEAM-B');

  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000039301', 'admin@acmeplan.test', 'Plan Admin', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'admin@acmeplan.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000039301', 'tenant_admin', v_tenant1, null, 'tester');

  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000039302', 'repa@acmeplan.test', 'Rep A', v_team_a, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'repa@acmeplan.test'), 'active', 'onboarded', 'tester');
  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000039303', 'manager@acmeplan.test', 'Ops Manager', v_team_a, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'manager@acmeplan.test'), 'active', 'onboarded', 'tester');
  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000039304', 'viewer@acmeplan.test', 'OPS Viewer', v_team_a, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'viewer@acmeplan.test'), 'active', 'onboarded', 'tester');
  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000039305', 'outsider@acmeplan.test', 'Team B Outsider', v_team_b, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'outsider@acmeplan.test'), 'active', 'onboarded', 'tester');

  -- Rep: OPS Create/Edit/View, no Override -- proves override authority is a genuinely
  -- distinct gate, not implied by Edit.
  v_rep_role := (app.create_role(v_tenant1, 'Plan Rep', 'full commercial + ops create/edit/view', 'tester')).id;
  v_rep_draft := app.create_role_version(v_rep_role, 'tester');
  perform app.set_role_version_permissions(
    v_rep_draft.id,
    array(select id from app.permissions where (resource_module_code = 'COM' and action in ('Create', 'Edit', 'Approve', 'View', 'View cost'))
      or (resource_module_code = 'OPS' and action in ('Create', 'Edit', 'View'))),
    'tester'
  );
  perform app.publish_role_version(v_rep_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_rep_role and status = 'published'), '00000000-0000-0000-0000-000000039302', '00000000-0000-0000-0000-000000039301', 'tester');

  v_manager_role := (app.create_role(v_tenant1, 'Plan Manager', 'OPS create/edit/view/override', 'tester')).id;
  v_manager_draft := app.create_role_version(v_manager_role, 'tester');
  perform app.set_role_version_permissions(v_manager_draft.id, array(select id from app.permissions where resource_module_code = 'OPS' and action in ('Create', 'Edit', 'View', 'Override')), 'tester');
  perform app.publish_role_version(v_manager_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_manager_role and status = 'published'), '00000000-0000-0000-0000-000000039303', '00000000-0000-0000-0000-000000039301', 'tester');

  -- register_vehicle_operational_profile/register_driver_operational_profile call
  -- app.create_master_record internally, which is hard-gated to tenant_admin/Supreme
  -- Admin regardless of OPS role (ATW-223's own disclosed precondition) -- but they
  -- also separately require OPS:Create. The tenant_admin fixture user has no OPS
  -- role by default, so grant it the manager role here (via Supreme Admin, avoiding
  -- self-assignment), mirroring ATW-223's own db-test fixture fix.
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_manager_role and status = 'published'), '00000000-0000-0000-0000-000000039301', '00000000-0000-0000-0000-000000039306', 'tester');

  v_viewer_role := (app.create_role(v_tenant1, 'Plan Ops Viewer', 'OPS:View only, no Create/Edit', 'tester')).id;
  v_viewer_draft := app.create_role_version(v_viewer_role, 'tester');
  perform app.set_role_version_permissions(v_viewer_draft.id, array(select id from app.permissions where resource_module_code = 'OPS' and action in ('View')), 'tester');
  perform app.publish_role_version(v_viewer_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_viewer_role and status = 'published'), '00000000-0000-0000-0000-000000039304', '00000000-0000-0000-0000-000000039304', 'tester');

  v_outsider_role := (app.create_role(v_tenant1, 'Plan Outsider', 'sibling team, full grants', 'tester')).id;
  v_outsider_draft := app.create_role_version(v_outsider_role, 'tester');
  perform app.set_role_version_permissions(
    v_outsider_draft.id,
    array(select id from app.permissions where (resource_module_code = 'COM' and action in ('Create', 'Edit', 'View'))
      or (resource_module_code = 'OPS' and action in ('Create', 'Edit', 'View'))),
    'tester'
  );
  perform app.publish_role_version(v_outsider_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_outsider_role and status = 'published'), '00000000-0000-0000-0000-000000039305', '00000000-0000-0000-0000-000000039301', 'tester');

  -- Fleet: two active vehicles (tight vs. loose capacity fit) and two active drivers.
  -- register_vehicle_operational_profile/register_driver_operational_profile call
  -- app.create_master_record internally, hard-gated to tenant_admin/Supreme Admin
  -- (ATW-223's own disclosed precondition) -- registered as the tenant_admin.
  select * into v_vehicle_a from app.register_vehicle_operational_profile(v_tenant1, 'VEH-PLAN-A', 'Plan Truck A (tight fit)', 'owned', 1000, 20, '00000000-0000-0000-0000-000000039301', 'admin');
  select * into v_vehicle_b from app.register_vehicle_operational_profile(v_tenant1, 'VEH-PLAN-B', 'Plan Truck B (loose fit)', 'owned', 5000, 60, '00000000-0000-0000-0000-000000039301', 'admin');
  select * into v_driver_a from app.register_driver_operational_profile(v_tenant1, 'DRV-PLAN-A', 'Driver A', 'B2', (now() + interval '2 years')::date, '00000000-0000-0000-0000-000000039301', 'admin');
  select * into v_driver_b from app.register_driver_operational_profile(v_tenant1, 'DRV-PLAN-B', 'Driver B', 'B2', (now() + interval '2 years')::date, '00000000-0000-0000-0000-000000039301', 'admin');

  perform app.capture_lead(v_tenant1, 'manual', null, 'Plan Test Co', 'Jane Plan', 'jane@plantest.test', '0811',
    '00000000-0000-0000-0000-000000039302', v_team_a, '00000000-0000-0000-0000-000000039302', 'tester');
  select * into v_lead from app.leads where email = 'jane@plantest.test';
  perform app.qualify_lead(v_lead.id, v_lead.record_version, '00000000-0000-0000-0000-000000039302', 'tester');
  select * into v_lead from app.leads where id = v_lead.id;
  perform app.convert_lead_to_prospect(v_lead.id, 'Plan Test Co', 'PTC', '11.111.111.3-111.000',
    jsonb_build_object('line1', 'Jl. Rasuna Said 3', 'city', 'Jakarta', 'country', 'ID'),
    '00000000-0000-0000-0000-000000039302', 'tester');
  select * into v_prospect from app.prospects where lead_id = v_lead.id;

  select * into v_contact from app.create_contact(v_tenant1, 'Jane Plan Ops', 'Procurement Lead', 'jane@plantest.test', '0811', '00000000-0000-0000-0000-000000039302', v_team_a, '00000000-0000-0000-0000-000000039302', 'tester');
  perform app.link_contact_to_record(v_contact.id, 'prospect', v_prospect.id, 'primary', true, '00000000-0000-0000-0000-000000039302', 'tester');

  select * into v_opportunity from app.create_opportunity(
    v_tenant1, v_prospect.id, 'Planning test lane',
    jsonb_build_object('service_type', 'land_freight', 'cargo_description', 'General cargo', 'origin', 'Jakarta', 'destination', 'Bandung', 'target_ready_date', '2026-08-01'),
    '00000000-0000-0000-0000-000000039302', v_team_a, '00000000-0000-0000-0000-000000039302', 'tester'
  );
  select * into v_request from app.request_costing(v_opportunity.id, '[]'::jsonb, null, '00000000-0000-0000-0000-000000039302', 'tester');
  select * into v_rate from app.create_rate_version(
    v_tenant1, 'VENDOR-PLAN-1', 'Contoso Plan Line', 'land_freight', 'FTL', 'Jakarta', 'Bandung', '20ft',
    null, null, null, null, 'IDR', 4000000, null, '[]'::jsonb, now(), null, null, '00000000-0000-0000-0000-000000039301', 'tester'
  );
  perform app.approve_rate_version(v_rate.id, v_rate.record_version, '00000000-0000-0000-0000-000000039301', 'tester');
  select * into v_selection from app.select_vendor_rate(v_request.id, v_rate.id, false, null, null, null, '00000000-0000-0000-0000-000000039302', 'tester');

  select * into v_rule from app.create_margin_rule_version(v_tenant1, 20.00, 'half_up', '00000000-0000-0000-0000-000000039302', 'tester');
  perform app.publish_margin_rule_version(v_rule.id, v_rule.record_version, null, '00000000-0000-0000-0000-000000039302', 'tester');
  perform app.calculate_margin(v_selection.id, 4800000, 'IDR', 0, '00000000-0000-0000-0000-000000039302', 'tester');
  select id into v_calc_id from app.margin_calculations where rate_selection_id = v_selection.id and is_current;

  select * into v_quote from app.create_quotation_draft(v_tenant1, v_opportunity.id, 'IDR', now() + interval '14 days', v_contact.id, null, null, '00000000-0000-0000-0000-000000039302', 'tester');
  perform app.add_quotation_line(v_quote.id, v_quote.record_version, 'service', 'Land freight planning lane', v_calc_id, 1, 4800000, 0, 0, '00000000-0000-0000-0000-000000039302', 'tester');
  select * into v_quote from app.quotations where id = v_quote.id;
  perform app.submit_quotation(v_quote.id, v_quote.record_version, '00000000-0000-0000-0000-000000039302', 'tester');
  select * into v_send from app.send_quotation_for_acceptance(v_quote.id, null, 'email', '00000000-0000-0000-0000-000000039302', 'tester');
  perform app.record_quotation_customer_decision(v_send.raw_token, 'accepted', 'Jane Plan Ops', null, null, null, null, null);
  select * into v_quote from app.quotations where id = v_quote.id;
  select * into v_account from app.convert_quotation_to_account(v_quote.id, null, null, '00000000-0000-0000-0000-000000039302', 'rep');
  select * into v_handoff from app.prepare_job_order_handoff(v_quote.id, '00000000-0000-0000-0000-000000039302', 'rep');

  select * into v_job_order from app.prepare_job_order(v_handoff.id, '00000000-0000-0000-0000-000000039302', 'rep');
  select * into v_job_order from app.confirm_job_order(v_job_order.id, v_job_order.record_version, '00000000-0000-0000-0000-000000039302', 'rep');

  select * into v_shipment_feasible from app.create_shipment_order_from_job(
    v_job_order.id, 'idem-plan-feasible', null, null, 'land_freight', 'land', 'Jakarta', 'Bandung',
    now() + interval '1 day', now() + interval '2 days', 800, 800, 10, 800, 800, 10, null, '00000000-0000-0000-0000-000000039302', 'rep'
  );
  select * into v_shipment_feasible from app.confirm_shipment_order(v_shipment_feasible.id, v_shipment_feasible.record_version, '00000000-0000-0000-0000-000000039302', 'rep');

  -- No allocation basis on this second Shipment Order off the same Job Order (null
  -- allocated/basis, mirroring ATW-221's own legacy-fixture precedent) -- the job
  -- order's own remaining allocation was already fully consumed by the feasible
  -- shipment above, and this fixture only needs the scenario's own
  -- requested_weight_kg (set independently below) to drive the infeasible-candidate
  -- test.
  select * into v_shipment_infeasible from app.create_shipment_order_from_job(
    v_job_order.id, 'idem-plan-infeasible', null, null, 'land_freight', 'land', 'Jakarta', 'Bandung',
    now() + interval '1 day', now() + interval '2 days', null, null, null, null, null, null, 'split: infeasible fixture', '00000000-0000-0000-0000-000000039302', 'rep'
  );
  select * into v_shipment_infeasible from app.confirm_shipment_order(v_shipment_infeasible.id, v_shipment_infeasible.record_version, '00000000-0000-0000-0000-000000039302', 'rep');

  select * into v_shipment_legs_done from app.create_shipment_order_from_job(
    v_job_order.id, 'idem-plan-legs-done', null, null, 'land_freight', 'land', 'Jakarta', 'Bogor',
    now() + interval '1 day', now() + interval '2 days', null, null, null, null, null, null, 'split: legs-done fixture', '00000000-0000-0000-0000-000000039302', 'rep'
  );
  select * into v_shipment_legs_done from app.confirm_shipment_order(v_shipment_legs_done.id, v_shipment_legs_done.record_version, '00000000-0000-0000-0000-000000039302', 'rep');
end $$;

\echo '>> app.prepare_route_planning_scenario: authority-gated, idempotent on (tenant_id, shipment_order_id, idempotency_key)'
do $$
declare
  v_shipment_id uuid;
  v_scenario app.route_planning_scenarios;
  v_retry app.route_planning_scenarios;
begin
  select id into v_shipment_id from app.shipment_orders where idempotency_key = 'idem-plan-feasible';

  begin
    perform app.prepare_route_planning_scenario(v_shipment_id, 'idem-scenario-denied', 800, 10, '00000000-0000-0000-0000-000000039304', 'viewer');
    raise exception 'assertion failed: expected insufficient_authority for an OPS:View-only actor';
  exception
    when others then
      if sqlerrm not like 'insufficient_authority%' then raise; end if;
  end;

  select * into v_scenario from app.prepare_route_planning_scenario(v_shipment_id, 'idem-scenario-feasible', 800, 10, '00000000-0000-0000-0000-000000039302', 'rep');
  if v_scenario.status <> 'draft' then
    raise exception 'assertion failed: expected a fresh scenario in draft status';
  end if;

  select * into v_retry from app.prepare_route_planning_scenario(v_shipment_id, 'idem-scenario-feasible', 800, 10, '00000000-0000-0000-0000-000000039302', 'rep');
  if v_retry.id <> v_scenario.id then
    raise exception 'assertion failed: expected the idempotent repeated call to return the exact same scenario row';
  end if;
end $$;

\echo '>> app.add_route_planning_stop / app.add_route_planning_constraint: only while draft, structural value-shape validation, geog built from longitude/latitude'
do $$
declare
  v_scenario_id uuid;
  v_stop1 app.route_planning_stops;
  v_stop2 app.route_planning_stops;
  v_stops jsonb;
begin
  select id into v_scenario_id from app.route_planning_scenarios where idempotency_key = 'idem-scenario-feasible';

  select * into v_stop1 from app.add_route_planning_stop(v_scenario_id, 1, 'pickup', 'Jakarta Warehouse', 'Jl. Rasuna Said 1', 106.8456, -6.2088, now() + interval '1 day', now() + interval '1 day 2 hours', '00000000-0000-0000-0000-000000039302', 'rep');
  if v_stop1.location_geog is null then
    raise exception 'assertion failed: expected a real geography point built from the supplied longitude/latitude';
  end if;
  select * into v_stop2 from app.add_route_planning_stop(v_scenario_id, 2, 'delivery', 'Bandung Warehouse', null, 107.6098, -6.9175, now() + interval '2 days', null, '00000000-0000-0000-0000-000000039302', 'rep');

  select jsonb_agg(location_geojson) into v_stops from app.get_route_planning_stops(v_scenario_id);
  if v_stops is null or jsonb_array_length(v_stops) <> 2 then
    raise exception 'assertion failed: expected app.get_route_planning_stops to project 2 GeoJSON stops';
  end if;

  perform app.add_route_planning_constraint(v_scenario_id, 'hard', 'max_weight_kg', jsonb_build_object('value', 900), '00000000-0000-0000-0000-000000039302', 'rep');

  begin
    perform app.add_route_planning_constraint(v_scenario_id, 'hard', 'max_weight_kg', jsonb_build_object('value', -5), '00000000-0000-0000-0000-000000039302', 'rep');
    raise exception 'assertion failed: expected invalid_constraint_value for a non-positive max_weight_kg';
  exception
    when others then
      if sqlerrm not like 'invalid_constraint_value%' then raise; end if;
  end;

  -- Upsert on constraint_key: the malformed attempt above never wrote a row, so the
  -- valid 900 value from earlier must still be current.
  if (select (constraint_value ->> 'value')::numeric from app.route_planning_constraints where scenario_id = v_scenario_id and constraint_key = 'max_weight_kg') <> 900 then
    raise exception 'assertion failed: expected max_weight_kg to remain 900 after the rejected update attempt';
  end if;

  begin
    perform app.add_route_planning_stop(v_scenario_id, 3, 'delivery', 'Should Fail', null, null, null, null, null, '00000000-0000-0000-0000-000000039305', 'outsider');
    raise exception 'assertion failed: expected insufficient_authority -- outsider has no access to team A''s own shipment record';
  exception
    when others then
      if sqlerrm not like 'insufficient_authority%' then raise; end if;
  end;
end $$;

\echo '>> app.validate_route_planning_scenario: rejects <2 stops and a sequence gap; captures the canonical-position snapshot (honestly not_tracked/unusable -- ATW-226F has not shipped)'
do $$
declare
  v_shipment_id uuid;
  v_bare app.route_planning_scenarios;
  v_scenario app.route_planning_scenarios;
begin
  select id into v_shipment_id from app.shipment_orders where idempotency_key = 'idem-plan-legs-done';
  select * into v_bare from app.prepare_route_planning_scenario(v_shipment_id, 'idem-scenario-legs-done', 10, 4, '00000000-0000-0000-0000-000000039302', 'rep');

  begin
    perform app.validate_route_planning_scenario(v_bare.id, v_bare.record_version, '00000000-0000-0000-0000-000000039302', 'rep');
    raise exception 'assertion failed: expected stops_insufficient for a scenario with zero stops';
  exception
    when others then
      if sqlerrm not like 'stops_insufficient%' then raise; end if;
  end;

  perform app.add_route_planning_stop(v_bare.id, 1, 'pickup', 'Jakarta Warehouse', null, null, null, null, null, '00000000-0000-0000-0000-000000039302', 'rep');
  perform app.add_route_planning_stop(v_bare.id, 3, 'delivery', 'Bogor Warehouse', null, null, null, null, null, '00000000-0000-0000-0000-000000039302', 'rep');

  begin
    perform app.validate_route_planning_scenario(v_bare.id, v_bare.record_version, '00000000-0000-0000-0000-000000039302', 'rep');
    raise exception 'assertion failed: expected stop_sequence_gap for stop_sequence 1,3 (missing 2)';
  exception
    when others then
      if sqlerrm not like 'stop_sequence_gap%' then raise; end if;
  end;

  select * into v_scenario from app.route_planning_scenarios where idempotency_key = 'idem-scenario-feasible';
  select * into v_scenario from app.validate_route_planning_scenario(v_scenario.id, v_scenario.record_version, '00000000-0000-0000-0000-000000039302', 'rep');
  if v_scenario.status <> 'validated' then
    raise exception 'assertion failed: expected scenario status validated';
  end if;
  if v_scenario.canonical_position_snapshot ->> 'tracking_status' <> 'not_tracked' or (v_scenario.canonical_position_snapshot ->> 'is_usable')::boolean is distinct from false then
    raise exception 'assertion failed: expected an honest not_tracked/unusable canonical-position snapshot (no ATW-226F writer exists yet), got %', v_scenario.canonical_position_snapshot;
  end if;
end $$;

\echo '>> app.validate_route_planning_scenario: required_vehicle_master_id/required_driver_master_id hard constraints must resolve to an active operational profile'
do $$
declare
  v_shipment_id uuid;
  v_scenario app.route_planning_scenarios;
begin
  select id into v_shipment_id from app.shipment_orders where idempotency_key = 'idem-plan-infeasible';
  select * into v_scenario from app.prepare_route_planning_scenario(v_shipment_id, 'idem-scenario-infeasible', 50000, 10, '00000000-0000-0000-0000-000000039302', 'rep');
  perform app.add_route_planning_stop(v_scenario.id, 1, 'pickup', 'Jakarta Warehouse', null, 106.8456, -6.2088, null, null, '00000000-0000-0000-0000-000000039302', 'rep');
  perform app.add_route_planning_stop(v_scenario.id, 2, 'delivery', 'Bandung Warehouse', null, 107.6098, -6.9175, null, null, '00000000-0000-0000-0000-000000039302', 'rep');
  perform app.add_route_planning_constraint(v_scenario.id, 'hard', 'required_vehicle_master_id', jsonb_build_object('master_id', gen_random_uuid()::text), '00000000-0000-0000-0000-000000039302', 'rep');

  begin
    perform app.validate_route_planning_scenario(v_scenario.id, v_scenario.record_version, '00000000-0000-0000-0000-000000039302', 'rep');
    raise exception 'assertion failed: expected required_vehicle_not_found for an unknown vehicle_master_id';
  exception
    when others then
      if sqlerrm not like 'required_vehicle_not_found%' then raise; end if;
  end;
end $$;

\echo '>> app.execute_route_planning_scenario / app.run_next_route_planning_job: enqueues + runs the deterministic baseline planner; best-capacity-fit ranking; exactly one infeasible placeholder when nothing qualifies'
do $$
declare
  v_scenario app.route_planning_scenarios;
  v_infeasible_scenario app.route_planning_scenarios;
  v_top app.route_planning_candidate_plans;
  v_feasible_count integer;
  v_vehicle_a_id uuid;
  v_ran app.route_planning_scenarios;
  v_none app.route_planning_scenarios;
begin
  select vop.vehicle_master_id into v_vehicle_a_id
    from app.vehicle_operational_profiles vop
    join app.master_records mr on mr.id = vop.vehicle_master_id
    where vop.tenant_id = (select id from app.tenants where slug = 'acmeplan') and mr.code = 'VEH-PLAN-A';

  select * into v_scenario from app.route_planning_scenarios where idempotency_key = 'idem-scenario-feasible';
  select * into v_scenario from app.execute_route_planning_scenario(v_scenario.id, v_scenario.record_version, 'idem-plan-job-feasible', '00000000-0000-0000-0000-000000039302', 'rep');
  if v_scenario.status <> 'executing' or v_scenario.job_id is null then
    raise exception 'assertion failed: expected scenario executing with a real job_id';
  end if;

  -- Bring the second (infeasible) scenario through validate + execute too, so both
  -- jobs are queued when the worker runs.
  select * into v_infeasible_scenario from app.route_planning_scenarios where idempotency_key = 'idem-scenario-infeasible';
  delete from app.route_planning_constraints where scenario_id = v_infeasible_scenario.id and constraint_key = 'required_vehicle_master_id';
  select * into v_infeasible_scenario from app.validate_route_planning_scenario(v_infeasible_scenario.id, v_infeasible_scenario.record_version, '00000000-0000-0000-0000-000000039302', 'rep');
  select * into v_infeasible_scenario from app.execute_route_planning_scenario(v_infeasible_scenario.id, v_infeasible_scenario.record_version, 'idem-plan-job-infeasible', '00000000-0000-0000-0000-000000039302', 'rep');

  select * into v_ran from app.run_next_route_planning_job('worker-1');
  if v_ran is null then
    raise exception 'assertion failed: expected the worker to claim and run a job';
  end if;
  select * into v_ran from app.run_next_route_planning_job('worker-1');
  if v_ran is null then
    raise exception 'assertion failed: expected the worker to claim and run the second job too';
  end if;

  select * into v_ran from app.run_next_route_planning_job('worker-1');
  if v_ran is not null then
    raise exception 'assertion failed: expected app.run_next_route_planning_job to return null once no route_load_planning job remains due';
  end if;

  select * into v_scenario from app.route_planning_scenarios where idempotency_key = 'idem-scenario-feasible';
  if v_scenario.status <> 'ready' then
    raise exception 'assertion failed: expected the feasible scenario status ready after the worker ran, got %', v_scenario.status;
  end if;

  select count(*) into v_feasible_count from app.route_planning_candidate_plans where scenario_id = v_scenario.id and feasible;
  if v_feasible_count <> 2 then
    raise exception 'assertion failed: expected exactly 2 feasible candidates (both registered vehicles qualify for 800kg/10cbm), found %', v_feasible_count;
  end if;

  select * into v_top from app.route_planning_candidate_plans where scenario_id = v_scenario.id and plan_rank = 1;
  if v_top.vehicle_master_id <> v_vehicle_a_id then
    raise exception 'assertion failed: expected plan_rank 1 to be the tighter-capacity-fit vehicle (VEH-PLAN-A)';
  end if;
  if v_top.total_distance_km is null or v_top.total_distance_km <= 0 or v_top.total_distance_km > 300 then
    raise exception 'assertion failed: expected a real, bounded Jakarta-Bandung geodesic distance, got %', v_top.total_distance_km;
  end if;
  if (select count(*) from app.route_planning_score_components where candidate_plan_id = v_top.id) <> 3 then
    raise exception 'assertion failed: expected 3 score components (distance/duration/utilization) on the top candidate';
  end if;

  select * into v_infeasible_scenario from app.route_planning_scenarios where idempotency_key = 'idem-scenario-infeasible';
  if v_infeasible_scenario.status <> 'ready' then
    raise exception 'assertion failed: expected the infeasible scenario status ready (candidates generated, all infeasible)';
  end if;
  if (select count(*) from app.route_planning_candidate_plans where scenario_id = v_infeasible_scenario.id) <> 1 then
    raise exception 'assertion failed: expected exactly one infeasible placeholder candidate';
  end if;
  if (select feasible from app.route_planning_candidate_plans where scenario_id = v_infeasible_scenario.id) then
    raise exception 'assertion failed: expected the one placeholder candidate to be infeasible (no vehicle can carry 50000kg)';
  end if;
  if not ((select infeasibility_reasons from app.route_planning_candidate_plans where scenario_id = v_infeasible_scenario.id) @> '["no_eligible_vehicle"]'::jsonb) then
    raise exception 'assertion failed: expected no_eligible_vehicle among the infeasibility_reasons';
  end if;
end $$;

\echo '>> app.select_route_planning_plan: rejects an infeasible candidate; succeeds on a feasible one; re-selecting supersedes the prior selection'
do $$
declare
  v_scenario app.route_planning_scenarios;
  v_infeasible_scenario app.route_planning_scenarios;
  v_infeasible_candidate uuid;
  v_second_best uuid;
  v_first_selection app.route_planning_selected_plans;
  v_second_selection app.route_planning_selected_plans;
begin
  select * into v_infeasible_scenario from app.route_planning_scenarios where idempotency_key = 'idem-scenario-infeasible';
  select id into v_infeasible_candidate from app.route_planning_candidate_plans where scenario_id = v_infeasible_scenario.id;

  begin
    perform app.select_route_planning_plan(v_infeasible_scenario.id, v_infeasible_candidate, v_infeasible_scenario.record_version, '00000000-0000-0000-0000-000000039302', 'rep');
    raise exception 'assertion failed: expected candidate_infeasible -- app.override_route_planning_selection is required for an infeasible candidate';
  exception
    when others then
      if sqlerrm not like 'candidate_infeasible%' then raise; end if;
  end;

  select * into v_scenario from app.route_planning_scenarios where idempotency_key = 'idem-scenario-feasible';
  select id into v_second_best from app.route_planning_candidate_plans where scenario_id = v_scenario.id and plan_rank = 2;

  select * into v_first_selection from app.select_route_planning_plan(v_scenario.id, v_second_best, v_scenario.record_version, '00000000-0000-0000-0000-000000039302', 'rep');
  if not v_first_selection.is_current or v_first_selection.is_override then
    raise exception 'assertion failed: expected a fresh, non-override, is_current selection';
  end if;

  select * into v_scenario from app.route_planning_scenarios where id = v_scenario.id;
  if v_scenario.status <> 'selected' then
    raise exception 'assertion failed: expected scenario status selected';
  end if;

  select * into v_second_selection from app.select_route_planning_plan(
    v_scenario.id, (select id from app.route_planning_candidate_plans where scenario_id = v_scenario.id and plan_rank = 1),
    v_scenario.record_version, '00000000-0000-0000-0000-000000039302', 'rep'
  );

  select * into v_first_selection from app.route_planning_selected_plans where id = v_first_selection.id;
  if v_first_selection.is_current or v_first_selection.superseded_by_id <> v_second_selection.id then
    raise exception 'assertion failed: expected the prior selection superseded, never overwritten in place';
  end if;
  if (select count(*) from app.route_planning_selected_plans where scenario_id = v_scenario.id and is_current) <> 1 then
    raise exception 'assertion failed: expected exactly one is_current selection per scenario (partial unique index)';
  end if;
end $$;

\echo '>> app.override_route_planning_selection: requires OPS:Override (denied for a Create/Edit-only rep), requires a non-empty reason, allows selecting an infeasible candidate once granted'
do $$
declare
  v_tenant1 uuid;
  v_infeasible_scenario app.route_planning_scenarios;
  v_infeasible_candidate uuid;
  v_selection app.route_planning_selected_plans;
begin
  v_tenant1 := (select id from app.tenants where slug = 'acmeplan');
  select * into v_infeasible_scenario from app.route_planning_scenarios where idempotency_key = 'idem-scenario-infeasible';
  select id into v_infeasible_candidate from app.route_planning_candidate_plans where scenario_id = v_infeasible_scenario.id;

  begin
    perform app.override_route_planning_selection(v_infeasible_scenario.id, v_infeasible_candidate, 'manual override: use rented truck outside registered fleet', v_infeasible_scenario.record_version, '00000000-0000-0000-0000-000000039302', 'rep');
    raise exception 'assertion failed: expected insufficient_authority -- rep holds OPS:Create/Edit/View but not OPS:Override';
  exception
    when others then
      if sqlerrm not like 'insufficient_authority%' then raise; end if;
  end;

  begin
    perform app.override_route_planning_selection(v_infeasible_scenario.id, v_infeasible_candidate, '', v_infeasible_scenario.record_version, '00000000-0000-0000-0000-000000039302', 'rep');
    raise exception 'assertion failed: expected override_reason_required for an empty reason (the reason check runs before the authority check)';
  exception
    when others then
      if sqlerrm not like 'override_reason_required%' then raise; end if;
  end;

  -- Widen rep's own grants with the manager role's OPS:Override permission (roles are
  -- additive per identity) -- proves Override is the genuine deciding factor, on the
  -- exact same identity that already owns this shipment (app.shipment_orders carries
  -- no org_unit_id; record-scope is owner-only), rather than swapping in a different
  -- identity that would also have to separately prove record ownership.
  perform app.assign_role(v_tenant1, (select rv.id from app.role_versions rv join app.roles r on r.id = rv.role_id where r.name = 'Plan Manager' and rv.status = 'published'), '00000000-0000-0000-0000-000000039302', '00000000-0000-0000-0000-000000039306', 'tester');

  select * into v_selection from app.override_route_planning_selection(
    v_infeasible_scenario.id, v_infeasible_candidate, 'manual override: use rented truck outside registered fleet',
    v_infeasible_scenario.record_version, '00000000-0000-0000-0000-000000039302', 'rep'
  );
  if not v_selection.is_override or v_selection.override_reason is null then
    raise exception 'assertion failed: expected an is_override selection carrying its own override_reason';
  end if;

  select * into v_infeasible_scenario from app.route_planning_scenarios where id = v_infeasible_scenario.id;
  if v_infeasible_scenario.status <> 'selected' then
    raise exception 'assertion failed: expected the infeasible scenario status selected after override';
  end if;
end $$;

\echo '>> app.cancel_route_planning_scenario: allowed before selection, blocked once selected; app.replan_route_planning_scenario copies stops/constraints into a fresh draft scenario and requires a non-empty reason'
do $$
declare
  v_shipment_id uuid;
  v_scenario app.route_planning_scenarios;
  v_cancelled app.route_planning_scenarios;
  v_replanned app.route_planning_scenarios;
  v_stop_count integer;
begin
  select id into v_shipment_id from app.shipment_orders where idempotency_key = 'idem-plan-feasible';
  select * into v_scenario from app.prepare_route_planning_scenario(v_shipment_id, 'idem-scenario-to-cancel', 800, 10, '00000000-0000-0000-0000-000000039302', 'rep');

  select * into v_cancelled from app.cancel_route_planning_scenario(v_scenario.id, v_scenario.record_version, 'test: no longer needed', '00000000-0000-0000-0000-000000039302', 'rep');
  if v_cancelled.status <> 'cancelled' then
    raise exception 'assertion failed: expected a draft scenario to cancel cleanly';
  end if;

  begin
    perform app.cancel_route_planning_scenario(v_cancelled.id, v_cancelled.record_version, 'test: double cancel', '00000000-0000-0000-0000-000000039302', 'rep');
    raise exception 'assertion failed: expected scenario_not_mutable -- an already-cancelled scenario cannot cancel again';
  exception
    when others then
      if sqlerrm not like 'scenario_not_mutable%' then raise; end if;
  end;

  select * into v_scenario from app.route_planning_scenarios where idempotency_key = 'idem-scenario-feasible';

  begin
    perform app.cancel_route_planning_scenario(v_scenario.id, v_scenario.record_version, 'test: cannot cancel a selected scenario', '00000000-0000-0000-0000-000000039302', 'rep');
    raise exception 'assertion failed: expected scenario_not_mutable -- a selected scenario cannot be cancelled';
  exception
    when others then
      if sqlerrm not like 'scenario_not_mutable%' then raise; end if;
  end;

  begin
    perform app.replan_route_planning_scenario(v_scenario.id, '', 'idem-replan-bad-reason', '00000000-0000-0000-0000-000000039302', 'rep');
    raise exception 'assertion failed: expected replan_reason_required for an empty reason';
  exception
    when others then
      if sqlerrm not like 'replan_reason_required%' then raise; end if;
  end;

  select * into v_replanned from app.replan_route_planning_scenario(v_scenario.id, 'approved tracking-derived exception: route deviation observed', 'idem-replan-1', '00000000-0000-0000-0000-000000039302', 'rep');
  if v_replanned.status <> 'draft' or v_replanned.shipment_order_id <> v_scenario.shipment_order_id then
    raise exception 'assertion failed: expected a fresh draft scenario on the same shipment order';
  end if;

  select count(*) into v_stop_count from app.route_planning_stops where scenario_id = v_replanned.id;
  if v_stop_count <> 2 then
    raise exception 'assertion failed: expected the replanned scenario to inherit both of the prior scenario''s own stops, found %', v_stop_count;
  end if;
  if (select count(*) from app.route_planning_replan_events where scenario_id = v_replanned.id and previous_scenario_id = v_scenario.id) <> 1 then
    raise exception 'assertion failed: expected exactly one replan_events row linking the new scenario back to the prior one';
  end if;
end $$;

\echo '>> app.replan_route_planning_scenario: nothing_to_replan once every one of the shipment''s own legs has already left planned'
do $$
declare
  v_shipment app.shipment_orders;
  v_scenario app.route_planning_scenarios;
  v_leg app.shipment_legs;
begin
  select * into v_shipment from app.shipment_orders where idempotency_key = 'idem-plan-legs-done';

  select * into v_leg from app.add_shipment_leg(v_shipment.id, 'idem-plan-legs-done-leg1', 1, 'land', null, now(), now() + interval '1 day', '00000000-0000-0000-0000-000000039302', 'rep');
  perform app.add_shipment_leg_stop(v_leg.id, 1, 'pickup', 'Jakarta Warehouse', null, null, null, now(), '00000000-0000-0000-0000-000000039302', 'rep');
  perform app.add_shipment_leg_stop(v_leg.id, 2, 'delivery', 'Bogor Warehouse', null, null, null, now() + interval '1 day', '00000000-0000-0000-0000-000000039302', 'rep');
  perform app.allocate_shipment_leg_cargo(v_leg.id, 10, 500, 4, '00000000-0000-0000-0000-000000039302', 'rep');
  perform app.confirm_shipment_leg_network(v_shipment.id, (select record_version from app.shipment_orders where id = v_shipment.id), '00000000-0000-0000-0000-000000039302', 'rep');
  select * into v_leg from app.shipment_legs where id = v_leg.id;
  select * into v_leg from app.transition_shipment_leg(v_leg.id, 'dispatched', v_leg.record_version, '00000000-0000-0000-0000-000000039302', 'rep');
  select * into v_leg from app.transition_shipment_leg(v_leg.id, 'in_transit', v_leg.record_version, '00000000-0000-0000-0000-000000039302', 'rep');
  select * into v_leg from app.transition_shipment_leg(v_leg.id, 'arrived', v_leg.record_version, '00000000-0000-0000-0000-000000039302', 'rep');
  perform app.transition_shipment_leg(v_leg.id, 'completed', v_leg.record_version, '00000000-0000-0000-0000-000000039302', 'rep');

  select * into v_scenario from app.route_planning_scenarios where idempotency_key = 'idem-scenario-legs-done';

  begin
    perform app.replan_route_planning_scenario(v_scenario.id, 'attempt to replan a fully executed shipment', 'idem-replan-legs-done', '00000000-0000-0000-0000-000000039302', 'rep');
    raise exception 'assertion failed: expected nothing_to_replan -- every leg of this shipment has already left planned';
  exception
    when others then
      if sqlerrm not like 'nothing_to_replan%' then raise; end if;
  end;
end $$;

\echo '>> cross-tenant isolation: app.prepare_route_planning_scenario/app.validate_route_planning_scenario fail closed for an identity with no membership in the shipment''s own tenant'
do $$
declare
  v_tenant2 uuid;
  v_shipment_id uuid;
begin
  insert into auth.users (id, email) values ('00000000-0000-0000-0000-000000039307', 'admin2@acmeplan2.test');
  perform app.provision_tenant('acmeplan2', 'Acme Planning Co 2', 'idem-acmeplan2', 'tester');
  v_tenant2 := (select id from app.tenants where slug = 'acmeplan2');
  perform app.transition_tenant_status(v_tenant2, 'active', 'setup', 'tester');
  perform app.invite_user(v_tenant2, '00000000-0000-0000-0000-000000039307', 'admin2@acmeplan2.test', 'Tenant 2 Admin', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'admin2@acmeplan2.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000039307', 'tenant_admin', v_tenant2, null, 'tester');

  select id into v_shipment_id from app.shipment_orders where idempotency_key = 'idem-plan-feasible';

  begin
    perform app.prepare_route_planning_scenario(v_shipment_id, 'idem-scenario-tenant2', 800, 10, '00000000-0000-0000-0000-000000039307', 'tenant2-admin');
    raise exception 'assertion failed: expected insufficient_privilege -- tenant 2''s admin holds no OPS:Create in tenant 1';
  exception
    when others then
      if sqlerrm not like 'insufficient_authority%' then raise; end if;
  end;
end $$;

\echo '>> schema-privilege defense in depth: anon holds no EXECUTE on any of the 15 new Route and Load Planning functions (ERR-2026-004 regression guard)'
do $$
declare
  v_count integer;
begin
  select count(*) into v_count
  from information_schema.routine_privileges
  where routine_schema = 'app'
    and grantee = 'anon'
    and routine_name in (
      'route_planning_default_speed_kmh', 'route_planning_position_staleness_tolerance_seconds',
      'get_canonical_position_for_planning', 'prepare_route_planning_scenario', 'add_route_planning_stop',
      'add_route_planning_constraint', 'validate_route_planning_scenario', 'execute_route_planning_scenario',
      'generate_route_planning_candidates', 'run_next_route_planning_job', 'cancel_route_planning_scenario',
      'select_route_planning_plan', 'override_route_planning_selection', 'replan_route_planning_scenario',
      'get_route_planning_stops'
    );
  if v_count <> 0 then
    raise exception 'assertion failed: expected zero anon EXECUTE grants on the 15 new Route and Load Planning functions, found %', v_count;
  end if;
end $$;

\echo '>> schema-privilege defense in depth: authenticated has no direct INSERT/UPDATE/DELETE on any of the 7 new tables (mutation only through the governed RPCs above)'
do $$
declare
  v_count integer;
begin
  select count(*) into v_count
  from information_schema.role_table_grants
  where table_schema = 'app'
    and grantee = 'authenticated'
    and privilege_type in ('INSERT', 'UPDATE', 'DELETE')
    and table_name in (
      'route_planning_scenarios', 'route_planning_stops', 'route_planning_constraints',
      'route_planning_candidate_plans', 'route_planning_score_components', 'route_planning_selected_plans',
      'route_planning_replan_events'
    );
  if v_count <> 0 then
    raise exception 'assertion failed: expected zero authenticated INSERT/UPDATE/DELETE grants on the 7 new tables, found %', v_count;
  end if;
end $$;

\echo '>> audit trail: every real Route and Load Planning mutation recorded a real app.audit_logs event, tenant-scoped'
do $$
declare
  v_tenant1 uuid;
  v_count integer;
begin
  v_tenant1 := (select id from app.tenants where slug = 'acmeplan');

  select count(*) into v_count from app.audit_logs where tenant_id = v_tenant1 and resource_type = 'app.route_planning_scenarios' and action = 'prepare_route_planning_scenario';
  if v_count <> 4 then
    raise exception 'assertion failed: expected exactly 4 prepare_route_planning_scenario audit events (feasible, infeasible, legs-done, to-cancel; the idempotent retry and the denied attempt are not counted), found %', v_count;
  end if;

  select count(*) into v_count from app.audit_logs where tenant_id = v_tenant1 and resource_type = 'app.route_planning_selected_plans' and action = 'override_route_planning_selection';
  if v_count <> 1 then
    raise exception 'assertion failed: expected exactly 1 override_route_planning_selection audit event, found %', v_count;
  end if;

  select count(*) into v_count from app.audit_logs where tenant_id = v_tenant1 and resource_type = 'app.route_planning_scenarios' and action = 'replan_route_planning_scenario';
  if v_count <> 1 then
    raise exception 'assertion failed: expected exactly 1 replan_route_planning_scenario audit event, found %', v_count;
  end if;
end $$;
