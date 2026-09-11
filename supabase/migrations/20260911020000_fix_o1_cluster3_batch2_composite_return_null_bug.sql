-- CG-AUDIT-2026-09-02 O1-query-layer remediation -- corrective fix for a real
-- defect in 20260911010000_close_o1_query_layer_cluster3_batch2_milestone_leg_
-- tracking_multileg.sql (already committed and pushed), found by cluster 3
-- batch 3's own adversarial verify pass before that batch's own migration was
-- ever written. Per AGENTS.md ("Never edit an applied migration; add a new
-- migration") and this project's own machine-enforced
-- scripts/git/check-protected-paths.ts guard, the defect is fixed here in a
-- NEW migration rather than by editing the original file in place.
--
-- THE DEFECT: app.get_shipment_leg_tracking_policy and app.get_current_
-- shipment_leg_tracking_session (both app.*/public.* pairs, 4 declarations
-- total) were declared `returns app.<table>` -- a bare, non-SETOF composite
-- return -- on the premise that "a non-SETOF SQL function's underlying query
-- returning zero rows yields a NULL result." That premise is WRONG --
-- empirically verified against a live Postgres 16 instance: a non-SETOF SQL
-- function whose body query matches zero rows returns exactly ONE row with
-- every column NULL (e.g. `row_to_json` produces `{"id":null,...}`), not zero
-- rows. Against server/queries/mile-orchestration.ts's own
-- `row ? parse(row) : null` unwrap (`Array.isArray(data) ? data[0] : data`),
-- that all-NULL object is truthy, so both functions would have thrown an
-- uncaught ZodError for the ordinary, expected "no policy/session defined
-- yet" case -- a genuine functional regression, worse than the
-- `.maybeSingle()` -> null behavior they replaced.
--
-- THE FIX: both functions (app.* and public.* layers) are dropped and
-- recreated with `returns setof app.<table>` instead of `returns app.<table>`
-- -- Postgres's `CREATE OR REPLACE FUNCTION` does not allow changing a
-- function's return type, so a plain replace is not possible; DROP then
-- CREATE is required. `returns setof` correctly yields zero rows on a miss.
-- No TS code change is needed: the existing `Array.isArray(data) ? data[0] :
-- data` unwrap in server/queries/mile-orchestration.ts already handles a
-- SETOF-returning function's empty-array result correctly (confirmed by
-- re-reading that file -- it was never touched by this fix).
--
-- Every function body, RULE A/B/C authority reasoning, grant, and comment
-- below is otherwise byte-for-byte identical to the original migration's own
-- declarations -- only the `returns` clause and the parts of each comment
-- describing return-shape semantics change.
--
-- Independently re-verified before this migration was written: repo-wide grep
-- for the identical `returns app\.[a-z_]+$` bare-composite-return pattern
-- across every other Ø1-query-layer migration (clusters 0 through 3 batch 2)
-- confirms no other function in this remediation series carries this same
-- defect -- every other single-row lookup in this series uses `returns table
-- (...)` (implicitly SETOF-safe) instead.

-- ===========================================================================
-- 1. app.get_shipment_leg_tracking_policy
-- ===========================================================================
drop function if exists app.get_shipment_leg_tracking_policy(uuid);

create function app.get_shipment_leg_tracking_policy(p_shipment_leg_id uuid)
returns setof app.shipment_leg_tracking_policies
language sql
stable
security invoker
set search_path = app, pg_temp
as $$
  select * from app.shipment_leg_tracking_policies where shipment_leg_id = p_shipment_leg_id;
$$;

