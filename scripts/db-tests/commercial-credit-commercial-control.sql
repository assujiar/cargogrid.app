-- Real, executable test evidence for COM-157 (Credit and Commercial Control,
-- CG-S7-COM-016) -- run via `pnpm run db:test` against a real, disposable Postgres
-- database.

\set ON_ERROR_STOP on

\echo '>> setup: one tenant, a company/branch/two-team org hierarchy, a rep (COM:Create/Edit/View/View selling price -- no Approve), an approver (COM:Approve/View/View selling price, assigned the routed Credit Approver role), a viewer (COM:View only -- masking test), a sibling-team outsider (same as rep but not assigned the approver role), and two full lead->prospect->opportunity->costing->rate->margin->quotation chains, both accepted and converted to accounts (A and B)'
do $$
declare
  v_tenant uuid;
  v_company uuid;
  v_branch uuid;
  v_team_a uuid;
  v_team_b uuid;
  v_rep_role uuid;
  v_rep_draft app.role_versions;
  v_approver_role_id uuid;
  v_viewer_role uuid;
  v_viewer_draft app.role_versions;
  v_outsider_role uuid;
  v_outsider_draft app.role_versions;
  v_config_draft app.config_versions;
  v_lead_a app.leads;
  v_lead_b app.leads;
  v_prospect_a app.prospects;
  v_prospect_b app.prospects;
  v_contact_a app.contacts;
  v_contact_b app.contacts;
  v_opportunity_a app.opportunities;
  v_opportunity_b app.opportunities;
  v_request_a app.costing_requests;
  v_request_b app.costing_requests;
  v_rate app.vendor_rate_versions;
  v_selection_a app.rate_selections;
  v_selection_b app.rate_selections;
  v_rule app.margin_rule_versions;
  v_calc_a_id uuid;
  v_calc_b_id uuid;
  v_quote_a app.quotations;
  v_quote_b app.quotations;
  v_send record;
