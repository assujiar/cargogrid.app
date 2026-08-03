import Link from "next/link";
import { notFound } from "next/navigation";
import { resolveOperationsAccessForRequest } from "../../../../../lib/portal/resolve-operations-access.server.ts";
import { createSupabaseServerClient } from "../../../../../lib/supabase/server.ts";
import { listTenantWarehouses, listWarehouseZones, WarehouseZoneQueryError } from "../../../../../server/queries/warehouse-zone.ts";
import type { TenantWarehouseListRow, WarehouseZone } from "../../../../../server/contracts/warehouse-zone/warehouse-zone.ts";
import { ErrorState } from "../../../../../components/ui/error-state.tsx";
import { StatusBadge } from "../../../../../components/ui/status-badge.tsx";

const WAREHOUSE_STATUS_TONE = { active: "success", inactive: "neutral" } as const;
const ZONE_STATUS_TONE = { active: "success", on_hold: "warning", inactive: "neutral" } as const;

/**
 * Warehouse and Zone topology view (ATW-229, CG-S10-ATW-010). Read-only tenant-wide
 * facility/zone list over app.list_tenant_warehouses/app.list_warehouse_zones -- every
 * warehouse the caller's own org-unit scope can reach, each with its own zone table.
 *
 * Create/edit/eligibility/status-change are dispatch/admin-integration operations, not
 * a human data-entry form here -- this checkpoint ships the topology read surface an
 * admin needs first (matching the capacity dashboard's own precedent, ATW-227), the
 * same facility/zone identity this task's own scope covers; a full topology editor is
 * deferred to whichever future capability first needs one.
 */
export default async function WarehouseZonePage({ params }: { params: Promise<{ tenantSlug: string }> }) {
  const { tenantSlug } = await params;
  const access = await resolveOperationsAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    notFound();
  }

  const supabase = await createSupabaseServerClient();
  const tenantId = access.tenant.id;

  let warehouses: TenantWarehouseListRow[] = [];
  let zonesByWarehouseId = new Map<string, WarehouseZone[]>();
  let loadError: "denied" | "failed" | null = null;
  try {
    warehouses = await listTenantWarehouses(supabase, tenantId, access.authUserId);
    const zoneLists = await Promise.all(warehouses.map((warehouse) => listWarehouseZones(supabase, warehouse.id, access.authUserId)));
    zonesByWarehouseId = new Map(warehouses.map((warehouse, index) => [warehouse.id, zoneLists[index] ?? []]));
  } catch (error) {
    if (!(error instanceof WarehouseZoneQueryError)) {
      throw error;
    }
    loadError = /insufficient_authority/.test(error.message) ? "denied" : "failed";
  }

  return (
    <div className="flex flex-col gap-4">
      <div>
        <h1 className="text-xl font-semibold text-neutral-900">Warehouses and zones</h1>
        <p className="text-xs text-neutral-500">Facility and zone topology for the warehouses your own scope can reach. Warehouse and zone are canonical masters, never copied into a Job Order or Shipment Order.</p>
      </div>

      {loadError === "denied" ? (
        <ErrorState description="You don't hold the OPS View permission needed to see this topology." />
      ) : loadError === "failed" ? (
        <ErrorState description="Something went wrong loading warehouses and zones. Please try again." />
      ) : warehouses.length === 0 ? (
        <div className="rounded-md border border-neutral-200 p-4 text-sm text-neutral-500">No warehouses registered yet.</div>
      ) : (
        warehouses.map((warehouse) => {
          const zones = zonesByWarehouseId.get(warehouse.id) ?? [];
          return (
            <section key={warehouse.id} className="flex flex-col gap-3 rounded-md border border-neutral-200 p-4">
              <div className="flex flex-wrap items-center justify-between gap-2">
                <div>
                  <div className="flex items-center gap-2">
                    <h2 className="text-sm font-semibold text-neutral-900">{warehouse.code}</h2>
                    <StatusBadge tone={WAREHOUSE_STATUS_TONE[warehouse.status]} label={warehouse.status} />
                  </div>
                  <p className="text-xs text-neutral-500">{warehouse.name}</p>
                  <p className="text-xs text-neutral-500">
                    {warehouse.siteAddress ?? "no site address on file"} · {warehouse.timezone}
                  </p>
                  {warehouse.serviceTypeEligibility.length > 0 ? <p className="text-xs text-neutral-500">Service: {warehouse.serviceTypeEligibility.join(", ")}</p> : null}
                </div>
                <div className="text-right text-xs text-neutral-500">
                  <p>
                    {warehouse.activeZoneCount} active / {warehouse.zoneCount} zone{warehouse.zoneCount === 1 ? "" : "s"}
                  </p>
                  <Link href={`/${tenantSlug}/operations/warehouses/${warehouse.id}/locations`} className="underline">
                    Bin and racking locations →
                  </Link>
                </div>
              </div>

              <div className="overflow-x-auto">
                <table className="w-full text-left text-sm">
                  <thead>
                    <tr className="border-b border-neutral-200 text-xs text-neutral-500">
                      <th className="py-2 pr-3 font-medium">Zone</th>
                      <th className="py-2 pr-3 font-medium">Type</th>
                      <th className="py-2 pr-3 font-medium">Status</th>
                      <th className="py-2 pr-3 font-medium">Capacity</th>
                      <th className="py-2 pr-3 font-medium">Effective window</th>
                    </tr>
                  </thead>
                  <tbody>
                    {zones.length === 0 ? (
                      <tr>
                        <td colSpan={5} className="py-3 text-sm text-neutral-500">
                          No zones registered under this warehouse yet.
                        </td>
                      </tr>
                    ) : (
                      zones.map((zone) => (
                        <tr key={zone.id} className="border-b border-neutral-100">
                          <td className="py-2 pr-3">
                            <div className="font-medium text-neutral-900">{zone.code}</div>
                            <div className="text-xs text-neutral-500">{zone.name}</div>
                          </td>
                          <td className="py-2 pr-3 text-neutral-700">{zone.zoneType}</td>
                          <td className="py-2 pr-3">
                            <StatusBadge tone={ZONE_STATUS_TONE[zone.status]} label={zone.status.replace(/_/g, " ")} />
                          </td>
                          <td className="py-2 pr-3 text-neutral-700">{zone.capacityValue !== null ? `${zone.capacityValue} ${zone.capacityUom ?? ""}` : "—"}</td>
                          <td className="py-2 pr-3 text-neutral-500">
                            {zone.effectiveFrom ? new Date(zone.effectiveFrom).toLocaleDateString() : "—"}
                            {zone.effectiveTo ? ` – ${new Date(zone.effectiveTo).toLocaleDateString()}` : ""}
                          </td>
                        </tr>
                      ))
                    )}
                  </tbody>
                </table>
              </div>
            </section>
          );
        })
      )}
    </div>
  );
}
