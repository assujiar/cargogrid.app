"use server";

/**
 * Fleet, Vehicle, Driver, Device and SIM Operational Baseline Server Actions
 * (ATW-223, CG-S10-ATW-004).
 */

import { revalidatePath } from "next/cache";
import { createSupabaseServerClient } from "../../../../../lib/supabase/server.ts";
import { createSupabaseServiceRoleClient } from "../../../../../lib/supabase/service-role.ts";
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
import {
  uploadGpsDeviceInstallationEvidenceFile,
  recordGpsDeviceInstallation,
  GpsDeviceInstallationMutationError,
  type GpsDeviceInstallationMutationRpcClient,
} from "../../../../../server/mutations/gps-device-installation.ts";
import type { DocumentMutationRpcClient } from "../../../../../server/mutations/document.ts";
import type { BackgroundJobMutationRpcClient } from "../../../../../server/mutations/background-job.ts";
import { storeFileBytesAndEnqueueScan, type StorageUploadClient } from "../../../../../lib/malware-scan/store-file-bytes-and-enqueue-scan.server.ts";
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

  // ATW-031 (ISS-2026-028): this generic control must never be the path to `installed`.
  // That transition requires real installation evidence and belongs to
  // app.record_gps_device_installation (ATW-226B). The database enforces this itself
  // (`installation_evidence_required`); rejecting it here too turns a raw RPC error into
  // an explanation, and keeps the bypass closed even if the form is posted directly.
  if (toStatus === "installed") {
    return {
      error:
        "A device cannot be marked installed from here. Record the installation evidence (evidence file and technician) instead — installation is evidence-mandatory.",
    };
  }

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

/**
 * CG-AUDIT-2026-09-02 E5: app.record_gps_device_installation (ATW-226B) and
 * its own authority/malware-scan gating already exist and are fully
 * db-tested -- the real gap was that nothing in this app ever called the
 * upload+store+scan sequence, so a device could never actually accumulate
 * a clean-scanned evidence file to record. Mirrors uploadAndLinkDocumentAction's
 * own shape (shipment-orders/actions.ts): app.initiate_file_upload is
 * service_role-only, so the upload step runs through the service-role
 * client, while app.record_gps_device_installation itself is
 * `authenticated`-callable (it re-checks OPS:Edit via the reused
 * app.transition_gps_device_status gate) and runs through the ordinary
 * RLS-scoped client, exactly like every other write in this file.
 */
function toGpsDeviceInstallationStoreClient(client: ReturnType<typeof createSupabaseServiceRoleClient>): DocumentMutationRpcClient & StorageUploadClient {
  return client as unknown as DocumentMutationRpcClient & StorageUploadClient;
}

function toGpsDeviceInstallationUploadClient(client: ReturnType<typeof createSupabaseServiceRoleClient>): GpsDeviceInstallationMutationRpcClient {
  return client;
}

function toGpsDeviceInstallationBackgroundJobClient(client: Awaited<ReturnType<typeof createSupabaseServerClient>>): BackgroundJobMutationRpcClient {
  return client as unknown as BackgroundJobMutationRpcClient;
}

export async function recordGpsDeviceInstallationAction(
  tenantSlug: string,
  deviceId: string,
  deviceVehicleAssignmentId: string,
  expectedDeviceVersion: number,
  _prevState: FleetFormState,
  formData: FormData,
): Promise<FleetFormState> {
  const access = await resolveOperationsAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    return { error: "You don't have access to this organization's Operations workspace." };
  }

  const evidenceFile = formData.get("evidenceFile");
  if (!(evidenceFile instanceof File) || evidenceFile.size === 0) {
    return { error: "Choose an installation evidence photo to upload." };
  }
  const technicianLabel = String(formData.get("technicianLabel") ?? "").trim();
  if (!technicianLabel) {
    return { error: "A technician name is required." };
  }
  const installationNotesRaw = String(formData.get("installationNotes") ?? "").trim();

  const supabase = await createSupabaseServerClient();
  try {
    const serviceRole = createSupabaseServiceRoleClient();
    const uploaded = await uploadGpsDeviceInstallationEvidenceFile(toGpsDeviceInstallationUploadClient(serviceRole), {
      tenantId: access.tenant.id,
      deviceId,
      originalFilename: evidenceFile.name,
      mimeType: evidenceFile.type || "application/octet-stream",
      sizeBytes: evidenceFile.size,
      idempotencyKey: `gps-install-${deviceId}-${access.authUserId}-${Date.now()}`,
      actorAuthUserId: access.authUserId,
      actorLabel: access.authUserId,
    });

    const storeError = await storeFileBytesAndEnqueueScan(
      toGpsDeviceInstallationStoreClient(serviceRole),
      toGpsDeviceInstallationBackgroundJobClient(supabase),
      uploaded,
      evidenceFile,
      access.tenant.id,
      access.authUserId,
      "installation evidence photo",
    );
    if (storeError) {
      return storeError;
    }

    await recordGpsDeviceInstallation(supabase, {
      deviceVehicleAssignmentId,
      evidenceFileId: uploaded.id,
      technicianLabel,
      installationNotes: installationNotesRaw.length === 0 ? null : installationNotesRaw,
      expectedDeviceVersion,
      actorAuthUserId: access.authUserId,
      actorLabel: access.authUserId,
    });
  } catch (error) {
    if (error instanceof GpsDeviceInstallationMutationError) {
      return { error: `Could not record this installation: ${error.message}` };
    }
    throw error;
  }

  revalidatePath(`/${tenantSlug}/operations/fleet`);
  return { error: null };
}
