/**
 * Customer Document Center contract (CPL-308, CG-S13-CPL-010, Prompt 308).
 * Mirrors both new RPCs in supabase/migrations/20260801090000_create_
 * customer_portal_document_center.sql -- app.list_customer_documents and
 * app.get_customer_document -- which share the identical customer-safe
 * projection shape, so this file exports exactly one row type/parser for
 * both.
 *
 * `documentId` is the underlying app.files.id directly (migration design
 * decision 4) -- there is no separate, synthetic document identifier space.
 */

import { z } from "zod";

export const CUSTOMER_DOCUMENT_SOURCE_MODULES = ["quote_request", "epod", "invoice", "ticket"] as const;
export const CustomerDocumentSourceModuleSchema = z.enum(CUSTOMER_DOCUMENT_SOURCE_MODULES);
export type CustomerDocumentSourceModule = z.infer<typeof CustomerDocumentSourceModuleSchema>;

/**
 * Only these two source modules have a real, live union arm in
 * app.list_customer_documents today (migration design decision 2). `invoice`
 * (Prompt 311) and `ticket` (Prompt 313) are still recognized, valid filter
 * values -- they deterministically return zero rows, never an error and
 * never fabricated data.
 */
export const CUSTOMER_DOCUMENT_LIVE_SOURCE_MODULES = ["quote_request", "epod"] as const satisfies readonly CustomerDocumentSourceModule[];

export const CustomerDocumentSchema = z.object({
  documentId: z.string().uuid(),
  sourceModule: CustomerDocumentSourceModuleSchema,
  sourceEntityId: z.string().uuid(),
  documentType: z.string(),
  originalFilename: z.string(),
  mimeType: z.string(),
  sizeBytes: z.number(),
  /** Reused verbatim from the owning source's own app.files row -- never filtered, never defaulted to "clean" (migration design decision 5). */
  malwareScanStatus: z.string(),
  accountId: z.string().uuid(),
  createdAt: z.string(),
});
export type CustomerDocument = z.infer<typeof CustomerDocumentSchema>;

/** Maps a raw app.list_customer_documents/app.get_customer_document row (snake_case) to this contract's camelCase shape. */
export function parseCustomerDocument(row: Record<string, unknown>): CustomerDocument {
  return CustomerDocumentSchema.parse({
    documentId: row.document_id,
    sourceModule: row.source_module,
    sourceEntityId: row.source_entity_id,
    documentType: row.document_type,
    originalFilename: row.original_filename,
    mimeType: row.mime_type,
    sizeBytes: row.size_bytes,
    malwareScanStatus: row.malware_scan_status,
    accountId: row.account_id,
    createdAt: row.created_at,
  });
}
