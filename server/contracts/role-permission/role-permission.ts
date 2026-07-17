/**
 * Role and permission builder contract (PLT-111, CG-S6-PLT-008). Mirrors
 * supabase/migrations/20260716103445_create_roles_permissions.sql's app.permissions /
 * app.roles / app.role_versions / app.role_assignments shapes and their RPCs. Role
 * assignment alone grants no data access -- RBAC enforcement against these bindings is
 * PLT-112's scope, not this one's (Prompt 111 §24).
 */

import { z } from "zod";

export const PERMISSION_ACTIONS = [
  "View", "Create", "Edit", "Delete", "Approve", "Reject", "Assign", "Export", "Import",
  "Print", "Download", "View cost", "View selling price", "View margin", "View payroll",
  "View personal data", "Configure", "Override", "Reopen", "Close",
] as const;
export const PermissionActionSchema = z.enum(PERMISSION_ACTIONS);
export type PermissionAction = z.infer<typeof PermissionActionSchema>;

export const PERMISSION_CATEGORIES = ["standard", "workflow", "sensitive", "admin"] as const;
export const PermissionCategorySchema = z.enum(PERMISSION_CATEGORIES);
export type PermissionCategory = z.infer<typeof PermissionCategorySchema>;

export const PermissionSchema = z.object({
  id: z.string().uuid(),
  action: PermissionActionSchema,
  resourceModuleCode: z.string(),
  category: PermissionCategorySchema,
  protected: z.boolean(),
  code: z.string(),
  createdAt: z.string(),
});
export type Permission = z.infer<typeof PermissionSchema>;

export const ROLE_STATUSES = ["active", "archived"] as const;
export const RoleStatusSchema = z.enum(ROLE_STATUSES);
export type RoleStatus = z.infer<typeof RoleStatusSchema>;

export const RoleSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  name: z.string(),
  description: z.string().nullable(),
  status: RoleStatusSchema,
  createdBy: z.string().nullable(),
  recordVersion: z.number().int().positive(),
  createdAt: z.string(),
  updatedAt: z.string(),
});
export type Role = z.infer<typeof RoleSchema>;

export const ROLE_VERSION_STATUSES = ["draft", "published", "archived"] as const;
export const RoleVersionStatusSchema = z.enum(ROLE_VERSION_STATUSES);
export type RoleVersionStatus = z.infer<typeof RoleVersionStatusSchema>;

export const RoleVersionSchema = z.object({
  id: z.string().uuid(),
  roleId: z.string().uuid(),
  versionNumber: z.number().int().positive(),
  status: RoleVersionStatusSchema,
  effectiveFrom: z.string().nullable(),
  clonedFromVersionId: z.string().uuid().nullable(),
  createdBy: z.string().nullable(),
  publishedBy: z.string().nullable(),
  publishedAt: z.string().nullable(),
  archivedAt: z.string().nullable(),
  archivedReason: z.string().nullable(),
  recordVersion: z.number().int().positive(),
  createdAt: z.string(),
  updatedAt: z.string(),
});
export type RoleVersion = z.infer<typeof RoleVersionSchema>;

export const ROLE_ASSIGNMENT_STATUSES = ["active", "revoked"] as const;
export const RoleAssignmentStatusSchema = z.enum(ROLE_ASSIGNMENT_STATUSES);
export type RoleAssignmentStatus = z.infer<typeof RoleAssignmentStatusSchema>;

export const RoleAssignmentSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  roleVersionId: z.string().uuid(),
  authUserId: z.string().uuid(),
  status: RoleAssignmentStatusSchema,
  grantedBy: z.string().nullable(),
  grantedAt: z.string(),
  revokedAt: z.string().nullable(),
  revokedReason: z.string().nullable(),
  recordVersion: z.number().int().positive(),
  createdAt: z.string(),
  updatedAt: z.string(),
});
export type RoleAssignment = z.infer<typeof RoleAssignmentSchema>;

