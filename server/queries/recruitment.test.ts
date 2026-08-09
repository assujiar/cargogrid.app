import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  listJobVacancies,
  getJobVacancy,
  getCandidateProfile,
  listCandidates,
  listApplicationsForVacancy,
  getApplicationDetail,
  getMyAssignedInterviews,
  getOfferTimeline,
  getPublicOpenVacancySummaries,
  resolvePublicJobPosting,
  RecruitmentQueryError,
  type RecruitmentQueryClient,
} from "./recruitment.ts";

const TENANT_ID = "123e4567-e89b-12d3-a456-426614174000";
const ID_1 = "223e4567-e89b-12d3-a456-426614174000";
const ID_2 = "323e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "423e4567-e89b-12d3-a456-426614174000";

function fakeRpcClient(response: { data: unknown; error: { message: string } | null }): { client: RecruitmentQueryClient; calls: { fn: string; args: Record<string, unknown> }[] } {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];
  const client = {
    async rpc(fn: string, args: Record<string, unknown>) {
      calls.push({ fn, args });
      return response;
    },
  } as unknown as RecruitmentQueryClient;
  return { client, calls };
}

const VACANCY_ROW = {
  id: ID_1,
  tenant_id: TENANT_ID,
  position_id: ID_2,
  title: "Software Engineer",
  employment_type: "full_time",
  headcount: 1,
  status: "open",
  status_reason: null,
  description: null,
  requirements: null,
  hiring_manager_employee_id: null,
  owner_auth_user_id: null,
  record_version: 1,
  created_at: "2026-08-09T00:00:00.000Z",
  updated_at: "2026-08-09T00:00:00.000Z",
};

