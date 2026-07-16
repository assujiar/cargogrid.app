/**
 * Permission catalogue and role lookup (PLT-111, CG-S6-PLT-008). Read path
 * (server/queries/, per docs/architecture/04_REPOSITORY_TARGET_STRUCTURE.md §8) wrapping
 * direct table reads -- neither the catalogue nor a tenant's role list needs bespoke RPC
 * logic, matching PLT-107's listIdentityTenantLinks precedent.
 */

import { parsePermission, parseRole, type Permission, type Role } from "../contracts/role-permission/role-permission.ts";

export interface RolePermissionLookupClient {
  from(table: "permissions" | "roles"): {
    select(columns: string): {
      eq(column: string, value: string): Promise<{ data: unknown[] | null; error: { message: string } | null }>;
    };
  };
}

export class RolePermissionLookupError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "RolePermissionLookupError";
  }
}

/** The full canonical permission catalogue for one business-domain module. */
export async function listPermissionsForModule(client: RolePermissionLookupClient, moduleCode: string): Promise<Permission[]> {
  const { data, error } = await client.from("permissions").select("*").eq("resource_module_code", moduleCode);

  if (error) {
    throw new RolePermissionLookupError(error.message);
  }
  return (data ?? []).map((row) => parsePermission(row as Record<string, unknown>));
}

/** Every role (any status) a tenant has created. */
export async function listTenantRoles(client: RolePermissionLookupClient, tenantId: string): Promise<Role[]> {
  const { data, error } = await client.from("roles").select("*").eq("tenant_id", tenantId);

  if (error) {
    throw new RolePermissionLookupError(error.message);
  }
  return (data ?? []).map((row) => parseRole(row as Record<string, unknown>));
}
