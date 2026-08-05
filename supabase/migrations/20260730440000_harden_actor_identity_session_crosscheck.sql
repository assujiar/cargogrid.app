-- CG-S10-ATW-031 (post-Prompt-248 codebase audit — closes `ISS-2026-017`).
--
-- Every `SECURITY DEFINER` RPC in this repository takes the acting identity as an
-- ordinary parameter (`p_actor_auth_user_id`) and trusts it as given. None cross-checked
-- it against `auth.uid()` — the real, session-bound identity of the calling Postgres
-- role, read from the JWT PostgREST/Supabase sets per request. Any `authenticated`
-- session holding EXECUTE on such a function could therefore pass an ARBITRARY UUID and
-- have every downstream authority decision, record-scope check, and audit entry evaluated
-- as that other user.
--
-- `ISS-2026-017` recorded this as repository-wide with "no confirmed live exploit" —
-- true, because every caller today is this repository's own TypeScript service layer,
-- which derives the actor from the server-resolved session (independently re-verified at
-- `ATW-030`: all `actorAuthUserId` call sites in `app/` read `access.authUserId`, never
-- form data). That is a property of the current callers, not of the database. Any future
-- direct RPC consumer — a mobile client, a partner integration, the REST/GraphQL surfaces
-- Phase 8/9 will add — inherits a full impersonation primitive the moment it appears.
--
-- ===========================================================================
-- Where the check goes, and why one place is enough
-- ===========================================================================
--
-- `app.evaluate_permission` is the single authority gate 416 of these functions already
-- call. A repository-wide sweep this checkpoint confirmed it is ALWAYS called with the
-- request's own actor as its first argument — there is no "can user X do Y?" preview path
-- anywhere that legitimately passes a third party's id — so the check can be made
-- unconditional there without breaking a real caller. That is a single, auditable choke
-- point rather than ~600 near-identical edits, each of which would be its own chance to
-- get one wrong.
--
-- ===========================================================================
-- Why it is safe for every existing caller
-- ===========================================================================
--
-- The assertion is a no-op whenever `auth.uid()` is NULL. That covers, by construction:
--   * `service_role` and superuser connections (no JWT) — the server-side job runners,
--     the GPS gateway's ingest client, and every `scripts/db-tests/*.sql` invocation;
--   * any nested call already running inside a `SECURITY DEFINER` function.
-- It engages only for a genuine `authenticated` session, which is exactly the principal
-- the impersonation primitive was reachable from. A session that passes its own id — what
-- the TypeScript layer already does — is unaffected.
--
-- `auth.uid()` is also called defensively: if the `auth` schema is absent or the JWT claim
-- is malformed, the helper treats the session as unauthenticated rather than raising, so a
-- deployment without Supabase's auth schema fails open to today's behavior rather than
-- bricking every authority check.
--
-- Residual, disclosed: ~315 functions accept `p_actor_auth_user_id` without calling
-- `app.evaluate_permission` (helpers, readers, and functions that delegate to another
-- function which does check). They are not newly exposed by this migration — they are
-- simply not covered by it. Recorded as `ISS-2026-032`.
--
-- Additive and reversible: one new function and one `CREATE OR REPLACE FUNCTION` on an
-- identical signature. No table, column, index, constraint, grant, or policy is touched.
--
-- Per `ERR-2026-004`: this migration carries its own explicit `revoke execute on all
-- functions in schema app from public` before its final grants.

create or replace function app.assert_actor_is_session_identity(p_actor_auth_user_id uuid)
returns void
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_session_identity uuid;
begin
  -- Defensive: a deployment without Supabase's auth schema, or a malformed JWT claim,
  -- must degrade to "no session identity known" rather than raising -- otherwise this
  -- helper would brick every authority check in the database.
  begin
    v_session_identity := auth.uid();
  exception
    when others then
      v_session_identity := null;
  end;

  -- NULL session identity means service_role, superuser, or an already-nested
  -- SECURITY DEFINER call -- all trusted, all unaffected. The check engages only for a
  -- genuine authenticated session, the one principal that could impersonate.
  if v_session_identity is not null
     and p_actor_auth_user_id is not null
     and v_session_identity <> p_actor_auth_user_id then
    raise exception 'actor_identity_mismatch: the authenticated session is % but this call claims to act as % -- an RPC may not act on behalf of another identity', v_session_identity, p_actor_auth_user_id
      using errcode = 'insufficient_privilege';
  end if;
end;
$$;

