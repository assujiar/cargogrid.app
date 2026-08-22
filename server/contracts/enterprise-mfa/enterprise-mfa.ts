/**
 * Enterprise MFA and Session Controls contract (IAE-027, Prompt 355). Mirrors
 * supabase/migrations/20260807100000_create_intelligence_enterprise_mfa_session_controls.sql's
 * app.mfa_tenant_policies/app.mfa_step_up_challenges/app.user_sessions/
 * app.mfa_exceptions shapes and their request/verify/assert/revoke/approve/
 * consume/list RPCs.
 */

import { z } from "zod";

export const MfaTenantPolicySchema = z.object({
  tenantId: z.string().uuid(),
  tenantWideRequired: z.boolean(),
  requiredLayers: z.array(z.string()),
  stepUpMaxAgeMinutes: z.number().int(),
  additionalHighRiskActions: z.array(z.object({ moduleCode: z.string(), action: z.string() })),
  updatedBy: z.string().nullable(),
  updatedAt: z.string(),
});
export type MfaTenantPolicy = z.infer<typeof MfaTenantPolicySchema>;

export function parseMfaTenantPolicy(row: Record<string, unknown>): MfaTenantPolicy {
  return MfaTenantPolicySchema.parse({
    tenantId: row.tenant_id,
    tenantWideRequired: row.tenant_wide_required,
    requiredLayers: row.required_layers,
    stepUpMaxAgeMinutes: row.step_up_max_age_minutes,
    additionalHighRiskActions: row.additional_high_risk_actions,
    updatedBy: row.updated_by,
    updatedAt: row.updated_at,
  });
}

export const MFA_STEP_UP_CHALLENGE_STATUSES = ["pending", "verified", "expired", "failed"] as const;
export const MfaStepUpChallengeStatusSchema = z.enum(MFA_STEP_UP_CHALLENGE_STATUSES);
export type MfaStepUpChallengeStatus = z.infer<typeof MfaStepUpChallengeStatusSchema>;

export const MfaStepUpChallengeSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  authUserId: z.string().uuid(),
  moduleCode: z.string(),
  action: z.string(),
  status: MfaStepUpChallengeStatusSchema,
  challengeIssuedAt: z.string(),
  challengeExpiresAt: z.string(),
  verifiedAt: z.string().nullable(),
});
export type MfaStepUpChallenge = z.infer<typeof MfaStepUpChallengeSchema>;

export function parseMfaStepUpChallenge(row: Record<string, unknown>): MfaStepUpChallenge {
  return MfaStepUpChallengeSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    authUserId: row.auth_user_id,
    moduleCode: row.module_code,
    action: row.action,
    status: row.status,
    challengeIssuedAt: row.challenge_issued_at,
    challengeExpiresAt: row.challenge_expires_at,
    verifiedAt: row.verified_at,
  });
}

export const USER_SESSION_STATUSES = ["active", "revoked"] as const;
export const UserSessionStatusSchema = z.enum(USER_SESSION_STATUSES);
export type UserSessionStatus = z.infer<typeof UserSessionStatusSchema>;

export const UserSessionSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  authUserId: z.string().uuid(),
  deviceLabel: z.string().nullable(),
  ipAddress: z.string().nullable(),
  status: UserSessionStatusSchema,
  createdAt: z.string(),
  lastSeenAt: z.string(),
  revokedAt: z.string().nullable(),
  revokedReason: z.string().nullable(),
  revokedBy: z.string().nullable(),
});
export type UserSession = z.infer<typeof UserSessionSchema>;

export function parseUserSession(row: Record<string, unknown>): UserSession {
  return UserSessionSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    authUserId: row.auth_user_id,
    deviceLabel: row.device_label,
    ipAddress: row.ip_address,
    status: row.status,
    createdAt: row.created_at,
    lastSeenAt: row.last_seen_at,
    revokedAt: row.revoked_at,
    revokedReason: row.revoked_reason,
    revokedBy: row.revoked_by,
  });
}

