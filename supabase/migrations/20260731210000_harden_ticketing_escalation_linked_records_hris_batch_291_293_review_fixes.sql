-- Tier C batch review-and-fix migration for Batch 1 of Phase 7 (HRIS and
-- Ticketing), covering Prompt 291 (Ticket Escalation, CG-S12-HRT-019),
-- Prompt 292 (Typed Ticket-Linked Records, CG-S12-HRT-020) and Prompt 293
-- (Sensitive Personal and Payroll Data Controls, CG-S12-HRT-021), per
-- docs/standards/BUILD_EXECUTION_PROTOCOL.md §5 (the batch's own adversarial
-- review round). Four parallel lenses (spec-compliance, security/RLS/
-- tenant-isolation, correctness/concurrency, cross-prompt integration) ran
-- against `git diff 05e9106..HEAD`; every CONFIRMED Critical/High finding
-- below was independently re-derived against a live, disposable Postgres 16
-- database before being fixed here -- never trusted from a lens's own report
-- alone (docs/standards/BUILD_EXECUTION_PROTOCOL.md §5.3). Full disposition
-- table, live-reproduction evidence, and Tier B self-check for this file
-- live in docs/build-log/phase-07/HRT-293.md's own "Batch close: Tier C
-- review" section. Additive only -- zero lines of any prior migration
-- (<= 20260731200000) touched, per this repository's own discipline.
--
-- ===========================================================================
-- FIX 1 (CRITICAL, security lens) -- app.ticket_links/app.ticket_link_events
-- raw-table SELECT grants exactly the cross-domain, cross-tenant access the
-- capability's own RPC layer (app.list_ticket_links/app.list_ticket_link_
-- events, both SECURITY DEFINER) exists to deny.
-- ===========================================================================
--
-- 20260731170000's own RLS policies (`ticket_links_select_scoped`/
-- `ticket_link_events_select_scoped`) admit any caller who can merely
-- app.can_access_ticket the parent ticket (staff/watcher/requester) -- OR any
-- Supreme Admin, unconditionally -- with NO re-check of the linked record's
-- own domain authorization (FIN/PRC/OPS/customer-owner-scope) and NO re-check
-- of app._ticket_link_actor_may_view_tenant_data (decision 5's own
-- capability-specific gate closing the "any Supreme Admin can browse any
-- tenant's data via a helpdesk ticket" hole). That RLS shape is CORRECT for
-- the sibling ticket_escalation_* ledger tables (ticket-native fields only,
-- no cross-domain data -- independently re-verified clean by this review) but
-- WRONG here, because app.ticket_links.safe_snapshot and app.ticket_link_
-- events both carry live-authorization-gated FIN/PRC/OPS/customer content the
-- RLS predicate never re-checks.
--
-- Live-reproduced twice against a real disposable database, both pre-fix:
--   1. Same-tenant, non-domain-authorized staff (a real ticket-queue member
--      with zero OPS/FIN/PRC permission): app.list_ticket_links correctly
--      shows invoice/shipment/vendor/warehouse as live_available=false, label
--      NULL -- but `select * from app.ticket_links where ticket_id = ...`
--      returned every row's full safe_snapshot (real invoice amount, real
--      vendor legal_name, real shipment number/mode, including a REMOVED
--      row), unfiltered.
--   2. Cross-tenant, zero-grant Supreme Admin on a helpdesk ticket (a fresh
--      Supreme Admin holding zero app.principal_memberships scoped to the
--      target tenant, zero app.support_access_grants, zero app.tenant_user_
--      identities): app.search_ticket_link_candidates correctly returns
--      candidate_count=0 (decision 5's own gate holds at the RPC layer) --
--      but a raw `select * from app.ticket_links where ticket_id = ...`
--      against that SAME helpdesk ticket returned the real linked vendor's
--      safe_snapshot in full, defeating the exact scenario decision 5's own
--      migration-header commentary says this capability was built to close.
--
-- Root-cause fix: RLS policies cannot cheaply reproduce app._ticket_link_
-- resolve_candidate's own per-row, per-entity-type domain dispatch inline (it
-- calls six different domains' own real predicates, several requiring
-- app.resolve_customer_owner_account_scope/app.customer_warehouse_
-- eligibility_active composition). Mirroring how every WRITE on these two
-- tables is already RPC-only (no direct INSERT/UPDATE/DELETE grant to
-- authenticated exists anywhere in 20260731170000), reads are now RPC-only
-- too: `authenticated` loses raw SELECT entirely on both tables. Every
-- legitimate read already goes through app.list_ticket_links/app.list_
-- ticket_link_events, both SECURITY DEFINER (so revoking the grantee's own
-- table-level SELECT does not affect them -- confirmed live: both continue
-- to return correct, masked data for the identical staff1/Supreme-Admin
-- probes above after this revoke). RLS policies themselves are left in place
-- (defense in depth for `service_role`/any future direct grant, matching
-- this repository's own "RLS stays even where the grant is the real gate"
-- convention elsewhere) -- they are simply never reached by `authenticated`
-- once the underlying table-level privilege check fails first.
--
-- Repo-wide propagation sweep performed before writing this fix: grepped
-- every OTHER new/changed table this batch introduces for the same
-- shape (RLS gated only on app.can_access_ticket/is_supreme_admin, but the
-- table ALSO carries cross-domain safe-summary content). Only app.
-- ticket_links/app.ticket_link_events qualify -- the six app.ticket_
-- escalation_* tables carry exclusively ticket-native fields (target/reason/
-- trigger/level), independently re-verified live (an unauthorized-but-
-- ticket-visible staff1 raw-reads app.ticket_escalations/app.ticket_
-- escalation_events cleanly -- nothing there requires a domain permission
-- beyond ticket access itself, so no equivalent leak exists).
revoke select on app.ticket_links, app.ticket_link_events from authenticated;

