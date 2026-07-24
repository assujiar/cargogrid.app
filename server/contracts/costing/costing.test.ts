import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  RequestCostingInputSchema,
  SubmitCostingResponseInputSchema,
  parseCostingRequest,
  parseCostingRequestComponent,
  parseCostingResponse,
  parseCostingResponseComponent,
} from "./costing.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const REQUEST_ID = "323e4567-e89b-12d3-a456-426614174000";
const OPPORTUNITY_ID = "423e4567-e89b-12d3-a456-426614174000";
const COMPONENT_ID = "523e4567-e89b-12d3-a456-426614174000";
const RESPONSE_ID = "623e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "723e4567-e89b-12d3-a456-426614174000";

describe("RequestCostingInputSchema", () => {
  test("defaults components to an empty array and dueAt to null", () => {
    const parsed = RequestCostingInputSchema.parse({
      opportunityId: OPPORTUNITY_ID,
      actorAuthUserId: ACTOR_ID,
      createdBy: "tester",
    });
    assert.deepEqual(parsed.components, []);
    assert.equal(parsed.dueAt, null);
  });
});

describe("SubmitCostingResponseInputSchema", () => {
  test("rejects a malformed currency code", () => {
    assert.throws(() =>
      SubmitCostingResponseInputSchema.parse({
        requestId: REQUEST_ID,
        sourceType: "internal",
        currency: "idr",
        components: [{ requestComponentId: COMPONENT_ID, amount: 100 }],
        actorAuthUserId: ACTOR_ID,
        actorLabel: "tester",
      }),
    );
  });

  test("requires at least one component", () => {
    assert.throws(() =>
      SubmitCostingResponseInputSchema.parse({
        requestId: REQUEST_ID,
        sourceType: "internal",
        currency: "IDR",
        components: [],
        actorAuthUserId: ACTOR_ID,
        actorLabel: "tester",
      }),
    );
  });
});

describe("parseCostingRequest", () => {
  test("maps a raw snake_case row to the camelCase contract shape", () => {
    const request = parseCostingRequest({
      id: REQUEST_ID,
      tenant_id: TENANT_ID,
      opportunity_id: OPPORTUNITY_ID,
      source_opportunity_version: 1,
      requirements_snapshot: { service_type: "freight_forwarding" },
      status: "pending",
      due_at: null,
      assignee_user_id: null,
      cancel_reason: null,
      revised_from_id: null,
      owner_user_id: ACTOR_ID,
      org_unit_id: null,
      record_version: 1,
      created_by: "tester",
      created_at: "2026-07-24T00:00:00.000Z",
      updated_at: "2026-07-24T00:00:00.000Z",
    });
    assert.equal(request.status, "pending");
    assert.equal(request.requirementsSnapshot.serviceType, "freight_forwarding");
  });
});

describe("parseCostingRequestComponent", () => {
  test("maps a raw snake_case row to the camelCase contract shape", () => {
    const component = parseCostingRequestComponent({
      id: COMPONENT_ID,
      tenant_id: TENANT_ID,
      costing_request_id: REQUEST_ID,
      component_code: "ocean_freight",
      description: "Ocean freight leg",
      quantity: "1",
      unit: "container",
      created_at: "2026-07-24T00:00:00.000Z",
    });
    assert.equal(component.componentCode, "ocean_freight");
    assert.equal(component.quantity, 1);
  });
});

describe("parseCostingResponse", () => {
  test("coerces a string numeric total_amount and preserves masking metadata", () => {
    const response = parseCostingResponse({
      id: RESPONSE_ID,
      tenant_id: TENANT_ID,
      costing_request_id: REQUEST_ID,
      source_type: "internal",
      vendor_ref: null,
      currency: "IDR",
      total_amount: "17500000.00",
      cost_masked: false,
      effective_at: "2026-07-24T00:00:00.000Z",
      expiry_at: null,
      is_expired: false,
      submitted_by: "tester",
      created_at: "2026-07-24T00:00:00.000Z",
    });
    assert.equal(response.totalAmount, 17500000);
    assert.equal(response.costMasked, false);
  });

  test("maps a masked response with null currency/total_amount", () => {
    const response = parseCostingResponse({
      id: RESPONSE_ID,
      tenant_id: TENANT_ID,
      costing_request_id: REQUEST_ID,
      source_type: "internal",
      vendor_ref: null,
      currency: null,
      total_amount: null,
      cost_masked: true,
      effective_at: "2026-07-24T00:00:00.000Z",
      expiry_at: null,
      is_expired: false,
      submitted_by: "tester",
      created_at: "2026-07-24T00:00:00.000Z",
    });
    assert.equal(response.costMasked, true);
    assert.equal(response.totalAmount, null);
  });
});

describe("parseCostingResponseComponent", () => {
  test("maps a raw snake_case row to the camelCase contract shape", () => {
    const component = parseCostingResponseComponent({
      id: "823e4567-e89b-12d3-a456-426614174000",
      tenant_id: TENANT_ID,
      costing_response_id: RESPONSE_ID,
      costing_request_component_id: COMPONENT_ID,
      amount: "15000000.00",
      created_at: "2026-07-24T00:00:00.000Z",
    });
    assert.equal(component.amount, 15000000);
  });
});
