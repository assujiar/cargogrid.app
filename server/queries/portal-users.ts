/**
 * Tenant Admin portal users-list query (PLT-135, CG-S6-PLT-032). Reads `app.users_directory`
 * (PLT-114/116's own field-masked, tenant-scoped view -- reused directly, no new schema
 * per Prompt 135 §13's "no direct client DB / new portal-specific schema is prohibited
 * unless separately justified") through the RLS-scoped `authenticated` client, never
 * service-role -- cross-tenant leakage is prevented by the view's own RLS-equivalent
 * WHERE clause (`app.has_active_tenant_membership`) plus this query's own explicit
 * `tenant_id` filter (a caller with membership in multiple tenants must not see every
 * tenant's users merged together).
 *
 * Bounded, server-paginated (Prompt 135 §17: "no full datasets") -- `pageSize` is
 * clamped to `[1, 100]` regardless of what a caller requests.
 */

import { z } from "zod";
import type { SupabaseClient } from "@supabase/supabase-js";

const MAX_PAGE_SIZE = 100;

export const PortalUserSchema = z.object({
  id: z.string().uuid(),
  displayName: z.string(),
  status: z.string(),
  email: z.string().nullable(),
  emailMasked: z.boolean(),
});
export type PortalUser = z.infer<typeof PortalUserSchema>;

export interface ListPortalUsersInput {
  readonly tenantId: string;
  readonly page: number;
  readonly pageSize: number;
}

export interface ListPortalUsersResult {
  readonly users: readonly PortalUser[];
  readonly totalCount: number;
  readonly page: number;
  readonly pageSize: number;
}

export class PortalUsersQueryError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "PortalUsersQueryError";
  }
}

/** Maps a raw app.users_directory row (snake_case) to this contract's camelCase shape. */
function parsePortalUser(row: Record<string, unknown>): PortalUser {
  return PortalUserSchema.parse({
    id: row.id,
    displayName: row.display_name,
    status: row.status,
    email: row.email,
    emailMasked: row.email_masked,
  });
}

export async function listPortalUsers(
  client: Pick<SupabaseClient, "from">,
  input: ListPortalUsersInput,
): Promise<ListPortalUsersResult> {
  const pageSize = Math.min(Math.max(Math.trunc(input.pageSize), 1), MAX_PAGE_SIZE);
  const page = Math.max(Math.trunc(input.page), 1);
  const from = (page - 1) * pageSize;
  const to = from + pageSize - 1;

  const { data, error, count } = await client
    .from("users_directory")
    .select("id, display_name, status, email, email_masked", { count: "exact" })
    .eq("tenant_id", input.tenantId)
    .order("display_name", { ascending: true })
    .range(from, to);

  if (error) {
    throw new PortalUsersQueryError(error.message);
  }

  return {
    users: (data ?? []).map((row: Record<string, unknown>) => parsePortalUser(row)),
    totalCount: count ?? 0,
    page,
    pageSize,
  };
}
