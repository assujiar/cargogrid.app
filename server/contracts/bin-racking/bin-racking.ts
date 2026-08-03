/**
 * Bin and Racking contract (ATW-230, CG-S10-ATW-011). Mirrors
 * supabase/migrations/20260730150000_create_advanced_tms_bin_racking.sql's
 * app.warehouse_locations shape and its create/update/move/status RPCs.
 *
 * location_type is a real closed enum (unlike zone_type/service_type in
 * server/contracts/warehouse-zone/warehouse-zone.ts) -- Prompt 230 itself names the
 * identical six-value set ("rack, shelf, floor, staging, dock, bin") across multiple
 * sections, a repeated sourced taxonomy, not a single test-data mention. environment/
 * restrictions are generic attribute bags mirroring master-data.ts's own
 * MasterAttributesSchema shape, matching server/contracts/warehouse-zone/
 * warehouse-zone.ts's own reuse.
 */

import { z } from "zod";

export const WAREHOUSE_LOCATION_TYPES = ["rack", "shelf", "floor", "staging", "dock", "bin"] as const;
export const WarehouseLocationTypeSchema = z.enum(WAREHOUSE_LOCATION_TYPES);
export type WarehouseLocationType = z.infer<typeof WarehouseLocationTypeSchema>;

export const WAREHOUSE_LOCATION_STATUSES = ["draft", "active", "inactive"] as const;
export const WarehouseLocationStatusSchema = z.enum(WAREHOUSE_LOCATION_STATUSES);
export type WarehouseLocationStatus = z.infer<typeof WarehouseLocationStatusSchema>;

export const WarehouseLocationAttributesSchema = z.record(z.string(), z.unknown());

export const WarehouseLocationSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  warehouseId: z.string().uuid(),
  zoneId: z.string().uuid().nullable(),
  parentId: z.string().uuid().nullable(),
  code: z.string(),
  name: z.string(),
  locationType: WarehouseLocationTypeSchema,
  path: z.array(z.string().uuid()),
  depth: z.number().int().min(0),
  sequence: z.number().int(),
  capacityValue: z.coerce.number().nullable(),
  capacityUom: z.string().nullable(),
  environment: WarehouseLocationAttributesSchema,
  restrictions: WarehouseLocationAttributesSchema,
  barcode: z.string().nullable(),
  pickEnabled: z.boolean(),
  putawayEnabled: z.boolean(),
  status: WarehouseLocationStatusSchema,
  recordVersion: z.number().int().positive(),
  createdBy: z.string().nullable(),
  createdAt: z.string(),
  updatedAt: z.string(),
});
export type WarehouseLocation = z.infer<typeof WarehouseLocationSchema>;

export function parseWarehouseLocation(row: Record<string, unknown>): WarehouseLocation {
  return WarehouseLocationSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    warehouseId: row.warehouse_id,
    zoneId: row.zone_id ?? null,
    parentId: row.parent_id ?? null,
    code: row.code,
    name: row.name,
    locationType: row.location_type,
    path: row.path ?? [],
    depth: row.depth,
    sequence: row.sequence,
    capacityValue: row.capacity_value ?? null,
    capacityUom: row.capacity_uom ?? null,
    environment: row.environment ?? {},
    restrictions: row.restrictions ?? {},
    barcode: row.barcode ?? null,
    pickEnabled: row.pick_enabled,
    putawayEnabled: row.putaway_enabled,
    status: row.status,
    recordVersion: row.record_version,
    createdBy: row.created_by ?? null,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  });
}

export const WarehouseLocationDeactivationImpactSchema = z.object({
  activeChildCount: z.number().int(),
  draftChildCount: z.number().int(),
});
export type WarehouseLocationDeactivationImpact = z.infer<typeof WarehouseLocationDeactivationImpactSchema>;

export function parseWarehouseLocationDeactivationImpact(row: Record<string, unknown>): WarehouseLocationDeactivationImpact {
  return WarehouseLocationDeactivationImpactSchema.parse({
    activeChildCount: row.active_child_count,
    draftChildCount: row.draft_child_count,
  });
}

// --- Mutation input schemas ---

export const CreateWarehouseLocationInputSchema = z.object({
  warehouseId: z.string().uuid(),
  zoneId: z.string().uuid().nullable(),
  parentId: z.string().uuid().nullable(),
  code: z.string().min(1),
  name: z.string().min(1),
  locationType: WarehouseLocationTypeSchema,
  sequence: z.number().int(),
  capacityValue: z.number().min(0).nullable(),
  capacityUom: z.string().nullable(),
  environment: WarehouseLocationAttributesSchema.nullable(),
  restrictions: WarehouseLocationAttributesSchema.nullable(),
  barcode: z.string().nullable(),
  pickEnabled: z.boolean(),
  putawayEnabled: z.boolean(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type CreateWarehouseLocationInput = z.input<typeof CreateWarehouseLocationInputSchema>;

export const UpdateWarehouseLocationInputSchema = z.object({
  locationId: z.string().uuid(),
  name: z.string().min(1),
  sequence: z.number().int(),
  capacityValue: z.number().min(0).nullable(),
  capacityUom: z.string().nullable(),
  environment: WarehouseLocationAttributesSchema.nullable(),
  restrictions: WarehouseLocationAttributesSchema.nullable(),
  barcode: z.string().nullable(),
  pickEnabled: z.boolean(),
  putawayEnabled: z.boolean(),
  expectedVersion: z.number().int().positive(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type UpdateWarehouseLocationInput = z.input<typeof UpdateWarehouseLocationInputSchema>;

export const MoveWarehouseLocationInputSchema = z.object({
  locationId: z.string().uuid(),
  newParentId: z.string().uuid().nullable(),
  expectedVersion: z.number().int().positive(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type MoveWarehouseLocationInput = z.input<typeof MoveWarehouseLocationInputSchema>;

export const SetWarehouseLocationStatusInputSchema = z.object({
  locationId: z.string().uuid(),
  newStatus: WarehouseLocationStatusSchema,
  reason: z.string().nullable(),
  expectedVersion: z.number().int().positive(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type SetWarehouseLocationStatusInput = z.input<typeof SetWarehouseLocationStatusInputSchema>;
