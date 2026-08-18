import { test, describe } from "node:test";
import assert from "node:assert/strict";
import { subscribeCustomerShipmentAlert, unsubscribeCustomerShipmentAlert, CustomerShipmentAlertMutationError, type CustomerShipmentAlertMutationRpcClient } from "./customer-shipment-alert.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const ACCOUNT_ID = "323e4567-e89b-12d3-a456-426614174000";
const SHIPMENT_ID = "423e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "523e4567-e89b-12d3-a456-426614174000";
const SUBSCRIPTION_ID = "623e4567-e89b-12d3-a456-426614174000";

const ROW = {
  id: SUBSCRIPTION_ID,
  tenant_id: TENANT_ID,
  account_id: ACCOUNT_ID,
  shipment_order_id: SHIPMENT_ID,
  auth_user_id: ACTOR_ID,
  alert_type: "milestone_delay",
  status: "active",
  created_at: "2026-08-16T00:00:00.000Z",
  updated_at: "2026-08-16T00:00:00.000Z",
  record_version: 1,
};

function fakeRpcClient(response: { data: unknown; error: { message: string } | null }): {
  client: CustomerShipmentAlertMutationRpcClient;
  calls: { fn: string; args: Record<string, unknown> }[];
} {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];
  const client = {
    async rpc(fn: string, args: Record<string, unknown>) {
      calls.push({ fn, args });
      return response;
    },
  } as unknown as CustomerShipmentAlertMutationRpcClient;
  return { client, calls };
}

describe("subscribeCustomerShipmentAlert", () => {
  test("passes exact param names -- no idempotency key parameter exists (natural-key upsert)", async () => {
    const { client, calls } = fakeRpcClient({ data: [ROW], error: null });
    const result = await subscribeCustomerShipmentAlert(client, {
      tenantId: TENANT_ID,
      shipmentOrderId: SHIPMENT_ID,
      alertType: "milestone_delay",
      actorAuthUserId: ACTOR_ID,
      actorLabel: "alpha-admin",
    });
    assert.equal(result.status, "active");
    assert.deepEqual(calls[0], {
      fn: "subscribe_customer_shipment_alert",
      args: {
        p_tenant_id: TENANT_ID,
        p_shipment_order_id: SHIPMENT_ID,
        p_alert_type: "milestone_delay",
        p_actor_auth_user_id: ACTOR_ID,
        p_actor_label: "alpha-admin",
      },
    });
  });

  test("rejects an unrecognized alertType at the schema layer before any RPC call", async () => {
    const { client, calls } = fakeRpcClient({ data: null, error: null });
    await assert.rejects(() =>
      subscribeCustomerShipmentAlert(client, { tenantId: TENANT_ID, shipmentOrderId: SHIPMENT_ID, alertType: "not_a_real_type" as never, actorAuthUserId: ACTOR_ID, actorLabel: "x" }),
    );
    assert.equal(calls.length, 0);
  });

  test("classifies shipment_order_not_found for a forged/out-of-scope shipment order", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "shipment_order_not_found: no permitted shipment order exists for x" } });
    await assert.rejects(
      () => subscribeCustomerShipmentAlert(client, { tenantId: TENANT_ID, shipmentOrderId: SHIPMENT_ID, alertType: "exception", actorAuthUserId: ACTOR_ID, actorLabel: "x" }),
      (err: unknown) => {
        assert.ok(err instanceof CustomerShipmentAlertMutationError);
        assert.equal(err.code, "shipment_order_not_found");
        return true;
      },
    );
  });
});

describe("unsubscribeCustomerShipmentAlert", () => {
  test("passes exact param names", async () => {
    const { client, calls } = fakeRpcClient({ data: [{ ...ROW, status: "unsubscribed" }], error: null });
    const result = await unsubscribeCustomerShipmentAlert(client, {
      tenantId: TENANT_ID,
      shipmentOrderId: SHIPMENT_ID,
      alertType: "milestone_delay",
      actorAuthUserId: ACTOR_ID,
      actorLabel: "alpha-admin",
    });
    assert.equal(result.status, "unsubscribed");
    assert.deepEqual(calls[0], {
      fn: "unsubscribe_customer_shipment_alert",
      args: {
        p_tenant_id: TENANT_ID,
        p_shipment_order_id: SHIPMENT_ID,
        p_alert_type: "milestone_delay",
        p_actor_auth_user_id: ACTOR_ID,
        p_actor_label: "alpha-admin",
      },
    });
  });

  test("classifies invalid_alert_type", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "invalid_alert_type: x is not a recognized shipment alert type" } });
    await assert.rejects(
      () => unsubscribeCustomerShipmentAlert(client, { tenantId: TENANT_ID, shipmentOrderId: SHIPMENT_ID, alertType: "delivery", actorAuthUserId: ACTOR_ID, actorLabel: "x" }),
      (err: unknown) => {
        assert.ok(err instanceof CustomerShipmentAlertMutationError);
        assert.equal(err.code, "invalid_alert_type");
        return true;
      },
    );
  });

  test("succeeds even when no prior subscription existed (idempotent both ways)", async () => {
    const { client } = fakeRpcClient({ data: [{ ...ROW, status: "unsubscribed" }], error: null });
    const result = await unsubscribeCustomerShipmentAlert(client, { tenantId: TENANT_ID, shipmentOrderId: SHIPMENT_ID, alertType: "document_available", actorAuthUserId: ACTOR_ID, actorLabel: "x" });
    assert.equal(result.status, "unsubscribed");
  });
});
