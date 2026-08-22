/**
 * Dedicated Enterprise Deployment mutation primitives (IAE-032, Prompt 360).
 * Thin, typed wrappers around app.request_dedicated_deployment_qualification /
 * app.approve_dedicated_deployment_qualification /
 * app.set_deployment_provisioning_status / app.set_deployment_environment_ref
 * (supabase/migrations/20260808000000_create_intelligence_dedicated_enterprise_deployment.sql).
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import {
  RequestDedicatedDeploymentQualificationInputSchema,
  ApproveDedicatedDeploymentQualificationInputSchema,
  SetDeploymentProvisioningStatusInputSchema,
  SetDeploymentEnvironmentRefInputSchema,
  parseTenantDeploymentRecord,
  parseTenantDeploymentEnvironmentRef,
  type RequestDedicatedDeploymentQualificationInput,
  type ApproveDedicatedDeploymentQualificationInput,
  type SetDeploymentProvisioningStatusInput,
  type SetDeploymentEnvironmentRefInput,
  type TenantDeploymentRecord,
  type TenantDeploymentEnvironmentRef,
} from "../contracts/dedicated-enterprise-deployment/dedicated-enterprise-deployment.ts";

export type DedicatedEnterpriseDeploymentMutationRpcClient = Pick<SupabaseClient, "rpc">;

export const DEDICATED_ENTERPRISE_DEPLOYMENT_KNOWN_MUTATION_ERROR_CODES = [
  "insufficient_authority",
  "deployment_qualification_reason_required",
  "deployment_record_not_pending_qualification",
  "deployment_self_approval_forbidden",
  "deployment_record_not_found",
  "deployment_invalid_transition",
  "deployment_invalid_environment_category",
  "deployment_reference_value_required",
] as const;
type KnownDedicatedEnterpriseDeploymentMutationErrorCode = (typeof DEDICATED_ENTERPRISE_DEPLOYMENT_KNOWN_MUTATION_ERROR_CODES)[number];
export type DedicatedEnterpriseDeploymentMutationErrorCode = KnownDedicatedEnterpriseDeploymentMutationErrorCode | "mutation_failed" | "invalid_response";

export class DedicatedEnterpriseDeploymentMutationError extends Error {
  readonly code: DedicatedEnterpriseDeploymentMutationErrorCode;

  constructor(code: DedicatedEnterpriseDeploymentMutationErrorCode, message: string) {
    super(message);
    this.name = "DedicatedEnterpriseDeploymentMutationError";
    this.code = code;
  }
}

function classifyError(message: string): DedicatedEnterpriseDeploymentMutationErrorCode {
  const prefix = message.split(":")[0]?.trim();
  return (DEDICATED_ENTERPRISE_DEPLOYMENT_KNOWN_MUTATION_ERROR_CODES as readonly string[]).includes(prefix ?? "")
    ? (prefix as KnownDedicatedEnterpriseDeploymentMutationErrorCode)
    : "mutation_failed";
}

/** Authority: DEPLOY:Configure. Fails with a real unique_violation (surfaced as mutation_failed) if this tenant already has a deployment record -- exactly one dedicated-deployment qualification lifecycle per tenant. */
export async function requestDedicatedDeploymentQualification(client: DedicatedEnterpriseDeploymentMutationRpcClient, input: RequestDedicatedDeploymentQualificationInput): Promise<TenantDeploymentRecord> {
  const parsedInput = RequestDedicatedDeploymentQualificationInputSchema.parse(input);
  const { data, error } = await client.rpc("request_dedicated_deployment_qualification", {
    p_tenant_id: parsedInput.tenantId,
    p_qualification_reason: parsedInput.qualificationReason,
    p_contract_reference: parsedInput.contractReference,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new DedicatedEnterpriseDeploymentMutationError(classifyError(error.message), error.message);
  }
  if (!data || typeof data !== "object") {
    throw new DedicatedEnterpriseDeploymentMutationError("invalid_response", "request_dedicated_deployment_qualification returned no row");
  }
  return parseTenantDeploymentRecord(data as Record<string, unknown>);
}

/** Authority: DEPLOY:Approve -- a real, separate authority tier from DEPLOY:Configure ("Provisioning requires contract/security/CTO approval", Prompt 360 §24). */
export async function approveDedicatedDeploymentQualification(client: DedicatedEnterpriseDeploymentMutationRpcClient, input: ApproveDedicatedDeploymentQualificationInput): Promise<TenantDeploymentRecord> {
  const parsedInput = ApproveDedicatedDeploymentQualificationInputSchema.parse(input);
  const { data, error } = await client.rpc("approve_dedicated_deployment_qualification", {
    p_deployment_record_id: parsedInput.deploymentRecordId,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new DedicatedEnterpriseDeploymentMutationError(classifyError(error.message), error.message);
  }
  if (!data || typeof data !== "object") {
    throw new DedicatedEnterpriseDeploymentMutationError("invalid_response", "approve_dedicated_deployment_qualification returned no row");
  }
  return parseTenantDeploymentRecord(data as Record<string, unknown>);
}

/** Authority: DEPLOY:Configure. Enforces the real, ordered transition graph (pending_qualification -> qualified -> provisioning -> active -> decommissioned) -- an out-of-order transition is rejected, never silently applied. */
export async function setDeploymentProvisioningStatus(client: DedicatedEnterpriseDeploymentMutationRpcClient, input: SetDeploymentProvisioningStatusInput): Promise<TenantDeploymentRecord> {
  const parsedInput = SetDeploymentProvisioningStatusInputSchema.parse(input);
  const { data, error } = await client.rpc("set_deployment_provisioning_status", {
    p_deployment_record_id: parsedInput.deploymentRecordId,
    p_new_status: parsedInput.newStatus,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new DedicatedEnterpriseDeploymentMutationError(classifyError(error.message), error.message);
  }
  if (!data || typeof data !== "object") {
    throw new DedicatedEnterpriseDeploymentMutationError("invalid_response", "set_deployment_provisioning_status returned no row");
  }
  return parseTenantDeploymentRecord(data as Record<string, unknown>);
}

/** Authority: DEPLOY:Configure against the deployment record's own tenant. Stores only a reference/pointer -- never a real secret value. Upserts the same row per (deploymentRecordId, environmentCategory) pair. */
export async function setDeploymentEnvironmentRef(client: DedicatedEnterpriseDeploymentMutationRpcClient, input: SetDeploymentEnvironmentRefInput): Promise<TenantDeploymentEnvironmentRef> {
  const parsedInput = SetDeploymentEnvironmentRefInputSchema.parse(input);
  const { data, error } = await client.rpc("set_deployment_environment_ref", {
    p_deployment_record_id: parsedInput.deploymentRecordId,
    p_environment_category: parsedInput.environmentCategory,
    p_reference_value: parsedInput.referenceValue,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new DedicatedEnterpriseDeploymentMutationError(classifyError(error.message), error.message);
  }
  if (!data || typeof data !== "object") {
    throw new DedicatedEnterpriseDeploymentMutationError("invalid_response", "set_deployment_environment_ref returned no row");
  }
  return parseTenantDeploymentEnvironmentRef(data as Record<string, unknown>);
}
