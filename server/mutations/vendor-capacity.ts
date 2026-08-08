/**
 * Vendor Capacity and Availability mutation primitives (PRC-262, CG-S11-PRC-013).
 * Thin, typed wrappers around the write RPCs supabase/migrations/
 * 20260730710000_create_procurement_vendor_capacity.sql adds -- the same
 * KNOWN_MUTATION_ERROR_CODES / classifyError / callRpc shape
 * server/mutations/vendor-contract.ts already establishes for this checkpoint's own
 * template.
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import {
  CreateVendorCapacityOfferDraftInputSchema,
  UpdateVendorCapacityOfferDraftInputSchema,
  PublishVendorCapacityOfferInputSchema,
  ArchiveVendorCapacityOfferInputSchema,
  AddVendorCapacityBlackoutInputSchema,
  RemoveVendorCapacityBlackoutInputSchema,
  ReserveVendorCapacityInputSchema,
  AcceptVendorCapacityReservationInputSchema,
  DeclineVendorCapacityReservationInputSchema,
  ReleaseVendorCapacityReservationInputSchema,
  ConsumeVendorCapacityReservationInputSchema,
  parseVendorCapacityOffer,
  parseVendorCapacityBlackout,
  parseVendorCapacityReservation,
  type CreateVendorCapacityOfferDraftInput,
  type UpdateVendorCapacityOfferDraftInput,
  type PublishVendorCapacityOfferInput,
  type ArchiveVendorCapacityOfferInput,
  type AddVendorCapacityBlackoutInput,
  type RemoveVendorCapacityBlackoutInput,
  type ReserveVendorCapacityInput,
  type AcceptVendorCapacityReservationInput,
  type DeclineVendorCapacityReservationInput,
  type ReleaseVendorCapacityReservationInput,
  type ConsumeVendorCapacityReservationInput,
  type VendorCapacityOffer,
  type VendorCapacityBlackout,
  type VendorCapacityReservation,
} from "../contracts/vendor-capacity/vendor-capacity.ts";

export type VendorCapacityMutationRpcClient = Pick<SupabaseClient, "rpc">;

export const VENDOR_CAPACITY_KNOWN_MUTATION_ERROR_CODES = [
  "insufficient_authority",
  "vendor_capacity_offer_not_found",
  "vendor_capacity_blackout_not_found",
  "vendor_capacity_reservation_not_found",
  "vendor_profile_not_found",
  "invalid_resource_reference",
  "invalid_contract_reference",
  "invalid_quantity",
  "invalid_window",
  "reason_required",
  "idempotency_key_conflict",
  "invalid_transition",
  "active_reservations_exist",
  "reservation_outside_offer_window",
  "reservation_in_blackout",
  "over_reservation",
  "stale_version",
] as const;
type KnownVendorCapacityMutationErrorCode = (typeof VENDOR_CAPACITY_KNOWN_MUTATION_ERROR_CODES)[number];
export type VendorCapacityMutationErrorCode = KnownVendorCapacityMutationErrorCode | "mutation_failed" | "invalid_response";

export class VendorCapacityMutationError extends Error {
  readonly code: VendorCapacityMutationErrorCode;

  constructor(code: VendorCapacityMutationErrorCode, message: string) {
    super(message);
    this.name = "VendorCapacityMutationError";
    this.code = code;
  }
}

function classifyError(message: string): VendorCapacityMutationErrorCode {
  const prefix = message.split(":")[0]?.trim();
  return (VENDOR_CAPACITY_KNOWN_MUTATION_ERROR_CODES as readonly string[]).includes(prefix ?? "") ? (prefix as KnownVendorCapacityMutationErrorCode) : "mutation_failed";
}

async function callRpc(client: VendorCapacityMutationRpcClient, fn: string, args: Record<string, unknown>): Promise<unknown> {
  const { data, error } = await client.rpc(fn, args);
  if (error) {
    throw new VendorCapacityMutationError(classifyError(error.message), error.message);
  }
  return data;
}

function requireOfferRow(data: unknown, fn: string): VendorCapacityOffer {
  const row = Array.isArray(data) ? data[0] : data;
  if (!row || typeof row !== "object") {
    throw new VendorCapacityMutationError("invalid_response", `${fn} returned no row`);
  }
  return parseVendorCapacityOffer(row as Record<string, unknown>);
}

function requireReservationRow(data: unknown, fn: string): VendorCapacityReservation {
  const row = Array.isArray(data) ? data[0] : data;
  if (!row || typeof row !== "object") {
    throw new VendorCapacityMutationError("invalid_response", `${fn} returned no row`);
  }
  return parseVendorCapacityReservation(row as Record<string, unknown>);
}

export async function createVendorCapacityOfferDraft(client: VendorCapacityMutationRpcClient, input: CreateVendorCapacityOfferDraftInput): Promise<VendorCapacityOffer> {
  const parsed = CreateVendorCapacityOfferDraftInputSchema.parse(input);
  const data = await callRpc(client, "create_vendor_capacity_offer_draft", {
    p_tenant_id: parsed.tenantId,
    p_vendor_master_id: parsed.vendorMasterId,
    p_contract_id: parsed.contractId,
    p_service_type: parsed.serviceType,
    p_mode: parsed.mode,
    p_origin_lane: parsed.originLane,
    p_destination_lane: parsed.destinationLane,
    p_resource_type: parsed.resourceType,
    p_resource_master_id: parsed.resourceMasterId,
    p_quantity: parsed.quantity,
    p_uom: parsed.uom,
    p_window_start: parsed.windowStart,
    p_window_end: parsed.windowEnd,
    p_idempotency_key: parsed.idempotencyKey,
    p_actor_auth_user_id: parsed.actorAuthUserId,
    p_actor_label: parsed.actorLabel,
  });
  return requireOfferRow(data, "create_vendor_capacity_offer_draft");
}

export async function updateVendorCapacityOfferDraft(client: VendorCapacityMutationRpcClient, input: UpdateVendorCapacityOfferDraftInput): Promise<VendorCapacityOffer> {
  const parsed = UpdateVendorCapacityOfferDraftInputSchema.parse(input);
  const data = await callRpc(client, "update_vendor_capacity_offer_draft", {
    p_offer_id: parsed.offerId,
    p_expected_version: parsed.expectedVersion,
    p_contract_id: parsed.contractId,
    p_mode: parsed.mode,
    p_origin_lane: parsed.originLane,
    p_destination_lane: parsed.destinationLane,
    p_resource_master_id: parsed.resourceMasterId,
    p_quantity: parsed.quantity,
    p_uom: parsed.uom,
    p_window_start: parsed.windowStart,
    p_window_end: parsed.windowEnd,
    p_actor_auth_user_id: parsed.actorAuthUserId,
    p_actor_label: parsed.actorLabel,
  });
  return requireOfferRow(data, "update_vendor_capacity_offer_draft");
}

export async function publishVendorCapacityOffer(client: VendorCapacityMutationRpcClient, input: PublishVendorCapacityOfferInput): Promise<VendorCapacityOffer> {
  const parsed = PublishVendorCapacityOfferInputSchema.parse(input);
  const data = await callRpc(client, "publish_vendor_capacity_offer", {
    p_offer_id: parsed.offerId,
    p_expected_version: parsed.expectedVersion,
    p_actor_auth_user_id: parsed.actorAuthUserId,
    p_actor_label: parsed.actorLabel,
  });
  return requireOfferRow(data, "publish_vendor_capacity_offer");
}

export async function archiveVendorCapacityOffer(client: VendorCapacityMutationRpcClient, input: ArchiveVendorCapacityOfferInput): Promise<VendorCapacityOffer> {
  const parsed = ArchiveVendorCapacityOfferInputSchema.parse(input);
  const data = await callRpc(client, "archive_vendor_capacity_offer", {
    p_offer_id: parsed.offerId,
    p_expected_version: parsed.expectedVersion,
    p_actor_auth_user_id: parsed.actorAuthUserId,
    p_actor_label: parsed.actorLabel,
  });
  return requireOfferRow(data, "archive_vendor_capacity_offer");
}

export async function addVendorCapacityBlackout(client: VendorCapacityMutationRpcClient, input: AddVendorCapacityBlackoutInput): Promise<VendorCapacityBlackout> {
  const parsed = AddVendorCapacityBlackoutInputSchema.parse(input);
  const data = await callRpc(client, "add_vendor_capacity_blackout", {
    p_offer_id: parsed.offerId,
    p_window_start: parsed.windowStart,
    p_window_end: parsed.windowEnd,
    p_reason: parsed.reason,
    p_actor_auth_user_id: parsed.actorAuthUserId,
    p_actor_label: parsed.actorLabel,
  });
  const row = Array.isArray(data) ? data[0] : data;
  if (!row || typeof row !== "object") {
    throw new VendorCapacityMutationError("invalid_response", "add_vendor_capacity_blackout returned no row");
  }
  return parseVendorCapacityBlackout(row as Record<string, unknown>);
}

export async function removeVendorCapacityBlackout(client: VendorCapacityMutationRpcClient, input: RemoveVendorCapacityBlackoutInput): Promise<void> {
  const parsed = RemoveVendorCapacityBlackoutInputSchema.parse(input);
  await callRpc(client, "remove_vendor_capacity_blackout", {
    p_blackout_id: parsed.blackoutId,
    p_expected_version: parsed.expectedVersion,
    p_actor_auth_user_id: parsed.actorAuthUserId,
    p_actor_label: parsed.actorLabel,
  });
}

/** The concurrency-critical write -- locks the parent offer row before computing available-vs-committed (migration design note 2). status=held. */
export async function reserveVendorCapacity(client: VendorCapacityMutationRpcClient, input: ReserveVendorCapacityInput): Promise<VendorCapacityReservation> {
  const parsed = ReserveVendorCapacityInputSchema.parse(input);
  const data = await callRpc(client, "reserve_vendor_capacity", {
    p_offer_id: parsed.offerId,
    p_requested_quantity: parsed.requestedQuantity,
    p_window_start: parsed.windowStart,
    p_window_end: parsed.windowEnd,
    p_source_reference_type: parsed.sourceReferenceType,
    p_source_reference_id: parsed.sourceReferenceId,
    p_idempotency_key: parsed.idempotencyKey,
    p_actor_auth_user_id: parsed.actorAuthUserId,
    p_actor_label: parsed.actorLabel,
  });
  return requireReservationRow(data, "reserve_vendor_capacity");
}

