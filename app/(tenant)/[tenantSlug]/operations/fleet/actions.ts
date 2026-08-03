"use server";

/**
 * Fleet, Vehicle, Driver, Device and SIM Operational Baseline Server Actions
 * (ATW-223, CG-S10-ATW-004).
 */

import { revalidatePath } from "next/cache";
import { createSupabaseServerClient } from "../../../../../lib/supabase/server.ts";
import { resolveOperationsAccessForRequest } from "../../../../../lib/portal/resolve-operations-access.server.ts";
import {
  registerVehicleOperationalProfile,
  registerDriverOperationalProfile,
  setDriverMobileTrackingConsent,
  registerGpsDevice,
  transitionGpsDeviceStatus,
  assignDeviceToVehicle,
  unassignDeviceFromVehicle,
  registerSimCard,
  assignSimToDevice,
  unassignSimFromDevice,
  registerProviderVehicleMapping,
  setVehicleTrackingSourcePriority,
  FleetDriverDeviceMutationError,
} from "../../../../../server/mutations/fleet-driver-device.ts";
import type { VehicleOwnershipType, DeviceOwnershipType, GpsDeviceStatus } from "../../../../../server/contracts/fleet-driver-device/fleet-driver-device.ts";

export interface FleetFormState {
  readonly error: string | null;
}

export async function registerVehicleAction(tenantSlug: string, _prevState: FleetFormState, formData: FormData): Promise<FleetFormState> {
  const access = await resolveOperationsAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    return { error: "You don't have access to this organization's Operations workspace." };
  }

  const code = String(formData.get("code") ?? "");
  const name = String(formData.get("name") ?? "");
  const ownershipType = String(formData.get("ownershipType") ?? "") as VehicleOwnershipType;
  const capacityWeightRaw = String(formData.get("capacityWeightKg") ?? "").trim();
  const capacityVolumeRaw = String(formData.get("capacityVolumeCbm") ?? "").trim();

  const supabase = await createSupabaseServerClient();
  try {
    await registerVehicleOperationalProfile(supabase, {
      tenantId: access.tenant.id,
      code,
      name,
      ownershipType,
      capacityWeightKg: capacityWeightRaw.length === 0 ? null : Number(capacityWeightRaw),
      capacityVolumeCbm: capacityVolumeRaw.length === 0 ? null : Number(capacityVolumeRaw),
      actorAuthUserId: access.authUserId,
      actorLabel: access.authUserId,
    });
  } catch (error) {
    if (error instanceof FleetDriverDeviceMutationError) {
      return { error: `Could not register this vehicle: ${error.message}` };
    }
    throw error;
  }

  revalidatePath(`/${tenantSlug}/operations/fleet`);
  return { error: null };
}

export async function registerDriverAction(tenantSlug: string, _prevState: FleetFormState, formData: FormData): Promise<FleetFormState> {
  const access = await resolveOperationsAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    return { error: "You don't have access to this organization's Operations workspace." };
  }

  const code = String(formData.get("code") ?? "");
  const name = String(formData.get("name") ?? "");
  const licenseClass = String(formData.get("licenseClass") ?? "").trim();
  const licenseExpiryDate = String(formData.get("licenseExpiryDate") ?? "").trim();

  const supabase = await createSupabaseServerClient();
  try {
    await registerDriverOperationalProfile(supabase, {
      tenantId: access.tenant.id,
      code,
      name,
      licenseClass: licenseClass.length === 0 ? null : licenseClass,
      licenseExpiryDate: licenseExpiryDate.length === 0 ? null : licenseExpiryDate,
      actorAuthUserId: access.authUserId,
      actorLabel: access.authUserId,
    });
  } catch (error) {
    if (error instanceof FleetDriverDeviceMutationError) {
      return { error: `Could not register this driver: ${error.message}` };
    }
    throw error;
  }

  revalidatePath(`/${tenantSlug}/operations/fleet`);
  return { error: null };
}

