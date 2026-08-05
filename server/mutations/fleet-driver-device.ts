/**
 * Fleet, Vehicle, Driver, Device and SIM Operational Baseline mutation primitives
 * (ATW-223, CG-S10-ATW-004). Thin, typed wrappers around the RPCs in
 * supabase/migrations/20260729310000_create_advanced_tms_fleet_driver_device.sql.
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import {
  RegisterVehicleOperationalProfileInputSchema,
  SetVehicleTrackingEligibilityInputSchema,
  RegisterDriverOperationalProfileInputSchema,
  SetDriverMobileTrackingConsentInputSchema,
  RegisterGpsDeviceInputSchema,
  TransitionGpsDeviceStatusInputSchema,
  AssignDeviceToVehicleInputSchema,
  UnassignDeviceFromVehicleInputSchema,
  RegisterSimCardInputSchema,
  AssignSimToDeviceInputSchema,
  UnassignSimFromDeviceInputSchema,
  RegisterProviderVehicleMappingInputSchema,
  SetVehicleTrackingSourcePriorityInputSchema,
  parseVehicleOperationalProfile,
  parseDriverOperationalProfile,
  parseGpsDevice,
  parseSimCard,
  parseDeviceVehicleAssignment,
  parseProviderVehicleMapping,
  parseVehicleTrackingSourcePriority,
  type RegisterVehicleOperationalProfileInput,
  type SetVehicleTrackingEligibilityInput,
  type RegisterDriverOperationalProfileInput,
  type SetDriverMobileTrackingConsentInput,
  type RegisterGpsDeviceInput,
  type TransitionGpsDeviceStatusInput,
  type AssignDeviceToVehicleInput,
  type UnassignDeviceFromVehicleInput,
  type RegisterSimCardInput,
  type AssignSimToDeviceInput,
  type UnassignSimFromDeviceInput,
  type RegisterProviderVehicleMappingInput,
  type SetVehicleTrackingSourcePriorityInput,
  type VehicleOperationalProfile,
  type DriverOperationalProfile,
  type GpsDevice,
  type SimCard,
  type DeviceVehicleAssignment,
  type ProviderVehicleMapping,
  type VehicleTrackingSourcePriority,
} from "../contracts/fleet-driver-device/fleet-driver-device.ts";

export type FleetDriverDeviceMutationRpcClient = Pick<SupabaseClient, "rpc">;

export const FLEET_DRIVER_DEVICE_KNOWN_MUTATION_ERROR_CODES = [
  "insufficient_authority",
  "invalid_ownership_type",
  "vehicle_profile_not_found",
  "stale_version",
  "driver_profile_not_found",
  "imei_required",
  "device_not_found",
  "invalid_device_status_transition",
  "device_retired",
  "tenant_mismatch",
  "unassign_reason_required",
  "no_current_assignment",
  "iccid_required",
  "sim_not_found",
  "device_already_has_sim",
  "vehicle_not_found",
  "provider_external_id_collision",
  "invalid_source_type",
  "invalid_priority_rank",
] as const;
type KnownFleetDriverDeviceMutationErrorCode = (typeof FLEET_DRIVER_DEVICE_KNOWN_MUTATION_ERROR_CODES)[number];
export type FleetDriverDeviceMutationErrorCode = KnownFleetDriverDeviceMutationErrorCode | "mutation_failed" | "invalid_response";

export class FleetDriverDeviceMutationError extends Error {
  readonly code: FleetDriverDeviceMutationErrorCode;

  constructor(code: FleetDriverDeviceMutationErrorCode, message: string) {
    super(message);
    this.name = "FleetDriverDeviceMutationError";
    this.code = code;
  }
}

function classifyError(message: string): FleetDriverDeviceMutationErrorCode {
  const prefix = message.split(":")[0]?.trim();
  return (FLEET_DRIVER_DEVICE_KNOWN_MUTATION_ERROR_CODES as readonly string[]).includes(prefix ?? "")
    ? (prefix as KnownFleetDriverDeviceMutationErrorCode)
    : "mutation_failed";
}

async function callRpc(client: FleetDriverDeviceMutationRpcClient, fn: string, args: Record<string, unknown>): Promise<Record<string, unknown>> {
  const { data, error } = await client.rpc(fn, args);
  if (error) {
    throw new FleetDriverDeviceMutationError(classifyError(error.message), error.message);
  }
  if (!data || typeof data !== "object") {
    throw new FleetDriverDeviceMutationError("invalid_response", `${fn} returned no row`);
  }
  return data as Record<string, unknown>;
}

export async function registerVehicleOperationalProfile(
  client: FleetDriverDeviceMutationRpcClient,
  input: RegisterVehicleOperationalProfileInput,
): Promise<VehicleOperationalProfile> {
  const parsedInput = RegisterVehicleOperationalProfileInputSchema.parse(input);
  const row = await callRpc(client, "register_vehicle_operational_profile", {
    p_tenant_id: parsedInput.tenantId,
    p_code: parsedInput.code,
    p_name: parsedInput.name,
    p_ownership_type: parsedInput.ownershipType,
    p_capacity_weight_kg: parsedInput.capacityWeightKg,
    p_capacity_volume_cbm: parsedInput.capacityVolumeCbm,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  return parseVehicleOperationalProfile(row);
}

export async function setVehicleTrackingEligibility(
  client: FleetDriverDeviceMutationRpcClient,
  input: SetVehicleTrackingEligibilityInput,
): Promise<VehicleOperationalProfile> {
  const parsedInput = SetVehicleTrackingEligibilityInputSchema.parse(input);
  const row = await callRpc(client, "set_vehicle_tracking_eligibility", {
    p_vehicle_profile_id: parsedInput.vehicleProfileId,
    p_mobile_eligible: parsedInput.mobileEligible,
    p_direct_device_eligible: parsedInput.directDeviceEligible,
    p_third_party_eligible: parsedInput.thirdPartyEligible,
    p_expected_version: parsedInput.expectedVersion,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  return parseVehicleOperationalProfile(row);
}

export async function registerDriverOperationalProfile(
  client: FleetDriverDeviceMutationRpcClient,
  input: RegisterDriverOperationalProfileInput,
): Promise<DriverOperationalProfile> {
  const parsedInput = RegisterDriverOperationalProfileInputSchema.parse(input);
  const row = await callRpc(client, "register_driver_operational_profile", {
    p_tenant_id: parsedInput.tenantId,
    p_code: parsedInput.code,
    p_name: parsedInput.name,
    p_license_class: parsedInput.licenseClass,
    p_license_expiry_date: parsedInput.licenseExpiryDate,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  return parseDriverOperationalProfile(row);
}

export async function setDriverMobileTrackingConsent(
  client: FleetDriverDeviceMutationRpcClient,
  input: SetDriverMobileTrackingConsentInput,
): Promise<DriverOperationalProfile> {
  const parsedInput = SetDriverMobileTrackingConsentInputSchema.parse(input);
  const row = await callRpc(client, "set_driver_mobile_tracking_consent", {
    p_driver_profile_id: parsedInput.driverProfileId,
    p_consent: parsedInput.consent,
    p_expected_version: parsedInput.expectedVersion,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  return parseDriverOperationalProfile(row);
}

export async function registerGpsDevice(client: FleetDriverDeviceMutationRpcClient, input: RegisterGpsDeviceInput): Promise<GpsDevice> {
  const parsedInput = RegisterGpsDeviceInputSchema.parse(input);
  const row = await callRpc(client, "register_gps_device", {
    p_tenant_id: parsedInput.tenantId,
    p_imei: parsedInput.imei,
    p_device_model: parsedInput.deviceModel,
    p_ownership_type: parsedInput.ownershipType,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  return parseGpsDevice(row);
}

export async function transitionGpsDeviceStatus(client: FleetDriverDeviceMutationRpcClient, input: TransitionGpsDeviceStatusInput): Promise<GpsDevice> {
  const parsedInput = TransitionGpsDeviceStatusInputSchema.parse(input);
  // ATW-031 (ISS-2026-028): app.transition_gps_device_status is no longer granted to
  // authenticated -- it is the internal status-machine core. Clients go through this
  // entry point, which refuses the evidence-mandatory "installed" transition; that one
  // belongs exclusively to app.record_gps_device_installation (ATW-226B).
  const row = await callRpc(client, "request_gps_device_status_transition", {
    p_device_id: parsedInput.deviceId,
    p_to_status: parsedInput.toStatus,
    p_expected_version: parsedInput.expectedVersion,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  return parseGpsDevice(row);
}

export async function assignDeviceToVehicle(client: FleetDriverDeviceMutationRpcClient, input: AssignDeviceToVehicleInput): Promise<DeviceVehicleAssignment> {
  const parsedInput = AssignDeviceToVehicleInputSchema.parse(input);
  const row = await callRpc(client, "assign_device_to_vehicle", {
    p_device_id: parsedInput.deviceId,
    p_vehicle_profile_id: parsedInput.vehicleProfileId,
    p_reason: parsedInput.reason,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  return parseDeviceVehicleAssignment(row);
}

export async function unassignDeviceFromVehicle(
  client: FleetDriverDeviceMutationRpcClient,
  input: UnassignDeviceFromVehicleInput,
): Promise<DeviceVehicleAssignment> {
  const parsedInput = UnassignDeviceFromVehicleInputSchema.parse(input);
  const row = await callRpc(client, "unassign_device_from_vehicle", {
    p_device_id: parsedInput.deviceId,
    p_reason: parsedInput.reason,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  return parseDeviceVehicleAssignment(row);
}

export async function registerSimCard(client: FleetDriverDeviceMutationRpcClient, input: RegisterSimCardInput): Promise<SimCard> {
  const parsedInput = RegisterSimCardInputSchema.parse(input);
  const row = await callRpc(client, "register_sim_card", {
    p_tenant_id: parsedInput.tenantId,
    p_iccid: parsedInput.iccid,
    p_msisdn: parsedInput.msisdn,
    p_carrier: parsedInput.carrier,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  return parseSimCard(row);
}

export async function assignSimToDevice(client: FleetDriverDeviceMutationRpcClient, input: AssignSimToDeviceInput): Promise<SimCard> {
  const parsedInput = AssignSimToDeviceInputSchema.parse(input);
  const row = await callRpc(client, "assign_sim_to_device", {
    p_sim_id: parsedInput.simId,
    p_device_id: parsedInput.deviceId,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  return parseSimCard(row);
}

export async function unassignSimFromDevice(client: FleetDriverDeviceMutationRpcClient, input: UnassignSimFromDeviceInput): Promise<SimCard> {
  const parsedInput = UnassignSimFromDeviceInputSchema.parse(input);
  const row = await callRpc(client, "unassign_sim_from_device", {
    p_sim_id: parsedInput.simId,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  return parseSimCard(row);
}

export async function registerProviderVehicleMapping(
  client: FleetDriverDeviceMutationRpcClient,
  input: RegisterProviderVehicleMappingInput,
): Promise<ProviderVehicleMapping> {
  const parsedInput = RegisterProviderVehicleMappingInputSchema.parse(input);
  const row = await callRpc(client, "register_provider_vehicle_mapping", {
    p_tenant_id: parsedInput.tenantId,
    p_vehicle_master_id: parsedInput.vehicleMasterId,
    p_provider_code: parsedInput.providerCode,
    p_external_vehicle_id: parsedInput.externalVehicleId,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  return parseProviderVehicleMapping(row);
}

export async function setVehicleTrackingSourcePriority(
  client: FleetDriverDeviceMutationRpcClient,
  input: SetVehicleTrackingSourcePriorityInput,
): Promise<VehicleTrackingSourcePriority> {
  const parsedInput = SetVehicleTrackingSourcePriorityInputSchema.parse(input);
  const row = await callRpc(client, "set_vehicle_tracking_source_priority", {
    p_tenant_id: parsedInput.tenantId,
    p_vehicle_master_id: parsedInput.vehicleMasterId,
    p_source_type: parsedInput.sourceType,
    p_priority_rank: parsedInput.priorityRank,
    p_is_enabled: parsedInput.isEnabled,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  return parseVehicleTrackingSourcePriority(row);
}
