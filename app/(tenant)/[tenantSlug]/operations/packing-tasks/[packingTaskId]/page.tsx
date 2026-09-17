import { notFound } from "next/navigation";
import { resolveOperationsAccessForRequest } from "../../../../../../lib/portal/resolve-operations-access.server.ts";
import { createSupabaseServerClient } from "../../../../../../lib/supabase/server.ts";
import { getWmsPackingTask, listWmsPackages, WmsPackingQueryError } from "../../../../../../server/queries/wms-packing.ts";
import { getWmsOutboundOrder, WmsOutboundOrderQueryError } from "../../../../../../server/queries/wms-outbound-order.ts";
import { listTenantWarehouses, WarehouseZoneQueryError } from "../../../../../../server/queries/warehouse-zone.ts";
import { getAccountById, AccountQueryError } from "../../../../../../server/queries/account.ts";
import type { WmsPackage } from "../../../../../../server/contracts/wms-packing/wms-packing.ts";
import { ErrorState } from "../../../../../../components/ui/error-state.tsx";
import { StatusBadge } from "../../../../../../components/ui/status-badge.tsx";

const PACKAGE_STATUS_TONE = { open: "warning", confirmed: "success" } as const;
const QC_STATUS_TONE = { pending: "neutral", pass: "success", fail: "danger", hold: "warning" } as const;

/**
 * WMS Packing Task detail (audit remediation A7, "packing list" printable).
 * ATW-018's own domain (`app.wms_packing_tasks`/`app.wms_packages`) is real
 * and fully tested (`server/queries/wms-packing.ts`), but had zero
 * pages/actions anywhere -- confirmed live via repo-wide search -- so there
 * was nothing yet to print. Standalone and unlinked, mirroring
 * `finance/config/page.tsx`'s/the inventory-opening-balance import page's
 * own precedent: no host list page for `wms_outbound_orders`/packing tasks
 * exists anywhere in this codebase yet (a genuinely separate, larger gap --
 * an internal outbound-order/pick-pack worklist -- out of this printable-
 * document slice's own scope), so this page is reached directly by a
 * packing task id rather than from an inbound link.
 *
 * Read-only: package/line contents are entered through the mobile/warehouse
 * scanning RPCs this domain already exposes (create/add-line/measure/qc/
 * seal/confirm), not through this page.
 */
export default async function PackingTaskDetailPage({ params }: { params: Promise<{ tenantSlug: string; packingTaskId: string }> }) {
  const { tenantSlug, packingTaskId } = await params;
  const access = await resolveOperationsAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    notFound();
  }

  const supabase = await createSupabaseServerClient();

  let packages: WmsPackage[] = [];
  let outboundNumber = "—";
  let warehouseLabel = "—";
  let ownerAccountLabel = "—";
  let loadError: "denied" | "failed" | null = null;
  try {
    const packingTask = await getWmsPackingTask(supabase, packingTaskId, access.authUserId);
    const [outboundOrder, warehouses, account, wmsPackages] = await Promise.all([
      getWmsOutboundOrder(supabase, packingTask.outboundOrderId, access.authUserId),
      listTenantWarehouses(supabase, access.tenant.id, access.authUserId),
      getAccountById(supabase, packingTask.ownerAccountId, access.authUserId),
      listWmsPackages(supabase, access.tenant.id, access.authUserId, { packingTaskId: packingTask.id, limit: 200 }),
    ]);
    const warehouse = warehouses.find((candidate) => candidate.id === packingTask.warehouseId) ?? null;
    outboundNumber = outboundOrder.outboundNumber;
    warehouseLabel = warehouse ? `${warehouse.code} — ${warehouse.name}` : packingTask.warehouseId;
    ownerAccountLabel = account ? (account.tradeName ? `${account.legalName} (${account.tradeName})` : account.legalName) : "Unknown account";
    packages = wmsPackages;
  } catch (error) {
    if (error instanceof WmsPackingQueryError && /packing_task_not_found/.test(error.message)) {
      notFound();
    }
    if (!(error instanceof WmsPackingQueryError || error instanceof WmsOutboundOrderQueryError || error instanceof WarehouseZoneQueryError || error instanceof AccountQueryError)) {
      throw error;
    }
    loadError = /insufficient_authority|insufficient_privilege/.test(error.message) ? "denied" : "failed";
  }

  return (
    <div className="flex flex-col gap-4">
      <div className="flex flex-wrap items-center justify-between gap-2">
        <div>
          <h1 className="text-xl font-semibold text-neutral-900">Packing task</h1>
          <p className="text-xs text-neutral-500">
            Outbound {outboundNumber} · {warehouseLabel} · {ownerAccountLabel}
          </p>
        </div>
        {loadError === null ? (
          <a
            href={`/${tenantSlug}/operations/packing-tasks/${packingTaskId}/print`}
            target="_blank"
            rel="noopener noreferrer"
            className="text-sm font-medium text-primary underline"
          >
            Print packing list
          </a>
        ) : null}
      </div>

      {loadError === "denied" ? (
        <ErrorState description="You don't hold the OPS View permission needed to see this packing task." />
      ) : loadError === "failed" ? (
        <ErrorState description="Something went wrong loading this packing task. Please try again." />
      ) : packages.length === 0 ? (
        <div className="rounded-md border border-neutral-200 p-4 text-sm text-neutral-500">No packages created under this packing task yet.</div>
      ) : (
        <div className="overflow-x-auto">
          <table className="w-full text-left text-sm">
            <thead>
              <tr className="border-b border-neutral-200 text-xs text-neutral-500">
                <th className="py-2 pr-3 font-medium">Package</th>
                <th className="py-2 pr-3 font-medium">Type</th>
                <th className="py-2 pr-3 font-medium">Status</th>
                <th className="py-2 pr-3 font-medium">QC</th>
                <th className="py-2 pr-3 font-medium">Weight</th>
                <th className="py-2 pr-3 font-medium">Seal</th>
                <th className="py-2 pr-3 font-medium">Lines</th>
                <th className="py-2 pr-3 font-medium">Total qty</th>
              </tr>
            </thead>
            <tbody>
              {packages.map((pkg) => (
                <tr key={pkg.id} className="border-b border-neutral-100">
                  <td className="py-2 pr-3 font-medium text-neutral-900">{pkg.packageNumber}</td>
                  <td className="py-2 pr-3 text-neutral-700">{pkg.packageType}</td>
                  <td className="py-2 pr-3">
                    <StatusBadge tone={PACKAGE_STATUS_TONE[pkg.status]} label={pkg.status} />
                  </td>
                  <td className="py-2 pr-3">
                    <StatusBadge tone={QC_STATUS_TONE[pkg.qcStatus]} label={pkg.qcStatus} />
                  </td>
                  <td className="py-2 pr-3 text-neutral-700">{pkg.weightValue !== null ? `${pkg.weightValue} ${pkg.weightUomCode ?? ""}` : "—"}</td>
                  <td className="py-2 pr-3 text-neutral-700">{pkg.sealNumber ?? "—"}</td>
                  <td className="py-2 pr-3 text-neutral-700">{pkg.lineCount}</td>
                  <td className="py-2 pr-3 text-neutral-700">{pkg.totalPackedQuantity.toLocaleString()}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </div>
  );
}
