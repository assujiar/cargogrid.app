/**
 * Lot, Batch, Serial and Expiry mutation primitives (ATW-016, CG-S10-ATW-016). Thin,
 * typed wrappers around app.create_item_control_policy_version_draft/
 * app.publish_item_control_policy_version/app.register_lot_identity/
 * app.register_serial_identity/app.set_lot_identity_status/
 * app.set_serial_identity_status
 * (supabase/migrations/20260730220000_create_advanced_tms_lot_batch_serial_expiry.sql).
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import {
  CreateItemControlPolicyVersionDraftInputSchema,
  PublishItemControlPolicyVersionInputSchema,
  RegisterLotIdentityInputSchema,
  RegisterSerialIdentityInputSchema,
  SetLotIdentityStatusInputSchema,
  SetSerialIdentityStatusInputSchema,
  parseItemControlPolicyVersion,
  parseLotIdentity,
  parseSerialIdentity,
  type CreateItemControlPolicyVersionDraftInput,
  type PublishItemControlPolicyVersionInput,
  type RegisterLotIdentityInput,
  type RegisterSerialIdentityInput,
  type SetLotIdentityStatusInput,
  type SetSerialIdentityStatusInput,
  type ItemControlPolicyVersion,
  type LotIdentity,
  type SerialIdentity,
} from "../contracts/lot-batch-serial/lot-batch-serial.ts";

export type LotBatchSerialMutationRpcClient = Pick<SupabaseClient, "rpc">;

export const LOT_BATCH_SERIAL_KNOWN_MUTATION_ERROR_CODES = [
  "insufficient_authority",
  "item_master_not_found",
  "invalid_allocation_rule",
  "invalid_near_expiry_warning_days",
  "expiry_date_not_applicable",
  "policy_version_not_found",
  "stale_version",
  "invalid_transition",
  "superseded_policy_not_found",
  "invalid_supersede",
  "active_policy_exists",
  "item_not_lot_controlled",
  "item_not_serial_controlled",
  "invalid_lot_number",
  "invalid_serial_number",
  "invalid_source_type",
  "invalid_date_order",
  "genealogy_mismatch",
  "parent_lot_not_found",
  "invalid_idempotency_key",
  "duplicate_serial",
  "invalid_status",
  "lot_identity_not_found",
  "serial_identity_not_found",
  "invalid_reason",
] as const;
type KnownLotBatchSerialMutationErrorCode = (typeof LOT_BATCH_SERIAL_KNOWN_MUTATION_ERROR_CODES)[number];
export type LotBatchSerialMutationErrorCode = KnownLotBatchSerialMutationErrorCode | "mutation_failed" | "invalid_response";

export class LotBatchSerialMutationError extends Error {
  readonly code: LotBatchSerialMutationErrorCode;

  constructor(code: LotBatchSerialMutationErrorCode, message: string) {
    super(message);
    this.name = "LotBatchSerialMutationError";
    this.code = code;
  }
}

function classifyError(message: string): LotBatchSerialMutationErrorCode {
  const prefix = message.split(":")[0]?.trim();
  return (LOT_BATCH_SERIAL_KNOWN_MUTATION_ERROR_CODES as readonly string[]).includes(prefix ?? "")
    ? (prefix as KnownLotBatchSerialMutationErrorCode)
    : "mutation_failed";
}

function firstRow(data: unknown): Record<string, unknown> | null {
  const row = Array.isArray(data) ? data[0] : data;
  return row && typeof row === "object" ? (row as Record<string, unknown>) : null;
}

/** Rejects fefo/nearExpiryWarningDays when the item is not expiry-controlled (uncontrolled items avoid unnecessary fields). */
export async function createItemControlPolicyVersionDraft(
  client: LotBatchSerialMutationRpcClient,
  input: CreateItemControlPolicyVersionDraftInput,
): Promise<ItemControlPolicyVersion> {
  const parsedInput = CreateItemControlPolicyVersionDraftInputSchema.parse(input);
  const { data, error } = await client.rpc("create_item_control_policy_version_draft", {
    p_item_master_id: parsedInput.itemMasterId,
    p_allocation_rule: parsedInput.allocationRule,
    p_hold_on_unknown_lot: parsedInput.holdOnUnknownLot,
    p_near_expiry_warning_days: parsedInput.nearExpiryWarningDays,
    p_effective_from: parsedInput.effectiveFrom,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new LotBatchSerialMutationError(classifyError(error.message), error.message);
  }
  const row = firstRow(data);
  if (!row) {
    throw new LotBatchSerialMutationError("invalid_response", "create_item_control_policy_version_draft returned no row");
  }
  return parseItemControlPolicyVersion(row);
}

/** OPS:Override-gated governance action. draft -> published, archiving supersedesVersionId first so at most one published policy ever exists per item. */
export async function publishItemControlPolicyVersion(
  client: LotBatchSerialMutationRpcClient,
  input: PublishItemControlPolicyVersionInput,
): Promise<ItemControlPolicyVersion> {
  const parsedInput = PublishItemControlPolicyVersionInputSchema.parse(input);
  const { data, error } = await client.rpc("publish_item_control_policy_version", {
    p_policy_version_id: parsedInput.policyVersionId,
    p_expected_version: parsedInput.expectedVersion,
    p_supersedes_version_id: parsedInput.supersedesVersionId,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new LotBatchSerialMutationError(classifyError(error.message), error.message);
  }
  const row = firstRow(data);
  if (!row) {
    throw new LotBatchSerialMutationError("invalid_response", "publish_item_control_policy_version returned no row");
  }
  return parseItemControlPolicyVersion(row);
}

/** Idempotent by natural key (tenant, owner, item, lotNumber) -- a repeat registration of an already-known lot is not an error. */
export async function registerLotIdentity(client: LotBatchSerialMutationRpcClient, input: RegisterLotIdentityInput): Promise<LotIdentity> {
  const parsedInput = RegisterLotIdentityInputSchema.parse(input);
  const { data, error } = await client.rpc("register_lot_identity", {
    p_item_master_id: parsedInput.itemMasterId,
    p_lot_number: parsedInput.lotNumber,
    p_manufacture_date: parsedInput.manufactureDate,
    p_expiry_date: parsedInput.expiryDate,
    p_source_type: parsedInput.sourceType,
    p_source_id: parsedInput.sourceId,
    p_parent_lot_id: parsedInput.parentLotId,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new LotBatchSerialMutationError(classifyError(error.message), error.message);
  }
  const row = firstRow(data);
  if (!row) {
    throw new LotBatchSerialMutationError("invalid_response", "register_lot_identity returned no row");
  }
  return parseLotIdentity(row);
}

/** Idempotent on idempotencyKey. A different idempotency key colliding on the real governed-scope uniqueness (tenant, item, serialNumber) is rejected duplicate_serial. */
export async function registerSerialIdentity(client: LotBatchSerialMutationRpcClient, input: RegisterSerialIdentityInput): Promise<SerialIdentity> {
  const parsedInput = RegisterSerialIdentityInputSchema.parse(input);
  const { data, error } = await client.rpc("register_serial_identity", {
    p_item_master_id: parsedInput.itemMasterId,
    p_serial_number: parsedInput.serialNumber,
    p_lot_number: parsedInput.lotNumber,
    p_manufacture_date: parsedInput.manufactureDate,
    p_expiry_date: parsedInput.expiryDate,
    p_source_type: parsedInput.sourceType,
    p_source_id: parsedInput.sourceId,
    p_idempotency_key: parsedInput.idempotencyKey,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new LotBatchSerialMutationError(classifyError(error.message), error.message);
  }
  const row = firstRow(data);
  if (!row) {
    throw new LotBatchSerialMutationError("invalid_response", "register_serial_identity returned no row");
  }
  return parseSerialIdentity(row);
}

/** OPS:Override-gated (supervisor hold/release/quarantine/expire/reactivate). consumed is terminal. */
export async function setLotIdentityStatus(client: LotBatchSerialMutationRpcClient, input: SetLotIdentityStatusInput): Promise<LotIdentity> {
  const parsedInput = SetLotIdentityStatusInputSchema.parse(input);
  const { data, error } = await client.rpc("set_lot_identity_status", {
    p_lot_identity_id: parsedInput.lotIdentityId,
    p_new_status: parsedInput.newStatus,
    p_reason: parsedInput.reason,
    p_expected_version: parsedInput.expectedVersion,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new LotBatchSerialMutationError(classifyError(error.message), error.message);
  }
  const row = firstRow(data);
  if (!row) {
    throw new LotBatchSerialMutationError("invalid_response", "set_lot_identity_status returned no row");
  }
  return parseLotIdentity(row);
}

/** OPS:Override-gated (supervisor hold/release/quarantine/expire/reactivate). consumed is terminal. */
export async function setSerialIdentityStatus(client: LotBatchSerialMutationRpcClient, input: SetSerialIdentityStatusInput): Promise<SerialIdentity> {
  const parsedInput = SetSerialIdentityStatusInputSchema.parse(input);
  const { data, error } = await client.rpc("set_serial_identity_status", {
    p_serial_identity_id: parsedInput.serialIdentityId,
    p_new_status: parsedInput.newStatus,
    p_reason: parsedInput.reason,
    p_expected_version: parsedInput.expectedVersion,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new LotBatchSerialMutationError(classifyError(error.message), error.message);
  }
  const row = firstRow(data);
  if (!row) {
    throw new LotBatchSerialMutationError("invalid_response", "set_serial_identity_status returned no row");
  }
  return parseSerialIdentity(row);
}
