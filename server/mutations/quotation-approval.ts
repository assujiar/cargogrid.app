/**
 * Quotation Approval mutation primitives (COM-153, CG-S7-COM-012). Thin, typed wrappers
 * around app.create_quotation_approval_rule_version / app.publish_quotation_approval_rule_version /
 * app.decide_quotation_approval_step
 * (supabase/migrations/20260724270000_create_commercial_quotation_approval.sql).
 * Delegation/escalation/cancel keep going straight through the already-existing Approval
 * Engine mutations (server/mutations/approval.ts, PLT-123) -- neither needs a
 * quotation-specific wrapper (this migration's own header: neither changes a request's
 * final outcome). app.submit_quotation itself is unchanged in shape -- still wrapped by
 * server/mutations/quotation.ts's own submitQuotation -- routing now simply happens
 * inside that same RPC server-side.
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import {
  CreateQuotationApprovalRuleVersionInputSchema,
  PublishQuotationApprovalRuleVersionInputSchema,
  DecideQuotationApprovalStepInputSchema,
  parseQuotationApprovalRuleVersion,
  type CreateQuotationApprovalRuleVersionInput,
  type PublishQuotationApprovalRuleVersionInput,
  type DecideQuotationApprovalStepInput,
  type QuotationApprovalRuleVersion,
} from "../contracts/quotation/quotation-approval.ts";
import { parseQuotation, type Quotation } from "../contracts/quotation/quotation.ts";

export type QuotationApprovalMutationRpcClient = Pick<SupabaseClient, "rpc">;

export const QUOTATION_APPROVAL_KNOWN_MUTATION_ERROR_CODES = [
  "insufficient_authority",
  "quotation_approval_rule_not_found",
  "stale_version",
  "invalid_transition",
  "superseded_rule_not_found",
  "invalid_supersede",
  "active_rule_exists",
  "quotation_not_found",
  "approval_definition_not_configured",
  "approval_step_not_found",
  "not_a_quotation_approval",
  "approval_request_not_pending",
  "approval_step_not_active",
  "approval_self_approval_denied",
  "approval_decision_already_recorded",
  "approval_invalid_decision",
] as const;
type KnownQuotationApprovalMutationErrorCode = (typeof QUOTATION_APPROVAL_KNOWN_MUTATION_ERROR_CODES)[number];
export type QuotationApprovalMutationErrorCode = KnownQuotationApprovalMutationErrorCode | "mutation_failed" | "invalid_response";

export class QuotationApprovalMutationError extends Error {
  readonly code: QuotationApprovalMutationErrorCode;

  constructor(code: QuotationApprovalMutationErrorCode, message: string) {
    super(message);
    this.name = "QuotationApprovalMutationError";
    this.code = code;
  }
}

function classifyError(message: string): QuotationApprovalMutationErrorCode {
  const prefix = message.split(":")[0]?.trim();
  return (QUOTATION_APPROVAL_KNOWN_MUTATION_ERROR_CODES as readonly string[]).includes(prefix ?? "")
    ? (prefix as KnownQuotationApprovalMutationErrorCode)
    : "mutation_failed";
}

async function callRpc(client: QuotationApprovalMutationRpcClient, fn: string, args: Record<string, unknown>): Promise<unknown> {
  const { data, error } = await client.rpc(fn, args);
  if (error) {
    throw new QuotationApprovalMutationError(classifyError(error.message), error.message);
  }
  return data;
}

/** Draft creation, gated by COM:Create. At least one of minMarginPct/maxDiscountPct/minValueAmount is required (contract-level refine, mirrored by the migration's own quotation_approval_rules_at_least_one_threshold CHECK). */
export async function createQuotationApprovalRuleVersion(client: QuotationApprovalMutationRpcClient, input: CreateQuotationApprovalRuleVersionInput): Promise<QuotationApprovalRuleVersion> {
  const parsedInput = CreateQuotationApprovalRuleVersionInputSchema.parse(input);
  const data = await callRpc(client, "create_quotation_approval_rule_version", {
    p_tenant_id: parsedInput.tenantId,
    p_min_margin_pct: parsedInput.minMarginPct,
    p_max_discount_pct: parsedInput.maxDiscountPct,
    p_min_value_amount: parsedInput.minValueAmount,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_created_by: parsedInput.createdBy,
  });
  if (!data || typeof data !== "object") {
    throw new QuotationApprovalMutationError("invalid_response", "create_quotation_approval_rule_version returned no row");
  }
  return parseQuotationApprovalRuleVersion(data as Record<string, unknown>);
}

/** draft -> published, gated by COM:Approve. Supplying supersedesVersionId archives the tenant's prior published rule first (at most one published rule per tenant). */
export async function publishQuotationApprovalRuleVersion(client: QuotationApprovalMutationRpcClient, input: PublishQuotationApprovalRuleVersionInput): Promise<QuotationApprovalRuleVersion> {
  const parsedInput = PublishQuotationApprovalRuleVersionInputSchema.parse(input);
  const data = await callRpc(client, "publish_quotation_approval_rule_version", {
    p_rule_version_id: parsedInput.ruleVersionId,
    p_expected_version: parsedInput.expectedVersion,
    p_supersedes_version_id: parsedInput.supersedesVersionId,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (!data || typeof data !== "object") {
    throw new QuotationApprovalMutationError("invalid_response", "publish_quotation_approval_rule_version returned no row");
  }
  return parseQuotationApprovalRuleVersion(data as Record<string, unknown>);
}

/** Records one approver's decision on one step of a quotation's bound approval request, then syncs the quotation's own approvalStatus once the request reaches a final state (approved/rejected) -- still pending mid-routing otherwise. "Request revision" is not a third decision value -- reject with a reason, then createQuotationRevision (server/mutations/quotation.ts, COM-152) starts a fresh governed approval path. */
export async function decideQuotationApprovalStep(client: QuotationApprovalMutationRpcClient, input: DecideQuotationApprovalStepInput): Promise<Quotation> {
  const parsedInput = DecideQuotationApprovalStepInputSchema.parse(input);
  const data = await callRpc(client, "decide_quotation_approval_step", {
    p_request_step_id: parsedInput.requestStepId,
    p_decision: parsedInput.decision,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
    p_reason: parsedInput.reason,
  });
  if (!data || typeof data !== "object") {
    throw new QuotationApprovalMutationError("invalid_response", "decide_quotation_approval_step returned no row");
  }
  return parseQuotation(data as Record<string, unknown>);
}
