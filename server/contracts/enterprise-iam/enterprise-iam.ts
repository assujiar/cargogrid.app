/**
 * Enterprise IAM contract (IAE-026, Prompt 354). Mirrors
 * supabase/migrations/20260807000000_create_intelligence_enterprise_iam_sso.sql's
 * app.iam_domain_claims/app.iam_sso_login_attempts/app.iam_scim_user_links/
 * app.iam_scim_provisioning_events shapes and their request/verify/activate/
 * disable/resolve/provision/list RPCs. Connection CRUD itself reuses
 * server/contracts/integration-hub/integration-hub.ts's own IntegrationConnection
 * type unmodified (this capability's own connections are just two more
 * adapter_code values -- enterprise_sso_oidc/enterprise_sso_saml -- on the
 * SAME app.integration_connections table, not a parallel shape).
 */

import { z } from "zod";

export const ENTERPRISE_SSO_ADAPTER_CODES = ["enterprise_sso_oidc", "enterprise_sso_saml"] as const;
export const EnterpriseSsoAdapterCodeSchema = z.enum(ENTERPRISE_SSO_ADAPTER_CODES);
export type EnterpriseSsoAdapterCode = z.infer<typeof EnterpriseSsoAdapterCodeSchema>;

export const IAM_DOMAIN_CLAIM_STATUSES = ["pending_verification", "verified", "active", "disabled", "rejected", "expired"] as const;
export const IamDomainClaimStatusSchema = z.enum(IAM_DOMAIN_CLAIM_STATUSES);
export type IamDomainClaimStatus = z.infer<typeof IamDomainClaimStatusSchema>;

export const IamDomainClaimSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  connectionId: z.string().uuid(),
  emailDomain: z.string(),
  status: IamDomainClaimStatusSchema,
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
  createdAt: z.string(),
  updatedAt: z.string(),
});
export type IamDomainClaim = z.infer<typeof IamDomainClaimSchema>;

export function parseIamDomainClaim(row: Record<string, unknown>): IamDomainClaim {
  return IamDomainClaimSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    connectionId: row.connection_id,
    emailDomain: row.email_domain,
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
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  });
}

export const IAM_SSO_LOGIN_ATTEMPT_OUTCOMES = [
  "matched",
  "no_domain_claim",
  "no_user_match",
  "ambiguous_match",
  "deprovisioned",
  "connection_not_active",
  "invalid_email_claim",
] as const;
export const IamSsoLoginAttemptOutcomeSchema = z.enum(IAM_SSO_LOGIN_ATTEMPT_OUTCOMES);
export type IamSsoLoginAttemptOutcome = z.infer<typeof IamSsoLoginAttemptOutcomeSchema>;

export const IamSsoLoginAttemptSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  connectionId: z.string().uuid(),
  domainClaimId: z.string().uuid().nullable(),
  subjectClaim: z.string(),
  emailClaim: z.string().nullable(),
  resolvedAuthUserId: z.string().uuid().nullable(),
  outcome: IamSsoLoginAttemptOutcomeSchema,
  resolvedByAuthUserId: z.string().uuid().nullable(),
  occurredAt: z.string(),
});
export type IamSsoLoginAttempt = z.infer<typeof IamSsoLoginAttemptSchema>;

export function parseIamSsoLoginAttempt(row: Record<string, unknown>): IamSsoLoginAttempt {
  return IamSsoLoginAttemptSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    connectionId: row.connection_id,
    domainClaimId: row.domain_claim_id,
    subjectClaim: row.subject_claim,
    emailClaim: row.email_claim,
    resolvedAuthUserId: row.resolved_auth_user_id,
    outcome: row.outcome,
    resolvedByAuthUserId: row.resolved_by_auth_user_id,
    occurredAt: row.occurred_at,
  });
}

export const IAM_SCIM_OPERATIONS = ["create", "update", "deactivate", "reactivate"] as const;
export const IamScimOperationSchema = z.enum(IAM_SCIM_OPERATIONS);
export type IamScimOperation = z.infer<typeof IamScimOperationSchema>;

