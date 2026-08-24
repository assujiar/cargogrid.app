-- Real, executable test evidence for OPS-184 (Operations Transaction Lineage,
-- CG-S8-OPS-018) -- run via `pnpm run db:test` against a real, disposable Postgres
-- database.

\set ON_ERROR_STOP on

\echo '>> setup: one tenant, a company/team-a/team-b org hierarchy, a bootstrap tenant-admin, a rep (COM full + OPS full incl Override), a restricted actor (OPS View/Edit only, no Override), a sibling-team outsider (full grants incl Override, wrong record scope), a credit approver -- two full accepted-quote funnels (A drives a full shipment/ePOD/cost/profitability/billing-readiness chain, B stays a bare confirmed Job Order used only as the corrective override''s new source)'
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
  v_approver_role uuid;
  v_approver_draft app.role_versions;
  v_config_draft app.config_versions;
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
  v_profile app.credit_profiles;
  v_step_id uuid;
  v_handoff app.job_order_handoffs;
  v_opportunity_b app.opportunities;
  v_request_b app.costing_requests;
  v_rate_b app.vendor_rate_versions;
  v_selection_b app.rate_selections;
  v_calc_id_b uuid;
  v_quote_b app.quotations;
  v_send_b record;
  v_account_b app.accounts;
  v_profile_b app.credit_profiles;
  v_step_id_b uuid;
  v_handoff_b app.job_order_handoffs;
