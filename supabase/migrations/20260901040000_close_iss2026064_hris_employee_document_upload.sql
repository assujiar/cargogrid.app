-- ISS-2026-064 item 2 (docs/runtime/KNOWN_ISSUES.md): the Employee Master Documents
-- tab lists app.files rows but has no write path -- a caller would have to script
-- app.initiate_file_upload directly. That primitive is service_role-only and gates on
-- nothing more than active tenant membership (app.check_file_action_authority,
-- 20260719140000_create_document_file_engine.sql:269-275) -- it has no concept of HRS
-- authority at all. The naive fix (call it directly from a Server Action with a
-- service-role client, the exact shape
-- app/(tenant)/[tenantSlug]/procurement/compliance/vendors/actions.ts already uses for
-- vendor_compliance evidence) would let ANY active tenant member -- including a
-- customer_user-layer principal or a plain HRS:View holder -- create a file row
-- against an employee's record before any HRS:Edit check ever runs. Live-verified
-- before writing this migration: no domain RPC anywhere in this repository currently
-- wraps app.initiate_file_upload with its own authority check (grep across every
-- migration -- the function is only ever called directly, from db-test fixtures and
-- from that one procurement Server Action) -- this is the first one.
--
-- app.initiate_employee_document_upload is a new, narrow, HRS:Edit-gated RPC that:
--   1. resolves the employee by master_record_id, folding "not found" and "actor has
--      no active membership in the employee's tenant" into the SAME employee_not_found
--      error -- app.assert_employee_editable_for_child_crud's own established
--      existence-oracle-safe shape (20260730830000:1695-1717), so a cross-tenant probe
--      learns nothing a genuinely nonexistent master_record_id wouldn't also produce.
--   2. separately checks real HRS:Edit authority via app.evaluate_permission (which
--      itself already asserts caller-is-session-identity internally, per that same
--      migration's own header, decision 8) -- never HRS:View, never coarse portal
--      entry.
--   3. refuses only an ARCHIVED employee (employee_closed) -- deliberately NOT reusing
--      app.assert_employee_editable_for_child_crud as-is, since that helper also
--      refuses 'terminated' (20260730830000:1712-1715), which would make it impossible
--      to file a termination letter or offboarding document against exactly the
--      employee it concerns. A terminated employee is still document-uploadable; only
--      a closed/archived profile is not. This decision is asserted, not just narrated,
--      in scripts/db-tests/hris-employee-master.sql's new regression block below.
--   4. only then delegates to app.initiate_file_upload for the actual metadata
--      recording (MIME/size/classification validation, idempotency, audit) --
--      reimplementing none of that.
--
-- document_type_code is hardcoded to 'employee_document' (the only document type ever
-- registered for this record type, 20260730830000:2501-2521) rather than accepted as a
-- caller-supplied parameter -- there is no second employee document type to choose
-- between, and accepting an arbitrary code here would let a caller target any
-- published document-type definition in the tenant through an HR-labeled entry point.
-- classification is passed straight through as p_classification (nullable) -- never a
-- hardcoded literal -- so a tenant's own published default_classification for
-- 'employee_document' (e.g. 'confidential', see the db-test fixture) always applies
-- when the caller does not name one; asserted below, not just assumed.
--
-- SECURITY DEFINER, `set search_path = app, pg_temp`, a blanket revoke-from-public plus
-- a targeted grant to authenticated + service_role, and a matching public.* wrapper --
-- mirroring 20260831060000_close_hris_authority_shape_rulings.sql's own
-- app.list_my_hiring_manager_vacancies / public.list_my_hiring_manager_vacancies pair
-- verbatim (a brand-new HRIS RPC that performs its own authority check and is called
-- through the RLS-scoped client, not a raw service-role-only primitive directly) --
-- verified live as this repository's current convention for exactly this shape before
-- writing this migration. scripts/db-tests/public-api-wrapper-regression.sql's own
-- exhaustive, catalog-derived assertions enforce the grant/security-mode parity between
-- the two automatically; no exception list to update.

create function app.assert_employee_document_upload_authority(p_master_record_id uuid, p_actor_auth_user_id uuid, out v_employee app.employees)
language plpgsql
as $$
declare
  v_decision app.rbac_decision;
begin
  select * into v_employee from app.employees where master_record_id = p_master_record_id for update;
  if not found or not app.has_active_tenant_membership(v_employee.tenant_id, p_actor_auth_user_id) then
    raise exception 'employee_not_found: %', p_master_record_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_employee.tenant_id, 'HRS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks HRS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_employee.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  -- Deliberately narrower than app.assert_employee_editable_for_child_crud, which also
  -- refuses 'terminated' -- an operational necessity here: offboarding/termination
  -- paperwork is filed against exactly a terminated employee. Only a closed/archived
  -- profile refuses further documents.
  if v_employee.lifecycle_status = 'archived' then
    raise exception 'employee_closed: employee % is archived -- documents may not be uploaded against a closed profile', p_master_record_id
      using errcode = 'check_violation';
  end if;
end;
$$;

comment on function app.assert_employee_document_upload_authority is 'ISS-2026-064 item 2: shared authority+state precondition for employee document upload -- HRS:Edit plus a non-archived lifecycle_status, under a `for update` row lock (mirrors app.assert_employee_editable_for_child_crud''s existence-oracle-safe shape exactly, but allows ''terminated'' where that helper does not -- see this migration''s own header).';

create function app.initiate_employee_document_upload(
  p_master_record_id uuid,
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
  v_employee app.employees;
  v_file app.files;
begin
  v_employee := app.assert_employee_document_upload_authority(p_master_record_id, p_actor_auth_user_id);

  v_file := app.initiate_file_upload(
    v_employee.tenant_id, 'employee_document', 'employee', p_master_record_id,
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

comment on function app.initiate_employee_document_upload is 'ISS-2026-064 item 2: HRS:Edit-gated employee-document upload -- resolves the employee, checks real domain authority (never the raw app.initiate_file_upload primitive''s own coarse tenant-membership-only gate), then delegates to app.initiate_file_upload for MIME/size/classification validation, idempotency and audit. document_type_code is fixed to ''employee_document'' -- the only document type ever registered for record_type=''employee''. Returns a storage_path-less projection (server/contracts/document/document.ts''s FileSummary shape) since this is callable directly by `authenticated`, unlike the raw primitive.';

-- Every prior migration's own established convention (e.g. 20260730950000,
-- 20260730930000): a brand-new function created by this same migration-applying role
-- otherwise retains an implicit PUBLIC EXECUTE grant the moment any explicit GRANT
-- statement first materializes its ACL (the schema-wide `alter default privileges` set
-- up in 20260717095000 does not by itself prevent this within a single migration's own
-- newly-created functions) -- this blanket revoke is the actual operative mechanism,
-- not merely defense-in-depth, exactly as every other migration in this repository
-- already relies on. It also leaves app.assert_employee_document_upload_authority with
-- NO grant at all (mirroring app.assert_employee_editable_for_child_crud, which carries
-- none either) -- callable only from within another SECURITY DEFINER function owned by
-- the same role, and deliberately never given its own public.* wrapper: an explicit
-- grant on it would make scripts/db-tests/public-api-wrapper-regression.sql's exhaustive
-- check demand one for a function nothing external should ever call directly.
revoke execute on all functions in schema app from public;

grant execute on function app.initiate_employee_document_upload(uuid, text, text, bigint, text, text, uuid, text) to authenticated, service_role;

-- public.* wrapper, security mode matching the app.* function exactly (RGL-394 Option
-- 2, mirroring 20260831060000's own app.list_my_hiring_manager_vacancies /
-- public.list_my_hiring_manager_vacancies pair verbatim). app is not exposed to
-- PostgREST, so without this the function is unreachable from the application.
create function public.initiate_employee_document_upload(
  p_master_record_id uuid, p_original_filename text, p_mime_type text, p_size_bytes bigint,
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
  select * from app.initiate_employee_document_upload(p_master_record_id, p_original_filename, p_mime_type, p_size_bytes, p_classification, p_idempotency_key, p_actor_auth_user_id, p_actor_label);
$wrap$;

comment on function public.initiate_employee_document_upload(uuid, text, text, bigint, text, text, uuid, text) is
  'RGL-394 Option-2 wrapper: app is not exposed to PostgREST; this is a thin security-definer pass-through to app.initiate_employee_document_upload, never a reimplementation.';

revoke execute on function public.initiate_employee_document_upload(uuid, text, text, bigint, text, text, uuid, text) from anon, authenticated, service_role, public;
grant execute on function public.initiate_employee_document_upload(uuid, text, text, bigint, text, text, uuid, text) to authenticated, service_role;
