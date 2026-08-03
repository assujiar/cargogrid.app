/**
 * WMS Outbound Order mutation primitives (ATW-016A, CG-S10-ATW-016A). Thin, typed
 * wrappers around app.prepare_wms_outbound_from_shipment/app.create_manual_wms_
 * outbound_order/app.add_wms_outbound_order_line(s)/app.update_wms_outbound_order_
 * line/app.remove_wms_outbound_order_line/app.confirm_wms_outbound_order/app.
 * cancel_wms_outbound_order
 * (supabase/migrations/20260730230000_create_advanced_tms_wms_outbound_order.sql).
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import {
  PrepareWmsOutboundFromShipmentInputSchema,
  CreateManualWmsOutboundOrderInputSchema,
  AddWmsOutboundOrderLineInputSchema,
  AddWmsOutboundOrderLinesInputSchema,
  UpdateWmsOutboundOrderLineInputSchema,
  RemoveWmsOutboundOrderLineInputSchema,
  ConfirmWmsOutboundOrderInputSchema,
  CancelWmsOutboundOrderInputSchema,
  parseWmsOutboundOrder,
  parseWmsOutboundOrderLine,
  type PrepareWmsOutboundFromShipmentInput,
  type CreateManualWmsOutboundOrderInput,
  type AddWmsOutboundOrderLineInput,
  type AddWmsOutboundOrderLinesInput,
  type UpdateWmsOutboundOrderLineInput,
  type RemoveWmsOutboundOrderLineInput,
  type ConfirmWmsOutboundOrderInput,
  type CancelWmsOutboundOrderInput,
  type WmsOutboundOrder,
  type WmsOutboundOrderLine,
} from "../contracts/wms-outbound-order/wms-outbound-order.ts";

export type WmsOutboundOrderMutationRpcClient = Pick<SupabaseClient, "rpc">;

export const WMS_OUTBOUND_ORDER_KNOWN_MUTATION_ERROR_CODES = [
  "insufficient_authority",
  "shipment_order_not_found",
  "source_not_confirmed",
  "warehouse_not_found",
  "warehouse_not_active",
  "owner_account_not_found",
  "invalid_reason",
  "invalid_idempotency_key",
  "outbound_order_not_found",
  "outbound_not_draft",
  "item_not_eligible",
  "invalid_uom",
  "invalid_quantity",
  "invalid_lines",
  "too_many_lines",
  "line_not_found",
  "stale_version",
  "invalid_transition",
  "outbound_not_ready",
] as const;
type KnownWmsOutboundOrderMutationErrorCode = (typeof WMS_OUTBOUND_ORDER_KNOWN_MUTATION_ERROR_CODES)[number];
export type WmsOutboundOrderMutationErrorCode = KnownWmsOutboundOrderMutationErrorCode | "mutation_failed" | "invalid_response";

export class WmsOutboundOrderMutationError extends Error {
  readonly code: WmsOutboundOrderMutationErrorCode;

  constructor(code: WmsOutboundOrderMutationErrorCode, message: string) {
    super(message);
    this.name = "WmsOutboundOrderMutationError";
    this.code = code;
  }
}

function classifyError(message: string): WmsOutboundOrderMutationErrorCode {
  const prefix = message.split(":")[0]?.trim();
  return (WMS_OUTBOUND_ORDER_KNOWN_MUTATION_ERROR_CODES as readonly string[]).includes(prefix ?? "")
    ? (prefix as KnownWmsOutboundOrderMutationErrorCode)
    : "mutation_failed";
}

function firstRow(data: unknown): Record<string, unknown> | null {
  const row = Array.isArray(data) ? data[0] : data;
  return row && typeof row === "object" ? (row as Record<string, unknown>) : null;
}

function parseOrderResponse(data: unknown, rpcName: string): WmsOutboundOrder {
  const row = firstRow(data);
  if (!row) {
    throw new WmsOutboundOrderMutationError("invalid_response", `${rpcName} returned no row`);
  }
  return parseWmsOutboundOrder(row);
}

function parseLineResponse(data: unknown, rpcName: string): WmsOutboundOrderLine {
  const row = firstRow(data);
  if (!row) {
    throw new WmsOutboundOrderMutationError("invalid_response", `${rpcName} returned no row`);
  }
  return parseWmsOutboundOrderLine(row);
}

/** Idempotent on (tenant_id, source_shipment_order_id) among non-cancelled rows. owner_account_id is inherited from the shipment order's own shipper_account_id. Requires the source shipment order's own status = confirmed. */
export async function prepareWmsOutboundFromShipment(client: WmsOutboundOrderMutationRpcClient, input: PrepareWmsOutboundFromShipmentInput): Promise<WmsOutboundOrder> {
  const parsedInput = PrepareWmsOutboundFromShipmentInputSchema.parse(input);
  const { data, error } = await client.rpc("prepare_wms_outbound_from_shipment", {
    p_tenant_id: parsedInput.tenantId,
    p_shipment_order_id: parsedInput.shipmentOrderId,
    p_warehouse_id: parsedInput.warehouseId,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new WmsOutboundOrderMutationError(classifyError(error.message), error.message);
  }
  return parseOrderResponse(data, "prepare_wms_outbound_from_shipment");
}

/** The governed manual-entry exception path -- requires a non-empty sourceReason. Idempotent on (tenant_id, idempotencyKey) among non-cancelled rows. */
export async function createManualWmsOutboundOrder(client: WmsOutboundOrderMutationRpcClient, input: CreateManualWmsOutboundOrderInput): Promise<WmsOutboundOrder> {
  const parsedInput = CreateManualWmsOutboundOrderInputSchema.parse(input);
  const { data, error } = await client.rpc("create_manual_wms_outbound_order", {
    p_tenant_id: parsedInput.tenantId,
    p_warehouse_id: parsedInput.warehouseId,
    p_owner_account_id: parsedInput.ownerAccountId,
    p_source_reason: parsedInput.sourceReason,
    p_idempotency_key: parsedInput.idempotencyKey,
    p_requested_ship_date: parsedInput.requestedShipDate ?? null,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new WmsOutboundOrderMutationError(classifyError(error.message), error.message);
  }
  return parseOrderResponse(data, "create_manual_wms_outbound_order");
}

/** Only while the header is draft. Rejects an item not owned by the same account as the outbound order. */
export async function addWmsOutboundOrderLine(client: WmsOutboundOrderMutationRpcClient, input: AddWmsOutboundOrderLineInput): Promise<WmsOutboundOrderLine> {
  const parsedInput = AddWmsOutboundOrderLineInputSchema.parse(input);
  const { data, error } = await client.rpc("add_wms_outbound_order_line", {
    p_outbound_order_id: parsedInput.outboundOrderId,
    p_item_master_id: parsedInput.itemMasterId,
    p_requested_uom_code: parsedInput.requestedUomCode,
    p_requested_quantity: parsedInput.requestedQuantity,
    p_notes: parsedInput.notes,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new WmsOutboundOrderMutationError(classifyError(error.message), error.message);
  }
  return parseLineResponse(data, "add_wms_outbound_order_line");
}

/** The bounded bulk-add alt flow -- all-or-nothing, at most 200 lines per call. */
export async function addWmsOutboundOrderLines(client: WmsOutboundOrderMutationRpcClient, input: AddWmsOutboundOrderLinesInput): Promise<WmsOutboundOrderLine[]> {
  const parsedInput = AddWmsOutboundOrderLinesInputSchema.parse(input);
  const { data, error } = await client.rpc("add_wms_outbound_order_lines", {
    p_outbound_order_id: parsedInput.outboundOrderId,
    p_lines: parsedInput.lines.map((line) => ({
      item_master_id: line.itemMasterId,
      requested_uom_code: line.requestedUomCode,
      requested_quantity: line.requestedQuantity,
      notes: line.notes ?? null,
    })),
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new WmsOutboundOrderMutationError(classifyError(error.message), error.message);
  }
  return ((data as Record<string, unknown>[] | null) ?? []).map(parseWmsOutboundOrderLine);
}

/** Mutable fields only. Optimistic-concurrency gated. Only while the header is draft. */
export async function updateWmsOutboundOrderLine(client: WmsOutboundOrderMutationRpcClient, input: UpdateWmsOutboundOrderLineInput): Promise<WmsOutboundOrderLine> {
  const parsedInput = UpdateWmsOutboundOrderLineInputSchema.parse(input);
  const { data, error } = await client.rpc("update_wms_outbound_order_line", {
    p_line_id: parsedInput.lineId,
    p_requested_quantity: parsedInput.requestedQuantity,
    p_notes: parsedInput.notes,
    p_expected_version: parsedInput.expectedVersion,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new WmsOutboundOrderMutationError(classifyError(error.message), error.message);
  }
  return parseLineResponse(data, "update_wms_outbound_order_line");
}

/** Only while the header is draft. Optimistic-concurrency gated. */
export async function removeWmsOutboundOrderLine(client: WmsOutboundOrderMutationRpcClient, input: RemoveWmsOutboundOrderLineInput): Promise<boolean> {
  const parsedInput = RemoveWmsOutboundOrderLineInputSchema.parse(input);
  const { data, error } = await client.rpc("remove_wms_outbound_order_line", {
    p_line_id: parsedInput.lineId,
    p_expected_version: parsedInput.expectedVersion,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new WmsOutboundOrderMutationError(classifyError(error.message), error.message);
  }
  return Boolean(data);
}

/** draft -> confirmed only, re-validates full readiness rather than trusting a stale prior check (including that a shipment-sourced order's own source shipment order is still confirmed). */
export async function confirmWmsOutboundOrder(client: WmsOutboundOrderMutationRpcClient, input: ConfirmWmsOutboundOrderInput): Promise<WmsOutboundOrder> {
  const parsedInput = ConfirmWmsOutboundOrderInputSchema.parse(input);
  const { data, error } = await client.rpc("confirm_wms_outbound_order", {
    p_outbound_order_id: parsedInput.outboundOrderId,
    p_expected_version: parsedInput.expectedVersion,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new WmsOutboundOrderMutationError(classifyError(error.message), error.message);
  }
  return parseOrderResponse(data, "confirm_wms_outbound_order");
}

/** Requires a non-empty reason; a same-status (already-cancelled) call is a no-op returning the current row. Does not check any pick/pack downstream progress (design note 8) -- ATW-017 owns that guard once it exists. */
export async function cancelWmsOutboundOrder(client: WmsOutboundOrderMutationRpcClient, input: CancelWmsOutboundOrderInput): Promise<WmsOutboundOrder> {
  const parsedInput = CancelWmsOutboundOrderInputSchema.parse(input);
  const { data, error } = await client.rpc("cancel_wms_outbound_order", {
    p_outbound_order_id: parsedInput.outboundOrderId,
    p_reason: parsedInput.reason,
    p_expected_version: parsedInput.expectedVersion,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new WmsOutboundOrderMutationError(classifyError(error.message), error.message);
  }
  return parseOrderResponse(data, "cancel_wms_outbound_order");
}
