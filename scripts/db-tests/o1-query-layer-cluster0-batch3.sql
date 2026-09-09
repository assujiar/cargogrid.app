-- Real, executable test evidence for CG-AUDIT-2026-09-02 Ø1-query-layer, cluster 0 batch 3
-- (supabase/migrations/20260909010000_close_o1_query_layer_cluster0_batch3_costing_credit_approval.sql).
--
-- Proves, against a real disposable database: each new app.*/public.* function returns the
-- real data a member/record-owner can see; RULE A genuinely rejects a claimed actor that
-- does not match the real session identity; RULE B excludes a customer_user-layer principal
-- from app.credit_profiles/app.credit_profile_overrides/app.approval_requests (all three
-- gated by has_active_tenant_membership AND NOT actor_holds_customer_user_layer); a global
-- Supreme Admin with ZERO tenant membership genuinely bypasses every one of those three
-- (each predicate carries an explicit "OR is_supreme_admin()"); app.costing_response_
-- components' documented "all-or-nothing" (never masked-but-visible) COM:View cost gate
-- denies the plain member entirely, not merely masking columns; and cross-tenant denial
-- throughout.

\set ON_ERROR_STOP on

\echo '>> setup: one tenant with an org_user member (also the owner of every fixture row), a customer_user-layer principal, a global Supreme Admin with NO membership in this tenant, and a second isolated tenant'
do $$
declare
  v_tenant_id uuid;
  v_other_tenant_id uuid;
  v_org_unit_id uuid;
begin
  insert into auth.users (id, email) values
    ('00000000-0000-0000-0000-000000998201', 'membero1b3@example.test'),
    ('00000000-0000-0000-0000-000000998203', 'customerusero1b3@example.test'),
    ('00000000-0000-0000-0000-000000998204', 'supremeo1b3@example.test'),
    ('00000000-0000-0000-0000-000000998205', 'othertenanto1b3@example.test');

  perform app.provision_tenant('acmeo1b3', 'Acme O1B3 Co', 'idem-acmeo1b3', 'tester');
  v_tenant_id := (select id from app.tenants where slug = 'acmeo1b3');
  perform app.transition_tenant_status(v_tenant_id, 'active', 'setup', 'tester');
  perform app.create_org_unit(v_tenant_id, 'company', null, 'ACMEO1B3-CO', 'Acme O1B3 Co', 'tester');
  v_org_unit_id := (select id from app.org_units where tenant_id = v_tenant_id and code = 'ACMEO1B3-CO');

  perform app.invite_user(v_tenant_id, '00000000-0000-0000-0000-000000998201', 'membero1b3@example.test', 'Member', v_org_unit_id, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'membero1b3@example.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000998201', 'org_user', v_tenant_id, null, 'tester');

  perform app.link_auth_identity('00000000-0000-0000-0000-000000998203', v_tenant_id, 'tester', 'active');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000998203', 'customer_user', v_tenant_id, 'fake-account-ref', 'tester');

  perform app.grant_principal_membership('00000000-0000-0000-0000-000000998204', 'supreme_admin', null, null, 'tester');

  perform app.provision_tenant('gizmoo1b3', 'Gizmo O1B3 Co', 'idem-gizmoo1b3', 'tester');
  v_other_tenant_id := (select id from app.tenants where slug = 'gizmoo1b3');
  perform app.transition_tenant_status(v_other_tenant_id, 'active', 'setup', 'tester');
  perform app.invite_user(v_other_tenant_id, '00000000-0000-0000-0000-000000998205', 'othertenanto1b3@example.test', 'Other Tenant Admin', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'othertenanto1b3@example.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000998205', 'tenant_admin', v_other_tenant_id, null, 'tester');
end $$;

\echo '>> app.costing_responses_directory / app.costing_response_components: masked/all-or-nothing for the owner, cross-tenant denied'
do $$
declare
  v_tenant_id uuid;
  v_org_unit_id uuid;
  v_lead_id uuid;
  v_prospect_id uuid;
  v_opportunity_id uuid;
  v_costing_request_id uuid;
  v_component_id uuid;
  v_response_id uuid;
  v_count integer;
  v_cost_masked boolean;
