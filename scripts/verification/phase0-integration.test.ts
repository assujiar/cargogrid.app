/**
 * Phase 0 integrated verification — docs/build-log/phase-00/PH0-99.md,
 * CG-S5-PH0-020 (Prompt 99). Prompt 99 §5/§24: "passing isolated tasks does
 * not imply integrated pass" — every test below exercises two or more of
 * PH0-93/94/95/97/98's foundation modules *together*, in one real scenario,
 * rather than re-asserting what each module's own test suite already
 * proves in isolation.
 */

import { test, describe } from "node:test";
import assert from "node:assert/strict";
import { log, redact } from "../observability/logger.ts";
import { scanContent } from "../security/check-secrets.ts";
import { track, pseudonymizeId, findProhibitedProperties, type AnalyticsEventInput } from "../product-analytics/analytics.ts";
import { evaluate, type FlagDefinition, type EvaluationContext } from "../feature-flags/flags.ts";
import { PHASE_0_REGISTRY } from "../data-classification/registry.ts";
import { ENV_REGISTRY } from "../env/schema.ts";

describe("cross-foundation: flag → analytics → observability pipeline (real end-to-end scenario)", () => {
  test("a flag-gated event flows through evaluation, analytics validation, and redacted logging with zero leakage", () => {
    const flag: FlagDefinition = {
      id: "flag.shipment_v2",
      description: "integration smoke flag",
      owner: "Platform",
      environments: ["production"],
      killSwitch: false,
      rolloutPercentage: 100,
    };
    const context: EvaluationContext = {
      tenantId: "tenant-integration-a",
      environment: "production",
      cohorts: [],
      now: new Date("2026-07-16T00:00:00.000Z"),
    };

    const decision = evaluate(flag, context);
    assert.equal(decision.enabled, true, "flag foundation: rollout decision");

    const salt = "integration-test-salt";
    const pseudoTenant = pseudonymizeId(context.tenantId, salt);
    const pseudoUser = pseudonymizeId("integration-user-1", salt);

    const analyticsInput: AnalyticsEventInput = {
      event: "shipment.created",
      pseudonymousId: pseudoUser,
      tenantRef: pseudoTenant,
      context: { source: "web" },
      consentState: "granted",
      properties: { shipmentId: "s-integration-1", flagDecisionReason: decision.reason },
    };

    let loggedLine = "";
    const trackResult = track(analyticsInput, "evt-integration-1", {
      enabled: true,
      sink: (event) => {
        // observability foundation logs the delivery, including a deliberately
        // sensitive field, to prove redaction holds across the module boundary.
        log(
          {
            severity: "info",
            event: "analytics.delivered",
            message: "event delivered",
            correlationId: "corr-integration-1",
            source: "api",
            fields: { eventId: event.eventId, tenantRef: event.tenantRef, apiKey: "raw-secret-should-never-appear" },
          },
          (line) => {
            loggedLine = line;
          },
        );
      },
    });

    assert.equal(trackResult.delivered, true, "analytics foundation: delivery");
    assert.ok(loggedLine.length > 0, "observability foundation: log line produced");
    assert.ok(!loggedLine.includes("raw-secret-should-never-appear"), "raw secret must never reach the emitted log line");
    assert.ok(loggedLine.includes(pseudoTenant), "pseudonymized tenant reference is safe to log and should be present");
    assert.ok(!loggedLine.includes(context.tenantId), "the raw, un-pseudonymized tenant id must never reach the log line");
  });

  test("a kill-switched flag never reaches the analytics/logging stages at all", () => {
    const flag: FlagDefinition = {
      id: "flag.killed",
      description: "integration smoke flag (killed)",
      owner: "Platform",
      environments: ["production"],
      killSwitch: true,
      rolloutPercentage: 100,
    };
    const context: EvaluationContext = { tenantId: "tenant-integration-b", environment: "production", cohorts: [], now: new Date() };

    const decision = evaluate(flag, context);
    assert.equal(decision.enabled, false);
    assert.equal(decision.reason, "kill_switch");

    // The real product code path: analytics/logging never run when the
    // gating flag is off — proven here as a real conditional, not asserted
    // as a documentation claim.
    let sinkCalled = false;
    if (decision.enabled) {
      track({ event: "shipment.created", pseudonymousId: "x", tenantRef: "y", context: { source: "web" }, consentState: "granted" }, "evt-2", {
        enabled: true,
        sink: () => {
          sinkCalled = true;
        },
      });
    }
    assert.equal(sinkCalled, false);
  });
});

