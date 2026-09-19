-- Real, executable test evidence for CG-AUDIT-2026-09-02 O1-query-layer, cluster 4
-- (telematics-tracking) batch 1 of N
-- (supabase/migrations/20260911050000_close_o1_query_layer_cluster4_batch1_fleet_driver_device.sql).
--
-- Proves, against a real disposable database, that all 7 new function pairs (14
-- functions total -- ALL SECURITY INVOKER with ZERO actor parameter) return exactly
-- what their own comments and this migration's own header claim. All 7 target
-- tables (app.vehicle_operational_profiles, app.driver_operational_profiles,
-- app.gps_devices, app.sim_cards, app.device_vehicle_assignments,
-- app.provider_vehicle_mappings, app.vehicle_tracking_source_priorities) share the
-- IDENTICAL tenant-membership RLS predicate (the SAME shape cluster 3 batch 4's own
-- app.vehicle_capacity_reservations used):
--
--   (app.has_active_tenant_membership(tenant_id)
--     AND NOT app.actor_holds_customer_user_layer(tenant_id))
--     OR app.is_supreme_admin()
--
-- so this file is structured as ONE shared test matrix run across all 7 functions,
-- plus a few function-specific ordering checks:
--
--   * A real ACTIVE org_user tenant member (999101) with NO owner/org-unit
--     relationship of any kind (this table family has none) sees every real fixture
--     row from all 7 functions, in the documented order.
--   * A customer_user-layer principal in the SAME tenant (999102: an active
--     app.tenant_user_identities linkage PLUS an active customer_user
--     app.principal_memberships row) sees ZERO rows from all 7 functions despite
--     passing has_active_tenant_membership -- proving `AND NOT
--     app.actor_holds_customer_user_layer(tenant_id)` genuinely fires. This is the
--     single most important assertion in this batch.
--   * A cross-tenant tenant_admin (999104, gizmoo1c4b1's own admin, zero standing in
--     acmeo1c4b1) sees ZERO rows from all 7 functions when called with acmeo1c4b1's
--     own ids.
--   * A Supreme Admin (999103) with ZERO tenant membership anywhere still sees every
--     real fixture row from all 7 functions via `... OR app.is_supreme_admin()`.
--
-- KEY FINDING under test: app.list_device_vehicle_assignment_history,
-- app.list_provider_vehicle_mappings and app.list_vehicle_tracking_source_priorities
-- are filtered in the RPC call ITSELF by device_id/vehicle_master_id -- NOT by
-- tenant_id -- but their RLS AUTHORITY predicate is still evaluated against each
-- row's OWN, independent tenant_id column (see the migration's own KEY FINDING
-- section). The fixture below makes this concrete rather than assumed: every
-- device_vehicle_assignments/provider_vehicle_mappings/vehicle_tracking_source_
-- priorities row filtered by in every test below has device_id/vehicle_master_id
-- pointing at a real acmeo1c4b1 device/vehicle, AND its own tenant_id column set to
-- acmeo1c4b1 -- so the customer_user-layer and cross-tenant denial assertions below
-- are proof that the AUTHORITY check is genuinely reading that row's own tenant_id
-- column (which the RLS predicate sees), not silently deriving tenant scope from
-- the device_id/vehicle_master_id the caller happened to filter by (there is no
-- join to app.gps_devices or app.master_records anywhere in this table family's
-- RLS policies to derive it from even if a caller wanted to).
--
-- Ordering fidelity: app.list_device_vehicle_assignment_history and
-- app.list_provider_vehicle_mappings (`order by created_at desc`) are each proven
-- with a real 2-row fixture inserted in ASCENDING created_at order (so the
-- expected DESC output is the reverse of physical insertion order -- a naive
-- unordered scan would not coincidentally match). app.list_vehicle_tracking_source_
-- priorities is proven with a real 3-row fixture whose priority_rank values are
-- deliberately uncorrelated with both insertion order and created_at order in
-- either direction -- the one function in this batch ordered by `priority_rank asc`
-- instead of `created_at desc`.
--
-- Also confirms schema-privilege defense in depth: anon holds zero EXECUTE on any of
-- the 14 new functions in EITHER schema -- a real call attempt against every one of
-- the 7 public.* wrappers, not merely an information_schema read -- and (spot-
-- checked on 3 of the 7 pairs, including the dead-code
-- list_device_vehicle_assignment_history and the different-ordering
-- list_vehicle_tracking_source_priorities) authenticated/service_role hold EXECUTE
-- on both the app.* function and its public.* wrapper, exactly as this migration's
-- own GRANT PARITY section declares. A service_role (BYPASSRLS) smoke check is run
-- against those same 3 spot-checked functions (both app.* and public.*), confirming
-- it reads the real rows regardless of RLS -- app.list_device_vehicle_assignment_
-- history has ZERO real production callers today per the migration's own
-- "ADDITIONAL DEFECT FOUND" note, but that is not a reason to skip testing it: it is
-- tested identically to its 6 siblings throughout this file.

