-- ISS-2026-060 closure: additive zone/distance pricing dimension for the vendor rate
-- engine (PRC-255, app.vendor_rate_versions / app.vendor_rate_tiers,
-- supabase/migrations/20260730620000_extend_commercial_vendor_rate_for_procurement.sql).
-- 255_VENDOR_RATE_PRICELIST_PROMPT.md (lines 60, 76, 100) and ADR-0015 both name
-- zone/distance as required rate-tiering dimensions never implemented -- confirmed
-- absent by grep against every migration prior to this one.
--
-- Live-drift check performed before writing this file (per this checkpoint's own
-- mandate): app.create_rate_version/app.approve_rate_version were read live via
-- pg_get_functiondef, not from the applied migration file text. Both have drifted
-- since 20260730620000 -- a PRC-259 governance-approval routing block
-- (governance_approval_status/governance_approval_request_id, a call to
-- app._request_procurement_entity_approval, and a gate on that status inside
-- app.approve_rate_version) was added later and is not present in the migration
-- file's own text. This migration's own widened app.approve_rate_version body below
-- reproduces the CURRENT LIVE body verbatim, plus exactly one new statement (design
-- note 4).
--
-- Design decisions, disclosed rather than left implicit:
--
-- 1. No compatible "zone" concept exists to reuse. app.warehouse_zones (ATW-229,
--    20260730140000_create_advanced_tms_warehouse_zone.sql) is a warehouse-INTERNAL
--    physical storage-zone concept (racking/dock/staging areas, scoped to one
--    app.warehouses row via warehouse_id) -- structurally unrelated to an
--    origin/destination pricing zone and not a compatible parallel concept.
--    grep-confirmed (rate_zone|pricing_zone|shipping_zone|distance_bracket|
--    zone_pair|origin_zone|destination_zone) returns zero matches anywhere in
--    supabase/migrations/ prior to this file. A new, minimal, free-text zone_code
--    dimension is introduced here, scoped only to this rate engine, per the task's
--    own "a simpler zone-code dimension" option.
-- 2. A wholly NEW, additive child table, app.vendor_rate_zone_distance_tiers,
--    PARALLEL to (never touching) app.vendor_rate_tiers. The existing weight/volume
--    tier-matching path -- app._compute_vendor_rate_amount, app.calculate_vendor_rate,
--    app.select_vendor_rate, app.search_vendor_rates -- is NOT MODIFIED AT ALL by
--    this migration: not its signature, not its body, not one byte. A rate version
--    with zero rows in the new table is completely unaffected by anything in this
--    file except a single read-only `exists()` check inside the one new entry point
--    below. This is the "zero behavior change for tenants who don't configure the
--    new dimension" guarantee, achieved by construction (the old code path is
--    untouched), not by careful parallel maintenance of two implementations.
-- 3. app.calculate_vendor_rate_zoned (new, public, PRC:View cost-gated -- the exact
--    same authority app.calculate_vendor_rate itself requires) is the new lookup
--    entry point. It COMPOSES WITH, never replaces, the existing engine: when a
--    rate version has no zone/distance tiers configured, it delegates straight to
--    app._compute_vendor_rate_amount -- the SAME private helper app.calculate_
--    vendor_rate itself calls -- and returns a result computed by the identical,
--    unmodified code path (zone_distance_priced=false in the return row marks
--    which branch ran, so a caller never has to guess). Only when zone/distance
--    tiers ARE configured does it use the new matching logic
--    (app._compute_vendor_rate_zone_distance_amount).
-- 4. Ambiguous/no-match handling (documented, never silently wrong): when a rate
--    version has at least one zone/distance tier configured but the supplied
--    (p_zone_code, p_distance) does not match any of them, app.calculate_vendor_
--    rate_zoned RAISES a clear, named zone_distance_tier_not_matched error -- it
--    never silently falls back to base_amount or to an arbitrary tier. When more
--    than one tier COULD match (the deliberately bounded case: two tiers whose
--    zone/distance ranges are not actually disjoint), resolution is deterministic
--    -- lowest tier_order wins -- mirroring app._compute_vendor_rate_amount's own
--    established weight/volume tie-break exactly. To keep that case rare rather
--    than the normal path, app.approve_rate_version is widened (unchanged 4-arg
--    signature, so `create or replace`, not DROP+CREATE) to reject a genuinely
--    overlapping zone/distance tier set at publish time -- the same "validate once,
--    at publish, never on every add" discipline PRC-255 already established for
--    weight/volume tiers (app._validate_vendor_rate_tiers_contiguous), applied here
--    a second time via a new, parallel validator,
--    app._validate_vendor_rate_zone_distance_tiers_contiguous, partitioned by
--    zone_code (null-safe grouping via IS NOT DISTINCT FROM) so tiers that vary by
--    distance only within one zone are validated independently of every other
--    zone's own distance ladder.
-- 5. Zone/distance tiers reuse the SAME PRC:Edit-gated, "only while pending_approval"
--    child-CRUD precondition as weight/volume tiers --
--    app.assert_vendor_rate_version_tier_editable is called UNCHANGED, never
--    duplicated -- and the SAME PRC:View cost cost-masking gate
--    (app.has_prc_view_cost, PRC-255's own ADR-0020-directed reuse for its new
--    sensitive-field classes) via a masked directory view mirroring
--    app.vendor_rate_tiers_directory's own hardened pattern-5 row predicate
--    byte-for-byte. No new permission or masking mechanism is invented.
-- 6. Idempotency-key replay compares the full target tuple, mirroring
--    app._insert_vendor_rate_tier exactly (the same private-helper convention --
--    no grant to authenticated/service_role, callable only from within another
--    function owned by the same role).
-- 7. Per ERR-2026-004: explicit `revoke execute on all functions in schema app from
--    public` before final grants, the standing per-migration convention.

