/**
 * Permission catalogue and role lookup (PLT-111, CG-S6-PLT-008). RPC-backed read of
 * app.list_permissions_for_module / app.list_tenant_roles (CG-AUDIT-2026-09-02 O1
 * cluster 2) -- the app schema is not exposed to PostgREST, so a direct
 * app.permissions / app.roles read never worked.
 *
 * listRoleVersions / listRoleVersionPermissions / listRoleAssignmentsForRole (audit
 * remediation A2): the read side the admin/roles/ UI needs to show its own results
 * again after a page reload -- see 20260914010000's own header for why these three
 * specifically (app.role_versions/app.role_assignments already had live RLS + an
 * authenticated grant; app.role_version_permissions had neither).
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import {
  parsePermission,
  parseRole,
  parseRoleVersion,
  parseRoleAssignment,
  type Permission,
  type Role,
  type RoleVersion,
  type RoleAssignment,
} from "../contracts/role-permission/role-permission.ts";

export interface RolePermissionLookupClient {
  rpc(
    fn: "list_permissions_for_module",
    args: { p_resource_module_code: string; p_actor_auth_user_id: string },
  ): Promise<{ data: unknown[] | null; error: { message: string } | null }>;
  rpc(
    fn: "list_tenant_roles",
    args: { p_tenant_id: string; p_actor_auth_user_id: string },
  ): Promise<{ data: unknown[] | null; error: { message: string } | null }>;
  rpc(
    fn: "list_role_versions",
    args: { p_role_id: string },
  ): Promise<{ data: unknown[] | null; error: { message: string } | null }>;
  rpc(
    fn: "list_role_version_permissions",
    args: { p_role_version_id: string; p_actor_auth_user_id: string },
  ): Promise<{ data: unknown[] | null; error: { message: string } | null }>;
  rpc(
    fn: "list_role_assignments_for_role",
    args: { p_role_id: string },
  ): Promise<{ data: unknown[] | null; error: { message: string } | null }>;
  rpc(
    fn: "list_active_tenant_users_for_role_assignment",
    args: { p_tenant_id: string; p_actor_auth_user_id: string },
  ): Promise<{ data: unknown[] | null; error: { message: string } | null }>;
}

export interface RoleAssignmentCandidate {
  readonly authUserId: string;
  readonly displayName: string;
}

function parseRoleAssignmentCandidate(row: Record<string, unknown>): RoleAssignmentCandidate {
  return { authUserId: String(row.auth_user_id), displayName: String(row.display_name) };
}

/**
 * Supabase's own `.rpc()` returns a `PostgrestFilterBuilder` (thenable, not a strict
 * `Promise`) -- structurally incompatible with this file's own hand-written
 * `RolePermissionLookupClient` interface. The same `async (fn, args) => await
 * client.rpc(fn, args)` adapter every other cross-module RPC composition in this
 * repository already uses for that exact mismatch.
 */
export function toRolePermissionLookupClient(client: Pick<SupabaseClient, "rpc">): RolePermissionLookupClient {
  return { rpc: async (fn: string, args: Record<string, unknown>) => await client.rpc(fn, args) } as RolePermissionLookupClient;
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

/** Every version (any status) of one role, newest version_number first. SECURITY INVOKER on the database side -- takes no actor parameter, relies on the caller's own session via live RLS. */
export async function listRoleVersions(client: RolePermissionLookupClient, roleId: string): Promise<RoleVersion[]> {
  const { data, error } = await client.rpc("list_role_versions", { p_role_id: roleId });

  if (error) {
    throw new RolePermissionLookupError(error.message);
  }
  return (data ?? []).map((row) => parseRoleVersion(row as Record<string, unknown>));
}

/** The permission set currently bound to one role version. */
export async function listRoleVersionPermissions(client: RolePermissionLookupClient, roleVersionId: string, actorAuthUserId: string): Promise<Permission[]> {
  const { data, error } = await client.rpc("list_role_version_permissions", {
    p_role_version_id: roleVersionId,
    p_actor_auth_user_id: actorAuthUserId,
  });

  if (error) {
    throw new RolePermissionLookupError(error.message);
  }
  return (data ?? []).map((row) => parsePermission(row as Record<string, unknown>));
}

/** Every assignment (active or revoked) of any version of one role, newest grant first. SECURITY INVOKER on the database side -- takes no actor parameter, relies on the caller's own session via live RLS. */
export async function listRoleAssignmentsForRole(client: RolePermissionLookupClient, roleId: string): Promise<RoleAssignment[]> {
  const { data, error } = await client.rpc("list_role_assignments_for_role", { p_role_id: roleId });

  if (error) {
    throw new RolePermissionLookupError(error.message);
  }
  return (data ?? []).map((row) => parseRoleAssignment(row as Record<string, unknown>));
}

/** Every active user's real auth_user_id (never app.users.id) plus a display label -- the option list for the "assign role" form. */
export async function listActiveTenantUsersForRoleAssignment(client: RolePermissionLookupClient, tenantId: string, actorAuthUserId: string): Promise<RoleAssignmentCandidate[]> {
  const { data, error } = await client.rpc("list_active_tenant_users_for_role_assignment", {
    p_tenant_id: tenantId,
    p_actor_auth_user_id: actorAuthUserId,
  });

  if (error) {
    throw new RolePermissionLookupError(error.message);
  }
  return (data ?? []).map((row) => parseRoleAssignmentCandidate(row as Record<string, unknown>));
}
