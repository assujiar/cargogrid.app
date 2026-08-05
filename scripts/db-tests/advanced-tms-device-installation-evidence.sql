-- Real, executable test evidence for ATW-226B (CG-S10-ATW-006's family, Prompt 226
-- decomposition "Device, SIM, provider, installation, and mapping management") -- run
-- via `pnpm run db:test` against a real, disposable Postgres database.

\set ON_ERROR_STOP on

\echo '>> setup: one tenant, an OPS:Edit-capable rep, an OPS:View-only viewer, a Supreme Admin, one registered/assigned GPS device on one active vehicle, the gps_device_installation document type published'
do $$
declare
  v_tenant1 uuid;
  v_edit_role uuid;
  v_edit_draft app.role_versions;
  v_viewer_role uuid;
  v_viewer_draft app.role_versions;
  v_vehicle_master uuid;
  v_vehicle_profile app.vehicle_operational_profiles;
  v_device app.gps_devices;
  v_doc_draft app.config_versions;
begin
  insert into auth.users (id, email) values
    ('00000000-0000-0000-0000-000000041101', 'admin@acmeinstall.test'),
    ('00000000-0000-0000-0000-000000041102', 'viewer@acmeinstall.test'),
    ('00000000-0000-0000-0000-000000041103', 'supreme@acmeinstall.test');

  perform app.grant_principal_membership('00000000-0000-0000-0000-000000041103', 'supreme_admin', null, null, 'tester');

  perform app.provision_tenant('acmeinstall', 'Acme Install Co', 'idem-acmeinstall', 'tester');
  v_tenant1 := (select id from app.tenants where slug = 'acmeinstall');
  perform app.transition_tenant_status(v_tenant1, 'active', 'setup', 'tester');

  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000041101', 'admin@acmeinstall.test', 'Install Admin', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'admin@acmeinstall.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000041101', 'tenant_admin', v_tenant1, null, 'tester');

  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000041102', 'viewer@acmeinstall.test', 'OPS Viewer', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'viewer@acmeinstall.test'), 'active', 'onboarded', 'tester');

  v_edit_role := (app.create_role(v_tenant1, 'Install Editor', 'OPS:Edit/Create/Assign', 'tester')).id;
  v_edit_draft := app.create_role_version(v_edit_role, 'tester');
  perform app.set_role_version_permissions(v_edit_draft.id, array(select id from app.permissions where resource_module_code = 'OPS' and action in ('Edit', 'Create', 'Assign')), 'tester');
  perform app.publish_role_version(v_edit_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_edit_role and status = 'published'), '00000000-0000-0000-0000-000000041101', '00000000-0000-0000-0000-000000041103', 'tester');

  v_viewer_role := (app.create_role(v_tenant1, 'OPS Viewer', 'OPS:View only', 'tester')).id;
  v_viewer_draft := app.create_role_version(v_viewer_role, 'tester');
  perform app.set_role_version_permissions(v_viewer_draft.id, array(select id from app.permissions where resource_module_code = 'OPS' and action = 'View'), 'tester');
  perform app.publish_role_version(v_viewer_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_viewer_role and status = 'published'), '00000000-0000-0000-0000-000000041102', '00000000-0000-0000-0000-000000041103', 'tester');

  perform app.register_vehicle_operational_profile(v_tenant1, 'VEH-INSTALL-001', 'Install Truck 001', 'owned', 5000, 20, '00000000-0000-0000-0000-000000041101', 'admin');
  v_vehicle_master := (select id from app.master_records where tenant_id = v_tenant1 and code = 'VEH-INSTALL-001');
  select * into v_vehicle_profile from app.vehicle_operational_profiles where vehicle_master_id = v_vehicle_master;

  select * into v_device from app.register_gps_device(v_tenant1, '868712345699901', 'Teltonika FMC920', 'cargogrid', '00000000-0000-0000-0000-000000041101', 'admin');
  select * into v_device from app.transition_gps_device_status(v_device.id, 'assigned', v_device.record_version, '00000000-0000-0000-0000-000000041101', 'admin');
  perform app.assign_device_to_vehicle(v_device.id, v_vehicle_profile.id, 'install fixture', '00000000-0000-0000-0000-000000041101', 'admin');

  perform app.register_document_type('gps_device_installation', 'GPS Device Installation Evidence', 'DOC', '00000000-0000-0000-0000-000000041103', 'supreme');
  v_doc_draft := app.create_config_draft('document:gps_device_installation', v_tenant1, 'tenant', null, '00000000-0000-0000-0000-000000041101', 'admin');
  perform app.set_config_items(v_doc_draft.id, jsonb_build_array(
    jsonb_build_object('key', 'allowed_mime_types', 'value', jsonb_build_array('image/jpeg', 'application/pdf')),
    jsonb_build_object('key', 'max_size_bytes', 'value', 5242880),
    jsonb_build_object('key', 'retention_class', 'value', 'operational_contract_plus_90d'),
    jsonb_build_object('key', 'default_classification', 'value', 'internal'),
    jsonb_build_object('key', 'legal_hold_eligible', 'value', false)
  ), '00000000-0000-0000-0000-000000041101', 'admin');
  perform app.publish_document_type_definition(v_doc_draft.id, '00000000-0000-0000-0000-000000041101', now(), 'admin');
