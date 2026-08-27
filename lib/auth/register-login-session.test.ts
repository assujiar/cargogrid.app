import { test, describe } from "node:test";
import assert from "node:assert/strict";
import { registerLoginSessionIfApplicable, type RegisterLoginSessionDeps } from "./register-login-session.ts";

const TENANT_ID = "123e4567-e89b-12d3-a456-426614174000";
const AUTH_USER_ID = "223e4567-e89b-12d3-a456-426614174000";

function deps(overrides: Partial<RegisterLoginSessionDeps> = {}): RegisterLoginSessionDeps {
  return {
    findTenantBySlug: async () => ({ id: TENANT_ID }),
    resolveAccessContext: async () => ({ layer: "org_user" }),
    registerSession: async () => {},
    ...overrides,
  };
}

describe("registerLoginSessionIfApplicable", () => {
  test("does nothing for a blank tenant slug (the Supreme Admin path)", async () => {
    let called = false;
    await registerLoginSessionIfApplicable(deps({ registerSession: async () => { called = true; } }), {
      tenantSlug: "",
      authUserId: AUTH_USER_ID,
      actorLabel: "admin@example.test",
    });
    assert.equal(called, false);
  });

  test("does nothing when the tenant slug does not resolve to a real tenant", async () => {
    let accessContextCalled = false;
    let registerCalled = false;
    await registerLoginSessionIfApplicable(
      deps({
        findTenantBySlug: async () => null,
        resolveAccessContext: async () => {
          accessContextCalled = true;
          return { layer: "org_user" };
        },
        registerSession: async () => { registerCalled = true; },
      }),
      { tenantSlug: "does-not-exist", authUserId: AUTH_USER_ID, actorLabel: "user@example.test" },
    );
    assert.equal(accessContextCalled, false);
    assert.equal(registerCalled, false);
  });

  test("does nothing when the identity holds no active membership in the resolved tenant", async () => {
    let called = false;
    await registerLoginSessionIfApplicable(
      deps({
        resolveAccessContext: async () => null,
        registerSession: async () => { called = true; },
      }),
      { tenantSlug: "acme", authUserId: AUTH_USER_ID, actorLabel: "user@example.test" },
    );
    assert.equal(called, false);
  });

  test("registers a session with the resolved tenant id, the real auth user id, and the given actor label", async () => {
    const calls: Array<{ tenantId: string; authUserId: string; actorLabel: string }> = [];
    await registerLoginSessionIfApplicable(
      deps({
        registerSession: async (tenantId, authUserId, actorLabel) => {
          calls.push({ tenantId, authUserId, actorLabel });
        },
      }),
      { tenantSlug: "acme", authUserId: AUTH_USER_ID, actorLabel: "user@example.test" },
    );
    assert.deepEqual(calls, [{ tenantId: TENANT_ID, authUserId: AUTH_USER_ID, actorLabel: "user@example.test" }]);
  });

  test("propagates a real error from registerSession -- the caller (login/actions.ts) is responsible for treating this as best-effort, not this function", async () => {
    await assert.rejects(
      registerLoginSessionIfApplicable(
        deps({
          registerSession: async () => {
            throw new Error("rpc failed");
          },
        }),
        { tenantSlug: "acme", authUserId: AUTH_USER_ID, actorLabel: "user@example.test" },
      ),
      /rpc failed/,
    );
  });
});
