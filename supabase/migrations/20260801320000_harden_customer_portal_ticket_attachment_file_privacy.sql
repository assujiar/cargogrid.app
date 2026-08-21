-- Phase 8 Customer Portal and Loyalty (CPL-325, CG-S13-CPL-027, Prompt 325,
-- "Customer Portal and Loyalty Privacy Integrity Hardening") -- closes a
-- live-reproduced file-privacy gap: ticket attachments were the ONE file-
-- exposing surface in this repository that never re-verified live
-- malware-scan status at READ time and never wrote a single app.file_
-- access_logs row, unlike every sibling capability (app.get_customer_epod
-- CPL-307, app.get_customer_document CPL-308, app.get_customer_portal_
-- loyalty_reward CPL-320), each of which independently re-selects the file
-- row live and logs a 'metadata_view' app.file_access_logs row on every
-- exposure -- and each of which documents WHY: RPD-022's own disclosed
-- Supreme Admin absolute-CRUD residual risk means malware_scan_status is
-- not immutable-for-all even once a file is attached (CPL-307's own header,
-- "residual risk means malware_scan_status is not immutable-for-all even
-- once a capture reaches 'completed'").
--
-- Root cause, live-reproduced this checkpoint: app.list_customer_ticket_
-- messages (20260731080000_extend_ticketing_customer_channel.sql:1488) and
-- app.list_ticket_messages (currently active version:
-- 20260731100000_extend_ticketing_helpdesk_channel.sql:1746) both return
-- the raw `attachment_file_ids uuid[]` column straight from app.
-- ticket_messages with no re-check against app.files and no app.file_
-- access_logs insert anywhere in either body. A file attached while clean
-- (app.reply_to_ticket/app.reply_to_customer_ticket DO gate correctly at
-- attach time -- `evidence_file_infected`/`evidence_file_not_scanned`,
-- unaffected by this fix), later corrected to infected via RPD-022's own
-- disclosed exception path, remained permanently, silently exposed as a
-- live attachment reference to both the customer and staff through the
-- real, granted RPC surface -- reachable via a raw API call regardless of
-- whether the current portal UI renders an attachment-download affordance
-- (it does not, today -- app/(tenant)/[tenantSlug]/customer-tickets/
-- [ticketId]/customer-ticket-detail-panel.tsx has no attachment UI at all,
-- so today's blast radius is the RPC surface, not the shipped UI). No
-- forensic trail existed for a ticket-attachment view in any circumstance,
-- clean or not -- a real, undisclosed gap against RPD-032 and source spec
-- §18's audit-completeness requirement. This is NOT a cross-tenant leak
-- (the write-path already correctly tenant/record-scopes every attach) and
-- does not meet this checkpoint's own Critical-escalation bar
-- (balance/liability manipulation, double-spend, cross-tenant/cross-account
-- leak) -- rated High (a live, reachable, undisclosed gap in a mandatory
-- RPD-032/audit control, on a real granted RPC surface).
--
-- Fix (bounded, additive, `CREATE OR REPLACE FUNCTION` against identical
-- signatures -- the already-applied 20260731060000/20260731080000/
-- 20260731100000 files are never edited, mirrors this repository's own
-- established `harden_*.sql` precedent, e.g. 20260801160000/20260801260000):
-- both functions now live-re-verify EVERY referenced attachment against
-- app.files at read time -- identical tenant/record-scope/soft-delete/
-- malware-scan-status re-check app.get_customer_epod already uses
-- (20260801080000, decision documented at that migration's own header) --
-- and log one app.file_access_logs row per referenced file (granted or
-- denied, access_type='metadata_view', the same literal every other real
-- file-exposure call site in this repository uses). A file that fails
-- re-verification is FILTERED OUT of the returned attachment_file_ids array
-- (never an error, never a dropped message -- the message's own body/
-- author/timestamp are unaffected, mirroring app.get_customer_epod's own
-- non-raising "quarantined" pattern rather than app.reply_to_ticket's own
-- attach-time raising pattern, since a read is not a write and should not
-- fail a whole page load over one bad attachment). No new table, no new
-- column, no schema change -- app.file_access_logs/app.files already exist
-- (PLT-128, 20260719140000).
--
-- Regression coverage: a new block is added to scripts/db-tests/
-- ticketing-customer.sql, live-reproducing this checkpoint's own exact
-- finding (attach while clean, correct to infected post-attach via a
-- direct UPDATE simulating the disclosed RPD-022 exception path, confirm
-- the file id is no longer returned by either list function post-
-- correction, and confirm exactly one app.file_access_logs row per
-- exposure exists).

-- ===========================================================================
-- 1. app.list_customer_ticket_messages
-- ===========================================================================

create or replace function app.list_customer_ticket_messages(p_ticket_id uuid, p_actor_auth_user_id uuid, p_limit integer, p_after_id uuid)
returns table (
  id uuid, ticket_id uuid, body text, is_redacted boolean, attachment_file_ids uuid[],
  author_role text, author_display text, created_at timestamptz, record_version integer
)
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_ticket app.tickets;
  v_limit integer := least(greatest(coalesce(p_limit, 100), 1), 500);
  v_after_created_at timestamptz;
  v_row record;
  v_file app.files;
  v_file_id uuid;
  v_reason text;
  v_visible_file_ids uuid[];
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  select * into v_ticket from app.tickets t0 where t0.id = p_ticket_id and t0.channel = 'customer';
  if not found then
    return;
  end if;
  if not app.can_access_ticket(p_ticket_id, p_actor_auth_user_id) then
    return;
  end if;

  if p_after_id is not null then
    select m0.created_at into v_after_created_at from app.ticket_messages m0 where m0.id = p_after_id;
  end if;

  -- Decision 6 (unchanged): visibility is hard-filtered to 'public' -- this
  -- function accepts no visibility parameter at all, so an internal note
  -- can never reach a customer caller through this path structurally. A
  -- staff author's real name/label is replaced with a fixed generic label
  -- ('Support Team').
  for v_row in
    select m.id, m.ticket_id, m.body, m.is_redacted, m.attachment_file_ids,
           m.author_role,
           case when m.author_role = 'staff' then 'Support Team' else coalesce(m.author_label, 'You') end as author_display,
           m.created_at, m.record_version
    from app.ticket_messages m
    where m.ticket_id = p_ticket_id
      and m.visibility = 'public'
      and (p_after_id is null or m.created_at > v_after_created_at or (m.created_at = v_after_created_at and m.id > p_after_id))
    order by m.created_at asc, m.id asc
    limit v_limit
  loop
    -- CPL-325 fix (file-privacy hardening, this migration's own header):
    -- live-re-verify every referenced attachment against app.files, never
    -- trust app.reply_to_customer_ticket's own attach-time clean-scan
    -- invariant alone. Filters (never raises) on any file that is no
    -- longer a valid clean tenant/ticket-scoped attachment; logs one
    -- app.file_access_logs row per referenced file.
    v_visible_file_ids := '{}';
    foreach v_file_id in array coalesce(v_row.attachment_file_ids, '{}'::uuid[]) loop
      select * into v_file from app.files f where f.id = v_file_id;

      if v_file.id is null then
        v_reason := 'document_deleted';
      elsif v_file.tenant_id <> v_ticket.tenant_id or v_file.record_type <> 'ticket' or v_file.record_id <> p_ticket_id then
        v_reason := 'document_record_access_denied';
      elsif v_file.deleted_at is not null then
        v_reason := 'document_deleted';
      elsif v_file.malware_scan_status = 'infected' then
        v_reason := 'document_infected_quarantined';
      elsif v_file.malware_scan_status <> 'clean' then
        v_reason := 'document_not_yet_scanned';
      else
        v_reason := null;
      end if;

      if v_reason is null then
        v_visible_file_ids := v_visible_file_ids || v_file_id;
      end if;

      -- app.file_access_logs.file_id carries a real FK to app.files -- only
      -- logged when the file genuinely exists (mirrors app.get_customer_
      -- epod's own decision 3).
      if v_file.id is not null then
        insert into app.file_access_logs (tenant_id, file_id, accessed_by_auth_user_id, access_type, result, reason, correlation_id)
        values (v_ticket.tenant_id, v_file.id, p_actor_auth_user_id, 'metadata_view', case when v_reason is null then 'granted' else 'denied' end, v_reason, null);
      end if;
    end loop;

    id := v_row.id;
    ticket_id := v_row.ticket_id;
    body := v_row.body;
    is_redacted := v_row.is_redacted;
    attachment_file_ids := v_visible_file_ids;
    author_role := v_row.author_role;
    author_display := v_row.author_display;
    created_at := v_row.created_at;
    record_version := v_row.record_version;
    return next;
  end loop;
end;
$$;

comment on function app.list_customer_ticket_messages is
  'CPL-313, hardened at CPL-325 (file-privacy hardening, this migration): customer-safe ticket-message read, visibility hard-filtered to public, staff authors genericized to "Support Team". attachment_file_ids is now live-re-verified against app.files at READ time (tenant/record-scope/soft-delete/malware-scan-status), mirroring app.get_customer_epod''s own established pattern -- a file that fails re-verification is silently filtered out of the returned array (never an error, never a dropped message), and one app.file_access_logs row (metadata_view, granted/denied) is logged per referenced file.';

-- ===========================================================================
-- 2. app.list_ticket_messages (staff-facing; currently-active override from
--    20260731100000_extend_ticketing_helpdesk_channel.sql -- this migration
--    replaces that same signature, preserving every gate it already
--    applies: can_access_ticket, helpdesk-channel Supreme-Admin-only gate,
--    customer_user-layer structural exclusion).
-- ===========================================================================

create or replace function app.list_ticket_messages(p_ticket_id uuid, p_actor_auth_user_id uuid, p_limit integer, p_after_id uuid)
returns table (
  id uuid, ticket_id uuid, visibility text, body text, is_redacted boolean, attachment_file_ids uuid[],
  author_auth_user_id uuid, author_label text, author_role text, created_at timestamptz, record_version integer
)
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_tenant_id uuid;
  v_channel text;
  v_is_staff boolean;
  v_limit integer := least(greatest(coalesce(p_limit, 100), 1), 500);
  v_after_created_at timestamptz;
  v_row record;
  v_file app.files;
  v_file_id uuid;
  v_reason text;
  v_visible_file_ids uuid[];
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  if not app.can_access_ticket(p_ticket_id, p_actor_auth_user_id) then
    return;
  end if;
  select t0.tenant_id, t0.channel into v_tenant_id, v_channel from app.tickets t0 where t0.id = p_ticket_id;
  if v_channel = 'helpdesk' and not app.is_supreme_admin(p_actor_auth_user_id) then
    return;
  end if;
  if app.actor_holds_customer_user_layer(v_tenant_id, p_actor_auth_user_id) then
    return;
  end if;
  v_is_staff := app.is_ticket_staff(p_ticket_id, p_actor_auth_user_id);

  if p_after_id is not null then
    select m0.created_at into v_after_created_at from app.ticket_messages m0 where m0.id = p_after_id;
  end if;

  for v_row in
    select m.id, m.ticket_id, m.visibility, m.body, m.is_redacted, m.attachment_file_ids,
           m.author_auth_user_id, m.author_label, m.author_role, m.created_at, m.record_version
    from app.ticket_messages m
    where m.ticket_id = p_ticket_id
      and (m.visibility = 'public' or v_is_staff)
      and (p_after_id is null or m.created_at > v_after_created_at or (m.created_at = v_after_created_at and m.id > p_after_id))
    order by m.created_at asc, m.id asc
    limit v_limit
  loop
    -- CPL-325 fix (file-privacy hardening, see app.list_customer_ticket_
    -- messages above and this migration's own header for the full,
    -- disclosed reasoning) -- identical live-re-verification/filter/log
    -- shape, staff-facing side of the same gap.
    v_visible_file_ids := '{}';
    foreach v_file_id in array coalesce(v_row.attachment_file_ids, '{}'::uuid[]) loop
      select * into v_file from app.files f where f.id = v_file_id;

      if v_file.id is null then
        v_reason := 'document_deleted';
      elsif v_file.tenant_id <> v_tenant_id or v_file.record_type <> 'ticket' or v_file.record_id <> p_ticket_id then
        v_reason := 'document_record_access_denied';
      elsif v_file.deleted_at is not null then
        v_reason := 'document_deleted';
      elsif v_file.malware_scan_status = 'infected' then
        v_reason := 'document_infected_quarantined';
      elsif v_file.malware_scan_status <> 'clean' then
        v_reason := 'document_not_yet_scanned';
      else
        v_reason := null;
      end if;

      if v_reason is null then
        v_visible_file_ids := v_visible_file_ids || v_file_id;
      end if;

      if v_file.id is not null then
        insert into app.file_access_logs (tenant_id, file_id, accessed_by_auth_user_id, access_type, result, reason, correlation_id)
        values (v_tenant_id, v_file.id, p_actor_auth_user_id, 'metadata_view', case when v_reason is null then 'granted' else 'denied' end, v_reason, null);
      end if;
    end loop;

    id := v_row.id;
    ticket_id := v_row.ticket_id;
    visibility := v_row.visibility;
    body := v_row.body;
    is_redacted := v_row.is_redacted;
    attachment_file_ids := v_visible_file_ids;
    author_auth_user_id := v_row.author_auth_user_id;
    author_label := v_row.author_label;
    author_role := v_row.author_role;
    created_at := v_row.created_at;
    record_version := v_row.record_version;
    return next;
  end loop;
end;
$$;

comment on function app.list_ticket_messages is
  'HRT-286/287/288, extended by CPL-313 wiring, hardened at CPL-325 (file-privacy hardening, this migration): staff-facing ticket-message read (internal notes visible to staff only), helpdesk-channel Supreme-Admin-only, customer_user-layer structurally excluded. attachment_file_ids is now live-re-verified against app.files at READ time (tenant/record-scope/soft-delete/malware-scan-status), mirroring app.get_customer_epod''s own established pattern -- a file that fails re-verification is silently filtered out of the returned array, and one app.file_access_logs row (metadata_view, granted/denied) is logged per referenced file.';
