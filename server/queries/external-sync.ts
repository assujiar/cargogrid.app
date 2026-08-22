/**
 * External Accounting and HR Integrations queries (IAE-018, Prompt 346).
 * Thin, typed wrappers around app.list_external_sync_records_for_tenant /
 * app.get_external_sync_connection_for_sync / app.get_external_sync_credential
 * (supabase/migrations/20260805050000_create_intelligence_external_accounting_hr_integrations.sql).
 */

import {
  ListExternalSyncRecordsForTenantInputSchema,
  parseExternalSyncRecord,
  parseExternalSyncConnectionForSync,
  type ListExternalSyncRecordsForTenantInput,
  type ExternalSyncRecord,
  type ExternalSyncConnectionForSync,
} from "../contracts/external-sync/external-sync.ts";

export interface ExternalSyncQueryRpcClient {
  rpc(
    fn: "list_external_sync_records_for_tenant" | "get_external_sync_connection_for_sync" | "get_external_sync_credential",
    args: Record<string, unknown>,
  ): Promise<{ data: unknown; error: { message: string } | null }>;
}

export class ExternalSyncQueryError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "ExternalSyncQueryError";
  }
}

/** Authority: entity-type-dispatched View (HRS:View for employee, FIN:View for gl_account; either when entityType is omitted). */
export async function listExternalSyncRecordsForTenant(client: ExternalSyncQueryRpcClient, input: ListExternalSyncRecordsForTenantInput): Promise<ExternalSyncRecord[]> {
  const parsedInput = ListExternalSyncRecordsForTenantInputSchema.parse(input);
  const { data, error } = await client.rpc("list_external_sync_records_for_tenant", {
    p_tenant_id: parsedInput.tenantId,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_entity_type: parsedInput.entityType,
    p_conflict_status: parsedInput.conflictStatus,
    p_limit: parsedInput.limit,
  });
  if (error) {
    throw new ExternalSyncQueryError(error.message);
  }
  if (!Array.isArray(data)) {
    throw new ExternalSyncQueryError("list_external_sync_records_for_tenant returned a non-array result");
  }
  return data.map((row) => parseExternalSyncRecord(row as Record<string, unknown>));
}

/** The real poll worker's own read -- no actor authority check (an already-authorized background job). Returns null if the connection does not exist. */
export async function getExternalSyncConnectionForSync(client: ExternalSyncQueryRpcClient, connectionId: string): Promise<ExternalSyncConnectionForSync | null> {
  const { data, error } = await client.rpc("get_external_sync_connection_for_sync", { p_connection_id: connectionId });
  if (error) {
    throw new ExternalSyncQueryError(error.message);
  }
  const row = Array.isArray(data) ? data[0] : data;
  if (!row || typeof row !== "object") {
    return null;
  }
  return parseExternalSyncConnectionForSync(row as Record<string, unknown>);
}

/** service_role-only. Returns null if the connection has no stored credential. */
export async function getExternalSyncCredential(client: ExternalSyncQueryRpcClient, connectionId: string): Promise<string | null> {
  const { data, error } = await client.rpc("get_external_sync_credential", { p_connection_id: connectionId });
  if (error) {
    throw new ExternalSyncQueryError(error.message);
  }
  return typeof data === "string" ? data : null;
}
