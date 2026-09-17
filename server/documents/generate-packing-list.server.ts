/**
 * Packing List generation (audit remediation A7). Assembles a
 * `PackingListData` from already-existing, already-tested read queries --
 * `getWmsPackingTask`, `listWmsPackages`, `listWmsPackageLines`,
 * `getWmsOutboundOrder`, `listTenantWarehouses`, `getAccountById`,
 * `getItemMaster` -- no new schema, no new RPC -- and renders it to a PDF
 * buffer via `@react-pdf/renderer`, the exact pattern established for surat
 * jalan/POD/purchase order.
 *
 * Warehouse label: `app.list_tenant_warehouses` is the only read query this
 * codebase has for warehouse identity (no single-warehouse-by-id getter
 * exists) -- resolved the same "fetch the caller's own scoped list, pick the
 * matching row" way `purchase-order`'s own vendor-address resolution already
 * does when no narrower getter is available. Item code/name: resolved once
 * per distinct `itemMasterId` across every package line (a `Map` cache),
 * never once per line -- the same item is frequently packed into more than
 * one package/line on a real outbound order.
 */

import { createElement } from "react";
import { renderToBuffer } from "@react-pdf/renderer";
import { getWmsPackingTask, listWmsPackages, listWmsPackageLines, WmsPackingQueryError, type WmsPackingQueryClient } from "../queries/wms-packing.ts";
import { getWmsOutboundOrder, WmsOutboundOrderQueryError, type WmsOutboundOrderQueryClient } from "../queries/wms-outbound-order.ts";
import { listTenantWarehouses, WarehouseZoneQueryError, type WarehouseZoneQueryClient } from "../queries/warehouse-zone.ts";
import { getAccountById, AccountQueryError, type AccountQueryClient } from "../queries/account.ts";
import { getItemMaster, ItemUomMasterQueryError, type ItemUomMasterQueryClient } from "../queries/item-uom-master.ts";
import { PackingListDocument, type PackingListData, type PackingListPackageData, type PackingListLineData } from "./packing-list-document.tsx";
import type { WmsPackingTask } from "../contracts/wms-packing/wms-packing.ts";

export class PackingListGenerationError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "PackingListGenerationError";
  }
}

type PackingListGenerationClient = WmsPackingQueryClient & WmsOutboundOrderQueryClient & WarehouseZoneQueryClient & AccountQueryClient & ItemUomMasterQueryClient;

function formatDate(value: string | null): string | null {
  if (!value) return null;
  const parsed = new Date(value);
  if (Number.isNaN(parsed.getTime())) return value;
  return parsed.toLocaleString("id-ID", { dateStyle: "medium", timeStyle: "short" });
}

async function resolveItemLabels(
  client: ItemUomMasterQueryClient,
  itemMasterIds: readonly string[],
  actorAuthUserId: string,
): Promise<Map<string, { code: string; name: string }>> {
  const distinctIds = Array.from(new Set(itemMasterIds));
  const resolved = await Promise.all(
    distinctIds.map(async (itemMasterId) => {
      const item = await getItemMaster(client, itemMasterId, actorAuthUserId);
      return [itemMasterId, { code: item.code, name: item.name }] as const;
    }),
  );
  return new Map(resolved);
}

async function buildPackingListData(client: PackingListGenerationClient, tenantLabel: string, tenantId: string, packingTask: WmsPackingTask, actorAuthUserId: string): Promise<PackingListData> {
  const outboundOrder = await getWmsOutboundOrder(client, packingTask.outboundOrderId, actorAuthUserId);
  const warehouses = await listTenantWarehouses(client, tenantId, actorAuthUserId);
  const warehouse = warehouses.find((candidate) => candidate.id === packingTask.warehouseId) ?? null;
  const account = await getAccountById(client, packingTask.ownerAccountId, actorAuthUserId);

  const wmsPackages = await listWmsPackages(client, tenantId, actorAuthUserId, { packingTaskId: packingTask.id, limit: 200 });
  const lineLists = await Promise.all(wmsPackages.map((pkg) => listWmsPackageLines(client, pkg.id, actorAuthUserId)));
  const itemLabels = await resolveItemLabels(
    client,
    lineLists.flat().map((line) => line.itemMasterId),
    actorAuthUserId,
  );

  const packages: PackingListPackageData[] = wmsPackages.map((pkg, index) => {
    const lines: PackingListLineData[] = (lineLists[index] ?? []).map((line) => {
      const item = itemLabels.get(line.itemMasterId);
      return {
        itemCode: item?.code ?? line.itemMasterId,
        itemName: item?.name ?? "Unknown item",
        lotNumber: line.lotNumber,
        serialNumber: line.serialNumber,
        expiryDate: line.expiryDate,
        quantity: line.quantity,
        uomCode: line.uomCode,
      };
    });
    return {
      packageNumber: pkg.packageNumber,
      packageType: pkg.packageType,
      status: pkg.status,
      qcStatus: pkg.qcStatus,
      weightValue: pkg.weightValue,
      weightUomCode: pkg.weightUomCode,
      lengthValue: pkg.lengthValue,
      widthValue: pkg.widthValue,
      heightValue: pkg.heightValue,
      dimensionUomCode: pkg.dimensionUomCode,
      sealNumber: pkg.sealNumber,
      confirmedAt: formatDate(pkg.confirmedAt),
      confirmedByLabel: pkg.confirmedByLabel,
      lines,
    };
  });

  return {
    tenantLabel,
    packingTaskNumber: packingTask.packingTaskNumber,
    outboundNumber: outboundOrder.outboundNumber,
    warehouseLabel: warehouse ? `${warehouse.code} — ${warehouse.name}` : packingTask.warehouseId,
    ownerAccountLabel: account ? (account.tradeName ? `${account.legalName} (${account.tradeName})` : account.legalName) : "Unknown account",
    printedAt: formatDate(new Date().toISOString()) ?? "",
    packages,
    totalPackages: wmsPackages.length,
    totalQuantity: wmsPackages.reduce((sum, pkg) => sum + pkg.totalPackedQuantity, 0),
  };
}

/** Fetches the packing task (throws PackingListGenerationError for not-found/insufficient-authority, matching getWmsPackingTask's own throw-never-null contract) and every piece of data its printable needs, then renders a PDF buffer. */
export async function generatePackingListPdf(client: PackingListGenerationClient, tenantLabel: string, tenantId: string, packingTaskId: string, actorAuthUserId: string): Promise<{ packingTask: WmsPackingTask; pdfBuffer: Buffer }> {
  let packingTask: WmsPackingTask;
  try {
    packingTask = await getWmsPackingTask(client, packingTaskId, actorAuthUserId);
  } catch (error) {
    if (error instanceof WmsPackingQueryError) throw new PackingListGenerationError(error.message);
    throw error;
  }

  let data: PackingListData;
  try {
    data = await buildPackingListData(client, tenantLabel, tenantId, packingTask, actorAuthUserId);
  } catch (error) {
    if (
      error instanceof WmsPackingQueryError ||
      error instanceof WmsOutboundOrderQueryError ||
      error instanceof WarehouseZoneQueryError ||
      error instanceof AccountQueryError ||
      error instanceof ItemUomMasterQueryError
    ) {
      throw new PackingListGenerationError(error.message);
    }
    throw error;
  }

  const pdfBuffer = await renderToBuffer(createElement(PackingListDocument, { data }) as unknown as Parameters<typeof renderToBuffer>[0]);
  return { packingTask, pdfBuffer };
}
