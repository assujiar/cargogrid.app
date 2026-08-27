-- ISS-2026-271 (Step 16 historical-issue-backlog remediation, docs/runtime/KNOWN_ISSUES.md)
-- -- no rollback_import_job/undo_import_job/revert_import_job RPC exists anywhere in this
-- codebase; a manual, FK-ordered raw-SQL delete (lifecycle events -> employees ->
-- master_records -> staging rows -> job row) was live-proved to work cleanly but left 2
-- real residues: (a) app.audit_logs rows permanently reference a resource_id (the deleted
-- job row) that no longer exists anywhere, a dangling, unresolvable audit-trail entry;
-- (b) app.employee_number_counters.last_seq is untouched, so a burned auto-generated
-- number is never reclaimed. This entry's own text also flags the deeper, unexercised
-- risk: "a record with downstream references (payroll, position assignments) would likely
-- hit real FK blocks not exercised in this drill."
--
-- Fixed: app.rollback_employee_import_job, a real, governed RPC -- deliberately different
-- from the manual drill's own raw-delete shape in exactly the ways that close both
-- residues:
--   (a) the job row is never deleted -- its status moves to a new terminal value,
--       'rolled_back' (jobs_status_check widened), so every existing app.audit_logs row
--       that already references this job_id (e.g. the original commit's own audit event)
--       stays resolvable forever. The rollback itself is captured as one new, explicit
--       audit event, giving a human reading the trail later a real, findable answer for
--       "why did these employee/master_record rows disappear" instead of an unexplained
--       gap.
--   (b) app.employee_number_counters is deliberately left untouched -- that table's own
--       comment already states "Never reused" (mirroring app.vendor_code_counters,
--       PRC-251); decrementing it on rollback would risk a FUTURE import reusing a number
--       a different, concurrent import already consumed. A gap in the sequence from a
--       rollback is the same normal, safe behavior as a gap from any other cause -- not a
--       defect to fix.
--
-- The downstream-reference risk this entry itself flagged as unexercised is handled by
-- Postgres's own built-in foreign-key enforcement, not a hand-rolled completeness check:
-- every table in this schema that references app.employees does so with the default
-- (RESTRICT) delete behavior, confirmed by direct migration read -- no ON DELETE CASCADE
-- exists anywhere on an app.employees reference. A DELETE that would orphan a real
-- downstream row (payroll, position assignment, attendance, leave, etc., today or any
-- future table added later) is refused by the database itself with a genuine
-- foreign_key_violation, caught here and re-raised as a clear, named error rather than a
-- raw Postgres constraint message -- correct and complete by construction, since it relies
-- on the database's own authoritative FK catalog rather than a list this migration could
-- let drift out of date.
--
-- The set of master_record_ids this job created is resolved via app.employee_lifecycle_
-- events.metadata->>'job_id' -- the exact linkage app.commit_employee_import_job's own
-- creation-event insert already writes (`jsonb_build_object('source', 'bulk_import',
-- 'job_id', p_job_id)`), not a new mechanism invented for this fix.
alter table app.jobs drop constraint jobs_status_check;
alter table app.jobs add constraint jobs_status_check check (status in ('pending', 'in_progress', 'cancelling', 'cancelled', 'completed', 'failed', 'dead_letter', 'rolled_back'));

create function app.rollback_employee_import_job(
  p_job_id uuid,
  p_reason text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.jobs
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_job app.jobs;
  v_decision app.rbac_decision;
  v_master_record_ids uuid[];
  v_deleted_lifecycle_events integer;
  v_deleted_employees integer;
  v_deleted_master_records integer;
  v_deleted_staging_rows integer;
  v_updated app.jobs;
begin
  select * into v_job from app.jobs where job_id = p_job_id for update;
  if not found then
    raise exception 'import_export_job_not_found: no job %', p_job_id using errcode = 'no_data_found';
  end if;

  if v_job.job_type <> 'import' or v_job.import_export_schema_code <> 'employee_import' then
    raise exception 'import_export_wrong_schema: job % is not an employee_import job', p_job_id using errcode = 'check_violation';
  end if;

  if not app.check_import_export_job_authority(v_job.tenant_id, p_actor_auth_user_id) then
    raise exception 'job_actor_unauthorized: identity % lacks active membership in tenant %', p_actor_auth_user_id, v_job.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_job.tenant_id, 'HRS', 'Import');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks HRS:Import (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_job.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_job.status <> 'completed' then
    raise exception 'import_export_job_not_rollbackable: job % is %, only a completed job may be rolled back', p_job_id, v_job.status
      using errcode = 'check_violation';
  end if;

  if coalesce(trim(p_reason), '') = '' then
    raise exception 'employee_import_rollback_reason_required: a real, non-empty reason is required to roll back a completed import' using errcode = 'check_violation';
  end if;

  select coalesce(array_agg(distinct master_record_id), '{}')
  into v_master_record_ids
  from app.employee_lifecycle_events
  where tenant_id = v_job.tenant_id and metadata ->> 'job_id' = p_job_id::text;

  if array_length(v_master_record_ids, 1) is null then
    raise exception 'employee_import_rollback_no_records: job % created no employee records to roll back (already rolled back, or nothing was ever committed)', p_job_id
      using errcode = 'no_data_found';
  end if;

  begin
    delete from app.employee_lifecycle_events where master_record_id = any (v_master_record_ids);
    get diagnostics v_deleted_lifecycle_events = row_count;

    delete from app.employees where master_record_id = any (v_master_record_ids);
    get diagnostics v_deleted_employees = row_count;

    delete from app.master_records where id = any (v_master_record_ids);
    get diagnostics v_deleted_master_records = row_count;

    delete from app.import_staging_rows where job_id = p_job_id;
    get diagnostics v_deleted_staging_rows = row_count;
  exception
    when foreign_key_violation then
      raise exception 'employee_import_rollback_blocked_by_downstream_references: job % created % employee record(s), and at least one now has real downstream references (e.g. payroll, position assignment, attendance, leave) that must be removed first -- refusing to silently orphan or cascade-delete them', p_job_id, array_length(v_master_record_ids, 1)
        using errcode = 'foreign_key_violation';
  end;

  update app.jobs
  set status = 'rolled_back', error = p_reason
  where job_id = p_job_id
  returning * into v_updated;

  perform app.capture_audit_event(
    v_job.tenant_id, p_actor_auth_user_id, p_actor_label, 'rollback_employee_import_job',
    'app.jobs', p_job_id, 'success', p_reason,
    to_jsonb(v_job),
    jsonb_build_object(
      'master_records_deleted', v_deleted_master_records,
      'employees_deleted', v_deleted_employees,
      'lifecycle_events_deleted', v_deleted_lifecycle_events,
      'staging_rows_deleted', v_deleted_staging_rows
    )
  );

  return v_updated;
end;
$$;

comment on function app.rollback_employee_import_job is 'ISS-2026-271: a real, governed rollback for a completed app.commit_employee_import_job run. Deletes the employee/master_record/lifecycle-event/staging rows this specific job created (resolved via app.employee_lifecycle_events.metadata->>''job_id''), refuses cleanly (foreign_key_violation, caught and re-raised as employee_import_rollback_blocked_by_downstream_references) if any created employee now has a real downstream reference (payroll, position assignment, etc. -- enforced by Postgres''s own default RESTRICT delete behavior, not a hand-maintained table list). The job row itself is never deleted -- its status moves to ''rolled_back'' so every audit_logs row already referencing this job_id stays resolvable, and this rollback''s own effect is captured as one new, explicit audit event. app.employee_number_counters is deliberately left untouched -- see this migration''s own header for why reclaiming a burned number would be unsafe, not merely unimplemented.';

revoke execute on all functions in schema app from public;
grant execute on function app.rollback_employee_import_job(uuid, text, uuid, text) to authenticated, service_role;

-- Option 2 wrapper (RGL-394): app is not exposed to PostgREST directly -- every
-- externally-callable app.* function needs a matching public.* wrapper, enforced by
-- scripts/db-tests/public-api-wrapper-regression.sql's own zero-tolerance guard.
create function public.rollback_employee_import_job(p_job_id uuid, p_reason text, p_actor_auth_user_id uuid, p_actor_label text)
returns app.jobs
language sql
volatile
security definer
set search_path = pg_catalog, pg_temp
as $wrap$
  select app.rollback_employee_import_job(p_job_id, p_reason, p_actor_auth_user_id, p_actor_label);
$wrap$;

comment on function public.rollback_employee_import_job(p_job_id uuid, p_reason text, p_actor_auth_user_id uuid, p_actor_label text) is
  'RGL-394 Option-2 wrapper: app is not exposed to PostgREST; this is a thin security-definer pass-through to app.rollback_employee_import_job with an identical grant set, never a reimplementation. See docs/build-log/release-go-live/RGL-394.md.';

-- 20260826010000_harden_public_api_data_wrappers_tierc_fixes.sql's own amended
-- convention (Finding 2 there): Supabase's own platform-level default privilege
-- grants EXECUTE on every new public-schema function to anon/authenticated/service_role
-- automatically at CREATE time -- `revoke ... from public` alone (the PUBLIC
-- pseudo-role) never touches that. Must revoke from the named roles explicitly.
revoke execute on function public.rollback_employee_import_job(p_job_id uuid, p_reason text, p_actor_auth_user_id uuid, p_actor_label text) from anon, authenticated, service_role, public;
grant execute on function public.rollback_employee_import_job(p_job_id uuid, p_reason text, p_actor_auth_user_id uuid, p_actor_label text) to authenticated, service_role;
