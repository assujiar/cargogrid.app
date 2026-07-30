/**
 * Fleet, Vehicle, Driver, Device and SIM Operational Baseline contract (ATW-223,
 * CG-S10-ATW-004). Mirrors
 * supabase/migrations/20260729310000_create_advanced_tms_fleet_driver_device.sql's
 * table shapes and RPCs.
 *
 * Vehicle/driver identity is not duplicated here -- vehicleMasterId/driverMasterId
 * always reference an existing app.master_records row (master_type_code
 * 'vehicle'/'driver', OPS-172). These schemas model only the new operational layer:
 * capacity, ownership, tracking-mode eligibility (a capability flag, never an
 * entitlement decision), device/SIM inventory and assignment, provider mapping, and
 * declared source-priority policy.
 */

import { z } from "zod";

export const VEHICLE_OWNERSHIP_TYPES = ["owned", "leased", "vendor", "rental", "ad_hoc"] as const;
export const VehicleOwnershipTypeSchema = z.enum(VEHICLE_OWNERSHIP_TYPES);
export type VehicleOwnershipType = z.infer<typeof VehicleOwnershipTypeSchema>;

export const VEHICLE_PROFILE_STATUSES = ["active", "inactive", "maintenance", "retired"] as const;
export const VehicleProfileStatusSchema = z.enum(VEHICLE_PROFILE_STATUSES);
export type VehicleProfileStatus = z.infer<typeof VehicleProfileStatusSchema>;

export const DRIVER_PROFILE_STATUSES = ["active", "inactive", "suspended", "retired"] as const;
export const DriverProfileStatusSchema = z.enum(DRIVER_PROFILE_STATUSES);
export type DriverProfileStatus = z.infer<typeof DriverProfileStatusSchema>;

export const DEVICE_OWNERSHIP_TYPES = ["cargogrid", "customer", "partner"] as const;
export const DeviceOwnershipTypeSchema = z.enum(DEVICE_OWNERSHIP_TYPES);
export type DeviceOwnershipType = z.infer<typeof DeviceOwnershipTypeSchema>;

export const GPS_DEVICE_STATUSES = ["stock", "assigned", "installed", "active", "offline", "suspended", "maintenance", "retired"] as const;
export const GpsDeviceStatusSchema = z.enum(GPS_DEVICE_STATUSES);
export type GpsDeviceStatus = z.infer<typeof GpsDeviceStatusSchema>;

export const SIM_CARD_STATUSES = ["stock", "assigned", "active", "suspended", "retired"] as const;
export const SimCardStatusSchema = z.enum(SIM_CARD_STATUSES);
export type SimCardStatus = z.infer<typeof SimCardStatusSchema>;

export const TRACKING_SOURCE_TYPES = ["driver_mobile", "direct_device", "third_party_platform"] as const;
export const TrackingSourceTypeSchema = z.enum(TRACKING_SOURCE_TYPES);
export type TrackingSourceType = z.infer<typeof TrackingSourceTypeSchema>;

export const VehicleOperationalProfileSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  vehicleMasterId: z.string().uuid(),
  ownershipType: VehicleOwnershipTypeSchema,
  capacityWeightKg: z.coerce.number().nullable(),
  capacityVolumeCbm: z.coerce.number().nullable(),
  mobileTrackingEligible: z.boolean(),
  directDeviceTrackingEligible: z.boolean(),
  thirdPartyTrackingEligible: z.boolean(),
  status: VehicleProfileStatusSchema,
  recordVersion: z.number().int().positive(),
  createdBy: z.string().nullable(),
  createdAt: z.string(),
  updatedAt: z.string(),
});
export type VehicleOperationalProfile = z.infer<typeof VehicleOperationalProfileSchema>;

export function parseVehicleOperationalProfile(row: Record<string, unknown>): VehicleOperationalProfile {
  return VehicleOperationalProfileSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    vehicleMasterId: row.vehicle_master_id,
    ownershipType: row.ownership_type,
    capacityWeightKg: row.capacity_weight_kg ?? null,
    capacityVolumeCbm: row.capacity_volume_cbm ?? null,
    mobileTrackingEligible: row.mobile_tracking_eligible,
    directDeviceTrackingEligible: row.direct_device_tracking_eligible,
    thirdPartyTrackingEligible: row.third_party_tracking_eligible,
    status: row.status,
    recordVersion: row.record_version,
    createdBy: row.created_by ?? null,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  });
}

export const DriverOperationalProfileSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  driverMasterId: z.string().uuid(),
  licenseClass: z.string().nullable(),
  licenseExpiryDate: z.string().nullable(),
  mobileTrackingConsent: z.boolean(),
  mobileTrackingConsentAt: z.string().nullable(),
  status: DriverProfileStatusSchema,
  recordVersion: z.number().int().positive(),
  createdBy: z.string().nullable(),
  createdAt: z.string(),
  updatedAt: z.string(),
});
export type DriverOperationalProfile = z.infer<typeof DriverOperationalProfileSchema>;

