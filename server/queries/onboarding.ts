/**
 * Onboarding and Offboarding read queries (HRT-277, CG-S12-HRT-005). Thin, typed
 * wrappers around every read RPC in
 * supabase/migrations/20260730880000_create_hris_onboarding_offboarding.sql.
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import {
  parseTemplateListRow,
  parseOnboardingChecklistTemplateTask,
  parseOnboardingCasePreview,
  parseCaseListRow,
  parseCaseDetail,
  parseCaseTask,
  parseMyOnboardingTask,
  parseApprovalTimelineRow,
  parseCaseExportRow,
  type OnboardingChecklistTemplateTask,
  type OnboardingCasePreview,
  type TemplateListRow,
  type CaseListRow,
  type CaseDetail,
  type CaseTask,
  type MyOnboardingTask,
  type ApprovalTimelineRow,
  type CaseExportRow,
  type CaseType,
  type CaseStatus,
} from "../contracts/onboarding/onboarding.ts";

export type OnboardingQueryClient = Pick<SupabaseClient, "rpc">;

export class OnboardingQueryError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "OnboardingQueryError";
  }
}

function firstRow(data: unknown): Record<string, unknown> | null {
  const row = Array.isArray(data) ? data[0] : data;
  return row && typeof row === "object" ? (row as Record<string, unknown>) : null;
}

function rows(data: unknown): Record<string, unknown>[] {
  return (data as Record<string, unknown>[] | null) ?? [];
}

export async function listOnboardingChecklistTemplates(
  client: OnboardingQueryClient,
  tenantId: string,
  actorAuthUserId: string,
  options?: { caseTypeFilter?: CaseType | null },
): Promise<TemplateListRow[]> {
  const { data, error } = await client.rpc("list_onboarding_checklist_templates", {
    p_tenant_id: tenantId,
    p_actor_auth_user_id: actorAuthUserId,
    p_case_type_filter: options?.caseTypeFilter ?? null,
  });
  if (error) throw new OnboardingQueryError(error.message);
  return rows(data).map(parseTemplateListRow);
}

export async function getOnboardingChecklistTemplateVersion(
  client: OnboardingQueryClient,
  templateVersionId: string,
  actorAuthUserId: string,
): Promise<OnboardingChecklistTemplateTask[]> {
  const { data, error } = await client.rpc("get_onboarding_checklist_template_version", {
    p_template_version_id: templateVersionId,
    p_actor_auth_user_id: actorAuthUserId,
  });
  if (error) throw new OnboardingQueryError(error.message);
  return rows(data).map(parseOnboardingChecklistTemplateTask);
}

export async function previewOnboardingCaseStart(
  client: OnboardingQueryClient,
  input: { tenantId: string; caseType: string; sourceType: string; sourceJobOfferId: string | null; employeeMasterRecordId: string | null; actorAuthUserId: string },
): Promise<OnboardingCasePreview> {
  const { data, error } = await client.rpc("preview_onboarding_case_start", {
    p_tenant_id: input.tenantId,
    p_case_type: input.caseType,
    p_source_type: input.sourceType,
    p_source_job_offer_id: input.sourceJobOfferId,
    p_employee_master_record_id: input.employeeMasterRecordId,
    p_actor_auth_user_id: input.actorAuthUserId,
  });
  if (error) throw new OnboardingQueryError(error.message);
  const row = firstRow(data);
  if (!row) throw new OnboardingQueryError("preview_onboarding_case_start returned no row");
  return parseOnboardingCasePreview(row);
}

/** Server-filtered/searched, cursor-paginated (id-keyset) -- never a client-loaded full dataset. */
export async function listOnboardingCases(
  client: OnboardingQueryClient,
  tenantId: string,
  actorAuthUserId: string,
  options?: { caseTypeFilter?: CaseType | null; statusFilter?: CaseStatus | null; search?: string | null; limit?: number; afterId?: string | null },
): Promise<CaseListRow[]> {
  const { data, error } = await client.rpc("list_onboarding_cases", {
    p_tenant_id: tenantId,
    p_actor_auth_user_id: actorAuthUserId,
    p_case_type_filter: options?.caseTypeFilter ?? null,
    p_status_filter: options?.statusFilter ?? null,
    p_search: options?.search ?? null,
    p_limit: options?.limit ?? 50,
    p_after_id: options?.afterId ?? null,
  });
  if (error) throw new OnboardingQueryError(error.message);
  return rows(data).map(parseCaseListRow);
}

export async function getOnboardingCase(client: OnboardingQueryClient, caseId: string, actorAuthUserId: string): Promise<CaseDetail> {
  const { data, error } = await client.rpc("get_onboarding_case", { p_case_id: caseId, p_actor_auth_user_id: actorAuthUserId });
  if (error) throw new OnboardingQueryError(error.message);
  const row = firstRow(data);
  if (!row) throw new OnboardingQueryError("get_onboarding_case returned no row");
  return parseCaseDetail(row);
}

/** evidence_note/waive_reason masked (sensitiveMasked=true) unless the caller holds HRS:View personal data or is the task's own assigned owner (task-owner isolation, section 26). */
export async function listOnboardingCaseTasks(client: OnboardingQueryClient, caseId: string, actorAuthUserId: string): Promise<CaseTask[]> {
  const { data, error } = await client.rpc("list_onboarding_case_tasks", { p_case_id: caseId, p_actor_auth_user_id: actorAuthUserId });
  if (error) throw new OnboardingQueryError(error.message);
  return rows(data).map(parseCaseTask);
}

/** Zero rows (never throws) when the case has never been submitted for finalize approval yet. */
export async function getOnboardingCaseApprovalTimeline(client: OnboardingQueryClient, caseId: string, actorAuthUserId: string): Promise<ApprovalTimelineRow[]> {
  const { data, error } = await client.rpc("get_onboarding_case_approval_timeline", { p_case_id: caseId, p_actor_auth_user_id: actorAuthUserId });
  if (error) throw new OnboardingQueryError(error.message);
  return rows(data).map(parseApprovalTimelineRow);
}

/** Self-service, identity-match-gated -- never requires HRS:View. Returns only this actor's own not-yet-completed/waived assigned tasks. */
export async function listMyOnboardingTasks(client: OnboardingQueryClient, tenantId: string, actorAuthUserId: string): Promise<MyOnboardingTask[]> {
  const { data, error } = await client.rpc("list_my_onboarding_tasks", { p_tenant_id: tenantId, p_actor_auth_user_id: actorAuthUserId });
  if (error) throw new OnboardingQueryError(error.message);
  return rows(data).map(parseMyOnboardingTask);
}

/** The scoped export projection (section 14 "read/report") -- carries no exit_reason/evidence_note/waive_reason column at all. */
export async function exportOnboardingCases(
  client: OnboardingQueryClient,
  tenantId: string,
  actorAuthUserId: string,
  options?: { statusFilter?: CaseStatus | null; limit?: number },
): Promise<CaseExportRow[]> {
  const { data, error } = await client.rpc("export_onboarding_cases", {
    p_tenant_id: tenantId,
    p_actor_auth_user_id: actorAuthUserId,
    p_status_filter: options?.statusFilter ?? null,
    p_limit: options?.limit ?? 500,
  });
  if (error) throw new OnboardingQueryError(error.message);
  return rows(data).map(parseCaseExportRow);
}

