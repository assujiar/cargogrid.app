/**
 * Item/SKU and UOM Master mutation primitives (ATW-011A, CG-S10-ATW-011A). Thin,
 * typed wrappers around app.create_item_master/app.update_item_master/
 * app.set_item_master_status
 * (supabase/migrations/20260730160000_create_advanced_tms_item_uom_master.sql).
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import {
  CreateItemMasterInputSchema,
  UpdateItemMasterInputSchema,
  SetItemMasterStatusInputSchema,
  parseItemMaster,
  type CreateItemMasterInput,
  type UpdateItemMasterInput,
  type SetItemMasterStatusInput,
  type ItemMaster,
} from "../contracts/item-uom-master/item-uom-master.ts";
import {
  ValidateStagingRowInputSchema,
  CommitItemImportJobInputSchema,
  parseImportStagingRow,
  parseImportExportJob,
  type ValidateStagingRowInput,
  type CommitItemImportJobInput,
  type ImportStagingRow,
  type ImportExportJob,
} from "../contracts/import-export/import-export.ts";

export type ItemUomMasterMutationRpcClient = Pick<SupabaseClient, "rpc">;

export const ITEM_UOM_MASTER_KNOWN_MUTATION_ERROR_CODES = [
  "insufficient_authority",
  "invalid_code",
  "invalid_name",
  "owner_account_not_found",
  "invalid_base_uom",
  "item_master_not_found",
  "stale_version",
  "invalid_status",
  "invalid_reason",
  // --- Staged import (CG-AUDIT-2026-09-02 A4, sixth import schema) ---
  // app.validate_item_import_row/app.commit_item_import_job
  // (supabase/migrations/20260830120000_create_customer_and_item_import_adapters.sql,
  // latest commit redefinition
  // 20260903122000_harden_tenant_id_disclosure_hris_payroll_import_commit.sql)
  // compose the generic PLT-131 framework's own errors plus these
  // domain-specific ones.
  "import_export_job_not_found",
  "import_export_wrong_schema",
  "job_actor_unauthorized",
  "mfa_step_up_required",
  "ip_not_allowed",
  "import_export_job_not_committable",
  "import_export_job_not_fully_validated",
  "import_export_job_has_invalid_rows",
  // Re-resolved at commit time (not carried from validation) since an owner
  // account could have been merged/deactivated between validate and commit --
  // distinct from owner_account_not_found above, which app.create_item_master
  // itself never raises (it takes an already-resolved owner_account_id).
  "import_owner_account_not_found",
  // ISS-2026-277: a resolved duplicate match (create-or-link, not
  // flag-for-review) that lands on an item master under legal hold refuses
  // the whole commit rather than silently linking import content to it.
  "import_blocked_legal_hold",
] as const;
type KnownItemUomMasterMutationErrorCode = (typeof ITEM_UOM_MASTER_KNOWN_MUTATION_ERROR_CODES)[number];
export type ItemUomMasterMutationErrorCode = KnownItemUomMasterMutationErrorCode | "mutation_failed" | "invalid_response";

export class ItemUomMasterMutationError extends Error {
  readonly code: ItemUomMasterMutationErrorCode;

  constructor(code: ItemUomMasterMutationErrorCode, message: string) {
    super(message);
    this.name = "ItemUomMasterMutationError";
    this.code = code;
  }
}

function classifyError(message: string): ItemUomMasterMutationErrorCode {
  const prefix = message.split(":")[0]?.trim();
  return (ITEM_UOM_MASTER_KNOWN_MUTATION_ERROR_CODES as readonly string[]).includes(prefix ?? "")
    ? (prefix as KnownItemUomMasterMutationErrorCode)
    : "mutation_failed";
}

function firstRow(data: unknown): Record<string, unknown> | null {
  const row = Array.isArray(data) ? data[0] : data;
  return row && typeof row === "object" ? (row as Record<string, unknown>) : null;
}

function parseItemMasterResponse(data: unknown, rpcName: string): ItemMaster {
  const row = firstRow(data);
  if (!row) {
    throw new ItemUomMasterMutationError("invalid_response", `${rpcName} returned no row`);
  }
  return parseItemMaster(row);
}

/** Idempotent on (tenant_id, owner_account_id, code) -- a same-code retry under the same owner returns the identical row. The identical code under a different owner_account_id in the same tenant is a distinct, legal row. */
export async function createItemMaster(client: ItemUomMasterMutationRpcClient, input: CreateItemMasterInput): Promise<ItemMaster> {
  const parsedInput = CreateItemMasterInputSchema.parse(input);
  const { data, error } = await client.rpc("create_item_master", {
    p_tenant_id: parsedInput.tenantId,
    p_owner_account_id: parsedInput.ownerAccountId,
    p_code: parsedInput.code,
    p_name: parsedInput.name,
    p_description: parsedInput.description,
    p_base_uom_code: parsedInput.baseUomCode,
    p_lot_controlled: parsedInput.lotControlled,
    p_serial_controlled: parsedInput.serialControlled,
    p_expiry_controlled: parsedInput.expiryControlled,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new ItemUomMasterMutationError(classifyError(error.message), error.message);
  }
  return parseItemMasterResponse(data, "create_item_master");
}

/** Mutable fields only -- code, tenant_id, owner_account_id and base_uom_code are immutable once created. Optimistic-concurrency gated (record_version). */
export async function updateItemMaster(client: ItemUomMasterMutationRpcClient, input: UpdateItemMasterInput): Promise<ItemMaster> {
  const parsedInput = UpdateItemMasterInputSchema.parse(input);
  const { data, error } = await client.rpc("update_item_master", {
    p_item_master_id: parsedInput.itemMasterId,
    p_name: parsedInput.name,
    p_description: parsedInput.description,
    p_lot_controlled: parsedInput.lotControlled,
    p_serial_controlled: parsedInput.serialControlled,
    p_expiry_controlled: parsedInput.expiryControlled,
    p_expected_version: parsedInput.expectedVersion,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new ItemUomMasterMutationError(classifyError(error.message), error.message);
  }
  return parseItemMasterResponse(data, "update_item_master");
}

/** A reason is required to deactivate; a same-status transition is a no-op returning the current row. Does not check for referencing inbound/receiving/ledger/lot rows -- none exist yet at this checkpoint (disclosed, ATW-231 or whichever future capability first references an item_master row is obligated to wire that check). */
export async function setItemMasterStatus(client: ItemUomMasterMutationRpcClient, input: SetItemMasterStatusInput): Promise<ItemMaster> {
  const parsedInput = SetItemMasterStatusInputSchema.parse(input);
  const { data, error } = await client.rpc("set_item_master_status", {
    p_item_master_id: parsedInput.itemMasterId,
    p_new_status: parsedInput.newStatus,
    p_reason: parsedInput.reason,
    p_expected_version: parsedInput.expectedVersion,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new ItemUomMasterMutationError(classifyError(error.message), error.message);
  }
  return parseItemMasterResponse(data, "set_item_master_status");
}

// --- Staged import (CG-AUDIT-2026-09-02 A4, sixth import schema) ---
// app.validate_item_import_row returns app.import_staging_rows and
// app.commit_item_import_job returns app.jobs -- the SAME composite types the
// generic PLT-131 app.validate_staging_row/app.commit_import_job return, so both
// reuse the generic parsers directly, mirroring
// server/mutations/account.ts's own precedent.

/** Calls app.validate_staging_row UNCHANGED first, then adds formula/spreadsheet-injection rejection (code, name, description, base_uom_code, owner_account_tax_id, owner_account_legal_name), non-empty code/name, base_uom_code resolving to a registered active UOM, and owner-account resolution by tax id or legal name against active app.accounts -- zero or more than one match is an error, never a silent pick (a confidentiality concern, never a tidiness one). Refuses a row that supplies status/record_version -- those are platform-controlled, never importable. */
export async function validateItemImportRow(client: ItemUomMasterMutationRpcClient, input: ValidateStagingRowInput): Promise<ImportStagingRow> {
  const parsed = ValidateStagingRowInputSchema.parse(input);
  const { data, error } = await client.rpc("validate_item_import_row", {
    p_staging_row_id: parsed.stagingRowId,
    p_actor_auth_user_id: parsed.actorAuthUserId,
    p_actor_label: parsed.actorLabel,
  });
  if (error) throw new ItemUomMasterMutationError(classifyError(error.message), error.message);
  if (!data || typeof data !== "object") throw new ItemUomMasterMutationError("invalid_response", "validate_item_import_row returned no row");
  return parseImportStagingRow(data as Record<string, unknown>);
}

/** Requires OPS:Import AND is_support_grant_authority (additive, never either-or). Writes only through app.create_item_master (never a direct INSERT), re-resolving the owner account at commit time (never carried from validation, since it could have been merged/deactivated in between -- import_owner_account_not_found if it no longer resolves to exactly one active account). Create-or-link, not flag-for-review: a duplicate (tenant, owner_account, code) match resolves to the existing item master and is counted as linked, never blocked -- unless that item master is under legal hold (import_blocked_legal_hold), which aborts the whole commit. */
export async function commitItemImportJob(client: ItemUomMasterMutationRpcClient, input: CommitItemImportJobInput): Promise<ImportExportJob> {
  const parsed = CommitItemImportJobInputSchema.parse(input);
  const { data, error } = await client.rpc("commit_item_import_job", {
    p_job_id: parsed.jobId,
    p_allow_partial: parsed.allowPartial,
    p_actor_auth_user_id: parsed.actorAuthUserId,
    p_actor_label: parsed.actorLabel,
    p_client_ip: parsed.clientIp,
  });
  if (error) throw new ItemUomMasterMutationError(classifyError(error.message), error.message);
  if (!data || typeof data !== "object") throw new ItemUomMasterMutationError("invalid_response", "commit_item_import_job returned no row");
  return parseImportExportJob(data as Record<string, unknown>);
}
