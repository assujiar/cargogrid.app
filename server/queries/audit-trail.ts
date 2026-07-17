/**
 * Audit trail read queries (PLT-116, CG-S6-PLT-013). Thin, typed wrappers around
 * app.query_audit_logs / app.export_audit_logs
 * (supabase/migrations/20260716113048_create_audit_trail.sql). Both RPCs are
 * "queries" from the caller's perspective (they return audit rows) even though each
 * call also self-logs its own invocation internally -- the same "query" classification
 * PLT-112's evaluatePermission() already established for an RPC with an internal
 * side effect. Read-only (server/queries/, per
 * docs/architecture/04_REPOSITORY_TARGET_STRUCTURE.md §8) -- the actual write paths
 * (app.capture_audit_event, app.supreme_admin_mutate_audit_log,
 * app.supreme_admin_delete_audit_log) live in server/mutations/audit-trail.ts.
 */

import {
  QueryAuditLogsInputSchema,
  parseAuditLog,
  type AuditLog,
  type QueryAuditLogsInput,
} from "../contracts/audit-trail/audit-trail.ts";

export interface AuditTrailRpcClient {
  rpc(
    fn: "query_audit_logs" | "export_audit_logs",
    args: Record<string, unknown>,
  ): Promise<{ data: unknown; error: { message: string } | null }>;
}

export const AUDIT_TRAIL_KNOWN_ERROR_CODES = ["insufficient_authority"] as const;
type KnownAuditTrailErrorCode = (typeof AUDIT_TRAIL_KNOWN_ERROR_CODES)[number];
export type AuditTrailQueryErrorCode = KnownAuditTrailErrorCode | "query_failed";

export class AuditTrailQueryError extends Error {
  readonly code: AuditTrailQueryErrorCode;

  constructor(code: AuditTrailQueryErrorCode, message: string) {
    super(message);
    this.name = "AuditTrailQueryError";
    this.code = code;
  }
}

function classifyError(message: string): AuditTrailQueryErrorCode {
  const prefix = message.split(":")[0]?.trim();
  return (AUDIT_TRAIL_KNOWN_ERROR_CODES as readonly string[]).includes(prefix ?? "")
    ? (prefix as KnownAuditTrailErrorCode)
    : "query_failed";
}

async function callAndParseRows(
  client: AuditTrailRpcClient,
  fn: "query_audit_logs" | "export_audit_logs",
  parsedInput: QueryAuditLogsInput,
): Promise<AuditLog[]> {
  const { data, error } = await client.rpc(fn, {
    p_requester_auth_user_id: parsedInput.requesterAuthUserId,
    p_tenant_id: parsedInput.tenantId,
    p_limit: parsedInput.limit,
    p_before_occurred_at: parsedInput.beforeOccurredAt,
    p_before_id: parsedInput.beforeId,
  });

  if (error) {
    throw new AuditTrailQueryError(classifyError(error.message), error.message);
  }
  if (!Array.isArray(data)) {
    throw new AuditTrailQueryError("query_failed", `${fn} returned a non-array result`);
  }
  return data.map((row) => parseAuditLog(row as Record<string, unknown>));
}

/** Permission-aware, keyset-paginated audit read. Every call also self-logs its own invocation (Prompt 116 §26: "privileged access itself audited") -- a structural guarantee enforced inside app.query_audit_logs() itself, not by this wrapper. */
export async function queryAuditLogs(client: AuditTrailRpcClient, input: QueryAuditLogsInput): Promise<AuditLog[]> {
  const parsedInput = QueryAuditLogsInputSchema.parse(input);
  return callAndParseRows(client, "query_audit_logs", parsedInput);
}

/** Bulk audit export, otherwise identical to queryAuditLogs -- kept a distinct RPC/function so its own self-audit action label (export_audit_logs) is unambiguous evidence of which access pattern occurred. */
export async function exportAuditLogs(client: AuditTrailRpcClient, input: QueryAuditLogsInput): Promise<AuditLog[]> {
  const parsedInput = QueryAuditLogsInputSchema.parse(input);
  return callAndParseRows(client, "export_audit_logs", parsedInput);
}
