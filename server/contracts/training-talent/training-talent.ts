/**
 * Training and Talent contract (HRT-284, CG-S12-HRT-012). Mirrors
 * supabase/migrations/20260731040000_create_hris_training_talent.sql's
 * table shapes and RPCs. Follows the exact directory convention every
 * prior HRT checkpoint established: Zod schemas here, list/read
 * projections in server/queries/training-talent.ts, RPC-calling mutation
 * wrappers with an enumerated error-code type in
 * server/mutations/training-talent.ts.
 *
 * Several entities are read from more than one RPC shape -- a mutation
 * (create/decide/etc.) returns the RAW table row, while a list RPC returns
 * a JOINED projection with denormalized display columns (employee full
 * name, course code, etc.). Rather than doubling every schema, the joined
 * display columns are modeled as OPTIONAL on the same row schema: a raw
 * mutation-return row parses with them simply absent (undefined), and a
 * list-projection row carries them. Every score/weight/count-adjacent
 * numeric that Postgres returns as `numeric` is a decimal STRING once
 * parsed (this repository's established "exact decimals, never binary
 * float" discipline) -- hours_attended/score/max_score here.
 */

import { z } from "zod";

export const TRAINING_CATALOGUE_STATUSES = ["draft", "published", "archived"] as const;
export const TrainingCatalogueStatusSchema = z.enum(TRAINING_CATALOGUE_STATUSES);
export type TrainingCatalogueStatus = z.infer<typeof TrainingCatalogueStatusSchema>;

export const TRAINING_COURSE_STATUSES = ["active", "retired"] as const;
export const TrainingCourseStatusSchema = z.enum(TRAINING_COURSE_STATUSES);
export type TrainingCourseStatus = z.infer<typeof TrainingCourseStatusSchema>;

export const TRAINING_DELIVERY_MODES = ["in_person", "virtual", "e_learning", "blended"] as const;
export const TrainingDeliveryModeSchema = z.enum(TRAINING_DELIVERY_MODES);
export type TrainingDeliveryMode = z.infer<typeof TrainingDeliveryModeSchema>;

export const TRAINING_PROVIDER_TYPES = ["internal", "external"] as const;
export const TrainingProviderTypeSchema = z.enum(TRAINING_PROVIDER_TYPES);
export type TrainingProviderType = z.infer<typeof TrainingProviderTypeSchema>;

export const TRAINING_PROVIDER_STATUSES = ["active", "inactive"] as const;
export const TrainingProviderStatusSchema = z.enum(TRAINING_PROVIDER_STATUSES);
export type TrainingProviderStatus = z.infer<typeof TrainingProviderStatusSchema>;

export const TRAINING_SESSION_STATUSES = ["scheduled", "in_progress", "completed", "cancelled"] as const;
export const TrainingSessionStatusSchema = z.enum(TRAINING_SESSION_STATUSES);
export type TrainingSessionStatus = z.infer<typeof TrainingSessionStatusSchema>;

export const TRAINING_ENROLLMENT_STATUSES = ["pending_approval", "enrolled", "waitlisted", "cancelled", "completed", "failed", "no_show"] as const;
export const TrainingEnrollmentStatusSchema = z.enum(TRAINING_ENROLLMENT_STATUSES);
export type TrainingEnrollmentStatus = z.infer<typeof TrainingEnrollmentStatusSchema>;

export const TRAINING_ENROLLMENT_SOURCES = ["self", "manager_assigned", "hr_assigned", "mandatory_assigned"] as const;
export const TrainingEnrollmentSourceSchema = z.enum(TRAINING_ENROLLMENT_SOURCES);
export type TrainingEnrollmentSource = z.infer<typeof TrainingEnrollmentSourceSchema>;

export const TRAINING_CERTIFICATE_STATUSES = ["issued", "expired", "revoked"] as const;
export const TrainingCertificateStatusSchema = z.enum(TRAINING_CERTIFICATE_STATUSES);
export type TrainingCertificateStatus = z.infer<typeof TrainingCertificateStatusSchema>;