end $$;

\echo '>> app.record_gps_device_installation: rejects a not-yet-clean evidence file, a file belonging to a different device, and an empty technician_label -- before ever touching device status'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'acmeinstall');
  v_device_id uuid := (select id from app.gps_devices where imei = '868712345699901');
  v_assignment_id uuid := (select id from app.device_vehicle_assignments where device_id = v_device_id and is_current);
  v_pending_file app.files;
  v_wrong_device app.files;
  v_other_device app.gps_devices;
begin
  select * into v_pending_file from app.initiate_file_upload(
    v_tenant1, 'gps_device_installation', 'gps_device', v_device_id, 'install-photo.jpg', 'image/jpeg', 40960, null, false, null, '{}'::uuid[], null, 'idem-install-pending', '00000000-0000-0000-0000-000000041101', 'admin'
  );

  begin
    perform app.record_gps_device_installation(v_assignment_id, v_pending_file.id, 'Budi Teknisi', 'installed on dashboard', 1, '00000000-0000-0000-0000-000000041101', 'admin');
    raise exception 'assertion failed: expected installation_unsafe_evidence -- file scan status is still pending';
  exception
    when others then
      if sqlerrm not like 'installation_unsafe_evidence%' then raise; end if;
  end;

  perform app.record_file_scan_result(v_pending_file.id, 'clean', 'test-scanner-ref', '00000000-0000-0000-0000-000000041101', 'admin');

  select * into v_other_device from app.register_gps_device(v_tenant1, '868712345699902', 'Teltonika FMC920', 'cargogrid', '00000000-0000-0000-0000-000000041101', 'admin');
  select * into v_wrong_device from app.initiate_file_upload(
    v_tenant1, 'gps_device_installation', 'gps_device', v_other_device.id, 'wrong-device.jpg', 'image/jpeg', 40960, null, false, null, '{}'::uuid[], null, 'idem-install-wrong', '00000000-0000-0000-0000-000000041101', 'admin'
  );
  perform app.record_file_scan_result(v_wrong_device.id, 'clean', 'test-scanner-ref', '00000000-0000-0000-0000-000000041101', 'admin');

  begin
    perform app.record_gps_device_installation(v_assignment_id, v_wrong_device.id, 'Budi Teknisi', null, 1, '00000000-0000-0000-0000-000000041101', 'admin');
    raise exception 'assertion failed: expected installation_evidence_file_mismatch -- file belongs to a different device';
  exception
    when others then
      if sqlerrm not like 'installation_evidence_file_mismatch%' then raise; end if;
  end;

  begin
    perform app.record_gps_device_installation(v_assignment_id, v_pending_file.id, '   ', null, 1, '00000000-0000-0000-0000-000000041101', 'admin');
    raise exception 'assertion failed: expected technician_label_required -- blank label';
  exception
    when others then
      if sqlerrm not like 'technician_label_required%' then raise; end if;
  end;

  if (select status from app.gps_devices where id = v_device_id) <> 'assigned' then
    raise exception 'assertion failed: device status must remain assigned -- every attempt above was rejected before the status transition';
  end if;
