/**
 * HDN-376 (API Compatibility Audit, ISS-2026-147 item 1): a shared, reusable HTTP-layer
 * test harness for the 9 `app/api/v1/**` route handlers.
 *
 * These route handlers call `lib/api-gateway/authenticate.server.ts`'s own
 * `authorizeApiV1Request()`, which internally constructs a real `@supabase/supabase-js`
 * client (`createSupabaseServiceRoleClient()`) and calls `.rpc(...)` on it -- there is
 * no dependency-injection seam to substitute a fake RPC client at the route-handler
 * level, and this repository has no local PostgREST/Supabase stack to run these tests
 * against a real backend. `@supabase/supabase-js`'s `.rpc()` call is, underneath,
 * exactly one `fetch(POST, "<SUPABASE_URL>/rest/v1/rpc/<function_name>", {body: params})`
 * -- so this harness stubs `globalThis.fetch` for the duration of a test, pattern-matches
 * the RPC function name out of the request URL, and returns a programmable canned
 * response per function name. Every route's own real request parsing, header/auth
 * extraction, response shaping and error-code-to-HTTP-status mapping still runs for
 * real; only the network boundary is faked -- exactly the seam ISS-2026-147 named as
 * having zero dedicated coverage.
 */

export interface RpcResponse {
  status?: number;
  data?: unknown;
  error?: { message: string; code?: string } | null;
}

export type RpcHandlers = Record<string, RpcResponse | ((body: Record<string, unknown>) => RpcResponse)>;

/** Standard `authenticate_and_authorize_api_request` "ok" row, camelCase input fields translated to the snake_case PostgREST would actually return. */
export function okAuthRow(overrides: Partial<{
  apiKeyId: string;
  tenantId: string;
  createdByAuthUserId: string;
  rateLimitPerMinute: number | null;
  rateLimitRemaining: number | null;
  vendorMasterRecordId: string | null;
}> = {}) {
  return [
    {
      outcome: "ok",
      api_key_id: overrides.apiKeyId ?? "11111111-1111-4111-8111-111111111111",
      tenant_id: overrides.tenantId ?? "22222222-2222-4222-8222-222222222222",
      created_by_auth_user_id: overrides.createdByAuthUserId ?? "33333333-3333-4333-8333-333333333333",
      rate_limit_per_minute: overrides.rateLimitPerMinute ?? 60,
      rate_limit_remaining: overrides.rateLimitRemaining ?? 59,
      vendor_master_record_id: overrides.vendorMasterRecordId ?? null,
    },
  ];
}

/** Standard denial row for `authenticate_and_authorize_api_request` -- outcome is one of "unauthenticated" | "forbidden_scope" | "rate_limited". */
export function deniedAuthRow(outcome: "unauthenticated" | "forbidden_scope" | "rate_limited", tenantId: string | null = null, apiKeyId: string | null = null) {
  return [{ outcome, api_key_id: apiKeyId, tenant_id: tenantId, created_by_auth_user_id: null, rate_limit_per_minute: null, rate_limit_remaining: null, vendor_master_record_id: null }];
}

/** `record_api_request` always succeeds trivially in these tests -- its own real behavior is covered by scripts/db-tests, not the route-level HTTP-layer concern this harness targets. Echoes the real input params back into a fully-shaped ApiLog row (ApiLogSchema, server/contracts/api/api.ts) so parseApiLog() never fails on a mocked call regardless of what the route passed. */
function defaultHandlers(): RpcHandlers {
  return {
    /**
     * ISS-2026-207: the gateway now asks the version registry before authenticating. Defaulted
     * to an ACTIVE v1 so every existing route test keeps testing what it was written to test.
     *
     * It has to be a real default rather than left unhandled: an unhandled name 404s here, and
     * `evaluateApiVersionRequest` deliberately fails OPEN on an unreadable answer, so the nine
     * route tests would still pass — while silently exercising the failure path instead of the
     * registry. A test that passes for the wrong reason is worse than one that fails.
     */
    evaluate_api_version_request: { data: [{ decision: "ok", status: "active", sunset_at: null }] },
    record_api_request: (body: Record<string, unknown>) => ({
      data: {
        id: "44444444-4444-4444-8444-444444444444",
        correlation_id: body.p_correlation_id ?? "55555555-5555-4555-8555-555555555555",
        tenant_id: body.p_tenant_id ?? null,
        actor_auth_user_id: body.p_actor_auth_user_id ?? null,
        actor_type: body.p_actor_type ?? "api_key",
        api_key_id: body.p_api_key_id ?? null,
        interface: body.p_interface ?? "rest",
        operation: body.p_operation ?? "unknown",
        http_method: body.p_http_method ?? null,
        path: body.p_path ?? null,
        graphql_operation_name: body.p_graphql_operation_name ?? null,
        status_code: body.p_status_code ?? null,
        result: body.p_result ?? "success",
        error_code: body.p_error_code ?? null,
        idempotency_key: body.p_idempotency_key ?? null,
        duration_ms: body.p_duration_ms ?? 1,
        created_at: "2026-08-24T00:00:00.000Z",
      },
    }),
  };
}

/**
 * Installs a `fetch` stub for the duration of the returned `restore()` call. `handlers`
 * maps a bare RPC function name (e.g. `"authenticate_and_authorize_api_request"`) to
 * either a static `RpcResponse` or a function of the parsed request body producing one --
 * unmatched function names 404, surfacing a missing-fixture bug immediately rather than
 * silently returning an empty success.
 */
export function installRpcFetchStub(handlers: RpcHandlers): { restore: () => void; calls: Array<{ fn: string; body: Record<string, unknown> }> } {
  process.env.NEXT_PUBLIC_SUPABASE_URL ??= "http://127.0.0.1:54321";
  process.env.SUPABASE_SERVICE_ROLE_KEY ??= "test-service-role-key";

  const merged: RpcHandlers = { ...defaultHandlers(), ...handlers };
  const calls: Array<{ fn: string; body: Record<string, unknown> }> = [];
  const originalFetch = globalThis.fetch;

  globalThis.fetch = (async (input: RequestInfo | URL, init?: RequestInit) => {
    const url = typeof input === "string" ? input : input instanceof URL ? input.toString() : (input as Request).url;
    const match = /\/rest\/v1\/rpc\/([a-zA-Z0-9_]+)/.exec(url);
    if (!match) {
      throw new Error(`installRpcFetchStub: unexpected fetch to non-RPC URL ${url} -- this harness only stubs PostgREST RPC calls`);
    }
    const fn = match[1] as string;
    const body = init?.body ? (JSON.parse(init.body as string) as Record<string, unknown>) : {};
    calls.push({ fn, body });

    const entry = merged[fn];
    if (entry === undefined) {
      return new Response(JSON.stringify({ message: `installRpcFetchStub: no handler registered for RPC "${fn}"`, code: "PGRST202" }), { status: 404, headers: { "content-type": "application/json" } });
    }
    const resolved = typeof entry === "function" ? entry(body) : entry;
    if (resolved.error) {
      return new Response(JSON.stringify(resolved.error), { status: resolved.status ?? 400, headers: { "content-type": "application/json" } });
    }
    return new Response(JSON.stringify(resolved.data ?? null), { status: resolved.status ?? 200, headers: { "content-type": "application/json" } });
  }) as typeof fetch;

  return {
    calls,
    restore: () => {
      globalThis.fetch = originalFetch;
    },
  };
}
