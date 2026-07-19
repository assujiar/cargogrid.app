/**
 * Numbering engine mutation primitives (PLT-125, CG-S6-PLT-022). Thin, typed wrappers
 * around app.publish_numbering_definition / app.bootstrap_numbering_counter /
 * app.allocate_number / app.reserve_number / app.confirm_number_reservation /
 * app.release_number_reservation / app.void_number_allocation
 * (supabase/migrations/20260719110000_create_numbering_engine.sql). All
 * service_role-only (see the migration's own grant comment).
 */

import {
  PublishNumberingDefinitionInputSchema,
  BootstrapNumberingCounterInputSchema,
  AllocateNumberInputSchema,
  ReserveNumberInputSchema,
  ConfirmNumberReservationInputSchema,
  ReleaseNumberReservationInputSchema,
  VoidNumberAllocationInputSchema,
  ConfigVersionSchema,
  parseNumberingCounter,
  parseNumberingAllocation,
  type PublishNumberingDefinitionInput,
  type BootstrapNumberingCounterInput,
  type AllocateNumberInput,
  type ReserveNumberInput,
  type ConfirmNumberReservationInput,
  type ReleaseNumberReservationInput,
  type VoidNumberAllocationInput,
  type NumberingCounter,
  type NumberingAllocation,
  type ConfigVersion,
} from "../contracts/numbering/numbering.ts";
import { parseConfigVersion } from "../contracts/config/config.ts";

export interface NumberingMutationRpcClient {
  rpc(
    fn:
      | "publish_numbering_definition"
      | "bootstrap_numbering_counter"
      | "allocate_number"
      | "reserve_number"
      | "confirm_number_reservation"
      | "release_number_reservation"
      | "void_number_allocation",
    args: Record<string, unknown>,
  ): Promise<{ data: unknown; error: { message: string } | null }>;
}

export const NUMBERING_KNOWN_MUTATION_ERROR_CODES = [
  "insufficient_authority",
  "numbering_missing_format",
  "numbering_invalid_seq_token_count",
  "numbering_unknown_token",
  "numbering_invalid_reset_period",
  "numbering_invalid_padding",
  "numbering_definition_not_found",
  "numbering_invalid_starting_seq",
  "numbering_counter_cannot_decrease",
  "numbering_definition_not_published",
  "numbering_allocation_not_found",
  "numbering_allocation_not_reserved",
  "numbering_allocation_not_allocated",
  "numbering_void_reason_required",
] as const;
type KnownNumberingMutationErrorCode = (typeof NUMBERING_KNOWN_MUTATION_ERROR_CODES)[number];
export type NumberingMutationErrorCode = KnownNumberingMutationErrorCode | "mutation_failed" | "invalid_response";

export class NumberingMutationError extends Error {
  readonly code: NumberingMutationErrorCode;

  constructor(code: NumberingMutationErrorCode, message: string) {
    super(message);
    this.name = "NumberingMutationError";
    this.code = code;
  }
}

function classifyError(message: string): NumberingMutationErrorCode {
  const prefix = message.split(":")[0]?.trim();
  return (NUMBERING_KNOWN_MUTATION_ERROR_CODES as readonly string[]).includes(prefix ?? "")
    ? (prefix as KnownNumberingMutationErrorCode)
    : "mutation_failed";
}

