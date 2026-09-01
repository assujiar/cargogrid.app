-- Real, executable test evidence for OPS-179 (Basic Job Profitability, CG-S8-OPS-013)
-- -- run via `pnpm run db:test` against a real, disposable Postgres database.

\set ON_ERROR_STOP on

\echo '>> setup: one tenant, a company/team-a/team-b org hierarchy, a bootstrap tenant-admin, a rep (OPS full + OPS:View margin + OPS:View cost), a restricted actor (OPS full, no OPS:View margin), a sibling-team outsider (full grants incl. View margin, wrong record scope), one confirmed Job Order (revenue 15,000,000 IDR), and two confirmed/assigned Shipment Orders off it with approved actual costs'
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
  v_cost_a app.shipment_actual_costs;
  v_cost_b app.shipment_actual_costs;
begin
  insert into auth.users (id, email) values
    ('00000000-0000-0000-0000-000000023401', 'admin@acmeprofit.test'),
    ('00000000-0000-0000-0000-000000023402', 'repa@acmeprofit.test'),
    ('00000000-0000-0000-0000-000000023403', 'restricted@acmeprofit.test'),
    ('00000000-0000-0000-0000-000000023404', 'outsider@acmeprofit.test');

  perform app.provision_tenant('acmeprofit', 'Acme Profit Co', 'idem-acmeprofit', 'tester');
  v_tenant1 := (select id from app.tenants where slug = 'acmeprofit');
  perform app.transition_tenant_status(v_tenant1, 'active', 'setup', 'tester');

  perform app.create_org_unit(v_tenant1, 'company', null, 'ACMEPROFIT-CO', 'Acme Profit Co', 'tester');
  perform app.create_org_unit(v_tenant1, 'department', (select id from app.org_units where tenant_id = v_tenant1 and code = 'ACMEPROFIT-CO'), 'ACMEPROFIT-TEAM-A', 'Team A', 'tester');
  v_team_a := (select id from app.org_units where tenant_id = v_tenant1 and code = 'ACMEPROFIT-TEAM-A');
  perform app.create_org_unit(v_tenant1, 'department', (select id from app.org_units where tenant_id = v_tenant1 and code = 'ACMEPROFIT-CO'), 'ACMEPROFIT-TEAM-B', 'Team B', 'tester');
  v_team_b := (select id from app.org_units where tenant_id = v_tenant1 and code = 'ACMEPROFIT-TEAM-B');

  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000023401', 'admin@acmeprofit.test', 'Profit Admin', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'admin@acmeprofit.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000023401', 'tenant_admin', v_tenant1, null, 'tester');

  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000023402', 'repa@acmeprofit.test', 'Rep A', v_team_a, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'repa@acmeprofit.test'), 'active', 'onboarded', 'tester');
  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000023403', 'restricted@acmeprofit.test', 'Restricted Actor', v_team_a, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'restricted@acmeprofit.test'), 'active', 'onboarded', 'tester');
  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000023404', 'outsider@acmeprofit.test', 'Team B Outsider', v_team_b, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'outsider@acmeprofit.test'), 'active', 'onboarded', 'tester');

  v_rep_role := (app.create_role(v_tenant1, 'Profit Rep', 'full commercial + ops grants + view cost/margin', 'tester')).id;
  v_rep_draft := app.create_role_version(v_rep_role, 'tester');
  perform app.set_role_version_permissions(
    v_rep_draft.id,
    array(select id from app.permissions where (resource_module_code = 'COM' and action in ('Create', 'Edit', 'Approve', 'View', 'View cost'))
      or (resource_module_code = 'OPS' and action in ('Create', 'Edit', 'Assign', 'View', 'View cost', 'View margin'))),
    'tester'
  );
  perform app.publish_role_version(v_rep_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_rep_role and status = 'published'), '00000000-0000-0000-0000-000000023402', '00000000-0000-0000-0000-000000023401', 'tester');

  v_restricted_role := (app.create_role(v_tenant1, 'Profit Restricted', 'full OPS Create/Edit/View, no View margin', 'tester')).id;
  v_restricted_draft := app.create_role_version(v_restricted_role, 'tester');
  perform app.set_role_version_permissions(
    v_restricted_draft.id,
    array(select id from app.permissions where resource_module_code = 'OPS' and action in ('Create', 'Edit', 'View')),
    'tester'
  );
  perform app.publish_role_version(v_restricted_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_restricted_role and status = 'published'), '00000000-0000-0000-0000-000000023403', '00000000-0000-0000-0000-000000023403', 'tester');

  v_outsider_role := (app.create_role(v_tenant1, 'Profit Outsider', 'sibling team, full grants incl. view margin', 'tester')).id;
  v_outsider_draft := app.create_role_version(v_outsider_role, 'tester');
  perform app.set_role_version_permissions(
    v_outsider_draft.id,
    array(select id from app.permissions where (resource_module_code = 'COM' and action in ('Create', 'Edit', 'View'))
      or (resource_module_code = 'OPS' and action in ('Create', 'Edit', 'Assign', 'View', 'View cost', 'View margin'))),
    'tester'
  );
  perform app.publish_role_version(v_outsider_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_outsider_role and status = 'published'), '00000000-0000-0000-0000-000000023404', '00000000-0000-0000-0000-000000023401', 'tester');

  perform app.capture_lead(v_tenant1, 'manual', null, 'Profit Test Co', 'Jane Profit', 'jane@profittest.test', '0811',
    '00000000-0000-0000-0000-000000023402', v_team_a, '00000000-0000-0000-0000-000000023402', 'tester');
  select * into v_lead from app.leads where email = 'jane@profittest.test';
  perform app.qualify_lead(v_lead.id, v_lead.record_version, '00000000-0000-0000-0000-000000023402', 'tester');
  select * into v_lead from app.leads where id = v_lead.id;
  perform app.convert_lead_to_prospect(v_lead.id, 'Profit Test Co', 'PFT', '11.111.111.5-555.000',
    jsonb_build_object('line1', 'Jl. Rasuna Said 5', 'city', 'Jakarta', 'country', 'ID'),
    '00000000-0000-0000-0000-000000023402', 'tester');
  select * into v_prospect from app.prospects where lead_id = v_lead.id;

  select * into v_contact from app.create_contact(v_tenant1, 'Jane Profit Ops', 'Procurement Lead', 'jane@profittest.test', '0811', '00000000-0000-0000-0000-000000023402', v_team_a, '00000000-0000-0000-0000-000000023402', 'tester');
  perform app.link_contact_to_record(v_contact.id, 'prospect', v_prospect.id, 'primary', true, '00000000-0000-0000-0000-000000023402', 'tester');

  select * into v_opportunity from app.create_opportunity(
    v_tenant1, v_prospect.id, 'Profit test lane',
    jsonb_build_object('service_type', 'ocean_freight', 'cargo_description', 'General cargo', 'origin', 'Jakarta', 'destination', 'Surabaya', 'target_ready_date', '2026-08-01'),
    '00000000-0000-0000-0000-000000023402', v_team_a, '00000000-0000-0000-0000-000000023402', 'tester'
  );
  select * into v_request from app.request_costing(v_opportunity.id, '[]'::jsonb, null, '00000000-0000-0000-0000-000000023402', 'tester');
  select * into v_rate from app.create_rate_version(
    v_tenant1, 'VENDOR-PROFIT-1', 'Contoso Ocean Line', 'ocean_freight', 'FCL', 'Jakarta', 'Surabaya', '20ft',
    null, null, null, null, 'IDR', 10000000, null, '[]'::jsonb, now(), null, null, '00000000-0000-0000-0000-000000023401', 'tester'
  );
  perform app.approve_rate_version(v_rate.id, v_rate.record_version, '00000000-0000-0000-0000-000000023401', 'tester');
  select * into v_selection from app.select_vendor_rate(v_request.id, v_rate.id, false, null, null, null, '00000000-0000-0000-0000-000000023402', 'tester');

  select * into v_rule from app.create_margin_rule_version(v_tenant1, 20.00, 'half_up', '00000000-0000-0000-0000-000000023402', 'tester');
  perform app.publish_margin_rule_version(v_rule.id, v_rule.record_version, null, '00000000-0000-0000-0000-000000023402', 'tester');
  perform app.calculate_margin(v_selection.id, 15000000, 'IDR', 0, '00000000-0000-0000-0000-000000023402', 'tester');
  select id into v_calc_id from app.margin_calculations where rate_selection_id = v_selection.id and is_current;

  -- Quotation total = 15,000,000 IDR (0 discount/tax) -- this is the revenue_snapshot.totalAmount app.job_orders will carry.
  select * into v_quote from app.create_quotation_draft(v_tenant1, v_opportunity.id, 'IDR', now() + interval '14 days', v_contact.id, null, null, '00000000-0000-0000-0000-000000023402', 'tester');
  perform app.add_quotation_line(v_quote.id, v_quote.record_version, 'service', 'Ocean freight profit lane', v_calc_id, 1, 15000000, 0, 0, '00000000-0000-0000-0000-000000023402', 'tester');
  select * into v_quote from app.quotations where id = v_quote.id;
  perform app.submit_quotation(v_quote.id, v_quote.record_version, '00000000-0000-0000-0000-000000023402', 'tester');
  select * into v_send from app.send_quotation_for_acceptance(v_quote.id, null, 'email', '00000000-0000-0000-0000-000000023402', 'tester');
  perform app.record_quotation_customer_decision(v_send.raw_token, 'accepted', 'Jane Profit Ops', null, null, null, null, null);
  select * into v_quote from app.quotations where id = v_quote.id;
  select * into v_account from app.convert_quotation_to_account(v_quote.id, null, null, '00000000-0000-0000-0000-000000023402', 'rep');
  select * into v_handoff from app.prepare_job_order_handoff(v_quote.id, '00000000-0000-0000-0000-000000023402', 'rep');

  select * into v_job_order from app.prepare_job_order(v_handoff.id, '00000000-0000-0000-0000-000000023402', 'rep');
  select * into v_job_order from app.confirm_job_order(v_job_order.id, v_job_order.record_version, '00000000-0000-0000-0000-000000023402', 'rep');

  select * into v_vendor from app.create_master_record('vendor', v_tenant1, 'VEND-PROFIT-1', 'Contoso Trucking', '[]'::jsonb, '{}'::jsonb, '00000000-0000-0000-0000-000000023401', 'admin');
  select * into v_vendor_b from app.create_master_record('vendor', v_tenant1, 'VEND-PROFIT-2', 'Fabrikam Trucking', '[]'::jsonb, '{}'::jsonb, '00000000-0000-0000-0000-000000023401', 'admin');

  select * into v_shipment_a from app.create_shipment_order_from_job(
    v_job_order.id, 'idem-profit-a', null, null, 'ocean_freight', 'sea', 'Jakarta', 'Surabaya',
    now() + interval '1 day', now() + interval '10 days', null, null, null, null, null, null, null, '00000000-0000-0000-0000-000000023402', 'rep'
  );
  select * into v_shipment_a from app.confirm_shipment_order(v_shipment_a.id, v_shipment_a.record_version, '00000000-0000-0000-0000-000000023402', 'rep');
  select * into v_shipment_a from app.transition_shipment_order(v_shipment_a.id, 'planned', v_shipment_a.record_version, null, null, 'idem-profit-a-planned', '00000000-0000-0000-0000-000000023402', 'rep');
  select * into v_shipment_a from app.transition_shipment_order(v_shipment_a.id, 'assigned', v_shipment_a.record_version, null, null, 'idem-profit-a-assigned', '00000000-0000-0000-0000-000000023402', 'rep');
  perform app.assign_resource(v_shipment_a.id, 'vendor', v_vendor.id, '00000000-0000-0000-0000-000000023402', 'rep');

  select * into v_shipment_b from app.create_shipment_order_from_job(
    v_job_order.id, 'idem-profit-b', null, null, 'ocean_freight', 'sea', 'Jakarta', 'Bandung',
    now() + interval '1 day', now() + interval '10 days', null, null, null, null, null, null, 'split: profit second fixture', '00000000-0000-0000-0000-000000023402', 'rep'
  );
  select * into v_shipment_b from app.confirm_shipment_order(v_shipment_b.id, v_shipment_b.record_version, '00000000-0000-0000-0000-000000023402', 'rep');
  select * into v_shipment_b from app.transition_shipment_order(v_shipment_b.id, 'planned', v_shipment_b.record_version, null, null, 'idem-profit-b-planned', '00000000-0000-0000-0000-000000023402', 'rep');
  select * into v_shipment_b from app.transition_shipment_order(v_shipment_b.id, 'assigned', v_shipment_b.record_version, null, null, 'idem-profit-b-assigned', '00000000-0000-0000-0000-000000023402', 'rep');
  perform app.assign_resource(v_shipment_b.id, 'vendor', v_vendor_b.id, '00000000-0000-0000-0000-000000023402', 'rep');

  -- Approved actual costs: 6,000,000 + 2,000,000 = 8,000,000 IDR total.
  v_cost_a := app.create_actual_cost_draft(v_tenant1, v_shipment_a.id, 'IDR', null, '00000000-0000-0000-0000-000000023402', 'rep');
  perform app.add_actual_cost_component(v_cost_a.id, 'freight', 'vendor', v_vendor.id, null, null, 'Ocean freight', 1, 'shipment', 6000000, null, 0, 'idem-profit-cost-a', '00000000-0000-0000-0000-000000023402', 'rep');
  select * into v_cost_a from app.shipment_actual_costs where id = v_cost_a.id;
  v_cost_a := app.submit_actual_cost(v_cost_a.id, v_cost_a.record_version, '00000000-0000-0000-0000-000000023402', 'rep');
  v_cost_a := app.decide_actual_cost(v_cost_a.id, 'approved', null, v_cost_a.record_version, '00000000-0000-0000-0000-000000023402', 'rep');

  v_cost_b := app.create_actual_cost_draft(v_tenant1, v_shipment_b.id, 'IDR', null, '00000000-0000-0000-0000-000000023402', 'rep');
  perform app.add_actual_cost_component(v_cost_b.id, 'trucking', 'vendor', v_vendor_b.id, null, null, 'Inland trucking', 1, 'shipment', 2000000, null, 0, 'idem-profit-cost-b', '00000000-0000-0000-0000-000000023402', 'rep');
  select * into v_cost_b from app.shipment_actual_costs where id = v_cost_b.id;
  v_cost_b := app.submit_actual_cost(v_cost_b.id, v_cost_b.record_version, '00000000-0000-0000-0000-000000023402', 'rep');
  v_cost_b := app.decide_actual_cost(v_cost_b.id, 'approved', null, v_cost_b.record_version, '00000000-0000-0000-0000-000000023402', 'rep');
