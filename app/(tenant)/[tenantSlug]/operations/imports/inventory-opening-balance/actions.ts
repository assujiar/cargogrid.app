"use server";

/**
 * Inventory opening balance import Server Actions (CG-AUDIT-2026-09-02 A4,
 * twelfth and FINAL import schema). Every RPC this file calls already
 * existed, fully implemented and tested
 * (app.create_import_export_job/app.stage_import_rows/
 * app.validate_inventory_opening_balance_import_row/
 * app.commit_inventory_opening_balance_import_job, plus PLT-121's generic
 * config-draft primitives for the one-time per-tenant bootstrap) -- this
 * file is a near-mechanical port of
 * hris/imports/payroll-loans/actions.ts's own trio, swapping the
 * payroll-specific validate/commit adapters for their inventory equivalents.
 *
 * The `inventory_opening_balance_import` SCHEMA kind was already a real,
 * global app.import_export_schemas row
 * (20260831260000_create_inventory_and_leave_opening_balance_import_adapters.sql
 * -- the SAME migration that also creates leave_opening_balance_import's
 * own schema kind), but no dedicated DOCUMENT TYPE existed anywhere for
 * this schema's own source file -- scripts/db-tests/master-data-import.sql's
 * own bootstrap reuses the generic, COM-owned master_data_import_source
 * document type. Following this session's own leave_opening_balance_import
 * and payroll_loan_cutover_import precedent (the exact same situation, both
 * declining that reuse), this session registered a dedicated, OPS-owned
 * `inventory_opening_balance_import_source` document type
 * (20260917070000_register_inventory_opening_balance_import_source_document_type.sql).
 * Each tenant must still separately publish its own
 * `document:inventory_opening_balance_import_source` and
 * `import_export:inventory_opening_balance_import` config VERSIONS before a
 * real upload or stage can succeed -- this file's own bootstrap action.
 *
 * commit_inventory_opening_balance_import_job requires BOTH
 * app.is_support_grant_authority (Supreme Admin or tenant_admin) AND
 * OPS:Import (additive, never either-or). The importer ALSO needs genuine
 * record scope over each row's own warehouse -- app.post_inventory_movement
 * checks app.can_access_record against the warehouse's own company org
 * unit, invisible in the RPC's own guard list since it lives inside the
 * primitive itself; a caller who passes every other gate can still be
 * refused deep inside the commit if they lack that scope.
 *
 * Like the leave/payroll opening-balance imports, this is a one-time
 * cutover load, not a routine batch upload: the idempotency key is derived
 * from the staging row's own id, so re-running the SAME job is a safe
 * no-op, but a corrected re-upload posts a brand-new, additive movement
 * rather than correcting a wrong one -- fixing a mistake requires the
 * separate app.reverse_inventory_movement path (already wrapped as
 * reverseInventoryMovement in server/mutations/inventory-ledger.ts),
 * outside this wizard entirely.
 *
 * No warehouse/inventory-management admin page exists anywhere in this
 * codebase yet (confirmed by repo-wide search before writing this file,
 * mirroring item_import's own identical situation) -- this page is
 * therefore standalone and unlinked, mirroring finance/config/page.tsx's
 * own precedent, rather than invented navigation for a host page that does
 * not exist.
 *
 * Every RPC call in this file is service_role, matching each one's own
 * service_role-only (or service_role+authenticated) grant.
 */

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { randomUUID } from "node:crypto";
import { createSupabaseServiceRoleClient } from "../../../../../../lib/supabase/service-role.ts";
import { createSupabaseServerClient } from "../../../../../../lib/supabase/server.ts";
import { resolveOperationsAccessForRequest } from "../../../../../../lib/portal/resolve-operations-access.server.ts";
import { resolveRequestClientIp } from "../../../../../../lib/security/client-ip.ts";
import { TENANT_DOCUMENTS_BUCKET_ID } from "../../../../../../lib/storage/tenant-documents-bucket.ts";
import { storeFileBytesAndEnqueueScan, type StorageUploadClient } from "../../../../../../lib/malware-scan/store-file-bytes-and-enqueue-scan.server.ts";
import { parseCsvToRows, CsvParseError } from "../../../../../../server/policies/csv-import-parse.ts";
import { createConfigDraft, setConfigItems, ConfigMutationError, type ConfigMutationRpcClient } from "../../../../../../server/mutations/config.ts";
import { publishDocumentTypeDefinition, initiateFileUpload, DocumentMutationError, type DocumentMutationRpcClient } from "../../../../../../server/mutations/document.ts";
import { publishImportExportSchema, createImportExportJob, stageImportRows, ImportExportMutationError, type ImportExportMutationRpcClient } from "../../../../../../server/mutations/import-export.ts";
import { listImportStagingRows, getImportExportJob, ImportExportQueryError, type ImportExportQueryRpcClient } from "../../../../../../server/queries/import-export.ts";
import { validateInventoryOpeningBalanceImportRow, commitInventoryOpeningBalanceImportJob, InventoryLedgerMutationError, type InventoryLedgerMutationRpcClient } from "../../../../../../server/mutations/inventory-ledger.ts";
import type { BackgroundJobMutationRpcClient } from "../../../../../../server/mutations/background-job.ts";

