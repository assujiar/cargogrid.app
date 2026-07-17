/**
 * Four-layer identity and access context contract (PLT-108, CG-S6-PLT-005). Mirrors
 * supabase/migrations/20260716100825_create_principal_memberships.sql's
 * app.principal_memberships shape and the app.grant_principal_membership /
 * app.revoke_principal_membership / app.resolve_access_context RPCs. A resolved context
 * is an identity/scope fact, not a permission grant -- RBAC/scope/field/record checks
 * (PLT-111/112/113/114) still gate what the resolved principal may actually do.
 */

import { z } from "zod";

export const PRINCIPAL_LAYERS = ["supreme_admin", "tenant_admin", "org_user", "customer_user"] as const;
export const PrincipalLayerSchema = z.enum(PRINCIPAL_LAYERS);
export type PrincipalLayer = z.infer<typeof PrincipalLayerSchema>;

export const MEMBERSHIP_STATUSES = ["active", "suspended", "revoked"] as const;
export const MembershipStatusSchema = z.enum(MEMBERSHIP_STATUSES);
export type MembershipStatus = z.infer<typeof MembershipStatusSchema>;

export const PrincipalMembershipSchema = z.object({
  id: z.string().uuid(),
  authUserId: z.string().uuid(),
  layer: PrincipalLayerSchema,
  tenantId: z.string().uuid().nullable(),
  customerAccountRef: z.string().nullable(),
  status: MembershipStatusSchema,
  grantedBy: z.string().nullable(),
  grantedAt: z.string(),
  revokedAt: z.string().nullable(),
  revokedReason: z.string().nullable(),
  recordVersion: z.number().int().positive(),
  createdAt: z.string(),
  updatedAt: z.string(),
});
export type PrincipalMembership = z.infer<typeof PrincipalMembershipSchema>;

/** The resolved, unforgeable context returned by app.resolve_access_context -- always exactly one principal, never a partial/ambiguous shape. */
export const AccessContextSchema = z.object({
  membershipId: z.string().uuid(),
  authUserId: z.string().uuid(),
  layer: PrincipalLayerSchema,
  tenantId: z.string().uuid().nullable(),
  customerAccountRef: z.string().nullable(),
  resolvedAt: z.string(),
});
export type AccessContext = z.infer<typeof AccessContextSchema>;

export const ResolveAccessContextInputSchema = z.object({
  authUserId: z.string().uuid(),
  tenantId: z.string().uuid().nullable().default(null),
  customerAccountRef: z.string().nullable().default(null),
});
export type ResolveAccessContextInput = z.input<typeof ResolveAccessContextInputSchema>;

export const GrantPrincipalMembershipInputSchema = z.object({
  authUserId: z.string().uuid(),
  layer: PrincipalLayerSchema,
  tenantId: z.string().uuid().nullable().default(null),
  customerAccountRef: z.string().nullable().default(null),
  grantedBy: z.string().min(1),
});
export type GrantPrincipalMembershipInput = z.input<typeof GrantPrincipalMembershipInputSchema>;

export const RevokePrincipalMembershipInputSchema = z.object({
  membershipId: z.string().uuid(),
  reason: z.string().min(1),
  requestedBy: z.string().min(1),
});
export type RevokePrincipalMembershipInput = z.infer<typeof RevokePrincipalMembershipInputSchema>;

/** Maps a raw app.principal_memberships row (snake_case) to this contract's camelCase shape. */
export function parsePrincipalMembership(row: Record<string, unknown>): PrincipalMembership {
  return PrincipalMembershipSchema.parse({
    id: row.id,
    authUserId: row.auth_user_id,
    layer: row.layer,
    tenantId: row.tenant_id,
    customerAccountRef: row.customer_account_ref,
    status: row.status,
    grantedBy: row.granted_by,
    grantedAt: row.granted_at,
    revokedAt: row.revoked_at,
    revokedReason: row.revoked_reason,
    recordVersion: row.record_version,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  });
}

/** Maps a raw app.access_context composite (snake_case) to this contract's camelCase shape. */
export function parseAccessContext(row: Record<string, unknown>): AccessContext {
  return AccessContextSchema.parse({
    membershipId: row.membership_id,
    authUserId: row.auth_user_id,
    layer: row.layer,
    tenantId: row.tenant_id,
    customerAccountRef: row.customer_account_ref,
    resolvedAt: row.resolved_at,
  });
}
