-- Real, executable test evidence for COM-156 (Contract and Customer Pricing,
-- CG-S7-COM-015) -- run via `pnpm run db:test` against a real, disposable Postgres
-- database.

\set ON_ERROR_STOP on

\echo '>> setup: one tenant, a company/branch/two-team org hierarchy, a rep (COM:Create/Edit/Approve/View/View selling price/View cost, team A), a viewer (COM:View only, team B -- no ownership stake), a full lead->prospect->opportunity->costing->rate->margin->quotation chain, accepted and converted to an account'
do $$
declare
  v_tenant uuid;
  v_company uuid;
  v_branch uuid;
  v_team_a uuid;
  v_team_b uuid;
  v_rep_role uuid;
  v_rep_draft app.role_versions;
  v_viewer_role uuid;
  v_viewer_draft app.role_versions;
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
begin
  insert into auth.users (id, email) values
    ('00000000-0000-0000-0000-000000009901', 'tenantadmin@acmectr.test'),
    ('00000000-0000-0000-0000-000000009902', 'rep@acmectr.test'),
    ('00000000-0000-0000-0000-000000009903', 'viewer@acmectr.test');

  perform app.provision_tenant('acmectr', 'Acme Contract Co', 'idem-acmectr', 'tester');
  v_tenant := (select id from app.tenants where slug = 'acmectr');
  perform app.transition_tenant_status(v_tenant, 'active', 'setup', 'tester');

  perform app.create_org_unit(v_tenant, 'company', null, 'ACMECTR-CO', 'Acme Contract Co', 'tester');
  v_company := (select id from app.org_units where tenant_id = v_tenant and code = 'ACMECTR-CO');
  perform app.create_org_unit(v_tenant, 'branch', v_company, 'ACMECTR-BR', 'Jakarta Branch', 'tester');
  v_branch := (select id from app.org_units where tenant_id = v_tenant and code = 'ACMECTR-BR');
  perform app.create_org_unit(v_tenant, 'department', v_branch, 'ACMECTR-TEAM-A', 'Sales Team A', 'tester');
  v_team_a := (select id from app.org_units where tenant_id = v_tenant and code = 'ACMECTR-TEAM-A');
  perform app.create_org_unit(v_tenant, 'department', v_branch, 'ACMECTR-TEAM-B', 'Sales Team B', 'tester');
  v_team_b := (select id from app.org_units where tenant_id = v_tenant and code = 'ACMECTR-TEAM-B');

  perform app.invite_user(v_tenant, '00000000-0000-0000-0000-000000009901', 'tenantadmin@acmectr.test', 'Tenant Admin', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'tenantadmin@acmectr.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000009901', 'tenant_admin', v_tenant, null, 'tester');

  perform app.invite_user(v_tenant, '00000000-0000-0000-0000-000000009902', 'rep@acmectr.test', 'Rep', v_team_a, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'rep@acmectr.test'), 'active', 'onboarded', 'tester');
  perform app.invite_user(v_tenant, '00000000-0000-0000-0000-000000009903', 'viewer@acmectr.test', 'Team B Viewer', v_team_b, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'viewer@acmectr.test'), 'active', 'onboarded', 'tester');

  v_rep_role := (app.create_role(v_tenant, 'Contract Rep', 'contract and pricing', 'tester')).id;
  v_rep_draft := app.create_role_version(v_rep_role, 'tester');
  perform app.set_role_version_permissions(
    v_rep_draft.id,
    array(select id from app.permissions where resource_module_code = 'COM' and action in ('Create', 'Edit', 'Approve', 'View', 'View selling price', 'View cost')),
    'tester'
  );
  perform app.publish_role_version(v_rep_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant, (select id from app.role_versions where role_id = v_rep_role and status = 'published'),
    '00000000-0000-0000-0000-000000009902', '00000000-0000-0000-0000-000000009901', 'tester');

  v_viewer_role := (app.create_role(v_tenant, 'Team B Viewer', 'view only, no edit/approve/selling price', 'tester')).id;
  v_viewer_draft := app.create_role_version(v_viewer_role, 'tester');
  perform app.set_role_version_permissions(
    v_viewer_draft.id,
    array(select id from app.permissions where resource_module_code = 'COM' and action = 'View'),
    'tester'
  );
  perform app.publish_role_version(v_viewer_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant, (select id from app.role_versions where role_id = v_viewer_role and status = 'published'),
    '00000000-0000-0000-0000-000000009903', '00000000-0000-0000-0000-000000009901', 'tester');

  perform app.capture_lead(v_tenant, 'manual', null, 'Contract Test Co', 'Jane Ctr', 'jane@acmectr.test', '0811',
    '00000000-0000-0000-0000-000000009902', v_team_a, '00000000-0000-0000-0000-000000009902', 'tester');
  select * into v_lead from app.leads where email = 'jane@acmectr.test';
  perform app.qualify_lead(v_lead.id, v_lead.record_version, '00000000-0000-0000-0000-000000009902', 'tester');
  select * into v_lead from app.leads where email = 'jane@acmectr.test';
  perform app.convert_lead_to_prospect(v_lead.id, 'Contract Test Co', 'CtrCo', '22.222.222.2-222.000',
    jsonb_build_object('line1', 'Jl. Thamrin 1', 'city', 'Jakarta', 'country', 'ID'),
    '00000000-0000-0000-0000-000000009902', 'tester');
  select * into v_prospect from app.prospects where lead_id = v_lead.id;

  select * into v_contact from app.create_contact(v_tenant, 'Jane Ctr', 'Procurement Lead', 'jane@acmectr.test', '0811', '00000000-0000-0000-0000-000000009902', v_team_a, '00000000-0000-0000-0000-000000009902', 'tester');
  perform app.link_contact_to_record(v_contact.id, 'prospect', v_prospect.id, 'primary', true, '00000000-0000-0000-0000-000000009902', 'tester');

  select * into v_opportunity from app.create_opportunity(
    v_tenant, v_prospect.id, 'CtrCo ocean lane',
    jsonb_build_object('service_type', 'ocean_freight', 'cargo_description', 'General cargo', 'origin', 'Jakarta', 'destination', 'Surabaya', 'target_ready_date', '2026-08-01'),
    '00000000-0000-0000-0000-000000009902', v_team_a, '00000000-0000-0000-0000-000000009902', 'tester'
  );

  select * into v_request from app.request_costing(v_opportunity.id, '[]'::jsonb, null, '00000000-0000-0000-0000-000000009902', 'tester');

  select * into v_rate from app.create_rate_version(
    v_tenant, 'VENDOR-CTR-1', 'Contoso Ocean Line', 'ocean_freight', 'FCL', 'Jakarta', 'Surabaya', '20ft',
    null, null, null, null, 'IDR', 10000000, null, '[]'::jsonb, now(), null, null,
    '00000000-0000-0000-0000-000000009901', 'tester'
  );
  perform app.approve_rate_version(v_rate.id, v_rate.record_version, '00000000-0000-0000-0000-000000009901', 'tester');
  select * into v_selection from app.select_vendor_rate(v_request.id, v_rate.id, false, null, null, null, '00000000-0000-0000-0000-000000009902', 'tester');

  select * into v_rule from app.create_margin_rule_version(v_tenant, 20.00, 'half_up', '00000000-0000-0000-0000-000000009902', 'tester');
  perform app.publish_margin_rule_version(v_rule.id, v_rule.record_version, null, '00000000-0000-0000-0000-000000009902', 'tester');
  perform app.calculate_margin(v_selection.id, 15000000, 'IDR', 0, '00000000-0000-0000-0000-000000009902', 'tester');
  select id into v_calc_id from app.margin_calculations where rate_selection_id = v_selection.id and is_current;

  select * into v_quote from app.create_quotation_draft(v_tenant, v_opportunity.id, 'IDR', now() + interval '14 days', v_contact.id, null, null, '00000000-0000-0000-0000-000000009902', 'tester');
  perform app.add_quotation_line(v_quote.id, v_quote.record_version, 'service', 'Ocean freight', v_calc_id, 1, 15000000, 0, 0, '00000000-0000-0000-0000-000000009902', 'tester');
  select * into v_quote from app.quotations where id = v_quote.id;
  perform app.submit_quotation(v_quote.id, v_quote.record_version, '00000000-0000-0000-0000-000000009902', 'tester');
  select * into v_send from app.send_quotation_for_acceptance(v_quote.id, null, 'email', '00000000-0000-0000-0000-000000009902', 'tester');
  perform app.record_quotation_customer_decision(v_send.raw_token, 'accepted', 'Jane Ctr', null, null, null, null, null);

  select * into v_account from app.convert_quotation_to_account(v_quote.id, null, null, '00000000-0000-0000-0000-000000009902', 'rep');
