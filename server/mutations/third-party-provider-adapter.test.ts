import { test } from "node:test";
import assert from "node:assert/strict";
import {
  registerThirdPartyProviderConnection,
  rotateThirdPartyProviderWebhookSecret,
  updateThirdPartyProviderPollCursor,
  ingestThirdPartyProviderWebhookEvent,
  disableThirdPartyProviderConnection,
  reenableThirdPartyProviderConnection,
  ThirdPartyProviderAdapterMutationError,
  type ThirdPartyProviderAdapterMutationRpcClient,
} from "./third-party-provider-adapter.ts";

const CONN_ID = "723e4567-e89b-12d3-a456-426614174001";
const TENANT_ID = "723e4567-e89b-12d3-a456-426614174002";
const ACTOR_ID = "723e4567-e89b-12d3-a456-426614174003";

function connectionRow(overrides: Record<string, unknown> = {}): Record<string, unknown> {
  return {
    id: CONN_ID,
    tenant_id: TENANT_ID,
    provider_code: "acmegps",
    integration_mode: "webhook",
    poll_cursor: null,
    status: "disabled",
    consecutive_failure_count: 10,
    last_successful_ingest_at: null,
    auto_disabled_at: "2026-08-03T04:00:00.000Z",
    disabled_reason: "consecutive_failure_threshold_exceeded",
    created_at: "2026-08-01T00:00:00.000Z",
    updated_at: "2026-08-03T04:00:00.000Z",
    ...overrides,
  };
}

function fakeClient(response: { data: unknown; error: { message: string } | null }): ThirdPartyProviderAdapterMutationRpcClient {
  return {
    rpc: async (_fn: string, _args: Record<string, unknown>) => response,
  } as unknown as ThirdPartyProviderAdapterMutationRpcClient;
}

test("registerThirdPartyProviderConnection parses a real registration result", async () => {
  const client = fakeClient({
    data: [{ connection_id: CONN_ID, provider_code: "acmegps", integration_mode: "webhook", raw_webhook_secret: "tpws_abc", status: "active" }],
    error: null,
  });
  const result = await registerThirdPartyProviderConnection(client, {
    tenantId: TENANT_ID,
    providerCode: "acmegps",
    integrationMode: "webhook",
    actorAuthUserId: ACTOR_ID,
    actorLabel: "admin",
  });
  assert.equal(result.rawWebhookSecret, "tpws_abc");
});

test("registerThirdPartyProviderConnection throws a classified error for insufficient authority", async () => {
  const client = fakeClient({ data: null, error: { message: "insufficient_authority: identity x lacks OPS:Create" } });
  await assert.rejects(
    () =>
      registerThirdPartyProviderConnection(client, {
        tenantId: TENANT_ID,
        providerCode: "acmegps",
        integrationMode: "webhook",
        actorAuthUserId: ACTOR_ID,
        actorLabel: "viewer",
      }),
    (err: unknown) => err instanceof ThirdPartyProviderAdapterMutationError && err.code === "insufficient_authority",
  );
});

test("rotateThirdPartyProviderWebhookSecret parses the new raw secret", async () => {
  const client = fakeClient({ data: [{ connection_id: CONN_ID, raw_webhook_secret: "tpws_new" }], error: null });
  const result = await rotateThirdPartyProviderWebhookSecret(client, { connectionId: CONN_ID, actorAuthUserId: ACTOR_ID, actorLabel: "admin" });
  assert.equal(result.rawWebhookSecret, "tpws_new");
});

test("updateThirdPartyProviderPollCursor throws a classified error for a webhook-mode connection", async () => {
  const client = fakeClient({ data: null, error: { message: "not_a_poll_connection: x is a webhook connection" } });
  await assert.rejects(
    () => updateThirdPartyProviderPollCursor(client, { connectionId: CONN_ID, cursor: { page: 2 }, actorAuthUserId: ACTOR_ID, actorLabel: "admin" }),
    (err: unknown) => err instanceof ThirdPartyProviderAdapterMutationError && err.code === "not_a_poll_connection",
  );
});

test("ingestThirdPartyProviderWebhookEvent parses an ok result", async () => {
  const client = fakeClient({ data: [{ ingest_status: "ok", report_id: CONN_ID }], error: null });
  const result = await ingestThirdPartyProviderWebhookEvent(client, {
    connectionId: CONN_ID,
    clientKey: "client-a",
    rawPayload: '{"event_id":"evt-1"}',
    timestamp: 1_754_000_000,
    signature: "deadbeef",
  });
  assert.equal(result.ingestStatus, "ok");
});

test("ingestThirdPartyProviderWebhookEvent parses a quarantined result without throwing", async () => {
  const client = fakeClient({ data: [{ ingest_status: "quarantined", report_id: null }], error: null });
  const result = await ingestThirdPartyProviderWebhookEvent(client, {
    connectionId: CONN_ID,
    clientKey: "client-a",
    rawPayload: '{"event_id":"evt-1"}',
    timestamp: 1_754_000_000,
    signature: "deadbeef",
  });
  assert.equal(result.ingestStatus, "quarantined");
  assert.equal(result.reportId, null);
});

test("disableThirdPartyProviderConnection parses the disabled connection row", async () => {
  const client = fakeClient({ data: connectionRow({ disabled_reason: "manual disable" }), error: null });
  const result = await disableThirdPartyProviderConnection(client, { connectionId: CONN_ID, reason: "manual disable", actorAuthUserId: ACTOR_ID, actorLabel: "admin" });
  assert.equal(result.status, "disabled");
  assert.equal(result.disabledReason, "manual disable");
});

test("disableThirdPartyProviderConnection throws a classified error for a connection that does not exist", async () => {
  const client = fakeClient({ data: null, error: { message: "connection_not_found: 723e4567-e89b-12d3-a456-426614174001" } });
  await assert.rejects(
    () => disableThirdPartyProviderConnection(client, { connectionId: CONN_ID, reason: null, actorAuthUserId: ACTOR_ID, actorLabel: "admin" }),
    (err: unknown) => err instanceof ThirdPartyProviderAdapterMutationError && err.code === "connection_not_found",
  );
});

test("reenableThirdPartyProviderConnection parses the reset, re-activated connection row", async () => {
  const client = fakeClient({
    data: connectionRow({ status: "active", consecutive_failure_count: 0, auto_disabled_at: null, disabled_reason: null }),
    error: null,
  });
  const result = await reenableThirdPartyProviderConnection(client, { connectionId: CONN_ID, actorAuthUserId: ACTOR_ID, actorLabel: "admin" });
  assert.equal(result.status, "active");
  assert.equal(result.consecutiveFailureCount, 0);
  assert.equal(result.autoDisabledAt, null);
  assert.equal(result.disabledReason, null);
});

test("reenableThirdPartyProviderConnection throws a classified error for insufficient authority", async () => {
  const client = fakeClient({ data: null, error: { message: "insufficient_authority: identity x lacks OPS:Edit" } });
  await assert.rejects(
    () => reenableThirdPartyProviderConnection(client, { connectionId: CONN_ID, actorAuthUserId: ACTOR_ID, actorLabel: "viewer" }),
    (err: unknown) => err instanceof ThirdPartyProviderAdapterMutationError && err.code === "insufficient_authority",
  );
});
