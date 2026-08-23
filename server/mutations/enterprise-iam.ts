/**
 * Enterprise IAM mutation primitives (IAE-026, Prompt 354). Thin, typed
 * wrappers around app.request_enterprise_sso_domain_claim /
 * app.verify_enterprise_sso_domain_claim / app.activate_enterprise_sso_domain_claim /
 * app.disable_enterprise_sso_domain_claim / app.resolve_enterprise_sso_claims /
 * app.activate_enterprise_idp_connection / app.provision_scim_identity
 * (supabase/migrations/20260807000000_create_intelligence_enterprise_iam_sso.sql).
 * Connection create/update/rotate/disable itself reuses
 * server/mutations/integration-hub.ts's own createIntegrationConnection /
 * setIntegrationConnectionStatus UNMODIFIED (design decision 3a of this
 * capability's own migration) -- not re-wrapped here.
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import {
  RequestEnterpriseSsoDomainClaimInputSchema,
  VerifyEnterpriseSsoDomainClaimInputSchema,
  ActivateEnterpriseSsoDomainClaimInputSchema,
  DisableEnterpriseSsoDomainClaimInputSchema,
  ResolveEnterpriseSsoClaimsInputSchema,
  ActivateEnterpriseIdpConnectionInputSchema,
  ProvisionScimIdentityInputSchema,
  parseIamDomainClaim,
  parseIamSsoLoginAttempt,
  parseIamScimProvisioningEvent,
  type RequestEnterpriseSsoDomainClaimInput,
  type VerifyEnterpriseSsoDomainClaimInput,
  type ActivateEnterpriseSsoDomainClaimInput,
  type DisableEnterpriseSsoDomainClaimInput,
  type ResolveEnterpriseSsoClaimsInput,
  type ActivateEnterpriseIdpConnectionInput,
  type ProvisionScimIdentityInput,
  type IamDomainClaim,
  type IamSsoLoginAttempt,
  type IamScimProvisioningEvent,
} from "../contracts/enterprise-iam/enterprise-iam.ts";
import { parseIntegrationConnection, type IntegrationConnection } from "../contracts/integration-hub/integration-hub.ts";

export type EnterpriseIamMutationRpcClient = Pick<SupabaseClient, "rpc">;

export const ENTERPRISE_IAM_KNOWN_MUTATION_ERROR_CODES = [
  "insufficient_authority",
  "iam_connection_not_found",
  "iam_connection_wrong_adapter",
  "invalid_email_domain",
  "reserved_email_domain",
  "email_domain_already_claimed",
  "iam_domain_claim_not_found",
  "iam_domain_claim_not_pending",
  "iam_domain_claim_expired",
  "iam_domain_claim_token_mismatch",
  "iam_domain_claim_not_verified",
  "iam_domain_claim_not_disableable",
  "iam_missing_subject_claim",
  "enterprise_idp_no_verified_test_login",
  "iam_scim_invalid_operation",
  "iam_scim_api_key_not_found",
  "iam_scim_missing_external_id",
] as const;
type KnownEnterpriseIamMutationErrorCode = (typeof ENTERPRISE_IAM_KNOWN_MUTATION_ERROR_CODES)[number];
export type EnterpriseIamMutationErrorCode = KnownEnterpriseIamMutationErrorCode | "mutation_failed" | "invalid_response";

export class EnterpriseIamMutationError extends Error {
  readonly code: EnterpriseIamMutationErrorCode;

  constructor(code: EnterpriseIamMutationErrorCode, message: string) {
    super(message);
    this.name = "EnterpriseIamMutationError";
    this.code = code;
  }
}

function classifyError(message: string): EnterpriseIamMutationErrorCode {
  const prefix = message.split(":")[0]?.trim();
  return (ENTERPRISE_IAM_KNOWN_MUTATION_ERROR_CODES as readonly string[]).includes(prefix ?? "")
    ? (prefix as KnownEnterpriseIamMutationErrorCode)
    : "mutation_failed";
}

export async function requestEnterpriseSsoDomainClaim(
  client: EnterpriseIamMutationRpcClient,
  input: RequestEnterpriseSsoDomainClaimInput,
): Promise<IamDomainClaim> {
  const parsedInput = RequestEnterpriseSsoDomainClaimInputSchema.parse(input);
  const { data, error } = await client.rpc("request_enterprise_sso_domain_claim", {
    p_tenant_id: parsedInput.tenantId,
    p_connection_id: parsedInput.connectionId,
    p_email_domain: parsedInput.emailDomain,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new EnterpriseIamMutationError(classifyError(error.message), error.message);
  }
  if (!data || typeof data !== "object") {
    throw new EnterpriseIamMutationError("invalid_response", "request_enterprise_sso_domain_claim returned no row");
  }
  return parseIamDomainClaim(data as Record<string, unknown>);
}

export async function verifyEnterpriseSsoDomainClaim(
  client: EnterpriseIamMutationRpcClient,
  input: VerifyEnterpriseSsoDomainClaimInput,
): Promise<IamDomainClaim> {
  const parsedInput = VerifyEnterpriseSsoDomainClaimInputSchema.parse(input);
  const { data, error } = await client.rpc("verify_enterprise_sso_domain_claim", {
    p_claim_id: parsedInput.claimId,
    p_observed_txt_value: parsedInput.observedTxtValue,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new EnterpriseIamMutationError(classifyError(error.message), error.message);
  }
  if (!data || typeof data !== "object") {
    throw new EnterpriseIamMutationError("invalid_response", "verify_enterprise_sso_domain_claim returned no row");
  }
  return parseIamDomainClaim(data as Record<string, unknown>);
}

export async function activateEnterpriseSsoDomainClaim(
  client: EnterpriseIamMutationRpcClient,
  input: ActivateEnterpriseSsoDomainClaimInput,
): Promise<IamDomainClaim> {
  const parsedInput = ActivateEnterpriseSsoDomainClaimInputSchema.parse(input);
  const { data, error } = await client.rpc("activate_enterprise_sso_domain_claim", {
    p_claim_id: parsedInput.claimId,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new EnterpriseIamMutationError(classifyError(error.message), error.message);
  }
  if (!data || typeof data !== "object") {
    throw new EnterpriseIamMutationError("invalid_response", "activate_enterprise_sso_domain_claim returned no row");
  }
  return parseIamDomainClaim(data as Record<string, unknown>);
}

export async function disableEnterpriseSsoDomainClaim(
  client: EnterpriseIamMutationRpcClient,
  input: DisableEnterpriseSsoDomainClaimInput,
): Promise<IamDomainClaim> {
  const parsedInput = DisableEnterpriseSsoDomainClaimInputSchema.parse(input);
  const { data, error } = await client.rpc("disable_enterprise_sso_domain_claim", {
    p_claim_id: parsedInput.claimId,
    p_reason: parsedInput.reason,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new EnterpriseIamMutationError(classifyError(error.message), error.message);
  }
  if (!data || typeof data !== "object") {
    throw new EnterpriseIamMutationError("invalid_response", "disable_enterprise_sso_domain_claim returned no row");
  }
  return parseIamDomainClaim(data as Record<string, unknown>);
}

/** Administrative claims-test tool -- see this capability's own migration header for the disclosed protocol-verification boundary. */
export async function resolveEnterpriseSsoClaims(
  client: EnterpriseIamMutationRpcClient,
  input: ResolveEnterpriseSsoClaimsInput,
): Promise<IamSsoLoginAttempt> {
  const parsedInput = ResolveEnterpriseSsoClaimsInputSchema.parse(input);
  const { data, error } = await client.rpc("resolve_enterprise_sso_claims", {
    p_connection_id: parsedInput.connectionId,
    p_subject_claim: parsedInput.subjectClaim,
    p_raw_email_claim: parsedInput.rawEmailClaim,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new EnterpriseIamMutationError(classifyError(error.message), error.message);
  }
  if (!data || typeof data !== "object") {
    throw new EnterpriseIamMutationError("invalid_response", "resolve_enterprise_sso_claims returned no row");
  }
  return parseIamSsoLoginAttempt(data as Record<string, unknown>);
}

/** The structural lockout guard -- requires at least one prior `matched` app.iam_sso_login_attempts row. */
export async function activateEnterpriseIdpConnection(
  client: EnterpriseIamMutationRpcClient,
  input: ActivateEnterpriseIdpConnectionInput,
): Promise<IntegrationConnection> {
  const parsedInput = ActivateEnterpriseIdpConnectionInputSchema.parse(input);
  const { data, error } = await client.rpc("activate_enterprise_idp_connection", {
    p_connection_id: parsedInput.connectionId,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new EnterpriseIamMutationError(classifyError(error.message), error.message);
  }
  if (!data || typeof data !== "object") {
    throw new EnterpriseIamMutationError("invalid_response", "activate_enterprise_idp_connection returned no row");
  }
  return parseIntegrationConnection(data as Record<string, unknown>);
}

/** IAM:Configure-gated. Real deactivate/reactivate enforcement; a genuinely new identity (no app.users email match) is disclosed-rejected, never fabricated -- see this capability's own migration header. */
export async function provisionScimIdentity(
  client: EnterpriseIamMutationRpcClient,
  input: ProvisionScimIdentityInput,
): Promise<IamScimProvisioningEvent> {
  const parsedInput = ProvisionScimIdentityInputSchema.parse(input);
  const { data, error } = await client.rpc("provision_scim_identity", {
    p_tenant_id: parsedInput.tenantId,
    p_api_key_id: parsedInput.apiKeyId,
    p_external_id: parsedInput.externalId,
    p_raw_email: parsedInput.rawEmail,
    p_display_name: parsedInput.displayName,
    p_operation: parsedInput.operation,
    p_is_dry_run: parsedInput.isDryRun,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new EnterpriseIamMutationError(classifyError(error.message), error.message);
  }
  if (!data || typeof data !== "object") {
    throw new EnterpriseIamMutationError("invalid_response", "provision_scim_identity returned no row");
  }
  return parseIamScimProvisioningEvent(data as Record<string, unknown>);
}
