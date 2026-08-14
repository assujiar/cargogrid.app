/**
 * Training and Talent read queries (HRT-284, CG-S12-HRT-012). Thin, typed
 * wrappers around every read RPC in
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
  parseTrainingCertificateExpiryReminderRow,
  parseTrainingDevelopmentPlanRow,
  parseTrainingDevelopmentPlanActionRow,
  parseTalentReviewCycleRow,
  parseTalentReviewAssignmentRow,
  parseTalentReviewRow,
  parseTalentPoolRow,
  parseTalentPoolMemberRow,
  parseTalentSuccessionCandidateRow,
  parseTalentPoolDistributionRow,
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
  type TrainingCertificateExpiryReminderRow,
  type TrainingDevelopmentPlanRow,
  type TrainingDevelopmentPlanActionRow,
  type TalentReviewCycleRow,
  type TalentReviewAssignmentRow,
  type TalentReviewRow,
  type TalentPoolRow,
  type TalentPoolMemberRow,
  type TalentSuccessionCandidateRow,
  type TalentPoolDistributionRow,
} from "../contracts/training-talent/training-talent.ts";

export type TrainingTalentQueryClient = Pick<SupabaseClient, "rpc">;

export class TrainingTalentQueryError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "TrainingTalentQueryError";
  }
}

function rows(data: unknown): Record<string, unknown>[] {
  return (data as Record<string, unknown>[] | null) ?? [];
}

// --- Competency ---

export async function listTrainingCompetencies(client: TrainingTalentQueryClient, tenantId: string, actorAuthUserId: string): Promise<TrainingCompetencyRow[]> {
  const { data, error } = await client.rpc("list_training_competencies", { p_tenant_id: tenantId, p_actor_auth_user_id: actorAuthUserId });
  if (error) throw new TrainingTalentQueryError(error.message);
  return rows(data).map(parseTrainingCompetencyRow);
}

// --- Course / version / competency ---

export async function listTrainingCourses(client: TrainingTalentQueryClient, tenantId: string, actorAuthUserId: string): Promise<TrainingCourseRow[]> {
  const { data, error } = await client.rpc("list_training_courses", { p_tenant_id: tenantId, p_actor_auth_user_id: actorAuthUserId });
  if (error) throw new TrainingTalentQueryError(error.message);
  return rows(data).map(parseTrainingCourseRow);
}

export async function listTrainingCourseVersions(client: TrainingTalentQueryClient, courseId: string, actorAuthUserId: string): Promise<TrainingCourseVersionRow[]> {
  const { data, error } = await client.rpc("list_training_course_versions", { p_course_id: courseId, p_actor_auth_user_id: actorAuthUserId });
  if (error) throw new TrainingTalentQueryError(error.message);
  return rows(data).map(parseTrainingCourseVersionRow);
}

export async function listTrainingCourseCompetencies(client: TrainingTalentQueryClient, courseId: string, actorAuthUserId: string): Promise<TrainingCourseCompetencyRow[]> {
  const { data, error } = await client.rpc("list_training_course_competencies", { p_course_id: courseId, p_actor_auth_user_id: actorAuthUserId });
  if (error) throw new TrainingTalentQueryError(error.message);
  return rows(data).map(parseTrainingCourseCompetencyRow);
}

export async function listTrainingCoursePrerequisites(client: TrainingTalentQueryClient, courseId: string, actorAuthUserId: string): Promise<TrainingCoursePrerequisiteRow[]> {
  const { data, error } = await client.rpc("list_training_course_prerequisites", { p_course_id: courseId, p_actor_auth_user_id: actorAuthUserId });
  if (error) throw new TrainingTalentQueryError(error.message);
  return rows(data).map(parseTrainingCoursePrerequisiteRow);
}

// --- Provider ---

export async function listTrainingProviders(client: TrainingTalentQueryClient, tenantId: string, actorAuthUserId: string): Promise<TrainingProviderRow[]> {
  const { data, error } = await client.rpc("list_training_providers", { p_tenant_id: tenantId, p_actor_auth_user_id: actorAuthUserId });
  if (error) throw new TrainingTalentQueryError(error.message);
  return rows(data).map(parseTrainingProviderRow);
}

// --- Session ---

export async function listTrainingSessions(
  client: TrainingTalentQueryClient, tenantId: string, actorAuthUserId: string, courseId?: string | null, status?: string | null,
): Promise<TrainingSessionRow[]> {
  const { data, error } = await client.rpc("list_training_sessions", { p_tenant_id: tenantId, p_actor_auth_user_id: actorAuthUserId, p_course_id: courseId ?? null, p_status: status ?? null });
  if (error) throw new TrainingTalentQueryError(error.message);
  return rows(data).map(parseTrainingSessionRow);
}

export async function getTrainingSession(client: TrainingTalentQueryClient, sessionId: string, actorAuthUserId: string): Promise<TrainingSessionRow | null> {
  const { data, error } = await client.rpc("get_training_session", { p_session_id: sessionId, p_actor_auth_user_id: actorAuthUserId });
  if (error) throw new TrainingTalentQueryError(error.message);
  const row = Array.isArray(data) ? data[0] : data;
  return row ? parseTrainingSessionRow(row as Record<string, unknown>) : null;
}

// --- Enrollment ---

export async function listTrainingEnrollments(
  client: TrainingTalentQueryClient, tenantId: string, actorAuthUserId: string, sessionId?: string | null, employeeId?: string | null, status?: string | null,
): Promise<TrainingEnrollmentRow[]> {
  const { data, error } = await client.rpc("list_training_enrollments", {
    p_tenant_id: tenantId, p_actor_auth_user_id: actorAuthUserId, p_session_id: sessionId ?? null, p_employee_id: employeeId ?? null, p_status: status ?? null,
  });
  if (error) throw new TrainingTalentQueryError(error.message);
  return rows(data).map(parseTrainingEnrollmentRow);
}

export async function listMyTrainingEnrollments(client: TrainingTalentQueryClient, tenantId: string, actorAuthUserId: string, status?: string | null): Promise<TrainingEnrollmentRow[]> {
  const { data, error } = await client.rpc("list_my_training_enrollments", { p_tenant_id: tenantId, p_actor_auth_user_id: actorAuthUserId, p_status: status ?? null });
  if (error) throw new TrainingTalentQueryError(error.message);
  return rows(data).map(parseTrainingEnrollmentRow);
}

// --- Assessment ---

export async function listTrainingAssessments(client: TrainingTalentQueryClient, enrollmentId: string, actorAuthUserId: string): Promise<TrainingAssessmentRow[]> {
  const { data, error } = await client.rpc("list_training_assessments", { p_enrollment_id: enrollmentId, p_actor_auth_user_id: actorAuthUserId });
  if (error) throw new TrainingTalentQueryError(error.message);
  return rows(data).map(parseTrainingAssessmentRow);
}

// --- Certificate ---

export async function listTrainingCertificates(client: TrainingTalentQueryClient, tenantId: string, actorAuthUserId: string, employeeId?: string | null): Promise<TrainingCertificateRow[]> {
  const { data, error } = await client.rpc("list_training_certificates", { p_tenant_id: tenantId, p_actor_auth_user_id: actorAuthUserId, p_employee_id: employeeId ?? null });
  if (error) throw new TrainingTalentQueryError(error.message);
  return rows(data).map(parseTrainingCertificateRow);
}

export async function listMyTrainingCertificates(client: TrainingTalentQueryClient, tenantId: string, actorAuthUserId: string): Promise<TrainingCertificateRow[]> {
  const { data, error } = await client.rpc("list_my_training_certificates", { p_tenant_id: tenantId, p_actor_auth_user_id: actorAuthUserId });
  if (error) throw new TrainingTalentQueryError(error.message);
  return rows(data).map(parseTrainingCertificateRow);
}

export async function getTrainingCertificate(client: TrainingTalentQueryClient, certificateId: string, actorAuthUserId: string): Promise<TrainingCertificateRow | null> {
  const { data, error } = await client.rpc("get_training_certificate", { p_certificate_id: certificateId, p_actor_auth_user_id: actorAuthUserId });
  if (error) throw new TrainingTalentQueryError(error.message);
  const row = Array.isArray(data) ? data[0] : data;
  return row ? parseTrainingCertificateRow(row as Record<string, unknown>) : null;
}

export async function listTrainingCertificateExpiryReminders(
  client: TrainingTalentQueryClient, tenantId: string, actorAuthUserId: string, employeeId?: string | null,
): Promise<TrainingCertificateExpiryReminderRow[]> {
  const { data, error } = await client.rpc("list_training_certificate_expiry_reminders", { p_tenant_id: tenantId, p_actor_auth_user_id: actorAuthUserId, p_employee_id: employeeId ?? null });
  if (error) throw new TrainingTalentQueryError(error.message);
  return rows(data).map(parseTrainingCertificateExpiryReminderRow);
}

// --- Development plan ---

export async function listTrainingDevelopmentPlans(
  client: TrainingTalentQueryClient, tenantId: string, actorAuthUserId: string, employeeId?: string | null,
): Promise<TrainingDevelopmentPlanRow[]> {
  const { data, error } = await client.rpc("list_training_development_plans", { p_tenant_id: tenantId, p_actor_auth_user_id: actorAuthUserId, p_employee_id: employeeId ?? null });
  if (error) throw new TrainingTalentQueryError(error.message);
  return rows(data).map(parseTrainingDevelopmentPlanRow);
}

export async function listMyTrainingDevelopmentPlans(client: TrainingTalentQueryClient, tenantId: string, actorAuthUserId: string): Promise<TrainingDevelopmentPlanRow[]> {
  const { data, error } = await client.rpc("list_my_training_development_plans", { p_tenant_id: tenantId, p_actor_auth_user_id: actorAuthUserId });
  if (error) throw new TrainingTalentQueryError(error.message);
  return rows(data).map(parseTrainingDevelopmentPlanRow);
}

export async function listTrainingDevelopmentPlanActions(client: TrainingTalentQueryClient, planId: string, actorAuthUserId: string): Promise<TrainingDevelopmentPlanActionRow[]> {
  const { data, error } = await client.rpc("list_training_development_plan_actions", { p_plan_id: planId, p_actor_auth_user_id: actorAuthUserId });
  if (error) throw new TrainingTalentQueryError(error.message);
  return rows(data).map(parseTrainingDevelopmentPlanActionRow);
}

// --- Talent review ---

export async function listTalentReviewCycles(client: TrainingTalentQueryClient, tenantId: string, actorAuthUserId: string): Promise<TalentReviewCycleRow[]> {
  const { data, error } = await client.rpc("list_talent_review_cycles", { p_tenant_id: tenantId, p_actor_auth_user_id: actorAuthUserId });
  if (error) throw new TrainingTalentQueryError(error.message);
  return rows(data).map(parseTalentReviewCycleRow);
}

export async function listTalentReviewAssignments(
  client: TrainingTalentQueryClient, tenantId: string, actorAuthUserId: string, cycleId?: string | null,
): Promise<TalentReviewAssignmentRow[]> {
  const { data, error } = await client.rpc("list_talent_review_assignments", { p_tenant_id: tenantId, p_actor_auth_user_id: actorAuthUserId, p_cycle_id: cycleId ?? null });
  if (error) throw new TrainingTalentQueryError(error.message);
  return rows(data).map(parseTalentReviewAssignmentRow);
}

export async function listMyTalentReviewAssignments(client: TrainingTalentQueryClient, tenantId: string, actorAuthUserId: string): Promise<TalentReviewAssignmentRow[]> {
  const { data, error } = await client.rpc("list_my_talent_review_assignments", { p_tenant_id: tenantId, p_actor_auth_user_id: actorAuthUserId });
  if (error) throw new TrainingTalentQueryError(error.message);
  return rows(data).map(parseTalentReviewAssignmentRow);
}

export async function getTalentReview(client: TrainingTalentQueryClient, reviewId: string, actorAuthUserId: string): Promise<TalentReviewRow | null> {
  const { data, error } = await client.rpc("get_talent_review", { p_review_id: reviewId, p_actor_auth_user_id: actorAuthUserId });
  if (error) throw new TrainingTalentQueryError(error.message);
  const row = Array.isArray(data) ? data[0] : data;
  return row ? parseTalentReviewRow(row as Record<string, unknown>) : null;
}

// --- Talent pool ---

export async function listTalentPools(client: TrainingTalentQueryClient, tenantId: string, actorAuthUserId: string): Promise<TalentPoolRow[]> {
  const { data, error } = await client.rpc("list_talent_pools", { p_tenant_id: tenantId, p_actor_auth_user_id: actorAuthUserId });
  if (error) throw new TrainingTalentQueryError(error.message);
  return rows(data).map(parseTalentPoolRow);
}

export async function listTalentPoolMembers(client: TrainingTalentQueryClient, poolId: string, actorAuthUserId: string): Promise<TalentPoolMemberRow[]> {
  const { data, error } = await client.rpc("list_talent_pool_members", { p_pool_id: poolId, p_actor_auth_user_id: actorAuthUserId });
  if (error) throw new TrainingTalentQueryError(error.message);
  return rows(data).map(parseTalentPoolMemberRow);
}

// --- Succession candidate ---

export async function listSuccessionCandidates(
  client: TrainingTalentQueryClient, tenantId: string, actorAuthUserId: string, positionId?: string | null,
): Promise<TalentSuccessionCandidateRow[]> {
  const { data, error } = await client.rpc("list_succession_candidates", { p_tenant_id: tenantId, p_actor_auth_user_id: actorAuthUserId, p_position_id: positionId ?? null });
  if (error) throw new TrainingTalentQueryError(error.message);
  return rows(data).map(parseTalentSuccessionCandidateRow);
}

// --- Reporting ---

export async function reportTalentPoolDistributionByDepartment(
  client: TrainingTalentQueryClient, tenantId: string, poolId: string, actorAuthUserId: string, actorLabel: string,
): Promise<TalentPoolDistributionRow[]> {
  const { data, error } = await client.rpc("report_talent_pool_distribution_by_department", { p_tenant_id: tenantId, p_pool_id: poolId, p_actor_auth_user_id: actorAuthUserId, p_actor_label: actorLabel });
  if (error) throw new TrainingTalentQueryError(error.message);
  return rows(data).map(parseTalentPoolDistributionRow);
}