/** Runs the format-token structural validation gate (exactly one {SEQ} token, no unrecognized token, a real reset_period and padding), then supersedes the prior published definition. */
export async function publishNumberingDefinition(client: NumberingMutationRpcClient, input: PublishNumberingDefinitionInput): Promise<ConfigVersion> {
  const parsedInput = PublishNumberingDefinitionInputSchema.parse(input);
  const { data, error } = await client.rpc("publish_numbering_definition", {
    p_version_id: parsedInput.versionId,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_effective_from: parsedInput.effectiveFrom,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new NumberingMutationError(classifyError(error.message), error.message);
  }
  if (!data || typeof data !== "object") {
    throw new NumberingMutationError("invalid_response", "publish_numbering_definition returned no row");
  }
  return ConfigVersionSchema.parse(parseConfigVersion(data as Record<string, unknown>));
}

/** Seeds a counter's last-used value directly; structurally refuses to lower an existing counter (numbering_counter_cannot_decrease) -- never renumbers historical records. */
export async function bootstrapNumberingCounter(client: NumberingMutationRpcClient, input: BootstrapNumberingCounterInput): Promise<NumberingCounter> {
  const parsedInput = BootstrapNumberingCounterInputSchema.parse(input);
  const { data, error } = await client.rpc("bootstrap_numbering_counter", {
    p_config_version_id: parsedInput.configVersionId,
    p_scope_key: parsedInput.scopeKey,
    p_period_key: parsedInput.periodKey,
    p_starting_seq: parsedInput.startingSeq,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new NumberingMutationError(classifyError(error.message), error.message);
  }
  if (!data || typeof data !== "object") {
    throw new NumberingMutationError("invalid_response", "bootstrap_numbering_counter returned no row");
  }
  return parseNumberingCounter(data as Record<string, unknown>);
}

/** Idempotent on (tenantId, idempotencyKey). Atomically allocates the next seq and renders formatted_number immediately at status='allocated' -- the main flow. */
export async function allocateNumber(client: NumberingMutationRpcClient, input: AllocateNumberInput): Promise<NumberingAllocation> {
  const parsedInput = AllocateNumberInputSchema.parse(input);
  const { data, error } = await client.rpc("allocate_number", {
    p_config_version_id: parsedInput.configVersionId,
    p_tenant_id: parsedInput.tenantId,
    p_scope_key: parsedInput.scopeKey,
    p_entity_type: parsedInput.entityType,
    p_entity_id: parsedInput.entityId,
    p_idempotency_key: parsedInput.idempotencyKey,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_allocated_by: parsedInput.allocatedBy,
  });
  if (error) {
    throw new NumberingMutationError(classifyError(error.message), error.message);
  }
  if (!data || typeof data !== "object") {
    throw new NumberingMutationError("invalid_response", "allocate_number returned no row");
  }
  return parseNumberingAllocation(data as Record<string, unknown>);
}

/** Idempotent on (tenantId, idempotencyKey). Atomically allocates the next seq at status='reserved' -- the alternative reserve/confirm/release flow. The seq is consumed immediately and never reused, even if the reservation is later released. */
export async function reserveNumber(client: NumberingMutationRpcClient, input: ReserveNumberInput): Promise<NumberingAllocation> {
  const parsedInput = ReserveNumberInputSchema.parse(input);
  const { data, error } = await client.rpc("reserve_number", {
    p_config_version_id: parsedInput.configVersionId,
    p_tenant_id: parsedInput.tenantId,
    p_scope_key: parsedInput.scopeKey,
    p_entity_type: parsedInput.entityType,
    p_entity_id: parsedInput.entityId,
    p_idempotency_key: parsedInput.idempotencyKey,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_allocated_by: parsedInput.allocatedBy,
  });
  if (error) {
    throw new NumberingMutationError(classifyError(error.message), error.message);
  }
  if (!data || typeof data !== "object") {
    throw new NumberingMutationError("invalid_response", "reserve_number returned no row");
  }
  return parseNumberingAllocation(data as Record<string, unknown>);
}

/** reserved -> allocated. */
export async function confirmNumberReservation(client: NumberingMutationRpcClient, input: ConfirmNumberReservationInput): Promise<NumberingAllocation> {
  const parsedInput = ConfirmNumberReservationInputSchema.parse(input);
  const { data, error } = await client.rpc("confirm_number_reservation", {
    p_allocation_id: parsedInput.allocationId,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new NumberingMutationError(classifyError(error.message), error.message);
  }
  if (!data || typeof data !== "object") {
    throw new NumberingMutationError("invalid_response", "confirm_number_reservation returned no row");
  }
  return parseNumberingAllocation(data as Record<string, unknown>);
}

/** reserved -> released. The seq is never returned to the counter for reuse. */
export async function releaseNumberReservation(client: NumberingMutationRpcClient, input: ReleaseNumberReservationInput): Promise<NumberingAllocation> {
  const parsedInput = ReleaseNumberReservationInputSchema.parse(input);
  const { data, error } = await client.rpc("release_number_reservation", {
    p_allocation_id: parsedInput.allocationId,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
    p_reason: parsedInput.reason,
  });
  if (error) {
    throw new NumberingMutationError(classifyError(error.message), error.message);
  }
  if (!data || typeof data !== "object") {
    throw new NumberingMutationError("invalid_response", "release_number_reservation returned no row");
  }
  return parseNumberingAllocation(data as Record<string, unknown>);
}

/** allocated -> voided; requires a non-empty reason (Prompt 125 §24: not recycled unless an explicit audited rule). The seq is never returned to the counter for reuse. */
export async function voidNumberAllocation(client: NumberingMutationRpcClient, input: VoidNumberAllocationInput): Promise<NumberingAllocation> {
  const parsedInput = VoidNumberAllocationInputSchema.parse(input);
  const { data, error } = await client.rpc("void_number_allocation", {
    p_allocation_id: parsedInput.allocationId,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
    p_reason: parsedInput.reason,
  });
  if (error) {
    throw new NumberingMutationError(classifyError(error.message), error.message);
  }
  if (!data || typeof data !== "object") {
    throw new NumberingMutationError("invalid_response", "void_number_allocation returned no row");
  }
  return parseNumberingAllocation(data as Record<string, unknown>);
}
