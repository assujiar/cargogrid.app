-- Closes `ISS-2026-315` (registered by this migration), and unblocks `ISS-2026-076`.
--
-- THE DEFECT, LIVE-VERIFIED RATHER THAN REASONED ABOUT
--
--   `app.list_timesheet_entries` (`20260730990000:829`) declares a RETURNS TABLE with no
--   `unpaid_break_minutes` column. Its TypeScript reader, `parseTimesheetEntryRow`
--   (`server/contracts/overtime-timesheet/overtime-timesheet.ts:230`), requires
--   `unpaidBreakMinutes` as a **non-nullable integer**. So the admin workspace's own listing
--   throws a `ZodError` -- not the caught `OvertimeTimesheetQueryError` -- the moment the RPC
--   returns a single row.
--
--   Reproduced directly by feeding `parseTimesheetEntryAdminRow` exactly the column set the RPC
--   declares: `Invalid input: expected number, received undefined` at path `unpaidBreakMinutes`.
--
--   This has never been caught because the tenant count is still zero, and because the unit test
--   at `server/queries/overtime-timesheet.test.ts:71` builds its fake row from the *schema*
--   rather than from the RPC's actual output columns -- so the fixture carries an
--   `unpaid_break_minutes` the real function has never returned. A fake more generous than the
--   thing it stands in for proves nothing about the thing.
--
--   `app.list_my_timesheet_entries` (the employee's own listing) does return it, which is why
--   only the HR/manager surface is affected -- and why the mismatch was easy to miss.
--
-- WHY `notes` IS ADDED IN THE SAME MIGRATION, RATHER THAN LATER
--
--   `ISS-2026-076` wires `app.update_timesheet_entry_draft` to a real HR correction form for the
--   first time. That RPC takes `p_notes` and writes it unconditionally. Neither listing returns
--   `notes` today, so a correction form could only ever submit a blank field -- silently
--   **erasing** a note the person editing was never shown. Fixing the minutes bug while leaving
--   that trap in place would be fixing the half that was already visible.
--
-- DROP + CREATE, not CREATE OR REPLACE: PostgreSQL cannot change a function's RETURNS TABLE
-- shape in place ("cannot change return type of existing function"). The `public.*` wrappers
-- depend on these, so they are dropped first and recreated with the widened row type and the
-- same grant set (`ISS-2026-309` revoke shape).

drop function public.list_timesheet_entries(uuid, uuid, uuid, text, date, date, integer, uuid);
drop function app.list_timesheet_entries(uuid, uuid, uuid, text, date, date, integer, uuid);

create function app.list_timesheet_entries(
  p_tenant_id uuid, p_actor_auth_user_id uuid, p_employee_id uuid, p_status text, p_from_date date, p_to_date date, p_limit integer, p_after_id uuid
)
returns table (
  id uuid, employee_id uuid, employee_number text, employee_full_name text, work_date date, entry_minutes integer,
  unpaid_break_minutes integer, job_order_id uuid, job_number text, shipment_order_id uuid, shipment_number text, notes text,
  status text, reconciliation_status text, eligible_minutes integer, approved_minutes integer, payroll_input_status text,
  record_version integer
)
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_self app.employees;
  v_has_view boolean;
  v_after app.timesheet_entries;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  if not app.has_active_tenant_membership(p_tenant_id, p_actor_auth_user_id) then
    return;
  end if;

  v_self := app.get_self_employee(p_tenant_id, p_actor_auth_user_id);
  v_has_view := (app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'HRS', 'View')).allowed;

  if p_employee_id is not null then
    if not (
      v_has_view
      or (v_self.master_record_id is not null and v_self.master_record_id = p_employee_id)
      or exists (select 1 from app.employees e where e.master_record_id = p_employee_id and e.manager_employee_id = v_self.master_record_id)
    ) then
      return;
    end if;
  elsif not v_has_view and v_self.master_record_id is null then
    return;
  end if;

  if p_after_id is not null then
    select te2.* into v_after from app.timesheet_entries te2 where te2.id = p_after_id;
  end if;

  -- Body unchanged from 20260730990000 except for the two added projections. The manager-scope
  -- predicate, keyset pagination and 200-row clamp are reproduced byte-for-byte on purpose: this
  -- migration is fixing an output-column omission, not revisiting who may read what.
  return query
  select te.id, te.employee_id, m.code, e.full_name, te.work_date, te.entry_minutes, te.unpaid_break_minutes,
         te.job_order_id, jo.job_number, te.shipment_order_id, so.shipment_number, te.notes,
         te.status, te.reconciliation_status, te.eligible_minutes, te.approved_minutes, te.payroll_input_status, te.record_version
  from app.timesheet_entries te
  join app.employees e on e.master_record_id = te.employee_id
  join app.master_records m on m.id = e.master_record_id
  left join app.job_orders jo on jo.id = te.job_order_id
  left join app.shipment_orders so on so.id = te.shipment_order_id
  where te.tenant_id = p_tenant_id
    and (p_status is null or te.status = p_status)
    and (p_from_date is null or te.work_date >= p_from_date)
    and (p_to_date is null or te.work_date <= p_to_date)
    and (
      (p_employee_id is not null and te.employee_id = p_employee_id)
      or (p_employee_id is null and v_has_view)
      or (p_employee_id is null and not v_has_view and (te.employee_id = v_self.master_record_id or e.manager_employee_id = v_self.master_record_id))
    )
    and (v_after.id is null or (te.work_date, te.id) < (v_after.work_date, v_after.id))
  order by te.work_date desc, te.id desc
  limit least(coalesce(p_limit, 50), 200);