end $$;

\echo '>> app.record_gps_device_installation: an OPS:View-only viewer is rejected; a valid call by the OPS:Edit rep evidences the installation AND transitions the device assigned -> installed in one call; a second attempt on the same assignment is rejected'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'acmeinstall');
  v_device_id uuid := (select id from app.gps_devices where imei = '868712345699901');
  v_assignment_id uuid := (select id from app.device_vehicle_assignments where device_id = v_device_id and is_current);
  v_clean_file uuid := (select id from app.files where idempotency_key = 'idem-install-pending');
  v_device_version integer := (select record_version from app.gps_devices where id = v_device_id);
  v_installation app.gps_device_installations;
begin
  begin
    perform app.record_gps_device_installation(v_assignment_id, v_clean_file, 'Budi Teknisi', null, v_device_version, '00000000-0000-0000-0000-000000041102', 'viewer');
    raise exception 'assertion failed: expected insufficient_authority -- viewer holds OPS:View only, not OPS:Edit';
  exception
    when others then
      if sqlerrm not like 'insufficient_authority%' then raise; end if;
  end;

  v_installation := app.record_gps_device_installation(v_assignment_id, v_clean_file, 'Budi Teknisi', 'Installed under dashboard, verified power draw nominal', v_device_version, '00000000-0000-0000-0000-000000041101', 'admin');

  if v_installation.evidence_file_id <> v_clean_file or v_installation.technician_label <> 'Budi Teknisi' or v_installation.verified_by_auth_user_id is not null then
    raise exception 'assertion failed: expected evidence_file_id=%, technician_label=Budi Teknisi, unverified -- got %/%/%', v_clean_file, v_installation.evidence_file_id, v_installation.technician_label, v_installation.verified_by_auth_user_id;
  end if;

  if (select status from app.gps_devices where id = v_device_id) <> 'installed' then
    raise exception 'assertion failed: expected the device to have transitioned assigned -> installed as a side effect of recording real evidence';
  end if;

  begin
    perform app.record_gps_device_installation(v_assignment_id, v_clean_file, 'Someone Else', null, 2, '00000000-0000-0000-0000-000000041101', 'admin');
    raise exception 'assertion failed: expected installation_already_recorded -- this assignment already carries an evidence row';
  exception
    when others then
      if sqlerrm not like 'installation_already_recorded%' then raise; end if;
  end;
end $$;

\echo '>> app.verify_gps_device_installation: OPS:Edit-gated, idempotent-by-reassertion, never mutates the original evidence'
do $$
declare
  v_installation_id uuid := (select id from app.gps_device_installations where tenant_id = (select id from app.tenants where slug = 'acmeinstall') limit 1);
  v_verified app.gps_device_installations;
  v_reverified app.gps_device_installations;
begin
  begin
    perform app.verify_gps_device_installation(v_installation_id, '00000000-0000-0000-0000-000000041102', 'viewer');
    raise exception 'assertion failed: expected insufficient_authority for the OPS:View-only viewer';
  exception
    when others then
      if sqlerrm not like 'insufficient_authority%' then raise; end if;
  end;

  v_verified := app.verify_gps_device_installation(v_installation_id, '00000000-0000-0000-0000-000000041101', 'admin');
  if v_verified.verified_by_auth_user_id <> '00000000-0000-0000-0000-000000041101' or v_verified.verified_at is null then
    raise exception 'assertion failed: expected verified_by_auth_user_id/verified_at to be set';
  end if;

  v_reverified := app.verify_gps_device_installation(v_installation_id, '00000000-0000-0000-0000-000000041103', 'supreme');
  if v_reverified.evidence_file_id <> v_verified.evidence_file_id or v_reverified.technician_label <> v_verified.technician_label then
    raise exception 'assertion failed: re-verification must never mutate the original evidence fields';
  end if;
  if v_reverified.verified_by_auth_user_id <> '00000000-0000-0000-0000-000000041103' then
    raise exception 'assertion failed: expected the second reviewer to overwrite verified_by_auth_user_id, a legitimate real re-review';
  end if;
