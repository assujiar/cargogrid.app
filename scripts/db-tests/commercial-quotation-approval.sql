-- Real, executable test evidence for COM-153 (Quotation Approval, CG-S7-COM-012) -- run via
-- `pnpm run db:test` against a real, disposable Postgres database.

\set ON_ERROR_STOP on

\echo '>> setup: one tenant, a company/branch/two-team org hierarchy, a rep (COM:Create/Edit/View/View selling price/View cost), a sibling-team outsider with the same permission set, a manager approver, a finance approver, a full opportunity/costing/rate/margin chain (margin_pct=33.33, below a 40% floor), and a tenant_admin'
do $$
declare
  v_tenant1 uuid;
  v_company uuid;
  v_branch uuid;
  v_team_a uuid;
  v_team_b uuid;
  v_rep_role uuid;
  v_rep_draft app.role_versions;
  v_out_role uuid;
  v_out_draft app.role_versions;
  v_lead app.leads;
  v_prospect app.prospects;
  v_contact app.contacts;
  v_opportunity app.opportunities;
  v_request app.costing_requests;
  v_rate app.vendor_rate_versions;
  v_selection app.rate_selections;
  v_rule app.margin_rule_versions;
begin
  insert into auth.users (id, email) values
    ('00000000-0000-0000-0000-000000009601', 'tenantadmin@acmeappr.test'),
    ('00000000-0000-0000-0000-000000009602', 'rep@acmeappr.test'),
    ('00000000-0000-0000-0000-000000009603', 'manager@acmeappr.test'),
    ('00000000-0000-0000-0000-000000009604', 'finance@acmeappr.test'),
    ('00000000-0000-0000-0000-000000009605', 'outsider@acmeappr.test');

  perform app.provision_tenant('acmeappr', 'Acme Approval Co', 'idem-acmeappr', 'tester');
  v_tenant1 := (select id from app.tenants where slug = 'acmeappr');
  perform app.transition_tenant_status(v_tenant1, 'active', 'setup', 'tester');

  perform app.create_org_unit(v_tenant1, 'company', null, 'ACMEAPPR-CO', 'Acme Approval Co', 'tester');
  v_company := (select id from app.org_units where tenant_id = v_tenant1 and code = 'ACMEAPPR-CO');
  perform app.create_org_unit(v_tenant1, 'branch', v_company, 'ACMEAPPR-BR', 'Jakarta Branch', 'tester');
  v_branch := (select id from app.org_units where tenant_id = v_tenant1 and code = 'ACMEAPPR-BR');
  perform app.create_org_unit(v_tenant1, 'department', v_branch, 'ACMEAPPR-TEAM-A', 'Sales Team A', 'tester');
  v_team_a := (select id from app.org_units where tenant_id = v_tenant1 and code = 'ACMEAPPR-TEAM-A');
  perform app.create_org_unit(v_tenant1, 'department', v_branch, 'ACMEAPPR-TEAM-B', 'Sales Team B', 'tester');
  v_team_b := (select id from app.org_units where tenant_id = v_tenant1 and code = 'ACMEAPPR-TEAM-B');

  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000009601', 'tenantadmin@acmeappr.test', 'Tenant Admin', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'tenantadmin@acmeappr.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000009601', 'tenant_admin', v_tenant1, null, 'tester');

  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000009602', 'rep@acmeappr.test', 'Rep', v_team_a, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'rep@acmeappr.test'), 'active', 'onboarded', 'tester');
  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000009603', 'manager@acmeappr.test', 'Manager', v_team_a, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'manager@acmeappr.test'), 'active', 'onboarded', 'tester');
  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000009604', 'finance@acmeappr.test', 'Finance', v_team_a, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'finance@acmeappr.test'), 'active', 'onboarded', 'tester');
  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000009605', 'outsider@acmeappr.test', 'Team B Outsider', v_team_b, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'outsider@acmeappr.test'), 'active', 'onboarded', 'tester');

  v_rep_role := (app.create_role(v_tenant1, 'Approval Rep', 'quote approval', 'tester')).id;
  v_rep_draft := app.create_role_version(v_rep_role, 'tester');
  perform app.set_role_version_permissions(
    v_rep_draft.id,
    array(select id from app.permissions where resource_module_code = 'COM' and action in ('Create', 'Edit', 'Approve', 'View', 'View selling price', 'View cost')),
    'tester'
  );
  perform app.publish_role_version(v_rep_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_rep_role and status = 'published'),
    '00000000-0000-0000-0000-000000009602', '00000000-0000-0000-0000-000000009601', 'tester');

  v_out_role := (app.create_role(v_tenant1, 'Team B Approval Rep', 'sibling team', 'tester')).id;
  v_out_draft := app.create_role_version(v_out_role, 'tester');
  perform app.set_role_version_permissions(
    v_out_draft.id,
    array(select id from app.permissions where resource_module_code = 'COM' and action in ('Create', 'Edit', 'View', 'View selling price', 'View cost')),
    'tester'
  );
  perform app.publish_role_version(v_out_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_out_role and status = 'published'),
    '00000000-0000-0000-0000-000000009605', '00000000-0000-0000-0000-000000009601', 'tester');

  perform app.capture_lead(v_tenant1, 'manual', null, 'Contoso Approval Ltd', 'Jane Doe Appr', 'jane@contosoappr.test', '0811',
    '00000000-0000-0000-0000-000000009602', v_team_a, '00000000-0000-0000-0000-000000009602', 'tester');
  select * into v_lead from app.leads where email = 'jane@contosoappr.test';
  perform app.qualify_lead(v_lead.id, v_lead.record_version, '00000000-0000-0000-0000-000000009602', 'tester');
  select * into v_lead from app.leads where email = 'jane@contosoappr.test';
  perform app.convert_lead_to_prospect(v_lead.id, 'Contoso Approval Ltd', 'Contoso', '01.234.567.8-901.000',
    jsonb_build_object('line1', 'Jl. Sudirman 1', 'city', 'Jakarta', 'country', 'ID'),
    '00000000-0000-0000-0000-000000009602', 'tester');
  select * into v_prospect from app.prospects where legal_name = 'Contoso Approval Ltd';

  select * into v_contact from app.create_contact(v_tenant1, 'Jane Doe Appr', 'Procurement Lead', 'jane@contosoappr.test', '0811', '00000000-0000-0000-0000-000000009602', v_team_a, '00000000-0000-0000-0000-000000009602', 'tester');

  select * into v_opportunity from app.create_opportunity(
    v_tenant1, v_prospect.id, 'Contoso Jakarta-Surabaya approval lane',
    jsonb_build_object(
      'service_type', 'ocean_freight', 'cargo_description', 'General cargo',
      'origin', 'Jakarta', 'destination', 'Surabaya', 'target_ready_date', '2026-08-01'
    ),
    '00000000-0000-0000-0000-000000009602', v_team_a, '00000000-0000-0000-0000-000000009602', 'tester'
  );
  select * into v_request from app.request_costing(v_opportunity.id, '[]'::jsonb, null, '00000000-0000-0000-0000-000000009602', 'tester');

  select * into v_rate from app.create_rate_version(
    v_tenant1, 'VENDOR-APPR-1', 'Contoso Ocean Line', 'ocean_freight', 'FCL', 'Jakarta', 'Surabaya', '20ft',
    null, null, null, null, 'IDR', 10000000, null, '[]'::jsonb, now(), null, null,
    '00000000-0000-0000-0000-000000009601', 'tester'
  );
  perform app.approve_rate_version(v_rate.id, v_rate.record_version, '00000000-0000-0000-0000-000000009601', 'tester');
  select * into v_selection from app.select_vendor_rate(v_request.id, v_rate.id, false, null, null, null, '00000000-0000-0000-0000-000000009602', 'tester');

  select * into v_rule from app.create_margin_rule_version(v_tenant1, 20.00, 'half_up', '00000000-0000-0000-0000-000000009602', 'tester');
  perform app.publish_margin_rule_version(v_rule.id, v_rule.record_version, null, '00000000-0000-0000-0000-000000009602', 'tester');
  perform app.calculate_margin(v_selection.id, 15000000, 'IDR', 0, '00000000-0000-0000-0000-000000009602', 'tester');
