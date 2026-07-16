import { test, describe } from "node:test";
import assert from "node:assert/strict";
import { EvaluateEntitlementInputSchema, AssignEntitlementInputSchema, TransitionEntitlementInputSchema, parseEntitlementDecision } from "./entitlement.ts";

describe("EvaluateEntitlementInputSchema", () => {
  test("accepts a well-formed evaluation request with an optional feature code", () => {
    const parsed = EvaluateEntitlementInputSchema.parse({ tenantId: "123e4567-e89b-12d3-a456-426614174000", moduleCode: "COM" });
    assert.equal(parsed.moduleCode, "COM");
    assert.equal(parsed.featureCode, undefined);
  });

  test("rejects a non-UUID tenantId", () => {
    assert.throws(() => EvaluateEntitlementInputSchema.parse({ tenantId: "not-a-uuid", moduleCode: "COM" }));
  });

  test("rejects an empty moduleCode", () => {
    assert.throws(() => EvaluateEntitlementInputSchema.parse({ tenantId: "123e4567-e89b-12d3-a456-426614174000", moduleCode: "" }));
  });
});

describe("AssignEntitlementInputSchema", () => {
  test("accepts trial or active status only (assignment never starts suspended/expired/cancelled)", () => {
    assert.doesNotThrow(() =>
      AssignEntitlementInputSchema.parse({
        tenantId: "123e4567-e89b-12d3-a456-426614174000",
        packageId: "223e4567-e89b-12d3-a456-426614174000",
        status: "trial",
        reason: "onboarding",
        requestedBy: "supreme-admin-1",
      }),
    );
    assert.throws(() =>
      AssignEntitlementInputSchema.parse({
        tenantId: "123e4567-e89b-12d3-a456-426614174000",
        packageId: "223e4567-e89b-12d3-a456-426614174000",
        status: "suspended",
        reason: "onboarding",
        requestedBy: "supreme-admin-1",
      }),
    );
  });
});

describe("TransitionEntitlementInputSchema", () => {
  test("accepts any canonical status as a transition target", () => {
    const parsed = TransitionEntitlementInputSchema.parse({
      tenantId: "123e4567-e89b-12d3-a456-426614174000",
      newStatus: "suspended",
      reason: "billing hold",
      requestedBy: "supreme-admin-1",
    });
    assert.equal(parsed.newStatus, "suspended");
  });

  test("rejects a status outside the canonical enum", () => {
    assert.throws(() =>
      TransitionEntitlementInputSchema.parse({ tenantId: "123e4567-e89b-12d3-a456-426614174000", newStatus: "archived", reason: "x", requestedBy: "x" }),
    );
  });
});

describe("parseEntitlementDecision", () => {
  test("maps a real snake_case Postgres composite row to the camelCase contract shape", () => {
    const decision = parseEntitlementDecision({
      allowed: true,
      reason: "package_granted",
      limit_value: 50,
      package_code: "professional",
      evaluated_at: "2026-07-16T00:00:00.000Z",
    });
    assert.equal(decision.allowed, true);
    assert.equal(decision.limitValue, 50);
    assert.equal(decision.packageCode, "professional");
  });

  test("maps a null limit_value (unlimited/denied) correctly", () => {
    const decision = parseEntitlementDecision({
      allowed: false,
      reason: "no_active_entitlement",
      limit_value: null,
      package_code: null,
      evaluated_at: "2026-07-16T00:00:00.000Z",
    });
    assert.equal(decision.limitValue, null);
    assert.equal(decision.packageCode, null);
  });
});
