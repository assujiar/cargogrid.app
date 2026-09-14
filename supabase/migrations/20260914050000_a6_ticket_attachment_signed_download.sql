-- CG-AUDIT-2026-09-02 A6: extends the signed-download pattern
-- (20260914020000_a6_vendor_compliance_signed_download.sql,
-- 20260914040000_a6_shipment_document_checklist_signed_download.sql) to
-- ticket-reply attachments -- upload+scan for this record type was already
-- wired (20260914030000_a6_ticket_attachment_upload_scan.sql), so an
-- attachment a requester or staff member posts is real, malware-scanned
-- bytes; there was simply no way to ever fetch those bytes back out again.
-- ticket-detail-panel.tsx does not even render an attachment's filename
-- today, let alone a download control (confirmed live, this checkpoint's own
-- research: MessageBubble renders only body/author/timestamp).
--
-- Unlike the vendor-compliance/shipment-checklist pair, this record type has
-- NO dedicated, unused permission-action seam to reach for (OPS:Download was
-- exactly that seam for shipment checklists) -- ticket read access has
-- always been governed by app.can_access_ticket (staff OR the ticket's own
-- requester OR an active watcher, 20260731060000's own decision 5) plus, for
-- one specific message, app.ticket_messages.visibility (public vs.
-- internal-staff-only, decision 3). This migration reuses BOTH of those
-- existing primitives directly rather than introducing a new authority
-- concept:
--   1. app.can_access_ticket(ticket_id, actor) -- the same baseline gate
--      app.list_ticket_messages/app.list_customer_ticket_messages
--      (20260801320000) both already apply.
--   2. the SAME 'visibility = public or app.is_ticket_staff(...)' predicate
--      those two functions filter their own message rows by (decision 3),
--      applied here to the ONE ticket_messages row that actually references
--      this file_id in its attachment_file_ids array -- a customer-layer
--      requester can never mint a download link for an attachment on an
--      internal-only staff note, exactly as they can never see that note's
--      body today.
--   3. the SAME helpdesk-channel-is-Supreme-Admin-only hard block
--      app.list_ticket_messages applies (decision 1/HRT-286 extension,
--      20260731100000) -- a non-Supreme-Admin who is otherwise ticket staff
--      still never reaches a helpdesk-channel attachment through this path,
--      matching that they never reach the channel's messages either.
-- Deliberately NOT the app.actor_holds_customer_user_layer exclusion
-- app.list_ticket_messages also applies: that exclusion exists so a
-- customer-layer caller cannot consume the STAFF-facing listing (which
-- reveals internal-note existence, real staff author identities, etc.)
-- wholesale -- a customer-layer caller has its own parallel
-- list_customer_ticket_messages instead. This function is not a listing; it
-- authorizes exactly one already-known file_id against exactly one
-- already-resolved message's own visibility, so the SAME protection that
-- exclusion provides falls naturally out of gate 2 above (a customer-layer
-- caller can only ever download a public-visibility attachment) without
-- needing a caller-type distinction. This also means the one RPC below is
-- usable, unmodified, by a future customer-portal-side download action too
-- (customer-ticket-detail-panel.tsx has no attachment UI at all today,
-- confirmed live -- out of scope for this migration, which wires the
-- staff-facing panel only).
--
-- app.authorize_ticket_attachment_evidence_file_access is a narrowly-scoped
-- sibling of app.authorize_vendor_evidence_file_access /
-- app.authorize_shipment_document_evidence_file_access -- identical
-- malware-scan/deleted-file/restricted-classification gates, duplicated
-- rather than shared (same reasoning both precedents already disclose: a
-- reviewer reading this function alone sees its complete grant surface and
-- behavior without tracing an EXECUTE grant through a second function with a
-- different grant boundary). record-scope is omitted for the same reason as
-- both precedents: the caller (app.access_ticket_attachment_evidence_for_
-- download) has already independently verified can_access_ticket +
-- message-visibility scope before ever calling this.

create function app.authorize_ticket_attachment_evidence_file_access(
  p_file_id uuid,
  p_access_type text,
  p_actor_auth_user_id uuid,
  p_correlation_id uuid default null
)
returns app.file_access_logs
language plpgsql
as $$
declare
  v_file app.files;
  v_result text;
  v_reason text;
  v_log app.file_access_logs;
begin
  select * into v_file from app.files where id = p_file_id;
  if not found then
    raise exception 'document_file_not_found: no file %', p_file_id
      using errcode = 'no_data_found';
  end if;

  if not app.check_file_action_authority(v_file.tenant_id, p_actor_auth_user_id) then
    raise exception 'file_actor_unauthorized: identity % lacks active membership in tenant %', p_actor_auth_user_id, v_file.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if not (p_access_type = any (array['signed_url_issued', 'download', 'metadata_view'])) then
    raise exception 'document_access_type_invalid: % is not one of signed_url_issued/download/metadata_view', p_access_type
      using errcode = 'check_violation';
  end if;

  v_result := 'granted';
  v_reason := null;

  if p_access_type <> 'metadata_view' then
    if v_file.deleted_at is not null and not (app.is_supreme_admin(p_actor_auth_user_id) or app.is_support_grant_authority(p_actor_auth_user_id, v_file.tenant_id)) then
      v_result := 'denied';
      v_reason := 'document_deleted';
    elsif v_file.malware_scan_status = 'infected' then
      v_result := 'denied';
      v_reason := 'document_infected_quarantined';
    elsif v_file.malware_scan_status <> 'clean' and v_file.uploaded_by_auth_user_id <> p_actor_auth_user_id then
      v_result := 'denied';
      v_reason := 'document_not_yet_scanned';
    end if;
  end if;

  -- Record-scope (ticket-participation/message-visibility) is deliberately
  -- omitted, same reasoning as both precedent siblings: the caller
  -- (app.access_ticket_attachment_evidence_for_download) has already
  -- independently verified app.can_access_ticket PLUS the linked message's
  -- own visibility scope -- a second, narrower ownership condition on the
  -- underlying file itself is not this workflow's own bar.
  if v_result = 'granted' and v_file.classification in ('restricted', 'credential') and v_file.uploaded_by_auth_user_id <> p_actor_auth_user_id then
    if not (app.is_supreme_admin(p_actor_auth_user_id) or app.is_support_grant_authority(p_actor_auth_user_id, v_file.tenant_id)) then
      v_result := 'denied';
      v_reason := 'document_classification_access_denied';
    end if;
  end if;

  insert into app.file_access_logs (tenant_id, file_id, accessed_by_auth_user_id, access_type, result, reason, correlation_id)
  values (v_file.tenant_id, v_file.id, p_actor_auth_user_id, p_access_type, v_result, v_reason, p_correlation_id)
  returning * into v_log;

  return v_log;
end;
$$;

comment on function app.authorize_ticket_attachment_evidence_file_access is
  'CG-AUDIT-2026-09-02 A6: narrowly-scoped sibling of app.authorize_vendor_evidence_file_access/app.authorize_shipment_document_evidence_file_access for ticket-attachment evidence only. Identical malware-scan + deleted-file + restricted/credential-classification gates; the record-scope (ticket-participation/message-visibility) gate is intentionally omitted since the caller has already verified app.can_access_ticket plus the linked ticket_messages row''s own visibility scope.';

revoke execute on function app.authorize_ticket_attachment_evidence_file_access(uuid, text, uuid, uuid) from public;
grant execute on function app.authorize_ticket_attachment_evidence_file_access(uuid, text, uuid, uuid) to service_role;

-- app.authorize_ticket_attachment_evidence_file_access is language plpgsql
-- with no security clause, i.e. INVOKER mode -- matching both precedent
-- siblings exactly. scripts/db-tests/public-api-wrapper-regression.sql
-- asserts exhaustively that no public.* wrapper's security mode
-- (definer/invoker) ever differs from its app.* counterpart, so this wrapper
-- carries no `security definer` either.
create function public.authorize_ticket_attachment_evidence_file_access(
  p_file_id uuid, p_access_type text, p_actor_auth_user_id uuid, p_correlation_id uuid DEFAULT NULL::uuid
)
returns app.file_access_logs
language sql
volatile
set search_path = pg_catalog, pg_temp
as $wrap$
  select app.authorize_ticket_attachment_evidence_file_access(p_file_id, p_access_type, p_actor_auth_user_id, p_correlation_id);
$wrap$;

comment on function public.authorize_ticket_attachment_evidence_file_access(p_file_id uuid, p_access_type text, p_actor_auth_user_id uuid, p_correlation_id uuid) is
  'RGL-394 Option-2 wrapper: app is not exposed to PostgREST; this is a thin invoker-mode pass-through to app.authorize_ticket_attachment_evidence_file_access (itself invoker-mode) with an identical (service_role-only) grant set, never a reimplementation.';

revoke execute on function public.authorize_ticket_attachment_evidence_file_access(uuid, text, uuid, uuid) from anon, authenticated, service_role, public;
grant execute on function public.authorize_ticket_attachment_evidence_file_access(uuid, text, uuid, uuid) to service_role;

create function app.access_ticket_attachment_evidence_for_download(
  p_file_id uuid, p_actor_auth_user_id uuid, p_actor_label text, p_correlation_id uuid default null
)
returns table (
  bucket_id text, storage_path text, original_filename text, mime_type text, access_result text, access_reason text
)
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_file app.files;
  v_ticket app.tickets;
  v_message app.ticket_messages;
  v_log app.file_access_logs;
begin
  select * into v_file from app.files where id = p_file_id and record_type = 'ticket' and document_type_code = 'ticket_attachment';
  if not found then
    raise exception 'ticket_attachment_not_found: %', p_file_id using errcode = 'no_data_found';
  end if;

  select * into v_ticket from app.tickets where id = v_file.record_id;
  if not found or not app.can_access_ticket(v_file.record_id, p_actor_auth_user_id) then
    raise exception 'ticket_attachment_not_found: %', p_file_id using errcode = 'no_data_found';
  end if;

  -- Mirrors app.list_ticket_messages' own hard block (20260731100000): a
  -- helpdesk-channel ticket's attachments are Supreme-Admin-eyes-only,
  -- regardless of other staff authority (queue membership, TKT:Edit,
  -- assignee) -- never a looser bar for download than for reading the
  -- message itself.
  if v_ticket.channel = 'helpdesk' and not app.is_supreme_admin(p_actor_auth_user_id) then
    raise exception 'ticket_attachment_not_found: %', p_file_id using errcode = 'no_data_found';
  end if;

  select * into v_message from app.ticket_messages
  where ticket_id = v_file.record_id and p_file_id = any(attachment_file_ids)
  order by created_at asc
  limit 1;
  if not found then
    raise exception 'ticket_attachment_not_linked: file % is not attached to any message on ticket %', p_file_id, v_file.record_id
      using errcode = 'check_violation';
  end if;

  -- The exact 'visibility = public or is_ticket_staff' predicate
  -- app.list_ticket_messages/app.list_customer_ticket_messages already
  -- filter message ROWS by (decision 3), applied here to the one message
  -- this file is actually attached to -- a requester/watcher can never
  -- download an attachment from an internal-only staff note, exactly as
  -- they can never read that note's body.
  if v_message.visibility = 'internal' and not app.is_ticket_staff(v_file.record_id, p_actor_auth_user_id) then
    raise exception 'ticket_attachment_not_found: %', p_file_id using errcode = 'no_data_found';
  end if;

  v_log := app.authorize_ticket_attachment_evidence_file_access(p_file_id, 'signed_url_issued', p_actor_auth_user_id, p_correlation_id);

  perform app.capture_audit_event(
    v_ticket.tenant_id, p_actor_auth_user_id, p_actor_label, 'access_ticket_attachment_evidence_for_download',
    'app.ticket_messages', v_message.id, case when v_log.result = 'granted' then 'success' else 'failure' end,
    v_log.reason, null, jsonb_build_object('access_type', 'signed_url_issued', 'result', v_log.result, 'file_id', p_file_id)
  );

  if v_log.result <> 'granted' then
    return query select null::text, null::text, null::text, null::text, v_log.result, v_log.reason;
    return;
  end if;

  return query
  select 'tenant-documents'::text, v_file.storage_path, v_file.original_filename, v_file.mime_type, v_log.result, v_log.reason;
end;
$$;

comment on function app.access_ticket_attachment_evidence_for_download is
  'CG-AUDIT-2026-09-02 A6: service_role-only signed-download RPC for one ticket-reply attachment. Gated by app.can_access_ticket (the same staff-or-requester-or-watcher baseline every ticket read RPC already uses), a helpdesk-channel Supreme-Admin-only hard block mirroring app.list_ticket_messages, and the linked ticket_messages row''s own visibility (public vs. internal-staff-only) -- then app.authorize_ticket_attachment_evidence_file_access''s own malware-scan/classification gate. Returns bucket_id/storage_path only once granted, so server-side code can mint a short-lived signed URL -- the browser never sees storage_path directly. Never granted to authenticated or anon.';

revoke execute on function app.access_ticket_attachment_evidence_for_download(uuid, uuid, text, uuid) from public;
grant execute on function app.access_ticket_attachment_evidence_for_download(uuid, uuid, text, uuid) to service_role;

create function public.access_ticket_attachment_evidence_for_download(
  p_file_id uuid, p_actor_auth_user_id uuid, p_actor_label text, p_correlation_id uuid DEFAULT NULL::uuid
)
returns TABLE(bucket_id text, storage_path text, original_filename text, mime_type text, access_result text, access_reason text)
language sql
volatile
security definer
set search_path = pg_catalog, pg_temp
as $wrap$
  select * from app.access_ticket_attachment_evidence_for_download(p_file_id, p_actor_auth_user_id, p_actor_label, p_correlation_id);
$wrap$;

comment on function public.access_ticket_attachment_evidence_for_download(p_file_id uuid, p_actor_auth_user_id uuid, p_actor_label text, p_correlation_id uuid) is
  'RGL-394 Option-2 wrapper: app is not exposed to PostgREST; this is a thin security-definer pass-through to app.access_ticket_attachment_evidence_for_download with an identical (service_role-only) grant set, never a reimplementation.';

revoke execute on function public.access_ticket_attachment_evidence_for_download(uuid, uuid, text, uuid) from anon, authenticated, service_role, public;
grant execute on function public.access_ticket_attachment_evidence_for_download(uuid, uuid, text, uuid) to service_role;
