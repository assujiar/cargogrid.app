-- Real, executable test evidence for OPS-181 (Billing Readiness, CG-S8-OPS-015) --
-- run via `pnpm run db:test` against a real, disposable Postgres database.

\set ON_ERROR_STOP on

\echo '>> setup: one tenant, a company/team-a/team-b org hierarchy, a bootstrap tenant-admin, a rep (COM full + OPS full incl Override), a restricted actor (OPS View/Edit only, no Override), a sibling-team outsider (full grants incl Override, wrong record scope), a credit approver, a one-step credit approval routing definition, one confirmed Job Order with an active/allow-outcome credit profile'
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
  v_outcome text;
  v_handoff app.job_order_handoffs;
begin
  insert into auth.users (id, email) values
    ('00000000-0000-0000-0000-000000023601', 'admin@acmebilling.test'),
    ('00000000-0000-0000-0000-000000023602', 'rep@acmebilling.test'),
    ('00000000-0000-0000-0000-000000023603', 'restricted@acmebilling.test'),
    ('00000000-0000-0000-0000-000000023604', 'outsider@acmebilling.test'),
    ('00000000-0000-0000-0000-000000023605', 'approver@acmebilling.test'),
    ('00000000-0000-0000-0000-000000023606', 'supreme@acmebilling.test');

  perform app.grant_principal_membership('00000000-0000-0000-0000-000000023606', 'supreme_admin', null, null, 'tester');

  perform app.provision_tenant('acmebilling', 'Acme Billing Co', 'idem-acmebilling', 'tester');
  v_tenant1 := (select id from app.tenants where slug = 'acmebilling');
  perform app.transition_tenant_status(v_tenant1, 'active', 'setup', 'tester');

  perform app.create_org_unit(v_tenant1, 'company', null, 'ACMEBILLING-CO', 'Acme Billing Co', 'tester');
  perform app.create_org_unit(v_tenant1, 'department', (select id from app.org_units where tenant_id = v_tenant1 and code = 'ACMEBILLING-CO'), 'ACMEBILLING-TEAM-A', 'Team A', 'tester');
  v_team_a := (select id from app.org_units where tenant_id = v_tenant1 and code = 'ACMEBILLING-TEAM-A');
  perform app.create_org_unit(v_tenant1, 'department', (select id from app.org_units where tenant_id = v_tenant1 and code = 'ACMEBILLING-CO'), 'ACMEBILLING-TEAM-B', 'Team B', 'tester');
  v_team_b := (select id from app.org_units where tenant_id = v_tenant1 and code = 'ACMEBILLING-TEAM-B');

  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000023601', 'admin@acmebilling.test', 'Billing Admin', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'admin@acmebilling.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000023601', 'tenant_admin', v_tenant1, null, 'tester');
  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000023602', 'rep@acmebilling.test', 'Billing Rep', v_team_a, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'rep@acmebilling.test'), 'active', 'onboarded', 'tester');
  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000023603', 'restricted@acmebilling.test', 'Restricted Actor', v_team_a, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'restricted@acmebilling.test'), 'active', 'onboarded', 'tester');
  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000023604', 'outsider@acmebilling.test', 'Team B Outsider', v_team_b, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'outsider@acmebilling.test'), 'active', 'onboarded', 'tester');
  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000023605', 'approver@acmebilling.test', 'Credit Approver', v_team_a, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'approver@acmebilling.test'), 'active', 'onboarded', 'tester');

  v_rep_role := (app.create_role(v_tenant1, 'Billing Rep', 'full commercial + ops grants incl OPS:Override', 'tester')).id;
  v_rep_draft := app.create_role_version(v_rep_role, 'tester');
  perform app.set_role_version_permissions(
    v_rep_draft.id,
    array(select id from app.permissions where (resource_module_code = 'COM' and action in ('Create', 'Edit', 'Approve', 'View', 'View cost'))
      or (resource_module_code = 'OPS' and action in ('Create', 'Edit', 'Assign', 'View', 'View cost', 'Override'))),
    'tester'
  );
  perform app.publish_role_version(v_rep_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_rep_role and status = 'published'), '00000000-0000-0000-0000-000000023602', '00000000-0000-0000-0000-000000023601', 'tester');

  v_restricted_role := (app.create_role(v_tenant1, 'Billing Restricted', 'OPS Create/Edit/View only, no OPS:Override', 'tester')).id;
  v_restricted_draft := app.create_role_version(v_restricted_role, 'tester');
  perform app.set_role_version_permissions(
    v_restricted_draft.id,
    array(select id from app.permissions where resource_module_code = 'OPS' and action in ('Create', 'Edit', 'View')),
    'tester'
  );
  perform app.publish_role_version(v_restricted_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_restricted_role and status = 'published'), '00000000-0000-0000-0000-000000023603', '00000000-0000-0000-0000-000000023603', 'tester');

  v_outsider_role := (app.create_role(v_tenant1, 'Billing Outsider', 'sibling team, full grants incl OPS:Override', 'tester')).id;
  v_outsider_draft := app.create_role_version(v_outsider_role, 'tester');
  perform app.set_role_version_permissions(
    v_outsider_draft.id,
    array(select id from app.permissions where (resource_module_code = 'COM' and action in ('Create', 'Edit', 'View'))
      or (resource_module_code = 'OPS' and action in ('Create', 'Edit', 'Assign', 'View', 'View cost', 'Override'))),
    'tester'
  );
  perform app.publish_role_version(v_outsider_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_outsider_role and status = 'published'), '00000000-0000-0000-0000-000000023604', '00000000-0000-0000-0000-000000023601', 'tester');

  v_approver_role := (app.create_role(v_tenant1, 'Billing Credit Approver', 'decides the routed credit-profile approval request', 'tester')).id;
  v_approver_draft := app.create_role_version(v_approver_role, 'tester');
  perform app.set_role_version_permissions(v_approver_draft.id, array(select id from app.permissions where resource_module_code = 'COM' and action in ('Approve', 'View')), 'tester');
  perform app.publish_role_version(v_approver_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_approver_role and status = 'published'), '00000000-0000-0000-0000-000000023605', '00000000-0000-0000-0000-000000023601', 'tester');

  -- One-step sequential credit-approval routing definition -- the same generic
  -- PLT-121/PLT-123 'approval' config_type_code reuse COM-157's own db-test already
  -- established, no new SQL.
  select * into v_config_draft from app.create_config_draft('approval', v_tenant1, 'tenant', null, '00000000-0000-0000-0000-000000023601', 'tenant admin');
  perform app.set_config_items(v_config_draft.id, jsonb_build_array(
    jsonb_build_object('key', 'pattern', 'value', 'sequential'),
    jsonb_build_object('key', 'steps', 'value', jsonb_build_array(
      jsonb_build_object('step_order', 1, 'approver_type', 'role', 'role_id', v_approver_role::text, 'required_approvals', 1)
    )),
    jsonb_build_object('key', 'allow_self_approval', 'value', false)
  ), '00000000-0000-0000-0000-000000023601', 'tenant admin');
  perform app.publish_approval_definition(v_config_draft.id, '00000000-0000-0000-0000-000000023601', null, 'tenant admin');

  perform app.capture_lead(v_tenant1, 'manual', null, 'Billing Test Co', 'Jane Billing', 'jane@billingtest.test', '0811',
    '00000000-0000-0000-0000-000000023602', v_team_a, '00000000-0000-0000-0000-000000023602', 'tester');
  select * into v_lead from app.leads where email = 'jane@billingtest.test';
  perform app.qualify_lead(v_lead.id, v_lead.record_version, '00000000-0000-0000-0000-000000023602', 'tester');
  select * into v_lead from app.leads where id = v_lead.id;
  perform app.convert_lead_to_prospect(v_lead.id, 'Billing Test Co', 'BLT', '11.111.111.6-666.000',
    jsonb_build_object('line1', 'Jl. Sudirman 6', 'city', 'Jakarta', 'country', 'ID'),
    '00000000-0000-0000-0000-000000023602', 'tester');
  select * into v_prospect from app.prospects where lead_id = v_lead.id;

  select * into v_contact from app.create_contact(v_tenant1, 'Jane Billing Ops', 'Procurement Lead', 'jane@billingtest.test', '0811', '00000000-0000-0000-0000-000000023602', v_team_a, '00000000-0000-0000-0000-000000023602', 'tester');
  perform app.link_contact_to_record(v_contact.id, 'prospect', v_prospect.id, 'primary', true, '00000000-0000-0000-0000-000000023602', 'tester');

  select * into v_opportunity from app.create_opportunity(
    v_tenant1, v_prospect.id, 'Billing test lane',
    jsonb_build_object('service_type', 'ocean_freight', 'cargo_description', 'General cargo', 'origin', 'Jakarta', 'destination', 'Semarang', 'target_ready_date', '2026-08-01'),
    '00000000-0000-0000-0000-000000023602', v_team_a, '00000000-0000-0000-0000-000000023602', 'tester'
  );
  select * into v_request from app.request_costing(v_opportunity.id, '[]'::jsonb, null, '00000000-0000-0000-0000-000000023602', 'tester');
  select * into v_rate from app.create_rate_version(
    v_tenant1, 'VENDOR-BILL-1', 'Contoso Ocean Line', 'ocean_freight', 'FCL', 'Jakarta', 'Semarang', '20ft',
    null, null, null, null, 'IDR', 8000000, null, '[]'::jsonb, now(), null, null, '00000000-0000-0000-0000-000000023601', 'tester'
  );
  perform app.approve_rate_version(v_rate.id, v_rate.record_version, '00000000-0000-0000-0000-000000023601', 'tester');
  select * into v_selection from app.select_vendor_rate(v_request.id, v_rate.id, false, null, null, null, '00000000-0000-0000-0000-000000023602', 'tester');

  select * into v_rule from app.create_margin_rule_version(v_tenant1, 20.00, 'half_up', '00000000-0000-0000-0000-000000023602', 'tester');
  perform app.publish_margin_rule_version(v_rule.id, v_rule.record_version, null, '00000000-0000-0000-0000-000000023602', 'tester');
  perform app.calculate_margin(v_selection.id, 12000000, 'IDR', 0, '00000000-0000-0000-0000-000000023602', 'tester');
  select id into v_calc_id from app.margin_calculations where rate_selection_id = v_selection.id and is_current;

  select * into v_quote from app.create_quotation_draft(v_tenant1, v_opportunity.id, 'IDR', now() + interval '14 days', v_contact.id, null, null, '00000000-0000-0000-0000-000000023602', 'tester');
  perform app.add_quotation_line(v_quote.id, v_quote.record_version, 'service', 'Ocean freight billing lane', v_calc_id, 1, 12000000, 0, 0, '00000000-0000-0000-0000-000000023602', 'tester');
  select * into v_quote from app.quotations where id = v_quote.id;
  perform app.submit_quotation(v_quote.id, v_quote.record_version, '00000000-0000-0000-0000-000000023602', 'tester');
  select * into v_send from app.send_quotation_for_acceptance(v_quote.id, null, 'email', '00000000-0000-0000-0000-000000023602', 'tester');
  perform app.record_quotation_customer_decision(v_send.raw_token, 'accepted', 'Jane Billing Ops', null, null, null, null, null);
  select * into v_quote from app.quotations where id = v_quote.id;
  select * into v_account from app.convert_quotation_to_account(v_quote.id, null, null, '00000000-0000-0000-0000-000000023602', 'rep');

  -- Credit profile: requested -> approved (active) -- makes app.check_customer_credit
  -- resolve 'allow' for a within-limit amount, the exact evidence
  -- app.job_orders.credit_snapshot pins verbatim at handoff time.
  v_profile := app.request_customer_credit_profile(v_tenant1, v_account.id, 'IDR', 20000000, '00000000-0000-0000-0000-000000023602', 'rep');
  select rs.id into v_step_id from app.approval_request_steps rs where rs.request_id = v_profile.approval_request_id and rs.step_order = 1;
  v_profile := app.decide_credit_profile_approval_step(v_step_id, 'approved', 'Approved for billing readiness fixture', now(), '00000000-0000-0000-0000-000000023605', 'approver');
  select outcome into v_outcome from app.check_customer_credit(v_tenant1, v_account.id, 'IDR', 12000000, 'quotation', v_quote.id, '00000000-0000-0000-0000-000000023602', 'rep');
  if v_outcome <> 'allow' then
    raise exception 'fixture setup failed: expected credit check outcome allow, got %', v_outcome;
  end if;

  select * into v_handoff from app.prepare_job_order_handoff(v_quote.id, '00000000-0000-0000-0000-000000023602', 'rep');
  if (v_handoff.payload -> 'credit' ->> 'outcome') <> 'allow' then
    raise exception 'fixture setup failed: expected the handoff payload credit outcome to be allow, got %', (v_handoff.payload -> 'credit' ->> 'outcome');
  end if;
