/**
 * Onboarding and Offboarding contract (HRT-277, CG-S12-HRT-005). Mirrors
 * supabase/migrations/20260730880000_create_hris_onboarding_offboarding.sql's
 * checklist template/version/task/dependency, case, case-task, case-task-
 * dependency, and provisioning-request shapes and their RPCs. Follows the exact
 * directory convention HRT-274/275/276 established: Zod schemas here, list/read
 * projections in server/queries/onboarding.ts, RPC-calling mutation wrappers
 * with an enumerated error-code type in server/mutations/onboarding.ts.
 *
 * Per ADR-0023 Part B, app.start_onboarding_case is the governed candidate ->
 * employee -> Platform-user-readiness conversion this whole capability exists
 * for; app.request_onboarding_access_provisioning/revocation are the real
 * Platform-identity-authority writes (section 16) -- both reuse app.invite_user/
 * app.link_employee_user/app.assign_role/app.transition_user_status (PLT-107/
 * 110/111) directly, never a second mechanism.
 */

import { z } from "zod";

export const CASE_TYPES = ["onboarding", "offboarding", "transfer"] as const;
export const CaseTypeSchema = z.enum(CASE_TYPES);
export type CaseType = z.infer<typeof CaseTypeSchema>;

export const SOURCE_TYPES = ["job_offer", "direct_hire", "existing_employee"] as const;
export const SourceTypeSchema = z.enum(SOURCE_TYPES);
export type SourceType = z.infer<typeof SourceTypeSchema>;

export const CASE_STATUSES = ["draft", "active", "pending_finalize_approval", "finalized", "cancelled"] as const;
export const CaseStatusSchema = z.enum(CASE_STATUSES);
export type CaseStatus = z.infer<typeof CaseStatusSchema>;

export const TASK_TYPES = ["document", "access_provisioning", "access_revocation", "handoff", "generic"] as const;
export const TaskTypeSchema = z.enum(TASK_TYPES);
export type TaskType = z.infer<typeof TaskTypeSchema>;

export const HANDOFF_CATEGORIES = ["asset", "training", "payroll", "operations"] as const;
export const HandoffCategorySchema = z.enum(HANDOFF_CATEGORIES);
export type HandoffCategory = z.infer<typeof HandoffCategorySchema>;

export const OWNER_TYPES = ["hr", "manager", "employee", "it", "finance", "operations"] as const;
export const OwnerTypeSchema = z.enum(OWNER_TYPES);
export type OwnerType = z.infer<typeof OwnerTypeSchema>;

export const TASK_STATUSES = ["pending", "blocked", "in_progress", "completed", "waived", "reopened"] as const;
export const TaskStatusSchema = z.enum(TASK_STATUSES);
export type TaskStatus = z.infer<typeof TaskStatusSchema>;

export const TEMPLATE_STATUSES = ["active", "archived"] as const;
export const TemplateStatusSchema = z.enum(TEMPLATE_STATUSES);
export type TemplateStatus = z.infer<typeof TemplateStatusSchema>;

export const TEMPLATE_VERSION_STATUSES = ["draft", "published", "superseded"] as const;
export const TemplateVersionStatusSchema = z.enum(TEMPLATE_VERSION_STATUSES);
export type TemplateVersionStatus = z.infer<typeof TemplateVersionStatusSchema>;

export const APPROVAL_DECISIONS = ["approved", "rejected"] as const;
export const ApprovalDecisionSchema = z.enum(APPROVAL_DECISIONS);
export type ApprovalDecision = z.infer<typeof ApprovalDecisionSchema>;

// --- Core rows ---

export const OnboardingChecklistTemplateSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  code: z.string(),
  name: z.string(),
  caseType: CaseTypeSchema,
  status: TemplateStatusSchema,
  recordVersion: z.number().int().positive(),
  createdAt: z.string(),
  updatedAt: z.string(),
});
export type OnboardingChecklistTemplate = z.infer<typeof OnboardingChecklistTemplateSchema>;

