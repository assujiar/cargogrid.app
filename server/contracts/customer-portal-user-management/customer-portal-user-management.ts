/**
 * Customer Portal User Management contract (CPL-315, CG-S13-CPL-017, Prompt
 * 315). Mirrors supabase/migrations/
 * 20260801170000_create_customer_portal_user_management.sql's RPC surface:
 * app.update_customer_portal_account_membership_role/app.record_customer_
 * portal_account_membership_access_review/app.list_customer_portal_account_
 * membership_access_reviews/app.list_customer_portal_account_memberships_
 * for_access_review.
 *
 * Reuses CustomerPortalMembershipRoleSchema/CustomerPortalAccountMembership
 * Schema/parseCustomerPortalAccountMembership from the sibling
 * customer-portal-scope contract directly rather than re-deriving the same
 * role enum/row shape a second, independently-evolving way --
 * app.update_customer_portal_account_membership_role returns the SAME
 * app.customer_portal_account_memberships row shape CPL-300 already modeled.
 */

import { z } from "zod";
import { CustomerPortalMembershipRoleSchema, parseCustomerPortalAccountMembership, type CustomerPortalAccountMembership } from "../customer-portal-scope/customer-portal-scope.ts";

export { parseCustomerPortalAccountMembership };
export type { CustomerPortalAccountMembership };

export const CUSTOMER_PORTAL_ACCESS_REVIEW_OUTCOMES = ["confirmed_appropriate", "flagged_for_follow_up"] as const;
export const CustomerPortalAccessReviewOutcomeSchema = z.enum(CUSTOMER_PORTAL_ACCESS_REVIEW_OUTCOMES);
export type CustomerPortalAccessReviewOutcome = z.infer<typeof CustomerPortalAccessReviewOutcomeSchema>;

/** Customer-admin-facing label for each outcome -- presentation only. */
export const CUSTOMER_PORTAL_ACCESS_REVIEW_OUTCOME_LABELS: Record<CustomerPortalAccessReviewOutcome, string> = {
  confirmed_appropriate: "Confirmed appropriate",
  flagged_for_follow_up: "Flagged for follow-up",
};

// --- Row schema: app.customer_portal_account_membership_access_reviews ---

export const CustomerPortalAccessReviewSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  accountId: z.string().uuid(),
  membershipId: z.string().uuid(),
  reviewedByActorAuthUserId: z.string().uuid(),
  reviewedByLabel: z.string().nullable(),
  reviewOutcome: CustomerPortalAccessReviewOutcomeSchema,
  note: z.string().nullable(),
  idempotencyKey: z.string(),
  reviewedAt: z.string(),
  createdAt: z.string(),
});
export type CustomerPortalAccessReview = z.infer<typeof CustomerPortalAccessReviewSchema>;

export function parseCustomerPortalAccessReview(row: Record<string, unknown>): CustomerPortalAccessReview {
  return CustomerPortalAccessReviewSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    accountId: row.account_id,
    membershipId: row.membership_id,
    reviewedByActorAuthUserId: row.reviewed_by_actor_auth_user_id,
    reviewedByLabel: row.reviewed_by_label ?? null,
    reviewOutcome: row.review_outcome,
    note: row.note ?? null,
    idempotencyKey: row.idempotency_key,
    reviewedAt: row.reviewed_at,
    createdAt: row.created_at,
  });
}

// --- app.list_customer_portal_account_memberships_for_access_review row ---

export const CustomerPortalAccessReviewMembershipRowSchema = z.object({
  membershipId: z.string().uuid(),
  authUserId: z.string().uuid(),
  role: CustomerPortalMembershipRoleSchema,
  status: z.string(),
  grantedAt: z.string(),
  updatedAt: z.string(),
  recordVersion: z.number().int().positive(),
  lastReviewedAt: z.string().nullable(),
  lastReviewedByLabel: z.string().nullable(),
  lastReviewOutcome: CustomerPortalAccessReviewOutcomeSchema.nullable(),
  lastReviewNote: z.string().nullable(),
});
export type CustomerPortalAccessReviewMembershipRow = z.infer<typeof CustomerPortalAccessReviewMembershipRowSchema>;

export function parseCustomerPortalAccessReviewMembershipRow(row: Record<string, unknown>): CustomerPortalAccessReviewMembershipRow {
  return CustomerPortalAccessReviewMembershipRowSchema.parse({
    membershipId: row.membership_id,
    authUserId: row.auth_user_id,
    role: row.role,
    status: row.status,
    grantedAt: row.granted_at,
    updatedAt: row.updated_at,
    recordVersion: row.record_version,
    lastReviewedAt: row.last_reviewed_at ?? null,
    lastReviewedByLabel: row.last_reviewed_by_label ?? null,
    lastReviewOutcome: row.last_review_outcome ?? null,
    lastReviewNote: row.last_review_note ?? null,
  });
}

// --- Cursor pagination (local, self-contained -- mirrors CPL-314's own
// established convention of a per-capability cursor schema even where the
// (timestamp, id) shape is structurally identical to a sibling capability's) ---

export const CustomerPortalAccessReviewCursorSchema = z
  .object({
    cursorReviewedAt: z.string().nullable().optional(),
    cursorId: z.string().uuid().nullable().optional(),
  })
  .refine((cursor) => !cursor.cursorId || !!cursor.cursorReviewedAt, {
    message: "cursorReviewedAt is required when cursorId is supplied",
    path: ["cursorReviewedAt"],
  });
export type CustomerPortalAccessReviewCursor = z.input<typeof CustomerPortalAccessReviewCursorSchema>;

export const CustomerPortalAccessReviewMembershipCursorSchema = z
  .object({
    cursorUpdatedAt: z.string().nullable().optional(),
    cursorId: z.string().uuid().nullable().optional(),
  })
  .refine((cursor) => !cursor.cursorId || !!cursor.cursorUpdatedAt, {
    message: "cursorUpdatedAt is required when cursorId is supplied",
    path: ["cursorUpdatedAt"],
  });
export type CustomerPortalAccessReviewMembershipCursor = z.input<typeof CustomerPortalAccessReviewMembershipCursorSchema>;

// --- Mutation input schemas ---

export const UpdateCustomerPortalAccountMembershipRoleInputSchema = z.object({
  membershipId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  newRole: CustomerPortalMembershipRoleSchema,
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type UpdateCustomerPortalAccountMembershipRoleInput = z.input<typeof UpdateCustomerPortalAccountMembershipRoleInputSchema>;

export const RecordCustomerPortalAccountMembershipAccessReviewInputSchema = z.object({
  membershipId: z.string().uuid(),
  reviewOutcome: CustomerPortalAccessReviewOutcomeSchema,
  note: z.string().nullable().optional(),
  idempotencyKey: z.string().min(1),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type RecordCustomerPortalAccountMembershipAccessReviewInput = z.input<typeof RecordCustomerPortalAccountMembershipAccessReviewInputSchema>;
