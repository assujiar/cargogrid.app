/**
 * Recruitment, Job Portal and ATS contract (HRT-276, CG-S12-HRT-004). Mirrors
 * supabase/migrations/20260730860000_create_hris_recruitment_ats.sql's
 * app.job_vacancies/app.candidates/app.job_applications/app.candidate_assessments/
 * app.interviews/app.job_offers(+versions) shapes and their RPCs. Follows the exact
 * directory convention HRT-274/275 established: Zod schemas here, list/read
 * projections in server/queries/recruitment.ts, RPC-calling mutation wrappers with an
 * enumerated error-code type in server/mutations/recruitment.ts.
 *
 * Candidate identity is deliberately NOT app.employees/app.users (ADR-0023 Part B) --
 * see the migration's own design note 1. This contract never imports from
 * server/contracts/employee/ for that reason.
 */

import { z } from "zod";

export const VACANCY_STATUSES = ["draft", "open", "on_hold", "closed", "cancelled"] as const;
export const VacancyStatusSchema = z.enum(VACANCY_STATUSES);
export type VacancyStatus = z.infer<typeof VacancyStatusSchema>;

export const EMPLOYMENT_TYPES = ["full_time", "part_time", "contract", "internship", "temporary"] as const;
export const EmploymentTypeSchema = z.enum(EMPLOYMENT_TYPES);
export type EmploymentType = z.infer<typeof EmploymentTypeSchema>;

export const CANDIDATE_SOURCES = ["public_application", "staff_created", "referral", "agency", "talent_pool", "import"] as const;
export const CandidateSourceSchema = z.enum(CANDIDATE_SOURCES);
export type CandidateSource = z.infer<typeof CandidateSourceSchema>;

export const CANDIDATE_STATUSES = ["active", "blocked", "archived"] as const;
export const CandidateStatusSchema = z.enum(CANDIDATE_STATUSES);
export type CandidateStatus = z.infer<typeof CandidateStatusSchema>;

export const APPLICATION_STAGES = ["new", "screening", "assessment", "interview", "offer", "offer_accepted", "rejected", "withdrawn"] as const;
export const ApplicationStageSchema = z.enum(APPLICATION_STAGES);
export type ApplicationStage = z.infer<typeof ApplicationStageSchema>;

export const ASSESSMENT_TYPES = ["screening", "technical", "behavioral", "case_study", "other"] as const;
export const AssessmentTypeSchema = z.enum(ASSESSMENT_TYPES);
export type AssessmentType = z.infer<typeof AssessmentTypeSchema>;

export const ASSESSMENT_STATUSES = ["pending", "in_progress", "completed", "cancelled"] as const;
export const AssessmentStatusSchema = z.enum(ASSESSMENT_STATUSES);
export type AssessmentStatus = z.infer<typeof AssessmentStatusSchema>;

export const INTERVIEW_MODES = ["in_person", "phone", "video"] as const;
export const InterviewModeSchema = z.enum(INTERVIEW_MODES);
export type InterviewMode = z.infer<typeof InterviewModeSchema>;

export const INTERVIEW_STATUSES = ["scheduled", "completed", "cancelled", "no_show"] as const;
export const InterviewStatusSchema = z.enum(INTERVIEW_STATUSES);
export type InterviewStatus = z.infer<typeof InterviewStatusSchema>;

export const INTERVIEW_RECOMMENDATIONS = ["strong_yes", "yes", "no", "strong_no"] as const;
export const InterviewRecommendationSchema = z.enum(INTERVIEW_RECOMMENDATIONS);
export type InterviewRecommendation = z.infer<typeof InterviewRecommendationSchema>;

export const OFFER_STATUSES = ["draft", "pending_approval", "approved", "extended", "accepted", "declined", "withdrawn"] as const;
export const OfferStatusSchema = z.enum(OFFER_STATUSES);
export type OfferStatus = z.infer<typeof OfferStatusSchema>;

