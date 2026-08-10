"use server";

/**
 * Application detail Server Actions (HRT-276, CG-S12-HRT-004): stage transitions,
 * assessments, interviews/feedback, offers. Mirrors the sibling actions.ts files'
 * shape exactly.
 */

import { revalidatePath } from "next/cache";
import { createSupabaseServerClient } from "../../../../../../../lib/supabase/server.ts";
import { resolveHrisAccessForRequest } from "../../../../../../../lib/portal/resolve-hris-access.server.ts";
import {
  transitionApplicationStage,
  rejectApplication,
  withdrawApplication,
  createCandidateAssessment,
  recordAssessmentResult,
  scheduleInterview,
  completeInterview,
  submitInterviewFeedback,
  createJobOfferVersion,
  submitJobOfferForApproval,
  decideJobOfferApproval,
  extendJobOffer,
  recordOfferResponse,
  RecruitmentMutationError,
} from "../../../../../../../server/mutations/recruitment.ts";
import type { ApplicationStage, AssessmentType, InterviewMode, InterviewRecommendation, EmploymentType, OfferResponse } from "../../../../../../../server/contracts/recruitment/recruitment.ts";

export interface ApplicationActionState {
  readonly error: string | null;
}

const OK: ApplicationActionState = { error: null };
const NO_ACCESS: ApplicationActionState = { error: "You don't have access to this organization's HRIS workspace." };

async function requireAccess(tenantSlug: string) {
  const access = await resolveHrisAccessForRequest(tenantSlug);
  if (access.status !== "allowed") return null;
  return access;
}

function detailPath(tenantSlug: string, applicationId: string): string {
  return `/${tenantSlug}/hris/recruitment/applications/${applicationId}`;
}

export async function transitionApplicationStageAction(
  tenantSlug: string,
  applicationId: string,
  expectedVersion: number,
  toStage: ApplicationStage,
  _prevState: ApplicationActionState,
  _formData: FormData,
): Promise<ApplicationActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return NO_ACCESS;
  if (toStage === "offer_accepted" || toStage === "rejected" || toStage === "withdrawn") {
    return { error: "Use the dedicated action for this transition." };
  }

  const supabase = await createSupabaseServerClient();
  try {
    await transitionApplicationStage(supabase, { id: applicationId, expectedVersion, toStage, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof RecruitmentMutationError) return { error: `Could not advance this application: ${error.message}` };
    throw error;
  }

  revalidatePath(detailPath(tenantSlug, applicationId));
  return OK;
}

export async function rejectApplicationAction(tenantSlug: string, applicationId: string, expectedVersion: number, _prevState: ApplicationActionState, formData: FormData): Promise<ApplicationActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return NO_ACCESS;
  const reason = String(formData.get("reason") ?? "").trim();
  if (!reason) return { error: "A reason is required to reject an application." };

  const supabase = await createSupabaseServerClient();
  try {
    await rejectApplication(supabase, { id: applicationId, expectedVersion, reason, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof RecruitmentMutationError) return { error: `Could not reject this application: ${error.message}` };
    throw error;
  }

  revalidatePath(detailPath(tenantSlug, applicationId));
  return OK;
}

export async function withdrawApplicationAction(tenantSlug: string, applicationId: string, expectedVersion: number, _prevState: ApplicationActionState, formData: FormData): Promise<ApplicationActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return NO_ACCESS;
  const reason = String(formData.get("reason") ?? "").trim();
  if (!reason) return { error: "A reason is required to withdraw an application." };

  const supabase = await createSupabaseServerClient();
  try {
    await withdrawApplication(supabase, { id: applicationId, expectedVersion, reason, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof RecruitmentMutationError) return { error: `Could not withdraw this application: ${error.message}` };
    throw error;
  }

  revalidatePath(detailPath(tenantSlug, applicationId));
  return OK;
}