end;
$$;

\echo '>> app.submit_quotation with no published app.quotation_approval_rules: approval is not_required, quotation auto-approves, no approval_request row is ever created'
do $$
declare
  v_tenant1 uuid;
  v_contact_id uuid;
  v_calc_id uuid;
  v_quote app.quotations;
begin
  v_tenant1 := (select id from app.tenants where slug = 'acmeappr');
  select id into v_contact_id from app.contacts where email = 'jane@contosoappr.test';
  select mc.id into v_calc_id from app.margin_calculations mc join app.rate_selections rs on rs.id = mc.rate_selection_id join app.costing_requests cr on cr.id = rs.costing_request_id join app.opportunities o on o.id = cr.opportunity_id where o.tenant_id = v_tenant1 and mc.is_current;

  select * into v_quote from app.create_quotation_draft(v_tenant1, (select id from app.opportunities where tenant_id = v_tenant1), 'IDR', now() + interval '14 days', v_contact_id, null, null, '00000000-0000-0000-0000-000000009602', 'tester');
  perform app.add_quotation_line(v_quote.id, v_quote.record_version, 'service', 'Ocean freight Jakarta-Surabaya', v_calc_id, 1, 15000000, 0, 0, '00000000-0000-0000-0000-000000009602', 'tester');
  select * into v_quote from app.quotations where id = v_quote.id;

  select * into v_quote from app.submit_quotation(v_quote.id, v_quote.record_version, '00000000-0000-0000-0000-000000009602', 'tester');
  if v_quote.status <> 'submitted' or v_quote.approval_status <> 'approved' or v_quote.approval_request_id is not null then
    raise exception 'assertion failed: expected status=submitted approval_status=approved approval_request_id=null (no published rule), got status=% approval_status=% approval_request_id=%', v_quote.status, v_quote.approval_status, v_quote.approval_request_id;
  end if;
