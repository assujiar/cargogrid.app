import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  listTrainingCompetencies,
  listTrainingCourses,
  listTrainingCourseVersions,
  listTrainingSessions,
  getTrainingSession,
  listTrainingEnrollments,
  listMyTrainingEnrollments,
  listTrainingCertificates,
  listMyTrainingCertificates,
  getTrainingCertificate,
  listTrainingCertificateExpiryReminders,
  listTrainingDevelopmentPlans,
  listTalentReviewAssignments,
  listMyTalentReviewAssignments,
  getTalentReview,
  listTalentPools,
  listTalentPoolMembers,
  listSuccessionCandidates,
  reportTalentPoolDistributionByDepartment,
  TrainingTalentQueryError,
  type TrainingTalentQueryClient,
} from "./training-talent.ts";

const TENANT_ID = "123e4567-e89b-12d3-a456-426614174000";
const ID_1 = "223e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "423e4567-e89b-12d3-a456-426614174000";

function fakeClient(response: { data: unknown; error: { message: string } | null }): { client: TrainingTalentQueryClient; calls: { fn: string; args: Record<string, unknown> }[] } {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];
  const client = {
    async rpc(fn: string, args: Record<string, unknown>) {
      calls.push({ fn, args });
      return response;
    },
  } as unknown as TrainingTalentQueryClient;
  return { client, calls };
}

describe("catalogue reads", () => {
  test("listTrainingCompetencies forwards tenant and actor", async () => {
    const { client, calls } = fakeClient({ data: [], error: null });
    await listTrainingCompetencies(client, TENANT_ID, ACTOR_ID);
    assert.equal(calls[0]?.fn, "list_training_competencies");
    assert.equal(calls[0]?.args.p_tenant_id, TENANT_ID);
  });

  test("listTrainingCourses surfaces a mapped query error", async () => {
    const { client } = fakeClient({ data: null, error: { message: "insufficient_authority: x" } });
    await assert.rejects(() => listTrainingCourses(client, TENANT_ID, ACTOR_ID), TrainingTalentQueryError);
  });

  test("listTrainingCourseVersions forwards course_id", async () => {
    const { client, calls } = fakeClient({ data: [], error: null });
    await listTrainingCourseVersions(client, ID_1, ACTOR_ID);
    assert.equal(calls[0]?.args.p_course_id, ID_1);
  });
});

describe("session reads", () => {
  test("listTrainingSessions defaults course_id/status to null", async () => {
    const { client, calls } = fakeClient({ data: [], error: null });
    await listTrainingSessions(client, TENANT_ID, ACTOR_ID);
    assert.equal(calls[0]?.args.p_course_id, null);
    assert.equal(calls[0]?.args.p_status, null);
  });

  test("getTrainingSession returns null when no row is found", async () => {
    const { client } = fakeClient({ data: [], error: null });
    const result = await getTrainingSession(client, ID_1, ACTOR_ID);
    assert.equal(result, null);
  });

  test("getTrainingSession parses a single object response", async () => {
    const { client } = fakeClient({
      data: {
        id: ID_1, course_version_id: ID_1, provider_id: null, session_code: "sess_a", location: null, start_at: "2026-09-01T00:00:00Z",
        end_at: "2026-09-01T04:00:00Z", capacity: 10, status: "scheduled", record_version: 1,
      },
      error: null,
    });
    const result = await getTrainingSession(client, ID_1, ACTOR_ID);
    assert.equal(result?.sessionCode, "sess_a");
  });
});

describe("enrollment reads", () => {
  test("listTrainingEnrollments forwards every optional filter", async () => {
    const { client, calls } = fakeClient({ data: [], error: null });
    await listTrainingEnrollments(client, TENANT_ID, ACTOR_ID, ID_1, ID_1, "enrolled");
    assert.equal(calls[0]?.args.p_session_id, ID_1);
    assert.equal(calls[0]?.args.p_status, "enrolled");
  });

  test("listMyTrainingEnrollments never takes an employee_id parameter", async () => {
    const { client, calls } = fakeClient({ data: [], error: null });
    await listMyTrainingEnrollments(client, TENANT_ID, ACTOR_ID);
    assert.equal(Object.prototype.hasOwnProperty.call(calls[0]?.args, "p_employee_id"), false);
  });
});