export const TRAINING_CERTIFICATE_SOURCES = ["internal_completion", "external_import"] as const;
export const TrainingCertificateSourceSchema = z.enum(TRAINING_CERTIFICATE_SOURCES);
export type TrainingCertificateSource = z.infer<typeof TrainingCertificateSourceSchema>;

export const TRAINING_CERTIFICATE_VERIFICATION_STATUSES = ["verified", "unverified"] as const;
export const TrainingCertificateVerificationStatusSchema = z.enum(TRAINING_CERTIFICATE_VERIFICATION_STATUSES);
export type TrainingCertificateVerificationStatus = z.infer<typeof TrainingCertificateVerificationStatusSchema>;

export const TRAINING_DEVELOPMENT_PLAN_STATUSES = ["draft", "active", "completed", "cancelled"] as const;
export const TrainingDevelopmentPlanStatusSchema = z.enum(TRAINING_DEVELOPMENT_PLAN_STATUSES);
export type TrainingDevelopmentPlanStatus = z.infer<typeof TrainingDevelopmentPlanStatusSchema>;

export const TRAINING_DEVELOPMENT_PLAN_ACTION_TYPES = ["training", "coaching", "stretch_assignment", "certification", "other"] as const;
export const TrainingDevelopmentPlanActionTypeSchema = z.enum(TRAINING_DEVELOPMENT_PLAN_ACTION_TYPES);
export type TrainingDevelopmentPlanActionType = z.infer<typeof TrainingDevelopmentPlanActionTypeSchema>;

export const TRAINING_DEVELOPMENT_PLAN_ACTION_STATUSES = ["planned", "in_progress", "completed", "cancelled"] as const;
export const TrainingDevelopmentPlanActionStatusSchema = z.enum(TRAINING_DEVELOPMENT_PLAN_ACTION_STATUSES);
export type TrainingDevelopmentPlanActionStatus = z.infer<typeof TrainingDevelopmentPlanActionStatusSchema>;

export const TALENT_REVIEW_CYCLE_STATUSES = ["draft", "active", "closed"] as const;
export const TalentReviewCycleStatusSchema = z.enum(TALENT_REVIEW_CYCLE_STATUSES);
export type TalentReviewCycleStatus = z.infer<typeof TalentReviewCycleStatusSchema>;

export const TALENT_REVIEW_ASSIGNMENT_STATUSES = ["active", "reassigned"] as const;
export const TalentReviewAssignmentStatusSchema = z.enum(TALENT_REVIEW_ASSIGNMENT_STATUSES);
export type TalentReviewAssignmentStatus = z.infer<typeof TalentReviewAssignmentStatusSchema>;

export const TALENT_REVIEW_STATUSES = ["draft", "submitted"] as const;
export const TalentReviewStatusSchema = z.enum(TALENT_REVIEW_STATUSES);
export type TalentReviewStatus = z.infer<typeof TalentReviewStatusSchema>;

export const TALENT_POTENTIAL_RATINGS = ["low", "moderate", "high"] as const;
export const TalentPotentialRatingSchema = z.enum(TALENT_POTENTIAL_RATINGS);
export type TalentPotentialRating = z.infer<typeof TalentPotentialRatingSchema>;

export const TALENT_RISK_OF_LOSS = ["low", "medium", "high"] as const;
export const TalentRiskOfLossSchema = z.enum(TALENT_RISK_OF_LOSS);
export type TalentRiskOfLoss = z.infer<typeof TalentRiskOfLossSchema>;

export const TALENT_POOL_TYPES = ["successor", "high_potential", "critical_role"] as const;
export const TalentPoolTypeSchema = z.enum(TALENT_POOL_TYPES);
export type TalentPoolType = z.infer<typeof TalentPoolTypeSchema>;

export const TALENT_POOL_STATUSES = ["active", "archived"] as const;
export const TalentPoolStatusSchema = z.enum(TALENT_POOL_STATUSES);
export type TalentPoolStatus = z.infer<typeof TalentPoolStatusSchema>;

