"use client";

/**
 * Vendor risk / compliance-expiry drilldown queue -- the filter/search/band/hold
 * controls and cursor "Load more" affordance for
 * `app.list_procurement_vendor_risk_dashboard_rows` (PRC-266). Mirrors
 * `app/(tenant)/[tenantSlug]/procurement/vendors/vendor-directory-panel.tsx`'s own
 * exact searchParams-driven filter pattern (the established, already-repository-wide
 * convention for a server-filtered/searched list, Prompt 251 §17's own "no
 * client-loaded full dataset" precedent) -- extracted into its own client component so
 * the filter bar can push URL updates without making the whole dashboard page a client
 * component.
 *
 * Tier C batch-5 fix (HIGH, spec-compliance): before this fix, the RPC's own
 * lifecycle_status/compliance_hold_only/band/search filters and cursor pagination were
 * fully built and db-tested at the RPC layer but had zero UI caller anywhere on this
 * page -- this component is that caller. `after`/`afterId` together are the composite
 * (created_at, vendor_master_id) keyset the corrective migration
 * (20260730790000_harden_procurement_dashboard_reports_tier_c_review_fixes.sql) added
 * to close the tie-drop defect the single-column cursor carried.
 */

import Link from "next/link";
import { useRouter, useSearchParams } from "next/navigation";
import { StatusBadge } from "../../../../../components/ui/status-badge.tsx";
import { EmptyState } from "../../../../../components/ui/empty-state.tsx";
import { VENDOR_LIFECYCLE_STATUSES } from "../../../../../server/contracts/vendor-profile/vendor-profile.ts";
import { VENDOR_KPI_BANDS } from "../../../../../server/contracts/vendor-performance/vendor-performance.ts";
import type { ProcurementVendorRiskDashboardRow } from "../../../../../server/contracts/procurement-dashboard/procurement-dashboard.ts";

const VENDOR_RISK_QUEUE_LIMIT = 25;

export interface VendorRiskQueueFilters {
  readonly status: string;
  readonly band: string;
  readonly hold: boolean;
  readonly search: string;
}

export function VendorRiskQueuePanel({
  tenantSlug,
  rows,
  filters,
}: {
  tenantSlug: string;
  rows: readonly ProcurementVendorRiskDashboardRow[];
  filters: VendorRiskQueueFilters;
}) {
  const router = useRouter();
  const searchParams = useSearchParams();

  function applyFilter(next: Partial<VendorRiskQueueFilters>) {
    const merged: VendorRiskQueueFilters = { ...filters, ...next };
    const params = new URLSearchParams(searchParams.toString());
    if (merged.status) params.set("status", merged.status);
    else params.delete("status");
    if (merged.band) params.set("band", merged.band);
    else params.delete("band");
    if (merged.hold) params.set("hold", "true");
    else params.delete("hold");
    if (merged.search) params.set("q", merged.search);
    else params.delete("q");
    // A new filter always resets pagination back to page 1 -- an "after" cursor from
    // the previous filter set is meaningless once the row order it was walking changes.
    params.delete("after");
    params.delete("afterId");
    router.push(`/${tenantSlug}/procurement/dashboard?${params.toString()}`);
  }

  const lastRow = rows.length > 0 ? rows[rows.length - 1] : null;
  const nextPageParams = new URLSearchParams(searchParams.toString());
  if (lastRow) {
    nextPageParams.set("after", lastRow.createdAt);
    nextPageParams.set("afterId", lastRow.vendorMasterId);
  }
  const hasMore = rows.length === VENDOR_RISK_QUEUE_LIMIT;

  return (
    <div className="flex flex-col gap-2">
      <div className="flex flex-wrap items-end gap-3 rounded-md border border-neutral-200 p-3">
        <div className="flex flex-col gap-1">
          <label htmlFor="vrq-search" className="text-xs font-medium text-neutral-600">
            Search
          </label>
          <input
            id="vrq-search"
            type="search"
            defaultValue={filters.search}
            placeholder="Legal or trade name"
            className="rounded-md border border-neutral-300 px-3 py-1.5 text-sm"
            onKeyDown={(event) => {
              if (event.key === "Enter") applyFilter({ search: event.currentTarget.value });
            }}
          />
        </div>
        <div className="flex flex-col gap-1">
          <label htmlFor="vrq-status" className="text-xs font-medium text-neutral-600">
            Lifecycle status
          </label>
          <select id="vrq-status" defaultValue={filters.status} className="rounded-md border border-neutral-300 px-3 py-1.5 text-sm" onChange={(event) => applyFilter({ status: event.currentTarget.value })}>
            <option value="">All statuses</option>
            {VENDOR_LIFECYCLE_STATUSES.map((s) => (
              <option key={s} value={s}>
                {s.replace(/_/g, " ")}
              </option>
            ))}
          </select>
        </div>
        <div className="flex flex-col gap-1">
          <label htmlFor="vrq-band" className="text-xs font-medium text-neutral-600">
            Scorecard band
          </label>
          <select id="vrq-band" defaultValue={filters.band} className="rounded-md border border-neutral-300 px-3 py-1.5 text-sm" onChange={(event) => applyFilter({ band: event.currentTarget.value })}>
            <option value="">All bands</option>
            {VENDOR_KPI_BANDS.map((b) => (
              <option key={b} value={b}>
                {b}
              </option>
            ))}
          </select>
        </div>
        <label htmlFor="vrq-hold" className="flex items-center gap-2 pb-1.5 text-xs font-medium text-neutral-600">
          <input id="vrq-hold" type="checkbox" defaultChecked={filters.hold} onChange={(event) => applyFilter({ hold: event.currentTarget.checked })} />
          Compliance hold only
        </label>
      </div>

      {rows.length === 0 ? (
        <EmptyState title="No vendors to show" description="No vendor rows matched this filter." />
      ) : (
        <>
          <div className="overflow-x-auto rounded-md border border-neutral-200">
            <table className="w-full text-sm">
              <thead className="bg-neutral-50 text-left text-xs font-medium uppercase text-neutral-500">
                <tr>
                  <th className="px-3 py-2">Vendor</th>
                  <th className="px-3 py-2">Status</th>
                  <th className="px-3 py-2">Compliance</th>
                  <th className="px-3 py-2">Band</th>
                </tr>
              </thead>
              <tbody>
                {rows.map((row) => (
                  <tr key={row.vendorMasterId} className="border-t border-neutral-200">
                    <td className="px-3 py-2">
                      <Link href={`/${tenantSlug}/procurement/vendor-performance/${row.vendorMasterId}`} className="font-medium text-primary hover:underline">
                        {row.legalName}
                      </Link>
                    </td>
                    <td className="px-3 py-2 text-neutral-700">{row.lifecycleStatus.replace(/_/g, " ")}</td>
                    <td className="px-3 py-2 text-xs text-neutral-500">
                      {row.complianceHold ? <StatusBadge tone="danger" label="On hold" /> : "OK"}
                      {row.complianceExpiringSoonCount > 0 ? ` · ${row.complianceExpiringSoonCount} expiring` : ""}
                      {row.complianceExpiredCount > 0 ? ` · ${row.complianceExpiredCount} expired` : ""}
                    </td>
                    <td className="px-3 py-2 text-neutral-700">{row.scorecardBand ?? "—"}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
          {hasMore ? (
            <Link href={`/${tenantSlug}/procurement/dashboard?${nextPageParams.toString()}`} className="self-start text-xs font-medium text-primary hover:underline">
              Load more vendors
            </Link>
          ) : null}
        </>
      )}
    </div>
  );
}
