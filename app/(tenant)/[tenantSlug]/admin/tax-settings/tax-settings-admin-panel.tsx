import type { FinanceTaxCode, FinanceTaxRuleVersion, FinanceTaxRuleStatus } from "../../../../../server/contracts/tax-baseline/tax-baseline.ts";
import { isTaxRuleInForce, isTaxRuleUnconfirmed } from "../../../../../lib/finance/tax-rule-status.ts";

/**
 * Presentational half of the tax settings console.
 *
 * The point of this console is `RPD-016`: the seeded Indonesian PPN rate has never been confirmed
 * by a tax SME, and until this page existed there was nowhere to *see* that. The schema already
 * distinguishes a provisional rate from a confirmed one — `isExampleFixture`, `status`,
 * `approvedBy`/`approvedAt`, `evidenceNote` — so the job here is to stop that distinction being
 * invisible.
 *
 * Read-only. Creating and approving a rate version go through their own audited RPCs with their
 * own `FIN:*` authority checks; a second write path from a dashboard would widen the surface
 * without adding evidence. What this page owes the reader is an honest answer to "is the rate we
 * are charging customers actually confirmed?"
 */

const STATUS_STYLE: Record<FinanceTaxRuleStatus, string> = {
  approved: "bg-status-success-subtle text-status-success-strong",
  draft: "bg-status-warning-subtle text-status-warning-strong",
  archived: "bg-surface-muted text-text-secondary",
};

function formatRate(rule: FinanceTaxRuleVersion): string {
  if (rule.rateBasis === "percentage") {
    // Trailing zeros trimmed: 11.000000 reads as 11%.
    return `${Number(rule.rateValue).toString()}%`;
  }
  return `${Number(rule.rateValue).toString()}${rule.currency ? ` ${rule.currency}` : ""}`;
}

function formatDate(value: string | null): string {
  return value ? value.slice(0, 10) : "—";
}

// `isTaxRuleInForce` and `isTaxRuleUnconfirmed` live in lib/finance/tax-rule-status.ts so they
// carry unit tests — a banner that silently under-reports would give false assurance that every
// invoice's rate is confirmed, which is worse than showing no banner at all.
const isInForce = isTaxRuleInForce;
const isUnconfirmed = isTaxRuleUnconfirmed;

export function UnconfirmedRateBanner({ rules }: { rules: FinanceTaxRuleVersion[] }) {
  const risky = rules.filter((r) => isInForce(r) && isUnconfirmed(r));
  if (risky.length === 0) return null;

  return (
    <div className="rounded-lg border border-status-danger-subtle bg-status-danger-subtle p-4">
      <h2 className="text-sm font-semibold text-status-danger-strong">
        {risky.length === 1 ? "One tax rate currently in force is not confirmed" : `${risky.length} tax rates currently in force are not confirmed`}
      </h2>
      <p className="mt-1 text-sm text-status-danger-strong">
        These rates are being applied to real calculations, but nothing in the record establishes them as confirmed
        statutory figures — they are seeded examples, unapproved, or carry no evidence. <strong>If a rate is wrong, every
        invoice computed from it is wrong</strong>, and that is a legal and tax exposure rather than a software defect.
        A tax adviser should confirm each one; recording the confirmation here clears this banner without a code release.
      </p>
      <ul className="mt-2 list-disc pl-5 text-sm text-status-danger-strong">
        {risky.map((rule) => (
          <li key={rule.id}>
            {formatRate(rule)} from {formatDate(rule.effectiveFrom)} —{" "}
            {rule.isExampleFixture ? "seeded example fixture" : !rule.approvedBy ? "never approved" : "no evidence recorded"}
          </li>
        ))}
      </ul>
    </div>
  );
}

