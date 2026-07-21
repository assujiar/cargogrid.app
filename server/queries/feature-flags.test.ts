import { test, describe } from "node:test";
import assert from "node:assert/strict";
import { evaluateFeatureFlag, FeatureFlagCache, FeatureFlagQueryError, type FeatureFlagRpcClient } from "./feature-flags.ts";

const TENANT_ID = "123e4567-e89b-12d3-a456-426614174000";

const ENABLED_ROW = {
  enabled: true,
  reason: "rollout_bucket",
  resolved_scope_level: "global",
  resolved_version_id: "223e4567-e89b-12d3-a456-426614174000",
  evaluated_at: "2026-07-21T00:00:00.000Z",
};
const DISABLED_ROW = {
  enabled: false,
  reason: "kill_switch",
  resolved_scope_level: "global",
  resolved_version_id: "223e4567-e89b-12d3-a456-426614174000",
  evaluated_at: "2026-07-21T00:00:00.000Z",
};

function fakeClient(response: { data: unknown; error: { message: string } | null }): FeatureFlagRpcClient & { callCount: number } {
  let callCount = 0;
  return {
    get callCount() {
      return callCount;
    },
    async rpc() {
      callCount++;
      return response;
    },
  };
}

describe("evaluateFeatureFlag", () => {
  test("calls the RPC with the exact snake_case params the SQL function expects", async () => {
    let capturedArgs: Record<string, unknown> | undefined;
    const client: FeatureFlagRpcClient = {
      async rpc(_fn, args) {
        capturedArgs = args;
        return { data: ENABLED_ROW, error: null };
      },
    };
    await evaluateFeatureFlag(client, { flagKey: "platform.example_rollout", tenantId: TENANT_ID, environment: "production", cohorts: ["beta"] }, undefined, 1_000_000);
    assert.equal(capturedArgs?.p_flag_key, "platform.example_rollout");
    assert.equal(capturedArgs?.p_tenant_id, TENANT_ID);
    assert.equal(capturedArgs?.p_environment, "production");
    assert.deepEqual(capturedArgs?.p_cohorts, ["beta"]);
  });

  test("returns a typed decision on success", async () => {
    const client = fakeClient({ data: ENABLED_ROW, error: null });
    const decision = await evaluateFeatureFlag(client, { flagKey: "platform.example_rollout", tenantId: TENANT_ID, environment: "production" });
    assert.equal(decision.enabled, true);
    assert.equal(decision.reason, "rollout_bucket");
  });

  test("wraps a database error into FeatureFlagQueryError", async () => {
    const client = fakeClient({ data: null, error: { message: "connection reset" } });
    await assert.rejects(() => evaluateFeatureFlag(client, { flagKey: "platform.example_rollout", tenantId: TENANT_ID, environment: "production" }), FeatureFlagQueryError);
  });

  test("serves a cached decision without a second RPC call within the TTL", async () => {
    const client = fakeClient({ data: ENABLED_ROW, error: null });
    const cache = new FeatureFlagCache(60_000);
    const input = { flagKey: "platform.example_rollout", tenantId: TENANT_ID, environment: "production" as const };

    await evaluateFeatureFlag(client, input, cache, 1_000_000);
    await evaluateFeatureFlag(client, input, cache, 1_000_000 + 30_000);

    assert.equal(client.callCount, 1, "second call within TTL must be served from cache, not a second RPC round-trip");
  });

  test("re-fetches once the TTL has elapsed", async () => {
    const client = fakeClient({ data: ENABLED_ROW, error: null });
    const cache = new FeatureFlagCache(1_000);
    const input = { flagKey: "platform.example_rollout", tenantId: TENANT_ID, environment: "production" as const };

    await evaluateFeatureFlag(client, input, cache, 1_000_000);
    await evaluateFeatureFlag(client, input, cache, 1_000_000 + 2_000);

    assert.equal(client.callCount, 2, "a call after the TTL elapsed must re-fetch");
  });

  test("caches distinct environments and cohort sets independently", async () => {
    const client = fakeClient({ data: ENABLED_ROW, error: null });
    const cache = new FeatureFlagCache(60_000);

    await evaluateFeatureFlag(client, { flagKey: "platform.example_rollout", tenantId: TENANT_ID, environment: "production" }, cache, 1_000_000);
    await evaluateFeatureFlag(client, { flagKey: "platform.example_rollout", tenantId: TENANT_ID, environment: "staging" }, cache, 1_000_000);
    await evaluateFeatureFlag(client, { flagKey: "platform.example_rollout", tenantId: TENANT_ID, environment: "production", cohorts: ["beta"] }, cache, 1_000_000);

    assert.equal(client.callCount, 3, "environment and cohort must both be real cache-key dimensions");
  });

  test("treats a different tenant (including platform-wide null) as a distinct cache key", async () => {
    const client = fakeClient({ data: ENABLED_ROW, error: null });
    const cache = new FeatureFlagCache(60_000);
    const otherTenantId = "323e4567-e89b-12d3-a456-426614174000";

    await evaluateFeatureFlag(client, { flagKey: "platform.example_rollout", tenantId: TENANT_ID, environment: "production" }, cache, 1_000_000);
    await evaluateFeatureFlag(client, { flagKey: "platform.example_rollout", tenantId: otherTenantId, environment: "production" }, cache, 1_000_000);
    await evaluateFeatureFlag(client, { flagKey: "platform.example_rollout", tenantId: null, environment: "production" }, cache, 1_000_000);

    assert.equal(client.callCount, 3);
  });
});

describe("FeatureFlagCache", () => {
  test("invalidate() drops every cached entry, forcing a re-fetch (prompt invalidation after a mutation)", async () => {
    const client = fakeClient({ data: DISABLED_ROW, error: null });
    const cache = new FeatureFlagCache(60_000);
    const input = { flagKey: "platform.example_rollout", tenantId: TENANT_ID, environment: "production" as const };

    await evaluateFeatureFlag(client, input, cache, 1_000_000);
    cache.invalidate();
    await evaluateFeatureFlag(client, input, cache, 1_000_000);

    assert.equal(client.callCount, 2, "invalidate() must force a re-fetch on the very next call, regardless of TTL -- e.g. right after a kill");
  });
});
