/**
 * Vendor Assessment read queries (PRC-252, CG-S11-PRC-003). Thin, typed wrappers
 * around app.get_vendor_assessment_template/app.list_vendor_assessment_templates/
 * app.list_vendor_assessment_template_criteria/app.get_vendor_assessment/
 * app.list_vendor_assessments/app.get_vendor_assessment_score_breakdown/
 * app.list_vendor_assessment_findings/app.list_vendor_assessment_corrective_actions/
 * app.get_vendor_current_assessment_status
 * (supabase/migrations/20260730590000_create_procurement_vendor_assessment.sql).
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import {
  parseVendorAssessmentTemplate,
  parseVendorAssessmentTemplateCriterion,
  parseVendorAssessment,
  parseVendorAssessmentMutationResult,
  parseVendorAssessmentScoreBreakdownRow,
  parseVendorAssessmentFinding,
  parseVendorAssessmentCorrectiveAction,
  parseVendorCurrentAssessmentStatusRow,
  type VendorAssessmentTemplate,
  type VendorAssessmentTemplateCriterion,
  type VendorAssessment,
  type VendorAssessmentMutationResult,
  type VendorAssessmentScoreBreakdownRow,
  type VendorAssessmentFinding,
  type VendorAssessmentCorrectiveAction,
  type VendorCurrentAssessmentStatusRow,
  type VendorAssessmentTemplateStatus,
  type VendorAssessmentStatus,
} from "../contracts/vendor-assessment/vendor-assessment.ts";

export type VendorAssessmentQueryClient = Pick<SupabaseClient, "rpc">;

export class VendorAssessmentQueryError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "VendorAssessmentQueryError";
  }
}

function firstRow(data: unknown): Record<string, unknown> | null {
  const row = Array.isArray(data) ? data[0] : data;
  return row && typeof row === "object" ? (row as Record<string, unknown>) : null;
}

function rows(data: unknown): Record<string, unknown>[] {
  return (data as Record<string, unknown>[] | null) ?? [];
}

// --- Templates ---

export async function getVendorAssessmentTemplate(client: VendorAssessmentQueryClient, templateVersionId: string, actorAuthUserId: string): Promise<VendorAssessmentTemplate> {
  const { data, error } = await client.rpc("get_vendor_assessment_template", { p_template_version_id: templateVersionId, p_actor_auth_user_id: actorAuthUserId });
  if (error) throw new VendorAssessmentQueryError(error.message);
  const row = firstRow(data);
  if (!row) throw new VendorAssessmentQueryError("get_vendor_assessment_template returned no row");
  return parseVendorAssessmentTemplate(row);
}

export async function listVendorAssessmentTemplates(
  client: VendorAssessmentQueryClient,
  tenantId: string,
  actorAuthUserId: string,
  options?: { statusFilter?: VendorAssessmentTemplateStatus | null; vendorCategory?: string | null; assessmentType?: string | null; limit?: number; afterId?: string | null },
): Promise<VendorAssessmentTemplate[]> {
  const { data, error } = await client.rpc("list_vendor_assessment_templates", {
    p_tenant_id: tenantId,
    p_actor_auth_user_id: actorAuthUserId,
    p_status_filter: options?.statusFilter ?? null,
    p_vendor_category: options?.vendorCategory ?? null,
    p_assessment_type: options?.assessmentType ?? null,
    p_limit: options?.limit ?? 50,
    p_after_id: options?.afterId ?? null,
  });
  if (error) throw new VendorAssessmentQueryError(error.message);
  return rows(data).map(parseVendorAssessmentTemplate);
}

export async function listVendorAssessmentTemplateCriteria(client: VendorAssessmentQueryClient, templateVersionId: string, actorAuthUserId: string): Promise<VendorAssessmentTemplateCriterion[]> {
  const { data, error } = await client.rpc("list_vendor_assessment_template_criteria", { p_template_version_id: templateVersionId, p_actor_auth_user_id: actorAuthUserId });
  if (error) throw new VendorAssessmentQueryError(error.message);
  return rows(data).map(parseVendorAssessmentTemplateCriterion);
}

// --- Assessments ---

export async function getVendorAssessment(client: VendorAssessmentQueryClient, assessmentId: string, actorAuthUserId: string): Promise<VendorAssessment> {
  const { data, error } = await client.rpc("get_vendor_assessment", { p_assessment_id: assessmentId, p_actor_auth_user_id: actorAuthUserId });
  if (error) throw new VendorAssessmentQueryError(error.message);
  const row = firstRow(data);
  if (!row) throw new VendorAssessmentQueryError("get_vendor_assessment returned no row");
  return parseVendorAssessment(row);
}

/** Cursor-paginated queue, server-filtered -- never a client-loaded full dataset. assignedToMe=true filters to rows where the caller is the assessor OR the reviewer (the assessment queue's own "assigned to me" tab). */
export async function listVendorAssessments(
  client: VendorAssessmentQueryClient,
  tenantId: string,
  actorAuthUserId: string,
  options?: { statusFilter?: VendorAssessmentStatus | null; vendorMasterRecordId?: string | null; assignedToMe?: boolean; limit?: number; afterId?: string | null },
): Promise<VendorAssessmentMutationResult[]> {
  const { data, error } = await client.rpc("list_vendor_assessments", {
    p_tenant_id: tenantId,
    p_actor_auth_user_id: actorAuthUserId,
    p_status_filter: options?.statusFilter ?? null,
    p_vendor_master_record_id: options?.vendorMasterRecordId ?? null,
    p_assigned_to_me: options?.assignedToMe ?? false,
    p_limit: options?.limit ?? 50,
    p_after_id: options?.afterId ?? null,
  });
  if (error) throw new VendorAssessmentQueryError(error.message);
  return rows(data).map(parseVendorAssessmentMutationResult);
}