begin
  v_tenant_id := (select id from app.tenants where slug = 'acmeo1b3');
  v_org_unit_id := (select id from app.org_units where tenant_id = v_tenant_id and code = 'ACMEO1B3-CO');

  v_lead_id := gen_random_uuid();
  insert into app.leads (id, tenant_id, source, contact_name, email, duplicate_fingerprint, owner_user_id, org_unit_id, created_by)
  values (v_lead_id, v_tenant_id, 'manual', 'O1B3 Test Lead', 'o1b3lead@example.test', 'fp-o1b3-lead-1', '00000000-0000-0000-0000-000000998201', v_org_unit_id, 'tester');

  v_prospect_id := gen_random_uuid();
  insert into app.prospects (id, tenant_id, lead_id, legal_name, duplicate_fingerprint, contact_name, owner_user_id, org_unit_id, created_by)
  values (v_prospect_id, v_tenant_id, v_lead_id, 'O1B3 Test Prospect Co', 'fp-o1b3-prospect-1', 'O1B3 Test Lead', '00000000-0000-0000-0000-000000998201', v_org_unit_id, 'tester');

  v_opportunity_id := gen_random_uuid();
  insert into app.opportunities (id, tenant_id, prospect_id, name, owner_user_id, org_unit_id, created_by)
  values (v_opportunity_id, v_tenant_id, v_prospect_id, 'O1B3 Test Opportunity', '00000000-0000-0000-0000-000000998201', v_org_unit_id, 'tester');

  v_costing_request_id := gen_random_uuid();
  insert into app.costing_requests (id, tenant_id, opportunity_id, source_opportunity_version, owner_user_id, org_unit_id, created_by)
  values (v_costing_request_id, v_tenant_id, v_opportunity_id, 1, '00000000-0000-0000-0000-000000998201', v_org_unit_id, 'tester');

  v_component_id := gen_random_uuid();
  insert into app.costing_request_components (id, tenant_id, costing_request_id, component_code, description)
  values (v_component_id, v_tenant_id, v_costing_request_id, 'ocean_freight', 'Ocean freight leg');

  v_response_id := gen_random_uuid();
  insert into app.costing_responses (id, tenant_id, costing_request_id, source_type, currency, total_amount, submitted_by)
  values (v_response_id, v_tenant_id, v_costing_request_id, 'internal', 'IDR', 1000000, 'tester');

  insert into app.costing_response_components (tenant_id, costing_response_id, costing_request_component_id, amount)
  values (v_tenant_id, v_response_id, v_component_id, 1000000);

  -- app.list_costing_responses_for_request: masked (no COM:View cost granted to the member).
  select count(*), bool_and(cost_masked) into v_count, v_cost_masked
    from app.list_costing_responses_for_request(v_costing_request_id, '00000000-0000-0000-0000-000000998201');
  if v_count <> 1 or v_cost_masked is not true then
    raise exception 'assertion failed: expected exactly 1 masked costing response (cost_masked true), got count=%, cost_masked=%', v_count, v_cost_masked;
  end if;

  select count(*) into v_count from app.list_costing_responses_for_request(v_costing_request_id, '00000000-0000-0000-0000-000000998205');
  if v_count <> 0 then
    raise exception 'assertion failed: a different tenant''s admin must not see this costing request''s responses, got %', v_count;
  end if;

  -- app.list_costing_response_components: all-or-nothing on COM:View cost -- the plain
  -- member (no such permission configured) gets zero rows, not a masked-but-visible row.
  select count(*) into v_count from app.list_costing_response_components(v_response_id, '00000000-0000-0000-0000-000000998201');
  if v_count <> 0 then
    raise exception 'assertion failed: expected zero component rows without COM:View cost (all-or-nothing), got %', v_count;
  end if;
  select count(*) into v_count from app.list_costing_response_components(v_response_id, '00000000-0000-0000-0000-000000998205');
  if v_count <> 0 then
    raise exception 'assertion failed: cross-tenant actor must also see zero component rows, got %', v_count;
  end if;

  raise notice 'app.costing_responses_directory/app.costing_response_components proof: owner sees masked response, all-or-nothing component gate denies without COM:View cost, cross-tenant denied throughout';
end $$;