export async function acceptVendorCapacityReservation(client: VendorCapacityMutationRpcClient, input: AcceptVendorCapacityReservationInput): Promise<VendorCapacityReservation> {
  const parsed = AcceptVendorCapacityReservationInputSchema.parse(input);
  const data = await callRpc(client, "accept_vendor_capacity_reservation", {
    p_reservation_id: parsed.reservationId,
    p_expected_version: parsed.expectedVersion,
    p_actor_auth_user_id: parsed.actorAuthUserId,
    p_actor_label: parsed.actorLabel,
  });
  return requireReservationRow(data, "accept_vendor_capacity_reservation");
}

export async function declineVendorCapacityReservation(client: VendorCapacityMutationRpcClient, input: DeclineVendorCapacityReservationInput): Promise<VendorCapacityReservation> {
  const parsed = DeclineVendorCapacityReservationInputSchema.parse(input);
  const data = await callRpc(client, "decline_vendor_capacity_reservation", {
    p_reservation_id: parsed.reservationId,
    p_expected_version: parsed.expectedVersion,
    p_reason: parsed.reason,
    p_actor_auth_user_id: parsed.actorAuthUserId,
    p_actor_label: parsed.actorLabel,
  });
  return requireReservationRow(data, "decline_vendor_capacity_reservation");
}

