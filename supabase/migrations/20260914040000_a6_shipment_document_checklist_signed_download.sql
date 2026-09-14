-- CG-AUDIT-2026-09-02 A6: extends the signed-download pattern
-- (20260914020000_a6_vendor_compliance_signed_download.sql) to shipment document
-- checklist evidence -- upload+scan for this record type was already wired
-- (20260914010000-era session work), so evidence a reviewer approves/rejects is
-- real, malware-scanned bytes; there was simply no way to ever fetch those bytes
-- back out again. Same shape as the vendor-compliance pair: a narrow
-- authorization sibling (identical malware-scan/classification gate, no
-- vendor-specific record-scope) plus a service_role-only RPC that only returns
-- storage_path/bucket_id once granted.
--
-- Authority gate: app.evaluate_permission(..., 'OPS', 'Download') -- the SAME
-- permission action code app.evaluate_permission already exposes
-- (20260716103445_create_roles_permissions.sql: `('Download', 'OPS', 'standard',
-- false)`), seeded from day one but, confirmed live (grep across every migration),
-- never once actually checked by any RPC until now -- a ready-made seam, exactly
-- the position `'PRC', 'Download'` was in before PRC-253's own evidence-access
-- RPCs started using it. No tenant holds this permission on any role by default;
-- assigning it to a role is a tenant-admin action (app/(tenant)/[tenantSlug]/
-- admin/roles/), same as any other permission -- not something this migration
-- can or should pre-populate.
-- app.can_access_record(actor, tenant, shipment.owner_user_id,
-- app.lead_record_scope_org_unit_ids(shipment.org_unit_id), null) -- the exact
-- record-scope call app.link_document_to_checklist_item/app.review_document_
-- checklist_item already use for this same table, re-derived here rather than
-- assumed.
--
-- One deliberate improvement over its own two existing sibling functions
-- (app.link_document_to_checklist_item/app.review_document_checklist_item, both
-- UNCHANGED by this migration -- Part C, no applied migration edited): those two
-- raise their `evaluate_permission`-driven insufficient_authority BEFORE ever
-- checking whether the actor has any membership at all in the checklist item's
-- own tenant, so a zero-relationship cross-tenant probe would see the real
-- tenant_id interpolated into that error message -- the exact ISS-2026-146 defect
-- class this repository's own many `harden_tenant_id_disclosure_*` migrations
-- already fixed elsewhere. This new function folds that membership check into
-- its own initial not-found branch instead (the same fix shape those hardening
-- migrations established), so it does not reintroduce a known, already-fixed-
-- elsewhere defect in brand-new code. Disclosed here, not fixed there: fixing
-- the two pre-existing sibling functions is a separate, out-of-scope finding.

