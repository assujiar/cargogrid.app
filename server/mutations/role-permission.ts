/**
 * Role and permission builder service (PLT-111, CG-S6-PLT-008). Thin, typed wrappers
 * around app.create_role / app.create_role_version / app.set_role_version_permissions /
 * app.publish_role_version / app.clone_role_version / app.archive_role_version /
 * app.assign_role / app.revoke_role_assignment
 * (supabase/migrations/20260716103445_create_roles_permissions.sql).
 */

import {
  ArchiveRoleVersionInputSchema,
  AssignRoleInputSchema,
  CloneRoleVersionInputSchema,
  CreateRoleInputSchema,
  CreateRoleVersionInputSchema,
  PublishRoleVersionInputSchema,
  RevokeRoleAssignmentInputSchema,
  SetRoleVersionPermissionsInputSchema,
  parseRole,
  parseRoleAssignment,
  parseRoleVersion,
  type ArchiveRoleVersionInput,
  type AssignRoleInput,
  type CloneRoleVersionInput,
  type CreateRoleInput,
  type CreateRoleVersionInput,
  type PublishRoleVersionInput,
  type Role,
  type RoleAssignment,
  type RevokeRoleAssignmentInput,
  type RoleVersion,
  type SetRoleVersionPermissionsInput,
} from "../contracts/role-permission/role-permission.ts";

export interface RolePermissionRpcClient {
  rpc(
    fn:
      | "create_role"
      | "create_role_version"
      | "set_role_version_permissions"
      | "publish_role_version"
      | "clone_role_version"
      | "archive_role_version"
      | "assign_role"
      | "revoke_role_assignment",
    args: Record<string, unknown>,
  ): Promise<{ data: unknown; error: { message: string } | null }>;
}

export const ROLE_PERMISSION_KNOWN_ERROR_CODES = [
  "role_not_found",
  "role_version_not_found",
  "role_version_not_draft",
  "role_version_not_published",
  "cannot_clone_draft",
  "cross_tenant_role",
  "user_not_active_in_tenant",
  "self_escalation",
  "role_assignment_not_found",
] as const;
type KnownRolePermissionErrorCode = (typeof ROLE_PERMISSION_KNOWN_ERROR_CODES)[number];
export type RolePermissionMutationErrorCode = KnownRolePermissionErrorCode | "mutation_failed" | "invalid_response";

export class RolePermissionMutationError extends Error {
  readonly code: RolePermissionMutationErrorCode;

  constructor(code: RolePermissionMutationErrorCode, message: string) {
    super(message);
    this.name = "RolePermissionMutationError";
    this.code = code;
  }
}

function classifyError(message: string): RolePermissionMutationErrorCode {
  const prefix = message.split(":")[0]?.trim();
  return (ROLE_PERMISSION_KNOWN_ERROR_CODES as readonly string[]).includes(prefix ?? "")
    ? (prefix as KnownRolePermissionErrorCode)
    : "mutation_failed";
}

async function callRpc(client: RolePermissionRpcClient, fn: Parameters<RolePermissionRpcClient["rpc"]>[0], args: Record<string, unknown>) {
  const { data, error } = await client.rpc(fn, args);
  if (error) {
    throw new RolePermissionMutationError(classifyError(error.message), error.message);
  }
  return data;
}

export async function createRole(client: RolePermissionRpcClient, input: CreateRoleInput): Promise<Role> {
  const parsedInput = CreateRoleInputSchema.parse(input);
  const data = await callRpc(client, "create_role", {
    p_tenant_id: parsedInput.tenantId,
    p_name: parsedInput.name,
    p_description: parsedInput.description,
    p_created_by: parsedInput.createdBy,
  });
  if (!data || typeof data !== "object") {
    throw new RolePermissionMutationError("invalid_response", "create_role returned no row");
  }
  return parseRole(data as Record<string, unknown>);
}

