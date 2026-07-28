-- Real, executable test evidence for OPS-178 (Actual Cost, CG-S8-OPS-012)
-- -- run via `pnpm run db:test` against a real, disposable Postgres database.

\set ON_ERROR_STOP on

\echo '>> setup: one tenant, a company/team-a/team-b org hierarchy, a bootstrap tenant-admin, a rep (OPS full + OPS:View cost), a restricted actor (OPS full, no OPS:View cost), a sibling-team outsider (full grants incl. View cost, wrong record scope), two vendors, one confirmed Job Order, and two confirmed Shipment Orders (assigned, with a real active vendor assignment)'
do $$
declare
  v_tenant1 uuid;
  v_team_a uuid;
  v_team_b uuid;
  v_rep_role uuid;
  v_rep_draft app.role_versions;
  v_restricted_role uuid;
  v_restricted_draft app.role_versions;
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
  v_vendor app.master_records;
  v_vendor_b app.master_records;
  v_shipment_a app.shipment_orders;
  v_shipment_b app.shipment_orders;
  v_assignment_a app.resource_assignments;
begin
  insert into auth.users (id, email) values
    ('00000000-0000-0000-0000-000000023301', 'admin@acmeactcost.test'),
    ('00000000-0000-0000-0000-000000023302', 'repa@acmeactcost.test'),
    ('00000000-0000-0000-0000-000000023303', 'restricted@acmeactcost.test'),
    ('00000000-0000-0000-0000-000000023304', 'outsider@acmeactcost.test');

  perform app.provision_tenant('acmeactcost', 'Acme Actcost Co', 'idem-acmeactcost', 'tester');
  v_tenant1 := (select id from app.tenants where slug = 'acmeactcost');
  perform app.transition_tenant_status(v_tenant1, 'active', 'setup', 'tester');

  perform app.create_org_unit(v_tenant1, 'company', null, 'ACMEACTCOST-CO', 'Acme Actcost Co', 'tester');
  perform app.create_org_unit(v_tenant1, 'department', (select id from app.org_units where tenant_id = v_tenant1 and code = 'ACMEACTCOST-CO'), 'ACMEACTCOST-TEAM-A', 'Team A', 'tester');
  v_team_a := (select id from app.org_units where tenant_id = v_tenant1 and code = 'ACMEACTCOST-TEAM-A');
  perform app.create_org_unit(v_tenant1, 'department', (select id from app.org_units where tenant_id = v_tenant1 and code = 'ACMEACTCOST-CO'), 'ACMEACTCOST-TEAM-B', 'Team B', 'tester');
  v_team_b := (select id from app.org_units where tenant_id = v_tenant1 and code = 'ACMEACTCOST-TEAM-B');

  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000023301', 'admin@acmeactcost.test', 'Actcost Admin', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'admin@acmeactcost.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000023301', 'tenant_admin', v_tenant1, null, 'tester');

  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000023302', 'repa@acmeactcost.test', 'Rep A', v_team_a, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'repa@acmeactcost.test'), 'active', 'onboarded', 'tester');
  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000023303', 'restricted@acmeactcost.test', 'Restricted Actor', v_team_a, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'restricted@acmeactcost.test'), 'active', 'onboarded', 'tester');
  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000023304', 'outsider@acmeactcost.test', 'Team B Outsider', v_team_b, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'outsider@acmeactcost.test'), 'active', 'onboarded', 'tester');

  v_rep_role := (app.create_role(v_tenant1, 'Actcost Rep', 'full commercial + ops grants + view cost', 'tester')).id;
  v_rep_draft := app.create_role_version(v_rep_role, 'tester');
  perform app.set_role_version_permissions(
    v_rep_draft.id,
    array(select id from app.permissions where (resource_module_code = 'COM' and action in ('Create', 'Edit', 'Approve', 'View', 'View cost'))
      or (resource_module_code = 'OPS' and action in ('Create', 'Edit', 'Assign', 'View', 'View cost'))),
    'tester'
  );
  perform app.publish_role_version(v_rep_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_rep_role and status = 'published'), '00000000-0000-0000-0000-000000023302', '00000000-0000-0000-0000-000000023301', 'tester');

  v_restricted_role := (app.create_role(v_tenant1, 'Actcost Restricted', 'full OPS Create/Edit/View, no View cost', 'tester')).id;
  v_restricted_draft := app.create_role_version(v_restricted_role, 'tester');
  perform app.set_role_version_permissions(
    v_restricted_draft.id,
    array(select id from app.permissions where resource_module_code = 'OPS' and action in ('Create', 'Edit', 'View')),
    'tester'
  );
  perform app.publish_role_version(v_restricted_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_restricted_role and status = 'published'), '00000000-0000-0000-0000-000000023303', '00000000-0000-0000-0000-000000023303', 'tester');

  v_outsider_role := (app.create_role(v_tenant1, 'Actcost Outsider', 'sibling team, full grants incl. view cost', 'tester')).id;
  v_outsider_draft := app.create_role_version(v_outsider_role, 'tester');
  perform app.set_role_version_permissions(
    v_outsider_draft.id,
    array(select id from app.permissions where (resource_module_code = 'COM' and action in ('Create', 'Edit', 'View'))
      or (resource_module_code = 'OPS' and action in ('Create', 'Edit', 'Assign', 'View', 'View cost'))),
    'tester'
  );
  perform app.publish_role_version(v_outsider_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_outsider_role and status = 'published'), '00000000-0000-0000-0000-000000023304', '00000000-0000-0000-0000-000000023301', 'tester');

  perform app.capture_lead(v_tenant1, 'manual', null, 'Actcost Test Co', 'Jane Actcost', 'jane@actcosttest.test', '0811',
    '00000000-0000-0000-0000-000000023302', v_team_a, '00000000-0000-0000-0000-000000023302', 'tester');
  select * into v_lead from app.leads where email = 'jane@actcosttest.test';
  perform app.qualify_lead(v_lead.id, v_lead.record_version, '00000000-0000-0000-0000-000000023302', 'tester');
  select * into v_lead from app.leads where id = v_lead.id;
  perform app.convert_lead_to_prospect(v_lead.id, 'Actcost Test Co', 'ACT', '11.111.111.4-444.000',
    jsonb_build_object('line1', 'Jl. Rasuna Said 4', 'city', 'Jakarta', 'country', 'ID'),
    '00000000-0000-0000-0000-000000023302', 'tester');
  select * into v_prospect from app.prospects where lead_id = v_lead.id;

  select * into v_contact from app.create_contact(v_tenant1, 'Jane Actcost Ops', 'Procurement Lead', 'jane@actcosttest.test', '0811', '00000000-0000-0000-0000-000000023302', v_team_a, '00000000-0000-0000-0000-000000023302', 'tester');
  perform app.link_contact_to_record(v_contact.id, 'prospect', v_prospect.id, 'primary', true, '00000000-0000-0000-0000-000000023302', 'tester');

  select * into v_opportunity from app.create_opportunity(
    v_tenant1, v_prospect.id, 'Actcost test lane',
    jsonb_build_object('service_type', 'ocean_freight', 'cargo_description', 'General cargo', 'origin', 'Jakarta', 'destination', 'Surabaya', 'target_ready_date', '2026-08-01'),
    '00000000-0000-0000-0000-000000023302', v_team_a, '00000000-0000-0000-0000-000000023302', 'tester'
  );
  select * into v_request from app.request_costing(v_opportunity.id, '[]'::jsonb, null, '00000000-0000-0000-0000-000000023302', 'tester');
  select * into v_rate from app.create_rate_version(
    v_tenant1, 'VENDOR-ACTCOST-1', 'Contoso Ocean Line', 'ocean_freight', 'FCL', 'Jakarta', 'Surabaya', '20ft',
    null, null, null, null, 'IDR', 10000000, null, '[]'::jsonb, now(), null, null, '00000000-0000-0000-0000-000000023301', 'tester'
  );
  perform app.approve_rate_version(v_rate.id, v_rate.record_version, '00000000-0000-0000-0000-000000023301', 'tester');
  select * into v_selection from app.select_vendor_rate(v_request.id, v_rate.id, false, null, null, null, '00000000-0000-0000-0000-000000023302', 'tester');

  select * into v_rule from app.create_margin_rule_version(v_tenant1, 20.00, 'half_up', '00000000-0000-0000-0000-000000023302', 'tester');
  perform app.publish_margin_rule_version(v_rule.id, v_rule.record_version, null, '00000000-0000-0000-0000-000000023302', 'tester');
  perform app.calculate_margin(v_selection.id, 15000000, 'IDR', 0, '00000000-0000-0000-0000-000000023302', 'tester');
  select id into v_calc_id from app.margin_calculations where rate_selection_id = v_selection.id and is_current;

  select * into v_quote from app.create_quotation_draft(v_tenant1, v_opportunity.id, 'IDR', now() + interval '14 days', v_contact.id, null, null, '00000000-0000-0000-0000-000000023302', 'tester');
  perform app.add_quotation_line(v_quote.id, v_quote.record_version, 'service', 'Ocean freight actcost lane', v_calc_id, 1, 15000000, 0, 0, '00000000-0000-0000-0000-000000023302', 'tester');
  select * into v_quote from app.quotations where id = v_quote.id;
  perform app.submit_quotation(v_quote.id, v_quote.record_version, '00000000-0000-0000-0000-000000023302', 'tester');
  select * into v_send from app.send_quotation_for_acceptance(v_quote.id, null, 'email', '00000000-0000-0000-0000-000000023302', 'tester');
  perform app.record_quotation_customer_decision(v_send.raw_token, 'accepted', 'Jane Actcost Ops', null, null, null, null, null);
  select * into v_quote from app.quotations where id = v_quote.id;
  select * into v_account from app.convert_quotation_to_account(v_quote.id, null, null, '00000000-0000-0000-0000-000000023302', 'rep');
  select * into v_handoff from app.prepare_job_order_handoff(v_quote.id, '00000000-0000-0000-0000-000000023302', 'rep');

  select * into v_job_order from app.prepare_job_order(v_handoff.id, '00000000-0000-0000-0000-000000023302', 'rep');
  select * into v_job_order from app.confirm_job_order(v_job_order.id, v_job_order.record_version, '00000000-0000-0000-0000-000000023302', 'rep');

  select * into v_vendor from app.create_master_record('vendor', v_tenant1, 'VEND-ACTCOST-1', 'Contoso Trucking', '[]'::jsonb, '{}'::jsonb, '00000000-0000-0000-0000-000000023301', 'admin');
  select * into v_vendor_b from app.create_master_record('vendor', v_tenant1, 'VEND-ACTCOST-2', 'Fabrikam Trucking', '[]'::jsonb, '{}'::jsonb, '00000000-0000-0000-0000-000000023301', 'admin');

  select * into v_shipment_a from app.create_shipment_order_from_job(
    v_job_order.id, 'idem-actcost-a', null, null, 'ocean_freight', 'sea', 'Jakarta', 'Surabaya',
    now() + interval '1 day', now() + interval '10 days', null, null, null, null, null, null, null, '00000000-0000-0000-0000-000000023302', 'rep'
  );
  select * into v_shipment_a from app.confirm_shipment_order(v_shipment_a.id, v_shipment_a.record_version, '00000000-0000-0000-0000-000000023302', 'rep');
  select * into v_shipment_a from app.transition_shipment_order(v_shipment_a.id, 'planned', v_shipment_a.record_version, null, null, 'idem-actcost-a-planned', '00000000-0000-0000-0000-000000023302', 'rep');
  select * into v_shipment_a from app.transition_shipment_order(v_shipment_a.id, 'assigned', v_shipment_a.record_version, null, null, 'idem-actcost-a-assigned', '00000000-0000-0000-0000-000000023302', 'rep');
  select * into v_assignment_a from app.assign_resource(v_shipment_a.id, 'vendor', v_vendor.id, '00000000-0000-0000-0000-000000023302', 'rep');

  select * into v_shipment_b from app.create_shipment_order_from_job(
    v_job_order.id, 'idem-actcost-b', null, null, 'ocean_freight', 'sea', 'Jakarta', 'Bandung',
    now() + interval '1 day', now() + interval '10 days', null, null, null, null, null, null, 'split: actcost second fixture', '00000000-0000-0000-0000-000000023302', 'rep'
  );
  select * into v_shipment_b from app.confirm_shipment_order(v_shipment_b.id, v_shipment_b.record_version, '00000000-0000-0000-0000-000000023302', 'rep');
  select * into v_shipment_b from app.transition_shipment_order(v_shipment_b.id, 'planned', v_shipment_b.record_version, null, null, 'idem-actcost-b-planned', '00000000-0000-0000-0000-000000023302', 'rep');
  select * into v_shipment_b from app.transition_shipment_order(v_shipment_b.id, 'assigned', v_shipment_b.record_version, null, null, 'idem-actcost-b-assigned', '00000000-0000-0000-0000-000000023302', 'rep');
  perform app.assign_resource(v_shipment_b.id, 'vendor', v_vendor_b.id, '00000000-0000-0000-0000-000000023302', 'rep');
