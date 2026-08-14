-- Tier C batch review fix pass for CG-S12-HRT-015 (Prompt 287, Customer-to-
-- Tenant Ticket). Additive only -- does NOT edit 20260731080000 (or
-- 20260731060000/070000) in place, per BUILD_EXECUTION_PROTOCOL.md §5.
--
-- Fixes two independently CONFIRMED (live-reproduced against a real
-- disposable Postgres 16 database, not accepted from lens citation alone,
-- per §5.3) findings from the four-lens adversarial review of commit
-- f1225c6:
--
--   Fix 1 (HIGH -- spec-compliance lens Finding 1 / security lens Finding 1,
--   independently, identically) -- app.get_customer_ticket returned
--   resolution_summary/cancelled_reason/last_reopen_reason VERBATIM to the
--   customer. resolution_summary is, by construction
--   (app._ticket_transition_authority: 'resolved'/'closed' are never
--   requester_allowed), ALWAYS staff-authored -- so exposing it unconditionally
--   directly contradicts this exact prompt's own "support metadata...
--   remain hidden"/"internal notes never cross [the customer-safe
--   projection]" business rule the moment any staff member types an
--   internally-oriented rationale into an ordinary TKT:Close/TKT:Reopen
--   transition on a customer-channel ticket -- reproduced live twice
--   (resolve and reopen) in this review, both leaking verbatim,
--   zero test coverage, zero staff-facing warning. cancelled_reason/
--   last_reopen_reason are genuinely dual-authored (the SAME generic
--   app.transition_ticket_status services both a customer's own
--   self-cancel/self-reopen AND a staff-driven cancel/reopen on the
--   customer's behalf, decision 9) -- only the customer-authored case is
--   actually safe to echo back verbatim.
--
--   Fix 2 (HIGH -- correctness/concurrency lens, live-reproduced both
--   sequentially and under two genuinely concurrent OS psql processes) --
--   app._create_ticket's customer-channel idempotency match/replay logic
--   (both the pre-check SELECT and the unique_violation recovery SELECT)
--   and the underlying tickets_idempotency_customer_unique partial index
--   key on (tenant_id, requested_by_auth_user_id, idempotency_key) only --
--   never requester_customer_account_id. A customer_user actor legitimately
--   scoped to more than one account (decision 5/8 of 20260731080000 --
--   explicitly supported, not a fabricated edge case) who reuses one
--   idempotency key across two different-account requests with matching
--   subject/body/category/priority gets the second request silently
--   short-circuited to the first account's ticket -- no error, no row ever
--   created for the account actually requested, wrong account_id in the
--   response. The index comment's own stated rationale ("a second,
--   different company user reusing the same idempotency key by coincidence
--   must not be treated as a replay of someone else's request") addresses a
--   DIFFERENT scenario (two distinct people) and does not cover this one
--   (the SAME person, two different intended targets) -- not a deliberate
--   design choice, a genuine gap.
--
-- Both are described in full, with live-reproduction evidence, in
-- docs/build-log/phase-07/HRT-287.md §14 (Tier C batch review).

-- ===========================================================================
-- Fix 1a: track which channel-appropriate party actually authored
-- cancelled_reason/last_reopen_reason, so app.get_customer_ticket can tell
-- "the customer's own words" (safe to echo back) apart from "a staff
-- member's internally-oriented rationale" (never safe to echo back).
-- resolution_summary needs no such column -- it is unconditionally
-- staff-authored by construction, so it is simply never exposed to the
-- customer projection at all (see Fix 1c below).
-- ===========================================================================

alter table app.tickets
  add column cancelled_reason_authored_by_customer boolean not null default false,
  add column last_reopen_reason_authored_by_customer boolean not null default false;

comment on column app.tickets.cancelled_reason_authored_by_customer is
  'CG-S12-HRT-015 Tier C batch review fix (finding: staff-authored rationale text leak). true only when the actor who moved this ticket to cancelled was itself the requester-side party (app._is_ticket_requester_party) for a requester_allowed transition -- i.e. the customer''s own submitted text, not a staff member''s internal note. app.get_customer_ticket only echoes cancelled_reason back to the customer when this is true.';

comment on column app.tickets.last_reopen_reason_authored_by_customer is
  'CG-S12-HRT-015 Tier C batch review fix (finding: staff-authored rationale text leak). Same shape and purpose as cancelled_reason_authored_by_customer, for the reopen (closed/resolved -> open) transition.';

-- ===========================================================================
-- Fix 1b: app.transition_ticket_status -- populate the two new tracking
-- columns alongside the existing free-text columns, in the same
-- transition-scoped CASE expressions. Signature and every other behavior
-- byte-for-byte unchanged (grants preserved by CREATE OR REPLACE).
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
  v_actor_is_requester boolean;
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

  -- CG-S12-HRT-015 Tier C batch review fix: is the acting identity the
  -- ticket's own requester-side party (per channel, via
  -- app._is_ticket_requester_party)? Only relevant for cancel/reopen, the
  -- two transitions requester_allowed ever admits -- resolve/close never
  -- reach this branch as true (never requester_allowed).
  v_actor_is_requester := app._is_ticket_requester_party(v_ticket, p_actor_auth_user_id);

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
    cancelled_reason_authored_by_customer = case when p_to_status = 'cancelled' then v_actor_is_requester and v_ticket.channel = 'customer' else cancelled_reason_authored_by_customer end,
    reopen_count = case when v_is_reopen then reopen_count + 1 else reopen_count end,
    last_reopened_by = case when v_is_reopen then p_actor_label else last_reopened_by end,
    last_reopened_at = case when v_is_reopen then now() else last_reopened_at end,
    last_reopen_reason = case when v_is_reopen then p_reason else last_reopen_reason end,
    last_reopen_reason_authored_by_customer = case when v_is_reopen then v_actor_is_requester and v_ticket.channel = 'customer' else last_reopen_reason_authored_by_customer end
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
  'HRT-286 (decision 6), corrected at the CG-S12-HRT-014 Tier C batch review, corrected again at the CG-S12-HRT-015 Tier C batch review: the ONE generic lifecycle RPC. record_version is checked immediately after the existence/access checks, before the transition-graph lookup or the authority check, so a concurrent modification always surfaces as stale_version rather than a business-rule error derived from a re-read, already-changed row. Looks up (from_status, to_status) in app.ticket_status_transitions and rejects any pair with no matching row -- an invalid jump (e.g. new -> closed, or any transition out of cancelled) is structurally impossible. p_reason doubles as resolution_summary/cancelled_reason/last_reopen_reason depending on p_to_status -- never passed raw into capture_audit_event (decision 9); the real text lives only on app.tickets and app.ticket_events, both scoped no wider than the ticket itself. cancelled_reason_authored_by_customer/last_reopen_reason_authored_by_customer additionally record whether the acting identity was the ticket''s own requester-side party (customer channel only) -- app.get_customer_ticket uses these to echo the customer''s OWN words back but never a staff member''s internally-oriented rationale (CG-S12-HRT-015 Tier C finding: resolution_summary/cancelled_reason/last_reopen_reason were previously returned to the customer verbatim regardless of author).';

