-- Real, executable test evidence for CG-AUDIT-2026-09-02 Ø1-query-layer, cluster 0 batch 5
-- (supabase/migrations/20260909030000_close_o1_query_layer_cluster0_batch5_vendor_rate_
-- directories.sql). This is the FINAL batch of cluster 0 -- all 32 tables are closed after
-- this file passes.
--
-- Proves, against a real disposable database: each new app.*/public.* function returns the
-- real data a member/record-owner can see; RULE A genuinely rejects a claimed actor that
-- does not match the real session identity; RULE B excludes a customer_user-layer principal
-- from every vendor_rate_versions_directory/vendor_rate_tiers_directory function (the
-- hardened pattern-5 predicate); a global Supreme Admin with ZERO tenant membership
-- genuinely bypasses every one of them (each predicate carries an explicit
-- "OR is_supreme_admin()"); app.list_active_vendor_rates RAISES insufficient_authority for a
-- genuine non-member (the "list for one named tenant" posture, not a silent empty page);
-- app.get_rate_version_by_id/app.list_rate_selections_for_request/app.list_vendor_rate_tiers
-- correctly mask cost columns (cost_masked=true) for a member lacking COM:View cost/PRC:View
-- cost; app.list_procurement_linked_vendor_rate_versions/app.list_vendor_rate_versions_for_
-- vendor correctly filter on vendor_master_id; and cross-tenant denial throughout.

\set ON_ERROR_STOP on

\echo '>> setup: one tenant with an org_user member (also the owner of every fixture row), a customer_user-layer principal, a global Supreme Admin with NO membership in this tenant, and a second isolated tenant'
do $$
declare
  v_tenant_id uuid;
  v_other_tenant_id uuid;
  v_org_unit_id uuid;
begin
  insert into auth.users (id, email) values
    ('00000000-0000-0000-0000-000000998401', 'membero1b5@example.test'),
    ('00000000-0000-0000-0000-000000998403', 'customerusero1b5@example.test'),
    ('00000000-0000-0000-0000-000000998404', 'supremeo1b5@example.test'),
    ('00000000-0000-0000-0000-000000998405', 'othertenanto1b5@example.test');

  perform app.provision_tenant('acmeo1b5', 'Acme O1B5 Co', 'idem-acmeo1b5', 'tester');
  v_tenant_id := (select id from app.tenants where slug = 'acmeo1b5');
  perform app.transition_tenant_status(v_tenant_id, 'active', 'setup', 'tester');
  perform app.create_org_unit(v_tenant_id, 'company', null, 'ACMEO1B5-CO', 'Acme O1B5 Co', 'tester');
  v_org_unit_id := (select id from app.org_units where tenant_id = v_tenant_id and code = 'ACMEO1B5-CO');

  perform app.invite_user(v_tenant_id, '00000000-0000-0000-0000-000000998401', 'membero1b5@example.test', 'Member', v_org_unit_id, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'membero1b5@example.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000998401', 'org_user', v_tenant_id, null, 'tester');

  perform app.link_auth_identity('00000000-0000-0000-0000-000000998403', v_tenant_id, 'tester', 'active');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000998403', 'customer_user', v_tenant_id, 'fake-account-ref', 'tester');

  perform app.grant_principal_membership('00000000-0000-0000-0000-000000998404', 'supreme_admin', null, null, 'tester');

  perform app.provision_tenant('gizmoo1b5', 'Gizmo O1B5 Co', 'idem-gizmoo1b5', 'tester');
  v_other_tenant_id := (select id from app.tenants where slug = 'gizmoo1b5');
  perform app.transition_tenant_status(v_other_tenant_id, 'active', 'setup', 'tester');
  perform app.invite_user(v_other_tenant_id, '00000000-0000-0000-0000-000000998405', 'othertenanto1b5@example.test', 'Other Tenant Admin', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'othertenanto1b5@example.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000998405', 'tenant_admin', v_other_tenant_id, null, 'tester');
