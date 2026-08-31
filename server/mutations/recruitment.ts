/**
 * Recruitment, Job Portal and ATS mutation primitives (HRT-276, CG-S12-HRT-004).
 * Thin, typed wrappers around every vacancy/candidate/application/assessment/
 * interview/offer RPC in
 * supabase/migrations/20260730860000_create_hris_recruitment_ats.sql.
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import {
  CreateJobVacancyDraftInputSchema,
  UpdateJobVacancyDraftInputSchema,
  PublishJobVacancyInputSchema,
  VacancyStatusActionInputSchema,
  CreateCandidateInputSchema,
  UpdateCandidateProfileInputSchema,
  RecordCandidateConsentInputSchema,
  SetCandidateStatusInputSchema,
  FlagCandidateDuplicateInputSchema,
  DecideCandidateDuplicateInputSchema,
  ApplyToVacancyInputSchema,
  TransitionApplicationStageInputSchema,
  ApplicationTerminalActionInputSchema,
  CreateCandidateAssessmentInputSchema,
  RecordAssessmentResultInputSchema,
  CancelCandidateAssessmentInputSchema,
  ScheduleInterviewInputSchema,
  RescheduleInterviewInputSchema,
  CancelInterviewInputSchema,
  CompleteInterviewInputSchema,
  SubmitInterviewFeedbackInputSchema,
  CreateJobOfferVersionInputSchema,
  SubmitJobOfferForApprovalInputSchema,
  DecideJobOfferApprovalInputSchema,
  ExtendJobOfferInputSchema,
  RecordOfferResponseInputSchema,
  SubmitPublicJobApplicationInputSchema,
  parseJobVacancy,
  parseJobVacancyPublishResult,
  parseCandidateProfile,
  parseCandidateDuplicateCandidate,
  parseJobApplication,
  parseCandidateAssessment,
  parseInterview,
  parseInterviewFeedback,
  parseJobOffer,
  parseJobOfferVersion,
  parsePublicSubmitResult,
  type CreateJobVacancyDraftInput,
  type UpdateJobVacancyDraftInput,
  type PublishJobVacancyInput,
  type VacancyStatusActionInput,
  type CreateCandidateInput,
  type UpdateCandidateProfileInput,
  type RecordCandidateConsentInput,
  type SetCandidateStatusInput,
  type FlagCandidateDuplicateInput,
  type DecideCandidateDuplicateInput,
  type ApplyToVacancyInput,
  type TransitionApplicationStageInput,
  type ApplicationTerminalActionInput,
  type CreateCandidateAssessmentInput,
  type RecordAssessmentResultInput,
  type CancelCandidateAssessmentInput,
  type ScheduleInterviewInput,
  type RescheduleInterviewInput,
  type CancelInterviewInput,
  type CompleteInterviewInput,
  type SubmitInterviewFeedbackInput,
  type CreateJobOfferVersionInput,
  type SubmitJobOfferForApprovalInput,
  type DecideJobOfferApprovalInput,
  type ExtendJobOfferInput,
  type RecordOfferResponseInput,
  type SubmitPublicJobApplicationInput,
  type JobVacancy,
  type JobVacancyPublishResult,
  type CandidateProfile,
  type CandidateDuplicateCandidate,
  type JobApplication,
  type CandidateAssessment,
  type Interview,
  type InterviewFeedback,
  type JobOffer,
  type JobOfferVersion,
  type PublicSubmitResult,
} from "../contracts/recruitment/recruitment.ts";
import { resolveRequestClientIp } from "../../lib/security/client-ip.ts";

export type RecruitmentMutationRpcClient = Pick<SupabaseClient, "rpc">;

export const RECRUITMENT_KNOWN_MUTATION_ERROR_CODES = [
  "insufficient_authority",
  "insufficient_privilege",
  "invalid_title",
  "invalid_headcount",
  "invalid_validity",
  "invalid_transition",
  "reason_required",
  "stale_version",
  "vacancy_not_found",
  "position_not_found",
  "position_inactive",
  "employee_not_found",
  "idempotency_key_conflict",
  "vacancy_headcount_exceeds_position_capacity",
  "posting_expired",
  "invalid_full_name",
  "invalid_email",
  "invalid_source",
  "referral_employee_required",
  "candidate_not_found",
  "candidate_archived",
  "resume_file_not_found",
  "resume_file_infected",
  "consent_version_required",
  "invalid_status",
  "invalid_duplicate_pair",
  "similarity_basis_required",
  "duplicate_candidate_not_found",
  "invalid_decision",
  "vacancy_not_open",
  "candidate_not_active",
  "application_not_found",
  "application_already_exists",
  "consent_required",
  "resume_not_scanned",
  "interview_feedback_required",
  "invalid_application_stage",
  "criteria_version_required",
  "invalid_max_score",
  "invalid_pass_threshold",
  "assessment_not_found",
  "invalid_score",
  "interviewers_required",
  "interview_not_found",
  "not_assigned_interviewer",
  "invalid_interview_status",
  "invalid_rating",
  "invalid_recommendation",
  "feedback_already_submitted",
  "invalid_compensation_amount",
  "invalid_currency",
  "invalid_expiry_date",
  "offer_not_found",
  "approval_definition_not_configured",
  "approval_step_not_found",
  "not_a_job_offer_approval",
  "invalid_response",
  "intake_client_key_required",
  "invalid_response_shape",
  // HRT-294 (CG-S12-HRT-022, ISS-2026-114): raised by app.decide_job_offer_approval
  // since its own Tier C fix migration, never added here (API-parity gap).
  "offer_approval_no_longer_applicable",
] as const;
type KnownRecruitmentMutationErrorCode = (typeof RECRUITMENT_KNOWN_MUTATION_ERROR_CODES)[number];
export type RecruitmentMutationErrorCode = KnownRecruitmentMutationErrorCode | "mutation_failed";

export class RecruitmentMutationError extends Error {
  readonly code: RecruitmentMutationErrorCode;

  constructor(code: RecruitmentMutationErrorCode, message: string) {
    super(message);
    this.name = "RecruitmentMutationError";
    this.code = code;
  }
}

function classifyError(message: string): RecruitmentMutationErrorCode {
  const prefix = message.split(":")[0]?.trim();
  return (RECRUITMENT_KNOWN_MUTATION_ERROR_CODES as readonly string[]).includes(prefix ?? "") ? (prefix as KnownRecruitmentMutationErrorCode) : "mutation_failed";
}

function firstRow(data: unknown): Record<string, unknown> | null {
  const row = Array.isArray(data) ? data[0] : data;
  return row && typeof row === "object" ? (row as Record<string, unknown>) : null;
}

// --- Vacancy ---

export async function createJobVacancyDraft(client: RecruitmentMutationRpcClient, input: CreateJobVacancyDraftInput): Promise<JobVacancy> {
  const parsed = CreateJobVacancyDraftInputSchema.parse(input);
  const { data, error } = await client.rpc("create_job_vacancy_draft", {
    p_tenant_id: parsed.tenantId,
    p_position_id: parsed.positionId,
    p_title: parsed.title,
    p_employment_type: parsed.employmentType,
    p_headcount: parsed.headcount,
    p_description: parsed.description ?? null,
    p_requirements: parsed.requirements ?? null,
    p_hiring_manager_employee_id: parsed.hiringManagerEmployeeId ?? null,
    p_idempotency_key: parsed.idempotencyKey ?? null,
    p_actor_auth_user_id: parsed.actorAuthUserId,
    p_actor_label: parsed.actorLabel,
  });
  if (error) throw new RecruitmentMutationError(classifyError(error.message), error.message);
  const row = firstRow(data);
  if (!row) throw new RecruitmentMutationError("invalid_response_shape", "create_job_vacancy_draft returned no row");
  return parseJobVacancy(row);
}

export async function updateJobVacancyDraft(client: RecruitmentMutationRpcClient, input: UpdateJobVacancyDraftInput): Promise<JobVacancy> {
  const parsed = UpdateJobVacancyDraftInputSchema.parse(input);
  const { data, error } = await client.rpc("update_job_vacancy_draft", {
    p_id: parsed.id,
    p_expected_version: parsed.expectedVersion,
    p_title: parsed.title,
    p_employment_type: parsed.employmentType,
    p_headcount: parsed.headcount,
    p_description: parsed.description ?? null,
    p_requirements: parsed.requirements ?? null,
    p_hiring_manager_employee_id: parsed.hiringManagerEmployeeId ?? null,
    p_actor_auth_user_id: parsed.actorAuthUserId,
    p_actor_label: parsed.actorLabel,
  });
  if (error) throw new RecruitmentMutationError(classifyError(error.message), error.message);
  const row = firstRow(data);
  if (!row) throw new RecruitmentMutationError("invalid_response_shape", "update_job_vacancy_draft returned no row");
  return parseJobVacancy(row);
}

export async function publishJobVacancy(client: RecruitmentMutationRpcClient, input: PublishJobVacancyInput): Promise<JobVacancyPublishResult> {
  const parsed = PublishJobVacancyInputSchema.parse(input);
  const { data, error } = await client.rpc("publish_job_vacancy", {
    p_id: parsed.id,
    p_expected_version: parsed.expectedVersion,
    p_validity_days: parsed.validityDays,
    p_actor_auth_user_id: parsed.actorAuthUserId,
    p_actor_label: parsed.actorLabel,
    // ISS-2026-302: read here rather than threaded through every caller -- a security
    // control a call site can forget to pass is not a control. Null outside a request.
    p_client_ip: await resolveRequestClientIp(),
  });
  if (error) throw new RecruitmentMutationError(classifyError(error.message), error.message);
  const row = firstRow(data);
  if (!row) throw new RecruitmentMutationError("invalid_response_shape", "publish_job_vacancy returned no row");
  return parseJobVacancyPublishResult(row);
}

async function vacancyStatusAction(client: RecruitmentMutationRpcClient, rpcName: string, input: VacancyStatusActionInput): Promise<JobVacancy> {
  const parsed = VacancyStatusActionInputSchema.parse(input);
  const { data, error } = await client.rpc(rpcName, {
    p_id: parsed.id,
    p_expected_version: parsed.expectedVersion,
    p_reason: parsed.reason ?? null,
    p_actor_auth_user_id: parsed.actorAuthUserId,
    p_actor_label: parsed.actorLabel,
  });
  if (error) throw new RecruitmentMutationError(classifyError(error.message), error.message);
  const row = firstRow(data);
  if (!row) throw new RecruitmentMutationError("invalid_response_shape", `${rpcName} returned no row`);
  return parseJobVacancy(row);
}

export const holdJobVacancy = (client: RecruitmentMutationRpcClient, input: VacancyStatusActionInput) => vacancyStatusAction(client, "hold_job_vacancy", input);
export const closeJobVacancy = (client: RecruitmentMutationRpcClient, input: VacancyStatusActionInput) => vacancyStatusAction(client, "close_job_vacancy", input);
export const cancelJobVacancyDraft = (client: RecruitmentMutationRpcClient, input: VacancyStatusActionInput) => vacancyStatusAction(client, "cancel_job_vacancy_draft", input);

export async function reopenJobVacancy(client: RecruitmentMutationRpcClient, input: { id: string; expectedVersion: number; actorAuthUserId: string; actorLabel: string }): Promise<JobVacancy> {
  const { data, error } = await client.rpc("reopen_job_vacancy", {
    p_id: input.id,
    p_expected_version: input.expectedVersion,
    p_actor_auth_user_id: input.actorAuthUserId,
    p_actor_label: input.actorLabel,
  });
  if (error) throw new RecruitmentMutationError(classifyError(error.message), error.message);
  const row = firstRow(data);
  if (!row) throw new RecruitmentMutationError("invalid_response_shape", "reopen_job_vacancy returned no row");
  return parseJobVacancy(row);
}

// --- Candidate ---

export async function createCandidate(client: RecruitmentMutationRpcClient, input: CreateCandidateInput): Promise<CandidateProfile> {
  const parsed = CreateCandidateInputSchema.parse(input);
  const { data, error } = await client.rpc("create_candidate", {
    p_tenant_id: parsed.tenantId,
    p_full_name: parsed.fullName,
    p_email: parsed.email,
    p_phone: parsed.phone ?? null,
    p_source: parsed.source,
    p_referral_employee_id: parsed.referralEmployeeId ?? null,
    p_idempotency_key: parsed.idempotencyKey ?? null,
    p_actor_auth_user_id: parsed.actorAuthUserId,
    p_actor_label: parsed.actorLabel,
  });
  if (error) throw new RecruitmentMutationError(classifyError(error.message), error.message);
  const row = firstRow(data);
  if (!row) throw new RecruitmentMutationError("invalid_response_shape", "create_candidate returned no row");
  // create_candidate returns the raw app.candidates row (unmasked -- the caller just
  // supplied these values themselves), reuse parseCandidateProfile with masked=false.
  return parseCandidateProfile({ ...row, personal_data_masked: false });
}

export async function updateCandidateProfile(client: RecruitmentMutationRpcClient, input: UpdateCandidateProfileInput): Promise<CandidateProfile> {
  const parsed = UpdateCandidateProfileInputSchema.parse(input);
  const { data, error } = await client.rpc("update_candidate_profile", {
    p_id: parsed.id,
    p_expected_version: parsed.expectedVersion,
    p_full_name: parsed.fullName,
    p_phone: parsed.phone ?? null,
    p_national_id_number: parsed.nationalIdNumber ?? null,
    p_date_of_birth: parsed.dateOfBirth ?? null,
    p_address: parsed.address ?? null,
    p_resume_file_id: parsed.resumeFileId ?? null,
    p_actor_auth_user_id: parsed.actorAuthUserId,
    p_actor_label: parsed.actorLabel,
  });
  if (error) throw new RecruitmentMutationError(classifyError(error.message), error.message);
  const row = firstRow(data);
  if (!row) throw new RecruitmentMutationError("invalid_response_shape", "update_candidate_profile returned no row");
  return parseCandidateProfile({ ...row, personal_data_masked: false });
}

export async function recordCandidateConsent(client: RecruitmentMutationRpcClient, input: RecordCandidateConsentInput): Promise<CandidateProfile> {
  const parsed = RecordCandidateConsentInputSchema.parse(input);
  const { data, error } = await client.rpc("record_candidate_consent", {
    p_id: parsed.id,
    p_expected_version: parsed.expectedVersion,
    p_consent_version: parsed.consentVersion,
    p_actor_auth_user_id: parsed.actorAuthUserId,
    p_actor_label: parsed.actorLabel,
  });
  if (error) throw new RecruitmentMutationError(classifyError(error.message), error.message);
  const row = firstRow(data);
  if (!row) throw new RecruitmentMutationError("invalid_response_shape", "record_candidate_consent returned no row");
  return parseCandidateProfile({ ...row, personal_data_masked: false });
}

export async function setCandidateStatus(client: RecruitmentMutationRpcClient, input: SetCandidateStatusInput): Promise<CandidateProfile> {
  const parsed = SetCandidateStatusInputSchema.parse(input);
  const { data, error } = await client.rpc("set_candidate_status", {
    p_id: parsed.id,
    p_expected_version: parsed.expectedVersion,
    p_new_status: parsed.newStatus,
    p_reason: parsed.reason ?? null,
    p_actor_auth_user_id: parsed.actorAuthUserId,
    p_actor_label: parsed.actorLabel,
  });
  if (error) throw new RecruitmentMutationError(classifyError(error.message), error.message);
  const row = firstRow(data);
  if (!row) throw new RecruitmentMutationError("invalid_response_shape", "set_candidate_status returned no row");
  return parseCandidateProfile({ ...row, personal_data_masked: false });
}

export async function flagCandidateDuplicate(client: RecruitmentMutationRpcClient, input: FlagCandidateDuplicateInput): Promise<CandidateDuplicateCandidate> {
  const parsed = FlagCandidateDuplicateInputSchema.parse(input);
  const { data, error } = await client.rpc("flag_candidate_duplicate", {
    p_source_candidate_id: parsed.sourceCandidateId,
    p_candidate_id: parsed.candidateId,
    p_similarity_basis: parsed.similarityBasis,
    p_similarity_score: parsed.similarityScore ?? null,
    p_actor_auth_user_id: parsed.actorAuthUserId,
    p_actor_label: parsed.actorLabel,
  });
  if (error) throw new RecruitmentMutationError(classifyError(error.message), error.message);
  const row = firstRow(data);
  if (!row) throw new RecruitmentMutationError("invalid_response_shape", "flag_candidate_duplicate returned no row");
  return parseCandidateDuplicateCandidate(row);
}

export async function decideCandidateDuplicate(client: RecruitmentMutationRpcClient, input: DecideCandidateDuplicateInput): Promise<CandidateDuplicateCandidate> {
  const parsed = DecideCandidateDuplicateInputSchema.parse(input);
  const { data, error } = await client.rpc("decide_candidate_duplicate", {
    p_id: parsed.id,
    p_expected_version: parsed.expectedVersion,
    p_decision: parsed.decision,
    p_reason: parsed.reason,
    p_actor_auth_user_id: parsed.actorAuthUserId,
    p_actor_label: parsed.actorLabel,
  });
  if (error) throw new RecruitmentMutationError(classifyError(error.message), error.message);
  const row = firstRow(data);
  if (!row) throw new RecruitmentMutationError("invalid_response_shape", "decide_candidate_duplicate returned no row");
  return parseCandidateDuplicateCandidate(row);
}

// --- Application ---

export async function applyToVacancy(client: RecruitmentMutationRpcClient, input: ApplyToVacancyInput): Promise<JobApplication> {
  const parsed = ApplyToVacancyInputSchema.parse(input);
  const { data, error } = await client.rpc("apply_to_vacancy", {
    p_vacancy_id: parsed.vacancyId,
    p_candidate_id: parsed.candidateId,
    p_source: parsed.source,
    p_idempotency_key: parsed.idempotencyKey ?? null,
    p_actor_auth_user_id: parsed.actorAuthUserId,
    p_actor_label: parsed.actorLabel,
  });
  if (error) throw new RecruitmentMutationError(classifyError(error.message), error.message);
  const row = firstRow(data);
  if (!row) throw new RecruitmentMutationError("invalid_response_shape", "apply_to_vacancy returned no row");
  return parseJobApplication(row);
}

export async function transitionApplicationStage(client: RecruitmentMutationRpcClient, input: TransitionApplicationStageInput): Promise<JobApplication> {
  const parsed = TransitionApplicationStageInputSchema.parse(input);
  const { data, error } = await client.rpc("transition_application_stage", {
    p_id: parsed.id,
    p_expected_version: parsed.expectedVersion,
    p_to_stage: parsed.toStage,
    p_actor_auth_user_id: parsed.actorAuthUserId,
    p_actor_label: parsed.actorLabel,
  });
  if (error) throw new RecruitmentMutationError(classifyError(error.message), error.message);
  const row = firstRow(data);
  if (!row) throw new RecruitmentMutationError("invalid_response_shape", "transition_application_stage returned no row");
  return parseJobApplication(row);
}

async function applicationTerminalAction(client: RecruitmentMutationRpcClient, rpcName: string, input: ApplicationTerminalActionInput): Promise<JobApplication> {
  const parsed = ApplicationTerminalActionInputSchema.parse(input);
  const { data, error } = await client.rpc(rpcName, {
    p_id: parsed.id,
    p_expected_version: parsed.expectedVersion,
    p_reason: parsed.reason,
    p_actor_auth_user_id: parsed.actorAuthUserId,
    p_actor_label: parsed.actorLabel,
  });
  if (error) throw new RecruitmentMutationError(classifyError(error.message), error.message);
  const row = firstRow(data);
  if (!row) throw new RecruitmentMutationError("invalid_response_shape", `${rpcName} returned no row`);
  return parseJobApplication(row);
}

export const rejectApplication = (client: RecruitmentMutationRpcClient, input: ApplicationTerminalActionInput) => applicationTerminalAction(client, "reject_application", input);
export const withdrawApplication = (client: RecruitmentMutationRpcClient, input: ApplicationTerminalActionInput) => applicationTerminalAction(client, "withdraw_application", input);

// --- Assessment ---

export async function createCandidateAssessment(client: RecruitmentMutationRpcClient, input: CreateCandidateAssessmentInput): Promise<CandidateAssessment> {
  const parsed = CreateCandidateAssessmentInputSchema.parse(input);
  const { data, error } = await client.rpc("create_candidate_assessment", {
    p_application_id: parsed.applicationId,
    p_assessment_type: parsed.assessmentType,
    p_criteria_version: parsed.criteriaVersion,
    p_max_score: parsed.maxScore,
    p_pass_threshold: parsed.passThreshold ?? null,
    p_actor_auth_user_id: parsed.actorAuthUserId,
    p_actor_label: parsed.actorLabel,
  });
  if (error) throw new RecruitmentMutationError(classifyError(error.message), error.message);
  const row = firstRow(data);
  if (!row) throw new RecruitmentMutationError("invalid_response_shape", "create_candidate_assessment returned no row");
  return parseCandidateAssessment(row);
}

export async function recordAssessmentResult(client: RecruitmentMutationRpcClient, input: RecordAssessmentResultInput): Promise<CandidateAssessment> {
  const parsed = RecordAssessmentResultInputSchema.parse(input);
  const { data, error } = await client.rpc("record_assessment_result", {
    p_id: parsed.id,
    p_expected_version: parsed.expectedVersion,
    p_score: parsed.score,
    p_notes: parsed.notes ?? null,
    p_actor_auth_user_id: parsed.actorAuthUserId,
    p_actor_label: parsed.actorLabel,
  });
  if (error) throw new RecruitmentMutationError(classifyError(error.message), error.message);
  const row = firstRow(data);
  if (!row) throw new RecruitmentMutationError("invalid_response_shape", "record_assessment_result returned no row");
  return parseCandidateAssessment(row);
}

export async function cancelCandidateAssessment(client: RecruitmentMutationRpcClient, input: CancelCandidateAssessmentInput): Promise<CandidateAssessment> {
  const parsed = CancelCandidateAssessmentInputSchema.parse(input);
  const { data, error } = await client.rpc("cancel_candidate_assessment", {
    p_id: parsed.id,
    p_expected_version: parsed.expectedVersion,
    p_reason: parsed.reason,
    p_actor_auth_user_id: parsed.actorAuthUserId,
    p_actor_label: parsed.actorLabel,
  });
  if (error) throw new RecruitmentMutationError(classifyError(error.message), error.message);
  const row = firstRow(data);
  if (!row) throw new RecruitmentMutationError("invalid_response_shape", "cancel_candidate_assessment returned no row");
  return parseCandidateAssessment(row);
}

// --- Interview ---

export async function scheduleInterview(client: RecruitmentMutationRpcClient, input: ScheduleInterviewInput): Promise<Interview> {
  const parsed = ScheduleInterviewInputSchema.parse(input);
  const { data, error } = await client.rpc("schedule_interview", {
    p_application_id: parsed.applicationId,
    p_round: parsed.round ?? null,
    p_mode: parsed.mode,
    p_scheduled_at: parsed.scheduledAt,
    p_duration_minutes: parsed.durationMinutes,
    p_location_or_link: parsed.locationOrLink ?? null,
    p_interviewer_employee_ids: parsed.interviewerEmployeeIds,
    p_actor_auth_user_id: parsed.actorAuthUserId,
    p_actor_label: parsed.actorLabel,
  });
  if (error) throw new RecruitmentMutationError(classifyError(error.message), error.message);
  const row = firstRow(data);
  if (!row) throw new RecruitmentMutationError("invalid_response_shape", "schedule_interview returned no row");
  return parseInterview(row);
}

export async function rescheduleInterview(client: RecruitmentMutationRpcClient, input: RescheduleInterviewInput): Promise<Interview> {
  const parsed = RescheduleInterviewInputSchema.parse(input);
  const { data, error } = await client.rpc("reschedule_interview", {
    p_id: parsed.id,
    p_expected_version: parsed.expectedVersion,
    p_scheduled_at: parsed.scheduledAt,
    p_duration_minutes: parsed.durationMinutes,
    p_location_or_link: parsed.locationOrLink ?? null,
    p_mode: parsed.mode,
    p_actor_auth_user_id: parsed.actorAuthUserId,
    p_actor_label: parsed.actorLabel,
  });
  if (error) throw new RecruitmentMutationError(classifyError(error.message), error.message);
  const row = firstRow(data);
  if (!row) throw new RecruitmentMutationError("invalid_response_shape", "reschedule_interview returned no row");
  return parseInterview(row);
}

export async function cancelInterview(client: RecruitmentMutationRpcClient, input: CancelInterviewInput): Promise<Interview> {
  const parsed = CancelInterviewInputSchema.parse(input);
  const { data, error } = await client.rpc("cancel_interview", {
    p_id: parsed.id,
    p_expected_version: parsed.expectedVersion,
    p_reason: parsed.reason,
    p_actor_auth_user_id: parsed.actorAuthUserId,
    p_actor_label: parsed.actorLabel,
  });
  if (error) throw new RecruitmentMutationError(classifyError(error.message), error.message);
  const row = firstRow(data);
  if (!row) throw new RecruitmentMutationError("invalid_response_shape", "cancel_interview returned no row");
  return parseInterview(row);
}

export async function completeInterview(client: RecruitmentMutationRpcClient, input: CompleteInterviewInput): Promise<Interview> {
  const parsed = CompleteInterviewInputSchema.parse(input);
  const { data, error } = await client.rpc("complete_interview", {
    p_id: parsed.id,
    p_expected_version: parsed.expectedVersion,
    p_actor_auth_user_id: parsed.actorAuthUserId,
    p_actor_label: parsed.actorLabel,
  });
  if (error) throw new RecruitmentMutationError(classifyError(error.message), error.message);
  const row = firstRow(data);
  if (!row) throw new RecruitmentMutationError("invalid_response_shape", "complete_interview returned no row");
  return parseInterview(row);
}

/** Identity-gated (design note 5) -- the caller's own linked employee must be an assigned interviewer for this interview. */
export async function submitInterviewFeedback(client: RecruitmentMutationRpcClient, input: SubmitInterviewFeedbackInput): Promise<InterviewFeedback> {
  const parsed = SubmitInterviewFeedbackInputSchema.parse(input);
  const { data, error } = await client.rpc("submit_interview_feedback", {
    p_interview_id: parsed.interviewId,
    p_rating: parsed.rating,
    p_recommendation: parsed.recommendation,
    p_notes: parsed.notes ?? null,
    p_actor_auth_user_id: parsed.actorAuthUserId,
    p_actor_label: parsed.actorLabel,
  });
  if (error) throw new RecruitmentMutationError(classifyError(error.message), error.message);
  const row = firstRow(data);
  if (!row) throw new RecruitmentMutationError("invalid_response_shape", "submit_interview_feedback returned no row");
  return parseInterviewFeedback(row);
}

