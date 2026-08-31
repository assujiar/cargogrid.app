/**
 * Onboarding and Offboarding mutation primitives (HRT-277, CG-S12-HRT-005). Thin,
 * typed wrappers around every write RPC in
 * supabase/migrations/20260730880000_create_hris_onboarding_offboarding.sql.
 *
 * app.request_onboarding_access_provisioning/revocation write through Platform
 * identity/access authority (app.invite_user/app.link_employee_user/
 * app.assign_role/app.transition_user_status, PLT-107/110/111) -- never a direct
 * app.users/app.role_assignments write from this domain.
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import {
  CreateOnboardingChecklistTemplateInputSchema,
  CreateOnboardingChecklistTemplateVersionInputSchema,
  AddOnboardingChecklistTemplateTaskInputSchema,
  AddOnboardingChecklistTemplateTaskDependencyInputSchema,
  PublishOnboardingChecklistTemplateVersionInputSchema,
  StartOnboardingCaseInputSchema,
  AssignOnboardingTaskInputSchema,
  CompleteOnboardingTaskInputSchema,
  WaiveOnboardingTaskInputSchema,
  ReopenOnboardingTaskInputSchema,
  RequestOnboardingAccessProvisioningInputSchema,
  RequestOnboardingAccessRevocationInputSchema,
  SubmitOnboardingCaseForFinalizeApprovalInputSchema,
  DecideOnboardingCaseFinalizeApprovalInputSchema,
  CancelOnboardingCaseInputSchema,
  RehireEmployeeInputSchema,
  parseOnboardingChecklistTemplate,
  parseOnboardingChecklistTemplateVersion,
  parseOnboardingCase,
  parseCaseTask,
  type CreateOnboardingChecklistTemplateInput,
  type CreateOnboardingChecklistTemplateVersionInput,
  type AddOnboardingChecklistTemplateTaskInput,
  type AddOnboardingChecklistTemplateTaskDependencyInput,
  type PublishOnboardingChecklistTemplateVersionInput,
  type StartOnboardingCaseInput,
  type AssignOnboardingTaskInput,
  type CompleteOnboardingTaskInput,
  type WaiveOnboardingTaskInput,
  type ReopenOnboardingTaskInput,
  type RequestOnboardingAccessProvisioningInput,
  type RequestOnboardingAccessRevocationInput,
  type SubmitOnboardingCaseForFinalizeApprovalInput,
  type DecideOnboardingCaseFinalizeApprovalInput,
  type CancelOnboardingCaseInput,
  type RehireEmployeeInput,
  type OnboardingChecklistTemplate,
  type OnboardingChecklistTemplateVersion,
  type OnboardingCase,
  type CaseTask,
} from "../contracts/onboarding/onboarding.ts";
import { resolveRequestClientIp } from "../../lib/security/client-ip.ts";

export type OnboardingMutationRpcClient = Pick<SupabaseClient, "rpc">;

export const ONBOARDING_KNOWN_MUTATION_ERROR_CODES = [
  "insufficient_authority",
  "insufficient_privilege",
  "invalid_case_type",
  "idempotency_key_conflict",
  "template_code_conflict",
  "template_not_found",
  "template_version_not_found",
  "invalid_transition",
  "task_key_conflict",
  "task_key_not_found",
  "dependency_cycle",
  "dependency_already_exists",
  "stale_version",
  "template_has_no_tasks",
  "source_job_offer_id_required",
  "invalid_source_type",
  "offer_not_found",
  "offer_not_accepted",
  "invalid_case_type_for_source",
  "invalid_full_name",
  "invalid_employment_type",
  "idempotency_key_required",
  "employee_master_record_id_required",
  "employee_not_found",
  "template_version_not_available",
  "template_case_type_mismatch",
  "no_published_checklist_template",
  "case_not_found",
  "case_not_active",
  "task_not_found",
  "owner_not_found",
  "wrong_completion_path",
  "task_blocked",
  "evidence_file_not_found",
  "evidence_file_infected",
  "evidence_file_not_scanned",
  "reason_required",
  "case_has_no_employee",
  "employee_already_linked",
  "mandatory_tasks_incomplete",
  "employee_not_active_yet",
  "employee_not_terminated_yet",
  "exit_reason_required",
  "approval_definition_not_configured",
  "approval_step_not_found",
  "not_an_onboarding_case_approval",
  "case_finalize_no_longer_applicable",
  "user_not_found",
  "invalid_response",
  // Tier C review-round fix pass (20260730890000):
  "evidence_required",
  "target_identity_not_activatable",
  "insufficient_authority_to_delegate",
] as const;
type KnownOnboardingMutationErrorCode = (typeof ONBOARDING_KNOWN_MUTATION_ERROR_CODES)[number];
export type OnboardingMutationErrorCode = KnownOnboardingMutationErrorCode | "mutation_failed";

export class OnboardingMutationError extends Error {
  readonly code: OnboardingMutationErrorCode;

  constructor(code: OnboardingMutationErrorCode, message: string) {
    super(message);
    this.name = "OnboardingMutationError";
    this.code = code;
  }
}

function classifyError(message: string): OnboardingMutationErrorCode {
  const prefix = message.split(":")[0]?.trim();
  return (ONBOARDING_KNOWN_MUTATION_ERROR_CODES as readonly string[]).includes(prefix ?? "") ? (prefix as KnownOnboardingMutationErrorCode) : "mutation_failed";
}

function firstRow(data: unknown): Record<string, unknown> | null {
  const row = Array.isArray(data) ? data[0] : data;
  return row && typeof row === "object" ? (row as Record<string, unknown>) : null;
}

// --- Checklist template authoring ---

export async function createOnboardingChecklistTemplate(client: OnboardingMutationRpcClient, input: CreateOnboardingChecklistTemplateInput): Promise<OnboardingChecklistTemplate> {
  const parsed = CreateOnboardingChecklistTemplateInputSchema.parse(input);
  const { data, error } = await client.rpc("create_onboarding_checklist_template", {
    p_tenant_id: parsed.tenantId,
    p_code: parsed.code,
    p_name: parsed.name,
    p_case_type: parsed.caseType,
    p_actor_auth_user_id: parsed.actorAuthUserId,
    p_actor_label: parsed.actorLabel,
  });
  if (error) throw new OnboardingMutationError(classifyError(error.message), error.message);
  const row = firstRow(data);
  if (!row) throw new OnboardingMutationError("invalid_response", "create_onboarding_checklist_template returned no row");
  return parseOnboardingChecklistTemplate(row);
}

export async function createOnboardingChecklistTemplateVersion(client: OnboardingMutationRpcClient, input: CreateOnboardingChecklistTemplateVersionInput): Promise<OnboardingChecklistTemplateVersion> {
  const parsed = CreateOnboardingChecklistTemplateVersionInputSchema.parse(input);
  const { data, error } = await client.rpc("create_onboarding_checklist_template_version", {
    p_template_id: parsed.templateId,
    p_actor_auth_user_id: parsed.actorAuthUserId,
    p_actor_label: parsed.actorLabel,
  });
  if (error) throw new OnboardingMutationError(classifyError(error.message), error.message);
  const row = firstRow(data);
  if (!row) throw new OnboardingMutationError("invalid_response", "create_onboarding_checklist_template_version returned no row");
  return parseOnboardingChecklistTemplateVersion(row);
}

export async function addOnboardingChecklistTemplateTask(client: OnboardingMutationRpcClient, input: AddOnboardingChecklistTemplateTaskInput): Promise<void> {
  const parsed = AddOnboardingChecklistTemplateTaskInputSchema.parse(input);
  const { error } = await client.rpc("add_onboarding_checklist_template_task", {
    p_template_version_id: parsed.templateVersionId,
    p_task_key: parsed.taskKey,
    p_title: parsed.title,
    p_description: parsed.description ?? null,
    p_task_type: parsed.taskType,
    p_handoff_category: parsed.handoffCategory ?? null,
    p_owner_type: parsed.ownerType,
    p_is_mandatory: parsed.isMandatory,
    p_sla_days: parsed.slaDays,
    p_sort_order: parsed.sortOrder,
    p_actor_auth_user_id: parsed.actorAuthUserId,
    p_actor_label: parsed.actorLabel,
  });
  if (error) throw new OnboardingMutationError(classifyError(error.message), error.message);
}

export async function addOnboardingChecklistTemplateTaskDependency(client: OnboardingMutationRpcClient, input: AddOnboardingChecklistTemplateTaskDependencyInput): Promise<void> {
  const parsed = AddOnboardingChecklistTemplateTaskDependencyInputSchema.parse(input);
  const { error } = await client.rpc("add_onboarding_checklist_template_task_dependency", {
    p_template_version_id: parsed.templateVersionId,
    p_task_key: parsed.taskKey,
    p_depends_on_task_key: parsed.dependsOnTaskKey,
    p_actor_auth_user_id: parsed.actorAuthUserId,
    p_actor_label: parsed.actorLabel,
  });
  if (error) throw new OnboardingMutationError(classifyError(error.message), error.message);
}

export async function publishOnboardingChecklistTemplateVersion(client: OnboardingMutationRpcClient, input: PublishOnboardingChecklistTemplateVersionInput): Promise<OnboardingChecklistTemplateVersion> {
  const parsed = PublishOnboardingChecklistTemplateVersionInputSchema.parse(input);
  const { data, error } = await client.rpc("publish_onboarding_checklist_template_version", {
    p_template_version_id: parsed.templateVersionId,
    p_expected_version: parsed.expectedVersion,
    p_actor_auth_user_id: parsed.actorAuthUserId,
    p_actor_label: parsed.actorLabel,
    // ISS-2026-302: read here rather than threaded through every caller -- a security
    // control a call site can forget to pass is not a control. Null outside a request.
    p_client_ip: await resolveRequestClientIp(),
  });
  if (error) throw new OnboardingMutationError(classifyError(error.message), error.message);
  const row = firstRow(data);
  if (!row) throw new OnboardingMutationError("invalid_response", "publish_onboarding_checklist_template_version returned no row");
  return parseOnboardingChecklistTemplateVersion(row);
}

// --- Case lifecycle ---

function parseCaseResponse(data: unknown, rpcName: string): OnboardingCase {
  const row = firstRow(data);
  if (!row) throw new OnboardingMutationError("invalid_response", `${rpcName} returned no row`);
  return parseOnboardingCase(row);
}

function parseTaskResponse(data: unknown, rpcName: string): CaseTask {
  const row = firstRow(data);
  if (!row) throw new OnboardingMutationError("invalid_response", `${rpcName} returned no row`);
  // app.onboarding_case_tasks' own row shape differs from app.list_onboarding_case_tasks'
  // masked read projection (no is_overdue/sensitive_masked/depends_on_task_ids computed
  // columns) -- normalize here so callers get one consistent CaseTask shape regardless
  // of whether it came from a write RPC or a read RPC.
  return parseCaseTask({
    ...row,
    is_overdue: row.due_at != null && new Date(row.due_at as string).getTime() < Date.now() && !["completed", "waived"].includes(row.status as string),
    sensitive_masked: false,
    depends_on_task_ids: [],
  });
}

export async function startOnboardingCase(client: OnboardingMutationRpcClient, input: StartOnboardingCaseInput): Promise<OnboardingCase> {
  const parsed = StartOnboardingCaseInputSchema.parse(input);
  const { data, error } = await client.rpc("start_onboarding_case", {
    p_tenant_id: parsed.tenantId,
    p_case_type: parsed.caseType,
    p_source_type: parsed.sourceType,
    p_source_job_offer_id: parsed.sourceJobOfferId ?? null,
    p_employee_master_record_id: parsed.employeeMasterRecordId ?? null,
    p_checklist_template_version_id: parsed.checklistTemplateVersionId ?? null,
    p_effective_date: parsed.effectiveDate ?? null,
    p_full_name: parsed.fullName ?? null,
    p_employment_type: parsed.employmentType ?? null,
    p_work_email: parsed.workEmail ?? null,
    p_personal_email: parsed.personalEmail ?? null,
    p_personal_phone: parsed.personalPhone ?? null,
    p_national_id_number: parsed.nationalIdNumber ?? null,
    p_date_of_birth: parsed.dateOfBirth ?? null,
    p_gender: parsed.gender ?? null,
    p_company_org_unit_id: parsed.companyOrgUnitId ?? null,
    p_branch_org_unit_id: parsed.branchOrgUnitId ?? null,
    p_department_org_unit_id: parsed.departmentOrgUnitId ?? null,
    p_position_title: parsed.positionTitle ?? null,
    p_manager_employee_id: parsed.managerEmployeeId ?? null,
    p_idempotency_key: parsed.idempotencyKey ?? null,
    p_actor_auth_user_id: parsed.actorAuthUserId,
    p_actor_label: parsed.actorLabel,
  });
  if (error) throw new OnboardingMutationError(classifyError(error.message), error.message);
  return parseCaseResponse(data, "start_onboarding_case");
}

export async function assignOnboardingTask(client: OnboardingMutationRpcClient, input: AssignOnboardingTaskInput): Promise<CaseTask> {
  const parsed = AssignOnboardingTaskInputSchema.parse(input);
  const { data, error } = await client.rpc("assign_onboarding_task", {
    p_case_id: parsed.caseId,
    p_task_id: parsed.taskId,
    p_expected_version: parsed.expectedVersion,
    p_owner_auth_user_id: parsed.ownerAuthUserId ?? null,
    p_actor_auth_user_id: parsed.actorAuthUserId,
    p_actor_label: parsed.actorLabel,
  });
  if (error) throw new OnboardingMutationError(classifyError(error.message), error.message);
  return parseTaskResponse(data, "assign_onboarding_task");
}

export async function completeOnboardingTask(client: OnboardingMutationRpcClient, input: CompleteOnboardingTaskInput): Promise<CaseTask> {
  const parsed = CompleteOnboardingTaskInputSchema.parse(input);
  const { data, error } = await client.rpc("complete_onboarding_task", {
    p_case_id: parsed.caseId,
    p_task_id: parsed.taskId,
    p_expected_version: parsed.expectedVersion,
    p_evidence_note: parsed.evidenceNote ?? null,
    p_evidence_file_id: parsed.evidenceFileId ?? null,
    p_actor_auth_user_id: parsed.actorAuthUserId,
    p_actor_label: parsed.actorLabel,
  });
  if (error) throw new OnboardingMutationError(classifyError(error.message), error.message);
  return parseTaskResponse(data, "complete_onboarding_task");
}

export async function waiveOnboardingTask(client: OnboardingMutationRpcClient, input: WaiveOnboardingTaskInput): Promise<CaseTask> {
  const parsed = WaiveOnboardingTaskInputSchema.parse(input);
  const { data, error } = await client.rpc("waive_onboarding_task", {
    p_case_id: parsed.caseId,
    p_task_id: parsed.taskId,
    p_expected_version: parsed.expectedVersion,
    p_waive_reason: parsed.waiveReason,
    p_actor_auth_user_id: parsed.actorAuthUserId,
    p_actor_label: parsed.actorLabel,
  });
  if (error) throw new OnboardingMutationError(classifyError(error.message), error.message);
  return parseTaskResponse(data, "waive_onboarding_task");
}

export async function reopenOnboardingTask(client: OnboardingMutationRpcClient, input: ReopenOnboardingTaskInput): Promise<CaseTask> {
  const parsed = ReopenOnboardingTaskInputSchema.parse(input);
  const { data, error } = await client.rpc("reopen_onboarding_task", {
    p_case_id: parsed.caseId,
    p_task_id: parsed.taskId,
    p_expected_version: parsed.expectedVersion,
    p_reason: parsed.reason,
    p_actor_auth_user_id: parsed.actorAuthUserId,
    p_actor_label: parsed.actorLabel,
  });
  if (error) throw new OnboardingMutationError(classifyError(error.message), error.message);
  return parseTaskResponse(data, "reopen_onboarding_task");
}

/** The real Platform-identity-authority grant (section 16). When targetAuthUserId is supplied, performs a real synchronous grant; otherwise records the request and leaves the task in_progress (section 22 "preboarding without user access"). */
export async function requestOnboardingAccessProvisioning(client: OnboardingMutationRpcClient, input: RequestOnboardingAccessProvisioningInput): Promise<CaseTask> {
  const parsed = RequestOnboardingAccessProvisioningInputSchema.parse(input);
  const { data, error } = await client.rpc("request_onboarding_access_provisioning", {
    p_case_id: parsed.caseId,
    p_task_id: parsed.taskId,
    p_expected_version: parsed.expectedVersion,
    p_target_auth_user_id: parsed.targetAuthUserId ?? null,
    p_role_version_ids: parsed.roleVersionIds,
    p_org_unit_id: parsed.orgUnitId ?? null,
    p_actor_auth_user_id: parsed.actorAuthUserId,
    p_actor_label: parsed.actorLabel,
  });
  if (error) throw new OnboardingMutationError(classifyError(error.message), error.message);
  return parseTaskResponse(data, "request_onboarding_access_provisioning");
}

