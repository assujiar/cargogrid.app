-- Real, executable test evidence for COM-155 (Customer and Account Conversion,
-- CG-S7-COM-014) -- run via `pnpm run db:test` against a real, disposable Postgres
-- database.

\set ON_ERROR_STOP on

\echo '>> setup: one tenant, a company/branch/two-team org hierarchy, a rep (COM:Create/Edit/Approve/View/View selling price/View cost), a sibling-team outsider (same permissions minus Approve), two prospects sharing one legal identity (Duplicate Test Co), a contact linked to prospect 1, and a full opportunity/costing/rate/margin chain reused across both prospects, ending with two accepted quotations (1 and 2)'
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
  v_lead1 app.leads;
  v_lead2 app.leads;
  v_prospect1 app.prospects;
  v_prospect2 app.prospects;
  v_contact1 app.contacts;
  v_contact2 app.contacts;
  v_opportunity1 app.opportunities;
  v_opportunity2 app.opportunities;
  v_request1 app.costing_requests;
  v_request2 app.costing_requests;
  v_rate app.vendor_rate_versions;
  v_selection1 app.rate_selections;
  v_selection2 app.rate_selections;
  v_rule app.margin_rule_versions;
  v_calc1_id uuid;
  v_calc2_id uuid;
  v_quote1 app.quotations;
  v_quote2 app.quotations;
  v_send record;
