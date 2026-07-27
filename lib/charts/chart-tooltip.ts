/**
 * Shared tooltip content builder (CargoGrid Chart System). ECharts renders a string
 * tooltip formatter's return value as HTML (a floating DOM node, not canvas text) --
 * every dynamic value is escaped here before interpolation, so a future chart bound to
 * anything less trusted than today's internal numeric/label data (a customer name, a
 * free-form note) can never inject markup through this path.
 */

function escapeHtml(value: string): string {
  return value.replace(/[&<>"']/g, (char) => {
    switch (char) {
      case "&":
        return "&amp;";
      case "<":
        return "&lt;";
      case ">":
        return "&gt;";
      case '"':
        return "&quot;";
      default:
        return "&#39;";
    }
  });
}

export interface TooltipRow {
  readonly label: string;
  readonly value: string;
  /** e.g. "vs May 2026    +8,4%" -- rendered de-emphasized, on its own line. */
  readonly comparison?: string;
}

export interface TooltipContent {
  readonly heading: string;
  readonly rows: readonly TooltipRow[];
}

/** Builds the shared tooltip HTML fragment every preset's ECharts `tooltip.formatter` returns -- one format across the whole chart system, never a per-preset ad hoc string template. */
export function buildTooltipHtml(content: TooltipContent): string {
  const rows = content.rows
    .map(
      (row) => `
        <div style="display:flex;justify-content:space-between;gap:16px;">
          <span>${escapeHtml(row.label)}</span>
          <strong>${escapeHtml(row.value)}</strong>
        </div>
        ${row.comparison ? `<div style="opacity:0.7;font-size:11px;">${escapeHtml(row.comparison)}</div>` : ""}
      `,
    )
    .join("");

  return `
    <div style="font-size:12px;min-width:160px;">
      <div style="font-weight:600;margin-bottom:4px;">${escapeHtml(content.heading)}</div>
      ${rows}
    </div>
  `;
}
