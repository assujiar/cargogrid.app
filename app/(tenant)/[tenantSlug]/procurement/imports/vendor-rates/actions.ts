"use server";

/**
 * Vendor rate import Server Actions (CG-AUDIT-2026-09-02 A4, fourth import schema
 * after finance_opening_balance_import, employee_import, and vendor_import). Every
 * RPC this file calls already existed, fully implemented and tested
 * (app.create_import_export_job/app.stage_import_rows/app.validate_vendor_rate_import_row/
 * app.commit_vendor_rate_import_job, plus PLT-121's generic config-draft primitives
 * for the one-time per-tenant bootstrap) -- this file is a near-mechanical port of
 * procurement/imports/vendors/actions.ts's own trio, swapping the vendor-profile
 * validate/commit adapters for their vendor-rate equivalents.
 *
 * Unlike vendor_import (and like finance_opening_balance_import), the
 * import_export:vendor_rate_import SCHEMA was already registered as a real global
 * catalog row directly by
 * 20260730620000_extend_commercial_vendor_rate_for_procurement.sql -- only the
 * vendor_rate_import_source DOCUMENT TYPE was never registered by any real
 * migration (only by a db-test fixture, the exact vendor_import_source gap
 * repeated a third time), fixed by
 * 20260917030000_register_vendor_rate_import_source_document_type.sql.
 *
 * server/mutations/procurement-rate.ts already had a complete
 * validateVendorRateImportRow/commitVendorRateImportJob wrapper before this slice
 * -- unlike vendor_import, which needed one built from scratch -- this slice only
 * had to close two small parity gaps in it (commit never passed the RPC's own
 * p_client_ip param, and the error-code allowlist was missing ip_not_allowed/
 * mfa_step_up_required), mirroring the exact class of fix employee_import's own
 * scoping found in server/mutations/employee.ts.
 *
 * app.commit_vendor_rate_import_job's own authority composition matches
 * vendor_import's: BOTH app.is_support_grant_authority AND PRC:Import, additive,
 * never either alone -- this action's own gate (resolveProcurementAccessForRequest)
 * is coarser and deliberately does not stand in for either check.
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
import { validateVendorRateImportRow, commitVendorRateImportJob, ProcurementRateMutationError, type ProcurementRateMutationRpcClient } from "../../../../../../server/mutations/procurement-rate.ts";
import { VENDOR_RATE_IMPORT_SCHEMA_CODE, VENDOR_RATE_IMPORT_COLUMNS } from "../../../../../../server/contracts/procurement-rate/procurement-rate.ts";
import type { BackgroundJobMutationRpcClient } from "../../../../../../server/mutations/background-job.ts";

const SCHEMA_CODE = VENDOR_RATE_IMPORT_SCHEMA_CODE;
const DOCUMENT_TYPE_CODE = "vendor_rate_import_source";

export interface VendorRateImportActionState {
  readonly error: string | null;
}

const OK: VendorRateImportActionState = { error: null };
const NO_ACCESS: VendorRateImportActionState = { error: "You don't have access to this organization's Procurement workspace." };

type UnifiedClient = ConfigMutationRpcClient & DocumentMutationRpcClient & ImportExportMutationRpcClient & ImportExportQueryRpcClient & ProcurementRateMutationRpcClient & StorageUploadClient;

function toUnifiedClient(client: ReturnType<typeof createSupabaseServiceRoleClient>): UnifiedClient {
  return client as unknown as UnifiedClient;
}

function toBackgroundJobClient(client: Awaited<ReturnType<typeof createSupabaseServerClient>>): BackgroundJobMutationRpcClient {
  return client as unknown as BackgroundJobMutationRpcClient;
}

/** One-time per-tenant setup: publishes both the document-type definition (file-upload rules) and the import schema's column definition -- everything a tenant needs before its first vendor-rate upload. Publishes the FULL 31-column contract (VENDOR_RATE_IMPORT_COLUMNS, 13 flat fields plus 3 tier blocks of 6 fields each) -- app.commit_vendor_rate_import_job loops all 3 tier slots, not just the one scripts/db-tests/procurement-vendor-rate-tiers.sql's own fixture exercises for brevity. Idempotent: createConfigDraft returns any already-pending draft rather than a new one, so re-running this after a partial failure safely resumes. */
export async function bootstrapVendorRateImportAction(tenantSlug: string, _prevState: VendorRateImportActionState, _formData: FormData): Promise<VendorRateImportActionState> {
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
      items: [{ key: "columns", value: [...VENDOR_RATE_IMPORT_COLUMNS], canonicalRef: null }],
      actorAuthUserId: access.authUserId,
      actorLabel: access.authUserId,
    });
    await publishImportExportSchema(client, { versionId: schemaDraft.id, actorAuthUserId: access.authUserId, effectiveFrom: new Date().toISOString(), actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof ConfigMutationError || error instanceof DocumentMutationError || error instanceof ImportExportMutationError) {
      return { error: `Could not set up vendor rate imports: ${error.message}` };
    }
    throw error;
  }

  revalidatePath(`/${tenantSlug}/procurement/imports/vendor-rates`);
  return OK;
}

