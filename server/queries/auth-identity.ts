/**
 * Auth identity linkage lookup (PLT-107, CG-S6-PLT-004). Read path
 * (server/queries/, per docs/architecture/04_REPOSITORY_TARGET_STRUCTURE.md §8) wrapping
 * a direct table read -- app.tenant_user_identities has no bespoke lookup RPC (a plain
 * filtered select is the correct shape here, unlike PLT-106's evaluator which needed
 * real precedence logic).
 */

import { parseTenantUserIdentity, type TenantUserIdentity } from "../contracts/auth/identity.ts";

export interface IdentityLookupClient {
  from(table: "tenant_user_identities"): {
    select(columns: string): {
      eq(column: string, value: string): Promise<{ data: unknown[] | null; error: { message: string } | null }>;
    };
  };
}

export class IdentityLookupError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "IdentityLookupError";
  }
}

/** Every tenant an auth identity is currently linked to (any status -- caller filters by status if only active/invited linkages are wanted). */
export async function listIdentityTenantLinks(client: IdentityLookupClient, authUserId: string): Promise<TenantUserIdentity[]> {
  const { data, error } = await client.from("tenant_user_identities").select("*").eq("auth_user_id", authUserId);

  if (error) {
    throw new IdentityLookupError(error.message);
  }
  return (data ?? []).map((row) => parseTenantUserIdentity(row as Record<string, unknown>));
}
