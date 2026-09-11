-- Real, executable test evidence for CG-AUDIT-2026-09-02 O1-query-layer, cluster 3
-- (operations-tms-core) batch 4 of 4 -- the FINAL batch of cluster 3
-- (supabase/migrations/20260911040000_close_o1_query_layer_cluster3_batch4_shipment_order_capacity_exceptions.sql).
--
-- Proves, against a real disposable database, that all 7 new function pairs (14
-- functions total -- ALL SECURITY INVOKER with ZERO actor parameter) return exactly
-- what their own comments and this migration's own header claim, across the TWO
-- distinct authority shapes the migration itself calls out:
--
--   PART 1 (app.shipment_orders / app.shipment_mode_profiles -- app.can_access_record,
--   directly for shipment_orders and via a one-hop exists-join for
--   shipment_mode_profiles):
--     * app.get_shipment_order / app.list_shipment_orders_for_job_order /
--       app.list_shipment_orders / app.get_shipment_mode_profile all return the real
--       rows an owner or a shared-org-unit member (same org unit, not the owner) can
--       see; a real same-tenant member with no owner/org-unit relationship to the
--       fixture, and a cross-tenant member, both get zero rows, never an exception; a
--       Supreme Admin with ZERO tenant membership anywhere still sees the real rows
--       (app.can_access_record's own is_supreme_admin branch).
--     * app.get_shipment_order and app.get_shipment_mode_profile, the two 0-or-1-row
--       lookups this migration's own header singles out for the SETOF-vs-BARE-COMPOSITE
--       defect class: a nonexistent id (resp. a real shipment order with no mode
--       profile set yet) comes back as a GENUINELY EMPTY result -- count(*)=0 AND no
--       row at all via exists() -- never one row of all-NULL columns.
--     * Ordering fidelity: list_shipment_orders_for_job_order (created_at desc) and
--       list_shipment_orders (created_at desc, id desc) both come back in the
--       documented order, with no extra ORDER BY added at the call site; a job order
--       with zero shipment orders returns zero rows.
--     * app.list_shipment_orders' own pagination: page 1/page 2 split a 3-row fixture
--       correctly with an identical total_count on every row of every page; an
--       out-of-range page returns zero rows (so total_count is then unreadable --
--       this migration's own disclosed characteristic, not a bug); a page_size far
--       over the 100 clamp neither errors nor returns more than 100 rows.
--
--   PART 2 (app.vehicle_capacity_reservations -- tenant-membership RLS shape, NOT
--   can_access_record; and app.exceptions_directory -- a VIEW with its own
--   self-contained can_access_record + cost-masking WHERE clause):
--     * app.list_capacity_reservations_for_leg / app.list_active_capacity_
--       reservations_for_vehicle: a real ACTIVE TENANT MEMBER with NO owner/org-unit
--       relationship to anything (the exact identity PART 1 above calls "denied") DOES
--       see these rows -- this table's RLS predicate is
--       `(has_active_tenant_membership AND NOT actor_holds_customer_user_layer) OR
--       is_supreme_admin()`, deliberately not owner/org-unit-scoped -- while a
--       customer_user-layer principal in the SAME tenant is denied, a cross-tenant
--       member is denied, and a Supreme Admin with zero membership still sees the
--       rows. app.list_active_capacity_reservations_for_vehicle's own status filter
--       (held/consumed included, released excluded) and its window_start-ascending
--       order are both proven against fixture rows that would fail both checks under
--       a naive read.
--     * app.list_shipment_exceptions: can_access_record-based visibility (owner and
--       shared-org-unit member see it, a denied same-tenant member and a cross-tenant
--       member do not, Supreme Admin does) IDENTICAL in shape to PART 1 (this view
--       joins back to app.shipment_orders for its own scoping) plus the OPS:View cost
--       field-masking behavior: internal_notes/damage_loss_details/claim_amount/
--       claim_currency are real for a caller holding OPS:View cost and null
--       (sensitive_masked=true) for a caller who can see the row but lacks that
--       permission -- and a Supreme Admin with NO explicit grant at all still sees the
--       real values via app.evaluate_permission's own supreme_admin_exception branch.
--       Ordering fidelity (created_at desc) is proven the same way as PART 1.
--
-- Also confirms schema-privilege defense in depth: anon holds zero EXECUTE on any of
-- the 14 new functions in EITHER schema -- a real call attempt against every one of
-- the 7 public.* wrappers, not merely an information_schema read -- and (spot-checked
-- on 3 pairs) authenticated/service_role hold EXECUTE on both the app.* function and
-- its public.* wrapper, exactly as this migration's own GRANT PARITY section
-- declares. A service_role (BYPASSRLS) smoke check is run against 3 of the PART
-- 1/PART 2A functions (both app.* and public.*), which sit on real RLS-policy-bearing
-- tables that BYPASSRLS genuinely bypasses; app.list_shipment_exceptions is
-- deliberately NOT included in that smoke check -- app.exceptions_directory's own
-- row-visibility WHERE clause is keyed on auth.uid() directly (not RLS), and
-- service_role's session here carries no request.jwt.claims at all, so auth.uid() is
-- null and the view would report zero rows regardless of BYPASSRLS -- exactly the
-- AUTHORITY SHAPE 2 distinction this migration's own header draws out, not a gap in
-- this test file.

\set ON_ERROR_STOP on

\echo '>> setup: tenant acmeo1c3b4 with an owner (org_user), a shared-org-unit member (same org unit, not the owner), a real active tenant member with NO owner/org-unit/customer relationship to anything (denied under can_access_record, but a valid tenant-membership-shape member for PART 2A), a customer_user-layer principal, a bootstrap tenant_admin (role-grant plumbing only), a global Supreme Admin with NO membership in this tenant, and a second isolated tenant gizmoo1c3b4 with its own admin'
do $$
declare
  v_tenant_id uuid;
  v_other_tenant_id uuid;
  v_org_unit_id uuid;
begin
  insert into auth.users (id, email) values
    ('00000000-0000-0000-0000-000000999001', 'ownero1c3b4@example.test'),
    ('00000000-0000-0000-0000-000000999002', 'sharedvieweramo1c3b4@example.test'),
    ('00000000-0000-0000-0000-000000999003', 'tenantonlymembero1c3b4@example.test'),
    ('00000000-0000-0000-0000-000000999004', 'supremeo1c3b4@example.test'),
    ('00000000-0000-0000-0000-000000999005', 'othertenanto1c3b4@example.test'),
    ('00000000-0000-0000-0000-000000999006', 'customerusero1c3b4@example.test'),
    ('00000000-0000-0000-0000-000000999007', 'bootstrapadmino1c3b4@example.test');

  perform app.provision_tenant('acmeo1c3b4', 'Acme O1C3B4 Co', 'idem-acmeo1c3b4', 'tester');
  v_tenant_id := (select id from app.tenants where slug = 'acmeo1c3b4');
  perform app.transition_tenant_status(v_tenant_id, 'active', 'setup', 'tester');
  perform app.create_org_unit(v_tenant_id, 'company', null, 'ACMEO1C3B4-CO', 'Acme O1C3B4 Co', 'tester');
  v_org_unit_id := (select id from app.org_units where tenant_id = v_tenant_id and code = 'ACMEO1C3B4-CO');

  perform app.invite_user(v_tenant_id, '00000000-0000-0000-0000-000000999001', 'ownero1c3b4@example.test', 'Owner', v_org_unit_id, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'ownero1c3b4@example.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000999001', 'org_user', v_tenant_id, null, 'tester');

  -- Same org_unit_id as the owner -- app.can_access_record's shared-org-unit branch
  -- admits this identity to every row owned by 999001 in this org unit, without being
  -- the owner itself.
  perform app.invite_user(v_tenant_id, '00000000-0000-0000-0000-000000999002', 'sharedvieweramo1c3b4@example.test', 'Shared Viewer', v_org_unit_id, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'sharedvieweramo1c3b4@example.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000999002', 'org_user', v_tenant_id, null, 'tester');

  -- A real, ACTIVE org_user member of the SAME tenant, but no org_unit (so the
  -- shared-org-unit branch never matches) and not the owner of anything -- the exact
  -- per-row denial app.can_access_record's own coalesce(..., false) is meant to
  -- produce for PART 1/PART 2B (owner/org-unit-scoped tables), and simultaneously the
  -- exact identity that PROVES PART 2A's different, tenant-membership-only RLS shape
  -- admits someone can_access_record would deny.
  perform app.invite_user(v_tenant_id, '00000000-0000-0000-0000-000000999003', 'tenantonlymembero1c3b4@example.test', 'Tenant-Only Member', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'tenantonlymembero1c3b4@example.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000999003', 'org_user', v_tenant_id, null, 'tester');

  perform app.grant_principal_membership('00000000-0000-0000-0000-000000999004', 'supreme_admin', null, null, 'tester');

  -- A bootstrap tenant_admin -- role-grant plumbing only (app.assign_role's own actor
  -- audit label), never itself used as a test persona below.
  perform app.invite_user(v_tenant_id, '00000000-0000-0000-0000-000000999007', 'bootstrapadmino1c3b4@example.test', 'Bootstrap Admin', v_org_unit_id, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'bootstrapadmino1c3b4@example.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000999007', 'tenant_admin', v_tenant_id, null, 'tester');

  -- Customer-portal-layer principal (ATW-023 shape, PART 2A's own denial case): an
  -- active app.tenant_user_identities linkage plus an active customer_user
  -- app.principal_memberships row, granted directly (no app.users profile at all --
  -- a customer_user-layer identity never gets one), mirroring
  -- scripts/db-tests/o1-query-layer-cluster0-batch3.sql's own established pattern for
  -- this exact identity shape.
  perform app.link_auth_identity('00000000-0000-0000-0000-000000999006', v_tenant_id, 'tester', 'active');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000999006', 'customer_user', v_tenant_id, 'fake-account-ref-o1c3b4', 'tester');

  perform app.provision_tenant('gizmoo1c3b4', 'Gizmo O1C3B4 Co', 'idem-gizmoo1c3b4', 'tester');
  v_other_tenant_id := (select id from app.tenants where slug = 'gizmoo1c3b4');
  perform app.transition_tenant_status(v_other_tenant_id, 'active', 'setup', 'tester');
  perform app.invite_user(v_other_tenant_id, '00000000-0000-0000-0000-000000999005', 'othertenanto1c3b4@example.test', 'Other Tenant Admin', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'othertenanto1c3b4@example.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000999005', 'tenant_admin', v_other_tenant_id, null, 'tester');
end $$;

-- A plain, top-level, temporary test helper -- mirrors cluster 3 batch 1/2/3's own
-- job-order-chain helpers, trimmed to just what a Shipment Order needs
-- (app.shipment_orders.job_order_id is NOT NULL): the
-- lead->prospect->opportunity->quotation->job_order_handoff->job_order chain, real
-- rows throughout, never a raw shortcut into app.job_orders alone.
create function app._o1c3b4_test_make_job_order_chain(p_tenant uuid, p_org_unit uuid, p_owner uuid, p_tag text)
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
  values (gen_random_uuid(), p_tenant, p_tag || ' Account', 'fp-o1c3b4-' || p_tag || '-account', 'active', 'tester')
  returning id into v_account;

  insert into app.leads (id, tenant_id, source, contact_name, email, duplicate_fingerprint, status, created_by)
  values (gen_random_uuid(), p_tenant, 'referral', p_tag || ' Lead', p_tag || '-lead@o1c3b4.test', 'fp-o1c3b4-' || p_tag || '-lead', 'qualified', 'tester')
  returning id into v_lead;
  insert into app.prospects (id, tenant_id, lead_id, legal_name, duplicate_fingerprint, contact_name, status, created_by)
  values (gen_random_uuid(), p_tenant, v_lead, p_tag || ' Prospect Co', 'fp-o1c3b4-' || p_tag || '-prospect', p_tag || ' Contact', 'active', 'tester')
  returning id into v_prospect;
  insert into app.opportunities (id, tenant_id, prospect_id, name, stage, created_by)
  values (gen_random_uuid(), p_tenant, v_prospect, p_tag || ' Opportunity', 'ready_for_costing', 'tester')
  returning id into v_opportunity;
  v_quotation := gen_random_uuid();
  insert into app.quotations (id, tenant_id, quote_number, opportunity_id, source_opportunity_version, prospect_id, currency, validity_to, status, root_quotation_id, created_by)
  values (v_quotation, p_tenant, 'QUO-O1C3B4-' || p_tag, v_opportunity, 1, v_prospect, 'USD', now() + interval '30 days', 'submitted', v_quotation, 'tester');
  insert into app.job_order_handoffs (id, tenant_id, quotation_id, account_id, payload, payload_hash, prepared_by_auth_user_id, owner_user_id, org_unit_id, created_by)
  values (gen_random_uuid(), p_tenant, v_quotation, v_account, jsonb_build_object('note', 'o1c3b4 handoff ' || p_tag), 'hash-o1c3b4-' || p_tag, p_owner, p_owner, p_org_unit, 'tester')
  returning id into v_handoff;
  insert into app.job_orders (
    id, tenant_id, job_number, source_handoff_id, quotation_id, account_id,
    customer_snapshot, cargo_service_snapshot, revenue_snapshot, contract_snapshot,
    credit_snapshot, acceptance_snapshot, status, owner_user_id, org_unit_id, created_by
  ) values (
    gen_random_uuid(), p_tenant, 'JOB-O1C3B4-' || p_tag, v_handoff, v_quotation, v_account,
    jsonb_build_object('legalName', p_tag || ' Account'), '{}'::jsonb,
    jsonb_build_object('totalAmount', 1000000, 'currency', 'IDR'), '{}'::jsonb,
    jsonb_build_object('creditTermsDays', 30), '{}'::jsonb,
    'confirmed', p_owner, p_org_unit, 'tester'
  )
  returning id into v_job_order;

  return query select v_job_order, v_handoff, v_quotation, v_account;
end;
$$;

\echo '>> fixture (PART 1): Job Order JOB-O1C3B4-A (owned by 999001) with 3 Shipment Orders inserted with explicit created_at OUT of their eventual desc order of insertion relevance -- SHP-O1C3B4-A1 (oldest, now()-5d, carries the one sea-mode shipment_mode_profile), SHP-O1C3B4-A2 (now()-4d, no profile), SHP-O1C3B4-A3 (newest, now()-3d, no profile -- the "no profile yet" fixture for get_shipment_mode_profile); and Job Order JOB-O1C3B4-B (also owned by 999001) with ZERO Shipment Orders -- the "job order with nothing under it" fixture for list_shipment_orders_for_job_order'
do $$
declare
  v_tenant_id uuid := (select id from app.tenants where slug = 'acmeo1c3b4');
  v_org_unit_id uuid := (select id from app.org_units where tenant_id = v_tenant_id and code = 'ACMEO1C3B4-CO');
  v_chain record;
  v_shipment_a1 uuid;
begin
  select * into v_chain from app._o1c3b4_test_make_job_order_chain(v_tenant_id, v_org_unit_id, '00000000-0000-0000-0000-000000999001', 'A');

  insert into app.shipment_orders (
    id, tenant_id, job_order_id, shipment_number, idempotency_key, status, shipper_account_id,
    consignee_snapshot, cargo_service_snapshot, service_type, mode, origin, destination,
    planned_pickup_at, owner_user_id, org_unit_id, created_by, created_at, updated_at
  ) values (
    gen_random_uuid(), v_tenant_id, v_chain.job_order_id, 'SHP-O1C3B4-A1', 'idem-shp-o1c3b4-a1', 'confirmed', v_chain.account_id,
    '{}'::jsonb, '{}'::jsonb, 'FCL', 'sea', 'Jakarta', 'Surabaya',
    now() + interval '1 day', '00000000-0000-0000-0000-000000999001', v_org_unit_id, 'tester', now() - interval '5 days', now() - interval '5 days'
  ) returning id into v_shipment_a1;

  insert into app.shipment_orders (
    id, tenant_id, job_order_id, shipment_number, idempotency_key, status, shipper_account_id,
    consignee_snapshot, cargo_service_snapshot, service_type, mode, origin, destination,
    planned_pickup_at, owner_user_id, org_unit_id, created_by, created_at, updated_at
  ) values (
    gen_random_uuid(), v_tenant_id, v_chain.job_order_id, 'SHP-O1C3B4-A2', 'idem-shp-o1c3b4-a2', 'confirmed', v_chain.account_id,
    '{}'::jsonb, '{}'::jsonb, 'LCL', 'land', 'Jakarta', 'Bandung',
    now() + interval '2 days', '00000000-0000-0000-0000-000000999001', v_org_unit_id, 'tester', now() - interval '4 days', now() - interval '4 days'
  );

  insert into app.shipment_orders (
    id, tenant_id, job_order_id, shipment_number, idempotency_key, status, shipper_account_id,
    consignee_snapshot, cargo_service_snapshot, service_type, mode, origin, destination,
    planned_pickup_at, owner_user_id, org_unit_id, created_by, created_at, updated_at
  ) values (
    gen_random_uuid(), v_tenant_id, v_chain.job_order_id, 'SHP-O1C3B4-A3', 'idem-shp-o1c3b4-a3', 'confirmed', v_chain.account_id,
    '{}'::jsonb, '{}'::jsonb, 'LCL', 'land', 'Jakarta', 'Semarang',
    now() + interval '3 days', '00000000-0000-0000-0000-000000999001', v_org_unit_id, 'tester', now() - interval '3 days', now() - interval '3 days'
  );

  insert into app.shipment_mode_profiles (
    id, tenant_id, shipment_order_id, mode,
    sea_bl_number, sea_booking_number, sea_vessel_name, sea_origin_port, sea_destination_port,
    created_by
  ) values (
    gen_random_uuid(), v_tenant_id, v_shipment_a1, 'sea',
    'BL-O1C3B4-A1', 'BKG-O1C3B4-A1', 'MV O1C3B4', 'IDJKT', 'IDSUB',
    'tester'
  );

  -- JOB-O1C3B4-B: a second, real job order chain with ZERO shipment orders under it.
  perform app._o1c3b4_test_make_job_order_chain(v_tenant_id, v_org_unit_id, '00000000-0000-0000-0000-000000999001', 'B');
end $$;

\echo '>> owner session (999001): app.list_shipment_orders_for_job_order(JOB-A) comes back [A3, A2, A1] (created_at desc); JOB-B (zero shipment orders) returns zero rows; app.get_shipment_order resolves A1 and returns a GENUINELY EMPTY result (count=0, no row at all) for a nonexistent id; app.get_shipment_mode_profile resolves A1''s sea profile and returns a GENUINELY EMPTY result for A3 (no profile set yet); app.list_shipment_orders paginates the 3-row fixture correctly (page1/page2/out-of-range/page_size clamp) with a consistent total_count'
begin;
  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000999001", "role": "authenticated"}';
  do $$
  declare
    v_tenant_id uuid := (select id from app.tenants where slug = 'acmeo1c3b4');
    v_job_a_id uuid := (select id from app.job_orders where job_number = 'JOB-O1C3B4-A');
    v_job_b_id uuid := (select id from app.job_orders where job_number = 'JOB-O1C3B4-B');
    v_shipment_a1_id uuid := (select id from app.shipment_orders where shipment_number = 'SHP-O1C3B4-A1');
    v_shipment_a2_id uuid := (select id from app.shipment_orders where shipment_number = 'SHP-O1C3B4-A2');
    v_shipment_a3_id uuid := (select id from app.shipment_orders where shipment_number = 'SHP-O1C3B4-A3');
    v_nonexistent uuid := gen_random_uuid();
    v_ids uuid[];
    v_totals bigint[];
    v_row record;
    v_count integer;
  begin
    -- 1. list_shipment_orders_for_job_order: newest-first. No ORDER BY added at the
    -- call site -- genuinely exercises the function body's own `order by created_at
    -- desc`.
    select array_agg(id) into v_ids from app.list_shipment_orders_for_job_order(v_job_a_id);
    if v_ids <> array[v_shipment_a3_id, v_shipment_a2_id, v_shipment_a1_id] then
      raise exception 'assertion failed: list_shipment_orders_for_job_order(JOB-A) must return [A3, A2, A1] (created_at desc), got %', v_ids;
    end if;

    select count(*) into v_count from app.list_shipment_orders_for_job_order(v_job_b_id);
    if v_count <> 0 then
      raise exception 'assertion failed: list_shipment_orders_for_job_order(JOB-B, zero shipment orders) must return zero rows, got %', v_count;
    end if;

    -- 2. get_shipment_order: real row by primary key.
    select * into v_row from app.get_shipment_order(v_shipment_a1_id);
    if v_row.id is null or v_row.id <> v_shipment_a1_id or v_row.shipment_number <> 'SHP-O1C3B4-A1' then
      raise exception 'assertion failed: get_shipment_order(A1) must return the real row, got %', v_row;
    end if;

    -- 2b. get_shipment_order: a nonexistent id is a GENUINELY EMPTY result -- zero
    -- rows, never one row of all-NULL columns (this migration's own
    -- SETOF-vs-BARE-COMPOSITE defect class).
    select count(*) into v_count from app.get_shipment_order(v_nonexistent);
    if v_count <> 0 then
      raise exception 'assertion failed: get_shipment_order(nonexistent) must return zero rows, got %', v_count;
    end if;
    if exists (select 1 from app.get_shipment_order(v_nonexistent)) then
      raise exception 'assertion failed: get_shipment_order(nonexistent) must be a genuinely empty row set, found at least one row';
    end if;

    -- 3. get_shipment_mode_profile: real row for A1 (sea mode).
    select * into v_row from app.get_shipment_mode_profile(v_shipment_a1_id);
    if v_row.id is null or v_row.mode <> 'sea' or v_row.sea_bl_number <> 'BL-O1C3B4-A1' then
      raise exception 'assertion failed: get_shipment_mode_profile(A1) must return the real sea-mode profile, got %', v_row;
    end if;

    -- 3b. get_shipment_mode_profile: A3 has no profile set yet -- a GENUINELY EMPTY
    -- result, never one row of all-NULL columns.
    select count(*) into v_count from app.get_shipment_mode_profile(v_shipment_a3_id);
    if v_count <> 0 then
      raise exception 'assertion failed: get_shipment_mode_profile(A3, no profile yet) must return zero rows, got %', v_count;
    end if;
    if exists (select 1 from app.get_shipment_mode_profile(v_shipment_a3_id)) then
      raise exception 'assertion failed: get_shipment_mode_profile(A3) must be a genuinely empty row set, found at least one row';
    end if;

    -- 4. list_shipment_orders: page 1 of 2 (page_size=2) -> [A3, A2], total_count=3 on
    -- every row. No ORDER BY added at the call site -- genuinely exercises the
    -- function body's own `order by created_at desc, id desc`.
    select array_agg(id), array_agg(total_count) into v_ids, v_totals from app.list_shipment_orders(v_tenant_id, 1, 2);
    if v_ids <> array[v_shipment_a3_id, v_shipment_a2_id] then
      raise exception 'assertion failed: list_shipment_orders(page=1, size=2) must return [A3, A2], got %', v_ids;
    end if;
    if v_totals <> array[3::bigint, 3::bigint] then
      raise exception 'assertion failed: list_shipment_orders(page=1, size=2) must report total_count=3 on every row, got %', v_totals;
    end if;

    -- 4b. page 2 of 2 -> the remaining row [A1], same total_count=3.
    select array_agg(id), array_agg(total_count) into v_ids, v_totals from app.list_shipment_orders(v_tenant_id, 2, 2);
    if v_ids <> array[v_shipment_a1_id] then
      raise exception 'assertion failed: list_shipment_orders(page=2, size=2) must return [A1], got %', v_ids;
    end if;
    if v_totals <> array[3::bigint] then
      raise exception 'assertion failed: list_shipment_orders(page=2, size=2) must report total_count=3, got %', v_totals;
    end if;

    -- 4c. page 3 (out of range for a 3-row fixture at page_size=2) -> zero rows.
    -- total_count is then unreadable (no row to read it off of) -- this migration's
    -- own disclosed characteristic of the count(*) over() idiom, not a bug: it is NOT
    -- asserted here precisely because there is no row to assert it against.
    select count(*) into v_count from app.list_shipment_orders(v_tenant_id, 3, 2);
    if v_count <> 0 then
      raise exception 'assertion failed: list_shipment_orders(page=3, size=2, out of range) must return zero rows, got %', v_count;
    end if;

    -- 4d. page_size far over the server-side clamp (100): must not error, and must
    -- never return more than 100 rows -- here, exactly the 3 real rows (all visible
    -- to the owner), proving the clamp is harmless when the true row count is small.
    select count(*) into v_count from app.list_shipment_orders(v_tenant_id, 1, 500);
    if v_count <> 3 or v_count > 100 then
      raise exception 'assertion failed: list_shipment_orders(page_size=500) must return exactly the 3 real rows (clamped harmlessly, never more than 100), got %', v_count;
    end if;

    raise notice 'owner proof: all 4 PART 1 functions return the expected rows/order; both 0-or-1-row getters return a genuinely empty result (not a row of nulls) on their respective miss case; pagination is correct across page1/page2/out-of-range/oversized-page_size';
  end $$;
  reset role;
  reset request.jwt.claims;
commit;

\echo '>> shared-org-unit viewer session (999002, same org unit as the owner, not the owner): also sees JOB-A''s 3 shipment orders, A1 by id, and A1''s mode profile -- proves the RLS predicate''s shared-org-unit branch, not merely exact-owner-match'
begin;
  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000999002", "role": "authenticated"}';
  do $$
  declare
    v_tenant_id uuid := (select id from app.tenants where slug = 'acmeo1c3b4');
    v_job_a_id uuid := (select id from app.job_orders where job_number = 'JOB-O1C3B4-A');
    v_shipment_a1_id uuid := (select id from app.shipment_orders where shipment_number = 'SHP-O1C3B4-A1');
    v_count integer;
    v_row record;
  begin
    select count(*) into v_count from app.list_shipment_orders_for_job_order(v_job_a_id);
    if v_count <> 3 then
      raise exception 'assertion failed: shared-org-unit viewer must see all 3 shipment orders under JOB-A, got %', v_count;
    end if;

    select * into v_row from app.get_shipment_order(v_shipment_a1_id);
    if v_row.id is null then
      raise exception 'assertion failed: shared-org-unit viewer must see A1 via get_shipment_order';
    end if;

    select * into v_row from app.get_shipment_mode_profile(v_shipment_a1_id);
    if v_row.id is null or v_row.mode <> 'sea' then
      raise exception 'assertion failed: shared-org-unit viewer must see A1''s real mode profile';
    end if;

    select count(*) into v_count from app.list_shipment_orders(v_tenant_id, 1, 50);
    if v_count <> 3 then
      raise exception 'assertion failed: shared-org-unit viewer must see all 3 shipment orders via list_shipment_orders, got %', v_count;
    end if;

    raise notice 'shared-org-unit viewer proof: real shipment orders/mode profile returned via the RLS shared-org-unit branch';
  end $$;
  reset role;
  reset request.jwt.claims;
commit;

\echo '>> tenant-only member session (999003, real acmeo1c3b4 tenant member, no owner/org-unit relationship to anything): zero rows from all 4 PART 1 functions, never an exception -- this is the exact identity PART 2A below proves a DIFFERENT verdict for'
begin;
  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000999003", "role": "authenticated"}';
  do $$
  declare
    v_tenant_id uuid := (select id from app.tenants where slug = 'acmeo1c3b4');
    v_job_a_id uuid := (select id from app.job_orders where job_number = 'JOB-O1C3B4-A');
    v_shipment_a1_id uuid := (select id from app.shipment_orders where shipment_number = 'SHP-O1C3B4-A1');
    v_count integer;
  begin
    select count(*) into v_count from app.list_shipment_orders_for_job_order(v_job_a_id);
    if v_count <> 0 then raise exception 'assertion failed: tenant-only member must see zero rows from list_shipment_orders_for_job_order, got %', v_count; end if;

    select count(*) into v_count from app.get_shipment_order(v_shipment_a1_id);
    if v_count <> 0 then raise exception 'assertion failed: tenant-only member must see zero rows from get_shipment_order, got %', v_count; end if;

    select count(*) into v_count from app.get_shipment_mode_profile(v_shipment_a1_id);
    if v_count <> 0 then raise exception 'assertion failed: tenant-only member must see zero rows from get_shipment_mode_profile, got %', v_count; end if;

    select count(*) into v_count from app.list_shipment_orders(v_tenant_id, 1, 50);
    if v_count <> 0 then raise exception 'assertion failed: tenant-only member must see zero rows from list_shipment_orders, got %', v_count; end if;

    raise notice 'tenant-only member proof: zero rows from all 4 PART 1 functions, never an exception';
  end $$;
  reset role;
  reset request.jwt.claims;
commit;

\echo '>> cross-tenant session (999005, gizmoo1c3b4''s own tenant_admin, no standing in acmeo1c3b4 at all): zero rows from all 4 PART 1 functions'
begin;
  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000999005", "role": "authenticated"}';
  do $$
  declare
    v_tenant_id uuid := (select id from app.tenants where slug = 'acmeo1c3b4');
    v_job_a_id uuid := (select id from app.job_orders where job_number = 'JOB-O1C3B4-A');
    v_shipment_a1_id uuid := (select id from app.shipment_orders where shipment_number = 'SHP-O1C3B4-A1');
    v_count integer;
  begin
    select count(*) into v_count from app.list_shipment_orders_for_job_order(v_job_a_id);
    if v_count <> 0 then raise exception 'assertion failed: cross-tenant actor must see zero rows from list_shipment_orders_for_job_order, got %', v_count; end if;

    select count(*) into v_count from app.get_shipment_order(v_shipment_a1_id);
    if v_count <> 0 then raise exception 'assertion failed: cross-tenant actor must see zero rows from get_shipment_order, got %', v_count; end if;

    select count(*) into v_count from app.get_shipment_mode_profile(v_shipment_a1_id);
    if v_count <> 0 then raise exception 'assertion failed: cross-tenant actor must see zero rows from get_shipment_mode_profile, got %', v_count; end if;

    select count(*) into v_count from app.list_shipment_orders(v_tenant_id, 1, 50);
    if v_count <> 0 then raise exception 'assertion failed: cross-tenant actor must see zero rows from list_shipment_orders, got %', v_count; end if;

    raise notice 'cross-tenant proof: zero rows from all 4 PART 1 functions, never an exception';
  end $$;
  reset role;
  reset request.jwt.claims;
commit;

\echo '>> Supreme Admin session (999004, ZERO tenant membership anywhere): still sees the real rows via app.can_access_record''s own is_supreme_admin branch, evaluated by the RLS policy under the real session identity'
begin;
  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000999004", "role": "authenticated"}';
  do $$
  declare
    v_tenant_id uuid := (select id from app.tenants where slug = 'acmeo1c3b4');
    v_job_a_id uuid := (select id from app.job_orders where job_number = 'JOB-O1C3B4-A');
    v_shipment_a1_id uuid := (select id from app.shipment_orders where shipment_number = 'SHP-O1C3B4-A1');
    v_count integer;
    v_row record;
  begin
    select count(*) into v_count from app.list_shipment_orders_for_job_order(v_job_a_id);
    if v_count <> 3 then
      raise exception 'assertion failed: Supreme Admin with zero membership must bypass and see all 3 shipment orders, got %', v_count;
    end if;

    select * into v_row from app.get_shipment_order(v_shipment_a1_id);
    if v_row.id is null then
      raise exception 'assertion failed: Supreme Admin with zero membership must still reach A1 via get_shipment_order';
    end if;

    select * into v_row from app.get_shipment_mode_profile(v_shipment_a1_id);
    if v_row.id is null then
      raise exception 'assertion failed: Supreme Admin with zero membership must still reach A1''s mode profile via get_shipment_mode_profile';
    end if;

    select count(*) into v_count from app.list_shipment_orders(v_tenant_id, 1, 50);
    if v_count <> 3 then
      raise exception 'assertion failed: Supreme Admin with zero membership must bypass and see all 3 shipment orders via list_shipment_orders, got %', v_count;
    end if;

    raise notice 'Supreme Admin proof: zero tenant membership anywhere, still bypasses via app.can_access_record''s own is_supreme_admin branch and sees the real rows';
  end $$;
  reset role;
  reset request.jwt.claims;
commit;

\echo '>> fixture (PART 2A): one vehicle master record, 3 shipment legs under SHP-O1C3B4-A1, and 4 capacity reservations across them -- LEG-1 carries R1 (released, older) and R2 (held, newer, active), LEG-2 carries R3 (consumed, active), LEG-3 carries R4 (released) -- so list_capacity_reservations_for_leg(LEG-1) must return BOTH R1/R2 (any status), while list_active_capacity_reservations_for_vehicle must return only R2/R3 (held/consumed), excluding R1/R4 (released), ordered by window_start ascending (R3''s window starts before R2''s)'
do $$
declare
  v_tenant_id uuid := (select id from app.tenants where slug = 'acmeo1c3b4');
  v_shipment_a1_id uuid := (select id from app.shipment_orders where shipment_number = 'SHP-O1C3B4-A1');
  v_vehicle_master_id uuid;
  v_leg1 uuid;
  v_leg2 uuid;
  v_leg3 uuid;
begin
  insert into app.master_records (id, master_type_code, tenant_id, code, name, canonical_status, created_by)
  values (gen_random_uuid(), 'vehicle', v_tenant_id, 'VEH-O1C3B4-1', 'O1C3B4 Truck 1', 'active', 'tester')
  returning id into v_vehicle_master_id;

  insert into app.shipment_legs (id, tenant_id, shipment_order_id, sequence_no, idempotency_key, mode, leg_status, created_by)
  values (gen_random_uuid(), v_tenant_id, v_shipment_a1_id, 1, 'idem-leg-o1c3b4-1', 'land', 'planned', 'tester')
  returning id into v_leg1;
  insert into app.shipment_legs (id, tenant_id, shipment_order_id, sequence_no, idempotency_key, mode, leg_status, created_by)
  values (gen_random_uuid(), v_tenant_id, v_shipment_a1_id, 2, 'idem-leg-o1c3b4-2', 'land', 'planned', 'tester')
  returning id into v_leg2;
  insert into app.shipment_legs (id, tenant_id, shipment_order_id, sequence_no, idempotency_key, mode, leg_status, created_by)
  values (gen_random_uuid(), v_tenant_id, v_shipment_a1_id, 3, 'idem-leg-o1c3b4-3', 'land', 'planned', 'tester')
  returning id into v_leg3;

  -- R1: LEG-1, released, older creation -- list_capacity_reservations_for_leg(LEG-1)'s
  -- own "any status" full-history claim depends on this row surviving in that
  -- function's result alongside R2 below.
  insert into app.vehicle_capacity_reservations (id, tenant_id, shipment_leg_id, vehicle_master_id, idempotency_key, window_start, window_end, status, released_reason, created_by, created_at, updated_at)
  values (gen_random_uuid(), v_tenant_id, v_leg1, v_vehicle_master_id, 'idem-res-o1c3b4-1', now() + interval '1 day', now() + interval '2 days', 'released', 'o1c3b4 test release', 'tester', now() - interval '3 hours', now() - interval '3 hours');

  -- R2: LEG-1, held, newer creation, window_start further out than R3 below --
  -- proves list_capacity_reservations_for_leg's own `order by created_at desc`
  -- (R2 must sort before R1) and list_active_capacity_reservations_for_vehicle's own
  -- `order by window_start asc` (R2 must sort AFTER R3).
  insert into app.vehicle_capacity_reservations (id, tenant_id, shipment_leg_id, vehicle_master_id, idempotency_key, window_start, window_end, status, created_by, created_at, updated_at)
  values (gen_random_uuid(), v_tenant_id, v_leg1, v_vehicle_master_id, 'idem-res-o1c3b4-2', now() + interval '4 days', now() + interval '5 days', 'held', 'tester', now() - interval '1 hour', now() - interval '1 hour');

  -- R3: LEG-2, consumed, window_start earlier than R2's.
  insert into app.vehicle_capacity_reservations (id, tenant_id, shipment_leg_id, vehicle_master_id, idempotency_key, window_start, window_end, status, created_by, created_at, updated_at)
  values (gen_random_uuid(), v_tenant_id, v_leg2, v_vehicle_master_id, 'idem-res-o1c3b4-3', now() + interval '2 days', now() + interval '3 days', 'consumed', 'tester', now() - interval '2 hours', now() - interval '2 hours');

  -- R4: LEG-3, released -- must be excluded from list_active_capacity_reservations_for_vehicle
  -- despite a window_start that would otherwise sort between R3 and R2.
  insert into app.vehicle_capacity_reservations (id, tenant_id, shipment_leg_id, vehicle_master_id, idempotency_key, window_start, window_end, status, released_reason, created_by, created_at, updated_at)
  values (gen_random_uuid(), v_tenant_id, v_leg3, v_vehicle_master_id, 'idem-res-o1c3b4-4', now() + interval '3 days', now() + interval '4 days', 'released', 'o1c3b4 test release 2', 'tester', now() - interval '4 hours', now() - interval '4 hours');
end $$;

\echo '>> tenant-only member session (999003, the SAME identity PART 1 above proved is denied everywhere): sees BOTH reservations on LEG-1 (any status) via list_capacity_reservations_for_leg, and sees exactly the 2 active (held/consumed) reservations on the vehicle -- ordered window_start asc, released rows excluded -- proving PART 2A''s tenant-membership RLS shape is genuinely different from PART 1/2B''s owner/org-unit shape'
begin;
  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000999003", "role": "authenticated"}';
  do $$
  declare
    v_leg1_id uuid := (select id from app.shipment_legs where idempotency_key = 'idem-leg-o1c3b4-1');
    v_vehicle_master_id uuid := (select id from app.master_records where code = 'VEH-O1C3B4-1');
    v_res_r1_id uuid := (select id from app.vehicle_capacity_reservations where idempotency_key = 'idem-res-o1c3b4-1');
    v_res_r2_id uuid := (select id from app.vehicle_capacity_reservations where idempotency_key = 'idem-res-o1c3b4-2');
    v_res_r3_id uuid := (select id from app.vehicle_capacity_reservations where idempotency_key = 'idem-res-o1c3b4-3');
    v_ids uuid[];
  begin
    -- list_capacity_reservations_for_leg(LEG-1): any status, newest-created first --
    -- [R2, R1]. No ORDER BY added at the call site.
    select array_agg(id) into v_ids from app.list_capacity_reservations_for_leg(v_leg1_id);
    if v_ids <> array[v_res_r2_id, v_res_r1_id] then
      raise exception 'assertion failed: list_capacity_reservations_for_leg(LEG-1) must return [R2, R1] (created_at desc, any status), got %', v_ids;
    end if;

    -- list_active_capacity_reservations_for_vehicle: only held/consumed (R3, R2),
    -- excluding released (R1, R4), ordered window_start asc -- [R3, R2].
    select array_agg(id) into v_ids from app.list_active_capacity_reservations_for_vehicle(v_vehicle_master_id);
    if v_ids <> array[v_res_r3_id, v_res_r2_id] then
      raise exception 'assertion failed: list_active_capacity_reservations_for_vehicle must return [R3, R2] (window_start asc, held/consumed only), got %', v_ids;
    end if;

    raise notice 'tenant-only member proof: PART 2A''s tenant-membership RLS shape admits this identity where PART 1/2B''s owner/org-unit shape denies it; status filter and window_start ordering both correct';
  end $$;
  reset role;
  reset request.jwt.claims;
commit;

\echo '>> customer_user-layer session (999006, an active tenant_user_identities linkage PLUS an active customer_user principal_memberships row in acmeo1c3b4): zero rows from both PART 2A functions -- `AND NOT app.actor_holds_customer_user_layer(tenant_id)` genuinely excludes this identity despite passing has_active_tenant_membership'
begin;
  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000999006", "role": "authenticated"}';
  do $$
  declare
    v_leg1_id uuid := (select id from app.shipment_legs where idempotency_key = 'idem-leg-o1c3b4-1');
    v_vehicle_master_id uuid := (select id from app.master_records where code = 'VEH-O1C3B4-1');
    v_count integer;
  begin
    select count(*) into v_count from app.list_capacity_reservations_for_leg(v_leg1_id);
    if v_count <> 0 then raise exception 'assertion failed: a customer_user-layer principal must see zero rows from list_capacity_reservations_for_leg, got %', v_count; end if;

    select count(*) into v_count from app.list_active_capacity_reservations_for_vehicle(v_vehicle_master_id);
    if v_count <> 0 then raise exception 'assertion failed: a customer_user-layer principal must see zero rows from list_active_capacity_reservations_for_vehicle, got %', v_count; end if;

    raise notice 'customer_user-layer proof: zero rows from both PART 2A functions despite an active tenant membership -- the customer-layer exclusion genuinely fires';
  end $$;
  reset role;
  reset request.jwt.claims;
commit;

\echo '>> cross-tenant session (999005): zero rows from both PART 2A functions'
begin;
  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000999005", "role": "authenticated"}';
  do $$
  declare
    v_leg1_id uuid := (select id from app.shipment_legs where idempotency_key = 'idem-leg-o1c3b4-1');
    v_vehicle_master_id uuid := (select id from app.master_records where code = 'VEH-O1C3B4-1');
    v_count integer;
  begin
    select count(*) into v_count from app.list_capacity_reservations_for_leg(v_leg1_id);
    if v_count <> 0 then raise exception 'assertion failed: cross-tenant actor must see zero rows from list_capacity_reservations_for_leg, got %', v_count; end if;

    select count(*) into v_count from app.list_active_capacity_reservations_for_vehicle(v_vehicle_master_id);
    if v_count <> 0 then raise exception 'assertion failed: cross-tenant actor must see zero rows from list_active_capacity_reservations_for_vehicle, got %', v_count; end if;

    raise notice 'cross-tenant proof: zero rows from both PART 2A functions, never an exception';
  end $$;
  reset role;
  reset request.jwt.claims;
commit;

\echo '>> Supreme Admin session (999004, ZERO tenant membership anywhere): still sees both PART 2A functions'' real rows via `... OR app.is_supreme_admin()`'
begin;
  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000999004", "role": "authenticated"}';
  do $$
  declare
    v_leg1_id uuid := (select id from app.shipment_legs where idempotency_key = 'idem-leg-o1c3b4-1');
    v_vehicle_master_id uuid := (select id from app.master_records where code = 'VEH-O1C3B4-1');
    v_count integer;
  begin
    select count(*) into v_count from app.list_capacity_reservations_for_leg(v_leg1_id);
    if v_count <> 2 then raise exception 'assertion failed: Supreme Admin must see both reservations on LEG-1, got %', v_count; end if;

    select count(*) into v_count from app.list_active_capacity_reservations_for_vehicle(v_vehicle_master_id);
    if v_count <> 2 then raise exception 'assertion failed: Supreme Admin must see both active reservations on the vehicle, got %', v_count; end if;

    raise notice 'Supreme Admin proof: zero tenant membership anywhere, still bypasses via the RLS policy''s own is_supreme_admin() branch';
  end $$;
  reset role;
  reset request.jwt.claims;
commit;

\echo '>> setup (PART 2B): a role granting ONLY OPS:View cost, published and assigned to the owner (999001) alone -- never to the shared-org-unit viewer (999002), who keeps zero roles and therefore zero permissions -- for app.list_shipment_exceptions'' own field-masking test'
do $$
declare
  v_tenant_id uuid := (select id from app.tenants where slug = 'acmeo1c3b4');
  v_role_id uuid;
  v_draft app.role_versions;
begin
  v_role_id := (app.create_role(v_tenant_id, 'O1C3B4 Cost Viewer', 'OPS:View cost only', 'tester')).id;
  v_draft := app.create_role_version(v_role_id, 'tester');
  perform app.set_role_version_permissions(
    v_draft.id,
    array(select id from app.permissions where resource_module_code = 'OPS' and action = 'View cost'),
    'tester'
  );
  perform app.publish_role_version(v_draft.id, now(), 'tester');
  perform app.assign_role(
    v_tenant_id,
    (select id from app.role_versions where role_id = v_role_id and status = 'published'),
    '00000000-0000-0000-0000-000000999001',
    '00000000-0000-0000-0000-000000999007',
    'tester'
  );
end $$;

\echo '>> fixture (PART 2B): 2 exceptions on SHP-O1C3B4-A1 -- EXC-1 (older, now()-2d, carries real internal_notes/damage_loss_details/claim_amount/claim_currency) and EXC-2 (newer, now()-1d, no sensitive fields at all) -- so list_shipment_exceptions must return [EXC-2, EXC-1] (created_at desc) and EXC-1 is the field-masking fixture'
do $$
declare
  v_tenant_id uuid := (select id from app.tenants where slug = 'acmeo1c3b4');
  v_shipment_a1_id uuid := (select id from app.shipment_orders where shipment_number = 'SHP-O1C3B4-A1');
begin
  insert into app.operational_exceptions (
    id, tenant_id, shipment_order_id, type, severity, status, source, description,
    internal_notes, damage_loss_details, claim_amount, claim_currency,
    created_by, created_at, updated_at
  ) values (
    gen_random_uuid(), v_tenant_id, v_shipment_a1_id, 'damage', 'high', 'open', 'manual',
    'O1C3B4 test: cargo damage observed at destination',
    'Sensitive internal note for O1C3B4 -- forklift puncture, photos on file',
    jsonb_build_object('kind', 'cargo_damage', 'severity', 'moderate'),
    1234.56, 'USD',
    'tester', now() - interval '2 days', now() - interval '2 days'
  );

  insert into app.operational_exceptions (
    id, tenant_id, shipment_order_id, type, severity, status, source, description,
    created_by, created_at, updated_at
  ) values (
    gen_random_uuid(), v_tenant_id, v_shipment_a1_id, 'hold', 'medium', 'open', 'manual',
    'O1C3B4 test: customs hold, no sensitive fields on this one',
    'tester', now() - interval '1 day', now() - interval '1 day'
  );
end $$;

\echo '>> owner session (999001, holds OPS:View cost): list_shipment_exceptions(A1) returns [EXC-2, EXC-1] (created_at desc); on EXC-1, sensitive_masked=false and the real internal_notes/damage_loss_details/claim_amount/claim_currency are visible'
begin;
  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000999001", "role": "authenticated"}';
  do $$
  declare
    v_shipment_a1_id uuid := (select id from app.shipment_orders where shipment_number = 'SHP-O1C3B4-A1');
    -- authenticated holds no direct grant on app.operational_exceptions (the base
    -- table) -- only on app.exceptions_directory (the masked view) and service_role
    -- -- so these lookups go through the view, exactly like the function under test.
    v_exc1_id uuid := (select id from app.exceptions_directory where description like 'O1C3B4 test: cargo damage%');
    v_exc2_id uuid := (select id from app.exceptions_directory where description like 'O1C3B4 test: customs hold%');
    v_ids uuid[];
    v_masked boolean;
    v_claim_amount numeric;
    v_claim_currency text;
    v_internal_notes text;
    v_damage_details jsonb;
  begin
    select array_agg(id) into v_ids from app.list_shipment_exceptions(v_shipment_a1_id);
    if v_ids <> array[v_exc2_id, v_exc1_id] then
      raise exception 'assertion failed: list_shipment_exceptions(A1) must return [EXC-2, EXC-1] (created_at desc), got %', v_ids;
    end if;

    select sensitive_masked, claim_amount, claim_currency, internal_notes, damage_loss_details
    into v_masked, v_claim_amount, v_claim_currency, v_internal_notes, v_damage_details
    from app.list_shipment_exceptions(v_shipment_a1_id)
    where id = v_exc1_id;

    if v_masked or v_claim_amount is distinct from 1234.56 or v_claim_currency <> 'USD'
      or v_internal_notes is null or v_damage_details is null then
      raise exception 'assertion failed: owner (OPS:View cost) must see real sensitive fields on EXC-1, got masked=% claim_amount=% claim_currency=% internal_notes=% damage_loss_details=%',
        v_masked, v_claim_amount, v_claim_currency, v_internal_notes, v_damage_details;
    end if;

    raise notice 'owner proof: real ordering and real (unmasked) sensitive fields for a caller holding OPS:View cost';
  end $$;
  reset role;
  reset request.jwt.claims;
commit;

\echo '>> shared-org-unit viewer session (999002, sees the row via the shared-org-unit branch but holds ZERO roles/permissions): still sees both exceptions via list_shipment_exceptions, but on EXC-1 sees sensitive_masked=true and internal_notes/damage_loss_details/claim_amount/claim_currency all null -- row-level access and field-level masking are genuinely independent checks'
begin;
  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000999002", "role": "authenticated"}';
  do $$
  declare
    v_shipment_a1_id uuid := (select id from app.shipment_orders where shipment_number = 'SHP-O1C3B4-A1');
    v_exc1_id uuid := (select id from app.exceptions_directory where description like 'O1C3B4 test: cargo damage%');
    v_count integer;
    v_masked boolean;
    v_claim_amount numeric;
    v_claim_currency text;
    v_internal_notes text;
    v_damage_details jsonb;
  begin
    select count(*) into v_count from app.list_shipment_exceptions(v_shipment_a1_id);
    if v_count <> 2 then
      raise exception 'assertion failed: shared-org-unit viewer must still see both exceptions (row-level access is independent of OPS:View cost), got %', v_count;
    end if;

    select sensitive_masked, claim_amount, claim_currency, internal_notes, damage_loss_details
    into v_masked, v_claim_amount, v_claim_currency, v_internal_notes, v_damage_details
    from app.list_shipment_exceptions(v_shipment_a1_id)
    where id = v_exc1_id;

    if not v_masked or v_claim_amount is not null or v_claim_currency is not null
      or v_internal_notes is not null or v_damage_details is not null then
      raise exception 'assertion failed: a caller lacking OPS:View cost must see sensitive_masked=true and every sensitive field null on EXC-1, got masked=% claim_amount=% claim_currency=% internal_notes=% damage_loss_details=%',
        v_masked, v_claim_amount, v_claim_currency, v_internal_notes, v_damage_details;
    end if;

    raise notice 'shared-org-unit viewer proof: full row-level visibility, real field-level masking (sensitive_masked=true, all 4 fields null) for a caller lacking OPS:View cost';
  end $$;
  reset role;
  reset request.jwt.claims;
commit;

\echo '>> tenant-only member (999003) and cross-tenant (999005) sessions: zero rows from list_shipment_exceptions -- the SAME can_access_record shape as PART 1, independent of PART 2A''s different tenant-membership shape proven above'
begin;
  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000999003", "role": "authenticated"}';
  do $$
  declare
    v_shipment_a1_id uuid := (select id from app.shipment_orders where shipment_number = 'SHP-O1C3B4-A1');
    v_count integer;
  begin
    select count(*) into v_count from app.list_shipment_exceptions(v_shipment_a1_id);
    if v_count <> 0 then raise exception 'assertion failed: tenant-only member must see zero rows from list_shipment_exceptions, got %', v_count; end if;
    raise notice 'tenant-only member proof: zero rows from list_shipment_exceptions';
  end $$;
  reset role;
  reset request.jwt.claims;
commit;

begin;
  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000999005", "role": "authenticated"}';
  do $$
  declare
    v_shipment_a1_id uuid := (select id from app.shipment_orders where shipment_number = 'SHP-O1C3B4-A1');
    v_count integer;
  begin
    select count(*) into v_count from app.list_shipment_exceptions(v_shipment_a1_id);
    if v_count <> 0 then raise exception 'assertion failed: cross-tenant actor must see zero rows from list_shipment_exceptions, got %', v_count; end if;
    raise notice 'cross-tenant proof: zero rows from list_shipment_exceptions';
  end $$;
  reset role;
  reset request.jwt.claims;
commit;

\echo '>> Supreme Admin session (999004, ZERO tenant membership AND no explicit OPS:View cost grant of any kind): sees both exceptions via can_access_record''s own is_supreme_admin branch, AND sees the real (unmasked) sensitive fields on EXC-1 via app.evaluate_permission''s own supreme_admin_exception branch -- an absolute-CRUD exception, not merely a role grant this actor happens to hold'
begin;
  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000999004", "role": "authenticated"}';
  do $$
  declare
    v_shipment_a1_id uuid := (select id from app.shipment_orders where shipment_number = 'SHP-O1C3B4-A1');
    v_exc1_id uuid := (select id from app.exceptions_directory where description like 'O1C3B4 test: cargo damage%');
    v_count integer;
    v_masked boolean;
    v_claim_amount numeric;
  begin
    select count(*) into v_count from app.list_shipment_exceptions(v_shipment_a1_id);
    if v_count <> 2 then
      raise exception 'assertion failed: Supreme Admin must see both exceptions, got %', v_count;
    end if;

    select sensitive_masked, claim_amount into v_masked, v_claim_amount
    from app.list_shipment_exceptions(v_shipment_a1_id)
    where id = v_exc1_id;
    if v_masked or v_claim_amount is distinct from 1234.56 then
      raise exception 'assertion failed: Supreme Admin must see real (unmasked) sensitive fields on EXC-1 with no explicit OPS:View cost grant, got masked=% claim_amount=%', v_masked, v_claim_amount;
    end if;

    raise notice 'Supreme Admin proof: sees both exceptions and the real (unmasked) sensitive fields, with zero explicit membership or permission grant of any kind';
  end $$;
  reset role;
  reset request.jwt.claims;
commit;

\echo '>> anon defense in depth: all 7 public.* wrapper functions genuinely reject anon at the grant level -- real call attempts, not merely an information_schema read'
begin;
  set local role anon;
  do $$
  declare
    v_dummy uuid := gen_random_uuid();
  begin
    begin
      perform public.get_shipment_order(v_dummy);
      raise exception 'assertion failed: anon must be denied EXECUTE on public.get_shipment_order';
    exception
      when insufficient_privilege then
        raise notice 'anon denial proof: public.get_shipment_order correctly rejected anon';
    end;

    begin
      perform public.list_shipment_orders_for_job_order(v_dummy);
      raise exception 'assertion failed: anon must be denied EXECUTE on public.list_shipment_orders_for_job_order';
    exception
      when insufficient_privilege then
        raise notice 'anon denial proof: public.list_shipment_orders_for_job_order correctly rejected anon';
    end;

    begin
      perform public.list_shipment_orders(v_dummy);
      raise exception 'assertion failed: anon must be denied EXECUTE on public.list_shipment_orders';
    exception
      when insufficient_privilege then
        raise notice 'anon denial proof: public.list_shipment_orders correctly rejected anon';
    end;

    begin
      perform public.get_shipment_mode_profile(v_dummy);
      raise exception 'assertion failed: anon must be denied EXECUTE on public.get_shipment_mode_profile';
    exception
      when insufficient_privilege then
        raise notice 'anon denial proof: public.get_shipment_mode_profile correctly rejected anon';
    end;

    begin
      perform public.list_capacity_reservations_for_leg(v_dummy);
      raise exception 'assertion failed: anon must be denied EXECUTE on public.list_capacity_reservations_for_leg';
    exception
      when insufficient_privilege then
        raise notice 'anon denial proof: public.list_capacity_reservations_for_leg correctly rejected anon';
    end;

    begin
      perform public.list_active_capacity_reservations_for_vehicle(v_dummy);
      raise exception 'assertion failed: anon must be denied EXECUTE on public.list_active_capacity_reservations_for_vehicle';
    exception
      when insufficient_privilege then
        raise notice 'anon denial proof: public.list_active_capacity_reservations_for_vehicle correctly rejected anon';
    end;

    begin
      perform public.list_shipment_exceptions(v_dummy);
      raise exception 'assertion failed: anon must be denied EXECUTE on public.list_shipment_exceptions';
    exception
      when insufficient_privilege then
        raise notice 'anon denial proof: public.list_shipment_exceptions correctly rejected anon';
    end;
  end $$;
  reset role;
commit;

\echo '>> service_role smoke check: BYPASSRLS reads via 3 of the 7 functions (both app.* and public.*) succeed and see the real fixture rows -- deliberately chosen from PART 1/PART 2A, which sit on real RLS-policy-bearing tables that BYPASSRLS genuinely bypasses; app.list_shipment_exceptions is intentionally excluded here (see this file''s own header note: its view''s row-visibility WHERE clause is keyed on auth.uid() directly, which is null under service_role''s own claims-free session here, so BYPASSRLS would not help it)'
begin;
  set local role service_role;
  do $$
  declare
    v_shipment_a1_id uuid := (select id from app.shipment_orders where shipment_number = 'SHP-O1C3B4-A1');
    v_leg1_id uuid := (select id from app.shipment_legs where idempotency_key = 'idem-leg-o1c3b4-1');
    v_count integer;
  begin
    select count(*) into v_count from app.get_shipment_order(v_shipment_a1_id);
    if v_count <> 1 then
      raise exception 'assertion failed: service_role must see A1 via app.get_shipment_order, got %', v_count;
    end if;

    select count(*) into v_count from public.get_shipment_order(v_shipment_a1_id);
    if v_count <> 1 then
      raise exception 'assertion failed: service_role must see A1 via public.get_shipment_order, got %', v_count;
    end if;

    select count(*) into v_count from app.get_shipment_mode_profile(v_shipment_a1_id);
    if v_count <> 1 then
      raise exception 'assertion failed: service_role must see A1''s mode profile via app.get_shipment_mode_profile, got %', v_count;
    end if;

    select count(*) into v_count from public.get_shipment_mode_profile(v_shipment_a1_id);
    if v_count <> 1 then
      raise exception 'assertion failed: service_role must see A1''s mode profile via public.get_shipment_mode_profile, got %', v_count;
    end if;

    select count(*) into v_count from app.list_capacity_reservations_for_leg(v_leg1_id);
    if v_count <> 2 then
      raise exception 'assertion failed: service_role must see both reservations on LEG-1 via app.list_capacity_reservations_for_leg, got %', v_count;
    end if;

    select count(*) into v_count from public.list_capacity_reservations_for_leg(v_leg1_id);
    if v_count <> 2 then
      raise exception 'assertion failed: service_role must see both reservations on LEG-1 via public.list_capacity_reservations_for_leg, got %', v_count;
    end if;

    raise notice 'service_role proof: BYPASSRLS reads succeed via both app.* and public.* on the spot-checked PART 1/PART 2A functions, matching the migration''s own no-new-capability argument';
  end $$;
  reset role;
commit;

\echo '>> schema-privilege defense in depth: anon holds zero EXECUTE on any of the 7 new cluster-3-batch-4 function pairs (14 functions) in EITHER schema (app or public); authenticated/service_role (spot-checked on 3 of the 7 pairs, one per authority family plus the view-backed one) hold EXECUTE on both the app.* function and its public.* wrapper, exactly as this migration''s own GRANT PARITY section declares'
do $$
declare
  v_count integer;
begin
  select count(*) into v_count
  from information_schema.routine_privileges
  where routine_schema in ('app', 'public')
    and routine_name in (
      'get_shipment_order',
      'list_shipment_orders_for_job_order',
      'list_shipment_orders',
      'get_shipment_mode_profile',
      'list_capacity_reservations_for_leg',
      'list_active_capacity_reservations_for_vehicle',
      'list_shipment_exceptions'
    )
    and grantee = 'anon';
  if v_count <> 0 then
    raise exception 'assertion failed: anon must hold zero EXECUTE on any of the 7 cluster-3-batch-4 function pairs (14 functions, either schema), found % grants', v_count;
  end if;

  -- Spot-check 3 of the 7: authenticated AND service_role both hold EXECUTE on the
  -- app.* function AND its public.* wrapper (grant parity, ISS-2026-309).
  select count(*) into v_count
  from information_schema.routine_privileges
  where routine_schema in ('app', 'public')
    and routine_name in ('get_shipment_order', 'list_active_capacity_reservations_for_vehicle', 'list_shipment_exceptions')
    and grantee in ('authenticated', 'service_role');
  if v_count <> 3 * 2 * 2 then
    raise exception 'assertion failed: expected exactly 12 grants (3 functions x 2 schemas x 2 grantees) for the spot-checked functions, found %', v_count;
  end if;

  raise notice 'schema-privilege proof: anon holds zero EXECUTE on any of the 14 new cluster-3-batch-4 functions; authenticated/service_role hold the declared grant on both the app.* and public.* spot-checked functions';
end $$;

drop function app._o1c3b4_test_make_job_order_chain(uuid, uuid, uuid, text);

\echo '>> o1-query-layer-cluster3-batch4.sql test suite passed -- cluster 3 batch 4 (shipment orders, shipment mode profiles, vehicle capacity reservations, shipment exceptions, 7/7 call sites) is now fully DONE -- cluster 3 (operations-tms-core) is COMPLETE: 20/20 tables, 28/28 call sites'
