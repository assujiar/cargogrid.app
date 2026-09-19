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
 *
 * Evidence images (audit remediation NEW-2, follow-on to A6's own closure):
 * this document embeds the real signature/photo images once A6's signed-
 * download RPC exists to fetch them -- `getEpodEvidenceSignedDownloadUrl`
 * (service_role-only) mints a short-lived (300s) Storage signed URL per
 * file, and `@react-pdf/renderer`'s own `Image` component fetches that URL
 * directly while rendering, well inside the TTL. A per-file failure (denied
 * access, a since-deleted file, a transient fetch error) degrades to a
 * text note rather than failing the whole document -- one bad evidence file
 * should never block printing the rest of a real, already-approved POD.
 */

import { createElement } from "react";
import { renderToBuffer } from "@react-pdf/renderer";
import { getShipmentOrder, ShipmentOrderQueryError, type ShipmentOrderQueryTableClient } from "../queries/shipment-order.ts";
import { getEpodCaptureHistory, EpodCaptureReviewQueryError, type EpodCaptureReviewQueryClient } from "../queries/epod-capture-review.ts";
import { getEpodEvidenceSignedDownloadUrl, type EpodEvidenceDownloadClient } from "../mutations/epod-capture-review.ts";
import { PodDocument, type PodData } from "./pod-document.tsx";
import type { ShipmentOrder } from "../contracts/shipment-order/shipment-order.ts";
import type { EpodCapture } from "../contracts/epod-capture-review/epod-capture-review.ts";

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

/** Mints a signed URL for one evidence file, degrading to null (never throwing) on denial or any other failure -- a single unavailable evidence file must not block printing the rest of a real POD. */
async function resolveEvidenceImageUrl(serviceRoleClient: EpodEvidenceDownloadClient, fileId: string, actorAuthUserId: string): Promise<string | null> {
  try {
    const result = await getEpodEvidenceSignedDownloadUrl(serviceRoleClient, fileId, actorAuthUserId, actorAuthUserId);
    return result.accessResult === "granted" ? result.signedUrl : null;
  } catch {
    return null;
  }
}

async function buildPodEvidenceUrls(serviceRoleClient: EpodEvidenceDownloadClient, latest: EpodCapture, actorAuthUserId: string): Promise<{ signatureImageUrl: string | null; photoImageUrls: readonly string[] }> {
  const signatureImageUrl = latest.signatureFileId ? await resolveEvidenceImageUrl(serviceRoleClient, latest.signatureFileId, actorAuthUserId) : null;
  const photoImageUrls = (await Promise.all(latest.photoFileIds.map((fileId) => resolveEvidenceImageUrl(serviceRoleClient, fileId, actorAuthUserId)))).filter((url): url is string => url !== null);
  return { signatureImageUrl, photoImageUrls };
}

/** Fetches the shipment order and its latest ePOD capture, then renders a PDF buffer. Returns null if the shipment does not exist, RLS hides it, or it has no ePOD capture yet -- the caller decides whether that is a 404. `serviceRoleClient` is only ever used for the signed-download RPC + Storage -- every other read goes through `client`, the caller's own RLS-scoped identity. */
export async function generatePodPdf(client: PodGenerationClient, serviceRoleClient: EpodEvidenceDownloadClient, tenantLabel: string, shipmentOrderId: string, actorAuthUserId: string): Promise<{ shipmentOrder: ShipmentOrder; pdfBuffer: Buffer } | null> {
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

  const { signatureImageUrl, photoImageUrls } = await buildPodEvidenceUrls(serviceRoleClient, latest, actorAuthUserId);

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
    signatureImageUrl,
    photoImageUrls,
  };

  const pdfBuffer = await renderToBuffer(createElement(PodDocument, { data }) as unknown as Parameters<typeof renderToBuffer>[0]);
  return { shipmentOrder, pdfBuffer };
}