/** Uploads a real CSV source file (PLT-128, malware-scanned like every other real evidence upload this session's own A6 work established) and immediately opens a new import job against it -- job creation does not itself require the file to be clean yet (only staging does). The job's own payload carries the file's storage path forward, since app.import_staging_rows/app.files are not directly browsable and this is the one place that path is ever known. */
export async function uploadVendorRateImportSourceAction(tenantSlug: string, _prevState: VendorRateImportActionState, formData: FormData): Promise<VendorRateImportActionState> {
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

    const storeError = await storeFileBytesAndEnqueueScan(client, toBackgroundJobClient(supabase), uploaded, file, access.tenant.id, access.authUserId, "vendor rate source file");
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

  redirect(`/${tenantSlug}/procurement/imports/vendor-rates?job=${createdJobId}`);
}

/** Downloads the job's own already-uploaded, already-scanned source file back from Storage (never re-accepts a fresh file at this step -- the staged rows must come from the SAME bytes that were scanned), parses it, and stages+validates every row in one action. Resumable: skips staging (never re-stages, which would duplicate every row) once the job already has staged rows, and only validates rows still pending. */
export async function stageAndValidateVendorRateImportRowsAction(tenantSlug: string, jobId: string, _prevState: VendorRateImportActionState, _formData: FormData): Promise<VendorRateImportActionState> {
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
        await validateVendorRateImportRow(client, { stagingRowId: row.id, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
      }
    }
  } catch (error) {
    if (error instanceof ImportExportMutationError || error instanceof ImportExportQueryError || error instanceof ProcurementRateMutationError) {
      return { error: `Could not process this file: ${error.message}` };
    }
    throw error;
  }

  revalidatePath(`/${tenantSlug}/procurement/imports/vendor-rates`);
  return OK;
}

/** Requires BOTH tenant_admin/Supreme authority AND PRC:Import, in-body -- this action's own gate (resolveProcurementAccessForRequest) is coarser and deliberately does not stand in for either check. Passes the caller's own client IP so the tenant's IP allowlist (if configured) is genuinely enforced. Imported rates land as pending_approval, exactly like manually-created ones -- a separate, deliberate approval step is still required afterward on each rate's own detail page. */
export async function commitVendorRateImportAction(tenantSlug: string, jobId: string, _prevState: VendorRateImportActionState, formData: FormData): Promise<VendorRateImportActionState> {
  const access = await resolveProcurementAccessForRequest(tenantSlug);
  if (access.status !== "allowed") return NO_ACCESS;

  const allowPartial = formData.get("allowPartial") === "on";
  const clientIp = await resolveRequestClientIp();

  const client = toUnifiedClient(createSupabaseServiceRoleClient());
  try {
    await commitVendorRateImportJob(client, { jobId, allowPartial, actorAuthUserId: access.authUserId, actorLabel: access.authUserId, clientIp });
  } catch (error) {
    if (error instanceof ProcurementRateMutationError) {
      return { error: `Could not commit this import: ${error.message}` };
    }
    throw error;
  }

  revalidatePath(`/${tenantSlug}/procurement/imports/vendor-rates`);
  return OK;
}