export const TALENT_POOL_MEMBER_STATUSES = ["active", "removed"] as const;
export const TalentPoolMemberStatusSchema = z.enum(TALENT_POOL_MEMBER_STATUSES);
export type TalentPoolMemberStatus = z.infer<typeof TalentPoolMemberStatusSchema>;

export const TALENT_SUCCESSION_READINESS = ["ready_now", "ready_1_2_years", "ready_3_plus_years", "development_needed"] as const;
export const TalentSuccessionReadinessSchema = z.enum(TALENT_SUCCESSION_READINESS);
export type TalentSuccessionReadiness = z.infer<typeof TalentSuccessionReadinessSchema>;

export const TALENT_SUCCESSION_CANDIDATE_STATUSES = ["proposed", "confirmed", "withdrawn"] as const;
export const TalentSuccessionCandidateStatusSchema = z.enum(TALENT_SUCCESSION_CANDIDATE_STATUSES);
export type TalentSuccessionCandidateStatus = z.infer<typeof TalentSuccessionCandidateStatusSchema>;

const decimal = z.union([z.string(), z.number()]).transform((v) => String(v));
const nullableDecimal = z.union([z.string(), z.number()]).nullable().transform((v) => (v === null ? null : String(v)));

// --- Competency ---

export const TrainingCompetencyRowSchema = z.object({
  id: z.string().uuid(),
  code: z.string(),
  name: z.string(),
  description: z.string().nullable(),
  category: z.string().nullable(),
  status: TrainingCatalogueStatusSchema,
  recordVersion: z.number().int().positive(),
});
export type TrainingCompetencyRow = z.infer<typeof TrainingCompetencyRowSchema>;

export function parseTrainingCompetencyRow(row: Record<string, unknown>): TrainingCompetencyRow {
  return TrainingCompetencyRowSchema.parse({
    id: row.id, code: row.code, name: row.name, description: row.description ?? null, category: row.category ?? null,
    status: row.status, recordVersion: row.record_version,
  });
}

// --- Course / version / competency link ---

export const TrainingCourseRowSchema = z.object({
  id: z.string().uuid(),
  code: z.string(),
  name: z.string(),
  category: z.string().nullable(),
  status: TrainingCourseStatusSchema,
});
export type TrainingCourseRow = z.infer<typeof TrainingCourseRowSchema>;

export function parseTrainingCourseRow(row: Record<string, unknown>): TrainingCourseRow {
  return TrainingCourseRowSchema.parse({ id: row.id, code: row.code, name: row.name, category: row.category ?? null, status: row.status });
}

export const TrainingCourseVersionRowSchema = z.object({
  id: z.string().uuid(),
  courseId: z.string().uuid(),
  versionNumber: z.number().int().positive(),
  status: TrainingCatalogueStatusSchema,
  description: z.string().nullable(),
  deliveryMode: TrainingDeliveryModeSchema,
  durationHours: nullableDecimal,
  isMandatory: z.boolean(),
  requiresEnrollmentApproval: z.boolean(),
  requiresAssessment: z.boolean(),
  passingScore: nullableDecimal,
  issuesCertificate: z.boolean(),
  certificateValidityMonths: z.number().int().nullable(),
  recordVersion: z.number().int().positive(),
});
export type TrainingCourseVersionRow = z.infer<typeof TrainingCourseVersionRowSchema>;

export function parseTrainingCourseVersionRow(row: Record<string, unknown>): TrainingCourseVersionRow {
  return TrainingCourseVersionRowSchema.parse({
    id: row.id, courseId: row.course_id, versionNumber: row.version_number, status: row.status, description: row.description ?? null,
    deliveryMode: row.delivery_mode, durationHours: row.duration_hours ?? null, isMandatory: row.is_mandatory,
    requiresEnrollmentApproval: row.requires_enrollment_approval, requiresAssessment: row.requires_assessment,
    passingScore: row.passing_score ?? null, issuesCertificate: row.issues_certificate,
    certificateValidityMonths: (row.certificate_validity_months as number | null) ?? null, recordVersion: row.record_version,
  });
}

