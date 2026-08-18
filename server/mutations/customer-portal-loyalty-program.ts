/**
 * Loyalty Program and Earning mutation primitives (CPL-316, CG-S13-CPL-018).
 * Thin, typed wrappers around every write RPC in supabase/migrations/
 * 20260801180000_create_customer_portal_loyalty_program_earning.sql --
 * ALL of them are staff-gated (LYL:Create/Edit/Configure) internally by the
 * RPC itself; there is no customer-initiated write in this capability
 * (ADR-0024 Part B: earning is evaluated by a staff/system actor, never a
 * customer principal). None of these exports should ever be called from a
 * customer-facing Server Action.
 *
 * Mirrors server/mutations/customer-portal-profile.ts's own known-error-
 * code/classifyError/callRpc shape.
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import {
  parseLoyaltyProgram,
  parseLoyaltyProgramRuleVersion,
  parseLoyaltyAccount,
  parseLoyaltyEarningEvent,
  CreateLoyaltyProgramInputSchema,
  UpdateLoyaltyProgramStatusInputSchema,
  CreateLoyaltyProgramRuleVersionInputSchema,
  UpdateLoyaltyProgramRuleVersionDraftInputSchema,
  PublishLoyaltyProgramRuleVersionInputSchema,
  EnrollCustomerLoyaltyAccountInputSchema,
  SetLoyaltyAccountStatusInputSchema,
  EvaluateCustomerLoyaltyEarningForPaidInvoiceInputSchema,
  ReverseLoyaltyEarningEventInputSchema,
  type CreateLoyaltyProgramInput,
  type UpdateLoyaltyProgramStatusInput,
  type CreateLoyaltyProgramRuleVersionInput,
  type UpdateLoyaltyProgramRuleVersionDraftInput,
  type PublishLoyaltyProgramRuleVersionInput,
  type EnrollCustomerLoyaltyAccountInput,
  type SetLoyaltyAccountStatusInput,
  type EvaluateCustomerLoyaltyEarningForPaidInvoiceInput,
  type ReverseLoyaltyEarningEventInput,
  type LoyaltyProgram,
  type LoyaltyProgramRuleVersion,
  type LoyaltyAccount,
  type LoyaltyEarningEvent,
} from "../contracts/customer-portal-loyalty-program/customer-portal-loyalty-program.ts";

export type LoyaltyProgramMutationRpcClient = Pick<SupabaseClient, "rpc">;

export const LOYALTY_PROGRAM_KNOWN_MUTATION_ERROR_CODES = [
  "insufficient_authority",
  "invalid_name",
  "loyalty_program_name_conflict",
  "invalid_status",
  "loyalty_program_not_found",
  "stale_version",
  "invalid_transition",
  "invalid_reward_type",
  "invalid_earning_basis",
  "invalid_rate",
  "invalid_eligibility_config",
  "draft_already_exists",
  "loyalty_program_rule_version_not_found",
  "customer_account_not_found",
  "loyalty_program_not_active",
  "customer_already_has_active_enrollment",
  "loyalty_account_not_found",
  "reason_required",
  "ar_open_item_not_found",
  "ar_open_item_not_paid",
  "ar_open_item_held",
  "loyalty_account_not_active",
  "no_published_rule_version",
  "unsupported_earning_basis",
  "ineligible_amount_below_minimum",
  "computed_amount_not_positive",
  "invalid_idempotency_key",
  "loyalty_earning_event_not_found",
  "invalid_reversal",
  "already_reversed",
  "actor_identity_mismatch",
] as const;
export type KnownLoyaltyProgramMutationErrorCode = (typeof LOYALTY_PROGRAM_KNOWN_MUTATION_ERROR_CODES)[number];
export type LoyaltyProgramMutationErrorCode = KnownLoyaltyProgramMutationErrorCode | "mutation_failed";

export class LoyaltyProgramMutationError extends Error {
  readonly code: LoyaltyProgramMutationErrorCode;

  constructor(code: LoyaltyProgramMutationErrorCode, message: string) {
    super(message);
    this.name = "LoyaltyProgramMutationError";
    this.code = code;
  }
}

function classifyError(message: string): LoyaltyProgramMutationErrorCode {
  const prefix = message.split(":")[0]?.trim();
  if (prefix && (LOYALTY_PROGRAM_KNOWN_MUTATION_ERROR_CODES as readonly string[]).includes(prefix)) {
    return prefix as KnownLoyaltyProgramMutationErrorCode;
  }
  return "mutation_failed";
}

async function callRpc<T>(client: LoyaltyProgramMutationRpcClient, fn: string, args: Record<string, unknown>, parse: (row: Record<string, unknown>) => T): Promise<T> {
  const { data, error } = await client.rpc(fn, args);
  if (error) {
    throw new LoyaltyProgramMutationError(classifyError(error.message), error.message);
  }
  const row = Array.isArray(data) ? data[0] : data;
  if (!row || typeof row !== "object") {
    throw new LoyaltyProgramMutationError("mutation_failed", `${fn} returned no row`);
  }
  return parse(row as Record<string, unknown>);
}

// ===========================================================================
// Program CRUD (LYL:Create / LYL:Edit)
// ===========================================================================

export async function createLoyaltyProgram(client: LoyaltyProgramMutationRpcClient, input: CreateLoyaltyProgramInput): Promise<LoyaltyProgram> {
  const v = CreateLoyaltyProgramInputSchema.parse(input);
  return callRpc(
    client,
    "create_loyalty_program",
    {
      p_tenant_id: v.tenantId,
      p_name: v.name,
      p_description: v.description,
      p_actor_auth_user_id: v.actorAuthUserId,
      p_actor_label: v.actorLabel,
    },
    parseLoyaltyProgram,
  );
}

/** draft -> active -> inactive -> active. An identical target status is a safe no-op. */
export async function updateLoyaltyProgramStatus(client: LoyaltyProgramMutationRpcClient, input: UpdateLoyaltyProgramStatusInput): Promise<LoyaltyProgram> {
  const v = UpdateLoyaltyProgramStatusInputSchema.parse(input);
  return callRpc(
    client,
    "update_loyalty_program_status",
    {
      p_tenant_id: v.tenantId,
      p_program_id: v.programId,
      p_expected_version: v.expectedVersion,
      p_new_status: v.newStatus,
      p_actor_auth_user_id: v.actorAuthUserId,
      p_actor_label: v.actorLabel,
    },
    parseLoyaltyProgram,
  );
}