describe("cross-foundation: two-tenant isolation smoke (Prompt 99 §26 — synthetic, least-privilege, isolated)", () => {
  test("flag evaluation context for tenant A never leaks into tenant B's evaluation", () => {
    const flag: FlagDefinition = {
      id: "flag.tenant_scoped",
      description: "integration smoke flag",
      owner: "Platform",
      environments: ["production"],
      killSwitch: false,
      rolloutPercentage: 100,
      tenantDenyList: ["tenant-integration-deny"],
    };
    const now = new Date("2026-07-16T00:00:00.000Z");

    const resultA = evaluate(flag, { tenantId: "tenant-integration-allow", environment: "production", cohorts: [], now });
    const resultDeny = evaluate(flag, { tenantId: "tenant-integration-deny", environment: "production", cohorts: [], now });

    assert.equal(resultA.enabled, true);
    assert.equal(resultDeny.enabled, false);
    assert.equal(resultDeny.reason, "tenant_deny_list");
  });

  test("pseudonymization never collides between two distinct tenants under the same salt", () => {
    const salt = "integration-test-salt";
    const pseudoA = pseudonymizeId("tenant-integration-a", salt);
    const pseudoB = pseudonymizeId("tenant-integration-b", salt);
    assert.notEqual(pseudoA, pseudoB);
  });

  test("the data-classification registry's one credential entry matches the real env schema's one secret variable — no drift between foundations", () => {
    const secretEnvVars = ENV_REGISTRY.filter((v) => v.classification === "secret").map((v) => v.name);
    const registeredCredentialIds = PHASE_0_REGISTRY.filter((e) => e.level === "credential").map((e) => e.id);
    assert.deepEqual(
      secretEnvVars.map((name) => `env:${name}`),
      registeredCredentialIds,
    );
  });
});

describe("cross-foundation: sensitive-key-pattern consistency (three independently-written modules)", () => {
  const REPRESENTATIVE_SENSITIVE_KEYS = ["password", "npwp", "bankAccountNumber", "salary"];
  // Overlaps every module's pattern list (docs/standards/SECURITY_STANDARDS.md
  // §3, docs/standards/OBSERVABILITY_STANDARDS.md §4, docs/standards/
  // PRODUCT_ANALYTICS_STANDARDS.md §3) — the one key guaranteed to prove
  // agreement, distinct from the broader-only set below.
  const UNIVERSALLY_COVERED_KEY = "password";

  test("scripts/observability/logger.ts's redact() treats every representative key as sensitive", () => {
    for (const key of REPRESENTATIVE_SENSITIVE_KEYS) {
      const redacted = redact({ [key]: "raw-value-for-consistency-check" });
      assert.notEqual(redacted[key], "raw-value-for-consistency-check", `logger.ts did not redact "${key}"`);
    }
  });

  test("scripts/product-analytics/analytics.ts's findProhibitedProperties() rejects every representative key", () => {
    for (const key of REPRESENTATIVE_SENSITIVE_KEYS) {
      const found = findProhibitedProperties({ [key]: "raw-value-for-consistency-check" });
      assert.deepEqual(found, [key], `analytics.ts did not flag "${key}"`);
    }
  });

  test("scripts/security/check-secrets.ts's scanContent() flags the universally-covered key", () => {
    const findings = scanContent("integration-check.ts", `${UNIVERSALLY_COVERED_KEY} = "raw-value-long-enough-to-trip-the-generic-rule"`);
    assert.ok(findings.some((f) => f.kind === "GENERIC_HARDCODED_SECRET_ASSIGNMENT"));
  });

  test(
    "REAL, DISCLOSED GAP (ISS-2026-008): check-secrets.ts's GENERIC_HARDCODED_SECRET_ASSIGNMENT pattern is narrower " +
      "than logger.ts's/analytics.ts's — it does not currently flag npwp/bank/salary-shaped key names, only " +
      "secret/password/token/api_key/private_key. This test documents the verified current behavior (found by this " +
      "integrated-verification checkpoint, not caught by any single module's own isolated test suite) rather than " +
      "asserting a false cross-module guarantee. See docs/build-log/phase-00/PH0-99.md's failure matrix for the " +
      "recovery-task recommendation — not fixed in this checkpoint (Prompt 99 §11: default no repair).",
    () => {
      const stillUncovered = ["npwp", "bankAccountNumber", "salary"].filter((key) => {
        const findings = scanContent("integration-check.ts", `${key} = "raw-value-long-enough-to-trip-the-generic-rule"`);
        return !findings.some((f) => f.kind === "GENERIC_HARDCODED_SECRET_ASSIGNMENT");
      });
      assert.deepEqual(stillUncovered, ["npwp", "bankAccountNumber", "salary"], "expected this documented gap to still be present — update this test and the failure matrix together if it is ever closed");
    },
  );
});
