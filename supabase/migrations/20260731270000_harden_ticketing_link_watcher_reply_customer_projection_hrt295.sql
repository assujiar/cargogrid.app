-- HRT-295 (CG-S12-HRT-023, Prompt 295 -- Ticket closure/masking/identity
-- hardening). Repairs two HRT-294 findings against the Typed Linked Records
-- (HRT-292) / Internal Ticket (HRT-286) / Helpdesk (HRT-288) capabilities:
--
-- ISS-2026-109 (Medium): a closed or cancelled ticket was not
-- mutation-inert. app.link_ticket_record/app.unlink_ticket_record
-- (20260731170000) and app.add_ticket_watcher/app.remove_ticket_watcher
-- (final live bodies in 20260731110000) never read v_ticket.status at all;
-- app.reply_to_ticket (final live body in 20260731110000) guarded only
-- 'cancelled', never 'closed' -- unlike every other ticket-lifecycle RPC in
-- the same family (app.escalate_ticket, app.claim_ticket/app.assign_ticket,
-- app.auto_route_ticket, app.transfer_ticket_queue/app.update_ticket_
-- classification, app.assign_helpdesk_ticket), which all explicitly reject
-- status in ('closed', 'cancelled') with invalid_transition.
--
-- Design decision (per this entry's own named open question -- "should
-- closed behave exactly like cancelled for all four functions, or does the
-- linked-records/watcher capability need its own narrower closure
-- semantics"): NOT symmetric. Two real, already-shipped precedents inside
-- this SAME capability family point in opposite directions for "create a
-- new engagement" versus "remove/clean up an existing one":
--   - app.escalate_ticket/app.claim_ticket/app.assign_ticket/app.auto_
--     route_ticket/app.transfer_ticket_queue/app.update_ticket_
--     classification/app.assign_helpdesk_ticket (all "start something new
--     on this ticket") ALL reject a closed/cancelled ticket.
--   - app.acknowledge_ticket_escalation/app.resolve_ticket_escalation
--     (20260731160000, "wind down something that already exists") do NOT
--     check v_ticket.status at all -- staff may acknowledge/resolve an
--     escalation regardless of the ticket's own terminal state.
-- Applied here: app.link_ticket_record and app.add_ticket_watcher (both
-- "engage something new with this ticket") now reject closed/cancelled with
-- invalid_transition, mirroring the first precedent. app.unlink_ticket_
-- record and app.remove_ticket_watcher (both "remove an existing
-- engagement", the exact cleanup case this entry's own text names --
-- "removing a bad link/watcher from an already-closed ticket is arguably
-- still legitimate cleanup") are DELIBERATELY left unguarded, mirroring the
-- second precedent -- comment-only update, zero behavior change, so the
-- decision is discoverable in the function itself rather than living only
-- in this migration header. app.reply_to_ticket ("post new content") joins
-- the first group: its own pre-existing 'cancelled' guard is extended with
-- a closed check, using a NEW, parallel ticket_closed error rather than
-- switching to the family's generic invalid_transition -- preserving this
-- function's own already-tested ticket_cancelled contract
-- (scripts/db-tests/ticketing-internal.sql section 7) byte-for-byte while
-- closing the actual gap.
--
-- app.add_ticket_watcher's ticket lookup is additionally upgraded from a
-- plain SELECT to SELECT ... FOR UPDATE (C-04 self-check on this diff's own
-- new decision: a status-gating decision on an unlocked row is exactly the
-- class of defect docs/standards/RECURRING_DEFECT_TAXONOMY.md C-04 exists to
-- catch) -- matches every sibling RPC that already gates on ticket status
-- (app.link_ticket_record, app.escalate_ticket, app.claim_ticket, ...), all
-- of which lock the ticket row before reading its status. Adds exactly one
-- row lock, no second table locked by this function, so no new C-21
-- cross-function lock-order question is introduced.
--
-- ISS-2026-110 (Low): app.list_ticket_links (20260731170000) returned the
-- raw internal staff created_by identity to a customer caller -- no
-- customer-vs-staff branching anywhere in the function body, unlike this
-- same workstream's own established "genericize staff identity for
-- customer reads" convention (app.list_customer_ticket_messages,
-- 20260731080000, substitutes a fixed "Support Team" label for a
-- staff-authored message). Fix, per this entry's own Disposition: a genuine
-- new customer-safe projection RPC, mirroring app.list_customer_ticket_
-- messages' shape exactly (a DISTINCT function, never a branch inside the
-- staff-facing one -- confirmed the established convention by reading
-- server/queries/ticketing.ts's own HRT-287 comment, "Each calls its own
-- dedicated, customer-safe projection RPC -- never the internal wrappers
-- above with fields merely dropped client-side"). app.ticket_links carries
-- no stored creator-role column (unlike app.ticket_messages.author_role,
-- captured at INSERT time) -- app.list_customer_ticket_links' created_by
-- branch is therefore a LIVE app.is_ticket_staff re-check on the creator's
-- own auth_user_id rather than a stored value, which is consistent with
-- (not a departure from) this exact capability's own already-established
-- "never trust a stored value, always re-derive live" convention (app.list_
-- ticket_links' own label/detail/status_label, decision 6 of the HRT-292
-- migration) -- disclosed as a deliberate, bounded design choice rather
-- than a speculative created_by_role column/backfill the closing finding
-- never asked for. entity_type/entity_id scope narrowing for a customer
-- caller is explicitly OUT of scope here -- that is the separate,
-- already-registered ISS-2026-102, not this finding.
--
-- Per ERR-2026-004: this migration carries its own explicit
-- `revoke execute on all functions in schema app from public` before its
-- final grants.

-- ===========================================================================
-- 1. app.link_ticket_record -- reject a closed/cancelled ticket.
-- ===========================================================================

create or replace function app.link_ticket_record(
  p_ticket_id uuid,
  p_entity_type text,
  p_entity_id uuid,
  p_relationship text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.ticket_links
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_ticket app.tickets;
  v_is_staff boolean;
  v_is_requester boolean;
  v_relationship text;
  v_existing app.ticket_links;
  v_candidate record;
  v_snapshot jsonb;
  v_row app.ticket_links;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  select * into v_ticket from app.tickets where id = p_ticket_id for update;
  if not found or not app.can_access_ticket(p_ticket_id, p_actor_auth_user_id) then
    raise exception 'ticket_not_found: %', p_ticket_id using errcode = 'no_data_found';
  end if;

  v_is_staff := app.is_ticket_staff(p_ticket_id, p_actor_auth_user_id);
  v_is_requester := app._is_ticket_requester_party(v_ticket, p_actor_auth_user_id);
  if not (v_is_staff or v_is_requester) then
    raise exception 'insufficient_authority: identity % may not link records to ticket %', p_actor_auth_user_id, p_ticket_id
      using errcode = 'insufficient_privilege';
  end if;

  -- HRT-295 (ISS-2026-109): a closed/cancelled ticket may not gain a NEW
  -- record link -- mirrors app.escalate_ticket/app.claim_ticket/app.assign_
  -- ticket/app.auto_route_ticket/app.transfer_ticket_queue/app.update_
  -- ticket_classification/app.assign_helpdesk_ticket's own identical guard.
  -- app.unlink_ticket_record deliberately does NOT get the equivalent
  -- guard -- see its own comment for the design decision (cleanup remains
  -- permitted, mirroring app.resolve_ticket_escalation/app.acknowledge_
  -- ticket_escalation's own precedent).
  if v_ticket.status in ('closed', 'cancelled') then
    raise exception 'invalid_transition: cannot link a record to a % ticket', v_ticket.status using errcode = 'check_violation';
  end if;

  if not (p_entity_type = any (app.ticket_link_entity_types())) then
    raise exception 'unsupported_entity_type: % is not a supported ticket link entity type', p_entity_type using errcode = 'check_violation';
  end if;

  if app.actor_holds_customer_user_layer(v_ticket.tenant_id, p_actor_auth_user_id) and not (p_entity_type = any (app.ticket_link_customer_safe_entity_types())) then
    raise exception 'entity_type_not_permitted: % is not a customer-permitted link type', p_entity_type using errcode = 'insufficient_privilege';
  end if;

  v_relationship := coalesce(p_relationship, 'related');
  if not (v_relationship = any (array['primary_subject', 'related', 'affected', 'context'])) then
    raise exception 'invalid_relationship: % is not a recognized link relationship', p_relationship using errcode = 'check_violation';
  end if;

  -- Anti-enumeration (decisions 3/4/8): existence, tenant scope, and this
  -- caller's OWN independent domain authorization collapse into ONE
  -- outcome here -- a forged id, a cross-tenant id, a deleted record, and
  -- an unauthorized-but-real candidate are all indistinguishable.
  --
  -- Deliberately runs BEFORE the duplicate-policy short-circuit below (a
  -- self-found ordering defect, live-caught by this migration's own
  -- db-test, not by review): an EARLIER draft checked for an existing
  -- active link FIRST and returned it unconditionally on a match, which
  -- would let caller B silently receive (and read the safe_snapshot of)
  -- a record caller A already linked, even when B has NO independent
  -- domain authorization of their own -- exactly the "a link grants
  -- access" violation this capability''s own business rule forbids. Every
  -- link_ticket_record call, including a fully idempotent replay, now
  -- re-proves the CURRENT caller''s own eligibility every time.
  select * into v_candidate from app._ticket_link_resolve_candidate(p_entity_type, v_ticket.tenant_id, p_actor_auth_user_id, p_entity_id);
  if not found then
    raise exception 'record_not_eligible: no eligible % record exists for %', p_entity_type, p_entity_id using errcode = 'no_data_found';
  end if;

  -- Duplicate policy (decision 12): an already-active link for the
  -- identical natural key is a clean, idempotent no-op return -- never a
  -- duplicate row, never an error -- but ONLY once the caller''s own
  -- eligibility (immediately above) has already been proven.
  select * into v_existing from app.ticket_links where ticket_id = p_ticket_id and entity_type = p_entity_type and entity_id = p_entity_id and status = 'active';
  if found then
    return v_existing;
  end if;

  v_snapshot := jsonb_build_object('label', v_candidate.primary_label, 'detail', v_candidate.secondary_label, 'status', v_candidate.status_label);

  begin
    insert into app.ticket_links (
      tenant_id, ticket_id, entity_type, entity_id, relationship, source, status,
      safe_snapshot, snapshot_captured_at, created_by_auth_user_id, created_by
    ) values (
      v_ticket.tenant_id, p_ticket_id, p_entity_type, p_entity_id, v_relationship, 'manual', 'active',
      v_snapshot, now(), p_actor_auth_user_id, p_actor_label
    )
    returning * into v_row;
  exception
    when unique_violation then
      select * into v_row from app.ticket_links where ticket_id = p_ticket_id and entity_type = p_entity_type and entity_id = p_entity_id and status = 'active';
      if not found then
        raise;
      end if;
      return v_row;
  end;

  insert into app.ticket_link_events (tenant_id, ticket_id, link_id, entity_type, entity_id, relationship, event_type, actor_auth_user_id, actor_label)
  values (v_ticket.tenant_id, p_ticket_id, v_row.id, p_entity_type, p_entity_id, v_relationship, 'linked', p_actor_auth_user_id, p_actor_label);

  return v_row;
end;
$$;

comment on function app.link_ticket_record is
  'HRT-292: link authority mirrors app.add_ticket_watcher exactly (decision: staff OR requester-side party, never a plain watcher) -- is_ticket_staff OR app._is_ticket_requester_party. Idempotent on the (ticket_id, entity_type, entity_id) natural key (decision 12, real partial unique index + exception handler). Anti-enumerating record_not_eligible (decision 8) on any invalid/unauthorized candidate -- the caller cannot distinguish forged/cross-tenant/deleted/unauthorized. HRT-295 (ISS-2026-109 fix): rejects a closed/cancelled ticket with invalid_transition, mirroring app.escalate_ticket''s own sibling guard -- see this migration''s own header for the full closed-vs-cancelled/link-vs-unlink design decision.';

-- ===========================================================================
-- 2. app.unlink_ticket_record -- comment-only update (ERR-2026-004 note:
--    plain COMMENT ON FUNCTION, no CREATE OR REPLACE -- the function body,
--    and therefore its ACL, is genuinely unchanged). Deliberately NOT given
--    the closed/cancelled guard -- see comment.
-- ===========================================================================

comment on function app.unlink_ticket_record(uuid, integer, text, uuid, text) is
  'HRT-292 (decision 13): ticket-first lock order, preserved without requiring the caller to already know the ticket id. Reason is mandatory (business rule "record link/unlink source/reason"). Removing a link never deletes the row -- status=removed, a real removed_at/removed_by/removed_reason, so the ledger and the row itself both keep full history. HRT-295 (ISS-2026-109 design decision, DELIBERATELY UNCHANGED): unlink remains permitted on a closed or cancelled ticket -- removing an already-linked record is cleanup, not a new engagement, mirroring app.resolve_ticket_escalation/app.acknowledge_ticket_escalation''s own established precedent of staying reachable regardless of the ticket''s own terminal status. app.link_ticket_record (the create-type sibling) DOES reject closed/cancelled -- see its own comment.';

-- ===========================================================================
-- 3. app.add_ticket_watcher / app.remove_ticket_watcher.
-- ===========================================================================

create or replace function app.add_ticket_watcher(p_ticket_id uuid, p_employee_id uuid, p_actor_auth_user_id uuid, p_actor_label text)
returns app.ticket_watchers
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_ticket app.tickets;
  v_is_requester boolean;
  v_is_staff boolean;
  v_row app.ticket_watchers;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  -- HRT-295 (ISS-2026-109, C-04 self-check on this diff's own new status
  -- decision below): FOR UPDATE added -- was a plain, unlocked SELECT.
  -- Every sibling RPC that gates on ticket status locks the row first
  -- (app.link_ticket_record, app.escalate_ticket, app.claim_ticket, ...);
  -- without the lock, a concurrent app.transition_ticket_status(-> closed)
  -- could interleave between this read and the new status check below.
  select * into v_ticket from app.tickets where id = p_ticket_id for update;
  if not found then
    raise exception 'ticket_not_found: %', p_ticket_id using errcode = 'no_data_found';
  end if;

  if not app.can_access_ticket(p_ticket_id, p_actor_auth_user_id) then
    raise exception 'ticket_not_found: %', p_ticket_id using errcode = 'no_data_found';
  end if;

  if v_ticket.channel = 'helpdesk' then
    raise exception 'channel_not_supported: ticket % is a helpdesk case -- ticket watchers are an employee-participant mechanism that does not apply to the tenant-as-requester helpdesk model', p_ticket_id
      using errcode = 'check_violation';
  end if;

  v_is_staff := app.is_ticket_staff(p_ticket_id, p_actor_auth_user_id);
  v_is_requester := app._is_ticket_requester_party(v_ticket, p_actor_auth_user_id);

  if v_ticket.channel = 'customer' then
    -- Decision 8: watchers are an employee/staff mechanism -- a
    -- customer-channel requester never manages this roster, even for
    -- their own ticket.
    if not v_is_staff then
      raise exception 'insufficient_authority: identity % may not add a watcher to ticket %', p_actor_auth_user_id, p_ticket_id
        using errcode = 'insufficient_privilege';
    end if;
  elsif not (v_is_requester or v_is_staff) then
    raise exception 'insufficient_authority: identity % may not add a watcher to ticket %', p_actor_auth_user_id, p_ticket_id
      using errcode = 'insufficient_privilege';
  end if;

  -- HRT-295 (ISS-2026-109): a closed/cancelled ticket may not gain a NEW
  -- watcher -- mirrors app.link_ticket_record's own identical guard (see its
  -- comment) and the established sibling convention across this capability
  -- family. app.remove_ticket_watcher is deliberately NOT given the
  -- equivalent guard -- see its own comment for the design decision.
  if v_ticket.status in ('closed', 'cancelled') then
    raise exception 'invalid_transition: cannot add a watcher to a % ticket', v_ticket.status using errcode = 'check_violation';
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

comment on function app.add_ticket_watcher is
  'HRT-286 (decisions 3/8), corrected at the CG-S12-HRT-016 Tier C batch review: generalized identity resolution, staff-only for a customer-channel ticket. Explicitly REJECTS a helpdesk-channel ticket (Tier C finding: previously fell through to the generic requester-or-staff elsif branch, and since a helpdesk ticket''s own tenant_admin/TKT:Edit holder legitimately IS the requester party, an ordinary tenant admin could insert a real employee-participant watcher row against a channel whose whole design principle is that no employee is ever a participant) -- watchers have no helpdesk analogue at all, unlike assign/transfer/classify which each have a dedicated Supreme-Admin-gated sibling. HRT-295 (ISS-2026-109 fix): also rejects a closed/cancelled ticket with invalid_transition, and the ticket lookup is now FOR UPDATE (was unlocked) -- see this migration''s own header.';

-- Comment-only update -- plain COMMENT ON FUNCTION, no CREATE OR REPLACE,
-- body and ACL genuinely unchanged. Deliberately NOT given the
-- closed/cancelled guard -- see comment.
comment on function app.remove_ticket_watcher(uuid, integer, uuid, text) is
  'HRT-286, corrected at the CG-S12-HRT-016 Tier C batch review: explicitly REJECTS a helpdesk-channel ticket, mirroring app.add_ticket_watcher''s own Tier C fix -- see its comment for the full defect this closes. HRT-295 (ISS-2026-109 design decision, DELIBERATELY UNCHANGED): removal remains permitted on a closed or cancelled ticket -- removing an already-added watcher is cleanup, not a new engagement, mirroring app.resolve_ticket_escalation/app.acknowledge_ticket_escalation''s own established precedent. app.add_ticket_watcher (the create-type sibling) DOES reject closed/cancelled -- see its own comment.';

-- ===========================================================================
-- 4. app.reply_to_ticket -- extend the existing cancelled-only guard to
--    also cover closed, with a new parallel error rather than switching to
--    invalid_transition (preserves the pre-existing, already-tested
--    ticket_cancelled contract byte-for-byte).
-- ===========================================================================

create or replace function app.reply_to_ticket(
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

  -- C-05: a caller with NO relationship to this ticket at all gets the SAME
  -- ticket_not_found a genuinely missing id would produce.
  if not app.can_access_ticket(p_ticket_id, p_actor_auth_user_id) then
    raise exception 'ticket_not_found: %', p_ticket_id using errcode = 'no_data_found';
  end if;

  if v_ticket.status = 'cancelled' then
    raise exception 'ticket_cancelled: cancelled ticket % cannot receive new messages', p_ticket_id using errcode = 'check_violation';
  end if;
  -- HRT-295 (ISS-2026-109): closed was the one terminal status this guard
  -- never covered, unlike every sibling ticket-lifecycle RPC. A NEW,
  -- parallel error (ticket_closed) rather than folding into the family's
  -- generic invalid_transition or reusing ticket_cancelled -- keeps this
  -- function's own pre-existing, already-tested ticket_cancelled contract
  -- (scripts/db-tests/ticketing-internal.sql section 7) byte-for-byte.
  if v_ticket.status = 'closed' then
    raise exception 'ticket_closed: closed ticket % cannot receive new messages', p_ticket_id using errcode = 'check_violation';
  end if;

  v_is_requester := app._is_ticket_requester_party(v_ticket, p_actor_auth_user_id);
  v_is_staff := app.is_ticket_staff(p_ticket_id, p_actor_auth_user_id);

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
    where tenant_id = v_ticket.tenant_id and ticket_id = p_ticket_id and author_auth_user_id = p_actor_auth_user_id and idempotency_key = p_idempotency_key;
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
        where tenant_id = v_ticket.tenant_id and ticket_id = p_ticket_id and author_auth_user_id = p_actor_auth_user_id and idempotency_key = p_idempotency_key;
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
  'HRT-286 (decision 3), corrected at the CG-S12-HRT-016 Tier C batch review: requester or ticket staff may post; ONLY staff may set visibility=internal (enforced here, at write time -- the RLS policy on app.ticket_messages enforces the SAME rule at read time). Never changes app.tickets.status as a side effect (decision 6) -- status is always a separate, explicit app.transition_ticket_status call. Idempotency replay is keyed on (tenant_id, ticket_id, author_auth_user_id, idempotency_key) -- Tier C finding: the author was previously omitted from both the match logic and ticket_messages_idempotency_unique, so two different, independently-authorized participants on the same ticket who coincidentally reused one idempotency key with matching visibility/body were silently collapsed into a single row, discarding the second caller''s genuine reply with no error and misattributing it to the first caller. See ticket_messages_idempotency_unique. HRT-295 (ISS-2026-109 fix): also rejects a closed ticket with a new, parallel ticket_closed error (the pre-existing ticket_cancelled guard is unchanged) -- see this migration''s own header.';

-- ===========================================================================
-- 5. app.list_customer_ticket_links -- new customer-safe projection of
--    app.list_ticket_links, closing ISS-2026-110.
-- ===========================================================================

create function app.list_customer_ticket_links(p_ticket_id uuid, p_actor_auth_user_id uuid)
returns table (
  id uuid, entity_type text, entity_id uuid, relationship text, status text,
  live_available boolean, label text, detail text, status_label text,
  linked_at timestamptz, created_by text, record_version integer
)
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_ticket app.tickets;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  -- Mirrors app.list_customer_ticket_messages' own defensive channel guard
  -- (20260731080000): folds "not a customer-channel ticket" into the
  -- identical empty-result shape a genuinely nonexistent id or a denied
  -- caller would produce -- no enumeration oracle on channel.
  select * into v_ticket from app.tickets t0 where t0.id = p_ticket_id and t0.channel = 'customer';
  if not found then
    return;
  end if;
  if not app.can_access_ticket(p_ticket_id, p_actor_auth_user_id) then
    return;
  end if;

  -- HRT-295 (ISS-2026-110 fix): created_by is genericized for a customer
  -- caller exactly the way app.list_customer_ticket_messages genericizes
  -- author_label -- a real staff creator shows "Support Team", never their
  -- raw internal auth_user_id. app.ticket_links carries no stored
  -- creator-role column (unlike app.ticket_messages.author_role, captured
  -- at INSERT time), so the branch is a LIVE app.is_ticket_staff re-check
  -- on the creator's own auth_user_id -- consistent with, not a departure
  -- from, this same function's own upstream app.list_ticket_links'
  -- established "never trust a stored value, always re-derive live"
  -- convention (its label/detail/status_label, decision 6 of the HRT-292
  -- migration). Disclosed, bounded limitation: a creator later offboarded
  -- (no longer ticket staff on ANY ticket) would show their own raw
  -- historical auth_user_id instead of "Support Team" here -- distinct from
  -- the live-reproduced defect this finding closes (an ACTIVE staff
  -- member's identity leaking to a customer on every ordinary read).
  -- entity_type/entity_id scope narrowing is deliberately unchanged from
  -- app.list_ticket_links (out of scope -- see ISS-2026-102).
  return query
  select
    l.id, l.entity_type, l.entity_id, l.relationship, l.status,
    (c.primary_label is not null) as live_available,
    c.primary_label, c.secondary_label,
    coalesce(c.status_label, 'unavailable'),
    l.created_at,
    case when app.is_ticket_staff(p_ticket_id, l.created_by_auth_user_id) then 'Support Team' else coalesce(l.created_by, 'You') end,
    l.record_version
  from app.ticket_links l
  left join lateral app._ticket_link_resolve_candidate(l.entity_type, v_ticket.tenant_id, p_actor_auth_user_id, l.entity_id) c on true
  where l.ticket_id = p_ticket_id and l.status = 'active'
  order by l.created_at asc;
end;
$$;

comment on function app.list_customer_ticket_links is
  'HRT-295 (ISS-2026-110 fix): the customer-safe app.list_ticket_links counterpart this workstream''s own established genericization convention (app.list_customer_ticket_messages'' "Support Team" substitution) was missing for linked-record created_by. created_by is a LIVE app.is_ticket_staff re-check on the creator''s auth_user_id (app.ticket_links has no stored creator-role column) -- a real staff creator always shows "Support Team", never a raw internal auth_user_id. Every other column is byte-identical to app.list_ticket_links -- entity_type/entity_id scope narrowing is the separate, already-registered ISS-2026-102, not this finding.';

revoke execute on all functions in schema app from public;

grant execute on function app.list_customer_ticket_links(uuid, uuid) to authenticated, service_role;
