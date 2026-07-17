import { test, describe } from "node:test";
import assert from "node:assert/strict";
import { provisionTenant, transitionTenantStatus, TenantServiceError, type TenantRpcClient } from "./tenant.ts";

const VALID_ROW = {
  id: "123e4567-e89b-12d3-a456-426614174000",
  slug: "acme",
  name: "Acme Corp",
  canonical_status: "provisioning",
  plan_snapshot: {},
  idempotency_key: "idem-1",
  requested_by: "supreme-admin-1",
  reason: null,
  legal_hold: false,
  record_version: 1,
  effective_from: null,
  effective_until: null,
  activated_at: null,
  deactivated_at: null,
  terminated_at: null,
  created_at: "2026-07-16T00:00:00.000Z",
  updated_at: "2026-07-16T00:00:00.000Z",
};

function fakeClient(response: { data: unknown; error: { message: string } | null }): TenantRpcClient & { calls: { fn: string; args: Record<string, unknown> }[] } {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];
  return {
    calls,
    async rpc(fn, args) {
      calls.push({ fn, args });
      return response;
    },
  };
}

describe("provisionTenant", () => {
  test("calls the provision_tenant RPC with the exact snake_case params the SQL function expects", async () => {
    const client = fakeClient({ data: VALID_ROW, error: null });
    await provisionTenant(client, { slug: "acme", name: "Acme Corp", idempotencyKey: "idem-1", requestedBy: "supreme-admin-1" });

    assert.equal(client.calls.length, 1);
    assert.equal(client.calls[0]?.fn, "provision_tenant");
    assert.deepEqual(client.calls[0]?.args, {
      p_slug: "acme",
      p_name: "Acme Corp",
      p_idempotency_key: "idem-1",
      p_requested_by: "supreme-admin-1",
      p_plan_snapshot: {},
    });
  });

  test("returns a fully-typed Tenant on success", async () => {
    const client = fakeClient({ data: VALID_ROW, error: null });
    const tenant = await provisionTenant(client, { slug: "acme", name: "Acme Corp", idempotencyKey: "idem-1", requestedBy: "supreme-admin-1" });
    assert.equal(tenant.canonicalStatus, "provisioning");
    assert.equal(tenant.slug, "acme");
  });

  test("rejects invalid input before ever calling the RPC (fail before touching the database)", async () => {
    const client = fakeClient({ data: VALID_ROW, error: null });
    await assert.rejects(() => provisionTenant(client, { slug: "Not Valid", name: "x", idempotencyKey: "idem-1", requestedBy: "x" }));
    assert.equal(client.calls.length, 0);
  });

  test("wraps a database error into a typed TenantServiceError, never a raw driver error", async () => {
    const client = fakeClient({ data: null, error: { message: "duplicate key value violates unique constraint" } });
    await assert.rejects(
      () => provisionTenant(client, { slug: "acme", name: "Acme Corp", idempotencyKey: "idem-1", requestedBy: "supreme-admin-1" }),
      (err: unknown) => {
        assert.ok(err instanceof TenantServiceError);
        assert.equal(err.code, "provision_failed");
        return true;
      },
    );
  });
});

describe("transitionTenantStatus", () => {
  test("calls the transition_tenant_status RPC with the exact snake_case params the SQL function expects", async () => {
    const activeRow = { ...VALID_ROW, canonical_status: "active", activated_at: "2026-07-16T01:00:00.000Z" };
    const client = fakeClient({ data: activeRow, error: null });
    await transitionTenantStatus(client, { tenantId: VALID_ROW.id, newStatus: "active", reason: "bootstrap complete", requestedBy: "supreme-admin-1" });

    assert.equal(client.calls[0]?.fn, "transition_tenant_status");
    assert.deepEqual(client.calls[0]?.args, {
      p_tenant_id: VALID_ROW.id,
      p_new_status: "active",
      p_reason: "bootstrap complete",
      p_requested_by: "supreme-admin-1",
    });
  });

  test("wraps a database error (e.g. an invalid transition rejected by the trigger) into a typed error", async () => {
    const client = fakeClient({ data: null, error: { message: "invalid_tenant_transition: active -> provisioning is not a canonical transition" } });
    await assert.rejects(
      () => transitionTenantStatus(client, { tenantId: VALID_ROW.id, newStatus: "provisioning", reason: "x", requestedBy: "x" }),
      (err: unknown) => {
        assert.ok(err instanceof TenantServiceError);
        assert.equal(err.code, "transition_failed");
        return true;
      },
    );
  });

  test("rejects a malformed tenantId before ever calling the RPC", async () => {
    const client = fakeClient({ data: VALID_ROW, error: null });
    await assert.rejects(() => transitionTenantStatus(client, { tenantId: "not-a-uuid", newStatus: "active", reason: "x", requestedBy: "x" }));
    assert.equal(client.calls.length, 0);
  });
});
