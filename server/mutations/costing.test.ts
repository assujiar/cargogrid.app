import { test, describe } from "node:test";
import assert from "node:assert/strict";
import { requestCosting, submitCostingResponse, reviseCostingRequest, cancelCostingRequest, CostingMutationError, type CostingMutationRpcClient } from "./costing.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const REQUEST_ID = "323e4567-e89b-12d3-a456-426614174000";
const OPPORTUNITY_ID = "423e4567-e89b-12d3-a456-426614174000";
const COMPONENT_ID = "523e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "623e4567-e89b-12d3-a456-426614174000";

const VALID_REQUEST_ROW = {
  id: REQUEST_ID,
  tenant_id: TENANT_ID,
  opportunity_id: OPPORTUNITY_ID,
  source_opportunity_version: 1,
  requirements_snapshot: {},
  status: "pending",
  due_at: null,
  assignee_user_id: null,
  cancel_reason: null,
  revised_from_id: null,
  owner_user_id: null,
  org_unit_id: null,
  record_version: 1,
  created_by: "tester",
  created_at: "2026-07-24T00:00:00.000Z",
  updated_at: "2026-07-24T00:00:00.000Z",
};

describe("requestCosting", () => {
  test("calls request_costing with the exact snake_case params, mapping components", async () => {
    const calls: { fn: string; args: Record<string, unknown> }[] = [];
    const client = {
      async rpc(fn: string, args: Record<string, unknown>) {
        calls.push({ fn, args });
        return { data: VALID_REQUEST_ROW, error: null };
      },
    } as unknown as CostingMutationRpcClient;

    const request = await requestCosting(client, {
      opportunityId: OPPORTUNITY_ID,
      components: [{ code: "ocean_freight", description: "Ocean freight leg" }],
      actorAuthUserId: ACTOR_ID,
      createdBy: "tester",
    });

    assert.equal(calls[0]?.fn, "request_costing");
    assert.deepEqual(calls[0]?.args.p_components, [{ code: "ocean_freight", description: "Ocean freight leg", quantity: null, unit: null }]);
    assert.equal(request.status, "pending");
  });

  test("classifies requirements_incomplete", async () => {
    const client = {
      async rpc() {
        return { data: null, error: { message: "requirements_incomplete: opportunity x is missing origin, destination" } };
      },
    } as unknown as CostingMutationRpcClient;

    await assert.rejects(
      () => requestCosting(client, { opportunityId: OPPORTUNITY_ID, actorAuthUserId: ACTOR_ID, createdBy: "tester" }),
      (err: unknown) => {
        assert.ok(err instanceof CostingMutationError);
        assert.equal((err as CostingMutationError).code, "requirements_incomplete");
        return true;
      },
    );
  });
});

describe("submitCostingResponse", () => {
  test("classifies an unrecognized error message as mutation_failed", async () => {
    const client = {
      async rpc() {
        return { data: null, error: { message: "some unexpected database error" } };
      },
    } as unknown as CostingMutationRpcClient;

    await assert.rejects(
      () =>
        submitCostingResponse(client, {
          requestId: REQUEST_ID,
          sourceType: "internal",
          currency: "IDR",
          components: [{ requestComponentId: COMPONENT_ID, amount: 100 }],
          actorAuthUserId: ACTOR_ID,
          actorLabel: "tester",
        }),
      (err: unknown) => {
        assert.ok(err instanceof CostingMutationError);
        assert.equal((err as CostingMutationError).code, "mutation_failed");
        return true;
      },
    );
  });
});

describe("reviseCostingRequest", () => {
  test("classifies no_new_version", async () => {
    const client = {
      async rpc() {
        return { data: null, error: { message: "no_new_version: opportunity x has not changed since costing request y" } };
      },
    } as unknown as CostingMutationRpcClient;

    await assert.rejects(
      () => reviseCostingRequest(client, { requestId: REQUEST_ID, actorAuthUserId: ACTOR_ID, createdBy: "tester" }),
      (err: unknown) => {
        assert.ok(err instanceof CostingMutationError);
        assert.equal((err as CostingMutationError).code, "no_new_version");
        return true;
      },
    );
  });
});

describe("cancelCostingRequest", () => {
  test("calls cancel_costing_request with the exact snake_case params", async () => {
    const calls: { fn: string; args: Record<string, unknown> }[] = [];
    const client = {
      async rpc(fn: string, args: Record<string, unknown>) {
        calls.push({ fn, args });
        return { data: { ...VALID_REQUEST_ROW, status: "cancelled", cancel_reason: "No longer needed" }, error: null };
      },
    } as unknown as CostingMutationRpcClient;

    const request = await cancelCostingRequest(client, { requestId: REQUEST_ID, expectedVersion: 1, reason: "No longer needed", actorAuthUserId: ACTOR_ID, actorLabel: "tester" });
    assert.equal(calls[0]?.fn, "cancel_costing_request");
    assert.equal(request.status, "cancelled");
  });
});
