/**
 * Status engine mutation primitives (PLT-124, CG-S6-PLT-021). Thin, typed wrappers
 * around app.register_status_set / app.register_canonical_status /
 * app.register_status_legacy_mapping / app.publish_status_presentation
 * (supabase/migrations/20260719100000_create_status_engine.sql). All
 * service_role-only (see the migration's own grant comment).
 */

import {
  RegisterStatusSetInputSchema,
  RegisterCanonicalStatusInputSchema,
  RegisterStatusLegacyMappingInputSchema,
  PublishStatusPresentationInputSchema,
  ConfigVersionSchema,
  parseStatusSet,
  parseCanonicalStatus,
  parseStatusLegacyMapping,
  type RegisterStatusSetInput,
  type RegisterCanonicalStatusInput,
  type RegisterStatusLegacyMappingInput,
  type PublishStatusPresentationInput,
  type StatusSet,
  type CanonicalStatus,
  type StatusLegacyMapping,
  type ConfigVersion,
} from "../contracts/status/status.ts";
import { parseConfigVersion } from "../contracts/config/config.ts";

export interface StatusMutationRpcClient {
  rpc(
    fn:
      | "register_status_set"
      | "register_canonical_status"
      | "register_status_legacy_mapping"
      | "publish_status_presentation",
    args: Record<string, unknown>,
  ): Promise<{ data: unknown; error: { message: string } | null }>;
}

export const STATUS_KNOWN_MUTATION_ERROR_CODES = [
  "insufficient_authority",
  "status_set_not_found",
  "status_invalid_category",
  "status_unknown_code",
  "status_legacy_mapping_collision",
  "status_not_a_presentation_version",
  "status_missing_labels",
  "status_missing_label",
  "status_missing_accessible_cue",
  "status_invalid_color",
] as const;
type KnownStatusMutationErrorCode = (typeof STATUS_KNOWN_MUTATION_ERROR_CODES)[number];
export type StatusMutationErrorCode = KnownStatusMutationErrorCode | "mutation_failed" | "invalid_response";

export class StatusMutationError extends Error {
  readonly code: StatusMutationErrorCode;

  constructor(code: StatusMutationErrorCode, message: string) {
    super(message);
    this.name = "StatusMutationError";
    this.code = code;
  }
}

function classifyError(message: string): StatusMutationErrorCode {
  const prefix = message.split(":")[0]?.trim();
  return (STATUS_KNOWN_MUTATION_ERROR_CODES as readonly string[]).includes(prefix ?? "")
    ? (prefix as KnownStatusMutationErrorCode)
    : "mutation_failed";
}

/** Idempotent -- Supreme-Admin-only. Also mints a dedicated status:<code> config_type (this migration's own header explains why one shared type cannot host every set's independent tenant presentation). */
export async function registerStatusSet(client: StatusMutationRpcClient, input: RegisterStatusSetInput): Promise<StatusSet> {
  const parsedInput = RegisterStatusSetInputSchema.parse(input);
  const { data, error } = await client.rpc("register_status_set", {
    p_code: parsedInput.code,
    p_name: parsedInput.name,
    p_owner_primitive_code: parsedInput.ownerPrimitiveCode,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_registered_by: parsedInput.registeredBy,
  });
  if (error) {
    throw new StatusMutationError(classifyError(error.message), error.message);
  }
  if (!data || typeof data !== "object") {
    throw new StatusMutationError("invalid_response", "register_status_set returned no row");
  }
  return parseStatusSet(data as Record<string, unknown>);
}

/** Idempotent -- Supreme-Admin-only. Canonical status meaning is permanent once registered (this migration's own header). */
export async function registerCanonicalStatus(client: StatusMutationRpcClient, input: RegisterCanonicalStatusInput): Promise<CanonicalStatus> {
  const parsedInput = RegisterCanonicalStatusInputSchema.parse(input);
  const { data, error } = await client.rpc("register_canonical_status", {
    p_status_set_code: parsedInput.statusSetCode,
    p_code: parsedInput.code,
    p_category: parsedInput.category,
    p_sort_order: parsedInput.sortOrder,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_registered_by: parsedInput.registeredBy,
  });
  if (error) {
    throw new StatusMutationError(classifyError(error.message), error.message);
  }
  if (!data || typeof data !== "object") {
    throw new StatusMutationError("invalid_response", "register_canonical_status returned no row");
  }
  return parseCanonicalStatus(data as Record<string, unknown>);
}

/** Idempotent for a repeat of the same mapping; raises status_legacy_mapping_collision if the legacy value is already mapped to a different canonical status. */
export async function registerStatusLegacyMapping(client: StatusMutationRpcClient, input: RegisterStatusLegacyMappingInput): Promise<StatusLegacyMapping> {
  const parsedInput = RegisterStatusLegacyMappingInputSchema.parse(input);
  const { data, error } = await client.rpc("register_status_legacy_mapping", {
    p_status_set_code: parsedInput.statusSetCode,
    p_legacy_value: parsedInput.legacyValue,
    p_canonical_status_code: parsedInput.canonicalStatusCode,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_registered_by: parsedInput.registeredBy,
  });
  if (error) {
    throw new StatusMutationError(classifyError(error.message), error.message);
  }
  if (!data || typeof data !== "object") {
    throw new StatusMutationError("invalid_response", "register_status_legacy_mapping returned no row");
  }
  return parseStatusLegacyMapping(data as Record<string, unknown>);
}

/** Runs the structural validation gate (every labeled code registered, every entry has a label and an accessible icon cue, any color is a real hex value), then supersedes the prior published presentation (PLT-121's app.publish_config_version() composed underneath). */
export async function publishStatusPresentation(client: StatusMutationRpcClient, input: PublishStatusPresentationInput): Promise<ConfigVersion> {
  const parsedInput = PublishStatusPresentationInputSchema.parse(input);
  const { data, error } = await client.rpc("publish_status_presentation", {
    p_version_id: parsedInput.versionId,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_effective_from: parsedInput.effectiveFrom,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new StatusMutationError(classifyError(error.message), error.message);
  }
  if (!data || typeof data !== "object") {
    throw new StatusMutationError("invalid_response", "publish_status_presentation returned no row");
  }
  return ConfigVersionSchema.parse(parseConfigVersion(data as Record<string, unknown>));
}
