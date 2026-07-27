-- Real, executable test evidence for COM-161 (No-Reentry Enforcement, CG-S7-COM-020) --
-- run via `pnpm run db:test` against a real, disposable Postgres database.

\set ON_ERROR_STOP on

\echo '>> setup: one tenant, a company/team org hierarchy, a rep (COM:Create/Edit/Approve/View/View selling price/View cost) and an outsider with no active tenant membership, plus one full lead->prospect->opportunity->quotation->acceptance->account pipeline yielding a real app.accounts row (Existing Customer Co)'
do $$
declare
  v_tenant1 uuid;
  v_company uuid;
  v_team uuid;
  v_rep_role uuid;
  v_rep_draft app.role_versions;
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
    ('00000000-0000-0000-0000-000000009920', 'tenantadmin@acmereentry.test'),
    ('00000000-0000-0000-0000-000000009921', 'rep@acmereentry.test');
  -- 9922 is deliberately never granted a tenant membership -- the "outsider" identity.

  perform app.provision_tenant('acmereentry', 'Acme Reentry Co', 'idem-acmereentry', 'tester');
  v_tenant1 := (select id from app.tenants where slug = 'acmereentry');
  perform app.transition_tenant_status(v_tenant1, 'active', 'setup', 'tester');

  perform app.create_org_unit(v_tenant1, 'company', null, 'ACMEREENTRY-CO', 'Acme Reentry Co', 'tester');
  v_company := (select id from app.org_units where tenant_id = v_tenant1 and code = 'ACMEREENTRY-CO');
  perform app.create_org_unit(v_tenant1, 'department', v_company, 'ACMEREENTRY-TEAM', 'Sales Team', 'tester');
  v_team := (select id from app.org_units where tenant_id = v_tenant1 and code = 'ACMEREENTRY-TEAM');

  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000009920', 'tenantadmin@acmereentry.test', 'Tenant Admin', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'tenantadmin@acmereentry.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000009920', 'tenant_admin', v_tenant1, null, 'tester');

  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000009921', 'rep@acmereentry.test', 'Rep', v_team, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'rep@acmereentry.test'), 'active', 'onboarded', 'tester');

  v_rep_role := (app.create_role(v_tenant1, 'Reentry Rep', 'no-reentry test rep', 'tester')).id;
  v_rep_draft := app.create_role_version(v_rep_role, 'tester');
  perform app.set_role_version_permissions(
    v_rep_draft.id,
    array(select id from app.permissions where resource_module_code = 'COM' and action in ('Create', 'Edit', 'Approve', 'View', 'View selling price', 'View cost')),
    'tester'
  );
  perform app.publish_role_version(v_rep_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_rep_role and status = 'published'),
    '00000000-0000-0000-0000-000000009921', '00000000-0000-0000-0000-000000009920', 'tester');

  perform app.capture_lead(v_tenant1, 'manual', null, 'Existing Customer Co', 'Original Contact', 'orig@reentry.test', '0811',
    '00000000-0000-0000-0000-000000009921', v_team, '00000000-0000-0000-0000-000000009921', 'tester');
  select * into v_lead from app.leads where email = 'orig@reentry.test';
  perform app.qualify_lead(v_lead.id, v_lead.record_version, '00000000-0000-0000-0000-000000009921', 'tester');
  select * into v_lead from app.leads where email = 'orig@reentry.test';
  perform app.convert_lead_to_prospect(v_lead.id, 'Existing Customer Co', 'ECC', '33.333.333.3-333.000',
    jsonb_build_object('line1', 'Jl. Thamrin 1', 'city', 'Jakarta', 'country', 'ID'),
    '00000000-0000-0000-0000-000000009921', 'tester');
  select * into v_prospect from app.prospects where lead_id = v_lead.id;

  select * into v_contact from app.create_contact(v_tenant1, 'Original Contact', 'Procurement Lead', 'orig@reentry.test', '0811', '00000000-0000-0000-0000-000000009921', v_team, '00000000-0000-0000-0000-000000009921', 'tester');
  perform app.link_contact_to_record(v_contact.id, 'prospect', v_prospect.id, 'primary', true, '00000000-0000-0000-0000-000000009921', 'tester');

  select * into v_opportunity from app.create_opportunity(
    v_tenant1, v_prospect.id, 'ECC first lane',
    jsonb_build_object('service_type', 'ocean_freight', 'cargo_description', 'General cargo', 'origin', 'Jakarta', 'destination', 'Surabaya', 'target_ready_date', '2026-08-01'),
    '00000000-0000-0000-0000-000000009921', v_team, '00000000-0000-0000-0000-000000009921', 'tester'
  );
  select * into v_request from app.request_costing(v_opportunity.id, '[]'::jsonb, null, '00000000-0000-0000-0000-000000009921', 'tester');
  select * into v_rate from app.create_rate_version(
    v_tenant1, 'VENDOR-REENTRY-1', 'Contoso Ocean Line', 'ocean_freight', 'FCL', 'Jakarta', 'Surabaya', '20ft',
    null, null, null, null, 'IDR', 10000000, null, '[]'::jsonb, now(), null, null,
    '00000000-0000-0000-0000-000000009920', 'tester'
  );
  perform app.approve_rate_version(v_rate.id, v_rate.record_version, '00000000-0000-0000-0000-000000009920', 'tester');
  select * into v_selection from app.select_vendor_rate(v_request.id, v_rate.id, false, null, null, null, '00000000-0000-0000-0000-000000009921', 'tester');

  select * into v_rule from app.create_margin_rule_version(v_tenant1, 20.00, 'half_up', '00000000-0000-0000-0000-000000009921', 'tester');
  perform app.publish_margin_rule_version(v_rule.id, v_rule.record_version, null, '00000000-0000-0000-0000-000000009921', 'tester');
  perform app.calculate_margin(v_selection.id, 15000000, 'IDR', 0, '00000000-0000-0000-0000-000000009921', 'tester');
  select id into v_calc_id from app.margin_calculations where rate_selection_id = v_selection.id and is_current;

  select * into v_quote from app.create_quotation_draft(v_tenant1, v_opportunity.id, 'IDR', now() + interval '14 days', v_contact.id, null, null, '00000000-0000-0000-0000-000000009921', 'tester');
  perform app.add_quotation_line(v_quote.id, v_quote.record_version, 'service', 'Ocean freight ECC lane', v_calc_id, 1, 15000000, 0, 0, '00000000-0000-0000-0000-000000009921', 'tester');
  select * into v_quote from app.quotations where id = v_quote.id;
  perform app.submit_quotation(v_quote.id, v_quote.record_version, '00000000-0000-0000-0000-000000009921', 'tester');
  select * into v_send from app.send_quotation_for_acceptance(v_quote.id, null, 'email', '00000000-0000-0000-0000-000000009921', 'tester');
  perform app.record_quotation_customer_decision(v_send.raw_token, 'accepted', 'Original Contact', null, null, null, null, null);

  select * into v_account from app.convert_quotation_to_account(v_quote.id, null, null, '00000000-0000-0000-0000-000000009921', 'rep');
  if v_account.legal_name <> 'Existing Customer Co' then
    raise exception 'setup assertion failed: expected the seeded account to exist, got %', v_account.legal_name;
  end if;
