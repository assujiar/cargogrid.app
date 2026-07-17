import { test, describe } from "node:test";
import assert from "node:assert/strict";
import { evaluateEntitlement, EntitlementCache, EntitlementServiceError, type EntitlementRpcClient } from "./entitlement.ts";

const TENANT_ID = "123e4567-e89b-12d3-a456-426614174000";

const ALLOWED_ROW = { allowed: true, reason: "package_granted", limit_value: 50, package_code: "professional", evaluated_at: "2026-07-16T00:00:00.000Z" };
const DENIED_ROW = { allowed: false, reason: "no_active_entitlement", limit_value: null, package_code: null, evaluated_at: "2026-07-16T00:00:00.000Z" };

function fakeClient(response: { data: unknown; error: { message: string } | null }): EntitlementRpcClient & { callCount: number } {
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

describe("evaluateEntitlement", () => {
  test("calls the RPC with the exact snake_case params the SQL function expects", async () => {
    let capturedArgs: Record<string, unknown> | undefined;
    const client: EntitlementRpcClient = {
      async rpc(_fn, args) {
        capturedArgs = args;
        return { data: ALLOWED_ROW, error: null };
      },
    };
    await evaluateEntitlement(client, { tenantId: TENANT_ID, moduleCode: "COM", featureCode: "COM-QTN" }, undefined, 1_000_000);
    assert.equal(capturedArgs?.p_tenant_id, TENANT_ID);
    assert.equal(capturedArgs?.p_module_code, "COM");
    assert.equal(capturedArgs?.p_feature_code, "COM-QTN");
  });

  test("returns a typed decision on success", async () => {
    const client = fakeClient({ data: ALLOWED_ROW, error: null });
    const decision = await evaluateEntitlement(client, { tenantId: TENANT_ID, moduleCode: "COM" });
    assert.equal(decision.allowed, true);
    assert.equal(decision.limitValue, 50);
  });

  test("wraps a database error into EntitlementServiceError", async () => {
    const client = fakeClient({ data: null, error: { message: "connection reset" } });
    await assert.rejects(() => evaluateEntitlement(client, { tenantId: TENANT_ID, moduleCode: "COM" }), EntitlementServiceError);
  });

  test("serves a cached decision without a second RPC call within the TTL", async () => {
    const client = fakeClient({ data: ALLOWED_ROW, error: null });
    const cache = new EntitlementCache(60_000);

    await evaluateEntitlement(client, { tenantId: TENANT_ID, moduleCode: "COM" }, cache, 1_000_000);
    await evaluateEntitlement(client, { tenantId: TENANT_ID, moduleCode: "COM" }, cache, 1_000_000 + 30_000);

    assert.equal(client.callCount, 1, "second call within TTL must be served from cache, not a second RPC round-trip");
  });

  test("re-fetches once the TTL has elapsed", async () => {
    const client = fakeClient({ data: ALLOWED_ROW, error: null });
    const cache = new EntitlementCache(1_000);

    await evaluateEntitlement(client, { tenantId: TENANT_ID, moduleCode: "COM" }, cache, 1_000_000);
    await evaluateEntitlement(client, { tenantId: TENANT_ID, moduleCode: "COM" }, cache, 1_000_000 + 2_000);

    assert.equal(client.callCount, 2, "a call after the TTL elapsed must re-fetch");
  });

  test("caches module and feature evaluations independently (different cache keys)", async () => {
    const client = fakeClient({ data: ALLOWED_ROW, error: null });
    const cache = new EntitlementCache(60_000);

    await evaluateEntitlement(client, { tenantId: TENANT_ID, moduleCode: "COM" }, cache, 1_000_000);
    await evaluateEntitlement(client, { tenantId: TENANT_ID, moduleCode: "COM", featureCode: "COM-QTN" }, cache, 1_000_000);

    assert.equal(client.callCount, 2, "module-level and feature-level evaluations must not collide in the cache");
  });
});

describe("EntitlementCache", () => {
  test("invalidate(tenantId) drops every cached entry for that tenant, forcing a re-fetch", async () => {
    const client = fakeClient({ data: DENIED_ROW, error: null });
    const cache = new EntitlementCache(60_000);

    await evaluateEntitlement(client, { tenantId: TENANT_ID, moduleCode: "COM" }, cache, 1_000_000);
    cache.invalidate(TENANT_ID);
    await evaluateEntitlement(client, { tenantId: TENANT_ID, moduleCode: "COM" }, cache, 1_000_000);

    assert.equal(client.callCount, 2, "invalidate() must force a re-fetch on the very next call, regardless of TTL");
  });

  test("invalidating one tenant does not affect another tenant's cached entries", async () => {
    const otherTenantId = "223e4567-e89b-12d3-a456-426614174000";
    const client = fakeClient({ data: ALLOWED_ROW, error: null });
    const cache = new EntitlementCache(60_000);

    await evaluateEntitlement(client, { tenantId: TENANT_ID, moduleCode: "COM" }, cache, 1_000_000);
    await evaluateEntitlement(client, { tenantId: otherTenantId, moduleCode: "COM" }, cache, 1_000_000);
    cache.invalidate(TENANT_ID);
    await evaluateEntitlement(client, { tenantId: otherTenantId, moduleCode: "COM" }, cache, 1_000_000);

    assert.equal(client.callCount, 2, "the untouched tenant's cache entry must still be served without a third RPC call");
  });
});
