/**
 * Customer ePOD access contract (CPL-307, CG-S13-CPL-009, Prompt 307).
 * Mirrors supabase/migrations/20260801080000_create_customer_portal_
 * epod_access.sql's single RPC, app.get_customer_epod.
 *
 * `files` array elements already carry camelCase keys -- the RPC's own
 * `jsonb_build_object('fileId', ..., 'role', ..., 'originalFilename', ...)`
 * projection, the same convention server/contracts/customer-shipment-
 * tracking/customer-shipment-tracking.ts's own `milestones` field already
 * uses -- so no snake_case remapping is needed for that field.
 *
 * `files` never carries `storagePath` -- the RPC itself never selects it
 * (migration design decision 8): no live Supabase Storage integration exists
 * anywhere in this repository, and this capability composes up to the same
 * disclosed boundary `app.access_vendor_compliance_document_evidence`
 * (PRC-253) already established -- authorized file metadata only, never a
 * working signed URL.
 */

import { z } from "zod";

export const EPOD_STATUSES = ["not_available", "quarantined", "available"] as const;
export const EpodStatusSchema = z.enum(EPOD_STATUSES);
export type EpodStatus = z.infer<typeof EpodStatusSchema>;

export const EPOD_FILE_ROLES = ["signature", "photo"] as const;
export const EpodFileRoleSchema = z.enum(EPOD_FILE_ROLES);
export type EpodFileRole = z.infer<typeof EpodFileRoleSchema>;

export const CustomerEpodFileSchema = z.object({
  fileId: z.string().uuid(),
  role: EpodFileRoleSchema,
  originalFilename: z.string(),
  mimeType: z.string(),
  sizeBytes: z.number(),
});
export type CustomerEpodFile = z.infer<typeof CustomerEpodFileSchema>;

export const CustomerEpodSchema = z.object({
  shipmentOrderId: z.string().uuid(),
  epodStatus: EpodStatusSchema,
  epodCaptureId: z.string().uuid().nullable(),
  receiverName: z.string().nullable(),
  capturedAt: z.string().nullable(),
  serverReceivedAt: z.string().nullable(),
  files: z.array(CustomerEpodFileSchema),
});
export type CustomerEpod = z.infer<typeof CustomerEpodSchema>;

/** Maps a raw app.get_customer_epod row (snake_case, `files` already camelCase) to this contract's camelCase shape. */
export function parseCustomerEpod(row: Record<string, unknown>): CustomerEpod {
  const rawFiles = row.files;
  const filesArray: unknown[] = Array.isArray(rawFiles) ? rawFiles : typeof rawFiles === "string" ? (JSON.parse(rawFiles) as unknown[]) : [];

  return CustomerEpodSchema.parse({
    shipmentOrderId: row.shipment_order_id,
    epodStatus: row.epod_status,
    epodCaptureId: row.epod_capture_id ?? null,
    receiverName: row.receiver_name ?? null,
    capturedAt: row.captured_at ?? null,
    serverReceivedAt: row.server_received_at ?? null,
    files: filesArray,
  });
}
