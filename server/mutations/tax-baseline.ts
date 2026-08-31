/**
 * Tax Baseline mutation primitives (FIN-195, CG-S9-FIN-006). Thin, typed
 * wrappers around app.create_finance_tax_rule_draft /
 * app.attach_finance_tax_rule_evidence / app.discard_finance_tax_rule_draft /
 * app.approve_finance_tax_rule
 * (supabase/migrations/20260729090000_create_finance_tax_baseline.sql).
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import {
  CreateFinanceTaxRuleDraftInputSchema,
  AttachFinanceTaxRuleEvidenceInputSchema,
  DiscardFinanceTaxRuleDraftInputSchema,
  ApproveFinanceTaxRuleInputSchema,
  parseFinanceTaxRuleVersion,
  type CreateFinanceTaxRuleDraftInput,
  type AttachFinanceTaxRuleEvidenceInput,
  type DiscardFinanceTaxRuleDraftInput,
  type ApproveFinanceTaxRuleInput,
  type FinanceTaxRuleVersion,
} from "../contracts/tax-baseline/tax-baseline.ts";
import { resolveRequestClientIp } from "../../lib/security/client-ip.ts";

export type TaxBaselineMutationRpcClient = Pick<SupabaseClient, "rpc">;

export const TAX_BASELINE_KNOWN_MUTATION_ERROR_CODES = [
  "insufficient_authority",
  "finance_tax_rule_unsupported_code",
  "finance_tax_rule_scope_mismatch",
  "finance_tax_rule_unsupported_basis",
  "finance_tax_rule_invalid_rate",
  "finance_tax_rule_account_scope_mismatch",
  "finance_tax_rule_invalid_account_mapping",
  "finance_tax_rule_not_found",
  "finance_tax_rule_not_draft",
  "finance_tax_rule_evidence_missing",
  "finance_tax_rule_example_fixture_not_activatable",
  "finance_tax_rule_overlap",
  "finance_tax_rule_missing",
  "finance_tax_rule_invalid_base_amount",
  "stale_version",
] as const;
type KnownTaxBaselineMutationErrorCode = (typeof TAX_BASELINE_KNOWN_MUTATION_ERROR_CODES)[number];
export type TaxBaselineMutationErrorCode = KnownTaxBaselineMutationErrorCode | "mutation_failed" | "invalid_response";

export class TaxBaselineMutationError extends Error {
  readonly code: TaxBaselineMutationErrorCode;

  constructor(code: TaxBaselineMutationErrorCode, message: string) {
    super(message);
    this.name = "TaxBaselineMutationError";
    this.code = code;
  }
}

function classifyError(message: string): TaxBaselineMutationErrorCode {
  const prefix = message.split(":")[0]?.trim();
  return (TAX_BASELINE_KNOWN_MUTATION_ERROR_CODES as readonly string[]).includes(prefix ?? "")
    ? (prefix as KnownTaxBaselineMutationErrorCode)
    : "mutation_failed";
}

async function callAndParseRule(
  client: TaxBaselineMutationRpcClient,
  fn: "create_finance_tax_rule_draft" | "attach_finance_tax_rule_evidence" | "discard_finance_tax_rule_draft" | "approve_finance_tax_rule",
  args: Record<string, unknown>,
): Promise<FinanceTaxRuleVersion> {
  const { data, error } = await client.rpc(fn, args);
  if (error) {
    throw new TaxBaselineMutationError(classifyError(error.message), error.message);
  }
  if (!data || typeof data !== "object") {
    throw new TaxBaselineMutationError("invalid_response", `${fn} returned no row`);
  }
  return parseFinanceTaxRuleVersion(data as Record<string, unknown>);
}

/** FIN:Edit-gated. Rejects an inactive/unknown tax code, an unsupported rate basis, a negative rate, or an inactive/non-postable/cross-tenant account mapping. */
export async function createFinanceTaxRuleDraft(
  client: TaxBaselineMutationRpcClient,
  input: CreateFinanceTaxRuleDraftInput,
): Promise<FinanceTaxRuleVersion> {
  const parsedInput = CreateFinanceTaxRuleDraftInputSchema.parse(input);
  return callAndParseRule(client, "create_finance_tax_rule_draft", {
    p_tenant_id: parsedInput.tenantId,
    p_tax_code_id: parsedInput.taxCodeId,
    p_rate_basis: parsedInput.rateBasis,
    p_rate_value: parsedInput.rateValue,
    p_currency: parsedInput.currency,
    p_output_account_id: parsedInput.outputAccountId,
    p_recoverable_account_id: parsedInput.recoverableAccountId,
    p_effective_from: parsedInput.effectiveFrom,
    p_effective_to: parsedInput.effectiveTo,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_created_by: parsedInput.createdBy,
  });
}

/** FIN:Edit-gated, draft only. At least one of an evidence file or a non-empty evidence note is required before approval. */
export async function attachFinanceTaxRuleEvidence(
  client: TaxBaselineMutationRpcClient,
  input: AttachFinanceTaxRuleEvidenceInput,
): Promise<FinanceTaxRuleVersion> {
  const parsedInput = AttachFinanceTaxRuleEvidenceInputSchema.parse(input);
  return callAndParseRule(client, "attach_finance_tax_rule_evidence", {
    p_rule_id: parsedInput.ruleId,
    p_expected_version: parsedInput.expectedVersion,
    p_evidence_reference_file_id: parsedInput.evidenceReferenceFileId,
    p_evidence_note: parsedInput.evidenceNote,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
}

/** FIN:Edit-gated. draft -> archived. Rejected once the rule is approved. */
export async function discardFinanceTaxRuleDraft(
  client: TaxBaselineMutationRpcClient,
  input: DiscardFinanceTaxRuleDraftInput,
): Promise<FinanceTaxRuleVersion> {
  const parsedInput = DiscardFinanceTaxRuleDraftInputSchema.parse(input);
  return callAndParseRule(client, "discard_finance_tax_rule_draft", {
    p_rule_id: parsedInput.ruleId,
    p_expected_version: parsedInput.expectedVersion,
    p_reason: parsedInput.reason,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
}

/**
 * FIN:Approve-gated (the authorized SME/finance approver). draft -> approved.
 * Rejected with no evidence attached, for the seeded illustrative example
 * fixture (can never be approved), or when it overlaps an already-approved
 * window for the same tax code/scope.
 */
export async function approveFinanceTaxRule(
  client: TaxBaselineMutationRpcClient,
  input: ApproveFinanceTaxRuleInput,
): Promise<FinanceTaxRuleVersion> {
  const parsedInput = ApproveFinanceTaxRuleInputSchema.parse(input);
  return callAndParseRule(client, "approve_finance_tax_rule", {
    p_rule_id: parsedInput.ruleId,
    p_expected_version: parsedInput.expectedVersion,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
    // ISS-2026-302: read here rather than threaded through every caller -- a security
    // control a call site can forget to pass is not a control. Null outside a request.
    p_client_ip: await resolveRequestClientIp(),
  });
}