export async function setDriverConsentAction(
  tenantSlug: string,
  driverProfileId: string,
  expectedVersion: number,
  consent: boolean,
  _prevState: FleetFormState,
  _formData: FormData,
): Promise<FleetFormState> {
  const access = await resolveOperationsAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    return { error: "You don't have access to this organization's Operations workspace." };
  }

  const supabase = await createSupabaseServerClient();
  try {
    await setDriverMobileTrackingConsent(supabase, { driverProfileId, consent, expectedVersion, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof FleetDriverDeviceMutationError) {
      return { error: `Could not update mobile tracking consent: ${error.message}` };
    }
    throw error;
  }

  revalidatePath(`/${tenantSlug}/operations/fleet`);
  return { error: null };
}

export async function registerDeviceAction(tenantSlug: string, _prevState: FleetFormState, formData: FormData): Promise<FleetFormState> {
  const access = await resolveOperationsAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    return { error: "You don't have access to this organization's Operations workspace." };
  }

  const imei = String(formData.get("imei") ?? "");
  const deviceModel = String(formData.get("deviceModel") ?? "");
  const ownershipType = String(formData.get("ownershipType") ?? "") as DeviceOwnershipType;

  const supabase = await createSupabaseServerClient();
  try {
    await registerGpsDevice(supabase, { tenantId: access.tenant.id, imei, deviceModel, ownershipType, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof FleetDriverDeviceMutationError) {
      return { error: `Could not register this device: ${error.message}` };
    }
    throw error;
  }

  revalidatePath(`/${tenantSlug}/operations/fleet`);
  return { error: null };
}

export async function transitionDeviceStatusAction(
  tenantSlug: string,
  deviceId: string,
  expectedVersion: number,
  _prevState: FleetFormState,
  formData: FormData,
): Promise<FleetFormState> {
  const access = await resolveOperationsAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    return { error: "You don't have access to this organization's Operations workspace." };
  }

  const toStatus = String(formData.get("toStatus") ?? "") as GpsDeviceStatus;
  const supabase = await createSupabaseServerClient();
  try {
    await transitionGpsDeviceStatus(supabase, { deviceId, toStatus, expectedVersion, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof FleetDriverDeviceMutationError) {
      return { error: `Could not transition this device: ${error.message}` };
    }
    throw error;
  }

  revalidatePath(`/${tenantSlug}/operations/fleet`);
  return { error: null };
}

export async function assignDeviceToVehicleAction(tenantSlug: string, deviceId: string, _prevState: FleetFormState, formData: FormData): Promise<FleetFormState> {
  const access = await resolveOperationsAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    return { error: "You don't have access to this organization's Operations workspace." };
  }

  const vehicleProfileId = String(formData.get("vehicleProfileId") ?? "");
  const reason = String(formData.get("reason") ?? "").trim();

  const supabase = await createSupabaseServerClient();
  try {
    await assignDeviceToVehicle(supabase, { deviceId, vehicleProfileId, reason: reason.length === 0 ? null : reason, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof FleetDriverDeviceMutationError) {
      return { error: `Could not assign this device: ${error.message}` };
    }
    throw error;
  }

  revalidatePath(`/${tenantSlug}/operations/fleet`);
  return { error: null };
}

export async function unassignDeviceFromVehicleAction(tenantSlug: string, deviceId: string, _prevState: FleetFormState, formData: FormData): Promise<FleetFormState> {
  const access = await resolveOperationsAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    return { error: "You don't have access to this organization's Operations workspace." };
  }

  const reason = String(formData.get("reason") ?? "");
  const supabase = await createSupabaseServerClient();
  try {
    await unassignDeviceFromVehicle(supabase, { deviceId, reason, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof FleetDriverDeviceMutationError) {
      return { error: `Could not unassign this device: ${error.message}` };
    }
    throw error;
  }

  revalidatePath(`/${tenantSlug}/operations/fleet`);
  return { error: null };
}

export async function registerSimAction(tenantSlug: string, _prevState: FleetFormState, formData: FormData): Promise<FleetFormState> {
  const access = await resolveOperationsAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    return { error: "You don't have access to this organization's Operations workspace." };
  }

  const iccid = String(formData.get("iccid") ?? "");
  const msisdn = String(formData.get("msisdn") ?? "").trim();
  const carrier = String(formData.get("carrier") ?? "").trim();

  const supabase = await createSupabaseServerClient();
  try {
    await registerSimCard(supabase, {
      tenantId: access.tenant.id,
      iccid,
      msisdn: msisdn.length === 0 ? null : msisdn,
      carrier: carrier.length === 0 ? null : carrier,
      actorAuthUserId: access.authUserId,
      actorLabel: access.authUserId,
    });
  } catch (error) {
    if (error instanceof FleetDriverDeviceMutationError) {
      return { error: `Could not register this SIM: ${error.message}` };
    }
    throw error;
  }

  revalidatePath(`/${tenantSlug}/operations/fleet`);
  return { error: null };
}

