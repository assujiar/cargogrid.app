-- CG-AUDIT-2026-09-02 A6, third and final of the audit's own 3 named deadlocked
-- flows -- vendor compliance document submission and shipment document checklist
-- uploads were already wired end to end this remediation series. Ticket-reply
-- attachments are actually WORSE than the other two: they are not merely stuck at
-- malware_scan_status='pending' forever, they are an outright, reproducible hard
-- failure today. app.reply_to_ticket (20260731270000_harden_ticketing_internal_
-- replayable_review_fixes_hrt295.sql:422) raises evidence_file_not_scanned for any
-- attached file whose malware_scan_status is not 'clean' -- and since nothing in
-- this codebase has ever called .storage.from(...).upload() or enqueued a
-- malware_scan job for a ticket attachment, NO file attached via
-- app.initiate_ticket_attachment_upload can ever reach 'clean'. Every real attempt
-- to post a ticket reply with an attachment fails outright with that error.
--
-- Why this needs a small new RPC rather than reusing the surat-jalan/checklist
-- pattern verbatim: those two flows call the raw app.initiate_file_upload
-- primitive directly through a service-role client, which returns the full row
-- (storage_path included) because that primitive is inherently service_role-only
-- anyway. Ticket attachments are different by design
-- (20260901120000_close_iss2026087_ticket_attachment_upload.sql's own header):
-- app.initiate_ticket_attachment_upload is deliberately `authenticated`-callable,
-- carrying its own per-ticket requester-or-staff authority check inline, and
-- deliberately returns a storage_path-less FileSummary projection for exactly that
-- reason -- so the Server Action never gets storage_path back from the call that
-- creates the file.
--
-- The fix is NOT "re-derive that same per-ticket authority check a second time" --
-- the actor already passed it the moment app.initiate_ticket_attachment_upload
-- itself succeeded, in the SAME request, for the SAME actor. What's actually needed
-- is much narrower: "hand back the storage_path of a file this exact actor just
-- uploaded as a ticket attachment" -- a plain ownership check
-- (uploaded_by_auth_user_id = the caller), not a ticket-participation check.
-- service_role-only, since storage_path itself still carries no column grant to
-- `authenticated` at all (Finding A, 20260814000000_harden_storage_signed_url_
-- audit_findings.sql) and this function's whole purpose is to read it.

create function app.get_ticket_attachment_storage_path(p_file_id uuid, p_actor_auth_user_id uuid)
returns text
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_file app.files;
begin
  select * into v_file from app.files
  where id = p_file_id and record_type = 'ticket' and document_type_code = 'ticket_attachment';

  if not found or v_file.uploaded_by_auth_user_id <> p_actor_auth_user_id then
    raise exception 'ticket_attachment_not_found: %', p_file_id using errcode = 'no_data_found';
  end if;

  return v_file.storage_path;
end;
$$;

comment on function app.get_ticket_attachment_storage_path is
  'CG-AUDIT-2026-09-02 A6: service_role-only, narrowly-scoped storage_path lookup for a ticket attachment the caller JUST uploaded via app.initiate_ticket_attachment_upload in the same request -- a plain uploaded_by_auth_user_id ownership check, never a re-derivation of that RPC''s own per-ticket requester-or-staff authority (already satisfied by the time this is called). ticket_attachment_not_found for a missing file, a wrong record_type/document_type_code, or a caller who did not upload it -- indistinguishable, existence-oracle-safe.';

revoke execute on function app.get_ticket_attachment_storage_path(uuid, uuid) from public;
grant execute on function app.get_ticket_attachment_storage_path(uuid, uuid) to service_role;

-- app is not exposed to PostgREST (supabase/config.toml: schemas = ["public",
-- "graphql_public"]) -- every RPC callable from application code needs a matching
-- public.* thin pass-through wrapper, the standing convention
-- 20260826000000_create_public_api_data_wrappers.sql established and
-- scripts/db-tests/public-api-wrapper-regression.sql enforces exhaustively.

create function public.get_ticket_attachment_storage_path(p_file_id uuid, p_actor_auth_user_id uuid)
returns text
language sql
volatile
security definer
set search_path = pg_catalog, pg_temp
as $wrap$
  select app.get_ticket_attachment_storage_path(p_file_id, p_actor_auth_user_id);
$wrap$;

comment on function public.get_ticket_attachment_storage_path(p_file_id uuid, p_actor_auth_user_id uuid) is
  'RGL-394 Option-2 wrapper: app is not exposed to PostgREST; this is a thin security-definer pass-through to app.get_ticket_attachment_storage_path with an identical (service_role-only) grant set, never a reimplementation.';

revoke execute on function public.get_ticket_attachment_storage_path(uuid, uuid) from anon, authenticated, service_role, public;
grant execute on function public.get_ticket_attachment_storage_path(uuid, uuid) to service_role;