begin
  insert into auth.users (id, email) values
    ('00000000-0000-0000-0000-000000023901', 'admin@acmeopslineage.test'),
    ('00000000-0000-0000-0000-000000023902', 'rep@acmeopslineage.test'),
    ('00000000-0000-0000-0000-000000023903', 'restricted@acmeopslineage.test'),
    ('00000000-0000-0000-0000-000000023904', 'outsider@acmeopslineage.test'),
    ('00000000-0000-0000-0000-000000023905', 'approver@acmeopslineage.test'),
    ('00000000-0000-0000-0000-000000023906', 'supreme@acmeopslineage.test');

  perform app.grant_principal_membership('00000000-0000-0000-0000-000000023906', 'supreme_admin', null, null, 'tester');

  perform app.provision_tenant('acmeopslineage', 'Acme Ops Lineage Co', 'idem-acmeopslineage', 'tester');
  v_tenant1 := (select id from app.tenants where slug = 'acmeopslineage');
  perform app.transition_tenant_status(v_tenant1, 'active', 'setup', 'tester');

  perform app.create_org_unit(v_tenant1, 'company', null, 'ACMEOPSLINEAGE-CO', 'Acme Ops Lineage Co', 'tester');
  perform app.create_org_unit(v_tenant1, 'department', (select id from app.org_units where tenant_id = v_tenant1 and code = 'ACMEOPSLINEAGE-CO'), 'ACMEOPSLINEAGE-TEAM-A', 'Team A', 'tester');
  v_team_a := (select id from app.org_units where tenant_id = v_tenant1 and code = 'ACMEOPSLINEAGE-TEAM-A');
  perform app.create_org_unit(v_tenant1, 'department', (select id from app.org_units where tenant_id = v_tenant1 and code = 'ACMEOPSLINEAGE-CO'), 'ACMEOPSLINEAGE-TEAM-B', 'Team B', 'tester');
  v_team_b := (select id from app.org_units where tenant_id = v_tenant1 and code = 'ACMEOPSLINEAGE-TEAM-B');

  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000023901', 'admin@acmeopslineage.test', 'Lineage Admin', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'admin@acmeopslineage.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000023901', 'tenant_admin', v_tenant1, null, 'tester');
  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000023902', 'rep@acmeopslineage.test', 'Lineage Rep', v_team_a, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'rep@acmeopslineage.test'), 'active', 'onboarded', 'tester');
  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000023903', 'restricted@acmeopslineage.test', 'Restricted Actor', v_team_a, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'restricted@acmeopslineage.test'), 'active', 'onboarded', 'tester');
  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000023904', 'outsider@acmeopslineage.test', 'Team B Outsider', v_team_b, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'outsider@acmeopslineage.test'), 'active', 'onboarded', 'tester');
  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000023905', 'approver@acmeopslineage.test', 'Credit Approver', v_team_a, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'approver@acmeopslineage.test'), 'active', 'onboarded', 'tester');

  v_rep_role := (app.create_role(v_tenant1, 'Lineage Rep', 'full commercial + ops grants incl OPS:Override', 'tester')).id;
  v_rep_draft := app.create_role_version(v_rep_role, 'tester');
  perform app.set_role_version_permissions(
    v_rep_draft.id,
    array(select id from app.permissions where (resource_module_code = 'COM' and action in ('Create', 'Edit', 'Approve', 'View', 'View cost'))
      or (resource_module_code = 'OPS' and action in ('Create', 'Edit', 'Assign', 'View', 'View cost', 'View margin', 'Override'))),
    'tester'
  );
  perform app.publish_role_version(v_rep_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_rep_role and status = 'published'), '00000000-0000-0000-0000-000000023902', '00000000-0000-0000-0000-000000023901', 'tester');

  v_restricted_role := (app.create_role(v_tenant1, 'Lineage Restricted', 'OPS Create/Edit/View only, no OPS:Override', 'tester')).id;
  v_restricted_draft := app.create_role_version(v_restricted_role, 'tester');
  perform app.set_role_version_permissions(
    v_restricted_draft.id,
    array(select id from app.permissions where resource_module_code = 'OPS' and action in ('Create', 'Edit', 'View')),
    'tester'
  );
  perform app.publish_role_version(v_restricted_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_restricted_role and status = 'published'), '00000000-0000-0000-0000-000000023903', '00000000-0000-0000-0000-000000023903', 'tester');

  v_outsider_role := (app.create_role(v_tenant1, 'Lineage Outsider', 'sibling team, full grants incl OPS:Override', 'tester')).id;
  v_outsider_draft := app.create_role_version(v_outsider_role, 'tester');
  perform app.set_role_version_permissions(
    v_outsider_draft.id,
    array(select id from app.permissions where (resource_module_code = 'COM' and action in ('Create', 'Edit', 'View'))
      or (resource_module_code = 'OPS' and action in ('Create', 'Edit', 'Assign', 'View', 'View cost', 'Override'))),
    'tester'
  );
  perform app.publish_role_version(v_outsider_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_outsider_role and status = 'published'), '00000000-0000-0000-0000-000000023904', '00000000-0000-0000-0000-000000023901', 'tester');

  v_approver_role := (app.create_role(v_tenant1, 'Lineage Credit Approver', 'decides the routed credit-profile approval request', 'tester')).id;
  v_approver_draft := app.create_role_version(v_approver_role, 'tester');
  perform app.set_role_version_permissions(v_approver_draft.id, array(select id from app.permissions where resource_module_code = 'COM' and action in ('Approve', 'View')), 'tester');
  perform app.publish_role_version(v_approver_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_approver_role and status = 'published'), '00000000-0000-0000-0000-000000023905', '00000000-0000-0000-0000-000000023901', 'tester');

  select * into v_config_draft from app.create_config_draft('approval', v_tenant1, 'tenant', null, '00000000-0000-0000-0000-000000023901', 'tenant admin');
  perform app.set_config_items(v_config_draft.id, jsonb_build_array(
    jsonb_build_object('key', 'pattern', 'value', 'sequential'),
    jsonb_build_object('key', 'steps', 'value', jsonb_build_array(
      jsonb_build_object('step_order', 1, 'approver_type', 'role', 'role_id', v_approver_role::text, 'required_approvals', 1)
    )),
    jsonb_build_object('key', 'allow_self_approval', 'value', false)
  ), '00000000-0000-0000-0000-000000023901', 'tenant admin');
  perform app.publish_approval_definition(v_config_draft.id, '00000000-0000-0000-0000-000000023901', null, 'tenant admin');

  -- Funnel A: full chain through billing readiness.
  perform app.capture_lead(v_tenant1, 'manual', null, 'Lineage Test Co A', 'Jane Lineage', 'jane@lineagetest.test', '0811',
    '00000000-0000-0000-0000-000000023902', v_team_a, '00000000-0000-0000-0000-000000023902', 'tester');
  select * into v_lead from app.leads where email = 'jane@lineagetest.test';
  perform app.qualify_lead(v_lead.id, v_lead.record_version, '00000000-0000-0000-0000-000000023902', 'tester');
  select * into v_lead from app.leads where id = v_lead.id;
  perform app.convert_lead_to_prospect(v_lead.id, 'Lineage Test Co A', 'LTA', '11.111.111.7-777.000',
    jsonb_build_object('line1', 'Jl. Sudirman 7', 'city', 'Jakarta', 'country', 'ID'),
    '00000000-0000-0000-0000-000000023902', 'tester');
  select * into v_prospect from app.prospects where lead_id = v_lead.id;

  select * into v_contact from app.create_contact(v_tenant1, 'Jane Lineage Ops', 'Procurement Lead', 'jane@lineagetest.test', '0811', '00000000-0000-0000-0000-000000023902', v_team_a, '00000000-0000-0000-0000-000000023902', 'tester');
  perform app.link_contact_to_record(v_contact.id, 'prospect', v_prospect.id, 'primary', true, '00000000-0000-0000-0000-000000023902', 'tester');

  select * into v_opportunity from app.create_opportunity(
    v_tenant1, v_prospect.id, 'Lineage test lane A',
    jsonb_build_object('service_type', 'ocean_freight', 'cargo_description', 'General cargo', 'origin', 'Jakarta', 'destination', 'Semarang', 'target_ready_date', '2026-08-01'),
    '00000000-0000-0000-0000-000000023902', v_team_a, '00000000-0000-0000-0000-000000023902', 'tester'
  );
  select * into v_request from app.request_costing(v_opportunity.id, '[]'::jsonb, null, '00000000-0000-0000-0000-000000023902', 'tester');
  select * into v_rate from app.create_rate_version(
    v_tenant1, 'VENDOR-LINEAGE-A', 'Contoso Ocean Line', 'ocean_freight', 'FCL', 'Jakarta', 'Semarang', '20ft',
    null, null, null, null, 'IDR', 8000000, null, '[]'::jsonb, now(), null, null, '00000000-0000-0000-0000-000000023901', 'tester'
  );
  perform app.approve_rate_version(v_rate.id, v_rate.record_version, '00000000-0000-0000-0000-000000023901', 'tester');
  select * into v_selection from app.select_vendor_rate(v_request.id, v_rate.id, false, null, null, null, '00000000-0000-0000-0000-000000023902', 'tester');

  select * into v_rule from app.create_margin_rule_version(v_tenant1, 20.00, 'half_up', '00000000-0000-0000-0000-000000023902', 'tester');
  perform app.publish_margin_rule_version(v_rule.id, v_rule.record_version, null, '00000000-0000-0000-0000-000000023902', 'tester');
  perform app.calculate_margin(v_selection.id, 12000000, 'IDR', 0, '00000000-0000-0000-0000-000000023902', 'tester');
  select id into v_calc_id from app.margin_calculations where rate_selection_id = v_selection.id and is_current;

  select * into v_quote from app.create_quotation_draft(v_tenant1, v_opportunity.id, 'IDR', now() + interval '14 days', v_contact.id, null, null, '00000000-0000-0000-0000-000000023902', 'tester');
  perform app.add_quotation_line(v_quote.id, v_quote.record_version, 'service', 'Ocean freight lineage lane A', v_calc_id, 1, 12000000, 0, 0, '00000000-0000-0000-0000-000000023902', 'tester');
  select * into v_quote from app.quotations where id = v_quote.id;
  perform app.submit_quotation(v_quote.id, v_quote.record_version, '00000000-0000-0000-0000-000000023902', 'tester');
  select * into v_send from app.send_quotation_for_acceptance(v_quote.id, null, 'email', '00000000-0000-0000-0000-000000023902', 'tester');
  perform app.record_quotation_customer_decision(v_send.raw_token, 'accepted', 'Jane Lineage Ops', null, null, null, null, null);
  select * into v_quote from app.quotations where id = v_quote.id;
  select * into v_account from app.convert_quotation_to_account(v_quote.id, null, null, '00000000-0000-0000-0000-000000023902', 'rep');

  v_profile := app.request_customer_credit_profile(v_tenant1, v_account.id, 'IDR', 20000000, '00000000-0000-0000-0000-000000023902', 'rep');
  select rs.id into v_step_id from app.approval_request_steps rs where rs.request_id = v_profile.approval_request_id and rs.step_order = 1;
  v_profile := app.decide_credit_profile_approval_step(v_step_id, 'approved', 'Approved for lineage fixture A', now(), '00000000-0000-0000-0000-000000023905', 'approver');

  select * into v_handoff from app.prepare_job_order_handoff(v_quote.id, '00000000-0000-0000-0000-000000023902', 'rep');

  -- Funnel B: a second, independent accepted quote that becomes a second Job Order --
  -- used only as the corrective override''s new source in the traversal/override test
  -- block below (a realistic "this shipment actually also belongs to consolidation job B"
  -- correction), never given its own shipment/ePOD/cost/profitability/billing-readiness.
  perform app.capture_lead(v_tenant1, 'manual', null, 'Lineage Test Co B', 'Budi Lineage', 'budi@lineagetest.test', '0812',
    '00000000-0000-0000-0000-000000023902', v_team_a, '00000000-0000-0000-0000-000000023902', 'tester');
  select * into v_lead from app.leads where email = 'budi@lineagetest.test';
  perform app.qualify_lead(v_lead.id, v_lead.record_version, '00000000-0000-0000-0000-000000023902', 'tester');
  select * into v_lead from app.leads where id = v_lead.id;
  perform app.convert_lead_to_prospect(v_lead.id, 'Lineage Test Co B', 'LTB', '11.111.111.8-888.000',
    jsonb_build_object('line1', 'Jl. Sudirman 8', 'city', 'Jakarta', 'country', 'ID'),
    '00000000-0000-0000-0000-000000023902', 'tester');
  select * into v_prospect from app.prospects where lead_id = v_lead.id;

  select * into v_contact from app.create_contact(v_tenant1, 'Budi Lineage Ops', 'Procurement Lead', 'budi@lineagetest.test', '0812', '00000000-0000-0000-0000-000000023902', v_team_a, '00000000-0000-0000-0000-000000023902', 'tester');
  perform app.link_contact_to_record(v_contact.id, 'prospect', v_prospect.id, 'primary', true, '00000000-0000-0000-0000-000000023902', 'tester');

  select * into v_opportunity_b from app.create_opportunity(
    v_tenant1, v_prospect.id, 'Lineage test lane B',
    jsonb_build_object('service_type', 'ocean_freight', 'cargo_description', 'General cargo', 'origin', 'Jakarta', 'destination', 'Cirebon', 'target_ready_date', '2026-08-01'),
    '00000000-0000-0000-0000-000000023902', v_team_a, '00000000-0000-0000-0000-000000023902', 'tester'
  );
  select * into v_request_b from app.request_costing(v_opportunity_b.id, '[]'::jsonb, null, '00000000-0000-0000-0000-000000023902', 'tester');
  select * into v_rate_b from app.create_rate_version(
    v_tenant1, 'VENDOR-LINEAGE-B', 'Fabrikam Ocean Line', 'ocean_freight', 'FCL', 'Jakarta', 'Cirebon', '20ft',
    null, null, null, null, 'IDR', 4000000, null, '[]'::jsonb, now(), null, null, '00000000-0000-0000-0000-000000023901', 'tester'
  );
  perform app.approve_rate_version(v_rate_b.id, v_rate_b.record_version, '00000000-0000-0000-0000-000000023901', 'tester');
  select * into v_selection_b from app.select_vendor_rate(v_request_b.id, v_rate_b.id, false, null, null, null, '00000000-0000-0000-0000-000000023902', 'tester');
  perform app.calculate_margin(v_selection_b.id, 6000000, 'IDR', 0, '00000000-0000-0000-0000-000000023902', 'tester');
  select id into v_calc_id_b from app.margin_calculations where rate_selection_id = v_selection_b.id and is_current;

  select * into v_quote_b from app.create_quotation_draft(v_tenant1, v_opportunity_b.id, 'IDR', now() + interval '14 days', v_contact.id, null, null, '00000000-0000-0000-0000-000000023902', 'tester');
  perform app.add_quotation_line(v_quote_b.id, v_quote_b.record_version, 'service', 'Ocean freight lineage lane B', v_calc_id_b, 1, 6000000, 0, 0, '00000000-0000-0000-0000-000000023902', 'tester');
  select * into v_quote_b from app.quotations where id = v_quote_b.id;
  perform app.submit_quotation(v_quote_b.id, v_quote_b.record_version, '00000000-0000-0000-0000-000000023902', 'tester');
  select * into v_send_b from app.send_quotation_for_acceptance(v_quote_b.id, null, 'email', '00000000-0000-0000-0000-000000023902', 'tester');
  perform app.record_quotation_customer_decision(v_send_b.raw_token, 'accepted', 'Budi Lineage Ops', null, null, null, null, null);
  select * into v_quote_b from app.quotations where id = v_quote_b.id;
  select * into v_account_b from app.convert_quotation_to_account(v_quote_b.id, null, null, '00000000-0000-0000-0000-000000023902', 'rep');

  v_profile_b := app.request_customer_credit_profile(v_tenant1, v_account_b.id, 'IDR', 20000000, '00000000-0000-0000-0000-000000023902', 'rep');
  select rs.id into v_step_id_b from app.approval_request_steps rs where rs.request_id = v_profile_b.approval_request_id and rs.step_order = 1;
  v_profile_b := app.decide_credit_profile_approval_step(v_step_id_b, 'approved', 'Approved for lineage fixture B', now(), '00000000-0000-0000-0000-000000023905', 'approver');

  select * into v_handoff_b from app.prepare_job_order_handoff(v_quote_b.id, '00000000-0000-0000-0000-000000023902', 'rep');
