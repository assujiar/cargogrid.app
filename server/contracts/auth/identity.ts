/**
 * Auth identity linkage contract (PLT-107, CG-S6-PLT-004). Mirrors
 * supabase/migrations/20260716095343_link_auth_identities.sql's app.tenant_user_identities
 * shape and the app.link_auth_identity/app.revoke_auth_identity RPCs. Authentication
 * (this contract) proves identity only -- entitlement/RBAC/RLS (PLT-106/111/112/113)
 * determine access (Prompt 107 §24).
 */

import { z } from "zod";

export const IDENTITY_LINK_STATUSES = ["invited", "active", "revoked"] as const;
export const IdentityLinkStatusSchema = z.enum(IDENTITY_LINK_STATUSES);
export type IdentityLinkStatus = z.infer<typeof IdentityLinkStatusSchema>;

export const TenantUserIdentitySchema = z.object({
  id: z.string().uuid(),
  authUserId: z.string().uuid(),
  tenantId: z.string().uuid(),
  status: IdentityLinkStatusSchema,
  invitedBy: z.string().nullable(),
  invitedAt: z.string(),
  activatedAt: z.string().nullable(),
  revokedAt: z.string().nullable(),
  revokedReason: z.string().nullable(),
  mfaEnrolled: z.boolean(),
  recordVersion: z.number().int().positive(),
  createdAt: z.string(),
  updatedAt: z.string(),
});
export type TenantUserIdentity = z.infer<typeof TenantUserIdentitySchema>;

export const LinkAuthIdentityInputSchema = z.object({
  authUserId: z.string().uuid(),
  tenantId: z.string().uuid(),
  invitedBy: z.string().min(1),
  status: z.enum(["invited", "active"]).default("invited"),
});
// z.input (not z.infer/output) so callers may omit `status` -- the schema's own default
// fills it in during .parse(), but the *pre-parse* type must keep it optional.
export type LinkAuthIdentityInput = z.input<typeof LinkAuthIdentityInputSchema>;

export const RevokeAuthIdentityInputSchema = z.object({
  authUserId: z.string().uuid(),
  tenantId: z.string().uuid(),
  reason: z.string().min(1),
  requestedBy: z.string().min(1),
});
export type RevokeAuthIdentityInput = z.infer<typeof RevokeAuthIdentityInputSchema>;

/** Maps a raw app.tenant_user_identities row (snake_case) to this contract's camelCase shape. */
export function parseTenantUserIdentity(row: Record<string, unknown>): TenantUserIdentity {
  return TenantUserIdentitySchema.parse({
    id: row.id,
    authUserId: row.auth_user_id,
    tenantId: row.tenant_id,
    status: row.status,
    invitedBy: row.invited_by,
    invitedAt: row.invited_at,
    activatedAt: row.activated_at,
    revokedAt: row.revoked_at,
    revokedReason: row.revoked_reason,
    mfaEnrolled: row.mfa_enrolled,
    recordVersion: row.record_version,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  });
}
