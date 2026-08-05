-- CG-S10-ATW-031 (post-Prompt-248 codebase audit — closes `ISS-2026-028`).
--
-- `app.record_gps_device_installation` (`ATW-226B`) exists specifically to make GPS
-- device installation evidence-mandatory: a malware-scan-clean evidence file that
-- genuinely belongs to the device, plus a technician label, captured against the
-- device's own vehicle assignment. But nothing forced anyone through it.
-- `app.transition_gps_device_status` (`ATW-223`) accepted `assigned -> installed`
-- directly with no evidence of any kind, and was granted to `authenticated`. The
-- `operations/fleet` workspace UI's own status dropdown called exactly that, so a staff
-- user holding ordinary `OPS:Edit` could mark any device installed with no evidence file
-- and no technician ever recorded.
--
-- ===========================================================================
-- Why the repair is in the database, not the UI
-- ===========================================================================
--
-- `ISS-2026-028` describes this as a UI gap, and it was found by reading the UI. Fixing
-- the UI alone would leave the hole open: `app.transition_gps_device_status` is reachable
-- by ANY caller holding `OPS:Edit`, not just the workspace. Per `AGENTS.md` ("UI
-- visibility is not authorization. Enforce ... server-side"), the gate belongs here. The
-- UI is corrected in the same checkpoint, but as the second line of defence.
--
-- ===========================================================================
-- Mechanism: the grant boundary, not a runtime flag
-- ===========================================================================
--
-- `app.transition_gps_device_status` keeps its full, unmodified status machine and
-- becomes a shared INTERNAL core: its `authenticated` and `service_role` EXECUTE grants
-- are revoked. This is the same pattern `ATW-021` already established for
-- `app.execute_label_print_job` ("Deliberately NOT granted to authenticated, design
-- note 3") — a shared mutation core reachable only through the entry points that own its
-- preconditions. `app.record_gps_device_installation` is `SECURITY DEFINER` and owned by
-- the same role, so it continues to call the core unchanged; the grant revocation does
-- not affect it.
--
-- A new entry point, `app.request_gps_device_status_transition`, carries the
-- `authenticated`/`service_role` grant instead. It refuses `p_to_status = 'installed'`
-- outright with `installation_evidence_required`, and delegates every other transition to
-- the core unchanged.
--
-- This is deliberately enforced by the grant model rather than by a runtime marker (a
-- `set_config`/`current_setting` "I am the trusted caller" flag) or by an
-- installation-row-must-already-exist precondition. A flag is only as strong as the
-- caller's inability to set it. A revoked grant is enforced by Postgres itself, needs no
-- ordering discipline inside `app.record_gps_device_installation`, and — unlike a
-- row-existence precondition — does not force every unrelated test fixture that merely
-- needs a device in `installed` state to first stand up a whole document-type
-- configuration and evidence-file upload.
--
-- Net effect: the ONLY way for a client to reach `installed` is
-- `app.record_gps_device_installation`, which validates the evidence file (exists,
-- belongs to this device and tenant, malware scan `clean`) and the technician label
-- before it ever touches device status.
--
-- Every other transition in `ATW-223`'s status machine is unchanged and still reachable.
--
-- Contract note: `server/mutations/fleet-driver-device.ts`'s `transitionGpsDeviceStatus`
-- is repointed to `app.request_gps_device_status_transition` in this same checkpoint. The
-- old function is NOT dropped and its signature is NOT changed, so this is an additive,
-- expand-and-contract-safe change rather than a breaking rename.
--
-- Per `ERR-2026-004`: this migration carries its own explicit `revoke execute on all
-- functions in schema app from public` before its final grants.

create or replace function app.request_gps_device_status_transition(
  p_device_id uuid,
  p_to_status text,
  p_expected_version integer,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.gps_devices
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_device app.gps_devices;
begin
  -- ATW-031 (ISS-2026-028): the one transition this generic entry point must never
  -- perform. Marking a device installed is evidence-mandatory and belongs exclusively to
  -- app.record_gps_device_installation (ATW-226B), which captures a malware-scan-clean
  -- evidence file belonging to this device plus a technician label first. Before this
  -- gate, any caller holding ordinary OPS:Edit could reach 'installed' with none of that.
  if p_to_status = 'installed' then
    raise exception 'installation_evidence_required: device % cannot be marked installed through the generic status transition -- use app.record_gps_device_installation, which captures the mandatory evidence file and technician label', p_device_id
      using errcode = 'check_violation';
  end if;

  select * into v_device from app.transition_gps_device_status(
    p_device_id, p_to_status, p_expected_version, p_actor_auth_user_id, p_actor_label
  );
  return v_device;
end;
$$;

comment on function app.request_gps_device_status_transition is
  'ATW-031 (ISS-2026-028): the ONLY GPS device status-transition entry point granted to authenticated. Refuses p_to_status = ''installed'' (installation_evidence_required) -- that transition is evidence-mandatory and belongs exclusively to app.record_gps_device_installation (ATW-226B). Every other transition delegates to app.transition_gps_device_status (ATW-223) with its status machine, authority gate and optimistic-concurrency check completely unchanged.';

comment on function app.transition_gps_device_status is
  'ATW-223, re-scoped at ATW-031 (ISS-2026-028): the shared INTERNAL status-machine core. No longer granted to authenticated or service_role -- clients go through app.request_gps_device_status_transition, which refuses the evidence-mandatory ''installed'' transition. Still called directly, unchanged, by app.record_gps_device_installation (SECURITY DEFINER, same owner, so unaffected by the grant revocation), which is what makes that RPC the only route to ''installed''. Deliberately NOT granted to authenticated -- the same shared-mutation-core pattern ATW-021 established for app.execute_label_print_job.';

revoke execute on all functions in schema app from public;

-- ATW-031: the actual enforcement. Revoking these two grants is what closes the bypass;
-- app.record_gps_device_installation is SECURITY DEFINER and owned by the same role, so
-- it keeps working without any grant of its own.
revoke execute on function app.transition_gps_device_status(uuid, text, integer, uuid, text) from authenticated;
revoke execute on function app.transition_gps_device_status(uuid, text, integer, uuid, text) from service_role;

grant execute on function app.request_gps_device_status_transition(uuid, text, integer, uuid, text) to authenticated, service_role;