end;
$$;

\echo '>> app.create_quotation_approval_rule_version / app.publish_quotation_approval_rule_version: min_margin_pct=40 (above this deal''s 33.33% margin) published, exactly like app.margin_rule_versions'' own versioning discipline'
do $$
declare
  v_tenant1 uuid;
  v_rule app.quotation_approval_rules;
begin
  v_tenant1 := (select id from app.tenants where slug = 'acmeappr');

  begin
    perform app.create_quotation_approval_rule_version(v_tenant1, null, null, null, '00000000-0000-0000-0000-000000009602', 'tester');
    raise exception 'assertion failed: expected check_violation -- a rule with every threshold null is meaningless';
  exception
    when sqlstate '23514' then
      null; -- expected
  end;

  select * into v_rule from app.create_quotation_approval_rule_version(v_tenant1, 40.00, null, null, '00000000-0000-0000-0000-000000009602', 'tester');
  if v_rule.status <> 'draft' then
    raise exception 'assertion failed: expected a fresh rule to start draft, got %', v_rule.status;
  end if;

  select * into v_rule from app.publish_quotation_approval_rule_version(v_rule.id, v_rule.record_version, null, '00000000-0000-0000-0000-000000009602', 'tester');
  if v_rule.status <> 'published' then
    raise exception 'assertion failed: expected published, got %', v_rule.status;
  end if;
end;
$$;

\echo '>> app.evaluate_quotation_approval_requirement: a fresh quotation sourced from the same 33.33%-margin calculation now crosses the published 40% floor; app.submit_quotation fails closed (approval_definition_not_configured) with no published routing definition yet'
do $$
declare
  v_tenant1 uuid;
  v_contact_id uuid;
  v_calc_id uuid;
  v_quote app.quotations;
  v_required boolean;
  v_reasons text[];