export async function assignSimToDeviceAction(tenantSlug: string, simId: string, _prevState: FleetFormState, formData: FormData): Promise<FleetFormState> {
  const access = await resolveOperationsAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    return { error: "You don't have access to this organization's Operations workspace." };
  }

  const deviceId = String(formData.get("deviceId") ?? "");
  const supabase = await createSupabaseServerClient();
  try {
    await assignSimToDevice(supabase, { simId, deviceId, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof FleetDriverDeviceMutationError) {
      return { error: `Could not assign this SIM: ${error.message}` };
    }
    throw error;
  }

  revalidatePath(`/${tenantSlug}/operations/fleet`);
  return { error: null };
}

export async function unassignSimFromDeviceAction(tenantSlug: string, simId: string, _prevState: FleetFormState, _formData: FormData): Promise<FleetFormState> {
  const access = await resolveOperationsAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    return { error: "You don't have access to this organization's Operations workspace." };
  }

  const supabase = await createSupabaseServerClient();
  try {
    await unassignSimFromDevice(supabase, { simId, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof FleetDriverDeviceMutationError) {
      return { error: `Could not unassign this SIM: ${error.message}` };
    }
    throw error;
  }

  revalidatePath(`/${tenantSlug}/operations/fleet`);
  return { error: null };
}

/** ATW-226H: closes ATW-223's own already-shipped-mutation, never-rendered-UI gap for the two remaining tracking-configuration forms. */
export async function registerProviderMappingAction(tenantSlug: string, _prevState: FleetFormState, formData: FormData): Promise<FleetFormState> {
  const access = await resolveOperationsAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    return { error: "You don't have access to this organization's Operations workspace." };
  }

  const vehicleMasterId = String(formData.get("vehicleMasterId") ?? "");
  const providerCode = String(formData.get("providerCode") ?? "");
  const externalVehicleId = String(formData.get("externalVehicleId") ?? "");

  const supabase = await createSupabaseServerClient();
  try {
    await registerProviderVehicleMapping(supabase, {
      tenantId: access.tenant.id,
      vehicleMasterId,
      providerCode,
      externalVehicleId,
      actorAuthUserId: access.authUserId,
      actorLabel: access.authUserId,
    });
  } catch (error) {
    if (error instanceof FleetDriverDeviceMutationError) {
      return { error: `Could not register this provider mapping: ${error.message}` };
    }
    throw error;
  }

  revalidatePath(`/${tenantSlug}/operations/fleet`);
  return { error: null };
}

export async function setVehicleSourcePriorityAction(tenantSlug: string, _prevState: FleetFormState, formData: FormData): Promise<FleetFormState> {
  const access = await resolveOperationsAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    return { error: "You don't have access to this organization's Operations workspace." };
  }

  const vehicleMasterId = String(formData.get("vehicleMasterId") ?? "");
  const sourceType = String(formData.get("sourceType") ?? "") as "driver_mobile" | "direct_device" | "third_party_platform";
  const priorityRank = Number(formData.get("priorityRank") ?? 0);
  const isEnabled = formData.get("isEnabled") === "on";

  const supabase = await createSupabaseServerClient();
  try {
    await setVehicleTrackingSourcePriority(supabase, {
      tenantId: access.tenant.id,
      vehicleMasterId,
      sourceType,
      priorityRank,
      isEnabled,
      actorAuthUserId: access.authUserId,
      actorLabel: access.authUserId,
    });
  } catch (error) {
    if (error instanceof FleetDriverDeviceMutationError) {
      return { error: `Could not set this vehicle's source priority: ${error.message}` };
    }
    throw error;
  }

  revalidatePath(`/${tenantSlug}/operations/fleet`);
  return { error: null };
}
