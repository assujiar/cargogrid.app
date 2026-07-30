-- Advanced TMS capability CG-S10-ATW-004 (Prompt 223, Fleet, Vehicle, Driver, Device
-- and SIM Operational Baseline). Implements the operational fleet/vehicle/driver
-- resources plus the device, SIM, mobile eligibility, provider mapping, and
-- installation records multi-source tracking (ATW-226) will later depend on.
--
-- Design boundary (disclosed): "Operational resource is not a vendor/employee
-- master" (Prompt 223 §24). Vehicle and driver *identity* already exists as generic
-- `app.master_records` rows (`master_type_code in ('vehicle','driver')`, seeded at
-- OPS-172) -- this migration never forks a second identity table. It adds only the
-- genuinely new *operational* layer: capacity, ownership semantics, tracking-mode
-- eligibility, and (for drivers) mobile-tracking consent, each a 1:1 profile
-- referencing the existing master record. Device/SIM/provider-mapping/source-
-- priority are entirely new concepts (no prior table claims this ground) and are
-- built fresh.
--
-- History preservation follows OPS-172's own established idiom: device-to-vehicle
-- assignment is a hybrid append-only/in-place table (`is_current`, `superseded_by_id`,
-- a partial unique index enforcing "one device, at most one current vehicle"),
-- mirroring `app.resource_assignments` exactly, since Prompt 223 §24 makes the
-- identical demand ("historical assignments are preserved"). SIM-to-device pairing
-- is deliberately simpler (a mutable `current_device_id` pointer on `app.sim_cards`,
-- relying on `app.capture_audit_event` for transfer history) -- Prompt 223 never
-- names SIM history preservation as a business rule the way it explicitly does for
-- device/vehicle, so a full history table there would be unrequested scope.
--
-- Tracking-mode eligibility here is a *capability* flag only ("this vehicle/driver
-- may use mode X"), never an entitlement decision -- `ATW-226A` (tracking
-- entitlement and source policy) owns the actual package/subscription gate.
-- `app.vehicle_tracking_source_priorities` similarly stores only a declared
-- primary/fallback *policy*, not live arbitration (`ATW-226F`'s own scope) -- no
-- telemetry, position, or live source-health data is read or written anywhere in
-- this migration, matching Prompt 223 §16's "no vendor banking/tax or HR/payroll
-- duplication" and this repository's own confirmed telemetry-greenfield state
-- (ATW-221).
--
-- Record-scope reuses `app.has_active_tenant_membership()`/`app.is_supreme_admin()`
-- directly (the identical pattern `app.master_records` itself already uses, PLT-120)
-- rather than the shipment-anchored `can_access_record`/record-scope composition --
-- these are tenant-wide operational assets with no natural owning user/org-unit,
-- the same shape `app.master_records` already established.
--
-- Permission catalogue: reuses the already-seeded `OPS` action set (`Create`,
-- `Edit`, `Assign`, `View`) -- no new `app.permissions` row, no new module code.
--
-- Per ERR-2026-004 (docs/runtime/ERROR_LEDGER.md): this migration carries its own
-- explicit `REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA app FROM PUBLIC` statement
-- before its final grants, the standing per-migration convention since `PLT-118`.

create table app.vehicle_operational_profiles (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  vehicle_master_id uuid not null references app.master_records (id),
  ownership_type text not null,
  capacity_weight_kg numeric,
  capacity_volume_cbm numeric,
  mobile_tracking_eligible boolean not null default false,
  direct_device_tracking_eligible boolean not null default false,
  third_party_tracking_eligible boolean not null default false,
  status text not null default 'active',
  record_version integer not null default 1,
  created_by text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint vehicle_operational_profiles_vehicle_unique unique (vehicle_master_id),
  constraint vehicle_operational_profiles_ownership_check check (ownership_type in ('owned', 'leased', 'vendor', 'rental', 'ad_hoc')),
  constraint vehicle_operational_profiles_status_check check (status in ('active', 'inactive', 'maintenance', 'retired')),
  constraint vehicle_operational_profiles_capacity_weight_check check (capacity_weight_kg is null or capacity_weight_kg >= 0),
  constraint vehicle_operational_profiles_capacity_volume_check check (capacity_volume_cbm is null or capacity_volume_cbm >= 0)
);

comment on table app.vehicle_operational_profiles is
  'ATW-223: the operational layer over one existing app.master_records vehicle identity (never a second vehicle master). Tracking-mode eligibility columns are capability flags only, not entitlement decisions (ATW-226A owns entitlement).';

create index vehicle_operational_profiles_tenant_idx on app.vehicle_operational_profiles (tenant_id);
create index vehicle_operational_profiles_status_idx on app.vehicle_operational_profiles (tenant_id, status);

create function app.touch_vehicle_operational_profiles_row()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  new.record_version := old.record_version + 1;
  return new;
end;
$$;

create trigger vehicle_operational_profiles_touch_row
  before update on app.vehicle_operational_profiles
  for each row
  execute function app.touch_vehicle_operational_profiles_row();

create table app.driver_operational_profiles (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  driver_master_id uuid not null references app.master_records (id),
  license_class text,
  license_expiry_date date,
  mobile_tracking_consent boolean not null default false,
  mobile_tracking_consent_at timestamptz,
  status text not null default 'active',
  record_version integer not null default 1,
  created_by text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint driver_operational_profiles_driver_unique unique (driver_master_id),
  constraint driver_operational_profiles_status_check check (status in ('active', 'inactive', 'suspended', 'retired'))
);

comment on table app.driver_operational_profiles is
  'ATW-223: the operational layer over one existing app.master_records driver identity. mobile_tracking_consent is a real consent prerequisite (Prompt 223 required-task "driver-mobile eligibility and consent prerequisites") -- driver-mobile tracking eligibility (ATW-226C) must check this flag, never assume consent.';

create index driver_operational_profiles_tenant_idx on app.driver_operational_profiles (tenant_id);

create function app.touch_driver_operational_profiles_row()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  new.record_version := old.record_version + 1;
  return new;
end;
$$;

create trigger driver_operational_profiles_touch_row
  before update on app.driver_operational_profiles
  for each row
  execute function app.touch_driver_operational_profiles_row();

create table app.gps_devices (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  imei text not null,
  device_model text not null,
  ownership_type text not null,
  status text not null default 'stock',
  record_version integer not null default 1,
  created_by text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint gps_devices_tenant_imei_unique unique (tenant_id, imei),
  constraint gps_devices_ownership_check check (ownership_type in ('cargogrid', 'customer', 'partner')),
  constraint gps_devices_status_check check (status in ('stock', 'assigned', 'installed', 'active', 'offline', 'suspended', 'maintenance', 'retired'))
);

comment on table app.gps_devices is
  'ATW-223: a physical GPS tracker inventory row. No service-role key or provider credential is ever stored on this row or on the device itself (219_*.md §4.3) -- device secrets are ATW-226D''s own deployment-time concern, out of this table''s shape entirely.';

create index gps_devices_tenant_status_idx on app.gps_devices (tenant_id, status);

create function app.touch_gps_devices_row()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  new.record_version := old.record_version + 1;
  return new;
end;
$$;

create trigger gps_devices_touch_row
  before update on app.gps_devices
  for each row
  execute function app.touch_gps_devices_row();

create table app.sim_cards (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  iccid text not null,
  msisdn text,
  carrier text,
  status text not null default 'stock',
  current_device_id uuid references app.gps_devices (id),
  record_version integer not null default 1,
  created_by text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint sim_cards_tenant_iccid_unique unique (tenant_id, iccid),
  constraint sim_cards_status_check check (status in ('stock', 'assigned', 'active', 'suspended', 'retired'))
);

comment on table app.sim_cards is
  'ATW-223: SIM inventory. current_device_id is a mutable pointer (unlike device-to-vehicle assignment, Prompt 223 does not name SIM assignment history preservation as a business rule) -- transfer/replace events are still fully audited via app.capture_audit_event.';

create index sim_cards_tenant_status_idx on app.sim_cards (tenant_id, status);
create unique index sim_cards_current_device_unique on app.sim_cards (current_device_id) where current_device_id is not null;

create function app.touch_sim_cards_row()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  new.record_version := old.record_version + 1;
  return new;
end;
$$;

create trigger sim_cards_touch_row
  before update on app.sim_cards
  for each row
  execute function app.touch_sim_cards_row();

create table app.device_vehicle_assignments (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  device_id uuid not null references app.gps_devices (id),
  vehicle_operational_profile_id uuid not null references app.vehicle_operational_profiles (id),
  is_current boolean not null default true,
  effective_from timestamptz not null default now(),
  effective_to timestamptz,
  reason text,
  superseded_by_id uuid references app.device_vehicle_assignments (id),
  created_by text,
  created_at timestamptz not null default now()
);

comment on table app.device_vehicle_assignments is
  'ATW-223: one physical device has at most one current vehicle assignment (enforced by the partial unique index below); historical assignments are preserved, never overwritten -- the identical is_current/superseded_by_id idiom app.resource_assignments (OPS-172) already established.';

create index device_vehicle_assignments_tenant_idx on app.device_vehicle_assignments (tenant_id, device_id);
create index device_vehicle_assignments_vehicle_idx on app.device_vehicle_assignments (vehicle_operational_profile_id);
create unique index device_vehicle_assignments_current_device_unique on app.device_vehicle_assignments (device_id) where is_current;

create table app.provider_vehicle_mappings (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  vehicle_master_id uuid not null references app.master_records (id),
  provider_code text not null,
  external_vehicle_id text not null,
  status text not null default 'active',
  record_version integer not null default 1,
  created_by text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint provider_vehicle_mappings_status_check check (status in ('active', 'inactive')),
  constraint provider_vehicle_mappings_tenant_vehicle_provider_unique unique (tenant_id, vehicle_master_id, provider_code),
  constraint provider_vehicle_mappings_tenant_provider_external_unique unique (tenant_id, provider_code, external_vehicle_id)
);

comment on table app.provider_vehicle_mappings is
  'ATW-223: an existing third-party GPS/fleet platform''s own external vehicle identifier, mapped to one canonical vehicle master record. Case-specific per provider_code -- never a universal lowest-common-denominator provider abstraction (219_*.md §4.4). Live provider adapter behavior (authentication, polling, webhooks) is ATW-226E''s own scope; this table only records the identity mapping.';

create index provider_vehicle_mappings_tenant_vehicle_idx on app.provider_vehicle_mappings (tenant_id, vehicle_master_id);

create function app.touch_provider_vehicle_mappings_row()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  new.record_version := old.record_version + 1;
  return new;
end;
$$;

create trigger provider_vehicle_mappings_touch_row
  before update on app.provider_vehicle_mappings
  for each row
  execute function app.touch_provider_vehicle_mappings_row();

create table app.vehicle_tracking_source_priorities (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  vehicle_master_id uuid not null references app.master_records (id),
  source_type text not null,
  priority_rank integer not null,
  is_enabled boolean not null default true,
  record_version integer not null default 1,
  created_by text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint vehicle_tracking_source_priorities_source_check check (source_type in ('driver_mobile', 'direct_device', 'third_party_platform')),
  constraint vehicle_tracking_source_priorities_rank_check check (priority_rank > 0),
  constraint vehicle_tracking_source_priorities_vehicle_source_unique unique (vehicle_master_id, source_type)
);

comment on table app.vehicle_tracking_source_priorities is
  'ATW-223: a declared primary/fallback source-preference policy per vehicle (Prompt 223 required-task "primary/fallback source policy links") -- a policy declaration only. Live hybrid arbitration using freshness/accuracy/health at runtime is ATW-226F''s own scope; no telemetry is read or written here.';

create index vehicle_tracking_source_priorities_tenant_vehicle_idx on app.vehicle_tracking_source_priorities (tenant_id, vehicle_master_id);

create function app.touch_vehicle_tracking_source_priorities_row()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  new.record_version := old.record_version + 1;
  return new;
end;
$$;

create trigger vehicle_tracking_source_priorities_touch_row
  before update on app.vehicle_tracking_source_priorities
  for each row
  execute function app.touch_vehicle_tracking_source_priorities_row();

-- app.register_vehicle_operational_profile (Prompt 223 §21 "Ops Admin registers or
-- links a vehicle"). Reuses app.create_master_record for the underlying identity
-- (idempotent there already) rather than duplicating master-record creation logic,
-- then creates (or returns, if one already exists) the 1:1 operational profile.
create function app.register_vehicle_operational_profile(
  p_tenant_id uuid,
  p_code text,
  p_name text,
  p_ownership_type text,
  p_capacity_weight_kg numeric,
  p_capacity_volume_cbm numeric,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.vehicle_operational_profiles
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_master app.master_records;
  v_existing app.vehicle_operational_profiles;
  v_profile app.vehicle_operational_profiles;
begin
  if p_ownership_type not in ('owned', 'leased', 'vendor', 'rental', 'ad_hoc') then
    raise exception 'invalid_ownership_type: % is not a supported ownership type', p_ownership_type using errcode = 'check_violation';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'OPS', 'Create');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Create (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  v_master := app.create_master_record('vehicle', p_tenant_id, p_code, p_name, null, null, p_actor_auth_user_id, p_actor_label);

  select * into v_existing from app.vehicle_operational_profiles where vehicle_master_id = v_master.id;
  if found then
    return v_existing;
  end if;

  insert into app.vehicle_operational_profiles (tenant_id, vehicle_master_id, ownership_type, capacity_weight_kg, capacity_volume_cbm, created_by)
  values (p_tenant_id, v_master.id, p_ownership_type, p_capacity_weight_kg, p_capacity_volume_cbm, p_actor_label)
  returning * into v_profile;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'register_vehicle_operational_profile',
    'app.vehicle_operational_profiles', v_profile.id, 'success', null, null,
    jsonb_build_object('vehicle_master_id', v_master.id, 'ownership_type', p_ownership_type)
  );

  return v_profile;
end;
$$;

comment on function app.register_vehicle_operational_profile is
  'ATW-223: idempotent on (tenant, vehicle master code) via app.create_master_record, then idempotent on vehicle_master_id for the profile itself.';

create function app.set_vehicle_tracking_eligibility(
  p_vehicle_profile_id uuid,
  p_mobile_eligible boolean,
  p_direct_device_eligible boolean,
  p_third_party_eligible boolean,
  p_expected_version integer,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.vehicle_operational_profiles
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_profile app.vehicle_operational_profiles;
  v_decision app.rbac_decision;
begin
  select * into v_profile from app.vehicle_operational_profiles where id = p_vehicle_profile_id;
  if not found then
    raise exception 'vehicle_profile_not_found: %', p_vehicle_profile_id using errcode = 'no_data_found';
  end if;

  if v_profile.record_version <> p_expected_version then
    raise exception 'stale_version: vehicle profile % expected version % but found %', p_vehicle_profile_id, p_expected_version, v_profile.record_version
      using errcode = 'serialization_failure';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_profile.tenant_id, 'OPS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_profile.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  update app.vehicle_operational_profiles
  set mobile_tracking_eligible = p_mobile_eligible, direct_device_tracking_eligible = p_direct_device_eligible, third_party_tracking_eligible = p_third_party_eligible
  where id = p_vehicle_profile_id and record_version = p_expected_version
  returning * into v_profile;

  perform app.capture_audit_event(
    v_profile.tenant_id, p_actor_auth_user_id, p_actor_label, 'set_vehicle_tracking_eligibility',
    'app.vehicle_operational_profiles', v_profile.id, 'success', null, null,
    jsonb_build_object('mobile_tracking_eligible', p_mobile_eligible, 'direct_device_tracking_eligible', p_direct_device_eligible, 'third_party_tracking_eligible', p_third_party_eligible)
  );

  return v_profile;
end;
$$;

comment on function app.set_vehicle_tracking_eligibility is
  'ATW-223: a capability flag, never an entitlement decision -- ATW-226A owns whether a tenant''s active package actually permits a given mode.';

-- app.register_driver_operational_profile (Prompt 223 §21).
create function app.register_driver_operational_profile(
  p_tenant_id uuid,
  p_code text,
  p_name text,
  p_license_class text,
  p_license_expiry_date date,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.driver_operational_profiles
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_master app.master_records;
  v_existing app.driver_operational_profiles;
  v_profile app.driver_operational_profiles;
begin
  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'OPS', 'Create');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Create (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  v_master := app.create_master_record('driver', p_tenant_id, p_code, p_name, null, null, p_actor_auth_user_id, p_actor_label);

  select * into v_existing from app.driver_operational_profiles where driver_master_id = v_master.id;
  if found then
    return v_existing;
  end if;

  insert into app.driver_operational_profiles (tenant_id, driver_master_id, license_class, license_expiry_date, created_by)
  values (p_tenant_id, v_master.id, p_license_class, p_license_expiry_date, p_actor_label)
  returning * into v_profile;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'register_driver_operational_profile',
    'app.driver_operational_profiles', v_profile.id, 'success', null, null, jsonb_build_object('driver_master_id', v_master.id)
  );

  return v_profile;
end;
$$;

comment on function app.register_driver_operational_profile is
  'ATW-223: idempotent identically to app.register_vehicle_operational_profile. license_class/license_expiry_date are the only license-shaped fields stored -- Prompt 223 §16''s "minimize driver PII" is honored by not storing a full license number.';

create function app.set_driver_mobile_tracking_consent(
  p_driver_profile_id uuid,
  p_consent boolean,
  p_expected_version integer,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.driver_operational_profiles
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_profile app.driver_operational_profiles;
  v_decision app.rbac_decision;
begin
  select * into v_profile from app.driver_operational_profiles where id = p_driver_profile_id;
  if not found then
    raise exception 'driver_profile_not_found: %', p_driver_profile_id using errcode = 'no_data_found';
  end if;

  if v_profile.record_version <> p_expected_version then
    raise exception 'stale_version: driver profile % expected version % but found %', p_driver_profile_id, p_expected_version, v_profile.record_version
      using errcode = 'serialization_failure';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_profile.tenant_id, 'OPS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_profile.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  update app.driver_operational_profiles
  set mobile_tracking_consent = p_consent, mobile_tracking_consent_at = case when p_consent then now() else null end
  where id = p_driver_profile_id and record_version = p_expected_version
  returning * into v_profile;

  perform app.capture_audit_event(
    v_profile.tenant_id, p_actor_auth_user_id, p_actor_label, 'set_driver_mobile_tracking_consent',
    'app.driver_operational_profiles', v_profile.id, 'success', null, null, jsonb_build_object('consent', p_consent)
  );

  return v_profile;
end;
$$;

comment on function app.set_driver_mobile_tracking_consent is
  'ATW-223: the one real consent prerequisite ATW-226C (driver mobile GPS session) must check before starting any tracking session -- revoking consent (p_consent=false) clears the consent timestamp, never leaves a stale prior grant time in place.';

-- app.register_gps_device (Prompt 223 §20 task 2). Idempotent on (tenant, imei).
create function app.register_gps_device(
  p_tenant_id uuid,
  p_imei text,
  p_device_model text,
  p_ownership_type text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.gps_devices
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_existing app.gps_devices;
  v_device app.gps_devices;
begin
  if p_imei is null or length(trim(p_imei)) = 0 then
    raise exception 'imei_required: a non-empty IMEI is required' using errcode = 'check_violation';
  end if;
  if p_ownership_type not in ('cargogrid', 'customer', 'partner') then
    raise exception 'invalid_ownership_type: % is not a supported device ownership type', p_ownership_type using errcode = 'check_violation';
  end if;

  select * into v_existing from app.gps_devices where tenant_id = p_tenant_id and imei = p_imei;
  if found then
    return v_existing;
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'OPS', 'Create');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Create (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  begin
    insert into app.gps_devices (tenant_id, imei, device_model, ownership_type, created_by)
    values (p_tenant_id, p_imei, p_device_model, p_ownership_type, p_actor_label)
    returning * into v_device;
  exception
    when unique_violation then
      select * into v_device from app.gps_devices where tenant_id = p_tenant_id and imei = p_imei;
      return v_device;
  end;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'register_gps_device',
    'app.gps_devices', v_device.id, 'success', null, null, jsonb_build_object('device_model', p_device_model, 'ownership_type', p_ownership_type)
  );

  return v_device;
end;
$$;

comment on function app.register_gps_device is
  'ATW-223: idempotent on (tenant_id, imei) -- a duplicate IMEI registration attempt for the same tenant returns the exact same row, never a duplicate device identity.';

-- app.transition_gps_device_status -- hardcoded edges (Prompt 223 §13 "stock,
-- assigned, installed, active, offline, suspended, maintenance, retired").
create function app.transition_gps_device_status(
  p_device_id uuid,
  p_to_status text,
  p_expected_version integer,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.gps_devices
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_device app.gps_devices;
  v_decision app.rbac_decision;
  v_allowed boolean := false;
begin
  select * into v_device from app.gps_devices where id = p_device_id;
  if not found then
    raise exception 'device_not_found: %', p_device_id using errcode = 'no_data_found';
  end if;

  if v_device.record_version <> p_expected_version then
    raise exception 'stale_version: device % expected version % but found %', p_device_id, p_expected_version, v_device.record_version
      using errcode = 'serialization_failure';
  end if;

  v_allowed := (v_device.status = 'stock' and p_to_status = 'assigned')
    or (v_device.status = 'assigned' and p_to_status = 'installed')
    or (v_device.status = 'installed' and p_to_status = 'active')
    or (v_device.status in ('active', 'offline') and p_to_status in ('active', 'offline', 'suspended', 'maintenance'))
    or (v_device.status in ('suspended', 'maintenance') and p_to_status = 'active')
    or (v_device.status <> 'retired' and p_to_status = 'retired');

  if not v_allowed then
    raise exception 'invalid_device_status_transition: device % cannot move from % to %', p_device_id, v_device.status, p_to_status
      using errcode = 'check_violation';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_device.tenant_id, 'OPS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_device.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  update app.gps_devices set status = p_to_status where id = p_device_id and record_version = p_expected_version
  returning * into v_device;

  perform app.capture_audit_event(
    v_device.tenant_id, p_actor_auth_user_id, p_actor_label, 'transition_gps_device_status',
    'app.gps_devices', v_device.id, 'success', null, jsonb_build_object('status', v_device.status), jsonb_build_object('status', p_to_status)
  );

  return v_device;
end;
$$;

comment on function app.transition_gps_device_status is
  'ATW-223: hardcoded edges only. retired is terminal (excluded from every "from" branch except explicitly reachable from any non-retired status).';

-- app.assign_device_to_vehicle (Prompt 223 §24 "one physical device has at most one
-- current vehicle assignment"). Releases the device''s own prior current assignment
-- (if any) before inserting the new one, exactly like app.reassign_resource
-- (OPS-172) releases the prior row before inserting -- the partial unique index is
-- never violated even momentarily.
create function app.assign_device_to_vehicle(
  p_device_id uuid,
  p_vehicle_profile_id uuid,
  p_reason text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.device_vehicle_assignments
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_device app.gps_devices;
  v_profile app.vehicle_operational_profiles;
  v_decision app.rbac_decision;
  v_prior app.device_vehicle_assignments;
  v_had_prior boolean := false;
  v_assignment app.device_vehicle_assignments;
begin
  select * into v_device from app.gps_devices where id = p_device_id;
  if not found then
    raise exception 'device_not_found: %', p_device_id using errcode = 'no_data_found';
  end if;
  if v_device.status = 'retired' then
    raise exception 'device_retired: device % is retired and cannot be assigned', p_device_id using errcode = 'check_violation';
  end if;

  select * into v_profile from app.vehicle_operational_profiles where id = p_vehicle_profile_id;
  if not found then
    raise exception 'vehicle_profile_not_found: %', p_vehicle_profile_id using errcode = 'no_data_found';
  end if;
  if v_profile.tenant_id <> v_device.tenant_id then
    raise exception 'tenant_mismatch: device % and vehicle profile % belong to different tenants', p_device_id, p_vehicle_profile_id
      using errcode = 'check_violation';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_device.tenant_id, 'OPS', 'Assign');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Assign (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_device.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_prior from app.device_vehicle_assignments where device_id = p_device_id and is_current;
  v_had_prior := found;
  if v_had_prior and v_prior.vehicle_operational_profile_id = p_vehicle_profile_id then
    return v_prior;
  end if;

  if v_had_prior then
    update app.device_vehicle_assignments
    set is_current = false, effective_to = now()
    where id = v_prior.id;
  end if;

  insert into app.device_vehicle_assignments (tenant_id, device_id, vehicle_operational_profile_id, reason, created_by)
  values (v_device.tenant_id, p_device_id, p_vehicle_profile_id, p_reason, p_actor_label)
  returning * into v_assignment;

  if v_had_prior then
    update app.device_vehicle_assignments
    set superseded_by_id = v_assignment.id
    where id = v_prior.id;
  end if;

  perform app.capture_audit_event(
    v_device.tenant_id, p_actor_auth_user_id, p_actor_label, 'assign_device_to_vehicle',
    'app.device_vehicle_assignments', v_assignment.id, 'success', null, null,
    jsonb_build_object('device_id', p_device_id, 'vehicle_operational_profile_id', p_vehicle_profile_id)
  );

  return v_assignment;
end;
$$;

comment on function app.assign_device_to_vehicle is
  'ATW-223: releases the device''s own prior current assignment (if any) before inserting the new one, mirroring app.reassign_resource (OPS-172). Idempotent no-op if the device is already currently assigned to the same vehicle.';

create function app.unassign_device_from_vehicle(
  p_device_id uuid,
  p_reason text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.device_vehicle_assignments
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_device app.gps_devices;
  v_decision app.rbac_decision;
  v_current app.device_vehicle_assignments;
begin
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'unassign_reason_required: a non-empty reason is required' using errcode = 'check_violation';
  end if;

  select * into v_device from app.gps_devices where id = p_device_id;
  if not found then
    raise exception 'device_not_found: %', p_device_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_device.tenant_id, 'OPS', 'Assign');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Assign (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_device.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_current from app.device_vehicle_assignments where device_id = p_device_id and is_current;
  if not found then
    raise exception 'no_current_assignment: device % has no current vehicle assignment to release', p_device_id using errcode = 'check_violation';
  end if;

  update app.device_vehicle_assignments set is_current = false, effective_to = now(), reason = p_reason
  where id = v_current.id
  returning * into v_current;

  perform app.capture_audit_event(
    v_device.tenant_id, p_actor_auth_user_id, p_actor_label, 'unassign_device_from_vehicle',
    'app.device_vehicle_assignments', v_current.id, 'success', null, null, jsonb_build_object('reason', p_reason)
  );

  return v_current;
end;
$$;

comment on function app.unassign_device_from_vehicle is
  'ATW-223: releases the device''s own current vehicle assignment (mandatory reason), leaving the device unassigned. The released row is preserved (is_current=false), never deleted.';

-- app.register_sim_card / app.assign_sim_to_device / app.unassign_sim_from_device
-- (Prompt 223 §20 task 2, "SIM inventory... replace/transfer flow").
create function app.register_sim_card(
  p_tenant_id uuid,
  p_iccid text,
  p_msisdn text,
  p_carrier text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.sim_cards
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_existing app.sim_cards;
  v_sim app.sim_cards;
begin
  if p_iccid is null or length(trim(p_iccid)) = 0 then
    raise exception 'iccid_required: a non-empty ICCID is required' using errcode = 'check_violation';
  end if;

  select * into v_existing from app.sim_cards where tenant_id = p_tenant_id and iccid = p_iccid;
  if found then
    return v_existing;
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'OPS', 'Create');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Create (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  begin
    insert into app.sim_cards (tenant_id, iccid, msisdn, carrier, created_by)
    values (p_tenant_id, p_iccid, p_msisdn, p_carrier, p_actor_label)
    returning * into v_sim;
  exception
    when unique_violation then
      select * into v_sim from app.sim_cards where tenant_id = p_tenant_id and iccid = p_iccid;
      return v_sim;
  end;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'register_sim_card',
    'app.sim_cards', v_sim.id, 'success', null, null, jsonb_build_object('carrier', p_carrier)
  );

  return v_sim;
end;
$$;

comment on function app.register_sim_card is
  'ATW-223: idempotent on (tenant_id, iccid).';

create function app.assign_sim_to_device(
  p_sim_id uuid,
  p_device_id uuid,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.sim_cards
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_sim app.sim_cards;
  v_device app.gps_devices;
  v_decision app.rbac_decision;
begin
  select * into v_sim from app.sim_cards where id = p_sim_id;
  if not found then
    raise exception 'sim_not_found: %', p_sim_id using errcode = 'no_data_found';
  end if;

  select * into v_device from app.gps_devices where id = p_device_id;
  if not found then
    raise exception 'device_not_found: %', p_device_id using errcode = 'no_data_found';
  end if;
  if v_device.tenant_id <> v_sim.tenant_id then
    raise exception 'tenant_mismatch: sim % and device % belong to different tenants', p_sim_id, p_device_id using errcode = 'check_violation';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_sim.tenant_id, 'OPS', 'Assign');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Assign (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_sim.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if exists (select 1 from app.sim_cards where current_device_id = p_device_id and id <> p_sim_id) then
    raise exception 'device_already_has_sim: device % already has a different SIM assigned', p_device_id using errcode = 'check_violation';
  end if;

  update app.sim_cards set current_device_id = p_device_id, status = 'assigned'
  where id = p_sim_id
  returning * into v_sim;

  perform app.capture_audit_event(
    v_sim.tenant_id, p_actor_auth_user_id, p_actor_label, 'assign_sim_to_device',
    'app.sim_cards', v_sim.id, 'success', null, null, jsonb_build_object('device_id', p_device_id)
  );

  return v_sim;
end;
$$;

comment on function app.assign_sim_to_device is
  'ATW-223: at most one SIM per device at a time, enforced by a real partial unique index (sim_cards_current_device_unique) as well as this pre-check.';

create function app.unassign_sim_from_device(
  p_sim_id uuid,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.sim_cards
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_sim app.sim_cards;
  v_decision app.rbac_decision;
begin
  select * into v_sim from app.sim_cards where id = p_sim_id;
  if not found then
    raise exception 'sim_not_found: %', p_sim_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_sim.tenant_id, 'OPS', 'Assign');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Assign (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_sim.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  update app.sim_cards set current_device_id = null, status = 'stock'
  where id = p_sim_id
  returning * into v_sim;

  perform app.capture_audit_event(
    v_sim.tenant_id, p_actor_auth_user_id, p_actor_label, 'unassign_sim_from_device',
    'app.sim_cards', v_sim.id, 'success', null, null, null
  );

  return v_sim;
end;
$$;

-- app.register_provider_vehicle_mapping (Prompt 223 §22 "an existing provider may
-- map external IDs").
create function app.register_provider_vehicle_mapping(
  p_tenant_id uuid,
  p_vehicle_master_id uuid,
  p_provider_code text,
  p_external_vehicle_id text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.provider_vehicle_mappings
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_existing app.provider_vehicle_mappings;
  v_mapping app.provider_vehicle_mappings;
begin
  if not exists (select 1 from app.master_records where id = p_vehicle_master_id and master_type_code = 'vehicle' and (tenant_id = p_tenant_id or tenant_id is null)) then
    raise exception 'vehicle_not_found: % is not a known vehicle reference for tenant %', p_vehicle_master_id, p_tenant_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'OPS', 'Create');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Create (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_existing from app.provider_vehicle_mappings where tenant_id = p_tenant_id and vehicle_master_id = p_vehicle_master_id and provider_code = p_provider_code;
  if found then
    return v_existing;
  end if;

  begin
    insert into app.provider_vehicle_mappings (tenant_id, vehicle_master_id, provider_code, external_vehicle_id, created_by)
    values (p_tenant_id, p_vehicle_master_id, p_provider_code, p_external_vehicle_id, p_actor_label)
    returning * into v_mapping;
  exception
    when unique_violation then
      raise exception 'provider_external_id_collision: external vehicle id % is already mapped for provider % in this tenant', p_external_vehicle_id, p_provider_code
        using errcode = 'check_violation';
  end;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'register_provider_vehicle_mapping',
    'app.provider_vehicle_mappings', v_mapping.id, 'success', null, null,
    jsonb_build_object('vehicle_master_id', p_vehicle_master_id, 'provider_code', p_provider_code)
  );

  return v_mapping;
end;
$$;

comment on function app.register_provider_vehicle_mapping is
  'ATW-223: idempotent on (tenant, vehicle, provider_code); a distinct external_vehicle_id already claimed by another vehicle under the same provider in this tenant is a real, named conflict, never silently overwritten.';

-- app.set_vehicle_tracking_source_priority (Prompt 223 §20 task 4, upsert).
create function app.set_vehicle_tracking_source_priority(
  p_tenant_id uuid,
  p_vehicle_master_id uuid,
  p_source_type text,
  p_priority_rank integer,
  p_is_enabled boolean,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.vehicle_tracking_source_priorities
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_priority app.vehicle_tracking_source_priorities;
begin
  if p_source_type not in ('driver_mobile', 'direct_device', 'third_party_platform') then
    raise exception 'invalid_source_type: % is not a supported source type', p_source_type using errcode = 'check_violation';
  end if;
  if p_priority_rank is null or p_priority_rank <= 0 then
    raise exception 'invalid_priority_rank: priority_rank must be a positive integer' using errcode = 'check_violation';
  end if;
  if not exists (select 1 from app.master_records where id = p_vehicle_master_id and master_type_code = 'vehicle' and (tenant_id = p_tenant_id or tenant_id is null)) then
    raise exception 'vehicle_not_found: % is not a known vehicle reference for tenant %', p_vehicle_master_id, p_tenant_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'OPS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  insert into app.vehicle_tracking_source_priorities (tenant_id, vehicle_master_id, source_type, priority_rank, is_enabled, created_by)
  values (p_tenant_id, p_vehicle_master_id, p_source_type, p_priority_rank, p_is_enabled, p_actor_label)
  on conflict (vehicle_master_id, source_type) do update set
    priority_rank = excluded.priority_rank,
    is_enabled = excluded.is_enabled
  returning * into v_priority;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'set_vehicle_tracking_source_priority',
    'app.vehicle_tracking_source_priorities', v_priority.id, 'success', null, null,
    jsonb_build_object('source_type', p_source_type, 'priority_rank', p_priority_rank, 'is_enabled', p_is_enabled)
  );

  return v_priority;
end;
$$;

comment on function app.set_vehicle_tracking_source_priority is
  'ATW-223: one priority row per (vehicle, source_type), upserted. A declared policy only -- ATW-226F performs the actual live arbitration using this policy plus real-time freshness/accuracy/health, none of which exists yet.';

alter table app.vehicle_operational_profiles enable row level security;
alter table app.driver_operational_profiles enable row level security;
alter table app.gps_devices enable row level security;
alter table app.sim_cards enable row level security;
alter table app.device_vehicle_assignments enable row level security;
alter table app.provider_vehicle_mappings enable row level security;
alter table app.vehicle_tracking_source_priorities enable row level security;

create policy vehicle_operational_profiles_select_scoped on app.vehicle_operational_profiles
  for select to authenticated
  using (app.has_active_tenant_membership(tenant_id) or app.is_supreme_admin());

create policy driver_operational_profiles_select_scoped on app.driver_operational_profiles
  for select to authenticated
  using (app.has_active_tenant_membership(tenant_id) or app.is_supreme_admin());

create policy gps_devices_select_scoped on app.gps_devices
  for select to authenticated
  using (app.has_active_tenant_membership(tenant_id) or app.is_supreme_admin());

create policy sim_cards_select_scoped on app.sim_cards
  for select to authenticated
  using (app.has_active_tenant_membership(tenant_id) or app.is_supreme_admin());

create policy device_vehicle_assignments_select_scoped on app.device_vehicle_assignments
  for select to authenticated
  using (app.has_active_tenant_membership(tenant_id) or app.is_supreme_admin());

create policy provider_vehicle_mappings_select_scoped on app.provider_vehicle_mappings
  for select to authenticated
  using (app.has_active_tenant_membership(tenant_id) or app.is_supreme_admin());

create policy vehicle_tracking_source_priorities_select_scoped on app.vehicle_tracking_source_priorities
  for select to authenticated
  using (app.has_active_tenant_membership(tenant_id) or app.is_supreme_admin());

revoke execute on all functions in schema app from public;

grant select on app.vehicle_operational_profiles to authenticated, service_role;
grant insert, update, delete on app.vehicle_operational_profiles to service_role;
grant select on app.driver_operational_profiles to authenticated, service_role;
grant insert, update, delete on app.driver_operational_profiles to service_role;
grant select on app.gps_devices to authenticated, service_role;
grant insert, update, delete on app.gps_devices to service_role;
grant select on app.sim_cards to authenticated, service_role;
grant insert, update, delete on app.sim_cards to service_role;
grant select on app.device_vehicle_assignments to authenticated, service_role;
grant insert, update, delete on app.device_vehicle_assignments to service_role;
grant select on app.provider_vehicle_mappings to authenticated, service_role;
grant insert, update, delete on app.provider_vehicle_mappings to service_role;
grant select on app.vehicle_tracking_source_priorities to authenticated, service_role;
grant insert, update, delete on app.vehicle_tracking_source_priorities to service_role;

grant execute on function app.register_vehicle_operational_profile(uuid, text, text, text, numeric, numeric, uuid, text) to authenticated, service_role;
grant execute on function app.set_vehicle_tracking_eligibility(uuid, boolean, boolean, boolean, integer, uuid, text) to authenticated, service_role;
grant execute on function app.register_driver_operational_profile(uuid, text, text, text, date, uuid, text) to authenticated, service_role;
grant execute on function app.set_driver_mobile_tracking_consent(uuid, boolean, integer, uuid, text) to authenticated, service_role;
grant execute on function app.register_gps_device(uuid, text, text, text, uuid, text) to authenticated, service_role;
grant execute on function app.transition_gps_device_status(uuid, text, integer, uuid, text) to authenticated, service_role;
grant execute on function app.assign_device_to_vehicle(uuid, uuid, text, uuid, text) to authenticated, service_role;
grant execute on function app.unassign_device_from_vehicle(uuid, text, uuid, text) to authenticated, service_role;
grant execute on function app.register_sim_card(uuid, text, text, text, uuid, text) to authenticated, service_role;
grant execute on function app.assign_sim_to_device(uuid, uuid, uuid, text) to authenticated, service_role;
grant execute on function app.unassign_sim_from_device(uuid, uuid, text) to authenticated, service_role;
grant execute on function app.register_provider_vehicle_mapping(uuid, uuid, text, text, uuid, text) to authenticated, service_role;
grant execute on function app.set_vehicle_tracking_source_priority(uuid, uuid, text, integer, boolean, uuid, text) to authenticated, service_role;
