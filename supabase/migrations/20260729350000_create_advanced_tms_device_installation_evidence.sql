-- Advanced TMS capability ATW-226B (Prompt 226 decomposition child, "Device, SIM,
-- provider, installation, and mapping management" -- docs/build-log/phase-05/
-- ADVANCED_TMS_WMS_EXECUTION_INDEX.md §1.4).
--
-- Design boundary (disclosed): ATW-223 (20260729310000) already built the device/SIM/
-- provider-mapping/mobile-eligibility inventory layer in full: app.gps_devices (8-state
-- status machine including 'installed'), app.sim_cards, app.device_vehicle_assignments
-- (append-only assignment history), app.provider_vehicle_mappings, and mobile
-- eligibility/consent flags on app.vehicle_operational_profiles/
-- app.driver_operational_profiles. A direct re-read of that migration found no
-- duplicate-worthy gap in device/SIM/provider identity or mapping -- re-building any of
-- that here would violate AGENTS.md's "do not create duplicate... schemas... because an
-- existing implementation was not searched thoroughly."
--
-- The one genuine, concrete gap: `app.transition_gps_device_status` lets any OPS:Edit
-- actor flip a device straight to 'installed' with zero evidence -- no technician, no
-- date, no proof photo, nothing 226D can later trust before treating that device's own
-- telemetry as attributable to a specific vehicle (219_*.md §16: "treat IMEI as an
-- identifier, not sufficient strong authentication"). This migration closes exactly
-- that gap: real installation evidence, tied to the specific app.device_vehicle_
-- assignments row it documents, reusing the Document and File Engine (PLT-128) exactly
-- the way ATW-176 (ePOD) already established -- a file uploaded against the owning
-- business record (here, the device itself), then linked and clean-scan-validated by
-- this capability's own mutation, never a second file-storage mechanism.
--
-- `app.record_gps_device_installation` composes `app.transition_gps_device_status`
-- (unmodified, called internally) rather than re-implementing the assigned->installed
-- transition -- the device's own status machine remains the single source of truth for
-- device state; this table only adds the evidence a bare status value cannot carry.
--
-- Per ERR-2026-004: this migration carries its own explicit
-- `revoke execute on all functions in schema app from public` statement before its
-- final grants.

create table app.gps_device_installations (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  device_id uuid not null references app.gps_devices (id),
  device_vehicle_assignment_id uuid not null references app.device_vehicle_assignments (id),
  evidence_file_id uuid not null references app.files (id),
  technician_label text not null,
  installation_notes text,
  installed_at timestamptz not null default now(),
  verified_by_auth_user_id uuid,
  verified_at timestamptz,
  record_version integer not null default 1,
  created_by text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint gps_device_installations_assignment_unique unique (device_vehicle_assignment_id),
  constraint gps_device_installations_technician_label_check check (length(trim(technician_label)) > 0),
  constraint gps_device_installations_verified_consistency_check check ((verified_by_auth_user_id is null) = (verified_at is null))
);

comment on table app.gps_device_installations is
  'ATW-226B: real, evidenced proof that a specific GPS device was physically installed on a specific vehicle -- one row per app.device_vehicle_assignments row (unique constraint), never a second assignment-history mechanism. evidence_file_id is mandatory (app.files, clean-scan and record-scope validated by app.record_gps_device_installation before insert) -- an installation with no evidence is not recorded as installed by this capability, even though app.gps_devices.status alone would still permit the bare transition. Optional secondary review (verified_by_auth_user_id/verified_at) via app.verify_gps_device_installation.';

create index gps_device_installations_tenant_device_idx on app.gps_device_installations (tenant_id, device_id);

create function app.touch_gps_device_installations_row()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  new.record_version := old.record_version + 1;
  return new;
end;
$$;

create trigger gps_device_installations_touch_row
  before update on app.gps_device_installations
  for each row
  execute function app.touch_gps_device_installations_row();

-- Composes app.transition_gps_device_status (ATW-223, unmodified) for the actual
-- assigned->installed state change -- this function adds evidence, it does not
-- reimplement status-machine validation/authority, which that function already owns.
create function app.record_gps_device_installation(
  p_device_vehicle_assignment_id uuid,
  p_evidence_file_id uuid,
  p_technician_label text,
  p_installation_notes text,
  p_expected_device_version integer,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.gps_device_installations
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_assignment app.device_vehicle_assignments;
  v_device app.gps_devices;
  v_file app.files;
  v_installation app.gps_device_installations;
begin
  select * into v_assignment from app.device_vehicle_assignments where id = p_device_vehicle_assignment_id;
  if not found then
    raise exception 'assignment_not_found: %', p_device_vehicle_assignment_id using errcode = 'no_data_found';
  end if;
  if not v_assignment.is_current then
    raise exception 'assignment_not_current: % is a superseded device-vehicle assignment, installation evidence may only be recorded against the current one', p_device_vehicle_assignment_id
      using errcode = 'check_violation';
  end if;

  if exists (select 1 from app.gps_device_installations where device_vehicle_assignment_id = p_device_vehicle_assignment_id) then
    raise exception 'installation_already_recorded: assignment % already carries an installation evidence row' , p_device_vehicle_assignment_id
      using errcode = 'unique_violation';
  end if;

  if p_technician_label is null or length(trim(p_technician_label)) = 0 then
    raise exception 'technician_label_required: a non-empty technician_label is required' using errcode = 'check_violation';
  end if;

  select * into v_file from app.files where id = p_evidence_file_id;
  if not found then
    raise exception 'evidence_file_not_found: %', p_evidence_file_id using errcode = 'no_data_found';
  end if;
  if v_file.tenant_id <> v_assignment.tenant_id or v_file.record_type <> 'gps_device' or v_file.record_id <> v_assignment.device_id then
    raise exception 'installation_evidence_file_mismatch: file % does not belong to device % in tenant %', p_evidence_file_id, v_assignment.device_id, v_assignment.tenant_id
      using errcode = 'check_violation';
  end if;
  if v_file.malware_scan_status <> 'clean' then
    raise exception 'installation_unsafe_evidence: evidence file % has scan status % -- only clean evidence may be recorded', p_evidence_file_id, v_file.malware_scan_status
      using errcode = 'check_violation';
  end if;

  -- Reuses ATW-223's own status machine and authority gate (OPS:Edit) unmodified --
  -- raises invalid_device_status_transition/insufficient_authority/stale_version itself
  -- if the device is not currently 'assigned' or the actor/version is wrong.
  select * into v_device from app.transition_gps_device_status(v_assignment.device_id, 'installed', p_expected_device_version, p_actor_auth_user_id, p_actor_label);

  insert into app.gps_device_installations (
    tenant_id, device_id, device_vehicle_assignment_id, evidence_file_id, technician_label, installation_notes, created_by
  ) values (
    v_assignment.tenant_id, v_assignment.device_id, p_device_vehicle_assignment_id, p_evidence_file_id, p_technician_label, p_installation_notes, p_actor_label
  )
  returning * into v_installation;

  perform app.capture_audit_event(
    v_assignment.tenant_id, p_actor_auth_user_id, p_actor_label, 'record_gps_device_installation',
    'app.gps_device_installations', v_installation.id, 'success', null, null,
    jsonb_build_object('device_id', v_assignment.device_id, 'device_vehicle_assignment_id', p_device_vehicle_assignment_id, 'evidence_file_id', p_evidence_file_id)
  );

  return v_installation;
end;
$$;

comment on function app.record_gps_device_installation is
  'ATW-226B: records evidenced installation and transitions the device assigned -> installed in one call, composing app.transition_gps_device_status (ATW-223) rather than duplicating its own status-machine/authority logic. Rejects a non-clean-scanned or mismatched evidence file before ever touching device status.';

create function app.verify_gps_device_installation(
  p_installation_id uuid,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.gps_device_installations
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_installation app.gps_device_installations;
  v_decision app.rbac_decision;
begin
  select * into v_installation from app.gps_device_installations where id = p_installation_id;
  if not found then
    raise exception 'installation_not_found: %', p_installation_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_installation.tenant_id, 'OPS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_installation.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  update app.gps_device_installations
  set verified_by_auth_user_id = p_actor_auth_user_id, verified_at = now()
  where id = p_installation_id
  returning * into v_installation;

  perform app.capture_audit_event(
    v_installation.tenant_id, p_actor_auth_user_id, p_actor_label, 'verify_gps_device_installation',
    'app.gps_device_installations', v_installation.id, 'success', null, null, jsonb_build_object('verified_at', v_installation.verified_at)
  );

  return v_installation;
end;
$$;

comment on function app.verify_gps_device_installation is
  'ATW-226B: an optional secondary OPS:Edit review over an already-recorded installation. Idempotent-by-reassertion -- re-verifying only refreshes verified_by_auth_user_id/verified_at, never an error, since a second reviewer confirming the same evidence is a legitimate real action, not a mistake.';

alter table app.gps_device_installations enable row level security;

create policy gps_device_installations_select_scoped on app.gps_device_installations
  for select to authenticated
  using (app.has_active_tenant_membership(tenant_id) or app.is_supreme_admin());

revoke execute on all functions in schema app from public;

grant select on app.gps_device_installations to authenticated, service_role;
grant insert, update, delete on app.gps_device_installations to service_role;

grant execute on function app.record_gps_device_installation(uuid, uuid, text, text, integer, uuid, text) to authenticated, service_role;
grant execute on function app.verify_gps_device_installation(uuid, uuid, text) to authenticated, service_role;