end $$;

\echo '>> app.calculate_job_profitability: unavailable (no_approved_cost) before any approved cost exists on a fresh sibling job order is out of scope for this fixture set (both fixtures already have approved cost) -- instead verify authority-gating, a real positive-margin calculation, and the exact revenue/cost/margin numbers'
do $$
declare
  v_job_order_id uuid := (select jo.id from app.job_orders jo join app.tenants t on t.id = jo.tenant_id where t.slug = 'acmeprofit');
  v_snapshot app.job_profitability_snapshots;
begin
  begin
    perform app.calculate_job_profitability(v_job_order_id, null, '00000000-0000-0000-0000-000000023403', 'restricted');
    raise exception 'assertion failed: expected the restricted actor (no OPS:View margin) to be denied';
  exception
    when insufficient_privilege then null;
  end;

  begin
    perform app.calculate_job_profitability(v_job_order_id, null, '00000000-0000-0000-0000-000000023404', 'outsider');
    raise exception 'assertion failed: expected the sibling-team outsider to be denied by record scope despite full grants';
  exception
    when insufficient_privilege then null;
  end;

  v_snapshot := app.calculate_job_profitability(v_job_order_id, null, '00000000-0000-0000-0000-000000023402', 'rep');
  if v_snapshot.status <> 'calculated' or v_snapshot.revenue_amount <> 15000000.00 or v_snapshot.cost_amount <> 8000000.00 or v_snapshot.margin_amount <> 7000000.00 then
    raise exception 'assertion failed: expected revenue 15000000.00 / cost 8000000.00 / margin 7000000.00, got %/%/%', v_snapshot.revenue_amount, v_snapshot.cost_amount, v_snapshot.margin_amount;
  end if;
  -- margin_percent = 7,000,000 / 15,000,000 * 100 = 46.6667 (rounded to 4dp).
  if v_snapshot.margin_percent <> 46.6667 then
    raise exception 'assertion failed: expected margin_percent 46.6667, got %', v_snapshot.margin_percent;
  end if;
  if array_length(v_snapshot.source_cost_version_ids, 1) <> 2 then
    raise exception 'assertion failed: expected exactly 2 source cost version ids, got %', array_length(v_snapshot.source_cost_version_ids, 1);
  end if;