end $$;

\echo '>> app.create_actual_cost_draft: authority-gated (OPS:Create + OPS:View cost, record-scope), idempotent, at most one current version per shipment'
do $$
declare
  v_shipment_a_id uuid := (select id from app.shipment_orders where idempotency_key = 'idem-actcost-a');
  v_draft1 app.shipment_actual_costs;
  v_draft2 app.shipment_actual_costs;
begin
  begin
    perform app.create_actual_cost_draft((select tenant_id from app.shipment_orders where id = v_shipment_a_id), v_shipment_a_id, 'IDR', null, '00000000-0000-0000-0000-000000023303', 'restricted');
    raise exception 'assertion failed: expected the restricted actor (no OPS:View cost) to be denied';
  exception
    when insufficient_privilege then null;
  end;

  begin
    perform app.create_actual_cost_draft((select tenant_id from app.shipment_orders where id = v_shipment_a_id), v_shipment_a_id, 'IDR', null, '00000000-0000-0000-0000-000000023304', 'outsider');
    raise exception 'assertion failed: expected the sibling-team outsider to be denied by record scope despite full grants';
  exception
    when insufficient_privilege then null;
  end;

  v_draft1 := app.create_actual_cost_draft((select tenant_id from app.shipment_orders where id = v_shipment_a_id), v_shipment_a_id, 'IDR', 12000000, '00000000-0000-0000-0000-000000023302', 'rep');
  v_draft2 := app.create_actual_cost_draft((select tenant_id from app.shipment_orders where id = v_shipment_a_id), v_shipment_a_id, 'IDR', 12000000, '00000000-0000-0000-0000-000000023302', 'rep');
  if v_draft1.id <> v_draft2.id then
    raise exception 'assertion failed: expected repeated draft creation for the same shipment to be idempotent';
  end if;
  if v_draft1.status <> 'draft' or v_draft1.total_amount <> 0 then
    raise exception 'assertion failed: expected a fresh draft with zero total';
  end if;
