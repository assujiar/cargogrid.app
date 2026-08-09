import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  createJobVacancyDraft,
  publishJobVacancy,
  createCandidate,
  applyToVacancy,
  transitionApplicationStage,
  submitInterviewFeedback,
  createJobOfferVersion,
  recordOfferResponse,
  submitPublicJobApplication,
  RecruitmentMutationError,
  type RecruitmentMutationRpcClient,
} from "./recruitment.ts";

const TENANT_ID = "123e4567-e89b-12d3-a456-426614174000";
const ID_1 = "223e4567-e89b-12d3-a456-426614174000";
const ID_2 = "323e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "423e4567-e89b-12d3-a456-426614174000";

function fakeRpcClient(response: { data: unknown; error: { message: string } | null }): { client: RecruitmentMutationRpcClient; calls: { fn: string; args: Record<string, unknown> }[] } {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];
  const client = {
    async rpc(fn: string, args: Record<string, unknown>) {
      calls.push({ fn, args });
      return response;
    },
  } as unknown as RecruitmentMutationRpcClient;
  return { client, calls };
}

const VACANCY_ROW = {
  id: ID_1,
  tenant_id: TENANT_ID,
  position_id: ID_2,
  title: "Software Engineer",
  employment_type: "full_time",
  headcount: 1,
  status: "draft",
  status_reason: null,
  description: null,
  requirements: null,
  hiring_manager_employee_id: null,
  owner_auth_user_id: null,
  record_version: 1,
  created_at: "2026-08-09T00:00:00.000Z",
  updated_at: "2026-08-09T00:00:00.000Z",
};

const APPLICATION_ROW = {
  id: ID_1,
  tenant_id: TENANT_ID,
  vacancy_id: ID_2,
  candidate_id: ID_2,
  stage: "new",
  source: "staff_created",
  applied_at: "2026-08-09T00:00:00.000Z",
  stage_since: "2026-08-09T00:00:00.000Z",
  rejection_reason: null,
  withdrawal_reason: null,
  record_version: 1,
  created_at: "2026-08-09T00:00:00.000Z",
  updated_at: "2026-08-09T00:00:00.000Z",
};

