"use server";

/**
 * HR/manager/talent-admin Training and Talent Server Actions (HRT-284,
 * CG-S12-HRT-012). Every write here is permission-gated at the RPC layer
 * (HRS:Edit/Approve/Override, or a structural self-decision/assigned-
 * reviewer check) -- this file never re-implements or weakens that gate,
 * it only forwards.
 */

import { revalidatePath } from "next/cache";
import { createSupabaseServerClient } from "../../../../../lib/supabase/server.ts";
import { resolveHrisAccessForRequest } from "../../../../../lib/portal/resolve-hris-access.server.ts";
import {
  createTrainingCompetency,
  publishTrainingCompetency,
  createTrainingCourse,
  createTrainingCourseVersion,
  publishTrainingCourseVersion,
  addTrainingCourseCompetency,
  addTrainingCoursePrerequisite,
  createTrainingProvider,
  createTrainingSession,
  cancelTrainingSession,
  enrollEmployeeInTrainingSession,
  bulkAssignMandatoryTrainingSession,
  decideTrainingEnrollment,
  recordTrainingAttendance,
  recordTrainingCompletion,
  recordTrainingAssessment,
  issueTrainingCertificate,
  importHistoricalTrainingCertificate,
  attachTrainingCertificateEvidence,
  attachTrainingProviderEvidence,
  verifyTrainingCertificate,
  revokeTrainingCertificate,
  runTrainingCertificateExpiryBatch,
  runTrainingCertificateExpiryReminderBatch,
  createTrainingDevelopmentPlan,
  addTrainingDevelopmentPlanAction,
  createTalentReviewCycle,
  transitionTalentReviewCycleStatus,
  assignTalentReviewer,
  reassignTalentReviewer,
  createTalentPool,
  addTalentPoolMember,
  removeTalentPoolMember,
  proposeSuccessionCandidate,
  decideSuccessionCandidate,
  TrainingTalentMutationError,
} from "../../../../../server/mutations/training-talent.ts";

export interface TrainingTalentAdminActionState {
  readonly error: string | null;
}

const OK: TrainingTalentAdminActionState = { error: null };
const NO_ACCESS: TrainingTalentAdminActionState = { error: "You don't have access to this organization's HRIS workspace." };

function path(tenantSlug: string): string {
  return `/${tenantSlug}/hris/training-talent`;
}

