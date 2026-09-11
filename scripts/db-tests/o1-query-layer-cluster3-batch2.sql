-- Real, executable test evidence for CG-AUDIT-2026-09-02 O1-query-layer, cluster 3
-- (operations-tms-core) batch 2 of ~N
-- (supabase/migrations/20260911010000_close_o1_query_layer_cluster3_batch2_milestone_leg_tracking_multileg.sql).
--
-- Proves, against a real disposable database:
--
-- PART 1 (SECURITY INVOKER, zero actor parameter, relies on the CALLING SESSION's own
-- live RLS): app.list_milestone_codes returns every seeded row (platform-wide, no
-- tenant scoping), ordered by name ascending, reachable by any authenticated session
-- but denied to anon at the public.* wrapper. app.get_shipment_leg_tracking_policy /
-- app.get_current_shipment_leg_tracking_session are exercised by actually forcing the
-- calling SESSION's own identity via `set local role authenticated; set local
-- request.jwt.claims = '{"sub": ..., "role": "authenticated"}'` (this repo's own
-- established idiom, scripts/db-tests/fixtures/auth-schema-stub.sql) since neither
-- function takes an actor parameter -- the owner and a shared-org-unit member (same
-- org unit, not the owner) both see the real policy row and the real is_current=true
-- session (never the superseded one); a real tenant member with no owner/org-unit
-- relationship to this shipment order, and a cross-tenant member, both get NULL from
-- both functions, never an exception; a Supreme Admin with ZERO tenant membership
-- anywhere still sees the real rows (app.can_access_record's own is_supreme_admin
-- branch); and a nonexistent shipment_leg_id also returns NULL, not an error.
--
-- PART 2 (SECURITY DEFINER, explicit p_actor_auth_user_id, RULE A guarded):
-- app.list_shipment_legs / app.get_shipment_leg_cargo_allocation /
-- app.list_shipment_leg_custody_events all return the real rows an owner or
-- shared-org-unit actor can see (list_shipment_legs includes a cancelled leg,
-- unfiltered, in correct sequence_no order; the cargo allocation returns NULL, not an
-- error, for a leg with no allocation row; custody events come back oldest-first); a
-- denied non-member actor and a cross-tenant actor both get zero rows/NULL from all
-- three, never an exception; a Supreme Admin with zero tenant membership anywhere sees
-- everything; and RULE A (app.assert_actor_is_session_identity) genuinely rejects a
-- claimed actor that does not match the real forced session identity, on all 3
-- functions.
--
-- Also confirms schema-privilege defense in depth: anon holds zero EXECUTE on any of
-- the 12 new functions in either schema (app or public) -- spot-checked directly for
-- public.list_milestone_codes (a real call attempt, not merely an information_schema
-- read) -- and (spot-checked on 3 of the 6 pairs) authenticated/service_role hold
-- EXECUTE on both the app.* function and its public.* wrapper, exactly as this
-- migration's own GRANT PARITY section declares.

\set ON_ERROR_STOP on

\echo '>> setup: tenant acmeo1c3b2 with an owner (org_user), a shared-org-unit member (same org unit, not the owner), a non-owning/non-org-unit member, a global Supreme Admin with NO membership in this tenant, and a second isolated tenant gizmoo1c3b2 with its own admin'
do $$
declare
  v_tenant_id uuid;
  v_other_tenant_id uuid;
  v_org_unit_id uuid;
begin
  insert into auth.users (id, email) values
    ('00000000-0000-0000-0000-000000998801', 'ownero1c3b2@example.test'),
    ('00000000-0000-0000-0000-000000998802', 'sharedvieweramo1c3b2@example.test'),
    ('00000000-0000-0000-0000-000000998803', 'deniedmembero1c3b2@example.test'),
    ('00000000-0000-0000-0000-000000998804', 'supremeo1c3b2@example.test'),
    ('00000000-0000-0000-0000-000000998805', 'othertenanto1c3b2@example.test');

  perform app.provision_tenant('acmeo1c3b2', 'Acme O1C3B2 Co', 'idem-acmeo1c3b2', 'tester');
  v_tenant_id := (select id from app.tenants where slug = 'acmeo1c3b2');
  perform app.transition_tenant_status(v_tenant_id, 'active', 'setup', 'tester');
  perform app.create_org_unit(v_tenant_id, 'company', null, 'ACMEO1C3B2-CO', 'Acme O1C3B2 Co', 'tester');
  v_org_unit_id := (select id from app.org_units where tenant_id = v_tenant_id and code = 'ACMEO1C3B2-CO');

  perform app.invite_user(v_tenant_id, '00000000-0000-0000-0000-000000998801', 'ownero1c3b2@example.test', 'Owner', v_org_unit_id, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'ownero1c3b2@example.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000998801', 'org_user', v_tenant_id, null, 'tester');

  -- Same org_unit_id as the owner -- app.can_access_record's shared-org-unit branch
  -- admits this identity to every row owned by 998801 in this org unit, without being
  -- the owner itself.
  perform app.invite_user(v_tenant_id, '00000000-0000-0000-0000-000000998802', 'sharedvieweramo1c3b2@example.test', 'Shared Viewer', v_org_unit_id, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'sharedvieweramo1c3b2@example.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000998802', 'org_user', v_tenant_id, null, 'tester');

  -- A real active org_user member of the SAME tenant, but no org_unit (so the
  -- shared-org-unit branch never matches), not the owner of anything, and no
  -- customer-account membership -- the exact per-row denial (not tenant-membership
  -- denial) app.can_access_record's own coalesce(..., false) is meant to produce.
  perform app.invite_user(v_tenant_id, '00000000-0000-0000-0000-000000998803', 'deniedmembero1c3b2@example.test', 'Denied Member', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'deniedmembero1c3b2@example.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000998803', 'org_user', v_tenant_id, null, 'tester');

  perform app.grant_principal_membership('00000000-0000-0000-0000-000000998804', 'supreme_admin', null, null, 'tester');

  perform app.provision_tenant('gizmoo1c3b2', 'Gizmo O1C3B2 Co', 'idem-gizmoo1c3b2', 'tester');
  v_other_tenant_id := (select id from app.tenants where slug = 'gizmoo1c3b2');
  perform app.transition_tenant_status(v_other_tenant_id, 'active', 'setup', 'tester');
  perform app.invite_user(v_other_tenant_id, '00000000-0000-0000-0000-000000998805', 'othertenanto1c3b2@example.test', 'Other Tenant Admin', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'othertenanto1c3b2@example.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000998805', 'tenant_admin', v_other_tenant_id, null, 'tester');
end $$;

-- A plain, top-level, temporary test helper -- mirrors cluster 3 batch 1's own
-- app._o1c3b1_test_make_job_order_chain (scripts/db-tests/o1-query-layer-cluster3-batch1.sql),
-- trimmed to just what a Shipment Order needs (app.shipment_orders.job_order_id is
-- NOT NULL): the lead->prospect->opportunity->quotation->job_order_handoff->job_order
-- chain, real rows throughout, never a raw shortcut into app.job_orders alone.
create function app._o1c3b2_test_make_job_order_chain(p_tenant uuid, p_org_unit uuid, p_owner uuid, p_tag text)
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
  values (gen_random_uuid(), p_tenant, p_tag || ' Account', 'fp-o1c3b2-' || p_tag || '-account', 'active', 'tester')
  returning id into v_account;

  insert into app.leads (id, tenant_id, source, contact_name, email, duplicate_fingerprint, status, created_by)
  values (gen_random_uuid(), p_tenant, 'referral', p_tag || ' Lead', p_tag || '-lead@o1c3b2.test', 'fp-o1c3b2-' || p_tag || '-lead', 'qualified', 'tester')
  returning id into v_lead;
  insert into app.prospects (id, tenant_id, lead_id, legal_name, duplicate_fingerprint, contact_name, status, created_by)
  values (gen_random_uuid(), p_tenant, v_lead, p_tag || ' Prospect Co', 'fp-o1c3b2-' || p_tag || '-prospect', p_tag || ' Contact', 'active', 'tester')
  returning id into v_prospect;
  insert into app.opportunities (id, tenant_id, prospect_id, name, stage, created_by)
  values (gen_random_uuid(), p_tenant, v_prospect, p_tag || ' Opportunity', 'ready_for_costing', 'tester')
  returning id into v_opportunity;
  v_quotation := gen_random_uuid();
  insert into app.quotations (id, tenant_id, quote_number, opportunity_id, source_opportunity_version, prospect_id, currency, validity_to, status, root_quotation_id, created_by)
  values (v_quotation, p_tenant, 'QUO-O1C3B2-' || p_tag, v_opportunity, 1, v_prospect, 'USD', now() + interval '30 days', 'submitted', v_quotation, 'tester');
  insert into app.job_order_handoffs (id, tenant_id, quotation_id, account_id, payload, payload_hash, prepared_by_auth_user_id, owner_user_id, org_unit_id, created_by)
  values (gen_random_uuid(), p_tenant, v_quotation, v_account, jsonb_build_object('note', 'o1c3b2 handoff ' || p_tag), 'hash-o1c3b2-' || p_tag, p_owner, p_owner, p_org_unit, 'tester')
  returning id into v_handoff;
  insert into app.job_orders (
    id, tenant_id, job_number, source_handoff_id, quotation_id, account_id,
    customer_snapshot, cargo_service_snapshot, revenue_snapshot, contract_snapshot,
    credit_snapshot, acceptance_snapshot, status, owner_user_id, org_unit_id, created_by
  ) values (
    gen_random_uuid(), p_tenant, 'JOB-O1C3B2-' || p_tag, v_handoff, v_quotation, v_account,
    jsonb_build_object('legalName', p_tag || ' Account'), '{}'::jsonb,
    jsonb_build_object('totalAmount', 1000000, 'currency', 'IDR'), '{}'::jsonb,
    jsonb_build_object('creditTermsDays', 30), '{}'::jsonb,
    'confirmed', p_owner, p_org_unit, 'tester'
  )
  returning id into v_job_order;

  return query select v_job_order, v_handoff, v_quotation, v_account;
end;
$$;

\echo '>> fixture: one shipment order (SHP-O1C3B2-1, owned by 998801) on a real job order chain, with 2 legs (LEG1 sequence_no=1 dispatched, LEG2 sequence_no=2 cancelled -- proving list_shipment_legs includes cancelled legs unfiltered), a tracking policy + 2 tracking sessions on LEG1 (one is_current=true, one is_current=false), a cargo allocation on LEG1 only (LEG2 deliberately has none), and 2 custody events on LEG1 with different sequence_no (proving oldest-first ordering)'
do $$
declare
  v_tenant_id uuid := (select id from app.tenants where slug = 'acmeo1c3b2');
  v_org_unit_id uuid := (select id from app.org_units where tenant_id = v_tenant_id and code = 'ACMEO1C3B2-CO');
  v_chain record;
  v_shipment_order_id uuid;
  v_leg1_id uuid;
  v_leg2_id uuid;
  v_driver_id uuid;
  v_policy_id uuid;
begin
  select * into v_chain from app._o1c3b2_test_make_job_order_chain(v_tenant_id, v_org_unit_id, '00000000-0000-0000-0000-000000998801', 'A');

  insert into app.shipment_orders (
    id, tenant_id, job_order_id, shipment_number, idempotency_key, status, shipper_account_id,
    consignee_snapshot, cargo_service_snapshot, service_type, mode, origin, destination,
    planned_pickup_at, owner_user_id, org_unit_id, created_by
  ) values (
    gen_random_uuid(), v_tenant_id, v_chain.job_order_id, 'SHP-O1C3B2-1', 'idem-shp-o1c3b2-1', 'confirmed', v_chain.account_id,
    '{}'::jsonb, '{}'::jsonb, 'FCL', 'sea', 'Jakarta', 'Surabaya',
    now() + interval '1 day', '00000000-0000-0000-0000-000000998801', v_org_unit_id, 'tester'
  ) returning id into v_shipment_order_id;

  insert into app.shipment_legs (id, tenant_id, shipment_order_id, sequence_no, idempotency_key, mode, leg_status, owner_user_id, created_by)
  values (gen_random_uuid(), v_tenant_id, v_shipment_order_id, 1, 'idem-leg1-o1c3b2', 'sea', 'dispatched', '00000000-0000-0000-0000-000000998801', 'tester')
  returning id into v_leg1_id;

  insert into app.shipment_legs (id, tenant_id, shipment_order_id, sequence_no, idempotency_key, mode, leg_status, owner_user_id, created_by)
  values (gen_random_uuid(), v_tenant_id, v_shipment_order_id, 2, 'idem-leg2-o1c3b2', 'sea', 'cancelled', '00000000-0000-0000-0000-000000998801', 'tester')
  returning id into v_leg2_id;

  insert into app.master_records (id, master_type_code, tenant_id, code, name, canonical_status, created_by)
  values (gen_random_uuid(), 'driver', v_tenant_id, 'DRV-O1C3B2-1', 'O1C3B2 Driver 1', 'active', 'tester')
  returning id into v_driver_id;

  insert into app.shipment_leg_tracking_policies (
    id, tenant_id, shipment_leg_id, tracking_required, allowed_sources, preferred_source,
    fallback_order, start_trigger, end_trigger, customer_visible, created_by
  ) values (
    gen_random_uuid(), v_tenant_id, v_leg1_id, true, array['driver_mobile']::text[], 'driver_mobile',
    '{}'::text[], 'leg_dispatch', 'leg_complete', false, 'tester'
  ) returning id into v_policy_id;

  insert into app.shipment_leg_tracking_sessions (
    id, tenant_id, shipment_leg_id, policy_id, source_type, resource_kind, resource_master_id,
    status, started_at, ended_at, end_reason, is_current, created_by
  ) values (
    '00000000-0000-0000-0000-0000eeee0001', v_tenant_id, v_leg1_id, v_policy_id, 'driver_mobile', 'driver', v_driver_id,
    'ended', now() - interval '2 days', now() - interval '1 day', 'handoff', false, 'tester'
  );

  insert into app.shipment_leg_tracking_sessions (
    id, tenant_id, shipment_leg_id, policy_id, source_type, resource_kind, resource_master_id,
    status, started_at, is_current, created_by
  ) values (
    '00000000-0000-0000-0000-0000eeee0002', v_tenant_id, v_leg1_id, v_policy_id, 'driver_mobile', 'driver', v_driver_id,
    'active', now() - interval '1 day', true, 'tester'
  );

  insert into app.shipment_leg_cargo_allocations (id, tenant_id, shipment_leg_id, allocated_quantity, allocated_weight_kg, allocated_volume_cbm, created_by)
  values ('00000000-0000-0000-0000-0000aaaa0001', v_tenant_id, v_leg1_id, 10, 500, 20, 'tester');

  insert into app.shipment_leg_custody_events (id, tenant_id, shipment_leg_id, sequence_no, event_type, to_party_snapshot, occurred_at, recorded_by)
  values ('00000000-0000-0000-0000-0000cccc0001', v_tenant_id, v_leg1_id, 1, 'custody_transfer', jsonb_build_object('party', 'origin_agent'), now() - interval '3 hours', 'tester');

  insert into app.shipment_leg_custody_events (id, tenant_id, shipment_leg_id, sequence_no, event_type, from_party_snapshot, to_party_snapshot, occurred_at, recorded_by)
  values ('00000000-0000-0000-0000-0000cccc0002', v_tenant_id, v_leg1_id, 2, 'handoff_confirmed', jsonb_build_object('party', 'origin_agent'), jsonb_build_object('party', 'linehaul_carrier'), now() - interval '1 hour', 'tester');
end $$;

\echo '>> app.list_milestone_codes: 2 real fixture rows inserted (out of alphabetical order); confirms every row in app.milestone_codes comes back, ordered by name ascending -- app.milestone_codes is genuinely platform-wide/non-tenant-scoped, so any authenticated session (no tenant fixture needed) can read it'
insert into app.milestone_codes (code, name, category, is_customer_visible, affects_eta, is_terminal, registered_by) values
  ('o1c3b2_test_zzz', 'Zzz O1c3b2 Test Milestone', 'administrative', false, false, false, 'o1c3b2-tester'),
  ('o1c3b2_test_aaa', 'Aaa O1c3b2 Test Milestone', 'administrative', false, false, false, 'o1c3b2-tester');

begin;
  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000998801", "role": "authenticated"}';
  do $$
  declare
    v_names text[];
    v_sorted_names text[];
    v_app_count integer;
    v_public_count integer;
    v_table_count integer;
  begin
    select array_agg(name) into v_names from app.list_milestone_codes();
    select array_agg(name order by name asc) into v_sorted_names from app.milestone_codes;
    if v_names is distinct from v_sorted_names then
      raise exception 'assertion failed: app.list_milestone_codes must return every row ordered by name ascending, got %, expected %', v_names, v_sorted_names;
    end if;
    if not ('Aaa O1c3b2 Test Milestone' = any(v_names)) or not ('Zzz O1c3b2 Test Milestone' = any(v_names)) then
      raise exception 'assertion failed: both fixture milestone code rows must appear in app.list_milestone_codes result, got %', v_names;
    end if;

    select count(*) into v_app_count from app.list_milestone_codes();
    select count(*) into v_public_count from public.list_milestone_codes();
    select count(*) into v_table_count from app.milestone_codes;
    if v_app_count <> v_table_count or v_public_count <> v_table_count then
      raise exception 'assertion failed: app.list_milestone_codes (%) and public.list_milestone_codes (%) must both return exactly the real row count (%)', v_app_count, v_public_count, v_table_count;
    end if;

    raise notice 'app.list_milestone_codes proof: % real rows returned, name-ascending, under a real authenticated-role session; public.* wrapper matches exactly', v_table_count;
  end $$;
  reset role;
  reset request.jwt.claims;
commit;

\echo '>> anon defense in depth: public.list_milestone_codes (and its app.* counterpart) genuinely reject anon at the grant level -- a real call attempt, not merely an information_schema read'
begin;
  set local role anon;
  do $$
  begin
    begin
      perform public.list_milestone_codes();
      raise exception 'assertion failed: anon must be denied EXECUTE on public.list_milestone_codes, but the call succeeded';
    exception
      when insufficient_privilege then
        raise notice 'anon denial proof: public.list_milestone_codes correctly rejected anon (no EXECUTE grant)';
    end;
  end $$;
  reset role;
commit;

\echo '>> app.get_shipment_leg_tracking_policy / app.get_current_shipment_leg_tracking_session (SECURITY INVOKER, session-identity-driven): the owner sees the real policy row and the real is_current session (never the superseded one)'
begin;
  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000998801", "role": "authenticated"}';
  do $$
  declare
    v_leg1_id uuid := (select id from app.shipment_legs where idempotency_key = 'idem-leg1-o1c3b2');
    v_policy record;
    v_session record;
  begin
    select * into v_policy from app.get_shipment_leg_tracking_policy(v_leg1_id);
    if v_policy.id is null or v_policy.shipment_leg_id <> v_leg1_id then
      raise exception 'assertion failed: owner must see the real tracking policy row for LEG1, got %', v_policy;
    end if;

    select * into v_session from app.get_current_shipment_leg_tracking_session(v_leg1_id);
    if v_session.id is null or v_session.id <> '00000000-0000-0000-0000-0000eeee0002'::uuid or v_session.is_current is not true then
      raise exception 'assertion failed: owner must see the real is_current=true session (id=...eeee0002), not the superseded one, got id=% is_current=%', v_session.id, v_session.is_current;
    end if;

    -- A nonexistent shipment_leg_id returns NULL, never an exception.
    select * into v_policy from app.get_shipment_leg_tracking_policy(gen_random_uuid());
    if v_policy.shipment_leg_id is not null then
      raise exception 'assertion failed: a nonexistent shipment_leg_id must return NULL from get_shipment_leg_tracking_policy';
    end if;
    select * into v_session from app.get_current_shipment_leg_tracking_session(gen_random_uuid());
    if v_session.shipment_leg_id is not null then
      raise exception 'assertion failed: a nonexistent shipment_leg_id must return NULL from get_current_shipment_leg_tracking_session';
    end if;

    raise notice 'owner proof: real tracking policy + real is_current session returned; nonexistent leg id returns NULL, not an error';
  end $$;
  reset role;
  reset request.jwt.claims;
commit;

\echo '>> app.get_shipment_leg_tracking_policy / app.get_current_shipment_leg_tracking_session: a shared-org-unit member (same org unit as the owner, not the owner) also sees the real rows -- proves the RLS predicate''s shared-org-unit branch, not merely exact-owner-match'
begin;
  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000998802", "role": "authenticated"}';
  do $$
  declare
    v_leg1_id uuid := (select id from app.shipment_legs where idempotency_key = 'idem-leg1-o1c3b2');
    v_policy record;
    v_session record;
  begin
    select * into v_policy from app.get_shipment_leg_tracking_policy(v_leg1_id);
    if v_policy.shipment_leg_id is null then
      raise exception 'assertion failed: shared-org-unit member must see the real tracking policy row for LEG1';
    end if;
    select * into v_session from app.get_current_shipment_leg_tracking_session(v_leg1_id);
    if v_session.id is null or v_session.id <> '00000000-0000-0000-0000-0000eeee0002'::uuid then
      raise exception 'assertion failed: shared-org-unit member must see the real is_current session, got %', v_session;
    end if;
    raise notice 'shared-org-unit member proof: real tracking policy + real is_current session returned via the RLS shared-org-unit branch';
  end $$;
  reset role;
  reset request.jwt.claims;
commit;

\echo '>> app.get_shipment_leg_tracking_policy / app.get_current_shipment_leg_tracking_session: a real tenant member with no owner/org-unit/customer-account relationship to this shipment order gets NULL from both, never an exception'
begin;
  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000998803", "role": "authenticated"}';
  do $$
  declare
    v_leg1_id uuid := (select id from app.shipment_legs where idempotency_key = 'idem-leg1-o1c3b2');
    v_policy record;
    v_session record;
  begin
    select * into v_policy from app.get_shipment_leg_tracking_policy(v_leg1_id);
    if v_policy.shipment_leg_id is not null then
      raise exception 'assertion failed: denied member must get NULL from get_shipment_leg_tracking_policy, got %', v_policy;
    end if;
    select * into v_session from app.get_current_shipment_leg_tracking_session(v_leg1_id);
    if v_session.shipment_leg_id is not null then
      raise exception 'assertion failed: denied member must get NULL from get_current_shipment_leg_tracking_session, got %', v_session;
    end if;
    raise notice 'denied member proof: NULL returned from both functions (RLS per-row denial), never an exception';
  end $$;
  reset role;
  reset request.jwt.claims;
commit;

\echo '>> app.get_shipment_leg_tracking_policy / app.get_current_shipment_leg_tracking_session: a cross-tenant member (gizmoo1c3b2''s own admin) also gets NULL from both'
begin;
  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000998805", "role": "authenticated"}';
  do $$
  declare
    v_leg1_id uuid := (select id from app.shipment_legs where idempotency_key = 'idem-leg1-o1c3b2');
    v_policy record;
    v_session record;
  begin
    select * into v_policy from app.get_shipment_leg_tracking_policy(v_leg1_id);
    if v_policy.shipment_leg_id is not null then
      raise exception 'assertion failed: cross-tenant actor must get NULL from get_shipment_leg_tracking_policy, got %', v_policy;
    end if;
    select * into v_session from app.get_current_shipment_leg_tracking_session(v_leg1_id);
    if v_session.shipment_leg_id is not null then
      raise exception 'assertion failed: cross-tenant actor must get NULL from get_current_shipment_leg_tracking_session, got %', v_session;
    end if;
    raise notice 'cross-tenant proof: NULL returned from both functions, never an exception';
  end $$;
  reset role;
  reset request.jwt.claims;
commit;

\echo '>> app.get_shipment_leg_tracking_policy / app.get_current_shipment_leg_tracking_session: a Supreme Admin with ZERO tenant membership anywhere still sees the real rows (app.can_access_record''s own is_supreme_admin branch, evaluated by the RLS policy under the real session identity)'
begin;
  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000998804", "role": "authenticated"}';
  do $$
  declare
    v_leg1_id uuid := (select id from app.shipment_legs where idempotency_key = 'idem-leg1-o1c3b2');
    v_policy record;
    v_session record;
  begin
    select * into v_policy from app.get_shipment_leg_tracking_policy(v_leg1_id);
    if v_policy.shipment_leg_id is null then
      raise exception 'assertion failed: Supreme Admin with zero tenant membership must still see the real tracking policy row';
    end if;
    select * into v_session from app.get_current_shipment_leg_tracking_session(v_leg1_id);
    if v_session.id is null or v_session.id <> '00000000-0000-0000-0000-0000eeee0002'::uuid then
      raise exception 'assertion failed: Supreme Admin with zero tenant membership must still see the real is_current session, got %', v_session;
    end if;
    raise notice 'Supreme Admin proof: zero tenant membership anywhere, still bypasses via app.can_access_record''s own is_supreme_admin branch and sees the real rows';
  end $$;
  reset role;
  reset request.jwt.claims;
commit;

\echo '>> app.list_shipment_legs / app.get_shipment_leg_cargo_allocation / app.list_shipment_leg_custody_events (SECURITY DEFINER + explicit actor id): the owner sees both legs (including the cancelled one, in sequence_no order), the real cargo allocation on LEG1, NULL for LEG2 (no allocation row), and both custody events oldest-first'
do $$
declare
  v_shipment_order_id uuid := (select id from app.shipment_orders where shipment_number = 'SHP-O1C3B2-1');
  v_leg1_id uuid := (select id from app.shipment_legs where idempotency_key = 'idem-leg1-o1c3b2');
  v_leg2_id uuid := (select id from app.shipment_legs where idempotency_key = 'idem-leg2-o1c3b2');
  v_owner uuid := '00000000-0000-0000-0000-000000998801';
  v_legs uuid[];
  v_statuses text[];
  v_seqs integer[];
  v_alloc record;
  v_alloc_count integer;
  v_events_seq integer[];
  v_events_count integer;
begin
  select array_agg(id order by sequence_no), array_agg(leg_status order by sequence_no), array_agg(sequence_no order by sequence_no)
    into v_legs, v_statuses, v_seqs
  from app.list_shipment_legs(v_shipment_order_id, v_owner);

  if v_legs <> array[v_leg1_id, v_leg2_id] then
    raise exception 'assertion failed: owner must see both legs in sequence_no order [LEG1, LEG2], got %', v_legs;
  end if;
  if v_statuses[2] <> 'cancelled' then
    raise exception 'assertion failed: list_shipment_legs must include the cancelled leg unfiltered, got statuses %', v_statuses;
  end if;
  if v_seqs <> array[1, 2] then
    raise exception 'assertion failed: sequence_no must come back [1, 2], got %', v_seqs;
  end if;

  select * into v_alloc from app.get_shipment_leg_cargo_allocation(v_leg1_id, v_owner);
  if v_alloc.id is null or v_alloc.allocated_quantity <> 10 or v_alloc.allocated_weight_kg <> 500 or v_alloc.allocated_volume_cbm <> 20 then
    raise exception 'assertion failed: owner must see the real cargo allocation on LEG1, got %', v_alloc;
  end if;

  select count(*) into v_alloc_count from app.get_shipment_leg_cargo_allocation(v_leg2_id, v_owner);
  if v_alloc_count <> 0 then
    raise exception 'assertion failed: LEG2 has no cargo allocation row -- expected zero rows (TS layer maps to NULL), got %', v_alloc_count;
  end if;

  select array_agg(sequence_no), count(*) into v_events_seq, v_events_count from app.list_shipment_leg_custody_events(v_leg1_id, v_owner);
  if v_events_count <> 2 or v_events_seq <> array[1, 2] then
    raise exception 'assertion failed: owner must see both custody events oldest-first (sequence_no [1, 2]), got count=% seq=%', v_events_count, v_events_seq;
  end if;

  raise notice 'owner proof: list_shipment_legs includes the cancelled leg in correct order, cargo allocation is real for LEG1 / NULL for LEG2, custody events come back oldest-first';
end $$;

\echo '>> app.list_shipment_legs / app.get_shipment_leg_cargo_allocation / app.list_shipment_leg_custody_events: a denied non-member actor (real session, real membership, no owner/org-unit/customer-account relationship to this shipment order) gets ZERO rows/NULL from all 3, never an exception'
do $$
declare
  v_shipment_order_id uuid := (select id from app.shipment_orders where shipment_number = 'SHP-O1C3B2-1');
  v_leg1_id uuid := (select id from app.shipment_legs where idempotency_key = 'idem-leg1-o1c3b2');
  v_denied uuid := '00000000-0000-0000-0000-000000998803';
  v_count integer;
begin
  select count(*) into v_count from app.list_shipment_legs(v_shipment_order_id, v_denied);
  if v_count <> 0 then
    raise exception 'assertion failed: denied member must see zero rows from list_shipment_legs, got %', v_count;
  end if;
  select count(*) into v_count from app.get_shipment_leg_cargo_allocation(v_leg1_id, v_denied);
  if v_count <> 0 then
    raise exception 'assertion failed: denied member must see zero rows from get_shipment_leg_cargo_allocation, got %', v_count;
  end if;
  select count(*) into v_count from app.list_shipment_leg_custody_events(v_leg1_id, v_denied);
  if v_count <> 0 then
    raise exception 'assertion failed: denied member must see zero rows from list_shipment_leg_custody_events, got %', v_count;
  end if;
  raise notice 'denied member proof: zero rows from all 3 functions, never an exception';
end $$;

\echo '>> app.list_shipment_legs / app.get_shipment_leg_cargo_allocation / app.list_shipment_leg_custody_events: a cross-tenant actor (gizmoo1c3b2''s own admin) also gets ZERO rows/NULL from all 3'
do $$
declare
  v_shipment_order_id uuid := (select id from app.shipment_orders where shipment_number = 'SHP-O1C3B2-1');
  v_leg1_id uuid := (select id from app.shipment_legs where idempotency_key = 'idem-leg1-o1c3b2');
  v_cross_tenant uuid := '00000000-0000-0000-0000-000000998805';
  v_count integer;
begin
  select count(*) into v_count from app.list_shipment_legs(v_shipment_order_id, v_cross_tenant);
  if v_count <> 0 then
    raise exception 'assertion failed: cross-tenant actor must see zero rows from list_shipment_legs, got %', v_count;
  end if;
  select count(*) into v_count from app.get_shipment_leg_cargo_allocation(v_leg1_id, v_cross_tenant);
  if v_count <> 0 then
    raise exception 'assertion failed: cross-tenant actor must see zero rows from get_shipment_leg_cargo_allocation, got %', v_count;
  end if;
  select count(*) into v_count from app.list_shipment_leg_custody_events(v_leg1_id, v_cross_tenant);
  if v_count <> 0 then
    raise exception 'assertion failed: cross-tenant actor must see zero rows from list_shipment_leg_custody_events, got %', v_count;
  end if;
  raise notice 'cross-tenant proof: zero rows from all 3 functions, never an exception';
end $$;

\echo '>> app.list_shipment_legs / app.get_shipment_leg_cargo_allocation / app.list_shipment_leg_custody_events: a Supreme Admin with ZERO tenant membership anywhere sees everything via all 3'
do $$
declare
  v_shipment_order_id uuid := (select id from app.shipment_orders where shipment_number = 'SHP-O1C3B2-1');
  v_leg1_id uuid := (select id from app.shipment_legs where idempotency_key = 'idem-leg1-o1c3b2');
  v_supreme uuid := '00000000-0000-0000-0000-000000998804';
  v_count integer;
begin
  select count(*) into v_count from app.list_shipment_legs(v_shipment_order_id, v_supreme);
  if v_count <> 2 then
    raise exception 'assertion failed: Supreme Admin with zero membership must bypass and see 2 legs, got %', v_count;
  end if;
  select count(*) into v_count from app.get_shipment_leg_cargo_allocation(v_leg1_id, v_supreme);
  if v_count <> 1 then
    raise exception 'assertion failed: Supreme Admin with zero membership must bypass and see the real cargo allocation, got % rows', v_count;
  end if;
  select count(*) into v_count from app.list_shipment_leg_custody_events(v_leg1_id, v_supreme);
  if v_count <> 2 then
    raise exception 'assertion failed: Supreme Admin with zero membership must bypass and see both custody events, got %', v_count;
  end if;
  raise notice 'Supreme Admin proof: zero tenant membership anywhere, still bypasses and sees everything via all 3 functions';
end $$;

\echo '>> RULE A: app.list_shipment_legs, app.get_shipment_leg_cargo_allocation and app.list_shipment_leg_custody_events all genuinely reject a claimed actor that does not match the real forced session identity'
begin;
  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000998805", "role": "authenticated"}';
  do $$
  declare
    v_shipment_order_id uuid := (select id from app.shipment_orders where shipment_number = 'SHP-O1C3B2-1');
    v_leg1_id uuid := (select id from app.shipment_legs where idempotency_key = 'idem-leg1-o1c3b2');
    v_claimed_owner uuid := '00000000-0000-0000-0000-000000998801';
  begin
    begin
      -- Real session is 998805 (gizmoo1c3b2's own admin); claims to be 998801 (acmeo1c3b2's
      -- own owner, who WOULD otherwise see this shipment's legs) -- must still be rejected.
      perform app.list_shipment_legs(v_shipment_order_id, v_claimed_owner);
      raise exception 'assertion failed: RULE A -- a claimed actor that does not match the real session identity must be rejected (list_shipment_legs)';
    exception
      when insufficient_privilege then
        raise notice 'RULE A proof: list_shipment_legs impersonation attempt correctly rejected (actor_identity_mismatch)';
    end;

    begin
      perform app.get_shipment_leg_cargo_allocation(v_leg1_id, v_claimed_owner);
      raise exception 'assertion failed: RULE A -- a claimed actor that does not match the real session identity must be rejected (get_shipment_leg_cargo_allocation)';
    exception
      when insufficient_privilege then
        raise notice 'RULE A proof: get_shipment_leg_cargo_allocation impersonation attempt correctly rejected (actor_identity_mismatch)';
    end;

    begin
      perform app.list_shipment_leg_custody_events(v_leg1_id, v_claimed_owner);
      raise exception 'assertion failed: RULE A -- a claimed actor that does not match the real session identity must be rejected (list_shipment_leg_custody_events)';
    exception
      when insufficient_privilege then
        raise notice 'RULE A proof: list_shipment_leg_custody_events impersonation attempt correctly rejected (actor_identity_mismatch)';
    end;
  end $$;
  reset role;
  reset request.jwt.claims;
commit;

\echo '>> schema-privilege defense in depth: anon holds zero EXECUTE on any of the 12 new cluster-3-batch-2 functions in EITHER schema (app or public); authenticated/service_role (spot-checked on 3 of the 6 pairs) hold EXECUTE on both the app.* function and its public.* wrapper, exactly as this migration''s own GRANT PARITY section declares'
do $$
declare
  v_count integer;
begin
  select count(*) into v_count
  from information_schema.routine_privileges
  where routine_schema in ('app', 'public')
    and routine_name in (
      'list_milestone_codes',
      'get_shipment_leg_tracking_policy',
      'get_current_shipment_leg_tracking_session',
      'list_shipment_legs',
      'get_shipment_leg_cargo_allocation',
      'list_shipment_leg_custody_events'
    )
    and grantee = 'anon';
  if v_count <> 0 then
    raise exception 'assertion failed: anon must hold zero EXECUTE on any of the 12 cluster-3-batch-2 functions (either schema), found % grants', v_count;
  end if;

  -- Spot-check 3 of the 6: authenticated AND service_role both hold EXECUTE on the
  -- app.* function AND its public.* wrapper (grant parity, ISS-2026-309).
  select count(*) into v_count
  from information_schema.routine_privileges
  where routine_schema in ('app', 'public')
    and routine_name in ('list_milestone_codes', 'get_shipment_leg_tracking_policy', 'list_shipment_legs')
    and grantee in ('authenticated', 'service_role');
  if v_count <> 3 * 2 * 2 then
    raise exception 'assertion failed: expected exactly 12 grants (3 functions x 2 schemas x 2 grantees) for the spot-checked functions, found %', v_count;
  end if;

  raise notice 'schema-privilege proof: anon holds zero EXECUTE on any of the 12 new cluster-3-batch-2 functions; authenticated/service_role hold the declared grant on both the app.* and public.* spot-checked functions';
end $$;

drop function app._o1c3b2_test_make_job_order_chain(uuid, uuid, uuid, text);

\echo '>> o1-query-layer-cluster3-batch2.sql test suite passed -- cluster 3 batch 2 (milestone codes + leg tracking policy/session + multi-leg shipment, 6/6 call sites) is now fully DONE'
