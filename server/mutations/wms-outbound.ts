/**
 * WMS Outbound (ship-execution) mutation primitives (ATW-019, CG-S10-ATW-019). Thin,
 * typed wrappers around app.create_wms_outbound_shipment/app.add_package_to_shipment/
 * app.remove_package_from_shipment/app.set_wms_shipment_vehicle_ref/
 * app.set_wms_shipment_dock_location/app.load_wms_outbound_shipment/
 * app.ship_confirm_wms_outbound_shipment/app.cancel_wms_outbound_shipment
 * (supabase/migrations/20260730260000_create_advanced_tms_wms_outbound.sql).
 *
 * Distinct filename from server/mutations/wms-outbound-order.ts (ATW-016A).
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import {
  CreateWmsOutboundShipmentInputSchema,
  AddPackageToShipmentInputSchema,
  RemovePackageFromShipmentInputSchema,
  SetWmsShipmentVehicleRefInputSchema,
  SetWmsShipmentDockLocationInputSchema,
  LoadWmsOutboundShipmentInputSchema,
  ShipConfirmWmsOutboundShipmentInputSchema,
  CancelWmsOutboundShipmentInputSchema,
  parseWmsOutboundShipment,
  type CreateWmsOutboundShipmentInput,
  type AddPackageToShipmentInput,
  type RemovePackageFromShipmentInput,
  type SetWmsShipmentVehicleRefInput,
  type SetWmsShipmentDockLocationInput,
  type LoadWmsOutboundShipmentInput,
  type ShipConfirmWmsOutboundShipmentInput,
  type CancelWmsOutboundShipmentInput,
  type WmsOutboundShipment,
} from "../contracts/wms-outbound/wms-outbound.ts";

export type WmsOutboundMutationRpcClient = Pick<SupabaseClient, "rpc">;

export const WMS_OUTBOUND_KNOWN_MUTATION_ERROR_CODES = [
  "insufficient_authority",
  "invalid_idempotency_key",
  "invalid_reason",
  "invalid_transition",
  "stale_version",
  "outbound_order_not_found",
  "outbound_order_not_confirmed",
  "warehouse_not_found",
  "shipment_not_found",
  "shipment_not_staging",
  "shipment_locked",
  "shipment_not_cancellable",
  "package_not_found",
  "package_not_confirmed",
  "package_already_staged",
  "wrong_order",
  "wrong_owner",
  "location_not_found",
  "incompatible_location",
  "blocked_destination",
  "dock_location_not_set",
  "empty_shipment_rejected",
  "custody_required",
  "partial_fulfillment_not_acknowledged",
  "insufficient_stock",
  // ATW-032: app.inventory_balances carries a non-deferrable (reserved + held) <= on_hand
  // CHECK that post_inventory_movement never tested, so a cycle-count variance approved
  // against pre-freeze reserved stock died on a raw 23514 no caller classified.
  "insufficient_unreserved_stock",
  "idempotency_key_conflict",
] as const;
type KnownWmsOutboundMutationErrorCode = (typeof WMS_OUTBOUND_KNOWN_MUTATION_ERROR_CODES)[number];
export type WmsOutboundMutationErrorCode = KnownWmsOutboundMutationErrorCode | "mutation_failed" | "invalid_response";

export class WmsOutboundMutationError extends Error {
  readonly code: WmsOutboundMutationErrorCode;

  constructor(code: WmsOutboundMutationErrorCode, message: string) {
    super(message);
    this.name = "WmsOutboundMutationError";
    this.code = code;
  }
}

function classifyError(message: string): WmsOutboundMutationErrorCode {
  const prefix = message.split(":")[0]?.trim();
  return (WMS_OUTBOUND_KNOWN_MUTATION_ERROR_CODES as readonly string[]).includes(prefix ?? "")
    ? (prefix as KnownWmsOutboundMutationErrorCode)
    : "mutation_failed";
}

function firstRow(data: unknown): Record<string, unknown> | null {
  const row = Array.isArray(data) ? data[0] : data;
  return row && typeof row === "object" ? (row as Record<string, unknown>) : null;
}

function parseShipmentResponse(data: unknown, rpcName: string): WmsOutboundShipment {
  const row = firstRow(data);
  if (!row) {
    throw new WmsOutboundMutationError("invalid_response", `${rpcName} returned no row`);
  }
  return parseWmsOutboundShipment(row);
}

/** Idempotent on (tenant_id, idempotency_key), including under a genuine race. Multiple shipments per order are allowed -- no one-per-order guard. */
export async function createWmsOutboundShipment(client: WmsOutboundMutationRpcClient, input: CreateWmsOutboundShipmentInput): Promise<WmsOutboundShipment> {
  const parsedInput = CreateWmsOutboundShipmentInputSchema.parse(input);
  const { data, error } = await client.rpc("create_wms_outbound_shipment", {
    p_outbound_order_id: parsedInput.outboundOrderId,
    p_idempotency_key: parsedInput.idempotencyKey,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new WmsOutboundMutationError(classifyError(error.message), error.message);
  }
  return parseShipmentResponse(data, "create_wms_outbound_shipment");
}

/** Rejects package_not_confirmed/wrong_order/wrong_owner/package_already_staged. Idempotent on (tenant_id, idempotency_key). Only while the shipment is staging. */
export async function addPackageToShipment(client: WmsOutboundMutationRpcClient, input: AddPackageToShipmentInput): Promise<WmsOutboundShipment> {
  const parsedInput = AddPackageToShipmentInputSchema.parse(input);
  const { data, error } = await client.rpc("add_package_to_shipment", {
    p_shipment_id: parsedInput.shipmentId,
    p_package_id: parsedInput.packageId,
    p_idempotency_key: parsedInput.idempotencyKey,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new WmsOutboundMutationError(classifyError(error.message), error.message);
  }
  return parseShipmentResponse(data, "add_package_to_shipment");
}

/** Only while staging. Idempotent no-op if the package is not (or no longer) staged on this shipment -- never an error on a legitimate retry. */
export async function removePackageFromShipment(client: WmsOutboundMutationRpcClient, input: RemovePackageFromShipmentInput): Promise<boolean> {
  const parsedInput = RemovePackageFromShipmentInputSchema.parse(input);
  const { data, error } = await client.rpc("remove_package_from_shipment", {
    p_shipment_id: parsedInput.shipmentId,
    p_package_id: parsedInput.packageId,
    p_reason: parsedInput.reason,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new WmsOutboundMutationError(classifyError(error.message), error.message);
  }
  return Boolean(data);
}

/** A plain, disclosed text/reference field -- no live dispatch/capacity integration. Settable while staging OR loaded, never once shipped/cancelled. */
export async function setWmsShipmentVehicleRef(client: WmsOutboundMutationRpcClient, input: SetWmsShipmentVehicleRefInput): Promise<WmsOutboundShipment> {
  const parsedInput = SetWmsShipmentVehicleRefInputSchema.parse(input);
  const { data, error } = await client.rpc("set_wms_shipment_vehicle_ref", {
    p_shipment_id: parsedInput.shipmentId,
    p_vehicle_ref: parsedInput.vehicleRef,
    p_expected_version: parsedInput.expectedVersion,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new WmsOutboundMutationError(classifyError(error.message), error.message);
  }
  return parseShipmentResponse(data, "set_wms_shipment_vehicle_ref");
}

/** A real app.warehouse_locations FK (location_type = dock). Only settable/changeable while staging -- fixed once app.load_wms_outbound_shipment posts its own real transfer. */
export async function setWmsShipmentDockLocation(client: WmsOutboundMutationRpcClient, input: SetWmsShipmentDockLocationInput): Promise<WmsOutboundShipment> {
  const parsedInput = SetWmsShipmentDockLocationInputSchema.parse(input);
  const { data, error } = await client.rpc("set_wms_shipment_dock_location", {
    p_shipment_id: parsedInput.shipmentId,
    p_dock_location_id: parsedInput.dockLocationId,
    p_expected_version: parsedInput.expectedVersion,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new WmsOutboundMutationError(classifyError(error.message), error.message);
  }
  return parseShipmentResponse(data, "set_wms_shipment_dock_location");
}

/** The one and only path that ever posts a real transfer movement for a shipment (staging location(s) -> dock). staging -> loaded only. Idempotent on (tenant_id, idempotency_key), including under a genuine race. */
export async function loadWmsOutboundShipment(client: WmsOutboundMutationRpcClient, input: LoadWmsOutboundShipmentInput): Promise<WmsOutboundShipment> {
  const parsedInput = LoadWmsOutboundShipmentInputSchema.parse(input);
  const { data, error } = await client.rpc("load_wms_outbound_shipment", {
    p_shipment_id: parsedInput.shipmentId,
    p_idempotency_key: parsedInput.idempotencyKey,
    p_expected_version: parsedInput.expectedVersion,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new WmsOutboundMutationError(classifyError(error.message), error.message);
  }
  return parseShipmentResponse(data, "load_wms_outbound_shipment");
}

/**
 * The atomic terminal step -- ship confirmation, custody event and inventory issue (a
 * single batched consumption movement) commit together in one transaction, idempotent
 * on (tenant_id, idempotency_key). loaded -> shipped only; a genuine concurrent
 * double-confirm is rejected invalid_transition once the first winner commits. Requires
 * explicit isPartialFulfillment acknowledgment whenever real confirmed packages of the
 * order remain unshipped. Creates exactly one billing-eligibility event.
 */
export async function shipConfirmWmsOutboundShipment(client: WmsOutboundMutationRpcClient, input: ShipConfirmWmsOutboundShipmentInput): Promise<WmsOutboundShipment> {
  const parsedInput = ShipConfirmWmsOutboundShipmentInputSchema.parse(input);
  const { data, error } = await client.rpc("ship_confirm_wms_outbound_shipment", {
    p_shipment_id: parsedInput.shipmentId,
    p_custody_confirmed_by_label: parsedInput.custodyConfirmedByLabel,
    p_custody_confirmed_reason: parsedInput.custodyConfirmedReason,
    p_is_partial_fulfillment: parsedInput.isPartialFulfillment,
    p_partial_fulfillment_reason: parsedInput.partialFulfillmentReason,
    p_idempotency_key: parsedInput.idempotencyKey,
    p_expected_version: parsedInput.expectedVersion,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new WmsOutboundMutationError(classifyError(error.message), error.message);
  }
  return parseShipmentResponse(data, "ship_confirm_wms_outbound_shipment");
}

/** Only while staging (before any real ledger movement has posted) -- frees every staged package for a future shipment attempt. A loaded shipment is not cancellable via this RPC. */
export async function cancelWmsOutboundShipment(client: WmsOutboundMutationRpcClient, input: CancelWmsOutboundShipmentInput): Promise<WmsOutboundShipment> {
  const parsedInput = CancelWmsOutboundShipmentInputSchema.parse(input);
  const { data, error } = await client.rpc("cancel_wms_outbound_shipment", {
    p_shipment_id: parsedInput.shipmentId,
    p_reason: parsedInput.reason,
    p_expected_version: parsedInput.expectedVersion,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new WmsOutboundMutationError(classifyError(error.message), error.message);
  }
  return parseShipmentResponse(data, "cancel_wms_outbound_shipment");
}