export const CreateRoleInputSchema = z.object({
  tenantId: z.string().uuid(),
  name: z.string().min(1),
  description: z.string().nullable().default(null),
  createdBy: z.string().min(1),
});
export type CreateRoleInput = z.input<typeof CreateRoleInputSchema>;

export const CreateRoleVersionInputSchema = z.object({
  roleId: z.string().uuid(),
  createdBy: z.string().min(1),
});
export type CreateRoleVersionInput = z.infer<typeof CreateRoleVersionInputSchema>;

export const SetRoleVersionPermissionsInputSchema = z.object({
  roleVersionId: z.string().uuid(),
  permissionIds: z.array(z.string().uuid()),
  requestedBy: z.string().min(1),
});
export type SetRoleVersionPermissionsInput = z.infer<typeof SetRoleVersionPermissionsInputSchema>;

export const PublishRoleVersionInputSchema = z.object({
  roleVersionId: z.string().uuid(),
  effectiveFrom: z.string(),
  publishedBy: z.string().min(1),
});
export type PublishRoleVersionInput = z.infer<typeof PublishRoleVersionInputSchema>;

export const CloneRoleVersionInputSchema = z.object({
  roleVersionId: z.string().uuid(),
  createdBy: z.string().min(1),
});
export type CloneRoleVersionInput = z.infer<typeof CloneRoleVersionInputSchema>;

export const ArchiveRoleVersionInputSchema = z.object({
  roleVersionId: z.string().uuid(),
  reason: z.string().min(1),
  requestedBy: z.string().min(1),
});
export type ArchiveRoleVersionInput = z.infer<typeof ArchiveRoleVersionInputSchema>;

export const AssignRoleInputSchema = z.object({
  tenantId: z.string().uuid(),
  roleVersionId: z.string().uuid(),
  authUserId: z.string().uuid(),
  actorAuthUserId: z.string().uuid(),
  grantedBy: z.string().min(1),
});
export type AssignRoleInput = z.infer<typeof AssignRoleInputSchema>;

export const RevokeRoleAssignmentInputSchema = z.object({
  id: z.string().uuid(),
  reason: z.string().min(1),
  requestedBy: z.string().min(1),
});
export type RevokeRoleAssignmentInput = z.infer<typeof RevokeRoleAssignmentInputSchema>;

/** Maps a raw app.permissions row (snake_case) to this contract's camelCase shape. */
export function parsePermission(row: Record<string, unknown>): Permission {
  return PermissionSchema.parse({
    id: row.id,
    action: row.action,
    resourceModuleCode: row.resource_module_code,
    category: row.category,
    protected: row.protected,
    code: row.code,
    createdAt: row.created_at,
  });
}

/** Maps a raw app.roles row (snake_case) to this contract's camelCase shape. */
export function parseRole(row: Record<string, unknown>): Role {
  return RoleSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    name: row.name,
    description: row.description,
    status: row.status,
    createdBy: row.created_by,
    recordVersion: row.record_version,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  });
}

/** Maps a raw app.role_versions row (snake_case) to this contract's camelCase shape. */
export function parseRoleVersion(row: Record<string, unknown>): RoleVersion {
  return RoleVersionSchema.parse({
    id: row.id,
    roleId: row.role_id,
    versionNumber: row.version_number,
    status: row.status,
    effectiveFrom: row.effective_from,
    clonedFromVersionId: row.cloned_from_version_id,
    createdBy: row.created_by,
    publishedBy: row.published_by,
    publishedAt: row.published_at,
    archivedAt: row.archived_at,
    archivedReason: row.archived_reason,
    recordVersion: row.record_version,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  });
}

/** Maps a raw app.role_assignments row (snake_case) to this contract's camelCase shape. */
export function parseRoleAssignment(row: Record<string, unknown>): RoleAssignment {
  return RoleAssignmentSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    roleVersionId: row.role_version_id,
    authUserId: row.auth_user_id,
    status: row.status,
    grantedBy: row.granted_by,
    grantedAt: row.granted_at,
    revokedAt: row.revoked_at,
    revokedReason: row.revoked_reason,
    recordVersion: row.record_version,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  });
}
