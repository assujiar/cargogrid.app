/**
 * Organization hierarchy scope-ancestry queries (PLT-109, CG-S6-PLT-006). Thin, typed
 * wrappers around app.org_unit_ancestor_ids / app.org_unit_descendant_ids
 * (supabase/migrations/20260716101726_create_org_units.sql) -- both read the materialized
 * `path` column directly, no recursive query on this side either.
 * Read-only (server/queries/, per docs/architecture/04_REPOSITORY_TARGET_STRUCTURE.md §8).
 *
 * listOrgUnits (O1 remediation, cluster 7): a flat, optionally status/unit_type-filtered
 * org-unit picker list, replacing 5 identical/near-identical broken `.from("org_units")` reads
 * embedded directly in HRIS page.tsx files (app is not exposed to PostgREST). Goes through the
 * new `list_org_units` RPC (20260913050000), SECURITY INVOKER, zero actor parameter --
 * domain-agnostic ("any active tenant member"), matching every one of its 5 call sites'
 * own access guard regardless of which domain resolved it.
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import { parseOrgUnit, type OrgUnit } from "../contracts/org-hierarchy/org-hierarchy.ts";

export interface OrgHierarchyRpcClient {
  rpc(
    fn: "org_unit_ancestor_ids" | "org_unit_descendant_ids" | "list_org_units",
    args: Record<string, unknown>,
  ): Promise<{ data: unknown; error: { message: string } | null }>;
}

/** Adapts a real Supabase client (whose own .rpc() returns a thenable query builder, not a plain Promise) into this module's narrower rpc-only contract -- same idiom as server/queries/procurement-approval.ts's toApprovalQueryRpcClient. */
export function toOrgHierarchyRpcClient(client: Pick<SupabaseClient, "rpc">): OrgHierarchyRpcClient {
  return { rpc: async (fn, args) => await client.rpc(fn, args) };
}

export class OrgHierarchyQueryError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "OrgHierarchyQueryError";
  }
}

export interface OrgUnitSummary {
  readonly id: string;
  readonly name: string;
  readonly unitType: string;
}

function parseOrgUnitSummary(row: Record<string, unknown>): OrgUnitSummary {
  return { id: String(row.id), name: String(row.name), unitType: String(row.unit_type) };
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

/** A flat, optionally status/unit_type-filtered picker list for one tenant, ordered by name. */
export async function listOrgUnits(
  client: OrgHierarchyRpcClient,
  tenantId: string,
  options?: { statusFilter?: string | null; unitTypeFilter?: string | null },
): Promise<OrgUnitSummary[]> {
  const { data, error } = await client.rpc("list_org_units", {
    p_tenant_id: tenantId,
    p_status_filter: options?.statusFilter ?? null,
    p_unit_type_filter: options?.unitTypeFilter ?? null,
  });

  if (error) {
    throw new OrgHierarchyQueryError(error.message);
  }
  if (!Array.isArray(data)) {
    throw new OrgHierarchyQueryError("list_org_units returned a non-array result");
  }
  return (data as Record<string, unknown>[]).map(parseOrgUnitSummary);
}

/**
 * The same `list_org_units` RPC, parsed as the FULL `OrgUnit` shape rather than the
 * narrow picker-list summary (audit remediation A2's own admin/organization/ UI needs
 * status/parentId/recordVersion to render and to drive move/rename/set-status forms,
 * none of which `OrgUnitSummary` carries) -- the RPC already returns every column
 * (`select *`, its own header: "full-row, never narrowed"), so this is a pure
 * projection choice, not a new database read.
 */
export async function listOrgUnitsFull(
  client: OrgHierarchyRpcClient,
  tenantId: string,
  options?: { statusFilter?: string | null; unitTypeFilter?: string | null },
): Promise<OrgUnit[]> {
  const { data, error } = await client.rpc("list_org_units", {
    p_tenant_id: tenantId,
    p_status_filter: options?.statusFilter ?? null,
    p_unit_type_filter: options?.unitTypeFilter ?? null,
  });

  if (error) {
    throw new OrgHierarchyQueryError(error.message);
  }
  if (!Array.isArray(data)) {
    throw new OrgHierarchyQueryError("list_org_units returned a non-array result");
  }
  return (data as Record<string, unknown>[]).map(parseOrgUnit);
}