export const TrainingCourseCompetencyRowSchema = z.object({
  courseId: z.string().uuid(),
  competencyId: z.string().uuid(),
  competencyCode: z.string().optional(),
  competencyName: z.string().optional(),
});
export type TrainingCourseCompetencyRow = z.infer<typeof TrainingCourseCompetencyRowSchema>;

export function parseTrainingCourseCompetencyRow(row: Record<string, unknown>): TrainingCourseCompetencyRow {
  return TrainingCourseCompetencyRowSchema.parse({
    courseId: row.course_id, competencyId: row.competency_id,
    competencyCode: (row.competency_code as string | undefined) ?? undefined, competencyName: (row.competency_name as string | undefined) ?? undefined,
  });
}

// --- Provider ---

export const TrainingProviderRowSchema = z.object({
  id: z.string().uuid(),
  name: z.string(),
  providerType: TrainingProviderTypeSchema,
  contactName: z.string().nullable(),
  contactEmail: z.string().nullable(),
  contactPhone: z.string().nullable(),
  status: TrainingProviderStatusSchema,
  /**
   * `ISS-2026-083`: the provider's own accreditation document — the thing an auditor asks for
   * when they want to know whether a certificate this provider issued means anything. Nullable
   * and defaulted, so a row from a projection that omits it degrades to "none attached" rather
   * than throwing (`ISS-2026-315` is what a required-but-unreturned field costs).
   */
  evidenceFileId: z.string().uuid().nullable(),
  recordVersion: z.number().int().positive(),
});
export type TrainingProviderRow = z.infer<typeof TrainingProviderRowSchema>;

export function parseTrainingProviderRow(row: Record<string, unknown>): TrainingProviderRow {
  return TrainingProviderRowSchema.parse({
    id: row.id, name: row.name, providerType: row.provider_type, contactName: row.contact_name ?? null,
    contactEmail: row.contact_email ?? null, contactPhone: row.contact_phone ?? null, status: row.status,
    evidenceFileId: row.evidence_file_id ?? null, recordVersion: row.record_version,
  });
}

// --- Prerequisite ---

export const TrainingCoursePrerequisiteRowSchema = z.object({
  id: z.string().uuid(),
  courseId: z.string().uuid(),
  prerequisiteCourseId: z.string().uuid(),
});
export type TrainingCoursePrerequisiteRow = z.infer<typeof TrainingCoursePrerequisiteRowSchema>;

export function parseTrainingCoursePrerequisiteRow(row: Record<string, unknown>): TrainingCoursePrerequisiteRow {
  return TrainingCoursePrerequisiteRowSchema.parse({ id: row.id, courseId: row.course_id, prerequisiteCourseId: row.prerequisite_course_id });
}

// --- Session ---

export const TrainingSessionRowSchema = z.object({
  id: z.string().uuid(),
  courseVersionId: z.string().uuid(),
  courseId: z.string().uuid().optional(),
  courseCode: z.string().optional(),
  courseName: z.string().optional(),
  providerId: z.string().uuid().nullable(),
  providerName: z.string().nullable().optional(),
  sessionCode: z.string(),
  location: z.string().nullable(),
  startAt: z.string(),
  endAt: z.string(),
  capacity: z.number().int().positive(),
  enrolledCount: z.number().int().nonnegative().optional(),
  waitlistedCount: z.number().int().nonnegative().optional(),
  status: TrainingSessionStatusSchema,
  cancelReason: z.string().nullable().optional(),
  recordVersion: z.number().int().positive(),
});
export type TrainingSessionRow = z.infer<typeof TrainingSessionRowSchema>;

