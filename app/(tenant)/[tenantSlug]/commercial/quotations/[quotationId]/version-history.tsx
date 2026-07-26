import type { Quotation } from "../../../../../../server/contracts/quotation/quotation.ts";

/** Version history table (COM-152) -- every version sharing one root_quotation_id, oldest first. Locked/current state is shown as a real column (`docs/standards/DESIGN_SYSTEM.md` §2.1's non-color-alone rule), not merely a row highlight. */
export function VersionHistory({ tenantSlug, versions, currentViewedId }: { tenantSlug: string; versions: readonly Quotation[]; currentViewedId: string }) {
  return (
    <div className="rounded-md border border-neutral-200 p-4">
      <h2 className="text-sm font-semibold text-neutral-900">Version history</h2>
      <table className="mt-2 w-full border-collapse text-sm">
        <thead>
          <tr className="border-b border-neutral-200 text-left text-neutral-600">
            <th scope="col" className="py-2 pr-4 font-medium">
              Version
            </th>
            <th scope="col" className="py-2 pr-4 font-medium">
              State
            </th>
            <th scope="col" className="py-2 pr-4 font-medium">
              Reason
            </th>
            <th scope="col" className="py-2 pr-4 font-medium">
              Created
            </th>
            <th scope="col" className="py-2 font-medium">
              Action
            </th>
          </tr>
        </thead>
        <tbody>
          {versions.map((version) => {
            const isViewed = version.id === currentViewedId;
            return (
              <tr key={version.id} className="border-b border-neutral-100">
                <td className="py-2 pr-4 text-neutral-900">v{version.versionNumber}</td>
                <td className="py-2 pr-4 text-neutral-600">{version.isCurrent ? "Current" : "Superseded"} — {version.status}</td>
                <td className="py-2 pr-4 text-neutral-600">{version.revisionReason ?? "—"}</td>
                <td className="py-2 pr-4 text-neutral-600">{new Date(version.createdAt).toLocaleString()}</td>
                <td className="py-2 text-neutral-600">
                  {isViewed ? (
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
                  )}
                </td>
              </tr>
            );
          })}
        </tbody>
      </table>
    </div>
  );
}