-- ===========================================================================
-- 1. app.vendor_rate_zone_distance_tiers.
-- ===========================================================================

create table app.vendor_rate_zone_distance_tiers (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  rate_version_id uuid not null references app.vendor_rate_versions (id),
  tier_order integer not null,
  zone_code text,
  distance_min numeric(10, 2),
  distance_max numeric(10, 2),
  amount numeric(14, 2) not null,
  minimum_charge numeric(14, 2),
  idempotency_key text,
  record_version integer not null default 1,
  created_by text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint vendor_rate_zone_distance_tiers_tier_order_check check (tier_order > 0),
  constraint vendor_rate_zone_distance_tiers_zone_code_check check (zone_code is null or length(trim(zone_code)) > 0),
  constraint vendor_rate_zone_distance_tiers_distance_min_check check (distance_min is null or distance_min >= 0),
  constraint vendor_rate_zone_distance_tiers_distance_range_check check (distance_max is null or distance_max > coalesce(distance_min, 0)),
  constraint vendor_rate_zone_distance_tiers_amount_check check (amount >= 0),
  constraint vendor_rate_zone_distance_tiers_minimum_charge_check check (minimum_charge is null or minimum_charge >= 0),
  -- A row must configure at least one real dimension -- guards against a no-op
  -- wildcard-everything row ever entering this table, which would make "zero rows
  -- in this table = old behavior" an unreliable test (design note 2).
  constraint vendor_rate_zone_distance_tiers_dimension_check check (zone_code is not null or distance_min is not null or distance_max is not null),
  constraint vendor_rate_zone_distance_tiers_unique_order unique (rate_version_id, tier_order)
);

comment on table app.vendor_rate_zone_distance_tiers is
  'ISS-2026-060: an ordered, opt-in zone-code and/or [min,max)-half-open distance pricing tier belonging to one app.vendor_rate_versions row -- parallel to, never merged with, app.vendor_rate_tiers (weight/volume, PRC-255). zone_code null on a tier means "any zone" (a wildcard within its own distance slot); distance_min/distance_max both null means "any distance". A rate version with zero rows here never reaches this table''s own matching logic at all (app.calculate_vendor_rate_zoned delegates straight to the unmodified app._compute_vendor_rate_amount). May only be created/removed while the parent is pending_approval (app.assert_vendor_rate_version_tier_editable, reused unchanged from PRC-255). Contiguity within each zone_code partition is validated once, at app.approve_rate_version time.';

create index vendor_rate_zone_distance_tiers_rate_version_idx on app.vendor_rate_zone_distance_tiers (rate_version_id, tier_order);
create unique index vendor_rate_zone_distance_tiers_idempotency_key_unique on app.vendor_rate_zone_distance_tiers (tenant_id, idempotency_key) where idempotency_key is not null;