end $$;

\echo '>> app.evaluate_billing_readiness: authority-gated (restricted actor lacks OPS:Edit is fine here since they have it -- record-scope-gated instead via the sibling outsider); a draft, shipment-less Job Order evaluates not_ready with job_order_not_confirmed + no_shipments blockers'
do $$
declare
  v_job_order app.job_orders;
  v_handoff_id uuid := (select h.id from app.job_order_handoffs h join app.quotations q on q.id = h.quotation_id join app.tenants t on t.id = h.tenant_id where t.slug = 'acmebilling');
  v_eval app.billing_readiness_evaluations;
  v_codes text[];
begin
  select * into v_job_order from app.prepare_job_order(v_handoff_id, '00000000-0000-0000-0000-000000023602', 'rep');

  begin
    perform app.evaluate_billing_readiness(v_job_order.id, null, '00000000-0000-0000-0000-000000023604', 'outsider');
    raise exception 'assertion failed: expected the sibling-team outsider to be denied by record scope despite full grants';
  exception
    when insufficient_privilege then null;
  end;

  v_eval := app.evaluate_billing_readiness(v_job_order.id, null, '00000000-0000-0000-0000-000000023602', 'rep');
  if v_eval.evaluated_status <> 'not_ready' or v_eval.version_number <> 1 then
    raise exception 'assertion failed: expected a fresh not_ready evaluation at version 1, got %/%', v_eval.evaluated_status, v_eval.version_number;
  end if;
  select array_agg(b ->> 'code' order by b ->> 'code') into v_codes from jsonb_array_elements(v_eval.blockers) b;
  if v_codes <> array['job_order_not_confirmed', 'no_shipments'] then
    raise exception 'assertion failed: expected blockers [job_order_not_confirmed, no_shipments], got %', v_codes;
  end if;
