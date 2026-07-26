import { ViewportFrame } from "../viewport-frame.tsx";
import { DataTable, type DataTableColumn } from "../../../../../components/tables/data-table.tsx";

interface MockRow {
  readonly id: string;
  readonly name: string;
  readonly source: string;
  readonly status: string;
  readonly score: number;
}

const MOCK_ROWS: readonly MockRow[] = [
  { id: "1", name: "Amara Chen", source: "Referral", status: "New", score: 82 },
  { id: "2", name: "Marcus Obi", source: "Website", status: "Qualified", score: 64 },
];

const COLUMNS: readonly DataTableColumn<MockRow>[] = [
  { key: "name", header: "Contact", render: (row) => row.name },
  { key: "source", header: "Source", render: (row) => row.source },
  { key: "status", header: "Status", render: (row) => row.status },
  { key: "score", header: "Score", align: "right", render: (row) => row.score },
];

export default function ResponsivePreviewPage() {
  return (
    <div className="flex flex-col gap-4">
      <div>
        <h1 className="text-xl font-semibold">Responsive preview</h1>
        <p className="mt-1 text-sm text-[var(--ds-text-secondary)]">
          Use the desktop/tablet/mobile control in the sidebar — it is available on every page in this showcase (see{" "}
          <code>viewport-frame.tsx</code>), and this page demonstrates it against a real <code>DataTable</code>. No
          dedicated CargoGrid breakpoint scale exists beyond Tailwind&apos;s own framework defaults (see{" "}
          <code>Foundations → Breakpoints</code>) — internal ERP routes are desktop-first by design (
          <code>docs/standards/DESIGN_SYSTEM.md</code>), so the only real responsive behavior this repository has built
          today is horizontal scroll on a table that outgrows a narrow viewport, shown below.
        </p>
      </div>
      <ViewportFrame>
        <DataTable caption="Mock leads" columns={COLUMNS} rows={MOCK_ROWS} rowKey={(row) => row.id} emptyMessage="No rows." />
      </ViewportFrame>
    </div>
  );
}
