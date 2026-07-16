/**
 * Organization hierarchy contract (PLT-109, CG-S6-PLT-006). Mirrors
 * supabase/migrations/20260716101726_create_org_units.sql's app.org_units shape and the
 * app.create_org_unit/app.move_org_unit/app.rename_org_unit/app.set_org_unit_status RPCs.
 * `path` is the materialized ancestor-id list (root first, self excluded) the migration
 * maintains -- ancestor/descendant queries read it directly, never a recursive walk.
 */

import { z } from "zod";

export const ORG_UNIT_TYPES = ["company", "branch", "department", "business_unit"] as const;
export const OrgUnitTypeSchema = z.enum(ORG_UNIT_TYPES);
export type OrgUnitType = z.infer<typeof OrgUnitTypeSchema>;

export const ORG_UNIT_STATUSES = ["active", "inactive"] as const;
export const OrgUnitStatusSchema = z.enum(ORG_UNIT_STATUSES);
export type OrgUnitStatus = z.infer<typeof OrgUnitStatusSchema>;

export const OrgUnitSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  unitType: OrgUnitTypeSchema,
  parentId: z.string().uuid().nullable(),
  code: z.string(),
  name: z.string(),
  status: OrgUnitStatusSchema,
  path: z.array(z.string().uuid()),
  depth: z.number().int().nonnegative(),
  recordVersion: z.number().int().positive(),
  createdAt: z.string(),
  updatedAt: z.string(),
});
export type OrgUnit = z.infer<typeof OrgUnitSchema>;

export const CreateOrgUnitInputSchema = z.object({
  tenantId: z.string().uuid(),
  unitType: OrgUnitTypeSchema,
  parentId: z.string().uuid().nullable().default(null),
  code: z.string().min(1),
  name: z.string().min(1),
  requestedBy: z.string().min(1),
});
export type CreateOrgUnitInput = z.input<typeof CreateOrgUnitInputSchema>;

export const MoveOrgUnitInputSchema = z.object({
  id: z.string().uuid(),
  newParentId: z.string().uuid().nullable(),
  expectedVersion: z.number().int().positive(),
  requestedBy: z.string().min(1),
});
export type MoveOrgUnitInput = z.infer<typeof MoveOrgUnitInputSchema>;

export const RenameOrgUnitInputSchema = z.object({
  id: z.string().uuid(),
  newName: z.string().min(1),
  expectedVersion: z.number().int().positive(),
  requestedBy: z.string().min(1),
});
export type RenameOrgUnitInput = z.infer<typeof RenameOrgUnitInputSchema>;

export const SetOrgUnitStatusInputSchema = z.object({
  id: z.string().uuid(),
  newStatus: OrgUnitStatusSchema,
  expectedVersion: z.number().int().positive(),
  reason: z.string().min(1),
  requestedBy: z.string().min(1),
});
export type SetOrgUnitStatusInput = z.infer<typeof SetOrgUnitStatusInputSchema>;

/** Maps a raw app.org_units row (snake_case) to this contract's camelCase shape. */
export function parseOrgUnit(row: Record<string, unknown>): OrgUnit {
  return OrgUnitSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    unitType: row.unit_type,
    parentId: row.parent_id,
    code: row.code,
    name: row.name,
    status: row.status,
    path: row.path,
    depth: row.depth,
    recordVersion: row.record_version,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  });
}
