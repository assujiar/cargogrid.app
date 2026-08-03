/**
 * Warehouse and Zone contract (ATW-229, CG-S10-ATW-010). Mirrors
 * supabase/migrations/20260730140000_create_advanced_tms_warehouse_zone.sql's
 * app.warehouses/app.warehouse_zones/app.warehouse_customer_eligibility shapes and
 * their create/update/status/eligibility RPCs.
 *
 * zoneType/serviceTypeEligibility are free text (that migration's own design note 2 --
 * matching service_type's own established free-text convention elsewhere in this
 * repository), never a hard-coded enum. environment/restrictions are generic attribute
 * bags (design note 3), mirroring server/contracts/master-data/master-data.ts's own
 * MasterAttributesSchema shape.
 */

import { z } from "zod";

export const WAREHOUSE_STATUSES = ["active", "inactive"] as const;
export const WarehouseStatusSchema = z.enum(WAREHOUSE_STATUSES);
export type WarehouseStatus = z.infer<typeof WarehouseStatusSchema>;

export const WAREHOUSE_ZONE_STATUSES = ["active", "inactive", "on_hold"] as const;
export const WarehouseZoneStatusSchema = z.enum(WAREHOUSE_ZONE_STATUSES);
export type WarehouseZoneStatus = z.infer<typeof WarehouseZoneStatusSchema>;

export const WAREHOUSE_CUSTOMER_ELIGIBILITY_STATUSES = ["active", "revoked"] as const;
export const WarehouseCustomerEligibilityStatusSchema = z.enum(WAREHOUSE_CUSTOMER_ELIGIBILITY_STATUSES);
export type WarehouseCustomerEligibilityStatus = z.infer<typeof WarehouseCustomerEligibilityStatusSchema>;

export const WarehouseGeoJsonPointSchema = z.object({
  type: z.literal("Point"),
  coordinates: z.tuple([z.number(), z.number()]),
});
export type WarehouseGeoJsonPoint = z.infer<typeof WarehouseGeoJsonPointSchema>;

export const WarehouseAttributesSchema = z.record(z.string(), z.unknown());

export const WarehouseSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  companyOrgUnitId: z.string().uuid(),
  code: z.string(),
  name: z.string(),
  siteAddress: z.string().nullable(),
  timezone: z.string(),
  siteGeojson: WarehouseGeoJsonPointSchema.nullable(),
  serviceTypeEligibility: z.array(z.string()),
  status: WarehouseStatusSchema,
  recordVersion: z.number().int().positive(),
  createdBy: z.string().nullable(),
  createdAt: z.string(),
  updatedAt: z.string(),
});
export type Warehouse = z.infer<typeof WarehouseSchema>;

/**
 * A create/update/status-change mutation returns the raw app.warehouses row, which
 * carries a `site_geog` PostGIS geography column, not GeoJSON -- the same "mutation
 * responses never carry a parsed geometry" boundary
 * server/contracts/multi-leg-shipment/multi-leg-shipment.ts's own parseShipmentLegStop
 * already established (its own callers pass `location_geojson: null` explicitly).
 * Every mutation wrapper below passes `site_geog_geojson: null` for the same reason;
 * only app.list_tenant_warehouses' own read projection carries a real parsed point.
 */
export function parseWarehouse(row: Record<string, unknown>): Warehouse {
  return WarehouseSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    companyOrgUnitId: row.company_org_unit_id,
    code: row.code,
    name: row.name,
    siteAddress: row.site_address ?? null,
    timezone: row.timezone,
    siteGeojson: row.site_geog_geojson ?? null,
    serviceTypeEligibility: row.service_type_eligibility ?? [],
    status: row.status,
    recordVersion: row.record_version,
    createdBy: row.created_by ?? null,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  });
}

export const WarehouseZoneSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  warehouseId: z.string().uuid(),
  code: z.string(),
  name: z.string(),
  zoneType: z.string(),
  environment: WarehouseAttributesSchema,
  capacityValue: z.coerce.number().nullable(),
  capacityUom: z.string().nullable(),
  restrictions: WarehouseAttributesSchema,
  status: WarehouseZoneStatusSchema,
  effectiveFrom: z.string().nullable(),
  effectiveTo: z.string().nullable(),
  recordVersion: z.number().int().positive(),
  createdBy: z.string().nullable(),
  createdAt: z.string(),
  updatedAt: z.string(),
});
export type WarehouseZone = z.infer<typeof WarehouseZoneSchema>;

