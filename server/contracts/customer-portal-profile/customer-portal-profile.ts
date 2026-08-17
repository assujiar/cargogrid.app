/**
 * Customer Profile contract (CPL-314, CG-S13-CPL-016, Prompt 314). Mirrors
 * supabase/migrations/20260801150000_create_customer_portal_customer_profile.sql's
 * RPC surface: app.submit_customer_profile_change_request/app.withdraw_
 * customer_profile_change_request/app.list_customer_portal_profile_change_
 * requests/app.get_customer_portal_account_profile/app.list_customer_portal_
 * account_contacts/app.decide_customer_profile_change_request.
 *
 * Writable field set is deliberately narrow: trade_name and billing_address
 * only (migration design decision 2) -- legal_name/tax_id are readable
 * (CustomerPortalAccountProfileSchema) but never appear in
 * CUSTOMER_PROFILE_WRITABLE_FIELDS. There is no credit-adjacent field
 * anywhere on this contract -- app.accounts itself carries none.
 */

import { z } from "zod";

// --- Writable field registry (mirrors the migration's own cppcr_field_name_check) ---

export const CUSTOMER_PROFILE_WRITABLE_FIELDS = ["trade_name", "billing_address"] as const;
export const CustomerProfileWritableFieldSchema = z.enum(CUSTOMER_PROFILE_WRITABLE_FIELDS);
export type CustomerProfileWritableField = z.infer<typeof CustomerProfileWritableFieldSchema>;

/** Customer-facing label for each writable field -- presentation only. */
export const CUSTOMER_PROFILE_WRITABLE_FIELD_LABELS: Record<CustomerProfileWritableField, string> = {
  trade_name: "Trade name",
  billing_address: "Billing address",
};

export const CUSTOMER_PROFILE_CHANGE_REQUEST_STATUSES = ["pending", "approved", "rejected", "withdrawn"] as const;
export const CustomerProfileChangeRequestStatusSchema = z.enum(CUSTOMER_PROFILE_CHANGE_REQUEST_STATUSES);
export type CustomerProfileChangeRequestStatus = z.infer<typeof CustomerProfileChangeRequestStatusSchema>;

/** A bounded, free-form billing address object -- mirrors app.accounts.billing_address's own shape (no stricter schema than "is a JSON object" exists on the canonical column itself). */
export const CustomerProfileBillingAddressSchema = z
  .object({
    line1: z.string().optional(),
    line2: z.string().optional(),
    city: z.string().optional(),
    state: z.string().optional(),
    postalCode: z.string().optional(),
    country: z.string().optional(),
  })
  .catchall(z.unknown());
export type CustomerProfileBillingAddress = z.infer<typeof CustomerProfileBillingAddressSchema>;

// --- Row schema (app.customer_portal_profile_change_requests) ---

export const CustomerProfileChangeRequestSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  accountId: z.string().uuid(),
  requestedByActorAuthUserId: z.string().uuid(),
  fieldName: CustomerProfileWritableFieldSchema,
  proposedValue: z.unknown(),
  status: CustomerProfileChangeRequestStatusSchema,
  reviewedBy: z.string().nullable(),
  reviewedAt: z.string().nullable(),
  reviewReason: z.string().nullable(),
  idempotencyKey: z.string().nullable(),
  recordVersion: z.number().int().positive(),
  createdAt: z.string(),
  updatedAt: z.string(),
});
export type CustomerProfileChangeRequest = z.infer<typeof CustomerProfileChangeRequestSchema>;

