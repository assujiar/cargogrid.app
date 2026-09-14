/**
 * Proof of Delivery (POD) generation (audit remediation A7, second printable
 * document). Assembles a `PodData` from `getEpodCaptureHistory` (OPS-177) --
 * no new schema, no new RPC -- and renders it via `@react-pdf/renderer`,
 * exactly the same `renderToBuffer` pattern established for surat jalan.
 *
 * "Latest" capture is `history.find((c) => c.isLatestVersion)`, the same
 * definition `epod-panel.tsx` already uses for "the current version" --
 * every rejected/revised version stays in history, but only one per
 * `versionGroupId` is ever current. Returns null (the caller's 404) when
 * the shipment has no ePOD capture at all yet, not an error: nothing to
 * print before delivery capture has started.
 */

import { createElement } from "react";
import { renderToBuffer } from "@react-pdf/renderer";
import { getShipmentOrder, ShipmentOrderQueryError, type ShipmentOrderQueryTableClient } from "../queries/shipment-order.ts";
import { getEpodCaptureHistory, EpodCaptureReviewQueryError, type EpodCaptureReviewQueryClient } from "../queries/epod-capture-review.ts";
import { PodDocument, type PodData } from "./pod-document.tsx";
import type { ShipmentOrder } from "../contracts/shipment-order/shipment-order.ts";

export class PodGenerationError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "PodGenerationError";
  }
}

type PodGenerationClient = ShipmentOrderQueryTableClient & EpodCaptureReviewQueryClient;

function formatDate(value: string | null): string | null {
  if (!value) return null;
  const parsed = new Date(value);
  if (Number.isNaN(parsed.getTime())) return value;
  return parsed.toLocaleString("id-ID", { dateStyle: "medium", timeStyle: "short" });
}

/** Fetches the shipment order and its latest ePOD capture, then renders a PDF buffer. Returns null if the shipment does not exist, RLS hides it, or it has no ePOD capture yet -- the caller decides whether that is a 404. */
export async function generatePodPdf(client: PodGenerationClient, tenantLabel: string, shipmentOrderId: string, actorAuthUserId: string): Promise<{ shipmentOrder: ShipmentOrder; pdfBuffer: Buffer } | null> {
  let shipmentOrder: ShipmentOrder | null;
  try {
    shipmentOrder = await getShipmentOrder(client, shipmentOrderId);
  } catch (error) {
    if (error instanceof ShipmentOrderQueryError) throw new PodGenerationError(error.message);
    throw error;
  }
  if (!shipmentOrder) return null;

  let history;
  try {
    history = await getEpodCaptureHistory(client, { shipmentOrderId, actorAuthUserId });
  } catch (error) {
    if (error instanceof EpodCaptureReviewQueryError) throw new PodGenerationError(error.message);
    throw error;
  }

  const latest = history.find((capture) => capture.isLatestVersion) ?? null;
  if (!latest) return null;

  const data: PodData = {
    tenantLabel,
    shipmentNumber: shipmentOrder.shipmentNumber,
    printedAt: formatDate(new Date().toISOString()) ?? "",
    status: latest.status,
    receiverName: latest.receiverName,
    receiverPosition: latest.receiverPosition,
    capturedAt: formatDate(latest.capturedAt),
    versionNumber: latest.versionNumber,
    reviewedAt: formatDate(latest.reviewedAt),
    reviewNotes: latest.reviewNotes,
    photoCount: latest.photoFileIds.length,
    hasSignature: latest.signatureFileId !== null,
  };

  const pdfBuffer = await renderToBuffer(createElement(PodDocument, { data }) as unknown as Parameters<typeof renderToBuffer>[0]);
  return { shipmentOrder, pdfBuffer };
}