end;
$$;

comment on function app.list_timesheet_entries is
  'HRT-281: the HR/manager timesheet-entry listing -- HRS:View sees the whole tenant, a manager without it transparently sees self + direct reports, reusing the roster''s own manager-scope resolution. ISS-2026-315 (20260831160000): now returns unpaid_break_minutes, which its own TypeScript reader has always required as non-nullable -- the omission made the admin workspace throw a ZodError on the first real row, and went unnoticed only because the unit-test fixture was built from the schema rather than from this function''s actual output columns. Also returns notes, so ISS-2026-076''s HR draft-correction form can show a note before overwriting it instead of silently erasing one it never displayed.';

revoke execute on function app.list_timesheet_entries(uuid, uuid, uuid, text, date, date, integer, uuid) from public;
grant execute on function app.list_timesheet_entries(uuid, uuid, uuid, text, date, date, integer, uuid) to authenticated, service_role;

create function public.list_timesheet_entries(p_tenant_id uuid, p_actor_auth_user_id uuid, p_employee_id uuid, p_status text, p_from_date date, p_to_date date, p_limit integer, p_after_id uuid)
returns table (
  id uuid, employee_id uuid, employee_number text, employee_full_name text, work_date date, entry_minutes integer,
  unpaid_break_minutes integer, job_order_id uuid, job_number text, shipment_order_id uuid, shipment_number text, notes text,
  status text, reconciliation_status text, eligible_minutes integer, approved_minutes integer, payroll_input_status text,
  record_version integer
)
language sql
volatile
security definer
set search_path = pg_catalog, pg_temp
as $wrap$
  select * from app.list_timesheet_entries(p_tenant_id, p_actor_auth_user_id, p_employee_id, p_status, p_from_date, p_to_date, p_limit, p_after_id);
$wrap$;

comment on function public.list_timesheet_entries(uuid, uuid, uuid, text, date, date, integer, uuid) is
  'RGL-394 Option-2 wrapper: a thin security-definer pass-through to app.list_timesheet_entries, never a reimplementation.';

-- `from anon, ...`, not `from public` alone: Supabase's ALTER DEFAULT PRIVILEGES grants anon
-- EXECUTE explicitly at CREATE time, and an explicit grant survives a PUBLIC revoke (ISS-2026-309).
revoke execute on function public.list_timesheet_entries(uuid, uuid, uuid, text, date, date, integer, uuid) from anon, authenticated, service_role, public;
grant execute on function public.list_timesheet_entries(uuid, uuid, uuid, text, date, date, integer, uuid) to authenticated, service_role;