describe("recruitment mutation wrappers", () => {
  test("createJobVacancyDraft maps camelCase input to snake_case RPC args", async () => {
    const { client, calls } = fakeRpcClient({ data: [VACANCY_ROW], error: null });
    const vacancy = await createJobVacancyDraft(client, {
      tenantId: TENANT_ID,
      positionId: ID_2,
      title: "Software Engineer",
      employmentType: "full_time",
      headcount: 1,
      description: null,
      requirements: null,
      hiringManagerEmployeeId: null,
      idempotencyKey: "idem-1",
      actorAuthUserId: ACTOR_ID,
      actorLabel: "tester",
    });
    assert.equal(calls[0]?.fn, "create_job_vacancy_draft");
    assert.equal(calls[0]?.args.p_position_id, ID_2);
    assert.equal(calls[0]?.args.p_idempotency_key, "idem-1");
    assert.equal(vacancy.title, "Software Engineer");
  });

  test("publishJobVacancy parses the (vacancy, raw_posting_token, posting_expires_at) row", async () => {
    const { client } = fakeRpcClient({
      data: [{ vacancy: VACANCY_ROW, raw_posting_token: "a".repeat(64), posting_expires_at: "2026-09-08T00:00:00.000Z" }],
      error: null,
    });
    const result = await publishJobVacancy(client, { id: ID_1, expectedVersion: 1, validityDays: 30, actorAuthUserId: ACTOR_ID, actorLabel: "tester" });
    assert.equal(result.rawPostingToken.length, 64);
    assert.equal(result.vacancy.id, ID_1);
  });

  test("createCandidate throws a classified RecruitmentMutationError on a known error prefix", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "referral_employee_required: source=referral requires a referring employee" } });
    await assert.rejects(
      () =>
        createCandidate(client, {
          tenantId: TENANT_ID,
          fullName: "Ada Lovelace",
          email: "ada@example.test",
          phone: null,
          source: "referral",
          referralEmployeeId: null,
          idempotencyKey: null,
          actorAuthUserId: ACTOR_ID,
          actorLabel: "tester",
        }),
      (error: unknown) => {
        assert.ok(error instanceof RecruitmentMutationError);
        assert.equal(error.code, "referral_employee_required");
        return true;
      },
    );
  });

  test("createCandidate classifies an unrecognized error message as mutation_failed", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "some_unexpected_driver_error: boom" } });
    await assert.rejects(
      () =>
        createCandidate(client, {
          tenantId: TENANT_ID,
          fullName: "Ada Lovelace",
          email: "ada@example.test",
          phone: null,
          source: "staff_created",
          referralEmployeeId: null,
          idempotencyKey: null,
          actorAuthUserId: ACTOR_ID,
          actorLabel: "tester",
        }),
      (error: unknown) => {
        assert.ok(error instanceof RecruitmentMutationError);
        assert.equal(error.code, "mutation_failed");
        return true;
      },
    );
  });

  test("applyToVacancy passes idempotencyKey through", async () => {
    const { client, calls } = fakeRpcClient({ data: [APPLICATION_ROW], error: null });
    await applyToVacancy(client, { vacancyId: ID_2, candidateId: ID_2, source: "staff_created", idempotencyKey: "idem-app", actorAuthUserId: ACTOR_ID, actorLabel: "tester" });
    assert.equal(calls[0]?.args.p_idempotency_key, "idem-app");
  });

  test("transitionApplicationStage forwards toStage", async () => {
    const { client, calls } = fakeRpcClient({ data: [{ ...APPLICATION_ROW, stage: "screening" }], error: null });
    const application = await transitionApplicationStage(client, { id: ID_1, expectedVersion: 1, toStage: "screening", actorAuthUserId: ACTOR_ID, actorLabel: "tester" });
    assert.equal(calls[0]?.args.p_to_stage, "screening");
    assert.equal(application.stage, "screening");
  });

  test("submitInterviewFeedback maps rating/recommendation", async () => {
    const { client, calls } = fakeRpcClient({
      data: [{ id: ID_1, interview_id: ID_2, interviewer_employee_id: ID_2, rating: 5, recommendation: "strong_yes", notes: null, submitted_at: "2026-08-09T00:00:00.000Z" }],
      error: null,
    });
    const feedback = await submitInterviewFeedback(client, { interviewId: ID_2, rating: 5, recommendation: "strong_yes", notes: null, actorAuthUserId: ACTOR_ID, actorLabel: "tester" });
    assert.equal(calls[0]?.args.p_rating, 5);
    assert.equal(feedback.recommendation, "strong_yes");
  });

  test("createJobOfferVersion forwards compensation fields", async () => {
    const { client, calls } = fakeRpcClient({
      data: [
        {
          id: ID_1,
          offer_id: ID_2,
          version_number: 1,
          compensation_amount: "15000000",
          compensation_currency: "IDR",
          effective_date: "2026-09-01",
          expiry_date: null,
          title: "Software Engineer",
          employment_type: "full_time",
          benefits_note: null,
          status: "draft",
          created_at: "2026-08-09T00:00:00.000Z",
        },
      ],
      error: null,
    });
    const version = await createJobOfferVersion(client, {
      applicationId: ID_1,
      compensationAmount: 15000000,
      compensationCurrency: "IDR",
      effectiveDate: "2026-09-01",
      expiryDate: null,
      title: "Software Engineer",
      employmentType: "full_time",
      benefitsNote: null,
      actorAuthUserId: ACTOR_ID,
      actorLabel: "tester",
    });
    assert.equal(calls[0]?.args.p_compensation_amount, 15000000);
    assert.equal(version.compensationCurrency, "IDR");
  });

  test("recordOfferResponse forwards response/responseNote", async () => {
    const { client, calls } = fakeRpcClient({
      data: [{ id: ID_1, tenant_id: TENANT_ID, application_id: ID_2, status: "accepted", approval_status: "approved", approval_request_id: null, current_version_id: ID_2, record_version: 2, created_at: "2026-08-09T00:00:00.000Z", updated_at: "2026-08-09T00:00:00.000Z" }],
      error: null,
    });
    const offer = await recordOfferResponse(client, { offerId: ID_1, expectedVersion: 1, response: "accepted", responseNote: "excited", actorAuthUserId: ACTOR_ID, actorLabel: "tester" });
    assert.equal(calls[0]?.args.p_response, "accepted");
    assert.equal(offer.status, "accepted");
  });

  test("submitPublicJobApplication (anonymous) never sends an actor parameter", async () => {
    const { client, calls } = fakeRpcClient({ data: [{ submit_status: "ok", application_id: ID_1 }], error: null });
    const result = await submitPublicJobApplication(client, {
      postingToken: "raw-token",
      clientKey: "hashed-client-key",
      fullName: "Ada Lovelace",
      email: "ada@example.test",
      phone: null,
      consentGiven: true,
      consentVersion: "v1",
      idempotencyKey: null,
    });
    assert.equal(Object.keys(calls[0]?.args ?? {}).some((k) => k.includes("actor")), false);
    assert.equal(result.submitStatus, "ok");
    assert.equal(result.applicationId, ID_1);
  });

  test("a mutation wrapper throws invalid_response_shape when the RPC returns no row", async () => {
    const { client } = fakeRpcClient({ data: [], error: null });
    await assert.rejects(
      () => publishJobVacancy(client, { id: ID_1, expectedVersion: 1, validityDays: 30, actorAuthUserId: ACTOR_ID, actorLabel: "tester" }),
      (error: unknown) => {
        assert.ok(error instanceof RecruitmentMutationError);
        assert.equal(error.code, "invalid_response_shape");
        return true;
      },
    );
  });
});
