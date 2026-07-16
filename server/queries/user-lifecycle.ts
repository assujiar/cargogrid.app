/**
 * User lifecycle lookup (PLT-110, CG-S6-PLT-007). Read path (server/queries/, per
 * docs/architecture/04_REPOSITORY_TARGET_STRUCTURE.md §8) wrapping a direct table read --
 * app.users has no bespoke lookup RPC, matching PLT-107's listIdentityTenantLinks
 * precedent (a plain filtered select is the correct shape for a simple lookup).
 */

import { parseUser, type User } from "../contracts/user-lifecycle/user-lifecycle.ts";

export interface UserLookupClient {
  from(table: "users"): {
    select(columns: string): {
      eq(column: string, value: string): Promise<{ data: unknown[] | null; error: { message: string } | null }>;
    };
  };
}

export class UserLookupError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "UserLookupError";
  }
}

/** Every user profile in a tenant (any status -- caller filters by status if only active users are wanted). */
export async function listTenantUsers(client: UserLookupClient, tenantId: string): Promise<User[]> {
  const { data, error } = await client.from("users").select("*").eq("tenant_id", tenantId);

  if (error) {
    throw new UserLookupError(error.message);
  }
  return (data ?? []).map((row) => parseUser(row as Record<string, unknown>));
}