export const OFFER_APPROVAL_STATUSES = ["not_required", "pending", "approved", "rejected"] as const;
export const OfferApprovalStatusSchema = z.enum(OFFER_APPROVAL_STATUSES);
export type OfferApprovalStatus = z.infer<typeof OfferApprovalStatusSchema>;

export const OFFER_RESPONSES = ["accepted", "declined"] as const;
export const OfferResponseSchema = z.enum(OFFER_RESPONSES);
export type OfferResponse = z.infer<typeof OfferResponseSchema>;

// --- Vacancy ---

export const JobVacancySchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  positionId: z.string().uuid(),
  title: z.string(),
  employmentType: EmploymentTypeSchema,
  headcount: z.number().int().positive(),
  status: VacancyStatusSchema,
  statusReason: z.string().nullable(),
  description: z.string().nullable(),
  requirements: z.string().nullable(),
  hiringManagerEmployeeId: z.string().uuid().nullable(),
  ownerAuthUserId: z.string().uuid().nullable(),
  recordVersion: z.number().int().positive(),
  createdAt: z.string(),
  updatedAt: z.string(),
});
export type JobVacancy = z.infer<typeof JobVacancySchema>;

export function parseJobVacancy(row: Record<string, unknown>): JobVacancy {
  return JobVacancySchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    positionId: row.position_id,
    title: row.title,
    employmentType: row.employment_type,
    headcount: row.headcount,
    status: row.status,
    statusReason: row.status_reason ?? null,
    description: row.description ?? null,
    requirements: row.requirements ?? null,
    hiringManagerEmployeeId: row.hiring_manager_employee_id ?? null,
    ownerAuthUserId: row.owner_auth_user_id ?? null,
    recordVersion: row.record_version,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  });
}

export const JobVacancyPublishResultSchema = z.object({
  vacancy: JobVacancySchema,
  rawPostingToken: z.string(),
  postingExpiresAt: z.string(),
});
export type JobVacancyPublishResult = z.infer<typeof JobVacancyPublishResultSchema>;

export function parseJobVacancyPublishResult(row: Record<string, unknown>): JobVacancyPublishResult {
  return JobVacancyPublishResultSchema.parse({
    vacancy: parseJobVacancy(row.vacancy as Record<string, unknown>),
    rawPostingToken: row.raw_posting_token,
    postingExpiresAt: row.posting_expires_at,
  });
}

export const JobVacancyDetailSchema = z.object({
  vacancy: JobVacancySchema,
  activePostingExpiresAt: z.string().nullable(),
  currentOpenHeadcount: z.number().int().nonnegative(),
});
export type JobVacancyDetail = z.infer<typeof JobVacancyDetailSchema>;

export function parseJobVacancyDetail(row: Record<string, unknown>): JobVacancyDetail {
  return JobVacancyDetailSchema.parse({
    vacancy: parseJobVacancy(row.vacancy as Record<string, unknown>),
    activePostingExpiresAt: row.active_posting_expires_at ?? null,
    currentOpenHeadcount: row.current_open_headcount,
  });
}

export const PublicVacancySummarySchema = z.object({
  postingToken: z.string(),
  title: z.string(),
  employmentType: EmploymentTypeSchema,
  orgUnitName: z.string(),
  headcount: z.number().int().positive(),
  publishedAt: z.string(),
});
export type PublicVacancySummary = z.infer<typeof PublicVacancySummarySchema>;

export function parsePublicVacancySummary(row: Record<string, unknown>): PublicVacancySummary {
  return PublicVacancySummarySchema.parse({
    postingToken: row.posting_token,
    title: row.title,
    employmentType: row.employment_type,
    orgUnitName: row.org_unit_name,
    headcount: row.headcount,
    publishedAt: row.published_at,
  });
}

export const PublicVacancyDetailSchema = z.object({
  vacancyId: z.string().uuid(),
  title: z.string(),
  employmentType: EmploymentTypeSchema,
  description: z.string().nullable(),
  requirements: z.string().nullable(),
  orgUnitName: z.string(),
  headcount: z.number().int().positive(),
});
export type PublicVacancyDetail = z.infer<typeof PublicVacancyDetailSchema>;