comment on function app.get_shipment_leg_tracking_policy(uuid) is
  'ATW-225/O1 remediation: the one tracking policy for a leg, if defined yet, replacing server/queries/mile-orchestration.ts:33''s broken .from("shipment_leg_tracking_policies").select("*").eq("shipment_leg_id", shipmentLegId).maybeSingle() (app is not exposed to PostgREST). Security invoker, zero actor parameter -- mirrors this exact table family''s own existing plain-read function, app.get_shipment_leg_tracking_sessions (20260729330000_create_advanced_tms_mile_orchestration.sql:779-790, "security invoker (relies on the caller''s own RLS)"), rather than its sibling app.resolve_leg_tracking_policy (same file, line 336-442), which is a SECURITY DEFINER computed projection over resource-assignment/device/provider eligibility, not a plain table read. Relies entirely on the calling role''s own RLS evaluation of shipment_leg_tracking_policies_select_scoped (same file, line 795-804: an exists-join through app.shipment_legs/app.shipment_orders scoped via app.can_access_record((select auth.uid()), so.tenant_id, so.owner_user_id, app.lead_record_scope_org_unit_ids(so.org_unit_id), null)) -- reproduced verbatim, confirmed via repo-wide grep that no rewrite of this rule exists anywhere in the migration set. The real calling role already holds a direct `grant select on app.shipment_leg_tracking_policies to authenticated, service_role` (same file, line 819). No RULE A guard: no actor parameter exists to protect -- invoker mode means the policy''s own `(select auth.uid())` already resolves to the real caller. shipment_leg_tracking_policies_shipment_leg_unique (same file, line 103) bounds this read to 0-or-1 rows at the database level. CORRECTIVE FIX (this migration, 20260911020000): declared `returns setof app.shipment_leg_tracking_policies`, not a bare (non-SETOF) composite return -- the original 20260911010000 draft''s `returns app.shipment_leg_tracking_policies` was a real defect: a non-SETOF SQL function whose body query matches zero rows returns ONE row with every column NULL, not zero rows, which the TS layer''s `row ? parse(row) : null` unwrap would have treated as truthy and thrown an uncaught ZodError instead of returning null for the ordinary "no policy defined yet" case. `returns setof` correctly yields zero rows on a miss. Returns zero rows (never an exception) for a nonexistent shipment_leg_id, a leg with no policy defined yet, or an actor who cannot reach that leg''s shipment order''s tenant/owner/org-unit scope -- matching the original RLS-filtered `.maybeSingle()` call''s own current null-on-miss behavior via the TS layer''s existing empty-array check, unchanged.';

-- Option-2 wrapper: app is not exposed to PostgREST; this is a thin pass-through
-- to app.get_shipment_leg_tracking_policy with an identical grant set and an
-- identical security mode (invoker, matching its app.* counterpart).
drop function if exists public.get_shipment_leg_tracking_policy(uuid);

create function public.get_shipment_leg_tracking_policy(p_shipment_leg_id uuid)
returns setof app.shipment_leg_tracking_policies
language sql
stable
set search_path = pg_catalog, pg_temp
as $wrap$
  select * from app.get_shipment_leg_tracking_policy(p_shipment_leg_id);
$wrap$;

comment on function public.get_shipment_leg_tracking_policy(uuid) is
  'Option-2 wrapper: app is not exposed to PostgREST; this is a thin pass-through to app.get_shipment_leg_tracking_policy with an identical grant set and an identical security mode (invoker), never a reimplementation.';

revoke execute on function app.get_shipment_leg_tracking_policy(uuid) from public;
grant execute on function app.get_shipment_leg_tracking_policy(uuid) to authenticated, service_role;

revoke execute on function public.get_shipment_leg_tracking_policy(uuid) from anon, authenticated, service_role, public;
grant execute on function public.get_shipment_leg_tracking_policy(uuid) to authenticated, service_role;

-- ===========================================================================
-- 2. app.get_current_shipment_leg_tracking_session
-- ===========================================================================
drop function if exists app.get_current_shipment_leg_tracking_session(uuid);

create function app.get_current_shipment_leg_tracking_session(p_shipment_leg_id uuid)
returns setof app.shipment_leg_tracking_sessions
language sql
stable
security invoker
set search_path = app, pg_temp
as $$
  select * from app.shipment_leg_tracking_sessions where shipment_leg_id = p_shipment_leg_id and is_current = true;
