import { test, describe } from "node:test";
import assert from "node:assert/strict";
import { bucketFor, evaluate, evaluateWithFallback, validateFlagRegistry, FlagCache, type FlagDefinition, type EvaluationContext } from "./flags.ts";

function baseFlag(overrides: Partial<FlagDefinition> = {}): FlagDefinition {
  return {
    id: "flag.test",
    description: "test flag",
    owner: "Platform",
    environments: ["production"],
    killSwitch: false,
    rolloutPercentage: 100,
    ...overrides,
  };
}

function baseContext(overrides: Partial<EvaluationContext> = {}): EvaluationContext {
  return {
    tenantId: "tenant-1",
    environment: "production",
    cohorts: [],
    now: new Date("2026-07-16T00:00:00.000Z"),
    ...overrides,
  };
}

describe("bucketFor — deterministic rollout bucketing", () => {
  test("the same tenant and flag always bucket identically", () => {
    assert.equal(bucketFor("tenant-1", "flag.a"), bucketFor("tenant-1", "flag.a"));
  });

  test("stays within [0, 100)", () => {
    for (let i = 0; i < 50; i++) {
      const bucket = bucketFor(`tenant-${i}`, "flag.a");
      assert.ok(bucket >= 0 && bucket < 100);
    }
  });

  test("is roughly uniform across many synthetic tenants (statistical sanity check, not proof)", () => {
    let below50 = 0;
    const sampleSize = 500;
    for (let i = 0; i < sampleSize; i++) {
      if (bucketFor(`synthetic-tenant-${i}`, "flag.uniformity-check") < 50) below50++;
    }
    const ratio = below50 / sampleSize;
    assert.ok(ratio > 0.35 && ratio < 0.65, `expected roughly half below 50, got ratio ${ratio}`);
  });

  test("different flag ids are not all identical for the same tenant (independent bucketing, not one shared value)", () => {
    const buckets = new Set(["flag.a", "flag.b", "flag.c", "flag.d", "flag.e"].map((flagId) => bucketFor("tenant-1", flagId)));
    assert.ok(buckets.size > 1, "expected at least two distinct buckets across 5 different flags for the same tenant");
  });
});

describe("evaluate — precedence order (docs/standards/FEATURE_FLAG_STANDARDS.md §2)", () => {
  test("kill switch overrides a 100% rollout", () => {
    const flag = baseFlag({ killSwitch: true, rolloutPercentage: 100 });
    const result = evaluate(flag, baseContext());
    assert.equal(result.enabled, false);
    assert.equal(result.reason, "kill_switch");
  });

  test("environment gate rejects an environment not in the allowlist", () => {
    const flag = baseFlag({ environments: ["staging"] });
    const result = evaluate(flag, baseContext({ environment: "production" }));
    assert.equal(result.enabled, false);
    assert.equal(result.reason, "environment_gate");
  });

  test("effective-date window rejects before effectiveFrom", () => {
    const flag = baseFlag({ effectiveFrom: "2026-08-01T00:00:00.000Z" });
    const result = evaluate(flag, baseContext({ now: new Date("2026-07-16T00:00:00.000Z") }));
    assert.equal(result.enabled, false);
    assert.equal(result.reason, "effective_date_window");
  });

  test("effective-date window rejects after effectiveUntil", () => {
    const flag = baseFlag({ effectiveUntil: "2026-01-01T00:00:00.000Z" });
    const result = evaluate(flag, baseContext({ now: new Date("2026-07-16T00:00:00.000Z") }));
    assert.equal(result.enabled, false);
    assert.equal(result.reason, "effective_date_window");
  });

  test("effective-date window accepts within the range", () => {
    const flag = baseFlag({ effectiveFrom: "2026-01-01T00:00:00.000Z", effectiveUntil: "2026-12-31T00:00:00.000Z" });
    const result = evaluate(flag, baseContext());
    assert.equal(result.enabled, true);
  });

  test("tenant deny list rejects even at 100% rollout", () => {
    const flag = baseFlag({ tenantDenyList: ["tenant-1"] });
    const result = evaluate(flag, baseContext({ tenantId: "tenant-1" }));
    assert.equal(result.enabled, false);
    assert.equal(result.reason, "tenant_deny_list");
  });

  test("tenant allow list accepts even at 0% rollout", () => {
    const flag = baseFlag({ rolloutPercentage: 0, tenantAllowList: ["tenant-1"] });
    const result = evaluate(flag, baseContext({ tenantId: "tenant-1" }));
    assert.equal(result.enabled, true);
    assert.equal(result.reason, "tenant_allow_list");
  });

  test("cohort mismatch rejects when cohorts are defined and none match", () => {
    const flag = baseFlag({ cohorts: ["beta_testers"] });
    const result = evaluate(flag, baseContext({ cohorts: ["general"] }));
    assert.equal(result.enabled, false);
    assert.equal(result.reason, "cohort_mismatch");
  });

  test("cohort match accepts when at least one cohort overlaps", () => {
    const flag = baseFlag({ cohorts: ["beta_testers", "internal"] });
    const result = evaluate(flag, baseContext({ cohorts: ["general", "internal"] }));
    assert.equal(result.enabled, true);
  });

  test("no cohort restriction falls through to rollout evaluation", () => {
    const flag = baseFlag({ rolloutPercentage: 100 });
    const result = evaluate(flag, baseContext());
    assert.equal(result.enabled, true);
    assert.equal(result.reason, "rollout_bucket");
  });

  test("0% rollout with no other rule rejects by default", () => {
    const flag = baseFlag({ rolloutPercentage: 0 });
    const result = evaluate(flag, baseContext());
    assert.equal(result.enabled, false);
    assert.equal(result.reason, "default");
  });
});

