"use server";

/**
 * Payroll loan cutover import Server Actions (CG-AUDIT-2026-09-02 A4,
 * eleventh import schema). Every RPC this file calls already existed, fully
 * implemented and tested (app.create_import_export_job/app.stage_import_rows/
 * app.validate_payroll_loan_cutover_import_row/
 * app.commit_payroll_loan_cutover_import_job, plus PLT-121's generic
 * config-draft primitives for the one-time per-tenant bootstrap) -- this
 * file is a near-mechanical port of
 * hris/imports/leave-opening-balance/actions.ts's own trio, swapping the
 * leave-specific validate/commit adapters for their payroll-loan
 * equivalents.
 *
 * The `payroll_loan_cutover_import` SCHEMA kind was already a real, global
 * app.import_export_schemas row
 * (20260901010000_create_payroll_loan_cutover_import_adapter.sql), but no
 * DOCUMENT TYPE for the raw source file had ever been registered anywhere --
 * scripts/db-tests/hris-payroll.sql's own bootstrap reuses the generic,
 * COM-owned master_data_import_source document type rather than a dedicated
 * one. Following this session's own leave_opening_balance_import precedent
 * (the exact same situation), this session registered a dedicated,
 * HRS-owned `payroll_loan_cutover_import_source` document type
 * (20260917060000_register_payroll_loan_cutover_import_source_document_type.sql),
 * mirroring timesheet_import_source's/attendance_device_import_source's/
 * leave_opening_balance_import_source's own one-document-type-per-schema
 * precedent rather than sharing a generic one -- payroll loan balances are
 * personal debt/financial obligation data tied to an individual employee,
 * genuinely warranting the same dedicated treatment. Each tenant must still
 * separately publish its own
 * `document:payroll_loan_cutover_import_source` and
 * `import_export:payroll_loan_cutover_import` config VERSIONS before a real
 * upload or stage can succeed -- this file's own bootstrap action.
 *
 * commit_payroll_loan_cutover_import_job's own authority composition is the
 * richest of any A4 import schema so far: app.is_support_grant_authority
 * (Supreme Admin or tenant_admin) AND HRS:Import AND HRS:Approve (additive,
 * never either-or) -- HRS:Approve is required because app.issue_payroll_loan
 * itself demands it of every caller issuing a loan, and bulk import is not
 * exempt from that same rule.
 *
 * Like the leave opening balance import, this is a one-time cutover load,
 * not a routine batch upload: the idempotency key is derived from the
 * staging row's own id (backed by a partial unique index on
 * app.payroll_loans), so re-running the SAME job is a safe no-op, but a
 * corrected re-upload creates a brand-new loan rather than correcting a
 * wrong one -- fixing a mistake requires cancelling/adjusting the loan
 * outside this wizard entirely.
 *
 * Every RPC call in this file is service_role, matching each one's own
 * service_role-only (or service_role+authenticated) grant.
 */

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { randomUUID } from "node:crypto";
import { createSupabaseServiceRoleClient } from "../../../../../../lib/supabase/service-role.ts";
import { createSupabaseServerClient } from "../../../../../../lib/supabase/server.ts";
import { resolveHrisAccessForRequest } from "../../../../../../lib/portal/resolve-hris-access.server.ts";
import { resolveRequestClientIp } from "../../../../../../lib/security/client-ip.ts";
import { TENANT_DOCUMENTS_BUCKET_ID } from "../../../../../../lib/storage/tenant-documents-bucket.ts";
import { storeFileBytesAndEnqueueScan, type StorageUploadClient } from "../../../../../../lib/malware-scan/store-file-bytes-and-enqueue-scan.server.ts";
import { parseCsvToRows, CsvParseError } from "../../../../../../server/policies/csv-import-parse.ts";
import { createConfigDraft, setConfigItems, ConfigMutationError, type ConfigMutationRpcClient } from "../../../../../../server/mutations/config.ts";
import { publishDocumentTypeDefinition, initiateFileUpload, DocumentMutationError, type DocumentMutationRpcClient } from "../../../../../../server/mutations/document.ts";
import { publishImportExportSchema, createImportExportJob, stageImportRows, ImportExportMutationError, type ImportExportMutationRpcClient } from "../../../../../../server/mutations/import-export.ts";
import { listImportStagingRows, getImportExportJob, ImportExportQueryError, type ImportExportQueryRpcClient } from "../../../../../../server/queries/import-export.ts";
import { validatePayrollLoanCutoverImportRow, commitPayrollLoanCutoverImportJob, PayrollMutationError, type PayrollMutationRpcClient } from "../../../../../../server/mutations/payroll.ts";
import type { BackgroundJobMutationRpcClient } from "../../../../../../server/mutations/background-job.ts";

