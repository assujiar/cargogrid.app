import { test, describe } from "node:test";
import assert from "node:assert/strict";
import { parseWebhookDelivery, parseWebhookDeliveryRow, parseWebhookDeliveryDispatchInfo, ListWebhookDeliveriesForTenantInputSchema, SendTestWebhookDeliveryInputSchema } from "./webhook-management.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const DELIVERY_ID = "323e4567-e89b-12d3-a456-426614174000";
const ENDPOINT_ID = "423e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "523e4567-e89b-12d3-a456-426614174000";

describe("parseWebhookDelivery", () => {
  test("maps snake_case columns to camelCase, including the joined endpoint_url", () => {
    const delivery = parseWebhookDelivery({
      id: DELIVERY_ID,
      webhook_endpoint_id: ENDPOINT_ID,
      endpoint_url: "https://example.test/webhook",
      event_type_code: "shipment.status_changed",
      status: "dead_letter",
      attempts: 5,
      max_attempts: 5,
      next_attempt_at: null,
      created_at: "2026-08-21T00:00:00.000Z",
      updated_at: "2026-08-21T00:00:00.000Z",
    });
    assert.equal(delivery.endpointUrl, "https://example.test/webhook");
    assert.equal(delivery.status, "dead_letter");
  });
});

describe("parseWebhookDeliveryRow", () => {
  test("maps the bare app.webhook_deliveries row shape -- no endpoint_url", () => {
    const row = parseWebhookDeliveryRow({
      id: DELIVERY_ID,
      webhook_endpoint_id: ENDPOINT_ID,
      event_type_code: "webhook.test",
      status: "pending",
      attempts: 0,
      max_attempts: 1,
      next_attempt_at: "2026-08-21T00:00:00.000Z",
      created_at: "2026-08-21T00:00:00.000Z",
      updated_at: "2026-08-21T00:00:00.000Z",
    });
    assert.equal(row.webhookEndpointId, ENDPOINT_ID);
    assert.equal(row.status, "pending");
  });
});

describe("parseWebhookDeliveryDispatchInfo", () => {
  test("maps the worker's own minimal dispatch read -- never a signing secret field", () => {
    const info = parseWebhookDeliveryDispatchInfo({
      delivery_id: DELIVERY_ID,
      tenant_id: TENANT_ID,
      status: "pending",
      event_type_code: "webhook.test",
      payload: { hello: "world" },
      webhook_endpoint_id: ENDPOINT_ID,
      endpoint_url: "https://example.test/webhook",
      endpoint_status: "active",
    });
    assert.equal(info.endpointUrl, "https://example.test/webhook");
    assert.deepEqual(info.payload, { hello: "world" });
    assert.equal("secretValue" in info, false);
  });
});

describe("ListWebhookDeliveriesForTenantInputSchema", () => {
  test("defaults status to null and limit to 50", () => {
    const parsed = ListWebhookDeliveriesForTenantInputSchema.parse({ tenantId: TENANT_ID, actorAuthUserId: ACTOR_ID });
    assert.equal(parsed.status, null);
    assert.equal(parsed.limit, 50);
  });

  test("rejects a limit above 200", () => {
    assert.throws(() => ListWebhookDeliveriesForTenantInputSchema.parse({ tenantId: TENANT_ID, actorAuthUserId: ACTOR_ID, limit: 201 }));
  });

  // ISS-2026-147 item 2: the per-connector filter must default to null, so the tenant-wide
  // list every pre-existing caller relies on is unchanged unless a caller opts in.
  test("defaults webhookEndpointId to null so the unfiltered tenant-wide list stays the default", () => {
    const parsed = ListWebhookDeliveriesForTenantInputSchema.parse({ tenantId: TENANT_ID, actorAuthUserId: ACTOR_ID });
    assert.equal(parsed.webhookEndpointId, null);
  });

  test("accepts a uuid webhookEndpointId and rejects a non-uuid one", () => {
    assert.equal(ListWebhookDeliveriesForTenantInputSchema.parse({ tenantId: TENANT_ID, actorAuthUserId: ACTOR_ID, webhookEndpointId: ENDPOINT_ID }).webhookEndpointId, ENDPOINT_ID);
    assert.throws(() => ListWebhookDeliveriesForTenantInputSchema.parse({ tenantId: TENANT_ID, actorAuthUserId: ACTOR_ID, webhookEndpointId: "not-a-uuid" }));
  });
});

describe("SendTestWebhookDeliveryInputSchema", () => {
  test("requires a real endpointId and actorAuthUserId", () => {
    const parsed = SendTestWebhookDeliveryInputSchema.parse({ endpointId: ENDPOINT_ID, actorAuthUserId: ACTOR_ID, actorLabel: "tenant admin" });
    assert.equal(parsed.endpointId, ENDPOINT_ID);
  });

  test("rejects a non-UUID endpointId", () => {
    assert.throws(() => SendTestWebhookDeliveryInputSchema.parse({ endpointId: "not-a-uuid", actorAuthUserId: ACTOR_ID, actorLabel: "tenant admin" }));
  });
});