end;
$$;

\echo '>> gap 1 fixed: app.opportunities.account_id is now a real FK-backed canonical reference, set to the same value as the legacy account_ref text placeholder -- app.commercial_opportunity_account_ref_drift is structurally empty'
do $$
declare
  v_tenant1 uuid;
  v_opportunity app.opportunities;
  v_account_id uuid;
  v_drift_count integer;
begin
  v_tenant1 := (select id from app.tenants where slug = 'acmereentry');
  select id into v_account_id from app.accounts where tenant_id = v_tenant1 and legal_name = 'Existing Customer Co';
  select * into v_opportunity from app.opportunities where tenant_id = v_tenant1 and name = 'ECC first lane';

  if v_opportunity.account_id <> v_account_id or v_opportunity.account_ref <> v_account_id::text then
    raise exception 'assertion failed: expected both account_id (%) and account_ref (%) to equal the converted account %', v_opportunity.account_id, v_opportunity.account_ref, v_account_id;
  end if;

  select count(*) into v_drift_count from app.commercial_opportunity_account_ref_drift where tenant_id = v_tenant1;
  if v_drift_count <> 0 then
    raise exception 'assertion failed: expected zero drift rows for a checkpoint-native conversion, found %', v_drift_count;
  end if;
end;
$$;

\echo '>> gap 1 reconciliation: a brownfield-style row where account_ref and account_id disagree is surfaced by app.commercial_opportunity_account_ref_drift, never silently repaired'
do $$
declare
  v_tenant1 uuid;
  v_opportunity_id uuid;
  v_real_account_id uuid;
  v_drift_count integer;
