"use server";

/**
 * Finance opening-balance import Server Actions (CG-AUDIT-2026-09-02 A4, narrowed
 * to the finance_opening_balance_import schema -- see this session's own backlog
 * entry for why this one schema was chosen over the other 11). Every RPC this file
 * calls already existed, fully implemented and tested
 * (app.create_import_export_job/app.stage_import_rows/app.validate_finance_opening_balance_import_row/
 * app.commit_finance_opening_balance_import_job, plus PLT-121's generic config-draft
 * primitives for the one-time per-tenant bootstrap) -- this file is pure wiring, the
 * same "UI over an already-working backend" shape as A1/A2/A3b/E5.
 *
 * Three real, previously-undiscovered gaps this slice closes (disclosed in the
 * backlog entry): (1) no real migration ever registered the
 * finance_opening_balance_source DOCUMENT TYPE (only db-test fixtures did,
 * the exact E5 pattern) -- fixed by
 * 20260914080000_register_finance_opening_balance_source_document_type.sql;
 * (2) no read RPC ever listed a job's own staged rows for a reviewer to see
 * WHICH row failed and WHY, and (3) app.jobs' own documented direct-table RLS
 * for `authenticated` is unreachable through PostgREST (app is not exposed to
 * it) -- both (2) and (3) fixed by
 * 20260914090000_create_import_export_job_detail_read_rpcs.sql's
 * app.list_import_staging_rows/app.get_import_export_job.
 *
 * Every RPC call in this file is service_role, matching each one's own
 * service_role-only grant.
 */

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { randomUUID } from "node:crypto";
import { createSupabaseServiceRoleClient } from "../../../../../../lib/supabase/service-role.ts";
import { createSupabaseServerClient } from "../../../../../../lib/supabase/server.ts";
import { resolveFinanceAccessForRequest } from "../../../../../../lib/portal/resolve-finance-access.server.ts";
import { resolveRequestClientIp } from "../../../../../../lib/security/client-ip.ts";
import { TENANT_DOCUMENTS_BUCKET_ID } from "../../../../../../lib/storage/tenant-documents-bucket.ts";
import { storeFileBytesAndEnqueueScan, type StorageUploadClient } from "../../../../../../lib/malware-scan/store-file-bytes-and-enqueue-scan.server.ts";
import { parseCsvToRows, CsvParseError } from "../../../../../../server/policies/csv-import-parse.ts";
import { createConfigDraft, setConfigItems, ConfigMutationError, type ConfigMutationRpcClient } from "../../../../../../server/mutations/config.ts";
import { publishDocumentTypeDefinition, initiateFileUpload, DocumentMutationError, type DocumentMutationRpcClient } from "../../../../../../server/mutations/document.ts";
import { publishImportExportSchema, createImportExportJob, stageImportRows, ImportExportMutationError, type ImportExportMutationRpcClient } from "../../../../../../server/mutations/import-export.ts";
import { listImportStagingRows, getImportExportJob, ImportExportQueryError, type ImportExportQueryRpcClient } from "../../../../../../server/queries/import-export.ts";
import { validateFinanceOpeningBalanceImportRow, commitFinanceOpeningBalanceImportJob, FinanceOpeningBalanceImportMutationError, type FinanceOpeningBalanceImportMutationRpcClient } from "../../../../../../server/mutations/finance-opening-balance-import.ts";
import type { BackgroundJobMutationRpcClient } from "../../../../../../server/mutations/background-job.ts";

const SCHEMA_CODE = "finance_opening_balance_import";
const DOCUMENT_TYPE_CODE = "finance_opening_balance_source";

const OPENING_BALANCE_COLUMNS = [
  { key: "open_item_type", label: "AR or AP", required: true, data_type: "text" },
  { key: "party_tax_id", label: "Customer tax id", required: false, data_type: "text" },
  { key: "party_legal_name", label: "Customer legal name", required: false, data_type: "text" },
  { key: "party_vendor_code", label: "Vendor code", required: false, data_type: "text" },
  { key: "currency", label: "Currency", required: true, data_type: "text" },
  { key: "original_amount", label: "Amount", required: true, data_type: "number" },
  { key: "document_date", label: "Document date", required: true, data_type: "date" },
  { key: "due_date", label: "Due date", required: true, data_type: "date" },
] as const;

export interface OpeningBalanceImportActionState {
  readonly error: string | null;
}

const OK: OpeningBalanceImportActionState = { error: null };
const NO_ACCESS: OpeningBalanceImportActionState = { error: "You don't have access to this organization's Finance workspace." };

type UnifiedClient = ConfigMutationRpcClient & DocumentMutationRpcClient & ImportExportMutationRpcClient & ImportExportQueryRpcClient & FinanceOpeningBalanceImportMutationRpcClient & StorageUploadClient;

