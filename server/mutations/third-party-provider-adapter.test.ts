import { test } from "node:test";
import assert from "node:assert/strict";
import {
  registerThirdPartyProviderConnection,
  rotateThirdPartyProviderWebhookSecret,
  updateThirdPartyProviderPollCursor,
  ingestThirdPartyProviderWebhookEvent,
  ThirdPartyProviderAdapterMutationError,
  type ThirdPartyProviderAdapterMutationRpcClient,
} from "./third-party-provider-adapter.ts";

const CONN_ID = "723e4567-e89b-12d3-a456-426614174001";
const TENANT_ID = "723e4567-e89b-12d3-a456-426614174002";
const ACTOR_ID = "723e4567-e89b-12d3-a456-426614174003";

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