export function parsePublicVacancyDetail(row: Record<string, unknown>): PublicVacancyDetail {
  return PublicVacancyDetailSchema.parse({
    vacancyId: row.vacancy_id,
    title: row.title,
    employmentType: row.employment_type,
    description: row.description ?? null,
    requirements: row.requirements ?? null,
    orgUnitName: row.org_unit_name,
    headcount: row.headcount,
  });
}

// --- Candidate ---

export const CandidateProfileSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  fullName: z.string(),
  email: z.string().nullable(),
  phone: z.string().nullable(),
  nationalIdNumber: z.string().nullable(),
  dateOfBirth: z.string().nullable(),
  address: z.string().nullable(),
  resumeFileId: z.string().uuid().nullable(),
  source: CandidateSourceSchema,
  status: CandidateStatusSchema,
  consentGiven: z.boolean(),
  consentGivenAt: z.string().nullable(),
  consentVersion: z.string().nullable(),
  personalDataMasked: z.boolean(),
  recordVersion: z.number().int().positive(),
  createdAt: z.string(),
  updatedAt: z.string(),
});
export type CandidateProfile = z.infer<typeof CandidateProfileSchema>;

export function parseCandidateProfile(row: Record<string, unknown>): CandidateProfile {
  return CandidateProfileSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    fullName: row.full_name,
    email: row.email ?? null,
    phone: row.phone ?? null,
    nationalIdNumber: row.national_id_number ?? null,
    dateOfBirth: row.date_of_birth ?? null,
    address: row.address ?? null,
    resumeFileId: row.resume_file_id ?? null,
    source: row.source,
    status: row.status,
    consentGiven: row.consent_given,
    consentGivenAt: row.consent_given_at ?? null,
    consentVersion: row.consent_version ?? null,
    personalDataMasked: row.personal_data_masked,
    recordVersion: row.record_version,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  });
}

/** app.list_candidates' own projection -- no pii column at all (mirrors app.list_employees). */
export const CandidateListRowSchema = z.object({
  id: z.string().uuid(),
  fullName: z.string(),
  source: CandidateSourceSchema,
  status: CandidateStatusSchema,
  consentGiven: z.boolean(),
  createdAt: z.string(),
});
export type CandidateListRow = z.infer<typeof CandidateListRowSchema>;

export function parseCandidateListRow(row: Record<string, unknown>): CandidateListRow {
  return CandidateListRowSchema.parse({
    id: row.id,
    fullName: row.full_name,
    source: row.source,
    status: row.status,
    consentGiven: row.consent_given,
    createdAt: row.created_at,
  });
}

export const CandidateDuplicateMatchSchema = z.object({
  id: z.string().uuid(),
  fullName: z.string(),
  similarityBasis: z.string(),
  similarityScore: z.coerce.number(),
});
export type CandidateDuplicateMatch = z.infer<typeof CandidateDuplicateMatchSchema>;

export function parseCandidateDuplicateMatch(row: Record<string, unknown>): CandidateDuplicateMatch {
  return CandidateDuplicateMatchSchema.parse({
    id: row.id,
    fullName: row.full_name,
    similarityBasis: row.similarity_basis,
    similarityScore: row.similarity_score,
  });
}

export const CandidateDuplicateCandidateSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  sourceCandidateId: z.string().uuid(),
  candidateId: z.string().uuid(),
  similarityBasis: z.string(),
  similarityScore: z.coerce.number().nullable(),
  decision: z.enum(["pending", "linked", "dismissed"]),
  decidedBy: z.string().nullable(),
  decidedAt: z.string().nullable(),
  decidedReason: z.string().nullable(),
  recordVersion: z.number().int().positive(),
  createdAt: z.string(),
});
export type CandidateDuplicateCandidate = z.infer<typeof CandidateDuplicateCandidateSchema>;

