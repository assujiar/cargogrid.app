-- HDN-372 (Step 15, Prompt 372, Tenant Isolation Audit, `CG-S15-HDN-004`) — closes
-- `HDN-BLK-011`/`ISS-2026-164`.
--
-- `ATW-032` (`20260730510000_harden_actor_identity_unchecked_authority_surface.sql`)
-- closed `ISS-2026-032` under the premise that "43 of those are `STABLE`/`IMMUTABLE` —
-- pure reads that perform no side effect, where a forged actor changes nothing a caller
-- could not already read." That premise is false for a `SECURITY DEFINER` reader: it
-- bypasses RLS, so a forged actor is exactly what lets a caller read what they could not
-- otherwise read. A second, narrower gap in the same sweep: its own candidate regex
-- looked only for `p_actor_auth_user_id`, so two `VOLATILE` functions naming the
-- parameter `p_requester_auth_user_id` were never in the candidate set at all.
--
-- `HDN-372`'s own live adversarial testing (four independent parallel lenses, full
-- disposition `docs/build-log/full-system-hardening/HDN-372.md` §7, `HDN-BLK-011`)
-- forced and confirmed real cross-tenant reads against this exact class — full PII
-- (`app.get_self_employee`), customer inventory/warehouse/order data (the ATW-023
-- `app.resolve_customer_owner_account_scope` family, 12 functions), the audit trail
-- (`app.query_audit_logs`/`app.export_audit_logs`), notifications
-- (`app.list_notifications_for_recipient`/`app.count_unread_notifications`), and
-- workflow/approval/shipment history (`app.get_workflow_instance_history`/
-- `app.get_approval_request_history`/`app.get_shipment_status_history`) — by passing a
-- victim tenant's own real identity as the claimed actor from an attacker session that
-- is not a member of that tenant at all.
--
-- This migration fixes the 9 functions below directly. `app.resolve_customer_owner_
-- account_scope` is one of the 9: it is the single shared root every one of the other
-- 12 `ATW-023` customer-inventory-access functions calls (directly, or transitively via
-- `app.evaluate_customer_inventory_access`/`app.get_customer_outbound_order`) to
-- resolve which customer accounts an actor may see, and none of those 12 callers
-- re-derives or mutates the actor before passing it through — so fixing the root closes
-- the whole family without touching 12 separate function bodies, mirroring how
-- `ATW-031` fixed 416 functions at one choke point (`app.evaluate_permission`) rather
-- than editing each individually. The fix itself mirrors `CPL-300`'s own successor
-- primitive, `app.resolve_customer_account_scope`
-- (`20260801010000_create_customer_portal_account_scope.sql`), which already carries
-- the identical `assert_actor_is_session_identity` guard for the identical reason.
--
-- `app.get_self_employee` was, until this migration, on `scripts/db-tests/rbac-
-- enforcement.sql`'s own `v_expected` reviewed-exempt list, reasoned as "every one of
-- its own call sites additionally calls `app.assert_actor_is_session_identity` before
-- invoking it." That reasoning protected only the function's *intended* callers — it
-- is `SECURITY DEFINER` and granted `EXECUTE` directly to `authenticated`, so any
-- session can call it standalone, bypassing whatever a caller-side wrapper does. This
-- migration moves the check inside the function itself, closing that gap at its root
-- rather than relying on caller convention, and the exemption is removed from the test
-- file in the same checkpoint.
--
-- Deliberately NOT touched here — registered as `ISS-2026-165`/`HDN-BLK-012` with a
-- named owner (`HDN-373`, Tenant Isolation's own immediate successor lane, RLS/RBAC
-- Audit) rather than silently bundled into this migration or silently dropped:
--   * 13 dashboard read functions (`app.get_ops_dashboard_*` ×6,
--     `app.get_dashboard_*` ×7) share the identical shape — an unchecked
--     `p_actor_auth_user_id` reaching `app.can_access_record` — but each is an
--     independent `LANGUAGE sql` entry point with no shared root to fix once, so
--     closing the class needs 13 separate conversions best done as their own
--     reviewed, regression-tested pass.
--   * The boolean/status oracle functions already named and reasoned about in
--     `rbac-enforcement.sql`'s own `v_expected` list (`current_support_session`,
--     `has_active_support_grant`, `is_ticket_queue_member`,
--     `pipeline_scope_org_unit_ids`, `evaluate_dispatch_readiness`,
--     `customer_warehouse_eligibility_active`) return a boolean/narrow oracle rather
--     than record content and are Medium, not High, per
--     `docs/build-log/full-system-hardening/00_EXECUTION_INDEX.md` §7 — real defense-
--     in-depth candidates, not this checkpoint's own bounded-repair scope.
--
-- Regression proof: `scripts/db-tests/rbac-enforcement.sql` gains a new named-list
-- check (§ "HDN-372") proving each of the 9 functions below now calls
-- `app.assert_actor_is_session_identity`, plus a live two-session forced-spoof
-- assertion mirroring the one this checkpoint used to find the defect.

