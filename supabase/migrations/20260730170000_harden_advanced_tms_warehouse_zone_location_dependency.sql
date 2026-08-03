-- Advanced TMS/WMS hardening (inserted alongside `CG-S10-ATW-011A`, no source
-- prompt number -- a real, currently-active defect found by this session's own
-- comprehensive read-only gap audit of Phase 5's `VERIFIED` build output).
--
-- `ATW-229`'s own migration header (design note 7,
-- `20260730140000_create_advanced_tms_warehouse_zone.sql`) disclosed this exact
-- obligation up front: "a zone's own deactivation does NOT check for stock/task
-- dependencies... since no bin/inventory/task table exists yet at this checkpoint...
-- Prompt 230 (or whichever future capability first adds a real bin/inventory table)
-- is the one obligated to wire a real check before it lets a zone holding inventory
-- deactivate." `ATW-230` then built `app.warehouse_locations` (with an optional
-- `zone_id` FK to `app.warehouse_zones`) but never discharged that obligation --
-- `app.set_warehouse_zone_status` still lets a zone deactivate while `draft`/`active`
-- locations reference it. This migration closes that gap, plus the identical,
-- previously-unnoticed sibling gap one level up: `app.set_warehouse_status` blocks
-- deactivation on active/on-hold zones but never checks locations created directly
-- under the warehouse with no `zone_id` at all (`ATW-230`'s own design note 4: "some
-- locations legitimately have no zone context," e.g. a root-level dock).
--
-- Both widened functions reuse the identical `draft`/`active` blocking-status pair
-- `ATW-230`'s own `app.set_warehouse_location_status` already established for the
-- symmetric case (a location cannot deactivate while a `draft`/`active` child
-- location exists under it) -- the same real, checkable dependency shape, not a new
-- convention.
--
-- Per `ERR-2026-004` (docs/runtime/ERROR_LEDGER.md): this migration carries its own
-- explicit `REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA app FROM PUBLIC` statement
-- before its final grants.

create or replace function app.set_warehouse_zone_status(
  p_zone_id uuid,
  p_new_status text,
  p_reason text,
  p_expected_version integer,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.warehouse_zones
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_zone app.warehouse_zones;
  v_warehouse app.warehouses;
  v_active_location_count integer;
begin
  if p_new_status not in ('active', 'inactive', 'on_hold') then
    raise exception 'invalid_status: % is not a valid zone status', p_new_status using errcode = 'check_violation';
  end if;

  select * into v_zone from app.warehouse_zones where id = p_zone_id;
  if not found then
    raise exception 'zone_not_found: %', p_zone_id using errcode = 'no_data_found';
  end if;
  select * into v_warehouse from app.warehouses where id = v_zone.warehouse_id;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_zone.tenant_id, 'OPS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_zone.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.can_access_record(p_actor_auth_user_id, v_zone.tenant_id, null, app.lead_record_scope_org_unit_ids(v_warehouse.company_org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot edit zone %', p_actor_auth_user_id, p_zone_id using errcode = 'insufficient_privilege';
  end if;

  if v_zone.record_version <> p_expected_version then
    raise exception 'stale_version: zone % expected version % but found %', p_zone_id, p_expected_version, v_zone.record_version
      using errcode = 'check_violation';
  end if;
  if v_zone.status = p_new_status then
    return v_zone;
  end if;
  if p_new_status in ('inactive', 'on_hold') and (p_reason is null or length(trim(p_reason)) = 0) then
    raise exception 'reason_required: a non-empty reason is required to set a zone to %', p_new_status using errcode = 'check_violation';
  end if;

  if p_new_status = 'inactive' then
    select count(*) into v_active_location_count
      from app.warehouse_locations where zone_id = p_zone_id and status in ('draft', 'active');
    if v_active_location_count > 0 then
      raise exception 'zone_has_active_locations: % cannot be deactivated while % draft/active location(s) exist under it', p_zone_id, v_active_location_count
        using errcode = 'check_violation';
    end if;
  end if;

  update app.warehouse_zones set status = p_new_status where id = p_zone_id returning * into v_zone;

  perform app.capture_audit_event(
    v_zone.tenant_id, p_actor_auth_user_id, p_actor_label, 'set_warehouse_zone_status',
    'app.warehouse_zones', v_zone.id, 'success', p_reason, null, jsonb_build_object('new_status', p_new_status)
  );

  return v_zone;
end;
$$;

comment on function app.set_warehouse_zone_status is
  'ATW-229/widened this checkpoint: a zone cannot deactivate while any draft/active app.warehouse_locations row still references it (zone_id) -- the real dependency check ATW-229''s own design note 7 disclosed as deferred until a real bin/location table existed (ATW-230). on_hold remains unguarded by this check (a temporary hold, not a permanent deactivation).';

create or replace function app.set_warehouse_status(
  p_warehouse_id uuid,
  p_new_status text,
  p_reason text,
  p_expected_version integer,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.warehouses
language plpgsql
security definer
set search_path = app, public, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_warehouse app.warehouses;
  v_active_zone_count integer;
  v_active_location_count integer;
begin
  if p_new_status not in ('active', 'inactive') then
    raise exception 'invalid_status: % is not a valid warehouse status', p_new_status using errcode = 'check_violation';
  end if;

  select * into v_warehouse from app.warehouses where id = p_warehouse_id;
  if not found then
    raise exception 'warehouse_not_found: %', p_warehouse_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_warehouse.tenant_id, 'OPS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_warehouse.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.can_access_record(p_actor_auth_user_id, v_warehouse.tenant_id, null, app.lead_record_scope_org_unit_ids(v_warehouse.company_org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot edit warehouse %', p_actor_auth_user_id, p_warehouse_id using errcode = 'insufficient_privilege';
  end if;

  if v_warehouse.record_version <> p_expected_version then
    raise exception 'stale_version: warehouse % expected version % but found %', p_warehouse_id, p_expected_version, v_warehouse.record_version
      using errcode = 'check_violation';
  end if;
  if v_warehouse.status = p_new_status then
    return v_warehouse;
  end if;

  if p_new_status = 'inactive' then
    if p_reason is null or length(trim(p_reason)) = 0 then
      raise exception 'reason_required: a non-empty reason is required to deactivate a warehouse' using errcode = 'check_violation';
    end if;
    select count(*) into v_active_zone_count from app.warehouse_zones where warehouse_id = p_warehouse_id and status in ('active', 'on_hold');
    if v_active_zone_count > 0 then
      raise exception 'warehouse_has_active_zones: % cannot be deactivated while % active/on-hold zone(s) exist', p_warehouse_id, v_active_zone_count
        using errcode = 'check_violation';
    end if;
    select count(*) into v_active_location_count
      from app.warehouse_locations where warehouse_id = p_warehouse_id and status in ('draft', 'active');
    if v_active_location_count > 0 then
      raise exception 'warehouse_has_active_locations: % cannot be deactivated while % draft/active location(s) exist (including zoneless root-level locations)', p_warehouse_id, v_active_location_count
        using errcode = 'check_violation';
    end if;
  end if;

  update app.warehouses set status = p_new_status where id = p_warehouse_id returning * into v_warehouse;

  perform app.capture_audit_event(
    v_warehouse.tenant_id, p_actor_auth_user_id, p_actor_label, 'set_warehouse_status',
    'app.warehouses', v_warehouse.id, 'success', p_reason, null, jsonb_build_object('new_status', p_new_status)
  );

  return v_warehouse;
end;
$$;

comment on function app.set_warehouse_status is
  'ATW-229/widened this checkpoint: in addition to the pre-existing active/on-hold zone check, a warehouse cannot deactivate while any draft/active app.warehouse_locations row exists under it directly (zone_id is optional -- ATW-230''s own design note 4 -- so this check is independent of, not redundant with, the zone check above).';

-- Per ERR-2026-004: explicit, directly-provable revoke of PostgreSQL's PUBLIC-execute
-- default, the standing per-migration convention since PLT-118, re-applied here even
-- though this migration widens (not creates) functions -- CREATE OR REPLACE does not
-- reset a function's own grants, but this statement is cheap, idempotent, and keeps
-- the convention directly provable per-migration rather than relying on a prior
-- migration's own grant surviving unmodified.
revoke execute on all functions in schema app from public;

grant execute on function app.set_warehouse_zone_status(uuid, text, text, integer, uuid, text) to authenticated, service_role;
grant execute on function app.set_warehouse_status(uuid, text, text, integer, uuid, text) to authenticated, service_role;
