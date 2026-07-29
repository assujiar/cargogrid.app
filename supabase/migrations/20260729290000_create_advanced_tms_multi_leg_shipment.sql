-- Advanced TMS capability CG-S10-ATW-002 (Prompt 221, Multi-Leg and Multimodal
-- Shipment). Extends the verified single-leg, single-mode Shipment Order
-- (`app.shipment_orders`, OPS-169) into ordered multi-pickup/transfer/linehaul/
-- delivery legs across land/air/sea, without duplicating the canonical Shipment
-- Order root or its own already-governed lifecycle (`app.transition_shipment_order`,
-- OPS-170).
--
-- Design boundary (disclosed): the Shipment Order remains the single authoritative
-- lifecycle record. This migration adds a *network* of legs beneath it -- an
-- additive planning/execution layer, not a second shipment root and not a second
-- state machine that could race the OPS-170 transition matrix. `app.shipment_orders`
-- gains one new nullable column, `leg_network_status` (null|draft|confirmed),
-- reporting whether a leg network has been declared and validated for this
-- shipment; the shipment's own canonical `status` is untouched by this migration.
-- Every existing/legacy Shipment Order is left with `leg_network_status = null`
-- until `app.migrate_legacy_shipment_to_leg_network` is explicitly invoked for it
-- (a reversible, idempotent expand-only backfill -- never applied automatically by
-- this migration itself, since no live Supabase project/data exists yet to backfill,
-- per docs/runtime/HANDOFF.md's repeatedly disclosed "no deployed environment"
-- condition; the function exists so a future real backfill run, or this
-- migration's own db-test, can exercise it against real rows).
--
-- Carrier reference reuses `app.master_records` directly (`master_type_code in
-- ('vendor','fleet')`), the identical party-shaped-reference template
-- `app.resource_assignments.resource_id` (OPS-172) and Finance's own
-- `app.finance_vendor_bills.vendor_master_id` (FIN-19x) already established --
-- never a new vendor/fleet master table.
--
-- Location uses the PostGIS `geography(Point,4326)` convention established at
-- PLT-134 (`docs/adr/ADR-0014-postgis-spatial-conventions.md`): a `geography`
-- column directly on the stop row it describes, built via
-- `app.geojson_point_to_geography`, validated by `app.validate_geography_point`.
--
-- Permission catalogue: reuses the already-seeded `OPS` action set (`Create`,
-- `Edit`) exactly as OPS-169/170/172 already do -- no new `app.permissions` row,
-- no new module code. Record-scope reuses `app.can_access_record`/
-- `app.lead_record_scope_org_unit_ids` joined through to the parent Shipment
-- Order's own `tenant_id`/`owner_user_id`/`org_unit_id`, the identical pattern
-- `app.shipment_mode_profiles` (OPS-171) and `app.milestone_events` (OPS-173)
-- already use for a child table with no owner/org-unit column of its own.
--
-- Per ERR-2026-004 (docs/runtime/ERROR_LEDGER.md): this migration carries its own
-- explicit `REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA app FROM PUBLIC` statement
-- before its final grants, the standing per-migration convention since `PLT-118`.

alter table app.shipment_orders
  add column leg_network_status text;

alter table app.shipment_orders
  add constraint shipment_orders_leg_network_status_check
  check (leg_network_status is null or leg_network_status in ('draft', 'confirmed'));

comment on column app.shipment_orders.leg_network_status is
  'ATW-221: null until a leg network is first declared for this Shipment Order; draft while legs/stops/cargo are being planned; confirmed once app.confirm_shipment_leg_network validates the network. Never mutates the Shipment Order''s own canonical status (app.transition_shipment_order, OPS-170) -- an additive planning-state projection only.';

create table app.shipment_legs (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  shipment_order_id uuid not null references app.shipment_orders (id),
  sequence_no integer not null,
  idempotency_key text not null,
  mode text not null,
  leg_status text not null default 'planned',
  is_legacy_compat boolean not null default false,
  carrier_master_id uuid references app.master_records (id),
  planned_departure_at timestamptz,
  planned_arrival_at timestamptz,
  actual_departure_at timestamptz,
  actual_arrival_at timestamptz,
  owner_user_id uuid references auth.users (id),
  record_version integer not null default 1,
  created_by text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint shipment_legs_mode_check check (mode in ('land', 'air', 'sea')),
  constraint shipment_legs_status_check check (leg_status in ('planned', 'dispatched', 'in_transit', 'arrived', 'completed', 'cancelled')),
  constraint shipment_legs_sequence_positive_check check (sequence_no > 0),
  constraint shipment_legs_tenant_shipment_idempotency_unique unique (tenant_id, shipment_order_id, idempotency_key),
  constraint shipment_legs_tenant_shipment_sequence_unique unique (tenant_id, shipment_order_id, sequence_no)
);

comment on table app.shipment_legs is
  'ATW-221: one ordered leg within a Shipment Order''s own multi-leg network. A leg is not an independent shipment -- it always belongs to exactly one Shipment Order (the canonical root, OPS-169). idempotency_key makes app.add_shipment_leg safe to retry; sequence_no is the leg''s own business-unique order within the shipment. is_legacy_compat marks the one auto-created leg app.migrate_legacy_shipment_to_leg_network produces for a pre-existing single-leg shipment.';

create index shipment_legs_tenant_shipment_idx on app.shipment_legs (tenant_id, shipment_order_id);
create index shipment_legs_tenant_status_idx on app.shipment_legs (tenant_id, leg_status);
create index shipment_legs_carrier_idx on app.shipment_legs (carrier_master_id);

create function app.touch_shipment_legs_row()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  new.record_version := old.record_version + 1;
  return new;
end;
$$;

create trigger shipment_legs_touch_row
  before update on app.shipment_legs
  for each row
  execute function app.touch_shipment_legs_row();

create table app.shipment_leg_stops (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  shipment_leg_id uuid not null references app.shipment_legs (id),
  stop_sequence integer not null,
  stop_type text not null,
  location_name text not null,
  address text,
  location_geog geography (point, 4326),
  planned_at timestamptz,
  actual_at timestamptz,
  stop_status text not null default 'pending',
  record_version integer not null default 1,
  created_by text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint shipment_leg_stops_type_check check (stop_type in ('pickup', 'transfer', 'delivery')),
  constraint shipment_leg_stops_status_check check (stop_status in ('pending', 'arrived', 'departed', 'skipped')),
  constraint shipment_leg_stops_sequence_positive_check check (stop_sequence > 0),
  constraint shipment_leg_stops_geog_check check (location_geog is null or app.validate_geography_point(location_geog)),
  constraint shipment_leg_stops_tenant_leg_sequence_unique unique (tenant_id, shipment_leg_id, stop_sequence)
);

comment on table app.shipment_leg_stops is
  'ATW-221: one ordered stop (pickup/transfer/delivery) within one leg. location_geog is the PLT-134 PostGIS convention (geography(Point,4326), built via app.geojson_point_to_geography) -- an attribute of the stop, never a separate spatial entity.';

create index shipment_leg_stops_tenant_leg_idx on app.shipment_leg_stops (tenant_id, shipment_leg_id);
create index shipment_leg_stops_geog_idx on app.shipment_leg_stops using gist (location_geog);

create function app.touch_shipment_leg_stops_row()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  new.record_version := old.record_version + 1;
  return new;
end;
$$;

create trigger shipment_leg_stops_touch_row
  before update on app.shipment_leg_stops
  for each row
  execute function app.touch_shipment_leg_stops_row();

create table app.shipment_leg_cargo_allocations (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  shipment_leg_id uuid not null references app.shipment_legs (id),
  allocated_quantity numeric,
  allocated_weight_kg numeric,
  allocated_volume_cbm numeric,
  record_version integer not null default 1,
  created_by text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint shipment_leg_cargo_allocations_leg_unique unique (shipment_leg_id),
  constraint shipment_leg_cargo_allocations_quantity_check check (allocated_quantity is null or allocated_quantity >= 0),
  constraint shipment_leg_cargo_allocations_weight_check check (allocated_weight_kg is null or allocated_weight_kg >= 0),
  constraint shipment_leg_cargo_allocations_volume_check check (allocated_volume_cbm is null or allocated_volume_cbm >= 0)
);

comment on table app.shipment_leg_cargo_allocations is
  'ATW-221: one cargo allocation per leg (a governed 1:1, the same bounded-slice discipline app.shipment_mode_profiles (OPS-171) already applies -- splitting cargo across multiple lines within a single leg is out of this task''s scope). The sum of every non-cancelled leg''s allocation for a shipment must never exceed that Shipment Order''s own allocated_quantity/allocated_weight_kg/allocated_volume_cbm (app.allocate_shipment_leg_cargo enforces this).';

create index shipment_leg_cargo_allocations_tenant_idx on app.shipment_leg_cargo_allocations (tenant_id);

create function app.touch_shipment_leg_cargo_allocations_row()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  new.record_version := old.record_version + 1;
  return new;
end;
$$;

create trigger shipment_leg_cargo_allocations_touch_row
  before update on app.shipment_leg_cargo_allocations
  for each row
  execute function app.touch_shipment_leg_cargo_allocations_row();

create table app.shipment_leg_custody_events (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  shipment_leg_id uuid not null references app.shipment_legs (id),
  sequence_no integer not null,
  event_type text not null,
  from_party_snapshot jsonb,
  to_party_snapshot jsonb not null,
  occurred_at timestamptz not null,
  evidence jsonb,
  recorded_by text,
  created_at timestamptz not null default now(),
  constraint shipment_leg_custody_events_type_check check (event_type in ('custody_transfer', 'handoff_confirmed')),
  constraint shipment_leg_custody_events_tenant_leg_sequence_unique unique (tenant_id, shipment_leg_id, sequence_no)
);

comment on table app.shipment_leg_custody_events is
  'ATW-221: append-only custody/handoff lineage for one leg -- never updated or deleted, matching every other append-only event table in this repository (app.milestone_events, app.dispatch_commands). to_party_snapshot is mandatory (a handoff always names who now holds custody); from_party_snapshot is null only for the first custody event on a leg (the leg''s own initial custody).';

create index shipment_leg_custody_events_tenant_leg_idx on app.shipment_leg_custody_events (tenant_id, shipment_leg_id);

-- Sequence generator (server-assigned, never client-supplied) for custody events,
-- mirroring app.milestone_events' own server-assigned sequence_no discipline.
create function app.next_shipment_leg_custody_sequence(p_shipment_leg_id uuid)
returns integer
language sql
stable
as $$
  select coalesce(max(sequence_no), 0) + 1 from app.shipment_leg_custody_events where shipment_leg_id = p_shipment_leg_id;
$$;

-- app.add_shipment_leg (Prompt 221 §20 task 3). OPS:Create-gated. Idempotent on
-- (tenant_id, shipment_order_id, idempotency_key). Adding a leg to a shipment whose
-- network was already confirmed resets leg_network_status back to 'draft' -- a
-- confirmed network is a validated snapshot of a specific leg set, so any
-- membership change must be re-validated before execution resumes (Prompt 221 §22's
-- "add an approved transshipment... with impact preview" alternative flow).
create function app.add_shipment_leg(
  p_shipment_order_id uuid,
  p_idempotency_key text,
  p_sequence_no integer,
  p_mode text,
  p_carrier_master_id uuid,
  p_planned_departure_at timestamptz,
  p_planned_arrival_at timestamptz,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.shipment_legs
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_shipment app.shipment_orders;
  v_decision app.rbac_decision;
  v_existing app.shipment_legs;
  v_leg app.shipment_legs;
  v_sequence_taken boolean;
begin
  if p_mode not in ('land', 'air', 'sea') then
    raise exception 'invalid_mode: % is not a supported mode', p_mode using errcode = 'check_violation';
  end if;

  if p_idempotency_key is null or length(trim(p_idempotency_key)) = 0 then
    raise exception 'idempotency_key_required: a non-empty idempotency key is required' using errcode = 'check_violation';
  end if;

  if p_sequence_no is null or p_sequence_no <= 0 then
    raise exception 'invalid_sequence: sequence_no must be a positive integer' using errcode = 'check_violation';
  end if;

  select * into v_shipment from app.shipment_orders where id = p_shipment_order_id;
  if not found then
    raise exception 'shipment_order_not_found: %', p_shipment_order_id using errcode = 'no_data_found';
  end if;

  select * into v_existing from app.shipment_legs
    where tenant_id = v_shipment.tenant_id and shipment_order_id = p_shipment_order_id and idempotency_key = p_idempotency_key;
  if found then
    return v_existing;
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_shipment.tenant_id, 'OPS', 'Create');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Create (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_shipment.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if not app.can_access_record(p_actor_auth_user_id, v_shipment.tenant_id, v_shipment.owner_user_id, app.lead_record_scope_org_unit_ids(v_shipment.org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot access shipment order %', p_actor_auth_user_id, p_shipment_order_id
      using errcode = 'insufficient_privilege';
  end if;

  select exists (
    select 1 from app.shipment_legs where tenant_id = v_shipment.tenant_id and shipment_order_id = p_shipment_order_id and sequence_no = p_sequence_no and leg_status <> 'cancelled'
  ) into v_sequence_taken;
  if v_sequence_taken then
    raise exception 'leg_sequence_duplicate: sequence % is already used by an active leg of shipment order %', p_sequence_no, p_shipment_order_id
      using errcode = 'check_violation';
  end if;

  if p_carrier_master_id is not null then
    if not exists (
      select 1 from app.master_records
      where id = p_carrier_master_id and master_type_code in ('vendor', 'fleet') and canonical_status = 'active'
        and (tenant_id = v_shipment.tenant_id or tenant_id is null)
    ) then
      raise exception 'carrier_not_found: % is not a known active vendor/fleet reference for tenant %', p_carrier_master_id, v_shipment.tenant_id
        using errcode = 'no_data_found';
    end if;
  end if;

  begin
    insert into app.shipment_legs (
      tenant_id, shipment_order_id, sequence_no, idempotency_key, mode, carrier_master_id,
      planned_departure_at, planned_arrival_at, owner_user_id, created_by
    ) values (
      v_shipment.tenant_id, p_shipment_order_id, p_sequence_no, p_idempotency_key, p_mode, p_carrier_master_id,
      p_planned_departure_at, p_planned_arrival_at, v_shipment.owner_user_id, p_actor_label
    )
    returning * into v_leg;
  exception
    when unique_violation then
      select * into v_leg from app.shipment_legs
        where tenant_id = v_shipment.tenant_id and shipment_order_id = p_shipment_order_id and idempotency_key = p_idempotency_key;
      return v_leg;
  end;

  if v_shipment.leg_network_status = 'confirmed' then
    update app.shipment_orders set leg_network_status = 'draft' where id = p_shipment_order_id;
  elsif v_shipment.leg_network_status is null then
    update app.shipment_orders set leg_network_status = 'draft' where id = p_shipment_order_id;
  end if;

  perform app.capture_audit_event(
    v_shipment.tenant_id, p_actor_auth_user_id, p_actor_label, 'add_shipment_leg',
    'app.shipment_legs', v_leg.id, 'success', null, null,
    jsonb_build_object('shipment_order_id', p_shipment_order_id, 'sequence_no', p_sequence_no, 'mode', p_mode)
  );

  return v_leg;
end;
$$;

comment on function app.add_shipment_leg is
  'ATW-221: idempotent on (tenant_id, shipment_order_id, idempotency_key). sequence_no must be unique among that shipment''s own non-cancelled legs. Resets leg_network_status to draft (from confirmed or null) since membership just changed and must be re-validated.';

-- app.cancel_shipment_leg -- the one leg-removal path (never a hard delete, matching
-- this repository''s append-only-preferring discipline). Only a leg still in
-- 'planned' may be cancelled directly; a leg that has already started execution
-- (dispatched/in_transit/arrived) is immutable here and must instead go through
-- app.transition_shipment_leg's own governed edges.
create function app.cancel_shipment_leg(
  p_shipment_leg_id uuid,
  p_expected_version integer,
  p_reason text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.shipment_legs
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_leg app.shipment_legs;
  v_shipment app.shipment_orders;
  v_decision app.rbac_decision;
begin
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'cancel_reason_required: a non-empty reason is required to cancel a leg' using errcode = 'check_violation';
  end if;

  select * into v_leg from app.shipment_legs where id = p_shipment_leg_id;
  if not found then
    raise exception 'leg_not_found: %', p_shipment_leg_id using errcode = 'no_data_found';
  end if;

  select * into v_shipment from app.shipment_orders where id = v_leg.shipment_order_id;

  if v_leg.record_version <> p_expected_version then
    raise exception 'stale_version: leg % expected version % but found %', p_shipment_leg_id, p_expected_version, v_leg.record_version
      using errcode = 'serialization_failure';
  end if;

  if v_leg.leg_status <> 'planned' then
    raise exception 'leg_not_mutable: leg % is % and can only be cancelled while planned', p_shipment_leg_id, v_leg.leg_status
      using errcode = 'check_violation';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_shipment.tenant_id, 'OPS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_shipment.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if not app.can_access_record(p_actor_auth_user_id, v_shipment.tenant_id, v_shipment.owner_user_id, app.lead_record_scope_org_unit_ids(v_shipment.org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot access shipment order %', p_actor_auth_user_id, v_leg.shipment_order_id
      using errcode = 'insufficient_privilege';
  end if;

  update app.shipment_legs set leg_status = 'cancelled' where id = p_shipment_leg_id and record_version = p_expected_version
  returning * into v_leg;

  if v_shipment.leg_network_status = 'confirmed' then
    update app.shipment_orders set leg_network_status = 'draft' where id = v_leg.shipment_order_id;
  end if;

  perform app.capture_audit_event(
    v_shipment.tenant_id, p_actor_auth_user_id, p_actor_label, 'cancel_shipment_leg',
    'app.shipment_legs', v_leg.id, 'success', null, null, jsonb_build_object('reason', p_reason)
  );

  return v_leg;
end;
$$;

comment on function app.cancel_shipment_leg is
  'ATW-221: planned-only cancellation (never a hard delete). Resets leg_network_status to draft if the network had been confirmed, since the leg set just changed.';

-- app.add_shipment_leg_stop (Prompt 221 §20 task 3). Only while the owning leg is
-- 'planned' (started-leg destructive edit prevention, Prompt 221 §23).
create function app.add_shipment_leg_stop(
  p_shipment_leg_id uuid,
  p_stop_sequence integer,
  p_stop_type text,
  p_location_name text,
  p_address text,
  p_longitude numeric,
  p_latitude numeric,
  p_planned_at timestamptz,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.shipment_leg_stops
language plpgsql
security definer
set search_path = app, public, pg_temp
as $$
declare
  v_leg app.shipment_legs;
  v_shipment app.shipment_orders;
  v_decision app.rbac_decision;
  v_stop app.shipment_leg_stops;
  v_geog geography;
begin
  if p_stop_type not in ('pickup', 'transfer', 'delivery') then
    raise exception 'invalid_stop_type: % is not a supported stop type', p_stop_type using errcode = 'check_violation';
  end if;

  if p_stop_sequence is null or p_stop_sequence <= 0 then
    raise exception 'invalid_sequence: stop_sequence must be a positive integer' using errcode = 'check_violation';
  end if;

  if p_location_name is null or length(trim(p_location_name)) = 0 then
    raise exception 'location_name_required: a non-empty location_name is required' using errcode = 'check_violation';
  end if;

  select * into v_leg from app.shipment_legs where id = p_shipment_leg_id;
  if not found then
    raise exception 'leg_not_found: %', p_shipment_leg_id using errcode = 'no_data_found';
  end if;

  select * into v_shipment from app.shipment_orders where id = v_leg.shipment_order_id;

  if v_leg.leg_status <> 'planned' then
    raise exception 'leg_not_mutable: leg % is % and its stops can only be edited while planned', p_shipment_leg_id, v_leg.leg_status
      using errcode = 'check_violation';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_shipment.tenant_id, 'OPS', 'Create');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Create (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_shipment.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if not app.can_access_record(p_actor_auth_user_id, v_shipment.tenant_id, v_shipment.owner_user_id, app.lead_record_scope_org_unit_ids(v_shipment.org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot access shipment order %', p_actor_auth_user_id, v_leg.shipment_order_id
      using errcode = 'insufficient_privilege';
  end if;

  if p_longitude is not null and p_latitude is not null then
    v_geog := app.geojson_point_to_geography(jsonb_build_object('type', 'Point', 'coordinates', jsonb_build_array(p_longitude, p_latitude)));
  end if;

  insert into app.shipment_leg_stops (
    tenant_id, shipment_leg_id, stop_sequence, stop_type, location_name, address, location_geog, planned_at, created_by
  ) values (
    v_leg.tenant_id, p_shipment_leg_id, p_stop_sequence, p_stop_type, p_location_name, p_address, v_geog, p_planned_at, p_actor_label
  )
  returning * into v_stop;

  perform app.capture_audit_event(
    v_leg.tenant_id, p_actor_auth_user_id, p_actor_label, 'add_shipment_leg_stop',
    'app.shipment_leg_stops', v_stop.id, 'success', null, null,
    jsonb_build_object('shipment_leg_id', p_shipment_leg_id, 'stop_sequence', p_stop_sequence, 'stop_type', p_stop_type)
  );

  return v_stop;
end;
$$;

comment on function app.add_shipment_leg_stop is
  'ATW-221: only while the owning leg is planned. location_geog is built via app.geojson_point_to_geography (PLT-134 convention) when longitude/latitude are both supplied; either may be omitted for a stop with no known coordinates yet.';

-- app.allocate_shipment_leg_cargo (Prompt 221 §20 task 3, business rule "allocated
-- quantity across active legs never exceeds source cargo"). Upsert-shaped (one
-- allocation per leg); enforces the sum across every non-cancelled leg of the
-- shipment never exceeds that Shipment Order's own allocated_* basis.
create function app.allocate_shipment_leg_cargo(
  p_shipment_leg_id uuid,
  p_allocated_quantity numeric,
  p_allocated_weight_kg numeric,
  p_allocated_volume_cbm numeric,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.shipment_leg_cargo_allocations
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_leg app.shipment_legs;
  v_shipment app.shipment_orders;
  v_decision app.rbac_decision;
  v_other_qty numeric;
  v_other_weight numeric;
  v_other_volume numeric;
  v_allocation app.shipment_leg_cargo_allocations;
begin
  select * into v_leg from app.shipment_legs where id = p_shipment_leg_id;
  if not found then
    raise exception 'leg_not_found: %', p_shipment_leg_id using errcode = 'no_data_found';
  end if;

  select * into v_shipment from app.shipment_orders where id = v_leg.shipment_order_id;

  if v_leg.leg_status <> 'planned' then
    raise exception 'leg_not_mutable: leg % is % and its cargo allocation can only be edited while planned', p_shipment_leg_id, v_leg.leg_status
      using errcode = 'check_violation';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_shipment.tenant_id, 'OPS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_shipment.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if not app.can_access_record(p_actor_auth_user_id, v_shipment.tenant_id, v_shipment.owner_user_id, app.lead_record_scope_org_unit_ids(v_shipment.org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot access shipment order %', p_actor_auth_user_id, v_leg.shipment_order_id
      using errcode = 'insufficient_privilege';
  end if;

  select coalesce(sum(a.allocated_quantity), 0), coalesce(sum(a.allocated_weight_kg), 0), coalesce(sum(a.allocated_volume_cbm), 0)
    into v_other_qty, v_other_weight, v_other_volume
  from app.shipment_leg_cargo_allocations a
  join app.shipment_legs sl on sl.id = a.shipment_leg_id
  where sl.shipment_order_id = v_leg.shipment_order_id and sl.leg_status <> 'cancelled' and a.shipment_leg_id <> p_shipment_leg_id;

  if v_shipment.allocated_quantity is not null and (v_other_qty + coalesce(p_allocated_quantity, 0)) > v_shipment.allocated_quantity then
    raise exception 'cargo_over_allocated: allocated_quantity % across legs exceeds shipment allocation %', (v_other_qty + coalesce(p_allocated_quantity, 0)), v_shipment.allocated_quantity
      using errcode = 'check_violation';
  end if;
  if v_shipment.allocated_weight_kg is not null and (v_other_weight + coalesce(p_allocated_weight_kg, 0)) > v_shipment.allocated_weight_kg then
    raise exception 'cargo_over_allocated: allocated_weight_kg % across legs exceeds shipment allocation %', (v_other_weight + coalesce(p_allocated_weight_kg, 0)), v_shipment.allocated_weight_kg
      using errcode = 'check_violation';
  end if;
  if v_shipment.allocated_volume_cbm is not null and (v_other_volume + coalesce(p_allocated_volume_cbm, 0)) > v_shipment.allocated_volume_cbm then
    raise exception 'cargo_over_allocated: allocated_volume_cbm % across legs exceeds shipment allocation %', (v_other_volume + coalesce(p_allocated_volume_cbm, 0)), v_shipment.allocated_volume_cbm
      using errcode = 'check_violation';
  end if;

  insert into app.shipment_leg_cargo_allocations (tenant_id, shipment_leg_id, allocated_quantity, allocated_weight_kg, allocated_volume_cbm, created_by)
  values (v_leg.tenant_id, p_shipment_leg_id, p_allocated_quantity, p_allocated_weight_kg, p_allocated_volume_cbm, p_actor_label)
  on conflict (shipment_leg_id) do update set
    allocated_quantity = excluded.allocated_quantity,
    allocated_weight_kg = excluded.allocated_weight_kg,
    allocated_volume_cbm = excluded.allocated_volume_cbm
  returning * into v_allocation;

  perform app.capture_audit_event(
    v_leg.tenant_id, p_actor_auth_user_id, p_actor_label, 'allocate_shipment_leg_cargo',
    'app.shipment_leg_cargo_allocations', v_allocation.id, 'success', null, null,
    jsonb_build_object('shipment_leg_id', p_shipment_leg_id, 'allocated_quantity', p_allocated_quantity, 'allocated_weight_kg', p_allocated_weight_kg, 'allocated_volume_cbm', p_allocated_volume_cbm)
  );

  return v_allocation;
end;
$$;

comment on function app.allocate_shipment_leg_cargo is
  'ATW-221: one allocation per leg (upsert). The sum across every non-cancelled leg of the same shipment is checked against that Shipment Order''s own allocated_quantity/allocated_weight_kg/allocated_volume_cbm, per dimension independently -- a null shipment-level dimension is advisory-only (no cap), matching app.get_job_shipment_allocation_balance''s own null-basis convention.';

-- app.confirm_shipment_leg_network (Prompt 221 §21 "validates the network").
-- Requires: at least one non-cancelled leg; sequence numbers among non-cancelled
-- legs form a contiguous 1..N series with no gap or duplicate; every non-cancelled
-- leg has a cargo allocation. Sets leg_network_status = 'confirmed'.
create function app.confirm_shipment_leg_network(
  p_shipment_order_id uuid,
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
  v_leg_count integer;
  v_max_sequence integer;
  v_distinct_sequence_count integer;
  v_unallocated_count integer;
begin
  select * into v_shipment from app.shipment_orders where id = p_shipment_order_id;
  if not found then
    raise exception 'shipment_order_not_found: %', p_shipment_order_id using errcode = 'no_data_found';
  end if;

  if v_shipment.record_version <> p_expected_version then
    raise exception 'stale_version: shipment order % expected version % but found %', p_shipment_order_id, p_expected_version, v_shipment.record_version
      using errcode = 'serialization_failure';
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

  select count(*), max(sequence_no), count(distinct sequence_no)
    into v_leg_count, v_max_sequence, v_distinct_sequence_count
  from app.shipment_legs where shipment_order_id = p_shipment_order_id and leg_status <> 'cancelled';

  if v_leg_count = 0 then
    raise exception 'network_empty: shipment order % has no active leg to confirm', p_shipment_order_id using errcode = 'check_violation';
  end if;

  if v_distinct_sequence_count <> v_leg_count or v_max_sequence <> v_leg_count then
    raise exception 'network_sequence_gap: shipment order % legs must form a contiguous 1..% sequence with no gap or duplicate', p_shipment_order_id, v_leg_count
      using errcode = 'check_violation';
  end if;

  select count(*) into v_unallocated_count
  from app.shipment_legs sl
  where sl.shipment_order_id = p_shipment_order_id and sl.leg_status <> 'cancelled'
    and not exists (select 1 from app.shipment_leg_cargo_allocations a where a.shipment_leg_id = sl.id);
  if v_unallocated_count > 0 then
    raise exception 'network_cargo_incomplete: % leg(s) of shipment order % have no cargo allocation', v_unallocated_count, p_shipment_order_id
      using errcode = 'check_violation';
  end if;

  update app.shipment_orders set leg_network_status = 'confirmed' where id = p_shipment_order_id and record_version = p_expected_version
  returning * into v_shipment;

  perform app.capture_audit_event(
    v_shipment.tenant_id, p_actor_auth_user_id, p_actor_label, 'confirm_shipment_leg_network',
    'app.shipment_orders', v_shipment.id, 'success', null, null, jsonb_build_object('leg_count', v_leg_count)
  );

  return v_shipment;
end;
$$;

comment on function app.confirm_shipment_leg_network is
  'ATW-221: validates leg-sequence contiguity (no gap/duplicate among non-cancelled legs) and that every non-cancelled leg carries a cargo allocation, then sets leg_network_status = confirmed. Never touches the Shipment Order''s own canonical status.';

-- app.transition_shipment_leg -- hardcoded edge matrix, mirroring
-- app.transition_shipment_order's own hand-rolled state-machine discipline (OPS-170)
-- at a smaller, leg-scoped grain. A leg may only leave 'planned' once its own
-- shipment's leg network is confirmed (dispatch requires a validated network).
create function app.transition_shipment_leg(
  p_shipment_leg_id uuid,
  p_to_status text,
  p_expected_version integer,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.shipment_legs
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_leg app.shipment_legs;
  v_shipment app.shipment_orders;
  v_decision app.rbac_decision;
  v_allowed boolean := false;
begin
  select * into v_leg from app.shipment_legs where id = p_shipment_leg_id;
  if not found then
    raise exception 'leg_not_found: %', p_shipment_leg_id using errcode = 'no_data_found';
  end if;

  select * into v_shipment from app.shipment_orders where id = v_leg.shipment_order_id;

  if v_leg.record_version <> p_expected_version then
    raise exception 'stale_version: leg % expected version % but found %', p_shipment_leg_id, p_expected_version, v_leg.record_version
      using errcode = 'serialization_failure';
  end if;

  v_allowed := (v_leg.leg_status = 'planned' and p_to_status = 'dispatched')
    or (v_leg.leg_status = 'dispatched' and p_to_status = 'in_transit')
    or (v_leg.leg_status = 'in_transit' and p_to_status = 'arrived')
    or (v_leg.leg_status = 'arrived' and p_to_status = 'completed')
    or (v_leg.leg_status in ('planned', 'dispatched', 'in_transit', 'arrived') and p_to_status = 'cancelled');

  if not v_allowed then
    raise exception 'invalid_leg_status_transition: leg % cannot move from % to %', p_shipment_leg_id, v_leg.leg_status, p_to_status
      using errcode = 'check_violation';
  end if;

  if v_leg.leg_status = 'planned' and p_to_status = 'dispatched' and v_shipment.leg_network_status <> 'confirmed' then
    raise exception 'network_not_confirmed: shipment order % leg network must be confirmed before any leg can dispatch', v_leg.shipment_order_id
      using errcode = 'check_violation';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_shipment.tenant_id, 'OPS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_shipment.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if not app.can_access_record(p_actor_auth_user_id, v_shipment.tenant_id, v_shipment.owner_user_id, app.lead_record_scope_org_unit_ids(v_shipment.org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot access shipment order %', p_actor_auth_user_id, v_leg.shipment_order_id
      using errcode = 'insufficient_privilege';
  end if;

  update app.shipment_legs
  set leg_status = p_to_status,
      actual_departure_at = case when p_to_status = 'dispatched' and actual_departure_at is null then now() else actual_departure_at end,
      actual_arrival_at = case when p_to_status = 'arrived' and actual_arrival_at is null then now() else actual_arrival_at end
  where id = p_shipment_leg_id and record_version = p_expected_version
  returning * into v_leg;

  perform app.capture_audit_event(
    v_shipment.tenant_id, p_actor_auth_user_id, p_actor_label, 'transition_shipment_leg',
    'app.shipment_legs', v_leg.id, 'success', null, jsonb_build_object('leg_status', p_to_status), jsonb_build_object('leg_status', v_leg.leg_status)
  );

  return v_leg;
end;
$$;

comment on function app.transition_shipment_leg is
  'ATW-221: hardcoded edges planned->dispatched->in_transit->arrived->completed, plus any non-terminal state->cancelled. A leg cannot leave planned for dispatched until its own shipment''s leg_network_status is confirmed.';

-- app.record_shipment_leg_custody_event -- append-only, server-assigned sequence_no.
create function app.record_shipment_leg_custody_event(
  p_shipment_leg_id uuid,
  p_event_type text,
  p_from_party_snapshot jsonb,
  p_to_party_snapshot jsonb,
  p_occurred_at timestamptz,
  p_evidence jsonb,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.shipment_leg_custody_events
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_leg app.shipment_legs;
  v_shipment app.shipment_orders;
  v_decision app.rbac_decision;
  v_event app.shipment_leg_custody_events;
  v_sequence integer;
begin
  if p_event_type not in ('custody_transfer', 'handoff_confirmed') then
    raise exception 'invalid_event_type: % is not a supported custody event type', p_event_type using errcode = 'check_violation';
  end if;

  if p_to_party_snapshot is null then
    raise exception 'to_party_required: a custody event must name the party that now holds custody' using errcode = 'check_violation';
  end if;

  select * into v_leg from app.shipment_legs where id = p_shipment_leg_id;
  if not found then
    raise exception 'leg_not_found: %', p_shipment_leg_id using errcode = 'no_data_found';
  end if;

  select * into v_shipment from app.shipment_orders where id = v_leg.shipment_order_id;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_shipment.tenant_id, 'OPS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_shipment.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if not app.can_access_record(p_actor_auth_user_id, v_shipment.tenant_id, v_shipment.owner_user_id, app.lead_record_scope_org_unit_ids(v_shipment.org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot access shipment order %', p_actor_auth_user_id, v_leg.shipment_order_id
      using errcode = 'insufficient_privilege';
  end if;

  v_sequence := app.next_shipment_leg_custody_sequence(p_shipment_leg_id);

  insert into app.shipment_leg_custody_events (
    tenant_id, shipment_leg_id, sequence_no, event_type, from_party_snapshot, to_party_snapshot, occurred_at, evidence, recorded_by
  ) values (
    v_leg.tenant_id, p_shipment_leg_id, v_sequence, p_event_type, p_from_party_snapshot, p_to_party_snapshot, p_occurred_at, p_evidence, p_actor_label
  )
  returning * into v_event;

  perform app.capture_audit_event(
    v_shipment.tenant_id, p_actor_auth_user_id, p_actor_label, 'record_shipment_leg_custody_event',
    'app.shipment_leg_custody_events', v_event.id, 'success', null, null,
    jsonb_build_object('shipment_leg_id', p_shipment_leg_id, 'event_type', p_event_type, 'sequence_no', v_sequence)
  );

  return v_event;
end;
$$;

comment on function app.record_shipment_leg_custody_event is
  'ATW-221: append-only, server-assigned sequence_no (never client-supplied) -- preserves custody lineage per leg. to_party_snapshot is mandatory.';

-- app.migrate_legacy_shipment_to_leg_network (Prompt 221 §19 "evolve existing
-- single-leg shipments into one explicit legacy-compatible leg with reversible
-- mapping"). Idempotent: a shipment that already has any leg is a no-op returning
-- the existing legacy leg. Copies the shipment's own mode/schedule/allocation/
-- origin/destination verbatim into one sequence=1 leg with two stops (pickup at
-- origin, delivery at destination), then immediately confirms the (trivially
-- valid, single-leg) network -- no further planning is needed for a straight
-- single-leg mapping.
create function app.migrate_legacy_shipment_to_leg_network(
  p_shipment_order_id uuid,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.shipment_legs
language plpgsql
security definer
set search_path = app, public, pg_temp
as $$
declare
  v_shipment app.shipment_orders;
  v_decision app.rbac_decision;
  v_existing app.shipment_legs;
  v_leg app.shipment_legs;
  v_leg_status text;
begin
  select * into v_shipment from app.shipment_orders where id = p_shipment_order_id;
  if not found then
    raise exception 'shipment_order_not_found: %', p_shipment_order_id using errcode = 'no_data_found';
  end if;

  select * into v_existing from app.shipment_legs where shipment_order_id = p_shipment_order_id order by sequence_no asc limit 1;
  if found then
    return v_existing;
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

  v_leg_status := case
    when v_shipment.status in ('delivered', 'epod', 'closed') then 'completed'
    when v_shipment.status in ('dispatched', 'in_transit') then v_shipment.status
    else 'planned'
  end;

  insert into app.shipment_legs (
    tenant_id, shipment_order_id, sequence_no, idempotency_key, mode, leg_status, is_legacy_compat,
    planned_departure_at, planned_arrival_at, owner_user_id, created_by
  ) values (
    v_shipment.tenant_id, p_shipment_order_id, 1, 'legacy-compat:' || p_shipment_order_id::text, v_shipment.mode, v_leg_status, true,
    v_shipment.planned_pickup_at, v_shipment.planned_delivery_at, v_shipment.owner_user_id, p_actor_label
  )
  returning * into v_leg;

  insert into app.shipment_leg_stops (tenant_id, shipment_leg_id, stop_sequence, stop_type, location_name, planned_at, created_by)
  values
    (v_shipment.tenant_id, v_leg.id, 1, 'pickup', v_shipment.origin, v_shipment.planned_pickup_at, p_actor_label),
    (v_shipment.tenant_id, v_leg.id, 2, 'delivery', v_shipment.destination, v_shipment.planned_delivery_at, p_actor_label);

  insert into app.shipment_leg_cargo_allocations (tenant_id, shipment_leg_id, allocated_quantity, allocated_weight_kg, allocated_volume_cbm, created_by)
  values (v_shipment.tenant_id, v_leg.id, v_shipment.allocated_quantity, v_shipment.allocated_weight_kg, v_shipment.allocated_volume_cbm, p_actor_label);

  update app.shipment_orders set leg_network_status = 'confirmed' where id = p_shipment_order_id;

  perform app.capture_audit_event(
    v_shipment.tenant_id, p_actor_auth_user_id, p_actor_label, 'migrate_legacy_shipment_to_leg_network',
    'app.shipment_legs', v_leg.id, 'success', null, null,
    jsonb_build_object('shipment_order_id', p_shipment_order_id, 'leg_status', v_leg_status)
  );

  return v_leg;
end;
$$;

comment on function app.migrate_legacy_shipment_to_leg_network is
  'ATW-221: idempotent expand-only backfill for a pre-existing single-leg Shipment Order. Reversible in the sense that no Shipment Order data is altered -- only a new is_legacy_compat leg (plus its two stops and one cargo allocation) is added, and leg_network_status is set to confirmed since a straight 1:1 mapping needs no further planning.';

-- app.get_shipment_leg_network_state -- a read-only, live-derived aggregate label
-- (never stored) over one shipment's own non-cancelled legs, satisfying Prompt 221
-- §24's "aggregate shipment state is derived from canonical leg states under a
-- versioned rule" without mutating app.shipment_orders.status (OPS-170's own
-- canonical lifecycle stays the single authoritative status field).
create function app.get_shipment_leg_network_state(p_shipment_order_id uuid)
returns text
language sql
stable
security definer
set search_path = app, pg_temp
as $$
  select case
    when not exists (select 1 from app.shipment_legs where shipment_order_id = p_shipment_order_id and leg_status <> 'cancelled') then 'not_started'
    when (select leg_network_status from app.shipment_orders where id = p_shipment_order_id) is distinct from 'confirmed' then 'blocked'
    when not exists (select 1 from app.shipment_legs where shipment_order_id = p_shipment_order_id and leg_status <> 'cancelled' and leg_status <> 'completed') then 'completed'
    when exists (select 1 from app.shipment_legs where shipment_order_id = p_shipment_order_id and leg_status in ('dispatched', 'in_transit', 'arrived')) then 'in_progress'
    else 'not_started'
  end;
$$;

comment on function app.get_shipment_leg_network_state is
  'ATW-221: versioned aggregation rule v1 -- not_started (no active leg, or all legs still planned), blocked (network not yet confirmed but at least one leg exists), in_progress (any active leg dispatched/in_transit/arrived), completed (every non-cancelled leg is completed). Live-derived on every read, never stored, so it can never drift from the underlying legs.';

-- app.get_shipment_leg_stops -- the one read path for stops. Serializes
-- location_geog into GeoJSON via app.geography_to_geojson_point (the PLT-134/
-- ADR-0014 convention) rather than exposing the raw geography wire format through
-- a direct table select, mirroring how every other domain projects a computed
-- read shape instead of a raw internal column.
create function app.get_shipment_leg_stops(p_shipment_leg_id uuid)
returns table (
  id uuid,
  tenant_id uuid,
  shipment_leg_id uuid,
  stop_sequence integer,
  stop_type text,
  location_name text,
  address text,
  location_geojson jsonb,
  planned_at timestamptz,
  actual_at timestamptz,
  stop_status text,
  record_version integer,
  created_at timestamptz,
  updated_at timestamptz
)
language sql
stable
security invoker
set search_path = app, public, pg_temp
as $$
  select
    s.id, s.tenant_id, s.shipment_leg_id, s.stop_sequence, s.stop_type, s.location_name, s.address,
    app.geography_to_geojson_point(s.location_geog), s.planned_at, s.actual_at, s.stop_status, s.record_version, s.created_at, s.updated_at
  from app.shipment_leg_stops s
  where s.shipment_leg_id = p_shipment_leg_id
  order by s.stop_sequence asc;
$$;

comment on function app.get_shipment_leg_stops is
  'ATW-221: security invoker (relies on the caller''s own RLS on app.shipment_leg_stops, matching every other plain projection function in this repository) -- serializes location_geog to GeoJSON, never returning the raw geography wire format.';

alter table app.shipment_legs enable row level security;
alter table app.shipment_leg_stops enable row level security;
alter table app.shipment_leg_cargo_allocations enable row level security;
alter table app.shipment_leg_custody_events enable row level security;

create policy shipment_legs_select_scoped on app.shipment_legs
  for select to authenticated
  using (
    exists (
      select 1 from app.shipment_orders so
      where so.id = shipment_legs.shipment_order_id
        and app.can_access_record(auth.uid(), so.tenant_id, so.owner_user_id, app.lead_record_scope_org_unit_ids(so.org_unit_id), null)
    )
  );

create policy shipment_leg_stops_select_scoped on app.shipment_leg_stops
  for select to authenticated
  using (
    exists (
      select 1 from app.shipment_legs sl
      join app.shipment_orders so on so.id = sl.shipment_order_id
      where sl.id = shipment_leg_stops.shipment_leg_id
        and app.can_access_record(auth.uid(), so.tenant_id, so.owner_user_id, app.lead_record_scope_org_unit_ids(so.org_unit_id), null)
    )
  );

create policy shipment_leg_cargo_allocations_select_scoped on app.shipment_leg_cargo_allocations
  for select to authenticated
  using (
    exists (
      select 1 from app.shipment_legs sl
      join app.shipment_orders so on so.id = sl.shipment_order_id
      where sl.id = shipment_leg_cargo_allocations.shipment_leg_id
        and app.can_access_record(auth.uid(), so.tenant_id, so.owner_user_id, app.lead_record_scope_org_unit_ids(so.org_unit_id), null)
    )
  );

create policy shipment_leg_custody_events_select_scoped on app.shipment_leg_custody_events
  for select to authenticated
  using (
    exists (
      select 1 from app.shipment_legs sl
      join app.shipment_orders so on so.id = sl.shipment_order_id
      where sl.id = shipment_leg_custody_events.shipment_leg_id
        and app.can_access_record(auth.uid(), so.tenant_id, so.owner_user_id, app.lead_record_scope_org_unit_ids(so.org_unit_id), null)
    )
  );

revoke execute on all functions in schema app from public;

grant select on app.shipment_legs to authenticated, service_role;
grant insert, update, delete on app.shipment_legs to service_role;
grant select on app.shipment_leg_stops to authenticated, service_role;
grant insert, update, delete on app.shipment_leg_stops to service_role;
grant select on app.shipment_leg_cargo_allocations to authenticated, service_role;
grant insert, update, delete on app.shipment_leg_cargo_allocations to service_role;
grant select on app.shipment_leg_custody_events to authenticated, service_role;
grant insert, update, delete on app.shipment_leg_custody_events to service_role;

grant execute on function app.next_shipment_leg_custody_sequence(uuid) to authenticated, service_role;
grant execute on function app.add_shipment_leg(uuid, text, integer, text, uuid, timestamptz, timestamptz, uuid, text) to authenticated, service_role;
grant execute on function app.cancel_shipment_leg(uuid, integer, text, uuid, text) to authenticated, service_role;
grant execute on function app.add_shipment_leg_stop(uuid, integer, text, text, text, numeric, numeric, timestamptz, uuid, text) to authenticated, service_role;
grant execute on function app.allocate_shipment_leg_cargo(uuid, numeric, numeric, numeric, uuid, text) to authenticated, service_role;
grant execute on function app.confirm_shipment_leg_network(uuid, integer, uuid, text) to authenticated, service_role;
grant execute on function app.transition_shipment_leg(uuid, text, integer, uuid, text) to authenticated, service_role;
grant execute on function app.record_shipment_leg_custody_event(uuid, text, jsonb, jsonb, timestamptz, jsonb, uuid, text) to authenticated, service_role;
grant execute on function app.migrate_legacy_shipment_to_leg_network(uuid, uuid, text) to authenticated, service_role;
grant execute on function app.get_shipment_leg_network_state(uuid) to authenticated, service_role;
grant execute on function app.get_shipment_leg_stops(uuid) to authenticated, service_role;
