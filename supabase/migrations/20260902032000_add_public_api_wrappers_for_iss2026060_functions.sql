-- Follow-up to 20260902030000 (ISS-2026-060): the three new externally-callable
-- app.* functions it grants to authenticated/service_role
-- (app.add_vendor_rate_zone_distance_tier, app.remove_vendor_rate_zone_distance_tier,
-- app.calculate_vendor_rate_zoned) each need a matching public.* wrapper, the
-- standing repository-wide convention 20260826000000_create_public_api_data_
-- wrappers.sql established (app schema is unreachable via PostgREST directly --
-- PGRST106) and scripts/db-tests/public-api-wrapper-regression.sql enforces
-- exhaustively on every db-test run. Caught live by that exact regression suite
-- against this checkpoint's own first draft -- fixed here, not silently left
-- missing. Mirrors app.add_vendor_rate_tier / app.remove_vendor_rate_tier / app.
-- calculate_vendor_rate's own public.* wrappers byte-for-byte in shape (language
-- sql, security definer, set search_path to pg_catalog/pg_temp, a bare passthrough
-- select), granted to the identical role set the underlying app.* function itself
-- grants -- never wider (the regression suite's own second assertion, "no wrapper
-- grants a role app.<name> itself does not grant", zero-tolerance).

create function public.add_vendor_rate_zone_distance_tier(
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
language sql
security definer
set search_path = pg_catalog, pg_temp
as $$
  select app.add_vendor_rate_zone_distance_tier(p_rate_version_id, p_tier_order, p_zone_code, p_distance_min, p_distance_max, p_amount, p_minimum_charge, p_idempotency_key, p_actor_auth_user_id, p_actor_label);
$$;

comment on function public.add_vendor_rate_zone_distance_tier is 'PostgREST-reachable wrapper for app.add_vendor_rate_zone_distance_tier (ISS-2026-060) -- 20260826000000''s own standing convention (app schema not exposed to PostgREST).';

create function public.remove_vendor_rate_zone_distance_tier(
  p_tier_id uuid,
  p_expected_version integer,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns void
language sql
security definer
set search_path = pg_catalog, pg_temp
as $$
  select app.remove_vendor_rate_zone_distance_tier(p_tier_id, p_expected_version, p_actor_auth_user_id, p_actor_label);
$$;

comment on function public.remove_vendor_rate_zone_distance_tier is 'PostgREST-reachable wrapper for app.remove_vendor_rate_zone_distance_tier (ISS-2026-060).';

create function public.calculate_vendor_rate_zoned(
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
language sql
stable
security definer
set search_path = pg_catalog, pg_temp
as $$
  select * from app.calculate_vendor_rate_zoned(p_rate_version_id, p_zone_code, p_distance, p_weight, p_volume, p_quantity, p_actor_auth_user_id);
$$;

comment on function public.calculate_vendor_rate_zoned is 'PostgREST-reachable wrapper for app.calculate_vendor_rate_zoned (ISS-2026-060), mirroring public.calculate_vendor_rate''s own shape exactly.';

revoke execute on function public.add_vendor_rate_zone_distance_tier(uuid, integer, text, numeric, numeric, numeric, numeric, text, uuid, text) from public;
revoke execute on function public.remove_vendor_rate_zone_distance_tier(uuid, integer, uuid, text) from public;
revoke execute on function public.calculate_vendor_rate_zoned(uuid, text, numeric, numeric, numeric, numeric, uuid) from public;

-- Identical role set to the underlying app.* grant -- authenticated, service_role.
-- Never anon (the zero-tolerance privilege-widening regression check would fail).
grant execute on function public.add_vendor_rate_zone_distance_tier(uuid, integer, text, numeric, numeric, numeric, numeric, text, uuid, text) to authenticated, service_role;
grant execute on function public.remove_vendor_rate_zone_distance_tier(uuid, integer, uuid, text) to authenticated, service_role;
grant execute on function public.calculate_vendor_rate_zoned(uuid, text, numeric, numeric, numeric, numeric, uuid) to authenticated, service_role;
