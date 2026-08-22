import { test, describe } from "node:test";
import assert from "node:assert/strict";
import { createServer, type Server } from "node:http";
import { geocodeAddress, type GeocodeAddressRpcClient } from "./geocode-address.server.ts";

const ALLOW_ALL_URLS = async () => ({ safe: true, reason: null });

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const CONNECTION_ID = "323e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "423e4567-e89b-12d3-a456-426614174000";

interface RecordedCalls {
  requests: Record<string, unknown>[];
}

function mockClient(apiUrl: string | null, dispatchOverrides: Record<string, unknown> = {}, recorded: RecordedCalls = { requests: [] }, credential: string | null = "test-credential-value"): GeocodeAddressRpcClient {
  return {
    rpc: async (fn: string, args: Record<string, unknown>) => {
      if (fn === "get_maps_provider_dispatch_info") {
        return { data: { connection_id: CONNECTION_ID, connection_status: "active", connection_config: apiUrl ? { apiUrl } : {}, ...dispatchOverrides }, error: null };
      }
      if (fn === "get_maps_provider_credential") {
        return { data: credential, error: null };
      }
      if (fn === "record_geocode_request") {
        recorded.requests.push(args);
        return {
          data: {
            id: "523e4567-e89b-12d3-a456-426614174000", tenant_id: TENANT_ID, connection_id: args.p_connection_id, request_type: args.p_request_type,
            query_payload: args.p_query_payload, status: args.p_status, result_payload: args.p_result_payload ?? null,
            provider_unit_cost_amount: args.p_provider_unit_cost_amount ?? null, currency: args.p_currency ?? null, billed_amount: null,
            error_message: args.p_error_message ?? null, requested_by_auth_user_id: ACTOR_ID, requested_by: "test", created_at: "2026-08-21T00:00:00.000Z",
          },
          error: null,
        };
      }
      throw new Error(`unexpected rpc call: ${fn}`);
    },
  } as unknown as GeocodeAddressRpcClient;
}

async function startServer(handler: (req: import("node:http").IncomingMessage, res: import("node:http").ServerResponse) => void): Promise<{ server: Server; url: string }> {
  const server = createServer(handler);
  await new Promise<void>((resolve) => server.listen(0, "127.0.0.1", resolve));
  const { port } = server.address() as { port: number };
  return { server, url: `http://127.0.0.1:${port}/geocode` };
}

