import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  startVendorAssessment,
  recordVendorAssessmentAnswer,
  submitVendorAssessmentForReview,
  decideVendorAssessmentReview,
  adjustVendorAssessmentScore,
  closeVendorAssessment,
  createVendorAssessmentTemplateDraft,
  publishVendorAssessmentTemplate,
  raiseVendorAssessmentFinding,
  VendorAssessmentMutationError,
  type VendorAssessmentMutationRpcClient,
} from "./vendor-assessment.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const VENDOR_ID = "323e4567-e89b-12d3-a456-426614174000";
const TEMPLATE_ID = "123e4567-e89b-12d3-a456-426614174000";
const ASSESSMENT_ID = "423e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "623e4567-e89b-12d3-a456-426614174000";
const CRITERION_ID = "523e4567-e89b-12d3-a456-426614174000";
const ANSWER_ID = "823e4567-e89b-12d3-a456-426614174000";
const FINDING_ID = "923e4567-e89b-12d3-a456-426614174000";

function fakeRpcClient(response: { data: unknown; error: { message: string } | null }): {
  client: VendorAssessmentMutationRpcClient;
  calls: { fn: string; args: Record<string, unknown> }[];
} {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];
  const client = {
    async rpc(fn: string, args: Record<string, unknown>) {
      calls.push({ fn, args });
      return response;
    },
  } as unknown as VendorAssessmentMutationRpcClient;
  return { client, calls };
}

const ASSESSMENT_ROW = {
  id: ASSESSMENT_ID,
  tenant_id: TENANT_ID,
  vendor_master_record_id: VENDOR_ID,
  template_version_id: TEMPLATE_ID,
  assessment_type: "initial",
  status: "draft",
  assessor_auth_user_id: ACTOR_ID,
  reviewer_auth_user_id: null,
  calculated_score: null,
  score_band: null,
  adjusted_score: null,
  adjustment_reason: null,
  adjusted_by: null,
  adjusted_at: null,
  submitted_at: null,
  decided_at: null,
  decision_reason: null,
  expiry_date: null,
  predecessor_assessment_id: null,
  record_version: 1,
  created_by: "staff",
  created_at: "2026-08-05T00:00:00.000Z",
  updated_at: "2026-08-05T00:00:00.000Z",
};

const TEMPLATE_ROW = {
  id: TEMPLATE_ID,
  tenant_id: TENANT_ID,
  vendor_category: "trucking",
  assessment_type: "initial",
  name: "Initial Trucking Assessment",
  description: null,
  validity_period_days: 180,
  pass_threshold: 80,
  conditional_threshold: 60,
  weight_total_required: 100,
  status: "draft",
  supersedes_version_id: null,
  effective_from: "2026-08-05T00:00:00.000Z",
  record_version: 1,
  created_by: "staff",
  created_at: "2026-08-05T00:00:00.000Z",
  updated_at: "2026-08-05T00:00:00.000Z",
};

describe("startVendorAssessment", () => {
  test("calls start_vendor_assessment with mapped snake_case args and parses the response", async () => {
    const { client, calls } = fakeRpcClient({ data: [ASSESSMENT_ROW], error: null });
    const result = await startVendorAssessment(client, {
      vendorMasterRecordId: VENDOR_ID,
      templateVersionId: TEMPLATE_ID,
      reviewerAuthUserId: null,
      idempotencyKey: "idem-1",
      actorAuthUserId: ACTOR_ID,
      actorLabel: "staff",
    });
    assert.equal(calls[0]?.fn, "start_vendor_assessment");
    assert.equal(calls[0]?.args.p_vendor_master_record_id, VENDOR_ID);
    assert.equal(calls[0]?.args.p_template_version_id, TEMPLATE_ID);
    assert.equal(result.status, "draft");
  });

  test("classifies conflicting_active_assessment", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "conflicting_active_assessment: vendor already has an open initial assessment" } });
    await assert.rejects(
      () => startVendorAssessment(client, { vendorMasterRecordId: VENDOR_ID, templateVersionId: TEMPLATE_ID, actorAuthUserId: ACTOR_ID, actorLabel: "staff" }),
      (error: unknown) => error instanceof VendorAssessmentMutationError && error.code === "conflicting_active_assessment",
    );
  });

  test("classifies vendor_blacklisted", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "vendor_blacklisted: vendor is blacklisted" } });
    await assert.rejects(
      () => startVendorAssessment(client, { vendorMasterRecordId: VENDOR_ID, templateVersionId: TEMPLATE_ID, actorAuthUserId: ACTOR_ID, actorLabel: "staff" }),
      (error: unknown) => error instanceof VendorAssessmentMutationError && error.code === "vendor_blacklisted",
    );
  });

  test("falls back to mutation_failed for an unrecognized error prefix", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "some_unrelated_db_error: connection reset" } });
    await assert.rejects(
      () => startVendorAssessment(client, { vendorMasterRecordId: VENDOR_ID, templateVersionId: TEMPLATE_ID, actorAuthUserId: ACTOR_ID, actorLabel: "staff" }),
      (error: unknown) => error instanceof VendorAssessmentMutationError && error.code === "mutation_failed",
    );
  });
});

