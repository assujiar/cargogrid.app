-- CG-AUDIT-2026-09-02 D3b remediation.
--
-- The independent launch-readiness audit (docs/audit/2026-09-02-independent-launch-readiness-audit.md
-- §4 D3b) reproduced live: suspending a user through the governed RPC
-- (app.transition_user_status) does not cut their access. `app.transition_user_status`
-- already strips every active `app.role_assignments` row on suspend (ISS-2026-072), but
-- neither `app.resolve_access_context` (the gate every tenant page calls) nor
-- `app.has_active_tenant_membership` (the RLS predicate underneath 450+ policies) reads
-- `app.users.status` at all -- both key off `app.tenant_user_identities.status = 'active'`
-- alone, which `transition_user_status` never touches on suspend (only on revoke, via
-- `app.revoke_auth_identity`). A suspended user therefore keeps full RLS-gated read access
-- and keeps resolving a real access-context layer, even with zero role assignments left.
--
-- `app.tenant_user_identities` deliberately has no 'suspended' state of its own --
-- `app.enforce_identity_link_transition`'s own comment states this plainly (HRT-295 /
-- ISS-2026-108: "this table has no 'suspended' state, only invited/active/revoked"). Rather
-- than reversing that design (widening the identity-linkage table's own CHECK constraint
-- and transition trigger, a materially larger and riskier change to a foundational security
-- table used far beyond these two functions), this fix layers an additional guard onto
-- exactly the two functions the audit named: a genuinely active identity linkage is no
-- longer sufficient on its own if a corresponding `app.users` row exists AND is
-- `suspended`/`revoked`. Using NOT EXISTS (rather than a JOIN) preserves current behavior
-- exactly for any identity with no corresponding `app.users` row at all (customer_user-layer
-- portal principals, who this table's own HRIS-flavored lifecycle language -- "offboarded",
-- "rehire" -- was never written for) -- only a genuine, existing, suspended/revoked `app.users`
-- row newly excludes access. `app.users_tenant_auth_user_unique (tenant_id, auth_user_id)`
-- backs this lookup with an index, so the added cost is one indexed lookup, not a scan.
--
-- The Supreme Admin and support-grant branches of app.has_active_tenant_membership are
-- deliberately left untouched: both are independent elevated-access mechanisms
-- (principal_memberships/support grants), never gated by a tenant's own app.users row, and
-- must not become collateral damage of an employee-lifecycle fix.
--
-- One deliberate, tested, pre-existing behavior this fix must NOT regress:
-- `20260731230000_couple_hris_employee_lifecycle_to_platform_identity_hrt295.sql` (HRT-295 /
-- ISS-2026-104) fixed terminate/suspend to strip PERMISSION-gated authority (role_
-- assignments) but left `app.tenant_user_identities` untouched for a suspend specifically so
-- five narrow self-service reads keep working while a suspension is under review --
-- `app.get_my_employee_profile`, `app.get_my_assigned_interviews`,
-- `app.get_my_attendance_status`, `app.get_my_employee_position_assignment_history`,
-- `app.get_my_schedule` -- each gated only by `app.has_active_tenant_membership` and each
-- reading only the caller's OWN row(s), never another identity's or the wider tenant's data.
-- `scripts/db-tests/hris-employee-master.sql`'s own existing regression documents this
-- exactly ("suspend deliberately preserves self-service reads... a suspended employee can
-- still see their own profile / open a ticket about the suspension"). Tightening
-- `has_active_tenant_membership` itself, unmodified, would silently break this real,
-- deliberate, already-tested feature -- it is the RLS-policy-facing gate all five of these
-- functions happen to reuse, not a purpose-built self-service check.
--
-- So this migration also adds `app.has_active_identity_link`: the EXACT ORIGINAL body of
-- `has_active_tenant_membership` before this fix (genuinely active tenant_user_identities
-- linkage, or Supreme Admin, or an active support grant -- no app.users.status opinion at
-- all), and repoints all five of those narrow, own-row-only self-service functions at it
-- instead. The distinction this migration draws, going forward: `has_active_tenant_
-- membership` is the broad, RLS-policy-facing gate (does this identity see the tenant's
-- data at large) and now correctly excludes a suspended/revoked app.users row;
-- `has_active_identity_link` is the narrower "is this identity still linked to the tenant at
-- all" check the small, already-reviewed set of self-service RPCs that read only the
-- caller's own row may keep relying on. `hris-employee-master.sql`'s own existing assertion
-- is updated in step to match -- has_active_tenant_membership now correctly reads false for
-- a suspended employee, while app.get_my_employee_profile still returns their own row,
-- exactly as HRT-295 intended.

create or replace function app.has_active_tenant_membership(p_tenant_id uuid, p_auth_user_id uuid default auth.uid())
returns boolean
language sql
stable
security definer
set search_path to 'app', 'pg_temp'
as $function$
  select exists (
    select 1 from app.tenant_user_identities tui
    where tui.tenant_id = p_tenant_id and tui.auth_user_id = p_auth_user_id and tui.status = 'active'
      and not exists (
        select 1 from app.users u
        where u.tenant_id = tui.tenant_id and u.auth_user_id = tui.auth_user_id and u.status in ('suspended', 'revoked')
      )
  )
  or app.is_supreme_admin(p_auth_user_id)
  or app.has_active_support_grant(p_tenant_id, p_auth_user_id);
$function$;

comment on function app.has_active_tenant_membership(uuid, uuid) is
  'CG-AUDIT-2026-09-02 D3b: a genuinely active tenant_user_identities linkage is no longer sufficient on its own -- a corresponding app.users row that is suspended or revoked now excludes access too, closing the gap where suspending a user (which already strips role_assignments, ISS-2026-072) left every RLS-gated table and app.resolve_access_context still open. NOT EXISTS, not a JOIN, so an identity with no app.users row (e.g. a customer_user-layer principal) is entirely unaffected.';

create or replace function app.resolve_access_context(p_auth_user_id uuid, p_tenant_id uuid default null::uuid, p_customer_account_ref text default null::text)
returns app.access_context
language plpgsql
stable
as $function$
declare
  v_membership app.principal_memberships;
  v_match_count integer;
begin
  if p_tenant_id is null then
    -- Global request: a live Supreme Admin grant always resolves first and alone --
    -- Supreme Admin never shares an unqualified request with a tenant-scoped layer.
    select * into v_membership
    from app.principal_memberships
    where auth_user_id = p_auth_user_id and layer = 'supreme_admin' and status = 'active';

    if found then
      return row(v_membership.id, v_membership.auth_user_id, v_membership.layer, v_membership.tenant_id, v_membership.customer_account_ref, now())::app.access_context;
    end if;

    select count(*) into v_match_count
    from app.principal_memberships
    where auth_user_id = p_auth_user_id and status = 'active';

    if v_match_count = 0 then
      raise exception 'no_active_membership: identity % holds no active principal membership', p_auth_user_id
        using errcode = 'no_data_found';
    elsif v_match_count > 1 then
      raise exception 'ambiguous_context: identity % holds % active memberships, tenant_id must be specified', p_auth_user_id, v_match_count
        using errcode = 'check_violation';
    end if;

    select * into v_membership
    from app.principal_memberships
    where auth_user_id = p_auth_user_id and status = 'active';

    return row(v_membership.id, v_membership.auth_user_id, v_membership.layer, v_membership.tenant_id, v_membership.customer_account_ref, now())::app.access_context;
  end if;

  -- Tenant-qualified request: the target tenant must itself be active -- an inactive
  -- tenant fails closed regardless of membership state (Prompt 108 §23).
  if not exists (select 1 from app.tenants where id = p_tenant_id and canonical_status = 'active') then
    raise exception 'inactive_tenant: tenant % is not active' , p_tenant_id
      using errcode = 'check_violation';
  end if;

  -- The underlying identity linkage (PLT-107) must itself be active, not merely invited
  -- or already revoked -- authentication proves identity, membership proves layer, and
  -- both must independently be live. CG-AUDIT-2026-09-02 D3b: a genuinely active linkage is
  -- no longer sufficient on its own -- see app.has_active_tenant_membership's own comment
  -- for why a corresponding suspended/revoked app.users row now also fails this closed, via
  -- the identical NOT EXISTS shape (an identity with no app.users row is unaffected).
  if not exists (
    select 1 from app.tenant_user_identities tui
    where tui.auth_user_id = p_auth_user_id and tui.tenant_id = p_tenant_id and tui.status = 'active'
      and not exists (
        select 1 from app.users u
        where u.tenant_id = tui.tenant_id and u.auth_user_id = tui.auth_user_id and u.status in ('suspended', 'revoked')
      )
  ) then
    raise exception 'inactive_identity_link: identity % has no active linkage to tenant %', p_auth_user_id, p_tenant_id
      using errcode = 'no_data_found';
  end if;

  select count(*) into v_match_count
  from app.principal_memberships
  where auth_user_id = p_auth_user_id and tenant_id = p_tenant_id and status = 'active'
    and (p_customer_account_ref is null or customer_account_ref = p_customer_account_ref);

  if v_match_count = 0 then
    raise exception 'no_active_membership_for_tenant: identity % holds no active membership in tenant %', p_auth_user_id, p_tenant_id
      using errcode = 'no_data_found';
  elsif v_match_count > 1 then
    raise exception 'ambiguous_context: identity % holds % active memberships in tenant %, customer_account_ref must be specified', p_auth_user_id, v_match_count, p_tenant_id
      using errcode = 'check_violation';
  end if;

  select * into v_membership
  from app.principal_memberships
  where auth_user_id = p_auth_user_id and tenant_id = p_tenant_id and status = 'active'
    and (p_customer_account_ref is null or customer_account_ref = p_customer_account_ref);

  return row(v_membership.id, v_membership.auth_user_id, v_membership.layer, v_membership.tenant_id, v_membership.customer_account_ref, now())::app.access_context;
end;
$function$;

comment on function app.resolve_access_context(uuid, uuid, text) is
  'PLT-108: resolves the caller''s four-layer access context. Two distinct branches, not one: '
  '(1) p_tenant_id omitted (null) -- a live Supreme Admin grant always resolves first and alone, '
  'never sharing an unqualified request with a tenant-scoped layer; absent that, the caller''s '
  'single active global-scope principal_membership resolves, or no_active_membership/'
  'ambiguous_context raises if zero/multiple exist. '
  '(2) p_tenant_id supplied -- the target tenant must itself be canonical_status=active '
  '(else inactive_tenant), AND the caller must hold its own active app.tenant_user_identities '
  '(PLT-107) row for that exact tenant (else inactive_identity_link) -- this branch has no '
  'Supreme Admin shortcut: a global-only Supreme Admin with no per-tenant identity link fails '
  'closed here exactly like any other unlinked identity would, by design (verified at PLT-137''s '
  'own integration testing, docs/build-log/phase-01/PLT-137.md §5/§6 scenario 3). The one '
  'production caller of the tenant-qualified form is app.has_active_tenant_membership()''s own '
  'RLS-facing callers; lib/portal/supreme-admin-guard.ts (PLT-136) always calls the omitted-'
  'p_tenant_id form instead, so this branch''s fail-closed behavior for Supreme Admin has no '
  'portal-facing impact. '
  'CG-AUDIT-2026-09-02 D3b: the tenant-qualified identity-linkage check (2) now ALSO fails '
  'closed (inactive_identity_link) when a corresponding app.users row exists and is suspended '
  'or revoked, mirroring app.has_active_tenant_membership''s own fix exactly.';

-- The exact original body of app.has_active_tenant_membership, preserved verbatim under a
-- new name for the narrow set of self-service RPCs that must keep working through a
-- temporary suspension -- see this migration's own header for the full rationale.
create function app.has_active_identity_link(p_tenant_id uuid, p_auth_user_id uuid default auth.uid())
returns boolean
language sql
stable
security definer
set search_path to 'app', 'pg_temp'
as $function$
  select exists (
    select 1 from app.tenant_user_identities
    where tenant_id = p_tenant_id and auth_user_id = p_auth_user_id and status = 'active'
  )
  or app.is_supreme_admin(p_auth_user_id)
  or app.has_active_support_grant(p_tenant_id, p_auth_user_id);
$function$;

comment on function app.has_active_identity_link(uuid, uuid) is
  'CG-AUDIT-2026-09-02 D3b: a genuinely active tenant_user_identities linkage, independent of any app.users employment status -- the narrow check a small, already-reviewed set of self-service RPCs (app.get_my_employee_profile and siblings) that read only the calling identity''s own row may keep relying on through a temporary suspension (HRT-295), unlike app.has_active_tenant_membership (the broad, RLS-policy-facing gate) which now correctly excludes a suspended/revoked app.users row. Never grant EXECUTE on this to anon -- it carries no permission check of its own, exactly like has_active_tenant_membership.';

revoke execute on function app.has_active_identity_link(uuid, uuid) from public;
grant execute on function app.has_active_identity_link(uuid, uuid) to authenticated, service_role;

-- Option-2 wrapper, mirroring public.has_active_tenant_membership's own exact shape
-- (including its own impersonation check ahead of the real call, since a caller reaching
-- this via PostgREST supplies p_auth_user_id explicitly rather than defaulting to auth.uid()):
-- app is not exposed to PostgREST; this is a thin security-definer pass-through, never a
-- reimplementation.
create function public.has_active_identity_link(p_tenant_id uuid, p_auth_user_id uuid default auth.uid())
returns boolean
language sql
stable
security definer
set search_path to 'pg_catalog', 'pg_temp'
as $function$
  select app.assert_actor_is_session_identity(p_auth_user_id);
  select app.has_active_identity_link(p_tenant_id, p_auth_user_id);
$function$;

comment on function public.has_active_identity_link(uuid, uuid) is
  'CG-AUDIT-2026-09-02 D3b Option-2 wrapper: app is not exposed to PostgREST; this is a thin security-definer pass-through to app.has_active_identity_link with an identical grant set, never a reimplementation.';

revoke execute on function public.has_active_identity_link(uuid, uuid) from anon, authenticated, service_role, public;
grant execute on function public.has_active_identity_link(uuid, uuid) to authenticated, service_role;

-- The five self-service RPCs HRT-295's own db-test regression names -- verbatim their live
-- bodies, only the membership-check function name changed.

create or replace function app.get_my_employee_profile(p_tenant_id uuid, p_actor_auth_user_id uuid)
returns table(master_record_id uuid, employee_number text, tenant_id uuid, user_id uuid, full_name text, employment_type text, lifecycle_status text, intake_source text, work_email text, work_phone text, personal_email text, personal_phone text, national_id_number text, date_of_birth date, gender text, personal_address_street text, personal_address_city text, personal_address_province text, personal_address_postal_code text, personal_address_country text, hire_date date, probation_end_date date, employment_end_date date, company_org_unit_id uuid, branch_org_unit_id uuid, department_org_unit_id uuid, position_title text, manager_employee_id uuid, record_version integer, created_at timestamp with time zone, updated_at timestamp with time zone)
language plpgsql
security definer
set search_path to 'app', 'pg_temp'
as $function$
declare
  v_caller_user_id uuid;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  if not app.has_active_identity_link(p_tenant_id, p_actor_auth_user_id) then
    return;
  end if;

  select u.id into v_caller_user_id from app.users u where u.auth_user_id = p_actor_auth_user_id and u.tenant_id = p_tenant_id;
  if v_caller_user_id is null then
    return;
  end if;

  return query
  select
    e.master_record_id, m.code, e.tenant_id, e.user_id, e.full_name, e.employment_type, e.lifecycle_status, e.intake_source,
    e.work_email, e.work_phone, e.personal_email, e.personal_phone, e.national_id_number, e.date_of_birth, e.gender,
    e.personal_address_street, e.personal_address_city, e.personal_address_province, e.personal_address_postal_code, e.personal_address_country,
    e.hire_date, e.probation_end_date, e.employment_end_date, e.company_org_unit_id, e.branch_org_unit_id, e.department_org_unit_id,
    e.position_title, e.manager_employee_id, e.record_version, e.created_at, e.updated_at
  from app.employees e
  join app.master_records m on m.id = e.master_record_id
  where e.tenant_id = p_tenant_id and e.user_id = v_caller_user_id;
end;
$function$;

create or replace function app.get_my_assigned_interviews(p_tenant_id uuid, p_actor_auth_user_id uuid)
returns table(interview_id uuid, application_id uuid, candidate_full_name text, vacancy_title text, scheduled_at timestamp with time zone, status text, my_feedback_submitted boolean)
language plpgsql
stable
security definer
set search_path to 'app', 'pg_temp'
as $function$
declare
  v_employee_id uuid;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  -- Explicit tenant-membership guard (defense in depth, HRT-275 "cheap defense in
  -- depth" precedent) -- app.resolve_actor_employee_id already implies membership
  -- transitively (app.users.tenant_id must match), but an explicit gate here is both
  -- clearer and keeps this function inside rbac-enforcement.sql's own authority-check
  -- call-graph closure (ISS-2026-033), matching app.get_my_employee_profile's own
  -- established shape exactly.
  if not app.has_active_identity_link(p_tenant_id, p_actor_auth_user_id) then
    return;
  end if;

  v_employee_id := app.resolve_actor_employee_id(p_tenant_id, p_actor_auth_user_id);
  if v_employee_id is null then
    return;
  end if;

  return query
  select i.id, a.id, c.full_name, v.title, i.scheduled_at, i.status,
    exists (select 1 from app.interview_feedback f where f.interview_id = i.id and f.interviewer_employee_id = v_employee_id)
  from app.interview_interviewers ii
  join app.interviews i on i.id = ii.interview_id
  join app.job_applications a on a.id = i.application_id
  join app.candidates c on c.id = a.candidate_id
  join app.job_vacancies v on v.id = a.vacancy_id
  where ii.employee_id = v_employee_id and i.tenant_id = p_tenant_id
  order by i.scheduled_at desc;
end;
$function$;

create or replace function app.get_my_attendance_status(p_tenant_id uuid, p_actor_auth_user_id uuid)
returns table(session_id uuid, work_date date, status text, effective_clock_in_at timestamp with time zone, effective_clock_out_at timestamp with time zone, open_exception_count integer, payroll_input_status text)
language plpgsql
security definer
set search_path to 'app', 'pg_temp'
as $function$
declare
  v_self app.employees;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  if not app.has_active_identity_link(p_tenant_id, p_actor_auth_user_id) then
    return;
  end if;

  v_self := app.get_self_employee(p_tenant_id, p_actor_auth_user_id);
  if v_self.master_record_id is null then
    return;
  end if;

  return query
  select s.id, s.work_date, s.status, s.effective_clock_in_at, s.effective_clock_out_at,
         (select count(*)::integer from app.attendance_exceptions x where x.session_id = s.id and x.status in ('open', 'acknowledged')),
         s.payroll_input_status
  from app.attendance_sessions s
  where s.tenant_id = p_tenant_id and s.employee_id = v_self.master_record_id
  order by s.work_date desc
  limit 14;
end;
$function$;

create or replace function app.get_my_employee_position_assignment_history(p_tenant_id uuid, p_actor_auth_user_id uuid)
returns setof app.employee_position_assignments
language plpgsql
security definer
set search_path to 'app', 'pg_temp'
as $function$
declare
  v_caller_user_id uuid;
  v_master_record_id uuid;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  if not app.has_active_identity_link(p_tenant_id, p_actor_auth_user_id) then
    return;
  end if;

  select u.id into v_caller_user_id from app.users u where u.auth_user_id = p_actor_auth_user_id and u.tenant_id = p_tenant_id;
  if v_caller_user_id is null then
    return;
  end if;

  select e.master_record_id into v_master_record_id from app.employees e where e.tenant_id = p_tenant_id and e.user_id = v_caller_user_id;
  if v_master_record_id is null then
    return;
  end if;

  return query
  select * from app.employee_position_assignments
  where master_record_id = v_master_record_id
  order by effective_start_date desc, created_at desc;
end;
$function$;

create or replace function app.get_my_schedule(p_tenant_id uuid, p_actor_auth_user_id uuid, p_from_date date, p_to_date date)
returns table(assignment_id uuid, work_date date, shift_template_id uuid, shift_template_name text, shift_type text, crosses_midnight boolean, status text)
language plpgsql
security definer
set search_path to 'app', 'pg_temp'
as $function$
declare
  v_self app.employees;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  if not app.has_active_identity_link(p_tenant_id, p_actor_auth_user_id) then
    return;
  end if;

  v_self := app.get_self_employee(p_tenant_id, p_actor_auth_user_id);
  if v_self.master_record_id is null then
    return;
  end if;

  return query
  select sa.id, sa.work_date, st.id, st.name, sv.shift_type, sv.crosses_midnight, sa.status
  from app.schedule_assignments sa
  join app.shift_template_versions sv on sv.id = sa.shift_template_version_id
  join app.shift_templates st on st.id = sv.shift_template_id
  where sa.tenant_id = p_tenant_id and sa.employee_id = v_self.master_record_id and sa.status = 'published'
    and (p_from_date is null or sa.work_date >= p_from_date) and (p_to_date is null or sa.work_date <= p_to_date)
  order by sa.work_date;
end;
$function$;
