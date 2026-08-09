import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  parseOnboardingChecklistTemplate,
  parseOnboardingChecklistTemplateVersion,
  parseOnboardingChecklistTemplateTask,
  parseOnboardingCasePreview,
  parseOnboardingCase,
  parseCaseListRow,
  parseCaseDetail,
  parseCaseTask,
  parseMyOnboardingTask,
  parseApprovalTimelineRow,
  parseCaseExportRow,
  StartOnboardingCaseInputSchema,
  RequestOnboardingAccessProvisioningInputSchema,
  CompleteOnboardingTaskInputSchema,
} from "./onboarding.ts";

const TENANT_ID = "123e4567-e89b-12d3-a456-426614174000";
const ID_1 = "223e4567-e89b-12d3-a456-426614174000";
const ID_2 = "323e4567-e89b-12d3-a456-426614174000";
const ACTOR = "423e4567-e89b-12d3-a456-426614174000";

describe("parseOnboardingChecklistTemplate / version / task", () => {
  test("template maps snake_case to camelCase", () => {
    const t = parseOnboardingChecklistTemplate({
      id: ID_1, tenant_id: TENANT_ID, code: "ONB-STD", name: "Standard Onboarding", case_type: "onboarding",
      status: "active", record_version: 1, created_at: "2026-08-09T00:00:00.000Z", updated_at: "2026-08-09T00:00:00.000Z",
    });
    assert.equal(t.caseType, "onboarding");
    assert.equal(t.code, "ONB-STD");
  });

  test("version maps nullable published fields", () => {
    const v = parseOnboardingChecklistTemplateVersion({
      id: ID_1, template_id: ID_2, tenant_id: TENANT_ID, version_number: 1, status: "draft",
      published_at: null, published_by: null, record_version: 1, created_at: "2026-08-09T00:00:00.000Z", updated_at: "2026-08-09T00:00:00.000Z",
    });
    assert.equal(v.status, "draft");
    assert.equal(v.publishedAt, null);
  });

  test("template task carries dependsOnTaskKeys defaulting to an empty array", () => {
    const t = parseOnboardingChecklistTemplateTask({
      id: ID_1, template_id: ID_2, version_number: 1, status: "published", record_version: 1, task_id: ID_2, task_key: "it-access",
      title: "Provision access", description: null, task_type: "access_provisioning", handoff_category: null,
      owner_type: "it", is_mandatory: true, sla_days: 2, sort_order: 2, depends_on_task_keys: null,
    });
    assert.deepEqual(t.dependsOnTaskKeys, []);
    assert.equal(t.taskType, "access_provisioning");
  });

  test("a task-less draft version row (LEFT JOIN, zero tasks yet) parses with every task_* field null", () => {
    const t = parseOnboardingChecklistTemplateTask({
      id: ID_1, template_id: ID_2, version_number: 1, status: "draft", record_version: 1, task_id: null, task_key: null,
      title: null, description: null, task_type: null, handoff_category: null, owner_type: null,
      is_mandatory: null, sla_days: null, sort_order: null, depends_on_task_keys: null,
    });
    assert.equal(t.taskId, null);
    assert.equal(t.versionRecordVersion, 1);
  });
});

describe("parseOnboardingCasePreview", () => {
  test("maps a real preview row", () => {
    const p = parseOnboardingCasePreview({
      would_reuse_existing_employee: false, resolved_employee_master_record_id: null,
      resolved_template_version_id: ID_1, resolved_template_task_count: 4,
      offer_status: "accepted", offer_application_id: ID_2, candidate_full_name: "Ada Lovelace",
    });
    assert.equal(p.resolvedTemplateTaskCount, 4);
    assert.equal(p.candidateFullName, "Ada Lovelace");
  });
});

describe("parseOnboardingCase / parseCaseListRow / parseCaseDetail", () => {
  test("parseOnboardingCase maps the full case row", () => {
    const c = parseOnboardingCase({
      id: ID_1, tenant_id: TENANT_ID, case_type: "onboarding", source_type: "job_offer",
      source_job_offer_id: ID_2, source_job_application_id: null, source_candidate_id: null,
      employee_master_record_id: ID_2, checklist_template_version_id: ID_1, status: "active",
      effective_date: "2026-09-01", initiated_by: "hr", initiated_at: "2026-08-09T00:00:00.000Z",
      finalize_approval_request_id: null, finalized_at: null, finalized_by: null, cancel_reason: null,
      cancelled_at: null, idempotency_key: null, record_version: 1, created_by: "hr",
      created_at: "2026-08-09T00:00:00.000Z", updated_at: "2026-08-09T00:00:00.000Z",
    });
    assert.equal(c.status, "active");
    assert.equal(c.sourceType, "job_offer");
  });

  test("parseCaseDetail carries exitReasonMasked", () => {
    const d = parseCaseDetail({
      id: ID_1, tenant_id: TENANT_ID, case_type: "offboarding", source_type: "existing_employee",
      source_job_offer_id: null, employee_master_record_id: ID_2, employee_full_name: "Jane Doe",
      checklist_template_version_id: ID_1, status: "pending_finalize_approval", effective_date: "2026-09-01",
      initiated_by: "hr", initiated_at: "2026-08-09T00:00:00.000Z", finalize_approval_request_id: ID_2,
      finalized_at: null, cancel_reason: null, exit_reason: null, exit_reason_masked: true, record_version: 1,
    });
    assert.equal(d.exitReasonMasked, true);
    assert.equal(d.exitReason, null);
  });
});

