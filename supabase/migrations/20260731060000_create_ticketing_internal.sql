-- Phase 7 (HRIS and Ticketing) capability CG-S12-HRT-014 (Internal and
-- Interdepartmental Ticket, Prompt 286) -- the FIRST capability of the separate
-- Ticket workstream (HRT-286..292), and the FOUNDATION every subsequent ticket
-- prompt extends: 287 (Customer-to-Tenant), 288 (Tenant-to-CargoGrid Helpdesk),
-- 289 (SLA/Knowledge Base), 290 (Ticket Assignment), 291 (Escalation), 292
-- (Linked Records). Per 272_HRIS_TICKETING_README.md section 7: "One canonical
-- ticket model supports internal/interdepartmental, customer-to-tenant and
-- tenant-to-CargoGrid helpdesk channels while preserving distinct principal,
-- tenant, customer and support boundaries."
--
-- Design decisions, disclosed rather than left implicit (matching every prior
-- HRT checkpoint's own discipline):
--
-- 1. **Channel extensibility is a pure additive CHECK-widen, never a redesign.**
--    app.tickets.channel is checked against ('internal') ONLY in this migration.
--    Every column this canonical model will ever need for 'customer'/'helpdesk'
--    already exists here (requester identity, queue, category, priority, status,
--    conversation visibility, watchers, attachments, assignee/SLA extension
--    points) because the requester/participant SHAPE is generic -- only the
--    ALLOWED VALUE of `channel` and the identity-resolution path that populates
--    `requester_employee_id` differ per channel. Prompt 287/288 are expected to
--    `alter table app.tickets drop constraint tickets_channel_check, add
--    constraint tickets_channel_check check (channel in ('internal','customer'))`
--    (or `...,'helpdesk')`) in their OWN new migration, plus their own
--    `create or replace function` for a channel-specific creation entry point
--    (e.g. `app.create_customer_ticket`) that calls the SAME shared
--    `app._create_ticket` engine below with a different `p_channel` -- never a
--    second ticket table, never a redesign of this one. This mirrors the exact,
--    precedented "widen the CHECK constraint and the reference table together, in
--    a later migration" pattern `app.jobs.job_type` already used repeatedly
--    (HRT-284 decision 5, its own header).
--
-- 2. **Requester is a Layer 3 tenant user, resolved via the established
--    employee/user link -- never a new identity concept.** `app.tickets.
--    requester_employee_id` is a real FK to `app.employees(master_record_id)`,
--    resolved for self-service creation exclusively via `app.get_self_employee`
--    (HRT-278, reused verbatim, never re-derived) -- there is no
--    `p_requester_employee_id` parameter on the self-service entry point for a
--    caller to spoof (mirrors `app.create_leave_request`'s own "no field to
--    spoof" design, HRT-280 decision 10). An explicit on-behalf entry point,
--    `app.create_ticket_for_employee`, exists separately, gated on `TKT:Edit`
--    (mirrors `app.create_leave_request_for_employee`'s own HRS:Edit-gated
--    split exactly) -- "employees act only for self unless explicit authority"
--    applies to tickets exactly as it already does to leave.
--
-- 3. **Message visibility (requester-visible reply vs. internal note) is a
--    strict enum column, checked at BOTH write time (the RPC) and read time
--    (RLS)** -- never inferred from role, author, or any other signal.
--    `app.ticket_messages.visibility in ('public','internal')` is the single
--    source of truth; `app.ticket_messages_select_scoped`'s own RLS predicate
--    (`visibility = 'public' or app.is_ticket_staff(ticket_id)`) is evaluated on
--    every raw-table read AND is the exact same predicate every read RPC below
--    additionally applies in its own WHERE clause (defense in depth: a
--    SECURITY DEFINER RPC does not automatically inherit RLS, so the RPC's own
--    WHERE clause is the actually-enforcing layer for RPC callers; RLS is what
--    protects a direct `.from("ticket_messages")` PostgREST/supabase-js read).
--    An internal note can therefore never reach a requester-visible read path
--    structurally -- there is no code path, RPC or raw-table, that omits this
--    check.
--
-- 4. **Requester, participant, watcher and queue access are explicit and
--    revocable; department/org_unit membership alone is deliberately NOT
--    sufficient.** `app.ticket_queue_members` is a dedicated, explicit staffing
--    roster (soft-revocable, mirrors `app.talent_pool_members`'s own
--    active/removed shape, HRT-284) -- being a member of the department
--    `app.org_units` node a queue happens to be linked to grants NOTHING by
--    itself; only an explicit `app.add_ticket_queue_member` grant (itself
--    `TKT:Edit`-gated) does. Likewise `app.ticket_watchers` is a dedicated,
--    explicit, revocable grant -- never inferred from org membership,
--    reporting line, or queue staffing.
--
-- 5. **Authority is two independent, both-required dimensions**, mirroring
--    `app.can_access_record`'s (PLT-114) own ownership-vs-permission split:
--    STRUCTURAL SCOPE (is this caller the requester, the assignee, an active
--    watcher, or an active queue member of this ticket's queue? --
--    `app.can_access_ticket`/`app.is_ticket_staff`, reused as the single source
--    of truth by every RLS policy AND every read/write RPC below) decides WHO
--    can see or touch a given ticket at all; RBAC (`TKT:Assign`/`TKT:Close`/
--    `TKT:Reopen`/`TKT:Edit`, evaluated via the standard `app.evaluate_permission`
--    choke point) decides which of the higher-stakes lifecycle actions a
--    structurally-scoped staff member may additionally perform. Plain queue
--    membership (no extra `TKT` permission) is sufficient to read the full
--    thread (including internal notes) and post a reply/internal note --
--    ordinary day-to-day ticket work. Resolving, closing, reopening (staff-side)
--    and assigning each additionally require their own named `TKT` permission
--    (`Close`/`Reopen`/`Assign`, all already seeded at PLT-111,
--    20260716103445:65-67) -- a deliberately higher bar for the more
--    consequential actions (taxonomy C-18: "enumerate every state transition,
--    not just the primary one, and confirm each carries the control its risk
--    warrants"). `TKT:Edit` is reserved for QUEUE/CATEGORY CONFIGURATION and
--    on-behalf ticket creation (administrative actions), not for ordinary
--    ticket work -- so a plain queue member never needs it just to do their job.
--
-- 6. **Status transitions use an explicit, validated, queryable transition
--    graph** (`app.ticket_status_transitions`, a small seeded reference table,
--    never a hidden if/else chain) -- `new -> open -> {pending, on_hold,
--    resolved, cancelled}`, `pending <-> open`, `on_hold <-> open`, `{open,
--    pending, on_hold} -> cancelled`, `resolved -> closed`, `{resolved,
--    closed} -> open` (reopen, incrementing `reopen_count`). `cancelled` is
--    terminal (zero outgoing rows). Every transition is a single, explicit,
--    separately-authorized `app.transition_ticket_status` call -- status is
--    NEVER changed as an implicit side effect of `app.reply_to_ticket` or
--    `app.assign_ticket`, by design: an implicit transition would undermine
--    the very explicitness this section exists to guarantee, and every prior
--    HRT checkpoint's own "no dead action, no hidden side effect" discipline
--    applies here identically.
--
-- 7. **SLA-clock/assignment/escalation extension points are HONESTLY ABSENT,
--    not faked.** `assignee_employee_id` is a real, real column with a real,
--    tested, authority-gated manual `app.assign_ticket` RPC (validated against
--    real queue staffing, never a fake scoring algorithm) -- ownership
--    genuinely progresses, matching section 21's own main-flow language. NO
--    SLA-clock column (target/breach/pause timestamps), NO escalation-path
--    column, and NO auto-routing/eligibility-scoring logic exists anywhere in
--    this migration -- Prompts 289 (SLA)/290 (real assignment
--    eligibility/workload routing)/291 (escalation) own that logic and will add
--    their own columns additively when they land. A column that no code ever
--    populates is a worse trap than an honestly-absent one (a future reader
--    would reasonably assume a populated-looking column is load-bearing) -- so
--    none was added speculatively.
--
-- 8. **Attachments reuse `app.files` directly (PLT-128), never a second file
--    table** -- `document_type_code='ticket_attachment'`, `record_type=
--    'ticket'`, `record_id=<ticket id>`. Re-validated for tenant/record-scope/
--    clean-scan at the ACCEPTING RPC itself (`app.reply_to_ticket`), mirroring
--    `app.attach_training_certificate_evidence`'s (HRT-284) identical two-step
--    shape (upload via `app.initiate_file_upload` first, since the record must
--    exist before a file can be scoped to it for a NEW ticket's own first
--    message -- the same chicken-and-egg reasoning HRT-284's own header
--    documents). `app.ticket_messages.attachment_file_ids` is a `uuid[]`
--    (multiple attachments per message, unlike the single-`evidence_file_id`
--    pattern most other HRT capabilities use, because a support conversation
--    routinely needs more than one file per reply) -- disclosed as a deliberate
--    departure from the single-evidence-file convention, not an oversight.
--
-- 9. **C-24 discipline (unmasked reason/free-text reaching `app.audit_logs`),
--    taken as seriously as HRT-283/284's own recurrence there.** NOT ONE
--    `capture_audit_event` call site in this migration passes a raw `p_*reason`/
--    `p_body` parameter into `p_reason`, and NOT ONE passes `to_jsonb(row)` for
--    `app.tickets` or `app.ticket_messages` -- both carry genuinely sensitive
--    free text (`subject`/`resolution_summary`/`cancelled_reason`/
--    `last_reopen_reason` on tickets; `body` itself, by definition, on
--    messages -- an internal note or a reply can contain anything a real
--    support conversation contains). `app.ticket_audit_projection()` is an
--    explicit, allowlisted structural-fields-only projection (id, tenant_id,
--    ticket_number, channel, category_id, queue_id, priority, status,
--    requester_employee_id, assignee_employee_id, record_version,
--    reopen_count -- deliberately excluding every free-text column), mirroring
--    `app.leave_request_audit_projection`'s (HRT-280) exact discipline. Every
--    ticket-message audit call logs structural metadata only (message id,
--    ticket id, visibility, attachment_count, is_redacted) -- never `body`,
--    not even on redaction (the whole point of `app.redact_ticket_message` is
--    that the removed text does not persist anywhere else queryable, including
--    `app.audit_logs`, which is readable by any tenant's own plain
--    `tenant_admin` -- a materially broader bar than this capability's own
--    `TKT:*` gates). `app.ticket_events` (the ticket-scoped status/assignment/
--    transfer/classification history) is DELIBERATELY DIFFERENT: it is governed
--    by the exact same RLS as the ticket itself (`app.can_access_ticket`), so
--    storing the real transition `reason` there carries no broader-audience
--    exposure than the ticket already has -- unlike `app.audit_logs`, which is
--    NOT scoped to ticket participants.
--
-- 10. **Concurrency**: every write RPC below `select ... for update` locks the
--     target row before deciding, checks authority BEFORE record_version (never
--     discloses a real record_version to an unauthorized caller), and repeats
--     `record_version = p_expected_version` in the terminal UPDATE's own WHERE
--     clause as a second, belt-and-suspenders guard beyond the row lock,
--     mirroring HRT-274's own established shape verbatim. Every check-then-
--     insert idempotency path (ticket creation, message creation, queue/
--     category creation, watcher/queue-member addition) wraps its INSERT in a
--     REAL `exception when unique_violation` handler, per this task's own
--     explicit C-01 mandate ("need a real exception handler, not just a
--     pre-check") -- not merely a pre-check `select` (the exact gap this task's
--     own mandatory reading flagged as still-open in sibling HRIS migrations
--     that predate this instruction).
--
-- 11. **C-02 discipline (ambiguous bare `id` against a `RETURNS TABLE` output
--     column)** -- every `returns table (id uuid, ...)` function below
--     source-aliases every table it selects from and NEVER writes a bare
--     `where id = ...`; every internal single-row lookup uses an explicit
--     alias (`t.id`, `m.id`, `q.id`, ...). This exact class made 7 RPCs 100%
--     non-functional in the immediately-preceding HRT-283/284 batch.
--
-- 12. **Requester/queue/watcher/staff reporting ("managers see scoped reports",
--     section 26) is DELIBERATELY NOT BUILT this prompt** -- disclosed, not
--     silently dropped (taxonomy C-23). `app.can_access_ticket` grants full
--     tenant-wide ticket visibility to a `TKT:Edit` holder (service admin) and
--     to actual queue staff/requester/watcher/assignee, but there is
--     deliberately NO blanket "any `TKT:View` holder sees every ticket"
--     clause -- an aggregate, cross-queue MANAGER reporting view (counts/
--     trends without raw per-ticket detail) is a genuinely different,
--     dashboard-shaped capability this foundational prompt does not build; a
--     future ticket-reporting capability can add it without touching this
--     schema. Building a narrow "sees everything via View" shortcut instead
--     would have been the wrong trade -- it would have made the isolation
--     model this prompt exists to prove untestable (an "unrelated employee"
--     holding a routine, broad `TKT:View` grant would then see every ticket
--     regardless of queue/participation).

-- ===========================================================================
-- 1. Document-type registration (decision 8) -- migration-apply context has no
--    live actor session, so this mirrors app.employees' own direct-INSERT
--    'employee_document' convention (HRT-274) rather than calling the
--    Supreme-Admin-gated app.register_document_type().
-- ===========================================================================

insert into app.document_types (code, name, owner_primitive_code, registered_by)
values ('ticket_attachment', 'Ticket Attachment', 'TKT', 'system')
on conflict (code) do nothing;

insert into app.config_types (code, name, owner_primitive_code, registered_by)
values ('document:ticket_attachment', 'Ticket Attachment', 'TKT', 'system')
on conflict (code) do nothing;

-- ===========================================================================
-- 2. Ticket numbering -- mirrors app.next_employee_number (HRT-274) exactly.
-- ===========================================================================

create table app.ticket_number_counters (
  tenant_id uuid primary key references app.tenants (id),
  last_seq integer not null default 0
);

create function app.next_ticket_number(p_tenant_id uuid)
returns text
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_seq integer;
begin
  insert into app.ticket_number_counters (tenant_id, last_seq)
  values (p_tenant_id, 1)
  on conflict (tenant_id) do update set last_seq = app.ticket_number_counters.last_seq + 1
  returning last_seq into v_seq;

  return 'TKT-' || to_char(now(), 'YYYY') || '-' || lpad(v_seq::text, 6, '0');
end;
$$;

comment on function app.next_ticket_number is
  'HRT-286: internal-only (no authenticated grant) -- called exclusively from app._create_ticket below. Fixed default format, mirrors app.next_employee_number (HRT-274) exactly.';

-- ===========================================================================
-- 3. Shared record_version-bump trigger (mirrors app.touch_training_row,
--    HRT-284).
-- ===========================================================================

create function app.touch_ticket_row()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  new.record_version := old.record_version + 1;
  return new;
end;
$$;

comment on function app.touch_ticket_row is
  'HRT-286: shared record_version-bump trigger for every versioned table below, mirroring app.touch_training_row (HRT-284) / app.touch_org_unit_row (PLT-109) -- reused, never reimplemented per-table.';

-- ===========================================================================
-- 4. Catalog: ticket queues (decision 4/"department scope is explicit") --
--    each queue is linked to a real app.org_units node.
-- ===========================================================================

create table app.ticket_queues (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  org_unit_id uuid not null references app.org_units (id),
  code text not null,
  name text not null,
  description text,
  status text not null default 'active',
  record_version integer not null default 1,
  created_by text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint ticket_queues_status_check check (status in ('active', 'inactive')),
  constraint ticket_queues_code_check check (length(trim(code)) > 0),
  constraint ticket_queues_name_check check (length(trim(name)) > 0),
  constraint ticket_queues_code_unique unique (tenant_id, code)
);

comment on table app.ticket_queues is
  'HRT-286: department/team ticket queue, linked to a real app.org_units node (decision 4, "department scope is explicit"). Any org_unit type is accepted (company/branch/department/business_unit) -- a queue may be scoped broader than one department.';

create index ticket_queues_tenant_status_idx on app.ticket_queues (tenant_id, status);
create index ticket_queues_org_unit_idx on app.ticket_queues (org_unit_id);

create trigger ticket_queues_touch before update on app.ticket_queues
  for each row execute function app.touch_ticket_row();

create table app.ticket_categories (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  code text not null,
  name text not null,
  default_queue_id uuid references app.ticket_queues (id),
  status text not null default 'active',
  record_version integer not null default 1,
  created_by text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint ticket_categories_status_check check (status in ('active', 'inactive')),
  constraint ticket_categories_code_check check (length(trim(code)) > 0),
  constraint ticket_categories_name_check check (length(trim(name)) > 0),
  constraint ticket_categories_code_unique unique (tenant_id, code)
);

comment on table app.ticket_categories is
  'HRT-286: ticket category catalog. default_queue_id lets a caller create a ticket without explicitly naming a queue -- app._create_ticket resolves p_queue_id, falling back to the category''s own default_queue_id, raising if neither is present.';

create index ticket_categories_tenant_status_idx on app.ticket_categories (tenant_id, status);

create trigger ticket_categories_touch before update on app.ticket_categories
  for each row execute function app.touch_ticket_row();

-- Explicit, revocable queue staffing roster (decision 4) -- department/
-- org_unit membership alone grants NOTHING; only an active row here does.
create table app.ticket_queue_members (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  queue_id uuid not null references app.ticket_queues (id),
  employee_id uuid not null references app.employees (master_record_id),
  status text not null default 'active',
  added_by text,
  added_at timestamptz not null default now(),
  removed_by text,
  removed_at timestamptz,
  removed_reason text,
  record_version integer not null default 1,
  updated_at timestamptz not null default now(),
  constraint ticket_queue_members_status_check check (status in ('active', 'removed'))
);

comment on table app.ticket_queue_members is
  'HRT-286: explicit, revocable queue staffing roster (decision 4/5). Soft-revoked (status=removed), mirrors app.talent_pool_members (HRT-284) exactly -- never hard-deleted. Being a member here is what grants both ticket visibility (app.can_access_ticket) AND ordinary ticket-work authority (reply/transfer/classify) for this queue''s tickets -- no separate TKT permission is required beyond this explicit grant for routine work; the higher-stakes actions (assign/resolve/close/reopen) additionally require their own named TKT permission (decision 5).';

create index ticket_queue_members_queue_idx on app.ticket_queue_members (queue_id, status);
create index ticket_queue_members_tenant_employee_idx on app.ticket_queue_members (tenant_id, employee_id);
create unique index ticket_queue_members_active_unique on app.ticket_queue_members (queue_id, employee_id) where status = 'active';

create trigger ticket_queue_members_touch before update on app.ticket_queue_members
  for each row execute function app.touch_ticket_row();

-- ===========================================================================
-- 5. Explicit, validated ticket status transition graph (decision 6) -- a
--    real, queryable reference table, never a hidden if/else chain.
--    Tenant-independent (a structural catalog, like app.document_types).
-- ===========================================================================

create table app.ticket_status_transitions (
  from_status text not null,
  to_status text not null,
  requires_reason boolean not null default false,
  requester_allowed boolean not null default false,
  primary key (from_status, to_status)
);

comment on table app.ticket_status_transitions is
  'HRT-286 (decision 6): the canonical, explicit ticket lifecycle graph. app.transition_ticket_status looks up (from_status, to_status) here and rejects any pair with no matching row -- an invalid jump is structurally impossible, not merely discouraged. requester_allowed marks the transitions the ticket''s own requester may perform without any TKT permission (cancel, reopen); every other transition requires app.is_ticket_staff plus, for the higher-stakes targets, a named TKT permission (see app._ticket_transition_authority). ''cancelled'' is terminal by construction -- zero rows have from_status=''cancelled''.';

insert into app.ticket_status_transitions (from_status, to_status, requires_reason, requester_allowed) values
  ('new', 'open', false, false),
  ('new', 'cancelled', true, true),
  ('open', 'pending', false, false),
  ('open', 'on_hold', true, false),
  ('open', 'resolved', true, false),
  ('open', 'cancelled', true, true),
  ('pending', 'open', false, true),
  ('pending', 'resolved', true, false),
  ('pending', 'on_hold', true, false),
  ('pending', 'cancelled', true, true),
  ('on_hold', 'open', false, false),
  ('on_hold', 'cancelled', true, true),
  ('resolved', 'closed', false, false),
  ('resolved', 'open', true, true),
  ('closed', 'open', true, true);

-- ===========================================================================
-- 6. app.tickets -- the canonical ticket record (decisions 1/2/7).
-- ===========================================================================

create table app.tickets (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  ticket_number text not null,
  channel text not null default 'internal',
  category_id uuid not null references app.ticket_categories (id),
  queue_id uuid not null references app.ticket_queues (id),
  priority text not null default 'normal',
  subject text not null,
  status text not null default 'new',
  requester_employee_id uuid not null references app.employees (master_record_id),
  requested_by_auth_user_id uuid not null,
  requested_by text,
  assignee_employee_id uuid references app.employees (master_record_id),
  assigned_by text,
  assigned_at timestamptz,
  resolution_summary text,
  resolved_by text,
  resolved_at timestamptz,
  closed_by text,
  closed_at timestamptz,
  cancelled_reason text,
  cancelled_by text,
  cancelled_at timestamptz,
  reopen_count integer not null default 0,
  last_reopened_by text,
  last_reopened_at timestamptz,
  last_reopen_reason text,
  idempotency_key text,
  record_version integer not null default 1,
  created_by text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint tickets_channel_check check (channel in ('internal')),
  constraint tickets_priority_check check (priority in ('low', 'normal', 'high', 'urgent')),
  constraint tickets_status_check check (status in ('new', 'open', 'pending', 'on_hold', 'resolved', 'closed', 'cancelled')),
  constraint tickets_subject_check check (length(trim(subject)) > 0),
  constraint tickets_ticket_number_unique unique (tenant_id, ticket_number),
  constraint tickets_resolved_requires_summary check (status <> 'resolved' or resolution_summary is not null),
  constraint tickets_cancelled_requires_reason check (status <> 'cancelled' or cancelled_reason is not null),
  constraint tickets_reopen_count_check check (reopen_count >= 0)
);

comment on table app.tickets is
  'HRT-286: the ONE canonical ticket model for every channel (decision 1). channel is checked against (''internal'') only in this migration -- 287/288 widen the CHECK constraint additively, never a redesign. requester_employee_id is a real app.employees FK (decision 2) -- Layer 3 tenant user, resolved via app.get_self_employee for self-service creation, never a spoofable parameter. assignee_employee_id is a real, tested manual-assignment extension point (decision 7); no SLA-clock or escalation column exists anywhere on this table (decision 7, honestly absent).';

-- Backs _create_ticket's own idempotency exception handler (decision 10) --
-- live-reproduced as CRITICAL without this index: two genuinely concurrent
-- create_ticket calls with the identical idempotency key both passed the
-- pre-insert SELECT (neither had committed yet) and both INSERTs succeeded
-- independently, producing two separate tickets with zero constraint to
-- violate and zero exception to catch. Confirmed fixed by two real,
-- concurrent OS psql processes after this index was added.
create unique index tickets_idempotency_unique on app.tickets (tenant_id, requester_employee_id, idempotency_key) where idempotency_key is not null;

create index tickets_tenant_status_idx on app.tickets (tenant_id, status);
create index tickets_tenant_queue_idx on app.tickets (tenant_id, queue_id, status);
create index tickets_tenant_category_idx on app.tickets (tenant_id, category_id);
create index tickets_tenant_priority_idx on app.tickets (tenant_id, priority);
create index tickets_requester_idx on app.tickets (tenant_id, requester_employee_id);
create index tickets_assignee_idx on app.tickets (tenant_id, assignee_employee_id) where assignee_employee_id is not null;
create index tickets_tenant_updated_idx on app.tickets (tenant_id, updated_at desc);
create index tickets_created_at_idx on app.tickets (created_at desc, id desc);

create trigger tickets_touch before update on app.tickets
  for each row execute function app.touch_ticket_row();

-- ===========================================================================
-- 7. app.ticket_messages -- the conversation, with a strict, server-enforced
--    visibility distinction (decision 3).
-- ===========================================================================

create table app.ticket_messages (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  ticket_id uuid not null references app.tickets (id),
  visibility text not null default 'public',
  body text not null,
  attachment_file_ids uuid[] not null default '{}'::uuid[],
  author_auth_user_id uuid not null,
  author_label text,
  author_role text not null,
  is_redacted boolean not null default false,
  redacted_at timestamptz,
  redacted_by text,
  redacted_reason text,
  idempotency_key text,
  record_version integer not null default 1,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint ticket_messages_visibility_check check (visibility in ('public', 'internal')),
  constraint ticket_messages_body_check check (length(trim(body)) > 0),
  constraint ticket_messages_author_role_check check (author_role in ('requester', 'staff')),
  constraint ticket_messages_redacted_shape_check check (not is_redacted or (redacted_at is not null and redacted_reason is not null))
);

comment on table app.ticket_messages is
  'HRT-286 (decision 3): visibility is a strict, closed enum -- public (requester-visible reply) or internal (staff-only note) -- checked at write time (app.reply_to_ticket) and read time (RLS + every read RPC''s own identical WHERE predicate), never inferred from author or role. Redaction (app.redact_ticket_message) overwrites body in place and never persists the original text anywhere else queryable, including app.audit_logs (decision 9) -- normal roles cannot un-redact; Supreme Admin''s standing absolute-CRUD exception (RPD-022) is unchanged and already disclosed platform-wide.';

create index ticket_messages_ticket_idx on app.ticket_messages (ticket_id, created_at asc);
create unique index ticket_messages_idempotency_unique on app.ticket_messages (tenant_id, ticket_id, idempotency_key) where idempotency_key is not null;

create trigger ticket_messages_touch before update on app.ticket_messages
  for each row execute function app.touch_ticket_row();

-- ===========================================================================
-- 8. app.ticket_watchers -- explicit, revocable watcher grant (decision 4).
-- ===========================================================================

create table app.ticket_watchers (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  ticket_id uuid not null references app.tickets (id),
  employee_id uuid not null references app.employees (master_record_id),
  status text not null default 'active',
  added_by text,
  added_at timestamptz not null default now(),
  removed_by text,
  removed_at timestamptz,
  record_version integer not null default 1,
  updated_at timestamptz not null default now(),
  constraint ticket_watchers_status_check check (status in ('active', 'removed'))
);

comment on table app.ticket_watchers is
  'HRT-286 (decision 4): explicit, revocable ticket watcher grant. Soft-revoked, never hard-deleted. A watcher gains read access to the ticket (app.can_access_ticket) but NOT staff status (app.is_ticket_staff) merely by watching -- watching is a participation grant, not a queue-staffing grant.';

create index ticket_watchers_ticket_idx on app.ticket_watchers (ticket_id, status);
create index ticket_watchers_tenant_employee_idx on app.ticket_watchers (tenant_id, employee_id);
create unique index ticket_watchers_active_unique on app.ticket_watchers (ticket_id, employee_id) where status = 'active';

create trigger ticket_watchers_touch before update on app.ticket_watchers
  for each row execute function app.touch_ticket_row();

-- ===========================================================================
-- 9. app.ticket_events -- append-only status/assignment/transfer/
--    classification/watcher history. Governed by the SAME RLS as the ticket
--    itself (decision 9) -- deliberately NOT app.audit_logs, whose readership
--    is broader (any plain tenant_admin).
-- ===========================================================================

create table app.ticket_events (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  ticket_id uuid not null references app.tickets (id),
  event_type text not null,
  from_value text,
  to_value text,
  reason text,
  actor_auth_user_id uuid,
  actor_label text,
  occurred_at timestamptz not null default now(),
  constraint ticket_events_event_type_check check (event_type in (
    'create', 'status_change', 'assignment', 'queue_transfer', 'classification_change',
    'watcher_added', 'watcher_removed', 'message_redacted'
  ))
);

comment on table app.ticket_events is
  'HRT-286: append-only ticket lifecycle history, scoped by the exact same RLS as app.tickets (app.can_access_ticket) -- unlike app.audit_logs, this table''s readership never exceeds the ticket''s own participant/queue-staff/service-admin population, so it may safely carry the real transition reason text (decision 9).';

create index ticket_events_ticket_idx on app.ticket_events (ticket_id, occurred_at asc);

-- ===========================================================================
-- 10. Authority/scope helper functions (decision 5) -- the SINGLE source of
--     truth every RLS policy AND every RPC below reuses, never duplicated.
-- ===========================================================================

create function app.check_ticket_authority(p_action text, p_tenant_id uuid, p_actor_auth_user_id uuid)
returns boolean
language sql
stable
security definer
set search_path = app, pg_temp
as $$
  select (app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'TKT', p_action)).allowed;
$$;

comment on function app.check_ticket_authority is
  'HRT-286: SECURITY DEFINER wrapper over app.evaluate_permission(..., ''TKT'', ...) -- mirrors app.check_training_authority (HRT-284) exactly, so RLS policies can evaluate TKT authority without granting authenticated direct access to app.permissions/app.role_version_permissions.';

create function app.is_ticket_queue_member(p_queue_id uuid, p_auth_user_id uuid default auth.uid())
returns boolean
language sql
stable
security definer
set search_path = app, pg_temp
as $$
  select exists (
    select 1
    from app.ticket_queue_members m
    join app.employees e on e.master_record_id = m.employee_id
    join app.users u on u.id = e.user_id
    where m.queue_id = p_queue_id
      and m.status = 'active'
      and u.auth_user_id = p_auth_user_id
  );
$$;

comment on function app.is_ticket_queue_member is
  'HRT-286: true if the caller has an active app.ticket_queue_members row for this queue, resolved via the established employee/user link (app.employees.user_id -> app.users.auth_user_id) -- never a second identity mechanism.';

create function app.is_ticket_staff(p_ticket_id uuid, p_auth_user_id uuid default auth.uid())
returns boolean
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_ticket app.tickets;
  v_self app.employees;
begin
  select * into v_ticket from app.tickets where id = p_ticket_id;
  if not found then
    return false;
  end if;
  if app.is_supreme_admin(p_auth_user_id) then
    return true;
  end if;
  if app.check_ticket_authority('Edit', v_ticket.tenant_id, p_auth_user_id) then
    return true;
  end if;
  v_self := app.get_self_employee(v_ticket.tenant_id, p_auth_user_id);
  if v_self.master_record_id is not null and v_self.master_record_id = v_ticket.assignee_employee_id then
    return true;
  end if;
  return app.is_ticket_queue_member(v_ticket.queue_id, p_auth_user_id);
end;
$$;

comment on function app.is_ticket_staff is
  'HRT-286 (decision 5): true if the caller is Supreme Admin, holds TKT:Edit (service admin, tenant-wide), is the ticket''s own assignee, or is an active member of the ticket''s queue. Governs internal-note visibility/posting and ordinary staff-side ticket work. Used directly by RLS (app.ticket_messages_select_scoped) and by every write RPC below.';

create function app.can_access_ticket(p_ticket_id uuid, p_auth_user_id uuid default auth.uid())
returns boolean
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_ticket app.tickets;
  v_self app.employees;
begin
  select * into v_ticket from app.tickets where id = p_ticket_id;
  if not found then
    return false;
  end if;
  if app.is_ticket_staff(p_ticket_id, p_auth_user_id) then
    return true;
  end if;
  v_self := app.get_self_employee(v_ticket.tenant_id, p_auth_user_id);
  if v_self.master_record_id is not null and v_self.master_record_id = v_ticket.requester_employee_id then
    return true;
  end if;
  return exists (
    select 1
    from app.ticket_watchers w
    join app.employees e on e.master_record_id = w.employee_id
    join app.users u on u.id = e.user_id
    where w.ticket_id = p_ticket_id
      and w.status = 'active'
      and u.auth_user_id = p_auth_user_id
  );
end;
$$;

comment on function app.can_access_ticket is
  'HRT-286 (decision 5, section 26): true if the caller is ticket staff (app.is_ticket_staff), the ticket''s own requester, or an active watcher. Deliberately NO blanket "any TKT:View holder sees every ticket" clause (decision 12, disclosed) -- structural scope is what grants access, not a permission alone. The single predicate every RLS SELECT policy on tickets/messages/watchers/events AND every list/get RPC''s own WHERE clause reuses -- never re-derived.';

create function app.ticket_audit_projection(p_ticket app.tickets)
returns jsonb
language sql
immutable
as $$
  select jsonb_build_object(
    'id', p_ticket.id,
    'tenant_id', p_ticket.tenant_id,
    'ticket_number', p_ticket.ticket_number,
    'channel', p_ticket.channel,
    'category_id', p_ticket.category_id,
    'queue_id', p_ticket.queue_id,
    'priority', p_ticket.priority,
    'status', p_ticket.status,
    'requester_employee_id', p_ticket.requester_employee_id,
    'assignee_employee_id', p_ticket.assignee_employee_id,
    'record_version', p_ticket.record_version,
    'reopen_count', p_ticket.reopen_count
  );
$$;

comment on function app.ticket_audit_projection is
  'HRT-286 (decision 9, C-24 discipline): explicit structural-fields-only allowlist for app.tickets audit before/after values -- deliberately excludes subject/resolution_summary/cancelled_reason/last_reopen_reason (free text). Never to_jsonb(row). Mirrors app.leave_request_audit_projection (HRT-280) exactly.';

-- ===========================================================================
-- 11. Queue/category configuration RPCs -- TKT:Edit-gated (decision 5).
-- ===========================================================================

create function app.create_ticket_queue(
  p_tenant_id uuid, p_org_unit_id uuid, p_code text, p_name text, p_description text,
  p_actor_auth_user_id uuid, p_actor_label text
)
returns app.ticket_queues
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_org_unit app.org_units;
  v_existing app.ticket_queues;
  v_queue app.ticket_queues;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'TKT', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks TKT:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if p_code is null or length(trim(p_code)) = 0 then
    raise exception 'code_required: a non-empty code is required' using errcode = 'check_violation';
  end if;
  if p_name is null or length(trim(p_name)) = 0 then
    raise exception 'name_required: a non-empty name is required' using errcode = 'check_violation';
  end if;

  select * into v_org_unit from app.org_units where id = p_org_unit_id and tenant_id = p_tenant_id;
  if not found then
    raise exception 'org_unit_not_found: % is not a valid org unit for tenant %', p_org_unit_id, p_tenant_id using errcode = 'no_data_found';
  end if;

  select * into v_existing from app.ticket_queues where tenant_id = p_tenant_id and code = p_code;
  if found then
    return v_existing;
  end if;

  begin
    insert into app.ticket_queues (tenant_id, org_unit_id, code, name, description, created_by)
    values (p_tenant_id, p_org_unit_id, p_code, p_name, p_description, p_actor_label)
    returning * into v_queue;
  exception
    when unique_violation then
      select * into v_queue from app.ticket_queues where tenant_id = p_tenant_id and code = p_code;
      if not found then
        raise;
      end if;
  end;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'create_ticket_queue',
    'app.ticket_queues', v_queue.id, 'success', null, null, jsonb_build_object('code', v_queue.code, 'org_unit_id', v_queue.org_unit_id)
  );

  return v_queue;
end;
$$;

create function app.create_ticket_category(
  p_tenant_id uuid, p_code text, p_name text, p_default_queue_id uuid, p_actor_auth_user_id uuid, p_actor_label text
)
returns app.ticket_categories
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_existing app.ticket_categories;
  v_category app.ticket_categories;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'TKT', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks TKT:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if p_code is null or length(trim(p_code)) = 0 then
    raise exception 'code_required: a non-empty code is required' using errcode = 'check_violation';
  end if;
  if p_name is null or length(trim(p_name)) = 0 then
    raise exception 'name_required: a non-empty name is required' using errcode = 'check_violation';
  end if;

  if p_default_queue_id is not null and not exists (
    select 1 from app.ticket_queues where id = p_default_queue_id and tenant_id = p_tenant_id
  ) then
    raise exception 'ticket_queue_not_found: % is not a valid queue for tenant %', p_default_queue_id, p_tenant_id using errcode = 'no_data_found';
  end if;

  select * into v_existing from app.ticket_categories where tenant_id = p_tenant_id and code = p_code;
  if found then
    return v_existing;
  end if;

  begin
    insert into app.ticket_categories (tenant_id, code, name, default_queue_id, created_by)
    values (p_tenant_id, p_code, p_name, p_default_queue_id, p_actor_label)
    returning * into v_category;
  exception
    when unique_violation then
      select * into v_category from app.ticket_categories where tenant_id = p_tenant_id and code = p_code;
      if not found then
        raise;
      end if;
  end;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'create_ticket_category',
    'app.ticket_categories', v_category.id, 'success', null, null, jsonb_build_object('code', v_category.code, 'default_queue_id', v_category.default_queue_id)
  );

  return v_category;
