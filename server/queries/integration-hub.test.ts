import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  listIntegrationAdapters,
  listIntegrationConnections,
  getIntegrationConnectionById,
  listIntegrationHealthChecks,
  IntegrationHubQueryError,
  type IntegrationHubQueryClient,
} from "./integration-hub.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const CONNECTION_ID = "323e4567-e89b-12d3-a456-426614174000";

const VALID_ADAPTER_ROW = {
  code: "iae_hub_test_adapter",
  name: "IAE Hub Test Adapter",
  category: "communication",
  owner_primitive_code: "INTHUB",
  registered_by: "tester",
  created_at: "2026-08-21T00:00:00.000Z",
};

const VALID_CONNECTION_ROW = {
  id: CONNECTION_ID,
  tenant_id: TENANT_ID,
  adapter_code: "iae_hub_test_adapter",
  name: "Primary Comms Adapter",
  environment: "production",
  status: "active",
  owner_team: "Platform Ops",
  owner_email: "ops@example.test",
  runbook_url: null,
  config: {},
  consecutive_failure_count: 0,
  last_health_check_at: null,
  last_health_status: null,
  auto_disabled_at: null,
  disabled_reason: null,
  record_version: 1,
  created_at: "2026-08-21T00:00:00.000Z",
  updated_at: "2026-08-21T00:00:00.000Z",
};

const VALID_HEALTH_CHECK_ROW = {
  id: "423e4567-e89b-12d3-a456-426614174000",
  connection_id: CONNECTION_ID,
  status: "healthy",
  detail: "ok",
  checked_by: "tester",
  checked_at: "2026-08-21T00:00:00.000Z",
};

function fakeRpcClient(response: { data: unknown; error: { message: string } | null }): {
  client: IntegrationHubQueryClient;
  calls: { fn: string; args: Record<string, unknown> }[];
} {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];
  const client = {
    async rpc(fn: string, args: Record<string, unknown> = {}) {
      calls.push({ fn, args });
      return response;
    },
  } as unknown as IntegrationHubQueryClient;
  return { client, calls };
}

describe("listIntegrationAdapters", () => {
  test("calls list_integration_adapters and maps adapter rows", async () => {
    const { client, calls } = fakeRpcClient({ data: [VALID_ADAPTER_ROW], error: null });
    const adapters = await listIntegrationAdapters(client);
    assert.equal(calls[0]?.fn, "list_integration_adapters");
    assert.equal(adapters.length, 1);
    assert.equal(adapters[0]?.code, "iae_hub_test_adapter");
  });

  test("wraps a query error", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "boom" } });
    await assert.rejects(
      () => listIntegrationAdapters(client),
      (err: unknown) => err instanceof IntegrationHubQueryError,
    );
  });
});

describe("listIntegrationConnections", () => {
  test("calls list_integration_connections and maps connection rows", async () => {
    const { client, calls } = fakeRpcClient({ data: [VALID_CONNECTION_ROW], error: null });
    const connections = await listIntegrationConnections(client, TENANT_ID);
    assert.deepEqual(calls[0]?.args, { p_tenant_id: TENANT_ID });
    assert.equal(connections.length, 1);
    assert.equal(connections[0]?.name, "Primary Comms Adapter");
  });
});

describe("getIntegrationConnectionById", () => {
  test("returns null (never an error) when not found", async () => {
    const { client } = fakeRpcClient({ data: [], error: null });
    const connection = await getIntegrationConnectionById(client, CONNECTION_ID);
    assert.equal(connection, null);
  });

  test("parses a matched row", async () => {
    const { client, calls } = fakeRpcClient({ data: [VALID_CONNECTION_ROW], error: null });
    const connection = await getIntegrationConnectionById(client, CONNECTION_ID);
    assert.deepEqual(calls[0]?.args, { p_connection_id: CONNECTION_ID });
    assert.equal(connection?.id, CONNECTION_ID);
  });
});

describe("listIntegrationHealthChecks", () => {
  test("calls list_integration_health_checks and maps health-check rows, newest first", async () => {
    const { client, calls } = fakeRpcClient({ data: [VALID_HEALTH_CHECK_ROW], error: null });
    const checks = await listIntegrationHealthChecks(client, CONNECTION_ID);
    assert.deepEqual(calls[0]?.args, { p_connection_id: CONNECTION_ID, p_limit: 25 });
    assert.equal(checks.length, 1);
    assert.equal(checks[0]?.status, "healthy");
  });
});