begin
  v_tenant1 := (select id from app.tenants where slug = 'acmeappr');
  select id into v_contact_id from app.contacts where email = 'jane@contosoappr.test';
  select mc.id into v_calc_id from app.margin_calculations mc join app.rate_selections rs on rs.id = mc.rate_selection_id join app.costing_requests cr on cr.id = rs.costing_request_id join app.opportunities o on o.id = cr.opportunity_id where o.tenant_id = v_tenant1 and mc.is_current;

  select * into v_quote from app.create_quotation_draft(v_tenant1, (select id from app.opportunities where tenant_id = v_tenant1), 'IDR', now() + interval '14 days', v_contact_id, null, null, '00000000-0000-0000-0000-000000009602', 'tester');
  perform app.add_quotation_line(v_quote.id, v_quote.record_version, 'service', 'Ocean freight Jakarta-Surabaya', v_calc_id, 1, 15000000, 0, 0, '00000000-0000-0000-0000-000000009602', 'tester');
  select * into v_quote from app.quotations where id = v_quote.id;

  select required, reasons into v_required, v_reasons from app.evaluate_quotation_approval_requirement(v_quote.id);
  if not v_required or v_reasons <> array['below_minimum_margin'] then
    raise exception 'assertion failed: expected required=true reasons=[below_minimum_margin], got required=% reasons=%', v_required, v_reasons;
  end if;

  begin
    perform app.submit_quotation(v_quote.id, v_quote.record_version, '00000000-0000-0000-0000-000000009602', 'tester');
    raise exception 'assertion failed: expected approval_definition_not_configured -- no published quotation approval routing definition exists yet';
  exception
    when sqlstate '23514' then
      if sqlerrm not like 'approval_definition_not_configured:%' then
        raise exception 'assertion failed: expected approval_definition_not_configured, got %', sqlerrm;
      end if;
  end;

  select * into v_quote from app.quotations where id = v_quote.id;
  if v_quote.status <> 'draft' then
    raise exception 'assertion failed: expected the failed submission attempt to leave the quotation at draft (transactional rollback), got %', v_quote.status;
  end if;
end;
$$;

\echo '>> publish a real 2-step sequential quotation approval routing definition (manager then finance) via the already-VERIFIED PLT-121/PLT-123 generic RPCs -- no new SQL, exactly this migration''s own disclosed reuse'
do $$
declare
  v_tenant1 uuid;
  v_manager_role_id uuid;
  v_finance_role_id uuid;
  v_draft app.config_versions;
begin
  v_tenant1 := (select id from app.tenants where slug = 'acmeappr');
  v_manager_role_id := (app.create_role(v_tenant1, 'Quote Manager Approver', 'quote approval routing', 'tester')).id;
  perform app.publish_role_version((app.create_role_version(v_manager_role_id, 'tester')).id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_manager_role_id and status = 'published'),
    '00000000-0000-0000-0000-000000009603', '00000000-0000-0000-0000-000000009601', 'tester');

  v_finance_role_id := (app.create_role(v_tenant1, 'Quote Finance Approver', 'quote approval routing', 'tester')).id;
  perform app.publish_role_version((app.create_role_version(v_finance_role_id, 'tester')).id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_finance_role_id and status = 'published'),
    '00000000-0000-0000-0000-000000009604', '00000000-0000-0000-0000-000000009601', 'tester');

  select * into v_draft from app.create_config_draft('approval', v_tenant1, 'tenant', null, '00000000-0000-0000-0000-000000009601', 'tenant admin');
  perform app.set_config_items(v_draft.id, jsonb_build_array(
    jsonb_build_object('key', 'pattern', 'value', 'sequential'),
    jsonb_build_object('key', 'steps', 'value', jsonb_build_array(
      jsonb_build_object('step_order', 1, 'approver_type', 'role', 'role_id', v_manager_role_id::text, 'required_approvals', 1),
      jsonb_build_object('step_order', 2, 'approver_type', 'role', 'role_id', v_finance_role_id::text, 'required_approvals', 1)
    )),
    jsonb_build_object('key', 'allow_self_approval', 'value', false)
  ), '00000000-0000-0000-0000-000000009601', 'tenant admin');
  perform app.publish_approval_definition(v_draft.id, '00000000-0000-0000-0000-000000009601', null, 'tenant admin');
