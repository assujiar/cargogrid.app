import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  dispatchShipmentOrder,
  bulkDispatchShipmentOrders,
  BasicDispatchMutationError,
  type BasicDispatchMutationRpcClient,
} from "./basic-dispatch.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const SHIPMENT_ID = "323e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "423e4567-e89b-12d3-a456-426614174000";
const COMMAND_ID = "523e4567-e89b-12d3-a456-426614174000";
const SHIPMENT_ID_2 = "623e4567-e89b-12d3-a456-426614174000";

function fakeRpcClient(response: { data: unknown; error: { message: string } | null }): {
  client: BasicDispatchMutationRpcClient;
  calls: { fn: string; args: Record<string, unknown> }[];
} {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];
  const client = {
    async rpc(fn: string, args: Record<string, unknown>) {
      calls.push({ fn, args });
      return response;
    },
  } as unknown as BasicDispatchMutationRpcClient;
  return { client, calls };
}

const COMMAND_ROW = {
  id: COMMAND_ID,
  tenant_id: TENANT_ID,
  shipment_order_id: SHIPMENT_ID,
  command: "dispatch",
  readiness_snapshot: { is_ready: true, blockers: [] },
  idempotency_key: "idem-disp-1",
  actor_auth_user_id: ACTOR_ID,
  actor_label: "rep",
  dispatched_at: "2026-07-27T09:00:00.000Z",
  created_at: "2026-07-27T09:00:00.000Z",
};

describe("dispatchShipmentOrder", () => {
  test("calls dispatch_shipment_order with the exact snake_case params", async () => {
    const { client, calls } = fakeRpcClient({ data: COMMAND_ROW, error: null });
    const command = await dispatchShipmentOrder(client, {
      shipmentOrderId: SHIPMENT_ID,
      expectedVersion: 1,
      idempotencyKey: "idem-disp-1",
      actorAuthUserId: ACTOR_ID,
      actorLabel: "rep",
    });
    assert.equal(calls[0]?.fn, "dispatch_shipment_order");
    assert.deepEqual(calls[0]?.args, {
      p_shipment_order_id: SHIPMENT_ID,
      p_expected_version: 1,
      p_idempotency_key: "idem-disp-1",
      p_actor_auth_user_id: ACTOR_ID,
      p_actor_label: "rep",
    });
    assert.equal(command.readinessSnapshot.isReady, true);
  });

  test("classifies dispatch_not_ready for a blocked shipment", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "dispatch_not_ready: shipment order X is not ready to dispatch ([{...}])" } });
    await assert.rejects(
      () =>
        dispatchShipmentOrder(client, {
          shipmentOrderId: SHIPMENT_ID,
          expectedVersion: 1,
          idempotencyKey: "idem-disp-1",
          actorAuthUserId: ACTOR_ID,
          actorLabel: "rep",
        }),
      (err: unknown) => {
        assert.ok(err instanceof BasicDispatchMutationError);
        assert.equal(err.code, "dispatch_not_ready");
        return true;
      },
    );
  });

  test("classifies insufficient_authority for an OPS:View-only actor", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "insufficient_authority: identity lacks OPS:Edit" } });
    await assert.rejects(
      () =>
        dispatchShipmentOrder(client, {
          shipmentOrderId: SHIPMENT_ID,
          expectedVersion: 1,
          idempotencyKey: "idem-disp-1",
          actorAuthUserId: ACTOR_ID,
          actorLabel: "viewer",
        }),
      (err: unknown) => {
        assert.ok(err instanceof BasicDispatchMutationError);
        assert.equal(err.code, "insufficient_authority");
        return true;
      },
    );
  });
});

describe("bulkDispatchShipmentOrders", () => {
  test("calls bulk_dispatch_shipment_orders with the exact snake_case params and maps every per-record result row", async () => {
    const { client, calls } = fakeRpcClient({
      data: [
        { shipment_order_id: SHIPMENT_ID, success: true, error_code: null, error_message: null },
        { shipment_order_id: SHIPMENT_ID_2, success: false, error_code: "dispatch_not_ready", error_message: "dispatch_not_ready: not ready" },
      ],
      error: null,
    });
    const results = await bulkDispatchShipmentOrders(client, {
      shipmentOrderIds: [SHIPMENT_ID, SHIPMENT_ID_2],
      idempotencyKeyPrefix: "idem-bulk",
      actorAuthUserId: ACTOR_ID,
      actorLabel: "rep",
    });
    assert.equal(calls[0]?.fn, "bulk_dispatch_shipment_orders");
    assert.deepEqual(calls[0]?.args, {
      p_shipment_order_ids: [SHIPMENT_ID, SHIPMENT_ID_2],
      p_idempotency_key_prefix: "idem-bulk",
      p_actor_auth_user_id: ACTOR_ID,
      p_actor_label: "rep",
    });
    assert.equal(results.length, 2);
    assert.equal(results[0]?.success, true);
    assert.equal(results[1]?.errorCode, "dispatch_not_ready");
  });

  test("classifies bulk_too_large for a >50 item batch", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "bulk_too_large: at most 50 shipment orders may be dispatched in one bulk call, got 51" } });
    const ids = Array.from({ length: 50 }, () => SHIPMENT_ID);
    await assert.rejects(
      () => bulkDispatchShipmentOrders(client, { shipmentOrderIds: ids, idempotencyKeyPrefix: "idem-bulk", actorAuthUserId: ACTOR_ID, actorLabel: "rep" }),
      (err: unknown) => {
        assert.ok(err instanceof BasicDispatchMutationError);
        assert.equal(err.code, "bulk_too_large");
        return true;
      },
    );
  });

  test("wraps a non-array response as invalid_response", async () => {
    const { client } = fakeRpcClient({ data: {}, error: null });
    await assert.rejects(
      () => bulkDispatchShipmentOrders(client, { shipmentOrderIds: [SHIPMENT_ID], idempotencyKeyPrefix: "idem-bulk", actorAuthUserId: ACTOR_ID, actorLabel: "rep" }),
      (err: unknown) => {
        assert.ok(err instanceof BasicDispatchMutationError);
        assert.equal(err.code, "invalid_response");
        return true;
      },
    );
  });
});
