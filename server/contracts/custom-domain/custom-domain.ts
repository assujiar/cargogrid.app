/**
 * Tenant custom-domain contract (PLT-118, CG-S6-PLT-015). Mirrors
 * supabase/migrations/20260717103015_create_custom_domain.sql's
 * app.tenant_custom_domains shape and the app.request_tenant_domain /
 * app.verify_tenant_domain / app.activate_tenant_domain / app.disable_tenant_domain /
 * app.reject_tenant_domain / app.list_tenant_domains / app.resolve_tenant_by_domain RPCs.
 */

import { z } from "zod";

export const DOMAIN_STATUSES = ["pending_verification", "verified", "active", "disabled", "rejected", "expired"] as const;
export const DomainStatusSchema = z.enum(DOMAIN_STATUSES);
export type DomainStatus = z.infer<typeof DomainStatusSchema>;

const HOSTNAME_PATTERN = /^([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]{2,63}$/;

/** Structural hostname shape only -- callers should still normalize (lowercase, strip a trailing dot) before submitting. */
export const HostnameSchema = z.string().max(253).regex(HOSTNAME_PATTERN, "must be a well-formed lowercase ASCII domain hostname");

export const TenantCustomDomainSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  hostname: z.string(),
  status: DomainStatusSchema,
  verificationMethod: z.literal("dns_txt"),
  verificationToken: z.string(),
  verificationChallengeHost: z.string(),
  requestedBy: z.string().nullable(),
  verifiedAt: z.string().nullable(),
  verifiedBy: z.string().nullable(),
  activatedAt: z.string().nullable(),
  activatedBy: z.string().nullable(),
  disabledAt: z.string().nullable(),
  disabledBy: z.string().nullable(),
  disabledReason: z.string().nullable(),
  rejectedAt: z.string().nullable(),
  rejectedBy: z.string().nullable(),
  rejectedReason: z.string().nullable(),
  expiresAt: z.string(),
  recordVersion: z.number().int().positive(),
  createdAt: z.string(),
  updatedAt: z.string(),
});
export type TenantCustomDomain = z.infer<typeof TenantCustomDomainSchema>;

export const RequestTenantDomainInputSchema = z.object({
  tenantId: z.string().uuid(),
  actorAuthUserId: z.string().uuid(),
  hostname: z.string().min(1),
  requestedBy: z.string().min(1),
});
export type RequestTenantDomainInput = z.infer<typeof RequestTenantDomainInputSchema>;

export const VerifyTenantDomainInputSchema = z.object({
  domainId: z.string().uuid(),
  actorAuthUserId: z.string().uuid(),
  observedTxtValue: z.string().min(1),
  verifiedBy: z.string().min(1),
});
export type VerifyTenantDomainInput = z.infer<typeof VerifyTenantDomainInputSchema>;

export const ActivateTenantDomainInputSchema = z.object({
  domainId: z.string().uuid(),
  actorAuthUserId: z.string().uuid(),
  activatedBy: z.string().min(1),
});
export type ActivateTenantDomainInput = z.infer<typeof ActivateTenantDomainInputSchema>;

export const DisableTenantDomainInputSchema = z.object({
  domainId: z.string().uuid(),
  actorAuthUserId: z.string().uuid(),
  reason: z.string().min(1),
  disabledBy: z.string().min(1),
});
export type DisableTenantDomainInput = z.infer<typeof DisableTenantDomainInputSchema>;

export const RejectTenantDomainInputSchema = z.object({
  domainId: z.string().uuid(),
  actorAuthUserId: z.string().uuid(),
  reason: z.string().min(1),
  rejectedBy: z.string().min(1),
});
export type RejectTenantDomainInput = z.infer<typeof RejectTenantDomainInputSchema>;

export const ListTenantDomainsInputSchema = z.object({
  tenantId: z.string().uuid(),
  actorAuthUserId: z.string().uuid(),
});
export type ListTenantDomainsInput = z.infer<typeof ListTenantDomainsInputSchema>;

export const ResolveTenantByDomainInputSchema = z.object({
  hostname: z.string().min(1),
});
export type ResolveTenantByDomainInput = z.infer<typeof ResolveTenantByDomainInputSchema>;

export const ResolvedTenantDomainSchema = z.object({
  domainId: z.string().uuid(),
  resolvedTenantId: z.string().uuid(),
  tenantCanonicalStatus: z.string(),
});
export type ResolvedTenantDomain = z.infer<typeof ResolvedTenantDomainSchema>;

/** Maps a raw app.tenant_custom_domains row (snake_case) to this contract's camelCase shape. */
export function parseTenantCustomDomain(row: Record<string, unknown>): TenantCustomDomain {
  return TenantCustomDomainSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    hostname: row.hostname,
    status: row.status,
    verificationMethod: row.verification_method,
    verificationToken: row.verification_token,
    verificationChallengeHost: row.verification_challenge_host,
    requestedBy: row.requested_by,
    verifiedAt: row.verified_at,
    verifiedBy: row.verified_by,
    activatedAt: row.activated_at,
    activatedBy: row.activated_by,
    disabledAt: row.disabled_at,
    disabledBy: row.disabled_by,
    disabledReason: row.disabled_reason,
    rejectedAt: row.rejected_at,
    rejectedBy: row.rejected_by,
    rejectedReason: row.rejected_reason,
    expiresAt: row.expires_at,
    recordVersion: row.record_version,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  });
}

/** Maps a raw app.resolve_tenant_by_domain() row (snake_case) to this contract's camelCase shape. */
export function parseResolvedTenantDomain(row: Record<string, unknown>): ResolvedTenantDomain {
  return ResolvedTenantDomainSchema.parse({
    domainId: row.domain_id,
    resolvedTenantId: row.resolved_tenant_id,
    tenantCanonicalStatus: row.tenant_canonical_status,
  });
}
