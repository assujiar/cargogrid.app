import { test, describe } from "node:test";
import assert from "node:assert/strict";
import { resolveTenantAdminAccess, type TenantAdminGuardDeps, type TenantLookupResult } from "./tenant-admin-guard.ts";

const TENANT: TenantLookupResult = { id: "123e4567-e89b-12d3-a456-426614174000", slug: "acme", canonicalStatus: "active" };
const AUTH_USER_ID = "223e4567-e89b-12d3-a456-426614174000";

function deps(overrides: Partial<TenantAdminGuardDeps> = {}): TenantAdminGuardDeps {
  return {
    getCurrentUserId: async () => AUTH_USER_ID,
    findTenantBySlug: async () => TENANT,
    resolveAccessContext: async () => ({ layer: "tenant_admin", tenantId: TENANT.id }),
    ...overrides,
  };
}

describe("resolveTenantAdminAccess", () => {
  test("returns unauthenticated when there is no current user", async () => {
    const result = await resolveTenantAdminAccess(deps({ getCurrentUserId: async () => null }), "acme");
    assert.equal(result.status, "unauthenticated");
  });

  test("returns tenant_not_found_or_not_member when the tenant lookup returns null (covers both non-existence and non-membership, deliberately not distinguished)", async () => {
    const result = await resolveTenantAdminAccess(deps({ findTenantBySlug: async () => null }), "does-not-exist");
    assert.equal(result.status, "tenant_not_found_or_not_member");
  });

  test("returns tenant_suspended for a non-active tenant, without ever calling resolveAccessContext", async () => {
    let accessContextCalled = false;
    const result = await resolveTenantAdminAccess(
      deps({
        findTenantBySlug: async () => ({ ...TENANT, canonicalStatus: "suspended" }),
        resolveAccessContext: async () => {
          accessContextCalled = true;
          return { layer: "tenant_admin", tenantId: TENANT.id };
        },
      }),
      "acme",
    );
    assert.equal(result.status, "tenant_suspended");
    assert.equal(accessContextCalled, false, "a suspended tenant must short-circuit before resolving access context");
  });

  test("returns forbidden when no active membership context resolves", async () => {
    const result = await resolveTenantAdminAccess(deps({ resolveAccessContext: async () => null }), "acme");
    assert.equal(result.status, "forbidden");
    if (result.status === "forbidden") {
      assert.equal(result.layer, "none");
    }
  });

  test("returns forbidden (not allowed) for a resolved context whose layer is not tenant_admin", async () => {
    const result = await resolveTenantAdminAccess(deps({ resolveAccessContext: async () => ({ layer: "org_user", tenantId: TENANT.id }) }), "acme");
    assert.equal(result.status, "forbidden");
    if (result.status === "forbidden") {
      assert.equal(result.layer, "org_user");
    }
  });

  test("returns forbidden for a Supreme Admin (a distinct portal, never silently granted tenant-admin access)", async () => {
    const result = await resolveTenantAdminAccess(deps({ resolveAccessContext: async () => ({ layer: "supreme_admin", tenantId: null }) }), "acme");
    assert.equal(result.status, "forbidden");
  });

  test("returns allowed for an active tenant_admin membership on an active tenant", async () => {
    const result = await resolveTenantAdminAccess(deps(), "acme");
    assert.equal(result.status, "allowed");
    if (result.status === "allowed") {
      assert.equal(result.tenant.id, TENANT.id);
      assert.equal(result.authUserId, AUTH_USER_ID);
    }
  });
});