begin
  insert into auth.users (id, email) values
    ('00000000-0000-0000-0000-000000009801', 'tenantadmin@acmeconv.test'),
    ('00000000-0000-0000-0000-000000009802', 'rep@acmeconv.test'),
    ('00000000-0000-0000-0000-000000009803', 'outsider@acmeconv.test');

  perform app.provision_tenant('acmeconv', 'Acme Conversion Co', 'idem-acmeconv', 'tester');
  v_tenant1 := (select id from app.tenants where slug = 'acmeconv');
  perform app.transition_tenant_status(v_tenant1, 'active', 'setup', 'tester');

  perform app.create_org_unit(v_tenant1, 'company', null, 'ACMECONV-CO', 'Acme Conversion Co', 'tester');
  v_company := (select id from app.org_units where tenant_id = v_tenant1 and code = 'ACMECONV-CO');
  perform app.create_org_unit(v_tenant1, 'branch', v_company, 'ACMECONV-BR', 'Jakarta Branch', 'tester');
  v_branch := (select id from app.org_units where tenant_id = v_tenant1 and code = 'ACMECONV-BR');
  perform app.create_org_unit(v_tenant1, 'department', v_branch, 'ACMECONV-TEAM-A', 'Sales Team A', 'tester');
  v_team_a := (select id from app.org_units where tenant_id = v_tenant1 and code = 'ACMECONV-TEAM-A');
  perform app.create_org_unit(v_tenant1, 'department', v_branch, 'ACMECONV-TEAM-B', 'Sales Team B', 'tester');
  v_team_b := (select id from app.org_units where tenant_id = v_tenant1 and code = 'ACMECONV-TEAM-B');

  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000009801', 'tenantadmin@acmeconv.test', 'Tenant Admin', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'tenantadmin@acmeconv.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000009801', 'tenant_admin', v_tenant1, null, 'tester');

  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000009802', 'rep@acmeconv.test', 'Rep', v_team_a, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'rep@acmeconv.test'), 'active', 'onboarded', 'tester');
  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000009803', 'outsider@acmeconv.test', 'Team B Outsider', v_team_b, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'outsider@acmeconv.test'), 'active', 'onboarded', 'tester');

  v_rep_role := (app.create_role(v_tenant1, 'Conversion Rep', 'account conversion', 'tester')).id;
  v_rep_draft := app.create_role_version(v_rep_role, 'tester');
  perform app.set_role_version_permissions(
    v_rep_draft.id,
    array(select id from app.permissions where resource_module_code = 'COM' and action in ('Create', 'Edit', 'Approve', 'View', 'View selling price', 'View cost')),
    'tester'
  );
  perform app.publish_role_version(v_rep_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_rep_role and status = 'published'),
    '00000000-0000-0000-0000-000000009802', '00000000-0000-0000-0000-000000009801', 'tester');

  v_out_role := (app.create_role(v_tenant1, 'Team B Conversion Rep', 'sibling team, no Approve', 'tester')).id;
  v_out_draft := app.create_role_version(v_out_role, 'tester');
  perform app.set_role_version_permissions(
    v_out_draft.id,
    array(select id from app.permissions where resource_module_code = 'COM' and action in ('Create', 'Edit', 'View', 'View selling price', 'View cost')),
    'tester'
  );
  perform app.publish_role_version(v_out_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_out_role and status = 'published'),
    '00000000-0000-0000-0000-000000009803', '00000000-0000-0000-0000-000000009801', 'tester');

  -- Two independently-captured leads that both convert to prospects sharing the same
  -- real-world legal identity (a genuine "someone re-entered the same company" scenario).
  perform app.capture_lead(v_tenant1, 'manual', null, 'Duplicate Test Co', 'Jane Doe Conv', 'jane1@dupconv.test', '0811',
    '00000000-0000-0000-0000-000000009802', v_team_a, '00000000-0000-0000-0000-000000009802', 'tester');
  select * into v_lead1 from app.leads where email = 'jane1@dupconv.test';
  perform app.qualify_lead(v_lead1.id, v_lead1.record_version, '00000000-0000-0000-0000-000000009802', 'tester');
  select * into v_lead1 from app.leads where email = 'jane1@dupconv.test';
  perform app.convert_lead_to_prospect(v_lead1.id, 'Duplicate Test Co', 'DupCo', '11.111.111.1-111.000',
    jsonb_build_object('line1', 'Jl. Sudirman 1', 'city', 'Jakarta', 'country', 'ID'),
    '00000000-0000-0000-0000-000000009802', 'tester');
  select * into v_prospect1 from app.prospects where lead_id = v_lead1.id;

  perform app.capture_lead(v_tenant1, 'manual', null, 'Duplicate Test Co', 'John Roe Conv', 'john2@dupconv.test', '0822',
    '00000000-0000-0000-0000-000000009802', v_team_a, '00000000-0000-0000-0000-000000009802', 'tester');
  select * into v_lead2 from app.leads where email = 'john2@dupconv.test';
  perform app.qualify_lead(v_lead2.id, v_lead2.record_version, '00000000-0000-0000-0000-000000009802', 'tester');
  select * into v_lead2 from app.leads where email = 'john2@dupconv.test';
  perform app.convert_lead_to_prospect(v_lead2.id, 'Duplicate Test Co', 'DupCo', '11.111.111.1-111.000',
    jsonb_build_object('line1', 'Jl. Sudirman 1', 'city', 'Jakarta', 'country', 'ID'),
    '00000000-0000-0000-0000-000000009802', 'tester');
  select * into v_prospect2 from app.prospects where lead_id = v_lead2.id;

  select * into v_contact1 from app.create_contact(v_tenant1, 'Jane Doe Conv', 'Procurement Lead', 'jane1@dupconv.test', '0811', '00000000-0000-0000-0000-000000009802', v_team_a, '00000000-0000-0000-0000-000000009802', 'tester');
  perform app.link_contact_to_record(v_contact1.id, 'prospect', v_prospect1.id, 'primary', true, '00000000-0000-0000-0000-000000009802', 'tester');
  select * into v_contact2 from app.create_contact(v_tenant1, 'John Roe Conv', 'Procurement Lead', 'john2@dupconv.test', '0822', '00000000-0000-0000-0000-000000009802', v_team_a, '00000000-0000-0000-0000-000000009802', 'tester');
  perform app.link_contact_to_record(v_contact2.id, 'prospect', v_prospect2.id, 'primary', true, '00000000-0000-0000-0000-000000009802', 'tester');

  select * into v_opportunity1 from app.create_opportunity(
    v_tenant1, v_prospect1.id, 'DupCo lane 1',
    jsonb_build_object('service_type', 'ocean_freight', 'cargo_description', 'General cargo', 'origin', 'Jakarta', 'destination', 'Surabaya', 'target_ready_date', '2026-08-01'),
    '00000000-0000-0000-0000-000000009802', v_team_a, '00000000-0000-0000-0000-000000009802', 'tester'
  );
  select * into v_opportunity2 from app.create_opportunity(
    v_tenant1, v_prospect2.id, 'DupCo lane 2',
    jsonb_build_object('service_type', 'ocean_freight', 'cargo_description', 'General cargo', 'origin', 'Jakarta', 'destination', 'Surabaya', 'target_ready_date', '2026-08-01'),
    '00000000-0000-0000-0000-000000009802', v_team_a, '00000000-0000-0000-0000-000000009802', 'tester'
  );

  select * into v_request1 from app.request_costing(v_opportunity1.id, '[]'::jsonb, null, '00000000-0000-0000-0000-000000009802', 'tester');
  select * into v_request2 from app.request_costing(v_opportunity2.id, '[]'::jsonb, null, '00000000-0000-0000-0000-000000009802', 'tester');

  select * into v_rate from app.create_rate_version(
    v_tenant1, 'VENDOR-CONV-1', 'Contoso Ocean Line', 'ocean_freight', 'FCL', 'Jakarta', 'Surabaya', '20ft',
    null, null, null, null, 'IDR', 10000000, null, '[]'::jsonb, now(), null, null,
    '00000000-0000-0000-0000-000000009801', 'tester'
  );
  perform app.approve_rate_version(v_rate.id, v_rate.record_version, '00000000-0000-0000-0000-000000009801', 'tester');
  select * into v_selection1 from app.select_vendor_rate(v_request1.id, v_rate.id, false, null, null, null, '00000000-0000-0000-0000-000000009802', 'tester');
  select * into v_selection2 from app.select_vendor_rate(v_request2.id, v_rate.id, false, null, null, null, '00000000-0000-0000-0000-000000009802', 'tester');

  select * into v_rule from app.create_margin_rule_version(v_tenant1, 20.00, 'half_up', '00000000-0000-0000-0000-000000009802', 'tester');
  perform app.publish_margin_rule_version(v_rule.id, v_rule.record_version, null, '00000000-0000-0000-0000-000000009802', 'tester');
  perform app.calculate_margin(v_selection1.id, 15000000, 'IDR', 0, '00000000-0000-0000-0000-000000009802', 'tester');
  perform app.calculate_margin(v_selection2.id, 15000000, 'IDR', 0, '00000000-0000-0000-0000-000000009802', 'tester');
  select id into v_calc1_id from app.margin_calculations where rate_selection_id = v_selection1.id and is_current;
  select id into v_calc2_id from app.margin_calculations where rate_selection_id = v_selection2.id and is_current;

  select * into v_quote1 from app.create_quotation_draft(v_tenant1, v_opportunity1.id, 'IDR', now() + interval '14 days', v_contact1.id, null, null, '00000000-0000-0000-0000-000000009802', 'tester');
  perform app.add_quotation_line(v_quote1.id, v_quote1.record_version, 'service', 'Ocean freight lane 1', v_calc1_id, 1, 15000000, 0, 0, '00000000-0000-0000-0000-000000009802', 'tester');
  select * into v_quote1 from app.quotations where id = v_quote1.id;
  perform app.submit_quotation(v_quote1.id, v_quote1.record_version, '00000000-0000-0000-0000-000000009802', 'tester');
  select * into v_send from app.send_quotation_for_acceptance(v_quote1.id, null, 'email', '00000000-0000-0000-0000-000000009802', 'tester');
  perform app.record_quotation_customer_decision(v_send.raw_token, 'accepted', 'Jane Doe Conv', null, null, null, null, null);

  select * into v_quote2 from app.create_quotation_draft(v_tenant1, v_opportunity2.id, 'IDR', now() + interval '14 days', v_contact2.id, null, null, '00000000-0000-0000-0000-000000009802', 'tester');
  perform app.add_quotation_line(v_quote2.id, v_quote2.record_version, 'service', 'Ocean freight lane 2', v_calc2_id, 1, 15000000, 0, 0, '00000000-0000-0000-0000-000000009802', 'tester');
  select * into v_quote2 from app.quotations where id = v_quote2.id;
  perform app.submit_quotation(v_quote2.id, v_quote2.record_version, '00000000-0000-0000-0000-000000009802', 'tester');
  select * into v_send from app.send_quotation_for_acceptance(v_quote2.id, null, 'email', '00000000-0000-0000-0000-000000009802', 'tester');
  perform app.record_quotation_customer_decision(v_send.raw_token, 'accepted', 'John Roe Conv', null, null, null, null, null);