export const MFA_EXCEPTION_STATUSES = ["pending", "approved", "denied", "expired", "used"] as const;
export const MfaExceptionStatusSchema = z.enum(MFA_EXCEPTION_STATUSES);
export type MfaExceptionStatus = z.infer<typeof MfaExceptionStatusSchema>;

export const MfaExceptionSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  targetAuthUserId: z.string().uuid(),
  reason: z.string(),
  requestedByAuthUserId: z.string().uuid(),
  requestedBy: z.string().nullable(),
  approvedByAuthUserId: z.string().uuid().nullable(),
  approvedBy: z.string().nullable(),
  status: MfaExceptionStatusSchema,
  requestedAt: z.string(),
  decidedAt: z.string().nullable(),
  expiresAt: z.string(),
  usedAt: z.string().nullable(),
});
export type MfaException = z.infer<typeof MfaExceptionSchema>;

export function parseMfaException(row: Record<string, unknown>): MfaException {
  return MfaExceptionSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    targetAuthUserId: row.target_auth_user_id,
    reason: row.reason,
    requestedByAuthUserId: row.requested_by_auth_user_id,
    requestedBy: row.requested_by,
    approvedByAuthUserId: row.approved_by_auth_user_id,
    approvedBy: row.approved_by,
    status: row.status,
    requestedAt: row.requested_at,
    decidedAt: row.decided_at,
    expiresAt: row.expires_at,
    usedAt: row.used_at,
  });
}

export const SetMfaTenantPolicyInputSchema = z.object({
  tenantId: z.string().uuid(),
  tenantWideRequired: z.boolean(),
  requiredLayers: z.array(z.string()),
  stepUpMaxAgeMinutes: z.number().int().min(1).max(1440),
  additionalHighRiskActions: z.array(z.object({ moduleCode: z.string(), action: z.string() })),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type SetMfaTenantPolicyInput = z.input<typeof SetMfaTenantPolicyInputSchema>;

export const RequestMfaStepUpChallengeInputSchema = z.object({
  tenantId: z.string().uuid(),
  moduleCode: z.string().min(1),
  action: z.string().min(1),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type RequestMfaStepUpChallengeInput = z.input<typeof RequestMfaStepUpChallengeInputSchema>;

export const VerifyMfaStepUpChallengeInputSchema = z.object({
  challengeId: z.string().uuid(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type VerifyMfaStepUpChallengeInput = z.input<typeof VerifyMfaStepUpChallengeInputSchema>;

export const RegisterUserSessionInputSchema = z.object({
  tenantId: z.string().uuid(),
  deviceLabel: z.string().nullable(),
  ipAddress: z.string().nullable(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type RegisterUserSessionInput = z.input<typeof RegisterUserSessionInputSchema>;

export const RevokeUserSessionInputSchema = z.object({
  sessionId: z.string().uuid(),
  reason: z.string().nullable(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type RevokeUserSessionInput = z.input<typeof RevokeUserSessionInputSchema>;

export const RevokeAllActorSessionsInputSchema = z.object({
  tenantId: z.string().uuid(),
  targetAuthUserId: z.string().uuid(),
  reason: z.string().min(1),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type RevokeAllActorSessionsInput = z.input<typeof RevokeAllActorSessionsInputSchema>;

export const RequestMfaExceptionInputSchema = z.object({
  tenantId: z.string().uuid(),
  targetAuthUserId: z.string().uuid(),
  reason: z.string().min(1),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type RequestMfaExceptionInput = z.input<typeof RequestMfaExceptionInputSchema>;

export const ApproveMfaExceptionInputSchema = z.object({
  exceptionId: z.string().uuid(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type ApproveMfaExceptionInput = z.input<typeof ApproveMfaExceptionInputSchema>;

export const ConsumeMfaExceptionInputSchema = z.object({
  exceptionId: z.string().uuid(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type ConsumeMfaExceptionInput = z.input<typeof ConsumeMfaExceptionInputSchema>;