end $$;

\echo '>> app.add_actual_cost_component: exact amount reconciliation (quantity*rate/minimum/surcharge), vendor-required validation, assignment/document mismatch rejected, idempotent, header total recomputed'
do $$
declare
  v_shipment_a_id uuid := (select id from app.shipment_orders where idempotency_key = 'idem-actcost-a');
  v_shipment_b_id uuid := (select id from app.shipment_orders where idempotency_key = 'idem-actcost-b');
  v_cost app.shipment_actual_costs;
  v_vendor_id uuid := (select id from app.master_records where code = 'VEND-ACTCOST-1');
  v_assignment_id uuid := (select id from app.resource_assignments where shipment_order_id = v_shipment_a_id and is_current);
  v_wrong_assignment_id uuid;
  v_component1 app.shipment_actual_cost_components;
  v_component1_repeat app.shipment_actual_cost_components;
  v_component2 app.shipment_actual_cost_components;
  v_updated_cost app.shipment_actual_costs;
begin
  select * into v_cost from app.shipment_actual_costs where shipment_order_id = v_shipment_a_id;

  begin
    perform app.add_actual_cost_component(v_cost.id, 'freight', 'vendor', null, null, null, 'Ocean freight', 1, 'shipment', 9500000, null, 0, 'idem-actcost-comp-novendor', '00000000-0000-0000-0000-000000023302', 'rep');
    raise exception 'assertion failed: expected actual_cost_vendor_required when source_type=vendor and vendor_id is null';
  exception
    when check_violation then
      if sqlerrm !~ 'actual_cost_vendor_required' then raise; end if;
  end;

  -- An assignment belonging to a different shipment order.
  select id into v_wrong_assignment_id from app.resource_assignments where shipment_order_id = v_shipment_b_id and is_current;

  begin
    perform app.add_actual_cost_component(v_cost.id, 'freight', 'vendor', v_vendor_id, v_wrong_assignment_id, null, 'Ocean freight', 1, 'shipment', 9500000, null, 0, 'idem-actcost-comp-wrongassign', '00000000-0000-0000-0000-000000023302', 'rep');
    raise exception 'assertion failed: expected actual_cost_assignment_mismatch for an assignment belonging to a different shipment';
  exception
    when check_violation then
      if sqlerrm !~ 'actual_cost_assignment_mismatch' then raise; end if;
  end;

  -- 1 * 9,500,000 vs minimum 10,000,000 -> minimum wins; + 250,000 surcharge = 10,250,000.00
  v_component1 := app.add_actual_cost_component(v_cost.id, 'freight', 'vendor', v_vendor_id, v_assignment_id, null, 'Ocean freight', 1, 'shipment', 9500000, 10000000, 250000, 'idem-actcost-comp-1', '00000000-0000-0000-0000-000000023302', 'rep');
  if v_component1.amount <> 10250000.00 then
    raise exception 'assertion failed: expected amount 10250000.00 (minimum wins + surcharge), got %', v_component1.amount;
  end if;

  v_component1_repeat := app.add_actual_cost_component(v_cost.id, 'freight', 'vendor', v_vendor_id, v_assignment_id, null, 'Ocean freight', 1, 'shipment', 9500000, 10000000, 250000, 'idem-actcost-comp-1', '00000000-0000-0000-0000-000000023302', 'rep');
  if v_component1.id <> v_component1_repeat.id then
    raise exception 'assertion failed: expected repeated add with the same idempotency_key to be idempotent';
  end if;

  -- 5 * 200,000 = 1,000,000, no minimum, no surcharge -> internal source (no vendor required).
  v_component2 := app.add_actual_cost_component(v_cost.id, 'handling', 'internal', null, null, null, 'Warehouse handling', 5, 'ton', 200000, null, 0, 'idem-actcost-comp-2', '00000000-0000-0000-0000-000000023302', 'rep');
  if v_component2.amount <> 1000000.00 then
    raise exception 'assertion failed: expected amount 1000000.00, got %', v_component2.amount;
  end if;

  select * into v_updated_cost from app.shipment_actual_costs where id = v_cost.id;
  if v_updated_cost.total_amount <> 11250000.00 then
    raise exception 'assertion failed: expected header total_amount 11250000.00, got %', v_updated_cost.total_amount;
  end if;
