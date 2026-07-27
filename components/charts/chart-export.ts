/**
 * Chart export utilities (CargoGrid Chart System). PNG/SVG export use ECharts' own
 * `getDataURL()` (real, built-in, no extra dependency); CSV export reuses this
 * repository's existing `rowsToSafeCsv` (`server/policies/csv-export-sanitize.ts`, the
 * same OWASP formula-injection guard Commercial Reports already uses) rather than a
 * second, duplicate CSV-safety implementation -- that module is pure and
 * zero-dependency, safe to bundle client-side despite living under `server/`.
 *
 * Deliberately not built this checkpoint: a dedicated print stylesheet/flow (a bare
 * `window.print()` of the whole page is not a real print experience) -- disclosed, not
 * silently stubbed.
 */

import type { ECharts } from "echarts/core";
import { rowsToSafeCsv } from "../../server/policies/csv-export-sanitize.ts";

export interface ChartExportMetadata {
  readonly title: string;
  readonly period?: string;
  readonly generatedAt?: Date;
}

function triggerDownload(href: string, filename: string): void {
  const link = document.createElement("a");
  link.href = href;
  link.download = filename;
  link.click();
}

function safeFilenamePart(value: string): string {
  return value.replace(/[^a-zA-Z0-9_-]+/g, "-").replace(/(^-|-$)/g, "");
}

/** Exports the chart's current render as a PNG, embedding no confidential metadata in the filename beyond the chart's own title. */
export function exportChartAsPng(instance: ECharts, metadata: ChartExportMetadata): void {
  const dataUrl = instance.getDataURL({ type: "png", pixelRatio: 2, backgroundColor: "#fff" });
  triggerDownload(dataUrl, `${safeFilenamePart(metadata.title)}.png`);
}

/** Exports the chart's own already-fetched structured data (never values parsed back from the rendered canvas) as a sanitized CSV. */
export function exportChartDataAsCsv(
  metadata: ChartExportMetadata,
  header: readonly string[],
  rows: readonly (readonly (string | number | boolean | null | undefined)[])[],
): void {
  const csv = rowsToSafeCsv(header, rows);
  const blob = new Blob([csv], { type: "text/csv;charset=utf-8" });
  const url = URL.createObjectURL(blob);
  triggerDownload(url, `${safeFilenamePart(metadata.title)}.csv`);
  URL.revokeObjectURL(url);
}