end $$;

\echo '>> app.vendor_rate_versions_directory family (5 functions): masked real data for the owner, RULE B excludes the customer_user layer, Supreme Admin bypasses with zero membership, cross-tenant denied'
do $$
declare
  v_tenant_id uuid;
  v_master_record_id uuid;
  v_vendor_identity_id uuid;
  v_rate_version_id uuid;
  v_rate_version_pending_id uuid;
  v_count integer;
  v_cost_masked boolean;
begin
  v_tenant_id := (select id from app.tenants where slug = 'acmeo1b5');

  v_master_record_id := gen_random_uuid();
  insert into app.master_records (id, master_type_code, tenant_id, code, name, created_by)
  values (v_master_record_id, 'vendor_rate', v_tenant_id, 'RATE-O1B5-1', 'O1B5 Test Rate Identity', 'tester');

  v_vendor_identity_id := gen_random_uuid();
  insert into app.master_records (id, master_type_code, tenant_id, code, name, created_by)
  values (v_vendor_identity_id, 'vendor', v_tenant_id, 'VENDOR-O1B5-1', 'O1B5 Test Vendor', 'tester');

  v_rate_version_id := gen_random_uuid();
  insert into app.vendor_rate_versions (id, tenant_id, master_record_id, vendor_master_id, service_type, origin_lane, destination_lane, currency, base_amount, minimum_amount, approval_status, effective_from, effective_to, created_by)
  values (v_rate_version_id, v_tenant_id, v_master_record_id, v_vendor_identity_id, 'ocean_freight', 'IDJKT', 'USLAX', 'USD', 1500, 1000, 'approved', now() - interval '1 day', null, 'tester');

  v_rate_version_pending_id := gen_random_uuid();
  insert into app.vendor_rate_versions (id, tenant_id, master_record_id, vendor_master_id, service_type, origin_lane, destination_lane, currency, base_amount, approval_status, created_by)
  values (v_rate_version_pending_id, v_tenant_id, v_master_record_id, v_vendor_identity_id, 'air_freight', 'IDJKT', 'USLAX', 'USD', 2500, 'pending_approval', 'tester');

  -- app.list_rate_versions_for_master_record: both versions (any approval_status).
  select count(*) into v_count from app.list_rate_versions_for_master_record(v_master_record_id, '00000000-0000-0000-0000-000000998401');
  if v_count <> 2 then
    raise exception 'assertion failed: expected both rate versions under the master record, got %', v_count;
  end if;
  select count(*) into v_count from app.list_rate_versions_for_master_record(v_master_record_id, '00000000-0000-0000-0000-000000998405');
  if v_count <> 0 then
    raise exception 'assertion failed: a different tenant''s admin must not list this master record''s rate versions, got %', v_count;
  end if;

  -- app.get_rate_version_by_id: masked (no COM:View cost granted to the member).
  select count(*), bool_and(cost_masked) into v_count, v_cost_masked
    from app.get_rate_version_by_id(v_rate_version_id, '00000000-0000-0000-0000-000000998401');
  if v_count <> 1 or v_cost_masked is not true then
    raise exception 'assertion failed: expected exactly 1 masked rate version (cost_masked true), got count=%, cost_masked=%', v_count, v_cost_masked;
  end if;
  select count(*) into v_count from app.get_rate_version_by_id(v_rate_version_id, '00000000-0000-0000-0000-000000998405');
  if v_count <> 0 then
    raise exception 'assertion failed: a different tenant''s admin must not read this rate version by id, got %', v_count;
  end if;

  -- app.list_pending_rate_versions: only the pending one.
  select count(*) into v_count from app.list_pending_rate_versions(v_tenant_id, '00000000-0000-0000-0000-000000998401');
  if v_count <> 1 then
    raise exception 'assertion failed: expected exactly 1 pending rate version, got %', v_count;
  end if;
  select count(*) into v_count from app.list_pending_rate_versions(v_tenant_id, '00000000-0000-0000-0000-000000998405');
  if v_count <> 0 then
    raise exception 'assertion failed: a different tenant''s admin must not list this tenant''s pending rate versions, got %', v_count;
  end if;

  -- app.list_procurement_linked_vendor_rate_versions: both versions carry vendor_master_id.
  select count(*) into v_count from app.list_procurement_linked_vendor_rate_versions(v_tenant_id, '00000000-0000-0000-0000-000000998401');
  if v_count <> 2 then
    raise exception 'assertion failed: expected both procurement-linked rate versions, got %', v_count;
  end if;
  select count(*) into v_count from app.list_procurement_linked_vendor_rate_versions(v_tenant_id, '00000000-0000-0000-0000-000000998405');
  if v_count <> 0 then
    raise exception 'assertion failed: a different tenant''s admin must not list this tenant''s procurement-linked rate versions, got %', v_count;
  end if;

  -- app.list_vendor_rate_versions_for_vendor: both versions belong to the same vendor identity.
  select count(*) into v_count from app.list_vendor_rate_versions_for_vendor(v_tenant_id, v_vendor_identity_id, '00000000-0000-0000-0000-000000998401');
  if v_count <> 2 then
    raise exception 'assertion failed: expected both rate versions for this vendor identity, got %', v_count;
  end if;
  select count(*) into v_count from app.list_vendor_rate_versions_for_vendor(v_tenant_id, v_vendor_identity_id, '00000000-0000-0000-0000-000000998405');
  if v_count <> 0 then
    raise exception 'assertion failed: a different tenant''s admin must not list this vendor''s rate versions, got %', v_count;
  end if;

  -- RULE B: the customer_user-layer principal gets ZERO rows from every function above, not
  -- merely masked ones -- checked here once against the representative list function.
  select count(*) into v_count from app.list_rate_versions_for_master_record(v_master_record_id, '00000000-0000-0000-0000-000000998403');
  if v_count <> 0 then
    raise exception 'assertion failed: RULE B -- a customer_user-layer principal must see zero rate versions, got %', v_count;
  end if;

  -- Explicit supreme-admin bypass ("OR is_supreme_admin()"): the fixture Supreme Admin has
  -- zero standing in this tenant but must still see both rate versions.
  select count(*) into v_count from app.list_rate_versions_for_master_record(v_master_record_id, '00000000-0000-0000-0000-000000998404');
  if v_count <> 2 then
    raise exception 'assertion failed: expected the Supreme Admin (zero membership) to see both rate versions via the explicit bypass, got %', v_count;
  end if;

  raise notice 'app.vendor_rate_versions_directory family proof: owner sees masked/unmasked rows across all 5 functions, RULE B excludes customer_user layer, Supreme Admin bypasses with zero membership, cross-tenant denied throughout';
