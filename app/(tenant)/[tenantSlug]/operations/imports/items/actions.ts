"use server";

/**
 * Item master import Server Actions (CG-AUDIT-2026-09-02 A4, sixth import schema
 * after finance_opening_balance_import, employee_import, vendor_import,
 * vendor_rate_import, and customer_import). Every RPC this file calls already
 * existed, fully implemented and tested
 * (app.create_import_export_job/app.stage_import_rows/app.validate_item_import_row/
 * app.commit_item_import_job, plus PLT-121's generic config-draft primitives for
 * the one-time per-tenant bootstrap) -- this file is a near-mechanical port of
 * commercial/imports/customers/actions.ts's own trio, swapping the account
 * validate/commit adapters for their item/UOM master equivalents.
 *
 * Unlike every prior schema in this backlog, item_import needs NO new migration
 * at all: both the import_export:item_import SCHEMA and the
 * master_data_import_source DOCUMENT TYPE (shared with customer_import) were
 * already registered as real global catalog rows before this slice --
 * 20260830120000_create_customer_and_item_import_adapters.sql registers
 * customer_import and item_import's own schema kinds together in one statement,
 * and 20260917040000_register_master_data_import_source_document_type.sql (this
 * session's own customer_import slice) already registered the shared document
 * type, additive and idempotent, specifically anticipating this slice.
 *
 * server/mutations/item-uom-master.ts had ZERO wrapper for
 * validate_item_import_row/commit_item_import_job at all (a from-scratch build,
 * like vendor_import's/customer_import's own slices) -- both new functions reuse
 * the generic PLT-131 parsers directly.
 *
 * app.commit_item_import_job's own authority composition matches
 * vendor_import's/customer_import's: BOTH app.is_support_grant_authority AND
 * OPS:Import, additive, never either alone -- this action's own gate
 * (resolveOperationsAccessForRequest) is coarser and deliberately does not stand
 * in for either check. Commit is create-or-link, not flag-for-review, exactly
 * like customer_import: a duplicate (owner_account, code) match resolves to the
 * existing item master and is counted as linked, never blocked -- unless that
 * item master is under legal hold (import_blocked_legal_hold), which aborts the
 * whole commit.
 *
 * No page in this codebase manages item/SKU master data yet (confirmed by
 * repo-wide search before writing this file) -- this page is therefore
 * standalone and unlinked, mirroring finance/config/page.tsx's own precedent,
 * rather than invented navigation for a host page that does not exist.
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
import { validateItemImportRow, commitItemImportJob, ItemUomMasterMutationError, type ItemUomMasterMutationRpcClient } from "../../../../../../server/mutations/item-uom-master.ts";
import type { BackgroundJobMutationRpcClient } from "../../../../../../server/mutations/background-job.ts";

const SCHEMA_CODE = "item_import";
const DOCUMENT_TYPE_CODE = "master_data_import_source";

const ITEM_IMPORT_COLUMNS = [
  { key: "code", label: "Item code", required: true, data_type: "text" },
  { key: "name", label: "Item name", required: true, data_type: "text" },
  { key: "description", label: "Description", required: false, data_type: "text" },
  { key: "base_uom_code", label: "Base UOM", required: true, data_type: "text" },
  { key: "owner_account_tax_id", label: "Owner account tax id", required: false, data_type: "text" },
  { key: "owner_account_legal_name", label: "Owner account legal name", required: false, data_type: "text" },
  { key: "lot_controlled", label: "Lot controlled", required: false, data_type: "boolean" },
  { key: "serial_controlled", label: "Serial controlled", required: false, data_type: "boolean" },
  { key: "expiry_controlled", label: "Expiry controlled", required: false, data_type: "boolean" },
] as const;

export interface ItemImportActionState {
  readonly error: string | null;
}

const OK: ItemImportActionState = { error: null };
const NO_ACCESS: ItemImportActionState = { error: "You don't have access to this organization's Operations workspace." };

type UnifiedClient = ConfigMutationRpcClient & DocumentMutationRpcClient & ImportExportMutationRpcClient & ImportExportQueryRpcClient & ItemUomMasterMutationRpcClient & StorageUploadClient;

function toUnifiedClient(client: ReturnType<typeof createSupabaseServiceRoleClient>): UnifiedClient {
  return client as unknown as UnifiedClient;
}

function toBackgroundJobClient(client: Awaited<ReturnType<typeof createSupabaseServerClient>>): BackgroundJobMutationRpcClient {
  return client as unknown as BackgroundJobMutationRpcClient;
}

/** One-time per-tenant setup: publishes both the document-type definition (file-upload rules) and the import schema's column definition -- everything a tenant needs before its first item-master upload. Idempotent: createConfigDraft returns any already-pending draft rather than a new one, so re-running this after a partial failure safely resumes. */
export async function bootstrapItemImportAction(tenantSlug: string, _prevState: ItemImportActionState, _formData: FormData): Promise<ItemImportActionState> {
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
      items: [{ key: "columns", value: [...ITEM_IMPORT_COLUMNS], canonicalRef: null }],
      actorAuthUserId: access.authUserId,
      actorLabel: access.authUserId,
    });
    await publishImportExportSchema(client, { versionId: schemaDraft.id, actorAuthUserId: access.authUserId, effectiveFrom: new Date().toISOString(), actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof ConfigMutationError || error instanceof DocumentMutationError || error instanceof ImportExportMutationError) {
      return { error: `Could not set up item imports: ${error.message}` };
    }
    throw error;
  }

  revalidatePath(`/${tenantSlug}/operations/imports/items`);
  return OK;
}

