/**
 * Customer Quote Request contract (CPL-302, CG-S13-CPL-004, Prompt 302).
 * Mirrors supabase/migrations/20260801030000_create_customer_portal_quote_
 * requests.sql's RPC surface: app.create_customer_quote_request_draft/app.
 * update_customer_quote_request_draft/app.submit_customer_quote_request/app.
 * cancel_customer_quote_request/app.get_customer_quote_request/app.list_
 * customer_quote_requests/app.link_customer_quote_request_to_quotation/app.
 * list_customer_quote_request_files.
 *
 * This is a portal-owned REQUEST for a quote -- never a rated quote itself
 * (ADR-0024 Part B). It carries no tariff/margin/tax field of any kind, on
 * either the database row or this contract. `origin`/`destination` are
 * bounded, free-form location SNAPSHOTS (no canonical address/lane master
 * exists yet, the migration's own design decision 2) -- `QuoteLocationSchema`
 * below is deliberately permissive (every field optional, unknown keys
 * allowed) rather than a strict schema, matching that disclosed boundary.
 */

import { z } from "zod";

export const QUOTE_REQUEST_STATUSES = ["draft", "submitted", "cancelled", "converted"] as const;
export const QuoteRequestStatusSchema = z.enum(QUOTE_REQUEST_STATUSES);
export type QuoteRequestStatus = z.infer<typeof QuoteRequestStatusSchema>;

/** A bounded, free-form location snapshot -- never a canonical address/geocode (no such master exists yet, migration design decision 2). Every field optional; unrecognized keys pass through unchanged. */
export const QuoteLocationSchema = z
  .object({
    label: z.string().optional(),
    addressLine: z.string().optional(),
    city: z.string().optional(),
    country: z.string().optional(),
  })
  .catchall(z.unknown());
export type QuoteLocation = z.infer<typeof QuoteLocationSchema>;

// --- Row schema ---

export const CustomerQuoteRequestSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  accountId: z.string().uuid(),
  requestedByAuthUserId: z.string().uuid(),
  status: QuoteRequestStatusSchema,
  cargoDescription: z.string().nullable(),
  origin: z.record(z.string(), z.unknown()),
  destination: z.record(z.string(), z.unknown()),
  serviceType: z.string().nullable(),
  requestedPickupDate: z.string().nullable(),
  requestedDeliveryDate: z.string().nullable(),
  notes: z.string().nullable(),
  idempotencyKey: z.string().nullable(),
  submittedIdempotencyKey: z.string().nullable(),
  linkedQuotationId: z.string().uuid().nullable(),
  recordVersion: z.number().int().positive(),
  createdBy: z.string().nullable(),
  createdAt: z.string(),
  updatedAt: z.string(),
  submittedAt: z.string().nullable(),
  cancelledAt: z.string().nullable(),
  cancelledReason: z.string().nullable(),
});
export type CustomerQuoteRequest = z.infer<typeof CustomerQuoteRequestSchema>;

export function parseCustomerQuoteRequest(row: Record<string, unknown>): CustomerQuoteRequest {
  return CustomerQuoteRequestSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    accountId: row.account_id,
    requestedByAuthUserId: row.requested_by_auth_user_id,
    status: row.status,
    cargoDescription: row.cargo_description ?? null,
    origin: row.origin ?? {},
    destination: row.destination ?? {},
    serviceType: row.service_type ?? null,
    requestedPickupDate: row.requested_pickup_date ?? null,
    requestedDeliveryDate: row.requested_delivery_date ?? null,
    notes: row.notes ?? null,
    idempotencyKey: row.idempotency_key ?? null,
    submittedIdempotencyKey: row.submitted_idempotency_key ?? null,
    linkedQuotationId: row.linked_quotation_id ?? null,
    recordVersion: row.record_version,
    createdBy: row.created_by ?? null,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
    submittedAt: row.submitted_at ?? null,
    cancelledAt: row.cancelled_at ?? null,
    cancelledReason: row.cancelled_reason ?? null,
  });
}

// --- Attachment metadata row (app.list_customer_quote_request_files) ---

export const CustomerQuoteRequestFileSchema = z.object({
  id: z.string().uuid(),
  originalFilename: z.string(),
  mimeType: z.string(),
  sizeBytes: z.number().int().positive(),
  malwareScanStatus: z.enum(["pending", "clean", "infected", "error"]),
  uploadedByAuthUserId: z.string().uuid(),
  createdAt: z.string(),
});
export type CustomerQuoteRequestFile = z.infer<typeof CustomerQuoteRequestFileSchema>;

