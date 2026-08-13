"use server";

/** Overtime/timesheet policy authoring Server Actions (HRT-281, CG-S12-HRT-009). */

import { revalidatePath } from "next/cache";
import { createSupabaseServerClient } from "../../../../../../lib/supabase/server.ts";
import { resolveHrisAccessForRequest } from "../../../../../../lib/portal/resolve-hris-access.server.ts";
import { createOvertimePolicy, createOvertimePolicyVersion, publishOvertimePolicyVersion, OvertimeTimesheetMutationError } from "../../../../../../server/mutations/overtime-timesheet.ts";
import type { RoundingMode } from "../../../../../../server/contracts/overtime-timesheet/overtime-timesheet.ts";

export interface OvertimePolicyActionState {
  readonly error: string | null;
}

const OK: OvertimePolicyActionState = { error: null };
const NO_ACCESS: OvertimePolicyActionState = { error: "You don't have access to this organization's HRIS workspace." };

function path(tenantSlug: string): string {
  return `/${tenantSlug}/hris/overtime-timesheet/policies`;
}

export async function createOvertimePolicyAction(tenantSlug: string, _prevState: OvertimePolicyActionState, formData: FormData): Promise<OvertimePolicyActionState> {
  const access = await resolveHrisAccessForRequest(tenantSlug);
  if (access.status !== "allowed") return NO_ACCESS;

  const name = String(formData.get("name") ?? "").trim();
  const orgUnitId = String(formData.get("orgUnitId") ?? "").trim() || null;
  if (!name) return { error: "A policy name is required." };

  const supabase = await createSupabaseServerClient();
  try {
    await createOvertimePolicy(supabase, { tenantId: access.tenant.id, orgUnitId, name, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof OvertimeTimesheetMutationError) return { error: `Could not create this policy: ${error.message}` };
    throw error;
  }

  revalidatePath(path(tenantSlug));
  return OK;
}

export async function createAndPublishOvertimePolicyVersionAction(tenantSlug: string, policyId: string, _prevState: OvertimePolicyActionState, formData: FormData): Promise<OvertimePolicyActionState> {
  const access = await resolveHrisAccessForRequest(tenantSlug);
  if (access.status !== "allowed") return NO_ACCESS;

  const roundingIncrementMinutes = Number(formData.get("roundingIncrementMinutes") ?? 15);
  const roundingMode = String(formData.get("roundingMode") ?? "nearest") as RoundingMode;
  const minOvertimeMinutes = Number(formData.get("minOvertimeMinutes") ?? 0);
  const dailyRaw = String(formData.get("dailyOvertimeCapMinutes") ?? "").trim();
  const weeklyRaw = String(formData.get("weeklyOvertimeCapMinutes") ?? "").trim();
  const standardWorkdayMinutes = Number(formData.get("standardWorkdayMinutes") ?? 480);
  const defaultBreakDeductionMinutes = Number(formData.get("defaultBreakDeductionMinutes") ?? 0);
  const requiresPreApproval = formData.get("requiresPreApproval") === "on";
  const effectiveFrom = String(formData.get("effectiveFrom") ?? "").trim();

  if (!effectiveFrom) return { error: "An effective-from date is required." };

  const supabase = await createSupabaseServerClient();
  try {
    const version = await createOvertimePolicyVersion(supabase, {
      policyId,
      roundingIncrementMinutes,
      roundingMode,
      minOvertimeMinutes,
      dailyOvertimeCapMinutes: dailyRaw ? Number(dailyRaw) : null,
      weeklyOvertimeCapMinutes: weeklyRaw ? Number(weeklyRaw) : null,
      standardWorkdayMinutes,
      defaultBreakDeductionMinutes,
      requiresPreApproval,
      effectiveFrom,
      actorAuthUserId: access.authUserId,
      actorLabel: access.authUserId,
    });
    await publishOvertimePolicyVersion(supabase, { versionId: String(version.id), expectedVersion: Number(version.record_version), actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof OvertimeTimesheetMutationError) return { error: `Could not create/publish this policy version: ${error.message}` };
    throw error;
  }

  revalidatePath(path(tenantSlug));
  return OK;
}
