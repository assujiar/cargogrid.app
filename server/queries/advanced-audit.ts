/**
 * Advanced Audit and Impersonation read queries (IAE-029, Prompt 357). Thin,
 * typed wrappers around app.search_audit_logs /
 * app.list_audit_logs_for_support_session / app.get_audit_export
 * (supabase/migrations/20260807300000_create_intelligence_advanced_audit_impersonation.sql).
 */

import { parseAuditLog, parseAuditExportRequest, SearchAuditLogsInputSchema, type SearchAuditLogsInput, type AuditLog, type AuditExportRequest } from "../contracts/advanced-audit/advanced-audit.ts";

export interface AdvancedAuditQueryRpcClient {
  rpc(
    fn: "search_audit_logs" | "list_audit_logs_for_support_session" | "get_audit_export",
    args: Record<string, unknown>,
  ): Promise<{ data: unknown; error: { message: string } | null }>;
}

export class AdvancedAuditQueryError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "AdvancedAuditQueryError";
  }
}

function asRows(data: unknown): Record<string, unknown>[] {
  if (!data) {
    return [];
  }
  return Array.isArray(data) ? (data as Record<string, unknown>[]) : [data as Record<string, unknown>];
}

/** Authority: app.is_support_grant_authority (Supreme Admin or the tenant's own tenant_admin) -- the same authority app.query_audit_logs/app.export_audit_logs already require. */
export async function searchAuditLogs(client: AdvancedAuditQueryRpcClient, input: SearchAuditLogsInput): Promise<AuditLog[]> {
  const parsedInput = SearchAuditLogsInputSchema.parse(input);
  const { data, error } = await client.rpc("search_audit_logs", {
    p_requester_auth_user_id: parsedInput.requesterAuthUserId,
    p_tenant_id: parsedInput.tenantId,
    p_actor_auth_user_id_filter: parsedInput.actorAuthUserIdFilter,
    p_action_filter: parsedInput.actionFilter,
    p_resource_type_filter: parsedInput.resourceTypeFilter,
    p_result_filter: parsedInput.resultFilter,
    p_support_access_grant_id_filter: parsedInput.supportAccessGrantIdFilter,
    p_occurred_after: parsedInput.occurredAfter,
    p_occurred_before: parsedInput.occurredBefore,
    p_limit: parsedInput.limit,
  });
  if (error) {
    throw new AdvancedAuditQueryError(error.message);
  }
  return asRows(data).map(parseAuditLog);
}

/** Authority: same as searchAuditLogs. Chronological, oldest first -- the natural order for reviewing an impersonation/support session. */
export async function listAuditLogsForSupportSession(client: AdvancedAuditQueryRpcClient, requesterAuthUserId: string, grantId: string, limit = 200): Promise<AuditLog[]> {
  const { data, error } = await client.rpc("list_audit_logs_for_support_session", { p_requester_auth_user_id: requesterAuthUserId, p_grant_id: grantId, p_limit: limit });
  if (error) {
    throw new AdvancedAuditQueryError(error.message);
  }
  return asRows(data).map(parseAuditLog);
}

/** Lazily reports (never silently serves) a past-expiry ready export as expired, with its result_payload cleared. */
export async function getAuditExport(client: AdvancedAuditQueryRpcClient, requestId: string, actorAuthUserId: string): Promise<AuditExportRequest> {
  const { data, error } = await client.rpc("get_audit_export", { p_request_id: requestId, p_actor_auth_user_id: actorAuthUserId });
  if (error) {
    throw new AdvancedAuditQueryError(error.message);
  }
  if (!data || typeof data !== "object") {
    throw new AdvancedAuditQueryError("get_audit_export returned no row");
  }
  return parseAuditExportRequest(data as Record<string, unknown>);
}
