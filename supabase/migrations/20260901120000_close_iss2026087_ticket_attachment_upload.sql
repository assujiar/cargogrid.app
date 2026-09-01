-- ISS-2026-087 (docs/runtime/KNOWN_ISSUES.md): app/(tenant)/[tenantSlug]/tickets/
-- actions.ts hardcodes attachmentFileIds: null on ticket-reply submission, and
-- ticket-detail-panel.tsx has zero file-upload UI, even though app.reply_to_ticket's
-- own attachment parameter and its full malware-scan-gating logic are already real,
-- live, and DB-tested (scripts/db-tests/ticketing-internal.sql section 11).
--
-- Live-verified before writing this migration (Supabase Management API against
-- project awdlicmwzdxquopwtcfd, 2026-09-01):
--   * app.document_types ALREADY carries a 'ticket_attachment' row, and
--     app.config_types ALREADY carries a 'document:ticket_attachment' row -- both
--     registered directly by 20260731060000_create_ticketing_internal.sql's own
--     decision 8 (section 1 of that migration) when the ticketing domain was first
--     built, long before this checkpoint. NO new document-type/config-type
--     registration migration is needed here -- unlike ISS-2026-064 item 2 (HRIS) and
--     ISS-2026-131 item 3 (Loyalty), which each had to register a brand-new type. This
--     is the one place this task's own precedent does NOT repeat verbatim.
--   * Zero tenants have ever published an actual `document:ticket_attachment`
--     config_object -- app.config_objects has no row for this config_type_code
--     project-wide. Exactly the same disclosed gap ISS-2026-131's own migration
--     disclosed for 'reward_terms': every tenant's own publish step is a separate,
--     later, per-tenant admin action, out of this migration's scope. An upload
--     against a tenant with no published definition fails document_type_not_configured
--     (an existing, already-classified error code on this service layer) until that
--     tenant's own admin publishes one -- same shape section 15 of the source ticket
--     capability always had for any OTHER as-yet-unpublished document type.
--   * app.initiate_file_upload is service_role-only (confirmed via
--     information_schema.routine_privileges: only postgres/service_role hold EXECUTE,
--     `authenticated` does not) -- exactly the PLT-128 primitive's own coarse
--     tenant-membership-only gate (app.check_file_action_authority) both prior sibling
--     builds (HRIS/Loyalty) independently disclosed.
--   * app.can_access_ticket, app.is_ticket_staff, and app.reply_to_ticket ITSELF are
--     ALL granted to `authenticated` (both directly on app.* and via their
--     public.* RGL-394 wrappers, 20260826000000_create_public_api_data_wrappers.sql) --
--     this is the material fact that determines which of the two prior sibling
--     builds' shapes actually applies here, re-derived fresh rather than assumed:
--       - HRIS (ISS-2026-064 item 2) wrapped the raw primitive in ONE new
--         SECURITY DEFINER RPC carrying its own domain-authority check, granted
--         directly to `authenticated` -- appropriate there because app.evaluate_
--         permission (the authority primitive HRS:Edit needs) is ALSO service_role-
--         only, so no `authenticated`-callable pre-check existed to call separately;
--         the check had to move inside a new SECURITY DEFINER wrapper regardless.
--       - Loyalty (ISS-2026-131 item 3) instead called the raw primitive directly
--         from a service-role-mediated Server Action, with a SEPARATE service-role
--         pre-check (app.evaluate_permission for LYL:Create/Edit) run first -- for
--         the identical reason: evaluate_permission has no `authenticated`-callable
--         form either, so the check could not run through the ordinary RLS-scoped
--         client the rest of that Server Action otherwise uses.
--     Ticketing is neither of those: app.reply_to_ticket's OWN authority chain
--     (app.can_access_ticket for existence-oracle-safe scoping,
--     app._is_ticket_requester_party + app.is_ticket_staff for the actual
--     requester-or-staff bar, exactly the same three primitives reply_to_ticket
--     itself calls) is fully `authenticated`-reachable already. There is therefore no
--     reason to split a separate service-role pre-check out of the Server Action --
--     the HRIS shape (one new SECURITY DEFINER RPC, granted straight to
--     `authenticated`, doing its own check inline) is the correct one to follow here,
--     and app/(tenant)/[tenantSlug]/tickets/actions.ts below calls it through the
--     SAME createSupabaseServerClient() (RLS-scoped) client every other write in that
--     file already uses -- no new client type, no separate pre-check round trip.
--
-- app.initiate_ticket_attachment_upload is a new, narrow RPC that:
--   1. resolves the ticket by id under a `for update` row lock and folds "not found"
--      and "actor cannot access this ticket at all" into the SAME ticket_not_found
--      error app.reply_to_ticket itself already raises for the identical scenario
--      (C-05, existence-oracle-safe) -- a cross-tenant/unrelated-ticket probe learns
--      nothing a genuinely nonexistent ticket id wouldn't also produce.
--   2. refuses a cancelled or closed ticket (ticket_cancelled / ticket_closed) --
--      mirrors app.reply_to_ticket's own terminal-status guard byte-for-byte
--      (20260731270000's HRT-295 fix): an attachment that could never actually be
--      attached to a new reply is not worth letting a caller create.
--   3. requires the caller to be the requester-side party (app.
--      _is_ticket_requester_party) OR ticket staff (app.is_ticket_staff) -- the SAME
--      "insufficient_authority: ... is not a participant on ticket ..." bar
--      app.reply_to_ticket enforces for posting itself, not merely a looser
--      "can view this ticket" check (a plain watcher can see a ticket via
--      app.can_access_ticket but may not post -- and, by the same reasoning, may not
--      stage an attachment for a reply they cannot make either).
--   4. only then delegates to app.initiate_file_upload for the actual metadata
--      recording (MIME/size/classification validation, idempotency, audit) --
--      reimplementing none of that. document_type_code is hardcoded to
--      'ticket_attachment' and record_type/record_id are hardcoded to
--      'ticket'/<the locked ticket's own id> -- never caller-supplied -- exactly
--      app.reply_to_ticket's own later validation of an attached file
--      (`v_file.record_type <> 'ticket' or v_file.record_id <> p_ticket_id`) already
--      assumes. classification passes through as given (nullable), never a hardcoded
--      literal, so a tenant's own published default_classification always applies
--      when the caller does not name one -- identical discipline to both prior
--      sibling builds.
--
-- SECURITY DEFINER, `set search_path = app, pg_temp`, a blanket revoke-from-public
-- plus a targeted grant to authenticated + service_role, and a matching public.*
-- wrapper (RGL-394 Option 2) -- mirrors 20260901040000_close_iss2026064_hris_
-- employee_document_upload.sql's app.initiate_employee_document_upload /
-- public.initiate_employee_document_upload pair verbatim, this repository's own
-- current convention for exactly this shape (a brand-new domain RPC that performs
-- its own authority check and is called through the RLS-scoped client, not a raw
-- service-role-only primitive directly).
--
-- Returns a storage_path-less projection (server/contracts/document/document.ts's
-- FileSummary shape), same reasoning as the HRIS sibling: this RPC is callable
-- directly by `authenticated`, unlike app.initiate_file_upload itself, which still
-- returns the real storage_path (a service_role-only concern).

create function app.assert_ticket_attachment_upload_authority(p_ticket_id uuid, p_actor_auth_user_id uuid, out v_ticket app.tickets)
language plpgsql
as $$
declare
  v_is_requester boolean;
  v_is_staff boolean;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  select * into v_ticket from app.tickets where id = p_ticket_id for update;
  if not found then
    raise exception 'ticket_not_found: %', p_ticket_id using errcode = 'no_data_found';
  end if;

  -- C-05, mirrored from app.reply_to_ticket verbatim: a caller with no
  -- relationship to this ticket at all must get the SAME ticket_not_found a
  -- genuinely missing id would produce, never insufficient_authority (which
  -- would disclose that this ticket_id is real).
  if not app.can_access_ticket(p_ticket_id, p_actor_auth_user_id) then
    raise exception 'ticket_not_found: %', p_ticket_id using errcode = 'no_data_found';
  end if;

  if v_ticket.status = 'cancelled' then
    raise exception 'ticket_cancelled: cancelled ticket % cannot receive new attachments', p_ticket_id using errcode = 'check_violation';
  end if;
  if v_ticket.status = 'closed' then
    raise exception 'ticket_closed: closed ticket % cannot receive new attachments', p_ticket_id using errcode = 'check_violation';
  end if;

  v_is_requester := app._is_ticket_requester_party(v_ticket, p_actor_auth_user_id);
  v_is_staff := app.is_ticket_staff(p_ticket_id, p_actor_auth_user_id);
  if not (v_is_requester or v_is_staff) then
    raise exception 'insufficient_authority: identity % is not a participant on ticket %', p_actor_auth_user_id, p_ticket_id
      using errcode = 'insufficient_privilege';
  end if;
end;
$$;

comment on function app.assert_ticket_attachment_upload_authority is 'ISS-2026-087: shared authority+state precondition for a ticket-attachment upload -- ticket_not_found for a nonexistent/inaccessible ticket (C-05 existence-oracle-safe), ticket_cancelled/ticket_closed for a terminal ticket, insufficient_authority unless the caller is the requester-side party or ticket staff. Mirrors app.reply_to_ticket''s own inline checks byte-for-byte (see this migration''s own header) rather than re-deriving a looser bar.';

create function app.initiate_ticket_attachment_upload(
  p_ticket_id uuid,
  p_original_filename text,
  p_mime_type text,
  p_size_bytes bigint,
  p_classification text,
  p_idempotency_key text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns table (
  id uuid, tenant_id uuid, document_type_code text, config_version_id uuid, record_type text, record_id uuid,
  classification text, original_filename text, mime_type text, size_bytes bigint,
  malware_scan_status text, malware_scan_completed_at timestamptz, malware_scan_provider_ref text,
  version_group_id uuid, version_number integer, is_latest_version boolean, lifecycle_status text,
  legal_hold boolean, legal_hold_reason text, deleted_at timestamptz, uploaded_by_auth_user_id uuid,
  shared_org_unit_ids uuid[], customer_account_ref text, idempotency_key text, created_at timestamptz, updated_at timestamptz
)
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_ticket app.tickets;
  v_file app.files;
begin
  v_ticket := app.assert_ticket_attachment_upload_authority(p_ticket_id, p_actor_auth_user_id);

  v_file := app.initiate_file_upload(
    v_ticket.tenant_id, 'ticket_attachment', 'ticket', p_ticket_id,
    p_original_filename, p_mime_type, p_size_bytes, p_classification,
    false, null, '{}'::uuid[], null, p_idempotency_key, p_actor_auth_user_id, p_actor_label
  );

  return query select
    v_file.id, v_file.tenant_id, v_file.document_type_code, v_file.config_version_id, v_file.record_type, v_file.record_id,
    v_file.classification, v_file.original_filename, v_file.mime_type, v_file.size_bytes,
    v_file.malware_scan_status, v_file.malware_scan_completed_at, v_file.malware_scan_provider_ref,
    v_file.version_group_id, v_file.version_number, v_file.is_latest_version, v_file.lifecycle_status,
    v_file.legal_hold, v_file.legal_hold_reason, v_file.deleted_at, v_file.uploaded_by_auth_user_id,
    v_file.shared_org_unit_ids, v_file.customer_account_ref, v_file.idempotency_key, v_file.created_at, v_file.updated_at;
end;
$$;

comment on function app.initiate_ticket_attachment_upload is 'ISS-2026-087: requester-or-staff-gated ticket-attachment upload -- resolves and locks the ticket, checks the SAME participation bar app.reply_to_ticket itself enforces (never the raw app.initiate_file_upload primitive''s own coarse tenant-membership-only gate), then delegates to app.initiate_file_upload for MIME/size/classification validation, idempotency and audit. document_type_code/record_type/record_id are fixed server-side to ''ticket_attachment''/''ticket''/<the locked ticket''s own id> -- never caller-supplied. Returns a storage_path-less projection (server/contracts/document/document.ts''s FileSummary shape) since this is callable directly by `authenticated`, unlike the raw primitive.';

-- Every prior migration's own established convention (e.g. 20260901040000,
-- 20260730950000): a brand-new function created by this same migration-applying
-- role otherwise retains an implicit PUBLIC EXECUTE grant the moment any explicit
-- GRANT statement first materializes its ACL -- this blanket revoke is the actual
-- operative mechanism, not merely defense-in-depth. It also leaves
-- app.assert_ticket_attachment_upload_authority with NO grant at all (mirroring
-- app.assert_employee_document_upload_authority, which carries none either) --
-- callable only from within another SECURITY DEFINER function owned by the same
-- role, and deliberately never given its own public.* wrapper.
revoke execute on all functions in schema app from public;

grant execute on function app.initiate_ticket_attachment_upload(uuid, text, text, bigint, text, text, uuid, text) to authenticated, service_role;

-- public.* wrapper, security mode matching the app.* function exactly (RGL-394
-- Option 2). app is not exposed to PostgREST, so without this the function is
-- unreachable from the application.
create function public.initiate_ticket_attachment_upload(
  p_ticket_id uuid, p_original_filename text, p_mime_type text, p_size_bytes bigint,
  p_classification text, p_idempotency_key text, p_actor_auth_user_id uuid, p_actor_label text
)
returns table (
  id uuid, tenant_id uuid, document_type_code text, config_version_id uuid, record_type text, record_id uuid,
  classification text, original_filename text, mime_type text, size_bytes bigint,
  malware_scan_status text, malware_scan_completed_at timestamptz, malware_scan_provider_ref text,
  version_group_id uuid, version_number integer, is_latest_version boolean, lifecycle_status text,
  legal_hold boolean, legal_hold_reason text, deleted_at timestamptz, uploaded_by_auth_user_id uuid,
  shared_org_unit_ids uuid[], customer_account_ref text, idempotency_key text, created_at timestamptz, updated_at timestamptz
)
language sql
security definer
set search_path = app, public, pg_temp
as $wrap$
  select * from app.initiate_ticket_attachment_upload(p_ticket_id, p_original_filename, p_mime_type, p_size_bytes, p_classification, p_idempotency_key, p_actor_auth_user_id, p_actor_label);
$wrap$;

comment on function public.initiate_ticket_attachment_upload(uuid, text, text, bigint, text, text, uuid, text) is
  'RGL-394 Option-2 wrapper: app is not exposed to PostgREST; this is a thin security-definer pass-through to app.initiate_ticket_attachment_upload, never a reimplementation.';

revoke execute on function public.initiate_ticket_attachment_upload(uuid, text, text, bigint, text, text, uuid, text) from anon, authenticated, service_role, public;
grant execute on function public.initiate_ticket_attachment_upload(uuid, text, text, bigint, text, text, uuid, text) to authenticated, service_role;
