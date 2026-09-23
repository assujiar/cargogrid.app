-- CG-AUDIT-2026-09-02 E5 (untracked sub-claim A, self-caught from the audit's own E5
-- paragraph, absent from the backlog table's condensed 2-line summary): "Driver licence
-- expiry and vehicle serviceability are checked at neither assignment nor dispatch."
--
-- app.evaluate_dispatch_readiness (20260727160000_create_operations_basic_dispatch.sql)
-- already discloses "a per-mode required-role matrix is explicit Phase 5 (Advanced TMS)
-- scope, not built here" -- that is a DIFFERENT, still-deferred check (does this mode
-- have the RIGHT ROLE TYPES assigned at all). Whether an ALREADY-assigned driver/vehicle
-- is itself fit to run (unexpired licence, active/serviceable status) is a separate
-- question Phase 5 has since shipped the data for: app.driver_operational_profiles.
-- license_expiry_date and app.vehicle_operational_profiles.status
-- (20260729310000_create_advanced_tms_fleet_driver_device.sql), joinable via the
-- existing app.resource_assignments.resource_id -- and nobody wired it into the
-- dispatch gate. This migration is exactly that wiring: two new blocker checks reusing
-- already-live data, no new table, no new RPC signature, no invented business rule --
-- "active" is this codebase's own established status vocabulary (mirrors
-- app.finance_accounts.status <> 'active' and every sibling check), and an expiry date
-- in the past is unambiguous.
--
-- Fail-open on missing data, by design, matching this same migration file's own
-- already-disclosed posture for the analogous case ("required-document readiness is
-- explicitly NOT_RUN -- no Document Requirement capability exists yet"): a tenant that
-- has not enrolled ATW-223 driver/vehicle operational profiles at all sees no new
-- blocker, exactly as before this migration. A blocker fires only on POSITIVE evidence
-- (a real profile row with an expiry date in the past, or a real profile row whose
-- status is not 'active') -- never on the absence of a profile.
--
-- Base definition for this CREATE OR REPLACE is app.evaluate_dispatch_readiness's own
-- and only definition (20260727160000, verified via a repo-wide grep for a later
-- redefinition -- none exists, unlike C3's app.create_finance_tax_rule_draft case
-- earlier this session), so no security-mode/search_path drift risk applies here.
create or replace function app.evaluate_dispatch_readiness(p_shipment_order_id uuid)
returns table (is_ready boolean, blockers jsonb)
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_shipment app.shipment_orders;
  v_blockers jsonb := '[]'::jsonb;
begin
  select * into v_shipment from app.shipment_orders where id = p_shipment_order_id;
  if not found then
    raise exception 'shipment_order_not_found: %', p_shipment_order_id using errcode = 'no_data_found';
  end if;

  if v_shipment.status <> 'assigned' then
    v_blockers := v_blockers || jsonb_build_array(jsonb_build_object('code', 'wrong_status', 'detail', v_shipment.status));
  end if;

  if not exists (
    select 1 from app.resource_assignments ra
    where ra.shipment_order_id = p_shipment_order_id and ra.is_current and ra.status = 'active'
  ) then
    v_blockers := v_blockers || jsonb_build_array(jsonb_build_object('code', 'no_active_assignment', 'detail', null));
  end if;

  if exists (
    select 1
    from app.resource_assignments ra
    join app.driver_operational_profiles dp on dp.driver_master_id = ra.resource_id
    where ra.shipment_order_id = p_shipment_order_id
      and ra.role = 'driver' and ra.is_current and ra.status = 'active'
      and dp.license_expiry_date is not null
      and dp.license_expiry_date < current_date
  ) then
    v_blockers := v_blockers || jsonb_build_array(jsonb_build_object('code', 'driver_license_expired', 'detail', null));
  end if;

  if exists (
    select 1
    from app.resource_assignments ra
    join app.vehicle_operational_profiles vp on vp.vehicle_master_id = ra.resource_id
    where ra.shipment_order_id = p_shipment_order_id
      and ra.role = 'vehicle' and ra.is_current and ra.status = 'active'
      and vp.status <> 'active'
  ) then
    v_blockers := v_blockers || jsonb_build_array(jsonb_build_object('code', 'vehicle_not_serviceable', 'detail', null));
  end if;

  if exists (
    select 1 from app.operational_exceptions oe
    where oe.shipment_order_id = p_shipment_order_id and oe.status in ('open', 'acknowledged', 'reopened')
  ) then
    v_blockers := v_blockers || jsonb_build_array(jsonb_build_object('code', 'blocking_exception', 'detail', null));
  end if;

  if v_shipment.planned_pickup_at is null then
    v_blockers := v_blockers || jsonb_build_array(jsonb_build_object('code', 'missing_schedule', 'detail', null));
  end if;

  return query select (jsonb_array_length(v_blockers) = 0), v_blockers;
end;
$$;

comment on function app.evaluate_dispatch_readiness is
  'OPS-175: the basic-MVP readiness checklist (status=assigned, an active resource assignment, no blocking exception, a planned pickup time), extended by CG-AUDIT-2026-09-02 E5 with two data-backed checks: an assigned driver whose app.driver_operational_profiles.license_expiry_date has passed (driver_license_expired), and an assigned vehicle whose app.vehicle_operational_profiles.status is not active (vehicle_not_serviceable) -- both fail-open when no operational profile is enrolled for the assigned resource, matching this function''s own pre-existing NOT_RUN posture for required-document readiness. A per-mode required-role matrix (land requires vehicle+driver, sea requires a vendor) remains the explicit, still-deferred Phase 5 boundary this function''s original comment already disclosed -- unrelated to, and not widened by, this migration. Shared by every other function/view in this migration, defined exactly once.';
