-- HDN-377 (Step 15, Prompt 377, Storage and Signed URL Audit) -- first-round fix
-- migration. Four independent parallel investigation lenses (upload/scan/quarantine
-- gate; signed URL expiry/scope/revocation; file access audit and retention/legal
-- hold; cross-tenant/RLS on file-shaped tables), each required to live-force its own
-- findings against a disposable database or real request/response construction
-- rather than accept a code read as proof.
--
-- ===========================================================================
-- Finding A (CRITICAL, found independently by 3 of 4 lenses): app.files.storage_path
-- -- the real Supabase Storage object key -- carries a full table-level SELECT grant
-- to `authenticated`, with no column-level mask. Every RPC this codebase built to
-- deliberately withhold storage_path (app.get_customer_document,
-- app.access_vendor_compliance_document_evidence and its financial-security
-- siblings) is moot: any caller with ordinary RLS row-visibility into a file can
-- simply query app.files directly and read the key straight from the table, no
-- service-role or RPC needed. Live-forced: `set local role authenticated`, then
-- `select storage_path from app.files where uploaded_by_auth_user_id = ...` returned
-- the real path string, unconditional on malware_scan_status (a `pending` and a
-- freshly-`infected` file both still returned it). Mirrors the exact, already-proven
-- app.users/email column-level carve-out precedent (20260716110430_create_field_
-- record_access.sql's own header): a bare column-level REVOKE cannot carve an
-- exception out of a broader table-level GRANT in Postgres -- the correct pattern,
-- proven there, is to REVOKE the table-level grant entirely and re-GRANT SELECT on
-- an explicit column list that omits the sensitive column.
-- ===========================================================================

revoke select on app.files from authenticated;
grant select (
  id, tenant_id, document_type_code, config_version_id, record_type, record_id,
  classification, original_filename, mime_type, size_bytes,
  malware_scan_status, malware_scan_completed_at, malware_scan_provider_ref,
  version_group_id, version_number, is_latest_version, lifecycle_status,
  legal_hold, legal_hold_reason, deleted_at, uploaded_by_auth_user_id,
  shared_org_unit_ids, customer_account_ref, idempotency_key, created_at, updated_at
) on app.files to authenticated;

-- ===========================================================================
-- Finding B (CRITICAL): two independent, non-communicating legal-hold mechanisms
-- exist for files. PLT-128 built its own file-native hold (app.files.legal_hold +
-- app.set_file_legal_hold(), consulted only by app.request_file_deletion()).
-- Separately, IAE-031 built a generic, cross-domain legal-hold primitive
-- (app.legal_holds, app.request_legal_hold()/app._is_under_legal_hold(),
-- polymorphic scope_record_table/scope_record_id) that any other domain (an HR
-- case, a finance dispute, a claim, a ticket) is expected to use for placing a hold
-- on ITS OWN records. Neither mechanism was aware of the other. Live-forced both
-- directions: (a) a hold placed via app.request_legal_hold(scope='app.files',
-- file.id) left app.files.legal_hold false, and app.request_file_deletion() still
-- succeeded, soft-deleting the file despite the active generic hold; (b) a
-- PLT-128-native hold (app.files.legal_hold=true) was invisible to
-- app.request_retention_archive()'s own dry-run classification
-- (legal_hold_blocking=false). Fixed by extending app._is_under_legal_hold() with
-- one additional OR-branch checking app.files.legal_hold directly whenever the
-- source table is 'app.files' -- this single extension point closes both
-- directions at once, since app.request_retention_archive() already calls
-- app._is_under_legal_hold() and app.request_file_deletion() is updated below to
-- also call it (in addition to its own existing native-flag check, kept as
-- defense-in-depth rather than replaced).
-- ===========================================================================

create or replace function app._is_under_legal_hold(p_tenant_id uuid, p_record_class text, p_source_table text, p_source_record_id uuid)
returns boolean
language sql
stable
security definer
set search_path = app, pg_temp
as $$
  select
    exists (
      select 1 from app.legal_holds
      where status = 'active' and scope_record_table = p_source_table and scope_record_id = p_source_record_id
    )
    or
    exists (
      select 1 from app.legal_holds
      where tenant_id = p_tenant_id and record_class = p_record_class and status = 'active'
        and scope_record_table is null and scope_record_id is null
    )
    or
    -- HDN-377 (Storage and Signed URL Audit) fix: bridges the PLT-128-native
    -- app.files.legal_hold flag into the generic IAE-031 hold-check primitive, so
    -- app.request_retention_archive()'s dry-run classification (and any future
    -- caller of this function) sees a file-native hold too, live-forced missing
    -- before this fix.
    (
      p_source_table = 'app.files'
      and exists (select 1 from app.files where id = p_source_record_id and legal_hold = true)
    );
$$;

