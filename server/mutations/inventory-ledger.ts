/**
 * Inventory Ledger mutation primitives (ATW-015, CG-S10-ATW-015). Thin, typed
 * wrappers around app.post_inventory_movement/app.reserve_inventory/
 * app.release_inventory_reservation/app.consume_inventory_reservation/
 * app.reverse_inventory_movement
 * (supabase/migrations/20260730190000_create_advanced_tms_inventory_ledger.sql).
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import {
  PostInventoryMovementInputSchema,
  ReserveInventoryInputSchema,
  ReleaseInventoryReservationInputSchema,
  ConsumeInventoryReservationInputSchema,
  ReverseInventoryMovementInputSchema,
  parseInventoryMovement,
  parseInventoryReservation,
  type PostInventoryMovementInput,
  type ReserveInventoryInput,
  type ReleaseInventoryReservationInput,
  type ConsumeInventoryReservationInput,
  type ReverseInventoryMovementInput,
  type InventoryMovement,
  type InventoryReservation,
} from "../contracts/inventory-ledger/inventory-ledger.ts";
import {
  ValidateStagingRowInputSchema,
  CommitInventoryOpeningBalanceImportJobInputSchema,
  parseImportStagingRow,
  parseImportExportJob,
  type ValidateStagingRowInput,
  type CommitInventoryOpeningBalanceImportJobInput,
  type ImportStagingRow,
  type ImportExportJob,
} from "../contracts/import-export/import-export.ts";

export type InventoryLedgerMutationRpcClient = Pick<SupabaseClient, "rpc">;

export const INVENTORY_LEDGER_KNOWN_MUTATION_ERROR_CODES = [
  "insufficient_authority",
  "warehouse_not_found",
  "invalid_movement_type",
  "invalid_reason",
  "invalid_correction",
  "invalid_idempotency_key",
  "invalid_lines",
  "invalid_quantity",
  "invalid_status",
  "invalid_uom",
  "item_not_eligible",
  "location_not_eligible",
  "insufficient_stock",
  // ATW-032: app.inventory_balances carries a non-deferrable (reserved + held) <= on_hand
  // CHECK that post_inventory_movement never tested, so a cycle-count variance approved
  // against pre-freeze reserved stock died on a raw 23514 no caller classified.
  "insufficient_unreserved_stock",
  "serial_conflict",
  "unbalanced_transfer",
  "balance_not_found",
  "insufficient_available_stock",
  "reservation_not_found",
  "invalid_transition",
  "movement_not_found",
  "invalid_reversal",
  "already_reversed",
  // CG-AUDIT-2026-09-02 A4 (inventory_opening_balance_import UI slice, twelfth and
  // final import schema): app.commit_inventory_opening_balance_import_job's latest
  // redefinition (20260903122000_harden_tenant_id_disclosure_hris_payroll_import_commit.sql)
  // composes app.check_import_export_job_authority (job_actor_unauthorized),
  // app.assert_current_step_up_authorization, and app.assert_ip_allowed -- the same
  // authority stack commit_payroll_loan_cutover_import_job composes, plus the generic
  // import_export_* prefixes app.commit_import_job/app.validate_staging_row raise.
  "import_export_job_not_found",
  "import_export_wrong_schema",
  "import_export_job_not_committable",
  "import_export_job_not_fully_validated",
  "import_export_job_has_invalid_rows",
  "job_actor_unauthorized",
  "mfa_step_up_required",
  "ip_not_allowed",
  "import_row_no_longer_resolvable",
] as const;
type KnownInventoryLedgerMutationErrorCode = (typeof INVENTORY_LEDGER_KNOWN_MUTATION_ERROR_CODES)[number];
export type InventoryLedgerMutationErrorCode = KnownInventoryLedgerMutationErrorCode | "mutation_failed" | "invalid_response";

export class InventoryLedgerMutationError extends Error {
  readonly code: InventoryLedgerMutationErrorCode;

  constructor(code: InventoryLedgerMutationErrorCode, message: string) {
    super(message);
    this.name = "InventoryLedgerMutationError";
    this.code = code;
  }
}

function classifyError(message: string): InventoryLedgerMutationErrorCode {
  const prefix = message.split(":")[0]?.trim();
  return (INVENTORY_LEDGER_KNOWN_MUTATION_ERROR_CODES as readonly string[]).includes(prefix ?? "")
    ? (prefix as KnownInventoryLedgerMutationErrorCode)
    : "mutation_failed";
}

function firstRow(data: unknown): Record<string, unknown> | null {
  const row = Array.isArray(data) ? data[0] : data;
  return row && typeof row === "object" ? (row as Record<string, unknown>) : null;
}

function parseMovementResponse(data: unknown, rpcName: string): InventoryMovement {
  const row = firstRow(data);
  if (!row) {
    throw new InventoryLedgerMutationError("invalid_response", `${rpcName} returned no row`);
  }
  return parseInventoryMovement(row);
}

function parseReservationResponse(data: unknown, rpcName: string): InventoryReservation {
  const row = firstRow(data);
  if (!row) {
    throw new InventoryLedgerMutationError("invalid_response", `${rpcName} returned no row`);
  }
  return parseInventoryReservation(row);
}

/**
 * The one generic posting primitive every WMS capability composes (design note 4) --
 * never insert into app.inventory_movements/app.inventory_balances directly.
 * Idempotent on (tenant_id, idempotencyKey); a transfer's own lines must sum to
 * exactly zero; a resulting negative on_hand or a serial exceeding 1 both fail the
 * whole call.
 */