export function parseCustomerQuoteRequestFile(row: Record<string, unknown>): CustomerQuoteRequestFile {
  return CustomerQuoteRequestFileSchema.parse({
    id: row.id,
    originalFilename: row.original_filename,
    mimeType: row.mime_type,
    sizeBytes: row.size_bytes,
    malwareScanStatus: row.malware_scan_status,
    uploadedByAuthUserId: row.uploaded_by_auth_user_id,
    createdAt: row.created_at,
  });
}

// --- Cursor pagination ---

/** The (timestamp, id) keyset pair app.list_customer_quote_requests accepts -- never OFFSET. Mirrors server/contracts/customer-portal-scope's CustomerPortalMembershipCursorSchema exactly. */
export const CustomerQuoteRequestCursorSchema = z
  .object({
    cursorUpdatedAt: z.string().nullable().optional(),
    cursorId: z.string().uuid().nullable().optional(),
  })
  .refine((cursor) => !cursor.cursorId || !!cursor.cursorUpdatedAt, {
    message: "cursorUpdatedAt is required when cursorId is supplied",
    path: ["cursorUpdatedAt"],
  });
export type CustomerQuoteRequestCursor = z.input<typeof CustomerQuoteRequestCursorSchema>;

// --- Mutation input schemas ---

const locationInputShape = z.union([QuoteLocationSchema, z.record(z.string(), z.unknown())]).nullable().optional();

export const CreateCustomerQuoteRequestDraftInputSchema = z.object({
  tenantId: z.string().uuid(),
  accountId: z.string().uuid(),
  cargoDescription: z.string().nullable().optional(),
  origin: locationInputShape,
  destination: locationInputShape,
  serviceType: z.string().nullable().optional(),
  requestedPickupDate: z.string().nullable().optional(),
  requestedDeliveryDate: z.string().nullable().optional(),
  notes: z.string().nullable().optional(),
  idempotencyKey: z.string().nullable().optional(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type CreateCustomerQuoteRequestDraftInput = z.input<typeof CreateCustomerQuoteRequestDraftInputSchema>;

export const UpdateCustomerQuoteRequestDraftInputSchema = z.object({
  requestId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  cargoDescription: z.string().nullable().optional(),
  origin: locationInputShape,
  destination: locationInputShape,
  serviceType: z.string().nullable().optional(),
  requestedPickupDate: z.string().nullable().optional(),
  requestedDeliveryDate: z.string().nullable().optional(),
  notes: z.string().nullable().optional(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type UpdateCustomerQuoteRequestDraftInput = z.input<typeof UpdateCustomerQuoteRequestDraftInputSchema>;

export const SubmitCustomerQuoteRequestInputSchema = z.object({
  requestId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  idempotencyKey: z.string().min(1),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type SubmitCustomerQuoteRequestInput = z.input<typeof SubmitCustomerQuoteRequestInputSchema>;

export const CancelCustomerQuoteRequestInputSchema = z.object({
  requestId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  reason: z.string().min(1),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type CancelCustomerQuoteRequestInput = z.input<typeof CancelCustomerQuoteRequestInputSchema>;

export const LinkCustomerQuoteRequestToQuotationInputSchema = z.object({
  requestId: z.string().uuid(),
  quotationId: z.string().uuid(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type LinkCustomerQuoteRequestToQuotationInput = z.input<typeof LinkCustomerQuoteRequestToQuotationInputSchema>;

/** Not a direct RPC 1:1 input -- server/mutations/customer-quote-request-attachment.ts composes this into the existing initiateFileUpload call (server/mutations/document.ts, PLT-128), with documentTypeCode/recordType fixed by this capability. */
export const UploadCustomerQuoteRequestAttachmentInputSchema = z.object({
  tenantId: z.string().uuid(),
  requestId: z.string().uuid(),
  originalFilename: z.string().min(1),
  mimeType: z.string().min(1),
  sizeBytes: z.number().int().positive(),
  idempotencyKey: z.string().nullable().optional(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type UploadCustomerQuoteRequestAttachmentInput = z.input<typeof UploadCustomerQuoteRequestAttachmentInputSchema>;