-- ===========================================================================
-- Fix 1c: app.get_customer_ticket -- resolution_summary is never exposed
-- (always staff-authored by construction); cancelled_reason/
-- last_reopen_reason are exposed ONLY when the new tracking columns show
-- the customer themself authored that specific piece of text. Column list,
-- staff-projection-exclusion (queue/assignee identity), and the anti-
-- enumeration channel-filter-before-scope-check ordering are all otherwise
-- byte-for-byte unchanged.
-- ===========================================================================

create or replace function app.get_customer_ticket(p_ticket_id uuid, p_actor_auth_user_id uuid)
returns table (
  id uuid, ticket_number text, subject text, status text, priority text,
  category_name text, account_id uuid, account_name text,
  resolution_summary text, cancelled_reason text, last_reopen_reason text,
  reopen_count integer, record_version integer,
  created_at timestamptz, updated_at timestamptz, resolved_at timestamptz, closed_at timestamptz
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

  -- Anti-enumeration: an internal-channel ticket id, another tenant's id,
  -- and a genuinely nonexistent id are ALL indistinguishable (zero rows) to
  -- a customer caller here -- the channel filter is applied FIRST, before
  -- any scope check, so this function never even evaluates
  -- can_access_ticket for a non-customer-channel ticket.
  select * into v_ticket from app.tickets t0 where t0.id = p_ticket_id and t0.channel = 'customer';
  if not found then
    return;
  end if;
  if not app.can_access_ticket(p_ticket_id, p_actor_auth_user_id) then
    return;
  end if;

  return query
  select t.id, t.ticket_number, t.subject, t.status, t.priority,
         c.name, t.requester_customer_account_id, a.legal_name,
         null::text,
         case when t.cancelled_reason_authored_by_customer then t.cancelled_reason else null end,
         case when t.last_reopen_reason_authored_by_customer then t.last_reopen_reason else null end,
         t.reopen_count, t.record_version,
         t.created_at, t.updated_at, t.resolved_at, t.closed_at
  from app.tickets t
  join app.ticket_categories c on c.id = t.category_id
  join app.accounts a on a.id = t.requester_customer_account_id
  where t.id = p_ticket_id;
end;
$$;

comment on function app.get_customer_ticket is
  'HRT-287 (decision 6), corrected at the CG-S12-HRT-015 Tier C batch review: the customer-safe ticket projection -- deliberately excludes queue_id/queue_code/queue_name (internal routing) and assignee_employee_id/assignee_name (internal staff identity), unlike app.get_ticket. resolution_summary is ALWAYS null here -- app._ticket_transition_authority never admits a requester-side actor into resolved/closed, so this column is unconditionally staff-authored and therefore never safe to echo back to a customer (Tier C finding: it previously leaked staff-internal rationale text verbatim on every resolve). cancelled_reason/last_reopen_reason ARE returned, but ONLY when app.tickets.cancelled_reason_authored_by_customer/last_reopen_reason_authored_by_customer is true -- i.e. only when the ticket''s own requester-side party (not staff acting on their behalf) authored that specific text; a staff-driven cancel/reopen on a customer''s ticket now returns null for that field instead of leaking the staff member''s internal note.';

-- ===========================================================================
-- Fix 2a: tickets_idempotency_customer_unique -- add
-- requester_customer_account_id to the key. The pre-existing index's own
-- rationale (dedupe a single ACTOR's double-submit, not conflate two
-- DIFFERENT people who happen to reuse the same key) is preserved --
-- adding the account id only distinguishes "the same actor filing on
-- behalf of two different accounts they both legitimately hold
-- customer_user membership on" (decision 5/8 of 20260731080000, a
-- genuinely supported multi-account scenario), which the original index
-- could not.
-- ===========================================================================