export function parseCandidateDuplicateCandidate(row: Record<string, unknown>): CandidateDuplicateCandidate {
  return CandidateDuplicateCandidateSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    sourceCandidateId: row.source_candidate_id,
    candidateId: row.candidate_id,
    similarityBasis: row.similarity_basis,
    similarityScore: row.similarity_score ?? null,
    decision: row.decision,
    decidedBy: row.decided_by ?? null,
    decidedAt: row.decided_at ?? null,
    decidedReason: row.decided_reason ?? null,
    recordVersion: row.record_version,
    createdAt: row.created_at,
  });
}

// --- Application ---

export const JobApplicationSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  vacancyId: z.string().uuid(),
  candidateId: z.string().uuid(),
  stage: ApplicationStageSchema,
  source: CandidateSourceSchema,
  appliedAt: z.string(),
  stageSince: z.string(),
  rejectionReason: z.string().nullable(),
  withdrawalReason: z.string().nullable(),
  recordVersion: z.number().int().positive(),
  createdAt: z.string(),
  updatedAt: z.string(),
});
export type JobApplication = z.infer<typeof JobApplicationSchema>;

export function parseJobApplication(row: Record<string, unknown>): JobApplication {
  return JobApplicationSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    vacancyId: row.vacancy_id,
    candidateId: row.candidate_id,
    stage: row.stage,
    source: row.source,
    appliedAt: row.applied_at,
    stageSince: row.stage_since,
    rejectionReason: row.rejection_reason ?? null,
    withdrawalReason: row.withdrawal_reason ?? null,
    recordVersion: row.record_version,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  });
}

export const ApplicationPipelineRowSchema = z.object({
  id: z.string().uuid(),
  candidateId: z.string().uuid(),
  candidateFullName: z.string(),
  stage: ApplicationStageSchema,
  source: CandidateSourceSchema,
  appliedAt: z.string(),
  stageSince: z.string(),
});
export type ApplicationPipelineRow = z.infer<typeof ApplicationPipelineRowSchema>;

export function parseApplicationPipelineRow(row: Record<string, unknown>): ApplicationPipelineRow {
  return ApplicationPipelineRowSchema.parse({
    id: row.id,
    candidateId: row.candidate_id,
    candidateFullName: row.candidate_full_name,
    stage: row.stage,
    source: row.source,
    appliedAt: row.applied_at,
    stageSince: row.stage_since,
  });
}

export const ApplicationDetailSchema = z.object({
  application: JobApplicationSchema,
  candidateId: z.string().uuid(),
  candidateFullName: z.string(),
  vacancyTitle: z.string(),
});
export type ApplicationDetail = z.infer<typeof ApplicationDetailSchema>;

export function parseApplicationDetail(row: Record<string, unknown>): ApplicationDetail {
  return ApplicationDetailSchema.parse({
    application: parseJobApplication(row.application as Record<string, unknown>),
    candidateId: row.candidate_id,
    candidateFullName: row.candidate_full_name,
    vacancyTitle: row.vacancy_title,
  });
}

export const ApplicationStageHistoryRowSchema = z.object({
  id: z.string().uuid(),
  fromStage: z.string(),
  toStage: z.string(),
  reason: z.string().nullable(),
  actorLabel: z.string().nullable(),
  occurredAt: z.string(),
});
export type ApplicationStageHistoryRow = z.infer<typeof ApplicationStageHistoryRowSchema>;

export function parseApplicationStageHistoryRow(row: Record<string, unknown>): ApplicationStageHistoryRow {
  return ApplicationStageHistoryRowSchema.parse({
    id: row.id,
    fromStage: row.from_stage,
    toStage: row.to_stage,
    reason: row.reason ?? null,
    actorLabel: row.actor_label ?? null,
    occurredAt: row.occurred_at,
  });
}

// --- Assessment ---

