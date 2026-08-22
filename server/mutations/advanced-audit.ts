/**
 * Advanced Audit and Impersonation mutation primitives (IAE-029, Prompt 357).
 * Thin, typed wrappers around app.request_audit_export /
 * app.record_audit_export_outcome
 * (supabase/migrations/20260807300000_create_intelligence_advanced_audit_impersonation.sql).
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import {
  RequestAuditExportInputSchema,
  RecordAuditExportOutcomeInputSchema,
  parseAuditExportRequest,
  type RequestAuditExportInput,
  type RecordAuditExportOutcomeInput,
  type AuditExportRequest,
} from "../contracts/advanced-audit/advanced-audit.ts";

export type AdvancedAuditMutationRpcClient = Pick<SupabaseClient, "rpc">;

export const ADVANCED_AUDIT_KNOWN_MUTATION_ERROR_CODES = [
  "insufficient_authority",
  "audit_export_unsafe_filters",
  "audit_export_invalid_outcome_status",
  "audit_export_request_not_found",
  "audit_export_outcome_already_recorded",
] as const;
type KnownAdvancedAuditMutationErrorCode = (typeof ADVANCED_AUDIT_KNOWN_MUTATION_ERROR_CODES)[number];
export type AdvancedAuditMutationErrorCode = KnownAdvancedAuditMutationErrorCode | "mutation_failed" | "invalid_response";

export class AdvancedAuditMutationError extends Error {
  readonly code: AdvancedAuditMutationErrorCode;

  constructor(code: AdvancedAuditMutationErrorCode, message: string) {
    super(message);
    this.name = "AdvancedAuditMutationError";
    this.code = code;
  }
}

function classifyError(message: string): AdvancedAuditMutationErrorCode {
  const prefix = message.split(":")[0]?.trim();
  return (ADVANCED_AUDIT_KNOWN_MUTATION_ERROR_CODES as readonly string[]).includes(prefix ?? "")
    ? (prefix as KnownAdvancedAuditMutationErrorCode)
    : "mutation_failed";
}

export async function requestAuditExport(client: AdvancedAuditMutationRpcClient, input: RequestAuditExportInput): Promise<AuditExportRequest> {
  const parsedInput = RequestAuditExportInputSchema.parse(input);
  const { data, error } = await client.rpc("request_audit_export", {
    p_tenant_id: parsedInput.tenantId,
    p_filters: parsedInput.filters,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new AdvancedAuditMutationError(classifyError(error.message), error.message);
  }
  if (!data || typeof data !== "object") {
    throw new AdvancedAuditMutationError("invalid_response", "request_audit_export returned no row");
  }
  return parseAuditExportRequest(data as Record<string, unknown>);
}

/** service_role-only -- called by the (disclosed, not yet built) audit-export job worker, never directly from a live end-user session. */
export async function recordAuditExportOutcome(client: AdvancedAuditMutationRpcClient, input: RecordAuditExportOutcomeInput): Promise<AuditExportRequest> {
  const parsedInput = RecordAuditExportOutcomeInputSchema.parse(input);
  const { data, error } = await client.rpc("record_audit_export_outcome", {
    p_request_id: parsedInput.requestId,
    p_status: parsedInput.status,
    p_result_row_count: parsedInput.resultRowCount,
    p_result_payload: parsedInput.resultPayload,
    p_failure_reason: parsedInput.failureReason,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new AdvancedAuditMutationError(classifyError(error.message), error.message);
  }
  if (!data || typeof data !== "object") {
    throw new AdvancedAuditMutationError("invalid_response", "record_audit_export_outcome returned no row");
  }
  return parseAuditExportRequest(data as Record<string, unknown>);
}
