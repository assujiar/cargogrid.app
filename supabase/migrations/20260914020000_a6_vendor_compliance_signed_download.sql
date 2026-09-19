-- CG-AUDIT-2026-09-02 A6, third and final piece of the audit's own step-4 wording
-- ("wire upload + signed download + scanning to app.files"). Upload
-- (app.initiate_file_upload) and scanning (the real malware_scan job type + a real
-- VirusTotal adapter) were already wired end to end by an earlier remediation pass
-- this series. Signed download never was, for any record type -- confirmed live by
-- grep: no code anywhere in this repository calls `.storage.from(...).createSignedUrl()`
-- except this migration's own new caller (added alongside this migration, not yet
-- applied at grep time).
--
-- Why this could not simply reuse app.access_vendor_compliance_document_evidence: that
-- function already accepts p_access_type='signed_url_issued' and already performs the
-- exact right authorization dance (PRC:Download module authority +
-- app.authorize_vendor_evidence_file_access's malware-scan/classification gate), but by
-- deliberate design (Finding A, 20260814000000_harden_storage_signed_url_audit_findings.sql)
-- it can never return storage_path: app.files.storage_path carries no column grant to
-- `authenticated` at all, and that function IS granted to `authenticated`. Minting a
-- signed URL genuinely needs the raw storage key, so the one safe place to read it is a
-- sibling function granted to `service_role` only, called from server-side code after
-- the caller's own identity has already been authenticated via the ordinary RLS-scoped
-- client -- the same "explicit actor, service-role execution" architecture
-- lib/supabase/service-role.ts's own header already documents for every other
-- privileged mutation in this codebase.
--
-- Deliberately NOT a refactor of the existing function to share a body across the
-- authenticated/service_role grant boundary: duplicating the short authorization
-- preamble keeps each function's own security review self-contained -- a reviewer
-- reading this function alone sees its complete grant surface and behavior without
-- tracing an EXECUTE grant through a second function with a different (wider) grant
-- set. Bodies are intentionally near-identical to
-- app.access_vendor_compliance_document_evidence's own current, latest definition
-- (20260903123000_harden_tenant_id_disclosure_procurement_integrations_platform.sql).

create function app.access_vendor_compliance_document_evidence_for_download(
  p_document_id uuid, p_actor_auth_user_id uuid, p_actor_label text, p_correlation_id uuid default null
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
  v_document app.vendor_compliance_documents;
  v_file app.files;
  v_log app.file_access_logs;
begin
  select * into v_document from app.vendor_compliance_documents where id = p_document_id;
  if not found or not app.has_active_tenant_membership(v_document.tenant_id, p_actor_auth_user_id) then
    raise exception 'vendor_compliance_document_not_found: %', p_document_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_document.tenant_id, 'PRC', 'Download');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:Download (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_document.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  v_log := app.authorize_vendor_evidence_file_access(v_document.file_id, 'signed_url_issued', p_actor_auth_user_id, p_correlation_id);

  perform app.capture_audit_event(
    v_document.tenant_id, p_actor_auth_user_id, p_actor_label, 'access_vendor_compliance_document_evidence_for_download',
    'app.vendor_compliance_documents', v_document.id, case when v_log.result = 'granted' then 'success' else 'failure' end,
    v_log.reason, null, jsonb_build_object('access_type', 'signed_url_issued', 'result', v_log.result)
  );

  if v_log.result <> 'granted' then
    return query select null::text, null::text, null::text, null::text, v_log.result, v_log.reason;
    return;
  end if;

  select * into v_file from app.files where id = v_document.file_id;

  -- 'tenant-documents' matches lib/storage/tenant-documents-bucket.ts's own
  -- TENANT_DOCUMENTS_BUCKET_ID constant -- the single real bucket
  -- 20260908010000_close_a6_storage_bucket_and_malware_scan_job_type.sql provisions.
  -- Every file this codebase's own app.initiate_file_upload ever creates a row for is
  -- uploaded into that one bucket; there is no per-tenant or per-document-type bucket
  -- to look up.
  return query
  select 'tenant-documents'::text, v_file.storage_path, v_file.original_filename, v_file.mime_type, v_log.result, v_log.reason;
end;
$$;

comment on function app.access_vendor_compliance_document_evidence_for_download is
  'CG-AUDIT-2026-09-02 A6: service_role-only sibling of app.access_vendor_compliance_document_evidence. Performs the identical PRC:Download + app.authorize_vendor_evidence_file_access(''signed_url_issued'') gate, but returns bucket_id/storage_path once granted so server-side code (never the browser) can mint a short-lived signed URL via the Storage API -- the one piece app.access_vendor_compliance_document_evidence itself can never provide, since app.files.storage_path carries no column grant to authenticated at all (Finding A, 20260814000000_harden_storage_signed_url_audit_findings.sql) and that function is granted to authenticated. Never granted to authenticated or anon.';

revoke execute on function app.access_vendor_compliance_document_evidence_for_download(uuid, uuid, text, uuid) from public;
grant execute on function app.access_vendor_compliance_document_evidence_for_download(uuid, uuid, text, uuid) to service_role;

-- app is not exposed to PostgREST (supabase/config.toml: schemas = ["public",
-- "graphql_public"]) -- every RPC callable from application code needs a matching
-- public.* thin pass-through wrapper, the standing convention
-- 20260826000000_create_public_api_data_wrappers.sql established and
-- scripts/db-tests/public-api-wrapper-regression.sql enforces exhaustively (every
-- externally-callable app.* function, catalog-derived, not a sample).

create function public.access_vendor_compliance_document_evidence_for_download(
  p_document_id uuid, p_actor_auth_user_id uuid, p_actor_label text, p_correlation_id uuid DEFAULT NULL::uuid
)
returns TABLE(bucket_id text, storage_path text, original_filename text, mime_type text, access_result text, access_reason text)
language sql
volatile
security definer
set search_path = pg_catalog, pg_temp
as $wrap$
  select * from app.access_vendor_compliance_document_evidence_for_download(p_document_id, p_actor_auth_user_id, p_actor_label, p_correlation_id);
$wrap$;

comment on function public.access_vendor_compliance_document_evidence_for_download(p_document_id uuid, p_actor_auth_user_id uuid, p_actor_label text, p_correlation_id uuid) is
  'RGL-394 Option-2 wrapper: app is not exposed to PostgREST; this is a thin security-definer pass-through to app.access_vendor_compliance_document_evidence_for_download with an identical (service_role-only) grant set, never a reimplementation.';

revoke execute on function public.access_vendor_compliance_document_evidence_for_download(uuid, uuid, text, uuid) from anon, authenticated, service_role, public;
grant execute on function public.access_vendor_compliance_document_evidence_for_download(uuid, uuid, text, uuid) to service_role;