export async function createTrainingCompetencyAction(tenantSlug: string, _prevState: TrainingTalentAdminActionState, formData: FormData): Promise<TrainingTalentAdminActionState> {
  const access = await resolveHrisAccessForRequest(tenantSlug);
  if (access.status !== "allowed") return NO_ACCESS;

  const code = String(formData.get("code") ?? "").trim();
  const name = String(formData.get("name") ?? "").trim();
  const category = String(formData.get("category") ?? "").trim() || null;
  if (!code || !name) return { error: "Code and name are both required." };

  const supabase = await createSupabaseServerClient();
  try {
    await createTrainingCompetency(supabase, { tenantId: access.tenant.id, code, name, description: null, category, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof TrainingTalentMutationError) return { error: `Could not create this competency: ${error.message}` };
    throw error;
  }

  revalidatePath(path(tenantSlug));
  return OK;
}

export async function publishTrainingCompetencyAction(tenantSlug: string, competencyId: string, expectedVersion: number, _prevState: TrainingTalentAdminActionState, _formData: FormData): Promise<TrainingTalentAdminActionState> {
  const access = await resolveHrisAccessForRequest(tenantSlug);
  if (access.status !== "allowed") return NO_ACCESS;

  const supabase = await createSupabaseServerClient();
  try {
    await publishTrainingCompetency(supabase, { competencyId, expectedVersion, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof TrainingTalentMutationError) return { error: `Could not publish this competency: ${error.message}` };
    throw error;
  }

  revalidatePath(path(tenantSlug));
  return OK;
}

export async function createTrainingCourseAction(tenantSlug: string, _prevState: TrainingTalentAdminActionState, formData: FormData): Promise<TrainingTalentAdminActionState> {
  const access = await resolveHrisAccessForRequest(tenantSlug);
  if (access.status !== "allowed") return NO_ACCESS;

  const code = String(formData.get("code") ?? "").trim();
  const name = String(formData.get("name") ?? "").trim();
  const category = String(formData.get("category") ?? "").trim() || null;
  if (!code || !name) return { error: "Code and name are both required." };

  const supabase = await createSupabaseServerClient();
  try {
    const course = await createTrainingCourse(supabase, { tenantId: access.tenant.id, code, name, category, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
    await createTrainingCourseVersion(supabase, {
      courseId: course.id, description: String(formData.get("description") ?? "").trim() || null, deliveryMode: String(formData.get("deliveryMode") ?? "in_person"),
      durationHours: null, isMandatory: formData.get("isMandatory") === "on", requiresEnrollmentApproval: formData.get("requiresEnrollmentApproval") === "on",
      requiresAssessment: formData.get("requiresAssessment") === "on",
      passingScore: formData.get("requiresAssessment") === "on" ? Number(formData.get("passingScore") ?? 70) : null,
      issuesCertificate: formData.get("issuesCertificate") === "on",
      certificateValidityMonths: formData.get("issuesCertificate") === "on" && formData.get("certificateValidityMonths") ? Number(formData.get("certificateValidityMonths")) : null,
      actorAuthUserId: access.authUserId, actorLabel: access.authUserId,
    });
  } catch (error) {
    if (error instanceof TrainingTalentMutationError) return { error: `Could not create this course: ${error.message}` };
    throw error;
  }

  revalidatePath(path(tenantSlug));
  return OK;
}

export async function publishTrainingCourseVersionAction(tenantSlug: string, versionId: string, expectedVersion: number, _prevState: TrainingTalentAdminActionState, _formData: FormData): Promise<TrainingTalentAdminActionState> {
  const access = await resolveHrisAccessForRequest(tenantSlug);
  if (access.status !== "allowed") return NO_ACCESS;

  const supabase = await createSupabaseServerClient();
  try {
    await publishTrainingCourseVersion(supabase, { versionId, expectedVersion, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof TrainingTalentMutationError) return { error: `Could not publish this course version: ${error.message}` };
    throw error;
  }

  revalidatePath(path(tenantSlug));
  return OK;
}

export async function addTrainingCourseCompetencyAction(tenantSlug: string, courseId: string, _prevState: TrainingTalentAdminActionState, formData: FormData): Promise<TrainingTalentAdminActionState> {
  const access = await resolveHrisAccessForRequest(tenantSlug);
  if (access.status !== "allowed") return NO_ACCESS;

  const competencyId = String(formData.get("competencyId") ?? "").trim();
  if (!competencyId) return { error: "A competency is required." };

  const supabase = await createSupabaseServerClient();
  try {
    await addTrainingCourseCompetency(supabase, { courseId, competencyId, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof TrainingTalentMutationError) return { error: `Could not link this competency: ${error.message}` };
    throw error;
  }

  revalidatePath(path(tenantSlug));
  return OK;
}

export async function addTrainingCoursePrerequisiteAction(tenantSlug: string, courseId: string, _prevState: TrainingTalentAdminActionState, formData: FormData): Promise<TrainingTalentAdminActionState> {
  const access = await resolveHrisAccessForRequest(tenantSlug);
  if (access.status !== "allowed") return NO_ACCESS;

  const prerequisiteCourseId = String(formData.get("prerequisiteCourseId") ?? "").trim();
  if (!prerequisiteCourseId) return { error: "A prerequisite course is required." };

  const supabase = await createSupabaseServerClient();
  try {
    await addTrainingCoursePrerequisite(supabase, { courseId, prerequisiteCourseId, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof TrainingTalentMutationError) return { error: `Could not add this prerequisite: ${error.message}` };
    throw error;
  }

  revalidatePath(path(tenantSlug));
  return OK;
}

export async function createTrainingProviderAction(tenantSlug: string, _prevState: TrainingTalentAdminActionState, formData: FormData): Promise<TrainingTalentAdminActionState> {
  const access = await resolveHrisAccessForRequest(tenantSlug);
  if (access.status !== "allowed") return NO_ACCESS;

  const name = String(formData.get("name") ?? "").trim();
  const providerType = String(formData.get("providerType") ?? "internal");
  if (!name) return { error: "A provider name is required." };

  const supabase = await createSupabaseServerClient();
  try {
    await createTrainingProvider(supabase, {
      tenantId: access.tenant.id, name, providerType, contactName: null, contactEmail: null, contactPhone: null, actorAuthUserId: access.authUserId, actorLabel: access.authUserId,
    });
  } catch (error) {
    if (error instanceof TrainingTalentMutationError) return { error: `Could not create this provider: ${error.message}` };
    throw error;
  }

  revalidatePath(path(tenantSlug));
  return OK;
}

export async function createTrainingSessionAction(tenantSlug: string, _prevState: TrainingTalentAdminActionState, formData: FormData): Promise<TrainingTalentAdminActionState> {
  const access = await resolveHrisAccessForRequest(tenantSlug);
  if (access.status !== "allowed") return NO_ACCESS;

  const courseVersionId = String(formData.get("courseVersionId") ?? "").trim();
  const sessionCode = String(formData.get("sessionCode") ?? "").trim();
  const startAt = String(formData.get("startAt") ?? "").trim();
  const endAt = String(formData.get("endAt") ?? "").trim();
  const capacity = Number(formData.get("capacity") ?? 0);
  if (!courseVersionId || !sessionCode || !startAt || !endAt || capacity <= 0) return { error: "A published course version, session code, start/end time, and a positive capacity are all required." };

  const supabase = await createSupabaseServerClient();
  try {
    await createTrainingSession(supabase, {
      tenantId: access.tenant.id, courseVersionId, providerId: String(formData.get("providerId") ?? "").trim() || null, sessionCode,
      location: String(formData.get("location") ?? "").trim() || null, startAt, endAt, capacity, actorAuthUserId: access.authUserId, actorLabel: access.authUserId,
    });
  } catch (error) {
    if (error instanceof TrainingTalentMutationError) return { error: `Could not create this session: ${error.message}` };
    throw error;
  }

  revalidatePath(path(tenantSlug));
  return OK;
}

export async function cancelTrainingSessionAction(tenantSlug: string, sessionId: string, expectedVersion: number, _prevState: TrainingTalentAdminActionState, formData: FormData): Promise<TrainingTalentAdminActionState> {
  const access = await resolveHrisAccessForRequest(tenantSlug);
  if (access.status !== "allowed") return NO_ACCESS;

  const reason = String(formData.get("reason") ?? "").trim();
  if (!reason) return { error: "A reason is required to cancel a session." };

  const supabase = await createSupabaseServerClient();
  try {
    await cancelTrainingSession(supabase, { sessionId, expectedVersion, reason, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof TrainingTalentMutationError) return { error: `Could not cancel this session (requires HRS:Override): ${error.message}` };
    throw error;
  }

  revalidatePath(path(tenantSlug));
  return OK;
}

export async function enrollEmployeeInTrainingSessionAction(tenantSlug: string, sessionId: string, _prevState: TrainingTalentAdminActionState, formData: FormData): Promise<TrainingTalentAdminActionState> {
  const access = await resolveHrisAccessForRequest(tenantSlug);
  if (access.status !== "allowed") return NO_ACCESS;

  const employeeId = String(formData.get("employeeId") ?? "").trim();
  if (!employeeId) return { error: "An employee is required." };

  const supabase = await createSupabaseServerClient();
  try {
    await enrollEmployeeInTrainingSession(supabase, { tenantId: access.tenant.id, sessionId, employeeId, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof TrainingTalentMutationError) return { error: `Could not enroll this employee: ${error.message}` };
    throw error;
  }

  revalidatePath(path(tenantSlug));
  return OK;
}

export async function bulkAssignMandatoryTrainingSessionAction(tenantSlug: string, sessionId: string, _prevState: TrainingTalentAdminActionState, _formData: FormData): Promise<TrainingTalentAdminActionState> {
  const access = await resolveHrisAccessForRequest(tenantSlug);
  if (access.status !== "allowed") return NO_ACCESS;

  const supabase = await createSupabaseServerClient();
  try {
    await bulkAssignMandatoryTrainingSession(supabase, { tenantId: access.tenant.id, sessionId, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof TrainingTalentMutationError) return { error: `Could not bulk-assign this mandatory session: ${error.message}` };
    throw error;
  }

  revalidatePath(path(tenantSlug));
  return OK;
}

export async function decideTrainingEnrollmentAction(
  tenantSlug: string, enrollmentId: string, expectedVersion: number, decision: "approve" | "reject", _prevState: TrainingTalentAdminActionState, formData: FormData,
): Promise<TrainingTalentAdminActionState> {
  const access = await resolveHrisAccessForRequest(tenantSlug);
  if (access.status !== "allowed") return NO_ACCESS;

  const decisionReason = String(formData.get("decisionReason") ?? "").trim() || null;
  if (decision === "reject" && !decisionReason) return { error: "A reason is required to reject an enrollment request." };

  const supabase = await createSupabaseServerClient();
  try {
    await decideTrainingEnrollment(supabase, { enrollmentId, expectedVersion, decision, decisionReason, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof TrainingTalentMutationError) return { error: `Could not ${decision} this enrollment request: ${error.message}` };
    throw error;
  }

  revalidatePath(path(tenantSlug));
  return OK;
}

/** Reads enrollment_id from the form itself (typed/pasted by the caller) rather than a bound row parameter -- this action is reused across arbitrary enrollments, not rendered once per row. */
export async function recordTrainingAttendanceByIdAction(tenantSlug: string, _prevState: TrainingTalentAdminActionState, formData: FormData): Promise<TrainingTalentAdminActionState> {
  const access = await resolveHrisAccessForRequest(tenantSlug);
  if (access.status !== "allowed") return NO_ACCESS;

  const enrollmentId = String(formData.get("enrollmentId") ?? "").trim();
  const attended = formData.get("attended") === "on";
  const hoursAttendedRaw = String(formData.get("hoursAttended") ?? "").trim();
  if (!enrollmentId) return { error: "An enrollment id is required." };

  const supabase = await createSupabaseServerClient();
  try {
    await recordTrainingAttendance(supabase, { enrollmentId, attended, hoursAttended: hoursAttendedRaw ? Number(hoursAttendedRaw) : null, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof TrainingTalentMutationError) return { error: `Could not record attendance: ${error.message}` };
    throw error;
  }

  revalidatePath(path(tenantSlug));
  return OK;
}

export async function recordTrainingCompletionByIdAction(tenantSlug: string, _prevState: TrainingTalentAdminActionState, formData: FormData): Promise<TrainingTalentAdminActionState> {
  const access = await resolveHrisAccessForRequest(tenantSlug);
  if (access.status !== "allowed") return NO_ACCESS;

  const enrollmentId = String(formData.get("enrollmentId") ?? "").trim();
  const expectedVersion = Number(formData.get("expectedVersion") ?? Number.NaN);
  const completionStatus = String(formData.get("completionStatus") ?? "completed") as "completed" | "failed" | "no_show";
  const notes = String(formData.get("notes") ?? "").trim() || null;
  if (!enrollmentId || !Number.isFinite(expectedVersion)) return { error: "An enrollment id and its current version are both required." };

  const supabase = await createSupabaseServerClient();
  try {
    await recordTrainingCompletion(supabase, { enrollmentId, expectedVersion, completionStatus, notes, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof TrainingTalentMutationError) return { error: `Could not record completion: ${error.message}` };
    throw error;
  }

  revalidatePath(path(tenantSlug));
  return OK;
}

export async function recordTrainingAssessmentByIdAction(tenantSlug: string, _prevState: TrainingTalentAdminActionState, formData: FormData): Promise<TrainingTalentAdminActionState> {
  const access = await resolveHrisAccessForRequest(tenantSlug);
  if (access.status !== "allowed") return NO_ACCESS;

  const enrollmentId = String(formData.get("enrollmentId") ?? "").trim();
  const score = Number(formData.get("score") ?? Number.NaN);
  const maxScore = Number(formData.get("maxScore") ?? 100);
  if (!enrollmentId || !Number.isFinite(score)) return { error: "An enrollment id and a score are both required." };

  const supabase = await createSupabaseServerClient();
  try {
    await recordTrainingAssessment(supabase, { enrollmentId, score, maxScore, notes: String(formData.get("notes") ?? "").trim() || null, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof TrainingTalentMutationError) return { error: `Could not record this assessment: ${error.message}` };
    throw error;
  }

  revalidatePath(path(tenantSlug));
  return OK;
}

export async function issueTrainingCertificateAction(tenantSlug: string, _prevState: TrainingTalentAdminActionState, formData: FormData): Promise<TrainingTalentAdminActionState> {
  const access = await resolveHrisAccessForRequest(tenantSlug);
  if (access.status !== "allowed") return NO_ACCESS;

  const employeeId = String(formData.get("employeeId") ?? "").trim();
  const courseVersionId = String(formData.get("courseVersionId") ?? "").trim();
  const issuedAt = String(formData.get("issuedAt") ?? "").trim();
  if (!employeeId || !courseVersionId || !issuedAt) return { error: "Employee, course version, and issued date are all required." };

  const supabase = await createSupabaseServerClient();
  try {
    await issueTrainingCertificate(supabase, {
      tenantId: access.tenant.id, employeeId, courseVersionId, enrollmentId: String(formData.get("enrollmentId") ?? "").trim() || null,
      certificateNumber: String(formData.get("certificateNumber") ?? "").trim() || null, issuedAt,
      expiryDate: String(formData.get("expiryDate") ?? "").trim() || null, actorAuthUserId: access.authUserId, actorLabel: access.authUserId,
    });
  } catch (error) {
    if (error instanceof TrainingTalentMutationError) return { error: `Could not issue this certificate: ${error.message}` };
    throw error;
  }

  revalidatePath(path(tenantSlug));
  return OK;
}

export async function importHistoricalTrainingCertificateAction(tenantSlug: string, _prevState: TrainingTalentAdminActionState, formData: FormData): Promise<TrainingTalentAdminActionState> {
  const access = await resolveHrisAccessForRequest(tenantSlug);
  if (access.status !== "allowed") return NO_ACCESS;

  const employeeId = String(formData.get("employeeId") ?? "").trim();
  const externalCourseName = String(formData.get("externalCourseName") ?? "").trim();
  const issuedAt = String(formData.get("issuedAt") ?? "").trim();
  if (!employeeId || !externalCourseName || !issuedAt) return { error: "Employee, an external course name, and issued date are all required." };

  const supabase = await createSupabaseServerClient();
  try {
    await importHistoricalTrainingCertificate(supabase, {
      tenantId: access.tenant.id, employeeId, externalCourseName, providerId: null, certificateNumber: String(formData.get("certificateNumber") ?? "").trim() || null,
      issuedAt, expiryDate: String(formData.get("expiryDate") ?? "").trim() || null, actorAuthUserId: access.authUserId, actorLabel: access.authUserId,
    });
  } catch (error) {
    if (error instanceof TrainingTalentMutationError) return { error: `Could not import this historical certificate: ${error.message}` };
    throw error;
  }

  revalidatePath(path(tenantSlug));
  return OK;
}

// Batch 283-285 Tier C fix (spec-compliance lens finding 1): the malware-scan/
// tenant/record-type re-validation this wraps (app.attach_training_certificate_
// evidence, reusing PLT-128) was real, tested, and granted at the SQL layer
// from HRT-284's own original commit, but had no UI caller anywhere -- the
// Certificates section's own description text ("private and malware-scanned
// before attach") was therefore describing a feature no user could actually
// reach. Wired here rather than merely disclosed: the backend was already
// complete, and this section's own copy already claimed the capability existed.
export async function attachTrainingCertificateEvidenceAction(tenantSlug: string, certificateId: string, expectedVersion: number, _prevState: TrainingTalentAdminActionState, formData: FormData): Promise<TrainingTalentAdminActionState> {
  const access = await resolveHrisAccessForRequest(tenantSlug);
  if (access.status !== "allowed") return NO_ACCESS;

  const evidenceFileId = String(formData.get("evidenceFileId") ?? "").trim();
  if (!evidenceFileId) return { error: "An evidence file id is required." };

  const supabase = await createSupabaseServerClient();
  try {
    await attachTrainingCertificateEvidence(supabase, { certificateId, expectedVersion, evidenceFileId, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof TrainingTalentMutationError) return { error: `Could not attach this evidence file: ${error.message}` };
    throw error;
  }

  revalidatePath(path(tenantSlug));
  return OK;
}

/**
 * `ISS-2026-083`. Mirrors `attachTrainingCertificateEvidenceAction` exactly, including re-checking
 * nothing: `HRS:Edit` and the PLT-128 file re-validation (tenant, record scope, malware scan) are
 * enforced inside `app.attach_training_provider_evidence` regardless of what this file does.
 */
export async function attachTrainingProviderEvidenceAction(tenantSlug: string, providerId: string, expectedVersion: number, _prevState: TrainingTalentAdminActionState, formData: FormData): Promise<TrainingTalentAdminActionState> {
  const access = await resolveHrisAccessForRequest(tenantSlug);
  if (access.status !== "allowed") return NO_ACCESS;

  const evidenceFileId = String(formData.get("evidenceFileId") ?? "").trim();
  if (!evidenceFileId) return { error: "An evidence file id is required." };

  const supabase = await createSupabaseServerClient();
  try {
    await attachTrainingProviderEvidence(supabase, { providerId, expectedVersion, evidenceFileId, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof TrainingTalentMutationError) return { error: `Could not attach this accreditation file: ${error.message}` };
    throw error;
  }

  revalidatePath(path(tenantSlug));
  return OK;
}

export async function verifyTrainingCertificateAction(tenantSlug: string, certificateId: string, expectedVersion: number, _prevState: TrainingTalentAdminActionState, _formData: FormData): Promise<TrainingTalentAdminActionState> {
  const access = await resolveHrisAccessForRequest(tenantSlug);
  if (access.status !== "allowed") return NO_ACCESS;

  const supabase = await createSupabaseServerClient();
  try {
    await verifyTrainingCertificate(supabase, { certificateId, expectedVersion, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof TrainingTalentMutationError) return { error: `Could not verify this certificate: ${error.message}` };
    throw error;
  }

  revalidatePath(path(tenantSlug));
  return OK;
}

export async function revokeTrainingCertificateAction(tenantSlug: string, certificateId: string, expectedVersion: number, _prevState: TrainingTalentAdminActionState, formData: FormData): Promise<TrainingTalentAdminActionState> {
  const access = await resolveHrisAccessForRequest(tenantSlug);
  if (access.status !== "allowed") return NO_ACCESS;

  const reason = String(formData.get("reason") ?? "").trim();
  if (!reason) return { error: "A reason is required to revoke a certificate." };

  const supabase = await createSupabaseServerClient();
  try {
    await revokeTrainingCertificate(supabase, { certificateId, expectedVersion, reason, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof TrainingTalentMutationError) return { error: `Could not revoke this certificate (requires HRS:Override): ${error.message}` };
    throw error;
  }

  revalidatePath(path(tenantSlug));
  return OK;
}

export async function runTrainingCertificateExpiryBatchAction(tenantSlug: string, _prevState: TrainingTalentAdminActionState, formData: FormData): Promise<TrainingTalentAdminActionState> {
  const access = await resolveHrisAccessForRequest(tenantSlug);
  if (access.status !== "allowed") return NO_ACCESS;

  const periodLabel = String(formData.get("periodLabel") ?? "").trim();
  if (!periodLabel) return { error: "A period label is required." };

  const supabase = await createSupabaseServerClient();
  try {
    await runTrainingCertificateExpiryBatch(supabase, { tenantId: access.tenant.id, asOfDate: new Date().toISOString().slice(0, 10), periodLabel, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof TrainingTalentMutationError) return { error: `Could not run the certificate expiry batch (requires HRS:Override): ${error.message}` };
    throw error;
  }

  revalidatePath(path(tenantSlug));
  return OK;
}

export async function runTrainingCertificateExpiryReminderBatchAction(tenantSlug: string, _prevState: TrainingTalentAdminActionState, formData: FormData): Promise<TrainingTalentAdminActionState> {
  const access = await resolveHrisAccessForRequest(tenantSlug);
  if (access.status !== "allowed") return NO_ACCESS;

  const periodLabel = String(formData.get("periodLabel") ?? "").trim();
  const lookaheadDays = Number(formData.get("lookaheadDays") ?? 30);
  if (!periodLabel) return { error: "A period label is required." };

  const supabase = await createSupabaseServerClient();
  try {
    await runTrainingCertificateExpiryReminderBatch(supabase, {
      tenantId: access.tenant.id, asOfDate: new Date().toISOString().slice(0, 10), lookaheadDays, periodLabel, actorAuthUserId: access.authUserId, actorLabel: access.authUserId,
    });
  } catch (error) {
    if (error instanceof TrainingTalentMutationError) return { error: `Could not run the certificate expiry reminder batch (requires HRS:Override): ${error.message}` };
    throw error;
  }

  revalidatePath(path(tenantSlug));
  return OK;
}

export async function createTrainingDevelopmentPlanAction(tenantSlug: string, _prevState: TrainingTalentAdminActionState, formData: FormData): Promise<TrainingTalentAdminActionState> {
  const access = await resolveHrisAccessForRequest(tenantSlug);
  if (access.status !== "allowed") return NO_ACCESS;

  const employeeId = String(formData.get("employeeId") ?? "").trim();
  const title = String(formData.get("title") ?? "").trim();
  if (!employeeId || !title) return { error: "Employee and title are both required." };

  const supabase = await createSupabaseServerClient();
  try {
    await createTrainingDevelopmentPlan(supabase, {
      tenantId: access.tenant.id, employeeId, title, cycleLabel: String(formData.get("cycleLabel") ?? "").trim() || null, linkedPerformanceOutcomeId: null,
      actorAuthUserId: access.authUserId, actorLabel: access.authUserId,
    });
  } catch (error) {
    if (error instanceof TrainingTalentMutationError) return { error: `Could not create this development plan (requires HRS:Edit or being this employee's direct manager): ${error.message}` };
    throw error;
  }

  revalidatePath(path(tenantSlug));
  return OK;
}

export async function addTrainingDevelopmentPlanActionAction(tenantSlug: string, planId: string, _prevState: TrainingTalentAdminActionState, formData: FormData): Promise<TrainingTalentAdminActionState> {
  const access = await resolveHrisAccessForRequest(tenantSlug);
  if (access.status !== "allowed") return NO_ACCESS;

  const description = String(formData.get("description") ?? "").trim();
  if (!description) return { error: "A description is required." };

  const supabase = await createSupabaseServerClient();
  try {
    await addTrainingDevelopmentPlanAction(supabase, {
      planId, actionType: String(formData.get("actionType") ?? "training"), description, linkedCourseId: String(formData.get("linkedCourseId") ?? "").trim() || null,
      targetDate: String(formData.get("targetDate") ?? "").trim() || null, actorAuthUserId: access.authUserId, actorLabel: access.authUserId,
    });
  } catch (error) {
    if (error instanceof TrainingTalentMutationError) return { error: `Could not add this action: ${error.message}` };
    throw error;
  }

  revalidatePath(path(tenantSlug));
  return OK;
}

export async function createTalentReviewCycleAction(tenantSlug: string, _prevState: TrainingTalentAdminActionState, formData: FormData): Promise<TrainingTalentAdminActionState> {
  const access = await resolveHrisAccessForRequest(tenantSlug);
  if (access.status !== "allowed") return NO_ACCESS;

  const name = String(formData.get("name") ?? "").trim();
  const periodLabel = String(formData.get("periodLabel") ?? "").trim();
  if (!name || !periodLabel) return { error: "Name and period label are both required." };

  const supabase = await createSupabaseServerClient();
  try {
    await createTalentReviewCycle(supabase, { tenantId: access.tenant.id, name, periodLabel, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof TrainingTalentMutationError) return { error: `Could not create this talent review cycle (requires HRS:Override): ${error.message}` };
    throw error;
  }

  revalidatePath(path(tenantSlug));
  return OK;
}

export async function transitionTalentReviewCycleStatusAction(
  tenantSlug: string, cycleId: string, expectedVersion: number, targetStatus: string, _prevState: TrainingTalentAdminActionState, _formData: FormData,
): Promise<TrainingTalentAdminActionState> {
  const access = await resolveHrisAccessForRequest(tenantSlug);
  if (access.status !== "allowed") return NO_ACCESS;

  const supabase = await createSupabaseServerClient();
  try {
    await transitionTalentReviewCycleStatus(supabase, { cycleId, expectedVersion, targetStatus, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof TrainingTalentMutationError) return { error: `Could not advance this cycle: ${error.message}` };
    throw error;
  }

  revalidatePath(path(tenantSlug));
  return OK;
}

export async function assignTalentReviewerAction(tenantSlug: string, cycleId: string, _prevState: TrainingTalentAdminActionState, formData: FormData): Promise<TrainingTalentAdminActionState> {
  const access = await resolveHrisAccessForRequest(tenantSlug);
  if (access.status !== "allowed") return NO_ACCESS;

  const subjectEmployeeId = String(formData.get("subjectEmployeeId") ?? "").trim();
  const reviewerEmployeeId = String(formData.get("reviewerEmployeeId") ?? "").trim();
  if (!subjectEmployeeId || !reviewerEmployeeId) return { error: "Subject and reviewer are both required." };

  const supabase = await createSupabaseServerClient();
  try {
    await assignTalentReviewer(supabase, { cycleId, subjectEmployeeId, reviewerEmployeeId, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof TrainingTalentMutationError) return { error: `Could not assign this reviewer: ${error.message}` };
    throw error;
  }

  revalidatePath(path(tenantSlug));
  return OK;
}

export async function reassignTalentReviewerAction(tenantSlug: string, assignmentId: string, _prevState: TrainingTalentAdminActionState, formData: FormData): Promise<TrainingTalentAdminActionState> {
  const access = await resolveHrisAccessForRequest(tenantSlug);
  if (access.status !== "allowed") return NO_ACCESS;

  const newReviewerEmployeeId = String(formData.get("newReviewerEmployeeId") ?? "").trim();
  const reason = String(formData.get("reason") ?? "").trim();
  if (!newReviewerEmployeeId || !reason) return { error: "A new reviewer and a reason are both required." };

  const supabase = await createSupabaseServerClient();
  try {
    await reassignTalentReviewer(supabase, { assignmentId, newReviewerEmployeeId, reason, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof TrainingTalentMutationError) return { error: `Could not reassign this reviewer: ${error.message}` };
    throw error;
  }

  revalidatePath(path(tenantSlug));
  return OK;
}

export async function createTalentPoolAction(tenantSlug: string, _prevState: TrainingTalentAdminActionState, formData: FormData): Promise<TrainingTalentAdminActionState> {
  const access = await resolveHrisAccessForRequest(tenantSlug);
  if (access.status !== "allowed") return NO_ACCESS;

  const name = String(formData.get("name") ?? "").trim();
  const poolType = String(formData.get("poolType") ?? "high_potential");
  if (!name) return { error: "A pool name is required." };

  const supabase = await createSupabaseServerClient();
  try {
    await createTalentPool(supabase, { tenantId: access.tenant.id, name, description: null, poolType, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof TrainingTalentMutationError) return { error: `Could not create this talent pool (requires HRS:Override): ${error.message}` };
    throw error;
  }

  revalidatePath(path(tenantSlug));
  return OK;
}

export async function addTalentPoolMemberAction(tenantSlug: string, poolId: string, _prevState: TrainingTalentAdminActionState, formData: FormData): Promise<TrainingTalentAdminActionState> {
  const access = await resolveHrisAccessForRequest(tenantSlug);
  if (access.status !== "allowed") return NO_ACCESS;

  const employeeId = String(formData.get("employeeId") ?? "").trim();
  const addedReason = String(formData.get("addedReason") ?? "").trim();
  if (!employeeId || !addedReason) return { error: "Employee and a reason are both required." };

  const supabase = await createSupabaseServerClient();
  try {
    await addTalentPoolMember(supabase, { poolId, employeeId, addedReason, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof TrainingTalentMutationError) return { error: `Could not add this pool member: ${error.message}` };
    throw error;
  }

  revalidatePath(path(tenantSlug));
  return OK;
}

export async function removeTalentPoolMemberAction(tenantSlug: string, memberId: string, expectedVersion: number, _prevState: TrainingTalentAdminActionState, formData: FormData): Promise<TrainingTalentAdminActionState> {
  const access = await resolveHrisAccessForRequest(tenantSlug);
  if (access.status !== "allowed") return NO_ACCESS;

  const removedReason = String(formData.get("removedReason") ?? "").trim();
  if (!removedReason) return { error: "A reason is required to remove a pool member." };

  const supabase = await createSupabaseServerClient();
  try {
    await removeTalentPoolMember(supabase, { memberId, expectedVersion, removedReason, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof TrainingTalentMutationError) return { error: `Could not remove this pool member: ${error.message}` };
    throw error;
  }

  revalidatePath(path(tenantSlug));
  return OK;
}

export async function proposeSuccessionCandidateAction(tenantSlug: string, _prevState: TrainingTalentAdminActionState, formData: FormData): Promise<TrainingTalentAdminActionState> {
  const access = await resolveHrisAccessForRequest(tenantSlug);
  if (access.status !== "allowed") return NO_ACCESS;

  const positionId = String(formData.get("positionId") ?? "").trim();
  const candidateEmployeeId = String(formData.get("candidateEmployeeId") ?? "").trim();
  const readiness = String(formData.get("readiness") ?? "ready_1_2_years");
  const decisionReason = String(formData.get("decisionReason") ?? "").trim();
  if (!positionId || !candidateEmployeeId || !decisionReason) return { error: "Position, candidate, and a reason are all required." };

  const supabase = await createSupabaseServerClient();
  try {
    await proposeSuccessionCandidate(supabase, { tenantId: access.tenant.id, positionId, candidateEmployeeId, readiness, decisionReason, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof TrainingTalentMutationError) return { error: `Could not propose this succession candidate: ${error.message}` };
    throw error;
  }

  revalidatePath(path(tenantSlug));
  return OK;
}

export async function decideSuccessionCandidateAction(
  tenantSlug: string, candidateId: string, expectedVersion: number, decision: "confirm" | "withdraw", _prevState: TrainingTalentAdminActionState, formData: FormData,
): Promise<TrainingTalentAdminActionState> {
  const access = await resolveHrisAccessForRequest(tenantSlug);
  if (access.status !== "allowed") return NO_ACCESS;

  const decisionReason = String(formData.get("decisionReason") ?? "").trim();
  if (!decisionReason) return { error: "A reason is required." };

  const supabase = await createSupabaseServerClient();
  try {
    await decideSuccessionCandidate(supabase, { candidateId, expectedVersion, decision, decisionReason, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof TrainingTalentMutationError) return { error: `Could not ${decision} this succession candidate: ${error.message}` };
    throw error;
  }

  revalidatePath(path(tenantSlug));
  return OK;
}
