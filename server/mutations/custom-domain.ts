/**
 * Tenant custom-domain lifecycle mutation primitives (PLT-118, CG-S6-PLT-015). Thin,
 * typed wrappers around app.request_tenant_domain / app.verify_tenant_domain /
 * app.activate_tenant_domain / app.disable_tenant_domain / app.reject_tenant_domain
 * (supabase/migrations/20260717103015_create_custom_domain.sql). All five RPCs are
 * service_role-only (see the migration's own grant comment) -- callers of this module
 * must already have authenticated and authorized the acting session themselves.
 */

import {
  RequestTenantDomainInputSchema,
  VerifyTenantDomainInputSchema,
  ActivateTenantDomainInputSchema,
  DisableTenantDomainInputSchema,
  RejectTenantDomainInputSchema,
  parseTenantCustomDomain,
  type RequestTenantDomainInput,
  type VerifyTenantDomainInput,
  type ActivateTenantDomainInput,
  type DisableTenantDomainInput,
  type RejectTenantDomainInput,
  type TenantCustomDomain,
} from "../contracts/custom-domain/custom-domain.ts";

type CustomDomainMutationRpcFn =
  | "request_tenant_domain"
  | "verify_tenant_domain"
  | "activate_tenant_domain"
  | "disable_tenant_domain"
  | "reject_tenant_domain";

export interface CustomDomainMutationRpcClient {
  rpc(
    fn: CustomDomainMutationRpcFn,
    args: Record<string, unknown>,
  ): Promise<{ data: unknown; error: { message: string } | null }>;
}

export const CUSTOM_DOMAIN_KNOWN_MUTATION_ERROR_CODES = [
  "insufficient_authority",
  "invalid_hostname",
  "reserved_hostname",
  "domain_already_claimed",
  "domain_not_found",
  "domain_not_pending",
  "domain_not_verified",
  "domain_not_disableable",
  "verification_expired",
  "verification_token_mismatch",
] as const;
type KnownCustomDomainMutationErrorCode = (typeof CUSTOM_DOMAIN_KNOWN_MUTATION_ERROR_CODES)[number];
export type CustomDomainMutationErrorCode = KnownCustomDomainMutationErrorCode | "mutation_failed" | "invalid_response";

export class CustomDomainMutationError extends Error {
  readonly code: CustomDomainMutationErrorCode;

  constructor(code: CustomDomainMutationErrorCode, message: string) {
    super(message);
    this.name = "CustomDomainMutationError";
    this.code = code;
  }
}

function classifyError(message: string): CustomDomainMutationErrorCode {
  const prefix = message.split(":")[0]?.trim();
  return (CUSTOM_DOMAIN_KNOWN_MUTATION_ERROR_CODES as readonly string[]).includes(prefix ?? "")
    ? (prefix as KnownCustomDomainMutationErrorCode)
    : "mutation_failed";
}

async function callAndParseRow(
  client: CustomDomainMutationRpcClient,
  fn: CustomDomainMutationRpcFn,
  args: Record<string, unknown>,
): Promise<TenantCustomDomain> {
  const { data, error } = await client.rpc(fn, args);

  if (error) {
    throw new CustomDomainMutationError(classifyError(error.message), error.message);
  }
  if (!data || typeof data !== "object") {
    throw new CustomDomainMutationError("invalid_response", `${fn} returned no row`);
  }
  return parseTenantCustomDomain(data as Record<string, unknown>);
}

/** Idempotent for a repeated request of the exact same (tenant, hostname) while the prior request is still pending_verification. Rejects a reserved/malformed hostname, or one already claimed live by another tenant. */
export async function requestTenantDomain(
  client: CustomDomainMutationRpcClient,
  input: RequestTenantDomainInput,
): Promise<TenantCustomDomain> {
  const parsedInput = RequestTenantDomainInputSchema.parse(input);
  return callAndParseRow(client, "request_tenant_domain", {
    p_tenant_id: parsedInput.tenantId,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_hostname: parsedInput.hostname,
    p_requested_by: parsedInput.requestedBy,
  });
}

/** Compares observedTxtValue (from an external DNS-lookup job) against the stored challenge token. Never re-derives or trusts a caller's own claim of success. */
export async function verifyTenantDomain(
  client: CustomDomainMutationRpcClient,
  input: VerifyTenantDomainInput,
): Promise<TenantCustomDomain> {
  const parsedInput = VerifyTenantDomainInputSchema.parse(input);
  return callAndParseRow(client, "verify_tenant_domain", {
    p_domain_id: parsedInput.domainId,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_observed_txt_value: parsedInput.observedTxtValue,
    p_verified_by: parsedInput.verifiedBy,
  });
}

/** Verified -> active. Only after this does app.resolve_tenant_by_domain() start resolving the hostname. */
export async function activateTenantDomain(
  client: CustomDomainMutationRpcClient,
  input: ActivateTenantDomainInput,
): Promise<TenantCustomDomain> {
  const parsedInput = ActivateTenantDomainInputSchema.parse(input);
  return callAndParseRow(client, "activate_tenant_domain", {
    p_domain_id: parsedInput.domainId,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_activated_by: parsedInput.activatedBy,
  });
}

/** The kill switch: verified or active -> disabled. Frees the hostname for another tenant to claim. */
export async function disableTenantDomain(
  client: CustomDomainMutationRpcClient,
  input: DisableTenantDomainInput,
): Promise<TenantCustomDomain> {
  const parsedInput = DisableTenantDomainInputSchema.parse(input);
  return callAndParseRow(client, "disable_tenant_domain", {
    p_domain_id: parsedInput.domainId,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_reason: parsedInput.reason,
    p_disabled_by: parsedInput.disabledBy,
  });
}

/** Manual rejection of a still-pending request (abuse mitigation). */
export async function rejectTenantDomain(
  client: CustomDomainMutationRpcClient,
  input: RejectTenantDomainInput,
): Promise<TenantCustomDomain> {
  const parsedInput = RejectTenantDomainInputSchema.parse(input);
  return callAndParseRow(client, "reject_tenant_domain", {
    p_domain_id: parsedInput.domainId,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_reason: parsedInput.reason,
    p_rejected_by: parsedInput.rejectedBy,
  });
}