end $$;

\echo '>> confirming the Job Order and pinning two Shipment Orders (fully compliant a, exception-blocked b): reevaluation without a reason is rejected once a current evaluation exists; a confirmed job with undelivered shipments evaluates not_ready with per-shipment shipment_not_delivered blockers'
do $$
declare
  v_job_order app.job_orders;
  v_vendor app.master_records;
  v_vendor_b app.master_records;
  v_shipment_a app.shipment_orders;
  v_shipment_b app.shipment_orders;
  v_cost app.shipment_actual_costs;
  v_req_def app.document_requirement_definitions;
  v_config_draft app.config_versions;
  v_file app.files;
  v_item app.shipment_document_checklist_items;
  v_capture app.epod_captures;
  v_exception app.operational_exceptions;
  v_eval app.billing_readiness_evaluations;
  v_codes text[];
begin
  select jo.* into v_job_order from app.job_orders jo join app.tenants t on t.id = jo.tenant_id where t.slug = 'acmebilling';
  v_job_order := app.confirm_job_order(v_job_order.id, v_job_order.record_version, '00000000-0000-0000-0000-000000023602', 'rep');

  begin
    perform app.evaluate_billing_readiness(v_job_order.id, null, '00000000-0000-0000-0000-000000023602', 'rep');
    raise exception 'assertion failed: expected billing_readiness_reevaluation_reason_required with no reason';
  exception
    when check_violation then
      if sqlerrm !~ 'billing_readiness_reevaluation_reason_required' then raise; end if;
  end;

  select * into v_vendor from app.create_master_record('vendor', v_job_order.tenant_id, 'VEND-BILL-1', 'Contoso Trucking', '[]'::jsonb, '{}'::jsonb, '00000000-0000-0000-0000-000000023601', 'admin');
  select * into v_vendor_b from app.create_master_record('vendor', v_job_order.tenant_id, 'VEND-BILL-2', 'Fabrikam Trucking', '[]'::jsonb, '{}'::jsonb, '00000000-0000-0000-0000-000000023601', 'admin');

  select * into v_shipment_a from app.create_shipment_order_from_job(
    v_job_order.id, 'idem-billing-a', null, null, 'ocean_freight', 'sea', 'Jakarta', 'Semarang',
    now() + interval '1 day', now() + interval '10 days', null, null, null, null, null, null, null, '00000000-0000-0000-0000-000000023602', 'rep'
  );
  v_shipment_a := app.confirm_shipment_order(v_shipment_a.id, v_shipment_a.record_version, '00000000-0000-0000-0000-000000023602', 'rep');
  perform app.assign_resource(v_shipment_a.id, 'vendor', v_vendor.id, '00000000-0000-0000-0000-000000023602', 'rep');

  select * into v_shipment_b from app.create_shipment_order_from_job(
    v_job_order.id, 'idem-billing-b', null, null, 'ocean_freight', 'sea', 'Jakarta', 'Cirebon',
    now() + interval '1 day', now() + interval '10 days', null, null, null, null, null, null, 'split: billing readiness second fixture', '00000000-0000-0000-0000-000000023602', 'rep'
  );
  v_shipment_b := app.confirm_shipment_order(v_shipment_b.id, v_shipment_b.record_version, '00000000-0000-0000-0000-000000023602', 'rep');
  perform app.assign_resource(v_shipment_b.id, 'vendor', v_vendor_b.id, '00000000-0000-0000-0000-000000023602', 'rep');

  v_eval := app.evaluate_billing_readiness(v_job_order.id, 'shipments now exist', '00000000-0000-0000-0000-000000023602', 'rep');
  if v_eval.evaluated_status <> 'not_ready' or v_eval.version_number <> 2 then
    raise exception 'assertion failed: expected not_ready at version 2, got %/%', v_eval.evaluated_status, v_eval.version_number;
  end if;
  -- Neither shipment has been delivered, ePOD-completed, or actual-costed yet, and
  -- no document checklist has been pinned yet (that happens below) -- three distinct
  -- blocker codes per shipment (6 total), never documents_incomplete this early.
  select array_agg(distinct b ->> 'code' order by b ->> 'code') into v_codes from jsonb_array_elements(v_eval.blockers) b;
  if v_codes <> array['actual_cost_not_approved', 'epod_incomplete', 'shipment_not_delivered'] then
    raise exception 'assertion failed: expected exactly [actual_cost_not_approved, epod_incomplete, shipment_not_delivered], got %', v_codes;
  end if;
  if jsonb_array_length(v_eval.blockers) <> 6 then
    raise exception 'assertion failed: expected 3 blockers per shipment (6 total), got %', jsonb_array_length(v_eval.blockers);
  end if;

  -- Drive both shipments to closed with an approved document checklist and an
  -- approved actual cost -- fully compliant except one deliberately-left-open
  -- exception on shipment_b, isolating exactly one blocker at the next evaluation.
  perform app.register_document_type('pod', 'Proof of Delivery', 'DOC', '00000000-0000-0000-0000-000000023606', 'supreme');
  perform app.register_document_type('epod', 'Electronic Proof of Delivery', 'DOC', '00000000-0000-0000-0000-000000023606', 'supreme');

  v_config_draft := app.create_config_draft('document:pod', v_job_order.tenant_id, 'tenant', null, '00000000-0000-0000-0000-000000023601', 'admin');
  perform app.set_config_items(v_config_draft.id, jsonb_build_array(
    jsonb_build_object('key', 'allowed_mime_types', 'value', jsonb_build_array('application/pdf', 'image/jpeg')),
    jsonb_build_object('key', 'max_size_bytes', 'value', 5242880),
    jsonb_build_object('key', 'retention_class', 'value', 'operational_contract_plus_90d'),
    jsonb_build_object('key', 'default_classification', 'value', 'internal'),
    jsonb_build_object('key', 'legal_hold_eligible', 'value', false)
  ), '00000000-0000-0000-0000-000000023601', 'admin');
  perform app.publish_document_type_definition(v_config_draft.id, '00000000-0000-0000-0000-000000023601', now(), 'admin');

  v_config_draft := app.create_config_draft('document:epod', v_job_order.tenant_id, 'tenant', null, '00000000-0000-0000-0000-000000023601', 'admin');
  perform app.set_config_items(v_config_draft.id, jsonb_build_array(
    jsonb_build_object('key', 'allowed_mime_types', 'value', jsonb_build_array('image/png', 'image/jpeg')),
    jsonb_build_object('key', 'max_size_bytes', 'value', 5242880),
    jsonb_build_object('key', 'retention_class', 'value', 'operational_contract_plus_90d'),
    jsonb_build_object('key', 'default_classification', 'value', 'internal'),
    jsonb_build_object('key', 'legal_hold_eligible', 'value', false)
  ), '00000000-0000-0000-0000-000000023601', 'admin');
  perform app.publish_document_type_definition(v_config_draft.id, '00000000-0000-0000-0000-000000023601', now(), 'admin');

  select * into v_req_def from app.create_document_requirement_draft(v_job_order.tenant_id, null, null, 'delivered', 'carrier', 'pod', 'mandatory', '00000000-0000-0000-0000-000000023602', 'rep');
  perform app.publish_document_requirement_version(v_req_def.id, v_req_def.record_version, '00000000-0000-0000-0000-000000023602', 'rep');

  perform app.transition_shipment_order(v_shipment_a.id, 'planned', v_shipment_a.record_version, null, null, 'idem-billing-a-planned', '00000000-0000-0000-0000-000000023602', 'rep');
  select * into v_shipment_a from app.shipment_orders where id = v_shipment_a.id;
  perform app.transition_shipment_order(v_shipment_a.id, 'assigned', v_shipment_a.record_version, null, null, 'idem-billing-a-assigned', '00000000-0000-0000-0000-000000023602', 'rep');
  select * into v_shipment_a from app.shipment_orders where id = v_shipment_a.id;
  perform app.transition_shipment_order(v_shipment_a.id, 'dispatched', v_shipment_a.record_version, null, null, 'idem-billing-a-dispatched', '00000000-0000-0000-0000-000000023602', 'rep');
  select * into v_shipment_a from app.shipment_orders where id = v_shipment_a.id;
  perform app.transition_shipment_order(v_shipment_a.id, 'in_transit', v_shipment_a.record_version, null, null, 'idem-billing-a-intransit', '00000000-0000-0000-0000-000000023602', 'rep');
  select * into v_shipment_a from app.shipment_orders where id = v_shipment_a.id;
  perform app.transition_shipment_order(v_shipment_a.id, 'delivered', v_shipment_a.record_version, null, 'physical delivery confirmed', 'idem-billing-a-delivered', '00000000-0000-0000-0000-000000023602', 'rep');
  select * into v_shipment_a from app.shipment_orders where id = v_shipment_a.id;

  perform app.pin_shipment_document_checklist(v_shipment_a.id, '00000000-0000-0000-0000-000000023602', 'rep');
  select * into v_item from app.shipment_document_checklist_items where shipment_order_id = v_shipment_a.id;
  select * into v_file from app.initiate_file_upload(v_job_order.tenant_id, 'pod', 'shipment_order', v_shipment_a.id, 'pod-a.pdf', 'application/pdf', 102400, null, false, null, '{}'::uuid[], null, 'idem-billing-a-pod', '00000000-0000-0000-0000-000000023602', 'rep');
  perform app.link_document_to_checklist_item(v_item.id, v_file.id, '00000000-0000-0000-0000-000000023602', 'rep');
  perform app.record_file_scan_result(v_file.id, 'clean', 'test-scanner-ref', '00000000-0000-0000-0000-000000023602', 'rep');
  perform app.review_document_checklist_item(v_item.id, 'approved', 'signed and dated', null, '00000000-0000-0000-0000-000000023602', 'rep');

  v_capture := app.start_epod_capture(v_job_order.tenant_id, v_shipment_a.id, null, 'idem-billing-a-cap', '00000000-0000-0000-0000-000000023602', 'rep');
  select * into v_file from app.initiate_file_upload(v_job_order.tenant_id, 'epod', 'shipment_order', v_shipment_a.id, 'signature-a.png', 'image/png', 20480, null, false, null, '{}'::uuid[], null, 'idem-billing-a-sig', '00000000-0000-0000-0000-000000023602', 'rep');
  perform app.record_file_scan_result(v_file.id, 'clean', 'test-scanner-ref', '00000000-0000-0000-0000-000000023602', 'rep');
  v_capture := app.set_epod_evidence(v_capture.id, 'Budi Santoso', 'Warehouse Staff', v_file.id, '{}'::uuid[], null, now(), '00000000-0000-0000-0000-000000023602', 'rep');
  v_capture := app.submit_epod_capture(v_capture.id, v_capture.record_version, '00000000-0000-0000-0000-000000023602', 'rep');
  v_capture := app.review_epod_capture(v_capture.id, 'approved', 'looks good', v_capture.record_version, '00000000-0000-0000-0000-000000023602', 'rep');
  select * into v_shipment_a from app.shipment_orders where id = v_shipment_a.id;
  v_capture := app.complete_epod_capture(v_capture.id, v_capture.record_version, v_shipment_a.record_version, 'idem-billing-a-complete', '00000000-0000-0000-0000-000000023602', 'rep');
  select * into v_shipment_a from app.shipment_orders where id = v_shipment_a.id;
  perform app.transition_shipment_order(v_shipment_a.id, 'closed', v_shipment_a.record_version, null, 'billed and closed', 'idem-billing-a-closed', '00000000-0000-0000-0000-000000023602', 'rep');

  v_cost := app.create_actual_cost_draft(v_job_order.tenant_id, v_shipment_a.id, 'IDR', null, '00000000-0000-0000-0000-000000023602', 'rep');
  perform app.add_actual_cost_component(v_cost.id, 'freight', 'vendor', v_vendor.id, null, null, 'Ocean freight', 1, 'shipment', 5000000, null, 0, 'idem-billing-cost-a', '00000000-0000-0000-0000-000000023602', 'rep');
  select * into v_cost from app.shipment_actual_costs where id = v_cost.id;
  v_cost := app.submit_actual_cost(v_cost.id, v_cost.record_version, '00000000-0000-0000-0000-000000023602', 'rep');
  perform app.decide_actual_cost(v_cost.id, 'approved', null, v_cost.record_version, '00000000-0000-0000-0000-000000023602', 'rep');

  -- Shipment b: identical happy path, plus one deliberately unresolved exception.
  perform app.transition_shipment_order(v_shipment_b.id, 'planned', v_shipment_b.record_version, null, null, 'idem-billing-b-planned', '00000000-0000-0000-0000-000000023602', 'rep');
  select * into v_shipment_b from app.shipment_orders where id = v_shipment_b.id;
  perform app.transition_shipment_order(v_shipment_b.id, 'assigned', v_shipment_b.record_version, null, null, 'idem-billing-b-assigned', '00000000-0000-0000-0000-000000023602', 'rep');
  select * into v_shipment_b from app.shipment_orders where id = v_shipment_b.id;
  perform app.transition_shipment_order(v_shipment_b.id, 'dispatched', v_shipment_b.record_version, null, null, 'idem-billing-b-dispatched', '00000000-0000-0000-0000-000000023602', 'rep');
  select * into v_shipment_b from app.shipment_orders where id = v_shipment_b.id;
  perform app.transition_shipment_order(v_shipment_b.id, 'in_transit', v_shipment_b.record_version, null, null, 'idem-billing-b-intransit', '00000000-0000-0000-0000-000000023602', 'rep');
  select * into v_shipment_b from app.shipment_orders where id = v_shipment_b.id;
  perform app.transition_shipment_order(v_shipment_b.id, 'delivered', v_shipment_b.record_version, null, 'physical delivery confirmed', 'idem-billing-b-delivered', '00000000-0000-0000-0000-000000023602', 'rep');
  select * into v_shipment_b from app.shipment_orders where id = v_shipment_b.id;

  perform app.pin_shipment_document_checklist(v_shipment_b.id, '00000000-0000-0000-0000-000000023602', 'rep');
  select * into v_item from app.shipment_document_checklist_items where shipment_order_id = v_shipment_b.id;
  select * into v_file from app.initiate_file_upload(v_job_order.tenant_id, 'pod', 'shipment_order', v_shipment_b.id, 'pod-b.pdf', 'application/pdf', 102400, null, false, null, '{}'::uuid[], null, 'idem-billing-b-pod', '00000000-0000-0000-0000-000000023602', 'rep');
  perform app.link_document_to_checklist_item(v_item.id, v_file.id, '00000000-0000-0000-0000-000000023602', 'rep');
  perform app.record_file_scan_result(v_file.id, 'clean', 'test-scanner-ref', '00000000-0000-0000-0000-000000023602', 'rep');
  perform app.review_document_checklist_item(v_item.id, 'approved', 'signed and dated', null, '00000000-0000-0000-0000-000000023602', 'rep');

  v_capture := app.start_epod_capture(v_job_order.tenant_id, v_shipment_b.id, null, 'idem-billing-b-cap', '00000000-0000-0000-0000-000000023602', 'rep');
  select * into v_file from app.initiate_file_upload(v_job_order.tenant_id, 'epod', 'shipment_order', v_shipment_b.id, 'signature-b.png', 'image/png', 20480, null, false, null, '{}'::uuid[], null, 'idem-billing-b-sig', '00000000-0000-0000-0000-000000023602', 'rep');
  perform app.record_file_scan_result(v_file.id, 'clean', 'test-scanner-ref', '00000000-0000-0000-0000-000000023602', 'rep');
  v_capture := app.set_epod_evidence(v_capture.id, 'Siti Aminah', 'Warehouse Staff', v_file.id, '{}'::uuid[], null, now(), '00000000-0000-0000-0000-000000023602', 'rep');
  v_capture := app.submit_epod_capture(v_capture.id, v_capture.record_version, '00000000-0000-0000-0000-000000023602', 'rep');
  v_capture := app.review_epod_capture(v_capture.id, 'approved', 'looks good', v_capture.record_version, '00000000-0000-0000-0000-000000023602', 'rep');
  select * into v_shipment_b from app.shipment_orders where id = v_shipment_b.id;
  v_capture := app.complete_epod_capture(v_capture.id, v_capture.record_version, v_shipment_b.record_version, 'idem-billing-b-complete', '00000000-0000-0000-0000-000000023602', 'rep');
  select * into v_shipment_b from app.shipment_orders where id = v_shipment_b.id;
  perform app.transition_shipment_order(v_shipment_b.id, 'closed', v_shipment_b.record_version, null, 'billed and closed', 'idem-billing-b-closed', '00000000-0000-0000-0000-000000023602', 'rep');

  v_cost := app.create_actual_cost_draft(v_job_order.tenant_id, v_shipment_b.id, 'IDR', null, '00000000-0000-0000-0000-000000023602', 'rep');
  perform app.add_actual_cost_component(v_cost.id, 'freight', 'vendor', v_vendor_b.id, null, null, 'Ocean freight', 1, 'shipment', 3000000, null, 0, 'idem-billing-cost-b', '00000000-0000-0000-0000-000000023602', 'rep');
  select * into v_cost from app.shipment_actual_costs where id = v_cost.id;
  v_cost := app.submit_actual_cost(v_cost.id, v_cost.record_version, '00000000-0000-0000-0000-000000023602', 'rep');
  perform app.decide_actual_cost(v_cost.id, 'approved', null, v_cost.record_version, '00000000-0000-0000-0000-000000023602', 'rep');

  select * into v_exception from app.report_exception(v_shipment_b.id, null, 'delay', 'medium', 'late arrival at destination port', 'manual', 'idem-billing-b-exc', '00000000-0000-0000-0000-000000023602', 'rep');
