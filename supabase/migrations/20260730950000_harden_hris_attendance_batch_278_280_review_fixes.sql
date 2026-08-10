-- Tier C batch review-round fix pass, CG-S12-HRT-006 (Prompt 278, Attendance),
-- part of the combined 278-280 batch close. AGENTS.md "never edit an applied
-- migration; add a new migration" -- 20260730900000 is already applied and
-- committed, so every fix below is additive (CREATE FUNCTION for the one
-- genuinely new helper, CREATE OR REPLACE FUNCTION for existing functions
-- with an identical signature/return shape, DROP POLICY + CREATE POLICY for
-- RLS) exactly as 20260730920000/20260730940000 already established for this
-- same capability's own prior binding migrations.
--
-- Fixes two CONFIRMED, live-reproduced findings from the batch's Tier C
-- review (security/RLS lens, correctness lens), independently re-derived
-- against a fresh disposable Postgres 16 database before this migration was
-- written, per BUILD_EXECUTION_PROTOCOL.md section 5.3:
--
-- 1. HIGH (self-scoping-raw-table-overexposure): app.attendance_sessions and
--    app.attendance_events (plus, found during this fix pass's own mandatory
--    section 5.4 propagation sweep across the WHOLE 278-280 batch,
--    app.attendance_exceptions and app.attendance_correction_requests --
--    the identical shape, same tables' own column-restricted grants still
--    disclose real per-employee behavioral data) had a tenant-membership-only
--    RLS SELECT policy -- correct RPC-layer self/manager/HRS:View scoping
--    (app.list_attendance_sessions et al) was entirely bypassable via a raw
--    `select ... from app.attendance_sessions where tenant_id = <tenant>`,
--    live-reproduced: a tenant member holding a published role with ZERO
--    permissions and no linked app.employees row saw every employee's real
--    clock-in/out timestamps and payroll_input_status. Fixed by adding a new
--    reusable RLS helper, app.can_view_hris_person_scoped_row, that encodes
--    the SAME self-or-direct-manager-or-HRS:View authorization the RPC layer
--    already computes, and ANDing it into each of the four tables' own
--    SELECT policy -- the raw table now enforces the identical scope the RPC
--    layer always claimed, closing the bypass at its root (the RLS layer),
--    not merely patching the one reported table.
--
-- 2. MEDIUM (correctness, recurring ambiguous-bare-column class this
--    repository's own taxonomy repeatedly tracks): app.get_attendance_
--    session_detail's own `where id = p_session_id` and three list RPCs'
--    own p_after_id cursor-lookup `where id = p_after_id` collide with each
--    function's own RETURNS TABLE output column also named `id`, raising a
--    hard `column reference "id" is ambiguous` for every caller (fail-closed,
--    no data disclosed, but a genuine reliability defect -- confirmed zero
--    db-test coverage exercised get_attendance_session_detail at all, and the
--    three list RPCs' own db-test coverage never supplied a non-null cursor).
--    Fixed by aliasing the source table in each offending SELECT, mirroring
--    the alias-qualified style every OTHER query in this same migration
--    already uses (e.g. `s.id`, `x.id`, `cr.id`) -- this was the one
--    inconsistent bare-reference spot in an otherwise-consistently-aliased
--    file.

-- ===========================================================================
-- Fix 1: self/manager/HRS:View RLS scoping (finding "self-scoping-raw-table-
-- overexposure", HIGH).
-- ===========================================================================

-- Mirrors the exact self-or-direct-manager-or-HRS:View authorization already
-- computed independently by app.list_attendance_sessions, app.list_schedule_
-- assignments (HRT-279), and app.list_leave_requests (HRT-280) -- moved into
-- one reusable, STABLE, SECURITY DEFINER RLS predicate so a raw SELECT on any
-- per-employee HRIS instance table enforces the SAME scope the RPC layer
-- always claimed to enforce, rather than trusting every future table's own
-- bespoke RPC to be the only path. SECURITY DEFINER (same convention as
-- app.has_active_tenant_membership/app.actor_holds_customer_user_layer,
-- 20260716105512/20260730311000) so its own internal reads of app.employees/
-- app.users/app.role_assignments are never subject to the RLS policy this
-- function is itself evaluated inside of -- avoids any recursive-RLS
-- evaluation hazard.
create function app.can_view_hris_person_scoped_row(p_tenant_id uuid, p_employee_id uuid, p_auth_user_id uuid default auth.uid())
returns boolean
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_self app.employees;
begin
  if p_tenant_id is null or p_employee_id is null then
    return false;
  end if;
  if not app.has_active_tenant_membership(p_tenant_id, p_auth_user_id) then
    return false;
  end if;
  -- evaluate_permission's own supreme_admin_exception branch (20260716104519)
  -- already returns allowed=true for any resource_module_code/action, so a
  -- Supreme Admin is covered here with no separate branch needed.
  if (app.evaluate_permission(p_auth_user_id, p_tenant_id, 'HRS', 'View')).allowed then
    return true;
  end if;
  v_self := app.get_self_employee(p_tenant_id, p_auth_user_id);
  if v_self.master_record_id is null then
    return false;
  end if;
  if v_self.master_record_id = p_employee_id then
    return true;
  end if;
  return exists (
    select 1 from app.employees e
    where e.master_record_id = p_employee_id and e.tenant_id = p_tenant_id and e.manager_employee_id = v_self.master_record_id
  );
end;
$$;

comment on function app.can_view_hris_person_scoped_row is
  'Batch 278-280 Tier C fix (security/RLS lens, HIGH, live-reproduced): the shared self-or-direct-manager-or-HRS:View RLS predicate for every per-employee HRIS instance table (attendance sessions/events/exceptions/correction requests, schedule assignments/swap requests, leave/permit/business-trip requests and their balance ledger). Mirrors the RPC-layer scoping app.list_attendance_sessions/app.list_schedule_assignments/app.list_leave_requests each independently compute -- the point of adding it at RLS is that a raw SELECT now enforces the identical scope, not merely whichever RPC a given caller happened to use.';

-- Every prior migration's own established convention (e.g. 20260730900000,
-- 20260730930000): a brand-new function created by this same migration-
-- applying role otherwise retains an implicit PUBLIC EXECUTE grant the
-- moment any explicit GRANT statement first materializes its ACL (the
-- schema-wide `alter default privileges` set up in 20260717095000 does not
-- by itself prevent this within a single migration's own newly-created
-- functions) -- this blanket revoke is the actual operative mechanism, not
-- merely defense-in-depth, exactly as every other migration in this
-- repository already relies on.
revoke execute on all functions in schema app from public;

grant execute on function app.can_view_hris_person_scoped_row(uuid, uuid, uuid) to authenticated, service_role;

drop policy if exists attendance_sessions_select_scoped on app.attendance_sessions;
create policy attendance_sessions_select_scoped on app.attendance_sessions
  for select to authenticated
  using (
    app.is_supreme_admin()
    or (
      app.has_active_tenant_membership(tenant_id)
      and not app.actor_holds_customer_user_layer(tenant_id)
      and app.can_view_hris_person_scoped_row(tenant_id, employee_id)
    )
  );

drop policy if exists attendance_events_select_scoped on app.attendance_events;
create policy attendance_events_select_scoped on app.attendance_events
  for select to authenticated
  using (
    app.is_supreme_admin()
    or (
      app.has_active_tenant_membership(tenant_id)
      and not app.actor_holds_customer_user_layer(tenant_id)
      and app.can_view_hris_person_scoped_row(tenant_id, employee_id)
    )
  );

drop policy if exists attendance_exceptions_select_scoped on app.attendance_exceptions;
create policy attendance_exceptions_select_scoped on app.attendance_exceptions
  for select to authenticated
  using (
    app.is_supreme_admin()
    or (
      app.has_active_tenant_membership(tenant_id)
      and not app.actor_holds_customer_user_layer(tenant_id)
      and app.can_view_hris_person_scoped_row(tenant_id, employee_id)
    )
  );

drop policy if exists attendance_correction_requests_select_scoped on app.attendance_correction_requests;
create policy attendance_correction_requests_select_scoped on app.attendance_correction_requests
  for select to authenticated
  using (
    app.is_supreme_admin()
    or (
      app.has_active_tenant_membership(tenant_id)
      and not app.actor_holds_customer_user_layer(tenant_id)
      and app.can_view_hris_person_scoped_row(tenant_id, employee_id)
    )
  );

-- ===========================================================================
-- Fix 2: ambiguous-bare-`id`-column fix (correctness, MEDIUM).
-- ===========================================================================

create or replace function app.get_attendance_session_detail(p_session_id uuid, p_actor_auth_user_id uuid)
returns table (
  id uuid, employee_id uuid, work_date date, status text, timezone text, effective_clock_in_at timestamptz, effective_clock_out_at timestamptz,
  raw_clock_in_at timestamptz, raw_clock_out_at timestamptz, payroll_input_status text, record_version integer
)
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_session app.attendance_sessions;
  v_self app.employees;
  v_has_view boolean;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  select * into v_session from app.attendance_sessions s where s.id = p_session_id;
  if not found or not app.has_active_tenant_membership(v_session.tenant_id, p_actor_auth_user_id) then
    return;
  end if;

  v_self := app.get_self_employee(v_session.tenant_id, p_actor_auth_user_id);
  v_has_view := (app.evaluate_permission(p_actor_auth_user_id, v_session.tenant_id, 'HRS', 'View')).allowed;

  if not (
    v_has_view
    or (v_self.master_record_id is not null and v_self.master_record_id = v_session.employee_id)
    or exists (select 1 from app.employees e where e.master_record_id = v_session.employee_id and e.manager_employee_id = v_self.master_record_id)
  ) then
    return;
  end if;

  return query
  select s.id, s.employee_id, s.work_date, s.status, s.timezone, s.effective_clock_in_at, s.effective_clock_out_at,
         s.raw_clock_in_at, s.raw_clock_out_at, s.payroll_input_status, s.record_version
  from app.attendance_sessions s where s.id = p_session_id;
end;
$$;

comment on function app.get_attendance_session_detail is
  'Batch 278-280 Tier C fix (correctness lens, MEDIUM, live-reproduced): the original `select * into v_session from app.attendance_sessions where id = p_session_id` was ambiguous against this function''s own RETURNS TABLE output column also named `id` -- every caller got a hard ''column reference "id" is ambiguous'' error, unconditionally. Fixed by aliasing the source table (`s`), matching the alias-qualified style every other query in this file already uses.';

create or replace function app.list_attendance_sessions(
  p_tenant_id uuid, p_actor_auth_user_id uuid, p_from_date date, p_to_date date, p_employee_id uuid, p_status text,
  p_limit integer, p_after_id uuid
)
returns table (
  id uuid, employee_id uuid, employee_number text, employee_full_name text, work_date date, status text,
  effective_clock_in_at timestamptz, effective_clock_out_at timestamptz, payroll_input_status text,
  open_exception_count integer, record_version integer
)
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_self app.employees;
  v_has_view boolean;
  v_after app.attendance_sessions;
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
    select * into v_after from app.attendance_sessions a where a.id = p_after_id;
  end if;

  return query
  select s.id, s.employee_id, m.code, e.full_name, s.work_date, s.status, s.effective_clock_in_at, s.effective_clock_out_at,
         s.payroll_input_status,
         (select count(*)::integer from app.attendance_exceptions x where x.session_id = s.id and x.status in ('open', 'acknowledged')),
         s.record_version
  from app.attendance_sessions s
  join app.employees e on e.master_record_id = s.employee_id
  join app.master_records m on m.id = e.master_record_id
  where s.tenant_id = p_tenant_id
    and (p_from_date is null or s.work_date >= p_from_date)
    and (p_to_date is null or s.work_date <= p_to_date)
    and (p_status is null or s.status = p_status)
    and (
      (p_employee_id is not null and s.employee_id = p_employee_id)
      or (p_employee_id is null and v_has_view)
      or (p_employee_id is null and not v_has_view and (s.employee_id = v_self.master_record_id or e.manager_employee_id = v_self.master_record_id))
    )
    and (v_after.id is null or (s.work_date, s.id) < (v_after.work_date, v_after.id))
  order by s.work_date desc, s.id desc
  limit least(coalesce(p_limit, 50), 200);
end;
$$;

comment on function app.list_attendance_sessions is
  'HRT-278 (section 26): HRS:View holders see the full tenant-scoped list; anyone else (no HRS:View) transparently gets a manager/self scope (their own session rows plus their own direct reports'' rows only) -- the concrete "manager effective-team review where configured" + "prevent cross-team views" mechanism, unified into one RPC rather than a separate team-only endpoint. Batch 278-280 Tier C fix (correctness lens, MEDIUM): the p_after_id cursor lookup''s own bare `where id = p_after_id` was ambiguous against this function''s RETURNS TABLE `id` output column -- every caller supplying a non-null cursor got a hard error; fixed by aliasing the source table (`a`).';

create or replace function app.list_attendance_exceptions(
  p_tenant_id uuid, p_actor_auth_user_id uuid, p_status text, p_limit integer, p_after_id uuid
)
returns table (
  id uuid, employee_id uuid, employee_number text, session_id uuid, work_date date, exception_type text, severity text,
  status text, detail jsonb, detected_at timestamptz, record_version integer
)
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_after app.attendance_exceptions;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'HRS', 'View');
  if not v_decision.allowed then
    return;
  end if;

  if p_after_id is not null then
    select * into v_after from app.attendance_exceptions a where a.id = p_after_id;
  end if;

  return query
  select x.id, x.employee_id, m.code, x.session_id, s.work_date, x.exception_type, x.severity, x.status, x.detail, x.detected_at, x.record_version
  from app.attendance_exceptions x
  join app.attendance_sessions s on s.id = x.session_id
  join app.employees e on e.master_record_id = x.employee_id
  join app.master_records m on m.id = e.master_record_id
  where x.tenant_id = p_tenant_id
    and (p_status is null or x.status = p_status)
    and (v_after.id is null or (x.detected_at, x.id) < (v_after.detected_at, v_after.id))
  order by x.detected_at desc, x.id desc
  limit least(coalesce(p_limit, 50), 200);
end;
$$;

comment on function app.list_attendance_exceptions is
  'Batch 278-280 Tier C fix (correctness lens, MEDIUM, live-reproduced): the p_after_id cursor lookup''s own bare `where id = p_after_id` was ambiguous against this function''s RETURNS TABLE `id` output column -- every caller supplying a non-null cursor got a hard error; fixed by aliasing the source table (`a`).';

create or replace function app.list_attendance_correction_requests(
  p_tenant_id uuid, p_actor_auth_user_id uuid, p_status text, p_limit integer, p_after_id uuid
)
returns table (
  id uuid, employee_id uuid, employee_number text, session_id uuid, work_date date, request_type text, status text,
  created_at timestamptz, record_version integer, has_evidence boolean
)
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_after app.attendance_correction_requests;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'HRS', 'View');
  if not v_decision.allowed then
    return;
  end if;

  if p_after_id is not null then
    select * into v_after from app.attendance_correction_requests a where a.id = p_after_id;
  end if;

  return query
  select cr.id, cr.employee_id, m.code, cr.session_id, s.work_date, cr.request_type, cr.status, cr.created_at, cr.record_version,
         (cr.evidence_file_id is not null)
  from app.attendance_correction_requests cr
  join app.attendance_sessions s on s.id = cr.session_id
  join app.employees e on e.master_record_id = cr.employee_id
  join app.master_records m on m.id = e.master_record_id
  where cr.tenant_id = p_tenant_id
    and (p_status is null or cr.status = p_status)
    and (v_after.id is null or (cr.created_at, cr.id) < (v_after.created_at, v_after.id))
  order by cr.created_at desc, cr.id desc
  limit least(coalesce(p_limit, 50), 200);
end;
$$;

comment on function app.list_attendance_correction_requests is
  'Batch 278-280 Tier C fix (correctness lens, MEDIUM, live-reproduced): the p_after_id cursor lookup''s own bare `where id = p_after_id` was ambiguous against this function''s RETURNS TABLE `id` output column -- every caller supplying a non-null cursor got a hard error; fixed by aliasing the source table (`a`).';