describe("geocodeAddress", () => {
  test("a real 2xx provider response with valid coordinates succeeds and records a real cost", async () => {
    const received: { headers: Record<string, string | string[] | undefined>; body: string }[] = [];
    const { server, url } = await startServer((req, res) => {
      let body = "";
      req.on("data", (chunk) => (body += chunk));
      req.on("end", () => {
        received.push({ headers: req.headers, body });
        res.writeHead(200, { "content-type": "application/json" });
        res.end(JSON.stringify({ latitude: 1.23, longitude: 4.56, formattedAddress: "123 Main St, Testville" }));
      });
    });
    try {
      const recorded: RecordedCalls = { requests: [] };
      const client = mockClient(url, {}, recorded);
      const result = await geocodeAddress(client, { tenantId: TENANT_ID, actorAuthUserId: ACTOR_ID, actorLabel: "system", address: "123 Main St" }, ALLOW_ALL_URLS);

      assert.equal(result.success, true);
      assert.equal(result.latitude, 1.23);
      assert.equal(result.formattedAddress, "123 Main St, Testville");
      assert.equal(recorded.requests.length, 1);
      assert.equal(recorded.requests[0]?.p_status, "success");
      assert.ok((recorded.requests[0]?.p_provider_unit_cost_amount as number) > 0);
      assert.equal(received[0]?.headers["authorization"], "Bearer test-credential-value");
      assert.deepEqual(JSON.parse(received[0]!.body), { address: "123 Main St" });
    } finally {
      server.close();
    }
  });

  test("a real non-2xx provider response fails cleanly", async () => {
    const { server, url } = await startServer((_req, res) => {
      res.writeHead(503);
      res.end("provider down");
    });
    try {
      const recorded: RecordedCalls = { requests: [] };
      const client = mockClient(url, {}, recorded);
      const result = await geocodeAddress(client, { tenantId: TENANT_ID, actorAuthUserId: ACTOR_ID, actorLabel: "system", address: "123 Main St" }, ALLOW_ALL_URLS);

      assert.equal(result.success, false);
      assert.match(result.errorMessage ?? "", /HTTP 503/);
      assert.equal(recorded.requests[0]?.p_status, "failed");
    } finally {
      server.close();
    }
  });

  test("a real network-level failure is classified as a failure, not an uncaught throw", async () => {
    const recorded: RecordedCalls = { requests: [] };
    const client = mockClient("http://127.0.0.1:1/unreachable", {}, recorded);
    const result = await geocodeAddress(client, { tenantId: TENANT_ID, actorAuthUserId: ACTOR_ID, actorLabel: "system", address: "123 Main St" }, ALLOW_ALL_URLS);

    assert.equal(result.success, false);
    assert.ok(result.errorMessage);
    assert.equal(recorded.requests[0]?.p_status, "failed");
  });

  test("no active connection fails without attempting a live HTTP call", async () => {
    let called = false;
    const { server, url } = await startServer((_req, res) => {
      called = true;
      res.writeHead(200);
      res.end();
    });
    try {
      const recorded: RecordedCalls = { requests: [] };
      const client = mockClient(url, { connection_status: "disabled" }, recorded);
      const result = await geocodeAddress(client, { tenantId: TENANT_ID, actorAuthUserId: ACTOR_ID, actorLabel: "system", address: "123 Main St" }, ALLOW_ALL_URLS);

      assert.equal(result.success, false);
      assert.match(result.errorMessage ?? "", /no active maps_geocoding/);
      assert.equal(called, false);
    } finally {
      server.close();
    }
  });

  test("a malformed provider response (missing coordinates) fails cleanly", async () => {
    const { server, url } = await startServer((_req, res) => {
      res.writeHead(200, { "content-type": "application/json" });
      res.end(JSON.stringify({ formattedAddress: "somewhere" }));
    });
    try {
      const recorded: RecordedCalls = { requests: [] };
      const client = mockClient(url, {}, recorded);
      const result = await geocodeAddress(client, { tenantId: TENANT_ID, actorAuthUserId: ACTOR_ID, actorLabel: "system", address: "123 Main St" }, ALLOW_ALL_URLS);

      assert.equal(result.success, false);
      assert.match(result.errorMessage ?? "", /latitude\/longitude/);
    } finally {
      server.close();
    }
  });

  test("the REAL (non-injected) SSRF guard refuses a literal private-IP provider apiUrl without attempting a live HTTP call", async () => {
    const recorded: RecordedCalls = { requests: [] };
    const client = mockClient("https://169.254.169.254/latest/meta-data/", {}, recorded);
    const result = await geocodeAddress(client, { tenantId: TENANT_ID, actorAuthUserId: ACTOR_ID, actorLabel: "system", address: "123 Main St" });

    assert.equal(result.success, false);
    assert.match(result.errorMessage ?? "", /refusing to dispatch/);
  });

  test("Tier C fix: no connection row AT ALL (a tenant that never configured maps_geocoding) fails cleanly, never a raw foreign-key-violation from a sentinel connection id", async () => {
    let called = false;
    const client: GeocodeAddressRpcClient = {
      rpc: async (fn: string) => {
        if (fn === "get_maps_provider_dispatch_info") {
          called = true;
          return { data: null, error: null };
        }
        throw new Error(`unexpected rpc call: ${fn} -- no evidence write should ever be attempted with no real connection_id to attribute it to`);
      },
    } as unknown as GeocodeAddressRpcClient;
    const result = await geocodeAddress(client, { tenantId: TENANT_ID, actorAuthUserId: ACTOR_ID, actorLabel: "system", address: "123 Main St" }, ALLOW_ALL_URLS);

    assert.equal(called, true);
    assert.equal(result.success, false);
    assert.match(result.errorMessage ?? "", /no active maps_geocoding/);
  });
});
