"use server";

/**
 * Role and permission builder Server Actions (audit remediation A2;
 * `docs/audit/2026-09-02-independent-launch-readiness-audit.md` finding A2:
 * "createRole/assignRole/revokeRoleAssignment have no caller"). Every
 * mutation in `server/mutations/role-permission.ts` (PLT-111) already
 * existed, fully implemented and tested, but is `service_role`-only
 * (this file's own migration's grants) -- every call below uses the
 * service-role client, the "explicit actor, service-role execution"
 * pattern every other privileged mutation in this repository already
 * follows. `resolveTenantAdminAccessForRequest` (tenant_admin layer only)
 * is the sole gate: this migration's own header notes role administration
 * "has no authenticated-reachable mutation path at all today ... no
 * narrower 'who may configure roles' authority to defer to" -- there is no
 * finer-grained permission to check beyond being a tenant admin at all.
 */

import { revalidatePath } from "next/cache";
import { createSupabaseServiceRoleClient } from "../../../../../lib/supabase/service-role.ts";
import { resolveTenantAdminAccessForRequest } from "../../../../../lib/portal/resolve-tenant-admin-access.server.ts";
import {
  createRole,
  createRoleVersion,
  setRoleVersionPermissions,
  publishRoleVersion,
  assignRole,
  revokeRoleAssignment,
  toRolePermissionRpcClient,
  RolePermissionMutationError,
} from "../../../../../server/mutations/role-permission.ts";

export interface RoleActionState {
  readonly error: string | null;
}

const OK: RoleActionState = { error: null };
const NO_ACCESS: RoleActionState = { error: "You don't have access to manage roles for this organization." };

async function requireAccess(tenantSlug: string) {
  const access = await resolveTenantAdminAccessForRequest(tenantSlug);
  if (access.status !== "allowed") return null;
  return access;
}

export async function createRoleAction(tenantSlug: string, _prevState: RoleActionState, formData: FormData): Promise<RoleActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return NO_ACCESS;

  const name = String(formData.get("name") ?? "").trim();
  const description = String(formData.get("description") ?? "").trim() || null;

  const client = toRolePermissionRpcClient(createSupabaseServiceRoleClient());
  try {
    await createRole(client, { tenantId: access.tenant.id, name, description, createdBy: access.authUserId });
  } catch (error) {
    if (error instanceof RolePermissionMutationError) return { error: `Could not create this role: ${error.message}` };
    throw error;
  }

  revalidatePath(`/${tenantSlug}/admin/roles`);
  return OK;
}

export async function createRoleVersionAction(tenantSlug: string, roleId: string, _prevState: RoleActionState, _formData: FormData): Promise<RoleActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return NO_ACCESS;

  const client = toRolePermissionRpcClient(createSupabaseServiceRoleClient());
  try {
    await createRoleVersion(client, { roleId, createdBy: access.authUserId });
  } catch (error) {
    if (error instanceof RolePermissionMutationError) return { error: `Could not create a new draft version: ${error.message}` };
    throw error;
  }

  revalidatePath(`/${tenantSlug}/admin/roles/${roleId}`);
  return OK;
}

export async function setRoleVersionPermissionsAction(tenantSlug: string, roleId: string, roleVersionId: string, _prevState: RoleActionState, formData: FormData): Promise<RoleActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return NO_ACCESS;

  const permissionIds = formData.getAll("permissionId").map(String);

  const client = toRolePermissionRpcClient(createSupabaseServiceRoleClient());
  try {
    await setRoleVersionPermissions(client, { roleVersionId, permissionIds, requestedBy: access.authUserId });
  } catch (error) {
    if (error instanceof RolePermissionMutationError) return { error: `Could not save these permissions: ${error.message}` };
    throw error;
  }

  revalidatePath(`/${tenantSlug}/admin/roles/${roleId}`);
  return OK;
}

export async function publishRoleVersionAction(tenantSlug: string, roleId: string, roleVersionId: string, _prevState: RoleActionState, _formData: FormData): Promise<RoleActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return NO_ACCESS;

  const client = toRolePermissionRpcClient(createSupabaseServiceRoleClient());
  try {
    await publishRoleVersion(client, { roleVersionId, effectiveFrom: new Date().toISOString(), publishedBy: access.authUserId });
  } catch (error) {
    if (error instanceof RolePermissionMutationError) return { error: `Could not publish this version: ${error.message}` };
    throw error;
  }

  revalidatePath(`/${tenantSlug}/admin/roles/${roleId}`);
  return OK;
}

export async function assignRoleAction(tenantSlug: string, roleId: string, _prevState: RoleActionState, formData: FormData): Promise<RoleActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return NO_ACCESS;

  const roleVersionId = String(formData.get("roleVersionId") ?? "").trim();
  const authUserId = String(formData.get("authUserId") ?? "").trim();

  const client = toRolePermissionRpcClient(createSupabaseServiceRoleClient());
  try {
    await assignRole(client, { tenantId: access.tenant.id, roleVersionId, authUserId, actorAuthUserId: access.authUserId, grantedBy: access.authUserId });
  } catch (error) {
    if (error instanceof RolePermissionMutationError) return { error: `Could not assign this role: ${error.message}` };
    throw error;
  }

  revalidatePath(`/${tenantSlug}/admin/roles/${roleId}`);
  return OK;
}

export async function revokeRoleAssignmentAction(tenantSlug: string, roleId: string, assignmentId: string, _prevState: RoleActionState, _formData: FormData): Promise<RoleActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return NO_ACCESS;

  const client = toRolePermissionRpcClient(createSupabaseServiceRoleClient());
  try {
    await revokeRoleAssignment(client, { id: assignmentId, reason: "revoked from admin/roles", requestedBy: access.authUserId });
  } catch (error) {
    if (error instanceof RolePermissionMutationError) return { error: `Could not revoke this assignment: ${error.message}` };
    throw error;
  }

  revalidatePath(`/${tenantSlug}/admin/roles/${roleId}`);
  return OK;
}
