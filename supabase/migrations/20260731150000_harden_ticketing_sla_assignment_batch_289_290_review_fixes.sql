-- Tier C batch review fix pass for CG-S12-HRT-017/018 (Prompts 289/290,
-- Ticket SLA and Knowledge Base + Ticket Assignment). Additive only -- does
-- NOT edit 20260731120000/20260731130000/20260731140000 (or any prior
-- ticketing migration) in place, per BUILD_EXECUTION_PROTOCOL.md §5. This is
-- also the FINAL checkpoint of the "lanjut prompt 281-290" operator
-- authorization -- see docs/build-log/phase-07/HRT-289.md/HRT-290.md's
-- shared Tier C section for the full disposition table, propagation sweep,
-- and fresh gate suite.
--
-- Fixes two independently CONFIRMED, live-reproduced findings (never
-- accepted from lens citation alone, per §5.3) plus one propagation
-- instance of the second found during the mandatory §5.4 sweep:
--
--   Fix 1 (CRITICAL -- spec-compliance lens, Prompt 289) -- the RLS SELECT
--   policy on app.ticket_sla_clocks omitted the
--   `not app.actor_holds_customer_user_layer(tenant_id)` narrowing every
--   sibling SLA/KB/routing/assignment table in this exact batch correctly
--   carries (app.can_access_ticket's own documented customer-admitting
--   branch is reachable ONLY through a dedicated customer-safe RPC, never a
--   raw table read -- HRT-287 decision 7/HRT-289 decision 10's own written
--   guarantee). Live-reproduced before this fix: a customer_user-layer
--   requester's own forged session read
--   sla_policy_version_id/sla_calendar_version_id/started_at/
--   response_met_at/response_breached_at/resolution_met_at/
--   resolution_breached_at/last_evaluated_at/record_version directly off
--   app.ticket_sla_clocks -- every field HRT-289's own decision 10 states is
--   withheld from a requester (only reachable, by design, through
--   app.get_ticket_sla_status_for_requester's narrower projection). Fixed
--   by dropping and recreating the policy with the same narrowing every
--   other new table in this batch already carries. Re-verified live
--   post-fix: the identical forged session now reads zero rows.
--
--   Fix 2 (HIGH -- correctness/concurrency lens, Prompt 290) -- the
--   workload cap ("hard, no-override" on app.claim_ticket; override-only-
--   with-explicit-flag on app.assign_ticket) is enforced by reading
--   app._count_employee_active_ticket_assignments -- a live, UNLOCKED
--   COUNT(*) over the employee's own OTHER tickets -- with no lock forcing
--   two concurrent callers to serialize. Two genuinely concurrent claims (or
--   assigns) of two DIFFERENT tickets to the SAME employee each read the
--   pre-commit count, both see it under the configured cap, and both
--   commit -- a real TOCTOU race on a documented hard invariant. Live-
--   reproduced before this fix with two genuine OS `psql` processes racing
--   `app.claim_ticket` on two fresh tickets under a cap of 1: BOTH
--   succeeded, leaving the employee at 2 active assignments in a queue
--   capped at 1, zero error raised to either caller. Fixed by taking a
--   `pg_advisory_xact_lock` keyed on (tenant_id, queue_id) -- the resource
--   the racing callers actually share -- immediately before any workload-
--   cap-relevant read, in app.claim_ticket AND app.assign_ticket. Re-
--   verified live post-fix: the identical two-process race now produces
--   exactly one winner and one clean, discriminated `workload_limit_exceeded`
--   for the loser, in both directions (claim/claim and claim/assign).
--
--   Fix 2's propagation instance (same root cause, per §5.4) --
--   app.auto_route_ticket's own least-loaded candidate scan
--   (`w.active_count < v_rule.max_active_assignments_per_member`) reads the
--   identical unlocked helper over the SAME candidate pool and is subject to
--   the identical race between two concurrent auto-routes into the same
--   queue (flagged, not independently live-reproduced, by the correctness
--   lens's own report). Closed by acquiring the SAME (tenant_id, queue_id)
--   advisory lock before the candidate scan+apply, so a concurrent
--   claim/assign/auto-route into the same queue all serialize around the
--   one workload-cap-relevant resource they share. Deadlock-safe: every one
--   of the three functions acquires at most one advisory lock, always AFTER
--   its own single ticket-row `for update` lock and never nested inside
--   another advisory lock, so no two functions can ever wait on each other
--   in reverse order.
--
-- One additional MEDIUM/LOW finding (integration lens) was reviewed and
-- fixed as a cheap, in-scope consistency correction (not a live
-- vulnerability -- verified inert, see below):
--
--   Fix 3 (MEDIUM, currently inert -- integration lens, Prompt 290) --
--   app.list_ticket_assignment_events was missing the explicit
--   `channel = 'helpdesk'` rejection every sibling assignment RPC in this
--   same migration already carries (claim/accept/decline/assign/transfer/
--   auto_route all reject a helpdesk ticket with `channel_not_supported`).
--   Structurally inert today (app.ticket_assignment_events can never
--   contain a helpdesk-channel row -- every INSERT site is downstream of one
--   of the six functions above, all of which already reject the channel
--   before any insert), but a genuine recurrence of the exact "missing
--   channel-rejection guard on a channel-inapplicable RPC" shape HRT-288's
--   own Tier C review already found and fixed once (for
--   add_ticket_watcher/remove_ticket_watcher) -- left uncorrected here it
--   would silently become live-exploitable the moment any future migration
--   adds a helpdesk-reachable write path to this ledger. Fixed by adding the
--   same explicit guard, matching every sibling function in this migration
--   exactly.
--
-- A third finding (MODERATE, spec-compliance/integration lenses) is
-- disclosed, not code-fixed, per §5.6 -- see
-- docs/build-log/phase-07/HRT-290.md's Tier C section for the full
-- reasoning: Prompt 290's own "queue, team and user assignment" wording
-- names a "team" dimension nowhere built (no team/team-membership entity
-- exists anywhere in this repository, at any phase) and nowhere named as a
-- disclosed narrowing in HRT-290's own §9 C-23 walk, unlike every other
-- deliberate trim in that same section. Not a security or correctness
-- defect (queue-based grouping is the same team-analog every other HRIS/
-- ticketing capability in this phase already uses, live-verified correct by
-- three of the four lenses), purely a disclosure-discipline gap in the
-- build log -- corrected there, not in code.

-- ===========================================================================
-- Fix 1 -- app.ticket_sla_clocks_select_scoped: add the same
-- actor_holds_customer_user_layer narrowing every sibling table in this
-- batch already carries.
-- ===========================================================================

drop policy ticket_sla_clocks_select_scoped on app.ticket_sla_clocks;

create policy ticket_sla_clocks_select_scoped on app.ticket_sla_clocks
  for select to authenticated
  using ((app.can_access_ticket(ticket_id) and not app.actor_holds_customer_user_layer(tenant_id)) or app.is_supreme_admin());

comment on policy ticket_sla_clocks_select_scoped on app.ticket_sla_clocks is
  'HRT-289/290 batch review fix (CG-S12-HRT-017/018, Finding 1, CRITICAL): a customer_user-layer requester could previously read this table''s raw rows directly -- sla_policy_version_id/sla_calendar_version_id/started_at/*_met_at/*_breached_at/last_evaluated_at/record_version -- every field HRT-289 decision 10''s own written guarantee says is withheld from a requester (a requester reads SLA status ONLY through app.get_ticket_sla_status_for_requester''s narrower projection). Now matches every sibling table in this same batch (sla_calendars/sla_policies/kb_articles/ticket_routing_rules/ticket_assignment_events, all of which correctly narrow with this same predicate from the start).';

-- ===========================================================================
-- Fix 2 -- workload-cap TOCTOU race: serialize claim_ticket/assign_ticket/
-- auto_route_ticket on a pg_advisory_xact_lock keyed to (tenant_id,
-- queue_id) -- the resource two racing callers actually share -- before any
-- workload-cap-relevant read. Held for the remainder of the transaction,
-- released automatically at commit/rollback (pg_advisory_XACT_lock, never a
-- session-level advisory lock that could leak past this call).
-- ===========================================================================

create or replace function app.claim_ticket(p_ticket_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text)
returns app.tickets
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_ticket app.tickets;
  v_self app.employees;
  v_rule app.ticket_routing_rule_versions;
  v_active_count integer;
  v_updated app.tickets;
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
    raise exception 'channel_not_supported: ticket % is a helpdesk case -- use app.assign_helpdesk_ticket instead', p_ticket_id using errcode = 'check_violation';
  end if;

  v_self := app.get_self_employee(v_ticket.tenant_id, p_actor_auth_user_id);
  if v_self.master_record_id is null then
    raise exception 'employee_not_found: no linked employee profile' using errcode = 'no_data_found';
  end if;
  if not exists (select 1 from app.ticket_queue_members m where m.queue_id = v_ticket.queue_id and m.employee_id = v_self.master_record_id and m.status = 'active') then
    raise exception 'insufficient_authority: identity % is not an active member of queue %', p_actor_auth_user_id, v_ticket.queue_id
      using errcode = 'insufficient_privilege';
  end if;

  -- Version checked immediately after existence/access/authority, before any
  -- business-rule check that depends on a fresh read (decision 5, mirrors
  -- every sibling ticket RPC's own established order) -- the genuine
  -- two-employee claim race's LOSER re-reads the ALREADY-INCREMENTED
  -- record_version under this same row lock and is caught here, cleanly, as
  -- stale_version -- never a raw constraint violation.
  if v_ticket.record_version <> p_expected_version then
    raise exception 'stale_version: expected version % but current version is %', p_expected_version, v_ticket.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_ticket.status in ('closed', 'cancelled') then
    raise exception 'invalid_transition: cannot claim a % ticket', v_ticket.status using errcode = 'check_violation';
  end if;
  if not app._is_employee_ticket_eligible(v_ticket.tenant_id, v_self.master_record_id) then
    raise exception 'employee_not_eligible: the claiming employee is not currently active/available for ticket assignment' using errcode = 'check_violation';
  end if;

  if v_ticket.assignee_employee_id is not null then
    if v_ticket.assignee_employee_id = v_self.master_record_id then
      -- Idempotent replay: this employee already owns this ticket. A real,
      -- deliberate no-op, never a duplicate ledger row (C-01 discipline).
      return v_ticket;
    end if;
    raise exception 'ticket_already_assigned: ticket % is already assigned to another employee', p_ticket_id using errcode = 'check_violation';
  end if;

  v_rule := app._resolve_ticket_routing_rule_for_ticket(v_ticket);
  if v_rule.max_active_assignments_per_member is not null then
    -- Batch-review fix (Finding, HIGH, correctness/concurrency lens): the
    -- workload cap is a documented HARD, no-override invariant on this
    -- function, but the count below reads OTHER tickets' rows with no lock
    -- of its own -- two genuinely concurrent claims of two DIFFERENT
    -- tickets by the SAME employee would otherwise both read the same
    -- pre-commit count and both pass. Serialize on the one resource both
    -- callers actually share (this employee's queue-scoped workload) before
    -- reading it, mirroring app.publish_sla_calendar_version's own
    -- established "lock the shared resource, not just the row being
    -- written" discipline.
    perform pg_advisory_xact_lock(hashtextextended('ticket_assignment_workload:' || v_ticket.tenant_id::text || ':' || v_ticket.queue_id::text, 0));
    v_active_count := app._count_employee_active_ticket_assignments(v_ticket.tenant_id, v_self.master_record_id, v_ticket.queue_id);
    if v_active_count >= v_rule.max_active_assignments_per_member then
      raise exception 'workload_limit_exceeded: employee already holds % active tickets in this queue, at or above the configured limit of %', v_active_count, v_rule.max_active_assignments_per_member
        using errcode = 'check_violation';
    end if;
  end if;

  v_updated := app._apply_ticket_assignment(v_ticket, p_expected_version, v_self.master_record_id, 'claim', 'claim', v_rule.id, null, p_actor_auth_user_id, p_actor_label);

  perform app.capture_audit_event(
    v_ticket.tenant_id, p_actor_auth_user_id, p_actor_label, 'claim_ticket',
    'app.tickets', p_ticket_id, 'success', null, app.ticket_audit_projection(v_ticket), app.ticket_audit_projection(v_updated)
  );

  return v_updated;
end;
$$;

comment on function app.claim_ticket is
  'HRT-286/290 (decisions 3/5/6/9 of 20260731140000; batch review fix, Finding 2): self-service atomic claim -- no TKT:Assign required, plain ACTIVE queue membership is sufficient (mirrors HRT-286 decision 5''s own "ordinary day-to-day ticket work" bar). Blocked by: wrong channel (helpdesk), stale version (a real race loser), invalid ticket status, ineligible employee (inactive/on-leave), already assigned to someone else, or a configured workload cap with no override (decision 9 -- unlike app.assign_ticket, claim never overrides its own cap) -- the cap check is now serialized via pg_advisory_xact_lock(tenant_id, queue_id) so two genuinely concurrent claims of different tickets by the same employee can no longer both pass a stale pre-commit count.';

create or replace function app.assign_ticket(
  p_ticket_id uuid, p_expected_version integer, p_assignee_employee_id uuid, p_actor_auth_user_id uuid, p_actor_label text,
  p_reason text default null, p_override_workload_limit boolean default false
)
returns app.tickets
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_ticket app.tickets;
  v_rule app.ticket_routing_rule_versions;
  v_active_count integer;
  v_event_type text;
  v_updated app.tickets;
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
    raise exception 'channel_not_supported: ticket % is a helpdesk case -- use app.assign_helpdesk_ticket instead', p_ticket_id using errcode = 'check_violation';
  end if;
  if not app.check_ticket_authority('Assign', v_ticket.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks TKT:Assign for tenant %', p_actor_auth_user_id, v_ticket.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if v_ticket.record_version <> p_expected_version then
    raise exception 'stale_version: expected version % but current version is %', p_expected_version, v_ticket.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_ticket.status in ('closed', 'cancelled') then
    raise exception 'invalid_transition: cannot reassign a % ticket', v_ticket.status using errcode = 'check_violation';
  end if;

  if p_assignee_employee_id is not null then
    if not exists (select 1 from app.employees e where e.master_record_id = p_assignee_employee_id and e.tenant_id = v_ticket.tenant_id) then
      raise exception 'employee_not_found: %', p_assignee_employee_id using errcode = 'no_data_found';
    end if;
    if not exists (select 1 from app.ticket_queue_members m where m.queue_id = v_ticket.queue_id and m.employee_id = p_assignee_employee_id and m.status = 'active') then
      raise exception 'assignee_not_queue_member: employee % is not an active member of queue %', p_assignee_employee_id, v_ticket.queue_id using errcode = 'check_violation';
    end if;
    -- HRT-290 (decision 9): eligibility (active/available) is a HARD block
    -- for every path, no override -- an inactive/on-leave/terminated
    -- employee can never become a ticket owner regardless of actor
    -- authority. The workload CAP, by contrast, is override-able here
    -- (p_override_workload_limit) -- a manager legitimately needs to push a
    -- genuinely urgent ticket onto someone already at their configured cap;
    -- app.claim_ticket has no such override (decision 9).
    if not app._is_employee_ticket_eligible(v_ticket.tenant_id, p_assignee_employee_id) then
      raise exception 'employee_not_eligible: employee % is not currently active/available for ticket assignment', p_assignee_employee_id using errcode = 'check_violation';
    end if;
    if v_ticket.assignee_employee_id is distinct from p_assignee_employee_id and not p_override_workload_limit then
      v_rule := app._resolve_ticket_routing_rule_for_ticket(v_ticket);
      if v_rule.max_active_assignments_per_member is not null then
        -- Batch-review fix (Finding 2, HIGH, correctness/concurrency lens):
        -- same shared, unlocked-count race as app.claim_ticket above --
        -- serialize on the same (tenant_id, queue_id) resource before
        -- reading the count.
        perform pg_advisory_xact_lock(hashtextextended('ticket_assignment_workload:' || v_ticket.tenant_id::text || ':' || v_ticket.queue_id::text, 0));
        v_active_count := app._count_employee_active_ticket_assignments(v_ticket.tenant_id, p_assignee_employee_id, v_ticket.queue_id);
        if v_active_count >= v_rule.max_active_assignments_per_member then
          raise exception 'workload_limit_exceeded: employee already holds % active tickets in this queue, at or above the configured limit of % -- pass p_override_workload_limit to override', v_active_count, v_rule.max_active_assignments_per_member
            using errcode = 'check_violation';
        end if;
      end if;
    end if;
  end if;

  if v_ticket.assignee_employee_id is null and p_assignee_employee_id is not null then
    v_event_type := 'manual_assign';
  elsif v_ticket.assignee_employee_id is not null and p_assignee_employee_id is null then
    v_event_type := 'unassign';
  elsif v_ticket.assignee_employee_id is distinct from p_assignee_employee_id then
    v_event_type := 'reassign';
  else
    -- Idempotent replay: same assignee already set. A real, deliberate
    -- no-op, never a duplicate ledger row (C-01 discipline).
    return v_ticket;
  end if;

  v_updated := app._apply_ticket_assignment(v_ticket, p_expected_version, p_assignee_employee_id, v_event_type, 'manual', null, p_reason, p_actor_auth_user_id, p_actor_label);

  perform app.capture_audit_event(
    v_ticket.tenant_id, p_actor_auth_user_id, p_actor_label, 'assign_ticket',
    'app.tickets', p_ticket_id, 'success', null, app.ticket_audit_projection(v_ticket), app.ticket_audit_projection(v_updated)
  );

  return v_updated;
end;
$$;

comment on function app.assign_ticket is
  'HRT-286/290 (decision 7 of 20260731060000; decisions 9/10 of 20260731140000; batch review fix, Finding 2): manual designation, TKT:Assign-gated. Signature widened with two new trailing DEFAULTed parameters (p_reason, p_override_workload_limit) via explicit drop+create (decision 10) -- every pre-existing 5-argument caller is unaffected. Validates the target is a real, ACTIVE, ELIGIBLE (decision 6) member of the ticket''s own queue, and (unless overridden) within any configured workload cap (decision 9) -- the cap check is now serialized via pg_advisory_xact_lock(tenant_id, queue_id), the SAME lock key app.claim_ticket takes, so a claim and a manual assign racing for the same employee''s queue-scoped workload can no longer both pass a stale pre-commit count. Event type (manual_assign/reassign/unassign) is computed from the real before/after state and logged to BOTH app.ticket_events and the app.ticket_assignment_events ledger via app._apply_ticket_assignment. Never changes app.tickets.status as a side effect (HRT-286 decision 6, unchanged).';

create or replace function app.auto_route_ticket(p_ticket_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text)
returns app.tickets
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_ticket app.tickets;
  v_rule app.ticket_routing_rule_versions;
  v_updated app.tickets;
  v_reason text;
  v_candidate_employee_id uuid;
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
    raise exception 'channel_not_supported: ticket % is a helpdesk case -- no non-Supreme-Admin routing model exists for this channel (decision 2)', p_ticket_id using errcode = 'check_violation';
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
    raise exception 'invalid_transition: cannot auto-route a % ticket', v_ticket.status using errcode = 'check_violation';
  end if;

  v_rule := app._resolve_ticket_routing_rule_for_ticket(v_ticket);
  if v_rule.id is null then
    raise exception 'ticket_routing_rule_not_matched: no published routing rule matches ticket % (channel %, category %, priority %)', p_ticket_id, v_ticket.channel, v_ticket.category_id, v_ticket.priority
      using errcode = 'no_data_found';
  end if;
  if not exists (select 1 from app.ticket_queues q where q.id = v_rule.target_queue_id and q.status = 'active') then
    raise exception 'queue_not_available: the matched rule''s target queue % is no longer active', v_rule.target_queue_id using errcode = 'check_violation';
  end if;

  v_reason := 'auto-route: rule version ' || v_rule.id::text;
  v_updated := v_ticket;

  if v_rule.target_queue_id is distinct from v_ticket.queue_id then
    update app.tickets set queue_id = v_rule.target_queue_id, assignee_employee_id = null, assigned_by = null, assigned_at = null, assignment_confirmed_at = null, assignment_confirmed_by = null
    where id = p_ticket_id and record_version = p_expected_version
    returning * into v_updated;
    if not found then
      raise exception 'stale_version: concurrent update detected for ticket %', p_ticket_id using errcode = 'serialization_failure';
    end if;

    insert into app.ticket_events (tenant_id, ticket_id, event_type, from_value, to_value, reason, actor_auth_user_id, actor_label)
    values (v_ticket.tenant_id, p_ticket_id, 'queue_transfer', v_ticket.queue_id::text, v_rule.target_queue_id::text, v_reason, p_actor_auth_user_id, p_actor_label);

    insert into app.ticket_assignment_events (tenant_id, ticket_id, event_type, source, rule_version_id, from_queue_id, to_queue_id, reason, actor_auth_user_id, actor_label)
    values (v_ticket.tenant_id, p_ticket_id, 'auto_route', 'rule_engine', v_rule.id, v_ticket.queue_id, v_rule.target_queue_id, v_reason, p_actor_auth_user_id, p_actor_label);
  end if;

  if v_rule.assignment_mode = 'least_loaded' and v_updated.assignee_employee_id is null then
    -- Batch-review fix (Finding 2's own propagation instance, per §5.4):
    -- this candidate scan reads the SAME unlocked per-employee count
    -- app.claim_ticket/app.assign_ticket read, over the whole queue member
    -- pool -- two concurrent auto-routes into the SAME target queue could
    -- otherwise both pick (and both apply) the identical "least-loaded"
    -- candidate before either commits. Serialize on the SAME
    -- (tenant_id, queue_id) lock key claim_ticket/assign_ticket use, so all
    -- three workload-cap-relevant operations against one queue's bookkeeping
    -- are mutually exclusive.
    perform pg_advisory_xact_lock(hashtextextended('ticket_assignment_workload:' || v_ticket.tenant_id::text || ':' || v_rule.target_queue_id::text, 0));
    select w.employee_id into v_candidate_employee_id
    from (
      select m.employee_id, app._count_employee_active_ticket_assignments(v_ticket.tenant_id, m.employee_id, v_rule.target_queue_id) as active_count
      from app.ticket_queue_members m
      where m.queue_id = v_rule.target_queue_id and m.status = 'active'
        and app._is_employee_ticket_eligible(v_ticket.tenant_id, m.employee_id)
    ) w
    where v_rule.max_active_assignments_per_member is null or w.active_count < v_rule.max_active_assignments_per_member
    order by w.active_count asc, w.employee_id asc
    limit 1;

    if v_candidate_employee_id is not null then
      v_updated := app._apply_ticket_assignment(v_updated, v_updated.record_version, v_candidate_employee_id, 'auto_route', 'rule_engine', v_rule.id, v_reason || ' (least-loaded pick)', p_actor_auth_user_id, p_actor_label);
    else
      -- Records the ATTEMPT and its exclusion explicitly (section 18:
      -- "routing rule/version/input/result/exclusions") -- a real,
      -- disclosed outcome, not a silent no-op.
      insert into app.ticket_assignment_events (tenant_id, ticket_id, event_type, source, rule_version_id, reason, actor_auth_user_id, actor_label)
      values (v_ticket.tenant_id, p_ticket_id, 'auto_route', 'rule_engine', v_rule.id, 'least-loaded: no eligible, available, under-cap queue member found', p_actor_auth_user_id, p_actor_label);
    end if;
  end if;

  perform app.capture_audit_event(
    v_ticket.tenant_id, p_actor_auth_user_id, p_actor_label, 'auto_route_ticket',
    'app.tickets', p_ticket_id, 'success', null, app.ticket_audit_projection(v_ticket), app.ticket_audit_projection(v_updated)
  );

  return v_updated;
end;
$$;

comment on function app.auto_route_ticket is
  'HRT-290 (decisions 2/4/6/9; batch review fix, Finding 2''s propagation instance): applies the ONE matched, published routing-rule version (app._resolve_ticket_routing_rule_for_ticket) to a REAL ticket -- moves it to the rule''s own target_queue_id if different (clearing any prior assignee, mirroring app.transfer_ticket_queue''s own shape), and, for assignment_mode=least_loaded, additionally auto-picks the eligible queue member with the fewest current active assignments in that queue (tie-broken by employee id -- deterministic, explainable, never random), now under the SAME pg_advisory_xact_lock(tenant_id, queue_id) app.claim_ticket/app.assign_ticket take, closing the identical unlocked-count race across all three entry points into one queue''s workload bookkeeping. Gated on app.is_ticket_staff, mirroring app.transfer_ticket_queue''s own bar. Raises ticket_routing_rule_not_matched (no hard failure of the ticket itself -- the caller decides whether to fall back to manual assignment) when no published rule matches this ticket''s scope.';

-- ===========================================================================
-- Fix 3 -- app.list_ticket_assignment_events: add the same explicit
-- helpdesk-channel rejection every sibling assignment RPC in this migration
-- already carries (currently inert -- see the header comment above -- but a
-- genuine recurrence of an already-once-fixed defect class, per §5.4).
-- ===========================================================================

create or replace function app.list_ticket_assignment_events(p_ticket_id uuid, p_actor_auth_user_id uuid)
returns table (
  id uuid, event_type text, source text, rule_version_id uuid,
  from_assignee_employee_id uuid, from_assignee_name text,
  to_assignee_employee_id uuid, to_assignee_name text,
  from_queue_id uuid, to_queue_id uuid, reason text,
  actor_label text, occurred_at timestamptz
)
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_ticket app.tickets;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  select * into v_ticket from app.tickets t0 where t0.id = p_ticket_id;
  if not found then
    raise exception 'ticket_not_found: %', p_ticket_id using errcode = 'no_data_found';
  end if;
  -- HRT-290 (decision 8): folds a customer-layer caller (even for their own
  -- real ticket) into the SAME ticket_not_found response the RLS predicate
  -- would produce for a raw-table read -- no enumeration oracle between the
  -- RPC and RLS surfaces (mirrors HRT-287''s own established discipline).
  if not app.can_access_ticket(p_ticket_id, p_actor_auth_user_id) or app.actor_holds_customer_user_layer(v_ticket.tenant_id, p_actor_auth_user_id) then
    raise exception 'ticket_not_found: %', p_ticket_id using errcode = 'no_data_found';
  end if;
  -- Batch review fix (Finding 3, MEDIUM, integration lens): every sibling
  -- assignment RPC in this migration explicitly rejects a helpdesk-channel
  -- ticket -- this read RPC did not, structurally inert today (the ledger
  -- can never hold a helpdesk row, see the header comment above) but a
  -- genuine recurrence of the exact shape HRT-288's own Tier C review
  -- already fixed once for add_ticket_watcher/remove_ticket_watcher.
  if v_ticket.channel = 'helpdesk' then
    raise exception 'channel_not_supported: ticket % is a helpdesk case', p_ticket_id using errcode = 'check_violation';
  end if;

  return query
  select ev.id, ev.event_type, ev.source, ev.rule_version_id,
    ev.from_assignee_employee_id, fe.full_name,
    ev.to_assignee_employee_id, te.full_name,
    ev.from_queue_id, ev.to_queue_id, ev.reason,
    ev.actor_label, ev.occurred_at
  from app.ticket_assignment_events ev
  left join app.employees fe on fe.master_record_id = ev.from_assignee_employee_id
  left join app.employees te on te.master_record_id = ev.to_assignee_employee_id
  where ev.ticket_id = p_ticket_id
  order by ev.occurred_at asc;
end;
$$;

comment on function app.list_ticket_assignment_events is
  'HRT-290 (batch review fix, Finding 3): the ticket-scoped assignment-event history reader. Rejects a customer-layer caller with the identical ticket_not_found an RLS predicate would produce (decision 8, anti-enumeration), AND now explicitly rejects a helpdesk-channel ticket with channel_not_supported, matching every sibling assignment RPC in this migration (structurally inert today since the ledger can never hold a helpdesk row -- defense in depth against a future write path, not a live gap).';