export function parseOnboardingChecklistTemplate(row: Record<string, unknown>): OnboardingChecklistTemplate {
  return OnboardingChecklistTemplateSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    code: row.code,
    name: row.name,
    caseType: row.case_type,
    status: row.status,
    recordVersion: row.record_version,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  });
}

export const TemplateListRowSchema = z.object({
  id: z.string().uuid(),
  code: z.string(),
  name: z.string(),
  caseType: CaseTypeSchema,
  status: TemplateStatusSchema,
  publishedVersionId: z.string().uuid().nullable(),
  publishedVersionNumber: z.number().int().nullable(),
  recordVersion: z.number().int().positive(),
});
export type TemplateListRow = z.infer<typeof TemplateListRowSchema>;

export function parseTemplateListRow(row: Record<string, unknown>): TemplateListRow {
  return TemplateListRowSchema.parse({
    id: row.id,
    code: row.code,
    name: row.name,
    caseType: row.case_type,
    status: row.status,
    publishedVersionId: row.published_version_id ?? null,
    publishedVersionNumber: row.published_version_number ?? null,
    recordVersion: row.record_version,
  });
}

export const OnboardingChecklistTemplateVersionSchema = z.object({
  id: z.string().uuid(),
  templateId: z.string().uuid(),
  tenantId: z.string().uuid(),
  versionNumber: z.number().int().positive(),
  status: TemplateVersionStatusSchema,
  publishedAt: z.string().nullable(),
  publishedBy: z.string().nullable(),
  recordVersion: z.number().int().positive(),
  createdAt: z.string(),
  updatedAt: z.string(),
});
export type OnboardingChecklistTemplateVersion = z.infer<typeof OnboardingChecklistTemplateVersionSchema>;

export function parseOnboardingChecklistTemplateVersion(row: Record<string, unknown>): OnboardingChecklistTemplateVersion {
  return OnboardingChecklistTemplateVersionSchema.parse({
    id: row.id,
    templateId: row.template_id,
    tenantId: row.tenant_id,
    versionNumber: row.version_number,
    status: row.status,
    publishedAt: row.published_at ?? null,
    publishedBy: row.published_by ?? null,
    recordVersion: row.record_version,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  });
}

/**
 * app.get_onboarding_checklist_template_version's own projection -- one row per
 * task, LEFT JOINed from the version itself (a brand-new draft with zero tasks
 * yet still returns exactly one row, with every task_* field null, so the
 * caller always sees the version's own id/status/recordVersion).
 */
export const OnboardingChecklistTemplateTaskSchema = z.object({
  versionId: z.string().uuid(),
  templateId: z.string().uuid(),
  versionNumber: z.number().int(),
  status: TemplateVersionStatusSchema,
  versionRecordVersion: z.number().int().positive(),
  taskId: z.string().uuid().nullable(),
  taskKey: z.string().nullable(),
  title: z.string().nullable(),
  description: z.string().nullable(),
  taskType: TaskTypeSchema.nullable(),
  handoffCategory: HandoffCategorySchema.nullable(),
  ownerType: OwnerTypeSchema.nullable(),
  isMandatory: z.boolean().nullable(),
  slaDays: z.number().int().positive().nullable(),
  sortOrder: z.number().int().nullable(),
  dependsOnTaskKeys: z.array(z.string()),
});
export type OnboardingChecklistTemplateTask = z.infer<typeof OnboardingChecklistTemplateTaskSchema>;

export function parseOnboardingChecklistTemplateTask(row: Record<string, unknown>): OnboardingChecklistTemplateTask {
  return OnboardingChecklistTemplateTaskSchema.parse({
    versionId: row.id,
    templateId: row.template_id,
    versionNumber: row.version_number,
    status: row.status,
    versionRecordVersion: row.record_version,
    taskId: row.task_id ?? null,
    taskKey: row.task_key ?? null,
    title: row.title ?? null,
    description: row.description ?? null,
    taskType: row.task_type ?? null,
    handoffCategory: row.handoff_category ?? null,
    ownerType: row.owner_type ?? null,
    isMandatory: row.is_mandatory ?? null,
    slaDays: row.sla_days ?? null,
    sortOrder: row.sort_order ?? null,
    dependsOnTaskKeys: (row.depends_on_task_keys as string[] | null) ?? [],
  });
}

