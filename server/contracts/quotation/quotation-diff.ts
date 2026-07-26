/**
 * Quotation version comparison (COM-152, CG-S7-COM-011). Pure, unit-tested TypeScript --
 * not a SQL function. Two already field-masked `app.quotations_directory`/
 * `app.quotation_lines_directory` reads (one per version) already carry every access
 * decision that matters (Prompt 152 §26 "approval roles view sensitive diff by
 * permission" is satisfied transitively: a masked field diffs as `null` vs `null`, never
 * exposing what the caller could not already see) -- the diff itself has no
 * authorization/data-integrity requirement beyond what those reads already enforce, so it
 * is computed here rather than in a third SQL function with no real database-side rule to
 * enforce (`supabase/migrations/20260724240000_create_commercial_quotation_versioning.sql`'s
 * own header, "Compare" boundary).
 */

import type { Quotation, QuotationLine } from "./quotation.ts";

export interface QuotationHeaderFieldChange {
  readonly field: string;
  readonly before: unknown;
  readonly after: unknown;
}

export type QuotationLineChangeKind = "added" | "removed" | "changed";

export interface QuotationLineChange {
  readonly key: string;
  readonly kind: QuotationLineChangeKind;
  readonly before: QuotationLine | null;
  readonly after: QuotationLine | null;
}

export interface QuotationVersionDiff {
  readonly headerChanges: readonly QuotationHeaderFieldChange[];
  readonly lineChanges: readonly QuotationLineChange[];
}

/** The material, customer-facing-or-restricted header fields Prompt 152 §25 requires a compare to reconcile. Fields that are always identical across versions of the same root (id, quoteNumber, rootQuotationId, opportunityId) are deliberately excluded -- comparing them would never produce a real change. */
const MATERIAL_HEADER_FIELDS = [
  "currency",
  "validityFrom",
  "validityTo",
  "status",
  "contactId",
  "subtotalAmount",
  "discountAmount",
  "taxAmount",
  "totalAmount",
] as const satisfies readonly (keyof Quotation)[];

function deepEqual(a: unknown, b: unknown): boolean {
  return JSON.stringify(a) === JSON.stringify(b);
}

/** A quotation line has no stable id across versions (each version's lines are copied as brand-new rows) -- correlated by its sourcing margin calculation when present, else by (lineType, description), the same best-effort matching this module discloses rather than claims a perfect semantic match. */
function lineCorrelationKey(line: QuotationLine): string {
  return line.marginCalculationId ? `calc:${line.marginCalculationId}` : `manual:${line.lineType}:${line.description}`;
}

export function diffQuotationVersions(
  before: { readonly quotation: Quotation; readonly lines: readonly QuotationLine[] },
  after: { readonly quotation: Quotation; readonly lines: readonly QuotationLine[] },
): QuotationVersionDiff {
  const headerChanges: QuotationHeaderFieldChange[] = [];
  for (const field of MATERIAL_HEADER_FIELDS) {
    const beforeValue = before.quotation[field];
    const afterValue = after.quotation[field];
    if (!deepEqual(beforeValue, afterValue)) {
      headerChanges.push({ field, before: beforeValue, after: afterValue });
    }
  }
  if (!deepEqual(before.quotation.terms, after.quotation.terms)) {
    headerChanges.push({ field: "terms", before: before.quotation.terms, after: after.quotation.terms });
  }

  const beforeByKey = new Map(before.lines.map((line) => [lineCorrelationKey(line), line]));
  const afterByKey = new Map(after.lines.map((line) => [lineCorrelationKey(line), line]));
  const allKeys = new Set([...beforeByKey.keys(), ...afterByKey.keys()]);

  const lineChanges: QuotationLineChange[] = [];
  for (const key of allKeys) {
    const beforeLine = beforeByKey.get(key) ?? null;
    const afterLine = afterByKey.get(key) ?? null;

    if (beforeLine && !afterLine) {
      lineChanges.push({ key, kind: "removed", before: beforeLine, after: null });
      continue;
    }
    if (!beforeLine && afterLine) {
      lineChanges.push({ key, kind: "added", before: null, after: afterLine });
      continue;
    }
    if (beforeLine && afterLine) {
      const materialFieldsEqual =
        beforeLine.quantity === afterLine.quantity &&
        beforeLine.unitPrice === afterLine.unitPrice &&
        beforeLine.discountPct === afterLine.discountPct &&
        beforeLine.taxPct === afterLine.taxPct &&
        beforeLine.lineTotal === afterLine.lineTotal;
      if (!materialFieldsEqual) {
        lineChanges.push({ key, kind: "changed", before: beforeLine, after: afterLine });
      }
    }
  }

  return { headerChanges, lineChanges };
}
