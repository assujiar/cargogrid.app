/**
 * WMS Inbound mutation primitives (ATW-012, CG-S10-ATW-012). Thin, typed wrappers
 * around app.prepare_wms_inbound_from_shipment/app.create_manual_wms_inbound/
 * app.add_wms_inbound_order_line(s)/app.update_wms_inbound_order_line/
 * app.remove_wms_inbound_order_line/app.schedule_wms_inbound_appointment/
 * app.reschedule_wms_inbound_appointment/app.confirm_wms_inbound/
 * app.cancel_wms_inbound
 * (supabase/migrations/20260730180000_create_advanced_tms_wms_inbound.sql).
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import {
  PrepareWmsInboundFromShipmentInputSchema,
  CreateManualWmsInboundInputSchema,
  AddWmsInboundOrderLineInputSchema,
  AddWmsInboundOrderLinesInputSchema,
  UpdateWmsInboundOrderLineInputSchema,
  RemoveWmsInboundOrderLineInputSchema,
  ScheduleWmsInboundAppointmentInputSchema,
  ConfirmWmsInboundInputSchema,
  CancelWmsInboundInputSchema,
  parseWmsInboundOrder,
  parseWmsInboundOrderLine,
  type PrepareWmsInboundFromShipmentInput,
  type CreateManualWmsInboundInput,
  type AddWmsInboundOrderLineInput,
  type AddWmsInboundOrderLinesInput,
  type UpdateWmsInboundOrderLineInput,
  type RemoveWmsInboundOrderLineInput,
  type ScheduleWmsInboundAppointmentInput,
  type ConfirmWmsInboundInput,
  type CancelWmsInboundInput,
  type WmsInboundOrder,
  type WmsInboundOrderLine,
} from "../contracts/wms-inbound/wms-inbound.ts";

export type WmsInboundMutationRpcClient = Pick<SupabaseClient, "rpc">;

export const WMS_INBOUND_KNOWN_MUTATION_ERROR_CODES = [
  "insufficient_authority",
  "shipment_order_not_found",
  "warehouse_not_found",
  "warehouse_not_active",
  "stale_source",
  "owner_account_not_found",
  "invalid_reason",
  "invalid_idempotency_key",
  "inbound_order_not_found",
  "inbound_not_draft",
  "item_not_eligible",
  "invalid_uom",
  "invalid_quantity",
  "invalid_lines",
  "too_many_lines",
  "line_not_found",
  "stale_version",
  "invalid_transition",
  "invalid_appointment_window",
  "no_lines",
  "inbound_not_ready",
] as const;
type KnownWmsInboundMutationErrorCode = (typeof WMS_INBOUND_KNOWN_MUTATION_ERROR_CODES)[number];
export type WmsInboundMutationErrorCode = KnownWmsInboundMutationErrorCode | "mutation_failed" | "invalid_response";

export class WmsInboundMutationError extends Error {
  readonly code: WmsInboundMutationErrorCode;

  constructor(code: WmsInboundMutationErrorCode, message: string) {
    super(message);
    this.name = "WmsInboundMutationError";
    this.code = code;
  }
}

function classifyError(message: string): WmsInboundMutationErrorCode {
  const prefix = message.split(":")[0]?.trim();
  return (WMS_INBOUND_KNOWN_MUTATION_ERROR_CODES as readonly string[]).includes(prefix ?? "")
    ? (prefix as KnownWmsInboundMutationErrorCode)
    : "mutation_failed";
}

function firstRow(data: unknown): Record<string, unknown> | null {
  const row = Array.isArray(data) ? data[0] : data;
  return row && typeof row === "object" ? (row as Record<string, unknown>) : null;
}

function parseOrderResponse(data: unknown, rpcName: string): WmsInboundOrder {
  const row = firstRow(data);
  if (!row) {
    throw new WmsInboundMutationError("invalid_response", `${rpcName} returned no row`);
  }
  return parseWmsInboundOrder(row);
}

function parseLineResponse(data: unknown, rpcName: string): WmsInboundOrderLine {
  const row = firstRow(data);
  if (!row) {
    throw new WmsInboundMutationError("invalid_response", `${rpcName} returned no row`);
  }
  return parseWmsInboundOrderLine(row);
}

/** Idempotent on (tenant_id, source_shipment_order_id) among non-cancelled rows. owner_account_id is inherited from the shipment order's own shipper_account_id. */
export async function prepareWmsInboundFromShipment(client: WmsInboundMutationRpcClient, input: PrepareWmsInboundFromShipmentInput): Promise<WmsInboundOrder> {
  const parsedInput = PrepareWmsInboundFromShipmentInputSchema.parse(input);
  const { data, error } = await client.rpc("prepare_wms_inbound_from_shipment", {
    p_tenant_id: parsedInput.tenantId,
    p_shipment_order_id: parsedInput.shipmentOrderId,
    p_warehouse_id: parsedInput.warehouseId,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new WmsInboundMutationError(classifyError(error.message), error.message);
  }
  return parseOrderResponse(data, "prepare_wms_inbound_from_shipment");
}

/** The governed manual-entry exception path -- requires a non-empty sourceReason. Idempotent on (tenant_id, idempotencyKey) among non-cancelled rows. */
export async function createManualWmsInbound(client: WmsInboundMutationRpcClient, input: CreateManualWmsInboundInput): Promise<WmsInboundOrder> {
  const parsedInput = CreateManualWmsInboundInputSchema.parse(input);
  const { data, error } = await client.rpc("create_manual_wms_inbound", {
    p_tenant_id: parsedInput.tenantId,
    p_warehouse_id: parsedInput.warehouseId,
    p_owner_account_id: parsedInput.ownerAccountId,
    p_source_reason: parsedInput.sourceReason,
    p_idempotency_key: parsedInput.idempotencyKey,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new WmsInboundMutationError(classifyError(error.message), error.message);
  }
  return parseOrderResponse(data, "create_manual_wms_inbound");
}

/** Only while the header is draft. Rejects an item not owned by the same account as the inbound order. */
export async function addWmsInboundOrderLine(client: WmsInboundMutationRpcClient, input: AddWmsInboundOrderLineInput): Promise<WmsInboundOrderLine> {
  const parsedInput = AddWmsInboundOrderLineInputSchema.parse(input);
  const { data, error } = await client.rpc("add_wms_inbound_order_line", {
    p_inbound_order_id: parsedInput.inboundOrderId,
    p_item_master_id: parsedInput.itemMasterId,
    p_expected_uom_code: parsedInput.expectedUomCode,
    p_expected_quantity: parsedInput.expectedQuantity,
    p_notes: parsedInput.notes,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new WmsInboundMutationError(classifyError(error.message), error.message);
  }
  return parseLineResponse(data, "add_wms_inbound_order_line");
}

/** The bounded bulk/staged-import alt flow (Prompt 231 section 22) -- all-or-nothing, at most 200 lines per call. */
export async function addWmsInboundOrderLines(client: WmsInboundMutationRpcClient, input: AddWmsInboundOrderLinesInput): Promise<WmsInboundOrderLine[]> {
  const parsedInput = AddWmsInboundOrderLinesInputSchema.parse(input);
  const { data, error } = await client.rpc("add_wms_inbound_order_lines", {
    p_inbound_order_id: parsedInput.inboundOrderId,
    p_lines: parsedInput.lines.map((line) => ({
      item_master_id: line.itemMasterId,
      expected_uom_code: line.expectedUomCode,
      expected_quantity: line.expectedQuantity,
      notes: line.notes ?? null,
    })),
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new WmsInboundMutationError(classifyError(error.message), error.message);
  }
  return ((data as Record<string, unknown>[] | null) ?? []).map(parseWmsInboundOrderLine);
}

/** Mutable fields only. Optimistic-concurrency gated. Only while the header is draft. */
export async function updateWmsInboundOrderLine(client: WmsInboundMutationRpcClient, input: UpdateWmsInboundOrderLineInput): Promise<WmsInboundOrderLine> {
  const parsedInput = UpdateWmsInboundOrderLineInputSchema.parse(input);
  const { data, error } = await client.rpc("update_wms_inbound_order_line", {
    p_line_id: parsedInput.lineId,
    p_expected_quantity: parsedInput.expectedQuantity,
    p_notes: parsedInput.notes,
    p_expected_version: parsedInput.expectedVersion,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new WmsInboundMutationError(classifyError(error.message), error.message);
  }
  return parseLineResponse(data, "update_wms_inbound_order_line");
}

/** Only while the header is draft. Optimistic-concurrency gated. */
export async function removeWmsInboundOrderLine(client: WmsInboundMutationRpcClient, input: RemoveWmsInboundOrderLineInput): Promise<boolean> {
  const parsedInput = RemoveWmsInboundOrderLineInputSchema.parse(input);
  const { data, error } = await client.rpc("remove_wms_inbound_order_line", {
    p_line_id: parsedInput.lineId,
    p_expected_version: parsedInput.expectedVersion,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new WmsInboundMutationError(classifyError(error.message), error.message);
  }
  return Boolean(data);
}

/** draft -> scheduled only, requires at least one line to already exist. */
export async function scheduleWmsInboundAppointment(client: WmsInboundMutationRpcClient, input: ScheduleWmsInboundAppointmentInput): Promise<WmsInboundOrder> {
  const parsedInput = ScheduleWmsInboundAppointmentInputSchema.parse(input);
  const { data, error } = await client.rpc("schedule_wms_inbound_appointment", {
    p_inbound_order_id: parsedInput.inboundOrderId,
    p_window_start: parsedInput.windowStart,
    p_window_end: parsedInput.windowEnd,
    p_expected_version: parsedInput.expectedVersion,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new WmsInboundMutationError(classifyError(error.message), error.message);
  }
  return parseOrderResponse(data, "schedule_wms_inbound_appointment");
}

/** The reschedule alt flow -- scheduled or confirmed only; status itself never changes. */
export async function rescheduleWmsInboundAppointment(client: WmsInboundMutationRpcClient, input: ScheduleWmsInboundAppointmentInput): Promise<WmsInboundOrder> {
  const parsedInput = ScheduleWmsInboundAppointmentInputSchema.parse(input);
  const { data, error } = await client.rpc("reschedule_wms_inbound_appointment", {
    p_inbound_order_id: parsedInput.inboundOrderId,
    p_window_start: parsedInput.windowStart,
    p_window_end: parsedInput.windowEnd,
    p_expected_version: parsedInput.expectedVersion,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new WmsInboundMutationError(classifyError(error.message), error.message);
  }
  return parseOrderResponse(data, "reschedule_wms_inbound_appointment");
}

/** scheduled -> confirmed only, re-validates full readiness rather than trusting a stale prior check. */
export async function confirmWmsInbound(client: WmsInboundMutationRpcClient, input: ConfirmWmsInboundInput): Promise<WmsInboundOrder> {
  const parsedInput = ConfirmWmsInboundInputSchema.parse(input);
  const { data, error } = await client.rpc("confirm_wms_inbound", {
    p_inbound_order_id: parsedInput.inboundOrderId,
    p_expected_version: parsedInput.expectedVersion,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new WmsInboundMutationError(classifyError(error.message), error.message);
  }
  return parseOrderResponse(data, "confirm_wms_inbound");
}

/** Requires a non-empty reason; a same-status (already-cancelled) call is a no-op returning the current row. Does not check real receiving progress (design note 8) -- ATW-232 owns that guard. */
export async function cancelWmsInbound(client: WmsInboundMutationRpcClient, input: CancelWmsInboundInput): Promise<WmsInboundOrder> {
  const parsedInput = CancelWmsInboundInputSchema.parse(input);
  const { data, error } = await client.rpc("cancel_wms_inbound", {
    p_inbound_order_id: parsedInput.inboundOrderId,
    p_reason: parsedInput.reason,
    p_expected_version: parsedInput.expectedVersion,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new WmsInboundMutationError(classifyError(error.message), error.message);
  }
  return parseOrderResponse(data, "cancel_wms_inbound");
}