comment on function app._is_under_legal_hold is
  'IAE-031: internal-only primitive, no actor/authority parameter -- never granted to anon/authenticated. A specific-record hold matches on (source_table, source_record_id) ALONE, independent of the caller''s own tenant_id/record_class claim (HDN-373 Tier C review fix); a whole-class hold necessarily still matches on the caller''s own (tenant_id, record_class) declaration, since there is no specific record to anchor against instead. HDN-377 (Storage and Signed URL Audit): also true whenever source_table=''app.files'' and that file''s own legal_hold column is set -- bridges PLT-128''s file-native hold flag into this generic cross-domain primitive, closing the gap where a hold placed through either mechanism was invisible to the other.';

-- ===========================================================================
-- Finding C (HIGH): app.files.legal_hold was enforced only inside the
-- app.request_file_deletion() RPC, with no schema-level backstop -- a raw
-- service_role DELETE physically erased a legally-held file row. Live-forced: the
-- RPC correctly raised document_legal_hold_blocks_deletion, then a raw
-- `delete from app.files where id = ...` as service_role succeeded, row gone
-- entirely (app.files carries only a BEFORE UPDATE touch_row trigger, no
-- BEFORE DELETE guard at all, and service_role holds a live table-level DELETE
-- grant). Fixed with a narrowly-scoped BEFORE DELETE guard, mirroring
-- app.protect_transaction_lineage_edges_append_only's own proven RPD-022
-- supreme-admin-bypass shape (HDN-375) -- this guard fires ONLY on DELETE of a
-- legal_hold=true row; ordinary UPDATE (scan-status transitions, versioning
-- supersede) and soft-deletion (deleted_at) are entirely unaffected.
-- ===========================================================================

create function app.protect_files_legal_hold_from_deletion()
returns trigger
language plpgsql
as $$
declare
  v_actor uuid := auth.uid();
begin
  if OLD.legal_hold and not app.is_supreme_admin(v_actor) then
    raise exception 'document_legal_hold_blocks_deletion: file % is under legal hold (%), it cannot be physically deleted -- app.request_file_deletion already refuses this at the RPC layer, this is the schema-level backstop for a direct DELETE', OLD.id, OLD.legal_hold_reason
      using errcode = 'insufficient_privilege';
  end if;

  if OLD.legal_hold then
    perform app.capture_audit_event(
      OLD.tenant_id, v_actor, 'supreme_admin_absolute_crud', 'delete_legally_held_file',
      'app.files', OLD.id, 'success',
      'RPD-022 absolute-CRUD exception invoked (best-effort evidence, not a preventive control) -- app.files is otherwise blocked from physical deletion while under legal hold',
      to_jsonb(OLD), null
    );
  end if;

  return OLD;
end;
$$;

comment on function app.protect_files_legal_hold_from_deletion is
  'HDN-377 (Storage and Signed URL Audit): BEFORE DELETE guard for app.files -- app.request_file_deletion already refuses a legally-held file at the RPC layer, but that check had no schema-level backstop; live-forced, a raw service_role DELETE against a legally-held row previously succeeded unconditionally. Blocks physical deletion of any row with legal_hold=true unless app.is_supreme_admin(auth.uid()) -- a detective, best-effort-evidenced RPD-022 exception mirroring app.protect_loyalty_ledger_append_only/app.protect_transaction_lineage_edges_append_only''s own proven shape, never a tamper-proof claim. Soft-deletion (deleted_at) and every other UPDATE path are unaffected -- this guards only the physical DELETE statement.';

create trigger files_protect_legal_hold_from_deletion
  before delete on app.files
  for each row
  execute function app.protect_files_legal_hold_from_deletion();

