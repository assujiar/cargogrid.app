/**
 * External Accounting and HR Integrations mutation primitives (IAE-018,
 * Prompt 346). Thin, typed wrappers around
 * app.set_external_sync_entity_mapping / app.link_external_sync_entity /
 * app.record_external_sync_snapshot / app.review_external_sync_conflict /
 * app.trigger_external_sync
 * (supabase/migrations/20260805050000_create_intelligence_external_accounting_hr_integrations.sql).
 */

import {
  SetExternalSyncEntityMappingInputSchema,
  parseExternalSyncEntityMapping,
  LinkExternalSyncEntityInputSchema,
  parseExternalSyncEntityLink,
  RecordExternalSyncSnapshotInputSchema,
  parseExternalSyncRecord,
  ReviewExternalSyncConflictInputSchema,
  TriggerExternalSyncInputSchema,
  type SetExternalSyncEntityMappingInput,
  type ExternalSyncEntityMapping,
  type LinkExternalSyncEntityInput,
  type ExternalSyncEntityLink,
  type RecordExternalSyncSnapshotInput,
  type ExternalSyncRecord,
  type ReviewExternalSyncConflictInput,
  type TriggerExternalSyncInput,
} from "../contracts/external-sync/external-sync.ts";

export interface ExternalSyncMutationRpcClient {
  rpc(
    fn:
      | "set_external_sync_entity_mapping"
      | "link_external_sync_entity"
      | "record_external_sync_snapshot"
      | "review_external_sync_conflict"
      | "trigger_external_sync",
    args: Record<string, unknown>,
  ): Promise<{ data: unknown; error: { message: string } | null }>;
}

export const EXTERNAL_SYNC_KNOWN_MUTATION_ERROR_CODES = [
  "insufficient_authority",
  "external_sync_invalid_adapter_code",
  "external_sync_invalid_entity_type",
  "external_sync_invalid_ownership_direction",
  "external_sync_mapping_not_configured",
  "external_sync_internal_record_not_found",
  "external_sync_record_not_found",
  "external_sync_invalid_decision",
  "external_sync_invalid_conflict_status",
  "external_sync_invalid_limit",
  "external_sync_connection_not_found",
  "external_sync_connection_not_active",
] as const;
type KnownExternalSyncMutationErrorCode = (typeof EXTERNAL_SYNC_KNOWN_MUTATION_ERROR_CODES)[number];
export type ExternalSyncMutationErrorCode = KnownExternalSyncMutationErrorCode | "mutation_failed" | "invalid_response";

export class ExternalSyncMutationError extends Error {
  readonly code: ExternalSyncMutationErrorCode;

  constructor(code: ExternalSyncMutationErrorCode, message: string) {
    super(message);
    this.name = "ExternalSyncMutationError";
    this.code = code;
  }
}

function classifyError(message: string): ExternalSyncMutationErrorCode {
  const prefix = message.split(":")[0]?.trim();
  return (EXTERNAL_SYNC_KNOWN_MUTATION_ERROR_CODES as readonly string[]).includes(prefix ?? "") ? (prefix as KnownExternalSyncMutationErrorCode) : "mutation_failed";
}