export function parseTrainingSessionRow(row: Record<string, unknown>): TrainingSessionRow {
  return TrainingSessionRowSchema.parse({
    id: row.id, courseVersionId: row.course_version_id, courseId: (row.course_id as string | undefined) ?? undefined,
    courseCode: (row.course_code as string | undefined) ?? undefined, courseName: (row.course_name as string | undefined) ?? undefined,
    providerId: row.provider_id ?? null, providerName: (row.provider_name as string | null | undefined) ?? undefined,
    sessionCode: row.session_code, location: row.location ?? null, startAt: row.start_at, endAt: row.end_at, capacity: row.capacity,
    enrolledCount: (row.enrolled_count as number | undefined) ?? undefined, waitlistedCount: (row.waitlisted_count as number | undefined) ?? undefined,
    status: row.status, cancelReason: (row.cancel_reason as string | null | undefined) ?? undefined, recordVersion: row.record_version,
  });
}

// --- Enrollment ---

export const TrainingEnrollmentRowSchema = z.object({
  id: z.string().uuid(),
  sessionId: z.string().uuid(),
  sessionCode: z.string().optional(),
  employeeId: z.string().uuid().optional(),
  employeeFullName: z.string().nullable().optional(),
  courseVersionId: z.string().uuid(),
  courseCode: z.string().optional(),
  courseName: z.string().optional(),
  startAt: z.string().optional(),
  status: TrainingEnrollmentStatusSchema,
  enrollmentSource: TrainingEnrollmentSourceSchema,
  attended: z.boolean().nullable().optional(),
  hoursAttended: nullableDecimal.optional(),
  completionNotes: z.string().nullable().optional(),
  recordVersion: z.number().int().positive(),
});
export type TrainingEnrollmentRow = z.infer<typeof TrainingEnrollmentRowSchema>;

export function parseTrainingEnrollmentRow(row: Record<string, unknown>): TrainingEnrollmentRow {
  return TrainingEnrollmentRowSchema.parse({
    id: row.id, sessionId: row.session_id, sessionCode: (row.session_code as string | undefined) ?? undefined,
    employeeId: (row.employee_id as string | undefined) ?? undefined, employeeFullName: (row.employee_full_name as string | null | undefined) ?? undefined,
    courseVersionId: row.course_version_id, courseCode: (row.course_code as string | undefined) ?? undefined,
    courseName: (row.course_name as string | undefined) ?? undefined, startAt: (row.start_at as string | undefined) ?? undefined,
    status: row.status, enrollmentSource: row.enrollment_source, attended: (row.attended as boolean | null | undefined) ?? undefined,
    hoursAttended: (row.hours_attended as string | number | null | undefined) ?? undefined,
    completionNotes: (row.completion_notes as string | null | undefined) ?? undefined, recordVersion: row.record_version,
  });
}

// --- Assessment ---

export const TrainingAssessmentRowSchema = z.object({
  id: z.string().uuid(),
  enrollmentId: z.string().uuid(),
  employeeId: z.string().uuid(),
  courseVersionId: z.string().uuid(),
  attemptNumber: z.number().int().positive(),
  score: decimal,
  maxScore: decimal,
  passed: z.boolean(),
  assessedBy: z.string().nullable(),
  assessedAt: z.string(),
  notes: z.string().nullable(),
  recordVersion: z.number().int().positive(),
});
export type TrainingAssessmentRow = z.infer<typeof TrainingAssessmentRowSchema>;

export function parseTrainingAssessmentRow(row: Record<string, unknown>): TrainingAssessmentRow {
  return TrainingAssessmentRowSchema.parse({
    id: row.id, enrollmentId: row.enrollment_id, employeeId: row.employee_id, courseVersionId: row.course_version_id,
    attemptNumber: row.attempt_number, score: row.score, maxScore: row.max_score, passed: row.passed, assessedBy: row.assessed_by ?? null,
    assessedAt: row.assessed_at, notes: row.notes ?? null, recordVersion: row.record_version,
  });
}

// --- Certificate ---