end;
$$;

\echo '>> app.submit_quotation now routes for real: approval_status=pending, a real app.approval_requests row bound (idempotency_key = quotation id), step 1 (manager) active, step 2 (finance) pending'
do $$
declare
  v_tenant1 uuid;
  v_quote app.quotations;
  v_step1_status text;
  v_step2_status text;
begin
  v_tenant1 := (select id from app.tenants where slug = 'acmeappr');
  select * into v_quote from app.quotations where tenant_id = v_tenant1 and status = 'draft' order by quote_number asc limit 1;

  select * into v_quote from app.submit_quotation(v_quote.id, v_quote.record_version, '00000000-0000-0000-0000-000000009602', 'tester');
  if v_quote.status <> 'submitted' or v_quote.approval_status <> 'pending' or v_quote.approval_request_id is null then
    raise exception 'assertion failed: expected status=submitted approval_status=pending approval_request_id set, got status=% approval_status=% approval_request_id=%', v_quote.status, v_quote.approval_status, v_quote.approval_request_id;
  end if;
  if (select entity_type from app.approval_requests where id = v_quote.approval_request_id) <> 'quotation'
    or (select entity_id from app.approval_requests where id = v_quote.approval_request_id) <> v_quote.id then
    raise exception 'assertion failed: expected the bound request to carry entity_type=quotation entity_id=%', v_quote.id;
  end if;

  select status into v_step1_status from app.approval_request_steps where request_id = v_quote.approval_request_id and step_order = 1;
  select status into v_step2_status from app.approval_request_steps where request_id = v_quote.approval_request_id and step_order = 2;
  if v_step1_status <> 'active' or v_step2_status <> 'pending' then
    raise exception 'assertion failed: expected sequential step 1=active step 2=pending, got %/%', v_step1_status, v_step2_status;
  end if;
end;
$$;

\echo '>> app.decide_quotation_approval_step: an ineligible actor (sibling-team outsider, not manager/finance) is denied; the manager approves step 1 (quotation stays pending, step 2 activates); the finance approver then approves step 2 (quotation syncs to approved)'
do $$
declare
  v_tenant1 uuid;
  v_quote app.quotations;
  v_step1_id uuid;
  v_step2_id uuid;
begin
  v_tenant1 := (select id from app.tenants where slug = 'acmeappr');
  select * into v_quote from app.quotations where tenant_id = v_tenant1 and approval_status = 'pending' order by quote_number asc limit 1;
  select id into v_step1_id from app.approval_request_steps where request_id = v_quote.approval_request_id and step_order = 1;
  select id into v_step2_id from app.approval_request_steps where request_id = v_quote.approval_request_id and step_order = 2;

  begin
    perform app.decide_quotation_approval_step(v_step1_id, 'approved', '00000000-0000-0000-0000-000000009605', 'outsider', null);
    raise exception 'assertion failed: expected insufficient_privilege -- the sibling-team outsider holds no manager/finance role assignment';
  exception
    when insufficient_privilege then
      null; -- expected
  end;

  select * into v_quote from app.decide_quotation_approval_step(v_step1_id, 'approved', '00000000-0000-0000-0000-000000009603', 'manager', 'Looks good');
  if v_quote.approval_status <> 'pending' then
    raise exception 'assertion failed: expected the quotation to remain pending after only step 1 of 2 approved, got %', v_quote.approval_status;
  end if;
  if (select status from app.approval_request_steps where id = v_step2_id) <> 'active' then
    raise exception 'assertion failed: expected step 2 to activate once step 1 approved';
  end if;

  select * into v_quote from app.decide_quotation_approval_step(v_step2_id, 'approved', '00000000-0000-0000-0000-000000009604', 'finance', 'Approved');
  if v_quote.approval_status <> 'approved' then
    raise exception 'assertion failed: expected approval_status=approved once every required step passed, got %', v_quote.approval_status;
  end if;
