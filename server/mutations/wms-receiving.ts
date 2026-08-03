/**
 * WMS Receiving mutation primitives (ATW-013, CG-S10-ATW-013). Thin, typed wrappers
 * around app.start_wms_receipt_session/app.record_wms_receipt_line_count/
 * app.approve_wms_receipt_overage/app.commit_wms_receipt_line/
 * app.complete_wms_receipt_session/app.cancel_wms_receipt_session/
 * app.resolve_wms_receipt_hold
 * (supabase/migrations/20260730200000_create_advanced_tms_wms_receiving.sql).
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import {
  StartWmsReceiptSessionInputSchema,
  RecordWmsReceiptLineCountInputSchema,
  ApproveWmsReceiptOverageInputSchema,
  CommitWmsReceiptLineInputSchema,
  CompleteWmsReceiptSessionInputSchema,
  CancelWmsReceiptSessionInputSchema,
  ResolveWmsReceiptHoldInputSchema,
  parseWmsReceiptSession,
  parseWmsReceiptLine,
  type StartWmsReceiptSessionInput,
  type RecordWmsReceiptLineCountInput,
  type ApproveWmsReceiptOverageInput,
  type CommitWmsReceiptLineInput,
  type CompleteWmsReceiptSessionInput,
  type CancelWmsReceiptSessionInput,
  type ResolveWmsReceiptHoldInput,
  type WmsReceiptSession,
  type WmsReceiptLine,
} from "../contracts/wms-receiving/wms-receiving.ts";

export type WmsReceivingMutationRpcClient = Pick<SupabaseClient, "rpc">;

export const WMS_RECEIVING_KNOWN_MUTATION_ERROR_CODES = [
  "insufficient_authority",
  "inbound_order_not_found",
  "inbound_not_confirmed",
  "location_not_found",
  "incompatible_location",
  "invalid_idempotency_key",
  "session_not_found",
  "session_not_in_progress",
  "line_not_found",
  "invalid_quantity",
  "invalid_equation",
  "invalid_uom",
  "missing_lot",
  "missing_serial",
  "missing_expiry",
  "serial_quantity_exceeded",
  "stale_version",
  "line_already_committed",
  "line_not_counted",
  "line_not_committed",
  "unapproved_overage",
  "no_overage_to_approve",
  "invalid_reason",
  "no_held_quantity",
  "invalid_resolution",
  "lines_not_committed",
  "has_committed_lines",
  "has_receipt_progress",
  "insufficient_stock",
  "item_not_eligible",
  "location_not_eligible",
  "serial_conflict",
] as const;
type KnownWmsReceivingMutationErrorCode = (typeof WMS_RECEIVING_KNOWN_MUTATION_ERROR_CODES)[number];
export type WmsReceivingMutationErrorCode = KnownWmsReceivingMutationErrorCode | "mutation_failed" | "invalid_response";

export class WmsReceivingMutationError extends Error {
  readonly code: WmsReceivingMutationErrorCode;

  constructor(code: WmsReceivingMutationErrorCode, message: string) {
    super(message);
    this.name = "WmsReceivingMutationError";
    this.code = code;
  }
}

function classifyError(message: string): WmsReceivingMutationErrorCode {
  const prefix = message.split(":")[0]?.trim();
  return (WMS_RECEIVING_KNOWN_MUTATION_ERROR_CODES as readonly string[]).includes(prefix ?? "")
    ? (prefix as KnownWmsReceivingMutationErrorCode)
    : "mutation_failed";
}

function firstRow(data: unknown): Record<string, unknown> | null {
  const row = Array.isArray(data) ? data[0] : data;
  return row && typeof row === "object" ? (row as Record<string, unknown>) : null;
}

function parseSessionResponse(data: unknown, rpcName: string): WmsReceiptSession {
  const row = firstRow(data);
  if (!row) {
    throw new WmsReceivingMutationError("invalid_response", `${rpcName} returned no row`);
  }
  return parseWmsReceiptSession(row);
}

function parseLineResponse(data: unknown, rpcName: string): WmsReceiptLine {
  const row = firstRow(data);
  if (!row) {
    throw new WmsReceivingMutationError("invalid_response", `${rpcName} returned no row`);
  }
  return parseWmsReceiptLine(row);
}

/** Idempotent on (tenant_id, idempotency_key) AND on (tenant_id, inbound_order_id) among non-cancelled sessions. Requires a confirmed inbound order and an active dock/staging receiving location of the same warehouse. */
export async function startWmsReceiptSession(client: WmsReceivingMutationRpcClient, input: StartWmsReceiptSessionInput): Promise<WmsReceiptSession> {
  const parsedInput = StartWmsReceiptSessionInputSchema.parse(input);
  const { data, error } = await client.rpc("start_wms_receipt_session", {
    p_inbound_order_id: parsedInput.inboundOrderId,
    p_receiving_location_id: parsedInput.receivingLocationId,
    p_idempotency_key: parsedInput.idempotencyKey,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new WmsReceivingMutationError(classifyError(error.message), error.message);
  }
  return parseSessionResponse(data, "start_wms_receipt_session");
}

/** Pure administrative recording -- posts no ledger movement. Overwrite, not accumulate, semantics. Converts every quantity into the line's own immutable expected UOM. Resets any prior overage approval. */
export async function recordWmsReceiptLineCount(client: WmsReceivingMutationRpcClient, input: RecordWmsReceiptLineCountInput): Promise<WmsReceiptLine> {
  const parsedInput = RecordWmsReceiptLineCountInputSchema.parse(input);
  const { data, error } = await client.rpc("record_wms_receipt_line_count", {
    p_line_id: parsedInput.lineId,
    p_uom_code: parsedInput.uomCode,
    p_counted_quantity: parsedInput.countedQuantity,
    p_accepted_quantity: parsedInput.acceptedQuantity,
    p_damaged_quantity: parsedInput.damagedQuantity,
    p_held_quantity: parsedInput.heldQuantity,
    p_rejected_quantity: parsedInput.rejectedQuantity,
    p_lot_number: parsedInput.lotNumber,
    p_serial_number: parsedInput.serialNumber,
    p_expiry_date: parsedInput.expiryDate,
    p_condition_notes: parsedInput.conditionNotes,
    p_expected_version: parsedInput.expectedVersion,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new WmsReceivingMutationError(classifyError(error.message), error.message);
  }
  return parseLineResponse(data, "record_wms_receipt_line_count");
}

/** OPS:Override supervisor authority -- the one path that lets a line with over_quantity > 0 be committed. */
export async function approveWmsReceiptOverage(client: WmsReceivingMutationRpcClient, input: ApproveWmsReceiptOverageInput): Promise<WmsReceiptLine> {
  const parsedInput = ApproveWmsReceiptOverageInputSchema.parse(input);
  const { data, error } = await client.rpc("approve_wms_receipt_overage", {
    p_line_id: parsedInput.lineId,
    p_reason: parsedInput.reason,
    p_expected_version: parsedInput.expectedVersion,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new WmsReceivingMutationError(classifyError(error.message), error.message);
  }
  return parseLineResponse(data, "approve_wms_receipt_overage");
}

/** Idempotent by short-circuiting on status=committed. The one path that calls app.post_inventory_movement for this line. Blocked by unapproved_overage until app.approve_wms_receipt_overage has run. */
export async function commitWmsReceiptLine(client: WmsReceivingMutationRpcClient, input: CommitWmsReceiptLineInput): Promise<WmsReceiptLine> {
  const parsedInput = CommitWmsReceiptLineInputSchema.parse(input);
  const { data, error } = await client.rpc("commit_wms_receipt_line", {
    p_line_id: parsedInput.lineId,
    p_idempotency_key: parsedInput.idempotencyKey,
    p_expected_version: parsedInput.expectedVersion,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new WmsReceivingMutationError(classifyError(error.message), error.message);
  }
  return parseLineResponse(data, "commit_wms_receipt_line");
}

/** Idempotent no-op on an already-completed session. Requires every line on the session to be committed first. */
export async function completeWmsReceiptSession(client: WmsReceivingMutationRpcClient, input: CompleteWmsReceiptSessionInput): Promise<WmsReceiptSession> {
  const parsedInput = CompleteWmsReceiptSessionInputSchema.parse(input);
  const { data, error } = await client.rpc("complete_wms_receipt_session", {
    p_session_id: parsedInput.sessionId,
    p_expected_version: parsedInput.expectedVersion,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new WmsReceivingMutationError(classifyError(error.message), error.message);
  }
  return parseSessionResponse(data, "complete_wms_receipt_session");
}

/** in_progress only, and only while zero lines have committed -- once real inventory has posted, the session can only move forward to completed. */
export async function cancelWmsReceiptSession(client: WmsReceivingMutationRpcClient, input: CancelWmsReceiptSessionInput): Promise<WmsReceiptSession> {
  const parsedInput = CancelWmsReceiptSessionInputSchema.parse(input);
  const { data, error } = await client.rpc("cancel_wms_receipt_session", {
    p_session_id: parsedInput.sessionId,
    p_reason: parsedInput.reason,
    p_expected_version: parsedInput.expectedVersion,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new WmsReceivingMutationError(classifyError(error.message), error.message);
  }
  return parseSessionResponse(data, "cancel_wms_receipt_session");
}

/** OPS:Override supervisor authority. Idempotent by short-circuiting on hold_resolved. Posts a real two-line adjustment movement (held -> on_hand or held -> damaged, same location), never a bare balance edit. */
export async function resolveWmsReceiptHold(client: WmsReceivingMutationRpcClient, input: ResolveWmsReceiptHoldInput): Promise<WmsReceiptLine> {
  const parsedInput = ResolveWmsReceiptHoldInputSchema.parse(input);
  const { data, error } = await client.rpc("resolve_wms_receipt_hold", {
    p_line_id: parsedInput.lineId,
    p_resolution: parsedInput.resolution,
    p_reason: parsedInput.reason,
    p_idempotency_key: parsedInput.idempotencyKey,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new WmsReceivingMutationError(classifyError(error.message), error.message);
  }
  return parseLineResponse(data, "resolve_wms_receipt_hold");
}
