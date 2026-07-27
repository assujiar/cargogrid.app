/**
 * Centralized chart number/currency formatters (CargoGrid Chart System) -- every chart
 * formats through these, never an independent `toLocaleString()`/manual string build
 * inside a preset (the mission's own "do not format financial values independently
 * inside each chart" rule). Indonesian (`id-ID`) locale by default, matching the
 * examples this checkpoint's own instruction gave ("Rp4,8 miliar", "1.250 shipment").
 */

const COMPACT_SUFFIXES: readonly { readonly threshold: number; readonly suffix: string }[] = [
  { threshold: 1_000_000_000_000, suffix: " triliun" },
  { threshold: 1_000_000_000, suffix: " miliar" },
  { threshold: 1_000_000, suffix: " juta" },
  { threshold: 1_000, suffix: " ribu" },
];

/** `formatCompactNumber(4_820_000_000)` -> `"4,8 miliar"`. Below 1.000, renders the plain `id-ID`-grouped integer. */
export function formatCompactNumber(value: number, options: { readonly maximumFractionDigits?: number } = {}): string {
  const { maximumFractionDigits = 1 } = options;
  const magnitude = Math.abs(value);
  const bucket = COMPACT_SUFFIXES.find((entry) => magnitude >= entry.threshold);
  if (!bucket) {
    return new Intl.NumberFormat("id-ID").format(value);
  }
  const scaled = value / bucket.threshold;
  return `${new Intl.NumberFormat("id-ID", { maximumFractionDigits }).format(scaled)}${bucket.suffix}`;
}

/** `formatCurrency(4_820_000_000, "IDR")` -> `"Rp4,8 miliar"`. `formatCurrency(48_200, "USD")` -> `"USD 48.200"` (non-IDR currencies are not auto-converted, and are not given an invented compact-suffix convention). */
export function formatCurrency(value: number, currencyCode: string, options: { readonly compact?: boolean } = {}): string {
  const { compact = true } = options;
  if (currencyCode === "IDR") {
    return compact ? `Rp${formatCompactNumber(value)}` : `Rp${new Intl.NumberFormat("id-ID").format(value)}`;
  }
  return `${currencyCode} ${new Intl.NumberFormat("id-ID").format(value)}`;
}

/** `formatCount(1250, "shipment")` -> `"1.250 shipment"`. */
export function formatCount(value: number, unit: string): string {
  return `${new Intl.NumberFormat("id-ID").format(value)} ${unit}`;
}

/** `formatPercent(18.5)` -> `"18,5%"`. */
export function formatPercent(value: number, options: { readonly maximumFractionDigits?: number; readonly signed?: boolean } = {}): string {
  const { maximumFractionDigits = 1, signed = false } = options;
  const formatted = new Intl.NumberFormat("id-ID", { maximumFractionDigits, signDisplay: signed ? "always" : "auto" }).format(value);
  return `${formatted}%`;
}

/** `formatDuration(7, "hari")` -> `"7 hari"`; `formatDuration(24, "jam")` -> `"24 jam"`. Thin, but centralizes the pattern so no preset hand-builds it differently. */
export function formatDuration(value: number, unit: "hari" | "jam"): string {
  return `${new Intl.NumberFormat("id-ID").format(value)} ${unit}`;
}