export const TrainingCertificateRowSchema = z.object({
  id: z.string().uuid(),
  employeeId: z.string().uuid().optional(),
  employeeFullName: z.string().nullable().optional(),
  courseVersionId: z.string().uuid().nullable(),
  courseCode: z.string().nullable().optional(),
  courseName: z.string().nullable().optional(),
  externalCourseName: z.string().nullable(),
  certificateNumber: z.string().nullable(),
  issuedAt: z.string(),
  expiryDate: z.string().nullable(),
  status: TrainingCertificateStatusSchema,
  source: TrainingCertificateSourceSchema,
  verificationStatus: TrainingCertificateVerificationStatusSchema,
  evidenceFileId: z.string().uuid().nullable(),
  renewedFromCertificateId: z.string().uuid().nullable().optional(),
  recordVersion: z.number().int().positive(),
});
export type TrainingCertificateRow = z.infer<typeof TrainingCertificateRowSchema>;

export function parseTrainingCertificateRow(row: Record<string, unknown>): TrainingCertificateRow {
  return TrainingCertificateRowSchema.parse({
    id: row.id, employeeId: (row.employee_id as string | undefined) ?? undefined,
    employeeFullName: (row.employee_full_name as string | null | undefined) ?? undefined, courseVersionId: row.course_version_id ?? null,
    courseCode: (row.course_code as string | null | undefined) ?? undefined, courseName: (row.course_name as string | null | undefined) ?? undefined,
    externalCourseName: row.external_course_name ?? null, certificateNumber: row.certificate_number ?? null, issuedAt: row.issued_at,
    expiryDate: row.expiry_date ?? null, status: row.status, source: row.source, verificationStatus: row.verification_status,
    evidenceFileId: row.evidence_file_id ?? null, renewedFromCertificateId: (row.renewed_from_certificate_id as string | null | undefined) ?? undefined,
    recordVersion: row.record_version,
  });
}

export const TrainingCertificateExpiryReminderRowSchema = z.object({
  id: z.string().uuid(),
  certificateId: z.string().uuid(),
  employeeId: z.string().uuid(),
  periodLabel: z.string(),
  daysUntilExpiry: z.number().int(),
  remindedAt: z.string(),
});
export type TrainingCertificateExpiryReminderRow = z.infer<typeof TrainingCertificateExpiryReminderRowSchema>;

export function parseTrainingCertificateExpiryReminderRow(row: Record<string, unknown>): TrainingCertificateExpiryReminderRow {
  return TrainingCertificateExpiryReminderRowSchema.parse({
    id: row.id, certificateId: row.certificate_id, employeeId: row.employee_id, periodLabel: row.period_label,
    daysUntilExpiry: row.days_until_expiry, remindedAt: row.reminded_at,
  });
}

// --- Development plan ---

export const TrainingDevelopmentPlanRowSchema = z.object({
  id: z.string().uuid(),
  employeeId: z.string().uuid(),
  employeeFullName: z.string().nullable().optional(),
  title: z.string(),
  cycleLabel: z.string().nullable(),
  status: TrainingDevelopmentPlanStatusSchema,
  linkedPerformanceOutcomeId: z.string().uuid().nullable(),
  recordVersion: z.number().int().positive(),
});
export type TrainingDevelopmentPlanRow = z.infer<typeof TrainingDevelopmentPlanRowSchema>;

export function parseTrainingDevelopmentPlanRow(row: Record<string, unknown>): TrainingDevelopmentPlanRow {
  return TrainingDevelopmentPlanRowSchema.parse({
    id: row.id, employeeId: row.employee_id, employeeFullName: (row.employee_full_name as string | null | undefined) ?? undefined,
    title: row.title, cycleLabel: row.cycle_label ?? null, status: row.status,
    linkedPerformanceOutcomeId: row.linked_performance_outcome_id ?? null, recordVersion: row.record_version,
  });
}