end;
$$;

create function app.add_ticket_queue_member(p_queue_id uuid, p_employee_id uuid, p_actor_auth_user_id uuid, p_actor_label text)
returns app.ticket_queue_members
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_queue app.ticket_queues;
  v_row app.ticket_queue_members;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  select * into v_queue from app.ticket_queues where id = p_queue_id;
  if not found then
    raise exception 'ticket_queue_not_found: %', p_queue_id using errcode = 'no_data_found';
  end if;
  if not app.check_ticket_authority('Edit', v_queue.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks TKT:Edit for tenant %', p_actor_auth_user_id, v_queue.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not exists (select 1 from app.employees e where e.master_record_id = p_employee_id and e.tenant_id = v_queue.tenant_id) then
    raise exception 'employee_not_found: %', p_employee_id using errcode = 'no_data_found';
  end if;

  select * into v_row from app.ticket_queue_members where queue_id = p_queue_id and employee_id = p_employee_id and status = 'active';
  if found then
    return v_row;
  end if;

  begin
    insert into app.ticket_queue_members (tenant_id, queue_id, employee_id, added_by)
    values (v_queue.tenant_id, p_queue_id, p_employee_id, p_actor_label)
    returning * into v_row;
  exception
    when unique_violation then
      select * into v_row from app.ticket_queue_members where queue_id = p_queue_id and employee_id = p_employee_id and status = 'active';
      if not found then
        raise;
      end if;
  end;

  perform app.capture_audit_event(
    v_queue.tenant_id, p_actor_auth_user_id, p_actor_label, 'add_ticket_queue_member',
    'app.ticket_queue_members', v_row.id, 'success', null, null, jsonb_build_object('queue_id', p_queue_id, 'employee_id', p_employee_id)
  );

  return v_row;
end;
$$;

create function app.remove_ticket_queue_member(p_member_id uuid, p_expected_version integer, p_reason text, p_actor_auth_user_id uuid, p_actor_label text)
returns app.ticket_queue_members
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_row app.ticket_queue_members;
  v_tenant_id uuid;
  v_updated app.ticket_queue_members;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  select * into v_row from app.ticket_queue_members where id = p_member_id for update;
  if not found then
    raise exception 'ticket_queue_member_not_found: %', p_member_id using errcode = 'no_data_found';
  end if;
  v_tenant_id := v_row.tenant_id;
  if not app.check_ticket_authority('Edit', v_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks TKT:Edit for tenant %', p_actor_auth_user_id, v_tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if v_row.record_version <> p_expected_version then
    raise exception 'stale_version: expected version % but current version is %', p_expected_version, v_row.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_row.status <> 'active' then
    raise exception 'invalid_transition: member % is % not active', p_member_id, v_row.status using errcode = 'check_violation';
  end if;

  update app.ticket_queue_members set status = 'removed', removed_by = p_actor_label, removed_at = now(), removed_reason = p_reason
  where id = p_member_id and record_version = p_expected_version
  returning * into v_updated;
  if not found then
    raise exception 'stale_version: concurrent update detected for ticket queue member %', p_member_id using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_tenant_id, p_actor_auth_user_id, p_actor_label, 'remove_ticket_queue_member',
    'app.ticket_queue_members', v_updated.id, 'success', null, null, jsonb_build_object('queue_id', v_updated.queue_id, 'employee_id', v_updated.employee_id)
  );

  return v_updated;
end;
$$;

-- ===========================================================================
-- 12. Ticket creation -- shared engine + two entry points (decision 2).
-- ===========================================================================

create function app._create_ticket(
  p_tenant_id uuid, p_requester_employee_id uuid, p_category_id uuid, p_queue_id uuid, p_priority text,
  p_subject text, p_body text, p_idempotency_key text, p_actor_auth_user_id uuid, p_actor_label text
)
returns app.tickets
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_category app.ticket_categories;
  v_resolved_queue_id uuid;
  v_priority text := coalesce(p_priority, 'normal');
  v_existing app.tickets;
  v_existing_body text;
  v_ticket app.tickets;
  v_number text;
begin
  if p_subject is null or length(trim(p_subject)) = 0 then
    raise exception 'subject_required: a non-empty subject is required' using errcode = 'check_violation';
  end if;
  if p_body is null or length(trim(p_body)) = 0 then
    raise exception 'body_required: a non-empty ticket description is required' using errcode = 'check_violation';
  end if;
  if not (v_priority = any (array['low', 'normal', 'high', 'urgent'])) then
    raise exception 'invalid_priority: % is not one of low/normal/high/urgent', v_priority using errcode = 'check_violation';
  end if;

  select * into v_category from app.ticket_categories where id = p_category_id and tenant_id = p_tenant_id and status = 'active';
  if not found then
    raise exception 'category_not_available: % is not an active category for this tenant', p_category_id using errcode = 'no_data_found';
  end if;

  v_resolved_queue_id := coalesce(p_queue_id, v_category.default_queue_id);
  if v_resolved_queue_id is null then
    raise exception 'queue_required: no queue was supplied and category % has no default queue', p_category_id using errcode = 'check_violation';
  end if;
  if not exists (select 1 from app.ticket_queues where id = v_resolved_queue_id and tenant_id = p_tenant_id and status = 'active') then
    raise exception 'queue_not_available: % is not an active queue for this tenant', v_resolved_queue_id using errcode = 'no_data_found';
  end if;

  if p_idempotency_key is not null then
    select * into v_existing from app.tickets
    where tenant_id = p_tenant_id and requester_employee_id = p_requester_employee_id and idempotency_key = p_idempotency_key;
    if found then
      select m.body into v_existing_body from app.ticket_messages m where m.ticket_id = v_existing.id order by m.created_at asc limit 1;
      if v_existing.category_id = p_category_id and v_existing.queue_id = v_resolved_queue_id and v_existing.priority = v_priority
         and v_existing.subject = p_subject and coalesce(v_existing_body, '') = p_body then
        return v_existing;
      else
        raise exception 'idempotency_key_conflict: key % was already used for a different ticket', p_idempotency_key using errcode = 'unique_violation';
      end if;
    end if;
  end if;

  v_number := app.next_ticket_number(p_tenant_id);

  begin
    insert into app.tickets (
      tenant_id, ticket_number, category_id, queue_id, priority, subject, status,
      requester_employee_id, requested_by_auth_user_id, requested_by, idempotency_key, created_by
    ) values (
      p_tenant_id, v_number, p_category_id, v_resolved_queue_id, v_priority, p_subject, 'new',
      p_requester_employee_id, p_actor_auth_user_id, p_actor_label, p_idempotency_key, p_actor_label
    )
    returning * into v_ticket;
  exception
    when unique_violation then
      if p_idempotency_key is not null then
        select * into v_ticket from app.tickets
        where tenant_id = p_tenant_id and requester_employee_id = p_requester_employee_id and idempotency_key = p_idempotency_key;
        if found then
          select m.body into v_existing_body from app.ticket_messages m where m.ticket_id = v_ticket.id order by m.created_at asc limit 1;
          if v_ticket.category_id = p_category_id and v_ticket.queue_id = v_resolved_queue_id and v_ticket.priority = v_priority
             and v_ticket.subject = p_subject and coalesce(v_existing_body, '') = p_body then
            return v_ticket;
          end if;
        end if;
      end if;
      raise;
  end;

  insert into app.ticket_messages (tenant_id, ticket_id, visibility, body, author_auth_user_id, author_label, author_role)
  values (p_tenant_id, v_ticket.id, 'public', p_body, p_actor_auth_user_id, p_actor_label, 'requester');

  insert into app.ticket_events (tenant_id, ticket_id, event_type, from_value, to_value, actor_auth_user_id, actor_label)
  values (p_tenant_id, v_ticket.id, 'create', null, 'new', p_actor_auth_user_id, p_actor_label);

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'create_ticket',
    'app.tickets', v_ticket.id, 'success', null, null, app.ticket_audit_projection(v_ticket)
  );

  return v_ticket;
