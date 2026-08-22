import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  parseEtaPrediction,
  parseEtaPredictionDetail,
  parseEtaPredictionTenantSetting,
  RequestEtaPredictionInputSchema,
  OverrideEtaPredictionInputSchema,
  EvaluateEtaPredictionInputSchema,
} from "./eta-prediction.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const SHIPMENT_ID = "323e4567-e89b-12d3-a456-426614174000";
const PREDICTION_ID = "423e4567-e89b-12d3-a456-426614174000";
const REQUEST_ID = "523e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "623e4567-e89b-12d3-a456-426614174000";

describe("parseEtaPrediction", () => {
  test("round-trips a pending row", () => {
    const prediction = parseEtaPrediction({
      id: PREDICTION_ID, tenant_id: TENANT_ID, shipment_order_id: SHIPMENT_ID, ai_governed_request_id: null,
      feature_snapshot: { mode: "sea" }, status: "pending", predicted_eta: null, predicted_eta_earliest: null,
      predicted_eta_latest: null, overridden: false, override_reason: null, requested_by: "rep",
      created_at: "2026-08-22T00:00:00.000Z", completed_at: null,
    });
    assert.equal(prediction.status, "pending");
    assert.equal(prediction.predictedEta, null);
  });

  test("rejects an unrecognized status", () => {
    assert.throws(() =>
      parseEtaPrediction({
        id: PREDICTION_ID, tenant_id: TENANT_ID, shipment_order_id: SHIPMENT_ID, ai_governed_request_id: null,
        feature_snapshot: {}, status: "not-a-real-status", predicted_eta: null, predicted_eta_earliest: null,
        predicted_eta_latest: null, overridden: false, override_reason: null, requested_by: null,
        created_at: "2026-08-22T00:00:00.000Z", completed_at: null,
      }),
    );
  });
});

describe("parseEtaPredictionDetail", () => {
  test("surfaces the linked governed request's own evidence and any evaluation", () => {
    const detail = parseEtaPredictionDetail({
      id: PREDICTION_ID, tenant_id: TENANT_ID, shipment_order_id: SHIPMENT_ID, ai_governed_request_id: REQUEST_ID,
      status: "succeeded", predicted_eta: "2026-09-05T14:00:00.000Z", predicted_eta_earliest: "2026-09-05T08:00:00.000Z",
      predicted_eta_latest: "2026-09-05T20:00:00.000Z", overridden: false, override_reason: null, requested_by: "rep",
      created_at: "2026-08-22T00:00:00.000Z", completed_at: "2026-08-22T00:01:00.000Z", confidence_label: "high",
      model_version: "openai-multimodal", request_status: "succeeded", error_minutes: "45", within_confidence_band: true,
      actual_arrival_at: "2026-09-05T14:45:00.000Z",
    });
    assert.equal(detail.confidenceLabel, "high");
    assert.equal(detail.errorMinutes, 45);
    assert.equal(detail.withinConfidenceBand, true);
  });
});

describe("parseEtaPredictionTenantSetting", () => {
  test("round-trips a disabled row", () => {
    const setting = parseEtaPredictionTenantSetting({
      tenant_id: TENANT_ID, enabled: false, disabled_reason: "drift", disabled_by: "rep", updated_at: "2026-08-22T00:00:00.000Z",
    });
    assert.equal(setting.enabled, false);
    assert.equal(setting.disabledReason, "drift");
  });
});

describe("RequestEtaPredictionInputSchema", () => {
  test("accepts a valid input", () => {
    const parsed = RequestEtaPredictionInputSchema.parse({
      tenantId: TENANT_ID, shipmentOrderId: SHIPMENT_ID, featureSnapshot: { mode: "sea" }, idempotencyKey: "idem-1", actorAuthUserId: ACTOR_ID, actorLabel: "rep",
    });
    assert.equal(parsed.idempotencyKey, "idem-1");
  });

  test("rejects an empty idempotency key", () => {
    assert.throws(() =>
      RequestEtaPredictionInputSchema.parse({
        tenantId: TENANT_ID, shipmentOrderId: SHIPMENT_ID, featureSnapshot: {}, idempotencyKey: "", actorAuthUserId: ACTOR_ID, actorLabel: "rep",
      }),
    );
  });
});

describe("OverrideEtaPredictionInputSchema", () => {
  test("rejects an empty reason", () => {
    assert.throws(() => OverrideEtaPredictionInputSchema.parse({ predictionId: PREDICTION_ID, tenantId: TENANT_ID, reason: "", actorAuthUserId: ACTOR_ID, actorLabel: "rep" }));
  });
});

describe("EvaluateEtaPredictionInputSchema", () => {
  test("accepts a valid input", () => {
    const parsed = EvaluateEtaPredictionInputSchema.parse({
      predictionId: PREDICTION_ID, tenantId: TENANT_ID, actualArrivalAt: "2026-09-05T14:45:00.000Z", actorAuthUserId: ACTOR_ID, actorLabel: "rep",
    });
    assert.equal(parsed.actualArrivalAt, "2026-09-05T14:45:00.000Z");
  });
});
