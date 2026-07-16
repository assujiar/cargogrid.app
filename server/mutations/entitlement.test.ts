import { test, describe } from "node:test";
import assert from "node:assert/strict";
import { assignEntitlement, transitionEntitlementStatus, EntitlementMutationError, type EntitlementMutationClient } from "./entitlement.ts";
import { EntitlementCache, evaluateEntitlement, type EntitlementRpcClient } from "../queries/entitlement.ts";

const TENANT_ID = "123e4567-e89b-12d3-a456-426614174000";
const PACKAGE_ID = "223e4567-e89b-12d3-a456-426614174000";

function fakeClient(response: { data: unknown; error: { message: string } | null }): EntitlementMutationClient & { calls: { fn: string; args: Record<string, unknown> }[] } {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];
  return {
    calls,
    async rpc(fn, args) {
      calls.push({ fn, args });
      return response;
    },
  };
}

describe("assignEntitlement", () => {
  test("calls assign_entitlement with the exact snake_case params the SQL function expects", async () => {
    const client = fakeClient({ data: { id: "row-1" }, error: null });
    await assignEntitlement(client, { tenantId: TENANT_ID, packageId: PACKAGE_ID, status: "trial", reason: "onboarding", requestedBy: "supreme-admin-1" });

    assert.equal(client.calls[0]?.fn, "assign_entitlement");
    assert.equal(client.calls[0]?.args.p_tenant_id, TENANT_ID);
    assert.equal(client.calls[0]?.args.p_package_id, PACKAGE_ID);
    assert.equal(client.calls[0]?.args.p_status, "trial");
  });

  test("wraps a database error into a typed EntitlementMutationError", async () => {
    const client = fakeClient({ data: null, error: { message: "invalid_entitlement_transition" } });
    await assert.rejects(
      () => assignEntitlement(client, { tenantId: TENANT_ID, packageId: PACKAGE_ID, status: "active", reason: "x", requestedBy: "x" }),
      (err: unknown) => {
        assert.ok(err instanceof EntitlementMutationError);
        assert.equal(err.code, "assign_failed");
        return true;
      },
    );
  });

  test("invalidates the tenant's cache entry on success, forcing the next evaluation to re-fetch", async () => {
    const mutationClient = fakeClient({ data: { id: "row-1" }, error: null });
    const evaluationClient: EntitlementRpcClient = {
      async rpc() {
        return { data: { allowed: true, reason: "package_granted", limit_value: null, package_code: "professional", evaluated_at: "2026-07-16T00:00:00.000Z" }, error: null };
      },
    };
    const cache = new EntitlementCache(60_000);

    await evaluateEntitlement(evaluationClient, { tenantId: TENANT_ID, moduleCode: "COM" }, cache, 1_000_000);
    await assignEntitlement(mutationClient, { tenantId: TENANT_ID, packageId: PACKAGE_ID, status: "active", reason: "plan change", requestedBy: "x" }, cache);

    let secondCallHappened = false;
    const trackedClient: EntitlementRpcClient = {
      async rpc() {
        secondCallHappened = true;
        return { data: { allowed: true, reason: "package_granted", limit_value: null, package_code: "starter", evaluated_at: "2026-07-16T00:00:00.000Z" }, error: null };
      },
    };
    await evaluateEntitlement(trackedClient, { tenantId: TENANT_ID, moduleCode: "COM" }, cache, 1_000_000);
    assert.equal(secondCallHappened, true, "assignEntitlement must invalidate the cache so the next evaluate() call re-fetches, not serve a stale decision");
  });
});

describe("transitionEntitlementStatus", () => {
  test("calls transition_entitlement_status with the exact snake_case params the SQL function expects", async () => {
    const client = fakeClient({ data: { id: "row-1" }, error: null });
    await transitionEntitlementStatus(client, { tenantId: TENANT_ID, newStatus: "suspended", reason: "billing hold", requestedBy: "supreme-admin-1" });

    assert.equal(client.calls[0]?.fn, "transition_entitlement_status");
    assert.equal(client.calls[0]?.args.p_new_status, "suspended");
  });

  test("wraps a database error (e.g. a terminal-state transition rejected by the trigger) into a typed error", async () => {
    const client = fakeClient({ data: null, error: { message: "invalid_entitlement_transition: cancelled has no further transition" } });
    await assert.rejects(
      () => transitionEntitlementStatus(client, { tenantId: TENANT_ID, newStatus: "active", reason: "x", requestedBy: "x" }),
      (err: unknown) => {
        assert.ok(err instanceof EntitlementMutationError);
        assert.equal(err.code, "transition_failed");
        return true;
      },
    );
  });
});
