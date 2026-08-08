"use server";

/**
 * Vendor Performance detail Server Actions (PRC-264, CG-S11-PRC-015). Same shape as
 * the queue's own actions.ts (resolve portal access, call the typed mutation wrapper,
 * translate a known mutation error, revalidate). One file for every mutation this
 * detail page surfaces: calculate/publish, source dispute raise/decide, issue raise/
 * status, corrective action add/status, manual adjustment request/decide, and the
 * governed lifecycle recommendation evaluate/decide.
 */

import { revalidatePath } from "next/cache";
import { createSupabaseServerClient } from "../../../../../../lib/supabase/server.ts";
import { resolveProcurementAccessForRequest } from "../../../../../../lib/portal/resolve-procurement-access.server.ts";
import { VENDOR_KPI_CODES, VENDOR_LIFECYCLE_RECOMMENDATION_ACTIONS } from "../../../../../../server/contracts/vendor-performance/vendor-performance.ts";
import {
  calculateVendorKpiMetrics,
  publishVendorKpiScorecard,
  raiseVendorKpiSourceDispute,
  decideVendorKpiSourceDispute,
  raiseVendorPerformanceIssue,
  updateVendorPerformanceIssueStatus,
  addVendorPerformanceCorrectiveAction,
  updateVendorPerformanceCorrectiveActionStatus,
  requestVendorKpiManualAdjustment,
  decideVendorKpiManualAdjustment,
  evaluateVendorLifecycleRecommendation,
  decideVendorLifecycleRecommendation,
  VendorPerformanceMutationError,
} from "../../../../../../server/mutations/vendor-performance.ts";

export interface VendorPerformanceActionState {
  readonly error: string | null;
}

const OK: VendorPerformanceActionState = { error: null };
const NO_ACCESS: VendorPerformanceActionState = { error: "You don't have access to this organization's Procurement workspace." };

async function requireAccess(tenantSlug: string) {
  const access = await resolveProcurementAccessForRequest(tenantSlug);
  if (access.status !== "allowed") return null;
  return access;
}

function detailPath(tenantSlug: string, vendorMasterId: string): string {
  return `/${tenantSlug}/procurement/vendor-performance/${vendorMasterId}`;
}

function asError(error: unknown): VendorPerformanceActionState {
  if (error instanceof VendorPerformanceMutationError) return { error: error.message };
  throw error;
}

export async function calculateVendorKpiMetricsAction(tenantSlug: string, vendorMasterId: string, _prevState: VendorPerformanceActionState, formData: FormData): Promise<VendorPerformanceActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return NO_ACCESS;

  const windowStart = String(formData.get("windowStart") ?? "").trim();
  const windowEnd = String(formData.get("windowEnd") ?? "").trim();
  if (!windowStart || !windowEnd) {
    return { error: "A window start and end are required." };
  }

  const supabase = await createSupabaseServerClient();
  try {
    await calculateVendorKpiMetrics(supabase, {
      tenantId: access.tenant.id,
      vendorMasterId,
      windowStart: new Date(windowStart).toISOString(),
      windowEnd: new Date(windowEnd).toISOString(),
      triggeredBy: "manual",
      idempotencyKey: crypto.randomUUID(),
      actorAuthUserId: access.authUserId,
      actorLabel: access.authUserId,
    });
  } catch (error) {
    return asError(error);
  }

  revalidatePath(detailPath(tenantSlug, vendorMasterId));
  return OK;
}

export async function publishVendorKpiScorecardAction(tenantSlug: string, vendorMasterId: string, _prevState: VendorPerformanceActionState, formData: FormData): Promise<VendorPerformanceActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return NO_ACCESS;

  const windowStart = String(formData.get("windowStart") ?? "").trim();
  const windowEnd = String(formData.get("windowEnd") ?? "").trim();
  if (!windowStart || !windowEnd) {
    return { error: "A window start and end are required (must match a window already calculated)." };
  }

  const supabase = await createSupabaseServerClient();
  try {
    await publishVendorKpiScorecard(supabase, {
      tenantId: access.tenant.id,
      vendorMasterId,
      windowStart: new Date(windowStart).toISOString(),
      windowEnd: new Date(windowEnd).toISOString(),
      idempotencyKey: crypto.randomUUID(),
      actorAuthUserId: access.authUserId,
      actorLabel: access.authUserId,
    });
  } catch (error) {
    return asError(error);
  }

  revalidatePath(detailPath(tenantSlug, vendorMasterId));
  return OK;
}