begin
  insert into auth.users (id, email) values
    ('00000000-0000-0000-0000-000000010101', 'tenantadmin@acmecred.test'),
    ('00000000-0000-0000-0000-000000010102', 'rep@acmecred.test'),
    ('00000000-0000-0000-0000-000000010103', 'approver@acmecred.test'),
    ('00000000-0000-0000-0000-000000010104', 'viewer@acmecred.test'),
    ('00000000-0000-0000-0000-000000010105', 'outsider@acmecred.test');

  perform app.provision_tenant('acmecred', 'Acme Credit Co', 'idem-acmecred', 'tester');
  v_tenant := (select id from app.tenants where slug = 'acmecred');
  perform app.transition_tenant_status(v_tenant, 'active', 'setup', 'tester');

  perform app.create_org_unit(v_tenant, 'company', null, 'ACMECRED-CO', 'Acme Credit Co', 'tester');
  v_company := (select id from app.org_units where tenant_id = v_tenant and code = 'ACMECRED-CO');
  perform app.create_org_unit(v_tenant, 'branch', v_company, 'ACMECRED-BR', 'Jakarta Branch', 'tester');
  v_branch := (select id from app.org_units where tenant_id = v_tenant and code = 'ACMECRED-BR');
  perform app.create_org_unit(v_tenant, 'department', v_branch, 'ACMECRED-TEAM-A', 'Sales Team A', 'tester');
  v_team_a := (select id from app.org_units where tenant_id = v_tenant and code = 'ACMECRED-TEAM-A');
  perform app.create_org_unit(v_tenant, 'department', v_branch, 'ACMECRED-TEAM-B', 'Sales Team B', 'tester');
  v_team_b := (select id from app.org_units where tenant_id = v_tenant and code = 'ACMECRED-TEAM-B');

  perform app.invite_user(v_tenant, '00000000-0000-0000-0000-000000010101', 'tenantadmin@acmecred.test', 'Tenant Admin', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'tenantadmin@acmecred.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000010101', 'tenant_admin', v_tenant, null, 'tester');

  perform app.invite_user(v_tenant, '00000000-0000-0000-0000-000000010102', 'rep@acmecred.test', 'Rep', v_team_a, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'rep@acmecred.test'), 'active', 'onboarded', 'tester');
  perform app.invite_user(v_tenant, '00000000-0000-0000-0000-000000010103', 'approver@acmecred.test', 'Approver', v_team_a, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'approver@acmecred.test'), 'active', 'onboarded', 'tester');
  perform app.invite_user(v_tenant, '00000000-0000-0000-0000-000000010104', 'viewer@acmecred.test', 'Viewer', v_team_b, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'viewer@acmecred.test'), 'active', 'onboarded', 'tester');
  perform app.invite_user(v_tenant, '00000000-0000-0000-0000-000000010105', 'outsider@acmecred.test', 'Outsider', v_team_b, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'outsider@acmecred.test'), 'active', 'onboarded', 'tester');

  v_rep_role := (app.create_role(v_tenant, 'Credit Requester', 'requests credit profiles, no approve', 'tester')).id;
  v_rep_draft := app.create_role_version(v_rep_role, 'tester');
  perform app.set_role_version_permissions(
    v_rep_draft.id,
    array(select id from app.permissions where resource_module_code = 'COM' and action in ('Create', 'Edit', 'View', 'View selling price', 'View cost')),
    'tester'
  );
  perform app.publish_role_version(v_rep_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant, (select id from app.role_versions where role_id = v_rep_role and status = 'published'),
    '00000000-0000-0000-0000-000000010102', '00000000-0000-0000-0000-000000010101', 'tester');

  v_approver_role_id := (app.create_role(v_tenant, 'Credit Approver', 'decides/holds/releases/overrides credit', 'tester')).id;
  perform app.set_role_version_permissions(
    (app.create_role_version(v_approver_role_id, 'tester')).id,
    array(select id from app.permissions where resource_module_code = 'COM' and action in ('Create', 'Edit', 'Approve', 'View', 'View selling price')),
    'tester'
  );
  perform app.publish_role_version((select id from app.role_versions where role_id = v_approver_role_id and status = 'draft'), now(), 'tester');
  perform app.assign_role(v_tenant, (select id from app.role_versions where role_id = v_approver_role_id and status = 'published'),
    '00000000-0000-0000-0000-000000010103', '00000000-0000-0000-0000-000000010101', 'tester');

  v_viewer_role := (app.create_role(v_tenant, 'Credit Viewer', 'view only, masked', 'tester')).id;
  v_viewer_draft := app.create_role_version(v_viewer_role, 'tester');
  perform app.set_role_version_permissions(v_viewer_draft.id, array(select id from app.permissions where resource_module_code = 'COM' and action = 'View'), 'tester');
  perform app.publish_role_version(v_viewer_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant, (select id from app.role_versions where role_id = v_viewer_role and status = 'published'),
    '00000000-0000-0000-0000-000000010104', '00000000-0000-0000-0000-000000010101', 'tester');

  v_outsider_role := (app.create_role(v_tenant, 'Credit Outsider', 'not assigned the approver role', 'tester')).id;
  v_outsider_draft := app.create_role_version(v_outsider_role, 'tester');
  perform app.set_role_version_permissions(
    v_outsider_draft.id,
    array(select id from app.permissions where resource_module_code = 'COM' and action in ('Create', 'Edit', 'View', 'View selling price')),
    'tester'
  );
  perform app.publish_role_version(v_outsider_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant, (select id from app.role_versions where role_id = v_outsider_role and status = 'published'),
    '00000000-0000-0000-0000-000000010105', '00000000-0000-0000-0000-000000010101', 'tester');

  -- One-step sequential approval routing definition (Credit Approver only) via the
  -- already-VERIFIED PLT-121/PLT-123 generic RPCs -- no new SQL, the same reuse COM-153
  -- already established for quotations; this tenant's credit requests route through the
  -- exact same 'approval' config_type_code.
  select * into v_config_draft from app.create_config_draft('approval', v_tenant, 'tenant', null, '00000000-0000-0000-0000-000000010101', 'tenant admin');
  perform app.set_config_items(v_config_draft.id, jsonb_build_array(
    jsonb_build_object('key', 'pattern', 'value', 'sequential'),
    jsonb_build_object('key', 'steps', 'value', jsonb_build_array(
      jsonb_build_object('step_order', 1, 'approver_type', 'role', 'role_id', v_approver_role_id::text, 'required_approvals', 1)
    )),
    jsonb_build_object('key', 'allow_self_approval', 'value', false)
  ), '00000000-0000-0000-0000-000000010101', 'tenant admin');
  perform app.publish_approval_definition(v_config_draft.id, '00000000-0000-0000-0000-000000010101', null, 'tenant admin');

  -- Chain A ("Credit Test Co A")
  perform app.capture_lead(v_tenant, 'manual', null, 'Credit Test Co A', 'Jane Cred A', 'jane.a@acmecred.test', '0811',
    '00000000-0000-0000-0000-000000010102', v_team_a, '00000000-0000-0000-0000-000000010102', 'tester');
  select * into v_lead_a from app.leads where email = 'jane.a@acmecred.test';
  perform app.qualify_lead(v_lead_a.id, v_lead_a.record_version, '00000000-0000-0000-0000-000000010102', 'tester');
  select * into v_lead_a from app.leads where email = 'jane.a@acmecred.test';
  perform app.convert_lead_to_prospect(v_lead_a.id, 'Credit Test Co A', 'CredA', '33.333.333.3-333.000',
    jsonb_build_object('line1', 'Jl. Gatot Subroto 1', 'city', 'Jakarta', 'country', 'ID'),
    '00000000-0000-0000-0000-000000010102', 'tester');
  select * into v_prospect_a from app.prospects where lead_id = v_lead_a.id;
  select * into v_contact_a from app.create_contact(v_tenant, 'Jane Cred A', 'Finance Lead', 'jane.a@acmecred.test', '0811', '00000000-0000-0000-0000-000000010102', v_team_a, '00000000-0000-0000-0000-000000010102', 'tester');
  perform app.link_contact_to_record(v_contact_a.id, 'prospect', v_prospect_a.id, 'primary', true, '00000000-0000-0000-0000-000000010102', 'tester');
  select * into v_opportunity_a from app.create_opportunity(
    v_tenant, v_prospect_a.id, 'CredCo A ocean lane',
    jsonb_build_object('service_type', 'ocean_freight', 'cargo_description', 'General cargo', 'origin', 'Jakarta', 'destination', 'Surabaya', 'target_ready_date', '2026-08-01'),
    '00000000-0000-0000-0000-000000010102', v_team_a, '00000000-0000-0000-0000-000000010102', 'tester'
  );
  select * into v_request_a from app.request_costing(v_opportunity_a.id, '[]'::jsonb, null, '00000000-0000-0000-0000-000000010102', 'tester');

  select * into v_rate from app.create_rate_version(
    v_tenant, 'VENDOR-CRED-1', 'Contoso Ocean Line', 'ocean_freight', 'FCL', 'Jakarta', 'Surabaya', '20ft',
    null, null, null, null, 'IDR', 10000000, null, '[]'::jsonb, now(), null, null,
    '00000000-0000-0000-0000-000000010101', 'tester'
  );
  perform app.approve_rate_version(v_rate.id, v_rate.record_version, '00000000-0000-0000-0000-000000010101', 'tester');
  select * into v_selection_a from app.select_vendor_rate(v_request_a.id, v_rate.id, false, null, null, null, '00000000-0000-0000-0000-000000010102', 'tester');

  select * into v_rule from app.create_margin_rule_version(v_tenant, 20.00, 'half_up', '00000000-0000-0000-0000-000000010102', 'tester');
  perform app.publish_margin_rule_version(v_rule.id, v_rule.record_version, null, '00000000-0000-0000-0000-000000010103', 'tester');
  perform app.calculate_margin(v_selection_a.id, 15000000, 'IDR', 0, '00000000-0000-0000-0000-000000010102', 'tester');
  select id into v_calc_a_id from app.margin_calculations where rate_selection_id = v_selection_a.id and is_current;

  select * into v_quote_a from app.create_quotation_draft(v_tenant, v_opportunity_a.id, 'IDR', now() + interval '14 days', v_contact_a.id, null, null, '00000000-0000-0000-0000-000000010102', 'tester');
  perform app.add_quotation_line(v_quote_a.id, v_quote_a.record_version, 'service', 'Ocean freight', v_calc_a_id, 1, 15000000, 0, 0, '00000000-0000-0000-0000-000000010102', 'tester');
  select * into v_quote_a from app.quotations where id = v_quote_a.id;
  perform app.submit_quotation(v_quote_a.id, v_quote_a.record_version, '00000000-0000-0000-0000-000000010102', 'tester');
  select * into v_send from app.send_quotation_for_acceptance(v_quote_a.id, null, 'email', '00000000-0000-0000-0000-000000010102', 'tester');
  perform app.record_quotation_customer_decision(v_send.raw_token, 'accepted', 'Jane Cred A', null, null, null, null, null);
  perform app.convert_quotation_to_account(v_quote_a.id, null, null, '00000000-0000-0000-0000-000000010103', 'approver');

  -- Chain B ("Credit Test Co B")
  perform app.capture_lead(v_tenant, 'manual', null, 'Credit Test Co B', 'Jane Cred B', 'jane.b@acmecred.test', '0812',
    '00000000-0000-0000-0000-000000010102', v_team_a, '00000000-0000-0000-0000-000000010102', 'tester');
  select * into v_lead_b from app.leads where email = 'jane.b@acmecred.test';
  perform app.qualify_lead(v_lead_b.id, v_lead_b.record_version, '00000000-0000-0000-0000-000000010102', 'tester');
  select * into v_lead_b from app.leads where email = 'jane.b@acmecred.test';
  perform app.convert_lead_to_prospect(v_lead_b.id, 'Credit Test Co B', 'CredB', '44.444.444.4-444.000',
    jsonb_build_object('line1', 'Jl. Sudirman 99', 'city', 'Jakarta', 'country', 'ID'),
    '00000000-0000-0000-0000-000000010102', 'tester');
  select * into v_prospect_b from app.prospects where lead_id = v_lead_b.id;
  select * into v_contact_b from app.create_contact(v_tenant, 'Jane Cred B', 'Finance Lead', 'jane.b@acmecred.test', '0812', '00000000-0000-0000-0000-000000010102', v_team_a, '00000000-0000-0000-0000-000000010102', 'tester');
  perform app.link_contact_to_record(v_contact_b.id, 'prospect', v_prospect_b.id, 'primary', true, '00000000-0000-0000-0000-000000010102', 'tester');
  select * into v_opportunity_b from app.create_opportunity(
    v_tenant, v_prospect_b.id, 'CredCo B ocean lane',
    jsonb_build_object('service_type', 'ocean_freight', 'cargo_description', 'General cargo', 'origin', 'Jakarta', 'destination', 'Surabaya', 'target_ready_date', '2026-08-01'),
    '00000000-0000-0000-0000-000000010102', v_team_a, '00000000-0000-0000-0000-000000010102', 'tester'
  );
  select * into v_request_b from app.request_costing(v_opportunity_b.id, '[]'::jsonb, null, '00000000-0000-0000-0000-000000010102', 'tester');
  select * into v_selection_b from app.select_vendor_rate(v_request_b.id, v_rate.id, false, null, null, null, '00000000-0000-0000-0000-000000010102', 'tester');
  perform app.calculate_margin(v_selection_b.id, 15000000, 'IDR', 0, '00000000-0000-0000-0000-000000010102', 'tester');
  select id into v_calc_b_id from app.margin_calculations where rate_selection_id = v_selection_b.id and is_current;

  select * into v_quote_b from app.create_quotation_draft(v_tenant, v_opportunity_b.id, 'IDR', now() + interval '14 days', v_contact_b.id, null, null, '00000000-0000-0000-0000-000000010102', 'tester');
  perform app.add_quotation_line(v_quote_b.id, v_quote_b.record_version, 'service', 'Ocean freight', v_calc_b_id, 1, 15000000, 0, 0, '00000000-0000-0000-0000-000000010102', 'tester');
  select * into v_quote_b from app.quotations where id = v_quote_b.id;
  perform app.submit_quotation(v_quote_b.id, v_quote_b.record_version, '00000000-0000-0000-0000-000000010102', 'tester');
  select * into v_send from app.send_quotation_for_acceptance(v_quote_b.id, null, 'email', '00000000-0000-0000-0000-000000010102', 'tester');
  perform app.record_quotation_customer_decision(v_send.raw_token, 'accepted', 'Jane Cred B', null, null, null, null, null);
  perform app.convert_quotation_to_account(v_quote_b.id, null, null, '00000000-0000-0000-0000-000000010103', 'approver');
