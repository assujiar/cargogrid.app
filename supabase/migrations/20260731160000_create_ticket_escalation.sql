-- Phase 7 (HRIS and Ticketing) capability CG-S12-HRT-019 (Ticket Escalation,
-- Prompt 291). Builds on app.tickets/app.ticket_queues/app.ticket_categories
-- (HRT-286), app.ticket_sla_clocks/app.ticket_sla_clock_events (HRT-289),
-- app.ticket_assignment_events/app._apply_ticket_assignment/app._is_employee_
-- ticket_eligible (HRT-290), app.jobs (PLT-131/132) and app.notifications
-- (PLT-127) -- never a second ticket, job, or notification mechanism. Zero
-- lines of any prior migration (<= 20260731150000) are touched.
--
-- Design decisions, disclosed rather than left implicit:
--
-- 1. **Channel is bounded to internal/customer, exactly like HRT-290's own
--    precedent-setting decision 2 for routing/assignment.** Every new table
--    that carries a channel column restricts it to ('internal','customer');
--    every new RPC that operates against a real ticket explicitly rejects
--    channel='helpdesk' with channel_not_supported, mirroring claim_ticket/
--    assign_ticket/auto_route_ticket's own established guard verbatim. This
--    is a deliberate choice, not an oversight: building a genuinely separate
--    Supreme-Admin-only helpdesk escalation path (the alternative the task's
--    own instructions explicitly allow) would double the RPC surface, the
--    db-test surface, and the UI surface for a channel that already has no
--    non-Supreme-Admin staffing/eligibility model of any kind (HRT-288
--    decision 3, HRT-290 decision 2) -- a future prompt can add one the same
--    additive way HRT-288 added Supreme-Admin-only helpdesk staffing,
--    without touching this shape.
-- 2. **Target is queue or employee only -- no "role" target, no "team"
--    entity.** HRT-290's own Tier C review (ISS-2026-089) already disclosed
--    that no team/team-membership entity exists anywhere in this repository
--    and that queue-based grouping is the correct, working team-analog every
--    other capability in this phase uses -- reused here identically. A
--    "role" target (broadcast-notify every current holder of a role) is a
--    genuinely different fan-out shape from every other target-resolution
--    concept in this codebase (which always resolves to exactly one
--    accountable employee or one queue) and is deliberately NOT built --
--    disclosed, not silently dropped (taxonomy C-23).
-- 3. **Escalation may notify and/or reassign, exactly as configured per
--    level -- "create an approval/task" is deliberately NOT built.** This
--    repository's approval engine (PLT-115-adjacent) and every ticket
--    workflow concept model a fundamentally different object shape
--    (multi-step decision records against a specific, typed target entity);
--    wiring ticket escalation into it would be a real, separate integration
--    a future prompt should own deliberately, not a corollary of this one.
--    Disclosed (taxonomy C-23), not silently dropped -- action_notify/
--    action_reassign are the two real, independently-configured, tested
--    actions this checkpoint ships.
-- 4. **Reassignment reuses app._apply_ticket_assignment (HRT-290) directly
--    -- never a second per-ticket assignment mechanism.** When a level's
--    action_reassign fires against an eligible employee target,
--    app._apply_ticket_escalation calls the SAME shared engine
--    claim_ticket/assign_ticket/auto_route_ticket already call, so the
--    resulting reassignment is logged to app.ticket_assignment_events (the
--    existing, already-VERIFIED ledger) exactly like any other reassignment,
--    with no parallel "who is assigned" state anywhere.
-- 5. **A missing/ineligible/revoked target is a disclosed, ledger-recorded
--    outcome, never a silent no-op or a hard failure** -- mirrors
--    auto_route_ticket's own "no eligible candidate" precedent (HRT-290)
--    exactly. app._ticket_escalation_target_eligible gates every target at
--    both authoring time (existence/tenant-scope) and trigger time
--    (liveness/eligibility); a trigger-time miss still records the real
--    'triggered' event (the condition genuinely fired) but records
--    'reassign_skipped'/'notification_failed' for the sub-action that could
--    not complete, with a real, human-readable reason.
-- 6. **Idempotency is the natural key (ticket, policy/version, trigger,
--    level) PLUS the ticket's own reopen_count at trigger time.** A
--    reopened-and-rebreached ticket is honestly a NEW escalation cycle
--    (business meaning: the prior escalation was resolved when the ticket
--    closed/resolved -- HRT-286's own reopen_count column, reused verbatim,
--    never a parallel "cycle" column). The real guarantee is a real partial
--    unique index on app.ticket_escalation_events, backed by a real
--    `exception when unique_violation` handler in
--    app._apply_ticket_escalation (C-01/C-02 mandate) -- not merely a
--    pre-check SELECT.
-- 7. **Resolution/closure/cancellation resolves an open escalation on the
--    NEXT evaluation pass, an honest, disclosed latency -- never a hidden
--    hook into app.transition_ticket_status (untouched, decision-consistent
--    with HRT-289's own decision 1: every cross-cutting ticket concern is an
--    explicit, separate, periodically-evaluated consumer, never a trigger).**
--    app.resolve_ticket_escalation additionally gives staff an immediate,
--    explicit manual de-escalation/resolve action (section 14's own named
--    "resolve/de-escalate" API operation) -- real-time, not batch-bound.
-- 8. **Cooldown is a real, load-bearing per-level pacing gate, not a decorative
--    column.** Because a level's own 'triggered' event can only ever fire
--    once per (ticket, policy_version, trigger, level, reopen cycle) by
--    construction (decision 6), a naive "block a repeat of the SAME level"
--    reading of cooldown would be permanently unreachable (taxonomy C-20).
--    cooldown_minutes instead gates how soon the NEXT (higher) level may
--    fire after the CURRENT level's own last trigger -- a genuine
--    backpressure control against a single incident racing through every
--    configured level in one evaluation cycle, tested directly.
-- 9. **First real consumer of PLT-127's notification engine (its own
--    migration header disclosed zero domain consumers existed yet).**
--    Bootstrapped via a direct INSERT into app.notification_types/
--    app.config_types/app.config_objects/app.config_versions/
--    app.config_items -- migration-apply context has no live actor session,
--    so app.register_notification_type/app.create_config_draft/app.publish_
--    config_version (all Supreme-Admin- or scope-authority-gated) cannot be
--    called here, mirroring HRT-286's own established 'ticket_attachment'
--    document-type direct-INSERT bootstrap exactly. channels=['in_app']
--    ONLY (no live email provider exists anywhere in this repository,
--    PLT-127's own disclosed boundary) -- the seeded template content was
--    manually verified against app.validate_notification_template's own
--    checks (real locale, balanced token braces, non-empty subject/body)
--    even though that function is not itself invoked at migration-apply
--    time. Notification context carries ONLY ticket_number/escalation_level/
--    trigger_type -- deliberately NEVER the ticket's own subject/reason free
--    text, both to satisfy this prompt's own "minimized fields" security
--    requirement and to guarantee app.render_notification_template's own
--    angle-bracket/link-scheme safety checks can never be tripped by
--    user-authored content.
-- 10. **Batch-triggered escalation events attribute actor_auth_user_id/
--    actor_label to the REAL identity that invoked the evaluation batch --
--    never a fabricated "system" auth identity.** app.queue_notification's
--    own authority gate (app.check_notification_trigger_authority) requires
--    a genuine, currently-tenant-active (or Supreme Admin) actor; no
--    anonymous system-actor concept exists anywhere in this schema.
--    app.run_ticket_escalation_evaluation_batch's own TKT:Edit-holding
--    caller is threaded through app._evaluate_ticket_escalation into every
--    ledger row and notification call it produces -- an accurate, audited
--    attribution (the accountable party who caused this evaluation run),
--    mirroring app.run_ticket_sla_evaluation_batch's own actor threading.
-- 11. **Suppression is authority-gated (TKT:Assign, a materially higher bar
--    than plain is_ticket_staff), requires a real reason and a real future
--    expiry, and NEVER hides the underlying ledger** (business rule,
--    literally) -- app.ticket_escalation_events still records every
--    'triggered'/'suppressed'/'suppression_ended' row regardless of
--    suppression state; suppression only gates whether app._evaluate_ticket_
--    escalation may advance to a NEW level, never what compliance reporting
--    can see. A stale, unrevoked, already-expired suppression is
--    auto-revoked (revoked_reason='expired') the next time it is checked --
--    a real, disclosed state transition, never silently ignored.
-- 12. **Customer-visible status is a single boolean, structurally separate
--    from every internal field** (business rule, security impact section
--    16). app.get_ticket_escalation_status_for_requester returns is_escalated
--    ONLY -- no level, no target, no trigger, no acknowledgement detail, no
--    hierarchy -- a DIFFERENT RPC from the staff-facing app.get_ticket_
--    escalation (mirrors app.get_ticket_sla_status_for_requester's own
--    established split, HRT-289, exactly).
-- 13. **A dedicated breach/stuck queue view (app.list_ticket_breach_queue)
--    is built rather than widening app.list_tickets/app.list_my_tickets.**
--    Those two RPCs are already-VERIFIED, applied migrations this task may
--    never edit in place; widening their RETURNS TABLE shape would require a
--    genuine drop+create (HRT-290's own assign_ticket precedent for a
--    signature change) rippling through TicketListRow/MyTicketListRow, every
--    existing caller, and every existing test for a return-shape change no
--    other capability needs. A minimal, dedicated, staff-scoped (is_ticket_
--    staff per row, mirrors app.list_tickets' own can_access_ticket-per-row
--    shape) cursor-paginated view is built instead -- disclosed, not an
--    oversight (taxonomy C-23).
-- 14. **Locking discipline (C-04):** every RPC that mutates escalation state
--    for a given ticket takes `select ... from app.tickets ... for update`
--    FIRST, consistently, before locking any child row (app.ticket_
--    escalations / app.ticket_escalation_suppressions) -- including
--    app.revoke_ticket_escalation_suppression, which takes p_ticket_id as an
--    explicit parameter (rather than deriving it from the suppression row)
--    specifically so it can preserve this same ticket-first lock order and
--    never risk a reversed-order deadlock against app.suppress_ticket_
--    escalation (C-21 discipline, applied from the start).
-- 15. **C-24 discipline.** Every free-text column (escalation reason,
--    suppression reason, decline-style notes) lives ONLY on app.ticket_
--    escalation_events / app.ticket_escalation_suppressions, both governed by
--    the exact same RLS as the ticket itself (app.can_access_ticket) --
--    mirroring app.ticket_events/app.ticket_assignment_events exactly, never
--    app.audit_logs. app.ticket_escalation_audit_projection is an explicit
--    structural-fields-only allowlist; every capture_audit_event call site in
--    this migration passes it (or an explicit jsonb_build_object allowlist),
--    never to_jsonb(row) and never a raw p_reason.

-- ===========================================================================
-- 0. Widen app.jobs.job_type (mirrors HRT-289 exactly -- the seventh HRIS/
--    Ticketing-domain adopter of PLT-132's generic job_type list, kept
--    set-equal with app.generic_job_types() by the standing ATW-031
--    drift-gate assertion).
-- ===========================================================================

-- Self-found defect, fixed before commit (own Tier B walk, not review):
-- app.generic_job_types()/jobs_job_type_check are FULL replacements, not
-- additive -- an earlier draft of this section copied the SLA migration's
-- own (120000) list verbatim and, in doing so, silently DROPPED
-- 'kb_article_expiry' (added one migration later, 130000, after 120000 was
-- already written) from both the CHECK constraint and the function, which
-- would have made every already-published KB expiry job/batch call start
-- failing (job_invalid_type) the moment this migration applied -- caught
-- live by a full `pnpm run db:test` pass (scripts/db-tests/ticketing-
-- knowledge-base.sql''s own step 3 failed with exactly that error). Fixed by
-- carrying forward the FULL current list (120000 + 130000's own additions)
-- plus this migration's own new type -- never re-deriving from a single
-- prior migration in isolation.
alter table app.jobs drop constraint jobs_job_type_check;
alter table app.jobs add constraint jobs_job_type_check check (
  job_type in (
    'import', 'export', 'report_generation', 'notification_batch', 'webhook_retry', 'document_generation',
    'dashboard_refresh', 'loyalty_expiration', 'recurring_billing', 'integration_sync',
    'route_load_planning', 'print_label', 'roster_generation', 'leave_accrual', 'leave_carry_forward_expiry',
    'payroll_calculation', 'training_certificate_expiry', 'training_certificate_expiry_reminder',
    'ticket_sla_evaluation', 'kb_article_expiry', 'ticket_escalation_evaluation'
  )
);

comment on constraint jobs_job_type_check on app.jobs is
  'HRT-291 (decision, mirrors HRT-289): widened to add ''ticket_escalation_evaluation''. Kept set-equal with app.generic_job_types() by the standing ATW-031 drift-gate assertion (scripts/db-tests/background-job.sql).';

create or replace function app.generic_job_types()
returns text[]
language sql
immutable
set search_path = app, pg_temp
as $$
  select array[
    'report_generation', 'notification_batch', 'webhook_retry', 'document_generation',
    'dashboard_refresh', 'loyalty_expiration', 'recurring_billing', 'integration_sync',
    'route_load_planning', 'print_label', 'roster_generation', 'leave_accrual', 'leave_carry_forward_expiry',
    'payroll_calculation', 'training_certificate_expiry', 'training_certificate_expiry_reminder',
    'ticket_sla_evaluation', 'kb_article_expiry', 'ticket_escalation_evaluation'
  ]::text[];
$$;

comment on function app.generic_job_types is
  'ATW-031 (ISS-2026-012), widened by HRT-291 to add ''ticket_escalation_evaluation''. Unchanged callers: app.enqueue_job and app.dispatch_event_as_job.';

-- ===========================================================================
-- 0b. Notification type bootstrap (decision 9) -- direct INSERT, mirrors
--     HRT-286's own 'ticket_attachment' document-type bootstrap exactly.
-- ===========================================================================

insert into app.notification_types (code, name, owner_primitive_code, registered_by)
values ('ticket_escalated', 'Ticket Escalated', 'TKT', 'system')
on conflict (code) do nothing;

insert into app.config_types (code, name, owner_primitive_code, registered_by)
values ('notification:ticket_escalated', 'Ticket Escalated Notification', 'TKT', 'system')
on conflict (code) do nothing;

do $$
declare
  v_object_id uuid;
  v_version_id uuid;
begin
  select id into v_object_id from app.config_objects
  where config_type_code = 'notification:ticket_escalated' and tenant_id is null and scope_level = 'global' and scope_id is null;

  if v_object_id is null then
    insert into app.config_objects (config_type_code, tenant_id, scope_level, scope_id, created_by)
    values ('notification:ticket_escalated', null, 'global', null, 'system')
    returning id into v_object_id;
  end if;

  select id into v_version_id from app.config_versions where config_object_id = v_object_id and status = 'published';

  if v_version_id is null then
    insert into app.config_versions (config_object_id, version_number, status, effective_from, created_by, published_by, published_at)
    values (v_object_id, 1, 'published', now(), 'system', 'system', now())
    returning id into v_version_id;

    insert into app.config_items (config_version_id, key, value) values
      (v_version_id, 'channels', '["in_app"]'::jsonb),
      (v_version_id, 'default_locale', '"en"'::jsonb),
      (v_version_id, 'templates', '{"en": {"subject": "Ticket {{ticket_number}} escalated (level {{escalation_level}})", "body": "Ticket {{ticket_number}} has been escalated to level {{escalation_level}} ({{trigger_type}}). Open your CargoGrid tickets workspace to review."}}'::jsonb);
  end if;

  raise notice 'ticket_escalated notification template ready: config_object=%, published_version=%', v_object_id, v_version_id;
end;
$$;

-- ===========================================================================
-- 1. app.ticket_escalation_policies / app.ticket_escalation_policy_versions
--    -- versioned scope catalog, mirrors app.ticket_routing_rules /
--    app.ticket_routing_rule_versions (HRT-290) exactly.
-- ===========================================================================

create table app.ticket_escalation_policies (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  code text not null,
  name text not null,
  status text not null default 'active',
  record_version integer not null default 1,
  created_by text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint ticket_escalation_policies_status_check check (status in ('active', 'inactive')),
  constraint ticket_escalation_policies_code_check check (length(trim(code)) > 0),
  constraint ticket_escalation_policies_name_check check (length(trim(name)) > 0),
  constraint ticket_escalation_policies_code_unique unique (tenant_id, code)
);

create index ticket_escalation_policies_tenant_status_idx on app.ticket_escalation_policies (tenant_id, status);

create trigger ticket_escalation_policies_touch before update on app.ticket_escalation_policies
  for each row execute function app.touch_ticket_row();

create table app.ticket_escalation_policy_versions (
  id uuid primary key default gen_random_uuid(),
  policy_id uuid not null references app.ticket_escalation_policies (id),
  tenant_id uuid not null references app.tenants (id),
  version_number integer not null,
  status text not null default 'draft',
  channel text not null,
  category_id uuid references app.ticket_categories (id),
  priority text,
  queue_id uuid references app.ticket_queues (id),
  precedence_rank integer not null default 0,
  published_at timestamptz,
  published_by text,
  record_version integer not null default 1,
  created_by text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint ticket_escalation_policy_versions_status_check check (status in ('draft', 'published', 'superseded')),
  constraint ticket_escalation_policy_versions_channel_check check (channel in ('internal', 'customer')),
  constraint ticket_escalation_policy_versions_priority_check check (priority is null or priority in ('low', 'normal', 'high', 'urgent')),
  constraint ticket_escalation_policy_versions_published_shape_check check (
    (status <> 'published') or (published_at is not null and published_by is not null)
  ),
  constraint ticket_escalation_policy_versions_scope_unique unique (policy_id, version_number)
);

comment on table app.ticket_escalation_policy_versions is
  'HRT-291 (decision 1): channel restricted to internal/customer -- helpdesk has no eligibility model to escalate within, mirroring app.ticket_routing_rule_versions (HRT-290) exactly. category_id/priority/queue_id are each either NULL (wildcard) or an exact match; app._resolve_ticket_escalation_policy_version_for_ticket is the single deterministic precedence engine.';

create index ticket_escalation_policy_versions_policy_idx on app.ticket_escalation_policy_versions (policy_id, status);
create index ticket_escalation_policy_versions_match_idx on app.ticket_escalation_policy_versions (tenant_id, channel, status) where status = 'published';

create trigger ticket_escalation_policy_versions_touch before update on app.ticket_escalation_policy_versions
  for each row execute function app.touch_ticket_row();

-- ===========================================================================
-- 2. app.ticket_escalation_levels -- steps within one policy version
--    (decisions 2/3/8).
-- ===========================================================================

create table app.ticket_escalation_levels (
  id uuid primary key default gen_random_uuid(),
  policy_version_id uuid not null references app.ticket_escalation_policy_versions (id),
  tenant_id uuid not null references app.tenants (id),
  level_number integer not null,
  trigger_type text not null,
  threshold_minutes integer,
  min_priority text,
  target_type text not null,
  target_queue_id uuid references app.ticket_queues (id),
  target_employee_id uuid references app.employees (master_record_id),
  action_notify boolean not null default true,
  action_reassign boolean not null default false,
  cooldown_minutes integer not null default 60,
  created_by text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint ticket_escalation_levels_level_number_check check (level_number > 0),
  constraint ticket_escalation_levels_trigger_type_check check (trigger_type in (
    'sla_response_warning', 'sla_response_breach', 'sla_resolution_warning', 'sla_resolution_breach',
    'priority_threshold', 'inactivity', 'assignment_failure'
  )),
  constraint ticket_escalation_levels_threshold_shape_check check (
    (trigger_type in ('inactivity', 'assignment_failure') and threshold_minutes is not null and threshold_minutes > 0)
    or (trigger_type not in ('inactivity', 'assignment_failure') and threshold_minutes is null)
  ),
  constraint ticket_escalation_levels_min_priority_check check (min_priority is null or min_priority in ('low', 'normal', 'high', 'urgent')),
  constraint ticket_escalation_levels_min_priority_shape_check check (trigger_type <> 'priority_threshold' or min_priority is not null),
  constraint ticket_escalation_levels_target_type_check check (target_type in ('queue', 'employee')),
  constraint ticket_escalation_levels_target_shape_check check (
    (target_type = 'queue' and target_queue_id is not null and target_employee_id is null)
    or (target_type = 'employee' and target_employee_id is not null and target_queue_id is null)
  ),
  constraint ticket_escalation_levels_reassign_shape_check check (not action_reassign or target_type = 'employee'),
  constraint ticket_escalation_levels_cooldown_check check (cooldown_minutes > 0),
  constraint ticket_escalation_levels_scope_unique unique (policy_version_id, level_number)
);

comment on table app.ticket_escalation_levels is
  'HRT-291 (decisions 2/3/8): one step of one policy version. trigger_type is the auto-evaluation condition (min_priority is an ADDITIONAL optional gate on every trigger_type, and the sole condition when trigger_type=priority_threshold); target is queue OR employee only (decision 2, no role/team target); action_notify/action_reassign are the two real, independently-configured actions (decision 3, no approval/task creation); cooldown_minutes paces how soon the NEXT level may fire after this one''s own last trigger (decision 8) -- never a re-trigger guard for this SAME level, which the natural-key unique index on app.ticket_escalation_events already makes structurally impossible within one escalation cycle.';

create index ticket_escalation_levels_version_idx on app.ticket_escalation_levels (policy_version_id, level_number);

-- No touch trigger here, deliberately -- this table carries no record_version
-- (decision: a level is only ever mutated while its parent policy_version is
-- draft, gated by that PARENT's own record_version check in app.add_ticket_
-- escalation_level; app.touch_ticket_row() itself requires a record_version
-- column, which would be meaningless on a child row with no independent
-- optimistic-concurrency contract of its own). app.add_ticket_escalation_
-- level sets updated_at explicitly on its own UPDATE branch instead.

-- ===========================================================================
-- 3. app.ticket_escalations -- the CURRENT escalation state cache, one row
--    per ticket, mirrors app.ticket_sla_clocks' own "cache + append-only
--    ledger" split (HRT-289 decision 5) exactly.
-- ===========================================================================

create table app.ticket_escalations (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  ticket_id uuid not null references app.tickets (id),
  policy_version_id uuid references app.ticket_escalation_policy_versions (id),
  status text not null default 'active',
  current_level integer not null,
  current_level_id uuid references app.ticket_escalation_levels (id),
  last_trigger_type text not null,
  reopen_count_at_trigger integer not null default 0,
  acknowledged_at timestamptz,
  acknowledged_by text,
  resolved_at timestamptz,
  resolved_reason text,
  last_triggered_at timestamptz not null default now(),
  record_version integer not null default 1,
  created_by text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint ticket_escalations_status_check check (status in ('active', 'acknowledged', 'resolved')),
  constraint ticket_escalations_current_level_check check (current_level > 0),
  constraint ticket_escalations_resolved_reason_check check (resolved_reason is null or resolved_reason in ('ticket_resolved', 'ticket_closed', 'ticket_cancelled', 'manual_recovery')),
  constraint ticket_escalations_resolved_shape_check check ((status <> 'resolved') or (resolved_at is not null and resolved_reason is not null)),
  constraint ticket_escalations_acknowledged_shape_check check ((status <> 'acknowledged') or (acknowledged_at is not null)),
  constraint ticket_escalations_ticket_unique unique (ticket_id)
);

comment on table app.ticket_escalations is
  'HRT-291 (decision 7): one row per ticket -- the CURRENT escalation state, reproducible at any time from app.ticket_escalation_events (the real ledger). policy_version_id is null for a ticket whose current cycle only ever had manual (unconfigured) escalations. Never a second source of truth for who is assigned -- app.tickets.assignee_employee_id remains the one current-owner column even when action_reassign fires.';

create index ticket_escalations_tenant_status_idx on app.ticket_escalations (tenant_id, status) where status <> 'resolved';

create trigger ticket_escalations_touch before update on app.ticket_escalations
  for each row execute function app.touch_ticket_row();

-- ===========================================================================
-- 4. app.ticket_escalation_events -- append-only ledger (decisions 6/15).
-- ===========================================================================

create table app.ticket_escalation_events (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  ticket_id uuid not null references app.tickets (id),
  escalation_id uuid references app.ticket_escalations (id),
  policy_version_id uuid references app.ticket_escalation_policy_versions (id),
  level_id uuid references app.ticket_escalation_levels (id),
  level_number integer not null,
  trigger_type text not null,
  ticket_reopen_count integer not null default 0,
  event_type text not null,
  target_type text,
  target_queue_id uuid references app.ticket_queues (id),
  target_employee_id uuid references app.employees (master_record_id),
  reason text,
  actor_auth_user_id uuid,
  actor_label text,
  job_id uuid references app.jobs (job_id),
  occurred_at timestamptz not null default now(),
  constraint ticket_escalation_events_level_number_check check (level_number >= 0),
  constraint ticket_escalation_events_trigger_type_check check (trigger_type in (
    'sla_response_warning', 'sla_response_breach', 'sla_resolution_warning', 'sla_resolution_breach',
    'priority_threshold', 'inactivity', 'assignment_failure', 'manual'
  )),
  constraint ticket_escalation_events_event_type_check check (event_type in (
    'triggered', 'notified', 'notification_failed', 'reassigned', 'reassign_skipped',
    'acknowledged', 'suppressed', 'suppression_ended', 'resolved', 'recovered'
  )),
  constraint ticket_escalation_events_target_type_check check (target_type is null or target_type in ('queue', 'employee'))
);

comment on table app.ticket_escalation_events is
  'HRT-291 (decisions 6/15): the append-only compliance ledger -- the ONLY authoritative source of escalation history. Governed by the SAME RLS as the parent ticket (app.can_access_ticket), never app.audit_logs (decision 15), mirroring app.ticket_assignment_events (HRT-290) exactly. The unique index below is the REAL idempotency guarantee (decision 6, C-01/C-02) -- a retried batch evaluation cannot insert a second triggered row for the same (ticket, policy_version, trigger_type, level_number, reopen_count).';

create unique index ticket_escalation_events_triggered_unique on app.ticket_escalation_events (ticket_id, policy_version_id, trigger_type, level_number, ticket_reopen_count) where event_type = 'triggered' and policy_version_id is not null;
create index ticket_escalation_events_ticket_idx on app.ticket_escalation_events (ticket_id, occurred_at asc);
create index ticket_escalation_events_tenant_type_idx on app.ticket_escalation_events (tenant_id, event_type);

-- ===========================================================================
-- 5. app.ticket_escalation_suppressions -- authority/reason/expiry-gated
--    cooldown (decision 11).
-- ===========================================================================

create table app.ticket_escalation_suppressions (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  ticket_id uuid not null references app.tickets (id),
  reason text not null,
  expires_at timestamptz not null,
  suppressed_by_auth_user_id uuid not null,
  suppressed_by text,
  revoked_at timestamptz,
  revoked_by text,
  revoked_reason text,
  record_version integer not null default 1,
  created_at timestamptz not null default now(),
  constraint ticket_escalation_suppressions_reason_check check (length(trim(reason)) > 0)
);

comment on column app.ticket_escalation_suppressions.expires_at is
  'HRT-291: app.suppress_ticket_escalation validates expires_at > now() at INSERT time (the real, enforced invariant) -- deliberately NOT a table CHECK against created_at, which would only ever compare two values captured in the same instant (always true at insert, never meaningfully violated) while blocking the legitimate later state "time has since passed and this row is now expired" that app._evaluate_ticket_escalation/app.suppress_ticket_escalation both detect and act on.';

comment on table app.ticket_escalation_suppressions is
  'HRT-291 (decision 11, business rule "suppression/cooldown requires authority, reason, expiry, never hides compliance reporting"): TKT:Assign-gated (app.suppress_ticket_escalation), a materially higher bar than plain is_ticket_staff. At most one non-revoked row per ticket at a time (the partial unique index below); an already-expired-but-unrevoked row is auto-revoked (revoked_reason=''expired'') the next time it is checked, never silently left stale. Never hides app.ticket_escalation_events -- suppression only gates whether a NEW level may auto-trigger.';

create unique index ticket_escalation_suppressions_active_unique on app.ticket_escalation_suppressions (ticket_id) where revoked_at is null;
create index ticket_escalation_suppressions_ticket_idx on app.ticket_escalation_suppressions (ticket_id, revoked_at);

-- ===========================================================================
-- 6. Audit projection + internal helpers (decisions 5/15).
-- ===========================================================================

create function app.ticket_escalation_audit_projection(p_escalation app.ticket_escalations)
returns jsonb
language sql
immutable
as $$
  select jsonb_build_object(
    'id', p_escalation.id,
    'tenant_id', p_escalation.tenant_id,
    'ticket_id', p_escalation.ticket_id,
    'policy_version_id', p_escalation.policy_version_id,
    'status', p_escalation.status,
    'current_level', p_escalation.current_level,
    'record_version', p_escalation.record_version
  );
$$;

comment on function app.ticket_escalation_audit_projection is
  'HRT-291 (decision 15, C-24 discipline): explicit structural-fields-only allowlist -- never to_jsonb(row). Never carries acknowledged_by/resolved_reason free-text-adjacent fields into app.audit_logs.';

create function app._ticket_priority_rank(p_priority text)
returns integer
language sql
immutable
set search_path = app, pg_temp
as $$
  select array_position(array['low', 'normal', 'high', 'urgent'], p_priority);
$$;

comment on function app._ticket_priority_rank is
  'HRT-291: ordinal rank for the closed low/normal/high/urgent priority enum, used only for min_priority comparisons.';

create function app._ticket_escalation_target_eligible(p_tenant_id uuid, p_target_type text, p_target_queue_id uuid, p_target_employee_id uuid)
returns boolean
language sql
stable
security definer
set search_path = app, pg_temp
as $$
  select case
    when p_target_type = 'queue' then exists (select 1 from app.ticket_queues q where q.id = p_target_queue_id and q.tenant_id = p_tenant_id and q.status = 'active')
    when p_target_type = 'employee' then
      exists (select 1 from app.employees e where e.master_record_id = p_target_employee_id and e.tenant_id = p_tenant_id)
      and app._is_employee_ticket_eligible(p_tenant_id, p_target_employee_id)
    else false
  end;
$$;

comment on function app._ticket_escalation_target_eligible is
  'HRT-291 (decision 5): reuses app._is_employee_ticket_eligible (HRT-290) verbatim for an employee target -- never a parallel eligibility concept. A queue target is eligible iff it exists, is tenant-scoped, and is active.';

grant execute on function app._ticket_priority_rank(text) to service_role;
grant execute on function app._ticket_escalation_target_eligible(uuid, text, uuid, uuid) to service_role;

-- ===========================================================================
-- 7. Policy/level authoring RPCs (TKT:Edit) -- mirrors app.create_ticket_
--    routing_rule/app.create_ticket_routing_rule_version (HRT-290) exactly.
-- ===========================================================================

create function app.create_ticket_escalation_policy(p_tenant_id uuid, p_code text, p_name text, p_actor_auth_user_id uuid, p_actor_label text)
returns app.ticket_escalation_policies
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_existing app.ticket_escalation_policies;
  v_row app.ticket_escalation_policies;
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

  select * into v_existing from app.ticket_escalation_policies where tenant_id = p_tenant_id and code = p_code;
  if found then
    return v_existing;
  end if;

  begin
    insert into app.ticket_escalation_policies (tenant_id, code, name, created_by)
    values (p_tenant_id, p_code, p_name, p_actor_label)
    returning * into v_row;
  exception
    when unique_violation then
      select * into v_row from app.ticket_escalation_policies where tenant_id = p_tenant_id and code = p_code;
      if not found then
        raise;
      end if;
  end;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'create_ticket_escalation_policy',
    'app.ticket_escalation_policies', v_row.id, 'success', null, null, jsonb_build_object('code', v_row.code)
  );

  return v_row;
end;
$$;

create function app.create_ticket_escalation_policy_version(
  p_policy_id uuid, p_channel text, p_category_id uuid, p_priority text, p_queue_id uuid, p_precedence_rank integer,
  p_actor_auth_user_id uuid, p_actor_label text
)
returns app.ticket_escalation_policy_versions
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_policy app.ticket_escalation_policies;
  v_next_version integer;
  v_row app.ticket_escalation_policy_versions;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  select * into v_policy from app.ticket_escalation_policies where id = p_policy_id for update;
  if not found then
    raise exception 'ticket_escalation_policy_not_found: %', p_policy_id using errcode = 'no_data_found';
  end if;
  if not app.check_ticket_authority('Edit', v_policy.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks TKT:Edit for tenant %', p_actor_auth_user_id, v_policy.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if p_channel is null or not (p_channel = any (array['internal', 'customer'])) then
    raise exception 'invalid_channel: % is not one of internal/customer -- helpdesk escalation has no non-Supreme-Admin model (decision 1)', p_channel using errcode = 'check_violation';
  end if;
  if p_priority is not null and not (p_priority = any (array['low', 'normal', 'high', 'urgent'])) then
    raise exception 'invalid_priority: % is not one of low/normal/high/urgent', p_priority using errcode = 'check_violation';
  end if;
  if p_category_id is not null and not exists (select 1 from app.ticket_categories c where c.id = p_category_id and c.tenant_id = v_policy.tenant_id) then
    raise exception 'ticket_category_not_found: %', p_category_id using errcode = 'no_data_found';
  end if;
  if p_queue_id is not null and not exists (select 1 from app.ticket_queues q where q.id = p_queue_id and q.tenant_id = v_policy.tenant_id) then
    raise exception 'ticket_queue_not_found: %', p_queue_id using errcode = 'no_data_found';
  end if;

  select coalesce(max(version_number), 0) + 1 into v_next_version from app.ticket_escalation_policy_versions where policy_id = p_policy_id;

  insert into app.ticket_escalation_policy_versions (
    policy_id, tenant_id, version_number, channel, category_id, priority, queue_id, precedence_rank, created_by
  ) values (
    p_policy_id, v_policy.tenant_id, v_next_version, p_channel, p_category_id, p_priority, p_queue_id, coalesce(p_precedence_rank, 0), p_actor_label
  )
  returning * into v_row;

  perform app.capture_audit_event(
    v_policy.tenant_id, p_actor_auth_user_id, p_actor_label, 'create_ticket_escalation_policy_version',
    'app.ticket_escalation_policy_versions', v_row.id, 'success', null, null,
    jsonb_build_object('policy_id', p_policy_id, 'version_number', v_next_version, 'channel', p_channel, 'category_id', p_category_id, 'priority', p_priority, 'queue_id', p_queue_id, 'precedence_rank', v_row.precedence_rank)
  );

  return v_row;
end;
$$;

create function app.add_ticket_escalation_level(
  p_policy_version_id uuid, p_level_number integer, p_trigger_type text, p_threshold_minutes integer, p_min_priority text,
  p_target_type text, p_target_queue_id uuid, p_target_employee_id uuid, p_action_notify boolean, p_action_reassign boolean,
  p_cooldown_minutes integer, p_actor_auth_user_id uuid, p_actor_label text
)
returns app.ticket_escalation_levels
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_version app.ticket_escalation_policy_versions;
  v_row app.ticket_escalation_levels;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  select * into v_version from app.ticket_escalation_policy_versions where id = p_policy_version_id for update;
  if not found then
    raise exception 'ticket_escalation_policy_version_not_found: %', p_policy_version_id using errcode = 'no_data_found';
  end if;
  if not app.check_ticket_authority('Edit', v_version.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks TKT:Edit for tenant %', p_actor_auth_user_id, v_version.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if v_version.status <> 'draft' then
    raise exception 'invalid_state: policy version % is % not draft', p_policy_version_id, v_version.status using errcode = 'check_violation';
  end if;
  if p_level_number is null or p_level_number <= 0 then
    raise exception 'invalid_level_number: level_number must be a positive integer' using errcode = 'check_violation';
  end if;
  if not (p_trigger_type = any (array['sla_response_warning', 'sla_response_breach', 'sla_resolution_warning', 'sla_resolution_breach', 'priority_threshold', 'inactivity', 'assignment_failure'])) then
    raise exception 'invalid_trigger_type: % is not a recognized escalation trigger type', p_trigger_type using errcode = 'check_violation';
  end if;
  if p_trigger_type in ('inactivity', 'assignment_failure') and coalesce(p_threshold_minutes, 0) <= 0 then
    raise exception 'threshold_minutes_required: a positive threshold_minutes is required for trigger_type %', p_trigger_type using errcode = 'check_violation';
  end if;
  if p_trigger_type not in ('inactivity', 'assignment_failure') and p_threshold_minutes is not null then
    raise exception 'threshold_minutes_not_applicable: threshold_minutes only applies to inactivity/assignment_failure' using errcode = 'check_violation';
  end if;
  if p_trigger_type = 'priority_threshold' and p_min_priority is null then
    raise exception 'min_priority_required: priority_threshold requires a min_priority' using errcode = 'check_violation';
  end if;
  if p_min_priority is not null and not (p_min_priority = any (array['low', 'normal', 'high', 'urgent'])) then
    raise exception 'invalid_priority: % is not one of low/normal/high/urgent', p_min_priority using errcode = 'check_violation';
  end if;
  if not (p_target_type = any (array['queue', 'employee'])) then
    raise exception 'invalid_target_type: % is not one of queue/employee (decision 2 -- no role/team target)', p_target_type using errcode = 'check_violation';
  end if;
  if p_target_type = 'queue' then
    if p_target_queue_id is null or p_target_employee_id is not null then
      raise exception 'invalid_target: target_type=queue requires target_queue_id only' using errcode = 'check_violation';
    end if;
    if not exists (select 1 from app.ticket_queues q where q.id = p_target_queue_id and q.tenant_id = v_version.tenant_id) then
      raise exception 'ticket_queue_not_found: %', p_target_queue_id using errcode = 'no_data_found';
    end if;
  else
    if p_target_employee_id is null or p_target_queue_id is not null then
      raise exception 'invalid_target: target_type=employee requires target_employee_id only' using errcode = 'check_violation';
    end if;
    if not exists (select 1 from app.employees e where e.master_record_id = p_target_employee_id and e.tenant_id = v_version.tenant_id) then
      raise exception 'employee_not_found: %', p_target_employee_id using errcode = 'no_data_found';
    end if;
  end if;
  if coalesce(p_action_reassign, false) and p_target_type <> 'employee' then
    raise exception 'invalid_target: reassignment requires an employee target' using errcode = 'check_violation';
  end if;
  if coalesce(p_cooldown_minutes, 60) <= 0 then
    raise exception 'invalid_cooldown: cooldown_minutes must be positive' using errcode = 'check_violation';
  end if;

  begin
    insert into app.ticket_escalation_levels (
      policy_version_id, tenant_id, level_number, trigger_type, threshold_minutes, min_priority,
      target_type, target_queue_id, target_employee_id, action_notify, action_reassign, cooldown_minutes, created_by
    ) values (
      p_policy_version_id, v_version.tenant_id, p_level_number, p_trigger_type, p_threshold_minutes, p_min_priority,
      p_target_type, p_target_queue_id, p_target_employee_id, coalesce(p_action_notify, true), coalesce(p_action_reassign, false), coalesce(p_cooldown_minutes, 60), p_actor_label
    )
    returning * into v_row;
  exception
    when unique_violation then
      update app.ticket_escalation_levels set
        trigger_type = p_trigger_type, threshold_minutes = p_threshold_minutes, min_priority = p_min_priority,
        target_type = p_target_type, target_queue_id = p_target_queue_id, target_employee_id = p_target_employee_id,
        action_notify = coalesce(p_action_notify, true), action_reassign = coalesce(p_action_reassign, false),
        cooldown_minutes = coalesce(p_cooldown_minutes, 60), updated_at = now()
      where policy_version_id = p_policy_version_id and level_number = p_level_number
      returning * into v_row;
  end;

  return v_row;
end;
$$;

comment on function app.add_ticket_escalation_level is
  'HRT-291: draft-only authoring, idempotent insert-or-update-in-place on the (policy_version_id, level_number) natural key -- mirrors app.add_sla_calendar_business_hours (HRT-289) exactly.';

create function app.publish_ticket_escalation_policy_version(p_version_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text)
returns app.ticket_escalation_policy_versions
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_version app.ticket_escalation_policy_versions;
  v_policy app.ticket_escalation_policies;
  v_updated app.ticket_escalation_policy_versions;
  v_has_levels boolean;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  select * into v_version from app.ticket_escalation_policy_versions where id = p_version_id for update;
  if not found then
    raise exception 'ticket_escalation_policy_version_not_found: %', p_version_id using errcode = 'no_data_found';
  end if;
  select * into v_policy from app.ticket_escalation_policies where id = v_version.policy_id for update;

  if not app.check_ticket_authority('Edit', v_version.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks TKT:Edit for tenant %', p_actor_auth_user_id, v_version.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if v_version.record_version <> p_expected_version then
    raise exception 'stale_version: expected version % but current version is %', p_expected_version, v_version.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_version.status <> 'draft' then
    raise exception 'invalid_state: policy version % is % not draft', p_version_id, v_version.status using errcode = 'check_violation';
  end if;

  select exists (select 1 from app.ticket_escalation_levels l where l.policy_version_id = p_version_id) into v_has_levels;
  if not v_has_levels then
    raise exception 'escalation_policy_incomplete: version % has no escalation levels configured', p_version_id using errcode = 'check_violation';
  end if;

  -- Supersede this SAME policy's own prior published version, applied FROM
  -- THE START (HRT-289/290's own self-found fix, reused precedent) --
  -- deliberately does NOT supersede a DIFFERENT policy's version; that
  -- ambiguity is caught at RESOLUTION time (ticket_escalation_policy_
  -- ambiguous_match), never suppressed here.
  update app.ticket_escalation_policy_versions
  set status = 'superseded'
  where policy_id = v_version.policy_id and status = 'published';

  update app.ticket_escalation_policy_versions
  set status = 'published', published_at = now(), published_by = p_actor_label
  where id = p_version_id and record_version = p_expected_version
  returning * into v_updated;
  if not found then
    raise exception 'stale_version: concurrent update detected for policy version %', p_version_id using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_version.tenant_id, p_actor_auth_user_id, p_actor_label, 'publish_ticket_escalation_policy_version',
    'app.ticket_escalation_policy_versions', p_version_id, 'success', null, null,
    jsonb_build_object('policy_id', v_version.policy_id, 'version_number', v_updated.version_number)
  );

  return v_updated;
end;
$$;

-- ===========================================================================
-- 8. app._resolve_ticket_escalation_policy_version_for_ticket -- the
--    deterministic precedence engine, mirrors app._resolve_ticket_routing_
--    rule_for_ticket (HRT-290) verbatim in shape.
-- ===========================================================================

create function app._resolve_ticket_escalation_policy_version_for_ticket(p_ticket app.tickets)
returns app.ticket_escalation_policy_versions
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_rec record;
  v_best_id uuid;
  v_tie_count integer := 0;
  v_result app.ticket_escalation_policy_versions;
begin
  if p_ticket.channel not in ('internal', 'customer') then
    return null;
  end if;

  for v_rec in
    select pv.id,
      rank() over (
        order by
          (pv.queue_id is not null) desc,
          (pv.category_id is not null) desc,
          (pv.priority is not null) desc,
          pv.precedence_rank desc
      ) as tie_rank
    from app.ticket_escalation_policy_versions pv
    join app.ticket_escalation_policies p on p.id = pv.policy_id
    where p.tenant_id = p_ticket.tenant_id
      and p.status = 'active'
      and pv.status = 'published'
      and pv.channel = p_ticket.channel
      and (pv.category_id is null or pv.category_id = p_ticket.category_id)
      and (pv.priority is null or pv.priority = p_ticket.priority)
      and (pv.queue_id is null or pv.queue_id = p_ticket.queue_id)
    order by tie_rank asc
  loop
    exit when v_rec.tie_rank > 1;
    v_tie_count := v_tie_count + 1;
    v_best_id := v_rec.id;
  end loop;

  if v_tie_count = 0 then
    return null;
  elsif v_tie_count > 1 then
    raise exception 'ticket_escalation_policy_ambiguous_match: % published escalation policy versions tie for tenant % channel %', v_tie_count, p_ticket.tenant_id, p_ticket.channel
      using errcode = 'check_violation';
  end if;

  select pv.* into v_result from app.ticket_escalation_policy_versions pv where pv.id = v_best_id;
  return v_result;
end;
$$;

grant execute on function app._resolve_ticket_escalation_policy_version_for_ticket(app.tickets) to service_role;

create function app.preview_ticket_escalation(p_tenant_id uuid, p_channel text, p_category_id uuid, p_priority text, p_queue_id uuid, p_actor_auth_user_id uuid)
returns table (matched boolean, policy_id uuid, policy_version_id uuid, version_number integer, level_count integer)
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_policy_version app.ticket_escalation_policy_versions;
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
  v_fake_ticket.queue_id := p_queue_id;

  v_policy_version := app._resolve_ticket_escalation_policy_version_for_ticket(v_fake_ticket);

  if v_policy_version.id is null then
    return query select false, null::uuid, null::uuid, null::integer, null::integer;
    return;
  end if;

  return query
  select true, v_policy_version.policy_id, v_policy_version.id, v_policy_version.version_number,
    (select count(*)::integer from app.ticket_escalation_levels l where l.policy_version_id = v_policy_version.id);
end;
$$;

comment on function app.preview_ticket_escalation is
  'HRT-291 (section 14 "policy preview"): TKT:Edit-gated simulation against a SYNTHETIC ticket row -- never a real app.tickets insert, mirrors app.preview_ticket_routing (HRT-290) exactly.';

-- ===========================================================================
-- 9. app._queue_ticket_escalation_notification / app._apply_ticket_
--    escalation -- the shared engine every trigger path (manual, auto) calls
--    (decisions 4/5/9/10). service_role only -- nested-called by the owner-
--    privileged functions below.
-- ===========================================================================

create function app._queue_ticket_escalation_notification(
  p_ticket app.tickets, p_escalation_id uuid, p_level_number integer, p_trigger_type text,
  p_target_type text, p_target_queue_id uuid, p_target_employee_id uuid, p_job_id uuid,
  p_actor_auth_user_id uuid, p_actor_label text
)
returns void
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_config_version_id uuid;
  v_recipient_auth_user_id uuid;
  v_dedupe_key text := p_ticket.id::text || ':' || p_level_number::text || ':' || p_trigger_type;
begin
  select v.id into v_config_version_id
  from app.config_versions v
  join app.config_objects o on o.id = v.config_object_id
  where o.config_type_code = 'notification:ticket_escalated' and v.status = 'published'
  order by v.version_number desc
  limit 1;

  if v_config_version_id is null then
    insert into app.ticket_escalation_events (tenant_id, ticket_id, escalation_id, level_number, trigger_type, ticket_reopen_count, event_type, reason, job_id)
    values (p_ticket.tenant_id, p_ticket.id, p_escalation_id, p_level_number, p_trigger_type, p_ticket.reopen_count, 'notification_failed', 'no published ticket_escalated notification template is configured', p_job_id);
    return;
  end if;

  if p_target_type = 'employee' and p_target_employee_id is not null then
    select u.auth_user_id into v_recipient_auth_user_id
    from app.employees e join app.users u on u.id = e.user_id
    where e.master_record_id = p_target_employee_id;
  elsif p_target_type = 'queue' and p_target_queue_id is not null then
    select u.auth_user_id into v_recipient_auth_user_id
    from app.ticket_queue_members m
    join app.employees e on e.master_record_id = m.employee_id
    join app.users u on u.id = e.user_id
    where m.queue_id = p_target_queue_id and m.status = 'active'
      and app.has_active_tenant_membership(p_ticket.tenant_id, u.auth_user_id)
    order by m.added_at asc
    limit 1;
  end if;

  if v_recipient_auth_user_id is null or not app.has_active_tenant_membership(p_ticket.tenant_id, v_recipient_auth_user_id) then
    insert into app.ticket_escalation_events (tenant_id, ticket_id, escalation_id, level_number, trigger_type, ticket_reopen_count, event_type, reason, job_id)
    values (p_ticket.tenant_id, p_ticket.id, p_escalation_id, p_level_number, p_trigger_type, p_ticket.reopen_count, 'notification_failed', 'no active, tenant-authorized recipient could be resolved for this escalation target', p_job_id);
    return;
  end if;

  begin
    perform app.queue_notification(
      v_config_version_id, p_ticket.tenant_id, 'ticket_escalated', v_recipient_auth_user_id, 'in_app', 'en',
      jsonb_build_object('ticket_number', p_ticket.ticket_number, 'escalation_level', p_level_number, 'trigger_type', p_trigger_type),
      v_dedupe_key, p_actor_auth_user_id, p_actor_label
    );
    insert into app.ticket_escalation_events (tenant_id, ticket_id, escalation_id, level_number, trigger_type, ticket_reopen_count, event_type, target_type, target_queue_id, target_employee_id, job_id)
    values (p_ticket.tenant_id, p_ticket.id, p_escalation_id, p_level_number, p_trigger_type, p_ticket.reopen_count, 'notified', p_target_type, p_target_queue_id, p_target_employee_id, p_job_id);
  exception
    when others then
      -- Deliberately, narrowly isolated (decision, this function only): a
      -- notification-queuing failure (e.g. an unsafe context value) must
      -- never roll back the real 'triggered'/'reassigned' state this
      -- function's own caller already committed earlier in the same
      -- transaction -- section 18/"retry/failure visibility" requires the
      -- failure to be RECORDED, not to abort the whole escalation.
      insert into app.ticket_escalation_events (tenant_id, ticket_id, escalation_id, level_number, trigger_type, ticket_reopen_count, event_type, reason, job_id)
      values (p_ticket.tenant_id, p_ticket.id, p_escalation_id, p_level_number, p_trigger_type, p_ticket.reopen_count, 'notification_failed', 'queue_notification raised: ' || sqlerrm, p_job_id);
  end;
end;
$$;

comment on function app._queue_ticket_escalation_notification is
  'HRT-291 (decisions 5/9/10): resolves a real recipient (the target employee''s own linked auth user, or the earliest-added active member of the target queue), calls app.queue_notification (PLT-127) -- this checkpoint''s first real domain consumer -- and always records a discriminated ticket_escalation_events row (notified/notification_failed), never a silent drop.';

create function app._apply_ticket_escalation(
  p_ticket app.tickets, p_policy_version_id uuid, p_level_id uuid, p_level_number integer, p_trigger_type text,
  p_target_type text, p_target_queue_id uuid, p_target_employee_id uuid, p_do_notify boolean, p_do_reassign boolean,
  p_reason text, p_actor_auth_user_id uuid, p_actor_label text, p_job_id uuid
)
returns app.ticket_escalations
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_existing app.ticket_escalations;
  v_row app.ticket_escalations;
  v_reassign_eligible boolean;
  v_already_triggered boolean := false;
begin
  select * into v_existing from app.ticket_escalations where ticket_id = p_ticket.id for update;

  if not found then
    begin
      insert into app.ticket_escalations (
        tenant_id, ticket_id, policy_version_id, status, current_level, current_level_id,
        last_trigger_type, reopen_count_at_trigger, last_triggered_at, created_by
      ) values (
        p_ticket.tenant_id, p_ticket.id, p_policy_version_id, 'active', p_level_number, p_level_id,
        p_trigger_type, p_ticket.reopen_count, now(), p_actor_label
      )
      returning * into v_row;
    exception
      when unique_violation then
        select * into v_existing from app.ticket_escalations where ticket_id = p_ticket.id for update;
        if not found then
          raise;
        end if;
    end;
  end if;

  if v_row.id is null then
    -- Either the initial select found an existing row, or the insert hit a
    -- concurrent unique_violation and re-selected it above (C-01/C-02
    -- belt-and-suspenders -- the caller's own ticket-row lock, held by every
    -- entry point into this function, already makes this race narrow; this
    -- is defense in depth, not the sole guarantee).
    update app.ticket_escalations
    set policy_version_id = p_policy_version_id,
        status = 'active',
        current_level = p_level_number,
        current_level_id = p_level_id,
        last_trigger_type = p_trigger_type,
        reopen_count_at_trigger = p_ticket.reopen_count,
        last_triggered_at = now(),
        acknowledged_at = null,
        acknowledged_by = null
    where id = v_existing.id and record_version = v_existing.record_version
    returning * into v_row;
    if not found then
      raise exception 'stale_version: concurrent escalation update detected for ticket %', p_ticket.id using errcode = 'serialization_failure';
    end if;
  end if;

  -- C-01/C-02: the REAL idempotency guarantee is this real partial unique
  -- index (ticket_escalation_events_triggered_unique) plus this real
  -- exception handler -- not merely a pre-check. A genuine retry of the
  -- exact same natural key (ticket, policy_version, trigger_type,
  -- level_number, reopen_count) lands here as a clean, detected no-op:
  -- the escalation STATE row above may still legitimately advance/update
  -- (idempotent to re-apply), but the notify/reassign SUB-ACTIONS below are
  -- skipped on a detected duplicate -- they already ran on the original
  -- trigger, and re-running them would be the exact "retry creates a
  -- duplicate action" the business rule forbids.
  begin
    insert into app.ticket_escalation_events (
      tenant_id, ticket_id, escalation_id, policy_version_id, level_id, level_number, trigger_type,
      ticket_reopen_count, event_type, target_type, target_queue_id, target_employee_id, reason,
      actor_auth_user_id, actor_label, job_id
    ) values (
      p_ticket.tenant_id, p_ticket.id, v_row.id, p_policy_version_id, p_level_id, p_level_number, p_trigger_type,
      p_ticket.reopen_count, 'triggered', p_target_type, p_target_queue_id, p_target_employee_id, p_reason,
      p_actor_auth_user_id, p_actor_label, p_job_id
    );
  exception
    when unique_violation then
      v_already_triggered := true;
  end;

  if v_already_triggered then
    return v_row;
  end if;

  if p_do_notify then
    perform app._queue_ticket_escalation_notification(p_ticket, v_row.id, p_level_number, p_trigger_type, p_target_type, p_target_queue_id, p_target_employee_id, p_job_id, p_actor_auth_user_id, p_actor_label);
  end if;

  if p_do_reassign and p_target_type = 'employee' and p_target_employee_id is not null and p_ticket.channel in ('internal', 'customer') then
    v_reassign_eligible := app._is_employee_ticket_eligible(p_ticket.tenant_id, p_target_employee_id)
      and exists (select 1 from app.ticket_queue_members m where m.queue_id = p_ticket.queue_id and m.employee_id = p_target_employee_id and m.status = 'active');
    if v_reassign_eligible and p_ticket.assignee_employee_id is distinct from p_target_employee_id then
      perform app._apply_ticket_assignment(p_ticket, p_ticket.record_version, p_target_employee_id, 'reassign', 'manual', null, 'escalation level ' || p_level_number::text || ' reassignment', p_actor_auth_user_id, p_actor_label);
      insert into app.ticket_escalation_events (tenant_id, ticket_id, escalation_id, policy_version_id, level_id, level_number, trigger_type, ticket_reopen_count, event_type, target_type, target_employee_id, job_id)
      values (p_ticket.tenant_id, p_ticket.id, v_row.id, p_policy_version_id, p_level_id, p_level_number, p_trigger_type, p_ticket.reopen_count, 'reassigned', 'employee', p_target_employee_id, p_job_id);
    else
      insert into app.ticket_escalation_events (tenant_id, ticket_id, escalation_id, policy_version_id, level_id, level_number, trigger_type, ticket_reopen_count, event_type, target_type, target_employee_id, reason, job_id)
      values (p_ticket.tenant_id, p_ticket.id, v_row.id, p_policy_version_id, p_level_id, p_level_number, p_trigger_type, p_ticket.reopen_count, 'reassign_skipped', 'employee', p_target_employee_id, 'configured target employee is not currently an eligible, active member of this ticket''s queue', p_job_id);
    end if;
  end if;

  return v_row;
end;
$$;

comment on function app._apply_ticket_escalation is
  'HRT-291 (decisions 4/5/6): the ONE shared "advance the escalation state" engine -- app.escalate_ticket (manual) and app._evaluate_ticket_escalation (auto) both call this, never re-implementing the state-advance+ledger shape independently. Reassignment reuses app._apply_ticket_assignment (HRT-290) directly (decision 4) -- never a second per-ticket assignment mechanism. Caller''s own ticket-row lock (held before this is ever called) is what actually serializes concurrent advances for the SAME ticket; the exception handler here is defense in depth (C-01/C-02), not the sole guarantee.';

grant execute on function app._queue_ticket_escalation_notification(app.tickets, uuid, integer, text, text, uuid, uuid, uuid, uuid, text) to service_role;
grant execute on function app._apply_ticket_escalation(app.tickets, uuid, uuid, integer, text, text, uuid, uuid, boolean, boolean, text, uuid, text, uuid) to service_role;

-- ===========================================================================
-- 10. app.escalate_ticket -- manual escalation (section 14's own named API
--     operation). is_ticket_staff bar (decision 1/"eligible agents/managers
--     manually escalate"), mandatory reason (business rule), explicit target,
--     explicit opt-in reassignment (decision 3, "only as explicitly
--     configured").
-- ===========================================================================

create function app.escalate_ticket(
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

  return app._apply_ticket_escalation(
    v_ticket, null, null, v_next_level, 'manual', p_target_type, p_target_queue_id, p_target_employee_id,
    true, coalesce(p_reassign, false), p_reason, p_actor_auth_user_id, p_actor_label, null
  );
end;
$$;

comment on function app.escalate_ticket is
  'HRT-291 (decision 1, business rule "reason required"): manual escalation -- policy_version_id/level_id are null (no configured level applies), trigger_type=manual, level_number is the ticket''s own current_level + 1. A genuine double-submit with the SAME p_expected_version races on the ticket''s own record_version (this function''s own lock), matching every sibling ticket RPC''s established shape -- no separate idempotency key needed for a deliberate, versioned manual action.';

-- ===========================================================================
-- 11. app.acknowledge_ticket_escalation / app.resolve_ticket_escalation.
--     is_ticket_staff bar; idempotent replay is a real, deliberate no-op
--     (C-01), never a duplicate ledger row.
-- ===========================================================================

create function app.acknowledge_ticket_escalation(p_ticket_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text)
returns app.ticket_escalations
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_ticket app.tickets;
  v_escalation app.ticket_escalations;
  v_updated app.ticket_escalations;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  select * into v_ticket from app.tickets where id = p_ticket_id for update;
  if not found or v_ticket.channel = 'helpdesk' or not app.can_access_ticket(p_ticket_id, p_actor_auth_user_id) then
    raise exception 'ticket_not_found: %', p_ticket_id using errcode = 'no_data_found';
  end if;
  if not app.is_ticket_staff(p_ticket_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % is not ticket staff on %', p_actor_auth_user_id, p_ticket_id
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_escalation from app.ticket_escalations where ticket_id = p_ticket_id for update;
  if not found then
    raise exception 'ticket_escalation_not_found: ticket % has no active escalation', p_ticket_id using errcode = 'no_data_found';
  end if;
  if v_escalation.record_version <> p_expected_version then
    raise exception 'stale_version: expected version % but current version is %', p_expected_version, v_escalation.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_escalation.status = 'resolved' then
    raise exception 'invalid_transition: this ticket''s escalation is already resolved' using errcode = 'check_violation';
  end if;
  if v_escalation.status = 'acknowledged' then
    return v_escalation;
  end if;

  update app.ticket_escalations set status = 'acknowledged', acknowledged_at = now(), acknowledged_by = p_actor_label
  where id = v_escalation.id and record_version = p_expected_version
  returning * into v_updated;
  if not found then
    raise exception 'stale_version: concurrent escalation update detected for ticket %', p_ticket_id using errcode = 'serialization_failure';
  end if;

  insert into app.ticket_escalation_events (tenant_id, ticket_id, escalation_id, policy_version_id, level_id, level_number, trigger_type, ticket_reopen_count, event_type, actor_auth_user_id, actor_label)
  values (v_ticket.tenant_id, p_ticket_id, v_updated.id, v_updated.policy_version_id, v_updated.current_level_id, v_updated.current_level, v_updated.last_trigger_type, v_ticket.reopen_count, 'acknowledged', p_actor_auth_user_id, p_actor_label);

  perform app.capture_audit_event(
    v_ticket.tenant_id, p_actor_auth_user_id, p_actor_label, 'acknowledge_ticket_escalation',
    'app.ticket_escalations', v_updated.id, 'success', null, app.ticket_escalation_audit_projection(v_escalation), app.ticket_escalation_audit_projection(v_updated)
  );

  return v_updated;
end;
$$;

create function app.resolve_ticket_escalation(p_ticket_id uuid, p_expected_version integer, p_reason text, p_actor_auth_user_id uuid, p_actor_label text)
returns app.ticket_escalations
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_ticket app.tickets;
  v_escalation app.ticket_escalations;
  v_updated app.ticket_escalations;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  select * into v_ticket from app.tickets where id = p_ticket_id for update;
  if not found or v_ticket.channel = 'helpdesk' or not app.can_access_ticket(p_ticket_id, p_actor_auth_user_id) then
    raise exception 'ticket_not_found: %', p_ticket_id using errcode = 'no_data_found';
  end if;
  if not app.is_ticket_staff(p_ticket_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % is not ticket staff on %', p_actor_auth_user_id, p_ticket_id
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_escalation from app.ticket_escalations where ticket_id = p_ticket_id for update;
  if not found then
    raise exception 'ticket_escalation_not_found: ticket % has no active escalation', p_ticket_id using errcode = 'no_data_found';
  end if;
  if v_escalation.record_version <> p_expected_version then
    raise exception 'stale_version: expected version % but current version is %', p_expected_version, v_escalation.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_escalation.status = 'resolved' then
    return v_escalation;
  end if;

  update app.ticket_escalations set status = 'resolved', resolved_at = now(), resolved_reason = 'manual_recovery'
  where id = v_escalation.id and record_version = p_expected_version
  returning * into v_updated;
  if not found then
    raise exception 'stale_version: concurrent escalation update detected for ticket %', p_ticket_id using errcode = 'serialization_failure';
  end if;

  insert into app.ticket_escalation_events (tenant_id, ticket_id, escalation_id, policy_version_id, level_id, level_number, trigger_type, ticket_reopen_count, event_type, reason, actor_auth_user_id, actor_label)
  values (v_ticket.tenant_id, p_ticket_id, v_updated.id, v_updated.policy_version_id, v_updated.current_level_id, v_updated.current_level, v_updated.last_trigger_type, v_ticket.reopen_count, 'recovered', p_reason, p_actor_auth_user_id, p_actor_label);

  perform app.capture_audit_event(
    v_ticket.tenant_id, p_actor_auth_user_id, p_actor_label, 'resolve_ticket_escalation',
    'app.ticket_escalations', v_updated.id, 'success', null, app.ticket_escalation_audit_projection(v_escalation), app.ticket_escalation_audit_projection(v_updated)
  );

  return v_updated;
end;
$$;

comment on function app.resolve_ticket_escalation is
  'HRT-291 (decision 7, section 14''s own named "resolve/de-escalate" API operation): real-time manual de-escalation -- resolved_reason=manual_recovery, event_type=recovered (distinct from the auto-evaluator''s own event_type=resolved for a ticket-status-driven resolution, decision 7) -- the ticket itself is untouched, this only closes the escalation state.';

-- ===========================================================================
-- 12. app.suppress_ticket_escalation / app.revoke_ticket_escalation_
--     suppression -- TKT:Assign-gated (decision 11, "requires authority").
-- ===========================================================================

create function app.suppress_ticket_escalation(p_ticket_id uuid, p_reason text, p_expires_at timestamptz, p_actor_auth_user_id uuid, p_actor_label text)
returns app.ticket_escalation_suppressions
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_ticket app.tickets;
  v_stale app.ticket_escalation_suppressions;
  v_active app.ticket_escalation_suppressions;
  v_row app.ticket_escalation_suppressions;
  v_escalation app.ticket_escalations;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  select * into v_ticket from app.tickets where id = p_ticket_id for update;
  if not found or v_ticket.channel = 'helpdesk' or not app.can_access_ticket(p_ticket_id, p_actor_auth_user_id) then
    raise exception 'ticket_not_found: %', p_ticket_id using errcode = 'no_data_found';
  end if;
  if not app.check_ticket_authority('Assign', v_ticket.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks TKT:Assign for tenant % -- suppression requires named authority', p_actor_auth_user_id, v_ticket.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'reason_required: a reason is required to suppress escalation' using errcode = 'check_violation';
  end if;
  if p_expires_at is null or p_expires_at <= now() then
    raise exception 'invalid_expiry: p_expires_at must be a real, future timestamp' using errcode = 'check_violation';
  end if;

  select * into v_stale from app.ticket_escalation_suppressions where ticket_id = p_ticket_id and revoked_at is null for update;
  if v_stale.id is not null then
    if v_stale.expires_at > now() then
      raise exception 'escalation_already_suppressed: an active suppression already covers this ticket until % -- revoke it first', v_stale.expires_at using errcode = 'check_violation';
    end if;
    update app.ticket_escalation_suppressions set revoked_at = now(), revoked_by = p_actor_label, revoked_reason = 'expired'
    where id = v_stale.id;
  end if;

  begin
    insert into app.ticket_escalation_suppressions (tenant_id, ticket_id, reason, expires_at, suppressed_by_auth_user_id, suppressed_by)
    values (v_ticket.tenant_id, p_ticket_id, p_reason, p_expires_at, p_actor_auth_user_id, p_actor_label)
    returning * into v_row;
  exception
    when unique_violation then
      select * into v_active from app.ticket_escalation_suppressions where ticket_id = p_ticket_id and revoked_at is null;
      if v_active.id is null then
        raise;
      end if;
      raise exception 'escalation_already_suppressed: a concurrent suppression was just created for this ticket' using errcode = 'check_violation';
  end;

  select * into v_escalation from app.ticket_escalations where ticket_id = p_ticket_id;

  insert into app.ticket_escalation_events (tenant_id, ticket_id, escalation_id, policy_version_id, level_id, level_number, trigger_type, ticket_reopen_count, event_type, reason, actor_auth_user_id, actor_label)
  values (
    v_ticket.tenant_id, p_ticket_id, v_escalation.id, v_escalation.policy_version_id, v_escalation.current_level_id,
    coalesce(v_escalation.current_level, 0), coalesce(v_escalation.last_trigger_type, 'manual'), v_ticket.reopen_count,
    'suppressed', p_reason, p_actor_auth_user_id, p_actor_label
  );

  perform app.capture_audit_event(
    v_ticket.tenant_id, p_actor_auth_user_id, p_actor_label, 'suppress_ticket_escalation',
    'app.ticket_escalation_suppressions', v_row.id, 'success', null, null,
    jsonb_build_object('ticket_id', p_ticket_id, 'expires_at', v_row.expires_at)
  );

  return v_row;
end;
$$;

create function app.revoke_ticket_escalation_suppression(p_ticket_id uuid, p_suppression_id uuid, p_expected_version integer, p_reason text, p_actor_auth_user_id uuid, p_actor_label text)
returns app.ticket_escalation_suppressions
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_ticket app.tickets;
  v_row app.ticket_escalation_suppressions;
  v_updated app.ticket_escalation_suppressions;
  v_escalation app.ticket_escalations;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  -- Ticket locked FIRST, consistently with every other escalation RPC
  -- (decision 14, C-21) -- p_ticket_id is an explicit parameter specifically
  -- so this function never has to derive it from the suppression row and
  -- lock in the reverse order app.suppress_ticket_escalation uses.
  select * into v_ticket from app.tickets where id = p_ticket_id for update;
  if not found or v_ticket.channel = 'helpdesk' or not app.can_access_ticket(p_ticket_id, p_actor_auth_user_id) then
    raise exception 'ticket_not_found: %', p_ticket_id using errcode = 'no_data_found';
  end if;
  if not app.check_ticket_authority('Assign', v_ticket.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks TKT:Assign for tenant %', p_actor_auth_user_id, v_ticket.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_row from app.ticket_escalation_suppressions where id = p_suppression_id for update;
  if not found or v_row.ticket_id <> p_ticket_id then
    raise exception 'ticket_escalation_suppression_not_found: %', p_suppression_id using errcode = 'no_data_found';
  end if;
  if v_row.record_version <> p_expected_version then
    raise exception 'stale_version: expected version % but current version is %', p_expected_version, v_row.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_row.revoked_at is not null then
    return v_row;
  end if;

  update app.ticket_escalation_suppressions set revoked_at = now(), revoked_by = p_actor_label, revoked_reason = coalesce(p_reason, 'revoked by staff')
  where id = p_suppression_id and record_version = p_expected_version
  returning * into v_updated;
  if not found then
    raise exception 'stale_version: concurrent update detected for suppression %', p_suppression_id using errcode = 'serialization_failure';
  end if;

  select * into v_escalation from app.ticket_escalations where ticket_id = p_ticket_id;

  insert into app.ticket_escalation_events (tenant_id, ticket_id, escalation_id, policy_version_id, level_id, level_number, trigger_type, ticket_reopen_count, event_type, reason, actor_auth_user_id, actor_label)
  values (
    v_ticket.tenant_id, p_ticket_id, v_escalation.id, v_escalation.policy_version_id, v_escalation.current_level_id,
    coalesce(v_escalation.current_level, 0), coalesce(v_escalation.last_trigger_type, 'manual'), v_ticket.reopen_count,
    'suppression_ended', coalesce(p_reason, 'revoked by staff'), p_actor_auth_user_id, p_actor_label
  );

  return v_updated;
end;
$$;

comment on function app.revoke_ticket_escalation_suppression is
  'HRT-291 (decision 14, C-21 discipline): takes p_ticket_id explicitly and locks it FIRST -- the SAME order app.suppress_ticket_escalation uses -- specifically to avoid a reversed-lock-order deadlock between the two functions.';

-- ===========================================================================
-- 13. app._evaluate_ticket_escalation / app.run_ticket_escalation_
--     evaluation_batch -- the durable, idempotent job wrapper (decisions 6/
--     7/8/9/10). Mirrors app.run_ticket_sla_evaluation_batch (HRT-289)
--     EXACTLY -- no live scheduler exists anywhere in this repository (the
--     same NOT_RUN class PLT-123/125/132 and HRT-289 already disclosed);
--     this is the real, callable, tested entry point a future scheduler
--     would invoke periodically.
-- ===========================================================================

create function app._evaluate_ticket_escalation(p_ticket_id uuid, p_as_of timestamptz, p_job_id uuid, p_actor_auth_user_id uuid, p_actor_label text)
returns void
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_ticket app.tickets;
  v_escalation app.ticket_escalations;
  v_policy_version app.ticket_escalation_policy_versions;
  v_level app.ticket_escalation_levels;
  v_active_suppression app.ticket_escalation_suppressions;
  v_as_of timestamptz := coalesce(p_as_of, now());
  v_resolved_reason text;
  v_is_new_cycle boolean;
  v_current_level integer;
  v_cooldown_minutes integer;
  v_condition_met boolean;
  v_minutes_since_activity numeric;
  v_minutes_unassigned numeric;
begin
  select * into v_ticket from app.tickets where id = p_ticket_id for update;
  if not found then
    return;
  end if;
  if v_ticket.channel not in ('internal', 'customer') then
    return;
  end if;

  select * into v_escalation from app.ticket_escalations where ticket_id = p_ticket_id for update;

  -- Ticket resolution/closure/cancellation resolves any still-open
  -- escalation (decision 7, C-18) -- an honest, disclosed one-batch-pass
  -- latency, mirroring HRT-289's own already-disclosed evaluation cadence.
  if v_ticket.status in ('resolved', 'closed', 'cancelled') then
    if v_escalation.id is not null and v_escalation.status <> 'resolved' then
      v_resolved_reason := case v_ticket.status when 'resolved' then 'ticket_resolved' when 'closed' then 'ticket_closed' else 'ticket_cancelled' end;
      update app.ticket_escalations set status = 'resolved', resolved_at = now(), resolved_reason = v_resolved_reason
      where id = v_escalation.id and record_version = v_escalation.record_version;
      insert into app.ticket_escalation_events (tenant_id, ticket_id, escalation_id, policy_version_id, level_id, level_number, trigger_type, ticket_reopen_count, event_type, reason, job_id)
      values (v_ticket.tenant_id, p_ticket_id, v_escalation.id, v_escalation.policy_version_id, v_escalation.current_level_id, v_escalation.current_level, v_escalation.last_trigger_type, v_ticket.reopen_count, 'resolved', v_resolved_reason, p_job_id);
    end if;
    return;
  end if;

  v_policy_version := app._resolve_ticket_escalation_policy_version_for_ticket(v_ticket);
  if v_policy_version.id is null then
    return;
  end if;

  -- Suppression gate -- auto-expires a stale, unrevoked, already-expired row
  -- (a real state transition, decision 11) before deciding.
  select * into v_active_suppression from app.ticket_escalation_suppressions where ticket_id = p_ticket_id and revoked_at is null for update;
  if v_active_suppression.id is not null then
    if v_active_suppression.expires_at <= v_as_of then
      update app.ticket_escalation_suppressions set revoked_at = now(), revoked_by = 'system:escalation-evaluation-job', revoked_reason = 'expired'
      where id = v_active_suppression.id;
      insert into app.ticket_escalation_events (tenant_id, ticket_id, escalation_id, policy_version_id, level_id, level_number, trigger_type, ticket_reopen_count, event_type, reason, job_id)
      values (v_ticket.tenant_id, p_ticket_id, v_escalation.id, v_escalation.policy_version_id, v_escalation.current_level_id, coalesce(v_escalation.current_level, 0), coalesce(v_escalation.last_trigger_type, 'manual'), v_ticket.reopen_count, 'suppression_ended', 'expired', p_job_id);
    else
      return; -- actively suppressed, no new auto-trigger this pass
    end if;
  end if;

  v_is_new_cycle := v_escalation.id is not null and v_escalation.reopen_count_at_trigger < v_ticket.reopen_count;
  v_current_level := case when v_is_new_cycle or v_escalation.id is null then 0 else v_escalation.current_level end;

  -- Cooldown gate (decision 8) -- paces how soon the NEXT level may fire
  -- after the CURRENT level's own last trigger, within the SAME cycle only.
  if not v_is_new_cycle and v_escalation.id is not null and v_escalation.current_level_id is not null then
    select l.cooldown_minutes into v_cooldown_minutes from app.ticket_escalation_levels l where l.id = v_escalation.current_level_id;
    if v_cooldown_minutes is not null and v_as_of - v_escalation.last_triggered_at < (v_cooldown_minutes || ' minutes')::interval then
      return;
    end if;
  end if;

  for v_level in
    select * from app.ticket_escalation_levels where policy_version_id = v_policy_version.id and level_number > v_current_level order by level_number asc
  loop
    v_condition_met := false;

    if v_level.min_priority is not null and app._ticket_priority_rank(v_ticket.priority) < app._ticket_priority_rank(v_level.min_priority) then
      continue; -- the optional priority gate fails regardless of trigger_type
    end if;

    if v_level.trigger_type = 'priority_threshold' then
      v_condition_met := true; -- the priority gate above already enforced min_priority
    elsif v_level.trigger_type in ('sla_response_warning', 'sla_response_breach', 'sla_resolution_warning', 'sla_resolution_breach') then
      v_condition_met := exists (
        select 1
        from app.ticket_sla_clock_events e
        join app.ticket_sla_clocks c on c.id = e.clock_id
        where c.ticket_id = p_ticket_id
          and e.phase = (case when v_level.trigger_type like 'sla_response%' then 'response' else 'resolution' end)
          and e.event_type = (case when v_level.trigger_type like '%\_warning' escape '\' then 'reminder' else 'breached' end)
      );
    elsif v_level.trigger_type = 'inactivity' then
      v_minutes_since_activity := extract(epoch from (v_as_of - v_ticket.updated_at)) / 60;
      v_condition_met := v_minutes_since_activity >= v_level.threshold_minutes;
    elsif v_level.trigger_type = 'assignment_failure' then
      v_minutes_unassigned := extract(epoch from (v_as_of - v_ticket.created_at)) / 60;
      v_condition_met := v_ticket.assignee_employee_id is null and v_minutes_unassigned >= v_level.threshold_minutes;
    end if;

    if v_condition_met then
      perform app._apply_ticket_escalation(
        v_ticket, v_policy_version.id, v_level.id, v_level.level_number, v_level.trigger_type,
        v_level.target_type, v_level.target_queue_id, v_level.target_employee_id,
        v_level.action_notify, v_level.action_reassign, null, p_actor_auth_user_id, p_actor_label, p_job_id
      );
      exit; -- one level advance per evaluation pass (performance impact: chunked/backpressure)
    end if;
  end loop;
end;
$$;

comment on function app._evaluate_ticket_escalation is
  'HRT-291 (decisions 6/7/8/10): the idempotent per-ticket evaluation primitive. Locks the ticket row FOR UPDATE first (C-04), then the escalation/suppression child rows -- consistent order across every escalation RPC (decision 14). p_actor_auth_user_id/p_actor_label are the REAL identity that invoked app.run_ticket_escalation_evaluation_batch (decision 10), threaded through to every ledger row and to app.queue_notification''s own authority check -- never a fabricated system identity. service_role only.';

create function app.run_ticket_escalation_evaluation_batch(p_tenant_id uuid, p_as_of timestamptz, p_period_label text, p_actor_auth_user_id uuid, p_actor_label text)
returns table (evaluated_count integer, job_id uuid)
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_job app.jobs;
  v_worker_id text;
  v_ticket record;
  v_evaluated integer := 0;
  v_as_of timestamptz := coalesce(p_as_of, now());
begin
  if not app.check_ticket_authority('Edit', p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks TKT:Edit for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if p_period_label is null or length(trim(p_period_label)) = 0 then
    raise exception 'invalid_period: a non-empty p_period_label is required' using errcode = 'check_violation';
  end if;

  v_job := app.enqueue_job(
    p_tenant_id, 'ticket_escalation_evaluation', jsonb_build_object('as_of', v_as_of, 'period_label', p_period_label),
    0, 'ticket_escalation_evaluation:' || p_tenant_id::text || ':' || p_period_label, 1, p_actor_auth_user_id, p_actor_label
  );

  if v_job.status = 'pending' then
    v_worker_id := 'inline-ticket-escalation-evaluation:' || p_actor_auth_user_id::text;
    update app.jobs j set status = 'in_progress', locked_by = v_worker_id, locked_until = now() + interval '10 minutes'
    where j.job_id = v_job.job_id and j.status = 'pending';

    for v_ticket in
      select t.id from app.tickets t
      where t.tenant_id = p_tenant_id
        and t.channel in ('internal', 'customer')
        and (t.status not in ('closed', 'cancelled') or exists (select 1 from app.ticket_escalations e where e.ticket_id = t.id and e.status <> 'resolved'))
    loop
      perform app._evaluate_ticket_escalation(v_ticket.id, v_as_of, v_job.job_id, p_actor_auth_user_id, p_actor_label);
      v_evaluated := v_evaluated + 1;
    end loop;

    perform app.complete_job(v_job.job_id, v_worker_id, null, p_actor_label);

    perform app.capture_audit_event(
      p_tenant_id, p_actor_auth_user_id, p_actor_label, 'run_ticket_escalation_evaluation_batch',
      'app.jobs', v_job.job_id, 'success', null, null, jsonb_build_object('period_label', p_period_label, 'evaluated_count', v_evaluated)
    );
  end if;

  evaluated_count := v_evaluated; job_id := v_job.job_id;
  return next;
end;
$$;

comment on function app.run_ticket_escalation_evaluation_batch is
  'HRT-291 (decisions 6/8/9/10): a real app.jobs row tracked through the actual PLT-132 lifecycle (enqueue -> self-claim -> complete). Idempotent per (tenant, period_label) at the JOB level (a replayed period is a pending-status no-op), AND every individual ticket evaluation inside the loop is separately idempotent at the LEDGER level regardless of job replay -- two independent, overlapping guarantees, mirroring app.run_ticket_sla_evaluation_batch (HRT-289) exactly. Also re-evaluates any ticket with a still-open escalation regardless of its own current status/channel filter, so a closed ticket''s dangling escalation is still resolved (C-18).';

grant execute on function app._evaluate_ticket_escalation(uuid, timestamptz, uuid, uuid, text) to service_role;

-- ===========================================================================
-- 14. Read RPCs (decisions 12/13, C-02 discipline -- every source table
--     aliased, no bare `where id = ...`).
-- ===========================================================================

create function app.list_ticket_escalation_policies(p_tenant_id uuid, p_actor_auth_user_id uuid)
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
  select p.id, p.code, p.name, p.status, p.record_version from app.ticket_escalation_policies p where p.tenant_id = p_tenant_id order by p.code asc;
end;
$$;

create function app.list_ticket_escalation_policy_versions(p_policy_id uuid, p_actor_auth_user_id uuid)
returns table (
  id uuid, version_number integer, status text, channel text, category_id uuid, priority text, queue_id uuid,
  precedence_rank integer, published_at timestamptz, record_version integer
)
language plpgsql
security definer
set search_path = app, pg_temp
stable
as $$
declare
  v_policy app.ticket_escalation_policies;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  select * into v_policy from app.ticket_escalation_policies where id = p_policy_id;
  if not found or not app.has_active_tenant_membership(v_policy.tenant_id, p_actor_auth_user_id) or app.actor_holds_customer_user_layer(v_policy.tenant_id, p_actor_auth_user_id) then
    return;
  end if;
  return query
  select v.id, v.version_number, v.status, v.channel, v.category_id, v.priority, v.queue_id, v.precedence_rank, v.published_at, v.record_version
  from app.ticket_escalation_policy_versions v
  where v.policy_id = p_policy_id
  order by v.version_number desc;
end;
$$;

create function app.list_ticket_escalation_levels(p_policy_version_id uuid, p_actor_auth_user_id uuid)
returns table (
  id uuid, level_number integer, trigger_type text, threshold_minutes integer, min_priority text,
  target_type text, target_queue_id uuid, target_queue_code text, target_employee_id uuid, target_employee_name text,
  action_notify boolean, action_reassign boolean, cooldown_minutes integer
)
language plpgsql
security definer
set search_path = app, pg_temp
stable
as $$
declare
  v_version app.ticket_escalation_policy_versions;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  select * into v_version from app.ticket_escalation_policy_versions where id = p_policy_version_id;
  if not found or not app.has_active_tenant_membership(v_version.tenant_id, p_actor_auth_user_id) or app.actor_holds_customer_user_layer(v_version.tenant_id, p_actor_auth_user_id) then
    return;
  end if;
  return query
  select l.id, l.level_number, l.trigger_type, l.threshold_minutes, l.min_priority,
    l.target_type, l.target_queue_id, tq.code, l.target_employee_id, te.full_name,
    l.action_notify, l.action_reassign, l.cooldown_minutes
  from app.ticket_escalation_levels l
  left join app.ticket_queues tq on tq.id = l.target_queue_id
  left join app.employees te on te.master_record_id = l.target_employee_id
  where l.policy_version_id = p_policy_version_id
  order by l.level_number asc;
end;
$$;

-- Staff-only full projection -- returns zero rows for a non-staff caller
-- (mirrors app.get_ticket_sla_clock's own graceful-empty pattern, HRT-289).
-- The ticket's own requester-side party uses
-- app.get_ticket_escalation_status_for_requester instead (decision 12).
create function app.get_ticket_escalation(p_ticket_id uuid, p_actor_auth_user_id uuid)
returns table (
  id uuid, policy_version_id uuid, status text, current_level integer, current_level_id uuid,
  last_trigger_type text, acknowledged_at timestamptz, acknowledged_by text,
  resolved_at timestamptz, resolved_reason text, last_triggered_at timestamptz, record_version integer
)
language plpgsql
security definer
set search_path = app, pg_temp
stable
as $$
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  if not app.is_ticket_staff(p_ticket_id, p_actor_auth_user_id) then
    return;
  end if;
  return query
  select e.id, e.policy_version_id, e.status, e.current_level, e.current_level_id,
    e.last_trigger_type, e.acknowledged_at, e.acknowledged_by, e.resolved_at, e.resolved_reason, e.last_triggered_at, e.record_version
  from app.ticket_escalations e
  where e.ticket_id = p_ticket_id;
end;
$$;

create function app.get_ticket_escalation_status_for_requester(p_ticket_id uuid, p_actor_auth_user_id uuid)
returns table (is_escalated boolean)
language plpgsql
security definer
set search_path = app, pg_temp
stable
as $$
declare
  v_ticket app.tickets;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  select t.* into v_ticket from app.tickets t where t.id = p_ticket_id;
  if not found then
    return;
  end if;
  if not (app._is_ticket_requester_party(v_ticket, p_actor_auth_user_id) or app.is_ticket_staff(p_ticket_id, p_actor_auth_user_id)) then
    return;
  end if;
  return query
  select exists (select 1 from app.ticket_escalations e where e.ticket_id = p_ticket_id and e.status <> 'resolved');
end;
$$;

comment on function app.get_ticket_escalation_status_for_requester is
  'HRT-291 (decision 12, security impact section 16 "customer users see only configured service-status projection"): a SINGLE boolean -- no level, no target, no trigger, no acknowledgement detail, no internal hierarchy of any kind. A structurally DIFFERENT RPC from app.get_ticket_escalation, mirroring app.get_ticket_sla_status_for_requester (HRT-289) exactly.';

create function app.list_ticket_escalation_events(p_ticket_id uuid, p_actor_auth_user_id uuid)
returns table (
  id uuid, level_number integer, trigger_type text, event_type text, target_type text,
  target_queue_id uuid, target_queue_code text, target_employee_id uuid, target_employee_name text,
  reason text, actor_label text, occurred_at timestamptz
)
language plpgsql
security definer
set search_path = app, pg_temp
stable
as $$
declare
  v_ticket app.tickets;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  select t.* into v_ticket from app.tickets t where t.id = p_ticket_id;
  if not found then
    raise exception 'ticket_not_found: %', p_ticket_id using errcode = 'no_data_found';
  end if;
  -- Folds a customer-layer caller (even for their own real ticket) into the
  -- SAME ticket_not_found response the RLS predicate would produce -- no
  -- enumeration oracle (mirrors app.list_ticket_assignment_events, HRT-290).
  if not app.can_access_ticket(p_ticket_id, p_actor_auth_user_id) or app.actor_holds_customer_user_layer(v_ticket.tenant_id, p_actor_auth_user_id) then
    raise exception 'ticket_not_found: %', p_ticket_id using errcode = 'no_data_found';
  end if;
  if v_ticket.channel = 'helpdesk' then
    raise exception 'channel_not_supported: ticket % is a helpdesk case', p_ticket_id using errcode = 'check_violation';
  end if;
  if not app.is_ticket_staff(p_ticket_id, p_actor_auth_user_id) then
    return;
  end if;

  return query
  select ev.id, ev.level_number, ev.trigger_type, ev.event_type, ev.target_type,
    ev.target_queue_id, tq.code, ev.target_employee_id, te.full_name,
    ev.reason, ev.actor_label, ev.occurred_at
  from app.ticket_escalation_events ev
  left join app.ticket_queues tq on tq.id = ev.target_queue_id
  left join app.employees te on te.master_record_id = ev.target_employee_id
  where ev.ticket_id = p_ticket_id
  order by ev.occurred_at asc;
end;
$$;

create function app.list_ticket_escalation_suppressions(p_ticket_id uuid, p_actor_auth_user_id uuid)
returns table (
  id uuid, reason text, expires_at timestamptz, suppressed_by text,
  revoked_at timestamptz, revoked_by text, revoked_reason text, record_version integer, created_at timestamptz
)
language plpgsql
security definer
set search_path = app, pg_temp
stable
as $$
declare
  v_ticket app.tickets;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  select t.* into v_ticket from app.tickets t where t.id = p_ticket_id;
  if not found then
    raise exception 'ticket_not_found: %', p_ticket_id using errcode = 'no_data_found';
  end if;
  if not app.can_access_ticket(p_ticket_id, p_actor_auth_user_id) or app.actor_holds_customer_user_layer(v_ticket.tenant_id, p_actor_auth_user_id) then
    raise exception 'ticket_not_found: %', p_ticket_id using errcode = 'no_data_found';
  end if;
  if v_ticket.channel = 'helpdesk' then
    raise exception 'channel_not_supported: ticket % is a helpdesk case', p_ticket_id using errcode = 'check_violation';
  end if;
  if not app.is_ticket_staff(p_ticket_id, p_actor_auth_user_id) then
    return;
  end if;

  return query
  select s.id, s.reason, s.expires_at, s.suppressed_by, s.revoked_at, s.revoked_by, s.revoked_reason, s.record_version, s.created_at
  from app.ticket_escalation_suppressions s
  where s.ticket_id = p_ticket_id
  order by s.created_at desc;
end;
$$;

-- The breach/stuck queue browser (decision 13) -- staff-scoped per row via
-- app.is_ticket_staff, mirroring app.list_tickets' own can_access_ticket-
-- per-row shape (HRT-286) exactly. Never a blanket "any tenant member sees
-- every escalated ticket" clause.
create function app.list_ticket_breach_queue(p_tenant_id uuid, p_actor_auth_user_id uuid, p_min_level integer, p_limit integer, p_after_id uuid)
returns table (
  ticket_id uuid, ticket_number text, subject text, status text, priority text, queue_code text,
  current_level integer, last_trigger_type text, escalation_status text, last_triggered_at timestamptz, acknowledged_at timestamptz
)
language plpgsql
security definer
set search_path = app, pg_temp
stable
as $$
declare
  v_limit integer := least(greatest(coalesce(p_limit, 50), 1), 200);
  v_after_triggered_at timestamptz;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  if p_after_id is not null then
    select e0.last_triggered_at into v_after_triggered_at from app.ticket_escalations e0 where e0.ticket_id = p_after_id;
  end if;

  return query
  select t.id, t.ticket_number, t.subject, t.status, t.priority, q.code,
    e.current_level, e.last_trigger_type, e.status, e.last_triggered_at, e.acknowledged_at
  from app.ticket_escalations e
  join app.tickets t on t.id = e.ticket_id
  join app.ticket_queues q on q.id = t.queue_id
  where t.tenant_id = p_tenant_id
    and e.status <> 'resolved'
    and app.is_ticket_staff(t.id, p_actor_auth_user_id)
    and (p_min_level is null or e.current_level >= p_min_level)
    and (p_after_id is null or e.last_triggered_at < v_after_triggered_at or (e.last_triggered_at = v_after_triggered_at and t.id < p_after_id))
  order by e.last_triggered_at desc, t.id desc
  limit v_limit;
end;
$$;

comment on function app.list_ticket_breach_queue is
  'HRT-291 (decision 13): a dedicated, minimal breach/stuck-ticket browser -- never a widened app.list_tickets (an already-applied migration this task may never edit in place). Staff-scoped per row (app.is_ticket_staff), cursor-paginated on (last_triggered_at, ticket_id), bounded to 200 rows.';

-- ===========================================================================
-- 15. RLS -- hardened default-deny select policy on every new table
--     (decisions 12/15). Config catalog (policies/versions/levels) is
--     tenant-wide non-customer-visible, mirroring app.ticket_routing_rules/
--     app.sla_policies exactly; per-ticket state/ledger/suppressions are
--     scoped by app.can_access_ticket AND explicitly narrowed against a
--     customer_user-layer actor AND against a helpdesk-channel ticket --
--     applied from the START, learning proactively from HRT-290's own Tier C
--     finding on app.ticket_assignment_events rather than waiting to be
--     found again (decision 15).
-- ===========================================================================

alter table app.ticket_escalation_policies enable row level security;
alter table app.ticket_escalation_policy_versions enable row level security;
alter table app.ticket_escalation_levels enable row level security;
alter table app.ticket_escalations enable row level security;
alter table app.ticket_escalation_events enable row level security;
alter table app.ticket_escalation_suppressions enable row level security;

create policy ticket_escalation_policies_select_scoped on app.ticket_escalation_policies
  for select to authenticated
  using ((app.has_active_tenant_membership(tenant_id) and not app.actor_holds_customer_user_layer(tenant_id)) or app.is_supreme_admin());

create policy ticket_escalation_policy_versions_select_scoped on app.ticket_escalation_policy_versions
  for select to authenticated
  using ((app.has_active_tenant_membership(tenant_id) and not app.actor_holds_customer_user_layer(tenant_id)) or app.is_supreme_admin());

create policy ticket_escalation_levels_select_scoped on app.ticket_escalation_levels
  for select to authenticated
  using ((app.has_active_tenant_membership(tenant_id) and not app.actor_holds_customer_user_layer(tenant_id)) or app.is_supreme_admin());

create policy ticket_escalations_select_scoped on app.ticket_escalations
  for select to authenticated
  using (
    (app.can_access_ticket(ticket_id) and not app.actor_holds_customer_user_layer(tenant_id) and app.ticket_channel_of(ticket_id) <> 'helpdesk')
    or app.is_supreme_admin()
  );

create policy ticket_escalation_events_select_scoped on app.ticket_escalation_events
  for select to authenticated
  using (
    (app.can_access_ticket(ticket_id) and not app.actor_holds_customer_user_layer(tenant_id) and app.ticket_channel_of(ticket_id) <> 'helpdesk')
    or app.is_supreme_admin()
  );

create policy ticket_escalation_suppressions_select_scoped on app.ticket_escalation_suppressions
  for select to authenticated
  using (
    (app.can_access_ticket(ticket_id) and not app.actor_holds_customer_user_layer(tenant_id) and app.ticket_channel_of(ticket_id) <> 'helpdesk')
    or app.is_supreme_admin()
  );

-- ===========================================================================
-- 16. Grants -- explicit, deliberate, never blanket.
-- ===========================================================================

-- ERR-2026-004: Postgres grants EXECUTE to PUBLIC by default on function
-- creation -- every prior HRT ticketing migration carries this exact
-- statement for its own new functions.
revoke execute on all functions in schema app from public;

grant select on app.ticket_escalation_policies to authenticated;
grant select on app.ticket_escalation_policies to service_role;
grant select on app.ticket_escalation_policy_versions to authenticated;
grant select on app.ticket_escalation_policy_versions to service_role;
grant select on app.ticket_escalation_levels to authenticated;
grant select on app.ticket_escalation_levels to service_role;
grant select on app.ticket_escalations to authenticated;
grant select on app.ticket_escalations to service_role;
grant select on app.ticket_escalation_events to authenticated;
grant select on app.ticket_escalation_events to service_role;
grant select on app.ticket_escalation_suppressions to authenticated;
grant select on app.ticket_escalation_suppressions to service_role;

grant execute on function app.create_ticket_escalation_policy(uuid, text, text, uuid, text) to authenticated, service_role;
grant execute on function app.create_ticket_escalation_policy_version(uuid, text, uuid, text, uuid, integer, uuid, text) to authenticated, service_role;
grant execute on function app.add_ticket_escalation_level(uuid, integer, text, integer, text, text, uuid, uuid, boolean, boolean, integer, uuid, text) to authenticated, service_role;
grant execute on function app.publish_ticket_escalation_policy_version(uuid, integer, uuid, text) to authenticated, service_role;
grant execute on function app.preview_ticket_escalation(uuid, text, uuid, text, uuid, uuid) to authenticated, service_role;

grant execute on function app.escalate_ticket(uuid, integer, text, uuid, uuid, boolean, text, uuid, text) to authenticated, service_role;
grant execute on function app.acknowledge_ticket_escalation(uuid, integer, uuid, text) to authenticated, service_role;
grant execute on function app.resolve_ticket_escalation(uuid, integer, text, uuid, text) to authenticated, service_role;
grant execute on function app.suppress_ticket_escalation(uuid, text, timestamptz, uuid, text) to authenticated, service_role;
grant execute on function app.revoke_ticket_escalation_suppression(uuid, uuid, integer, text, uuid, text) to authenticated, service_role;

grant execute on function app.run_ticket_escalation_evaluation_batch(uuid, timestamptz, text, uuid, text) to authenticated, service_role;

grant execute on function app.list_ticket_escalation_policies(uuid, uuid) to authenticated, service_role;
grant execute on function app.list_ticket_escalation_policy_versions(uuid, uuid) to authenticated, service_role;
grant execute on function app.list_ticket_escalation_levels(uuid, uuid) to authenticated, service_role;
grant execute on function app.get_ticket_escalation(uuid, uuid) to authenticated, service_role;
grant execute on function app.get_ticket_escalation_status_for_requester(uuid, uuid) to authenticated, service_role;
grant execute on function app.list_ticket_escalation_events(uuid, uuid) to authenticated, service_role;
grant execute on function app.list_ticket_escalation_suppressions(uuid, uuid) to authenticated, service_role;
grant execute on function app.list_ticket_breach_queue(uuid, uuid, integer, integer, uuid) to authenticated, service_role;

grant execute on function app.ticket_escalation_audit_projection(app.ticket_escalations) to authenticated, service_role;
