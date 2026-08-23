-- Advanced TMS capability CG-S10-ATW-003 (Prompt 222, Advanced Dispatch Board with
-- Tracking Health). Extends OPS-175's own "list/queue, not a board" Basic Dispatch
-- into a wider operational window (assigned + dispatched + in_transit, not just
-- assigned) with a canonical tracking-health projection layered on top -- a
-- projection, never a tracking source (Prompt 222 §24).
--
-- Design boundary (disclosed): ATW-226 (Multi-Source GPS and Telematics Integration)
-- has not been built yet -- there is no canonical telemetry table, no entitlement
-- config, and no vehicle/driver/device identity anywhere in this repository (per
-- ATW-221's own greenfield confirmation, unchanged). This migration therefore adds
-- the *read model* Prompt 222 §13 requires (`tracking_status`,
-- `authoritative_source_type`, `last_position_at`, `freshness_status`,
-- `accuracy_meters`, `fallback_active`, `tracking_entitled`,
-- `tracking_exception_count`) as a genuinely real, empty table
-- (`app.shipment_tracking_health`) that `ATW-226F` (canonical telemetry
-- normalization/arbitration) will populate later -- never a duplicate position
-- history, per §13's own "never duplicate position history." No writer function is
-- created here (there is nothing yet for it to write); the dispatch board's own read
-- query LEFT JOINs this table and defaults every absent row to an honest
-- "not tracked" projection (`tracking_status = 'not_tracked'`), matching Prompt 222
-- §9's "the board may be implemented before 226, but tracking columns remain
-- feature-gated" instruction exactly -- these columns are real and queryable today,
-- they simply have no live data source to report yet, and every value is honest
-- (never fabricated "tracked" state). `app.is_shipment_tracking_entitled` is
-- similarly a disclosed stub returning `false` for every tenant until `ATW-226A`
-- (tracking entitlement and source policy) registers the real `tracking.*`
-- entitlement keys in the Configuration Engine (`PLT-121`) -- calling into that
-- engine for a key that was never registered would raise, not gracefully report
-- "not entitled," so a stub is the honest choice until that dependency ships.
--
-- Reuses `app.evaluate_dispatch_readiness` (OPS-175) unmodified for the `assigned`
-- rows in the wider window; readiness is meaningless for an already-dispatched or
-- in_transit shipment, so `is_ready`/`blockers` are null for those rows rather than
-- silently re-running (and misreporting) the assigned-only checklist against them.
-- Assign/hold/reassign/dispatch remain OPS-172's/OPS-175's own existing validated
-- commands -- this migration adds no new mutation, only an extended read model.
--
-- Per ERR-2026-004 (docs/runtime/ERROR_LEDGER.md): this migration carries its own
-- explicit `REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA app FROM PUBLIC` statement
-- before its final grants, the standing per-migration convention since `PLT-118`.

create table app.shipment_tracking_health (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  shipment_order_id uuid not null references app.shipment_orders (id),
  tracking_status text not null default 'not_tracked',
  authoritative_source_type text,
  last_position_at timestamptz,
  freshness_status text,
  accuracy_meters numeric,
  fallback_active boolean not null default false,
  tracking_exception_count integer not null default 0,
  record_version integer not null default 1,
  updated_at timestamptz not null default now(),
  constraint shipment_tracking_health_shipment_unique unique (shipment_order_id),
  constraint shipment_tracking_health_status_check check (tracking_status in ('not_tracked', 'tracked', 'stale', 'degraded', 'conflict')),
  constraint shipment_tracking_health_source_check check (authoritative_source_type is null or authoritative_source_type in ('driver_mobile', 'direct_device', 'third_party_platform', 'hybrid')),
  constraint shipment_tracking_health_freshness_check check (freshness_status is null or freshness_status in ('fresh', 'stale', 'unknown')),
  constraint shipment_tracking_health_accuracy_check check (accuracy_meters is null or accuracy_meters >= 0),
  constraint shipment_tracking_health_exception_count_check check (tracking_exception_count >= 0)
);

comment on table app.shipment_tracking_health is
  'ATW-221/222 boundary: the canonical per-shipment tracking-health projection Prompt 222 §13 requires. Deliberately empty and write-path-less as of ATW-222 -- ATW-226F (canonical telemetry normalization/arbitration) owns populating it once multi-source GPS ingestion exists. Never a position history table (that is ATW-226F''s own canonical telemetry store); this table holds only the single current derived health snapshot per shipment.';

create index shipment_tracking_health_tenant_idx on app.shipment_tracking_health (tenant_id);

-- Disclosed stub (see migration header) -- always false until ATW-226A registers the
-- real tracking.* entitlement keys in the Configuration Engine (PLT-121).
create function app.is_shipment_tracking_entitled(p_tenant_id uuid)
returns boolean
language sql
immutable
as $$
  select false;
$$;

comment on function app.is_shipment_tracking_entitled is
  'ATW-222 disclosed stub: always false. Real per-tenant tracking.* entitlement resolution is ATW-226A''s own scope (Configuration Engine, PLT-121) -- calling into an unregistered config key would raise rather than gracefully report "not entitled," so this stub is the honest interim answer, not a fabricated one.';

-- The advanced dispatch board's own read model (Prompt 222 §13/§15) -- a wider
-- operational window than OPS-175's own assigned-only ready queue, with the
-- feature-gated tracking-health projection joined in. A projection only: no mutation
-- exists here, and no raw GPS/device/provider data is ever read (there is none yet).
create view app.dispatch_board_queue
as
select
  so.*,
  case when so.status = 'assigned' then r.is_ready else null end as is_ready,
  case when so.status = 'assigned' then r.blockers else null end as blockers,
  exists (
    select 1 from app.resource_assignments ra
    where ra.shipment_order_id = so.id and ra.is_current and ra.status = 'active'
  ) as has_active_assignment,
  coalesce(th.tracking_status, 'not_tracked') as tracking_status,
  th.authoritative_source_type,
  th.last_position_at,
  coalesce(th.freshness_status, 'unknown') as freshness_status,
  th.accuracy_meters,
  coalesce(th.fallback_active, false) as fallback_active,
  app.is_shipment_tracking_entitled(so.tenant_id) as tracking_entitled,
  coalesce(th.tracking_exception_count, 0) as tracking_exception_count
from app.shipment_orders so
cross join lateral app.evaluate_dispatch_readiness(so.id) as r
left join app.shipment_tracking_health th on th.shipment_order_id = so.id
where so.status in ('assigned', 'dispatched', 'in_transit')
  and app.can_access_record(auth.uid(), so.tenant_id, so.owner_user_id, app.lead_record_scope_org_unit_ids(so.org_unit_id), null);

comment on view app.dispatch_board_queue is
  'ATW-222: every assigned/dispatched/in_transit Shipment Order the caller can access, record-scoped identically to app.dispatch_ready_queue (OPS-175). Tracking columns are honest and feature-gated (not_tracked/unknown/false/not entitled) until ATW-226 ships a real telemetry source -- never a fabricated live position. is_ready/blockers are populated only for assigned rows (readiness is meaningless once a shipment has already dispatched).';

alter table app.shipment_tracking_health enable row level security;

create policy shipment_tracking_health_select_scoped on app.shipment_tracking_health
  for select to authenticated
  using (
    exists (
      select 1 from app.shipment_orders so
      where so.id = shipment_tracking_health.shipment_order_id
        and app.can_access_record((select auth.uid()), so.tenant_id, so.owner_user_id, app.lead_record_scope_org_unit_ids(so.org_unit_id), null)
    )
  );

revoke execute on all functions in schema app from public;

grant select on app.shipment_tracking_health to authenticated, service_role;
grant insert, update, delete on app.shipment_tracking_health to service_role;
grant select on app.dispatch_board_queue to authenticated, service_role;

grant execute on function app.is_shipment_tracking_entitled(uuid) to authenticated, service_role;
