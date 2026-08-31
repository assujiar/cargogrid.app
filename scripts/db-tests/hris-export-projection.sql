-- ISS-2026-075. Pins the contract between the four HRIS export RPCs and the TypeScript
-- that now reads them (`server/contracts/hris-export/hris-export.ts`,
-- `server/queries/hris-export.ts`).
--
-- WHY A DEDICATED FILE, AND WHY IT ASSERTS SHAPES RATHER THAN ROWS
--
--   These four RPCs were already live-tested at the SQL layer by their own capability
--   db-tests -- `ISS-2026-075` says so explicitly, and re-running those assertions here
--   would prove nothing new. What was NEVER tested is the thing that just started
--   existing: a TypeScript parser reading specific column NAMES and TYPES out of them.
--
--   That join is exactly where `ISS-2026-315` was found and where it hurt: both halves
--   were internally consistent and only the contract between them was wrong, so neither
--   half's own tests could see it. A column renamed or retyped in any of these four
--   projections would leave every existing db-test green and break four export buttons
--   with a Zod error the user reads as "something went wrong".
--
--   One of these four already carries the inconsistency this file exists to freeze:
--   `app.export_leave_requests` names its first two columns `employee_code`/
--   `employee_name`, where the other three say `employee_number`/`employee_full_name`.
--   The TypeScript absorbs that difference in one place. This test is what stops the
--   absorption from silently becoming wrong.
--
--   `public.*` shapes are pinned alongside `app.*`, not instead of them: PostgREST is
--   what the application actually calls, so the wrapper's own independently-declared
--   `returns TABLE(...)` is the shape the parsers really meet (the lesson
--   `ISS-2026-124`'s own fix recorded when a widened `app.*` projection would have
--   mismatched its wrapper and broken every call).
--
-- No fixtures, no tenant, no UUID range claimed -- this file reads the catalogue only.

\set ON_ERROR_STOP on

\echo '>> ISS-2026-075: all four HRIS export RPCs, and their public.* wrappers, project exactly the columns the TypeScript contracts parse'
do $$
declare
  v_expect record;
  v_actual text;
begin
  for v_expect in
    select * from (values
      ('export_attendance_sessions',
       'TABLE(employee_number text, employee_full_name text, work_date date, status text, effective_clock_in_at timestamp with time zone, effective_clock_out_at timestamp with time zone, payroll_input_status text, exception_types text)'),
      ('export_schedule_assignments',
       'TABLE(employee_number text, employee_full_name text, work_date date, shift_template_name text, status text)'),
      -- The odd one out, frozen deliberately: employee_code/employee_name, not
      -- employee_number/employee_full_name. server/contracts/hris-export normalises it.
      ('export_leave_requests',
       'TABLE(employee_code text, employee_name text, leave_type_code text, category text, date_from date, date_to date, total_units numeric, status text)'),
      ('export_timesheet_entries',
       'TABLE(employee_number text, employee_full_name text, work_date date, job_number text, shipment_number text, entry_minutes integer, eligible_minutes integer, approved_minutes integer, status text)')
    ) as t(fn, result_shape)
  loop
    select pg_get_function_result(p.oid) into v_actual
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'app' and p.proname = v_expect.fn;

    if v_actual is null then
      raise exception 'assertion failed: app.% does not exist', v_expect.fn;
    end if;
    if v_actual <> v_expect.result_shape then
      raise exception 'assertion failed: app.%''s projection changed. The TypeScript parser in server/contracts/hris-export/hris-export.ts reads these column names -- update BOTH, or the export silently returns a Zod error to the user. expected % / actual %',
        v_expect.fn, v_expect.result_shape, v_actual;
    end if;

    select pg_get_function_result(p.oid) into v_actual
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = v_expect.fn;

    if v_actual is null then
      raise exception 'assertion failed: public.% does not exist -- PostgREST is what the application actually calls', v_expect.fn;
    end if;
    if v_actual <> v_expect.result_shape then
      raise exception 'assertion failed: public.% has drifted from its app.* original: expected % / actual %', v_expect.fn, v_expect.result_shape, v_actual;
    end if;
  end loop;
end $$;

\echo '>> ISS-2026-075: each export RPC still gates on HRS:Export, and still answers an unauthorised caller with an empty result rather than an error -- the exact behaviour the TypeScript wrapper compensates for'
do $$
declare
  v_fn text;
  v_src text;
