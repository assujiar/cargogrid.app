-- Track B Batch 7 -- ISS-2026-224 bounded fix.
--
-- ===========================================================================
-- Background (re-verified against the current schema, not merely the
-- KNOWN_ISSUES.md narrative)
-- ===========================================================================
--
-- `app.access_vendor_compliance_document_evidence` / `app.access_vendor_bank_
-- account_evidence` / `app.access_vendor_tax_identity_evidence` (PRC-253/`HDN-
-- 377`) each independently check `PRC:Download` module authority FIRST, then
-- call the shared `app.authorize_file_access()`, whose own non-uploader branch
-- requires `app.can_access_record(actor, tenant, uploader, shared_org_unit_
-- ids, customer_account_ref)` to pass (exact owner match, shared org-unit
-- membership, or a customer-account match -- `20260723180000_create_
-- commercial_sales_pipeline.sql` lines 50-88, the current, latest body).
--
-- Every vendor compliance/bank/tax evidence file is uploaded via `app.
-- initiate_file_upload()` (`20260719140000_create_document_file_engine.sql`
-- line 425) from client/application code that has no way to know, at upload
-- time, which OTHER tenant staff will later be assigned as the "second
-- reviewer" -- so `p_shared_org_unit_ids` is always omitted (defaults to
-- `'{}'`) and `p_customer_account_ref` is always null for these three record
-- types (re-verified: grepped every call site building an `initiate_file_
-- upload` argument list for `record_type` in
-- `('vendor_compliance','vendor_bank_account','vendor_tax_identity')` --
-- none pass a non-null `p_shared_org_unit_ids`). The result: `app.can_access_
-- record`'s ownership/share/customer-scope model has no vocabulary for "any
-- actor holding the tenant's own PRC:Download review permission, regardless
-- of who uploaded" -- so a genuine second reviewer, who is not the uploader,
-- is denied with the identical `document_record_access_denied` reason an
-- actually-unauthorized caller gets. This directly contradicts `app.access_
-- vendor_compliance_document_evidence`'s own header comment, which names
-- itself a fix for exactly this scenario (Sec.21 "authorized reviewers
-- verify evidence... reviewers verified evidence blind").
--
-- ===========================================================================
-- Why this is fixed here, at the RPC layer, and NOT inside `app.can_access_
-- record` or `app.authorize_file_access` themselves
-- ===========================================================================
--
-- `app.can_access_record` is genuinely repository-wide (dozens of call sites
-- across Commercial/Procurement/Finance/HR -- re-confirmed via grep against
-- `supabase/migrations/`, including 3 call sites added as recently as
-- `20260827010000_harden_cross_tenant_error_disclosure_representative.sql`
-- and `20260827130000_harden_tenant_disclosure_representative_extension_
-- batch2.sql`, both still in this same batch window). Widening its own
-- ownership/share model to also admit "holds module permission X" would
-- require passing a permission-code parameter through every one of those call
-- sites and deciding what it means for each of them -- a real design decision
-- for the shared primitive's own contract, not a bounded repair.
--
-- `app.authorize_file_access` is narrower (4 real callers: this migration's 3
-- evidence RPCs, `app.claim_case_evidence` in `20260730340000_create_
-- advanced_tms_claim_incident_operations.sql`, and the generic `public.
-- authorize_file_access` PostgREST pass-through) but is still the single
-- shared, documented "one evaluation flow" gate (`06_RLS_RBAC_WORKSTREAM.md`
-- §3) composing malware-scan + record-scope + classification checks for
-- EVERY caller, including ones (the claim/incident evidence viewer, the
-- generic public wrapper) that have not already verified a PRC:Download-
-- shaped module permission the way these 3 RPCs have. Weakening its own
-- record-scope branch in place would silently widen access for those other
-- callers too.
--
-- The bounded fix: a new, narrowly-scoped sibling function, `app.authorize_
-- vendor_evidence_file_access()`, byte-for-byte identical to `app.authorize_
-- file_access()` except its own record-scope branch is omitted -- because,
-- for these 3 RPCs specifically, the caller has ALREADY independently
-- verified `PRC:Download` module authority before ever reaching this call,
-- and per these RPCs' own documented design intent (Sec.21), that module
-- permission IS this workflow's reviewer authority; requiring the SAME actor
-- to also happen to share the uploader's org unit or customer account is a
-- second, unrelated gate this workflow was never meant to impose. The
-- malware-scan/deleted-file gate and the restricted/credential classification
-- gate are both preserved unchanged -- only the record-scope (ownership)
-- branch is skipped, and only for these 3 call sites. `app.authorize_file_
-- access` itself is untouched, byte-for-byte, so its own general contract for
-- every other existing and future caller is unaffected.
-- ===========================================================================

create function app.authorize_vendor_evidence_file_access(
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

  -- ISS-2026-224: the record-scope (uploader/shared-org-unit/customer-account)
  -- gate `app.authorize_file_access` applies here is deliberately OMITTED.
  -- Every caller of this function has already independently verified PRC:
  -- Download module authority (`app.access_vendor_compliance_document_
  -- evidence`/`app.access_vendor_bank_account_evidence`/`app.access_vendor_
  -- tax_identity_evidence`, each checking `app.evaluate_permission(...,
  -- 'PRC', 'Download')` before ever calling this function) -- that module
  -- permission IS this workflow's own documented reviewer authority (Sec.21
  -- "authorized reviewers verify evidence"), so an ownership/org-unit/
  -- customer-account match is not a second condition this workflow requires.

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

comment on function app.authorize_vendor_evidence_file_access is
  'ISS-2026-224 bounded fix: a narrowly-scoped sibling of app.authorize_file_access() for the 3 vendor evidence-access RPCs only (compliance document / bank account / tax identity). Identical malware-scan + deleted-file + restricted/credential-classification gates, but the record-scope (uploader/shared-org-unit/customer-account) gate is intentionally omitted -- every caller has already verified PRC:Download module authority, which for this workflow (Sec.21, PRC-253) IS the reviewer authority, so a non-uploading-but-authorized second reviewer is no longer denied with the same document_record_access_denied reason a genuinely unauthorized caller gets. app.authorize_file_access itself is untouched byte-for-byte -- its other 2 real callers (app.claim_case_evidence, the generic public.authorize_file_access wrapper) keep the full record-scope gate unchanged.';

-- Repoint the 3 evidence RPCs at the new function. CREATE OR REPLACE, signatures
-- unchanged -- their own public.* PostgREST wrappers (`20260826000000_create_
-- public_api_data_wrappers.sql`) are thin same-signature pass-throughs and need no
-- change. Bodies otherwise byte-for-byte identical to their current, latest
-- definitions (`20260814000000_harden_storage_signed_url_audit_findings.sql`).

create or replace function app.access_vendor_compliance_document_evidence(
  p_document_id uuid, p_access_type text, p_actor_auth_user_id uuid, p_actor_label text, p_correlation_id uuid default null
)
returns table (
  file_id uuid, original_filename text, mime_type text, size_bytes bigint, malware_scan_status text,
  classification text, legal_hold boolean, uploaded_at timestamptz, access_result text, access_reason text
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
  if p_access_type not in ('signed_url_issued', 'download', 'metadata_view') then
    raise exception 'invalid_access_type: % is not one of signed_url_issued/download/metadata_view', p_access_type using errcode = 'check_violation';
  end if;

  select * into v_document from app.vendor_compliance_documents where id = p_document_id;
  if not found then
    raise exception 'vendor_compliance_document_not_found: %', p_document_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_document.tenant_id, 'PRC', 'Download');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:Download (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_document.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  v_log := app.authorize_vendor_evidence_file_access(v_document.file_id, p_access_type, p_actor_auth_user_id, p_correlation_id);

  perform app.capture_audit_event(
    v_document.tenant_id, p_actor_auth_user_id, p_actor_label, 'access_vendor_compliance_document_evidence',
    'app.vendor_compliance_documents', v_document.id, case when v_log.result = 'granted' then 'success' else 'failure' end,
    v_log.reason, null, jsonb_build_object('access_type', p_access_type, 'result', v_log.result)
  );

  if v_log.result <> 'granted' then
    return query select null::uuid, null::text, null::text, null::bigint, null::text, null::text, null::boolean, null::timestamptz, v_log.result, v_log.reason;
    return;
  end if;

  select * into v_file from app.files where id = v_document.file_id;

  return query
  select v_file.id, v_file.original_filename, v_file.mime_type, v_file.size_bytes, v_file.malware_scan_status,
    v_file.classification, v_file.legal_hold, v_file.created_at, v_log.result, v_log.reason;
end;
$$;

comment on function app.access_vendor_compliance_document_evidence is 'PRC-253 fix-pass addition: the document/version viewer''s own gated evidence-access call (Sec.15/16/18/21) -- PRC:Download plus a record/sensitivity access gate, both audited. Never returns storage_path. A denied result nulls out every file-identifying field rather than raising. ISS-2026-224 fix: now calls app.authorize_vendor_evidence_file_access() instead of the shared app.authorize_file_access() -- the shared function''s own record-scope (uploader/org-unit/customer-account) gate had no vocabulary for "any actor holding this tenant''s PRC:Download authority", so a legitimate, non-uploading second reviewer was denied identically to an unauthorized caller, defeating this RPC''s own documented Sec.21 purpose.';

create or replace function app.access_vendor_bank_account_evidence(p_account_id uuid, p_access_type text, p_actor_auth_user_id uuid, p_actor_label text, p_correlation_id uuid default null)
returns table (
  file_id uuid, original_filename text, mime_type text, size_bytes bigint, malware_scan_status text,
  classification text, legal_hold boolean, uploaded_at timestamptz, access_result text, access_reason text
)
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_account app.vendor_bank_accounts;
  v_file app.files;
  v_log app.file_access_logs;
begin
  if p_access_type not in ('signed_url_issued', 'download', 'metadata_view') then
    raise exception 'invalid_access_type: % is not one of signed_url_issued/download/metadata_view', p_access_type using errcode = 'check_violation';
  end if;

  select * into v_account from app.vendor_bank_accounts where id = p_account_id;
  if not found then
    raise exception 'vendor_bank_account_not_found: %', p_account_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_account.tenant_id, 'PRC', 'Download');
  if not v_decision.allowed then
    perform app.capture_audit_event(
      v_account.tenant_id, p_actor_auth_user_id, p_actor_label, 'access_vendor_bank_account_evidence',
      'app.vendor_bank_accounts', v_account.id, 'failure', v_decision.reason, null,
      jsonb_build_object('access_type', p_access_type, 'result', 'denied', 'gate', 'insufficient_authority'),
      p_correlation_id
    );
    return query select null::uuid, null::text, null::text, null::bigint, null::text, null::text, null::boolean, null::timestamptz, 'denied'::text, ('insufficient_authority: ' || coalesce(v_decision.reason, ''))::text;
    return;
  end if;

  if v_account.evidence_file_id is null then
    raise exception 'no_evidence_attached: bank account % has no evidence file attached', p_account_id using errcode = 'no_data_found';
  end if;

  v_log := app.authorize_vendor_evidence_file_access(v_account.evidence_file_id, p_access_type, p_actor_auth_user_id, p_correlation_id);

  perform app.capture_audit_event(
    v_account.tenant_id, p_actor_auth_user_id, p_actor_label, 'access_vendor_bank_account_evidence',
    'app.vendor_bank_accounts', v_account.id, case when v_log.result = 'granted' then 'success' else 'failure' end,
    v_log.reason, null, jsonb_build_object('access_type', p_access_type, 'result', v_log.result)
  );

  if v_log.result <> 'granted' then
    return query select null::uuid, null::text, null::text, null::bigint, null::text, null::text, null::boolean, null::timestamptz, v_log.result, v_log.reason;
    return;
  end if;

  select * into v_file from app.files where id = v_account.evidence_file_id;

  return query
  select v_file.id, v_file.original_filename, v_file.mime_type, v_file.size_bytes, v_file.malware_scan_status,
    v_file.classification, v_file.legal_hold, v_file.created_at, v_log.result, v_log.reason;
end;
$$;

comment on function app.access_vendor_bank_account_evidence is 'ISS-2026-224 fix: now calls app.authorize_vendor_evidence_file_access() instead of the shared app.authorize_file_access() -- see app.access_vendor_compliance_document_evidence''s own comment for the full rationale, identical for this sibling.';

create or replace function app.access_vendor_tax_identity_evidence(p_tax_identity_id uuid, p_access_type text, p_actor_auth_user_id uuid, p_actor_label text, p_correlation_id uuid default null)
returns table (
  file_id uuid, original_filename text, mime_type text, size_bytes bigint, malware_scan_status text,
  classification text, legal_hold boolean, uploaded_at timestamptz, access_result text, access_reason text
)
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_tax_identity app.vendor_tax_identities;
  v_file app.files;
  v_log app.file_access_logs;
begin
  if p_access_type not in ('signed_url_issued', 'download', 'metadata_view') then
    raise exception 'invalid_access_type: % is not one of signed_url_issued/download/metadata_view', p_access_type using errcode = 'check_violation';
  end if;

  select * into v_tax_identity from app.vendor_tax_identities where id = p_tax_identity_id;
  if not found then
    raise exception 'vendor_tax_identity_not_found: %', p_tax_identity_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_tax_identity.tenant_id, 'PRC', 'Download');
  if not v_decision.allowed then
    perform app.capture_audit_event(
      v_tax_identity.tenant_id, p_actor_auth_user_id, p_actor_label, 'access_vendor_tax_identity_evidence',
      'app.vendor_tax_identities', v_tax_identity.id, 'failure', v_decision.reason, null,
      jsonb_build_object('access_type', p_access_type, 'result', 'denied', 'gate', 'insufficient_authority'),
      p_correlation_id
    );
    return query select null::uuid, null::text, null::text, null::bigint, null::text, null::text, null::boolean, null::timestamptz, 'denied'::text, ('insufficient_authority: ' || coalesce(v_decision.reason, ''))::text;
    return;
  end if;

  if v_tax_identity.evidence_file_id is null then
    raise exception 'no_evidence_attached: tax identity % has no evidence file attached', p_tax_identity_id using errcode = 'no_data_found';
  end if;

  v_log := app.authorize_vendor_evidence_file_access(v_tax_identity.evidence_file_id, p_access_type, p_actor_auth_user_id, p_correlation_id);

  perform app.capture_audit_event(
    v_tax_identity.tenant_id, p_actor_auth_user_id, p_actor_label, 'access_vendor_tax_identity_evidence',
    'app.vendor_tax_identities', v_tax_identity.id, case when v_log.result = 'granted' then 'success' else 'failure' end,
    v_log.reason, null, jsonb_build_object('access_type', p_access_type, 'result', v_log.result)
  );

  if v_log.result <> 'granted' then
    return query select null::uuid, null::text, null::text, null::bigint, null::text, null::text, null::boolean, null::timestamptz, v_log.result, v_log.reason;
    return;
  end if;

  select * into v_file from app.files where id = v_tax_identity.evidence_file_id;

  return query
  select v_file.id, v_file.original_filename, v_file.mime_type, v_file.size_bytes, v_file.malware_scan_status,
    v_file.classification, v_file.legal_hold, v_file.created_at, v_log.result, v_log.reason;
