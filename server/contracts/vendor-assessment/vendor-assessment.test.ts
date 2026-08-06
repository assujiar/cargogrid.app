import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  parseVendorAssessmentTemplate,
  parseVendorAssessmentTemplateCriterion,
  parseVendorAssessment,
  parseVendorAssessmentMutationResult,
  parseVendorAssessmentAnswer,
  parseVendorAssessmentScoreBreakdownRow,
  parseVendorAssessmentFinding,
  parseVendorAssessmentCorrectiveAction,
  parseVendorCurrentAssessmentStatusRow,
  CreateVendorAssessmentTemplateDraftInputSchema,
  AdjustVendorAssessmentScoreInputSchema,
  DecideVendorAssessmentReviewInputSchema,
  RecordVendorAssessmentAnswerInputSchema,
} from "./vendor-assessment.ts";

const TEMPLATE_ID = "123e4567-e89b-12d3-a456-426614174000";
const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const VENDOR_ID = "323e4567-e89b-12d3-a456-426614174000";
const ASSESSMENT_ID = "423e4567-e89b-12d3-a456-426614174000";
const CRITERION_ID = "523e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "623e4567-e89b-12d3-a456-426614174000";
const REVIEWER_ID = "723e4567-e89b-12d3-a456-426614174000";
const ANSWER_ID = "823e4567-e89b-12d3-a456-426614174000";
const FINDING_ID = "923e4567-e89b-12d3-a456-426614174000";
const CA_ID = "a23e4567-e89b-12d3-a456-426614174000";

describe("parseVendorAssessmentTemplate", () => {
  test("maps every field, coercing numeric-shaped strings", () => {
    const template = parseVendorAssessmentTemplate({
      id: TEMPLATE_ID,
      tenant_id: TENANT_ID,
      vendor_category: "trucking",
      assessment_type: "initial",
      name: "Initial Trucking Assessment",
      description: "baseline",
      validity_period_days: 180,
      pass_threshold: "80.00",
      conditional_threshold: "60.00",
      weight_total_required: "100.00",
      status: "draft",
      supersedes_version_id: null,
      effective_from: "2026-08-05T00:00:00.000Z",
      record_version: 1,
      created_by: "staff",
      created_at: "2026-08-05T00:00:00.000Z",
      updated_at: "2026-08-05T00:00:00.000Z",
      criterion_count: 3,
    });
    assert.equal(template.passThreshold, 80);
    assert.equal(template.status, "draft");
    assert.equal(template.criterionCount, 3);
  });

  test("criterionCount is undefined when the row omits it (raw mutation-shaped row)", () => {
    const template = parseVendorAssessmentTemplate({
      id: TEMPLATE_ID,
      tenant_id: TENANT_ID,
      vendor_category: null,
      assessment_type: "periodic",
      name: "Periodic Review",
      description: null,
      validity_period_days: 90,
      pass_threshold: 70,
      conditional_threshold: 50,
      weight_total_required: 100,
      status: "published",
      supersedes_version_id: null,
      effective_from: "2026-08-05T00:00:00.000Z",
      record_version: 2,
      created_by: "staff",
      created_at: "2026-08-05T00:00:00.000Z",
      updated_at: "2026-08-05T00:00:00.000Z",
    });
    assert.equal(template.criterionCount, undefined);
  });
});

describe("parseVendorAssessmentTemplateCriterion", () => {
  test("maps every field", () => {
    const criterion = parseVendorAssessmentTemplateCriterion({
      id: CRITERION_ID,
      tenant_id: TENANT_ID,
      template_version_id: TEMPLATE_ID,
      label: "Safety compliance",
      purpose_tag: "safety",
      weight: 30,
      scoring_guidance: "safety audit score",
      display_order: 2,
      status: "active",
      record_version: 1,
      created_by: "staff",
      created_at: "2026-08-05T00:00:00.000Z",
      updated_at: "2026-08-05T00:00:00.000Z",
    });
    assert.equal(criterion.purposeTag, "safety");
    assert.equal(criterion.weight, 30);
  });
});

describe("parseVendorAssessmentMutationResult / parseVendorAssessment", () => {
  const raw = {
    id: ASSESSMENT_ID,
    tenant_id: TENANT_ID,
    vendor_master_record_id: VENDOR_ID,
    template_version_id: TEMPLATE_ID,
    assessment_type: "initial",
    status: "approved",
    assessor_auth_user_id: ACTOR_ID,
    reviewer_auth_user_id: REVIEWER_ID,
    calculated_score: "85.00",
    score_band: "pass",
    adjusted_score: null,
    adjustment_reason: null,
    adjusted_by: null,
    adjusted_at: null,
    submitted_at: "2026-08-05T00:00:00.000Z",
    decided_at: "2026-08-05T00:01:00.000Z",
    decision_reason: null,
    expiry_date: "2027-02-01",
    predecessor_assessment_id: null,
    record_version: 4,
    created_by: "staff",
    created_at: "2026-08-05T00:00:00.000Z",
    updated_at: "2026-08-05T00:01:00.000Z",
  };

  test("parseVendorAssessmentMutationResult maps the raw table row, coercing numeric strings", () => {
    const result = parseVendorAssessmentMutationResult(raw);
    assert.equal(result.calculatedScore, 85);
    assert.equal(result.scoreBand, "pass");
    assert.equal(result.recordVersion, 4);
  });

  test("parseVendorAssessment adds the computed reassessmentDue flag on top of the same row shape", () => {
    const result = parseVendorAssessment({ ...raw, reassessment_due: true });
    assert.equal(result.reassessmentDue, true);
    assert.equal(result.calculatedScore, 85);
  });
});