end;
$$;

comment on function app._create_ticket is
  'HRT-286 (decision 1): the ONE shared ticket-creation engine both app.create_ticket and app.create_ticket_for_employee call -- never two independently-validated write paths. Inserts the ticket AND its own opening ticket_messages row (visibility=public, author_role=requester) in one transaction -- the "first message IS the ticket body" canonical shape, so there is no separate description column to keep in sync. channel is hardcoded ''internal'' at the column default; future channel entry points call this same engine (decision 1).';

create function app.create_ticket(
  p_tenant_id uuid, p_category_id uuid, p_queue_id uuid, p_priority text, p_subject text, p_body text,
  p_idempotency_key text, p_actor_auth_user_id uuid, p_actor_label text
)
returns app.tickets
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_self app.employees;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  if not app.has_active_tenant_membership(p_tenant_id, p_actor_auth_user_id) then
    raise exception 'employee_not_found: no linked employee profile' using errcode = 'no_data_found';
  end if;
  v_self := app.get_self_employee(p_tenant_id, p_actor_auth_user_id);
  if v_self.master_record_id is null then
    raise exception 'employee_not_found: no linked employee profile' using errcode = 'no_data_found';
  end if;
  return app._create_ticket(p_tenant_id, v_self.master_record_id, p_category_id, p_queue_id, p_priority, p_subject, p_body, p_idempotency_key, p_actor_auth_user_id, p_actor_label);
