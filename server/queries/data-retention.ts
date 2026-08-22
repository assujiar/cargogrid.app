/**
 * Data Retention and Archival read queries (IAE-031, Prompt 359). Thin,
 * typed wrappers around app.resolve_retention_days /
 * app.list_retention_policies_for_tenant / app.list_legal_holds_for_tenant /
 * app.get_retention_archive_request / app.list_retention_archive_requests_for_tenant
 * (supabase/migrations/20260807500000_create_intelligence_data_retention_archival.sql).
 */

import { parseRetentionPolicy, parseLegalHold, parseRetentionArchiveRequest, type RetentionPolicy, type LegalHold, type RetentionArchiveRequest, type RetentionRecordClass } from "../contracts/data-retention/data-retention.ts";

export interface DataRetentionQueryRpcClient {
  rpc(
    fn:
      | "resolve_retention_days"
      | "list_retention_policies_for_tenant"
      | "list_legal_holds_for_tenant"
      | "get_retention_archive_request"
      | "list_retention_archive_requests_for_tenant",
    args: Record<string, unknown>,
  ): Promise<{ data: unknown; error: { message: string } | null }>;
}

export class DataRetentionQueryError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "DataRetentionQueryError";
  }
}

function asRows(data: unknown): Record<string, unknown>[] {
  if (!data) {
    return [];
  }
  return Array.isArray(data) ? (data as Record<string, unknown>[]) : [data as Record<string, unknown>];
}

/** service_role-only -- takes no actor/authority parameter of its own by design (see app.is_high_risk_action's own comment for the identical shape); call with a trusted server-side client, never an end-user session client. Resolves the applicable retention-days schedule (tenant override, then platform override, then RPD-025's own hardcoded default). */
export async function resolveRetentionDays(client: DataRetentionQueryRpcClient, tenantId: string | null, recordClass: RetentionRecordClass): Promise<number> {
  const { data, error } = await client.rpc("resolve_retention_days", { p_tenant_id: tenantId, p_record_class: recordClass });
  if (error) {
    throw new DataRetentionQueryError(error.message);
  }
  if (typeof data !== "number") {
    throw new DataRetentionQueryError("resolve_retention_days returned a non-numeric result");
  }
  return data;
}

/** Authority: RET:View. */
export async function listRetentionPolicies(client: DataRetentionQueryRpcClient, tenantId: string, actorAuthUserId: string): Promise<RetentionPolicy[]> {
  const { data, error } = await client.rpc("list_retention_policies_for_tenant", { p_tenant_id: tenantId, p_actor_auth_user_id: actorAuthUserId });
  if (error) {
    throw new DataRetentionQueryError(error.message);
  }
  return asRows(data).map(parseRetentionPolicy);
}

/** Authority: RET:View. */
export async function listLegalHolds(client: DataRetentionQueryRpcClient, tenantId: string, actorAuthUserId: string): Promise<LegalHold[]> {
  const { data, error } = await client.rpc("list_legal_holds_for_tenant", { p_tenant_id: tenantId, p_actor_auth_user_id: actorAuthUserId });
  if (error) {
    throw new DataRetentionQueryError(error.message);
  }
  return asRows(data).map(parseLegalHold);
}

/** Authority: RET:View against the request's own tenant. */
export async function getRetentionArchiveRequest(client: DataRetentionQueryRpcClient, requestId: string, actorAuthUserId: string): Promise<RetentionArchiveRequest> {
  const { data, error } = await client.rpc("get_retention_archive_request", { p_request_id: requestId, p_actor_auth_user_id: actorAuthUserId });
  if (error) {
    throw new DataRetentionQueryError(error.message);
  }
  if (!data || typeof data !== "object") {
    throw new DataRetentionQueryError("get_retention_archive_request returned no row");
  }
  return parseRetentionArchiveRequest(data as Record<string, unknown>);
}

/** Authority: RET:View. */
export async function listRetentionArchiveRequests(client: DataRetentionQueryRpcClient, tenantId: string, actorAuthUserId: string): Promise<RetentionArchiveRequest[]> {
  const { data, error } = await client.rpc("list_retention_archive_requests_for_tenant", { p_tenant_id: tenantId, p_actor_auth_user_id: actorAuthUserId });
  if (error) {
    throw new DataRetentionQueryError(error.message);
  }
  return asRows(data).map(parseRetentionArchiveRequest);
}
