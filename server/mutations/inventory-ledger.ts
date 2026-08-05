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
