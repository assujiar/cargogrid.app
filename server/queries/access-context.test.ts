import { test, describe } from "node:test";
import assert from "node:assert/strict";
import { resolveAccessContext, AccessContextResolutionError, type AccessContextRpcClient } from "./access-context.ts";

const AUTH_USER_ID = "123e4567-e89b-12d3-a456-426614174000";
const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";

const CONTEXT_ROW = {
  membership_id: "323e4567-e89b-12d3-a456-426614174000",
  auth_user_id: AUTH_USER_ID,
  layer: "tenant_admin",
  tenant_id: TENANT_ID,
  customer_account_ref: null,
  resolved_at: "2026-07-16T00:00:00.000Z",
};

function fakeClient(response: { data: unknown; error: { message: string } | null }): AccessContextRpcClient & {
  calls: { fn: string; args: Record<string, unknown> }[];
} {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];
  return {
    calls,
    async rpc(fn, args) {
      calls.push({ fn, args });
      return response;
    },
  };
}

describe("resolveAccessContext", () => {
  test("calls resolve_access_context with the exact snake_case params the SQL function expects, defaulting tenant/customer to null", async () => {
    const client = fakeClient({ data: CONTEXT_ROW, error: null });
    const ctx = await resolveAccessContext(client, { authUserId: AUTH_USER_ID });

    assert.equal(client.calls[0]?.fn, "resolve_access_context");
    assert.equal(client.calls[0]?.args.p_auth_user_id, AUTH_USER_ID);
    assert.equal(client.calls[0]?.args.p_tenant_id, null);
    assert.equal(client.calls[0]?.args.p_customer_account_ref, null);
    assert.equal(ctx.layer, "tenant_admin");
  });

  test("classifies a known fail-closed reason (e.g. ambiguous_context) into its typed error code", async () => {
    const client = fakeClient({ data: null, error: { message: "ambiguous_context: identity holds 2 active memberships, tenant_id must be specified" } });
    await assert.rejects(
      () => resolveAccessContext(client, { authUserId: AUTH_USER_ID }),
      (err: unknown) => {
        assert.ok(err instanceof AccessContextResolutionError);
        assert.equal(err.code, "ambiguous_context");
        return true;
      },
    );
  });

  test("classifies an inactive_tenant failure distinctly from an inactive_identity_link failure", async () => {
    const inactiveTenantClient = fakeClient({ data: null, error: { message: "inactive_tenant: tenant is not active" } });
    await assert.rejects(
      () => resolveAccessContext(inactiveTenantClient, { authUserId: AUTH_USER_ID, tenantId: TENANT_ID }),
      (err: unknown) => {
        assert.ok(err instanceof AccessContextResolutionError);
        assert.equal(err.code, "inactive_tenant");
        return true;
      },
    );

    const inactiveLinkClient = fakeClient({ data: null, error: { message: "inactive_identity_link: identity has no active linkage to tenant" } });
    await assert.rejects(
      () => resolveAccessContext(inactiveLinkClient, { authUserId: AUTH_USER_ID, tenantId: TENANT_ID }),
      (err: unknown) => {
        assert.ok(err instanceof AccessContextResolutionError);
        assert.equal(err.code, "inactive_identity_link");
        return true;
      },
    );
  });

  test("falls back to resolution_failed for an unrecognized database error, never leaking a raw message as a code", async () => {
    const client = fakeClient({ data: null, error: { message: "connection reset by peer" } });
    await assert.rejects(
      () => resolveAccessContext(client, { authUserId: AUTH_USER_ID }),
      (err: unknown) => {
        assert.ok(err instanceof AccessContextResolutionError);
        assert.equal(err.code, "resolution_failed");
        return true;
      },
    );
  });

  test("rejects a null/non-object success response as invalid_response rather than returning a fabricated context", async () => {
    const client = fakeClient({ data: null, error: null });
    await assert.rejects(
      () => resolveAccessContext(client, { authUserId: AUTH_USER_ID }),
      (err: unknown) => {
        assert.ok(err instanceof AccessContextResolutionError);
        assert.equal(err.code, "invalid_response");
        return true;
      },
    );
  });
});