export const OnboardingCasePreviewSchema = z.object({
  wouldReuseExistingEmployee: z.boolean(),
  resolvedEmployeeMasterRecordId: z.string().uuid().nullable(),
  resolvedTemplateVersionId: z.string().uuid().nullable(),
  resolvedTemplateTaskCount: z.number().int().nonnegative(),
  offerStatus: z.string().nullable(),
  offerApplicationId: z.string().uuid().nullable(),
  candidateFullName: z.string().nullable(),
});
export type OnboardingCasePreview = z.infer<typeof OnboardingCasePreviewSchema>;

export function parseOnboardingCasePreview(row: Record<string, unknown>): OnboardingCasePreview {
  return OnboardingCasePreviewSchema.parse({
    wouldReuseExistingEmployee: row.would_reuse_existing_employee,
    resolvedEmployeeMasterRecordId: row.resolved_employee_master_record_id ?? null,
    resolvedTemplateVersionId: row.resolved_template_version_id ?? null,
    resolvedTemplateTaskCount: row.resolved_template_task_count,
    offerStatus: row.offer_status ?? null,
    offerApplicationId: row.offer_application_id ?? null,
    candidateFullName: row.candidate_full_name ?? null,
  });
}

export const OnboardingCaseSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  caseType: CaseTypeSchema,
  sourceType: SourceTypeSchema,
  sourceJobOfferId: z.string().uuid().nullable(),
  sourceJobApplicationId: z.string().uuid().nullable(),
  sourceCandidateId: z.string().uuid().nullable(),
  employeeMasterRecordId: z.string().uuid().nullable(),
  checklistTemplateVersionId: z.string().uuid().nullable(),
  status: CaseStatusSchema,
  effectiveDate: z.string().nullable(),
  initiatedBy: z.string().nullable(),
  initiatedAt: z.string(),
  finalizeApprovalRequestId: z.string().uuid().nullable(),
  finalizedAt: z.string().nullable(),
  finalizedBy: z.string().nullable(),
  cancelReason: z.string().nullable(),
  cancelledAt: z.string().nullable(),
  idempotencyKey: z.string().nullable(),
  recordVersion: z.number().int().positive(),
  createdBy: z.string().nullable(),
  createdAt: z.string(),
  updatedAt: z.string(),
});
export type OnboardingCase = z.infer<typeof OnboardingCaseSchema>;

export function parseOnboardingCase(row: Record<string, unknown>): OnboardingCase {
  return OnboardingCaseSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    caseType: row.case_type,
    sourceType: row.source_type,
    sourceJobOfferId: row.source_job_offer_id ?? null,
    sourceJobApplicationId: row.source_job_application_id ?? null,
    sourceCandidateId: row.source_candidate_id ?? null,
    employeeMasterRecordId: row.employee_master_record_id ?? null,
    checklistTemplateVersionId: row.checklist_template_version_id ?? null,
    status: row.status,
    effectiveDate: row.effective_date ?? null,
    initiatedBy: row.initiated_by ?? null,
    initiatedAt: row.initiated_at,
    finalizeApprovalRequestId: row.finalize_approval_request_id ?? null,
    finalizedAt: row.finalized_at ?? null,
    finalizedBy: row.finalized_by ?? null,
    cancelReason: row.cancel_reason ?? null,
    cancelledAt: row.cancelled_at ?? null,
    idempotencyKey: row.idempotency_key ?? null,
    recordVersion: row.record_version,
    createdBy: row.created_by ?? null,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  });
}