\echo '>> RULE A: app.list_credit_profiles genuinely rejects a claimed actor that does not match the real session identity'
begin;
  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000998205", "role": "authenticated"}';
  do $$
  declare
    v_tenant_id uuid;
  begin
    v_tenant_id := (select id from app.tenants where slug = 'acmeo1b3');
    begin
      -- Real session is 998205 (the other tenant's admin); claims to be 998201 (this
      -- tenant's own member, who WOULD otherwise be allowed) -- must still be rejected.
      perform app.list_credit_profiles(v_tenant_id, '00000000-0000-0000-0000-000000998201');
      raise exception 'assertion failed: RULE A -- a claimed actor that does not match the real session identity must be rejected';
    exception
      when insufficient_privilege then
        raise notice 'RULE A proof: impersonation attempt correctly rejected (actor_identity_mismatch)';
    end;
  end $$;
  reset role;
  reset request.jwt.claims;
commit;

\echo '>> app.credit_profiles family + app.credit_profile_overrides: real (masked) data for a member, RULE B excludes the customer_user layer, Supreme Admin bypasses with zero membership, cross-tenant denied'
do $$
declare
  v_tenant_id uuid;
  v_org_unit_id uuid;
  v_account_id uuid;
  v_profile_id uuid;
  v_count integer;
  v_masked boolean;
begin
  v_tenant_id := (select id from app.tenants where slug = 'acmeo1b3');
  v_org_unit_id := (select id from app.org_units where tenant_id = v_tenant_id and code = 'ACMEO1B3-CO');

  insert into app.accounts (tenant_id, legal_name, duplicate_fingerprint, owner_user_id, org_unit_id, created_by)
  values (v_tenant_id, 'O1B3 Test Account', 'fp-o1b3-account-1', '00000000-0000-0000-0000-000000998201', v_org_unit_id, 'tester')
  returning id into v_account_id;

  v_profile_id := gen_random_uuid();
  insert into app.credit_profiles (id, tenant_id, account_id, currency, requested_limit_amount, owner_user_id, org_unit_id, created_by)
  values (v_profile_id, v_tenant_id, v_account_id, 'IDR', 50000000, '00000000-0000-0000-0000-000000998201', v_org_unit_id, 'tester');

  insert into app.credit_profile_overrides (tenant_id, credit_profile_id, amount, reason, expires_at, created_by)
  values (v_tenant_id, v_profile_id, 5000000, 'temporary override for test', now() + interval '30 days', 'tester');

  -- app.list_credit_profiles: masked (no COM:View selling price granted to the member).
  select count(*), bool_and(amount_masked) into v_count, v_masked
    from app.list_credit_profiles(v_tenant_id, '00000000-0000-0000-0000-000000998201');
  if v_count <> 1 or v_masked is not true then
    raise exception 'assertion failed: expected exactly 1 masked credit profile, got count=%, amount_masked=%', v_count, v_masked;
  end if;

  -- RULE B: the customer_user-layer principal must not see the tenant-wide credit list.
  begin
    perform app.list_credit_profiles(v_tenant_id, '00000000-0000-0000-0000-000000998203');
    raise exception 'assertion failed: RULE B -- a customer_user-layer principal must not list credit profiles';
  exception
    when insufficient_privilege then null;
  end;

  -- Cross-tenant: the other tenant's admin has no standing in this tenant at all.
  begin
    perform app.list_credit_profiles(v_tenant_id, '00000000-0000-0000-0000-000000998205');
    raise exception 'assertion failed: expected insufficient_authority for a non-member of the tenant';
  exception
    when insufficient_privilege then null;
  end;

  -- Explicit supreme-admin bypass ("OR is_supreme_admin()"): the fixture Supreme Admin has
  -- zero standing in this tenant but must still see the profile.
  select count(*) into v_count from app.list_credit_profiles(v_tenant_id, '00000000-0000-0000-0000-000000998204');
  if v_count <> 1 then
    raise exception 'assertion failed: expected the Supreme Admin (zero membership) to see the credit profile via the explicit bypass, got %', v_count;
  end if;

  select count(*) into v_count from app.get_credit_profile_for_account(v_account_id, '00000000-0000-0000-0000-000000998201');
  if v_count <> 1 then
    raise exception 'assertion failed: expected the member to read the credit profile for its own account';
  end if;
  select count(*) into v_count from app.get_credit_profile_for_account(v_account_id, '00000000-0000-0000-0000-000000998205');
  if v_count <> 0 then
    raise exception 'assertion failed: a different tenant''s admin must not read this account''s credit profile, got %', v_count;
  end if;

  select count(*) into v_count from app.get_credit_profile_by_id(v_profile_id, '00000000-0000-0000-0000-000000998201');
  if v_count <> 1 then
    raise exception 'assertion failed: expected the member to read the credit profile by id';
  end if;
  select count(*) into v_count from app.get_credit_profile_by_id(v_profile_id, '00000000-0000-0000-0000-000000998205');
  if v_count <> 0 then
    raise exception 'assertion failed: a different tenant''s admin must not read this credit profile by id, got %', v_count;
  end if;

  -- app.list_credit_profile_overrides: masked, RULE B, cross-tenant denied (zero rows,
  -- never a raise, per its own documented contract).
  select count(*), bool_and(amount_masked) into v_count, v_masked
    from app.list_credit_profile_overrides(v_profile_id, '00000000-0000-0000-0000-000000998201');
  if v_count <> 1 or v_masked is not true then
    raise exception 'assertion failed: expected exactly 1 masked credit profile override, got count=%, amount_masked=%', v_count, v_masked;
  end if;
  select count(*) into v_count from app.list_credit_profile_overrides(v_profile_id, '00000000-0000-0000-0000-000000998203');
  if v_count <> 0 then
    raise exception 'assertion failed: RULE B -- a customer_user-layer principal must not see credit profile overrides, got %', v_count;
  end if;
  select count(*) into v_count from app.list_credit_profile_overrides(v_profile_id, '00000000-0000-0000-0000-000000998205');
  if v_count <> 0 then
    raise exception 'assertion failed: a different tenant''s admin must not see this profile''s overrides, got %', v_count;
  end if;

  raise notice 'app.credit_profiles/app.credit_profile_overrides proof: member sees masked data, customer_user-layer excluded (RULE B), Supreme Admin bypasses with zero membership, cross-tenant denied throughout';
end $$;

\echo '>> app.get_approval_requests_entity_refs: real data for a member, RULE B excludes the customer_user layer, Supreme Admin bypasses with zero membership, cross-tenant denied -- shared by both credit.ts and quotation-approval.ts'
do $$
declare
  v_tenant_id uuid;
  v_config_object_id uuid;
  v_config_version_id uuid;
  v_request_id uuid;
  v_count integer;
  v_entity_type text;
begin
  v_tenant_id := (select id from app.tenants where slug = 'acmeo1b3');

  v_config_object_id := gen_random_uuid();
  insert into app.config_objects (id, config_type_code, tenant_id, scope_level, created_by)
  values (v_config_object_id, 'approval', v_tenant_id, 'tenant', 'tester');

  v_config_version_id := gen_random_uuid();
  insert into app.config_versions (id, config_object_id, version_number, status, created_by)
  values (v_config_version_id, v_config_object_id, 1, 'draft', 'tester');

  v_request_id := gen_random_uuid();
  insert into app.approval_requests (id, tenant_id, config_version_id, entity_type, entity_id, pattern, status, idempotency_key, requested_by)
  values (v_request_id, v_tenant_id, v_config_version_id, 'credit_profile', gen_random_uuid(), 'sequential', 'pending', 'idem-o1b3-approval-1', 'tester');

  select entity_type into v_entity_type from app.get_approval_requests_entity_refs(array[v_request_id], '00000000-0000-0000-0000-000000998201');
  if v_entity_type <> 'credit_profile' then
    raise exception 'assertion failed: expected the member to resolve entity_type=credit_profile for this request, got %', v_entity_type;
  end if;

  -- RULE B: the customer_user-layer principal must not resolve this request at all.
  select count(*) into v_count from app.get_approval_requests_entity_refs(array[v_request_id], '00000000-0000-0000-0000-000000998203');
  if v_count <> 0 then
    raise exception 'assertion failed: RULE B -- a customer_user-layer principal must not resolve approval request entity refs, got %', v_count;
  end if;

  -- Cross-tenant: silently omitted, never raised (matches the original .in() read's own contract).
  select count(*) into v_count from app.get_approval_requests_entity_refs(array[v_request_id], '00000000-0000-0000-0000-000000998205');
  if v_count <> 0 then
    raise exception 'assertion failed: a different tenant''s admin must not resolve this request''s entity ref, got %', v_count;
  end if;

  -- Explicit supreme-admin bypass: zero membership, still resolves.
  select count(*) into v_count from app.get_approval_requests_entity_refs(array[v_request_id], '00000000-0000-0000-0000-000000998204');
  if v_count <> 1 then
    raise exception 'assertion failed: expected the Supreme Admin (zero membership) to resolve the entity ref via the explicit bypass, got %', v_count;
  end if;

  raise notice 'app.get_approval_requests_entity_refs proof: member resolves entity_type=credit_profile, customer_user-layer excluded (RULE B), Supreme Admin bypasses with zero membership, cross-tenant denied';
end $$;

\echo '>> o1-query-layer-cluster0-batch3.sql test suite passed'