-- The employee's own listing keeps unpaid_break_minutes (it always returned it) and gains notes
-- for the same reason: app.update_timesheet_entry_draft is owner-or-HRS:Edit, so an employee
-- correcting their OWN draft would hit the identical erasure trap. Fixing one side and not the
-- other would leave the two listings asymmetric for no reason a reader could reconstruct.
drop function public.list_my_timesheet_entries(uuid, uuid, date, date, integer, uuid);
drop function app.list_my_timesheet_entries(uuid, uuid, date, date, integer, uuid);

create function app.list_my_timesheet_entries(p_tenant_id uuid, p_actor_auth_user_id uuid, p_from_date date, p_to_date date, p_limit integer, p_after_id uuid)
returns table (
  id uuid, work_date date, entry_minutes integer, unpaid_break_minutes integer, job_order_id uuid, job_number text,
  shipment_order_id uuid, shipment_number text, notes text, status text, reconciliation_status text, eligible_minutes integer,
  approved_minutes integer, payroll_input_status text, record_version integer
)
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_self app.employees;
  v_after app.timesheet_entries;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  if not app.has_active_tenant_membership(p_tenant_id, p_actor_auth_user_id) then
    return;
  end if;
  v_self := app.get_self_employee(p_tenant_id, p_actor_auth_user_id);
  if v_self.master_record_id is null then
    return;
  end if;

  if p_after_id is not null then
    select * into v_after from app.timesheet_entries where id = p_after_id;
  end if;

  return query
  select te.id, te.work_date, te.entry_minutes, te.unpaid_break_minutes, te.job_order_id, jo.job_number,
         te.shipment_order_id, so.shipment_number, te.notes,
         te.status, te.reconciliation_status, te.eligible_minutes, te.approved_minutes, te.payroll_input_status, te.record_version
  from app.timesheet_entries te
  left join app.job_orders jo on jo.id = te.job_order_id
  left join app.shipment_orders so on so.id = te.shipment_order_id
  where te.tenant_id = p_tenant_id and te.employee_id = v_self.master_record_id
    and (p_from_date is null or te.work_date >= p_from_date)
    and (p_to_date is null or te.work_date <= p_to_date)
    and (v_after.id is null or (te.work_date, te.id) < (v_after.work_date, v_after.id))
  order by te.work_date desc, te.id desc
  limit least(coalesce(p_limit, 50), 200);
end;
$$;

comment on function app.list_my_timesheet_entries is
  'HRT-281: an employee''s own timesheet entries, self-resolved -- carries no employee-id-shaped input to spoof. ISS-2026-315 (20260831160000): gains notes so a draft correction can be shown before it is overwritten; unpaid_break_minutes was already returned here, which is why only the HR/manager listing carried the ISS-2026-315 defect.';

revoke execute on function app.list_my_timesheet_entries(uuid, uuid, date, date, integer, uuid) from public;
grant execute on function app.list_my_timesheet_entries(uuid, uuid, date, date, integer, uuid) to authenticated, service_role;

create function public.list_my_timesheet_entries(p_tenant_id uuid, p_actor_auth_user_id uuid, p_from_date date, p_to_date date, p_limit integer, p_after_id uuid)
returns table (
  id uuid, work_date date, entry_minutes integer, unpaid_break_minutes integer, job_order_id uuid, job_number text,
  shipment_order_id uuid, shipment_number text, notes text, status text, reconciliation_status text, eligible_minutes integer,
  approved_minutes integer, payroll_input_status text, record_version integer
)
language sql
volatile
security definer
set search_path = pg_catalog, pg_temp
as $wrap$
  select * from app.list_my_timesheet_entries(p_tenant_id, p_actor_auth_user_id, p_from_date, p_to_date, p_limit, p_after_id);
$wrap$;

comment on function public.list_my_timesheet_entries(uuid, uuid, date, date, integer, uuid) is
  'RGL-394 Option-2 wrapper: a thin security-definer pass-through to app.list_my_timesheet_entries, never a reimplementation.';

revoke execute on function public.list_my_timesheet_entries(uuid, uuid, date, date, integer, uuid) from anon, authenticated, service_role, public;
grant execute on function public.list_my_timesheet_entries(uuid, uuid, date, date, integer, uuid) to authenticated, service_role;