describe("parseCaseTask", () => {
  test("maps masking flags and dependsOnTaskIds", () => {
    const t = parseCaseTask({
      id: ID_1, template_task_key: "welcome-doc", title: "Sign welcome document", description: null,
      task_type: "document", handoff_category: null, owner_type: "employee", owner_auth_user_id: null,
      is_mandatory: true, due_at: null, is_overdue: false, sort_order: 1, status: "pending",
      completed_at: null, waived_at: null, waive_reason: null, evidence_note: null, evidence_file_id: null,
      sensitive_masked: false, depends_on_task_ids: [ID_2], record_version: 1,
    });
    assert.deepEqual(t.dependsOnTaskIds, [ID_2]);
    assert.equal(t.sensitiveMasked, false);
  });
});

describe("parseMyOnboardingTask / parseApprovalTimelineRow / parseCaseExportRow", () => {
  test("my task row", () => {
    const t = parseMyOnboardingTask({
      id: ID_1, case_id: ID_2, template_task_key: "return-asset", title: "Return laptop",
      task_type: "handoff", handoff_category: "asset", due_at: null, is_overdue: false, status: "pending", record_version: 1,
    });
    assert.equal(t.handoffCategory, "asset");
  });

  test("approval timeline row", () => {
    const r = parseApprovalTimelineRow({
      step_id: ID_1, step_order: 1, approver_type: "role", step_status: "approved", decision_id: ID_2,
      actor_auth_user_id: ACTOR, actor_label: "approver", decision: "approved", reason: null, decided_at: "2026-08-09T00:00:00.000Z",
    });
    assert.equal(r.decision, "approved");
  });

  test("export row carries no sensitive columns", () => {
    const r = parseCaseExportRow({
      case_type: "onboarding", source_type: "job_offer", employee_full_name: "Ada Lovelace",
      status: "finalized", effective_date: "2026-09-01", initiated_at: "2026-08-09T00:00:00.000Z",
    });
    assert.equal(r.employeeFullName, "Ada Lovelace");
    assert.equal((r as Record<string, unknown>).exitReason, undefined);
  });
});

describe("mutation input schemas", () => {
  test("StartOnboardingCaseInputSchema accepts a job_offer-sourced onboarding start", () => {
    const parsed = StartOnboardingCaseInputSchema.parse({
      tenantId: TENANT_ID, caseType: "onboarding", sourceType: "job_offer", sourceJobOfferId: ID_1,
      employeeMasterRecordId: null, checklistTemplateVersionId: null, effectiveDate: null, fullName: null,
      employmentType: null, workEmail: null, personalEmail: null, personalPhone: null, nationalIdNumber: null,
      dateOfBirth: null, gender: null, companyOrgUnitId: null, branchOrgUnitId: null, departmentOrgUnitId: null,
      positionTitle: null, managerEmployeeId: null, idempotencyKey: null, actorAuthUserId: ACTOR, actorLabel: "hr",
    });
    assert.equal(parsed.caseType, "onboarding");
  });

  test("RequestOnboardingAccessProvisioningInputSchema accepts a null targetAuthUserId (unresolved-identity path)", () => {
    const parsed = RequestOnboardingAccessProvisioningInputSchema.parse({
      caseId: ID_1, taskId: ID_2, expectedVersion: 1, targetAuthUserId: null, roleVersionIds: [],
      orgUnitId: null, actorAuthUserId: ACTOR, actorLabel: "hr",
    });
    assert.equal(parsed.targetAuthUserId, null);
    assert.deepEqual(parsed.roleVersionIds, []);
  });

  test("CompleteOnboardingTaskInputSchema rejects a non-positive expectedVersion", () => {
    assert.throws(() =>
      CompleteOnboardingTaskInputSchema.parse({
        caseId: ID_1, taskId: ID_2, expectedVersion: 0, evidenceNote: null, evidenceFileId: null,
        actorAuthUserId: ACTOR, actorLabel: "hr",
      }),
    );
  });
});
