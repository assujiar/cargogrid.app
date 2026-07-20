import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  parseApiKey,
  parseCreatedApiKey,
  parseAuthenticatedApiKey,
  parseWebhookEventType,
  parseWebhookEndpoint,
  parseCreatedWebhookEndpoint,
  parseWebhookDelivery,
  CreateApiKeyInputSchema,
  RegisterWebhookEndpointInputSchema,
} from "./api-key-webhook.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const KEY_ID = "323e4567-e89b-12d3-a456-426614174000";
const ENDPOINT_ID = "423e4567-e89b-12d3-a456-426614174000";
const DELIVERY_ID = "523e4567-e89b-12d3-a456-426614174000";
const RECORD_ID = "623e4567-e89b-12d3-a456-426614174000";

describe("parseApiKey", () => {
  test("maps a raw snake_case row to the camelCase contract shape, never carrying key_hash", () => {
    const key = parseApiKey({
      id: KEY_ID,
      tenant_id: TENANT_ID,
      name: "CI key",
      key_prefix: "cgk_abcdef01",
      scopes: ["HRS:View personal data"],
      status: "active",
      rate_limit_per_minute: 60,
      expires_at: null,
      last_used_at: null,
      created_at: "2026-07-19T00:00:00.000Z",
      updated_at: "2026-07-19T00:00:00.000Z",
    });
    assert.equal(key.keyPrefix, "cgk_abcdef01");
    assert.ok(!("keyHash" in key));
  });
});

describe("parseCreatedApiKey", () => {
  test("includes the one-time raw_key", () => {
    const key = parseCreatedApiKey({
      id: KEY_ID,
      tenant_id: TENANT_ID,
      name: "CI key",
      key_prefix: "cgk_abcdef01",
      scopes: ["HRS:View personal data"],
      status: "active",
      rate_limit_per_minute: null,
      expires_at: null,
      created_at: "2026-07-19T00:00:00.000Z",
      raw_key: "cgk_abcdef0123456789abcdef0123456789abcdef0123456789",
    });
    assert.ok(key.rawKey.startsWith("cgk_"));
  });
});

describe("parseAuthenticatedApiKey", () => {
  test("maps a raw snake_case row to the camelCase contract shape", () => {
    const auth = parseAuthenticatedApiKey({
      api_key_id: KEY_ID,
      tenant_id: TENANT_ID,
      scopes: ["HRS:View personal data"],
      rate_limit_per_minute: 60,
    });
    assert.equal(auth.apiKeyId, KEY_ID);
    assert.deepEqual(auth.scopes, ["HRS:View personal data"]);
  });
});

describe("parseWebhookEventType", () => {
  test("maps a raw snake_case row to the camelCase contract shape", () => {
    const type = parseWebhookEventType({
      code: "shipment.dispatched",
      name: "Shipment Dispatched",
      owner_primitive_code: "API-WH",
      registered_by: "platform-core-foundation",
      created_at: "2026-07-19T00:00:00.000Z",
    });
    assert.equal(type.code, "shipment.dispatched");
  });
});

describe("parseWebhookEndpoint", () => {
  test("maps a raw snake_case row to the camelCase contract shape, never carrying secret_value", () => {
    const endpoint = parseWebhookEndpoint({
      id: ENDPOINT_ID,
      tenant_id: TENANT_ID,
      url: "https://hooks.example-partner.test/a",
      status: "active",
      consecutive_failure_count: 0,
      auto_disabled_at: null,
      disabled_reason: null,
      created_at: "2026-07-19T00:00:00.000Z",
      updated_at: "2026-07-19T00:00:00.000Z",
    });
    assert.equal(endpoint.status, "active");
    assert.ok(!("secretValue" in endpoint));
  });
});

describe("parseCreatedWebhookEndpoint", () => {
  test("includes the one-time raw_secret", () => {
    const endpoint = parseCreatedWebhookEndpoint({
      id: ENDPOINT_ID,
      tenant_id: TENANT_ID,
      url: "https://hooks.example-partner.test/a",
      status: "active",
      consecutive_failure_count: 0,
      created_at: "2026-07-19T00:00:00.000Z",
      raw_secret: "whsec_abcdef0123456789abcdef0123456789abcdef0123456789",
    });
    assert.ok(endpoint.rawSecret.startsWith("whsec_"));
  });
});

describe("parseWebhookDelivery", () => {
  test("maps a raw snake_case row to the camelCase contract shape", () => {
    const delivery = parseWebhookDelivery({
      id: DELIVERY_ID,
      tenant_id: TENANT_ID,
      webhook_endpoint_id: ENDPOINT_ID,
      event_type_code: "shipment.dispatched",
      event_id: RECORD_ID,
      payload: { shipment_id: "9001" },
      idempotency_key: "idem-1",
      status: "pending",
      attempts: 0,
      max_attempts: 5,
      next_attempt_at: "2026-07-19T00:00:00.000Z",
      created_at: "2026-07-19T00:00:00.000Z",
      updated_at: "2026-07-19T00:00:00.000Z",
    });
    assert.equal(delivery.status, "pending");
    assert.deepEqual(delivery.payload, { shipment_id: "9001" });
  });
});

describe("CreateApiKeyInputSchema", () => {
  test("defaults expiresAt/rateLimitPerMinute to null", () => {
    const parsed = CreateApiKeyInputSchema.parse({
      tenantId: TENANT_ID,
      name: "CI key",
      scopes: ["HRS:View personal data"],
      actorAuthUserId: KEY_ID,
      actorLabel: "tenant admin",
    });
    assert.equal(parsed.expiresAt, null);
    assert.equal(parsed.rateLimitPerMinute, null);
  });

  test("rejects an empty scopes array", () => {
    assert.throws(() =>
      CreateApiKeyInputSchema.parse({
        tenantId: TENANT_ID,
        name: "CI key",
        scopes: [],
        actorAuthUserId: KEY_ID,
        actorLabel: "tenant admin",
      }),
    );
  });
});

describe("RegisterWebhookEndpointInputSchema", () => {
  test("rejects an empty eventTypeCodes array", () => {
    assert.throws(() =>
      RegisterWebhookEndpointInputSchema.parse({
        tenantId: TENANT_ID,
        url: "https://hooks.example-partner.test/a",
        eventTypeCodes: [],
        actorAuthUserId: KEY_ID,
        actorLabel: "tenant admin",
      }),
    );
  });

  test("parses a well-formed input", () => {
    const parsed = RegisterWebhookEndpointInputSchema.parse({
      tenantId: TENANT_ID,
      url: "https://hooks.example-partner.test/a",
      eventTypeCodes: ["shipment.dispatched"],
      actorAuthUserId: KEY_ID,
      actorLabel: "tenant admin",
    });
    assert.deepEqual(parsed.eventTypeCodes, ["shipment.dispatched"]);
  });
});
