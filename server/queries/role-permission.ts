/**
 * Permission catalogue and role lookup (PLT-111, CG-S6-PLT-008). RPC-backed read of
 * app.list_permissions_for_module / app.list_tenant_roles (CG-AUDIT-2026-09-02 O1
 * cluster 2) -- the app schema is not exposed to PostgREST, so a direct
 * app.permissions / app.roles read never worked.
 */

import { parsePermission, parseRole, type Permission, type Role } from "../contracts/role-permission/role-permission.ts";

export interface RolePermissionLookupClient {
  rpc(
    fn: "list_permissions_for_module",
    args: { p_resource_module_code: string; p_actor_auth_user_id: string },
  ): Promise<{ data: unknown[] | null; error: { message: string } | null }>;
  rpc(
    fn: "list_tenant_roles",
    args: { p_tenant_id: string; p_actor_auth_user_id: string },
  ): Promise<{ data: unknown[] | null; error: { message: string } | null }>;
}

export class RolePermissionLookupError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "RolePermissionLookupError";
  }
}

/** The full canonical permission catalogue for one business-domain module. */
export async function listPermissionsForModule(client: RolePermissionLookupClient, moduleCode: string, actorAuthUserId: string): Promise<Permission[]> {
  const { data, error } = await client.rpc("list_permissions_for_module", {
    p_resource_module_code: moduleCode,
    p_actor_auth_user_id: actorAuthUserId,
  });

  if (error) {
    throw new RolePermissionLookupError(error.message);
  }
  return (data ?? []).map((row) => parsePermission(row as Record<string, unknown>));
}

/** Every role (any status) a tenant has created. */
export async function listTenantRoles(client: RolePermissionLookupClient, tenantId: string, actorAuthUserId: string): Promise<Role[]> {
  const { data, error } = await client.rpc("list_tenant_roles", {
    p_tenant_id: tenantId,
    p_actor_auth_user_id: actorAuthUserId,
  });

  if (error) {
    throw new RolePermissionLookupError(error.message);
  }
  return (data ?? []).map((row) => parseRole(row as Record<string, unknown>));
}