end $$;

\echo '>> recalculation: a reason is required once a current snapshot already exists; recalculating creates a brand-new version while the prior version remains linked, never rewritten'
do $$
declare
  v_job_order_id uuid := (select jo.id from app.job_orders jo join app.tenants t on t.id = jo.tenant_id where t.slug = 'acmeprofit');
  v_first app.job_profitability_snapshots;
  v_second app.job_profitability_snapshots;
  v_prior app.job_profitability_snapshots;
begin
  select * into v_first from app.job_profitability_snapshots where job_order_id = v_job_order_id and is_current;

  begin
    perform app.calculate_job_profitability(v_job_order_id, null, '00000000-0000-0000-0000-000000023402', 'rep');
    raise exception 'assertion failed: expected job_profitability_recalculation_reason_required with no reason';
  exception
    when check_violation then
      if sqlerrm !~ 'job_profitability_recalculation_reason_required' then raise; end if;
  end;

  v_second := app.calculate_job_profitability(v_job_order_id, 'vendor issued a corrected invoice on shipment A', '00000000-0000-0000-0000-000000023402', 'rep');
  if v_second.version_number <> v_first.version_number + 1 then
    raise exception 'assertion failed: expected version_number to increment';
  end if;

  select * into v_prior from app.job_profitability_snapshots where id = v_first.id;
  if v_prior.is_current then
    raise exception 'assertion failed: expected the prior snapshot to no longer be current';
  end if;
  if v_prior.revenue_amount <> 15000000.00 then
    raise exception 'assertion failed: expected the prior snapshot to remain unchanged (revenue 15000000.00), got %', v_prior.revenue_amount;
  end if;