end $$;

\echo '>> fully-compliant shipment_a plus one open exception on shipment_b: evaluation isolates exactly one blocker (active_exception); handoff is refused while not_ready'
do $$
declare
  v_job_order_id uuid := (select jo.id from app.job_orders jo join app.tenants t on t.id = jo.tenant_id where t.slug = 'acmebilling');
  v_eval app.billing_readiness_evaluations;
begin
  v_eval := app.evaluate_billing_readiness(v_job_order_id, 'both shipments closed, checking for the deliberately open exception', '00000000-0000-0000-0000-000000023602', 'rep');
  if v_eval.evaluated_status <> 'not_ready' or v_eval.version_number <> 3 then
    raise exception 'assertion failed: expected not_ready at version 3, got %/%', v_eval.evaluated_status, v_eval.version_number;
  end if;
  if jsonb_array_length(v_eval.blockers) <> 1 or (v_eval.blockers -> 0 ->> 'code') <> 'active_exception' then
    raise exception 'assertion failed: expected exactly one active_exception blocker, got %', v_eval.blockers;
  end if;

  begin
    perform app.handoff_billing_readiness(v_job_order_id, 'idem-billing-handoff-1', '00000000-0000-0000-0000-000000023602', 'rep');
    raise exception 'assertion failed: expected billing_readiness_not_ready while a blocker remains';
  exception
    when check_violation then
      if sqlerrm !~ 'billing_readiness_not_ready' then raise; end if;
  end;