create view app.vendor_rate_zone_distance_tiers_directory
as
select
  t.id,
  t.tenant_id,
  t.rate_version_id,
  t.tier_order,
  t.zone_code,
  t.distance_min,
  t.distance_max,
  case when app.has_prc_view_cost(t.tenant_id) then t.amount else null end as amount,
  case when app.has_prc_view_cost(t.tenant_id) then t.minimum_charge else null end as minimum_charge,
  not app.has_prc_view_cost(t.tenant_id) as cost_masked,
  t.record_version,
  t.created_by,
  t.created_at,
  t.updated_at
from app.vendor_rate_zone_distance_tiers t
where (app.has_active_tenant_membership(t.tenant_id) and not app.actor_holds_customer_user_layer(t.tenant_id)) or app.is_supreme_admin();

comment on view app.vendor_rate_zone_distance_tiers_directory is
  'ISS-2026-060: field-masked projection of app.vendor_rate_zone_distance_tiers, mirroring app.vendor_rate_tiers_directory''s own hardened pattern-5 predicate byte-for-byte (a customer_user-layer principal gets zero rows, not merely masked ones) and the same PRC:View cost masking gate (app.has_prc_view_cost).';

-- ===========================================================================
-- 2. Private insert helper + public add/remove RPCs (design notes 5, 6). Reuses
--    app.assert_vendor_rate_version_tier_editable UNCHANGED (PRC-255) -- never
--    redefined here.
-- ===========================================================================

create function app._insert_vendor_rate_zone_distance_tier(
  p_rate app.vendor_rate_versions,
  p_tier_order integer,
  p_zone_code text,
  p_distance_min numeric,
  p_distance_max numeric,
  p_amount numeric,
  p_minimum_charge numeric,
  p_idempotency_key text,
  p_actor_label text
)
returns app.vendor_rate_zone_distance_tiers
language plpgsql
as $$
declare
  v_existing app.vendor_rate_zone_distance_tiers;
  v_tier app.vendor_rate_zone_distance_tiers;
  v_constraint_name text;
  v_zone_code text := nullif(trim(coalesce(p_zone_code, '')), '');
begin
  if p_rate.approval_status <> 'pending_approval' then
    raise exception 'vendor_rate_version_not_editable: rate version % is % -- zone/distance tiers may only be added while pending_approval', p_rate.id, p_rate.approval_status
      using errcode = 'check_violation';
  end if;
  if p_tier_order is null or p_tier_order <= 0 then
    raise exception 'invalid_tier_order: tier_order must be a positive integer' using errcode = 'check_violation';
  end if;
  if p_amount is null or p_amount < 0 then
    raise exception 'invalid_tier_amount: amount must be a non-negative value' using errcode = 'check_violation';
  end if;
  if v_zone_code is null and p_distance_min is null and p_distance_max is null then
    raise exception 'invalid_zone_distance_dimension: at least one of zone_code/distance_min/distance_max must be supplied' using errcode = 'check_violation';
  end if;
  if p_distance_min is not null and p_distance_min < 0 then
    raise exception 'invalid_tier_range: distance_min must be non-negative' using errcode = 'check_violation';
  end if;
  if p_distance_max is not null and p_distance_max <= coalesce(p_distance_min, 0) then
    raise exception 'invalid_tier_distance_range: distance_max must exceed distance_min' using errcode = 'check_violation';
  end if;
  if p_minimum_charge is not null and p_minimum_charge < 0 then
    raise exception 'invalid_tier_minimum_charge: minimum_charge must be non-negative' using errcode = 'check_violation';
  end if;

  if p_idempotency_key is not null then
    select * into v_existing from app.vendor_rate_zone_distance_tiers where tenant_id = p_rate.tenant_id and idempotency_key = p_idempotency_key;
    if found then
      if v_existing.rate_version_id is distinct from p_rate.id or v_existing.tier_order is distinct from p_tier_order
        or v_existing.zone_code is distinct from v_zone_code or v_existing.distance_min is distinct from p_distance_min or v_existing.distance_max is distinct from p_distance_max
        or v_existing.amount is distinct from p_amount or v_existing.minimum_charge is distinct from p_minimum_charge
      then
        raise exception 'idempotency_key_conflict: idempotency key % was already used for a different zone/distance tier proposal', p_idempotency_key
          using errcode = 'unique_violation';
      end if;
      return v_existing;
    end if;
  end if;

  begin
    insert into app.vendor_rate_zone_distance_tiers (
      tenant_id, rate_version_id, tier_order, zone_code, distance_min, distance_max, amount, minimum_charge, idempotency_key, created_by
    ) values (
      p_rate.tenant_id, p_rate.id, p_tier_order, v_zone_code, p_distance_min, p_distance_max, p_amount, p_minimum_charge, p_idempotency_key, p_actor_label
    )
    returning * into v_tier;
  exception
    when unique_violation then
      get stacked diagnostics v_constraint_name = constraint_name;
      if v_constraint_name = 'vendor_rate_zone_distance_tiers_idempotency_key_unique' and p_idempotency_key is not null then
        select * into v_existing from app.vendor_rate_zone_distance_tiers where tenant_id = p_rate.tenant_id and idempotency_key = p_idempotency_key;
        if found then
          if v_existing.rate_version_id is distinct from p_rate.id or v_existing.tier_order is distinct from p_tier_order
            or v_existing.zone_code is distinct from v_zone_code or v_existing.distance_min is distinct from p_distance_min or v_existing.distance_max is distinct from p_distance_max
            or v_existing.amount is distinct from p_amount or v_existing.minimum_charge is distinct from p_minimum_charge
          then
            raise exception 'idempotency_key_conflict: idempotency key % was already used for a different zone/distance tier proposal', p_idempotency_key
              using errcode = 'unique_violation';
          end if;
          return v_existing;
        end if;
      end if;
      raise exception 'duplicate_tier_order: rate version % already has a zone/distance tier at tier_order %', p_rate.id, p_tier_order
        using errcode = 'unique_violation';
  end;

  return v_tier;