drop index if exists app.tickets_idempotency_customer_unique;
create unique index tickets_idempotency_customer_unique on app.tickets (tenant_id, requested_by_auth_user_id, requester_customer_account_id, idempotency_key) where idempotency_key is not null and channel = 'customer';

-- ===========================================================================
-- Fix 2b: app._create_ticket -- both the pre-check replay SELECT and the
-- unique_violation recovery SELECT now match on
-- requester_customer_account_id too, for the customer-channel branch (the
-- internal-channel branch, matching on requester_employee_id, was already
-- correct and is untouched). Signature unchanged (grants preserved).
-- ===========================================================================

create or replace function app._create_ticket(
  p_tenant_id uuid,
  p_channel text,
  p_requester_employee_id uuid,
  p_requester_customer_account_id uuid,
  p_category_id uuid,
  p_queue_id uuid,
  p_priority text,
  p_subject text,
  p_body text,
  p_idempotency_key text,
  p_actor_auth_user_id uuid,
  p_actor_label text
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
  if p_channel is null or not (p_channel = any (array['internal', 'customer'])) then
    raise exception 'invalid_channel: % is not one of internal/customer', p_channel using errcode = 'check_violation';
  end if;
  if p_channel = 'internal' then
    if p_requester_employee_id is null or p_requester_customer_account_id is not null then
      raise exception 'invalid_requester_identity: internal channel requires exactly a requester_employee_id' using errcode = 'check_violation';
    end if;
  else
    if p_requester_customer_account_id is null or p_requester_employee_id is not null then
      raise exception 'invalid_requester_identity: customer channel requires exactly a requester_customer_account_id' using errcode = 'check_violation';
    end if;
  end if;

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
    if p_channel = 'internal' then
      select * into v_existing from app.tickets
      where tenant_id = p_tenant_id and channel = 'internal' and requester_employee_id = p_requester_employee_id and idempotency_key = p_idempotency_key;
    else
      select * into v_existing from app.tickets
      where tenant_id = p_tenant_id and channel = 'customer' and requested_by_auth_user_id = p_actor_auth_user_id
        and requester_customer_account_id = p_requester_customer_account_id and idempotency_key = p_idempotency_key;
    end if;
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
      tenant_id, ticket_number, channel, category_id, queue_id, priority, subject, status,
      requester_employee_id, requester_customer_account_id, requested_by_auth_user_id, requested_by, idempotency_key, created_by
    ) values (
      p_tenant_id, v_number, p_channel, p_category_id, v_resolved_queue_id, v_priority, p_subject, 'new',
      p_requester_employee_id, p_requester_customer_account_id, p_actor_auth_user_id, p_actor_label, p_idempotency_key, p_actor_label
    )
    returning * into v_ticket;
  exception
    when unique_violation then
      if p_idempotency_key is not null then
        if p_channel = 'internal' then
          select * into v_ticket from app.tickets
          where tenant_id = p_tenant_id and channel = 'internal' and requester_employee_id = p_requester_employee_id and idempotency_key = p_idempotency_key;
        else
          select * into v_ticket from app.tickets
          where tenant_id = p_tenant_id and channel = 'customer' and requested_by_auth_user_id = p_actor_auth_user_id
            and requester_customer_account_id = p_requester_customer_account_id and idempotency_key = p_idempotency_key;
        end if;
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
  'HRT-286/287 (decision 4/ISS-2026-085 resolved), corrected at the CG-S12-HRT-015 Tier C batch review: the shared ticket-creation engine, taking a real p_channel and per-channel requester identity parameter, validated to be exactly one of employee/customer-account matching that channel (belt-and-suspenders alongside the table CHECK tickets_requester_identity_shape). Called by app.create_ticket/app.create_ticket_for_employee (channel:=''internal'') and app.create_customer_ticket (channel:=''customer''). Idempotency replay is keyed differently per channel: requester_employee_id for internal; requested_by_auth_user_id AND requester_customer_account_id for customer (Tier C finding: the account id was previously omitted from both the match logic and tickets_idempotency_customer_unique, so a customer_user actor legitimately scoped to more than one account who reused one idempotency key across two different-account requests with matching content got silently short-circuited to the first account''s ticket -- no row was ever created for the account actually requested) -- see tickets_idempotency_unique / tickets_idempotency_customer_unique.';
