/**
 * Recruitment, Job Portal and ATS read queries (HRT-276, CG-S12-HRT-004). Thin,
 * typed wrappers around every list/get/export/search RPC in
 * supabase/migrations/20260730860000_create_hris_recruitment_ats.sql, plus the three
 * genuinely public (anonymous) intake reads.
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import {
  parseJobVacancy,
  parseJobVacancyDetail,
  parseCandidateProfile,
  parseCandidateListRow,
  parseCandidateDuplicateMatch,
  parseApplicationStageHistoryRow,
  parseApplicationPipelineRow,
  parseApplicationDetail,
  parseCandidateAssessment,
  parseInterviewWithPanel,
  parseMyAssignedInterview,
  parseOfferTimeline,
  parsePublicVacancySummary,
  parsePublicVacancyDetail,
  type JobVacancy,
  type JobVacancyDetail,
  type CandidateProfile,
  type CandidateListRow,
  type CandidateDuplicateMatch,
  type ApplicationStageHistoryRow,
  type ApplicationPipelineRow,
  type ApplicationDetail,
  type CandidateAssessment,
  type InterviewWithPanel,
  type MyAssignedInterview,
  type OfferTimeline,
  type PublicVacancySummary,
  type PublicVacancyDetail,
  type VacancyStatus,
  type CandidateStatus,
  type ApplicationStage,
} from "../contracts/recruitment/recruitment.ts";

export type RecruitmentQueryClient = Pick<SupabaseClient, "rpc">;

export class RecruitmentQueryError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "RecruitmentQueryError";
  }
}

function firstRow(data: unknown): Record<string, unknown> | null {
  const row = Array.isArray(data) ? data[0] : data;
  return row && typeof row === "object" ? (row as Record<string, unknown>) : null;
}

function rows(data: unknown): Record<string, unknown>[] {
  return (data as Record<string, unknown>[] | null) ?? [];
}

// --- Vacancy ---

/** Cursor-paginated (id-keyset), server-filtered/searched -- never a client-loaded full dataset. */
export async function listJobVacancies(
  client: RecruitmentQueryClient,
  tenantId: string,
  actorAuthUserId: string,
  options?: { statusFilter?: VacancyStatus | null; search?: string | null; limit?: number; afterId?: string | null },
): Promise<JobVacancy[]> {
  const { data, error } = await client.rpc("list_job_vacancies", {
    p_tenant_id: tenantId,
    p_actor_auth_user_id: actorAuthUserId,
    p_status_filter: options?.statusFilter ?? null,
    p_search: options?.search ?? null,
    p_limit: options?.limit ?? 50,
    p_after_id: options?.afterId ?? null,
  });
  if (error) throw new RecruitmentQueryError(error.message);
  return rows(data).map(parseJobVacancy);
}

export async function getJobVacancy(client: RecruitmentQueryClient, id: string, actorAuthUserId: string): Promise<JobVacancyDetail> {
  const { data, error } = await client.rpc("get_job_vacancy", { p_id: id, p_actor_auth_user_id: actorAuthUserId });
  if (error) throw new RecruitmentQueryError(error.message);
  const row = firstRow(data);
  if (!row) throw new RecruitmentQueryError("get_job_vacancy returned no row");
  return parseJobVacancyDetail(row);
}

export async function exportJobVacancies(
  client: RecruitmentQueryClient,
  tenantId: string,
  actorAuthUserId: string,
  options?: { statusFilter?: VacancyStatus | null; limit?: number },
): Promise<{ id: string; title: string; employmentType: string; headcount: number; status: string }[]> {
  const { data, error } = await client.rpc("export_job_vacancies", {
    p_tenant_id: tenantId,
    p_actor_auth_user_id: actorAuthUserId,
    p_status_filter: options?.statusFilter ?? null,
    p_limit: options?.limit ?? 500,
  });
  if (error) throw new RecruitmentQueryError(error.message);
  return rows(data).map((row) => ({
    id: String(row.id),
    title: String(row.title),
    employmentType: String(row.employment_type),
    headcount: Number(row.headcount),
    status: String(row.status),
  }));
}

// --- Candidate ---

