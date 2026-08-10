"use server";

/** Rotating roster cycle Server Actions (HRT-279, decision 3). */

import { revalidatePath } from "next/cache";
import { createSupabaseServerClient } from "../../../../../../lib/supabase/server.ts";
import { resolveHrisAccessForRequest } from "../../../../../../lib/portal/resolve-hris-access.server.ts";
import { createRosterCycle, setRosterCycleSlot, publishRosterCycle, generateRosterScheduleAssignments, ShiftRosterMutationError } from "../../../../../../server/mutations/shift-roster.ts";

export interface RosterCycleActionState {
  readonly error: string | null;
  readonly info?: string | null;
}

const OK: RosterCycleActionState = { error: null };
const NO_ACCESS: RosterCycleActionState = { error: "You don't have access to this organization's HRIS workspace." };

function path(tenantSlug: string): string {
  return `/${tenantSlug}/hris/roster/cycles`;
}

export async function createRosterCycleAction(tenantSlug: string, _prevState: RosterCycleActionState, formData: FormData): Promise<RosterCycleActionState> {
  const access = await resolveHrisAccessForRequest(tenantSlug);
  if (access.status !== "allowed") return NO_ACCESS;

  const name = String(formData.get("name") ?? "").trim();
  const cycleLengthDays = Number(formData.get("cycleLengthDays") ?? 0);
  const orgUnitId = String(formData.get("orgUnitId") ?? "").trim() || null;
  if (!name || cycleLengthDays < 1) return { error: "A name and a cycle length of at least 1 day are required." };

  const supabase = await createSupabaseServerClient();
  try {
    await createRosterCycle(supabase, { tenantId: access.tenant.id, orgUnitId, name, cycleLengthDays, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof ShiftRosterMutationError) return { error: `Could not create this roster cycle: ${error.message}` };
    throw error;
  }

  revalidatePath(path(tenantSlug));
  return OK;
}

export async function setRosterCycleSlotAction(tenantSlug: string, rosterCycleId: string, _prevState: RosterCycleActionState, formData: FormData): Promise<RosterCycleActionState> {
  const access = await resolveHrisAccessForRequest(tenantSlug);
  if (access.status !== "allowed") return NO_ACCESS;

  const dayOffset = Number(formData.get("dayOffset") ?? -1);
  const shiftTemplateId = String(formData.get("shiftTemplateId") ?? "").trim() || null;
  if (dayOffset < 0) return { error: "A valid day offset is required." };

  const supabase = await createSupabaseServerClient();
  try {
    await setRosterCycleSlot(supabase, { rosterCycleId, dayOffset, shiftTemplateId, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof ShiftRosterMutationError) return { error: `Could not save this day-offset slot: ${error.message}` };
    throw error;
  }

  revalidatePath(path(tenantSlug));
  return OK;
}

export async function publishRosterCycleAction(tenantSlug: string, rosterCycleId: string, expectedVersion: number, _prevState: RosterCycleActionState, _formData: FormData): Promise<RosterCycleActionState> {
  const access = await resolveHrisAccessForRequest(tenantSlug);
  if (access.status !== "allowed") return NO_ACCESS;

  const supabase = await createSupabaseServerClient();
  try {
    await publishRosterCycle(supabase, { rosterCycleId, expectedVersion, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof ShiftRosterMutationError) return { error: `Could not publish this roster cycle: ${error.message}` };
    throw error;
  }

  revalidatePath(path(tenantSlug));
  return OK;
}

export async function generateRosterScheduleAssignmentsAction(tenantSlug: string, rosterCycleId: string, _prevState: RosterCycleActionState, formData: FormData): Promise<RosterCycleActionState> {
  const access = await resolveHrisAccessForRequest(tenantSlug);
  if (access.status !== "allowed") return NO_ACCESS;

  const employeeIdsRaw = String(formData.get("employeeIds") ?? "").trim();
  const fromDate = String(formData.get("fromDate") ?? "").trim();
  const toDate = String(formData.get("toDate") ?? "").trim();
  const employeeIds = employeeIdsRaw
    .split(/[\s,]+/)
    .map((s) => s.trim())
    .filter(Boolean);
  if (employeeIds.length === 0 || !fromDate || !toDate) return { error: "At least one employee id and a from/to date range are required." };

  const supabase = await createSupabaseServerClient();
  try {
    const result = await generateRosterScheduleAssignments(supabase, { tenantId: access.tenant.id, rosterCycleId, employeeIds, fromDate, toDate, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
    revalidatePath(path(tenantSlug));
    return { error: null, info: `Generated ${result.createdCount} new, ${result.supersededCount} superseded, ${result.skippedCount} skipped (job ${result.jobId}).` };
  } catch (error) {
    if (error instanceof ShiftRosterMutationError) return { error: `Could not generate this batch: ${error.message}` };
    throw error;
  }
}