export function parseCustomerProfileChangeRequest(row: Record<string, unknown>): CustomerProfileChangeRequest {
  return CustomerProfileChangeRequestSchema.parse({
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

/** Reads a change request's own proposedValue as the plain display value for its fieldName (a JSON string for trade_name, a JSON object for billing_address) -- never assumes a shape the row's own fieldName does not declare. */
export function readCustomerProfileProposedValue(request: CustomerProfileChangeRequest): string | CustomerProfileBillingAddress {
  if (request.fieldName === "trade_name") {
    return typeof request.proposedValue === "string" ? request.proposedValue : "";
  }
  const parsed = CustomerProfileBillingAddressSchema.safeParse(request.proposedValue);
  return parsed.success ? parsed.data : {};
}

// --- app.get_customer_portal_account_profile ---

export const CustomerPortalAccountProfileSchema = z.object({
  accountId: z.string().uuid(),
  legalName: z.string(),
  tradeName: z.string().nullable(),
  taxId: z.string().nullable(),
  billingAddress: z.record(z.string(), z.unknown()),
  customerStatus: z.string(),
  recordVersion: z.number().int().positive(),
  updatedAt: z.string(),
  pendingChangeRequestCount: z.number().int().nonnegative(),
  latestPendingChangeRequestId: z.string().uuid().nullable(),
  latestPendingChangeRequestField: CustomerProfileWritableFieldSchema.nullable(),
  latestPendingChangeRequestSubmittedAt: z.string().nullable(),
});
export type CustomerPortalAccountProfile = z.infer<typeof CustomerPortalAccountProfileSchema>;

export function parseCustomerPortalAccountProfile(row: Record<string, unknown>): CustomerPortalAccountProfile {
  return CustomerPortalAccountProfileSchema.parse({
    accountId: row.account_id,
    legalName: row.legal_name,
    tradeName: row.trade_name ?? null,
    taxId: row.tax_id ?? null,
    billingAddress: row.billing_address ?? {},
    customerStatus: row.customer_status,
    recordVersion: row.record_version,
    updatedAt: row.updated_at,
    pendingChangeRequestCount: row.pending_change_request_count ?? 0,
    latestPendingChangeRequestId: row.latest_pending_change_request_id ?? null,
    latestPendingChangeRequestField: row.latest_pending_change_request_field ?? null,
    latestPendingChangeRequestSubmittedAt: row.latest_pending_change_request_submitted_at ?? null,
  });
}

// --- app.list_customer_portal_account_contacts (read-only, no change-request path -- migration design decision 4) ---

export const CustomerPortalAccountContactSchema = z.object({
  contactId: z.string().uuid(),
  fullName: z.string(),
  title: z.string().nullable(),
  email: z.string().nullable(),
  phone: z.string().nullable(),
  role: z.string(),
  isPrimary: z.boolean(),
});
export type CustomerPortalAccountContact = z.infer<typeof CustomerPortalAccountContactSchema>;

export function parseCustomerPortalAccountContact(row: Record<string, unknown>): CustomerPortalAccountContact {
  return CustomerPortalAccountContactSchema.parse({
    contactId: row.contact_id,
    fullName: row.full_name,
    title: row.title ?? null,
    email: row.email ?? null,
    phone: row.phone ?? null,
    role: row.role,
    isPrimary: row.is_primary,
  });
}

// --- Cursor pagination ---

export const CustomerProfileChangeRequestCursorSchema = z
  .object({
    cursorUpdatedAt: z.string().nullable().optional(),
    cursorId: z.string().uuid().nullable().optional(),
  })
  .refine((cursor) => !cursor.cursorId || !!cursor.cursorUpdatedAt, {
    message: "cursorUpdatedAt is required when cursorId is supplied",
    path: ["cursorUpdatedAt"],
  });
export type CustomerProfileChangeRequestCursor = z.input<typeof CustomerProfileChangeRequestCursorSchema>;

// --- Mutation input schemas ---

export const SubmitCustomerProfileChangeRequestInputSchema = z.object({
  tenantId: z.string().uuid(),
  accountId: z.string().uuid(),
  fieldName: CustomerProfileWritableFieldSchema,
  proposedValue: z.union([z.string(), CustomerProfileBillingAddressSchema]),
  idempotencyKey: z.string().nullable().optional(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type SubmitCustomerProfileChangeRequestInput = z.input<typeof SubmitCustomerProfileChangeRequestInputSchema>;

export const WithdrawCustomerProfileChangeRequestInputSchema = z.object({
  requestId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type WithdrawCustomerProfileChangeRequestInput = z.input<typeof WithdrawCustomerProfileChangeRequestInputSchema>;

export const CUSTOMER_PROFILE_DECISIONS = ["approve", "reject"] as const;
export const CustomerProfileDecisionSchema = z.enum(CUSTOMER_PROFILE_DECISIONS);
export type CustomerProfileDecision = z.infer<typeof CustomerProfileDecisionSchema>;

/** Staff-only (COM:Approve) -- never callable from a customer-facing route. */
export const DecideCustomerProfileChangeRequestInputSchema = z.object({
  requestId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  decision: CustomerProfileDecisionSchema,
  reviewReason: z.string().min(1),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type DecideCustomerProfileChangeRequestInput = z.input<typeof DecideCustomerProfileChangeRequestInputSchema>;
