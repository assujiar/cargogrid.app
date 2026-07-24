/**
 * Credit and Commercial Control mutation primitives (COM-157, CG-S7-COM-016). Thin,
 * typed wrappers around the six RPCs
 * supabase/migrations/20260724310000_create_commercial_credit_commercial_control.sql
 * defines. checkCustomerCredit lives here, not in queries/credit.ts, despite its "check"
 * name -- it always persists a new, immutable app.credit_check_snapshots row as its real
 * side effect (the same "a read-shaped RPC that writes its own evidence" posture
 * app.select_vendor_rate, COM-149, already established).
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import {
  RequestCustomerCreditProfileInputSchema,
  DecideCreditProfileApprovalStepInputSchema,
  HoldCreditProfileInputSchema,
  ReleaseCreditProfileInputSchema,
  CreateCreditOverrideInputSchema,
  CheckCustomerCreditInputSchema,
  parseCreditProfile,
  parseCreditProfileOverride,
  parseCreditCheckResult,
  type RequestCustomerCreditProfileInput,
  type DecideCreditProfileApprovalStepInput,
  type HoldCreditProfileInput,
  type ReleaseCreditProfileInput,
  type CreateCreditOverrideInput,
  type CheckCustomerCreditInput,
  type CreditProfile,
  type CreditProfileOverride,
  type CreditCheckResult,
} from "../contracts/credit/credit.ts";

export type CreditMutationRpcClient = Pick<SupabaseClient, "rpc">;

export const CREDIT_KNOWN_MUTATION_ERROR_CODES = [
  "insufficient_authority",
  "account_not_found",
  "invalid_currency",
  "invalid_amount",
  "credit_profile_already_requested",
  "approval_definition_not_configured",
  "approval_step_not_found",
  "not_a_credit_profile_approval",
  "reauth_required",
  "credit_profile_not_found",
  "reason_required",
  "invalid_expiry",
  "stale_version",
  "invalid_transition",
] as const;
type KnownCreditMutationErrorCode = (typeof CREDIT_KNOWN_MUTATION_ERROR_CODES)[number];
export type CreditMutationErrorCode = KnownCreditMutationErrorCode | "mutation_failed" | "invalid_response";

export class CreditMutationError extends Error {
  readonly code: CreditMutationErrorCode;

  constructor(code: CreditMutationErrorCode, message: string) {
    super(message);
    this.name = "CreditMutationError";
    this.code = code;
  }
}

function classifyError(message: string): CreditMutationErrorCode {
  const prefix = message.split(":")[0]?.trim();
  return (CREDIT_KNOWN_MUTATION_ERROR_CODES as readonly string[]).includes(prefix ?? "") ? (prefix as KnownCreditMutationErrorCode) : "mutation_failed";
}

/** Unconditionally routes through the Platform Approval Engine (entity_type=credit_profile) -- fails closed (approval_definition_not_configured) if the tenant has never published an approval routing definition. */
export async function requestCustomerCreditProfile(client: CreditMutationRpcClient, input: RequestCustomerCreditProfileInput): Promise<CreditProfile> {
  const parsedInput = RequestCustomerCreditProfileInputSchema.parse(input);
  const { data, error } = await client.rpc("request_customer_credit_profile", {
    p_tenant_id: parsedInput.tenantId,
    p_account_id: parsedInput.accountId,
    p_currency: parsedInput.currency,
    p_requested_limit_amount: parsedInput.requestedLimitAmount,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new CreditMutationError(classifyError(error.message), error.message);
  }
  if (!data || typeof data !== "object") {
    throw new CreditMutationError("invalid_response", "request_customer_credit_profile returned no row");
  }
  return parseCreditProfile({ ...(data as Record<string, unknown>), amount_masked: false });
}

/** The privileged-approver decision. reauthConfirmedAt must be a fresh (<=5 minute) timestamp -- Prompt 157 §16's MFA-for-privileged-approvers gate, reused from PLT-115 (see contract header). */
export async function decideCreditProfileApprovalStep(client: CreditMutationRpcClient, input: DecideCreditProfileApprovalStepInput): Promise<CreditProfile> {
  const parsedInput = DecideCreditProfileApprovalStepInputSchema.parse(input);
  const { data, error } = await client.rpc("decide_credit_profile_approval_step", {
    p_request_step_id: parsedInput.requestStepId,
    p_decision: parsedInput.decision,
    p_reason: parsedInput.reason,
    p_reauth_confirmed_at: parsedInput.reauthConfirmedAt,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new CreditMutationError(classifyError(error.message), error.message);
  }
  if (!data || typeof data !== "object") {
    throw new CreditMutationError("invalid_response", "decide_credit_profile_approval_step returned no row");
  }
  return parseCreditProfile({ ...(data as Record<string, unknown>), amount_masked: false });
}

export async function holdCreditProfile(client: CreditMutationRpcClient, input: HoldCreditProfileInput): Promise<CreditProfile> {
  const parsedInput = HoldCreditProfileInputSchema.parse(input);
  const { data, error } = await client.rpc("hold_credit_profile", {
    p_profile_id: parsedInput.profileId,
    p_expected_version: parsedInput.expectedVersion,
    p_reason: parsedInput.reason,
    p_reauth_confirmed_at: parsedInput.reauthConfirmedAt,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new CreditMutationError(classifyError(error.message), error.message);
  }
  if (!data || typeof data !== "object") {
    throw new CreditMutationError("invalid_response", "hold_credit_profile returned no row");
  }
  return parseCreditProfile({ ...(data as Record<string, unknown>), amount_masked: false });
}

export async function releaseCreditProfile(client: CreditMutationRpcClient, input: ReleaseCreditProfileInput): Promise<CreditProfile> {
  const parsedInput = ReleaseCreditProfileInputSchema.parse(input);
  const { data, error } = await client.rpc("release_credit_profile", {
    p_profile_id: parsedInput.profileId,
    p_expected_version: parsedInput.expectedVersion,
    p_reauth_confirmed_at: parsedInput.reauthConfirmedAt,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new CreditMutationError(classifyError(error.message), error.message);
  }
  if (!data || typeof data !== "object") {
    throw new CreditMutationError("invalid_response", "release_credit_profile returned no row");
  }
  return parseCreditProfile({ ...(data as Record<string, unknown>), amount_masked: false });
}

/** A bounded, reasoned, always-expiring exception -- COM:Approve + fresh reauth gated (the "elevated approval" Prompt 157 §22 asks for). */
export async function createCreditOverride(client: CreditMutationRpcClient, input: CreateCreditOverrideInput): Promise<CreditProfileOverride> {
  const parsedInput = CreateCreditOverrideInputSchema.parse(input);
  const { data, error } = await client.rpc("create_credit_override", {
    p_profile_id: parsedInput.profileId,
    p_amount: parsedInput.amount,
    p_reason: parsedInput.reason,
    p_expires_at: parsedInput.expiresAt,
    p_reauth_confirmed_at: parsedInput.reauthConfirmedAt,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new CreditMutationError(classifyError(error.message), error.message);
  }
  if (!data || typeof data !== "object") {
    throw new CreditMutationError("invalid_response", "create_credit_override returned no row");
  }
  return parseCreditProfileOverride({ ...(data as Record<string, unknown>), amount_masked: false });
}

/** The deterministic, reproducible pre-conversion check (Prompt 157 §20 task 3). Always produces a persisted snapshot; the returned row is masked per-caller (COM:View selling price) by the RPC itself, not by this wrapper. */
export async function checkCustomerCredit(client: CreditMutationRpcClient, input: CheckCustomerCreditInput): Promise<CreditCheckResult> {
  const parsedInput = CheckCustomerCreditInputSchema.parse(input);
  const { data, error } = await client.rpc("check_customer_credit", {
    p_tenant_id: parsedInput.tenantId,
    p_account_id: parsedInput.accountId,
    p_currency: parsedInput.currency,
    p_requested_amount: parsedInput.requestedAmount,
    p_context_type: parsedInput.contextType,
    p_context_id: parsedInput.contextId,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new CreditMutationError(classifyError(error.message), error.message);
  }
  const row = Array.isArray(data) ? data[0] : data;
  if (!row || typeof row !== "object") {
    throw new CreditMutationError("invalid_response", "check_customer_credit returned no row");
  }
  return parseCreditCheckResult(row as Record<string, unknown>);
}
