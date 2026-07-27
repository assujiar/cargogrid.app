import { test, describe } from "node:test";
import assert from "node:assert/strict";
import { resolveOperationsAccess, type OperationsGuardDeps, type TenantLookupResult } from "./operations-guard.ts";

const TENANT: TenantLookupResult = { id: "123e4567-e89b-12d3-a456-426614174000", slug: "acmeops", canonicalStatus: "active" };
const AUTH_USER_ID = "223e4567-e89b-12d3-a456-426614174000";

function deps(overrides: Partial<OperationsGuardDeps> = {}): OperationsGuardDeps {
  return {
    getCurrentUserId: async () => AUTH_USER_ID,
    findTenantBySlug: async () => TENANT,
    resolveAccessContext: async () => ({ layer: "org_user", tenantId: TENANT.id }),
    ...overrides,
  };
}

describe("resolveOperationsAccess", () => {
  test("returns unauthenticated when there is no current user", async () => {
    const result = await resolveOperationsAccess(deps({ getCurrentUserId: async () => null }), "acmeops");
    assert.equal(result.status, "unauthenticated");
  });

  test("returns tenant_not_found_or_not_member when the tenant lookup returns null", async () => {
    const result = await resolveOperationsAccess(deps({ findTenantBySlug: async () => null }), "does-not-exist");
    assert.equal(result.status, "tenant_not_found_or_not_member");
  });

  test("returns tenant_suspended for a non-active tenant, without ever calling resolveAccessContext", async () => {
    let accessContextCalled = false;
    const result = await resolveOperationsAccess(
      deps({
        findTenantBySlug: async () => ({ ...TENANT, canonicalStatus: "suspended" }),
        resolveAccessContext: async () => {
          accessContextCalled = true;
          return { layer: "org_user", tenantId: TENANT.id };
        },
      }),
      "acmeops",
    );
    assert.equal(result.status, "tenant_suspended");
    assert.equal(accessContextCalled, false);
  });

  test("returns allowed for an org_user (regular Operations user) membership", async () => {
    const result = await resolveOperationsAccess(deps(), "acmeops");
    assert.equal(result.status, "allowed");
    if (result.status === "allowed") {
      assert.equal(result.layer, "org_user");
    }
  });

  test("returns allowed for a tenant_admin membership too", async () => {
    const result = await resolveOperationsAccess(deps({ resolveAccessContext: async () => ({ layer: "tenant_admin", tenantId: TENANT.id }) }), "acmeops");
    assert.equal(result.status, "allowed");
    if (result.status === "allowed") {
      assert.equal(result.layer, "tenant_admin");
    }
  });

  test("returns forbidden for a Supreme Admin (a distinct portal, never silently granted Operations access)", async () => {
    const result = await resolveOperationsAccess(deps({ resolveAccessContext: async () => ({ layer: "supreme_admin", tenantId: null }) }), "acmeops");
    assert.equal(result.status, "forbidden");
  });

  test("returns forbidden for a customer_user (Operations is an internal workspace, not the customer-facing surface)", async () => {
    const result = await resolveOperationsAccess(deps({ resolveAccessContext: async () => ({ layer: "customer_user", tenantId: TENANT.id }) }), "acmeops");
    assert.equal(result.status, "forbidden");
  });

  test("returns forbidden when no active membership context resolves", async () => {
    const result = await resolveOperationsAccess(deps({ resolveAccessContext: async () => null }), "acmeops");
    assert.equal(result.status, "forbidden");
    if (result.status === "forbidden") {
      assert.equal(result.layer, "none");
    }
  });
});
