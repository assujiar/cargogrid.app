import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  listOnboardingChecklistTemplates,
  getOnboardingChecklistTemplateVersion,
  previewOnboardingCaseStart,
  listOnboardingCases,
  getOnboardingCase,
  listOnboardingCaseTasks,
  getOnboardingCaseApprovalTimeline,
  listMyOnboardingTasks,
  exportOnboardingCases,
  OnboardingQueryError,
  type OnboardingQueryClient,
} from "./onboarding.ts";

const TENANT_ID = "123e4567-e89b-12d3-a456-426614174000";
const ID_1 = "223e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "323e4567-e89b-12d3-a456-426614174000";

function fakeClient(response: { data: unknown; error: { message: string } | null }): { client: OnboardingQueryClient; calls: { fn: string; args: Record<string, unknown> }[] } {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];
  const client = {
    async rpc(fn: string, args: Record<string, unknown>) {
      calls.push({ fn, args });
      return response;
    },
  } as unknown as OnboardingQueryClient;
  return { client, calls };
}

describe("listOnboardingChecklistTemplates / getOnboardingChecklistTemplateVersion", () => {
  test("listOnboardingChecklistTemplates maps default args", async () => {
    const { client, calls } = fakeClient({ data: [], error: null });
    await listOnboardingChecklistTemplates(client, TENANT_ID, ACTOR_ID);
    assert.deepEqual(calls[0]?.args, { p_tenant_id: TENANT_ID, p_actor_auth_user_id: ACTOR_ID, p_case_type_filter: null });
  });

  test("getOnboardingChecklistTemplateVersion returns the parsed task rows", async () => {
    const { client } = fakeClient({
      data: [{ id: ID_1, template_id: ID_1, version_number: 1, status: "published", record_version: 1, task_id: ID_1, task_key: "welcome-doc", title: "Sign welcome document", description: null, task_type: "document", handoff_category: null, owner_type: "employee", is_mandatory: true, sla_days: 3, sort_order: 1, depends_on_task_keys: [] }],
      error: null,
    });
    const rows = await getOnboardingChecklistTemplateVersion(client, ID_1, ACTOR_ID);
    assert.equal(rows.length, 1);
    assert.equal(rows[0]?.taskKey, "welcome-doc");
  });
});

describe("previewOnboardingCaseStart", () => {
  test("throws OnboardingQueryError when the RPC returns no row", async () => {
    const { client } = fakeClient({ data: [], error: null });
    await assert.rejects(
      () => previewOnboardingCaseStart(client, { tenantId: TENANT_ID, caseType: "onboarding", sourceType: "job_offer", sourceJobOfferId: ID_1, employeeMasterRecordId: null, actorAuthUserId: ACTOR_ID }),
      OnboardingQueryError,
    );
  });
});

describe("listOnboardingCases / exportOnboardingCases", () => {
  test("listOnboardingCases caps limit and threads pagination cursor", async () => {
    const { client, calls } = fakeClient({ data: [], error: null });
    await listOnboardingCases(client, TENANT_ID, ACTOR_ID, { limit: 25, afterId: ID_1 });
    assert.equal(calls[0]?.args.p_limit, 25);
    assert.equal(calls[0]?.args.p_after_id, ID_1);
  });

  test("exportOnboardingCases defaults limit to 500", async () => {
    const { client, calls } = fakeClient({ data: [], error: null });
    await exportOnboardingCases(client, TENANT_ID, ACTOR_ID);
    assert.equal(calls[0]?.args.p_limit, 500);
  });
});

describe("getOnboardingCase / listOnboardingCaseTasks / getOnboardingCaseApprovalTimeline / listMyOnboardingTasks", () => {
  test("getOnboardingCase surfaces the masking flags unchanged", async () => {
    const { client } = fakeClient({
      data: [{ id: ID_1, tenant_id: TENANT_ID, case_type: "offboarding", source_type: "existing_employee", source_job_offer_id: null, employee_master_record_id: ID_1, employee_full_name: "Jane Doe", checklist_template_version_id: ID_1, status: "active", effective_date: null, initiated_by: "hr", initiated_at: "2026-08-09T00:00:00.000Z", finalize_approval_request_id: null, finalized_at: null, cancel_reason: null, exit_reason: null, exit_reason_masked: true, record_version: 1 }],
      error: null,
    });
    const detail = await getOnboardingCase(client, ID_1, ACTOR_ID);
    assert.equal(detail.exitReasonMasked, true);
  });

  test("listOnboardingCaseTasks passes through the caseId/actor pair", async () => {
    const { client, calls } = fakeClient({ data: [], error: null });
    await listOnboardingCaseTasks(client, ID_1, ACTOR_ID);
    assert.deepEqual(calls[0]?.args, { p_case_id: ID_1, p_actor_auth_user_id: ACTOR_ID });
  });

  test("getOnboardingCaseApprovalTimeline returns an empty array, never throws, for a never-submitted case", async () => {
    const { client } = fakeClient({ data: [], error: null });
    const rows = await getOnboardingCaseApprovalTimeline(client, ID_1, ACTOR_ID);
    assert.deepEqual(rows, []);
  });

  test("listMyOnboardingTasks is identity-scoped, never requires a status/case filter", async () => {
    const { client, calls } = fakeClient({ data: [], error: null });
    await listMyOnboardingTasks(client, TENANT_ID, ACTOR_ID);
    assert.deepEqual(calls[0]?.args, { p_tenant_id: TENANT_ID, p_actor_auth_user_id: ACTOR_ID });
  });
});
