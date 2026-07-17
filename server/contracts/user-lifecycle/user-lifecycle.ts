/**
 * User lifecycle contract (PLT-110, CG-S6-PLT-007). Mirrors
 * supabase/migrations/20260716102620_create_users.sql's app.users shape and the
 * app.invite_user / app.resend_invitation / app.transition_user_status /
 * app.reassign_user_org_unit RPCs. A user profile is layered on top of PLT-107's identity
 * linkage and PLT-108's principal memberships, not a replacement for either.
 */

import { z } from "zod";

export const USER_STATUSES = ["invited", "active", "suspended", "revoked"] as const;
export const UserStatusSchema = z.enum(USER_STATUSES);
export type UserStatus = z.infer<typeof UserStatusSchema>;

export const UserSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  authUserId: z.string().uuid(),
  email: z.string().email(),
  displayName: z.string(),
  status: UserStatusSchema,
  orgUnitId: z.string().uuid().nullable(),
  invitedBy: z.string().nullable(),
  invitedAt: z.string(),
  inviteExpiresAt: z.string(),
  activatedAt: z.string().nullable(),
  suspendedAt: z.string().nullable(),
  suspendedReason: z.string().nullable(),
  revokedAt: z.string().nullable(),
  revokedReason: z.string().nullable(),
  recordVersion: z.number().int().positive(),
  createdAt: z.string(),
  updatedAt: z.string(),
});
export type User = z.infer<typeof UserSchema>;

export const InviteUserInputSchema = z.object({
  tenantId: z.string().uuid(),
  authUserId: z.string().uuid(),
  email: z.string().email(),
  displayName: z.string().min(1),
  orgUnitId: z.string().uuid().nullable().default(null),
  invitedBy: z.string().min(1),
  inviteExpiresAt: z.string(),
});
export type InviteUserInput = z.input<typeof InviteUserInputSchema>;

export const ResendInvitationInputSchema = z.object({
  id: z.string().uuid(),
  newExpiresAt: z.string(),
  requestedBy: z.string().min(1),
});
export type ResendInvitationInput = z.infer<typeof ResendInvitationInputSchema>;

export const TransitionUserStatusInputSchema = z.object({
  id: z.string().uuid(),
  newStatus: UserStatusSchema,
  reason: z.string().min(1),
  requestedBy: z.string().min(1),
});
export type TransitionUserStatusInput = z.infer<typeof TransitionUserStatusInputSchema>;

export const ReassignUserOrgUnitInputSchema = z.object({
  id: z.string().uuid(),
  newOrgUnitId: z.string().uuid().nullable(),
  expectedVersion: z.number().int().positive(),
  requestedBy: z.string().min(1),
});
export type ReassignUserOrgUnitInput = z.infer<typeof ReassignUserOrgUnitInputSchema>;

/** Maps a raw app.users row (snake_case) to this contract's camelCase shape. */
export function parseUser(row: Record<string, unknown>): User {
  return UserSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    authUserId: row.auth_user_id,
    email: row.email,
    displayName: row.display_name,
    status: row.status,
    orgUnitId: row.org_unit_id,
    invitedBy: row.invited_by,
    invitedAt: row.invited_at,
    inviteExpiresAt: row.invite_expires_at,
    activatedAt: row.activated_at,
    suspendedAt: row.suspended_at,
    suspendedReason: row.suspended_reason,
    revokedAt: row.revoked_at,
    revokedReason: row.revoked_reason,
    recordVersion: row.record_version,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  });
}
