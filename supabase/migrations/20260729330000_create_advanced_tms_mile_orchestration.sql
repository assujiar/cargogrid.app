-- Advanced TMS capability CG-S10-ATW-006 (Prompt 225, First-, Middle-, and
-- Last-Mile Orchestration with Tracking Policy). Implements a tracking POLICY
-- and SESSION-ORCHESTRATION layer over the already-verified `ATW-221` leg
-- network -- every executable leg can resolve an explicit tracking policy
-- (required or explicitly not-required), and a resolved policy's own source
-- can be started, handed off, or ended with a real, audited lifecycle.
--
-- Design boundary (disclosed): Prompt 225 §14 itself states "do not ingest
-- telemetry here." `ATW-226` (Multi-Source GPS and Telematics Integration)
-- has not been built -- there is no live position feed, no raw device/mobile/
-- provider data stream, and no canonical telemetry store anywhere in this
-- repository. A "tracking session" in this migration is therefore an
-- *intent-level* orchestration record (who/what should be the authoritative
-- source, from when, via which resource) -- never a position, ping, or raw
-- telemetry row. `ATW-226F` (canonical telemetry normalization/arbitration)
-- owns turning a session's own declared source into live position data.
--
-- Scope and design decisions, disclosed rather than left implicit:
--
-- * **Entitlement is disclosed, not a hard gate on orchestration mechanics.**
--   `app.is_shipment_tracking_entitled` (`ATW-222`) is a disclosed stub,
--   always `false` until `ATW-226A` registers real `tracking.*` entitlement
--   keys. Session start/handoff/end are genuinely testable and useful today
--   (assigning/recording which resource *should* track a leg is real
--   orchestration bookkeeping, not itself a subscription-consuming action),
--   so this migration does not block them on entitlement -- it snapshots
--   `tracking_entitled_at_start` onto every session for honest audit
--   disclosure instead, mirroring `ATW-222`'s own "the column is real,
--   feature-gated only where it must be" precedent rather than blocking a
--   whole capability on a dependency that has not shipped.
-- * **Eligibility is real and checked against `ATW-223`'s own operational
--   data**: a chosen source/resource pair must be the shipment's own current
--   `app.resource_assignments` (OPS-172) occupant for that role, and must
--   satisfy the matching `ATW-223` capability flag/consent/mapping
--   (`app.driver_operational_profiles.mobile_tracking_consent`,
--   `app.vehicle_operational_profiles.direct_device_tracking_eligible` plus a
--   real active `app.device_vehicle_assignments`/`app.gps_devices` row,
--   `app.vehicle_operational_profiles.third_party_tracking_eligible` plus a
--   real active `app.provider_vehicle_mappings` row). `hybrid` multi-source
--   fusion is out of this checkpoint's scope (a session names exactly one
--   concrete source) -- `ATW-226F`'s own arbitration owns that.
-- * **Handoff follows `app.device_vehicle_assignments`'/`app.resource_
--   assignments`'/`ATW-224`'s own `is_current`/`superseded_by_id` idiom**,
--   with the update-before-insert statement ordering `ATW-224`'s own header
--   already disclosed finding and fixing (mark the prior row non-current
--   *before* inserting the new one, never after) -- applied correctly here
--   from the start, not found as a defect this time.
-- * **No-signal escalation is an orchestration-level staleness detector, not
--   a raw GPS-timeout detector.** `app.evaluate_leg_no_signal_escalation`
--   compares a still-`active` session's own `started_at` against the
--   policy's own `no_signal_escalation_seconds` -- real, bounded, and
--   provable without live telemetry (this checkpoint's own db-test proves it
--   by directly backdating a session's `started_at`, not by faking a GPS
--   feed). A genuinely stale session is ended (`end_reason = 'stale_source'`)
--   and a real `app.operational_exceptions` row is raised via the
--   already-verified `app.report_exception` (OPS-174), `source = 'system'`,
--   deduplicated on `correlation_key`. Raw per-ping GPS-timeout detection
--   remains `ATW-226F`'s own future scope.
-- * **Start/end triggers are declarative policy metadata, not wired into
--   `app.transition_shipment_leg` (OPS-170/`ATW-221`, an already-applied
--   migration this checkpoint never edits).** `start_trigger`/`end_trigger`
--   record which leg-lifecycle event *should* start/end tracking, for a
--   dispatcher or a future automation to act on -- automatically firing a
--   session on every leg transition would require hooking into an applied
--   migration's own function, forbidden by `AGENTS.md`'s "never edit an
--   applied migration."
-- * **`unauthorized_override` is a real, gated end path**, not merely a
--   label: ending a session with that reason requires `OPS:Override`
--   (already-seeded, the same gate `ATW-224`'s own override path uses) plus
--   a non-empty reason note, distinct from the `OPS:Edit`-gated
--   `leg_completed`/`manual_stop` paths.
-- * Record-scope reuses `app.can_access_record`/`app.lead_record_scope_org_
--   unit_ids` joined through to the owning Shipment Order, identical to
--   `ATW-221`'s own `shipment_legs`/`shipment_leg_stops` policy shape.
-- * Permission catalogue: reuses the already-seeded `OPS` action set
--   (`Create`, `Edit`, `Override`) -- no new `app.permissions` row.
-- * Per `ERR-2026-004`: this migration carries its own explicit
--   `REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA app FROM PUBLIC` statement
--   before its final grants.

create table app.shipment_leg_tracking_policies (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  shipment_leg_id uuid not null references app.shipment_legs (id),
  tracking_required boolean not null,
  allowed_sources text[] not null default '{}',
  preferred_source text,
  fallback_order text[] not null default '{}',
  freshness_tolerance_seconds integer,
  accuracy_tolerance_meters numeric,
  ping_interval_seconds integer,
  start_trigger text not null,
  end_trigger text not null,
  geofence_policy jsonb,
  customer_visible boolean not null default false,
  no_signal_escalation_seconds integer,
  policy_version integer not null default 1,
  status text not null default 'active',
  record_version integer not null default 1,
  created_by text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint shipment_leg_tracking_policies_shipment_leg_unique unique (shipment_leg_id),
  constraint shipment_leg_tracking_policies_source_check check (allowed_sources <@ array['driver_mobile', 'direct_device', 'third_party_platform']::text[]),
  constraint shipment_leg_tracking_policies_preferred_check check (preferred_source is null or preferred_source = any (allowed_sources)),
  constraint shipment_leg_tracking_policies_fallback_check check (fallback_order <@ allowed_sources),
  constraint shipment_leg_tracking_policies_not_required_clean_check check (
    tracking_required or (preferred_source is null and coalesce(array_length(fallback_order, 1), 0) = 0 and coalesce(array_length(allowed_sources, 1), 0) = 0)
  ),
  constraint shipment_leg_tracking_policies_start_trigger_check check (start_trigger in ('leg_dispatch', 'first_stop_arrival')),
  constraint shipment_leg_tracking_policies_end_trigger_check check (end_trigger in ('last_stop_arrival', 'leg_complete')),
  constraint shipment_leg_tracking_policies_freshness_check check (freshness_tolerance_seconds is null or freshness_tolerance_seconds > 0),
  constraint shipment_leg_tracking_policies_accuracy_check check (accuracy_tolerance_meters is null or accuracy_tolerance_meters >= 0),
  constraint shipment_leg_tracking_policies_interval_check check (ping_interval_seconds is null or ping_interval_seconds > 0),
  constraint shipment_leg_tracking_policies_escalation_check check (no_signal_escalation_seconds is null or no_signal_escalation_seconds > 0),
  constraint shipment_leg_tracking_policies_status_check check (status in ('active', 'disabled'))
);

comment on table app.shipment_leg_tracking_policies is
  'ATW-225: one tracking policy per shipment leg (ATW-221). tracking_required=false with empty allowed_sources/fallback_order/null preferred_source is the explicit "not tracking-required" state Prompt 225 §24 requires -- never an implicit default. geofence_policy is a candidate configuration blob only; actual geofence evaluation is ATW-226G''s own scope.';

create index shipment_leg_tracking_policies_tenant_idx on app.shipment_leg_tracking_policies (tenant_id);

create function app.touch_shipment_leg_tracking_policies_row()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  new.record_version := old.record_version + 1;
  new.policy_version := old.policy_version + 1;
  return new;
end;
$$;

create trigger shipment_leg_tracking_policies_touch_row
  before update on app.shipment_leg_tracking_policies
  for each row
  execute function app.touch_shipment_leg_tracking_policies_row();

create table app.shipment_leg_tracking_sessions (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  shipment_leg_id uuid not null references app.shipment_legs (id),
  policy_id uuid not null references app.shipment_leg_tracking_policies (id),
  source_type text not null,
  resource_kind text not null,
  resource_master_id uuid not null references app.master_records (id),
  device_id uuid references app.gps_devices (id),
  tracking_entitled_at_start boolean not null default false,
  status text not null default 'active',
  started_at timestamptz not null default now(),
  ended_at timestamptz,
  end_reason text,
  is_current boolean not null default true,
  superseded_by_id uuid references app.shipment_leg_tracking_sessions (id),
  created_by text,
  created_at timestamptz not null default now(),
  constraint shipment_leg_tracking_sessions_source_check check (source_type in ('driver_mobile', 'direct_device', 'third_party_platform')),
  constraint shipment_leg_tracking_sessions_resource_kind_check check (resource_kind in ('vehicle', 'driver')),
  constraint shipment_leg_tracking_sessions_kind_source_match_check check (
    (source_type = 'driver_mobile' and resource_kind = 'driver') or (source_type in ('direct_device', 'third_party_platform') and resource_kind = 'vehicle')
  ),
  constraint shipment_leg_tracking_sessions_device_required_check check ((source_type = 'direct_device') = (device_id is not null)),
  constraint shipment_leg_tracking_sessions_status_check check (status in ('active', 'ended')),
  constraint shipment_leg_tracking_sessions_end_reason_check check (end_reason is null or end_reason in ('leg_completed', 'handoff', 'stale_source', 'manual_stop', 'unauthorized_override')),
  constraint shipment_leg_tracking_sessions_ended_consistency_check check ((status = 'ended') = (ended_at is not null))
);

comment on table app.shipment_leg_tracking_sessions is
  'ATW-225: an intent-level tracking-source assignment for one leg -- never a position/ping/raw-telemetry row (ATW-226F''s own scope). is_current/superseded_by_id is the identical history-preservation idiom app.resource_assignments (OPS-172), app.device_vehicle_assignments (ATW-223), and app.route_planning_selected_plans (ATW-224) already established. tracking_entitled_at_start is a disclosed audit snapshot, never a gate on this table''s own lifecycle.';

create index shipment_leg_tracking_sessions_tenant_leg_idx on app.shipment_leg_tracking_sessions (tenant_id, shipment_leg_id);
create unique index shipment_leg_tracking_sessions_current_leg_unique on app.shipment_leg_tracking_sessions (shipment_leg_id) where is_current;

-- app.check_leg_tracking_source_eligible -- the one governed eligibility
-- primitive, reused by both app.resolve_leg_tracking_policy (loops over
-- every allowed source) and app.start_leg_tracking_session/app.handoff_leg_
-- tracking_session (validates one specific caller-chosen source/resource).
create function app.check_leg_tracking_source_eligible(
  p_shipment_leg_id uuid,
  p_source_type text,
  p_resource_kind text,
  p_resource_master_id uuid,
  p_device_id uuid
)
returns boolean
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_leg app.shipment_legs;
  v_assigned boolean;
begin
  select * into v_leg from app.shipment_legs where id = p_shipment_leg_id;
  if not found then
    return false;
  end if;

  select exists (
    select 1 from app.resource_assignments
    where shipment_order_id = v_leg.shipment_order_id and role = p_resource_kind and resource_id = p_resource_master_id
      and is_current and status = 'active'
  ) into v_assigned;
  if not v_assigned then
    return false;
  end if;

  if p_source_type = 'driver_mobile' then
    return exists (
      select 1 from app.driver_operational_profiles
      where driver_master_id = p_resource_master_id and status = 'active' and mobile_tracking_consent
    );
  elsif p_source_type = 'direct_device' then
    if p_device_id is null then
      return false;
    end if;
    return exists (
      select 1 from app.vehicle_operational_profiles vop
      join app.device_vehicle_assignments dva on dva.vehicle_operational_profile_id = vop.id and dva.is_current
      join app.gps_devices d on d.id = dva.device_id and d.status = 'active'
      where vop.vehicle_master_id = p_resource_master_id and vop.status = 'active' and vop.direct_device_tracking_eligible and dva.device_id = p_device_id
    );
  elsif p_source_type = 'third_party_platform' then
    return exists (
      select 1 from app.vehicle_operational_profiles vop
      where vop.vehicle_master_id = p_resource_master_id and vop.status = 'active' and vop.third_party_tracking_eligible
    ) and exists (
      select 1 from app.provider_vehicle_mappings where vehicle_master_id = p_resource_master_id and status = 'active'
    );
  else
    return false;
  end if;
end;
$$;

comment on function app.check_leg_tracking_source_eligible is
  'ATW-225: real eligibility against ATW-223''s own operational data -- the chosen resource must be the shipment''s own current app.resource_assignments (OPS-172) occupant for that role, plus the matching capability flag/consent/device/provider-mapping. Independent of tracking entitlement (this migration''s own header) -- entitlement is disclosed, never a gate here.';

-- app.upsert_shipment_leg_tracking_policy -- one policy per leg (idempotent
-- upsert on shipment_leg_id).
create function app.upsert_shipment_leg_tracking_policy(
  p_shipment_leg_id uuid,
  p_tracking_required boolean,
  p_allowed_sources text[],
  p_preferred_source text,
  p_fallback_order text[],
  p_freshness_tolerance_seconds integer,
  p_accuracy_tolerance_meters numeric,
  p_ping_interval_seconds integer,
  p_start_trigger text,
  p_end_trigger text,
  p_geofence_policy jsonb,
  p_customer_visible boolean,
  p_no_signal_escalation_seconds integer,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.shipment_leg_tracking_policies
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_leg app.shipment_legs;
  v_shipment app.shipment_orders;
  v_decision app.rbac_decision;
  v_policy app.shipment_leg_tracking_policies;
begin
  if p_start_trigger not in ('leg_dispatch', 'first_stop_arrival') then
    raise exception 'invalid_start_trigger: % is not a supported start trigger', p_start_trigger using errcode = 'check_violation';
  end if;
  if p_end_trigger not in ('last_stop_arrival', 'leg_complete') then
    raise exception 'invalid_end_trigger: % is not a supported end trigger', p_end_trigger using errcode = 'check_violation';
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

  insert into app.shipment_leg_tracking_policies (
    tenant_id, shipment_leg_id, tracking_required, allowed_sources, preferred_source, fallback_order,
    freshness_tolerance_seconds, accuracy_tolerance_meters, ping_interval_seconds, start_trigger, end_trigger,
    geofence_policy, customer_visible, no_signal_escalation_seconds, created_by
  ) values (
    v_shipment.tenant_id, p_shipment_leg_id, p_tracking_required, coalesce(p_allowed_sources, '{}'), p_preferred_source, coalesce(p_fallback_order, '{}'),
    p_freshness_tolerance_seconds, p_accuracy_tolerance_meters, p_ping_interval_seconds, p_start_trigger, p_end_trigger,
    p_geofence_policy, coalesce(p_customer_visible, false), p_no_signal_escalation_seconds, p_actor_label
  )
  on conflict (shipment_leg_id) do update set
    tracking_required = excluded.tracking_required,
    allowed_sources = excluded.allowed_sources,
    preferred_source = excluded.preferred_source,
    fallback_order = excluded.fallback_order,
    freshness_tolerance_seconds = excluded.freshness_tolerance_seconds,
    accuracy_tolerance_meters = excluded.accuracy_tolerance_meters,
    ping_interval_seconds = excluded.ping_interval_seconds,
    start_trigger = excluded.start_trigger,
    end_trigger = excluded.end_trigger,
    geofence_policy = excluded.geofence_policy,
    customer_visible = excluded.customer_visible,
    no_signal_escalation_seconds = excluded.no_signal_escalation_seconds
  returning * into v_policy;

  perform app.capture_audit_event(
    v_shipment.tenant_id, p_actor_auth_user_id, p_actor_label, 'upsert_shipment_leg_tracking_policy',
    'app.shipment_leg_tracking_policies', v_policy.id, 'success', null, null,
    jsonb_build_object('shipment_leg_id', p_shipment_leg_id, 'tracking_required', p_tracking_required, 'policy_version', v_policy.policy_version)
  );

  return v_policy;
end;
$$;

comment on function app.upsert_shipment_leg_tracking_policy is
  'ATW-225: one policy per leg (upsert on shipment_leg_id, policy_version incremented by the touch trigger on every real update). tracking_required=false requires empty allowed_sources/fallback_order and a null preferred_source (schema CHECK), the explicit "not tracking-required" state Prompt 225 SS24 requires.';

-- app.resolve_leg_tracking_policy -- read-only resolution: given the leg''s
-- own policy and its shipment-level resource assignment (OPS-172), which
-- sources are eligible right now, and which one the policy''s own fallback
-- order would pick.
create function app.resolve_leg_tracking_policy(
  p_shipment_leg_id uuid,
  p_actor_auth_user_id uuid
)
returns table (
  policy_id uuid,
  tracking_required boolean,
  tracking_entitled boolean,
  eligible_sources text[],
  resolved_source text,
  resolved_vehicle_master_id uuid,
  resolved_driver_master_id uuid,
  resolved_device_id uuid,
  blocked_reason text
)
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_leg app.shipment_legs;
  v_shipment app.shipment_orders;
  v_policy app.shipment_leg_tracking_policies;
  v_vehicle_master_id uuid;
  v_driver_master_id uuid;
  v_device_id uuid;
  v_eligible text[] := '{}';
  v_order text[];
  v_source text;
  v_resolved text;
begin
  select * into v_leg from app.shipment_legs where id = p_shipment_leg_id;
  if not found then
    raise exception 'leg_not_found: %', p_shipment_leg_id using errcode = 'no_data_found';
  end if;
  select * into v_shipment from app.shipment_orders where id = v_leg.shipment_order_id;

  if not app.can_access_record(p_actor_auth_user_id, v_shipment.tenant_id, v_shipment.owner_user_id, app.lead_record_scope_org_unit_ids(v_shipment.org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot access shipment order %', p_actor_auth_user_id, v_leg.shipment_order_id
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_policy from app.shipment_leg_tracking_policies where shipment_leg_id = p_shipment_leg_id;
  if not found then
    return query select null::uuid, null::boolean, app.is_shipment_tracking_entitled(v_shipment.tenant_id), '{}'::text[], null::text, null::uuid, null::uuid, null::uuid, 'policy_not_defined'::text;
    return;
  end if;

  select resource_id into v_vehicle_master_id from app.resource_assignments
    where shipment_order_id = v_leg.shipment_order_id and role = 'vehicle' and is_current and status = 'active';
  select resource_id into v_driver_master_id from app.resource_assignments
    where shipment_order_id = v_leg.shipment_order_id and role = 'driver' and is_current and status = 'active';

  if v_driver_master_id is not null and exists (
    select 1 from app.driver_operational_profiles where driver_master_id = v_driver_master_id and status = 'active' and mobile_tracking_consent
  ) then
    v_eligible := array_append(v_eligible, 'driver_mobile');
  end if;

  if v_vehicle_master_id is not null then
    select dva.device_id into v_device_id
    from app.vehicle_operational_profiles vop
    join app.device_vehicle_assignments dva on dva.vehicle_operational_profile_id = vop.id and dva.is_current
    join app.gps_devices d on d.id = dva.device_id and d.status = 'active'
    where vop.vehicle_master_id = v_vehicle_master_id and vop.status = 'active' and vop.direct_device_tracking_eligible
    limit 1;
    if v_device_id is not null then
      v_eligible := array_append(v_eligible, 'direct_device');
    end if;

    if exists (select 1 from app.vehicle_operational_profiles where vehicle_master_id = v_vehicle_master_id and status = 'active' and third_party_tracking_eligible)
      and exists (select 1 from app.provider_vehicle_mappings where vehicle_master_id = v_vehicle_master_id and status = 'active')
    then
      v_eligible := array_append(v_eligible, 'third_party_platform');
    end if;
  end if;

  v_order := case
    when coalesce(array_length(v_policy.fallback_order, 1), 0) > 0 then v_policy.fallback_order
    when v_policy.preferred_source is not null then array[v_policy.preferred_source]
    else v_policy.allowed_sources
  end;

  foreach v_source in array coalesce(v_order, '{}') loop
    if v_source = any (v_eligible) then
      v_resolved := v_source;
      exit;
    end if;
  end loop;

  return query select
    v_policy.id, v_policy.tracking_required, app.is_shipment_tracking_entitled(v_shipment.tenant_id), v_eligible, v_resolved,
    case when v_resolved = 'direct_device' or v_resolved = 'third_party_platform' then v_vehicle_master_id end,
    case when v_resolved = 'driver_mobile' then v_driver_master_id end,
    case when v_resolved = 'direct_device' then v_device_id end,
    case
      when not v_policy.tracking_required then 'not_required'
      when v_resolved is not null then null
      when coalesce(array_length(v_eligible, 1), 0) = 0 then 'no_eligible_source'
      else 'no_source_in_fallback_order'
    end;
end;
$$;

comment on function app.resolve_leg_tracking_policy is
  'ATW-225: read-only resolution over the leg''s own policy and its shipment-level app.resource_assignments (OPS-172) occupants -- eligible_sources reflects real ATW-223 capability/consent/device/provider data; tracking_entitled is disclosed alongside, never folded into blocked_reason, since entitlement does not gate this migration''s own orchestration mechanics.';

-- app.start_leg_tracking_session -- the first session on a leg.
create function app.start_leg_tracking_session(
  p_shipment_leg_id uuid,
  p_source_type text,
  p_resource_kind text,
  p_resource_master_id uuid,
  p_device_id uuid,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.shipment_leg_tracking_sessions
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_leg app.shipment_legs;
  v_shipment app.shipment_orders;
  v_decision app.rbac_decision;
  v_policy app.shipment_leg_tracking_policies;
  v_existing app.shipment_leg_tracking_sessions;
  v_session app.shipment_leg_tracking_sessions;
begin
  if p_source_type not in ('driver_mobile', 'direct_device', 'third_party_platform') then
    raise exception 'invalid_source_type: % is not a supported tracking source', p_source_type using errcode = 'check_violation';
  end if;
  if p_resource_kind not in ('vehicle', 'driver') then
    raise exception 'invalid_resource_kind: % is not a supported resource kind', p_resource_kind using errcode = 'check_violation';
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

  select * into v_policy from app.shipment_leg_tracking_policies where shipment_leg_id = p_shipment_leg_id;
  if not found then
    raise exception 'policy_not_defined: leg % has no tracking policy defined yet', p_shipment_leg_id using errcode = 'check_violation';
  end if;
  if not v_policy.tracking_required then
    raise exception 'tracking_not_required: leg % is explicitly not tracking-required', p_shipment_leg_id using errcode = 'check_violation';
  end if;
  if not (p_source_type = any (v_policy.allowed_sources)) then
    raise exception 'source_not_allowed: % is not among the policy''s own allowed_sources for leg %', p_source_type, p_shipment_leg_id using errcode = 'check_violation';
  end if;

  select * into v_existing from app.shipment_leg_tracking_sessions where shipment_leg_id = p_shipment_leg_id and is_current;
  if found then
    raise exception 'session_already_active: leg % already has an active tracking session -- use handoff instead', p_shipment_leg_id using errcode = 'check_violation';
  end if;

  if not app.check_leg_tracking_source_eligible(p_shipment_leg_id, p_source_type, p_resource_kind, p_resource_master_id, p_device_id) then
    raise exception 'source_not_eligible: % (%) is not currently eligible to track leg %', p_source_type, p_resource_master_id, p_shipment_leg_id
      using errcode = 'check_violation';
  end if;

  insert into app.shipment_leg_tracking_sessions (
    tenant_id, shipment_leg_id, policy_id, source_type, resource_kind, resource_master_id, device_id, tracking_entitled_at_start, created_by
  ) values (
    v_shipment.tenant_id, p_shipment_leg_id, v_policy.id, p_source_type, p_resource_kind, p_resource_master_id, p_device_id,
    app.is_shipment_tracking_entitled(v_shipment.tenant_id), p_actor_label
  )
  returning * into v_session;

  perform app.capture_audit_event(
    v_shipment.tenant_id, p_actor_auth_user_id, p_actor_label, 'start_leg_tracking_session',
    'app.shipment_leg_tracking_sessions', v_session.id, 'success', null, null,
    jsonb_build_object('shipment_leg_id', p_shipment_leg_id, 'source_type', p_source_type, 'resource_master_id', p_resource_master_id)
  );

  return v_session;
end;
$$;

comment on function app.start_leg_tracking_session is
  'ATW-225: requires a defined, tracking_required policy naming this source among allowed_sources, no already-active session (use handoff instead), and real eligibility (app.check_leg_tracking_source_eligible). Entitlement is snapshotted, never blocking.';

-- app.handoff_leg_tracking_session -- supersedes the current session.
-- Update-before-insert ordering applied correctly from the start (ATW-224's
-- own header discloses the defect this avoids).
create function app.handoff_leg_tracking_session(
  p_shipment_leg_id uuid,
  p_source_type text,
  p_resource_kind text,
  p_resource_master_id uuid,
  p_device_id uuid,
  p_handoff_reason text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.shipment_leg_tracking_sessions
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_leg app.shipment_legs;
  v_shipment app.shipment_orders;
  v_decision app.rbac_decision;
  v_policy app.shipment_leg_tracking_policies;
  v_prior app.shipment_leg_tracking_sessions;
  v_session app.shipment_leg_tracking_sessions;
begin
  if p_source_type not in ('driver_mobile', 'direct_device', 'third_party_platform') then
    raise exception 'invalid_source_type: % is not a supported tracking source', p_source_type using errcode = 'check_violation';
  end if;
  if p_resource_kind not in ('vehicle', 'driver') then
    raise exception 'invalid_resource_kind: % is not a supported resource kind', p_resource_kind using errcode = 'check_violation';
  end if;
  if p_handoff_reason is null or length(trim(p_handoff_reason)) = 0 then
    raise exception 'handoff_reason_required: a non-empty reason is required to hand off a tracking session' using errcode = 'check_violation';
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

  select * into v_policy from app.shipment_leg_tracking_policies where shipment_leg_id = p_shipment_leg_id;
  if not found or not v_policy.tracking_required then
    raise exception 'tracking_not_required: leg % has no tracking-required policy to hand off', p_shipment_leg_id using errcode = 'check_violation';
  end if;
  if not (p_source_type = any (v_policy.allowed_sources)) then
    raise exception 'source_not_allowed: % is not among the policy''s own allowed_sources for leg %', p_source_type, p_shipment_leg_id using errcode = 'check_violation';
  end if;

  select * into v_prior from app.shipment_leg_tracking_sessions where shipment_leg_id = p_shipment_leg_id and is_current;
  if not found then
    raise exception 'no_active_session: leg % has no active tracking session to hand off -- use start instead', p_shipment_leg_id using errcode = 'check_violation';
  end if;

  if not app.check_leg_tracking_source_eligible(p_shipment_leg_id, p_source_type, p_resource_kind, p_resource_master_id, p_device_id) then
    raise exception 'source_not_eligible: % (%) is not currently eligible to track leg %', p_source_type, p_resource_master_id, p_shipment_leg_id
      using errcode = 'check_violation';
  end if;

  update app.shipment_leg_tracking_sessions set is_current = false, status = 'ended', ended_at = now(), end_reason = 'handoff' where id = v_prior.id;

  insert into app.shipment_leg_tracking_sessions (
    tenant_id, shipment_leg_id, policy_id, source_type, resource_kind, resource_master_id, device_id, tracking_entitled_at_start, created_by
  ) values (
    v_shipment.tenant_id, p_shipment_leg_id, v_policy.id, p_source_type, p_resource_kind, p_resource_master_id, p_device_id,
    app.is_shipment_tracking_entitled(v_shipment.tenant_id), p_actor_label
  )
  returning * into v_session;

  update app.shipment_leg_tracking_sessions set superseded_by_id = v_session.id where id = v_prior.id;

  perform app.capture_audit_event(
    v_shipment.tenant_id, p_actor_auth_user_id, p_actor_label, 'handoff_leg_tracking_session',
    'app.shipment_leg_tracking_sessions', v_session.id, 'success', null, null,
    jsonb_build_object('shipment_leg_id', p_shipment_leg_id, 'from_session_id', v_prior.id, 'to_source_type', p_source_type, 'reason', p_handoff_reason)
  );

  return v_session;
end;
$$;

comment on function app.handoff_leg_tracking_session is
  'ATW-225: supersedes the current session (end_reason=handoff), is_current/superseded_by_id history preserved. Update-before-insert ordering avoids transiently double-booking shipment_leg_tracking_sessions_current_leg_unique (ATW-224''s own disclosed defect class, applied correctly here from the start).';

-- app.end_leg_tracking_session -- normal (OPS:Edit) or forced-override
-- (OPS:Override, mandatory reason) termination.
create function app.end_leg_tracking_session(
  p_shipment_leg_id uuid,
  p_end_reason text,
  p_reason_note text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.shipment_leg_tracking_sessions
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_leg app.shipment_legs;
  v_shipment app.shipment_orders;
  v_decision app.rbac_decision;
  v_session app.shipment_leg_tracking_sessions;
begin
  if p_end_reason not in ('leg_completed', 'manual_stop', 'unauthorized_override') then
    raise exception 'invalid_end_reason: % is not a supported end reason for a direct end call', p_end_reason using errcode = 'check_violation';
  end if;
  if p_end_reason = 'manual_stop' and (p_reason_note is null or length(trim(p_reason_note)) = 0) then
    raise exception 'end_reason_required: a non-empty reason is required to manually stop a tracking session' using errcode = 'check_violation';
  end if;
  if p_end_reason = 'unauthorized_override' and (p_reason_note is null or length(trim(p_reason_note)) = 0) then
    raise exception 'override_reason_required: a non-empty reason is required to force-end a tracking session' using errcode = 'check_violation';
  end if;

  select * into v_leg from app.shipment_legs where id = p_shipment_leg_id;
  if not found then
    raise exception 'leg_not_found: %', p_shipment_leg_id using errcode = 'no_data_found';
  end if;
  select * into v_shipment from app.shipment_orders where id = v_leg.shipment_order_id;

  if p_end_reason = 'unauthorized_override' then
    v_decision := app.evaluate_permission(p_actor_auth_user_id, v_shipment.tenant_id, 'OPS', 'Override');
    if not v_decision.allowed then
      raise exception 'insufficient_authority: identity % lacks OPS:Override (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_shipment.tenant_id
        using errcode = 'insufficient_privilege';
    end if;
  else
    v_decision := app.evaluate_permission(p_actor_auth_user_id, v_shipment.tenant_id, 'OPS', 'Edit');
    if not v_decision.allowed then
      raise exception 'insufficient_authority: identity % lacks OPS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_shipment.tenant_id
        using errcode = 'insufficient_privilege';
    end if;
  end if;
  if not app.can_access_record(p_actor_auth_user_id, v_shipment.tenant_id, v_shipment.owner_user_id, app.lead_record_scope_org_unit_ids(v_shipment.org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot access shipment order %', p_actor_auth_user_id, v_leg.shipment_order_id
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_session from app.shipment_leg_tracking_sessions where shipment_leg_id = p_shipment_leg_id and is_current;
  if not found then
    raise exception 'no_active_session: leg % has no active tracking session to end', p_shipment_leg_id using errcode = 'check_violation';
  end if;

  update app.shipment_leg_tracking_sessions
  set is_current = false, status = 'ended', ended_at = now(), end_reason = p_end_reason
  where id = v_session.id
  returning * into v_session;

  perform app.capture_audit_event(
    v_shipment.tenant_id, p_actor_auth_user_id, p_actor_label, 'end_leg_tracking_session',
    'app.shipment_leg_tracking_sessions', v_session.id, 'success', p_reason_note, null,
    jsonb_build_object('shipment_leg_id', p_shipment_leg_id, 'end_reason', p_end_reason)
  );

  return v_session;
end;
$$;

comment on function app.end_leg_tracking_session is
  'ATW-225: leg_completed/manual_stop require OPS:Edit; unauthorized_override requires OPS:Override plus a mandatory reason note -- a genuinely distinct, gated force-end path, not merely a label (Prompt 225 SS23 "unauthorized override").';

-- app.evaluate_leg_no_signal_escalation -- orchestration-level staleness
-- detector (this migration's own header). Real, bounded, provable without
-- live telemetry.
create function app.evaluate_leg_no_signal_escalation(
  p_shipment_leg_id uuid,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.shipment_leg_tracking_sessions
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_leg app.shipment_legs;
  v_shipment app.shipment_orders;
  v_decision app.rbac_decision;
  v_policy app.shipment_leg_tracking_policies;
  v_session app.shipment_leg_tracking_sessions;
begin
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

  select * into v_session from app.shipment_leg_tracking_sessions where shipment_leg_id = p_shipment_leg_id and is_current;
  if not found then
    return null;
  end if;

  select * into v_policy from app.shipment_leg_tracking_policies where id = v_session.policy_id;
  if v_policy.no_signal_escalation_seconds is null then
    return v_session;
  end if;
  if now() - v_session.started_at < (v_policy.no_signal_escalation_seconds || ' seconds')::interval then
    return v_session;
  end if;

  update app.shipment_leg_tracking_sessions
  set is_current = false, status = 'ended', ended_at = now(), end_reason = 'stale_source'
  where id = v_session.id
  returning * into v_session;

  perform app.report_exception(
    v_leg.shipment_order_id, null, 'incident', 'medium',
    format('Tracking session %s for leg %s exceeded its own no-signal escalation threshold (%s seconds) without ending or handoff', v_session.id, p_shipment_leg_id, v_policy.no_signal_escalation_seconds),
    'system', 'leg-no-signal:' || p_shipment_leg_id::text, p_actor_auth_user_id, p_actor_label
  );

  perform app.capture_audit_event(
    v_shipment.tenant_id, p_actor_auth_user_id, p_actor_label, 'evaluate_leg_no_signal_escalation',
    'app.shipment_leg_tracking_sessions', v_session.id, 'success', null, null,
    jsonb_build_object('shipment_leg_id', p_shipment_leg_id, 'no_signal_escalation_seconds', v_policy.no_signal_escalation_seconds)
  );

  return v_session;
end;
$$;

comment on function app.evaluate_leg_no_signal_escalation is
  'ATW-225: compares a still-active session''s own started_at against the policy''s own no_signal_escalation_seconds -- an orchestration-level staleness check (session left open too long), never a raw GPS-ping-timeout check (ATW-226F''s own future scope, no live telemetry exists to time out). A genuinely stale session is ended (end_reason=stale_source) and a real app.operational_exceptions row is raised via app.report_exception (OPS-174), deduplicated on correlation_key. Returns null when no current session exists, unchanged when nothing is stale.';

-- app.get_shipment_leg_tracking_sessions -- the one read path for session
-- history, security invoker (relies on the caller's own RLS).
create function app.get_shipment_leg_tracking_sessions(p_shipment_leg_id uuid)
returns setof app.shipment_leg_tracking_sessions
language sql
stable
security invoker
set search_path = app, pg_temp
as $$
  select * from app.shipment_leg_tracking_sessions where shipment_leg_id = p_shipment_leg_id order by started_at asc;
$$;

comment on function app.get_shipment_leg_tracking_sessions is
  'ATW-225: security invoker (relies on the caller''s own RLS on app.shipment_leg_tracking_sessions) -- plain chronological session history for one leg.';

alter table app.shipment_leg_tracking_policies enable row level security;
alter table app.shipment_leg_tracking_sessions enable row level security;

create policy shipment_leg_tracking_policies_select_scoped on app.shipment_leg_tracking_policies
  for select to authenticated
  using (
    exists (
      select 1 from app.shipment_legs sl
      join app.shipment_orders so on so.id = sl.shipment_order_id
      where sl.id = shipment_leg_tracking_policies.shipment_leg_id
        and app.can_access_record((select auth.uid()), so.tenant_id, so.owner_user_id, app.lead_record_scope_org_unit_ids(so.org_unit_id), null)
    )
  );

create policy shipment_leg_tracking_sessions_select_scoped on app.shipment_leg_tracking_sessions
  for select to authenticated
  using (
    exists (
      select 1 from app.shipment_legs sl
      join app.shipment_orders so on so.id = sl.shipment_order_id
      where sl.id = shipment_leg_tracking_sessions.shipment_leg_id
        and app.can_access_record((select auth.uid()), so.tenant_id, so.owner_user_id, app.lead_record_scope_org_unit_ids(so.org_unit_id), null)
    )
  );

revoke execute on all functions in schema app from public;

grant select on app.shipment_leg_tracking_policies to authenticated, service_role;
grant insert, update, delete on app.shipment_leg_tracking_policies to service_role;
grant select on app.shipment_leg_tracking_sessions to authenticated, service_role;
grant insert, update, delete on app.shipment_leg_tracking_sessions to service_role;

grant execute on function app.check_leg_tracking_source_eligible(uuid, text, text, uuid, uuid) to authenticated, service_role;
grant execute on function app.upsert_shipment_leg_tracking_policy(uuid, boolean, text[], text, text[], integer, numeric, integer, text, text, jsonb, boolean, integer, uuid, text) to authenticated, service_role;
grant execute on function app.resolve_leg_tracking_policy(uuid, uuid) to authenticated, service_role;
grant execute on function app.start_leg_tracking_session(uuid, text, text, uuid, uuid, uuid, text) to authenticated, service_role;
grant execute on function app.handoff_leg_tracking_session(uuid, text, text, uuid, uuid, text, uuid, text) to authenticated, service_role;
grant execute on function app.end_leg_tracking_session(uuid, text, text, uuid, text) to authenticated, service_role;
grant execute on function app.evaluate_leg_no_signal_escalation(uuid, uuid, text) to authenticated, service_role;
grant execute on function app.get_shipment_leg_tracking_sessions(uuid) to authenticated, service_role;