export const CaseListRowSchema = z.object({
  id: z.string().uuid(),
  caseType: CaseTypeSchema,
  sourceType: SourceTypeSchema,
  employeeMasterRecordId: z.string().uuid().nullable(),
  employeeFullName: z.string().nullable(),
  status: CaseStatusSchema,
  effectiveDate: z.string().nullable(),
  initiatedAt: z.string(),
  recordVersion: z.number().int().positive(),
});
export type CaseListRow = z.infer<typeof CaseListRowSchema>;

export function parseCaseListRow(row: Record<string, unknown>): CaseListRow {
  return CaseListRowSchema.parse({
    id: row.id,
    caseType: row.case_type,
    sourceType: row.source_type,
    employeeMasterRecordId: row.employee_master_record_id ?? null,
    employeeFullName: row.employee_full_name ?? null,
    status: row.status,
    effectiveDate: row.effective_date ?? null,
    initiatedAt: row.initiated_at,
    recordVersion: row.record_version,
  });
}

/** app.get_onboarding_case's own detail projection -- exit_reason is masked (with exitReasonMasked=true) unless the caller holds HRS:View personal data. */
export const CaseDetailSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  caseType: CaseTypeSchema,
  sourceType: SourceTypeSchema,
  sourceJobOfferId: z.string().uuid().nullable(),
  employeeMasterRecordId: z.string().uuid().nullable(),
  employeeFullName: z.string().nullable(),
  checklistTemplateVersionId: z.string().uuid().nullable(),
  status: CaseStatusSchema,
  effectiveDate: z.string().nullable(),
  initiatedBy: z.string().nullable(),
  initiatedAt: z.string(),
  finalizeApprovalRequestId: z.string().uuid().nullable(),
  finalizedAt: z.string().nullable(),
  cancelReason: z.string().nullable(),
  exitReason: z.string().nullable(),
  exitReasonMasked: z.boolean(),
  recordVersion: z.number().int().positive(),
});
export type CaseDetail = z.infer<typeof CaseDetailSchema>;

export function parseCaseDetail(row: Record<string, unknown>): CaseDetail {
  return CaseDetailSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    caseType: row.case_type,
    sourceType: row.source_type,
    sourceJobOfferId: row.source_job_offer_id ?? null,
    employeeMasterRecordId: row.employee_master_record_id ?? null,
    employeeFullName: row.employee_full_name ?? null,
    checklistTemplateVersionId: row.checklist_template_version_id ?? null,
    status: row.status,
    effectiveDate: row.effective_date ?? null,
    initiatedBy: row.initiated_by ?? null,
    initiatedAt: row.initiated_at,
    finalizeApprovalRequestId: row.finalize_approval_request_id ?? null,
    finalizedAt: row.finalized_at ?? null,
    cancelReason: row.cancel_reason ?? null,
    exitReason: row.exit_reason ?? null,
    exitReasonMasked: row.exit_reason_masked as boolean,
    recordVersion: row.record_version,
  });
}

/** app.list_onboarding_case_tasks' own projection -- evidence_note/waive_reason masked (with sensitiveMasked=true) unless the caller holds HRS:View personal data OR is the task's own assigned owner. */
export const CaseTaskSchema = z.object({
  id: z.string().uuid(),
  templateTaskKey: z.string(),
  title: z.string(),
  description: z.string().nullable(),
  taskType: TaskTypeSchema,
  handoffCategory: HandoffCategorySchema.nullable(),
  ownerType: OwnerTypeSchema,
  ownerAuthUserId: z.string().uuid().nullable(),
  isMandatory: z.boolean(),
  dueAt: z.string().nullable(),
  isOverdue: z.boolean(),
  sortOrder: z.number().int(),
  status: TaskStatusSchema,
  completedAt: z.string().nullable(),
  waivedAt: z.string().nullable(),
  waiveReason: z.string().nullable(),
  evidenceNote: z.string().nullable(),
  evidenceFileId: z.string().uuid().nullable(),
  sensitiveMasked: z.boolean(),
  dependsOnTaskIds: z.array(z.string().uuid()),
  recordVersion: z.number().int().positive(),
});
export type CaseTask = z.infer<typeof CaseTaskSchema>;