end;
$$;

comment on function app.create_ticket is
  'HRT-286 (decision 2): self-service creation -- no p_requester_employee_id parameter exists, the requester is resolved exclusively from the caller''s own session identity (app.get_self_employee), so there is no field for a self-service caller to spoof. Mirrors app.create_leave_request (HRT-280 decision 10) exactly.';

create function app.create_ticket_for_employee(
  p_tenant_id uuid, p_requester_employee_id uuid, p_category_id uuid, p_queue_id uuid, p_priority text, p_subject text, p_body text,
  p_idempotency_key text, p_actor_auth_user_id uuid, p_actor_label text
)
returns app.tickets
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_employee app.employees;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'TKT', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks TKT:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_employee from app.employees where master_record_id = p_requester_employee_id and tenant_id = p_tenant_id;
  if not found then
    raise exception 'employee_not_found: %', p_requester_employee_id using errcode = 'no_data_found';
  end if;

  return app._create_ticket(p_tenant_id, v_employee.master_record_id, p_category_id, p_queue_id, p_priority, p_subject, p_body, p_idempotency_key, p_actor_auth_user_id, p_actor_label);
end;
$$;

comment on function app.create_ticket_for_employee is
  'HRT-286 (decision 2, section 22 "on-behalf request by authorized service desk"): explicit on-behalf entry point, TKT:Edit-gated -- mirrors app.create_leave_request_for_employee (HRT-280) exactly. The opening ticket_messages row''s author_auth_user_id is the ACTUAL submitting actor (the service-desk staffer), never the requester -- it records who really typed it; requester_employee_id records whose issue it is.';