export async function createRoleVersion(client: RolePermissionRpcClient, input: CreateRoleVersionInput): Promise<RoleVersion> {
  const parsedInput = CreateRoleVersionInputSchema.parse(input);
  const data = await callRpc(client, "create_role_version", {
    p_role_id: parsedInput.roleId,
    p_created_by: parsedInput.createdBy,
  });
  if (!data || typeof data !== "object") {
    throw new RolePermissionMutationError("invalid_response", "create_role_version returned no row");
  }
  return parseRoleVersion(data as Record<string, unknown>);
}

/** Returns the number of permissions now bound to the draft version. */
export async function setRoleVersionPermissions(client: RolePermissionRpcClient, input: SetRoleVersionPermissionsInput): Promise<number> {
  const parsedInput = SetRoleVersionPermissionsInputSchema.parse(input);
  const data = await callRpc(client, "set_role_version_permissions", {
    p_role_version_id: parsedInput.roleVersionId,
    p_permission_ids: parsedInput.permissionIds,
    p_requested_by: parsedInput.requestedBy,
  });
  if (typeof data !== "number") {
    throw new RolePermissionMutationError("invalid_response", "set_role_version_permissions returned a non-numeric result");
  }
  return data;
}

export async function publishRoleVersion(client: RolePermissionRpcClient, input: PublishRoleVersionInput): Promise<RoleVersion> {
  const parsedInput = PublishRoleVersionInputSchema.parse(input);
  const data = await callRpc(client, "publish_role_version", {
    p_role_version_id: parsedInput.roleVersionId,
    p_effective_from: parsedInput.effectiveFrom,
    p_published_by: parsedInput.publishedBy,
  });
  if (!data || typeof data !== "object") {
    throw new RolePermissionMutationError("invalid_response", "publish_role_version returned no row");
  }
  return parseRoleVersion(data as Record<string, unknown>);
}

export async function cloneRoleVersion(client: RolePermissionRpcClient, input: CloneRoleVersionInput): Promise<RoleVersion> {
  const parsedInput = CloneRoleVersionInputSchema.parse(input);
  const data = await callRpc(client, "clone_role_version", {
    p_role_version_id: parsedInput.roleVersionId,
    p_created_by: parsedInput.createdBy,
  });
  if (!data || typeof data !== "object") {
    throw new RolePermissionMutationError("invalid_response", "clone_role_version returned no row");
  }
  return parseRoleVersion(data as Record<string, unknown>);
}

export async function archiveRoleVersion(client: RolePermissionRpcClient, input: ArchiveRoleVersionInput): Promise<RoleVersion> {
  const parsedInput = ArchiveRoleVersionInputSchema.parse(input);
  const data = await callRpc(client, "archive_role_version", {
    p_role_version_id: parsedInput.roleVersionId,
    p_reason: parsedInput.reason,
    p_requested_by: parsedInput.requestedBy,
  });
  if (!data || typeof data !== "object") {
    throw new RolePermissionMutationError("invalid_response", "archive_role_version returned no row");
  }
  return parseRoleVersion(data as Record<string, unknown>);
}

export async function assignRole(client: RolePermissionRpcClient, input: AssignRoleInput): Promise<RoleAssignment> {
  const parsedInput = AssignRoleInputSchema.parse(input);
  const data = await callRpc(client, "assign_role", {
    p_tenant_id: parsedInput.tenantId,
    p_role_version_id: parsedInput.roleVersionId,
    p_auth_user_id: parsedInput.authUserId,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_granted_by: parsedInput.grantedBy,
  });
  if (!data || typeof data !== "object") {
    throw new RolePermissionMutationError("invalid_response", "assign_role returned no row");
  }
  return parseRoleAssignment(data as Record<string, unknown>);
}

export async function revokeRoleAssignment(client: RolePermissionRpcClient, input: RevokeRoleAssignmentInput): Promise<RoleAssignment> {
  const parsedInput = RevokeRoleAssignmentInputSchema.parse(input);
  const data = await callRpc(client, "revoke_role_assignment", {
    p_id: parsedInput.id,
    p_reason: parsedInput.reason,
    p_requested_by: parsedInput.requestedBy,
  });
  if (!data || typeof data !== "object") {
    throw new RolePermissionMutationError("invalid_response", "revoke_role_assignment returned no row");
  }
  return parseRoleAssignment(data as Record<string, unknown>);
}