/** INTHUB:Configure-gated. Makes "CargoGrid source-domain ownership must be explicit before sync" a hard gate -- idempotent upsert. */
export async function setExternalSyncEntityMapping(client: ExternalSyncMutationRpcClient, input: SetExternalSyncEntityMappingInput): Promise<ExternalSyncEntityMapping> {
  const parsedInput = SetExternalSyncEntityMappingInputSchema.parse(input);
  const { data, error } = await client.rpc("set_external_sync_entity_mapping", {
    p_tenant_id: parsedInput.tenantId,
    p_adapter_code: parsedInput.adapterCode,
    p_entity_type: parsedInput.entityType,
    p_ownership_direction: parsedInput.ownershipDirection,
    p_notes: parsedInput.notes,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new ExternalSyncMutationError(classifyError(error.message), error.message);
  }
  if (!data || typeof data !== "object") {
    throw new ExternalSyncMutationError("invalid_response", "set_external_sync_entity_mapping returned no row");
  }
  return parseExternalSyncEntityMapping(data as Record<string, unknown>);
}

/** Explicit, human-driven linking only -- never a best-effort auto-match (design decision 4). */
export async function linkExternalSyncEntity(client: ExternalSyncMutationRpcClient, input: LinkExternalSyncEntityInput): Promise<ExternalSyncEntityLink> {
  const parsedInput = LinkExternalSyncEntityInputSchema.parse(input);
  const { data, error } = await client.rpc("link_external_sync_entity", {
    p_tenant_id: parsedInput.tenantId,
    p_adapter_code: parsedInput.adapterCode,
    p_entity_type: parsedInput.entityType,
    p_external_entity_id: parsedInput.externalEntityId,
    p_internal_record_id: parsedInput.internalRecordId,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new ExternalSyncMutationError(classifyError(error.message), error.message);
  }
  if (!data || typeof data !== "object") {
    throw new ExternalSyncMutationError("invalid_response", "link_external_sync_entity returned no row");
  }
  return parseExternalSyncEntityLink(data as Record<string, unknown>);
}

/** Never writes to app.employees/app.finance_accounts -- read-only evidence + diff only (design decision 3). */
export async function recordExternalSyncSnapshot(client: ExternalSyncMutationRpcClient, input: RecordExternalSyncSnapshotInput): Promise<ExternalSyncRecord> {
  const parsedInput = RecordExternalSyncSnapshotInputSchema.parse(input);
  const { data, error } = await client.rpc("record_external_sync_snapshot", {
    p_tenant_id: parsedInput.tenantId,
    p_connection_id: parsedInput.connectionId,
    p_adapter_code: parsedInput.adapterCode,
    p_entity_type: parsedInput.entityType,
    p_external_entity_id: parsedInput.externalEntityId,
    p_raw_payload: parsedInput.rawPayload,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new ExternalSyncMutationError(classifyError(error.message), error.message);
  }
  if (!data || typeof data !== "object") {
    throw new ExternalSyncMutationError("invalid_response", "record_external_sync_snapshot returned no row");
  }
  return parseExternalSyncRecord(data as Record<string, unknown>);
}

/** Evidence-only -- never writes to app.employees/app.finance_accounts. */
export async function reviewExternalSyncConflict(client: ExternalSyncMutationRpcClient, input: ReviewExternalSyncConflictInput): Promise<ExternalSyncRecord> {
  const parsedInput = ReviewExternalSyncConflictInputSchema.parse(input);
  const { data, error } = await client.rpc("review_external_sync_conflict", {
    p_record_id: parsedInput.recordId,
    p_decision: parsedInput.decision,
    p_notes: parsedInput.notes,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new ExternalSyncMutationError(classifyError(error.message), error.message);
  }
  if (!data || typeof data !== "object") {
    throw new ExternalSyncMutationError("invalid_response", "review_external_sync_conflict returned no row");
  }
  return parseExternalSyncRecord(data as Record<string, unknown>);
}

export interface TriggerExternalSyncResult {
  readonly jobId: string;
}

/** The real third caller of app.check_integration_connection_active (IAE-336), after IAE-016 and IAE-017. */
export async function triggerExternalSync(client: ExternalSyncMutationRpcClient, input: TriggerExternalSyncInput): Promise<TriggerExternalSyncResult> {
  const parsedInput = TriggerExternalSyncInputSchema.parse(input);
  const { data, error } = await client.rpc("trigger_external_sync", {
    p_tenant_id: parsedInput.tenantId,
    p_connection_id: parsedInput.connectionId,
    p_entity_type: parsedInput.entityType,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new ExternalSyncMutationError(classifyError(error.message), error.message);
  }
  const row = data as Record<string, unknown> | null;
  if (!row || typeof row.job_id !== "string") {
    throw new ExternalSyncMutationError("invalid_response", "trigger_external_sync returned no row");
  }
  return { jobId: row.job_id };
}
