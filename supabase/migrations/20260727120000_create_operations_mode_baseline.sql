-- Operations capability OPS-171 (Land, Air and Sea Baseline, CG-S8-OPS-005)
-- One bounded, single-mode/single-leg mode profile per Shipment Order (OPS-169),
-- typed per mode (land/air/sea) via mutually-exclusive column groups on one shared
-- table -- "common canonical shipment identity/lifecycle is not forked by mode"
-- (Prompt 171 §24) means the profile augments the one canonical `app.shipment_orders`
-- row, it never becomes a second parallel shipment concept.
--
-- Vehicle/vendor/carrier references are deliberately plain text in this capability,
-- never a foreign key into a vehicle/vendor master -- no such master type has been
-- registered anywhere in this repository yet (`app.master_records`, PLT-120, has only
-- ever seeded `vendor_rate`). Binding these fields to real canonical vendor/fleet/
-- vehicle/driver references is `OPS-172`'s (Resource Assignment) own explicit scope,
-- not anticipated or duplicated here.
--
-- Mode change policy (Prompt 171 §22/§23, the "eligible draft changes mode" alternative
-- flow / "confirmed-mode change blocks safely" exception flow): `app.change_shipment_mode`
-- is the one path that may alter `app.shipment_orders.mode` itself, and it is allowed
-- only while the shipment is still `draft` -- it explicitly reconciles the prior
-- incompatible profile by deleting it, rather than leaving stale mismatched fields
-- behind. Editing the profile's own field *values* for the shipment's current,
-- unchanged mode is a separate, less restrictive path (`app.set_shipment_mode_profile`,
-- an idempotent upsert) blocked only once the shipment is cancelled.
--
-- Multi-leg, multimodal, multi-pickup/drop, consolidation, route/load optimization and
-- GPS/telematics all remain explicit Phase 3/5 (Advanced TMS/WMS) scope, never
-- anticipated here (Prompt 171 §24).
--
-- Per ERR-2026-004 (docs/runtime/ERROR_LEDGER.md): this migration carries its own
-- explicit `REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA app FROM PUBLIC` statement
-- before its final grants, the standing per-migration convention since `PLT-118`.

create table app.shipment_mode_profiles (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  shipment_order_id uuid not null references app.shipment_orders (id),
  mode text not null,
  land_vehicle_ref text,
  land_vendor_ref text,
  land_pickup_address text,
  land_delivery_address text,
  air_awb_number text,
  air_flight_number text,
  air_origin_airport text,
  air_destination_airport text,
  sea_bl_number text,
  sea_booking_number text,
  sea_vessel_name text,
  sea_origin_port text,
  sea_destination_port text,
  sea_container_number text,
  sea_container_type text,
  record_version integer not null default 1,
  created_by text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint shipment_mode_profiles_shipment_order_unique unique (shipment_order_id),
  constraint shipment_mode_profiles_mode_check check (mode in ('land', 'air', 'sea')),
  constraint shipment_mode_profiles_mode_fields_check check (
    (mode = 'land'
      and land_vehicle_ref is not null and land_vendor_ref is not null
      and land_pickup_address is not null and land_delivery_address is not null
      and air_awb_number is null and air_flight_number is null and air_origin_airport is null and air_destination_airport is null
      and sea_bl_number is null and sea_booking_number is null and sea_vessel_name is null and sea_origin_port is null and sea_destination_port is null and sea_container_number is null and sea_container_type is null)
    or
    (mode = 'air'
      and air_awb_number is not null and air_flight_number is not null and air_origin_airport is not null and air_destination_airport is not null
      and land_vehicle_ref is null and land_vendor_ref is null and land_pickup_address is null and land_delivery_address is null
      and sea_bl_number is null and sea_booking_number is null and sea_vessel_name is null and sea_origin_port is null and sea_destination_port is null and sea_container_number is null and sea_container_type is null)
    or
    (mode = 'sea'
      and sea_bl_number is not null and sea_booking_number is not null and sea_vessel_name is not null and sea_origin_port is not null and sea_destination_port is not null
      and land_vehicle_ref is null and land_vendor_ref is null and land_pickup_address is null and land_delivery_address is null
      and air_awb_number is null and air_flight_number is null and air_origin_airport is null and air_destination_airport is null)
  )
);

comment on table app.shipment_mode_profiles is
  'OPS-171: one bounded, single-mode/single-leg mode profile per Shipment Order (unique on shipment_order_id, a real 1:1). Exactly one mode''s own column group is ever populated -- the others structurally null, enforced by shipment_mode_profiles_mode_fields_check, never merely a convention. sea_container_number/sea_container_type stay optional (LCL cargo may have neither); every other field its own mode requires is mandatory.';