end;
$$;

\echo '>> app.get_account_conversion_readiness (quotation 1): ready with zero duplicate candidates before any account exists'
do $$
declare
  v_quote1 app.quotations;
  v_ready boolean;
  v_reasons text[];
  v_candidates uuid[];
begin
  select * into v_quote1 from app.quotations where customer_snapshot ->> 'legal_name' = 'Duplicate Test Co' and customer_decision = 'accepted' order by quote_number asc limit 1;
  select ready, blocking_reasons, duplicate_candidate_ids into v_ready, v_reasons, v_candidates from app.get_account_conversion_readiness(v_quote1.id, '00000000-0000-0000-0000-000000009802');
  if not v_ready or array_length(v_candidates, 1) is not null then
    raise exception 'assertion failed: expected ready=true with zero duplicate candidates, got ready=% candidates=%', v_ready, v_candidates;
  end if;
end;
$$;

\echo '>> app.convert_quotation_to_account: authority-gated (an actor without COM:Approve is denied); creates a new account from the source prospect, backfills app.opportunities.account_ref, and reuses the prospect''s linked contact onto the new account'
do $$
declare
  v_quote1 app.quotations;
  v_account app.accounts;
  v_account_ref text;
  v_contact_id uuid;
  v_link_count integer;
begin
  select * into v_quote1 from app.quotations where customer_snapshot ->> 'legal_name' = 'Duplicate Test Co' and customer_decision = 'accepted' order by quote_number asc limit 1;

  begin
    perform app.convert_quotation_to_account(v_quote1.id, null, null, '00000000-0000-0000-0000-000000009803', 'outsider');
    raise exception 'assertion failed: expected insufficient_privilege -- the outsider lacks COM:Approve';
  exception
    when insufficient_privilege then
      null; -- expected
  end;

  select * into v_account from app.convert_quotation_to_account(v_quote1.id, null, null, '00000000-0000-0000-0000-000000009802', 'rep');
  if v_account.legal_name <> 'Duplicate Test Co' or v_account.tax_id <> '11.111.111.1-111.000' or v_account.customer_status <> 'active' or v_account.status <> 'active' then
    raise exception 'assertion failed: expected a real account snapshotted from the prospect, got legal_name=% tax_id=% customer_status=% status=%', v_account.legal_name, v_account.tax_id, v_account.customer_status, v_account.status;
  end if;

  select account_ref into v_account_ref from app.opportunities where id = v_quote1.opportunity_id;
  if v_account_ref <> v_account.id::text then
    raise exception 'assertion failed: expected app.opportunities.account_ref to be backfilled to the new account id, got %', v_account_ref;
  end if;

  select id into v_contact_id from app.contacts where email = 'jane1@dupconv.test';
  select count(*) into v_link_count from app.contact_links where contact_id = v_contact_id and related_type = 'account' and related_id = v_account.id;
  if v_link_count <> 1 then
    raise exception 'assertion failed: expected the prospect''s own linked contact to be reused onto the new account, found % link(s)', v_link_count;
  end if;
