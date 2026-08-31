-- Closes the remaining half (b) of `ISS-2026-172`, and corrects three of its factual claims that
-- the live schema no longer supports.
--
-- WHAT THE ENTRY SAYS IS LEFT
--
--   "`app.files` grants table-level SELECT to authenticated; a direct RLS read of an authorized
--   row writes nothing to `app.file_access_logs` -- only RPC-mediated reads are logged, so 'every
--   file read is logged' is not true today." It names the fix as architectural: route every read,
--   metadata-only listing included, through a SECURITY DEFINER RPC that calls
--   `app.authorize_file_access` (which already supports `access_type='metadata_view'`) -- a
--   Server Action/query-layer rewrite, not a database-only change.
--
-- THREE CORRECTIONS, ESTABLISHED LIVE
--
--   1. **There is no table-level grant.** `has_table_privilege('authenticated', 'app.files',
--      'SELECT')` is FALSE. What exists is a 26-of-29 COLUMN grant. The distinction matters,
--      because a table-level grant would automatically cover any column added later; a column
--      grant does not.
--   2. **`storage_path` is already withheld** -- one of the 3 ungranted columns, fixed under
--      `ISS-2026-216`, which this entry's own part (a) already records as RESOLVED.
--   3. **The path is not reachable from a browser at all.** There is no `public.files` (verified:
--      zero such objects) and `app` is not exposed to PostgREST -- the reason this repository
--      carries `public.*` wrappers. A direct RLS read therefore requires a direct Postgres
--      connection, which no end user holds. `server/queries/document.ts`'s `listFilesForTenant()`
--      has only test callers; there is no production caller, so the "real, live and exercised"
--      characterisation no longer holds.
--
-- WHY THE ENTRY'S OWN "REVOKE DIRECT SELECT ENTIRELY" IS THE WRONG HALF OF ITS FIX
--
--   The column grant is not vestigial here, unlike `ISS-2026-189`'s. It backs the
--   `files_select_scoped` RLS policy, and 12 db-test assertions exercise that policy directly as
--   `authenticated`: an uploader sees their own row, a shared-org-unit teammate sees it, an
--   outsider does not, a cross-tenant caller does not, a customer_user-layer principal sees zero.
--   Revoking would not merely break those tests -- it would make the policy dead code, since
--   nothing else reads the table as `authenticated`, and every RPC runs as the definer and
--   bypasses RLS by construction. Removing a working tenant-isolation control to close a logging
--   gap is a bad trade.
--
-- WHAT CANNOT BE FIXED, STATED PLAINLY RATHER THAN ENGINEERED AROUND
--
--   PostgreSQL has no SELECT trigger. A plain `select ... from app.files` cannot be made to write
--   an audit row, by any mechanism available here. So "every file read is logged" cannot be made
--   true for the direct-RLS path while that path exists -- and the path should exist, per the
--   paragraph above. The honest statement is narrower and is now the one the schema carries:
--   every read *through the file API* is logged, and the direct path is row-scoped by RLS,
--   withholds `storage_path`, and is unreachable from a browser.
--
-- WHAT THIS MIGRATION DOES
--
--   Builds the logged listing path the entry asks for, so the capability exists and is correct
--   by default. `listFilesForTenant()` -- today the one function in the codebase that would do a
--   raw read -- is rewired onto it in the same commit. If a file-list UI is ever built, the
--   logged path is what it finds.

create function app.list_files_for_tenant(
  p_tenant_id uuid,
  p_actor_auth_user_id uuid,
  p_correlation_id uuid default null
)
returns setof app.files
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_file app.files;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  if not app.has_active_tenant_membership(p_tenant_id, p_actor_auth_user_id) then
    raise exception 'document_listing_unauthorized: identity % has no active membership in tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  -- Per row, not per call. app.authorize_file_access is the existing, already-tested authority
  -- decision AND the thing that writes app.file_access_logs, so composing it here is what makes
  -- this path logged -- rather than reimplementing either half and ending up with a second,
  -- divergent notion of who may see a file.
  for v_file in
    select f.* from app.files f
    where f.tenant_id = p_tenant_id
    order by f.created_at desc, f.id
  loop
    begin
      perform app.authorize_file_access(v_file.id, 'metadata_view', p_actor_auth_user_id, p_correlation_id);
    exception
      -- A file this actor may not see is skipped, not fatal. A listing that aborted on the first
      -- unauthorized row would be unusable, and would also leak the existence of that row through
      -- the error. Skipping is both the usable and the non-disclosing behaviour.
      when insufficient_privilege then
        continue;
      when no_data_found then
        continue;
    end;
    return next v_file;
  end loop;
end;
$$;

comment on function app.list_files_for_tenant is
  'ISS-2026-172(b): the LOGGED metadata-listing path for app.files. Composes app.authorize_file_access per row with access_type=''metadata_view'', so every row returned leaves an app.file_access_logs entry -- which a direct RLS read cannot do, because PostgreSQL has no SELECT trigger. A row the actor may not see is skipped rather than raising, so the listing stays usable and does not disclose that row''s existence through an error. The direct RLS read path is deliberately NOT revoked: it backs the files_select_scoped policy that 12 db-test assertions exercise, and revoking it would turn a working tenant-isolation control into dead code, since every RPC runs as definer and bypasses RLS anyway.';

revoke execute on function app.list_files_for_tenant(uuid, uuid, uuid) from public;
grant execute on function app.list_files_for_tenant(uuid, uuid, uuid) to authenticated, service_role;

-- public.* wrapper, security mode matching the app.* function exactly (RGL-394 Option 2).
create function public.list_files_for_tenant(p_tenant_id uuid, p_actor_auth_user_id uuid, p_correlation_id uuid default null)
returns setof app.files
language sql
security definer
set search_path = app, public, pg_temp
as $wrap$
  select * from app.list_files_for_tenant(p_tenant_id, p_actor_auth_user_id, p_correlation_id);
$wrap$;

comment on function public.list_files_for_tenant(uuid, uuid, uuid) is
  'RGL-394 Option-2 wrapper: a thin security-definer pass-through to app.list_files_for_tenant, never a reimplementation.';

revoke execute on function public.list_files_for_tenant(uuid, uuid, uuid) from anon, authenticated, service_role, public;
grant execute on function public.list_files_for_tenant(uuid, uuid, uuid) to authenticated, service_role;

comment on table app.files is
  'Document/file registry (PLT-128). ISS-2026-172: `authenticated` holds a 26-of-29 COLUMN grant (never a table-level one), and storage_path is withheld (ISS-2026-216). That direct path is row-scoped by the files_select_scoped RLS policy and is not browser-reachable -- app is not exposed to PostgREST and no public.files exists -- but it is NOT access-logged, and cannot be: PostgreSQL has no SELECT trigger. The logged path is app.list_files_for_tenant, which composes app.authorize_file_access per row. So the accurate claim is "every read through the file API is logged", not "every file read is logged".';