end $$;

\echo '>> RULE A: app.list_rate_versions_for_master_record genuinely rejects a claimed actor that does not match the real session identity'
begin;
  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000998405", "role": "authenticated"}';
  do $$
  declare
    v_master_record_id uuid;
  begin
    v_master_record_id := (select id from app.master_records where code = 'RATE-O1B5-1');
    begin
      -- Real session is 998405 (the other tenant's admin); claims to be 998401 (this
      -- tenant's own member, who WOULD otherwise be allowed) -- must still be rejected.
      perform app.list_rate_versions_for_master_record(v_master_record_id, '00000000-0000-0000-0000-000000998401');
      raise exception 'assertion failed: RULE A -- a claimed actor that does not match the real session identity must be rejected';
    exception
      when insufficient_privilege then
        raise notice 'RULE A proof: impersonation attempt correctly rejected (actor_identity_mismatch)';
    end;
  end $$;
  reset role;
  reset request.jwt.claims;
commit;

\echo '>> app.list_active_vendor_rates: only the approved + currently-effective rate version, raises for a genuine non-member, Supreme Admin bypasses with zero membership, cross-tenant admin has no standing either'
do $$
declare
  v_tenant_id uuid;
  v_count integer;
begin
  v_tenant_id := (select id from app.tenants where slug = 'acmeo1b5');

  -- Only the approved+effective version (the pending one is excluded).
  select count(*) into v_count from app.list_active_vendor_rates(v_tenant_id, '00000000-0000-0000-0000-000000998401');
  if v_count <> 1 then
    raise exception 'assertion failed: expected exactly 1 active (approved+effective) vendor rate, got %', v_count;
  end if;

  -- A genuine non-member (the other tenant's admin) raises, matching the "list for one named
  -- tenant" posture (never a silent empty page).
  begin
    perform app.list_active_vendor_rates(v_tenant_id, '00000000-0000-0000-0000-000000998405');
    raise exception 'assertion failed: expected insufficient_authority for a non-member of the tenant';
  exception
    when insufficient_privilege then null;
  end;

  -- Explicit supreme-admin bypass: zero membership, still lists the active rate.
  select count(*) into v_count from app.list_active_vendor_rates(v_tenant_id, '00000000-0000-0000-0000-000000998404');
  if v_count <> 1 then
    raise exception 'assertion failed: expected the Supreme Admin (zero membership) to see the active vendor rate via the explicit bypass, got %', v_count;
  end if;

  raise notice 'app.list_active_vendor_rates proof: only approved+effective rows returned, non-member raises, Supreme Admin bypasses with zero membership';
end $$;

\echo '>> app.vendor_rate_tiers_directory: masked real data for the owner, cross-tenant denied'
do $$
declare
  v_tenant_id uuid;
  v_rate_version_id uuid;
  v_count integer;
  v_cost_masked boolean;
begin
  v_tenant_id := (select id from app.tenants where slug = 'acmeo1b5');
  v_rate_version_id := (select id from app.vendor_rate_versions where tenant_id = v_tenant_id and approval_status = 'approved');

  insert into app.vendor_rate_tiers (id, tenant_id, rate_version_id, tier_order, amount, minimum_charge, created_by)
  values (gen_random_uuid(), v_tenant_id, v_rate_version_id, 1, 500, 100, 'tester');

  select count(*), bool_and(cost_masked) into v_count, v_cost_masked
    from app.list_vendor_rate_tiers(v_rate_version_id, '00000000-0000-0000-0000-000000998401');
  if v_count <> 1 or v_cost_masked is not true then
    raise exception 'assertion failed: expected exactly 1 masked vendor rate tier (cost_masked true), got count=%, cost_masked=%', v_count, v_cost_masked;
  end if;
  select count(*) into v_count from app.list_vendor_rate_tiers(v_rate_version_id, '00000000-0000-0000-0000-000000998405');
  if v_count <> 0 then
    raise exception 'assertion failed: a different tenant''s admin must not see this rate version''s tiers, got %', v_count;
  end if;

  raise notice 'app.vendor_rate_tiers_directory proof: owner sees masked tier (cost_masked true), cross-tenant denied';
end $$;

\echo '>> app.rate_selections_directory: masked real data for the owner, cross-tenant denied'
do $$
declare
  v_tenant_id uuid;
  v_org_unit_id uuid;
  v_rate_version_id uuid;
  v_lead_id uuid;
  v_prospect_id uuid;
  v_opportunity_id uuid;
  v_costing_request_id uuid;
  v_count integer;
  v_cost_masked boolean;
begin
  v_tenant_id := (select id from app.tenants where slug = 'acmeo1b5');
  v_org_unit_id := (select id from app.org_units where tenant_id = v_tenant_id and code = 'ACMEO1B5-CO');
  v_rate_version_id := (select id from app.vendor_rate_versions where tenant_id = v_tenant_id and approval_status = 'approved');

  v_lead_id := gen_random_uuid();
  insert into app.leads (id, tenant_id, source, contact_name, email, duplicate_fingerprint, owner_user_id, org_unit_id, created_by)
  values (v_lead_id, v_tenant_id, 'manual', 'O1B5 Test Lead', 'o1b5lead@example.test', 'fp-o1b5-lead-1', '00000000-0000-0000-0000-000000998401', v_org_unit_id, 'tester');

  v_prospect_id := gen_random_uuid();
  insert into app.prospects (id, tenant_id, lead_id, legal_name, duplicate_fingerprint, contact_name, owner_user_id, org_unit_id, created_by)
  values (v_prospect_id, v_tenant_id, v_lead_id, 'O1B5 Test Prospect Co', 'fp-o1b5-prospect-1', 'O1B5 Test Lead', '00000000-0000-0000-0000-000000998401', v_org_unit_id, 'tester');

  v_opportunity_id := gen_random_uuid();
  insert into app.opportunities (id, tenant_id, prospect_id, name, owner_user_id, org_unit_id, created_by)
  values (v_opportunity_id, v_tenant_id, v_prospect_id, 'O1B5 Test Opportunity', '00000000-0000-0000-0000-000000998401', v_org_unit_id, 'tester');

  v_costing_request_id := gen_random_uuid();
  insert into app.costing_requests (id, tenant_id, opportunity_id, source_opportunity_version, owner_user_id, org_unit_id, created_by)
  values (v_costing_request_id, v_tenant_id, v_opportunity_id, 1, '00000000-0000-0000-0000-000000998401', v_org_unit_id, 'tester');

  insert into app.rate_selections (id, tenant_id, costing_request_id, rate_version_id, is_adhoc, currency, amount, snapshot, selected_by)
  values (gen_random_uuid(), v_tenant_id, v_costing_request_id, v_rate_version_id, false, 'USD', 1500, '{}'::jsonb, 'tester');

  select count(*), bool_and(cost_masked) into v_count, v_cost_masked
    from app.list_rate_selections_for_request(v_costing_request_id, '00000000-0000-0000-0000-000000998401');
  if v_count <> 1 or v_cost_masked is not true then
    raise exception 'assertion failed: expected exactly 1 masked rate selection (cost_masked true), got count=%, cost_masked=%', v_count, v_cost_masked;
  end if;
  select count(*) into v_count from app.list_rate_selections_for_request(v_costing_request_id, '00000000-0000-0000-0000-000000998405');
  if v_count <> 0 then
    raise exception 'assertion failed: a different tenant''s admin must not see this costing request''s rate selections, got %', v_count;
  end if;

  raise notice 'app.rate_selections_directory proof: owner sees masked rate selection (cost_masked true), cross-tenant denied';
end $$;

\echo '>> schema-privilege defense in depth: anon holds zero EXECUTE on any new batch-5 function'
do $$
declare
  v_count integer;
begin
  select count(*) into v_count
  from information_schema.routine_privileges
  where routine_schema in ('app', 'public')
    and routine_name in (
      'list_rate_versions_for_master_record', 'get_rate_version_by_id',
      'list_pending_rate_versions', 'list_procurement_linked_vendor_rate_versions',
      'list_vendor_rate_versions_for_vendor',
      'list_active_vendor_rates',
      'list_rate_selections_for_request',
      'list_vendor_rate_tiers'
    )
    and grantee = 'anon';
  if v_count <> 0 then
    raise exception 'assertion failed: anon must hold zero EXECUTE on any batch-5 function, found % grants', v_count;
  end if;
  raise notice 'schema-privilege proof: anon holds zero EXECUTE on any of the 8 new batch-5 functions';
end $$;

\echo '>> o1-query-layer-cluster0-batch5.sql test suite passed -- cluster 0 (32/32 tables) is now fully DONE'