export async function getCandidateProfile(client: RecruitmentQueryClient, id: string, actorAuthUserId: string): Promise<CandidateProfile> {
  const { data, error } = await client.rpc("get_candidate_profile", { p_id: id, p_actor_auth_user_id: actorAuthUserId });
  if (error) throw new RecruitmentQueryError(error.message);
  const row = firstRow(data);
  if (!row) throw new RecruitmentQueryError("get_candidate_profile returned no row");
  return parseCandidateProfile(row);
}

/** No pii column in this listing projection at all (mirrors app.list_employees). */
export async function listCandidates(
  client: RecruitmentQueryClient,
  tenantId: string,
  actorAuthUserId: string,
  options?: { statusFilter?: CandidateStatus | null; search?: string | null; limit?: number; afterId?: string | null },
): Promise<CandidateListRow[]> {
  const { data, error } = await client.rpc("list_candidates", {
    p_tenant_id: tenantId,
    p_actor_auth_user_id: actorAuthUserId,
    p_status_filter: options?.statusFilter ?? null,
    p_search: options?.search ?? null,
    p_limit: options?.limit ?? 50,
    p_after_id: options?.afterId ?? null,
  });
  if (error) throw new RecruitmentQueryError(error.message);
  return rows(data).map(parseCandidateListRow);
}

export async function exportCandidates(
  client: RecruitmentQueryClient,
  tenantId: string,
  actorAuthUserId: string,
  options?: { statusFilter?: CandidateStatus | null; limit?: number },
): Promise<{ id: string; fullName: string; source: string; status: string }[]> {
  const { data, error } = await client.rpc("export_candidates", {
    p_tenant_id: tenantId,
    p_actor_auth_user_id: actorAuthUserId,
    p_status_filter: options?.statusFilter ?? null,
    p_limit: options?.limit ?? 500,
  });
  if (error) throw new RecruitmentQueryError(error.message);
  return rows(data).map((row) => ({ id: String(row.id), fullName: String(row.full_name), source: String(row.source), status: String(row.status) }));
}

export async function searchCandidateDuplicates(
  client: RecruitmentQueryClient,
  tenantId: string,
  actorAuthUserId: string,
  options: { fullName?: string | null; email?: string | null; phone?: string | null; limit?: number },
): Promise<CandidateDuplicateMatch[]> {
  const { data, error } = await client.rpc("search_candidate_duplicates", {
    p_tenant_id: tenantId,
    p_full_name: options.fullName ?? null,
    p_email: options.email ?? null,
    p_phone: options.phone ?? null,
    p_actor_auth_user_id: actorAuthUserId,
    p_limit: options.limit ?? 10,
  });
  if (error) throw new RecruitmentQueryError(error.message);
  return rows(data).map(parseCandidateDuplicateMatch);
}

// --- Application ---

/** The recruitment pipeline table projection -- candidate_full_name only, no pii column. */
export async function listApplicationsForVacancy(client: RecruitmentQueryClient, vacancyId: string, actorAuthUserId: string, stageFilter?: ApplicationStage | null): Promise<ApplicationPipelineRow[]> {
  const { data, error } = await client.rpc("list_applications_for_vacancy", { p_vacancy_id: vacancyId, p_actor_auth_user_id: actorAuthUserId, p_stage_filter: stageFilter ?? null });
  if (error) throw new RecruitmentQueryError(error.message);
  return rows(data).map(parseApplicationPipelineRow);
}

export async function getApplicationDetail(client: RecruitmentQueryClient, id: string, actorAuthUserId: string): Promise<ApplicationDetail> {
  const { data, error } = await client.rpc("get_application_detail", { p_id: id, p_actor_auth_user_id: actorAuthUserId });
  if (error) throw new RecruitmentQueryError(error.message);
  const row = firstRow(data);
  if (!row) throw new RecruitmentQueryError("get_application_detail returned no row");
  return parseApplicationDetail(row);
}

export async function listApplicationStageHistory(client: RecruitmentQueryClient, applicationId: string, actorAuthUserId: string): Promise<ApplicationStageHistoryRow[]> {
  const { data, error } = await client.rpc("list_application_stage_history", { p_application_id: applicationId, p_actor_auth_user_id: actorAuthUserId });
  if (error) throw new RecruitmentQueryError(error.message);
  return rows(data).map(parseApplicationStageHistoryRow);
}

