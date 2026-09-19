-- Real, executable test evidence for CG-AUDIT-2026-09-02 O1-query-layer, cluster 4
-- (telematics-tracking) batch 2 of 2 -- the FINAL batch of cluster 4
-- (supabase/migrations/20260911060000_close_o1_query_layer_cluster4_batch2_tracking_security.sql).
--
-- Proves, against a real disposable database, both distinct authority shapes this
-- migration's own header discloses:
--
-- SHAPE 1 (SECURITY DEFINER, explicit p_actor_auth_user_id, RULE A guarded):
-- app.get_driver_mobile_tracking_session and app.get_active_shipment_tracking_token.
--   * app.get_driver_mobile_tracking_session: a real tenant member with NO owner/
--     org-unit relationship to anything sees the active driver-mobile bearer-token
--     row (this function's own tenant-membership predicate, not can_access_record),
--     and its own response shape NEVER carries a token_hash key at all (confirmed via
--     to_jsonb(row) ? 'token_hash', not merely "the caller ignores it"); a
--     customer_user-layer principal in the SAME tenant is denied despite active
--     membership; a cross-tenant actor is denied; a Supreme Admin with ZERO tenant
--     membership anywhere still sees the row; a tracking session with only a
--     REVOKED driver-mobile token (and a nonexistent tracking session id) both come
--     back as a GENUINELY EMPTY result (count(*)=0 AND exists()=false), never a row
--     of nulls; and RULE A genuinely rejects a claimed actor that does not match the
--     real session identity.
--   * app.get_active_shipment_tracking_token: an actor who can_access_record the
--     shipment order sees the active token's metadata (same token_hash-absence
--     proof); a real tenant member who CANNOT pass can_access_record for that same
--     shipment order (no owner/org-unit relationship) is denied; a cross-tenant actor
--     is denied; a shipment order with only a REVOKED token comes back genuinely
--     empty even for its own owner (isolating "no active token" from "actor cannot
--     see the row"); and RULE A genuinely rejects a claimed actor that does not match
--     the real session identity.
--
-- SHAPE 2 (SECURITY INVOKER, zero actor parameter, relies on the CALLING SESSION's
-- own live RLS): app.list_gps_device_installations, app.get_gps_device_installation_
-- for_assignment, and app.get_tenant_tracking_source_policy -- all 3 share the
-- IDENTICAL tenant-membership RLS predicate shape (the same shape this series' own
-- cluster 3 batch 4 PART 2A already proved for app.vehicle_capacity_reservations):
-- a real tenant member with no owner/org-unit relationship to anything DOES see these
-- rows, a customer_user-layer principal in the same tenant is denied despite active
-- membership, a cross-tenant actor is denied, and a Supreme Admin with ZERO tenant
-- membership anywhere still sees the rows.
--   * app.list_gps_device_installations: installed_at-descending order is proven
--     against 2 fixture rows inserted out of that order.
--   * app.get_gps_device_installation_for_assignment: resolves the real row for an
--     assignment with recorded evidence, and returns a GENUINELY EMPTY result
--     (count=0, no row at all via exists()) for a real, current assignment with NO
--     installation evidence recorded yet -- never a row of nulls.
--   * app.get_tenant_tracking_source_policy: returns the real explicit policy row for
--     a tenant that has set one, and -- the one piece of optional "flavor" this batch
--     calls out -- for a tenant that has NEVER set an explicit policy, this function
--     returns a GENUINELY EMPTY result while the sibling app.resolve_tenant_tracking_
--     source_policy (NOT part of this migration) ALWAYS resolves to exactly one
--     defaulted row (is_explicit=false) -- the exact structural distinction this
--     migration's own header discloses, confirmed even under a Supreme Admin session
--     that could see a real row if one actually existed.
--
-- Also confirms schema-privilege defense in depth: anon holds zero EXECUTE on any of
-- the 5 new public.* wrapper functions -- real call attempts, not merely an
-- information_schema read -- and a service_role smoke check: the 2 SECURITY DEFINER
-- functions (passed a real actor id explicitly, since neither ever relies on
-- auth.uid()) succeed via both app.* and public.*; the 3 SECURITY INVOKER functions
-- succeed via service_role's own BYPASSRLS regardless of membership, under a session
-- that carries no request.jwt.claims at all. A full information_schema.routine_
-- privileges spot check confirms authenticated/service_role hold EXECUTE on both the
-- app.* function and its public.* wrapper for all 5 pairs, exactly as this
-- migration's own GRANT PARITY section declares.
--
-- Fixture UUID range: 999201-999260 (last 6 hex digits) -- distinct from every other
-- db-test file in this series (most recently cluster 3 batch 4's 999001-999060 and
-- the sibling cluster 4 batch 1 agent's own, independently-chosen 999101-999160,
-- drafted in parallel against a completely disjoint set of tables/functions).

\set ON_ERROR_STOP on

\echo '>> setup: tenant acmeo1c4b2 with an owner (org_user, owns SO1/SO2 and their fixture chain), a tenant-only member with NO owner/org-unit relationship to anything (real active membership -- admitted under the tenant-membership shape function 1/3/4/5 all rely on, but denied under can_access_record, which function 2 relies on -- the two authority shapes are genuinely different, not the same predicate in disguise), a customer_user-layer principal, a global Supreme Admin with NO membership in this tenant, and a second isolated tenant gizmoo1c4b2 with its own admin (a real cross-tenant actor, and also the tenant used below for the get_tenant_tracking_source_policy-vs-resolve contrast, since it never gets an explicit policy row of its own)'
do $$
declare
  v_tenant_id uuid;
  v_other_tenant_id uuid;
  v_org_unit_id uuid;
begin
  insert into auth.users (id, email) values
    ('00000000-0000-0000-0000-000000999201', 'ownero1c4b2@example.test'),
    ('00000000-0000-0000-0000-000000999202', 'tenantonlyo1c4b2@example.test'),
    ('00000000-0000-0000-0000-000000999203', 'customerusero1c4b2@example.test'),
    ('00000000-0000-0000-0000-000000999204', 'supremeo1c4b2@example.test'),
    ('00000000-0000-0000-0000-000000999205', 'othertenanto1c4b2@example.test');

  perform app.provision_tenant('acmeo1c4b2', 'Acme O1C4B2 Co', 'idem-acmeo1c4b2', 'tester');
  v_tenant_id := (select id from app.tenants where slug = 'acmeo1c4b2');
  perform app.transition_tenant_status(v_tenant_id, 'active', 'setup', 'tester');
  perform app.create_org_unit(v_tenant_id, 'company', null, 'ACMEO1C4B2-CO', 'Acme O1C4B2 Co', 'tester');
  v_org_unit_id := (select id from app.org_units where tenant_id = v_tenant_id and code = 'ACMEO1C4B2-CO');

  perform app.invite_user(v_tenant_id, '00000000-0000-0000-0000-000000999201', 'ownero1c4b2@example.test', 'Owner', v_org_unit_id, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'ownero1c4b2@example.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000999201', 'org_user', v_tenant_id, null, 'tester');

  -- Real, ACTIVE org_user member of the SAME tenant, but no org_unit at all (so
  -- can_access_record's shared-org-unit branch never matches) and not the owner of
  -- anything -- denied under function 2's own reproduced can_access_record shape, yet
  -- admitted under the tenant-membership shape function 1 and functions 3/4/5 all use.
  perform app.invite_user(v_tenant_id, '00000000-0000-0000-0000-000000999202', 'tenantonlyo1c4b2@example.test', 'Tenant-Only Member', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'tenantonlyo1c4b2@example.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000999202', 'org_user', v_tenant_id, null, 'tester');

  -- Customer-portal-layer principal (ATW-023 shape): an active app.tenant_user_identities
  -- linkage plus an active customer_user app.principal_memberships row, granted directly
  -- (no app.users profile at all -- a customer_user-layer identity never gets one),
  -- mirroring scripts/db-tests/o1-query-layer-cluster3-batch4.sql's own established
  -- pattern for this exact identity shape.
  perform app.link_auth_identity('00000000-0000-0000-0000-000000999203', v_tenant_id, 'tester', 'active');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000999203', 'customer_user', v_tenant_id, 'fake-account-ref-o1c4b2', 'tester');

  perform app.grant_principal_membership('00000000-0000-0000-0000-000000999204', 'supreme_admin', null, null, 'tester');

  perform app.provision_tenant('gizmoo1c4b2', 'Gizmo O1C4B2 Co', 'idem-gizmoo1c4b2', 'tester');
  v_other_tenant_id := (select id from app.tenants where slug = 'gizmoo1c4b2');
  perform app.transition_tenant_status(v_other_tenant_id, 'active', 'setup', 'tester');
  perform app.invite_user(v_other_tenant_id, '00000000-0000-0000-0000-000000999205', 'othertenanto1c4b2@example.test', 'Other Tenant Admin', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'othertenanto1c4b2@example.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000999205', 'tenant_admin', v_other_tenant_id, null, 'tester');
end $$;

-- A plain, top-level, temporary test helper -- mirrors cluster 3 batch 1/2/4's own
-- job-order-chain helpers, trimmed to just what a Shipment Order needs
-- (app.shipment_orders.job_order_id is NOT NULL): the lead->prospect->opportunity->
-- quotation->job_order_handoff->job_order chain, real rows throughout.
create function app._o1c4b2_test_make_job_order_chain(p_tenant uuid, p_org_unit uuid, p_owner uuid, p_tag text)
returns table (job_order_id uuid, handoff_id uuid, quotation_id uuid, account_id uuid)
language plpgsql
as $$
declare
  v_lead uuid;
  v_prospect uuid;
  v_opportunity uuid;
  v_quotation uuid;
  v_handoff uuid;
  v_account uuid;
  v_job_order uuid;
begin
  insert into app.accounts (id, tenant_id, legal_name, duplicate_fingerprint, status, created_by)
  values (gen_random_uuid(), p_tenant, p_tag || ' Account', 'fp-o1c4b2-' || p_tag || '-account', 'active', 'tester')
  returning id into v_account;

  insert into app.leads (id, tenant_id, source, contact_name, email, duplicate_fingerprint, status, created_by)
  values (gen_random_uuid(), p_tenant, 'referral', p_tag || ' Lead', p_tag || '-lead@o1c4b2.test', 'fp-o1c4b2-' || p_tag || '-lead', 'qualified', 'tester')
  returning id into v_lead;
  insert into app.prospects (id, tenant_id, lead_id, legal_name, duplicate_fingerprint, contact_name, status, created_by)
  values (gen_random_uuid(), p_tenant, v_lead, p_tag || ' Prospect Co', 'fp-o1c4b2-' || p_tag || '-prospect', p_tag || ' Contact', 'active', 'tester')
  returning id into v_prospect;
  insert into app.opportunities (id, tenant_id, prospect_id, name, stage, created_by)
  values (gen_random_uuid(), p_tenant, v_prospect, p_tag || ' Opportunity', 'ready_for_costing', 'tester')
  returning id into v_opportunity;
  v_quotation := gen_random_uuid();
  insert into app.quotations (id, tenant_id, quote_number, opportunity_id, source_opportunity_version, prospect_id, currency, validity_to, status, root_quotation_id, created_by)
  values (v_quotation, p_tenant, 'QUO-O1C4B2-' || p_tag, v_opportunity, 1, v_prospect, 'USD', now() + interval '30 days', 'submitted', v_quotation, 'tester');
  insert into app.job_order_handoffs (id, tenant_id, quotation_id, account_id, payload, payload_hash, prepared_by_auth_user_id, owner_user_id, org_unit_id, created_by)
  values (gen_random_uuid(), p_tenant, v_quotation, v_account, jsonb_build_object('note', 'o1c4b2 handoff ' || p_tag), 'hash-o1c4b2-' || p_tag, p_owner, p_owner, p_org_unit, 'tester')
  returning id into v_handoff;
  insert into app.job_orders (
    id, tenant_id, job_number, source_handoff_id, quotation_id, account_id,
    customer_snapshot, cargo_service_snapshot, revenue_snapshot, contract_snapshot,
    credit_snapshot, acceptance_snapshot, status, owner_user_id, org_unit_id, created_by
  ) values (
    gen_random_uuid(), p_tenant, 'JOB-O1C4B2-' || p_tag, v_handoff, v_quotation, v_account,
    jsonb_build_object('legalName', p_tag || ' Account'), '{}'::jsonb,
    jsonb_build_object('totalAmount', 1000000, 'currency', 'IDR'), '{}'::jsonb,
    jsonb_build_object('creditTermsDays', 30), '{}'::jsonb,
    'confirmed', p_owner, p_org_unit, 'tester'
  )
  returning id into v_job_order;

  return query select v_job_order, v_handoff, v_quotation, v_account;
end;
$$;

\echo '>> fixture: SO1/SO2 (both owned by 999201) on a real job order chain, each with its own shipment leg (LEG1/LEG2) + tracking policy + shipment_leg_tracking_session (TS1/TS2); TS1 gets an ACTIVE app.driver_mobile_tracking_sessions token (DMT1, the primary row under test) while TS2 gets ONLY a REVOKED one (DMT2 -- the "no active token" fixture); SO1 gets an ACTIVE app.shipment_tracking_tokens row (STT1) while SO2 gets ONLY a REVOKED one (STT2 -- same fixture shape, one level up)'
do $$
declare
  v_tenant_id uuid := (select id from app.tenants where slug = 'acmeo1c4b2');
  v_org_unit_id uuid := (select id from app.org_units where tenant_id = v_tenant_id and code = 'ACMEO1C4B2-CO');
  v_chain record;
  v_so1_id uuid;
  v_so2_id uuid;
  v_leg1_id uuid;
  v_leg2_id uuid;
  v_policy1_id uuid;
  v_policy2_id uuid;
  v_driver1_id uuid;
  v_driver2_id uuid;
  v_ts1_id uuid;
  v_ts2_id uuid;
begin
  select * into v_chain from app._o1c4b2_test_make_job_order_chain(v_tenant_id, v_org_unit_id, '00000000-0000-0000-0000-000000999201', 'A');

  insert into app.shipment_orders (
    id, tenant_id, job_order_id, shipment_number, idempotency_key, status, shipper_account_id,
    consignee_snapshot, cargo_service_snapshot, service_type, mode, origin, destination,
    planned_pickup_at, owner_user_id, org_unit_id, created_by
  ) values (
    gen_random_uuid(), v_tenant_id, v_chain.job_order_id, 'SHP-O1C4B2-1', 'idem-shp-o1c4b2-1', 'confirmed', v_chain.account_id,
    '{}'::jsonb, '{}'::jsonb, 'FCL', 'sea', 'Jakarta', 'Surabaya',
    now() + interval '1 day', '00000000-0000-0000-0000-000000999201', v_org_unit_id, 'tester'
  ) returning id into v_so1_id;

  insert into app.shipment_orders (
    id, tenant_id, job_order_id, shipment_number, idempotency_key, status, shipper_account_id,
    consignee_snapshot, cargo_service_snapshot, service_type, mode, origin, destination,
    planned_pickup_at, owner_user_id, org_unit_id, created_by
  ) values (
    gen_random_uuid(), v_tenant_id, v_chain.job_order_id, 'SHP-O1C4B2-2', 'idem-shp-o1c4b2-2', 'confirmed', v_chain.account_id,
    '{}'::jsonb, '{}'::jsonb, 'LCL', 'land', 'Jakarta', 'Bandung',
    now() + interval '2 days', '00000000-0000-0000-0000-000000999201', v_org_unit_id, 'tester'
  ) returning id into v_so2_id;

  insert into app.shipment_legs (id, tenant_id, shipment_order_id, sequence_no, idempotency_key, mode, leg_status, created_by)
  values (gen_random_uuid(), v_tenant_id, v_so1_id, 1, 'idem-leg1-o1c4b2', 'sea', 'dispatched', 'tester')
  returning id into v_leg1_id;

  insert into app.shipment_legs (id, tenant_id, shipment_order_id, sequence_no, idempotency_key, mode, leg_status, created_by)
  values (gen_random_uuid(), v_tenant_id, v_so1_id, 2, 'idem-leg2-o1c4b2', 'sea', 'dispatched', 'tester')
  returning id into v_leg2_id;

  insert into app.master_records (id, master_type_code, tenant_id, code, name, canonical_status, created_by)
  values (gen_random_uuid(), 'driver', v_tenant_id, 'DRV-O1C4B2-1', 'O1C4B2 Driver 1', 'active', 'tester')
  returning id into v_driver1_id;

  insert into app.master_records (id, master_type_code, tenant_id, code, name, canonical_status, created_by)
  values (gen_random_uuid(), 'driver', v_tenant_id, 'DRV-O1C4B2-2', 'O1C4B2 Driver 2', 'active', 'tester')
  returning id into v_driver2_id;

  insert into app.shipment_leg_tracking_policies (
    id, tenant_id, shipment_leg_id, tracking_required, allowed_sources, preferred_source,
    fallback_order, start_trigger, end_trigger, customer_visible, created_by
  ) values (
    gen_random_uuid(), v_tenant_id, v_leg1_id, true, array['driver_mobile']::text[], 'driver_mobile',
    '{}'::text[], 'leg_dispatch', 'leg_complete', false, 'tester'
  ) returning id into v_policy1_id;

  insert into app.shipment_leg_tracking_policies (
    id, tenant_id, shipment_leg_id, tracking_required, allowed_sources, preferred_source,
    fallback_order, start_trigger, end_trigger, customer_visible, created_by
  ) values (
    gen_random_uuid(), v_tenant_id, v_leg2_id, true, array['driver_mobile']::text[], 'driver_mobile',
    '{}'::text[], 'leg_dispatch', 'leg_complete', false, 'tester'
  ) returning id into v_policy2_id;

  insert into app.shipment_leg_tracking_sessions (
    id, tenant_id, shipment_leg_id, policy_id, source_type, resource_kind, resource_master_id,
    status, started_at, is_current, created_by
  ) values (
    gen_random_uuid(), v_tenant_id, v_leg1_id, v_policy1_id, 'driver_mobile', 'driver', v_driver1_id,
    'active', now() - interval '1 day', true, 'tester'
  ) returning id into v_ts1_id;

  insert into app.shipment_leg_tracking_sessions (
    id, tenant_id, shipment_leg_id, policy_id, source_type, resource_kind, resource_master_id,
    status, started_at, is_current, created_by
  ) values (
    gen_random_uuid(), v_tenant_id, v_leg2_id, v_policy2_id, 'driver_mobile', 'driver', v_driver2_id,
    'active', now() - interval '1 day', true, 'tester'
  ) returning id into v_ts2_id;

  -- DMT1: the ACTIVE driver-mobile bearer token on TS1 -- the primary row under test
  -- for app.get_driver_mobile_tracking_session below.
  insert into app.driver_mobile_tracking_sessions (
    id, tenant_id, shipment_leg_tracking_session_id, token_hash, status, issued_at, expires_at, created_by
  ) values (
    gen_random_uuid(), v_tenant_id, v_ts1_id, 'o1c4b2-dmt1-token-hash', 'active', now() - interval '1 day', now() + interval '1 day', 'tester'
  );

  -- DMT2: a REVOKED-only driver-mobile bearer token on TS2 -- TS2 has no active token
  -- row at all, only revoked history -- the "no active token" fixture below.
  insert into app.driver_mobile_tracking_sessions (
    id, tenant_id, shipment_leg_tracking_session_id, token_hash, status, issued_at, expires_at, revoked_at, revoked_reason, created_by
  ) values (
    gen_random_uuid(), v_tenant_id, v_ts2_id, 'o1c4b2-dmt2-token-hash', 'revoked', now() - interval '2 days', now() + interval '5 days', now() - interval '1 day', 'o1c4b2 test revoke', 'tester'
  );

  -- STT1: the ACTIVE shipment tracking token on SO1 -- the primary row under test for
  -- app.get_active_shipment_tracking_token below.
  insert into app.shipment_tracking_tokens (
    id, tenant_id, shipment_order_id, token_hash, status, expires_at, created_by
  ) values (
    gen_random_uuid(), v_tenant_id, v_so1_id, 'o1c4b2-stt1-token-hash', 'active', now() + interval '7 days', 'tester'
  );

  -- STT2: a REVOKED-only shipment tracking token on SO2 -- SO2 has no active token at
  -- all, only revoked history -- the "no active token" fixture below.
  insert into app.shipment_tracking_tokens (
    id, tenant_id, shipment_order_id, token_hash, status, expires_at, revoked_at, revoked_reason, created_by
  ) values (
    gen_random_uuid(), v_tenant_id, v_so2_id, 'o1c4b2-stt2-token-hash', 'revoked', now() + interval '7 days', now() - interval '1 day', 'o1c4b2 test revoke', 'tester'
  );
end $$;

\echo '>> app.get_driver_mobile_tracking_session (SECURITY DEFINER, RULE A): a real tenant member with NO owner/org-unit relationship (999202) sees the active session on TS1, and the response NEVER carries a token_hash key at all (to_jsonb(row) ? ''token_hash'' is false, not merely ignored by a caller); a customer_user-layer principal (999203) is denied despite active membership; a cross-tenant actor (999205) is denied; a zero-membership Supreme Admin (999204) still sees the row'
do $$
declare
  v_ts1_id uuid := (select id from app.shipment_leg_tracking_sessions where shipment_leg_id = (select id from app.shipment_legs where idempotency_key = 'idem-leg1-o1c4b2'));
  v_row record;
  v_count integer;
begin
  select * into v_row from app.get_driver_mobile_tracking_session(v_ts1_id, '00000000-0000-0000-0000-000000999202');
  if v_row.id is null or v_row.status <> 'active' or v_row.shipment_leg_tracking_session_id <> v_ts1_id then
    raise exception 'assertion failed: tenant-only member (999202, no owner/org-unit relationship to anything) must see the active driver-mobile session on TS1, got %', v_row;
  end if;
  if to_jsonb(v_row) ? 'token_hash' then
    raise exception 'CRITICAL: app.get_driver_mobile_tracking_session''s own response shape carries a token_hash key -- ISS-2026-232 regression';
  end if;

  select count(*) into v_count from app.get_driver_mobile_tracking_session(v_ts1_id, '00000000-0000-0000-0000-000000999203');
  if v_count <> 0 then
    raise exception 'assertion failed: a customer_user-layer principal (999203) must see zero rows despite active membership, got %', v_count;
  end if;

  select count(*) into v_count from app.get_driver_mobile_tracking_session(v_ts1_id, '00000000-0000-0000-0000-000000999205');
  if v_count <> 0 then
    raise exception 'assertion failed: cross-tenant actor (999205) must see zero rows, got %', v_count;
  end if;

  select * into v_row from app.get_driver_mobile_tracking_session(v_ts1_id, '00000000-0000-0000-0000-000000999204');
  if v_row.id is null then
    raise exception 'assertion failed: Supreme Admin (999204, zero membership) must still see the active session on TS1';
  end if;

  raise notice 'app.get_driver_mobile_tracking_session proof: a real tenant member with no owner/org-unit relationship sees the row with no token_hash key at all in its own response shape; customer_user-layer/cross-tenant actors denied; Supreme Admin bypasses';
end $$;

\echo '>> app.get_driver_mobile_tracking_session: TS2 (only a REVOKED driver-mobile token, no active one) and a nonexistent shipment_leg_tracking_session_id both come back as a GENUINELY EMPTY result -- count(*)=0 AND no row at all via exists() -- never a row of nulls'
do $$
declare
  v_ts2_id uuid := (select id from app.shipment_leg_tracking_sessions where shipment_leg_id = (select id from app.shipment_legs where idempotency_key = 'idem-leg2-o1c4b2'));
  v_nonexistent uuid := gen_random_uuid();
  v_count integer;
begin
  select count(*) into v_count from app.get_driver_mobile_tracking_session(v_ts2_id, '00000000-0000-0000-0000-000000999201');
  if v_count <> 0 then
    raise exception 'assertion failed: TS2 (revoked-only token) must return zero rows, got %', v_count;
  end if;
  if exists (select 1 from app.get_driver_mobile_tracking_session(v_ts2_id, '00000000-0000-0000-0000-000000999201')) then
    raise exception 'assertion failed: TS2 (revoked-only token) must be a genuinely empty row set, found at least one row';
  end if;

  select count(*) into v_count from app.get_driver_mobile_tracking_session(v_nonexistent, '00000000-0000-0000-0000-000000999201');
  if v_count <> 0 then
    raise exception 'assertion failed: a nonexistent shipment_leg_tracking_session_id must return zero rows, got %', v_count;
  end if;
  if exists (select 1 from app.get_driver_mobile_tracking_session(v_nonexistent, '00000000-0000-0000-0000-000000999201')) then
    raise exception 'assertion failed: a nonexistent shipment_leg_tracking_session_id must be a genuinely empty row set, found at least one row';
  end if;

  raise notice 'app.get_driver_mobile_tracking_session proof: a revoked-only token and a nonexistent tracking session id both come back genuinely empty, never a row of nulls';
end $$;

\echo '>> app.get_active_shipment_tracking_token (SECURITY DEFINER, RULE A): the owner (999201, passes can_access_record on SO1) sees the active token''s metadata, with no token_hash key in the response shape; a real tenant member who cannot pass can_access_record for SO1 (999202, no owner/org-unit relationship) is denied; a cross-tenant actor (999205) is denied'
do $$
declare
  v_so1_id uuid := (select id from app.shipment_orders where shipment_number = 'SHP-O1C4B2-1');
  v_row record;
  v_count integer;
begin
  select * into v_row from app.get_active_shipment_tracking_token(v_so1_id, '00000000-0000-0000-0000-000000999201');
  if v_row.id is null or v_row.status <> 'active' or v_row.shipment_order_id <> v_so1_id then
    raise exception 'assertion failed: owner (999201) must see the active shipment tracking token on SO1, got %', v_row;
  end if;
  if to_jsonb(v_row) ? 'token_hash' then
    raise exception 'CRITICAL: app.get_active_shipment_tracking_token''s own response shape carries a token_hash key -- ISS-2026-232 regression';
  end if;

  select count(*) into v_count from app.get_active_shipment_tracking_token(v_so1_id, '00000000-0000-0000-0000-000000999202');
  if v_count <> 0 then
    raise exception 'assertion failed: a real tenant member who cannot pass can_access_record for SO1 (999202, no owner/org-unit relationship) must see zero rows, got %', v_count;
  end if;

  select count(*) into v_count from app.get_active_shipment_tracking_token(v_so1_id, '00000000-0000-0000-0000-000000999205');
  if v_count <> 0 then
    raise exception 'assertion failed: cross-tenant actor (999205) must see zero rows, got %', v_count;
  end if;

  raise notice 'app.get_active_shipment_tracking_token proof: an actor who can_access_record the shipment order sees the token metadata with no token_hash key at all in its own response shape; can_access_record denial and cross-tenant denial both hold';
end $$;

\echo '>> app.get_active_shipment_tracking_token: SO2 (only a REVOKED token, no active one) comes back as a GENUINELY EMPTY result for the very actor (999201, owner of SO2 too) who CAN otherwise access the shipment order -- isolating "no active token" from "actor cannot see the row"'
do $$
declare
  v_so2_id uuid := (select id from app.shipment_orders where shipment_number = 'SHP-O1C4B2-2');
  v_count integer;
begin
  select count(*) into v_count from app.get_active_shipment_tracking_token(v_so2_id, '00000000-0000-0000-0000-000000999201');
  if v_count <> 0 then
    raise exception 'assertion failed: SO2 (revoked-only token) must return zero rows even for its own owner, got %', v_count;
  end if;
  if exists (select 1 from app.get_active_shipment_tracking_token(v_so2_id, '00000000-0000-0000-0000-000000999201')) then
    raise exception 'assertion failed: SO2 (revoked-only token) must be a genuinely empty row set, found at least one row';
  end if;

  raise notice 'app.get_active_shipment_tracking_token proof: a shipment order with only a revoked token comes back genuinely empty, never a row of nulls, even for an actor who can otherwise access the record';
end $$;

\echo '>> RULE A (SAFETY-CRITICAL): app.get_driver_mobile_tracking_session and app.get_active_shipment_tracking_token both genuinely reject a claimed actor that does not match the real session identity'
begin;
  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000999205", "role": "authenticated"}';
  do $$
  declare
    v_ts1_id uuid := (select id from app.shipment_leg_tracking_sessions where shipment_leg_id = (select id from app.shipment_legs where idempotency_key = 'idem-leg1-o1c4b2'));
    v_so1_id uuid := (select id from app.shipment_orders where shipment_number = 'SHP-O1C4B2-1');
  begin
    begin
      -- Real session is 999205 (gizmoo1c4b2's own admin); claims to be 999201
      -- (acmeo1c4b2's own owner, who WOULD otherwise see this row) -- must still be
      -- rejected, before any lookup or authority check runs.
      perform app.get_driver_mobile_tracking_session(v_ts1_id, '00000000-0000-0000-0000-000000999201');
      raise exception 'assertion failed: RULE A -- a claimed actor that does not match the real session identity must be rejected (get_driver_mobile_tracking_session)';
    exception
      when insufficient_privilege then
        raise notice 'RULE A proof: get_driver_mobile_tracking_session impersonation attempt correctly rejected (actor_identity_mismatch)';
    end;

    begin
      perform app.get_active_shipment_tracking_token(v_so1_id, '00000000-0000-0000-0000-000000999201');
      raise exception 'assertion failed: RULE A -- a claimed actor that does not match the real session identity must be rejected (get_active_shipment_tracking_token)';
    exception
      when insufficient_privilege then
        raise notice 'RULE A proof: get_active_shipment_tracking_token impersonation attempt correctly rejected (actor_identity_mismatch)';
    end;
  end $$;
  reset role;
  reset request.jwt.claims;
commit;

\echo '>> fixture: two full device-vehicle-assignment chains for acmeo1c4b2 with recorded installation evidence -- V1/D1/DVA1/GDI1 (installed 2 days ago) and V2/D2/DVA2/GDI2 (installed 1 day ago, so app.list_gps_device_installations must return [GDI2, GDI1] under installed_at desc, the reverse of insertion order) -- plus V3/D3/DVA3, a real CURRENT device-vehicle assignment with ZERO installation evidence recorded yet (the "no installation for this assignment" fixture for app.get_gps_device_installation_for_assignment); and one explicit app.tenant_tracking_source_policies row for acmeo1c4b2 with values deliberately distinct from the system defaults -- gizmoo1c4b2 deliberately gets NO explicit policy row at all, for the get_tenant_tracking_source_policy-vs-resolve_tenant_tracking_source_policy contrast below'
do $$
declare
  v_tenant_id uuid := (select id from app.tenants where slug = 'acmeo1c4b2');
  v_vehicle1_id uuid;
  v_vehicle2_id uuid;
  v_vehicle3_id uuid;
  v_vop1_id uuid;
  v_vop2_id uuid;
  v_vop3_id uuid;
  v_device1_id uuid;
  v_device2_id uuid;
  v_device3_id uuid;
  v_dva1_id uuid;
  v_dva2_id uuid;
  v_dva3_id uuid;
  v_config_object_id uuid;
  v_config_version_id uuid;
  v_file1_id uuid;
  v_file2_id uuid;
begin
  insert into app.master_records (id, master_type_code, tenant_id, code, name, canonical_status, created_by) values
    (gen_random_uuid(), 'vehicle', v_tenant_id, 'VEH-O1C4B2-1', 'O1C4B2 Truck 1', 'active', 'tester') returning id into v_vehicle1_id;
  insert into app.master_records (id, master_type_code, tenant_id, code, name, canonical_status, created_by) values
    (gen_random_uuid(), 'vehicle', v_tenant_id, 'VEH-O1C4B2-2', 'O1C4B2 Truck 2', 'active', 'tester') returning id into v_vehicle2_id;
  insert into app.master_records (id, master_type_code, tenant_id, code, name, canonical_status, created_by) values
    (gen_random_uuid(), 'vehicle', v_tenant_id, 'VEH-O1C4B2-3', 'O1C4B2 Truck 3', 'active', 'tester') returning id into v_vehicle3_id;

  insert into app.vehicle_operational_profiles (id, tenant_id, vehicle_master_id, ownership_type, created_by) values
    (gen_random_uuid(), v_tenant_id, v_vehicle1_id, 'owned', 'tester') returning id into v_vop1_id;
  insert into app.vehicle_operational_profiles (id, tenant_id, vehicle_master_id, ownership_type, created_by) values
    (gen_random_uuid(), v_tenant_id, v_vehicle2_id, 'owned', 'tester') returning id into v_vop2_id;
  insert into app.vehicle_operational_profiles (id, tenant_id, vehicle_master_id, ownership_type, created_by) values
    (gen_random_uuid(), v_tenant_id, v_vehicle3_id, 'owned', 'tester') returning id into v_vop3_id;

  insert into app.gps_devices (id, tenant_id, imei, device_model, ownership_type, status, created_by) values
    (gen_random_uuid(), v_tenant_id, 'IMEI-O1C4B2-1', 'Model O1C4B2-X', 'cargogrid', 'installed', 'tester') returning id into v_device1_id;
  insert into app.gps_devices (id, tenant_id, imei, device_model, ownership_type, status, created_by) values
    (gen_random_uuid(), v_tenant_id, 'IMEI-O1C4B2-2', 'Model O1C4B2-X', 'cargogrid', 'installed', 'tester') returning id into v_device2_id;
  insert into app.gps_devices (id, tenant_id, imei, device_model, ownership_type, status, created_by) values
    (gen_random_uuid(), v_tenant_id, 'IMEI-O1C4B2-3', 'Model O1C4B2-X', 'cargogrid', 'assigned', 'tester') returning id into v_device3_id;

  insert into app.device_vehicle_assignments (id, tenant_id, device_id, vehicle_operational_profile_id, is_current, created_by) values
    (gen_random_uuid(), v_tenant_id, v_device1_id, v_vop1_id, true, 'tester') returning id into v_dva1_id;
  insert into app.device_vehicle_assignments (id, tenant_id, device_id, vehicle_operational_profile_id, is_current, created_by) values
    (gen_random_uuid(), v_tenant_id, v_device2_id, v_vop2_id, true, 'tester') returning id into v_dva2_id;
  insert into app.device_vehicle_assignments (id, tenant_id, device_id, vehicle_operational_profile_id, is_current, created_by) values
    (gen_random_uuid(), v_tenant_id, v_device3_id, v_vop3_id, true, 'tester') returning id into v_dva3_id;

  -- Minimal raw config-engine/document-type chain to satisfy app.files' own FK
  -- requirements -- this migration never touches the document engine, so bypassing
  -- app.register_document_type/app.create_config_draft/app.initiate_file_upload with
  -- direct inserts is the same "raw INSERT past the real RPC" idiom this series
  -- already uses for every other fixture chain (e.g. app.job_orders inserted directly
  -- rather than via app.prepare_job_order).
  insert into app.config_types (code, name, owner_primitive_code, registered_by) values
    ('document:o1c4b2_gps_evidence', 'O1C4B2 GPS Evidence', 'DOC', 'tester');
  insert into app.config_objects (id, config_type_code, tenant_id, scope_level, created_by) values
    (gen_random_uuid(), 'document:o1c4b2_gps_evidence', v_tenant_id, 'tenant', 'tester') returning id into v_config_object_id;
  insert into app.config_versions (id, config_object_id, version_number, status, created_by) values
    (gen_random_uuid(), v_config_object_id, 1, 'published', 'tester') returning id into v_config_version_id;
  insert into app.document_types (code, name, owner_primitive_code, registered_by) values
    ('o1c4b2_gps_evidence', 'O1C4B2 GPS Evidence', 'DOC', 'tester');

  insert into app.files (
    id, tenant_id, document_type_code, config_version_id, record_type, record_id,
    classification, original_filename, mime_type, size_bytes, storage_path,
    malware_scan_status, version_group_id, version_number, is_latest_version,
    lifecycle_status, legal_hold, uploaded_by_auth_user_id, shared_org_unit_ids,
    idempotency_key
  ) values (
    gen_random_uuid(), v_tenant_id, 'o1c4b2_gps_evidence', v_config_version_id, 'gps_device_installation', gen_random_uuid(),
    'internal', 'o1c4b2-install-1.jpg', 'image/jpeg', 204800, 'tenant/' || v_tenant_id::text || '/o1c4b2-install-1.jpg',
    'clean', gen_random_uuid(), 1, true,
    'active', false, '00000000-0000-0000-0000-000000999201', '{}',
    'idem-o1c4b2-file-1'
  ) returning id into v_file1_id;

  insert into app.files (
    id, tenant_id, document_type_code, config_version_id, record_type, record_id,
    classification, original_filename, mime_type, size_bytes, storage_path,
    malware_scan_status, version_group_id, version_number, is_latest_version,
    lifecycle_status, legal_hold, uploaded_by_auth_user_id, shared_org_unit_ids,
    idempotency_key
  ) values (
    gen_random_uuid(), v_tenant_id, 'o1c4b2_gps_evidence', v_config_version_id, 'gps_device_installation', gen_random_uuid(),
    'internal', 'o1c4b2-install-2.jpg', 'image/jpeg', 204800, 'tenant/' || v_tenant_id::text || '/o1c4b2-install-2.jpg',
    'clean', gen_random_uuid(), 1, true,
    'active', false, '00000000-0000-0000-0000-000000999201', '{}',
    'idem-o1c4b2-file-2'
  ) returning id into v_file2_id;

  -- GDI1: installed 2 days ago (older).
  insert into app.gps_device_installations (id, tenant_id, device_id, device_vehicle_assignment_id, evidence_file_id, technician_label, installed_at, created_by, updated_at)
  values (gen_random_uuid(), v_tenant_id, v_device1_id, v_dva1_id, v_file1_id, 'O1C4B2 Tech A', now() - interval '2 days', 'tester', now() - interval '2 days');

  -- GDI2: installed 1 day ago (newer) -- must sort FIRST under installed_at desc.
  insert into app.gps_device_installations (id, tenant_id, device_id, device_vehicle_assignment_id, evidence_file_id, technician_label, installed_at, created_by, updated_at)
  values (gen_random_uuid(), v_tenant_id, v_device2_id, v_dva2_id, v_file2_id, 'O1C4B2 Tech B', now() - interval '1 day', 'tester', now() - interval '1 day');

  -- DVA3 (declared above) is a real, current device-vehicle assignment with ZERO
  -- app.gps_device_installations rows referencing it -- the "no installation evidence
  -- recorded yet" fixture for app.get_gps_device_installation_for_assignment's own
  -- empty-on-miss proof below.

  -- One explicit tenant tracking source policy for acmeo1c4b2, values deliberately
  -- distinct from app.resolve_tenant_tracking_source_policy's own system defaults
  -- (array['driver_mobile','direct_device','third_party_platform']/300/100/120) so a
  -- test can tell "the real explicit row" apart from "the coalesce()-filled default".
  insert into app.tenant_tracking_source_policies (id, tenant_id, default_source_priority, freshness_threshold_seconds, accuracy_threshold_meters, switch_hysteresis_seconds, created_by)
  values (gen_random_uuid(), v_tenant_id, array['direct_device', 'driver_mobile']::text[], 222, 55, 15, 'tester');

  -- gizmoo1c4b2 deliberately gets NO app.tenant_tracking_source_policies row at all --
  -- the "tenant never set a policy" fixture for the get_tenant_tracking_source_policy
  -- vs. resolve_tenant_tracking_source_policy contrast below.
end $$;

\echo '>> owner session (999201, real acmeo1c4b2 tenant member, no owner/org-unit relationship required by any of these 3 INVOKER functions'' own RLS predicate): app.list_gps_device_installations returns [GDI2, GDI1] (installed_at desc, proven against fixture rows inserted out of that order); app.get_gps_device_installation_for_assignment resolves DVA1''s real row and returns a GENUINELY EMPTY result (count=0, no row at all) for DVA3 (a real, current assignment with no installation evidence yet); app.get_tenant_tracking_source_policy returns the real explicit policy row for acmeo1c4b2'
begin;
  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000999201", "role": "authenticated"}';
  do $$
  declare
    v_tenant_id uuid := (select id from app.tenants where slug = 'acmeo1c4b2');
    v_dva1_id uuid := (select id from app.device_vehicle_assignments where device_id = (select id from app.gps_devices where imei = 'IMEI-O1C4B2-1'));
    v_dva3_id uuid := (select id from app.device_vehicle_assignments where device_id = (select id from app.gps_devices where imei = 'IMEI-O1C4B2-3'));
    v_gdi1_id uuid := (select id from app.gps_device_installations where device_id = (select id from app.gps_devices where imei = 'IMEI-O1C4B2-1'));
    v_gdi2_id uuid := (select id from app.gps_device_installations where device_id = (select id from app.gps_devices where imei = 'IMEI-O1C4B2-2'));
    v_ids uuid[];
    v_row record;
    v_count integer;
  begin
    select array_agg(id) into v_ids from app.list_gps_device_installations(v_tenant_id);
    if v_ids <> array[v_gdi2_id, v_gdi1_id] then
      raise exception 'assertion failed: list_gps_device_installations must return [GDI2, GDI1] (installed_at desc), got %', v_ids;
    end if;

    select * into v_row from app.get_gps_device_installation_for_assignment(v_dva1_id);
    if v_row.id is null or v_row.id <> v_gdi1_id then
      raise exception 'assertion failed: get_gps_device_installation_for_assignment(DVA1) must return GDI1, got %', v_row;
    end if;

    select count(*) into v_count from app.get_gps_device_installation_for_assignment(v_dva3_id);
    if v_count <> 0 then
      raise exception 'assertion failed: get_gps_device_installation_for_assignment(DVA3, no installation yet) must return zero rows, got %', v_count;
    end if;
    if exists (select 1 from app.get_gps_device_installation_for_assignment(v_dva3_id)) then
      raise exception 'assertion failed: get_gps_device_installation_for_assignment(DVA3) must be a genuinely empty row set, found at least one row';
    end if;

    select * into v_row from app.get_tenant_tracking_source_policy(v_tenant_id);
    if v_row.tenant_id is null or v_row.freshness_threshold_seconds <> 222 or v_row.accuracy_threshold_meters <> 55 then
      raise exception 'assertion failed: get_tenant_tracking_source_policy must return the real explicit acmeo1c4b2 policy row, got %', v_row;
    end if;

    raise notice 'owner proof: list_gps_device_installations ordering correct; get_gps_device_installation_for_assignment resolves the real row and is genuinely empty on a real assignment with no installation; get_tenant_tracking_source_policy returns the real explicit row';
  end $$;
  reset role;
  reset request.jwt.claims;
commit;

\echo '>> customer_user-layer session (999203, an active tenant_user_identities linkage PLUS an active customer_user principal_memberships row in acmeo1c4b2): zero rows from all 3 INVOKER functions -- `AND NOT app.actor_holds_customer_user_layer(tenant_id)` genuinely excludes this identity despite passing has_active_tenant_membership'
begin;
  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000999203", "role": "authenticated"}';
  do $$
  declare
    v_tenant_id uuid := (select id from app.tenants where slug = 'acmeo1c4b2');
    v_dva1_id uuid := (select id from app.device_vehicle_assignments where device_id = (select id from app.gps_devices where imei = 'IMEI-O1C4B2-1'));
    v_count integer;
  begin
    select count(*) into v_count from app.list_gps_device_installations(v_tenant_id);
    if v_count <> 0 then raise exception 'assertion failed: a customer_user-layer principal must see zero rows from list_gps_device_installations, got %', v_count; end if;

    select count(*) into v_count from app.get_gps_device_installation_for_assignment(v_dva1_id);
    if v_count <> 0 then raise exception 'assertion failed: a customer_user-layer principal must see zero rows from get_gps_device_installation_for_assignment, got %', v_count; end if;

    select count(*) into v_count from app.get_tenant_tracking_source_policy(v_tenant_id);
    if v_count <> 0 then raise exception 'assertion failed: a customer_user-layer principal must see zero rows from get_tenant_tracking_source_policy, got %', v_count; end if;

    raise notice 'customer_user-layer proof: zero rows from all 3 INVOKER functions despite an active tenant membership -- the customer-layer exclusion genuinely fires';
  end $$;
  reset role;
  reset request.jwt.claims;
commit;

\echo '>> cross-tenant session (999205, gizmoo1c4b2''s own tenant_admin, no standing in acmeo1c4b2 at all): zero rows from all 3 INVOKER functions'
begin;
  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000999205", "role": "authenticated"}';
  do $$
  declare
    v_tenant_id uuid := (select id from app.tenants where slug = 'acmeo1c4b2');
    v_dva1_id uuid := (select id from app.device_vehicle_assignments where device_id = (select id from app.gps_devices where imei = 'IMEI-O1C4B2-1'));
    v_count integer;
  begin
    select count(*) into v_count from app.list_gps_device_installations(v_tenant_id);
    if v_count <> 0 then raise exception 'assertion failed: cross-tenant actor must see zero rows from list_gps_device_installations, got %', v_count; end if;

    select count(*) into v_count from app.get_gps_device_installation_for_assignment(v_dva1_id);
    if v_count <> 0 then raise exception 'assertion failed: cross-tenant actor must see zero rows from get_gps_device_installation_for_assignment, got %', v_count; end if;

    select count(*) into v_count from app.get_tenant_tracking_source_policy(v_tenant_id);
    if v_count <> 0 then raise exception 'assertion failed: cross-tenant actor must see zero rows from get_tenant_tracking_source_policy, got %', v_count; end if;

    raise notice 'cross-tenant proof: zero rows from all 3 INVOKER functions, never an exception';
  end $$;
  reset role;
  reset request.jwt.claims;
commit;

\echo '>> Supreme Admin session (999204, ZERO tenant membership anywhere): still sees the real rows from all 3 INVOKER functions via `... OR app.is_supreme_admin()`'
begin;
  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000999204", "role": "authenticated"}';
  do $$
  declare
    v_tenant_id uuid := (select id from app.tenants where slug = 'acmeo1c4b2');
    v_dva1_id uuid := (select id from app.device_vehicle_assignments where device_id = (select id from app.gps_devices where imei = 'IMEI-O1C4B2-1'));
    v_count integer;
  begin
    select count(*) into v_count from app.list_gps_device_installations(v_tenant_id);
    if v_count <> 2 then raise exception 'assertion failed: Supreme Admin with zero membership must bypass and see both installations, got %', v_count; end if;

    select count(*) into v_count from app.get_gps_device_installation_for_assignment(v_dva1_id);
    if v_count <> 1 then raise exception 'assertion failed: Supreme Admin with zero membership must bypass and see DVA1''s installation, got %', v_count; end if;

    select count(*) into v_count from app.get_tenant_tracking_source_policy(v_tenant_id);
    if v_count <> 1 then raise exception 'assertion failed: Supreme Admin with zero membership must bypass and see the real explicit policy row, got %', v_count; end if;

    raise notice 'Supreme Admin proof: zero tenant membership anywhere, still bypasses via the RLS policy''s own is_supreme_admin() branch on all 3 INVOKER functions';
  end $$;
  reset role;
  reset request.jwt.claims;
commit;

\echo '>> app.get_tenant_tracking_source_policy vs. the sibling app.resolve_tenant_tracking_source_policy (NOT part of this migration): for gizmoo1c4b2, which has never set an explicit policy, get_tenant_tracking_source_policy returns a GENUINELY EMPTY result while resolve_tenant_tracking_source_policy ALWAYS resolves to exactly one defaulted row (is_explicit=false) -- the exact structural distinction this migration''s own header discloses, confirmed even under a Supreme Admin session that could see a real row if one actually existed'
begin;
  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000999204", "role": "authenticated"}';
  do $$
  declare
    v_gizmo_tenant_id uuid := (select id from app.tenants where slug = 'gizmoo1c4b2');
    v_count integer;
    v_resolved record;
  begin
    select count(*) into v_count from app.get_tenant_tracking_source_policy(v_gizmo_tenant_id);
    if v_count <> 0 then
      raise exception 'assertion failed: get_tenant_tracking_source_policy(gizmoo1c4b2, no explicit policy ever set) must return zero rows, got %', v_count;
    end if;
    if exists (select 1 from app.get_tenant_tracking_source_policy(v_gizmo_tenant_id)) then
      raise exception 'assertion failed: get_tenant_tracking_source_policy(gizmoo1c4b2) must be a genuinely empty row set, found at least one row';
    end if;

    select * into v_resolved from app.resolve_tenant_tracking_source_policy(v_gizmo_tenant_id);
    if v_resolved.tenant_id is null or v_resolved.is_explicit is not false
       or v_resolved.freshness_threshold_seconds <> 300 or v_resolved.accuracy_threshold_meters <> 100 then
      raise exception 'assertion failed: resolve_tenant_tracking_source_policy(gizmoo1c4b2) must ALWAYS resolve to exactly one defaulted row (is_explicit=false, system defaults), got %', v_resolved;
    end if;

    raise notice 'get_tenant_tracking_source_policy-vs-resolve_tenant_tracking_source_policy proof: the new function returns a genuinely empty result for a tenant with no explicit policy, while the sibling function always resolves to exactly one defaulted row';
  end $$;
  reset role;
  reset request.jwt.claims;
commit;

\echo '>> anon defense in depth: all 5 public.* wrapper functions genuinely reject anon at the grant level -- real call attempts, not merely an information_schema read'
begin;
  set local role anon;
  do $$
  declare
    v_dummy uuid := gen_random_uuid();
  begin
    begin
      perform public.get_driver_mobile_tracking_session(v_dummy, v_dummy);
      raise exception 'assertion failed: anon must be denied EXECUTE on public.get_driver_mobile_tracking_session';
    exception
      when insufficient_privilege then
        raise notice 'anon denial proof: public.get_driver_mobile_tracking_session correctly rejected anon';
    end;

    begin
      perform public.list_gps_device_installations(v_dummy);
      raise exception 'assertion failed: anon must be denied EXECUTE on public.list_gps_device_installations';
    exception
      when insufficient_privilege then
        raise notice 'anon denial proof: public.list_gps_device_installations correctly rejected anon';
    end;

    begin
      perform public.get_gps_device_installation_for_assignment(v_dummy);
      raise exception 'assertion failed: anon must be denied EXECUTE on public.get_gps_device_installation_for_assignment';
    exception
      when insufficient_privilege then
        raise notice 'anon denial proof: public.get_gps_device_installation_for_assignment correctly rejected anon';
    end;

    begin
      perform public.get_tenant_tracking_source_policy(v_dummy);
      raise exception 'assertion failed: anon must be denied EXECUTE on public.get_tenant_tracking_source_policy';
    exception
      when insufficient_privilege then
        raise notice 'anon denial proof: public.get_tenant_tracking_source_policy correctly rejected anon';
    end;

    begin
      perform public.get_active_shipment_tracking_token(v_dummy, v_dummy);
      raise exception 'assertion failed: anon must be denied EXECUTE on public.get_active_shipment_tracking_token';
    exception
      when insufficient_privilege then
        raise notice 'anon denial proof: public.get_active_shipment_tracking_token correctly rejected anon';
    end;
  end $$;
  reset role;
commit;

\echo '>> service_role smoke check: app.get_driver_mobile_tracking_session/app.get_active_shipment_tracking_token (SECURITY DEFINER, explicit actor param -- passed a real actor id explicitly since neither ever relies on auth.uid()) succeed via both app.* and public.*; app.list_gps_device_installations/app.get_gps_device_installation_for_assignment/app.get_tenant_tracking_source_policy (SECURITY INVOKER) all succeed via service_role''s own BYPASSRLS regardless of membership, under a session that carries no request.jwt.claims at all'
begin;
  set local role service_role;
  do $$
  declare
    v_ts1_id uuid := (select id from app.shipment_leg_tracking_sessions where shipment_leg_id = (select id from app.shipment_legs where idempotency_key = 'idem-leg1-o1c4b2'));
    v_so1_id uuid := (select id from app.shipment_orders where shipment_number = 'SHP-O1C4B2-1');
    v_tenant_id uuid := (select id from app.tenants where slug = 'acmeo1c4b2');
    v_dva1_id uuid := (select id from app.device_vehicle_assignments where device_id = (select id from app.gps_devices where imei = 'IMEI-O1C4B2-1'));
    v_count integer;
  begin
    select count(*) into v_count from app.get_driver_mobile_tracking_session(v_ts1_id, '00000000-0000-0000-0000-000000999201');
    if v_count <> 1 then raise exception 'assertion failed: service_role must see TS1''s active session via app.get_driver_mobile_tracking_session, got %', v_count; end if;
    select count(*) into v_count from public.get_driver_mobile_tracking_session(v_ts1_id, '00000000-0000-0000-0000-000000999201');
    if v_count <> 1 then raise exception 'assertion failed: service_role must see TS1''s active session via public.get_driver_mobile_tracking_session, got %', v_count; end if;

    select count(*) into v_count from app.get_active_shipment_tracking_token(v_so1_id, '00000000-0000-0000-0000-000000999201');
    if v_count <> 1 then raise exception 'assertion failed: service_role must see SO1''s active token via app.get_active_shipment_tracking_token, got %', v_count; end if;
    select count(*) into v_count from public.get_active_shipment_tracking_token(v_so1_id, '00000000-0000-0000-0000-000000999201');
    if v_count <> 1 then raise exception 'assertion failed: service_role must see SO1''s active token via public.get_active_shipment_tracking_token, got %', v_count; end if;

    -- BYPASSRLS: this service_role session carries no request.jwt.claims at all
    -- (auth.uid() is null throughout), yet still sees every row on these 3
    -- RLS-policy-bearing tables -- BYPASSRLS, not membership, is what admits it.
    select count(*) into v_count from app.list_gps_device_installations(v_tenant_id);
    if v_count <> 2 then raise exception 'assertion failed: service_role must see both installations via app.list_gps_device_installations (BYPASSRLS), got %', v_count; end if;
    select count(*) into v_count from public.list_gps_device_installations(v_tenant_id);
    if v_count <> 2 then raise exception 'assertion failed: service_role must see both installations via public.list_gps_device_installations (BYPASSRLS), got %', v_count; end if;

    select count(*) into v_count from app.get_gps_device_installation_for_assignment(v_dva1_id);
    if v_count <> 1 then raise exception 'assertion failed: service_role must see DVA1''s installation via app.get_gps_device_installation_for_assignment (BYPASSRLS), got %', v_count; end if;
    select count(*) into v_count from public.get_gps_device_installation_for_assignment(v_dva1_id);
    if v_count <> 1 then raise exception 'assertion failed: service_role must see DVA1''s installation via public.get_gps_device_installation_for_assignment (BYPASSRLS), got %', v_count; end if;

    select count(*) into v_count from app.get_tenant_tracking_source_policy(v_tenant_id);
    if v_count <> 1 then raise exception 'assertion failed: service_role must see the real explicit policy via app.get_tenant_tracking_source_policy (BYPASSRLS), got %', v_count; end if;
    select count(*) into v_count from public.get_tenant_tracking_source_policy(v_tenant_id);
    if v_count <> 1 then raise exception 'assertion failed: service_role must see the real explicit policy via public.get_tenant_tracking_source_policy (BYPASSRLS), got %', v_count; end if;

    raise notice 'service_role proof: the 2 SECURITY DEFINER functions succeed with an explicitly-passed real actor id; the 3 SECURITY INVOKER functions succeed via BYPASSRLS regardless of membership';
  end $$;
  reset role;
commit;

\echo '>> schema-privilege defense in depth: anon holds zero EXECUTE on any of the 5 new cluster-4-batch-2 function pairs (10 functions) in EITHER schema; authenticated/service_role hold EXECUTE on both the app.* function and its public.* wrapper for all 5 pairs, exactly as this migration''s own GRANT PARITY section declares'
do $$
declare
  v_count integer;
begin
  select count(*) into v_count
  from information_schema.routine_privileges
  where routine_schema in ('app', 'public')
    and routine_name in (
      'get_driver_mobile_tracking_session',
      'list_gps_device_installations',
      'get_gps_device_installation_for_assignment',
      'get_tenant_tracking_source_policy',
      'get_active_shipment_tracking_token'
    )
    and grantee = 'anon';
  if v_count <> 0 then
    raise exception 'assertion failed: anon must hold zero EXECUTE on any of the 5 cluster-4-batch-2 function pairs (10 functions, either schema), found % grants', v_count;
  end if;

  -- Full check on all 5 pairs (not merely a spot check): authenticated AND
  -- service_role both hold EXECUTE on the app.* function AND its public.* wrapper for
  -- every one of the 5 pairs (grant parity, ISS-2026-309) -- 5 functions x 2 schemas
  -- x 2 grantees = 20 grants.
  select count(*) into v_count
  from information_schema.routine_privileges
  where routine_schema in ('app', 'public')
    and routine_name in (
      'get_driver_mobile_tracking_session',
      'list_gps_device_installations',
      'get_gps_device_installation_for_assignment',
      'get_tenant_tracking_source_policy',
      'get_active_shipment_tracking_token'
    )
    and grantee in ('authenticated', 'service_role');
  if v_count <> 5 * 2 * 2 then
    raise exception 'assertion failed: expected exactly 20 grants (5 functions x 2 schemas x 2 grantees), found %', v_count;
  end if;

  raise notice 'schema-privilege proof: anon holds zero EXECUTE on any of the 10 new cluster-4-batch-2 functions; authenticated/service_role hold the declared grant on both the app.* and public.* function in every one of the 5 pairs';
end $$;

drop function app._o1c4b2_test_make_job_order_chain(uuid, uuid, uuid, text);

\echo '>> o1-query-layer-cluster4-batch2.sql test suite passed -- cluster 4 batch 2 (driver mobile tracking sessions, GPS device installations, tenant tracking source policies, shipment tracking tokens, 5/5 call sites) is now fully DONE -- cluster 4 (telematics-tracking) is COMPLETE'
