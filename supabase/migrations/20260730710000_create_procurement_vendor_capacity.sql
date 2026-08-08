-- Procurement capability PRC-262 (Vendor Capacity and Availability, CG-S11-PRC-013),
-- batch 3 (261-263) of the operator's "lanjut sd prompt 265" authorization, prompt 2 of
-- 3. Depends on PRC-261 (app.vendor_contracts, for the optional governing-contract
-- link) built earlier in this same batch.
--
-- Vendor-owned capacity declaration, blackout, reservation, acceptance and release --
-- extends, never duplicates, Phase 5's own canonical resource identities (Prompt 262
-- §24). Unlike Phase 5's app.vehicle_capacity_reservations (a single-vehicle,
-- single-leg hold keyed by a unique index), vendor capacity is a QUANTITY offered over
-- a TIME WINDOW that can be partially consumed by multiple concurrent reservations --
-- "available" requires real overlap arithmetic under a lock, not a unique-index
-- collision, so this migration cannot simply reuse that table's own shape.
--
-- Design decisions, disclosed rather than left implicit:
--
-- 1. **No vendor-portal identity exists (already-accepted PRC-257/258/261 precedent).**
--    Every offer/reservation-lifecycle action here is staff-initiated on the vendor's
--    behalf ("internal declaration" per §26), disclosed rather than fabricating a
--    vendor-facing acceptance surface. `accept_vendor_capacity_reservation` records a
--    staff actor's own confirmation, not a live vendor response.
-- 2. **Concurrency-safe reservation, by design, not by convention (§24 "no silent
--    overbooking").** `app.reserve_vendor_capacity` locks the PARENT OFFER row `for
--    update` before computing `available = quantity - sum(overlapping active
--    reservations)` -- every concurrent reservation attempt against the SAME offer
--    serializes through that one lock, so two racing callers can never both observe
--    "capacity available" for the same over-committing pair (this prompt's own Tier B
--    self-check, applying the C-04 lesson learned live during PRC-261 immediately
--    before this one, from the very first draft rather than discovered by later
--    review).
-- 3. **One offer, one UOM -- reservations carry no UOM of their own.** A reservation
--    always draws against exactly one offer, so its `requested_quantity` is
--    definitionally in that offer's own `uom`; a separate per-reservation UOM column
--    would only create a mismatch class to defend against for no real requirement.
-- 4. **Idempotency replay compares the full target tuple, not just the key (C-01,
--    applied from the start).** Both `create_vendor_capacity_offer_draft` and
--    `reserve_vendor_capacity` raise `idempotency_key_conflict` on a key reused for a
--    genuinely different vendor/window/quantity, mirroring PRC-261's own
--    Tier-B-corrected shape.
-- 5. **By-id reads fold "not found" and "cross-tenant, zero-membership" into the SAME
--    not-found error from the start (C-05, applied from the start)** -- mirrors
--    `app.get_purchase_order`/`app.get_vendor_contract`'s own established shape.
-- 6. **Blackouts do not retroactively cancel existing reservations.** Adding a
--    blackout after a reservation already exists in that window blocks only FUTURE
--    reservation attempts; an existing hold must be explicitly declined/released.
--    Disclosed rather than silently auto-cancelling live commitments.
-- 7. **No PRC:View cost masking in this capability.** Unlike PRC-261 (rate/payment
--    terms), nothing in this schema is commercial/cost-shaped -- quantity, window, and
--    resource references are operational facts, not pricing. §16's "internal
--    budgets/customer demand are hidden" concern has no live enforcement point here
--    either (no vendor-portal exists to hide them FROM, design note 1) -- disclosed,
--    not fabricated as an unreachable mask.
--
-- Per ERR-2026-004: explicit `revoke execute on all functions in schema app from
-- public` before final grants, the standing per-migration convention since PLT-118.

-- ===========================================================================
-- 1. app.vendor_capacity_offers.
-- ===========================================================================

create table app.vendor_capacity_offers (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  vendor_master_id uuid not null references app.vendor_profiles (master_record_id),
  contract_id uuid references app.vendor_contracts (id),
  service_type text not null,
  mode text,
  origin_lane text,
  destination_lane text,
  resource_type text not null default 'general',
  resource_master_id uuid references app.master_records (id),
  quantity numeric(14, 3) not null,
  uom text not null,
  window_start timestamptz not null,
  window_end timestamptz not null,
  status text not null default 'draft',
  idempotency_key text,
  record_version integer not null default 1,
  created_by text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint vendor_capacity_offers_service_type_check check (length(trim(service_type)) > 0),
  constraint vendor_capacity_offers_resource_type_check check (resource_type in ('vehicle', 'warehouse', 'driver', 'general')),
  constraint vendor_capacity_offers_quantity_check check (quantity > 0),
  constraint vendor_capacity_offers_uom_check check (length(trim(uom)) > 0),
  constraint vendor_capacity_offers_window_check check (window_end > window_start),
  constraint vendor_capacity_offers_status_check check (status in ('draft', 'published', 'archived'))
);

comment on table app.vendor_capacity_offers is
  'PRC-262: one row per vendor-declared capacity offer (quantity available over a time window for a service/mode/lane). resource_master_id optionally references a canonical Phase 5 resource (vehicle/warehouse/driver) when the vendor capacity is known to correspond to one -- never required, never a second resource identity (design note 0, business rule).';

create index vendor_capacity_offers_tenant_vendor_status_idx on app.vendor_capacity_offers (tenant_id, vendor_master_id, status);
create index vendor_capacity_offers_tenant_service_idx on app.vendor_capacity_offers (tenant_id, service_type, status);
create index vendor_capacity_offers_window_idx on app.vendor_capacity_offers (window_start, window_end) where status = 'published';
create unique index vendor_capacity_offers_idempotency_key_unique on app.vendor_capacity_offers (tenant_id, idempotency_key) where idempotency_key is not null;

create function app.enforce_vendor_capacity_offer_identity()
returns trigger
language plpgsql
as $$
declare
  v_vendor app.vendor_profiles;
  v_resource app.master_records;
  v_contract app.vendor_contracts;
begin
  select * into v_vendor from app.vendor_profiles where master_record_id = new.vendor_master_id;
  if not found then
    raise exception 'vendor_profile_not_found: no vendor profile %', new.vendor_master_id using errcode = 'foreign_key_violation';
  end if;
  if v_vendor.tenant_id is distinct from new.tenant_id then
    raise exception 'invalid_vendor_identity: vendor profile % belongs to tenant %, not %', new.vendor_master_id, v_vendor.tenant_id, new.tenant_id
      using errcode = 'check_violation';
  end if;

  if new.resource_master_id is not null then
    select * into v_resource from app.master_records where id = new.resource_master_id;
    if not found or v_resource.tenant_id is distinct from new.tenant_id then
      raise exception 'invalid_resource_reference: resource % does not resolve within tenant %', new.resource_master_id, new.tenant_id
        using errcode = 'check_violation';
    end if;
  end if;

  if new.contract_id is not null then
    select * into v_contract from app.vendor_contracts where id = new.contract_id;
    if not found or v_contract.tenant_id is distinct from new.tenant_id or v_contract.vendor_master_id is distinct from new.vendor_master_id then
      raise exception 'invalid_contract_reference: contract % does not govern vendor % in tenant %', new.contract_id, new.vendor_master_id, new.tenant_id
        using errcode = 'check_violation';
    end if;
  end if;

  return new;
end;
$$;

create trigger vendor_capacity_offers_enforce_identity
  before insert or update of vendor_master_id, tenant_id, resource_master_id, contract_id on app.vendor_capacity_offers
  for each row
  execute function app.enforce_vendor_capacity_offer_identity();

create function app.touch_vendor_capacity_offers_row()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  new.record_version := old.record_version + 1;
  return new;
end;
$$;

create trigger vendor_capacity_offers_touch_row
  before update on app.vendor_capacity_offers
  for each row
  execute function app.touch_vendor_capacity_offers_row();

-- ===========================================================================
-- 2. app.vendor_capacity_blackouts.
-- ===========================================================================

create table app.vendor_capacity_blackouts (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  offer_id uuid not null references app.vendor_capacity_offers (id),
  window_start timestamptz not null,
  window_end timestamptz not null,
  reason text not null,
  record_version integer not null default 1,
  created_by text,
  created_at timestamptz not null default now(),
  constraint vendor_capacity_blackouts_window_check check (window_end > window_start),
  constraint vendor_capacity_blackouts_reason_check check (length(trim(reason)) > 0)
);

comment on table app.vendor_capacity_blackouts is 'PRC-262: a window within which a published offer accepts no new reservations. Does not retroactively cancel existing reservations (design note 6).';
create index vendor_capacity_blackouts_offer_idx on app.vendor_capacity_blackouts (offer_id);

-- ===========================================================================
-- 3. app.vendor_capacity_reservations.
-- ===========================================================================

create table app.vendor_capacity_reservations (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  offer_id uuid not null references app.vendor_capacity_offers (id),
  requested_quantity numeric(14, 3) not null,
  window_start timestamptz not null,
  window_end timestamptz not null,
  status text not null default 'held',
  source_reference_type text,
  source_reference_id uuid,
  decline_reason text,
  released_reason text,
  idempotency_key text,
  record_version integer not null default 1,
  created_by text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint vendor_capacity_reservations_quantity_check check (requested_quantity > 0),
  constraint vendor_capacity_reservations_window_check check (window_end > window_start),
  constraint vendor_capacity_reservations_status_check check (status in ('held', 'accepted', 'declined', 'consumed', 'released')),
  constraint vendor_capacity_reservations_source_type_check check (source_reference_type is null or source_reference_type in ('sourcing_request', 'assignment', 'manual')),
  constraint vendor_capacity_reservations_decline_reason_check check (status <> 'declined' or (decline_reason is not null and length(trim(decline_reason)) > 0)),
  constraint vendor_capacity_reservations_released_reason_check check (status <> 'released' or (released_reason is not null and length(trim(released_reason)) > 0))
);

comment on table app.vendor_capacity_reservations is
  'PRC-262: one row per commitment held against an offer''s own declared quantity. "active" (still consuming capacity) = status in (held, accepted, consumed); declined/released free the capacity back. requested_quantity is always in the parent offer''s own uom (design note 3).';
create index vendor_capacity_reservations_offer_status_idx on app.vendor_capacity_reservations (offer_id, status);
create index vendor_capacity_reservations_tenant_source_idx on app.vendor_capacity_reservations (tenant_id, source_reference_type, source_reference_id);
-- Scoped to (offer_id, idempotency_key), NOT (tenant_id, idempotency_key) -- a
-- reservation's natural idempotency scope is its own offer (this prompt's own Tier B
-- self-check caught a real mismatch: app.reserve_vendor_capacity's lookup/race-
-- recovery queries were already offer_id-scoped, but this index was originally
-- tenant-scoped, so a key reused across two DIFFERENT offers in the same tenant would
-- have violated the index while the recovery query found no row to recover from,
-- surfacing a raw unique_violation instead of a clean idempotency_key_conflict).
create unique index vendor_capacity_reservations_idempotency_key_unique on app.vendor_capacity_reservations (offer_id, idempotency_key) where idempotency_key is not null;

create function app.touch_vendor_capacity_reservations_row()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  new.record_version := old.record_version + 1;
  return new;
end;
$$;

create trigger vendor_capacity_reservations_touch_row
  before update on app.vendor_capacity_reservations
  for each row
  execute function app.touch_vendor_capacity_reservations_row();

-- ===========================================================================
-- 4. Offer lifecycle RPCs.
-- ===========================================================================

create function app.create_vendor_capacity_offer_draft(
  p_tenant_id uuid,
  p_vendor_master_id uuid,
  p_contract_id uuid,
  p_service_type text,
  p_mode text,
  p_origin_lane text,
  p_destination_lane text,
  p_resource_type text,
  p_resource_master_id uuid,
  p_quantity numeric,
  p_uom text,
  p_window_start timestamptz,
  p_window_end timestamptz,
  p_idempotency_key text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.vendor_capacity_offers
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_existing app.vendor_capacity_offers;
  v_offer app.vendor_capacity_offers;
begin
  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'PRC', 'Create');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:Create (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if p_quantity is null or p_quantity <= 0 then
    raise exception 'invalid_quantity: quantity must be positive' using errcode = 'check_violation';
  end if;
  if p_window_end is null or p_window_start is null or p_window_end <= p_window_start then
    raise exception 'invalid_window: window_end must be after window_start' using errcode = 'check_violation';
  end if;

  if p_idempotency_key is not null then
    select * into v_existing from app.vendor_capacity_offers where tenant_id = p_tenant_id and idempotency_key = p_idempotency_key;
    if found then
      if v_existing.vendor_master_id is distinct from p_vendor_master_id or v_existing.service_type <> p_service_type or v_existing.quantity <> p_quantity or v_existing.window_start <> p_window_start then
        raise exception 'idempotency_key_conflict: idempotency key % was already used for a different vendor capacity offer', p_idempotency_key
          using errcode = 'unique_violation';
      end if;
      return v_existing;
    end if;
  end if;

  begin
    insert into app.vendor_capacity_offers (
      tenant_id, vendor_master_id, contract_id, service_type, mode, origin_lane, destination_lane,
      resource_type, resource_master_id, quantity, uom, window_start, window_end, idempotency_key, created_by
    )
    values (
      p_tenant_id, p_vendor_master_id, p_contract_id, p_service_type, p_mode, p_origin_lane, p_destination_lane,
      coalesce(p_resource_type, 'general'), p_resource_master_id, p_quantity, p_uom, p_window_start, p_window_end, p_idempotency_key, p_actor_label
    )
    returning * into v_offer;
  exception
    when unique_violation then
      select * into v_existing from app.vendor_capacity_offers where tenant_id = p_tenant_id and idempotency_key = p_idempotency_key;
      if not found then
        raise;
      end if;
      if v_existing.vendor_master_id is distinct from p_vendor_master_id or v_existing.service_type <> p_service_type or v_existing.quantity <> p_quantity or v_existing.window_start <> p_window_start then
        raise exception 'idempotency_key_conflict: idempotency key % was already used for a different vendor capacity offer', p_idempotency_key
          using errcode = 'unique_violation';
      end if;
      return v_existing;
  end;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'create_vendor_capacity_offer_draft',
    'app.vendor_capacity_offers', v_offer.id, 'success', null, null, jsonb_build_object('service_type', v_offer.service_type, 'quantity', v_offer.quantity)
  );

  return v_offer;
end;
$$;

create function app.update_vendor_capacity_offer_draft(
  p_offer_id uuid,
  p_expected_version integer,
  p_contract_id uuid,
  p_mode text,
  p_origin_lane text,
  p_destination_lane text,
  p_resource_master_id uuid,
  p_quantity numeric,
  p_uom text,
  p_window_start timestamptz,
  p_window_end timestamptz,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.vendor_capacity_offers
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_offer app.vendor_capacity_offers;
begin
  select * into v_offer from app.vendor_capacity_offers where id = p_offer_id;
  if not found then
    raise exception 'vendor_capacity_offer_not_found: %', p_offer_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_offer.tenant_id, 'PRC', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_offer.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_offer.record_version <> p_expected_version then
    raise exception 'stale_version: vendor capacity offer % expected version % but found %', p_offer_id, p_expected_version, v_offer.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_offer.status <> 'draft' then
    raise exception 'invalid_transition: vendor capacity offer % is % and cannot be edited', p_offer_id, v_offer.status
      using errcode = 'check_violation';
  end if;
  if p_quantity is null or p_quantity <= 0 then
    raise exception 'invalid_quantity: quantity must be positive' using errcode = 'check_violation';
  end if;
  if p_window_end is null or p_window_start is null or p_window_end <= p_window_start then
    raise exception 'invalid_window: window_end must be after window_start' using errcode = 'check_violation';
  end if;

  -- contract_id/mode/origin_lane/destination_lane/resource_master_id are truly
  -- optional -- preserve-by-null (coalesce). quantity/uom/window are always-required
  -- direct assignment (PRC-261's own Tier B lesson: never conflate the two shapes).
  update app.vendor_capacity_offers
  set contract_id = coalesce(p_contract_id, contract_id),
      mode = coalesce(p_mode, mode),
      origin_lane = coalesce(p_origin_lane, origin_lane),
      destination_lane = coalesce(p_destination_lane, destination_lane),
      resource_master_id = coalesce(p_resource_master_id, resource_master_id),
      quantity = p_quantity,
      uom = p_uom,
      window_start = p_window_start,
      window_end = p_window_end
  where id = p_offer_id and record_version = p_expected_version
  returning * into v_offer;
  if not found then
    raise exception 'stale_version: vendor capacity offer % target row was concurrently modified (expected version %)', p_offer_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_offer.tenant_id, p_actor_auth_user_id, p_actor_label, 'update_vendor_capacity_offer_draft',
    'app.vendor_capacity_offers', v_offer.id, 'success', null, null, '{}'::jsonb
  );

  return v_offer;
end;
$$;

create function app.publish_vendor_capacity_offer(
  p_offer_id uuid,
  p_expected_version integer,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.vendor_capacity_offers
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_offer app.vendor_capacity_offers;
begin
  select * into v_offer from app.vendor_capacity_offers where id = p_offer_id;
  if not found then
    raise exception 'vendor_capacity_offer_not_found: %', p_offer_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_offer.tenant_id, 'PRC', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_offer.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_offer.record_version <> p_expected_version then
    raise exception 'stale_version: vendor capacity offer % expected version % but found %', p_offer_id, p_expected_version, v_offer.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_offer.status <> 'draft' then
    raise exception 'invalid_transition: vendor capacity offer % is % and cannot be published', p_offer_id, v_offer.status
      using errcode = 'check_violation';
  end if;

  update app.vendor_capacity_offers set status = 'published' where id = p_offer_id and record_version = p_expected_version returning * into v_offer;
  if not found then
    raise exception 'stale_version: vendor capacity offer % target row was concurrently modified (expected version %)', p_offer_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_offer.tenant_id, p_actor_auth_user_id, p_actor_label, 'publish_vendor_capacity_offer',
    'app.vendor_capacity_offers', v_offer.id, 'success', null, null, '{}'::jsonb
  );

  return v_offer;
end;
$$;

create function app.archive_vendor_capacity_offer(
  p_offer_id uuid,
  p_expected_version integer,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.vendor_capacity_offers
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_offer app.vendor_capacity_offers;
  v_active_count integer;
begin
  select * into v_offer from app.vendor_capacity_offers where id = p_offer_id for update;
  if not found then
    raise exception 'vendor_capacity_offer_not_found: %', p_offer_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_offer.tenant_id, 'PRC', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_offer.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_offer.record_version <> p_expected_version then
    raise exception 'stale_version: vendor capacity offer % expected version % but found %', p_offer_id, p_expected_version, v_offer.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_offer.status not in ('draft', 'published') then
    raise exception 'invalid_transition: vendor capacity offer % is % and cannot be archived', p_offer_id, v_offer.status
      using errcode = 'check_violation';
  end if;

  select count(*) into v_active_count from app.vendor_capacity_reservations where offer_id = p_offer_id and status in ('held', 'accepted');
  if v_active_count > 0 then
    raise exception 'active_reservations_exist: vendor capacity offer % has % active reservation(s) -- decline or release them first', p_offer_id, v_active_count
      using errcode = 'check_violation';
  end if;

  update app.vendor_capacity_offers set status = 'archived' where id = p_offer_id and record_version = p_expected_version returning * into v_offer;
  if not found then
    raise exception 'stale_version: vendor capacity offer % target row was concurrently modified (expected version %)', p_offer_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_offer.tenant_id, p_actor_auth_user_id, p_actor_label, 'archive_vendor_capacity_offer',
    'app.vendor_capacity_offers', v_offer.id, 'success', null, null, '{}'::jsonb
  );

  return v_offer;
end;
$$;

-- ===========================================================================
-- 5. Blackout RPCs.
-- ===========================================================================

create function app.add_vendor_capacity_blackout(
  p_offer_id uuid,
  p_window_start timestamptz,
  p_window_end timestamptz,
  p_reason text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.vendor_capacity_blackouts
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_offer app.vendor_capacity_offers;
  v_blackout app.vendor_capacity_blackouts;
begin
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'reason_required: a non-empty reason is required to add a blackout' using errcode = 'check_violation';
  end if;
  if p_window_end is null or p_window_start is null or p_window_end <= p_window_start then
    raise exception 'invalid_window: window_end must be after window_start' using errcode = 'check_violation';
  end if;

  select * into v_offer from app.vendor_capacity_offers where id = p_offer_id for update;
  if not found then
    raise exception 'vendor_capacity_offer_not_found: %', p_offer_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_offer.tenant_id, 'PRC', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_offer.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  insert into app.vendor_capacity_blackouts (tenant_id, offer_id, window_start, window_end, reason, created_by)
  values (v_offer.tenant_id, p_offer_id, p_window_start, p_window_end, p_reason, p_actor_label)
  returning * into v_blackout;

  perform app.capture_audit_event(
    v_offer.tenant_id, p_actor_auth_user_id, p_actor_label, 'add_vendor_capacity_blackout',
    'app.vendor_capacity_blackouts', v_blackout.id, 'success', p_reason, null, '{}'::jsonb
  );

  return v_blackout;
end;
$$;

create function app.remove_vendor_capacity_blackout(
  p_blackout_id uuid,
  p_expected_version integer,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns void
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_blackout app.vendor_capacity_blackouts;
begin
  select * into v_blackout from app.vendor_capacity_blackouts where id = p_blackout_id;
  if not found then
    raise exception 'vendor_capacity_blackout_not_found: %', p_blackout_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_blackout.tenant_id, 'PRC', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_blackout.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if v_blackout.record_version <> p_expected_version then
    raise exception 'stale_version: vendor capacity blackout % expected version % but found %', p_blackout_id, p_expected_version, v_blackout.record_version
      using errcode = 'serialization_failure';
  end if;

  delete from app.vendor_capacity_blackouts where id = p_blackout_id and record_version = p_expected_version;
  if not found then
    raise exception 'stale_version: vendor capacity blackout % target row was concurrently modified (expected version %)', p_blackout_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_blackout.tenant_id, p_actor_auth_user_id, p_actor_label, 'remove_vendor_capacity_blackout',
    'app.vendor_capacity_blackouts', p_blackout_id, 'success', null, null, '{}'::jsonb
  );
end;
$$;

-- ===========================================================================
-- 6. Reservation RPCs -- the concurrency-critical core (design note 2).
-- ===========================================================================

create function app.reserve_vendor_capacity(
  p_offer_id uuid,
  p_requested_quantity numeric,
  p_window_start timestamptz,
  p_window_end timestamptz,
  p_source_reference_type text,
  p_source_reference_id uuid,
  p_idempotency_key text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.vendor_capacity_reservations
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_offer app.vendor_capacity_offers;
  v_existing app.vendor_capacity_reservations;
  v_committed numeric;
  v_blackout_count integer;
  v_reservation app.vendor_capacity_reservations;
begin
  if p_requested_quantity is null or p_requested_quantity <= 0 then
    raise exception 'invalid_quantity: requested_quantity must be positive' using errcode = 'check_violation';
  end if;
  if p_window_end is null or p_window_start is null or p_window_end <= p_window_start then
    raise exception 'invalid_window: window_end must be after window_start' using errcode = 'check_violation';
  end if;

  if p_idempotency_key is not null then
    select * into v_existing from app.vendor_capacity_reservations where offer_id = p_offer_id and idempotency_key = p_idempotency_key;
    if found then
      if v_existing.requested_quantity <> p_requested_quantity or v_existing.window_start <> p_window_start or v_existing.window_end <> p_window_end then
        raise exception 'idempotency_key_conflict: idempotency key % was already used for a different reservation on this offer', p_idempotency_key
          using errcode = 'unique_violation';
      end if;
      return v_existing;
    end if;
  end if;

  -- Design note 2: locking the OFFER row serializes every concurrent reservation
  -- attempt against it -- the "available" computation and the INSERT below happen
  -- inside the SAME lock, so no two concurrent callers can both observe capacity that
  -- only one of them can actually have.
  select * into v_offer from app.vendor_capacity_offers where id = p_offer_id for update;
  if not found then
    raise exception 'vendor_capacity_offer_not_found: %', p_offer_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_offer.tenant_id, 'PRC', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_offer.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_offer.status <> 'published' then
    raise exception 'invalid_transition: vendor capacity offer % is % -- only a published offer may be reserved against', p_offer_id, v_offer.status
      using errcode = 'check_violation';
  end if;
  if p_window_start < v_offer.window_start or p_window_end > v_offer.window_end then
    raise exception 'reservation_outside_offer_window: requested window is not within offer %''s own declared window', p_offer_id
      using errcode = 'check_violation';
  end if;

  select count(*) into v_blackout_count
  from app.vendor_capacity_blackouts b
  where b.offer_id = p_offer_id and b.window_start < p_window_end and b.window_end > p_window_start;
  if v_blackout_count > 0 then
    raise exception 'reservation_in_blackout: requested window overlaps a declared blackout on offer %', p_offer_id
      using errcode = 'check_violation';
  end if;

  select coalesce(sum(r.requested_quantity), 0) into v_committed
  from app.vendor_capacity_reservations r
  where r.offer_id = p_offer_id
    and r.status in ('held', 'accepted', 'consumed')
    and r.window_start < p_window_end and r.window_end > p_window_start;

  if v_committed + p_requested_quantity > v_offer.quantity then
    raise exception 'over_reservation: requesting % of % but only % of % remains uncommitted for this window on offer %', p_requested_quantity, v_offer.uom, v_offer.quantity - v_committed, v_offer.uom, p_offer_id
      using errcode = 'check_violation';
  end if;

  begin
    insert into app.vendor_capacity_reservations (
      tenant_id, offer_id, requested_quantity, window_start, window_end, source_reference_type, source_reference_id, idempotency_key, created_by
    )
    values (
      v_offer.tenant_id, p_offer_id, p_requested_quantity, p_window_start, p_window_end, p_source_reference_type, p_source_reference_id, p_idempotency_key, p_actor_label
    )
    returning * into v_reservation;
  exception
    when unique_violation then
      select * into v_existing from app.vendor_capacity_reservations where offer_id = p_offer_id and idempotency_key = p_idempotency_key;
      if not found then
        raise;
      end if;
      if v_existing.requested_quantity <> p_requested_quantity or v_existing.window_start <> p_window_start or v_existing.window_end <> p_window_end then
        raise exception 'idempotency_key_conflict: idempotency key % was already used for a different reservation on this offer', p_idempotency_key
          using errcode = 'unique_violation';
      end if;
      return v_existing;
  end;

  perform app.capture_audit_event(
    v_offer.tenant_id, p_actor_auth_user_id, p_actor_label, 'reserve_vendor_capacity',
    'app.vendor_capacity_reservations', v_reservation.id, 'success', null, null, jsonb_build_object('requested_quantity', p_requested_quantity)
  );

  return v_reservation;
end;
$$;

comment on function app.reserve_vendor_capacity is 'PRC-262: the one concurrency-critical write in this capability -- locks the parent offer row before computing available-vs-committed over the requested window and inserting (design note 2). status=held.';

create function app.accept_vendor_capacity_reservation(
  p_reservation_id uuid,
  p_expected_version integer,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.vendor_capacity_reservations
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_reservation app.vendor_capacity_reservations;
begin
  select * into v_reservation from app.vendor_capacity_reservations where id = p_reservation_id;
  if not found then
    raise exception 'vendor_capacity_reservation_not_found: %', p_reservation_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_reservation.tenant_id, 'PRC', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_reservation.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_reservation.record_version <> p_expected_version then
    raise exception 'stale_version: vendor capacity reservation % expected version % but found %', p_reservation_id, p_expected_version, v_reservation.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_reservation.status <> 'held' then
    raise exception 'invalid_transition: vendor capacity reservation % is % and cannot be accepted', p_reservation_id, v_reservation.status
      using errcode = 'check_violation';
  end if;

  update app.vendor_capacity_reservations set status = 'accepted' where id = p_reservation_id and record_version = p_expected_version returning * into v_reservation;
  if not found then
    raise exception 'stale_version: vendor capacity reservation % target row was concurrently modified (expected version %)', p_reservation_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_reservation.tenant_id, p_actor_auth_user_id, p_actor_label, 'accept_vendor_capacity_reservation',
    'app.vendor_capacity_reservations', v_reservation.id, 'success', null, null, '{}'::jsonb
  );

  return v_reservation;
end;
$$;

create function app.decline_vendor_capacity_reservation(
  p_reservation_id uuid,
  p_expected_version integer,
  p_reason text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.vendor_capacity_reservations
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_reservation app.vendor_capacity_reservations;
begin
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'reason_required: a non-empty reason is required to decline a reservation' using errcode = 'check_violation';
  end if;

  select * into v_reservation from app.vendor_capacity_reservations where id = p_reservation_id;
  if not found then
    raise exception 'vendor_capacity_reservation_not_found: %', p_reservation_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_reservation.tenant_id, 'PRC', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_reservation.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_reservation.record_version <> p_expected_version then
    raise exception 'stale_version: vendor capacity reservation % expected version % but found %', p_reservation_id, p_expected_version, v_reservation.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_reservation.status <> 'held' then
    raise exception 'invalid_transition: vendor capacity reservation % is % and cannot be declined', p_reservation_id, v_reservation.status
      using errcode = 'check_violation';
  end if;

  update app.vendor_capacity_reservations set status = 'declined', decline_reason = p_reason where id = p_reservation_id and record_version = p_expected_version returning * into v_reservation;
  if not found then
    raise exception 'stale_version: vendor capacity reservation % target row was concurrently modified (expected version %)', p_reservation_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_reservation.tenant_id, p_actor_auth_user_id, p_actor_label, 'decline_vendor_capacity_reservation',
    'app.vendor_capacity_reservations', v_reservation.id, 'success', p_reason, null, '{}'::jsonb
  );

  return v_reservation;
end;
$$;

create function app.release_vendor_capacity_reservation(
  p_reservation_id uuid,
  p_expected_version integer,
  p_reason text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.vendor_capacity_reservations
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_reservation app.vendor_capacity_reservations;
begin
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'reason_required: a non-empty reason is required to release a reservation' using errcode = 'check_violation';
  end if;

  select * into v_reservation from app.vendor_capacity_reservations where id = p_reservation_id;
  if not found then
    raise exception 'vendor_capacity_reservation_not_found: %', p_reservation_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_reservation.tenant_id, 'PRC', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_reservation.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_reservation.record_version <> p_expected_version then
    raise exception 'stale_version: vendor capacity reservation % expected version % but found %', p_reservation_id, p_expected_version, v_reservation.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_reservation.status <> 'accepted' then
    raise exception 'invalid_transition: vendor capacity reservation % is % and cannot be released', p_reservation_id, v_reservation.status
      using errcode = 'check_violation';
  end if;

  update app.vendor_capacity_reservations set status = 'released', released_reason = p_reason where id = p_reservation_id and record_version = p_expected_version returning * into v_reservation;
  if not found then
    raise exception 'stale_version: vendor capacity reservation % target row was concurrently modified (expected version %)', p_reservation_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_reservation.tenant_id, p_actor_auth_user_id, p_actor_label, 'release_vendor_capacity_reservation',
    'app.vendor_capacity_reservations', v_reservation.id, 'success', p_reason, null, '{}'::jsonb
  );

  return v_reservation;
end;
$$;

create function app.consume_vendor_capacity_reservation(
  p_reservation_id uuid,
  p_expected_version integer,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.vendor_capacity_reservations
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_reservation app.vendor_capacity_reservations;
begin
  select * into v_reservation from app.vendor_capacity_reservations where id = p_reservation_id;
  if not found then
    raise exception 'vendor_capacity_reservation_not_found: %', p_reservation_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_reservation.tenant_id, 'PRC', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_reservation.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_reservation.record_version <> p_expected_version then
    raise exception 'stale_version: vendor capacity reservation % expected version % but found %', p_reservation_id, p_expected_version, v_reservation.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_reservation.status <> 'accepted' then
    raise exception 'invalid_transition: vendor capacity reservation % is % and cannot be consumed', p_reservation_id, v_reservation.status
      using errcode = 'check_violation';
  end if;

  update app.vendor_capacity_reservations set status = 'consumed' where id = p_reservation_id and record_version = p_expected_version returning * into v_reservation;
  if not found then
    raise exception 'stale_version: vendor capacity reservation % target row was concurrently modified (expected version %)', p_reservation_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_reservation.tenant_id, p_actor_auth_user_id, p_actor_label, 'consume_vendor_capacity_reservation',
    'app.vendor_capacity_reservations', v_reservation.id, 'success', null, null, '{}'::jsonb
  );

  return v_reservation;
end;
$$;

comment on function app.consume_vendor_capacity_reservation is 'PRC-262: accepted -> consumed, marking fulfillment. Called directly by PRC-263 (Vendor Assignment, next in this same batch) once a real assignment consumes the held commitment -- also callable standalone (PRC:Edit) for manual reconciliation.';

-- ===========================================================================
-- 7. Reads (PRC:View). No cost masking in this capability (design note 7).
-- ===========================================================================

create function app.get_vendor_capacity_offer(p_offer_id uuid, p_actor_auth_user_id uuid)
returns app.vendor_capacity_offers
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_tenant_id uuid;
  v_offer app.vendor_capacity_offers;
begin
  select tenant_id into v_tenant_id from app.vendor_capacity_offers where id = p_offer_id;
  if v_tenant_id is null or not app.has_active_tenant_membership(v_tenant_id, p_actor_auth_user_id) then
    raise exception 'vendor_capacity_offer_not_found: %', p_offer_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_tenant_id, 'PRC', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_offer from app.vendor_capacity_offers where id = p_offer_id;
  return v_offer;
end;
$$;

create function app.list_vendor_capacity_offers(
  p_tenant_id uuid,
  p_vendor_master_id uuid,
  p_status text,
  p_service_type text,
  p_actor_auth_user_id uuid,
  p_limit integer default 25
)
returns setof app.vendor_capacity_offers
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
begin
  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'PRC', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  return query
  select * from app.vendor_capacity_offers
  where tenant_id = p_tenant_id
    and (p_vendor_master_id is null or vendor_master_id = p_vendor_master_id)
    and (p_status is null or status = p_status)
    and (p_service_type is null or service_type = p_service_type)
  order by created_at desc
  limit least(coalesce(p_limit, 25), 100);
end;
$$;

create function app.list_vendor_capacity_blackouts(p_offer_id uuid, p_actor_auth_user_id uuid)
returns setof app.vendor_capacity_blackouts
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_tenant_id uuid;
begin
  select tenant_id into v_tenant_id from app.vendor_capacity_offers where id = p_offer_id;
  if v_tenant_id is null or not app.has_active_tenant_membership(v_tenant_id, p_actor_auth_user_id) then
    raise exception 'vendor_capacity_offer_not_found: %', p_offer_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_tenant_id, 'PRC', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  return query select * from app.vendor_capacity_blackouts where offer_id = p_offer_id order by window_start;
end;
$$;

create function app.list_vendor_capacity_reservations(p_offer_id uuid, p_status text, p_actor_auth_user_id uuid)
returns setof app.vendor_capacity_reservations
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_tenant_id uuid;
begin
  select tenant_id into v_tenant_id from app.vendor_capacity_offers where id = p_offer_id;
  if v_tenant_id is null or not app.has_active_tenant_membership(v_tenant_id, p_actor_auth_user_id) then
    raise exception 'vendor_capacity_offer_not_found: %', p_offer_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_tenant_id, 'PRC', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  return query select * from app.vendor_capacity_reservations where offer_id = p_offer_id and (p_status is null or status = p_status) order by created_at desc;
end;
$$;

create function app.get_vendor_capacity_reservation(p_reservation_id uuid, p_actor_auth_user_id uuid)
returns app.vendor_capacity_reservations
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_tenant_id uuid;
  v_reservation app.vendor_capacity_reservations;
begin
  select tenant_id into v_tenant_id from app.vendor_capacity_reservations where id = p_reservation_id;
  if v_tenant_id is null or not app.has_active_tenant_membership(v_tenant_id, p_actor_auth_user_id) then
    raise exception 'vendor_capacity_reservation_not_found: %', p_reservation_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_tenant_id, 'PRC', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_reservation from app.vendor_capacity_reservations where id = p_reservation_id;
  return v_reservation;
end;
$$;

create function app.compute_vendor_capacity_available(
  p_offer_id uuid,
  p_window_start timestamptz,
  p_window_end timestamptz,
  p_actor_auth_user_id uuid
)
returns numeric
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_offer app.vendor_capacity_offers;
  v_committed numeric;
begin
  select * into v_offer from app.vendor_capacity_offers where id = p_offer_id;
  if v_offer.id is null or not app.has_active_tenant_membership(v_offer.tenant_id, p_actor_auth_user_id) then
    raise exception 'vendor_capacity_offer_not_found: %', p_offer_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_offer.tenant_id, 'PRC', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_offer.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  select coalesce(sum(r.requested_quantity), 0) into v_committed
  from app.vendor_capacity_reservations r
  where r.offer_id = p_offer_id
    and r.status in ('held', 'accepted', 'consumed')
    and r.window_start < p_window_end and r.window_end > p_window_start;

  return v_offer.quantity - v_committed;
end;
$$;

comment on function app.compute_vendor_capacity_available is 'PRC-262: advisory-only preview (no lock) -- the real, race-safe enforcement is app.reserve_vendor_capacity''s own locked computation (design note 2). A UI caller uses this to show "would this fit" before submitting a reservation attempt.';

-- ===========================================================================
-- 8. RLS -- default-deny form (pattern (3)), mirroring app.vendor_contracts exactly.
-- ===========================================================================

alter table app.vendor_capacity_offers enable row level security;
alter table app.vendor_capacity_blackouts enable row level security;
alter table app.vendor_capacity_reservations enable row level security;

create policy vendor_capacity_offers_select_scoped on app.vendor_capacity_offers
  for select to authenticated
  using ((app.has_active_tenant_membership(tenant_id) and not app.actor_holds_customer_user_layer(tenant_id)) or app.is_supreme_admin());

create policy vendor_capacity_blackouts_select_scoped on app.vendor_capacity_blackouts
  for select to authenticated
  using ((app.has_active_tenant_membership(tenant_id) and not app.actor_holds_customer_user_layer(tenant_id)) or app.is_supreme_admin());

create policy vendor_capacity_reservations_select_scoped on app.vendor_capacity_reservations
  for select to authenticated
  using ((app.has_active_tenant_membership(tenant_id) and not app.actor_holds_customer_user_layer(tenant_id)) or app.is_supreme_admin());

-- ===========================================================================
-- 9. Grants.
-- ===========================================================================

revoke execute on all functions in schema app from public;

grant select on app.vendor_capacity_offers to authenticated, service_role;
grant insert, update on app.vendor_capacity_offers to service_role;
grant select on app.vendor_capacity_blackouts to authenticated, service_role;
grant insert, delete on app.vendor_capacity_blackouts to service_role;
grant select on app.vendor_capacity_reservations to authenticated, service_role;
grant insert, update on app.vendor_capacity_reservations to service_role;

grant execute on function app.create_vendor_capacity_offer_draft(uuid, uuid, uuid, text, text, text, text, text, uuid, numeric, text, timestamptz, timestamptz, text, uuid, text) to authenticated, service_role;
grant execute on function app.update_vendor_capacity_offer_draft(uuid, integer, uuid, text, text, text, uuid, numeric, text, timestamptz, timestamptz, uuid, text) to authenticated, service_role;
grant execute on function app.publish_vendor_capacity_offer(uuid, integer, uuid, text) to authenticated, service_role;
grant execute on function app.archive_vendor_capacity_offer(uuid, integer, uuid, text) to authenticated, service_role;

grant execute on function app.add_vendor_capacity_blackout(uuid, timestamptz, timestamptz, text, uuid, text) to authenticated, service_role;
grant execute on function app.remove_vendor_capacity_blackout(uuid, integer, uuid, text) to authenticated, service_role;

grant execute on function app.reserve_vendor_capacity(uuid, numeric, timestamptz, timestamptz, text, uuid, text, uuid, text) to authenticated, service_role;
grant execute on function app.accept_vendor_capacity_reservation(uuid, integer, uuid, text) to authenticated, service_role;
grant execute on function app.decline_vendor_capacity_reservation(uuid, integer, text, uuid, text) to authenticated, service_role;
grant execute on function app.release_vendor_capacity_reservation(uuid, integer, text, uuid, text) to authenticated, service_role;
grant execute on function app.consume_vendor_capacity_reservation(uuid, integer, uuid, text) to authenticated, service_role;

grant execute on function app.get_vendor_capacity_offer(uuid, uuid) to authenticated, service_role;
grant execute on function app.list_vendor_capacity_offers(uuid, uuid, text, text, uuid, integer) to authenticated, service_role;
grant execute on function app.list_vendor_capacity_blackouts(uuid, uuid) to authenticated, service_role;
grant execute on function app.list_vendor_capacity_reservations(uuid, text, uuid) to authenticated, service_role;
grant execute on function app.get_vendor_capacity_reservation(uuid, uuid) to authenticated, service_role;
grant execute on function app.compute_vendor_capacity_available(uuid, timestamptz, timestamptz, uuid) to authenticated, service_role;
