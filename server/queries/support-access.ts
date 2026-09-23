/**
 * Support access read queries (PLT-115, CG-S6-PLT-012). Thin, typed wrappers around
 * app.has_active_support_grant / app.current_support_session
 * (supabase/migrations/20260716111315_create_support_access.sql). Read-only
 * (server/queries/, per docs/architecture/04_REPOSITORY_TARGET_STRUCTURE.md §8) --
 * grant/session lifecycle mutations live in server/mutations/support-access.ts.
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import { parseSupportAccessGrant, parseSupportAccessSession, type SupportAccessGrant, type SupportAccessSession } from "../contracts/support-access/support-access.ts";

export interface SupportAccessRpcClient {
  rpc(
    fn: "has_active_support_grant" | "current_support_session" | "list_support_access_grants_for_admin",
    args: Record<string, unknown>,
  ): Promise<{ data: unknown; error: { message: string } | null }>;
}

/** Adapts a real Supabase client to this file's own narrower interface -- CG-AUDIT-2026-09-02 UNTRACKED-D4's first real caller, mirrors server/mutations/tenant.ts's own toTenantRpcClient exactly. */
export function toSupportAccessRpcClient(client: Pick<SupabaseClient, "rpc">): SupportAccessRpcClient {
  return { rpc: async (fn, args) => await client.rpc(fn, args) };
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

const MAX_PAGE_SIZE = 100;

export interface ListSupportAccessGrantsForAdminInput {
  readonly page: number;
  readonly pageSize: number;
}

export interface ListSupportAccessGrantsForAdminResult {
  readonly grants: readonly SupportAccessGrant[];
  readonly totalCount: number;
  readonly page: number;
  readonly pageSize: number;
}

/**
 * CG-AUDIT-2026-09-02 UNTRACKED-D4: the support-access console's own paginated
 * grant list, through app.list_support_access_grants_for_admin (SECURITY
 * INVOKER, RLS does the visibility filtering -- see that RPC's own comment).
 * Mirrors server/queries/supreme-tenants.ts#listSupremeTenants exactly.
 */
export async function listSupportAccessGrantsForAdmin(
  client: SupportAccessRpcClient,
  input: ListSupportAccessGrantsForAdminInput,
): Promise<ListSupportAccessGrantsForAdminResult> {
  const pageSize = Math.min(Math.max(Math.trunc(input.pageSize), 1), MAX_PAGE_SIZE);
  const page = Math.max(Math.trunc(input.page), 1);

  const { data, error } = await client.rpc("list_support_access_grants_for_admin", { p_page: page, p_page_size: pageSize });

  if (error) {
    throw new SupportAccessQueryError(error.message);
  }

  const rows = (data ?? []) as Record<string, unknown>[];
  return {
    grants: rows.map((row) => parseSupportAccessGrant(row)),
    totalCount: rows.length > 0 ? Number(rows[0]!.total_count) : 0,
    page,
    pageSize,
  };
}
