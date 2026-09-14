/**
 * Pure logic split out of `surat-jalan-document.tsx` (a `.tsx` file containing JSX,
 * which this repository's plain `node --experimental-strip-types --test` runner
 * cannot load -- it strips TypeScript types but does not transform JSX syntax, so any
 * `.test.ts` file importing a `.tsx` module fails with `ERR_UNKNOWN_FILE_EXTENSION`
 * before a single assertion runs). Kept in its own `.ts` file so this genuinely
 * test-worthy label/value transform (used to render both
 * `app.shipment_orders.consignee_snapshot`/`.cargo_service_snapshot` and
 * `app.accounts.billing_address`, all deliberately unstructured JSONB with no fixed
 * schema anywhere in this codebase) has real unit coverage.
 */

export interface SuratJalanLabeledValue {
  readonly label: string;
  readonly value: string;
}

/** Converts an arbitrary JSON object's own keys into a label/value list -- snake_case and camelCase keys both become Title Case labels, nested objects/arrays fall back to a compact JSON string rather than being silently dropped. */
export function toLabeledValues(source: Record<string, unknown> | null | undefined): SuratJalanLabeledValue[] {
  if (!source) return [];
  return Object.entries(source)
    .filter(([, value]) => value !== null && value !== undefined && value !== "")
    .map(([key, value]) => ({
      label: key
        .replace(/([a-z0-9])([A-Z])/g, "$1 $2")
        .replace(/_/g, " ")
        .replace(/\s+/g, " ")
        .trim()
        .replace(/^./, (char) => char.toUpperCase()),
      value: typeof value === "object" ? JSON.stringify(value) : String(value),
    }));
}