export async function postInventoryMovement(client: InventoryLedgerMutationRpcClient, input: PostInventoryMovementInput): Promise<InventoryMovement> {
  const parsedInput = PostInventoryMovementInputSchema.parse(input);
  const { data, error } = await client.rpc("post_inventory_movement", {
    p_tenant_id: parsedInput.tenantId,
    p_warehouse_id: parsedInput.warehouseId,
    p_movement_type: parsedInput.movementType,
    p_source_type: parsedInput.sourceType,
    p_source_id: parsedInput.sourceId ?? null,
    p_idempotency_key: parsedInput.idempotencyKey,
    p_reason: parsedInput.reason ?? null,
    p_lines: parsedInput.lines.map((line) => ({
      owner_account_id: line.ownerAccountId,
      item_master_id: line.itemMasterId,
      location_id: line.locationId,
      uom_code: line.uomCode,
      signed_quantity: line.signedQuantity,
      lot_number: line.lotNumber ?? null,
      serial_number: line.serialNumber ?? null,
      expiry_date: line.expiryDate ?? null,
      status: line.status ?? null,
    })),
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
    p_corrects_movement_id: parsedInput.correctsMovementId ?? null,
  });
  if (error) {
    throw new InventoryLedgerMutationError(classifyError(error.message), error.message);
  }
  return parseMovementResponse(data, "post_inventory_movement");
}

