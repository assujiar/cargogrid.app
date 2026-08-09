import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  startOnboardingCase,
  completeOnboardingTask,
  waiveOnboardingTask,
  requestOnboardingAccessProvisioning,
  requestOnboardingAccessRevocation,
  submitOnboardingCaseForFinalizeApproval,
  cancelOnboardingCase,
  rehireEmployee,
  createOnboardingChecklistTemplate,
  publishOnboardingChecklistTemplateVersion,
  OnboardingMutationError,
  type OnboardingMutationRpcClient,
} from "./onboarding.ts";

const TENANT_ID = "123e4567-e89b-12d3-a456-426614174000";
const ID_1 = "223e4567-e89b-12d3-a456-426614174000";
const ID_2 = "323e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "423e4567-e89b-12d3-a456-426614174000";

function fakeClient(response: { data: unknown; error: { message: string } | null }): { client: OnboardingMutationRpcClient; calls: { fn: string; args: Record<string, unknown> }[] } {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];
  const client = {
    async rpc(fn: string, args: Record<string, unknown>) {
      calls.push({ fn, args });
      return response;
    },
  } as unknown as OnboardingMutationRpcClient;
  return { client, calls };
}

const CASE_ROW = {
  id: ID_1, tenant_id: TENANT_ID, case_type: "onboarding", source_type: "job_offer", source_job_offer_id: ID_2,
  source_job_application_id: null, source_candidate_id: null, employee_master_record_id: ID_2,
  checklist_template_version_id: ID_1, status: "active", effective_date: null, initiated_by: "hr",
  initiated_at: "2026-08-09T00:00:00.000Z", finalize_approval_request_id: null, finalized_at: null,
  finalized_by: null, cancel_reason: null, cancelled_at: null, idempotency_key: null, record_version: 1,
  created_by: "hr", created_at: "2026-08-09T00:00:00.000Z", updated_at: "2026-08-09T00:00:00.000Z",
};

const TASK_ROW = {
  id: ID_1, case_id: ID_2, tenant_id: TENANT_ID, template_task_key: "welcome-doc", title: "Sign welcome document",
  description: null, task_type: "document", handoff_category: null, owner_type: "employee", owner_auth_user_id: null,
  is_mandatory: true, due_at: null, sort_order: 1, status: "completed", completed_at: "2026-08-09T00:00:00.000Z",
  completed_by: "hr", waived_at: null, waived_by: null, waive_reason: null, evidence_note: "signed",
  evidence_file_id: null, record_version: 2, created_at: "2026-08-09T00:00:00.000Z", updated_at: "2026-08-09T00:00:00.000Z",
};

describe("startOnboardingCase", () => {
  test("threads every field through to the RPC call", async () => {
    const { client, calls } = fakeClient({ data: [CASE_ROW], error: null });
    const result = await startOnboardingCase(client, {
      tenantId: TENANT_ID, caseType: "onboarding", sourceType: "job_offer", sourceJobOfferId: ID_2,
      employeeMasterRecordId: null, checklistTemplateVersionId: null, effectiveDate: null, fullName: null,
      employmentType: null, workEmail: null, personalEmail: null, personalPhone: null, nationalIdNumber: null,
      dateOfBirth: null, gender: null, companyOrgUnitId: null, branchOrgUnitId: null, departmentOrgUnitId: null,
      positionTitle: null, managerEmployeeId: null, idempotencyKey: null, actorAuthUserId: ACTOR_ID, actorLabel: "hr",
    });
    assert.equal(calls[0]?.fn, "start_onboarding_case");
    assert.equal(calls[0]?.args.p_source_job_offer_id, ID_2);
    assert.equal(result.status, "active");
  });

  test("classifies a named error prefix", async () => {
    const { client } = fakeClient({ data: null, error: { message: "offer_not_accepted: offer x is draft" } });
    await assert.rejects(
      () =>
        startOnboardingCase(client, {
          tenantId: TENANT_ID, caseType: "onboarding", sourceType: "job_offer", sourceJobOfferId: ID_2,
          employeeMasterRecordId: null, checklistTemplateVersionId: null, effectiveDate: null, fullName: null,
          employmentType: null, workEmail: null, personalEmail: null, personalPhone: null, nationalIdNumber: null,
          dateOfBirth: null, gender: null, companyOrgUnitId: null, branchOrgUnitId: null, departmentOrgUnitId: null,
          positionTitle: null, managerEmployeeId: null, idempotencyKey: null, actorAuthUserId: ACTOR_ID, actorLabel: "hr",
        }),
      (err: unknown) => err instanceof OnboardingMutationError && err.code === "offer_not_accepted",
    );
  });

  test("classifies an unrecognized error prefix as mutation_failed", async () => {
    const { client } = fakeClient({ data: null, error: { message: "some_unmapped_db_error: boom" } });
    await assert.rejects(
      () =>
        startOnboardingCase(client, {
          tenantId: TENANT_ID, caseType: "onboarding", sourceType: "job_offer", sourceJobOfferId: ID_2,
          employeeMasterRecordId: null, checklistTemplateVersionId: null, effectiveDate: null, fullName: null,
          employmentType: null, workEmail: null, personalEmail: null, personalPhone: null, nationalIdNumber: null,
          dateOfBirth: null, gender: null, companyOrgUnitId: null, branchOrgUnitId: null, departmentOrgUnitId: null,
          positionTitle: null, managerEmployeeId: null, idempotencyKey: null, actorAuthUserId: ACTOR_ID, actorLabel: "hr",
        }),
      (err: unknown) => err instanceof OnboardingMutationError && err.code === "mutation_failed",
    );
  });
});

