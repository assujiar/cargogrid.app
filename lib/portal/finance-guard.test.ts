import { test, describe } from "node:test";
import assert from "node:assert/strict";
import { resolveFinanceAccess, type FinanceGuardDeps, type TenantLookupResult } from "./finance-guard.ts";

const TENANT: TenantLookupResult = { id: "123e4567-e89b-12d3-a456-426614174000", slug: "acme", canonicalStatus: "active" };
const AUTH_USER_ID = "223e4567-e89b-12d3-a456-426614174000";

function deps(overrides: Partial<FinanceGuardDeps> = {}): FinanceGuardDeps {
  return {
    getCurrentUserId: async () => AUTH_USER_ID,
    findTenantBySlug: async () => TENANT,
    resolveAccessContext: async () => ({ layer: "org_user", tenantId: TENANT.id }),
    ...overrides,
  };
}

describe("resolveFinanceAccess", () => {
  test("returns unauthenticated when there is no current user", async () => {
    const result = await resolveFinanceAccess(deps({ getCurrentUserId: async () => null }), "acme");
    assert.equal(result.status, "unauthenticated");
  });

  test("returns tenant_not_found_or_not_member when the tenant lookup returns null", async () => {
    const result = await resolveFinanceAccess(deps({ findTenantBySlug: async () => null }), "does-not-exist");
    assert.equal(result.status, "tenant_not_found_or_not_member");
  });

  test("returns tenant_suspended for a non-active tenant, without ever calling resolveAccessContext", async () => {
    let accessContextCalled = false;
    const result = await resolveFinanceAccess(
      deps({
        findTenantBySlug: async () => ({ ...TENANT, canonicalStatus: "suspended" }),
        resolveAccessContext: async () => {
          accessContextCalled = true;
          return { layer: "org_user", tenantId: TENANT.id };
        },
      }),
      "acme",
    );
    assert.equal(result.status, "tenant_suspended");
    assert.equal(accessContextCalled, false);
  });

  test("returns allowed for an org_user (regular Finance-role holder) membership", async () => {
    const result = await resolveFinanceAccess(deps(), "acme");
    assert.equal(result.status, "allowed");
    if (result.status === "allowed") {
      assert.equal(result.layer, "org_user");
    }
  });

  test("returns allowed for a tenant_admin membership too", async () => {
    const result = await resolveFinanceAccess(deps({ resolveAccessContext: async () => ({ layer: "tenant_admin", tenantId: TENANT.id }) }), "acme");
    assert.equal(result.status, "allowed");
    if (result.status === "allowed") {
      assert.equal(result.layer, "tenant_admin");
    }
  });

  test("returns forbidden for a Supreme Admin (a distinct portal, never silently granted Finance access)", async () => {
    const result = await resolveFinanceAccess(deps({ resolveAccessContext: async () => ({ layer: "supreme_admin", tenantId: null }) }), "acme");
    assert.equal(result.status, "forbidden");
  });

  test("returns forbidden for a customer_user (Finance Configuration is internal Finance UX only, never a Customer Portal surface)", async () => {
    const result = await resolveFinanceAccess(deps({ resolveAccessContext: async () => ({ layer: "customer_user", tenantId: TENANT.id }) }), "acme");
    assert.equal(result.status, "forbidden");
  });

  test("returns forbidden when no active membership context resolves", async () => {
    const result = await resolveFinanceAccess(deps({ resolveAccessContext: async () => null }), "acme");
    assert.equal(result.status, "forbidden");
    if (result.status === "forbidden") {
      assert.equal(result.layer, "none");
    }
  });
});
