-- Self-found regression, caught live by `pnpm run db:test` immediately after
-- 20260902040000_create_position_crosswalk_import_adapter.sql applied. One line in
-- app.validate_position_crosswalk_import_row appends a bare string LITERAL (not a
-- concatenation expression) to a text[] via `||`:
--
--   v_errors := v_errors || ('change_reason: a secondary assignment_type requires an explicit
--   change_reason of secondary_assignment');
--
-- Every OTHER v_errors || (...) call site in this same function concatenates at least two
-- operands first (e.g. 'field: ' || value || ' suffix'), which gives Postgres's parser an
-- unambiguous `text` type for the right-hand side before it ever reaches the `||` against
-- v_errors. This ONE line's right-hand side is a single untyped string literal, and Postgres's
-- operator resolution for `||` against an unknown-type literal prefers the anyarray||anyarray
-- (array_cat) candidate over anyarray||anyelement (array_append) -- so it tries to PARSE the
-- literal AS AN ARRAY LITERAL and fails:
--
--   ERROR: malformed array literal: "change_reason: a secondary assignment_type requires an
--   explicit change_reason of secondary_assignment"
--   DETAIL: Array value must start with "{" or dimension information.
--
-- live-reproduced by this checkpoint's own new db-tests regression block (scripts/db-tests/
-- hris-organization-position-linkage.sql, the row exercising assignment_type=secondary with a
-- mismatched change_reason). Fix: an explicit ::text cast on that one literal, resolving the
-- ambiguity exactly as every neighboring concatenation expression already does implicitly.
-- Every other line is byte-identical to the live definition -- no other behavior changes.

