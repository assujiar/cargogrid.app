-- CG-AUDIT-2026-09-02 O1-query-layer remediation -- cluster 3 (operations-tms-core)
-- batch 2: milestone codes, leg tracking policy/session, and multi-leg shipment
-- reads. Continues the same Design->Verify->Fix adversarial pipeline established
-- by clusters 0-2 and cluster 3 batch 1: supabase/config.toml's `schemas =
-- ["public", "graphql_public"]` never exposes the "app" Postgres schema to
-- PostgREST, so every `.from()` read against an `app.*` table in
-- server/queries/*.ts has never worked in production.
--
-- Closes 6 call sites across 3 files / 6 tables:
--   app.milestone_codes                        server/queries/milestone-management.ts
--   app.shipment_leg_tracking_policies          server/queries/mile-orchestration.ts
--   app.shipment_leg_tracking_sessions          server/queries/mile-orchestration.ts
--   app.shipment_legs                           server/queries/multi-leg-shipment.ts
--   app.shipment_leg_cargo_allocations          server/queries/multi-leg-shipment.ts
--   app.shipment_leg_custody_events             server/queries/multi-leg-shipment.ts
--
-- 6 new function pairs (12 functions total). Two DIFFERENT security postures are
-- used in this single migration, both independently verified correct for their
-- own table's own real authority shape (see each part's own header for the full
-- reasoning):
--   * PART 1 (app.milestone_codes, app.shipment_leg_tracking_policies, app.
--     shipment_leg_tracking_sessions): SECURITY INVOKER, zero actor parameter --
--     app.milestone_codes is a genuinely non-tenant-scoped, `using (true)`
--     reference table (mirroring cluster 1 batch 1's app.list_finance_currencies
--     precedent); the two leg-tracking functions mirror this exact table
--     family's own pre-existing, already-live sibling read
--     (app.get_shipment_leg_tracking_sessions), which is itself SECURITY INVOKER
--     with no actor parameter. The verify pass independently confirmed this is
--     safe despite `service_role`'s own BYPASSRLS: `service_role` already holds
--     a direct SELECT grant on all 3 tables (independent of these new
--     functions), so no new capability is created, and for a genuine
--     `authenticated` caller INVOKER is the MOST faithful reproduction of the
--     original (never-reachable) RLS-scoped read -- there is no separate
--     "claimed actor" decoupled from session identity for RULE A to protect
--     against, unlike cluster 3 batch 1's dispatch functions.
--   * PART 2 (app.shipment_legs, app.shipment_leg_cargo_allocations, app.
--     shipment_leg_custody_events): SECURITY DEFINER + explicit
--     p_actor_auth_user_id (RULE A), the dominant convention across this whole
--     series -- these tables' own RLS policies vary per shipment order
--     (tenant/owner/org-unit scope resolved via a 1- or 2-hop join to app.
--     shipment_orders), so an INVOKER function would leak unfiltered rows to a
--     `service_role` caller under BYPASSRLS, exactly the failure mode cluster 3
--     batch 1's own migration already identified and fixed for its dispatch
--     functions.
--
-- Both drafts were produced independently and each passed its own adversarial
-- verify pass, all claims (RULE B predicates, RULE C helper citations, table
-- grants, column lists, unique constraints) independently re-derived from
-- primary sources before this migration was ever applied to any database.
--
-- ===========================================================================
-- PART 1 of 2: MILESTONE CODES + LEG TRACKING (milestone-management.ts,
-- mile-orchestration.ts)
-- ===========================================================================

-- CG-AUDIT-2026-09-02 O1-query-layer remediation -- cluster 3 batch 2, Part 1 of 2
-- (milestone codes + leg tracking). Continues the same Design->Verify->Fix
-- adversarial pipeline established by clusters 0-2 and cluster 3 batch 1 (RULE
-- A/B/C baked into every function below). supabase/config.toml only exposes
-- "public"/"graphql_public" to PostgREST, so every
-- .from() read against the "app" schema has never worked in production. This batch
-- closes 3 broken .from() call sites across 2 files / 3 tables:
--
--   server/queries/milestone-management.ts:32   listMilestoneCodes
--     .from("milestone_codes").select("*").order("name")
--   server/queries/mile-orchestration.ts:33      getShipmentLegTrackingPolicy
--     .from("shipment_leg_tracking_policies").select("*").eq("shipment_leg_id", shipmentLegId).maybeSingle()
--   server/queries/mile-orchestration.ts:54      getCurrentShipmentLegTrackingSession
--     .from("shipment_leg_tracking_sessions").select("*").eq("shipment_leg_id", shipmentLegId).eq("is_current", true).maybeSingle()
--
-- 3 new app.*/public.* Option-2 wrapper function pairs:
--   app.milestone_codes (BASE TABLE):                app.list_milestone_codes
--   app.shipment_leg_tracking_policies (BASE TABLE):  app.get_shipment_leg_tracking_policy
--   app.shipment_leg_tracking_sessions (BASE TABLE):  app.get_current_shipment_leg_tracking_session
--
-- ===========================================================================
-- Design decision 1 -- app.list_milestone_codes: SECURITY INVOKER, zero actor
-- parameter, mirroring cluster 1 batch 1's app.list_finance_currencies /
-- app.list_finance_rounding_modes precedent (supabase/migrations/
-- 20260910000000_close_o1_query_layer_cluster1_batch1_finance_reads.sql:1140-1172),
-- NOT the otherwise-universal SECURITY DEFINER + p_actor_auth_user_id shape.
--
-- Independently confirmed before drafting (per the task's own research steps),
-- not assumed from the stale TS comment:
--   * app.milestone_codes' table definition (supabase/migrations/
--     20260727140000_create_operations_milestone_management.sql:60-70) carries no
--     tenant_id, no owner_user_id, no org_unit_id column at all -- structurally
--     incapable of per-row/per-tenant variance.
--   * Its own comment on table (same file, line 72-73) calls it "the permanent,
--     platform-wide canonical milestone code registry ... is_customer_visible/
--     affects_eta/is_terminal are permanent properties of the code itself -- never
--     overridden per-tenant".
--   * Its one and only SELECT policy, milestone_codes_select_authenticated (same
--     file, line 672-674), is a bare `using (true)` for role authenticated -- no
--     later alter of this policy exists anywhere in supabase/migrations (repo-wide
--     grep of the policy name, sorted by filename, finds only this one
--     declaration -- RULE B satisfied trivially: the original declaration already
--     IS the current predicate).
--   * Its own grants (same file, line 702-703): `grant select on
--     app.milestone_codes to authenticated, service_role;` / `grant insert,
--     update, delete on app.milestone_codes to service_role;` -- an authenticated
--     caller already holds a direct table-level SELECT grant, so SECURITY INVOKER
--     mode needs nothing extra to work, exactly like app.finance_currencies'/
--     app.finance_rounding_modes' own grant shape.
--   * A second, independent migration (supabase/migrations/
--     20260907140000_fix_racy_resource_assignment_iss_e2.sql:28-42) separately
--     re-confirms in its own prose that "app.milestone_codes is a genuinely
--     platform-wide, non-tenant-scoped registry" while explaining why a baseline
--     seed was deliberately NOT added there -- independent corroboration of the
--     same non-tenant-scoped conclusion from an unrelated fix, not merely the
--     original table comment repeating itself.
-- Conclusion: this IS the same "global reference table, zero actor param, zero
-- tenant scoping" shape as app.list_finance_currencies/app.list_finance_rounding_modes/
-- app.list_api_versions/app.list_webhook_event_types. SECURITY DEFINER + an actor
-- parameter would be strictly more privilege than this read needs, and RULE A's
-- app.assert_actor_is_session_identity guard does not apply (no actor parameter
-- exists to protect against impersonation in the first place).
--
-- Also mirroring cluster 1 batch 1's own precedent exactly (not merely its general
-- shape): the app.* function itself carries NO `set search_path` clause at all
-- (only its public.* wrapper sets `search_path = pg_catalog, pg_temp`) -- verified
-- against app.list_finance_currencies'/app.list_finance_rounding_modes' own bodies,
-- neither of which sets search_path either. See the OPEN DESIGN QUESTION at the
-- bottom of this file: this differs from the mile-orchestration functions below,
-- which DO set `search_path = app, pg_temp` despite also being SECURITY INVOKER,
-- because their own closer sibling precedent (app.get_shipment_leg_tracking_sessions)
-- sets it. Both existing precedents are followed as given rather than picked from
-- a single self-invented universal rule.
--
-- ===========================================================================
-- Design decision 2 -- app.get_shipment_leg_tracking_policy /
-- app.get_current_shipment_leg_tracking_session: SECURITY INVOKER, zero actor
-- parameter, mirroring this exact table family's OWN existing read function,
-- app.get_shipment_leg_tracking_sessions (supabase/migrations/
-- 20260729330000_create_advanced_tms_mile_orchestration.sql:779-790), NOT its
-- sibling app.resolve_leg_tracking_policy (same file, line 336-442), which is a
-- SECURITY DEFINER + p_actor_auth_user_id computed projection over resource
-- assignments/device/provider eligibility -- a fundamentally different kind of
-- read (mile-orchestration.ts's own file header, lines 1-8, already draws this
-- exact line: "reads go directly against the base tables (RLS-scoped) except for
-- session history (app.get_shipment_leg_tracking_sessions) and policy resolution
-- (app.resolve_leg_tracking_policy, a computed projection requiring an actor
-- parameter, not a plain table read)"). Both getShipmentLegTrackingPolicy and
-- getCurrentShipmentLegTrackingSession ARE plain table reads (a `select *`
-- filtered by shipment_leg_id, one of them additionally by is_current), so
-- app.get_shipment_leg_tracking_sessions -- itself a plain `select *` filtered by
-- shipment_leg_id against the exact same app.shipment_leg_tracking_sessions table
-- -- is the direct, same-table-family precedent to mirror, not
-- app.resolve_leg_tracking_policy.
--
-- Independently confirmed before drafting:
--   * app.shipment_leg_tracking_policies' table definition (supabase/migrations/
--     20260729330000_create_advanced_tms_mile_orchestration.sql:81-117) is scoped
--     only via shipment_leg_id -> app.shipment_legs -> shipment_order_id ->
--     app.shipment_orders (tenant_id/owner_user_id/org_unit_id); it carries its
--     own tenant_id column (denormalized) but no owner_user_id/org_unit_id of its
--     own, so row visibility is necessarily resolved through the shipment order,
--     exactly as its own RLS policy already does (see below).
--   * app.shipment_leg_tracking_sessions' table definition (same file, line
--     141-168) is scoped the identical way (shipment_leg_id -> ... ->
--     shipment_order_id -> app.shipment_orders), with a partial unique index
--     shipment_leg_tracking_sessions_current_leg_unique on (shipment_leg_id) WHERE
--     is_current (line 174) -- confirming at most one is_current=true row can ever
--     exist per leg, so `getCurrentShipmentLegTrackingSession`'s
--     is_current-filtered read is structurally bounded to 0-or-1 rows by the
--     database itself, independent of this function's own logic. Likewise
--     shipment_leg_tracking_policies_shipment_leg_unique (line 103) bounds
--     getShipmentLegTrackingPolicy's own read to 0-or-1 rows.
--   * Their SELECT policies (same file):
--       shipment_leg_tracking_policies_select_scoped (line 795-804):
--         for select to authenticated using (
--           exists (
--             select 1 from app.shipment_legs sl
--             join app.shipment_orders so on so.id = sl.shipment_order_id
--             where sl.id = shipment_leg_tracking_policies.shipment_leg_id
--               and app.can_access_record((select auth.uid()), so.tenant_id, so.owner_user_id, app.lead_record_scope_org_unit_ids(so.org_unit_id), null)
--           )
--         );
--       shipment_leg_tracking_sessions_select_scoped (line 806-815): identical
--         shape, exists-joining through app.shipment_legs/app.shipment_orders the
--         same way. Repo-wide grep of both policy names (sorted by filename)
--         finds only these single declarations each -- no later alter of either
--         policy exists anywhere in supabase/migrations. RULE B satisfied: these
--         ARE the current predicates, reproduced verbatim below via the identical
--         exists-join shape (not re-derived independently).
--   * Their own grants (same file, line 819-822): `grant select on
--     app.shipment_leg_tracking_policies to authenticated, service_role;` /
--     `grant select on app.shipment_leg_tracking_sessions to authenticated,
--     service_role;` -- an authenticated caller already holds the table-level
--     SELECT grant these SECURITY INVOKER functions need.
--   * app.get_shipment_leg_tracking_sessions' own body and comment (same file,
--     line 779-790): `language sql stable security invoker set search_path = app,
--     pg_temp` wrapping a bare `select * from app.shipment_leg_tracking_sessions
--     where shipment_leg_id = p_shipment_leg_id order by started_at asc;`, its own
--     comment reading "security invoker (relies on the caller's own RLS on
--     app.shipment_leg_tracking_sessions)". This is the exact authority pattern
--     mirrored below: the function itself performs zero authority check of its
--     own and takes zero actor parameter; it relies entirely on the calling
--     role's own RLS evaluation (invoker mode means `(select auth.uid())` inside
--     the policy resolves to the REAL calling user's session, not this function's
--     definer). Confirmed via the existing public.get_shipment_leg_tracking_sessions
--     wrapper (supabase/migrations/20260826000000_create_public_api_data_wrappers.sql:
--     16912-16920) that this exact invoker shape already round-trips correctly
--     through an Option-2 public.* wrapper in this same table family today.
--   * app.resolve_leg_tracking_policy's own body (same file, line 336-442) was
--     read in full per RULE C (its only `create function`, no later `create or
--     replace` exists anywhere -- confirmed via repo-wide case-insensitive grep)
--     to confirm it is NOT the shape to mirror for a plain read: it is `security
--     definer` with an explicit `p_actor_auth_user_id` parameter, calls
--     `app.can_access_record(p_actor_auth_user_id, ...)` directly against that
--     parameter, and RAISEs on both leg_not_found and insufficient_authority --
--     none of which fits this task's own RAISE-vs-silent-zero-rows instruction
--     for these 2 functions (silent null/no-row, matching the replaced
--     .maybeSingle() calls' own current behavior, never a new RAISE). Also
--     separately disclosed below: this existing function predates RULE A and
--     does NOT call app.assert_actor_is_session_identity on its own
--     p_actor_auth_user_id -- an out-of-scope pre-existing gap in a function this
--     batch does not touch, flagged per this series' own disclosure convention,
--     not fixed here.
--
-- No RULE A guard needed on any of the 3 new functions below: none of them takes
-- an actor parameter (the INVOKER + real-RLS shape makes one unnecessary), so
-- there is no explicit identity claim for app.assert_actor_is_session_identity to
-- cross-check.
--
-- OPEN DESIGN QUESTIONS / RISKS FOR THE VERIFY PASS (flagged deliberately, not
-- silently resolved by this draft):
--   1. search_path inconsistency across the two precedents actually followed:
--      app.list_milestone_codes sets NO search_path (matching app.list_finance_currencies
--      exactly), while app.get_shipment_leg_tracking_policy/
--      app.get_current_shipment_leg_tracking_session DO set `search_path = app,
--      pg_temp` (matching app.get_shipment_leg_tracking_sessions exactly). This
--      draft intentionally follows each function's own closest existing sibling
--      rather than picking one rule across all 3 -- verify pass should confirm
--      this is the right call rather than a drafting inconsistency, and decide
--      whether either existing precedent (not touched by this batch) should
--      itself be reconciled separately.
--   2. [RESOLVED, verify pass] SECURITY INVOKER-vs-DEFINER, addressed point-blank
--      against the BYPASSRLS question cluster 3 batch 1's own migration raised for
--      a DIFFERENT set of functions (its dispatch count/list functions), rather
--      than left implicit. `service_role` genuinely has BYPASSRLS in this project
--      (independently re-confirmed: 20260716075355_create_tenants.sql:230,
--      20260716113048_create_audit_trail.sql:446-447, empirically verified via
--      `select rolbypassrls from pg_roles`), so an INVOKER function called by a
--      `service_role` session skips RLS evaluation entirely for
--      shipment_leg_tracking_policies_select_scoped/shipment_leg_tracking_sessions_
--      select_scoped, exactly as cluster 3 batch 1's own reasoning describes for
--      its own dispatch functions. The two cases are NOT analogous, though, and
--      the distinction matters: cluster 3 batch 1's dispatch functions take an
--      EXPLICIT `p_actor_auth_user_id` parameter DECOUPLED from the calling
--      session's own identity, because `service_role` is expected to call those
--      RPCs ON BEHALF OF an arbitrary end user it has already authenticated by
--      some other means (a server-side route with no Supabase Auth session of its
--      own) -- under INVOKER, `service_role` has no session `auth.uid()` to filter
--      by at all, so the actor-scoping the RPC exists to provide would be silently
--      lost for exactly the caller class (`service_role`) that most needs it. The
--      two functions here take NO actor parameter and never will: they mirror
--      `app.get_shipment_leg_tracking_sessions`'s OWN pre-existing, already-live
--      design (not invented by this batch), and for a genuine `authenticated`
--      caller, INVOKER is the MOST faithful reproduction of the original (never-
--      actually-reachable) `.from().maybeSingle()` intent -- RLS evaluates against
--      the real session identity directly, with no separate "claimed actor" for
--      RULE A to even need to protect. For `service_role`, BYPASSRLS grants no NEW
--      capability this function did not already hand it: `service_role` already
--      holds a direct `grant select` on both base tables (confirmed above,
--      20260729330000:819/821) AND already has BYPASSRLS independent of this
--      function's existence, so it could already read any row of either table via
--      a bare `select` today, with or without this RPC. Exposing that same,
--      already-existing access through a `public.*` wrapper adds no new attack
--      surface: `service_role` is this project's own fully-trusted backend
--      identity (holding the service-role secret key is already
--      root-equivalent for this schema), never an identity an `authenticated`
--      end-user session can forge into. Conclusion: SECURITY INVOKER is correct
--      and safe for both functions, matching their own direct sibling precedent
--      exactly -- not changed to SECURITY DEFINER.
--   2b. SECURITY INVOKER correctness also depends on the underlying table-level
--      SELECT grant staying intact and RLS remaining enabled as already
--      configured -- independently re-confirmed via a repo-wide grep for any
--      `revoke ... on app.milestone_codes|app.shipment_leg_tracking_policies|
--      app.shipment_leg_tracking_sessions` statement (a different statement type
--      than the ALTER POLICY grep already run): zero hits beyond the two ISS-2026-
--      309-driven `public.*` wrapper revokes this draft itself adds. No later
--      migration revoked or narrowed any of the 3 tables' own SELECT grants.
--   3. app.resolve_leg_tracking_policy's own missing RULE A guard (see above) is
--      a real, pre-existing, out-of-scope gap -- recorded here per this series'
--      disclosure convention so it is not silently rediscovered, matching cluster
--      1 batch 1's own disclosed out-of-scope findings.
--   4. `returns app.<table>` (non-SETOF composite) for the two mile-orchestration
--      functions relies on documented Postgres SQL-function semantics (a
--      non-SETOF SQL function's underlying query returning zero rows yields a
--      NULL result) plus each table's own partial/plain unique index bounding
--      the filtered read to 0-or-1 rows -- verify pass should double check the
--      TS layer's defensive `Array.isArray(data) ? data[0] : data` idiom (already
--      established at server/queries/actual-cost.ts:29-38 for a `returns table
--      (...)` function) is applied in the TS integration below regardless, so
--      behavior is correct under either wire shape PostgREST/pg RPC could
--      plausibly return for a non-SETOF composite result.
-- ===========================================================================

-- ===========================================================================
-- 1. app.list_milestone_codes -- replaces server/queries/
--    milestone-management.ts:32 (listMilestoneCodes)
-- ===========================================================================
-- Replaces: `.from("milestone_codes").select("*").order("name")`.
create function app.list_milestone_codes()
returns setof app.milestone_codes
language sql
stable
as $$
  select * from app.milestone_codes order by name asc;
$$;

comment on function app.list_milestone_codes() is
  'OPS-173/O1 remediation: the full, platform-wide registered milestone code catalogue, name ascending, replacing server/queries/milestone-management.ts:32''s broken .from("milestone_codes").select("*").order("name") (app is not exposed to PostgREST). Zero parameters, zero in-function authority check -- app.milestone_codes carries no tenant_id/owner_user_id/org_unit_id column at all (20260727140000_create_operations_milestone_management.sql:60-70) and its own only-ever-declared SELECT policy, milestone_codes_select_authenticated, is a bare `using (true)` for role authenticated (same file, line 672-674; no later alter of this policy exists anywhere in supabase/migrations, confirmed by repo-wide grep of the policy name). Deliberately `security invoker` (the unmarked default), not `security definer`: this function runs as the real calling role, which already holds a direct `grant select on app.milestone_codes to authenticated, service_role` (same file, line 702) -- matching this codebase''s own established shape for a zero-actor-param global reference table (app.list_finance_currencies/app.finance_currencies, app.list_finance_rounding_modes/app.finance_rounding_modes, app.list_api_versions/app.api_versions, app.list_webhook_event_types/app.webhook_event_types, all unmarked-invoker over an identical bare-true/authenticated-grant table shape). No RULE A actor-impersonation guard: this function takes no actor parameter, so there is no identity claim for app.assert_actor_is_session_identity to cross-check. No `set search_path` on this function itself, mirroring app.list_finance_currencies''/app.list_finance_rounding_modes'' own bodies (20260910000000_close_o1_query_layer_cluster1_batch1_finance_reads.sql:1140-1146, 1178-1184) exactly -- only the public.* wrapper below sets one. Returns exactly the 8-column shape server/contracts/milestone-management/milestone-management.ts''s parseMilestoneCode consumes (code, name, category, is_customer_visible, affects_eta, is_terminal, registered_by, created_at) -- identical to the replaced `select *`, ordered the same way (`order("name")`, ascending, the driver''s own default).';

-- Option-2 wrapper: app is not exposed to PostgREST; this is a thin pass-through
-- to app.list_milestone_codes with an identical grant set and an identical
-- security mode (invoker, matching its app.* counterpart -- never a
-- reimplementation, and never a privilege upgrade the app.* function itself does
-- not have).
create function public.list_milestone_codes()
returns setof app.milestone_codes
language sql
stable
set search_path = pg_catalog, pg_temp
as $wrap$
  select * from app.list_milestone_codes();
$wrap$;

comment on function public.list_milestone_codes() is
  'Option-2 wrapper: app is not exposed to PostgREST; this is a thin pass-through to app.list_milestone_codes with an identical grant set and an identical security mode (invoker), never a reimplementation.';

revoke execute on function app.list_milestone_codes() from public;
grant execute on function app.list_milestone_codes() to authenticated, service_role;

-- Option-2 wrapper grant, corrected per ISS-2026-309 (a bare `revoke ... from
-- public` does not undo this project's own ALTER DEFAULT PRIVILEGES ... GRANT
-- EXECUTE ON FUNCTIONS TO anon, authenticated bootstrap grant on the public
-- schema).
revoke execute on function public.list_milestone_codes() from anon, authenticated, service_role, public;
grant execute on function public.list_milestone_codes() to authenticated, service_role;

-- ===========================================================================
-- 2. app.get_shipment_leg_tracking_policy -- replaces server/queries/
--    mile-orchestration.ts:33 (getShipmentLegTrackingPolicy)
-- ===========================================================================
-- Replaces: `.from("shipment_leg_tracking_policies").select("*")
-- .eq("shipment_leg_id", shipmentLegId).maybeSingle()`.
create function app.get_shipment_leg_tracking_policy(p_shipment_leg_id uuid)
returns app.shipment_leg_tracking_policies
language sql
stable
security invoker
set search_path = app, pg_temp
as $$
  select * from app.shipment_leg_tracking_policies where shipment_leg_id = p_shipment_leg_id;
$$;

comment on function app.get_shipment_leg_tracking_policy(uuid) is
  'ATW-225/O1 remediation: the one tracking policy for a leg, if defined yet, replacing server/queries/mile-orchestration.ts:33''s broken .from("shipment_leg_tracking_policies").select("*").eq("shipment_leg_id", shipmentLegId).maybeSingle() (app is not exposed to PostgREST). Security invoker, zero actor parameter -- mirrors this exact table family''s own existing plain-read function, app.get_shipment_leg_tracking_sessions (20260729330000_create_advanced_tms_mile_orchestration.sql:779-790, "security invoker (relies on the caller''s own RLS)"), rather than its sibling app.resolve_leg_tracking_policy (same file, line 336-442), which is a SECURITY DEFINER computed projection over resource-assignment/device/provider eligibility, not a plain table read (mile-orchestration.ts''s own file header already draws this line). Relies entirely on the calling role''s own RLS evaluation of shipment_leg_tracking_policies_select_scoped (same file, line 795-804: an exists-join through app.shipment_legs/app.shipment_orders scoped via app.can_access_record((select auth.uid()), so.tenant_id, so.owner_user_id, app.lead_record_scope_org_unit_ids(so.org_unit_id), null)) -- reproduced verbatim, not re-derived, and confirmed via repo-wide grep of the policy name that no later alter of it exists anywhere in supabase/migrations. The real calling role already holds a direct `grant select on app.shipment_leg_tracking_policies to authenticated, service_role` (same file, line 819). No RULE A guard: no actor parameter exists to protect -- invoker mode means the policy''s own `(select auth.uid())` already resolves to the real caller, never a value this function could itself be tricked into trusting. shipment_leg_tracking_policies_shipment_leg_unique (same file, line 103) bounds this read to 0-or-1 rows at the database level, matching `returns app.shipment_leg_tracking_policies` (non-setof: zero matching rows yields a null result, one row is returned as-is) -- Postgres itself would raise if the unique constraint were ever violated, so no additional LIMIT/ORDER BY is needed. Returns null (never an exception) for a nonexistent shipment_leg_id, a leg with no policy defined yet, or an actor who cannot reach that leg''s shipment order''s tenant/owner/org-unit scope -- matching the original RLS-filtered `.maybeSingle()` call''s own current null-on-miss behavior, unchanged.';

-- Option-2 wrapper: app is not exposed to PostgREST; this is a thin pass-through
-- to app.get_shipment_leg_tracking_policy with an identical grant set and an
-- identical security mode (invoker, matching its app.* counterpart).
create function public.get_shipment_leg_tracking_policy(p_shipment_leg_id uuid)
returns app.shipment_leg_tracking_policies
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
-- 3. app.get_current_shipment_leg_tracking_session -- replaces server/queries/
--    mile-orchestration.ts:54 (getCurrentShipmentLegTrackingSession)
-- ===========================================================================
-- Replaces: `.from("shipment_leg_tracking_sessions").select("*")
-- .eq("shipment_leg_id", shipmentLegId).eq("is_current", true).maybeSingle()`.
create function app.get_current_shipment_leg_tracking_session(p_shipment_leg_id uuid)
returns app.shipment_leg_tracking_sessions
language sql
stable
security invoker
set search_path = app, pg_temp
as $$
  select * from app.shipment_leg_tracking_sessions where shipment_leg_id = p_shipment_leg_id and is_current = true;
$$;

comment on function app.get_current_shipment_leg_tracking_session(uuid) is
  'ATW-225/O1 remediation: the current (is_current) tracking session for a leg, if any, replacing server/queries/mile-orchestration.ts:54''s broken .from("shipment_leg_tracking_sessions").select("*").eq("shipment_leg_id", shipmentLegId).eq("is_current", true).maybeSingle() (app is not exposed to PostgREST). Security invoker, zero actor parameter, same table and same authority shape as its own sibling read app.get_shipment_leg_tracking_sessions (20260729330000_create_advanced_tms_mile_orchestration.sql:779-790: `select * from app.shipment_leg_tracking_sessions where shipment_leg_id = p_shipment_leg_id order by started_at asc`, "security invoker (relies on the caller''s own RLS)") -- this function is that same read narrowed to the one is_current row, not a different authority pattern. Relies entirely on the calling role''s own RLS evaluation of shipment_leg_tracking_sessions_select_scoped (same file, line 806-815: an exists-join through app.shipment_legs/app.shipment_orders scoped via app.can_access_record((select auth.uid()), so.tenant_id, so.owner_user_id, app.lead_record_scope_org_unit_ids(so.org_unit_id), null)) -- reproduced verbatim, not re-derived, and confirmed via repo-wide grep of the policy name that no later alter of it exists anywhere in supabase/migrations. The real calling role already holds a direct `grant select on app.shipment_leg_tracking_sessions to authenticated, service_role` (same file, line 821). No RULE A guard: no actor parameter exists to protect. The partial unique index shipment_leg_tracking_sessions_current_leg_unique on (shipment_leg_id) where is_current (same file, line 174) bounds this read to 0-or-1 rows at the database level, matching `returns app.shipment_leg_tracking_sessions` (non-setof: zero matching rows yields a null result, one row is returned as-is). Returns null (never an exception) for a nonexistent shipment_leg_id, a leg with no current session (none ever started, or the last one already ended with is_current left false), or an actor who cannot reach that leg''s shipment order''s tenant/owner/org-unit scope -- matching the original RLS-filtered `.maybeSingle()` call''s own current null-on-miss behavior, unchanged.';

-- Option-2 wrapper: app is not exposed to PostgREST; this is a thin pass-through
-- to app.get_current_shipment_leg_tracking_session with an identical grant set
-- and an identical security mode (invoker, matching its app.* counterpart).
create function public.get_current_shipment_leg_tracking_session(p_shipment_leg_id uuid)
returns app.shipment_leg_tracking_sessions
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

-- ===========================================================================
-- TS INTEGRATION:
-- Exact, mechanical instructions for a later step to apply against
-- server/queries/milestone-management.ts and server/queries/mile-orchestration.ts.
-- Neither target function's call SIGNATURE gains a new parameter (no actor id is
-- introduced anywhere in this batch) -- all 3 changes are NON-BREAKING to callers:
-- only each function's OWN internal client-method call (`.from()` -> `.rpc()`)
-- and its client TYPE POSITION change; every existing call site
-- (app/(tenant)/[tenantSlug]/operations/shipment-orders/[shipmentOrderId]/page.tsx:
-- 188, 272, 280) keeps passing the exact same arguments it does today.
--
-- ---------------------------------------------------------------------------
-- File 1/2: server/queries/milestone-management.ts
-- ---------------------------------------------------------------------------
-- 1. Client type: `MilestoneManagementQueryTableClient` (currently `Pick<
--    SupabaseClient, "from">`, line 21) changes to `Pick<SupabaseClient, "rpc">`.
--    Keep the TYPE NAME unchanged (only its definition narrows) -- it is imported
--    by name in server/queries/milestone-management.test.ts:9, and renaming it
--    would be a gratuitous second breaking change on top of the fake-shape change
--    below. NON-BREAKING for the real caller (SupabaseClient always has both
--    `from` and `rpc`); BREAKING only for any fake/mock client that implements
--    solely `from()` for this type (see test note below).
--
--      export type MilestoneManagementQueryTableClient = Pick<SupabaseClient, "rpc">;
--
-- 2. `listMilestoneCodes` (line 31-37) body changes from a `.from()` table read
--    to a `.rpc()` call; the function's own exported SIGNATURE
--    (`(client: MilestoneManagementQueryTableClient) => Promise<MilestoneCode[]>`)
--    is UNCHANGED -- no new parameter, no actor id. New body:
--
--      export async function listMilestoneCodes(client: MilestoneManagementQueryTableClient): Promise<MilestoneCode[]> {
--        const { data, error } = await client.rpc("list_milestone_codes");
--        if (error) {
--          throw new MilestoneManagementQueryError(error.message);
--        }
--        return (data ?? []).map((row: Record<string, unknown>) => parseMilestoneCode(row));
--      }
--
--    (Only the `.from(...)` line inside the function body actually changes; the
--    error-check and `.map(parseMilestoneCode)` lines are byte-identical to
--    today.) Update the function's own leading comment (line 30) too: it
--    currently reads "... RLS-scoped select to authenticated (reference data,
--    true for every row), no RPC needed" -- that last clause is now wrong (an RPC
--    IS needed, because app is not exposed to PostgREST) and should be corrected,
--    e.g. to: "The full, platform-wide registered milestone code catalogue --
--    zero-actor-param, SECURITY INVOKER RPC over a bare `using (true)`-to-
--    authenticated reference table (app.list_milestone_codes)."
--
-- 3. Test file server/queries/milestone-management.test.ts: its `fakeTableClient`
--    helper (line 98) currently implements `.from()` and must instead implement
--    `.rpc()` returning `{ data, error }` directly (mirroring the existing
--    `fakeRpcClient` helper already defined in the same file at line 34-36, which
--    can likely be reused as-is/renamed rather than kept as a second near-
--    identical helper) and assert the call was made with fn `"list_milestone_codes"`
--    (with no args object, matching `app.list_finance_currencies()`'s own
--    zero-arg TS call convention at server/queries/currency-exchange-rate.ts:32).
--    Not applied here (out of this batch's stated scope), flagged so the later
--    mechanical-apply step does not skip it.
--
-- ---------------------------------------------------------------------------
-- File 2/2: server/queries/mile-orchestration.ts
-- ---------------------------------------------------------------------------
-- 1. Client type: `MileOrchestrationQueryTableClient` (currently `Pick<
--    SupabaseClient, "from" | "rpc">`, line 22) narrows to `Pick<SupabaseClient,
--    "rpc">` -- after this batch, ALL FOUR functions in this file (including the
--    already-RPC-backed `listShipmentLegTrackingSessions`/`resolveLegTrackingPolicy`)
--    use only `.rpc()`; `.from()` becomes entirely unused in this file. Keep the
--    TYPE NAME unchanged for the same import-stability reason as above (used by
--    name in server/queries/mile-orchestration.test.ts:4). NON-BREAKING for the
--    real caller; BREAKING only for fake/mock clients implementing solely
--    `from()` for this type.
--
--      export type MileOrchestrationQueryTableClient = Pick<SupabaseClient, "rpc">;
--
-- 2. `getShipmentLegTrackingPolicy` (line 32-41): SIGNATURE UNCHANGED
--    (`(client: MileOrchestrationQueryTableClient, shipmentLegId: string) =>
--    Promise<ShipmentLegTrackingPolicy | null>`). New body:
--
--      export async function getShipmentLegTrackingPolicy(client: MileOrchestrationQueryTableClient, shipmentLegId: string): Promise<ShipmentLegTrackingPolicy | null> {
--        const { data, error } = await client.rpc("get_shipment_leg_tracking_policy", { p_shipment_leg_id: shipmentLegId });
--        if (error) {
--          throw new MileOrchestrationQueryError(error.message);
--        }
--        const row = Array.isArray(data) ? data[0] : data;
--        return row ? parseShipmentLegTrackingPolicy(row as Record<string, unknown>) : null;
--      }
--
--    (The `Array.isArray(data) ? data[0] : data` defensive unwrap mirrors the
--    already-established idiom at server/queries/actual-cost.ts:29-38 for a
--    similar single-row RPC result, and covers both a bare composite-object wire
--    shape and a one-element-array wire shape without needing to pin down which
--    one PostgREST/pg RPC actually returns for a non-SETOF composite return type
--    -- see OPEN DESIGN QUESTION 4 above.)
--
-- 3. `getCurrentShipmentLegTrackingSession` (line 53-62): SIGNATURE UNCHANGED
--    (`(client: MileOrchestrationQueryTableClient, shipmentLegId: string) =>
--    Promise<ShipmentLegTrackingSession | null>`). New body:
--
--      export async function getCurrentShipmentLegTrackingSession(client: MileOrchestrationQueryTableClient, shipmentLegId: string): Promise<ShipmentLegTrackingSession | null> {
--        const { data, error } = await client.rpc("get_current_shipment_leg_tracking_session", { p_shipment_leg_id: shipmentLegId });
--        if (error) {
--          throw new MileOrchestrationQueryError(error.message);
--        }
--        const row = Array.isArray(data) ? data[0] : data;
--        return row ? parseShipmentLegTrackingSession(row as Record<string, unknown>) : null;
--      }
--
-- 4. `listShipmentLegTrackingSessions` and `resolveLegTrackingPolicy` (line
--    44-50, 65-80): UNCHANGED -- already RPC-backed, not touched by this batch.
--
-- 5. File header comment (line 1-8): currently reads "reads go directly against
--    the base tables (RLS-scoped) except for session history ... and policy
--    resolution ..., not a plain table read" -- this is now wrong for 2 of the 4
--    functions and should be corrected, e.g.: "reads go through
--    app.get_shipment_leg_tracking_policy / app.get_current_shipment_leg_tracking_session
--    (plain, security-invoker, RLS-scoped single-row reads) or
--    app.get_shipment_leg_tracking_sessions (session history) or
--    app.resolve_leg_tracking_policy (a computed projection requiring an actor
--    parameter) -- app is not exposed to PostgREST, so none of these are reachable
--    via .from()."
--
-- 6. Test file server/queries/mile-orchestration.test.ts: its 3
--    `getShipmentLegTrackingPolicy` test cases (line 11-104) currently build a
--    fake client implementing `.from()` (with `.rpc()` stubbed to throw "not
--    used") -- these must invert to implement `.rpc()` (asserting fn ===
--    "get_shipment_leg_tracking_policy" and args.p_shipment_leg_id === LEG_ID,
--    mirroring the existing `resolveLegTrackingPolicy` describe block's own fake
--    shape at line 106-149) with `.from()` stubbed to throw instead. No existing
--    test covers `getCurrentShipmentLegTrackingSession` at all -- a new describe
--    block for it (mirroring the corrected `getShipmentLegTrackingPolicy` shape)
--    should be added, not merely a fixed existing one. Not applied here (out of
--    this batch's stated scope), flagged so the later mechanical-apply step does
--    not skip it.
-- ===========================================================================

-- ===========================================================================
-- PART 2 of 2: MULTI-LEG SHIPMENT (multi-leg-shipment.ts)
-- ===========================================================================

-- CG-AUDIT-2026-09-02 O1-query-layer remediation -- cluster 3 (operations-tms-core)
-- batch 2, Part 2 of 2 (multi-leg shipment). Continues the same
-- Design->Verify->Fix adversarial pipeline established for cluster 0 (batches 1-5),
-- cluster 1 (batch 1), cluster 2 (batch 1), and cluster 3 batch 1 (dispatch/job
-- order views): supabase/config.toml's `schemas = ["public", "graphql_public"]`
-- never exposes the "app" Postgres schema to PostgREST, so every `.from()` read
-- against an `app.*` table in server/queries/*.ts has NEVER worked in production.
-- The fix is the Option-2 wrapper: a new `app.<name>` SECURITY DEFINER function
-- reproducing the read plus its RLS-equivalent authority check in SQL, a thin
-- `public.<name>` pass-through (the only PostgREST-reachable surface), then the TS
-- caller switches `.from()` -> `.rpc()`.
--
-- Closes 3 broken call sites, all in server/queries/multi-leg-shipment.ts (ATW-221,
-- CG-S10-ATW-002):
--   app.shipment_legs (base table)                  listShipmentLegs, lines 33-39
--   app.shipment_leg_cargo_allocations (base table)  getShipmentLegCargoAllocation, lines 51-60
--   app.shipment_leg_custody_events (base table)     listShipmentLegCustodyEvents, lines 63-69
--
-- This file's own two OTHER exported functions in the same TS module,
-- listShipmentLegStops and getShipmentLegNetworkState, are already `.rpc()`-backed
-- (app.get_shipment_leg_stops, app.get_shipment_leg_network_state) and are
-- deliberately OUT OF SCOPE here -- this batch touches neither function's own SQL,
-- only reads both bodies as research precedent (see PRECEDENT DIVERGENCE below for
-- why neither is actually followed verbatim).
--
-- 3 new function pairs (6 functions total):
--   app.list_shipment_legs / public.list_shipment_legs
--   app.get_shipment_leg_cargo_allocation / public.get_shipment_leg_cargo_allocation
--   app.list_shipment_leg_custody_events / public.list_shipment_leg_custody_events
--
-- ===========================================================================
-- PRECEDENT DIVERGENCE -- why this draft does NOT copy either cited existing
-- function's own authority mechanism verbatim, despite both being direct family
-- members of the same table group
-- ===========================================================================
-- The task brief that produced this draft named app.get_shipment_leg_stops and
-- app.get_shipment_leg_network_state as the two functions to read for precedent.
-- Both were read in full, against their own MOST RECENT definition (RULE C) --
-- neither turns out to be a safe template to copy verbatim, for two different
-- reasons, disclosed here rather than silently deviated from:
--
-- * app.get_shipment_leg_stops (20260729290000:928-959, never replaced since --
--   repo-wide grep for "create or replace function app.get_shipment_leg_stops"
--   finds zero hits; the original "create function" is still its current body) is
--   SECURITY INVOKER, not SECURITY DEFINER, and takes NO p_actor_auth_user_id
--   parameter at all -- it relies entirely on the caller's own live RLS on
--   app.shipment_leg_stops. It is reachable today only via public.get_shipment_leg_
--   stops (20260826000000:16896-16910), which IS security definer. A SECURITY
--   INVOKER function called from inside a SECURITY DEFINER function does not run as
--   the original end-user session -- it runs as whatever role is "current user" at
--   that point in the call stack, which after entering a SECURITY DEFINER function
--   is that function's OWNER, not the original caller. None of the tables in this
--   family carry `FORCE ROW LEVEL SECURITY` (repo-wide grep for that exact phrase
--   across every migration: zero hits), so a table owner calling into its own table
--   bypasses row security entirely by ordinary Postgres semantics, independent of
--   this migration's own author having realized that shipment_leg_stops_select_
--   scoped exists at all. Whether this specific composition actually leaks in
--   practice depends on which role owns public.get_shipment_leg_stops -- not
--   re-derived here, since app.get_shipment_leg_stops itself is explicitly out of
--   this batch's scope (it is not one of the three broken call sites this task was
--   given) -- but it means this function's own OWN authority posture is not
--   evidence of a safe pattern to imitate, and this draft does not imitate it.
--   **Flagged for the verify pass and for a future, separately-scoped item**: this
--   is a plausible real gap in an already-shipped function, not merely a stylistic
--   difference from the newer convention.
--
-- * app.get_shipment_leg_network_state (original 20260729290000:904-918, superseded
--   by 20260730460000:448-480's own `create or replace` -- repo-wide grep for
--   "get_shipment_leg_network_state" confirms no THIRD definition exists anywhere,
--   so 20260730460000's body is the true current one, RULE C) IS security definer,
--   but predates RULE A/RULE B as this series (cluster 0-3) has established them. It
--   takes no p_actor_auth_user_id parameter -- its only guard is `perform app.
--   assert_session_identity_in_tenant(v_tenant_id)`, a TENANT-membership-only check
--   resolved from the shipment order's own tenant_id, with no owner_user_id/org-
--   unit/customer-account scoping at all. That was a deliberate, narrower fix for a
--   narrower defect at the time (ATW-032/ISS-2026-033, "Group B: two readers whose
--   signature carries no tenant") -- it was never rewritten to the fuller app.can_
--   access_record shape this series' own ~55 prior functions all share, and it is
--   not the record-level RLS predicate that actually governs SELECT on app.
--   shipment_legs itself. Copying its authority MECHANISM into this draft's own
--   functions would under-scope every one of them relative to the real table
--   policies below. This draft therefore borrows ONLY the "one hop, no join needed"
--   observation the task brief was really pointing at (a shipment_order_id-scoped
--   read needs no intermediate join to reach app.shipment_orders, unlike a
--   shipment_leg_id-scoped read) -- not the assert_session_identity_in_tenant
--   mechanism itself.
--
-- The actual ground truth this draft follows instead, for all three functions, is
-- each table's own CURRENT row-security policy, confirmed directly (RULE B below)
-- -- which happens to already be phrased almost verbatim as this task brief's own
-- hinted shape, because app.shipment_leg_cargo_allocations_select_scoped and
-- app.shipment_leg_custody_events_select_scoped were themselves written, from day
-- one (20260729290000), as a two-hop join through app.shipment_legs to app.
-- shipment_orders -- there was never a need to reverse-engineer this shape from
-- get_shipment_leg_stops at all; it is independently, directly on the record.
--
-- ===========================================================================
-- RULE A (actor identity) -- signature change, not merely an addition
-- ===========================================================================
-- None of listShipmentLegs/getShipmentLegCargoAllocation/listShipmentLegCustodyEvents
-- takes an actor/auth-user-id parameter today -- RLS was the only authority check
-- before, evaluated against the session's own `auth.uid()`. Since each new app.*
-- function below is SECURITY DEFINER (required -- see SECURITY DEFINER vs INVOKER
-- below) and reachable by `authenticated`, RULE A requires an explicit
-- `p_actor_auth_user_id` parameter plus `perform app.assert_actor_is_session_
-- identity(p_actor_auth_user_id);` as the first executable statement, so a session
-- cannot claim to read on behalf of a different identity than its own. This is a
-- genuine, disclosed signature change to all three TS functions -- see TS
-- INTEGRATION at the end of this file.
--
-- ===========================================================================
-- SECURITY DEFINER vs SECURITY INVOKER
-- ===========================================================================
-- Every `app.*` function below is granted to `authenticated, service_role`
-- (uniform ISS-2026-309 convention, see GRANT PARITY below), and Supabase's own
-- `service_role` carries BYPASSRLS. A SECURITY INVOKER function called by a
-- service_role session would run its bare `select ... from app.shipment_legs
-- where ...` (or the cargo-allocation/custody-event equivalent) with NO row-
-- security filtering at all -- silently returning cross-tenant, cross-actor ROWS
-- to any service_role caller regardless of the p_actor_auth_user_id it claims to be
-- reading for. SECURITY DEFINER, with the record-scope predicate reproduced
-- explicitly against the caller-supplied p_actor_auth_user_id (never the session's
-- own row-security state), is required for correctness -- the identical reasoning
-- every prior function in cluster 0-3 batch 1 already applied.
--
-- ===========================================================================
-- RULE B (RLS predicate currency) -- each table's own current SELECT policy,
-- independently re-confirmed for this draft, not assumed from any other function's
-- header
-- ===========================================================================
-- Repo-wide grep for BOTH the bare policy name AND any rule-rewrite statement
-- naming each of the three tables, sorted by filename, finds for every one of them
-- exactly ONE file (their own original creation, 20260729290000) and no later
-- rewrite of any kind anywhere in the migration set:
--
--   * shipment_legs_select_scoped (app.shipment_legs), 20260729290000:966-974,
--     never touched again:
--       using (
--         exists (
--           select 1 from app.shipment_orders so
--           where so.id = shipment_legs.shipment_order_id
--             and app.can_access_record(actor, so.tenant_id, so.owner_user_id,
--               app.lead_record_scope_org_unit_ids(so.org_unit_id), null)
--         )
--       )
--     ONE hop: app.shipment_legs already carries shipment_order_id directly, so no
--     intermediate join is needed to reach app.shipment_orders.
--
--   * shipment_leg_cargo_allocations_select_scoped (app.shipment_leg_cargo_
--     allocations), 20260729290000:987-996, never touched again:
--       using (
--         exists (
--           select 1 from app.shipment_legs sl
--           join app.shipment_orders so on so.id = sl.shipment_order_id
--           where sl.id = shipment_leg_cargo_allocations.shipment_leg_id
--             and app.can_access_record(actor, so.tenant_id, so.owner_user_id,
--               app.lead_record_scope_org_unit_ids(so.org_unit_id), null)
--         )
--       )
--     TWO hops: this table is scoped by shipment_leg_id, not shipment_order_id, so
--     it must join through app.shipment_legs to reach app.shipment_orders.
--
--   * shipment_leg_custody_events_select_scoped (app.shipment_leg_custody_events),
--     20260729290000:998-1007, never touched again -- identical two-hop shape to
--     the cargo-allocations policy immediately above, substituting shipment_leg_
--     custody_events.shipment_leg_id for the exists() correlation.
--
-- All three predicates above are reproduced VERBATIM below, with the session-bound
-- `(select auth.uid())` each policy actually uses swapped for the explicit
-- `p_actor_auth_user_id` parameter (RULE A) -- never a different predicate shape,
-- never a narrower or wider one.
--
-- ===========================================================================
-- RULE C (helper staleness) -- every helper below checked against its MOST RECENT
-- definition
-- ===========================================================================
--   * app.can_access_record -- repo-wide grep for "create or replace function app.
--     can_access_record" / "create function app.can_access_record" finds exactly
--     two hits: the original 20260716110430 and ONE rewrite, 20260723180000:50-88
--     (COM-146's own NULL-owner coalesce fix). No third hit exists anywhere,
--     including in this series' own five prior closing migrations, which only ever
--     reference it by name in prose. Current signature: `can_access_record(p_auth_
--     user_id uuid, p_tenant_id uuid, p_owner_user_id uuid, p_shared_org_unit_ids
--     uuid[] default '{}', p_customer_account_ref text default null) returns
--     boolean`. Called by reference (never re-implemented) below.
--   * app.lead_record_scope_org_unit_ids -- exactly ONE hit repo-wide,
--     20260723090000:164-176 -- never replaced. Called by reference below.
--   * app.assert_actor_is_session_identity -- exactly ONE `create or replace` hit
--     repo-wide, 20260730440000:59-89 -- never re-replaced. A no-op whenever the
--     session identity is null (service_role, superuser, db-tests, nested SECURITY
--     DEFINER calls); raises `actor_identity_mismatch` only when a genuine
--     authenticated session's own identity differs from the claimed p_actor_auth_
--     user_id. `perform app.assert_actor_is_session_identity(p_actor_auth_user_id);`
--     is the first executable statement in every function below.
--
-- ===========================================================================
-- CONTRACT FIDELITY -- physical column shape for all three tables
-- ===========================================================================
-- Verified by reading each table's own original `create table app.<name>`
-- (20260729290000) plus a repo-wide grep for every later `alter table app.
-- shipment_legs|app.shipment_leg_cargo_allocations|app.shipment_leg_custody_events
-- add column` statement -- zero hits for all three tables beyond their own
-- original creation (the only later touches to this table family, 20260902031000
-- and 20260903120000, add a column to a DIFFERENT table, app.vendor_assignment_
-- invitations, and rewrite mutation-function BODIES for tenant-id-disclosure
-- hardening -- neither adds/drops/renames a column or touches RLS on any of the
-- three tables this draft reads). Each RETURNS TABLE below therefore names the
-- table's full, current physical column list, in the table's own declared order --
-- also independently cross-checked against server/contracts/multi-leg-shipment/
-- multi-leg-shipment.ts's own ShipmentLegSchema/ShipmentLegCargoAllocationSchema/
-- ShipmentLegCustodyEventSchema field lists, which match 1:1 (the cargo-allocation
-- contract's own parseShipmentLegCargoAllocation deliberately never reads
-- created_by off the row -- an existing, unrelated omission in that parser, not
-- something this draft's RETURNS TABLE should also omit, since `.select("*")`
-- itself always returned that column and this draft's own job is byte-for-byte
-- read-shape parity with the original `.from()` call, not the parser's downstream
-- consumption of it):
--
--   app.shipment_legs (18 columns): id, tenant_id, shipment_order_id, sequence_no,
--   idempotency_key, mode, leg_status, is_legacy_compat, carrier_master_id,
--   planned_departure_at, planned_arrival_at, actual_departure_at,
--   actual_arrival_at, owner_user_id, record_version, created_by, created_at,
--   updated_at.
--
--   app.shipment_leg_cargo_allocations (10 columns): id, tenant_id,
--   shipment_leg_id, allocated_quantity, allocated_weight_kg,
--   allocated_volume_cbm, record_version, created_by, created_at, updated_at.
--
--   app.shipment_leg_custody_events (11 columns): id, tenant_id, shipment_leg_id,
--   sequence_no, event_type, from_party_snapshot, to_party_snapshot, occurred_at,
--   evidence, recorded_by, created_at. (No updated_at -- this table is append-only
--   by design, and 20260729290000 never creates a touch-row trigger for it, unlike
--   its three siblings in the same migration.)
--
-- ===========================================================================
-- DOMAIN NOTE -- what the original TS comment's "non-cancelled-first" actually
-- means, investigated rather than guessed
-- ===========================================================================
-- listShipmentLegs' own header comment reads "Every non-cancelled-first leg for
-- one Shipment Order, ordered by sequence_no ascending." The CURRENT code below it
-- applies NO status filter of any kind -- `.eq("shipment_order_id", ...)` only,
-- then a plain `.order("sequence_no", { ascending: true })`. Two schema facts rule
-- out the most literal misreading (that a cancelled leg is somehow excluded, or
-- reordered ahead of an active "replacement" leg occupying the same slot):
--   1. `leg_status` has six possible values (planned, dispatched, in_transit,
--      arrived, completed, cancelled), confirmed via app.shipment_legs' own
--      `shipment_legs_status_check` CHECK constraint (20260729290000:76) -- there
--      is no separate "superseded" or "replaced" status a cancelled leg
--      transitions through, and no column anywhere in this table linking one leg
--      to a "replacement" leg.
--   2. `shipment_legs_tenant_shipment_sequence_unique unique (tenant_id,
--      shipment_order_id, sequence_no)` (20260729290000:79) is a PLAIN, whole-table
--      unique constraint -- it has no `where leg_status <> 'cancelled'` partial
--      clause, and repo-wide grep confirms it was never altered or dropped. A
--      cancelled leg therefore PERMANENTLY reserves its own sequence_no; no new leg
--      can ever be inserted at that same position afterward (app.add_shipment_leg's
--      own current body, 20260903120000:174-180, does check `and leg_status <>
--      'cancelled'` before its own pre-flight duplicate-sequence error -- but the
--      base table constraint would still reject the actual insert with a bare
--      unique_violation regardless of the existing row's status, since the
--      constraint itself carries no such exception; this looks like a latent,
--      already-shipped inconsistency in that function's own pre-flight check versus
--      the constraint it is guarding against, disclosed here as an out-of-scope
--      observation, not something this read-only draft touches).
-- Given both of those facts, "two legs sharing one sequence_no, cancelled-then-
-- replacement" is not a state this schema can ever actually produce -- so the
-- phrase cannot describe a same-slot ordering rule. The reading consistent with
-- the code as written is that "non-cancelled-first" is simply an awkward way of
-- saying the opposite of what it might first suggest: this read does NOT sort
-- cancelled legs to the front (or push them to the back, or drop them) -- EVERY
-- leg, cancelled or not, comes back in one plain ascending sequence_no order, each
-- sitting exactly where its own sequence_no places it. This draft reproduces
-- exactly that: no WHERE-clause status exclusion, `order by sequence_no asc` only,
-- matching the current `.from()` call byte-for-byte. **Flagged for the verify
-- pass**: this reading is the best one the schema and code support, not a fact
-- recovered from any design document -- if a domain owner confirms a different
-- original intent, that is a product-behavior question for a follow-up item, not a
-- reason to change this function's own byte-for-byte reproduction of the read it
-- replaces.
--
-- ===========================================================================
-- ROW-NOT-FOUND / EMPTY-RESULT BEHAVIOR
-- ===========================================================================
-- All three functions return zero rows (or, for the single-allocation read, zero
-- rows collapsing to a TS `null`) silently, never an exception, for a shipment
-- order/leg the actor cannot access or that does not exist -- matching each
-- original `.from()` read's own current RLS-filtered silent-empty-result behavior
-- exactly. No RAISE is introduced by this draft. Unlike app.get_job_order_for_
-- handoff/app.get_job_order_handoff_for_quotation (cluster 3 batch 1's own
-- adversarial-verify finding), app.get_shipment_leg_cargo_allocation needs no
-- count-then-raise-on-ambiguity guard: `shipment_leg_cargo_allocations_leg_unique
-- unique (shipment_leg_id)` (20260729290000:161) is a genuine, non-composite unique
-- constraint on the exact column this read filters by, so more than one matching
-- row is not merely unlikely -- it is schema-impossible. `.maybeSingle()`'s
-- throw-on-multi-row-conflict branch can therefore never be reached by this table
-- today, and this draft's RETURNS TABLE shape needs no LIMIT/ORDER BY tie-break to
-- stay deterministic.
--
-- ===========================================================================
-- GRANT PARITY (ISS-2026-309) and ERR-2026-004
-- ===========================================================================
-- Every `app.*` function below is granted to `authenticated, service_role`,
-- matching this series' own uniform convention. Per ISS-2026-309: every `public.*`
-- wrapper below explicitly revokes from `anon, authenticated, service_role, public`
-- (all four) before re-granting exactly `authenticated, service_role` -- a bare
-- `revoke ... from public` does not strip the `anon`/`authenticated` EXECUTE grants
-- Supabase's own ALTER DEFAULT PRIVILEGES rule applies to every new function in
-- schema `public` at CREATE time. Per ERR-2026-004: each `app.*` function below
-- carries its own explicit `revoke execute on function ... from public` before its
-- grant.
--
-- check-rls-initplan.ts false-positive avoidance: every `comment on function ...
-- is '...'` string below avoids combining a literal "CREATE POLICY"/"ALTER POLICY"
-- phrase with a bare, parenthesized `auth.uid()`/`auth.jwt()` mention in the same
-- string -- phrased instead as "this table's own current row-security rule" / "no
-- rewrite of this rule exists". This file's own `--` line-comment prose above is
-- unaffected (the guard's own blankLineComments preprocessing blanks every `--`
-- line before parsing) and is written plainly. The guard itself is never
-- suppressed, only the prose reworded.

-- ===========================================================================
-- 1. app.list_shipment_legs -- replaces server/queries/multi-leg-shipment.ts:33-39
--    (listShipmentLegs)
-- ===========================================================================
-- Replaces: `.from("shipment_legs").select("*").eq("shipment_order_id",
-- shipmentOrderId).order("sequence_no", { ascending: true })`. One hop: app.
-- shipment_legs already carries shipment_order_id directly, so the authority join
-- goes straight to app.shipment_orders, matching shipment_legs_select_scoped's own
-- current shape exactly (RULE B above).
create function app.list_shipment_legs(
  p_shipment_order_id uuid,
  p_actor_auth_user_id uuid
)
returns table (
  id uuid,
  tenant_id uuid,
  shipment_order_id uuid,
  sequence_no integer,
  idempotency_key text,
  mode text,
  leg_status text,
  is_legacy_compat boolean,
  carrier_master_id uuid,
  planned_departure_at timestamptz,
  planned_arrival_at timestamptz,
  actual_departure_at timestamptz,
  actual_arrival_at timestamptz,
  owner_user_id uuid,
  record_version integer,
  created_by text,
  created_at timestamptz,
  updated_at timestamptz
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
    sl.id, sl.tenant_id, sl.shipment_order_id, sl.sequence_no, sl.idempotency_key,
    sl.mode, sl.leg_status, sl.is_legacy_compat, sl.carrier_master_id,
    sl.planned_departure_at, sl.planned_arrival_at, sl.actual_departure_at,
    sl.actual_arrival_at, sl.owner_user_id, sl.record_version, sl.created_by,
    sl.created_at, sl.updated_at
  from app.shipment_legs sl
  where sl.shipment_order_id = p_shipment_order_id
    and exists (
      select 1 from app.shipment_orders so
      where so.id = sl.shipment_order_id
        and app.can_access_record(
          p_actor_auth_user_id,
          so.tenant_id,
          so.owner_user_id,
          app.lead_record_scope_org_unit_ids(so.org_unit_id),
          null
        )
    )
  order by sl.sequence_no asc;
end;
$$;

comment on function app.list_shipment_legs(uuid, uuid) is
  'CG-AUDIT-2026-09-02 O1 remediation (cluster 3, multi-leg shipment): every leg of one Shipment Order, replacing server/queries/multi-leg-shipment.ts''s broken .from("shipment_legs") read (lines 33-39) -- the app schema is not exposed to PostgREST. Actor identity cross-checked via app.assert_actor_is_session_identity before any lookup (RULE A -- this function''s p_actor_auth_user_id parameter is new; the original TS function took none). Row-visibility filter reproduces app.shipment_legs'' own current shipment_legs_select_scoped rule verbatim (app.can_access_record against the parent Shipment Order''s tenant/owner/org-unit scope, one join hop since shipment_order_id lives directly on this table) -- confirmed via repo-wide grep that no rewrite of this rule exists anywhere in the migration set. No status filter is applied, matching the original .from() call exactly: every leg, including a cancelled one, is returned in its own natural sequence_no position (see this migration''s own header for why the original TS comment''s "non-cancelled-first" phrase does not describe an exclusion or a same-slot reordering -- the schema''s own whole-table unique constraint on (tenant_id, shipment_order_id, sequence_no) makes a same-slot cancelled/replacement pair schema-impossible). Returns zero rows, never an exception, for a nonexistent shipment_order_id or an actor who cannot reach that shipment order''s tenant/owner/org-unit/customer-account scope -- matching the original RLS-filtered read''s own silent-empty-result posture, unchanged.';

-- Option-2 wrapper: app is not exposed to PostgREST; this is a thin security-
-- definer pass-through to app.list_shipment_legs with an identical grant set,
-- never a reimplementation.
create function public.list_shipment_legs(
  p_shipment_order_id uuid,
  p_actor_auth_user_id uuid
)
returns table (
  id uuid,
  tenant_id uuid,
  shipment_order_id uuid,
  sequence_no integer,
  idempotency_key text,
  mode text,
  leg_status text,
  is_legacy_compat boolean,
  carrier_master_id uuid,
  planned_departure_at timestamptz,
  planned_arrival_at timestamptz,
  actual_departure_at timestamptz,
  actual_arrival_at timestamptz,
  owner_user_id uuid,
  record_version integer,
  created_by text,
  created_at timestamptz,
  updated_at timestamptz
)
language sql
stable
security definer
set search_path = pg_catalog, pg_temp
as $wrap$
  select * from app.list_shipment_legs(p_shipment_order_id, p_actor_auth_user_id);
$wrap$;

comment on function public.list_shipment_legs(uuid, uuid) is
  'Option-2 wrapper: app is not exposed to PostgREST; this is a thin security-definer pass-through to app.list_shipment_legs with an identical grant set, never a reimplementation.';

revoke execute on function app.list_shipment_legs(uuid, uuid) from public;
grant execute on function app.list_shipment_legs(uuid, uuid) to authenticated, service_role;

revoke execute on function public.list_shipment_legs(uuid, uuid) from anon, authenticated, service_role, public;
grant execute on function public.list_shipment_legs(uuid, uuid) to authenticated, service_role;

-- ===========================================================================
-- 2. app.get_shipment_leg_cargo_allocation -- replaces
--    server/queries/multi-leg-shipment.ts:51-60 (getShipmentLegCargoAllocation)
-- ===========================================================================
-- Replaces: `.from("shipment_leg_cargo_allocations").select("*")
-- .eq("shipment_leg_id", shipmentLegId).maybeSingle()`. Two hops: this table
-- carries shipment_leg_id, not shipment_order_id, so the authority join goes
-- through app.shipment_legs first, matching shipment_leg_cargo_allocations_select_
-- scoped's own current shape exactly (RULE B above). shipment_leg_cargo_
-- allocations_leg_unique (unique on shipment_leg_id alone) already guarantees at
-- most one physical row per leg, so no LIMIT/ORDER BY is needed to stay
-- deterministic.
create function app.get_shipment_leg_cargo_allocation(
  p_shipment_leg_id uuid,
  p_actor_auth_user_id uuid
)
returns table (
  id uuid,
  tenant_id uuid,
  shipment_leg_id uuid,
  allocated_quantity numeric,
  allocated_weight_kg numeric,
  allocated_volume_cbm numeric,
  record_version integer,
  created_by text,
  created_at timestamptz,
  updated_at timestamptz
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
    a.id, a.tenant_id, a.shipment_leg_id, a.allocated_quantity, a.allocated_weight_kg,
    a.allocated_volume_cbm, a.record_version, a.created_by, a.created_at, a.updated_at
  from app.shipment_leg_cargo_allocations a
  where a.shipment_leg_id = p_shipment_leg_id
    and exists (
      select 1 from app.shipment_legs sl
      join app.shipment_orders so on so.id = sl.shipment_order_id
      where sl.id = a.shipment_leg_id
        and app.can_access_record(
          p_actor_auth_user_id,
          so.tenant_id,
          so.owner_user_id,
          app.lead_record_scope_org_unit_ids(so.org_unit_id),
          null
        )
    );
end;
$$;

comment on function app.get_shipment_leg_cargo_allocation(uuid, uuid) is
  'CG-AUDIT-2026-09-02 O1 remediation (cluster 3, multi-leg shipment): the one cargo allocation for one leg, if any, replacing server/queries/multi-leg-shipment.ts''s broken .from("shipment_leg_cargo_allocations") read (lines 51-60) -- the app schema is not exposed to PostgREST. Actor identity cross-checked via app.assert_actor_is_session_identity before any lookup (RULE A -- this function''s p_actor_auth_user_id parameter is new; the original TS function took none). Row-visibility filter reproduces app.shipment_leg_cargo_allocations'' own current shipment_leg_cargo_allocations_select_scoped rule verbatim (app.can_access_record against the owning Shipment Order''s tenant/owner/org-unit scope, joined through app.shipment_legs since this table is scoped by shipment_leg_id, not shipment_order_id) -- confirmed via repo-wide grep that no rewrite of this rule exists anywhere in the migration set. shipment_leg_cargo_allocations_leg_unique (a genuine unique constraint on shipment_leg_id alone, not a composite one) makes more than one matching row schema-impossible, so unlike app.get_job_order_for_handoff/app.get_job_order_handoff_for_quotation (cluster 3 batch 1) this function needs no count-then-raise ambiguity guard. Returns zero rows (the TS layer maps this to null, matching the original .maybeSingle()''s own not-found behavior) for a leg with no allocation yet, a nonexistent shipment_leg_id, or an actor who cannot reach the owning shipment order''s tenant/owner/org-unit/customer-account scope.';

-- Option-2 wrapper: app is not exposed to PostgREST; this is a thin security-
-- definer pass-through to app.get_shipment_leg_cargo_allocation with an identical
-- grant set, never a reimplementation.
create function public.get_shipment_leg_cargo_allocation(
  p_shipment_leg_id uuid,
  p_actor_auth_user_id uuid
)
returns table (
  id uuid,
  tenant_id uuid,
  shipment_leg_id uuid,
  allocated_quantity numeric,
  allocated_weight_kg numeric,
  allocated_volume_cbm numeric,
  record_version integer,
  created_by text,
  created_at timestamptz,
  updated_at timestamptz
)
language sql
stable
security definer
set search_path = pg_catalog, pg_temp
as $wrap$
  select * from app.get_shipment_leg_cargo_allocation(p_shipment_leg_id, p_actor_auth_user_id);
$wrap$;

comment on function public.get_shipment_leg_cargo_allocation(uuid, uuid) is
  'Option-2 wrapper: app is not exposed to PostgREST; this is a thin security-definer pass-through to app.get_shipment_leg_cargo_allocation with an identical grant set, never a reimplementation.';

revoke execute on function app.get_shipment_leg_cargo_allocation(uuid, uuid) from public;
grant execute on function app.get_shipment_leg_cargo_allocation(uuid, uuid) to authenticated, service_role;

revoke execute on function public.get_shipment_leg_cargo_allocation(uuid, uuid) from anon, authenticated, service_role, public;
grant execute on function public.get_shipment_leg_cargo_allocation(uuid, uuid) to authenticated, service_role;

-- ===========================================================================
-- 3. app.list_shipment_leg_custody_events -- replaces
--    server/queries/multi-leg-shipment.ts:63-69 (listShipmentLegCustodyEvents)
-- ===========================================================================
-- Replaces: `.from("shipment_leg_custody_events").select("*")
-- .eq("shipment_leg_id", shipmentLegId).order("sequence_no", { ascending: true
-- })`. Two hops, identical join shape to function 2 above: this table also
-- carries shipment_leg_id, not shipment_order_id, matching shipment_leg_custody_
-- events_select_scoped's own current shape exactly (RULE B above). This table is
-- append-only (no updated_at column, no touch-row trigger, per this migration's
-- own header CONTRACT FIDELITY section) -- sequence_no is server-assigned via app.
-- next_shipment_leg_custody_sequence and never reused, so ascending sequence_no
-- order is equivalent to insertion order ("oldest first"), matching the original
-- TS function''s own header comment.
create function app.list_shipment_leg_custody_events(
  p_shipment_leg_id uuid,
  p_actor_auth_user_id uuid
)
returns table (
  id uuid,
  tenant_id uuid,
  shipment_leg_id uuid,
  sequence_no integer,
  event_type text,
  from_party_snapshot jsonb,
  to_party_snapshot jsonb,
  occurred_at timestamptz,
  evidence jsonb,
  recorded_by text,
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
    e.id, e.tenant_id, e.shipment_leg_id, e.sequence_no, e.event_type,
    e.from_party_snapshot, e.to_party_snapshot, e.occurred_at, e.evidence,
    e.recorded_by, e.created_at
  from app.shipment_leg_custody_events e
  where e.shipment_leg_id = p_shipment_leg_id
    and exists (
      select 1 from app.shipment_legs sl
      join app.shipment_orders so on so.id = sl.shipment_order_id
      where sl.id = e.shipment_leg_id
        and app.can_access_record(
          p_actor_auth_user_id,
          so.tenant_id,
          so.owner_user_id,
          app.lead_record_scope_org_unit_ids(so.org_unit_id),
          null
        )
    )
  order by e.sequence_no asc;
end;
$$;

comment on function app.list_shipment_leg_custody_events(uuid, uuid) is
  'CG-AUDIT-2026-09-02 O1 remediation (cluster 3, multi-leg shipment): every custody event for one leg, oldest first, replacing server/queries/multi-leg-shipment.ts''s broken .from("shipment_leg_custody_events") read (lines 63-69) -- the app schema is not exposed to PostgREST. Actor identity cross-checked via app.assert_actor_is_session_identity before any lookup (RULE A -- this function''s p_actor_auth_user_id parameter is new; the original TS function took none). Row-visibility filter reproduces app.shipment_leg_custody_events'' own current shipment_leg_custody_events_select_scoped rule verbatim (app.can_access_record against the owning Shipment Order''s tenant/owner/org-unit scope, joined through app.shipment_legs since this table is scoped by shipment_leg_id, not shipment_order_id) -- confirmed via repo-wide grep that no rewrite of this rule exists anywhere in the migration set. No status filter applies (this table has no status column at all -- it is append-only, per this migration''s own header). Returns zero rows, never an exception, for a leg with no custody events yet, a nonexistent shipment_leg_id, or an actor who cannot reach the owning shipment order''s tenant/owner/org-unit/customer-account scope -- matching the original RLS-filtered read''s own silent-empty-result posture, unchanged.';

-- Option-2 wrapper: app is not exposed to PostgREST; this is a thin security-
-- definer pass-through to app.list_shipment_leg_custody_events with an identical
-- grant set, never a reimplementation.
create function public.list_shipment_leg_custody_events(
  p_shipment_leg_id uuid,
  p_actor_auth_user_id uuid
)
returns table (
  id uuid,
  tenant_id uuid,
  shipment_leg_id uuid,
  sequence_no integer,
  event_type text,
  from_party_snapshot jsonb,
  to_party_snapshot jsonb,
  occurred_at timestamptz,
  evidence jsonb,
  recorded_by text,
  created_at timestamptz
)
language sql
stable
security definer
set search_path = pg_catalog, pg_temp
as $wrap$
  select * from app.list_shipment_leg_custody_events(p_shipment_leg_id, p_actor_auth_user_id);
$wrap$;

comment on function public.list_shipment_leg_custody_events(uuid, uuid) is
  'Option-2 wrapper: app is not exposed to PostgREST; this is a thin security-definer pass-through to app.list_shipment_leg_custody_events with an identical grant set, never a reimplementation.';

revoke execute on function app.list_shipment_leg_custody_events(uuid, uuid) from public;
grant execute on function app.list_shipment_leg_custody_events(uuid, uuid) to authenticated, service_role;

revoke execute on function public.list_shipment_leg_custody_events(uuid, uuid) from anon, authenticated, service_role, public;
grant execute on function public.list_shipment_leg_custody_events(uuid, uuid) to authenticated, service_role;

-- ===========================================================================
-- OPEN DESIGN QUESTIONS / RISKS FOR THE VERIFY PASS
-- ===========================================================================
-- 1. app.get_shipment_leg_stops (SECURITY INVOKER, no p_actor_auth_user_id,
--    relies on live RLS) is called from inside a SECURITY DEFINER public wrapper,
--    and none of this table family carries FORCE ROW LEVEL SECURITY -- meaning a
--    table-owner role executing that nested invoker call could bypass RLS
--    entirely, independent of this table's own shipment_leg_stops_select_scoped
--    policy being otherwise correct. This is a pre-existing condition in
--    already-shipped code (20260729290000 / 20260826000000), not something this
--    draft introduces or was asked to fix -- flagged as a candidate for a
--    separately-scoped follow-up item, not addressed here.
-- 2. app.add_shipment_leg's own current pre-flight duplicate-sequence check
--    (20260903120000:174-180) tests `leg_status <> 'cancelled'`, but app.
--    shipment_legs' own base unique constraint on (tenant_id, shipment_order_id,
--    sequence_no) has no such carve-out -- so that pre-flight check can report a
--    misleading non-error before the insert itself would still fail with a bare
--    unique_violation for a cancelled leg''s sequence_no. This is a mutation-path
--    inconsistency this read-only draft discovered while investigating the
--    "non-cancelled-first" comment, not something in scope to fix here (no
--    mutation function is touched by this batch).
-- 3. The "non-cancelled-first" phrasing itself (DOMAIN NOTE above) is this
--    draft's own best reading of the schema and code, not a fact recovered from a
--    design document -- worth a quick confirmation from whoever owns this
--    domain''s product intent, though it changes nothing about this draft''s own
--    behavior (no status filter, ascending sequence_no, exactly reproducing the
--    current .from() call).
-- 4. No new covering index is added for any of the three new functions -- app.
--    shipment_legs already has `shipment_legs_tenant_shipment_idx (tenant_id,
--    shipment_order_id)`, and both shipment_leg_cargo_allocations/shipment_leg_
--    custody_events already have a `(tenant_id, shipment_leg_id)` index -- all
--    three of this draft's own filters are covered by an existing index, so no
--    schema change beyond the six new functions is proposed.

-- ===========================================================================
-- TS INTEGRATION:
-- ===========================================================================
--
-- server/queries/multi-leg-shipment.ts
-- ---------------------------------------------------------------------------
-- MultiLegShipmentQueryTableClient (currently line 23) is `Pick<SupabaseClient,
-- "from" | "rpc">` -- "from" is no longer used anywhere in this file once all
-- three functions below are switched (listShipmentLegStops/getShipmentLegNetworkState
-- already use "rpc" only). It MAY be narrowed to `Pick<SupabaseClient, "rpc">` as
-- an optional follow-on cleanup; not required for correctness.
--
-- All three functions below gain a new REQUIRED second parameter,
-- `actorAuthUserId: string`, inserted immediately after the existing identifier
-- parameter (matching this series'' own established call-signature convention,
-- e.g. getJobOrder(client, jobOrderId, actorAuthUserId)). This is a breaking
-- change to every real call site -- repo-wide grep for
-- "listShipmentLegs(" / "getShipmentLegCargoAllocation(" / "listShipmentLegCustodyEvents("
-- was not re-run as part of this SQL-only draft; do this before applying, and pass
-- each caller''s own resolved session actor (the same `access.authUserId`
-- convention ATW-030 already established repo-wide), or the TS build will fail at
-- compile time.
--
-- 1. listShipmentLegs (currently lines 33-39) -- replace the entire body:
--
--   export async function listShipmentLegs(
--     client: MultiLegShipmentQueryTableClient,
--     shipmentOrderId: string,
--     actorAuthUserId: string,
--   ): Promise<ShipmentLeg[]> {
--     const { data, error } = await client.rpc("list_shipment_legs", {
--       p_shipment_order_id: shipmentOrderId,
--       p_actor_auth_user_id: actorAuthUserId,
--     });
--     if (error) {
--       throw new MultiLegShipmentQueryError(error.message);
--     }
--     return (data ?? []).map((row: Record<string, unknown>) => parseShipmentLeg(row));
--   }
--
-- (No change to parseShipmentLeg or ShipmentLegSchema -- app.list_shipment_legs''
-- RETURNS TABLE column list matches app.shipment_legs'' own physical columns 1:1,
-- identical to what `.select("*")` previously returned.)
--
-- 2. getShipmentLegCargoAllocation (currently lines 51-60) -- replace the entire
--    body:
--
--   export async function getShipmentLegCargoAllocation(
--     client: MultiLegShipmentQueryTableClient,
--     shipmentLegId: string,
--     actorAuthUserId: string,
--   ): Promise<ShipmentLegCargoAllocation | null> {
--     const { data, error } = await client.rpc("get_shipment_leg_cargo_allocation", {
--       p_shipment_leg_id: shipmentLegId,
--       p_actor_auth_user_id: actorAuthUserId,
--     });
--     if (error) {
--       throw new MultiLegShipmentQueryError(error.message);
--     }
--     const row = Array.isArray(data) ? data[0] : data;
--     return row ? parseShipmentLegCargoAllocation(row as Record<string, unknown>) : null;
--   }
--
-- (RETURNS TABLE always comes back as an array via .rpc(), unlike the old
-- .maybeSingle() single-object shape -- the `Array.isArray(data) ? data[0] : data`
-- guard is this series'' own established idiom for this exact conversion,
-- cluster 1 batch 1 / cluster 3 batch 1. No change to parseShipmentLegCargoAllocation
-- or ShipmentLegCargoAllocationSchema.)
--
-- 3. listShipmentLegCustodyEvents (currently lines 63-69) -- replace the entire
--    body:
--
--   export async function listShipmentLegCustodyEvents(
--     client: MultiLegShipmentQueryTableClient,
--     shipmentLegId: string,
--     actorAuthUserId: string,
--   ): Promise<ShipmentLegCustodyEvent[]> {
--     const { data, error } = await client.rpc("list_shipment_leg_custody_events", {
--       p_shipment_leg_id: shipmentLegId,
--       p_actor_auth_user_id: actorAuthUserId,
--     });
--     if (error) {
--       throw new MultiLegShipmentQueryError(error.message);
--     }
--     return (data ?? []).map((row: Record<string, unknown>) => parseShipmentLegCustodyEvent(row));
--   }
--
-- (No change to parseShipmentLegCustodyEvent or ShipmentLegCustodyEventSchema.)
--
-- No change needed to server/contracts/multi-leg-shipment/multi-leg-shipment.ts --
-- every parse function already reads exactly the snake_case column names all
-- three new RPC functions return.
--
-- Live call sites needing a change (repo-wide grep for
-- "listShipmentLegs(" / "getShipmentLegCargoAllocation(" / "listShipmentLegCustodyEvents("
-- across every *.ts/*.tsx file, RE-RUN for this draft -- exactly one real, non-test
-- caller exists):
--
--   app/(tenant)/[tenantSlug]/operations/shipment-orders/[shipmentOrderId]/page.tsx
--   (lines 269, 276, 277) -- `access.authUserId` is already resolved earlier in
--   this same page (used at lines 232/244/246/247/279 for other actorAuthUserId-
--   taking calls), so the fix is a straight third-argument addition, no new lookup
--   needed:
--     Before (line 269): const legs = await listShipmentLegs(supabase, shipment.id);
--     After:              const legs = await listShipmentLegs(supabase, shipment.id, access.authUserId);
--     Before (line 276): cargoAllocation: await getShipmentLegCargoAllocation(supabase, leg.id),
--     After:              cargoAllocation: await getShipmentLegCargoAllocation(supabase, leg.id, access.authUserId),
--     Before (line 277): custodyEvents: await listShipmentLegCustodyEvents(supabase, leg.id),
--     After:              custodyEvents: await listShipmentLegCustodyEvents(supabase, leg.id, access.authUserId),
--
-- server/queries/multi-leg-shipment.test.ts (lines 55, 79) -- the only other repo-
-- wide hits, both calling listShipmentLegs with a mocked `.from()`-shaped client.
-- Per this task''s own SQL-only scope (matching this series'' established
-- disclaimer for every prior batch''s own *.test.ts files), no rewrite is attempted
-- here -- both call sites will need updating to pass a third actorAuthUserId
-- argument and to mock a `.rpc("list_shipment_legs", ...)` call instead of
-- `.from("shipment_legs")` before this draft can be applied without breaking the
-- test suite.