end $$;

\echo '>> unavailable path: mixed currency between an approved cost and the revenue snapshot makes the whole result unavailable, never a silently-wrong cross-currency subtraction'
do $$
declare
  v_job_order_id uuid := (select jo.id from app.job_orders jo join app.tenants t on t.id = jo.tenant_id where t.slug = 'acmeprofit');
  v_shipment_c app.shipment_orders;
  v_cost_c app.shipment_actual_costs;
  v_vendor_c app.master_records;
  v_snapshot app.job_profitability_snapshots;
begin
  select * into v_vendor_c from app.create_master_record('vendor', (select tenant_id from app.job_orders where id = v_job_order_id), 'VEND-PROFIT-3', 'Northwind Trucking', '[]'::jsonb, '{}'::jsonb, '00000000-0000-0000-0000-000000023401', 'admin');

  select * into v_shipment_c from app.create_shipment_order_from_job(
    v_job_order_id, 'idem-profit-c', null, null, 'ocean_freight', 'sea', 'Jakarta', 'Cirebon',
    now() + interval '1 day', now() + interval '10 days', null, null, null, null, null, null, 'split: profit mixed-currency fixture', '00000000-0000-0000-0000-000000023402', 'rep'
  );
  select * into v_shipment_c from app.confirm_shipment_order(v_shipment_c.id, v_shipment_c.record_version, '00000000-0000-0000-0000-000000023402', 'rep');

  v_cost_c := app.create_actual_cost_draft((select tenant_id from app.shipment_orders where id = v_shipment_c.id), v_shipment_c.id, 'USD', null, '00000000-0000-0000-0000-000000023402', 'rep');
  perform app.add_actual_cost_component(v_cost_c.id, 'other', 'vendor', v_vendor_c.id, null, null, 'Misc USD fee', 1, 'shipment', 100, null, 0, 'idem-profit-cost-c', '00000000-0000-0000-0000-000000023402', 'rep');
  select * into v_cost_c from app.shipment_actual_costs where id = v_cost_c.id;
  v_cost_c := app.submit_actual_cost(v_cost_c.id, v_cost_c.record_version, '00000000-0000-0000-0000-000000023402', 'rep');
  v_cost_c := app.decide_actual_cost(v_cost_c.id, 'approved', null, v_cost_c.record_version, '00000000-0000-0000-0000-000000023402', 'rep');

  v_snapshot := app.calculate_job_profitability(v_job_order_id, 'adding a third shipment with a USD cost', '00000000-0000-0000-0000-000000023402', 'rep');
  if v_snapshot.status <> 'unavailable' or v_snapshot.blocked_reason <> 'mixed_currency' then
    raise exception 'assertion failed: expected status=unavailable/blocked_reason=mixed_currency, got %/%', v_snapshot.status, v_snapshot.blocked_reason;
  end if;
  if v_snapshot.margin_amount is not null then
    raise exception 'assertion failed: expected margin_amount to be null when unavailable';
  end if;
end $$;

\echo '>> app.job_profitability_directory masks revenue/cost/margin amounts without OPS:View margin; record-scope/cross-tenant RLS; schema-privilege defense in depth (anon holds zero EXECUTE on both new functions)'
do $$
declare
  v_job_order_id uuid := (select jo.id from app.job_orders jo join app.tenants t on t.id = jo.tenant_id where t.slug = 'acmeprofit');
  v_snapshot_id uuid := (select id from app.job_profitability_snapshots where job_order_id = v_job_order_id and is_current);
  v_masked boolean;
  v_margin numeric;
  v_count integer;
  v_denied_count integer;
