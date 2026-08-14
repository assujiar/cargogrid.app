import { test, describe } from "node:test";
import assert from "node:assert/strict";
import { resolveCustomerTicketAccess, type CustomerTicketGuardDeps, type TenantLookupResult } from "./customer-ticket-guard.ts";

const TENANT: TenantLookupResult = { id: "123e4567-e89b-12d3-a456-426614174000", slug: "acme", canonicalStatus: "active" };
const AUTH_USER_ID = "223e4567-e89b-12d3-a456-426614174000";

function deps(overrides: Partial<CustomerTicketGuardDeps> = {}): CustomerTicketGuardDeps {
  return {
    getCurrentUserId: async () => AUTH_USER_ID,
    findTenantBySlug: async () => TENANT,
    actorHoldsCustomerUserLayer: async () => true,
    ...overrides,
  };
}

describe("resolveCustomerTicketAccess", () => {
  test("returns unauthenticated when there is no current user", async () => {
    const result = await resolveCustomerTicketAccess(deps({ getCurrentUserId: async () => null }), "acme");
    assert.equal(result.status, "unauthenticated");
  });

  test("returns tenant_not_found when the tenant lookup returns null", async () => {
    const result = await resolveCustomerTicketAccess(deps({ findTenantBySlug: async () => null }), "does-not-exist");
    assert.equal(result.status, "tenant_not_found");
  });

  test("returns tenant_suspended for a non-active tenant, without ever checking customer_user layer", async () => {
    let layerCheckCalled = false;
    const result = await resolveCustomerTicketAccess(
      deps({
        findTenantBySlug: async () => ({ ...TENANT, canonicalStatus: "suspended" }),
        actorHoldsCustomerUserLayer: async () => {
          layerCheckCalled = true;
          return true;
        },
      }),
      "acme",
    );
    assert.equal(result.status, "tenant_suspended");
    assert.equal(layerCheckCalled, false);
  });

  test("returns allowed for a real, active customer_user membership", async () => {
    const result = await resolveCustomerTicketAccess(deps(), "acme");
    assert.equal(result.status, "allowed");
    if (result.status === "allowed") {
      assert.equal(result.authUserId, AUTH_USER_ID);
      assert.equal(result.tenant.slug, "acme");
    }
  });

  test("returns forbidden for an org_user/tenant_admin (the STAFF ticket workspace is a different guard/route family, never this one)", async () => {
    const result = await resolveCustomerTicketAccess(deps({ actorHoldsCustomerUserLayer: async () => false }), "acme");
    assert.equal(result.status, "forbidden");
  });

  test("returns forbidden for a revoked customer_user membership -- the guard reflects the live RPC, never a cached grant", async () => {
    let calls = 0;
    const result = await resolveCustomerTicketAccess(
      deps({
        actorHoldsCustomerUserLayer: async () => {
          calls += 1;
          return false;
        },
      }),
      "acme",
    );
    assert.equal(result.status, "forbidden");
    assert.equal(calls, 1);
  });
});