end;
$$;

\echo '>> COM:View margin was newly seeded for the COM module (reused enum value, mirrors how COM-148 added COM:View cost) -- not yet granted to anyone in this tenant'
do $$
declare
  v_count integer;
  v_has boolean;
  v_tenant uuid;
begin
  select count(*) into v_count from app.permissions where resource_module_code = 'COM' and action = 'View margin';
  if v_count <> 1 then
    raise exception 'assertion failed: expected exactly 1 COM:View margin permission row, found %', v_count;
  end if;

  v_tenant := (select id from app.tenants where slug = 'acmectr');
  v_has := app.has_view_margin(v_tenant, '00000000-0000-0000-0000-000000009902');
  if v_has then
    raise exception 'assertion failed: expected the rep to NOT hold COM:View margin (never granted)';
  end if;
end;
$$;

\echo '>> app.create_customer_contract_draft: authority-gated (a viewer without COM:Edit is denied); creates version 1 as its own root, sourced from the accepted+converted quotation; a second attempt from the same quotation is rejected'
do $$
declare
  v_tenant uuid;
  v_quote_id uuid;
  v_account_id uuid;
  v_contract app.customer_contracts;
begin
  v_tenant := (select id from app.tenants where slug = 'acmectr');
  select id into v_quote_id from app.quotations where customer_snapshot ->> 'legal_name' = 'Contract Test Co';
  select account_id into v_account_id from app.account_conversions where quotation_id = v_quote_id;

  begin
    perform app.create_customer_contract_draft(v_quote_id, null, now(), now() + interval '30 days', null, '00000000-0000-0000-0000-000000009903', 'viewer');
    raise exception 'assertion failed: expected insufficient_privilege -- the viewer lacks COM:Edit';
  exception
    when insufficient_privilege then
      null; -- expected
  end;

  select * into v_contract from app.create_customer_contract_draft(v_quote_id, null, now(), now() + interval '30 days', null, '00000000-0000-0000-0000-000000009902', 'rep');
  if v_contract.status <> 'draft' or v_contract.version_number <> 1 or v_contract.root_contract_id <> v_contract.id or v_contract.account_id <> v_account_id or v_contract.source_quotation_id <> v_quote_id then
    raise exception 'assertion failed: expected a fresh draft root version 1 sourced from the quotation, got status=% version=% root=id?% account=% source=%',
      v_contract.status, v_contract.version_number, (v_contract.root_contract_id = v_contract.id), v_contract.account_id, v_contract.source_quotation_id;
  end if;

  begin
    perform app.create_customer_contract_draft(v_quote_id, null, now(), now() + interval '30 days', null, '00000000-0000-0000-0000-000000009902', 'rep');
    raise exception 'assertion failed: expected quotation_already_contracted on a second attempt from the same quotation';
  exception
    when unique_violation then
      null; -- expected
  end;
