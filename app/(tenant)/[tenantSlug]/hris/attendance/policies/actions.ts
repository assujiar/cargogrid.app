"use server";

/** Attendance policy authoring Server Actions (HRT-278, CG-S12-HRT-006). */

import { revalidatePath } from "next/cache";
import { createSupabaseServerClient } from "../../../../../../lib/supabase/server.ts";
import { resolveHrisAccessForRequest } from "../../../../../../lib/portal/resolve-hris-access.server.ts";
import { createAttendancePolicy, createAttendancePolicyVersion, publishAttendancePolicyVersion, AttendanceMutationError } from "../../../../../../server/mutations/attendance.ts";
import type { LocationEnforcementMode, SourceChannel } from "../../../../../../server/contracts/attendance/attendance.ts";

export interface PolicyActionState {
  readonly error: string | null;
}

const OK: PolicyActionState = { error: null };
const NO_ACCESS: PolicyActionState = { error: "You don't have access to this organization's HRIS workspace." };

function path(tenantSlug: string): string {
  return `/${tenantSlug}/hris/attendance/policies`;
}

export async function createPolicyAction(tenantSlug: string, _prevState: PolicyActionState, formData: FormData): Promise<PolicyActionState> {
  const access = await resolveHrisAccessForRequest(tenantSlug);
  if (access.status !== "allowed") return NO_ACCESS;

  const name = String(formData.get("name") ?? "").trim();
  const orgUnitId = String(formData.get("orgUnitId") ?? "").trim() || null;
  if (!name) return { error: "A policy name is required." };

  const supabase = await createSupabaseServerClient();
  try {
    await createAttendancePolicy(supabase, { tenantId: access.tenant.id, orgUnitId, name, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof AttendanceMutationError) return { error: `Could not create this policy: ${error.message}` };
    throw error;
  }

  revalidatePath(path(tenantSlug));
  return OK;
}

export async function createAndPublishPolicyVersionAction(tenantSlug: string, policyId: string, _prevState: PolicyActionState, formData: FormData): Promise<PolicyActionState> {
  const access = await resolveHrisAccessForRequest(tenantSlug);
  if (access.status !== "allowed") return NO_ACCESS;

  const timezone = String(formData.get("timezone") ?? "").trim();
  const workdayStartTime = String(formData.get("workdayStartTime") ?? "08:00").trim();
  const workdayEndTime = String(formData.get("workdayEndTime") ?? "17:00").trim();
  const dayBoundaryLocalTime = String(formData.get("dayBoundaryLocalTime") ?? "00:00").trim();
  const graceLateMinutes = Number(formData.get("graceLateMinutes") ?? 0);
  const graceEarlyMinutes = Number(formData.get("graceEarlyMinutes") ?? 0);
  const allowedChannels = formData.getAll("allowedChannels").map(String) as SourceChannel[];
  const locationEnforcementMode = String(formData.get("locationEnforcementMode") ?? "none") as LocationEnforcementMode;
  const geofenceLat = String(formData.get("geofenceLat") ?? "").trim();
  const geofenceLon = String(formData.get("geofenceLon") ?? "").trim();
  const geofenceRadiusMeters = String(formData.get("geofenceRadiusMeters") ?? "").trim();
  const maxSessionHours = Number(formData.get("maxSessionHours") ?? 16);
  const effectiveFrom = String(formData.get("effectiveFrom") ?? "").trim();

  if (!timezone || !effectiveFrom || allowedChannels.length === 0) return { error: "Timezone, effective date, and at least one allowed channel are required." };

  const geofenceCenterGeojson =
    locationEnforcementMode !== "none" && geofenceLat && geofenceLon
      ? { type: "Point" as const, coordinates: [Number(geofenceLon), Number(geofenceLat)] as [number, number] }
      : null;

  const supabase = await createSupabaseServerClient();
  try {
    const version = await createAttendancePolicyVersion(supabase, {
      policyId,
      timezone,
      workdayStartTime,
      workdayEndTime,
      dayBoundaryLocalTime,
      graceLateMinutes,
      graceEarlyMinutes,
      allowedChannels,
      locationEnforcementMode,
      geofenceCenterGeojson,
      geofenceRadiusMeters: geofenceRadiusMeters ? Number(geofenceRadiusMeters) : null,
      maxSessionHours,
      effectiveFrom,
      actorAuthUserId: access.authUserId,
      actorLabel: access.authUserId,
    });
    await publishAttendancePolicyVersion(supabase, { versionId: String(version.id), expectedVersion: Number(version.record_version), actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof AttendanceMutationError) return { error: `Could not create/publish this policy version: ${error.message}` };
    throw error;
  }

  revalidatePath(path(tenantSlug));
  return OK;
}
