import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  findAssignmentCandidates,
  getResourceAssignmentHistory,
  ResourceAssignmentQueryError,
  type ResourceAssignmentQueryRpcClient,
} from "./resource-assignment.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const ASSIGNMENT_ID = "323e4567-e89b-12d3-a456-426614174000";
const SHIPMENT_ID = "423e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "523e4567-e89b-12d3-a456-426614174000";
const RESOURCE_ID = "623e4567-e89b-12d3-a456-426614174000";

const ASSIGNMENT_ROW = {
  id: ASSIGNMENT_ID,
  tenant_id: TENANT_ID,
  shipment_order_id: SHIPMENT_ID,
  role: "vendor",
  resource_id: RESOURCE_ID,
  resource_snapshot: { code: "VEND-1", name: "Contoso Trucking" },
  status: "active",
  is_current: true,
  effective_from: "2026-07-27T00:00:00.000Z",
  effective_to: null,
  reason: null,
  superseded_by_id: null,
  record_version: 1,
  created_by: "rep",
  created_at: "2026-07-27T00:00:00.000Z",
  updated_at: "2026-07-27T00:00:00.000Z",
};

function fakeRpcClient(response: { data: unknown; error: { message: string } | null }): ResourceAssignmentQueryRpcClient {
  return { rpc: () => Promise.resolve(response) } as unknown as ResourceAssignmentQueryRpcClient;
}

describe("findAssignmentCandidates", () => {
  test("maps every row in the returned array", async () => {
    const client = fakeRpcClient({ data: [{ id: RESOURCE_ID, code: "VEND-1", name: "Contoso Trucking" }], error: null });
    const candidates = await findAssignmentCandidates(client, { tenantId: TENANT_ID, role: "vendor", actorAuthUserId: ACTOR_ID });
    assert.equal(candidates.length, 1);
    assert.equal(candidates[0]?.code, "VEND-1");
  });

  test("returns an empty array (never an error) when no active candidates exist yet", async () => {
    const client = fakeRpcClient({ data: [], error: null });
    const candidates = await findAssignmentCandidates(client, { tenantId: TENANT_ID, role: "driver", actorAuthUserId: ACTOR_ID });
    assert.deepEqual(candidates, []);
  });

  test("wraps an rpc error", async () => {
    const client = fakeRpcClient({ data: null, error: { message: "boom" } });
    await assert.rejects(
      () => findAssignmentCandidates(client, { tenantId: TENANT_ID, role: "vendor", actorAuthUserId: ACTOR_ID }),
      (err: unknown) => err instanceof ResourceAssignmentQueryError,
    );
  });
});

describe("getResourceAssignmentHistory", () => {
  test("maps every row in the returned array", async () => {
    const client = fakeRpcClient({ data: [ASSIGNMENT_ROW], error: null });
    const history = await getResourceAssignmentHistory(client, { shipmentOrderId: SHIPMENT_ID, actorAuthUserId: ACTOR_ID });
    assert.equal(history.length, 1);
    assert.equal(history[0]?.role, "vendor");
  });

  test("returns an empty array (never an error) for a shipment with no assignments yet", async () => {
    const client = fakeRpcClient({ data: [], error: null });
    const history = await getResourceAssignmentHistory(client, { shipmentOrderId: SHIPMENT_ID, actorAuthUserId: ACTOR_ID });
    assert.deepEqual(history, []);
  });

  test("wraps an rpc error", async () => {
    const client = fakeRpcClient({ data: null, error: { message: "boom" } });
    await assert.rejects(
      () => getResourceAssignmentHistory(client, { shipmentOrderId: SHIPMENT_ID, actorAuthUserId: ACTOR_ID }),
      (err: unknown) => err instanceof ResourceAssignmentQueryError,
    );
  });
});