begin
  foreach v_fn in array array['export_attendance_sessions', 'export_schedule_assignments', 'export_leave_requests', 'export_timesheet_entries'] loop
    select p.prosrc into v_src from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'app' and p.proname = v_fn;

    if v_src not like '%''HRS'', ''Export''%' then
      raise exception 'assertion failed: app.% no longer evaluates HRS:Export', v_fn;
    end if;

    -- This assertion documents a real property rather than endorsing it. A bare `return;`
    -- on denial means an unauthorised caller gets an empty result set, indistinguishable
    -- from an empty date range -- which is why server/queries/hris-export.ts checks
    -- HRS:Export itself, BEFORE calling, and throws instead. If this ever becomes a raise,
    -- that wrapper check becomes redundant rather than wrong: relax this assertion then,
    -- do not delete the wrapper's own check without re-proving the new behaviour.
    if v_src not like '%if not v_decision.allowed then%return;%' then
      raise exception 'assertion failed: app.%''s denial branch changed shape. server/queries/hris-export.ts compensates for a SILENT empty result; re-check that compensation before accepting this', v_fn;
    end if;

    if v_src not like '%366%' then
      raise exception 'assertion failed: app.% no longer caps its date range at 366 days, which server/queries/hris-export.ts mirrors client-side', v_fn;
    end if;
  end loop;
end $$;

\echo '>> ISS-2026-075: grants -- anon holds EXECUTE on none of the eight functions; authenticated and service_role hold it on all eight'
do $$
declare
  v_fn text;
  v_qualified text;
  v_schema text;
  v_has_priv boolean;
begin
  foreach v_schema in array array['app', 'public'] loop
    foreach v_fn in array array['export_attendance_sessions', 'export_schedule_assignments', 'export_leave_requests', 'export_timesheet_entries'] loop
      v_qualified := v_schema || '.' || v_fn || '(uuid, uuid, date, date)';

      select has_function_privilege('anon', v_qualified, 'EXECUTE') into v_has_priv;
      if v_has_priv then
        raise exception 'assertion failed: anon must NOT hold EXECUTE on %', v_qualified;
      end if;
      select has_function_privilege('authenticated', v_qualified, 'EXECUTE') into v_has_priv;
      if not v_has_priv then
        raise exception 'assertion failed: authenticated SHOULD hold EXECUTE on % -- the HRIS export UI calls it as the signed-in user', v_qualified;
      end if;
      select has_function_privilege('service_role', v_qualified, 'EXECUTE') into v_has_priv;
      if not v_has_priv then
        raise exception 'assertion failed: service_role SHOULD hold EXECUTE on %', v_qualified;
      end if;
    end loop;
  end loop;
end $$;

\echo '>> ISS-2026-075: every export self-captures an audit event naming its own action and date range -- an export of personal HR data that leaves no trace is the one failure mode worth pinning structurally'
do $$
declare
  v_fn text;
  v_src text;
begin
  foreach v_fn in array array['export_attendance_sessions', 'export_schedule_assignments', 'export_leave_requests', 'export_timesheet_entries'] loop
    select p.prosrc into v_src from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'app' and p.proname = v_fn;
    if v_src not like '%capture_audit_event%' || v_fn || '%' then
      raise exception 'assertion failed: app.% no longer captures an audit event naming itself', v_fn;
    end if;
    if v_src not like '%from_date%to_date%' then
      raise exception 'assertion failed: app.%''s audit event no longer records the exported date range', v_fn;
    end if;
  end loop;
end $$;

\echo '>> ISS-2026-075: the leave export still omits reason/destination/evidence, whatever the caller holds -- a minimisation rule that a future column addition must not quietly undo'
do $$
declare
  v_shape text;
  v_forbidden text;
begin
  select pg_get_function_result(p.oid) into v_shape
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'app' and p.proname = 'export_leave_requests';

  foreach v_forbidden in array array['reason', 'destination', 'evidence_file_id', 'notes'] loop
    if v_shape like '%' || v_forbidden || '%' then
      raise exception 'assertion failed: app.export_leave_requests now projects "%", which HRT-280 section 16 deliberately excludes from every export regardless of the caller''s own personal-data standing', v_forbidden;
    end if;
  end loop;
end $$;
