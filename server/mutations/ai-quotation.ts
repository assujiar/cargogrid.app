/**
 * AI-Assisted Quotation mutation primitives (IAE-020, Prompt 348). Thin,
 * typed wrappers around app.record_ai_quotation_suggestion /
 * app.dismiss_ai_quotation_suggestion / app.accept_ai_quotation_suggestion_as_draft
 * (supabase/migrations/20260805080000_create_intelligence_ai_assisted_quotation.sql).
 */

import {
  RecordAiQuotationSuggestionInputSchema,
  parseAiQuotationSuggestion,
  DismissAiQuotationSuggestionInputSchema,
  AcceptAiQuotationSuggestionAsDraftInputSchema,
  type RecordAiQuotationSuggestionInput,
  type AiQuotationSuggestion,
  type DismissAiQuotationSuggestionInput,
  type AcceptAiQuotationSuggestionAsDraftInput,
} from "../contracts/ai-quotation/ai-quotation.ts";
import { parseQuotation, type Quotation } from "../contracts/quotation/quotation.ts";

export interface AiQuotationMutationRpcClient {
  rpc(fn: "record_ai_quotation_suggestion" | "dismiss_ai_quotation_suggestion" | "accept_ai_quotation_suggestion_as_draft", args: Record<string, unknown>): Promise<{ data: unknown; error: { message: string } | null }>;
}

export const AI_QUOTATION_KNOWN_MUTATION_ERROR_CODES = [
  "insufficient_authority",
  "ai_quotation_suggestion_opportunity_not_found",
  "ai_quotation_suggestion_request_tenant_mismatch",
  "ai_quotation_suggestion_wrong_feature",
  "ai_quotation_suggestion_correlation_mismatch",
  "ai_quotation_suggestion_request_not_succeeded",
  "ai_quotation_suggestion_not_found",
  "ai_quotation_suggestion_not_pending",
  "ai_quotation_suggestion_low_confidence_blocked",
  "ai_quotation_suggestion_no_lines_provided",
  "ai_quotation_suggestion_missing_source",
  "ai_quotation_suggestion_invalid_limit",
] as const;
type KnownAiQuotationMutationErrorCode = (typeof AI_QUOTATION_KNOWN_MUTATION_ERROR_CODES)[number];
export type AiQuotationMutationErrorCode = KnownAiQuotationMutationErrorCode | "mutation_failed" | "invalid_response";

export class AiQuotationMutationError extends Error {
  readonly code: AiQuotationMutationErrorCode;

  constructor(code: AiQuotationMutationErrorCode, message: string) {
    super(message);
    this.name = "AiQuotationMutationError";
    this.code = code;
  }
}

function classifyError(message: string): AiQuotationMutationErrorCode {
  const prefix = message.split(":")[0]?.trim();
  return (AI_QUOTATION_KNOWN_MUTATION_ERROR_CODES as readonly string[]).includes(prefix ?? "") ? (prefix as KnownAiQuotationMutationErrorCode) : "mutation_failed";
}

/** Called by the AI-dispatch orchestration client AFTER a real, succeeded dispatchAiGovernedRequest round trip -- never before. Idempotent per ai_governed_request_id. */
export async function recordAiQuotationSuggestion(client: AiQuotationMutationRpcClient, input: RecordAiQuotationSuggestionInput): Promise<AiQuotationSuggestion> {
  const parsedInput = RecordAiQuotationSuggestionInputSchema.parse(input);
  const { data, error } = await client.rpc("record_ai_quotation_suggestion", {
    p_tenant_id: parsedInput.tenantId,
    p_opportunity_id: parsedInput.opportunityId,
    p_ai_governed_request_id: parsedInput.aiGovernedRequestId,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new AiQuotationMutationError(classifyError(error.message), error.message);
  }
  if (!data || typeof data !== "object") {
    throw new AiQuotationMutationError("invalid_response", "record_ai_quotation_suggestion returned no row");
  }
  return parseAiQuotationSuggestion(data as Record<string, unknown>);
}

/** Atomic pending-only transition -- raises ai_quotation_suggestion_not_pending if the suggestion was already accepted or dismissed by a concurrent actor. */
export async function dismissAiQuotationSuggestion(client: AiQuotationMutationRpcClient, input: DismissAiQuotationSuggestionInput): Promise<AiQuotationSuggestion> {
  const parsedInput = DismissAiQuotationSuggestionInputSchema.parse(input);
  const { data, error } = await client.rpc("dismiss_ai_quotation_suggestion", {
    p_suggestion_id: parsedInput.suggestionId,
    p_reason: parsedInput.reason,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new AiQuotationMutationError(classifyError(error.message), error.message);
  }
  if (!data || typeof data !== "object") {
    throw new AiQuotationMutationError("invalid_response", "dismiss_ai_quotation_suggestion returned no row");
  }
  return parseAiQuotationSuggestion(data as Record<string, unknown>);
}

/** The ONLY path from an AI suggestion into a real app.quotations row. Blocks low-confidence/no-source acceptance; every accepted line is handed unchanged to the existing, unmodified app.create_quotation_draft/app.add_quotation_line. Returns the real, unmasked quotation. */
export async function acceptAiQuotationSuggestionAsDraft(client: AiQuotationMutationRpcClient, input: AcceptAiQuotationSuggestionAsDraftInput): Promise<Quotation> {
  const parsedInput = AcceptAiQuotationSuggestionAsDraftInputSchema.parse(input);
  const { data, error } = await client.rpc("accept_ai_quotation_suggestion_as_draft", {
    p_suggestion_id: parsedInput.suggestionId,
    p_currency: parsedInput.currency,
    p_validity_to: parsedInput.validityTo,
    p_contact_id: parsedInput.contactId,
    p_owner_user_id: parsedInput.ownerUserId,
    p_org_unit_id: parsedInput.orgUnitId,
    p_accepted_lines: parsedInput.acceptedLines.map((line) => ({
      line_type: line.lineType,
      description: line.description,
      margin_calculation_id: line.marginCalculationId,
      quantity: line.quantity,
      unit_price: line.unitPrice,
      discount_pct: line.discountPct ?? 0,
      tax_pct: line.taxPct ?? 0,
    })),
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new AiQuotationMutationError(classifyError(error.message), error.message);
  }
  if (!data || typeof data !== "object") {
    throw new AiQuotationMutationError("invalid_response", "accept_ai_quotation_suggestion_as_draft returned no row");
  }
  return parseQuotation(data as Record<string, unknown>);
}
