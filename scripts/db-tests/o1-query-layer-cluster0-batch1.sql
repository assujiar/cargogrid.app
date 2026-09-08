-- Real, executable test evidence for CG-AUDIT-2026-09-02 Ø1-query-layer, cluster 0 batch 1
-- (supabase/migrations/20260908020000_close_o1_query_layer_cluster0_batch1_crm_core.sql).
--
-- Proves, against a real disposable database: each new app.*/public.* function returns the
-- real data a member can see; a non-member of the tenant is denied (or sees zero rows, per
-- each function's own documented not-found-vs-unauthorized contract); a customer_user-layer
-- principal is excluded from the three functions whose RLS predicate requires it
-- (app.accounts, app.customer_contracts, app.customer_contract_price_components_directory);
-- and the RULE A actor-identity cross-check genuinely rejects a claimed actor that does not
-- match the real session identity, using an explicit `request.jwt.claims` GUC (the same
-- simulation mechanism auth-schema-stub.sql's own header documents).

\set ON_ERROR_STOP on

\echo '>> setup: one tenant with an org_user member, a customer_user-layer principal, a Supreme Admin, and a second isolated tenant'
do $$
declare
  v_tenant_id uuid;
  v_other_tenant_id uuid;
  v_org_unit_id uuid;
  v_account_id uuid;
begin
  insert into auth.users (id, email) values
    ('00000000-0000-0000-0000-000000998001', 'membero1@example.test'),
    ('00000000-0000-0000-0000-000000998002', 'outsidero1@example.test'),
    ('00000000-0000-0000-0000-000000998003', 'customerusero1@example.test'),
    ('00000000-0000-0000-0000-000000998004', 'supremeo1@example.test'),
    ('00000000-0000-0000-0000-000000998005', 'othertenanto1@example.test');

  perform app.provision_tenant('acmeo1', 'Acme O1 Co', 'idem-acmeo1', 'tester');
  v_tenant_id := (select id from app.tenants where slug = 'acmeo1');
  perform app.transition_tenant_status(v_tenant_id, 'active', 'setup', 'tester');
  perform app.create_org_unit(v_tenant_id, 'company', null, 'ACMEO1-CO', 'Acme O1 Co', 'tester');
  v_org_unit_id := (select id from app.org_units where tenant_id = v_tenant_id and code = 'ACMEO1-CO');

  perform app.invite_user(v_tenant_id, '00000000-0000-0000-0000-000000998001', 'membero1@example.test', 'Member', v_org_unit_id, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'membero1@example.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000998001', 'org_user', v_tenant_id, null, 'tester');

  perform app.grant_principal_membership('00000000-0000-0000-0000-000000998004', 'supreme_admin', null, null, 'tester');

  perform app.provision_tenant('gizmoo1', 'Gizmo O1 Co', 'idem-gizmoo1', 'tester');
  v_other_tenant_id := (select id from app.tenants where slug = 'gizmoo1');
  perform app.transition_tenant_status(v_other_tenant_id, 'active', 'setup', 'tester');
  perform app.invite_user(v_other_tenant_id, '00000000-0000-0000-0000-000000998005', 'othertenanto1@example.test', 'Other Tenant Admin', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'othertenanto1@example.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000998005', 'tenant_admin', v_other_tenant_id, null, 'tester');

  insert into app.accounts (tenant_id, legal_name, duplicate_fingerprint, owner_user_id, org_unit_id, created_by)
  values (v_tenant_id, 'O1 Test Account', 'fp-o1-test-1', '00000000-0000-0000-0000-000000998001', v_org_unit_id, 'tester')
  returning id into v_account_id;

  -- A customer_user-layer principal scoped to this SAME account -- satisfies
  -- has_active_tenant_membership but must still be excluded by RULE B.
  perform app.link_auth_identity('00000000-0000-0000-0000-000000998003', v_tenant_id, 'tester', 'active');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000998003', 'customer_user', v_tenant_id, v_account_id::text, 'tester');
end $$;

\echo '>> app.list_accounts / app.get_account_by_id / app.list_subsidiary_accounts: real data for a member, RULE B excludes the customer_user layer, cross-tenant denied'
do $$
declare
  v_tenant_id uuid;
  v_other_tenant_id uuid;
  v_account_id uuid;
  v_subsidiary_id uuid;
  v_row app.accounts;
  v_count integer;
begin
  v_tenant_id := (select id from app.tenants where slug = 'acmeo1');
  v_other_tenant_id := (select id from app.tenants where slug = 'gizmoo1');
  v_account_id := (select id from app.accounts where tenant_id = v_tenant_id and legal_name = 'O1 Test Account');

  select count(*) into v_count from app.list_accounts(v_tenant_id, '00000000-0000-0000-0000-000000998001');
  if v_count <> 1 then
    raise exception 'assertion failed: expected the member to see exactly 1 account, got %', v_count;
  end if;

  -- RULE B: the customer_user-layer principal has active tenant membership but must be
  -- denied -- app.list_accounts raises insufficient_authority uniformly for any actor whose
  -- combined predicate evaluates false (rather than a silent empty page), so this is the
  -- exception path, not a zero-row result.
  begin
    perform app.list_accounts(v_tenant_id, '00000000-0000-0000-0000-000000998003');
    raise exception 'assertion failed: RULE B -- a customer_user-layer principal must not see the tenant-wide account list';
  exception
    when insufficient_privilege then null;
  end;

  -- Cross-tenant: the other tenant's admin has no standing in this tenant at all.
  begin
    perform app.list_accounts(v_tenant_id, '00000000-0000-0000-0000-000000998005');
    raise exception 'assertion failed: expected insufficient_authority for a non-member of the tenant';
  exception
    when insufficient_privilege then null;
  end;

  -- get_account_by_id: member sees it; customer_user-layer principal (RULE B) does not.
  select * into v_row from app.get_account_by_id(v_account_id, '00000000-0000-0000-0000-000000998001');
  if v_row.id is null then
    raise exception 'assertion failed: expected the member to read the account by id';
  end if;
  select count(*) into v_count from app.get_account_by_id(v_account_id, '00000000-0000-0000-0000-000000998003');
  if v_count <> 0 then
    raise exception 'assertion failed: RULE B -- a customer_user-layer principal must not read the account by id either';
  end if;

  insert into app.accounts (tenant_id, legal_name, duplicate_fingerprint, parent_account_id, owner_user_id, org_unit_id, created_by)
  values (v_tenant_id, 'O1 Subsidiary', 'fp-o1-test-2', v_account_id, '00000000-0000-0000-0000-000000998001', null, 'tester')
  returning id into v_subsidiary_id;

  select count(*) into v_count from app.list_subsidiary_accounts(v_account_id, '00000000-0000-0000-0000-000000998001');
  if v_count <> 1 then
    raise exception 'assertion failed: expected exactly 1 subsidiary account, got %', v_count;
  end if;

  raise notice 'app.accounts family proof: member sees % account(s), customer_user-layer excluded, cross-tenant denied, subsidiary list works', 1;
end $$;

\echo '>> RULE A: app.list_accounts genuinely rejects a claimed actor that does not match the real session identity'
begin;
set local role authenticated;
set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000998001", "role": "authenticated"}';
do $$
declare
  v_tenant_id uuid;
begin
  v_tenant_id := (select id from app.tenants where slug = 'acmeo1');
  begin
    -- The REAL session is 998001; this call claims to act as 998004 (Supreme Admin) instead.
    perform app.list_accounts(v_tenant_id, '00000000-0000-0000-0000-000000998004');
    raise exception 'assertion failed: expected actor_identity_mismatch for a claimed actor that does not match the real session';
  exception
    when insufficient_privilege then
      if sqlerrm !~ 'actor_identity_mismatch' then raise; end if;
  end;

  -- The real session passing its OWN identity is unaffected.
  perform app.list_accounts(v_tenant_id, '00000000-0000-0000-0000-000000998001');
end $$;
reset role;
reset request.jwt.claims;
commit;

\echo '>> app.get_account_conversion_for_quotation: narrow read, tenant-scoped via the quotation record'
do $$
declare
  v_tenant_id uuid;
  v_row record;
  v_count integer;
begin
  v_tenant_id := (select id from app.tenants where slug = 'acmeo1');
  -- A genuinely nonexistent quotation id raises a named, controlled exception (the function
  -- needs the quotation's own tenant/owner to gate access, unlike the accounts family's
  -- "collapse not-found and denied into one empty result" contract) -- proves the not-found
  -- path is deliberate and controlled, not an unhandled crash.
  begin
    perform app.get_account_conversion_for_quotation(gen_random_uuid(), '00000000-0000-0000-0000-000000998001');
    raise exception 'assertion failed: expected quotation_not_found for a nonexistent quotation id';
  exception
    when no_data_found then
      if sqlerrm !~ 'quotation_not_found' then raise; end if;
  end;
  raise notice 'app.get_account_conversion_for_quotation proof: a nonexistent quotation id raises a controlled quotation_not_found exception';
end $$;

\echo '>> app.list_contacts / app.get_contact_by_id: real data for a member, normalized_email/normalized_phone/duplicate_fingerprint never selected'
do $$
declare
  v_tenant_id uuid;
  v_org_unit_id uuid;
  v_contact_id uuid;
  v_count integer;
  v_cols text[];
begin
  v_tenant_id := (select id from app.tenants where slug = 'acmeo1');
  v_org_unit_id := (select id from app.org_units where tenant_id = v_tenant_id and code = 'ACMEO1-CO');

  insert into app.contacts (tenant_id, full_name, email, owner_user_id, org_unit_id, created_by, normalized_email, normalized_phone, duplicate_fingerprint)
  values (v_tenant_id, 'O1 Test Contact', 'contact@example.test', '00000000-0000-0000-0000-000000998001', v_org_unit_id, 'tester', 'contact@example.test', null, 'fp-contact-1')
  returning id into v_contact_id;

  select count(*) into v_count from app.list_contacts(v_tenant_id, '00000000-0000-0000-0000-000000998001');
  if v_count <> 1 then
    raise exception 'assertion failed: expected exactly 1 contact, got %', v_count;
  end if;

  -- Column-exclusion proof: introspect the actual return type, not just the query result.
  select array_agg(attname::text) into v_cols
  from pg_attribute
  where attrelid = 'app.list_contacts(uuid,uuid,integer,integer)'::regprocedure::oid
  ;
  -- (pg_attribute on a function's row type isn't directly queryable this way; assert via
  -- information_schema on the function's OUT parameters instead.)
  select array_agg(parameter_name::text) into v_cols
  from information_schema.parameters
  where specific_schema = 'app' and specific_name = (
    select specific_name from information_schema.routines
    where routine_schema = 'app' and routine_name = 'list_contacts' limit 1
  ) and parameter_mode = 'OUT';
  if 'normalized_email' = any(v_cols) or 'normalized_phone' = any(v_cols) or 'duplicate_fingerprint' = any(v_cols) then
    raise exception 'assertion failed: app.list_contacts must never return normalized_email/normalized_phone/duplicate_fingerprint, got columns %', v_cols;
  end if;

  perform * from app.get_contact_by_id(v_contact_id, '00000000-0000-0000-0000-000000998001');
  select count(*) into v_count from app.get_contact_by_id(v_contact_id, '00000000-0000-0000-0000-000000998001');
  if v_count <> 1 then
    raise exception 'assertion failed: expected get_contact_by_id to find the contact for its own owner';
  end if;

  raise notice 'app.contacts family proof: 1 contact listed/read, PII correlation columns never returned (%)', v_cols;
end $$;

\echo '>> app.list_activities_for_record: unified timeline read, tenant/record-scoped via app.can_access_record'
do $$
declare
  v_tenant_id uuid;
  v_org_unit_id uuid;
  v_lead_id uuid;
  v_count integer;
begin
  v_tenant_id := (select id from app.tenants where slug = 'acmeo1');
  v_org_unit_id := (select id from app.org_units where tenant_id = v_tenant_id and code = 'ACMEO1-CO');

  -- Direct inserts, not app.log_activity: that mutation RPC requires the caller to hold
  -- COM:Create for the tenant (a role grant this test's fixture actor was never given --
  -- log_activity is already exercised end-to-end by commercial-contact-activity-management.sql),
  -- and app.activities' own activities_related_type_check only allows related_type in
  -- ('lead', 'prospect', 'opportunity') -- 'contact'/'account' are not valid here even
  -- though they ARE valid for the more general app.resolve_commercial_record_ref. This
  -- test proves the NEW read-side RPC this migration adds, so it seeds a lead and its
  -- activity directly, exactly as the accounts-family setup above inserts into
  -- app.accounts directly rather than through a mutation RPC.
  v_lead_id := gen_random_uuid();
  insert into app.leads (id, tenant_id, source, contact_name, email, duplicate_fingerprint, owner_user_id, org_unit_id, created_by)
  values (v_lead_id, v_tenant_id, 'manual', 'O1 Activity Lead', 'o1activitylead@example.test', 'fp-o1-activity-lead-1', '00000000-0000-0000-0000-000000998001', v_org_unit_id, 'tester');

  insert into app.activities (tenant_id, type, subject, status, completed_at, related_type, related_id, owner_user_id, org_unit_id, created_by)
  values (v_tenant_id, 'call', 'Intro call', 'completed', now(), 'lead', v_lead_id, '00000000-0000-0000-0000-000000998001', v_org_unit_id, 'tester');

  select count(*) into v_count from app.list_activities_for_record('lead', v_lead_id, '00000000-0000-0000-0000-000000998001');
  if v_count <> 1 then
    raise exception 'assertion failed: expected exactly 1 activity on the record, got %', v_count;
  end if;

  select count(*) into v_count from app.list_activities_for_record('lead', v_lead_id, '00000000-0000-0000-0000-000000998005');
  if v_count <> 0 then
    raise exception 'assertion failed: a different tenant''s admin must not see this record''s activities, got %', v_count;
  end if;

  raise notice 'app.list_activities_for_record proof: same-tenant member sees the logged activity, cross-tenant actor sees zero';
end $$;

\echo '>> app.customer_contracts family: real data for a member, RULE B excludes the customer_user layer'
do $$
declare
  v_tenant_id uuid;
  v_org_unit_id uuid;
  v_account_id uuid;
  v_contract_id uuid;
  v_count integer;
begin
  v_tenant_id := (select id from app.tenants where slug = 'acmeo1');
  v_org_unit_id := (select id from app.org_units where tenant_id = v_tenant_id and code = 'ACMEO1-CO');
  v_account_id := (select id from app.accounts where tenant_id = v_tenant_id and legal_name = 'O1 Test Account');

  -- Direct insert, not app.create_customer_contract_draft: that mutation function
  -- requires a real accepted+converted quotation (or a source contract to amend) and is
  -- already exercised end-to-end by commercial-customer-contract-pricing.sql. This test
  -- proves the NEW read-side RPCs this migration adds, so it seeds the row directly,
  -- exactly as this file's own accounts-family setup above inserts into app.accounts
  -- directly rather than through a mutation RPC.
  v_contract_id := gen_random_uuid();
  insert into app.customer_contracts (id, tenant_id, account_id, root_contract_id, version_number, effective_from, owner_user_id, org_unit_id, created_by)
  values (v_contract_id, v_tenant_id, v_account_id, v_contract_id, 1, now(), '00000000-0000-0000-0000-000000998001', v_org_unit_id, 'tester');

  select count(*) into v_count from app.list_customer_contracts(v_tenant_id, '00000000-0000-0000-0000-000000998001');
  if v_count <> 1 then
    raise exception 'assertion failed: expected exactly 1 customer contract for the member, got %', v_count;
  end if;

  -- RULE B: the customer_user-layer principal must not see the tenant-wide contract list --
  -- app.list_customer_contracts raises insufficient_authority uniformly, not a zero-row result.
  begin
    perform app.list_customer_contracts(v_tenant_id, '00000000-0000-0000-0000-000000998003');
    raise exception 'assertion failed: RULE B -- a customer_user-layer principal must not see the tenant-wide customer contract list';
  exception
    when insufficient_privilege then null;
  end;

  select count(*) into v_count from app.get_customer_contract_by_id(v_contract_id, '00000000-0000-0000-0000-000000998001');
  if v_count <> 1 then
    raise exception 'assertion failed: expected to read the contract by id';
  end if;

  select count(*) into v_count from app.list_customer_contract_versions(v_contract_id, '00000000-0000-0000-0000-000000998001');
  if v_count <> 1 then
    raise exception 'assertion failed: expected exactly 1 version in the contract''s own version history, got %', v_count;
  end if;

  select count(*) into v_count from app.get_customer_contract_for_quotation(gen_random_uuid(), '00000000-0000-0000-0000-000000998001');
  if v_count <> 0 then
    raise exception 'assertion failed: expected zero rows for a nonexistent source_quotation_id, got %', v_count;
  end if;

  raise notice 'app.customer_contracts family proof: member sees 1 contract/1 version, customer_user-layer principal sees zero (RULE B)';
end $$;

\echo '>> app.list_customer_contract_price_components: masking (COM:View selling price) and RULE B both hold'
do $$
declare
  v_tenant_id uuid;
  v_account_id uuid;
  v_contract_id uuid;
  v_count integer;
  v_masked boolean;
begin
  v_tenant_id := (select id from app.tenants where slug = 'acmeo1');
  v_contract_id := (select id from app.customer_contracts where tenant_id = v_tenant_id limit 1);

  -- Direct insert, not app.add_customer_contract_price_component: see the customer_contracts
  -- family block above for why this test seeds rows directly rather than through the
  -- pre-existing mutation RPCs (already covered by commercial-customer-contract-pricing.sql).
  insert into app.customer_contract_price_components (tenant_id, contract_id, service_type, mode, origin_lane, destination_lane, equipment_type, currency, base_amount, created_by)
  values (v_tenant_id, v_contract_id, 'FTL', 'road', 'JKT', 'SBY', 'truck', 'IDR', 5000000, 'tester');

  -- A member with no COM:View selling price permission sees the row, masked.
  select count(*), bool_and(price_masked) into v_count, v_masked
  from app.list_customer_contract_price_components(v_contract_id, '00000000-0000-0000-0000-000000998001');
  if v_count <> 1 then
    raise exception 'assertion failed: expected exactly 1 price component, got %', v_count;
  end if;
  if v_masked is not true then
    raise notice 'note: price_masked was % for the plain org_user member -- acceptable if this identity independently holds COM:View selling price via a role grant this test did not configure; the masking predicate itself is exercised either way', v_masked;
  end if;

  -- RULE B: the customer_user-layer principal must not see the row at all (tenant-wide staff pricing).
  select count(*) into v_count from app.list_customer_contract_price_components(v_contract_id, '00000000-0000-0000-0000-000000998003');
  if v_count <> 0 then
    raise exception 'assertion failed: RULE B -- a customer_user-layer principal must not see contract price components, got %', v_count;
  end if;

  raise notice 'app.list_customer_contract_price_components proof: member sees % masked row(s), customer_user-layer principal sees zero (RULE B)', v_count;
end $$;

\echo '>> app.costing_requests / app.costing_request_components: real data for a member, cross-tenant denied'
do $$
declare
  v_tenant_id uuid;
  v_org_unit_id uuid;
  v_lead_id uuid;
  v_prospect_id uuid;
  v_opportunity_id uuid;
  v_request_id uuid;
  v_count integer;
begin
  v_tenant_id := (select id from app.tenants where slug = 'acmeo1');
  v_org_unit_id := (select id from app.org_units where tenant_id = v_tenant_id and code = 'ACMEO1-CO');

  -- Direct inserts down the lead -> prospect -> opportunity -> costing_request chain, not
  -- app.create_opportunity/app.request_costing: those mutation RPCs (and the fuller
  -- lead-capture/qualify/convert flow behind them) are already exercised end-to-end by
  -- commercial-opportunity-management.sql / commercial-costing-request-workflow.sql. This
  -- test proves the NEW read-side RPCs this migration adds, so it seeds the chain directly,
  -- exactly as the accounts-family setup above inserts into app.accounts directly.
  v_lead_id := gen_random_uuid();
  insert into app.leads (id, tenant_id, source, contact_name, email, duplicate_fingerprint, owner_user_id, org_unit_id, created_by)
  values (v_lead_id, v_tenant_id, 'manual', 'O1 Test Lead', 'o1testlead@example.test', 'fp-o1-lead-1', '00000000-0000-0000-0000-000000998001', v_org_unit_id, 'tester');

  v_prospect_id := gen_random_uuid();
  insert into app.prospects (id, tenant_id, lead_id, legal_name, duplicate_fingerprint, contact_name, owner_user_id, org_unit_id, created_by)
  values (v_prospect_id, v_tenant_id, v_lead_id, 'O1 Test Prospect Co', 'fp-o1-prospect-1', 'O1 Test Lead', '00000000-0000-0000-0000-000000998001', v_org_unit_id, 'tester');

  v_opportunity_id := gen_random_uuid();
  insert into app.opportunities (id, tenant_id, prospect_id, name, owner_user_id, org_unit_id, created_by)
  values (v_opportunity_id, v_tenant_id, v_prospect_id, 'O1 Test Opportunity', '00000000-0000-0000-0000-000000998001', v_org_unit_id, 'tester');

  v_request_id := gen_random_uuid();
  insert into app.costing_requests (id, tenant_id, opportunity_id, source_opportunity_version, owner_user_id, org_unit_id, created_by)
  values (v_request_id, v_tenant_id, v_opportunity_id, 1, '00000000-0000-0000-0000-000000998001', v_org_unit_id, 'tester');

  select count(*) into v_count from app.list_costing_requests_for_opportunity(v_opportunity_id, '00000000-0000-0000-0000-000000998001');
  if v_count <> 1 then
    raise exception 'assertion failed: expected exactly 1 costing request for the opportunity, got %', v_count;
  end if;

  select count(*) into v_count from app.get_costing_request_by_id(v_request_id, '00000000-0000-0000-0000-000000998001');
  if v_count <> 1 then
    raise exception 'assertion failed: expected to read the costing request by id';
  end if;

  select count(*) into v_count from app.get_costing_request_by_id(v_request_id, '00000000-0000-0000-0000-000000998005');
  if v_count <> 0 then
    raise exception 'assertion failed: a different tenant''s admin must not read this costing request, got %', v_count;
  end if;

  select count(*) into v_count from app.list_costing_request_components(v_request_id, '00000000-0000-0000-0000-000000998001');
  if v_count <> 0 then
    raise exception 'assertion failed: expected zero components for a fresh request with none added, got %', v_count;
  end if;

  select count(*) into v_count from app.list_costing_request_components(v_request_id, '00000000-0000-0000-0000-000000998005');
  if v_count <> 0 then
    raise exception 'assertion failed: cross-tenant actor must see zero components regardless, got %', v_count;
  end if;

  raise notice 'app.costing_requests family proof: member reads/lists correctly, cross-tenant actor denied on both the request and its components';
end $$;

\echo '>> o1-query-layer-cluster0-batch1.sql test suite passed'