export function parseDriverOperationalProfile(row: Record<string, unknown>): DriverOperationalProfile {
  return DriverOperationalProfileSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    driverMasterId: row.driver_master_id,
    licenseClass: row.license_class ?? null,
    licenseExpiryDate: row.license_expiry_date ?? null,
    mobileTrackingConsent: row.mobile_tracking_consent,
    mobileTrackingConsentAt: row.mobile_tracking_consent_at ?? null,
    status: row.status,
    recordVersion: row.record_version,
    createdBy: row.created_by ?? null,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  });
}

export const GpsDeviceSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  imei: z.string(),
  deviceModel: z.string(),
  ownershipType: DeviceOwnershipTypeSchema,
  status: GpsDeviceStatusSchema,
  recordVersion: z.number().int().positive(),
  createdBy: z.string().nullable(),
  createdAt: z.string(),
  updatedAt: z.string(),
});
export type GpsDevice = z.infer<typeof GpsDeviceSchema>;

export function parseGpsDevice(row: Record<string, unknown>): GpsDevice {
  return GpsDeviceSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    imei: row.imei,
    deviceModel: row.device_model,
    ownershipType: row.ownership_type,
    status: row.status,
    recordVersion: row.record_version,
    createdBy: row.created_by ?? null,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  });
}

export const SimCardSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  iccid: z.string(),
  msisdn: z.string().nullable(),
  carrier: z.string().nullable(),
  status: SimCardStatusSchema,
  currentDeviceId: z.string().uuid().nullable(),
  recordVersion: z.number().int().positive(),
  createdBy: z.string().nullable(),
  createdAt: z.string(),
  updatedAt: z.string(),
});
export type SimCard = z.infer<typeof SimCardSchema>;

export function parseSimCard(row: Record<string, unknown>): SimCard {
  return SimCardSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    iccid: row.iccid,
    msisdn: row.msisdn ?? null,
    carrier: row.carrier ?? null,
    status: row.status,
    currentDeviceId: row.current_device_id ?? null,
    recordVersion: row.record_version,
    createdBy: row.created_by ?? null,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  });
}

export const DeviceVehicleAssignmentSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  deviceId: z.string().uuid(),
  vehicleOperationalProfileId: z.string().uuid(),
  isCurrent: z.boolean(),
  effectiveFrom: z.string(),
  effectiveTo: z.string().nullable(),
  reason: z.string().nullable(),
  supersededById: z.string().uuid().nullable(),
  createdBy: z.string().nullable(),
  createdAt: z.string(),
});
export type DeviceVehicleAssignment = z.infer<typeof DeviceVehicleAssignmentSchema>;

export function parseDeviceVehicleAssignment(row: Record<string, unknown>): DeviceVehicleAssignment {
  return DeviceVehicleAssignmentSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    deviceId: row.device_id,
    vehicleOperationalProfileId: row.vehicle_operational_profile_id,
    isCurrent: row.is_current,
    effectiveFrom: row.effective_from,
    effectiveTo: row.effective_to ?? null,
    reason: row.reason ?? null,
    supersededById: row.superseded_by_id ?? null,
    createdBy: row.created_by ?? null,
    createdAt: row.created_at,
  });
}

export const ProviderVehicleMappingSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  vehicleMasterId: z.string().uuid(),
  providerCode: z.string(),
  externalVehicleId: z.string(),
  status: z.enum(["active", "inactive"]),
  recordVersion: z.number().int().positive(),
  createdBy: z.string().nullable(),
  createdAt: z.string(),
  updatedAt: z.string(),
});
export type ProviderVehicleMapping = z.infer<typeof ProviderVehicleMappingSchema>;

export function parseProviderVehicleMapping(row: Record<string, unknown>): ProviderVehicleMapping {
  return ProviderVehicleMappingSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    vehicleMasterId: row.vehicle_master_id,
    providerCode: row.provider_code,
    externalVehicleId: row.external_vehicle_id,
    status: row.status,
    recordVersion: row.record_version,
    createdBy: row.created_by ?? null,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  });
}

export const VehicleTrackingSourcePrioritySchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  vehicleMasterId: z.string().uuid(),
  sourceType: TrackingSourceTypeSchema,
  priorityRank: z.number().int().positive(),
  isEnabled: z.boolean(),
  recordVersion: z.number().int().positive(),
  createdBy: z.string().nullable(),
  createdAt: z.string(),
  updatedAt: z.string(),
});
export type VehicleTrackingSourcePriority = z.infer<typeof VehicleTrackingSourcePrioritySchema>;

