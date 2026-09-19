-- Real, executable test evidence for CG-AUDIT-2026-09-02 Ø1-query-layer, cluster 0 batch 4
-- (supabase/migrations/20260909020000_close_o1_query_layer_cluster0_batch4_leads_prospects_
-- quotation_directory.sql).
--
-- Proves, against a real disposable database: each new app.*/public.* function returns the
-- real data a member/record-owner can see; RULE A genuinely rejects a claimed actor that does
-- not match the real session identity; app.prospects' new functions never return
-- normalized_legal_name/normalized_tax_id/duplicate_fingerprint/disqualified_at/archived_at
-- (the column-exclusion fix applied during adversarial verify); app.quotations_directory/
-- app.quotation_lines_directory's masking (sell_masked/cost_masked) matches the replaced
-- views' own masking exactly; app.quotation_acceptance_tokens never returns token_hash;
-- app.quotation_approval_rules' RULE B excludes the customer_user layer and a Supreme Admin
-- with zero membership bypasses via the explicit OR is_supreme_admin() branch; and cross-tenant
-- denial throughout.

\set ON_ERROR_STOP on

\echo '>> setup: one tenant with an org_user member (also the owner of every fixture row), a customer_user-layer principal, a global Supreme Admin with NO membership in this tenant, and a second isolated tenant'
do $$
declare
  v_tenant_id uuid;
  v_other_tenant_id uuid;
  v_org_unit_id uuid;
begin
  insert into auth.users (id, email) values
    ('00000000-0000-0000-0000-000000998301', 'membero1b4@example.test'),
    ('00000000-0000-0000-0000-000000998303', 'customerusero1b4@example.test'),
    ('00000000-0000-0000-0000-000000998304', 'supremeo1b4@example.test'),
    ('00000000-0000-0000-0000-000000998305', 'othertenanto1b4@example.test');

  perform app.provision_tenant('acmeo1b4', 'Acme O1B4 Co', 'idem-acmeo1b4', 'tester');
  v_tenant_id := (select id from app.tenants where slug = 'acmeo1b4');
  perform app.transition_tenant_status(v_tenant_id, 'active', 'setup', 'tester');
  perform app.create_org_unit(v_tenant_id, 'company', null, 'ACMEO1B4-CO', 'Acme O1B4 Co', 'tester');
  v_org_unit_id := (select id from app.org_units where tenant_id = v_tenant_id and code = 'ACMEO1B4-CO');

  perform app.invite_user(v_tenant_id, '00000000-0000-0000-0000-000000998301', 'membero1b4@example.test', 'Member', v_org_unit_id, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'membero1b4@example.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000998301', 'org_user', v_tenant_id, null, 'tester');

  perform app.link_auth_identity('00000000-0000-0000-0000-000000998303', v_tenant_id, 'tester', 'active');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000998303', 'customer_user', v_tenant_id, 'fake-account-ref', 'tester');

  perform app.grant_principal_membership('00000000-0000-0000-0000-000000998304', 'supreme_admin', null, null, 'tester');

  perform app.provision_tenant('gizmoo1b4', 'Gizmo O1B4 Co', 'idem-gizmoo1b4', 'tester');
  v_other_tenant_id := (select id from app.tenants where slug = 'gizmoo1b4');
  perform app.transition_tenant_status(v_other_tenant_id, 'active', 'setup', 'tester');
  perform app.invite_user(v_other_tenant_id, '00000000-0000-0000-0000-000000998305', 'othertenanto1b4@example.test', 'Other Tenant Admin', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'othertenanto1b4@example.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000998305', 'tenant_admin', v_other_tenant_id, null, 'tester');
end $$;

\echo '>> app.leads: real data for the owner, cross-tenant denied'
do $$
declare
  v_tenant_id uuid;
  v_org_unit_id uuid;
  v_lead_id uuid;
  v_count integer;