end;
$$;

\echo '>> app.publish_customer_contract: rejects a draft with zero price components'
do $$
declare
  v_contract_id uuid;
  v_expected_version integer;
begin
  select id, record_version into v_contract_id, v_expected_version from app.customer_contracts where version_number = 1;

  begin
    perform app.publish_customer_contract(v_contract_id, v_expected_version, '00000000-0000-0000-0000-000000009902', 'rep');
    raise exception 'assertion failed: expected no_price_components on an empty draft';
  exception
    when check_violation then
      null; -- expected
  end;
end;
$$;

\echo '>> app.add_customer_contract_price_component / app.remove_customer_contract_price_component: adds distinct service/lane components, rejects an identical duplicate, and removes one cleanly'
do $$
declare
  v_contract_id uuid;
  v_component1 app.customer_contract_price_components;
  v_component2 app.customer_contract_price_components;
  v_count integer;
begin
  select id into v_contract_id from app.customer_contracts where version_number = 1;

  select * into v_component1 from app.add_customer_contract_price_component(
    v_contract_id, 'ocean_freight', 'FCL', 'Jakarta', 'Surabaya', '20ft', 'IDR', 12000000, null, 5, '[]'::jsonb,
    '00000000-0000-0000-0000-000000009902', 'rep'
  );

  begin
    perform app.add_customer_contract_price_component(
      v_contract_id, 'ocean_freight', 'FCL', 'Jakarta', 'Surabaya', '20ft', 'IDR', 12500000, null, 5, '[]'::jsonb,
      '00000000-0000-0000-0000-000000009902', 'rep'
    );
    raise exception 'assertion failed: expected a unique_violation on an identical service/lane/mode/equipment identity';
  exception
    when unique_violation then
      null; -- expected
  end;

  select * into v_component2 from app.add_customer_contract_price_component(
    v_contract_id, 'ocean_freight', 'FCL', 'Jakarta', 'Medan', '20ft', 'IDR', 9000000, null, 0, '[]'::jsonb,
    '00000000-0000-0000-0000-000000009902', 'rep'
  );

  perform app.remove_customer_contract_price_component(v_component2.id, '00000000-0000-0000-0000-000000009902', 'rep');

  select count(*) into v_count from app.customer_contract_price_components where contract_id = v_contract_id;
  if v_count <> 1 then
    raise exception 'assertion failed: expected exactly 1 remaining price component after add/add-duplicate-rejected/add-second/remove-second, got %', v_count;
  end if;