create or replace function app.validate_position_crosswalk_import_row(
  p_staging_row_id uuid,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.import_staging_rows
language plpgsql
as $$
declare
  v_row app.import_staging_rows;
  v_job app.jobs;
  v_payload jsonb;
  v_field text;
  v_value text;
  v_errors text[] := array[]::text[];
  v_text_fields text[] := array['employee_number', 'position_code', 'grade_code', 'manager_employee_number', 'assignment_type', 'change_reason', 'reason_note'];
  v_employee_id uuid;
  v_manager_id uuid;
  v_position_id uuid;
  v_assignment_type text;
  v_change_reason text;
  v_start_date date;
  v_end_date date;
  v_allocation numeric;
begin
  v_row := app.validate_staging_row(p_staging_row_id, p_actor_auth_user_id, p_actor_label);
  if v_row.validation_status <> 'valid' then
    return v_row;
  end if;

  select * into v_job from app.jobs where job_id = v_row.job_id;
  v_payload := v_row.raw_payload;

  foreach v_field in array v_text_fields loop
    v_value := v_payload ->> v_field;
    if v_value is not null and v_value ~ '^[-+=@\t\r]' then
      v_errors := v_errors || (v_field || ': value begins with a disallowed formula/spreadsheet-injection prefix (=, +, -, @, tab, or carriage return)');
    end if;
  end loop;

  select e.master_record_id, e.lifecycle_status into v_employee_id, v_value
  from app.employees e
  join app.master_records m on m.id = e.master_record_id
  where e.tenant_id = v_job.tenant_id and m.code = trim(coalesce(v_payload ->> 'employee_number', ''));
  if v_employee_id is null then
    v_errors := v_errors || ('employee_number: ' || coalesce(v_payload ->> 'employee_number', '(missing)') || ' does not resolve to an employee of this tenant');
  elsif v_value in ('terminated', 'archived') then
    v_errors := v_errors || ('employee_number: ' || (v_payload ->> 'employee_number') || ' is ' || v_value || ' and cannot receive a new position assignment');
  end if;

  select id into v_position_id from app.positions where tenant_id = v_job.tenant_id and code = trim(coalesce(v_payload ->> 'position_code', '')) and status = 'active';
  if v_position_id is null then
    v_errors := v_errors || ('position_code: ' || coalesce(v_payload ->> 'position_code', '(missing)') || ' does not resolve to an active position of this tenant');
  end if;

  if coalesce(v_payload ->> 'grade_code', '') <> '' and not exists (
    select 1 from app.position_grades where tenant_id = v_job.tenant_id and code = trim(v_payload ->> 'grade_code') and status = 'active'
  ) then
    v_errors := v_errors || ('grade_code: ' || (v_payload ->> 'grade_code') || ' does not resolve to an active grade of this tenant');
  end if;

  if coalesce(v_payload ->> 'manager_employee_number', '') <> '' then
    select e.master_record_id into v_manager_id
    from app.employees e
    join app.master_records m on m.id = e.master_record_id
    where e.tenant_id = v_job.tenant_id and m.code = trim(v_payload ->> 'manager_employee_number');
    if v_manager_id is null then
      v_errors := v_errors || ('manager_employee_number: ' || (v_payload ->> 'manager_employee_number') || ' does not resolve to an employee of this tenant');
    elsif v_manager_id = v_employee_id then
      v_errors := v_errors || ('manager_employee_number: an employee may not be their own manager');
    end if;
  end if;

  v_assignment_type := coalesce(nullif(trim(v_payload ->> 'assignment_type'), ''), 'primary');
  if v_assignment_type not in ('primary', 'secondary') then
    v_errors := v_errors || ('assignment_type: ' || v_assignment_type || ' must be primary or secondary');
  end if;

  v_change_reason := coalesce(nullif(trim(v_payload ->> 'change_reason'), ''), 'correction');
  if v_change_reason not in ('hire', 'transfer', 'promotion', 'demotion', 'lateral_move', 'reorganization', 'secondary_assignment', 'correction') then
    v_errors := v_errors || ('change_reason: ' || v_change_reason || ' is not a recognized change reason');
  elsif v_assignment_type = 'secondary' and v_change_reason <> 'secondary_assignment' then
    v_errors := v_errors || 'change_reason: a secondary assignment_type requires an explicit change_reason of secondary_assignment'::text;
  end if;

  if coalesce(v_payload ->> 'effective_start_date', '') <> '' then
    begin
      v_start_date := (trim(v_payload ->> 'effective_start_date'))::date;
    exception when others then
      v_errors := v_errors || ('effective_start_date: ' || (v_payload ->> 'effective_start_date') || ' is not a valid date');
    end;
  end if;

  if coalesce(v_payload ->> 'effective_end_date', '') <> '' then
    begin
      v_end_date := (trim(v_payload ->> 'effective_end_date'))::date;
      if v_start_date is not null and v_end_date < v_start_date then
        v_errors := v_errors || ('effective_end_date: ' || v_end_date || ' is before effective_start_date ' || v_start_date);
      end if;
    exception when others then
      v_errors := v_errors || ('effective_end_date: ' || (v_payload ->> 'effective_end_date') || ' is not a valid date');
    end;
  end if;

  if coalesce(v_payload ->> 'allocation_pct', '') <> '' then
    begin
      v_allocation := (trim(v_payload ->> 'allocation_pct'))::numeric;
      if v_allocation <= 0 or v_allocation > 100 then
        v_errors := v_errors || ('allocation_pct: ' || v_allocation || ' must be greater than 0 and no more than 100');
      end if;
    exception when others then
      v_errors := v_errors || ('allocation_pct: ' || (v_payload ->> 'allocation_pct') || ' is not a valid number');
    end;
  end if;

  if array_length(v_errors, 1) is not null then
    update app.import_staging_rows set validation_status = 'invalid', error = array_to_string(v_errors, '; ')
    where id = p_staging_row_id returning * into v_row;
    update app.jobs set valid_row_count = greatest(valid_row_count - 1, 0), invalid_row_count = invalid_row_count + 1
    where job_id = v_row.job_id;
  end if;

  return v_row;
end;
$$;

comment on function app.validate_position_crosswalk_import_row is
  'ISS-2026-066 item 3: row-level validation for position_crosswalk_import. Re-derives only what can be answered earlier and cheaper than the commit step -- employee_number resolving to a non-terminated/archived employee of this tenant, position_code resolving to an active position, an optional grade_code resolving to an active grade, an optional manager_employee_number resolving to a different employee, assignment_type/change_reason within the CHECK-constrained vocabulary (including the secondary/secondary_assignment pairing rule), and well-formed dates/allocation_pct -- and leaves the authoritative proposal rule (capacity, cycle detection, version match) inside app.propose_employee_position_assignment. Fixed at 20260902042000: the secondary/secondary_assignment mismatch message is now explicitly ::text-cast, avoiding the anyarray||anyarray (array_cat) operator resolution Postgres otherwise prefers for a bare untyped string literal against a text[].';