create or replace function app.get_self_employee(p_tenant_id uuid, p_actor_auth_user_id uuid)
returns app.employees
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_employee app.employees;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  select e.* into v_employee
  from app.employees e
  join app.users u on u.id = e.user_id
  where e.tenant_id = p_tenant_id and u.auth_user_id = p_actor_auth_user_id and u.tenant_id = p_tenant_id;

  return v_employee;
end;
$$;

create or replace function app.resolve_customer_owner_account_scope(p_auth_user_id uuid, p_tenant_id uuid)
returns uuid[]
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_scope uuid[];
begin
  -- HDN-372: this is a genuine authority boundary, not a pure lookup -- p_auth_user_id
  -- is a free parameter naming WHOSE scope to resolve, so without this check any
  -- authenticated session could pass ANY other identity's uuid and read that identity's
  -- entire cross-account customer-inventory scope through every one of this function's
  -- 12 callers (live-verified IDOR). Mirrors app.resolve_customer_account_scope's own
  -- CPL-300 fix exactly.
  perform app.assert_actor_is_session_identity(p_auth_user_id);

  select coalesce(array_agg(distinct pm.customer_account_ref::uuid), array[]::uuid[])
  into v_scope
  from app.principal_memberships pm
  where pm.auth_user_id = p_auth_user_id
    and pm.tenant_id = p_tenant_id
    and pm.layer = 'customer_user'
    and pm.status = 'active'
    and pm.customer_account_ref ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$';

  return v_scope;
end;
$$;

create or replace function app.query_audit_logs(p_requester_auth_user_id uuid, p_tenant_id uuid, p_limit integer default 50, p_before_occurred_at timestamptz default null, p_before_id uuid default null)
returns setof app.audit_logs
language plpgsql
security definer
set search_path = app, pg_temp
as $$
begin
  -- HDN-372: was reachable with a forged p_requester_auth_user_id -- this parameter's
  -- name (not p_actor_auth_user_id) is exactly why ATW-032's own candidate regex never
  -- saw this function at all.
  perform app.assert_actor_is_session_identity(p_requester_auth_user_id);

  if not app.is_support_grant_authority(p_requester_auth_user_id, p_tenant_id) then
    raise exception 'insufficient_authority: identity % holds neither Supreme Admin nor tenant_admin authority for tenant %', p_requester_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  perform app.capture_audit_event(
    p_tenant_id, p_requester_auth_user_id, 'audit_query_caller', 'query_audit_logs',
    'app.audit_logs', null, 'success', null
  );

  return query
    select al.*
    from app.audit_logs al
    where al.tenant_id = p_tenant_id
      and (
        p_before_occurred_at is null
        or al.occurred_at < p_before_occurred_at
        or (al.occurred_at = p_before_occurred_at and al.id < p_before_id)
      )
    order by al.occurred_at desc, al.id desc
    limit least(greatest(coalesce(p_limit, 50), 1), 200);
end;
$$;

create or replace function app.export_audit_logs(p_requester_auth_user_id uuid, p_tenant_id uuid, p_limit integer default 500, p_before_occurred_at timestamptz default null, p_before_id uuid default null)
returns setof app.audit_logs
language plpgsql
security definer
set search_path = app, pg_temp
as $$
begin
  -- HDN-372: same gap and same fix as app.query_audit_logs immediately above.
  perform app.assert_actor_is_session_identity(p_requester_auth_user_id);

  if not app.is_support_grant_authority(p_requester_auth_user_id, p_tenant_id) then
    raise exception 'insufficient_authority: identity % holds neither Supreme Admin nor tenant_admin authority for tenant %', p_requester_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  perform app.capture_audit_event(
    p_tenant_id, p_requester_auth_user_id, 'audit_export_caller', 'export_audit_logs',
    'app.audit_logs', null, 'success', null
  );

  return query
    select al.*
    from app.audit_logs al
    where al.tenant_id = p_tenant_id
      and (
        p_before_occurred_at is null
        or al.occurred_at < p_before_occurred_at
        or (al.occurred_at = p_before_occurred_at and al.id < p_before_id)
      )
    order by al.occurred_at desc, al.id desc
    limit least(greatest(coalesce(p_limit, 500), 1), 1000);
end;
$$;

