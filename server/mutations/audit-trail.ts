/**
 * Audit trail capture and Supreme Admin mutation primitives (PLT-116, CG-S6-PLT-013).
 * Thin, typed wrappers around app.capture_audit_event /
 * app.supreme_admin_mutate_audit_log / app.supreme_admin_delete_audit_log
 * (supabase/migrations/20260716113048_create_audit_trail.sql).
 */

import {
  CaptureAuditEventInputSchema,
  SupremeAdminDeleteAuditLogInputSchema,
  SupremeAdminMutateAuditLogInputSchema,
  parseAuditLog,
  type CaptureAuditEventInput,
  type SupremeAdminDeleteAuditLogInput,
  type SupremeAdminMutateAuditLogInput,
  type AuditLog,
} from "../contracts/audit-trail/audit-trail.ts";

type AuditRowRpcFn = "capture_audit_event" | "supreme_admin_mutate_audit_log";

export interface AuditTrailMutationRpcClient {
  rpc(
    fn: AuditRowRpcFn | "supreme_admin_delete_audit_log",
    args: Record<string, unknown>,
  ): Promise<{ data: unknown; error: { message: string } | null }>;
}

export const AUDIT_TRAIL_KNOWN_MUTATION_ERROR_CODES = [
  "insufficient_authority",
  "audit_log_not_found",
] as const;
type KnownAuditTrailMutationErrorCode = (typeof AUDIT_TRAIL_KNOWN_MUTATION_ERROR_CODES)[number];
export type AuditTrailMutationErrorCode = KnownAuditTrailMutationErrorCode | "mutation_failed" | "invalid_response";

export class AuditTrailMutationError extends Error {
  readonly code: AuditTrailMutationErrorCode;

  constructor(code: AuditTrailMutationErrorCode, message: string) {
    super(message);
    this.name = "AuditTrailMutationError";
    this.code = code;
  }
}

function classifyError(message: string): AuditTrailMutationErrorCode {
  const prefix = message.split(":")[0]?.trim();
  return (AUDIT_TRAIL_KNOWN_MUTATION_ERROR_CODES as readonly string[]).includes(prefix ?? "")
    ? (prefix as KnownAuditTrailMutationErrorCode)
    : "mutation_failed";
}

async function callAndParseRow(
  client: AuditTrailMutationRpcClient,
  fn: AuditRowRpcFn,
  args: Record<string, unknown>,
): Promise<AuditLog> {
  const { data, error } = await client.rpc(fn, args);

  if (error) {
    throw new AuditTrailMutationError(classifyError(error.message), error.message);
  }
  if (!data || typeof data !== "object") {
    throw new AuditTrailMutationError("invalid_response", `${fn} returned no row`);
  }
  return parseAuditLog(data as Record<string, unknown>);
}

/** The canonical audit-capture primitive. Every call is a genuinely new, distinct event -- deliberately not idempotent (see the migration's own header comment). before/after values are redacted server-side regardless of what the caller passes. */
export async function captureAuditEvent(client: AuditTrailMutationRpcClient, input: CaptureAuditEventInput): Promise<AuditLog> {
  const parsedInput = CaptureAuditEventInputSchema.parse(input);
  return callAndParseRow(client, "capture_audit_event", {
    p_tenant_id: parsedInput.tenantId,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
    p_action: parsedInput.action,
    p_resource_type: parsedInput.resourceType,
    p_resource_id: parsedInput.resourceId,
    p_result: parsedInput.result,
    p_reason: parsedInput.reason,
    p_before_value: parsedInput.beforeValue,
    p_after_value: parsedInput.afterValue,
    p_correlation_id: parsedInput.correlationId,
  });
}

/** RPD-022's disclosed absolute-CRUD exception, made concrete: only Supreme Admin may mutate an existing audit_logs row, and the mutation is itself immediately captured with before/after values (docs/architecture/06_RLS_RBAC_WORKSTREAM.md §10 test #9). */
export async function supremeAdminMutateAuditLog(
  client: AuditTrailMutationRpcClient,
  input: SupremeAdminMutateAuditLogInput,
): Promise<AuditLog> {
  const parsedInput = SupremeAdminMutateAuditLogInputSchema.parse(input);
  return callAndParseRow(client, "supreme_admin_mutate_audit_log", {
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_target_id: parsedInput.targetId,
    p_new_reason: parsedInput.newReason,
    p_new_legal_hold: parsedInput.newLegalHold,
    p_new_legal_hold_reason: parsedInput.newLegalHoldReason,
    p_mutation_reason: parsedInput.mutationReason,
  });
}

/** RPD-022's disclosed absolute-CRUD exception, delete case: only Supreme Admin may delete an audit_logs row; the deletion is itself captured, preserving the before-image. Returns void (the target row and its own deletion-audit row are two separate app.audit_logs concerns). */
export async function supremeAdminDeleteAuditLog(
  client: AuditTrailMutationRpcClient,
  input: SupremeAdminDeleteAuditLogInput,
): Promise<void> {
  const parsedInput = SupremeAdminDeleteAuditLogInputSchema.parse(input);
  const { error } = await client.rpc("supreme_admin_delete_audit_log", {
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_target_id: parsedInput.targetId,
    p_reason: parsedInput.reason,
  });

  if (error) {
    throw new AuditTrailMutationError(classifyError(error.message), error.message);
  }
}
