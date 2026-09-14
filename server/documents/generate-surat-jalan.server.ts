/**
 * Surat Jalan generation (audit remediation A7). Assembles a `SuratJalanData`
 * from already-existing, already-tested read queries -- no new schema, no new
 * RPC -- and renders it to a PDF buffer via `@react-pdf/renderer`
 * (`renderToBuffer`, the Node entry point; pure JS, no headless-browser
 * dependency, so it runs unchanged in a Vercel serverless function).
 *
 * Vehicle/driver come from `getResourceAssignmentHistory`'s own current
 * (`isCurrent: true`) rows for the `vehicle`/`driver` roles -- a shipment may
 * have neither assigned yet (pre-dispatch), which renders as "—", not an
 * error: a surat jalan can legitimately be printed and hand-annotated before
 * dispatch is finalized.
 */

import { createElement } from "react";
import { renderToBuffer } from "@react-pdf/renderer";
import { getShipmentOrder, ShipmentOrderQueryError, type ShipmentOrderQueryTableClient } from "../queries/shipment-order.ts";
import { getAccountById, AccountQueryError } from "../queries/account.ts";
import { getResourceAssignmentHistory, ResourceAssignmentQueryError } from "../queries/resource-assignment.ts";
import { SuratJalanDocument, type SuratJalanData } from "./surat-jalan-document.tsx";
import { toLabeledValues } from "./surat-jalan-labeled-values.ts";
import type { ShipmentOrder } from "../contracts/shipment-order/shipment-order.ts";

export class SuratJalanGenerationError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "SuratJalanGenerationError";
  }
}

function formatDate(value: string | null): string | null {
  if (!value) return null;
  const parsed = new Date(value);
  if (Number.isNaN(parsed.getTime())) return value;
  return parsed.toLocaleString("id-ID", { dateStyle: "medium", timeStyle: "short" });
}

async function buildSuratJalanData(client: ShipmentOrderQueryTableClient, tenantLabel: string, shipmentOrder: ShipmentOrder, actorAuthUserId: string): Promise<SuratJalanData> {
  const account = await getAccountById(client, shipmentOrder.shipperAccountId, actorAuthUserId);
  const assignments = await getResourceAssignmentHistory(client, { shipmentOrderId: shipmentOrder.id, actorAuthUserId });

  const currentVehicle = assignments.find((assignment) => assignment.role === "vehicle" && assignment.isCurrent);
  const currentDriver = assignments.find((assignment) => assignment.role === "driver" && assignment.isCurrent);

  return {
    tenantLabel,
    shipmentNumber: shipmentOrder.shipmentNumber,
    printedAt: formatDate(new Date().toISOString()) ?? "",
    shipperLegalName: account?.legalName ?? "—",
    shipperDetails: toLabeledValues(account?.billingAddress),
    consigneeDetails: toLabeledValues(shipmentOrder.consigneeSnapshot),
    notifyPartyDetails: toLabeledValues(shipmentOrder.notifyPartySnapshot),
    origin: shipmentOrder.origin,
    destination: shipmentOrder.destination,
    plannedPickupAt: formatDate(shipmentOrder.plannedPickupAt),
    plannedDeliveryAt: formatDate(shipmentOrder.plannedDeliveryAt),
    serviceType: shipmentOrder.serviceType,
    mode: shipmentOrder.mode,
    cargoDetails: toLabeledValues(shipmentOrder.cargoServiceSnapshot),
    basisQuantity: shipmentOrder.basisQuantity,
    basisWeightKg: shipmentOrder.basisWeightKg,
    basisVolumeCbm: shipmentOrder.basisVolumeCbm,
    vehicleLabel: currentVehicle ? `${currentVehicle.resourceSnapshot.name} (${currentVehicle.resourceSnapshot.code})` : null,
    driverLabel: currentDriver ? `${currentDriver.resourceSnapshot.name} (${currentDriver.resourceSnapshot.code})` : null,
  };
}

/** Fetches the shipment order (returns null if it does not exist or RLS hides it -- the caller decides whether that is a 404) and every piece of data its surat jalan needs, then renders a PDF buffer. */
export async function generateSuratJalanPdf(client: ShipmentOrderQueryTableClient, tenantLabel: string, shipmentOrderId: string, actorAuthUserId: string): Promise<{ shipmentOrder: ShipmentOrder; pdfBuffer: Buffer } | null> {
  let shipmentOrder: ShipmentOrder | null;
  try {
    shipmentOrder = await getShipmentOrder(client, shipmentOrderId);
  } catch (error) {
    if (error instanceof ShipmentOrderQueryError) throw new SuratJalanGenerationError(error.message);
    throw error;
  }
  if (!shipmentOrder) return null;

  let data: SuratJalanData;
  try {
    data = await buildSuratJalanData(client, tenantLabel, shipmentOrder, actorAuthUserId);
  } catch (error) {
    if (error instanceof AccountQueryError || error instanceof ResourceAssignmentQueryError) throw new SuratJalanGenerationError(error.message);
    throw error;
  }

  // renderToBuffer's own type declares its parameter as ReactElement<DocumentProps> --
  // the props of the root <Document> react-pdf component specifically, not any
  // component that happens to return one. Passing a wrapper functional component
  // (the idiomatic way to keep this file free of JSX/`.tsx`) is the same shape every
  // react-pdf consumer uses; the cast below is narrowing a genuinely-too-strict
  // upstream type, not silencing a real mismatch -- renderToBuffer only ever calls
  // React's own reconciler on the element, which does not care about this distinction.
  const pdfBuffer = await renderToBuffer(createElement(SuratJalanDocument, { data }) as unknown as Parameters<typeof renderToBuffer>[0]);
  return { shipmentOrder, pdfBuffer };
}