export function parseCaseTask(row: Record<string, unknown>): CaseTask {
  return CaseTaskSchema.parse({
    id: row.id,
    templateTaskKey: row.template_task_key,
    title: row.title,
    description: row.description ?? null,
    taskType: row.task_type,
    handoffCategory: row.handoff_category ?? null,
    ownerType: row.owner_type,
    ownerAuthUserId: row.owner_auth_user_id ?? null,
    isMandatory: row.is_mandatory,
    dueAt: row.due_at ?? null,
    isOverdue: row.is_overdue,
    sortOrder: row.sort_order,
    status: row.status,
    completedAt: row.completed_at ?? null,
    waivedAt: row.waived_at ?? null,
    waiveReason: row.waive_reason ?? null,
    evidenceNote: row.evidence_note ?? null,
    evidenceFileId: row.evidence_file_id ?? null,
    sensitiveMasked: row.sensitive_masked as boolean,
    dependsOnTaskIds: (row.depends_on_task_ids as string[] | null) ?? [],
    recordVersion: row.record_version,
  });
}

/** app.list_my_onboarding_tasks' own self-service projection (task-owner isolation, section 26). */
export const MyOnboardingTaskSchema = z.object({
  id: z.string().uuid(),
  caseId: z.string().uuid(),
  templateTaskKey: z.string(),
  title: z.string(),
  taskType: TaskTypeSchema,
  handoffCategory: HandoffCategorySchema.nullable(),
  dueAt: z.string().nullable(),
  isOverdue: z.boolean(),
  status: TaskStatusSchema,
  recordVersion: z.number().int().positive(),
});
export type MyOnboardingTask = z.infer<typeof MyOnboardingTaskSchema>;

export function parseMyOnboardingTask(row: Record<string, unknown>): MyOnboardingTask {
  return MyOnboardingTaskSchema.parse({
    id: row.id,
    caseId: row.case_id,
    templateTaskKey: row.template_task_key,
    title: row.title,
    taskType: row.task_type,
    handoffCategory: row.handoff_category ?? null,
    dueAt: row.due_at ?? null,
    isOverdue: row.is_overdue,
    status: row.status,
    recordVersion: row.record_version,
  });
}

/** app.get_onboarding_case_approval_timeline's own projection (section 15 "approval timeline"). */
export const ApprovalTimelineRowSchema = z.object({
  stepId: z.string().uuid(),
  stepOrder: z.number().int(),
  approverType: z.string(),
  stepStatus: z.string(),
  decisionId: z.string().uuid().nullable(),
  actorAuthUserId: z.string().uuid().nullable(),
  actorLabel: z.string().nullable(),
  decision: z.string().nullable(),
  reason: z.string().nullable(),
  decidedAt: z.string().nullable(),
});
export type ApprovalTimelineRow = z.infer<typeof ApprovalTimelineRowSchema>;

export function parseApprovalTimelineRow(row: Record<string, unknown>): ApprovalTimelineRow {
  return ApprovalTimelineRowSchema.parse({
    stepId: row.step_id,
    stepOrder: row.step_order,
    approverType: row.approver_type,
    stepStatus: row.step_status,
    decisionId: row.decision_id ?? null,
    actorAuthUserId: row.actor_auth_user_id ?? null,
    actorLabel: row.actor_label ?? null,
    decision: row.decision ?? null,
    reason: row.reason ?? null,
    decidedAt: row.decided_at ?? null,
  });
}

export const CaseExportRowSchema = z.object({
  caseType: CaseTypeSchema,
  sourceType: SourceTypeSchema,
  employeeFullName: z.string().nullable(),
  status: CaseStatusSchema,
  effectiveDate: z.string().nullable(),
  initiatedAt: z.string(),
});
export type CaseExportRow = z.infer<typeof CaseExportRowSchema>;

