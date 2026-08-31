/**
 * Enterprise MFA and Session Controls mutation primitives (IAE-027, Prompt 355).
 * Thin, typed wrappers around app.set_mfa_tenant_policy /
 * app.request_mfa_step_up_challenge / app.verify_mfa_step_up_challenge /
 * app.register_user_session / app.revoke_user_session /
 * app.revoke_all_actor_sessions / app.request_mfa_exception /
 * app.approve_mfa_exception / app.consume_mfa_exception
 * (supabase/migrations/20260807100000_create_intelligence_enterprise_mfa_session_controls.sql).
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import {
  SetMfaTenantPolicyInputSchema,
  RequestMfaStepUpChallengeInputSchema,
  VerifyMfaStepUpChallengeInputSchema,
  RegisterUserSessionInputSchema,
  RevokeUserSessionInputSchema,
  RevokeAllActorSessionsInputSchema,
  RequestMfaExceptionInputSchema,
  ApproveMfaExceptionInputSchema,
  ConsumeMfaExceptionInputSchema,
  parseMfaTenantPolicy,
  parseMfaStepUpChallenge,
  parseUserSession,
  parseMfaException,
  type SetMfaTenantPolicyInput,
  type RequestMfaStepUpChallengeInput,
  type VerifyMfaStepUpChallengeInput,
  type RegisterUserSessionInput,
  type RevokeUserSessionInput,
  type RevokeAllActorSessionsInput,
  type RequestMfaExceptionInput,
  type ApproveMfaExceptionInput,
  type ConsumeMfaExceptionInput,
  type MfaTenantPolicy,
  type MfaStepUpChallenge,
  type UserSession,
  type MfaException,
} from "../contracts/enterprise-mfa/enterprise-mfa.ts";
import { resolveRequestClientIp } from "../../lib/security/client-ip.ts";

export type EnterpriseMfaMutationRpcClient = Pick<SupabaseClient, "rpc">;

export const ENTERPRISE_MFA_KNOWN_MUTATION_ERROR_CODES = [
  "insufficient_authority",
  "mfa_invalid_step_up_max_age",
  "mfa_unsafe_additional_high_risk_actions",
  "mfa_step_up_not_required",
  "mfa_step_up_challenge_not_pending",
  "mfa_step_up_challenge_expired",
  "mfa_step_up_required",
  "user_session_not_active",
  "mfa_exception_reason_required",
  "mfa_exception_not_pending",
  "mfa_exception_self_approval_forbidden",
  "mfa_exception_not_approved",
  "mfa_exception_expired",
] as const;
type KnownEnterpriseMfaMutationErrorCode = (typeof ENTERPRISE_MFA_KNOWN_MUTATION_ERROR_CODES)[number];
export type EnterpriseMfaMutationErrorCode = KnownEnterpriseMfaMutationErrorCode | "mutation_failed" | "invalid_response";

export class EnterpriseMfaMutationError extends Error {
  readonly code: EnterpriseMfaMutationErrorCode;

  constructor(code: EnterpriseMfaMutationErrorCode, message: string) {
    super(message);
    this.name = "EnterpriseMfaMutationError";
    this.code = code;
  }
}

function classifyError(message: string): EnterpriseMfaMutationErrorCode {
  const prefix = message.split(":")[0]?.trim();
  return (ENTERPRISE_MFA_KNOWN_MUTATION_ERROR_CODES as readonly string[]).includes(prefix ?? "")
    ? (prefix as KnownEnterpriseMfaMutationErrorCode)
    : "mutation_failed";
}

export async function setMfaTenantPolicy(client: EnterpriseMfaMutationRpcClient, input: SetMfaTenantPolicyInput): Promise<MfaTenantPolicy> {
  const parsedInput = SetMfaTenantPolicyInputSchema.parse(input);
  const { data, error } = await client.rpc("set_mfa_tenant_policy", {
    p_tenant_id: parsedInput.tenantId,
    p_tenant_wide_required: parsedInput.tenantWideRequired,
    p_required_layers: parsedInput.requiredLayers,
    p_step_up_max_age_minutes: parsedInput.stepUpMaxAgeMinutes,
    p_additional_high_risk_actions: parsedInput.additionalHighRiskActions,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
    // ISS-2026-302: read here rather than threaded through every caller -- a security
    // control a call site can forget to pass is not a control. Null outside a request.
    p_client_ip: await resolveRequestClientIp(),
  });
  if (error) {
    throw new EnterpriseMfaMutationError(classifyError(error.message), error.message);
  }
  if (!data || typeof data !== "object") {
    throw new EnterpriseMfaMutationError("invalid_response", "set_mfa_tenant_policy returned no row");
  }
  return parseMfaTenantPolicy(data as Record<string, unknown>);
}

export async function requestMfaStepUpChallenge(client: EnterpriseMfaMutationRpcClient, input: RequestMfaStepUpChallengeInput): Promise<MfaStepUpChallenge> {
  const parsedInput = RequestMfaStepUpChallengeInputSchema.parse(input);
  const { data, error } = await client.rpc("request_mfa_step_up_challenge", {
    p_tenant_id: parsedInput.tenantId,
    p_module_code: parsedInput.moduleCode,
    p_action: parsedInput.action,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new EnterpriseMfaMutationError(classifyError(error.message), error.message);
  }
  if (!data || typeof data !== "object") {
    throw new EnterpriseMfaMutationError("invalid_response", "request_mfa_step_up_challenge returned no row");
  }
  return parseMfaStepUpChallenge(data as Record<string, unknown>);
}

/** Reports that the caller has ALREADY completed the real MFA factor verification (Supabase's own native flow) -- see this capability's own migration header for the disclosed protocol boundary. */
export async function verifyMfaStepUpChallenge(client: EnterpriseMfaMutationRpcClient, input: VerifyMfaStepUpChallengeInput): Promise<MfaStepUpChallenge> {
  const parsedInput = VerifyMfaStepUpChallengeInputSchema.parse(input);
  const { data, error } = await client.rpc("verify_mfa_step_up_challenge", {
    p_challenge_id: parsedInput.challengeId,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new EnterpriseMfaMutationError(classifyError(error.message), error.message);
  }
  if (!data || typeof data !== "object") {
    throw new EnterpriseMfaMutationError("invalid_response", "verify_mfa_step_up_challenge returned no row");
  }
  return parseMfaStepUpChallenge(data as Record<string, unknown>);
}

export async function registerUserSession(client: EnterpriseMfaMutationRpcClient, input: RegisterUserSessionInput): Promise<UserSession> {
  const parsedInput = RegisterUserSessionInputSchema.parse(input);
  const { data, error } = await client.rpc("register_user_session", {
    p_tenant_id: parsedInput.tenantId,
    p_device_label: parsedInput.deviceLabel,
    p_ip_address: parsedInput.ipAddress,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new EnterpriseMfaMutationError(classifyError(error.message), error.message);
  }
  if (!data || typeof data !== "object") {
    throw new EnterpriseMfaMutationError("invalid_response", "register_user_session returned no row");
  }
  return parseUserSession(data as Record<string, unknown>);
}

export async function revokeUserSession(client: EnterpriseMfaMutationRpcClient, input: RevokeUserSessionInput): Promise<UserSession> {
  const parsedInput = RevokeUserSessionInputSchema.parse(input);
  const { data, error } = await client.rpc("revoke_user_session", {
    p_session_id: parsedInput.sessionId,
    p_reason: parsedInput.reason,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
    // ISS-2026-302: read here rather than threaded through every caller -- a security
    // control a call site can forget to pass is not a control. Null outside a request.
    p_client_ip: await resolveRequestClientIp(),
  });
  if (error) {
    throw new EnterpriseMfaMutationError(classifyError(error.message), error.message);
  }
  if (!data || typeof data !== "object") {
    throw new EnterpriseMfaMutationError("invalid_response", "revoke_user_session returned no row");
  }
  return parseUserSession(data as Record<string, unknown>);
}

/** Real "session revocation propagates to API keys" enforcement -- also revokes every active app.api_keys row the target actor themselves created. Returns the number of sessions revoked. */
export async function revokeAllActorSessions(client: EnterpriseMfaMutationRpcClient, input: RevokeAllActorSessionsInput): Promise<number> {
  const parsedInput = RevokeAllActorSessionsInputSchema.parse(input);
  const { data, error } = await client.rpc("revoke_all_actor_sessions", {
    p_tenant_id: parsedInput.tenantId,
    p_target_auth_user_id: parsedInput.targetAuthUserId,
    p_reason: parsedInput.reason,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
    // ISS-2026-302: read here rather than threaded through every caller -- a security
    // control a call site can forget to pass is not a control. Null outside a request.
    p_client_ip: await resolveRequestClientIp(),
  });
  if (error) {
    throw new EnterpriseMfaMutationError(classifyError(error.message), error.message);
  }
  if (typeof data !== "number") {
    throw new EnterpriseMfaMutationError("invalid_response", "revoke_all_actor_sessions returned a non-numeric response");
  }
  return data;
}

export async function requestMfaException(client: EnterpriseMfaMutationRpcClient, input: RequestMfaExceptionInput): Promise<MfaException> {
  const parsedInput = RequestMfaExceptionInputSchema.parse(input);
  const { data, error } = await client.rpc("request_mfa_exception", {
    p_tenant_id: parsedInput.tenantId,
    p_target_auth_user_id: parsedInput.targetAuthUserId,
    p_reason: parsedInput.reason,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
    // ISS-2026-302: read here rather than threaded through every caller -- a security
    // control a call site can forget to pass is not a control. Null outside a request.
    p_client_ip: await resolveRequestClientIp(),
  });
  if (error) {
    throw new EnterpriseMfaMutationError(classifyError(error.message), error.message);
  }
  if (!data || typeof data !== "object") {
    throw new EnterpriseMfaMutationError("invalid_response", "request_mfa_exception returned no row");
  }
  return parseMfaException(data as Record<string, unknown>);
}

/** SEC:Approve-gated; never the same identity that requested it (enforced at the DB CHECK-constraint level, not merely in application code). */
export async function approveMfaException(client: EnterpriseMfaMutationRpcClient, input: ApproveMfaExceptionInput): Promise<MfaException> {
  const parsedInput = ApproveMfaExceptionInputSchema.parse(input);
  const { data, error } = await client.rpc("approve_mfa_exception", {
    p_exception_id: parsedInput.exceptionId,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
    p_client_ip: parsedInput.clientIp ?? null,
  });
  if (error) {
    throw new EnterpriseMfaMutationError(classifyError(error.message), error.message);
  }
  if (!data || typeof data !== "object") {
    throw new EnterpriseMfaMutationError("invalid_response", "approve_mfa_exception returned no row");
  }
  return parseMfaException(data as Record<string, unknown>);
}

/** The real, composable step-up gate other high-risk mutations should call first -- a no-op (resolves) for a non-high-risk action; throws `mfa_step_up_required` if no current verified challenge exists for a high-risk one. */
export async function assertCurrentStepUpAuthorization(
  client: EnterpriseMfaMutationRpcClient,
  input: { tenantId: string; actorAuthUserId: string; moduleCode: string; action: string },
): Promise<void> {
  const { error } = await client.rpc("assert_current_step_up_authorization", {
    p_tenant_id: input.tenantId,
    p_actor_auth_user_id: input.actorAuthUserId,
    p_module_code: input.moduleCode,
    p_action: input.action,
  });
  if (error) {
    throw new EnterpriseMfaMutationError(classifyError(error.message), error.message);
  }
}

export async function consumeMfaException(client: EnterpriseMfaMutationRpcClient, input: ConsumeMfaExceptionInput): Promise<MfaException> {
  const parsedInput = ConsumeMfaExceptionInputSchema.parse(input);
  const { data, error } = await client.rpc("consume_mfa_exception", {
    p_exception_id: parsedInput.exceptionId,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new EnterpriseMfaMutationError(classifyError(error.message), error.message);
  }
  if (!data || typeof data !== "object") {
    throw new EnterpriseMfaMutationError("invalid_response", "consume_mfa_exception returned no row");
  }
  return parseMfaException(data as Record<string, unknown>);
}