const SCHEMA_CODE = "inventory_opening_balance_import";
const DOCUMENT_TYPE_CODE = "inventory_opening_balance_import_source";

const INVENTORY_OPENING_BALANCE_IMPORT_COLUMNS = [
  { key: "warehouse_code", label: "Warehouse", required: true, data_type: "text" },
  { key: "location_code", label: "Location", required: true, data_type: "text" },
  { key: "owner_account_tax_id", label: "Owner Tax Id", required: true, data_type: "text" },
  { key: "item_code", label: "Item Code", required: true, data_type: "text" },
  { key: "uom_code", label: "UOM", required: true, data_type: "text" },
  { key: "quantity", label: "Quantity", required: true, data_type: "number" },
  { key: "lot_number", label: "Lot Number", required: false, data_type: "text" },
  { key: "serial_number", label: "Serial Number", required: false, data_type: "text" },
  { key: "expiry_date", label: "Expiry Date", required: false, data_type: "text" },
  { key: "status", label: "Status", required: false, data_type: "text" },
] as const;

export interface InventoryOpeningBalanceImportActionState {
  readonly error: string | null;
}

const OK: InventoryOpeningBalanceImportActionState = { error: null };
const NO_ACCESS: InventoryOpeningBalanceImportActionState = { error: "You don't have access to this organization's Operations workspace." };

type UnifiedClient = ConfigMutationRpcClient & DocumentMutationRpcClient & ImportExportMutationRpcClient & ImportExportQueryRpcClient & InventoryLedgerMutationRpcClient & StorageUploadClient;

function toUnifiedClient(client: ReturnType<typeof createSupabaseServiceRoleClient>): UnifiedClient {
  return client as unknown as UnifiedClient;
}

function toBackgroundJobClient(client: Awaited<ReturnType<typeof createSupabaseServerClient>>): BackgroundJobMutationRpcClient {
  return client as unknown as BackgroundJobMutationRpcClient;
}

/** One-time per-tenant setup: publishes both the document-type definition (file-upload rules) and the import schema's column definition -- everything a tenant needs before its first inventory cutover upload. Idempotent: createConfigDraft returns any already-pending draft rather than a new one, so re-running this after a partial failure safely resumes. */
export async function bootstrapInventoryOpeningBalanceImportAction(tenantSlug: string, _prevState: InventoryOpeningBalanceImportActionState, _formData: FormData): Promise<InventoryOpeningBalanceImportActionState> {
  const access = await resolveOperationsAccessForRequest(tenantSlug);
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
      items: [{ key: "columns", value: [...INVENTORY_OPENING_BALANCE_IMPORT_COLUMNS], canonicalRef: null }],
      actorAuthUserId: access.authUserId,
      actorLabel: access.authUserId,
    });
    await publishImportExportSchema(client, { versionId: schemaDraft.id, actorAuthUserId: access.authUserId, effectiveFrom: new Date().toISOString(), actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof ConfigMutationError || error instanceof DocumentMutationError || error instanceof ImportExportMutationError) {
      return { error: `Could not set up inventory opening balance imports: ${error.message}` };
    }
    throw error;
  }

  revalidatePath(`/${tenantSlug}/operations/imports/inventory-opening-balance`);
  return OK;
}