begin
  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000023403", "role": "authenticated"}';
  select margin_masked, margin_amount into v_masked, v_margin from app.job_profitability_directory where id = v_snapshot_id;
  if not v_masked or v_margin is not null then
    raise exception 'assertion failed: expected the restricted actor to see margin_masked=true and margin_amount=null, got %/%', v_masked, v_margin;
  end if;
  reset role;

  -- The current snapshot at this point is the prior block's own status=unavailable
  -- recalculation (margin_amount is legitimately null -- unavailable, not masked).
  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000023402", "role": "authenticated"}';
  select margin_masked, margin_amount into v_masked, v_margin from app.job_profitability_directory where id = v_snapshot_id;
  if v_masked then
    raise exception 'assertion failed: expected the full-access rep to see margin_masked=false (unavailable is not the same as masked), got %', v_masked;
  end if;
  reset role;

  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000023404", "role": "authenticated"}';
  select count(*) into v_count from app.job_profitability_snapshots where job_order_id = v_job_order_id;
  if v_count <> 0 then
    raise exception 'assertion failed: expected the sibling-team outsider to see zero profitability rows via RLS, got %', v_count;
  end if;
  reset role;

  select count(*) into v_denied_count
  from information_schema.routine_privileges
  where routine_schema = 'app' and routine_name in ('has_view_job_margin', 'calculate_job_profitability') and grantee = 'anon';
  if v_denied_count <> 0 then
    raise exception 'assertion failed: expected anon to hold zero EXECUTE grants on the 2 new OPS-179 functions, found %', v_denied_count;
  end if;
end $$;

\echo '>> audit trail: every calculation self-captures a canonical app.audit_logs entry'
do $$
declare
  v_count integer;
begin
  select count(*) into v_count from app.audit_logs where action = 'calculate_job_profitability';
  if v_count < 3 then
    raise exception 'assertion failed: expected at least 3 persisted OPS-179 audit events, found %', v_count;
  end if;
end $$;

-- ============================================================================================
-- ISS-2026-197 labeling fix regression (appended, nothing above this line edited or removed --
-- the mixed-currency fixture and its assertions above are the deliberate, spec-mandated
-- currency-blocking behavior and stay exactly as they are).
--
-- Proves: (1) a freshly calculated Operations snapshot carries revenue_basis='quoted'; (2) the
-- planned-vs-billed distinction is real and independently observable -- an actual issued
-- invoice for the SAME Job Order at a genuinely different amount than the Operations figure
-- (the invoice's own pre-tax billed subtotal vs. the quote's own tax-inclusive total) leaves
-- the Operations snapshot reporting the quoted figure/basis and the Finance fact reporting the
-- billed figure/basis, independently; (3) revenue_basis is never nulled out alongside a
-- blocked (unavailable/mixed_currency) calculation -- it is metadata, not a computed figure;
-- (4) app.job_profitability_directory still returns revenue_basis for a margin-masked actor.
-- ============================================================================================

\echo '>> ISS-2026-197 regression 1/4: revenue_basis is never nulled out alongside a blocked calculation -- the job order left unavailable/mixed_currency by the fixture above still carries revenue_basis=''quoted'' on its current snapshot'
do $$
declare
  v_job_order_id uuid := (select jo.id from app.job_orders jo join app.tenants t on t.id = jo.tenant_id where t.slug = 'acmeprofit');
  v_snapshot app.job_profitability_snapshots;
begin
  select * into v_snapshot from app.job_profitability_snapshots where job_order_id = v_job_order_id and is_current;
  if v_snapshot.status <> 'unavailable' or v_snapshot.blocked_reason <> 'mixed_currency' then
    raise exception 'assertion failed: expected this fixture''s current snapshot to still be the mixed_currency-unavailable one from the block above, got status=%/blocked_reason=%', v_snapshot.status, v_snapshot.blocked_reason;
  end if;
  if v_snapshot.revenue_basis <> 'quoted' then
    raise exception 'assertion failed: expected revenue_basis=''quoted'' on an unavailable/blocked snapshot (metadata, not a computed figure -- never nulled), got %', v_snapshot.revenue_basis;
  end if;
end $$;

\echo '>> ISS-2026-197 regression 2/4: Finance prerequisites for tenant acmeprofit (fiscal calendar, chart of accounts + posting map, a second Job Order''s own OPS:Override grant, and a Finance Manager)'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'acmeprofit');
  v_admin_id uuid := '00000000-0000-0000-0000-000000023401';
  v_override_role uuid;
  v_override_draft app.role_versions;
  v_fin_manager_role uuid;
  v_fin_manager_draft app.role_versions;
  v_account app.finance_accounts;
  v_pm_draft app.config_versions;