describe("task lifecycle wrappers", () => {
  test("completeOnboardingTask normalizes the write-RPC row into a CaseTask shape", async () => {
    const { client } = fakeClient({ data: [TASK_ROW], error: null });
    const task = await completeOnboardingTask(client, { caseId: ID_2, taskId: ID_1, expectedVersion: 1, evidenceNote: "signed", evidenceFileId: null, actorAuthUserId: ACTOR_ID, actorLabel: "hr" });
    assert.equal(task.status, "completed");
    assert.equal(task.sensitiveMasked, false);
  });

  test("requestOnboardingAccessProvisioning rejects a malformed input at the schema layer", async () => {
    const { client } = fakeClient({ data: [], error: null });
    await assert.rejects(() =>
      // @ts-expect-error -- deliberately invalid input under test, proving the Zod schema (not merely TypeScript) rejects it at runtime
      // SUPPRESS(owner=hrt277-onboarding, reason=deliberate runtime-schema-validation test fixture, expires=NONE, adr=NONE)
      requestOnboardingAccessProvisioning(client, {}),
    );
  });
});

describe("requestOnboardingAccessProvisioning / requestOnboardingAccessRevocation", () => {
  test("provisioning threads a null targetAuthUserId and empty role list through unchanged", async () => {
    const { client, calls } = fakeClient({ data: [{ ...TASK_ROW, task_type: "access_provisioning", status: "in_progress" }], error: null });
    const task = await requestOnboardingAccessProvisioning(client, {
      caseId: ID_2, taskId: ID_1, expectedVersion: 1, targetAuthUserId: null, roleVersionIds: [], orgUnitId: null,
      actorAuthUserId: ACTOR_ID, actorLabel: "hr",
    });
    assert.equal(calls[0]?.args.p_target_auth_user_id, null);
    assert.equal(task.status, "in_progress");
  });

  test("revocation calls the real RPC and returns the completed task", async () => {
    const { client, calls } = fakeClient({ data: [{ ...TASK_ROW, task_type: "access_revocation" }], error: null });
    await requestOnboardingAccessRevocation(client, { caseId: ID_2, taskId: ID_1, expectedVersion: 1, actorAuthUserId: ACTOR_ID, actorLabel: "hr" });
    assert.equal(calls[0]?.fn, "request_onboarding_access_revocation");
  });
});

describe("submitOnboardingCaseForFinalizeApproval / cancelOnboardingCase / rehireEmployee", () => {
  test("submit passes exitReason through (or null for onboarding cases)", async () => {
    const { client, calls } = fakeClient({ data: [{ ...CASE_ROW, status: "pending_finalize_approval" }], error: null });
    await submitOnboardingCaseForFinalizeApproval(client, { caseId: ID_1, expectedVersion: 1, exitReason: null, actorAuthUserId: ACTOR_ID, actorLabel: "hr" });
    assert.equal(calls[0]?.args.p_exit_reason, null);
  });

  test("cancel requires a non-empty reason at the schema layer", async () => {
    const { client } = fakeClient({ data: [], error: null });
    await assert.rejects(() => cancelOnboardingCase(client, { caseId: ID_1, expectedVersion: 1, reason: "", actorAuthUserId: ACTOR_ID, actorLabel: "hr" }));
  });

  test("rehireEmployee calls the real RPC with a reason", async () => {
    const { client, calls } = fakeClient({ data: [{}], error: null });
    await rehireEmployee(client, { masterRecordId: ID_1, expectedVersion: 3, reason: "rejoining the team", actorAuthUserId: ACTOR_ID, actorLabel: "hr" });
    assert.equal(calls[0]?.fn, "rehire_employee");
    assert.equal(calls[0]?.args.p_reason, "rejoining the team");
  });
});

describe("template authoring wrappers", () => {
  test("createOnboardingChecklistTemplate parses the returned template row", async () => {
    const { client } = fakeClient({
      data: [{ id: ID_1, tenant_id: TENANT_ID, code: "ONB-STD", name: "Standard Onboarding", case_type: "onboarding", status: "active", record_version: 1, created_at: "2026-08-09T00:00:00.000Z", updated_at: "2026-08-09T00:00:00.000Z" }],
      error: null,
    });
    const template = await createOnboardingChecklistTemplate(client, { tenantId: TENANT_ID, code: "ONB-STD", name: "Standard Onboarding", caseType: "onboarding", actorAuthUserId: ACTOR_ID, actorLabel: "hr" });
    assert.equal(template.code, "ONB-STD");
  });

  test("publishOnboardingChecklistTemplateVersion classifies template_has_no_tasks", async () => {
    const { client } = fakeClient({ data: null, error: { message: "template_has_no_tasks: version x has no tasks to publish" } });
    await assert.rejects(
      () => publishOnboardingChecklistTemplateVersion(client, { templateVersionId: ID_1, expectedVersion: 1, actorAuthUserId: ACTOR_ID, actorLabel: "hr" }),
      (err: unknown) => err instanceof OnboardingMutationError && err.code === "template_has_no_tasks",
    );
  });
});