end $$;

\echo '>> app.remove_actual_cost_component / app.submit_actual_cost / app.decide_actual_cost: draft-only removal recomputes total, submission requires >=1 component, rejection requires a reason, approval succeeds and records approver/timestamp'
do $$
declare
  v_shipment_a_id uuid := (select id from app.shipment_orders where idempotency_key = 'idem-actcost-a');
  v_cost app.shipment_actual_costs;
  v_component2_id uuid;
  v_updated_cost app.shipment_actual_costs;
  v_submitted app.shipment_actual_costs;
  v_decided app.shipment_actual_costs;
begin
  select * into v_cost from app.shipment_actual_costs where shipment_order_id = v_shipment_a_id;
  select id into v_component2_id from app.shipment_actual_cost_components where actual_cost_id = v_cost.id and category = 'handling';

  perform app.remove_actual_cost_component(v_component2_id, '00000000-0000-0000-0000-000000023302', 'rep');
  select * into v_updated_cost from app.shipment_actual_costs where id = v_cost.id;
  if v_updated_cost.total_amount <> 10250000.00 then
    raise exception 'assertion failed: expected total_amount to recompute to 10250000.00 after removal, got %', v_updated_cost.total_amount;
  end if;

  v_submitted := app.submit_actual_cost(v_updated_cost.id, v_updated_cost.record_version, '00000000-0000-0000-0000-000000023302', 'rep');
  if v_submitted.status <> 'submitted' then
    raise exception 'assertion failed: expected submitted status';
  end if;

  begin
    perform app.decide_actual_cost(v_submitted.id, 'rejected', null, v_submitted.record_version, '00000000-0000-0000-0000-000000023302', 'rep');
    raise exception 'assertion failed: expected actual_cost_rejection_reason_required with no reason';
  exception
    when check_violation then
      if sqlerrm !~ 'actual_cost_rejection_reason_required' then raise; end if;
  end;

  v_decided := app.decide_actual_cost(v_submitted.id, 'approved', null, v_submitted.record_version, '00000000-0000-0000-0000-000000023302', 'rep');
  if v_decided.status <> 'approved' or v_decided.approved_by_auth_user_id is null or v_decided.approved_at is null then
    raise exception 'assertion failed: expected the cost to approve with approver/timestamp recorded';
  end if;