end $$;

\echo '>> confirming both handoffs into Job Orders auto-captures two quote_to_job lineage edges (hash = the handoff''s own payload_hash); confirming Job A and pinning one fully-compliant Shipment Order auto-captures job_to_shipment; ePOD + actual cost + profitability + billing-readiness auto-capture their own edges in turn -- zero manual RPC call to any lineage function anywhere in this block'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'acmeopslineage');
  v_job_a app.job_orders;
  v_job_b app.job_orders;
  v_handoffs uuid[];
  v_handoff_a_id uuid;
  v_handoff_b_id uuid;
  v_vendor app.master_records;
  v_shipment app.shipment_orders;
  v_req_def app.document_requirement_definitions;
  v_config_draft app.config_versions;
  v_file app.files;
  v_item app.shipment_document_checklist_items;
  v_capture app.epod_captures;
  v_cost app.shipment_actual_costs;
  v_profitability app.job_profitability_snapshots;
  v_billing app.billing_readiness_evaluations;
  v_edge_count integer;
  v_hash text;
  v_expected_hash text;
begin
  select array_agg(id order by created_at) into v_handoffs from app.job_order_handoffs where tenant_id = v_tenant1;
  v_handoff_a_id := v_handoffs[1];
  v_handoff_b_id := v_handoffs[2];

  v_job_a := app.prepare_job_order(v_handoff_a_id, '00000000-0000-0000-0000-000000023902', 'rep');
  v_job_b := app.prepare_job_order(v_handoff_b_id, '00000000-0000-0000-0000-000000023902', 'rep');

  select count(*) into v_edge_count from app.transaction_lineage_edges where tenant_id = v_tenant1 and relation_type = 'quote_to_job';
  if v_edge_count <> 2 then
    raise exception 'assertion failed: expected exactly 2 auto-captured quote_to_job edges, got %', v_edge_count;
  end if;

  select source_version_hash into v_hash from app.transaction_lineage_edges where tenant_id = v_tenant1 and relation_type = 'quote_to_job' and target_id = v_job_a.id;
  select payload_hash into v_expected_hash from app.job_order_handoffs where id = v_handoff_a_id;
  if v_hash is null or v_hash <> v_expected_hash then
    raise exception 'assertion failed: expected quote_to_job edge hash to equal the handoff''s own payload_hash, got %/%', v_hash, v_expected_hash;
  end if;

  v_job_a := app.confirm_job_order(v_job_a.id, v_job_a.record_version, '00000000-0000-0000-0000-000000023902', 'rep');
  v_job_b := app.confirm_job_order(v_job_b.id, v_job_b.record_version, '00000000-0000-0000-0000-000000023902', 'rep');

  select * into v_vendor from app.create_master_record('vendor', v_tenant1, 'VEND-LINEAGE-1', 'Contoso Trucking', '[]'::jsonb, '{}'::jsonb, '00000000-0000-0000-0000-000000023901', 'admin');

  select * into v_shipment from app.create_shipment_order_from_job(
    v_job_a.id, 'idem-lineage-a', null, null, 'ocean_freight', 'sea', 'Jakarta', 'Semarang',
    now() + interval '1 day', now() + interval '10 days', null, null, null, null, null, null, null, '00000000-0000-0000-0000-000000023902', 'rep'
  );

  select count(*) into v_edge_count from app.transaction_lineage_edges where tenant_id = v_tenant1 and relation_type = 'job_to_shipment' and source_id = v_job_a.id and target_id = v_shipment.id;
  if v_edge_count <> 1 then
    raise exception 'assertion failed: expected exactly 1 auto-captured job_to_shipment edge for the new shipment, got %', v_edge_count;
  end if;

  v_shipment := app.confirm_shipment_order(v_shipment.id, v_shipment.record_version, '00000000-0000-0000-0000-000000023902', 'rep');
  perform app.assign_resource(v_shipment.id, 'vendor', v_vendor.id, '00000000-0000-0000-0000-000000023902', 'rep');

  perform app.register_document_type('pod', 'Proof of Delivery', 'DOC', '00000000-0000-0000-0000-000000023906', 'supreme');
  perform app.register_document_type('epod', 'Electronic Proof of Delivery', 'DOC', '00000000-0000-0000-0000-000000023906', 'supreme');

  v_config_draft := app.create_config_draft('document:pod', v_tenant1, 'tenant', null, '00000000-0000-0000-0000-000000023901', 'admin');
  perform app.set_config_items(v_config_draft.id, jsonb_build_array(
    jsonb_build_object('key', 'allowed_mime_types', 'value', jsonb_build_array('application/pdf', 'image/jpeg')),
    jsonb_build_object('key', 'max_size_bytes', 'value', 5242880),
    jsonb_build_object('key', 'retention_class', 'value', 'operational_contract_plus_90d'),
    jsonb_build_object('key', 'default_classification', 'value', 'internal'),
    jsonb_build_object('key', 'legal_hold_eligible', 'value', false)
  ), '00000000-0000-0000-0000-000000023901', 'admin');
  perform app.publish_document_type_definition(v_config_draft.id, '00000000-0000-0000-0000-000000023901', now(), 'admin');

  v_config_draft := app.create_config_draft('document:epod', v_tenant1, 'tenant', null, '00000000-0000-0000-0000-000000023901', 'admin');
  perform app.set_config_items(v_config_draft.id, jsonb_build_array(
    jsonb_build_object('key', 'allowed_mime_types', 'value', jsonb_build_array('image/png', 'image/jpeg')),
    jsonb_build_object('key', 'max_size_bytes', 'value', 5242880),
    jsonb_build_object('key', 'retention_class', 'value', 'operational_contract_plus_90d'),
    jsonb_build_object('key', 'default_classification', 'value', 'internal'),
    jsonb_build_object('key', 'legal_hold_eligible', 'value', false)
  ), '00000000-0000-0000-0000-000000023901', 'admin');
  perform app.publish_document_type_definition(v_config_draft.id, '00000000-0000-0000-0000-000000023901', now(), 'admin');

  select * into v_req_def from app.create_document_requirement_draft(v_tenant1, null, null, 'delivered', 'carrier', 'pod', 'mandatory', '00000000-0000-0000-0000-000000023902', 'rep');
  perform app.publish_document_requirement_version(v_req_def.id, v_req_def.record_version, '00000000-0000-0000-0000-000000023902', 'rep');

  perform app.transition_shipment_order(v_shipment.id, 'planned', v_shipment.record_version, null, null, 'idem-lineage-a-planned', '00000000-0000-0000-0000-000000023902', 'rep');
  select * into v_shipment from app.shipment_orders where id = v_shipment.id;
  perform app.transition_shipment_order(v_shipment.id, 'assigned', v_shipment.record_version, null, null, 'idem-lineage-a-assigned', '00000000-0000-0000-0000-000000023902', 'rep');
  select * into v_shipment from app.shipment_orders where id = v_shipment.id;
  perform app.transition_shipment_order(v_shipment.id, 'dispatched', v_shipment.record_version, null, null, 'idem-lineage-a-dispatched', '00000000-0000-0000-0000-000000023902', 'rep');
  select * into v_shipment from app.shipment_orders where id = v_shipment.id;
  perform app.transition_shipment_order(v_shipment.id, 'in_transit', v_shipment.record_version, null, null, 'idem-lineage-a-intransit', '00000000-0000-0000-0000-000000023902', 'rep');
  select * into v_shipment from app.shipment_orders where id = v_shipment.id;
  perform app.transition_shipment_order(v_shipment.id, 'delivered', v_shipment.record_version, null, 'physical delivery confirmed', 'idem-lineage-a-delivered', '00000000-0000-0000-0000-000000023902', 'rep');
  select * into v_shipment from app.shipment_orders where id = v_shipment.id;

  perform app.pin_shipment_document_checklist(v_shipment.id, '00000000-0000-0000-0000-000000023902', 'rep');
  select * into v_item from app.shipment_document_checklist_items where shipment_order_id = v_shipment.id;
  select * into v_file from app.initiate_file_upload(v_tenant1, 'pod', 'shipment_order', v_shipment.id, 'pod-a.pdf', 'application/pdf', 102400, null, false, null, '{}'::uuid[], null, 'idem-lineage-a-pod', '00000000-0000-0000-0000-000000023902', 'rep');
  perform app.link_document_to_checklist_item(v_item.id, v_file.id, '00000000-0000-0000-0000-000000023902', 'rep');
  perform app.record_file_scan_result(v_file.id, 'clean', 'test-scanner-ref', '00000000-0000-0000-0000-000000023902', 'rep');
  perform app.review_document_checklist_item(v_item.id, 'approved', 'signed and dated', null, '00000000-0000-0000-0000-000000023902', 'rep');

  v_capture := app.start_epod_capture(v_tenant1, v_shipment.id, null, 'idem-lineage-a-cap', '00000000-0000-0000-0000-000000023902', 'rep');

  select count(*) into v_edge_count from app.transaction_lineage_edges where tenant_id = v_tenant1 and relation_type = 'shipment_to_epod' and source_id = v_shipment.id and target_id = v_capture.id;
  if v_edge_count <> 1 then
    raise exception 'assertion failed: expected exactly 1 auto-captured shipment_to_epod edge for the new ePOD capture, got %', v_edge_count;
  end if;

  select * into v_file from app.initiate_file_upload(v_tenant1, 'epod', 'shipment_order', v_shipment.id, 'signature-a.png', 'image/png', 20480, null, false, null, '{}'::uuid[], null, 'idem-lineage-a-sig', '00000000-0000-0000-0000-000000023902', 'rep');
  perform app.record_file_scan_result(v_file.id, 'clean', 'test-scanner-ref', '00000000-0000-0000-0000-000000023902', 'rep');
  v_capture := app.set_epod_evidence(v_capture.id, 'Budi Santoso', 'Warehouse Staff', v_file.id, '{}'::uuid[], null, now(), '00000000-0000-0000-0000-000000023902', 'rep');
  v_capture := app.submit_epod_capture(v_capture.id, v_capture.record_version, '00000000-0000-0000-0000-000000023902', 'rep');
  v_capture := app.review_epod_capture(v_capture.id, 'approved', 'looks good', v_capture.record_version, '00000000-0000-0000-0000-000000023902', 'rep');
  select * into v_shipment from app.shipment_orders where id = v_shipment.id;
  v_capture := app.complete_epod_capture(v_capture.id, v_capture.record_version, v_shipment.record_version, 'idem-lineage-a-complete', '00000000-0000-0000-0000-000000023902', 'rep');
  select * into v_shipment from app.shipment_orders where id = v_shipment.id;
  perform app.transition_shipment_order(v_shipment.id, 'closed', v_shipment.record_version, null, 'billed and closed', 'idem-lineage-a-closed', '00000000-0000-0000-0000-000000023902', 'rep');

  v_cost := app.create_actual_cost_draft(v_tenant1, v_shipment.id, 'IDR', null, '00000000-0000-0000-0000-000000023902', 'rep');

  select count(*) into v_edge_count from app.transaction_lineage_edges where tenant_id = v_tenant1 and relation_type = 'shipment_to_cost' and source_id = v_shipment.id and target_id = v_cost.id;
  if v_edge_count <> 1 then
    raise exception 'assertion failed: expected exactly 1 auto-captured shipment_to_cost edge for the new actual cost, got %', v_edge_count;
  end if;

  perform app.add_actual_cost_component(v_cost.id, 'freight', 'vendor', v_vendor.id, null, null, 'Ocean freight', 1, 'shipment', 5000000, null, 0, 'idem-lineage-cost-a', '00000000-0000-0000-0000-000000023902', 'rep');
  select * into v_cost from app.shipment_actual_costs where id = v_cost.id;
  v_cost := app.submit_actual_cost(v_cost.id, v_cost.record_version, '00000000-0000-0000-0000-000000023902', 'rep');
  perform app.decide_actual_cost(v_cost.id, 'approved', null, v_cost.record_version, '00000000-0000-0000-0000-000000023902', 'rep');

  v_profitability := app.calculate_job_profitability(v_job_a.id, null, '00000000-0000-0000-0000-000000023902', 'rep');
  select count(*) into v_edge_count from app.transaction_lineage_edges where tenant_id = v_tenant1 and relation_type = 'job_to_profitability' and source_id = v_job_a.id and target_id = v_profitability.id;
  if v_edge_count <> 1 then
    raise exception 'assertion failed: expected exactly 1 auto-captured job_to_profitability edge, got %', v_edge_count;
  end if;

  v_billing := app.evaluate_billing_readiness(v_job_a.id, null, '00000000-0000-0000-0000-000000023902', 'rep');
  select count(*) into v_edge_count from app.transaction_lineage_edges where tenant_id = v_tenant1 and relation_type = 'job_to_billing_readiness' and source_id = v_job_a.id and target_id = v_billing.id;
  if v_edge_count <> 1 then
    raise exception 'assertion failed: expected exactly 1 auto-captured job_to_billing_readiness edge, got %', v_edge_count;
  end if;