/** The real Platform-identity-authority revoke (section 16/24). Reuses app.transition_user_status directly. */
export async function requestOnboardingAccessRevocation(client: OnboardingMutationRpcClient, input: RequestOnboardingAccessRevocationInput): Promise<CaseTask> {
  const parsed = RequestOnboardingAccessRevocationInputSchema.parse(input);
  const { data, error } = await client.rpc("request_onboarding_access_revocation", {
    p_case_id: parsed.caseId,
    p_task_id: parsed.taskId,
    p_expected_version: parsed.expectedVersion,
    p_reason: parsed.reason,
    p_actor_auth_user_id: parsed.actorAuthUserId,
    p_actor_label: parsed.actorLabel,
  });
  if (error) throw new OnboardingMutationError(classifyError(error.message), error.message);
  return parseTaskResponse(data, "request_onboarding_access_revocation");
}

export async function submitOnboardingCaseForFinalizeApproval(client: OnboardingMutationRpcClient, input: SubmitOnboardingCaseForFinalizeApprovalInput): Promise<OnboardingCase> {
  const parsed = SubmitOnboardingCaseForFinalizeApprovalInputSchema.parse(input);
  const { data, error } = await client.rpc("submit_onboarding_case_for_finalize_approval", {
    p_case_id: parsed.caseId,
    p_expected_version: parsed.expectedVersion,
    p_exit_reason: parsed.exitReason ?? null,
    p_actor_auth_user_id: parsed.actorAuthUserId,
    p_actor_label: parsed.actorLabel,
  });
  if (error) throw new OnboardingMutationError(classifyError(error.message), error.message);
  return parseCaseResponse(data, "submit_onboarding_case_for_finalize_approval");
}