end;
$$;

\echo '>> app.decide_quotation_approval_step refuses to decide a non-quotation approval request (not_a_quotation_approval) -- the domain sync wrapper is not a silent alias for app.decide_approval_step'
do $$
declare
  v_tenant1 uuid;
  v_config_version_id uuid;
  v_generic_request app.approval_requests;
  v_generic_step_id uuid;
begin
  v_tenant1 := (select id from app.tenants where slug = 'acmeappr');
  select cv.id into v_config_version_id
  from app.config_versions cv join app.config_objects co on co.id = cv.config_object_id
  where co.config_type_code = 'approval' and co.tenant_id = v_tenant1 and co.scope_level = 'tenant' and cv.status = 'published';

  select * into v_generic_request from app.request_approval(v_config_version_id, v_tenant1, 'generic', null, 'idem-generic-appr-test', '00000000-0000-0000-0000-000000009601', 'tenant admin');
  select id into v_generic_step_id from app.approval_request_steps where request_id = v_generic_request.id and step_order = 1;

  begin
    perform app.decide_quotation_approval_step(v_generic_step_id, 'approved', '00000000-0000-0000-0000-000000009603', 'manager', null);
    raise exception 'assertion failed: expected check_violation -- entity_type=generic is not a quotation approval';
  exception
    when sqlstate '23514' then
      if sqlerrm not like 'not_a_quotation_approval:%' then
        raise exception 'assertion failed: expected not_a_quotation_approval, got %', sqlerrm;
      end if;
  end;
end;
$$;

\echo '>> rejection path: a fresh threshold-crossing quotation is rejected at step 1 with a reason; app.create_quotation_revision (COM-152) then starts the new version at approval_status=not_required, never inheriting the rejected verdict'
do $$
declare
  v_tenant1 uuid;
  v_contact_id uuid;
  v_calc_id uuid;
  v_quote app.quotations;
  v_revision app.quotations;
  v_step1_id uuid;
begin
  v_tenant1 := (select id from app.tenants where slug = 'acmeappr');
  select id into v_contact_id from app.contacts where email = 'jane@contosoappr.test';
  select mc.id into v_calc_id from app.margin_calculations mc join app.rate_selections rs on rs.id = mc.rate_selection_id join app.costing_requests cr on cr.id = rs.costing_request_id join app.opportunities o on o.id = cr.opportunity_id where o.tenant_id = v_tenant1 and mc.is_current;

  select * into v_quote from app.create_quotation_draft(v_tenant1, (select id from app.opportunities where tenant_id = v_tenant1), 'IDR', now() + interval '14 days', v_contact_id, null, null, '00000000-0000-0000-0000-000000009602', 'tester');
  perform app.add_quotation_line(v_quote.id, v_quote.record_version, 'service', 'Ocean freight Jakarta-Surabaya', v_calc_id, 1, 15000000, 0, 0, '00000000-0000-0000-0000-000000009602', 'tester');
  select * into v_quote from app.quotations where id = v_quote.id;
  select * into v_quote from app.submit_quotation(v_quote.id, v_quote.record_version, '00000000-0000-0000-0000-000000009602', 'tester');

  select id into v_step1_id from app.approval_request_steps where request_id = v_quote.approval_request_id and step_order = 1;
  select * into v_quote from app.decide_quotation_approval_step(v_step1_id, 'rejected', '00000000-0000-0000-0000-000000009603', 'manager', 'Margin too thin for this lane');
  if v_quote.approval_status <> 'rejected' then
    raise exception 'assertion failed: expected approval_status=rejected, got %', v_quote.approval_status;
  end if;
  if (select status from app.approval_requests where id = v_quote.approval_request_id) <> 'rejected' then
    raise exception 'assertion failed: expected the bound request itself to be rejected';
  end if;

  select * into v_revision from app.create_quotation_revision(v_quote.id, 'Renegotiated cost with vendor', '00000000-0000-0000-0000-000000009602', 'tester');
  if v_revision.approval_status <> 'not_required' or v_revision.approval_request_id is not null or v_revision.approval_required_reasons <> array[]::text[] then
    raise exception 'assertion failed: expected a fresh revision to start approval_status=not_required with no bound request/reasons (never inheriting the rejected verdict), got status=% request_id=% reasons=%', v_revision.approval_status, v_revision.approval_request_id, v_revision.approval_required_reasons;
  end if;
