import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  getVendorAssessment,
  listVendorAssessments,
  getVendorAssessmentScoreBreakdown,
  getVendorCurrentAssessmentStatus,
  VendorAssessmentQueryError,
  type VendorAssessmentQueryClient,
} from "./vendor-assessment.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const VENDOR_ID = "323e4567-e89b-12d3-a456-426614174000";
const TEMPLATE_ID = "123e4567-e89b-12d3-a456-426614174000";
const ASSESSMENT_ID = "423e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "623e4567-e89b-12d3-a456-426614174000";
const CRITERION_ID = "523e4567-e89b-12d3-a456-426614174000";

function fakeRpcClient(response: { data: unknown; error: { message: string } | null }): {
  client: VendorAssessmentQueryClient;
  calls: { fn: string; args: Record<string, unknown> }[];
} {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];
  const client = {
    async rpc(fn: string, args: Record<string, unknown>) {
      calls.push({ fn, args });
      return response;
    },
  } as unknown as VendorAssessmentQueryClient;
  return { client, calls };
}

describe("getVendorAssessment", () => {
  test("maps the detail row including reassessment_due", async () => {
    const { client, calls } = fakeRpcClient({
      data: [
        {
          id: ASSESSMENT_ID,
          tenant_id: TENANT_ID,
          vendor_master_record_id: VENDOR_ID,
          template_version_id: TEMPLATE_ID,
          assessment_type: "initial",
          status: "approved",
          assessor_auth_user_id: ACTOR_ID,
          reviewer_auth_user_id: null,
          calculated_score: 85,
          score_band: "pass",
          adjusted_score: null,
          adjustment_reason: null,
          adjusted_by: null,
          adjusted_at: null,
          submitted_at: "2026-08-05T00:00:00.000Z",
          decided_at: "2026-08-05T00:01:00.000Z",
          decision_reason: null,
          expiry_date: "2027-02-01",
          reassessment_due: false,
          predecessor_assessment_id: null,
          record_version: 4,
          created_by: "staff",
          created_at: "2026-08-05T00:00:00.000Z",
          updated_at: "2026-08-05T00:01:00.000Z",
        },
      ],
      error: null,
    });

    const result = await getVendorAssessment(client, ASSESSMENT_ID, ACTOR_ID);
    assert.equal(result.reassessmentDue, false);
    assert.equal(calls[0]?.fn, "get_vendor_assessment");
    assert.equal(calls[0]?.args.p_assessment_id, ASSESSMENT_ID);
  });

  test("throws VendorAssessmentQueryError on an RPC error", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "insufficient_authority: identity lacks PRC:View" } });
    await assert.rejects(() => getVendorAssessment(client, ASSESSMENT_ID, ACTOR_ID), VendorAssessmentQueryError);
  });

  test("throws VendorAssessmentQueryError when no row is returned", async () => {
    const { client } = fakeRpcClient({ data: [], error: null });
    await assert.rejects(() => getVendorAssessment(client, ASSESSMENT_ID, ACTOR_ID), VendorAssessmentQueryError);
  });
});

describe("listVendorAssessments", () => {
  test("passes through the assignedToMe filter and cursor pagination options", async () => {
    const { client, calls } = fakeRpcClient({ data: [], error: null });
    await listVendorAssessments(client, TENANT_ID, ACTOR_ID, { assignedToMe: true, statusFilter: "under_review", limit: 25, afterId: "cursor-1" });
    assert.equal(calls[0]?.fn, "list_vendor_assessments");
    assert.equal(calls[0]?.args.p_assigned_to_me, true);
    assert.equal(calls[0]?.args.p_status_filter, "under_review");
    assert.equal(calls[0]?.args.p_limit, 25);
    assert.equal(calls[0]?.args.p_after_id, "cursor-1");
  });

  test("defaults assignedToMe to false when omitted", async () => {
    const { client, calls } = fakeRpcClient({ data: [], error: null });
    await listVendorAssessments(client, TENANT_ID, ACTOR_ID);
    assert.equal(calls[0]?.args.p_assigned_to_me, false);
  });
});

describe("getVendorAssessmentScoreBreakdown", () => {
  test("maps a masked financial row alongside an unmasked one", async () => {
    const { client } = fakeRpcClient({
      data: [
        { criterion_id: CRITERION_ID, label: "Financial stability disclosure", purpose_tag: "financial", weight: 20, answer_score: 50, contribution: 10, value: null, notes: null, evidence_file_id: null, answered: true },
        { criterion_id: "923e4567-e89b-12d3-a456-426614174111", label: "Safety compliance", purpose_tag: "safety", weight: 30, answer_score: 100, contribution: 30, value: "clean audit", notes: null, evidence_file_id: null, answered: true },
      ],
      error: null,
    });
    const rows = await getVendorAssessmentScoreBreakdown(client, ASSESSMENT_ID, ACTOR_ID);
    assert.equal(rows.length, 2);
    assert.equal(rows[0]?.value, null);
    assert.equal(rows[1]?.value, "clean audit");
  });
});

describe("getVendorCurrentAssessmentStatus", () => {
  test("maps one row per assessment_type", async () => {
    const { client, calls } = fakeRpcClient({
      data: [
        {
          assessment_type: "initial",
          assessment_id: ASSESSMENT_ID,
          status: "approved",
          calculated_score: 85,
          adjusted_score: null,
          score_band: "pass",
          decided_at: "2026-08-05T00:01:00.000Z",
          expiry_date: "2027-02-01",
          reassessment_due: false,
        },
      ],
      error: null,
    });
    const rows = await getVendorCurrentAssessmentStatus(client, VENDOR_ID, ACTOR_ID);
    assert.equal(rows.length, 1);
    assert.equal(rows[0]?.assessmentType, "initial");
    assert.equal(calls[0]?.args.p_vendor_master_record_id, VENDOR_ID);
  });
});