const SCHEMA_CODE = "payroll_loan_cutover_import";
const DOCUMENT_TYPE_CODE = "payroll_loan_cutover_import_source";

const PAYROLL_LOAN_CUTOVER_IMPORT_COLUMNS = [
  { key: "employee_number", label: "Employee Number", required: true, data_type: "text" },
  { key: "principal_amount", label: "Original Principal", required: true, data_type: "number" },
  { key: "currency", label: "Currency", required: false, data_type: "text" },
  { key: "installment_amount", label: "Installment Amount", required: true, data_type: "number" },
  { key: "term_count", label: "Term (Installments)", required: true, data_type: "number" },
  { key: "remaining_installments", label: "Remaining Installments As Of Cutover", required: true, data_type: "number" },
  { key: "notes", label: "Notes", required: false, data_type: "text" },
] as const;

export interface PayrollLoanCutoverImportActionState {
  readonly error: string | null;
}

const OK: PayrollLoanCutoverImportActionState = { error: null };
const NO_ACCESS: PayrollLoanCutoverImportActionState = { error: "You don't have access to this organization's HR workspace." };

type UnifiedClient = ConfigMutationRpcClient & DocumentMutationRpcClient & ImportExportMutationRpcClient & ImportExportQueryRpcClient & PayrollMutationRpcClient & StorageUploadClient;

function toUnifiedClient(client: ReturnType<typeof createSupabaseServiceRoleClient>): UnifiedClient {
  return client as unknown as UnifiedClient;
}

function toBackgroundJobClient(client: Awaited<ReturnType<typeof createSupabaseServerClient>>): BackgroundJobMutationRpcClient {
  return client as unknown as BackgroundJobMutationRpcClient;
}

