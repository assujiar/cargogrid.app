-- Real, executable test evidence for ATW-223 (CG-S10-ATW-004, Prompt 223 Fleet,
-- Vehicle, Driver, Device and SIM Operational Baseline) -- run via `pnpm run db:test`
-- against a real, disposable Postgres database.

\set ON_ERROR_STOP on

\echo '>> setup: one tenant, a company/team-a/team-b org hierarchy, a rep (OPS:Create/Edit/Assign), an OPS-viewer-only actor, a sibling-team outsider, a global Supreme Admin'
do $$
declare
  v_tenant1 uuid;
  v_team_a uuid;
  v_rep_role uuid;
  v_rep_draft app.role_versions;
  v_viewer_role uuid;
  v_viewer_draft app.role_versions;
begin
  insert into auth.users (id, email) values
    ('00000000-0000-0000-0000-000000039201', 'admin@acmefleet.test'),
    ('00000000-0000-0000-0000-000000039202', 'repa@acmefleet.test'),
    ('00000000-0000-0000-0000-000000039203', 'viewer@acmefleet.test'),
    ('00000000-0000-0000-0000-000000039204', 'supreme@acmefleet.test');

  perform app.grant_principal_membership('00000000-0000-0000-0000-000000039204', 'supreme_admin', null, null, 'tester');

  perform app.provision_tenant('acmefleet', 'Acme Fleet Co', 'idem-acmefleet', 'tester');
  v_tenant1 := (select id from app.tenants where slug = 'acmefleet');
  perform app.transition_tenant_status(v_tenant1, 'active', 'setup', 'tester');

  perform app.create_org_unit(v_tenant1, 'company', null, 'ACMEFLEET-CO', 'Acme Fleet Co', 'tester');
  v_team_a := (select id from app.org_units where tenant_id = v_tenant1 and code = 'ACMEFLEET-CO');

  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000039201', 'admin@acmefleet.test', 'Fleet Admin', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'admin@acmefleet.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000039201', 'tenant_admin', v_tenant1, null, 'tester');

  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000039202', 'repa@acmefleet.test', 'Rep A', v_team_a, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'repa@acmefleet.test'), 'active', 'onboarded', 'tester');
  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000039203', 'viewer@acmefleet.test', 'OPS Viewer', v_team_a, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'viewer@acmefleet.test'), 'active', 'onboarded', 'tester');

  v_rep_role := (app.create_role(v_tenant1, 'Fleet Rep', 'full ops grants', 'tester')).id;
  v_rep_draft := app.create_role_version(v_rep_role, 'tester');
  perform app.set_role_version_permissions(
    v_rep_draft.id,
    array(select id from app.permissions where resource_module_code = 'OPS' and action in ('Create', 'Edit', 'View', 'Assign')),
    'tester'
  );
  perform app.publish_role_version(v_rep_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_rep_role and status = 'published'), '00000000-0000-0000-0000-000000039202', '00000000-0000-0000-0000-000000039201', 'tester');
  -- Registering a new vehicle/driver identity delegates to app.create_master_record
  -- (PLT-120), which requires tenant_admin/Supreme authority regardless of any OPS
  -- role grant -- so the tenant_admin also needs the same OPS grants to exercise
  -- app.register_vehicle_operational_profile/register_driver_operational_profile
  -- themselves (the same "Ops Admin" actor Prompt 223 §21 itself names). Granted by
  -- the Supreme Admin to avoid any self-assignment question.
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_rep_role and status = 'published'), '00000000-0000-0000-0000-000000039201', '00000000-0000-0000-0000-000000039204', 'tester');

  v_viewer_role := (app.create_role(v_tenant1, 'Fleet Ops Viewer', 'OPS:View only', 'tester')).id;
  v_viewer_draft := app.create_role_version(v_viewer_role, 'tester');
  perform app.set_role_version_permissions(v_viewer_draft.id, array(select id from app.permissions where resource_module_code = 'OPS' and action in ('View')), 'tester');
  perform app.publish_role_version(v_viewer_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_viewer_role and status = 'published'), '00000000-0000-0000-0000-000000039203', '00000000-0000-0000-0000-000000039203', 'tester');
end $$;