-- ===========================================================================
-- 13. Conversation -- reply/internal note, and redaction (decisions 3/8/9).
-- ===========================================================================

create function app.reply_to_ticket(
  p_ticket_id uuid, p_body text, p_visibility text, p_attachment_file_ids uuid[], p_idempotency_key text,
  p_actor_auth_user_id uuid, p_actor_label text
)
returns app.ticket_messages
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_ticket app.tickets;
  v_self app.employees;
  v_is_requester boolean;
  v_is_staff boolean;
  v_visibility text := coalesce(p_visibility, 'public');
  v_author_role text;
  v_existing app.ticket_messages;
  v_message app.ticket_messages;
  v_file app.files;
  v_file_id uuid;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  select * into v_ticket from app.tickets where id = p_ticket_id for update;
  if not found then
    raise exception 'ticket_not_found: %', p_ticket_id using errcode = 'no_data_found';
  end if;

  -- C-05: a caller with NO relationship to this ticket at all (not
  -- requester/staff/watcher) must get the SAME ticket_not_found a genuinely
  -- missing id would produce -- never insufficient_authority, which would
  -- disclose that this ticket_id is real. Checked BEFORE any
  -- reply-specific authority branch below.
  if not app.can_access_ticket(p_ticket_id, p_actor_auth_user_id) then
    raise exception 'ticket_not_found: %', p_ticket_id using errcode = 'no_data_found';
  end if;

  if v_ticket.status = 'cancelled' then
    raise exception 'ticket_cancelled: cancelled ticket % cannot receive new messages', p_ticket_id using errcode = 'check_violation';
  end if;

  v_self := app.get_self_employee(v_ticket.tenant_id, p_actor_auth_user_id);
  v_is_requester := v_self.master_record_id is not null and v_self.master_record_id = v_ticket.requester_employee_id;
  v_is_staff := app.is_ticket_staff(p_ticket_id, p_actor_auth_user_id);

  -- Structurally scoped (can_access_ticket=true, e.g. a plain watcher) but
  -- not entitled to post -- a legitimate, disclosable denial (they already
  -- know this ticket exists).
  if not (v_is_requester or v_is_staff) then
    raise exception 'insufficient_authority: identity % is not a participant on ticket %', p_actor_auth_user_id, p_ticket_id
      using errcode = 'insufficient_privilege';
  end if;

  if not (v_visibility = any (array['public', 'internal'])) then
    raise exception 'invalid_visibility: % is not one of public/internal', v_visibility using errcode = 'check_violation';
  end if;
  if v_visibility = 'internal' and not v_is_staff then
    raise exception 'insufficient_authority: only ticket staff may post an internal note' using errcode = 'insufficient_privilege';
  end if;
  if p_body is null or length(trim(p_body)) = 0 then
    raise exception 'body_required: a non-empty message body is required' using errcode = 'check_violation';
  end if;

  v_author_role := case when v_is_staff then 'staff' else 'requester' end;

  if p_idempotency_key is not null then
    select * into v_existing from app.ticket_messages
    where tenant_id = v_ticket.tenant_id and ticket_id = p_ticket_id and idempotency_key = p_idempotency_key;
    if found then
      if v_existing.visibility = v_visibility and v_existing.body = p_body then
        return v_existing;
      else
        raise exception 'idempotency_key_conflict: key % was already used for a different message', p_idempotency_key using errcode = 'unique_violation';
      end if;
    end if;
  end if;

  if p_attachment_file_ids is not null then
    foreach v_file_id in array p_attachment_file_ids loop
      select * into v_file from app.files where id = v_file_id;
      if not found or v_file.tenant_id <> v_ticket.tenant_id or v_file.record_type <> 'ticket' or v_file.record_id <> p_ticket_id then
        raise exception 'evidence_file_not_found: file % is not a valid attachment for ticket %', v_file_id, p_ticket_id using errcode = 'no_data_found';
      end if;
      if v_file.malware_scan_status = 'infected' then
        raise exception 'evidence_file_infected: file % failed malware scanning and cannot be attached', v_file_id using errcode = 'check_violation';
      end if;
      if v_file.malware_scan_status <> 'clean' then
        raise exception 'evidence_file_not_scanned: file % has not cleared malware scanning (status %)', v_file_id, v_file.malware_scan_status
          using errcode = 'check_violation';
      end if;
    end loop;
  end if;

  begin
    insert into app.ticket_messages (tenant_id, ticket_id, visibility, body, attachment_file_ids, author_auth_user_id, author_label, author_role, idempotency_key)
    values (v_ticket.tenant_id, p_ticket_id, v_visibility, p_body, coalesce(p_attachment_file_ids, '{}'::uuid[]), p_actor_auth_user_id, p_actor_label, v_author_role, p_idempotency_key)
    returning * into v_message;
  exception
    when unique_violation then
      if p_idempotency_key is not null then
        select * into v_message from app.ticket_messages
        where tenant_id = v_ticket.tenant_id and ticket_id = p_ticket_id and idempotency_key = p_idempotency_key;
        if found and v_message.visibility = v_visibility and v_message.body = p_body then
          return v_message;
        end if;
      end if;
      raise;
  end;

  perform app.capture_audit_event(
    v_ticket.tenant_id, p_actor_auth_user_id, p_actor_label, 'reply_to_ticket',
    'app.ticket_messages', v_message.id, 'success', null, null,
    jsonb_build_object('ticket_id', p_ticket_id, 'visibility', v_message.visibility, 'attachment_count', coalesce(array_length(v_message.attachment_file_ids, 1), 0))
  );

  return v_message;
end;
$$;

comment on function app.reply_to_ticket is
  'HRT-286 (decision 3): requester or ticket staff may post; ONLY staff may set visibility=internal (enforced here, at write time -- the RLS policy on app.ticket_messages enforces the SAME rule at read time). Never changes app.tickets.status as a side effect (decision 6) -- status is always a separate, explicit app.transition_ticket_status call.';

