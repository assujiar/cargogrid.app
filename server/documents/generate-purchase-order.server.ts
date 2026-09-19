/**
 * Purchase Order generation (audit remediation A7). Assembles a
 * `PurchaseOrderData` from already-existing, already-tested read queries --
 * `getPurchaseOrder`, `listPurchaseOrderLines`, `getVendorProfile`,
 * `listVendorAddresses` -- no new schema, no new RPC -- and renders it to a
 * PDF buffer via `@react-pdf/renderer`, the exact pattern established for
 * surat jalan and POD.
 *
 * Vendor address: picks the vendor's own `legal` address (falling back to
 * `billing`, then any address on file) -- `app.vendor_addresses` carries no
 * single "primary" flag, so this is the same "most authoritative available"
 * choice a real PO would use for its "sold to" block. Renders "—" (never an
 * error) when a vendor has no address on file at all -- a real, disclosed gap
 * in vendor onboarding data, not a reason to block printing.
 */

import { createElement } from "react";
import { renderToBuffer } from "@react-pdf/renderer";
import { getPurchaseOrder, listPurchaseOrderLines, PurchaseOrderQueryError, type PurchaseOrderQueryRpcClient } from "../queries/purchase-order.ts";
import { getVendorProfile, listVendorAddresses, VendorProfileQueryError, type VendorProfileQueryClient } from "../queries/vendor-profile.ts";
import { PurchaseOrderDocument, type PurchaseOrderData, type PurchaseOrderLineData } from "./purchase-order-document.tsx";
import type { PurchaseOrder } from "../contracts/purchase-order/purchase-order.ts";
import type { VendorAddress } from "../contracts/vendor-profile/vendor-profile.ts";

export class PurchaseOrderGenerationError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "PurchaseOrderGenerationError";
  }
}

type PurchaseOrderGenerationClient = PurchaseOrderQueryRpcClient & VendorProfileQueryClient;

function formatDate(value: string | null): string | null {
  if (!value) return null;
  const parsed = new Date(value);
  if (Number.isNaN(parsed.getTime())) return value;
  return parsed.toLocaleString("id-ID", { dateStyle: "medium", timeStyle: "short" });
}

function pickVendorAddress(addresses: readonly VendorAddress[]): string | null {
  const preferred = addresses.find((a) => a.addressType === "legal") ?? addresses.find((a) => a.addressType === "billing") ?? addresses[0];
  if (!preferred) return null;
  return [preferred.street, preferred.city, preferred.province, preferred.postalCode, preferred.country].filter((part) => part && part.length > 0).join(", ");
}

async function buildPurchaseOrderData(client: PurchaseOrderGenerationClient, tenantLabel: string, purchaseOrder: PurchaseOrder, lines: readonly PurchaseOrderLineData[], actorAuthUserId: string): Promise<PurchaseOrderData> {
  const vendor = await getVendorProfile(client, purchaseOrder.vendorMasterId, actorAuthUserId);
  const addresses = await listVendorAddresses(client, purchaseOrder.vendorMasterId, actorAuthUserId);

  return {
    tenantLabel,
    poNumber: purchaseOrder.poNumber,
    version: purchaseOrder.version,
    printedAt: formatDate(new Date().toISOString()) ?? "",
    status: purchaseOrder.status,
    vendorLegalName: vendor.legalName,
    vendorCode: vendor.vendorCode,
    vendorAddress: pickVendorAddress(addresses),
    currency: purchaseOrder.currency,
    subtotalAmount: purchaseOrder.subtotalAmount,
    taxCode: purchaseOrder.taxCode,
    taxAmount: purchaseOrder.taxAmount,
    totalAmount: purchaseOrder.totalAmount,
    costMasked: purchaseOrder.costMasked,
    paymentTermDays: purchaseOrder.paymentTermDays,
    expectedDeliveryDate: formatDate(purchaseOrder.expectedDeliveryDate),
    servicePeriodStart: formatDate(purchaseOrder.servicePeriodStart),
    servicePeriodEnd: formatDate(purchaseOrder.servicePeriodEnd),
    commercialTerms: purchaseOrder.commercialTerms,
    notes: purchaseOrder.notes,
    lines,
    issuedAt: formatDate(purchaseOrder.issuedAt),
    issuedBy: purchaseOrder.issuedBy,
  };
}

/** Fetches the purchase order (throws PurchaseOrderGenerationError for not-found/insufficient-authority, matching getPurchaseOrder's own throw-never-null contract) and every piece of data its printable needs, then renders a PDF buffer. */
export async function generatePurchaseOrderPdf(client: PurchaseOrderGenerationClient, tenantLabel: string, purchaseOrderId: string, actorAuthUserId: string): Promise<{ purchaseOrder: PurchaseOrder; pdfBuffer: Buffer }> {
  let purchaseOrder: PurchaseOrder;
  let lines: PurchaseOrderLineData[];
  try {
    purchaseOrder = await getPurchaseOrder(client, purchaseOrderId, actorAuthUserId);
    lines = await listPurchaseOrderLines(client, purchaseOrderId, actorAuthUserId);
  } catch (error) {
    if (error instanceof PurchaseOrderQueryError) throw new PurchaseOrderGenerationError(error.message);
    throw error;
  }

  let data: PurchaseOrderData;
  try {
    data = await buildPurchaseOrderData(client, tenantLabel, purchaseOrder, lines, actorAuthUserId);
  } catch (error) {
    if (error instanceof VendorProfileQueryError) throw new PurchaseOrderGenerationError(error.message);
    throw error;
  }

  const pdfBuffer = await renderToBuffer(createElement(PurchaseOrderDocument, { data }) as unknown as Parameters<typeof renderToBuffer>[0]);
  return { purchaseOrder, pdfBuffer };
}
