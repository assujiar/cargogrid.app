import { test, describe } from "node:test";
import assert from "node:assert/strict";
import { isTaxRuleInForce, isTaxRuleUnconfirmed } from "./tax-rule-status.ts";
import type { FinanceTaxRuleVersion } from "../../server/contracts/tax-baseline/tax-baseline.ts";

/**
 * These predicates drive the unconfirmed-rate banner in the tax settings console, which exists
 * because of `RPD-016`. A banner that under-reports is worse than no banner — it would give
 * false assurance that the rate on every invoice is confirmed. So the tests below are written to
 * try to make each predicate say "fine" when it should not.
 */

const base: FinanceTaxRuleVersion = {
  id: "00000000-0000-0000-0000-000000000001",
  tenantId: null,
  taxCodeId: "00000000-0000-0000-0000-0000000000aa",
  rateBasis: "percentage",
  rateValue: 11,
  currency: null,
  outputAccountId: null,
  recoverableAccountId: null,
  effectiveFrom: "2026-01-01",
  effectiveTo: null,
  status: "approved",
  isExampleFixture: false,
  evidenceReferenceFileId: null,
  evidenceNote: "Confirmed by tax adviser, PMK ref on file",
  approvedBy: "finance-controller",
  approvedAt: "2026-01-02T00:00:00Z",
  archivedReason: null,
  recordVersion: 1,
  createdBy: null,
  createdAt: "2026-01-01T00:00:00Z",
  updatedAt: "2026-01-01T00:00:00Z",
};

const rule = (o: Partial<FinanceTaxRuleVersion> = {}): FinanceTaxRuleVersion => ({ ...base, ...o });
const on = (day: string): Date => new Date(`${day}T12:00:00Z`);

describe("isTaxRuleInForce", () => {
  test("an approved rule with an open-ended window is in force from its start date", () => {
    assert.equal(isTaxRuleInForce(rule(), on("2026-06-01")), true);
  });

  test("only approved rules are ever in force", () => {
    // A draft rate is a proposal. Treating it as in force would let an unreviewed figure reach an
    // invoice, which is the failure this whole console exists to prevent.
    assert.equal(isTaxRuleInForce(rule({ status: "draft" }), on("2026-06-01")), false);
    assert.equal(isTaxRuleInForce(rule({ status: "archived" }), on("2026-06-01")), false);
  });

  test("the effective window is inclusive at both ends", () => {
    const windowed = rule({ effectiveFrom: "2026-03-01", effectiveTo: "2026-03-31" });
    assert.equal(isTaxRuleInForce(windowed, on("2026-03-01")), true, "first day is inside");
    assert.equal(isTaxRuleInForce(windowed, on("2026-03-31")), true, "last day is inside");
    assert.equal(isTaxRuleInForce(windowed, on("2026-02-28")), false, "day before is outside");
    assert.equal(isTaxRuleInForce(windowed, on("2026-04-01")), false, "day after is outside");
  });

  test("a timestamp in the date columns does not shift the boundary", () => {
    // The columns are SQL `date`, but a row could carry a full timestamp. Comparing on the
    // YYYY-MM-DD prefix means the boundary day behaves the same either way.
    const withTimestamps = rule({ effectiveFrom: "2026-03-01T00:00:00Z", effectiveTo: "2026-03-31T23:59:59Z" });
    assert.equal(isTaxRuleInForce(withTimestamps, on("2026-03-01")), true);
    assert.equal(isTaxRuleInForce(withTimestamps, on("2026-03-31")), true);
    assert.equal(isTaxRuleInForce(withTimestamps, on("2026-04-01")), false);
  });

  test("a rule that has not started yet is not in force", () => {
    assert.equal(isTaxRuleInForce(rule({ effectiveFrom: "2027-01-01" }), on("2026-06-01")), false);
  });
});

describe("isTaxRuleUnconfirmed", () => {
  test("a fully evidenced, approved, non-fixture rule is confirmed", () => {
    assert.equal(isTaxRuleUnconfirmed(rule()), false);
  });

  test("a seeded example fixture is unconfirmed even when approved and evidenced", () => {
    // This is the RPD-016 shape exactly: the seeded PPN rate could carry an approval and still be
    // a placeholder. `isExampleFixture` must dominate.
    assert.equal(isTaxRuleUnconfirmed(rule({ isExampleFixture: true })), true);
  });

  test("an unapproved rule is unconfirmed", () => {
    assert.equal(isTaxRuleUnconfirmed(rule({ approvedBy: null })), true);
  });

  test("an approved rule with no evidence at all is unconfirmed", () => {
    // The easiest one to wave away, and the one that cannot be defended later when someone asks
    // why that figure.
    assert.equal(isTaxRuleUnconfirmed(rule({ evidenceNote: null, evidenceReferenceFileId: null })), true);
  });

  test("either form of evidence satisfies the evidence condition", () => {
    assert.equal(isTaxRuleUnconfirmed(rule({ evidenceNote: null, evidenceReferenceFileId: "00000000-0000-0000-0000-0000000000ff" })), false);
    assert.equal(isTaxRuleUnconfirmed(rule({ evidenceNote: "PMK 2026 art. 7", evidenceReferenceFileId: null })), false);
  });

  test("an empty-string note does not count as evidence", () => {
    // A blank note is the shape a careless UI produces; it must not read as confirmation.
    assert.equal(isTaxRuleUnconfirmed(rule({ evidenceNote: "", evidenceReferenceFileId: null })), true);
  });
});

describe("the two predicates together — what the banner actually flags", () => {
  test("a rate in force but unconfirmed is the case the banner must catch", () => {
    const seeded = rule({ isExampleFixture: true });
    assert.equal(isTaxRuleInForce(seeded, on("2026-06-01")), true);
    assert.equal(isTaxRuleUnconfirmed(seeded), true);
  });

  test("an unconfirmed draft is not flagged, because it is not being applied to anything", () => {
    // Flagging every unconfirmed draft would bury the one rate that is actually reaching invoices.
    const draft = rule({ status: "draft", isExampleFixture: true });
    assert.equal(isTaxRuleInForce(draft, on("2026-06-01")), false);
  });
});
