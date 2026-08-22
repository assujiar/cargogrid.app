import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  parseForecastJob,
  parseForecastJobFeedback,
  parseForecastJobDetail,
  RequestForecastJobInputSchema,
  RecordForecastPlanningDecisionInputSchema,
  EvaluateForecastJobInputSchema,
} from "./forecasting-recommendation.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const JOB_ID = "323e4567-e89b-12d3-a456-426614174000";
const REQUEST_ID = "423e4567-e89b-12d3-a456-426614174000";
const FEEDBACK_ID = "523e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "623e4567-e89b-12d3-a456-426614174000";

describe("parseForecastJob", () => {
  test("round-trips a succeeded row", () => {
    const job = parseForecastJob({
      id: JOB_ID, tenant_id: TENANT_ID, forecast_type: "demand", scenario_label: "baseline",
      scope_snapshot: { segment: "jkt-fcl" }, feature_snapshot: { history_weeks: 26 }, horizon_days: 90,
      ai_governed_request_id: REQUEST_ID, status: "succeeded", predicted_value: "48000", cohort_size: 250,
      is_small_cohort_suppressed: false, data_quality_note: null, requested_by: "rep",
      created_at: "2026-08-22T00:00:00.000Z", completed_at: "2026-08-22T00:01:00.000Z",
    });
    assert.equal(job.predictedValue, 48000);
    assert.equal(job.isSmallCohortSuppressed, false);
  });

  test("rejects an unrecognized forecast_type", () => {
    assert.throws(() =>
      parseForecastJob({
        id: JOB_ID, tenant_id: TENANT_ID, forecast_type: "not-a-real-type", scenario_label: "baseline",
        scope_snapshot: {}, feature_snapshot: {}, horizon_days: 30, ai_governed_request_id: null, status: "pending",
        predicted_value: null, cohort_size: null, is_small_cohort_suppressed: false, data_quality_note: null,
        requested_by: null, created_at: "2026-08-22T00:00:00.000Z", completed_at: null,
      }),
    );
  });
});

describe("parseForecastJobFeedback", () => {
  test("round-trips a useful feedback row", () => {
    const feedback = parseForecastJobFeedback({
      id: FEEDBACK_ID, tenant_id: TENANT_ID, forecast_job_id: JOB_ID, feedback: "useful",
      planning_decision_note: "increasing Q4 allocation", decided_by: "rep", decided_at: "2026-08-22T00:00:00.000Z",
    });
    assert.equal(feedback.feedback, "useful");
  });
});

describe("parseForecastJobDetail", () => {
  test("surfaces masked output_payload when output_payload_masked is true", () => {
    const detail = parseForecastJobDetail({
      id: JOB_ID, tenant_id: TENANT_ID, forecast_type: "churn", scenario_label: "baseline", scope_snapshot: {},
      feature_snapshot: {}, horizon_days: 30, status: "succeeded", predicted_value: "3", cohort_size: 4,
      is_small_cohort_suppressed: true, data_quality_note: null, requested_by: "rep", created_at: "2026-08-22T00:00:00.000Z",
      completed_at: "2026-08-22T00:01:00.000Z", output_payload: { predictedValue: 3 }, output_payload_masked: true,
      confidence_label: "medium", model_version: "openai-multimodal", request_status: "succeeded", feedback: null,
      planning_decision_note: null, decided_by: null, decided_at: null, actual_outcome_value: null, error_pct: null,
    });
    assert.equal(detail.outputPayloadMasked, true);
    assert.equal(detail.isSmallCohortSuppressed, true);
  });
});

describe("RequestForecastJobInputSchema", () => {
  test("accepts a valid input", () => {
    const parsed = RequestForecastJobInputSchema.parse({
      tenantId: TENANT_ID, forecastType: "demand", scopeSnapshot: { segment: "jkt-fcl" }, featureSnapshot: { history_weeks: 26 },
      horizonDays: 90, idempotencyKey: "idem-1", actorAuthUserId: ACTOR_ID, actorLabel: "rep",
    });
    assert.equal(parsed.horizonDays, 90);
  });

  test("rejects a horizon beyond 1095 days", () => {
    assert.throws(() =>
      RequestForecastJobInputSchema.parse({
        tenantId: TENANT_ID, forecastType: "demand", scopeSnapshot: {}, featureSnapshot: {}, horizonDays: 5000,
        idempotencyKey: "idem-1", actorAuthUserId: ACTOR_ID, actorLabel: "rep",
      }),
    );
  });
});

describe("RecordForecastPlanningDecisionInputSchema", () => {
  test("defaults planningDecisionNote to null", () => {
    const parsed = RecordForecastPlanningDecisionInputSchema.parse({ jobId: JOB_ID, tenantId: TENANT_ID, feedback: "useful", actorAuthUserId: ACTOR_ID, actorLabel: "rep" });
    assert.equal(parsed.planningDecisionNote, null);
  });
});

describe("EvaluateForecastJobInputSchema", () => {
  test("accepts a valid input", () => {
    const parsed = EvaluateForecastJobInputSchema.parse({ jobId: JOB_ID, tenantId: TENANT_ID, actualOutcomeValue: 52800, actorAuthUserId: ACTOR_ID, actorLabel: "rep" });
    assert.equal(parsed.actualOutcomeValue, 52800);
  });
});
