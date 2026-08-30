import type { FinanceTaxRuleVersion } from "../../server/contracts/tax-baseline/tax-baseline.ts";

/**
 * Two questions the tax settings console has to answer about a rate version, extracted here
 * rather than left inline in the page so they can be tested — the whole value of the
 * unconfirmed-rate banner is that it is *right*, and a banner nobody can test is decoration.
 *
 * Context: `RPD-016` records that the seeded Indonesia PPN rate has never been confirmed by a tax
 * adviser. `app.finance_tax_rule_versions` already carries everything needed to tell a
 * provisional rate from a confirmed one; these predicates are that distinction, written down.
 */

/**
 * True when this rate version is the one a calculation would use today: approved, and today falls
 * inside its effective window.
 *
 * Comparison is on `YYYY-MM-DD` string prefixes rather than parsed `Date` objects. The columns are
 * SQL `date`, not timestamps, so a timezone-aware parse would shift a boundary date by a day for
 * anyone east or west of UTC — and a tax rate that changes on the wrong day is exactly the class
 * of error this console exists to prevent. Lexicographic comparison on ISO dates is both correct
 * and timezone-free.
 */
export function isTaxRuleInForce(rule: FinanceTaxRuleVersion, today: Date = new Date()): boolean {
  if (rule.status !== "approved") return false;
  const day = today.toISOString().slice(0, 10);
  if (rule.effectiveFrom.slice(0, 10) > day) return false;
  if (rule.effectiveTo && rule.effectiveTo.slice(0, 10) < day) return false;
  return true;
}

/**
 * True when nothing in the record establishes this rate as a real statutory figure. Any one of
 * three conditions is enough, because each on its own means an invoice computed from the rate
 * rests on an assumption:
 *
 *   - it is still a seeded example fixture;
 *   - nobody approved it;
 *   - no evidence was recorded — no note, no attached document.
 *
 * The third is the one most easily waved away, and it is the one that matters most later: an
 * approved rate with no evidence cannot be defended when someone asks *why* that figure.
 */
export function isTaxRuleUnconfirmed(rule: FinanceTaxRuleVersion): boolean {
  if (rule.isExampleFixture) return true;
  if (!rule.approvedBy) return true;
  if (!rule.evidenceNote && !rule.evidenceReferenceFileId) return true;
  return false;
}
