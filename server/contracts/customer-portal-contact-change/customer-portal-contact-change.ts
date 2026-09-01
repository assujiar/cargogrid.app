/**
 * Contact Change Request contract (ISS-2026-123 item 2). Mirrors
 * supabase/migrations/20260901090000_create_customer_portal_contact_change_requests.sql's RPC
 * surface: app.submit_customer_contact_change_request/app.withdraw_customer_contact_change_
 * request/app.list_customer_portal_contact_change_requests/app.decide_customer_contact_change_
 * request.
 *
 * change_kind is {add, update, remove}; target_contact_id is required for update/remove and
 * forbidden for add -- mirrors the migration's own cpccr_target_contact_shape_check.
 */

import { z } from "zod";

export const CUSTOMER_CONTACT_CHANGE_KINDS = ["add", "update", "remove"] as const;
export const CustomerContactChangeKindSchema = z.enum(CUSTOMER_CONTACT_CHANGE_KINDS);
export type CustomerContactChangeKind = z.infer<typeof CustomerContactChangeKindSchema>;

export const CUSTOMER_CONTACT_ROLES = ["primary", "billing", "technical", "decision_maker", "other"] as const;
export const CustomerContactRoleSchema = z.enum(CUSTOMER_CONTACT_ROLES);
export type CustomerContactRole = z.infer<typeof CustomerContactRoleSchema>;

export const CUSTOMER_CONTACT_CHANGE_REQUEST_STATUSES = ["pending", "approved", "rejected", "withdrawn"] as const;
export const CustomerContactChangeRequestStatusSchema = z.enum(CUSTOMER_CONTACT_CHANGE_REQUEST_STATUSES);
export type CustomerContactChangeRequestStatus = z.infer<typeof CustomerContactChangeRequestStatusSchema>;

// --- Row schema (app.customer_portal_contact_change_requests) ---

export const CustomerContactChangeRequestSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  accountId: z.string().uuid(),
  requestedByActorAuthUserId: z.string().uuid(),
  changeKind: CustomerContactChangeKindSchema,
  targetContactId: z.string().uuid().nullable(),
  fullName: z.string().nullable(),
  title: z.string().nullable(),
  email: z.string().nullable(),
  phone: z.string().nullable(),
  role: CustomerContactRoleSchema.nullable(),
  isPrimary: z.boolean().nullable(),
  status: CustomerContactChangeRequestStatusSchema,
  reviewedBy: z.string().nullable(),
  reviewedAt: z.string().nullable(),
  reviewReason: z.string().nullable(),
  idempotencyKey: z.string().nullable(),
  recordVersion: z.number().int().positive(),
  createdAt: z.string(),
  updatedAt: z.string(),
});
export type CustomerContactChangeRequest = z.infer<typeof CustomerContactChangeRequestSchema>;

export function parseCustomerContactChangeRequest(row: Record<string, unknown>): CustomerContactChangeRequest {
  return CustomerContactChangeRequestSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    accountId: row.account_id,
    requestedByActorAuthUserId: row.requested_by_actor_auth_user_id,
    changeKind: row.change_kind,
    targetContactId: row.target_contact_id ?? null,
    fullName: row.full_name ?? null,
    title: row.title ?? null,
    email: row.email ?? null,
    phone: row.phone ?? null,
    role: row.role ?? null,
    isPrimary: row.is_primary ?? null,
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

// --- Cursor pagination ---

export const CustomerContactChangeRequestCursorSchema = z
  .object({
    cursorUpdatedAt: z.string().nullable().optional(),
    cursorId: z.string().uuid().nullable().optional(),
  })
  .refine((cursor) => !cursor.cursorId || !!cursor.cursorUpdatedAt, {
    message: "cursorUpdatedAt is required when cursorId is supplied",
    path: ["cursorUpdatedAt"],
  });
export type CustomerContactChangeRequestCursor = z.input<typeof CustomerContactChangeRequestCursorSchema>;

// --- Mutation input schemas ---

const baseSubmitFields = {
  tenantId: z.string().uuid(),
  accountId: z.string().uuid(),
  fullName: z.string().min(1).nullable().optional(),
  title: z.string().min(1).nullable().optional(),
  email: z.string().email().nullable().optional(),
  phone: z.string().min(1).nullable().optional(),
  role: CustomerContactRoleSchema.nullable().optional(),
  isPrimary: z.boolean().nullable().optional(),
  idempotencyKey: z.string().nullable().optional(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
};

/**
 * add: targetContactId forbidden (enforced by the migration's own CHECK -- validated again
 * here client-side for a fast, form-shaped error). update/remove: targetContactId required.
 */
export const SubmitCustomerContactChangeRequestInputSchema = z
  .object({
    changeKind: CustomerContactChangeKindSchema,
    targetContactId: z.string().uuid().nullable().optional(),
    ...baseSubmitFields,
  })
  .refine((v) => (v.changeKind === "add" ? !v.targetContactId : !!v.targetContactId), {
    message: "targetContactId is required for update/remove and forbidden for add",
    path: ["targetContactId"],
  });
export type SubmitCustomerContactChangeRequestInput = z.input<typeof SubmitCustomerContactChangeRequestInputSchema>;

export const WithdrawCustomerContactChangeRequestInputSchema = z.object({
  requestId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type WithdrawCustomerContactChangeRequestInput = z.input<typeof WithdrawCustomerContactChangeRequestInputSchema>;

export const CUSTOMER_CONTACT_CHANGE_DECISIONS = ["approve", "reject"] as const;
export const CustomerContactChangeDecisionSchema = z.enum(CUSTOMER_CONTACT_CHANGE_DECISIONS);
export type CustomerContactChangeDecision = z.infer<typeof CustomerContactChangeDecisionSchema>;

/** Staff-only (COM:Approve, additionally step-up-MFA-gated per tenant policy) -- never callable from a customer-facing route. */
export const DecideCustomerContactChangeRequestInputSchema = z.object({
  requestId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  decision: CustomerContactChangeDecisionSchema,
  reviewReason: z.string().min(1),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type DecideCustomerContactChangeRequestInput = z.input<typeof DecideCustomerContactChangeRequestInputSchema>;