\echo '>> app.register_vehicle_operational_profile / app.register_driver_operational_profile: authority-gated, idempotent, reuse app.master_records (never a second identity table)'
do $$
declare
  v_tenant1 uuid;
  v_vehicle app.vehicle_operational_profiles;
  v_vehicle_retry app.vehicle_operational_profiles;
  v_driver app.driver_operational_profiles;
  v_master_count integer;
begin
  v_tenant1 := (select id from app.tenants where slug = 'acmefleet');

  begin
    perform app.register_vehicle_operational_profile(v_tenant1, 'VEH-001', 'Truck 001', 'owned', 5000, 20, '00000000-0000-0000-0000-000000039203', 'viewer');
    raise exception 'assertion failed: expected insufficient_authority for an OPS:View-only actor';
  exception
    when others then
      if sqlerrm not like 'insufficient_authority%' then raise; end if;
  end;

  select * into v_vehicle from app.register_vehicle_operational_profile(v_tenant1, 'VEH-001', 'Truck 001', 'owned', 5000, 20, '00000000-0000-0000-0000-000000039201', 'admin');
  if v_vehicle.ownership_type <> 'owned' then
    raise exception 'assertion failed: expected ownership_type owned';
  end if;

  select count(*) into v_master_count from app.master_records where master_type_code = 'vehicle' and code = 'VEH-001' and tenant_id = v_tenant1;
  if v_master_count <> 1 then
    raise exception 'assertion failed: expected exactly one vehicle master record, found %', v_master_count;
  end if;

  select * into v_vehicle_retry from app.register_vehicle_operational_profile(v_tenant1, 'VEH-001', 'Truck 001', 'owned', 5000, 20, '00000000-0000-0000-0000-000000039201', 'admin');
  if v_vehicle_retry.id <> v_vehicle.id then
    raise exception 'assertion failed: expected the idempotent repeated call to return the same profile row';
  end if;

  select * into v_driver from app.register_driver_operational_profile(v_tenant1, 'DRV-001', 'Budi Santoso', 'B2', '2028-01-01', '00000000-0000-0000-0000-000000039201', 'admin');
  if v_driver.mobile_tracking_consent is not false then
    raise exception 'assertion failed: expected mobile_tracking_consent to default to false';
  end if;
end $$;

\echo '>> app.set_vehicle_tracking_eligibility / app.set_driver_mobile_tracking_consent: capability flags only, never entitlement; consent timestamp cleared on revoke'
do $$
declare
  v_vehicle app.vehicle_operational_profiles;
  v_driver app.driver_operational_profiles;
begin
  select * into v_vehicle from app.vehicle_operational_profiles where vehicle_master_id = (select id from app.master_records where code = 'VEH-001');
  select * into v_vehicle from app.set_vehicle_tracking_eligibility(v_vehicle.id, true, true, false, v_vehicle.record_version, '00000000-0000-0000-0000-000000039202', 'rep');
  if not v_vehicle.mobile_tracking_eligible or not v_vehicle.direct_device_tracking_eligible or v_vehicle.third_party_tracking_eligible then
    raise exception 'assertion failed: expected mobile+direct_device eligible, third_party not';
  end if;

  select * into v_driver from app.driver_operational_profiles where driver_master_id = (select id from app.master_records where code = 'DRV-001');
  select * into v_driver from app.set_driver_mobile_tracking_consent(v_driver.id, true, v_driver.record_version, '00000000-0000-0000-0000-000000039202', 'rep');
  if not v_driver.mobile_tracking_consent or v_driver.mobile_tracking_consent_at is null then
    raise exception 'assertion failed: expected consent granted with a real timestamp';
  end if;

  select * into v_driver from app.set_driver_mobile_tracking_consent(v_driver.id, false, v_driver.record_version, '00000000-0000-0000-0000-000000039202', 'rep');
  if v_driver.mobile_tracking_consent or v_driver.mobile_tracking_consent_at is not null then
    raise exception 'assertion failed: expected consent revoked and timestamp cleared';
  end if;
end $$;

\echo '>> app.register_gps_device / app.transition_gps_device_status: idempotent on IMEI, hardcoded status edges, retired is terminal'
do $$
declare
  v_tenant1 uuid;
  v_device app.gps_devices;
  v_device_retry app.gps_devices;