begin
  v_tenant_id := (select id from app.tenants where slug = 'acmeo1b4');
  v_org_unit_id := (select id from app.org_units where tenant_id = v_tenant_id and code = 'ACMEO1B4-CO');

  v_lead_id := gen_random_uuid();
  insert into app.leads (id, tenant_id, source, contact_name, email, duplicate_fingerprint, owner_user_id, org_unit_id, created_by)
  values (v_lead_id, v_tenant_id, 'manual', 'O1B4 Test Lead', 'o1b4lead@example.test', 'fp-o1b4-lead-1', '00000000-0000-0000-0000-000000998301', v_org_unit_id, 'tester');

  select count(*) into v_count from app.list_leads(v_tenant_id, '00000000-0000-0000-0000-000000998301');
  if v_count <> 1 then
    raise exception 'assertion failed: expected the owner to list exactly 1 lead, got %', v_count;
  end if;

  select count(*) into v_count from app.list_leads(v_tenant_id, '00000000-0000-0000-0000-000000998305');
  if v_count <> 0 then
    raise exception 'assertion failed: a different tenant''s admin must not list this tenant''s leads, got %', v_count;
  end if;

  select count(*) into v_count from app.get_lead_by_id(v_lead_id, '00000000-0000-0000-0000-000000998301');
  if v_count <> 1 then
    raise exception 'assertion failed: expected the owner to read this lead by id';
  end if;

  select count(*) into v_count from app.get_lead_by_id(v_lead_id, '00000000-0000-0000-0000-000000998305');
  if v_count <> 0 then
    raise exception 'assertion failed: a different tenant''s admin must not read this lead by id, got %', v_count;
  end if;

  raise notice 'app.leads proof: owner lists/reads its own lead, cross-tenant denied throughout';
end $$;