end;
$$;

\echo '>> app.quotations_directory: approval_status/approval_request_id/approval_rule_version_id/approval_required_reasons visible to any record-scoped viewer regardless of View cost/View selling price; sibling-team outsider still denied via record-scope'
do $$
declare
  v_tenant1 uuid;
  v_visible_count integer;
  v_approved_count integer;
  v_outsider_count integer;
begin
  v_tenant1 := (select id from app.tenants where slug = 'acmeappr');

  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000009602", "role": "authenticated"}';
  select count(*), count(*) filter (where approval_status = 'approved') into v_visible_count, v_approved_count from app.quotations_directory where tenant_id = v_tenant1;
  if v_visible_count <> 4 or v_approved_count <> 2 then
    raise exception 'assertion failed: expected the rep to see all 4 quotations with exactly 2 approved (auto-approved + fully-decided), got count=% approved=%', v_visible_count, v_approved_count;
  end if;
  reset role;

  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000009605", "role": "authenticated"}';
  select count(*) into v_outsider_count from app.quotations_directory where tenant_id = v_tenant1;
  if v_outsider_count <> 0 then
    raise exception 'assertion failed: expected the sibling-team outsider to be denied via record-scope, found % row(s)', v_outsider_count;
  end if;
  reset role;
end;
$$;

\echo '>> audit trail: every real lifecycle action self-captured a canonical app.audit_logs entry -- 3 successful submit_quotation calls (the fourth, failed attempt left no trace), 1 rule create + 1 rule publish, and 3 successful decide_approval_step decisions (the ineligible-outsider attempt and the not_a_quotation_approval attempt each left no trace)'
do $$
declare
  v_tenant1 uuid;
  v_count integer;
begin
  v_tenant1 := (select id from app.tenants where slug = 'acmeappr');

  select count(*) into v_count from app.audit_logs where resource_type = 'app.quotations' and action = 'submit_quotation' and tenant_id = v_tenant1;
  if v_count <> 3 then raise exception 'assertion failed: expected exactly 3 successful submit_quotation audit events, found %', v_count; end if;

  select count(*) into v_count from app.audit_logs where resource_type = 'app.quotation_approval_rules' and action = 'create_quotation_approval_rule_version' and tenant_id = v_tenant1;
  if v_count <> 1 then raise exception 'assertion failed: expected exactly 1 create_quotation_approval_rule_version audit event, found %', v_count; end if;

  select count(*) into v_count from app.audit_logs where resource_type = 'app.quotation_approval_rules' and action = 'publish_quotation_approval_rule_version' and tenant_id = v_tenant1;
  if v_count <> 1 then raise exception 'assertion failed: expected exactly 1 publish_quotation_approval_rule_version audit event, found %', v_count; end if;

  select count(*) into v_count from app.audit_logs where resource_type = 'app.approval_request_steps' and action = 'decide_approval_step' and tenant_id = v_tenant1;
  if v_count <> 3 then raise exception 'assertion failed: expected exactly 3 successful decide_approval_step audit events (manager+finance on the completed request, manager''s rejection on the second), found %', v_count; end if;
end;
$$;