begin
  v_tenant1 := (select id from app.tenants where slug = 'acmefleet');

  select * into v_device from app.register_gps_device(v_tenant1, '868712345678901', 'Teltonika FMB920', 'cargogrid', '00000000-0000-0000-0000-000000039202', 'rep');
  if v_device.status <> 'stock' then
    raise exception 'assertion failed: expected a new device to start in stock status';
  end if;

  select * into v_device_retry from app.register_gps_device(v_tenant1, '868712345678901', 'Teltonika FMB920', 'cargogrid', '00000000-0000-0000-0000-000000039202', 'rep');
  if v_device_retry.id <> v_device.id then
    raise exception 'assertion failed: expected the idempotent repeated registration to return the same device row';
  end if;

  begin
    perform app.transition_gps_device_status(v_device.id, 'active', v_device.record_version, '00000000-0000-0000-0000-000000039202', 'rep');
    raise exception 'assertion failed: expected invalid_device_status_transition -- stock cannot jump straight to active';
  exception
    when others then
      if sqlerrm not like 'invalid_device_status_transition%' then raise; end if;
  end;

  select * into v_device from app.transition_gps_device_status(v_device.id, 'assigned', v_device.record_version, '00000000-0000-0000-0000-000000039202', 'rep');
  select * into v_device from app.transition_gps_device_status(v_device.id, 'installed', v_device.record_version, '00000000-0000-0000-0000-000000039202', 'rep');
  select * into v_device from app.transition_gps_device_status(v_device.id, 'active', v_device.record_version, '00000000-0000-0000-0000-000000039202', 'rep');
  select * into v_device from app.transition_gps_device_status(v_device.id, 'retired', v_device.record_version, '00000000-0000-0000-0000-000000039202', 'rep');

  begin
    perform app.transition_gps_device_status(v_device.id, 'active', v_device.record_version, '00000000-0000-0000-0000-000000039202', 'rep');
    raise exception 'assertion failed: expected invalid_device_status_transition -- retired is terminal';
  exception
    when others then
      if sqlerrm not like 'invalid_device_status_transition%' then raise; end if;
  end;
end $$;

\echo '>> app.assign_device_to_vehicle / app.unassign_device_from_vehicle: one device has at most one current vehicle, history preserved, retired device rejected'
do $$
declare
  v_tenant1 uuid;
  v_device1 app.gps_devices;
  v_device2 app.gps_devices;
  v_vehicle1 app.vehicle_operational_profiles;
  v_vehicle2 app.vehicle_operational_profiles;
  v_assign1 app.device_vehicle_assignments;
  v_assign2 app.device_vehicle_assignments;
  v_history_count integer;
  v_current_count integer;