// --- Offer ---

export async function createJobOfferVersion(client: RecruitmentMutationRpcClient, input: CreateJobOfferVersionInput): Promise<JobOfferVersion> {
  const parsed = CreateJobOfferVersionInputSchema.parse(input);
  const { data, error } = await client.rpc("create_job_offer_version", {
    p_application_id: parsed.applicationId,
    p_compensation_amount: parsed.compensationAmount,
    p_compensation_currency: parsed.compensationCurrency,
    p_effective_date: parsed.effectiveDate,
    p_expiry_date: parsed.expiryDate ?? null,
    p_title: parsed.title,
    p_employment_type: parsed.employmentType,
    p_benefits_note: parsed.benefitsNote ?? null,
    p_actor_auth_user_id: parsed.actorAuthUserId,
    p_actor_label: parsed.actorLabel,
  });
  if (error) throw new RecruitmentMutationError(classifyError(error.message), error.message);
  const row = firstRow(data);
  if (!row) throw new RecruitmentMutationError("invalid_response_shape", "create_job_offer_version returned no row");
  return parseJobOfferVersion(row);
}

export async function submitJobOfferForApproval(client: RecruitmentMutationRpcClient, input: SubmitJobOfferForApprovalInput): Promise<JobOffer> {
  const parsed = SubmitJobOfferForApprovalInputSchema.parse(input);
  const { data, error } = await client.rpc("submit_job_offer_for_approval", {
    p_offer_id: parsed.offerId,
    p_expected_version: parsed.expectedVersion,
    p_actor_auth_user_id: parsed.actorAuthUserId,
    p_actor_label: parsed.actorLabel,
  });
  if (error) throw new RecruitmentMutationError(classifyError(error.message), error.message);
  const row = firstRow(data);
  if (!row) throw new RecruitmentMutationError("invalid_response_shape", "submit_job_offer_for_approval returned no row");
  return parseJobOffer(row);
}