end $$;

\echo '>> app.get_transaction_lineage: sibling-team outsider denied by record scope despite full grants incl OPS:Override; unknown Job Order raises job_order_not_found; the owning rep sees the full manifest -- 1 shipment with its ePOD/actual-cost/milestone-projection children, a profitability node, a billing-readiness node and all 6 edges (job B''s own edges are never included on job A''s manifest)'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'acmeopslineage');
  v_job_a_id uuid := (select jo.id from app.job_orders jo join app.job_order_handoffs h on h.id = jo.source_handoff_id join app.quotations q on q.id = h.quotation_id where q.opportunity_id = (select id from app.opportunities where name = 'Lineage test lane A'));
  v_manifest jsonb;
  v_shipment_count integer;
begin
  begin
    perform app.get_transaction_lineage(v_job_a_id, '00000000-0000-0000-0000-000000023904');
    raise exception 'assertion failed: expected the sibling-team outsider to be denied by record scope despite full grants incl OPS:Override';
  exception
    when insufficient_privilege then null;
  end;

  begin
    perform app.get_transaction_lineage('00000000-0000-0000-0000-000000000999', '00000000-0000-0000-0000-000000023902');
    raise exception 'assertion failed: expected job_order_not_found for an unknown job order id';
  exception
    when no_data_found then null;
  end;

  v_manifest := app.get_transaction_lineage(v_job_a_id, '00000000-0000-0000-0000-000000023902');
  if v_manifest -> 'sourceQuotationId' is null or v_manifest ->> 'sourcePayloadHash' is null then
    raise exception 'assertion failed: expected sourceQuotationId/sourcePayloadHash to be populated, got %', v_manifest;
  end if;
  select jsonb_array_length(v_manifest -> 'shipments') into v_shipment_count;
  if v_shipment_count <> 1 then
    raise exception 'assertion failed: expected exactly 1 shipment in the manifest, got %', v_shipment_count;
  end if;
  if (v_manifest -> 'shipments' -> 0 -> 'epod' -> 'status') is null or (v_manifest -> 'shipments' -> 0 -> 'actualCost' -> 'status') is null then
    raise exception 'assertion failed: expected the shipment node to carry both its epod and actualCost children, got %', v_manifest -> 'shipments' -> 0;
  end if;
  if (v_manifest -> 'profitability' -> 'status') is null or (v_manifest -> 'billingReadiness' -> 'effectiveStatus') is null then
    raise exception 'assertion failed: expected profitability/billingReadiness nodes to be populated, got %', v_manifest;
  end if;
  if jsonb_array_length(v_manifest -> 'edges') <> 6 then
    raise exception 'assertion failed: expected exactly 6 lineage edges on job A''s manifest (1 quote_to_job + 1 job_to_shipment + 1 shipment_to_epod + 1 shipment_to_cost + 1 job_to_profitability + 1 job_to_billing_readiness), got % -- %', jsonb_array_length(v_manifest -> 'edges'), v_manifest -> 'edges';
  end if;
