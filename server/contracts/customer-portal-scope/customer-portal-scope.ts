/**
 * Customer Portal Scope contract (CPL-300, CG-S13-CPL-002, Prompt 300). Mirrors
 * supabase/migrations/20260801010000_create_customer_portal_account_scope.sql's
 * RPC surface: app.resolve_customer_account_scope/app.get_customer_portal_scope_
 * context/app.invite_customer_portal_user/app.accept_customer_portal_invite/app.
 * set_customer_portal_account_membership_status/app.list_customer_portal_
 * account_memberships/app.grant_initial_customer_portal_account_admin.
 *
 * This is the new, canonical Layer-4 scope primitive every downstream Phase 8
 * capability (301 onward) composes -- ADR-0024 Part A.
 */

import { z } from "zod";

export const CUSTOMER_PORTAL_MEMBERSHIP_ROLES = ["account_admin", "member"] as const;
export const CustomerPortalMembershipRoleSchema = z.enum(CUSTOMER_PORTAL_MEMBERSHIP_ROLES);
export type CustomerPortalMembershipRole = z.infer<typeof CustomerPortalMembershipRoleSchema>;

export const CUSTOMER_PORTAL_MEMBERSHIP_STATUSES = ["invited", "active", "suspended", "revoked"] as const;
export const CustomerPortalMembershipStatusSchema = z.enum(CUSTOMER_PORTAL_MEMBERSHIP_STATUSES);
export type CustomerPortalMembershipStatus = z.infer<typeof CustomerPortalMembershipStatusSchema>;

// --- Row schemas ---

/** The full app.customer_portal_account_memberships row -- returned by every mutation RPC and app.list_customer_portal_account_memberships. */
export const CustomerPortalAccountMembershipSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  authUserId: z.string().uuid(),
  accountId: z.string().uuid(),
  role: CustomerPortalMembershipRoleSchema,
  status: CustomerPortalMembershipStatusSchema,
  invitedBy: z.string().nullable(),
  invitedAt: z.string().nullable(),
  acceptedAt: z.string().nullable(),
  grantedBy: z.string().nullable(),
  grantedAt: z.string(),
  suspendedBy: z.string().nullable(),
  suspendedAt: z.string().nullable(),
  suspendedReason: z.string().nullable(),
  revokedBy: z.string().nullable(),
  revokedAt: z.string().nullable(),
  revokedReason: z.string().nullable(),
  recordVersion: z.number().int().positive(),
  createdAt: z.string(),
  updatedAt: z.string(),
});
export type CustomerPortalAccountMembership = z.infer<typeof CustomerPortalAccountMembershipSchema>;

export function parseCustomerPortalAccountMembership(row: Record<string, unknown>): CustomerPortalAccountMembership {
  return CustomerPortalAccountMembershipSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    authUserId: row.auth_user_id,
    accountId: row.account_id,
    role: row.role,
    status: row.status,
    invitedBy: row.invited_by ?? null,
    invitedAt: row.invited_at ?? null,
    acceptedAt: row.accepted_at ?? null,
    grantedBy: row.granted_by ?? null,
    grantedAt: row.granted_at,
    suspendedBy: row.suspended_by ?? null,
    suspendedAt: row.suspended_at ?? null,
    suspendedReason: row.suspended_reason ?? null,
    revokedBy: row.revoked_by ?? null,
    revokedAt: row.revoked_at ?? null,
    revokedReason: row.revoked_reason ?? null,
    recordVersion: row.record_version,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  });
}

/** app.get_customer_portal_scope_context -- account_name is app.accounts.legal_name only, never an internal-only column. role is null for an account visible only through the legacy customer_account_ref marker (no explicit membership row). */
export const CustomerPortalScopeContextRowSchema = z.object({
  accountId: z.string().uuid(),
  accountName: z.string(),
  role: CustomerPortalMembershipRoleSchema.nullable(),
  isPrimary: z.boolean(),
});
export type CustomerPortalScopeContextRow = z.infer<typeof CustomerPortalScopeContextRowSchema>;

export function parseCustomerPortalScopeContextRow(row: Record<string, unknown>): CustomerPortalScopeContextRow {
  return CustomerPortalScopeContextRowSchema.parse({
    accountId: row.account_id,
    accountName: row.account_name,
    role: row.role ?? null,
    isPrimary: row.is_primary,
  });
}

// --- Cursor pagination ---

/**
 * The (timestamp, id) keyset pair app.list_customer_portal_account_memberships
 * accepts -- never OFFSET. Omit both for the first page; pass the previous
 * page's last row's own updatedAt/id to advance. `.refine()` rejects a
 * half-supplied cursor, mirroring server/contracts/customer-inventory-access/
 * customer-inventory-access.ts's own CustomerInventoryCursorSchema exactly.
 */
export const CustomerPortalMembershipCursorSchema = z
  .object({
    cursorUpdatedAt: z.string().nullable().optional(),
    cursorId: z.string().uuid().nullable().optional(),
  })
  .refine((cursor) => !cursor.cursorId || !!cursor.cursorUpdatedAt, {
    message: "cursorUpdatedAt is required when cursorId is supplied",
    path: ["cursorUpdatedAt"],
  });
export type CustomerPortalMembershipCursor = z.input<typeof CustomerPortalMembershipCursorSchema>;

// --- Mutation input schemas ---

export const InviteCustomerPortalUserInputSchema = z.object({
  tenantId: z.string().uuid(),
  accountId: z.string().uuid(),
  authUserId: z.string().uuid(),
  role: CustomerPortalMembershipRoleSchema,
  actorAuthUserId: z.string().uuid(),
  invitedBy: z.string().min(1),
});
export type InviteCustomerPortalUserInput = z.input<typeof InviteCustomerPortalUserInputSchema>;

export const AcceptCustomerPortalInviteInputSchema = z.object({
  membershipId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  authUserId: z.string().uuid(),
});
export type AcceptCustomerPortalInviteInput = z.input<typeof AcceptCustomerPortalInviteInputSchema>;

export const SetCustomerPortalAccountMembershipStatusInputSchema = z.object({
  membershipId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  toStatus: z.enum(["active", "suspended", "revoked"]),
  reason: z.string().nullable().optional(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type SetCustomerPortalAccountMembershipStatusInput = z.input<typeof SetCustomerPortalAccountMembershipStatusInputSchema>;

export const GrantInitialCustomerPortalAccountAdminInputSchema = z.object({
  tenantId: z.string().uuid(),
  accountId: z.string().uuid(),
  authUserId: z.string().uuid(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type GrantInitialCustomerPortalAccountAdminInput = z.input<typeof GrantInitialCustomerPortalAccountAdminInputSchema>;