create function app.redact_ticket_message(p_message_id uuid, p_expected_version integer, p_reason text, p_actor_auth_user_id uuid, p_actor_label text)
returns app.ticket_messages
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_message app.ticket_messages;
  v_updated app.ticket_messages;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  select * into v_message from app.ticket_messages where id = p_message_id for update;
  if not found then
    raise exception 'ticket_message_not_found: %', p_message_id using errcode = 'no_data_found';
  end if;

  -- C-05: fold a caller with no relationship to the OWNING ticket at all
  -- into the same not-found branch a genuinely missing message id would
  -- produce -- never disclose that this message/ticket exists to a
  -- cross-tenant or wholly unrelated caller before the TKT:Edit check.
  if not app.can_access_ticket(v_message.ticket_id, p_actor_auth_user_id) then
    raise exception 'ticket_message_not_found: %', p_message_id using errcode = 'no_data_found';
  end if;

  if not app.check_ticket_authority('Edit', v_message.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks TKT:Edit for tenant %', p_actor_auth_user_id, v_message.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if v_message.record_version <> p_expected_version then
    raise exception 'stale_version: expected version % but current version is %', p_expected_version, v_message.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_message.is_redacted then
    return v_message;
  end if;
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'reason_required: a reason is required to redact a message' using errcode = 'check_violation';
  end if;

  update app.ticket_messages
  set body = '[redacted]', attachment_file_ids = '{}'::uuid[], is_redacted = true, redacted_at = now(), redacted_by = p_actor_label, redacted_reason = p_reason
  where id = p_message_id and record_version = p_expected_version
  returning * into v_updated;
  if not found then
    raise exception 'stale_version: concurrent update detected for ticket message %', p_message_id using errcode = 'serialization_failure';
  end if;

  insert into app.ticket_events (tenant_id, ticket_id, event_type, actor_auth_user_id, actor_label)
  values (v_message.tenant_id, v_message.ticket_id, 'message_redacted', p_actor_auth_user_id, p_actor_label);

  perform app.capture_audit_event(
    v_message.tenant_id, p_actor_auth_user_id, p_actor_label, 'redact_ticket_message',
    'app.ticket_messages', v_message.id, 'success', null,
    jsonb_build_object('ticket_id', v_message.ticket_id, 'visibility', v_message.visibility, 'is_redacted', false),
    jsonb_build_object('ticket_id', v_updated.ticket_id, 'visibility', v_updated.visibility, 'is_redacted', true)
  );

  return v_updated;
end;
$$;

comment on function app.redact_ticket_message is
  'HRT-286 (decision 9): TKT:Edit-gated, never the plain author or plain queue membership -- redaction is content-destructive and deliberately held to the same bar as queue/category configuration. The original body is NEVER persisted anywhere else, including app.audit_logs (only structural before/after, is_redacted flip) -- normal roles cannot recover it once redacted; Supreme Admin''s standing RPD-022 exception is unaffected and already disclosed platform-wide.';

-- ===========================================================================
-- 14. Watchers -- explicit add/remove (decision 4).
-- ===========================================================================

create function app.add_ticket_watcher(p_ticket_id uuid, p_employee_id uuid, p_actor_auth_user_id uuid, p_actor_label text)
returns app.ticket_watchers
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_ticket app.tickets;
  v_self app.employees;
  v_is_requester boolean;
  v_is_staff boolean;
  v_row app.ticket_watchers;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  select * into v_ticket from app.tickets where id = p_ticket_id;
  if not found then
    raise exception 'ticket_not_found: %', p_ticket_id using errcode = 'no_data_found';
  end if;

  -- C-05: a total stranger (fails can_access_ticket entirely) gets the same
  -- ticket_not_found a missing id would produce, never a disclosing
  -- insufficient_authority.
  if not app.can_access_ticket(p_ticket_id, p_actor_auth_user_id) then
    raise exception 'ticket_not_found: %', p_ticket_id using errcode = 'no_data_found';
  end if;

  v_self := app.get_self_employee(v_ticket.tenant_id, p_actor_auth_user_id);
  v_is_requester := v_self.master_record_id is not null and v_self.master_record_id = v_ticket.requester_employee_id;
  v_is_staff := app.is_ticket_staff(p_ticket_id, p_actor_auth_user_id);
  if not (v_is_requester or v_is_staff) then
    raise exception 'insufficient_authority: identity % may not add a watcher to ticket %', p_actor_auth_user_id, p_ticket_id
      using errcode = 'insufficient_privilege';
  end if;

  if not exists (select 1 from app.employees e where e.master_record_id = p_employee_id and e.tenant_id = v_ticket.tenant_id) then
    raise exception 'employee_not_found: %', p_employee_id using errcode = 'no_data_found';
  end if;

  select * into v_row from app.ticket_watchers where ticket_id = p_ticket_id and employee_id = p_employee_id and status = 'active';
  if found then
    return v_row;
  end if;

  begin
    insert into app.ticket_watchers (tenant_id, ticket_id, employee_id, added_by)
    values (v_ticket.tenant_id, p_ticket_id, p_employee_id, p_actor_label)
    returning * into v_row;
  exception
    when unique_violation then
      select * into v_row from app.ticket_watchers where ticket_id = p_ticket_id and employee_id = p_employee_id and status = 'active';
      if not found then
        raise;
      end if;
  end;

  insert into app.ticket_events (tenant_id, ticket_id, event_type, to_value, actor_auth_user_id, actor_label)
  values (v_ticket.tenant_id, p_ticket_id, 'watcher_added', p_employee_id::text, p_actor_auth_user_id, p_actor_label);

  perform app.capture_audit_event(
    v_ticket.tenant_id, p_actor_auth_user_id, p_actor_label, 'add_ticket_watcher',
    'app.ticket_watchers', v_row.id, 'success', null, null, jsonb_build_object('ticket_id', p_ticket_id, 'employee_id', p_employee_id)
  );

  return v_row;
end;
$$;

create function app.remove_ticket_watcher(p_watcher_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text)
returns app.ticket_watchers
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_row app.ticket_watchers;
  v_ticket app.tickets;
  v_self app.employees;
  v_is_requester boolean;
  v_is_staff boolean;
  v_is_self_watcher boolean;
  v_updated app.ticket_watchers;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  select * into v_row from app.ticket_watchers where id = p_watcher_id for update;
  if not found then
    raise exception 'ticket_watcher_not_found: %', p_watcher_id using errcode = 'no_data_found';
  end if;
  select * into v_ticket from app.tickets where id = v_row.ticket_id;

  -- C-05: a total stranger to the owning ticket gets the same not-found a
  -- missing watcher id would produce.
  if not app.can_access_ticket(v_ticket.id, p_actor_auth_user_id) then
    raise exception 'ticket_watcher_not_found: %', p_watcher_id using errcode = 'no_data_found';
  end if;

  v_self := app.get_self_employee(v_ticket.tenant_id, p_actor_auth_user_id);
  v_is_requester := v_self.master_record_id is not null and v_self.master_record_id = v_ticket.requester_employee_id;
  v_is_staff := app.is_ticket_staff(v_ticket.id, p_actor_auth_user_id);
  v_is_self_watcher := v_self.master_record_id is not null and v_self.master_record_id = v_row.employee_id;
  if not (v_is_requester or v_is_staff or v_is_self_watcher) then
    raise exception 'insufficient_authority: identity % may not remove watcher %', p_actor_auth_user_id, p_watcher_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_row.record_version <> p_expected_version then
    raise exception 'stale_version: expected version % but current version is %', p_expected_version, v_row.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_row.status <> 'active' then
    raise exception 'invalid_transition: watcher % is % not active', p_watcher_id, v_row.status using errcode = 'check_violation';
  end if;

  update app.ticket_watchers set status = 'removed', removed_by = p_actor_label, removed_at = now()
  where id = p_watcher_id and record_version = p_expected_version
  returning * into v_updated;
  if not found then
    raise exception 'stale_version: concurrent update detected for ticket watcher %', p_watcher_id using errcode = 'serialization_failure';
  end if;

  insert into app.ticket_events (tenant_id, ticket_id, event_type, from_value, actor_auth_user_id, actor_label)
  values (v_ticket.tenant_id, v_ticket.id, 'watcher_removed', v_updated.employee_id::text, p_actor_auth_user_id, p_actor_label);

  perform app.capture_audit_event(
    v_ticket.tenant_id, p_actor_auth_user_id, p_actor_label, 'remove_ticket_watcher',
    'app.ticket_watchers', v_updated.id, 'success', null, null, jsonb_build_object('ticket_id', v_ticket.id, 'employee_id', v_updated.employee_id)
  );

  return v_updated;
end;
$$;

-- ===========================================================================
-- 15. Assignment, queue transfer, classification (decisions 5/7).
-- ===========================================================================

create function app.assign_ticket(p_ticket_id uuid, p_expected_version integer, p_assignee_employee_id uuid, p_actor_auth_user_id uuid, p_actor_label text)
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
  end if;

  update app.tickets set assignee_employee_id = p_assignee_employee_id, assigned_by = p_actor_label, assigned_at = now()
  where id = p_ticket_id and record_version = p_expected_version
  returning * into v_updated;
  if not found then
    raise exception 'stale_version: concurrent update detected for ticket %', p_ticket_id using errcode = 'serialization_failure';
  end if;

  insert into app.ticket_events (tenant_id, ticket_id, event_type, from_value, to_value, actor_auth_user_id, actor_label)
  values (v_ticket.tenant_id, p_ticket_id, 'assignment', v_ticket.assignee_employee_id::text, p_assignee_employee_id::text, p_actor_auth_user_id, p_actor_label);

  perform app.capture_audit_event(
    v_ticket.tenant_id, p_actor_auth_user_id, p_actor_label, 'assign_ticket',
    'app.tickets', p_ticket_id, 'success', null, app.ticket_audit_projection(v_ticket), app.ticket_audit_projection(v_updated)
  );

  return v_updated;
end;
$$;

comment on function app.assign_ticket is
  'HRT-286 (decision 7): manual designation only, TKT:Assign-gated. Validates the target is a real, ACTIVE member of the ticket''s own queue (a structural check, not an eligibility/workload algorithm) -- Prompt 290 owns real auto-routing and will layer it on top of this same column, never redesign it. Never changes app.tickets.status as a side effect (decision 6).';

create function app.transfer_ticket_queue(p_ticket_id uuid, p_expected_version integer, p_new_queue_id uuid, p_reason text, p_actor_auth_user_id uuid, p_actor_label text)
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
  -- C-05: a total stranger (fails can_access_ticket entirely) gets the same
  -- ticket_not_found a missing id would produce.
  if not app.can_access_ticket(p_ticket_id, p_actor_auth_user_id) then
    raise exception 'ticket_not_found: %', p_ticket_id using errcode = 'no_data_found';
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

  update app.tickets set queue_id = p_new_queue_id, assignee_employee_id = null, assigned_by = null, assigned_at = null
  where id = p_ticket_id and record_version = p_expected_version
  returning * into v_updated;
  if not found then
    raise exception 'stale_version: concurrent update detected for ticket %', p_ticket_id using errcode = 'serialization_failure';
  end if;

  insert into app.ticket_events (tenant_id, ticket_id, event_type, from_value, to_value, reason, actor_auth_user_id, actor_label)
  values (v_ticket.tenant_id, p_ticket_id, 'queue_transfer', v_ticket.queue_id::text, p_new_queue_id::text, p_reason, p_actor_auth_user_id, p_actor_label);

  perform app.capture_audit_event(
    v_ticket.tenant_id, p_actor_auth_user_id, p_actor_label, 'transfer_ticket_queue',
    'app.tickets', p_ticket_id, 'success', null, app.ticket_audit_projection(v_ticket), app.ticket_audit_projection(v_updated)
  );

  return v_updated;
end;
$$;

comment on function app.transfer_ticket_queue is
  'HRT-286 (section 22 "department transfer"): current queue staff (app.is_ticket_staff) may transfer, no separate TKT permission required beyond that structural scope. Clears assignee (the old assignee may not belong to the new queue) -- the new queue''s own staff must reassign explicitly.';

create function app.update_ticket_classification(p_ticket_id uuid, p_expected_version integer, p_category_id uuid, p_priority text, p_actor_auth_user_id uuid, p_actor_label text)
returns app.tickets
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_ticket app.tickets;
  v_updated app.tickets;
  v_priority text := coalesce(p_priority, 'normal');
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  select * into v_ticket from app.tickets where id = p_ticket_id for update;
  if not found then
    raise exception 'ticket_not_found: %', p_ticket_id using errcode = 'no_data_found';
  end if;
  -- C-05: a total stranger (fails can_access_ticket entirely) gets the same
  -- ticket_not_found a missing id would produce.
  if not app.can_access_ticket(p_ticket_id, p_actor_auth_user_id) then
    raise exception 'ticket_not_found: %', p_ticket_id using errcode = 'no_data_found';
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
    raise exception 'invalid_transition: cannot reclassify a % ticket', v_ticket.status using errcode = 'check_violation';
  end if;
  if not (v_priority = any (array['low', 'normal', 'high', 'urgent'])) then
    raise exception 'invalid_priority: % is not one of low/normal/high/urgent', v_priority using errcode = 'check_violation';
  end if;
  if not exists (select 1 from app.ticket_categories where id = p_category_id and tenant_id = v_ticket.tenant_id and status = 'active') then
    raise exception 'category_not_available: % is not an active category for this tenant', p_category_id using errcode = 'no_data_found';
  end if;

  update app.tickets set category_id = p_category_id, priority = v_priority
  where id = p_ticket_id and record_version = p_expected_version
  returning * into v_updated;
  if not found then
    raise exception 'stale_version: concurrent update detected for ticket %', p_ticket_id using errcode = 'serialization_failure';
  end if;

  insert into app.ticket_events (tenant_id, ticket_id, event_type, from_value, to_value, actor_auth_user_id, actor_label)
  values (
    v_ticket.tenant_id, p_ticket_id, 'classification_change',
    v_ticket.category_id::text || '/' || v_ticket.priority, p_category_id::text || '/' || v_priority,
    p_actor_auth_user_id, p_actor_label
  );

  perform app.capture_audit_event(
    v_ticket.tenant_id, p_actor_auth_user_id, p_actor_label, 'update_ticket_classification',
    'app.tickets', p_ticket_id, 'success', null, app.ticket_audit_projection(v_ticket), app.ticket_audit_projection(v_updated)
  );

  return v_updated;
end;
$$;

-- ===========================================================================
-- 16. Status transitions -- the ONE generic RPC (decision 6).
-- ===========================================================================

create function app._ticket_transition_authority(p_ticket app.tickets, p_to_status text, p_actor_auth_user_id uuid)
returns boolean
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_self app.employees;
  v_is_requester boolean;
  v_transition app.ticket_status_transitions;
begin
  select * into v_transition from app.ticket_status_transitions where from_status = p_ticket.status and to_status = p_to_status;
  if not found then
    return false;
  end if;

  v_self := app.get_self_employee(p_ticket.tenant_id, p_actor_auth_user_id);
  v_is_requester := v_self.master_record_id is not null and v_self.master_record_id = p_ticket.requester_employee_id;

  if v_transition.requester_allowed and v_is_requester then
    return true;
  end if;

  if not app.is_ticket_staff(p_ticket.id, p_actor_auth_user_id) then
    return false;
  end if;

  if p_to_status in ('resolved', 'closed') then
    return app.check_ticket_authority('Close', p_ticket.tenant_id, p_actor_auth_user_id);
  end if;
  if p_ticket.status in ('resolved', 'closed') and p_to_status = 'open' then
    return app.check_ticket_authority('Reopen', p_ticket.tenant_id, p_actor_auth_user_id);
  end if;

  return true;
end;
$$;

comment on function app._ticket_transition_authority is
  'HRT-286 (decision 5/6): resolve/close additionally require TKT:Close; staff-side reopen additionally requires TKT:Reopen; every other staff-side transition (lateral moves, cancel) needs only app.is_ticket_staff. The ticket''s own requester may additionally perform any transition flagged requester_allowed on app.ticket_status_transitions (cancel, reopen) with no TKT permission at all.';

create function app.transition_ticket_status(p_ticket_id uuid, p_expected_version integer, p_to_status text, p_reason text, p_actor_auth_user_id uuid, p_actor_label text)
returns app.tickets
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_ticket app.tickets;
  v_transition app.ticket_status_transitions;
  v_updated app.tickets;
  v_is_reopen boolean;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  select * into v_ticket from app.tickets where id = p_ticket_id for update;
  if not found then
    raise exception 'ticket_not_found: %', p_ticket_id using errcode = 'no_data_found';
  end if;
  if not app.can_access_ticket(p_ticket_id, p_actor_auth_user_id) then
    raise exception 'ticket_not_found: %', p_ticket_id using errcode = 'no_data_found';
  end if;

  select * into v_transition from app.ticket_status_transitions where from_status = v_ticket.status and to_status = p_to_status;
  if not found then
    raise exception 'invalid_transition: % -> % is not a legal ticket status transition', v_ticket.status, p_to_status using errcode = 'check_violation';
  end if;

  if not app._ticket_transition_authority(v_ticket, p_to_status, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % may not move ticket % from % to %', p_actor_auth_user_id, p_ticket_id, v_ticket.status, p_to_status
      using errcode = 'insufficient_privilege';
  end if;

  if v_ticket.record_version <> p_expected_version then
    raise exception 'stale_version: expected version % but current version is %', p_expected_version, v_ticket.record_version
      using errcode = 'serialization_failure';
  end if;

  if v_transition.requires_reason and (p_reason is null or length(trim(p_reason)) = 0) then
    raise exception 'reason_required: a reason is required to move this ticket from % to %', v_ticket.status, p_to_status using errcode = 'check_violation';
  end if;

  v_is_reopen := v_ticket.status in ('resolved', 'closed') and p_to_status = 'open';

  update app.tickets set
    status = p_to_status,
    resolution_summary = case when p_to_status = 'resolved' then p_reason else resolution_summary end,
    resolved_by = case when p_to_status = 'resolved' then p_actor_label else resolved_by end,
    resolved_at = case when p_to_status = 'resolved' then now() else resolved_at end,
    closed_by = case when p_to_status = 'closed' then p_actor_label else closed_by end,
    closed_at = case when p_to_status = 'closed' then now() else closed_at end,
    cancelled_reason = case when p_to_status = 'cancelled' then p_reason else cancelled_reason end,
    cancelled_by = case when p_to_status = 'cancelled' then p_actor_label else cancelled_by end,
    cancelled_at = case when p_to_status = 'cancelled' then now() else cancelled_at end,
    reopen_count = case when v_is_reopen then reopen_count + 1 else reopen_count end,
    last_reopened_by = case when v_is_reopen then p_actor_label else last_reopened_by end,
    last_reopened_at = case when v_is_reopen then now() else last_reopened_at end,
    last_reopen_reason = case when v_is_reopen then p_reason else last_reopen_reason end
  where id = p_ticket_id and record_version = p_expected_version
  returning * into v_updated;
  if not found then
    raise exception 'stale_version: concurrent update detected for ticket %', p_ticket_id using errcode = 'serialization_failure';
  end if;

  insert into app.ticket_events (tenant_id, ticket_id, event_type, from_value, to_value, reason, actor_auth_user_id, actor_label)
  values (v_ticket.tenant_id, p_ticket_id, 'status_change', v_ticket.status, p_to_status, p_reason, p_actor_auth_user_id, p_actor_label);

  perform app.capture_audit_event(
    v_ticket.tenant_id, p_actor_auth_user_id, p_actor_label, 'transition_ticket_status',
    'app.tickets', p_ticket_id, 'success', null, app.ticket_audit_projection(v_ticket), app.ticket_audit_projection(v_updated)
  );

  return v_updated;
end;
$$;

comment on function app.transition_ticket_status is
  'HRT-286 (decision 6): the ONE generic lifecycle RPC. Looks up (from_status, to_status) in app.ticket_status_transitions and rejects any pair with no matching row -- an invalid jump (e.g. new -> closed, or any transition out of cancelled) is structurally impossible. p_reason doubles as resolution_summary/cancelled_reason/last_reopen_reason depending on p_to_status -- never passed raw into capture_audit_event (decision 9); the real text lives only on app.tickets and app.ticket_events, both scoped no wider than the ticket itself.';

-- ===========================================================================
-- 17. Read RPCs -- every source table aliased, every lookup qualified
--     (decision 11/C-02 discipline). Reuse app.can_access_ticket/
--     app.is_ticket_staff as the SAME predicate RLS applies (decision 5).
-- ===========================================================================

create function app.list_ticket_queues(p_tenant_id uuid, p_actor_auth_user_id uuid)
returns table (id uuid, org_unit_id uuid, code text, name text, description text, status text, record_version integer)
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
  select q.id, q.org_unit_id, q.code, q.name, q.description, q.status, q.record_version
  from app.ticket_queues q
  where q.tenant_id = p_tenant_id
  order by q.code asc;
end;
$$;

create function app.list_ticket_categories(p_tenant_id uuid, p_actor_auth_user_id uuid)
returns table (id uuid, code text, name text, default_queue_id uuid, status text, record_version integer)
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
  select c.id, c.code, c.name, c.default_queue_id, c.status, c.record_version
  from app.ticket_categories c
  where c.tenant_id = p_tenant_id
  order by c.code asc;
end;
$$;

create function app.list_ticket_queue_members(p_queue_id uuid, p_actor_auth_user_id uuid)
returns table (id uuid, queue_id uuid, employee_id uuid, employee_name text, status text, added_by text, added_at timestamptz, record_version integer)
language plpgsql
security definer
set search_path = app, pg_temp
stable
as $$
declare
  v_queue app.ticket_queues;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  select q0.* into v_queue from app.ticket_queues q0 where q0.id = p_queue_id;
  if not found then
    return;
  end if;
  if not app.has_active_tenant_membership(v_queue.tenant_id, p_actor_auth_user_id) or app.actor_holds_customer_user_layer(v_queue.tenant_id, p_actor_auth_user_id) then
    return;
  end if;
  return query
  select m.id, m.queue_id, m.employee_id, e.full_name, m.status, m.added_by, m.added_at, m.record_version
  from app.ticket_queue_members m
  join app.employees e on e.master_record_id = m.employee_id
  where m.queue_id = p_queue_id
  order by m.status asc, e.full_name asc;
end;
$$;

create function app.get_ticket(p_ticket_id uuid, p_actor_auth_user_id uuid)
returns table (
  id uuid, tenant_id uuid, ticket_number text, channel text,
  category_id uuid, category_code text, category_name text,
  queue_id uuid, queue_code text, queue_name text,
  priority text, subject text, status text,
  requester_employee_id uuid, requester_name text, requested_by_auth_user_id uuid, requested_by text,
  assignee_employee_id uuid, assignee_name text, assigned_at timestamptz,
  resolution_summary text, resolved_at timestamptz, closed_at timestamptz,
  cancelled_reason text, cancelled_at timestamptz, reopen_count integer,
  record_version integer, created_at timestamptz, updated_at timestamptz,
  is_staff_viewer boolean, is_requester_viewer boolean
)
language plpgsql
security definer
set search_path = app, pg_temp
stable
as $$
declare
  v_tenant_id uuid;
  v_self app.employees;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  if not app.can_access_ticket(p_ticket_id, p_actor_auth_user_id) then
    return;
  end if;

  select t0.tenant_id into v_tenant_id from app.tickets t0 where t0.id = p_ticket_id;
  v_self := app.get_self_employee(v_tenant_id, p_actor_auth_user_id);

  return query
  select
    t.id, t.tenant_id, t.ticket_number, t.channel,
    t.category_id, c.code, c.name,
    t.queue_id, q.code, q.name,
    t.priority, t.subject, t.status,
    t.requester_employee_id, re.full_name, t.requested_by_auth_user_id, t.requested_by,
    t.assignee_employee_id, ae.full_name, t.assigned_at,
    t.resolution_summary, t.resolved_at, t.closed_at,
    t.cancelled_reason, t.cancelled_at, t.reopen_count,
    t.record_version, t.created_at, t.updated_at,
    app.is_ticket_staff(t.id, p_actor_auth_user_id),
    (v_self.master_record_id is not null and v_self.master_record_id = t.requester_employee_id)
  from app.tickets t
  join app.ticket_categories c on c.id = t.category_id
  join app.ticket_queues q on q.id = t.queue_id
  join app.employees re on re.master_record_id = t.requester_employee_id
  left join app.employees ae on ae.master_record_id = t.assignee_employee_id
  where t.id = p_ticket_id;
end;
$$;

create function app.list_tickets(
  p_tenant_id uuid, p_actor_auth_user_id uuid, p_status text, p_queue_id uuid, p_category_id uuid,
  p_priority text, p_assignee_employee_id uuid, p_limit integer, p_after_id uuid
)
returns table (
  id uuid, ticket_number text, subject text, status text, priority text,
  category_code text, queue_code text, requester_employee_id uuid, requester_name text,
  assignee_employee_id uuid, assignee_name text, record_version integer, created_at timestamptz, updated_at timestamptz
)
language plpgsql
security definer
set search_path = app, pg_temp
stable
as $$
declare
  v_limit integer := least(greatest(coalesce(p_limit, 50), 1), 200);
  v_after_created_at timestamptz;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  if p_after_id is not null then
    select t0.created_at into v_after_created_at from app.tickets t0 where t0.id = p_after_id;
  end if;

  return query
  select t.id, t.ticket_number, t.subject, t.status, t.priority, c.code, q.code,
         t.requester_employee_id, re.full_name, t.assignee_employee_id, ae.full_name,
         t.record_version, t.created_at, t.updated_at
  from app.tickets t
  join app.ticket_categories c on c.id = t.category_id
  join app.ticket_queues q on q.id = t.queue_id
  join app.employees re on re.master_record_id = t.requester_employee_id
  left join app.employees ae on ae.master_record_id = t.assignee_employee_id
  where t.tenant_id = p_tenant_id
    and app.can_access_ticket(t.id, p_actor_auth_user_id)
    and (p_status is null or t.status = p_status)
    and (p_queue_id is null or t.queue_id = p_queue_id)
    and (p_category_id is null or t.category_id = p_category_id)
    and (p_priority is null or t.priority = p_priority)
    and (p_assignee_employee_id is null or t.assignee_employee_id = p_assignee_employee_id)
    and (p_after_id is null or t.created_at < v_after_created_at or (t.created_at = v_after_created_at and t.id < p_after_id))
  order by t.created_at desc, t.id desc
  limit v_limit;
end;
$$;

create function app.list_my_tickets(p_tenant_id uuid, p_actor_auth_user_id uuid, p_status text, p_limit integer, p_after_id uuid)
returns table (
  id uuid, ticket_number text, subject text, status text, priority text,
  category_code text, queue_code text, assignee_employee_id uuid, assignee_name text,
  record_version integer, created_at timestamptz, updated_at timestamptz
)
language plpgsql
security definer
set search_path = app, pg_temp
stable
as $$
declare
  v_self app.employees;
  v_limit integer := least(greatest(coalesce(p_limit, 50), 1), 200);
  v_after_created_at timestamptz;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  v_self := app.get_self_employee(p_tenant_id, p_actor_auth_user_id);
  if v_self.master_record_id is null then
    return;
  end if;

  if p_after_id is not null then
    select t0.created_at into v_after_created_at from app.tickets t0 where t0.id = p_after_id;
  end if;

  return query
  select t.id, t.ticket_number, t.subject, t.status, t.priority, c.code, q.code,
         t.assignee_employee_id, ae.full_name, t.record_version, t.created_at, t.updated_at
  from app.tickets t
  join app.ticket_categories c on c.id = t.category_id
  join app.ticket_queues q on q.id = t.queue_id
  left join app.employees ae on ae.master_record_id = t.assignee_employee_id
  where t.tenant_id = p_tenant_id
    and t.requester_employee_id = v_self.master_record_id
    and (p_status is null or t.status = p_status)
    and (p_after_id is null or t.created_at < v_after_created_at or (t.created_at = v_after_created_at and t.id < p_after_id))
  order by t.created_at desc, t.id desc
  limit v_limit;
end;
$$;

create function app.list_ticket_messages(p_ticket_id uuid, p_actor_auth_user_id uuid, p_limit integer, p_after_id uuid)
returns table (
  id uuid, ticket_id uuid, visibility text, body text, is_redacted boolean, attachment_file_ids uuid[],
  author_auth_user_id uuid, author_label text, author_role text, created_at timestamptz, record_version integer
)
language plpgsql
security definer
set search_path = app, pg_temp
stable
as $$
declare
  v_is_staff boolean;
  v_limit integer := least(greatest(coalesce(p_limit, 100), 1), 500);
  v_after_created_at timestamptz;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  if not app.can_access_ticket(p_ticket_id, p_actor_auth_user_id) then
    return;
  end if;
  v_is_staff := app.is_ticket_staff(p_ticket_id, p_actor_auth_user_id);

  if p_after_id is not null then
    select m0.created_at into v_after_created_at from app.ticket_messages m0 where m0.id = p_after_id;
  end if;

  return query
  select m.id, m.ticket_id, m.visibility, m.body, m.is_redacted, m.attachment_file_ids,
         m.author_auth_user_id, m.author_label, m.author_role, m.created_at, m.record_version
  from app.ticket_messages m
  where m.ticket_id = p_ticket_id
    and (m.visibility = 'public' or v_is_staff)
    and (p_after_id is null or m.created_at > v_after_created_at or (m.created_at = v_after_created_at and m.id > p_after_id))
  order by m.created_at asc, m.id asc
  limit v_limit;
end;
$$;

comment on function app.list_ticket_messages is
  'HRT-286 (decision 3): the WHERE predicate (visibility = ''public'' or v_is_staff) mirrors app.ticket_messages_select_scoped''s own RLS predicate byte-for-byte -- a requester (not staff) never receives an internal-visibility row from this RPC, structurally, regardless of what a caller requests.';

create function app.list_ticket_watchers(p_ticket_id uuid, p_actor_auth_user_id uuid)
returns table (id uuid, ticket_id uuid, employee_id uuid, employee_name text, status text, added_by text, added_at timestamptz, record_version integer)
language plpgsql
security definer
set search_path = app, pg_temp
stable
as $$
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  if not app.can_access_ticket(p_ticket_id, p_actor_auth_user_id) then
    return;
  end if;
  return query
  select w.id, w.ticket_id, w.employee_id, e.full_name, w.status, w.added_by, w.added_at, w.record_version
  from app.ticket_watchers w
  join app.employees e on e.master_record_id = w.employee_id
  where w.ticket_id = p_ticket_id and w.status = 'active'
  order by w.added_at asc;
end;
$$;

create function app.list_ticket_events(p_ticket_id uuid, p_actor_auth_user_id uuid)
returns table (id uuid, ticket_id uuid, event_type text, from_value text, to_value text, reason text, actor_auth_user_id uuid, actor_label text, occurred_at timestamptz)
language plpgsql
security definer
set search_path = app, pg_temp
stable
as $$
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  if not app.can_access_ticket(p_ticket_id, p_actor_auth_user_id) then
    return;
  end if;
  return query
  select ev.id, ev.ticket_id, ev.event_type, ev.from_value, ev.to_value, ev.reason, ev.actor_auth_user_id, ev.actor_label, ev.occurred_at
  from app.ticket_events ev
  where ev.ticket_id = p_ticket_id
  order by ev.occurred_at asc;
end;
$$;

create function app.export_tickets(p_tenant_id uuid, p_actor_auth_user_id uuid, p_from_date date, p_to_date date)
returns table (
  ticket_number text, subject text, status text, priority text, category_code text, queue_code text,
  requester_name text, assignee_name text, created_at timestamptz, resolved_at timestamptz, closed_at timestamptz
)
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'TKT', 'Export');
  if not v_decision.allowed then
    return;
  end if;

  if p_from_date is null or p_to_date is null or (p_to_date - p_from_date) > 366 then
    raise exception 'invalid_date_range: export date range must be non-empty and at most 366 days' using errcode = 'check_violation';
  end if;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_auth_user_id::text, 'export_tickets',
    'app.tickets', null, 'success', null, null, jsonb_build_object('from_date', p_from_date, 'to_date', p_to_date)
  );

  return query
  select t.ticket_number, t.subject, t.status, t.priority, c.code, q.code, re.full_name, ae.full_name, t.created_at, t.resolved_at, t.closed_at
  from app.tickets t
  join app.ticket_categories c on c.id = t.category_id
  join app.ticket_queues q on q.id = t.queue_id
  join app.employees re on re.master_record_id = t.requester_employee_id
  left join app.employees ae on ae.master_record_id = t.assignee_employee_id
  where t.tenant_id = p_tenant_id and t.created_at::date between p_from_date and p_to_date
  order by t.created_at asc;
