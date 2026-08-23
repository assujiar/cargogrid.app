/**
 * Disaster Recovery and Enterprise Support contract (IAE-035, Prompt 363).
 * Mirrors
 * supabase/migrations/20260808300000_create_intelligence_disaster_recovery_enterprise_support.sql's
 * app.dr_restore_tests / app.support_entitlements /
 * app.enterprise_onboarding_checklists shapes, and their record/set/verify/
 * read RPCs.
 */

import { z } from "zod";

export const DR_DEPLOYMENT_TYPES = ["shared", "dedicated"] as const;
export const DrDeploymentTypeSchema = z.enum(DR_DEPLOYMENT_TYPES);
export type DrDeploymentType = z.infer<typeof DrDeploymentTypeSchema>;

export const DR_COMPONENT_SCOPES = ["database", "secrets", "backup", "observability", "jobs_integrations"] as const;
export const DrComponentScopeSchema = z.enum(DR_COMPONENT_SCOPES);
export type DrComponentScope = z.infer<typeof DrComponentScopeSchema>;

export const DR_TEST_STATUSES = ["passed", "failed"] as const;
export const DrTestStatusSchema = z.enum(DR_TEST_STATUSES);
export type DrTestStatus = z.infer<typeof DrTestStatusSchema>;

export const SUPPORT_ENTITLEMENT_TIERS = ["standard", "enterprise_24_7"] as const;
export const SupportEntitlementTierSchema = z.enum(SUPPORT_ENTITLEMENT_TIERS);
export type SupportEntitlementTier = z.infer<typeof SupportEntitlementTierSchema>;

export const ONBOARDING_CHECKLIST_ITEMS = [
  "sso_verified", "api_verified", "integrations_verified", "dr_evidence_verified", "support_entitlement_verified", "hypercare_plan_acknowledged",
] as const;
export const OnboardingChecklistItemSchema = z.enum(ONBOARDING_CHECKLIST_ITEMS);
export type OnboardingChecklistItem = z.infer<typeof OnboardingChecklistItemSchema>;

export const ONBOARDING_CHECKLIST_STATUSES = ["in_progress", "ready_for_production"] as const;
export const OnboardingChecklistStatusSchema = z.enum(ONBOARDING_CHECKLIST_STATUSES);
export type OnboardingChecklistStatus = z.infer<typeof OnboardingChecklistStatusSchema>;

export const DrRestoreTestSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid().nullable(),
  deploymentType: DrDeploymentTypeSchema,
  componentScope: DrComponentScopeSchema,
  status: DrTestStatusSchema,
  observedRpoMinutes: z.number().nullable(),
  observedRtoMinutes: z.number().nullable(),
  failureReason: z.string().nullable(),
  recoverySteps: z.string().nullable(),
  retestScheduledAt: z.string().nullable(),
  ownerAuthUserId: z.string().uuid().nullable(),
  ownerLabel: z.string().nullable(),
  testedByAuthUserId: z.string().uuid().nullable(),
  testedBy: z.string().nullable(),
  testedAt: z.string(),
  createdAt: z.string(),
});
export type DrRestoreTest = z.infer<typeof DrRestoreTestSchema>;

export function parseDrRestoreTest(row: Record<string, unknown>): DrRestoreTest {
  return DrRestoreTestSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    deploymentType: row.deployment_type,
    componentScope: row.component_scope,
    status: row.status,
    observedRpoMinutes: row.observed_rpo_minutes,
    observedRtoMinutes: row.observed_rto_minutes,
    failureReason: row.failure_reason,
    recoverySteps: row.recovery_steps,
    retestScheduledAt: row.retest_scheduled_at,
    ownerAuthUserId: row.owner_auth_user_id,
    ownerLabel: row.owner_label,
    testedByAuthUserId: row.tested_by_auth_user_id,
    testedBy: row.tested_by,
    testedAt: row.tested_at,
    createdAt: row.created_at,
  });
}

export const SupportEntitlementSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  tier: SupportEntitlementTierSchema,
  contractReference: z.string().nullable(),
  escalationContactName: z.string().nullable(),
  escalationContactEmail: z.string().nullable(),
  p1ResponseMinutes: z.number().int().nullable(),
  createdBy: z.string().nullable(),
  createdAt: z.string(),
  updatedAt: z.string(),
  recordVersion: z.number().int(),
});
export type SupportEntitlement = z.infer<typeof SupportEntitlementSchema>;

