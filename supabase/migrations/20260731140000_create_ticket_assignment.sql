-- Phase 7 (HRIS and Ticketing) capability CG-S12-HRT-018 (Ticket Assignment,
-- Prompt 290) -- explainable, versioned routing rules and governed
-- queue/team/user assignment across the canonical ticket model HRT-286/287/
-- 288 built and HRT-289 extended with SLA. Additive only --
-- 20260731060000/070000/080000/090000/100000/110000/120000/130000 are NOT
-- edited in place, per AGENTS.md. Second and FINAL prompt of the authorized
-- "lanjut prompt 281-290" batch; a combined Tier C review runs across
-- Prompts 289 and 290 together after this migration lands.
--
-- MANDATORY reading this migration is built against and does not repeat:
-- 290_TICKET_ASSIGNMENT_PROMPT.md; the three-channel ticket model
-- (20260731060000/080000/100000); HRT-286's own decision 7 (assign_ticket's
-- own comment: "Prompt 290 owns real auto-routing and will layer it on top
-- of THIS SAME column, never redesign it"); HRT-288's own decision 6 (why
-- assign_ticket/transfer_ticket_queue/update_ticket_classification reject a
-- helpdesk-channel ticket, and the dedicated Supreme-Admin-gated siblings
-- that exist instead); HRT-289's own precedence-ranking/supersede-on-publish
-- pattern (app.resolve_effective_sla_policy_version /
-- app.publish_sla_policy_version), reused verbatim, not rediscovered.
--
-- Design decisions, disclosed (mirrors every prior HRT ticketing checkpoint's
-- own discipline):
--
-- 1. **No second ticket table, no second "who owns this ticket" store.**
--    `app.tickets.assignee_employee_id` (internal/customer) and
--    `app.tickets.assignee_support_auth_user_id` (helpdesk, HRT-288) remain
--    the ONE current-owner columns -- every function below reads and writes
--    through them, never a parallel "current assignment" table. The new
--    `app.ticket_assignment_events` table below is a ledger (history), never
--    a second source of truth for "who is assigned now" -- section 13's own
--    "workload snapshot/reference... never a second source of truth" applies
--    to the whole capability, not merely the workload query.
--
-- 2. **The routing-rule engine and its new ledger/claim/accept/decline
--    machinery are bounded to `internal`/`customer` channels, matching
--    HRT-288's own established, precedented shape -- never fought.**
--    `assign_ticket`/`transfer_ticket_queue` already explicitly reject a
--    helpdesk-channel ticket (HRT-288 decision 6), because helpdesk staffing
--    is Supreme-Admin-authority-only with no queue-membership roster to
--    route among (HRT-288 decision 3: "no dedicated Platform Support Team
--    role distinct from Supreme Admin exists"). `app.claim_ticket`/
--    `app.accept_ticket_assignment`/`app.decline_ticket_assignment`/
--    `app.auto_route_ticket` below all explicitly reject `channel='helpdesk'`
--    the SAME way, pointing callers at the existing, unmodified
--    `app.assign_helpdesk_ticket`/`app.transfer_helpdesk_support_queue` --
--    never a fourth eligibility model bolted onto a channel that has none.
--    `app.ticket_routing_rule_versions.channel` is therefore CHECK-restricted
--    to `('internal', 'customer')` only, not widened to helpdesk. This is a
--    bounded, disclosed LIMITATION, not an oversight: a future prompt that
--    introduces a real non-Supreme-Admin "Platform support agent" role could
--    widen this the same additive way HRT-287/288 widened `channel` itself.
--
-- 3. **Customer-channel tickets DO route/assign through the SAME internal
--    staff/queue mechanism as internal tickets -- re-confirmed by direct code
--    read of HRT-287's own `app.assign_ticket`/`app.transfer_ticket_queue`
--    (20260731080000/090000), which reject nothing for `channel='customer'`.**
--    The customer never SEES the assignee (HRT-287 decision 6: no
--    `assignee_employee_id`/`assignee_name` in any customer-facing
--    projection) -- but the STAFF-side eligibility/claim/routing model is
--    identical for internal and customer tickets, both keyed off
--    `app.ticket_queue_members` for the ticket's own `queue_id`. This
--    migration's own routing rules, claim/accept/decline, and workload
--    queries therefore apply uniformly to both channels; only the
--    CUSTOMER-FACING read surface (unchanged, HRT-287's own) continues to
--    omit assignee/queue identity, satisfying section 16's "customer
--    requesters cannot select or enumerate internal/support users" -- no new
--    customer-facing surface is added here, and every new function below is
--    reachable only by a caller who already passes `app.is_ticket_staff` or
--    an active `app.ticket_queue_members` row, both structurally unreachable
--    from a `customer_user`-layer identity (no `app.employees` row, no
--    `app.get_self_employee` match) -- live-tested, not merely assumed.
--
-- 4. **Routing precedence reuses HRT-289's own deterministic `rank()`
--    specificity-ranking + genuine-tie-raises-ambiguous pattern verbatim,
--    scoped to the two dimensions that actually vary here (category, then
--    priority, then an explicit `precedence_rank` tie-break) -- queue is the
--    engine's OUTPUT here, not an input scope dimension the way it was for
--    SLA policy matching.** `app.publish_ticket_routing_rule_version`
--    supersedes this SAME rule's own prior published version under a parent
--    row lock, applying HRT-289's own self-found Tier C fix
--    (`app.publish_sla_policy_version`'s "a revised version tied against its
--    own predecessor at resolution time" bug) FROM THE START here, rather
--    than rediscovering it.
--
-- 5. **Assignment concurrency is optimistic-version-plus-row-lock, matching
--    every prior ticket RPC in this repository -- no advisory lock
--    introduced.** `app.claim_ticket` takes `select ... for update` on the
--    target ticket exactly like `app.assign_ticket` always has; the genuine
--    two-employee claim race is resolved by ordinary Postgres row-lock
--    serialization -- the SECOND session's own re-read under the now-granted
--    lock observes the ALREADY-INCREMENTED `record_version`, so its own
--    `record_version <> p_expected_version` check (checked before the
--    business-rule checks, matching every sibling RPC's own established
--    order) raises a clean `stale_version`/`serialization_failure` for the
--    loser -- never a raw unique-constraint violation. A SEPARATE, narrower
--    business-rule check (`ticket_already_assigned`) exists for the genuinely
--    different case of a caller who supplies a CURRENT, correct version but
--    the ticket is already owned by someone else (not a race, an ordinary
--    "you're too late" outcome) -- live-tested with two real, concurrent OS
--    `psql` processes in `scripts/db-tests/ticketing-assignment.sql`.
--
-- 6. **Eligibility ("effective employee status, availability") reuses
--    EXISTING canonical concepts exclusively -- `app.employees.
--    lifecycle_status` (HRT-274) and `app.leave_requests` (HRT-278/280),
--    never a parallel "agent status" table.** `app._is_employee_ticket_
--    eligible` is true only when `lifecycle_status = 'active'` AND the
--    employee has no `status='approved'` leave request whose
--    `validity_range` contains the current date -- both facts already exist
--    and are already governed elsewhere; this migration adds no new
--    employee-status column.
--
-- 7. **"Delegation" is honestly disclosed as N/A for ticket routing, not
--    silently dropped (taxonomy C-23) -- a genuine design decision, not an
--    oversight.** This repository's one existing delegation concept
--    (`app.approval_delegations`, PLT-118/19090000) is scoped to APPROVAL
--    DECISION authority (a named delegate stands in for a named approver on
--    a specific approval step) -- a materially different shape from ticket
--    routing, where "coverage while an agent is away" is ALREADY provided by
--    queue-membership breadth itself: any other ACTIVE, ELIGIBLE member of
--    the same queue may already claim/be assigned any ticket in that queue,
--    with no named 1:1 backup required. Reusing `app.approval_delegations`
--    for ticket routing would misapply an approval-authority concept to an
--    unrelated domain (exactly the "never invent a parallel one" instruction
--    read the other way -- reusing the WRONG existing concept is not better
--    than reusing none). Inventing a NEW ticket-specific delegation grant
--    table is out of this bounded slice's mandate. Availability (decision 6)
--    is the mechanism that actually satisfies "temporary unavailability"
--    (section 22): an employee `on_leave` or on an approved, currently-dated
--    leave request is simply not counted eligible, and their work is picked
--    up by any other active queue member -- no named redirect needed.
--
-- 8. **The assignment ledger (`app.ticket_assignment_events`) is governed by
--    the SAME RLS as `app.ticket_events` (HRT-286 decision 9, HRT-287/288's
--    own widening) -- `can_access_ticket AND NOT customer_user-layer AND
--    channel <> 'helpdesk'` -- never `app.audit_logs`, whose readership (any
--    tenant's own plain `tenant_admin`) is broader than this ledger's real
--    audience.** `app.list_ticket_assignment_events` additionally folds a
--    customer-layer caller's own real ticket into the same `ticket_not_found`
--    response the RLS predicate would produce for a raw-table read, so there
--    is no observable difference between the RPC and RLS surfaces (C-05
--    discipline, anti-enumeration).
--
-- 9. **A workload cap is a HARD block on self-service `app.claim_ticket`,
--    but an EXPLICIT, disclosed, TKT:Assign-gated OVERRIDE on manager-driven
--    `app.assign_ticket`** (`p_override_workload_limit boolean default
--    false`, a new trailing, defaulted parameter). A manager legitimately
--    needs to push a genuinely urgent ticket onto someone already at their
--    configured cap; a self-serving agent should not be able to load-balance
--    around their own configured limit by claiming instead of waiting to be
--    assigned. Both paths otherwise share the identical eligibility
--    (lifecycle_status/leave) check with NO override -- an inactive/on-leave/
--    terminated employee can never become a ticket owner through either
--    path, regardless of actor authority.
--
-- 10. **`app.assign_ticket`'s signature genuinely widens (two new trailing
--     DEFAULTed parameters: `p_reason text`, `p_override_workload_limit
--     boolean`) -- an explicit `drop function if exists` + `create function`,
--     never a bare `create or replace`.** Per HRT-287's own established
--     discipline (this migration's own mandatory reading, its header): a
--     `create or replace` that ADDS a parameter to the type list actually
--     creates a SECOND, ambiguous overload rather than replacing the
--     original -- the exact C-02-adjacent trap that discipline exists to
--     avoid. `app.transfer_ticket_queue` gains ledger logging with its
--     signature UNCHANGED, so it stays a genuine `create or replace` (grants
--     preserved automatically); `app.assign_ticket`'s grant is explicitly
--     re-stated below after the drop.
--
-- 11. **A ticket link/assignment change touches ONLY the ticket's own
--     assignee field and this migration's own new ledger/rule tables --
--     nothing else** (business rule, section 24: "never broadens
--     linked-record access"). No function in this migration reads, writes,
--     or grants access to any shipment/invoice/warehouse/vendor/customer
--     record; live-tested directly by asserting a freshly-claimed ticket's
--     own assignee gains ZERO new grants on any unrelated record type
--     (mirrors HRT-287's own "a ticket link grants no access" proof).

-- ===========================================================================
-- 1. app.tickets -- additive columns: real "confirmed" state for accept
--    (decision 9's own note: accept has a real, tested effect, never a
--    no-op ledger-only action -- taxonomy C-20).
-- ===========================================================================

alter table app.tickets add column assignment_confirmed_at timestamptz;
alter table app.tickets add column assignment_confirmed_by text;

comment on column app.tickets.assignment_confirmed_at is
  'HRT-290: set by app.accept_ticket_assignment when the CURRENT assignee affirmatively confirms the assignment; cleared by every reassignment/unassignment/transfer/decline. NULL means "assigned but not yet confirmed" or "unassigned" -- never conflated with assigned_at, which records WHEN an assignee was set, not whether they accepted.';

-- ===========================================================================
-- 2. app.ticket_routing_rules / app.ticket_routing_rule_versions -- the
--    explainable, versioned routing-rule catalog (decisions 2/4).
-- ===========================================================================

create table app.ticket_routing_rules (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  code text not null,
  name text not null,
  status text not null default 'active',
  record_version integer not null default 1,
  created_by text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint ticket_routing_rules_status_check check (status in ('active', 'inactive')),
  constraint ticket_routing_rules_code_check check (length(trim(code)) > 0),
  constraint ticket_routing_rules_name_check check (length(trim(name)) > 0),
  constraint ticket_routing_rules_code_unique unique (tenant_id, code)
);

comment on table app.ticket_routing_rules is
  'HRT-290 (decision 4): the routing-rule family catalog -- mirrors app.sla_policies exactly (a stable "rule identity" whose versions carry the actual scope/target). One rule may accumulate many versions over time; only its own most recent PUBLISHED version is ever matched.';

create index ticket_routing_rules_tenant_status_idx on app.ticket_routing_rules (tenant_id, status);

create trigger ticket_routing_rules_touch before update on app.ticket_routing_rules
  for each row execute function app.touch_ticket_row();

create table app.ticket_routing_rule_versions (
  id uuid primary key default gen_random_uuid(),
  rule_id uuid not null references app.ticket_routing_rules (id),
  tenant_id uuid not null references app.tenants (id),
  version_number integer not null,
  status text not null default 'draft',
  channel text not null,
  category_id uuid references app.ticket_categories (id),
  priority text,
  target_queue_id uuid not null references app.ticket_queues (id),
  assignment_mode text not null default 'manual',
  max_active_assignments_per_member integer,
  precedence_rank integer not null default 0,
  published_at timestamptz,
  published_by text,
  record_version integer not null default 1,
  created_by text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint ticket_routing_rule_versions_status_check check (status in ('draft', 'published', 'superseded', 'archived')),
  constraint ticket_routing_rule_versions_channel_check check (channel in ('internal', 'customer')),
  constraint ticket_routing_rule_versions_priority_check check (priority is null or priority in ('low', 'normal', 'high', 'urgent')),
  constraint ticket_routing_rule_versions_mode_check check (assignment_mode in ('manual', 'least_loaded')),
  constraint ticket_routing_rule_versions_workload_check check (max_active_assignments_per_member is null or max_active_assignments_per_member > 0),
  constraint ticket_routing_rule_versions_version_unique unique (rule_id, version_number)
);

comment on table app.ticket_routing_rule_versions is
  'HRT-290 (decisions 2/4/9): the deterministic routing/eligibility scope for ONE published rule version -- channel restricted to internal/customer (decision 2, helpdesk has no eligibility model to route within). category_id/priority are each either an exact match or NULL ("applies to every value"); app._resolve_ticket_routing_rule_for_ticket ranks candidates by specificity (category set > priority set > explicit precedence_rank tie-break), raising ticket_routing_rule_ambiguous_match on a genuine tie -- never picked arbitrarily. assignment_mode=''least_loaded'' (decision, disclosed: NOT literal round-robin rotation, a deterministic least-active-workload pick, tie-broken by employee id) additionally auto-picks an eligible queue member on app.auto_route_ticket; ''manual'' routes the queue only. max_active_assignments_per_member is the workload cap (decision 9): hard on app.claim_ticket, override-able on app.assign_ticket only via an explicit, actor-authorized parameter.';

create index ticket_routing_rule_versions_tenant_status_idx on app.ticket_routing_rule_versions (tenant_id, status);
create index ticket_routing_rule_versions_rule_idx on app.ticket_routing_rule_versions (rule_id, status);
create index ticket_routing_rule_versions_match_idx on app.ticket_routing_rule_versions (tenant_id, channel, status) where status = 'published';

create trigger ticket_routing_rule_versions_touch before update on app.ticket_routing_rule_versions
  for each row execute function app.touch_ticket_row();

-- ===========================================================================
-- 3. app.ticket_assignment_events -- the claim/accept/decline/reassign/
--    transfer/auto-route ledger (decisions 1/8).
-- ===========================================================================

create table app.ticket_assignment_events (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  ticket_id uuid not null references app.tickets (id),
  event_type text not null,
  source text not null,
  rule_version_id uuid references app.ticket_routing_rule_versions (id),
  from_assignee_employee_id uuid references app.employees (master_record_id),
  to_assignee_employee_id uuid references app.employees (master_record_id),
  from_queue_id uuid references app.ticket_queues (id),
  to_queue_id uuid references app.ticket_queues (id),
  reason text,
  actor_auth_user_id uuid,
  actor_label text,
  occurred_at timestamptz not null default now(),
  constraint ticket_assignment_events_event_type_check check (event_type in (
    'auto_route', 'manual_assign', 'claim', 'accept', 'decline', 'reassign', 'unassign', 'transfer'
  )),
  constraint ticket_assignment_events_source_check check (source in ('rule_engine', 'manual', 'claim', 'self'))
);

comment on table app.ticket_assignment_events is
  'HRT-290 (decisions 1/8): the assignment-lifecycle event ledger -- claim/accept/decline/reassign/unassign/transfer/auto_route, with reason and source (rule_engine/manual/claim/self). Governed by the SAME RLS as app.ticket_events (decision 8) -- never app.audit_logs, whose readership is broader than this ledger''s real audience. Never a second source of truth for "who is assigned now" (decision 1) -- app.tickets.assignee_employee_id/assignee_support_auth_user_id remain the one current-owner columns; this table is history only.';

create index ticket_assignment_events_ticket_idx on app.ticket_assignment_events (ticket_id, occurred_at asc);
create index ticket_assignment_events_tenant_type_idx on app.ticket_assignment_events (tenant_id, event_type);

-- ===========================================================================
-- 4. Internal helpers (service_role only -- nested-called by the owner-
--    privileged functions below, mirrors app.resolve_effective_sla_policy_
--    version's own "no grant needed for nested calls" precedent exactly).
-- ===========================================================================

create function app._is_employee_ticket_eligible(p_tenant_id uuid, p_employee_id uuid)
returns boolean
language sql
stable
security definer
set search_path = app, pg_temp
as $$
  select exists (
    select 1 from app.employees e
    where e.master_record_id = p_employee_id
      and e.tenant_id = p_tenant_id
      and e.lifecycle_status = 'active'
  )
  and not exists (
    select 1 from app.leave_requests lr
    where lr.employee_id = p_employee_id
      and lr.tenant_id = p_tenant_id
      and lr.status = 'approved'
      and lr.validity_range @> current_date
  );
$$;

comment on function app._is_employee_ticket_eligible is
  'HRT-290 (decision 6): "effective employee status/availability", reusing ONLY existing canonical concepts -- app.employees.lifecycle_status=''active'' AND no currently-dated, status=''approved'' app.leave_requests row. No parallel "agent status" concept invented.';

grant execute on function app._is_employee_ticket_eligible(uuid, uuid) to service_role;

create function app._count_employee_active_ticket_assignments(p_tenant_id uuid, p_employee_id uuid, p_queue_id uuid)
returns integer
language sql
stable
security definer
set search_path = app, pg_temp
as $$
  select count(*)::integer
  from app.tickets t
  where t.tenant_id = p_tenant_id
    and t.queue_id = p_queue_id
    and t.assignee_employee_id = p_employee_id
    and t.status not in ('resolved', 'closed', 'cancelled');
$$;

comment on function app._count_employee_active_ticket_assignments is
  'HRT-290 (decision 1/9): the workload aggregation -- a live COUNT(*) against app.tickets itself, never a second, separately-maintained counter that could drift. Powers both the workload cap (claim/assign) and app.get_ticket_queue_workload''s own read-only snapshot.';

grant execute on function app._count_employee_active_ticket_assignments(uuid, uuid, uuid) to service_role;

create function app._resolve_ticket_routing_rule_for_ticket(p_ticket app.tickets)
returns app.ticket_routing_rule_versions
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_rec record;
  v_best_id uuid;
  v_tie_count integer := 0;
  v_result app.ticket_routing_rule_versions;
begin
  if p_ticket.channel not in ('internal', 'customer') then
    return null;
  end if;

  for v_rec in
    select rv.id,
      rank() over (
        order by
          (rv.category_id is not null) desc,
          (rv.priority is not null) desc,
          rv.precedence_rank desc
      ) as tie_rank
    from app.ticket_routing_rule_versions rv
    join app.ticket_routing_rules r on r.id = rv.rule_id
    where r.tenant_id = p_ticket.tenant_id
      and r.status = 'active'
      and rv.status = 'published'
      and rv.channel = p_ticket.channel
      and (rv.category_id is null or rv.category_id = p_ticket.category_id)
      and (rv.priority is null or rv.priority = p_ticket.priority)
    order by tie_rank asc
  loop
    exit when v_rec.tie_rank > 1;
    v_tie_count := v_tie_count + 1;
    v_best_id := v_rec.id;
  end loop;

  if v_tie_count = 0 then
    return null;
  elsif v_tie_count > 1 then
    raise exception 'ticket_routing_rule_ambiguous_match: % published routing rule versions tie for tenant % channel % -- resolve the tie with a distinct precedence_rank or narrower scope', v_tie_count, p_ticket.tenant_id, p_ticket.channel
      using errcode = 'check_violation';
  end if;

  select rv.* into v_result from app.ticket_routing_rule_versions rv where rv.id = v_best_id;
  return v_result;
end;
$$;

comment on function app._resolve_ticket_routing_rule_for_ticket is
  'HRT-290 (decision 4): the ONE deterministic routing-rule-match engine, mirroring app.resolve_effective_sla_policy_version (HRT-289) verbatim in shape. Ranks by specificity (category_id set > priority set > explicit precedence_rank tie-break); a genuine tie raises ticket_routing_rule_ambiguous_match rather than picking arbitrarily. Returns null (no hard failure) when no published rule matches -- callers treat this as "no rule configured for this scope", never a hard error, matching app.assign_ticket''s own pre-existing manual-designation path remaining fully usable with zero rules configured.';

grant execute on function app._resolve_ticket_routing_rule_for_ticket(app.tickets) to service_role;

create function app._apply_ticket_assignment(
  p_ticket app.tickets, p_expected_version integer, p_new_assignee_employee_id uuid,
  p_event_type text, p_source text, p_rule_version_id uuid, p_reason text,
  p_actor_auth_user_id uuid, p_actor_label text
)
returns app.tickets
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_updated app.tickets;
begin
  update app.tickets
  set assignee_employee_id = p_new_assignee_employee_id,
      assigned_by = p_actor_label,
      assigned_at = now(),
      assignment_confirmed_at = null,
      assignment_confirmed_by = null
  where id = p_ticket.id and record_version = p_expected_version
  returning * into v_updated;
  if not found then
    raise exception 'stale_version: concurrent update detected for ticket %', p_ticket.id using errcode = 'serialization_failure';
  end if;

  insert into app.ticket_events (tenant_id, ticket_id, event_type, from_value, to_value, reason, actor_auth_user_id, actor_label)
  values (p_ticket.tenant_id, p_ticket.id, 'assignment', p_ticket.assignee_employee_id::text, p_new_assignee_employee_id::text, p_reason, p_actor_auth_user_id, p_actor_label);

  insert into app.ticket_assignment_events (
    tenant_id, ticket_id, event_type, source, rule_version_id,
    from_assignee_employee_id, to_assignee_employee_id, reason, actor_auth_user_id, actor_label
  ) values (
    p_ticket.tenant_id, p_ticket.id, p_event_type, p_source, p_rule_version_id,
    p_ticket.assignee_employee_id, p_new_assignee_employee_id, p_reason, p_actor_auth_user_id, p_actor_label
  );

  return v_updated;
end;
$$;

comment on function app._apply_ticket_assignment is
  'HRT-290 (decision 1): the ONE shared "change who is assigned" engine -- app.claim_ticket/app.assign_ticket/app.auto_route_ticket/app.decline_ticket_assignment all call this, never re-implementing the UPDATE+ledger-insert shape independently. Always writes BOTH app.ticket_events (event_type=''assignment'', the existing, already-VERIFIED participant-visible history) AND app.ticket_assignment_events (this migration''s own richer ledger) in the same transaction -- one real state change, one complete, consistent event trail (section 24: "one current owner state has a complete event history"). Callers perform their own capture_audit_event with their own action name (claim_ticket/assign_ticket/...) -- kept out of this shared helper so each caller''s audit action name stays accurate.';

grant execute on function app._apply_ticket_assignment(app.tickets, integer, uuid, text, text, uuid, text, uuid, text) to service_role;

-- ===========================================================================
-- 5. Routing-rule authoring/publish RPCs (TKT:Edit) -- mirrors HRT-289's own
--    sla policy authoring shape exactly (decision 4).
-- ===========================================================================

create function app.create_ticket_routing_rule(p_tenant_id uuid, p_code text, p_name text, p_actor_auth_user_id uuid, p_actor_label text)
returns app.ticket_routing_rules
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_existing app.ticket_routing_rules;
  v_row app.ticket_routing_rules;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  if not app.check_ticket_authority('Edit', p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks TKT:Edit for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if p_code is null or length(trim(p_code)) = 0 then
    raise exception 'code_required: a non-empty code is required' using errcode = 'check_violation';
  end if;
  if p_name is null or length(trim(p_name)) = 0 then
    raise exception 'name_required: a non-empty name is required' using errcode = 'check_violation';
  end if;

  select * into v_existing from app.ticket_routing_rules where tenant_id = p_tenant_id and code = p_code;
  if found then
    return v_existing;
  end if;

  begin
    insert into app.ticket_routing_rules (tenant_id, code, name, created_by)
    values (p_tenant_id, p_code, p_name, p_actor_label)
    returning * into v_row;
  exception
    when unique_violation then
      select * into v_row from app.ticket_routing_rules where tenant_id = p_tenant_id and code = p_code;
      if not found then
        raise;
      end if;
  end;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'create_ticket_routing_rule',
    'app.ticket_routing_rules', v_row.id, 'success', null, null, jsonb_build_object('code', v_row.code)
  );

  return v_row;
end;
$$;

create function app.create_ticket_routing_rule_version(
  p_rule_id uuid, p_channel text, p_category_id uuid, p_priority text, p_target_queue_id uuid,
  p_assignment_mode text, p_max_active_assignments_per_member integer, p_precedence_rank integer,
  p_actor_auth_user_id uuid, p_actor_label text
)
returns app.ticket_routing_rule_versions
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_rule app.ticket_routing_rules;
  v_next_version integer;
  v_row app.ticket_routing_rule_versions;
  v_mode text := coalesce(p_assignment_mode, 'manual');
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  select * into v_rule from app.ticket_routing_rules where id = p_rule_id for update;
  if not found then
    raise exception 'ticket_routing_rule_not_found: %', p_rule_id using errcode = 'no_data_found';
  end if;
  if not app.check_ticket_authority('Edit', v_rule.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks TKT:Edit for tenant %', p_actor_auth_user_id, v_rule.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if p_channel is null or not (p_channel = any (array['internal', 'customer'])) then
    raise exception 'invalid_channel: % is not one of internal/customer -- helpdesk routing has no eligibility model (decision 2), see app.assign_helpdesk_ticket', p_channel using errcode = 'check_violation';
  end if;
  if p_priority is not null and not (p_priority = any (array['low', 'normal', 'high', 'urgent'])) then
    raise exception 'invalid_priority: % is not one of low/normal/high/urgent', p_priority using errcode = 'check_violation';
  end if;
  if not (v_mode = any (array['manual', 'least_loaded'])) then
    raise exception 'invalid_assignment_mode: % is not one of manual/least_loaded', v_mode using errcode = 'check_violation';
  end if;
  if p_max_active_assignments_per_member is not null and p_max_active_assignments_per_member <= 0 then
    raise exception 'invalid_workload_limit: max_active_assignments_per_member must be positive when set' using errcode = 'check_violation';
  end if;
  if p_category_id is not null and not exists (select 1 from app.ticket_categories c where c.id = p_category_id and c.tenant_id = v_rule.tenant_id) then
    raise exception 'ticket_category_not_found: %', p_category_id using errcode = 'no_data_found';
  end if;
  if not exists (select 1 from app.ticket_queues q where q.id = p_target_queue_id and q.tenant_id = v_rule.tenant_id and q.status = 'active') then
    raise exception 'ticket_queue_not_found: % is not a valid active queue for tenant %', p_target_queue_id, v_rule.tenant_id using errcode = 'no_data_found';
  end if;

  select coalesce(max(version_number), 0) + 1 into v_next_version from app.ticket_routing_rule_versions where rule_id = p_rule_id;

  insert into app.ticket_routing_rule_versions (
    rule_id, tenant_id, version_number, channel, category_id, priority, target_queue_id,
    assignment_mode, max_active_assignments_per_member, precedence_rank, created_by
  ) values (
    p_rule_id, v_rule.tenant_id, v_next_version, p_channel, p_category_id, p_priority, p_target_queue_id,
    v_mode, p_max_active_assignments_per_member, coalesce(p_precedence_rank, 0), p_actor_label
  )
  returning * into v_row;

  perform app.capture_audit_event(
    v_rule.tenant_id, p_actor_auth_user_id, p_actor_label, 'create_ticket_routing_rule_version',
    'app.ticket_routing_rule_versions', v_row.id, 'success', null, null,
    jsonb_build_object(
      'rule_id', p_rule_id, 'version_number', v_next_version, 'channel', p_channel, 'category_id', p_category_id,
      'priority', p_priority, 'target_queue_id', p_target_queue_id, 'assignment_mode', v_mode,
      'max_active_assignments_per_member', p_max_active_assignments_per_member, 'precedence_rank', v_row.precedence_rank
    )
  );

  return v_row;
end;
$$;

create function app.publish_ticket_routing_rule_version(p_version_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text)
returns app.ticket_routing_rule_versions
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_version app.ticket_routing_rule_versions;
  v_rule app.ticket_routing_rules;
  v_updated app.ticket_routing_rule_versions;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  select * into v_version from app.ticket_routing_rule_versions where id = p_version_id for update;
  if not found then
    raise exception 'ticket_routing_rule_version_not_found: %', p_version_id using errcode = 'no_data_found';
  end if;
  select * into v_rule from app.ticket_routing_rules where id = v_version.rule_id for update;

  if not app.check_ticket_authority('Edit', v_version.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks TKT:Edit for tenant %', p_actor_auth_user_id, v_version.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if v_version.record_version <> p_expected_version then
    raise exception 'stale_version: expected version % but current version is %', p_expected_version, v_version.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_version.status <> 'draft' then
    raise exception 'invalid_state: routing rule version % is % not draft', p_version_id, v_version.status using errcode = 'check_violation';
  end if;

  -- Supersede this SAME rule's own prior published version under the parent
  -- row lock already taken above -- HRT-289's own self-found fix
  -- (app.publish_sla_policy_version: "a revised version tied against its own
  -- predecessor at resolution time"), applied here from the start rather
  -- than rediscovered (decision 4). Deliberately does NOT supersede a
  -- DIFFERENT rule's version -- two different rules may legitimately publish
  -- overlapping-scope versions; app._resolve_ticket_routing_rule_for_ticket
  -- raises ticket_routing_rule_ambiguous_match at MATCH time instead of
  -- suppressing the ambiguity here.
  update app.ticket_routing_rule_versions
  set status = 'superseded'
  where rule_id = v_version.rule_id and status = 'published';

  update app.ticket_routing_rule_versions
  set status = 'published', published_at = now(), published_by = p_actor_label
  where id = p_version_id and record_version = p_expected_version
  returning * into v_updated;
  if not found then
    raise exception 'stale_version: concurrent update detected for routing rule version %', p_version_id using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_version.tenant_id, p_actor_auth_user_id, p_actor_label, 'publish_ticket_routing_rule_version',
    'app.ticket_routing_rule_versions', p_version_id, 'success', null, null,
    jsonb_build_object('rule_id', v_version.rule_id, 'version_number', v_updated.version_number)
  );

  return v_updated;
end;
$$;

-- ===========================================================================
-- 6. app.preview_ticket_routing -- routing preview (section 14), TKT:Edit-
--    gated administrative "what would happen" simulation. Never requires a
--    real ticket to exist.
-- ===========================================================================

create function app.preview_ticket_routing(p_tenant_id uuid, p_channel text, p_category_id uuid, p_priority text, p_actor_auth_user_id uuid)
returns table (
  matched boolean, rule_id uuid, rule_version_id uuid, version_number integer,
  target_queue_id uuid, target_queue_code text, assignment_mode text, max_active_assignments_per_member integer
)
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_rule app.ticket_routing_rule_versions;
  v_fake_ticket app.tickets;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  if not app.check_ticket_authority('Edit', p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks TKT:Edit for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if p_channel is null or not (p_channel = any (array['internal', 'customer'])) then
    raise exception 'invalid_channel: % is not one of internal/customer', p_channel using errcode = 'check_violation';
  end if;

  v_fake_ticket.tenant_id := p_tenant_id;
  v_fake_ticket.channel := p_channel;
  v_fake_ticket.category_id := p_category_id;
  v_fake_ticket.priority := coalesce(p_priority, 'normal');

  v_rule := app._resolve_ticket_routing_rule_for_ticket(v_fake_ticket);

  if v_rule.id is null then
    return query select false, null::uuid, null::uuid, null::integer, null::uuid, null::text, null::text, null::integer;
    return;
  end if;

  return query
  select true, r.id, v_rule.id, v_rule.version_number, v_rule.target_queue_id, q.code, v_rule.assignment_mode, v_rule.max_active_assignments_per_member
  from app.ticket_routing_rules r
  join app.ticket_queues q on q.id = v_rule.target_queue_id
  where r.id = v_rule.rule_id;
end;
$$;

comment on function app.preview_ticket_routing is
  'HRT-290 (section 14, "routing preview"): a real, TKT:Edit-gated simulation against a SYNTHETIC ticket row (channel/category/priority only, never a real app.tickets insert) -- lets an admin verify a routing-rule configuration''s own explainable outcome before it ever affects a real ticket. matched=false with all other columns null means "no published rule matches this scope" -- never a hard error, since app.assign_ticket''s manual path remains fully usable with zero rules configured.';

-- ===========================================================================
-- 7. app.claim_ticket -- self-service atomic claim (decisions 3/5/6/9).
-- ===========================================================================

create function app.claim_ticket(p_ticket_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text)
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
  'HRT-290 (decisions 3/5/6/9): self-service atomic claim -- no TKT:Assign required, plain ACTIVE queue membership is sufficient (mirrors HRT-286 decision 5''s own "ordinary day-to-day ticket work" bar). Blocked by: wrong channel (helpdesk), stale version (a real race loser), invalid ticket status, ineligible employee (inactive/on-leave), already assigned to someone else, or a configured workload cap with no override (decision 9 -- unlike app.assign_ticket, claim never overrides its own cap).';

-- ===========================================================================
-- 8. app.accept_ticket_assignment / app.decline_ticket_assignment (decisions
--    3/9's own note: accept has a real, tested state effect).
-- ===========================================================================

create function app.accept_ticket_assignment(p_ticket_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text)
returns app.tickets
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_ticket app.tickets;
  v_self app.employees;
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
    raise exception 'channel_not_supported: ticket % is a helpdesk case', p_ticket_id using errcode = 'check_violation';
  end if;

  v_self := app.get_self_employee(v_ticket.tenant_id, p_actor_auth_user_id);
  if v_self.master_record_id is null or v_ticket.assignee_employee_id is distinct from v_self.master_record_id then
    raise exception 'insufficient_authority: identity % is not the current assignee of ticket %', p_actor_auth_user_id, p_ticket_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_ticket.record_version <> p_expected_version then
    raise exception 'stale_version: expected version % but current version is %', p_expected_version, v_ticket.record_version
      using errcode = 'serialization_failure';
  end if;

  if v_ticket.assignment_confirmed_at is not null then
    return v_ticket;
  end if;

  update app.tickets set assignment_confirmed_at = now(), assignment_confirmed_by = p_actor_label
  where id = p_ticket_id and record_version = p_expected_version
  returning * into v_updated;
  if not found then
    raise exception 'stale_version: concurrent update detected for ticket %', p_ticket_id using errcode = 'serialization_failure';
  end if;

  insert into app.ticket_assignment_events (tenant_id, ticket_id, event_type, source, from_assignee_employee_id, to_assignee_employee_id, actor_auth_user_id, actor_label)
  values (v_ticket.tenant_id, p_ticket_id, 'accept', 'self', v_ticket.assignee_employee_id, v_ticket.assignee_employee_id, p_actor_auth_user_id, p_actor_label);

  perform app.capture_audit_event(
    v_ticket.tenant_id, p_actor_auth_user_id, p_actor_label, 'accept_ticket_assignment',
    'app.tickets', p_ticket_id, 'success', null, app.ticket_audit_projection(v_ticket), app.ticket_audit_projection(v_updated)
  );

  return v_updated;
end;
$$;

create function app.decline_ticket_assignment(p_ticket_id uuid, p_expected_version integer, p_reason text, p_actor_auth_user_id uuid, p_actor_label text)
returns app.tickets
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_ticket app.tickets;
  v_self app.employees;
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
    raise exception 'channel_not_supported: ticket % is a helpdesk case', p_ticket_id using errcode = 'check_violation';
  end if;

  v_self := app.get_self_employee(v_ticket.tenant_id, p_actor_auth_user_id);
  if v_self.master_record_id is null or v_ticket.assignee_employee_id is distinct from v_self.master_record_id then
    raise exception 'insufficient_authority: identity % is not the current assignee of ticket %', p_actor_auth_user_id, p_ticket_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_ticket.record_version <> p_expected_version then
    raise exception 'stale_version: expected version % but current version is %', p_expected_version, v_ticket.record_version
      using errcode = 'serialization_failure';
  end if;
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'reason_required: a reason is required to decline a ticket assignment' using errcode = 'check_violation';
  end if;

  v_updated := app._apply_ticket_assignment(v_ticket, p_expected_version, null, 'decline', 'self', null, p_reason, p_actor_auth_user_id, p_actor_label);

  perform app.capture_audit_event(
    v_ticket.tenant_id, p_actor_auth_user_id, p_actor_label, 'decline_ticket_assignment',
    'app.tickets', p_ticket_id, 'success', null, app.ticket_audit_projection(v_ticket), app.ticket_audit_projection(v_updated)
  );

  return v_updated;
end;
$$;

comment on function app.decline_ticket_assignment is
  'HRT-290: the current assignee ONLY (never a manager on their behalf -- that is app.assign_ticket to null/someone else) declines, returning the ticket to its queue backlog unassigned (mirrors app.transfer_ticket_queue''s own "clears assignee" shape). A reason is mandatory, exactly like app.transfer_ticket_queue.';

-- ===========================================================================
-- 9. app.assign_ticket -- widened (decisions 9/10): explicit drop + create
--    (new trailing DEFAULTed params change the type signature -- a bare
--    create or replace would create a stale second overload, not replace).
--    Business logic and check ORDER for the original 5 parameters are
--    otherwise BYTE-FOR-BYTE unchanged from 20260731100000's own version.
-- ===========================================================================

drop function if exists app.assign_ticket(uuid, integer, uuid, uuid, text);

create function app.assign_ticket(
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
  'HRT-286/290 (decision 7 of 20260731060000; decisions 9/10 of this migration): manual designation, TKT:Assign-gated. Signature widened with two new trailing DEFAULTed parameters (p_reason, p_override_workload_limit) via explicit drop+create (decision 10) -- every pre-existing 5-argument caller is unaffected. Validates the target is a real, ACTIVE, ELIGIBLE (decision 6) member of the ticket''s own queue, and (unless overridden) within any configured workload cap (decision 9). Event type (manual_assign/reassign/unassign) is computed from the real before/after state and logged to BOTH app.ticket_events and the new app.ticket_assignment_events ledger via app._apply_ticket_assignment. Never changes app.tickets.status as a side effect (HRT-286 decision 6, unchanged).';

grant execute on function app.assign_ticket(uuid, integer, uuid, uuid, text, text, boolean) to authenticated, service_role;

-- ===========================================================================
-- 10. app.transfer_ticket_queue -- SAME signature, body widened to also log
--     the new ledger (decision 1). A genuine create or replace; grants
--     preserved automatically.
-- ===========================================================================

create or replace function app.transfer_ticket_queue(p_ticket_id uuid, p_expected_version integer, p_new_queue_id uuid, p_reason text, p_actor_auth_user_id uuid, p_actor_label text)
returns app.tickets
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_ticket app.tickets;
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
    raise exception 'channel_not_supported: ticket % is a helpdesk case -- use app.transfer_helpdesk_support_queue instead', p_ticket_id using errcode = 'check_violation';
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
    raise exception 'invalid_transition: cannot transfer a % ticket', v_ticket.status using errcode = 'check_violation';
  end if;
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'reason_required: a reason is required to transfer a ticket to another queue' using errcode = 'check_violation';
  end if;
  if not exists (select 1 from app.ticket_queues where id = p_new_queue_id and tenant_id = v_ticket.tenant_id and status = 'active') then
    raise exception 'queue_not_available: % is not an active queue for this tenant', p_new_queue_id using errcode = 'no_data_found';
  end if;

  update app.tickets set queue_id = p_new_queue_id, assignee_employee_id = null, assigned_by = null, assigned_at = null, assignment_confirmed_at = null, assignment_confirmed_by = null
  where id = p_ticket_id and record_version = p_expected_version
  returning * into v_updated;
  if not found then
    raise exception 'stale_version: concurrent update detected for ticket %', p_ticket_id using errcode = 'serialization_failure';
  end if;

  insert into app.ticket_events (tenant_id, ticket_id, event_type, from_value, to_value, reason, actor_auth_user_id, actor_label)
  values (v_ticket.tenant_id, p_ticket_id, 'queue_transfer', v_ticket.queue_id::text, p_new_queue_id::text, p_reason, p_actor_auth_user_id, p_actor_label);

  insert into app.ticket_assignment_events (tenant_id, ticket_id, event_type, source, from_queue_id, to_queue_id, from_assignee_employee_id, to_assignee_employee_id, reason, actor_auth_user_id, actor_label)
  values (v_ticket.tenant_id, p_ticket_id, 'transfer', 'manual', v_ticket.queue_id, p_new_queue_id, v_ticket.assignee_employee_id, null, p_reason, p_actor_auth_user_id, p_actor_label);

  perform app.capture_audit_event(
    v_ticket.tenant_id, p_actor_auth_user_id, p_actor_label, 'transfer_ticket_queue',
    'app.tickets', p_ticket_id, 'success', null, app.ticket_audit_projection(v_ticket), app.ticket_audit_projection(v_updated)
  );

  return v_updated;
end;
$$;

comment on function app.transfer_ticket_queue is
  'HRT-286/290 (decision 7 of 20260731060000; decision 1 of this migration): SAME signature as always -- a genuine create or replace, grants preserved. Body widened only to ALSO log app.ticket_assignment_events (event_type=transfer) alongside the pre-existing app.ticket_events row, and to clear the new assignment_confirmed_at/by columns (a transfer already clears the assignee itself).';

-- ===========================================================================
-- 11. app.auto_route_ticket -- applies a published rule version to a real
--     ticket: queue selection, and (least_loaded mode) an eligible-candidate
--     auto-pick (decisions 4/6/9).
-- ===========================================================================

create function app.auto_route_ticket(p_ticket_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text)
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
  'HRT-290 (decisions 2/4/6/9): applies the ONE matched, published routing-rule version (app._resolve_ticket_routing_rule_for_ticket) to a REAL ticket -- moves it to the rule''s own target_queue_id if different (clearing any prior assignee, mirroring app.transfer_ticket_queue''s own shape), and, for assignment_mode=least_loaded, additionally auto-picks the eligible queue member with the fewest current active assignments in that queue (tie-broken by employee id -- deterministic, explainable, never random). Gated on app.is_ticket_staff, mirroring app.transfer_ticket_queue''s own bar. Raises ticket_routing_rule_not_matched (no hard failure of the ticket itself -- the caller decides whether to fall back to manual assignment) when no published rule matches this ticket''s scope.';

grant execute on function app.auto_route_ticket(uuid, integer, uuid, text) to authenticated, service_role;

-- ===========================================================================
-- 12. Read RPCs -- routing-rule admin listing, assignment candidates
--     (explainable eligibility), workload snapshot, assignment history.
-- ===========================================================================

create function app.list_ticket_routing_rules(p_tenant_id uuid, p_actor_auth_user_id uuid)
returns table (id uuid, code text, name text, status text, record_version integer)
language plpgsql
security definer
set search_path = app, pg_temp
stable
as $$
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  if not app.has_active_tenant_membership(p_tenant_id, p_actor_auth_user_id) or app.actor_holds_customer_user_layer(p_tenant_id, p_actor_auth_user_id) then
    return;
  end if;
  return query
  select r.id, r.code, r.name, r.status, r.record_version from app.ticket_routing_rules r where r.tenant_id = p_tenant_id order by r.code asc;
end;
$$;

create function app.list_ticket_routing_rule_versions(p_rule_id uuid, p_actor_auth_user_id uuid)
returns table (
  id uuid, version_number integer, status text, channel text, category_id uuid, priority text,
  target_queue_id uuid, assignment_mode text, max_active_assignments_per_member integer,
  precedence_rank integer, published_at timestamptz, record_version integer
)
language plpgsql
security definer
set search_path = app, pg_temp
stable
as $$
declare
  v_rule app.ticket_routing_rules;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  select r0.* into v_rule from app.ticket_routing_rules r0 where r0.id = p_rule_id;
  if not found or not app.has_active_tenant_membership(v_rule.tenant_id, p_actor_auth_user_id) or app.actor_holds_customer_user_layer(v_rule.tenant_id, p_actor_auth_user_id) then
    return;
  end if;
  return query
  select v.id, v.version_number, v.status, v.channel, v.category_id, v.priority, v.target_queue_id,
    v.assignment_mode, v.max_active_assignments_per_member, v.precedence_rank, v.published_at, v.record_version
  from app.ticket_routing_rule_versions v where v.rule_id = p_rule_id order by v.version_number desc;
end;
$$;

create function app.list_ticket_assignment_candidates(p_ticket_id uuid, p_actor_auth_user_id uuid)
returns table (
  employee_id uuid, employee_name text, is_eligible boolean,
  active_ticket_count integer, ineligible_reason text
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
  if not found or v_ticket.channel = 'helpdesk' then
    raise exception 'ticket_not_found: %', p_ticket_id using errcode = 'no_data_found';
  end if;
  if not app.can_access_ticket(p_ticket_id, p_actor_auth_user_id) or not app.is_ticket_staff(p_ticket_id, p_actor_auth_user_id) then
    raise exception 'ticket_not_found: %', p_ticket_id using errcode = 'no_data_found';
  end if;

  return query
  select
    m.employee_id,
    e.full_name,
    app._is_employee_ticket_eligible(v_ticket.tenant_id, m.employee_id),
    app._count_employee_active_ticket_assignments(v_ticket.tenant_id, m.employee_id, v_ticket.queue_id),
    case when not app._is_employee_ticket_eligible(v_ticket.tenant_id, m.employee_id) then 'not currently active/available' else null end
  from app.ticket_queue_members m
  join app.employees e on e.master_record_id = m.employee_id
  where m.queue_id = v_ticket.queue_id and m.status = 'active'
  order by 4 asc, e.full_name asc;
end;
$$;

comment on function app.list_ticket_assignment_candidates is
  'HRT-290 (section 15, "assignment drawer with explainable eligibility"): every ACTIVE queue member of this ticket''s own queue, with a live eligibility bit and reason and a live workload count -- powers the assignment UI''s own explainability, never a raw employee directory. Gated on is_ticket_staff (the same bar app.assign_ticket/app.transfer_ticket_queue already require to act) -- folds "ticket does not exist"/"caller is not staff"/"ticket is a helpdesk case" into the identical ticket_not_found response (anti-enumeration, C-05 discipline).';

create function app.get_ticket_queue_workload(p_queue_id uuid, p_actor_auth_user_id uuid)
returns table (employee_id uuid, employee_name text, active_ticket_count integer, is_eligible boolean)
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_queue app.ticket_queues;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  select * into v_queue from app.ticket_queues q0 where q0.id = p_queue_id;
  if not found then
    raise exception 'ticket_queue_not_found: %', p_queue_id using errcode = 'no_data_found';
  end if;
  if not (
    app.is_ticket_queue_member(p_queue_id, p_actor_auth_user_id)
    or app.check_ticket_authority('Edit', v_queue.tenant_id, p_actor_auth_user_id)
    or app.check_ticket_authority('Assign', v_queue.tenant_id, p_actor_auth_user_id)
  ) then
    raise exception 'insufficient_authority: identity % may not view workload for queue %', p_actor_auth_user_id, p_queue_id
      using errcode = 'insufficient_privilege';
  end if;

  return query
  select m.employee_id, e.full_name,
    app._count_employee_active_ticket_assignments(v_queue.tenant_id, m.employee_id, p_queue_id),
    app._is_employee_ticket_eligible(v_queue.tenant_id, m.employee_id)
  from app.ticket_queue_members m
  join app.employees e on e.master_record_id = m.employee_id
  where m.queue_id = p_queue_id and m.status = 'active'
  order by 3 asc, e.full_name asc;
end;
$$;

comment on function app.get_ticket_queue_workload is
  'HRT-290 (decision 1, section 13 "workload snapshot/reference... never a second source of truth"): a live, read-only aggregation over app.tickets/app.ticket_queue_members -- computed on every call, never cached or separately maintained. Viewable by any active member of the queue itself, or a TKT:Edit/TKT:Assign holder (queue agents see their own queue''s workload; managers assign within governed scope -- section 26).';

create function app.list_ticket_assignment_events(p_ticket_id uuid, p_actor_auth_user_id uuid)
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

-- ===========================================================================
-- 13. RLS (decision 8) -- new tables only; every prior migration's own
--     policies are untouched.
-- ===========================================================================

alter table app.ticket_routing_rules enable row level security;
alter table app.ticket_routing_rule_versions enable row level security;
alter table app.ticket_assignment_events enable row level security;

create policy ticket_routing_rules_select_scoped on app.ticket_routing_rules
  for select to authenticated
  using ((app.has_active_tenant_membership(tenant_id) and not app.actor_holds_customer_user_layer(tenant_id)) or app.is_supreme_admin());

create policy ticket_routing_rule_versions_select_scoped on app.ticket_routing_rule_versions
  for select to authenticated
  using ((app.has_active_tenant_membership(tenant_id) and not app.actor_holds_customer_user_layer(tenant_id)) or app.is_supreme_admin());

create policy ticket_assignment_events_select_scoped on app.ticket_assignment_events
  for select to authenticated
  using (
    (app.can_access_ticket(ticket_id) and not app.actor_holds_customer_user_layer(tenant_id) and app.ticket_channel_of(ticket_id) <> 'helpdesk')
    or app.is_supreme_admin()
  );

comment on policy ticket_assignment_events_select_scoped on app.ticket_assignment_events is
  'HRT-290 (decision 8): identical shape to app.ticket_events_select_scoped (HRT-286/287/288) -- can_access_ticket AND not customer_user-layer AND channel<>helpdesk. This ledger only ever carries internal/customer rows (decision 2), so the channel clause is defense-in-depth against a future accidental write, matching the established pattern rather than assuming it away.';

-- ===========================================================================
-- 14. Grants (decision 10) -- explicit, deliberate, never blanket.
-- ===========================================================================

-- ERR-2026-004: Postgres grants EXECUTE to PUBLIC by default on function
-- creation -- every prior HRT ticketing migration carries this exact
-- statement for its own new functions; repeated here for this migration's
-- own new functions (self-found live by ATW-032/ISS-2026-032's own
-- has_function_privilege('authenticated', ...) sweep in every prior
-- checkpoint that omitted it).
revoke execute on all functions in schema app from public;

grant select on app.ticket_routing_rules to authenticated;
grant select on app.ticket_routing_rules to service_role;
grant select on app.ticket_routing_rule_versions to authenticated;
grant select on app.ticket_routing_rule_versions to service_role;
grant select on app.ticket_assignment_events to authenticated;
grant select on app.ticket_assignment_events to service_role;

grant execute on function app.create_ticket_routing_rule(uuid, text, text, uuid, text) to authenticated, service_role;
grant execute on function app.create_ticket_routing_rule_version(uuid, text, uuid, text, uuid, text, integer, integer, uuid, text) to authenticated, service_role;
grant execute on function app.publish_ticket_routing_rule_version(uuid, integer, uuid, text) to authenticated, service_role;
grant execute on function app.preview_ticket_routing(uuid, text, uuid, text, uuid) to authenticated, service_role;

grant execute on function app.claim_ticket(uuid, integer, uuid, text) to authenticated, service_role;
grant execute on function app.accept_ticket_assignment(uuid, integer, uuid, text) to authenticated, service_role;
grant execute on function app.decline_ticket_assignment(uuid, integer, text, uuid, text) to authenticated, service_role;
grant execute on function app.auto_route_ticket(uuid, integer, uuid, text) to authenticated, service_role;

grant execute on function app.list_ticket_routing_rules(uuid, uuid) to authenticated, service_role;
grant execute on function app.list_ticket_routing_rule_versions(uuid, uuid) to authenticated, service_role;
grant execute on function app.list_ticket_assignment_candidates(uuid, uuid) to authenticated, service_role;
grant execute on function app.get_ticket_queue_workload(uuid, uuid) to authenticated, service_role;
grant execute on function app.list_ticket_assignment_events(uuid, uuid) to authenticated, service_role;