begin
  insert into auth.users (id, email) values ('00000000-0000-0000-0000-000000023405', 'financemgr@acmeprofit.test');
  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000023405', 'financemgr@acmeprofit.test', 'Profit Finance Manager', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'financemgr@acmeprofit.test'), 'active', 'onboarded', 'tester');

  -- The existing rep (23402) already holds OPS:Edit/View margin from the setup block above --
  -- override_billing_readiness additionally requires OPS:Override, a distinct grant that
  -- role never carried. A second, additive role assignment on the SAME actor (role
  -- assignments are additive, not a single slot) rather than widening the original role.
  v_override_role := (app.create_role(v_tenant1, 'Profit Rep Billing Override', 'adds OPS:Override for the billing-readiness handoff regression fixture', 'tester')).id;
  v_override_draft := app.create_role_version(v_override_role, 'tester');
  perform app.set_role_version_permissions(v_override_draft.id, array(select id from app.permissions where resource_module_code = 'OPS' and action = 'Override'), 'tester');
  perform app.publish_role_version(v_override_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_override_role and status = 'published'), '00000000-0000-0000-0000-000000023402', v_admin_id, 'tester');

  v_fin_manager_role := (app.create_role(v_tenant1, 'Profit Finance Manager', 'FIN Create/Edit/Approve/View + View margin, for the ISS-2026-197 billed-vs-quoted regression', 'tester')).id;
  v_fin_manager_draft := app.create_role_version(v_fin_manager_role, 'tester');
  perform app.set_role_version_permissions(v_fin_manager_draft.id, array(select id from app.permissions where resource_module_code = 'FIN' and action in ('Create', 'Edit', 'Approve', 'View', 'View margin')), 'tester');
  perform app.publish_role_version(v_fin_manager_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_fin_manager_role and status = 'published'), '00000000-0000-0000-0000-000000023405', v_admin_id, 'tester');

  perform app.generate_finance_fiscal_calendar(v_tenant1, null, 'FY2026-OPS197', 'FY2026 Monthly (OPS-197 regression)', '2026-01-01'::date, 12, '00000000-0000-0000-0000-000000023405', 'financemgr');

  select * into v_account from app.create_finance_account_draft(v_tenant1, null, 'AR-CTRL-197', 'Accounts Receivable Control', 'asset', 'debit', null, false, null, '00000000-0000-0000-0000-000000023405', 'financemgr');
  perform app.activate_finance_account(v_account.id, v_account.record_version, '00000000-0000-0000-0000-000000023405', 'financemgr');
  select * into v_account from app.create_finance_account_draft(v_tenant1, null, 'REV-DEFAULT-197', 'Default Revenue', 'revenue', 'credit', null, false, null, '00000000-0000-0000-0000-000000023405', 'financemgr');
  perform app.activate_finance_account(v_account.id, v_account.record_version, '00000000-0000-0000-0000-000000023405', 'financemgr');
  select * into v_account from app.create_finance_account_draft(v_tenant1, null, 'TAX-PAY-DEF-197', 'Default Tax Payable', 'liability', 'credit', null, false, null, '00000000-0000-0000-0000-000000023405', 'financemgr');
  perform app.activate_finance_account(v_account.id, v_account.record_version, '00000000-0000-0000-0000-000000023405', 'financemgr');

  -- app.create_finance_config_draft's own tenant-scope authority check requires tenant_admin
  -- (mirrors FIN-212's own "FIN-202 fixture prerequisite" step in finance-job-profitability.sql).
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000023405', 'tenant_admin', v_tenant1, null, 'tester');

  select * into v_pm_draft from app.create_finance_config_draft('finance_posting_map', v_tenant1, 'tenant', null, '00000000-0000-0000-0000-000000023405', 'financemgr');
  perform app.set_finance_config_items(v_pm_draft.id, jsonb_build_array(
    jsonb_build_object('key', 'ar_control', 'value', jsonb_build_object('accountCodeRef', 'AR-CTRL-197')),
    jsonb_build_object('key', 'revenue_default', 'value', jsonb_build_object('accountCodeRef', 'REV-DEFAULT-197')),
    jsonb_build_object('key', 'tax_payable_default', 'value', jsonb_build_object('accountCodeRef', 'TAX-PAY-DEF-197'))
  ), '00000000-0000-0000-0000-000000023405', 'financemgr');
  perform app.publish_finance_config_version(v_pm_draft.id, '00000000-0000-0000-0000-000000023405', null, 'financemgr');
end $$;

\echo '>> ISS-2026-197 regression 3/4 + 4/4: a second Job Order (quote 20,000,000 IDR + 10% tax = 22,000,000 tax-inclusive total; one approved 5,000,000 IDR actual cost) proves the quoted/billed split -- Operations reports the quote''s own tax-inclusive total (22,000,000, ''quoted''), Finance reports the invoice''s own pre-tax billed subtotal (20,000,000, ''billed''), independently, from the SAME Job Order and the SAME approved cost; and app.job_profitability_directory still returns revenue_basis for a margin-masked actor'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'acmeprofit');
  v_team_a uuid := (select id from app.org_units where tenant_id = (select id from app.tenants where slug = 'acmeprofit') and code = 'ACMEPROFIT-TEAM-A');
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
  v_account app.accounts;
  v_handoff app.job_order_handoffs;
  v_job2 app.job_orders;
  v_vendor app.master_records;
  v_shipment app.shipment_orders;
  v_cost app.shipment_actual_costs;
  v_evaluation app.billing_readiness_evaluations;
  v_br_handoff app.billing_readiness_handoffs;
  v_invoice app.finance_invoices;
  v_ops_snapshot app.job_profitability_snapshots;
  v_fin_fact app.finance_job_profitability_facts;
  v_masked boolean;
  v_basis text;
