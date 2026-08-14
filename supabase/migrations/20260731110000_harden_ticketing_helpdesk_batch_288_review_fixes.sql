-- Tier C batch review fix pass for CG-S12-HRT-016 (Prompt 288, Tenant-to-
-- CargoGrid Helpdesk). Additive only -- does NOT edit 20260731100000 (or any
-- prior ticketing migration) in place, per BUILD_EXECUTION_PROTOCOL.md §5.
--
-- Fixes three independently CONFIRMED (live-reproduced against a real
-- disposable Postgres 16 database, not accepted from lens citation alone,
-- per §5.3) findings from the four-lens adversarial review of commit
-- e9185f2, plus one cheap in-scope LOW completeness gap. The two highest-
-- priority properties this prompt exists to guarantee -- "a support ticket
-- alone grants no tenant business-data access" and "an expired/revoked
-- support access grant, even correlated to a ticket, confers nothing" --
-- were independently re-derived live against this same database (active,
-- expired, AND revoked grants all probed directly) and CONFIRMED to hold,
-- unaffected by anything below; no fix was needed for either. See
-- docs/build-log/phase-07/HRT-288.md §15 (Tier C batch review) for full
-- live-reproduction evidence of every disposition below.
--
--   Fix 1 (HIGH -- correctness/concurrency lens) -- app.reply_to_ticket's
--   idempotency replay match (both the pre-check SELECT and the
--   unique_violation recovery SELECT) and the underlying
--   ticket_messages_idempotency_unique index key on
--   (tenant_id, ticket_id, idempotency_key) did not include the posting
--   actor. Two DIFFERENT, independently-authorized requester-side (or
--   staff-side) identities on the SAME ticket who coincidentally reused one
--   idempotency key with matching visibility+body were silently collapsed
--   into a single row -- the second caller's genuine, distinct reply was
--   discarded with no error, misattributed to the first caller, and
--   reported as success. Live-reproduced on the helpdesk channel (this
--   checkpoint's own new app.reply_to_helpdesk_ticket entry point, via the
--   shared app.reply_to_ticket it delegates to) with two distinct,
--   independently-authorized tenant-side identities (a tenant_admin and a
--   TKT:Edit holder), and independently re-reproduced on the pre-existing
--   customer channel with two distinct customer_user account members,
--   proving one shared root cause across all three ticket channels, not a
--   helpdesk-only regression -- but one this checkpoint's own new surface
--   inherited and shipped unfixed. Mirrors the identical, already-
--   established HRT-287 precedent for ticket CREATION (decision to key
--   idempotency on the actor, not merely the natural business key) applied
--   here to ticket REPLY, the one place in the ticket-message idempotency
--   design that precedent had not yet reached.
--
--   Fix 2 (MEDIUM -- spec-compliance lens) -- app.add_ticket_watcher /
--   app.remove_ticket_watcher were the one staff-lifecycle RPC pairing this
--   migration's own design discipline (decision 6: "the three existing
--   generic staff-lifecycle RPCs explicitly REJECT a helpdesk-channel
--   ticket... dedicated, Supreme-Admin-gated siblings exist instead")
--   did NOT extend to. Their channel dispatch was a two-way
--   if/elsif ('customer' / else), so a third channel (helpdesk) silently
--   fell into the generic "requester-or-staff" elsif branch instead of
--   being rejected -- and because a helpdesk ticket's
--   app._is_ticket_requester_party is true for any tenant_admin/TKT:Edit
--   holder (decision 4: the tenant itself is the requester), an ordinary
--   tenant admin could call app.add_ticket_watcher directly and insert a
--   real app.ticket_watchers row -- an employee-participant mechanism --
--   against a channel whose entire design principle is that no employee is
--   ever a participant. Live-reproduced: a tkh1 tenant_admin successfully
--   added a tkh1 employee as a watcher on a real helpdesk ticket. No live
--   confidentiality breach chained from this today (every read path --
--   RLS, every staff-facing projection RPC, and reply_to_ticket/
--   redact_ticket_message/_ticket_transition_authority -- independently
--   excludes/re-checks the helpdesk channel or gates on is_requester/
--   is_staff specifically, never watcher status alone), but it is a
--   genuine, silent, previously-untested crack in the one predicate
--   (app.can_access_ticket) this whole capability is chartered to keep
--   sound, reachable by any ordinary tenant admin.
--
--   Fix 3 (MEDIUM -- security lens) -- app.ticket_channel_of, added purely
--   as small RLS-policy support (to let ticket_messages/ticket_watchers/
--   ticket_events' SELECT policies apply the same helpdesk exclusion
--   app.tickets' own policy applies directly), was granted EXECUTE to
--   authenticated with zero scoping of its own -- `select channel from
--   app.tickets where id = p_ticket_id`, callable directly as an ordinary
--   RPC by ANY authenticated identity, including one with zero
--   principal_membership/tenant relationship anywhere in the system.
--   Live-reproduced: an identity with no relationship to tenant tkh1 at
--   all directly called app.ticket_channel_of on a real tkh1 helpdesk
--   ticket id and received 'helpdesk' back -- confirming both the ticket's
--   existence and its channel, for any tenant, to anyone who obtains a
--   ticket UUID from any side channel. This directly contradicts the
--   anti-enumeration discipline this same migration establishes everywhere
--   else (e.g. app.get_tenant_helpdesk_ticket's own "not-found and
--   access-denied are indistinguishable" comment). Fixed by making the
--   function itself apply the same access check its RLS callers already
--   AND it with -- a caller who does not already pass app.can_access_ticket
--   (or hold Supreme Admin) now gets NULL, identical to what a genuinely
--   nonexistent ticket id already produced, exactly like every other
--   oracle-shaped read in this capability. Provably behavior-preserving
--   for the original RLS use: every policy that calls
--   app.ticket_channel_of() ANDs it with app.can_access_ticket() on the
--   very same ticket id already, so a genuine participant's result is
--   unchanged.
--
--   Fix 4 (LOW -- spec-compliance lens, cheap/in-scope) --
--   app.list_platform_helpdesk_tickets had no p_product_area filter
--   parameter (nor an index on product_area) despite the prompt's own
--   §17 explicitly naming "product" alongside severity/status/queue/
--   assignee in its indexed-filter list. Added as a trailing, defaulted
--   parameter (backward compatible with the existing named-parameter
--   PostgREST RPC call in server/queries/ticketing.ts -- no caller
--   breakage) plus a supporting partial index. The Platform helpdesk queue
--   page itself does not yet wire ANY server-side filter into its UI
--   (status/severity, already present in the TS options type, are
--   similarly unused there today) -- that remains a disclosed, pre-existing
--   page-level enhancement, not something this fix's scope extends to.
--
-- Both HIGH/MEDIUM findings are described in full, with live-reproduction
-- evidence, in docs/build-log/phase-07/HRT-288.md §15 (Tier C batch
-- review).

-- ===========================================================================
-- Fix 1a: ticket_messages_idempotency_unique -- add author_auth_user_id to
-- the key, mirroring the HRT-287 tickets_idempotency_customer_unique
-- precedent exactly (dedupe a single ACTOR's double-submit, never conflate
-- two different people who happen to reuse the same key).
-- ===========================================================================

drop index if exists app.ticket_messages_idempotency_unique;
create unique index ticket_messages_idempotency_unique on app.ticket_messages (tenant_id, ticket_id, author_auth_user_id, idempotency_key) where idempotency_key is not null;

-- ===========================================================================
-- Fix 1b: app.reply_to_ticket -- both the pre-check replay SELECT and the
-- unique_violation recovery SELECT now match on author_auth_user_id too.
-- Signature unchanged (grants preserved); behavior for a single actor
-- reusing their own key is byte-identical to before.
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
  'HRT-286 (decision 3), corrected at the CG-S12-HRT-016 Tier C batch review: requester or ticket staff may post; ONLY staff may set visibility=internal (enforced here, at write time -- the RLS policy on app.ticket_messages enforces the SAME rule at read time). Never changes app.tickets.status as a side effect (decision 6) -- status is always a separate, explicit app.transition_ticket_status call. Idempotency replay is keyed on (tenant_id, ticket_id, author_auth_user_id, idempotency_key) -- Tier C finding: the author was previously omitted from both the match logic and ticket_messages_idempotency_unique, so two different, independently-authorized participants on the same ticket who coincidentally reused one idempotency key with matching visibility/body were silently collapsed into a single row, discarding the second caller''s genuine reply with no error and misattributing it to the first caller. See ticket_messages_idempotency_unique.';

-- ===========================================================================
-- Fix 2: app.add_ticket_watcher / app.remove_ticket_watcher -- add the same
-- explicit helpdesk-channel rejection every other channel-inapplicable
-- staff-lifecycle RPC in this domain already carries (assign_ticket/
-- transfer_ticket_queue/update_ticket_classification, all added by
-- 20260731100000 itself). Watchers are, by design (decision 4/8), an
-- employee-participant mechanism with no helpdesk analogue at all (unlike
-- assign/transfer/classify, there is no dedicated Supreme-Admin-gated
-- helpdesk sibling for watchers -- the capability simply does not apply to
-- a channel where "the tenant itself is the requester, never a specific
-- employee/account row" and staff is Supreme-Admin-only with no notion of
-- an internal watcher roster).
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

  select * into v_ticket from app.tickets where id = p_ticket_id;
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
  'HRT-286 (decisions 3/8), corrected at the CG-S12-HRT-016 Tier C batch review: generalized identity resolution, staff-only for a customer-channel ticket. Explicitly REJECTS a helpdesk-channel ticket (Tier C finding: previously fell through to the generic requester-or-staff elsif branch, and since a helpdesk ticket''s own tenant_admin/TKT:Edit holder legitimately IS the requester party, an ordinary tenant admin could insert a real employee-participant watcher row against a channel whose whole design principle is that no employee is ever a participant) -- watchers have no helpdesk analogue at all, unlike assign/transfer/classify which each have a dedicated Supreme-Admin-gated sibling.';

create or replace function app.remove_ticket_watcher(p_watcher_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text)
returns app.ticket_watchers
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_row app.ticket_watchers;
  v_ticket app.tickets;
  v_is_requester boolean;
  v_is_staff boolean;
  v_is_self_watcher boolean;
  v_self app.employees;
  v_updated app.ticket_watchers;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  select * into v_row from app.ticket_watchers where id = p_watcher_id for update;
  if not found then
    raise exception 'ticket_watcher_not_found: %', p_watcher_id using errcode = 'no_data_found';
  end if;
  select * into v_ticket from app.tickets where id = v_row.ticket_id;

  if not app.can_access_ticket(v_ticket.id, p_actor_auth_user_id) then
    raise exception 'ticket_watcher_not_found: %', p_watcher_id using errcode = 'no_data_found';
  end if;

  if v_ticket.channel = 'helpdesk' then
    raise exception 'channel_not_supported: ticket % is a helpdesk case -- ticket watchers are an employee-participant mechanism that does not apply to the tenant-as-requester helpdesk model', v_ticket.id
      using errcode = 'check_violation';
  end if;

  v_is_staff := app.is_ticket_staff(v_ticket.id, p_actor_auth_user_id);
  v_is_requester := app._is_ticket_requester_party(v_ticket, p_actor_auth_user_id);
  v_self := app.get_self_employee(v_ticket.tenant_id, p_actor_auth_user_id);
  v_is_self_watcher := v_self.master_record_id is not null and v_self.master_record_id = v_row.employee_id;

  if v_ticket.channel = 'customer' then
    if not (v_is_staff or v_is_self_watcher) then
      raise exception 'insufficient_authority: identity % may not remove watcher %', p_actor_auth_user_id, p_watcher_id
        using errcode = 'insufficient_privilege';
    end if;
  elsif not (v_is_requester or v_is_staff or v_is_self_watcher) then
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

comment on function app.remove_ticket_watcher is
  'HRT-286, corrected at the CG-S12-HRT-016 Tier C batch review: explicitly REJECTS a helpdesk-channel ticket, mirroring app.add_ticket_watcher''s own Tier C fix -- see its comment for the full defect this closes.';

-- ===========================================================================
-- Fix 3: app.ticket_channel_of -- close the unscoped direct-RPC oracle.
-- The function now returns a channel only when the caller already passes
-- app.can_access_ticket for that same ticket id, or holds Supreme Admin --
-- otherwise NULL, indistinguishable from a genuinely nonexistent ticket id,
-- matching the anti-enumeration discipline this migration establishes
-- everywhere else. Every RLS policy that calls this function already ANDs
-- it with app.can_access_ticket(ticket_id) on the identical ticket id, so a
-- genuine participant's result is byte-identical to before; only the
-- previously-unscoped direct-RPC path (any authenticated identity, zero
-- relationship to the ticket, calling app.ticket_channel_of directly) is
-- affected.
-- ===========================================================================

create or replace function app.ticket_channel_of(p_ticket_id uuid)
returns text
language sql
stable
security definer
set search_path = app, pg_temp
as $$
  select channel from app.tickets
  where id = p_ticket_id
    and (app.can_access_ticket(id) or app.is_supreme_admin());
$$;

comment on function app.ticket_channel_of is
  'HRT-288, corrected at the CG-S12-HRT-016 Tier C batch review: small RLS-support helper -- the channel of a given ticket id, used by the ticket_messages/ticket_watchers/ticket_events SELECT policies (which have no channel column of their own) to apply the same helpdesk exclusion app.tickets'' own policy applies directly. Tier C finding: originally granted EXECUTE to authenticated with no scoping of its own, making it a directly-callable, unscoped cross-tenant ticket-existence-and-channel oracle for ANY authenticated identity regardless of relationship to the ticket. Now returns NULL (indistinguishable from a genuinely nonexistent id) unless the caller already passes app.can_access_ticket for this same ticket, or holds Supreme Admin -- provably behavior-preserving for every existing RLS caller, which already ANDs this function with app.can_access_ticket(ticket_id) on the identical id.';

-- ===========================================================================
-- Fix 4: app.list_platform_helpdesk_tickets -- add a p_product_area filter
-- parameter (trailing, defaulted -- backward compatible with the existing
-- named-parameter RPC call site) and a supporting partial index, per the
-- prompt's own §17 indexed-filter list ("severity/product/status/queue/
-- assignee/updated time").
-- ===========================================================================

create index tickets_helpdesk_product_area_idx on app.tickets (product_area, created_at desc) where channel = 'helpdesk' and product_area is not null;

-- create or replace cannot add a new trailing parameter to an existing
-- function without leaving the old signature as a separate, still-callable
-- overload (Postgres resolves an exact-arity call to the no-default
-- overload in preference to the new one, silently leaving this fix inert
-- for existing callers) -- so the old 7-parameter signature is dropped
-- explicitly before the 8-parameter replacement is created.
drop function if exists app.list_platform_helpdesk_tickets(uuid, text, text, uuid, uuid, integer, uuid);

create function app.list_platform_helpdesk_tickets(
  p_actor_auth_user_id uuid, p_status text, p_severity text, p_support_queue_id uuid, p_tenant_id uuid,
  p_limit integer, p_after_id uuid, p_product_area text default null
)
returns table (
  id uuid, ticket_number text, tenant_id uuid, tenant_name text, subject text, status text, priority text,
  severity text, product_area text, support_queue_id uuid, support_queue_code text,
  assignee_support_auth_user_id uuid, assignee_email text, support_access_case_ref text,
  record_version integer, created_at timestamptz, updated_at timestamptz
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
  if not app.is_supreme_admin(p_actor_auth_user_id) then
    return;
  end if;

  if p_after_id is not null then
    select t0.created_at into v_after_created_at from app.tickets t0 where t0.id = p_after_id;
  end if;

  return query
  select t.id, t.ticket_number, t.tenant_id, tn.name, t.subject, t.status, t.priority,
         t.severity, t.product_area, t.support_queue_id, sq.code,
         t.assignee_support_auth_user_id, au.email, t.support_access_case_ref,
         t.record_version, t.created_at, t.updated_at
  from app.tickets t
  join app.tenants tn on tn.id = t.tenant_id
  left join app.support_queues sq on sq.id = t.support_queue_id
  left join auth.users au on au.id = t.assignee_support_auth_user_id
  where t.channel = 'helpdesk'
    and (p_status is null or t.status = p_status)
    and (p_severity is null or t.severity = p_severity)
    and (p_support_queue_id is null or t.support_queue_id = p_support_queue_id)
    and (p_tenant_id is null or t.tenant_id = p_tenant_id)
    and (p_product_area is null or t.product_area = p_product_area)
    and (p_after_id is null or t.created_at < v_after_created_at or (t.created_at = v_after_created_at and t.id < p_after_id))
  order by t.created_at desc, t.id desc
  limit v_limit;
end;
$$;

comment on function app.list_platform_helpdesk_tickets is
  'HRT-288 (decisions 2/3/7), corrected at the CG-S12-HRT-016 Tier C batch review: the one deliberate cross-tenant read surface this capability introduces, strictly bounded to channel=''helpdesk'' and Supreme-Admin-only (returns zero rows, not an error, for a non-Supreme-Admin caller). p_product_area added as a trailing defaulted parameter (Tier C finding: the prompt''s own indexed-filter list named product_area alongside severity/status/queue, but no filter parameter or index existed for it) -- backward compatible with the pre-existing named-parameter RPC call site in server/queries/ticketing.ts.';

grant execute on function app.list_platform_helpdesk_tickets(uuid, text, text, uuid, uuid, integer, uuid, text) to authenticated, service_role;
