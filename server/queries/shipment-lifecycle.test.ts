import { test, describe } from "node:test";
import assert from "node:assert/strict";
import { getShipmentStatusHistory, ShipmentLifecycleQueryError, type ShipmentLifecycleQueryRpcClient } from "./shipment-lifecycle.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const TRANSITION_ID = "323e4567-e89b-12d3-a456-426614174000";
const SHIPMENT_ID = "423e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "523e4567-e89b-12d3-a456-426614174000";

const TRANSITION_ROW = {
  id: TRANSITION_ID,
  tenant_id: TENANT_ID,
  shipment_order_id: SHIPMENT_ID,
  from_status: "confirmed",
  to_status: "planned",
  reason: null,
  evidence_ref: null,
  idempotency_key: "idem-1",
  actor_auth_user_id: ACTOR_ID,
  actor_label: "rep",
  occurred_at: "2026-07-27T00:00:00.000Z",
};

function fakeRpcClient(response: { data: unknown; error: { message: string } | null }): ShipmentLifecycleQueryRpcClient {
  return { rpc: () => Promise.resolve(response) } as unknown as ShipmentLifecycleQueryRpcClient;
}

describe("getShipmentStatusHistory", () => {
  test("maps every row in the returned array", async () => {
    const client = fakeRpcClient({ data: [TRANSITION_ROW], error: null });
    const history = await getShipmentStatusHistory(client, { shipmentOrderId: SHIPMENT_ID, actorAuthUserId: ACTOR_ID });
    assert.equal(history.length, 1);
    assert.equal(history[0]?.toStatus, "planned");
  });

  test("returns an empty array (never an error) for a shipment with no recorded transitions yet", async () => {
    const client = fakeRpcClient({ data: [], error: null });
    const history = await getShipmentStatusHistory(client, { shipmentOrderId: SHIPMENT_ID, actorAuthUserId: ACTOR_ID });
    assert.deepEqual(history, []);
  });

  test("wraps an rpc error", async () => {
    const client = fakeRpcClient({ data: null, error: { message: "boom" } });
    await assert.rejects(
      () => getShipmentStatusHistory(client, { shipmentOrderId: SHIPMENT_ID, actorAuthUserId: ACTOR_ID }),
      (err: unknown) => err instanceof ShipmentLifecycleQueryError,
    );
  });
});