describe("recordVendorAssessmentAnswer", () => {
  test("calls record_vendor_assessment_answer with mapped args", async () => {
    const { client, calls } = fakeRpcClient({
      data: [
        {
          id: ANSWER_ID,
          tenant_id: TENANT_ID,
          assessment_id: ASSESSMENT_ID,
          criterion_id: CRITERION_ID,
          value: "95% on-time",
          score: 90,
          evidence_file_id: null,
          notes: null,
          record_version: 1,
          created_by: "staff",
          created_at: "2026-08-05T00:00:00.000Z",
          updated_at: "2026-08-05T00:00:00.000Z",
        },
      ],
      error: null,
    });
    const result = await recordVendorAssessmentAnswer(client, { assessmentId: ASSESSMENT_ID, criterionId: CRITERION_ID, score: 90, actorAuthUserId: ACTOR_ID, actorLabel: "staff" });
    assert.equal(calls[0]?.fn, "record_vendor_assessment_answer");
    assert.equal(calls[0]?.args.p_score, 90);
    assert.equal(result.score, 90);
  });

  test("classifies not_assigned_assessor", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "not_assigned_assessor: identity is not the assigned assessor" } });
    await assert.rejects(
      () => recordVendorAssessmentAnswer(client, { assessmentId: ASSESSMENT_ID, criterionId: CRITERION_ID, score: 90, actorAuthUserId: ACTOR_ID, actorLabel: "staff" }),
      (error: unknown) => error instanceof VendorAssessmentMutationError && error.code === "not_assigned_assessor",
    );
  });
});

describe("submitVendorAssessmentForReview", () => {
  test("classifies missing_required_criteria", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "missing_required_criteria: 1 of 3 required criteria answered" } });
    await assert.rejects(
      () => submitVendorAssessmentForReview(client, { assessmentId: ASSESSMENT_ID, expectedVersion: 1, actorAuthUserId: ACTOR_ID, actorLabel: "staff" }),
      (error: unknown) => error instanceof VendorAssessmentMutationError && error.code === "missing_required_criteria",
    );
  });
});

describe("decideVendorAssessmentReview", () => {
  test("classifies self_approval_not_allowed (the mandatory maker-checker guard)", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "self_approval_not_allowed: identity assessed this vendor assessment and may not also decide its review" } });
    await assert.rejects(
      () => decideVendorAssessmentReview(client, { assessmentId: ASSESSMENT_ID, expectedVersion: 1, decision: "approve", actorAuthUserId: ACTOR_ID, actorLabel: "staff" }),
      (error: unknown) => error instanceof VendorAssessmentMutationError && error.code === "self_approval_not_allowed",
    );
  });

  test("maps decision/reason to p_decision/p_reason", async () => {
    const { client, calls } = fakeRpcClient({ data: [{ ...ASSESSMENT_ROW, status: "rejected", decision_reason: "score too low" }], error: null });
    const result = await decideVendorAssessmentReview(client, { assessmentId: ASSESSMENT_ID, expectedVersion: 1, decision: "reject", reason: "score too low", actorAuthUserId: ACTOR_ID, actorLabel: "reviewer" });
    assert.equal(calls[0]?.args.p_decision, "reject");
    assert.equal(calls[0]?.args.p_reason, "score too low");
    assert.equal(result.status, "rejected");
  });
});