$$;

comment on function app.get_current_shipment_leg_tracking_session(uuid) is
  'ATW-225/O1 remediation: the current (is_current) tracking session for a leg, if any, replacing server/queries/mile-orchestration.ts:54''s broken .from("shipment_leg_tracking_sessions").select("*").eq("shipment_leg_id", shipmentLegId).eq("is_current", true).maybeSingle() (app is not exposed to PostgREST). Security invoker, zero actor parameter, same table and same authority shape as its own sibling read app.get_shipment_leg_tracking_sessions (20260729330000_create_advanced_tms_mile_orchestration.sql:779-790: `select * from app.shipment_leg_tracking_sessions where shipment_leg_id = p_shipment_leg_id order by started_at asc`, "security invoker (relies on the caller''s own RLS)") -- this function is that same read narrowed to the one is_current row, not a different authority pattern. Relies entirely on the calling role''s own RLS evaluation of shipment_leg_tracking_sessions_select_scoped (same file, line 806-815: an exists-join through app.shipment_legs/app.shipment_orders scoped via app.can_access_record((select auth.uid()), so.tenant_id, so.owner_user_id, app.lead_record_scope_org_unit_ids(so.org_unit_id), null)) -- reproduced verbatim, confirmed via repo-wide grep that no rewrite of this rule exists anywhere in the migration set. The real calling role already holds a direct `grant select on app.shipment_leg_tracking_sessions to authenticated, service_role` (same file, line 821). No RULE A guard: no actor parameter exists to protect. The partial unique index shipment_leg_tracking_sessions_current_leg_unique on (shipment_leg_id) where is_current (same file, line 174) bounds this read to 0-or-1 rows at the database level. CORRECTIVE FIX (this migration, 20260911020000): declared `returns setof app.shipment_leg_tracking_sessions`, not a bare (non-SETOF) composite return -- the original 20260911010000 draft''s `returns app.shipment_leg_tracking_sessions` was a real defect, identical in kind to app.get_shipment_leg_tracking_policy''s own (see that function''s own corrective comment, this same migration, for the full empirical derivation). `returns setof` correctly yields zero rows on a miss. Returns zero rows (never an exception) for a nonexistent shipment_leg_id, a leg with no current session (none ever started, or the last one already ended with is_current left false), or an actor who cannot reach that leg''s shipment order''s tenant/owner/org-unit scope -- matching the original RLS-filtered `.maybeSingle()` call''s own current null-on-miss behavior via the TS layer''s existing empty-array check, unchanged.';

-- Option-2 wrapper: app is not exposed to PostgREST; this is a thin pass-through
-- to app.get_current_shipment_leg_tracking_session with an identical grant set
-- and an identical security mode (invoker, matching its app.* counterpart).
drop function if exists public.get_current_shipment_leg_tracking_session(uuid);

create function public.get_current_shipment_leg_tracking_session(p_shipment_leg_id uuid)
returns setof app.shipment_leg_tracking_sessions
language sql
stable
set search_path = pg_catalog, pg_temp
as $wrap$
  select * from app.get_current_shipment_leg_tracking_session(p_shipment_leg_id);
$wrap$;

comment on function public.get_current_shipment_leg_tracking_session(uuid) is
  'Option-2 wrapper: app is not exposed to PostgREST; this is a thin pass-through to app.get_current_shipment_leg_tracking_session with an identical grant set and an identical security mode (invoker), never a reimplementation.';

revoke execute on function app.get_current_shipment_leg_tracking_session(uuid) from public;
grant execute on function app.get_current_shipment_leg_tracking_session(uuid) to authenticated, service_role;

revoke execute on function public.get_current_shipment_leg_tracking_session(uuid) from anon, authenticated, service_role, public;
grant execute on function public.get_current_shipment_leg_tracking_session(uuid) to authenticated, service_role;