begin
  v_tenant1 := (select id from app.tenants where slug = 'acmefleet');

  select * into v_device1 from app.register_gps_device(v_tenant1, '868712345678902', 'Teltonika FMB920', 'cargogrid', '00000000-0000-0000-0000-000000039202', 'rep');
  select * into v_device2 from app.register_gps_device(v_tenant1, '868712345678903', 'Teltonika FMB920', 'cargogrid', '00000000-0000-0000-0000-000000039202', 'rep');
  select * into v_vehicle1 from app.register_vehicle_operational_profile(v_tenant1, 'VEH-002', 'Truck 002', 'owned', 4000, 15, '00000000-0000-0000-0000-000000039201', 'admin');
  select * into v_vehicle2 from app.register_vehicle_operational_profile(v_tenant1, 'VEH-003', 'Truck 003', 'owned', 4000, 15, '00000000-0000-0000-0000-000000039201', 'admin');

  select * into v_assign1 from app.assign_device_to_vehicle(v_device1.id, v_vehicle1.id, 'initial install', '00000000-0000-0000-0000-000000039202', 'rep');
  if not v_assign1.is_current then
    raise exception 'assertion failed: expected the first assignment to be current';
  end if;

  select * into v_assign2 from app.assign_device_to_vehicle(v_device1.id, v_vehicle2.id, 'reassigned to a different truck', '00000000-0000-0000-0000-000000039202', 'rep');
  if not v_assign2.is_current then
    raise exception 'assertion failed: expected the second assignment to be current';
  end if;

  select count(*) into v_history_count from app.device_vehicle_assignments where device_id = v_device1.id;
  if v_history_count <> 2 then
    raise exception 'assertion failed: expected both assignments preserved (history never overwritten), found %', v_history_count;
  end if;

  select count(*) into v_current_count from app.device_vehicle_assignments where device_id = v_device1.id and is_current;
  if v_current_count <> 1 then
    raise exception 'assertion failed: expected exactly one current assignment for device 1, found %', v_current_count;
  end if;

  if (select is_current from app.device_vehicle_assignments where id = v_assign1.id) is not false then
    raise exception 'assertion failed: expected the first assignment to have been superseded (is_current=false)';
  end if;
  if (select superseded_by_id from app.device_vehicle_assignments where id = v_assign1.id) <> v_assign2.id then
    raise exception 'assertion failed: expected the first assignment to point at the second as its own superseded_by_id';
  end if;

  perform app.unassign_device_from_vehicle(v_device1.id, 'test: unassign', '00000000-0000-0000-0000-000000039202', 'rep');
  if exists (select 1 from app.device_vehicle_assignments where device_id = v_device1.id and is_current) then
    raise exception 'assertion failed: expected no current assignment after unassign';
  end if;

  perform app.assign_device_to_vehicle(v_device2.id, v_vehicle1.id, 'installed on truck 002', '00000000-0000-0000-0000-000000039202', 'rep');
  select * into v_device2 from app.transition_gps_device_status(v_device2.id, 'assigned', v_device2.record_version, '00000000-0000-0000-0000-000000039202', 'rep');
  select * into v_device2 from app.transition_gps_device_status(v_device2.id, 'installed', v_device2.record_version, '00000000-0000-0000-0000-000000039202', 'rep');
  select * into v_device2 from app.transition_gps_device_status(v_device2.id, 'active', v_device2.record_version, '00000000-0000-0000-0000-000000039202', 'rep');
  select * into v_device2 from app.transition_gps_device_status(v_device2.id, 'retired', v_device2.record_version, '00000000-0000-0000-0000-000000039202', 'rep');

  begin
    perform app.assign_device_to_vehicle(v_device2.id, v_vehicle2.id, 'should fail', '00000000-0000-0000-0000-000000039202', 'rep');
    raise exception 'assertion failed: expected device_retired -- a retired device cannot be assigned';
  exception
    when others then
      if sqlerrm not like 'device_retired%' then raise; end if;
  end;
end $$;

\echo '>> app.register_sim_card / app.assign_sim_to_device / app.unassign_sim_from_device: idempotent on ICCID, at most one SIM per device'
do $$
declare
  v_tenant1 uuid;
  v_sim1 app.sim_cards;
  v_sim2 app.sim_cards;
  v_device app.gps_devices;
begin
  v_tenant1 := (select id from app.tenants where slug = 'acmefleet');
  select * into v_device from app.gps_devices where imei = '868712345678902';

  select * into v_sim1 from app.register_sim_card(v_tenant1, '8901260123456789012', '628111111111', 'Telkomsel', '00000000-0000-0000-0000-000000039202', 'rep');
  select * into v_sim2 from app.register_sim_card(v_tenant1, '8901260123456789013', '628222222222', 'Telkomsel', '00000000-0000-0000-0000-000000039202', 'rep');

  perform app.assign_sim_to_device(v_sim1.id, v_device.id, '00000000-0000-0000-0000-000000039202', 'rep');

  begin
    perform app.assign_sim_to_device(v_sim2.id, v_device.id, '00000000-0000-0000-0000-000000039202', 'rep');
    raise exception 'assertion failed: expected device_already_has_sim';
  exception
    when others then
      if sqlerrm not like 'device_already_has_sim%' then raise; end if;
  end;

  perform app.unassign_sim_from_device(v_sim1.id, '00000000-0000-0000-0000-000000039202', 'rep');
  perform app.assign_sim_to_device(v_sim2.id, v_device.id, '00000000-0000-0000-0000-000000039202', 'rep');
  if (select current_device_id from app.sim_cards where id = v_sim2.id) <> v_device.id then
    raise exception 'assertion failed: expected sim2 now assigned to the device after sim1 was released';
  end if;
end $$;

\echo '>> app.register_provider_vehicle_mapping: idempotent, distinct external IDs never collide silently'
do $$
declare
  v_tenant1 uuid;
  v_vehicle_master_id uuid;
  v_mapping1 app.provider_vehicle_mappings;
  v_mapping_retry app.provider_vehicle_mappings;