export async function releaseVendorCapacityReservation(client: VendorCapacityMutationRpcClient, input: ReleaseVendorCapacityReservationInput): Promise<VendorCapacityReservation> {
  const parsed = ReleaseVendorCapacityReservationInputSchema.parse(input);
  const data = await callRpc(client, "release_vendor_capacity_reservation", {
    p_reservation_id: parsed.reservationId,
    p_expected_version: parsed.expectedVersion,
    p_reason: parsed.reason,
    p_actor_auth_user_id: parsed.actorAuthUserId,
    p_actor_label: parsed.actorLabel,
  });
  return requireReservationRow(data, "release_vendor_capacity_reservation");
}

/** accepted -> consumed. Callable standalone (PRC:Edit) for manual reconciliation; PRC-263 (next in this same batch) also calls this directly once a real assignment consumes the held commitment. */
export async function consumeVendorCapacityReservation(client: VendorCapacityMutationRpcClient, input: ConsumeVendorCapacityReservationInput): Promise<VendorCapacityReservation> {
  const parsed = ConsumeVendorCapacityReservationInputSchema.parse(input);
  const data = await callRpc(client, "consume_vendor_capacity_reservation", {
    p_reservation_id: parsed.reservationId,
    p_expected_version: parsed.expectedVersion,
    p_actor_auth_user_id: parsed.actorAuthUserId,
    p_actor_label: parsed.actorLabel,
  });
  return requireReservationRow(data, "consume_vendor_capacity_reservation");
}