export async function exportApplications(
  client: RecruitmentQueryClient,
  tenantId: string,
  actorAuthUserId: string,
  options?: { vacancyId?: string | null; limit?: number },
): Promise<{ id: string; vacancyTitle: string; candidateFullName: string; stage: string; source: string; appliedAt: string }[]> {
  const { data, error } = await client.rpc("export_applications", {
    p_tenant_id: tenantId,
    p_actor_auth_user_id: actorAuthUserId,
    p_vacancy_id: options?.vacancyId ?? null,
    p_limit: options?.limit ?? 500,
  });
  if (error) throw new RecruitmentQueryError(error.message);
  return rows(data).map((row) => ({
    id: String(row.id),
    vacancyTitle: String(row.vacancy_title),
    candidateFullName: String(row.candidate_full_name),
    stage: String(row.stage),
    source: String(row.source),
    appliedAt: String(row.applied_at),
  }));
}

// --- Assessment ---

export async function listCandidateAssessments(client: RecruitmentQueryClient, applicationId: string, actorAuthUserId: string): Promise<CandidateAssessment[]> {
  const { data, error } = await client.rpc("list_candidate_assessments", { p_application_id: applicationId, p_actor_auth_user_id: actorAuthUserId });
  if (error) throw new RecruitmentQueryError(error.message);
  return rows(data).map(parseCandidateAssessment);
}

// --- Interview ---

export async function listApplicationInterviews(client: RecruitmentQueryClient, applicationId: string, actorAuthUserId: string): Promise<InterviewWithPanel[]> {
  const { data, error } = await client.rpc("list_application_interviews", { p_application_id: applicationId, p_actor_auth_user_id: actorAuthUserId });
  if (error) throw new RecruitmentQueryError(error.message);
  return rows(data).map(parseInterviewWithPanel);
}

/** Self-scoped, identity-gated -- never requires HRS:View (design note 5). Empty (never throws) when the caller has no linked employee profile. */
export async function getMyAssignedInterviews(client: RecruitmentQueryClient, tenantId: string, actorAuthUserId: string): Promise<MyAssignedInterview[]> {
  const { data, error } = await client.rpc("get_my_assigned_interviews", { p_tenant_id: tenantId, p_actor_auth_user_id: actorAuthUserId });
  if (error) throw new RecruitmentQueryError(error.message);
  return rows(data).map(parseMyAssignedInterview);
}

// --- Offer ---

/** HRS:View, OR a currently-eligible approver, OR an actor who already decided a step (app.can_view_job_offer). */
export async function getOfferTimeline(client: RecruitmentQueryClient, offerId: string, actorAuthUserId: string): Promise<OfferTimeline> {
  const { data, error } = await client.rpc("get_offer_timeline", { p_offer_id: offerId, p_actor_auth_user_id: actorAuthUserId });
  if (error) throw new RecruitmentQueryError(error.message);
  const row = firstRow(data);
  if (!row) throw new RecruitmentQueryError("get_offer_timeline returned no row");
  return parseOfferTimeline(row);
}

// --- Public intake (genuinely anonymous -- service_role client only, no actor param) ---

export async function getPublicOpenVacancySummaries(client: RecruitmentQueryClient, tenantSlug: string): Promise<PublicVacancySummary[]> {
  const { data, error } = await client.rpc("get_public_open_vacancy_summaries", { p_tenant_slug: tenantSlug });
  if (error) throw new RecruitmentQueryError(error.message);
  return rows(data).map(parsePublicVacancySummary);
}

export async function resolvePublicJobPosting(client: RecruitmentQueryClient, postingToken: string, clientKey: string): Promise<PublicVacancyDetail | null> {
  const { data, error } = await client.rpc("resolve_public_job_posting", { p_posting_token: postingToken, p_client_key: clientKey });
  if (error) throw new RecruitmentQueryError(error.message);
  const row = firstRow(data);
  if (!row || row.vacancy_id == null) return null;
  return parsePublicVacancyDetail(row);
}