end $$;

\echo '>> app.record_transaction_lineage_override: authority-gated (restricted actor lacks OPS:Override), reason mandatory, a genuine already-existing pairing is rejected (unique_violation), a real corrective consolidation mapping (job B also claims job A''s shipment) succeeds and is reason-audited without touching job A''s own original edge'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'acmeopslineage');
  v_job_a_id uuid := (select jo.id from app.job_orders jo join app.job_order_handoffs h on h.id = jo.source_handoff_id join app.quotations q on q.id = h.quotation_id where q.opportunity_id = (select id from app.opportunities where name = 'Lineage test lane A'));
  v_job_b_id uuid := (select jo.id from app.job_orders jo join app.job_order_handoffs h on h.id = jo.source_handoff_id join app.quotations q on q.id = h.quotation_id where q.opportunity_id = (select id from app.opportunities where name = 'Lineage test lane B'));
  v_shipment_id uuid := (select id from app.shipment_orders where job_order_id = v_job_a_id);
  v_edge app.transaction_lineage_edges;
  v_original_edge app.transaction_lineage_edges;
begin
  select * into v_original_edge from app.transaction_lineage_edges where relation_type = 'job_to_shipment' and source_id = v_job_a_id and target_id = v_shipment_id;

  begin
    perform app.record_transaction_lineage_override(v_tenant1, 'job_to_shipment', 'job_order', v_job_b_id, 'shipment_order', v_shipment_id, 'consolidation correction', '00000000-0000-0000-0000-000000023903', 'restricted');
    raise exception 'assertion failed: expected the restricted actor (no OPS:Override) to be denied';
  exception
    when insufficient_privilege then null;
  end;

  begin
    perform app.record_transaction_lineage_override(v_tenant1, 'job_to_shipment', 'job_order', v_job_b_id, 'shipment_order', v_shipment_id, '', '00000000-0000-0000-0000-000000023902', 'rep');
    raise exception 'assertion failed: expected transaction_lineage_override_reason_required with an empty reason';
  exception
    when check_violation then
      if sqlerrm !~ 'transaction_lineage_override_reason_required' then raise; end if;
  end;

  begin
    perform app.record_transaction_lineage_override(v_tenant1, 'job_to_shipment', 'job_order', v_job_a_id, 'shipment_order', v_shipment_id, 'redundant, already exists', '00000000-0000-0000-0000-000000023902', 'rep');
    raise exception 'assertion failed: expected transaction_lineage_edge_already_recorded for the exact same pairing the trigger already captured';
  exception
    when unique_violation then
      if sqlerrm !~ 'transaction_lineage_edge_already_recorded' then raise; end if;
  end;

  v_edge := app.record_transaction_lineage_override(v_tenant1, 'job_to_shipment', 'job_order', v_job_b_id, 'shipment_order', v_shipment_id, 'shipment consolidated into job B per customer request', '00000000-0000-0000-0000-000000023902', 'rep');
  if not v_edge.is_override or v_edge.override_reason is null or v_edge.created_by_auth_user_id <> '00000000-0000-0000-0000-000000023902' then
    raise exception 'assertion failed: expected a real, reasoned, actor-attributed override row, got %', v_edge;
  end if;

  select * into v_original_edge from app.transaction_lineage_edges where id = v_original_edge.id;
  if v_original_edge.is_override or v_original_edge.override_reason is not null then
    raise exception 'assertion failed: expected job A''s own original trigger-captured edge to remain completely untouched by the correction, got %', v_original_edge;
  end if;
