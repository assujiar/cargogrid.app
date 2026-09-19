"use server";

/**
 * Vendor import Server Actions (CG-AUDIT-2026-09-02 A4, third import schema after
 * finance_opening_balance_import and employee_import). Every RPC this file calls
 * already existed, fully implemented and tested
 * (app.create_import_export_job/app.stage_import_rows/app.validate_vendor_import_row/
 * app.commit_vendor_import_job, plus PLT-121's generic config-draft primitives for
 * the one-time per-tenant bootstrap) -- this file is a near-mechanical port of
 * hris/imports/employees/actions.ts's own trio, swapping the HRS-specific
 * validate/commit adapters for their PRC equivalents.
 *
 * Unlike employee_import, only the import_export:vendor_import SCHEMA is already
 * registered as a global catalog row directly by
 * 20260830100000_create_vendor_import_adapter.sql -- the vendor_import_source
 * DOCUMENT TYPE was never registered by any real migration (only by db-test
 * fixtures, the exact finance_opening_balance_import pattern), fixed by
 * 20260917020000_register_vendor_import_source_document_type.sql. Each tenant still
 * separately publishes its own document:vendor_import_source and
 * import_export:vendor_import config VERSIONS (the same one-time per-tenant
 * bootstrap step every PLT-131 adopter requires).
 *
 * app.commit_vendor_import_job's own authority composition is stricter than
 * employee_import's: it requires BOTH app.is_support_grant_authority AND PRC:Import
 * (additive, never either-or) -- this action's own gate
 * (resolveProcurementAccessForRequest) is coarser and deliberately does not stand in
 * for either check, matching every other domain adapter's own precedent.
 *
 * Every RPC call in this file is service_role, matching each one's own
 * service_role-only (or service_role+authenticated) grant.
 */

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { randomUUID } from "node:crypto";
import { createSupabaseServiceRoleClient } from "../../../../../../lib/supabase/service-role.ts";
import { createSupabaseServerClient } from "../../../../../../lib/supabase/server.ts";
import { resolveProcurementAccessForRequest } from "../../../../../../lib/portal/resolve-procurement-access.server.ts";
import { resolveRequestClientIp } from "../../../../../../lib/security/client-ip.ts";
import { TENANT_DOCUMENTS_BUCKET_ID } from "../../../../../../lib/storage/tenant-documents-bucket.ts";
import { storeFileBytesAndEnqueueScan, type StorageUploadClient } from "../../../../../../lib/malware-scan/store-file-bytes-and-enqueue-scan.server.ts";
import { parseCsvToRows, CsvParseError } from "../../../../../../server/policies/csv-import-parse.ts";
import { createConfigDraft, setConfigItems, ConfigMutationError, type ConfigMutationRpcClient } from "../../../../../../server/mutations/config.ts";
import { publishDocumentTypeDefinition, initiateFileUpload, DocumentMutationError, type DocumentMutationRpcClient } from "../../../../../../server/mutations/document.ts";
import { publishImportExportSchema, createImportExportJob, stageImportRows, ImportExportMutationError, type ImportExportMutationRpcClient } from "../../../../../../server/mutations/import-export.ts";
import { listImportStagingRows, getImportExportJob, ImportExportQueryError, type ImportExportQueryRpcClient } from "../../../../../../server/queries/import-export.ts";
import { validateVendorImportRow, commitVendorImportJob, VendorProfileMutationError, type VendorProfileMutationRpcClient } from "../../../../../../server/mutations/vendor-profile.ts";
import type { BackgroundJobMutationRpcClient } from "../../../../../../server/mutations/background-job.ts";

const SCHEMA_CODE = "vendor_import";
const DOCUMENT_TYPE_CODE = "vendor_import_source";

const VENDOR_IMPORT_COLUMNS = [
  { key: "legal_name", label: "Legal name", required: true, data_type: "text" },
  { key: "trade_name", label: "Trade name", required: false, data_type: "text" },
  { key: "legal_entity_type", label: "Legal entity type", required: false, data_type: "text" },
  { key: "business_registration_number", label: "Business registration number", required: false, data_type: "text" },
  { key: "vendor_category", label: "Vendor category", required: false, data_type: "text" },
  { key: "payment_term_days", label: "Payment term (days)", required: false, data_type: "number" },
] as const;

export interface VendorImportActionState {
  readonly error: string | null;
}

const OK: VendorImportActionState = { error: null };
const NO_ACCESS: VendorImportActionState = { error: "You don't have access to this organization's Procurement workspace." };

type UnifiedClient = ConfigMutationRpcClient & DocumentMutationRpcClient & ImportExportMutationRpcClient & ImportExportQueryRpcClient & VendorProfileMutationRpcClient & StorageUploadClient;

