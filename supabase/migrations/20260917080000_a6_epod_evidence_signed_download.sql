-- CG-AUDIT-2026-09-02 A6: extends the signed-download pattern
-- (20260914020000_a6_vendor_compliance_signed_download.sql,
-- 20260914040000_a6_shipment_document_checklist_signed_download.sql,
-- 20260914050000_a6_ticket_attachment_signed_download.sql) to ePOD evidence
-- (signature + delivery photo files on app.epod_captures). Upload+scan for
-- this record type was already fixed this same checkpoint
-- (the "A6: fix ePOD evidence upload to use real files" slice) -- a
-- signature/photo file a field user attaches is real, malware-scanned bytes
-- -- but there was still no way to ever fetch those bytes back out again.
-- epod-panel.tsx does not even render capture.signatureFileId/photoFileIds
-- today (confirmed live, this checkpoint's own research).
--
-- A second, more fundamental gap surfaced while scoping this: the 'epod'
-- document type itself was never registered by any REAL (non-db-test)
-- migration anywhere in this repository -- confirmed live via repo-wide
-- grep before writing this migration: every one of the 10+ call sites that
-- register it (scripts/db-tests/operations-epod-capture-review.sql and
-- ~9 sibling db-test fixtures) does so itself, against its own disposable
-- database. Since app.resolve_document_type_definition (PLT-128, the
-- function app.initiate_file_upload always calls first) raises
-- document_type_not_configured whenever no tenant has EVER published a
-- 'document:<code>' config_object for that document type -- and a tenant
-- can never publish one until the matching app.config_types catalogue row
-- exists -- every real tenant's first ePOD evidence upload attempt would
-- fail immediately with document_type_not_configured, in spite of
-- app.set_epod_evidence/app.initiate_file_upload both being fully wired and
-- fully tested. This is the exact same platform-level catalogue-
-- registration gap 20260914060000_register_gps_device_installation_document_type.sql
-- already fixed for 'gps_device_installation' -- that migration's own
-- comment explicitly name-drops 'epod'/'pod' as a same-shaped example still
-- outstanding at the time it was written. Mirrors its shape verbatim:
-- additive, idempotent (on conflict (code) do nothing), registers only the
-- two global catalogue rows every tenant's own later publish call depends
-- on -- never a per-tenant config_object (a separate, later, per-tenant
-- admin action, exactly as every other document type in this repository
-- already requires). code/name/owner_primitive_code reused verbatim from
-- every one of those 10+ db-test fixtures' own identical
-- register_document_type call (all agree byte-for-byte: 'epod', 'Electronic
-- Proof of Delivery', 'DOC').

insert into app.document_types (code, name, owner_primitive_code, registered_by)
values ('epod', 'Electronic Proof of Delivery', 'DOC', 'system')
on conflict (code) do nothing;

insert into app.config_types (code, name, owner_primitive_code, registered_by)
values ('document:epod', 'Electronic Proof of Delivery', 'DOC', 'system')
on conflict (code) do nothing;

-- Authority gate: app.evaluate_permission(..., 'OPS', 'Download') -- the SAME
-- seam 20260914040000's own shipment-document-checklist download RPC already
-- reaches for, plus app.can_access_record(actor, tenant, shipment.owner_user_id,
-- app.lead_record_scope_org_unit_ids(shipment.org_unit_id), null) against the
-- ePOD capture's own parent shipment order -- ePOD evidence has no narrower
-- record-scope concept of its own (unlike ticket attachments' message
-- visibility), so the shipment order's own existing record-scope is the
-- correct and only bar, exactly as it already is for that record's document
-- checklist evidence.
--
-- Parameterized by p_file_id (the ticket-attachment precedent's own shape),
-- not by capture id: app.epod_captures.signature_file_id is a single file,
-- photo_file_ids is an array -- a capture-id-parameterized RPC would still
-- need a second parameter picking which file, so file-id-parameterized is
-- both simpler and matches the one-file-per-call shape every other A6
-- download RPC (and the browser-side "one button per file" UI) already uses.
--
-- ISS-2026-146-safe from birth (the class 20260914040000's own comment
-- discloses two of its OWN pre-existing siblings still carry): the initial
-- not-found branch below folds app.has_active_tenant_membership into itself,
-- so a zero-relationship cross-tenant probe against a real file_id never
-- sees this tenant's real tenant_id interpolated into a later
-- insufficient_authority message -- it sees the same not-found response a
-- fabricated file_id would produce.

create function app.authorize_epod_evidence_file_access(
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

  -- Record-scope (the parent shipment order's own app.can_access_record) is
  -- deliberately omitted, same reasoning as every sibling: the caller
  -- (app.access_epod_evidence_for_download) has already independently
  -- verified OPS:Download module authority PLUS that record-scope check --
  -- a second, narrower ownership condition on the underlying file itself is
  -- not this workflow's own bar.
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

comment on function app.authorize_epod_evidence_file_access is
  'CG-AUDIT-2026-09-02 A6: narrowly-scoped sibling of app.authorize_shipment_document_evidence_file_access/app.authorize_ticket_attachment_evidence_file_access for ePOD signature/photo evidence only. Identical malware-scan + deleted-file + restricted/credential-classification gates; the record-scope (parent shipment order''s own app.can_access_record) gate is intentionally omitted since the caller has already verified OPS:Download module authority plus that record-scope check.';

revoke execute on function app.authorize_epod_evidence_file_access(uuid, text, uuid, uuid) from public;
grant execute on function app.authorize_epod_evidence_file_access(uuid, text, uuid, uuid) to service_role;

-- app.authorize_epod_evidence_file_access is language plpgsql with no
-- security clause, i.e. INVOKER mode -- matching every sibling exactly.
-- scripts/db-tests/public-api-wrapper-regression.sql asserts exhaustively
-- that no public.* wrapper's security mode (definer/invoker) ever differs
-- from its app.* counterpart, so this wrapper carries no `security definer`
-- either.
create function public.authorize_epod_evidence_file_access(
  p_file_id uuid, p_access_type text, p_actor_auth_user_id uuid, p_correlation_id uuid DEFAULT NULL::uuid
)
returns app.file_access_logs
language sql
volatile
set search_path = pg_catalog, pg_temp
as $wrap$
  select app.authorize_epod_evidence_file_access(p_file_id, p_access_type, p_actor_auth_user_id, p_correlation_id);
$wrap$;

comment on function public.authorize_epod_evidence_file_access(p_file_id uuid, p_access_type text, p_actor_auth_user_id uuid, p_correlation_id uuid) is
  'RGL-394 Option-2 wrapper: app is not exposed to PostgREST; this is a thin invoker-mode pass-through to app.authorize_epod_evidence_file_access (itself invoker-mode) with an identical (service_role-only) grant set, never a reimplementation.';

revoke execute on function public.authorize_epod_evidence_file_access(uuid, text, uuid, uuid) from anon, authenticated, service_role, public;
grant execute on function public.authorize_epod_evidence_file_access(uuid, text, uuid, uuid) to service_role;

create function app.access_epod_evidence_for_download(
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
  v_decision app.rbac_decision;
  v_file app.files;
  v_capture app.epod_captures;
  v_shipment app.shipment_orders;
  v_log app.file_access_logs;
begin
  select * into v_file from app.files where id = p_file_id and record_type = 'shipment_order' and document_type_code = 'epod';
  if not found or not app.has_active_tenant_membership(v_file.tenant_id, p_actor_auth_user_id) then
    raise exception 'epod_evidence_file_not_found: %', p_file_id using errcode = 'no_data_found';
  end if;

  select * into v_capture from app.epod_captures
  where tenant_id = v_file.tenant_id and (signature_file_id = p_file_id or p_file_id = any (photo_file_ids))
  order by created_at asc
  limit 1;
  if not found then
    raise exception 'epod_evidence_file_not_linked: file % is not linked to any ePOD capture', p_file_id
      using errcode = 'check_violation';
  end if;

  select * into v_shipment from app.shipment_orders where id = v_capture.shipment_order_id;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_file.tenant_id, 'OPS', 'Download');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Download (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_file.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.can_access_record(p_actor_auth_user_id, v_shipment.tenant_id, v_shipment.owner_user_id, app.lead_record_scope_org_unit_ids(v_shipment.org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot access shipment order %', p_actor_auth_user_id, v_shipment.id
      using errcode = 'insufficient_privilege';
  end if;

  v_log := app.authorize_epod_evidence_file_access(p_file_id, 'signed_url_issued', p_actor_auth_user_id, p_correlation_id);

  perform app.capture_audit_event(
    v_file.tenant_id, p_actor_auth_user_id, p_actor_label, 'access_epod_evidence_for_download',
    'app.epod_captures', v_capture.id, case when v_log.result = 'granted' then 'success' else 'failure' end,
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

comment on function app.access_epod_evidence_for_download is
  'CG-AUDIT-2026-09-02 A6: service_role-only signed-download RPC for one ePOD signature/photo evidence file. Gated by OPS:Download (module authority) plus the same app.can_access_record scope check the shipment order''s own document checklist download RPC already uses, then app.authorize_epod_evidence_file_access''s own malware-scan/classification gate. The initial not-found branch folds app.has_active_tenant_membership in (ISS-2026-146-safe from birth), so a zero-relationship cross-tenant probe never sees this tenant''s real tenant_id in a later error. Returns bucket_id/storage_path only once granted, so server-side code can mint a short-lived signed URL -- the browser never sees storage_path directly. Never granted to authenticated or anon.';

revoke execute on function app.access_epod_evidence_for_download(uuid, uuid, text, uuid) from public;
grant execute on function app.access_epod_evidence_for_download(uuid, uuid, text, uuid) to service_role;

create function public.access_epod_evidence_for_download(
  p_file_id uuid, p_actor_auth_user_id uuid, p_actor_label text, p_correlation_id uuid DEFAULT NULL::uuid
)
returns TABLE(bucket_id text, storage_path text, original_filename text, mime_type text, access_result text, access_reason text)
language sql
volatile
security definer
set search_path = pg_catalog, pg_temp
as $wrap$
  select * from app.access_epod_evidence_for_download(p_file_id, p_actor_auth_user_id, p_actor_label, p_correlation_id);
$wrap$;

comment on function public.access_epod_evidence_for_download(p_file_id uuid, p_actor_auth_user_id uuid, p_actor_label text, p_correlation_id uuid) is
  'RGL-394 Option-2 wrapper: app is not exposed to PostgREST; this is a thin security-definer pass-through to app.access_epod_evidence_for_download with an identical (service_role-only) grant set, never a reimplementation.';

revoke execute on function public.access_epod_evidence_for_download(uuid, uuid, text, uuid) from anon, authenticated, service_role, public;
grant execute on function public.access_epod_evidence_for_download(uuid, uuid, text, uuid) to service_role;
