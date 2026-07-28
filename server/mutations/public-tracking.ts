/**
 * Basic Public and Customer Tracking mutation primitives (OPS-180, CG-S8-OPS-014).
 * Thin, typed wrappers around the RPCs in
 * supabase/migrations/20260728130000_create_operations_public_tracking.sql.
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import {
  IssueShipmentTrackingTokenInputSchema,
  RevokeShipmentTrackingTokenInputSchema,
  parseIssuedShipmentTrackingToken,
  parseShipmentTrackingToken,
  type IssueShipmentTrackingTokenInput,
  type RevokeShipmentTrackingTokenInput,
  type IssuedShipmentTrackingToken,
  type ShipmentTrackingToken,
} from "../contracts/public-tracking/public-tracking.ts";

export type PublicTrackingMutationRpcClient = Pick<SupabaseClient, "rpc">;

export const PUBLIC_TRACKING_KNOWN_MUTATION_ERROR_CODES = [
  "shipment_order_not_found",
  "tracking_invalid_validity_days",
  "tracking_revoke_reason_required",
  "tracking_no_active_token",
  "insufficient_authority",
] as const;
type KnownPublicTrackingMutationErrorCode = (typeof PUBLIC_TRACKING_KNOWN_MUTATION_ERROR_CODES)[number];
export type PublicTrackingMutationErrorCode = KnownPublicTrackingMutationErrorCode | "mutation_failed" | "invalid_response";

export class PublicTrackingMutationError extends Error {
  readonly code: PublicTrackingMutationErrorCode;

  constructor(code: PublicTrackingMutationErrorCode, message: string) {
    super(message);
    this.name = "PublicTrackingMutationError";
    this.code = code;
  }
}

function classifyError(message: string): PublicTrackingMutationErrorCode {
  const prefix = message.split(":")[0]?.trim();
  return (PUBLIC_TRACKING_KNOWN_MUTATION_ERROR_CODES as readonly string[]).includes(prefix ?? "") ? (prefix as KnownPublicTrackingMutationErrorCode) : "mutation_failed";
}

/** Issuing again revokes the prior active token first -- at most one active token per shipment. */
export async function issueShipmentTrackingToken(client: PublicTrackingMutationRpcClient, input: IssueShipmentTrackingTokenInput): Promise<IssuedShipmentTrackingToken> {
  const parsedInput = IssueShipmentTrackingTokenInputSchema.parse(input);
  const { data, error } = await client.rpc("issue_shipment_tracking_token", {
    p_shipment_order_id: parsedInput.shipmentOrderId,
    p_validity_days: parsedInput.validityDays,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new PublicTrackingMutationError(classifyError(error.message), error.message);
  }
  const row = Array.isArray(data) ? data[0] : data;
  if (!row || typeof row !== "object") {
    throw new PublicTrackingMutationError("invalid_response", "issue_shipment_tracking_token returned no row");
  }
  return parseIssuedShipmentTrackingToken(row as Record<string, unknown>);
}

export async function revokeShipmentTrackingToken(client: PublicTrackingMutationRpcClient, input: RevokeShipmentTrackingTokenInput): Promise<ShipmentTrackingToken> {
  const parsedInput = RevokeShipmentTrackingTokenInputSchema.parse(input);
  const { data, error } = await client.rpc("revoke_shipment_tracking_token", {
    p_shipment_order_id: parsedInput.shipmentOrderId,
    p_reason: parsedInput.reason,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new PublicTrackingMutationError(classifyError(error.message), error.message);
  }
  if (!data || typeof data !== "object") {
    throw new PublicTrackingMutationError("invalid_response", "revoke_shipment_tracking_token returned no row");
  }
  return parseShipmentTrackingToken(data as Record<string, unknown>);
}