export const TrainingDevelopmentPlanActionRowSchema = z.object({
  id: z.string().uuid(),
  planId: z.string().uuid(),
  actionType: TrainingDevelopmentPlanActionTypeSchema,
  description: z.string(),
  linkedCourseId: z.string().uuid().nullable(),
  targetDate: z.string().nullable(),
  status: TrainingDevelopmentPlanActionStatusSchema,
  completedNote: z.string().nullable(),
  completedAt: z.string().nullable(),
  recordVersion: z.number().int().positive(),
});
export type TrainingDevelopmentPlanActionRow = z.infer<typeof TrainingDevelopmentPlanActionRowSchema>;

export function parseTrainingDevelopmentPlanActionRow(row: Record<string, unknown>): TrainingDevelopmentPlanActionRow {
  return TrainingDevelopmentPlanActionRowSchema.parse({
    id: row.id, planId: row.plan_id, actionType: row.action_type, description: row.description, linkedCourseId: row.linked_course_id ?? null,
    targetDate: row.target_date ?? null, status: row.status, completedNote: row.completed_note ?? null, completedAt: row.completed_at ?? null,
    recordVersion: row.record_version,
  });
}

// --- Talent review cycle / assignment / review ---

export const TalentReviewCycleRowSchema = z.object({
  id: z.string().uuid(),
  name: z.string(),
  periodLabel: z.string(),
  status: TalentReviewCycleStatusSchema,
  recordVersion: z.number().int().positive(),
});
export type TalentReviewCycleRow = z.infer<typeof TalentReviewCycleRowSchema>;

export function parseTalentReviewCycleRow(row: Record<string, unknown>): TalentReviewCycleRow {
  return TalentReviewCycleRowSchema.parse({ id: row.id, name: row.name, periodLabel: row.period_label, status: row.status, recordVersion: row.record_version });
}

export const TalentReviewAssignmentRowSchema = z.object({
  id: z.string().uuid(),
  cycleId: z.string().uuid(),
  cycleName: z.string().optional(),
  subjectEmployeeId: z.string().uuid(),
  subjectFullName: z.string().nullable().optional(),
  reviewerEmployeeId: z.string().uuid(),
  reviewerFullName: z.string().nullable().optional(),
  status: TalentReviewAssignmentStatusSchema,
  reviewId: z.string().uuid().nullable().optional(),
  reviewStatus: TalentReviewStatusSchema.nullable().optional(),
  recordVersion: z.number().int().positive(),
});
export type TalentReviewAssignmentRow = z.infer<typeof TalentReviewAssignmentRowSchema>;

export function parseTalentReviewAssignmentRow(row: Record<string, unknown>): TalentReviewAssignmentRow {
  return TalentReviewAssignmentRowSchema.parse({
    id: row.id, cycleId: row.cycle_id, cycleName: (row.cycle_name as string | undefined) ?? undefined,
    subjectEmployeeId: row.subject_employee_id, subjectFullName: (row.subject_full_name as string | null | undefined) ?? undefined,
    reviewerEmployeeId: row.reviewer_employee_id, reviewerFullName: (row.reviewer_full_name as string | null | undefined) ?? undefined,
    status: row.status, reviewId: (row.review_id as string | null | undefined) ?? undefined,
    reviewStatus: (row.review_status as TalentReviewStatus | null | undefined) ?? undefined, recordVersion: row.record_version,
  });
}

export const TalentReviewRowSchema = z.object({
  id: z.string().uuid(),
  cycleId: z.string().uuid(),
  subjectEmployeeId: z.string().uuid(),
  assignmentId: z.string().uuid(),
  potentialRating: TalentPotentialRatingSchema.nullable(),
  readinessNote: z.string().nullable(),
  riskOfLoss: TalentRiskOfLossSchema.nullable(),
  status: TalentReviewStatusSchema,
  submittedAt: z.string().nullable(),
  recordVersion: z.number().int().positive(),
});
export type TalentReviewRow = z.infer<typeof TalentReviewRowSchema>;