export const IAM_SCIM_PROVISIONING_OUTCOMES = ["applied", "dry_run_preview", "rejected"] as const;
export const IamScimProvisioningOutcomeSchema = z.enum(IAM_SCIM_PROVISIONING_OUTCOMES);
export type IamScimProvisioningOutcome = z.infer<typeof IamScimProvisioningOutcomeSchema>;

export const IamScimProvisioningEventSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  scimLinkId: z.string().uuid(),
  apiKeyId: z.string().uuid().nullable(),
  operation: IamScimOperationSchema,
  isDryRun: z.boolean(),
  outcome: IamScimProvisioningOutcomeSchema,
  outcomeReason: z.string().nullable(),
  occurredAt: z.string(),
});
export type IamScimProvisioningEvent = z.infer<typeof IamScimProvisioningEventSchema>;

export function parseIamScimProvisioningEvent(row: Record<string, unknown>): IamScimProvisioningEvent {
  return IamScimProvisioningEventSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    scimLinkId: row.scim_link_id,
    apiKeyId: row.api_key_id,
    operation: row.operation,
    isDryRun: row.is_dry_run,
    outcome: row.outcome,
    outcomeReason: row.outcome_reason,
    occurredAt: row.occurred_at,
  });
}

export const RequestEnterpriseSsoDomainClaimInputSchema = z.object({
  tenantId: z.string().uuid(),
  connectionId: z.string().uuid(),
  emailDomain: z.string().min(1),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type RequestEnterpriseSsoDomainClaimInput = z.input<typeof RequestEnterpriseSsoDomainClaimInputSchema>;

export const VerifyEnterpriseSsoDomainClaimInputSchema = z.object({
  claimId: z.string().uuid(),
  observedTxtValue: z.string().min(1),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type VerifyEnterpriseSsoDomainClaimInput = z.input<typeof VerifyEnterpriseSsoDomainClaimInputSchema>;

export const ActivateEnterpriseSsoDomainClaimInputSchema = z.object({
  claimId: z.string().uuid(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type ActivateEnterpriseSsoDomainClaimInput = z.input<typeof ActivateEnterpriseSsoDomainClaimInputSchema>;

export const DisableEnterpriseSsoDomainClaimInputSchema = z.object({
  claimId: z.string().uuid(),
  reason: z.string().min(1),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type DisableEnterpriseSsoDomainClaimInput = z.input<typeof DisableEnterpriseSsoDomainClaimInputSchema>;

export const ResolveEnterpriseSsoClaimsInputSchema = z.object({
  connectionId: z.string().uuid(),
  subjectClaim: z.string().min(1),
  rawEmailClaim: z.string().nullable(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type ResolveEnterpriseSsoClaimsInput = z.input<typeof ResolveEnterpriseSsoClaimsInputSchema>;

export const ActivateEnterpriseIdpConnectionInputSchema = z.object({
  connectionId: z.string().uuid(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
  clientIp: z.string().nullable().default(null),
});
export type ActivateEnterpriseIdpConnectionInput = z.input<typeof ActivateEnterpriseIdpConnectionInputSchema>;

export const ProvisionScimIdentityInputSchema = z.object({
  tenantId: z.string().uuid(),
  apiKeyId: z.string().uuid().nullable(),
  externalId: z.string().min(1),
  rawEmail: z.string().nullable(),
  displayName: z.string().nullable(),
  operation: IamScimOperationSchema,
  isDryRun: z.boolean(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type ProvisionScimIdentityInput = z.input<typeof ProvisionScimIdentityInputSchema>;

export const EnterpriseIdpByEmailDomainSchema = z.object({
  connectionId: z.string().uuid(),
  protocol: EnterpriseSsoAdapterCodeSchema,
  displayName: z.string(),
});
export type EnterpriseIdpByEmailDomain = z.infer<typeof EnterpriseIdpByEmailDomainSchema>;

export function parseEnterpriseIdpByEmailDomain(row: Record<string, unknown>): EnterpriseIdpByEmailDomain {
  return EnterpriseIdpByEmailDomainSchema.parse({
    connectionId: row.connection_id,
    protocol: row.protocol,
    displayName: row.display_name,
  });
}
