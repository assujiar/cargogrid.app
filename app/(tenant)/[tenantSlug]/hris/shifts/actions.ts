"use server";

/** Shift template authoring Server Actions (HRT-279, CG-S12-HRT-007). */

import { revalidatePath } from "next/cache";
import { createSupabaseServerClient } from "../../../../../lib/supabase/server.ts";
import { resolveHrisAccessForRequest } from "../../../../../lib/portal/resolve-hris-access.server.ts";
import { createShiftTemplate, createShiftTemplateVersion, publishShiftTemplateVersion, ShiftRosterMutationError } from "../../../../../server/mutations/shift-roster.ts";
import type { SegmentType, ShiftType } from "../../../../../server/contracts/shift-roster/shift-roster.ts";

export interface ShiftTemplateActionState {
  readonly error: string | null;
}

const OK: ShiftTemplateActionState = { error: null };
const NO_ACCESS: ShiftTemplateActionState = { error: "You don't have access to this organization's HRIS workspace." };
const MAX_SEGMENT_ROWS = 6;

function path(tenantSlug: string): string {
  return `/${tenantSlug}/hris/shifts`;
}

export async function createShiftTemplateAction(tenantSlug: string, _prevState: ShiftTemplateActionState, formData: FormData): Promise<ShiftTemplateActionState> {
  const access = await resolveHrisAccessForRequest(tenantSlug);
  if (access.status !== "allowed") return NO_ACCESS;

  const code = String(formData.get("code") ?? "").trim();
  const name = String(formData.get("name") ?? "").trim();
  const orgUnitId = String(formData.get("orgUnitId") ?? "").trim() || null;
  if (!code || !name) return { error: "A code and a name are both required." };

  const supabase = await createSupabaseServerClient();
  try {
    await createShiftTemplate(supabase, { tenantId: access.tenant.id, orgUnitId, code, name, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof ShiftRosterMutationError) return { error: `Could not create this shift template: ${error.message}` };
    throw error;
  }

  revalidatePath(path(tenantSlug));
  return OK;
}

export async function createAndPublishShiftTemplateVersionAction(tenantSlug: string, shiftTemplateId: string, _prevState: ShiftTemplateActionState, formData: FormData): Promise<ShiftTemplateActionState> {
  const access = await resolveHrisAccessForRequest(tenantSlug);
  if (access.status !== "allowed") return NO_ACCESS;

  const timezone = String(formData.get("timezone") ?? "").trim();
  const shiftType = String(formData.get("shiftType") ?? "fixed") as ShiftType;
  const dayBoundaryLocalTime = String(formData.get("dayBoundaryLocalTime") ?? "").trim() || null;
  const graceLateRaw = String(formData.get("graceLateMinutes") ?? "").trim();
  const graceEarlyRaw = String(formData.get("graceEarlyMinutes") ?? "").trim();
  const effectiveFrom = String(formData.get("effectiveFrom") ?? "").trim();

  const segments: { segmentType: SegmentType; startTime: string; endTime: string }[] = [];
  for (let i = 0; i < MAX_SEGMENT_ROWS; i++) {
    const segmentType = String(formData.get(`segmentType${i}`) ?? "").trim();
    const startTime = String(formData.get(`startTime${i}`) ?? "").trim();
    const endTime = String(formData.get(`endTime${i}`) ?? "").trim();
    if (!segmentType || !startTime || !endTime) continue;
    if (segmentType !== "work" && segmentType !== "break") continue;
    segments.push({ segmentType, startTime: `${startTime}:00`, endTime: `${endTime}:00` });
  }

  if (!timezone || !effectiveFrom || segments.length === 0) return { error: "Timezone, effective date, and at least one segment (start/end time) are required." };

  const supabase = await createSupabaseServerClient();
  try {
    const version = await createShiftTemplateVersion(supabase, {
      shiftTemplateId,
      timezone,
      dayBoundaryLocalTime,
      shiftType,
      graceLateMinutes: graceLateRaw ? Number(graceLateRaw) : null,
      graceEarlyMinutes: graceEarlyRaw ? Number(graceEarlyRaw) : null,
      effectiveFrom,
      segments,
      actorAuthUserId: access.authUserId,
      actorLabel: access.authUserId,
    });
    await publishShiftTemplateVersion(supabase, { versionId: String(version.id), expectedVersion: Number(version.record_version), actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof ShiftRosterMutationError) return { error: `Could not create/publish this shift version: ${error.message}` };
    throw error;
  }

  revalidatePath(path(tenantSlug));
  return OK;
}
