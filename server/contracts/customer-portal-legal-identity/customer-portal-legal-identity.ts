/**
 * Legal Identity Change Request contract (ISS-2026-123 item 1). Mirrors
 * supabase/migrations/20260901080000_create_customer_portal_legal_identity_change_requests.sql's
 * RPC surface: app.submit_customer_legal_identity_change_request/app.withdraw_
 * customer_legal_identity_change_request/app.list_customer_portal_legal_identity_
 * change_requests/app.decide_customer_legal_identity_change_request.
 *
 * A SEPARATE writable-field registry from server/contracts/customer-portal-profile/
 * customer-portal-profile.ts's own CUSTOMER_PROFILE_WRITABLE_FIELDS -- legal_name/tax_id
 * live ONLY here, never added to that sibling's registry (its own table's field_name CHECK
 * constraint, and its own unit tests, deliberately still reject them).
 */

import { z } from "zod";

// --- Writable field registry (mirrors the migration's own cplicr_field_name_check) ---

export const CUSTOMER_LEGAL_IDENTITY_WRITABLE_FIELDS = ["legal_name", "tax_id"] as const;
export const CustomerLegalIdentityWritableFieldSchema = z.enum(CUSTOMER_LEGAL_IDENTITY_WRITABLE_FIELDS);
export type CustomerLegalIdentityWritableField = z.infer<typeof CustomerLegalIdentityWritableFieldSchema>;

/** Customer-facing label for each writable field -- presentation only. */
export const CUSTOMER_LEGAL_IDENTITY_WRITABLE_FIELD_LABELS: Record<CustomerLegalIdentityWritableField, string> = {
  legal_name: "Legal name",
  tax_id: "Tax ID",
};

export const CUSTOMER_LEGAL_IDENTITY_CHANGE_REQUEST_STATUSES = ["pending", "approved", "rejected", "withdrawn"] as const;
export const CustomerLegalIdentityChangeRequestStatusSchema = z.enum(CUSTOMER_LEGAL_IDENTITY_CHANGE_REQUEST_STATUSES);
export type CustomerLegalIdentityChangeRequestStatus = z.infer<typeof CustomerLegalIdentityChangeRequestStatusSchema>;

// --- Row schema (app.customer_portal_legal_identity_change_requests) ---

export const CustomerLegalIdentityChangeRequestSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  accountId: z.string().uuid(),
  requestedByActorAuthUserId: z.string().uuid(),
  fieldName: CustomerLegalIdentityWritableFieldSchema,
  proposedValue: z.unknown(),
  status: CustomerLegalIdentityChangeRequestStatusSchema,
  reviewedBy: z.string().nullable(),
  reviewedAt: z.string().nullable(),
  reviewReason: z.string().nullable(),
  idempotencyKey: z.string().nullable(),
  recordVersion: z.number().int().positive(),
  createdAt: z.string(),
  updatedAt: z.string(),
});
export type CustomerLegalIdentityChangeRequest = z.infer<typeof CustomerLegalIdentityChangeRequestSchema>;

export function parseCustomerLegalIdentityChangeRequest(row: Record<string, unknown>): CustomerLegalIdentityChangeRequest {
  return CustomerLegalIdentityChangeRequestSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    accountId: row.account_id,
    requestedByActorAuthUserId: row.requested_by_actor_auth_user_id,
    fieldName: row.field_name,
    proposedValue: row.proposed_value,
    status: row.status,
    reviewedBy: row.reviewed_by ?? null,
    reviewedAt: row.reviewed_at ?? null,
    reviewReason: row.review_reason ?? null,
    idempotencyKey: row.idempotency_key ?? null,
    recordVersion: row.record_version,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  });
}

/** Reads a change request's own proposedValue as the plain display string. */
export function readCustomerLegalIdentityProposedValue(request: CustomerLegalIdentityChangeRequest): string {
  return typeof request.proposedValue === "string" ? request.proposedValue : "";
}

// --- Cursor pagination ---

export const CustomerLegalIdentityChangeRequestCursorSchema = z
  .object({
    cursorUpdatedAt: z.string().nullable().optional(),
    cursorId: z.string().uuid().nullable().optional(),
  })
  .refine((cursor) => !cursor.cursorId || !!cursor.cursorUpdatedAt, {
    message: "cursorUpdatedAt is required when cursorId is supplied",
    path: ["cursorUpdatedAt"],
  });
export type CustomerLegalIdentityChangeRequestCursor = z.input<typeof CustomerLegalIdentityChangeRequestCursorSchema>;

// --- Mutation input schemas ---

export const SubmitCustomerLegalIdentityChangeRequestInputSchema = z.object({
  tenantId: z.string().uuid(),
  accountId: z.string().uuid(),
  fieldName: CustomerLegalIdentityWritableFieldSchema,
  proposedValue: z.string().min(1),
  idempotencyKey: z.string().nullable().optional(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type SubmitCustomerLegalIdentityChangeRequestInput = z.input<typeof SubmitCustomerLegalIdentityChangeRequestInputSchema>;

export const WithdrawCustomerLegalIdentityChangeRequestInputSchema = z.object({
  requestId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type WithdrawCustomerLegalIdentityChangeRequestInput = z.input<typeof WithdrawCustomerLegalIdentityChangeRequestInputSchema>;

export const CUSTOMER_LEGAL_IDENTITY_DECISIONS = ["approve", "reject"] as const;
export const CustomerLegalIdentityDecisionSchema = z.enum(CUSTOMER_LEGAL_IDENTITY_DECISIONS);
export type CustomerLegalIdentityDecision = z.infer<typeof CustomerLegalIdentityDecisionSchema>;

/** Staff-only (COM:Approve, additionally step-up-MFA-gated per tenant policy) -- never callable from a customer-facing route. */
export const DecideCustomerLegalIdentityChangeRequestInputSchema = z.object({
  requestId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  decision: CustomerLegalIdentityDecisionSchema,
  reviewReason: z.string().min(1),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type DecideCustomerLegalIdentityChangeRequestInput = z.input<typeof DecideCustomerLegalIdentityChangeRequestInputSchema>;