export function parseVehicleTrackingSourcePriority(row: Record<string, unknown>): VehicleTrackingSourcePriority {
  return VehicleTrackingSourcePrioritySchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    vehicleMasterId: row.vehicle_master_id,
    sourceType: row.source_type,
    priorityRank: row.priority_rank,
    isEnabled: row.is_enabled,
    recordVersion: row.record_version,
    createdBy: row.created_by ?? null,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  });
}

// --- Mutation input schemas ---

export const RegisterVehicleOperationalProfileInputSchema = z.object({
  tenantId: z.string().uuid(),
  code: z.string().min(1),
  name: z.string().min(1),
  ownershipType: VehicleOwnershipTypeSchema,
  capacityWeightKg: z.number().nullable(),
  capacityVolumeCbm: z.number().nullable(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type RegisterVehicleOperationalProfileInput = z.input<typeof RegisterVehicleOperationalProfileInputSchema>;

export const SetVehicleTrackingEligibilityInputSchema = z.object({
  vehicleProfileId: z.string().uuid(),
  mobileEligible: z.boolean(),
  directDeviceEligible: z.boolean(),
  thirdPartyEligible: z.boolean(),
  expectedVersion: z.number().int().positive(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type SetVehicleTrackingEligibilityInput = z.input<typeof SetVehicleTrackingEligibilityInputSchema>;

export const RegisterDriverOperationalProfileInputSchema = z.object({
  tenantId: z.string().uuid(),
  code: z.string().min(1),
  name: z.string().min(1),
  licenseClass: z.string().nullable(),
  licenseExpiryDate: z.string().nullable(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type RegisterDriverOperationalProfileInput = z.input<typeof RegisterDriverOperationalProfileInputSchema>;

export const SetDriverMobileTrackingConsentInputSchema = z.object({
  driverProfileId: z.string().uuid(),
  consent: z.boolean(),
  expectedVersion: z.number().int().positive(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type SetDriverMobileTrackingConsentInput = z.input<typeof SetDriverMobileTrackingConsentInputSchema>;

export const RegisterGpsDeviceInputSchema = z.object({
  tenantId: z.string().uuid(),
  imei: z.string().min(1),
  deviceModel: z.string().min(1),
  ownershipType: DeviceOwnershipTypeSchema,
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type RegisterGpsDeviceInput = z.input<typeof RegisterGpsDeviceInputSchema>;

export const TransitionGpsDeviceStatusInputSchema = z.object({
  deviceId: z.string().uuid(),
  toStatus: GpsDeviceStatusSchema,
  expectedVersion: z.number().int().positive(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type TransitionGpsDeviceStatusInput = z.input<typeof TransitionGpsDeviceStatusInputSchema>;

export const AssignDeviceToVehicleInputSchema = z.object({
  deviceId: z.string().uuid(),
  vehicleProfileId: z.string().uuid(),
  reason: z.string().nullable(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type AssignDeviceToVehicleInput = z.input<typeof AssignDeviceToVehicleInputSchema>;

export const UnassignDeviceFromVehicleInputSchema = z.object({
  deviceId: z.string().uuid(),
  reason: z.string().min(1),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type UnassignDeviceFromVehicleInput = z.input<typeof UnassignDeviceFromVehicleInputSchema>;

export const RegisterSimCardInputSchema = z.object({
  tenantId: z.string().uuid(),
  iccid: z.string().min(1),
  msisdn: z.string().nullable(),
  carrier: z.string().nullable(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type RegisterSimCardInput = z.input<typeof RegisterSimCardInputSchema>;

export const AssignSimToDeviceInputSchema = z.object({
  simId: z.string().uuid(),
  deviceId: z.string().uuid(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type AssignSimToDeviceInput = z.input<typeof AssignSimToDeviceInputSchema>;

export const UnassignSimFromDeviceInputSchema = z.object({
  simId: z.string().uuid(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type UnassignSimFromDeviceInput = z.input<typeof UnassignSimFromDeviceInputSchema>;

export const RegisterProviderVehicleMappingInputSchema = z.object({
  tenantId: z.string().uuid(),
  vehicleMasterId: z.string().uuid(),
  providerCode: z.string().min(1),
  externalVehicleId: z.string().min(1),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type RegisterProviderVehicleMappingInput = z.input<typeof RegisterProviderVehicleMappingInputSchema>;

export const SetVehicleTrackingSourcePriorityInputSchema = z.object({
  tenantId: z.string().uuid(),
  vehicleMasterId: z.string().uuid(),
  sourceType: TrackingSourceTypeSchema,
  priorityRank: z.number().int().positive(),
  isEnabled: z.boolean(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type SetVehicleTrackingSourcePriorityInput = z.input<typeof SetVehicleTrackingSourcePriorityInputSchema>;