end;
$$;

\echo '>> app.convert_quotation_to_account is idempotent: calling it again for the same quotation returns the same account, creates no duplicate account or conversion row'
do $$
declare
  v_quote1 app.quotations;
  v_account1_id uuid;
  v_account2 app.accounts;
  v_account_count integer;
  v_conversion_count integer;
begin
  select * into v_quote1 from app.quotations where customer_snapshot ->> 'legal_name' = 'Duplicate Test Co' and customer_decision = 'accepted' order by quote_number asc limit 1;
  select account_id into v_account1_id from app.account_conversions where quotation_id = v_quote1.id;

  select * into v_account2 from app.convert_quotation_to_account(v_quote1.id, null, null, '00000000-0000-0000-0000-000000009802', 'rep');
  if v_account2.id <> v_account1_id then
    raise exception 'assertion failed: expected the idempotent retry to return the same account %, got %', v_account1_id, v_account2.id;
  end if;

  select count(*) into v_account_count from app.accounts where legal_name = 'Duplicate Test Co';
  select count(*) into v_conversion_count from app.account_conversions where quotation_id = v_quote1.id;
  if v_account_count <> 1 or v_conversion_count <> 1 then
    raise exception 'assertion failed: expected exactly 1 account and 1 conversion row after a repeated call, got accounts=% conversions=%', v_account_count, v_conversion_count;
  end if;
end;
$$;

