import type { QuotationVersionDiff } from "../../../../../../server/contracts/quotation/quotation-diff.ts";

const FIELD_LABELS: Record<string, string> = {
  currency: "Currency",
  validityFrom: "Valid from",
  validityTo: "Valid to",
  status: "Status",
  contactId: "Contact",
  subtotalAmount: "Subtotal",
  discountAmount: "Discount",
  taxAmount: "Tax",
  totalAmount: "Total",
  terms: "Terms",
};

function formatValue(value: unknown): string {
  if (value === null || value === undefined) return "—";
  if (typeof value === "object") return JSON.stringify(value);
  return String(value);
}

/** Renders a computed app.quotation-version diff (COM-152) -- every value here already passed through the field-masked directory reads that produced it, so a masked field simply renders "—" on both sides rather than ever needing its own permission check. */
export function ComparisonPanel({ diff, otherVersionNumber }: { diff: QuotationVersionDiff; otherVersionNumber: number }) {
  return (
    <div className="rounded-md border border-neutral-200 p-4">
      <h2 className="text-sm font-semibold text-neutral-900">Comparison with v{otherVersionNumber}</h2>

      {diff.headerChanges.length === 0 && diff.lineChanges.length === 0 ? (
        <p className="mt-2 text-sm text-neutral-600">No material differences.</p>
      ) : (
        <>
          {diff.headerChanges.length > 0 ? (
            <table className="mt-2 w-full border-collapse text-sm">
              <thead>
                <tr className="border-b border-neutral-200 text-left text-neutral-600">
                  <th scope="col" className="py-2 pr-4 font-medium">
                    Field
                  </th>
                  <th scope="col" className="py-2 pr-4 font-medium">
                    v{otherVersionNumber}
                  </th>
                  <th scope="col" className="py-2 font-medium">
                    This version
                  </th>
                </tr>
              </thead>
              <tbody>
                {diff.headerChanges.map((change) => (
                  <tr key={change.field} className="border-b border-neutral-100">
                    <td className="py-2 pr-4 text-neutral-900">{FIELD_LABELS[change.field] ?? change.field}</td>
                    <td className="py-2 pr-4 text-neutral-600">{formatValue(change.before)}</td>
                    <td className="py-2 text-neutral-600">{formatValue(change.after)}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          ) : null}

          {diff.lineChanges.length > 0 ? (
            <ul className="mt-3 flex flex-col gap-1 text-sm">
              {diff.lineChanges.map((change) => (
                <li key={change.key} className="text-neutral-600">
                  <span className="font-medium text-neutral-900">{change.kind}</span>
                  {": "}
                  {change.kind === "added" ? change.after?.description : change.kind === "removed" ? change.before?.description : `${change.before?.description} (${formatValue(change.before?.lineTotal)} → ${formatValue(change.after?.lineTotal)})`}
                </li>
              ))}
            </ul>
          ) : null}
        </>
      )}
    </div>
  );
}