/** The explainable-scoring panel's own data source -- one row per active criterion in the assessment's own applied template version. */
export async function getVendorAssessmentScoreBreakdown(client: VendorAssessmentQueryClient, assessmentId: string, actorAuthUserId: string): Promise<VendorAssessmentScoreBreakdownRow[]> {
  const { data, error } = await client.rpc("get_vendor_assessment_score_breakdown", { p_assessment_id: assessmentId, p_actor_auth_user_id: actorAuthUserId });
  if (error) throw new VendorAssessmentQueryError(error.message);
  return rows(data).map(parseVendorAssessmentScoreBreakdownRow);
}

export async function listVendorAssessmentFindings(client: VendorAssessmentQueryClient, assessmentId: string, actorAuthUserId: string): Promise<VendorAssessmentFinding[]> {
  const { data, error } = await client.rpc("list_vendor_assessment_findings", { p_assessment_id: assessmentId, p_actor_auth_user_id: actorAuthUserId });
  if (error) throw new VendorAssessmentQueryError(error.message);
  return rows(data).map(parseVendorAssessmentFinding);
}

export async function listVendorAssessmentCorrectiveActions(client: VendorAssessmentQueryClient, assessmentId: string, actorAuthUserId: string): Promise<VendorAssessmentCorrectiveAction[]> {
  const { data, error } = await client.rpc("list_vendor_assessment_corrective_actions", { p_assessment_id: assessmentId, p_actor_auth_user_id: actorAuthUserId });
  if (error) throw new VendorAssessmentQueryError(error.message);
  return rows(data).map(parseVendorAssessmentCorrectiveAction);
}

/** The downstream-composable read (prompt's own "Downstream" scope note) -- one row per assessment_type, for Prompts 253/256+ to compose eligibility against. Never composed here. */
export async function getVendorCurrentAssessmentStatus(client: VendorAssessmentQueryClient, vendorMasterRecordId: string, actorAuthUserId: string): Promise<VendorCurrentAssessmentStatusRow[]> {
  const { data, error } = await client.rpc("get_vendor_current_assessment_status", { p_vendor_master_record_id: vendorMasterRecordId, p_actor_auth_user_id: actorAuthUserId });
  if (error) throw new VendorAssessmentQueryError(error.message);
  return rows(data).map(parseVendorCurrentAssessmentStatusRow);
}
