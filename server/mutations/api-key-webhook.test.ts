import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  createApiKey,
  rotateApiKey,
  revokeApiKey,
  authenticateApiKey,
  registerWebhookEventType,
  registerWebhookEndpoint,
  rotateWebhookSecret,
  disableWebhookEndpoint,
  reenableWebhookEndpoint,
  queueWebhookDelivery,
  recordWebhookDeliveryAttempt,
  ApiKeyWebhookMutationError,
  type ApiKeyWebhookMutationRpcClient,
} from "./api-key-webhook.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const KEY_ID = "323e4567-e89b-12d3-a456-426614174000";
const ENDPOINT_ID = "423e4567-e89b-12d3-a456-426614174000";
const DELIVERY_ID = "523e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "623e4567-e89b-12d3-a456-426614174000";

const VALID_CREATED_KEY_ROW = {
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
};

const VALID_CREATED_ENDPOINT_ROW = {
  id: ENDPOINT_ID,
  tenant_id: TENANT_ID,
  url: "https://hooks.example-partner.test/a",
  status: "active",
  consecutive_failure_count: 0,
  created_at: "2026-07-19T00:00:00.000Z",
  raw_secret: "whsec_abcdef0123456789abcdef0123456789abcdef0123456789",
};

const VALID_DELIVERY_ROW = {
  id: DELIVERY_ID,
  tenant_id: TENANT_ID,
  webhook_endpoint_id: ENDPOINT_ID,
  event_type_code: "shipment.dispatched",
  event_id: DELIVERY_ID,
  payload: {},
  idempotency_key: "idem-1",
  status: "pending",
  attempts: 0,
  max_attempts: 5,
  next_attempt_at: "2026-07-19T00:00:00.000Z",
  created_at: "2026-07-19T00:00:00.000Z",
  updated_at: "2026-07-19T00:00:00.000Z",
};

function fakeClient(
  response: { data: unknown; error: { message: string } | null },
): ApiKeyWebhookMutationRpcClient & { calls: { fn: string; args: Record<string, unknown> }[] } {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];
  return {
    calls,
    async rpc(fn, args) {
      calls.push({ fn, args });
      return response;
    },
  };
}

describe("createApiKey", () => {
  test("calls create_api_key with the exact snake_case params and returns the raw key once", async () => {
    const client = fakeClient({ data: VALID_CREATED_KEY_ROW, error: null });
    const key = await createApiKey(client, { tenantId: TENANT_ID, name: "CI key", scopes: ["HRS:View personal data"], actorAuthUserId: ACTOR_ID, actorLabel: "tenant admin" });

    assert.deepEqual(client.calls[0]?.args, {
      p_tenant_id: TENANT_ID,
      p_name: "CI key",
      p_scopes: ["HRS:View personal data"],
      p_expires_at: null,
      p_rate_limit_per_minute: null,
      p_actor_auth_user_id: ACTOR_ID,
      p_actor_label: "tenant admin",
    });
    assert.ok(key.rawKey.startsWith("cgk_"));
  });

  test("wraps an api_key_scope_exceeds_actor_authority error", async () => {
    const client = fakeClient({ data: null, error: { message: "api_key_scope_exceeds_actor_authority: actor does not currently hold FIN:View cost (reason unknown_permission)" } });
    await assert.rejects(
      () => createApiKey(client, { tenantId: TENANT_ID, name: "x", scopes: ["FIN:View cost"], actorAuthUserId: ACTOR_ID, actorLabel: "tenant admin" }),
      (err: unknown) => {
        assert.ok(err instanceof ApiKeyWebhookMutationError);
        assert.equal(err.code, "api_key_scope_exceeds_actor_authority");
        return true;
      },
    );
  });
});

describe("rotateApiKey", () => {
  test("calls rotate_api_key with the exact snake_case params", async () => {
    const client = fakeClient({ data: { ...VALID_CREATED_KEY_ROW, id: "723e4567-e89b-12d3-a456-426614174000" }, error: null });
    await rotateApiKey(client, { keyId: KEY_ID, overlapMinutes: 60, actorAuthUserId: ACTOR_ID, actorLabel: "tenant admin" });

    assert.deepEqual(client.calls[0]?.args, {
      p_key_id: KEY_ID,
      p_overlap_minutes: 60,
      p_actor_auth_user_id: ACTOR_ID,
      p_actor_label: "tenant admin",
    });
  });

  test("wraps an api_key_not_active error", async () => {
    const client = fakeClient({ data: null, error: { message: "api_key_not_active: key is revoked, only an active key may be rotated" } });
    await assert.rejects(
      () => rotateApiKey(client, { keyId: KEY_ID, overlapMinutes: 60, actorAuthUserId: ACTOR_ID, actorLabel: "tenant admin" }),
      (err: unknown) => {
        assert.ok(err instanceof ApiKeyWebhookMutationError);
        assert.equal(err.code, "api_key_not_active");
        return true;
      },
    );
  });
});

