/**
 * Training and Talent mutation primitives (HRT-284, CG-S12-HRT-012). Thin,
 * typed wrappers around every write RPC in
 * supabase/migrations/20260731040000_create_hris_training_talent.sql.
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import {
  parseTrainingCompetencyRow,
  parseTrainingCourseRow,
  parseTrainingCourseVersionRow,
  parseTrainingCourseCompetencyRow,
  parseTrainingProviderRow,
  parseTrainingCoursePrerequisiteRow,
  parseTrainingSessionRow,
  parseTrainingEnrollmentRow,
  parseTrainingAssessmentRow,
  parseTrainingCertificateRow,
  parseTrainingDevelopmentPlanRow,
  parseTrainingDevelopmentPlanActionRow,
  parseTalentReviewCycleRow,
  parseTalentReviewAssignmentRow,
  parseTalentReviewRow,
  parseTalentPoolRow,
  parseTalentPoolMemberRow,
  parseTalentSuccessionCandidateRow,
  type TrainingCompetencyRow,
  type TrainingCourseRow,
  type TrainingCourseVersionRow,
  type TrainingCourseCompetencyRow,
  type TrainingProviderRow,
  type TrainingCoursePrerequisiteRow,
  type TrainingSessionRow,
  type TrainingEnrollmentRow,
  type TrainingAssessmentRow,
  type TrainingCertificateRow,
  type TrainingDevelopmentPlanRow,
  type TrainingDevelopmentPlanActionRow,
  type TalentReviewCycleRow,
  type TalentReviewAssignmentRow,
  type TalentReviewRow,
  type TalentPoolRow,
  type TalentPoolMemberRow,
  type TalentSuccessionCandidateRow,
} from "../contracts/training-talent/training-talent.ts";

export type TrainingTalentMutationRpcClient = Pick<SupabaseClient, "rpc">;

export const TRAINING_TALENT_KNOWN_MUTATION_ERROR_CODES = [
  "insufficient_authority", "insufficient_privilege", "stale_version", "reason_required", "invalid_transition",
  "training_competency_not_found", "training_competency_code_conflict",
  "training_course_not_found", "training_course_code_conflict", "training_course_version_not_found", "training_course_version_conflict",
  "course_version_not_published", "invalid_delivery_mode", "passing_score_required",
  "training_provider_not_found", "invalid_provider_type", "invalid_status",
  "training_course_prerequisite_not_found", "invalid_prerequisite",
  "training_session_not_found", "training_session_code_conflict", "invalid_session_dates", "invalid_capacity",
  "training_session_not_scheduled", "training_session_already_started", "training_prerequisite_not_met",
  "employee_not_active", "employee_not_found", "training_enrollment_already_active", "training_enrollment_not_found",
  "invalid_decision", "invalid_reschedule", "invalid_hours", "invalid_completion_status", "training_session_not_mandatory",
  "invalid_score", "training_assessment_not_applicable", "training_assessment_attempt_conflict",
  "training_certificate_not_found", "invalid_external_course_name", "evidence_file_not_found", "evidence_file_infected", "evidence_file_not_scanned",
  "invalid_period", "invalid_lookahead",
  "training_development_plan_not_found", "training_development_plan_action_not_found", "invalid_plan_status", "invalid_action_type", "description_required",
  "performance_outcome_not_found",
  "talent_review_cycle_not_found", "talent_review_cycle_name_conflict", "talent_review_cycle_closed",
  "talent_review_assignment_not_found", "talent_review_assignment_conflict", "invalid_assignee",
  "talent_review_not_found", "invalid_potential_rating", "invalid_risk_of_loss", "self_decision_not_permitted",
  "talent_pool_not_found", "talent_pool_name_conflict", "talent_pool_not_active", "invalid_pool_type",
  "talent_pool_member_not_found", "talent_pool_member_conflict",
  "position_not_found", "invalid_readiness", "talent_succession_candidate_not_found", "talent_succession_candidate_conflict",
] as const;
export type TrainingTalentKnownMutationErrorCode = (typeof TRAINING_TALENT_KNOWN_MUTATION_ERROR_CODES)[number];

export class TrainingTalentMutationError extends Error {
  readonly code: TrainingTalentKnownMutationErrorCode | "unknown";
  constructor(message: string) {
    super(message);
    this.name = "TrainingTalentMutationError";
    const prefix = message.split(":")[0]?.trim() ?? "";
    this.code = (TRAINING_TALENT_KNOWN_MUTATION_ERROR_CODES as readonly string[]).includes(prefix)
      ? (prefix as TrainingTalentKnownMutationErrorCode)
      : "unknown";
  }
}

function unwrap<T>(data: T, error: { message: string } | null): T {
  if (error) throw new TrainingTalentMutationError(error.message);
  return data;
}

// --- Competency ---

export async function createTrainingCompetency(
  client: TrainingTalentMutationRpcClient,
  input: { tenantId: string; code: string; name: string; description: string | null; category: string | null; actorAuthUserId: string; actorLabel: string },
): Promise<TrainingCompetencyRow> {
  const { data, error } = await client.rpc("create_training_competency", {
    p_tenant_id: input.tenantId, p_code: input.code, p_name: input.name, p_description: input.description, p_category: input.category,
    p_actor_auth_user_id: input.actorAuthUserId, p_actor_label: input.actorLabel,
  });
  return parseTrainingCompetencyRow(unwrap(data, error) as Record<string, unknown>);
}

export async function publishTrainingCompetency(
  client: TrainingTalentMutationRpcClient, input: { competencyId: string; expectedVersion: number; actorAuthUserId: string; actorLabel: string },
): Promise<TrainingCompetencyRow> {
  const { data, error } = await client.rpc("publish_training_competency", {
    p_competency_id: input.competencyId, p_expected_version: input.expectedVersion, p_actor_auth_user_id: input.actorAuthUserId, p_actor_label: input.actorLabel,
  });
  return parseTrainingCompetencyRow(unwrap(data, error) as Record<string, unknown>);
}

export async function archiveTrainingCompetency(
  client: TrainingTalentMutationRpcClient, input: { competencyId: string; expectedVersion: number; actorAuthUserId: string; actorLabel: string },
): Promise<TrainingCompetencyRow> {
  const { data, error } = await client.rpc("archive_training_competency", {
    p_competency_id: input.competencyId, p_expected_version: input.expectedVersion, p_actor_auth_user_id: input.actorAuthUserId, p_actor_label: input.actorLabel,
  });
  return parseTrainingCompetencyRow(unwrap(data, error) as Record<string, unknown>);
}

// --- Course / version / competency ---

export async function createTrainingCourse(
  client: TrainingTalentMutationRpcClient,
  input: { tenantId: string; code: string; name: string; category: string | null; actorAuthUserId: string; actorLabel: string },
): Promise<TrainingCourseRow> {
  const { data, error } = await client.rpc("create_training_course", {
    p_tenant_id: input.tenantId, p_code: input.code, p_name: input.name, p_category: input.category, p_actor_auth_user_id: input.actorAuthUserId, p_actor_label: input.actorLabel,
  });
  return parseTrainingCourseRow(unwrap(data, error) as Record<string, unknown>);
}

export async function createTrainingCourseVersion(
  client: TrainingTalentMutationRpcClient,
  input: {
    courseId: string; description: string | null; deliveryMode: string; durationHours: number | null; isMandatory: boolean;
    requiresEnrollmentApproval: boolean; requiresAssessment: boolean; passingScore: number | null; issuesCertificate: boolean;
    certificateValidityMonths: number | null; actorAuthUserId: string; actorLabel: string;
  },
): Promise<TrainingCourseVersionRow> {
  const { data, error } = await client.rpc("create_training_course_version", {
    p_course_id: input.courseId, p_description: input.description, p_delivery_mode: input.deliveryMode, p_duration_hours: input.durationHours,
    p_is_mandatory: input.isMandatory, p_requires_enrollment_approval: input.requiresEnrollmentApproval, p_requires_assessment: input.requiresAssessment,
    p_passing_score: input.passingScore, p_issues_certificate: input.issuesCertificate, p_certificate_validity_months: input.certificateValidityMonths,
    p_actor_auth_user_id: input.actorAuthUserId, p_actor_label: input.actorLabel,
  });
  return parseTrainingCourseVersionRow(unwrap(data, error) as Record<string, unknown>);
}

export async function publishTrainingCourseVersion(
  client: TrainingTalentMutationRpcClient, input: { versionId: string; expectedVersion: number; actorAuthUserId: string; actorLabel: string },
): Promise<TrainingCourseVersionRow> {
  const { data, error } = await client.rpc("publish_training_course_version", {
    p_version_id: input.versionId, p_expected_version: input.expectedVersion, p_actor_auth_user_id: input.actorAuthUserId, p_actor_label: input.actorLabel,
  });
  return parseTrainingCourseVersionRow(unwrap(data, error) as Record<string, unknown>);
}

export async function archiveTrainingCourseVersion(
  client: TrainingTalentMutationRpcClient, input: { versionId: string; expectedVersion: number; actorAuthUserId: string; actorLabel: string },
): Promise<TrainingCourseVersionRow> {
  const { data, error } = await client.rpc("archive_training_course_version", {
    p_version_id: input.versionId, p_expected_version: input.expectedVersion, p_actor_auth_user_id: input.actorAuthUserId, p_actor_label: input.actorLabel,
  });
  return parseTrainingCourseVersionRow(unwrap(data, error) as Record<string, unknown>);
}

export async function addTrainingCourseCompetency(
  client: TrainingTalentMutationRpcClient, input: { courseId: string; competencyId: string; actorAuthUserId: string; actorLabel: string },
): Promise<TrainingCourseCompetencyRow> {
  const { data, error } = await client.rpc("add_training_course_competency", {
    p_course_id: input.courseId, p_competency_id: input.competencyId, p_actor_auth_user_id: input.actorAuthUserId, p_actor_label: input.actorLabel,
  });
  return parseTrainingCourseCompetencyRow(unwrap(data, error) as Record<string, unknown>);
}

// --- Provider ---

export async function createTrainingProvider(
  client: TrainingTalentMutationRpcClient,
  input: { tenantId: string; name: string; providerType: string; contactName: string | null; contactEmail: string | null; contactPhone: string | null; actorAuthUserId: string; actorLabel: string },
): Promise<TrainingProviderRow> {
  const { data, error } = await client.rpc("create_training_provider", {
    p_tenant_id: input.tenantId, p_name: input.name, p_provider_type: input.providerType, p_contact_name: input.contactName,
    p_contact_email: input.contactEmail, p_contact_phone: input.contactPhone, p_actor_auth_user_id: input.actorAuthUserId, p_actor_label: input.actorLabel,
  });
  return parseTrainingProviderRow(unwrap(data, error) as Record<string, unknown>);
}

export async function updateTrainingProviderStatus(
  client: TrainingTalentMutationRpcClient, input: { providerId: string; expectedVersion: number; status: string; actorAuthUserId: string; actorLabel: string },
): Promise<TrainingProviderRow> {
  const { data, error } = await client.rpc("update_training_provider_status", {
    p_provider_id: input.providerId, p_expected_version: input.expectedVersion, p_status: input.status, p_actor_auth_user_id: input.actorAuthUserId, p_actor_label: input.actorLabel,
  });
  return parseTrainingProviderRow(unwrap(data, error) as Record<string, unknown>);
}

// --- Prerequisite ---

export async function addTrainingCoursePrerequisite(
  client: TrainingTalentMutationRpcClient, input: { courseId: string; prerequisiteCourseId: string; actorAuthUserId: string; actorLabel: string },
): Promise<TrainingCoursePrerequisiteRow> {
  const { data, error } = await client.rpc("add_training_course_prerequisite", {
    p_course_id: input.courseId, p_prerequisite_course_id: input.prerequisiteCourseId, p_actor_auth_user_id: input.actorAuthUserId, p_actor_label: input.actorLabel,
  });
  return parseTrainingCoursePrerequisiteRow(unwrap(data, error) as Record<string, unknown>);
}

export async function removeTrainingCoursePrerequisite(
  client: TrainingTalentMutationRpcClient, input: { prerequisiteId: string; actorAuthUserId: string; actorLabel: string },
): Promise<void> {
  const { error } = await client.rpc("remove_training_course_prerequisite", {
    p_prerequisite_id: input.prerequisiteId, p_actor_auth_user_id: input.actorAuthUserId, p_actor_label: input.actorLabel,
  });
  if (error) throw new TrainingTalentMutationError(error.message);
}

// --- Session ---

export async function createTrainingSession(
  client: TrainingTalentMutationRpcClient,
  input: {
    tenantId: string; courseVersionId: string; providerId: string | null; sessionCode: string; location: string | null;
    startAt: string; endAt: string; capacity: number; actorAuthUserId: string; actorLabel: string;
  },
): Promise<TrainingSessionRow> {
  const { data, error } = await client.rpc("create_training_session", {
    p_tenant_id: input.tenantId, p_course_version_id: input.courseVersionId, p_provider_id: input.providerId, p_session_code: input.sessionCode,
    p_location: input.location, p_start_at: input.startAt, p_end_at: input.endAt, p_capacity: input.capacity,
    p_actor_auth_user_id: input.actorAuthUserId, p_actor_label: input.actorLabel,
  });
  return parseTrainingSessionRow(unwrap(data, error) as Record<string, unknown>);
}

export async function cancelTrainingSession(
  client: TrainingTalentMutationRpcClient, input: { sessionId: string; expectedVersion: number; reason: string; actorAuthUserId: string; actorLabel: string },
): Promise<TrainingSessionRow> {
  const { data, error } = await client.rpc("cancel_training_session", {
    p_session_id: input.sessionId, p_expected_version: input.expectedVersion, p_reason: input.reason, p_actor_auth_user_id: input.actorAuthUserId, p_actor_label: input.actorLabel,
  });
  return parseTrainingSessionRow(unwrap(data, error) as Record<string, unknown>);
}

// --- Enrollment ---

export async function enrollSelfInTrainingSession(
  client: TrainingTalentMutationRpcClient, input: { tenantId: string; sessionId: string; actorAuthUserId: string; actorLabel: string },
): Promise<TrainingEnrollmentRow> {
  const { data, error } = await client.rpc("enroll_self_in_training_session", {
    p_tenant_id: input.tenantId, p_session_id: input.sessionId, p_actor_auth_user_id: input.actorAuthUserId, p_actor_label: input.actorLabel,
  });
  return parseTrainingEnrollmentRow(unwrap(data, error) as Record<string, unknown>);
}

export async function enrollEmployeeInTrainingSession(
  client: TrainingTalentMutationRpcClient, input: { tenantId: string; sessionId: string; employeeId: string; actorAuthUserId: string; actorLabel: string },
): Promise<TrainingEnrollmentRow> {
  const { data, error } = await client.rpc("enroll_employee_in_training_session", {
    p_tenant_id: input.tenantId, p_session_id: input.sessionId, p_employee_id: input.employeeId, p_actor_auth_user_id: input.actorAuthUserId, p_actor_label: input.actorLabel,
  });
  return parseTrainingEnrollmentRow(unwrap(data, error) as Record<string, unknown>);
}

export async function bulkAssignMandatoryTrainingSession(
  client: TrainingTalentMutationRpcClient, input: { tenantId: string; sessionId: string; actorAuthUserId: string; actorLabel: string },
): Promise<{ assignedCount: number; skippedCount: number }> {
  const { data, error } = await client.rpc("bulk_assign_mandatory_training_session", {
    p_tenant_id: input.tenantId, p_session_id: input.sessionId, p_actor_auth_user_id: input.actorAuthUserId, p_actor_label: input.actorLabel,
  });
  const row = unwrap(data, error) as { assigned_count: number; skipped_count: number } | { assigned_count: number; skipped_count: number }[];
  const r = Array.isArray(row) ? row[0] : row;
  return { assignedCount: r?.assigned_count ?? 0, skippedCount: r?.skipped_count ?? 0 };
}

export async function decideTrainingEnrollment(
  client: TrainingTalentMutationRpcClient,
  input: { enrollmentId: string; expectedVersion: number; decision: "approve" | "reject"; decisionReason: string | null; actorAuthUserId: string; actorLabel: string },
): Promise<TrainingEnrollmentRow> {
  const { data, error } = await client.rpc("decide_training_enrollment", {
    p_enrollment_id: input.enrollmentId, p_expected_version: input.expectedVersion, p_decision: input.decision, p_decision_reason: input.decisionReason,
    p_actor_auth_user_id: input.actorAuthUserId, p_actor_label: input.actorLabel,
  });
  return parseTrainingEnrollmentRow(unwrap(data, error) as Record<string, unknown>);
}

export async function cancelTrainingEnrollment(
  client: TrainingTalentMutationRpcClient, input: { enrollmentId: string; expectedVersion: number; reason: string; actorAuthUserId: string; actorLabel: string },
): Promise<TrainingEnrollmentRow> {
  const { data, error } = await client.rpc("cancel_training_enrollment", {
    p_enrollment_id: input.enrollmentId, p_expected_version: input.expectedVersion, p_reason: input.reason, p_actor_auth_user_id: input.actorAuthUserId, p_actor_label: input.actorLabel,
  });
  return parseTrainingEnrollmentRow(unwrap(data, error) as Record<string, unknown>);
}

export async function rescheduleTrainingEnrollment(
  client: TrainingTalentMutationRpcClient, input: { enrollmentId: string; newSessionId: string; actorAuthUserId: string; actorLabel: string },
): Promise<TrainingEnrollmentRow> {
  const { data, error } = await client.rpc("reschedule_training_enrollment", {
    p_enrollment_id: input.enrollmentId, p_new_session_id: input.newSessionId, p_actor_auth_user_id: input.actorAuthUserId, p_actor_label: input.actorLabel,
  });
  return parseTrainingEnrollmentRow(unwrap(data, error) as Record<string, unknown>);
}

export async function recordTrainingAttendance(
  client: TrainingTalentMutationRpcClient, input: { enrollmentId: string; attended: boolean; hoursAttended: number | null; actorAuthUserId: string; actorLabel: string },
): Promise<TrainingEnrollmentRow> {
  const { data, error } = await client.rpc("record_training_attendance", {
    p_enrollment_id: input.enrollmentId, p_attended: input.attended, p_hours_attended: input.hoursAttended, p_actor_auth_user_id: input.actorAuthUserId, p_actor_label: input.actorLabel,
  });
  return parseTrainingEnrollmentRow(unwrap(data, error) as Record<string, unknown>);
}

export async function recordTrainingCompletion(
  client: TrainingTalentMutationRpcClient,
  input: { enrollmentId: string; expectedVersion: number; completionStatus: "completed" | "failed" | "no_show"; notes: string | null; actorAuthUserId: string; actorLabel: string },
): Promise<TrainingEnrollmentRow> {
  const { data, error } = await client.rpc("record_training_completion", {
    p_enrollment_id: input.enrollmentId, p_expected_version: input.expectedVersion, p_completion_status: input.completionStatus, p_notes: input.notes,
    p_actor_auth_user_id: input.actorAuthUserId, p_actor_label: input.actorLabel,
  });
  return parseTrainingEnrollmentRow(unwrap(data, error) as Record<string, unknown>);
}

// --- Assessment ---

export async function recordTrainingAssessment(
  client: TrainingTalentMutationRpcClient,
  input: { enrollmentId: string; score: number; maxScore: number; notes: string | null; actorAuthUserId: string; actorLabel: string },
): Promise<TrainingAssessmentRow> {
  const { data, error } = await client.rpc("record_training_assessment", {
    p_enrollment_id: input.enrollmentId, p_score: input.score, p_max_score: input.maxScore, p_notes: input.notes,
    p_actor_auth_user_id: input.actorAuthUserId, p_actor_label: input.actorLabel,
  });
  return parseTrainingAssessmentRow(unwrap(data, error) as Record<string, unknown>);
}

// --- Certificate ---

export async function issueTrainingCertificate(
  client: TrainingTalentMutationRpcClient,
  input: {
    tenantId: string; employeeId: string; courseVersionId: string; enrollmentId: string | null; certificateNumber: string | null;
    issuedAt: string; expiryDate: string | null; actorAuthUserId: string; actorLabel: string;
  },
): Promise<TrainingCertificateRow> {
  const { data, error } = await client.rpc("issue_training_certificate", {
    p_tenant_id: input.tenantId, p_employee_id: input.employeeId, p_course_version_id: input.courseVersionId, p_enrollment_id: input.enrollmentId,
    p_certificate_number: input.certificateNumber, p_issued_at: input.issuedAt, p_expiry_date: input.expiryDate,
    p_actor_auth_user_id: input.actorAuthUserId, p_actor_label: input.actorLabel,
  });
  return parseTrainingCertificateRow(unwrap(data, error) as Record<string, unknown>);
}

export async function importHistoricalTrainingCertificate(
  client: TrainingTalentMutationRpcClient,
  input: {
    tenantId: string; employeeId: string; externalCourseName: string; providerId: string | null; certificateNumber: string | null;
    issuedAt: string; expiryDate: string | null; actorAuthUserId: string; actorLabel: string;
  },
): Promise<TrainingCertificateRow> {
  const { data, error } = await client.rpc("import_historical_training_certificate", {
    p_tenant_id: input.tenantId, p_employee_id: input.employeeId, p_external_course_name: input.externalCourseName, p_provider_id: input.providerId,
    p_certificate_number: input.certificateNumber, p_issued_at: input.issuedAt, p_expiry_date: input.expiryDate,
    p_actor_auth_user_id: input.actorAuthUserId, p_actor_label: input.actorLabel,
  });
  return parseTrainingCertificateRow(unwrap(data, error) as Record<string, unknown>);
}

export async function attachTrainingCertificateEvidence(
  client: TrainingTalentMutationRpcClient, input: { certificateId: string; expectedVersion: number; evidenceFileId: string; actorAuthUserId: string; actorLabel: string },
): Promise<TrainingCertificateRow> {
  const { data, error } = await client.rpc("attach_training_certificate_evidence", {
    p_certificate_id: input.certificateId, p_expected_version: input.expectedVersion, p_evidence_file_id: input.evidenceFileId,
    p_actor_auth_user_id: input.actorAuthUserId, p_actor_label: input.actorLabel,
  });
  return parseTrainingCertificateRow(unwrap(data, error) as Record<string, unknown>);
}

export async function verifyTrainingCertificate(
  client: TrainingTalentMutationRpcClient, input: { certificateId: string; expectedVersion: number; actorAuthUserId: string; actorLabel: string },
): Promise<TrainingCertificateRow> {
  const { data, error } = await client.rpc("verify_training_certificate", {
    p_certificate_id: input.certificateId, p_expected_version: input.expectedVersion, p_actor_auth_user_id: input.actorAuthUserId, p_actor_label: input.actorLabel,
  });
  return parseTrainingCertificateRow(unwrap(data, error) as Record<string, unknown>);
}

export async function revokeTrainingCertificate(
  client: TrainingTalentMutationRpcClient, input: { certificateId: string; expectedVersion: number; reason: string; actorAuthUserId: string; actorLabel: string },
): Promise<TrainingCertificateRow> {
  const { data, error } = await client.rpc("revoke_training_certificate", {
    p_certificate_id: input.certificateId, p_expected_version: input.expectedVersion, p_reason: input.reason, p_actor_auth_user_id: input.actorAuthUserId, p_actor_label: input.actorLabel,
  });
  return parseTrainingCertificateRow(unwrap(data, error) as Record<string, unknown>);
}

export async function renewTrainingCertificate(
  client: TrainingTalentMutationRpcClient,
  input: { oldCertificateId: string; certificateNumber: string | null; issuedAt: string; expiryDate: string | null; actorAuthUserId: string; actorLabel: string },
): Promise<TrainingCertificateRow> {
  const { data, error } = await client.rpc("renew_training_certificate", {
    p_old_certificate_id: input.oldCertificateId, p_certificate_number: input.certificateNumber, p_issued_at: input.issuedAt, p_expiry_date: input.expiryDate,
    p_actor_auth_user_id: input.actorAuthUserId, p_actor_label: input.actorLabel,
  });
  return parseTrainingCertificateRow(unwrap(data, error) as Record<string, unknown>);
}

// --- Certificate expiry / reminder jobs ---

export async function runTrainingCertificateExpiryBatch(
  client: TrainingTalentMutationRpcClient, input: { tenantId: string; asOfDate: string; periodLabel: string; actorAuthUserId: string; actorLabel: string },
): Promise<{ expiredCount: number; jobId: string }> {
  const { data, error } = await client.rpc("run_training_certificate_expiry_batch", {
    p_tenant_id: input.tenantId, p_as_of_date: input.asOfDate, p_period_label: input.periodLabel, p_actor_auth_user_id: input.actorAuthUserId, p_actor_label: input.actorLabel,
  });
  const row = unwrap(data, error) as { expired_count: number; job_id: string } | { expired_count: number; job_id: string }[];
  const r = Array.isArray(row) ? row[0] : row;
  return { expiredCount: r?.expired_count ?? 0, jobId: r?.job_id ?? "" };
}

export async function runTrainingCertificateExpiryReminderBatch(
  client: TrainingTalentMutationRpcClient,
  input: { tenantId: string; asOfDate: string; lookaheadDays: number; periodLabel: string; actorAuthUserId: string; actorLabel: string },
): Promise<{ remindedCount: number; skippedCount: number; jobId: string }> {
  const { data, error } = await client.rpc("run_training_certificate_expiry_reminder_batch", {
    p_tenant_id: input.tenantId, p_as_of_date: input.asOfDate, p_lookahead_days: input.lookaheadDays, p_period_label: input.periodLabel,
    p_actor_auth_user_id: input.actorAuthUserId, p_actor_label: input.actorLabel,
  });
  const row = unwrap(data, error) as { reminded_count: number; skipped_count: number; job_id: string } | { reminded_count: number; skipped_count: number; job_id: string }[];
  const r = Array.isArray(row) ? row[0] : row;
  return { remindedCount: r?.reminded_count ?? 0, skippedCount: r?.skipped_count ?? 0, jobId: r?.job_id ?? "" };
}

// --- Development plan ---

export async function createTrainingDevelopmentPlan(
  client: TrainingTalentMutationRpcClient,
  input: { tenantId: string; employeeId: string; title: string; cycleLabel: string | null; linkedPerformanceOutcomeId: string | null; actorAuthUserId: string; actorLabel: string },
): Promise<TrainingDevelopmentPlanRow> {
  const { data, error } = await client.rpc("create_training_development_plan", {
    p_tenant_id: input.tenantId, p_employee_id: input.employeeId, p_title: input.title, p_cycle_label: input.cycleLabel,
    p_linked_performance_outcome_id: input.linkedPerformanceOutcomeId, p_actor_auth_user_id: input.actorAuthUserId, p_actor_label: input.actorLabel,
  });
  return parseTrainingDevelopmentPlanRow(unwrap(data, error) as Record<string, unknown>);
}

export async function transitionTrainingDevelopmentPlanStatus(
  client: TrainingTalentMutationRpcClient,
  input: { planId: string; expectedVersion: number; targetStatus: string; reason: string | null; actorAuthUserId: string; actorLabel: string },
): Promise<TrainingDevelopmentPlanRow> {
  const { data, error } = await client.rpc("transition_training_development_plan_status", {
    p_plan_id: input.planId, p_expected_version: input.expectedVersion, p_target_status: input.targetStatus, p_reason: input.reason,
    p_actor_auth_user_id: input.actorAuthUserId, p_actor_label: input.actorLabel,
  });
  return parseTrainingDevelopmentPlanRow(unwrap(data, error) as Record<string, unknown>);
}

export async function addTrainingDevelopmentPlanAction(
  client: TrainingTalentMutationRpcClient,
  input: { planId: string; actionType: string; description: string; linkedCourseId: string | null; targetDate: string | null; actorAuthUserId: string; actorLabel: string },
): Promise<TrainingDevelopmentPlanActionRow> {
  const { data, error } = await client.rpc("add_training_development_plan_action", {
    p_plan_id: input.planId, p_action_type: input.actionType, p_description: input.description, p_linked_course_id: input.linkedCourseId,
    p_target_date: input.targetDate, p_actor_auth_user_id: input.actorAuthUserId, p_actor_label: input.actorLabel,
  });
  return parseTrainingDevelopmentPlanActionRow(unwrap(data, error) as Record<string, unknown>);
}

export async function updateTrainingDevelopmentPlanActionStatus(
  client: TrainingTalentMutationRpcClient,
  input: { actionId: string; expectedVersion: number; status: string; completedNote: string | null; actorAuthUserId: string; actorLabel: string },
): Promise<TrainingDevelopmentPlanActionRow> {
  const { data, error } = await client.rpc("update_training_development_plan_action_status", {
    p_action_id: input.actionId, p_expected_version: input.expectedVersion, p_status: input.status, p_completed_note: input.completedNote,
    p_actor_auth_user_id: input.actorAuthUserId, p_actor_label: input.actorLabel,
  });
  return parseTrainingDevelopmentPlanActionRow(unwrap(data, error) as Record<string, unknown>);
}

// --- Talent review ---

export async function createTalentReviewCycle(
  client: TrainingTalentMutationRpcClient, input: { tenantId: string; name: string; periodLabel: string; actorAuthUserId: string; actorLabel: string },
): Promise<TalentReviewCycleRow> {
  const { data, error } = await client.rpc("create_talent_review_cycle", {
    p_tenant_id: input.tenantId, p_name: input.name, p_period_label: input.periodLabel, p_actor_auth_user_id: input.actorAuthUserId, p_actor_label: input.actorLabel,
  });
  return parseTalentReviewCycleRow(unwrap(data, error) as Record<string, unknown>);
}

export async function transitionTalentReviewCycleStatus(
  client: TrainingTalentMutationRpcClient, input: { cycleId: string; expectedVersion: number; targetStatus: string; actorAuthUserId: string; actorLabel: string },
): Promise<TalentReviewCycleRow> {
  const { data, error } = await client.rpc("transition_talent_review_cycle_status", {
    p_cycle_id: input.cycleId, p_expected_version: input.expectedVersion, p_target_status: input.targetStatus, p_actor_auth_user_id: input.actorAuthUserId, p_actor_label: input.actorLabel,
  });
  return parseTalentReviewCycleRow(unwrap(data, error) as Record<string, unknown>);
}

export async function assignTalentReviewer(
  client: TrainingTalentMutationRpcClient, input: { cycleId: string; subjectEmployeeId: string; reviewerEmployeeId: string; actorAuthUserId: string; actorLabel: string },
): Promise<TalentReviewAssignmentRow> {
  const { data, error } = await client.rpc("assign_talent_reviewer", {
    p_cycle_id: input.cycleId, p_subject_employee_id: input.subjectEmployeeId, p_reviewer_employee_id: input.reviewerEmployeeId,
    p_actor_auth_user_id: input.actorAuthUserId, p_actor_label: input.actorLabel,
  });
  return parseTalentReviewAssignmentRow(unwrap(data, error) as Record<string, unknown>);
}

export async function reassignTalentReviewer(
  client: TrainingTalentMutationRpcClient, input: { assignmentId: string; newReviewerEmployeeId: string; reason: string; actorAuthUserId: string; actorLabel: string },
): Promise<TalentReviewAssignmentRow> {
  const { data, error } = await client.rpc("reassign_talent_reviewer", {
    p_assignment_id: input.assignmentId, p_new_reviewer_employee_id: input.newReviewerEmployeeId, p_reason: input.reason,
    p_actor_auth_user_id: input.actorAuthUserId, p_actor_label: input.actorLabel,
  });
  return parseTalentReviewAssignmentRow(unwrap(data, error) as Record<string, unknown>);
}

export async function submitTalentReview(
  client: TrainingTalentMutationRpcClient,
  input: {
    reviewId: string; expectedVersion: number; potentialRating: "low" | "moderate" | "high"; readinessNote: string | null;
    riskOfLoss: "low" | "medium" | "high" | null; actorAuthUserId: string; actorLabel: string;
  },
): Promise<TalentReviewRow> {
  const { data, error } = await client.rpc("submit_talent_review", {
    p_review_id: input.reviewId, p_expected_version: input.expectedVersion, p_potential_rating: input.potentialRating, p_readiness_note: input.readinessNote,
    p_risk_of_loss: input.riskOfLoss, p_actor_auth_user_id: input.actorAuthUserId, p_actor_label: input.actorLabel,
  });
  return parseTalentReviewRow(unwrap(data, error) as Record<string, unknown>);
}

// --- Talent pool ---

export async function createTalentPool(
  client: TrainingTalentMutationRpcClient,
  input: { tenantId: string; name: string; description: string | null; poolType: string; actorAuthUserId: string; actorLabel: string },
): Promise<TalentPoolRow> {
  const { data, error } = await client.rpc("create_talent_pool", {
    p_tenant_id: input.tenantId, p_name: input.name, p_description: input.description, p_pool_type: input.poolType,
    p_actor_auth_user_id: input.actorAuthUserId, p_actor_label: input.actorLabel,
  });
  return parseTalentPoolRow(unwrap(data, error) as Record<string, unknown>);
}

export async function archiveTalentPool(
  client: TrainingTalentMutationRpcClient, input: { poolId: string; expectedVersion: number; actorAuthUserId: string; actorLabel: string },
): Promise<TalentPoolRow> {
  const { data, error } = await client.rpc("archive_talent_pool", {
    p_pool_id: input.poolId, p_expected_version: input.expectedVersion, p_actor_auth_user_id: input.actorAuthUserId, p_actor_label: input.actorLabel,
  });
  return parseTalentPoolRow(unwrap(data, error) as Record<string, unknown>);
}

export async function addTalentPoolMember(
  client: TrainingTalentMutationRpcClient, input: { poolId: string; employeeId: string; addedReason: string; actorAuthUserId: string; actorLabel: string },
): Promise<TalentPoolMemberRow> {
  const { data, error } = await client.rpc("add_talent_pool_member", {
    p_pool_id: input.poolId, p_employee_id: input.employeeId, p_added_reason: input.addedReason, p_actor_auth_user_id: input.actorAuthUserId, p_actor_label: input.actorLabel,
  });
  return parseTalentPoolMemberRow(unwrap(data, error) as Record<string, unknown>);
}

export async function removeTalentPoolMember(
  client: TrainingTalentMutationRpcClient, input: { memberId: string; expectedVersion: number; removedReason: string; actorAuthUserId: string; actorLabel: string },
): Promise<TalentPoolMemberRow> {
  const { data, error } = await client.rpc("remove_talent_pool_member", {
    p_member_id: input.memberId, p_expected_version: input.expectedVersion, p_removed_reason: input.removedReason, p_actor_auth_user_id: input.actorAuthUserId, p_actor_label: input.actorLabel,
  });
  return parseTalentPoolMemberRow(unwrap(data, error) as Record<string, unknown>);
}

// --- Succession candidate ---

export async function proposeSuccessionCandidate(
  client: TrainingTalentMutationRpcClient,
  input: { tenantId: string; positionId: string; candidateEmployeeId: string; readiness: string; decisionReason: string; actorAuthUserId: string; actorLabel: string },
): Promise<TalentSuccessionCandidateRow> {
  const { data, error } = await client.rpc("propose_succession_candidate", {
    p_tenant_id: input.tenantId, p_position_id: input.positionId, p_candidate_employee_id: input.candidateEmployeeId, p_readiness: input.readiness,
    p_decision_reason: input.decisionReason, p_actor_auth_user_id: input.actorAuthUserId, p_actor_label: input.actorLabel,
  });
  return parseTalentSuccessionCandidateRow(unwrap(data, error) as Record<string, unknown>);
}

export async function decideSuccessionCandidate(
  client: TrainingTalentMutationRpcClient,
  input: { candidateId: string; expectedVersion: number; decision: "confirm" | "withdraw"; decisionReason: string; actorAuthUserId: string; actorLabel: string },
): Promise<TalentSuccessionCandidateRow> {
  const { data, error } = await client.rpc("decide_succession_candidate", {
    p_candidate_id: input.candidateId, p_expected_version: input.expectedVersion, p_decision: input.decision, p_decision_reason: input.decisionReason,
    p_actor_auth_user_id: input.actorAuthUserId, p_actor_label: input.actorLabel,
  });
  return parseTalentSuccessionCandidateRow(unwrap(data, error) as Record<string, unknown>);
}