describe("recruitment query wrappers", () => {
  test("listJobVacancies passes cursor/filter params through", async () => {
    const { client, calls } = fakeRpcClient({ data: [VACANCY_ROW], error: null });
    const vacancies = await listJobVacancies(client, TENANT_ID, ACTOR_ID, { statusFilter: "open", search: "engineer", limit: 25, afterId: ID_2 });
    assert.equal(calls[0]?.fn, "list_job_vacancies");
    assert.equal(calls[0]?.args.p_status_filter, "open");
    assert.equal(calls[0]?.args.p_after_id, ID_2);
    assert.equal(vacancies.length, 1);
  });

  test("getJobVacancy parses the (vacancy, active_posting_expires_at, current_open_headcount) row", async () => {
    const { client } = fakeRpcClient({ data: [{ vacancy: VACANCY_ROW, active_posting_expires_at: "2026-09-08T00:00:00.000Z", current_open_headcount: 3 }], error: null });
    const detail = await getJobVacancy(client, ID_1, ACTOR_ID);
    assert.equal(detail.currentOpenHeadcount, 3);
    assert.equal(detail.vacancy.title, "Software Engineer");
  });

  test("getJobVacancy throws RecruitmentQueryError when no row returned", async () => {
    const { client } = fakeRpcClient({ data: [], error: null });
    await assert.rejects(() => getJobVacancy(client, ID_1, ACTOR_ID), RecruitmentQueryError);
  });

  test("getJobVacancy propagates a real RPC error", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "insufficient_authority: identity lacks HRS:View" } });
    await assert.rejects(() => getJobVacancy(client, ID_1, ACTOR_ID), (error: unknown) => {
      assert.ok(error instanceof RecruitmentQueryError);
      assert.match(error.message, /insufficient_authority/);
      return true;
    });
  });

  test("getCandidateProfile parses masked pii", async () => {
    const { client } = fakeRpcClient({
      data: [
        {
          id: ID_1,
          tenant_id: TENANT_ID,
          full_name: "Ada Lovelace",
          email: null,
          phone: null,
          national_id_number: null,
          date_of_birth: null,
          address: null,
          resume_file_id: null,
          source: "staff_created",
          status: "active",
          consent_given: true,
          consent_given_at: "2026-08-09T00:00:00.000Z",
          consent_version: "v1",
          personal_data_masked: true,
          record_version: 1,
          created_at: "2026-08-09T00:00:00.000Z",
          updated_at: "2026-08-09T00:00:00.000Z",
        },
      ],
      error: null,
    });
    const candidate = await getCandidateProfile(client, ID_1, ACTOR_ID);
    assert.equal(candidate.personalDataMasked, true);
  });

  test("listCandidates carries no pii projection", async () => {
    const { client } = fakeRpcClient({ data: [{ id: ID_1, full_name: "Ada Lovelace", source: "staff_created", status: "active", consent_given: true, created_at: "2026-08-09T00:00:00.000Z" }], error: null });
    const rows = await listCandidates(client, TENANT_ID, ACTOR_ID);
    assert.equal(rows[0]?.fullName, "Ada Lovelace");
  });

  test("listApplicationsForVacancy maps the pipeline projection", async () => {
    const { client } = fakeRpcClient({
      data: [{ id: ID_1, candidate_id: ID_2, candidate_full_name: "Ada Lovelace", stage: "screening", source: "staff_created", applied_at: "2026-08-09T00:00:00.000Z", stage_since: "2026-08-09T00:00:00.000Z" }],
      error: null,
    });
    const rows = await listApplicationsForVacancy(client, ID_1, ACTOR_ID);
    assert.equal(rows[0]?.candidateFullName, "Ada Lovelace");
  });

  test("getApplicationDetail composes application + candidate + vacancy fields", async () => {
    const { client } = fakeRpcClient({
      data: [
        {
          application: {
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
          },
          candidate_id: ID_2,
          candidate_full_name: "Ada Lovelace",
          vacancy_title: "Software Engineer",
        },
      ],
      error: null,
    });
    const detail = await getApplicationDetail(client, ID_1, ACTOR_ID);
    assert.equal(detail.candidateFullName, "Ada Lovelace");
    assert.equal(detail.application.stage, "new");
  });

  test("getMyAssignedInterviews returns an empty array (never throws) for a caller with no linked employee", async () => {
    const { client } = fakeRpcClient({ data: [], error: null });
    const rows = await getMyAssignedInterviews(client, TENANT_ID, ACTOR_ID);
    assert.deepEqual(rows, []);
  });

  test("getOfferTimeline parses (offer, versions[])", async () => {
    const { client } = fakeRpcClient({
      data: [
        {
          offer: { id: ID_1, tenant_id: TENANT_ID, application_id: ID_2, status: "draft", approval_status: "not_required", approval_request_id: null, current_version_id: null, record_version: 1, created_at: "2026-08-09T00:00:00.000Z", updated_at: "2026-08-09T00:00:00.000Z" },
          versions: [],
        },
      ],
      error: null,
    });
    const timeline = await getOfferTimeline(client, ID_1, ACTOR_ID);
    assert.equal(timeline.offer.status, "draft");
    assert.deepEqual(timeline.versions, []);
  });

  test("getPublicOpenVacancySummaries has no actor parameter (genuinely anonymous)", async () => {
    const { client, calls } = fakeRpcClient({ data: [{ posting_token: "tok", title: "Engineer", employment_type: "full_time", org_unit_name: "Engineering", headcount: 1, published_at: "2026-08-09T00:00:00.000Z" }], error: null });
    await getPublicOpenVacancySummaries(client, "acme");
    assert.deepEqual(calls[0]?.args, { p_tenant_slug: "acme" });
  });

  test("resolvePublicJobPosting returns null (never throws) when the RPC returns an empty result", async () => {
    const { client } = fakeRpcClient({ data: [], error: null });
    const detail = await resolvePublicJobPosting(client, "bad-token", "client-key");
    assert.equal(detail, null);
  });

  test("resolvePublicJobPosting returns null when vacancy_id is null (uniform not-found shape)", async () => {
    const { client } = fakeRpcClient({ data: [{ vacancy_id: null, title: null, employment_type: null, description: null, requirements: null, org_unit_name: null, headcount: null }], error: null });
    const detail = await resolvePublicJobPosting(client, "bad-token", "client-key");
    assert.equal(detail, null);
  });
});