export const CandidateAssessmentSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  applicationId: z.string().uuid(),
  assessmentType: AssessmentTypeSchema,
  criteriaVersion: z.string(),
  maxScore: z.coerce.number(),
  passThreshold: z.coerce.number().nullable(),
  score: z.coerce.number().nullable(),
  status: AssessmentStatusSchema,
  notes: z.string().nullable(),
  completedAt: z.string().nullable(),
  recordVersion: z.number().int().positive(),
  createdAt: z.string(),
});
export type CandidateAssessment = z.infer<typeof CandidateAssessmentSchema>;

export function parseCandidateAssessment(row: Record<string, unknown>): CandidateAssessment {
  return CandidateAssessmentSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    applicationId: row.application_id,
    assessmentType: row.assessment_type,
    criteriaVersion: row.criteria_version,
    maxScore: row.max_score,
    passThreshold: row.pass_threshold ?? null,
    score: row.score ?? null,
    status: row.status,
    notes: row.notes ?? null,
    completedAt: row.completed_at ?? null,
    recordVersion: row.record_version,
    createdAt: row.created_at,
  });
}

// --- Interview ---

export const InterviewSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  applicationId: z.string().uuid(),
  round: z.number().int().positive(),
  mode: InterviewModeSchema,
  scheduledAt: z.string(),
  durationMinutes: z.number().int().positive(),
  locationOrLink: z.string().nullable(),
  status: InterviewStatusSchema,
  cancelReason: z.string().nullable(),
  recordVersion: z.number().int().positive(),
  createdAt: z.string(),
});
export type Interview = z.infer<typeof InterviewSchema>;

export function parseInterview(row: Record<string, unknown>): Interview {
  return InterviewSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    applicationId: row.application_id,
    round: row.round,
    mode: row.mode,
    scheduledAt: row.scheduled_at,
    durationMinutes: row.duration_minutes,
    locationOrLink: row.location_or_link ?? null,
    status: row.status,
    cancelReason: row.cancel_reason ?? null,
    recordVersion: row.record_version,
    createdAt: row.created_at,
  });
}

export const InterviewWithPanelSchema = z.object({
  interview: InterviewSchema,
  interviewerEmployeeIds: z.array(z.string().uuid()),
  feedbackCount: z.number().int().nonnegative(),
});
export type InterviewWithPanel = z.infer<typeof InterviewWithPanelSchema>;

export function parseInterviewWithPanel(row: Record<string, unknown>): InterviewWithPanel {
  return InterviewWithPanelSchema.parse({
    interview: parseInterview(row.interview as Record<string, unknown>),
    interviewerEmployeeIds: (row.interviewer_employee_ids as string[] | null) ?? [],
    feedbackCount: row.feedback_count,
  });
}

export const InterviewFeedbackSchema = z.object({
  id: z.string().uuid(),
  interviewId: z.string().uuid(),
  interviewerEmployeeId: z.string().uuid(),
  rating: z.number().int().min(1).max(5),
  recommendation: InterviewRecommendationSchema,
  notes: z.string().nullable(),
  submittedAt: z.string(),
});
export type InterviewFeedback = z.infer<typeof InterviewFeedbackSchema>;

export function parseInterviewFeedback(row: Record<string, unknown>): InterviewFeedback {
  return InterviewFeedbackSchema.parse({
    id: row.id,
    interviewId: row.interview_id,
    interviewerEmployeeId: row.interviewer_employee_id,
    rating: row.rating,
    recommendation: row.recommendation,
    notes: row.notes ?? null,
    submittedAt: row.submitted_at,
  });
}

export const MyAssignedInterviewSchema = z.object({
  interviewId: z.string().uuid(),
  applicationId: z.string().uuid(),
  candidateFullName: z.string(),
  vacancyTitle: z.string(),
  scheduledAt: z.string(),
  status: InterviewStatusSchema,
  myFeedbackSubmitted: z.boolean(),
});
export type MyAssignedInterview = z.infer<typeof MyAssignedInterviewSchema>;