/** Uploads a real CSV source file (PLT-128, malware-scanned like every other real evidence upload this session's own A6 work established) and immediately opens a new import job against it -- job creation does not itself require the file to be clean yet (only staging does). The job's own payload carries the file's storage path forward, since app.import_staging_rows/app.files are not directly browsable and this is the one place that path is ever known. */
export async function uploadInventoryOpeningBalanceImportSourceAction(tenantSlug: string, _prevState: InventoryOpeningBalanceImportActionState, formData: FormData): Promise<InventoryOpeningBalanceImportActionState> {
  const access = await resolveOperationsAccessForRequest(tenantSlug);
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

    const storeError = await storeFileBytesAndEnqueueScan(client, toBackgroundJobClient(supabase), uploaded, file, access.tenant.id, access.authUserId, "inventory opening balance source file");
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

  redirect(`/${tenantSlug}/operations/imports/inventory-opening-balance?job=${createdJobId}`);
}

/** Downloads the job's own already-uploaded, already-scanned source file back from Storage (never re-accepts a fresh file at this step -- the staged rows must come from the SAME bytes that were scanned), parses it, and stages+validates every row in one action. Resumable: skips staging (never re-stages, which would duplicate every row) once the job already has staged rows, and only validates rows still pending. */
export async function stageAndValidateInventoryOpeningBalanceImportRowsAction(tenantSlug: string, jobId: string, _prevState: InventoryOpeningBalanceImportActionState, _formData: FormData): Promise<InventoryOpeningBalanceImportActionState> {
  const access = await resolveOperationsAccessForRequest(tenantSlug);
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
        await validateInventoryOpeningBalanceImportRow(client, { stagingRowId: row.id, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
      }
    }
  } catch (error) {
    if (error instanceof ImportExportMutationError || error instanceof ImportExportQueryError || error instanceof InventoryLedgerMutationError) {
      return { error: `Could not process this file: ${error.message}` };
    }
    throw error;
  }

  revalidatePath(`/${tenantSlug}/operations/imports/inventory-opening-balance`);
  return OK;
}

/** Requires BOTH is_support_grant_authority AND OPS:Import, in-body -- this action's own gate (resolveOperationsAccessForRequest) is coarser and deliberately does not stand in for it. Passes the caller's own client IP so the tenant's IP allowlist (if configured) is genuinely enforced, and so the tenant's conditional MFA step-up gate (if configured) is genuinely reachable, matching commitPayrollLoanCutoverImportAction's own precedent. The importer also needs genuine record scope over each row's own warehouse -- a refusal from that check surfaces as a plain commit error here, not a distinct code, since it originates deep inside app.post_inventory_movement rather than this adapter's own guard list. */
export async function commitInventoryOpeningBalanceImportAction(tenantSlug: string, jobId: string, _prevState: InventoryOpeningBalanceImportActionState, formData: FormData): Promise<InventoryOpeningBalanceImportActionState> {
  const access = await resolveOperationsAccessForRequest(tenantSlug);
  if (access.status !== "allowed") return NO_ACCESS;

  const allowPartial = formData.get("allowPartial") === "on";
  const clientIp = await resolveRequestClientIp();

  const client = toUnifiedClient(createSupabaseServiceRoleClient());
  try {
    await commitInventoryOpeningBalanceImportJob(client, { jobId, allowPartial, actorAuthUserId: access.authUserId, actorLabel: access.authUserId, clientIp });
  } catch (error) {
    if (error instanceof InventoryLedgerMutationError) {
      return { error: `Could not commit this import: ${error.message}` };
    }
    throw error;
  }

  revalidatePath(`/${tenantSlug}/operations/imports/inventory-opening-balance`);
  return OK;
}