export function TaxCodeTable({ codes, rulesByCode }: { codes: FinanceTaxCode[]; rulesByCode: Map<string, FinanceTaxRuleVersion[]> }) {
  if (codes.length === 0) {
    return (
      <p className="rounded-lg border border-border-subtle bg-surface-raised p-4 text-sm text-text-secondary">
        No tax codes are visible to this tenant.
      </p>
    );
  }

  return (
    <div className="overflow-x-auto">
      <table className="w-full min-w-[56rem] border-collapse text-sm">
        <caption className="sr-only">Tax codes and the rate currently in force for each</caption>
        <thead>
          <tr className="border-b border-border-subtle text-left text-xs uppercase tracking-wide text-text-secondary">
            <th scope="col" className="py-2 pr-4 font-medium">Code</th>
            <th scope="col" className="py-2 pr-4 font-medium">Name</th>
            <th scope="col" className="py-2 pr-4 font-medium">Type</th>
            <th scope="col" className="py-2 pr-4 font-medium">Jurisdiction</th>
            <th scope="col" className="py-2 pr-4 font-medium">Rate in force today</th>
            <th scope="col" className="py-2 pr-4 font-medium">Confirmed?</th>
          </tr>
        </thead>
        <tbody>
          {codes.map((code) => {
            const rules = rulesByCode.get(code.id) ?? [];
            const inForce = rules.find((r) => isInForce(r));
            return (
              <tr key={code.id} className="border-b border-border-subtle last:border-0">
                <td className="py-2 pr-4 font-medium text-text-primary">{code.code}</td>
                <td className="py-2 pr-4 text-text-secondary">{code.name}</td>
                <td className="py-2 pr-4 text-text-secondary">{code.taxType}</td>
                <td className="py-2 pr-4 text-text-secondary">{code.jurisdictionCountry}</td>
                <td className="py-2 pr-4 tabular-nums text-text-primary">
                  {inForce ? formatRate(inForce) : <span className="text-status-warning-strong">none in force</span>}
                </td>
                <td className="py-2 pr-4">
                  {!inForce ? (
                    <span className="text-text-secondary">—</span>
                  ) : isUnconfirmed(inForce) ? (
                    <span className="inline-flex rounded bg-status-danger-subtle px-2 py-0.5 text-xs font-medium text-status-danger-strong">
                      not confirmed
                    </span>
                  ) : (
                    <span className="inline-flex rounded bg-status-success-subtle px-2 py-0.5 text-xs font-medium text-status-success-strong">
                      confirmed
                    </span>
                  )}
                </td>
              </tr>
            );
          })}
        </tbody>
      </table>
    </div>
  );
}

export function RuleVersionTable({ code, rules }: { code: FinanceTaxCode; rules: FinanceTaxRuleVersion[] }) {
  if (rules.length === 0) {
    return (
      <p className="rounded-lg border border-status-warning-subtle bg-status-warning-subtle p-3 text-sm text-status-warning-strong">
        <strong>{code.code}</strong> has no rate versions at all. Any calculation against this code fails rather than
        guessing a rate — which is the correct behaviour, but it means the code is unusable until a rate is recorded.
      </p>
    );
  }

  return (
    <div className="overflow-x-auto">
      <table className="w-full min-w-[64rem] border-collapse text-sm">
        <caption className="sr-only">Rate versions for {code.code}, newest effective date first</caption>
        <thead>
          <tr className="border-b border-border-subtle text-left text-xs uppercase tracking-wide text-text-secondary">
            <th scope="col" className="py-2 pr-4 font-medium">Rate</th>
            <th scope="col" className="py-2 pr-4 font-medium">Effective from</th>
            <th scope="col" className="py-2 pr-4 font-medium">Until</th>
            <th scope="col" className="py-2 pr-4 font-medium">Status</th>
            <th scope="col" className="py-2 pr-4 font-medium">Approved by</th>
            <th scope="col" className="py-2 pr-4 font-medium">Evidence</th>
            <th scope="col" className="py-2 pr-4 font-medium">In force today</th>
          </tr>
        </thead>
        <tbody>
          {rules.map((rule) => (
            <tr key={rule.id} className="border-b border-border-subtle last:border-0">
              <td className="py-2 pr-4 tabular-nums font-medium text-text-primary">{formatRate(rule)}</td>
              <td className="py-2 pr-4 tabular-nums text-text-secondary">{formatDate(rule.effectiveFrom)}</td>
              <td className="py-2 pr-4 tabular-nums text-text-secondary">{formatDate(rule.effectiveTo)}</td>
              <td className="py-2 pr-4">
                <span className={`inline-flex rounded px-2 py-0.5 text-xs font-medium ${STATUS_STYLE[rule.status]}`}>
                  {rule.status}
                </span>
                {rule.isExampleFixture ? (
                  <span className="ml-1 inline-flex rounded bg-status-danger-subtle px-2 py-0.5 text-xs font-medium text-status-danger-strong">
                    example fixture
                  </span>
                ) : null}
              </td>
              <td className="py-2 pr-4 text-text-secondary">
                {rule.approvedBy ? `${rule.approvedBy}${rule.approvedAt ? ` (${formatDate(rule.approvedAt)})` : ""}` : (
                  <span className="text-status-warning-strong">not approved</span>
                )}
              </td>
              <td className="py-2 pr-4 text-text-secondary">
                {rule.evidenceNote ?? (rule.evidenceReferenceFileId ? "attached file" : <span className="text-status-warning-strong">none</span>)}
              </td>
              <td className="py-2 pr-4 text-text-secondary">{isInForce(rule) ? "yes" : "no"}</td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}
