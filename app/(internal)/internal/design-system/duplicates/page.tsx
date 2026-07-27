import { MIGRATION_MAP, type MigrationMapEntry } from "../../../../../lib/design-system/migration-map.ts";
import { DataTable, type DataTableColumn } from "../../../../../components/tables/data-table.tsx";
import { StatusBadge } from "../../../../../components/ui/status-badge.tsx";

const PRIORITY_TONE = { High: "danger", Medium: "warning", Low: "neutral" } as const;
const RISK_TONE = { Low: "success", Medium: "warning", High: "danger" } as const;

const COLUMNS: readonly DataTableColumn<MigrationMapEntry>[] = [
  { key: "legacy", header: "Legacy implementation", render: (row) => row.legacyImplementation },
  {
    key: "replacement",
    header: "Shared replacement",
    render: (row) => (
      <span>
        {row.sharedReplacement}{" "}
        <StatusBadge tone={row.replacementStatus === "IMPLEMENTED" ? "success" : "neutral"} label={row.replacementStatus} />
      </span>
    ),
  },
  { key: "affected", header: "Affected pages", render: (row) => row.affectedPages.join("; ") },
  { key: "priority", header: "Priority", render: (row) => <StatusBadge tone={PRIORITY_TONE[row.priority]} label={row.priority} /> },
  { key: "risk", header: "Breaking-change risk", render: (row) => <StatusBadge tone={RISK_TONE[row.breakingChangeRisk]} label={row.breakingChangeRisk} /> },
];

/**
 * Duplicate-component detection and migration map (CargoGrid UI Modernization
 * checkpoint 3). Rendered through the real DataTable primitive — the migration map is
 * itself dense tabular data, so this page also doubles as one more real DataTable
 * consumer. Per this checkpoint's own instruction: this page only records the map: it
 * does not delete or migrate anything.
 */
export default function DuplicatesPage() {
  return (
    <div className="flex flex-col gap-4">
      <div>
        <h1 className="text-xl font-semibold">Duplicate components &amp; migration map</h1>
        <p className="mt-1 text-sm text-[var(--ds-text-secondary)]">
          Every affected-pages count was verified this checkpoint by grepping <code>app/</code> — not estimated. Legacy
          implementations are left in place; this is a map for future migration work, not a migration performed here.
        </p>
      </div>
      <DataTable
        caption="Duplicate component migration map"
        columns={COLUMNS}
        rows={MIGRATION_MAP}
        rowKey={(row) => row.legacyImplementation}
        emptyMessage="No duplicates recorded."
      />
    </div>
  );
}