export function parseWarehouseZone(row: Record<string, unknown>): WarehouseZone {
  return WarehouseZoneSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    warehouseId: row.warehouse_id,
    code: row.code,
    name: row.name,
    zoneType: row.zone_type,
    environment: row.environment ?? {},
    capacityValue: row.capacity_value ?? null,
    capacityUom: row.capacity_uom ?? null,
    restrictions: row.restrictions ?? {},
    status: row.status,
    effectiveFrom: row.effective_from ?? null,
    effectiveTo: row.effective_to ?? null,
    recordVersion: row.record_version,
    createdBy: row.created_by ?? null,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  });
}

export const WarehouseCustomerEligibilitySchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  warehouseId: z.string().uuid(),
  customerAccountId: z.string().uuid(),
  status: WarehouseCustomerEligibilityStatusSchema,
  grantedBy: z.string().nullable(),
  grantedAt: z.string(),
  revokedAt: z.string().nullable(),
  revokedReason: z.string().nullable(),
  recordVersion: z.number().int().positive(),
});
export type WarehouseCustomerEligibility = z.infer<typeof WarehouseCustomerEligibilitySchema>;

export function parseWarehouseCustomerEligibility(row: Record<string, unknown>): WarehouseCustomerEligibility {
  return WarehouseCustomerEligibilitySchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    warehouseId: row.warehouse_id,
    customerAccountId: row.customer_account_id,
    status: row.status,
    grantedBy: row.granted_by ?? null,
    grantedAt: row.granted_at,
    revokedAt: row.revoked_at ?? null,
    revokedReason: row.revoked_reason ?? null,
    recordVersion: row.record_version,
  });
}

// --- Read projections ---

export const TenantWarehouseListRowSchema = z.object({
  id: z.string().uuid(),
  companyOrgUnitId: z.string().uuid(),
  code: z.string(),
  name: z.string(),
  siteAddress: z.string().nullable(),
  timezone: z.string(),
  siteGeojson: WarehouseGeoJsonPointSchema.nullable(),
  serviceTypeEligibility: z.array(z.string()),
  status: WarehouseStatusSchema,
  zoneCount: z.number().int(),
  activeZoneCount: z.number().int(),
  recordVersion: z.number().int().positive(),
  createdAt: z.string(),
  updatedAt: z.string(),
});
export type TenantWarehouseListRow = z.infer<typeof TenantWarehouseListRowSchema>;

export function parseTenantWarehouseListRow(row: Record<string, unknown>): TenantWarehouseListRow {
  return TenantWarehouseListRowSchema.parse({
    id: row.id,
    companyOrgUnitId: row.company_org_unit_id,
    code: row.code,
    name: row.name,
    siteAddress: row.site_address ?? null,
    timezone: row.timezone,
    siteGeojson: row.site_geog_geojson ?? null,
    serviceTypeEligibility: row.service_type_eligibility ?? [],
    status: row.status,
    zoneCount: row.zone_count,
    activeZoneCount: row.active_zone_count,
    recordVersion: row.record_version,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  });
}

export const WarehouseCustomerEligibilityListRowSchema = z.object({
  id: z.string().uuid(),
  warehouseId: z.string().uuid(),
  customerAccountId: z.string().uuid(),
  customerLegalName: z.string(),
  status: WarehouseCustomerEligibilityStatusSchema,
  grantedBy: z.string().nullable(),
  grantedAt: z.string(),
  revokedAt: z.string().nullable(),
  revokedReason: z.string().nullable(),
  recordVersion: z.number().int().positive(),
});
export type WarehouseCustomerEligibilityListRow = z.infer<typeof WarehouseCustomerEligibilityListRowSchema>;

export function parseWarehouseCustomerEligibilityListRow(row: Record<string, unknown>): WarehouseCustomerEligibilityListRow {
  return WarehouseCustomerEligibilityListRowSchema.parse({
    id: row.id,
    warehouseId: row.warehouse_id,
    customerAccountId: row.customer_account_id,
    customerLegalName: row.customer_legal_name,
    status: row.status,
    grantedBy: row.granted_by ?? null,
    grantedAt: row.granted_at,
    revokedAt: row.revoked_at ?? null,
    revokedReason: row.revoked_reason ?? null,
    recordVersion: row.record_version,
  });
}

