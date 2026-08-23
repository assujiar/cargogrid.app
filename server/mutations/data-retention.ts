/**
 * Data Retention and Archival mutation primitives (IAE-031, Prompt 359).
 * Thin, typed wrappers around app.set_retention_policy /
 * app.request_legal_hold / app.release_legal_hold /
 * app.request_retention_archive / app.record_retention_archive_outcome
 * (supabase/migrations/20260807500000_create_intelligence_data_retention_archival.sql).
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import {
  SetRetentionPolicyInputSchema,
  RequestLegalHoldInputSchema,
  ReleaseLegalHoldInputSchema,
  RequestRetentionArchiveInputSchema,
  RecordRetentionArchiveOutcomeInputSchema,
  parseRetentionPolicy,
  parseLegalHold,
  parseRetentionArchiveRequest,
  type SetRetentionPolicyInput,
  type RequestLegalHoldInput,
  type ReleaseLegalHoldInput,
  type RequestRetentionArchiveInput,
  type RecordRetentionArchiveOutcomeInput,
  type RetentionPolicy,
  type LegalHold,
  type RetentionArchiveRequest,
} from "../contracts/data-retention/data-retention.ts";

export type DataRetentionMutationRpcClient = Pick<SupabaseClient, "rpc">;

export const DATA_RETENTION_KNOWN_MUTATION_ERROR_CODES = [
  "insufficient_authority",
  "retention_invalid_record_class",
  "retention_invalid_days",
  "legal_hold_reason_required",
  "legal_hold_invalid_scope",
  "legal_hold_not_active",
  "retention_source_table_required",
  "retention_archive_invalid_outcome_status",
  "retention_archive_request_not_found",
  "retention_archive_outcome_already_recorded",
] as const;
type KnownDataRetentionMutationErrorCode = (typeof DATA_RETENTION_KNOWN_MUTATION_ERROR_CODES)[number];
export type DataRetentionMutationErrorCode = KnownDataRetentionMutationErrorCode | "mutation_failed" | "invalid_response";

export class DataRetentionMutationError extends Error {
  readonly code: DataRetentionMutationErrorCode;

  constructor(code: DataRetentionMutationErrorCode, message: string) {
    super(message);
    this.name = "DataRetentionMutationError";
    this.code = code;
  }
}

function classifyError(message: string): DataRetentionMutationErrorCode {
  const prefix = message.split(":")[0]?.trim();
  return (DATA_RETENTION_KNOWN_MUTATION_ERROR_CODES as readonly string[]).includes(prefix ?? "")
    ? (prefix as KnownDataRetentionMutationErrorCode)
    : "mutation_failed";
}

export async function setRetentionPolicy(client: DataRetentionMutationRpcClient, input: SetRetentionPolicyInput): Promise<RetentionPolicy> {
  const parsedInput = SetRetentionPolicyInputSchema.parse(input);
  const { data, error } = await client.rpc("set_retention_policy", {
    p_tenant_id: parsedInput.tenantId,
    p_record_class: parsedInput.recordClass,
    p_retention_days: parsedInput.retentionDays,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new DataRetentionMutationError(classifyError(error.message), error.message);
  }
  if (!data || typeof data !== "object") {
    throw new DataRetentionMutationError("invalid_response", "set_retention_policy returned no row");
  }
  return parseRetentionPolicy(data as Record<string, unknown>);
}

export async function requestLegalHold(client: DataRetentionMutationRpcClient, input: RequestLegalHoldInput): Promise<LegalHold> {
  const parsedInput = RequestLegalHoldInputSchema.parse(input);
  const { data, error } = await client.rpc("request_legal_hold", {
    p_tenant_id: parsedInput.tenantId,
    p_record_class: parsedInput.recordClass,
    p_scope_record_table: parsedInput.scopeRecordTable,
    p_scope_record_id: parsedInput.scopeRecordId,
    p_reason: parsedInput.reason,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new DataRetentionMutationError(classifyError(error.message), error.message);
  }
  if (!data || typeof data !== "object") {
    throw new DataRetentionMutationError("invalid_response", "request_legal_hold returned no row");
  }
  return parseLegalHold(data as Record<string, unknown>);
}

/** Authority: RET:Approve -- a higher bar than placing a hold (RET:Configure), since releasing is what allows deletion/archive to proceed. */
export async function releaseLegalHold(client: DataRetentionMutationRpcClient, input: ReleaseLegalHoldInput): Promise<LegalHold> {
  const parsedInput = ReleaseLegalHoldInputSchema.parse(input);
  const { data, error } = await client.rpc("release_legal_hold", {
    p_hold_id: parsedInput.holdId,
    p_release_reason: parsedInput.releaseReason,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new DataRetentionMutationError(classifyError(error.message), error.message);
  }
  if (!data || typeof data !== "object") {
    throw new DataRetentionMutationError("invalid_response", "release_legal_hold returned no row");
  }
  return parseLegalHold(data as Record<string, unknown>);
}

/** dryRun=true never enqueues a job -- classification only. dryRun=false is rejected (blocked_within_retention/blocked_legal_hold), not enqueued, when the record has not reached its own retention floor or is under an active legal hold. */
export async function requestRetentionArchive(client: DataRetentionMutationRpcClient, input: RequestRetentionArchiveInput): Promise<RetentionArchiveRequest> {
  const parsedInput = RequestRetentionArchiveInputSchema.parse(input);
  const { data, error } = await client.rpc("request_retention_archive", {
    p_tenant_id: parsedInput.tenantId,
    p_record_class: parsedInput.recordClass,
    p_source_table: parsedInput.sourceTable,
    p_source_record_id: parsedInput.sourceRecordId,
    p_record_reference_date: parsedInput.recordReferenceDate,
    p_dry_run: parsedInput.dryRun,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new DataRetentionMutationError(classifyError(error.message), error.message);
  }
  if (!data || typeof data !== "object") {
    throw new DataRetentionMutationError("invalid_response", "request_retention_archive returned no row");
  }
  return parseRetentionArchiveRequest(data as Record<string, unknown>);
}

/** service_role-only -- called by the (disclosed, not yet built) retention-archive job worker, never directly from a live end-user session. */
export async function recordRetentionArchiveOutcome(client: DataRetentionMutationRpcClient, input: RecordRetentionArchiveOutcomeInput): Promise<RetentionArchiveRequest> {
  const parsedInput = RecordRetentionArchiveOutcomeInputSchema.parse(input);
  const { data, error } = await client.rpc("record_retention_archive_outcome", {
    p_request_id: parsedInput.requestId,
    p_status: parsedInput.status,
    p_result_note: parsedInput.resultNote,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new DataRetentionMutationError(classifyError(error.message), error.message);
  }
  if (!data || typeof data !== "object") {
    throw new DataRetentionMutationError("invalid_response", "record_retention_archive_outcome returned no row");
  }
  return parseRetentionArchiveRequest(data as Record<string, unknown>);
}