begin
  v_tenant1 := (select id from app.tenants where slug = 'acmereentry');
  select id into v_opportunity_id from app.opportunities where tenant_id = v_tenant1 and name = 'ECC first lane';
  select account_id into v_real_account_id from app.opportunities where id = v_opportunity_id;

  -- Simulates a legacy row that predates this checkpoint's account_id backfill --
  -- direct table access, not a mutation function, deliberately: no application code path
  -- is supposed to ever desynchronize these two columns.
  update app.opportunities set account_id = null where id = v_opportunity_id;

  select count(*) into v_drift_count from app.commercial_opportunity_account_ref_drift where opportunity_id = v_opportunity_id;
  if v_drift_count <> 1 then
    raise exception 'assertion failed: expected the desynchronized row to appear exactly once in the drift view, found %', v_drift_count;
  end if;

  -- restore for later assertions in this file
  update app.opportunities set account_id = v_real_account_id where id = v_opportunity_id;
end;
$$;

\echo '>> gap 2 (Lead stage): app.find_existing_accounts_for_lead surfaces the existing account for a new Lead sharing its company_name, is empty for a genuinely new company, never blocks app.capture_lead either way, and fails closed for an actor with no active tenant membership'
do $$
declare
  v_tenant1 uuid;
  v_team uuid;
  v_matching_lead app.leads;
  v_new_lead app.leads;
  v_existing_account_id uuid;
  v_match_count integer;
  v_nomatch_count integer;
begin
  v_tenant1 := (select id from app.tenants where slug = 'acmereentry');
  v_team := (select id from app.org_units where tenant_id = v_tenant1 and code = 'ACMEREENTRY-TEAM');
  select id into v_existing_account_id from app.accounts where tenant_id = v_tenant1 and legal_name = 'Existing Customer Co';

  perform app.capture_lead(v_tenant1, 'manual', null, 'Existing Customer Co', 'A New Rep Recontacted This', 'again@reentry.test', '0899',
    '00000000-0000-0000-0000-000000009921', v_team, '00000000-0000-0000-0000-000000009921', 'tester');
  select * into v_matching_lead from app.leads where email = 'again@reentry.test';
  if v_matching_lead.id is null then
    raise exception 'assertion failed: app.capture_lead must never be blocked by a duplicate-account candidate -- capture always succeeds';
  end if;

  perform app.capture_lead(v_tenant1, 'manual', null, 'Genuinely New Prospect Co', 'A Different Contact', 'new@reentry.test', '0877',
    '00000000-0000-0000-0000-000000009921', v_team, '00000000-0000-0000-0000-000000009921', 'tester');
  select * into v_new_lead from app.leads where email = 'new@reentry.test';

  select count(*) into v_match_count from app.find_existing_accounts_for_lead(v_tenant1, '00000000-0000-0000-0000-000000009921', v_matching_lead.id) t where t.id = v_existing_account_id;
  if v_match_count <> 1 then
    raise exception 'assertion failed: expected the existing account to be surfaced exactly once for a lead sharing its company_name, found %', v_match_count;
  end if;

  select count(*) into v_nomatch_count from app.find_existing_accounts_for_lead(v_tenant1, '00000000-0000-0000-0000-000000009921', v_new_lead.id);
  if v_nomatch_count <> 0 then
    raise exception 'assertion failed: expected zero candidates for a genuinely new company name, found %', v_nomatch_count;
  end if;

  begin
    perform app.find_existing_accounts_for_lead(v_tenant1, '00000000-0000-0000-0000-000000009922', v_matching_lead.id);
    raise exception 'assertion failed: expected insufficient_privilege for an identity with no active tenant membership';
  exception
    when insufficient_privilege then
      null; -- expected: fails closed, cannot be used to probe another identity''s tenant
  end;