describe("revokeApiKey", () => {
  test("calls revoke_api_key and returns the revoked row", async () => {
    const client = fakeClient({ data: { id: KEY_ID, tenant_id: TENANT_ID, name: "CI key", key_prefix: "cgk_abcdef01", scopes: [], status: "revoked", rate_limit_per_minute: null, expires_at: null, created_at: "2026-07-19T00:00:00.000Z" }, error: null });
    const key = await revokeApiKey(client, { keyId: KEY_ID, reason: "compromised", actorAuthUserId: ACTOR_ID, actorLabel: "tenant admin" });
    assert.equal(key.status, "revoked");
  });

  test("wraps an api_key_not_found error", async () => {
    const client = fakeClient({ data: null, error: { message: "api_key_not_found: no key 00000000-0000-0000-0000-000000000000" } });
    await assert.rejects(
      () => revokeApiKey(client, { keyId: KEY_ID, actorAuthUserId: ACTOR_ID, actorLabel: "tenant admin" }),
      (err: unknown) => {
        assert.ok(err instanceof ApiKeyWebhookMutationError);
        assert.equal(err.code, "api_key_not_found");
        return true;
      },
    );
  });
});

describe("authenticateApiKey", () => {
  test("calls authenticate_api_key with the raw key", async () => {
    const client = fakeClient({ data: { api_key_id: KEY_ID, tenant_id: TENANT_ID, scopes: ["HRS:View personal data"], rate_limit_per_minute: null }, error: null });
    const auth = await authenticateApiKey(client, { rawKey: "cgk_abcdef0123456789abcdef0123456789abcdef0123456789" });
    assert.deepEqual(client.calls[0]?.args, { p_raw_key: "cgk_abcdef0123456789abcdef0123456789abcdef0123456789" });
    assert.equal(auth.apiKeyId, KEY_ID);
  });

  test("wraps an api_key_revoked error", async () => {
    const client = fakeClient({ data: null, error: { message: "api_key_revoked: key has been revoked" } });
    await assert.rejects(
      () => authenticateApiKey(client, { rawKey: "cgk_deadbeef" }),
      (err: unknown) => {
        assert.ok(err instanceof ApiKeyWebhookMutationError);
        assert.equal(err.code, "api_key_revoked");
        return true;
      },
    );
  });
});

describe("registerWebhookEventType", () => {
  test("calls register_webhook_event_type with the exact snake_case params", async () => {
    const client = fakeClient({ data: { code: "shipment.dispatched", name: "Shipment Dispatched", owner_primitive_code: "API-WH", registered_by: "tester", created_at: "2026-07-19T00:00:00.000Z" }, error: null });
    await registerWebhookEventType(client, { code: "shipment.dispatched", name: "Shipment Dispatched", ownerPrimitiveCode: "API-WH", actorAuthUserId: ACTOR_ID, registeredBy: "tester" });
    assert.equal(client.calls[0]?.args.p_code, "shipment.dispatched");
  });

  test("wraps an insufficient_authority error", async () => {
    const client = fakeClient({ data: null, error: { message: "insufficient_authority: only Supreme Admin may register a webhook event type" } });
    await assert.rejects(
      () => registerWebhookEventType(client, { code: "x", name: "X", ownerPrimitiveCode: "API-WH", actorAuthUserId: ACTOR_ID, registeredBy: "tester" }),
      (err: unknown) => {
        assert.ok(err instanceof ApiKeyWebhookMutationError);
        assert.equal(err.code, "insufficient_authority");
        return true;
      },
    );
  });
});

describe("registerWebhookEndpoint", () => {
  test("calls register_webhook_endpoint and returns the raw secret once", async () => {
    const client = fakeClient({ data: VALID_CREATED_ENDPOINT_ROW, error: null });
    const endpoint = await registerWebhookEndpoint(client, { tenantId: TENANT_ID, url: "https://hooks.example-partner.test/a", eventTypeCodes: ["shipment.dispatched"], actorAuthUserId: ACTOR_ID, actorLabel: "tenant admin" });
    assert.ok(endpoint.rawSecret.startsWith("whsec_"));
  });

  test("wraps a webhook_unsafe_url_host error", async () => {
    const client = fakeClient({ data: null, error: { message: "webhook_unsafe_url_host: 127.0.0.1 resolves to a private/loopback/link-local literal, refusing to register" } });
    await assert.rejects(
      () => registerWebhookEndpoint(client, { tenantId: TENANT_ID, url: "https://127.0.0.1/a", eventTypeCodes: ["shipment.dispatched"], actorAuthUserId: ACTOR_ID, actorLabel: "tenant admin" }),
      (err: unknown) => {
        assert.ok(err instanceof ApiKeyWebhookMutationError);
        assert.equal(err.code, "webhook_unsafe_url_host");
        return true;
      },
    );
  });
});