end $$;

\echo '>> app.detect_transaction_lineage_anomalies: authority-gated (restricted actor lacks OPS:Override); the override above now shows up as a genuine duplicate_target (2 distinct sources claim the same shipment under job_to_shipment); simulated data-loss (a direct delete of the billing-readiness edge) is flagged orphan_billing_readiness; a directly-inserted mismatched-tenant edge is flagged cross_tenant_mismatch'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'acmeopslineage');
  v_tenant2 uuid;
  v_job_a_id uuid := (select jo.id from app.job_orders jo join app.job_order_handoffs h on h.id = jo.source_handoff_id join app.quotations q on q.id = h.quotation_id where q.opportunity_id = (select id from app.opportunities where name = 'Lineage test lane A'));
  v_shipment_id uuid := (select id from app.shipment_orders where job_order_id = v_job_a_id);
  v_billing_id uuid := (select id from app.billing_readiness_evaluations where job_order_id = v_job_a_id and is_current);
  v_dup_count integer;
  v_orphan_count integer;
  v_mismatch_count integer;
begin
  begin
    perform app.detect_transaction_lineage_anomalies(v_tenant1, '00000000-0000-0000-0000-000000023903');
    raise exception 'assertion failed: expected the restricted actor (no OPS:Override) to be denied';
  exception
    when insufficient_privilege then null;
  end;

  select count(*) into v_dup_count from app.detect_transaction_lineage_anomalies(v_tenant1, '00000000-0000-0000-0000-000000023902') a
  where a.anomaly_type = 'duplicate_target' and a.target_id = v_shipment_id;
  if v_dup_count <> 1 then
    raise exception 'assertion failed: expected exactly 1 duplicate_target anomaly for the consolidated shipment, got %', v_dup_count;
  end if;

  -- HDN-375 (Data Lineage Audit): app.transaction_lineage_edges is now a protected
  -- append-only ledger (app.protect_transaction_lineage_edges_append_only, mirroring
  -- CPL-325's own established shape) -- simulating data loss for this anomaly-detection
  -- proof requires a genuine Supreme Admin session context.
  perform set_config('request.jwt.claims', json_build_object('sub', '00000000-0000-0000-0000-000000023906', 'role', 'authenticated')::text, true);
  delete from app.transaction_lineage_edges where relation_type = 'job_to_billing_readiness' and target_id = v_billing_id;
  perform set_config('request.jwt.claims', 'null', true);

  select count(*) into v_orphan_count from app.detect_transaction_lineage_anomalies(v_tenant1, '00000000-0000-0000-0000-000000023902') a
  where a.anomaly_type = 'orphan_billing_readiness' and a.target_id = v_billing_id;
  if v_orphan_count <> 1 then
    raise exception 'assertion failed: expected exactly 1 orphan_billing_readiness anomaly after the simulated data-loss delete, got %', v_orphan_count;
  end if;

  perform app.provision_tenant('acmeopslineage2', 'Acme Ops Lineage Co 2', 'idem-acmeopslineage2', 'tester');
  v_tenant2 := (select id from app.tenants where slug = 'acmeopslineage2');

  insert into app.transaction_lineage_edges (tenant_id, relation_type, source_type, source_id, target_type, target_id, created_by_label)
  values (v_tenant2, 'quote_to_job', 'job_order_handoff', gen_random_uuid(), 'job_order', v_job_a_id, 'test-fixture');

  select count(*) into v_mismatch_count from app.detect_transaction_lineage_anomalies(v_tenant1, '00000000-0000-0000-0000-000000023902') a
  where a.anomaly_type = 'cross_tenant_mismatch' and a.target_id = v_job_a_id;
  if v_mismatch_count <> 1 then
    raise exception 'assertion failed: expected exactly 1 cross_tenant_mismatch anomaly for the directly-inserted mismatched-tenant row, got %', v_mismatch_count;
  end if;

  perform set_config('request.jwt.claims', json_build_object('sub', '00000000-0000-0000-0000-000000023906', 'role', 'authenticated')::text, true);
  delete from app.transaction_lineage_edges where tenant_id = v_tenant2;
  perform set_config('request.jwt.claims', 'null', true);
end $$;

\echo '>> app.backfill_transaction_lineage: authority-gated (restricted actor lacks OPS:Override); idempotent (a second call with nothing missing backfills zero); re-derives the exact billing-readiness edge the data-loss simulation deleted above -- orphan_billing_readiness no longer appears afterward'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'acmeopslineage');
  v_job_a_id uuid := (select jo.id from app.job_orders jo join app.job_order_handoffs h on h.id = jo.source_handoff_id join app.quotations q on q.id = h.quotation_id where q.opportunity_id = (select id from app.opportunities where name = 'Lineage test lane A'));
  v_billing_id uuid := (select id from app.billing_readiness_evaluations where job_order_id = v_job_a_id and is_current);
  v_backfilled integer;
  v_second_backfilled integer;
  v_orphan_count integer;