end $$;

\echo '>> app.override_billing_readiness / app.revoke_billing_readiness_override: authority-gated (restricted actor lacks OPS:Override), reason mandatory, stale-version checked, effective_status flips without mutating evaluated_status; handoff succeeds while overridden and is idempotent on the same key, then fails again once the override is revoked'
do $$
declare
  v_job_order_id uuid := (select jo.id from app.job_orders jo join app.tenants t on t.id = jo.tenant_id where t.slug = 'acmebilling');
  v_current app.billing_readiness_evaluations;
  v_overridden app.billing_readiness_evaluations;
  v_revoked app.billing_readiness_evaluations;
  v_handoff1 app.billing_readiness_handoffs;
  v_handoff2 app.billing_readiness_handoffs;
  v_handoff_count integer;
begin
  select * into v_current from app.billing_readiness_evaluations where job_order_id = v_job_order_id and is_current;

  begin
    perform app.override_billing_readiness(v_job_order_id, v_current.record_version, 'business justification', '00000000-0000-0000-0000-000000023603', 'restricted');
    raise exception 'assertion failed: expected the restricted actor (no OPS:Override) to be denied';
  exception
    when insufficient_privilege then null;
  end;

  begin
    perform app.override_billing_readiness(v_job_order_id, v_current.record_version, '', '00000000-0000-0000-0000-000000023602', 'rep');
    raise exception 'assertion failed: expected billing_readiness_override_reason_required with an empty reason';
  exception
    when check_violation then
      if sqlerrm !~ 'billing_readiness_override_reason_required' then raise; end if;
  end;

  begin
    perform app.override_billing_readiness(v_job_order_id, v_current.record_version + 99, 'stale test', '00000000-0000-0000-0000-000000023602', 'rep');
    raise exception 'assertion failed: expected stale_version with a wrong expected_version';
  exception
    when serialization_failure then null;
  end;

  v_overridden := app.override_billing_readiness(v_job_order_id, v_current.record_version, 'customer relationship priority, exception is a documentation-only delay', '00000000-0000-0000-0000-000000023602', 'rep');
  if v_overridden.effective_status <> 'ready' or v_overridden.evaluated_status <> 'not_ready' then
    raise exception 'assertion failed: expected effective_status=ready while evaluated_status remains not_ready, got %/%', v_overridden.effective_status, v_overridden.evaluated_status;
  end if;

  begin
    perform app.override_billing_readiness(v_job_order_id, v_overridden.record_version, 'redundant override', '00000000-0000-0000-0000-000000023602', 'rep');
    raise exception 'assertion failed: expected billing_readiness_override_not_needed once already effectively ready';
  exception
    when check_violation then
      if sqlerrm !~ 'billing_readiness_override_not_needed' then raise; end if;
  end;

  v_handoff1 := app.handoff_billing_readiness(v_job_order_id, 'idem-billing-handoff-2', '00000000-0000-0000-0000-000000023602', 'rep');
  v_handoff2 := app.handoff_billing_readiness(v_job_order_id, 'idem-billing-handoff-2', '00000000-0000-0000-0000-000000023602', 'rep');
  if v_handoff1.id <> v_handoff2.id then
    raise exception 'assertion failed: expected a retried handoff with the same idempotency_key to return the exact same row';
  end if;
  select count(*) into v_handoff_count from app.billing_readiness_handoffs where job_order_id = v_job_order_id;
  if v_handoff_count <> 1 then
    raise exception 'assertion failed: expected exactly one handoff row after an idempotent retry, got %', v_handoff_count;
  end if;

  begin
    perform app.revoke_billing_readiness_override(v_job_order_id, v_overridden.record_version, '', '00000000-0000-0000-0000-000000023602', 'rep');
    raise exception 'assertion failed: expected billing_readiness_revoke_reason_required with an empty reason';
  exception
    when check_violation then
      if sqlerrm !~ 'billing_readiness_revoke_reason_required' then raise; end if;
  end;

  v_revoked := app.revoke_billing_readiness_override(v_job_order_id, v_overridden.record_version, 'exception owner disputes the documentation-only classification', '00000000-0000-0000-0000-000000023602', 'rep');
  if v_revoked.effective_status <> 'not_ready' or v_revoked.is_overridden then
    raise exception 'assertion failed: expected effective_status back to not_ready and is_overridden=false after revoke, got %/%', v_revoked.effective_status, v_revoked.is_overridden;
  end if;
  if v_revoked.override_reason is null then
    raise exception 'assertion failed: expected override_reason to remain preserved for lineage after revoke';
  end if;

  begin
    perform app.revoke_billing_readiness_override(v_job_order_id, v_revoked.record_version, 'redundant revoke', '00000000-0000-0000-0000-000000023602', 'rep');
    raise exception 'assertion failed: expected billing_readiness_not_overridden once no override is active';
  exception
    when check_violation then
      if sqlerrm !~ 'billing_readiness_not_overridden' then raise; end if;
  end;

  begin
    perform app.handoff_billing_readiness(v_job_order_id, 'idem-billing-handoff-3', '00000000-0000-0000-0000-000000023602', 'rep');
    raise exception 'assertion failed: expected billing_readiness_not_ready once the override is revoked';
  exception
    when check_violation then
      if sqlerrm !~ 'billing_readiness_not_ready' then raise; end if;
  end;