export async function createCandidateAssessmentAction(tenantSlug: string, applicationId: string, _prevState: ApplicationActionState, formData: FormData): Promise<ApplicationActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return NO_ACCESS;

  const assessmentType = String(formData.get("assessmentType") ?? "technical") as AssessmentType;
  const criteriaVersion = String(formData.get("criteriaVersion") ?? "").trim();
  const maxScore = Number(String(formData.get("maxScore") ?? "100"));
  const passThresholdRaw = String(formData.get("passThreshold") ?? "").trim();

  const supabase = await createSupabaseServerClient();
  try {
    await createCandidateAssessment(supabase, {
      applicationId,
      assessmentType,
      criteriaVersion,
      maxScore,
      passThreshold: passThresholdRaw ? Number(passThresholdRaw) : null,
      actorAuthUserId: access.authUserId,
      actorLabel: access.authUserId,
    });
  } catch (error) {
    if (error instanceof RecruitmentMutationError) return { error: `Could not create this assessment: ${error.message}` };
    throw error;
  }

  revalidatePath(detailPath(tenantSlug, applicationId));
  return OK;
}

export async function recordAssessmentResultAction(
  tenantSlug: string,
  applicationId: string,
  assessmentId: string,
  expectedVersion: number,
  _prevState: ApplicationActionState,
  formData: FormData,
): Promise<ApplicationActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return NO_ACCESS;

  const score = Number(String(formData.get("score") ?? "0"));
  const notes = String(formData.get("notes") ?? "").trim() || null;

  const supabase = await createSupabaseServerClient();
  try {
    await recordAssessmentResult(supabase, { id: assessmentId, expectedVersion, score, notes, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof RecruitmentMutationError) return { error: `Could not record this result: ${error.message}` };
    throw error;
  }

  revalidatePath(detailPath(tenantSlug, applicationId));
  return OK;
}

export async function scheduleInterviewAction(tenantSlug: string, applicationId: string, _prevState: ApplicationActionState, formData: FormData): Promise<ApplicationActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return NO_ACCESS;

  const mode = String(formData.get("mode") ?? "video") as InterviewMode;
  const scheduledAt = String(formData.get("scheduledAt") ?? "").trim();
  const durationMinutes = Number(String(formData.get("durationMinutes") ?? "60"));
  const locationOrLink = String(formData.get("locationOrLink") ?? "").trim() || null;
  const interviewerEmployeeIds = String(formData.get("interviewerEmployeeId") ?? "")
    .trim()
    .split(",")
    .map((s) => s.trim())
    .filter(Boolean);

  if (!scheduledAt || interviewerEmployeeIds.length === 0) {
    return { error: "A scheduled time and at least one interviewer are required." };
  }

  const supabase = await createSupabaseServerClient();
  try {
    await scheduleInterview(supabase, {
      applicationId,
      round: null,
      mode,
      scheduledAt: new Date(scheduledAt).toISOString(),
      durationMinutes,
      locationOrLink,
      interviewerEmployeeIds,
      actorAuthUserId: access.authUserId,
      actorLabel: access.authUserId,
    });
  } catch (error) {
    if (error instanceof RecruitmentMutationError) return { error: `Could not schedule this interview: ${error.message}` };
    throw error;
  }

  revalidatePath(detailPath(tenantSlug, applicationId));
  return OK;
}

export async function completeInterviewAction(tenantSlug: string, applicationId: string, interviewId: string, expectedVersion: number, _prevState: ApplicationActionState, _formData: FormData): Promise<ApplicationActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return NO_ACCESS;

  const supabase = await createSupabaseServerClient();
  try {
    await completeInterview(supabase, { id: interviewId, expectedVersion, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof RecruitmentMutationError) return { error: `Could not complete this interview: ${error.message}` };
    throw error;
  }

  revalidatePath(detailPath(tenantSlug, applicationId));
  return OK;
}

/** Identity-gated -- succeeds only for the caller's own assigned interview (design note 5). */
export async function submitInterviewFeedbackAction(tenantSlug: string, applicationId: string, interviewId: string, _prevState: ApplicationActionState, formData: FormData): Promise<ApplicationActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return NO_ACCESS;

  const rating = Number(String(formData.get("rating") ?? "3"));
  const recommendation = String(formData.get("recommendation") ?? "yes") as InterviewRecommendation;
  const notes = String(formData.get("notes") ?? "").trim() || null;

  const supabase = await createSupabaseServerClient();
  try {
    await submitInterviewFeedback(supabase, { interviewId, rating, recommendation, notes, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof RecruitmentMutationError) return { error: `Could not submit feedback: ${error.message}` };
    throw error;
  }

  revalidatePath(detailPath(tenantSlug, applicationId));
  return OK;
}