end;
$$;

comment on function app.export_tickets is
  'HRT-286: TKT:Export-gated, bounded date range (<=366 days), mirrors app.export_attendance_sessions (HRT-278) exactly. Structural/status columns only -- deliberately excludes resolution_summary/cancelled_reason and every message body, a conservative bound against bulk free-text leakage via export.';

-- ===========================================================================
-- 18. RLS -- hardened default-deny select policy on every new table
--     (decision 3/5). Writes exclusively through the SECURITY DEFINER
--     functions above, never a raw INSERT/UPDATE grant to authenticated.
-- ===========================================================================

alter table app.ticket_queues enable row level security;
alter table app.ticket_categories enable row level security;
alter table app.ticket_queue_members enable row level security;
alter table app.tickets enable row level security;
alter table app.ticket_messages enable row level security;
alter table app.ticket_watchers enable row level security;
alter table app.ticket_events enable row level security;

create policy ticket_queues_select_scoped on app.ticket_queues
  for select to authenticated
  using ((app.has_active_tenant_membership(tenant_id) and not app.actor_holds_customer_user_layer(tenant_id)) or app.is_supreme_admin());

create policy ticket_categories_select_scoped on app.ticket_categories
  for select to authenticated
  using ((app.has_active_tenant_membership(tenant_id) and not app.actor_holds_customer_user_layer(tenant_id)) or app.is_supreme_admin());