end;
$$;

comment on function app.access_vendor_tax_identity_evidence is 'ISS-2026-224 fix: now calls app.authorize_vendor_evidence_file_access() instead of the shared app.authorize_file_access() -- see app.access_vendor_compliance_document_evidence''s own comment for the full rationale, identical for this sibling.';

-- Per ERR-2026-004 (docs/runtime/ERROR_LEDGER.md): this migration carries its own
-- explicit `revoke execute on all functions in schema app from public` statement before
-- its final grants, the standing per-migration convention since PLT-118. CREATE OR
-- REPLACE FUNCTION does not itself drop an existing grant on the 3 repointed RPCs, but
-- every grant below is re-asserted explicitly, verbatim from each function's own current
-- live grant statement, rather than relying on that Postgres behavior implicitly.
revoke execute on all functions in schema app from public;

grant execute on function app.authorize_vendor_evidence_file_access(uuid, text, uuid, uuid) to service_role;

-- RGL-394 Option-2: app is not exposed to PostgREST -- scripts/db-tests/public-api-
-- wrapper-regression.sql's own exhaustive sweep requires a matching public.* wrapper
-- for every externally-callable (any grant, including service_role-only) app.*
-- function. Mirrors public.authorize_file_access's own exact shape verbatim (`language
-- sql`, no `security definer` -- the underlying app.* function itself has none, i.e.
-- SECURITY INVOKER) -- a thin pass-through, never a reimplementation.
--
-- Per the AMENDED RGL-394 convention (20260826010000_harden_public_api_data_wrappers_
-- tierc_fixes.sql Finding 2, live-forced CRITICAL): this project's own Supabase
-- platform-level bootstrap carries `ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN
-- SCHEMA public GRANT EXECUTE ON FUNCTIONS TO anon, authenticated, service_role` --
-- every `create function public.*` run as role postgres (every migration) silently
-- picks up EXECUTE for anon AND authenticated at creation time, regardless of what is
-- explicitly granted afterward. `revoke ... from public` alone does NOT undo this (it
-- only revokes the PUBLIC pseudo-role's own grant, never a role-specific one a
-- default-privilege rule already attached by name) -- the revoke below must name
-- anon/authenticated/service_role explicitly, exactly as that migration's own amended
-- convention requires, before granting back only the roles app.authorize_vendor_
-- evidence_file_access itself grants (service_role only).
create function public.authorize_vendor_evidence_file_access(p_file_id uuid, p_access_type text, p_actor_auth_user_id uuid, p_correlation_id uuid default null)
returns app.file_access_logs
language sql
volatile
set search_path = pg_catalog, pg_temp
as $wrap$
  select app.authorize_vendor_evidence_file_access(p_file_id, p_access_type, p_actor_auth_user_id, p_correlation_id);
$wrap$;

comment on function public.authorize_vendor_evidence_file_access(p_file_id uuid, p_access_type text, p_actor_auth_user_id uuid, p_correlation_id uuid) is
  'RGL-394 Option-2 wrapper: app is not exposed to PostgREST; this is a thin security-definer pass-through to app.authorize_vendor_evidence_file_access with an identical grant set, never a reimplementation. See docs/build-log/release-go-live/RGL-394.md.';

revoke execute on function public.authorize_vendor_evidence_file_access(p_file_id uuid, p_access_type text, p_actor_auth_user_id uuid, p_correlation_id uuid) from anon, authenticated, service_role, public;
grant execute on function public.authorize_vendor_evidence_file_access(p_file_id uuid, p_access_type text, p_actor_auth_user_id uuid, p_correlation_id uuid) to service_role;
grant execute on function app.access_vendor_compliance_document_evidence(uuid, text, uuid, text, uuid) to authenticated, service_role;
grant execute on function app.access_vendor_bank_account_evidence(uuid, text, uuid, text, uuid) to authenticated, service_role;
grant execute on function app.access_vendor_tax_identity_evidence(uuid, text, uuid, text, uuid) to authenticated, service_role;