describe("rotateWebhookSecret", () => {
  test("calls rotate_webhook_secret and returns a genuinely new raw secret", async () => {
    const client = fakeClient({ data: { ...VALID_CREATED_ENDPOINT_ROW, raw_secret: "whsec_ffffffffffffffffffffffffffffffffffffffffffffff" }, error: null });
    const endpoint = await rotateWebhookSecret(client, { endpointId: ENDPOINT_ID, actorAuthUserId: ACTOR_ID, actorLabel: "tenant admin" });
    assert.notEqual(endpoint.rawSecret, VALID_CREATED_ENDPOINT_ROW.raw_secret);
  });
});

describe("disableWebhookEndpoint / reenableWebhookEndpoint", () => {
  test("disable calls disable_webhook_endpoint with the exact snake_case params", async () => {
    const client = fakeClient({ data: { id: ENDPOINT_ID, tenant_id: TENANT_ID, url: "https://hooks.example-partner.test/a", status: "disabled", consecutive_failure_count: 10, created_at: "2026-07-19T00:00:00.000Z" }, error: null });
    const endpoint = await disableWebhookEndpoint(client, { endpointId: ENDPOINT_ID, reason: "manual pause", actorAuthUserId: ACTOR_ID, actorLabel: "tenant admin" });
    assert.equal(endpoint.status, "disabled");
  });

  test("reenable resets the failure counter", async () => {
    const client = fakeClient({ data: { id: ENDPOINT_ID, tenant_id: TENANT_ID, url: "https://hooks.example-partner.test/a", status: "active", consecutive_failure_count: 0, created_at: "2026-07-19T00:00:00.000Z" }, error: null });
    const endpoint = await reenableWebhookEndpoint(client, { endpointId: ENDPOINT_ID, actorAuthUserId: ACTOR_ID, actorLabel: "tenant admin" });
    assert.equal(endpoint.consecutiveFailureCount, 0);
  });
});

describe("queueWebhookDelivery", () => {
  test("calls queue_webhook_delivery and maps every returned delivery row", async () => {
    const client = fakeClient({ data: [VALID_DELIVERY_ROW], error: null });
    const deliveries = await queueWebhookDelivery(client, { tenantId: TENANT_ID, eventTypeCode: "shipment.dispatched", idempotencyKey: "idem-1", actorAuthUserId: ACTOR_ID, triggeredBy: "tenant admin" });
    assert.equal(deliveries.length, 1);
    assert.equal(deliveries[0]?.status, "pending");
  });

  test("returns an empty array rather than throwing when nobody is subscribed", async () => {
    const client = fakeClient({ data: [], error: null });
    const deliveries = await queueWebhookDelivery(client, { tenantId: TENANT_ID, eventTypeCode: "nobody.subscribes", idempotencyKey: "idem-2", actorAuthUserId: ACTOR_ID, triggeredBy: "tenant admin" });
    assert.deepEqual(deliveries, []);
  });

  test("wraps a webhook_unsafe_payload error", async () => {
    const client = fakeClient({ data: null, error: { message: "webhook_unsafe_payload: payload failed structural validation" } });
    await assert.rejects(
      () => queueWebhookDelivery(client, { tenantId: TENANT_ID, eventTypeCode: "shipment.dispatched", idempotencyKey: "idem-3", actorAuthUserId: ACTOR_ID, triggeredBy: "tenant admin" }),
      (err: unknown) => {
        assert.ok(err instanceof ApiKeyWebhookMutationError);
        assert.equal(err.code, "webhook_unsafe_payload");
        return true;
      },
    );
  });
});

describe("recordWebhookDeliveryAttempt", () => {
  test("calls record_webhook_delivery_attempt with the exact snake_case params", async () => {
    const client = fakeClient({ data: { ...VALID_DELIVERY_ROW, status: "delivered", attempts: 1 }, error: null });
    const delivery = await recordWebhookDeliveryAttempt(client, { deliveryId: DELIVERY_ID, status: "success", httpStatusCode: 200, actorAuthUserId: ACTOR_ID, actorLabel: "delivery worker" });

    assert.deepEqual(client.calls[0]?.args, {
      p_delivery_id: DELIVERY_ID,
      p_status: "success",
      p_http_status_code: 200,
      p_error_message: null,
      p_actor_auth_user_id: ACTOR_ID,
      p_actor_label: "delivery worker",
    });
    assert.equal(delivery.status, "delivered");
  });

  test("wraps a webhook_delivery_already_terminal error", async () => {
    const client = fakeClient({ data: null, error: { message: "webhook_delivery_already_terminal: delivery is already delivered, no further attempts may be recorded" } });
    await assert.rejects(
      () => recordWebhookDeliveryAttempt(client, { deliveryId: DELIVERY_ID, status: "failed", actorAuthUserId: ACTOR_ID, actorLabel: "delivery worker" }),
      (err: unknown) => {
        assert.ok(err instanceof ApiKeyWebhookMutationError);
        assert.equal(err.code, "webhook_delivery_already_terminal");
        return true;
      },
    );
  });
});