end $$;

\echo '>> resolving the exception for real and reevaluating: evidence-based ready (not overridden), a fresh handoff with a new idempotency key succeeds; app RLS/schema-privilege defense in depth'
do $$
declare
  v_job_order_id uuid := (select jo.id from app.job_orders jo join app.tenants t on t.id = jo.tenant_id where t.slug = 'acmebilling');
  v_exception_id uuid := (select id from app.operational_exceptions where shipment_order_id in (select id from app.shipment_orders where job_order_id = v_job_order_id) and status = 'open');
  v_exception app.operational_exceptions;
  v_final app.billing_readiness_evaluations;
  v_handoff app.billing_readiness_handoffs;
  v_handoff_count integer;
  v_count integer;
  v_denied_count integer;
begin
  select * into v_exception from app.operational_exceptions where id = v_exception_id;
  perform app.resolve_exception(v_exception_id, v_exception.record_version, 'delay explained, no customer impact, billing may proceed', '00000000-0000-0000-0000-000000023602', 'rep');

  v_final := app.evaluate_billing_readiness(v_job_order_id, 'exception resolved, all evidence should now be clean', '00000000-0000-0000-0000-000000023602', 'rep');
  if v_final.evaluated_status <> 'ready' or v_final.effective_status <> 'ready' or v_final.is_overridden then
    raise exception 'assertion failed: expected a genuine evidence-based ready evaluation (not overridden), got evaluated=%/effective=%/overridden=%', v_final.evaluated_status, v_final.effective_status, v_final.is_overridden;
  end if;
  if jsonb_array_length(v_final.blockers) <> 0 then
    raise exception 'assertion failed: expected zero blockers, got %', v_final.blockers;
  end if;
  if jsonb_array_length(v_final.evidence -> 'shipmentOrderIds') <> 2 or jsonb_array_length(v_final.evidence -> 'actualCostIds') <> 2 or jsonb_array_length(v_final.evidence -> 'epodCaptureIds') <> 2 then
    raise exception 'assertion failed: expected evidence to reference exactly 2 shipments/costs/epod captures, got %', v_final.evidence;
  end if;

  v_handoff := app.handoff_billing_readiness(v_job_order_id, 'idem-billing-handoff-4', '00000000-0000-0000-0000-000000023602', 'rep');
  if v_handoff.evaluation_id <> v_final.id then
    raise exception 'assertion failed: expected the new handoff to reference the new evaluation version';
  end if;
  select count(*) into v_handoff_count from app.billing_readiness_handoffs where job_order_id = v_job_order_id;
  if v_handoff_count <> 2 then
    raise exception 'assertion failed: expected exactly 2 handoff rows total (one per genuinely-ready evaluation), got %', v_handoff_count;
  end if;

  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000023604", "role": "authenticated"}';
  select count(*) into v_count from app.billing_readiness_evaluations where job_order_id = v_job_order_id;
  if v_count <> 0 then
    raise exception 'assertion failed: expected the sibling-team outsider to see zero billing-readiness rows via RLS, got %', v_count;
  end if;
  select count(*) into v_count from app.billing_readiness_handoffs where job_order_id = v_job_order_id;
  if v_count <> 0 then
    raise exception 'assertion failed: expected the sibling-team outsider to see zero handoff rows via RLS, got %', v_count;
  end if;
  reset role;

  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000023602", "role": "authenticated"}';
  select count(*) into v_count from app.billing_readiness_evaluations where job_order_id = v_job_order_id;
  if v_count <> 4 then
    raise exception 'assertion failed: expected the full-access rep to see all 4 evaluation versions via RLS, got %', v_count;
  end if;
  reset role;

  select count(*) into v_denied_count
  from information_schema.routine_privileges
  where routine_schema = 'app'
    and routine_name in ('evaluate_billing_readiness', 'override_billing_readiness', 'revoke_billing_readiness_override', 'handoff_billing_readiness')
    and grantee = 'anon';
  if v_denied_count <> 0 then
    raise exception 'assertion failed: expected anon to hold zero EXECUTE grants on the 4 new OPS-181 functions, found %', v_denied_count;
  end if;
end $$;

\echo '>> audit trail: every evaluate/override/revoke/handoff self-captures a canonical app.audit_logs entry'
do $$
declare
  v_evaluate_count integer;
  v_override_count integer;
  v_revoke_count integer;
  v_handoff_count integer;
begin
  select count(*) into v_evaluate_count from app.audit_logs where action = 'evaluate_billing_readiness';
  select count(*) into v_override_count from app.audit_logs where action = 'override_billing_readiness';
  select count(*) into v_revoke_count from app.audit_logs where action = 'revoke_billing_readiness_override';
  select count(*) into v_handoff_count from app.audit_logs where action = 'handoff_billing_readiness';
  if v_evaluate_count < 4 or v_override_count < 1 or v_revoke_count < 1 or v_handoff_count < 2 then
    raise exception 'assertion failed: expected >=4 evaluate, >=1 override, >=1 revoke, >=2 handoff audit events, found %/%/%/%', v_evaluate_count, v_override_count, v_revoke_count, v_handoff_count;
  end if;
end $$;
