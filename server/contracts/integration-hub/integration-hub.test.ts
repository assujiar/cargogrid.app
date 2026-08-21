import { test, describe } from "node:test";
import assert from "node:assert/strict";
import { parseIntegrationAdapter, parseIntegrationConnection, parseIntegrationHealthCheck } from "./integration-hub.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const CONNECTION_ID = "323e4567-e89b-12d3-a456-426614174000";

describe("parseIntegrationAdapter", () => {
  test("maps snake_case columns to camelCase", () => {
    const adapter = parseIntegrationAdapter({
      code: "iae_hub_test_adapter",
      name: "IAE Hub Test Adapter",
      category: "communication",
      owner_primitive_code: "INTHUB",
      registered_by: "tester",
      created_at: "2026-08-21T00:00:00.000Z",
    });
    assert.equal(adapter.ownerPrimitiveCode, "INTHUB");
  });
});

describe("parseIntegrationConnection", () => {
  test("maps snake_case columns to camelCase and defaults config to {}", () => {
    const connection = parseIntegrationConnection({
      id: CONNECTION_ID,
      tenant_id: TENANT_ID,
      adapter_code: "iae_hub_test_adapter",
      name: "Primary Comms Adapter",
      environment: "production",
      status: "active",
      owner_team: "Platform Ops",
      owner_email: "ops@example.test",
      runbook_url: null,
      config: null,
      consecutive_failure_count: 0,
      last_health_check_at: null,
      last_health_status: null,
      auto_disabled_at: null,
      disabled_reason: null,
      record_version: 1,
      created_at: "2026-08-21T00:00:00.000Z",
      updated_at: "2026-08-21T00:00:00.000Z",
    });
    assert.deepEqual(connection.config, {});
    assert.equal(connection.ownerTeam, "Platform Ops");
  });

  test("never carries a credential field even if present on the raw row (structurally impossible via the real schema, but the parser itself must not accept one)", () => {
    const row = {
      id: CONNECTION_ID,
      tenant_id: TENANT_ID,
      adapter_code: "x",
      name: "x",
      environment: "production",
      status: "active",
      owner_team: null,
      owner_email: null,
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
      credential_value: "sk_live_should_never_be_here",
    };
    const connection = parseIntegrationConnection(row);
    assert.equal(Object.prototype.hasOwnProperty.call(connection, "credentialValue"), false);
  });
});

describe("parseIntegrationHealthCheck", () => {
  test("parses an unhealthy check row", () => {
    const check = parseIntegrationHealthCheck({
      id: "423e4567-e89b-12d3-a456-426614174000",
      connection_id: CONNECTION_ID,
      status: "unhealthy",
      detail: "timeout",
      checked_by: "tester",
      checked_at: "2026-08-21T00:00:00.000Z",
    });
    assert.equal(check.status, "unhealthy");
  });
});
