import { test, describe } from "node:test";
import assert from "node:assert/strict";
import { recordApiRequest, ApiLogMutationError, type ApiLogMutationRpcClient } from "./api-log.ts";

const CORRELATION_ID = "223e4567-e89b-12d3-a456-426614174000";
const TENANT_ID = "323e4567-e89b-12d3-a456-426614174000";
const LOG_ID = "423e4567-e89b-12d3-a456-426614174000";

function fakeClient(response: { data: unknown; error: { message: string } | null }): ApiLogMutationRpcClient & { calls: { fn: string; args: Record<string, unknown> }[] } {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];
  return {
    calls,
    async rpc(fn, args) {
      calls.push({ fn, args });
      return response;
    },
  };
}

describe("recordApiRequest", () => {
  test("calls record_api_request with the exact snake_case params, defaulting the optional fields", async () => {
    const client = fakeClient({
      data: {
        id: LOG_ID,
        correlation_id: CORRELATION_ID,
        tenant_id: TENANT_ID,
        actor_auth_user_id: null,
        actor_type: "service_role",
        api_key_id: null,
        interface: "rest",
        operation: "GET /v1/tenants",
        http_method: "GET",
        path: "/v1/tenants",
        graphql_operation_name: null,
        status_code: 200,
        result: "success",
        error_code: null,
        idempotency_key: null,
        duration_ms: 12,
        created_at: "2026-07-19T00:00:00.000Z",
      },
      error: null,
    });
    const log = await recordApiRequest(client, {
      correlationId: CORRELATION_ID,
      actorType: "service_role",
      interface: "rest",
      operation: "GET /v1/tenants",
      httpMethod: "GET",
      path: "/v1/tenants",
      statusCode: 200,
      result: "success",
      durationMs: 12,
    });

    assert.deepEqual(client.calls[0]?.args, {
      p_correlation_id: CORRELATION_ID,
      p_tenant_id: null,
      p_actor_auth_user_id: null,
      p_actor_type: "service_role",
      p_api_key_id: null,
      p_interface: "rest",
      p_operation: "GET /v1/tenants",
      p_http_method: "GET",
      p_path: "/v1/tenants",
      p_graphql_operation_name: null,
      p_status_code: 200,
      p_result: "success",
      p_error_code: null,
      p_idempotency_key: null,
      p_duration_ms: 12,
    });
    assert.equal(log.result, "success");
  });

  test("wraps an api_log_invalid_actor_type error", async () => {
    const client = fakeClient({ data: null, error: { message: "api_log_invalid_actor_type: not-a-type is not one of user/api_key/service_role/anon" } });
    await assert.rejects(
      () => recordApiRequest(client, { correlationId: CORRELATION_ID, actorType: "service_role", interface: "rest", operation: "GET /v1/tenants", result: "success" }),
      (err: unknown) => {
        assert.ok(err instanceof ApiLogMutationError);
        assert.equal(err.code, "api_log_invalid_actor_type");
        return true;
      },
    );
  });

  test("throws invalid_response when the RPC returns no row", async () => {
    const client = fakeClient({ data: null, error: null });
    await assert.rejects(
      () => recordApiRequest(client, { correlationId: CORRELATION_ID, actorType: "service_role", interface: "rest", operation: "GET /v1/tenants", result: "success" }),
      (err: unknown) => {
        assert.ok(err instanceof ApiLogMutationError);
        assert.equal(err.code, "invalid_response");
        return true;
      },
    );
  });
});
