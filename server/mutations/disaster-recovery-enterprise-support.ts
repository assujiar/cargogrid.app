/**
 * Disaster Recovery and Enterprise Support mutation primitives (IAE-035,
 * Prompt 363). Thin, typed wrappers around app.record_dr_restore_test /
 * app.set_support_entitlement / app.verify_onboarding_checklist_item
 * (supabase/migrations/20260808300000_create_intelligence_disaster_recovery_enterprise_support.sql).
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import {
  RecordDrRestoreTestInputSchema,
  SetSupportEntitlementInputSchema,
  VerifyOnboardingChecklistItemInputSchema,
  parseDrRestoreTest,
  parseSupportEntitlement,
  parseEnterpriseOnboardingChecklist,
  type RecordDrRestoreTestInput,
  type SetSupportEntitlementInput,
  type VerifyOnboardingChecklistItemInput,
  type DrRestoreTest,
  type SupportEntitlement,
  type EnterpriseOnboardingChecklist,
} from "../contracts/disaster-recovery-enterprise-support/disaster-recovery-enterprise-support.ts";

export type DisasterRecoveryEnterpriseSupportMutationRpcClient = Pick<SupabaseClient, "rpc">;

export const DISASTER_RECOVERY_ENTERPRISE_SUPPORT_KNOWN_MUTATION_ERROR_CODES = [
  "insufficient_authority",
  "dr_test_invalid_deployment_type",
  "dr_test_invalid_component_scope",
  "dr_test_invalid_status",
  "dr_test_deployment_mismatch",
  "support_entitlement_invalid_tier",
  "support_entitlement_24_7_requires_escalation",
  "onboarding_invalid_item",
] as const;
type KnownDisasterRecoveryEnterpriseSupportMutationErrorCode = (typeof DISASTER_RECOVERY_ENTERPRISE_SUPPORT_KNOWN_MUTATION_ERROR_CODES)[number];
export type DisasterRecoveryEnterpriseSupportMutationErrorCode = KnownDisasterRecoveryEnterpriseSupportMutationErrorCode | "mutation_failed" | "invalid_response";

export class DisasterRecoveryEnterpriseSupportMutationError extends Error {
  readonly code: DisasterRecoveryEnterpriseSupportMutationErrorCode;

  constructor(code: DisasterRecoveryEnterpriseSupportMutationErrorCode, message: string) {
    super(message);
    this.name = "DisasterRecoveryEnterpriseSupportMutationError";
    this.code = code;
  }
}

function classifyError(message: string): DisasterRecoveryEnterpriseSupportMutationErrorCode {
  const prefix = message.split(":")[0]?.trim();
  return (DISASTER_RECOVERY_ENTERPRISE_SUPPORT_KNOWN_MUTATION_ERROR_CODES as readonly string[]).includes(prefix ?? "")
    ? (prefix as KnownDisasterRecoveryEnterpriseSupportMutationErrorCode)
    : "mutation_failed";
}

/** Authority: SUP:Configure (tenant-scoped) or Supreme Admin (platform-wide, tenantId null). A dedicated-scoped test is rejected unless the tenant genuinely has an active dedicated deployment (IAE-032). */
export async function recordDrRestoreTest(client: DisasterRecoveryEnterpriseSupportMutationRpcClient, input: RecordDrRestoreTestInput): Promise<DrRestoreTest> {
  const parsedInput = RecordDrRestoreTestInputSchema.parse(input);
  const { data, error } = await client.rpc("record_dr_restore_test", {
    p_tenant_id: parsedInput.tenantId,
    p_deployment_type: parsedInput.deploymentType,
    p_component_scope: parsedInput.componentScope,
    p_status: parsedInput.status,
    p_observed_rpo_minutes: parsedInput.observedRpoMinutes,
    p_observed_rto_minutes: parsedInput.observedRtoMinutes,
    p_failure_reason: parsedInput.failureReason,
    p_recovery_steps: parsedInput.recoverySteps,
    p_retest_scheduled_at: parsedInput.retestScheduledAt,
    p_owner_auth_user_id: parsedInput.ownerAuthUserId,
    p_owner_label: parsedInput.ownerLabel,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new DisasterRecoveryEnterpriseSupportMutationError(classifyError(error.message), error.message);
  }
  if (!data || typeof data !== "object") {
    throw new DisasterRecoveryEnterpriseSupportMutationError("invalid_response", "record_dr_restore_test returned no row");
  }
  return parseDrRestoreTest(data as Record<string, unknown>);
}

/** Authority: SUP:Configure. An enterprise_24_7 tier requires a real escalationContactEmail and a positive p1ResponseMinutes. */
export async function setSupportEntitlement(client: DisasterRecoveryEnterpriseSupportMutationRpcClient, input: SetSupportEntitlementInput): Promise<SupportEntitlement> {
  const parsedInput = SetSupportEntitlementInputSchema.parse(input);
  const { data, error } = await client.rpc("set_support_entitlement", {
    p_tenant_id: parsedInput.tenantId,
    p_tier: parsedInput.tier,
    p_contract_reference: parsedInput.contractReference,
    p_escalation_contact_name: parsedInput.escalationContactName,
    p_escalation_contact_email: parsedInput.escalationContactEmail,
    p_p1_response_minutes: parsedInput.p1ResponseMinutes,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new DisasterRecoveryEnterpriseSupportMutationError(classifyError(error.message), error.message);
  }
  if (!data || typeof data !== "object") {
    throw new DisasterRecoveryEnterpriseSupportMutationError("invalid_response", "set_support_entitlement returned no row");
  }
  return parseSupportEntitlement(data as Record<string, unknown>);
}

/** Authority: SUP:Configure for the five auto-verified items; SUP:Approve for hypercarePlanAcknowledged (the final human sign-off). Five items are computed live from real data; humanAcknowledged is consulted ONLY for hypercarePlanAcknowledged. */
export async function verifyOnboardingChecklistItem(client: DisasterRecoveryEnterpriseSupportMutationRpcClient, input: VerifyOnboardingChecklistItemInput): Promise<EnterpriseOnboardingChecklist> {
  const parsedInput = VerifyOnboardingChecklistItemInputSchema.parse(input);
  const { data, error } = await client.rpc("verify_onboarding_checklist_item", {
    p_tenant_id: parsedInput.tenantId,
    p_item: parsedInput.item,
    p_human_acknowledged: parsedInput.humanAcknowledged,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new DisasterRecoveryEnterpriseSupportMutationError(classifyError(error.message), error.message);
  }
  if (!data || typeof data !== "object") {
    throw new DisasterRecoveryEnterpriseSupportMutationError("invalid_response", "verify_onboarding_checklist_item returned no row");
  }
  return parseEnterpriseOnboardingChecklist(data as Record<string, unknown>);
}