export function parseTalentReviewRow(row: Record<string, unknown>): TalentReviewRow {
  return TalentReviewRowSchema.parse({
    id: row.id, cycleId: row.cycle_id, subjectEmployeeId: row.subject_employee_id, assignmentId: row.assignment_id,
    potentialRating: row.potential_rating ?? null, readinessNote: row.readiness_note ?? null, riskOfLoss: row.risk_of_loss ?? null,
    status: row.status, submittedAt: row.submitted_at ?? null, recordVersion: row.record_version,
  });
}

// --- Talent pool ---

export const TalentPoolRowSchema = z.object({
  id: z.string().uuid(),
  name: z.string(),
  description: z.string().nullable(),
  poolType: TalentPoolTypeSchema,
  status: TalentPoolStatusSchema,
  recordVersion: z.number().int().positive(),
});
export type TalentPoolRow = z.infer<typeof TalentPoolRowSchema>;

export function parseTalentPoolRow(row: Record<string, unknown>): TalentPoolRow {
  return TalentPoolRowSchema.parse({
    id: row.id, name: row.name, description: row.description ?? null, poolType: row.pool_type, status: row.status, recordVersion: row.record_version,
  });
}

export const TalentPoolMemberRowSchema = z.object({
  id: z.string().uuid(),
  poolId: z.string().uuid(),
  employeeId: z.string().uuid(),
  employeeFullName: z.string().nullable().optional(),
  status: TalentPoolMemberStatusSchema,
  addedReason: z.string(),
  addedAt: z.string(),
  recordVersion: z.number().int().positive(),
});
export type TalentPoolMemberRow = z.infer<typeof TalentPoolMemberRowSchema>;

export function parseTalentPoolMemberRow(row: Record<string, unknown>): TalentPoolMemberRow {
  return TalentPoolMemberRowSchema.parse({
    id: row.id, poolId: row.pool_id, employeeId: row.employee_id, employeeFullName: (row.employee_full_name as string | null | undefined) ?? undefined,
    status: row.status, addedReason: row.added_reason, addedAt: row.added_at, recordVersion: row.record_version,
  });
}

// --- Succession candidate ---

export const TalentSuccessionCandidateRowSchema = z.object({
  id: z.string().uuid(),
  positionId: z.string().uuid(),
  positionTitle: z.string().optional(),
  candidateEmployeeId: z.string().uuid(),
  candidateFullName: z.string().nullable().optional(),
  readiness: TalentSuccessionReadinessSchema,
  decisionReason: z.string(),
  status: TalentSuccessionCandidateStatusSchema,
  recordVersion: z.number().int().positive(),
});
export type TalentSuccessionCandidateRow = z.infer<typeof TalentSuccessionCandidateRowSchema>;

export function parseTalentSuccessionCandidateRow(row: Record<string, unknown>): TalentSuccessionCandidateRow {
  return TalentSuccessionCandidateRowSchema.parse({
    id: row.id, positionId: row.position_id, positionTitle: (row.position_title as string | undefined) ?? undefined,
    candidateEmployeeId: row.candidate_employee_id, candidateFullName: (row.candidate_full_name as string | null | undefined) ?? undefined,
    readiness: row.readiness, decisionReason: row.decision_reason, status: row.status, recordVersion: row.record_version,
  });
}

// --- Reporting (k-anonymity) ---

export const TalentPoolDistributionRowSchema = z.object({
  departmentOrgUnitId: z.string().uuid().nullable(),
  departmentName: z.string().nullable(),
  memberCount: z.number().int().nonnegative().nullable(),
  suppressed: z.boolean(),
});
export type TalentPoolDistributionRow = z.infer<typeof TalentPoolDistributionRowSchema>;

export function parseTalentPoolDistributionRow(row: Record<string, unknown>): TalentPoolDistributionRow {
  return TalentPoolDistributionRowSchema.parse({
    departmentOrgUnitId: row.department_org_unit_id ?? null, departmentName: row.department_name ?? null,
    memberCount: row.member_count ?? null, suppressed: row.suppressed,
  });
}