export async function raiseVendorKpiSourceDisputeAction(tenantSlug: string, vendorMasterId: string, _prevState: VendorPerformanceActionState, formData: FormData): Promise<VendorPerformanceActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return NO_ACCESS;

  const kpiCodeRaw = String(formData.get("kpiCode") ?? "").trim();
  if (!(VENDOR_KPI_CODES as readonly string[]).includes(kpiCodeRaw)) {
    return { error: "A valid KPI category is required." };
  }
  const sourceId = String(formData.get("sourceId") ?? "").trim();
  const reason = String(formData.get("reason") ?? "").trim();
  if (!sourceId || !reason) {
    return { error: "A source id and reason are required." };
  }

  const supabase = await createSupabaseServerClient();
  try {
    await raiseVendorKpiSourceDispute(supabase, {
      tenantId: access.tenant.id,
      vendorMasterId,
      kpiCode: kpiCodeRaw as (typeof VENDOR_KPI_CODES)[number],
      sourceId,
      sourceLabel: String(formData.get("sourceLabel") ?? "").trim() || null,
      reason,
      actorAuthUserId: access.authUserId,
      actorLabel: access.authUserId,
    });
  } catch (error) {
    return asError(error);
  }

  revalidatePath(detailPath(tenantSlug, vendorMasterId));
  return OK;
}

export async function decideVendorKpiSourceDisputeAction(tenantSlug: string, vendorMasterId: string, _prevState: VendorPerformanceActionState, formData: FormData): Promise<VendorPerformanceActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return NO_ACCESS;

  const disputeId = String(formData.get("disputeId") ?? "").trim();
  const expectedVersion = Number(String(formData.get("expectedVersion") ?? ""));
  const decision = String(formData.get("decision") ?? "").trim();
  const decisionNotes = String(formData.get("decisionNotes") ?? "").trim();
  if (!disputeId || !Number.isFinite(expectedVersion) || (decision !== "upheld" && decision !== "rejected") || !decisionNotes) {
    return { error: "A dispute id, version, decision (upheld/rejected), and decision notes are required." };
  }

  const supabase = await createSupabaseServerClient();
  try {
    await decideVendorKpiSourceDispute(supabase, { disputeId, expectedVersion, decision, decisionNotes, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    return asError(error);
  }

  revalidatePath(detailPath(tenantSlug, vendorMasterId));
  return OK;
}

export async function raiseVendorPerformanceIssueAction(tenantSlug: string, vendorMasterId: string, _prevState: VendorPerformanceActionState, formData: FormData): Promise<VendorPerformanceActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return NO_ACCESS;

  const title = String(formData.get("title") ?? "").trim();
  const severity = String(formData.get("severity") ?? "").trim();
  if (!title || !["low", "medium", "high", "critical"].includes(severity)) {
    return { error: "A title and a valid severity are required." };
  }
  const scorecardId = String(formData.get("scorecardId") ?? "").trim() || null;
  const kpiCodeRaw = String(formData.get("kpiCode") ?? "").trim();
  const kpiCode = (VENDOR_KPI_CODES as readonly string[]).includes(kpiCodeRaw) ? (kpiCodeRaw as (typeof VENDOR_KPI_CODES)[number]) : null;

  const supabase = await createSupabaseServerClient();
  try {
    await raiseVendorPerformanceIssue(supabase, {
      tenantId: access.tenant.id,
      vendorMasterId,
      scorecardId,
      kpiCode,
      severity: severity as "low" | "medium" | "high" | "critical",
      title,
      description: String(formData.get("description") ?? "").trim() || null,
      idempotencyKey: crypto.randomUUID(),
      actorAuthUserId: access.authUserId,
      actorLabel: access.authUserId,
    });
  } catch (error) {
    return asError(error);
  }

  revalidatePath(detailPath(tenantSlug, vendorMasterId));
  return OK;
}

