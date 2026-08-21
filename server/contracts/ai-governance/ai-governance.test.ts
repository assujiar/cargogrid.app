import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  parseAiGovernedRequest,
  parseAiGovernedDispatchInfo,
  RequestAiGovernedActionInputSchema,
  RecordAiGovernedRequestOutcomeInputSchema,
  ListAiGovernedRequestsForTenantInputSchema,
  RequestAiOutputApprovalInputSchema,
  DecideAiOutputApprovalInputSchema,
} from "./ai-governance.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const CONNECTION_ID = "323e4567-e89b-12d3-a456-426614174000";
const REQUEST_ID = "423e4567-e89b-12d3-a456-426614174000";
const CORRELATION_ID = "523e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "623e4567-e89b-12d3-a456-426614174000";
const STEP_ID = "723e4567-e89b-12d3-a456-426614174000";

describe("parseAiGovernedRequest", () => {
  test("a pending request carries a null output, confidence, and approvalRequestId, not a crash", () => {
    const row = parseAiGovernedRequest({
      id: REQUEST_ID, tenant_id: TENANT_ID, connection_id: CONNECTION_ID, feature_code: "quotation_draft",
      correlation_record_type: null, correlation_record_id: null, prompt_payload: { origin: "JKT", destination: "SBY" },
      status: "pending", output_payload: null, confidence_label: null, model_version: null,
      provider_unit_cost_amount: null, currency: null, billed_amount: null, error_message: null,
      approval_request_id: null, requested_by_auth_user_id: ACTOR_ID, requested_by: "system", created_at: "2026-08-21T00:00:00.000Z", completed_at: null,
    });
    assert.equal(row.status, "pending");
    assert.equal(row.outputPayload, null);
    assert.equal(row.approvalRequestId, null);
  });

  test("a succeeded request with a correlation record and billed amount maps snake_case columns to camelCase", () => {
    const row = parseAiGovernedRequest({
      id: REQUEST_ID, tenant_id: TENANT_ID, connection_id: CONNECTION_ID, feature_code: "quotation_draft",
      correlation_record_type: "quotation", correlation_record_id: CORRELATION_ID, prompt_payload: { origin: "JKT" },
      status: "succeeded", output_payload: { draftLines: [] }, confidence_label: "medium", model_version: "openai-multimodal",
      provider_unit_cost_amount: 0.05, currency: "USD", billed_amount: 0.06, error_message: null,
      approval_request_id: null, requested_by_auth_user_id: ACTOR_ID, requested_by: "system", created_at: "2026-08-21T00:00:00.000Z", completed_at: "2026-08-21T00:01:00.000Z",
    });
    assert.equal(row.correlationRecordType, "quotation");
    assert.equal(row.correlationRecordId, CORRELATION_ID);
    assert.equal(row.billedAmount, 0.06);
    assert.equal(row.confidenceLabel, "medium");
  });
});

describe("parseAiGovernedDispatchInfo", () => {
  test("maps snake_case columns to camelCase", () => {
    const info = parseAiGovernedDispatchInfo({ connection_id: CONNECTION_ID, connection_status: "active", connection_config: { apiUrl: "https://ai.example.test/v1/infer" } });
    assert.equal(info.connectionId, CONNECTION_ID);
    assert.equal(info.connectionStatus, "active");
  });
});

describe("RequestAiGovernedActionInputSchema", () => {
  test("rejects an empty featureCode", () => {
    assert.throws(() =>
      RequestAiGovernedActionInputSchema.parse({
        tenantId: TENANT_ID, connectionId: CONNECTION_ID, featureCode: "", promptPayload: {}, actorAuthUserId: ACTOR_ID, actorLabel: "system",
      }),
    );
  });

  test("defaults correlationRecordType and correlationRecordId to null", () => {
    const parsed = RequestAiGovernedActionInputSchema.parse({
      tenantId: TENANT_ID, connectionId: CONNECTION_ID, featureCode: "quotation_draft", promptPayload: { origin: "JKT" }, actorAuthUserId: ACTOR_ID, actorLabel: "system",
    });
    assert.equal(parsed.correlationRecordType, null);
    assert.equal(parsed.correlationRecordId, null);
  });
});

describe("RecordAiGovernedRequestOutcomeInputSchema", () => {
  test("rejects a status outside succeeded/failed", () => {
    assert.throws(() =>
      RecordAiGovernedRequestOutcomeInputSchema.parse({
        requestId: REQUEST_ID, status: "pending", actorAuthUserId: ACTOR_ID, actorLabel: "system",
      }),
    );
  });

  test("rejects a negative providerUnitCostAmount", () => {
    assert.throws(() =>
      RecordAiGovernedRequestOutcomeInputSchema.parse({
        requestId: REQUEST_ID, status: "succeeded", providerUnitCostAmount: -1, actorAuthUserId: ACTOR_ID, actorLabel: "system",
      }),
    );
  });

  test("defaults outputPayload, confidenceLabel, and errorMessage to null", () => {
    const parsed = RecordAiGovernedRequestOutcomeInputSchema.parse({ requestId: REQUEST_ID, status: "failed", actorAuthUserId: ACTOR_ID, actorLabel: "system" });
    assert.equal(parsed.outputPayload, null);
    assert.equal(parsed.confidenceLabel, null);
    assert.equal(parsed.errorMessage, null);
  });
});

describe("ListAiGovernedRequestsForTenantInputSchema", () => {
  test("rejects a limit above 200", () => {
    assert.throws(() => ListAiGovernedRequestsForTenantInputSchema.parse({ tenantId: TENANT_ID, actorAuthUserId: ACTOR_ID, limit: 500 }));
  });

  test("defaults featureCode to null and limit to 50", () => {
    const parsed = ListAiGovernedRequestsForTenantInputSchema.parse({ tenantId: TENANT_ID, actorAuthUserId: ACTOR_ID });
    assert.equal(parsed.featureCode, null);
    assert.equal(parsed.limit, 50);
  });
});

describe("RequestAiOutputApprovalInputSchema", () => {
  test("rejects a missing actorLabel", () => {
    assert.throws(() => RequestAiOutputApprovalInputSchema.parse({ requestId: REQUEST_ID, actorAuthUserId: ACTOR_ID, actorLabel: "" }));
  });
});

describe("DecideAiOutputApprovalInputSchema", () => {
  test("rejects a decision outside approved/rejected", () => {
    assert.throws(() =>
      DecideAiOutputApprovalInputSchema.parse({ requestStepId: STEP_ID, decision: "accepted", actorAuthUserId: ACTOR_ID, actorLabel: "system" }),
    );
  });

  test("defaults reason to null", () => {
    const parsed = DecideAiOutputApprovalInputSchema.parse({ requestStepId: STEP_ID, decision: "approved", actorAuthUserId: ACTOR_ID, actorLabel: "system" });
    assert.equal(parsed.reason, null);
  });
});