export async function createJobOfferVersionAction(tenantSlug: string, applicationId: string, _prevState: ApplicationActionState, formData: FormData): Promise<ApplicationActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return NO_ACCESS;

  const compensationAmount = Number(String(formData.get("compensationAmount") ?? "0"));
  const compensationCurrency = String(formData.get("compensationCurrency") ?? "IDR").trim();
  const effectiveDate = String(formData.get("effectiveDate") ?? "").trim();
  const expiryDate = String(formData.get("expiryDate") ?? "").trim() || null;
  const title = String(formData.get("title") ?? "").trim();
  const employmentType = String(formData.get("employmentType") ?? "full_time") as EmploymentType;
  const benefitsNote = String(formData.get("benefitsNote") ?? "").trim() || null;

  if (!effectiveDate || !title) return { error: "An effective date and title are required." };

  const supabase = await createSupabaseServerClient();
  try {
    await createJobOfferVersion(supabase, {
      applicationId,
      compensationAmount,
      compensationCurrency,
      effectiveDate,
      expiryDate,
      title,
      employmentType,
      benefitsNote,
      actorAuthUserId: access.authUserId,
      actorLabel: access.authUserId,
    });
  } catch (error) {
    if (error instanceof RecruitmentMutationError) return { error: `Could not create this offer version: ${error.message}` };
    throw error;
  }

  revalidatePath(detailPath(tenantSlug, applicationId));
  return OK;
}

export async function submitJobOfferForApprovalAction(tenantSlug: string, applicationId: string, offerId: string, expectedVersion: number, _prevState: ApplicationActionState, _formData: FormData): Promise<ApplicationActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return NO_ACCESS;

  const supabase = await createSupabaseServerClient();
  try {
    await submitJobOfferForApproval(supabase, { offerId, expectedVersion, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof RecruitmentMutationError) return { error: `Could not submit this offer for approval: ${error.message}` };
    throw error;
  }

  revalidatePath(detailPath(tenantSlug, applicationId));
  return OK;
}

export async function decideJobOfferApprovalAction(tenantSlug: string, applicationId: string, requestStepId: string, decision: "approved" | "rejected", _prevState: ApplicationActionState, formData: FormData): Promise<ApplicationActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return NO_ACCESS;

  const reason = String(formData.get("reason") ?? "").trim() || null;

  const supabase = await createSupabaseServerClient();
  try {
    await decideJobOfferApproval(supabase, { requestStepId, decision, reason, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof RecruitmentMutationError) return { error: `Could not record this decision: ${error.message}` };
    throw error;
  }

  revalidatePath(detailPath(tenantSlug, applicationId));
  return OK;
}

export async function extendJobOfferAction(tenantSlug: string, applicationId: string, offerId: string, expectedVersion: number, _prevState: ApplicationActionState, _formData: FormData): Promise<ApplicationActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return NO_ACCESS;

  const supabase = await createSupabaseServerClient();
  try {
    await extendJobOffer(supabase, { offerId, expectedVersion, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof RecruitmentMutationError) return { error: `Could not extend this offer: ${error.message}` };
    throw error;
  }

  revalidatePath(detailPath(tenantSlug, applicationId));
  return OK;
}

export async function recordOfferResponseAction(
  tenantSlug: string,
  applicationId: string,
  offerId: string,
  expectedVersion: number,
  response: OfferResponse,
  _prevState: ApplicationActionState,
  formData: FormData,
): Promise<ApplicationActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return NO_ACCESS;

  const responseNote = String(formData.get("responseNote") ?? "").trim() || null;

  const supabase = await createSupabaseServerClient();
  try {
    await recordOfferResponse(supabase, { offerId, expectedVersion, response, responseNote, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof RecruitmentMutationError) return { error: `Could not record the candidate's response: ${error.message}` };
    throw error;
  }

  revalidatePath(detailPath(tenantSlug, applicationId));
  return OK;
}
