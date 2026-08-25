/** HDN-376 (API Compatibility Audit, ISS-2026-147 item 1): route-level HTTP-layer coverage for GET /api/v1/status. */
import { test, describe } from "node:test";
import assert from "node:assert/strict";
import { installRpcFetchStub, okAuthRow, deniedAuthRow } from "./support/rpc-fetch-stub.ts";
import { GET } from "../../../app/api/v1/status/route.ts";

describe("GET /api/v1/status", () => {
  test("missing Authorization header -> 401 unauthenticated, never reaches the gateway RPC", async () => {
    const stub = installRpcFetchStub({});
    try {
      const response = await GET(new Request("http://localhost/api/v1/status"));
      assert.equal(response.status, 401);
      const body = (await response.json()) as { error: { code: string } };
      assert.equal(body.error.code, "unauthenticated");
      assert.equal(response.headers.get("x-cargogrid-request-id") !== null, true);
      assert.equal(stub.calls.some((c) => c.fn === "authenticate_and_authorize_api_request"), false);
    } finally {
      stub.restore();
    }
  });

  test("gateway denies with unauthenticated (a present but unrecognized key) -> 401, logs actorType anon not api_key", async () => {
    // RGL-401: a key that never resolves to a real app.api_keys row means
    // authResult.apiKeyId is null (deniedAuthRow's own default) -- logging actorType
    // "api_key" with a null apiKeyId violates app.api_logs' own
    // api_logs_actor_shape_check CHECK constraint ("api_key" requires a non-null
    // api_key_id), which crashed this entire request with an uncaught 500 in
    // production (live-forced against the real hosted project, not merely reasoned
    // about) instead of the intended clean 401. This is distinct from the
    // "missing Authorization header" case above, which never reaches the gateway RPC
    // at all and already correctly logged "anon".
    const stub = installRpcFetchStub({
      authenticate_and_authorize_api_request: { data: deniedAuthRow("unauthenticated") },
    });
    try {
      const response = await GET(new Request("http://localhost/api/v1/status", { headers: { authorization: "Bearer cgk_totallybogusnonexistentkey" } }));
      assert.equal(response.status, 401);
      const body = (await response.json()) as { error: { code: string } };
      assert.equal(body.error.code, "unauthenticated");
      const denialLogs = stub.calls.filter((c) => c.fn === "record_api_request" && c.body.p_result === "failure");
      assert.equal(denialLogs.length, 1);
      assert.equal(denialLogs[0]?.body.p_actor_type, "anon");
      assert.equal(denialLogs[0]?.body.p_api_key_id, null);
    } finally {
      stub.restore();
    }
  });

  test("gateway denies with rate_limited -> 429 with retry-after header, logs actorType api_key (the key WAS resolved)", async () => {
    // RGL-401: unlike "unauthenticated", app.authenticate_and_authorize_api_request's own
    // rate_limited branch always returns a real, resolved api_key_id (v_auth.api_key_id) --
    // the key was found, only the rate check failed. Passing a realistic non-null apiKeyId
    // here (rather than the helper's own null default) matches that real contract and
    // exercises the "stays api_key" branch of the RGL-401 fix, not just the "anon" branch.
    const stub = installRpcFetchStub({
      authenticate_and_authorize_api_request: { data: deniedAuthRow("rate_limited", "22222222-2222-4222-8222-222222222222", "11111111-1111-4111-8111-111111111111") },
    });
    try {
      const response = await GET(new Request("http://localhost/api/v1/status", { headers: { authorization: "Bearer cgk_test_rate_limited" } }));
      assert.equal(response.status, 429);
      assert.equal(response.headers.get("retry-after"), "60");
      const body = (await response.json()) as { error: { code: string } };
      assert.equal(body.error.code, "rate_limited");
      const denialLogs = stub.calls.filter((c) => c.fn === "record_api_request" && c.body.p_result === "failure");
      assert.equal(denialLogs[0]?.body.p_actor_type, "api_key");
      assert.equal(denialLogs[0]?.body.p_api_key_id, "11111111-1111-4111-8111-111111111111");
    } finally {
      stub.restore();
    }
  });

  test("gateway denies with forbidden_scope -> 403, logs actorType api_key (the key WAS resolved)", async () => {
    // RGL-401: same real contract as rate_limited above -- forbidden_scope also always
    // carries a resolved api_key_id.
    const stub = installRpcFetchStub({
      authenticate_and_authorize_api_request: { data: deniedAuthRow("forbidden_scope", "22222222-2222-4222-8222-222222222222", "11111111-1111-4111-8111-111111111111") },
    });
    try {
      const response = await GET(new Request("http://localhost/api/v1/status", { headers: { authorization: "Bearer cgk_test_wrong_scope" } }));
      assert.equal(response.status, 403);
      const body = (await response.json()) as { error: { code: string } };
      assert.equal(body.error.code, "forbidden_scope");
      const denialLogs = stub.calls.filter((c) => c.fn === "record_api_request" && c.body.p_result === "failure");
      assert.equal(denialLogs[0]?.body.p_actor_type, "api_key");
      assert.equal(denialLogs[0]?.body.p_api_key_id, "11111111-1111-4111-8111-111111111111");
    } finally {
      stub.restore();
    }
  });

  test("a valid key returns 200 with real version/rate-limit shape, and logs exactly one success row", async () => {
    const stub = installRpcFetchStub({
      authenticate_and_authorize_api_request: { data: okAuthRow({ rateLimitPerMinute: 60, rateLimitRemaining: 42 }) },
      list_api_versions: {
        data: [{ code: "v1", status: "active", sunset_at: null, notes: "Initial version.", registered_by: null, created_at: "2026-07-19T00:00:00.000Z", updated_at: "2026-07-19T00:00:00.000Z" }],
      },
    });
    try {
      const response = await GET(new Request("http://localhost/api/v1/status", { headers: { authorization: "Bearer cgk_test_valid" } }));
      assert.equal(response.status, 200);
      const body = (await response.json()) as { versions: Array<{ code: string; status: string }>; rateLimit: { limitPerMinute: number; remaining: number } };
      assert.equal(body.versions.length, 1);
      assert.equal(body.versions[0]?.code, "v1");
      assert.equal(body.rateLimit.limitPerMinute, 60);
      assert.equal(body.rateLimit.remaining, 42);
      assert.equal(response.headers.get("x-cargogrid-api-version"), "v1");
      const successLogs = stub.calls.filter((c) => c.fn === "record_api_request" && c.body.p_result === "success");
      assert.equal(successLogs.length, 1);
      assert.equal(successLogs[0]?.body.p_status_code, 200);
    } finally {
      stub.restore();
    }
  });
});
