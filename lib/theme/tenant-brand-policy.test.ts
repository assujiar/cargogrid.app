import { test, describe } from "node:test";
import assert from "node:assert/strict";
import { evaluateTenantBrandPolicy } from "./tenant-brand-policy.ts";

describe("evaluateTenantBrandPolicy", () => {
  test("empty tokens are ok (no override proposed)", () => {
    const result = evaluateTenantBrandPolicy({});
    assert.equal(result.ok, true);
    assert.deepEqual(result.violations, []);
  });

  test("CargoGrid's own default primary/secondary (ADR-0016) never trips its own policy", () => {
    const result = evaluateTenantBrandPolicy({ primary: "#0097B2", secondary: "#CB3421" });
    assert.equal(result.ok, true);
    assert.deepEqual(result.violations, []);
  });

  test("a tenant primary exactly equal to the reserved danger color is rejected (red-primary-tenant case)", () => {
    const result = evaluateTenantBrandPolicy({ primary: "#B91C1C" });
    assert.equal(result.ok, false);
    assert.equal(result.violations.length, 1);
    assert.equal(result.violations[0]?.code, "near_duplicate_of_semantic_color");
  });

  test("a tenant primary near-identical (not exact) to a reserved semantic color is still rejected", () => {
    const result = evaluateTenantBrandPolicy({ primary: "#B81C1C" }); // one off from danger #B91C1C
    assert.equal(result.ok, false);
    assert.equal(result.violations[0]?.code, "near_duplicate_of_semantic_color");
  });

  test("a legitimate brand red that is merely in the same hue family as danger is accepted", () => {
    // Distance from #B91C1C (danger) is ~30, well above the near-duplicate threshold.
    const result = evaluateTenantBrandPolicy({ primary: "#CB3421" });
    assert.equal(result.ok, true);
  });

  test("identical primary and secondary are rejected as indistinguishable from each other", () => {
    const result = evaluateTenantBrandPolicy({ primary: "#336699", secondary: "#336699" });
    assert.equal(result.ok, false);
    assert.ok(result.violations.some((v) => v.code === "primary_secondary_indistinguishable"));
  });

  test("an invalid hex value is rejected with a distinct violation code", () => {
    const result = evaluateTenantBrandPolicy({ primary: "not-a-color" });
    assert.equal(result.ok, false);
    assert.equal(result.violations[0]?.code, "invalid_hex");
  });

  test("a tenant primary near-duplicate of warning is rejected", () => {
    const result = evaluateTenantBrandPolicy({ primary: "#B45309" }); // exactly warning
    assert.equal(result.ok, false);
    assert.ok(result.violations.some((v) => v.message.includes("warning")));
  });
});