end;
$$;

\echo '>> app.publish_customer_contract: authority-gated (a viewer without COM:Approve is denied); succeeds once at least one price component exists'
do $$
declare
  v_contract_id uuid;
  v_expected_version integer;
  v_contract app.customer_contracts;
begin
  select id, record_version into v_contract_id, v_expected_version from app.customer_contracts where version_number = 1;

  begin
    perform app.publish_customer_contract(v_contract_id, v_expected_version, '00000000-0000-0000-0000-000000009903', 'viewer');
    raise exception 'assertion failed: expected insufficient_privilege -- the viewer lacks COM:Approve';
  exception
    when insufficient_privilege then
      null; -- expected
  end;

  select * into v_contract from app.publish_customer_contract(v_contract_id, v_expected_version, '00000000-0000-0000-0000-000000009902', 'rep');
  if v_contract.status <> 'published' then
    raise exception 'assertion failed: expected status=published, got %', v_contract.status;
  end if;
end;
$$;

\echo '>> app.get_effective_customer_price: resolves the exact matching component deterministically; raises no_effective_price for an unmatched service_type; masks the money fields for a viewer without COM:View selling price'
do $$
declare
  v_tenant uuid;
  v_account_id uuid;
  v_currency text;
  v_base_amount numeric;
  v_masked boolean;
begin
  v_tenant := (select id from app.tenants where slug = 'acmectr');
  select account_id into v_account_id from app.account_conversions where quotation_id = (select id from app.quotations where customer_snapshot ->> 'legal_name' = 'Contract Test Co');

  select currency, base_amount, price_masked into v_currency, v_base_amount, v_masked
  from app.get_effective_customer_price(v_tenant, v_account_id, 'ocean_freight', 'FCL', 'Jakarta', 'Surabaya', '20ft', now() + interval '1 day', '00000000-0000-0000-0000-000000009902');
  if v_masked or v_currency <> 'IDR' or v_base_amount <> 12000000 then
    raise exception 'assertion failed: expected an unmasked match currency=IDR base_amount=12000000, got masked=% currency=% base_amount=%', v_masked, v_currency, v_base_amount;
  end if;

  begin
    perform app.get_effective_customer_price(v_tenant, v_account_id, 'air_freight', 'FCL', 'Jakarta', 'Surabaya', '20ft', now() + interval '1 day', '00000000-0000-0000-0000-000000009902');
    raise exception 'assertion failed: expected no_effective_price for an unmatched service_type';
  exception
    when no_data_found then
      null; -- expected
  end;

  select currency, base_amount, price_masked into v_currency, v_base_amount, v_masked
  from app.get_effective_customer_price(v_tenant, v_account_id, 'ocean_freight', 'FCL', 'Jakarta', 'Surabaya', '20ft', now() + interval '1 day', '00000000-0000-0000-0000-000000009903');
  if not v_masked or v_currency is not null or v_base_amount is not null then
    raise exception 'assertion failed: expected a masked result (price_masked=true, nulls) for the viewer (no COM:View selling price), got masked=% currency=% base_amount=%', v_masked, v_currency, v_base_amount;
  end if;
end;
$$;

\echo '>> app.create_customer_contract_draft (renewal/amendment flow): copies the source version''s own price components into a new draft under the same root, version_number incremented, mandatory reason enforced'
do $$
declare
  v_source_id uuid;
  v_renewal app.customer_contracts;
  v_root_id uuid;
  v_copied_count integer;
