"use client";

import { EmptyState } from "../../../../../components/ui/empty-state.tsx";
import type { OrgPositionTreeRow } from "../../../../../server/contracts/position/position.ts";

const UNIT_TYPE_LABEL: Record<string, string> = {
  company: "Company",
  branch: "Branch",
  department: "Department",
  business_unit: "Business unit",
  team: "Team",
};

/**
 * Renders the org/position tree as an accessible table -- depth is conveyed both
 * visually (indentation) AND textually (an explicit "Level N" cell and a repeated
 * "›" breadcrumb prefix on the name itself), so the hierarchy survives for a
 * screen-reader user who cannot perceive the CSS margin alone
 * (docs/design-system's own "tables/tree alternatives" requirement, section 15).
 */
export function OrganizationTreePanel({ tenantSlug, rows }: { tenantSlug: string; rows: readonly OrgPositionTreeRow[] }) {
  if (rows.length === 0) {
    return <EmptyState title="No organization structure yet" description="No company/branch/department/business_unit/team nodes exist for this tenant yet. Organization nodes are created by a Platform administrator." />;
  }

  return (
    <div className="overflow-x-auto rounded-md border border-neutral-200">
      <table className="w-full text-sm">
        <caption className="sr-only">Organization tree with each unit&apos;s governed positions and current headcount, indented by depth</caption>
        <thead>
          <tr className="border-b border-neutral-200 text-left text-xs text-neutral-500">
            <th scope="col" className="px-3 py-2">
              Organization unit
            </th>
            <th scope="col" className="px-3 py-2">
              Type
            </th>
            <th scope="col" className="px-3 py-2">
              Level
            </th>
            <th scope="col" className="px-3 py-2">
              Position
            </th>
            <th scope="col" className="px-3 py-2">
              Headcount
            </th>
          </tr>
        </thead>
        <tbody>
          {rows.map((row, index) => (
            <tr key={`${row.orgUnitId}-${row.positionId ?? "none"}-${index}`} className="border-t border-neutral-100">
              <td className="px-3 py-1.5" style={{ paddingLeft: `${0.75 + row.depth * 1.25}rem` }}>
                <span aria-hidden="true" className="text-neutral-400">
                  {"› ".repeat(row.depth)}
                </span>
                <span className="font-medium text-neutral-900">{row.orgUnitName}</span> <span className="text-xs text-neutral-500">({row.orgUnitCode})</span>
              </td>
              <td className="px-3 py-1.5 text-xs">{UNIT_TYPE_LABEL[row.unitType] ?? row.unitType}</td>
              <td className="px-3 py-1.5 text-xs">Level {row.depth}</td>
              <td className="px-3 py-1.5 text-xs">
                {row.positionId ? (
                  <a href={`/${tenantSlug}/hris/positions/${row.positionId}`} className="text-primary underline">
                    {row.positionTitle} ({row.positionCode})
                  </a>
                ) : (
                  <span className="text-neutral-400">— no position defined</span>
                )}
              </td>
              <td className="px-3 py-1.5 text-xs">{row.positionId ? `${row.currentHeadcount} / ${row.capacity}` : "—"}</td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}