end;
$$;

\echo '>> gap 2 (Prospect stage): app.find_existing_accounts_for_prospect reuses app.find_duplicate_accounts'' own legal_name+tax_id fingerprint match, surfacing the existing account long before Opportunity/costing/quotation work would otherwise duplicate it'
do $$
declare
  v_tenant1 uuid;
  v_team uuid;
  v_lead app.leads;
  v_matching_prospect app.prospects;
  v_nomatch_prospect app.prospects;
  v_existing_account_id uuid;
  v_match_count integer;
  v_nomatch_count integer;
begin
  v_tenant1 := (select id from app.tenants where slug = 'acmereentry');
  v_team := (select id from app.org_units where tenant_id = v_tenant1 and code = 'ACMEREENTRY-TEAM');
  select id into v_existing_account_id from app.accounts where tenant_id = v_tenant1 and legal_name = 'Existing Customer Co';

  perform app.capture_lead(v_tenant1, 'manual', null, 'Existing Customer Co (re-typed)', 'Yet Another Rep', 'thrice@reentry.test', '0866',
    '00000000-0000-0000-0000-000000009921', v_team, '00000000-0000-0000-0000-000000009921', 'tester');
  select * into v_lead from app.leads where email = 'thrice@reentry.test';
  perform app.qualify_lead(v_lead.id, v_lead.record_version, '00000000-0000-0000-0000-000000009921', 'tester');
  select * into v_lead from app.leads where email = 'thrice@reentry.test';
  perform app.convert_lead_to_prospect(v_lead.id, 'Existing Customer Co', 'ECC', '33.333.333.3-333.000', '{}'::jsonb,
    '00000000-0000-0000-0000-000000009921', 'tester');
  select * into v_matching_prospect from app.prospects where lead_id = v_lead.id;

  perform app.capture_lead(v_tenant1, 'manual', null, 'Totally Unrelated Co', 'Someone Else', 'unrelated@reentry.test', '0855',
    '00000000-0000-0000-0000-000000009921', v_team, '00000000-0000-0000-0000-000000009921', 'tester');
  select * into v_lead from app.leads where email = 'unrelated@reentry.test';
  perform app.qualify_lead(v_lead.id, v_lead.record_version, '00000000-0000-0000-0000-000000009921', 'tester');
  select * into v_lead from app.leads where email = 'unrelated@reentry.test';
  perform app.convert_lead_to_prospect(v_lead.id, 'Totally Unrelated Co', 'TUC', '99.999.999.9-999.000', '{}'::jsonb,
    '00000000-0000-0000-0000-000000009921', 'tester');
  select * into v_nomatch_prospect from app.prospects where lead_id = v_lead.id;

  select count(*) into v_match_count from app.find_existing_accounts_for_prospect(v_tenant1, '00000000-0000-0000-0000-000000009921', v_matching_prospect.id) t where t.id = v_existing_account_id;
  if v_match_count <> 1 then
    raise exception 'assertion failed: expected the existing account to be surfaced exactly once for a prospect sharing its legal_name+tax_id fingerprint, found %', v_match_count;
  end if;

  select count(*) into v_nomatch_count from app.find_existing_accounts_for_prospect(v_tenant1, '00000000-0000-0000-0000-000000009921', v_nomatch_prospect.id);
  if v_nomatch_count <> 0 then
    raise exception 'assertion failed: expected zero candidates for a genuinely unrelated legal identity, found %', v_nomatch_count;
  end if;
end;
$$;

\echo '>> cross-tenant isolation: find_existing_accounts_for_lead/for_prospect can never surface another tenant''s accounts, and reject a lead/prospect id from a foreign tenant'
do $$
declare
  v_tenant1 uuid;
  v_tenant2 uuid;
  v_team2 uuid;
  v_lead2 app.leads;
  v_role2 uuid;
  v_role2_draft app.role_versions;