describe("adjustVendorAssessmentScore", () => {
  test("the input schema itself rejects an empty reason before any RPC call (client-side mirror of the RPC's own mandatory-reason rule)", async () => {
    const { client, calls } = fakeRpcClient({ data: null, error: null });
    await assert.rejects(() => adjustVendorAssessmentScore(client, { assessmentId: ASSESSMENT_ID, expectedVersion: 1, adjustedScore: 70, reason: "", actorAuthUserId: ACTOR_ID, actorLabel: "manager" }));
    assert.equal(calls.length, 0);
  });

  test("classifies insufficient_authority when the RPC itself rejects a validly-shaped call", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "insufficient_authority: identity lacks PRC:Override" } });
    await assert.rejects(
      () => adjustVendorAssessmentScore(client, { assessmentId: ASSESSMENT_ID, expectedVersion: 1, adjustedScore: 70, reason: "evidence of undisclosed subcontracting", actorAuthUserId: ACTOR_ID, actorLabel: "manager" }),
      (error: unknown) => error instanceof VendorAssessmentMutationError && error.code === "insufficient_authority",
    );
  });
});

describe("closeVendorAssessment", () => {
  test("classifies open_corrective_actions_block_close", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "open_corrective_actions_block_close: 1 open corrective action(s) remain" } });
    await assert.rejects(
      () => closeVendorAssessment(client, { assessmentId: ASSESSMENT_ID, expectedVersion: 1, actorAuthUserId: ACTOR_ID, actorLabel: "staff" }),
      (error: unknown) => error instanceof VendorAssessmentMutationError && error.code === "open_corrective_actions_block_close",
    );
  });

  test("passes overrideReason through as p_override_reason", async () => {
    const { client, calls } = fakeRpcClient({ data: [{ ...ASSESSMENT_ROW, status: "closed" }], error: null });
    await closeVendorAssessment(client, { assessmentId: ASSESSMENT_ID, expectedVersion: 1, overrideReason: "cleared pending renewal", actorAuthUserId: ACTOR_ID, actorLabel: "manager" });
    assert.equal(calls[0]?.args.p_override_reason, "cleared pending renewal");
  });
});

describe("createVendorAssessmentTemplateDraft / publishVendorAssessmentTemplate", () => {
  test("classifies weight_sum_mismatch on publish", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "weight_sum_mismatch: criteria weights sum to 60 but must sum to 100" } });
    await assert.rejects(
      () => publishVendorAssessmentTemplate(client, { templateVersionId: TEMPLATE_ID, expectedVersion: 1, actorAuthUserId: ACTOR_ID, actorLabel: "reviewer" }),
      (error: unknown) => error instanceof VendorAssessmentMutationError && error.code === "weight_sum_mismatch",
    );
  });

  test("createVendorAssessmentTemplateDraft parses the returned template row", async () => {
    const { client, calls } = fakeRpcClient({ data: [TEMPLATE_ROW], error: null });
    const result = await createVendorAssessmentTemplateDraft(client, {
      tenantId: TENANT_ID,
      assessmentType: "initial",
      name: "Initial Trucking Assessment",
      validityPeriodDays: 180,
      passThreshold: 80,
      conditionalThreshold: 60,
      actorAuthUserId: ACTOR_ID,
      actorLabel: "staff",
    });
    assert.equal(calls[0]?.fn, "create_vendor_assessment_template_draft");
    assert.equal(result.status, "draft");
  });
});

describe("raiseVendorAssessmentFinding", () => {
  test("maps severity/description and parses the response", async () => {
    const { client, calls } = fakeRpcClient({
      data: [
        {
          id: FINDING_ID,
          tenant_id: TENANT_ID,
          assessment_id: ASSESSMENT_ID,
          severity: "high",
          description: "expired safety certificate on file",
          status: "open",
          resolution_reason: null,
          resolved_by: null,
          resolved_at: null,
          record_version: 1,
          created_by: "staff",
          created_at: "2026-08-05T00:00:00.000Z",
          updated_at: "2026-08-05T00:00:00.000Z",
        },
      ],
      error: null,
    });
    const result = await raiseVendorAssessmentFinding(client, { assessmentId: ASSESSMENT_ID, severity: "high", description: "expired safety certificate on file", actorAuthUserId: ACTOR_ID, actorLabel: "staff" });
    assert.equal(calls[0]?.args.p_severity, "high");
    assert.equal(result.status, "open");
  });
});