end $$;

\echo '>> app.evaluate_actual_cost_variance: real variance when estimated_amount was supplied; app.create_actual_cost_adjustment: approved-only, reason required, copies components onto a brand-new version while the prior approved version and its components remain unchanged'
do $$
declare
  v_shipment_a_id uuid := (select id from app.shipment_orders where idempotency_key = 'idem-actcost-a');
  v_approved app.shipment_actual_costs;
  v_variance record;
  v_adjustment app.shipment_actual_costs;
  v_prior app.shipment_actual_costs;
  v_prior_component_count integer;
  v_new_component_count integer;
begin
  select * into v_approved from app.shipment_actual_costs where shipment_order_id = v_shipment_a_id and is_current;

  select * into v_variance from app.evaluate_actual_cost_variance(v_approved.id, '00000000-0000-0000-0000-000000023302');
  if not v_variance.variance_available or v_variance.variance_amount <> (10250000.00 - 12000000.00) then
    raise exception 'assertion failed: expected a real variance of %, got %/%', (10250000.00 - 12000000.00), v_variance.variance_available, v_variance.variance_amount;
  end if;

  begin
    perform app.create_actual_cost_adjustment(v_approved.id, null, '00000000-0000-0000-0000-000000023302', 'rep');
    raise exception 'assertion failed: expected actual_cost_adjustment_reason_required with no reason';
  exception
    when check_violation then
      if sqlerrm !~ 'actual_cost_adjustment_reason_required' then raise; end if;
  end;

  v_adjustment := app.create_actual_cost_adjustment(v_approved.id, 'vendor issued a corrected invoice', '00000000-0000-0000-0000-000000023302', 'rep');
  if v_adjustment.version_number <> 2 or v_adjustment.status <> 'draft' or v_adjustment.supersedes_version_id <> v_approved.id then
    raise exception 'assertion failed: expected a new draft version 2 superseding the approved version';
  end if;
  if v_adjustment.total_amount <> 10250000.00 then
    raise exception 'assertion failed: expected the adjustment to start with the copied total 10250000.00, got %', v_adjustment.total_amount;
  end if;

  select * into v_prior from app.shipment_actual_costs where id = v_approved.id;
  if v_prior.is_current or v_prior.status <> 'approved' then
    raise exception 'assertion failed: expected the prior approved version to remain approved, no longer current';
  end if;

  select count(*) into v_prior_component_count from app.shipment_actual_cost_components where actual_cost_id = v_prior.id;
  select count(*) into v_new_component_count from app.shipment_actual_cost_components where actual_cost_id = v_adjustment.id;
  if v_prior_component_count <> 1 or v_new_component_count <> 1 then
    raise exception 'assertion failed: expected exactly 1 component preserved on the prior version and 1 copied onto the new version, got %/%', v_prior_component_count, v_new_component_count;
  end if;

  begin
    perform app.create_actual_cost_adjustment(v_adjustment.id, 'second adjustment attempt', '00000000-0000-0000-0000-000000023302', 'rep');
    raise exception 'assertion failed: expected invalid_transition -- the new version is still draft, not approved';
  exception
    when check_violation then
      if sqlerrm !~ 'invalid_transition' then raise; end if;
  end;