export async function updateVendorPerformanceIssueStatusAction(tenantSlug: string, vendorMasterId: string, _prevState: VendorPerformanceActionState, formData: FormData): Promise<VendorPerformanceActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return NO_ACCESS;

  const issueId = String(formData.get("issueId") ?? "").trim();
  const expectedVersion = Number(String(formData.get("expectedVersion") ?? ""));
  const status = String(formData.get("status") ?? "").trim();
  if (!issueId || !Number.isFinite(expectedVersion) || !["open", "in_progress", "resolved", "closed"].includes(status)) {
    return { error: "An issue id, version, and valid status are required." };
  }

  const supabase = await createSupabaseServerClient();
  try {
    await updateVendorPerformanceIssueStatus(supabase, {
      issueId,
      expectedVersion,
      status: status as "open" | "in_progress" | "resolved" | "closed",
      resolutionNote: String(formData.get("resolutionNote") ?? "").trim() || null,
      actorAuthUserId: access.authUserId,
      actorLabel: access.authUserId,
    });
  } catch (error) {
    return asError(error);
  }

  revalidatePath(detailPath(tenantSlug, vendorMasterId));
  return OK;
}

export async function addVendorPerformanceCorrectiveActionAction(tenantSlug: string, vendorMasterId: string, _prevState: VendorPerformanceActionState, formData: FormData): Promise<VendorPerformanceActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return NO_ACCESS;

  const issueId = String(formData.get("issueId") ?? "").trim();
  const description = String(formData.get("description") ?? "").trim();
  if (!issueId || !description) {
    return { error: "An issue id and description are required." };
  }

  const supabase = await createSupabaseServerClient();
  try {
    await addVendorPerformanceCorrectiveAction(supabase, {
      issueId,
      description,
      ownerLabel: String(formData.get("ownerLabel") ?? "").trim() || null,
      dueDate: String(formData.get("dueDate") ?? "").trim() || null,
      idempotencyKey: crypto.randomUUID(),
      actorAuthUserId: access.authUserId,
      actorLabel: access.authUserId,
    });
  } catch (error) {
    return asError(error);
  }

  revalidatePath(detailPath(tenantSlug, vendorMasterId));
  return OK;
}

export async function updateVendorPerformanceCorrectiveActionStatusAction(
  tenantSlug: string,
  vendorMasterId: string,
  _prevState: VendorPerformanceActionState,
  formData: FormData,
): Promise<VendorPerformanceActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return NO_ACCESS;

  const actionId = String(formData.get("actionId") ?? "").trim();
  const expectedVersion = Number(String(formData.get("expectedVersion") ?? ""));
  const status = String(formData.get("status") ?? "").trim();
  if (!actionId || !Number.isFinite(expectedVersion) || !["open", "in_progress", "completed", "cancelled"].includes(status)) {
    return { error: "An action id, version, and valid status are required." };
  }

  const supabase = await createSupabaseServerClient();
  try {
    await updateVendorPerformanceCorrectiveActionStatus(supabase, {
      actionId,
      expectedVersion,
      status: status as "open" | "in_progress" | "completed" | "cancelled",
      completionNote: String(formData.get("completionNote") ?? "").trim() || null,
      actorAuthUserId: access.authUserId,
      actorLabel: access.authUserId,
    });
  } catch (error) {
    return asError(error);
  }

  revalidatePath(detailPath(tenantSlug, vendorMasterId));
  return OK;
}

export async function requestVendorKpiManualAdjustmentAction(tenantSlug: string, vendorMasterId: string, _prevState: VendorPerformanceActionState, formData: FormData): Promise<VendorPerformanceActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return NO_ACCESS;

  const scorecardId = String(formData.get("scorecardId") ?? "").trim();
  const kpiCodeRaw = String(formData.get("kpiCode") ?? "").trim();
  const adjustedRaw = String(formData.get("adjustedNormalizedScore") ?? "").trim();
  const reason = String(formData.get("reason") ?? "").trim();
  if (!scorecardId || !(VENDOR_KPI_CODES as readonly string[]).includes(kpiCodeRaw) || !adjustedRaw || !reason) {
    return { error: "A scorecard, KPI category, adjusted score, and reason are all required." };
  }

  const supabase = await createSupabaseServerClient();
  try {
    await requestVendorKpiManualAdjustment(supabase, {
      scorecardId,
      kpiCode: kpiCodeRaw as (typeof VENDOR_KPI_CODES)[number],
      adjustedNormalizedScore: Number(adjustedRaw),
      reason,
      idempotencyKey: crypto.randomUUID(),
      actorAuthUserId: access.authUserId,
      actorLabel: access.authUserId,
    });
  } catch (error) {
    return asError(error);
  }

  revalidatePath(detailPath(tenantSlug, vendorMasterId));
  return OK;
}

