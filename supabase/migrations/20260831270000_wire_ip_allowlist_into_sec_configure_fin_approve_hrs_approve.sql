-- ISS-2026-302 (docs/runtime/KNOWN_ISSUES.md) -- the IP-restriction half of ISS-2026-236:
-- SEC:Configure, FIN:Approve and HRS:Approve still have no IP-allowlist wiring.
--
-- ISS-2026-236 named two missing controls for the same three high-risk tuples: step-up MFA
-- and IP restriction. The step-up half closed at the app.evaluate_permission chokepoint. The
-- IP half cannot use that chokepoint, and that is structural rather than a scoping choice:
-- IP enforcement here is app.assert_ip_allowed(tenant, client_ip, ...), which needs the
-- caller's own address, and app.evaluate_permission has no such parameter and no way to
-- obtain one. The pattern every wired function uses is an explicit optional trailing
-- p_client_ip supplied by the caller (20260826190000, the import-commit RPCs).
--
-- COUNT CORRECTED. The entry says 61 functions. A live pg_proc sweep returns 66 volatile
-- app.* functions gating on one of the three tuples -- 31 on SEC:Configure or HRS:Approve
-- via app.evaluate_permission, 35 on FIN:Approve via the app.check_finance_*_authority
-- helpers, which the entry's own regex-shaped count would not have matched because those
-- helpers take the action as a parameter. 61 is the number of them with a TypeScript caller,
-- which is a different question from how many exist.
--
-- 65 are widened here. app.create_and_post_finance_system_journal is deliberately NOT:
-- its front door admits FIN:Edit OR FIN:Approve, it has no TypeScript caller, and it exists
-- to be composed by app.post_finance_subledger_batch, app.allocate_finance_receipt and
-- app.post_finance_correction. It is an internal posting primitive that happens to accept an
-- approver, not an approval action a person performs from a browser. Wiring it would mean
-- threading p_client_ip through every internal caller as well -- a different change, and one
-- that would put an address parameter on a function no request ever reaches directly.
--
-- HOW EACH BODY WAS PRODUCED. Every one of the 130 definitions below (65 app.* plus their
-- 65 public.* wrappers) is the LIVE pg_get_functiondef output with exactly one scripted
-- insertion, asserted to match exactly once per function before anything was emitted.
-- Nothing was retyped, and nothing was rebuilt from its creating migration -- many of these
-- have been superseded by later hardening migrations, and rebuilding from a creating
-- migration is the trap that nearly deleted five live dispatcher branches at the
-- sixty-seventh freeze pass. The insertion point is the first `end if;` after the function's
-- own authority check, so the gate lands after authority is established and before any state
-- change, which is the ordering discipline HDN-378 and 20260826190000 both used.
--
-- CREATE OR REPLACE cannot be used: appending a parameter creates a second, ambiguous
-- overload rather than replacing the function (ISS-2026-260). Every one is DROP + CREATE,
-- with the public.* wrapper dropped first because a language-sql wrapper holds a real
-- pg_depend edge on the app.* function it calls. Grants are re-emitted from each function's
-- own live grantee set, not assumed.
--
-- WHAT THIS DOES AND DOES NOT GUARANTEE, stated plainly because the parameter's shape
-- invites the wrong reading. p_client_ip defaults to null and the gate is skipped when it is
-- null, so this is not a boundary a caller cannot cross -- any caller may simply omit the
-- address, exactly as they can today. It is defense in depth and an audit signal: a caller
-- that DOES supply an address is now checked on all 65, where before it was checked on none
-- of them. The enforcement that cannot be omitted remains the authority check above it.
--
-- ISS-2026-307's residual is unchanged by this migration and deliberately not made worse:
-- a denial raised inside a business transaction still loses its own app.ip_access_evaluations
-- row when that transaction aborts. That is why the durable evidence for these 65 is produced
-- at the application layer instead, by lib/security/ip-restriction-gate.ts calling
-- public.evaluate_ip_access in its own transaction BEFORE the business RPC -- where a denial
-- persists and raises its security incident -- with the gate below as the enforcement that
-- runs whether or not the pre-check did.

-- LIVE DRIFT FOUND AND REPAIRED HERE, recorded as ISS-2026-318. 29 of the 65 public.*
-- wrappers had lost their `security definer` flag on the hosted project, while the migration
-- set (20260826000000) declares every one of them definer. The public.* wrapper-parity gate
-- runs against a migration-built disposable database, so it could not see this: it compares
-- what the migrations say to what the migrations say. Copying the live shape into this
-- migration is what surfaced it -- the gate failed immediately, naming all 29. They are
-- recreated below as the migration set declares, which repairs the drift live as a side
-- effect of this change rather than leaving it for someone to find later.
--
-- Not a privilege escalation and not an exposure: the app.* function each one wraps IS
-- security definer, so the privileged work always ran as the owner regardless of the
-- wrapper's own mode. What drifted was the wrapper's declared shape, and a wrapper whose
-- shape nobody can predict from the migration set is exactly what the parity gate exists to
-- prevent.

-- 1. activate_employee -- authority shape: eval, tenant expression: v_employee.tenant_id
drop function public.activate_employee(p_master_record_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text);
drop function app.activate_employee(p_master_record_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text);

create function app.activate_employee(p_master_record_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text default null)
 RETURNS app.employees
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_decision app.rbac_decision;
  v_employee app.employees;
begin
  select * into v_employee from app.employees where master_record_id = p_master_record_id for update;
  if not found or not app.has_active_tenant_membership(v_employee.tenant_id, p_actor_auth_user_id) then
    raise exception 'employee_not_found: %', p_master_record_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_employee.tenant_id, 'HRS', 'Approve');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks HRS:Approve (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_employee.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  -- ISS-2026-302: IP allowlist, checked after authority is established and before any
  -- state change. Skipped when the caller supplies no address, and bypassable via the
  -- separately-governed app.ip_allowlist_bypass_grants -- the identical composition
  -- 20260826190000 established for the import-commit RPCs.
  if p_client_ip is not null and not app.has_active_ip_allowlist_bypass(v_employee.tenant_id, p_actor_auth_user_id) then
    perform app.assert_ip_allowed(v_employee.tenant_id, p_client_ip, 'admin', p_actor_label);
  end if;

  if v_employee.record_version <> p_expected_version then
    raise exception 'stale_version: employee % expected version % but found %', p_master_record_id, p_expected_version, v_employee.record_version
      using errcode = 'serialization_failure';
  end if;

  if v_employee.lifecycle_status <> 'approved' then
    raise exception 'invalid_transition: employee % is % and cannot be activated', p_master_record_id, v_employee.lifecycle_status
      using errcode = 'check_violation';
  end if;

  update app.employees
  set lifecycle_status = 'active'
  where master_record_id = p_master_record_id and record_version = p_expected_version
  returning * into v_employee;
  if not found then
    raise exception 'stale_version: employee % target row was concurrently modified (expected version %)', p_master_record_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  insert into app.employee_lifecycle_events (tenant_id, master_record_id, from_status, to_status, actor_auth_user_id, actor_label)
  values (v_employee.tenant_id, p_master_record_id, 'approved', 'active', p_actor_auth_user_id, p_actor_label);

  perform app.capture_audit_event(
    v_employee.tenant_id, p_actor_auth_user_id, p_actor_label, 'activate_employee',
    'app.employees', p_master_record_id, 'success', null, null, '{}'::jsonb
  );

  return v_employee;
end;
$function$;

revoke execute on function app.activate_employee(p_master_record_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) from anon, authenticated, service_role, public;
grant execute on function app.activate_employee(p_master_record_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) to authenticated;
grant execute on function app.activate_employee(p_master_record_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) to service_role;

create function public.activate_employee(p_master_record_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text default null)
 RETURNS app.employees
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
  select app.activate_employee(p_master_record_id, p_expected_version, p_actor_auth_user_id, p_actor_label, p_client_ip);
$function$;

revoke execute on function public.activate_employee(p_master_record_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) from anon, authenticated, service_role, public;
grant execute on function public.activate_employee(p_master_record_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) to authenticated;
grant execute on function public.activate_employee(p_master_record_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) to service_role;

-- 2. activate_finance_account -- authority shape: fin, tenant expression: v_account.tenant_id [wrapper definer flag repaired -- live had drifted to invoker]
drop function public.activate_finance_account(p_account_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text);
drop function app.activate_finance_account(p_account_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text);

create function app.activate_finance_account(p_account_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text default null)
 RETURNS app.finance_accounts
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_account app.finance_accounts;
  v_parent app.finance_accounts;
begin
  select * into v_account from app.finance_accounts where id = p_account_id;
  if not found then
    raise exception 'finance_account_not_found: %', p_account_id using errcode = 'no_data_found';
  end if;

  if v_account.record_version <> p_expected_version then
    raise exception 'stale_version: account % expected version % but found %', p_account_id, p_expected_version, v_account.record_version
      using errcode = 'serialization_failure';
  end if;

  if v_account.status <> 'draft' then
    raise exception 'finance_account_not_draft: account % is %, only a draft may be activated', p_account_id, v_account.status
      using errcode = 'check_violation';
  end if;

  if not app.check_finance_account_authority('Approve', v_account.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:Approve for tenant %', p_actor_auth_user_id, v_account.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  -- ISS-2026-302: IP allowlist, checked after authority is established and before any
  -- state change. Skipped when the caller supplies no address, and bypassable via the
  -- separately-governed app.ip_allowlist_bypass_grants -- the identical composition
  -- 20260826190000 established for the import-commit RPCs.
  if p_client_ip is not null and not app.has_active_ip_allowlist_bypass(v_account.tenant_id, p_actor_auth_user_id) then
    perform app.assert_ip_allowed(v_account.tenant_id, p_client_ip, 'admin', p_actor_label);
  end if;

  if app.detect_finance_account_hierarchy_cycle(v_account.id, v_account.parent_account_id) then
    raise exception 'finance_account_hierarchy_cycle: activating account % would create or confirm a cyclic/over-deep hierarchy', p_account_id
      using errcode = 'check_violation';
  end if;

  if v_account.parent_account_id is not null then
    select * into v_parent from app.finance_accounts where id = v_account.parent_account_id;
    if v_parent.status = 'inactive' then
      raise exception 'finance_account_parent_inactive: parent account % is inactive', v_account.parent_account_id
        using errcode = 'check_violation';
    end if;
  end if;

  update app.finance_accounts
  set status = 'active'
  where id = p_account_id and record_version = p_expected_version
  returning * into v_account;
  -- ATW-032 (ISS-2026-034): the version predicate above already PREVENTS the lost
  -- update -- the loser's UPDATE simply matches no row. What it did not do was say so:
  -- execution fell straight through with a NULL composite, so the audit trail gained a
  -- fabricated 'success' row with a NULL tenant_id and the caller was handed an all-NULL
  -- record instead of the 'stale_version' its own error contract already handles.
  if not found then
    raise exception 'stale_version: activate_finance_account target row was concurrently modified (expected version %)', p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_account.tenant_id, p_actor_auth_user_id, p_actor_label, 'activate_finance_account',
    'app.finance_accounts', v_account.id, 'success', null, null, to_jsonb(v_account)
  );

  return v_account;
end;
$function$;

revoke execute on function app.activate_finance_account(p_account_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) from anon, authenticated, service_role, public;
grant execute on function app.activate_finance_account(p_account_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) to authenticated;
grant execute on function app.activate_finance_account(p_account_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) to service_role;

create function public.activate_finance_account(p_account_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text default null)
 RETURNS app.finance_accounts
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
  select app.activate_finance_account(p_account_id, p_expected_version, p_actor_auth_user_id, p_actor_label, p_client_ip);
$function$;

revoke execute on function public.activate_finance_account(p_account_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) from anon, authenticated, service_role, public;
grant execute on function public.activate_finance_account(p_account_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) to authenticated;
grant execute on function public.activate_finance_account(p_account_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) to service_role;

-- 3. add_ip_allowlist_entry -- authority shape: eval, tenant expression: p_tenant_id
drop function public.add_ip_allowlist_entry(p_tenant_id uuid, p_raw_cidr text, p_label text, p_scope text, p_actor_auth_user_id uuid, p_actor_label text);
drop function app.add_ip_allowlist_entry(p_tenant_id uuid, p_raw_cidr text, p_label text, p_scope text, p_actor_auth_user_id uuid, p_actor_label text);

create function app.add_ip_allowlist_entry(p_tenant_id uuid, p_raw_cidr text, p_label text, p_scope text, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text default null)
 RETURNS app.ip_allowlist_entries
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_decision app.rbac_decision;
  v_cidr cidr;
  v_entry app.ip_allowlist_entries;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'SEC', 'Configure');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks SEC:Configure (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  -- ISS-2026-302: IP allowlist, checked after authority is established and before any
  -- state change. Skipped when the caller supplies no address, and bypassable via the
  -- separately-governed app.ip_allowlist_bypass_grants -- the identical composition
  -- 20260826190000 established for the import-commit RPCs.
  if p_client_ip is not null and not app.has_active_ip_allowlist_bypass(p_tenant_id, p_actor_auth_user_id) then
    perform app.assert_ip_allowed(p_tenant_id, p_client_ip, 'admin', p_actor_label);
  end if;

  v_cidr := app._parse_cidr(p_raw_cidr);
  if v_cidr is null then
    raise exception 'ip_allowlist_invalid_cidr: % is not a well-formed IPv4/IPv6 CIDR', p_raw_cidr using errcode = 'invalid_text_representation';
  end if;

  if coalesce(p_scope, 'all') not in ('ui', 'api', 'admin', 'all') then
    raise exception 'ip_allowlist_invalid_scope: % is not one of ui/api/admin/all', p_scope using errcode = 'check_violation';
  end if;

  insert into app.ip_allowlist_entries (tenant_id, cidr, label, scope, created_by_auth_user_id, created_by)
  values (p_tenant_id, v_cidr, p_label, coalesce(p_scope, 'all'), p_actor_auth_user_id, p_actor_label)
  returning * into v_entry;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'add_ip_allowlist_entry',
    'app.ip_allowlist_entries', v_entry.id, 'success', null, null, to_jsonb(v_entry)
  );

  return v_entry;
end;
$function$;

revoke execute on function app.add_ip_allowlist_entry(p_tenant_id uuid, p_raw_cidr text, p_label text, p_scope text, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) from anon, authenticated, service_role, public;
grant execute on function app.add_ip_allowlist_entry(p_tenant_id uuid, p_raw_cidr text, p_label text, p_scope text, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) to authenticated;
grant execute on function app.add_ip_allowlist_entry(p_tenant_id uuid, p_raw_cidr text, p_label text, p_scope text, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) to service_role;

create function public.add_ip_allowlist_entry(p_tenant_id uuid, p_raw_cidr text, p_label text, p_scope text, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text default null)
 RETURNS app.ip_allowlist_entries
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
  select app.add_ip_allowlist_entry(p_tenant_id, p_raw_cidr, p_label, p_scope, p_actor_auth_user_id, p_actor_label, p_client_ip);
$function$;

revoke execute on function public.add_ip_allowlist_entry(p_tenant_id uuid, p_raw_cidr text, p_label text, p_scope text, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) from anon, authenticated, service_role, public;
grant execute on function public.add_ip_allowlist_entry(p_tenant_id uuid, p_raw_cidr text, p_label text, p_scope text, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) to authenticated;
grant execute on function public.add_ip_allowlist_entry(p_tenant_id uuid, p_raw_cidr text, p_label text, p_scope text, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) to service_role;

-- 4. approve_attendance_for_payroll_input -- authority shape: eval, tenant expression: p_tenant_id
drop function public.approve_attendance_for_payroll_input(p_tenant_id uuid, p_from_date date, p_to_date date, p_employee_id uuid, p_actor_auth_user_id uuid, p_actor_label text);
drop function app.approve_attendance_for_payroll_input(p_tenant_id uuid, p_from_date date, p_to_date date, p_employee_id uuid, p_actor_auth_user_id uuid, p_actor_label text);

create function app.approve_attendance_for_payroll_input(p_tenant_id uuid, p_from_date date, p_to_date date, p_employee_id uuid, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text default null)
 RETURNS TABLE(session_id uuid, approved boolean, skip_reason text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_decision app.rbac_decision;
  v_row app.attendance_sessions;
  v_open_exceptions integer;
begin
  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'HRS', 'Approve');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks HRS:Approve (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  -- ISS-2026-302: IP allowlist, checked after authority is established and before any
  -- state change. Skipped when the caller supplies no address, and bypassable via the
  -- separately-governed app.ip_allowlist_bypass_grants -- the identical composition
  -- 20260826190000 established for the import-commit RPCs.
  if p_client_ip is not null and not app.has_active_ip_allowlist_bypass(p_tenant_id, p_actor_auth_user_id) then
    perform app.assert_ip_allowed(p_tenant_id, p_client_ip, 'admin', p_actor_label);
  end if;

  if p_from_date is null or p_to_date is null or p_to_date < p_from_date or (p_to_date - p_from_date) > 92 then
    raise exception 'invalid_date_range: date range must be non-empty and at most 92 days' using errcode = 'check_violation';
  end if;

  for v_row in
    select s.* from app.attendance_sessions s
    where s.tenant_id = p_tenant_id and s.work_date between p_from_date and p_to_date
      and (p_employee_id is null or s.employee_id = p_employee_id)
      and s.payroll_input_status = 'pending'
    for update
  loop
    if v_row.status <> 'closed' then
      session_id := v_row.id; approved := false; skip_reason := 'session_not_closed';
      return next;
      continue;
    end if;

    select count(*) into v_open_exceptions from app.attendance_exceptions x where x.session_id = v_row.id and x.status in ('open', 'acknowledged');
    if v_open_exceptions > 0 then
      session_id := v_row.id; approved := false; skip_reason := 'unresolved_exceptions';
      return next;
      continue;
    end if;

    update app.attendance_sessions
    set payroll_input_status = 'approved', payroll_approved_by = p_actor_label, payroll_approved_at = now()
    where id = v_row.id;

    session_id := v_row.id; approved := true; skip_reason := null;
    return next;
  end loop;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'approve_attendance_for_payroll_input',
    'app.attendance_sessions', null, 'success', null, null, jsonb_build_object('from_date', p_from_date, 'to_date', p_to_date, 'employee_id', p_employee_id)
  );

  return;
end;
$function$;

revoke execute on function app.approve_attendance_for_payroll_input(p_tenant_id uuid, p_from_date date, p_to_date date, p_employee_id uuid, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) from anon, authenticated, service_role, public;
grant execute on function app.approve_attendance_for_payroll_input(p_tenant_id uuid, p_from_date date, p_to_date date, p_employee_id uuid, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) to authenticated;
grant execute on function app.approve_attendance_for_payroll_input(p_tenant_id uuid, p_from_date date, p_to_date date, p_employee_id uuid, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) to service_role;

create function public.approve_attendance_for_payroll_input(p_tenant_id uuid, p_from_date date, p_to_date date, p_employee_id uuid, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text default null)
 RETURNS TABLE(session_id uuid, approved boolean, skip_reason text)
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
  select * from app.approve_attendance_for_payroll_input(p_tenant_id, p_from_date, p_to_date, p_employee_id, p_actor_auth_user_id, p_actor_label, p_client_ip);
$function$;

revoke execute on function public.approve_attendance_for_payroll_input(p_tenant_id uuid, p_from_date date, p_to_date date, p_employee_id uuid, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) from anon, authenticated, service_role, public;
grant execute on function public.approve_attendance_for_payroll_input(p_tenant_id uuid, p_from_date date, p_to_date date, p_employee_id uuid, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) to authenticated;
grant execute on function public.approve_attendance_for_payroll_input(p_tenant_id uuid, p_from_date date, p_to_date date, p_employee_id uuid, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) to service_role;

-- 5. approve_finance_correction -- authority shape: fin, tenant expression: v_correction.tenant_id [wrapper definer flag repaired -- live had drifted to invoker]
drop function public.approve_finance_correction(p_correction_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text);
drop function app.approve_finance_correction(p_correction_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text);