// ===========================================================================
// Rule version lifecycle: draft (LYL:Create/Edit) -> published (LYL:Configure)
// ===========================================================================

export async function createLoyaltyProgramRuleVersion(client: LoyaltyProgramMutationRpcClient, input: CreateLoyaltyProgramRuleVersionInput): Promise<LoyaltyProgramRuleVersion> {
  const v = CreateLoyaltyProgramRuleVersionInputSchema.parse(input);
  return callRpc(
    client,
    "create_loyalty_program_rule_version",
    {
      p_tenant_id: v.tenantId,
      p_program_id: v.programId,
      p_earning_basis: v.earningBasis,
      p_reward_type: v.rewardType,
      p_rate: v.rate,
      p_eligibility_config: v.eligibilityConfig,
      p_actor_auth_user_id: v.actorAuthUserId,
      p_actor_label: v.actorLabel,
    },
    parseLoyaltyProgramRuleVersion,
  );
}

export async function updateLoyaltyProgramRuleVersionDraft(client: LoyaltyProgramMutationRpcClient, input: UpdateLoyaltyProgramRuleVersionDraftInput): Promise<LoyaltyProgramRuleVersion> {
  const v = UpdateLoyaltyProgramRuleVersionDraftInputSchema.parse(input);
  return callRpc(
    client,
    "update_loyalty_program_rule_version_draft",
    {
      p_tenant_id: v.tenantId,
      p_rule_version_id: v.ruleVersionId,
      p_expected_version: v.expectedVersion,
      p_earning_basis: v.earningBasis,
      p_reward_type: v.rewardType,
      p_rate: v.rate,
      p_eligibility_config: v.eligibilityConfig,
      p_actor_auth_user_id: v.actorAuthUserId,
      p_actor_label: v.actorLabel,
    },
    parseLoyaltyProgramRuleVersion,
  );
}