create function app.authorize_shipment_document_evidence_file_access(
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

  -- Record-scope (uploader/shared-org-unit/customer-account) is deliberately
  -- omitted, same reasoning as app.authorize_vendor_evidence_file_access: the
  -- caller (app.access_shipment_document_checklist_item_evidence_for_download)
  -- has already independently verified OPS:Download module authority PLUS the
  -- shipment order's own app.can_access_record scope -- a second, narrower
  -- ownership condition on the underlying file itself is not this workflow's
  -- own bar.
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

comment on function app.authorize_shipment_document_evidence_file_access is
  'CG-AUDIT-2026-09-02 A6: narrowly-scoped sibling of app.authorize_vendor_evidence_file_access for shipment document checklist evidence only. Identical malware-scan + deleted-file + restricted/credential-classification gates; the record-scope (uploader/shared-org-unit/customer-account) gate is intentionally omitted since the caller has already verified OPS:Download module authority plus the parent shipment order''s own app.can_access_record scope.';

revoke execute on function app.authorize_shipment_document_evidence_file_access(uuid, text, uuid, uuid) from public;
grant execute on function app.authorize_shipment_document_evidence_file_access(uuid, text, uuid, uuid) to service_role;

-- app.authorize_shipment_document_evidence_file_access is language plpgsql with no
-- security clause, i.e. INVOKER mode -- its own app.authorize_vendor_evidence_file_access
-- precedent's public.* wrapper is invoker-mode too (no `security definer`), and
-- scripts/db-tests/public-api-wrapper-regression.sql asserts exhaustively that no
-- public.* wrapper's security mode (definer/invoker) ever differs from its app.*
-- counterpart -- an RLS-bypass class regression if it ever recurred. This wrapper
-- mirrors that exactly: no `security definer` here either.
create function public.authorize_shipment_document_evidence_file_access(
  p_file_id uuid, p_access_type text, p_actor_auth_user_id uuid, p_correlation_id uuid DEFAULT NULL::uuid
)
returns app.file_access_logs
language sql
volatile
set search_path = pg_catalog, pg_temp
as $wrap$
  select app.authorize_shipment_document_evidence_file_access(p_file_id, p_access_type, p_actor_auth_user_id, p_correlation_id);
$wrap$;

comment on function public.authorize_shipment_document_evidence_file_access(p_file_id uuid, p_access_type text, p_actor_auth_user_id uuid, p_correlation_id uuid) is
  'RGL-394 Option-2 wrapper: app is not exposed to PostgREST; this is a thin invoker-mode pass-through to app.authorize_shipment_document_evidence_file_access (itself invoker-mode) with an identical (service_role-only) grant set, never a reimplementation.';

revoke execute on function public.authorize_shipment_document_evidence_file_access(uuid, text, uuid, uuid) from anon, authenticated, service_role, public;
grant execute on function public.authorize_shipment_document_evidence_file_access(uuid, text, uuid, uuid) to service_role;

create function app.access_shipment_document_checklist_item_evidence_for_download(
  p_checklist_item_id uuid, p_actor_auth_user_id uuid, p_actor_label text, p_correlation_id uuid default null
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
  v_item app.shipment_document_checklist_items;
  v_shipment app.shipment_orders;
  v_file app.files;
  v_log app.file_access_logs;
begin
  select * into v_item from app.shipment_document_checklist_items where id = p_checklist_item_id;
  if not found or not app.has_active_tenant_membership(v_item.tenant_id, p_actor_auth_user_id) then
    raise exception 'document_checklist_item_not_found: %', p_checklist_item_id using errcode = 'no_data_found';
  end if;
  select * into v_shipment from app.shipment_orders where id = v_item.shipment_order_id;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_item.tenant_id, 'OPS', 'Download');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Download (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_item.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.can_access_record(p_actor_auth_user_id, v_shipment.tenant_id, v_shipment.owner_user_id, app.lead_record_scope_org_unit_ids(v_shipment.org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot access shipment order %', p_actor_auth_user_id, v_item.shipment_order_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_item.file_id is null then
    raise exception 'document_checklist_no_linked_file: checklist item % has no linked file to download', p_checklist_item_id
      using errcode = 'check_violation';
  end if;

  v_log := app.authorize_shipment_document_evidence_file_access(v_item.file_id, 'signed_url_issued', p_actor_auth_user_id, p_correlation_id);

  perform app.capture_audit_event(
    v_item.tenant_id, p_actor_auth_user_id, p_actor_label, 'access_shipment_document_checklist_item_evidence_for_download',
    'app.shipment_document_checklist_items', v_item.id, case when v_log.result = 'granted' then 'success' else 'failure' end,
    v_log.reason, null, jsonb_build_object('access_type', 'signed_url_issued', 'result', v_log.result)
  );

  if v_log.result <> 'granted' then
    return query select null::text, null::text, null::text, null::text, v_log.result, v_log.reason;
    return;
  end if;

  select * into v_file from app.files where id = v_item.file_id;

  return query
  select 'tenant-documents'::text, v_file.storage_path, v_file.original_filename, v_file.mime_type, v_log.result, v_log.reason;
end;
$$;

comment on function app.access_shipment_document_checklist_item_evidence_for_download is
  'CG-AUDIT-2026-09-02 A6: service_role-only signed-download RPC for one shipment document checklist item''s linked evidence file. Gated by OPS:Download (module authority) plus the same app.can_access_record scope check app.link_document_to_checklist_item/app.review_document_checklist_item already use, then app.authorize_shipment_document_evidence_file_access''s own malware-scan/classification gate. Returns bucket_id/storage_path only once granted, so server-side code can mint a short-lived signed URL -- the browser never sees storage_path directly. Never granted to authenticated or anon.';

revoke execute on function app.access_shipment_document_checklist_item_evidence_for_download(uuid, uuid, text, uuid) from public;
grant execute on function app.access_shipment_document_checklist_item_evidence_for_download(uuid, uuid, text, uuid) to service_role;

-- app is not exposed to PostgREST (supabase/config.toml: schemas = ["public",
-- "graphql_public"]) -- every RPC callable from application code needs a matching
-- public.* thin pass-through wrapper, the standing convention
-- 20260826000000_create_public_api_data_wrappers.sql established and
-- scripts/db-tests/public-api-wrapper-regression.sql enforces exhaustively.

create function public.access_shipment_document_checklist_item_evidence_for_download(
  p_checklist_item_id uuid, p_actor_auth_user_id uuid, p_actor_label text, p_correlation_id uuid DEFAULT NULL::uuid
)
returns TABLE(bucket_id text, storage_path text, original_filename text, mime_type text, access_result text, access_reason text)
language sql
volatile
security definer
set search_path = pg_catalog, pg_temp
as $wrap$
  select * from app.access_shipment_document_checklist_item_evidence_for_download(p_checklist_item_id, p_actor_auth_user_id, p_actor_label, p_correlation_id);
$wrap$;

comment on function public.access_shipment_document_checklist_item_evidence_for_download(p_checklist_item_id uuid, p_actor_auth_user_id uuid, p_actor_label text, p_correlation_id uuid) is
  'RGL-394 Option-2 wrapper: app is not exposed to PostgREST; this is a thin security-definer pass-through to app.access_shipment_document_checklist_item_evidence_for_download with an identical (service_role-only) grant set, never a reimplementation.';

revoke execute on function public.access_shipment_document_checklist_item_evidence_for_download(uuid, uuid, text, uuid) from anon, authenticated, service_role, public;
grant execute on function public.access_shipment_document_checklist_item_evidence_for_download(uuid, uuid, text, uuid) to service_role;
