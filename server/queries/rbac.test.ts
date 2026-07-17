import { test, describe } from "node:test";
import assert from "node:assert/strict";
import { evaluatePermission, RbacDecisionCache, RbacEvaluationError, type RbacRpcClient } from "./rbac.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const AUTH_USER_ID = "123e4567-e89b-12d3-a456-426614174000";

const ALLOWED_ROW = {
  allowed: true,
  reason: "role_grant",
  permission_id: "323e4567-e89b-12d3-a456-426614174000",
  role_id: "423e4567-e89b-12d3-a456-426614174000",
  role_version_id: "523e4567-e89b-12d3-a456-426614174000",
  evaluated_at: "2026-07-16T00:00:00.000Z",
};

function fakeClient(response: { data: unknown; error: { message: string } | null }): RbacRpcClient & { callCount: number } {
  let callCount = 0;
  return {
    get callCount() {
      return callCount;
    },
    async rpc(_fn, _args) {
      callCount += 1;
      return response;
    },
  };
}

describe("evaluatePermission", () => {
  test("calls evaluate_permission with the exact snake_case params", async () => {
    const client = fakeClient({ data: ALLOWED_ROW, error: null });
    const decision = await evaluatePermission(client, { authUserId: AUTH_USER_ID, tenantId: TENANT_ID, resourceModuleCode: "FIN", action: "Approve" });
    assert.equal(decision.allowed, true);
    assert.equal(client.callCount, 1);
  });

  test("wraps a database error into a typed error", async () => {
    const client = fakeClient({ data: null, error: { message: "connection reset" } });
    await assert.rejects(
      () => evaluatePermission(client, { authUserId: AUTH_USER_ID, tenantId: TENANT_ID, resourceModuleCode: "FIN", action: "Approve" }),
      RbacEvaluationError,
    );
  });

  test("rejects a null/non-object success response as an error rather than fabricating a decision", async () => {
    const client = fakeClient({ data: null, error: null });
    await assert.rejects(
      () => evaluatePermission(client, { authUserId: AUTH_USER_ID, tenantId: TENANT_ID, resourceModuleCode: "FIN", action: "Approve" }),
      RbacEvaluationError,
    );
  });
});

describe("RbacDecisionCache", () => {
  test("a cached decision is served without a second RPC call, until invalidated", async () => {
    const client = fakeClient({ data: ALLOWED_ROW, error: null });
    const cache = new RbacDecisionCache(60_000);
    const now = 1_000_000;

    await evaluatePermission(client, { authUserId: AUTH_USER_ID, tenantId: TENANT_ID, resourceModuleCode: "FIN", action: "Approve" }, cache, now);
    await evaluatePermission(client, { authUserId: AUTH_USER_ID, tenantId: TENANT_ID, resourceModuleCode: "FIN", action: "Approve" }, cache, now);
    assert.equal(client.callCount, 1);

    cache.invalidate(TENANT_ID, AUTH_USER_ID);
    await evaluatePermission(client, { authUserId: AUTH_USER_ID, tenantId: TENANT_ID, resourceModuleCode: "FIN", action: "Approve" }, cache, now);
    assert.equal(client.callCount, 2);
  });

  test("a distinct permission for the same identity is cached separately", async () => {
    const client = fakeClient({ data: ALLOWED_ROW, error: null });
    const cache = new RbacDecisionCache(60_000);
    const now = 1_000_000;

    await evaluatePermission(client, { authUserId: AUTH_USER_ID, tenantId: TENANT_ID, resourceModuleCode: "FIN", action: "Approve" }, cache, now);
    await evaluatePermission(client, { authUserId: AUTH_USER_ID, tenantId: TENANT_ID, resourceModuleCode: "FIN", action: "Reject" }, cache, now);
    assert.equal(client.callCount, 2);
  });

  test("an expired entry (past the TTL) is treated as a miss", async () => {
    const client = fakeClient({ data: ALLOWED_ROW, error: null });
    const cache = new RbacDecisionCache(1_000);

    await evaluatePermission(client, { authUserId: AUTH_USER_ID, tenantId: TENANT_ID, resourceModuleCode: "FIN", action: "Approve" }, cache, 0);
    await evaluatePermission(client, { authUserId: AUTH_USER_ID, tenantId: TENANT_ID, resourceModuleCode: "FIN", action: "Approve" }, cache, 5_000);
    assert.equal(client.callCount, 2);
  });
});