\echo '>> app.get_account_conversion_readiness (quotation 2, same legal identity as quotation 1''s prospect): surfaces the existing account as a duplicate candidate'
do $$
declare
  v_quote2 app.quotations;
  v_existing_account_id uuid;
  v_ready boolean;
  v_reasons text[];
  v_candidates uuid[];
begin
  select * into v_quote2 from app.quotations where customer_snapshot ->> 'legal_name' = 'Duplicate Test Co' and customer_decision = 'accepted' order by quote_number asc offset 1 limit 1;
  select id into v_existing_account_id from app.accounts where legal_name = 'Duplicate Test Co';

  select ready, blocking_reasons, duplicate_candidate_ids into v_ready, v_reasons, v_candidates from app.get_account_conversion_readiness(v_quote2.id, '00000000-0000-0000-0000-000000009802');
  if not v_ready or not (v_existing_account_id = any (v_candidates)) then
    raise exception 'assertion failed: expected ready=true with the existing account % among duplicate candidates %, got ready=%', v_existing_account_id, v_candidates, v_ready;
  end if;
end;
$$;

\echo '>> app.convert_quotation_to_account (alternative flow): linking quotation 2 to the existing account creates no second account row'
do $$
declare
  v_quote2 app.quotations;
  v_existing_account_id uuid;
  v_account app.accounts;
  v_account_count integer;
  v_outcome text;
begin
  select * into v_quote2 from app.quotations where customer_snapshot ->> 'legal_name' = 'Duplicate Test Co' and customer_decision = 'accepted' order by quote_number asc offset 1 limit 1;
  select id into v_existing_account_id from app.accounts where legal_name = 'Duplicate Test Co';

  select * into v_account from app.convert_quotation_to_account(v_quote2.id, v_existing_account_id, null, '00000000-0000-0000-0000-000000009802', 'rep');
  if v_account.id <> v_existing_account_id then
    raise exception 'assertion failed: expected linking to return the existing account %, got %', v_existing_account_id, v_account.id;
  end if;

  select outcome into v_outcome from app.account_conversions where quotation_id = v_quote2.id;
  if v_outcome <> 'linked_existing' then
    raise exception 'assertion failed: expected outcome=linked_existing, got %', v_outcome;
  end if;

  select count(*) into v_account_count from app.accounts where legal_name = 'Duplicate Test Co';
  if v_account_count <> 1 then
    raise exception 'assertion failed: expected still exactly 1 account after linking a second quotation to it, found %', v_account_count;
  end if;
end;
$$;

\echo '>> parent/subsidiary: a brand-new account created with p_parent_account_id set carries the parent link'
do $$
declare
  v_tenant1 uuid;
  v_parent_account_id uuid;
  v_lead app.leads;
  v_prospect app.prospects;
  v_opportunity app.opportunities;
  v_request app.costing_requests;
  v_selection app.rate_selections;
  v_calc_id uuid;
  v_quote app.quotations;
  v_send record;
  v_child_account app.accounts;
  v_contact app.contacts;
