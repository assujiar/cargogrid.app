-- CG-AUDIT-2026-09-02 O1-query-layer remediation -- cluster 4 (telematics-tracking)
-- batch 2 (FINAL batch of cluster 4). Continues the same Design->Verify->Fix
-- adversarial pipeline established by clusters 0-3 and by cluster 4 batch 1
-- (server/queries/fleet-driver-device.ts, drafted independently and in
-- parallel -- confirmed to target zero overlapping tables/functions with this
-- migration).
--
-- supabase/config.toml's `schemas = ["public", "graphql_public"]` never exposes
-- the "app" Postgres schema to PostgREST, so every `.from()` read against an
-- `app.*` table in server/queries/*.ts has NEVER worked in production. Closes
-- the LAST 5 broken .from() call sites of cluster 4 across 4 files:
--
--   server/queries/driver-mobile-tracking.ts:36   getDriverMobileTrackingSession
--   server/queries/gps-device-installation.ts:21  listGpsDeviceInstallations
--   server/queries/gps-device-installation.ts:33  getGpsDeviceInstallationForAssignment
--   server/queries/tracking-source-policy.ts:76   getTenantTrackingSourcePolicy
--   server/queries/public-tracking.ts:35          getActiveShipmentTrackingToken
--
-- 5 new app.*/public.* Option-2 wrapper function pairs (10 functions total),
-- over 4 distinct relations:
--
--   app.driver_mobile_tracking_sessions   -> app.get_driver_mobile_tracking_session      (SECURITY DEFINER)
--   app.gps_device_installations          -> app.list_gps_device_installations            (SECURITY INVOKER)
--                                          -> app.get_gps_device_installation_for_assignment (SECURITY INVOKER)
--   app.tenant_tracking_source_policies   -> app.get_tenant_tracking_source_policy         (SECURITY INVOKER)
--   app.shipment_tracking_tokens          -> app.get_active_shipment_tracking_token         (SECURITY DEFINER)
--
-- ===========================================================================
-- SECURITY POSTURE -- two distinct authority shapes in this one migration
-- ===========================================================================
--
-- SHAPE 1 (SECURITY DEFINER, actor parameter + RULE A): app.driver_mobile_
-- tracking_sessions and app.shipment_tracking_tokens.
--
-- Both tables were hit by ISS-2026-232 (20260815300000_harden_token_hash_
-- column_privilege_iss232_closure.sql), which contains, verbatim:
--
--   revoke select on app.driver_mobile_tracking_sessions from authenticated;
--   grant select (
--     id, tenant_id, shipment_leg_tracking_session_id, status, issued_at,
--     expires_at, last_seen_at, revoked_at, revoked_reason, created_by, created_at
--   ) on app.driver_mobile_tracking_sessions to authenticated;
--
--   revoke select on app.shipment_tracking_tokens from authenticated;
--   grant select (
--     id, tenant_id, shipment_order_id, status, expires_at, revoked_at,
--     revoked_reason, created_by, created_at
--   ) on app.shipment_tracking_tokens to authenticated;
--
-- (confirmed via grep, read in full, not paraphrased from memory.)
--
-- ADVERSARIAL NOTE on the actual mechanism (independent re-derivation, not
-- accepted uncritically): Postgres grants SELECT per-COLUMN, not only
-- per-table, and a SECURITY INVOKER function's privilege checks are evaluated
-- against the CALLING role for exactly the columns its own query body
-- references. The re-issued grant above is a COLUMN-level `grant select (<11
-- cols>)` / `grant select (<9 cols>)` -- and those 11/9 columns are EXACTLY the
-- columns app.get_driver_mobile_tracking_session/app.get_active_shipment_
-- tracking_token below select. Mechanically, a SECURITY INVOKER SQL function
-- with a body of `select <that exact column list> from <that exact table>
-- where <predicate over columns already in that list>` would in fact pass
-- Postgres's privilege check for `authenticated` today, and would additionally
-- be correctly row-scoped by the table's own live RLS policy (RULE B below
-- confirms both tables have a real, currently-enforced SELECT policy for
-- `authenticated`).
--
-- SECURITY DEFINER is still the correct choice here, for reasons independent
-- of "INVOKER is mechanically impossible":
--   1. Drift protection. An INVOKER function's safety would depend entirely on
--      the CURRENT state of an ambient, easily-perturbed external grant -- not
--      on anything written in the function's own body. That grant has already
--      regressed once: ISS-2026-232 exists specifically because these two
--      tables originally shipped with a blanket table-level `grant select ...
--      to authenticated` that silently included token_hash. A future,
--      well-intentioned migration that widens this column list via a bare
--      `grant select on app.<table> to authenticated` instead of a column list
--      would silently re-open the exact gap ISS-2026-232 closed, and an
--      INVOKER function here would inherit that regression with zero code of
--      its own changing. A DEFINER function's own explicit column list in its
--      SELECT is self-contained and immune to that class of drift.
--   2. Consistency with this exact table's own write-side precedent. Every
--      other privileged operation on these two tables is already SECURITY
--      DEFINER with its own explicit token_hash handling:
--      app.issue_shipment_tracking_token and app.revoke_shipment_tracking_token
--      (both `security definer`) mask token_hash to null on their RETURNING
--      composite as an ISS-2026-232 Tier C fix; app.start_driver_mobile_session
--      and app.revoke_driver_mobile_session (same) do the same. Making the
--      READ path DEFINER too means the full issue/revoke/read lifecycle for a
--      given token table shares one uniform, auditable, self-contained model
--      for excluding token_hash.
--
-- RULE A applies to both DEFINER functions below: each takes a NEW
-- p_actor_auth_user_id parameter (the original TS functions took none -- same
-- genuine, disclosed breaking signature change cluster 3 batch 1's own dispatch
-- functions already established as a precedent for this exact situation), so
-- each calls `app.assert_actor_is_session_identity(p_actor_auth_user_id)` as
-- its own leading statement, before any lookup or authority check --
-- necessitating `language plpgsql`.
--
-- Because SECURITY DEFINER bypasses RLS on the underlying table entirely, each
-- function's WHERE clause must reproduce -- not merely cite -- its table's own
-- CURRENT row-visibility policy, substituting the explicit, RULE-A-checked
-- p_actor_auth_user_id for the policy's own `(select auth.uid())`/implicit
-- default-to-session-identity argument:
--   * app.get_driver_mobile_tracking_session reproduces driver_mobile_
--     tracking_sessions_select_scoped's CURRENT text (RULE B below):
--       (app.has_active_tenant_membership(tenant_id) AND NOT
--         app.actor_holds_customer_user_layer(tenant_id)) OR app.is_supreme_admin()
--     via the explicit-actor overloads app.has_active_tenant_membership(p_tenant_id,
--     p_auth_user_id), app.actor_holds_customer_user_layer(p_tenant_id, p_auth_user_id)
--     (both default to auth.uid() for their own RLS-context callers, both
--     accept an explicit override), and app.is_supreme_admin(p_auth_user_id)
--     (one-arg, default auth.uid()).
--   * app.get_active_shipment_tracking_token reproduces shipment_tracking_
--     tokens_select_scoped's CURRENT (and, per RULE B, ONLY-ever) text
--     verbatim: an EXISTS join to app.shipment_orders gated by
--     app.can_access_record(auth.uid(), so.tenant_id, so.owner_user_id,
--     app.lead_record_scope_org_unit_ids(so.org_unit_id), null) -- the
--     IDENTICAL predicate app.issue_shipment_tracking_token/app.revoke_
--     shipment_tracking_token themselves already enforce for every mutation on
--     this same table.
--
-- SHAPE 2 (SECURITY INVOKER, zero actor parameter): app.gps_device_
-- installations and app.tenant_tracking_source_policies.
--
-- Neither table was touched by ISS-2026-232 -- both still carry their
-- ORIGINAL, unrestricted, table-level `grant select on app.<table> to
-- authenticated, service_role` (20260729350000:205 and 20260729340000:269
-- respectively; no later revoke of either exists). There is no
-- column-privilege gap to route around for either table, and this series' own
-- decisive test gives a clean negative result for all 3 TS functions over
-- these 2 tables (zero real callers under app/, only hand-rolled test fakes).
-- Live sibling precedent: cluster 3 batch 4's own app.list_capacity_
-- reservations_for_leg / app.list_active_capacity_reservations_for_vehicle
-- (20260911040000) are SECURITY INVOKER over app.vehicle_capacity_reservations,
-- whose OWN current RLS predicate is the byte-for-byte IDENTICAL shape used by
-- both tables here (RULE B below), each independently rewritten to this exact
-- text by the same 20260730560000 migration.
--
-- No RULE A guard on either of these 2 functions: neither takes an actor
-- parameter, so there is no separate identity claim for app.assert_actor_
-- is_session_identity to cross-check.
--
-- Note this does NOT contradict SHAPE 1's own DEFINER conclusion for driver_
-- mobile_tracking_sessions, even though driver_mobile_tracking_sessions_
-- select_scoped uses this EXACT SAME predicate shape (also rewritten by
-- 20260730560000 to the identical text). The DEFINER requirement there is
-- driven entirely by the ISS-2026-232 column-privilege closure unique to that
-- table (and to shipment_tracking_tokens) -- not by its RLS predicate shape,
-- which on its own would have supported INVOKER exactly as it does here. Two
-- tables sharing one RLS shape can legitimately land on two different
-- security modes when only one of them also carries a sensitive column that
-- ambient grants must never accidentally re-expose.
--
-- ===========================================================================
-- RULE B -- RLS predicate currency (all 4 relations)
-- ===========================================================================
--
-- * driver_mobile_tracking_sessions_select_scoped: ORIGINAL
--   (20260729360000_create_advanced_tms_driver_mobile_tracking.sql:520-522):
--     for select to authenticated
--     using (app.has_active_tenant_membership(tenant_id) or app.is_supreme_admin());
--   superseded by ALTER POLICY
--   (20260730560000_harden_customer_user_layer_default_deny.sql:130-131) --
--   CURRENT text:
--     using (((app.has_active_tenant_membership(tenant_id)
--       AND NOT app.actor_holds_customer_user_layer(tenant_id))
--       OR app.is_supreme_admin()));
--
-- * gps_device_installations_select_scoped: ORIGINAL
--   (20260729350000_create_advanced_tms_device_installation_evidence.sql:
--   199-201), superseded by ALTER POLICY (20260730560000:247-248) -- CURRENT
--   text, byte-for-byte identical shape to driver_mobile_tracking_sessions_
--   select_scoped above.
--
-- * tenant_tracking_source_policies_select_scoped: ORIGINAL
--   (20260729340000_create_advanced_tms_tracking_entitlement_source_policy.sql:
--   263-265), superseded by ALTER POLICY (20260730560000:319-320) -- CURRENT
--   text, same shape once more.
--
-- * shipment_tracking_tokens_select_scoped
--   (20260728130000_create_operations_public_tracking.sql:312-319) -- the
--   ORIGINAL and, per repo-wide grep of both "create|alter policy" and the
--   bare policy name, the ONLY-EVER declaration (this table was NOT among the
--   policies 20260730560000 touched, because its policy already has an
--   owner/org-unit-scoped shape rather than the bare has_active_tenant_
--   membership shape that migration was narrowing). CURRENT (and original)
--   text:
--     for select to authenticated
--     using (
--       exists (
--         select 1 from app.shipment_orders so
--         where so.id = shipment_tracking_tokens.shipment_order_id
--           and app.can_access_record((select auth.uid()), so.tenant_id,
--             so.owner_user_id, app.lead_record_scope_org_unit_ids(so.org_unit_id), null)
--       )
--     );
--
-- All 4 predicates are relied on via Postgres's own automatic RLS evaluation
-- for the 2 SECURITY INVOKER functions below (never re-implemented in SQL);
-- for the 2 SECURITY DEFINER functions, each predicate is REPRODUCED
-- explicitly in the function's own WHERE clause per SHAPE 1 above, since
-- DEFINER bypasses RLS on the underlying table.
--
-- ===========================================================================
-- RULE C -- currency of every cited existing app.* function
-- ===========================================================================
-- * app.assert_actor_is_session_identity: exactly 1 hit
--   (20260730440000_harden_actor_identity_session_crosscheck.sql:59) -- never
--   redefined since.
-- * app.has_active_tenant_membership(p_tenant_id uuid, p_auth_user_id uuid
--   default auth.uid()): LATEST body is 20260907110000_fix_suspended_user_
--   retains_access_iss_d3b.sql (a real, disclosed narrowing of who counts as
--   an active tenant member -- not re-derived here since this migration calls
--   the function rather than re-implementing its body).
-- * app.actor_holds_customer_user_layer: exactly 1 hit
--   (20260730311000_harden_customer_inventory_access_rls_isolation.sql:71).
-- * app.is_supreme_admin: exactly 1 hit
--   (20260716105512_create_rls_tenant_policies.sql:45).
-- * app.can_access_record: LATEST body is 20260723180000 (the same latest body
--   every prior O1 batch in this series has already independently confirmed).
-- * app.issue_shipment_tracking_token / app.revoke_shipment_tracking_token:
--   both `security definer`. Authority check (read in full at each function's
--   own latest body): looks up the shipment order by id, raises
--   `shipment_order_not_found` if missing or if `not app.has_active_tenant_
--   membership(v_shipment.tenant_id, p_actor_auth_user_id)`; then
--   `app.evaluate_permission(p_actor_auth_user_id, v_shipment.tenant_id, 'OPS',
--   'Edit')`, raising `insufficient_authority` if not allowed; then
--   `app.can_access_record(p_actor_auth_user_id, v_shipment.tenant_id,
--   v_shipment.owner_user_id, app.lead_record_scope_org_unit_ids(v_shipment.
--   org_unit_id), null)`. This is the OPS:Edit write-authority shape --
--   app.get_active_shipment_tracking_token below deliberately reproduces only
--   the can_access_record half (the record-scope read-visibility check that is
--   ALSO shipment_tracking_tokens_select_scoped's own RLS predicate verbatim),
--   never the OPS:Edit RBAC gate, since this is a read replacing an
--   RLS-scoped .from() select that never required an edit-tier permission --
--   adding one now would be a real, undisclosed authority-tightening
--   regression versus the original call, not a like-for-like port.
-- * app.start_driver_mobile_session / app.revoke_driver_mobile_session: both
--   `security definer`, same has_active_tenant_membership/evaluate_permission/
--   can_access_record shape scoped through app.shipment_leg_tracking_sessions
--   -> its own parent shipment leg/order (not re-derived line-by-line here
--   since app.get_driver_mobile_tracking_session below is scoped directly off
--   the session row's OWN tenant_id, matching driver_mobile_tracking_sessions_
--   select_scoped's OWN predicate, not the write functions' stricter
--   shipment-leg-scoped predicate, which these read functions were never
--   gated by even under RLS).
-- * app.resolve_tenant_tracking_source_policy: exactly 1 hit
--   (20260729340000:235) -- `language sql`, default SECURITY INVOKER. ALWAYS
--   resolves to exactly one row via `coalesce(...)` over a `left join`, so it
--   structurally CANNOT distinguish "tenant never set a policy" from "tenant
--   explicitly set the same values as the default". Its own comment: "RLS on
--   the underlying table still governs whether the caller may see a real
--   explicit row at all; an unauthorized caller simply observes the system
--   default" -- i.e. this function relies ENTIRELY on tenant_tracking_source_
--   policies_select_scoped's own live RLS evaluation, cross-confirming this
--   migration's own SECURITY INVOKER conclusion for that table (SHAPE 2).
--
-- ===========================================================================
-- SETOF-vs-BARE-COMPOSITE -- standing defect-class check
-- ===========================================================================
-- All 4 TS functions in this migration's scope are 0-or-1-row lookups
-- (`.maybeSingle()` in every one of their original .from() calls):
--   * getDriverMobileTrackingSession -> app.get_driver_mobile_tracking_session:
--     `returns table (...)` (an explicit column list, NOT `returns setof
--     app.driver_mobile_tracking_sessions`, whose composite type includes
--     token_hash).
--   * getGpsDeviceInstallationForAssignment -> app.get_gps_device_installation_
--     for_assignment: `returns setof app.gps_device_installations`.
--   * getTenantTrackingSourcePolicy -> app.get_tenant_tracking_source_policy:
--     `returns setof app.tenant_tracking_source_policies`.
--   * getActiveShipmentTrackingToken -> app.get_active_shipment_tracking_token:
--     `returns table (...)` (explicit column list, same token_hash-exclusion
--     reason as get_driver_mobile_tracking_session).
-- None of these 4 is declared as a bare (non-setof) composite return.
-- listGpsDeviceInstallations -> app.list_gps_device_installations is a genuine
-- unbounded list (`returns setof app.gps_device_installations`) -- confirmed
-- directly against its own current Promise<GpsDeviceInstallation[]> signature
-- and body (no .maybeSingle()/.single()/.limit(1) anywhere in it).
--
-- ===========================================================================
-- Explicit column lists (app.get_driver_mobile_tracking_session and
-- app.get_active_shipment_tracking_token must NOT `returns setof app.<table>`
-- with the table's own full composite type -- that would leak token_hash back
-- into the return value even though the TS parser never asks for it -- and
-- must instead hand-pick exactly the columns their original .from() calls
-- selected)
-- ===========================================================================
-- app.driver_mobile_tracking_sessions' own full column set (12 columns, read
-- directly from its CREATE TABLE,
-- 20260729360000_create_advanced_tms_driver_mobile_tracking.sql:74-90): id,
-- tenant_id, shipment_leg_tracking_session_id, token_hash, status, issued_at,
-- expires_at, last_seen_at, revoked_at, revoked_reason, created_by,
-- created_at. No ALTER TABLE ... ADD COLUMN was ever applied to this table
-- anywhere in the migration set. server/queries/driver-mobile-tracking.ts:37's
-- own explicit column list (id, tenant_id, shipment_leg_tracking_session_id,
-- status, issued_at, expires_at, last_seen_at, revoked_at, revoked_reason,
-- created_by, created_at) is exactly this full set minus token_hash -- the
-- same 11 columns app.get_driver_mobile_tracking_session's own `returns table
-- (...)` below reproduces, in the same order.
--
-- app.shipment_tracking_tokens' own full column set (10 columns, read directly
-- from its CREATE TABLE, 20260728130000_create_operations_public_tracking.sql:
-- 63-77): id, tenant_id, shipment_order_id, token_hash, status, expires_at,
-- revoked_at, revoked_reason, created_by, created_at. Same no-ALTER-TABLE
-- confirmation. server/queries/public-tracking.ts:36's own explicit column
-- list (id, tenant_id, shipment_order_id, status, expires_at, revoked_at,
-- revoked_reason, created_by, created_at) is exactly this full set minus
-- token_hash -- the same 9 columns app.get_active_shipment_tracking_token's
-- own `returns table (...)` below reproduces, in the same order.
--
-- ===========================================================================
-- GRANT PARITY (ISS-2026-309)
-- ===========================================================================
-- Every app.* function below: `revoke execute on function app.X(...) from
-- public;` then `grant execute on function app.X(...) to authenticated,
-- service_role;` -- matching all 4 relations' own direct grants (none grants
-- `anon` anything on any of these 4 tables). Every public.* wrapper below: the
-- full 4-role revoke per ISS-2026-309 then `grant execute on function
-- public.X(...) to authenticated, service_role;`.
--
-- Security mode parity between each app.* function and its public.* wrapper
-- follows the two established Option-2 templates: DEFINER app.* functions get
-- an explicitly `security definer` public.* wrapper (matching cluster 3 batch
-- 1's own convention); INVOKER app.* functions get a public.* wrapper with NO
-- explicit security clause (Postgres's own default is invoker, matching
-- cluster 3 batch 4's own convention).
-- ===========================================================================


-- ===========================================================================
-- 1. app.get_driver_mobile_tracking_session -- replaces server/queries/
--    driver-mobile-tracking.ts:36 (getDriverMobileTrackingSession)
--    SECURITY DEFINER (SHAPE 1 above)
-- ===========================================================================
-- Replaces: `.from("driver_mobile_tracking_sessions")
-- .select("id, tenant_id, shipment_leg_tracking_session_id, status, issued_at,
-- expires_at, last_seen_at, revoked_at, revoked_reason, created_by, created_at")
-- .eq("shipment_leg_tracking_session_id", shipmentLegTrackingSessionId)
-- .eq("status", "active").maybeSingle()`.
create function app.get_driver_mobile_tracking_session(
  p_shipment_leg_tracking_session_id uuid,
  p_actor_auth_user_id uuid
)
returns table (
  id uuid,
  tenant_id uuid,
  shipment_leg_tracking_session_id uuid,
  status text,
  issued_at timestamptz,
  expires_at timestamptz,
  last_seen_at timestamptz,
  revoked_at timestamptz,
  revoked_reason text,
  created_by text,
  created_at timestamptz
)
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
begin
  -- RULE A: leading statement, before any lookup or authority check.
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  return query
  select
    s.id, s.tenant_id, s.shipment_leg_tracking_session_id, s.status, s.issued_at,
    s.expires_at, s.last_seen_at, s.revoked_at, s.revoked_reason, s.created_by, s.created_at
  from app.driver_mobile_tracking_sessions s
  where s.shipment_leg_tracking_session_id = p_shipment_leg_tracking_session_id
    and s.status = 'active'
    and (
      (app.has_active_tenant_membership(s.tenant_id, p_actor_auth_user_id)
        and not app.actor_holds_customer_user_layer(s.tenant_id, p_actor_auth_user_id))
      or app.is_supreme_admin(p_actor_auth_user_id)
    );
end;
$$;

comment on function app.get_driver_mobile_tracking_session(uuid, uuid) is
  'ATW-226C/O1 remediation (cluster 4): the active mobile session token record for one ATW-225 tracking session, if any, replacing server/queries/driver-mobile-tracking.ts:36''s broken .from("driver_mobile_tracking_sessions").select("id, tenant_id, shipment_leg_tracking_session_id, status, issued_at, expires_at, last_seen_at, revoked_at, revoked_reason, created_by, created_at").eq("shipment_leg_tracking_session_id", ...).eq("status", "active").maybeSingle() (app is not exposed to PostgREST). SECURITY DEFINER, not INVOKER, because ISS-2026-232 (20260815300000, cited in full in this file''s own header) revoked authenticated''s TABLE-level select on this table and re-granted only a COLUMN-level select on these exact 11 columns -- this function''s own explicit SELECT list is self-contained and immune to that grant ever drifting back open, and matches the SECURITY DEFINER posture app.start_driver_mobile_session/app.revoke_driver_mobile_session already use on this same table (see this file''s own header SECURITY POSTURE/RULE C sections for the full derivation, including the adversarial note on the batch brief''s own stated mechanism). RULE A: p_actor_auth_user_id is NEW (the original TS function took none) and is cross-checked via app.assert_actor_is_session_identity as the leading statement. Because SECURITY DEFINER bypasses RLS, the WHERE clause explicitly reproduces driver_mobile_tracking_sessions_select_scoped''s own CURRENT predicate (RULE B: (app.has_active_tenant_membership(tenant_id) AND NOT app.actor_holds_customer_user_layer(tenant_id)) OR app.is_supreme_admin(), current since 20260730560000:130-131), substituting the RULE-A-checked p_actor_auth_user_id for auth.uid() via each helper''s own explicit-actor overload. `returns table (...)` with the same 11-column explicit list as the original TS call -- deliberately NOT `returns setof app.driver_mobile_tracking_sessions`, which would leak token_hash back into the return composite even though nothing downstream reads it. `driver_mobile_tracking_sessions_one_active_idx` (20260729360000:95, a partial UNIQUE index on shipment_leg_tracking_session_id WHERE status=''active'') bounds this read to 0-or-1 rows at the database level, independent of the authority predicate -- returns setof-shaped zero-or-one rows, never an all-NULL row on a miss. Returns zero rows -- never an exception -- for a session with no active token issued yet, a nonexistent shipment_leg_tracking_session_id, or an actor who cannot reach that session''s own tenant; the TS caller''s existing `data ? parse(data) : null` unwrap already treats that as null.';

-- Option-2 wrapper: app is not exposed to PostgREST; this is a thin security-
-- definer pass-through to app.get_driver_mobile_tracking_session with an
-- identical grant set and an identical security mode (definer, matching its
-- app.* counterpart), never a reimplementation.
create function public.get_driver_mobile_tracking_session(
  p_shipment_leg_tracking_session_id uuid,
  p_actor_auth_user_id uuid
)
returns table (
  id uuid,
  tenant_id uuid,
  shipment_leg_tracking_session_id uuid,
  status text,
  issued_at timestamptz,
  expires_at timestamptz,
  last_seen_at timestamptz,
  revoked_at timestamptz,
  revoked_reason text,
  created_by text,
  created_at timestamptz
)
language sql
stable
security definer
set search_path = pg_catalog, pg_temp
as $wrap$
  select * from app.get_driver_mobile_tracking_session(p_shipment_leg_tracking_session_id, p_actor_auth_user_id);
$wrap$;

comment on function public.get_driver_mobile_tracking_session(uuid, uuid) is
  'Option-2 wrapper: app is not exposed to PostgREST; this is a thin security-definer pass-through to app.get_driver_mobile_tracking_session with an identical grant set and an identical security mode (definer), never a reimplementation. Same explicit 11-column returns table (...) as its app.* counterpart -- see that function''s own comment for why not setof app.driver_mobile_tracking_sessions.';

revoke execute on function app.get_driver_mobile_tracking_session(uuid, uuid) from public;
grant execute on function app.get_driver_mobile_tracking_session(uuid, uuid) to authenticated, service_role;

revoke execute on function public.get_driver_mobile_tracking_session(uuid, uuid) from anon, authenticated, service_role, public;
grant execute on function public.get_driver_mobile_tracking_session(uuid, uuid) to authenticated, service_role;


-- ===========================================================================
-- 2. app.list_gps_device_installations -- replaces server/queries/
--    gps-device-installation.ts:21 (listGpsDeviceInstallations)
--    SECURITY INVOKER (SHAPE 2 above)
-- ===========================================================================
-- Replaces: `.from("gps_device_installations").select("*")
-- .eq("tenant_id", tenantId).order("installed_at", { ascending: false })`.
create function app.list_gps_device_installations(p_tenant_id uuid)
returns setof app.gps_device_installations
language sql
stable
security invoker
set search_path = app, pg_temp
as $$
  select * from app.gps_device_installations
  where tenant_id = p_tenant_id
  order by installed_at desc;
$$;

comment on function app.list_gps_device_installations(uuid) is
  'ATW-226B/O1 remediation (cluster 4): every installation evidence row for one tenant, newest-installed first, replacing server/queries/gps-device-installation.ts:21''s broken .from("gps_device_installations").select("*").eq("tenant_id", tenantId).order("installed_at", { ascending: false }) (app is not exposed to PostgREST). SECURITY INVOKER, zero actor parameter: this table was never touched by ISS-2026-232 (no column-privilege gap to route around -- `authenticated` still holds its ORIGINAL, unrestricted table-level select, 20260729350000:205, confirmed by a repo-wide grep of `revoke select on app.gps_device_installations` returning zero hits), and this series'' own decisive test finds zero real callers of listGpsDeviceInstallations anywhere under app/ -- only server/queries/gps-device-installation.test.ts, a hand-rolled fake client, ever calls it. Live sibling precedent: cluster 3 batch 4''s own app.list_capacity_reservations_for_leg/app.list_active_capacity_reservations_for_vehicle (20260911040000) are SECURITY INVOKER over the byte-for-byte IDENTICAL RLS predicate shape this table shares (see this file''s own header SECURITY POSTURE/RULE B sections). Relies entirely on the calling role''s own live RLS evaluation of gps_device_installations_select_scoped -- CURRENT text (20260730560000:247-248, superseding the original 20260729350000:199-201): (app.has_active_tenant_membership(tenant_id) AND NOT app.actor_holds_customer_user_layer(tenant_id)) OR app.is_supreme_admin() -- reproduced by the live RLS engine, never re-implemented in this function''s own SQL body. No RULE A guard: no actor parameter exists to protect. `returns setof app.gps_device_installations` (13 columns, matching server/contracts/gps-device-installation/gps-device-installation.ts''s own GpsDeviceInstallationSchema 1:1) -- a genuine unbounded list read (a tenant can have arbitrarily many installation-evidence rows) -- confirmed directly against the TS function''s own current Promise<GpsDeviceInstallation[]> signature and body (no .maybeSingle()/.single()/.limit(1)); setof used anyway per this series'' own uniform list-function convention. Returns zero rows, never an exception, for a tenant with no recorded installations or an actor whose session cannot pass the live predicate above, matching the original RLS-filtered .from() read''s own current (never-actually-reachable) empty-array-on-miss behavior, unchanged.';

-- Option-2 wrapper: app is not exposed to PostgREST; this is a thin pass-
-- through to app.list_gps_device_installations with an identical grant set
-- and an identical security mode (invoker, matching its app.* counterpart --
-- never a reimplementation, and never a privilege upgrade the app.* function
-- itself does not have).
create function public.list_gps_device_installations(p_tenant_id uuid)
returns setof app.gps_device_installations
language sql
stable
set search_path = pg_catalog, pg_temp
as $wrap$
  select * from app.list_gps_device_installations(p_tenant_id);
$wrap$;

comment on function public.list_gps_device_installations(uuid) is
  'Option-2 wrapper: app is not exposed to PostgREST; this is a thin pass-through to app.list_gps_device_installations with an identical grant set and an identical security mode (invoker), never a reimplementation.';

revoke execute on function app.list_gps_device_installations(uuid) from public;
grant execute on function app.list_gps_device_installations(uuid) to authenticated, service_role;

revoke execute on function public.list_gps_device_installations(uuid) from anon, authenticated, service_role, public;
grant execute on function public.list_gps_device_installations(uuid) to authenticated, service_role;


-- ===========================================================================
-- 3. app.get_gps_device_installation_for_assignment -- replaces server/
--    queries/gps-device-installation.ts:33 (getGpsDeviceInstallationForAssignment)
--    SECURITY INVOKER (SHAPE 2 above)
-- ===========================================================================
-- Replaces: `.from("gps_device_installations").select("*")
-- .eq("device_vehicle_assignment_id", deviceVehicleAssignmentId).maybeSingle()`.
create function app.get_gps_device_installation_for_assignment(p_device_vehicle_assignment_id uuid)
returns setof app.gps_device_installations
language sql
stable
security invoker
set search_path = app, pg_temp
as $$
  select * from app.gps_device_installations
  where device_vehicle_assignment_id = p_device_vehicle_assignment_id;
$$;

comment on function app.get_gps_device_installation_for_assignment(uuid) is
  'ATW-226B/O1 remediation (cluster 4): the installation evidence row for one device-vehicle assignment, if any was ever recorded, replacing server/queries/gps-device-installation.ts:33''s broken .from("gps_device_installations").select("*").eq("device_vehicle_assignment_id", deviceVehicleAssignmentId).maybeSingle() (app is not exposed to PostgREST). Security invoker, zero actor parameter -- identical table, identical authority shape, and identical decisive-test outcome as app.list_gps_device_installations above; no real caller of getGpsDeviceInstallationForAssignment exists anywhere in the repository besides a unit test using a hand-rolled fake client. Relies entirely on the calling role''s own live RLS evaluation of gps_device_installations_select_scoped (the identical CURRENT predicate cited under app.list_gps_device_installations above, not re-implemented here). No RULE A guard: no actor parameter exists to protect. `returns setof app.gps_device_installations`, deliberately NOT a bare (non-setof) composite -- a bare composite return would yield one all-NULL row on a miss rather than zero rows, throwing an uncaught ZodError against this codebase''s own `data ? parse(data) : null` unwrap idiom instead of the promised graceful null. `gps_device_installations_assignment_unique unique (device_vehicle_assignment_id)` (20260729350000:50) bounds this read to 0-or-1 rows at the database level, independent of RLS -- one installation-evidence row per assignment, by construction. Returns zero rows -- never a row of nulls, never an exception -- for an assignment with no installation evidence recorded yet, a nonexistent device_vehicle_assignment_id, or an actor whose session cannot pass the live predicate above; the TS caller''s existing `data ? parse(data) : null` unwrap already treats that as null.';

-- Option-2 wrapper: app is not exposed to PostgREST; this is a thin pass-
-- through to app.get_gps_device_installation_for_assignment with an identical
-- grant set and an identical security mode (invoker, matching its app.*
-- counterpart). `returns setof`, matching its own return shape exactly.
create function public.get_gps_device_installation_for_assignment(p_device_vehicle_assignment_id uuid)
returns setof app.gps_device_installations
language sql
stable
set search_path = pg_catalog, pg_temp
as $wrap$
  select * from app.get_gps_device_installation_for_assignment(p_device_vehicle_assignment_id);
$wrap$;

comment on function public.get_gps_device_installation_for_assignment(uuid) is
  'Option-2 wrapper: app is not exposed to PostgREST; this is a thin pass-through to app.get_gps_device_installation_for_assignment with an identical grant set and an identical security mode (invoker), never a reimplementation. Returns setof, not a bare composite -- see its app.* counterpart''s own comment for why.';

revoke execute on function app.get_gps_device_installation_for_assignment(uuid) from public;
grant execute on function app.get_gps_device_installation_for_assignment(uuid) to authenticated, service_role;

revoke execute on function public.get_gps_device_installation_for_assignment(uuid) from anon, authenticated, service_role, public;
grant execute on function public.get_gps_device_installation_for_assignment(uuid) to authenticated, service_role;


-- ===========================================================================
-- 4. app.get_tenant_tracking_source_policy -- replaces server/queries/
--    tracking-source-policy.ts:76 (getTenantTrackingSourcePolicy)
--    SECURITY INVOKER (SHAPE 2 above)
-- ===========================================================================
-- Replaces: `.from("tenant_tracking_source_policies").select("*")
-- .eq("tenant_id", tenantId).maybeSingle()`.
--
-- Deliberately distinct from the sibling app.resolve_tenant_tracking_source_
-- policy (20260729340000:235, RULE C above) -- that function ALWAYS resolves
-- with defaults via coalesce() over a left join and so structurally cannot
-- distinguish "tenant never set a policy" from "tenant explicitly set it to
-- the default values". This function selects the raw row (or nothing) with
-- no coalesce/default-filling of any kind, preserving that distinction for
-- its own real caller (an admin-form pre-fill, per the TS function's own
-- doc comment) exactly as required.
create function app.get_tenant_tracking_source_policy(p_tenant_id uuid)
returns setof app.tenant_tracking_source_policies
language sql
stable
security invoker
set search_path = app, pg_temp
as $$
  select * from app.tenant_tracking_source_policies
  where tenant_id = p_tenant_id;
$$;

comment on function app.get_tenant_tracking_source_policy(uuid) is
  'ATW-226A/O1 remediation (cluster 4): the raw explicit tracking-source-policy row for one tenant, or no row when the tenant has never set one, replacing server/queries/tracking-source-policy.ts:76''s broken .from("tenant_tracking_source_policies").select("*").eq("tenant_id", tenantId).maybeSingle() (app is not exposed to PostgREST). Deliberately distinct from the sibling app.resolve_tenant_tracking_source_policy (20260729340000:235, never redefined -- RULE C): that function ALWAYS resolves exactly one row via coalesce()-over-left-join and so cannot tell "never set" apart from "set to the same values as the default" -- this function selects the raw row with no defaulting of any kind, preserving that distinction for its own real caller (an admin-form pre-fill, per the TS function''s own doc comment). SECURITY INVOKER, zero actor parameter: this table was never touched by ISS-2026-232 (`authenticated` still holds its ORIGINAL unrestricted table-level select, 20260729340000:269; repo-wide grep of `revoke select on app.tenant_tracking_source_policies` returns zero hits), the decisive test finds zero real callers of getTenantTrackingSourcePolicy anywhere under app/ (only server/queries/tracking-source-policy.test.ts, a hand-rolled fake), and the live sibling app.resolve_tenant_tracking_source_policy itself already relies on this exact table''s own RLS for its own authority shape (its own comment: "RLS on the underlying table still governs whether the caller may see a real explicit row at all") -- this function reuses that same, already-shipped design rather than inventing a different one for the same table. Relies entirely on the calling role''s own live RLS evaluation of tenant_tracking_source_policies_select_scoped -- CURRENT text (20260730560000:319-320, superseding the original 20260729340000:263-265): (app.has_active_tenant_membership(tenant_id) AND NOT app.actor_holds_customer_user_layer(tenant_id)) OR app.is_supreme_admin() -- reproduced by the live RLS engine, never re-implemented here. No RULE A guard: no actor parameter exists to protect. `returns setof app.tenant_tracking_source_policies` (10 columns, matching server/contracts/tracking-source-policy/tracking-source-policy.ts''s own TenantTrackingSourcePolicySchema 1:1), deliberately NOT a bare (non-setof) composite. `tenant_tracking_source_policies_tenant_unique unique (tenant_id)` (20260729340000:116) bounds this read to 0-or-1 rows at the database level, independent of RLS. Returns zero rows -- never a row of nulls, never an exception -- for a tenant with no explicit policy row, a nonexistent tenant_id, or an actor whose session cannot pass the live predicate above.';

-- Option-2 wrapper: app is not exposed to PostgREST; this is a thin pass-
-- through to app.get_tenant_tracking_source_policy with an identical grant
-- set and an identical security mode (invoker, matching its app.*
-- counterpart). `returns setof`, matching its own return shape exactly.
create function public.get_tenant_tracking_source_policy(p_tenant_id uuid)
returns setof app.tenant_tracking_source_policies
language sql
stable
set search_path = pg_catalog, pg_temp
as $wrap$
  select * from app.get_tenant_tracking_source_policy(p_tenant_id);
$wrap$;

comment on function public.get_tenant_tracking_source_policy(uuid) is
  'Option-2 wrapper: app is not exposed to PostgREST; this is a thin pass-through to app.get_tenant_tracking_source_policy with an identical grant set and an identical security mode (invoker), never a reimplementation. Returns setof, not a bare composite -- see its app.* counterpart''s own comment for why.';

revoke execute on function app.get_tenant_tracking_source_policy(uuid) from public;
grant execute on function app.get_tenant_tracking_source_policy(uuid) to authenticated, service_role;

revoke execute on function public.get_tenant_tracking_source_policy(uuid) from anon, authenticated, service_role, public;
grant execute on function public.get_tenant_tracking_source_policy(uuid) to authenticated, service_role;


-- ===========================================================================
-- 5. app.get_active_shipment_tracking_token -- replaces server/queries/
--    public-tracking.ts:35 (getActiveShipmentTrackingToken)
--    SECURITY DEFINER (SHAPE 1 above)
-- ===========================================================================
-- Replaces: `.from("shipment_tracking_tokens")
-- .select("id, tenant_id, shipment_order_id, status, expires_at, revoked_at,
-- revoked_reason, created_by, created_at")
-- .eq("shipment_order_id", shipmentOrderId).eq("status", "active").maybeSingle()`.
--
-- Deliberately distinct from the sibling app.lookup_public_shipment_tracking
-- -- that RPC is the one intentionally anon-reachable, unauthenticated
-- public-facing lookup, authorized by token possession alone. This function
-- is the internal Operations tracking-token management panel's own read and
-- requires a real tenant/operations authority check -- reproduced below from
-- app.issue_shipment_tracking_token/app.revoke_shipment_tracking_token's own
-- current bodies (RULE C above), minus their OPS:Edit write-tier gate.
create function app.get_active_shipment_tracking_token(
  p_shipment_order_id uuid,
  p_actor_auth_user_id uuid
)
returns table (
  id uuid,
  tenant_id uuid,
  shipment_order_id uuid,
  status text,
  expires_at timestamptz,
  revoked_at timestamptz,
  revoked_reason text,
  created_by text,
  created_at timestamptz
)
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
begin
  -- RULE A: leading statement, before any lookup or authority check.
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  return query
  select
    t.id, t.tenant_id, t.shipment_order_id, t.status, t.expires_at,
    t.revoked_at, t.revoked_reason, t.created_by, t.created_at
  from app.shipment_tracking_tokens t
  where t.shipment_order_id = p_shipment_order_id
    and t.status = 'active'
    and exists (
      select 1 from app.shipment_orders so
      where so.id = t.shipment_order_id
        and app.can_access_record(
          p_actor_auth_user_id, so.tenant_id, so.owner_user_id,
          app.lead_record_scope_org_unit_ids(so.org_unit_id), null
        )
    );
end;
$$;

comment on function app.get_active_shipment_tracking_token(uuid, uuid) is
  'OPS-180/O1 remediation (cluster 4): the current active tracking token''s metadata (status/expiry/revocation), if any, for one Shipment Order -- for the internal Operations tracking-token management panel, never the raw token -- replacing server/queries/public-tracking.ts:35''s broken .from("shipment_tracking_tokens").select("id, tenant_id, shipment_order_id, status, expires_at, revoked_at, revoked_reason, created_by, created_at").eq("shipment_order_id", ...).eq("status", "active").maybeSingle() (app is not exposed to PostgREST). Deliberately distinct from the sibling app.lookup_public_shipment_tracking -- that RPC is this table''s own intentionally anon-reachable, unauthenticated public lookup, authorized by token possession alone; this function is the Operations-panel-facing read and requires a real tenant/operations authority check. SECURITY DEFINER, not INVOKER, because ISS-2026-232 (20260815300000, cited in full in this file''s own header) revoked authenticated''s TABLE-level select on this table and re-granted only a COLUMN-level select on these exact 9 columns -- this function''s own explicit SELECT list is self-contained and immune to that grant ever drifting back open, and matches the SECURITY DEFINER posture app.issue_shipment_tracking_token/app.revoke_shipment_tracking_token already use on this same table. RULE A: p_actor_auth_user_id is NEW (the original TS function took none) and is cross-checked via app.assert_actor_is_session_identity as the leading statement. Because SECURITY DEFINER bypasses RLS, the WHERE clause explicitly reproduces shipment_tracking_tokens_select_scoped''s own CURRENT (and, per RULE B, only-ever) predicate verbatim: an EXISTS join to app.shipment_orders gated by app.can_access_record(p_actor_auth_user_id, so.tenant_id, so.owner_user_id, app.lead_record_scope_org_unit_ids(so.org_unit_id), null) -- the IDENTICAL can_access_record call app.issue_shipment_tracking_token/app.revoke_shipment_tracking_token themselves already use for every mutation on this same table (RULE C), minus their own additional OPS:Edit app.evaluate_permission gate, which this read deliberately does not add (the original .from() read this replaces never required edit-tier authority either -- adding one now would be an undisclosed authority-tightening regression, not a like-for-like port). `returns table (...)` with the same 9-column explicit list as the original TS call -- deliberately NOT `returns setof app.shipment_tracking_tokens`, which would leak token_hash back into the return composite even though nothing downstream reads it. `shipment_tracking_tokens_one_active_idx` (20260728130000:82, a partial UNIQUE index on shipment_order_id WHERE status=''active'') bounds this read to 0-or-1 rows at the database level, independent of the authority predicate -- setof-shaped zero-or-one rows, never an all-NULL row on a miss. Returns zero rows -- never an exception -- for a shipment order with no active token issued, revoked-only history, a nonexistent shipment_order_id, or an actor who cannot reach that shipment order''s own tenant/owner/org-unit scope; the TS caller''s existing `data ? parse(data) : null` unwrap already treats that as null.';

-- Option-2 wrapper: app is not exposed to PostgREST; this is a thin security-
-- definer pass-through to app.get_active_shipment_tracking_token with an
-- identical grant set and an identical security mode (definer, matching its
-- app.* counterpart), never a reimplementation.
create function public.get_active_shipment_tracking_token(
  p_shipment_order_id uuid,
  p_actor_auth_user_id uuid
)
returns table (
  id uuid,
  tenant_id uuid,
  shipment_order_id uuid,
  status text,
  expires_at timestamptz,
  revoked_at timestamptz,
  revoked_reason text,
  created_by text,
  created_at timestamptz
)
language sql
stable
security definer
set search_path = pg_catalog, pg_temp
as $wrap$
  select * from app.get_active_shipment_tracking_token(p_shipment_order_id, p_actor_auth_user_id);
$wrap$;

comment on function public.get_active_shipment_tracking_token(uuid, uuid) is
  'Option-2 wrapper: app is not exposed to PostgREST; this is a thin security-definer pass-through to app.get_active_shipment_tracking_token with an identical grant set and an identical security mode (definer), never a reimplementation. Same explicit 9-column returns table (...) as its app.* counterpart -- see that function''s own comment for why not setof app.shipment_tracking_tokens.';

revoke execute on function app.get_active_shipment_tracking_token(uuid, uuid) from public;
grant execute on function app.get_active_shipment_tracking_token(uuid, uuid) to authenticated, service_role;

revoke execute on function public.get_active_shipment_tracking_token(uuid, uuid) from anon, authenticated, service_role, public;
grant execute on function public.get_active_shipment_tracking_token(uuid, uuid) to authenticated, service_role;
