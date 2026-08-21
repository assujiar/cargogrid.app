import { test, describe } from "node:test";
import assert from "node:assert/strict";
import { parseN8nAllowlistedAction, parseN8nConnector, parseCreatedN8nConnector, CreateN8nConnectorInputSchema } from "./n8n-integration.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const CONNECTOR_ID = "323e4567-e89b-12d3-a456-426614174000";
const KEY_ID = "423e4567-e89b-12d3-a456-426614174000";
const ENDPOINT_ID = "523e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "623e4567-e89b-12d3-a456-426614174000";

describe("parseN8nAllowlistedAction", () => {
  test("maps snake_case columns to camelCase", () => {
    const action = parseN8nAllowlistedAction({ scope: "OPS:View", description: "Read shipment data", registered_by: "phase-09-foundation", created_at: "2026-08-21T00:00:00.000Z" });
    assert.equal(action.scope, "OPS:View");
    assert.equal(action.registeredBy, "phase-09-foundation");
  });
});

describe("parseN8nConnector", () => {
  test("maps snake_case columns, including the live-joined webhook endpoint fields", () => {
    const connector = parseN8nConnector({
      connector_id: CONNECTOR_ID,
      api_key_id: KEY_ID,
      tenant_id: TENANT_ID,
      name: "Shipment Notifier",
      key_prefix: "cgk_abcd1234",
      scopes: ["OPS:View"],
      status: "active",
      rate_limit_per_minute: 60,
      last_used_at: null,
      webhook_endpoint_id: ENDPOINT_ID,
      webhook_endpoint_url: "https://n8n.example.test/webhook/abc",
      webhook_endpoint_status: "active",
      created_at: "2026-08-21T00:00:00.000Z",
      updated_at: "2026-08-21T00:00:00.000Z",
    });
    assert.equal(connector.webhookEndpointUrl, "https://n8n.example.test/webhook/abc");
    assert.deepEqual(connector.scopes, ["OPS:View"]);
  });

  test("a connector with no linked webhook endpoint carries null fields, not a crash", () => {
    const connector = parseN8nConnector({
      connector_id: CONNECTOR_ID,
      api_key_id: KEY_ID,
      tenant_id: TENANT_ID,
      name: "Action-only Connector",
      key_prefix: "cgk_abcd1234",
      scopes: ["TKT:Create"],
      status: "active",
      rate_limit_per_minute: null,
      last_used_at: null,
      webhook_endpoint_id: null,
      webhook_endpoint_url: null,
      webhook_endpoint_status: null,
      created_at: "2026-08-21T00:00:00.000Z",
      updated_at: "2026-08-21T00:00:00.000Z",
    });
    assert.equal(connector.webhookEndpointId, null);
  });
});

describe("parseCreatedN8nConnector", () => {
  test("carries the one-time raw_key", () => {
    const created = parseCreatedN8nConnector({
      connector_id: CONNECTOR_ID,
      api_key_id: KEY_ID,
      tenant_id: TENANT_ID,
      name: "Shipment Notifier",
      key_prefix: "cgk_abcd1234",
      scopes: ["OPS:View"],
      status: "active",
      rate_limit_per_minute: 60,
      webhook_endpoint_id: null,
      created_at: "2026-08-21T00:00:00.000Z",
      raw_key: "cgk_abcd1234deadbeef",
    });
    assert.equal(created.rawKey, "cgk_abcd1234deadbeef");
  });
});

describe("CreateN8nConnectorInputSchema", () => {
  test("defaults webhookEndpointId and rateLimitPerMinute to null", () => {
    const parsed = CreateN8nConnectorInputSchema.parse({
      tenantId: TENANT_ID,
      name: "Shipment Notifier",
      scopes: ["OPS:View"],
      actorAuthUserId: ACTOR_ID,
      actorLabel: "tenant admin",
    });
    assert.equal(parsed.webhookEndpointId, null);
    assert.equal(parsed.rateLimitPerMinute, null);
  });

  test("rejects an empty scopes array", () => {
    assert.throws(() =>
      CreateN8nConnectorInputSchema.parse({
        tenantId: TENANT_ID,
        name: "Shipment Notifier",
        scopes: [],
        actorAuthUserId: ACTOR_ID,
        actorLabel: "tenant admin",
      }),
    );
  });
});