begin
  select id, root_contract_id into v_source_id, v_root_id from app.customer_contracts where version_number = 1;

  begin
    perform app.create_customer_contract_draft(null, v_source_id, now() + interval '15 days', now() + interval '60 days', null, '00000000-0000-0000-0000-000000009902', 'rep');
    raise exception 'assertion failed: expected reason_required on a renewal with no reason';
  exception
    when not_null_violation then
      null; -- expected
  end;

  select * into v_renewal from app.create_customer_contract_draft(null, v_source_id, now() + interval '15 days', now() + interval '60 days', 'Overlap test renewal', '00000000-0000-0000-0000-000000009902', 'rep');
  if v_renewal.version_number <> 2 or v_renewal.root_contract_id <> v_root_id or v_renewal.status <> 'draft' then
    raise exception 'assertion failed: expected version_number=2 under the same root in draft status, got version=% root=id?% status=%', v_renewal.version_number, (v_renewal.root_contract_id = v_root_id), v_renewal.status;
  end if;

  select count(*) into v_copied_count from app.customer_contract_price_components where contract_id = v_renewal.id;
  if v_copied_count <> 1 then
    raise exception 'assertion failed: expected the one remaining source component to be copied into the renewal draft, got %', v_copied_count;
  end if;
end;
$$;

\echo '>> app.publish_customer_contract: rejects a date-overlapping publish against an already-published sibling under the same root'
do $$
declare
  v_renewal_id uuid;
  v_expected_version integer;
begin
  select id, record_version into v_renewal_id, v_expected_version from app.customer_contracts where version_number = 2;

  begin
    perform app.publish_customer_contract(v_renewal_id, v_expected_version, '00000000-0000-0000-0000-000000009902', 'rep');
    raise exception 'assertion failed: expected overlapping_active_version -- version 1 [now, now+30d) overlaps version 2 [now+15d, now+60d)';
  exception
    when check_violation then
      null; -- expected
  end;
end;
$$;

\echo '>> a second, non-overlapping renewal (version 3, a different price point) publishes cleanly alongside the still-published version 1; the effective-price lookup disambiguates by as_of date'
do $$
declare
  v_source_id uuid;
  v_root_id uuid;
  v_v3 app.customer_contracts;
  v_v3_component app.customer_contract_price_components;
  v_tenant uuid;
  v_account_id uuid;
  v_base_amount numeric;
begin
  select id, root_contract_id into v_source_id, v_root_id from app.customer_contracts where version_number = 1;

  select * into v_v3 from app.create_customer_contract_draft(null, v_source_id, now() + interval '30 days', now() + interval '90 days', 'Second renewal, no overlap', '00000000-0000-0000-0000-000000009902', 'rep');
  if v_v3.version_number <> 3 or v_v3.root_contract_id <> v_root_id then
    raise exception 'assertion failed: expected version_number=3 under the same root, got version=% root=id?%', v_v3.version_number, (v_v3.root_contract_id = v_root_id);
  end if;

  select * into v_v3_component from app.customer_contract_price_components where contract_id = v_v3.id;
  perform app.remove_customer_contract_price_component(v_v3_component.id, '00000000-0000-0000-0000-000000009902', 'rep');
  perform app.add_customer_contract_price_component(
    v_v3.id, 'ocean_freight', 'FCL', 'Jakarta', 'Surabaya', '20ft', 'IDR', 13000000, null, 5, '[]'::jsonb,
    '00000000-0000-0000-0000-000000009902', 'rep'
  );

  perform app.publish_customer_contract(v_v3.id, v_v3.record_version, '00000000-0000-0000-0000-000000009902', 'rep');

  v_tenant := (select id from app.tenants where slug = 'acmectr');
  select account_id into v_account_id from app.account_conversions where quotation_id = (select id from app.quotations where customer_snapshot ->> 'legal_name' = 'Contract Test Co');

  select base_amount into v_base_amount from app.get_effective_customer_price(v_tenant, v_account_id, 'ocean_freight', 'FCL', 'Jakarta', 'Surabaya', '20ft', now() + interval '10 days', '00000000-0000-0000-0000-000000009902');
  if v_base_amount <> 12000000 then
    raise exception 'assertion failed: expected as_of=+10d to resolve version 1''s price 12000000, got %', v_base_amount;
  end if;

  select base_amount into v_base_amount from app.get_effective_customer_price(v_tenant, v_account_id, 'ocean_freight', 'FCL', 'Jakarta', 'Surabaya', '20ft', now() + interval '45 days', '00000000-0000-0000-0000-000000009902');
  if v_base_amount <> 13000000 then
    raise exception 'assertion failed: expected as_of=+45d to resolve version 3''s price 13000000, got %', v_base_amount;
  end if;