export const WarehouseDeactivationImpactSchema = z.object({
  activeZoneCount: z.number().int(),
  onHoldZoneCount: z.number().int(),
  activeCustomerEligibilityCount: z.number().int(),
});
export type WarehouseDeactivationImpact = z.infer<typeof WarehouseDeactivationImpactSchema>;

export function parseWarehouseDeactivationImpact(row: Record<string, unknown>): WarehouseDeactivationImpact {
  return WarehouseDeactivationImpactSchema.parse({
    activeZoneCount: row.active_zone_count,
    onHoldZoneCount: row.on_hold_zone_count,
    activeCustomerEligibilityCount: row.active_customer_eligibility_count,
  });
}

// --- Mutation input schemas ---

export const CreateWarehouseInputSchema = z.object({
  tenantId: z.string().uuid(),
  companyOrgUnitId: z.string().uuid(),
  code: z.string().min(1),
  name: z.string().min(1),
  siteAddress: z.string().nullable(),
  timezone: z.string().min(1),
  siteGeojson: WarehouseGeoJsonPointSchema.nullable(),
  serviceTypeEligibility: z.array(z.string()),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type CreateWarehouseInput = z.input<typeof CreateWarehouseInputSchema>;

export const UpdateWarehouseInputSchema = z.object({
  warehouseId: z.string().uuid(),
  name: z.string().min(1),
  siteAddress: z.string().nullable(),
  timezone: z.string().min(1),
  siteGeojson: WarehouseGeoJsonPointSchema.nullable(),
  serviceTypeEligibility: z.array(z.string()),
  expectedVersion: z.number().int().positive(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type UpdateWarehouseInput = z.input<typeof UpdateWarehouseInputSchema>;

export const SetWarehouseStatusInputSchema = z.object({
  warehouseId: z.string().uuid(),
  newStatus: WarehouseStatusSchema,
  reason: z.string().nullable(),
  expectedVersion: z.number().int().positive(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type SetWarehouseStatusInput = z.input<typeof SetWarehouseStatusInputSchema>;

export const GrantWarehouseCustomerEligibilityInputSchema = z.object({
  warehouseId: z.string().uuid(),
  customerAccountId: z.string().uuid(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type GrantWarehouseCustomerEligibilityInput = z.input<typeof GrantWarehouseCustomerEligibilityInputSchema>;

export const RevokeWarehouseCustomerEligibilityInputSchema = z.object({
  id: z.string().uuid(),
  reason: z.string().min(1),
  expectedVersion: z.number().int().positive(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type RevokeWarehouseCustomerEligibilityInput = z.input<typeof RevokeWarehouseCustomerEligibilityInputSchema>;

export const CreateWarehouseZoneInputSchema = z.object({
  warehouseId: z.string().uuid(),
  code: z.string().min(1),
  name: z.string().min(1),
  zoneType: z.string().min(1),
  environment: WarehouseAttributesSchema.nullable(),
  capacityValue: z.number().min(0).nullable(),
  capacityUom: z.string().nullable(),
  restrictions: WarehouseAttributesSchema.nullable(),
  effectiveFrom: z.string().nullable(),
  effectiveTo: z.string().nullable(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type CreateWarehouseZoneInput = z.input<typeof CreateWarehouseZoneInputSchema>;

export const UpdateWarehouseZoneInputSchema = z.object({
  zoneId: z.string().uuid(),
  name: z.string().min(1),
  environment: WarehouseAttributesSchema.nullable(),
  capacityValue: z.number().min(0).nullable(),
  capacityUom: z.string().nullable(),
  restrictions: WarehouseAttributesSchema.nullable(),
  effectiveFrom: z.string().nullable(),
  effectiveTo: z.string().nullable(),
  expectedVersion: z.number().int().positive(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type UpdateWarehouseZoneInput = z.input<typeof UpdateWarehouseZoneInputSchema>;

export const SetWarehouseZoneStatusInputSchema = z.object({
  zoneId: z.string().uuid(),
  newStatus: WarehouseZoneStatusSchema,
  reason: z.string().nullable(),
  expectedVersion: z.number().int().positive(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type SetWarehouseZoneStatusInput = z.input<typeof SetWarehouseZoneStatusInputSchema>;