end;
$$;

\echo '>> app.request_customer_credit_profile: authority-gated (the viewer lacks COM:Create is denied); creates status=requested, routed to the published approval definition; a second request while one is already live is rejected'
do $$
declare
  v_tenant uuid;
  v_account_a_id uuid;
  v_profile app.credit_profiles;
begin
  v_tenant := (select id from app.tenants where slug = 'acmecred');
  select account_id into v_account_a_id from app.account_conversions where quotation_id = (select id from app.quotations where customer_snapshot ->> 'legal_name' = 'Credit Test Co A');

  begin
    perform app.request_customer_credit_profile(v_tenant, v_account_a_id, 'IDR', 50000000, '00000000-0000-0000-0000-000000010104', 'viewer');
    raise exception 'assertion failed: expected insufficient_privilege -- the viewer lacks COM:Create';
  exception
    when insufficient_privilege then
      null; -- expected
  end;

  select * into v_profile from app.request_customer_credit_profile(v_tenant, v_account_a_id, 'IDR', 50000000, '00000000-0000-0000-0000-000000010102', 'rep');
  if v_profile.status <> 'requested' or v_profile.approval_request_id is null or v_profile.requested_limit_amount <> 50000000 then
    raise exception 'assertion failed: expected status=requested with a bound approval_request_id and requested_limit_amount=50000000, got status=% approval_request_id=% amount=%', v_profile.status, v_profile.approval_request_id, v_profile.requested_limit_amount;
  end if;

  begin
    perform app.request_customer_credit_profile(v_tenant, v_account_a_id, 'IDR', 60000000, '00000000-0000-0000-0000-000000010102', 'rep');
    raise exception 'assertion failed: expected credit_profile_already_requested on a second live request for the same account';
  exception
    when unique_violation then
      null; -- expected
  end;