comment on function app.assert_actor_is_session_identity is
  'ATW-031 (ISS-2026-017): rejects a call whose claimed p_actor_auth_user_id differs from auth.uid(), the real session-bound identity. A no-op when auth.uid() is NULL (service_role, superuser, db-tests, nested SECURITY DEFINER calls), so it engages only for a genuine authenticated session -- the one principal from which the impersonation primitive was reachable. Called from app.evaluate_permission, the single authority gate 416 functions already share.';

CREATE OR REPLACE FUNCTION app.evaluate_permission(p_auth_user_id uuid, p_tenant_id uuid, p_resource_module_code text, p_action text, p_as_of timestamp with time zone DEFAULT now())
 RETURNS app.rbac_decision
 LANGUAGE plpgsql
 STABLE
AS $function$
declare
  v_permission app.permissions;
  v_match record;
begin
  -- ATW-031 (ISS-2026-029/ISS-2026-017): every SECURITY DEFINER RPC in this repository
  -- takes the acting identity as an ordinary parameter and, until now, trusted it as
  -- given -- none cross-checked it against auth.uid(), the real session-bound identity of
  -- the calling Postgres role. Any `authenticated` session could therefore pass an
  -- arbitrary UUID and have every authority decision evaluated as that other user.
  --
  -- This is the one place worth enforcing it: app.evaluate_permission is the single
  -- authority gate 416 functions already call, and a repository-wide sweep this
  -- checkpoint confirmed it is ALWAYS called with the request's own actor as its first
  -- argument -- zero call sites pass a third party's id (no "can user X do Y?" preview
  -- path exists), so the check can be made unconditional here without breaking a
  -- legitimate caller.
  perform app.assert_actor_is_session_identity(p_auth_user_id);
  select * into v_permission
  from app.permissions
  where resource_module_code = p_resource_module_code and action = p_action;

  if not found then
    return row(false, 'unknown_permission', null, null, null, p_as_of)::app.rbac_decision;
  end if;

  if exists (
    select 1 from app.principal_memberships
    where auth_user_id = p_auth_user_id and layer = 'supreme_admin' and status = 'active'
  ) then
    return row(true, 'supreme_admin_exception', v_permission.id, null, null, p_as_of)::app.rbac_decision;
  end if;

  -- The join to role_versions on status = 'published' is what makes a stale assignment
  -- (still 'active' in app.role_assignments, but pointing at a version PLT-111's
  -- publish_role_version() has since archived by superseding it) fail closed -- exactly
  -- Prompt 112 §23's "stale ... permission fails closed." No auto-reassignment to the new
  -- published version happens anywhere in this repository; that is a disclosed, bounded
  -- limitation of this checkpoint, not an oversight (see PLT-112.md §2/§8).
  select ra.id as assignment_id, rv.id as role_version_id, rv.role_id
  into v_match
  from app.role_assignments ra
  join app.role_versions rv on rv.id = ra.role_version_id
  join app.role_version_permissions rvp on rvp.role_version_id = rv.id
  where ra.tenant_id = p_tenant_id
    and ra.auth_user_id = p_auth_user_id
    and ra.status = 'active'
    and rv.status = 'published'
    and rvp.permission_id = v_permission.id
  limit 1;

  if found then
    return row(true, 'role_grant', v_permission.id, v_match.role_id, v_match.role_version_id, p_as_of)::app.rbac_decision;
  end if;

  if exists (
    select 1 from app.role_assignments
    where tenant_id = p_tenant_id and auth_user_id = p_auth_user_id and status = 'active'
  ) then
    return row(false, 'no_granting_role', v_permission.id, null, null, p_as_of)::app.rbac_decision;
  end if;

  return row(false, 'no_active_assignment', v_permission.id, null, null, p_as_of)::app.rbac_decision;
end;
$function$;


revoke execute on all functions in schema app from public;

grant execute on function app.evaluate_permission(uuid,uuid,text,text,timestamp with time zone) to service_role;
-- ATW-031: app.evaluate_permission is SECURITY INVOKER, so this nested helper runs as the
-- ORIGINAL caller and does need its own EXECUTE grant. Deliberately granted to
-- authenticated/service_role but NOT to anon: no anon-reachable path calls
-- app.evaluate_permission, and advanced-tms-canonical-telemetry-arbitration.sql carries a
-- regression guard on the exact anon-grant count that (correctly) rejected a wider grant
-- during this audit.
grant execute on function app.assert_actor_is_session_identity(uuid) to authenticated, service_role;