end;
$$;

\echo '>> app.retire_customer_contract: authority-gated, mandatory reason, only a published contract may be retired; a retired version drops out of the effective-price lookup'
do $$
declare
  v_v1_id uuid;
  v_expected_version integer;
  v_tenant uuid;
  v_account_id uuid;
begin
  select id, record_version into v_v1_id, v_expected_version from app.customer_contracts where version_number = 1;

  begin
    perform app.retire_customer_contract(v_v1_id, v_expected_version, null, '00000000-0000-0000-0000-000000009902', 'rep');
    raise exception 'assertion failed: expected reason_required on a retire with no reason';
  exception
    when not_null_violation then
      null; -- expected
  end;

  begin
    perform app.retire_customer_contract(v_v1_id, v_expected_version, 'Superseded by renewal', '00000000-0000-0000-0000-000000009903', 'viewer');
    raise exception 'assertion failed: expected insufficient_privilege -- the viewer lacks COM:Approve';
  exception
    when insufficient_privilege then
      null; -- expected
  end;

  perform app.retire_customer_contract(v_v1_id, v_expected_version, 'Superseded by renewal', '00000000-0000-0000-0000-000000009902', 'rep');

  v_tenant := (select id from app.tenants where slug = 'acmectr');
  select account_id into v_account_id from app.account_conversions where quotation_id = (select id from app.quotations where customer_snapshot ->> 'legal_name' = 'Contract Test Co');

  begin
    perform app.get_effective_customer_price(v_tenant, v_account_id, 'ocean_freight', 'FCL', 'Jakarta', 'Surabaya', '20ft', now() + interval '10 days', '00000000-0000-0000-0000-000000009902');
    raise exception 'assertion failed: expected no_effective_price at as_of=+10d now that version 1 is retired and version 3 does not cover that date';
  exception
    when no_data_found then
      null; -- expected
  end;
end;
$$;

\echo '>> app.customer_contracts / app.customer_contract_price_components_directory: tenant-wide visibility -- the sibling-team viewer (no ownership stake) sees every contract and its masked price components'
do $$
declare
  v_count integer;
begin
  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000009903", "role": "authenticated"}';

  select count(*) into v_count from app.customer_contracts where tenant_id = (select id from app.tenants where slug = 'acmectr');
  if v_count <> 3 then
    raise exception 'assertion failed: expected the viewer to see all 3 contract versions tenant-wide, got %', v_count;
  end if;

  select count(*) into v_count from app.customer_contract_price_components_directory where tenant_id = (select id from app.tenants where slug = 'acmectr');
  if v_count < 2 then
    raise exception 'assertion failed: expected the viewer to see the masked price components tenant-wide, got %', v_count;
  end if;

  reset role;
end;
$$;

\echo '>> schema-privilege defense in depth: authenticated has no direct column access to the selling-price columns on app.customer_contract_price_components itself'
do $$
declare
  v_component_id uuid;
begin
  select id into v_component_id from app.customer_contract_price_components limit 1;

  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000009902", "role": "authenticated"}';
  begin
    perform base_amount from app.customer_contract_price_components where id = v_component_id;
    raise exception 'assertion failed: expected a real Postgres permission-denied error selecting base_amount directly from app.customer_contract_price_components';
  exception
    when insufficient_privilege then
      null; -- expected
  end;
  reset role;
end;
$$;

\echo '>> full tenant-scoped audit trail: 3 successful create_customer_contract_draft, 2 successful publish_customer_contract (the overlapping attempt left no trace), 1 successful retire_customer_contract'
do $$
declare
  v_tenant uuid;
  v_create_count integer;
  v_publish_count integer;
  v_retire_count integer;
begin
  v_tenant := (select id from app.tenants where slug = 'acmectr');

  select count(*) into v_create_count from app.audit_logs where tenant_id = v_tenant and action = 'create_customer_contract_draft' and result = 'success';
  select count(*) into v_publish_count from app.audit_logs where tenant_id = v_tenant and action = 'publish_customer_contract' and result = 'success';
  select count(*) into v_retire_count from app.audit_logs where tenant_id = v_tenant and action = 'retire_customer_contract' and result = 'success';

  if v_create_count <> 3 or v_publish_count <> 2 or v_retire_count <> 1 then
    raise exception 'assertion failed: expected create=3 publish=2 retire=1, got create=% publish=% retire=%', v_create_count, v_publish_count, v_retire_count;
  end if;
end;
$$;
