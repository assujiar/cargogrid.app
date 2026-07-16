import { test, describe } from "node:test";
import assert from "node:assert/strict";
import { computeRiskRank, validateThreatRegister, THREAT_REGISTER, STRIDE_CATEGORIES, LIKELIHOODS, IMPACTS, type ThreatEntry } from "./threat-model.ts";

describe("computeRiskRank", () => {
  test("is reproducible — same inputs always produce the same rank (Prompt 96 §25)", () => {
    assert.equal(computeRiskRank("medium", "high"), computeRiskRank("medium", "high"));
  });

  test("low likelihood and low impact is the lowest rank", () => {
    assert.equal(computeRiskRank("low", "low"), "low");
  });

  test("high likelihood and critical impact is the highest rank", () => {
    assert.equal(computeRiskRank("high", "critical"), "critical");
  });

  test("is monotonic — increasing impact at fixed likelihood never decreases the rank", () => {
    const rankOrder: Record<string, number> = { low: 0, medium: 1, high: 2, critical: 3 };
    for (const likelihood of LIKELIHOODS) {
      let previous = -1;
      for (const impact of IMPACTS) {
        const rank = rankOrder[computeRiskRank(likelihood, impact)] ?? -1;
        assert.ok(rank >= previous, `rank decreased at likelihood=${likelihood}, impact=${impact}`);
        previous = rank;
      }
    }
  });

  test("is monotonic — increasing likelihood at fixed impact never decreases the rank", () => {
    const rankOrder: Record<string, number> = { low: 0, medium: 1, high: 2, critical: 3 };
    for (const impact of IMPACTS) {
      let previous = -1;
      for (const likelihood of LIKELIHOODS) {
        const rank = rankOrder[computeRiskRank(likelihood, impact)] ?? -1;
        assert.ok(rank >= previous, `rank decreased at impact=${impact}, likelihood=${likelihood}`);
        previous = rank;
      }
    }
  });

  test("every (likelihood, impact) pair produces a defined rank", () => {
    for (const likelihood of LIKELIHOODS) {
      for (const impact of IMPACTS) {
        assert.ok(["low", "medium", "high", "critical"].includes(computeRiskRank(likelihood, impact)));
      }
    }
  });
});

describe("validateThreatRegister", () => {
  function makeEntry(overrides: Partial<ThreatEntry> = {}): ThreatEntry {
    return {
      id: "THR-TEST",
      area: "test",
      stride: ["spoofing"],
      description: "test entry",
      likelihood: "low",
      impact: "low",
      controlStatus: "existing",
      control: "a real control",
      owner: "Security",
      source: "test",
      ...overrides,
    };
  }

  test("a well-formed entry has no violations", () => {
    assert.deepEqual(validateThreatRegister([makeEntry()]), []);
  });

  test("flags a duplicate id", () => {
    const violations = validateThreatRegister([makeEntry(), makeEntry()]);
    assert.equal(violations.filter((v) => v.kind === "DUPLICATE_ID").length, 1);
  });

  test("flags a missing owner", () => {
    const violations = validateThreatRegister([makeEntry({ owner: "" })]);
    assert.ok(violations.some((v) => v.kind === "MISSING_OWNER"));
  });

  test("flags a missing control", () => {
    const violations = validateThreatRegister([makeEntry({ control: "  " })]);
    assert.ok(violations.some((v) => v.kind === "MISSING_CONTROL"));
  });

  test("flags an empty stride array", () => {
    const violations = validateThreatRegister([makeEntry({ stride: [] })]);
    assert.ok(violations.some((v) => v.kind === "EMPTY_STRIDE"));
  });

  test("flags a critical-risk entry with no owner or control (Prompt 96 §23 exception flow)", () => {
    const violations = validateThreatRegister([makeEntry({ likelihood: "high", impact: "critical", owner: "", control: "" })]);
    assert.ok(violations.some((v) => v.kind === "UNOWNED_CRITICAL_WITH_NO_CONTROL"));
  });

  test("does not flag a critical-risk entry that has both owner and control", () => {
    const violations = validateThreatRegister([makeEntry({ likelihood: "high", impact: "critical" })]);
    assert.deepEqual(
      violations.filter((v) => v.kind === "UNOWNED_CRITICAL_WITH_NO_CONTROL"),
      [],
    );
  });

  test("empty register has no violations", () => {
    assert.deepEqual(validateThreatRegister([]), []);
  });
});

describe("THREAT_REGISTER — this repository's real initial threat model", () => {
  test("is internally valid — no duplicate/unowned/uncontrolled/malformed entries", () => {
    assert.deepEqual(validateThreatRegister(THREAT_REGISTER), []);
  });

  test("covers every area Prompt 96 §20 task 2 names", () => {
    const areas = new Set(THREAT_REGISTER.map((e) => e.area));
    for (const required of ["tenants", "access", "admin", "apis", "jobs", "files", "integrations", "finance", "operations"]) {
      assert.ok(areas.has(required), `missing area: ${required}`);
    }
  });

  test("every entry's stride categories are valid", () => {
    for (const entry of THREAT_REGISTER) {
      for (const category of entry.stride) {
        assert.ok(STRIDE_CATEGORIES.includes(category));
      }
    }
  });

  test("every entry cites a real source document", () => {
    for (const entry of THREAT_REGISTER) {
      assert.ok(entry.source.length > 0, `${entry.id} has no source citation`);
    }
  });

  test("has at least one entry per control status (existing, planned, and a disclosed gap)", () => {
    const statuses = new Set(THREAT_REGISTER.map((e) => e.controlStatus));
    assert.ok(statuses.has("existing"));
    assert.ok(statuses.has("planned_phase1"));
    assert.ok(statuses.has("gap_disclosed"));
  });
});