begin
  v_tenant1 := (select id from app.tenants where slug = 'acmereentry');

  insert into auth.users (id, email) values ('00000000-0000-0000-0000-000000009923', 'admin2@acmereentry2.test');
  perform app.provision_tenant('acmereentry2', 'Acme Reentry Two', 'idem-acmereentry2', 'tester');
  v_tenant2 := (select id from app.tenants where slug = 'acmereentry2');
  perform app.transition_tenant_status(v_tenant2, 'active', 'setup', 'tester');
  perform app.create_org_unit(v_tenant2, 'company', null, 'ACMEREENTRY2-CO', 'Acme Reentry Two', 'tester');
  v_team2 := (select id from app.org_units where tenant_id = v_tenant2 and code = 'ACMEREENTRY2-CO');
  perform app.invite_user(v_tenant2, '00000000-0000-0000-0000-000000009923', 'admin2@acmereentry2.test', 'Tenant 2 Admin', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'admin2@acmereentry2.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000009923', 'tenant_admin', v_tenant2, null, 'tester');

  v_role2 := (app.create_role(v_tenant2, 'Reentry Rep 2', 'no-reentry cross-tenant test rep', 'tester')).id;
  v_role2_draft := app.create_role_version(v_role2, 'tester');
  perform app.set_role_version_permissions(
    v_role2_draft.id,
    array(select id from app.permissions where resource_module_code = 'COM' and action = 'Create'),
    'tester'
  );
  perform app.publish_role_version(v_role2_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant2, (select id from app.role_versions where role_id = v_role2 and status = 'published'),
    '00000000-0000-0000-0000-000000009923', '00000000-0000-0000-0000-000000009923', 'tester');

  perform app.capture_lead(v_tenant2, 'manual', null, 'Existing Customer Co', 'Cross Tenant Contact', 'crosstenant@reentry.test', '0844',
    '00000000-0000-0000-0000-000000009923', v_team2, '00000000-0000-0000-0000-000000009923', 'tester');
  select * into v_lead2 from app.leads where email = 'crosstenant@reentry.test';

  -- Same company_name as tenant 1's real account, called from tenant 2's own admin
  -- against tenant 2's own lead: the duplicate-fingerprint tenant scoping (inherited from
  -- app.find_duplicate_accounts/app.normalize_prospect_identifier) must never leak tenant
  -- 1's account across the boundary.
  if exists (select 1 from app.find_existing_accounts_for_lead(v_tenant2, '00000000-0000-0000-0000-000000009923', v_lead2.id)) then
    raise exception 'assertion failed: expected zero cross-tenant candidates -- tenant 2 has no account of its own named Existing Customer Co';
  end if;

  -- A tenant-2 admin passing a tenant-1 lead id, scoped to p_tenant_id=tenant1, but
  -- authenticated as a tenant-2-only identity: must fail closed on membership, not leak.
  begin
    perform app.find_existing_accounts_for_lead(v_tenant1, '00000000-0000-0000-0000-000000009923', (select id from app.leads where tenant_id = v_tenant1 limit 1));
    raise exception 'assertion failed: expected insufficient_privilege for a tenant-2-only identity querying tenant 1';
  exception
    when insufficient_privilege then
      null; -- expected
  end;
end;
$$;

\echo '>> schema-privilege defense in depth: anon holds no EXECUTE on the new functions (ERR-2026-004 regression guard); authenticated does'
do $$
declare
  v_anon_has boolean;
  v_authenticated_has boolean;
begin
  select bool_or(has_function_privilege('anon', p.oid, 'EXECUTE'))
    into v_anon_has
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'app' and p.proname in ('find_existing_accounts_for_lead', 'find_existing_accounts_for_prospect');
  if coalesce(v_anon_has, false) then
    raise exception 'assertion failed: expected anon to hold no EXECUTE on either new function';
  end if;

  select bool_and(has_function_privilege('authenticated', p.oid, 'EXECUTE'))
    into v_authenticated_has
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'app' and p.proname in ('find_existing_accounts_for_lead', 'find_existing_accounts_for_prospect');
  if not coalesce(v_authenticated_has, false) then
    raise exception 'assertion failed: expected authenticated to hold EXECUTE on both new functions';
  end if;
end;
$$;
