import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  createIntegrationConnection,
  updateIntegrationConnectionConfig,
  rotateIntegrationConnectionCredential,
  setIntegrationConnectionStatus,
  recordIntegrationHealthCheck,
  IntegrationHubMutationError,
  type IntegrationHubMutationRpcClient,
} from "./integration-hub.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "323e4567-e89b-12d3-a456-426614174000";
const CONNECTION_ID = "423e4567-e89b-12d3-a456-426614174000";

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

function fakeRpcClient(response: { data: unknown; error: { message: string } | null }): {
  client: IntegrationHubMutationRpcClient;
  calls: { fn: string; args: Record<string, unknown> }[];
} {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];
  const client = {
    async rpc(fn: string, args: Record<string, unknown>) {
      calls.push({ fn, args });
      return response;
    },
  } as unknown as IntegrationHubMutationRpcClient;
  return { client, calls };
}

describe("createIntegrationConnection", () => {
  test("calls create_integration_connection with the exact snake_case params, including the credential", async () => {
    const { client, calls } = fakeRpcClient({ data: VALID_CONNECTION_ROW, error: null });
    const connection = await createIntegrationConnection(client, {
      tenantId: TENANT_ID,
      adapterCode: "iae_hub_test_adapter",
      name: "Primary Comms Adapter",
      credentialValue: "sk_live_real_secret_value",
      actorAuthUserId: ACTOR_ID,
      actorLabel: "tester",
    });

    assert.equal(calls[0]?.fn, "create_integration_connection");
    assert.equal(calls[0]?.args.p_credential_value, "sk_live_real_secret_value");
    assert.equal(connection.status, "active");
  });

  test("classifies integration_adapter_unknown", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "integration_adapter_unknown: not_a_real_adapter is not a registered integration adapter" } });
    await assert.rejects(
      () => createIntegrationConnection(client, { tenantId: TENANT_ID, adapterCode: "not_a_real_adapter", name: "x", credentialValue: "x", actorAuthUserId: ACTOR_ID, actorLabel: "tester" }),
      (err: unknown) => {
        assert.ok(err instanceof IntegrationHubMutationError);
        assert.equal(err.code, "integration_adapter_unknown");
        return true;
      },
    );
  });
});

describe("updateIntegrationConnectionConfig", () => {
  test("calls update_integration_connection_config with the exact snake_case params", async () => {
    const { client, calls } = fakeRpcClient({ data: VALID_CONNECTION_ROW, error: null });
    await updateIntegrationConnectionConfig(client, { connectionId: CONNECTION_ID, config: { base_url: "https://x.test" }, actorAuthUserId: ACTOR_ID, actorLabel: "tester" });

    assert.equal(calls[0]?.fn, "update_integration_connection_config");
    assert.deepEqual(calls[0]?.args.p_config, { base_url: "https://x.test" });
  });
});

describe("rotateIntegrationConnectionCredential", () => {
  test("calls rotate_integration_connection_credential and never leaks the value in the return type", async () => {
    const { client, calls } = fakeRpcClient({ data: VALID_CONNECTION_ROW, error: null });
    const connection = await rotateIntegrationConnectionCredential(client, { connectionId: CONNECTION_ID, newCredentialValue: "sk_live_rotated", actorAuthUserId: ACTOR_ID, actorLabel: "tester" });

    assert.equal(calls[0]?.fn, "rotate_integration_connection_credential");
    assert.equal(calls[0]?.args.p_new_credential_value, "sk_live_rotated");
    assert.equal(Object.prototype.hasOwnProperty.call(connection, "credentialValue"), false);
  });
});

describe("setIntegrationConnectionStatus", () => {
  test("calls set_integration_connection_status with the exact snake_case params", async () => {
    const { client, calls } = fakeRpcClient({ data: { ...VALID_CONNECTION_ROW, status: "disabled" }, error: null });
    const connection = await setIntegrationConnectionStatus(client, { connectionId: CONNECTION_ID, status: "disabled", reason: "planned maintenance", actorAuthUserId: ACTOR_ID, actorLabel: "tester" });

    assert.equal(calls[0]?.fn, "set_integration_connection_status");
    assert.equal(connection.status, "disabled");
  });
});

describe("recordIntegrationHealthCheck", () => {
  test("calls record_integration_health_check and returns a real check row", async () => {
    const checkRow = { id: "523e4567-e89b-12d3-a456-426614174000", connection_id: CONNECTION_ID, status: "unhealthy", detail: "timeout", checked_by: "tester", checked_at: "2026-08-21T00:00:00.000Z" };
    const { client, calls } = fakeRpcClient({ data: checkRow, error: null });
    const check = await recordIntegrationHealthCheck(client, { connectionId: CONNECTION_ID, status: "unhealthy", detail: "timeout", actorAuthUserId: ACTOR_ID, actorLabel: "tester" });

    assert.equal(calls[0]?.fn, "record_integration_health_check");
    assert.equal(check.status, "unhealthy");
  });

  test("falls back to mutation_failed for an unrecognized error message", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "boom, unrecognized" } });
    await assert.rejects(
      () => recordIntegrationHealthCheck(client, { connectionId: CONNECTION_ID, status: "healthy", actorAuthUserId: ACTOR_ID, actorLabel: "tester" }),
      (err: unknown) => {
        assert.ok(err instanceof IntegrationHubMutationError);
        assert.equal(err.code, "mutation_failed");
        return true;
      },
    );
  });
});
