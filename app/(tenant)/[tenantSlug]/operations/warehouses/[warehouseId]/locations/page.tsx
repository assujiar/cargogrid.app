import Link from "next/link";
import { notFound } from "next/navigation";
import { resolveOperationsAccessForRequest } from "../../../../../../../lib/portal/resolve-operations-access.server.ts";
import { createSupabaseServerClient } from "../../../../../../../lib/supabase/server.ts";
import { listWarehouseLocations, BinRackingQueryError } from "../../../../../../../server/queries/bin-racking.ts";
import { parseWarehouseLocation, type WarehouseLocation } from "../../../../../../../server/contracts/bin-racking/bin-racking.ts";
import { ErrorState } from "../../../../../../../components/ui/error-state.tsx";
import { StatusBadge } from "../../../../../../../components/ui/status-badge.tsx";

const LOCATION_STATUS_TONE = { draft: "neutral", active: "success", inactive: "neutral" } as const;

/**
 * Bin and Racking topology view (ATW-230, CG-S10-ATW-011). Read-only, one level at a
 * time over app.list_warehouse_locations -- a warehouse's own root locations, or one
 * parent's own direct children when `?parent=` is given. Deliberately never fetches a
 * full recursive tree client-side (Prompt 230 §17's own "no full warehouse tree in
 * browser" anti-pattern) -- each row link descends exactly one level.
 *
 * Create/edit/move/status-change/barcode-resolve are dispatch/admin-integration
 * operations, not wired to a human data-entry form here -- matching the capacity
 * dashboard's (ATW-227) and warehouse topology view's (ATW-229) own "read surface
 * first" precedent.
 */
export default async function WarehouseLocationsPage({
  params,
  searchParams,
}: {
  params: Promise<{ tenantSlug: string; warehouseId: string }>;
  searchParams: Promise<{ parent?: string }>;
}) {
  const { tenantSlug, warehouseId } = await params;
  const { parent } = await searchParams;
  const access = await resolveOperationsAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    notFound();
  }

  const supabase = await createSupabaseServerClient();

  let locations: WarehouseLocation[] = [];
  let parentLocation: WarehouseLocation | null = null;
  let loadError: "denied" | "failed" | null = null;
  try {
    locations = await listWarehouseLocations(supabase, warehouseId, access.authUserId, parent ?? null);
    if (parent) {
      const { data } = await supabase.from("warehouse_locations").select("*").eq("id", parent).maybeSingle();
      parentLocation = data ? parseWarehouseLocation(data as Record<string, unknown>) : null;
    }
  } catch (error) {
    if (!(error instanceof BinRackingQueryError)) {
      throw error;
    }
    loadError = /insufficient_authority/.test(error.message) ? "denied" : "failed";
  }

  return (
    <div className="flex flex-col gap-4">
      <div>
        <h1 className="text-xl font-semibold text-neutral-900">Bin and racking locations</h1>
        <p className="text-xs text-neutral-500">
          {parentLocation ? (
            <>
              Direct children of <span className="font-medium text-neutral-700">{parentLocation.code}</span> ({parentLocation.name}) --{" "}
              <Link href={`/${tenantSlug}/operations/warehouses/${warehouseId}/locations`} className="underline">
                back to root
              </Link>
            </>
          ) : (
            "Root locations for this warehouse -- rack is optional, a location may sit directly here with no parent."
          )}
        </p>
      </div>

      {loadError === "denied" ? (
        <ErrorState description="You don't hold the OPS View permission needed to see this topology." />
      ) : loadError === "failed" ? (
        <ErrorState description="Something went wrong loading this location topology. Please try again." />
      ) : (
        <div className="overflow-x-auto rounded-md border border-neutral-200">
          <table className="w-full text-left text-sm">
            <thead>
              <tr className="border-b border-neutral-200 text-xs text-neutral-500">
                <th className="py-2 pl-3 pr-3 font-medium">Location</th>
                <th className="py-2 pr-3 font-medium">Type</th>
                <th className="py-2 pr-3 font-medium">Status</th>
                <th className="py-2 pr-3 font-medium">Barcode</th>
                <th className="py-2 pr-3 font-medium">Capacity</th>
                <th className="py-2 pr-3 font-medium">Pick / putaway</th>
                <th className="py-2 pr-3 font-medium"></th>
              </tr>
            </thead>
            <tbody>
              {locations.length === 0 ? (
                <tr>
                  <td colSpan={7} className="py-3 pl-3 text-sm text-neutral-500">
                    No locations here yet.
                  </td>
                </tr>
              ) : (
                locations.map((location) => (
                  <tr key={location.id} className="border-b border-neutral-100">
                    <td className="py-2 pl-3 pr-3">
                      <div className="font-medium text-neutral-900">{location.code}</div>
                      <div className="text-xs text-neutral-500">{location.name}</div>
                    </td>
                    <td className="py-2 pr-3 text-neutral-700">{location.locationType}</td>
                    <td className="py-2 pr-3">
                      <StatusBadge tone={LOCATION_STATUS_TONE[location.status]} label={location.status} />
                    </td>
                    <td className="py-2 pr-3 text-neutral-500">{location.barcode ?? "—"}</td>
                    <td className="py-2 pr-3 text-neutral-700">{location.capacityValue !== null ? `${location.capacityValue} ${location.capacityUom ?? ""}` : "—"}</td>
                    <td className="py-2 pr-3 text-neutral-700">
                      {location.pickEnabled ? "pick" : ""}
                      {location.pickEnabled && location.putawayEnabled ? " / " : ""}
                      {location.putawayEnabled ? "putaway" : ""}
                      {!location.pickEnabled && !location.putawayEnabled ? "—" : ""}
                    </td>
                    <td className="py-2 pr-3 text-right">
                      <Link href={`/${tenantSlug}/operations/warehouses/${warehouseId}/locations?parent=${location.id}`} className="text-xs underline">
                        View children →
                      </Link>
                    </td>
                  </tr>
                ))
              )}
            </tbody>
          </table>
        </div>
      )}
    </div>
  );
}