export function parseSupportEntitlement(row: Record<string, unknown>): SupportEntitlement {
  return SupportEntitlementSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    tier: row.tier,
    contractReference: row.contract_reference,
    escalationContactName: row.escalation_contact_name,
    escalationContactEmail: row.escalation_contact_email,
    p1ResponseMinutes: row.p1_response_minutes,
    createdBy: row.created_by,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
    recordVersion: row.record_version,
  });
}

export const EnterpriseOnboardingChecklistSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  ssoVerified: z.boolean(),
  ssoVerifiedAt: z.string().nullable(),
  apiVerified: z.boolean(),
  apiVerifiedAt: z.string().nullable(),
  integrationsVerified: z.boolean(),
  integrationsVerifiedAt: z.string().nullable(),
  drEvidenceVerified: z.boolean(),
  drEvidenceVerifiedAt: z.string().nullable(),
  supportEntitlementVerified: z.boolean(),
  supportEntitlementVerifiedAt: z.string().nullable(),
  hypercarePlanAcknowledged: z.boolean(),
  hypercarePlanAcknowledgedAt: z.string().nullable(),
  hypercarePlanAcknowledgedByAuthUserId: z.string().uuid().nullable(),
  hypercarePlanAcknowledgedBy: z.string().nullable(),
  status: OnboardingChecklistStatusSchema,
  createdAt: z.string(),
  updatedAt: z.string(),
  recordVersion: z.number().int(),
});
export type EnterpriseOnboardingChecklist = z.infer<typeof EnterpriseOnboardingChecklistSchema>;

export function parseEnterpriseOnboardingChecklist(row: Record<string, unknown>): EnterpriseOnboardingChecklist {
  return EnterpriseOnboardingChecklistSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    ssoVerified: row.sso_verified,
    ssoVerifiedAt: row.sso_verified_at,
    apiVerified: row.api_verified,
    apiVerifiedAt: row.api_verified_at,
    integrationsVerified: row.integrations_verified,
    integrationsVerifiedAt: row.integrations_verified_at,
    drEvidenceVerified: row.dr_evidence_verified,
    drEvidenceVerifiedAt: row.dr_evidence_verified_at,
    supportEntitlementVerified: row.support_entitlement_verified,
    supportEntitlementVerifiedAt: row.support_entitlement_verified_at,
    hypercarePlanAcknowledged: row.hypercare_plan_acknowledged,
    hypercarePlanAcknowledgedAt: row.hypercare_plan_acknowledged_at,
    hypercarePlanAcknowledgedByAuthUserId: row.hypercare_plan_acknowledged_by_auth_user_id,
    hypercarePlanAcknowledgedBy: row.hypercare_plan_acknowledged_by,
    status: row.status,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
    recordVersion: row.record_version,
  });
}

export const RecordDrRestoreTestInputSchema = z.object({
  tenantId: z.string().uuid().nullable(),
  deploymentType: DrDeploymentTypeSchema,
  componentScope: DrComponentScopeSchema,
  status: DrTestStatusSchema,
  observedRpoMinutes: z.number().nullable(),
  observedRtoMinutes: z.number().nullable(),
  failureReason: z.string().nullable(),
  recoverySteps: z.string().nullable(),
  retestScheduledAt: z.string().nullable(),
  ownerAuthUserId: z.string().uuid().nullable(),
  ownerLabel: z.string().nullable(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type RecordDrRestoreTestInput = z.input<typeof RecordDrRestoreTestInputSchema>;

export const SetSupportEntitlementInputSchema = z.object({
  tenantId: z.string().uuid(),
  tier: SupportEntitlementTierSchema,
  contractReference: z.string().nullable(),
  escalationContactName: z.string().nullable(),
  escalationContactEmail: z.string().nullable(),
  p1ResponseMinutes: z.number().int().nullable(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type SetSupportEntitlementInput = z.input<typeof SetSupportEntitlementInputSchema>;

export const VerifyOnboardingChecklistItemInputSchema = z.object({
  tenantId: z.string().uuid(),
  item: OnboardingChecklistItemSchema,
  humanAcknowledged: z.boolean().nullable(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type VerifyOnboardingChecklistItemInput = z.input<typeof VerifyOnboardingChecklistItemInputSchema>;
