-- CG-AUDIT-2026-09-02 O1-query-layer remediation -- cluster 5
-- (procurement-document), the FULL cluster in one migration. Continues the
-- same Design->Verify->Fix adversarial pipeline established by clusters 0-4.
--
-- supabase/config.toml's `schemas = ["public", "graphql_public"]` never exposes
-- the "app" Postgres schema to PostgREST, so every `.from()` read against an
-- `app.*` table in server/queries/*.ts has NEVER worked in production. Closes
-- the 4 remaining broken `.from()` call sites of this cluster (a 5th,
-- documented below, needed no new SQL at all):
--
--   server/queries/procurement-approval.ts:49    listProcurementApprovalPolicyVersions
--   server/queries/procurement-dashboard.ts:110   listActiveProcurementMetricDefinitions
--   server/queries/document-requirement.ts:77     listDocumentRequirementDefinitions
--   server/queries/document.ts:94                 listDocumentTypes
--
-- 4 new app.*/public.* Option-2 wrapper function pairs (8 functions total),
-- over 4 distinct relations:
--
--   app.procurement_approval_policies       -> app.list_procurement_approval_policy_versions (SECURITY DEFINER)
--   app.procurement_metric_definitions      -> app.list_active_procurement_metric_definitions (SECURITY INVOKER)
--   app.document_requirement_definitions    -> app.list_document_requirement_definitions      (SECURITY DEFINER)
--   app.document_types                      -> app.list_document_types                        (SECURITY INVOKER)
--
-- ===========================================================================
-- FIFTH CALL SITE -- SWAP_ONLY, no new SQL (adversarial correction of the
-- recon's own classification)
-- ===========================================================================
-- server/queries/procurement-approval.ts:136 (listProcurementApprovalInboxForActor)
-- reads `.from("approval_requests").select("id, entity_type, entity_id").in("id",
-- requestIds)` -- the CG-AUDIT-2026-09-02-O1-QUERY-LAYER-RECON.json manifest
-- classified this NEEDS_NEW_FUNCTION, but that classification is now stale:
-- cluster 0 batch 3 (20260909010000_close_o1_query_layer_cluster0_batch3_
-- costing_credit_approval.sql:1432) already shipped
-- app.get_approval_requests_entity_refs(p_ids uuid[], p_actor_auth_user_id uuid)
-- -- byte-for-byte the same read shape (same table, same 3-column projection,
-- same "no p_tenant_id, authority evaluated per-row against each candidate
-- row's own tenant_id" contract, same current approval_requests_select_scoped
-- predicate) -- built for the IDENTICAL two-call-site pattern in
-- server/queries/credit.ts and server/queries/quotation-approval.ts. The recon
-- for this cluster was run independently of cluster 0's own additions and
-- could not have known that function would exist by the time this cluster was
-- closed. Re-verified directly (not assumed from the recon's own notes):
--   `grep -n "create function app.get_approval_requests_entity_refs"
--   supabase/migrations/*.sql` -- exactly one hit, no later `create or
--   replace` exists (RULE C: this is still that function's own only body).
-- Reusing it here means server/queries/quotation-approval.ts's
-- listQuotationApprovalInboxForActor and server/queries/procurement-approval.ts's
-- listProcurementApprovalInboxForActor now share the exact same three-consumer
-- RPC (alongside server/queries/credit.ts), never a duplicate. This migration
-- therefore adds NO new function for this call site -- see TS INTEGRATION
-- below for the plain swap.
--
-- ===========================================================================
-- 1. app.list_procurement_approval_policy_versions -- replaces server/queries/
--    procurement-approval.ts:49 (listProcurementApprovalPolicyVersions)
-- ===========================================================================
-- Replaces: `.from("procurement_approval_policies").select("*")
-- .eq("tenant_id", tenantId).order("created_at", { ascending: false })`.
--
-- Table (base table, not a view): app.procurement_approval_policies, created
-- at 20260730660000_create_procurement_approval.sql:177 -- "tenant-wide
-- reference/policy data ... never field-masked" per that migration's own
-- header (same file, line 1661-1662), mirroring app.quotation_approval_rules
-- (COM-153) exactly, per server/queries/procurement-approval.ts:47's own
-- doc-comment.
--
-- RULE B (RLS predicate currency): `grep -rn
-- "procurement_approval_policies_select_scoped" supabase/migrations/*.sql` --
-- exactly ONE hit, the original `create policy` at
-- 20260730660000_create_procurement_approval.sql:1663-1665. No later `alter
-- policy` exists for this table -- its predicate has never been rewritten
-- (unlike the customer_user-layer-default-deny sweep,
-- 20260730560000_harden_customer_user_layer_default_deny.sql, which touched
-- many sibling tables but never lists this one). The predicate reproduced
-- below is therefore that original, current text verbatim:
--   using ((app.has_active_tenant_membership(tenant_id) and not
--   app.actor_holds_customer_user_layer(tenant_id)) or app.is_supreme_admin());
--
-- RULE C (precedent staleness): this function is modeled directly on
-- app.list_quotation_approval_rule_versions
-- (20260909020000_close_o1_query_layer_cluster0_batch4_leads_prospects_
-- quotation_directory.sql:3077-3107, re-confirmed as that function's own
-- only body via the same `create or replace` grep discipline) -- same
-- tenant-membership predicate shape, same explicit-actor + RULE A + raise
-- insufficient_authority contract (a disclosed, low-risk tightening over the
-- original .from() call's own "RLS-filtered read returns empty on denial"
-- behavior), same server-side 200-row cap the original .from() call never
-- had, same most-recent-first ordering.
--
-- RULE A: p_actor_auth_user_id is an explicit parameter and this function is
-- granted to `authenticated` -> `perform
-- app.assert_actor_is_session_identity(p_actor_auth_user_id);` is the first
-- executable statement.
create function app.list_procurement_approval_policy_versions(
  p_tenant_id uuid,
  p_actor_auth_user_id uuid,
  p_limit integer default 200
)
returns setof app.procurement_approval_policies
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  if not (
    (app.has_active_tenant_membership(p_tenant_id, p_actor_auth_user_id)
       and not app.actor_holds_customer_user_layer(p_tenant_id, p_actor_auth_user_id))
    or app.is_supreme_admin(p_actor_auth_user_id)
  ) then
    raise exception 'insufficient_authority: identity % cannot list procurement approval policies for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  return query
    select *
    from app.procurement_approval_policies
    where tenant_id = p_tenant_id
    order by created_at desc
    limit least(coalesce(p_limit, 200), 200);
end;
$$;

comment on function app.list_procurement_approval_policy_versions(uuid, uuid, integer) is
  'PRC-259/O1 remediation: every procurement approval policy version for one tenant (any status, any entity_type), most-recent first, server-side clamped to <=200 rows regardless of what is requested (mirrors app.list_quotation_approval_rule_versions/app.list_margin_rule_versions/app.list_accounts'' own established cap convention -- the original .from() call site applied no limit, a disclosed, low-risk tightening). Authority reproduces the CURRENT (and only-ever) procurement_approval_policies_select_scoped RLS predicate (has_active_tenant_membership AND NOT actor_holds_customer_user_layer, OR is_supreme_admin) verbatim. Raises insufficient_authority (never a silent empty list) when the actor has no standing for p_tenant_id at all, matching app.list_quotation_approval_rule_versions for this same "list for one named tenant" shape. Tenant-wide policy/reference data -- never field-masked, mirroring app.quotation_approval_rules (COM-153) -- so every column is returned unconditionally.';

create function public.list_procurement_approval_policy_versions(
  p_tenant_id uuid,
  p_actor_auth_user_id uuid,
  p_limit integer default 200
)
returns setof app.procurement_approval_policies
language sql
stable
security definer
set search_path = pg_catalog, pg_temp
as $wrap$
  select * from app.list_procurement_approval_policy_versions(p_tenant_id, p_actor_auth_user_id, p_limit);
$wrap$;

comment on function public.list_procurement_approval_policy_versions(uuid, uuid, integer) is
  'Option-2 wrapper: app is not exposed to PostgREST; this is a thin security-definer pass-through to app.list_procurement_approval_policy_versions with an identical grant set, never a reimplementation.';

revoke execute on function app.list_procurement_approval_policy_versions(uuid, uuid, integer) from public;
grant execute on function app.list_procurement_approval_policy_versions(uuid, uuid, integer) to authenticated, service_role;

revoke execute on function public.list_procurement_approval_policy_versions(uuid, uuid, integer) from anon, authenticated, service_role, public;
grant execute on function public.list_procurement_approval_policy_versions(uuid, uuid, integer) to authenticated, service_role;

-- ===========================================================================
-- 2. app.list_active_procurement_metric_definitions -- replaces server/queries/
--    procurement-dashboard.ts:110 (listActiveProcurementMetricDefinitions)
-- ===========================================================================
-- Replaces: `.from("procurement_metric_definitions").select("*")
-- .eq("is_current", true).eq("status", "active").order("metric_group", { ascending: true })`.
--
-- app.procurement_metric_definitions
-- (20260730780000_create_procurement_dashboard_reports.sql:136-168) never has
-- `alter table ... enable row level security` called on it anywhere in
-- supabase/migrations/*.sql (confirmed by repo-wide grep) -- it is plain,
-- code-shipped, non-tenant reference data with a direct table grant instead
-- of RLS: `grant select on app.procurement_metric_definitions to
-- authenticated, service_role;` (same migration, line 1351). This exactly
-- mirrors app.report_types'' own posture (COM-159, cited by both this
-- table''s own migration header, line 128-134, and server/queries/
-- procurement-dashboard.ts:108''s doc-comment) and app.milestone_codes'' posture
-- (OPS-173, `using (true)` for role authenticated -- functionally identical
-- to "no RLS, plain grant" from an authorization-outcome standpoint), which
-- this codebase''s own O1 remediation already closed as
-- app.list_milestone_codes (cluster 3 batch 2): zero parameters, zero
-- in-function authority check, `security invoker` (the unmarked default), no
-- `set search_path` on the app.* function itself. This function follows that
-- exact precedent.
create function app.list_active_procurement_metric_definitions()
returns setof app.procurement_metric_definitions
language sql
stable
as $$
  select * from app.procurement_metric_definitions
  where is_current and status = 'active'
  order by metric_group asc;
$$;

comment on function app.list_active_procurement_metric_definitions() is
  'PRC-266/O1 remediation: every current, active procurement metric/report definition, metric_group ascending, replacing server/queries/procurement-dashboard.ts:110''s broken .from("procurement_metric_definitions").select("*").eq("is_current", true).eq("status", "active").order("metric_group", { ascending: true }) (app is not exposed to PostgREST). Zero parameters, zero in-function authority check -- app.procurement_metric_definitions carries no tenant_id/owner_user_id column at all and no RLS is enabled on it (confirmed by repo-wide grep of "enable row level security"); it is plain code-shipped reference data with a direct `grant select ... to authenticated, service_role`. Deliberately `security invoker` (the unmarked default), not `security definer`: this function runs as the real calling role, which already holds that direct table-level grant -- matching this codebase''s own established shape for a zero-actor-param global reference table (app.list_milestone_codes, app.list_finance_currencies, app.list_finance_rounding_modes, app.list_api_versions, app.list_webhook_event_types, all unmarked-invoker over an identical broadly-readable-registry shape). No RULE A guard: no actor parameter exists to protect.';

create function public.list_active_procurement_metric_definitions()
returns setof app.procurement_metric_definitions
language sql
stable
set search_path = pg_catalog, pg_temp
as $wrap$
  select * from app.list_active_procurement_metric_definitions();
$wrap$;

comment on function public.list_active_procurement_metric_definitions() is
  'Option-2 wrapper: app is not exposed to PostgREST; this is a thin pass-through to app.list_active_procurement_metric_definitions with an identical grant set and an identical security mode (invoker), never a reimplementation.';

revoke execute on function app.list_active_procurement_metric_definitions() from public;
grant execute on function app.list_active_procurement_metric_definitions() to authenticated, service_role;

revoke execute on function public.list_active_procurement_metric_definitions() from anon, authenticated, service_role, public;
grant execute on function public.list_active_procurement_metric_definitions() to authenticated, service_role;

-- ===========================================================================
-- 3. app.list_document_requirement_definitions -- replaces server/queries/
--    document-requirement.ts:77 (listDocumentRequirementDefinitions)
-- ===========================================================================
-- Replaces: `.from("document_requirement_definitions").select("*")
-- .eq("tenant_id", tenantId)` optionally `.eq("status", input.status)`.
--
-- Table (base table, not a view): app.document_requirement_definitions,
-- created at 20260728090000_create_operations_document_requirement.sql:56.
--
-- RULE B (RLS predicate currency) -- live discrepancy found, same shape as
-- this series has repeatedly found elsewhere: `create policy
-- document_requirement_definitions_select_scoped on app.document_requirement_
-- definitions` (same file, line 611-613) originally read:
--   using (app.has_active_tenant_membership(tenant_id) or app.is_supreme_admin());
-- It was LATER rewritten by `alter policy
-- document_requirement_definitions_select_scoped on app.document_requirement_
-- definitions` in 20260730560000_harden_customer_user_layer_default_deny.sql:124-125
-- to:
--   using (((app.has_active_tenant_membership(tenant_id) AND NOT
--            app.actor_holds_customer_user_layer(tenant_id)) OR app.is_supreme_admin()));
-- Confirmed via `grep -rn "document_requirement_definitions_select_scoped"
-- supabase/migrations/*.sql` that ONLY these two files reference the policy
-- name -- 20260730560000 is the current, final version. THIS function
-- reproduces that CURRENT (narrower) predicate.
--
-- RULE A: p_actor_auth_user_id is a new, explicit parameter (the original TS
-- signature took none -- see TS INTEGRATION below for the disclosed
-- signature change) and this function is granted to `authenticated` ->
-- `perform app.assert_actor_is_session_identity(p_actor_auth_user_id);` is
-- the first executable statement.
--
-- p_status defaults to null (list all statuses), matching the original TS
-- input's own optional `status?` field exactly -- when supplied, the original
-- applied a second `.eq("status", ...)` filter; this function reproduces that
-- as `and (p_status is null or status = p_status)`.
create function app.list_document_requirement_definitions(
  p_tenant_id uuid,
  p_actor_auth_user_id uuid,
  p_status text default null
)
returns setof app.document_requirement_definitions
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  if not (
    (app.has_active_tenant_membership(p_tenant_id, p_actor_auth_user_id)
       and not app.actor_holds_customer_user_layer(p_tenant_id, p_actor_auth_user_id))
    or app.is_supreme_admin(p_actor_auth_user_id)
  ) then
    raise exception 'insufficient_authority: identity % cannot list document requirement definitions for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  return query
    select *
    from app.document_requirement_definitions
    where tenant_id = p_tenant_id
      and (p_status is null or status = p_status);
end;
$$;

comment on function app.list_document_requirement_definitions(uuid, uuid, text) is
  'OPS-176/O1 remediation: every document requirement definition for one tenant, optionally filtered to one status (any status when p_status is null), replacing server/queries/document-requirement.ts:77''s broken .from("document_requirement_definitions").select("*").eq("tenant_id", tenantId)[.eq("status", input.status)] (app is not exposed to PostgREST). Authority reproduces the CURRENT document_requirement_definitions_select_scoped RLS predicate (has_active_tenant_membership AND NOT actor_holds_customer_user_layer, OR is_supreme_admin) as rewritten by 20260730560000_harden_customer_user_layer_default_deny.sql. Raises insufficient_authority (never a silent empty list) when the actor has no standing for p_tenant_id at all. No explicit ordering -- the original .from() call applied none either. Tenant-wide policy/reference data -- broadly readable within the tenant, mirroring the shape server/queries/document-requirement.ts:72''s own doc-comment describes -- so every column is returned unconditionally, never masked.';

create function public.list_document_requirement_definitions(
  p_tenant_id uuid,
  p_actor_auth_user_id uuid,
  p_status text default null
)
returns setof app.document_requirement_definitions
language sql
stable
security definer
set search_path = pg_catalog, pg_temp
as $wrap$
  select * from app.list_document_requirement_definitions(p_tenant_id, p_actor_auth_user_id, p_status);
$wrap$;

comment on function public.list_document_requirement_definitions(uuid, uuid, text) is
  'Option-2 wrapper: app is not exposed to PostgREST; this is a thin security-definer pass-through to app.list_document_requirement_definitions with an identical grant set, never a reimplementation.';

revoke execute on function app.list_document_requirement_definitions(uuid, uuid, text) from public;
grant execute on function app.list_document_requirement_definitions(uuid, uuid, text) to authenticated, service_role;

revoke execute on function public.list_document_requirement_definitions(uuid, uuid, text) from anon, authenticated, service_role, public;
grant execute on function public.list_document_requirement_definitions(uuid, uuid, text) to authenticated, service_role;

-- ===========================================================================
-- 4. app.list_document_types -- replaces server/queries/document.ts:94
--    (listDocumentTypes)
-- ===========================================================================
-- Replaces: `.from("document_types").select("*")`.
--
-- app.document_types (20260719140000_create_document_file_engine.sql:109-113)
-- has RLS enabled with a genuinely open policy: `create policy
-- document_types_select_all on app.document_types for select to authenticated
-- using (true);` (same file, line 900-902). `grep -rn
-- "document_types_select_all" supabase/migrations/*.sql` -- exactly ONE hit,
-- no later `alter policy` exists -- this predicate has never been narrowed.
-- Mirrors app.list_milestone_codes'' own precedent exactly (a `using (true)`
-- table, zero parameters, zero in-function check, unmarked `security
-- invoker`) -- this function runs as the real calling role, which passes that
-- `using (true)` policy unconditionally for any authenticated session.
--
-- server/queries/document.ts:93''s own listDocumentTypes has ZERO real
-- production callers today (confirmed via repo-wide grep of the export name
-- across app/**/*.tsx and server/**/*.ts) -- only server/queries/
-- document.test.ts exercises it. This migration still adds the wrapper
-- (matching this cluster''s own explicit scope, all 4 named call sites), but
-- flags the current dead-code status here so it is not mistaken for a live
-- regression fix, mirroring cluster 4 batch 1''s own disclosure for
-- app.list_device_vehicle_assignment_history.
create function app.list_document_types()
returns setof app.document_types
language sql
stable
as $$
  select * from app.document_types;
$$;

comment on function app.list_document_types() is
  'PLT-128/O1 remediation: the full document-type registry, replacing server/queries/document.ts:94''s broken .from("document_types").select("*") (app is not exposed to PostgREST). Zero parameters, zero in-function authority check -- app.document_types'' own only-ever-declared SELECT policy, document_types_select_all, is a bare `using (true)` for role authenticated (20260719140000_create_document_file_engine.sql:900-902; no later alter of this policy exists anywhere in supabase/migrations, confirmed by repo-wide grep of the policy name). Deliberately `security invoker` (the unmarked default), matching this codebase''s own established shape for a zero-actor-param, genuinely-open-RLS reference table (app.list_milestone_codes'' identical precedent). No explicit ordering -- the original .from() call applied none. server/queries/document.ts:93''s own listDocumentTypes has zero real production callers today (only a unit test) -- this wrapper is added regardless, per this cluster''s own explicit closure scope.';

create function public.list_document_types()
returns setof app.document_types
language sql
stable
set search_path = pg_catalog, pg_temp
as $wrap$
  select * from app.list_document_types();
$wrap$;

comment on function public.list_document_types() is
  'Option-2 wrapper: app is not exposed to PostgREST; this is a thin pass-through to app.list_document_types with an identical grant set and an identical security mode (invoker), never a reimplementation.';

revoke execute on function app.list_document_types() from public;
grant execute on function app.list_document_types() to authenticated, service_role;

revoke execute on function public.list_document_types() from anon, authenticated, service_role, public;
grant execute on function public.list_document_types() to authenticated, service_role;

-- ===========================================================================
-- RULE A / RULE B SELF-CHECK (re-read before shipping)
-- ===========================================================================
-- RULE A: app.list_procurement_approval_policy_versions and app.list_document_
-- requirement_definitions both take an explicit p_actor_auth_user_id and are
-- granted to `authenticated` -- `perform
-- app.assert_actor_is_session_identity(p_actor_auth_user_id);` is the first
-- statement inside `begin ... end` in both, before any lookup, any
-- has_active_tenant_membership/actor_holds_customer_user_layer/
-- is_supreme_admin call, and any `return query`. app.list_active_procurement_
-- metric_definitions and app.list_document_types take no actor parameter at
-- all, so RULE A does not apply to either (no identity claim exists to
-- cross-check) -- consistent with both being genuine SECURITY INVOKER,
-- zero-actor-param functions over a table with either no RLS at all or a
-- bare `using (true)` policy.
--
-- RULE B: every RLS predicate reproduced above was re-derived from a live
-- grep of both the original `create policy` and any later `alter policy`
-- statement (bare policy name, case-insensitive, sorted by filename) --
-- documented per-function above, not assumed to transfer from a sibling
-- table.
--
-- RULE C: app.get_approval_requests_entity_refs (reused, not reimplemented,
-- for the fifth call site) was re-confirmed as its own only body (no later
-- `create or replace`) before being cited as still-current.

-- ===========================================================================
-- TS INTEGRATION
-- ===========================================================================
--
-- File: server/queries/procurement-approval.ts.
--
-- 1) listProcurementApprovalPolicyVersions(client, tenantId) -- add a
--    required `actorAuthUserId: string` parameter. New body:
--
--      const { data, error } = await client.rpc("list_procurement_approval_policy_versions", {
--        p_tenant_id: tenantId,
--        p_actor_auth_user_id: actorAuthUserId,
--        p_limit: 200,
--      });
--      if (error) {
--        throw new ProcurementApprovalQueryError(error.message);
--      }
--      return (data ?? []).map((row: Record<string, unknown>) => parseProcurementApprovalPolicyVersion(row));
--
--    Return type unchanged. Behavior change (disclosed, matches app.list_
--    quotation_approval_rule_versions'' own precedent): an actor with NO
--    standing for tenantId at all now throws ProcurementApprovalQueryError
--    (insufficient_authority) instead of silently returning an empty array.
--    Real call site: app/(tenant)/[tenantSlug]/procurement/approvals/page.tsx:36
--    -- add `access.authUserId` (already in scope, already passed to the
--    inbox call on the line above).
--
-- 2) listProcurementApprovalInboxForActor -- swap the raw table read for the
--    already-existing shared RPC (SWAP_ONLY, see this migration''s own header
--    section above -- no signature change, actorAuthUserId is already a
--    parameter of this function):
--
--      const { data, error } = await client.rpc("get_approval_requests_entity_refs", {
--        p_ids: requestIds,
--        p_actor_auth_user_id: actorAuthUserId,
--      });
--
--    replacing `client.from("approval_requests").select("id, entity_type,
--    entity_id").in("id", requestIds)`. Keep the existing `if (error) { throw
--    new ProcurementApprovalQueryError(error.message); }` and downstream
--    mapping unchanged -- the returned row shape (id/entity_type/entity_id)
--    is identical.
--
-- 3) ProcurementApprovalQueryClient (line 33) narrows from
--    `Pick<SupabaseClient, "from" | "rpc">` to `Pick<SupabaseClient, "rpc">`
--    -- verified by reading the whole file: "from" appeared in exactly these
--    two functions, both converting to "rpc" above.
--
-- File: server/queries/procurement-dashboard.ts.
--
-- 4) listActiveProcurementMetricDefinitions(client) -- signature unchanged
--    (no actor parameter: the new function takes none either). New body:
--
--      const { data, error } = await client.rpc("list_active_procurement_metric_definitions");
--      if (error) {
--        throw new ProcurementDashboardQueryError(error.message);
--      }
--      return (data ?? []).map((row: Record<string, unknown>) => parseProcurementMetricDefinition(row));
--
--    (Or route it through this file''s own existing `callRpcRows` helper for
--    consistency with every other function in the file -- either shape is
--    behaviorally identical; the file''s own module-header comment describing
--    this as "a plain .from() read" needs updating to reflect the RPC swap.)
--    ProcurementDashboardQueryClient (line 44) narrows from
--    `Pick<SupabaseClient, "rpc" | "from">` to `Pick<SupabaseClient, "rpc">`
--    -- this was the file''s only "from" usage.
--
-- File: server/queries/document-requirement.ts.
--
-- 5) listDocumentRequirementDefinitions(client, input) -- input gains a
--    required `actorAuthUserId: string` field. New body:
--
--      const { data, error } = await client.rpc("list_document_requirement_definitions", {
--        p_tenant_id: input.tenantId,
--        p_actor_auth_user_id: input.actorAuthUserId,
--        p_status: input.status ?? null,
--      });
--      if (error) {
--        throw new DocumentRequirementQueryError(error.message);
--      }
--      return (data ?? []).map((row: Record<string, unknown>) => parseDocumentRequirementDefinition(row));
--
--    DocumentRequirementQueryClient (line 19) narrows from
--    `Pick<SupabaseClient, "from" | "rpc">` to `Pick<SupabaseClient, "rpc">`
--    -- this was the file''s only "from" usage. Zero real production callers
--    today (only a unit test) -- the new required field is a safe, disclosed
--    addition.
--
-- File: server/queries/document.ts.
--
-- 6) listDocumentTypes(client) -- signature unchanged (no actor parameter).
--    DocumentTypeLookupClient (line 79-83) changes from a `from()`-shaped
--    interface to an `rpc()`-shaped one:
--
--      export interface DocumentTypeLookupClient {
--        rpc(fn: "list_document_types"): Promise<{ data: unknown[] | null; error: { message: string } | null }>;
--      }
--
--    New body:
--
--      const { data, error } = await client.rpc("list_document_types");
--      if (error) {
--        throw new DocumentTypeLookupError(error.message);
--      }
--      return (data ?? []).map((row) => parseDocumentType(row as Record<string, unknown>));
--
--    The module-header comment (line 17-18) asserting listDocumentTypes
--    "stays a direct read" needs updating -- that assertion predates this
--    migration and was already wrong in production (schema app is never
--    exposed to PostgREST regardless of how permissive the table''s own RLS
--    policy is), the same defect class this whole migration closes.
