import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  parseCustomerShipmentAlertSubscription,
  CustomerShipmentAlertSubscriptionCursorSchema,
  CustomerShipmentAlertCursorSchema,
  SubscribeCustomerShipmentAlertInputSchema,
  customerShipmentAlertNotificationTypeCode,
  CUSTOMER_SHIPMENT_ALERT_TYPES,
  CUSTOMER_SHIPMENT_ALERT_SUBSCRIPTION_STATUSES,
} from "./customer-shipment-alert.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const ACCOUNT_ID = "323e4567-e89b-12d3-a456-426614174000";
const SHIPMENT_ID = "423e4567-e89b-12d3-a456-426614174000";
const AUTH_USER_ID = "523e4567-e89b-12d3-a456-426614174000";
const SUBSCRIPTION_ID = "623e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "723e4567-e89b-12d3-a456-426614174000";

const SUBSCRIPTION_ROW = {
  id: SUBSCRIPTION_ID,
  tenant_id: TENANT_ID,
  account_id: ACCOUNT_ID,
  shipment_order_id: SHIPMENT_ID,
  auth_user_id: AUTH_USER_ID,
  alert_type: "milestone_delay",
  status: "active",
  created_at: "2026-08-16T00:00:00.000Z",
  updated_at: "2026-08-16T00:00:00.000Z",
  record_version: 1,
};

describe("parseCustomerShipmentAlertSubscription", () => {
  test("maps every column, camelCased", () => {
    const parsed = parseCustomerShipmentAlertSubscription(SUBSCRIPTION_ROW);
    assert.equal(parsed.id, SUBSCRIPTION_ID);
    assert.equal(parsed.shipmentOrderId, SHIPMENT_ID);
    assert.equal(parsed.alertType, "milestone_delay");
    assert.equal(parsed.status, "active");
  });

  test("rejects an unrecognized alert type", () => {
    assert.throws(() => parseCustomerShipmentAlertSubscription({ ...SUBSCRIPTION_ROW, alert_type: "not_a_real_type" }));
  });

  test("rejects an unrecognized status", () => {
    assert.throws(() => parseCustomerShipmentAlertSubscription({ ...SUBSCRIPTION_ROW, status: "revoked" }));
  });

  test("every real alert type is exactly the migration's 6-value set", () => {
    assert.deepEqual([...CUSTOMER_SHIPMENT_ALERT_TYPES], ["milestone_delay", "exception", "no_fresh_position", "tracking_restored", "delivery", "document_available"]);
  });

  test("status is exactly the migration's 2-value reversible toggle (no terminal state)", () => {
    assert.deepEqual([...CUSTOMER_SHIPMENT_ALERT_SUBSCRIPTION_STATUSES], ["active", "unsubscribed"]);
  });
});

describe("customerShipmentAlertNotificationTypeCode", () => {
  test("prefixes every alert type with 'shipment_alert_', matching the migration's own bootstrap insert", () => {
    assert.equal(customerShipmentAlertNotificationTypeCode("milestone_delay"), "shipment_alert_milestone_delay");
    assert.equal(customerShipmentAlertNotificationTypeCode("document_available"), "shipment_alert_document_available");
  });
});

describe("CustomerShipmentAlertSubscriptionCursorSchema", () => {
  test("accepts an empty cursor (first page)", () => {
    assert.doesNotThrow(() => CustomerShipmentAlertSubscriptionCursorSchema.parse({}));
  });

  test("rejects a cursorId supplied without cursorUpdatedAt", () => {
    assert.throws(() => CustomerShipmentAlertSubscriptionCursorSchema.parse({ cursorId: SUBSCRIPTION_ID }));
  });
});

describe("CustomerShipmentAlertCursorSchema", () => {
  test("accepts an empty cursor (first page)", () => {
    assert.doesNotThrow(() => CustomerShipmentAlertCursorSchema.parse({}));
  });

  test("rejects a cursorId supplied without cursorCreatedAt", () => {
    assert.throws(() => CustomerShipmentAlertCursorSchema.parse({ cursorId: SUBSCRIPTION_ID }));
  });
});

describe("SubscribeCustomerShipmentAlertInputSchema", () => {
  test("accepts a minimal valid input", () => {
    const parsed = SubscribeCustomerShipmentAlertInputSchema.parse({
      tenantId: TENANT_ID,
      shipmentOrderId: SHIPMENT_ID,
      alertType: "exception",
      actorAuthUserId: ACTOR_ID,
      actorLabel: "alpha-admin",
    });
    assert.equal(parsed.alertType, "exception");
  });

  test("rejects an unrecognized alertType", () => {
    assert.throws(() =>
      SubscribeCustomerShipmentAlertInputSchema.parse({
        tenantId: TENANT_ID,
        shipmentOrderId: SHIPMENT_ID,
        alertType: "not_a_real_type",
        actorAuthUserId: ACTOR_ID,
        actorLabel: "x",
      }),
    );
  });

  test("rejects an empty actorLabel", () => {
    assert.throws(() =>
      SubscribeCustomerShipmentAlertInputSchema.parse({
        tenantId: TENANT_ID,
        shipmentOrderId: SHIPMENT_ID,
        alertType: "delivery",
        actorAuthUserId: ACTOR_ID,
        actorLabel: "",
      }),
    );
  });
});