begin
  begin
    perform app.backfill_transaction_lineage(v_tenant1, '00000000-0000-0000-0000-000000023903', 'restricted');
    raise exception 'assertion failed: expected the restricted actor (no OPS:Override) to be denied';
  exception
    when insufficient_privilege then null;
  end;

  v_backfilled := app.backfill_transaction_lineage(v_tenant1, '00000000-0000-0000-0000-000000023902', 'rep');
  if v_backfilled <> 1 then
    raise exception 'assertion failed: expected exactly 1 edge backfilled (the deleted job_to_billing_readiness edge), got %', v_backfilled;
  end if;

  v_second_backfilled := app.backfill_transaction_lineage(v_tenant1, '00000000-0000-0000-0000-000000023902', 'rep');
  if v_second_backfilled <> 0 then
    raise exception 'assertion failed: expected zero edges backfilled on an immediate idempotent retry, got %', v_second_backfilled;
  end if;

  select count(*) into v_orphan_count from app.detect_transaction_lineage_anomalies(v_tenant1, '00000000-0000-0000-0000-000000023902') a
  where a.anomaly_type = 'orphan_billing_readiness' and a.target_id = v_billing_id;
  if v_orphan_count <> 0 then
    raise exception 'assertion failed: expected zero orphan_billing_readiness anomalies once the edge is re-derived, got %', v_orphan_count;
  end if;
end $$;

\echo '>> RLS / schema-privilege defense in depth: the sibling-team outsider sees zero lineage-edge rows directly; the owning rep sees every edge; anon holds zero EXECUTE on the 4 new OPS-184 functions'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'acmeopslineage');
  v_count integer;
  v_denied_count integer;
