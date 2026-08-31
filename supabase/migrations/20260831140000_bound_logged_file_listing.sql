-- The fourth route named by `ISS-2026-238`: `listFilesForTenant`.
--
-- The Tier C sweep reclassified this one to Medium after finding it had been misfiled as a
-- "config/rule/directory-shaped table naturally bounded by business cardinality". It is not:
-- `app.files` is a polymorphic attachment table keyed by `record_type`/`record_id`, referenced
-- from shipment orders, employees, claims, portal documents and GPS evidence across 10+
-- migrations. It accumulates rows per business event, with no ceiling.
--
-- WHY THE CAP MATTERS MORE HERE THAN ON THE OTHER THREE
--
--   The other three are plain `select`s: unbounded, they cost a large read and a large payload.
--   This one is not. `app.list_files_for_tenant` (ISS-2026-172(b)) composes
--   `app.authorize_file_access` **per row**, which is what makes the path logged -- and that
--   writes an `app.file_access_logs` row for every file it returns. Unbounded, one page load
--   does not merely read a lot; it *writes* a lot, filling the access log with entries nobody
--   asked for and burying the real ones.
--
--   So the fix is not only cheaper, it also stops the audit trail being diluted by its own
--   listing path.
--
-- DROP + CREATE, not CREATE OR REPLACE: appending even a defaulted parameter produces a SECOND
-- overload and makes every existing call site ambiguous (ISS-2026-260). There is one caller,
-- `server/queries/document.ts`, and it is updated in the same commit.

drop function public.list_files_for_tenant(uuid, uuid, uuid);
drop function app.list_files_for_tenant(uuid, uuid, uuid);

create function app.list_files_for_tenant(
  p_tenant_id uuid,
  p_actor_auth_user_id uuid,
  p_correlation_id uuid default null,
  p_limit integer default 200
)
returns setof app.files
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_file app.files;
  v_returned integer := 0;
  -- Same 200 the RPC layer already uses for its own transactional lists, and the same the
  -- TypeScript bounded-list helper uses. Clamped rather than rejected: a caller asking for
  -- 100,000 rows has made a mistake, and failing their page is a worse answer than serving the
  -- first 200 -- especially here, where the alternative is writing 100,000 audit rows.
  v_limit integer := least(greatest(coalesce(p_limit, 200), 1), 200);
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  if not app.has_active_tenant_membership(p_tenant_id, p_actor_auth_user_id) then
    raise exception 'document_listing_unauthorized: identity % has no active membership in tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  for v_file in
    select f.* from app.files f
    where f.tenant_id = p_tenant_id
    order by f.created_at desc, f.id
  loop
    -- The cap is counted on rows RETURNED, not rows scanned, and the exit happens before
    -- app.authorize_file_access is called again. That ordering is the point: counting scanned
    -- rows would still write an access-log entry for every unauthorized row it stepped over.
    exit when v_returned >= v_limit;

    begin
      perform app.authorize_file_access(v_file.id, 'metadata_view', p_actor_auth_user_id, p_correlation_id);
    exception
      when insufficient_privilege then continue;
      when no_data_found then continue;
    end;
    v_returned := v_returned + 1;
    return next v_file;
  end loop;
end;
$$;

comment on function app.list_files_for_tenant is
  'ISS-2026-172(b): the LOGGED metadata-listing path for app.files -- composes app.authorize_file_access per row with access_type=''metadata_view'', so every row returned leaves an app.file_access_logs entry, which a direct RLS read cannot do because PostgreSQL has no SELECT trigger. A row the actor may not see is skipped rather than raising, so the listing stays usable and does not disclose that row''s existence through an error. ISS-2026-238 (20260831140000): capped at 200, clamped rather than rejected. The cap matters more here than on the other unbounded reads that finding named, because this path WRITES an access-log row per row returned -- unbounded, one page load would bury the real audit entries under its own listing. The limit counts rows RETURNED and exits before the next authorize call, so a skipped unauthorized row costs nothing.';

revoke execute on function app.list_files_for_tenant(uuid, uuid, uuid, integer) from public;
grant execute on function app.list_files_for_tenant(uuid, uuid, uuid, integer) to authenticated, service_role;

create function public.list_files_for_tenant(p_tenant_id uuid, p_actor_auth_user_id uuid, p_correlation_id uuid default null, p_limit integer default 200)
returns setof app.files
language sql
security definer
set search_path = app, public, pg_temp
as $wrap$
  select * from app.list_files_for_tenant(p_tenant_id, p_actor_auth_user_id, p_correlation_id, p_limit);
$wrap$;

comment on function public.list_files_for_tenant(uuid, uuid, uuid, integer) is
  'RGL-394 Option-2 wrapper: a thin security-definer pass-through to app.list_files_for_tenant, never a reimplementation.';

-- `from anon, ...`, not `from public` alone: Supabase's ALTER DEFAULT PRIVILEGES grants anon
-- EXECUTE explicitly at CREATE time, and an explicit grant survives a PUBLIC revoke (ISS-2026-309).
revoke execute on function public.list_files_for_tenant(uuid, uuid, uuid, integer) from anon, authenticated, service_role, public;
grant execute on function public.list_files_for_tenant(uuid, uuid, uuid, integer) to authenticated, service_role;