\set ON_ERROR_STOP on

\echo '>> setup: tenant acmeo1c4b1 with a real active org_user tenant member (999101, no owner/org-unit relationship to anything -- this table family has no such scoping), a customer_user-layer principal in the SAME tenant (999102), a global Supreme Admin with ZERO membership in this tenant (999103), and a second, isolated tenant gizmoo1c4b1 with its own tenant_admin (999104)'
do $$
declare
  v_tenant_id uuid;
  v_other_tenant_id uuid;
begin
  insert into auth.users (id, email) values
    ('00000000-0000-0000-0000-000000999101', 'fleetmembero1c4b1@example.test'),
    ('00000000-0000-0000-0000-000000999102', 'customerusero1c4b1@example.test'),
    ('00000000-0000-0000-0000-000000999103', 'supremeo1c4b1@example.test'),
    ('00000000-0000-0000-0000-000000999104', 'othertenanto1c4b1@example.test');

  perform app.provision_tenant('acmeo1c4b1', 'Acme O1C4B1 Co', 'idem-acmeo1c4b1', 'tester');
  v_tenant_id := (select id from app.tenants where slug = 'acmeo1c4b1');
  perform app.transition_tenant_status(v_tenant_id, 'active', 'setup', 'tester');

  -- The real, active tenant member this whole batch's authority shape turns on: a
  -- plain org_user with NO org_unit and no owner relationship to anything (this
  -- table family has neither concept) -- any active member should see every row for
  -- their own tenant.
  perform app.invite_user(v_tenant_id, '00000000-0000-0000-0000-000000999101', 'fleetmembero1c4b1@example.test', 'Fleet Member', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'fleetmembero1c4b1@example.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000999101', 'org_user', v_tenant_id, null, 'tester');

  -- Customer-portal-layer principal (ATW-023 shape, this batch's own denial case): an
  -- active app.tenant_user_identities linkage plus an active customer_user
  -- app.principal_memberships row, granted directly (no app.users profile at all --
  -- a customer_user-layer identity never gets one), mirroring
  -- scripts/db-tests/o1-query-layer-cluster3-batch4.sql's own established pattern
  -- for this exact identity shape.
  perform app.link_auth_identity('00000000-0000-0000-0000-000000999102', v_tenant_id, 'tester', 'active');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000999102', 'customer_user', v_tenant_id, 'fake-account-ref-o1c4b1', 'tester');

  perform app.grant_principal_membership('00000000-0000-0000-0000-000000999103', 'supreme_admin', null, null, 'tester');

  perform app.provision_tenant('gizmoo1c4b1', 'Gizmo O1C4B1 Co', 'idem-gizmoo1c4b1', 'tester');
  v_other_tenant_id := (select id from app.tenants where slug = 'gizmoo1c4b1');
  perform app.transition_tenant_status(v_other_tenant_id, 'active', 'setup', 'tester');
  perform app.invite_user(v_other_tenant_id, '00000000-0000-0000-0000-000000999104', 'othertenanto1c4b1@example.test', 'Other Tenant Admin', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'othertenanto1c4b1@example.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000999104', 'tenant_admin', v_other_tenant_id, null, 'tester');
end $$;

\echo '>> fixture: 2 app.master_records rows under acmeo1c4b1 -- VEH-O1C4B1-1 (master_type_code=vehicle) and DRV-O1C4B1-1 (master_type_code=driver) -- the real vehicle/driver identities every table in this batch is the operational layer over'
do $$
declare
  v_tenant_id uuid := (select id from app.tenants where slug = 'acmeo1c4b1');
begin
  insert into app.master_records (id, master_type_code, tenant_id, code, name, canonical_status, created_by)
  values (gen_random_uuid(), 'vehicle', v_tenant_id, 'VEH-O1C4B1-1', 'O1C4B1 Truck 1', 'active', 'tester');

  insert into app.master_records (id, master_type_code, tenant_id, code, name, canonical_status, created_by)
  values (gen_random_uuid(), 'driver', v_tenant_id, 'DRV-O1C4B1-1', 'O1C4B1 Driver 1', 'active', 'tester');
end $$;

\echo '>> fixture: 1 app.vehicle_operational_profiles row, 1 app.driver_operational_profiles row, 1 app.gps_devices row and 1 app.sim_cards row under acmeo1c4b1 -- the tenant_id-filtered functions'' own real rows'
do $$
declare
  v_tenant_id uuid := (select id from app.tenants where slug = 'acmeo1c4b1');
  v_vehicle_master_id uuid := (select id from app.master_records where code = 'VEH-O1C4B1-1');
  v_driver_master_id uuid := (select id from app.master_records where code = 'DRV-O1C4B1-1');
  v_device_id uuid;
begin
  insert into app.vehicle_operational_profiles (id, tenant_id, vehicle_master_id, ownership_type, capacity_weight_kg, capacity_volume_cbm, status, created_by)
  values (gen_random_uuid(), v_tenant_id, v_vehicle_master_id, 'owned', 8000, 32, 'active', 'tester');

  insert into app.driver_operational_profiles (id, tenant_id, driver_master_id, license_class, mobile_tracking_consent, status, created_by)
  values (gen_random_uuid(), v_tenant_id, v_driver_master_id, 'B2', true, 'active', 'tester');

  insert into app.gps_devices (id, tenant_id, imei, device_model, ownership_type, status, created_by)
  values (gen_random_uuid(), v_tenant_id, 'O1C4B1-IMEI-0001', 'TrackerX', 'cargogrid', 'active', 'tester')
  returning id into v_device_id;

  insert into app.sim_cards (id, tenant_id, iccid, msisdn, carrier, status, current_device_id, created_by)
  values (gen_random_uuid(), v_tenant_id, 'O1C4B1-ICCID-0001', '+6280000000001', 'TelcoOne', 'active', v_device_id, 'tester');
end $$;

\echo '>> fixture: 2 app.device_vehicle_assignments rows on the SAME device (filtered by device_id, NOT tenant_id in the RPC call -- but this row''s OWN tenant_id column, set to acmeo1c4b1 below, is what the RLS predicate actually reads) -- ASSIGN-OLD (superseded, created_at=now()-5d, inserted FIRST) and ASSIGN-NEW (current, created_at=now()-1d, inserted SECOND) -- so `order by created_at desc` must return [ASSIGN-NEW, ASSIGN-OLD], the REVERSE of physical insertion order'
do $$
declare
  v_tenant_id uuid := (select id from app.tenants where slug = 'acmeo1c4b1');
  v_device_id uuid := (select id from app.gps_devices where imei = 'O1C4B1-IMEI-0001');
  v_vop_id uuid := (select id from app.vehicle_operational_profiles where vehicle_master_id = (select id from app.master_records where code = 'VEH-O1C4B1-1'));
begin
  insert into app.device_vehicle_assignments (id, tenant_id, device_id, vehicle_operational_profile_id, is_current, effective_from, effective_to, reason, created_by, created_at)
  values (gen_random_uuid(), v_tenant_id, v_device_id, v_vop_id, false, now() - interval '5 days', now() - interval '2 days', 'o1c4b1 superseded assignment', 'tester', now() - interval '5 days');

  insert into app.device_vehicle_assignments (id, tenant_id, device_id, vehicle_operational_profile_id, is_current, effective_from, reason, created_by, created_at)
  values (gen_random_uuid(), v_tenant_id, v_device_id, v_vop_id, true, now() - interval '2 days', 'o1c4b1 current assignment', 'tester', now() - interval '1 day');
end $$;

\echo '>> fixture: 2 app.provider_vehicle_mappings rows on the SAME vehicle_master_id (filtered by vehicle_master_id, NOT tenant_id in the RPC call -- same independent-tenant_id-column situation as above) -- MAP-OLD (provider gpsone, created_at=now()-3d, inserted FIRST) and MAP-NEW (provider trackwave, created_at=now()-1d, inserted SECOND) -- so `order by created_at desc` must return [MAP-NEW, MAP-OLD], the REVERSE of physical insertion order'
do $$
declare
  v_tenant_id uuid := (select id from app.tenants where slug = 'acmeo1c4b1');
  v_vehicle_master_id uuid := (select id from app.master_records where code = 'VEH-O1C4B1-1');
begin
  insert into app.provider_vehicle_mappings (id, tenant_id, vehicle_master_id, provider_code, external_vehicle_id, status, created_by, created_at)
  values (gen_random_uuid(), v_tenant_id, v_vehicle_master_id, 'gpsone', 'GPSONE-EXT-1', 'active', 'tester', now() - interval '3 days');

  insert into app.provider_vehicle_mappings (id, tenant_id, vehicle_master_id, provider_code, external_vehicle_id, status, created_by, created_at)
  values (gen_random_uuid(), v_tenant_id, v_vehicle_master_id, 'trackwave', 'TRACKWAVE-EXT-1', 'active', 'tester', now() - interval '1 day');
end $$;

\echo '>> fixture: 3 app.vehicle_tracking_source_priorities rows on the SAME vehicle_master_id (filtered by vehicle_master_id, NOT tenant_id -- same independent-tenant_id-column situation) -- inserted in an order that is DELIBERATELY uncorrelated with priority_rank in either direction: third_party_platform/rank=3 (created_at=now()-3d, inserted FIRST), driver_mobile/rank=1 (created_at=now()-2d, inserted SECOND), direct_device/rank=2 (created_at=now()-1d, inserted THIRD) -- so `order by priority_rank asc` must return [driver_mobile(1), direct_device(2), third_party_platform(3)], matching NEITHER insertion order NOR created_at asc/desc -- the one function in this batch NOT ordered by created_at'
do $$
declare
  v_tenant_id uuid := (select id from app.tenants where slug = 'acmeo1c4b1');
  v_vehicle_master_id uuid := (select id from app.master_records where code = 'VEH-O1C4B1-1');
begin
  insert into app.vehicle_tracking_source_priorities (id, tenant_id, vehicle_master_id, source_type, priority_rank, is_enabled, created_by, created_at)
  values (gen_random_uuid(), v_tenant_id, v_vehicle_master_id, 'third_party_platform', 3, true, 'tester', now() - interval '3 days');

  insert into app.vehicle_tracking_source_priorities (id, tenant_id, vehicle_master_id, source_type, priority_rank, is_enabled, created_by, created_at)
  values (gen_random_uuid(), v_tenant_id, v_vehicle_master_id, 'driver_mobile', 1, true, 'tester', now() - interval '2 days');

  insert into app.vehicle_tracking_source_priorities (id, tenant_id, vehicle_master_id, source_type, priority_rank, is_enabled, created_by, created_at)
  values (gen_random_uuid(), v_tenant_id, v_vehicle_master_id, 'direct_device', 2, true, 'tester', now() - interval '1 day');
end $$;

\echo '>> tenant member session (999101, real active acmeo1c4b1 org_user, no owner/org-unit relationship to anything): sees the real fixture row(s) from all 7 functions, in the documented order -- created_at desc for 6 of them, priority_rank asc for app.list_vehicle_tracking_source_priorities'
begin;
  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000999101", "role": "authenticated"}';
  do $$
  declare
    v_tenant_id uuid := (select id from app.tenants where slug = 'acmeo1c4b1');
    v_vehicle_master_id uuid := (select id from app.master_records where code = 'VEH-O1C4B1-1');
    v_device_id uuid := (select id from app.gps_devices where imei = 'O1C4B1-IMEI-0001');
    v_vop_id uuid := (select id from app.vehicle_operational_profiles where vehicle_master_id = v_vehicle_master_id);
    v_dop_id uuid := (select id from app.driver_operational_profiles where driver_master_id = (select id from app.master_records where code = 'DRV-O1C4B1-1'));
    v_sim_id uuid := (select id from app.sim_cards where iccid = 'O1C4B1-ICCID-0001');
    v_assign_old_id uuid := (select id from app.device_vehicle_assignments where device_id = v_device_id and reason = 'o1c4b1 superseded assignment');
    v_assign_new_id uuid := (select id from app.device_vehicle_assignments where device_id = v_device_id and reason = 'o1c4b1 current assignment');
    v_map_old_id uuid := (select id from app.provider_vehicle_mappings where vehicle_master_id = v_vehicle_master_id and provider_code = 'gpsone');
    v_map_new_id uuid := (select id from app.provider_vehicle_mappings where vehicle_master_id = v_vehicle_master_id and provider_code = 'trackwave');
    v_rank1_id uuid := (select id from app.vehicle_tracking_source_priorities where vehicle_master_id = v_vehicle_master_id and source_type = 'driver_mobile');
    v_rank2_id uuid := (select id from app.vehicle_tracking_source_priorities where vehicle_master_id = v_vehicle_master_id and source_type = 'direct_device');
    v_rank3_id uuid := (select id from app.vehicle_tracking_source_priorities where vehicle_master_id = v_vehicle_master_id and source_type = 'third_party_platform');
    v_ids uuid[];
  begin
    select array_agg(id) into v_ids from app.list_vehicle_operational_profiles(v_tenant_id);
    if v_ids <> array[v_vop_id] then
      raise exception 'assertion failed: tenant member must see the real vehicle_operational_profiles row, got %', v_ids;
    end if;

    select array_agg(id) into v_ids from app.list_driver_operational_profiles(v_tenant_id);
    if v_ids <> array[v_dop_id] then
      raise exception 'assertion failed: tenant member must see the real driver_operational_profiles row, got %', v_ids;
    end if;

    select array_agg(id) into v_ids from app.list_gps_devices(v_tenant_id);
    if v_ids <> array[v_device_id] then
      raise exception 'assertion failed: tenant member must see the real gps_devices row, got %', v_ids;
    end if;

    select array_agg(id) into v_ids from app.list_sim_cards(v_tenant_id);
    if v_ids <> array[v_sim_id] then
      raise exception 'assertion failed: tenant member must see the real sim_cards row, got %', v_ids;
    end if;

    -- Filtered by device_id, not tenant_id -- created_at desc must reverse the
    -- ascending physical insertion order above.
    select array_agg(id) into v_ids from app.list_device_vehicle_assignment_history(v_device_id);
    if v_ids <> array[v_assign_new_id, v_assign_old_id] then
      raise exception 'assertion failed: tenant member must see [NEW, OLD] (created_at desc) from list_device_vehicle_assignment_history, got %', v_ids;
    end if;

    -- Filtered by vehicle_master_id, not tenant_id -- created_at desc must reverse
    -- the ascending physical insertion order above.
    select array_agg(id) into v_ids from app.list_provider_vehicle_mappings(v_vehicle_master_id);
    if v_ids <> array[v_map_new_id, v_map_old_id] then
      raise exception 'assertion failed: tenant member must see [NEW, OLD] (created_at desc) from list_provider_vehicle_mappings, got %', v_ids;
    end if;

    -- Filtered by vehicle_master_id, not tenant_id -- priority_rank asc, NOT
    -- created_at, must produce [rank1, rank2, rank3] regardless of insertion order.
    select array_agg(id) into v_ids from app.list_vehicle_tracking_source_priorities(v_vehicle_master_id);
    if v_ids <> array[v_rank1_id, v_rank2_id, v_rank3_id] then
      raise exception 'assertion failed: tenant member must see [rank1, rank2, rank3] (priority_rank asc) from list_vehicle_tracking_source_priorities, got %', v_ids;
    end if;

    raise notice 'tenant member proof: all 7 functions return the real fixture row(s) in the documented order (created_at desc for 6, priority_rank asc for the 7th)';
  end $$;
  reset role;
  reset request.jwt.claims;
commit;

\echo '>> customer_user-layer session (999102, an active tenant_user_identities linkage PLUS an active customer_user principal_memberships row in acmeo1c4b1): ZERO rows from ALL 7 functions despite passing has_active_tenant_membership -- `AND NOT app.actor_holds_customer_user_layer(tenant_id)` genuinely fires for all 7 tables, including the 3 whose RPC filter column is device_id/vehicle_master_id rather than tenant_id (proof that the authority check is genuinely reading each row''s own tenant_id column, not skipped because the filter column differs) -- THE single most important assertion in this batch'
begin;
  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000999102", "role": "authenticated"}';
  do $$
  declare
    v_tenant_id uuid := (select id from app.tenants where slug = 'acmeo1c4b1');
    v_vehicle_master_id uuid := (select id from app.master_records where code = 'VEH-O1C4B1-1');
    v_device_id uuid := (select id from app.gps_devices where imei = 'O1C4B1-IMEI-0001');
    v_count integer;
  begin
    select count(*) into v_count from app.list_vehicle_operational_profiles(v_tenant_id);
    if v_count <> 0 then raise exception 'assertion failed: customer_user-layer principal must see zero rows from list_vehicle_operational_profiles, got %', v_count; end if;

    select count(*) into v_count from app.list_driver_operational_profiles(v_tenant_id);
    if v_count <> 0 then raise exception 'assertion failed: customer_user-layer principal must see zero rows from list_driver_operational_profiles, got %', v_count; end if;

    select count(*) into v_count from app.list_gps_devices(v_tenant_id);
    if v_count <> 0 then raise exception 'assertion failed: customer_user-layer principal must see zero rows from list_gps_devices, got %', v_count; end if;

    select count(*) into v_count from app.list_sim_cards(v_tenant_id);
    if v_count <> 0 then raise exception 'assertion failed: customer_user-layer principal must see zero rows from list_sim_cards, got %', v_count; end if;

    select count(*) into v_count from app.list_device_vehicle_assignment_history(v_device_id);
    if v_count <> 0 then raise exception 'assertion failed: customer_user-layer principal must see zero rows from list_device_vehicle_assignment_history, got %', v_count; end if;

    select count(*) into v_count from app.list_provider_vehicle_mappings(v_vehicle_master_id);
    if v_count <> 0 then raise exception 'assertion failed: customer_user-layer principal must see zero rows from list_provider_vehicle_mappings, got %', v_count; end if;

    select count(*) into v_count from app.list_vehicle_tracking_source_priorities(v_vehicle_master_id);
    if v_count <> 0 then raise exception 'assertion failed: customer_user-layer principal must see zero rows from list_vehicle_tracking_source_priorities, got %', v_count; end if;

    raise notice 'customer_user-layer proof: zero rows from all 7 functions despite an active tenant membership -- the customer-layer exclusion genuinely fires for every table in this batch';
  end $$;
  reset role;
  reset request.jwt.claims;
commit;

\echo '>> cross-tenant session (999104, gizmoo1c4b1''s own tenant_admin, no standing in acmeo1c4b1 at all): ZERO rows from all 7 functions when called with acmeo1c4b1''s own ids -- including the 3 functions filtered by device_id/vehicle_master_id, proving the authority check does not leak across tenants merely because the caller can name a real device_id/vehicle_master_id row'
begin;
  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000999104", "role": "authenticated"}';
  do $$
  declare
    v_tenant_id uuid := (select id from app.tenants where slug = 'acmeo1c4b1');
    v_vehicle_master_id uuid := (select id from app.master_records where code = 'VEH-O1C4B1-1');
    v_device_id uuid := (select id from app.gps_devices where imei = 'O1C4B1-IMEI-0001');
    v_count integer;
  begin
    select count(*) into v_count from app.list_vehicle_operational_profiles(v_tenant_id);
    if v_count <> 0 then raise exception 'assertion failed: cross-tenant actor must see zero rows from list_vehicle_operational_profiles, got %', v_count; end if;

    select count(*) into v_count from app.list_driver_operational_profiles(v_tenant_id);
    if v_count <> 0 then raise exception 'assertion failed: cross-tenant actor must see zero rows from list_driver_operational_profiles, got %', v_count; end if;

    select count(*) into v_count from app.list_gps_devices(v_tenant_id);
    if v_count <> 0 then raise exception 'assertion failed: cross-tenant actor must see zero rows from list_gps_devices, got %', v_count; end if;

    select count(*) into v_count from app.list_sim_cards(v_tenant_id);
    if v_count <> 0 then raise exception 'assertion failed: cross-tenant actor must see zero rows from list_sim_cards, got %', v_count; end if;

    select count(*) into v_count from app.list_device_vehicle_assignment_history(v_device_id);
    if v_count <> 0 then raise exception 'assertion failed: cross-tenant actor must see zero rows from list_device_vehicle_assignment_history, got %', v_count; end if;

    select count(*) into v_count from app.list_provider_vehicle_mappings(v_vehicle_master_id);
    if v_count <> 0 then raise exception 'assertion failed: cross-tenant actor must see zero rows from list_provider_vehicle_mappings, got %', v_count; end if;

    select count(*) into v_count from app.list_vehicle_tracking_source_priorities(v_vehicle_master_id);
    if v_count <> 0 then raise exception 'assertion failed: cross-tenant actor must see zero rows from list_vehicle_tracking_source_priorities, got %', v_count; end if;

    raise notice 'cross-tenant proof: zero rows from all 7 functions, never an exception';
  end $$;
  reset role;
  reset request.jwt.claims;
commit;

\echo '>> Supreme Admin session (999103, ZERO tenant membership anywhere): still sees the real fixture row(s) from all 7 functions, in the documented order, via `... OR app.is_supreme_admin()`'
begin;
  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000999103", "role": "authenticated"}';
  do $$
  declare
    v_tenant_id uuid := (select id from app.tenants where slug = 'acmeo1c4b1');
    v_vehicle_master_id uuid := (select id from app.master_records where code = 'VEH-O1C4B1-1');
    v_device_id uuid := (select id from app.gps_devices where imei = 'O1C4B1-IMEI-0001');
    v_vop_id uuid := (select id from app.vehicle_operational_profiles where vehicle_master_id = v_vehicle_master_id);
    v_dop_id uuid := (select id from app.driver_operational_profiles where driver_master_id = (select id from app.master_records where code = 'DRV-O1C4B1-1'));
    v_sim_id uuid := (select id from app.sim_cards where iccid = 'O1C4B1-ICCID-0001');
    v_assign_old_id uuid := (select id from app.device_vehicle_assignments where device_id = v_device_id and reason = 'o1c4b1 superseded assignment');
    v_assign_new_id uuid := (select id from app.device_vehicle_assignments where device_id = v_device_id and reason = 'o1c4b1 current assignment');
    v_map_old_id uuid := (select id from app.provider_vehicle_mappings where vehicle_master_id = v_vehicle_master_id and provider_code = 'gpsone');
    v_map_new_id uuid := (select id from app.provider_vehicle_mappings where vehicle_master_id = v_vehicle_master_id and provider_code = 'trackwave');
    v_rank1_id uuid := (select id from app.vehicle_tracking_source_priorities where vehicle_master_id = v_vehicle_master_id and source_type = 'driver_mobile');
    v_rank2_id uuid := (select id from app.vehicle_tracking_source_priorities where vehicle_master_id = v_vehicle_master_id and source_type = 'direct_device');
    v_rank3_id uuid := (select id from app.vehicle_tracking_source_priorities where vehicle_master_id = v_vehicle_master_id and source_type = 'third_party_platform');
    v_ids uuid[];
  begin
    select array_agg(id) into v_ids from app.list_vehicle_operational_profiles(v_tenant_id);
    if v_ids <> array[v_vop_id] then
      raise exception 'assertion failed: Supreme Admin with zero membership must bypass and see the real vehicle_operational_profiles row, got %', v_ids;
    end if;

    select array_agg(id) into v_ids from app.list_driver_operational_profiles(v_tenant_id);
    if v_ids <> array[v_dop_id] then
      raise exception 'assertion failed: Supreme Admin with zero membership must bypass and see the real driver_operational_profiles row, got %', v_ids;
    end if;

    select array_agg(id) into v_ids from app.list_gps_devices(v_tenant_id);
    if v_ids <> array[v_device_id] then
      raise exception 'assertion failed: Supreme Admin with zero membership must bypass and see the real gps_devices row, got %', v_ids;
    end if;

    select array_agg(id) into v_ids from app.list_sim_cards(v_tenant_id);
    if v_ids <> array[v_sim_id] then
      raise exception 'assertion failed: Supreme Admin with zero membership must bypass and see the real sim_cards row, got %', v_ids;
    end if;

    select array_agg(id) into v_ids from app.list_device_vehicle_assignment_history(v_device_id);
    if v_ids <> array[v_assign_new_id, v_assign_old_id] then
      raise exception 'assertion failed: Supreme Admin with zero membership must bypass and see [NEW, OLD] from list_device_vehicle_assignment_history, got %', v_ids;
    end if;

    select array_agg(id) into v_ids from app.list_provider_vehicle_mappings(v_vehicle_master_id);
    if v_ids <> array[v_map_new_id, v_map_old_id] then
      raise exception 'assertion failed: Supreme Admin with zero membership must bypass and see [NEW, OLD] from list_provider_vehicle_mappings, got %', v_ids;
    end if;

    select array_agg(id) into v_ids from app.list_vehicle_tracking_source_priorities(v_vehicle_master_id);
    if v_ids <> array[v_rank1_id, v_rank2_id, v_rank3_id] then
      raise exception 'assertion failed: Supreme Admin with zero membership must bypass and see [rank1, rank2, rank3] from list_vehicle_tracking_source_priorities, got %', v_ids;
    end if;

    raise notice 'Supreme Admin proof: zero tenant membership anywhere, still bypasses via the RLS policy''s own is_supreme_admin() branch and sees the real rows in the documented order across all 7 functions';
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
      perform public.list_vehicle_operational_profiles(v_dummy);
      raise exception 'assertion failed: anon must be denied EXECUTE on public.list_vehicle_operational_profiles';
    exception
      when insufficient_privilege then
        raise notice 'anon denial proof: public.list_vehicle_operational_profiles correctly rejected anon';
    end;

    begin
      perform public.list_driver_operational_profiles(v_dummy);
      raise exception 'assertion failed: anon must be denied EXECUTE on public.list_driver_operational_profiles';
    exception
      when insufficient_privilege then
        raise notice 'anon denial proof: public.list_driver_operational_profiles correctly rejected anon';
    end;

    begin
      perform public.list_gps_devices(v_dummy);
      raise exception 'assertion failed: anon must be denied EXECUTE on public.list_gps_devices';
    exception
      when insufficient_privilege then
        raise notice 'anon denial proof: public.list_gps_devices correctly rejected anon';
    end;

    begin
      perform public.list_sim_cards(v_dummy);
      raise exception 'assertion failed: anon must be denied EXECUTE on public.list_sim_cards';
    exception
      when insufficient_privilege then
        raise notice 'anon denial proof: public.list_sim_cards correctly rejected anon';
    end;

    begin
      perform public.list_device_vehicle_assignment_history(v_dummy);
      raise exception 'assertion failed: anon must be denied EXECUTE on public.list_device_vehicle_assignment_history';
    exception
      when insufficient_privilege then
        raise notice 'anon denial proof: public.list_device_vehicle_assignment_history correctly rejected anon';
    end;

    begin
      perform public.list_provider_vehicle_mappings(v_dummy);
      raise exception 'assertion failed: anon must be denied EXECUTE on public.list_provider_vehicle_mappings';
    exception
      when insufficient_privilege then
        raise notice 'anon denial proof: public.list_provider_vehicle_mappings correctly rejected anon';
    end;

    begin
      perform public.list_vehicle_tracking_source_priorities(v_dummy);
      raise exception 'assertion failed: anon must be denied EXECUTE on public.list_vehicle_tracking_source_priorities';
    exception
      when insufficient_privilege then
        raise notice 'anon denial proof: public.list_vehicle_tracking_source_priorities correctly rejected anon';
    end;
  end $$;
  reset role;
commit;

\echo '>> service_role smoke check: BYPASSRLS reads via 3 of the 7 functions (both app.* and public.*) succeed and see the real fixture rows -- deliberately including app.list_device_vehicle_assignment_history (this migration''s own zero-real-callers-today function, tested identically to its 6 siblings) and app.list_vehicle_tracking_source_priorities (the priority_rank-ordered one)'
begin;
  set local role service_role;
  do $$
  declare
    v_tenant_id uuid := (select id from app.tenants where slug = 'acmeo1c4b1');
    v_vehicle_master_id uuid := (select id from app.master_records where code = 'VEH-O1C4B1-1');
    v_device_id uuid := (select id from app.gps_devices where imei = 'O1C4B1-IMEI-0001');
    v_count integer;
  begin
    select count(*) into v_count from app.list_gps_devices(v_tenant_id);
    if v_count <> 1 then
      raise exception 'assertion failed: service_role must see the real gps_devices row via app.list_gps_devices, got %', v_count;
    end if;

    select count(*) into v_count from public.list_gps_devices(v_tenant_id);
    if v_count <> 1 then
      raise exception 'assertion failed: service_role must see the real gps_devices row via public.list_gps_devices, got %', v_count;
    end if;

    select count(*) into v_count from app.list_device_vehicle_assignment_history(v_device_id);
    if v_count <> 2 then
      raise exception 'assertion failed: service_role must see both assignment-history rows via app.list_device_vehicle_assignment_history, got %', v_count;
    end if;

    select count(*) into v_count from public.list_device_vehicle_assignment_history(v_device_id);
    if v_count <> 2 then
      raise exception 'assertion failed: service_role must see both assignment-history rows via public.list_device_vehicle_assignment_history, got %', v_count;
    end if;

    select count(*) into v_count from app.list_vehicle_tracking_source_priorities(v_vehicle_master_id);
    if v_count <> 3 then
      raise exception 'assertion failed: service_role must see all 3 priority rows via app.list_vehicle_tracking_source_priorities, got %', v_count;
    end if;

    select count(*) into v_count from public.list_vehicle_tracking_source_priorities(v_vehicle_master_id);
    if v_count <> 3 then
      raise exception 'assertion failed: service_role must see all 3 priority rows via public.list_vehicle_tracking_source_priorities, got %', v_count;
    end if;

    raise notice 'service_role proof: BYPASSRLS reads succeed via both app.* and public.* on the spot-checked functions, regardless of RLS';
  end $$;
  reset role;
commit;

\echo '>> schema-privilege defense in depth: anon holds zero EXECUTE on any of the 7 new cluster-4-batch-1 function pairs (14 functions) in EITHER schema (app or public); authenticated/service_role (spot-checked on 3 of the 7 pairs) hold EXECUTE on both the app.* function and its public.* wrapper, exactly as this migration''s own GRANT PARITY section declares'
do $$
declare
  v_count integer;
begin
  select count(*) into v_count
  from information_schema.routine_privileges
  where routine_schema in ('app', 'public')
    and routine_name in (
      'list_vehicle_operational_profiles',
      'list_driver_operational_profiles',
      'list_gps_devices',
      'list_sim_cards',
      'list_device_vehicle_assignment_history',
      'list_provider_vehicle_mappings',
      'list_vehicle_tracking_source_priorities'
    )
    and grantee = 'anon';
  if v_count <> 0 then
    raise exception 'assertion failed: anon must hold zero EXECUTE on any of the 7 cluster-4-batch-1 function pairs (14 functions, either schema), found % grants', v_count;
  end if;

  -- Spot-check 3 of the 7: authenticated AND service_role both hold EXECUTE on the
  -- app.* function AND its public.* wrapper (grant parity, ISS-2026-309).
  select count(*) into v_count
  from information_schema.routine_privileges
  where routine_schema in ('app', 'public')
    and routine_name in ('list_gps_devices', 'list_device_vehicle_assignment_history', 'list_vehicle_tracking_source_priorities')
    and grantee in ('authenticated', 'service_role');
  if v_count <> 3 * 2 * 2 then
    raise exception 'assertion failed: expected exactly 12 grants (3 functions x 2 schemas x 2 grantees) for the spot-checked functions, found %', v_count;
  end if;

  raise notice 'schema-privilege proof: anon holds zero EXECUTE on any of the 14 new cluster-4-batch-1 functions; authenticated/service_role hold the declared grant on both the app.* and public.* spot-checked functions';
end $$;

\echo '>> o1-query-layer-cluster4-batch1.sql test suite passed -- cluster 4 batch 1 (vehicle operational profiles, driver operational profiles, GPS devices, SIM cards, device-vehicle assignment history, provider vehicle mappings, vehicle tracking source priorities, 7/7 call sites) is now fully DONE'
