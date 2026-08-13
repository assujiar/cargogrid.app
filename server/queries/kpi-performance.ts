/**
 * KPI and Performance read queries (HRT-283, CG-S12-HRT-011). Thin, typed
 * wrappers around every read RPC in
 * supabase/migrations/20260731030000_create_hris_kpi_performance.sql.
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import {
  parsePerformanceKpiDefinitionRow,
  parsePerformanceKpiDefinitionVersionRow,
  parsePerformanceTemplateRow,
  parsePerformanceTemplateKpiItemRow,
  parsePerformanceCycleRow,
  parsePerformanceGoalAssignmentRow,
  parsePerformanceMyGoalAssignmentRow,
  parsePerformanceGoalProgressEntryRow,
  parsePerformanceReviewerAssignmentRow,
  parsePerformanceAssessmentRow,
  parsePerformanceMyAssessmentRow,
  parsePerformanceAssessmentKpiScoreRow,
  parsePerformanceOutcomeRow,
  parsePerformanceMyOutcomeRow,
  parsePerformanceOutcomeDetailRow,
  parsePerformanceCalibrationAdjustmentRow,
  parsePerformanceAppealRow,
  parsePerformanceMyAppealRow,
  parsePerformanceCycleScoreDistributionRow,
  type PerformanceKpiDefinitionRow,
  type PerformanceKpiDefinitionVersionRow,
  type PerformanceTemplateRow,
  type PerformanceTemplateKpiItemRow,
  type PerformanceCycleRow,
  type PerformanceGoalAssignmentRow,
  type PerformanceMyGoalAssignmentRow,
  type PerformanceGoalProgressEntryRow,
  type PerformanceReviewerAssignmentRow,
  type PerformanceAssessmentRow,
  type PerformanceMyAssessmentRow,
  type PerformanceAssessmentKpiScoreRow,
  type PerformanceOutcomeRow,
  type PerformanceMyOutcomeRow,
  type PerformanceOutcomeDetailRow,
  type PerformanceCalibrationAdjustmentRow,
  type PerformanceAppealRow,
  type PerformanceMyAppealRow,
  type PerformanceCycleScoreDistributionRow,
} from "../contracts/kpi-performance/kpi-performance.ts";

export type PerformanceQueryClient = Pick<SupabaseClient, "rpc">;

export class PerformanceQueryError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "PerformanceQueryError";
  }
}

function rows(data: unknown): Record<string, unknown>[] {
  return (data as Record<string, unknown>[] | null) ?? [];
}

// --- Library ---

export async function listPerformanceKpiDefinitions(client: PerformanceQueryClient, tenantId: string, actorAuthUserId: string): Promise<PerformanceKpiDefinitionRow[]> {
  const { data, error } = await client.rpc("list_performance_kpi_definitions", { p_tenant_id: tenantId, p_actor_auth_user_id: actorAuthUserId });
  if (error) throw new PerformanceQueryError(error.message);
  return rows(data).map(parsePerformanceKpiDefinitionRow);
}

export async function listPerformanceKpiDefinitionVersions(client: PerformanceQueryClient, kpiDefinitionId: string, actorAuthUserId: string): Promise<PerformanceKpiDefinitionVersionRow[]> {
  const { data, error } = await client.rpc("list_performance_kpi_definition_versions", { p_kpi_definition_id: kpiDefinitionId, p_actor_auth_user_id: actorAuthUserId });
  if (error) throw new PerformanceQueryError(error.message);
  return rows(data).map(parsePerformanceKpiDefinitionVersionRow);
}

// --- Template ---

export async function listPerformanceTemplates(client: PerformanceQueryClient, tenantId: string, actorAuthUserId: string): Promise<PerformanceTemplateRow[]> {
  const { data, error } = await client.rpc("list_performance_templates", { p_tenant_id: tenantId, p_actor_auth_user_id: actorAuthUserId });
  if (error) throw new PerformanceQueryError(error.message);
  return rows(data).map(parsePerformanceTemplateRow);
}

export async function listPerformanceTemplateKpiItems(client: PerformanceQueryClient, templateId: string, actorAuthUserId: string): Promise<PerformanceTemplateKpiItemRow[]> {
  const { data, error } = await client.rpc("list_performance_template_kpi_items", { p_template_id: templateId, p_actor_auth_user_id: actorAuthUserId });
  if (error) throw new PerformanceQueryError(error.message);
  return rows(data).map(parsePerformanceTemplateKpiItemRow);
}

// --- Cycle ---

export async function listPerformanceCycles(client: PerformanceQueryClient, tenantId: string, actorAuthUserId: string, status?: string | null): Promise<PerformanceCycleRow[]> {
  const { data, error } = await client.rpc("list_performance_cycles", { p_tenant_id: tenantId, p_actor_auth_user_id: actorAuthUserId, p_status: status ?? null });
  if (error) throw new PerformanceQueryError(error.message);
  return rows(data).map(parsePerformanceCycleRow);
}

export async function getPerformanceCycle(client: PerformanceQueryClient, cycleId: string, actorAuthUserId: string): Promise<PerformanceCycleRow | null> {
  const { data, error } = await client.rpc("get_performance_cycle", { p_cycle_id: cycleId, p_actor_auth_user_id: actorAuthUserId });
  if (error) throw new PerformanceQueryError(error.message);
  const row = Array.isArray(data) ? data[0] : data;
  return row ? parsePerformanceCycleRow(row as Record<string, unknown>) : null;
}

// --- Goal assignment ---

export async function listPerformanceGoalAssignments(
  client: PerformanceQueryClient, tenantId: string, cycleId: string, actorAuthUserId: string, employeeId?: string | null,
): Promise<PerformanceGoalAssignmentRow[]> {
  const { data, error } = await client.rpc("list_performance_goal_assignments", {
    p_tenant_id: tenantId, p_cycle_id: cycleId, p_actor_auth_user_id: actorAuthUserId, p_employee_id: employeeId ?? null,
  });
  if (error) throw new PerformanceQueryError(error.message);
  return rows(data).map(parsePerformanceGoalAssignmentRow);
}

export async function listMyPerformanceGoalAssignments(
  client: PerformanceQueryClient, tenantId: string, actorAuthUserId: string, cycleId?: string | null,
): Promise<PerformanceMyGoalAssignmentRow[]> {
  const { data, error } = await client.rpc("list_my_performance_goal_assignments", { p_tenant_id: tenantId, p_actor_auth_user_id: actorAuthUserId, p_cycle_id: cycleId ?? null });
  if (error) throw new PerformanceQueryError(error.message);
  return rows(data).map(parsePerformanceMyGoalAssignmentRow);
}

export async function listPerformanceGoalProgressEntries(client: PerformanceQueryClient, goalAssignmentId: string, actorAuthUserId: string): Promise<PerformanceGoalProgressEntryRow[]> {
  const { data, error } = await client.rpc("list_performance_goal_progress_entries", { p_goal_assignment_id: goalAssignmentId, p_actor_auth_user_id: actorAuthUserId });
  if (error) throw new PerformanceQueryError(error.message);
  return rows(data).map(parsePerformanceGoalProgressEntryRow);
}

// --- Reviewer assignment ---

export async function listPerformanceReviewerAssignments(
  client: PerformanceQueryClient, tenantId: string, cycleId: string, actorAuthUserId: string, employeeId?: string | null,
): Promise<PerformanceReviewerAssignmentRow[]> {
  const { data, error } = await client.rpc("list_performance_reviewer_assignments", {
    p_tenant_id: tenantId, p_cycle_id: cycleId, p_actor_auth_user_id: actorAuthUserId, p_employee_id: employeeId ?? null,
  });
  if (error) throw new PerformanceQueryError(error.message);
  return rows(data).map(parsePerformanceReviewerAssignmentRow);
}

// --- Assessment ---

export async function listPerformanceAssessments(
  client: PerformanceQueryClient, tenantId: string, cycleId: string, actorAuthUserId: string, employeeId?: string | null, assessmentType?: string | null,
): Promise<PerformanceAssessmentRow[]> {
  const { data, error } = await client.rpc("list_performance_assessments", {
    p_tenant_id: tenantId, p_cycle_id: cycleId, p_actor_auth_user_id: actorAuthUserId, p_employee_id: employeeId ?? null, p_assessment_type: assessmentType ?? null,
  });
  if (error) throw new PerformanceQueryError(error.message);
  return rows(data).map(parsePerformanceAssessmentRow);
}

export async function listMyPerformanceAssessments(
  client: PerformanceQueryClient, tenantId: string, actorAuthUserId: string, assessmentType?: string | null,
): Promise<PerformanceMyAssessmentRow[]> {
  const { data, error } = await client.rpc("list_my_performance_assessments", { p_tenant_id: tenantId, p_actor_auth_user_id: actorAuthUserId, p_assessment_type: assessmentType ?? null });
  if (error) throw new PerformanceQueryError(error.message);
  return rows(data).map(parsePerformanceMyAssessmentRow);
}

export async function listPerformanceAssessmentKpiScores(client: PerformanceQueryClient, assessmentId: string, actorAuthUserId: string): Promise<PerformanceAssessmentKpiScoreRow[]> {
  const { data, error } = await client.rpc("list_performance_assessment_kpi_scores", { p_assessment_id: assessmentId, p_actor_auth_user_id: actorAuthUserId });
  if (error) throw new PerformanceQueryError(error.message);
  return rows(data).map(parsePerformanceAssessmentKpiScoreRow);
}

// --- Outcome / calibration ---

export async function listPerformanceOutcomes(
  client: PerformanceQueryClient, tenantId: string, cycleId: string, actorAuthUserId: string, employeeId?: string | null,
): Promise<PerformanceOutcomeRow[]> {
  const { data, error } = await client.rpc("list_performance_outcomes", {
    p_tenant_id: tenantId, p_cycle_id: cycleId, p_actor_auth_user_id: actorAuthUserId, p_employee_id: employeeId ?? null,
  });
  if (error) throw new PerformanceQueryError(error.message);
  return rows(data).map(parsePerformanceOutcomeRow);
}

export async function listMyPerformanceOutcomes(client: PerformanceQueryClient, tenantId: string, actorAuthUserId: string): Promise<PerformanceMyOutcomeRow[]> {
  const { data, error } = await client.rpc("list_my_performance_outcomes", { p_tenant_id: tenantId, p_actor_auth_user_id: actorAuthUserId });
  if (error) throw new PerformanceQueryError(error.message);
  return rows(data).map(parsePerformanceMyOutcomeRow);
}

export async function getPerformanceOutcome(client: PerformanceQueryClient, outcomeId: string, actorAuthUserId: string): Promise<PerformanceOutcomeDetailRow | null> {
  const { data, error } = await client.rpc("get_performance_outcome", { p_outcome_id: outcomeId, p_actor_auth_user_id: actorAuthUserId });
  if (error) throw new PerformanceQueryError(error.message);
  const row = Array.isArray(data) ? data[0] : data;
  return row ? parsePerformanceOutcomeDetailRow(row as Record<string, unknown>) : null;
}

export async function listPerformanceCalibrationAdjustments(client: PerformanceQueryClient, outcomeId: string, actorAuthUserId: string): Promise<PerformanceCalibrationAdjustmentRow[]> {
  const { data, error } = await client.rpc("list_performance_calibration_adjustments", { p_outcome_id: outcomeId, p_actor_auth_user_id: actorAuthUserId });
  if (error) throw new PerformanceQueryError(error.message);
  return rows(data).map(parsePerformanceCalibrationAdjustmentRow);
}

// --- Appeal ---

export async function listPerformanceAppeals(
  client: PerformanceQueryClient, tenantId: string, cycleId: string, actorAuthUserId: string, employeeId?: string | null,
): Promise<PerformanceAppealRow[]> {
  const { data, error } = await client.rpc("list_performance_appeals", {
    p_tenant_id: tenantId, p_cycle_id: cycleId, p_actor_auth_user_id: actorAuthUserId, p_employee_id: employeeId ?? null,
  });
  if (error) throw new PerformanceQueryError(error.message);
  return rows(data).map(parsePerformanceAppealRow);
}

export async function listMyPerformanceAppeals(client: PerformanceQueryClient, tenantId: string, actorAuthUserId: string): Promise<PerformanceMyAppealRow[]> {
  const { data, error } = await client.rpc("list_my_performance_appeals", { p_tenant_id: tenantId, p_actor_auth_user_id: actorAuthUserId });
  if (error) throw new PerformanceQueryError(error.message);
  return rows(data).map(parsePerformanceMyAppealRow);
}

// --- Reporting ---

export async function reportPerformanceCycleScoreDistribution(
  client: PerformanceQueryClient, tenantId: string, cycleId: string, actorAuthUserId: string, actorLabel: string,
): Promise<PerformanceCycleScoreDistributionRow[]> {
  const { data, error } = await client.rpc("report_performance_cycle_score_distribution", {
    p_tenant_id: tenantId, p_cycle_id: cycleId, p_actor_auth_user_id: actorAuthUserId, p_actor_label: actorLabel,
  });
  if (error) throw new PerformanceQueryError(error.message);
  return rows(data).map(parsePerformanceCycleScoreDistributionRow);
}