begin
  v_tenant1 := (select id from app.tenants where slug = 'acmefleet');
  v_vehicle_master_id := (select id from app.master_records where code = 'VEH-001' and tenant_id = v_tenant1);

  select * into v_mapping1 from app.register_provider_vehicle_mapping(v_tenant1, v_vehicle_master_id, 'contoso_fleet', 'EXT-001', '00000000-0000-0000-0000-000000039202', 'rep');
  select * into v_mapping_retry from app.register_provider_vehicle_mapping(v_tenant1, v_vehicle_master_id, 'contoso_fleet', 'EXT-001', '00000000-0000-0000-0000-000000039202', 'rep');
  if v_mapping_retry.id <> v_mapping1.id then
    raise exception 'assertion failed: expected idempotent mapping registration';
  end if;

  begin
    perform app.register_provider_vehicle_mapping(
      v_tenant1, (select id from app.master_records where code = 'VEH-002' and tenant_id = v_tenant1), 'contoso_fleet', 'EXT-001', '00000000-0000-0000-0000-000000039202', 'rep'
    );
    raise exception 'assertion failed: expected provider_external_id_collision -- EXT-001 is already mapped for contoso_fleet';
  exception
    when others then
      if sqlerrm not like 'provider_external_id_collision%' then raise; end if;
  end;
end $$;

\echo '>> app.set_vehicle_tracking_source_priority: upsert, one row per (vehicle, source_type)'
do $$
declare
  v_tenant1 uuid;
  v_vehicle_master_id uuid;
  v_priority app.vehicle_tracking_source_priorities;
  v_count integer;
begin
  v_tenant1 := (select id from app.tenants where slug = 'acmefleet');
  v_vehicle_master_id := (select id from app.master_records where code = 'VEH-001' and tenant_id = v_tenant1);

  select * into v_priority from app.set_vehicle_tracking_source_priority(v_tenant1, v_vehicle_master_id, 'driver_mobile', 1, true, '00000000-0000-0000-0000-000000039202', 'rep');
  perform app.set_vehicle_tracking_source_priority(v_tenant1, v_vehicle_master_id, 'direct_device', 2, true, '00000000-0000-0000-0000-000000039202', 'rep');
  select * into v_priority from app.set_vehicle_tracking_source_priority(v_tenant1, v_vehicle_master_id, 'driver_mobile', 3, false, '00000000-0000-0000-0000-000000039202', 'rep');
  if v_priority.priority_rank <> 3 or v_priority.is_enabled is not false then
    raise exception 'assertion failed: expected the upsert to overwrite the existing driver_mobile row, not create a second one';
  end if;

  select count(*) into v_count from app.vehicle_tracking_source_priorities where vehicle_master_id = v_vehicle_master_id;
  if v_count <> 2 then
    raise exception 'assertion failed: expected exactly 2 priority rows (driver_mobile, direct_device), found %', v_count;
  end if;
end $$;

\echo '>> cross-tenant isolation: app.register_vehicle_operational_profile/app.assign_device_to_vehicle fail closed for an identity with no membership in the target tenant'
do $$
declare
  v_tenant1 uuid;
  v_tenant2 uuid;
  v_device_id uuid;
  v_vehicle_id uuid;
begin
  insert into auth.users (id, email) values ('00000000-0000-0000-0000-000000039205', 'admin2@acmefleet2.test');
  perform app.provision_tenant('acmefleet2', 'Acme Fleet Co 2', 'idem-acmefleet2', 'tester');
  v_tenant2 := (select id from app.tenants where slug = 'acmefleet2');
  perform app.transition_tenant_status(v_tenant2, 'active', 'setup', 'tester');
  perform app.invite_user(v_tenant2, '00000000-0000-0000-0000-000000039205', 'admin2@acmefleet2.test', 'Tenant 2 Admin', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'admin2@acmefleet2.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000039205', 'tenant_admin', v_tenant2, null, 'tester');

  v_tenant1 := (select id from app.tenants where slug = 'acmefleet');
  select id into v_device_id from app.gps_devices where imei = '868712345678902';
  select id into v_vehicle_id from app.vehicle_operational_profiles where vehicle_master_id = (select id from app.master_records where code = 'VEH-003' and tenant_id = v_tenant1);

  begin
    perform app.register_vehicle_operational_profile(v_tenant1, 'VEH-INTRUDER', 'Should Fail', 'owned', null, null, '00000000-0000-0000-0000-000000039205', 'tenant2-admin');
    raise exception 'assertion failed: expected insufficient_privilege -- tenant 2''s admin holds no OPS:Create in tenant 1';
  exception
    when others then
      if sqlerrm not like 'insufficient_authority%' then raise; end if;
  end;

  begin
    perform app.assign_device_to_vehicle(v_device_id, v_vehicle_id, 'should fail', '00000000-0000-0000-0000-000000039205', 'tenant2-admin');
    raise exception 'assertion failed: expected insufficient_privilege -- tenant 2''s admin holds no OPS:Assign in tenant 1';
  exception
    when others then
      if sqlerrm not like 'insufficient_authority%' then raise; end if;
  end;