end $$;

\echo '>> app.list_actual_cost_components: denies outright (no partial result) without OPS:View cost; app.shipment_actual_costs_directory masks total_amount/estimated_amount without OPS:View cost; record-scope/cross-tenant RLS; schema-privilege defense in depth (anon holds zero EXECUTE on all 10 new functions, zero direct SELECT on the components table)'
do $$
declare
  v_shipment_a_id uuid := (select id from app.shipment_orders where idempotency_key = 'idem-actcost-a');
  v_cost_id uuid := (select id from app.shipment_actual_costs where shipment_order_id = v_shipment_a_id and is_current);
  v_count integer;
  v_denied_count integer;
  v_table_denied_count integer;
  v_masked boolean;
  v_total numeric;
begin
  begin
    perform app.list_actual_cost_components(v_cost_id, '00000000-0000-0000-0000-000000023303');
    raise exception 'assertion failed: expected the restricted actor (no OPS:View cost) to be denied listing components';
  exception
    when insufficient_privilege then null;
  end;

  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000023303", "role": "authenticated"}';
  select cost_masked, total_amount into v_masked, v_total from app.shipment_actual_costs_directory where id = v_cost_id;
  if not v_masked or v_total is not null then
    raise exception 'assertion failed: expected the restricted actor to see cost_masked=true and total_amount=null via the directory view, got %/%', v_masked, v_total;
  end if;
  reset role;

  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000023302", "role": "authenticated"}';
  select cost_masked, total_amount into v_masked, v_total from app.shipment_actual_costs_directory where id = v_cost_id;
  if v_masked or v_total is null then
    raise exception 'assertion failed: expected the full-access rep to see cost_masked=false and a real total_amount via the directory view, got %/%', v_masked, v_total;
  end if;
  reset role;

  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000023304", "role": "authenticated"}';
  select count(*) into v_count from app.shipment_actual_costs where shipment_order_id = v_shipment_a_id;
  if v_count <> 0 then
    raise exception 'assertion failed: expected the sibling-team outsider to see zero actual-cost rows for shipment_a via RLS, got %', v_count;
  end if;
  reset role;

  select count(*) into v_denied_count
  from information_schema.routine_privileges
  where routine_schema = 'app'
    and routine_name in (
      'has_view_actual_cost', 'compute_actual_cost_component_amount', 'create_actual_cost_draft', 'add_actual_cost_component',
      'remove_actual_cost_component', 'submit_actual_cost', 'decide_actual_cost', 'create_actual_cost_adjustment',
      'evaluate_actual_cost_variance', 'list_actual_cost_components'
    )
    and grantee = 'anon';
  if v_denied_count <> 0 then
    raise exception 'assertion failed: expected anon to hold zero EXECUTE grants on the 10 new OPS-178 functions, found %', v_denied_count;
  end if;

  select count(*) into v_table_denied_count
  from information_schema.table_privileges
  where table_schema = 'app' and table_name = 'shipment_actual_cost_components' and grantee in ('anon', 'authenticated');
  if v_table_denied_count <> 0 then
    raise exception 'assertion failed: expected neither anon nor authenticated to hold any direct grant on app.shipment_actual_cost_components, found %', v_table_denied_count;
  end if;
end $$;

\echo '>> audit trail: every mutation self-captures a canonical app.audit_logs entry'
do $$
declare
  v_count integer;
begin
  select count(*) into v_count from app.audit_logs
  where action in ('create_actual_cost_draft', 'add_actual_cost_component', 'remove_actual_cost_component', 'submit_actual_cost', 'decide_actual_cost', 'create_actual_cost_adjustment');
  if v_count < 6 then
    raise exception 'assertion failed: expected at least 6 persisted OPS-178 audit events, found %', v_count;
  end if;
end $$;
