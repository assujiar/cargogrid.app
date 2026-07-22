/**
 * Supreme Admin portal global tenant-list query (PLT-136, CG-S6-PLT-033). Reads
 * `app.tenants` directly through the RLS-scoped `authenticated` client, never
 * service-role -- `PLT-113`'s own `tenants_select_own_tenant` policy already grants a
 * Supreme Admin visibility into every row (`app.has_active_tenant_membership()`
 * resolves `true` for any tenant when the caller `app.is_supreme_admin()`, confirmed
 * by direct inspection of that function's own body, not assumed), so no service-role
 * bypass is needed for this read path -- consistent with Prompt 136 §16's "no browser
 * service key," extended here to "no *server-side* service-role reach where RLS
 * already grants exactly the intended visibility."
 *
 * Bounded, server-paginated (Prompt 136 §17: "paginated global queries... strict query
 * guards") -- `pageSize` clamped to `[1, 100]`, the same cap `server/queries/portal-users.ts`
 * already established.
 */

import { z } from "zod";
import type { SupabaseClient } from "@supabase/supabase-js";

const MAX_PAGE_SIZE = 100;

export const SupremeTenantSchema = z.object({
  id: z.string().uuid(),
  slug: z.string(),
  name: z.string(),
  canonicalStatus: z.string(),
});
export type SupremeTenant = z.infer<typeof SupremeTenantSchema>;

export interface ListSupremeTenantsInput {
  readonly page: number;
  readonly pageSize: number;
}

export interface ListSupremeTenantsResult {
  readonly tenants: readonly SupremeTenant[];
  readonly totalCount: number;
  readonly page: number;
  readonly pageSize: number;
}

export class SupremeTenantsQueryError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "SupremeTenantsQueryError";
  }
}

/** Maps a raw app.tenants row (snake_case) to this contract's camelCase shape. */
function parseSupremeTenant(row: Record<string, unknown>): SupremeTenant {
  return SupremeTenantSchema.parse({
    id: row.id,
    slug: row.slug,
    name: row.name,
    canonicalStatus: row.canonical_status,
  });
}

export async function listSupremeTenants(
  client: Pick<SupabaseClient, "from">,
  input: ListSupremeTenantsInput,
): Promise<ListSupremeTenantsResult> {
  const pageSize = Math.min(Math.max(Math.trunc(input.pageSize), 1), MAX_PAGE_SIZE);
  const page = Math.max(Math.trunc(input.page), 1);
  const from = (page - 1) * pageSize;
  const to = from + pageSize - 1;

  const { data, error, count } = await client
    .from("tenants")
    .select("id, slug, name, canonical_status", { count: "exact" })
    .order("name", { ascending: true })
    .range(from, to);

  if (error) {
    throw new SupremeTenantsQueryError(error.message);
  }

  return {
    tenants: (data ?? []).map((row: Record<string, unknown>) => parseSupremeTenant(row)),
    totalCount: count ?? 0,
    page,
    pageSize,
  };
}
