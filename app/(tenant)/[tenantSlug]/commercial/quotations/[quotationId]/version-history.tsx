import type { Quotation } from "../../../../../../server/contracts/quotation/quotation.ts";
import { DataTable, type DataTableColumn } from "../../../../../../components/tables/data-table.tsx";
import { StatusBadge } from "../../../../../../components/ui/status-badge.tsx";
import { QUOTATION_STATUS_TONE_MAP } from "../../../../../../components/domain/status-tone-map.ts";

/** Version history table (COM-152) -- every version sharing one root_quotation_id, oldest first. Locked/current state is shown as a real column (`docs/standards/DESIGN_SYSTEM.md` §2.1's non-color-alone rule), not merely a row highlight. */
export function VersionHistory({ tenantSlug, versions, currentViewedId }: { tenantSlug: string; versions: readonly Quotation[]; currentViewedId: string }) {
  const columns: readonly DataTableColumn<Quotation>[] = [
    { key: "version", header: "Version", render: (version) => `v${version.versionNumber}` },
    {
      key: "state",
      header: "State",
      render: (version) => {
        const { tone, label } = QUOTATION_STATUS_TONE_MAP[version.status];
        return (
          <span className="flex items-center gap-2">
            <StatusBadge tone={version.isCurrent ? "success" : "neutral"} label={version.isCurrent ? "Current" : "Superseded"} />
            <StatusBadge tone={tone} label={label} />
          </span>
        );
      },
    },
    { key: "reason", header: "Reason", render: (version) => version.revisionReason ?? "—" },
    { key: "created", header: "Created", render: (version) => new Date(version.createdAt).toLocaleString() },
    {
      key: "action",
      header: "Action",
      render: (version) =>
        version.id === currentViewedId ? (
          "Viewing"
        ) : (
          <span className="flex gap-3">
            <a href={`/${tenantSlug}/commercial/quotations/${version.id}`} className="font-medium text-primary underline">
              View
            </a>
            <a href={`/${tenantSlug}/commercial/quotations/${currentViewedId}?compareWith=${version.id}`} className="font-medium text-primary underline">
              Compare
            </a>
          </span>
        ),
    },
  ];

  return (
    <div className="rounded-md border border-neutral-200 p-4">
      <h2 className="text-sm font-semibold text-neutral-900">Version history</h2>
      <div className="mt-2">
        <DataTable
          caption="Quotation version history"
          columns={columns}
          rows={versions}
          rowKey={(version) => version.id}
          emptyMessage="No versions."
        />
      </div>
    </div>
  );
}