end;
$$;

create function app.add_vendor_rate_zone_distance_tier(
  p_rate_version_id uuid,
  p_tier_order integer,
  p_zone_code text,
  p_distance_min numeric,
  p_distance_max numeric,
  p_amount numeric,
  p_minimum_charge numeric,
  p_idempotency_key text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.vendor_rate_zone_distance_tiers
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_rate app.vendor_rate_versions;
  v_tier app.vendor_rate_zone_distance_tiers;
begin
  v_rate := app.assert_vendor_rate_version_tier_editable(p_rate_version_id, p_actor_auth_user_id);

  v_tier := app._insert_vendor_rate_zone_distance_tier(v_rate, p_tier_order, p_zone_code, p_distance_min, p_distance_max, p_amount, p_minimum_charge, p_idempotency_key, p_actor_label);

  perform app.capture_audit_event(
    v_rate.tenant_id, p_actor_auth_user_id, p_actor_label, 'add_vendor_rate_zone_distance_tier',
    'app.vendor_rate_zone_distance_tiers', v_tier.id, 'success', null, null, to_jsonb(v_tier)
  );

  return v_tier;
end;
$$;

comment on function app.add_vendor_rate_zone_distance_tier is 'ISS-2026-060: PRC:Edit-gated (mirrors app.add_vendor_rate_tier''s own "child CRUD = Edit" mapping, via the unchanged app.assert_vendor_rate_version_tier_editable). Only while the parent rate version is pending_approval. Idempotency-key replay compares every load-bearing field.';

create function app.remove_vendor_rate_zone_distance_tier(
  p_tier_id uuid,
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
  v_tier app.vendor_rate_zone_distance_tiers;
  v_rate app.vendor_rate_versions;
begin
  select * into v_tier from app.vendor_rate_zone_distance_tiers where id = p_tier_id for update;
  if not found then
    raise exception 'vendor_rate_zone_distance_tier_not_found: %', p_tier_id using errcode = 'no_data_found';
  end if;

  v_rate := app.assert_vendor_rate_version_tier_editable(v_tier.rate_version_id, p_actor_auth_user_id);

  if v_tier.record_version <> p_expected_version then
    raise exception 'stale_version: vendor rate zone/distance tier % expected version % but found %', p_tier_id, p_expected_version, v_tier.record_version
      using errcode = 'serialization_failure';
  end if;

  delete from app.vendor_rate_zone_distance_tiers where id = p_tier_id and record_version = p_expected_version;
  if not found then
    raise exception 'stale_version: vendor rate zone/distance tier % target row was concurrently modified (expected version %)', p_tier_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_rate.tenant_id, p_actor_auth_user_id, p_actor_label, 'remove_vendor_rate_zone_distance_tier',
    'app.vendor_rate_zone_distance_tiers', p_tier_id, 'success', null, to_jsonb(v_tier), null
  );
end;
$$;

-- ===========================================================================
-- 3. Contiguity/non-overlap validator, partitioned by zone_code (design note 4).
--    Called only at app.approve_rate_version time (section 5 below).
-- ===========================================================================

create function app._validate_vendor_rate_zone_distance_tiers_contiguous(p_rate_version_id uuid)
returns void
language plpgsql
as $$
declare
  v_zone record;
  v_tier record;
  v_prev_max numeric;
  v_first boolean;
  v_distinct_ranges integer;
begin
  for v_zone in
    select distinct zone_code from app.vendor_rate_zone_distance_tiers where rate_version_id = p_rate_version_id
  loop
    select count(distinct (distance_min, distance_max)) into v_distinct_ranges
    from app.vendor_rate_zone_distance_tiers
    where rate_version_id = p_rate_version_id and zone_code is not distinct from v_zone.zone_code;

    -- Mirrors app._validate_vendor_rate_tiers_contiguous's own established rule
    -- (PRC-255): a dimension every tier in this zone_code partition shares the
    -- identical range on is, by definition, not the one this partition's tiers
    -- vary by, and is exempt from the ordered-non-overlapping requirement.
    if v_distinct_ranges > 1 then
      v_first := true;
      v_prev_max := null;
      for v_tier in
        select distance_min, distance_max
        from app.vendor_rate_zone_distance_tiers
        where rate_version_id = p_rate_version_id and zone_code is not distinct from v_zone.zone_code
        order by coalesce(distance_min, 0), tier_order
      loop
        if not v_first then
          if v_prev_max is null then
            raise exception 'zone_distance_tier_overlap: an unbounded (null distance_max) tier must be the last tier by distance for zone % -- another tier starts at % after it', coalesce(v_zone.zone_code, '(any zone)'), v_tier.distance_min
              using errcode = 'check_violation';
          elsif coalesce(v_tier.distance_min, 0) < v_prev_max then
            raise exception 'zone_distance_tier_overlap: tier distance ranges overlap at % for zone % (previous tier''s distance_max is %)', v_tier.distance_min, coalesce(v_zone.zone_code, '(any zone)'), v_prev_max
              using errcode = 'check_violation';
          elsif coalesce(v_tier.distance_min, 0) > v_prev_max then
            raise exception 'zone_distance_tier_gap: a gap exists in distance coverage between % and % for zone % -- tiers must be contiguous ([min,max) half-open, touching boundaries)', v_prev_max, v_tier.distance_min, coalesce(v_zone.zone_code, '(any zone)')
              using errcode = 'check_violation';
          end if;
        end if;
        v_prev_max := v_tier.distance_max;
        v_first := false;
      end loop;
    end if;
  end loop;
end;
$$;

comment on function app._validate_vendor_rate_zone_distance_tiers_contiguous is 'ISS-2026-060: the zone/distance sibling of PRC-255''s app._validate_vendor_rate_tiers_contiguous, partitioned by zone_code (IS NOT DISTINCT FROM, null-safe) so each zone''s own distance ladder (or the single "any zone" ladder, when zone_code is null throughout) is validated independently. Called once, at app.approve_rate_version time.';

-- ===========================================================================
-- 4. app._compute_vendor_rate_zone_distance_amount + app.calculate_vendor_rate_zoned
--    (design note 3) -- the new lookup entry point that composes with, never
--    replaces, app._compute_vendor_rate_amount (untouched).
-- ===========================================================================

create function app._compute_vendor_rate_zone_distance_amount(
  p_rate app.vendor_rate_versions,
  p_zone_code text,
  p_distance numeric,
  p_quantity numeric
)
returns table (
  matched_tier_id uuid,
  matched_zone_code text,
  matched_distance_min numeric,
  matched_distance_max numeric,
  base_component numeric,
  tier_component numeric,
  surcharge_component numeric,
  subtotal_amount numeric,
  minimum_amount_applied boolean,
  computed_amount numeric,
  rounding_mode text,
  rounding_precision integer,
  component_breakdown jsonb
)
language plpgsql
as $$
declare
  v_tier app.vendor_rate_zone_distance_tiers;
  v_quantity numeric := coalesce(p_quantity, 1);
  v_surcharge_total numeric := 0;
  v_component jsonb;
  v_subtotal numeric;
  v_minimum_applied boolean := false;
  v_final numeric;
begin
  if v_quantity <= 0 then
    raise exception 'invalid_quantity: quantity must be a positive number' using errcode = 'check_violation';
  end if;

  -- A tier with zone_code=null is a wildcard on the zone dimension; a tier with
  -- distance_min/max both null is a wildcard on the distance dimension. A
  -- zone-scoped or distance-scoped tier only matches an input that actually
  -- supplies the matching dimension value -- never matches by default when the
  -- caller passes null for that dimension (design note 4: no silent fallback).
  select * into v_tier
  from app.vendor_rate_zone_distance_tiers t
  where t.rate_version_id = p_rate.id
    and (t.zone_code is null or t.zone_code = p_zone_code)
    and (
      (t.distance_min is null and t.distance_max is null)
      or (p_distance is not null and p_distance >= coalesce(t.distance_min, 0) and (t.distance_max is null or p_distance < t.distance_max))
    )
  order by t.tier_order
  limit 1;

  if not found then
    raise exception 'zone_distance_tier_not_matched: no zone/distance tier on rate version % matches zone_code=% distance=% -- a zone/distance-priced rate requires an unambiguous match, never a silent fallback to base_amount', p_rate.id, coalesce(p_zone_code, '(null)'), coalesce(p_distance::text, '(null)')
      using errcode = 'no_data_found';
  end if;

  for v_component in select * from jsonb_array_elements(coalesce(p_rate.surcharge_components, '[]'::jsonb)) loop
    v_surcharge_total := v_surcharge_total + coalesce((v_component ->> 'amount')::numeric, 0);
  end loop;

  v_subtotal := (v_tier.amount * v_quantity) + v_surcharge_total;

  if v_tier.minimum_charge is not null and v_subtotal < v_tier.minimum_charge then
    v_subtotal := v_tier.minimum_charge;
    v_minimum_applied := true;
  elsif v_tier.minimum_charge is null and p_rate.minimum_amount is not null and v_subtotal < p_rate.minimum_amount then
    v_subtotal := p_rate.minimum_amount;
    v_minimum_applied := true;
  end if;

  v_final := app.apply_finance_rounding(v_subtotal, 2, 'round_half_up');

  return query select
    v_tier.id, v_tier.zone_code, v_tier.distance_min, v_tier.distance_max,
    v_tier.amount * v_quantity, v_tier.amount * v_quantity, v_surcharge_total, v_subtotal, v_minimum_applied, v_final,
    'round_half_up'::text, 2,
    jsonb_build_object(
      'rate_version_id', p_rate.id, 'matched_tier_id', v_tier.id, 'matched_zone_code', v_tier.zone_code,
      'matched_distance_min', v_tier.distance_min, 'matched_distance_max', v_tier.distance_max,
      'zone_code_input', p_zone_code, 'distance_input', p_distance, 'quantity', v_quantity,
      'surcharge_components', p_rate.surcharge_components, 'lead_time_days', p_rate.lead_time_days,
      'capacity_terms', p_rate.capacity_terms, 'currency', p_rate.currency
    );
end;
$$;

comment on function app._compute_vendor_rate_zone_distance_amount is 'ISS-2026-060: private, ungated (no grant) -- the zone/distance sibling of app._compute_vendor_rate_amount (PRC-255, untouched by this migration). Matches a tier by zone_code equality (or wildcard) and [min,max) half-open distance containment (or wildcard), sums surcharge_components, applies the matched minimum, rounds via app.apply_finance_rounding (FIN-194, reused, never reimplemented) -- structurally identical treatment to the weight/volume engine, applied to a different matching dimension.';

create function app.calculate_vendor_rate_zoned(
  p_rate_version_id uuid,
  p_zone_code text,
  p_distance numeric,
  p_weight numeric,
  p_volume numeric,
  p_quantity numeric,
  p_actor_auth_user_id uuid
)
returns table (
  rate_version_id uuid,
  zone_distance_priced boolean,
  matched_tier_id uuid,
  currency text,
  base_component numeric,
  tier_component numeric,
  surcharge_component numeric,
  subtotal_amount numeric,
  minimum_amount_applied boolean,
  computed_amount numeric,
  rounding_mode text,
  rounding_precision integer,
  component_breakdown jsonb,
  computed_at timestamptz
)
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_rate app.vendor_rate_versions;
  v_decision app.rbac_decision;
  v_has_zone_tiers boolean;
begin
  select * into v_rate from app.vendor_rate_versions where id = p_rate_version_id;
  if not found then
    raise exception 'rate_version_not_found: %', p_rate_version_id using errcode = 'no_data_found';
  end if;

  -- Same gate app.calculate_vendor_rate itself requires (ADR-0020's own directed
  -- reuse) -- the entire return shape is cost data either way.
  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_rate.tenant_id, 'PRC', 'View cost');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:View cost (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_rate.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  select exists(select 1 from app.vendor_rate_zone_distance_tiers z where z.rate_version_id = p_rate_version_id) into v_has_zone_tiers;

  if v_has_zone_tiers then
    return query
    select p_rate_version_id, true, z.matched_tier_id, v_rate.currency, z.base_component, z.tier_component, z.surcharge_component,
      z.subtotal_amount, z.minimum_amount_applied, z.computed_amount, z.rounding_mode, z.rounding_precision, z.component_breakdown, now()
    from app._compute_vendor_rate_zone_distance_amount(v_rate, p_zone_code, p_distance, p_quantity) z;
  else
    -- No zone/distance dimension configured on this rate card: compose with the
    -- existing, UNMODIFIED weight/volume resolution engine -- byte-identical to
    -- app.calculate_vendor_rate's own result for the same inputs (design note 3).
    return query
    select p_rate_version_id, false, c.matched_tier_id, v_rate.currency, c.base_component, c.tier_component, c.surcharge_component,
      c.subtotal_amount, c.minimum_amount_applied, c.computed_amount, c.rounding_mode, c.rounding_precision, c.component_breakdown, now()
    from app._compute_vendor_rate_amount(v_rate, p_weight, p_volume, p_quantity) c;
  end if;
end;
$$;

comment on function app.calculate_vendor_rate_zoned is 'ISS-2026-060: new, additive lookup entry point -- composes with (calls) app._compute_vendor_rate_amount UNCHANGED when no zone/distance tier is configured on this rate version (zone_distance_priced=false in the result), or the new app._compute_vendor_rate_zone_distance_amount when at least one is (zone_distance_priced=true). Never silently falls back to base_amount on a configured-but-unmatched zone/distance input -- raises zone_distance_tier_not_matched instead. PRC:View cost-gated, mirroring app.calculate_vendor_rate exactly.';

-- ===========================================================================
-- 5. app.approve_rate_version widened (design note 4). Unchanged 4-argument
--    signature -- `create or replace function`, not DROP+CREATE. Reproduces the
--    CURRENT LIVE body (read via pg_get_functiondef immediately before writing
--    this file -- it already carries a PRC-259 governance-approval gate absent
--    from the 20260730620000 migration file's own text) plus exactly one new
--    statement, placed immediately after the existing weight/volume tier
--    contiguity validation call.
-- ===========================================================================

create or replace function app.approve_rate_version(
  p_rate_version_id uuid,
  p_expected_version integer,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.vendor_rate_versions
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_rate app.vendor_rate_versions;
  v_vendor_status text;
begin
  -- ATW-032 (ISS-2026-032) regression guard: unchanged, preserved from the live body.
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  -- PRC-255 addition (design note 13): `for update` -- serializes this approval
  -- against a concurrent app.add_vendor_rate_tier/app.remove_vendor_rate_tier call
  -- on the SAME parent row (both lock this exact row before touching a tier).
  select * into v_rate from app.vendor_rate_versions where id = p_rate_version_id for update;
  if not found then
    raise exception 'rate_version_not_found: %', p_rate_version_id using errcode = 'no_data_found';
  end if;

  if not app.is_support_grant_authority(p_actor_auth_user_id, v_rate.tenant_id) then
    raise exception 'insufficient_authority: identity % holds neither Supreme Admin nor tenant_admin authority for tenant %', p_actor_auth_user_id, v_rate.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_rate.record_version <> p_expected_version then
    raise exception 'stale_version: rate version % expected version % but found %', p_rate_version_id, p_expected_version, v_rate.record_version
      using errcode = 'serialization_failure';
  end if;

  if v_rate.approval_status <> 'pending_approval' then
    raise exception 'invalid_transition: rate version % is % and cannot be approved', p_rate_version_id, v_rate.approval_status
      using errcode = 'check_violation';
  end if;

  -- PRC-259: the gated "next lifecycle transition" -- a rate cannot be
  -- domain-approved while a crossed governance threshold from
  -- app.create_rate_version is still pending platform-routed approval. Preserved
  -- unchanged from the live body -- this migration does not touch PRC-259's own
  -- governance routing.
  if v_rate.governance_approval_status not in ('approved', 'not_required') then
    raise exception 'rate_governance_approval_pending: rate version % governance_approval_status is % (must be approved or not_required)', p_rate_version_id, v_rate.governance_approval_status
      using errcode = 'check_violation';
  end if;

  -- PRC-255 addition (design note 12): a rate linked to a real vendor identity
  -- cannot go live for a non-active vendor.
  if v_rate.vendor_master_id is not null then
    select lifecycle_status into v_vendor_status from app.vendor_profiles where master_record_id = v_rate.vendor_master_id;
    if v_vendor_status is distinct from 'active' then
      raise exception 'vendor_not_active: linked vendor % is % -- a rate cannot be approved for a non-active vendor', v_rate.vendor_master_id, coalesce(v_vendor_status, 'unregistered')
        using errcode = 'check_violation';
    end if;
  end if;

  -- PRC-255 addition (design note 3): ordered non-overlapping tier validation,
  -- validated at publish time only.
  perform app._validate_vendor_rate_tiers_contiguous(p_rate_version_id);

  -- ISS-2026-060 addition (design note 4): the zone/distance sibling validator,
  -- same "validate once, at publish" discipline. A rate version with zero
  -- zone/distance tiers is a trivial, immediate no-op (the new validator's own
  -- FOR loop iterates zero times) -- zero behavior change for every rate that
  -- does not configure this dimension.
  perform app._validate_vendor_rate_zone_distance_tiers_contiguous(p_rate_version_id);

  begin
    update app.vendor_rate_versions
    set approval_status = 'approved', approved_by = p_actor_label, approved_at = now(), updated_at = now(), record_version = record_version + 1
    where id = p_rate_version_id and record_version = p_expected_version
    returning * into v_rate;
  exception
    -- PRC-255 addition (design note 4): translate the raw EXCLUDE-constraint
    -- violation into the same clear, named error class every other validation
    -- failure in this repository raises.
    when exclusion_violation then
      raise exception 'ambiguous_overlap: an approved, currently-effective rate version already exists for the identical vendor/service/mode/lane/equipment scope with an overlapping validity window'
        using errcode = 'check_violation';
    when deadlock_detected then
      raise exception 'ambiguous_overlap: a concurrent approval at the identical vendor/service/mode/lane/equipment scope could not be serialized -- retry the approval'
        using errcode = 'check_violation';
  end;
  if not found then
    raise exception 'stale_version: rate version % target row was concurrently modified (expected version %)', p_rate_version_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_rate.tenant_id, p_actor_auth_user_id, p_actor_label, 'approve_rate_version',
    'app.vendor_rate_versions', v_rate.id, 'success', null, null, jsonb_build_object('approval_status', v_rate.approval_status)
  );

  return v_rate;
end;
$$;

comment on function app.approve_rate_version is 'COM-149, widened PRC-255, widened ISS-2026-060: unchanged signature. Adds (in order) a for-update lock, the PRC-259 governance-approval gate, a linked-vendor lifecycle_status=active check, weight/volume tier-contiguity validation, zone/distance tier-contiguity validation (this migration, no-op when zero zone/distance tiers exist), and translation of the EXCLUDE-constraint ambiguous-overlap violation into a named error. Authority (app.is_support_grant_authority) is unchanged.';

-- ===========================================================================
-- 6. RLS + grants.
-- ===========================================================================

alter table app.vendor_rate_zone_distance_tiers enable row level security;

create policy vendor_rate_zone_distance_tiers_select_scoped on app.vendor_rate_zone_distance_tiers
  for select to authenticated
  using ((app.has_active_tenant_membership(tenant_id) and not app.actor_holds_customer_user_layer(tenant_id)) or app.is_supreme_admin());

revoke execute on all functions in schema app from public;

grant select (
  id, tenant_id, rate_version_id, tier_order, zone_code, distance_min, distance_max,
  record_version, created_by, created_at, updated_at
) on app.vendor_rate_zone_distance_tiers to authenticated;
grant select on app.vendor_rate_zone_distance_tiers to service_role;

grant select on app.vendor_rate_zone_distance_tiers_directory to authenticated, service_role;

grant execute on function app.add_vendor_rate_zone_distance_tier(uuid, integer, text, numeric, numeric, numeric, numeric, text, uuid, text) to authenticated, service_role;
grant execute on function app.remove_vendor_rate_zone_distance_tier(uuid, integer, uuid, text) to authenticated, service_role;
grant execute on function app.calculate_vendor_rate_zoned(uuid, text, numeric, numeric, numeric, numeric, uuid) to authenticated, service_role;