/** Uploads a real CSV source file (PLT-128, malware-scanned like every other real evidence upload this session's own A6 work established) and immediately opens a new import job against it -- job creation does not itself require the file to be clean yet (only staging does). The job's own payload carries the file's storage path forward, since app.import_staging_rows/app.files are not directly browsable and this is the one place that path is ever known. */
export async function uploadItemImportSourceAction(tenantSlug: string, _prevState: ItemImportActionState, formData: FormData): Promise<ItemImportActionState> {
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

    const storeError = await storeFileBytesAndEnqueueScan(client, toBackgroundJobClient(supabase), uploaded, file, access.tenant.id, access.authUserId, "item master source file");
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

  redirect(`/${tenantSlug}/operations/imports/items?job=${createdJobId}`);
}

/** Downloads the job's own already-uploaded, already-scanned source file back from Storage (never re-accepts a fresh file at this step -- the staged rows must come from the SAME bytes that were scanned), parses it, and stages+validates every row in one action. Resumable: skips staging (never re-stages, which would duplicate every row) once the job already has staged rows, and only validates rows still pending. */
export async function stageAndValidateItemImportRowsAction(tenantSlug: string, jobId: string, _prevState: ItemImportActionState, _formData: FormData): Promise<ItemImportActionState> {
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
        await validateItemImportRow(client, { stagingRowId: row.id, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
      }
    }
  } catch (error) {
    if (error instanceof ImportExportMutationError || error instanceof ImportExportQueryError || error instanceof ItemUomMasterMutationError) {
      return { error: `Could not process this file: ${error.message}` };
    }
    throw error;
  }

  revalidatePath(`/${tenantSlug}/operations/imports/items`);
  return OK;
}

/** Requires BOTH tenant_admin/Supreme authority AND OPS:Import, in-body -- this action's own gate (resolveOperationsAccessForRequest) is coarser and deliberately does not stand in for either check. Passes the caller's own client IP so the tenant's IP allowlist (if configured) is genuinely enforced. Create-or-link: a row whose (owner account, code) matches an existing item master links to it rather than duplicating -- unless that item master is under legal hold, which aborts the whole commit. */
export async function commitItemImportAction(tenantSlug: string, jobId: string, _prevState: ItemImportActionState, formData: FormData): Promise<ItemImportActionState> {
  const access = await resolveOperationsAccessForRequest(tenantSlug);
  if (access.status !== "allowed") return NO_ACCESS;

  const allowPartial = formData.get("allowPartial") === "on";
  const clientIp = await resolveRequestClientIp();

  const client = toUnifiedClient(createSupabaseServiceRoleClient());
  try {
    await commitItemImportJob(client, { jobId, allowPartial, actorAuthUserId: access.authUserId, actorLabel: access.authUserId, clientIp });
  } catch (error) {
    if (error instanceof ItemUomMasterMutationError) {
      return { error: `Could not commit this import: ${error.message}` };
    }
    throw error;
  }

  revalidatePath(`/${tenantSlug}/operations/imports/items`);
  return OK;
}