export function parseCaseExportRow(row: Record<string, unknown>): CaseExportRow {
  return CaseExportRowSchema.parse({
    caseType: row.case_type,
    sourceType: row.source_type,
    employeeFullName: row.employee_full_name ?? null,
    status: row.status,
    effectiveDate: row.effective_date ?? null,
    initiatedAt: row.initiated_at,
  });
}

// --- Mutation input schemas ---

const ActorFieldsSchema = z.object({ actorAuthUserId: z.string().uuid(), actorLabel: z.string() });

export const CreateOnboardingChecklistTemplateInputSchema = z
  .object({ tenantId: z.string().uuid(), code: z.string().min(1), name: z.string().min(1), caseType: CaseTypeSchema })
  .merge(ActorFieldsSchema);
export type CreateOnboardingChecklistTemplateInput = z.input<typeof CreateOnboardingChecklistTemplateInputSchema>;

export const CreateOnboardingChecklistTemplateVersionInputSchema = z.object({ templateId: z.string().uuid() }).merge(ActorFieldsSchema);
export type CreateOnboardingChecklistTemplateVersionInput = z.input<typeof CreateOnboardingChecklistTemplateVersionInputSchema>;

export const AddOnboardingChecklistTemplateTaskInputSchema = z
  .object({
    templateVersionId: z.string().uuid(),
    taskKey: z.string().regex(/^[a-z0-9_-]{2,64}$/),
    title: z.string().min(1),
    description: z.string().nullable(),
    taskType: TaskTypeSchema,
    handoffCategory: HandoffCategorySchema.nullable(),
    ownerType: OwnerTypeSchema,
    isMandatory: z.boolean(),
    slaDays: z.number().int().positive(),
    sortOrder: z.number().int(),
  })
  .merge(ActorFieldsSchema);
export type AddOnboardingChecklistTemplateTaskInput = z.input<typeof AddOnboardingChecklistTemplateTaskInputSchema>;

export const AddOnboardingChecklistTemplateTaskDependencyInputSchema = z
  .object({ templateVersionId: z.string().uuid(), taskKey: z.string(), dependsOnTaskKey: z.string() })
  .merge(ActorFieldsSchema);
export type AddOnboardingChecklistTemplateTaskDependencyInput = z.input<typeof AddOnboardingChecklistTemplateTaskDependencyInputSchema>;

export const PublishOnboardingChecklistTemplateVersionInputSchema = z
  .object({ templateVersionId: z.string().uuid(), expectedVersion: z.number().int().positive() })
  .merge(ActorFieldsSchema);
export type PublishOnboardingChecklistTemplateVersionInput = z.input<typeof PublishOnboardingChecklistTemplateVersionInputSchema>;

export const StartOnboardingCaseInputSchema = z
  .object({
    tenantId: z.string().uuid(),
    caseType: CaseTypeSchema,
    sourceType: SourceTypeSchema,
    sourceJobOfferId: z.string().uuid().nullable(),
    employeeMasterRecordId: z.string().uuid().nullable(),
    checklistTemplateVersionId: z.string().uuid().nullable(),
    effectiveDate: z.string().nullable(),
    fullName: z.string().nullable(),
    employmentType: z.string().nullable(),
    workEmail: z.string().nullable(),
    personalEmail: z.string().nullable(),
    personalPhone: z.string().nullable(),
    nationalIdNumber: z.string().nullable(),
    dateOfBirth: z.string().nullable(),
    gender: z.string().nullable(),
    companyOrgUnitId: z.string().uuid().nullable(),
    branchOrgUnitId: z.string().uuid().nullable(),
    departmentOrgUnitId: z.string().uuid().nullable(),
    positionTitle: z.string().nullable(),
    managerEmployeeId: z.string().uuid().nullable(),
    idempotencyKey: z.string().nullable(),
  })
  .merge(ActorFieldsSchema);