create or replace function app.list_notifications_for_recipient(p_tenant_id uuid, p_recipient_auth_user_id uuid, p_actor_auth_user_id uuid, p_unread_only boolean default false)
returns setof app.notifications
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
begin
  -- HDN-372: the pre-existing `p_actor_auth_user_id <> p_recipient_auth_user_id` check
  -- below is trivially satisfied by forging BOTH parameters to the same victim identity
  -- (live-verified). This assert binds p_actor_auth_user_id to the real session first,
  -- so a forged pair can no longer pass either check.
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  if p_actor_auth_user_id <> p_recipient_auth_user_id and not app.is_supreme_admin(p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % may not list another identity''s notifications', p_actor_auth_user_id
      using errcode = 'insufficient_privilege';
  end if;
  return query
    select * from app.notifications
    where tenant_id = p_tenant_id and recipient_auth_user_id = p_recipient_auth_user_id
      and (not p_unread_only or (read_at is null and effective_channel = 'in_app'))
    order by created_at desc;
end;
$$;

create or replace function app.count_unread_notifications(p_tenant_id uuid, p_recipient_auth_user_id uuid, p_actor_auth_user_id uuid)
returns integer
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_count integer;
begin
  -- HDN-372: same gap and same fix as app.list_notifications_for_recipient above.
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  if p_actor_auth_user_id <> p_recipient_auth_user_id and not app.is_supreme_admin(p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % may not count another identity''s notifications', p_actor_auth_user_id
      using errcode = 'insufficient_privilege';
  end if;
  select count(*) into v_count from app.notifications
  where tenant_id = p_tenant_id and recipient_auth_user_id = p_recipient_auth_user_id
    and effective_channel = 'in_app' and read_at is null and status = 'sent';
  return v_count;
end;
$$;

create or replace function app.get_workflow_instance_history(p_instance_id uuid, p_actor_auth_user_id uuid)
returns setof app.workflow_transition_history
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_instance app.workflow_instances;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  select * into v_instance from app.workflow_instances where id = p_instance_id;
  if not found then
    raise exception 'workflow_instance_not_found: no workflow instance %', p_instance_id
      using errcode = 'no_data_found';
  end if;

  if not app.check_workflow_instance_authority(v_instance.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % is not an active member of tenant %', p_actor_auth_user_id, v_instance.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  return query select * from app.workflow_transition_history where instance_id = p_instance_id order by occurred_at;
end;
$$;

create or replace function app.get_approval_request_history(p_request_id uuid, p_actor_auth_user_id uuid)
returns table (step_id uuid, step_order integer, approver_type text, step_status text, decision_id uuid, actor_auth_user_id uuid, actor_label text, decision text, reason text, decided_at timestamptz)
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_request app.approval_requests;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  select * into v_request from app.approval_requests where id = p_request_id;
  if not found then
    raise exception 'approval_request_not_found: no approval request %', p_request_id
      using errcode = 'no_data_found';
  end if;
  if not app.check_approval_request_authority(v_request.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % is not an active member of tenant %', p_actor_auth_user_id, v_request.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  return query
    select s.id, s.step_order, s.approver_type, s.status, d.id, d.actor_auth_user_id, d.actor_label, d.decision, d.reason, d.decided_at
    from app.approval_request_steps s
    left join app.approval_decisions d on d.request_step_id = s.id
    where s.request_id = p_request_id
    order by s.step_order, d.decided_at;
end;
$$;

create or replace function app.get_shipment_status_history(p_shipment_order_id uuid, p_actor_auth_user_id uuid default auth.uid())
returns setof app.shipment_status_transitions
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_shipment app.shipment_orders;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  select * into v_shipment from app.shipment_orders where id = p_shipment_order_id;
  if not found then
    raise exception 'shipment_order_not_found: %', p_shipment_order_id using errcode = 'no_data_found';
  end if;

  if not app.can_access_record(p_actor_auth_user_id, v_shipment.tenant_id, v_shipment.owner_user_id, app.lead_record_scope_org_unit_ids(v_shipment.org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot access shipment order %', p_actor_auth_user_id, p_shipment_order_id
      using errcode = 'insufficient_privilege';
  end if;

  return query
    select * from app.shipment_status_transitions
    where shipment_order_id = p_shipment_order_id
    order by occurred_at asc;
end;
$$;

revoke execute on all functions in schema app from public;

grant execute on function app.get_self_employee(p_tenant_id uuid, p_actor_auth_user_id uuid) to authenticated, service_role;
grant execute on function app.resolve_customer_owner_account_scope(p_auth_user_id uuid, p_tenant_id uuid) to authenticated, service_role;
grant execute on function app.query_audit_logs(p_requester_auth_user_id uuid, p_tenant_id uuid, p_limit integer, p_before_occurred_at timestamptz, p_before_id uuid) to authenticated, service_role;
grant execute on function app.export_audit_logs(p_requester_auth_user_id uuid, p_tenant_id uuid, p_limit integer, p_before_occurred_at timestamptz, p_before_id uuid) to authenticated, service_role;
grant execute on function app.list_notifications_for_recipient(p_tenant_id uuid, p_recipient_auth_user_id uuid, p_actor_auth_user_id uuid, p_unread_only boolean) to authenticated, service_role;
grant execute on function app.count_unread_notifications(p_tenant_id uuid, p_recipient_auth_user_id uuid, p_actor_auth_user_id uuid) to authenticated, service_role;
grant execute on function app.get_workflow_instance_history(p_instance_id uuid, p_actor_auth_user_id uuid) to authenticated, service_role;
grant execute on function app.get_approval_request_history(p_request_id uuid, p_actor_auth_user_id uuid) to authenticated, service_role;
grant execute on function app.get_shipment_status_history(p_shipment_order_id uuid, p_actor_auth_user_id uuid) to authenticated, service_role;
