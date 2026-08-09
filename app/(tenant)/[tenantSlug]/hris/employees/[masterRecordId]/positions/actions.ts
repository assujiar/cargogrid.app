"use server";

/**
 * Employee assignment timeline / transfer-promotion-reorg wizard Server Actions
 * (HRT-275, CG-S12-HRT-003). Mirrors the established hris Server Action shape:
 * resolve portal access, call the typed mutation/query wrapper, translate a known
 * error into a plain-language message, revalidate the affected path.
 */

import { revalidatePath } from "next/cache";
import { createSupabaseServerClient } from "../../../../../../../lib/supabase/server.ts";
import { resolveHrisAccessForRequest } from "../../../../../../../lib/portal/resolve-hris-access.server.ts";
import { proposeEmployeePositionAssignment, decideEmployeePositionAssignment, cancelEmployeePositionAssignment, PositionMutationError } from "../../../../../../../server/mutations/position.ts";
import { previewEmployeePositionAssignmentImpact, PositionQueryError } from "../../../../../../../server/queries/position.ts";
import type { AssignmentImpactPreview, AssignmentType, ChangeReason } from "../../../../../../../server/contracts/position/position.ts";

export interface PositionWizardActionState {
  readonly error: string | null;
  readonly preview: AssignmentImpactPreview | null;
}

const OK: PositionWizardActionState = { error: null, preview: null };
const NO_ACCESS: PositionWizardActionState = { error: "You don't have access to this organization's HRIS workspace.", preview: null };

async function requireAccess(tenantSlug: string) {
  const access = await resolveHrisAccessForRequest(tenantSlug);
  if (access.status !== "allowed") return null;
  return access;
}

function timelinePath(tenantSlug: string, masterRecordId: string): string {
  return `/${tenantSlug}/hris/employees/${masterRecordId}/positions`;
}

export async function previewAssignmentImpactAction(
  tenantSlug: string,
  masterRecordId: string,
  _prevState: PositionWizardActionState,
  formData: FormData,
): Promise<PositionWizardActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return NO_ACCESS;

  const positionId = String(formData.get("positionId") ?? "").trim();
  const managerEmployeeId = String(formData.get("managerEmployeeId") ?? "").trim() || null;
  const effectiveStartDate = String(formData.get("effectiveStartDate") ?? "").trim() || null;

  if (!positionId) return { error: "Choose a position to preview its impact.", preview: null };

  const supabase = await createSupabaseServerClient();
  try {
    const preview = await previewEmployeePositionAssignmentImpact(supabase, { masterRecordId, positionId, managerEmployeeId, effectiveStartDate, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
    return { error: null, preview };
  } catch (error) {
    if (error instanceof PositionQueryError) return { error: `Could not compute impact preview: ${error.message}`, preview: null };
    throw error;
  }
}

export async function proposeAssignmentAction(
  tenantSlug: string,
  masterRecordId: string,
  expectedVersion: number,
  _prevState: PositionWizardActionState,
  formData: FormData,
): Promise<PositionWizardActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return NO_ACCESS;

  const positionId = String(formData.get("positionId") ?? "").trim();
  const gradeId = String(formData.get("gradeId") ?? "").trim() || null;
  const managerEmployeeId = String(formData.get("managerEmployeeId") ?? "").trim() || null;
  const assignmentType = String(formData.get("assignmentType") ?? "primary") as AssignmentType;
  const allocationPctRaw = String(formData.get("allocationPct") ?? "").trim();
  const effectiveStartDate = String(formData.get("effectiveStartDate") ?? "").trim();
  const effectiveEndDate = String(formData.get("effectiveEndDate") ?? "").trim() || null;
  const changeReason = String(formData.get("changeReason") ?? "") as ChangeReason;
  const reasonNote = String(formData.get("reasonNote") ?? "").trim() || null;

  const supabase = await createSupabaseServerClient();
  try {
    await proposeEmployeePositionAssignment(supabase, {
      masterRecordId,
      expectedVersion,
      positionId,
      gradeId,
      managerEmployeeId,
      assignmentType,
      allocationPct: allocationPctRaw ? Number(allocationPctRaw) : null,
      effectiveStartDate,
      effectiveEndDate,
      changeReason,
      reasonNote,
      actorAuthUserId: access.authUserId,
      actorLabel: access.authUserId,
    });
  } catch (error) {
    if (error instanceof PositionMutationError) return { error: `Could not propose this assignment: ${error.message}`, preview: null };
    throw error;
  }

  revalidatePath(timelinePath(tenantSlug, masterRecordId));
  return OK;
}

export async function decideAssignmentAction(
  tenantSlug: string,
  masterRecordId: string,
  assignmentId: string,
  expectedVersion: number,
  decision: "approve" | "reject",
  _prevState: PositionWizardActionState,
  formData: FormData,
): Promise<PositionWizardActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return NO_ACCESS;

  const reason = String(formData.get("reason") ?? "").trim();

  const supabase = await createSupabaseServerClient();
  try {
    await decideEmployeePositionAssignment(supabase, { assignmentId, expectedVersion, decision, reason, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof PositionMutationError) return { error: `Could not record this decision: ${error.message}`, preview: null };
    throw error;
  }

  revalidatePath(timelinePath(tenantSlug, masterRecordId));
  revalidatePath(`/${tenantSlug}/hris/employees/${masterRecordId}`);
  return OK;
}

export async function cancelAssignmentAction(
  tenantSlug: string,
  masterRecordId: string,
  assignmentId: string,
  expectedVersion: number,
  _prevState: PositionWizardActionState,
  formData: FormData,
): Promise<PositionWizardActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return NO_ACCESS;

  const reason = String(formData.get("reason") ?? "").trim();

  const supabase = await createSupabaseServerClient();
  try {
    await cancelEmployeePositionAssignment(supabase, { assignmentId, expectedVersion, reason, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof PositionMutationError) return { error: `Could not cancel this assignment: ${error.message}`, preview: null };
    throw error;
  }

  revalidatePath(timelinePath(tenantSlug, masterRecordId));
  return OK;
}
