/**
 * Tenant tracking source policy mutation primitives (ATW-226A, CG-S10-ATW-006's own
 * child). Thin, typed wrapper around app.upsert_tenant_tracking_source_policy
 * (supabase/migrations/20260729340000_create_advanced_tms_tracking_entitlement_source_policy.sql).
 *
 * Assigning/changing a tenant's tracking *package* (entitlement/tier/limits) is not
 * this module's concern -- it reuses PLT-121's own generic
 * createConfigDraft/setConfigItems/publishConfigVersion (server/mutations/config.ts)
 * directly, configTypeCode = "feature", scopeLevel = "tenant".
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import {
  UpsertTenantTrackingSourcePolicyInputSchema,
  parseTenantTrackingSourcePolicy,
  type UpsertTenantTrackingSourcePolicyInput,
  type TenantTrackingSourcePolicy,
} from "../contracts/tracking-source-policy/tracking-source-policy.ts";

export type TrackingSourcePolicyMutationRpcClient = Pick<SupabaseClient, "rpc">;

export const TRACKING_SOURCE_POLICY_KNOWN_MUTATION_ERROR_CODES = [
  "insufficient_authority",
  "invalid_source_priority",
  "invalid_freshness_threshold",
  "invalid_accuracy_threshold",
  "invalid_switch_hysteresis",
] as const;
type KnownTrackingSourcePolicyMutationErrorCode = (typeof TRACKING_SOURCE_POLICY_KNOWN_MUTATION_ERROR_CODES)[number];
export type TrackingSourcePolicyMutationErrorCode = KnownTrackingSourcePolicyMutationErrorCode | "mutation_failed" | "invalid_response";

export class TrackingSourcePolicyMutationError extends Error {
  readonly code: TrackingSourcePolicyMutationErrorCode;

  constructor(code: TrackingSourcePolicyMutationErrorCode, message: string) {
    super(message);
    this.name = "TrackingSourcePolicyMutationError";
    this.code = code;
  }
}

function classifyError(message: string): TrackingSourcePolicyMutationErrorCode {
  const prefix = message.split(":")[0]?.trim();
  return (TRACKING_SOURCE_POLICY_KNOWN_MUTATION_ERROR_CODES as readonly string[]).includes(prefix ?? "")
    ? (prefix as KnownTrackingSourcePolicyMutationErrorCode)
    : "mutation_failed";
}

export async function upsertTenantTrackingSourcePolicy(
  client: TrackingSourcePolicyMutationRpcClient,
  input: UpsertTenantTrackingSourcePolicyInput,
): Promise<TenantTrackingSourcePolicy> {
  const parsedInput = UpsertTenantTrackingSourcePolicyInputSchema.parse(input);
  const { data, error } = await client.rpc("upsert_tenant_tracking_source_policy", {
    p_tenant_id: parsedInput.tenantId,
    p_default_source_priority: parsedInput.defaultSourcePriority,
    p_freshness_threshold_seconds: parsedInput.freshnessThresholdSeconds,
    p_accuracy_threshold_meters: parsedInput.accuracyThresholdMeters,
    p_switch_hysteresis_seconds: parsedInput.switchHysteresisSeconds,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new TrackingSourcePolicyMutationError(classifyError(error.message), error.message);
  }
  if (!data || typeof data !== "object") {
    throw new TrackingSourcePolicyMutationError("invalid_response", "upsert_tenant_tracking_source_policy returned no row");
  }
  return parseTenantTrackingSourcePolicy(data as Record<string, unknown>);
}