export async function decideJobOfferApproval(client: RecruitmentMutationRpcClient, input: DecideJobOfferApprovalInput): Promise<JobOffer> {
  const parsed = DecideJobOfferApprovalInputSchema.parse(input);
  const { data, error } = await client.rpc("decide_job_offer_approval", {
    p_request_step_id: parsed.requestStepId,
    p_decision: parsed.decision,
    p_reason: parsed.reason ?? null,
    p_actor_auth_user_id: parsed.actorAuthUserId,
    p_actor_label: parsed.actorLabel,
  });
  if (error) throw new RecruitmentMutationError(classifyError(error.message), error.message);
  const row = firstRow(data);
  if (!row) throw new RecruitmentMutationError("invalid_response_shape", "decide_job_offer_approval returned no row");
  return parseJobOffer(row);
}

export async function extendJobOffer(client: RecruitmentMutationRpcClient, input: ExtendJobOfferInput): Promise<JobOffer> {
  const parsed = ExtendJobOfferInputSchema.parse(input);
  const { data, error } = await client.rpc("extend_job_offer", {
    p_offer_id: parsed.offerId,
    p_expected_version: parsed.expectedVersion,
    p_actor_auth_user_id: parsed.actorAuthUserId,
    p_actor_label: parsed.actorLabel,
  });
  if (error) throw new RecruitmentMutationError(classifyError(error.message), error.message);
  const row = firstRow(data);
  if (!row) throw new RecruitmentMutationError("invalid_response_shape", "extend_job_offer returned no row");
  return parseJobOffer(row);
}