/** Locks this rule version forever, supersedes the program's prior published version (if any) in the same transaction. */
export async function publishLoyaltyProgramRuleVersion(client: LoyaltyProgramMutationRpcClient, input: PublishLoyaltyProgramRuleVersionInput): Promise<LoyaltyProgramRuleVersion> {
  const v = PublishLoyaltyProgramRuleVersionInputSchema.parse(input);
  return callRpc(
    client,
    "publish_loyalty_program_rule_version",
    {
      p_tenant_id: v.tenantId,
      p_rule_version_id: v.ruleVersionId,
      p_expected_version: v.expectedVersion,
      p_effective_from: v.effectiveFrom,
      p_actor_auth_user_id: v.actorAuthUserId,
      p_actor_label: v.actorLabel,
    },
    parseLoyaltyProgramRuleVersion,
  );
}

// ===========================================================================
// Loyalty account enrollment/lifecycle (LYL:Create / LYL:Edit)
// ===========================================================================

export async function enrollCustomerLoyaltyAccount(client: LoyaltyProgramMutationRpcClient, input: EnrollCustomerLoyaltyAccountInput): Promise<LoyaltyAccount> {
  const v = EnrollCustomerLoyaltyAccountInputSchema.parse(input);
  return callRpc(
    client,
    "enroll_customer_loyalty_account",
    {
      p_tenant_id: v.tenantId,
      p_customer_account_id: v.customerAccountId,
      p_program_id: v.programId,
      p_actor_auth_user_id: v.actorAuthUserId,
      p_actor_label: v.actorLabel,
    },
    parseLoyaltyAccount,
  );
}

export async function setLoyaltyAccountStatus(client: LoyaltyProgramMutationRpcClient, input: SetLoyaltyAccountStatusInput): Promise<LoyaltyAccount> {
  const v = SetLoyaltyAccountStatusInputSchema.parse(input);
  return callRpc(
    client,
    "set_loyalty_account_status",
    {
      p_tenant_id: v.tenantId,
      p_account_id: v.accountId,
      p_expected_version: v.expectedVersion,
      p_new_status: v.newStatus,
      p_reason: v.reason,
      p_actor_auth_user_id: v.actorAuthUserId,
      p_actor_label: v.actorLabel,
    },
    parseLoyaltyAccount,
  );
}

// ===========================================================================
// Earning ledger (LYL:Edit to post, LYL:Configure to reverse)
// ===========================================================================

/**
 * Idempotent on (tenantId, 'ar-open-item:' + arOpenItemId) -- calling this
 * twice for the same paid invoice is a safe no-op, never a duplicate award.
 * On-demand/staff-triggered only in this checkpoint (no automatic job/
 * trigger wiring -- ISS-2026-126).
 */
export async function evaluateCustomerLoyaltyEarningForPaidInvoice(client: LoyaltyProgramMutationRpcClient, input: EvaluateCustomerLoyaltyEarningForPaidInvoiceInput): Promise<LoyaltyEarningEvent> {
  const v = EvaluateCustomerLoyaltyEarningForPaidInvoiceInputSchema.parse(input);
  return callRpc(
    client,
    "evaluate_customer_loyalty_earning_for_paid_invoice",
    {
      p_tenant_id: v.tenantId,
      p_ar_open_item_id: v.arOpenItemId,
      p_actor_auth_user_id: v.actorAuthUserId,
      p_actor_label: v.actorLabel,
    },
    parseLoyaltyEarningEvent,
  );
}

/** NEVER deletes/edits the original event -- inserts a new, linked row (correctsEventId), exact negation of the original amount. Idempotent on (tenantId, idempotencyKey). */
export async function reverseLoyaltyEarningEvent(client: LoyaltyProgramMutationRpcClient, input: ReverseLoyaltyEarningEventInput): Promise<LoyaltyEarningEvent> {
  const v = ReverseLoyaltyEarningEventInputSchema.parse(input);
  return callRpc(
    client,
    "reverse_loyalty_earning_event",
    {
      p_tenant_id: v.tenantId,
      p_event_id: v.eventId,
      p_reason: v.reason,
      p_idempotency_key: v.idempotencyKey,
      p_actor_auth_user_id: v.actorAuthUserId,
      p_actor_label: v.actorLabel,
    },
    parseLoyaltyEarningEvent,
  );
}