-- app.request_file_deletion(): also consults the generic hold primitive (Finding B),
-- kept alongside its own existing native-flag check as defense-in-depth. No other
-- behavior in this function changes.
create or replace function app.request_file_deletion(
  p_file_id uuid,
  p_reason text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.files
language plpgsql
as $$
declare
  v_file app.files;
  v_updated app.files;
begin
  select * into v_file from app.files where id = p_file_id;
  if not found then
    raise exception 'document_file_not_found: no file %', p_file_id
      using errcode = 'no_data_found';
  end if;

  if v_file.uploaded_by_auth_user_id <> p_actor_auth_user_id
     and not (app.is_supreme_admin(p_actor_auth_user_id) or app.is_support_grant_authority(p_actor_auth_user_id, v_file.tenant_id)) then
    raise exception 'document_deletion_unauthorized: only the original uploader or a support/supreme authority may request deletion of file %', p_file_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_file.deleted_at is not null then
    return v_file;
  end if;

  if v_file.legal_hold or app._is_under_legal_hold(v_file.tenant_id, 'operational', 'app.files', p_file_id) then
    raise exception 'document_legal_hold_blocks_deletion: file % is under legal hold (%), it cannot be deleted', p_file_id, v_file.legal_hold_reason
      using errcode = 'check_violation';
  end if;

  update app.files
  set deleted_at = now(), lifecycle_status = 'deleted'
  where id = p_file_id
  returning * into v_updated;

  perform app.capture_audit_event(
    v_updated.tenant_id, p_actor_auth_user_id, p_actor_label, 'request_file_deletion',
    'app.files', v_updated.id, 'success', p_reason, to_jsonb(v_file), to_jsonb(v_updated)
  );

  return v_updated;
end;
$$;

-- ===========================================================================
-- Finding D (MEDIUM): app.access_vendor_compliance_document_evidence and its two
-- financial-security siblings (app.access_vendor_bank_account_evidence,
-- app.access_vendor_tax_identity_evidence) each document their own contract as "a
-- denied result nulls out every file-identifying field" -- true on the
-- insufficient-authority denial branch, but the SECOND denial branch (PRC:Download
-- passes, but app.authorize_file_access itself denies -- malware/record-access/
-- classification) returned the real file/evidence UUID unmasked. Live-forced for
-- the compliance variant: a same-tenant, same-permission, non-uploader reviewer
-- got access_result=denied reason=document_record_access_denied file_id=<real
-- uuid>. The bank-account/tax-identity siblings share byte-for-byte identical
-- logic at the equivalent line. Fixed by nulling file_id on this branch too, same
-- as the first branch a few lines above it in each function.
-- ===========================================================================

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

  v_log := app.authorize_file_access(v_document.file_id, p_access_type, p_actor_auth_user_id, p_correlation_id);

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

comment on function app.access_vendor_compliance_document_evidence is 'PRC-253 fix-pass addition: the document/version viewer''s own gated evidence-access call (Sec.15/16/18/21) -- PRC:Download plus PLT-128''s own app.authorize_file_access (malware-scan + record/sensitivity gate, RPD-032), both audited (this capability''s own app.capture_audit_event AND app.authorize_file_access''s own app.file_access_logs row). Never returns storage_path. A denied result nulls out every file-identifying field rather than raising, so a UI can show "access denied: <reason>" without a second round trip. HDN-377 (Storage and Signed URL Audit) fix: the content-gate denial branch (authority passes, app.authorize_file_access itself denies) previously left file_id unmasked, contradicting this exact contract -- live-forced, now nulled the same as the authority-gate denial branch.';

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

  v_log := app.authorize_file_access(v_account.evidence_file_id, p_access_type, p_actor_auth_user_id, p_correlation_id);

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

  v_log := app.authorize_file_access(v_tax_identity.evidence_file_id, p_access_type, p_actor_auth_user_id, p_correlation_id);

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

-- ===========================================================================
-- Finding E (MEDIUM): app.vendor_compliance_documents_select_scoped and
-- app.rfq_response_attachments_select_scoped -- the RLS SELECT policies on two
-- file/evidence-shaped Procurement tables -- gate only on active tenant
-- membership (plus the customer_user-layer default-deny), never on PRC:View/
-- PRC:Download, while the correct RPC read paths for the same data
-- (app.access_vendor_compliance_document_evidence, app.list_rfq_response_
-- attachments) DO correctly require it. Live-forced: an active tenant member
-- holding zero PRC role assignments read every row of both tables directly
-- (verification_status/rejection_reason/expiry_date/file_id on the compliance
-- table; the competitor-bid file_id linkage on the RFQ table), while the RPC path
-- correctly raised insufficient_authority for the identical actor. Same defect
-- class HDN-373 already fixed once for app.finance_journals (ISS-2026-184,
-- app.finance_journals_select_scoped), mirrored here via the identical
-- check_<domain>_authority-in-RLS pattern that fix established
-- (app.payroll_periods_select_scoped's own precedent).
-- ===========================================================================

create function app.check_procurement_authority(p_action text, p_tenant_id uuid, p_actor_auth_user_id uuid)
returns boolean
language sql
stable
security definer
set search_path = app, pg_temp
as $$
  select (app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'PRC', p_action)).allowed;
$$;

comment on function app.check_procurement_authority is
  'HDN-377 (Storage and Signed URL Audit): SECURITY DEFINER wrapper around app.evaluate_permission for the PRC module, mirroring app.check_payroll_authority/app.check_finance_journal_authority''s own proven shape exactly -- an RLS using clause always runs as the querying role, and app.evaluate_permission itself is service_role-only, so a thin definer wrapper is required to embed a real PRC-module permission check directly into RLS rather than relying on tenant-membership-only visibility.';

grant execute on function app.check_procurement_authority(text, uuid, uuid) to authenticated, service_role;

drop policy vendor_compliance_documents_select_scoped on app.vendor_compliance_documents;
create policy vendor_compliance_documents_select_scoped on app.vendor_compliance_documents
  for select to authenticated
  using (
    app.is_supreme_admin()
    or (
      app.has_active_tenant_membership(tenant_id)
      and not app.actor_holds_customer_user_layer(tenant_id)
      and app.check_procurement_authority('View', tenant_id, (select auth.uid()))
    )
  );

drop policy rfq_response_attachments_select_scoped on app.rfq_response_attachments;
create policy rfq_response_attachments_select_scoped on app.rfq_response_attachments
  for select to authenticated
  using (
    app.is_supreme_admin()
    or (
      app.has_active_tenant_membership(tenant_id)
      and not app.actor_holds_customer_user_layer(tenant_id)
      and app.check_procurement_authority('View', tenant_id, (select auth.uid()))
    )
  );

revoke execute on all functions in schema app from public;
