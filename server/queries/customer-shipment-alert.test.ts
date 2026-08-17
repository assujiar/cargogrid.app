import { test, describe } from "node:test";
import assert from "node:assert/strict";
import { listCustomerShipmentAlertSubscriptions, listCustomerShipmentAlerts, CustomerShipmentAlertQueryError, type CustomerShipmentAlertQueryClient } from "./customer-shipment-alert.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const ACCOUNT_ID = "323e4567-e89b-12d3-a456-426614174000";
const SHIPMENT_ID = "423e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "523e4567-e89b-12d3-a456-426614174000";
const SUBSCRIPTION_ID = "623e4567-e89b-12d3-a456-426614174000";
const CONFIG_VERSION_ID = "723e4567-e89b-12d3-a456-426614174000";
const NOTIFICATION_ID = "823e4567-e89b-12d3-a456-426614174000";

const SUBSCRIPTION_ROW = {
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

const NOTIFICATION_ROW = {
  id: NOTIFICATION_ID,
  tenant_id: TENANT_ID,
  config_version_id: CONFIG_VERSION_ID,
  notification_type_code: "shipment_alert_milestone_delay",
  recipient_auth_user_id: ACTOR_ID,
  requested_channel: "in_app",
  effective_channel: "in_app",
  locale: "en",
  subject: "Shipment delayed",
  body: "Your shipment is running behind schedule.",
  context: { shipmentOrderId: SHIPMENT_ID },
  status: "sent",
  dedupe_key: "milestone-delay-1",
  triggered_by_auth_user_id: null,
  triggered_by: "system",
  read_at: null,
  created_at: "2026-08-16T00:00:00.000Z",
  updated_at: "2026-08-16T00:00:00.000Z",
};

function fakeRpcClient(response: { data: unknown; error: { message: string } | null }): {
  client: CustomerShipmentAlertQueryClient;
  calls: { fn: string; args: Record<string, unknown> }[];
} {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];
  const client = {
    async rpc(fn: string, args: Record<string, unknown>) {
      calls.push({ fn, args });
      return response;
    },
  } as unknown as CustomerShipmentAlertQueryClient;
  return { client, calls };
}

describe("listCustomerShipmentAlertSubscriptions", () => {
  test("defaults filters/cursor to null and limit to 50", async () => {
    const { client, calls } = fakeRpcClient({ data: [SUBSCRIPTION_ROW], error: null });
    const result = await listCustomerShipmentAlertSubscriptions(client, TENANT_ID, ACTOR_ID);
    assert.equal(result.length, 1);
    assert.equal(result[0]?.alertType, "milestone_delay");
    assert.deepEqual(calls[0]?.args, {
      p_tenant_id: TENANT_ID,
      p_actor_auth_user_id: ACTOR_ID,
      p_shipment_order_id: null,
      p_cursor_updated_at: null,
      p_cursor_id: null,
      p_limit: 50,
    });
  });

  test("forwards a shipmentOrderId filter and cursor overrides", async () => {
    const { client, calls } = fakeRpcClient({ data: [], error: null });
    await listCustomerShipmentAlertSubscriptions(client, TENANT_ID, ACTOR_ID, { shipmentOrderId: SHIPMENT_ID, cursorUpdatedAt: "2026-08-16T00:00:00.000Z", cursorId: SUBSCRIPTION_ID, limit: 10 });
    assert.deepEqual(calls[0]?.args, {
      p_tenant_id: TENANT_ID,
      p_actor_auth_user_id: ACTOR_ID,
      p_shipment_order_id: SHIPMENT_ID,
      p_cursor_updated_at: "2026-08-16T00:00:00.000Z",
      p_cursor_id: SUBSCRIPTION_ID,
      p_limit: 10,
    });
  });

  test("returns an empty array (never throws) for a deny-by-default response", async () => {
    const { client } = fakeRpcClient({ data: [], error: null });
    const result = await listCustomerShipmentAlertSubscriptions(client, TENANT_ID, ACTOR_ID);
    assert.deepEqual(result, []);
  });

  test("classifies an unrecognized error prefix as query_failed", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "some_unexpected_db_error: boom" } });
    await assert.rejects(
      () => listCustomerShipmentAlertSubscriptions(client, TENANT_ID, ACTOR_ID),
      (err: unknown) => {
        assert.ok(err instanceof CustomerShipmentAlertQueryError);
        assert.equal(err.code, "query_failed");
        return true;
      },
    );
  });
});

describe("listCustomerShipmentAlerts", () => {
  test("defaults filters/cursor to null, unreadOnly to false, and limit to 50", async () => {
    const { client, calls } = fakeRpcClient({ data: [NOTIFICATION_ROW], error: null });
    const result = await listCustomerShipmentAlerts(client, TENANT_ID, ACTOR_ID);
    assert.equal(result.length, 1);
    assert.equal(result[0]?.notificationTypeCode, "shipment_alert_milestone_delay");
    assert.deepEqual(calls[0]?.args, {
      p_tenant_id: TENANT_ID,
      p_actor_auth_user_id: ACTOR_ID,
      p_shipment_order_id: null,
      p_unread_only: false,
      p_cursor_created_at: null,
      p_cursor_id: null,
      p_limit: 50,
    });
  });

  test("forwards a shipmentOrderId filter, unreadOnly, and cursor overrides", async () => {
    const { client, calls } = fakeRpcClient({ data: [], error: null });
    await listCustomerShipmentAlerts(client, TENANT_ID, ACTOR_ID, {
      shipmentOrderId: SHIPMENT_ID,
      unreadOnly: true,
      cursorCreatedAt: "2026-08-16T00:00:00.000Z",
      cursorId: NOTIFICATION_ID,
      limit: 10,
    });
    assert.deepEqual(calls[0]?.args, {
      p_tenant_id: TENANT_ID,
      p_actor_auth_user_id: ACTOR_ID,
      p_shipment_order_id: SHIPMENT_ID,
      p_unread_only: true,
      p_cursor_created_at: "2026-08-16T00:00:00.000Z",
      p_cursor_id: NOTIFICATION_ID,
      p_limit: 10,
    });
  });

  test("returns an empty array (never throws) for a deny-by-default response", async () => {
    const { client } = fakeRpcClient({ data: [], error: null });
    const result = await listCustomerShipmentAlerts(client, TENANT_ID, ACTOR_ID);
    assert.deepEqual(result, []);
  });

  test("classifies an unrecognized error prefix as query_failed", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "some_unexpected_db_error: boom" } });
    await assert.rejects(
      () => listCustomerShipmentAlerts(client, TENANT_ID, ACTOR_ID),
      (err: unknown) => {
        assert.ok(err instanceof CustomerShipmentAlertQueryError);
        assert.equal(err.code, "query_failed");
        return true;
      },
    );
  });
});
