import { test, describe } from "node:test";
import assert from "node:assert/strict";
import { assertPermission, RbacDenialError } from "./permission-check.ts";
import { RbacDecisionCache, type RbacRpcClient } from "../queries/rbac.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const AUTH_USER_ID = "123e4567-e89b-12d3-a456-426614174000";

function fakeClient(response: { data: unknown; error: { message: string } | null }): RbacRpcClient {
  return { async rpc() { return response; } };
}

describe("assertPermission", () => {
  test("returns the decision when allowed", async () => {
    const client = fakeClient({
      data: {
        allowed: true, reason: "role_grant",
        permission_id: "323e4567-e89b-12d3-a456-426614174000",
        role_id: "423e4567-e89b-12d3-a456-426614174000",
        role_version_id: "523e4567-e89b-12d3-a456-426614174000",
        evaluated_at: "2026-07-16T00:00:00.000Z",
      },
      error: null,
    });
    const decision = await assertPermission(client, { authUserId: AUTH_USER_ID, tenantId: TENANT_ID, resourceModuleCode: "FIN", action: "Approve" });
    assert.equal(decision.allowed, true);
  });

  test("throws a typed RbacDenialError carrying the reason and input when denied -- never a silent false", async () => {
    const client = fakeClient({
      data: {
        allowed: false, reason: "no_active_assignment",
        permission_id: "323e4567-e89b-12d3-a456-426614174000",
        role_id: null, role_version_id: null,
        evaluated_at: "2026-07-16T00:00:00.000Z",
      },
      error: null,
    });
    await assert.rejects(
      () => assertPermission(client, { authUserId: AUTH_USER_ID, tenantId: TENANT_ID, resourceModuleCode: "FIN", action: "Approve" }),
      (err: unknown) => {
        assert.ok(err instanceof RbacDenialError);
        assert.equal(err.reason, "no_active_assignment");
        assert.equal(err.input.action, "Approve");
        return true;
      },
    );
  });

  test("passes an optional cache through to the underlying evaluator", async () => {
    let calls = 0;
    const client: RbacRpcClient = {
      async rpc() {
        calls += 1;
        return {
          data: {
            allowed: true, reason: "role_grant",
            permission_id: "323e4567-e89b-12d3-a456-426614174000",
            role_id: "423e4567-e89b-12d3-a456-426614174000",
            role_version_id: "523e4567-e89b-12d3-a456-426614174000",
            evaluated_at: "2026-07-16T00:00:00.000Z",
          },
          error: null,
        };
      },
    };
    const cache = new RbacDecisionCache(60_000);
    await assertPermission(client, { authUserId: AUTH_USER_ID, tenantId: TENANT_ID, resourceModuleCode: "FIN", action: "Approve" }, cache);
    await assertPermission(client, { authUserId: AUTH_USER_ID, tenantId: TENANT_ID, resourceModuleCode: "FIN", action: "Approve" }, cache);
    assert.equal(calls, 1);
  });
});