create function app.approve_finance_correction(p_correction_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text default null)
 RETURNS app.finance_journal_corrections
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_correction app.finance_journal_corrections;
begin
  select * into v_correction from app.finance_journal_corrections where id = p_correction_id for update;
  if not found then
    raise exception 'finance_correction_not_found: %', p_correction_id using errcode = 'no_data_found';
  end if;
  if not app.check_finance_correction_authority('Approve', v_correction.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:Approve for tenant %', p_actor_auth_user_id, v_correction.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  -- ISS-2026-302: IP allowlist, checked after authority is established and before any
  -- state change. Skipped when the caller supplies no address, and bypassable via the
  -- separately-governed app.ip_allowlist_bypass_grants -- the identical composition
  -- 20260826190000 established for the import-commit RPCs.
  if p_client_ip is not null and not app.has_active_ip_allowlist_bypass(v_correction.tenant_id, p_actor_auth_user_id) then
    perform app.assert_ip_allowed(v_correction.tenant_id, p_client_ip, 'admin', p_actor_label);
  end if;
  if v_correction.record_version <> p_expected_version then
    raise exception 'stale_version: correction % expected version % but found %', p_correction_id, p_expected_version, v_correction.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_correction.status <> 'submitted' then
    raise exception 'finance_correction_not_submitted: correction % is % not submitted', p_correction_id, v_correction.status
      using errcode = 'check_violation';
  end if;

  update app.finance_journal_corrections set status = 'approved', approved_by = p_actor_label, approved_at = now() where id = p_correction_id returning * into v_correction;

  perform app.capture_audit_event(
    v_correction.tenant_id, p_actor_auth_user_id, p_actor_label, 'approve_finance_correction',
    'app.finance_journal_corrections', v_correction.id, 'success', null, null, to_jsonb(v_correction)
  );

  return v_correction;
end;
$function$;

revoke execute on function app.approve_finance_correction(p_correction_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) from anon, authenticated, service_role, public;
grant execute on function app.approve_finance_correction(p_correction_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) to authenticated;
grant execute on function app.approve_finance_correction(p_correction_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) to service_role;

create function public.approve_finance_correction(p_correction_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text default null)
 RETURNS app.finance_journal_corrections
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
  select app.approve_finance_correction(p_correction_id, p_expected_version, p_actor_auth_user_id, p_actor_label, p_client_ip);
$function$;

revoke execute on function public.approve_finance_correction(p_correction_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) from anon, authenticated, service_role, public;
grant execute on function public.approve_finance_correction(p_correction_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) to authenticated;
grant execute on function public.approve_finance_correction(p_correction_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) to service_role;

-- 6. approve_finance_exchange_rate -- authority shape: fin, tenant expression: v_rate.tenant_id [wrapper definer flag repaired -- live had drifted to invoker]
drop function public.approve_finance_exchange_rate(p_rate_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text);
drop function app.approve_finance_exchange_rate(p_rate_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text);

create function app.approve_finance_exchange_rate(p_rate_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text default null)
 RETURNS app.finance_exchange_rates
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_rate app.finance_exchange_rates;
  v_overlap_count integer;
begin
  select * into v_rate from app.finance_exchange_rates where id = p_rate_id for update;
  -- ATW-032: the overlapping-approved-window check below was an unlocked read with no
  -- exclusion constraint behind it, so two concurrent approvals for the same currency pair
  -- could both pass it and leave two overlapping approved rates -- after which every
  -- conversion for that pair depends on which row a query happens to pick. Locking the
  -- row being approved serialises approvals of the same rate.
  if not found then
    raise exception 'finance_exchange_rate_not_found: %', p_rate_id using errcode = 'no_data_found';
  end if;

  if v_rate.record_version <> p_expected_version then
    raise exception 'stale_version: rate % expected version % but found %', p_rate_id, p_expected_version, v_rate.record_version
      using errcode = 'serialization_failure';
  end if;

  if v_rate.status <> 'draft' then
    raise exception 'finance_exchange_rate_not_draft: rate % is %, only a draft may be approved', p_rate_id, v_rate.status
      using errcode = 'check_violation';
  end if;

  if not app.check_finance_exchange_rate_authority('Approve', v_rate.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:Approve for tenant %', p_actor_auth_user_id, v_rate.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  -- ISS-2026-302: IP allowlist, checked after authority is established and before any
  -- state change. Skipped when the caller supplies no address, and bypassable via the
  -- separately-governed app.ip_allowlist_bypass_grants -- the identical composition
  -- 20260826190000 established for the import-commit RPCs.
  if p_client_ip is not null and not app.has_active_ip_allowlist_bypass(v_rate.tenant_id, p_actor_auth_user_id) then
    perform app.assert_ip_allowed(v_rate.tenant_id, p_client_ip, 'admin', p_actor_label);
  end if;

  select count(*) into v_overlap_count from app.finance_exchange_rates
    where id <> p_rate_id
      and status = 'approved'
      and coalesce(tenant_id, '00000000-0000-0000-0000-000000000000'::uuid) = coalesce(v_rate.tenant_id, '00000000-0000-0000-0000-000000000000'::uuid)
      and rate_type = v_rate.rate_type
      and source_currency = v_rate.source_currency
      and target_currency = v_rate.target_currency
      and effective_from <= coalesce(v_rate.effective_to, 'infinity'::timestamptz)
      and coalesce(effective_to, 'infinity'::timestamptz) >= v_rate.effective_from;
  if v_overlap_count > 0 then
    raise exception 'finance_exchange_rate_overlap: an approved rate already covers an overlapping window for this scope/type/pair'
      using errcode = 'check_violation';
  end if;

  update app.finance_exchange_rates
  set status = 'approved', approved_by = p_actor_label, approved_at = now()
  where id = p_rate_id and record_version = p_expected_version
  returning * into v_rate;
  -- ATW-032 (ISS-2026-034): the version predicate above already PREVENTS the lost
  -- update -- the loser's UPDATE simply matches no row. What it did not do was say so:
  -- execution fell straight through with a NULL composite, so the audit trail gained a
  -- fabricated 'success' row with a NULL tenant_id and the caller was handed an all-NULL
  -- record instead of the 'stale_version' its own error contract already handles.
  if not found then
    raise exception 'stale_version: approve_finance_exchange_rate target row was concurrently modified (expected version %)', p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_rate.tenant_id, p_actor_auth_user_id, p_actor_label, 'approve_finance_exchange_rate',
    'app.finance_exchange_rates', v_rate.id, 'success', null, null, to_jsonb(v_rate)
  );

  return v_rate;
end;
$function$;

revoke execute on function app.approve_finance_exchange_rate(p_rate_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) from anon, authenticated, service_role, public;
grant execute on function app.approve_finance_exchange_rate(p_rate_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) to authenticated;
grant execute on function app.approve_finance_exchange_rate(p_rate_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) to service_role;

create function public.approve_finance_exchange_rate(p_rate_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text default null)
 RETURNS app.finance_exchange_rates
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
  select app.approve_finance_exchange_rate(p_rate_id, p_expected_version, p_actor_auth_user_id, p_actor_label, p_client_ip);
$function$;

revoke execute on function public.approve_finance_exchange_rate(p_rate_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) from anon, authenticated, service_role, public;
grant execute on function public.approve_finance_exchange_rate(p_rate_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) to authenticated;
grant execute on function public.approve_finance_exchange_rate(p_rate_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) to service_role;

-- 7. approve_finance_invoice -- authority shape: fin, tenant expression: v_invoice.tenant_id [wrapper definer flag repaired -- live had drifted to invoker]
drop function public.approve_finance_invoice(p_invoice_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text);
drop function app.approve_finance_invoice(p_invoice_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text);

create function app.approve_finance_invoice(p_invoice_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text default null)
 RETURNS app.finance_invoices
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_invoice app.finance_invoices;
begin
  select * into v_invoice from app.finance_invoices where id = p_invoice_id for update;
  if not found or not app.has_active_tenant_membership(v_invoice.tenant_id, p_actor_auth_user_id) then
    raise exception 'finance_invoice_not_found: %', p_invoice_id using errcode = 'no_data_found';
  end if;
  if not app.check_finance_invoice_authority('Approve', v_invoice.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:Approve for tenant %', p_actor_auth_user_id, v_invoice.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  -- ISS-2026-302: IP allowlist, checked after authority is established and before any
  -- state change. Skipped when the caller supplies no address, and bypassable via the
  -- separately-governed app.ip_allowlist_bypass_grants -- the identical composition
  -- 20260826190000 established for the import-commit RPCs.
  if p_client_ip is not null and not app.has_active_ip_allowlist_bypass(v_invoice.tenant_id, p_actor_auth_user_id) then
    perform app.assert_ip_allowed(v_invoice.tenant_id, p_client_ip, 'admin', p_actor_label);
  end if;
  if v_invoice.record_version <> p_expected_version then
    raise exception 'stale_version: invoice % expected version % but found %', p_invoice_id, p_expected_version, v_invoice.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_invoice.status <> 'submitted' then
    raise exception 'finance_invoice_not_submitted: invoice % is % not submitted', p_invoice_id, v_invoice.status
      using errcode = 'check_violation';
  end if;

  update app.finance_invoices set status = 'approved', approved_by = p_actor_label, approved_at = now() where id = p_invoice_id returning * into v_invoice;

  perform app.capture_audit_event(
    v_invoice.tenant_id, p_actor_auth_user_id, p_actor_label, 'approve_finance_invoice',
    'app.finance_invoices', v_invoice.id, 'success', null, null, to_jsonb(v_invoice)
  );

  return v_invoice;
end;
$function$;

revoke execute on function app.approve_finance_invoice(p_invoice_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) from anon, authenticated, service_role, public;
grant execute on function app.approve_finance_invoice(p_invoice_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) to authenticated;
grant execute on function app.approve_finance_invoice(p_invoice_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) to service_role;

create function public.approve_finance_invoice(p_invoice_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text default null)
 RETURNS app.finance_invoices
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
  select app.approve_finance_invoice(p_invoice_id, p_expected_version, p_actor_auth_user_id, p_actor_label, p_client_ip);
$function$;

revoke execute on function public.approve_finance_invoice(p_invoice_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) from anon, authenticated, service_role, public;
grant execute on function public.approve_finance_invoice(p_invoice_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) to authenticated;
grant execute on function public.approve_finance_invoice(p_invoice_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) to service_role;

-- 8. approve_finance_journal -- authority shape: fin, tenant expression: v_journal.tenant_id [wrapper definer flag repaired -- live had drifted to invoker]
drop function public.approve_finance_journal(p_journal_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text);
drop function app.approve_finance_journal(p_journal_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text);

create function app.approve_finance_journal(p_journal_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text default null)
 RETURNS app.finance_journals
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_journal app.finance_journals;
begin
  select * into v_journal from app.finance_journals where id = p_journal_id for update;
  if not found then
    raise exception 'finance_journal_not_found: %', p_journal_id using errcode = 'no_data_found';
  end if;
  if not app.check_finance_journal_authority('Approve', v_journal.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:Approve for tenant %', p_actor_auth_user_id, v_journal.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  -- ISS-2026-302: IP allowlist, checked after authority is established and before any
  -- state change. Skipped when the caller supplies no address, and bypassable via the
  -- separately-governed app.ip_allowlist_bypass_grants -- the identical composition
  -- 20260826190000 established for the import-commit RPCs.
  if p_client_ip is not null and not app.has_active_ip_allowlist_bypass(v_journal.tenant_id, p_actor_auth_user_id) then
    perform app.assert_ip_allowed(v_journal.tenant_id, p_client_ip, 'admin', p_actor_label);
  end if;
  -- HDN-373 (ISS-2026-181, maker/checker): the preparer may not also be the approver.
  if v_journal.submitted_by_auth_user_id is not null and v_journal.submitted_by_auth_user_id = p_actor_auth_user_id then
    raise exception 'self_approval_denied: identity % submitted journal % and may not also approve it', p_actor_auth_user_id, p_journal_id
      using errcode = 'insufficient_privilege';
  end if;
  if v_journal.record_version <> p_expected_version then
    raise exception 'stale_version: journal % expected version % but found %', p_journal_id, p_expected_version, v_journal.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_journal.status <> 'submitted' then
    raise exception 'finance_journal_not_submitted: journal % is % not submitted', p_journal_id, v_journal.status
      using errcode = 'check_violation';
  end if;

  update app.finance_journals set status = 'approved', approved_by = p_actor_label, approved_at = now() where id = p_journal_id returning * into v_journal;

  perform app.capture_audit_event(
    v_journal.tenant_id, p_actor_auth_user_id, p_actor_label, 'approve_finance_journal',
    'app.finance_journals', v_journal.id, 'success', null, null, to_jsonb(v_journal)
  );

  return v_journal;
end;
$function$;

revoke execute on function app.approve_finance_journal(p_journal_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) from anon, authenticated, service_role, public;
grant execute on function app.approve_finance_journal(p_journal_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) to authenticated;
grant execute on function app.approve_finance_journal(p_journal_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) to service_role;

create function public.approve_finance_journal(p_journal_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text default null)
 RETURNS app.finance_journals
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
  select app.approve_finance_journal(p_journal_id, p_expected_version, p_actor_auth_user_id, p_actor_label, p_client_ip);
$function$;

revoke execute on function public.approve_finance_journal(p_journal_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) from anon, authenticated, service_role, public;
grant execute on function public.approve_finance_journal(p_journal_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) to authenticated;
grant execute on function public.approve_finance_journal(p_journal_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) to service_role;

-- 9. approve_finance_period_reopen -- authority shape: fin, tenant expression: v_lock.tenant_id [wrapper definer flag repaired -- live had drifted to invoker]
drop function public.approve_finance_period_reopen(p_lock_id uuid, p_expected_version integer, p_window_hours integer, p_actor_auth_user_id uuid, p_actor_label text);
drop function app.approve_finance_period_reopen(p_lock_id uuid, p_expected_version integer, p_window_hours integer, p_actor_auth_user_id uuid, p_actor_label text);

create function app.approve_finance_period_reopen(p_lock_id uuid, p_expected_version integer, p_window_hours integer, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text default null)
 RETURNS app.finance_period_locks
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_lock app.finance_period_locks;
begin
  select * into v_lock from app.finance_period_locks where id = p_lock_id for update;
  if not found then
    raise exception 'finance_period_lock_not_found: %', p_lock_id using errcode = 'no_data_found';
  end if;
  if not app.check_finance_period_lock_authority('Approve', v_lock.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:Approve for tenant %', p_actor_auth_user_id, v_lock.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  -- ISS-2026-302: IP allowlist, checked after authority is established and before any
  -- state change. Skipped when the caller supplies no address, and bypassable via the
  -- separately-governed app.ip_allowlist_bypass_grants -- the identical composition
  -- 20260826190000 established for the import-commit RPCs.
  if p_client_ip is not null and not app.has_active_ip_allowlist_bypass(v_lock.tenant_id, p_actor_auth_user_id) then
    perform app.assert_ip_allowed(v_lock.tenant_id, p_client_ip, 'admin', p_actor_label);
  end if;
  if v_lock.record_version <> p_expected_version then
    raise exception 'stale_version: lock % expected version % but found %', p_lock_id, p_expected_version, v_lock.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_lock.status <> 'reopen_requested' then
    raise exception 'finance_period_lock_not_reopen_requested: lock % is % not reopen_requested', p_lock_id, v_lock.status
      using errcode = 'check_violation';
  end if;
  if p_window_hours is null or p_window_hours <= 0 or p_window_hours > 720 then
    raise exception 'finance_period_reopen_window_invalid: % is not a valid reopen window (1-720 hours)', p_window_hours
      using errcode = 'check_violation';
  end if;

  update app.finance_period_locks
    set status = 'reopened', reopen_approved_by = p_actor_label, reopened_at = now(), reopen_window_expires_at = now() + make_interval(hours => p_window_hours)
    where id = p_lock_id
    returning * into v_lock;

  insert into app.finance_period_lock_events (lock_id, tenant_id, action, reason, actor_label) values (v_lock.id, v_lock.tenant_id, 'reopened', v_lock.reopen_reason, p_actor_label);

  perform app.capture_audit_event(
    v_lock.tenant_id, p_actor_auth_user_id, p_actor_label, 'approve_finance_period_reopen',
    'app.finance_period_locks', v_lock.id, 'success', null, null, to_jsonb(v_lock)
  );

  return v_lock;
end;
$function$;

revoke execute on function app.approve_finance_period_reopen(p_lock_id uuid, p_expected_version integer, p_window_hours integer, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) from anon, authenticated, service_role, public;
grant execute on function app.approve_finance_period_reopen(p_lock_id uuid, p_expected_version integer, p_window_hours integer, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) to authenticated;
grant execute on function app.approve_finance_period_reopen(p_lock_id uuid, p_expected_version integer, p_window_hours integer, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) to service_role;

create function public.approve_finance_period_reopen(p_lock_id uuid, p_expected_version integer, p_window_hours integer, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text default null)
 RETURNS app.finance_period_locks
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
  select app.approve_finance_period_reopen(p_lock_id, p_expected_version, p_window_hours, p_actor_auth_user_id, p_actor_label, p_client_ip);
$function$;

revoke execute on function public.approve_finance_period_reopen(p_lock_id uuid, p_expected_version integer, p_window_hours integer, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) from anon, authenticated, service_role, public;
grant execute on function public.approve_finance_period_reopen(p_lock_id uuid, p_expected_version integer, p_window_hours integer, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) to authenticated;
grant execute on function public.approve_finance_period_reopen(p_lock_id uuid, p_expected_version integer, p_window_hours integer, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) to service_role;

-- 10. approve_finance_settlement -- authority shape: fin, tenant expression: v_settlement.tenant_id [wrapper definer flag repaired -- live had drifted to invoker]
drop function public.approve_finance_settlement(p_settlement_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text);
drop function app.approve_finance_settlement(p_settlement_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text);

create function app.approve_finance_settlement(p_settlement_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text default null)
 RETURNS app.finance_settlements
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_settlement app.finance_settlements;
begin
  select * into v_settlement from app.finance_settlements where id = p_settlement_id for update;
  if not found then
    raise exception 'finance_settlement_not_found: %', p_settlement_id using errcode = 'no_data_found';
  end if;
  if not app.check_finance_settlement_authority('Approve', v_settlement.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:Approve for tenant %', p_actor_auth_user_id, v_settlement.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  -- ISS-2026-302: IP allowlist, checked after authority is established and before any
  -- state change. Skipped when the caller supplies no address, and bypassable via the
  -- separately-governed app.ip_allowlist_bypass_grants -- the identical composition
  -- 20260826190000 established for the import-commit RPCs.
  if p_client_ip is not null and not app.has_active_ip_allowlist_bypass(v_settlement.tenant_id, p_actor_auth_user_id) then
    perform app.assert_ip_allowed(v_settlement.tenant_id, p_client_ip, 'admin', p_actor_label);
  end if;
  if v_settlement.record_version <> p_expected_version then
    raise exception 'stale_version: settlement % expected version % but found %', p_settlement_id, p_expected_version, v_settlement.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_settlement.status <> 'submitted' then
    raise exception 'finance_settlement_not_submitted: settlement % is % not submitted', p_settlement_id, v_settlement.status
      using errcode = 'check_violation';
  end if;

  update app.finance_settlements set status = 'approved', approved_by = p_actor_label, approved_at = now() where id = p_settlement_id returning * into v_settlement;

  perform app.capture_audit_event(
    v_settlement.tenant_id, p_actor_auth_user_id, p_actor_label, 'approve_finance_settlement',
    'app.finance_settlements', v_settlement.id, 'success', null, null, to_jsonb(v_settlement)
  );

  return v_settlement;
end;
$function$;

revoke execute on function app.approve_finance_settlement(p_settlement_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) from anon, authenticated, service_role, public;
grant execute on function app.approve_finance_settlement(p_settlement_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) to authenticated;
grant execute on function app.approve_finance_settlement(p_settlement_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) to service_role;

create function public.approve_finance_settlement(p_settlement_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text default null)
 RETURNS app.finance_settlements
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
  select app.approve_finance_settlement(p_settlement_id, p_expected_version, p_actor_auth_user_id, p_actor_label, p_client_ip);
$function$;

revoke execute on function public.approve_finance_settlement(p_settlement_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) from anon, authenticated, service_role, public;
grant execute on function public.approve_finance_settlement(p_settlement_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) to authenticated;
grant execute on function public.approve_finance_settlement(p_settlement_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) to service_role;

-- 11. approve_finance_tax_rule -- authority shape: fin, tenant expression: v_rule.tenant_id [wrapper definer flag repaired -- live had drifted to invoker]
drop function public.approve_finance_tax_rule(p_rule_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text);
drop function app.approve_finance_tax_rule(p_rule_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text);

create function app.approve_finance_tax_rule(p_rule_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text default null)
 RETURNS app.finance_tax_rule_versions
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_rule app.finance_tax_rule_versions;
  v_overlap_count integer;
begin
  select * into v_rule from app.finance_tax_rule_versions where id = p_rule_id for update;
  if not found then
    raise exception 'finance_tax_rule_not_found: %', p_rule_id using errcode = 'no_data_found';
  end if;
  if not app.check_finance_tax_authority('Approve', v_rule.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:Approve for tenant %', p_actor_auth_user_id, v_rule.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  -- ISS-2026-302: IP allowlist, checked after authority is established and before any
  -- state change. Skipped when the caller supplies no address, and bypassable via the
  -- separately-governed app.ip_allowlist_bypass_grants -- the identical composition
  -- 20260826190000 established for the import-commit RPCs.
  if p_client_ip is not null and not app.has_active_ip_allowlist_bypass(v_rule.tenant_id, p_actor_auth_user_id) then
    perform app.assert_ip_allowed(v_rule.tenant_id, p_client_ip, 'admin', p_actor_label);
  end if;
  if v_rule.record_version <> p_expected_version then
    raise exception 'stale_version: expected version % but current version is %', p_expected_version, v_rule.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_rule.status <> 'draft' then
    raise exception 'finance_tax_rule_not_draft: rule % is % not draft', p_rule_id, v_rule.status
      using errcode = 'check_violation';
  end if;
  if v_rule.is_example_fixture then
    raise exception 'finance_tax_rule_example_fixture_not_activatable: rule % is a seeded illustrative example and can never be approved -- create a fresh evidence-backed draft', p_rule_id
      using errcode = 'check_violation';
  end if;
  if v_rule.evidence_reference_file_id is null and (v_rule.evidence_note is null or length(trim(v_rule.evidence_note)) = 0) then
    raise exception 'finance_tax_rule_evidence_missing: rule % has no attached SME evidence', p_rule_id
      using errcode = 'check_violation';
  end if;

  select count(*) into v_overlap_count
    from app.finance_tax_rule_versions r
    where r.tax_code_id = v_rule.tax_code_id
      and coalesce(r.tenant_id, '00000000-0000-0000-0000-000000000000'::uuid) = coalesce(v_rule.tenant_id, '00000000-0000-0000-0000-000000000000'::uuid)
      and r.status = 'approved'
      and r.id <> v_rule.id
      and r.effective_from <= coalesce(v_rule.effective_to, 'infinity'::date)
      and coalesce(r.effective_to, 'infinity'::date) >= v_rule.effective_from;
  if v_overlap_count > 0 then
    raise exception 'finance_tax_rule_overlap: an approved rule for this tax code and scope already covers an overlapping effective window'
      using errcode = 'check_violation';
  end if;

  update app.finance_tax_rule_versions
    set status = 'approved', approved_by = p_actor_label, approved_at = now()
    where id = p_rule_id
    returning * into v_rule;

  perform app.capture_audit_event(
    v_rule.tenant_id, p_actor_auth_user_id, p_actor_label, 'approve_finance_tax_rule',
    'app.finance_tax_rule_versions', v_rule.id, 'success', null, null, to_jsonb(v_rule)
  );

  return v_rule;
end;
$function$;

revoke execute on function app.approve_finance_tax_rule(p_rule_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) from anon, authenticated, service_role, public;
grant execute on function app.approve_finance_tax_rule(p_rule_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) to authenticated;
grant execute on function app.approve_finance_tax_rule(p_rule_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) to service_role;

create function public.approve_finance_tax_rule(p_rule_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text default null)
 RETURNS app.finance_tax_rule_versions
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
  select app.approve_finance_tax_rule(p_rule_id, p_expected_version, p_actor_auth_user_id, p_actor_label, p_client_ip);
$function$;

revoke execute on function public.approve_finance_tax_rule(p_rule_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) from anon, authenticated, service_role, public;
grant execute on function public.approve_finance_tax_rule(p_rule_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) to authenticated;
grant execute on function public.approve_finance_tax_rule(p_rule_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) to service_role;

-- 12. approve_finance_vendor_bill -- authority shape: fin, tenant expression: v_bill.tenant_id [wrapper definer flag repaired -- live had drifted to invoker]
drop function public.approve_finance_vendor_bill(p_bill_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text);
drop function app.approve_finance_vendor_bill(p_bill_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text);

create function app.approve_finance_vendor_bill(p_bill_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text default null)
 RETURNS app.finance_vendor_bills
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_bill app.finance_vendor_bills;
begin
  select * into v_bill from app.finance_vendor_bills where id = p_bill_id for update;
  if not found then
    raise exception 'finance_vendor_bill_not_found: %', p_bill_id using errcode = 'no_data_found';
  end if;
  if not app.check_finance_vendor_bill_authority('Approve', v_bill.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:Approve for tenant %', p_actor_auth_user_id, v_bill.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  -- ISS-2026-302: IP allowlist, checked after authority is established and before any
  -- state change. Skipped when the caller supplies no address, and bypassable via the
  -- separately-governed app.ip_allowlist_bypass_grants -- the identical composition
  -- 20260826190000 established for the import-commit RPCs.
  if p_client_ip is not null and not app.has_active_ip_allowlist_bypass(v_bill.tenant_id, p_actor_auth_user_id) then
    perform app.assert_ip_allowed(v_bill.tenant_id, p_client_ip, 'admin', p_actor_label);
  end if;
  if v_bill.record_version <> p_expected_version then
    raise exception 'stale_version: bill % expected version % but found %', p_bill_id, p_expected_version, v_bill.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_bill.status <> 'submitted' then
    raise exception 'finance_vendor_bill_not_submitted: bill % is % not submitted', p_bill_id, v_bill.status
      using errcode = 'check_violation';
  end if;

  update app.finance_vendor_bills set status = 'approved', approved_by = p_actor_label, approved_at = now() where id = p_bill_id returning * into v_bill;

  perform app.capture_audit_event(
    v_bill.tenant_id, p_actor_auth_user_id, p_actor_label, 'approve_finance_vendor_bill',
    'app.finance_vendor_bills', v_bill.id, 'success', null, jsonb_build_object('varianceStatus', v_bill.variance_status), to_jsonb(v_bill)
  );

  return v_bill;
end;
$function$;

revoke execute on function app.approve_finance_vendor_bill(p_bill_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) from anon, authenticated, service_role, public;
grant execute on function app.approve_finance_vendor_bill(p_bill_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) to authenticated;
grant execute on function app.approve_finance_vendor_bill(p_bill_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) to service_role;

create function public.approve_finance_vendor_bill(p_bill_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text default null)
 RETURNS app.finance_vendor_bills
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
  select app.approve_finance_vendor_bill(p_bill_id, p_expected_version, p_actor_auth_user_id, p_actor_label, p_client_ip);
$function$;

revoke execute on function public.approve_finance_vendor_bill(p_bill_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) from anon, authenticated, service_role, public;
grant execute on function public.approve_finance_vendor_bill(p_bill_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) to authenticated;
grant execute on function public.approve_finance_vendor_bill(p_bill_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) to service_role;

-- 13. approve_leave_for_payroll_input -- authority shape: eval, tenant expression: v_request.tenant_id
drop function public.approve_leave_for_payroll_input(p_request_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text);
drop function app.approve_leave_for_payroll_input(p_request_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text);

create function app.approve_leave_for_payroll_input(p_request_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text default null)
 RETURNS app.leave_requests
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_decision app.rbac_decision;
  v_request app.leave_requests;
begin
  select * into v_request from app.leave_requests where id = p_request_id for update;
  if not found or not app.has_active_tenant_membership(v_request.tenant_id, p_actor_auth_user_id) then
    raise exception 'leave_request_not_found: %', p_request_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_request.tenant_id, 'HRS', 'Approve');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks HRS:Approve (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_request.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  -- ISS-2026-302: IP allowlist, checked after authority is established and before any
  -- state change. Skipped when the caller supplies no address, and bypassable via the
  -- separately-governed app.ip_allowlist_bypass_grants -- the identical composition
  -- 20260826190000 established for the import-commit RPCs.
  if p_client_ip is not null and not app.has_active_ip_allowlist_bypass(v_request.tenant_id, p_actor_auth_user_id) then
    perform app.assert_ip_allowed(v_request.tenant_id, p_client_ip, 'admin', p_actor_label);
  end if;

  if v_request.record_version <> p_expected_version then
    raise exception 'stale_version: leave request % expected version % but found %', p_request_id, p_expected_version, v_request.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_request.status <> 'approved' then
    raise exception 'invalid_transition: leave request % is %, only an approved request may be marked ready for payroll input', p_request_id, v_request.status
      using errcode = 'check_violation';
  end if;

  update app.leave_requests set payroll_input_status = 'approved' where id = p_request_id and record_version = p_expected_version returning * into v_request;
  if not found then
    raise exception 'stale_version: leave request % target row was concurrently modified (expected version %)', p_request_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_request.tenant_id, p_actor_auth_user_id, p_actor_label, 'approve_leave_for_payroll_input',
    'app.leave_requests', v_request.id, 'success', null, null, app.leave_request_audit_projection(v_request)
  );

  return v_request;
end;
$function$;

revoke execute on function app.approve_leave_for_payroll_input(p_request_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) from anon, authenticated, service_role, public;
grant execute on function app.approve_leave_for_payroll_input(p_request_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) to authenticated;
grant execute on function app.approve_leave_for_payroll_input(p_request_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) to service_role;

create function public.approve_leave_for_payroll_input(p_request_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text default null)
 RETURNS app.leave_requests
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
  select app.approve_leave_for_payroll_input(p_request_id, p_expected_version, p_actor_auth_user_id, p_actor_label, p_client_ip);
$function$;

revoke execute on function public.approve_leave_for_payroll_input(p_request_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) from anon, authenticated, service_role, public;
grant execute on function public.approve_leave_for_payroll_input(p_request_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) to authenticated;
grant execute on function public.approve_leave_for_payroll_input(p_request_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) to service_role;

-- 14. approve_timesheet_period_summary -- authority shape: eval, tenant expression: v_summary.tenant_id
drop function public.approve_timesheet_period_summary(p_summary_id uuid, p_expected_version integer, p_reason text, p_actor_auth_user_id uuid, p_actor_label text);
drop function app.approve_timesheet_period_summary(p_summary_id uuid, p_expected_version integer, p_reason text, p_actor_auth_user_id uuid, p_actor_label text);

create function app.approve_timesheet_period_summary(p_summary_id uuid, p_expected_version integer, p_reason text, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text default null)
 RETURNS app.timesheet_period_summaries
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_summary app.timesheet_period_summaries;
  v_period app.timesheet_periods;
  v_decision app.rbac_decision;
  v_self app.employees;
begin
  select * into v_summary from app.timesheet_period_summaries where id = p_summary_id for update;
  if v_summary.id is null or not app.has_active_tenant_membership(v_summary.tenant_id, p_actor_auth_user_id) then
    raise exception 'timesheet_period_summary_not_found: %', p_summary_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_summary.tenant_id, 'HRS', 'Approve');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks HRS:Approve (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_summary.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  -- ISS-2026-302: IP allowlist, checked after authority is established and before any
  -- state change. Skipped when the caller supplies no address, and bypassable via the
  -- separately-governed app.ip_allowlist_bypass_grants -- the identical composition
  -- 20260826190000 established for the import-commit RPCs.
  if p_client_ip is not null and not app.has_active_ip_allowlist_bypass(v_summary.tenant_id, p_actor_auth_user_id) then
    perform app.assert_ip_allowed(v_summary.tenant_id, p_client_ip, 'admin', p_actor_label);
  end if;

  v_self := app.get_self_employee(v_summary.tenant_id, p_actor_auth_user_id);
  if v_self.master_record_id is not null and v_self.master_record_id = v_summary.employee_id then
    raise exception 'self_approval_not_permitted: an actor may not approve their own timesheet period summary' using errcode = 'insufficient_privilege';
  end if;

  if v_summary.record_version <> p_expected_version then
    raise exception 'stale_version: timesheet period summary % expected version % but found %', p_summary_id, p_expected_version, v_summary.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_summary.status <> 'submitted' then
    raise exception 'invalid_transition: timesheet period summary % is %, only a submitted summary may be approved', p_summary_id, v_summary.status
      using errcode = 'check_violation';
  end if;

  select * into v_period from app.timesheet_periods where id = v_summary.timesheet_period_id;
  if v_period.status <> 'open' then
    raise exception 'timesheet_period_locked: period % is locked, reopen it before deciding a summary', v_period.id using errcode = 'check_violation';
  end if;

  -- Recompute fresh, immediately before locking the figures in -- never
  -- approve a stale total (this table''s own comment). The recompute is a
  -- real UPDATE on THIS SAME row (upsert), so it advances record_version
  -- via app.touch_overtime_timesheet_row -- re-read the CURRENT version for
  -- the terminal guard below, never the caller's own, now-stale,
  -- p_expected_version (identical self-found class as app.submit_overtime_
  -- request/app.submit_timesheet_entry; the row lock held since the top
  -- SELECT ... FOR UPDATE makes this safe).
  v_summary := app._compute_timesheet_period_summary(v_summary.timesheet_period_id, v_summary.employee_id);

  update app.timesheet_period_summaries
  set status = 'approved', decided_by = p_actor_label, decided_at = now(), decided_reason = p_reason
  where id = p_summary_id and record_version = v_summary.record_version
  returning * into v_summary;
  if not found then
    raise exception 'stale_version: timesheet period summary % target row was concurrently modified (expected version %)', p_summary_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  -- Tier C batch review fix (Finding 5, HIGH, C-07): to_jsonb(v_summary)
  -- replaced with the masked projection, and p_reason no longer routed into
  -- the unredacted audit_logs.reason column -- still fully readable via
  -- app.get_timesheet_period_summary's own governed read path.
  perform app.capture_audit_event(
    v_summary.tenant_id, p_actor_auth_user_id, p_actor_label, 'approve_timesheet_period_summary',
    'app.timesheet_period_summaries', p_summary_id, 'success', null, null, app.timesheet_period_summary_audit_projection(v_summary)
  );

  return v_summary;
end;
$function$;

revoke execute on function app.approve_timesheet_period_summary(p_summary_id uuid, p_expected_version integer, p_reason text, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) from anon, authenticated, service_role, public;
grant execute on function app.approve_timesheet_period_summary(p_summary_id uuid, p_expected_version integer, p_reason text, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) to authenticated;
grant execute on function app.approve_timesheet_period_summary(p_summary_id uuid, p_expected_version integer, p_reason text, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) to service_role;

create function public.approve_timesheet_period_summary(p_summary_id uuid, p_expected_version integer, p_reason text, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text default null)
 RETURNS app.timesheet_period_summaries
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
  select app.approve_timesheet_period_summary(p_summary_id, p_expected_version, p_reason, p_actor_auth_user_id, p_actor_label, p_client_ip);
$function$;

revoke execute on function public.approve_timesheet_period_summary(p_summary_id uuid, p_expected_version integer, p_reason text, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) from anon, authenticated, service_role, public;
grant execute on function public.approve_timesheet_period_summary(p_summary_id uuid, p_expected_version integer, p_reason text, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) to authenticated;
grant execute on function public.approve_timesheet_period_summary(p_summary_id uuid, p_expected_version integer, p_reason text, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) to service_role;

-- 15. certify_finance_reconciliation_run -- authority shape: fin, tenant expression: v_run.tenant_id [wrapper definer flag repaired -- live had drifted to invoker]
drop function public.certify_finance_reconciliation_run(p_run_id uuid, p_expected_version integer, p_reason text, p_actor_auth_user_id uuid, p_actor_label text);
drop function app.certify_finance_reconciliation_run(p_run_id uuid, p_expected_version integer, p_reason text, p_actor_auth_user_id uuid, p_actor_label text);

create function app.certify_finance_reconciliation_run(p_run_id uuid, p_expected_version integer, p_reason text, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text default null)
 RETURNS app.finance_reconciliation_runs
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_run app.finance_reconciliation_runs;
  v_open_exceptions integer;
begin
  select * into v_run from app.finance_reconciliation_runs where id = p_run_id for update;
  if not found then
    raise exception 'finance_reconciliation_run_not_found: %', p_run_id using errcode = 'no_data_found';
  end if;
  if not app.check_finance_reconciliation_authority('Approve', v_run.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:Approve for tenant %', p_actor_auth_user_id, v_run.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  -- ISS-2026-302: IP allowlist, checked after authority is established and before any
  -- state change. Skipped when the caller supplies no address, and bypassable via the
  -- separately-governed app.ip_allowlist_bypass_grants -- the identical composition
  -- 20260826190000 established for the import-commit RPCs.
  if p_client_ip is not null and not app.has_active_ip_allowlist_bypass(v_run.tenant_id, p_actor_auth_user_id) then
    perform app.assert_ip_allowed(v_run.tenant_id, p_client_ip, 'admin', p_actor_label);
  end if;
  if v_run.record_version <> p_expected_version then
    raise exception 'stale_version: run % expected version % but found %', p_run_id, p_expected_version, v_run.record_version
      using errcode = 'serialization_failure';
  end if;
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'finance_reconciliation_certify_reason_required: a non-empty reason is required' using errcode = 'check_violation';
  end if;
  if v_run.status = 'certified' then
    return v_run;
  end if;

  select count(*) into v_open_exceptions from app.finance_reconciliation_exceptions where run_id = p_run_id and status = 'open';
  if v_open_exceptions > 0 then
    raise exception 'finance_reconciliation_unexplained_variance: run % has % unresolved exception(s)', p_run_id, v_open_exceptions
      using errcode = 'check_violation';
  end if;

  update app.finance_reconciliation_runs
    set status = 'certified', certify_reason = p_reason, certified_by = p_actor_label, certified_at = now()
    where id = p_run_id
    returning * into v_run;

  perform app.capture_audit_event(
    v_run.tenant_id, p_actor_auth_user_id, p_actor_label, 'certify_finance_reconciliation_run',
    'app.finance_reconciliation_runs', v_run.id, 'success', p_reason, null, to_jsonb(v_run)
  );

  return v_run;
end;
$function$;

revoke execute on function app.certify_finance_reconciliation_run(p_run_id uuid, p_expected_version integer, p_reason text, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) from anon, authenticated, service_role, public;
grant execute on function app.certify_finance_reconciliation_run(p_run_id uuid, p_expected_version integer, p_reason text, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) to authenticated;
grant execute on function app.certify_finance_reconciliation_run(p_run_id uuid, p_expected_version integer, p_reason text, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) to service_role;

create function public.certify_finance_reconciliation_run(p_run_id uuid, p_expected_version integer, p_reason text, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text default null)
 RETURNS app.finance_reconciliation_runs
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
  select app.certify_finance_reconciliation_run(p_run_id, p_expected_version, p_reason, p_actor_auth_user_id, p_actor_label, p_client_ip);
$function$;

revoke execute on function public.certify_finance_reconciliation_run(p_run_id uuid, p_expected_version integer, p_reason text, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) from anon, authenticated, service_role, public;
grant execute on function public.certify_finance_reconciliation_run(p_run_id uuid, p_expected_version integer, p_reason text, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) to authenticated;
grant execute on function public.certify_finance_reconciliation_run(p_run_id uuid, p_expected_version integer, p_reason text, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) to service_role;

-- 16. close_finance_period -- authority shape: fin, tenant expression: v_period.tenant_id [wrapper definer flag repaired -- live had drifted to invoker]
drop function public.close_finance_period(p_period_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text);
drop function app.close_finance_period(p_period_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text);

create function app.close_finance_period(p_period_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text default null)
 RETURNS app.finance_fiscal_periods
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_period app.finance_fiscal_periods;
  v_unsatisfied_count integer;
begin
  select * into v_period from app.finance_fiscal_periods where id = p_period_id;
  if not found then
    raise exception 'finance_period_not_found: %', p_period_id using errcode = 'no_data_found';
  end if;

  if v_period.record_version <> p_expected_version then
    raise exception 'stale_version: period % expected version % but found %', p_period_id, p_expected_version, v_period.record_version
      using errcode = 'serialization_failure';
  end if;

  if v_period.status <> 'soft_closed' then
    raise exception 'finance_period_not_soft_closed: period % is %, only a soft-closed period may be closed', p_period_id, v_period.status
      using errcode = 'check_violation';
  end if;

  if not app.check_finance_period_authority('Approve', v_period.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:Approve for tenant %', p_actor_auth_user_id, v_period.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  -- ISS-2026-302: IP allowlist, checked after authority is established and before any
  -- state change. Skipped when the caller supplies no address, and bypassable via the
  -- separately-governed app.ip_allowlist_bypass_grants -- the identical composition
  -- 20260826190000 established for the import-commit RPCs.
  if p_client_ip is not null and not app.has_active_ip_allowlist_bypass(v_period.tenant_id, p_actor_auth_user_id) then
    perform app.assert_ip_allowed(v_period.tenant_id, p_client_ip, 'admin', p_actor_label);
  end if;

  select count(*) into v_unsatisfied_count from app.finance_period_close_checklist_items
    where period_id = p_period_id and required and not satisfied;
  if v_unsatisfied_count > 0 then
    raise exception 'finance_period_checklist_incomplete: period % has % unsatisfied required close-checklist item(s)', p_period_id, v_unsatisfied_count
      using errcode = 'check_violation';
  end if;

  update app.finance_fiscal_periods
  set status = 'closed', closed_at = now(), closed_by = p_actor_label
  where id = p_period_id and record_version = p_expected_version
  returning * into v_period;
  -- ATW-032 (ISS-2026-034): the version predicate above already PREVENTS the lost
  -- update -- the loser's UPDATE simply matches no row. What it did not do was say so:
  -- execution fell straight through with a NULL composite, so the audit trail gained a
  -- fabricated 'success' row with a NULL tenant_id and the caller was handed an all-NULL
  -- record instead of the 'stale_version' its own error contract already handles.
  if not found then
    raise exception 'stale_version: close_finance_period target row was concurrently modified (expected version %)', p_expected_version
      using errcode = 'serialization_failure';
  end if;

  insert into app.finance_period_transitions (period_id, tenant_id, from_status, to_status, reason, actor_auth_user_id, actor_label)
  values (p_period_id, v_period.tenant_id, 'soft_closed', 'closed', null, p_actor_auth_user_id, p_actor_label);

  perform app.capture_audit_event(
    v_period.tenant_id, p_actor_auth_user_id, p_actor_label, 'close_finance_period',
    'app.finance_fiscal_periods', v_period.id, 'success', null, null, to_jsonb(v_period)
  );

  return v_period;
end;
$function$;

revoke execute on function app.close_finance_period(p_period_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) from anon, authenticated, service_role, public;
grant execute on function app.close_finance_period(p_period_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) to authenticated;
grant execute on function app.close_finance_period(p_period_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) to service_role;

create function public.close_finance_period(p_period_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text default null)
 RETURNS app.finance_fiscal_periods
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
  select app.close_finance_period(p_period_id, p_expected_version, p_actor_auth_user_id, p_actor_label, p_client_ip);
$function$;

revoke execute on function public.close_finance_period(p_period_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) from anon, authenticated, service_role, public;
grant execute on function public.close_finance_period(p_period_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) to authenticated;
grant execute on function public.close_finance_period(p_period_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) to service_role;

-- 17. create_finance_bank_account -- authority shape: fin, tenant expression: p_tenant_id [wrapper definer flag repaired -- live had drifted to invoker]
drop function public.create_finance_bank_account(p_tenant_id uuid, p_company_id uuid, p_account_name text, p_bank_name text, p_account_number_last4 text, p_currency text, p_gl_account_id uuid, p_actor_auth_user_id uuid, p_actor_label text);
drop function app.create_finance_bank_account(p_tenant_id uuid, p_company_id uuid, p_account_name text, p_bank_name text, p_account_number_last4 text, p_currency text, p_gl_account_id uuid, p_actor_auth_user_id uuid, p_actor_label text);

create function app.create_finance_bank_account(p_tenant_id uuid, p_company_id uuid, p_account_name text, p_bank_name text, p_account_number_last4 text, p_currency text, p_gl_account_id uuid, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text default null)
 RETURNS app.finance_bank_accounts
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_account app.finance_bank_accounts;
  v_gl_account app.finance_accounts;
begin
  if not app.has_active_tenant_membership(p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % holds no active membership for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.check_finance_cash_authority('Approve', p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:Approve for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  -- ISS-2026-302: IP allowlist, checked after authority is established and before any
  -- state change. Skipped when the caller supplies no address, and bypassable via the
  -- separately-governed app.ip_allowlist_bypass_grants -- the identical composition
  -- 20260826190000 established for the import-commit RPCs.
  if p_client_ip is not null and not app.has_active_ip_allowlist_bypass(p_tenant_id, p_actor_auth_user_id) then
    perform app.assert_ip_allowed(p_tenant_id, p_client_ip, 'admin', p_actor_label);
  end if;
  if not app.validate_currency_code(p_currency) then
    raise exception 'finance_cash_unsupported_currency: % is not a registered, active currency', p_currency
      using errcode = 'check_violation';
  end if;

  select * into v_gl_account from app.finance_accounts where id = p_gl_account_id and tenant_id = p_tenant_id;
  if not found then
    raise exception 'finance_cash_gl_account_not_found: % is not a known account for tenant %', p_gl_account_id, p_tenant_id
      using errcode = 'no_data_found';
  end if;
  if v_gl_account.status <> 'active' or not v_gl_account.is_postable then
    raise exception 'finance_cash_gl_account_not_postable: account % is not active/postable', v_gl_account.code
      using errcode = 'check_violation';
  end if;

  insert into app.finance_bank_accounts (tenant_id, company_id, account_name, bank_name, account_number_last4, currency, gl_account_id, created_by)
  values (p_tenant_id, p_company_id, p_account_name, p_bank_name, p_account_number_last4, p_currency, p_gl_account_id, p_actor_label)
  returning * into v_account;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'create_finance_bank_account',
    'app.finance_bank_accounts', v_account.id, 'success', null, null, to_jsonb(v_account)
  );

  return v_account;
end;
$function$;

revoke execute on function app.create_finance_bank_account(p_tenant_id uuid, p_company_id uuid, p_account_name text, p_bank_name text, p_account_number_last4 text, p_currency text, p_gl_account_id uuid, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) from anon, authenticated, service_role, public;
grant execute on function app.create_finance_bank_account(p_tenant_id uuid, p_company_id uuid, p_account_name text, p_bank_name text, p_account_number_last4 text, p_currency text, p_gl_account_id uuid, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) to authenticated;
grant execute on function app.create_finance_bank_account(p_tenant_id uuid, p_company_id uuid, p_account_name text, p_bank_name text, p_account_number_last4 text, p_currency text, p_gl_account_id uuid, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) to service_role;

create function public.create_finance_bank_account(p_tenant_id uuid, p_company_id uuid, p_account_name text, p_bank_name text, p_account_number_last4 text, p_currency text, p_gl_account_id uuid, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text default null)
 RETURNS app.finance_bank_accounts
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
  select app.create_finance_bank_account(p_tenant_id, p_company_id, p_account_name, p_bank_name, p_account_number_last4, p_currency, p_gl_account_id, p_actor_auth_user_id, p_actor_label, p_client_ip);
$function$;

revoke execute on function public.create_finance_bank_account(p_tenant_id uuid, p_company_id uuid, p_account_name text, p_bank_name text, p_account_number_last4 text, p_currency text, p_gl_account_id uuid, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) from anon, authenticated, service_role, public;
grant execute on function public.create_finance_bank_account(p_tenant_id uuid, p_company_id uuid, p_account_name text, p_bank_name text, p_account_number_last4 text, p_currency text, p_gl_account_id uuid, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) to authenticated;
grant execute on function public.create_finance_bank_account(p_tenant_id uuid, p_company_id uuid, p_account_name text, p_bank_name text, p_account_number_last4 text, p_currency text, p_gl_account_id uuid, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) to service_role;

-- 18. decide_attendance_correction -- authority shape: eval, tenant expression: v_request.tenant_id
drop function public.decide_attendance_correction(p_request_id uuid, p_expected_version integer, p_decision text, p_decided_reason text, p_actor_auth_user_id uuid, p_actor_label text);
drop function app.decide_attendance_correction(p_request_id uuid, p_expected_version integer, p_decision text, p_decided_reason text, p_actor_auth_user_id uuid, p_actor_label text);

create function app.decide_attendance_correction(p_request_id uuid, p_expected_version integer, p_decision text, p_decided_reason text, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text default null)
 RETURNS app.attendance_correction_requests
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_decision app.rbac_decision;
  v_request app.attendance_correction_requests;
  v_session app.attendance_sessions;
  v_self app.employees;
  v_new_status text;
begin
  if p_decision not in ('approve', 'reject') then
    raise exception 'invalid_decision: % is not approve or reject', p_decision using errcode = 'check_violation';
  end if;
  if p_decided_reason is null or length(trim(p_decided_reason)) = 0 then
    raise exception 'reason_required: a non-empty reason is required to decide a correction request' using errcode = 'check_violation';
  end if;

  select cr.* into v_request from app.attendance_correction_requests cr where cr.id = p_request_id for update;
  if not found or not app.has_active_tenant_membership(v_request.tenant_id, p_actor_auth_user_id) then
    raise exception 'correction_request_not_found: %', p_request_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_request.tenant_id, 'HRS', 'Approve');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks HRS:Approve (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_request.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  -- ISS-2026-302: IP allowlist, checked after authority is established and before any
  -- state change. Skipped when the caller supplies no address, and bypassable via the
  -- separately-governed app.ip_allowlist_bypass_grants -- the identical composition
  -- 20260826190000 established for the import-commit RPCs.
  if p_client_ip is not null and not app.has_active_ip_allowlist_bypass(v_request.tenant_id, p_actor_auth_user_id) then
    perform app.assert_ip_allowed(v_request.tenant_id, p_client_ip, 'admin', p_actor_label);
  end if;

  -- Self-approval is never permitted, even for an actor who happens to hold
  -- HRS:Approve (taxonomy C-18's "self-approval blocked on all transitions").
  v_self := app.get_self_employee(v_request.tenant_id, p_actor_auth_user_id);
  if v_self.master_record_id is not null and v_self.master_record_id = v_request.employee_id then
    raise exception 'self_approval_not_permitted: an actor may not decide their own attendance correction request' using errcode = 'insufficient_privilege';
  end if;

  if v_request.record_version <> p_expected_version then
    raise exception 'stale_version: correction request % expected version % but found %', p_request_id, p_expected_version, v_request.record_version
      using errcode = 'serialization_failure';
  end if;

  if v_request.status <> 'pending_approval' then
    raise exception 'invalid_transition: correction request % is %, cannot be decided', p_request_id, v_request.status
      using errcode = 'check_violation';
  end if;

  select * into v_session from app.attendance_sessions where id = v_request.session_id for update;

  v_new_status := case p_decision when 'approve' then 'approved' else 'rejected' end;

  update app.attendance_correction_requests
  set status = v_new_status, decided_by = p_actor_label, decided_at = now(), decided_reason = p_decided_reason
  where id = p_request_id and record_version = p_expected_version
  returning * into v_request;
  if not found then
    raise exception 'stale_version: correction request % target row was concurrently modified (expected version %)', p_request_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  if p_decision = 'approve' then
    if v_request.request_type in ('add_missing_clock_in', 'adjust_clock_in') then
      update app.attendance_sessions
      set corrected_clock_in_at = v_request.proposed_clock_in_at,
          raw_clock_in_at = coalesce(raw_clock_in_at, v_request.proposed_clock_in_at),
          status = case when status = 'open' or clock_out_event_id is not null then status else status end,
          payroll_input_status = 'pending', payroll_approved_by = null, payroll_approved_at = null
      where id = v_session.id;
    else
      update app.attendance_sessions
      set corrected_clock_out_at = v_request.proposed_clock_out_at,
          raw_clock_out_at = coalesce(raw_clock_out_at, v_request.proposed_clock_out_at),
          status = 'closed',
          clock_out_event_id = coalesce(clock_out_event_id, clock_in_event_id),
          payroll_input_status = 'pending', payroll_approved_by = null, payroll_approved_at = null
      where id = v_session.id;
    end if;

    if v_request.linked_exception_id is not null then
      update app.attendance_exceptions
      set status = 'resolved', resolved_at = now(), resolved_by = p_actor_label, resolution_note = 'resolved by approved correction ' || p_request_id::text
      where id = v_request.linked_exception_id and status in ('open', 'acknowledged');
    end if;

    perform app._recalculate_session_exceptions(v_session.id);
  else
    -- decision 9: rejecting never leaves the linked exception silently
    -- implying resolution is in flight.
    if v_request.linked_exception_id is not null then
      update app.attendance_exceptions set status = 'open'
      where id = v_request.linked_exception_id and status = 'open';
    end if;
  end if;

  -- HRT-293 Finding B fix (CRITICAL, C-24): p_decided_reason is already
  -- durably stored above in app.attendance_correction_requests.
  -- decided_reason (HRS_REGISTRY hrs:attendance_correction_requests.reason,
  -- column-restricted) -- never also duplicated into app.audit_logs.reason.
  perform app.capture_audit_event(
    v_request.tenant_id, p_actor_auth_user_id, p_actor_label, 'decide_attendance_correction',
    'app.attendance_correction_requests', p_request_id, 'success', null, null, jsonb_build_object('decision', p_decision)
  );

  return v_request;
end;
$function$;

revoke execute on function app.decide_attendance_correction(p_request_id uuid, p_expected_version integer, p_decision text, p_decided_reason text, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) from anon, authenticated, service_role, public;
grant execute on function app.decide_attendance_correction(p_request_id uuid, p_expected_version integer, p_decision text, p_decided_reason text, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) to authenticated;
grant execute on function app.decide_attendance_correction(p_request_id uuid, p_expected_version integer, p_decision text, p_decided_reason text, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) to service_role;

create function public.decide_attendance_correction(p_request_id uuid, p_expected_version integer, p_decision text, p_decided_reason text, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text default null)
 RETURNS app.attendance_correction_requests
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
  select app.decide_attendance_correction(p_request_id, p_expected_version, p_decision, p_decided_reason, p_actor_auth_user_id, p_actor_label, p_client_ip);
$function$;

revoke execute on function public.decide_attendance_correction(p_request_id uuid, p_expected_version integer, p_decision text, p_decided_reason text, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) from anon, authenticated, service_role, public;
grant execute on function public.decide_attendance_correction(p_request_id uuid, p_expected_version integer, p_decision text, p_decided_reason text, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) to authenticated;
grant execute on function public.decide_attendance_correction(p_request_id uuid, p_expected_version integer, p_decision text, p_decided_reason text, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) to service_role;

-- 19. decide_employee_position_assignment -- authority shape: eval, tenant expression: v_assignment.tenant_id
drop function public.decide_employee_position_assignment(p_assignment_id uuid, p_expected_version integer, p_decision text, p_reason text, p_actor_auth_user_id uuid, p_actor_label text);
drop function app.decide_employee_position_assignment(p_assignment_id uuid, p_expected_version integer, p_decision text, p_reason text, p_actor_auth_user_id uuid, p_actor_label text);

create function app.decide_employee_position_assignment(p_assignment_id uuid, p_expected_version integer, p_decision text, p_reason text, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text default null)
 RETURNS app.employee_position_assignments
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_decision app.rbac_decision;
  v_assignment app.employee_position_assignments;
  v_employee app.employees;
  v_position app.positions;
  v_predecessor app.employee_position_assignments;
  v_predecessor_found boolean;
  v_headcount integer;
  v_lock_key bigint;
begin
  if p_decision not in ('approve', 'reject') then
    raise exception 'invalid_decision: % is not approve or reject', p_decision using errcode = 'check_violation';
  end if;
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'reason_required: a non-empty reason is required to decide an assignment proposal' using errcode = 'check_violation';
  end if;

  select * into v_assignment from app.employee_position_assignments where id = p_assignment_id for update;
  if not found or not app.has_active_tenant_membership(v_assignment.tenant_id, p_actor_auth_user_id) then
    raise exception 'assignment_not_found: %', p_assignment_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_assignment.tenant_id, 'HRS', 'Approve');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks HRS:Approve (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_assignment.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  -- ISS-2026-302: IP allowlist, checked after authority is established and before any
  -- state change. Skipped when the caller supplies no address, and bypassable via the
  -- separately-governed app.ip_allowlist_bypass_grants -- the identical composition
  -- 20260826190000 established for the import-commit RPCs.
  if p_client_ip is not null and not app.has_active_ip_allowlist_bypass(v_assignment.tenant_id, p_actor_auth_user_id) then
    perform app.assert_ip_allowed(v_assignment.tenant_id, p_client_ip, 'admin', p_actor_label);
  end if;

  if v_assignment.record_version <> p_expected_version then
    raise exception 'stale_version: assignment % expected version % but found %', p_assignment_id, p_expected_version, v_assignment.record_version
      using errcode = 'serialization_failure';
  end if;

  if v_assignment.status <> 'pending_approval' then
    raise exception 'assignment_not_pending: assignment % is % and cannot be decided', p_assignment_id, v_assignment.status
      using errcode = 'check_violation';
  end if;

  if p_decision = 'reject' then
    update app.employee_position_assignments
    set status = 'rejected', decided_by = p_actor_label, decided_at = now(), decided_reason = p_reason
    where id = p_assignment_id and record_version = p_expected_version
    returning * into v_assignment;
    if not found then
      raise exception 'stale_version: assignment % target row was concurrently modified (expected version %)', p_assignment_id, p_expected_version
        using errcode = 'serialization_failure';
    end if;

    -- HRT-293 Finding B fix (self-found, CRITICAL, C-24): p_reason is
    -- already durably stored above in app.employee_position_assignments.
    -- decided_reason -- never also duplicated into app.audit_logs.reason.
    perform app.capture_audit_event(
      v_assignment.tenant_id, p_actor_auth_user_id, p_actor_label, 'decide_employee_position_assignment',
      'app.employee_position_assignments', v_assignment.id, 'success', null, null, app.employee_position_assignment_audit_projection(v_assignment)
    );
    return v_assignment;
  end if;

  -- Approve path (decisions 7, 8: capacity + cycle re-checked authoritatively here).
  select * into v_employee from app.employees where master_record_id = v_assignment.master_record_id for update;
  select * into v_position from app.positions where id = v_assignment.position_id;

  if v_position.status <> 'active' then
    raise exception 'position_inactive: position % is inactive and cannot be activated', v_assignment.position_id using errcode = 'check_violation';
  end if;

  if v_assignment.manager_employee_id is not null and app.would_create_employee_manager_cycle(v_assignment.master_record_id, v_assignment.manager_employee_id) then
    raise exception 'cyclic_reporting_line: approving assignment % would create a cyclic reporting line', p_assignment_id
      using errcode = 'check_violation';
  end if;

  if v_assignment.assignment_type = 'primary' then
    -- Position-scoped advisory lock (mirrors app.commit_vendor_rate_import_job's own
    -- job-scoped-advisory-lock precedent) -- serializes concurrent approvals against
    -- the SAME position's capacity so two racing approvals cannot both pass the
    -- count check before either commits.
    v_lock_key := hashtextextended('employee_position_assignments:position:' || v_assignment.position_id::text, 0);
    perform pg_advisory_xact_lock(v_lock_key);

    -- Predecessor lookup happens BEFORE the capacity check (not after, as a naive
    -- reading of "close predecessor, then check capacity" would do) so that a
    -- same-position correction/promotion -- which closes the employee's own existing
    -- occupancy of THIS SAME position and immediately replaces it -- does not
    -- double-count that soon-to-be-closed predecessor against the position's own
    -- capacity. A predecessor at a DIFFERENT position is never excluded (a genuine
    -- transfer away from one position and into another must be capacity-checked at
    -- the destination without any special-casing).
    select * into v_predecessor
    from app.employee_position_assignments
    where master_record_id = v_assignment.master_record_id and assignment_type = 'primary' and status = 'active' and effective_end_date is null
    for update;
    v_predecessor_found := found;

    v_headcount := app.count_position_active_primary_headcount(
      v_assignment.position_id, v_assignment.validity_range,
      case when v_predecessor_found and v_predecessor.position_id = v_assignment.position_id then v_predecessor.id else null end
    );
    if v_headcount >= v_position.capacity then
      raise exception 'position_over_capacity: position % has % of % capacity slot(s) already committed for this date range', v_assignment.position_id, v_headcount, v_position.capacity
        using errcode = 'check_violation';
    end if;

    -- Close the currently open-ended primary predecessor (if any) BEFORE flipping
    -- this row to active, so the EXCLUDE constraint below sees a non-overlapping
    -- state -- exactly PRC-255's own established ordering.
    if v_predecessor_found then
      if v_assignment.effective_start_date <= v_predecessor.effective_start_date then
        raise exception 'invalid_effective_range: new assignment must start after the current assignment''s own start date (%)', v_predecessor.effective_start_date
          using errcode = 'check_violation';
      end if;
      update app.employee_position_assignments
      set effective_end_date = v_assignment.effective_start_date - 1
      where id = v_predecessor.id;
    end if;
  end if;

  begin
    update app.employee_position_assignments
    set status = 'active', decided_by = p_actor_label, decided_at = now(), decided_reason = p_reason,
        previous_assignment_id = coalesce(previous_assignment_id, v_predecessor.id)
    where id = p_assignment_id and record_version = p_expected_version
    returning * into v_assignment;
  exception
    when exclusion_violation then
      raise exception 'assignment_overlap: an active % assignment already exists for this employee/position with an overlapping effective range', v_assignment.assignment_type
        using errcode = 'check_violation';
    when deadlock_detected then
      raise exception 'assignment_overlap: a concurrent decision on an overlapping assignment could not be serialized -- retry'
        using errcode = 'check_violation';
  end;
  if not found then
    raise exception 'stale_version: assignment % target row was concurrently modified (expected version %)', p_assignment_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  insert into app.employee_lifecycle_events (tenant_id, master_record_id, from_status, to_status, reason, metadata, actor_auth_user_id, actor_label)
  values (
    v_employee.tenant_id, v_employee.master_record_id, v_employee.lifecycle_status, v_employee.lifecycle_status, p_reason,
    jsonb_build_object('event', 'position_assignment', 'assignment_id', v_assignment.id, 'position_id', v_assignment.position_id, 'assignment_type', v_assignment.assignment_type, 'change_reason', v_assignment.change_reason, 'effective_start_date', v_assignment.effective_start_date),
    p_actor_auth_user_id, p_actor_label
  );

  -- Immediate sync only if already, or newly, in effect -- a future-dated approved
  -- assignment is left for app.activate_due_employee_position_assignments once its
  -- date arrives (decision 4).
  if v_assignment.effective_start_date <= current_date then
    perform app.sync_employee_current_assignment_cache(v_assignment);
  end if;

  -- HRT-293 Finding B fix (self-found, CRITICAL, C-24) -- see the reject
  -- branch above.
  perform app.capture_audit_event(
    v_assignment.tenant_id, p_actor_auth_user_id, p_actor_label, 'decide_employee_position_assignment',
    'app.employee_position_assignments', v_assignment.id, 'success', null, null, app.employee_position_assignment_audit_projection(v_assignment)
  );

  return v_assignment;
end;
$function$;

revoke execute on function app.decide_employee_position_assignment(p_assignment_id uuid, p_expected_version integer, p_decision text, p_reason text, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) from anon, authenticated, service_role, public;
grant execute on function app.decide_employee_position_assignment(p_assignment_id uuid, p_expected_version integer, p_decision text, p_reason text, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) to authenticated;
grant execute on function app.decide_employee_position_assignment(p_assignment_id uuid, p_expected_version integer, p_decision text, p_reason text, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) to service_role;

create function public.decide_employee_position_assignment(p_assignment_id uuid, p_expected_version integer, p_decision text, p_reason text, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text default null)
 RETURNS app.employee_position_assignments
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
  select app.decide_employee_position_assignment(p_assignment_id, p_expected_version, p_decision, p_reason, p_actor_auth_user_id, p_actor_label, p_client_ip);
$function$;

revoke execute on function public.decide_employee_position_assignment(p_assignment_id uuid, p_expected_version integer, p_decision text, p_reason text, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) from anon, authenticated, service_role, public;
grant execute on function public.decide_employee_position_assignment(p_assignment_id uuid, p_expected_version integer, p_decision text, p_reason text, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) to authenticated;
grant execute on function public.decide_employee_position_assignment(p_assignment_id uuid, p_expected_version integer, p_decision text, p_reason text, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) to service_role;

-- 20. decide_overtime_request -- authority shape: eval, tenant expression: v_request.tenant_id
drop function public.decide_overtime_request(p_request_id uuid, p_expected_version integer, p_decision text, p_decided_reason text, p_approved_minutes_override integer, p_actor_auth_user_id uuid, p_actor_label text);
drop function app.decide_overtime_request(p_request_id uuid, p_expected_version integer, p_decision text, p_decided_reason text, p_approved_minutes_override integer, p_actor_auth_user_id uuid, p_actor_label text);

create function app.decide_overtime_request(p_request_id uuid, p_expected_version integer, p_decision text, p_decided_reason text, p_approved_minutes_override integer, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text default null)
 RETURNS app.overtime_requests
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_rbac app.rbac_decision;
  v_override_rbac app.rbac_decision;
  v_request app.overtime_requests;
  v_self app.employees;
  v_employee app.employees;
  v_policy app.overtime_policy_versions;
  v_pre_round integer;
  v_eligible integer;
  v_classification text;
  v_approved integer;
  v_week_key text;
  v_week_sum integer;
  v_remaining integer;
begin
  if p_decision not in ('approve', 'reject') then
    raise exception 'invalid_decision: % is not approve or reject', p_decision using errcode = 'check_violation';
  end if;
  if p_decided_reason is null or length(trim(p_decided_reason)) = 0 then
    raise exception 'reason_required: a non-empty reason is required to decide an overtime request' using errcode = 'check_violation';
  end if;

  select * into v_request from app.overtime_requests where id = p_request_id for update;
  if not found or not app.has_active_tenant_membership(v_request.tenant_id, p_actor_auth_user_id) then
    raise exception 'overtime_request_not_found: %', p_request_id using errcode = 'no_data_found';
  end if;

  v_rbac := app.evaluate_permission(p_actor_auth_user_id, v_request.tenant_id, 'HRS', 'Approve');
  if not v_rbac.allowed then
    raise exception 'insufficient_authority: identity % lacks HRS:Approve (%) for tenant %', p_actor_auth_user_id, v_rbac.reason, v_request.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  -- ISS-2026-302: IP allowlist, checked after authority is established and before any
  -- state change. Skipped when the caller supplies no address, and bypassable via the
  -- separately-governed app.ip_allowlist_bypass_grants -- the identical composition
  -- 20260826190000 established for the import-commit RPCs.
  if p_client_ip is not null and not app.has_active_ip_allowlist_bypass(v_request.tenant_id, p_actor_auth_user_id) then
    perform app.assert_ip_allowed(v_request.tenant_id, p_client_ip, 'admin', p_actor_label);
  end if;

  -- C-18: self-approval never permitted, even for an actor who also holds
  -- HRS:Approve.
  v_self := app.get_self_employee(v_request.tenant_id, p_actor_auth_user_id);
  if v_self.master_record_id is not null and v_self.master_record_id = v_request.employee_id then
    raise exception 'self_approval_not_permitted: an actor may not decide their own overtime request' using errcode = 'insufficient_privilege';
  end if;

  if v_request.record_version <> p_expected_version then
    raise exception 'stale_version: overtime request % expected version % but found %', p_request_id, p_expected_version, v_request.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_request.status <> 'pending_approval' then
    raise exception 'invalid_transition: overtime request % is %, cannot be decided', p_request_id, v_request.status
      using errcode = 'check_violation';
  end if;

  select * into v_employee from app.employees where master_record_id = v_request.employee_id;
  if app.is_timesheet_period_locked(v_request.tenant_id, v_employee.branch_org_unit_id, v_request.work_date) then
    raise exception 'timesheet_period_locked: the period covering % is locked -- ask HR to reopen it first', v_request.work_date
      using errcode = 'check_violation';
  end if;

  if p_decision = 'approve' then
    -- Decision 3/16: refresh reconciliation with the freshest evidence
    -- available at decide time, then hard-block on missing/mismatched
    -- attendance evidence unless the decider also holds HRS:Override
    -- (exception flow, section 23).
    v_request := app._reconcile_overtime_request_actual(p_request_id);

    if v_request.reconciliation_status in ('no_attendance', 'mismatch') then
      v_override_rbac := app.evaluate_permission(p_actor_auth_user_id, v_request.tenant_id, 'HRS', 'Override');
      if not v_override_rbac.allowed then
        raise exception 'attendance_evidence_required: reconciliation status is % -- approving without matching attendance evidence requires HRS:Override (%)', v_request.reconciliation_status, v_override_rbac.reason
          using errcode = 'insufficient_privilege';
      end if;
    end if;

    -- v_policy.id is checked directly, never the bare FOUND special
    -- variable (the reconcile call immediately above already overwrote it) --
    -- the exact class HRT-279's own self-found defect #3 established.
    select * into v_policy from app.overtime_policy_versions where id = v_request.policy_version_id;
    if v_policy.id is null then
      select * into v_policy from app.resolve_effective_overtime_policy_version(v_request.tenant_id, v_employee.branch_org_unit_id, v_request.work_date) limit 1;
      if v_policy.id is null then
        raise exception 'no_eligible_policy: no published overtime policy is effective for employee % as of %', v_request.employee_id, v_request.work_date
          using errcode = 'check_violation';
      end if;
    end if;

    v_pre_round := greatest(0, coalesce(v_request.reconciled_actual_minutes, v_request.requested_minutes) - v_request.unpaid_break_minutes);

    if v_pre_round < v_policy.min_overtime_minutes then
      v_eligible := 0;
    else
      v_eligible := app.round_minutes(v_pre_round, v_policy.rounding_increment_minutes, v_policy.rounding_mode);

      if v_policy.daily_overtime_cap_minutes is not null then
        v_eligible := least(v_eligible, v_policy.daily_overtime_cap_minutes);
      end if;

      if v_policy.weekly_overtime_cap_minutes is not null then
        -- Decision 9: advisory-lock-serialized weekly-cap enforcement -- the
        -- structural safety net closing the real concurrent-approval race
        -- this task's own workflow instructions name explicitly. Keyed on
        -- (tenant, employee, ISO year-week), mirrors app.decide_leave_
        -- request's own pg_advisory_xact_lock shape (HRT-280 decision 4/9).
        v_week_key := v_request.tenant_id::text || ':' || v_request.employee_id::text || ':' || to_char(v_request.work_date, 'IYYY-IW');
        perform pg_advisory_xact_lock(hashtextextended(v_week_key, 281));

        select coalesce(sum(o.eligible_minutes), 0) into v_week_sum
        from app.overtime_requests o
        where o.tenant_id = v_request.tenant_id and o.employee_id = v_request.employee_id and o.status = 'approved'
          and o.id <> v_request.id
          and to_char(o.work_date, 'IYYY-IW') = to_char(v_request.work_date, 'IYYY-IW');

        v_remaining := greatest(0, v_policy.weekly_overtime_cap_minutes - v_week_sum);
        v_eligible := least(v_eligible, v_remaining);
      end if;
    end if;

    v_classification := app.classify_overtime_work_date(v_request.tenant_id, v_employee.branch_org_unit_id, v_request.work_date);

    v_approved := coalesce(p_approved_minutes_override, v_eligible);
    if v_approved < 0 or v_approved > v_eligible then
      raise exception 'invalid_approved_minutes: approved_minutes % must be between 0 and the eligible figure of %', v_approved, v_eligible
        using errcode = 'check_violation';
    end if;

    -- v_request.record_version is used here, never the caller's own
    -- p_expected_version -- the approve branch's own reconcile call above
    -- already advanced it (same self-found class as app.submit_overtime_
    -- request). The reject branch never touches the row before this point,
    -- so v_request.record_version there still equals p_expected_version
    -- exactly -- one uniform guard shape, safe in both branches, since the
    -- row lock held since the top SELECT ... FOR UPDATE rules out any
    -- external race in between.
    update app.overtime_requests
    set status = 'approved', decided_by = p_actor_label, decided_at = now(), decided_reason = p_decided_reason,
        eligible_minutes = v_eligible, eligible_classification = v_classification, approved_minutes = v_approved, payroll_input_status = 'pending'
    where id = p_request_id and record_version = v_request.record_version
    returning * into v_request;
  else
    update app.overtime_requests
    set status = 'rejected', decided_by = p_actor_label, decided_at = now(), decided_reason = p_decided_reason
    where id = p_request_id and record_version = v_request.record_version
    returning * into v_request;
  end if;
  if not found then
    raise exception 'stale_version: overtime request % target row was concurrently modified (expected version %)', p_request_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  -- Tier C batch review fix (Finding 5, HIGH, C-07): decided_reason no
  -- longer routed into capture_audit_event's unredacted p_reason column --
  -- still fully readable through app.get_overtime_request_detail's own
  -- governed, permission-scoped read path.
  perform app.capture_audit_event(
    v_request.tenant_id, p_actor_auth_user_id, p_actor_label, 'decide_overtime_request',
    'app.overtime_requests', p_request_id, 'success', null, null, jsonb_build_object('decision', p_decision, 'eligible_minutes', v_request.eligible_minutes, 'approved_minutes', v_request.approved_minutes)
  );

  return v_request;
end;
$function$;

revoke execute on function app.decide_overtime_request(p_request_id uuid, p_expected_version integer, p_decision text, p_decided_reason text, p_approved_minutes_override integer, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) from anon, authenticated, service_role, public;
grant execute on function app.decide_overtime_request(p_request_id uuid, p_expected_version integer, p_decision text, p_decided_reason text, p_approved_minutes_override integer, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) to authenticated;
grant execute on function app.decide_overtime_request(p_request_id uuid, p_expected_version integer, p_decision text, p_decided_reason text, p_approved_minutes_override integer, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) to service_role;

create function public.decide_overtime_request(p_request_id uuid, p_expected_version integer, p_decision text, p_decided_reason text, p_approved_minutes_override integer, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text default null)
 RETURNS app.overtime_requests
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
  select app.decide_overtime_request(p_request_id, p_expected_version, p_decision, p_decided_reason, p_approved_minutes_override, p_actor_auth_user_id, p_actor_label, p_client_ip);
$function$;

revoke execute on function public.decide_overtime_request(p_request_id uuid, p_expected_version integer, p_decision text, p_decided_reason text, p_approved_minutes_override integer, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) from anon, authenticated, service_role, public;
grant execute on function public.decide_overtime_request(p_request_id uuid, p_expected_version integer, p_decision text, p_decided_reason text, p_approved_minutes_override integer, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) to authenticated;
grant execute on function public.decide_overtime_request(p_request_id uuid, p_expected_version integer, p_decision text, p_decided_reason text, p_approved_minutes_override integer, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) to service_role;

-- 21. decide_schedule_swap_request -- authority shape: eval, tenant expression: v_peek.tenant_id
drop function public.decide_schedule_swap_request(p_request_id uuid, p_expected_version integer, p_decision text, p_decided_reason text, p_actor_auth_user_id uuid, p_actor_label text);
drop function app.decide_schedule_swap_request(p_request_id uuid, p_expected_version integer, p_decision text, p_decided_reason text, p_actor_auth_user_id uuid, p_actor_label text);

create function app.decide_schedule_swap_request(p_request_id uuid, p_expected_version integer, p_decision text, p_decided_reason text, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text default null)
 RETURNS app.schedule_swap_requests
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_decision app.rbac_decision;
  v_peek app.schedule_swap_requests;
  v_request app.schedule_swap_requests;
  v_self app.employees;
  v_lo uuid;
  v_hi uuid;
  v_lock_lo app.schedule_assignments;
  v_lock_hi app.schedule_assignments;
  v_assignment app.schedule_assignments;
  v_target_assignment app.schedule_assignments;
  v_new_status text;
begin
  if p_decision not in ('approve', 'reject') then
    raise exception 'invalid_decision: % is not approve or reject', p_decision using errcode = 'check_violation';
  end if;
  if p_decided_reason is null or length(trim(p_decided_reason)) = 0 then
    raise exception 'reason_required: a non-empty reason is required to decide a swap request' using errcode = 'check_violation';
  end if;

  -- decision 7: PLAIN unlocked read first, only to discover which two
  -- assignment ids to lock (mirrors HRT-276 section 12.4's own
  -- "plain-read-before-lock" precedent) -- never a lock taken on the swap
  -- request row before the assignment rows, matching app.cancel_schedule_
  -- assignment's own assignment-before-swap-request order exactly.
  select * into v_peek from app.schedule_swap_requests where id = p_request_id;
  if not found or not app.has_active_tenant_membership(v_peek.tenant_id, p_actor_auth_user_id) then
    raise exception 'schedule_swap_request_not_found: %', p_request_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_peek.tenant_id, 'HRS', 'Approve');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks HRS:Approve (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_peek.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  -- ISS-2026-302: IP allowlist, checked after authority is established and before any
  -- state change. Skipped when the caller supplies no address, and bypassable via the
  -- separately-governed app.ip_allowlist_bypass_grants -- the identical composition
  -- 20260826190000 established for the import-commit RPCs.
  if p_client_ip is not null and not app.has_active_ip_allowlist_bypass(v_peek.tenant_id, p_actor_auth_user_id) then
    perform app.assert_ip_allowed(v_peek.tenant_id, p_client_ip, 'admin', p_actor_label);
  end if;

  -- Self-approval is never permitted for EITHER participant (C-18), even for
  -- an actor who happens to also hold HRS:Approve.
  v_self := app.get_self_employee(v_peek.tenant_id, p_actor_auth_user_id);
  if v_self.master_record_id is not null and v_self.master_record_id in (v_peek.requesting_employee_id, v_peek.target_employee_id) then
    raise exception 'self_approval_not_permitted: an actor may not decide a swap request they are a party to' using errcode = 'insufficient_privilege';
  end if;

  -- Global ascending-uuid lock order on the two assignment rows -- deadlock-
  -- safe against another concurrent decide call on an overlapping pair.
  v_lo := least(v_peek.assignment_id, v_peek.target_assignment_id);
  v_hi := greatest(v_peek.assignment_id, v_peek.target_assignment_id);
  select * into v_lock_lo from app.schedule_assignments where id = v_lo for update;
  select * into v_lock_hi from app.schedule_assignments where id = v_hi for update;

  if v_lock_lo.id = v_peek.assignment_id then
    v_assignment := v_lock_lo; v_target_assignment := v_lock_hi;
  else
    v_assignment := v_lock_hi; v_target_assignment := v_lock_lo;
  end if;

  -- NOW lock and re-validate the swap request row itself, under the SAME
  -- (assignment-then-swap-request) global order every other function in this
  -- migration uses.
  select * into v_request from app.schedule_swap_requests where id = p_request_id for update;

  if v_request.record_version <> p_expected_version then
    raise exception 'stale_version: swap request % expected version % but found %', p_request_id, p_expected_version, v_request.record_version
      using errcode = 'serialization_failure';
  end if;

  if v_request.status <> 'pending_approval' then
    raise exception 'invalid_transition: swap request % is %, cannot be decided', p_request_id, v_request.status
      using errcode = 'check_violation';
  end if;

  v_new_status := case p_decision when 'approve' then 'approved' else 'rejected' end;

  update app.schedule_swap_requests
  set status = v_new_status, decided_by = p_actor_label, decided_at = now(), decided_reason = p_decided_reason
  where id = p_request_id and record_version = p_expected_version
  returning * into v_request;
  if not found then
    raise exception 'stale_version: swap request % target row was concurrently modified (expected version %)', p_request_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  if p_decision = 'approve' then
    if v_assignment.status <> 'published' or v_target_assignment.status <> 'published' then
      raise exception 'invalid_transition: both assignments must still be published to complete a swap (revalidated at decision time)' using errcode = 'check_violation';
    end if;
    if not exists (select 1 from app.employees where master_record_id = v_request.requesting_employee_id and lifecycle_status = 'active')
       or not exists (select 1 from app.employees where master_record_id = v_request.target_employee_id and lifecycle_status = 'active') then
      raise exception 'employee_not_active: both employees must be active to complete a swap' using errcode = 'check_violation';
    end if;

    -- Two sequential UPDATEs are safe here: the partial unique index
    -- guarantees at most one active/published row per (employee, work_date),
    -- so each target tuple below is provably free the instant the OTHER
    -- row's own tuple has moved off it (or was never colliding).
    update app.schedule_assignments set employee_id = v_target_assignment.employee_id where id = v_assignment.id;
    update app.schedule_assignments set employee_id = v_assignment.employee_id where id = v_target_assignment.id;
  end if;

  -- HRT-293 Finding B fix (CRITICAL, C-24): p_decided_reason is already
  -- durably stored above in app.schedule_swap_requests.decided_reason
  -- (HRS_REGISTRY hrs:schedule_swap_requests.reason, column-restricted) --
  -- never also duplicated into app.audit_logs.reason.
  perform app.capture_audit_event(
    v_request.tenant_id, p_actor_auth_user_id, p_actor_label, 'decide_schedule_swap_request',
    'app.schedule_swap_requests', p_request_id, 'success', null, null, jsonb_build_object('decision', p_decision)
  );

  return v_request;
end;
$function$;

revoke execute on function app.decide_schedule_swap_request(p_request_id uuid, p_expected_version integer, p_decision text, p_decided_reason text, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) from anon, authenticated, service_role, public;
grant execute on function app.decide_schedule_swap_request(p_request_id uuid, p_expected_version integer, p_decision text, p_decided_reason text, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) to authenticated;
grant execute on function app.decide_schedule_swap_request(p_request_id uuid, p_expected_version integer, p_decision text, p_decided_reason text, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) to service_role;

create function public.decide_schedule_swap_request(p_request_id uuid, p_expected_version integer, p_decision text, p_decided_reason text, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text default null)
 RETURNS app.schedule_swap_requests
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
  select app.decide_schedule_swap_request(p_request_id, p_expected_version, p_decision, p_decided_reason, p_actor_auth_user_id, p_actor_label, p_client_ip);
$function$;

revoke execute on function public.decide_schedule_swap_request(p_request_id uuid, p_expected_version integer, p_decision text, p_decided_reason text, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) from anon, authenticated, service_role, public;
grant execute on function public.decide_schedule_swap_request(p_request_id uuid, p_expected_version integer, p_decision text, p_decided_reason text, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) to authenticated;
grant execute on function public.decide_schedule_swap_request(p_request_id uuid, p_expected_version integer, p_decision text, p_decided_reason text, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) to service_role;

-- 22. decide_timesheet_entry -- authority shape: eval, tenant expression: v_entry.tenant_id
drop function public.decide_timesheet_entry(p_entry_id uuid, p_expected_version integer, p_decision text, p_decided_reason text, p_approved_minutes_override integer, p_actor_auth_user_id uuid, p_actor_label text);
drop function app.decide_timesheet_entry(p_entry_id uuid, p_expected_version integer, p_decision text, p_decided_reason text, p_approved_minutes_override integer, p_actor_auth_user_id uuid, p_actor_label text);

create function app.decide_timesheet_entry(p_entry_id uuid, p_expected_version integer, p_decision text, p_decided_reason text, p_approved_minutes_override integer, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text default null)
 RETURNS app.timesheet_entries
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_rbac app.rbac_decision;
  v_entry app.timesheet_entries;
  v_self app.employees;
  v_employee app.employees;
  v_policy app.overtime_policy_versions;
  v_pre_round integer;
  v_eligible integer;
  v_approved integer;
begin
  if p_decision not in ('approve', 'reject') then
    raise exception 'invalid_decision: % is not approve or reject', p_decision using errcode = 'check_violation';
  end if;
  if p_decided_reason is null or length(trim(p_decided_reason)) = 0 then
    raise exception 'reason_required: a non-empty reason is required to decide a timesheet entry' using errcode = 'check_violation';
  end if;

  select * into v_entry from app.timesheet_entries where id = p_entry_id for update;
  if not found or not app.has_active_tenant_membership(v_entry.tenant_id, p_actor_auth_user_id) then
    raise exception 'timesheet_entry_not_found: %', p_entry_id using errcode = 'no_data_found';
  end if;

  v_rbac := app.evaluate_permission(p_actor_auth_user_id, v_entry.tenant_id, 'HRS', 'Approve');
  if not v_rbac.allowed then
    raise exception 'insufficient_authority: identity % lacks HRS:Approve (%) for tenant %', p_actor_auth_user_id, v_rbac.reason, v_entry.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  -- ISS-2026-302: IP allowlist, checked after authority is established and before any
  -- state change. Skipped when the caller supplies no address, and bypassable via the
  -- separately-governed app.ip_allowlist_bypass_grants -- the identical composition
  -- 20260826190000 established for the import-commit RPCs.
  if p_client_ip is not null and not app.has_active_ip_allowlist_bypass(v_entry.tenant_id, p_actor_auth_user_id) then
    perform app.assert_ip_allowed(v_entry.tenant_id, p_client_ip, 'admin', p_actor_label);
  end if;

  v_self := app.get_self_employee(v_entry.tenant_id, p_actor_auth_user_id);
  if v_self.master_record_id is not null and v_self.master_record_id = v_entry.employee_id then
    raise exception 'self_approval_not_permitted: an actor may not decide their own timesheet entry' using errcode = 'insufficient_privilege';
  end if;

  if v_entry.record_version <> p_expected_version then
    raise exception 'stale_version: timesheet entry % expected version % but found %', p_entry_id, p_expected_version, v_entry.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_entry.status <> 'pending_approval' then
    raise exception 'invalid_transition: timesheet entry % is %, cannot be decided', p_entry_id, v_entry.status
      using errcode = 'check_violation';
  end if;

  select * into v_employee from app.employees where master_record_id = v_entry.employee_id;
  if app.is_timesheet_period_locked(v_entry.tenant_id, v_employee.branch_org_unit_id, v_entry.work_date) then
    raise exception 'timesheet_period_locked: the period covering % is locked -- ask HR to reopen it first', v_entry.work_date
      using errcode = 'check_violation';
  end if;

  if p_decision = 'approve' then
    select * into v_policy from app.overtime_policy_versions where id = v_entry.policy_version_id;
    if v_policy.id is null then
      select * into v_policy from app.resolve_effective_overtime_policy_version(v_entry.tenant_id, v_employee.branch_org_unit_id, v_entry.work_date) limit 1;
      if v_policy.id is null then
        raise exception 'no_eligible_policy: no published overtime/timesheet policy is effective for employee % as of %', v_entry.employee_id, v_entry.work_date
          using errcode = 'check_violation';
      end if;
    end if;

    v_pre_round := greatest(0, v_entry.entry_minutes - v_entry.unpaid_break_minutes);
    v_eligible := app.round_minutes(v_pre_round, v_policy.rounding_increment_minutes, v_policy.rounding_mode);

    v_approved := coalesce(p_approved_minutes_override, v_eligible);
    if v_approved < 0 or v_approved > v_eligible then
      raise exception 'invalid_approved_minutes: approved_minutes % must be between 0 and the eligible figure of %', v_approved, v_eligible
        using errcode = 'check_violation';
    end if;

    update app.timesheet_entries
    set status = 'approved', decided_by = p_actor_label, decided_at = now(), decided_reason = p_decided_reason,
        eligible_minutes = v_eligible, approved_minutes = v_approved, payroll_input_status = 'pending'
    where id = p_entry_id and record_version = p_expected_version
    returning * into v_entry;
  else
    update app.timesheet_entries
    set status = 'rejected', decided_by = p_actor_label, decided_at = now(), decided_reason = p_decided_reason
    where id = p_entry_id and record_version = p_expected_version
    returning * into v_entry;
  end if;
  if not found then
    raise exception 'stale_version: timesheet entry % target row was concurrently modified (expected version %)', p_entry_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  -- Tier C batch review fix (Finding 5, HIGH, C-07): same reasoning as
  -- app.decide_overtime_request above.
  perform app.capture_audit_event(
    v_entry.tenant_id, p_actor_auth_user_id, p_actor_label, 'decide_timesheet_entry',
    'app.timesheet_entries', p_entry_id, 'success', null, null, jsonb_build_object('decision', p_decision, 'eligible_minutes', v_entry.eligible_minutes, 'approved_minutes', v_entry.approved_minutes)
  );

  return v_entry;
end;
$function$;

revoke execute on function app.decide_timesheet_entry(p_entry_id uuid, p_expected_version integer, p_decision text, p_decided_reason text, p_approved_minutes_override integer, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) from anon, authenticated, service_role, public;
grant execute on function app.decide_timesheet_entry(p_entry_id uuid, p_expected_version integer, p_decision text, p_decided_reason text, p_approved_minutes_override integer, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) to authenticated;
grant execute on function app.decide_timesheet_entry(p_entry_id uuid, p_expected_version integer, p_decision text, p_decided_reason text, p_approved_minutes_override integer, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) to service_role;

create function public.decide_timesheet_entry(p_entry_id uuid, p_expected_version integer, p_decision text, p_decided_reason text, p_approved_minutes_override integer, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text default null)
 RETURNS app.timesheet_entries
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
  select app.decide_timesheet_entry(p_entry_id, p_expected_version, p_decision, p_decided_reason, p_approved_minutes_override, p_actor_auth_user_id, p_actor_label, p_client_ip);
$function$;

revoke execute on function public.decide_timesheet_entry(p_entry_id uuid, p_expected_version integer, p_decision text, p_decided_reason text, p_approved_minutes_override integer, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) from anon, authenticated, service_role, public;
grant execute on function public.decide_timesheet_entry(p_entry_id uuid, p_expected_version integer, p_decision text, p_decided_reason text, p_approved_minutes_override integer, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) to authenticated;
grant execute on function public.decide_timesheet_entry(p_entry_id uuid, p_expected_version integer, p_decision text, p_decided_reason text, p_approved_minutes_override integer, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) to service_role;

-- 23. discard_finance_settlement_draft -- authority shape: fin, tenant expression: v_settlement.tenant_id [wrapper definer flag repaired -- live had drifted to invoker]
drop function public.discard_finance_settlement_draft(p_settlement_id uuid, p_expected_version integer, p_reason text, p_actor_auth_user_id uuid, p_actor_label text);
drop function app.discard_finance_settlement_draft(p_settlement_id uuid, p_expected_version integer, p_reason text, p_actor_auth_user_id uuid, p_actor_label text);

create function app.discard_finance_settlement_draft(p_settlement_id uuid, p_expected_version integer, p_reason text, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text default null)
 RETURNS app.finance_settlements
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_settlement app.finance_settlements;
  v_was_executed boolean;
begin
  select * into v_settlement from app.finance_settlements where id = p_settlement_id for update;
  if not found then
    raise exception 'finance_settlement_not_found: %', p_settlement_id using errcode = 'no_data_found';
  end if;
  if not app.check_finance_settlement_authority('Edit', v_settlement.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:Edit for tenant %', p_actor_auth_user_id, v_settlement.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if v_settlement.record_version <> p_expected_version then
    raise exception 'stale_version: settlement % expected version % but found %', p_settlement_id, p_expected_version, v_settlement.record_version
      using errcode = 'serialization_failure';
  end if;
  -- ATW-032: 'executed' had no outgoing edge other than post_finance_settlement,
  -- and that edge fails unconditionally with finance_ap_over_settlement once a
  -- competing settlement has consumed the same AP open item. Such a settlement
  -- could not post, could not reverse (that path requires 'posted') and could not
  -- be discarded -- a real bank payment left permanently without a governed
  -- disposition. finance_settlements_status_check already admits 'void', so this
  -- needs no schema change; it needs an authorized, evidenced exit.
  -- 'approved' is deliberately NOT admitted: execute_finance_settlement is the
  -- correct next step from there and it is not blocked.
  if v_settlement.status not in ('draft', 'submitted', 'executed') then
    raise exception 'finance_settlement_not_cancellable: settlement % is %, only a draft, submitted or executed settlement may be discarded', p_settlement_id, v_settlement.status
      using errcode = 'check_violation';
  end if;

  v_was_executed := (v_settlement.status = 'executed');

  -- ATW-032: voiding an EXECUTED settlement is an approval-grade act, not an
  -- editing one -- a payment instruction has already left the bank
  -- (execution_reference/executed_by/executed_at are set). It is therefore held
  -- to the same FIN:Approve gate execute_/post_/request_..._reversal each apply,
  -- and to the same non-empty-reason requirement request_finance_settlement_reversal
  -- already imposes on the other post-execution correction path. The
  -- pre-execution statuses keep their original FIN:Edit-only behaviour exactly.
  if v_was_executed then
    if not app.check_finance_settlement_authority('Approve', v_settlement.tenant_id, p_actor_auth_user_id) then
      raise exception 'insufficient_authority: identity % lacks FIN:Approve for tenant % -- voiding an executed settlement requires approval authority, not edit authority', p_actor_auth_user_id, v_settlement.tenant_id
        using errcode = 'insufficient_privilege';
    end if;

  -- ISS-2026-302: IP allowlist, checked after authority is established and before any
  -- state change. Skipped when the caller supplies no address, and bypassable via the
  -- separately-governed app.ip_allowlist_bypass_grants -- the identical composition
  -- 20260826190000 established for the import-commit RPCs.
  if p_client_ip is not null and not app.has_active_ip_allowlist_bypass(v_settlement.tenant_id, p_actor_auth_user_id) then
    perform app.assert_ip_allowed(v_settlement.tenant_id, p_client_ip, 'admin', p_actor_label);
  end if;
    if p_reason is null or length(trim(p_reason)) = 0 then
      raise exception 'finance_settlement_void_reason_required: a non-empty reason is required to void an executed settlement'
        using errcode = 'check_violation';
    end if;
  end if;

  -- ATW-032: execution_reference, executed_by and executed_at are deliberately
  -- left untouched -- the evidence that a real payment left the bank must survive
  -- the void, not be erased by it.
  update app.finance_settlements set status = 'void', void_reason = p_reason, voided_by = p_actor_label, voided_at = now() where id = p_settlement_id returning * into v_settlement;

  -- ATW-032: a distinct action so a reviewer reading the audit trail can never
  -- mistake the voiding of a real executed payment for an ordinary draft discard.
  perform app.capture_audit_event(
    v_settlement.tenant_id, p_actor_auth_user_id, p_actor_label,
    case when v_was_executed then 'void_finance_executed_settlement' else 'discard_finance_settlement_draft' end,
    'app.finance_settlements', v_settlement.id, 'success', p_reason, null, to_jsonb(v_settlement)
  );

  return v_settlement;
end;
$function$;

revoke execute on function app.discard_finance_settlement_draft(p_settlement_id uuid, p_expected_version integer, p_reason text, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) from anon, authenticated, service_role, public;
grant execute on function app.discard_finance_settlement_draft(p_settlement_id uuid, p_expected_version integer, p_reason text, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) to authenticated;
grant execute on function app.discard_finance_settlement_draft(p_settlement_id uuid, p_expected_version integer, p_reason text, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) to service_role;

create function public.discard_finance_settlement_draft(p_settlement_id uuid, p_expected_version integer, p_reason text, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text default null)
 RETURNS app.finance_settlements
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
  select app.discard_finance_settlement_draft(p_settlement_id, p_expected_version, p_reason, p_actor_auth_user_id, p_actor_label, p_client_ip);
$function$;

revoke execute on function public.discard_finance_settlement_draft(p_settlement_id uuid, p_expected_version integer, p_reason text, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) from anon, authenticated, service_role, public;
grant execute on function public.discard_finance_settlement_draft(p_settlement_id uuid, p_expected_version integer, p_reason text, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) to authenticated;
grant execute on function public.discard_finance_settlement_draft(p_settlement_id uuid, p_expected_version integer, p_reason text, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) to service_role;

-- 24. execute_finance_settlement -- authority shape: fin, tenant expression: v_settlement.tenant_id [wrapper definer flag repaired -- live had drifted to invoker]
drop function public.execute_finance_settlement(p_settlement_id uuid, p_expected_version integer, p_execution_reference text, p_actor_auth_user_id uuid, p_actor_label text);
drop function app.execute_finance_settlement(p_settlement_id uuid, p_expected_version integer, p_execution_reference text, p_actor_auth_user_id uuid, p_actor_label text);

create function app.execute_finance_settlement(p_settlement_id uuid, p_expected_version integer, p_execution_reference text, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text default null)
 RETURNS app.finance_settlements
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_settlement app.finance_settlements;
begin
  select * into v_settlement from app.finance_settlements where id = p_settlement_id for update;
  if not found then
    raise exception 'finance_settlement_not_found: %', p_settlement_id using errcode = 'no_data_found';
  end if;
  if not app.check_finance_settlement_authority('Approve', v_settlement.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:Approve for tenant %', p_actor_auth_user_id, v_settlement.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  -- ISS-2026-302: IP allowlist, checked after authority is established and before any
  -- state change. Skipped when the caller supplies no address, and bypassable via the
  -- separately-governed app.ip_allowlist_bypass_grants -- the identical composition
  -- 20260826190000 established for the import-commit RPCs.
  if p_client_ip is not null and not app.has_active_ip_allowlist_bypass(v_settlement.tenant_id, p_actor_auth_user_id) then
    perform app.assert_ip_allowed(v_settlement.tenant_id, p_client_ip, 'admin', p_actor_label);
  end if;
  if v_settlement.record_version <> p_expected_version then
    raise exception 'stale_version: settlement % expected version % but found %', p_settlement_id, p_expected_version, v_settlement.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_settlement.status <> 'approved' then
    raise exception 'finance_settlement_not_approved: settlement % is % not approved', p_settlement_id, v_settlement.status
      using errcode = 'check_violation';
  end if;

  update app.finance_settlements
    set status = 'executed', execution_reference = p_execution_reference, executed_by = p_actor_label, executed_at = now()
    where id = p_settlement_id
    returning * into v_settlement;

  perform app.capture_audit_event(
    v_settlement.tenant_id, p_actor_auth_user_id, p_actor_label, 'execute_finance_settlement',
    'app.finance_settlements', v_settlement.id, 'success', null, null, to_jsonb(v_settlement)
  );

  return v_settlement;
end;
$function$;

revoke execute on function app.execute_finance_settlement(p_settlement_id uuid, p_expected_version integer, p_execution_reference text, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) from anon, authenticated, service_role, public;
grant execute on function app.execute_finance_settlement(p_settlement_id uuid, p_expected_version integer, p_execution_reference text, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) to authenticated;
grant execute on function app.execute_finance_settlement(p_settlement_id uuid, p_expected_version integer, p_execution_reference text, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) to service_role;

create function public.execute_finance_settlement(p_settlement_id uuid, p_expected_version integer, p_execution_reference text, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text default null)
 RETURNS app.finance_settlements
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
  select app.execute_finance_settlement(p_settlement_id, p_expected_version, p_execution_reference, p_actor_auth_user_id, p_actor_label, p_client_ip);
$function$;

revoke execute on function public.execute_finance_settlement(p_settlement_id uuid, p_expected_version integer, p_execution_reference text, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) from anon, authenticated, service_role, public;
grant execute on function public.execute_finance_settlement(p_settlement_id uuid, p_expected_version integer, p_execution_reference text, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) to authenticated;
grant execute on function public.execute_finance_settlement(p_settlement_id uuid, p_expected_version integer, p_execution_reference text, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) to service_role;

-- 25. generate_payroll_time_input -- authority shape: eval, tenant expression: v_period.tenant_id
drop function public.generate_payroll_time_input(p_period_id uuid, p_employee_id uuid, p_actor_auth_user_id uuid, p_actor_label text);
drop function app.generate_payroll_time_input(p_period_id uuid, p_employee_id uuid, p_actor_auth_user_id uuid, p_actor_label text);

create function app.generate_payroll_time_input(p_period_id uuid, p_employee_id uuid, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text default null)
 RETURNS app.payroll_time_inputs
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_period app.timesheet_periods;
  v_decision app.rbac_decision;
  v_employee app.employees;
begin
  select * into v_period from app.timesheet_periods where id = p_period_id;
  if v_period.id is null or not app.has_active_tenant_membership(v_period.tenant_id, p_actor_auth_user_id) then
    raise exception 'timesheet_period_not_found: %', p_period_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_period.tenant_id, 'HRS', 'Approve');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks HRS:Approve (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_period.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  -- ISS-2026-302: IP allowlist, checked after authority is established and before any
  -- state change. Skipped when the caller supplies no address, and bypassable via the
  -- separately-governed app.ip_allowlist_bypass_grants -- the identical composition
  -- 20260826190000 established for the import-commit RPCs.
  if p_client_ip is not null and not app.has_active_ip_allowlist_bypass(v_period.tenant_id, p_actor_auth_user_id) then
    perform app.assert_ip_allowed(v_period.tenant_id, p_client_ip, 'admin', p_actor_label);
  end if;

  select * into v_employee from app.employees where master_record_id = p_employee_id and tenant_id = v_period.tenant_id;
  if v_employee.master_record_id is null then
    raise exception 'employee_not_found: %', p_employee_id using errcode = 'no_data_found';
  end if;

  return app._generate_payroll_time_input(p_period_id, p_employee_id, p_actor_auth_user_id, p_actor_label);
end;
$function$;

revoke execute on function app.generate_payroll_time_input(p_period_id uuid, p_employee_id uuid, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) from anon, authenticated, service_role, public;
grant execute on function app.generate_payroll_time_input(p_period_id uuid, p_employee_id uuid, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) to authenticated;
grant execute on function app.generate_payroll_time_input(p_period_id uuid, p_employee_id uuid, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) to service_role;

create function public.generate_payroll_time_input(p_period_id uuid, p_employee_id uuid, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text default null)
 RETURNS app.payroll_time_inputs
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
  select app.generate_payroll_time_input(p_period_id, p_employee_id, p_actor_auth_user_id, p_actor_label, p_client_ip);
$function$;

revoke execute on function public.generate_payroll_time_input(p_period_id uuid, p_employee_id uuid, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) from anon, authenticated, service_role, public;
grant execute on function public.generate_payroll_time_input(p_period_id uuid, p_employee_id uuid, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) to authenticated;
grant execute on function public.generate_payroll_time_input(p_period_id uuid, p_employee_id uuid, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) to service_role;

-- 26. generate_payroll_time_inputs_for_period -- authority shape: eval, tenant expression: v_period.tenant_id
drop function public.generate_payroll_time_inputs_for_period(p_period_id uuid, p_actor_auth_user_id uuid, p_actor_label text);
drop function app.generate_payroll_time_inputs_for_period(p_period_id uuid, p_actor_auth_user_id uuid, p_actor_label text);

create function app.generate_payroll_time_inputs_for_period(p_period_id uuid, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text default null)
 RETURNS TABLE(employee_id uuid, payroll_time_input_id uuid, generated boolean, skip_reason text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_period app.timesheet_periods;
  v_decision app.rbac_decision;
  v_row record;
  v_result app.payroll_time_inputs;
begin
  select * into v_period from app.timesheet_periods where id = p_period_id;
  if v_period.id is null or not app.has_active_tenant_membership(v_period.tenant_id, p_actor_auth_user_id) then
    raise exception 'timesheet_period_not_found: %', p_period_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_period.tenant_id, 'HRS', 'Approve');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks HRS:Approve (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_period.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  -- ISS-2026-302: IP allowlist, checked after authority is established and before any
  -- state change. Skipped when the caller supplies no address, and bypassable via the
  -- separately-governed app.ip_allowlist_bypass_grants -- the identical composition
  -- 20260826190000 established for the import-commit RPCs.
  if p_client_ip is not null and not app.has_active_ip_allowlist_bypass(v_period.tenant_id, p_actor_auth_user_id) then
    perform app.assert_ip_allowed(v_period.tenant_id, p_client_ip, 'admin', p_actor_label);
  end if;

  for v_row in select s.employee_id as emp_id from app.timesheet_period_summaries s where s.timesheet_period_id = p_period_id and s.status = 'approved'
  loop
    begin
      v_result := app._generate_payroll_time_input(p_period_id, v_row.emp_id, p_actor_auth_user_id, p_actor_label);
      employee_id := v_row.emp_id; payroll_time_input_id := v_result.id; generated := true; skip_reason := null;
      return next;
    exception
      when others then
        employee_id := v_row.emp_id; payroll_time_input_id := null; generated := false; skip_reason := sqlerrm;
        return next;
    end;
  end loop;

  return;
end;
$function$;

revoke execute on function app.generate_payroll_time_inputs_for_period(p_period_id uuid, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) from anon, authenticated, service_role, public;
grant execute on function app.generate_payroll_time_inputs_for_period(p_period_id uuid, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) to authenticated;
grant execute on function app.generate_payroll_time_inputs_for_period(p_period_id uuid, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) to service_role;

create function public.generate_payroll_time_inputs_for_period(p_period_id uuid, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text default null)
 RETURNS TABLE(employee_id uuid, payroll_time_input_id uuid, generated boolean, skip_reason text)
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
  select * from app.generate_payroll_time_inputs_for_period(p_period_id, p_actor_auth_user_id, p_actor_label, p_client_ip);
$function$;

revoke execute on function public.generate_payroll_time_inputs_for_period(p_period_id uuid, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) from anon, authenticated, service_role, public;
grant execute on function public.generate_payroll_time_inputs_for_period(p_period_id uuid, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) to authenticated;
grant execute on function public.generate_payroll_time_inputs_for_period(p_period_id uuid, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) to service_role;

-- 27. import_historical_finance_journal -- authority shape: fin, tenant expression: p_tenant_id
drop function public.import_historical_finance_journal(p_tenant_id uuid, p_company_id uuid, p_source_id uuid, p_journal_date date, p_currency text, p_lines jsonb, p_reason text, p_actor_auth_user_id uuid, p_actor_label text);
drop function app.import_historical_finance_journal(p_tenant_id uuid, p_company_id uuid, p_source_id uuid, p_journal_date date, p_currency text, p_lines jsonb, p_reason text, p_actor_auth_user_id uuid, p_actor_label text);

create function app.import_historical_finance_journal(p_tenant_id uuid, p_company_id uuid, p_source_id uuid, p_journal_date date, p_currency text, p_lines jsonb, p_reason text, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text default null)
 RETURNS app.finance_journals
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_journal app.finance_journals;
  v_line jsonb;
  v_line_number integer := 0;
  v_total numeric(14, 2);
  v_period record;
  v_year integer;
  v_seq integer;
  v_number text;
begin
  if not app.check_finance_journal_authority('Approve', p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:Approve for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  -- ISS-2026-302: IP allowlist, checked after authority is established and before any
  -- state change. Skipped when the caller supplies no address, and bypassable via the
  -- separately-governed app.ip_allowlist_bypass_grants -- the identical composition
  -- 20260826190000 established for the import-commit RPCs.
  if p_client_ip is not null and not app.has_active_ip_allowlist_bypass(p_tenant_id, p_actor_auth_user_id) then
    perform app.assert_ip_allowed(p_tenant_id, p_client_ip, 'admin', p_actor_label);
  end if;

  if p_source_id is null then
    raise exception 'finance_journal_migration_source_id_required: a real, non-null source_id is required to import a historical journal' using errcode = 'check_violation';
  end if;

  if coalesce(trim(p_reason), '') = '' then
    raise exception 'finance_journal_migration_reason_required: a real, non-empty reason is required to import a historical journal' using errcode = 'check_violation';
  end if;

  select * into v_journal from app.finance_journals where tenant_id = p_tenant_id and source_type = 'migration' and source_id = p_source_id;
  if found then
    return v_journal;
  end if;

  v_total := app.validate_finance_journal_line_balance(p_lines);

  select * into v_period from app.resolve_finance_period_for_date(p_tenant_id, p_company_id, p_journal_date);
  if not found then
    raise exception 'finance_journal_period_not_found: no fiscal period covers % -- create the covering fiscal period before importing historical data into it', p_journal_date
      using errcode = 'no_data_found';
  end if;
  -- Deliberately does NOT require v_period.posting_eligible -- see this migration's own
  -- header for why (confirmed with the operator before implementing).

  v_year := extract(year from p_journal_date)::integer;
  insert into app.finance_journal_number_counters (tenant_id, company_id, year, next_seq)
  values (p_tenant_id, p_company_id, v_year, 2)
  on conflict (tenant_id, coalesce(company_id, '00000000-0000-0000-0000-000000000000'::uuid), year)
  do update set next_seq = app.finance_journal_number_counters.next_seq + 1
  returning next_seq - 1 into v_seq;
  v_number := 'JRNL-' || v_year::text || '-' || lpad(v_seq::text, 6, '0');

  insert into app.finance_journals (
    tenant_id, company_id, journal_number, source_type, source_id, idempotency_key,
    currency, total_amount, journal_date, status, posting_period_id, posted_by, posted_at, created_by
  )
  values (
    p_tenant_id, p_company_id, v_number, 'migration', p_source_id, 'migration:' || p_source_id::text,
    p_currency, v_total, p_journal_date, 'posted', v_period.period_id, p_actor_label, now(), p_actor_label
  )
  returning * into v_journal;

  for v_line in select * from jsonb_array_elements(p_lines) loop
    v_line_number := v_line_number + 1;
    insert into app.finance_journal_lines (journal_id, tenant_id, line_number, account_id, direction, amount)
    values (v_journal.id, p_tenant_id, v_line_number, (v_line ->> 'accountId')::uuid, v_line ->> 'direction', (v_line ->> 'amount')::numeric);
  end loop;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'import_historical_finance_journal',
    'app.finance_journals', v_journal.id, 'success', p_reason, null, to_jsonb(v_journal)
  );

  return v_journal;
end;
$function$;

revoke execute on function app.import_historical_finance_journal(p_tenant_id uuid, p_company_id uuid, p_source_id uuid, p_journal_date date, p_currency text, p_lines jsonb, p_reason text, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) from anon, authenticated, service_role, public;
grant execute on function app.import_historical_finance_journal(p_tenant_id uuid, p_company_id uuid, p_source_id uuid, p_journal_date date, p_currency text, p_lines jsonb, p_reason text, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) to authenticated;
grant execute on function app.import_historical_finance_journal(p_tenant_id uuid, p_company_id uuid, p_source_id uuid, p_journal_date date, p_currency text, p_lines jsonb, p_reason text, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) to service_role;

create function public.import_historical_finance_journal(p_tenant_id uuid, p_company_id uuid, p_source_id uuid, p_journal_date date, p_currency text, p_lines jsonb, p_reason text, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text default null)
 RETURNS app.finance_journals
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
  select app.import_historical_finance_journal(p_tenant_id, p_company_id, p_source_id, p_journal_date, p_currency, p_lines, p_reason, p_actor_auth_user_id, p_actor_label, p_client_ip);
$function$;

revoke execute on function public.import_historical_finance_journal(p_tenant_id uuid, p_company_id uuid, p_source_id uuid, p_journal_date date, p_currency text, p_lines jsonb, p_reason text, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) from anon, authenticated, service_role, public;
grant execute on function public.import_historical_finance_journal(p_tenant_id uuid, p_company_id uuid, p_source_id uuid, p_journal_date date, p_currency text, p_lines jsonb, p_reason text, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) to authenticated;
grant execute on function public.import_historical_finance_journal(p_tenant_id uuid, p_company_id uuid, p_source_id uuid, p_journal_date date, p_currency text, p_lines jsonb, p_reason text, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) to service_role;

-- 28. issue_finance_invoice -- authority shape: fin, tenant expression: v_invoice.tenant_id
drop function public.issue_finance_invoice(p_invoice_id uuid, p_expected_version integer, p_issue_date date, p_actor_auth_user_id uuid, p_actor_label text);
drop function app.issue_finance_invoice(p_invoice_id uuid, p_expected_version integer, p_issue_date date, p_actor_auth_user_id uuid, p_actor_label text);

create function app.issue_finance_invoice(p_invoice_id uuid, p_expected_version integer, p_issue_date date, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text default null)
 RETURNS app.finance_invoices
 LANGUAGE plpgsql
AS $function$
declare
  v_invoice app.finance_invoices;
  v_period record;
  v_year integer;
  v_seq integer;
  v_number text;
  v_ar_item app.finance_ar_open_items;
  v_due_date date;
  v_lines jsonb;
  v_tax_line app.finance_invoice_lines;
  v_tax_rule app.finance_tax_rule_versions;
begin
  select * into v_invoice from app.finance_invoices where id = p_invoice_id for update;
  if not found then
    raise exception 'finance_invoice_not_found: %', p_invoice_id using errcode = 'no_data_found';
  end if;
  if v_invoice.status = 'issued' then
    return v_invoice;
  end if;
  if not app.check_finance_invoice_authority('Approve', v_invoice.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:Approve for tenant %', p_actor_auth_user_id, v_invoice.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  -- ISS-2026-302: IP allowlist, checked after authority is established and before any
  -- state change. Skipped when the caller supplies no address, and bypassable via the
  -- separately-governed app.ip_allowlist_bypass_grants -- the identical composition
  -- 20260826190000 established for the import-commit RPCs.
  if p_client_ip is not null and not app.has_active_ip_allowlist_bypass(v_invoice.tenant_id, p_actor_auth_user_id) then
    perform app.assert_ip_allowed(v_invoice.tenant_id, p_client_ip, 'admin', p_actor_label);
  end if;
  if v_invoice.record_version <> p_expected_version then
    raise exception 'stale_version: invoice % expected version % but found %', p_invoice_id, p_expected_version, v_invoice.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_invoice.status <> 'approved' then
    raise exception 'finance_invoice_not_approved: invoice % is % not approved', p_invoice_id, v_invoice.status
      using errcode = 'check_violation';
  end if;

  -- HDN-374 (Financial Integrity Audit) finding 2: a job order may reach `issued` for at
  -- most one invoice at a time -- backed by finance_invoices_job_order_issued_unique
  -- (Tier C fix), not merely this application-level pre-check. Draft/submitted/approved
  -- invoices from a legitimate re-handoff (OPS-181) remain freely creatable and discardable
  -- (see the migration header); this is the actual AR/GL posting boundary, so it is the one
  -- place a second full-amount bill for the same job's revenue must be refused.
  if exists (
    select 1 from app.finance_invoices
    where tenant_id = v_invoice.tenant_id and job_order_id = v_invoice.job_order_id
      and id <> v_invoice.id and status = 'issued'
  ) then
    raise exception 'finance_invoice_job_order_already_issued: job order % already has a different issued invoice', v_invoice.job_order_id
      using errcode = 'check_violation';
  end if;

  select * into v_period from app.resolve_finance_period_for_date(v_invoice.tenant_id, v_invoice.company_id, p_issue_date);
  if not found then
    raise exception 'finance_invoice_period_not_found: no fiscal period covers %', p_issue_date
      using errcode = 'no_data_found';
  end if;
  if not v_period.posting_eligible then
    raise exception 'finance_invoice_period_not_open: fiscal period % for % is not open', v_period.period_code, p_issue_date
      using errcode = 'check_violation';
  end if;

  v_year := extract(year from p_issue_date)::integer;
  insert into app.finance_invoice_number_counters (tenant_id, company_id, year, next_seq)
  values (v_invoice.tenant_id, v_invoice.company_id, v_year, 2)
  on conflict (tenant_id, coalesce(company_id, '00000000-0000-0000-0000-000000000000'::uuid), year)
  do update set next_seq = app.finance_invoice_number_counters.next_seq + 1
  returning next_seq - 1 into v_seq;
  v_number := 'INV-' || v_year::text || '-' || lpad(v_seq::text, 6, '0');

  v_due_date := p_issue_date + (v_invoice.payment_term_days || ' days')::interval;

  select * into v_ar_item from app.post_finance_ar_open_item(
    v_invoice.tenant_id, v_invoice.company_id, v_invoice.customer_account_id, 'invoice', v_invoice.id,
    v_invoice.currency, v_invoice.total_amount, p_issue_date, v_due_date, p_actor_auth_user_id, p_actor_label
  );

  -- FIN-202: debit AR control for the full total; credit revenue for the
  -- subtotal; credit each tax line's own governed output account (or the
  -- tax_payable_default posting-map key when none is configured).
  v_lines := jsonb_build_array(
    jsonb_build_object('postingMapKey', 'ar_control', 'direction', 'debit', 'amount', v_invoice.total_amount, 'openItemType', 'ar_open_item', 'openItemId', v_ar_item.id)
  );
  if v_invoice.subtotal_amount > 0 then
    v_lines := v_lines || jsonb_build_array(jsonb_build_object('postingMapKey', 'revenue_default', 'direction', 'credit', 'amount', v_invoice.subtotal_amount));
  end if;
  for v_tax_line in select * from app.finance_invoice_lines where invoice_id = p_invoice_id and line_type = 'tax' and amount > 0 loop
    v_tax_rule := null;
    if v_tax_line.tax_rule_version_id is not null then
      select * into v_tax_rule from app.finance_tax_rule_versions where id = v_tax_line.tax_rule_version_id and output_account_id is not null;
    end if;
    if v_tax_rule is not null then
      v_lines := v_lines || jsonb_build_array(jsonb_build_object('accountId', v_tax_rule.output_account_id, 'direction', 'credit', 'amount', v_tax_line.amount));
    else
      v_lines := v_lines || jsonb_build_array(jsonb_build_object('postingMapKey', 'tax_payable_default', 'direction', 'credit', 'amount', v_tax_line.amount));
    end if;
  end loop;

  perform app.post_finance_subledger_batch(
    v_invoice.tenant_id, v_invoice.company_id, 'invoice', v_invoice.id, p_issue_date, v_invoice.currency,
    v_lines, p_actor_auth_user_id, p_actor_label
  );

  -- HDN-374 Tier C finding 2: a genuine race between the exists() pre-check above and this
  -- update (two concurrent issue_finance_invoice calls for two DIFFERENT invoices on the
  -- SAME job order, each already past its own exists() check before either commits) is
  -- caught here by finance_invoices_job_order_issued_unique -- the loser's own update
  -- raises unique_violation instead of silently succeeding; re-raised as the same named
  -- exception the non-concurrent pre-check above already gives, never a raw unique_violation.
  begin
    update app.finance_invoices
      set status = 'issued', invoice_number = v_number, issue_date = p_issue_date, due_date = v_due_date,
          posting_period_id = v_period.period_id, ar_open_item_id = v_ar_item.id, issued_by = p_actor_label, issued_at = now()
      where id = p_invoice_id
      returning * into v_invoice;
  exception
    when unique_violation then
      raise exception 'finance_invoice_job_order_already_issued: job order % already has a different issued invoice', v_invoice.job_order_id
        using errcode = 'check_violation';
  end;

  perform app.capture_audit_event(
    v_invoice.tenant_id, p_actor_auth_user_id, p_actor_label, 'issue_finance_invoice',
    'app.finance_invoices', v_invoice.id, 'success', null, null, to_jsonb(v_invoice)
  );

  return v_invoice;
end;
$function$;

revoke execute on function app.issue_finance_invoice(p_invoice_id uuid, p_expected_version integer, p_issue_date date, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) from anon, authenticated, service_role, public;
grant execute on function app.issue_finance_invoice(p_invoice_id uuid, p_expected_version integer, p_issue_date date, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) to authenticated;
grant execute on function app.issue_finance_invoice(p_invoice_id uuid, p_expected_version integer, p_issue_date date, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) to service_role;

create function public.issue_finance_invoice(p_invoice_id uuid, p_expected_version integer, p_issue_date date, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text default null)
 RETURNS app.finance_invoices
 LANGUAGE sql
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
  select app.issue_finance_invoice(p_invoice_id, p_expected_version, p_issue_date, p_actor_auth_user_id, p_actor_label, p_client_ip);
$function$;

revoke execute on function public.issue_finance_invoice(p_invoice_id uuid, p_expected_version integer, p_issue_date date, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) from anon, authenticated, service_role, public;
grant execute on function public.issue_finance_invoice(p_invoice_id uuid, p_expected_version integer, p_issue_date date, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) to authenticated;
grant execute on function public.issue_finance_invoice(p_invoice_id uuid, p_expected_version integer, p_issue_date date, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) to service_role;

-- 29. lock_finance_period -- authority shape: fin, tenant expression: p_tenant_id
drop function public.lock_finance_period(p_tenant_id uuid, p_company_id uuid, p_period_id uuid, p_lock_scope text, p_reason text, p_evidence_ref text, p_actor_auth_user_id uuid, p_actor_label text);
drop function app.lock_finance_period(p_tenant_id uuid, p_company_id uuid, p_period_id uuid, p_lock_scope text, p_reason text, p_evidence_ref text, p_actor_auth_user_id uuid, p_actor_label text);

create function app.lock_finance_period(p_tenant_id uuid, p_company_id uuid, p_period_id uuid, p_lock_scope text, p_reason text, p_evidence_ref text, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text default null)
 RETURNS app.finance_period_locks
 LANGUAGE plpgsql
AS $function$
declare
  v_lock app.finance_period_locks;
  v_period app.finance_fiscal_periods;
begin
  if not app.has_active_tenant_membership(p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % holds no active membership for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.check_finance_period_lock_authority('Approve', p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:Approve for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  -- ISS-2026-302: IP allowlist, checked after authority is established and before any
  -- state change. Skipped when the caller supplies no address, and bypassable via the
  -- separately-governed app.ip_allowlist_bypass_grants -- the identical composition
  -- 20260826190000 established for the import-commit RPCs.
  if p_client_ip is not null and not app.has_active_ip_allowlist_bypass(p_tenant_id, p_actor_auth_user_id) then
    perform app.assert_ip_allowed(p_tenant_id, p_client_ip, 'admin', p_actor_label);
  end if;
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'finance_period_lock_reason_required: a non-empty reason is required' using errcode = 'check_violation';
  end if;
  if p_lock_scope not in ('all', 'gl', 'ar', 'ap', 'tax') then
    raise exception 'finance_period_lock_invalid_scope: % is not a supported lock scope', p_lock_scope using errcode = 'check_violation';
  end if;

  select * into v_period from app.finance_fiscal_periods where id = p_period_id and tenant_id = p_tenant_id;
  if not found then
    raise exception 'finance_period_not_found: % is not a known fiscal period for tenant %', p_period_id, p_tenant_id
      using errcode = 'no_data_found';
  end if;

  select * into v_lock from app.finance_period_locks
    where tenant_id = p_tenant_id and period_id = p_period_id and lock_scope = p_lock_scope
      and coalesce(company_id, '00000000-0000-0000-0000-000000000000'::uuid) = coalesce(p_company_id, '00000000-0000-0000-0000-000000000000'::uuid);

  if found and v_lock.status = 'locked' then
    return v_lock;
  end if;

  if found then
    update app.finance_period_locks
      set status = 'locked', lock_reason = p_reason, evidence_ref = p_evidence_ref, locked_by = p_actor_label, locked_at = now(),
          relocked_by = p_actor_label, relocked_at = now()
      where id = v_lock.id
      returning * into v_lock;
  else
    -- HDN-374 Tier C fix: a genuine race between the not-found check above and this insert
    -- (two concurrent first-time lock calls for the same tenant/period/scope) is resolved by
    -- re-selecting the now-existing row and applying the same locked-transition logic the
    -- ordinary "found" branch above already uses, rather than surfacing a raw unique_violation
    -- or silently discarding the loser's own genuine lock intent.
    begin
      insert into app.finance_period_locks (tenant_id, company_id, period_id, lock_scope, lock_reason, evidence_ref, locked_by, created_by)
      values (p_tenant_id, p_company_id, p_period_id, p_lock_scope, p_reason, p_evidence_ref, p_actor_label, p_actor_label)
      returning * into v_lock;
    exception
      when unique_violation then
        select * into v_lock from app.finance_period_locks
          where tenant_id = p_tenant_id and period_id = p_period_id and lock_scope = p_lock_scope
            and coalesce(company_id, '00000000-0000-0000-0000-000000000000'::uuid) = coalesce(p_company_id, '00000000-0000-0000-0000-000000000000'::uuid);
        if not found then
          raise;
        end if;
        if v_lock.status = 'locked' then
          return v_lock;
        end if;
        update app.finance_period_locks
          set status = 'locked', lock_reason = p_reason, evidence_ref = p_evidence_ref, locked_by = p_actor_label, locked_at = now(),
              relocked_by = p_actor_label, relocked_at = now()
          where id = v_lock.id
          returning * into v_lock;
    end;
  end if;

  insert into app.finance_period_lock_events (lock_id, tenant_id, action, reason, actor_label) values (v_lock.id, p_tenant_id, 'locked', p_reason, p_actor_label);

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'lock_finance_period',
    'app.finance_period_locks', v_lock.id, 'success', p_reason, null, to_jsonb(v_lock)
  );

  return v_lock;
end;
$function$;

revoke execute on function app.lock_finance_period(p_tenant_id uuid, p_company_id uuid, p_period_id uuid, p_lock_scope text, p_reason text, p_evidence_ref text, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) from anon, authenticated, service_role, public;
grant execute on function app.lock_finance_period(p_tenant_id uuid, p_company_id uuid, p_period_id uuid, p_lock_scope text, p_reason text, p_evidence_ref text, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) to authenticated;
grant execute on function app.lock_finance_period(p_tenant_id uuid, p_company_id uuid, p_period_id uuid, p_lock_scope text, p_reason text, p_evidence_ref text, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) to service_role;

create function public.lock_finance_period(p_tenant_id uuid, p_company_id uuid, p_period_id uuid, p_lock_scope text, p_reason text, p_evidence_ref text, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text default null)
 RETURNS app.finance_period_locks
 LANGUAGE sql
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
  select app.lock_finance_period(p_tenant_id, p_company_id, p_period_id, p_lock_scope, p_reason, p_evidence_ref, p_actor_auth_user_id, p_actor_label, p_client_ip);
$function$;

revoke execute on function public.lock_finance_period(p_tenant_id uuid, p_company_id uuid, p_period_id uuid, p_lock_scope text, p_reason text, p_evidence_ref text, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) from anon, authenticated, service_role, public;
grant execute on function public.lock_finance_period(p_tenant_id uuid, p_company_id uuid, p_period_id uuid, p_lock_scope text, p_reason text, p_evidence_ref text, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) to authenticated;
grant execute on function public.lock_finance_period(p_tenant_id uuid, p_company_id uuid, p_period_id uuid, p_lock_scope text, p_reason text, p_evidence_ref text, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) to service_role;

-- 30. lock_timesheet_period -- authority shape: eval, tenant expression: v_period.tenant_id
drop function public.lock_timesheet_period(p_period_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text);
drop function app.lock_timesheet_period(p_period_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text);

create function app.lock_timesheet_period(p_period_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text default null)
 RETURNS app.timesheet_periods
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_decision app.rbac_decision;
  v_period app.timesheet_periods;
  v_unapproved_count integer;
begin
  select * into v_period from app.timesheet_periods where id = p_period_id for update;
  if v_period.id is null or not app.has_active_tenant_membership(v_period.tenant_id, p_actor_auth_user_id) then
    raise exception 'timesheet_period_not_found: %', p_period_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_period.tenant_id, 'HRS', 'Approve');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks HRS:Approve (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_period.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  -- ISS-2026-302: IP allowlist, checked after authority is established and before any
  -- state change. Skipped when the caller supplies no address, and bypassable via the
  -- separately-governed app.ip_allowlist_bypass_grants -- the identical composition
  -- 20260826190000 established for the import-commit RPCs.
  if p_client_ip is not null and not app.has_active_ip_allowlist_bypass(v_period.tenant_id, p_actor_auth_user_id) then
    perform app.assert_ip_allowed(v_period.tenant_id, p_client_ip, 'admin', p_actor_label);
  end if;

  if v_period.record_version <> p_expected_version then
    raise exception 'stale_version: timesheet period % expected version % but found %', p_period_id, p_expected_version, v_period.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_period.status <> 'open' then
    raise exception 'invalid_transition: timesheet period % is already locked', p_period_id using errcode = 'check_violation';
  end if;

  select count(*) into v_unapproved_count from app.timesheet_period_summaries where timesheet_period_id = p_period_id and status <> 'approved';
  if v_unapproved_count > 0 then
    raise exception 'period_has_unapproved_summaries: % employee summary(ies) in period % are not yet approved', v_unapproved_count, p_period_id
      using errcode = 'check_violation';
  end if;

  update app.timesheet_periods
  set status = 'locked', locked_by = p_actor_label, locked_at = now()
  where id = p_period_id and record_version = p_expected_version
  returning * into v_period;
  if not found then
    raise exception 'stale_version: timesheet period % target row was concurrently modified (expected version %)', p_period_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_period.tenant_id, p_actor_auth_user_id, p_actor_label, 'lock_timesheet_period',
    'app.timesheet_periods', p_period_id, 'success', null, null, '{}'::jsonb
  );

  return v_period;
end;
$function$;

revoke execute on function app.lock_timesheet_period(p_period_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) from anon, authenticated, service_role, public;
grant execute on function app.lock_timesheet_period(p_period_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) to authenticated;
grant execute on function app.lock_timesheet_period(p_period_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) to service_role;

create function public.lock_timesheet_period(p_period_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text default null)
 RETURNS app.timesheet_periods
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
  select app.lock_timesheet_period(p_period_id, p_expected_version, p_actor_auth_user_id, p_actor_label, p_client_ip);
$function$;

revoke execute on function public.lock_timesheet_period(p_period_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) from anon, authenticated, service_role, public;
grant execute on function public.lock_timesheet_period(p_period_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) to authenticated;
grant execute on function public.lock_timesheet_period(p_period_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) to service_role;

-- 31. post_finance_correction -- authority shape: fin, tenant expression: v_correction.tenant_id [wrapper definer flag repaired -- live had drifted to invoker]
drop function public.post_finance_correction(p_correction_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text);
drop function app.post_finance_correction(p_correction_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text);

create function app.post_finance_correction(p_correction_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text default null)
 RETURNS app.finance_journal_corrections
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_correction app.finance_journal_corrections;
  v_original app.finance_journals;
  v_lines jsonb := '[]'::jsonb;
  v_line record;
  v_flipped text;
  v_journal app.finance_journals;
  v_batch app.finance_subledger_batches;
begin
  select * into v_correction from app.finance_journal_corrections where id = p_correction_id for update;
  if not found then
    raise exception 'finance_correction_not_found: %', p_correction_id using errcode = 'no_data_found';
  end if;
  if v_correction.status = 'posted' then
    return v_correction;
  end if;
  if not app.check_finance_correction_authority('Approve', v_correction.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:Approve for tenant %', p_actor_auth_user_id, v_correction.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  -- ISS-2026-302: IP allowlist, checked after authority is established and before any
  -- state change. Skipped when the caller supplies no address, and bypassable via the
  -- separately-governed app.ip_allowlist_bypass_grants -- the identical composition
  -- 20260826190000 established for the import-commit RPCs.
  if p_client_ip is not null and not app.has_active_ip_allowlist_bypass(v_correction.tenant_id, p_actor_auth_user_id) then
    perform app.assert_ip_allowed(v_correction.tenant_id, p_client_ip, 'admin', p_actor_label);
  end if;
  if v_correction.record_version <> p_expected_version then
    raise exception 'stale_version: correction % expected version % but found %', p_correction_id, p_expected_version, v_correction.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_correction.status <> 'approved' then
    raise exception 'finance_correction_not_approved: correction % is % not approved', p_correction_id, v_correction.status
      using errcode = 'check_violation';
  end if;

  select * into v_original from app.finance_journals where id = v_correction.original_journal_id;
  if not found or v_original.status <> 'posted' then
    raise exception 'finance_correction_original_not_posted: journal % is no longer posted', v_correction.original_journal_id
      using errcode = 'check_violation';
  end if;

  if v_correction.correction_type = 'reversal' then
    for v_line in select direction, account_id, amount, dimension from app.finance_journal_lines where journal_id = v_original.id order by line_number asc loop
      v_flipped := case when v_line.direction = 'debit' then 'credit' else 'debit' end;
      v_lines := v_lines || jsonb_build_array(jsonb_build_object('accountId', v_line.account_id, 'direction', v_flipped, 'amount', v_line.amount, 'dimension', v_line.dimension));
    end loop;
  else
    v_lines := v_correction.adjustment_lines;
  end if;

  select * into v_journal from app.create_and_post_finance_system_journal(
    v_correction.tenant_id, v_correction.company_id, 'correction', v_correction.id, v_correction.correction_date,
    v_original.currency, v_lines, p_actor_auth_user_id, p_actor_label, 'gl'
  );

  if v_correction.correction_type = 'reversal' and v_original.source_type = 'subledger' then
    update app.finance_subledger_batches set status = 'reversed' where gl_journal_id = v_original.id and status = 'posted' returning * into v_batch;
  end if;

  update app.finance_journal_corrections
    set status = 'posted', correction_journal_id = v_journal.id, posted_by = p_actor_label, posted_at = now()
    where id = p_correction_id
    returning * into v_correction;

  perform app.capture_audit_event(
    v_correction.tenant_id, p_actor_auth_user_id, p_actor_label, 'post_finance_correction',
    'app.finance_journal_corrections', v_correction.id, 'success', null, null, to_jsonb(v_correction)
  );

  return v_correction;
end;
$function$;

revoke execute on function app.post_finance_correction(p_correction_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) from anon, authenticated, service_role, public;
grant execute on function app.post_finance_correction(p_correction_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) to authenticated;
grant execute on function app.post_finance_correction(p_correction_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) to service_role;

create function public.post_finance_correction(p_correction_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text default null)
 RETURNS app.finance_journal_corrections
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
  select app.post_finance_correction(p_correction_id, p_expected_version, p_actor_auth_user_id, p_actor_label, p_client_ip);
$function$;

revoke execute on function public.post_finance_correction(p_correction_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) from anon, authenticated, service_role, public;
grant execute on function public.post_finance_correction(p_correction_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) to authenticated;
grant execute on function public.post_finance_correction(p_correction_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) to service_role;

-- 32. post_finance_journal -- authority shape: fin, tenant expression: v_journal.tenant_id [wrapper definer flag repaired -- live had drifted to invoker]
drop function public.post_finance_journal(p_journal_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text);
drop function app.post_finance_journal(p_journal_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text);

create function app.post_finance_journal(p_journal_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text default null)
 RETURNS app.finance_journals
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_journal app.finance_journals;
  v_period record;
  v_year integer;
  v_seq integer;
  v_number text;
  v_lines jsonb;
begin
  select * into v_journal from app.finance_journals where id = p_journal_id for update;
  if not found then
    raise exception 'finance_journal_not_found: %', p_journal_id using errcode = 'no_data_found';
  end if;
  if v_journal.status = 'posted' then
    return v_journal;
  end if;
  if not app.check_finance_journal_authority('Approve', v_journal.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:Approve for tenant %', p_actor_auth_user_id, v_journal.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  -- ISS-2026-302: IP allowlist, checked after authority is established and before any
  -- state change. Skipped when the caller supplies no address, and bypassable via the
  -- separately-governed app.ip_allowlist_bypass_grants -- the identical composition
  -- 20260826190000 established for the import-commit RPCs.
  if p_client_ip is not null and not app.has_active_ip_allowlist_bypass(v_journal.tenant_id, p_actor_auth_user_id) then
    perform app.assert_ip_allowed(v_journal.tenant_id, p_client_ip, 'admin', p_actor_label);
  end if;
  -- HDN-373 (ISS-2026-181, maker/checker): defense in depth, mirroring this function's own
  -- existing convention of independently re-checking FIN:Approve rather than trusting the
  -- prior step alone -- the preparer may not reach posted status either.
  if v_journal.submitted_by_auth_user_id is not null and v_journal.submitted_by_auth_user_id = p_actor_auth_user_id then
    raise exception 'self_approval_denied: identity % submitted journal % and may not also post it', p_actor_auth_user_id, p_journal_id
      using errcode = 'insufficient_privilege';
  end if;
  if v_journal.record_version <> p_expected_version then
    raise exception 'stale_version: journal % expected version % but found %', p_journal_id, p_expected_version, v_journal.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_journal.status <> 'approved' then
    raise exception 'finance_journal_not_approved: journal % is % not approved', p_journal_id, v_journal.status
      using errcode = 'check_violation';
  end if;

  select coalesce(jsonb_agg(jsonb_build_object('direction', direction, 'amount', amount)), '[]'::jsonb)
    into v_lines
    from app.finance_journal_lines where journal_id = p_journal_id;
  perform app.validate_finance_journal_line_balance(v_lines);

  select * into v_period from app.resolve_finance_period_for_date(v_journal.tenant_id, v_journal.company_id, v_journal.journal_date);
  if not found then
    raise exception 'finance_journal_period_not_found: no fiscal period covers %', v_journal.journal_date
      using errcode = 'no_data_found';
  end if;
  if not v_period.posting_eligible then
    raise exception 'finance_journal_period_not_open: fiscal period % for % is not open', v_period.period_code, v_journal.journal_date
      using errcode = 'check_violation';
  end if;
  perform app.assert_finance_period_open_for_posting(v_journal.tenant_id, v_journal.company_id, v_period.period_id, 'gl');

  v_year := extract(year from v_journal.journal_date)::integer;
  insert into app.finance_journal_number_counters (tenant_id, company_id, year, next_seq)
  values (v_journal.tenant_id, v_journal.company_id, v_year, 2)
  on conflict (tenant_id, coalesce(company_id, '00000000-0000-0000-0000-000000000000'::uuid), year)
  do update set next_seq = app.finance_journal_number_counters.next_seq + 1
  returning next_seq - 1 into v_seq;
  v_number := 'JRNL-' || v_year::text || '-' || lpad(v_seq::text, 6, '0');

  update app.finance_journals
    set status = 'posted', journal_number = v_number, posting_period_id = v_period.period_id, posted_by = p_actor_label, posted_at = now()
    where id = p_journal_id
    returning * into v_journal;

  perform app.capture_audit_event(
    v_journal.tenant_id, p_actor_auth_user_id, p_actor_label, 'post_finance_journal',
    'app.finance_journals', v_journal.id, 'success', null, null, to_jsonb(v_journal)
  );

  return v_journal;
end;
$function$;

revoke execute on function app.post_finance_journal(p_journal_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) from anon, authenticated, service_role, public;
grant execute on function app.post_finance_journal(p_journal_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) to authenticated;
grant execute on function app.post_finance_journal(p_journal_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) to service_role;

create function public.post_finance_journal(p_journal_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text default null)
 RETURNS app.finance_journals
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
  select app.post_finance_journal(p_journal_id, p_expected_version, p_actor_auth_user_id, p_actor_label, p_client_ip);
$function$;

revoke execute on function public.post_finance_journal(p_journal_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) from anon, authenticated, service_role, public;
grant execute on function public.post_finance_journal(p_journal_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) to authenticated;
grant execute on function public.post_finance_journal(p_journal_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) to service_role;

-- 33. post_finance_opening_balance_batch -- authority shape: fin, tenant expression: v_tenant_id
drop function public.post_finance_opening_balance_batch(p_open_item_type text, p_open_item_id uuid, p_actor_auth_user_id uuid, p_actor_label text);
drop function app.post_finance_opening_balance_batch(p_open_item_type text, p_open_item_id uuid, p_actor_auth_user_id uuid, p_actor_label text);

create function app.post_finance_opening_balance_batch(p_open_item_type text, p_open_item_id uuid, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text default null)
 RETURNS app.finance_subledger_batches
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'public', 'pg_temp'
AS $function$
declare
  v_ar app.finance_ar_open_items;
  v_ap app.finance_ap_open_items;
  v_tenant_id uuid;
  v_company_id uuid;
  v_currency text;
  v_amount numeric(14, 2);
  v_posting_date date;
  v_lines jsonb;
  v_batch app.finance_subledger_batches;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  if p_open_item_type not in ('ar', 'ap') then
    raise exception 'finance_opening_balance_unknown_item_type: % is not ar or ap', p_open_item_type using errcode = 'check_violation';
  end if;

  if p_open_item_type = 'ar' then
    select * into v_ar from app.finance_ar_open_items where id = p_open_item_id;
    if not found then
      raise exception 'finance_ar_open_item_not_found: %', p_open_item_id using errcode = 'no_data_found';
    end if;
    if v_ar.source_document_type <> 'opening_balance' then
      raise exception 'finance_opening_balance_wrong_source_type: AR open item % is sourced from %, not an opening balance', p_open_item_id, v_ar.source_document_type
        using errcode = 'check_violation';
    end if;
    v_tenant_id := v_ar.tenant_id; v_company_id := v_ar.company_id; v_currency := v_ar.currency;
    v_amount := v_ar.original_amount; v_posting_date := v_ar.invoice_date;
  else
    select * into v_ap from app.finance_ap_open_items where id = p_open_item_id;
    if not found then
      raise exception 'finance_ap_open_item_not_found: %', p_open_item_id using errcode = 'no_data_found';
    end if;
    if v_ap.source_document_type <> 'opening_balance' then
      raise exception 'finance_opening_balance_wrong_source_type: AP open item % is sourced from %, not an opening balance', p_open_item_id, v_ap.source_document_type
        using errcode = 'check_violation';
    end if;
    v_tenant_id := v_ap.tenant_id; v_company_id := v_ap.company_id; v_currency := v_ap.currency;
    v_amount := v_ap.original_amount; v_posting_date := v_ap.bill_date;
  end if;

  if not app.check_finance_subledger_authority('Approve', v_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:Approve for tenant %', p_actor_auth_user_id, v_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  -- ISS-2026-302: IP allowlist, checked after authority is established and before any
  -- state change. Skipped when the caller supplies no address, and bypassable via the
  -- separately-governed app.ip_allowlist_bypass_grants -- the identical composition
  -- 20260826190000 established for the import-commit RPCs.
  if p_client_ip is not null and not app.has_active_ip_allowlist_bypass(v_tenant_id, p_actor_auth_user_id) then
    perform app.assert_ip_allowed(v_tenant_id, p_client_ip, 'admin', p_actor_label);
  end if;

  select * into v_batch from app.finance_subledger_batches
  where tenant_id = v_tenant_id and source_type = 'opening_balance' and source_id = p_open_item_id;
  if found then
    return v_batch;
  end if;

  if p_open_item_type = 'ar' then
    v_lines := jsonb_build_array(
      jsonb_build_object('postingMapKey', 'ar_control', 'direction', 'debit', 'amount', v_amount,
                         'openItemType', 'ar_open_item', 'openItemId', p_open_item_id),
      jsonb_build_object('postingMapKey', 'opening_balance_equity', 'direction', 'credit', 'amount', v_amount)
    );
  else
    v_lines := jsonb_build_array(
      jsonb_build_object('postingMapKey', 'opening_balance_equity', 'direction', 'debit', 'amount', v_amount),
      jsonb_build_object('postingMapKey', 'ap_control', 'direction', 'credit', 'amount', v_amount,
                         'openItemType', 'ap_open_item', 'openItemId', p_open_item_id)
    );
  end if;

  v_batch := app.post_finance_subledger_batch(
    v_tenant_id, v_company_id, 'opening_balance', p_open_item_id, v_posting_date, v_currency,
    v_lines, p_actor_auth_user_id, p_actor_label
  );

  return v_batch;
end;
$function$;

revoke execute on function app.post_finance_opening_balance_batch(p_open_item_type text, p_open_item_id uuid, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) from anon, authenticated, service_role, public;
grant execute on function app.post_finance_opening_balance_batch(p_open_item_type text, p_open_item_id uuid, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) to service_role;

create function public.post_finance_opening_balance_batch(p_open_item_type text, p_open_item_id uuid, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text default null)
 RETURNS app.finance_subledger_batches
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'app', 'public', 'pg_temp'
AS $function$
  select app.post_finance_opening_balance_batch(p_open_item_type, p_open_item_id, p_actor_auth_user_id, p_actor_label, p_client_ip);
$function$;

revoke execute on function public.post_finance_opening_balance_batch(p_open_item_type text, p_open_item_id uuid, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) from anon, authenticated, service_role, public;
grant execute on function public.post_finance_opening_balance_batch(p_open_item_type text, p_open_item_id uuid, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) to service_role;

-- 34. post_finance_settlement -- authority shape: fin, tenant expression: v_settlement.tenant_id [wrapper definer flag repaired -- live had drifted to invoker]
drop function public.post_finance_settlement(p_settlement_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text);
drop function app.post_finance_settlement(p_settlement_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text);

create function app.post_finance_settlement(p_settlement_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text default null)
 RETURNS app.finance_settlements
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_settlement app.finance_settlements;
  v_period record;
  v_year integer;
  v_seq integer;
  v_number text;
  v_allocation app.finance_settlement_allocations;
  v_lines jsonb;
begin
  select * into v_settlement from app.finance_settlements where id = p_settlement_id for update;
  if not found then
    raise exception 'finance_settlement_not_found: %', p_settlement_id using errcode = 'no_data_found';
  end if;
  if v_settlement.status = 'posted' then
    return v_settlement;
  end if;
  if not app.check_finance_settlement_authority('Approve', v_settlement.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:Approve for tenant %', p_actor_auth_user_id, v_settlement.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  -- ISS-2026-302: IP allowlist, checked after authority is established and before any
  -- state change. Skipped when the caller supplies no address, and bypassable via the
  -- separately-governed app.ip_allowlist_bypass_grants -- the identical composition
  -- 20260826190000 established for the import-commit RPCs.
  if p_client_ip is not null and not app.has_active_ip_allowlist_bypass(v_settlement.tenant_id, p_actor_auth_user_id) then
    perform app.assert_ip_allowed(v_settlement.tenant_id, p_client_ip, 'admin', p_actor_label);
  end if;
  if v_settlement.record_version <> p_expected_version then
    raise exception 'stale_version: settlement % expected version % but found %', p_settlement_id, p_expected_version, v_settlement.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_settlement.status <> 'executed' then
    raise exception 'finance_settlement_not_executed: settlement % is % not executed', p_settlement_id, v_settlement.status
      using errcode = 'check_violation';
  end if;

  select * into v_period from app.resolve_finance_period_for_date(v_settlement.tenant_id, v_settlement.company_id, v_settlement.settlement_date);
  if not found then
    raise exception 'finance_settlement_period_not_found: no fiscal period covers %', v_settlement.settlement_date
      using errcode = 'no_data_found';
  end if;
  if not v_period.posting_eligible then
    raise exception 'finance_settlement_period_not_open: fiscal period % for % is not open', v_period.period_code, v_settlement.settlement_date
      using errcode = 'check_violation';
  end if;

  for v_allocation in select * from app.finance_settlement_allocations where settlement_id = p_settlement_id and status = 'applied' order by created_at asc loop
    perform app.apply_finance_ap_settlement(
      v_allocation.ap_open_item_id, v_allocation.amount, 'settlement', v_settlement.id,
      v_settlement.idempotency_key || ':' || v_allocation.ap_open_item_id::text, p_actor_auth_user_id, p_actor_label
    );
  end loop;

  -- FIN-202: debit AP control for the allocated total (plus a governed fee
  -- expense debit when a fee applies); credit cash for the full total.
  v_lines := jsonb_build_array(
    jsonb_build_object('postingMapKey', 'ap_control', 'direction', 'debit', 'amount', v_settlement.allocated_amount)
  );
  if v_settlement.fee_amount > 0 then
    v_lines := v_lines || jsonb_build_array(jsonb_build_object('postingMapKey', 'fee_expense_default', 'direction', 'debit', 'amount', v_settlement.fee_amount));
  end if;
  v_lines := v_lines || jsonb_build_array(jsonb_build_object('postingMapKey', 'cash_default', 'direction', 'credit', 'amount', v_settlement.total_amount));

  perform app.post_finance_subledger_batch(
    v_settlement.tenant_id, v_settlement.company_id, 'settlement', v_settlement.id, v_settlement.settlement_date, v_settlement.currency,
    v_lines, p_actor_auth_user_id, p_actor_label
  );

  v_year := extract(year from v_settlement.settlement_date)::integer;
  insert into app.finance_settlement_number_counters (tenant_id, company_id, year, next_seq)
  values (v_settlement.tenant_id, v_settlement.company_id, v_year, 2)
  on conflict (tenant_id, coalesce(company_id, '00000000-0000-0000-0000-000000000000'::uuid), year)
  do update set next_seq = app.finance_settlement_number_counters.next_seq + 1
  returning next_seq - 1 into v_seq;
  v_number := 'SETL-' || v_year::text || '-' || lpad(v_seq::text, 6, '0');

  update app.finance_settlements
    set status = 'posted', settlement_number = v_number, posting_period_id = v_period.period_id,
        posted_by = p_actor_label, posted_at = now()
    where id = p_settlement_id
    returning * into v_settlement;

  perform app.capture_audit_event(
    v_settlement.tenant_id, p_actor_auth_user_id, p_actor_label, 'post_finance_settlement',
    'app.finance_settlements', v_settlement.id, 'success', null, null, to_jsonb(v_settlement)
  );

  return v_settlement;
end;
$function$;

revoke execute on function app.post_finance_settlement(p_settlement_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) from anon, authenticated, service_role, public;
grant execute on function app.post_finance_settlement(p_settlement_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) to authenticated;
grant execute on function app.post_finance_settlement(p_settlement_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) to service_role;

create function public.post_finance_settlement(p_settlement_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text default null)
 RETURNS app.finance_settlements
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
  select app.post_finance_settlement(p_settlement_id, p_expected_version, p_actor_auth_user_id, p_actor_label, p_client_ip);
$function$;

revoke execute on function public.post_finance_settlement(p_settlement_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) from anon, authenticated, service_role, public;
grant execute on function public.post_finance_settlement(p_settlement_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) to authenticated;
grant execute on function public.post_finance_settlement(p_settlement_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) to service_role;

-- 35. post_finance_vendor_bill -- authority shape: fin, tenant expression: v_bill.tenant_id [wrapper definer flag repaired -- live had drifted to invoker]
drop function public.post_finance_vendor_bill(p_bill_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text);
drop function app.post_finance_vendor_bill(p_bill_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text);

create function app.post_finance_vendor_bill(p_bill_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text default null)
 RETURNS app.finance_vendor_bills
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_bill app.finance_vendor_bills;
  v_period record;
  v_year integer;
  v_seq integer;
  v_number text;
  v_ap_item app.finance_ap_open_items;
  v_lines jsonb;
  v_tax_line app.finance_vendor_bill_lines;
  v_tax_rule app.finance_tax_rule_versions;
begin
  select * into v_bill from app.finance_vendor_bills where id = p_bill_id for update;
  if not found then
    raise exception 'finance_vendor_bill_not_found: %', p_bill_id using errcode = 'no_data_found';
  end if;
  if v_bill.status = 'posted' then
    return v_bill;
  end if;
  if not app.check_finance_vendor_bill_authority('Approve', v_bill.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:Approve for tenant %', p_actor_auth_user_id, v_bill.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  -- ISS-2026-302: IP allowlist, checked after authority is established and before any
  -- state change. Skipped when the caller supplies no address, and bypassable via the
  -- separately-governed app.ip_allowlist_bypass_grants -- the identical composition
  -- 20260826190000 established for the import-commit RPCs.
  if p_client_ip is not null and not app.has_active_ip_allowlist_bypass(v_bill.tenant_id, p_actor_auth_user_id) then
    perform app.assert_ip_allowed(v_bill.tenant_id, p_client_ip, 'admin', p_actor_label);
  end if;
  if v_bill.record_version <> p_expected_version then
    raise exception 'stale_version: bill % expected version % but found %', p_bill_id, p_expected_version, v_bill.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_bill.status <> 'approved' then
    raise exception 'finance_vendor_bill_not_approved: bill % is % not approved', p_bill_id, v_bill.status
      using errcode = 'check_violation';
  end if;

  select * into v_period from app.resolve_finance_period_for_date(v_bill.tenant_id, v_bill.company_id, v_bill.bill_date);
  if not found then
    raise exception 'finance_vendor_bill_period_not_found: no fiscal period covers %', v_bill.bill_date
      using errcode = 'no_data_found';
  end if;
  if not v_period.posting_eligible then
    raise exception 'finance_vendor_bill_period_not_open: fiscal period % for % is not open', v_period.period_code, v_bill.bill_date
      using errcode = 'check_violation';
  end if;

  v_year := extract(year from v_bill.bill_date)::integer;
  insert into app.finance_vendor_bill_number_counters (tenant_id, company_id, year, next_seq)
  values (v_bill.tenant_id, v_bill.company_id, v_year, 2)
  on conflict (tenant_id, coalesce(company_id, '00000000-0000-0000-0000-000000000000'::uuid), year)
  do update set next_seq = app.finance_vendor_bill_number_counters.next_seq + 1
  returning next_seq - 1 into v_seq;
  v_number := 'BILL-' || v_year::text || '-' || lpad(v_seq::text, 6, '0');

  select * into v_ap_item from app.post_finance_ap_open_item(
    v_bill.tenant_id, v_bill.company_id, v_bill.vendor_master_id, 'vendor_bill', v_bill.id,
    v_bill.currency, v_bill.total_amount, v_bill.bill_date, v_bill.due_date, p_actor_auth_user_id, p_actor_label
  );

  -- FIN-202: debit expense for the subtotal; debit each tax line's own
  -- governed recoverable account (or the input_tax_default posting-map key
  -- when none is configured); credit AP control for the full total.
  v_lines := '[]'::jsonb;
  if v_bill.subtotal_amount > 0 then
    v_lines := v_lines || jsonb_build_array(jsonb_build_object('postingMapKey', 'expense_default', 'direction', 'debit', 'amount', v_bill.subtotal_amount));
  end if;
  for v_tax_line in select * from app.finance_vendor_bill_lines where bill_id = p_bill_id and line_type = 'tax' and amount > 0 loop
    v_tax_rule := null;
    if v_tax_line.tax_rule_version_id is not null then
      select * into v_tax_rule from app.finance_tax_rule_versions where id = v_tax_line.tax_rule_version_id and recoverable_account_id is not null;
    end if;
    if v_tax_rule is not null then
      v_lines := v_lines || jsonb_build_array(jsonb_build_object('accountId', v_tax_rule.recoverable_account_id, 'direction', 'debit', 'amount', v_tax_line.amount));
    else
      v_lines := v_lines || jsonb_build_array(jsonb_build_object('postingMapKey', 'input_tax_default', 'direction', 'debit', 'amount', v_tax_line.amount));
    end if;
  end loop;
  v_lines := v_lines || jsonb_build_array(jsonb_build_object('postingMapKey', 'ap_control', 'direction', 'credit', 'amount', v_bill.total_amount, 'openItemType', 'ap_open_item', 'openItemId', v_ap_item.id));

  perform app.post_finance_subledger_batch(
    v_bill.tenant_id, v_bill.company_id, 'vendor_bill', v_bill.id, v_bill.bill_date, v_bill.currency,
    v_lines, p_actor_auth_user_id, p_actor_label
  );

  update app.finance_vendor_bills
    set status = 'posted', bill_number = v_number, posting_period_id = v_period.period_id, ap_open_item_id = v_ap_item.id,
        posted_by = p_actor_label, posted_at = now()
    where id = p_bill_id
    returning * into v_bill;

  perform app.capture_audit_event(
    v_bill.tenant_id, p_actor_auth_user_id, p_actor_label, 'post_finance_vendor_bill',
    'app.finance_vendor_bills', v_bill.id, 'success', null, null, to_jsonb(v_bill)
  );

  return v_bill;
end;
$function$;

revoke execute on function app.post_finance_vendor_bill(p_bill_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) from anon, authenticated, service_role, public;
grant execute on function app.post_finance_vendor_bill(p_bill_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) to authenticated;
grant execute on function app.post_finance_vendor_bill(p_bill_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) to service_role;

create function public.post_finance_vendor_bill(p_bill_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text default null)
 RETURNS app.finance_vendor_bills
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
  select app.post_finance_vendor_bill(p_bill_id, p_expected_version, p_actor_auth_user_id, p_actor_label, p_client_ip);
$function$;

revoke execute on function public.post_finance_vendor_bill(p_bill_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) from anon, authenticated, service_role, public;
grant execute on function public.post_finance_vendor_bill(p_bill_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) to authenticated;
grant execute on function public.post_finance_vendor_bill(p_bill_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) to service_role;

-- 36. publish_attendance_policy_version -- authority shape: eval, tenant expression: v_version.tenant_id
drop function public.publish_attendance_policy_version(p_version_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text);
drop function app.publish_attendance_policy_version(p_version_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text);

create function app.publish_attendance_policy_version(p_version_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text default null)
 RETURNS app.attendance_policy_versions
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'public', 'pg_temp'
AS $function$
declare
  v_decision app.rbac_decision;
  v_version app.attendance_policy_versions;
  v_policy app.attendance_policies;
begin
  select * into v_version from app.attendance_policy_versions where id = p_version_id for update;
  if not found or not app.has_active_tenant_membership(v_version.tenant_id, p_actor_auth_user_id) then
    raise exception 'policy_version_not_found: %', p_version_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_version.tenant_id, 'HRS', 'Approve');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks HRS:Approve (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_version.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  -- ISS-2026-302: IP allowlist, checked after authority is established and before any
  -- state change. Skipped when the caller supplies no address, and bypassable via the
  -- separately-governed app.ip_allowlist_bypass_grants -- the identical composition
  -- 20260826190000 established for the import-commit RPCs.
  if p_client_ip is not null and not app.has_active_ip_allowlist_bypass(v_version.tenant_id, p_actor_auth_user_id) then
    perform app.assert_ip_allowed(v_version.tenant_id, p_client_ip, 'admin', p_actor_label);
  end if;

  if v_version.record_version <> p_expected_version then
    raise exception 'stale_version: policy version % expected version % but found %', p_version_id, p_expected_version, v_version.record_version
      using errcode = 'serialization_failure';
  end if;

  if v_version.status <> 'draft' then
    raise exception 'invalid_transition: policy version % is %, only a draft may be published', p_version_id, v_version.status
      using errcode = 'check_violation';
  end if;

  update app.attendance_policy_versions
  set status = 'published', published_at = now(), published_by = p_actor_label
  where id = p_version_id and record_version = p_expected_version
  returning * into v_version;
  if not found then
    raise exception 'stale_version: policy version % target row was concurrently modified (expected version %)', p_version_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  update app.attendance_policies set status = 'published' where id = v_version.policy_id and status = 'draft';

  perform app.capture_audit_event(
    v_version.tenant_id, p_actor_auth_user_id, p_actor_label, 'publish_attendance_policy_version',
    'app.attendance_policy_versions', p_version_id, 'success', null, null, jsonb_build_object('effective_from', v_version.effective_from)
  );

  return v_version;
end;
$function$;

revoke execute on function app.publish_attendance_policy_version(p_version_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) from anon, authenticated, service_role, public;
grant execute on function app.publish_attendance_policy_version(p_version_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) to authenticated;
grant execute on function app.publish_attendance_policy_version(p_version_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) to service_role;

create function public.publish_attendance_policy_version(p_version_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text default null)
 RETURNS app.attendance_policy_versions
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
  select app.publish_attendance_policy_version(p_version_id, p_expected_version, p_actor_auth_user_id, p_actor_label, p_client_ip);
$function$;

revoke execute on function public.publish_attendance_policy_version(p_version_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) from anon, authenticated, service_role, public;
grant execute on function public.publish_attendance_policy_version(p_version_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) to authenticated;
grant execute on function public.publish_attendance_policy_version(p_version_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) to service_role;

-- 37. publish_finance_config_version -- authority shape: fin, tenant expression: v_object.tenant_id [wrapper definer flag repaired -- live had drifted to invoker]
drop function public.publish_finance_config_version(p_version_id uuid, p_actor_auth_user_id uuid, p_effective_from timestamp with time zone, p_actor_label text);
drop function app.publish_finance_config_version(p_version_id uuid, p_actor_auth_user_id uuid, p_effective_from timestamp with time zone, p_actor_label text);

create function app.publish_finance_config_version(p_version_id uuid, p_actor_auth_user_id uuid, p_effective_from timestamp with time zone, p_actor_label text, p_client_ip text default null)
 RETURNS app.config_versions
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_version app.config_versions;
  v_object app.config_objects;
  v_item record;
  v_ref text;
  v_account app.finance_accounts;
begin
  select * into v_version from app.config_versions where id = p_version_id;
  if not found then
    raise exception 'config_version_not_found: no config version %', p_version_id
      using errcode = 'no_data_found';
  end if;
  select * into v_object from app.config_objects where id = v_version.config_object_id;

  if not app.is_finance_config_type(v_object.config_type_code) then
    raise exception 'not_finance_config_type: % is not a Finance Configuration class', v_object.config_type_code
      using errcode = 'check_violation';
  end if;
  if not app.check_finance_config_authority('Approve', v_object.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:Approve for tenant %', p_actor_auth_user_id, v_object.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  -- ISS-2026-302: IP allowlist, checked after authority is established and before any
  -- state change. Skipped when the caller supplies no address, and bypassable via the
  -- separately-governed app.ip_allowlist_bypass_grants -- the identical composition
  -- 20260826190000 established for the import-commit RPCs.
  if p_client_ip is not null and not app.has_active_ip_allowlist_bypass(v_object.tenant_id, p_actor_auth_user_id) then
    perform app.assert_ip_allowed(v_object.tenant_id, p_client_ip, 'admin', p_actor_label);
  end if;

  perform app.validate_finance_config_version(p_version_id, v_object.config_type_code);

  -- FIN-192 addition: a finance_posting_map publish now also requires every
  -- referenced account code to resolve to an active, postable account in this
  -- tenant -- Prompt 191 section 25 / Prompt 192's own closed forward reference.
  if v_object.config_type_code = 'finance_posting_map' then
    for v_item in select key, value from app.config_items where config_version_id = p_version_id loop
      v_ref := v_item.value ->> 'accountCodeRef';
      select * into v_account from app.finance_accounts
        where tenant_id = v_object.tenant_id and code = v_ref
          and company_id is not distinct from case when v_object.scope_level = 'company' then v_object.scope_id else null end;
      if not found then
        raise exception 'finance_posting_map_unresolved_account: posting map key % references account code % which does not exist in this tenant''s chart of accounts', v_item.key, v_ref
          using errcode = 'check_violation';
      end if;
      if v_account.status <> 'active' then
        raise exception 'finance_posting_map_inactive_account: posting map key % references account code % which is not active (status=%)', v_item.key, v_ref, v_account.status
          using errcode = 'check_violation';
      end if;
      if not v_account.is_postable then
        raise exception 'finance_posting_map_not_postable_account: posting map key % references account code % which is not postable (control account)', v_item.key, v_ref
          using errcode = 'check_violation';
      end if;
    end loop;
  end if;

  return app.publish_config_version(p_version_id, p_actor_auth_user_id, p_effective_from, p_actor_label);
end;
$function$;

revoke execute on function app.publish_finance_config_version(p_version_id uuid, p_actor_auth_user_id uuid, p_effective_from timestamp with time zone, p_actor_label text, p_client_ip text) from anon, authenticated, service_role, public;
grant execute on function app.publish_finance_config_version(p_version_id uuid, p_actor_auth_user_id uuid, p_effective_from timestamp with time zone, p_actor_label text, p_client_ip text) to authenticated;
grant execute on function app.publish_finance_config_version(p_version_id uuid, p_actor_auth_user_id uuid, p_effective_from timestamp with time zone, p_actor_label text, p_client_ip text) to service_role;

create function public.publish_finance_config_version(p_version_id uuid, p_actor_auth_user_id uuid, p_effective_from timestamp with time zone, p_actor_label text, p_client_ip text default null)
 RETURNS app.config_versions
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
  select app.publish_finance_config_version(p_version_id, p_actor_auth_user_id, p_effective_from, p_actor_label, p_client_ip);
$function$;

revoke execute on function public.publish_finance_config_version(p_version_id uuid, p_actor_auth_user_id uuid, p_effective_from timestamp with time zone, p_actor_label text, p_client_ip text) from anon, authenticated, service_role, public;
grant execute on function public.publish_finance_config_version(p_version_id uuid, p_actor_auth_user_id uuid, p_effective_from timestamp with time zone, p_actor_label text, p_client_ip text) to authenticated;
grant execute on function public.publish_finance_config_version(p_version_id uuid, p_actor_auth_user_id uuid, p_effective_from timestamp with time zone, p_actor_label text, p_client_ip text) to service_role;

-- 38. publish_job_vacancy -- authority shape: eval, tenant expression: v_vacancy.tenant_id
drop function public.publish_job_vacancy(p_id uuid, p_expected_version integer, p_validity_days integer, p_actor_auth_user_id uuid, p_actor_label text);
drop function app.publish_job_vacancy(p_id uuid, p_expected_version integer, p_validity_days integer, p_actor_auth_user_id uuid, p_actor_label text);

create function app.publish_job_vacancy(p_id uuid, p_expected_version integer, p_validity_days integer, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text default null)
 RETURNS TABLE(vacancy app.job_vacancies, raw_posting_token text, posting_expires_at timestamp with time zone)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'public', 'extensions', 'pg_temp'
AS $function$
declare
  v_decision app.rbac_decision;
  v_vacancy app.job_vacancies;
  v_position app.positions;
  v_current_headcount integer;
  v_remaining integer;
  v_raw_token text;
  v_expires_at timestamptz;
begin
  select * into v_vacancy from app.job_vacancies where id = p_id;
  if not found or not app.has_active_tenant_membership(v_vacancy.tenant_id, p_actor_auth_user_id) then
    raise exception 'vacancy_not_found: %', p_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_vacancy.tenant_id, 'HRS', 'Approve');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks HRS:Approve (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_vacancy.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  -- ISS-2026-302: IP allowlist, checked after authority is established and before any
  -- state change. Skipped when the caller supplies no address, and bypassable via the
  -- separately-governed app.ip_allowlist_bypass_grants -- the identical composition
  -- 20260826190000 established for the import-commit RPCs.
  if p_client_ip is not null and not app.has_active_ip_allowlist_bypass(v_vacancy.tenant_id, p_actor_auth_user_id) then
    perform app.assert_ip_allowed(v_vacancy.tenant_id, p_client_ip, 'admin', p_actor_label);
  end if;

  if v_vacancy.record_version <> p_expected_version then
    raise exception 'stale_version: vacancy % expected version % but found %', p_id, p_expected_version, v_vacancy.record_version
      using errcode = 'serialization_failure';
  end if;

  if v_vacancy.status <> 'draft' then
    raise exception 'invalid_transition: vacancy % is % and cannot be published', p_id, v_vacancy.status
      using errcode = 'check_violation';
  end if;
  if coalesce(p_validity_days, 0) <= 0 then
    raise exception 'invalid_validity: validity_days must be positive' using errcode = 'check_violation';
  end if;

  select * into v_position from app.positions where id = v_vacancy.position_id for update;
  if v_position.status <> 'active' then
    raise exception 'position_inactive: position % is inactive and cannot be published against', v_vacancy.position_id using errcode = 'check_violation';
  end if;
  v_current_headcount := app.count_position_active_primary_headcount(v_position.id, daterange(current_date, current_date, '[]'));
  v_remaining := v_position.capacity - v_current_headcount;
  if v_vacancy.headcount > v_remaining then
    raise exception 'vacancy_headcount_exceeds_position_capacity: vacancy % requests % but position % has only % seat(s) remaining (capacity %, current headcount %)',
      p_id, v_vacancy.headcount, v_position.id, v_remaining, v_position.capacity, v_current_headcount
      using errcode = 'check_violation';
  end if;

  update app.job_vacancies
  set status = 'open', status_reason = null
  where id = p_id and record_version = p_expected_version
  returning * into v_vacancy;
  if not found then
    raise exception 'stale_version: vacancy % target row was concurrently modified (expected version %)', p_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  insert into app.job_vacancy_lifecycle_events (tenant_id, vacancy_id, from_status, to_status, actor_auth_user_id, actor_label)
  values (v_vacancy.tenant_id, p_id, 'draft', 'open', p_actor_auth_user_id, p_actor_label);

  v_raw_token := encode(gen_random_bytes(32), 'hex');
  v_expires_at := now() + (p_validity_days || ' days')::interval;

  insert into app.job_vacancy_postings (tenant_id, vacancy_id, posting_token, expires_at)
  values (v_vacancy.tenant_id, p_id, v_raw_token, v_expires_at);

  perform app.capture_audit_event(
    v_vacancy.tenant_id, p_actor_auth_user_id, p_actor_label, 'publish_job_vacancy',
    'app.job_vacancies', v_vacancy.id, 'success', null, null, app.job_vacancy_audit_projection(v_vacancy)
  );

  return query select v_vacancy, v_raw_token, v_expires_at;
end;
$function$;

revoke execute on function app.publish_job_vacancy(p_id uuid, p_expected_version integer, p_validity_days integer, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) from anon, authenticated, service_role, public;
grant execute on function app.publish_job_vacancy(p_id uuid, p_expected_version integer, p_validity_days integer, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) to authenticated;
grant execute on function app.publish_job_vacancy(p_id uuid, p_expected_version integer, p_validity_days integer, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) to service_role;

create function public.publish_job_vacancy(p_id uuid, p_expected_version integer, p_validity_days integer, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text default null)
 RETURNS TABLE(vacancy app.job_vacancies, raw_posting_token text, posting_expires_at timestamp with time zone)
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
  select * from app.publish_job_vacancy(p_id, p_expected_version, p_validity_days, p_actor_auth_user_id, p_actor_label, p_client_ip);
$function$;

revoke execute on function public.publish_job_vacancy(p_id uuid, p_expected_version integer, p_validity_days integer, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) from anon, authenticated, service_role, public;
grant execute on function public.publish_job_vacancy(p_id uuid, p_expected_version integer, p_validity_days integer, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) to authenticated;
grant execute on function public.publish_job_vacancy(p_id uuid, p_expected_version integer, p_validity_days integer, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) to service_role;

-- 39. publish_leave_type -- authority shape: eval, tenant expression: v_type.tenant_id
drop function public.publish_leave_type(p_leave_type_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text);
drop function app.publish_leave_type(p_leave_type_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text);

create function app.publish_leave_type(p_leave_type_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text default null)
 RETURNS app.leave_types
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_decision app.rbac_decision;
  v_type app.leave_types;
begin
  select * into v_type from app.leave_types where id = p_leave_type_id for update;
  if not found or not app.has_active_tenant_membership(v_type.tenant_id, p_actor_auth_user_id) then
    raise exception 'leave_type_not_found: %', p_leave_type_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_type.tenant_id, 'HRS', 'Approve');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks HRS:Approve (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_type.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  -- ISS-2026-302: IP allowlist, checked after authority is established and before any
  -- state change. Skipped when the caller supplies no address, and bypassable via the
  -- separately-governed app.ip_allowlist_bypass_grants -- the identical composition
  -- 20260826190000 established for the import-commit RPCs.
  if p_client_ip is not null and not app.has_active_ip_allowlist_bypass(v_type.tenant_id, p_actor_auth_user_id) then
    perform app.assert_ip_allowed(v_type.tenant_id, p_client_ip, 'admin', p_actor_label);
  end if;

  if v_type.record_version <> p_expected_version then
    raise exception 'stale_version: leave type % expected version % but found %', p_leave_type_id, p_expected_version, v_type.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_type.status <> 'draft' then
    raise exception 'invalid_transition: leave type % is %, only a draft may be published', p_leave_type_id, v_type.status
      using errcode = 'check_violation';
  end if;

  update app.leave_types set status = 'published' where id = p_leave_type_id and record_version = p_expected_version returning * into v_type;
  if not found then
    raise exception 'stale_version: leave type % target row was concurrently modified (expected version %)', p_leave_type_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_type.tenant_id, p_actor_auth_user_id, p_actor_label, 'publish_leave_type', 'app.leave_types', p_leave_type_id, 'success', null, null, '{}'::jsonb
  );

  return v_type;
end;
$function$;

revoke execute on function app.publish_leave_type(p_leave_type_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) from anon, authenticated, service_role, public;
grant execute on function app.publish_leave_type(p_leave_type_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) to authenticated;
grant execute on function app.publish_leave_type(p_leave_type_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) to service_role;

create function public.publish_leave_type(p_leave_type_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text default null)
 RETURNS app.leave_types
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
  select app.publish_leave_type(p_leave_type_id, p_expected_version, p_actor_auth_user_id, p_actor_label, p_client_ip);
$function$;

revoke execute on function public.publish_leave_type(p_leave_type_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) from anon, authenticated, service_role, public;
grant execute on function public.publish_leave_type(p_leave_type_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) to authenticated;
grant execute on function public.publish_leave_type(p_leave_type_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) to service_role;

-- 40. publish_leave_type_policy_version -- authority shape: eval, tenant expression: v_version.tenant_id
drop function public.publish_leave_type_policy_version(p_version_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text);
drop function app.publish_leave_type_policy_version(p_version_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text);

create function app.publish_leave_type_policy_version(p_version_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text default null)
 RETURNS app.leave_type_policy_versions
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_decision app.rbac_decision;
  v_version app.leave_type_policy_versions;
begin
  select * into v_version from app.leave_type_policy_versions where id = p_version_id for update;
  if not found or not app.has_active_tenant_membership(v_version.tenant_id, p_actor_auth_user_id) then
    raise exception 'policy_version_not_found: %', p_version_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_version.tenant_id, 'HRS', 'Approve');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks HRS:Approve (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_version.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  -- ISS-2026-302: IP allowlist, checked after authority is established and before any
  -- state change. Skipped when the caller supplies no address, and bypassable via the
  -- separately-governed app.ip_allowlist_bypass_grants -- the identical composition
  -- 20260826190000 established for the import-commit RPCs.
  if p_client_ip is not null and not app.has_active_ip_allowlist_bypass(v_version.tenant_id, p_actor_auth_user_id) then
    perform app.assert_ip_allowed(v_version.tenant_id, p_client_ip, 'admin', p_actor_label);
  end if;

  if v_version.record_version <> p_expected_version then
    raise exception 'stale_version: policy version % expected version % but found %', p_version_id, p_expected_version, v_version.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_version.status <> 'draft' then
    raise exception 'invalid_transition: policy version % is %, only a draft may be published', p_version_id, v_version.status
      using errcode = 'check_violation';
  end if;

  update app.leave_type_policy_versions
  set status = 'published', published_at = now(), published_by = p_actor_label
  where id = p_version_id and record_version = p_expected_version
  returning * into v_version;
  if not found then
    raise exception 'stale_version: policy version % target row was concurrently modified (expected version %)', p_version_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  update app.leave_types set status = 'published' where id = v_version.leave_type_id and status = 'draft';

  perform app.capture_audit_event(
    v_version.tenant_id, p_actor_auth_user_id, p_actor_label, 'publish_leave_type_policy_version',
    'app.leave_type_policy_versions', p_version_id, 'success', null, null, jsonb_build_object('effective_from', v_version.effective_from)
  );

  return v_version;
end;
$function$;

revoke execute on function app.publish_leave_type_policy_version(p_version_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) from anon, authenticated, service_role, public;
grant execute on function app.publish_leave_type_policy_version(p_version_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) to authenticated;
grant execute on function app.publish_leave_type_policy_version(p_version_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) to service_role;

create function public.publish_leave_type_policy_version(p_version_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text default null)
 RETURNS app.leave_type_policy_versions
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
  select app.publish_leave_type_policy_version(p_version_id, p_expected_version, p_actor_auth_user_id, p_actor_label, p_client_ip);
$function$;

revoke execute on function public.publish_leave_type_policy_version(p_version_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) from anon, authenticated, service_role, public;
grant execute on function public.publish_leave_type_policy_version(p_version_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) to authenticated;
grant execute on function public.publish_leave_type_policy_version(p_version_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) to service_role;

-- 41. publish_onboarding_checklist_template_version -- authority shape: eval, tenant expression: v_version.tenant_id
drop function public.publish_onboarding_checklist_template_version(p_template_version_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text);
drop function app.publish_onboarding_checklist_template_version(p_template_version_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text);

create function app.publish_onboarding_checklist_template_version(p_template_version_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text default null)
 RETURNS app.onboarding_checklist_template_versions
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_decision app.rbac_decision;
  v_version app.onboarding_checklist_template_versions;
  v_task_count integer;
begin
  select * into v_version from app.onboarding_checklist_template_versions where id = p_template_version_id for update;
  if not found or not app.has_active_tenant_membership(v_version.tenant_id, p_actor_auth_user_id) then
    raise exception 'template_version_not_found: %', p_template_version_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_version.tenant_id, 'HRS', 'Approve');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks HRS:Approve (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_version.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  -- ISS-2026-302: IP allowlist, checked after authority is established and before any
  -- state change. Skipped when the caller supplies no address, and bypassable via the
  -- separately-governed app.ip_allowlist_bypass_grants -- the identical composition
  -- 20260826190000 established for the import-commit RPCs.
  if p_client_ip is not null and not app.has_active_ip_allowlist_bypass(v_version.tenant_id, p_actor_auth_user_id) then
    perform app.assert_ip_allowed(v_version.tenant_id, p_client_ip, 'admin', p_actor_label);
  end if;

  if v_version.record_version <> p_expected_version then
    raise exception 'stale_version: template version % expected version % but found %', p_template_version_id, p_expected_version, v_version.record_version
      using errcode = 'serialization_failure';
  end if;

  if v_version.status <> 'draft' then
    raise exception 'invalid_transition: template version % is %, only a draft can be published', p_template_version_id, v_version.status
      using errcode = 'check_violation';
  end if;

  select count(*) into v_task_count from app.onboarding_checklist_template_tasks where template_version_id = p_template_version_id;
  if v_task_count = 0 then
    raise exception 'template_has_no_tasks: template version % has no tasks to publish', p_template_version_id using errcode = 'check_violation';
  end if;

  update app.onboarding_checklist_template_versions set status = 'superseded'
  where template_id = v_version.template_id and status = 'published';

  update app.onboarding_checklist_template_versions
  set status = 'published', published_at = now(), published_by = p_actor_label
  where id = p_template_version_id and record_version = p_expected_version
  returning * into v_version;
  if not found then
    raise exception 'stale_version: template version % target row was concurrently modified (expected version %)', p_template_version_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_version.tenant_id, p_actor_auth_user_id, p_actor_label, 'publish_onboarding_checklist_template_version',
    'app.onboarding_checklist_template_versions', v_version.id, 'success', null, null, to_jsonb(v_version)
  );

  return v_version;
end;
$function$;

revoke execute on function app.publish_onboarding_checklist_template_version(p_template_version_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) from anon, authenticated, service_role, public;
grant execute on function app.publish_onboarding_checklist_template_version(p_template_version_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) to authenticated;
grant execute on function app.publish_onboarding_checklist_template_version(p_template_version_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) to service_role;

create function public.publish_onboarding_checklist_template_version(p_template_version_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text default null)
 RETURNS app.onboarding_checklist_template_versions
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
  select app.publish_onboarding_checklist_template_version(p_template_version_id, p_expected_version, p_actor_auth_user_id, p_actor_label, p_client_ip);
$function$;

revoke execute on function public.publish_onboarding_checklist_template_version(p_template_version_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) from anon, authenticated, service_role, public;
grant execute on function public.publish_onboarding_checklist_template_version(p_template_version_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) to authenticated;
grant execute on function public.publish_onboarding_checklist_template_version(p_template_version_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) to service_role;

-- 42. publish_overtime_policy_version -- authority shape: eval, tenant expression: v_version.tenant_id
drop function public.publish_overtime_policy_version(p_version_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text);
drop function app.publish_overtime_policy_version(p_version_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text);

create function app.publish_overtime_policy_version(p_version_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text default null)
 RETURNS app.overtime_policy_versions
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_decision app.rbac_decision;
  v_version app.overtime_policy_versions;
begin
  select * into v_version from app.overtime_policy_versions where id = p_version_id for update;
  if not found or not app.has_active_tenant_membership(v_version.tenant_id, p_actor_auth_user_id) then
    raise exception 'policy_version_not_found: %', p_version_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_version.tenant_id, 'HRS', 'Approve');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks HRS:Approve (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_version.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  -- ISS-2026-302: IP allowlist, checked after authority is established and before any
  -- state change. Skipped when the caller supplies no address, and bypassable via the
  -- separately-governed app.ip_allowlist_bypass_grants -- the identical composition
  -- 20260826190000 established for the import-commit RPCs.
  if p_client_ip is not null and not app.has_active_ip_allowlist_bypass(v_version.tenant_id, p_actor_auth_user_id) then
    perform app.assert_ip_allowed(v_version.tenant_id, p_client_ip, 'admin', p_actor_label);
  end if;

  if v_version.record_version <> p_expected_version then
    raise exception 'stale_version: policy version % expected version % but found %', p_version_id, p_expected_version, v_version.record_version
      using errcode = 'serialization_failure';
  end if;

  if v_version.status <> 'draft' then
    raise exception 'invalid_transition: policy version % is %, only a draft may be published', p_version_id, v_version.status
      using errcode = 'check_violation';
  end if;

  update app.overtime_policy_versions
  set status = 'published', published_at = now(), published_by = p_actor_label
  where id = p_version_id and record_version = p_expected_version
  returning * into v_version;
  if not found then
    raise exception 'stale_version: policy version % target row was concurrently modified (expected version %)', p_version_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  update app.overtime_policies set status = 'published' where id = v_version.policy_id and status = 'draft';

  perform app.capture_audit_event(
    v_version.tenant_id, p_actor_auth_user_id, p_actor_label, 'publish_overtime_policy_version',
    'app.overtime_policy_versions', p_version_id, 'success', null, null, jsonb_build_object('effective_from', v_version.effective_from)
  );

  return v_version;
end;
$function$;

revoke execute on function app.publish_overtime_policy_version(p_version_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) from anon, authenticated, service_role, public;
grant execute on function app.publish_overtime_policy_version(p_version_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) to authenticated;
grant execute on function app.publish_overtime_policy_version(p_version_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) to service_role;

create function public.publish_overtime_policy_version(p_version_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text default null)
 RETURNS app.overtime_policy_versions
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
  select app.publish_overtime_policy_version(p_version_id, p_expected_version, p_actor_auth_user_id, p_actor_label, p_client_ip);
$function$;

revoke execute on function public.publish_overtime_policy_version(p_version_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) from anon, authenticated, service_role, public;
grant execute on function public.publish_overtime_policy_version(p_version_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) to authenticated;
grant execute on function public.publish_overtime_policy_version(p_version_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) to service_role;

-- 43. publish_roster_cycle -- authority shape: eval, tenant expression: v_cycle.tenant_id
drop function public.publish_roster_cycle(p_roster_cycle_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text);
drop function app.publish_roster_cycle(p_roster_cycle_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text);

create function app.publish_roster_cycle(p_roster_cycle_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text default null)
 RETURNS app.roster_cycles
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_decision app.rbac_decision;
  v_cycle app.roster_cycles;
  v_slot_count integer;
begin
  select * into v_cycle from app.roster_cycles where id = p_roster_cycle_id for update;
  if not found or not app.has_active_tenant_membership(v_cycle.tenant_id, p_actor_auth_user_id) then
    raise exception 'roster_cycle_not_found: %', p_roster_cycle_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_cycle.tenant_id, 'HRS', 'Approve');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks HRS:Approve (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_cycle.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  -- ISS-2026-302: IP allowlist, checked after authority is established and before any
  -- state change. Skipped when the caller supplies no address, and bypassable via the
  -- separately-governed app.ip_allowlist_bypass_grants -- the identical composition
  -- 20260826190000 established for the import-commit RPCs.
  if p_client_ip is not null and not app.has_active_ip_allowlist_bypass(v_cycle.tenant_id, p_actor_auth_user_id) then
    perform app.assert_ip_allowed(v_cycle.tenant_id, p_client_ip, 'admin', p_actor_label);
  end if;

  if v_cycle.record_version <> p_expected_version then
    raise exception 'stale_version: roster cycle % expected version % but found %', p_roster_cycle_id, p_expected_version, v_cycle.record_version
      using errcode = 'serialization_failure';
  end if;

  if v_cycle.status <> 'draft' then
    raise exception 'invalid_transition: roster cycle % is %, only a draft may be published', p_roster_cycle_id, v_cycle.status
      using errcode = 'check_violation';
  end if;

  select count(*) into v_slot_count from app.roster_cycle_slots where roster_cycle_id = p_roster_cycle_id;
  if v_slot_count <> v_cycle.cycle_length_days then
    raise exception 'incomplete_roster_cycle: cycle % has % of % day-offsets filled -- every offset must have a slot (day off is an explicit null shift) before publish', p_roster_cycle_id, v_slot_count, v_cycle.cycle_length_days
      using errcode = 'check_violation';
  end if;

  update app.roster_cycles set status = 'published' where id = p_roster_cycle_id and record_version = p_expected_version returning * into v_cycle;
  if not found then
    raise exception 'stale_version: roster cycle % target row was concurrently modified (expected version %)', p_roster_cycle_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_cycle.tenant_id, p_actor_auth_user_id, p_actor_label, 'publish_roster_cycle',
    'app.roster_cycles', p_roster_cycle_id, 'success', null, null, '{}'::jsonb
  );

  return v_cycle;
end;
$function$;

revoke execute on function app.publish_roster_cycle(p_roster_cycle_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) from anon, authenticated, service_role, public;
grant execute on function app.publish_roster_cycle(p_roster_cycle_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) to authenticated;
grant execute on function app.publish_roster_cycle(p_roster_cycle_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) to service_role;

create function public.publish_roster_cycle(p_roster_cycle_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text default null)
 RETURNS app.roster_cycles
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
  select app.publish_roster_cycle(p_roster_cycle_id, p_expected_version, p_actor_auth_user_id, p_actor_label, p_client_ip);
$function$;

revoke execute on function public.publish_roster_cycle(p_roster_cycle_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) from anon, authenticated, service_role, public;
grant execute on function public.publish_roster_cycle(p_roster_cycle_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) to authenticated;
grant execute on function public.publish_roster_cycle(p_roster_cycle_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) to service_role;

-- 44. publish_schedule_assignments -- authority shape: eval, tenant expression: p_tenant_id
drop function public.publish_schedule_assignments(p_tenant_id uuid, p_from_date date, p_to_date date, p_org_unit_id uuid, p_employee_id uuid, p_actor_auth_user_id uuid, p_actor_label text);
drop function app.publish_schedule_assignments(p_tenant_id uuid, p_from_date date, p_to_date date, p_org_unit_id uuid, p_employee_id uuid, p_actor_auth_user_id uuid, p_actor_label text);

create function app.publish_schedule_assignments(p_tenant_id uuid, p_from_date date, p_to_date date, p_org_unit_id uuid, p_employee_id uuid, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text default null)
 RETURNS TABLE(assignment_id uuid, published boolean, skip_reason text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_decision app.rbac_decision;
  v_row app.schedule_assignments;
  v_employee app.employees;
begin
  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'HRS', 'Approve');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks HRS:Approve (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  -- ISS-2026-302: IP allowlist, checked after authority is established and before any
  -- state change. Skipped when the caller supplies no address, and bypassable via the
  -- separately-governed app.ip_allowlist_bypass_grants -- the identical composition
  -- 20260826190000 established for the import-commit RPCs.
  if p_client_ip is not null and not app.has_active_ip_allowlist_bypass(p_tenant_id, p_actor_auth_user_id) then
    perform app.assert_ip_allowed(p_tenant_id, p_client_ip, 'admin', p_actor_label);
  end if;

  if p_from_date is null or p_to_date is null or p_to_date < p_from_date or (p_to_date - p_from_date) > 92 then
    raise exception 'invalid_date_range: date range must be non-empty and at most 92 days' using errcode = 'check_violation';
  end if;

  for v_row in
    select sa.* from app.schedule_assignments sa
    join app.employees e on e.master_record_id = sa.employee_id
    where sa.tenant_id = p_tenant_id and sa.work_date between p_from_date and p_to_date and sa.status = 'scheduled'
      and (p_employee_id is null or sa.employee_id = p_employee_id)
      and (p_org_unit_id is null or e.branch_org_unit_id = p_org_unit_id or e.department_org_unit_id = p_org_unit_id)
    for update of sa
  loop
    select * into v_employee from app.employees where master_record_id = v_row.employee_id;
    if v_employee.lifecycle_status <> 'active' then
      assignment_id := v_row.id; published := false; skip_reason := 'employee_not_active';
      return next;
      continue;
    end if;

    if not exists (select 1 from app.shift_template_versions where id = v_row.shift_template_version_id and status = 'published') then
      assignment_id := v_row.id; published := false; skip_reason := 'shift_template_version_not_published';
      return next;
      continue;
    end if;

    update app.schedule_assignments
    set status = 'published', published_at = now(), published_by = p_actor_label
    where id = v_row.id;

    assignment_id := v_row.id; published := true; skip_reason := null;
    return next;
  end loop;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'publish_schedule_assignments',
    'app.schedule_assignments', null, 'success', null, null, jsonb_build_object('from_date', p_from_date, 'to_date', p_to_date)
  );

  return;
end;
$function$;

revoke execute on function app.publish_schedule_assignments(p_tenant_id uuid, p_from_date date, p_to_date date, p_org_unit_id uuid, p_employee_id uuid, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) from anon, authenticated, service_role, public;
grant execute on function app.publish_schedule_assignments(p_tenant_id uuid, p_from_date date, p_to_date date, p_org_unit_id uuid, p_employee_id uuid, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) to authenticated;
grant execute on function app.publish_schedule_assignments(p_tenant_id uuid, p_from_date date, p_to_date date, p_org_unit_id uuid, p_employee_id uuid, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) to service_role;

create function public.publish_schedule_assignments(p_tenant_id uuid, p_from_date date, p_to_date date, p_org_unit_id uuid, p_employee_id uuid, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text default null)
 RETURNS TABLE(assignment_id uuid, published boolean, skip_reason text)
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
  select * from app.publish_schedule_assignments(p_tenant_id, p_from_date, p_to_date, p_org_unit_id, p_employee_id, p_actor_auth_user_id, p_actor_label, p_client_ip);
$function$;

revoke execute on function public.publish_schedule_assignments(p_tenant_id uuid, p_from_date date, p_to_date date, p_org_unit_id uuid, p_employee_id uuid, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) from anon, authenticated, service_role, public;
grant execute on function public.publish_schedule_assignments(p_tenant_id uuid, p_from_date date, p_to_date date, p_org_unit_id uuid, p_employee_id uuid, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) to authenticated;
grant execute on function public.publish_schedule_assignments(p_tenant_id uuid, p_from_date date, p_to_date date, p_org_unit_id uuid, p_employee_id uuid, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) to service_role;

-- 45. publish_shift_template_version -- authority shape: eval, tenant expression: v_version.tenant_id
drop function public.publish_shift_template_version(p_version_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text);
drop function app.publish_shift_template_version(p_version_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text);

create function app.publish_shift_template_version(p_version_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text default null)
 RETURNS app.shift_template_versions
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_decision app.rbac_decision;
  v_version app.shift_template_versions;
begin
  select * into v_version from app.shift_template_versions where id = p_version_id for update;
  if not found or not app.has_active_tenant_membership(v_version.tenant_id, p_actor_auth_user_id) then
    raise exception 'shift_template_version_not_found: %', p_version_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_version.tenant_id, 'HRS', 'Approve');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks HRS:Approve (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_version.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  -- ISS-2026-302: IP allowlist, checked after authority is established and before any
  -- state change. Skipped when the caller supplies no address, and bypassable via the
  -- separately-governed app.ip_allowlist_bypass_grants -- the identical composition
  -- 20260826190000 established for the import-commit RPCs.
  if p_client_ip is not null and not app.has_active_ip_allowlist_bypass(v_version.tenant_id, p_actor_auth_user_id) then
    perform app.assert_ip_allowed(v_version.tenant_id, p_client_ip, 'admin', p_actor_label);
  end if;

  if v_version.record_version <> p_expected_version then
    raise exception 'stale_version: shift template version % expected version % but found %', p_version_id, p_expected_version, v_version.record_version
      using errcode = 'serialization_failure';
  end if;

  if v_version.status <> 'draft' then
    raise exception 'invalid_transition: shift template version % is %, only a draft may be published', p_version_id, v_version.status
      using errcode = 'check_violation';
  end if;

  update app.shift_template_versions
  set status = 'published', published_at = now(), published_by = p_actor_label
  where id = p_version_id and record_version = p_expected_version
  returning * into v_version;
  if not found then
    raise exception 'stale_version: shift template version % target row was concurrently modified (expected version %)', p_version_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  update app.shift_templates set status = 'published' where id = v_version.shift_template_id and status = 'draft';

  perform app.capture_audit_event(
    v_version.tenant_id, p_actor_auth_user_id, p_actor_label, 'publish_shift_template_version',
    'app.shift_template_versions', p_version_id, 'success', null, null, jsonb_build_object('effective_from', v_version.effective_from)
  );

  return v_version;
end;
$function$;

revoke execute on function app.publish_shift_template_version(p_version_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) from anon, authenticated, service_role, public;
grant execute on function app.publish_shift_template_version(p_version_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) to authenticated;
grant execute on function app.publish_shift_template_version(p_version_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) to service_role;

create function public.publish_shift_template_version(p_version_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text default null)
 RETURNS app.shift_template_versions
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
  select app.publish_shift_template_version(p_version_id, p_expected_version, p_actor_auth_user_id, p_actor_label, p_client_ip);
$function$;

revoke execute on function public.publish_shift_template_version(p_version_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) from anon, authenticated, service_role, public;
grant execute on function public.publish_shift_template_version(p_version_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) to authenticated;
grant execute on function public.publish_shift_template_version(p_version_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) to service_role;

-- 46. record_direct_hire_approval -- authority shape: eval, tenant expression: v_case.tenant_id
drop function public.record_direct_hire_approval(p_case_id uuid, p_expected_version integer, p_note text, p_actor_auth_user_id uuid, p_actor_label text);
drop function app.record_direct_hire_approval(p_case_id uuid, p_expected_version integer, p_note text, p_actor_auth_user_id uuid, p_actor_label text);

create function app.record_direct_hire_approval(p_case_id uuid, p_expected_version integer, p_note text, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text default null)
 RETURNS app.onboarding_offboarding_cases
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_case app.onboarding_offboarding_cases;
  v_decision app.rbac_decision;
begin
  select * into v_case from app.onboarding_offboarding_cases where id = p_case_id for update;
  if not found or not app.has_active_tenant_membership(v_case.tenant_id, p_actor_auth_user_id) then
    raise exception 'case_not_found: %', p_case_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_case.tenant_id, 'HRS', 'Approve');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks HRS:Approve (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_case.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  -- ISS-2026-302: IP allowlist, checked after authority is established and before any
  -- state change. Skipped when the caller supplies no address, and bypassable via the
  -- separately-governed app.ip_allowlist_bypass_grants -- the identical composition
  -- 20260826190000 established for the import-commit RPCs.
  if p_client_ip is not null and not app.has_active_ip_allowlist_bypass(v_case.tenant_id, p_actor_auth_user_id) then
    perform app.assert_ip_allowed(v_case.tenant_id, p_client_ip, 'admin', p_actor_label);
  end if;

  if v_case.source_type <> 'direct_hire' then
    raise exception 'not_a_direct_hire_case: case % has source_type %, a direct-hire approval does not apply', p_case_id, v_case.source_type
      using errcode = 'check_violation';
  end if;

  if v_case.record_version <> p_expected_version then
    raise exception 'stale_version: case % expected version % but found %', p_case_id, p_expected_version, v_case.record_version
      using errcode = 'serialization_failure';
  end if;

  if v_case.status not in ('draft', 'active') then
    raise exception 'invalid_transition: case % is %, a direct-hire approval can only be recorded before finalize submission', p_case_id, v_case.status
      using errcode = 'check_violation';
  end if;

  if v_case.direct_hire_approved_at is not null then
    raise exception 'already_approved: case % was already approved as a direct hire at %', p_case_id, v_case.direct_hire_approved_at
      using errcode = 'check_violation';
  end if;

  if p_note is null or length(trim(p_note)) = 0 then
    raise exception 'approval_note_required: recording a direct-hire approval requires a justification note' using errcode = 'check_violation';
  end if;

  update app.onboarding_offboarding_cases
  set direct_hire_approved_by_auth_user_id = p_actor_auth_user_id,
      direct_hire_approved_at = now(),
      direct_hire_approval_note = trim(p_note)
  where id = p_case_id and record_version = p_expected_version
  returning * into v_case;
  if not found then
    raise exception 'stale_version: case % target row was concurrently modified (expected version %)', p_case_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  insert into app.onboarding_case_events (case_id, tenant_id, event_type, from_status, to_status, actor_auth_user_id, actor_label, notes)
  values (v_case.id, v_case.tenant_id, 'direct_hire_approved', v_case.status, v_case.status, p_actor_auth_user_id, p_actor_label, trim(p_note));

  perform app.capture_audit_event(
    v_case.tenant_id, p_actor_auth_user_id, p_actor_label, 'record_direct_hire_approval',
    'app.onboarding_offboarding_cases', v_case.id, 'success', null, null,
    jsonb_build_object('case_id', v_case.id, 'source_type', v_case.source_type, 'approved_at', v_case.direct_hire_approved_at)
  );

  return v_case;
end;
$function$;

revoke execute on function app.record_direct_hire_approval(p_case_id uuid, p_expected_version integer, p_note text, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) from anon, authenticated, service_role, public;
grant execute on function app.record_direct_hire_approval(p_case_id uuid, p_expected_version integer, p_note text, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) to authenticated;
grant execute on function app.record_direct_hire_approval(p_case_id uuid, p_expected_version integer, p_note text, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) to service_role;

create function public.record_direct_hire_approval(p_case_id uuid, p_expected_version integer, p_note text, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text default null)
 RETURNS app.onboarding_offboarding_cases
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'app', 'public', 'pg_temp'
AS $function$
  select * from app.record_direct_hire_approval(p_case_id, p_expected_version, p_note, p_actor_auth_user_id, p_actor_label, p_client_ip);
$function$;

revoke execute on function public.record_direct_hire_approval(p_case_id uuid, p_expected_version integer, p_note text, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) from anon, authenticated, service_role, public;
grant execute on function public.record_direct_hire_approval(p_case_id uuid, p_expected_version integer, p_note text, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) to authenticated;
grant execute on function public.record_direct_hire_approval(p_case_id uuid, p_expected_version integer, p_note text, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) to service_role;

-- 47. reject_timesheet_period_summary -- authority shape: eval, tenant expression: v_summary.tenant_id
drop function public.reject_timesheet_period_summary(p_summary_id uuid, p_expected_version integer, p_reason text, p_actor_auth_user_id uuid, p_actor_label text);
drop function app.reject_timesheet_period_summary(p_summary_id uuid, p_expected_version integer, p_reason text, p_actor_auth_user_id uuid, p_actor_label text);

create function app.reject_timesheet_period_summary(p_summary_id uuid, p_expected_version integer, p_reason text, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text default null)
 RETURNS app.timesheet_period_summaries
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_summary app.timesheet_period_summaries;
  v_decision app.rbac_decision;
  v_self app.employees;
begin
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'reason_required: a non-empty reason is required to reject a timesheet period summary' using errcode = 'check_violation';
  end if;

  select * into v_summary from app.timesheet_period_summaries where id = p_summary_id for update;
  if v_summary.id is null or not app.has_active_tenant_membership(v_summary.tenant_id, p_actor_auth_user_id) then
    raise exception 'timesheet_period_summary_not_found: %', p_summary_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_summary.tenant_id, 'HRS', 'Approve');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks HRS:Approve (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_summary.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  -- ISS-2026-302: IP allowlist, checked after authority is established and before any
  -- state change. Skipped when the caller supplies no address, and bypassable via the
  -- separately-governed app.ip_allowlist_bypass_grants -- the identical composition
  -- 20260826190000 established for the import-commit RPCs.
  if p_client_ip is not null and not app.has_active_ip_allowlist_bypass(v_summary.tenant_id, p_actor_auth_user_id) then
    perform app.assert_ip_allowed(v_summary.tenant_id, p_client_ip, 'admin', p_actor_label);
  end if;

  -- C-18 (RECURRING_DEFECT_TAXONOMY.md), self-found consistency gap: the
  -- sibling approve_timesheet_period_summary blocks self-decision; this
  -- reject counterpart did not. Low practical risk standing alone (a self-
  -- reject only sets the actor's own record back, granting nothing), but
  -- every OTHER decide-style function in this migration
  -- (decide_overtime_request, decide_timesheet_entry) blocks self on the
  -- WHOLE decide operation, not just its approve half -- matched here for
  -- the same uniform enforcement.
  v_self := app.get_self_employee(v_summary.tenant_id, p_actor_auth_user_id);
  if v_self.master_record_id is not null and v_self.master_record_id = v_summary.employee_id then
    raise exception 'self_approval_not_permitted: an actor may not decide their own timesheet period summary' using errcode = 'insufficient_privilege';
  end if;

  if v_summary.record_version <> p_expected_version then
    raise exception 'stale_version: timesheet period summary % expected version % but found %', p_summary_id, p_expected_version, v_summary.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_summary.status <> 'submitted' then
    raise exception 'invalid_transition: timesheet period summary % is %, only a submitted summary may be rejected', p_summary_id, v_summary.status
      using errcode = 'check_violation';
  end if;

  update app.timesheet_period_summaries
  set status = 'rejected', decided_by = p_actor_label, decided_at = now(), decided_reason = p_reason
  where id = p_summary_id and record_version = p_expected_version
  returning * into v_summary;
  if not found then
    raise exception 'stale_version: timesheet period summary % target row was concurrently modified (expected version %)', p_summary_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  -- Tier C batch review fix (Finding 5, HIGH, C-07): p_reason no longer
  -- routed into the unredacted audit_logs.reason column.
  perform app.capture_audit_event(
    v_summary.tenant_id, p_actor_auth_user_id, p_actor_label, 'reject_timesheet_period_summary',
    'app.timesheet_period_summaries', p_summary_id, 'success', null, null, '{}'::jsonb
  );

  return v_summary;
end;
$function$;

revoke execute on function app.reject_timesheet_period_summary(p_summary_id uuid, p_expected_version integer, p_reason text, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) from anon, authenticated, service_role, public;
grant execute on function app.reject_timesheet_period_summary(p_summary_id uuid, p_expected_version integer, p_reason text, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) to authenticated;
grant execute on function app.reject_timesheet_period_summary(p_summary_id uuid, p_expected_version integer, p_reason text, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) to service_role;

create function public.reject_timesheet_period_summary(p_summary_id uuid, p_expected_version integer, p_reason text, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text default null)
 RETURNS app.timesheet_period_summaries
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
  select app.reject_timesheet_period_summary(p_summary_id, p_expected_version, p_reason, p_actor_auth_user_id, p_actor_label, p_client_ip);
$function$;

revoke execute on function public.reject_timesheet_period_summary(p_summary_id uuid, p_expected_version integer, p_reason text, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) from anon, authenticated, service_role, public;
grant execute on function public.reject_timesheet_period_summary(p_summary_id uuid, p_expected_version integer, p_reason text, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) to authenticated;
grant execute on function public.reject_timesheet_period_summary(p_summary_id uuid, p_expected_version integer, p_reason text, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) to service_role;

-- 48. release_finance_ap_hold -- authority shape: fin, tenant expression: v_item.tenant_id [wrapper definer flag repaired -- live had drifted to invoker]
drop function public.release_finance_ap_hold(p_open_item_id uuid, p_expected_version integer, p_reason text, p_actor_auth_user_id uuid, p_actor_label text);
drop function app.release_finance_ap_hold(p_open_item_id uuid, p_expected_version integer, p_reason text, p_actor_auth_user_id uuid, p_actor_label text);

create function app.release_finance_ap_hold(p_open_item_id uuid, p_expected_version integer, p_reason text, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text default null)
 RETURNS app.finance_ap_open_items
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_item app.finance_ap_open_items;
begin
  select * into v_item from app.finance_ap_open_items where id = p_open_item_id for update;
  if not found then
    raise exception 'finance_ap_open_item_not_found: %', p_open_item_id using errcode = 'no_data_found';
  end if;
  if not app.check_finance_ap_authority('Approve', v_item.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:Approve for tenant %', p_actor_auth_user_id, v_item.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  -- ISS-2026-302: IP allowlist, checked after authority is established and before any
  -- state change. Skipped when the caller supplies no address, and bypassable via the
  -- separately-governed app.ip_allowlist_bypass_grants -- the identical composition
  -- 20260826190000 established for the import-commit RPCs.
  if p_client_ip is not null and not app.has_active_ip_allowlist_bypass(v_item.tenant_id, p_actor_auth_user_id) then
    perform app.assert_ip_allowed(v_item.tenant_id, p_client_ip, 'admin', p_actor_label);
  end if;
  if v_item.record_version <> p_expected_version then
    raise exception 'stale_version: open item % expected version % but found %', p_open_item_id, p_expected_version, v_item.record_version
      using errcode = 'serialization_failure';
  end if;
  if not v_item.is_held then
    raise exception 'finance_ap_not_held: open item % is not currently held', p_open_item_id
      using errcode = 'check_violation';
  end if;

  update app.finance_ap_open_items
    set is_held = false, released_by = p_actor_label, released_at = now()
    where id = p_open_item_id
    returning * into v_item;

  insert into app.finance_ap_open_item_events (tenant_id, open_item_id, event_type, reason, actor_auth_user_id, actor_label)
  values (v_item.tenant_id, v_item.id, 'hold_released', p_reason, p_actor_auth_user_id, p_actor_label);

  perform app.capture_audit_event(
    v_item.tenant_id, p_actor_auth_user_id, p_actor_label, 'release_finance_ap_hold',
    'app.finance_ap_open_items', v_item.id, 'success', p_reason, null, to_jsonb(v_item)
  );

  return v_item;
end;
$function$;

revoke execute on function app.release_finance_ap_hold(p_open_item_id uuid, p_expected_version integer, p_reason text, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) from anon, authenticated, service_role, public;
grant execute on function app.release_finance_ap_hold(p_open_item_id uuid, p_expected_version integer, p_reason text, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) to authenticated;
grant execute on function app.release_finance_ap_hold(p_open_item_id uuid, p_expected_version integer, p_reason text, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) to service_role;

create function public.release_finance_ap_hold(p_open_item_id uuid, p_expected_version integer, p_reason text, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text default null)
 RETURNS app.finance_ap_open_items
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
  select app.release_finance_ap_hold(p_open_item_id, p_expected_version, p_reason, p_actor_auth_user_id, p_actor_label, p_client_ip);
$function$;

revoke execute on function public.release_finance_ap_hold(p_open_item_id uuid, p_expected_version integer, p_reason text, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) from anon, authenticated, service_role, public;
grant execute on function public.release_finance_ap_hold(p_open_item_id uuid, p_expected_version integer, p_reason text, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) to authenticated;
grant execute on function public.release_finance_ap_hold(p_open_item_id uuid, p_expected_version integer, p_reason text, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) to service_role;

-- 49. release_finance_ar_hold -- authority shape: fin, tenant expression: v_item.tenant_id [wrapper definer flag repaired -- live had drifted to invoker]
drop function public.release_finance_ar_hold(p_open_item_id uuid, p_expected_version integer, p_reason text, p_actor_auth_user_id uuid, p_actor_label text);
drop function app.release_finance_ar_hold(p_open_item_id uuid, p_expected_version integer, p_reason text, p_actor_auth_user_id uuid, p_actor_label text);

create function app.release_finance_ar_hold(p_open_item_id uuid, p_expected_version integer, p_reason text, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text default null)
 RETURNS app.finance_ar_open_items
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_item app.finance_ar_open_items;
begin
  select * into v_item from app.finance_ar_open_items where id = p_open_item_id for update;
  if not found then
    raise exception 'finance_ar_open_item_not_found: %', p_open_item_id using errcode = 'no_data_found';
  end if;
  if not app.check_finance_ar_authority('Approve', v_item.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:Approve for tenant %', p_actor_auth_user_id, v_item.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  -- ISS-2026-302: IP allowlist, checked after authority is established and before any
  -- state change. Skipped when the caller supplies no address, and bypassable via the
  -- separately-governed app.ip_allowlist_bypass_grants -- the identical composition
  -- 20260826190000 established for the import-commit RPCs.
  if p_client_ip is not null and not app.has_active_ip_allowlist_bypass(v_item.tenant_id, p_actor_auth_user_id) then
    perform app.assert_ip_allowed(v_item.tenant_id, p_client_ip, 'admin', p_actor_label);
  end if;
  if v_item.record_version <> p_expected_version then
    raise exception 'stale_version: open item % expected version % but found %', p_open_item_id, p_expected_version, v_item.record_version
      using errcode = 'serialization_failure';
  end if;
  if not v_item.is_held then
    raise exception 'finance_ar_not_held: open item % is not currently held', p_open_item_id
      using errcode = 'check_violation';
  end if;

  update app.finance_ar_open_items
    set is_held = false, released_by = p_actor_label, released_at = now()
    where id = p_open_item_id
    returning * into v_item;

  insert into app.finance_ar_open_item_events (tenant_id, open_item_id, event_type, reason, actor_auth_user_id, actor_label)
  values (v_item.tenant_id, v_item.id, 'hold_released', p_reason, p_actor_auth_user_id, p_actor_label);

  perform app.capture_audit_event(
    v_item.tenant_id, p_actor_auth_user_id, p_actor_label, 'release_finance_ar_hold',
    'app.finance_ar_open_items', v_item.id, 'success', p_reason, null, to_jsonb(v_item)
  );

  return v_item;
end;
$function$;

revoke execute on function app.release_finance_ar_hold(p_open_item_id uuid, p_expected_version integer, p_reason text, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) from anon, authenticated, service_role, public;
grant execute on function app.release_finance_ar_hold(p_open_item_id uuid, p_expected_version integer, p_reason text, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) to authenticated;
grant execute on function app.release_finance_ar_hold(p_open_item_id uuid, p_expected_version integer, p_reason text, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) to service_role;

create function public.release_finance_ar_hold(p_open_item_id uuid, p_expected_version integer, p_reason text, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text default null)
 RETURNS app.finance_ar_open_items
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
  select app.release_finance_ar_hold(p_open_item_id, p_expected_version, p_reason, p_actor_auth_user_id, p_actor_label, p_client_ip);
$function$;

revoke execute on function public.release_finance_ar_hold(p_open_item_id uuid, p_expected_version integer, p_reason text, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) from anon, authenticated, service_role, public;
grant execute on function public.release_finance_ar_hold(p_open_item_id uuid, p_expected_version integer, p_reason text, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) to authenticated;
grant execute on function public.release_finance_ar_hold(p_open_item_id uuid, p_expected_version integer, p_reason text, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) to service_role;

-- 50. relock_finance_period -- authority shape: fin, tenant expression: v_lock.tenant_id [wrapper definer flag repaired -- live had drifted to invoker]
drop function public.relock_finance_period(p_lock_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text);
drop function app.relock_finance_period(p_lock_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text);

create function app.relock_finance_period(p_lock_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text default null)
 RETURNS app.finance_period_locks
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_lock app.finance_period_locks;
begin
  select * into v_lock from app.finance_period_locks where id = p_lock_id for update;
  if not found then
    raise exception 'finance_period_lock_not_found: %', p_lock_id using errcode = 'no_data_found';
  end if;
  if v_lock.status = 'locked' then
    return v_lock;
  end if;
  if not app.check_finance_period_lock_authority('Approve', v_lock.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:Approve for tenant %', p_actor_auth_user_id, v_lock.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  -- ISS-2026-302: IP allowlist, checked after authority is established and before any
  -- state change. Skipped when the caller supplies no address, and bypassable via the
  -- separately-governed app.ip_allowlist_bypass_grants -- the identical composition
  -- 20260826190000 established for the import-commit RPCs.
  if p_client_ip is not null and not app.has_active_ip_allowlist_bypass(v_lock.tenant_id, p_actor_auth_user_id) then
    perform app.assert_ip_allowed(v_lock.tenant_id, p_client_ip, 'admin', p_actor_label);
  end if;
  if v_lock.record_version <> p_expected_version then
    raise exception 'stale_version: lock % expected version % but found %', p_lock_id, p_expected_version, v_lock.record_version
      using errcode = 'serialization_failure';
  end if;

  update app.finance_period_locks
    set status = 'locked', relocked_by = p_actor_label, relocked_at = now()
    where id = p_lock_id
    returning * into v_lock;

  insert into app.finance_period_lock_events (lock_id, tenant_id, action, reason, actor_label) values (v_lock.id, v_lock.tenant_id, 'relocked', null, p_actor_label);

  perform app.capture_audit_event(
    v_lock.tenant_id, p_actor_auth_user_id, p_actor_label, 'relock_finance_period',
    'app.finance_period_locks', v_lock.id, 'success', null, null, to_jsonb(v_lock)
  );

  return v_lock;
end;
$function$;

revoke execute on function app.relock_finance_period(p_lock_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) from anon, authenticated, service_role, public;
grant execute on function app.relock_finance_period(p_lock_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) to authenticated;
grant execute on function app.relock_finance_period(p_lock_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) to service_role;

create function public.relock_finance_period(p_lock_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text default null)
 RETURNS app.finance_period_locks
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
  select app.relock_finance_period(p_lock_id, p_expected_version, p_actor_auth_user_id, p_actor_label, p_client_ip);
$function$;

revoke execute on function public.relock_finance_period(p_lock_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) from anon, authenticated, service_role, public;
grant execute on function public.relock_finance_period(p_lock_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) to authenticated;
grant execute on function public.relock_finance_period(p_lock_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) to service_role;

-- 51. reopen_finance_period -- authority shape: fin, tenant expression: v_period.tenant_id [wrapper definer flag repaired -- live had drifted to invoker]
drop function public.reopen_finance_period(p_period_id uuid, p_expected_version integer, p_reason text, p_actor_auth_user_id uuid, p_actor_label text);
drop function app.reopen_finance_period(p_period_id uuid, p_expected_version integer, p_reason text, p_actor_auth_user_id uuid, p_actor_label text);

create function app.reopen_finance_period(p_period_id uuid, p_expected_version integer, p_reason text, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text default null)
 RETURNS app.finance_fiscal_periods
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_period app.finance_fiscal_periods;
begin
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'finance_period_reopen_reason_required: a non-empty reason is required'
      using errcode = 'check_violation';
  end if;

  select * into v_period from app.finance_fiscal_periods where id = p_period_id;
  if not found then
    raise exception 'finance_period_not_found: %', p_period_id using errcode = 'no_data_found';
  end if;

  if v_period.record_version <> p_expected_version then
    raise exception 'stale_version: period % expected version % but found %', p_period_id, p_expected_version, v_period.record_version
      using errcode = 'serialization_failure';
  end if;

  if v_period.status <> 'closed' then
    raise exception 'finance_period_not_closed: period % is %, only a closed period may be reopened', p_period_id, v_period.status
      using errcode = 'check_violation';
  end if;

  if not app.check_finance_period_authority('Approve', v_period.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:Approve for tenant %', p_actor_auth_user_id, v_period.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  -- ISS-2026-302: IP allowlist, checked after authority is established and before any
  -- state change. Skipped when the caller supplies no address, and bypassable via the
  -- separately-governed app.ip_allowlist_bypass_grants -- the identical composition
  -- 20260826190000 established for the import-commit RPCs.
  if p_client_ip is not null and not app.has_active_ip_allowlist_bypass(v_period.tenant_id, p_actor_auth_user_id) then
    perform app.assert_ip_allowed(v_period.tenant_id, p_client_ip, 'admin', p_actor_label);
  end if;

  update app.finance_fiscal_periods
  set status = 'open', closed_at = null, closed_by = null
  where id = p_period_id and record_version = p_expected_version
  returning * into v_period;
  -- ATW-032 (ISS-2026-034): the version predicate above already PREVENTS the lost
  -- update -- the loser's UPDATE simply matches no row. What it did not do was say so:
  -- execution fell straight through with a NULL composite, so the audit trail gained a
  -- fabricated 'success' row with a NULL tenant_id and the caller was handed an all-NULL
  -- record instead of the 'stale_version' its own error contract already handles.
  if not found then
    raise exception 'stale_version: reopen_finance_period target row was concurrently modified (expected version %)', p_expected_version
      using errcode = 'serialization_failure';
  end if;

  insert into app.finance_period_transitions (period_id, tenant_id, from_status, to_status, reason, actor_auth_user_id, actor_label)
  values (p_period_id, v_period.tenant_id, 'closed', 'open', p_reason, p_actor_auth_user_id, p_actor_label);

  perform app.capture_audit_event(
    v_period.tenant_id, p_actor_auth_user_id, p_actor_label, 'reopen_finance_period',
    'app.finance_fiscal_periods', v_period.id, 'success', p_reason, null, to_jsonb(v_period)
  );

  return v_period;
end;
$function$;

revoke execute on function app.reopen_finance_period(p_period_id uuid, p_expected_version integer, p_reason text, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) from anon, authenticated, service_role, public;
grant execute on function app.reopen_finance_period(p_period_id uuid, p_expected_version integer, p_reason text, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) to authenticated;
grant execute on function app.reopen_finance_period(p_period_id uuid, p_expected_version integer, p_reason text, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) to service_role;

create function public.reopen_finance_period(p_period_id uuid, p_expected_version integer, p_reason text, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text default null)
 RETURNS app.finance_fiscal_periods
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
  select app.reopen_finance_period(p_period_id, p_expected_version, p_reason, p_actor_auth_user_id, p_actor_label, p_client_ip);
$function$;

revoke execute on function public.reopen_finance_period(p_period_id uuid, p_expected_version integer, p_reason text, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) from anon, authenticated, service_role, public;
grant execute on function public.reopen_finance_period(p_period_id uuid, p_expected_version integer, p_reason text, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) to authenticated;
grant execute on function public.reopen_finance_period(p_period_id uuid, p_expected_version integer, p_reason text, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) to service_role;

-- 52. request_finance_receipt_deallocation -- authority shape: fin, tenant expression: v_allocation.tenant_id [wrapper definer flag repaired -- live had drifted to invoker]
drop function public.request_finance_receipt_deallocation(p_allocation_id uuid, p_reason text, p_actor_auth_user_id uuid, p_actor_label text);
drop function app.request_finance_receipt_deallocation(p_allocation_id uuid, p_reason text, p_actor_auth_user_id uuid, p_actor_label text);

create function app.request_finance_receipt_deallocation(p_allocation_id uuid, p_reason text, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text default null)
 RETURNS app.finance_receipts
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_allocation app.finance_receipt_allocations;
  v_receipt app.finance_receipts;
begin
  select * into v_allocation from app.finance_receipt_allocations where id = p_allocation_id for update;
  if not found then
    raise exception 'finance_receipt_allocation_not_found: %', p_allocation_id using errcode = 'no_data_found';
  end if;
  if not app.check_finance_receipt_authority('Approve', v_allocation.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:Approve for tenant %', p_actor_auth_user_id, v_allocation.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  -- ISS-2026-302: IP allowlist, checked after authority is established and before any
  -- state change. Skipped when the caller supplies no address, and bypassable via the
  -- separately-governed app.ip_allowlist_bypass_grants -- the identical composition
  -- 20260826190000 established for the import-commit RPCs.
  if p_client_ip is not null and not app.has_active_ip_allowlist_bypass(v_allocation.tenant_id, p_actor_auth_user_id) then
    perform app.assert_ip_allowed(v_allocation.tenant_id, p_client_ip, 'admin', p_actor_label);
  end if;
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'finance_receipt_deallocation_reason_required: a non-empty reason is required to reverse an allocation'
      using errcode = 'check_violation';
  end if;
  if v_allocation.status <> 'applied' then
    raise exception 'finance_receipt_allocation_not_applied: allocation % is % not applied', p_allocation_id, v_allocation.status
      using errcode = 'check_violation';
  end if;

  perform app.reverse_finance_ar_allocation(
    v_allocation.ar_open_item_id, v_allocation.amount, p_reason, 'receipt', v_allocation.receipt_id,
    'dealloc:' || v_allocation.id::text, p_actor_auth_user_id, p_actor_label
  );

  update app.finance_receipt_allocations set status = 'reversed', reason = p_reason, reversed_by = p_actor_label, reversed_at = now() where id = p_allocation_id;

  update app.finance_receipts set allocated_amount = allocated_amount - v_allocation.amount where id = v_allocation.receipt_id returning * into v_receipt;

  perform app.capture_audit_event(
    v_allocation.tenant_id, p_actor_auth_user_id, p_actor_label, 'request_finance_receipt_deallocation',
    'app.finance_receipt_allocations', v_allocation.id, 'success', p_reason, null, jsonb_build_object('amount', v_allocation.amount)
  );

  return v_receipt;
end;
$function$;

revoke execute on function app.request_finance_receipt_deallocation(p_allocation_id uuid, p_reason text, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) from anon, authenticated, service_role, public;
grant execute on function app.request_finance_receipt_deallocation(p_allocation_id uuid, p_reason text, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) to authenticated;
grant execute on function app.request_finance_receipt_deallocation(p_allocation_id uuid, p_reason text, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) to service_role;

create function public.request_finance_receipt_deallocation(p_allocation_id uuid, p_reason text, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text default null)
 RETURNS app.finance_receipts
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
  select app.request_finance_receipt_deallocation(p_allocation_id, p_reason, p_actor_auth_user_id, p_actor_label, p_client_ip);
$function$;

revoke execute on function public.request_finance_receipt_deallocation(p_allocation_id uuid, p_reason text, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) from anon, authenticated, service_role, public;
grant execute on function public.request_finance_receipt_deallocation(p_allocation_id uuid, p_reason text, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) to authenticated;
grant execute on function public.request_finance_receipt_deallocation(p_allocation_id uuid, p_reason text, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) to service_role;

-- 53. request_finance_settlement_reversal -- authority shape: fin, tenant expression: v_settlement.tenant_id
drop function public.request_finance_settlement_reversal(p_settlement_id uuid, p_reason text, p_actor_auth_user_id uuid, p_actor_label text);
drop function app.request_finance_settlement_reversal(p_settlement_id uuid, p_reason text, p_actor_auth_user_id uuid, p_actor_label text);

create function app.request_finance_settlement_reversal(p_settlement_id uuid, p_reason text, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text default null)
 RETURNS app.finance_settlements
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_settlement app.finance_settlements;
  v_allocation app.finance_settlement_allocations;
  v_period record;
  v_batch app.finance_subledger_batches;
  v_original_journal app.finance_journals;
  v_reversal_lines jsonb := '[]'::jsonb;
  v_line record;
  v_flipped text;
  v_correction app.finance_journal_corrections;
  v_reversal_journal app.finance_journals;
begin
  select * into v_settlement from app.finance_settlements where id = p_settlement_id for update;
  if not found then
    raise exception 'finance_settlement_not_found: %', p_settlement_id using errcode = 'no_data_found';
  end if;
  if not app.check_finance_settlement_authority('Approve', v_settlement.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:Approve for tenant %', p_actor_auth_user_id, v_settlement.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  -- ISS-2026-302: IP allowlist, checked after authority is established and before any
  -- state change. Skipped when the caller supplies no address, and bypassable via the
  -- separately-governed app.ip_allowlist_bypass_grants -- the identical composition
  -- 20260826190000 established for the import-commit RPCs.
  if p_client_ip is not null and not app.has_active_ip_allowlist_bypass(v_settlement.tenant_id, p_actor_auth_user_id) then
    perform app.assert_ip_allowed(v_settlement.tenant_id, p_client_ip, 'admin', p_actor_label);
  end if;
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'finance_settlement_reversal_reason_required: a non-empty reason is required to reverse a posted settlement'
      using errcode = 'check_violation';
  end if;
  if v_settlement.status <> 'posted' then
    raise exception 'finance_settlement_not_posted: settlement % is % not posted', p_settlement_id, v_settlement.status
      using errcode = 'check_violation';
  end if;

  select * into v_period from app.resolve_finance_period_for_date(v_settlement.tenant_id, v_settlement.company_id, v_settlement.settlement_date);
  if not found then
    raise exception 'finance_settlement_reversal_period_not_found: no fiscal period covers %', v_settlement.settlement_date
      using errcode = 'no_data_found';
  end if;
  if not v_period.posting_eligible then
    raise exception 'finance_settlement_reversal_period_not_open: fiscal period % for % is not open', v_period.period_code, v_settlement.settlement_date
      using errcode = 'check_violation';
  end if;

  select * into v_batch from app.finance_subledger_batches where tenant_id = v_settlement.tenant_id and source_type = 'settlement' and source_id = v_settlement.id;
  if not found or v_batch.gl_journal_id is null then
    raise exception 'finance_settlement_reversal_batch_not_found: settlement % has no posted subledger batch/GL journal to reverse -- data integrity anomaly', p_settlement_id
      using errcode = 'no_data_found';
  end if;
  select * into v_original_journal from app.finance_journals where id = v_batch.gl_journal_id;
  if not found or v_original_journal.status <> 'posted' then
    raise exception 'finance_settlement_reversal_journal_not_posted: journal % for settlement % is not posted', v_batch.gl_journal_id, p_settlement_id
      using errcode = 'check_violation';
  end if;

  for v_line in select direction, account_id, amount, dimension from app.finance_journal_lines where journal_id = v_original_journal.id order by line_number asc loop
    v_flipped := case when v_line.direction = 'debit' then 'credit' else 'debit' end;
    v_reversal_lines := v_reversal_lines || jsonb_build_array(jsonb_build_object('accountId', v_line.account_id, 'direction', v_flipped, 'amount', v_line.amount, 'dimension', v_line.dimension));
  end loop;

  insert into app.finance_journal_corrections (
    tenant_id, company_id, original_journal_id, correction_type, correction_date, reason, evidence_ref, adjustment_lines,
    status, idempotency_key, submitted_by, submitted_at, approved_by, approved_at, created_by
  )
  values (
    v_settlement.tenant_id, v_settlement.company_id, v_original_journal.id, 'reversal', v_settlement.settlement_date, p_reason, null, null,
    'approved', 'settlement_reversal:' || v_settlement.id::text, p_actor_label, now(), p_actor_label, now(), p_actor_label
  )
  returning * into v_correction;

  select * into v_reversal_journal from app.create_and_post_finance_system_journal(
    v_settlement.tenant_id, v_settlement.company_id, 'correction', v_correction.id, v_settlement.settlement_date,
    v_original_journal.currency, v_reversal_lines, p_actor_auth_user_id, p_actor_label, 'ap'
  );

  update app.finance_journal_corrections
    set status = 'posted', correction_journal_id = v_reversal_journal.id, posted_by = p_actor_label, posted_at = now()
    where id = v_correction.id
    returning * into v_correction;

  update app.finance_subledger_batches set status = 'reversed' where id = v_batch.id and status = 'posted';

  perform app.capture_audit_event(
    v_settlement.tenant_id, p_actor_auth_user_id, p_actor_label, 'post_finance_correction',
    'app.finance_journal_corrections', v_correction.id, 'success', p_reason, null, to_jsonb(v_correction)
  );

  for v_allocation in select * from app.finance_settlement_allocations where settlement_id = p_settlement_id and status = 'applied' order by created_at asc loop
    perform app.reverse_finance_ap_settlement(
      v_allocation.ap_open_item_id, v_allocation.amount, p_reason, 'settlement', v_settlement.id,
      'reversal:' || v_settlement.id::text || ':' || v_allocation.ap_open_item_id::text, p_actor_auth_user_id, p_actor_label
    );
    update app.finance_settlement_allocations set status = 'reversed', reason = p_reason, reversed_by = p_actor_label, reversed_at = now() where id = v_allocation.id;
  end loop;

  update app.finance_settlements set status = 'reversed', void_reason = p_reason, voided_by = p_actor_label, voided_at = now() where id = p_settlement_id returning * into v_settlement;

  perform app.capture_audit_event(
    v_settlement.tenant_id, p_actor_auth_user_id, p_actor_label, 'request_finance_settlement_reversal',
    'app.finance_settlements', v_settlement.id, 'success', p_reason, null, to_jsonb(v_settlement)
  );

  return v_settlement;
end;
$function$;

revoke execute on function app.request_finance_settlement_reversal(p_settlement_id uuid, p_reason text, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) from anon, authenticated, service_role, public;
grant execute on function app.request_finance_settlement_reversal(p_settlement_id uuid, p_reason text, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) to authenticated;
grant execute on function app.request_finance_settlement_reversal(p_settlement_id uuid, p_reason text, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) to service_role;

create function public.request_finance_settlement_reversal(p_settlement_id uuid, p_reason text, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text default null)
 RETURNS app.finance_settlements
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
  select app.request_finance_settlement_reversal(p_settlement_id, p_reason, p_actor_auth_user_id, p_actor_label, p_client_ip);
$function$;

revoke execute on function public.request_finance_settlement_reversal(p_settlement_id uuid, p_reason text, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) from anon, authenticated, service_role, public;
grant execute on function public.request_finance_settlement_reversal(p_settlement_id uuid, p_reason text, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) to authenticated;
grant execute on function public.request_finance_settlement_reversal(p_settlement_id uuid, p_reason text, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) to service_role;

-- 54. request_ip_allowlist_bypass -- authority shape: eval, tenant expression: p_tenant_id
drop function public.request_ip_allowlist_bypass(p_tenant_id uuid, p_target_auth_user_id uuid, p_reason text, p_actor_auth_user_id uuid, p_actor_label text);
drop function app.request_ip_allowlist_bypass(p_tenant_id uuid, p_target_auth_user_id uuid, p_reason text, p_actor_auth_user_id uuid, p_actor_label text);

create function app.request_ip_allowlist_bypass(p_tenant_id uuid, p_target_auth_user_id uuid, p_reason text, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text default null)
 RETURNS app.ip_allowlist_bypass_grants
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_decision app.rbac_decision;
  v_grant app.ip_allowlist_bypass_grants;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'SEC', 'Configure');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks SEC:Configure (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  -- ISS-2026-302: IP allowlist, checked after authority is established and before any
  -- state change. Skipped when the caller supplies no address, and bypassable via the
  -- separately-governed app.ip_allowlist_bypass_grants -- the identical composition
  -- 20260826190000 established for the import-commit RPCs.
  if p_client_ip is not null and not app.has_active_ip_allowlist_bypass(p_tenant_id, p_actor_auth_user_id) then
    perform app.assert_ip_allowed(p_tenant_id, p_client_ip, 'admin', p_actor_label);
  end if;

  if coalesce(length(trim(p_reason)), 0) = 0 then
    raise exception 'ip_bypass_reason_required: a non-empty reason is required' using errcode = 'check_violation';
  end if;

  -- Tier C review fix (security/RLS/tenant lens, Low): identical fix to
  -- app.request_mfa_exception's own -- p_target_auth_user_id was accepted
  -- with no check that it actually belongs to p_tenant_id.
  if not app.has_active_tenant_membership(p_tenant_id, p_target_auth_user_id) then
    raise exception 'ip_bypass_target_not_tenant_member: % is not an active member of tenant %', p_target_auth_user_id, p_tenant_id
      using errcode = 'check_violation';
  end if;

  insert into app.ip_allowlist_bypass_grants (tenant_id, target_auth_user_id, reason, requested_by_auth_user_id, requested_by)
  values (p_tenant_id, p_target_auth_user_id, p_reason, p_actor_auth_user_id, p_actor_label)
  returning * into v_grant;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'request_ip_allowlist_bypass',
    'app.ip_allowlist_bypass_grants', v_grant.id, 'success', p_reason, null, to_jsonb(v_grant)
  );

  return v_grant;
end;
$function$;

revoke execute on function app.request_ip_allowlist_bypass(p_tenant_id uuid, p_target_auth_user_id uuid, p_reason text, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) from anon, authenticated, service_role, public;
grant execute on function app.request_ip_allowlist_bypass(p_tenant_id uuid, p_target_auth_user_id uuid, p_reason text, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) to authenticated;
grant execute on function app.request_ip_allowlist_bypass(p_tenant_id uuid, p_target_auth_user_id uuid, p_reason text, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) to service_role;

create function public.request_ip_allowlist_bypass(p_tenant_id uuid, p_target_auth_user_id uuid, p_reason text, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text default null)
 RETURNS app.ip_allowlist_bypass_grants
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
  select app.request_ip_allowlist_bypass(p_tenant_id, p_target_auth_user_id, p_reason, p_actor_auth_user_id, p_actor_label, p_client_ip);
$function$;

revoke execute on function public.request_ip_allowlist_bypass(p_tenant_id uuid, p_target_auth_user_id uuid, p_reason text, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) from anon, authenticated, service_role, public;
grant execute on function public.request_ip_allowlist_bypass(p_tenant_id uuid, p_target_auth_user_id uuid, p_reason text, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) to authenticated;
grant execute on function public.request_ip_allowlist_bypass(p_tenant_id uuid, p_target_auth_user_id uuid, p_reason text, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) to service_role;

-- 55. request_mfa_exception -- authority shape: eval, tenant expression: p_tenant_id
drop function public.request_mfa_exception(p_tenant_id uuid, p_target_auth_user_id uuid, p_reason text, p_actor_auth_user_id uuid, p_actor_label text);
drop function app.request_mfa_exception(p_tenant_id uuid, p_target_auth_user_id uuid, p_reason text, p_actor_auth_user_id uuid, p_actor_label text);

create function app.request_mfa_exception(p_tenant_id uuid, p_target_auth_user_id uuid, p_reason text, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text default null)
 RETURNS app.mfa_exceptions
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_decision app.rbac_decision;
  v_exception app.mfa_exceptions;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'SEC', 'Configure');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks SEC:Configure (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  -- ISS-2026-302: IP allowlist, checked after authority is established and before any
  -- state change. Skipped when the caller supplies no address, and bypassable via the
  -- separately-governed app.ip_allowlist_bypass_grants -- the identical composition
  -- 20260826190000 established for the import-commit RPCs.
  if p_client_ip is not null and not app.has_active_ip_allowlist_bypass(p_tenant_id, p_actor_auth_user_id) then
    perform app.assert_ip_allowed(p_tenant_id, p_client_ip, 'admin', p_actor_label);
  end if;

  if coalesce(length(trim(p_reason)), 0) = 0 then
    raise exception 'mfa_exception_reason_required: a non-empty reason is required' using errcode = 'check_violation';
  end if;

  -- Tier C review fix (security/RLS/tenant lens, Low): p_target_auth_user_id
  -- was accepted with no check that it actually belongs to p_tenant_id --
  -- referential-integrity gap, not itself a live bypass (this row is only
  -- ever consulted by tenant-scoped enforcement that separately re-checks
  -- the actor's own tenant standing), but worth closing rather than leaving
  -- an orphaned/meaningless row reachable.
  if not app.has_active_tenant_membership(p_tenant_id, p_target_auth_user_id) then
    raise exception 'mfa_exception_target_not_tenant_member: % is not an active member of tenant %', p_target_auth_user_id, p_tenant_id
      using errcode = 'check_violation';
  end if;

  insert into app.mfa_exceptions (tenant_id, target_auth_user_id, reason, requested_by_auth_user_id, requested_by)
  values (p_tenant_id, p_target_auth_user_id, p_reason, p_actor_auth_user_id, p_actor_label)
  returning * into v_exception;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'request_mfa_exception',
    'app.mfa_exceptions', v_exception.id, 'success', p_reason, null, to_jsonb(v_exception)
  );

  return v_exception;
end;
$function$;

revoke execute on function app.request_mfa_exception(p_tenant_id uuid, p_target_auth_user_id uuid, p_reason text, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) from anon, authenticated, service_role, public;
grant execute on function app.request_mfa_exception(p_tenant_id uuid, p_target_auth_user_id uuid, p_reason text, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) to authenticated;
grant execute on function app.request_mfa_exception(p_tenant_id uuid, p_target_auth_user_id uuid, p_reason text, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) to service_role;

create function public.request_mfa_exception(p_tenant_id uuid, p_target_auth_user_id uuid, p_reason text, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text default null)
 RETURNS app.mfa_exceptions
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
  select app.request_mfa_exception(p_tenant_id, p_target_auth_user_id, p_reason, p_actor_auth_user_id, p_actor_label, p_client_ip);
$function$;

revoke execute on function public.request_mfa_exception(p_tenant_id uuid, p_target_auth_user_id uuid, p_reason text, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) from anon, authenticated, service_role, public;
grant execute on function public.request_mfa_exception(p_tenant_id uuid, p_target_auth_user_id uuid, p_reason text, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) to authenticated;
grant execute on function public.request_mfa_exception(p_tenant_id uuid, p_target_auth_user_id uuid, p_reason text, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) to service_role;

-- 56. reverse_finance_ap_settlement -- authority shape: fin, tenant expression: v_item.tenant_id [wrapper definer flag repaired -- live had drifted to invoker]
drop function public.reverse_finance_ap_settlement(p_open_item_id uuid, p_amount numeric, p_reason text, p_source_type text, p_source_id uuid, p_idempotency_key text, p_actor_auth_user_id uuid, p_actor_label text);
drop function app.reverse_finance_ap_settlement(p_open_item_id uuid, p_amount numeric, p_reason text, p_source_type text, p_source_id uuid, p_idempotency_key text, p_actor_auth_user_id uuid, p_actor_label text);

create function app.reverse_finance_ap_settlement(p_open_item_id uuid, p_amount numeric, p_reason text, p_source_type text, p_source_id uuid, p_idempotency_key text, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text default null)
 RETURNS app.finance_ap_open_items
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_item app.finance_ap_open_items;
  v_existing_event app.finance_ap_open_item_events;
  v_new_settled numeric;
  v_new_status text;
begin
  select * into v_item from app.finance_ap_open_items where id = p_open_item_id for update;
  if not found then
    raise exception 'finance_ap_open_item_not_found: %', p_open_item_id using errcode = 'no_data_found';
  end if;
  if not app.check_finance_ap_authority('Approve', v_item.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:Approve for tenant %', p_actor_auth_user_id, v_item.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  -- ISS-2026-302: IP allowlist, checked after authority is established and before any
  -- state change. Skipped when the caller supplies no address, and bypassable via the
  -- separately-governed app.ip_allowlist_bypass_grants -- the identical composition
  -- 20260826190000 established for the import-commit RPCs.
  if p_client_ip is not null and not app.has_active_ip_allowlist_bypass(v_item.tenant_id, p_actor_auth_user_id) then
    perform app.assert_ip_allowed(v_item.tenant_id, p_client_ip, 'admin', p_actor_label);
  end if;

  if p_idempotency_key is not null then
    select * into v_existing_event from app.finance_ap_open_item_events
      where tenant_id = v_item.tenant_id and open_item_id = p_open_item_id and idempotency_key = p_idempotency_key;
    if found then
      -- ATW-031 (ISS-2026-029): a key already used for a DIFFERENT target is a
      -- conflict, never a replay. Returning the earlier target's row here silently
      -- misattributed this request to it (or silently discarded it entirely).
      if v_existing_event.event_type is distinct from 'unsettled' then
        raise exception 'idempotency_key_conflict: idempotency key % was already used for a different AP open-item event (event type %, not unsettled)', p_idempotency_key, v_existing_event.event_type
          using errcode = 'unique_violation';
      end if;
      return v_item;
    end if;
  end if;

  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'finance_ap_unsettlement_reason_required: a non-empty reason is required to reverse a settlement'
      using errcode = 'check_violation';
  end if;
  if p_amount is null or p_amount <= 0 then
    raise exception 'finance_ap_invalid_settlement_amount: reversal amount must be positive, got %', p_amount
      using errcode = 'check_violation';
  end if;
  if p_amount > v_item.settled_amount then
    raise exception 'finance_ap_over_reversal: reversal % exceeds settled amount % for open item %', p_amount, v_item.settled_amount, p_open_item_id
      using errcode = 'check_violation';
  end if;

  v_new_settled := v_item.settled_amount - p_amount;
  v_new_status := case when v_new_settled >= v_item.original_amount then 'settled' when v_new_settled > 0 then 'partial' else 'open' end;

  update app.finance_ap_open_items
    set settled_amount = v_new_settled, status = v_new_status
    where id = p_open_item_id
    returning * into v_item;

  insert into app.finance_ap_open_item_events (tenant_id, open_item_id, event_type, amount_delta, reason, source_type, source_id, idempotency_key, actor_auth_user_id, actor_label)
  values (v_item.tenant_id, v_item.id, 'unsettled', -p_amount, p_reason, p_source_type, p_source_id, p_idempotency_key, p_actor_auth_user_id, p_actor_label);

  perform app.capture_audit_event(
    v_item.tenant_id, p_actor_auth_user_id, p_actor_label, 'reverse_finance_ap_settlement',
    'app.finance_ap_open_items', v_item.id, 'success', p_reason, null, jsonb_build_object('amount', p_amount, 'newStatus', v_new_status)
  );

  return v_item;
end;
$function$;

revoke execute on function app.reverse_finance_ap_settlement(p_open_item_id uuid, p_amount numeric, p_reason text, p_source_type text, p_source_id uuid, p_idempotency_key text, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) from anon, authenticated, service_role, public;
grant execute on function app.reverse_finance_ap_settlement(p_open_item_id uuid, p_amount numeric, p_reason text, p_source_type text, p_source_id uuid, p_idempotency_key text, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) to authenticated;
grant execute on function app.reverse_finance_ap_settlement(p_open_item_id uuid, p_amount numeric, p_reason text, p_source_type text, p_source_id uuid, p_idempotency_key text, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) to service_role;

create function public.reverse_finance_ap_settlement(p_open_item_id uuid, p_amount numeric, p_reason text, p_source_type text, p_source_id uuid, p_idempotency_key text, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text default null)
 RETURNS app.finance_ap_open_items
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
  select app.reverse_finance_ap_settlement(p_open_item_id, p_amount, p_reason, p_source_type, p_source_id, p_idempotency_key, p_actor_auth_user_id, p_actor_label, p_client_ip);
$function$;

revoke execute on function public.reverse_finance_ap_settlement(p_open_item_id uuid, p_amount numeric, p_reason text, p_source_type text, p_source_id uuid, p_idempotency_key text, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) from anon, authenticated, service_role, public;
grant execute on function public.reverse_finance_ap_settlement(p_open_item_id uuid, p_amount numeric, p_reason text, p_source_type text, p_source_id uuid, p_idempotency_key text, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) to authenticated;
grant execute on function public.reverse_finance_ap_settlement(p_open_item_id uuid, p_amount numeric, p_reason text, p_source_type text, p_source_id uuid, p_idempotency_key text, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) to service_role;

-- 57. reverse_finance_ar_allocation -- authority shape: fin, tenant expression: v_item.tenant_id [wrapper definer flag repaired -- live had drifted to invoker]
drop function public.reverse_finance_ar_allocation(p_open_item_id uuid, p_amount numeric, p_reason text, p_source_type text, p_source_id uuid, p_idempotency_key text, p_actor_auth_user_id uuid, p_actor_label text);
drop function app.reverse_finance_ar_allocation(p_open_item_id uuid, p_amount numeric, p_reason text, p_source_type text, p_source_id uuid, p_idempotency_key text, p_actor_auth_user_id uuid, p_actor_label text);

create function app.reverse_finance_ar_allocation(p_open_item_id uuid, p_amount numeric, p_reason text, p_source_type text, p_source_id uuid, p_idempotency_key text, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text default null)
 RETURNS app.finance_ar_open_items
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_item app.finance_ar_open_items;
  v_existing_event app.finance_ar_open_item_events;
  v_new_allocated numeric;
  v_new_status text;
begin
  select * into v_item from app.finance_ar_open_items where id = p_open_item_id for update;
  if not found then
    raise exception 'finance_ar_open_item_not_found: %', p_open_item_id using errcode = 'no_data_found';
  end if;
  if not app.check_finance_ar_authority('Approve', v_item.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:Approve for tenant %', p_actor_auth_user_id, v_item.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  -- ISS-2026-302: IP allowlist, checked after authority is established and before any
  -- state change. Skipped when the caller supplies no address, and bypassable via the
  -- separately-governed app.ip_allowlist_bypass_grants -- the identical composition
  -- 20260826190000 established for the import-commit RPCs.
  if p_client_ip is not null and not app.has_active_ip_allowlist_bypass(v_item.tenant_id, p_actor_auth_user_id) then
    perform app.assert_ip_allowed(v_item.tenant_id, p_client_ip, 'admin', p_actor_label);
  end if;

  if p_idempotency_key is not null then
    select * into v_existing_event from app.finance_ar_open_item_events
      where tenant_id = v_item.tenant_id and open_item_id = p_open_item_id and idempotency_key = p_idempotency_key;
    if found then
      -- ATW-031 (ISS-2026-029): a key already used for a DIFFERENT target is a
      -- conflict, never a replay. Returning the earlier target's row here silently
      -- misattributed this request to it (or silently discarded it entirely).
      if v_existing_event.event_type is distinct from 'deallocated' then
        raise exception 'idempotency_key_conflict: idempotency key % was already used for a different AR open-item event (event type %, not deallocated)', p_idempotency_key, v_existing_event.event_type
          using errcode = 'unique_violation';
      end if;
      return v_item;
    end if;
  end if;

  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'finance_ar_deallocation_reason_required: a non-empty reason is required to reverse an allocation'
      using errcode = 'check_violation';
  end if;
  if p_amount is null or p_amount <= 0 then
    raise exception 'finance_ar_invalid_allocation_amount: reversal amount must be positive, got %', p_amount
      using errcode = 'check_violation';
  end if;
  if p_amount > v_item.allocated_amount then
    raise exception 'finance_ar_over_reversal: reversal % exceeds allocated amount % for open item %', p_amount, v_item.allocated_amount, p_open_item_id
      using errcode = 'check_violation';
  end if;

  v_new_allocated := v_item.allocated_amount - p_amount;
  v_new_status := case when v_new_allocated >= v_item.original_amount then 'paid' when v_new_allocated > 0 then 'partial' else 'open' end;

  update app.finance_ar_open_items
    set allocated_amount = v_new_allocated, status = v_new_status
    where id = p_open_item_id
    returning * into v_item;

  insert into app.finance_ar_open_item_events (tenant_id, open_item_id, event_type, amount_delta, reason, source_type, source_id, idempotency_key, actor_auth_user_id, actor_label)
  values (v_item.tenant_id, v_item.id, 'deallocated', -p_amount, p_reason, p_source_type, p_source_id, p_idempotency_key, p_actor_auth_user_id, p_actor_label);

  perform app.capture_audit_event(
    v_item.tenant_id, p_actor_auth_user_id, p_actor_label, 'reverse_finance_ar_allocation',
    'app.finance_ar_open_items', v_item.id, 'success', p_reason, null, jsonb_build_object('amount', p_amount, 'newStatus', v_new_status)
  );

  return v_item;
end;
$function$;

revoke execute on function app.reverse_finance_ar_allocation(p_open_item_id uuid, p_amount numeric, p_reason text, p_source_type text, p_source_id uuid, p_idempotency_key text, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) from anon, authenticated, service_role, public;
grant execute on function app.reverse_finance_ar_allocation(p_open_item_id uuid, p_amount numeric, p_reason text, p_source_type text, p_source_id uuid, p_idempotency_key text, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) to authenticated;
grant execute on function app.reverse_finance_ar_allocation(p_open_item_id uuid, p_amount numeric, p_reason text, p_source_type text, p_source_id uuid, p_idempotency_key text, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) to service_role;

create function public.reverse_finance_ar_allocation(p_open_item_id uuid, p_amount numeric, p_reason text, p_source_type text, p_source_id uuid, p_idempotency_key text, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text default null)
 RETURNS app.finance_ar_open_items
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
  select app.reverse_finance_ar_allocation(p_open_item_id, p_amount, p_reason, p_source_type, p_source_id, p_idempotency_key, p_actor_auth_user_id, p_actor_label, p_client_ip);
$function$;

revoke execute on function public.reverse_finance_ar_allocation(p_open_item_id uuid, p_amount numeric, p_reason text, p_source_type text, p_source_id uuid, p_idempotency_key text, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) from anon, authenticated, service_role, public;
grant execute on function public.reverse_finance_ar_allocation(p_open_item_id uuid, p_amount numeric, p_reason text, p_source_type text, p_source_id uuid, p_idempotency_key text, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) to authenticated;
grant execute on function public.reverse_finance_ar_allocation(p_open_item_id uuid, p_amount numeric, p_reason text, p_source_type text, p_source_id uuid, p_idempotency_key text, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) to service_role;

-- 58. revoke_all_actor_sessions -- authority shape: eval, tenant expression: p_tenant_id
drop function public.revoke_all_actor_sessions(p_tenant_id uuid, p_target_auth_user_id uuid, p_reason text, p_actor_auth_user_id uuid, p_actor_label text);
drop function app.revoke_all_actor_sessions(p_tenant_id uuid, p_target_auth_user_id uuid, p_reason text, p_actor_auth_user_id uuid, p_actor_label text);

create function app.revoke_all_actor_sessions(p_tenant_id uuid, p_target_auth_user_id uuid, p_reason text, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text default null)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_decision app.rbac_decision;
  v_session_count integer;
  v_key record;
  v_key_count integer := 0;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'SEC', 'Configure');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks SEC:Configure (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  -- ISS-2026-302: IP allowlist, checked after authority is established and before any
  -- state change. Skipped when the caller supplies no address, and bypassable via the
  -- separately-governed app.ip_allowlist_bypass_grants -- the identical composition
  -- 20260826190000 established for the import-commit RPCs.
  if p_client_ip is not null and not app.has_active_ip_allowlist_bypass(p_tenant_id, p_actor_auth_user_id) then
    perform app.assert_ip_allowed(p_tenant_id, p_client_ip, 'admin', p_actor_label);
  end if;

  update app.user_sessions
  set status = 'revoked', revoked_at = now(), revoked_reason = p_reason, revoked_by = p_actor_label
  where tenant_id = p_tenant_id and auth_user_id = p_target_auth_user_id and status = 'active';
  get diagnostics v_session_count = row_count;

  for v_key in
    select id from app.api_keys where tenant_id = p_tenant_id and created_by_auth_user_id = p_target_auth_user_id and status = 'active'
  loop
    perform app.revoke_api_key(v_key.id, p_reason, p_actor_auth_user_id, p_actor_label);
    v_key_count := v_key_count + 1;
  end loop;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'revoke_all_actor_sessions',
    'app.user_sessions', p_target_auth_user_id, 'success', p_reason, null,
    jsonb_build_object('sessions_revoked', v_session_count, 'api_keys_revoked', v_key_count)
  );

  return v_session_count;
end;
$function$;

revoke execute on function app.revoke_all_actor_sessions(p_tenant_id uuid, p_target_auth_user_id uuid, p_reason text, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) from anon, authenticated, service_role, public;
grant execute on function app.revoke_all_actor_sessions(p_tenant_id uuid, p_target_auth_user_id uuid, p_reason text, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) to authenticated;
grant execute on function app.revoke_all_actor_sessions(p_tenant_id uuid, p_target_auth_user_id uuid, p_reason text, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) to service_role;

create function public.revoke_all_actor_sessions(p_tenant_id uuid, p_target_auth_user_id uuid, p_reason text, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text default null)
 RETURNS integer
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
  select app.revoke_all_actor_sessions(p_tenant_id, p_target_auth_user_id, p_reason, p_actor_auth_user_id, p_actor_label, p_client_ip);
$function$;

revoke execute on function public.revoke_all_actor_sessions(p_tenant_id uuid, p_target_auth_user_id uuid, p_reason text, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) from anon, authenticated, service_role, public;
grant execute on function public.revoke_all_actor_sessions(p_tenant_id uuid, p_target_auth_user_id uuid, p_reason text, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) to authenticated;
grant execute on function public.revoke_all_actor_sessions(p_tenant_id uuid, p_target_auth_user_id uuid, p_reason text, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) to service_role;

-- 59. revoke_ip_allowlist_entry -- authority shape: eval, tenant expression: v_entry.tenant_id
drop function public.revoke_ip_allowlist_entry(p_entry_id uuid, p_actor_auth_user_id uuid, p_actor_label text);
drop function app.revoke_ip_allowlist_entry(p_entry_id uuid, p_actor_auth_user_id uuid, p_actor_label text);

create function app.revoke_ip_allowlist_entry(p_entry_id uuid, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text default null)
 RETURNS app.ip_allowlist_entries
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_decision app.rbac_decision;
  v_entry app.ip_allowlist_entries;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  select * into v_entry from app.ip_allowlist_entries where id = p_entry_id and status = 'active' for update;
  if not found then
    raise exception 'ip_allowlist_entry_not_active: % is not an active entry', p_entry_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_entry.tenant_id, 'SEC', 'Configure');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks SEC:Configure (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_entry.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  -- ISS-2026-302: IP allowlist, checked after authority is established and before any
  -- state change. Skipped when the caller supplies no address, and bypassable via the
  -- separately-governed app.ip_allowlist_bypass_grants -- the identical composition
  -- 20260826190000 established for the import-commit RPCs.
  if p_client_ip is not null and not app.has_active_ip_allowlist_bypass(v_entry.tenant_id, p_actor_auth_user_id) then
    perform app.assert_ip_allowed(v_entry.tenant_id, p_client_ip, 'admin', p_actor_label);
  end if;

  update app.ip_allowlist_entries
  set status = 'revoked', revoked_at = now(), revoked_by = p_actor_label
  where id = p_entry_id
  returning * into v_entry;

  perform app.capture_audit_event(
    v_entry.tenant_id, p_actor_auth_user_id, p_actor_label, 'revoke_ip_allowlist_entry',
    'app.ip_allowlist_entries', v_entry.id, 'success', null, null, to_jsonb(v_entry)
  );

  return v_entry;
end;
$function$;

revoke execute on function app.revoke_ip_allowlist_entry(p_entry_id uuid, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) from anon, authenticated, service_role, public;
grant execute on function app.revoke_ip_allowlist_entry(p_entry_id uuid, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) to authenticated;
grant execute on function app.revoke_ip_allowlist_entry(p_entry_id uuid, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) to service_role;

create function public.revoke_ip_allowlist_entry(p_entry_id uuid, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text default null)
 RETURNS app.ip_allowlist_entries
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
  select app.revoke_ip_allowlist_entry(p_entry_id, p_actor_auth_user_id, p_actor_label, p_client_ip);
$function$;

revoke execute on function public.revoke_ip_allowlist_entry(p_entry_id uuid, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) from anon, authenticated, service_role, public;
grant execute on function public.revoke_ip_allowlist_entry(p_entry_id uuid, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) to authenticated;
grant execute on function public.revoke_ip_allowlist_entry(p_entry_id uuid, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) to service_role;

-- 60. revoke_user_session -- authority shape: eval, tenant expression: v_session.tenant_id
drop function public.revoke_user_session(p_session_id uuid, p_reason text, p_actor_auth_user_id uuid, p_actor_label text);
drop function app.revoke_user_session(p_session_id uuid, p_reason text, p_actor_auth_user_id uuid, p_actor_label text);

create function app.revoke_user_session(p_session_id uuid, p_reason text, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text default null)
 RETURNS app.user_sessions
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_session app.user_sessions;
  v_decision app.rbac_decision;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  select * into v_session from app.user_sessions where id = p_session_id and status = 'active' for update;
  if not found then
    raise exception 'user_session_not_active: % is not an active session', p_session_id using errcode = 'no_data_found';
  end if;

  if v_session.auth_user_id <> p_actor_auth_user_id then
    v_decision := app.evaluate_permission(p_actor_auth_user_id, v_session.tenant_id, 'SEC', 'Configure');
    if not v_decision.allowed then
      raise exception 'insufficient_authority: identity % lacks SEC:Configure (%) to revoke another identity''s session', p_actor_auth_user_id, v_decision.reason
        using errcode = 'insufficient_privilege';
    end if;

  -- ISS-2026-302: IP allowlist, checked after authority is established and before any
  -- state change. Skipped when the caller supplies no address, and bypassable via the
  -- separately-governed app.ip_allowlist_bypass_grants -- the identical composition
  -- 20260826190000 established for the import-commit RPCs.
  if p_client_ip is not null and not app.has_active_ip_allowlist_bypass(v_session.tenant_id, p_actor_auth_user_id) then
    perform app.assert_ip_allowed(v_session.tenant_id, p_client_ip, 'admin', p_actor_label);
  end if;
  end if;

  update app.user_sessions
  set status = 'revoked', revoked_at = now(), revoked_reason = p_reason, revoked_by = p_actor_label
  where id = p_session_id
  returning * into v_session;

  perform app.capture_audit_event(
    v_session.tenant_id, p_actor_auth_user_id, p_actor_label, 'revoke_user_session',
    'app.user_sessions', v_session.id, 'success', p_reason, null, to_jsonb(v_session)
  );

  return v_session;
end;
$function$;

revoke execute on function app.revoke_user_session(p_session_id uuid, p_reason text, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) from anon, authenticated, service_role, public;
grant execute on function app.revoke_user_session(p_session_id uuid, p_reason text, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) to authenticated;
grant execute on function app.revoke_user_session(p_session_id uuid, p_reason text, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) to service_role;

create function public.revoke_user_session(p_session_id uuid, p_reason text, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text default null)
 RETURNS app.user_sessions
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
  select app.revoke_user_session(p_session_id, p_reason, p_actor_auth_user_id, p_actor_label, p_client_ip);
$function$;

revoke execute on function public.revoke_user_session(p_session_id uuid, p_reason text, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) from anon, authenticated, service_role, public;
grant execute on function public.revoke_user_session(p_session_id uuid, p_reason text, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) to authenticated;
grant execute on function public.revoke_user_session(p_session_id uuid, p_reason text, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) to service_role;

-- 61. rollback_finance_config_version -- authority shape: fin, tenant expression: v_object.tenant_id [wrapper definer flag repaired -- live had drifted to invoker]
drop function public.rollback_finance_config_version(p_target_version_id uuid, p_actor_auth_user_id uuid, p_reason text, p_actor_label text);
drop function app.rollback_finance_config_version(p_target_version_id uuid, p_actor_auth_user_id uuid, p_reason text, p_actor_label text);

create function app.rollback_finance_config_version(p_target_version_id uuid, p_actor_auth_user_id uuid, p_reason text, p_actor_label text, p_client_ip text default null)
 RETURNS app.config_versions
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_target app.config_versions;
  v_object app.config_objects;
begin
  select * into v_target from app.config_versions where id = p_target_version_id;
  if not found then
    raise exception 'config_version_not_found: no config version %', p_target_version_id
      using errcode = 'no_data_found';
  end if;
  select * into v_object from app.config_objects where id = v_target.config_object_id;

  if not app.is_finance_config_type(v_object.config_type_code) then
    raise exception 'not_finance_config_type: % is not a Finance Configuration class', v_object.config_type_code
      using errcode = 'check_violation';
  end if;
  if not app.check_finance_config_authority('Approve', v_object.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:Approve for tenant %', p_actor_auth_user_id, v_object.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  -- ISS-2026-302: IP allowlist, checked after authority is established and before any
  -- state change. Skipped when the caller supplies no address, and bypassable via the
  -- separately-governed app.ip_allowlist_bypass_grants -- the identical composition
  -- 20260826190000 established for the import-commit RPCs.
  if p_client_ip is not null and not app.has_active_ip_allowlist_bypass(v_object.tenant_id, p_actor_auth_user_id) then
    perform app.assert_ip_allowed(v_object.tenant_id, p_client_ip, 'admin', p_actor_label);
  end if;

  return app.rollback_config_version(p_target_version_id, p_actor_auth_user_id, p_reason, p_actor_label);
end;
$function$;

revoke execute on function app.rollback_finance_config_version(p_target_version_id uuid, p_actor_auth_user_id uuid, p_reason text, p_actor_label text, p_client_ip text) from anon, authenticated, service_role, public;
grant execute on function app.rollback_finance_config_version(p_target_version_id uuid, p_actor_auth_user_id uuid, p_reason text, p_actor_label text, p_client_ip text) to authenticated;
grant execute on function app.rollback_finance_config_version(p_target_version_id uuid, p_actor_auth_user_id uuid, p_reason text, p_actor_label text, p_client_ip text) to service_role;

create function public.rollback_finance_config_version(p_target_version_id uuid, p_actor_auth_user_id uuid, p_reason text, p_actor_label text, p_client_ip text default null)
 RETURNS app.config_versions
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
  select app.rollback_finance_config_version(p_target_version_id, p_actor_auth_user_id, p_reason, p_actor_label, p_client_ip);
$function$;

revoke execute on function public.rollback_finance_config_version(p_target_version_id uuid, p_actor_auth_user_id uuid, p_reason text, p_actor_label text, p_client_ip text) from anon, authenticated, service_role, public;
grant execute on function public.rollback_finance_config_version(p_target_version_id uuid, p_actor_auth_user_id uuid, p_reason text, p_actor_label text, p_client_ip text) to authenticated;
grant execute on function public.rollback_finance_config_version(p_target_version_id uuid, p_actor_auth_user_id uuid, p_reason text, p_actor_label text, p_client_ip text) to service_role;

-- 62. set_finance_aging_bucket_config -- authority shape: fin, tenant expression: p_tenant_id [wrapper definer flag repaired -- live had drifted to invoker]
drop function public.set_finance_aging_bucket_config(p_tenant_id uuid, p_entity_type text, p_buckets jsonb, p_actor_auth_user_id uuid, p_actor_label text);
drop function app.set_finance_aging_bucket_config(p_tenant_id uuid, p_entity_type text, p_buckets jsonb, p_actor_auth_user_id uuid, p_actor_label text);

create function app.set_finance_aging_bucket_config(p_tenant_id uuid, p_entity_type text, p_buckets jsonb, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text default null)
 RETURNS app.finance_aging_bucket_configs
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_config app.finance_aging_bucket_configs;
  v_next_version integer;
begin
  if not app.has_active_tenant_membership(p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % holds no active membership for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.check_finance_aging_authority('Approve', p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:Approve for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  -- ISS-2026-302: IP allowlist, checked after authority is established and before any
  -- state change. Skipped when the caller supplies no address, and bypassable via the
  -- separately-governed app.ip_allowlist_bypass_grants -- the identical composition
  -- 20260826190000 established for the import-commit RPCs.
  if p_client_ip is not null and not app.has_active_ip_allowlist_bypass(p_tenant_id, p_actor_auth_user_id) then
    perform app.assert_ip_allowed(p_tenant_id, p_client_ip, 'admin', p_actor_label);
  end if;
  if p_entity_type not in ('ar', 'ap') then
    raise exception 'finance_aging_invalid_entity_type: % is not a supported aging entity type', p_entity_type
      using errcode = 'check_violation';
  end if;

  perform app.validate_finance_aging_buckets(p_buckets);

  select coalesce(max(version), 0) + 1 into v_next_version from app.finance_aging_bucket_configs where tenant_id = p_tenant_id and entity_type = p_entity_type;

  update app.finance_aging_bucket_configs set is_active = false where tenant_id = p_tenant_id and entity_type = p_entity_type and is_active;

  insert into app.finance_aging_bucket_configs (tenant_id, entity_type, version, buckets, created_by)
  values (p_tenant_id, p_entity_type, v_next_version, p_buckets, p_actor_label)
  returning * into v_config;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'set_finance_aging_bucket_config',
    'app.finance_aging_bucket_configs', v_config.id, 'success', null, null, to_jsonb(v_config)
  );

  return v_config;
end;
$function$;

revoke execute on function app.set_finance_aging_bucket_config(p_tenant_id uuid, p_entity_type text, p_buckets jsonb, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) from anon, authenticated, service_role, public;
grant execute on function app.set_finance_aging_bucket_config(p_tenant_id uuid, p_entity_type text, p_buckets jsonb, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) to authenticated;
grant execute on function app.set_finance_aging_bucket_config(p_tenant_id uuid, p_entity_type text, p_buckets jsonb, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) to service_role;

create function public.set_finance_aging_bucket_config(p_tenant_id uuid, p_entity_type text, p_buckets jsonb, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text default null)
 RETURNS app.finance_aging_bucket_configs
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
  select app.set_finance_aging_bucket_config(p_tenant_id, p_entity_type, p_buckets, p_actor_auth_user_id, p_actor_label, p_client_ip);
$function$;

revoke execute on function public.set_finance_aging_bucket_config(p_tenant_id uuid, p_entity_type text, p_buckets jsonb, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) from anon, authenticated, service_role, public;
grant execute on function public.set_finance_aging_bucket_config(p_tenant_id uuid, p_entity_type text, p_buckets jsonb, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) to authenticated;
grant execute on function public.set_finance_aging_bucket_config(p_tenant_id uuid, p_entity_type text, p_buckets jsonb, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) to service_role;

-- 63. set_ip_allowlist_enforcement_mode -- authority shape: eval, tenant expression: p_tenant_id
drop function public.set_ip_allowlist_enforcement_mode(p_tenant_id uuid, p_enforcement_mode text, p_actor_auth_user_id uuid, p_actor_label text);
drop function app.set_ip_allowlist_enforcement_mode(p_tenant_id uuid, p_enforcement_mode text, p_actor_auth_user_id uuid, p_actor_label text);

create function app.set_ip_allowlist_enforcement_mode(p_tenant_id uuid, p_enforcement_mode text, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text default null)
 RETURNS app.ip_allowlist_policies
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_decision app.rbac_decision;
  v_policy app.ip_allowlist_policies;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'SEC', 'Configure');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks SEC:Configure (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  -- ISS-2026-302: IP allowlist, checked after authority is established and before any
  -- state change. Skipped when the caller supplies no address, and bypassable via the
  -- separately-governed app.ip_allowlist_bypass_grants -- the identical composition
  -- 20260826190000 established for the import-commit RPCs.
  if p_client_ip is not null and not app.has_active_ip_allowlist_bypass(p_tenant_id, p_actor_auth_user_id) then
    perform app.assert_ip_allowed(p_tenant_id, p_client_ip, 'admin', p_actor_label);
  end if;

  if p_enforcement_mode not in ('disabled', 'dry_run', 'enforced') then
    raise exception 'ip_allowlist_invalid_mode: % is not one of disabled/dry_run/enforced', p_enforcement_mode using errcode = 'check_violation';
  end if;

  perform app._get_or_create_ip_allowlist_policy(p_tenant_id);

  if p_enforcement_mode = 'enforced' and not exists (
    select 1 from app.ip_allowlist_entries where tenant_id = p_tenant_id and status = 'active'
  ) then
    raise exception 'ip_allowlist_no_active_entries: cannot enforce with zero active allowlist entries -- this would lock out every caller'
      using errcode = 'check_violation';
  end if;

  update app.ip_allowlist_policies
  set enforcement_mode = p_enforcement_mode, updated_by = p_actor_label
  where tenant_id = p_tenant_id
  returning * into v_policy;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'set_ip_allowlist_enforcement_mode',
    'app.ip_allowlist_policies', null, 'success', null, null, to_jsonb(v_policy)
  );

  return v_policy;
end;
$function$;

revoke execute on function app.set_ip_allowlist_enforcement_mode(p_tenant_id uuid, p_enforcement_mode text, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) from anon, authenticated, service_role, public;
grant execute on function app.set_ip_allowlist_enforcement_mode(p_tenant_id uuid, p_enforcement_mode text, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) to authenticated;
grant execute on function app.set_ip_allowlist_enforcement_mode(p_tenant_id uuid, p_enforcement_mode text, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) to service_role;

create function public.set_ip_allowlist_enforcement_mode(p_tenant_id uuid, p_enforcement_mode text, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text default null)
 RETURNS app.ip_allowlist_policies
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
  select app.set_ip_allowlist_enforcement_mode(p_tenant_id, p_enforcement_mode, p_actor_auth_user_id, p_actor_label, p_client_ip);
$function$;

revoke execute on function public.set_ip_allowlist_enforcement_mode(p_tenant_id uuid, p_enforcement_mode text, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) from anon, authenticated, service_role, public;
grant execute on function public.set_ip_allowlist_enforcement_mode(p_tenant_id uuid, p_enforcement_mode text, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) to authenticated;
grant execute on function public.set_ip_allowlist_enforcement_mode(p_tenant_id uuid, p_enforcement_mode text, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) to service_role;

-- 64. set_mfa_tenant_policy -- authority shape: eval, tenant expression: p_tenant_id
drop function public.set_mfa_tenant_policy(p_tenant_id uuid, p_tenant_wide_required boolean, p_required_layers jsonb, p_step_up_max_age_minutes integer, p_additional_high_risk_actions jsonb, p_actor_auth_user_id uuid, p_actor_label text);
drop function app.set_mfa_tenant_policy(p_tenant_id uuid, p_tenant_wide_required boolean, p_required_layers jsonb, p_step_up_max_age_minutes integer, p_additional_high_risk_actions jsonb, p_actor_auth_user_id uuid, p_actor_label text);

create function app.set_mfa_tenant_policy(p_tenant_id uuid, p_tenant_wide_required boolean, p_required_layers jsonb, p_step_up_max_age_minutes integer, p_additional_high_risk_actions jsonb, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text default null)
 RETURNS app.mfa_tenant_policies
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_decision app.rbac_decision;
  v_policy app.mfa_tenant_policies;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'SEC', 'Configure');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks SEC:Configure (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  -- ISS-2026-302: IP allowlist, checked after authority is established and before any
  -- state change. Skipped when the caller supplies no address, and bypassable via the
  -- separately-governed app.ip_allowlist_bypass_grants -- the identical composition
  -- 20260826190000 established for the import-commit RPCs.
  if p_client_ip is not null and not app.has_active_ip_allowlist_bypass(p_tenant_id, p_actor_auth_user_id) then
    perform app.assert_ip_allowed(p_tenant_id, p_client_ip, 'admin', p_actor_label);
  end if;

  if p_step_up_max_age_minutes not between 1 and 1440 then
    raise exception 'mfa_invalid_step_up_max_age: % must be between 1 and 1440 minutes', p_step_up_max_age_minutes using errcode = 'check_violation';
  end if;

  if not app.validate_config_value(coalesce(p_additional_high_risk_actions, '[]'::jsonb)) then
    raise exception 'mfa_unsafe_additional_high_risk_actions: failed structural validation' using errcode = 'check_violation';
  end if;

  perform app._get_or_create_mfa_tenant_policy(p_tenant_id);

  update app.mfa_tenant_policies
  set tenant_wide_required = p_tenant_wide_required,
      required_layers = coalesce(p_required_layers, required_layers),
      step_up_max_age_minutes = p_step_up_max_age_minutes,
      additional_high_risk_actions = coalesce(p_additional_high_risk_actions, additional_high_risk_actions),
      updated_by = p_actor_label
  where tenant_id = p_tenant_id
  returning * into v_policy;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'set_mfa_tenant_policy',
    'app.mfa_tenant_policies', null, 'success', null, null, to_jsonb(v_policy)
  );

  return v_policy;
end;
$function$;

revoke execute on function app.set_mfa_tenant_policy(p_tenant_id uuid, p_tenant_wide_required boolean, p_required_layers jsonb, p_step_up_max_age_minutes integer, p_additional_high_risk_actions jsonb, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) from anon, authenticated, service_role, public;
grant execute on function app.set_mfa_tenant_policy(p_tenant_id uuid, p_tenant_wide_required boolean, p_required_layers jsonb, p_step_up_max_age_minutes integer, p_additional_high_risk_actions jsonb, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) to authenticated;
grant execute on function app.set_mfa_tenant_policy(p_tenant_id uuid, p_tenant_wide_required boolean, p_required_layers jsonb, p_step_up_max_age_minutes integer, p_additional_high_risk_actions jsonb, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) to service_role;

create function public.set_mfa_tenant_policy(p_tenant_id uuid, p_tenant_wide_required boolean, p_required_layers jsonb, p_step_up_max_age_minutes integer, p_additional_high_risk_actions jsonb, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text default null)
 RETURNS app.mfa_tenant_policies
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
  select app.set_mfa_tenant_policy(p_tenant_id, p_tenant_wide_required, p_required_layers, p_step_up_max_age_minutes, p_additional_high_risk_actions, p_actor_auth_user_id, p_actor_label, p_client_ip);
$function$;

revoke execute on function public.set_mfa_tenant_policy(p_tenant_id uuid, p_tenant_wide_required boolean, p_required_layers jsonb, p_step_up_max_age_minutes integer, p_additional_high_risk_actions jsonb, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) from anon, authenticated, service_role, public;
grant execute on function public.set_mfa_tenant_policy(p_tenant_id uuid, p_tenant_wide_required boolean, p_required_layers jsonb, p_step_up_max_age_minutes integer, p_additional_high_risk_actions jsonb, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) to authenticated;
grant execute on function public.set_mfa_tenant_policy(p_tenant_id uuid, p_tenant_wide_required boolean, p_required_layers jsonb, p_step_up_max_age_minutes integer, p_additional_high_risk_actions jsonb, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) to service_role;

-- 65. unmatch_finance_bank_transaction -- authority shape: fin, tenant expression: v_transaction.tenant_id [wrapper definer flag repaired -- live had drifted to invoker]
drop function public.unmatch_finance_bank_transaction(p_transaction_id uuid, p_expected_version integer, p_reason text, p_actor_auth_user_id uuid, p_actor_label text);
drop function app.unmatch_finance_bank_transaction(p_transaction_id uuid, p_expected_version integer, p_reason text, p_actor_auth_user_id uuid, p_actor_label text);

create function app.unmatch_finance_bank_transaction(p_transaction_id uuid, p_expected_version integer, p_reason text, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text default null)
 RETURNS app.finance_bank_transactions
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_transaction app.finance_bank_transactions;
begin
  select * into v_transaction from app.finance_bank_transactions where id = p_transaction_id for update;
  if not found then
    raise exception 'finance_cash_transaction_not_found: %', p_transaction_id using errcode = 'no_data_found';
  end if;
  if not app.check_finance_cash_authority('Approve', v_transaction.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:Approve for tenant %', p_actor_auth_user_id, v_transaction.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  -- ISS-2026-302: IP allowlist, checked after authority is established and before any
  -- state change. Skipped when the caller supplies no address, and bypassable via the
  -- separately-governed app.ip_allowlist_bypass_grants -- the identical composition
  -- 20260826190000 established for the import-commit RPCs.
  if p_client_ip is not null and not app.has_active_ip_allowlist_bypass(v_transaction.tenant_id, p_actor_auth_user_id) then
    perform app.assert_ip_allowed(v_transaction.tenant_id, p_client_ip, 'admin', p_actor_label);
  end if;
  if v_transaction.record_version <> p_expected_version then
    raise exception 'stale_version: transaction % expected version % but found %', p_transaction_id, p_expected_version, v_transaction.record_version
      using errcode = 'serialization_failure';
  end if;
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'finance_cash_unmatch_reason_required: a non-empty reason is required' using errcode = 'check_violation';
  end if;
  if v_transaction.match_status <> 'matched' then
    raise exception 'finance_cash_transaction_not_matched: transaction % is % not matched', p_transaction_id, v_transaction.match_status
      using errcode = 'check_violation';
  end if;

  update app.finance_bank_transactions
    set match_status = 'unmatched', matched_source_type = null, matched_source_id = null, matched_by = null, matched_at = null, unmatch_reason = p_reason
    where id = p_transaction_id
    returning * into v_transaction;

  perform app.capture_audit_event(
    v_transaction.tenant_id, p_actor_auth_user_id, p_actor_label, 'unmatch_finance_bank_transaction',
    'app.finance_bank_transactions', v_transaction.id, 'success', p_reason, null, to_jsonb(v_transaction)
  );

  return v_transaction;
end;
$function$;

revoke execute on function app.unmatch_finance_bank_transaction(p_transaction_id uuid, p_expected_version integer, p_reason text, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) from anon, authenticated, service_role, public;
grant execute on function app.unmatch_finance_bank_transaction(p_transaction_id uuid, p_expected_version integer, p_reason text, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) to authenticated;
grant execute on function app.unmatch_finance_bank_transaction(p_transaction_id uuid, p_expected_version integer, p_reason text, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) to service_role;

create function public.unmatch_finance_bank_transaction(p_transaction_id uuid, p_expected_version integer, p_reason text, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text default null)
 RETURNS app.finance_bank_transactions
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
  select app.unmatch_finance_bank_transaction(p_transaction_id, p_expected_version, p_reason, p_actor_auth_user_id, p_actor_label, p_client_ip);
$function$;

revoke execute on function public.unmatch_finance_bank_transaction(p_transaction_id uuid, p_expected_version integer, p_reason text, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) from anon, authenticated, service_role, public;
grant execute on function public.unmatch_finance_bank_transaction(p_transaction_id uuid, p_expected_version integer, p_reason text, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) to authenticated;
grant execute on function public.unmatch_finance_bank_transaction(p_transaction_id uuid, p_expected_version integer, p_reason text, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) to service_role;