function toUnifiedClient(client: ReturnType<typeof createSupabaseServiceRoleClient>): UnifiedClient {
  return client as unknown as UnifiedClient;
}

function toBackgroundJobClient(client: Awaited<ReturnType<typeof createSupabaseServerClient>>): BackgroundJobMutationRpcClient {
  return client as unknown as BackgroundJobMutationRpcClient;
}

/** One-time per-tenant setup: publishes both the document-type definition (file-upload rules) and the import schema's column definition -- everything a tenant needs before its first vendor-roster upload. Idempotent: createConfigDraft returns any already-pending draft rather than a new one, so re-running this after a partial failure safely resumes. */
export async function bootstrapVendorImportAction(tenantSlug: string, _prevState: VendorImportActionState, _formData: FormData): Promise<VendorImportActionState> {
  const access = await resolveProcurementAccessForRequest(tenantSlug);
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
      items: [{ key: "columns", value: [...VENDOR_IMPORT_COLUMNS], canonicalRef: null }],
      actorAuthUserId: access.authUserId,
      actorLabel: access.authUserId,
    });
    await publishImportExportSchema(client, { versionId: schemaDraft.id, actorAuthUserId: access.authUserId, effectiveFrom: new Date().toISOString(), actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof ConfigMutationError || error instanceof DocumentMutationError || error instanceof ImportExportMutationError) {
      return { error: `Could not set up vendor imports: ${error.message}` };
    }
    throw error;
  }

  revalidatePath(`/${tenantSlug}/procurement/imports/vendors`);
  return OK;
}

/** Uploads a real CSV source file (PLT-128, malware-scanned like every other real evidence upload this session's own A6 work established) and immediately opens a new import job against it -- job creation does not itself require the file to be clean yet (only staging does). The job's own payload carries the file's storage path forward, since app.import_staging_rows/app.files are not directly browsable and this is the one place that path is ever known. */
export async function uploadVendorImportSourceAction(tenantSlug: string, _prevState: VendorImportActionState, formData: FormData): Promise<VendorImportActionState> {
  const access = await resolveProcurementAccessForRequest(tenantSlug);
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

    const storeError = await storeFileBytesAndEnqueueScan(client, toBackgroundJobClient(supabase), uploaded, file, access.tenant.id, access.authUserId, "vendor roster source file");
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

  redirect(`/${tenantSlug}/procurement/imports/vendors?job=${createdJobId}`);
}

/** Downloads the job's own already-uploaded, already-scanned source file back from Storage (never re-accepts a fresh file at this step -- the staged rows must come from the SAME bytes that were scanned), parses it, and stages+validates every row in one action. Resumable: skips staging (never re-stages, which would duplicate every row) once the job already has staged rows, and only validates rows still pending. */
export async function stageAndValidateVendorImportRowsAction(tenantSlug: string, jobId: string, _prevState: VendorImportActionState, _formData: FormData): Promise<VendorImportActionState> {
  const access = await resolveProcurementAccessForRequest(tenantSlug);
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
        await validateVendorImportRow(client, { stagingRowId: row.id, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
      }
    }
  } catch (error) {
    if (error instanceof ImportExportMutationError || error instanceof ImportExportQueryError || error instanceof VendorProfileMutationError) {
      return { error: `Could not process this file: ${error.message}` };
    }
    throw error;
  }

  revalidatePath(`/${tenantSlug}/procurement/imports/vendors`);
  return OK;
}

/** Requires BOTH tenant_admin/Supreme authority AND PRC:Import, in-body -- this action's own gate (resolveProcurementAccessForRequest) is coarser and deliberately does not stand in for either check. Passes the caller's own client IP so the tenant's IP allowlist (if configured) is genuinely enforced, matching commitOpeningBalanceImportAction's own precedent. Never blocks on a flagged duplicate vendor -- app.commit_vendor_import_job's own duplicate sweeps flag for human review, they never refuse the commit. */
export async function commitVendorImportAction(tenantSlug: string, jobId: string, _prevState: VendorImportActionState, formData: FormData): Promise<VendorImportActionState> {
  const access = await resolveProcurementAccessForRequest(tenantSlug);
  if (access.status !== "allowed") return NO_ACCESS;

  const allowPartial = formData.get("allowPartial") === "on";
  const clientIp = await resolveRequestClientIp();

  const client = toUnifiedClient(createSupabaseServiceRoleClient());
  try {
    await commitVendorImportJob(client, { jobId, allowPartial, actorAuthUserId: access.authUserId, actorLabel: access.authUserId, clientIp });
  } catch (error) {
    if (error instanceof VendorProfileMutationError) {
      return { error: `Could not commit this import: ${error.message}` };
    }
    throw error;
  }

  revalidatePath(`/${tenantSlug}/procurement/imports/vendors`);
  return OK;
}