comment on table app.ticket_links is
  'HRT-292 (decisions 1/2/12); HRT-291/292/293 batch Tier C fix (20260731210000, Finding 1 CRITICAL): raw SELECT revoked from authenticated -- every legitimate read goes through app.list_ticket_links (SECURITY DEFINER), which independently re-authorizes each linked record via app._ticket_link_resolve_candidate. entity_type is a CHECK-constrained enum (the registry, decision 1) -- entity_id carries NO foreign key (cannot, across six different source tables in five different migrations) and is instead re-validated live on every write/read via app._ticket_link_resolve_candidate. safe_snapshot is the UNIFORM {label, detail, status} shape (decision 2), captured once at link time for history only -- every live read re-fetches fresh (decision 6), never trusting this column as currently authoritative.';

comment on table app.ticket_link_events is
  'HRT-292 (decisions 9/10/11); HRT-291/292/293 batch Tier C fix (20260731210000, Finding 1 CRITICAL): raw SELECT revoked from authenticated -- the only authorized reader is app.list_ticket_link_events (SECURITY DEFINER, staff-only). The append-only compliance ledger -- the ONLY authoritative source of link history/access/denial. Never app.audit_logs, mirroring app.ticket_escalation_events (HRT-291) exactly.';

-- ===========================================================================
-- FIX 2 (HIGH, cross-prompt integration lens) -- five PRE-EXISTING HR/
-- Recruitment RPCs (untouched by this batch, but sharing this batch's own
-- HRT-293 raw-table-column-restriction scope) return the FULL row/composite
-- of a table whose free-text reason column HRT-293's own migration
-- (20260731200000) restricted at the raw-table-grant level -- silently
-- bypassing that exact restriction via `select *`/a returned composite
-- variable, never named literally as the leaking column in any grep for the
-- column name itself (which is exactly why 20260731200000's own "verified
-- before fixing... zero SELECT-shaped projections" claim, sound as a text
-- search, did not catch this -- these sites use `select *`/a whole-row
-- variable, never naming the column).
--
-- Live-reproduced: viewer@hrmemp1.test (plain HRS:View, NO HRS:View personal
-- data) calling app.list_employee_duplicate_candidates receives the real
-- decided_reason text ("different person, coincidental name match") in the
-- clear -- while a raw `select decided_reason from app.employee_duplicate_
-- candidates` as the SAME actor is correctly denied outright (`permission
-- denied for table employee_duplicate_candidates`), proving the RPC is the
-- live bypass, not a residual raw-table gap. The identical shape independently
-- confirmed by direct code read for the other four sites below (all `select
-- *`/a full composite variable returned to a plain HRS:View caller).
--
-- Fix, mirroring HRT-293's own already-established masking convention
-- (app.get_employee_profile/app.get_employee_lifecycle_history,
-- 20260731180000) exactly: every one of the five column(s) restricted by
-- 20260731200000 is now masked to null unless the caller holds HRS:View
-- personal data. No self-branch on any of the five (matching app.get_
-- employee_lifecycle_history's own established reasoning) -- each function's
-- own pre-existing call-authority gate already requires plain HRS:View for
-- EVERY caller (no self-only caller could ever reach this point without it),
-- so there is no legitimate self-only caller whose access this could narrow.
-- Call-authority gates themselves are UNCHANGED (this fix does not widen or
-- narrow who may call any of these five functions -- only what the already-
-- authorized caller sees).
-- ===========================================================================

-- 2a. app.list_employee_duplicate_candidates -- mask decided_reason.
-- Same signature (RETURNS SETOF app.employee_duplicate_candidates), body-only
-- change via a flat column list (never a row-constructor cast against
-- RETURNS SETOF <composite> -- HRT-293's own self-found bug, 20260731180000
-- §5 item 3, documents exactly why that shape fails).
create or replace function app.list_employee_duplicate_candidates(p_master_record_id uuid, p_actor_auth_user_id uuid)
returns setof app.employee_duplicate_candidates
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_employee app.employees;
  v_unmasked boolean;
begin
  select * into v_employee from app.employees where master_record_id = p_master_record_id;
  if not found or not app.has_active_tenant_membership(v_employee.tenant_id, p_actor_auth_user_id) then
    raise exception 'employee_not_found: %', p_master_record_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_employee.tenant_id, 'HRS', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks HRS:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_employee.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  -- Batch 291-293 Tier C fix (20260731210000, Finding 2 HIGH): decided_reason
  -- can carry disciplinary/identity-comparison narrative about a named
  -- colleague -- previously returned unconditionally (select *) to any plain
  -- HRS:View holder, silently bypassing 20260731200000's own raw-table
  -- column restriction on this exact column.
  v_unmasked := app.has_view_personal_data(v_employee.tenant_id, p_actor_auth_user_id);

  return query
  select
    d.id, d.tenant_id, d.source_master_record_id, d.candidate_master_record_id, d.similarity_basis, d.similarity_score,
    d.decision, d.decided_by, d.decided_at,
    case when v_unmasked then d.decided_reason else null end,
    d.record_version, d.created_by, d.created_at
  from app.employee_duplicate_candidates d
  where d.source_master_record_id = p_master_record_id
  order by d.created_at desc;
end;
$$;

comment on function app.list_employee_duplicate_candidates is 'HRT-274, masked by the batch 291-293 Tier C fix (20260731210000): decided_reason is nulled unless the caller holds HRS:View personal data -- previously an unconditional select * leaking identity-comparison narrative to any plain HRS:View holder.';

-- 2b. app.get_employee_position_assignment_history -- mask reason_note/decided_reason.
create or replace function app.get_employee_position_assignment_history(p_master_record_id uuid, p_actor_auth_user_id uuid)
returns setof app.employee_position_assignments
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_employee app.employees;
  v_unmasked boolean;
begin
  select * into v_employee from app.employees e where e.master_record_id = p_master_record_id;
  if not found or not app.has_active_tenant_membership(v_employee.tenant_id, p_actor_auth_user_id) then
    raise exception 'employee_not_found: %', p_master_record_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_employee.tenant_id, 'HRS', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks HRS:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_employee.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  -- Batch 291-293 Tier C fix (20260731210000, Finding 2 HIGH): reason_note/
  -- decided_reason bypassed 20260731200000's own raw-table column
  -- restriction via this function's unconditional select *.
  v_unmasked := app.has_view_personal_data(v_employee.tenant_id, p_actor_auth_user_id);

  return query
  select
    a.id, a.tenant_id, a.master_record_id, a.position_id, a.grade_id, a.manager_employee_id, a.assignment_type, a.allocation_pct,
    a.effective_start_date, a.effective_end_date, a.validity_range, a.status, a.change_reason,
    case when v_unmasked then a.reason_note else null end,
    a.previous_assignment_id, a.source_config_version_id, a.decided_by, a.decided_at,
    case when v_unmasked then a.decided_reason else null end,
    a.record_version, a.created_by, a.created_at, a.updated_at
  from app.employee_position_assignments a
  where a.master_record_id = p_master_record_id
  order by a.effective_start_date desc, a.created_at desc;
end;
$$;

comment on function app.get_employee_position_assignment_history is 'HRT-275, masked by the batch 291-293 Tier C fix (20260731210000): reason_note/decided_reason are nulled unless the caller holds HRS:View personal data -- previously an unconditional select * leaking position-change/decision narrative to any plain HRS:View holder.';

-- 2c. app.get_employee_current_assignment -- same treatment, same table.
create or replace function app.get_employee_current_assignment(p_master_record_id uuid, p_actor_auth_user_id uuid, p_as_of date default current_date)
returns setof app.employee_position_assignments
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_employee app.employees;
  v_unmasked boolean;
begin
  select * into v_employee from app.employees e where e.master_record_id = p_master_record_id;
  if not found or not app.has_active_tenant_membership(v_employee.tenant_id, p_actor_auth_user_id) then
    raise exception 'employee_not_found: %', p_master_record_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_employee.tenant_id, 'HRS', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks HRS:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_employee.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  v_unmasked := app.has_view_personal_data(v_employee.tenant_id, p_actor_auth_user_id);

  return query
  select
    a.id, a.tenant_id, a.master_record_id, a.position_id, a.grade_id, a.manager_employee_id, a.assignment_type, a.allocation_pct,
    a.effective_start_date, a.effective_end_date, a.validity_range, a.status, a.change_reason,
    case when v_unmasked then a.reason_note else null end,
    a.previous_assignment_id, a.source_config_version_id, a.decided_by, a.decided_at,
    case when v_unmasked then a.decided_reason else null end,
    a.record_version, a.created_by, a.created_at, a.updated_at
  from app.employee_position_assignments a
  where a.master_record_id = p_master_record_id and a.status = 'active' and a.validity_range @> p_as_of
  order by a.assignment_type;
end;
$$;

comment on function app.get_employee_current_assignment is
  'HRT-275: the genuinely point-in-time-correct read (section 20 "test ... historical queries") -- reads directly from app.employee_position_assignments'' own validity_range, never from app.employees'' convenience cache. Masked by the batch 291-293 Tier C fix (20260731210000): reason_note/decided_reason nulled unless the caller holds HRS:View personal data.';

-- 2d. app.get_application_detail -- mask rejection_reason/withdrawal_reason
-- on the returned app.job_applications composite. The v_application variable
-- itself is masked in place before being selected, so the RETURNS TABLE
-- (application app.job_applications, ...) shape (a genuinely composite-typed
-- OUT column, unlike RETURNS SETOF <composite>) needs no row-constructor cast
-- and no flattening -- a single composite value per row is exactly what this
-- declared shape expects.
create or replace function app.get_application_detail(p_id uuid, p_actor_auth_user_id uuid)
returns table (application app.job_applications, candidate_id uuid, candidate_full_name text, vacancy_title text)
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_application app.job_applications;
  v_unmasked boolean;
begin
  select * into v_application from app.job_applications where id = p_id;
  if not found or not app.has_active_tenant_membership(v_application.tenant_id, p_actor_auth_user_id) then
    raise exception 'application_not_found: %', p_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_application.tenant_id, 'HRS', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks HRS:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_application.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  -- Batch 291-293 Tier C fix (20260731210000, Finding 2 HIGH): rejection_
  -- reason/withdrawal_reason can carry candidate-identifying and
  -- occasionally disciplinary-adjacent narrative -- previously returned
  -- unconditionally as part of the full v_application composite, silently
  -- bypassing 20260731200000's own raw-table column restriction.
  v_unmasked := app.has_view_personal_data(v_application.tenant_id, p_actor_auth_user_id);
  if not v_unmasked then
    v_application.rejection_reason := null;
    v_application.withdrawal_reason := null;
  end if;

  return query
  select v_application, c.id, c.full_name, v.title
  from app.candidates c, app.job_vacancies v
  where c.id = v_application.candidate_id and v.id = v_application.vacancy_id;
end;
$$;

comment on function app.get_application_detail is 'HRT-276, masked by the batch 291-293 Tier C fix (20260731210000): rejection_reason/withdrawal_reason are nulled on the returned application unless the caller holds HRS:View personal data -- previously returned unconditionally as part of the full row, leaking candidate narrative to any plain HRS:View holder.';

-- 2e. app.list_application_interviews -- mask cancel_reason on the returned
-- app.interviews composite via a row-constructor cast (the correct shape
-- here, NOT the RETURNS SETOF <composite> case HRT-293 §5 item 3 warns
-- against -- this function's OUT column `interview` is itself declared
-- app.interviews-typed inside a RETURNS TABLE, so a single composite value
-- per row is exactly what Postgres expects, confirmed live before shipping).
create or replace function app.list_application_interviews(p_application_id uuid, p_actor_auth_user_id uuid)
returns table (interview app.interviews, interviewer_employee_ids uuid[], feedback_count integer)
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_application app.job_applications;
  v_unmasked boolean;
begin
  select * into v_application from app.job_applications where id = p_application_id;
  if not found or not app.has_active_tenant_membership(v_application.tenant_id, p_actor_auth_user_id) then
    raise exception 'application_not_found: %', p_application_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_application.tenant_id, 'HRS', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks HRS:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_application.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  -- Batch 291-293 Tier C fix (20260731210000, Finding 2 HIGH): cancel_reason
  -- previously returned unconditionally as part of the full interview
  -- composite, silently bypassing 20260731200000's own raw-table column
  -- restriction.
  v_unmasked := app.has_view_personal_data(v_application.tenant_id, p_actor_auth_user_id);

  return query
  select
    (i.id, i.tenant_id, i.application_id, i.round, i.mode, i.scheduled_at, i.duration_minutes, i.location_or_link, i.status,
     case when v_unmasked then i.cancel_reason else null end,
     i.record_version, i.created_by, i.created_at, i.updated_at)::app.interviews,
    (select array_agg(ii.employee_id) from app.interview_interviewers ii where ii.interview_id = i.id),
    (select count(*)::integer from app.interview_feedback f where f.interview_id = i.id)
  from app.interviews i
  where i.application_id = p_application_id
  order by i.round;
end;
$$;

comment on function app.list_application_interviews is 'HRT-276, masked by the batch 291-293 Tier C fix (20260731210000): cancel_reason is nulled on every returned interview unless the caller holds HRS:View personal data -- previously returned unconditionally as part of the full row.';

-- ===========================================================================
-- FIX 3 (MEDIUM, correctness/concurrency + spec-compliance lenses) --
-- app.escalate_ticket's own documented double-submit protection ("races on
-- the ticket's own record_version") is false whenever the escalation does
-- not itself mutate app.tickets -- i.e. every target_type='queue' call, and
-- every target_type='employee' call with p_reassign=false (both explicitly
-- supported, decision 3: "notify and/or reassign, independently
-- configured"). Live-reproduced twice with real concurrent psql processes:
-- two concurrent app.escalate_ticket calls against the SAME ticket, SAME
-- p_expected_version, target_type='queue', both succeed -- the ticket
-- advances to current_level=2 instead of the second call being rejected as a
-- stale/duplicate retry, and a second real notification is queued. The
-- natural-key unique index that protects AUTO-triggered escalations
-- (ticket_escalation_events_triggered_unique) is explicitly scoped `where
-- policy_version_id is not null` and so gives manual escalations (always
-- policy_version_id is null) no protection at all.
--
-- Fix: app.escalate_ticket now unconditionally touches app.tickets (bumping
-- record_version via the existing app.touch_ticket_row() trigger) once its
-- own escalation has been applied, for EVERY successful manual escalation --
-- not only the reassign+employee path, which already did this incidentally
-- via app._apply_ticket_assignment. Placed AFTER app._apply_ticket_
-- escalation returns (never before): app._apply_ticket_assignment, called
-- from inside app._apply_ticket_escalation on the reassign path, uses the
-- p_ticket parameter's OWN cached record_version for its own optimistic
-- check -- bumping the row first would make that stale check fail spuriously
-- on the very path already correctly protected. An unconditional UPDATE with
-- no WHERE ... record_version clause (only the primary key) always succeeds
-- regardless of what the reassignment path already did, so a genuine
-- concurrent double-submit with the SAME p_expected_version is now rejected
-- with stale_version at the lock-acquisition step of the SECOND call, for
-- every target/reassign combination -- matching what this function's own
-- comment already claimed. app._apply_ticket_escalation itself (the shared
-- engine the auto-evaluator batch also calls) is NOT touched -- the
-- auto-triggered path's real protection is the natural-key unique index
-- above, which already works correctly and is unaffected by this fix.
-- ===========================================================================
create or replace function app.escalate_ticket(
  p_ticket_id uuid, p_expected_version integer, p_target_type text, p_target_queue_id uuid, p_target_employee_id uuid,
  p_reassign boolean, p_reason text, p_actor_auth_user_id uuid, p_actor_label text
)
returns app.ticket_escalations
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_ticket app.tickets;
  v_existing app.ticket_escalations;
  v_active_suppression app.ticket_escalation_suppressions;
  v_next_level integer;
  v_result app.ticket_escalations;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  select * into v_ticket from app.tickets where id = p_ticket_id for update;
  if not found then
    raise exception 'ticket_not_found: %', p_ticket_id using errcode = 'no_data_found';
  end if;
  if not app.can_access_ticket(p_ticket_id, p_actor_auth_user_id) then
    raise exception 'ticket_not_found: %', p_ticket_id using errcode = 'no_data_found';
  end if;
  if v_ticket.channel = 'helpdesk' then
    raise exception 'channel_not_supported: ticket % is a helpdesk case -- escalation has no non-Supreme-Admin model (decision 1)', p_ticket_id using errcode = 'check_violation';
  end if;
  if not app.is_ticket_staff(p_ticket_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % is not ticket staff on %', p_actor_auth_user_id, p_ticket_id
      using errcode = 'insufficient_privilege';
  end if;
  if v_ticket.record_version <> p_expected_version then
    raise exception 'stale_version: expected version % but current version is %', p_expected_version, v_ticket.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_ticket.status in ('closed', 'cancelled') then
    raise exception 'invalid_transition: cannot escalate a % ticket', v_ticket.status using errcode = 'check_violation';
  end if;
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'reason_required: a reason is required to manually escalate a ticket' using errcode = 'check_violation';
  end if;
  if not (p_target_type = any (array['queue', 'employee'])) then
    raise exception 'invalid_target_type: % is not one of queue/employee', p_target_type using errcode = 'check_violation';
  end if;
  if (p_target_type = 'queue' and (p_target_queue_id is null or p_target_employee_id is not null))
     or (p_target_type = 'employee' and (p_target_employee_id is null or p_target_queue_id is not null)) then
    raise exception 'invalid_target: exactly one of target_queue_id/target_employee_id must be set, matching target_type' using errcode = 'check_violation';
  end if;
  if coalesce(p_reassign, false) and p_target_type <> 'employee' then
    raise exception 'invalid_target: reassignment requires an employee target' using errcode = 'check_violation';
  end if;
  if not app._ticket_escalation_target_eligible(v_ticket.tenant_id, p_target_type, p_target_queue_id, p_target_employee_id) then
    raise exception 'escalation_target_not_eligible: the requested escalation target is missing, inactive, or not currently eligible' using errcode = 'check_violation';
  end if;

  select * into v_active_suppression from app.ticket_escalation_suppressions where ticket_id = p_ticket_id and revoked_at is null and expires_at > now();
  if found then
    raise exception 'escalation_suppressed: this ticket''s escalation is currently suppressed until % -- revoke the suppression first', v_active_suppression.expires_at using errcode = 'check_violation';
  end if;

  select * into v_existing from app.ticket_escalations where ticket_id = p_ticket_id;
  v_next_level := coalesce(v_existing.current_level, 0) + 1;

  v_result := app._apply_ticket_escalation(
    v_ticket, null, null, v_next_level, 'manual', p_target_type, p_target_queue_id, p_target_employee_id,
    true, coalesce(p_reassign, false), p_reason, p_actor_auth_user_id, p_actor_label, null
  );

  -- Batch 291-293 Tier C fix (20260731210000, Finding 3 MEDIUM, C-01):
  -- unconditionally bump app.tickets so a genuine concurrent retry with the
  -- SAME p_expected_version is rejected stale_version, regardless of target
  -- type/reassignment -- see this migration's own header for full reasoning
  -- on why this must run AFTER _apply_ticket_escalation, never before.
  update app.tickets set updated_at = now() where id = p_ticket_id;

  return v_result;
end;
$$;

comment on function app.escalate_ticket is
  'HRT-291 (decision 1, business rule "reason required"): manual escalation -- policy_version_id/level_id are null (no configured level applies), trigger_type=manual, level_number is the ticket''s own current_level + 1. Batch 291-293 Tier C fix (20260731210000, Finding 3): app.tickets is now unconditionally touched after applying the escalation, so a genuine double-submit with the SAME p_expected_version always races on the ticket''s own record_version, for every target_type/reassign combination -- previously true only when reassignment happened to touch app.tickets via app._apply_ticket_assignment.';

-- ===========================================================================
-- FIX 4 (MEDIUM, correctness/concurrency lens) -- app.adjust_leave_balance
-- and app.load_opening_leave_balance (both redeployed verbatim in substance
-- by 20260731190000, this batch's own migration, save for the audit-reason
-- argument) have a real unique index (leave_balance_ledger_idempotency_
-- unique) and a pre-check SELECT, but NO `exception when unique_violation`
-- handler around the INSERT -- the three-part idempotency shape this
-- repository's own taxonomy (C-01/C-02) requires is only 2/3 present. A
-- genuine concurrent retry with the SAME p_idempotency_key does not create a
-- duplicate row (the unique index still holds), but the LOSING session gets
-- a raw, unhandled `duplicate key value violates unique constraint` instead
-- of the graceful idempotent-success return the pre-check was clearly
-- designed to provide. Inherited from HRT-280 (not introduced by this
-- batch), but fixed here because this batch's own migration redeploys both
-- function bodies in full and the task's own review mandate named "any
-- Prompt 293 corrective function" for idempotency verification.
--
-- Fix mirrors app.link_ticket_record's own established three-part shape
-- (20260731170000) exactly: wrap the INSERT, and on unique_violation,
-- re-select the winning row and either return it (if it matches the
-- caller's own requested target) or raise the SAME idempotency_key_conflict
-- the pre-check already raises for a genuine key-reuse-for-a-different-
-- target collision (never silently returning a mismatched row -- C-01's own
-- "verify the target, not just the key" mandate).
-- ===========================================================================
create or replace function app.adjust_leave_balance(p_tenant_id uuid, p_employee_id uuid, p_leave_type_id uuid, p_units numeric, p_effective_date date, p_reason text, p_idempotency_key text, p_actor_auth_user_id uuid, p_actor_label text)
returns app.leave_balance_ledger
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_existing app.leave_balance_ledger;
  v_entry app.leave_balance_ledger;
begin
  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'HRS', 'Override');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks HRS:Override (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if not exists (select 1 from app.employees where master_record_id = p_employee_id and tenant_id = p_tenant_id) then
    raise exception 'employee_not_found: %', p_employee_id using errcode = 'no_data_found';
  end if;
  if not exists (select 1 from app.leave_types where id = p_leave_type_id and tenant_id = p_tenant_id) then
    raise exception 'leave_type_not_found: %', p_leave_type_id using errcode = 'no_data_found';
  end if;
  if p_units = 0 then
    raise exception 'invalid_units: an adjustment must be non-zero' using errcode = 'check_violation';
  end if;
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'reason_required: a non-empty reason is required for a manual balance adjustment' using errcode = 'check_violation';
  end if;

  if p_idempotency_key is not null then
    select * into v_existing from app.leave_balance_ledger where tenant_id = p_tenant_id and employee_id = p_employee_id and leave_type_id = p_leave_type_id and idempotency_key = p_idempotency_key;
    if found then
      if v_existing.event_type = 'adjustment' and v_existing.units = p_units and v_existing.effective_date = p_effective_date then
        return v_existing;
      else
        raise exception 'idempotency_key_conflict: key % was already used for a different adjustment', p_idempotency_key using errcode = 'unique_violation';
      end if;
    end if;
  end if;

  -- Batch 291-293 Tier C fix (20260731210000, Finding 4 MEDIUM, C-01/C-02):
  -- the pre-check above cannot close the race between two concurrent
  -- identical calls (neither sees the other's row before both INSERT) -- a
  -- real exception handler is the actual guarantee, mirroring app.
  -- link_ticket_record's own established shape.
  begin
    insert into app.leave_balance_ledger (tenant_id, employee_id, leave_type_id, event_type, units, effective_date, reason, idempotency_key, created_by)
    values (p_tenant_id, p_employee_id, p_leave_type_id, 'adjustment', p_units, coalesce(p_effective_date, current_date), p_reason, p_idempotency_key, p_actor_label)
    returning * into v_entry;
  exception
    when unique_violation then
      select * into v_entry from app.leave_balance_ledger where tenant_id = p_tenant_id and employee_id = p_employee_id and leave_type_id = p_leave_type_id and idempotency_key = p_idempotency_key;
      if not found then
        raise;
      end if;
      if not (v_entry.event_type = 'adjustment' and v_entry.units = p_units and v_entry.effective_date = coalesce(p_effective_date, current_date)) then
        raise exception 'idempotency_key_conflict: key % was already used for a different adjustment', p_idempotency_key using errcode = 'unique_violation';
      end if;
      return v_entry;
  end;

  -- HRT-293 Finding B fix (CRITICAL, C-24): p_reason is already durably
  -- stored above in app.leave_balance_ledger.reason (HRS_REGISTRY
  -- hrs:leave_balance_ledger.reason, column-restricted) -- never also
  -- duplicated into app.audit_logs.reason.
  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'adjust_leave_balance',
    'app.leave_balance_ledger', v_entry.id, 'success', null, null, jsonb_build_object('employee_id', p_employee_id, 'leave_type_id', p_leave_type_id, 'units', p_units)
  );

  return v_entry;
end;
$$;

create or replace function app.load_opening_leave_balance(p_tenant_id uuid, p_employee_id uuid, p_leave_type_id uuid, p_units numeric, p_as_of_date date, p_source_reference text, p_idempotency_key text, p_actor_auth_user_id uuid, p_actor_label text)
returns app.leave_balance_ledger
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_existing app.leave_balance_ledger;
  v_entry app.leave_balance_ledger;
begin
  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'HRS', 'Import');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks HRS:Import (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if not exists (select 1 from app.employees where master_record_id = p_employee_id and tenant_id = p_tenant_id) then
    raise exception 'employee_not_found: %', p_employee_id using errcode = 'no_data_found';
  end if;
  if not exists (select 1 from app.leave_types where id = p_leave_type_id and tenant_id = p_tenant_id) then
    raise exception 'leave_type_not_found: %', p_leave_type_id using errcode = 'no_data_found';
  end if;
  if p_units is null or p_units <= 0 then
    raise exception 'invalid_units: an opening balance load must be a positive amount' using errcode = 'check_violation';
  end if;
  if p_idempotency_key is null or length(trim(p_idempotency_key)) = 0 then
    raise exception 'idempotency_key_required: an opening balance load requires an idempotency key (section 19 reconciliation)' using errcode = 'check_violation';
  end if;

  select * into v_existing from app.leave_balance_ledger where tenant_id = p_tenant_id and employee_id = p_employee_id and leave_type_id = p_leave_type_id and idempotency_key = p_idempotency_key;
  if found then
    if v_existing.event_type = 'opening_balance' and v_existing.units = p_units and v_existing.effective_date = p_as_of_date then
      return v_existing;
    else
      raise exception 'idempotency_key_conflict: key % was already used for a different opening balance load', p_idempotency_key using errcode = 'unique_violation';
    end if;
  end if;

  -- Batch 291-293 Tier C fix (20260731210000, Finding 4 MEDIUM, C-01/C-02):
  -- same real-exception-handler shape as app.adjust_leave_balance above.
  begin
    insert into app.leave_balance_ledger (tenant_id, employee_id, leave_type_id, event_type, units, effective_date, reason, idempotency_key, created_by)
    values (p_tenant_id, p_employee_id, p_leave_type_id, 'opening_balance', p_units, coalesce(p_as_of_date, current_date), coalesce(p_source_reference, 'opening balance load'), p_idempotency_key, p_actor_label)
    returning * into v_entry;
  exception
    when unique_violation then
      select * into v_entry from app.leave_balance_ledger where tenant_id = p_tenant_id and employee_id = p_employee_id and leave_type_id = p_leave_type_id and idempotency_key = p_idempotency_key;
      if not found then
        raise;
      end if;
      if not (v_entry.event_type = 'opening_balance' and v_entry.units = p_units and v_entry.effective_date = coalesce(p_as_of_date, current_date)) then
        raise exception 'idempotency_key_conflict: key % was already used for a different opening balance load', p_idempotency_key using errcode = 'unique_violation';
      end if;
      return v_entry;
  end;

  -- HRT-293 Finding B fix (self-found, CRITICAL, C-24) -- see 20260731190000's own header.
  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'load_opening_leave_balance',
    'app.leave_balance_ledger', v_entry.id, 'success', null, null, jsonb_build_object('employee_id', p_employee_id, 'leave_type_id', p_leave_type_id, 'units', p_units)
  );

  return v_entry;
end;
$$;

-- ===========================================================================
-- FIX 5 (CRITICAL, spec-compliance lens's own re-derivation of ISS-2026-093)
-- -- app.approval_requests.ended_reason is readable via a raw-table SELECT by
-- ANY active tenant member of ANY domain (Finance/Commercial/Procurement/
-- HR) -- zero permission of any kind required, a materially LOWER bar than
-- even the app.audit_logs.reason vector ISS-2026-093 disclosed (which
-- requires at least tenant_admin). Live-reproduced: viewer@hrt2771.test (a
-- plain Viewer role, zero HRS permission) reads a real onboarding case
-- cancellation's ended_reason ("reorg cancelled the exit") straight off
-- app.approval_requests via a raw select, with no RPC involved at all.
--
-- This is genuinely Platform Core (PLT-123) infrastructure shared by every
-- domain -- unlike ISS-2026-093's own audit-log duplication (a FUNCTION-BODY
-- change inside app.cancel_approval_request touching every domain's own
-- approval-cancellation call path, needing re-verification of each domain's
-- regression suite -- correctly left disclosed, not fixed, in
-- docs/runtime/KNOWN_ISSUES.md), a raw-table GRANT restriction carries near-
-- zero behavioral risk: verified live via `information_schema.columns` and a
-- repo-wide grep that NO existing RPC anywhere in this repository returns
-- ended_reason to a broad caller (app.get_approval_request_history reads the
-- PER-STEP app.approval_decisions.reason, a different column on a different
-- table, already gated by app.check_approval_request_authority -- untouched
-- here) and that every raw TypeScript read of this table
-- (server/queries/{procurement-approval,credit,quotation-approval,leave}.ts)
-- already selects only `id, entity_type, entity_id` -- never ended_reason.
-- Restricting this one column is therefore a pure closure of an unused,
-- unintended raw-table bypass (the identical C-08 "verified clean" shape
-- 20260731200000 itself used for its own five HR tables), not a narrowing of
-- any real caller's existing functionality. Mirrors 20260731200000's own
-- established two-statement shape (whole-table revoke + explicit column
-- re-grant, since the ORIGINAL grant here is also a plain whole-table grant,
-- not already column-restricted -- a bare column-level revoke against it
-- would be the exact no-op HRT-293's own §5 item 4 self-found and fixed).
--
-- Deliberately NOT fixed here (remains open, disclosed): the app.audit_logs
-- duplication itself (ISS-2026-093's own named vector, requiring a change to
-- app.cancel_approval_request's function body) -- that fix genuinely does
-- carry the larger, cross-domain blast radius ISS-2026-093's own reasoning
-- describes, and stays a dedicated Platform Core follow-up. See
-- docs/runtime/KNOWN_ISSUES.md ISS-2026-098 for the full, corrected
-- disposition (a new entry -- ISS-2026-093's own existing text is untouched,
-- per this repository's append-only KNOWN_ISSUES.md discipline).
-- ===========================================================================
revoke select on app.approval_requests from authenticated;
grant select (
  id, tenant_id, config_version_id, entity_type, entity_id, pattern, status, idempotency_key,
  requested_by_auth_user_id, requested_by, started_at, ended_at,
  record_version, created_at, updated_at
) on app.approval_requests to authenticated;

comment on table app.approval_requests is
  'PLT-123 (20260719090000); batch 291-293 Tier C fix (20260731210000, Finding 5 CRITICAL, self-found sibling of ISS-2026-093): ended_reason excluded from the raw-table grant to authenticated -- it can carry the identical free-text cancellation/rejection narrative every domain''s own approval-consuming capability passes through app.cancel_approval_request/app.decide_approval_step, with RLS admitting any active tenant member (zero permission). No existing RPC returns this column to a broad caller (app.get_approval_request_history reads the separate, differently-gated app.approval_decisions.reason instead), so this is a pure closure of an unused bypass.';

-- ===========================================================================
-- FIX 6 (self-found sibling of Finding A, disclosed as ISS-2026-092, Medium,
-- by HRT-293 -- re-assessed and fixed here per the spec-compliance lens's own
-- re-derivation: identical access bar as Finding A's raw-table vector, which
-- was rated CRITICAL). Precise starting shape, re-verified live against
-- `information_schema.column_privileges` before writing this fix (not
-- assumed from a single-line grep, which misses the multi-line grant
-- statement this table actually uses): 20260730830000's own
-- `grant select (...) on app.employee_change_requests to authenticated`
-- (line 2839-2842) is ALREADY column-restricted -- it correctly excludes
-- current_value_snapshot/requested_value (the two raw PII VALUE columns) but
-- WRONGLY INCLUDES reason/decided_reason (an employee's own free-text reason
-- for requesting a personal_email/phone/address correction, and HR's own
-- decision rationale -- every legal field_key on this table is
-- employee_change_requests_field_key_check-restricted to personal_email/
-- personal_phone/personal_address_*, so this narrative is always personal-
-- contact-adjacent, exactly ISS-2026-092's own finding). RLS
-- (employee_change_requests_select_scoped) admits any active tenant member,
-- zero HRS permission of any kind -- the identical mechanism and access bar
-- as Finding A (CRITICAL), differing only in content scope.
-- (app/(tenant)/[tenantSlug]/hris/employees/[masterRecordId]/page.tsx reads
-- this table directly via .select("*"), per that file's own now-corrected
-- comment.)
--
-- Fix mirrors Finding A's own established shape exactly: the raw-table grant
-- is revoked and re-granted restricted to structural columns only (also
-- newly excluding current_value_snapshot/requested_value at the RPC-return
-- layer below, defense in depth, even though the raw grant already excluded
-- them); a new masked RPC (app.get_employee_change_requests, self-or-
-- HRS:View-personal-data, matching app.get_employee_profile's own
-- v_unmasked convention) is the only legitimate read path; the page is
-- updated in the SAME commit (a bare select("*") against a column-restricted
-- table is rejected outright by Postgres), exactly like 20260731200000's own
-- employee_position_assignments/positions/[positionId]/page.tsx precedent.
-- ===========================================================================
revoke select on app.employee_change_requests from authenticated;
grant select (
  id, tenant_id, master_record_id, requested_by_user_id, field_key, status,
  decided_by, decided_at, record_version, created_at, updated_at
) on app.employee_change_requests to authenticated;

comment on table app.employee_change_requests is
  'HRT-274 (20260730830000); batch 291-293 Tier C fix (20260731210000, Finding 6, self-found sibling of ISS-2026-092): reason/decided_reason excluded from the raw-table grant (current_value_snapshot/requested_value were already correctly excluded) -- every legal field_key on this table is personal_email/personal_phone/personal_address_* (employee_change_requests_field_key_check), so these columns always carry a classified personal-data value or narrative about it. The only legitimate read path is now app.get_employee_change_requests (self-or-HRS:View-personal-data masked).';

create function app.get_employee_change_requests(p_master_record_id uuid, p_actor_auth_user_id uuid)
returns table (
  id uuid, master_record_id uuid, requested_by_user_id uuid, field_key text,
  current_value_snapshot text, requested_value text, reason text,
  status text, decided_by text, decided_at timestamptz, decided_reason text,
  record_version integer, created_at timestamptz
)
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_employee app.employees;
  v_caller_user_id uuid;
  v_is_self boolean;
  v_decision app.rbac_decision;
  v_unmasked boolean;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  select * into v_employee from app.employees e where e.master_record_id = p_master_record_id;
  if not found or not app.has_active_tenant_membership(v_employee.tenant_id, p_actor_auth_user_id) then
    raise exception 'employee_not_found: %', p_master_record_id using errcode = 'no_data_found';
  end if;

  select u.id into v_caller_user_id from app.users u where u.auth_user_id = p_actor_auth_user_id and u.tenant_id = v_employee.tenant_id;
  v_is_self := v_caller_user_id is not null and v_employee.user_id is not distinct from v_caller_user_id;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_employee.tenant_id, 'HRS', 'View');
  if not v_decision.allowed and not v_is_self then
    raise exception 'insufficient_authority: identity % lacks HRS:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_employee.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  -- Own-profile access never requires the HR permission -- mirrors app.
  -- get_employee_profile's own v_unmasked convention exactly (decision:
  -- self OR HRS:View personal data).
  v_unmasked := v_is_self or app.has_view_personal_data(v_employee.tenant_id, p_actor_auth_user_id);

  return query
  select
    r.id, r.master_record_id, r.requested_by_user_id, r.field_key,
    case when v_unmasked then r.current_value_snapshot else null end,
    case when v_unmasked then r.requested_value else null end,
    case when v_unmasked then r.reason else null end,
    r.status, r.decided_by, r.decided_at,
    case when v_unmasked then r.decided_reason else null end,
    r.record_version, r.created_at
  from app.employee_change_requests r
  where r.master_record_id = p_master_record_id
  order by r.created_at desc;
end;
$$;

comment on function app.get_employee_change_requests is 'Batch 291-293 Tier C fix (20260731210000, Finding 6): the masked read path for app.employee_change_requests, closing ISS-2026-092. current_value_snapshot/requested_value/reason/decided_reason are nulled unless the caller is the employee themselves (v_is_self) or holds HRS:View personal data -- field_key/status/decided_by/decided_at are structural and always visible to any HRS:View holder, matching app.get_employee_profile''s own established masking shape.';

-- Per ERR-2026-004/20260717095000 ("every migration going forward carries its
-- own explicit, redundant REVOKE EXECUTE ... FROM PUBLIC statement"): this
-- migration creates one genuinely new function (app.get_employee_change_
-- requests, above). Self-found live: relying on the schema-wide `alter
-- default privileges` alone was NOT sufficient here (has_function_privilege
-- ('public', ...) returned true for the new function before this explicit
-- statement was added) -- the same defense-in-depth, directly-provable
-- guarantee 20260731160000/20260731170000 each apply for their own new
-- functions is required here too, never assumed from the default-privileges
-- mechanism alone.
revoke execute on all functions in schema app from public;

grant execute on function app.get_employee_change_requests(uuid, uuid) to authenticated, service_role;
