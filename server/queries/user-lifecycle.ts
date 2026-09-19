/**
 * User lifecycle lookup (PLT-110, CG-S6-PLT-007). RPC-backed read of app.list_tenant_users
 * / app.list_user_directory_email_projections (CG-AUDIT-2026-09-02 O1 cluster 2) -- the
 * app schema is not exposed to PostgREST, so a direct app.users / app.users_directory read
 * never worked.
 *
 * The lifecycle columns come from app.list_tenant_users (explicit list, exactly the 17
 * columns PLT-114's own column-level grant covers -- never a raw `email`) and the address
 * comes from app.list_user_directory_email_projections, merged by id -- the masking
 * decision stays server-side where it belongs (PLT-114).
 */

import { parseTenantUser, type TenantUser } from "../contracts/user-lifecycle/user-lifecycle.ts";

export interface UserLookupClient {
  rpc(
    fn: "list_tenant_users",
    args: { p_tenant_id: string; p_actor_auth_user_id: string },
  ): Promise<{ data: unknown[] | null; error: { message: string } | null }>;
  rpc(
    fn: "list_user_directory_email_projections",
    args: { p_tenant_id: string; p_actor_auth_user_id: string },
  ): Promise<{ data: unknown[] | null; error: { message: string } | null }>;
}

export class UserLookupError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "UserLookupError";
  }
}

/**
 * Every user profile in a tenant (any status -- caller filters by status if only active
 * users are wanted). `email` is the masked projection unless the caller holds
 * `HRS:View personal data`; `emailMasked` says which of the two it is.
 */
export async function listTenantUsers(client: UserLookupClient, tenantId: string, actorAuthUserId: string): Promise<TenantUser[]> {
  const [users, directory] = await Promise.all([
    client.rpc("list_tenant_users", { p_tenant_id: tenantId, p_actor_auth_user_id: actorAuthUserId }),
    client.rpc("list_user_directory_email_projections", { p_tenant_id: tenantId, p_actor_auth_user_id: actorAuthUserId }),
  ]);

  if (users.error) {
    throw new UserLookupError(users.error.message);
  }
  if (directory.error) {
    throw new UserLookupError(directory.error.message);
  }

  const emailById = new Map<string, { email: unknown; email_masked: unknown }>();
  for (const entry of directory.data ?? []) {
    const row = entry as Record<string, unknown>;
    emailById.set(String(row.id), { email: row.email, email_masked: row.email_masked });
  }

  return (users.data ?? []).map((entry) => {
    const row = entry as Record<string, unknown>;
    const projection = emailById.get(String(row.id));
    if (!projection) {
      // The directory RPC is a plain projection of app.users, so a row present in one and
      // absent from the other means the two reads saw different snapshots. Failing loudly
      // beats inventing an address or silently dropping a user from an admin list.
      throw new UserLookupError(`user ${String(row.id)} has no app.users_directory projection`);
    }
    return parseTenantUser(row, projection);
  });
}
