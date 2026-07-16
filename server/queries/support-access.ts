/**
 * Support access read queries (PLT-115, CG-S6-PLT-012). Thin, typed wrappers around
 * app.has_active_support_grant / app.current_support_session
 * (supabase/migrations/20260716111315_create_support_access.sql). Read-only
 * (server/queries/, per docs/architecture/04_REPOSITORY_TARGET_STRUCTURE.md §8) --
 * grant/session lifecycle mutations live in server/mutations/support-access.ts.
 */

import { parseSupportAccessSession, type SupportAccessSession } from "../contracts/support-access/support-access.ts";

export interface SupportAccessRpcClient {
  rpc(
    fn: "has_active_support_grant" | "current_support_session",
    args: Record<string, unknown>,
  ): Promise<{ data: unknown; error: { message: string } | null }>;
}

export class SupportAccessQueryError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "SupportAccessQueryError";
  }
}

export async function hasActiveSupportGrant(
  client: SupportAccessRpcClient,
  input: { tenantId: string; authUserId: string },
): Promise<boolean> {
  const { data, error } = await client.rpc("has_active_support_grant", {
    p_tenant_id: input.tenantId,
    p_auth_user_id: input.authUserId,
  });

  if (error) {
    throw new SupportAccessQueryError(error.message);
  }
  if (typeof data !== "boolean") {
    throw new SupportAccessQueryError("has_active_support_grant returned a non-boolean result");
  }
  return data;
}

/** The caller's own currently-open support session into a tenant, or null if none (a normal, majority-case state, not an error). */
export async function currentSupportSession(
  client: SupportAccessRpcClient,
  input: { tenantId: string; authUserId: string },
): Promise<SupportAccessSession | null> {
  const { data, error } = await client.rpc("current_support_session", {
    p_tenant_id: input.tenantId,
    p_auth_user_id: input.authUserId,
  });

  if (error) {
    throw new SupportAccessQueryError(error.message);
  }
  if (!data || typeof data !== "object") {
    return null;
  }
  const row = data as Record<string, unknown>;
  if (row.id == null) {
    return null;
  }
  return parseSupportAccessSession(row);
}