function toUnifiedClient(client: ReturnType<typeof createSupabaseServiceRoleClient>): UnifiedClient {
  return client as unknown as UnifiedClient;
}

function toBackgroundJobClient(client: Awaited<ReturnType<typeof createSupabaseServerClient>>): BackgroundJobMutationRpcClient {
  return client as unknown as BackgroundJobMutationRpcClient;
}

/** One-time per-tenant setup: publishes both the document-type definition (file-upload rules) and the import schema's column definition -- everything a tenant needs before its first opening-balance upload. Idempotent: createConfigDraft returns any already-pending draft rather than a new one, so re-running this after a partial failure safely resumes. */
export async function bootstrapOpeningBalanceImportAction(tenantSlug: string, _prevState: OpeningBalanceImportActionState, _formData: FormData): Promise<OpeningBalanceImportActionState> {
  const access = await resolveFinanceAccessForRequest(tenantSlug);
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
        { key: "default_classification", value: "internal", canonicalRef: null },
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
      items: [{ key: "columns", value: [...OPENING_BALANCE_COLUMNS], canonicalRef: null }],
      actorAuthUserId: access.authUserId,
      actorLabel: access.authUserId,
    });
    await publishImportExportSchema(client, { versionId: schemaDraft.id, actorAuthUserId: access.authUserId, effectiveFrom: new Date().toISOString(), actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof ConfigMutationError || error instanceof DocumentMutationError || error instanceof ImportExportMutationError) {
      return { error: `Could not set up opening-balance imports: ${error.message}` };
    }
    throw error;
  }

  revalidatePath(`/${tenantSlug}/finance/imports/opening-balances`);
  return OK;
}

/** Uploads a real CSV source file (PLT-128, malware-scanned like every other real evidence upload this session's own A6 work established) and immediately opens a new import job against it -- job creation does not itself require the file to be clean yet (only staging does). The job's own payload carries the file's storage path forward, since app.import_staging_rows/app.files are not directly browsable and this is the one place that path is ever known. */
export async function uploadOpeningBalanceSourceAction(tenantSlug: string, _prevState: OpeningBalanceImportActionState, formData: FormData): Promise<OpeningBalanceImportActionState> {
  const access = await resolveFinanceAccessForRequest(tenantSlug);
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

    const storeError = await storeFileBytesAndEnqueueScan(client, toBackgroundJobClient(supabase), uploaded, file, access.tenant.id, access.authUserId, "opening balance source file");
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

  redirect(`/${tenantSlug}/finance/imports/opening-balances?job=${createdJobId}`);
}

/** Downloads the job's own already-uploaded, already-scanned source file back from Storage (never re-accepts a fresh file at this step -- the staged rows must come from the SAME bytes that were scanned), parses it, and stages+validates every row in one action. Resumable: skips staging (never re-stages, which would duplicate every row) once the job already has staged rows, and only validates rows still pending. */
export async function stageAndValidateOpeningBalanceRowsAction(tenantSlug: string, jobId: string, _prevState: OpeningBalanceImportActionState, _formData: FormData): Promise<OpeningBalanceImportActionState> {
  const access = await resolveFinanceAccessForRequest(tenantSlug);
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
        await validateFinanceOpeningBalanceImportRow(client, { stagingRowId: row.id, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
      }
    }
  } catch (error) {
    if (error instanceof ImportExportMutationError || error instanceof ImportExportQueryError || error instanceof FinanceOpeningBalanceImportMutationError) {
      return { error: `Could not process this file: ${error.message}` };
    }
    throw error;
  }

  revalidatePath(`/${tenantSlug}/finance/imports/opening-balances`);
  return OK;
}

/** Requires BOTH tenant_admin/Supreme authority and FIN:Import, in-body -- this action's own gate (resolveFinanceAccessForRequest) is coarser and deliberately does not stand in for either check. */
export async function commitOpeningBalanceImportAction(tenantSlug: string, jobId: string, _prevState: OpeningBalanceImportActionState, formData: FormData): Promise<OpeningBalanceImportActionState> {
  const access = await resolveFinanceAccessForRequest(tenantSlug);
  if (access.status !== "allowed") return NO_ACCESS;

  const allowPartial = formData.get("allowPartial") === "on";
  const clientIp = await resolveRequestClientIp();

  const client = toUnifiedClient(createSupabaseServiceRoleClient());
  try {
    await commitFinanceOpeningBalanceImportJob(client, { jobId, allowPartial, actorAuthUserId: access.authUserId, actorLabel: access.authUserId, clientIp });
  } catch (error) {
    if (error instanceof FinanceOpeningBalanceImportMutationError) {
      return { error: `Could not commit this import: ${error.message}` };
    }
    throw error;
  }

  revalidatePath(`/${tenantSlug}/finance/imports/opening-balances`);
  return OK;
}