create index shipment_mode_profiles_tenant_mode_idx on app.shipment_mode_profiles (tenant_id, mode);

create function app.touch_shipment_mode_profiles_row()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  new.record_version := old.record_version + 1;
  return new;
end;
$$;

create trigger shipment_mode_profiles_touch_row
  before update on app.shipment_mode_profiles
  for each row
  execute function app.touch_shipment_mode_profiles_row();

-- The one idempotent create-or-update path (Prompt 171 §21's own main flow). Mode is
-- never a caller-supplied argument -- it is always read from the linked Shipment
-- Order itself, so a profile can never drift out of sync with its own shipment's mode.
create function app.set_shipment_mode_profile(
  p_shipment_order_id uuid,
  p_land_vehicle_ref text,
  p_land_vendor_ref text,
  p_land_pickup_address text,
  p_land_delivery_address text,
  p_air_awb_number text,
  p_air_flight_number text,
  p_air_origin_airport text,
  p_air_destination_airport text,
  p_sea_bl_number text,
  p_sea_booking_number text,
  p_sea_vessel_name text,
  p_sea_origin_port text,
  p_sea_destination_port text,
  p_sea_container_number text,
  p_sea_container_type text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.shipment_mode_profiles
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_shipment app.shipment_orders;
  v_decision app.rbac_decision;
  v_profile app.shipment_mode_profiles;
begin
  select * into v_shipment from app.shipment_orders where id = p_shipment_order_id;
  if not found then
    raise exception 'shipment_order_not_found: %', p_shipment_order_id using errcode = 'no_data_found';
  end if;

  if v_shipment.status = 'cancelled' then
    raise exception 'invalid_transition: shipment order % is cancelled and its mode profile can no longer be set', p_shipment_order_id
      using errcode = 'check_violation';
  end if;

  if v_shipment.mode = 'land' and (p_land_vehicle_ref is null or p_land_vendor_ref is null or p_land_pickup_address is null or p_land_delivery_address is null) then
    raise exception 'missing_required_reference: land mode requires vehicle_ref, vendor_ref, pickup_address and delivery_address' using errcode = 'check_violation';
  end if;
  if v_shipment.mode = 'air' and (p_air_awb_number is null or p_air_flight_number is null or p_air_origin_airport is null or p_air_destination_airport is null) then
    raise exception 'missing_required_reference: air mode requires awb_number, flight_number, origin_airport and destination_airport' using errcode = 'check_violation';
  end if;
  if v_shipment.mode = 'sea' and (p_sea_bl_number is null or p_sea_booking_number is null or p_sea_vessel_name is null or p_sea_origin_port is null or p_sea_destination_port is null) then
    raise exception 'missing_required_reference: sea mode requires bl_number, booking_number, vessel_name, origin_port and destination_port' using errcode = 'check_violation';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_shipment.tenant_id, 'OPS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_shipment.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if not app.can_access_record(p_actor_auth_user_id, v_shipment.tenant_id, v_shipment.owner_user_id, app.lead_record_scope_org_unit_ids(v_shipment.org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot access shipment order %', p_actor_auth_user_id, p_shipment_order_id
      using errcode = 'insufficient_privilege';
  end if;

  insert into app.shipment_mode_profiles (
    tenant_id, shipment_order_id, mode,
    land_vehicle_ref, land_vendor_ref, land_pickup_address, land_delivery_address,
    air_awb_number, air_flight_number, air_origin_airport, air_destination_airport,
    sea_bl_number, sea_booking_number, sea_vessel_name, sea_origin_port, sea_destination_port, sea_container_number, sea_container_type,
    created_by
  ) values (
    v_shipment.tenant_id, p_shipment_order_id, v_shipment.mode,
    p_land_vehicle_ref, p_land_vendor_ref, p_land_pickup_address, p_land_delivery_address,
    p_air_awb_number, p_air_flight_number, p_air_origin_airport, p_air_destination_airport,
    p_sea_bl_number, p_sea_booking_number, p_sea_vessel_name, p_sea_origin_port, p_sea_destination_port, p_sea_container_number, p_sea_container_type,
    p_actor_label
  )
  on conflict (shipment_order_id) do update set
    mode = excluded.mode,
    land_vehicle_ref = excluded.land_vehicle_ref, land_vendor_ref = excluded.land_vendor_ref,
    land_pickup_address = excluded.land_pickup_address, land_delivery_address = excluded.land_delivery_address,
    air_awb_number = excluded.air_awb_number, air_flight_number = excluded.air_flight_number,
    air_origin_airport = excluded.air_origin_airport, air_destination_airport = excluded.air_destination_airport,
    sea_bl_number = excluded.sea_bl_number, sea_booking_number = excluded.sea_booking_number,
    sea_vessel_name = excluded.sea_vessel_name, sea_origin_port = excluded.sea_origin_port, sea_destination_port = excluded.sea_destination_port,
    sea_container_number = excluded.sea_container_number, sea_container_type = excluded.sea_container_type
  returning * into v_profile;

  perform app.capture_audit_event(
    v_shipment.tenant_id, p_actor_auth_user_id, p_actor_label, 'set_shipment_mode_profile',
    'app.shipment_mode_profiles', v_profile.id, 'success', null, null,
    jsonb_build_object('shipment_order_id', p_shipment_order_id, 'mode', v_shipment.mode)
  );

  return v_profile;
end;
$$;

comment on function app.set_shipment_mode_profile is
  'OPS-171: idempotent create-or-update (ON CONFLICT on the real shipment_order_id unique constraint) -- mode is always read from the shipment itself, never caller-supplied. Blocked only once the shipment is cancelled; not otherwise status-gated (editing the profile''s own field values for the shipment''s current, unchanged mode is deliberately less restrictive than changing the mode itself, app.change_shipment_mode).';

-- The one path that may alter app.shipment_orders.mode itself (Prompt 171 §22/§23).
-- draft-only; explicitly reconciles the prior profile by deleting it (never leaving
-- stale, now-incompatible field values behind for a caller to stumble over).
create function app.change_shipment_mode(
  p_shipment_order_id uuid,
  p_new_mode text,
  p_expected_version integer,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.shipment_orders
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_shipment app.shipment_orders;
  v_decision app.rbac_decision;
begin
  if p_new_mode not in ('land', 'air', 'sea') then
    raise exception 'invalid_mode: % is not a supported mode', p_new_mode using errcode = 'check_violation';
  end if;

  select * into v_shipment from app.shipment_orders where id = p_shipment_order_id;
  if not found then
    raise exception 'shipment_order_not_found: %', p_shipment_order_id using errcode = 'no_data_found';
  end if;

  if v_shipment.record_version <> p_expected_version then
    raise exception 'stale_version: shipment order % expected version % but found %', p_shipment_order_id, p_expected_version, v_shipment.record_version
      using errcode = 'serialization_failure';
  end if;

  if v_shipment.status <> 'draft' then
    raise exception 'confirmed_mode_change_blocked: shipment order % is % -- mode may only change while draft', p_shipment_order_id, v_shipment.status
      using errcode = 'check_violation';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_shipment.tenant_id, 'OPS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_shipment.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if not app.can_access_record(p_actor_auth_user_id, v_shipment.tenant_id, v_shipment.owner_user_id, app.lead_record_scope_org_unit_ids(v_shipment.org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot access shipment order %', p_actor_auth_user_id, p_shipment_order_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_shipment.mode <> p_new_mode then
    delete from app.shipment_mode_profiles where shipment_order_id = p_shipment_order_id;
  end if;

  update app.shipment_orders
  set mode = p_new_mode
  where id = p_shipment_order_id and record_version = p_expected_version
  returning * into v_shipment;

  perform app.capture_audit_event(
    v_shipment.tenant_id, p_actor_auth_user_id, p_actor_label, 'change_shipment_mode',
    'app.shipment_orders', v_shipment.id, 'success', null, null, jsonb_build_object('mode', p_new_mode)
  );

  return v_shipment;
end;
$$;

comment on function app.change_shipment_mode is
  'OPS-171: the one path that may alter a Shipment Order''s own mode -- draft-only (confirmed_mode_change_blocked otherwise), and reconciles the prior profile by deleting it whenever the mode actually changes, rather than leaving stale incompatible field values in place for the caller to discover later.';

alter table app.shipment_mode_profiles enable row level security;

create policy shipment_mode_profiles_select_scoped on app.shipment_mode_profiles
  for select to authenticated
  using (
    exists (
      select 1 from app.shipment_orders so
      where so.id = shipment_mode_profiles.shipment_order_id
        and app.can_access_record(auth.uid(), so.tenant_id, so.owner_user_id, app.lead_record_scope_org_unit_ids(so.org_unit_id), null)
    )
  );

revoke execute on all functions in schema app from public;

grant select on app.shipment_mode_profiles to authenticated, service_role;
grant insert, update, delete on app.shipment_mode_profiles to service_role;

grant execute on function app.set_shipment_mode_profile(uuid, text, text, text, text, text, text, text, text, text, text, text, text, text, text, text, uuid, text) to authenticated, service_role;
grant execute on function app.change_shipment_mode(uuid, text, integer, uuid, text) to authenticated, service_role;