end $$;

\echo '>> app.record_gps_device_installation: a superseded (non-current) assignment is rejected'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'acmeinstall');
  v_device_id uuid := (select id from app.gps_devices where imei = '868712345699901');
  v_old_assignment_id uuid := (select id from app.device_vehicle_assignments where device_id = v_device_id and is_current);
  v_second_vehicle_master uuid;
  v_second_vehicle_profile app.vehicle_operational_profiles;
  v_second_device_id uuid := (select id from app.gps_devices where imei = '868712345699902');
  v_second_file app.files;
begin
  perform app.register_vehicle_operational_profile(v_tenant1, 'VEH-INSTALL-002', 'Install Truck 002', 'owned', 5000, 20, '00000000-0000-0000-0000-000000041101', 'admin');
  v_second_vehicle_master := (select id from app.master_records where tenant_id = v_tenant1 and code = 'VEH-INSTALL-002');
  select * into v_second_vehicle_profile from app.vehicle_operational_profiles where vehicle_master_id = v_second_vehicle_master;

  -- Reassigning the same device supersedes its own prior current assignment (ATW-223's
  -- own already-verified behavior) -- v_old_assignment_id becomes non-current.
  perform app.assign_device_to_vehicle(v_device_id, v_second_vehicle_profile.id, 'reassigned for supersede test', '00000000-0000-0000-0000-000000041101', 'admin');

  select * into v_second_file from app.initiate_file_upload(
    v_tenant1, 'gps_device_installation', 'gps_device', v_second_device_id, 'stale-assignment.jpg', 'image/jpeg', 40960, null, false, null, '{}'::uuid[], null, 'idem-install-stale', '00000000-0000-0000-0000-000000041101', 'admin'
  );
  perform app.record_file_scan_result(v_second_file.id, 'clean', 'test-scanner-ref', '00000000-0000-0000-0000-000000041101', 'admin');

  begin
    perform app.record_gps_device_installation(v_old_assignment_id, v_second_file.id, 'Late Tech', null, 3, '00000000-0000-0000-0000-000000041101', 'admin');
    raise exception 'assertion failed: expected assignment_not_current -- this assignment was superseded by the reassignment above';
  exception
    when others then
      if sqlerrm not like 'assignment_not_current%' then raise; end if;
  end;
end $$;

\echo '>> RLS: tenant-wide read; schema-privilege defense in depth: anon holds no EXECUTE on either new function, authenticated has no direct INSERT/UPDATE/DELETE on the 1 new table'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'acmeinstall');
  v_row_count integer;
  v_count integer;
begin
  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000041102", "role": "authenticated"}';
  select count(*) into v_row_count from app.gps_device_installations where tenant_id = v_tenant1;
  reset role;
  if v_row_count <> 1 then
    raise exception 'assertion failed: expected the tenant''s own OPS:View-only viewer to see the one recorded installation, found %', v_row_count;
  end if;

  select count(*) into v_count
  from information_schema.routine_privileges
  where routine_schema = 'app' and grantee = 'anon'
    and routine_name in ('record_gps_device_installation', 'verify_gps_device_installation');
  if v_count <> 0 then
    raise exception 'assertion failed: expected zero anon EXECUTE grants on the 2 new functions, found %', v_count;
  end if;

  select count(*) into v_count
  from information_schema.role_table_grants
  where table_schema = 'app' and grantee = 'authenticated'
    and privilege_type in ('INSERT', 'UPDATE', 'DELETE') and table_name = 'gps_device_installations';
  if v_count <> 0 then
    raise exception 'assertion failed: expected zero authenticated INSERT/UPDATE/DELETE grants on gps_device_installations, found %', v_count;
  end if;
end $$;

