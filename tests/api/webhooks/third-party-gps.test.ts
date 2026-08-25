/** RGL-402 (Penetration Test Evidence): route-level HTTP-layer coverage for POST /api/webhooks/third-party-gps/[connectionId]. */
import { test, describe } from "node:test";
import assert from "node:assert/strict";
import { installRpcFetchStub } from "../v1/support/rpc-fetch-stub.ts";
import { POST } from "../../../app/api/webhooks/third-party-gps/[connectionId]/route.ts";

function post(connectionId: string, headers: Record<string, string> = {}, body = '{"test":1}') {
  return POST(
    new Request(`http://localhost/api/webhooks/third-party-gps/${encodeURIComponent(connectionId)}`, {
      method: "POST",
      headers: { "content-type": "application/json", "x-webhook-signature": "deadbeef", "x-webhook-timestamp": String(Date.now()), ...headers },
      body,
    }),
    { params: Promise.resolve({ connectionId }) },
  );
}

describe("POST /api/webhooks/third-party-gps/[connectionId]", () => {
  test("a non-UUID connectionId -> 400 invalid, never reaches the ingest RPC (live-forced: was an uncaught 500)", async () => {
    const stub = installRpcFetchStub({});
    try {
      const response = await post("1' OR '1'='1");
      assert.equal(response.status, 400);
      const body = (await response.json()) as { ingestStatus: string };
      assert.equal(body.ingestStatus, "invalid");
      assert.equal(stub.calls.some((c) => c.fn === "ingest_third_party_provider_webhook_event"), false);
    } finally {
      stub.restore();
    }
  });

  test("a path-traversal-shaped connectionId -> 400 invalid, never reaches the ingest RPC", async () => {
    const stub = installRpcFetchStub({});
    try {
      const response = await post("../../etc/passwd");
      assert.equal(response.status, 400);
      assert.equal(stub.calls.some((c) => c.fn === "ingest_third_party_provider_webhook_event"), false);
    } finally {
      stub.restore();
    }
  });

  test("a well-formed UUID connectionId with a valid ingest outcome -> 200 (fix does not regress the happy path)", async () => {
    const stub = installRpcFetchStub({
      ingest_third_party_provider_webhook_event: { data: { ingest_status: "ok", report_id: "11111111-1111-4111-8111-111111111111" } },
    });
    try {
      const response = await post("22222222-2222-4222-8222-222222222222");
      assert.equal(response.status, 200);
      const body = (await response.json()) as { ingestStatus: string; reportId: string | null };
      assert.equal(body.ingestStatus, "ok");
      assert.equal(body.reportId, "11111111-1111-4111-8111-111111111111");
    } finally {
      stub.restore();
    }
  });

  test("a well-formed UUID connectionId with an invalid-signature outcome -> 401 (denial mapping still correct)", async () => {
    const stub = installRpcFetchStub({
      ingest_third_party_provider_webhook_event: { data: { ingest_status: "invalid", report_id: null } },
    });
    try {
      const response = await post("22222222-2222-4222-8222-222222222222");
      assert.equal(response.status, 401);
    } finally {
      stub.restore();
    }
  });
});
