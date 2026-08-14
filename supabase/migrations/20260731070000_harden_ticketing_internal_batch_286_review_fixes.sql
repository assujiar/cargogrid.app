-- Tier C batch review-round fix pass for CG-S12-HRT-014 (Internal and
-- Interdepartmental Ticket, Prompt 286), a standalone single-prompt batch.
-- Additive only: 20260731060000 (create_ticketing_internal) is NOT edited
-- in place, per AGENTS.md. Every fix below was independently re-derived
-- live against a disposable Postgres 16 database (all 206 pre-existing
-- migrations applied) before being written here, per
-- docs/standards/BUILD_EXECUTION_PROTOCOL.md section 5.3 -- never fixed
-- from a lens citation alone. Full disposition table, propagation sweep,
-- and fresh gate numbers are in docs/build-log/phase-07/HRT-286.md's own
-- Tier C batch review section.
--
-- Fixes, by finding:
--
-- 1. (MEDIUM, correctness lens, CONFIRMED live) -- app.transition_ticket_
--    status checked the transition-graph lookup (raises invalid_transition)
--    and the authority check (raises insufficient_authority) BEFORE the
--    record_version check (raises stale_version), the sole outlier among
--    every sibling versioned-write RPC in this migration (assign_ticket,
--    transfer_ticket_queue, update_ticket_classification, remove_ticket_
--    watcher, remove_ticket_queue_member -- mechanically re-swept here,
--    all confirmed to check record_version before their own business-rule
--    check). Live-reproduced with two genuinely concurrent OS psql
--    processes racing on the same starting record_version: the lock loser
--    got "invalid_transition: resolved -> pending is not a legal ticket
--    status transition" instead of the correct "stale_version" -- because
--    its row lock unblocked AFTER the winner committed a DIFFERENT
--    transition, so the loser's re-read v_ticket.status was already the
--    winner's new status, not what the loser's request was validated
--    against. No data corruption (exactly one transition ever applied,
--    confirmed both before and after this fix), but a client built to
--    catch stale_version/serialization_failure and transparently retry
--    would not catch this shape here. Fixed by moving the record_version
--    check to immediately after the existence/access checks -- before
--    both the transition-graph lookup and the authority check -- so any
--    concurrent modification is reported as stale_version before either
--    check can observe a re-read, already-changed row. Re-verified live
--    after the fix: the identical race now correctly returns stale_version
--    for the loser in every observed lock-acquisition order.
--
-- 2. (MEDIUM, security lens, CONFIRMED live) -- app.ticket_messages.
--    redacted_reason (mandatory, staff-authored free text explaining WHY a
--    message was redacted) had no column-level restriction -- RLS on this
--    table is row-only (ticket_messages_select_scoped), and the table-level
--    `grant select on app.ticket_messages to authenticated` exposed every
--    column, including this one, to a raw `.from("ticket_messages").
--    select(...)` call. app.list_ticket_messages (the real read RPC)
--    deliberately omits this column, but a direct PostgREST/supabase-js
--    read bypasses that. Live-reproduced: redacted a PUBLIC reply (visible
--    to its own requester via RLS, since visibility='public') with a
--    staff-only rationale, then raw-selected it as a forged requester
--    session -- the rationale came back verbatim. This directly
--    contradicted this migration's own section-19 comment ("ticket-level
--    isolation is entirely row-scoped ... not column-scoped"), which was
--    true for every OTHER column but not this one. Fixed using this
--    repository's own established, precedented pattern (identical to
--    app.users' email-column carve-out, 20260716110430:130-138): REVOKE
--    the table-level grant entirely and re-GRANT SELECT on an explicit
--    column list that omits redacted_reason (table-level and column-level
--    ACLs are additive in Postgres, not layered with override semantics --
--    a bare column-level REVOKE cannot carve an exception out of a
--    pre-existing table-level GRANT). Every application read path already
--    goes through the RPC layer (grep-confirmed zero `.from("ticket_
--    messages")` call anywhere in server/), so this has no caller impact.
--
-- 3. (LOW-MEDIUM, security lens, CONFIRMED live) -- the identical column-
--    exposure shape recurs on app.ticket_queue_members.removed_reason (a
--    free-text staff rationale for pulling someone off a queue), readable
--    tenant-wide by ANY active tenant employee via ticket_queue_members_
--    select_scoped's deliberately broad catalog-visibility RLS (mirrors
--    ticket_queues/ticket_categories -- by design, unlike ticket-level
--    isolation). Live-reproduced: removed a queue member with a marker
--    reason, then read it raw as a total-stranger tenant employee with
--    zero relationship to that roster or queue -- returned. Propagation
--    sweep of every other free-text "_reason" column on this migration's
--    tables (tickets.cancelled_reason, tickets.last_reopen_reason,
--    tickets.resolution_summary) found no further instance of this shape:
--    those columns sit behind app.can_access_ticket's much narrower
--    structural-scope RLS (requester/assignee/watcher/queue-member only),
--    the same small audience that already has full context via ticket_
--    events, not the broad "any tenant employee" audience removed_reason
--    and redacted_reason were exposed to. Fixed identically to finding 2:
--    REVOKE + column-scoped re-GRANT excluding removed_reason.
--
-- Findings independently re-verified live and NOT fixed here (disclosed in
-- docs/runtime/KNOWN_ISSUES.md with reasoning and exposure, per section
-- 5.6 -- each requires either a genuine architectural decision outside
-- this single-prompt batch's mandate, or is an already-accepted,
-- precedented repository-wide posture, not a defect):
--
-- - Spec-compliance lens Finding 1 / integration lens Finding 1 (HIGH,
--   CONFIRMED live by direct code read): this migration's own header
--   (decision 1) and the completion build log both overclaim "channel
--   extensibility is a pure additive CHECK-widen, never a redesign" --
--   app.tickets.requester_employee_id is NOT NULL, FK'd exclusively to
--   app.employees, resolved exclusively via app.get_self_employee across
--   8 authority call sites, and read via INNER JOIN app.employees in
--   get_ticket/list_tickets/export_tickets. app._create_ticket has no
--   p_channel parameter at all. A genuine Layer-4 customer-channel
--   requester (Prompt 287) or a CargoGrid-support-scoped assignee (Prompt
--   288) cannot be represented without relaxing the NOT NULL constraint,
--   adding nullable discriminator columns, converting those INNER JOINs to
--   LEFT JOINs, and adding new branches to can_access_ticket/is_ticket_
--   staff/_ticket_transition_authority -- real, if narrow (concentrated in
--   the identity columns/joins/authority helpers, not the channel CHECK
--   constraint itself or the RLS policy objects), expand-and-contract
--   work. Corrected here via accurate `comment on table`/`comment on
--   function` object comments (below) rather than the schema rework
--   itself, which is Prompt 287/288's own architectural decision to make,
--   not this batch's. See ISS-2026-085.
--
-- - Spec-compliance lens Finding 2 (MEDIUM, CONFIRMED live): TKT:Edit
--   grants blanket, tenant-wide, non-queue-scoped app.is_ticket_staff
--   status (full read/reply/reclassify/transfer of every ticket in the
--   tenant, regardless of queue), in tension with this migration's own
--   decision-5 comment ("TKT:Edit is reserved for QUEUE/CATEGORY
--   CONFIGURATION ... not for ordinary ticket work"). NOT a simple
--   contradiction to resolve by deletion, though: app.redact_ticket_
--   message (a genuinely content-destructive action) deliberately gates
--   on TKT:Edit directly, independent of is_ticket_staff, with its own
--   comment explicitly holding redaction "to the same bar as queue/
--   category configuration" -- meaning TKT:Edit-as-tenant-wide-override IS
--   intentional elsewhere in this same migration, and the fixture itself
--   (scripts/db-tests/ticketing-internal.sql:593) relies on staff1's
--   TKT:Edit to post an internal reply to a ticket AFTER a queue transfer
--   left staff1 without explicit membership on the new queue -- removing
--   the branch would silently break that already-passing, intentional
--   coverage. Whether TKT:Edit should function as a blanket tenant-wide
--   ticket-content override (as redact_ticket_message already assumes) or
--   be split into a narrower config-only permission is a real access-
--   control policy decision, not a bounded review-fix. Corrected here via
--   an accurate `comment on function app.is_ticket_staff` (below); the
--   design tension itself is tracked at ISS-2026-086.
--
-- - Security lens Finding 3 (LOW, CONFIRMED live): app.remove_ticket_
--   queue_member lets a total stranger distinguish a real member id from a
--   fake one (insufficient_authority vs. not_found), unlike every other
--   ticket-specific write RPC in this migration, which fold that case into
--   the same not-found response (the C-05 taxonomy fix already applied to
--   6 sibling functions in the original commit). NOT fixed: this exact,
--   deliberate "tenant-permission-only, no fold" shape is this
--   repository's own established, already-accepted precedent for
--   catalog/roster-remove functions (app.remove_talent_pool_member, HRT-
--   284, cited by this migration's own build log as the intentional
--   model followed) -- distinct from a structurally-isolated business
--   record like a ticket. Matching precedent, not a regression.
--
-- - Spec-compliance lens Findings 3/4 (attachment-upload UI, browser/
--   accessibility/performance E2E): already disclosed in docs/build-log/
--   phase-07/HRT-286.md section 9, matching this repository's own
--   repeated precedent (no live Supabase project, no browser/E2E harness
--   anywhere yet). Tracked at ISS-2026-087.

-- ===========================================================================
-- Fix 1: app.transition_ticket_status -- record_version checked first.
-- ===========================================================================

create or replace function app.transition_ticket_status(p_ticket_id uuid, p_expected_version integer, p_to_status text, p_reason text, p_actor_auth_user_id uuid, p_actor_label text)
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

  -- HRT-286 Tier C fix (finding 1): record_version is checked BEFORE the
  -- transition-graph lookup and the authority check, unlike the original
  -- draft. A concurrent modification must always surface as stale_version,
  -- never as a business-rule error derived from re-reading a row that has
  -- already moved out from under this call's own assumptions -- matches
  -- every sibling versioned-write RPC's own check order in this file
  -- (assign_ticket, transfer_ticket_queue, update_ticket_classification,
  -- remove_ticket_watcher, remove_ticket_queue_member).
  if v_ticket.record_version <> p_expected_version then
    raise exception 'stale_version: expected version % but current version is %', p_expected_version, v_ticket.record_version
      using errcode = 'serialization_failure';
  end if;

  select * into v_transition from app.ticket_status_transitions where from_status = v_ticket.status and to_status = p_to_status;
  if not found then
    raise exception 'invalid_transition: % -> % is not a legal ticket status transition', v_ticket.status, p_to_status using errcode = 'check_violation';
  end if;

  if not app._ticket_transition_authority(v_ticket, p_to_status, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % may not move ticket % from % to %', p_actor_auth_user_id, p_ticket_id, v_ticket.status, p_to_status
      using errcode = 'insufficient_privilege';
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
  'HRT-286 (decision 6), corrected at the CG-S12-HRT-014 Tier C batch review: the ONE generic lifecycle RPC. record_version is checked immediately after the existence/access checks, before the transition-graph lookup or the authority check, so a concurrent modification always surfaces as stale_version rather than a business-rule error derived from a re-read, already-changed row. Looks up (from_status, to_status) in app.ticket_status_transitions and rejects any pair with no matching row -- an invalid jump (e.g. new -> closed, or any transition out of cancelled) is structurally impossible. p_reason doubles as resolution_summary/cancelled_reason/last_reopen_reason depending on p_to_status -- never passed raw into capture_audit_event (decision 9); the real text lives only on app.tickets and app.ticket_events, both scoped no wider than the ticket itself.';

-- ===========================================================================
-- Fix 2/3: column-level privilege carve-outs for staff-only free-text
-- rationale columns exposed by an otherwise-correct, row-only RLS policy.
-- Mirrors app.users' own established email-column carve-out exactly
-- (20260716110430_create_field_record_access.sql:130-138) -- REVOKE the
-- table-level grant entirely and re-GRANT SELECT on an explicit column
-- list, since table-level and column-level ACLs are additive in Postgres,
-- not layered with override semantics. Every SECURITY DEFINER RPC that
-- legitimately needs these columns (app.redact_ticket_message/app.
-- remove_ticket_queue_member for their own writes; nothing reads
-- redacted_reason/removed_reason back out through any RPC today) runs as
-- the function owner and is unaffected by either revoke.
-- ===========================================================================

revoke select on app.ticket_messages from authenticated;
grant select (
  id, tenant_id, ticket_id, visibility, body, attachment_file_ids,
  author_auth_user_id, author_label, author_role, is_redacted, redacted_at,
  redacted_by, idempotency_key, record_version, created_at, updated_at
) on app.ticket_messages to authenticated;

revoke select on app.ticket_queue_members from authenticated;
grant select (
  id, tenant_id, queue_id, employee_id, status, added_by, added_at,
  removed_by, removed_at, record_version, updated_at
) on app.ticket_queue_members to authenticated;

comment on table app.ticket_messages is
  'HRT-286 (decision 3), corrected at the CG-S12-HRT-014 Tier C batch review: visibility is a strict, closed enum -- public (requester-visible reply) or internal (staff-only note) -- checked at write time (app.reply_to_ticket) and read time (RLS + every read RPC''s own identical WHERE predicate), never inferred from author or role. Redaction (app.redact_ticket_message) overwrites body in place and never persists the original text anywhere else queryable, including app.audit_logs (decision 9). Isolation is MOSTLY row-scoped via RLS/app.can_access_ticket, EXCEPT redacted_reason (staff-only rationale text), which is additionally column-scoped (REVOKE + explicit re-GRANT to authenticated, excluding redacted_reason) because a redacted PUBLIC message remains row-visible to its own requester via RLS, and the redaction rationale is not meant for that audience -- app.list_ticket_messages, the real read RPC, already omitted this column; the column-level grant makes that structural, not merely a convention a future direct-table read could bypass.';

comment on table app.ticket_queue_members is
  'HRT-286 (decision 4), corrected at the CG-S12-HRT-014 Tier C batch review: a dedicated, explicit staffing roster (soft-revocable, mirrors app.talent_pool_members). Deliberately catalog-visible tenant-wide (any active tenant employee, not customer-layer) via ticket_queue_members_select_scoped, matching app.ticket_queues/app.ticket_categories -- but removed_reason (a free-text staff rationale for pulling someone off a queue) is additionally column-scoped (REVOKE + explicit re-GRANT to authenticated, excluding removed_reason), since that broad catalog-visibility audience was never meant to read a roster-removal rationale.';

-- ===========================================================================
-- Documentation corrections (no behavior change) -- accurate object
-- comments replacing overclaiming/contradicted language identified by the
-- CG-S12-HRT-014 Tier C batch review. The original migration file itself
-- is not edited, per AGENTS.md; `comment on` is the additive mechanism.
-- ===========================================================================

comment on table app.tickets is
  'HRT-286 (decisions 1/2/7). channel is checked against (''internal'') ONLY in this migration; widening the CHECK constraint itself, and the RLS policy objects that reference app.can_access_ticket/app.is_ticket_staff, is a genuine, precedented additive change (mirrors app.jobs.job_type). CORRECTED at the CG-S12-HRT-014 Tier C batch review: this table''s own identity columns are NOT a pure additive widen for Prompt 287 (customer)/288 (helpdesk) -- requester_employee_id is NOT NULL and FK''d exclusively to app.employees, resolved exclusively via app.get_self_employee across can_access_ticket/is_ticket_staff/_ticket_transition_authority, and read via INNER JOIN app.employees in get_ticket/list_tickets/export_tickets. Representing a genuine non-employee requester (Layer 4 customer) or a non-org-unit-scoped assignee (CargoGrid support) requires relaxing that NOT NULL constraint, adding nullable discriminator column(s), converting those INNER JOINs to LEFT JOINs, and adding new branches to the authority helpers above -- real, expand-and-contract schema work for whichever prompt lands the next channel, not a same-shape CHECK-widen alone. See ISS-2026-085 (docs/runtime/KNOWN_ISSUES.md) for the full analysis.';

comment on function app._create_ticket is
  'HRT-286 (decision 2): the shared creation engine behind app.create_ticket (self-service) and app.create_ticket_for_employee (on-behalf, TKT:Edit-gated). CORRECTED at the CG-S12-HRT-014 Tier C batch review: this function has NO p_channel parameter and its INSERT relies entirely on app.tickets.channel''s table-level default (''internal'') -- a future channel-specific creation entry point cannot simply call this same engine with a different p_channel value as originally documented; it will need either a new parameter here or a channel-aware sibling engine, decided alongside the identity-column rework tracked at ISS-2026-085.';

comment on function app.is_ticket_staff is
  'HRT-286 (decision 5), corrected at the CG-S12-HRT-014 Tier C batch review: true if the caller is Supreme Admin, holds TKT:Edit, is the ticket''s own assignee, or is an active member of the ticket''s queue. TKT:Edit is evaluated TENANT-WIDE here, not queue-scoped -- a TKT:Edit holder becomes ticket staff (read internal notes, reply, reclassify, transfer) on EVERY ticket in the tenant, not merely the queues they configure. This is broader than decision 5''s own "reserved for queue/category configuration, not ordinary ticket work" framing elsewhere in this migration''s header, and is a deliberate design tension tracked at ISS-2026-086 (docs/runtime/KNOWN_ISSUES.md), not a defect fixed by this comment -- app.redact_ticket_message already independently relies on TKT:Edit as a tenant-wide, content-destructive-action override (see its own comment), and this migration''s own db-test fixture relies on this exact branch (a staff member''s TKT:Edit covering a ticket after a queue transfer left them without explicit new-queue membership). Governs internal-note visibility/posting and ordinary staff-side ticket work. Used directly by RLS (app.ticket_messages_select_scoped) and by every write RPC in the base migration.';
