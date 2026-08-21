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

function fakeTableClient(response: { data: unknown; error: { message: string } | null }): IntegrationHubQueryClient {
  function chainNode(): unknown {
    return {
      select: () => chainNode(),
      eq: () => chainNode(),
      order: () => chainNode(),
      limit: () => chainNode(),
      maybeSingle: () => {
        const row = Array.isArray(response.data) ? (response.data[0] ?? null) : response.data;
        return Promise.resolve({ data: row, error: response.error });
      },
      then: (resolve: (value: unknown) => unknown, reject?: (reason: unknown) => unknown) => Promise.resolve(response).then(resolve, reject),
    };
  }
  return { from: () => chainNode() } as unknown as IntegrationHubQueryClient;
}

describe("listIntegrationAdapters", () => {
  test("maps adapter rows", async () => {
    const client = fakeTableClient({ data: [VALID_ADAPTER_ROW], error: null });
    const adapters = await listIntegrationAdapters(client);
    assert.equal(adapters.length, 1);
    assert.equal(adapters[0]?.code, "iae_hub_test_adapter");
  });

  test("wraps a query error", async () => {
    const client = fakeTableClient({ data: null, error: { message: "boom" } });
    await assert.rejects(
      () => listIntegrationAdapters(client),
      (err: unknown) => err instanceof IntegrationHubQueryError,
    );
  });
});

describe("listIntegrationConnections", () => {
  test("maps connection rows", async () => {
    const client = fakeTableClient({ data: [VALID_CONNECTION_ROW], error: null });
    const connections = await listIntegrationConnections(client, TENANT_ID);
    assert.equal(connections.length, 1);
    assert.equal(connections[0]?.name, "Primary Comms Adapter");
  });
});

describe("getIntegrationConnectionById", () => {
  test("returns null (never an error) when not found", async () => {
    const client = fakeTableClient({ data: null, error: null });
    const connection = await getIntegrationConnectionById(client, CONNECTION_ID);
    assert.equal(connection, null);
  });

  test("parses a matched row", async () => {
    const client = fakeTableClient({ data: VALID_CONNECTION_ROW, error: null });
    const connection = await getIntegrationConnectionById(client, CONNECTION_ID);
    assert.equal(connection?.id, CONNECTION_ID);
  });
});

describe("listIntegrationHealthChecks", () => {
  test("maps health-check rows, newest first", async () => {
    const client = fakeTableClient({ data: [VALID_HEALTH_CHECK_ROW], error: null });
    const checks = await listIntegrationHealthChecks(client, CONNECTION_ID);
    assert.equal(checks.length, 1);
    assert.equal(checks[0]?.status, "healthy");
  });
});