/** Locks the target balance row before checking availability. Idempotent on (tenant_id, idempotencyKey). */
export async function reserveInventory(client: InventoryLedgerMutationRpcClient, input: ReserveInventoryInput): Promise<InventoryReservation> {
  const parsedInput = ReserveInventoryInputSchema.parse(input);
  const { data, error } = await client.rpc("reserve_inventory", {
    p_tenant_id: parsedInput.tenantId,
    p_warehouse_id: parsedInput.warehouseId,
    p_owner_account_id: parsedInput.ownerAccountId,
    p_item_master_id: parsedInput.itemMasterId,
    p_location_id: parsedInput.locationId,
    p_lot_number: parsedInput.lotNumber ?? null,
    p_serial_number: parsedInput.serialNumber ?? null,
    p_quantity: parsedInput.quantity,
    p_source_type: parsedInput.sourceType,
    p_source_id: parsedInput.sourceId ?? null,
    p_idempotency_key: parsedInput.idempotencyKey,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new InventoryLedgerMutationError(classifyError(error.message), error.message);
  }
  return parseReservationResponse(data, "reserve_inventory");
}

/** active -> released only; frees the reserved quantity back onto the balance. */
export async function releaseInventoryReservation(client: InventoryLedgerMutationRpcClient, input: ReleaseInventoryReservationInput): Promise<InventoryReservation> {
  const parsedInput = ReleaseInventoryReservationInputSchema.parse(input);
  const { data, error } = await client.rpc("release_inventory_reservation", {
    p_reservation_id: parsedInput.reservationId,
    p_reason: parsedInput.reason ?? null,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new InventoryLedgerMutationError(classifyError(error.message), error.message);
  }
  return parseReservationResponse(data, "release_inventory_reservation");
}

/**
 * active -> consumed; posts a real negative app.post_inventory_movement atomically
 * with the reservation status transition. A same-reservation retry after the first
 * success is a direct no-op (status already consumed).
 */
export async function consumeInventoryReservation(client: InventoryLedgerMutationRpcClient, input: ConsumeInventoryReservationInput): Promise<InventoryReservation> {
  const parsedInput = ConsumeInventoryReservationInputSchema.parse(input);
  const { data, error } = await client.rpc("consume_inventory_reservation", {
    p_reservation_id: parsedInput.reservationId,
    p_idempotency_key: parsedInput.idempotencyKey,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new InventoryLedgerMutationError(classifyError(error.message), error.message);
  }
  return parseReservationResponse(data, "consume_inventory_reservation");
}

/**
 * A governed correction, never a delete or in-place edit -- posts a new movement
 * with exactly negated lines. Rejects reversing an already-reversed movement or a
 * reversal itself.
 */
export async function reverseInventoryMovement(client: InventoryLedgerMutationRpcClient, input: ReverseInventoryMovementInput): Promise<InventoryMovement> {
  const parsedInput = ReverseInventoryMovementInputSchema.parse(input);
  const { data, error } = await client.rpc("reverse_inventory_movement", {
    p_movement_id: parsedInput.movementId,
    p_idempotency_key: parsedInput.idempotencyKey,
    p_reason: parsedInput.reason,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new InventoryLedgerMutationError(classifyError(error.message), error.message);
  }
  return parseMovementResponse(data, "reverse_inventory_movement");
}

// --- Staged import (CG-AUDIT-2026-09-02 A4, twelfth and final import schema) ---
// app.validate_inventory_opening_balance_import_row returns app.import_staging_rows
// and app.commit_inventory_opening_balance_import_job returns app.jobs -- the SAME
// composite types the generic PLT-131 app.validate_staging_row/app.commit_import_job
// return, so both reuse the generic parsers directly, mirroring
// server/mutations/payroll.ts's own precedent.

/** Calls app.validate_staging_row UNCHANGED first, then adds formula/spreadsheet-injection rejection (warehouse_code, location_code, item_code, owner_account_tax_id, uom_code, lot_number, serial_number, status), warehouse_code/location_code/owner_account_tax_id/item_code/uom_code must each resolve within this tenant, quantity must be a strictly positive numeric ("on the shelf at cutover" -- never zero or negative), status must be one of on_hand/held/damaged/expired, and expiry_date if present must be a real date. */
export async function validateInventoryOpeningBalanceImportRow(client: InventoryLedgerMutationRpcClient, input: ValidateStagingRowInput): Promise<ImportStagingRow> {
  const parsed = ValidateStagingRowInputSchema.parse(input);
  const { data, error } = await client.rpc("validate_inventory_opening_balance_import_row", {
    p_staging_row_id: parsed.stagingRowId,
    p_actor_auth_user_id: parsed.actorAuthUserId,
    p_actor_label: parsed.actorLabel,
  });
  if (error) {
    throw new InventoryLedgerMutationError(classifyError(error.message), error.message);
  }
  if (!data || typeof data !== "object") {
    throw new InventoryLedgerMutationError("invalid_response", "validate_inventory_opening_balance_import_row returned no row");
  }
  return parseImportStagingRow(data as Record<string, unknown>);
}

/** Requires BOTH app.is_support_grant_authority (Supreme Admin or tenant_admin) AND OPS:Import (additive, never either-or), plus a conditional MFA step-up and a conditional IP allowlist check, identical in shape to commit_payroll_loan_cutover_import_job. The importer ALSO needs genuine record scope over each row's own warehouse -- app.post_inventory_movement checks app.can_access_record against the warehouse's company org unit, invisible in this RPC's own guard list since it lives inside the primitive itself. Calls app.post_inventory_movement per valid row with movement_type='opening_balance' -- the SAME primitive every other WMS write composes, never a bespoke insert into app.inventory_movements/app.inventory_balances. An already-committed staging row (idempotency key derived from the staging row's own id) is skipped as a plain idempotent replay, never a duplicate movement; warehouse/owner-account/item/location are re-resolved at commit time, and one that went inactive between validate and commit fails closed with import_row_no_longer_resolvable rather than silently proceeding. This import can never correct a wrong opening balance by re-running: a genuinely new row posts a new, additive movement, never an overwrite -- correcting a mistake requires app.reverse_inventory_movement outside this wizard entirely. */
export async function commitInventoryOpeningBalanceImportJob(client: InventoryLedgerMutationRpcClient, input: CommitInventoryOpeningBalanceImportJobInput): Promise<ImportExportJob> {
  const parsed = CommitInventoryOpeningBalanceImportJobInputSchema.parse(input);
  const { data, error } = await client.rpc("commit_inventory_opening_balance_import_job", {
    p_job_id: parsed.jobId,
    p_allow_partial: parsed.allowPartial,
    p_actor_auth_user_id: parsed.actorAuthUserId,
    p_actor_label: parsed.actorLabel,
    p_client_ip: parsed.clientIp,
  });
  if (error) {
    throw new InventoryLedgerMutationError(classifyError(error.message), error.message);
  }
  if (!data || typeof data !== "object") {
    throw new InventoryLedgerMutationError("invalid_response", "commit_inventory_opening_balance_import_job returned no row");
  }
  return parseImportExportJob(data as Record<string, unknown>);
}
