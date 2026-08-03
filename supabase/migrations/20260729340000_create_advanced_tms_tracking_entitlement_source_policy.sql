-- Advanced TMS capability CG-S10-ATW-006's own child ATW-226A (Prompt 226 decomposition,
-- "Tracking entitlement and source policy" -- docs/build-log/phase-05/
-- ADVANCED_TMS_WMS_EXECUTION_INDEX.md §1.4). Implements the two things every later
-- ATW-226 child (226D-226I) reads rather than re-deriving: (1) whether a tenant's
-- tracking package is entitled at all, its tier, and its numeric limits; (2) a
-- tenant-level *default* multi-source policy (priority order, freshness/accuracy
-- thresholds, switch hysteresis) that ATW-223's own per-vehicle
-- `app.vehicle_tracking_source_priorities` overrides when a vehicle has an explicit
-- row.
--
-- Design boundary (disclosed):
--
-- 1. Entitlement/package/limits are NOT a new schema. ATW-222's own migration header
--    (20260729300000, `app.is_shipment_tracking_entitled`'s disclosed-stub comment)
--    already named the intended mechanism verbatim: "the real tracking.* entitlement
--    keys in the Configuration Engine (PLT-121)". This migration honors that citation
--    exactly -- it reuses `app.config_types`'s already-seeded bare `'feature'` type
--    (Configuration Engine, PLT-121) via a tenant-scoped `config_object` with
--    `tracking.enabled` / `tracking.package` / `tracking.limits` items, resolved
--    through the existing `app.resolve_config()` RPC. No new config_type is
--    registered and no per-tenant data is seeded here (there is no tenant to scope it
--    to yet) -- a tenant admin assigns a tracking package later via PLT-121's own
--    already-shipped `createConfigDraft`/`setConfigItems`/`publishConfigVersion`
--    service-layer mutations, exactly as any other config-engine consumer would.
--    This is deliberately NOT `app.evaluate_entitlement` (PLT-106, the coarse
--    module-level SaaS subscription gate) or Feature Flags (PLT-133, which mints its
--    own `feature:<flagKey>` config_type per flag for kill-switch/rollout/cohort
--    concerns this capability does not have) -- neither is what ATW-222's own
--    citation named, and a tracking package tier plus numeric limits is config data,
--    not a rollout flag.
-- 2. Source *priority* is NOT a new schema either. ATW-223's own
--    `app.vehicle_tracking_source_priorities` (20260729310000) already declares a
--    per-vehicle primary/fallback source preference, with its own comment disclosing
--    that "live hybrid arbitration using freshness/accuracy/health at runtime is
--    ATW-226F's own scope." What is genuinely new here is the *tenant-level default*
--    those per-vehicle rows fall back to when a vehicle has none, plus the
--    freshness/accuracy/hysteresis thresholds no existing table carries at any grain
--    -- a distinct grain (tenant vs. vehicle) and a distinct field set, not a fork of
--    ATW-223's table.
-- 3. `app.is_shipment_tracking_entitled` is replaced via `CREATE OR REPLACE FUNCTION`
--    with an identical signature (never edit an applied migration) -- its existing
--    `authenticated`/`service_role` EXECUTE grant from 20260729300000 is preserved
--    automatically and is not re-granted here.
--
-- Per ERR-2026-004 (docs/runtime/ERROR_LEDGER.md): this migration carries its own
-- explicit `revoke execute on all functions in schema app from public` statement
-- before its final grants, the standing per-migration convention since `PLT-118`.

-- 1. Entitlement/package/limits resolution -- Configuration Engine ('feature' type),
--    read-only wrapper. `app.resolve_config()` already returns a jsonb item map keyed
--    by config item key; this composite type gives every later ATW-226 child (and
--    this migration's own `is_shipment_tracking_entitled`) one stable, typed shape
--    to read instead of re-parsing raw jsonb at each call site.
create type app.tracking_package_resolution as (
  enabled boolean,
  package_code text,
  max_tracked_vehicles integer,
  max_mobile_sessions integer,
  history_retention_days integer,
  resolved_version_id uuid
);

-- `left join ... on true` against a single dummy row guarantees exactly one output
-- row even when `app.resolve_config()` resolves nothing at any scope level (no
-- tracking package ever assigned to this tenant) -- the honest default is
-- `enabled = false` with every other field null, never a fabricated entitlement.
create function app.resolve_tenant_tracking_package(p_tenant_id uuid)
returns app.tracking_package_resolution
language sql
stable
as $$
  select
    coalesce((r.items ->> 'tracking.enabled')::boolean, false),
    r.items ->> 'tracking.package',
    nullif(r.items -> 'tracking.limits' ->> 'max_tracked_vehicles', '')::integer,
    nullif(r.items -> 'tracking.limits' ->> 'max_mobile_sessions', '')::integer,
    nullif(r.items -> 'tracking.limits' ->> 'history_retention_days', '')::integer,
    r.resolved_version_id
  from (select 1) as _one
  left join app.resolve_config('feature', p_tenant_id) r on true;
$$;

comment on function app.resolve_tenant_tracking_package is
  'ATW-226A: the single tracking-package resolution point every later ATW-226 child reads rather than re-deriving. Reuses Configuration Engine (PLT-121) app.resolve_config() against the pre-seeded bare ''feature'' config_type at tenant scope -- tracking.enabled/tracking.package/tracking.limits.* items. Always returns exactly one row; enabled=false with every other field null is the honest default when no package was ever assigned, never a fabricated entitlement.';

-- Real implementation, replacing ATW-222's disclosed stub (20260729300000) via
-- CREATE OR REPLACE with an identical signature -- its existing grant is preserved.
create or replace function app.is_shipment_tracking_entitled(p_tenant_id uuid)
returns boolean
language sql
stable
as $$
  select (app.resolve_tenant_tracking_package(p_tenant_id)).enabled;
$$;

comment on function app.is_shipment_tracking_entitled is
  'ATW-226A: real implementation, replacing ATW-222''s disclosed always-false stub. Delegates to app.resolve_tenant_tracking_package() (Configuration Engine, PLT-121) -- a tenant is entitled once, and only once, an authorized admin publishes a tracking.enabled=true config item for that tenant via the existing PLT-121 draft/publish mutations.';

-- 2. Tenant-level default source policy -- priority/freshness/accuracy/hysteresis.
-- Distinct grain from ATW-223's app.vehicle_tracking_source_priorities (per-vehicle);
-- this is the tenant-wide fallback those per-vehicle rows override, and the only
-- place freshness/accuracy/hysteresis thresholds exist at any grain yet. A policy
-- declaration only -- ATW-226F performs live arbitration using this policy plus
-- real-time source health, none of which exists yet.
create table app.tenant_tracking_source_policies (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  default_source_priority text[] not null default array['driver_mobile', 'direct_device', 'third_party_platform'],
  freshness_threshold_seconds integer not null default 300,
  accuracy_threshold_meters numeric not null default 100,
  switch_hysteresis_seconds integer not null default 120,
  record_version integer not null default 1,
  created_by text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint tenant_tracking_source_policies_tenant_unique unique (tenant_id),
  constraint tenant_tracking_source_policies_priority_nonempty_check check (array_length(default_source_priority, 1) > 0),
  constraint tenant_tracking_source_policies_priority_valid_check check (
    default_source_priority <@ array['driver_mobile', 'direct_device', 'third_party_platform']::text[]
  ),
  constraint tenant_tracking_source_policies_freshness_check check (freshness_threshold_seconds > 0),
  constraint tenant_tracking_source_policies_accuracy_check check (accuracy_threshold_meters > 0),
  constraint tenant_tracking_source_policies_hysteresis_check check (switch_hysteresis_seconds >= 0)
);

comment on table app.tenant_tracking_source_policies is
  'ATW-226A: one row per tenant (explicit not-required state -- absence means "no explicit override, tenant-wide system default applies", read via app.resolve_tenant_tracking_source_policy()), declaring the default multi-source priority order and the freshness/accuracy/hysteresis thresholds ATW-223''s own per-vehicle app.vehicle_tracking_source_priorities falls back to. Business rule (226_GPS_TELEMATICS_INTEGRATION_PROMPT.md §24): "source switches are auditable and cannot oscillate without configured hysteresis" -- switch_hysteresis_seconds is that configured value; enforcing it at runtime is ATW-226F''s own scope.';

create index tenant_tracking_source_policies_tenant_idx on app.tenant_tracking_source_policies (tenant_id);

create function app.touch_tenant_tracking_source_policies_row()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  new.record_version := old.record_version + 1;
  return new;
end;
$$;

create trigger tenant_tracking_source_policies_touch_row
  before update on app.tenant_tracking_source_policies
  for each row
  execute function app.touch_tenant_tracking_source_policies_row();

-- Element-set validity is enforced structurally (CHECK, above); array *uniqueness*
-- (no repeated source type) cannot be expressed in a CHECK constraint (Postgres
-- forbids subqueries there) so it is validated here, the same function-body
-- validation idiom ATW-223's app.set_vehicle_tracking_source_priority already uses
-- for its own priority_rank/source_type checks.
create function app.upsert_tenant_tracking_source_policy(
  p_tenant_id uuid,
  p_default_source_priority text[],
  p_freshness_threshold_seconds integer,
  p_accuracy_threshold_meters numeric,
  p_switch_hysteresis_seconds integer,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.tenant_tracking_source_policies
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_policy app.tenant_tracking_source_policies;
begin
  if p_default_source_priority is null or array_length(p_default_source_priority, 1) is null then
    raise exception 'invalid_source_priority: default_source_priority must not be empty' using errcode = 'check_violation';
  end if;
  if not (p_default_source_priority <@ array['driver_mobile', 'direct_device', 'third_party_platform']::text[]) then
    raise exception 'invalid_source_priority: default_source_priority may only contain driver_mobile, direct_device, third_party_platform' using errcode = 'check_violation';
  end if;
  if array_length(p_default_source_priority, 1) <> (
    select count(*) from (select distinct unnest(p_default_source_priority)) as d
  ) then
    raise exception 'invalid_source_priority: default_source_priority must not contain duplicate source types' using errcode = 'check_violation';
  end if;
  if p_freshness_threshold_seconds is null or p_freshness_threshold_seconds <= 0 then
    raise exception 'invalid_freshness_threshold: freshness_threshold_seconds must be a positive integer' using errcode = 'check_violation';
  end if;
  if p_accuracy_threshold_meters is null or p_accuracy_threshold_meters <= 0 then
    raise exception 'invalid_accuracy_threshold: accuracy_threshold_meters must be a positive number' using errcode = 'check_violation';
  end if;
  if p_switch_hysteresis_seconds is null or p_switch_hysteresis_seconds < 0 then
    raise exception 'invalid_switch_hysteresis: switch_hysteresis_seconds must not be negative' using errcode = 'check_violation';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'OPS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  insert into app.tenant_tracking_source_policies (
    tenant_id, default_source_priority, freshness_threshold_seconds,
    accuracy_threshold_meters, switch_hysteresis_seconds, created_by
  )
  values (
    p_tenant_id, p_default_source_priority, p_freshness_threshold_seconds,
    p_accuracy_threshold_meters, p_switch_hysteresis_seconds, p_actor_label
  )
  on conflict (tenant_id) do update set
    default_source_priority = excluded.default_source_priority,
    freshness_threshold_seconds = excluded.freshness_threshold_seconds,
    accuracy_threshold_meters = excluded.accuracy_threshold_meters,
    switch_hysteresis_seconds = excluded.switch_hysteresis_seconds
  returning * into v_policy;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'upsert_tenant_tracking_source_policy',
    'app.tenant_tracking_source_policies', v_policy.id, 'success', null, null,
    jsonb_build_object(
      'default_source_priority', p_default_source_priority,
      'freshness_threshold_seconds', p_freshness_threshold_seconds,
      'accuracy_threshold_meters', p_accuracy_threshold_meters,
      'switch_hysteresis_seconds', p_switch_hysteresis_seconds
    )
  );

  return v_policy;
end;
$$;

comment on function app.upsert_tenant_tracking_source_policy is
  'ATW-226A: idempotent one-row-per-tenant upsert, OPS:Edit-gated (the same authority tier ATW-223''s per-vehicle app.set_vehicle_tracking_source_priority already uses). A declared default policy only -- no telemetry is read or written here.';

-- Read helper mirroring app.resolve_tenant_tracking_package's own "always exactly one
-- row, honest default" shape -- absence of an explicit tenant_tracking_source_policies
-- row resolves to the system-wide default (is_explicit=false), never a raised error,
-- so every later ATW-226 child can call this unconditionally rather than
-- null-checking and re-deriving its own default constants.
create function app.resolve_tenant_tracking_source_policy(p_tenant_id uuid)
returns table (
  tenant_id uuid,
  default_source_priority text[],
  freshness_threshold_seconds integer,
  accuracy_threshold_meters numeric,
  switch_hysteresis_seconds integer,
  is_explicit boolean
)
language sql
stable
as $$
  select
    p_tenant_id,
    coalesce(t.default_source_priority, array['driver_mobile', 'direct_device', 'third_party_platform']::text[]),
    coalesce(t.freshness_threshold_seconds, 300),
    coalesce(t.accuracy_threshold_meters, 100),
    coalesce(t.switch_hysteresis_seconds, 120),
    (t.tenant_id is not null)
  from (select 1) as _one
  left join app.tenant_tracking_source_policies t on t.tenant_id = p_tenant_id;
$$;

comment on function app.resolve_tenant_tracking_source_policy is
  'ATW-226A: always returns exactly one row for any tenant_id, explicit-override-or-system-default (is_explicit discloses which). RLS on the underlying table still governs whether the caller may see a real explicit row at all; an unauthorized caller simply observes the system default, the same non-leaking shape app.is_shipment_tracking_entitled''s own honest-false default already established.';

alter table app.tenant_tracking_source_policies enable row level security;

create policy tenant_tracking_source_policies_select_scoped on app.tenant_tracking_source_policies
  for select to authenticated
  using (app.has_active_tenant_membership(tenant_id) or app.is_supreme_admin());

revoke execute on all functions in schema app from public;

grant select on app.tenant_tracking_source_policies to authenticated, service_role;
grant insert, update, delete on app.tenant_tracking_source_policies to service_role;

grant execute on function app.resolve_tenant_tracking_package(uuid) to authenticated, service_role;
grant execute on function app.upsert_tenant_tracking_source_policy(uuid, text[], integer, numeric, integer, uuid, text) to authenticated, service_role;
grant execute on function app.resolve_tenant_tracking_source_policy(uuid) to authenticated, service_role;