end $$;

\echo '>> record-scope: a same-tenant OPS:View-only actor can read but cannot mutate fleet/driver/device resources despite the tenant-wide (not owner-scoped) read policy'
do $$
declare
  v_row_count integer;
begin
  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000039203", "role": "authenticated"}';
  select count(*) into v_row_count from app.vehicle_operational_profiles;
  reset role;
  if v_row_count = 0 then
    raise exception 'assertion failed: expected the OPS:View-only actor to see the tenant''s own vehicle profiles (tenant-wide read, not owner-scoped)';
  end if;

  begin
    perform app.register_vehicle_operational_profile(
      (select id from app.tenants where slug = 'acmefleet'), 'VEH-VIEWER-DENIED', 'Should Fail', 'owned', null, null, '00000000-0000-0000-0000-000000039203', 'viewer'
    );
    raise exception 'assertion failed: expected insufficient_authority -- viewer holds OPS:View only, not OPS:Create';
  exception
    when others then
      if sqlerrm not like 'insufficient_authority%' then raise; end if;
  end;
end $$;

\echo '>> schema-privilege defense in depth: anon holds no EXECUTE on any of the 13 new functions; authenticated has no direct INSERT/UPDATE/DELETE on any of the 7 new tables'
do $$
declare
  v_count integer;
begin
  select count(*) into v_count
  from information_schema.routine_privileges
  where routine_schema = 'app'
    and grantee = 'anon'
    and routine_name in (
      'register_vehicle_operational_profile', 'set_vehicle_tracking_eligibility', 'register_driver_operational_profile',
      'set_driver_mobile_tracking_consent', 'register_gps_device', 'transition_gps_device_status',
      'assign_device_to_vehicle', 'unassign_device_from_vehicle', 'register_sim_card', 'assign_sim_to_device',
      'unassign_sim_from_device', 'register_provider_vehicle_mapping', 'set_vehicle_tracking_source_priority'
    );
  if v_count <> 0 then
    raise exception 'assertion failed: expected zero anon EXECUTE grants on the 13 new functions, found %', v_count;
  end if;

  select count(*) into v_count
  from information_schema.role_table_grants
  where table_schema = 'app'
    and grantee = 'authenticated'
    and privilege_type in ('INSERT', 'UPDATE', 'DELETE')
    and table_name in (
      'vehicle_operational_profiles', 'driver_operational_profiles', 'gps_devices', 'sim_cards',
      'device_vehicle_assignments', 'provider_vehicle_mappings', 'vehicle_tracking_source_priorities'
    );
  if v_count <> 0 then
    raise exception 'assertion failed: expected zero authenticated INSERT/UPDATE/DELETE grants on the 7 new tables, found %', v_count;
  end if;
end $$;

\echo '>> audit trail: every real fleet/driver/device mutation recorded a real app.audit_logs event, tenant-scoped'
do $$
declare
  v_tenant1 uuid;
  v_count integer;
begin
  v_tenant1 := (select id from app.tenants where slug = 'acmefleet');

  select count(*) into v_count from app.audit_logs where tenant_id = v_tenant1 and resource_type = 'app.vehicle_operational_profiles' and action = 'register_vehicle_operational_profile';
  if v_count <> 3 then
    raise exception 'assertion failed: expected exactly 3 register_vehicle_operational_profile audit events (VEH-001, VEH-002, VEH-003; the idempotent retry is not counted), found %', v_count;
  end if;

  select count(*) into v_count from app.audit_logs where tenant_id = v_tenant1 and resource_type = 'app.device_vehicle_assignments' and action = 'assign_device_to_vehicle';
  if v_count <> 3 then
    raise exception 'assertion failed: expected exactly 3 assign_device_to_vehicle audit events (device1->vehicle1, device1->vehicle2, device2->vehicle1), found %', v_count;
  end if;
end $$;
