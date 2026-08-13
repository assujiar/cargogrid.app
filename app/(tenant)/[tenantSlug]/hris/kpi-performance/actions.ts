"use server";

/**
 * HR/manager/reviewer KPI and Performance Server Actions (HRT-283,
 * CG-S12-HRT-011). Every write here is permission-gated at the RPC layer
 * (HRS:Edit/Approve/Override, or the assessment's own assigned-actor
 * identity) -- this file never re-implements or weakens that gate, it
 * only forwards.
 */

import { revalidatePath } from "next/cache";
import { createSupabaseServerClient } from "../../../../../lib/supabase/server.ts";
import { resolveHrisAccessForRequest } from "../../../../../lib/portal/resolve-hris-access.server.ts";
import {
  createPerformanceKpiDefinition,
  createPerformanceKpiDefinitionVersion,
  createPerformanceTemplate,
  addPerformanceTemplateKpiItem,
  publishPerformanceTemplate,
  createPerformanceCycle,
  advancePerformanceCycleStage,
  cancelPerformanceCycle,
  assignPerformanceGoal,
  markPerformanceGoalNotApplicable,
  assignPerformanceReviewer,
  reassignPerformanceReviewerAssignment,
  upsertPerformanceAssessmentKpiScore,
  submitPerformanceManagerAssessment,
  submitPerformanceReviewerAssessment,
  calibratePerformanceOutcomeScore,
  publishPerformanceOutcome,
  decidePerformanceAppeal,
  PerformanceMutationError,
} from "../../../../../server/mutations/kpi-performance.ts";

export interface PerformanceAdminActionState {
  readonly error: string | null;
}

const OK: PerformanceAdminActionState = { error: null };
const NO_ACCESS: PerformanceAdminActionState = { error: "You don't have access to this organization's HRIS workspace." };

function path(tenantSlug: string): string {
  return `/${tenantSlug}/hris/kpi-performance`;
}

