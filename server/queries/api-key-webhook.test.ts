import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  listApiKeysForTenant,
  listWebhookEndpointsForTenant,
  apiKeyHasScope,
  computeWebhookSignature,
  verifyWebhookSignature,
  ApiKeyWebhookQueryError,
  type ApiKeyWebhookQueryRpcClient,
} from "./api-key-webhook.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const KEY_ID = "323e4567-e89b-12d3-a456-426614174000";
const ENDPOINT_ID = "423e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "523e4567-e89b-12d3-a456-426614174000";

function fakeClient(
  response: { data: unknown; error: { message: string } | null },
): ApiKeyWebhookQueryRpcClient & { calls: { fn: string; args: Record<string, unknown> }[] } {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];
  return {
    calls,
    async rpc(fn, args) {
      calls.push({ fn, args });
      return response;
    },
  };
}

describe("listApiKeysForTenant", () => {
  test("calls list_api_keys_for_tenant with the exact snake_case params and maps every row", async () => {
    const client = fakeClient({
      data: [
        {
          id: KEY_ID,
          tenant_id: TENANT_ID,
          name: "CI key",
          key_prefix: "cgk_abcdef01",
          scopes: ["HRS:View personal data"],
          status: "active",
          rate_limit_per_minute: null,
          expires_at: null,
          last_used_at: null,
          created_at: "2026-07-19T00:00:00.000Z",
          updated_at: "2026-07-19T00:00:00.000Z",
        },
      ],
      error: null,
    });
    const keys = await listApiKeysForTenant(client, { tenantId: TENANT_ID, actorAuthUserId: ACTOR_ID });
    assert.deepEqual(client.calls[0]?.args, { p_tenant_id: TENANT_ID, p_actor_auth_user_id: ACTOR_ID });
    assert.equal(keys.length, 1);
    assert.equal(keys[0]?.keyPrefix, "cgk_abcdef01");
  });

  test("wraps an insufficient_authority error", async () => {
    const client = fakeClient({ data: null, error: { message: "insufficient_authority: identity lacks authority to view API keys for tenant" } });
    await assert.rejects(() => listApiKeysForTenant(client, { tenantId: TENANT_ID, actorAuthUserId: ACTOR_ID }), ApiKeyWebhookQueryError);
  });
});

describe("listWebhookEndpointsForTenant", () => {
  test("maps every row", async () => {
    const client = fakeClient({
      data: [
        {
          id: ENDPOINT_ID,
          tenant_id: TENANT_ID,
          url: "https://hooks.example-partner.test/a",
          status: "active",
          consecutive_failure_count: 0,
          auto_disabled_at: null,
          disabled_reason: null,
          created_at: "2026-07-19T00:00:00.000Z",
          updated_at: "2026-07-19T00:00:00.000Z",
        },
      ],
      error: null,
    });
    const endpoints = await listWebhookEndpointsForTenant(client, { tenantId: TENANT_ID, actorAuthUserId: ACTOR_ID });
    assert.equal(endpoints.length, 1);
    assert.equal(endpoints[0]?.url, "https://hooks.example-partner.test/a");
  });

  test("wraps a database error into a typed error", async () => {
    const client = fakeClient({ data: null, error: { message: "connection reset" } });
    await assert.rejects(() => listWebhookEndpointsForTenant(client, { tenantId: TENANT_ID, actorAuthUserId: ACTOR_ID }), ApiKeyWebhookQueryError);
  });
});

describe("apiKeyHasScope", () => {
  test("returns the boolean result", async () => {
    const client = fakeClient({ data: true, error: null });
    const has = await apiKeyHasScope(client, KEY_ID, "HRS:View personal data");
    assert.deepEqual(client.calls[0]?.args, { p_api_key_id: KEY_ID, p_scope: "HRS:View personal data" });
    assert.equal(has, true);
  });

  test("rejects a non-boolean response rather than fabricating a decision", async () => {
    const client = fakeClient({ data: "true", error: null });
    await assert.rejects(() => apiKeyHasScope(client, KEY_ID, "HRS:View personal data"), ApiKeyWebhookQueryError);
  });
});

describe("computeWebhookSignature / verifyWebhookSignature", () => {
  test("computeWebhookSignature returns the string signature", async () => {
    const client = fakeClient({ data: "abcdef0123456789", error: null });
    const signature = await computeWebhookSignature(client, ENDPOINT_ID, "{}", 1753000000);
    assert.deepEqual(client.calls[0]?.args, { p_endpoint_id: ENDPOINT_ID, p_payload: "{}", p_timestamp: 1753000000 });
    assert.equal(signature, "abcdef0123456789");
  });

  test("verifyWebhookSignature returns the boolean result", async () => {
    const client = fakeClient({ data: false, error: null });
    const valid = await verifyWebhookSignature(client, ENDPOINT_ID, "{}", 1753000000, "wrong-signature");
    assert.deepEqual(client.calls[0]?.args, { p_endpoint_id: ENDPOINT_ID, p_payload: "{}", p_timestamp: 1753000000, p_signature: "wrong-signature" });
    assert.equal(valid, false);
  });

  test("wraps a webhook_endpoint_not_found error", async () => {
    const client = fakeClient({ data: null, error: { message: "webhook_endpoint_not_found: no endpoint 00000000-0000-0000-0000-000000000000" } });
    await assert.rejects(() => computeWebhookSignature(client, "00000000-0000-0000-0000-000000000000", "{}", 1753000000), ApiKeyWebhookQueryError);
  });
});