describe("evaluateWithFallback — safe unavailable/unknown behavior (§4, never throws)", () => {
  test("an undefined registry returns degraded=true, unknown=true, and the safe default", () => {
    const result = evaluateWithFallback("flag.missing", undefined, baseContext(), false);
    assert.deepEqual(result, { enabled: false, unknown: true, degraded: true });
  });

  test("a flag id with no matching definition returns unknown=true, degraded=false", () => {
    const result = evaluateWithFallback("flag.does-not-exist", [baseFlag()], baseContext(), false);
    assert.equal(result.unknown, true);
    assert.equal(result.degraded, false);
    assert.equal(result.enabled, false);
  });

  test("respects the caller-supplied safe default for an unknown flag", () => {
    const result = evaluateWithFallback("flag.does-not-exist", [], baseContext(), true);
    assert.equal(result.enabled, true);
    assert.equal(result.unknown, true);
  });

  test("a known, valid flag evaluates normally through the fallback wrapper", () => {
    const result = evaluateWithFallback("flag.test", [baseFlag({ rolloutPercentage: 100 })], baseContext(), false);
    assert.equal(result.unknown, false);
    assert.equal(result.enabled, true);
    assert.equal(result.reason, "rollout_bucket");
  });
});

describe("validateFlagRegistry", () => {
  test("a well-formed registry has no violations", () => {
    assert.deepEqual(validateFlagRegistry([baseFlag()]), []);
  });

  test("flags a duplicate id", () => {
    const violations = validateFlagRegistry([baseFlag(), baseFlag()]);
    assert.ok(violations.some((v) => v.kind === "DUPLICATE_ID"));
  });

  test("flags a missing owner", () => {
    const violations = validateFlagRegistry([baseFlag({ owner: "" })]);
    assert.ok(violations.some((v) => v.kind === "MISSING_OWNER"));
  });

  test("flags a rollout percentage above 100", () => {
    const violations = validateFlagRegistry([baseFlag({ rolloutPercentage: 150 })]);
    assert.ok(violations.some((v) => v.kind === "INVALID_ROLLOUT_PERCENTAGE"));
  });

  test("flags a rollout percentage below 0", () => {
    const violations = validateFlagRegistry([baseFlag({ rolloutPercentage: -5 })]);
    assert.ok(violations.some((v) => v.kind === "INVALID_ROLLOUT_PERCENTAGE"));
  });

  test("flags effectiveFrom after effectiveUntil", () => {
    const violations = validateFlagRegistry([
      baseFlag({ effectiveFrom: "2026-12-31T00:00:00.000Z", effectiveUntil: "2026-01-01T00:00:00.000Z" }),
    ]);
    assert.ok(violations.some((v) => v.kind === "INVALID_EFFECTIVE_WINDOW"));
  });

  test("empty registry has no violations", () => {
    assert.deepEqual(validateFlagRegistry([]), []);
  });
});

describe("FlagCache — TTL expiry (§5, never serves a stale hit)", () => {
  test("a fresh entry is returned before TTL expiry", () => {
    const cache = new FlagCache(1000);
    const fixedNow = () => new Date("2026-07-16T00:00:00.000Z");
    cache.set("flag.a", { enabled: true, reason: "rollout_bucket" }, fixedNow);
    assert.deepEqual(cache.get("flag.a", fixedNow), { enabled: true, reason: "rollout_bucket" });
  });

  test("an entry past its TTL returns undefined (a fresh miss), not a stale value", () => {
    const cache = new FlagCache(1000);
    const setAt = () => new Date("2026-07-16T00:00:00.000Z");
    const getAt = () => new Date("2026-07-16T00:00:02.000Z");
    cache.set("flag.a", { enabled: true, reason: "rollout_bucket" }, setAt);
    assert.equal(cache.get("flag.a", getAt), undefined);
  });

  test("a missing key returns undefined", () => {
    const cache = new FlagCache(1000);
    assert.equal(cache.get("flag.never-set"), undefined);
  });

  test("invalidate removes an entry immediately regardless of TTL", () => {
    const cache = new FlagCache(60000);
    const fixedNow = () => new Date("2026-07-16T00:00:00.000Z");
    cache.set("flag.a", { enabled: true, reason: "rollout_bucket" }, fixedNow);
    cache.invalidate("flag.a");
    assert.equal(cache.get("flag.a", fixedNow), undefined);
  });

  test("size reflects the number of live entries", () => {
    const cache = new FlagCache(60000);
    const fixedNow = () => new Date("2026-07-16T00:00:00.000Z");
    cache.set("flag.a", { enabled: true, reason: "rollout_bucket" }, fixedNow);
    cache.set("flag.b", { enabled: false, reason: "default" }, fixedNow);
    assert.equal(cache.size(), 2);
  });
});