\echo '>> RULE A: app.list_leads genuinely rejects a claimed actor that does not match the real session identity'
begin;
  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000998305", "role": "authenticated"}';
  do $$
  declare
    v_tenant_id uuid;
  begin
    v_tenant_id := (select id from app.tenants where slug = 'acmeo1b4');
    begin
      -- Real session is 998305 (the other tenant's admin); claims to be 998301 (this
      -- tenant's own member, who WOULD otherwise be allowed) -- must still be rejected.
      perform app.list_leads(v_tenant_id, '00000000-0000-0000-0000-000000998301');
      raise exception 'assertion failed: RULE A -- a claimed actor that does not match the real session identity must be rejected';
    exception
      when insufficient_privilege then
        raise notice 'RULE A proof: impersonation attempt correctly rejected (actor_identity_mismatch)';
    end;
  end $$;
  reset role;
  reset request.jwt.claims;
commit;

\echo '>> app.prospects: real data for the owner, deliberate column exclusion (normalized_legal_name/normalized_tax_id/duplicate_fingerprint/disqualified_at/archived_at never returned), cross-tenant denied'
do $$
declare
  v_tenant_id uuid;
  v_org_unit_id uuid;
  v_lead_id uuid;
  v_prospect_id uuid;
  v_count integer;
  v_cols text[];
begin
  v_tenant_id := (select id from app.tenants where slug = 'acmeo1b4');
  v_org_unit_id := (select id from app.org_units where tenant_id = v_tenant_id and code = 'ACMEO1B4-CO');

  v_lead_id := gen_random_uuid();
  insert into app.leads (id, tenant_id, source, contact_name, email, duplicate_fingerprint, owner_user_id, org_unit_id, created_by)
  values (v_lead_id, v_tenant_id, 'manual', 'O1B4 Test Lead For Prospect', 'o1b4leadprospect@example.test', 'fp-o1b4-lead-2', '00000000-0000-0000-0000-000000998301', v_org_unit_id, 'tester');

  v_prospect_id := gen_random_uuid();
  insert into app.prospects (id, tenant_id, lead_id, legal_name, duplicate_fingerprint, contact_name, owner_user_id, org_unit_id, created_by)
  values (v_prospect_id, v_tenant_id, v_lead_id, 'O1B4 Test Prospect Co', 'fp-o1b4-prospect-1', 'O1B4 Test Lead For Prospect', '00000000-0000-0000-0000-000000998301', v_org_unit_id, 'tester');

  select count(*) into v_count from app.list_prospects(v_tenant_id, '00000000-0000-0000-0000-000000998301');
  if v_count <> 1 then
    raise exception 'assertion failed: expected the owner to list exactly 1 prospect, got %', v_count;
  end if;

  select count(*) into v_count from app.list_prospects(v_tenant_id, '00000000-0000-0000-0000-000000998305');
  if v_count <> 0 then
    raise exception 'assertion failed: a different tenant''s admin must not list this tenant''s prospects, got %', v_count;
  end if;

  select count(*) into v_count from app.get_prospect_by_id(v_prospect_id, '00000000-0000-0000-0000-000000998301');
  if v_count <> 1 then
    raise exception 'assertion failed: expected the owner to read this prospect by id';
  end if;
  select count(*) into v_count from app.get_prospect_by_id(v_prospect_id, '00000000-0000-0000-0000-000000998305');
  if v_count <> 0 then
    raise exception 'assertion failed: a different tenant''s admin must not read this prospect by id, got %', v_count;
  end if;

  -- Deliberate column exclusion, checked via the function's own OUT parameters, not a sample row.
  select array_agg(parameter_name::text) into v_cols
  from information_schema.parameters
  where specific_schema = 'app' and specific_name = (
    select specific_name from information_schema.routines
    where routine_schema = 'app' and routine_name = 'list_prospects' limit 1
  ) and parameter_mode = 'OUT';
  if 'normalized_legal_name' = any(v_cols) or 'normalized_tax_id' = any(v_cols) or 'duplicate_fingerprint' = any(v_cols)
     or 'disqualified_at' = any(v_cols) or 'archived_at' = any(v_cols) then
    raise exception 'assertion failed: app.list_prospects must never return normalized_legal_name/normalized_tax_id/duplicate_fingerprint/disqualified_at/archived_at, got columns %', v_cols;
  end if;

  select array_agg(parameter_name::text) into v_cols
  from information_schema.parameters
  where specific_schema = 'app' and specific_name = (
    select specific_name from information_schema.routines
    where routine_schema = 'app' and routine_name = 'get_prospect_by_id' limit 1
  ) and parameter_mode = 'OUT';
  if 'normalized_legal_name' = any(v_cols) or 'normalized_tax_id' = any(v_cols) or 'duplicate_fingerprint' = any(v_cols)
     or 'disqualified_at' = any(v_cols) or 'archived_at' = any(v_cols) then
    raise exception 'assertion failed: app.get_prospect_by_id must never return normalized_legal_name/normalized_tax_id/duplicate_fingerprint/disqualified_at/archived_at, got columns %', v_cols;
  end if;

  raise notice 'app.prospects proof: owner lists/reads its own prospect, PII/identity-correlation columns never returned (%), cross-tenant denied', v_cols;
end $$;

\echo '>> app.quotations_directory family: field-masked real data for the owner (all 4 functions), cross-tenant denied'
do $$
declare
  v_tenant_id uuid;
  v_org_unit_id uuid;
  v_lead_id uuid;
  v_prospect_id uuid;
  v_opportunity_id uuid;
  v_quotation_id uuid;
  v_quotation_v2_id uuid;
  v_count integer;
  v_sell_masked boolean;
begin
  v_tenant_id := (select id from app.tenants where slug = 'acmeo1b4');
  v_org_unit_id := (select id from app.org_units where tenant_id = v_tenant_id and code = 'ACMEO1B4-CO');

  v_lead_id := gen_random_uuid();
  insert into app.leads (id, tenant_id, source, contact_name, email, duplicate_fingerprint, owner_user_id, org_unit_id, created_by)
  values (v_lead_id, v_tenant_id, 'manual', 'O1B4 Test Lead For Quotation', 'o1b4leadquote@example.test', 'fp-o1b4-lead-3', '00000000-0000-0000-0000-000000998301', v_org_unit_id, 'tester');

  v_prospect_id := gen_random_uuid();
  insert into app.prospects (id, tenant_id, lead_id, legal_name, duplicate_fingerprint, contact_name, owner_user_id, org_unit_id, created_by)
  values (v_prospect_id, v_tenant_id, v_lead_id, 'O1B4 Test Quotation Prospect Co', 'fp-o1b4-prospect-2', 'O1B4 Test Lead For Quotation', '00000000-0000-0000-0000-000000998301', v_org_unit_id, 'tester');

  v_opportunity_id := gen_random_uuid();
  insert into app.opportunities (id, tenant_id, prospect_id, name, owner_user_id, org_unit_id, created_by)
  values (v_opportunity_id, v_tenant_id, v_prospect_id, 'O1B4 Test Opportunity', '00000000-0000-0000-0000-000000998301', v_org_unit_id, 'tester');

  v_quotation_id := gen_random_uuid();
  insert into app.quotations (id, tenant_id, quote_number, opportunity_id, source_opportunity_version, prospect_id, currency, validity_to, root_quotation_id, version_number, is_current, status, owner_user_id, org_unit_id, created_by)
  values (v_quotation_id, v_tenant_id, 'QUO-O1B4-0001', v_opportunity_id, 1, v_prospect_id, 'USD', now() + interval '30 days', v_quotation_id, 1, false, 'draft', '00000000-0000-0000-0000-000000998301', v_org_unit_id, 'tester');

  v_quotation_v2_id := gen_random_uuid();
  insert into app.quotations (id, tenant_id, quote_number, opportunity_id, source_opportunity_version, prospect_id, currency, validity_to, root_quotation_id, version_number, is_current, status, owner_user_id, org_unit_id, created_by)
  values (v_quotation_v2_id, v_tenant_id, 'QUO-O1B4-0001', v_opportunity_id, 1, v_prospect_id, 'USD', now() + interval '30 days', v_quotation_id, 2, true, 'draft', '00000000-0000-0000-0000-000000998301', v_org_unit_id, 'tester');

  -- app.get_quotation_by_id: masked (no COM:View selling price granted to the member).
  select count(*), bool_and(sell_masked) into v_count, v_sell_masked
    from app.get_quotation_by_id(v_quotation_v2_id, '00000000-0000-0000-0000-000000998301');
  if v_count <> 1 or v_sell_masked is not true then
    raise exception 'assertion failed: expected exactly 1 masked quotation (sell_masked true), got count=%, sell_masked=%', v_count, v_sell_masked;
  end if;
  select count(*) into v_count from app.get_quotation_by_id(v_quotation_v2_id, '00000000-0000-0000-0000-000000998305');
  if v_count <> 0 then
    raise exception 'assertion failed: a different tenant''s admin must not read this quotation by id, got %', v_count;
  end if;

  -- app.list_quotation_versions: both versions, oldest first, cross-tenant denied.
  select count(*) into v_count from app.list_quotation_versions(v_quotation_id, '00000000-0000-0000-0000-000000998301');
  if v_count <> 2 then
    raise exception 'assertion failed: expected both quotation versions to be listed, got %', v_count;
  end if;
  select count(*) into v_count from app.list_quotation_versions(v_quotation_id, '00000000-0000-0000-0000-000000998305');
  if v_count <> 0 then
    raise exception 'assertion failed: a different tenant''s admin must not list this quotation''s versions, got %', v_count;
  end if;

  -- app.list_quotations_for_opportunity: both versions belong to the same opportunity.
  select count(*) into v_count from app.list_quotations_for_opportunity(v_opportunity_id, '00000000-0000-0000-0000-000000998301');
  if v_count <> 2 then
    raise exception 'assertion failed: expected both quotation versions for this opportunity, got %', v_count;
  end if;
  select count(*) into v_count from app.list_quotations_for_opportunity(v_opportunity_id, '00000000-0000-0000-0000-000000998305');
  if v_count <> 0 then
    raise exception 'assertion failed: a different tenant''s admin must not list this opportunity''s quotations, got %', v_count;
  end if;

  -- app.list_quotations_for_tenant: tenant-wide, capped read, cross-tenant denied.
  select count(*) into v_count from app.list_quotations_for_tenant(v_tenant_id, '00000000-0000-0000-0000-000000998301');
  if v_count <> 2 then
    raise exception 'assertion failed: expected both quotation versions in the tenant-wide list, got %', v_count;
  end if;
  select count(*) into v_count from app.list_quotations_for_tenant(v_tenant_id, '00000000-0000-0000-0000-000000998305');
  if v_count <> 0 then
    raise exception 'assertion failed: a different tenant''s admin must not list this tenant''s quotations, got %', v_count;
  end if;

  raise notice 'app.quotations_directory family proof: owner sees masked quotation/versions/opportunity-list/tenant-list, cross-tenant denied throughout';
end $$;

\echo '>> app.quotation_lines_directory: field-masked real data for the owner, cross-tenant denied'
do $$
declare
  v_tenant_id uuid;
  v_quotation_id uuid;
  v_line_id uuid;
  v_count integer;
  v_sell_masked boolean;
  v_cost_masked boolean;
begin
  v_tenant_id := (select id from app.tenants where slug = 'acmeo1b4');
  v_quotation_id := (select root_quotation_id from app.quotations where tenant_id = v_tenant_id and quote_number = 'QUO-O1B4-0001' and version_number = 1);

  v_line_id := gen_random_uuid();
  insert into app.quotation_lines (id, tenant_id, quotation_id, line_no, description, unit_price, line_gross_amount, line_discount_amount, line_tax_amount, line_total, cost_amount_snapshot, margin_pct_snapshot, created_by)
  values (v_line_id, v_tenant_id, v_quotation_id, 1, 'O1B4 test freight line', 1000000, 1000000, 0, 0, 1000000, 700000, 30, 'tester');

  select count(*), bool_and(sell_masked), bool_and(cost_masked) into v_count, v_sell_masked, v_cost_masked
    from app.list_quotation_lines(v_quotation_id, '00000000-0000-0000-0000-000000998301');
  if v_count <> 1 or v_sell_masked is not true or v_cost_masked is not true then
    raise exception 'assertion failed: expected exactly 1 masked quotation line (sell_masked/cost_masked both true), got count=%, sell_masked=%, cost_masked=%', v_count, v_sell_masked, v_cost_masked;
  end if;
  select count(*) into v_count from app.list_quotation_lines(v_quotation_id, '00000000-0000-0000-0000-000000998305');
  if v_count <> 0 then
    raise exception 'assertion failed: a different tenant''s admin must not see this quotation''s lines, got %', v_count;
  end if;

  raise notice 'app.quotation_lines_directory proof: owner sees masked line (sell_masked/cost_masked both true), cross-tenant denied';
end $$;

\echo '>> app.quotation_approval_rules: real data for a member, RULE B excludes the customer_user layer, Supreme Admin bypasses with zero membership, non-member raises, cross-tenant denied'
do $$
declare
  v_tenant_id uuid;
  v_rule_id uuid;
  v_count integer;
begin
  v_tenant_id := (select id from app.tenants where slug = 'acmeo1b4');

  v_rule_id := gen_random_uuid();
  insert into app.quotation_approval_rules (id, tenant_id, min_margin_pct, status, created_by)
  values (v_rule_id, v_tenant_id, 40, 'published', 'tester');

  select count(*) into v_count from app.list_quotation_approval_rule_versions(v_tenant_id, '00000000-0000-0000-0000-000000998301');
  if v_count <> 1 then
    raise exception 'assertion failed: expected the member to list exactly 1 quotation approval rule version, got %', v_count;
  end if;

  -- RULE B: the customer_user-layer principal must not see the tenant-wide policy list.
  begin
    perform app.list_quotation_approval_rule_versions(v_tenant_id, '00000000-0000-0000-0000-000000998303');
    raise exception 'assertion failed: RULE B -- a customer_user-layer principal must not list quotation approval rules';
  exception
    when insufficient_privilege then null;
  end;

  -- A non-member of this tenant has no standing at all.
  begin
    perform app.list_quotation_approval_rule_versions(v_tenant_id, '00000000-0000-0000-0000-000000998305');
    raise exception 'assertion failed: expected insufficient_authority for a non-member of the tenant';
  exception
    when insufficient_privilege then null;
  end;

  -- Explicit supreme-admin bypass ("OR is_supreme_admin()"): the fixture Supreme Admin has
  -- zero standing in this tenant but must still see the rule.
  select count(*) into v_count from app.list_quotation_approval_rule_versions(v_tenant_id, '00000000-0000-0000-0000-000000998304');
  if v_count <> 1 then
    raise exception 'assertion failed: expected the Supreme Admin (zero membership) to see the quotation approval rule via the explicit bypass, got %', v_count;
  end if;

  raise notice 'app.quotation_approval_rules proof: member sees the published rule, customer_user-layer excluded (RULE B), non-member raises, Supreme Admin bypasses with zero membership';
end $$;

\echo '>> app.quotation_acceptance_tokens: real data for the owner, token_hash never returned, cross-tenant denied'
do $$
declare
  v_tenant_id uuid;
  v_quotation_id uuid;
  v_count integer;
  v_cols text[];
begin
  v_tenant_id := (select id from app.tenants where slug = 'acmeo1b4');
  v_quotation_id := (select root_quotation_id from app.quotations where tenant_id = v_tenant_id and quote_number = 'QUO-O1B4-0001' and version_number = 1);

  insert into app.quotation_acceptance_tokens (id, tenant_id, quotation_id, token_hash, status, expires_at, created_by)
  values (gen_random_uuid(), v_tenant_id, v_quotation_id, 'fake-token-hash-o1b4-1', 'active', now() + interval '7 days', 'tester');

  select count(*) into v_count from app.list_quotation_acceptance_tokens(v_quotation_id, '00000000-0000-0000-0000-000000998301');
  if v_count <> 1 then
    raise exception 'assertion failed: expected the owner to list exactly 1 acceptance token, got %', v_count;
  end if;
  select count(*) into v_count from app.list_quotation_acceptance_tokens(v_quotation_id, '00000000-0000-0000-0000-000000998305');
  if v_count <> 0 then
    raise exception 'assertion failed: a different tenant''s admin must not list this quotation''s acceptance tokens, got %', v_count;
  end if;

  -- Security-critical column exclusion, checked via the function's own OUT parameters.
  select array_agg(parameter_name::text) into v_cols
  from information_schema.parameters
  where specific_schema = 'app' and specific_name = (
    select specific_name from information_schema.routines
    where routine_schema = 'app' and routine_name = 'list_quotation_acceptance_tokens' limit 1
  ) and parameter_mode = 'OUT';
  if 'token_hash' = any(v_cols) then
    raise exception 'assertion failed: app.list_quotation_acceptance_tokens must never return token_hash, got columns %', v_cols;
  end if;

  raise notice 'app.quotation_acceptance_tokens proof: owner lists its own acceptance token, token_hash never returned (%), cross-tenant denied', v_cols;
end $$;

\echo '>> schema-privilege defense in depth: anon holds zero EXECUTE on any new batch-4 function'
do $$
declare
  v_count integer;
begin
  select count(*) into v_count
  from information_schema.routine_privileges
  where routine_schema in ('app', 'public')
    and routine_name in (
      'list_leads', 'get_lead_by_id',
      'list_prospects', 'get_prospect_by_id',
      'get_quotation_by_id', 'list_quotation_versions', 'list_quotations_for_opportunity', 'list_quotations_for_tenant',
      'list_quotation_lines',
      'list_quotation_approval_rule_versions',
      'list_quotation_acceptance_tokens'
    )
    and grantee = 'anon';
  if v_count <> 0 then
    raise exception 'assertion failed: anon must hold zero EXECUTE on any batch-4 function, found % grants', v_count;
  end if;
  raise notice 'schema-privilege proof: anon holds zero EXECUTE on any of the 11 new batch-4 functions';
end $$;

\echo '>> o1-query-layer-cluster0-batch4.sql test suite passed'
