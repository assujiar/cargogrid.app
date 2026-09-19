-- CG-AUDIT-2026-09-02 A4: two read gaps in the same capability, closed together.
--
-- (1) No read RPC exists anywhere to list a job's own staged rows
-- (raw_payload/validation_status/error) for display -- the only existing read,
-- app.preview_import_job (PLT-131), returns just 4 aggregate counts
-- (total/valid/invalid/pending), so a caller can tell a row is invalid but never
-- learn WHICH row or WHY without app.list_import_staging_rows below. This is the
-- concrete blocker behind any real import UI ever being able to show a reviewer
-- their own validation errors before committing.
--
-- (2) app.jobs itself carries a real "direct-table RLS for authenticated" policy
-- (20260719170000_create_import_export_job_framework.sql:85-87/944-951), but that
-- is only reachable over a raw Postgres connection (this repository's own
-- db-tests) -- "app is not exposed to PostgREST" (every Option-2 wrapper's own
-- comment, this migration's included) and no public.jobs view exists, so a real
-- caller through the Supabase JS client has NO way to read a job's own full row
-- (status/payload/source_file_id/counts) at all. app.get_import_export_job below
-- closes that gap -- without it, a real import UI cannot recover "which job is in
-- progress, and what state is it in" across a page reload.
--
-- Mirrors app.preview_import_job's own precedent exactly (same migration,
-- 20260719170000_create_import_export_job_framework.sql:596-622): the one
-- authenticated-facing read in this whole capability, SECURITY DEFINER
-- (app.import_staging_rows itself carries zero authenticated grant --
-- "raw imported content, not yet validated" per that migration's own
-- header), gated identically to app.preview_import_job (the job's own
-- requester, or their tenant's support/Supreme authority via
-- app.check_import_export_admin_authority) -- deliberately the SAME
-- authority shape, since this is the same capability's own row-level detail
-- view of the exact same job a caller may already preview in aggregate.
create function app.list_import_staging_rows(p_job_id uuid, p_actor_auth_user_id uuid)
returns setof app.import_staging_rows
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_job app.jobs;
begin
  select * into v_job from app.jobs where job_id = p_job_id;
  if not found then
    raise exception 'import_export_job_not_found: no job %', p_job_id using errcode = 'no_data_found';
  end if;

  if not (v_job.requested_by_auth_user_id = p_actor_auth_user_id or app.check_import_export_admin_authority(v_job.tenant_id, p_actor_auth_user_id)) then
    raise exception 'job_actor_unauthorized: identity % may not list job % rows', p_actor_auth_user_id, p_job_id
      using errcode = 'insufficient_privilege';
  end if;

  return query
  select * from app.import_staging_rows where job_id = p_job_id order by row_number;
end;
$$;

comment on function app.list_import_staging_rows is
  'CG-AUDIT-2026-09-02 A4: row-level sibling of app.preview_import_job -- same authority gate (job requester or tenant support/Supreme authority), same SECURITY DEFINER shape, since app.import_staging_rows carries zero direct authenticated grant. Returns every staged row (raw_payload/validation_status/error) for one job, ordered by row_number, so a caller can show a reviewer exactly which rows failed and why before committing.';

revoke execute on all functions in schema app from public;

grant execute on function app.list_import_staging_rows(uuid, uuid) to authenticated, service_role;

-- Option-2 PostgREST wrapper (mode parity with app.list_import_staging_rows).
create function public.list_import_staging_rows(p_job_id uuid, p_actor_auth_user_id uuid)
returns setof app.import_staging_rows
language sql
security definer
set search_path = pg_catalog, pg_temp
as $wrap$
  select * from app.list_import_staging_rows(p_job_id, p_actor_auth_user_id);
$wrap$;

comment on function public.list_import_staging_rows(p_job_id uuid, p_actor_auth_user_id uuid) is
  'RGL-394 Option-2 wrapper: app is not exposed to PostgREST; this is a thin security-definer pass-through to app.list_import_staging_rows with an identical grant set, never a reimplementation. See docs/build-log/release-go-live/RGL-394.md.';

revoke execute on function public.list_import_staging_rows(p_job_id uuid, p_actor_auth_user_id uuid) from anon, authenticated, service_role, public;
grant execute on function public.list_import_staging_rows(p_job_id uuid, p_actor_auth_user_id uuid) to service_role;
grant execute on function public.list_import_staging_rows(p_job_id uuid, p_actor_auth_user_id uuid) to authenticated;

-- Second gap from this migration's own header (2): the one full-row read for
-- app.jobs, same authority shape as the two functions above.
create function app.get_import_export_job(p_job_id uuid, p_actor_auth_user_id uuid)
returns app.jobs
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_job app.jobs;
begin
  select * into v_job from app.jobs where job_id = p_job_id;
  if not found then
    raise exception 'import_export_job_not_found: no job %', p_job_id using errcode = 'no_data_found';
  end if;

  if not (v_job.requested_by_auth_user_id = p_actor_auth_user_id or app.check_import_export_admin_authority(v_job.tenant_id, p_actor_auth_user_id)) then
    raise exception 'job_actor_unauthorized: identity % may not read job %', p_actor_auth_user_id, p_job_id
      using errcode = 'insufficient_privilege';
  end if;

  return v_job;
end;
$$;

comment on function app.get_import_export_job is
  'CG-AUDIT-2026-09-02 A4: the one full-row read for app.jobs reachable through PostgREST -- app.jobs own direct-table RLS for authenticated is real but unreachable from the JS client surface (app is not exposed to PostgREST). Same authority gate as app.preview_import_job/app.list_import_staging_rows.';

revoke execute on all functions in schema app from public;

grant execute on function app.get_import_export_job(uuid, uuid) to authenticated, service_role;

create function public.get_import_export_job(p_job_id uuid, p_actor_auth_user_id uuid)
returns app.jobs
language sql
security definer
set search_path = pg_catalog, pg_temp
as $wrap$
  select app.get_import_export_job(p_job_id, p_actor_auth_user_id);
$wrap$;

comment on function public.get_import_export_job(p_job_id uuid, p_actor_auth_user_id uuid) is
  'RGL-394 Option-2 wrapper: app is not exposed to PostgREST; this is a thin security-definer pass-through to app.get_import_export_job with an identical grant set, never a reimplementation. See docs/build-log/release-go-live/RGL-394.md.';

revoke execute on function public.get_import_export_job(p_job_id uuid, p_actor_auth_user_id uuid) from anon, authenticated, service_role, public;
grant execute on function public.get_import_export_job(p_job_id uuid, p_actor_auth_user_id uuid) to service_role;
grant execute on function public.get_import_export_job(p_job_id uuid, p_actor_auth_user_id uuid) to authenticated;