/** One-time per-tenant setup: publishes both the document-type definition (file-upload rules) and the import schema's column definition -- everything a tenant needs before its first loan cutover upload. Idempotent: createConfigDraft returns any already-pending draft rather than a new one, so re-running this after a partial failure safely resumes. */
export async function bootstrapPayrollLoanCutoverImportAction(tenantSlug: string, _prevState: PayrollLoanCutoverImportActionState, _formData: FormData): Promise<PayrollLoanCutoverImportActionState> {
  const access = await resolveHrisAccessForRequest(tenantSlug);
  if (access.status !== "allowed") return NO_ACCESS;

  const client = toUnifiedClient(createSupabaseServiceRoleClient());

  try {
    const docTypeDraft = await createConfigDraft(client, {
      configTypeCode: `document:${DOCUMENT_TYPE_CODE}`,
      tenantId: access.tenant.id,
      scopeLevel: "tenant",
      scopeId: null,
      actorAuthUserId: access.authUserId,
      createdBy: access.authUserId,
    });
    await setConfigItems(client, {
      versionId: docTypeDraft.id,
      items: [
        { key: "allowed_mime_types", value: ["text/csv"], canonicalRef: null },
        { key: "max_size_bytes", value: 10485760, canonicalRef: null },
        { key: "retention_class", value: "operational_contract_plus_90d", canonicalRef: null },
        { key: "default_classification", value: "confidential", canonicalRef: null },
        { key: "legal_hold_eligible", value: false, canonicalRef: null },
      ],
      actorAuthUserId: access.authUserId,
      actorLabel: access.authUserId,
    });
    await publishDocumentTypeDefinition(client, { versionId: docTypeDraft.id, actorAuthUserId: access.authUserId, effectiveFrom: null, actorLabel: access.authUserId });

    const schemaDraft = await createConfigDraft(client, {
      configTypeCode: `import_export:${SCHEMA_CODE}`,
      tenantId: access.tenant.id,
      scopeLevel: "tenant",
      scopeId: null,
      actorAuthUserId: access.authUserId,
      createdBy: access.authUserId,
    });
    await setConfigItems(client, {
      versionId: schemaDraft.id,
      items: [{ key: "columns", value: [...PAYROLL_LOAN_CUTOVER_IMPORT_COLUMNS], canonicalRef: null }],
      actorAuthUserId: access.authUserId,
      actorLabel: access.authUserId,
    });
    await publishImportExportSchema(client, { versionId: schemaDraft.id, actorAuthUserId: access.authUserId, effectiveFrom: new Date().toISOString(), actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof ConfigMutationError || error instanceof DocumentMutationError || error instanceof ImportExportMutationError) {
      return { error: `Could not set up payroll loan cutover imports: ${error.message}` };
    }
    throw error;
  }

  revalidatePath(`/${tenantSlug}/hris/imports/payroll-loans`);
  return OK;
}

/** Uploads a real CSV source file (PLT-128, malware-scanned like every other real evidence upload this session's own A6 work established) and immediately opens a new import job against it -- job creation does not itself require the file to be clean yet (only staging does). The job's own payload carries the file's storage path forward, since app.import_staging_rows/app.files are not directly browsable and this is the one place that path is ever known. */
export async function uploadPayrollLoanCutoverImportSourceAction(tenantSlug: string, _prevState: PayrollLoanCutoverImportActionState, formData: FormData): Promise<PayrollLoanCutoverImportActionState> {
  const access = await resolveHrisAccessForRequest(tenantSlug);
  if (access.status !== "allowed") return NO_ACCESS;

  const file = formData.get("sourceFile");
  if (!(file instanceof File) || file.size === 0) {
    return { error: "Choose a CSV file to upload." };
  }

  const serviceRole = createSupabaseServiceRoleClient();
  const client = toUnifiedClient(serviceRole);
  const supabase = await createSupabaseServerClient();

  let createdJobId: string;
  try {
    const uploaded = await initiateFileUpload(client, {
      tenantId: access.tenant.id,
      documentTypeCode: DOCUMENT_TYPE_CODE,
      recordType: "import_source",
      recordId: randomUUID(),
      originalFilename: file.name,
      mimeType: file.type || "text/csv",
      sizeBytes: file.size,
      classification: null,
      legalHold: false,
      legalHoldReason: null,
      sharedOrgUnitIds: [],
      customerAccountRef: null,
      idempotencyKey: null,
      actorAuthUserId: access.authUserId,
      actorLabel: access.authUserId,
    });

    const storeError = await storeFileBytesAndEnqueueScan(client, toBackgroundJobClient(supabase), uploaded, file, access.tenant.id, access.authUserId, "payroll loan cutover source file");
    if (storeError) {
      return storeError;
    }

    const createdJob = await createImportExportJob(client, {
      tenantId: access.tenant.id,
      jobType: "import",
      schemaCode: SCHEMA_CODE,
      sourceFileId: uploaded.id,
      filters: { source_storage_path: uploaded.storagePath, source_mime_type: uploaded.mimeType, source_original_filename: uploaded.originalFilename },
      idempotencyKey: null,
      actorAuthUserId: access.authUserId,
      actorLabel: access.authUserId,
    });
    createdJobId = createdJob.jobId;
  } catch (error) {
    if (error instanceof DocumentMutationError || error instanceof ImportExportMutationError) {
      return { error: `Could not start this import: ${error.message}` };
    }
    throw error;
  }

  redirect(`/${tenantSlug}/hris/imports/payroll-loans?job=${createdJobId}`);
}

/** Downloads the job's own already-uploaded, already-scanned source file back from Storage (never re-accepts a fresh file at this step -- the staged rows must come from the SAME bytes that were scanned), parses it, and stages+validates every row in one action. Resumable: skips staging (never re-stages, which would duplicate every row) once the job already has staged rows, and only validates rows still pending. */
export async function stageAndValidatePayrollLoanCutoverImportRowsAction(tenantSlug: string, jobId: string, _prevState: PayrollLoanCutoverImportActionState, _formData: FormData): Promise<PayrollLoanCutoverImportActionState> {
  const access = await resolveHrisAccessForRequest(tenantSlug);
  if (access.status !== "allowed") return NO_ACCESS;

  const serviceRole = createSupabaseServiceRoleClient();
  const client = toUnifiedClient(serviceRole);

  let job;
  try {
    job = await getImportExportJob(client, { jobId, actorAuthUserId: access.authUserId });
  } catch (error) {
    if (error instanceof ImportExportQueryError) return { error: "Could not find this import job." };
    throw error;
  }

  try {
    if (job.totalRows === null || job.totalRows === 0) {
      const storagePath = job.payload.source_storage_path;
      if (typeof storagePath !== "string") {
        return { error: "This job has no recorded source file path -- it may have been created outside this UI." };
      }
      const { data: blob, error: downloadError } = await serviceRole.storage.from(TENANT_DOCUMENTS_BUCKET_ID).download(storagePath);
      if (downloadError || !blob) {
        return { error: `Could not read the uploaded file: ${downloadError?.message ?? "no data returned"}` };
      }
      let rows: Record<string, string>[];
      try {
        rows = parseCsvToRows(await blob.text());
      } catch (error) {
        if (error instanceof CsvParseError) return { error: `Could not parse this CSV file: ${error.message}` };
        throw error;
      }
      await stageImportRows(client, { jobId, rows, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
    }

    const stagedRows = await listImportStagingRows(client, { jobId, actorAuthUserId: access.authUserId });
    for (const row of stagedRows) {
      if (row.validationStatus === "pending") {
        await validatePayrollLoanCutoverImportRow(client, { stagingRowId: row.id, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
      }
    }
  } catch (error) {
    if (error instanceof ImportExportMutationError || error instanceof ImportExportQueryError || error instanceof PayrollMutationError) {
      return { error: `Could not process this file: ${error.message}` };
    }
    throw error;
  }

  revalidatePath(`/${tenantSlug}/hris/imports/payroll-loans`);
  return OK;
}

/** Requires BOTH is_support_grant_authority AND HRS:Import AND HRS:Approve, in-body -- this action's own gate (resolveHrisAccessForRequest) is coarser and deliberately does not stand in for it; a caller holding only HRS:Import is refused here. Passes the caller's own client IP so the tenant's IP allowlist (if configured) is genuinely enforced, and so the tenant's conditional MFA step-up gate (if configured) is genuinely reachable, matching commitLeaveOpeningBalanceImportAction's own precedent. */
export async function commitPayrollLoanCutoverImportAction(tenantSlug: string, jobId: string, _prevState: PayrollLoanCutoverImportActionState, formData: FormData): Promise<PayrollLoanCutoverImportActionState> {
  const access = await resolveHrisAccessForRequest(tenantSlug);
  if (access.status !== "allowed") return NO_ACCESS;

  const allowPartial = formData.get("allowPartial") === "on";
  const clientIp = await resolveRequestClientIp();

  const client = toUnifiedClient(createSupabaseServiceRoleClient());
  try {
    await commitPayrollLoanCutoverImportJob(client, { jobId, allowPartial, actorAuthUserId: access.authUserId, actorLabel: access.authUserId, clientIp });
  } catch (error) {
    if (error instanceof PayrollMutationError) {
      return { error: `Could not commit this import: ${error.message}` };
    }
    throw error;
  }

  revalidatePath(`/${tenantSlug}/hris/imports/payroll-loans`);
  return OK;
}