export async function decideVendorKpiManualAdjustmentAction(tenantSlug: string, vendorMasterId: string, _prevState: VendorPerformanceActionState, formData: FormData): Promise<VendorPerformanceActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return NO_ACCESS;

  const adjustmentId = String(formData.get("adjustmentId") ?? "").trim();
  const expectedVersion = Number(String(formData.get("expectedVersion") ?? ""));
  const decision = String(formData.get("decision") ?? "").trim();
  const decisionNotes = String(formData.get("decisionNotes") ?? "").trim();
  if (!adjustmentId || !Number.isFinite(expectedVersion) || (decision !== "approved" && decision !== "rejected") || !decisionNotes) {
    return { error: "An adjustment id, version, decision (approved/rejected), and decision notes are required." };
  }

  const supabase = await createSupabaseServerClient();
  try {
    await decideVendorKpiManualAdjustment(supabase, { adjustmentId, expectedVersion, decision, decisionNotes, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    return asError(error);
  }

  revalidatePath(detailPath(tenantSlug, vendorMasterId));
  return OK;
}

export async function evaluateVendorLifecycleRecommendationAction(
  tenantSlug: string,
  vendorMasterId: string,
  _prevState: VendorPerformanceActionState,
  formData: FormData,
): Promise<VendorPerformanceActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return NO_ACCESS;

  const scorecardId = String(formData.get("scorecardId") ?? "").trim() || null;
  const overrideActionRaw = String(formData.get("overrideAction") ?? "").trim();
  const overrideAction = (VENDOR_LIFECYCLE_RECOMMENDATION_ACTIONS as readonly string[]).includes(overrideActionRaw)
    ? (overrideActionRaw as (typeof VENDOR_LIFECYCLE_RECOMMENDATION_ACTIONS)[number])
    : null;
  const rationale = String(formData.get("rationale") ?? "").trim() || null;
  if (!scorecardId && (!overrideAction || !rationale)) {
    return { error: "Either a basis scorecard, or an override action with a rationale, is required." };
  }

  const supabase = await createSupabaseServerClient();
  try {
    await evaluateVendorLifecycleRecommendation(supabase, {
      tenantId: access.tenant.id,
      vendorMasterId,
      scorecardId,
      overrideAction,
      rationale,
      idempotencyKey: crypto.randomUUID(),
      actorAuthUserId: access.authUserId,
      actorLabel: access.authUserId,
    });
  } catch (error) {
    return asError(error);
  }

  revalidatePath(detailPath(tenantSlug, vendorMasterId));
  return OK;
}

export async function decideVendorLifecycleRecommendationAction(
  tenantSlug: string,
  vendorMasterId: string,
  _prevState: VendorPerformanceActionState,
  formData: FormData,
): Promise<VendorPerformanceActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return NO_ACCESS;

  const recommendationId = String(formData.get("recommendationId") ?? "").trim();
  const expectedVersion = Number(String(formData.get("expectedVersion") ?? ""));
  const decidedActionRaw = String(formData.get("decidedAction") ?? "").trim();
  const decisionNotes = String(formData.get("decisionNotes") ?? "").trim();
  if (!recommendationId || !Number.isFinite(expectedVersion) || !(VENDOR_LIFECYCLE_RECOMMENDATION_ACTIONS as readonly string[]).includes(decidedActionRaw) || !decisionNotes) {
    return { error: "A recommendation id, version, decided action, and decision notes are required." };
  }

  const supabase = await createSupabaseServerClient();
  try {
    await decideVendorLifecycleRecommendation(supabase, {
      recommendationId,
      expectedVersion,
      decidedAction: decidedActionRaw as (typeof VENDOR_LIFECYCLE_RECOMMENDATION_ACTIONS)[number],
      decisionNotes,
      evidenceRef: String(formData.get("evidenceRef") ?? "").trim() || null,
      actorAuthUserId: access.authUserId,
      actorLabel: access.authUserId,
    });
  } catch (error) {
    return asError(error);
  }

  revalidatePath(detailPath(tenantSlug, vendorMasterId));
  return OK;
}