end;
$$;

\echo '>> app.decide_credit_profile_approval_step: stale/missing reauth is denied; an ineligible approver (outsider, not assigned the routed role) is denied; the assigned approver decides -- profile becomes status=active with approved_limit_amount set'
do $$
declare
  v_profile app.credit_profiles;
  v_step_id uuid;
begin
  select * into v_profile from app.credit_profiles where status = 'requested' and account_id = (select account_id from app.account_conversions where quotation_id = (select id from app.quotations where customer_snapshot ->> 'legal_name' = 'Credit Test Co A'));
  select id into v_step_id from app.approval_request_steps where request_id = v_profile.approval_request_id and step_order = 1;

  begin
    perform app.decide_credit_profile_approval_step(v_step_id, 'approved', 'Looks good', null, '00000000-0000-0000-0000-000000010103', 'approver');
    raise exception 'assertion failed: expected reauth_required with a null reauth timestamp';
  exception
    when insufficient_privilege then
      if sqlerrm not like 'reauth_required:%' then
        raise exception 'assertion failed: expected reauth_required, got %', sqlerrm;
      end if;
  end;

  begin
    perform app.decide_credit_profile_approval_step(v_step_id, 'approved', 'Looks good', now() - interval '10 minutes', '00000000-0000-0000-0000-000000010103', 'approver');
    raise exception 'assertion failed: expected reauth_required with a stale (>5 minute) reauth timestamp';
  exception
    when insufficient_privilege then
      if sqlerrm not like 'reauth_required:%' then
        raise exception 'assertion failed: expected reauth_required, got %', sqlerrm;
      end if;
  end;

  begin
    perform app.decide_credit_profile_approval_step(v_step_id, 'approved', 'Looks good', now(), '00000000-0000-0000-0000-000000010105', 'outsider');
    raise exception 'assertion failed: expected insufficient_privilege -- the outsider is not assigned the routed Credit Approver role';
  exception
    when insufficient_privilege then
      null; -- expected (app.decide_approval_step's own eligibility check)
  end;

  select * into v_profile from app.decide_credit_profile_approval_step(v_step_id, 'approved', 'Looks good', now(), '00000000-0000-0000-0000-000000010103', 'approver');
  if v_profile.status <> 'active' or v_profile.approved_limit_amount <> 50000000 or v_profile.effective_from is null then
    raise exception 'assertion failed: expected status=active approved_limit_amount=50000000 effective_from set, got status=% approved_limit_amount=% effective_from=%', v_profile.status, v_profile.approved_limit_amount, v_profile.effective_from;
  end if;
end;
$$;

\echo '>> app.check_customer_credit: allow within limit; blocked_limit above it; blocked_currency_mismatch on the wrong currency; blocked_no_profile for an account with no profile at all; every check produces a real, persisted snapshot row'
do $$
declare
  v_tenant uuid;
  v_account_a_id uuid;
  v_account_b_id uuid;
  v_outcome text;
  v_effective_limit numeric;
  v_snapshot_count integer;
begin
  v_tenant := (select id from app.tenants where slug = 'acmecred');
  select account_id into v_account_a_id from app.account_conversions where quotation_id = (select id from app.quotations where customer_snapshot ->> 'legal_name' = 'Credit Test Co A');
  select account_id into v_account_b_id from app.account_conversions where quotation_id = (select id from app.quotations where customer_snapshot ->> 'legal_name' = 'Credit Test Co B');

  select outcome, effective_limit_amount into v_outcome, v_effective_limit from app.check_customer_credit(v_tenant, v_account_a_id, 'IDR', 30000000, 'quotation', null, '00000000-0000-0000-0000-000000010103', 'approver');
  if v_outcome <> 'allow' or v_effective_limit <> 50000000 then
    raise exception 'assertion failed: expected allow with effective_limit_amount=50000000, got outcome=% limit=%', v_outcome, v_effective_limit;
  end if;

  select outcome into v_outcome from app.check_customer_credit(v_tenant, v_account_a_id, 'IDR', 90000000, 'quotation', null, '00000000-0000-0000-0000-000000010103', 'approver');
  if v_outcome <> 'blocked_limit' then
    raise exception 'assertion failed: expected blocked_limit for an amount above the approved limit, got %', v_outcome;
  end if;

  select outcome into v_outcome from app.check_customer_credit(v_tenant, v_account_a_id, 'USD', 100, 'quotation', null, '00000000-0000-0000-0000-000000010103', 'approver');
  if v_outcome <> 'blocked_currency_mismatch' then
    raise exception 'assertion failed: expected blocked_currency_mismatch for a currency the profile was not approved in, got %', v_outcome;
  end if;

  select outcome, effective_limit_amount into v_outcome, v_effective_limit from app.check_customer_credit(v_tenant, v_account_b_id, 'IDR', 100, 'quotation', null, '00000000-0000-0000-0000-000000010103', 'approver');
  if v_outcome <> 'blocked_no_profile' or v_effective_limit is not null then
    raise exception 'assertion failed: expected blocked_no_profile with a null effective_limit_amount for an account with no credit profile at all, got outcome=% limit=%', v_outcome, v_effective_limit;
  end if;

  select count(*) into v_snapshot_count from app.credit_check_snapshots where account_id in (v_account_a_id, v_account_b_id);
  if v_snapshot_count <> 4 then
    raise exception 'assertion failed: expected exactly 4 persisted check snapshots (one per check above), got %', v_snapshot_count;
  end if;
end;
$$;

\echo '>> app.check_customer_credit masking: the viewer (no COM:View selling price) sees the real outcome but null currency/requested_amount/effective_limit_amount and amount_masked=true'
do $$
declare
  v_tenant uuid;
  v_account_a_id uuid;
  v_outcome text;
  v_currency text;
  v_effective_limit numeric;
  v_masked boolean;
begin
  v_tenant := (select id from app.tenants where slug = 'acmecred');
  select account_id into v_account_a_id from app.account_conversions where quotation_id = (select id from app.quotations where customer_snapshot ->> 'legal_name' = 'Credit Test Co A');

  select outcome, currency, effective_limit_amount, amount_masked into v_outcome, v_currency, v_effective_limit, v_masked
  from app.check_customer_credit(v_tenant, v_account_a_id, 'IDR', 30000000, 'quotation', null, '00000000-0000-0000-0000-000000010104', 'viewer');
  if v_outcome <> 'allow' or v_currency is not null or v_effective_limit is not null or not v_masked then
    raise exception 'assertion failed: expected outcome=allow (never masked) but currency/effective_limit_amount null and amount_masked=true for the viewer, got outcome=% currency=% limit=% masked=%', v_outcome, v_currency, v_effective_limit, v_masked;
  end if;
end;
$$;

\echo '>> app.hold_credit_profile / app.release_credit_profile: reauth and authority gated (rep lacks COM:Approve); hold blocks the check (blocked_hold); release restores allow'
do $$
declare
  v_profile app.credit_profiles;
  v_outcome text;
  v_tenant uuid;
  v_account_a_id uuid;
begin
  v_tenant := (select id from app.tenants where slug = 'acmecred');
  select account_id into v_account_a_id from app.account_conversions where quotation_id = (select id from app.quotations where customer_snapshot ->> 'legal_name' = 'Credit Test Co A');
  select * into v_profile from app.credit_profiles where account_id = v_account_a_id and status = 'active';

  begin
    perform app.hold_credit_profile(v_profile.id, v_profile.record_version, 'Overdue invoice', now(), '00000000-0000-0000-0000-000000010102', 'rep');
    raise exception 'assertion failed: expected insufficient_privilege -- rep lacks COM:Approve';
  exception
    when insufficient_privilege then
      null; -- expected
  end;

  select * into v_profile from app.hold_credit_profile(v_profile.id, v_profile.record_version, 'Overdue invoice', now(), '00000000-0000-0000-0000-000000010103', 'approver');
  if v_profile.status <> 'held' or v_profile.hold_reason <> 'Overdue invoice' then
    raise exception 'assertion failed: expected status=held with the given reason, got status=% reason=%', v_profile.status, v_profile.hold_reason;
  end if;

  select outcome into v_outcome from app.check_customer_credit(v_tenant, v_account_a_id, 'IDR', 100, 'quotation', null, '00000000-0000-0000-0000-000000010103', 'approver');
  if v_outcome <> 'blocked_hold' then
    raise exception 'assertion failed: expected blocked_hold while the profile is on hold, got %', v_outcome;
  end if;

  select * into v_profile from app.release_credit_profile(v_profile.id, v_profile.record_version, now(), '00000000-0000-0000-0000-000000010103', 'approver');
  if v_profile.status <> 'active' or v_profile.hold_reason is not null then
    raise exception 'assertion failed: expected status=active with hold_reason cleared after release, got status=% reason=%', v_profile.status, v_profile.hold_reason;
  end if;

  select outcome into v_outcome from app.check_customer_credit(v_tenant, v_account_a_id, 'IDR', 30000000, 'quotation', null, '00000000-0000-0000-0000-000000010103', 'approver');
  if v_outcome <> 'allow' then
    raise exception 'assertion failed: expected allow again after release, got %', v_outcome;
  end if;
end;
$$;

\echo '>> app.create_credit_override: reauth/reason/expiry/authority validated; a valid override raises the effective limit for exactly the override amount, not silently combined with the approved limit'
do $$
declare
  v_profile app.credit_profiles;
  v_override app.credit_profile_overrides;
  v_outcome text;
  v_effective_limit numeric;
  v_tenant uuid;
  v_account_a_id uuid;
begin
  v_tenant := (select id from app.tenants where slug = 'acmecred');
  select account_id into v_account_a_id from app.account_conversions where quotation_id = (select id from app.quotations where customer_snapshot ->> 'legal_name' = 'Credit Test Co A');
  select * into v_profile from app.credit_profiles where account_id = v_account_a_id and status = 'active';

  begin
    perform app.create_credit_override(v_profile.id, 80000000, '', now() + interval '1 day', now(), '00000000-0000-0000-0000-000000010103', 'approver');
    raise exception 'assertion failed: expected reason_required for an empty reason';
  exception
    when not_null_violation then
      null; -- expected
  end;

  begin
    perform app.create_credit_override(v_profile.id, 80000000, 'One-time large shipment', now() - interval '1 day', now(), '00000000-0000-0000-0000-000000010103', 'approver');
    raise exception 'assertion failed: expected invalid_expiry for an expiry in the past';
  exception
    when check_violation then
      null; -- expected
  end;

  begin
    perform app.create_credit_override(v_profile.id, 80000000, 'One-time large shipment', now() + interval '1 day', null, '00000000-0000-0000-0000-000000010103', 'approver');
    raise exception 'assertion failed: expected reauth_required with no reauth timestamp';
  exception
    when insufficient_privilege then
      null; -- expected
  end;

  begin
    perform app.create_credit_override(v_profile.id, 80000000, 'One-time large shipment', now() + interval '1 day', now(), '00000000-0000-0000-0000-000000010102', 'rep');
    raise exception 'assertion failed: expected insufficient_privilege -- rep lacks COM:Approve (the "elevated approval" this action needs)';
  exception
    when insufficient_privilege then
      null; -- expected
  end;

  select * into v_override from app.create_credit_override(v_profile.id, 80000000, 'One-time large shipment', now() + interval '1 day', now(), '00000000-0000-0000-0000-000000010103', 'approver');
  if v_override.amount <> 80000000 then
    raise exception 'assertion failed: expected the override amount to be 80000000, got %', v_override.amount;
  end if;

  select outcome, effective_limit_amount into v_outcome, v_effective_limit from app.check_customer_credit(v_tenant, v_account_a_id, 'IDR', 70000000, 'quotation', null, '00000000-0000-0000-0000-000000010103', 'approver');
  if v_outcome <> 'allow' or v_effective_limit <> 80000000 then
    raise exception 'assertion failed: expected allow with effective_limit_amount=80000000 (the override, not the 50000000 approved limit), got outcome=% limit=%', v_outcome, v_effective_limit;
  end if;

  select outcome into v_outcome from app.check_customer_credit(v_tenant, v_account_a_id, 'IDR', 90000000, 'quotation', null, '00000000-0000-0000-0000-000000010103', 'approver');
  if v_outcome <> 'blocked_limit' then
    raise exception 'assertion failed: expected blocked_limit above even the overridden 80000000 limit, got %', v_outcome;
  end if;
end;
$$;

\echo '>> lazy expiry on check: backdating effective_to past now() flips an active profile to expired on the next check, and the flip is persisted, not just reported'
do $$
declare
  v_profile app.credit_profiles;
  v_outcome text;
  v_tenant uuid;
  v_account_a_id uuid;
  v_status_after text;
begin
  v_tenant := (select id from app.tenants where slug = 'acmecred');
  select account_id into v_account_a_id from app.account_conversions where quotation_id = (select id from app.quotations where customer_snapshot ->> 'legal_name' = 'Credit Test Co A');
  select * into v_profile from app.credit_profiles where account_id = v_account_a_id and status = 'active';

  update app.credit_profiles set effective_from = now() - interval '2 days', effective_to = now() - interval '1 day' where id = v_profile.id;

  select outcome into v_outcome from app.check_customer_credit(v_tenant, v_account_a_id, 'IDR', 100, 'quotation', null, '00000000-0000-0000-0000-000000010103', 'approver');
  if v_outcome <> 'blocked_not_active' then
    raise exception 'assertion failed: expected blocked_not_active once the profile''s own effective_to has passed, got %', v_outcome;
  end if;

  select status into v_status_after from app.credit_profiles where id = v_profile.id;
  if v_status_after <> 'expired' then
    raise exception 'assertion failed: expected the profile to be lazily flipped to status=expired in the database, got %', v_status_after;
  end if;
end;
$$;

\echo '>> a fresh request after rejection: an approver decision of "rejected" sets status=rejected with the reason; a new request for the same account links back via supersedes_profile_id'
do $$
declare
  v_tenant uuid;
  v_account_b_id uuid;
  v_profile app.credit_profiles;
  v_step_id uuid;
  v_rejected_id uuid;
  v_new_profile app.credit_profiles;
begin
  v_tenant := (select id from app.tenants where slug = 'acmecred');
  select account_id into v_account_b_id from app.account_conversions where quotation_id = (select id from app.quotations where customer_snapshot ->> 'legal_name' = 'Credit Test Co B');

  select * into v_profile from app.request_customer_credit_profile(v_tenant, v_account_b_id, 'IDR', 40000000, '00000000-0000-0000-0000-000000010102', 'rep');
  select id into v_step_id from app.approval_request_steps where request_id = v_profile.approval_request_id and step_order = 1;

  select * into v_profile from app.decide_credit_profile_approval_step(v_step_id, 'rejected', 'Insufficient trade history', now(), '00000000-0000-0000-0000-000000010103', 'approver');
  if v_profile.status <> 'rejected' or v_profile.rejected_reason <> 'Insufficient trade history' then
    raise exception 'assertion failed: expected status=rejected with the given reason, got status=% reason=%', v_profile.status, v_profile.rejected_reason;
  end if;
  v_rejected_id := v_profile.id;

  select * into v_new_profile from app.request_customer_credit_profile(v_tenant, v_account_b_id, 'IDR', 20000000, '00000000-0000-0000-0000-000000010102', 'rep');
  if v_new_profile.supersedes_profile_id <> v_rejected_id then
    raise exception 'assertion failed: expected the fresh request to link back to the rejected profile via supersedes_profile_id, got %', v_new_profile.supersedes_profile_id;
  end if;
end;
$$;

\echo '>> app.credit_profiles / app.credit_profiles_directory / app.credit_check_snapshots_directory: tenant-wide visibility -- the sibling-team outsider (no ownership stake) sees every profile and every masked check snapshot'
do $$
declare
  v_count integer;
begin
  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000010105", "role": "authenticated"}';

  select count(*) into v_count from app.credit_profiles where tenant_id = (select id from app.tenants where slug = 'acmecred');
  if v_count < 3 then
    raise exception 'assertion failed: expected the outsider to see every credit profile tenant-wide, got %', v_count;
  end if;

  select count(*) into v_count from app.credit_check_snapshots_directory where tenant_id = (select id from app.tenants where slug = 'acmecred');
  if v_count < 4 then
    raise exception 'assertion failed: expected the outsider to see every masked check snapshot tenant-wide, got %', v_count;
  end if;

  reset role;
end;
$$;

\echo '>> schema-privilege defense in depth: authenticated has no direct column access to approved_limit_amount on app.credit_profiles itself'
do $$
declare
  v_profile_id uuid;
begin
  select id into v_profile_id from app.credit_profiles limit 1;

  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000010102", "role": "authenticated"}';
  begin
    perform approved_limit_amount from app.credit_profiles where id = v_profile_id;
    raise exception 'assertion failed: expected a real Postgres permission-denied error selecting approved_limit_amount directly from app.credit_profiles';
  exception
    when insufficient_privilege then
      null; -- expected
  end;
  reset role;
end;
$$;

\echo '>> full tenant-scoped audit trail: 3 successful request_customer_credit_profile, 1 successful hold, 1 successful release, 1 successful create_credit_override'
do $$
declare
  v_tenant uuid;
  v_request_count integer;
  v_hold_count integer;
  v_release_count integer;
  v_override_count integer;
begin
  v_tenant := (select id from app.tenants where slug = 'acmecred');

  select count(*) into v_request_count from app.audit_logs where tenant_id = v_tenant and action = 'request_customer_credit_profile' and result = 'success';
  select count(*) into v_hold_count from app.audit_logs where tenant_id = v_tenant and action = 'hold_credit_profile' and result = 'success';
  select count(*) into v_release_count from app.audit_logs where tenant_id = v_tenant and action = 'release_credit_profile' and result = 'success';
  select count(*) into v_override_count from app.audit_logs where tenant_id = v_tenant and action = 'create_credit_override' and result = 'success';

  if v_request_count <> 3 or v_hold_count <> 1 or v_release_count <> 1 or v_override_count <> 1 then
    raise exception 'assertion failed: expected request=3 hold=1 release=1 override=1, got request=% hold=% release=% override=%', v_request_count, v_hold_count, v_release_count, v_override_count;
  end if;
end;
$$;