describe("certificate reads", () => {
  test("listTrainingCertificates forwards tenant/actor/employee filter", async () => {
    const { client, calls } = fakeClient({ data: [], error: null });
    await listTrainingCertificates(client, TENANT_ID, ACTOR_ID, ID_1);
    assert.equal(calls[0]?.args.p_employee_id, ID_1);
  });

  test("listMyTrainingCertificates calls the self-service RPC", async () => {
    const { client, calls } = fakeClient({ data: [], error: null });
    await listMyTrainingCertificates(client, TENANT_ID, ACTOR_ID);
    assert.equal(calls[0]?.fn, "list_my_training_certificates");
  });

  test("getTrainingCertificate surfaces a mapped query error", async () => {
    const { client } = fakeClient({ data: null, error: { message: "training_certificate_not_found: x" } });
    await assert.rejects(() => getTrainingCertificate(client, ID_1, ACTOR_ID), TrainingTalentQueryError);
  });

  test("listTrainingCertificateExpiryReminders forwards employee filter", async () => {
    const { client, calls } = fakeClient({ data: [], error: null });
    await listTrainingCertificateExpiryReminders(client, TENANT_ID, ACTOR_ID, ID_1);
    assert.equal(calls[0]?.args.p_employee_id, ID_1);
  });
});

describe("development plan reads", () => {
  test("listTrainingDevelopmentPlans forwards employee filter", async () => {
    const { client, calls } = fakeClient({ data: [], error: null });
    await listTrainingDevelopmentPlans(client, TENANT_ID, ACTOR_ID, ID_1);
    assert.equal(calls[0]?.args.p_employee_id, ID_1);
  });
});

describe("restricted talent reads", () => {
  test("listTalentReviewAssignments forwards cycle_id", async () => {
    const { client, calls } = fakeClient({ data: [], error: null });
    await listTalentReviewAssignments(client, TENANT_ID, ACTOR_ID, ID_1);
    assert.equal(calls[0]?.args.p_cycle_id, ID_1);
  });

  test("listMyTalentReviewAssignments never takes an employee/reviewer id parameter -- self-resolved server-side", async () => {
    const { client, calls } = fakeClient({ data: [], error: null });
    await listMyTalentReviewAssignments(client, TENANT_ID, ACTOR_ID);
    assert.equal(Object.keys(calls[0]?.args ?? {}).length, 2);
  });

  test("getTalentReview returns null when no row is found", async () => {
    const { client } = fakeClient({ data: null, error: null });
    const result = await getTalentReview(client, ID_1, ACTOR_ID);
    assert.equal(result, null);
  });

  test("listTalentPools calls the HRS:Override-gated RPC and surfaces a denial", async () => {
    const { client } = fakeClient({ data: null, error: { message: "insufficient_authority: lacks HRS:Override" } });
    await assert.rejects(() => listTalentPools(client, TENANT_ID, ACTOR_ID), TrainingTalentQueryError);
  });

  test("listTalentPoolMembers forwards pool_id", async () => {
    const { client, calls } = fakeClient({ data: [], error: null });
    await listTalentPoolMembers(client, ID_1, ACTOR_ID);
    assert.equal(calls[0]?.args.p_pool_id, ID_1);
  });

  test("listSuccessionCandidates forwards position filter", async () => {
    const { client, calls } = fakeClient({ data: [], error: null });
    await listSuccessionCandidates(client, TENANT_ID, ACTOR_ID, ID_1);
    assert.equal(calls[0]?.args.p_position_id, ID_1);
  });
});

describe("reportTalentPoolDistributionByDepartment", () => {
  test("forwards pool_id and actor_label, parses a suppressed row", async () => {
    const { client, calls } = fakeClient({ data: [{ department_org_unit_id: ID_1, department_name: "Small Dept", member_count: null, suppressed: true }], error: null });
    const rows = await reportTalentPoolDistributionByDepartment(client, TENANT_ID, ID_1, ACTOR_ID, "talentadmin");
    assert.equal(calls[0]?.args.p_pool_id, ID_1);
    assert.equal(rows[0]?.suppressed, true);
    assert.equal(rows[0]?.memberCount, null);
  });
});