export async function createPerformanceKpiDefinitionAction(tenantSlug: string, _prevState: PerformanceAdminActionState, formData: FormData): Promise<PerformanceAdminActionState> {
  const access = await resolveHrisAccessForRequest(tenantSlug);
  if (access.status !== "allowed") return NO_ACCESS;

  const code = String(formData.get("code") ?? "").trim();
  const name = String(formData.get("name") ?? "").trim();
  const unitOfMeasure = String(formData.get("unitOfMeasure") ?? "percent");
  const scoringMethod = String(formData.get("scoringMethod") ?? "target_ratio");
  const targetDirection = String(formData.get("targetDirection") ?? "higher_is_better");
  if (!code || !name) return { error: "Code and name are both required." };

  const supabase = await createSupabaseServerClient();
  try {
    const kpi = await createPerformanceKpiDefinition(supabase, { tenantId: access.tenant.id, code, name, description: null, unitOfMeasure, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
    await createPerformanceKpiDefinitionVersion(supabase, {
      kpiDefinitionId: kpi.id, scoringMethod, targetDirection: scoringMethod === "target_ratio" ? targetDirection : null,
      actorAuthUserId: access.authUserId, actorLabel: access.authUserId,
    });
  } catch (error) {
    if (error instanceof PerformanceMutationError) return { error: `Could not create this KPI: ${error.message}` };
    throw error;
  }

  revalidatePath(path(tenantSlug));
  return OK;
}

export async function createPerformanceTemplateAction(tenantSlug: string, _prevState: PerformanceAdminActionState, formData: FormData): Promise<PerformanceAdminActionState> {
  const access = await resolveHrisAccessForRequest(tenantSlug);
  if (access.status !== "allowed") return NO_ACCESS;

  const code = String(formData.get("code") ?? "").trim();
  const name = String(formData.get("name") ?? "").trim();
  if (!code || !name) return { error: "Code and name are both required." };

  const supabase = await createSupabaseServerClient();
  try {
    await createPerformanceTemplate(supabase, { tenantId: access.tenant.id, code, name, weightTotalRequired: 100, requiresReviewerStage: formData.get("requiresReviewerStage") === "on", actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof PerformanceMutationError) return { error: `Could not create this template: ${error.message}` };
    throw error;
  }

  revalidatePath(path(tenantSlug));
  return OK;
}

export async function addPerformanceTemplateKpiItemAction(tenantSlug: string, templateId: string, _prevState: PerformanceAdminActionState, formData: FormData): Promise<PerformanceAdminActionState> {
  const access = await resolveHrisAccessForRequest(tenantSlug);
  if (access.status !== "allowed") return NO_ACCESS;

  const kpiDefinitionId = String(formData.get("kpiDefinitionId") ?? "").trim();
  const defaultWeight = Number(formData.get("defaultWeight") ?? 0);
  if (!kpiDefinitionId || defaultWeight <= 0) return { error: "A KPI and a positive default weight are both required." };

  const supabase = await createSupabaseServerClient();
  try {
    await addPerformanceTemplateKpiItem(supabase, { templateId, kpiDefinitionId, defaultWeight, isRequired: true, sortOrder: 0, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof PerformanceMutationError) return { error: `Could not add this KPI to the template: ${error.message}` };
    throw error;
  }

  revalidatePath(path(tenantSlug));
  return OK;
}

export async function publishPerformanceTemplateAction(tenantSlug: string, templateId: string, expectedVersion: number, _prevState: PerformanceAdminActionState, _formData: FormData): Promise<PerformanceAdminActionState> {
  const access = await resolveHrisAccessForRequest(tenantSlug);
  if (access.status !== "allowed") return NO_ACCESS;

  const supabase = await createSupabaseServerClient();
  try {
    await publishPerformanceTemplate(supabase, { templateId, expectedVersion, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof PerformanceMutationError) return { error: `Could not publish this template: ${error.message}` };
    throw error;
  }

  revalidatePath(path(tenantSlug));
  return OK;
}

export async function createPerformanceCycleAction(tenantSlug: string, _prevState: PerformanceAdminActionState, formData: FormData): Promise<PerformanceAdminActionState> {
  const access = await resolveHrisAccessForRequest(tenantSlug);
  if (access.status !== "allowed") return NO_ACCESS;

  const templateId = String(formData.get("templateId") ?? "").trim();
  const code = String(formData.get("code") ?? "").trim();
  const name = String(formData.get("name") ?? "").trim();
  const periodStart = String(formData.get("periodStart") ?? "").trim();
  const periodEnd = String(formData.get("periodEnd") ?? "").trim();
  if (!templateId || !code || !name || !periodStart || !periodEnd) return { error: "Template, code, name, and period start/end are all required." };

  const supabase = await createSupabaseServerClient();
  try {
    await createPerformanceCycle(supabase, {
      tenantId: access.tenant.id, templateId, code, name, cycleType: "annual", periodStart, periodEnd,
      goalSettingDue: null, selfAssessmentDue: null, managerAssessmentDue: null, calibrationDue: null,
      actorAuthUserId: access.authUserId, actorLabel: access.authUserId,
    });
  } catch (error) {
    if (error instanceof PerformanceMutationError) return { error: `Could not create this cycle: ${error.message}` };
    throw error;
  }

  revalidatePath(path(tenantSlug));
  return OK;
}

export async function advancePerformanceCycleStageAction(
  tenantSlug: string, cycleId: string, expectedVersion: number, targetStatus: string, _prevState: PerformanceAdminActionState, _formData: FormData,
): Promise<PerformanceAdminActionState> {
  const access = await resolveHrisAccessForRequest(tenantSlug);
  if (access.status !== "allowed") return NO_ACCESS;

  const supabase = await createSupabaseServerClient();
  try {
    await advancePerformanceCycleStage(supabase, { cycleId, expectedVersion, targetStatus, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof PerformanceMutationError) return { error: `Could not advance this cycle: ${error.message}` };
    throw error;
  }

  revalidatePath(path(tenantSlug));
  return OK;
}

export async function cancelPerformanceCycleAction(tenantSlug: string, cycleId: string, expectedVersion: number, _prevState: PerformanceAdminActionState, formData: FormData): Promise<PerformanceAdminActionState> {
  const access = await resolveHrisAccessForRequest(tenantSlug);
  if (access.status !== "allowed") return NO_ACCESS;

  const reason = String(formData.get("reason") ?? "").trim();
  if (!reason) return { error: "A reason is required to cancel a performance cycle." };

  const supabase = await createSupabaseServerClient();
  try {
    await cancelPerformanceCycle(supabase, { cycleId, expectedVersion, reason, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof PerformanceMutationError) return { error: `Could not cancel this cycle: ${error.message}` };
    throw error;
  }

  revalidatePath(path(tenantSlug));
  return OK;
}

export async function assignPerformanceGoalAction(tenantSlug: string, cycleId: string, _prevState: PerformanceAdminActionState, formData: FormData): Promise<PerformanceAdminActionState> {
  const access = await resolveHrisAccessForRequest(tenantSlug);
  if (access.status !== "allowed") return NO_ACCESS;

  const employeeId = String(formData.get("employeeId") ?? "").trim();
  const kpiDefinitionId = String(formData.get("kpiDefinitionId") ?? "").trim();
  const weight = Number(formData.get("weight") ?? 0);
  const targetValueRaw = String(formData.get("targetValue") ?? "").trim();
  const targetUnit = String(formData.get("targetUnit") ?? "").trim() || null;
  if (!employeeId || !kpiDefinitionId || weight <= 0) return { error: "Employee, KPI, and a positive weight are all required." };

  const supabase = await createSupabaseServerClient();
  try {
    await assignPerformanceGoal(supabase, {
      cycleId, employeeId, kpiDefinitionId, weight, targetValue: targetValueRaw ? Number(targetValueRaw) : null, targetUnit,
      actorAuthUserId: access.authUserId, actorLabel: access.authUserId,
    });
  } catch (error) {
    if (error instanceof PerformanceMutationError) return { error: `Could not assign this goal: ${error.message}` };
    throw error;
  }

  revalidatePath(path(tenantSlug));
  return OK;
}

export async function markPerformanceGoalNotApplicableAction(tenantSlug: string, goalAssignmentId: string, expectedVersion: number, _prevState: PerformanceAdminActionState, formData: FormData): Promise<PerformanceAdminActionState> {
  const access = await resolveHrisAccessForRequest(tenantSlug);
  if (access.status !== "allowed") return NO_ACCESS;

  const reason = String(formData.get("reason") ?? "").trim();
  if (!reason) return { error: "A reason is required to mark a goal not applicable." };

  const supabase = await createSupabaseServerClient();
  try {
    await markPerformanceGoalNotApplicable(supabase, { goalAssignmentId, expectedVersion, reason, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof PerformanceMutationError) return { error: `Could not mark this goal not applicable: ${error.message}` };
    throw error;
  }

  revalidatePath(path(tenantSlug));
  return OK;
}

export async function assignPerformanceReviewerAction(tenantSlug: string, cycleId: string, _prevState: PerformanceAdminActionState, formData: FormData): Promise<PerformanceAdminActionState> {
  const access = await resolveHrisAccessForRequest(tenantSlug);
  if (access.status !== "allowed") return NO_ACCESS;

  const employeeId = String(formData.get("employeeId") ?? "").trim();
  const role = String(formData.get("role") ?? "reviewer");
  const assignedToEmployeeId = String(formData.get("assignedToEmployeeId") ?? "").trim();
  if (!employeeId || !assignedToEmployeeId) return { error: "Employee and assignee are both required." };

  const supabase = await createSupabaseServerClient();
  try {
    await assignPerformanceReviewer(supabase, { cycleId, employeeId, role, assignedToEmployeeId, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof PerformanceMutationError) return { error: `Could not assign this reviewer: ${error.message}` };
    throw error;
  }

  revalidatePath(path(tenantSlug));
  return OK;
}

export async function reassignPerformanceReviewerAssignmentAction(tenantSlug: string, assignmentId: string, _prevState: PerformanceAdminActionState, formData: FormData): Promise<PerformanceAdminActionState> {
  const access = await resolveHrisAccessForRequest(tenantSlug);
  if (access.status !== "allowed") return NO_ACCESS;

  const newAssignedToEmployeeId = String(formData.get("newAssignedToEmployeeId") ?? "").trim();
  const reason = String(formData.get("reason") ?? "").trim();
  if (!newAssignedToEmployeeId || !reason) return { error: "A new assignee and a reason are both required." };

  const supabase = await createSupabaseServerClient();
  try {
    await reassignPerformanceReviewerAssignment(supabase, { assignmentId, newAssignedToEmployeeId, reason, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof PerformanceMutationError) return { error: `Could not reassign this reviewer: ${error.message}` };
    throw error;
  }

  revalidatePath(path(tenantSlug));
  return OK;
}

export async function scorePerformanceGoalAction(tenantSlug: string, assessmentId: string, goalAssignmentId: string, _prevState: PerformanceAdminActionState, formData: FormData): Promise<PerformanceAdminActionState> {
  const access = await resolveHrisAccessForRequest(tenantSlug);
  if (access.status !== "allowed") return NO_ACCESS;

  const actualValueRaw = String(formData.get("actualValue") ?? "").trim();
  const manualScoreRaw = String(formData.get("manualScore") ?? "").trim();
  const scoreRationale = String(formData.get("scoreRationale") ?? "").trim();
  if (!scoreRationale) return { error: "A score rationale is required." };

  const supabase = await createSupabaseServerClient();
  try {
    await upsertPerformanceAssessmentKpiScore(supabase, {
      assessmentId, goalAssignmentId, actualValue: actualValueRaw ? Number(actualValueRaw) : null, manualScore: manualScoreRaw ? Number(manualScoreRaw) : null,
      scoreRationale, actorAuthUserId: access.authUserId, actorLabel: access.authUserId,
    });
  } catch (error) {
    if (error instanceof PerformanceMutationError) return { error: `Could not record this score: ${error.message}` };
    throw error;
  }

  revalidatePath(path(tenantSlug));
  return OK;
}

export async function submitPerformanceManagerAssessmentAction(tenantSlug: string, assessmentId: string, expectedVersion: number, _prevState: PerformanceAdminActionState, formData: FormData): Promise<PerformanceAdminActionState> {
  const access = await resolveHrisAccessForRequest(tenantSlug);
  if (access.status !== "allowed") return NO_ACCESS;

  const overallComment = String(formData.get("overallComment") ?? "").trim() || null;

  const supabase = await createSupabaseServerClient();
  try {
    await submitPerformanceManagerAssessment(supabase, { assessmentId, expectedVersion, overallComment, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof PerformanceMutationError) return { error: `Could not submit this manager assessment: ${error.message}` };
    throw error;
  }

  revalidatePath(path(tenantSlug));
  return OK;
}

export async function submitPerformanceReviewerAssessmentAction(tenantSlug: string, assessmentId: string, expectedVersion: number, _prevState: PerformanceAdminActionState, formData: FormData): Promise<PerformanceAdminActionState> {
  const access = await resolveHrisAccessForRequest(tenantSlug);
  if (access.status !== "allowed") return NO_ACCESS;

  const overallComment = String(formData.get("overallComment") ?? "").trim() || null;

  const supabase = await createSupabaseServerClient();
  try {
    await submitPerformanceReviewerAssessment(supabase, { assessmentId, expectedVersion, overallComment, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof PerformanceMutationError) return { error: `Could not submit this reviewer assessment: ${error.message}` };
    throw error;
  }

  revalidatePath(path(tenantSlug));
  return OK;
}

export async function calibratePerformanceOutcomeScoreAction(tenantSlug: string, outcomeId: string, expectedVersion: number, _prevState: PerformanceAdminActionState, formData: FormData): Promise<PerformanceAdminActionState> {
  const access = await resolveHrisAccessForRequest(tenantSlug);
  if (access.status !== "allowed") return NO_ACCESS;

  const adjustedScore = Number(formData.get("adjustedScore") ?? Number.NaN);
  const reason = String(formData.get("reason") ?? "").trim();
  if (!Number.isFinite(adjustedScore) || !reason) return { error: "An adjusted score and a reason are both required." };

  const supabase = await createSupabaseServerClient();
  try {
    await calibratePerformanceOutcomeScore(supabase, { outcomeId, expectedVersion, adjustedScore, reason, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof PerformanceMutationError) return { error: `Could not calibrate this outcome (requires HRS:Override; self-calibration is always blocked): ${error.message}` };
    throw error;
  }

  revalidatePath(path(tenantSlug));
  return OK;
}

export async function publishPerformanceOutcomeAction(tenantSlug: string, outcomeId: string, expectedVersion: number, _prevState: PerformanceAdminActionState, _formData: FormData): Promise<PerformanceAdminActionState> {
  const access = await resolveHrisAccessForRequest(tenantSlug);
  if (access.status !== "allowed") return NO_ACCESS;

  const supabase = await createSupabaseServerClient();
  try {
    await publishPerformanceOutcome(supabase, { outcomeId, expectedVersion, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof PerformanceMutationError) return { error: `Could not publish this outcome: ${error.message}` };
    throw error;
  }

  revalidatePath(path(tenantSlug));
  return OK;
}

export async function decidePerformanceAppealAction(
  tenantSlug: string, appealId: string, expectedVersion: number, decision: "uphold" | "overturn", _prevState: PerformanceAdminActionState, formData: FormData,
): Promise<PerformanceAdminActionState> {
  const access = await resolveHrisAccessForRequest(tenantSlug);
  if (access.status !== "allowed") return NO_ACCESS;

  const decisionReason = String(formData.get("decisionReason") ?? "").trim();
  if (!decisionReason) return { error: "A decision reason is required." };

  const supabase = await createSupabaseServerClient();
  try {
    await decidePerformanceAppeal(supabase, { appealId, expectedVersion, decision, decisionReason, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof PerformanceMutationError) return { error: `Could not ${decision} this appeal: ${error.message}` };
    throw error;
  }

  revalidatePath(path(tenantSlug));
  return OK;
}
