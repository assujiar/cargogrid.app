"use client";

import { Suspense } from "react";
import Link from "next/link";
import { useSearchParams } from "next/navigation";
import { DataTable, type DataTableColumn } from "../../../../../components/tables/data-table.tsx";
import { Pagination } from "../../../../../components/tables/pagination.tsx";
import { StatusBadge, type StatusTone } from "../../../../../components/ui/status-badge.tsx";
import { Button } from "../../../../../components/ui/button.tsx";
import { ViewportFrame } from "../viewport-frame.tsx";

interface LargeRow {
  readonly id: string;
  readonly name: string;
  readonly status: string;
  readonly statusTone: StatusTone;
  readonly notes: string;
}

const STATUSES: readonly [string, StatusTone][] = [
  ["Draft", "neutral"],
  ["Pending approval", "warning"],
  ["Approved", "success"],
  ["Rejected", "danger"],
  ["In review", "info"],
];

function buildMockRows(count: number): LargeRow[] {
  return Array.from({ length: count }, (_, index) => {
    const [status, tone] = STATUSES[index % STATUSES.length]!;
    return {
      id: String(index + 1),
      name: `Quotation QUO-2026-${String(10000 + index)}`,
      status,
      statusTone: tone,
      notes:
        index % 4 === 0
          ? "Customer requested an expedited response and flagged this as a strategic account renewal ahead of Q3 contract negotiations."
          : "—",
    };
  });
}

const LARGE_DATASET = buildMockRows(200);
const PAGE_SIZE = 10;

export default function TablesPage() {
  return (
    <Suspense fallback={<p className="text-sm text-[var(--ds-text-secondary)]">Loading…</p>}>
      <TablesPageContent />
    </Suspense>
  );
}

function TablesPageContent() {
  const searchParams = useSearchParams();
  const demoPage = Math.max(Number.parseInt(searchParams.get("demoPage") ?? "1", 10) || 1, 1);
  const rows = LARGE_DATASET.slice((demoPage - 1) * PAGE_SIZE, demoPage * PAGE_SIZE);

  const columns: readonly DataTableColumn<LargeRow>[] = [
    { key: "name", header: "Quotation", render: (row) => row.name },
    { key: "status", header: "Status", render: (row) => <StatusBadge tone={row.statusTone} label={row.status} /> },
    { key: "notes", header: "Notes", render: (row) => row.notes },
    {
      key: "actions",
      header: "Actions",
      align: "right",
      render: (row) => (
        <Button variant="secondary" onClick={() => alert(`Demo only — would open ${row.name}`)}>
          View
        </Button>
      ),
    },
  ];

  return (
    <div className="flex flex-col gap-6">
      <div>
        <h1 className="text-xl font-semibold">Tables</h1>
        <p className="mt-1 text-sm text-[var(--ds-text-secondary)]">
          <code>components/tables/data-table.tsx</code> + <code>components/tables/pagination.tsx</code> — the only shared
          table implementation in this repository, exercised here against 200 mock rows.
        </p>
      </div>

      <section className="flex flex-col gap-2">
        <h2 className="text-base font-semibold">Large data set, real pagination (200 mock rows)</h2>
        <p className="text-sm text-[var(--ds-text-secondary)]">
          This is a genuinely interactive demo — the Pagination control below updates this page&apos;s own URL
          (<code>?demoPage=</code>) and the table re-renders the correct slice, the same mechanism{" "}
          <code>commercial/leads/page.tsx</code> uses in the real app. Status cells and a row action are composed from{" "}
          <code>StatusBadge</code> and <code>Button</code> inside a column&apos;s <code>render</code> — DataTable has no
          dedicated &quot;status column&quot; or &quot;row actions&quot; type, this is the correct pattern today.
        </p>
        <ViewportFrame>
          <div className="flex flex-col gap-3">
            <DataTable caption="Mock quotations" columns={columns} rows={rows} rowKey={(row) => row.id} emptyMessage="No rows." />
            <Pagination
              page={demoPage}
              pageSize={PAGE_SIZE}
              totalCount={LARGE_DATASET.length}
              buildHref={(targetPage) => `/internal/design-system/tables?demoPage=${targetPage}`}
            />
          </div>
        </ViewportFrame>
        <p className="text-xs text-[var(--ds-text-secondary)]">
          The &ldquo;Notes&rdquo; column shows deliberately long text on every 4th row — DataTable does not truncate or
          line-clamp long cell content; it wraps naturally within the cell, which can grow a row&apos;s visual height
          past its density token on those rows (a real, disclosed limitation, not hidden here).
        </p>
      </section>

      <section className="flex flex-col gap-2">
        <h2 className="text-base font-semibold">Not supported today</h2>
        <ul className="list-disc pl-5 text-sm text-[var(--ds-text-secondary)]">
          <li>Sorting — no column header is clickable; no sortable-column prop exists.</li>
          <li>
            Filtering — no filter bar exists (docs/design-system/02_COMPONENTS.md §2, &ldquo;Filter bar&rdquo;,
            DOCUMENTED_ONLY).
          </li>
          <li>Grouping, saved views, column visibility/pinning — all DOCUMENTED_ONLY, no real consumer needs them yet.</li>
          <li>Row selection / bulk actions — no bulk mutation exists anywhere in this repository to drive them.</li>
          <li>Sticky first column — only the header row is sticky; no column is pinned.</li>
          <li>Export — no export UI exists (server primitives exist for Commercial Reports, unrelated to this table).</li>
        </ul>
      </section>

      <section className="flex flex-col gap-2">
        <h2 className="text-base font-semibold">Loading and Error states</h2>
        <p className="text-sm text-[var(--ds-text-secondary)]">
          Deliberately not demonstrated as part of <code>DataTable</code> itself — both remain page-owned in every real
          consumer today. See the real Loading state at <code>commercial/leads/loading.tsx</code> (a route{" "}
          <code>loading.tsx</code> Suspense boundary) and the real Error state inline in{" "}
          <code>commercial/leads/page.tsx</code> (a <code>role=&quot;alert&quot;</code> block) — reproduced live at{" "}
          <Link href="/internal/design-system/patterns" className="text-primary underline">
            Patterns → Error page / Empty page
          </Link>
          .
        </p>
      </section>
    </div>
  );
}