export async function decideOnboardingCaseFinalizeApproval(client: OnboardingMutationRpcClient, input: DecideOnboardingCaseFinalizeApprovalInput): Promise<OnboardingCase> {
  const parsed = DecideOnboardingCaseFinalizeApprovalInputSchema.parse(input);
  const { data, error } = await client.rpc("decide_onboarding_case_finalize_approval", {
    p_request_step_id: parsed.requestStepId,
    p_decision: parsed.decision,
    p_reason: parsed.reason ?? null,
    p_actor_auth_user_id: parsed.actorAuthUserId,
    p_actor_label: parsed.actorLabel,
  });
  if (error) throw new OnboardingMutationError(classifyError(error.message), error.message);
  return parseCaseResponse(data, "decide_onboarding_case_finalize_approval");
}

export async function cancelOnboardingCase(client: OnboardingMutationRpcClient, input: CancelOnboardingCaseInput): Promise<OnboardingCase> {
  const parsed = CancelOnboardingCaseInputSchema.parse(input);
  const { data, error } = await client.rpc("cancel_onboarding_case", {
    p_case_id: parsed.caseId,
    p_expected_version: parsed.expectedVersion,
    p_reason: parsed.reason,
    p_actor_auth_user_id: parsed.actorAuthUserId,
    p_actor_label: parsed.actorLabel,
  });
  if (error) throw new OnboardingMutationError(classifyError(error.message), error.message);
  return parseCaseResponse(data, "cancel_onboarding_case");
}

/** HRT-277 decision 2: the genuinely new terminated -> active employee-lifecycle transition app.reactivate_employee (HRT-274) cannot perform (that RPC only restores from suspended). Archived stays terminal. */
export async function rehireEmployee(client: OnboardingMutationRpcClient, input: RehireEmployeeInput): Promise<void> {
  const parsed = RehireEmployeeInputSchema.parse(input);
  const { error } = await client.rpc("rehire_employee", {
    p_master_record_id: parsed.masterRecordId,
    p_expected_version: parsed.expectedVersion,
    p_reason: parsed.reason,
    p_actor_auth_user_id: parsed.actorAuthUserId,
    p_actor_label: parsed.actorLabel,
  });
  if (error) throw new OnboardingMutationError(classifyError(error.message), error.message);
}