begin
  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000023904", "role": "authenticated"}';
  select count(*) into v_count from app.transaction_lineage_edges where tenant_id = v_tenant1;
  if v_count <> 0 then
    raise exception 'assertion failed: expected the sibling-team outsider to see zero lineage-edge rows via RLS, got %', v_count;
  end if;
  reset role;

  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000023902", "role": "authenticated"}';
  select count(*) into v_count from app.transaction_lineage_edges where tenant_id = v_tenant1;
  if v_count < 7 then
    raise exception 'assertion failed: expected the owning rep to see at least 7 lineage-edge rows via RLS (6 auto-captured + 1 override), got %', v_count;
  end if;
  reset role;

  select count(*) into v_denied_count
  from information_schema.routine_privileges
  where routine_schema = 'app'
    and routine_name in ('get_transaction_lineage', 'record_transaction_lineage_override', 'detect_transaction_lineage_anomalies', 'backfill_transaction_lineage')
    and grantee = 'anon';
  if v_denied_count <> 0 then
    raise exception 'assertion failed: expected anon to hold zero EXECUTE grants on the 4 new OPS-184 functions, found %', v_denied_count;
  end if;
end $$;

\echo '>> audit trail: automatic capture, the override, and the backfill each self-capture a canonical app.audit_logs entry'
do $$
declare
  v_capture_count integer;
  v_override_count integer;
  v_backfill_count integer;
begin
  select count(*) into v_capture_count from app.audit_logs where action = 'capture_transaction_lineage_edge';
  select count(*) into v_override_count from app.audit_logs where action = 'record_transaction_lineage_override';
  select count(*) into v_backfill_count from app.audit_logs where action = 'backfill_transaction_lineage';
  if v_capture_count < 6 or v_override_count < 1 or v_backfill_count < 1 then
    raise exception 'assertion failed: expected >=6 capture, >=1 override, >=1 backfill audit events, found %/%/%', v_capture_count, v_override_count, v_backfill_count;
  end if;
end $$;

\echo '>> HDN-375 (Data Lineage Audit) finding 1 regression: app.transaction_lineage_edges is now a protected append-only ledger -- a raw UPDATE/DELETE with no actor context, and by an ordinary tenant staff actor (OPS:Override, NOT supreme_admin), are both blocked; only a genuine Supreme Admin session may mutate it, and that mutation is captured to app.audit_logs with correct before/after and actor identity'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'acmeopslineage');
  v_rep uuid := '00000000-0000-0000-0000-000000023902';
  v_supreme uuid := '00000000-0000-0000-0000-000000023906';
  v_edge_id uuid;
  v_row app.transaction_lineage_edges;
  v_audit app.audit_logs;
begin
  select id into v_edge_id from app.transaction_lineage_edges where tenant_id = v_tenant1 limit 1;

  perform set_config('request.jwt.claims', 'null', true);
  begin
    update app.transaction_lineage_edges set override_reason = 'tamper attempt' where id = v_edge_id;
    raise exception 'assertion failed: expected UPDATE with no actor context to be blocked';
  exception when others then
    if sqlerrm !~ 'transaction_lineage_edge_append_only_immutable' then raise; end if;
  end;

  perform set_config('request.jwt.claims', json_build_object('sub', v_rep::text, 'role', 'authenticated')::text, true);
  begin
    delete from app.transaction_lineage_edges where id = v_edge_id;
    raise exception 'assertion failed: expected DELETE by an ordinary staff actor (OPS:Override, not supreme_admin) to be blocked';
  exception when others then
    if sqlerrm !~ 'transaction_lineage_edge_append_only_immutable' then raise; end if;
  end;
  perform set_config('request.jwt.claims', 'null', true);

  perform set_config('request.jwt.claims', json_build_object('sub', v_supreme::text, 'role', 'authenticated')::text, true);
  update app.transaction_lineage_edges set override_reason = 'corrected by supreme admin' where id = v_edge_id returning * into v_row;
  if v_row.override_reason <> 'corrected by supreme admin' then
    raise exception 'assertion failed: expected Supreme Admin UPDATE to succeed, got override_reason=%', v_row.override_reason;
  end if;
  perform set_config('request.jwt.claims', 'null', true);

  select * into v_audit from app.audit_logs where resource_type = 'app.transaction_lineage_edges' and resource_id = v_edge_id and action = 'update_append_only_transaction_lineage_edge';
  if v_audit.id is null then
    raise exception 'assertion failed: expected exactly 1 audit_logs row for the Supreme Admin UPDATE';
  end if;
  if v_audit.actor_auth_user_id <> v_supreme then
    raise exception 'assertion failed: expected audit actor_auth_user_id=%, got %', v_supreme, v_audit.actor_auth_user_id;
  end if;
end $$;

\echo '>> HDN-375 (Data Lineage Audit) finding 2 regression: app.loyalty_earning_events / app.finance_journals reject a source_id that does not resolve to a real row of the type source_type claims, even for a direct service_role insert bypassing the validating RPC'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'acmeopslineage');
  v_loyalty_account uuid;
begin
  -- No loyalty account exists in this file's own fixture -- a syntactically valid but
  -- nonexistent loyalty_account_id/program_id/rule_version_id would fail on THEIR OWN FK
  -- before ever reaching source_id validation, so this proof targets app.finance_journals
  -- instead, whose every other column has a real, satisfiable value in this fixture.
  begin
    insert into app.finance_journals (tenant_id, source_type, source_id, idempotency_key, currency, total_amount, journal_date, status, created_by)
    values (v_tenant1, 'subledger', gen_random_uuid(), 'hdn375-orphan-source-probe', 'USD', 100, current_date, 'draft', 'test-fixture');
    raise exception 'assertion failed: HDN-375 finding 2 regressed -- expected finance_journal_orphan_source for a source_id matching no real finance_subledger_batches row';
  exception
    when others then
      if sqlerrm !~ 'finance_journal_orphan_source' then
        raise exception 'assertion failed: expected finance_journal_orphan_source, got %', sqlerrm;
      end if;
  end;

  -- A manual journal legitimately has no source document -- source_id null is still
  -- accepted (this guard only validates a NON-null claim actually resolves).
  insert into app.finance_journals (tenant_id, source_type, source_id, idempotency_key, currency, total_amount, journal_date, status, created_by)
  values (v_tenant1, 'manual', null, 'hdn375-manual-source-probe', 'USD', 100, current_date, 'draft', 'test-fixture');
  if not exists (select 1 from app.finance_journals where idempotency_key = 'hdn375-manual-source-probe') then
    raise exception 'assertion failed: expected a manual journal with null source_id to insert successfully';
  end if;
end $$;
