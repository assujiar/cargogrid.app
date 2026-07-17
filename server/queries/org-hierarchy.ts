/**
 * Organization hierarchy scope-ancestry queries (PLT-109, CG-S6-PLT-006). Thin, typed
 * wrappers around app.org_unit_ancestor_ids / app.org_unit_descendant_ids
 * (supabase/migrations/20260716101726_create_org_units.sql) -- both read the materialized
 * `path` column directly, no recursive query on this side either.
 * Read-only (server/queries/, per docs/architecture/04_REPOSITORY_TARGET_STRUCTURE.md §8).
 */

export interface OrgHierarchyRpcClient {
  rpc(
    fn: "org_unit_ancestor_ids" | "org_unit_descendant_ids",
    args: Record<string, unknown>,
  ): Promise<{ data: unknown; error: { message: string } | null }>;
}

export class OrgHierarchyQueryError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "OrgHierarchyQueryError";
  }
}

/** Ancestor ids, root first, not including the node itself. Empty array for a root (company). */
export async function getOrgUnitAncestorIds(client: OrgHierarchyRpcClient, orgUnitId: string): Promise<string[]> {
  const { data, error } = await client.rpc("org_unit_ancestor_ids", { p_id: orgUnitId });

  if (error) {
    throw new OrgHierarchyQueryError(error.message);
  }
  if (!Array.isArray(data)) {
    throw new OrgHierarchyQueryError("org_unit_ancestor_ids returned a non-array result");
  }
  return data as string[];
}

/** Every descendant id (any depth), not including the node itself. */
export async function getOrgUnitDescendantIds(client: OrgHierarchyRpcClient, orgUnitId: string): Promise<string[]> {
  const { data, error } = await client.rpc("org_unit_descendant_ids", { p_id: orgUnitId });

  if (error) {
    throw new OrgHierarchyQueryError(error.message);
  }
  if (!Array.isArray(data)) {
    throw new OrgHierarchyQueryError("org_unit_descendant_ids returned a non-array result");
  }
  return data as string[];
}