\echo '>> audit trail: the one real record_gps_device_installation and the two real verify_gps_device_installation calls each recorded a real app.audit_logs event, tenant-scoped'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'acmeinstall');
  v_count integer;
begin
  select count(*) into v_count from app.audit_logs
  where tenant_id = v_tenant1 and resource_type = 'app.gps_device_installations' and action = 'record_gps_device_installation';
  if v_count <> 1 then
    raise exception 'assertion failed: expected exactly 1 record_gps_device_installation audit event, found %', v_count;
  end if;

  select count(*) into v_count from app.audit_logs
  where tenant_id = v_tenant1 and resource_type = 'app.gps_device_installations' and action = 'verify_gps_device_installation';
  if v_count <> 2 then
    raise exception 'assertion failed: expected exactly 2 verify_gps_device_installation audit events, found %', v_count;
  end if;
end $$;

\echo '>> ATW-031 (ISS-2026-028): the evidence gate is enforced by the GRANT BOUNDARY, in the database, not merely absent from the UI. app.transition_gps_device_status is no longer granted to authenticated/service_role -- it is the internal status-machine core -- and the one entry point clients do hold, app.request_gps_device_status_transition, refuses installed outright. Before this, any caller holding ordinary OPS:Edit (the operations/fleet workspace UI among them) could mark a device installed with no evidence whatsoever.'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'acmeinstall');
  v_device app.gps_devices;
  v_after app.gps_devices;
  v_count integer;
  v_raised boolean := false;
begin
  select * into v_device from app.register_gps_device(v_tenant1, '868712345699977', 'Teltonika FMC920', 'cargogrid', '00000000-0000-0000-0000-000000041101', 'admin');
  select * into v_device from app.request_gps_device_status_transition(v_device.id, 'assigned', v_device.record_version, '00000000-0000-0000-0000-000000041101', 'admin');

  -- 1. The bypass is closed: the client-reachable entry point refuses installed.
  begin
    perform app.request_gps_device_status_transition(v_device.id, 'installed', v_device.record_version, '00000000-0000-0000-0000-000000041101', 'admin');
    raise exception 'assertion failed: the client-reachable transition entry point still moved a device to installed with zero evidence -- the ISS-2026-028 bypass is open';
  exception
    when check_violation then
      if sqlerrm !~ 'installation_evidence_required' then raise; end if;
      v_raised := true;
  end;
  if not v_raised then
    raise exception 'assertion failed: expected installation_evidence_required';
  end if;

  -- 2. The device really did not move.
  select * into v_after from app.gps_devices where id = v_device.id;
  if v_after.status <> 'assigned' then
    raise exception 'assertion failed: expected the rejected device to remain assigned, got %', v_after.status;
  end if;

  -- 3. Every other transition still works through the same entry point -- the gate is
  --    surgical, not a blanket block on the status machine.
  select * into v_after from app.request_gps_device_status_transition(v_after.id, 'retired', v_after.record_version, '00000000-0000-0000-0000-000000041101', 'admin');
  if v_after.status <> 'retired' then
    raise exception 'assertion failed: expected a non-installed transition to still succeed, got %', v_after.status;
  end if;

  -- 4. The grant boundary IS the enforcement: neither authenticated nor service_role may
  --    reach the internal core directly, so there is no second route to installed.
  select count(*) into v_count
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  cross join lateral aclexplode(p.proacl) acl
  where n.nspname = 'app' and p.proname = 'transition_gps_device_status'
    and acl.privilege_type = 'EXECUTE'
    and pg_get_userbyid(acl.grantee) in ('anon', 'authenticated', 'service_role');
  if v_count <> 0 then
    raise exception 'assertion failed: app.transition_gps_device_status must carry NO anon/authenticated/service_role EXECUTE grant -- found %', v_count;
  end if;

  raise notice 'ATW-031 evidence-gate proof: the client-reachable entry point refuses installed and leaves the device untouched, every other transition still works, and the internal core carries zero client grant -- app.record_gps_device_installation is the only route to installed';
end $$;

\echo 'advanced-tms-device-installation-evidence.sql: ALL PASSED'
