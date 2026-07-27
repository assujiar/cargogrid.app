/**
 * Live variant/state matrices for the 6 real, `IMPLEMENTED` primitives (CargoGrid UI
 * Modernization checkpoint 3). Every example below renders the actual imported
 * component — never a screenshot or hand-recreated look-alike markup. Hover/focus/
 * active states are not simulated: the real component already wires
 * `hover:`/`focus-visible:` classes (see `components/ui/button.tsx`), so a live page is
 * sufficient to demonstrate them by genuine interaction — the labels below say so
 * rather than faking a pseudo-class.
 */

import { Button, type ButtonVariant } from "../../../../../components/ui/button.tsx";
import { Banner } from "../../../../../components/ui/banner.tsx";
import { Badge, type BadgeTone } from "../../../../../components/ui/badge.tsx";
import { StatusBadge, type StatusTone } from "../../../../../components/ui/status-badge.tsx";
import { DataTable, type DataTableColumn, type DataTableDensity } from "../../../../../components/tables/data-table.tsx";
import { Pagination } from "../../../../../components/tables/pagination.tsx";

const BUTTON_VARIANTS: readonly ButtonVariant[] = ["primary", "secondary", "destructive"];
const BADGE_TONES: readonly BadgeTone[] = ["neutral", "primary"];
const STATUS_TONES: readonly StatusTone[] = ["success", "warning", "danger", "info", "neutral"];
const STATUS_LABELS: Record<StatusTone, string> = {
  success: "Approved",
  warning: "Pending",
  danger: "Rejected",
  info: "In review",
  neutral: "Draft",
};

export function ButtonShowcase() {
  return (
    <div className="flex flex-col gap-4">
      <div className="grid grid-cols-1 gap-3 sm:grid-cols-3">
        {BUTTON_VARIANTS.map((variant) => (
          <div key={variant} className="flex flex-col gap-2 rounded-md border border-[var(--ds-border)] p-3">
            <span className="text-xs font-medium capitalize text-[var(--ds-text-secondary)]">{variant}</span>
            <Button variant={variant}>Save changes</Button>
            <Button variant={variant} disabled>
              Disabled
            </Button>
            <Button variant={variant} loading loadingLabel="Saving…">
              Save changes
            </Button>
          </div>
        ))}
      </div>
      <p className="text-xs text-[var(--ds-text-secondary)]">
        Hover, focus (Tab to it), and click-and-hold any enabled button above to see its real{" "}
        <code>hover:</code>/<code>focus-visible:</code>/<code>active</code> treatment — not simulated. Only{" "}
        <code>primary</code>/<code>secondary</code>/<code>destructive</code> variants and one size exist; tertiary,
        ghost, link, icon-only, and leading/trailing-icon slots are not supported by this component.
      </p>
    </div>
  );
}

export function BannerShowcase() {
  return (
    <div className="flex flex-col gap-2">
      <Banner variant="info">Informational: this quotation was auto-saved 2 minutes ago.</Banner>
      <Banner variant="warning">Warning: this quotation is below the account&apos;s minimum margin threshold.</Banner>
      <Banner variant="success">Success: the credit check completed with outcome &quot;cleared&quot;.</Banner>
      <Banner variant="danger">Danger: this account is on credit hold — new quotations require an override.</Banner>
    </div>
  );
}

export function BadgeShowcase() {
  return (
    <div className="flex gap-3">
      {BADGE_TONES.map((tone) => (
        <Badge key={tone} tone={tone}>
          {tone === "primary" ? "New" : "Ocean freight"}
        </Badge>
      ))}
    </div>
  );
}

export function StatusBadgeShowcase() {
  return (
    <div className="flex flex-wrap gap-3">
      {STATUS_TONES.map((tone) => (
        <StatusBadge key={tone} tone={tone} label={STATUS_LABELS[tone]} />
      ))}
    </div>
  );
}

interface MockTableRow {
  readonly id: string;
  readonly name: string;
  readonly owner: string;
  readonly value: string;
}

const MOCK_TABLE_ROWS: readonly MockTableRow[] = [
  { id: "1", name: "Q3 ocean freight RFQ — Halcyon", owner: "M. Tan", value: "USD 22,000" },
  { id: "2", name: "Annual air freight contract — Redline", owner: "J. Alvarez", value: "USD 148,000" },
  { id: "3", name: "Warehousing renewal — Northgate", owner: "M. Tan", value: "USD 61,500" },
];

const MOCK_TABLE_COLUMNS: readonly DataTableColumn<MockTableRow>[] = [
  { key: "name", header: "Name", render: (row) => row.name },
  { key: "owner", header: "Owner", render: (row) => row.owner },
  { key: "value", header: "Value", align: "right", render: (row) => row.value },
];

const DENSITIES: readonly DataTableDensity[] = ["compact", "default", "comfortable"];

export function DataTableShowcase() {
  return (
    <div className="flex flex-col gap-4">
      {DENSITIES.map((density) => (
        <div key={density} className="flex flex-col gap-1">
          <span className="text-xs font-medium capitalize text-[var(--ds-text-secondary)]">{density}</span>
          <DataTable
            caption={`Mock pipeline (${density})`}
            columns={MOCK_TABLE_COLUMNS}
            rows={MOCK_TABLE_ROWS}
            rowKey={(row) => row.id}
            density={density}
            emptyMessage="No records."
          />
        </div>
      ))}
      <div className="flex flex-col gap-1">
        <span className="text-xs font-medium text-[var(--ds-text-secondary)]">Empty state</span>
        <DataTable
          caption="Mock pipeline (empty)"
          columns={MOCK_TABLE_COLUMNS}
          rows={[]}
          rowKey={(row) => row.id}
          emptyMessage="No opportunities match the current view."
        />
      </div>
      <p className="text-xs text-[var(--ds-text-secondary)]">
        Loading and Error states are deliberately not shown here — they remain page-owned (a route <code>loading.tsx</code>{" "}
        Suspense boundary; an inline <code>role=&quot;alert&quot;</code> block), not built into this component. Sorting,
        filtering, row selection, bulk actions, column pinning, and export are not supported.
      </p>
    </div>
  );
}

export function PaginationShowcase() {
  return (
    <div className="flex flex-col gap-3">
      <div className="flex flex-col gap-1">
        <span className="text-xs font-medium text-[var(--ds-text-secondary)]">Middle of a long list (page 10 of 20)</span>
        <Pagination page={10} pageSize={10} totalCount={200} buildHref={() => "#"} />
      </div>
      <div className="flex flex-col gap-1">
        <span className="text-xs font-medium text-[var(--ds-text-secondary)]">First page (Previous disabled)</span>
        <Pagination page={1} pageSize={10} totalCount={200} buildHref={() => "#"} />
      </div>
      <div className="flex flex-col gap-1">
        <span className="text-xs font-medium text-[var(--ds-text-secondary)]">Last page (Next disabled)</span>
        <Pagination page={20} pageSize={10} totalCount={200} buildHref={() => "#"} />
      </div>
      <div className="flex flex-col gap-1">
        <span className="text-xs font-medium text-[var(--ds-text-secondary)]">Single page (renders nothing)</span>
        <div className="rounded border border-dashed border-[var(--ds-border)] p-2 text-xs text-[var(--ds-text-secondary)]">
          <Pagination page={1} pageSize={20} totalCount={5} buildHref={() => "#"} />
          (nothing rendered above — by design, a single-page result has no pagination decision to present)
        </div>
      </div>
    </div>
  );
}