begin
  v_tenant1 := (select id from app.tenants where slug = 'acmeconv');
  select id into v_parent_account_id from app.accounts where legal_name = 'Duplicate Test Co';

  perform app.capture_lead(v_tenant1, 'manual', null, 'DupCo Subsidiary', 'Subsidiary Contact', 'sub@dupconv.test', '0833',
    '00000000-0000-0000-0000-000000009802', (select id from app.org_units where tenant_id = v_tenant1 and code = 'ACMECONV-TEAM-A'), '00000000-0000-0000-0000-000000009802', 'tester');
  select * into v_lead from app.leads where email = 'sub@dupconv.test';
  perform app.qualify_lead(v_lead.id, v_lead.record_version, '00000000-0000-0000-0000-000000009802', 'tester');
  select * into v_lead from app.leads where email = 'sub@dupconv.test';
  perform app.convert_lead_to_prospect(v_lead.id, 'DupCo Subsidiary', 'DupCo Sub', '22.222.222.2-222.000',
    '{}'::jsonb, '00000000-0000-0000-0000-000000009802', 'tester');
  select * into v_prospect from app.prospects where lead_id = v_lead.id;

  select * into v_contact from app.create_contact(v_tenant1, 'Subsidiary Contact', 'Procurement Lead', 'sub@dupconv.test', '0833', '00000000-0000-0000-0000-000000009802', (select id from app.org_units where tenant_id = v_tenant1 and code = 'ACMECONV-TEAM-A'), '00000000-0000-0000-0000-000000009802', 'tester');
  perform app.link_contact_to_record(v_contact.id, 'prospect', v_prospect.id, 'primary', true, '00000000-0000-0000-0000-000000009802', 'tester');

  select * into v_opportunity from app.create_opportunity(
    v_tenant1, v_prospect.id, 'DupCo Subsidiary lane',
    jsonb_build_object('service_type', 'ocean_freight', 'cargo_description', 'General cargo', 'origin', 'Jakarta', 'destination', 'Surabaya', 'target_ready_date', '2026-08-01'),
    '00000000-0000-0000-0000-000000009802', (select id from app.org_units where tenant_id = v_tenant1 and code = 'ACMECONV-TEAM-A'), '00000000-0000-0000-0000-000000009802', 'tester'
  );
  select * into v_request from app.request_costing(v_opportunity.id, '[]'::jsonb, null, '00000000-0000-0000-0000-000000009802', 'tester');
  select * into v_selection from app.select_vendor_rate(v_request.id, (select id from app.vendor_rate_versions where tenant_id = v_tenant1 limit 1), false, null, null, null, '00000000-0000-0000-0000-000000009802', 'tester');
  perform app.calculate_margin(v_selection.id, 15000000, 'IDR', 0, '00000000-0000-0000-0000-000000009802', 'tester');
  select id into v_calc_id from app.margin_calculations where rate_selection_id = v_selection.id and is_current;

  select * into v_quote from app.create_quotation_draft(v_tenant1, v_opportunity.id, 'IDR', now() + interval '14 days', v_contact.id, null, null, '00000000-0000-0000-0000-000000009802', 'tester');
  perform app.add_quotation_line(v_quote.id, v_quote.record_version, 'service', 'Ocean freight subsidiary lane', v_calc_id, 1, 15000000, 0, 0, '00000000-0000-0000-0000-000000009802', 'tester');
  select * into v_quote from app.quotations where id = v_quote.id;
  perform app.submit_quotation(v_quote.id, v_quote.record_version, '00000000-0000-0000-0000-000000009802', 'tester');
  select * into v_send from app.send_quotation_for_acceptance(v_quote.id, null, 'email', '00000000-0000-0000-0000-000000009802', 'tester');
  perform app.record_quotation_customer_decision(v_send.raw_token, 'accepted', 'Subsidiary Contact', null, null, null, null, null);

  select * into v_child_account from app.convert_quotation_to_account(v_quote.id, null, v_parent_account_id, '00000000-0000-0000-0000-000000009802', 'rep');
  if v_child_account.parent_account_id <> v_parent_account_id then
    raise exception 'assertion failed: expected parent_account_id=%, got %', v_parent_account_id, v_child_account.parent_account_id;
  end if;
end;
$$;

\echo '>> app.accounts: tenant-wide visible (not record-scoped, ADR-0018''s own design) -- the sibling-team outsider CAN see every account in their own tenant, unlike every other Commercial entity''s own record-scoped directory'
do $$
declare
  v_tenant1 uuid;
  v_count integer;
begin
  v_tenant1 := (select id from app.tenants where slug = 'acmeconv');

  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000009803", "role": "authenticated"}';
  select count(*) into v_count from app.accounts where tenant_id = v_tenant1;
  if v_count <> 2 then
    raise exception 'assertion failed: expected the sibling-team outsider to see both accounts (tenant-wide visibility, not record-scoped), got %', v_count;
  end if;
  reset role;
end;
$$;

\echo '>> audit trail: convert_quotation_to_account recorded a real app.audit_logs event per successful conversion (created + linked_existing), tenant-scoped'
do $$
declare
  v_tenant1 uuid;
  v_count integer;
begin
  v_tenant1 := (select id from app.tenants where slug = 'acmeconv');

  select count(*) into v_count from app.audit_logs where resource_type = 'app.accounts' and action = 'convert_quotation_to_account' and tenant_id = v_tenant1;
  if v_count <> 3 then raise exception 'assertion failed: expected exactly 3 convert_quotation_to_account audit events (quote 1 create, quote 2 link, subsidiary quote create -- the idempotent retry left no new trace), found %', v_count; end if;
end;
$$;