export type StartOnboardingCaseInput = z.input<typeof StartOnboardingCaseInputSchema>;

export const AssignOnboardingTaskInputSchema = z
  .object({ caseId: z.string().uuid(), taskId: z.string().uuid(), expectedVersion: z.number().int().positive(), ownerAuthUserId: z.string().uuid().nullable() })
  .merge(ActorFieldsSchema);
export type AssignOnboardingTaskInput = z.input<typeof AssignOnboardingTaskInputSchema>;

export const CompleteOnboardingTaskInputSchema = z
  .object({ caseId: z.string().uuid(), taskId: z.string().uuid(), expectedVersion: z.number().int().positive(), evidenceNote: z.string().nullable(), evidenceFileId: z.string().uuid().nullable() })
  .merge(ActorFieldsSchema);
export type CompleteOnboardingTaskInput = z.input<typeof CompleteOnboardingTaskInputSchema>;

export const WaiveOnboardingTaskInputSchema = z
  .object({ caseId: z.string().uuid(), taskId: z.string().uuid(), expectedVersion: z.number().int().positive(), waiveReason: z.string().min(1) })
  .merge(ActorFieldsSchema);
export type WaiveOnboardingTaskInput = z.input<typeof WaiveOnboardingTaskInputSchema>;

export const ReopenOnboardingTaskInputSchema = z
  .object({ caseId: z.string().uuid(), taskId: z.string().uuid(), expectedVersion: z.number().int().positive(), reason: z.string().min(1) })
  .merge(ActorFieldsSchema);
export type ReopenOnboardingTaskInput = z.input<typeof ReopenOnboardingTaskInputSchema>;

export const RequestOnboardingAccessProvisioningInputSchema = z
  .object({
    caseId: z.string().uuid(),
    taskId: z.string().uuid(),
    expectedVersion: z.number().int().positive(),
    targetAuthUserId: z.string().uuid().nullable(),
    roleVersionIds: z.array(z.string().uuid()),
    orgUnitId: z.string().uuid().nullable(),
  })
  .merge(ActorFieldsSchema);
export type RequestOnboardingAccessProvisioningInput = z.input<typeof RequestOnboardingAccessProvisioningInputSchema>;

export const RequestOnboardingAccessRevocationInputSchema = z
  .object({ caseId: z.string().uuid(), taskId: z.string().uuid(), expectedVersion: z.number().int().positive() })
  .merge(ActorFieldsSchema);
export type RequestOnboardingAccessRevocationInput = z.input<typeof RequestOnboardingAccessRevocationInputSchema>;

export const SubmitOnboardingCaseForFinalizeApprovalInputSchema = z
  .object({ caseId: z.string().uuid(), expectedVersion: z.number().int().positive(), exitReason: z.string().nullable() })
  .merge(ActorFieldsSchema);
export type SubmitOnboardingCaseForFinalizeApprovalInput = z.input<typeof SubmitOnboardingCaseForFinalizeApprovalInputSchema>;

export const DecideOnboardingCaseFinalizeApprovalInputSchema = z
  .object({ requestStepId: z.string().uuid(), decision: ApprovalDecisionSchema, reason: z.string().nullable() })
  .merge(ActorFieldsSchema);
export type DecideOnboardingCaseFinalizeApprovalInput = z.input<typeof DecideOnboardingCaseFinalizeApprovalInputSchema>;

export const CancelOnboardingCaseInputSchema = z
  .object({ caseId: z.string().uuid(), expectedVersion: z.number().int().positive(), reason: z.string().min(1) })
  .merge(ActorFieldsSchema);
export type CancelOnboardingCaseInput = z.input<typeof CancelOnboardingCaseInputSchema>;

export const RehireEmployeeInputSchema = z
  .object({ masterRecordId: z.string().uuid(), expectedVersion: z.number().int().positive(), reason: z.string().min(1) })
  .merge(ActorFieldsSchema);
export type RehireEmployeeInput = z.input<typeof RehireEmployeeInputSchema>;
