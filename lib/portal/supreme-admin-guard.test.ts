import { test, describe } from "node:test";
import assert from "node:assert/strict";
import { resolveSupremeAdminAccess, type SupremeAdminGuardDeps } from "./supreme-admin-guard.ts";

const AUTH_USER_ID = "223e4567-e89b-12d3-a456-426614174000";

function deps(overrides: Partial<SupremeAdminGuardDeps> = {}): SupremeAdminGuardDeps {
  return {
    getCurrentUserId: async () => AUTH_USER_ID,
    resolveGlobalAccessContext: async () => ({ layer: "supreme_admin" }),
    ...overrides,
  };
}

describe("resolveSupremeAdminAccess", () => {
  test("returns unauthenticated when there is no current user", async () => {
    const result = await resolveSupremeAdminAccess(deps({ getCurrentUserId: async () => null }));
    assert.equal(result.status, "unauthenticated");
  });

  test("returns forbidden when no active membership context resolves at all", async () => {
    const result = await resolveSupremeAdminAccess(deps({ resolveGlobalAccessContext: async () => null }));
    assert.equal(result.status, "forbidden");
    if (result.status === "forbidden") {
      assert.equal(result.layer, "none");
    }
  });

  test("returns forbidden (not allowed) for a resolved context whose layer is not supreme_admin", async () => {
    const result = await resolveSupremeAdminAccess(deps({ resolveGlobalAccessContext: async () => ({ layer: "tenant_admin" }) }));
    assert.equal(result.status, "forbidden");
    if (result.status === "forbidden") {
      assert.equal(result.layer, "tenant_admin");
    }
  });

  test("returns forbidden for an org_user (never silently granted Supreme access)", async () => {
    const result = await resolveSupremeAdminAccess(deps({ resolveGlobalAccessContext: async () => ({ layer: "org_user" }) }));
    assert.equal(result.status, "forbidden");
  });

  test("returns allowed for a resolved supreme_admin context", async () => {
    const result = await resolveSupremeAdminAccess(deps());
    assert.equal(result.status, "allowed");
    if (result.status === "allowed") {
      assert.equal(result.authUserId, AUTH_USER_ID);
      assert.equal(result.layer, "supreme_admin");
    }
  });
});