begin
  insert into auth.users (id, email) values ('00000000-0000-0000-0000-000000023406', 'jill@profittest2.test') on conflict do nothing;

  perform app.capture_lead(v_tenant1, 'manual', null, 'Profit Test Co 2', 'Jill Profit', 'jill@profittest2.test', '0813',
    '00000000-0000-0000-0000-000000023402', v_team_a, '00000000-0000-0000-0000-000000023402', 'tester');
  select * into v_lead from app.leads where email = 'jill@profittest2.test';
  perform app.qualify_lead(v_lead.id, v_lead.record_version, '00000000-0000-0000-0000-000000023402', 'tester');
  select * into v_lead from app.leads where id = v_lead.id;
  perform app.convert_lead_to_prospect(v_lead.id, 'Profit Test Co 2', 'PFT2', '11.111.111.6-666.000',
    jsonb_build_object('line1', 'Jl. Rasuna Said 6', 'city', 'Jakarta', 'country', 'ID'),
    '00000000-0000-0000-0000-000000023402', 'tester');
  select * into v_prospect from app.prospects where lead_id = v_lead.id;

  select * into v_contact from app.create_contact(v_tenant1, 'Jill Profit Ops', 'Procurement Lead', 'jill@profittest2.test', '0813', '00000000-0000-0000-0000-000000023402', v_team_a, '00000000-0000-0000-0000-000000023402', 'tester');
  perform app.link_contact_to_record(v_contact.id, 'prospect', v_prospect.id, 'primary', true, '00000000-0000-0000-0000-000000023402', 'tester');

  select * into v_opportunity from app.create_opportunity(
    v_tenant1, v_prospect.id, 'Profit test lane 2 (OPS-197 regression)',
    jsonb_build_object('service_type', 'ocean_freight', 'cargo_description', 'General cargo', 'origin', 'Jakarta', 'destination', 'Semarang', 'target_ready_date', '2026-08-01'),
    '00000000-0000-0000-0000-000000023402', v_team_a, '00000000-0000-0000-0000-000000023402', 'tester'
  );
  select * into v_request from app.request_costing(v_opportunity.id, '[]'::jsonb, null, '00000000-0000-0000-0000-000000023402', 'tester');
  select * into v_rate from app.create_rate_version(
    v_tenant1, 'VENDOR-PROFIT-197', 'Contoso Ocean Line', 'ocean_freight', 'FCL', 'Jakarta', 'Semarang', '20ft',
    null, null, null, null, 'IDR', 10000000, null, '[]'::jsonb, now(), null, null, '00000000-0000-0000-0000-000000023401', 'tester'
  );
  perform app.approve_rate_version(v_rate.id, v_rate.record_version, '00000000-0000-0000-0000-000000023401', 'tester');
  select * into v_selection from app.select_vendor_rate(v_request.id, v_rate.id, false, null, null, null, '00000000-0000-0000-0000-000000023402', 'tester');

  -- Reuses the margin rule the file's own initial setup block already published for this tenant.
  perform app.calculate_margin(v_selection.id, 20000000, 'IDR', 0, '00000000-0000-0000-0000-000000023402', 'tester');
  select id into v_calc_id from app.margin_calculations where rate_selection_id = v_selection.id and is_current;

  -- 20,000,000 gross, 0% discount, 10% tax -> subtotal 20,000,000 / total 22,000,000: the
  -- quote's own tax-inclusive total (Operations' basis) genuinely differs from the invoice's
  -- own pre-tax billed subtotal (Finance's basis) -- a real product distinction (tax is a
  -- pass-through liability, excluded from Finance's billed revenue per FIN-212's own header),
  -- not a fabricated one.
  select * into v_quote from app.create_quotation_draft(v_tenant1, v_opportunity.id, 'IDR', now() + interval '14 days', v_contact.id, null, null, '00000000-0000-0000-0000-000000023402', 'tester');
  perform app.add_quotation_line(v_quote.id, v_quote.record_version, 'service', 'Ocean freight profit lane 2', v_calc_id, 1, 20000000, 0, 10, '00000000-0000-0000-0000-000000023402', 'tester');
  select * into v_quote from app.quotations where id = v_quote.id;
  if v_quote.subtotal_amount <> 20000000.00 or v_quote.total_amount <> 22000000.00 then
    raise exception 'assertion failed: expected quotation subtotal 20000000.00 / total 22000000.00, got %/%', v_quote.subtotal_amount, v_quote.total_amount;
  end if;
  perform app.submit_quotation(v_quote.id, v_quote.record_version, '00000000-0000-0000-0000-000000023402', 'tester');
  select * into v_send from app.send_quotation_for_acceptance(v_quote.id, null, 'email', '00000000-0000-0000-0000-000000023402', 'tester');
  perform app.record_quotation_customer_decision(v_send.raw_token, 'accepted', 'Jill Profit Ops', null, null, null, null, null);
  select * into v_quote from app.quotations where id = v_quote.id;
  select * into v_account from app.convert_quotation_to_account(v_quote.id, null, null, '00000000-0000-0000-0000-000000023402', 'rep');
  select * into v_handoff from app.prepare_job_order_handoff(v_quote.id, '00000000-0000-0000-0000-000000023402', 'rep');

  select * into v_job2 from app.prepare_job_order(v_handoff.id, '00000000-0000-0000-0000-000000023402', 'rep');
  select * into v_job2 from app.confirm_job_order(v_job2.id, v_job2.record_version, '00000000-0000-0000-0000-000000023402', 'rep');

  select * into v_vendor from app.create_master_record('vendor', v_tenant1, 'VEND-PROFIT-197', 'Contoso Trucking 197', '[]'::jsonb, '{}'::jsonb, '00000000-0000-0000-0000-000000023401', 'admin');

  select * into v_shipment from app.create_shipment_order_from_job(
    v_job2.id, 'idem-profit-197-a', null, null, 'ocean_freight', 'sea', 'Jakarta', 'Semarang',
    now() + interval '1 day', now() + interval '10 days', null, null, null, null, null, null, null, '00000000-0000-0000-0000-000000023402', 'rep'
  );
  select * into v_shipment from app.confirm_shipment_order(v_shipment.id, v_shipment.record_version, '00000000-0000-0000-0000-000000023402', 'rep');
  select * into v_shipment from app.transition_shipment_order(v_shipment.id, 'planned', v_shipment.record_version, null, null, 'idem-profit-197-a-planned', '00000000-0000-0000-0000-000000023402', 'rep');
  select * into v_shipment from app.transition_shipment_order(v_shipment.id, 'assigned', v_shipment.record_version, null, null, 'idem-profit-197-a-assigned', '00000000-0000-0000-0000-000000023402', 'rep');
  perform app.assign_resource(v_shipment.id, 'vendor', v_vendor.id, '00000000-0000-0000-0000-000000023402', 'rep');

  v_cost := app.create_actual_cost_draft(v_tenant1, v_shipment.id, 'IDR', null, '00000000-0000-0000-0000-000000023402', 'rep');
  perform app.add_actual_cost_component(v_cost.id, 'freight', 'vendor', v_vendor.id, null, null, 'Ocean freight', 1, 'shipment', 5000000, null, 0, 'idem-profit-197-cost-a', '00000000-0000-0000-0000-000000023402', 'rep');
  select * into v_cost from app.shipment_actual_costs where id = v_cost.id;
  v_cost := app.submit_actual_cost(v_cost.id, v_cost.record_version, '00000000-0000-0000-0000-000000023402', 'rep');
  v_cost := app.decide_actual_cost(v_cost.id, 'approved', null, v_cost.record_version, '00000000-0000-0000-0000-000000023402', 'rep');

  -- Operations: a freshly calculated snapshot carries the fixed revenue_basis='quoted' marker,
  -- and its revenue is the quote's own tax-inclusive total (22,000,000), not the invoice's own
  -- pre-tax billed subtotal that Finance will report below.
  v_ops_snapshot := app.calculate_job_profitability(v_job2.id, null, '00000000-0000-0000-0000-000000023402', 'rep');
  if v_ops_snapshot.status <> 'calculated' or v_ops_snapshot.revenue_amount <> 22000000.00 or v_ops_snapshot.cost_amount <> 5000000.00 or v_ops_snapshot.margin_amount <> 17000000.00 then
    raise exception 'assertion failed: expected Operations revenue 22000000.00 (quote total, tax-inclusive) / cost 5000000.00 / margin 17000000.00, got %/%/%', v_ops_snapshot.revenue_amount, v_ops_snapshot.cost_amount, v_ops_snapshot.margin_amount;
  end if;
  if v_ops_snapshot.revenue_basis <> 'quoted' then
    raise exception 'assertion failed: expected Operations revenue_basis=''quoted'', got %', v_ops_snapshot.revenue_basis;
  end if;

  -- Finance: issue a real invoice for the SAME Job Order. prepare_finance_invoice_from_
  -- readiness derives subtotal_amount from subtotalAmount-discountAmount (20,000,000,
  -- pre-tax) -- genuinely, structurally different from the 22,000,000 Operations just
  -- reported above, with zero special-casing needed to make it so.
  select * into v_evaluation from app.evaluate_billing_readiness(v_job2.id, null, '00000000-0000-0000-0000-000000023402', 'rep');
  select * into v_evaluation from app.override_billing_readiness(v_job2.id, v_evaluation.record_version, 'ISS-2026-197 regression: bypassing full evidence chain, out of this fixture''s own scope', '00000000-0000-0000-0000-000000023402', 'rep');
  select * into v_br_handoff from app.handoff_billing_readiness(v_job2.id, 'ops197-fixture-handoff', '00000000-0000-0000-0000-000000023402', 'rep');

  select * into v_invoice from app.prepare_finance_invoice_from_readiness(v_tenant1, v_br_handoff.id, 30, null, '00000000-0000-0000-0000-000000023405', 'financemgr');
  if v_invoice.subtotal_amount <> 20000000.00 then
    raise exception 'assertion failed: expected invoice subtotal 20000000.00 (pre-tax, discount-adjusted), got %', v_invoice.subtotal_amount;
  end if;
  select * into v_invoice from app.submit_finance_invoice_for_approval(v_invoice.id, v_invoice.record_version, '00000000-0000-0000-0000-000000023405', 'financemgr');
  select * into v_invoice from app.approve_finance_invoice(v_invoice.id, v_invoice.record_version, '00000000-0000-0000-0000-000000023405', 'financemgr');
  perform app.issue_finance_invoice(v_invoice.id, v_invoice.record_version, '2026-03-01'::date, '00000000-0000-0000-0000-000000023405', 'financemgr');

  v_fin_fact := app.calculate_finance_job_profitability(v_job2.id, null, '00000000-0000-0000-0000-000000023405', 'financemgr');
  if v_fin_fact.status <> 'calculated' or v_fin_fact.revenue_amount <> 20000000.00 or v_fin_fact.cost_amount <> 5000000.00 or v_fin_fact.profit_amount <> 15000000.00 then
    raise exception 'assertion failed: expected Finance revenue 20000000.00 (billed subtotal) / cost 5000000.00 / profit 15000000.00, got %/%/%', v_fin_fact.revenue_amount, v_fin_fact.cost_amount, v_fin_fact.profit_amount;
  end if;
  if v_fin_fact.revenue_basis <> 'billed' then
    raise exception 'assertion failed: expected Finance revenue_basis=''billed'', got %', v_fin_fact.revenue_basis;
  end if;

  -- The two facts are independent, stored rows -- calculating Finance's did not touch
  -- Operations' own already-current snapshot for the identical Job Order.
  select * into v_ops_snapshot from app.job_profitability_snapshots where job_order_id = v_job2.id and is_current;
  if v_ops_snapshot.revenue_amount <> 22000000.00 or v_ops_snapshot.revenue_basis <> 'quoted' then
    raise exception 'assertion failed: expected the Operations snapshot to remain unchanged (revenue 22000000.00, basis quoted) after the independent Finance calculation, got %/%', v_ops_snapshot.revenue_amount, v_ops_snapshot.revenue_basis;
  end if;

  -- regression 4/4: app.job_profitability_directory still returns revenue_basis for a
  -- margin-masked actor (the restricted actor from the setup block above, no OPS:View margin).
  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000023403", "role": "authenticated"}';
  select margin_masked, revenue_basis into v_masked, v_basis from app.job_profitability_directory where job_order_id = v_job2.id and is_current;
  reset role;
  if not v_masked then
    raise exception 'assertion failed: expected the restricted actor to see margin_masked=true for this row';
  end if;
  if v_basis <> 'quoted' then
    raise exception 'assertion failed: expected revenue_basis=''quoted'' to still be visible to a margin-masked actor (metadata, never masked), got %', v_basis;
  end if;
end $$;