export async function recordOfferResponse(client: RecruitmentMutationRpcClient, input: RecordOfferResponseInput): Promise<JobOffer> {
  const parsed = RecordOfferResponseInputSchema.parse(input);
  const { data, error } = await client.rpc("record_offer_response", {
    p_offer_id: parsed.offerId,
    p_expected_version: parsed.expectedVersion,
    p_response: parsed.response,
    p_response_note: parsed.responseNote ?? null,
    p_actor_auth_user_id: parsed.actorAuthUserId,
    p_actor_label: parsed.actorLabel,
  });
  if (error) throw new RecruitmentMutationError(classifyError(error.message), error.message);
  const row = firstRow(data);
  if (!row) throw new RecruitmentMutationError("invalid_response_shape", "record_offer_response returned no row");
  return parseJobOffer(row);
}

// --- Public intake (anonymous -- no actor parameter, service_role client only) ---

export async function submitPublicJobApplication(client: RecruitmentMutationRpcClient, input: SubmitPublicJobApplicationInput): Promise<PublicSubmitResult> {
  const parsed = SubmitPublicJobApplicationInputSchema.parse(input);
  const { data, error } = await client.rpc("submit_public_job_application", {
    p_posting_token: parsed.postingToken,
    p_client_key: parsed.clientKey,
    p_full_name: parsed.fullName,
    p_email: parsed.email,
    p_phone: parsed.phone ?? null,
    p_consent_given: parsed.consentGiven,
    p_consent_version: parsed.consentVersion,
    p_idempotency_key: parsed.idempotencyKey ?? null,
  });
  if (error) throw new RecruitmentMutationError(classifyError(error.message), error.message);
  const row = firstRow(data);
  if (!row) throw new RecruitmentMutationError("invalid_response_shape", "submit_public_job_application returned no row");
  return parsePublicSubmitResult(row);
}