export function parseMyAssignedInterview(row: Record<string, unknown>): MyAssignedInterview {
  return MyAssignedInterviewSchema.parse({
    interviewId: row.interview_id,
    applicationId: row.application_id,
    candidateFullName: row.candidate_full_name,
    vacancyTitle: row.vacancy_title,
    scheduledAt: row.scheduled_at,
    status: row.status,
    myFeedbackSubmitted: row.my_feedback_submitted,
  });
}

// --- Offer ---

export const JobOfferSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  applicationId: z.string().uuid(),
  status: OfferStatusSchema,
  approvalStatus: OfferApprovalStatusSchema,
  approvalRequestId: z.string().uuid().nullable(),
  currentVersionId: z.string().uuid().nullable(),
  recordVersion: z.number().int().positive(),
  createdAt: z.string(),
  updatedAt: z.string(),
});
export type JobOffer = z.infer<typeof JobOfferSchema>;

export function parseJobOffer(row: Record<string, unknown>): JobOffer {
  return JobOfferSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    applicationId: row.application_id,
    status: row.status,
    approvalStatus: row.approval_status,
    approvalRequestId: row.approval_request_id ?? null,
    currentVersionId: row.current_version_id ?? null,
    recordVersion: row.record_version,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  });
}

export const JobOfferVersionSchema = z.object({
  id: z.string().uuid(),
  offerId: z.string().uuid(),
  versionNumber: z.number().int().positive(),
  compensationAmount: z.coerce.number(),
  compensationCurrency: z.string(),
  effectiveDate: z.string(),
  expiryDate: z.string().nullable(),
  title: z.string(),
  employmentType: EmploymentTypeSchema,
  benefitsNote: z.string().nullable(),
  status: z.enum(["draft", "submitted", "superseded"]),
  createdAt: z.string(),
});
export type JobOfferVersion = z.infer<typeof JobOfferVersionSchema>;

export function parseJobOfferVersion(row: Record<string, unknown>): JobOfferVersion {
  return JobOfferVersionSchema.parse({
    id: row.id,
    offerId: row.offer_id,
    versionNumber: row.version_number,
    compensationAmount: row.compensation_amount,
    compensationCurrency: row.compensation_currency,
    effectiveDate: row.effective_date,
    expiryDate: row.expiry_date ?? null,
    title: row.title,
    employmentType: row.employment_type,
    benefitsNote: row.benefits_note ?? null,
    status: row.status,
    createdAt: row.created_at,
  });
}

export const OfferTimelineSchema = z.object({
  offer: JobOfferSchema,
  versions: z.array(JobOfferVersionSchema),
});
export type OfferTimeline = z.infer<typeof OfferTimelineSchema>;

export function parseOfferTimeline(row: Record<string, unknown>): OfferTimeline {
  const rawVersions = (row.versions as Record<string, unknown>[] | null) ?? [];
  return OfferTimelineSchema.parse({
    offer: parseJobOffer(row.offer as Record<string, unknown>),
    versions: rawVersions.map(parseJobOfferVersion),
  });
}

// --- Mutation input schemas ---

