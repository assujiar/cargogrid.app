import { test, describe } from "node:test";
import assert from "node:assert/strict";
import { resolveConfig, verifyConfigVersionCurrent, ConfigResolutionCache, ConfigQueryError, type ConfigQueryRpcClient } from "./config.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const VERSION_ID = "423e4567-e89b-12d3-a456-426614174000";

const RESOLVED_ROW = {
  config_type_code: "approval",
  resolved_scope_level: "tenant",
  resolved_version_id: VERSION_ID,
  effective_from: "2026-07-17T00:00:00.000Z",
  items: { threshold: 1000 },
};

function fakeClient(response: { data: unknown; error: { message: string } | null }): ConfigQueryRpcClient & { calls: number } {
  let calls = 0;
  return {
    get calls() {
      return calls;
    },
    async rpc(_fn, _args) {
      calls += 1;
      return response;
    },
  };
}

describe("resolveConfig", () => {
  test("parses a resolved row (array response, matching Supabase's table-returning RPC shape)", async () => {
    const client = fakeClient({ data: [RESOLVED_ROW], error: null });
    const resolved = await resolveConfig(client, { configTypeCode: "approval", tenantId: TENANT_ID });
    assert.equal(resolved?.resolvedScopeLevel, "tenant");
  });

  test("returns null when no level resolves (empty array response)", async () => {
    const client = fakeClient({ data: [], error: null });
    const resolved = await resolveConfig(client, { configTypeCode: "approval", tenantId: TENANT_ID });
    assert.equal(resolved, null);
  });

  test("wraps a database error into a typed ConfigQueryError", async () => {
    const client = fakeClient({ data: null, error: { message: "connection reset" } });
    await assert.rejects(
      () => resolveConfig(client, { configTypeCode: "approval", tenantId: TENANT_ID }),
      (err: unknown) => {
        assert.ok(err instanceof ConfigQueryError);
        return true;
      },
    );
  });
});

describe("verifyConfigVersionCurrent", () => {
  test("calls verify_config_version_current with the exact snake_case params", async () => {
    const client = fakeClient({ data: true, error: null }) as ConfigQueryRpcClient & { calls: number };
    let capturedArgs: Record<string, unknown> | undefined;
    client.rpc = async (_fn, args) => {
      capturedArgs = args;
      return { data: true, error: null };
    };
    const isCurrent = await verifyConfigVersionCurrent(client, { configTypeCode: "approval", tenantId: TENANT_ID, expectedVersionId: VERSION_ID });
    assert.equal(isCurrent, true);
    assert.equal(capturedArgs?.["p_expected_version_id"], VERSION_ID);
  });

  test("returns false when the resolution has since moved on", async () => {
    const client = fakeClient({ data: false, error: null });
    const isCurrent = await verifyConfigVersionCurrent(client, { configTypeCode: "approval", tenantId: TENANT_ID, expectedVersionId: VERSION_ID });
    assert.equal(isCurrent, false);
  });
});

describe("ConfigResolutionCache", () => {
  test("caches a positive resolution within the TTL without a second RPC call", async () => {
    const client = fakeClient({ data: [RESOLVED_ROW], error: null });
    const cache = new ConfigResolutionCache(30_000);
    const now = 1_000_000;

    await resolveConfig(client, { configTypeCode: "approval", tenantId: TENANT_ID }, cache, now);
    await resolveConfig(client, { configTypeCode: "approval", tenantId: TENANT_ID }, cache, now + 1_000);

    assert.equal(client.calls, 1);
  });

  test("keys the cache independently per full scope tuple (a role-level lookup must not collide with a tenant-level one)", async () => {
    const client = fakeClient({ data: [RESOLVED_ROW], error: null });
    const cache = new ConfigResolutionCache(30_000);
    const now = 1_000_000;

    await resolveConfig(client, { configTypeCode: "approval", tenantId: TENANT_ID }, cache, now);
    await resolveConfig(client, { configTypeCode: "approval", tenantId: TENANT_ID, roleId: VERSION_ID }, cache, now + 1_000);

    assert.equal(client.calls, 2);
  });

  test("invalidate() clears every cached entry, forcing a re-fetch on the next call", async () => {
    const client = fakeClient({ data: [RESOLVED_ROW], error: null });
    const cache = new ConfigResolutionCache(30_000);
    const now = 1_000_000;

    await resolveConfig(client, { configTypeCode: "approval", tenantId: TENANT_ID }, cache, now);
    cache.invalidate();
    await resolveConfig(client, { configTypeCode: "approval", tenantId: TENANT_ID }, cache, now + 1_000);

    assert.equal(client.calls, 2);
  });
});
