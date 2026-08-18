import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  requestCustomerShipmentOrderChange,
  respondToCustomerShipmentOrderChangeRequest,
  CustomerShipmentOrderMutationError,
  type CustomerShipmentOrderMutationRpcClient,
} from "./customer-shipment-order.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const SHIPMENT_ID = "323e4567-e89b-12d3-a456-426614174000";
const ACCOUNT_ID = "423e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "523e4567-e89b-12d3-a456-426614174000";
const REQUEST_ID = "623e4567-e89b-12d3-a456-426614174000";

const ROW = {
  id: REQUEST_ID,
  tenant_id: TENANT_ID,
  account_id: ACCOUNT_ID,
  shipment_order_id: SHIPMENT_ID,
  requested_by_auth_user_id: ACTOR_ID,
  request_type: "reschedule",
  details: "Please move pickup",
  status: "submitted",
  idempotency_key: "change-1",
  record_version: 1,
  created_at: "2026-08-16T00:00:00.000Z",
  updated_at: "2026-08-16T00:00:00.000Z",
  staff_response: null,
  staff_responded_by: null,
  staff_responded_at: null,
};

function fakeRpcClient(response: { data: unknown; error: { message: string } | null }): {
  client: CustomerShipmentOrderMutationRpcClient;
  calls: { fn: string; args: Record<string, unknown> }[];
} {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];
  const client = {
    async rpc(fn: string, args: Record<string, unknown>) {
      calls.push({ fn, args });
      return response;
    },
  } as unknown as CustomerShipmentOrderMutationRpcClient;
  return { client, calls };
}

describe("requestCustomerShipmentOrderChange", () => {
  test("passes exact param names, defaulting idempotencyKey to null", async () => {
    const { client, calls } = fakeRpcClient({ data: [ROW], error: null });
    const result = await requestCustomerShipmentOrderChange(client, {
      tenantId: TENANT_ID,
      shipmentOrderId: SHIPMENT_ID,
      requestType: "reschedule",
      details: "Please move pickup",
      actorAuthUserId: ACTOR_ID,
      actorLabel: "alpha-admin",
    });
    assert.equal(result.status, "submitted");
    assert.deepEqual(calls[0], {
      fn: "request_customer_shipment_order_change",
      args: {
        p_tenant_id: TENANT_ID,
        p_shipment_order_id: SHIPMENT_ID,
        p_request_type: "reschedule",
        p_details: "Please move pickup",
        p_idempotency_key: null,
        p_actor_auth_user_id: ACTOR_ID,
        p_actor_label: "alpha-admin",
      },
    });
  });

  test("rejects an empty details string at the schema layer before any RPC call", async () => {
    const { client, calls } = fakeRpcClient({ data: null, error: null });
    await assert.rejects(() =>
      requestCustomerShipmentOrderChange(client, { tenantId: TENANT_ID, shipmentOrderId: SHIPMENT_ID, requestType: "cancel", details: "", actorAuthUserId: ACTOR_ID, actorLabel: "x" }),
    );
    assert.equal(calls.length, 0);
  });

  test("classifies shipment_order_not_found for a forged/out-of-scope shipment order", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "shipment_order_not_found: no permitted shipment order exists for x" } });
    await assert.rejects(
      () => requestCustomerShipmentOrderChange(client, { tenantId: TENANT_ID, shipmentOrderId: SHIPMENT_ID, requestType: "other", details: "x", actorAuthUserId: ACTOR_ID, actorLabel: "x" }),
      (err: unknown) => {
        assert.ok(err instanceof CustomerShipmentOrderMutationError);
        assert.equal(err.code, "shipment_order_not_found");
        return true;
      },
    );
  });
});

describe("respondToCustomerShipmentOrderChangeRequest", () => {
  test("passes exact param names", async () => {
    const { client, calls } = fakeRpcClient({ data: [{ ...ROW, status: "acknowledged", staff_response: "Looking into it" }], error: null });
    const result = await respondToCustomerShipmentOrderChangeRequest(client, {
      changeRequestId: REQUEST_ID,
      expectedVersion: 1,
      toStatus: "acknowledged",
      staffResponse: "Looking into it",
      actorAuthUserId: ACTOR_ID,
      actorLabel: "ops-staff",
    });
    assert.equal(result.status, "acknowledged");
    assert.deepEqual(calls[0], {
      fn: "respond_to_customer_shipment_order_change_request",
      args: { p_change_request_id: REQUEST_ID, p_expected_version: 1, p_to_status: "acknowledged", p_staff_response: "Looking into it", p_actor_auth_user_id: ACTOR_ID, p_actor_label: "ops-staff" },
    });
  });

  test("rejects an empty staffResponse at the schema layer before any RPC call", async () => {
    const { client, calls } = fakeRpcClient({ data: null, error: null });
    await assert.rejects(() =>
      respondToCustomerShipmentOrderChangeRequest(client, { changeRequestId: REQUEST_ID, expectedVersion: 1, toStatus: "resolved", staffResponse: "", actorAuthUserId: ACTOR_ID, actorLabel: "x" }),
    );
    assert.equal(calls.length, 0);
  });

  test("classifies insufficient_authority for a staff actor lacking OPS:Edit", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "insufficient_authority: identity x lacks OPS:Edit (no_granting_role) for tenant y" } });
    await assert.rejects(
      () =>
        respondToCustomerShipmentOrderChangeRequest(client, { changeRequestId: REQUEST_ID, expectedVersion: 1, toStatus: "resolved", staffResponse: "Resolved", actorAuthUserId: ACTOR_ID, actorLabel: "x" }),
      (err: unknown) => {
        assert.ok(err instanceof CustomerShipmentOrderMutationError);
        assert.equal(err.code, "insufficient_authority");
        return true;
      },
    );
  });

  test("classifies stale_version", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "stale_version: change request x expected version 1 but found 2" } });
    await assert.rejects(
      () =>
        respondToCustomerShipmentOrderChangeRequest(client, { changeRequestId: REQUEST_ID, expectedVersion: 1, toStatus: "rejected", staffResponse: "No longer possible", actorAuthUserId: ACTOR_ID, actorLabel: "x" }),
      (err: unknown) => {
        assert.ok(err instanceof CustomerShipmentOrderMutationError);
        assert.equal(err.code, "stale_version");
        return true;
      },
    );
  });
});