create policy ticket_queue_members_select_scoped on app.ticket_queue_members
  for select to authenticated
  using ((app.has_active_tenant_membership(tenant_id) and not app.actor_holds_customer_user_layer(tenant_id)) or app.is_supreme_admin());

create policy tickets_select_scoped on app.tickets
  for select to authenticated
  using (app.can_access_ticket(id) or app.is_supreme_admin());

create policy ticket_messages_select_scoped on app.ticket_messages
  for select to authenticated
  using ((app.can_access_ticket(ticket_id) and (visibility = 'public' or app.is_ticket_staff(ticket_id))) or app.is_supreme_admin());

create policy ticket_watchers_select_scoped on app.ticket_watchers
  for select to authenticated
  using (app.can_access_ticket(ticket_id) or app.is_supreme_admin());

create policy ticket_events_select_scoped on app.ticket_events
  for select to authenticated
  using (app.can_access_ticket(ticket_id) or app.is_supreme_admin());

-- ===========================================================================
-- 19. Grants -- explicit, deliberate (never blanket). No column needs
--     excluding on any table here (unlike leave/attendance's free-text
--     reason columns) -- ticket-level isolation is entirely row-scoped via
--     RLS/app.can_access_ticket, not column-scoped.
-- ===========================================================================

revoke execute on all functions in schema app from public;

grant select on app.ticket_queues to authenticated;
grant select on app.ticket_queues to service_role;
grant select on app.ticket_categories to authenticated;
grant select on app.ticket_categories to service_role;
grant select on app.ticket_queue_members to authenticated;
grant select on app.ticket_queue_members to service_role;
grant select on app.tickets to authenticated;
grant select on app.tickets to service_role;
grant select on app.ticket_messages to authenticated;
grant select on app.ticket_messages to service_role;
grant select on app.ticket_watchers to authenticated;
grant select on app.ticket_watchers to service_role;
grant select on app.ticket_events to authenticated;
grant select on app.ticket_events to service_role;

grant execute on function app.check_ticket_authority(text, uuid, uuid) to authenticated, service_role;
grant execute on function app.is_ticket_queue_member(uuid, uuid) to authenticated, service_role;
grant execute on function app.is_ticket_staff(uuid, uuid) to authenticated, service_role;
grant execute on function app.can_access_ticket(uuid, uuid) to authenticated, service_role;

grant execute on function app.create_ticket_queue(uuid, uuid, text, text, text, uuid, text) to authenticated, service_role;
grant execute on function app.create_ticket_category(uuid, text, text, uuid, uuid, text) to authenticated, service_role;
grant execute on function app.add_ticket_queue_member(uuid, uuid, uuid, text) to authenticated, service_role;
grant execute on function app.remove_ticket_queue_member(uuid, integer, text, uuid, text) to authenticated, service_role;

grant execute on function app.create_ticket(uuid, uuid, uuid, text, text, text, text, uuid, text) to authenticated, service_role;
grant execute on function app.create_ticket_for_employee(uuid, uuid, uuid, uuid, text, text, text, text, uuid, text) to authenticated, service_role;
grant execute on function app.reply_to_ticket(uuid, text, text, uuid[], text, uuid, text) to authenticated, service_role;
grant execute on function app.redact_ticket_message(uuid, integer, text, uuid, text) to authenticated, service_role;

grant execute on function app.add_ticket_watcher(uuid, uuid, uuid, text) to authenticated, service_role;
grant execute on function app.remove_ticket_watcher(uuid, integer, uuid, text) to authenticated, service_role;

grant execute on function app.assign_ticket(uuid, integer, uuid, uuid, text) to authenticated, service_role;
grant execute on function app.transfer_ticket_queue(uuid, integer, uuid, text, uuid, text) to authenticated, service_role;
grant execute on function app.update_ticket_classification(uuid, integer, uuid, text, uuid, text) to authenticated, service_role;
grant execute on function app.transition_ticket_status(uuid, integer, text, text, uuid, text) to authenticated, service_role;

grant execute on function app.list_ticket_queues(uuid, uuid) to authenticated, service_role;
grant execute on function app.list_ticket_categories(uuid, uuid) to authenticated, service_role;
grant execute on function app.list_ticket_queue_members(uuid, uuid) to authenticated, service_role;
grant execute on function app.get_ticket(uuid, uuid) to authenticated, service_role;
grant execute on function app.list_tickets(uuid, uuid, text, uuid, uuid, text, uuid, integer, uuid) to authenticated, service_role;
grant execute on function app.list_my_tickets(uuid, uuid, text, integer, uuid) to authenticated, service_role;
grant execute on function app.list_ticket_messages(uuid, uuid, integer, uuid) to authenticated, service_role;
grant execute on function app.list_ticket_watchers(uuid, uuid) to authenticated, service_role;
grant execute on function app.list_ticket_events(uuid, uuid) to authenticated, service_role;
grant execute on function app.export_tickets(uuid, uuid, date, date) to authenticated, service_role;

-- Internal engine functions -- service_role only (called exclusively from
-- inside this migration's own already-authorized SECURITY DEFINER
-- functions), mirrors app.next_employee_number/app._create_leave_request's
-- own established "internal, no direct authenticated grant" convention.
grant execute on function app.next_ticket_number(uuid) to service_role;
grant execute on function app._create_ticket(uuid, uuid, uuid, uuid, text, text, text, text, uuid, text) to service_role;
grant execute on function app._ticket_transition_authority(app.tickets, text, uuid) to service_role;
grant execute on function app.ticket_audit_projection(app.tickets) to authenticated, service_role;
grant execute on function app.touch_ticket_row() to service_role;
