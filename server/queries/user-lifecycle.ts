/**
 * User lifecycle lookup (PLT-110, CG-S6-PLT-007). Read path (server/queries/, per
 * docs/architecture/04_REPOSITORY_TARGET_STRUCTURE.md §8) wrapping a direct table read --
 * app.users has no bespoke lookup RPC, matching PLT-107's listIdentityTenantLinks
 * precedent (a plain filtered select is the correct shape for a simple lookup).
 *
 * ATW-032 (post-Prompt-248 audit, ISS-2026-034): this used to be
 * `.from("users").select("*")`, which could never succeed for the `authenticated` role.
 * `20260716110430_create_field_record_access.sql` deliberately does
 * `revoke select on app.users from authenticated` and re-grants SELECT on an explicit
 * 17-column list that omits `email`, precisely so a column-level revoke cannot be undone
 * by PLT-113's broader table-level grant. Postgres denies `SELECT *` outright when ANY
 * column lacks a grant -- verified against the applied schema:
 *
 *     set role authenticated; select * from app.users limit 1;
 *       -> ERROR: permission denied for table users
 *     set role authenticated; select id, tenant_id from app.users limit 1;   -> ok
 *
 * so every call returned `{ error }` and threw. This is the same defect class as the
 * already-fixed `getThirdPartyProviderConnection` select("*") (ISS-2026-026); the rule is
 * documented at server/queries/third-party-provider-adapter.ts:36-42 and this call site
 * was missed.
 *
 * Narrowing the column list alone would not have been enough: the address itself is
 * ungranted, and the field-masking design (PLT-114) says the ONLY read path to it for a
 * tenant-layer caller is `app.users_directory`, which redacts it per row unless the caller
 * holds the real `HRS:View personal data` permission. So the lifecycle columns come from
 * `app.users` (explicit list, exactly the granted 17) and the address comes from the
 * directory view, merged by id -- the masking decision stays server-side where it belongs.
 */

import { parseTenantUser, type TenantUser } from "../contracts/user-lifecycle/user-lifecycle.ts";

/**
 * Exactly the columns `20260716110430_create_field_record_access.sql` grants SELECT on to
 * `authenticated`. Never `*` -- see the module header.
 */
const USERS_GRANTED_COLUMNS =
  "id, tenant_id, auth_user_id, display_name, status, org_unit_id, invited_by, invited_at, invite_expires_at, activated_at, suspended_at, suspended_reason, revoked_at, revoked_reason, record_version, created_at, updated_at";

export interface UserLookupClient {
  from(table: "users" | "users_directory"): {
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

/**
 * Every user profile in a tenant (any status -- caller filters by status if only active
 * users are wanted). `email` is the masked projection unless the caller holds
 * `HRS:View personal data`; `emailMasked` says which of the two it is.
 */
export async function listTenantUsers(client: UserLookupClient, tenantId: string): Promise<TenantUser[]> {
  const [users, directory] = await Promise.all([
    client.from("users").select(USERS_GRANTED_COLUMNS).eq("tenant_id", tenantId),
    client.from("users_directory").select("id, email, email_masked").eq("tenant_id", tenantId),
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
      // The directory view is a plain projection of app.users, so a row present in one and
      // absent from the other means the two reads saw different snapshots. Failing loudly
      // beats inventing an address or silently dropping a user from an admin list.
      throw new UserLookupError(`user ${String(row.id)} has no app.users_directory projection`);
    }
    return parseTenantUser(row, projection);
  });
}