describe("parseVendorAssessmentAnswer", () => {
  test("maps every field", () => {
    const answer = parseVendorAssessmentAnswer({
      id: ANSWER_ID,
      tenant_id: TENANT_ID,
      assessment_id: ASSESSMENT_ID,
      criterion_id: CRITERION_ID,
      value: "95% on-time",
      score: "90.00",
      evidence_file_id: null,
      notes: "strong performance",
      record_version: 1,
      created_by: "staff",
      created_at: "2026-08-05T00:00:00.000Z",
      updated_at: "2026-08-05T00:00:00.000Z",
    });
    assert.equal(answer.score, 90);
    assert.equal(answer.notes, "strong performance");
  });
});

describe("parseVendorAssessmentScoreBreakdownRow", () => {
  test("maps a masked row (financial value/notes null, contribution still visible)", () => {
    const row = parseVendorAssessmentScoreBreakdownRow({
      criterion_id: CRITERION_ID,
      label: "Financial stability disclosure",
      purpose_tag: "financial",
      weight: "20.00",
      answer_score: "50.00",
      contribution: "10.00",
      value: null,
      notes: null,
      evidence_file_id: null,
      answered: true,
    });
    assert.equal(row.value, null);
    assert.equal(row.notes, null);
    assert.equal(row.contribution, 10);
    assert.equal(row.answered, true);
  });
});

describe("parseVendorAssessmentFinding", () => {
  test("maps every field", () => {
    const finding = parseVendorAssessmentFinding({
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
    });
    assert.equal(finding.severity, "high");
    assert.equal(finding.status, "open");
  });
});

describe("parseVendorAssessmentCorrectiveAction", () => {
  test("maps every field", () => {
    const action = parseVendorAssessmentCorrectiveAction({
      id: CA_ID,
      tenant_id: TENANT_ID,
      finding_id: FINDING_ID,
      assessment_id: ASSESSMENT_ID,
      description: "obtain a renewed safety certificate",
      due_date: "2026-08-20",
      status: "completed",
      resolution_notes: "renewed certificate uploaded and verified",
      resolved_evidence_file_id: "b23e4567-e89b-12d3-a456-426614174000",
      resolved_by: "staff",
      resolved_at: "2026-08-15T00:00:00.000Z",
      record_version: 2,
      created_by: "staff",
      created_at: "2026-08-05T00:00:00.000Z",
      updated_at: "2026-08-15T00:00:00.000Z",
    });
    assert.equal(action.status, "completed");
    assert.equal(action.resolvedEvidenceFileId, "b23e4567-e89b-12d3-a456-426614174000");
  });
});

describe("parseVendorCurrentAssessmentStatusRow", () => {
  test("maps every field", () => {
    const row = parseVendorCurrentAssessmentStatusRow({
      assessment_type: "initial",
      assessment_id: ASSESSMENT_ID,
      status: "approved",
      calculated_score: "85.00",
      adjusted_score: null,
      score_band: "pass",
      decided_at: "2026-08-05T00:01:00.000Z",
      expiry_date: "2027-02-01",
      reassessment_due: false,
    });
    assert.equal(row.status, "approved");
    assert.equal(row.reassessmentDue, false);
  });
});

describe("mutation input schemas", () => {
  test("CreateVendorAssessmentTemplateDraftInputSchema accepts an optional weightTotalRequired and rejects an out-of-range threshold", () => {
    const parsed = CreateVendorAssessmentTemplateDraftInputSchema.parse({
      tenantId: TENANT_ID,
      assessmentType: "initial",
      name: "Initial Trucking Assessment",
      validityPeriodDays: 180,
      passThreshold: 80,
      conditionalThreshold: 60,
      actorAuthUserId: ACTOR_ID,
      actorLabel: "staff",
    });
    assert.equal(parsed.weightTotalRequired, undefined);

    assert.throws(() =>
      CreateVendorAssessmentTemplateDraftInputSchema.parse({
        tenantId: TENANT_ID,
        assessmentType: "initial",
        name: "Bad Threshold",
        validityPeriodDays: 180,
        passThreshold: 150,
        conditionalThreshold: 60,
        actorAuthUserId: ACTOR_ID,
        actorLabel: "staff",
      }),
    );
  });

  test("AdjustVendorAssessmentScoreInputSchema requires a non-empty reason", () => {
    assert.throws(() =>
      AdjustVendorAssessmentScoreInputSchema.parse({
        assessmentId: ASSESSMENT_ID,
        expectedVersion: 1,
        adjustedScore: 70,
        reason: "",
        actorAuthUserId: ACTOR_ID,
        actorLabel: "manager",
      }),
    );
  });

  test("DecideVendorAssessmentReviewInputSchema accepts approve/reject only", () => {
    assert.throws(() =>
      DecideVendorAssessmentReviewInputSchema.parse({
        assessmentId: ASSESSMENT_ID,
        expectedVersion: 1,
        decision: "maybe",
        actorAuthUserId: ACTOR_ID,
        actorLabel: "reviewer",
      }),
    );
  });

  test("RecordVendorAssessmentAnswerInputSchema rejects a score outside 0-100", () => {
    assert.throws(() =>
      RecordVendorAssessmentAnswerInputSchema.parse({
        assessmentId: ASSESSMENT_ID,
        criterionId: CRITERION_ID,
        score: 150,
        actorAuthUserId: ACTOR_ID,
        actorLabel: "staff",
      }),
    );
  });
});
