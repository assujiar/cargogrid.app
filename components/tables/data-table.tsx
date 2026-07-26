/**
 * DataTable primitive (CargoGrid UI Modernization checkpoint,
 * `docs/design-system/02_COMPONENTS.md`, flips "Table"/"Data grid" from
 * `DOCUMENTED_ONLY`) -- the first shared table implementation, built against its first
 * two real consumers (`commercial/leads/page.tsx`, `supreme/tenants/page.tsx`) per
 * `09_*.md` §4.2's "one owner, many consumers" rule, replacing each screen's own raw
 * `<table>`.
 *
 * Scope this checkpoint actually builds (named precisely, not overclaimed): column
 * rendering, sticky header (page-scroll, not a fixed-height virtualized viewport),
 * density tiers via the platform's existing `--row-height-*` tokens, and an in-table
 * Empty state. Loading and Error remain page-owned, matching every existing screen's
 * convention (a route-level `loading.tsx` Suspense boundary for Loading; an inline
 * `role="alert"` render before this component for Error) -- consolidating those into
 * the primitive itself is future work, not done here. Sorting, filtering, column
 * visibility/pinning, saved views, bulk actions, row selection, and export remain
 * `DOCUMENTED_ONLY`: no current screen has server-side support for any of them yet, and
 * building the UI ahead of a real consumer would be exactly the speculative-abstraction
 * pattern `AGENTS.md` forbids.
 */

import type { ReactNode } from "react";

export type DataTableDensity = "compact" | "default" | "comfortable";

const DENSITY_ROW_HEIGHT: Record<DataTableDensity, string> = {
  compact: "var(--row-height-compact)",
  default: "var(--row-height-default)",
  comfortable: "var(--row-height-comfortable)",
};

export interface DataTableColumn<Row> {
  readonly key: string;
  readonly header: string;
  readonly align?: "left" | "right";
  readonly render: (row: Row) => ReactNode;
}

export interface DataTableProps<Row> {
  /** Accessible table name (`<caption>`, visually hidden) -- required, not optional: an unlabeled data table has no accessible name for a screen-reader user (`docs/standards/DESIGN_SYSTEM.md` §5, WCAG 2.2 AA). */
  readonly caption: string;
  readonly columns: readonly DataTableColumn<Row>[];
  readonly rows: readonly Row[];
  readonly rowKey: (row: Row) => string;
  readonly density?: DataTableDensity;
  /** Rendered in place of the table when `rows` is empty. Required, not defaulted -- every list screen's empty copy is domain-specific ("No leads found..." vs. "No tenants have been provisioned...") and must stay that specific per `09_*.md` §5's Empty-state contract, never a generic fallback string. */
  readonly emptyMessage: ReactNode;
}

export function DataTable<Row>({ caption, columns, rows, rowKey, density = "default", emptyMessage }: DataTableProps<Row>) {
  if (rows.length === 0) {
    return (
      <div className="rounded-md border border-neutral-200 bg-surface p-6 text-sm text-neutral-600">{emptyMessage}</div>
    );
  }

  const rowHeight = DENSITY_ROW_HEIGHT[density];

  return (
    <div className="overflow-x-auto rounded-md border border-neutral-200">
      <table className="w-full min-w-full border-collapse text-sm">
        <caption className="sr-only">{caption}</caption>
        <thead>
          <tr style={{ height: rowHeight }}>
            {columns.map((column) => (
              <th
                key={column.key}
                scope="col"
                className={`sticky top-0 z-10 border-b border-neutral-200 bg-surface px-4 font-medium text-neutral-600 ${
                  column.align === "right" ? "text-right" : "text-left"
                }`}
              >
                {column.header}
              </th>
            ))}
          </tr>
        </thead>
        <tbody>
          {rows.map((row) => (
            <tr key={rowKey(row)} className="border-b border-neutral-100 last:border-0" style={{ height: rowHeight }}>
              {columns.map((column) => (
                <td
                  key={column.key}
                  className={`px-4 align-middle text-neutral-700 ${column.align === "right" ? "text-right" : "text-left"}`}
                >
                  {column.render(row)}
                </td>
              ))}
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}