export const CreateJobVacancyDraftInputSchema = z.object({
  tenantId: z.string().uuid(),
  positionId: z.string().uuid(),
  title: z.string().min(1),
  employmentType: EmploymentTypeSchema,
  headcount: z.number().int().positive(),
  description: z.string().nullable(),
  requirements: z.string().nullable(),
  hiringManagerEmployeeId: z.string().uuid().nullable(),
  idempotencyKey: z.string().nullable(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type CreateJobVacancyDraftInput = z.input<typeof CreateJobVacancyDraftInputSchema>;

export const UpdateJobVacancyDraftInputSchema = z.object({
  id: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  title: z.string().min(1),
  employmentType: EmploymentTypeSchema,
  headcount: z.number().int().positive(),
  description: z.string().nullable(),
  requirements: z.string().nullable(),
  hiringManagerEmployeeId: z.string().uuid().nullable(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type UpdateJobVacancyDraftInput = z.input<typeof UpdateJobVacancyDraftInputSchema>;

export const PublishJobVacancyInputSchema = z.object({
  id: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  validityDays: z.number().int().positive(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type PublishJobVacancyInput = z.input<typeof PublishJobVacancyInputSchema>;

export const VacancyStatusActionInputSchema = z.object({
  id: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  reason: z.string().nullable(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type VacancyStatusActionInput = z.input<typeof VacancyStatusActionInputSchema>;

export const CreateCandidateInputSchema = z.object({
  tenantId: z.string().uuid(),
  fullName: z.string().min(1),
  email: z.string().email(),
  phone: z.string().nullable(),
  source: z.enum(["staff_created", "referral", "agency", "talent_pool", "import"]),
  referralEmployeeId: z.string().uuid().nullable(),
  idempotencyKey: z.string().nullable(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type CreateCandidateInput = z.input<typeof CreateCandidateInputSchema>;

export const UpdateCandidateProfileInputSchema = z.object({
  id: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  fullName: z.string().min(1),
  phone: z.string().nullable(),
  nationalIdNumber: z.string().nullable(),
  dateOfBirth: z.string().nullable(),
  address: z.string().nullable(),
  resumeFileId: z.string().uuid().nullable(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type UpdateCandidateProfileInput = z.input<typeof UpdateCandidateProfileInputSchema>;

export const RecordCandidateConsentInputSchema = z.object({
  id: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  consentVersion: z.string().min(1),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type RecordCandidateConsentInput = z.input<typeof RecordCandidateConsentInputSchema>;

export const SetCandidateStatusInputSchema = z.object({
  id: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  newStatus: CandidateStatusSchema,
  reason: z.string().nullable(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type SetCandidateStatusInput = z.input<typeof SetCandidateStatusInputSchema>;

export const FlagCandidateDuplicateInputSchema = z.object({
  sourceCandidateId: z.string().uuid(),
  candidateId: z.string().uuid(),
  similarityBasis: z.string().min(1),
  similarityScore: z.number().nullable(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type FlagCandidateDuplicateInput = z.input<typeof FlagCandidateDuplicateInputSchema>;

export const DecideCandidateDuplicateInputSchema = z.object({
  id: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  decision: z.enum(["linked", "dismissed"]),
  reason: z.string().min(1),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type DecideCandidateDuplicateInput = z.input<typeof DecideCandidateDuplicateInputSchema>;

export const ApplyToVacancyInputSchema = z.object({
  vacancyId: z.string().uuid(),
  candidateId: z.string().uuid(),
  source: z.enum(["staff_created", "referral", "agency", "talent_pool", "import"]),
  idempotencyKey: z.string().nullable(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type ApplyToVacancyInput = z.input<typeof ApplyToVacancyInputSchema>;

export const TransitionApplicationStageInputSchema = z.object({
  id: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  toStage: z.enum(["new", "screening", "assessment", "interview", "offer"]),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type TransitionApplicationStageInput = z.input<typeof TransitionApplicationStageInputSchema>;

export const ApplicationTerminalActionInputSchema = z.object({
  id: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  reason: z.string().min(1),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type ApplicationTerminalActionInput = z.input<typeof ApplicationTerminalActionInputSchema>;

export const CreateCandidateAssessmentInputSchema = z.object({
  applicationId: z.string().uuid(),
  assessmentType: AssessmentTypeSchema,
  criteriaVersion: z.string().min(1),
  maxScore: z.number().positive(),
  passThreshold: z.number().nonnegative().nullable(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type CreateCandidateAssessmentInput = z.input<typeof CreateCandidateAssessmentInputSchema>;

export const RecordAssessmentResultInputSchema = z.object({
  id: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  score: z.number().nonnegative(),
  notes: z.string().nullable(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type RecordAssessmentResultInput = z.input<typeof RecordAssessmentResultInputSchema>;

export const CancelCandidateAssessmentInputSchema = z.object({
  id: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  reason: z.string().min(1),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type CancelCandidateAssessmentInput = z.input<typeof CancelCandidateAssessmentInputSchema>;

export const ScheduleInterviewInputSchema = z.object({
  applicationId: z.string().uuid(),
  round: z.number().int().positive().nullable(),
  mode: InterviewModeSchema,
  scheduledAt: z.string().min(1),
  durationMinutes: z.number().int().positive(),
  locationOrLink: z.string().nullable(),
  interviewerEmployeeIds: z.array(z.string().uuid()).min(1),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type ScheduleInterviewInput = z.input<typeof ScheduleInterviewInputSchema>;

export const RescheduleInterviewInputSchema = z.object({
  id: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  scheduledAt: z.string().min(1),
  durationMinutes: z.number().int().positive(),
  locationOrLink: z.string().nullable(),
  mode: InterviewModeSchema,
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type RescheduleInterviewInput = z.input<typeof RescheduleInterviewInputSchema>;

export const CancelInterviewInputSchema = z.object({
  id: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  reason: z.string().min(1),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type CancelInterviewInput = z.input<typeof CancelInterviewInputSchema>;

export const CompleteInterviewInputSchema = z.object({
  id: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type CompleteInterviewInput = z.input<typeof CompleteInterviewInputSchema>;

export const SubmitInterviewFeedbackInputSchema = z.object({
  interviewId: z.string().uuid(),
  rating: z.number().int().min(1).max(5),
  recommendation: InterviewRecommendationSchema,
  notes: z.string().nullable(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type SubmitInterviewFeedbackInput = z.input<typeof SubmitInterviewFeedbackInputSchema>;

export const CreateJobOfferVersionInputSchema = z.object({
  applicationId: z.string().uuid(),
  compensationAmount: z.number().nonnegative(),
  compensationCurrency: z.string().min(1),
  effectiveDate: z.string().min(1),
  expiryDate: z.string().nullable(),
  title: z.string().min(1),
  employmentType: EmploymentTypeSchema,
  benefitsNote: z.string().nullable(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type CreateJobOfferVersionInput = z.input<typeof CreateJobOfferVersionInputSchema>;

export const SubmitJobOfferForApprovalInputSchema = z.object({
  offerId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type SubmitJobOfferForApprovalInput = z.input<typeof SubmitJobOfferForApprovalInputSchema>;

export const DecideJobOfferApprovalInputSchema = z.object({
  requestStepId: z.string().uuid(),
  decision: z.enum(["approved", "rejected"]),
  reason: z.string().nullable(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type DecideJobOfferApprovalInput = z.input<typeof DecideJobOfferApprovalInputSchema>;

export const ExtendJobOfferInputSchema = z.object({
  offerId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type ExtendJobOfferInput = z.input<typeof ExtendJobOfferInputSchema>;

export const RecordOfferResponseInputSchema = z.object({
  offerId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  response: OfferResponseSchema,
  responseNote: z.string().nullable(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type RecordOfferResponseInput = z.input<typeof RecordOfferResponseInputSchema>;

// --- Public intake input schemas ---

export const SubmitPublicJobApplicationInputSchema = z.object({
  postingToken: z.string().min(1),
  clientKey: z.string().min(1),
  fullName: z.string().min(1),
  email: z.string().email(),
  phone: z.string().nullable(),
  consentGiven: z.boolean(),
  consentVersion: z.string().min(1),
  idempotencyKey: z.string().nullable(),
});
export type SubmitPublicJobApplicationInput = z.input<typeof SubmitPublicJobApplicationInputSchema>;

export const PublicSubmitResultSchema = z.object({
  submitStatus: z.enum(["ok", "not_found", "invalid", "rate_limited", "conflict"]),
  applicationId: z.string().uuid().nullable(),
});
export type PublicSubmitResult = z.infer<typeof PublicSubmitResultSchema>;

export function parsePublicSubmitResult(row: Record<string, unknown>): PublicSubmitResult {
  return PublicSubmitResultSchema.parse({
    submitStatus: row.submit_status,
    applicationId: (row.application_id as string | null) ?? null,
  });
}
