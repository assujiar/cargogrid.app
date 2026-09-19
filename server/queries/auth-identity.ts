/**
 * Auth identity linkage lookup (PLT-107, CG-S6-PLT-004). RPC-backed read of
 * app.list_identity_tenant_links (CG-AUDIT-2026-09-02 O1 cluster 2) -- the app schema is
 * not exposed to PostgREST, so a direct app.tenant_user_identities read never worked.
 */

import { parseTenantUserIdentity, type TenantUserIdentity } from "../contracts/auth/identity.ts";

export interface IdentityLookupClient {
  rpc(fn: "list_identity_tenant_links", args: { p_actor_auth_user_id: string }): Promise<{ data: unknown[] | null; error: { message: string } | null }>;
}

export class IdentityLookupError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "IdentityLookupError";
  }
}

/** Every tenant the CALLING identity is currently linked to (any status -- caller filters by status if only active/invited linkages are wanted). Self-lookup only -- authUserId must be the caller's own session identity; the database rejects any other value with actor_identity_mismatch (ATW-031/032). */
export async function listIdentityTenantLinks(client: IdentityLookupClient, authUserId: string): Promise<TenantUserIdentity[]> {
  const { data, error } = await client.rpc("list_identity_tenant_links", {
    p_actor_auth_user_id: authUserId,
  });

  if (error) {
    throw new IdentityLookupError(error.message);
  }
  return (data ?? []).map((row) => parseTenantUserIdentity(row as Record<string, unknown>));
}
