/**
 * AI-Assisted Quotation queries (IAE-020, Prompt 348). Thin, typed wrappers
 * around app.get_ai_quotation_suggestion / app.list_ai_quotation_suggestions_for_opportunity
 * (supabase/migrations/20260805080000_create_intelligence_ai_assisted_quotation.sql).
 */

import {
  GetAiQuotationSuggestionInputSchema,
  ListAiQuotationSuggestionsForOpportunityInputSchema,
  parseAiQuotationSuggestionDetail,
  type GetAiQuotationSuggestionInput,
  type ListAiQuotationSuggestionsForOpportunityInput,
  type AiQuotationSuggestionDetail,
} from "../contracts/ai-quotation/ai-quotation.ts";

export interface AiQuotationQueryRpcClient {
  rpc(fn: "get_ai_quotation_suggestion" | "list_ai_quotation_suggestions_for_opportunity", args: Record<string, unknown>): Promise<{ data: unknown; error: { message: string } | null }>;
}

export class AiQuotationQueryError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "AiQuotationQueryError";
  }
}

/** Authority: COM:View. Returns null if the suggestion does not exist (never distinguishes "not found" from "not authorized" beyond the RPC's own error). */
export async function getAiQuotationSuggestion(client: AiQuotationQueryRpcClient, input: GetAiQuotationSuggestionInput): Promise<AiQuotationSuggestionDetail | null> {
  const parsedInput = GetAiQuotationSuggestionInputSchema.parse(input);
  const { data, error } = await client.rpc("get_ai_quotation_suggestion", {
    p_suggestion_id: parsedInput.suggestionId,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
  });
  if (error) {
    throw new AiQuotationQueryError(error.message);
  }
  const row = Array.isArray(data) ? data[0] : data;
  if (!row || typeof row !== "object") {
    return null;
  }
  return parseAiQuotationSuggestionDetail(row as Record<string, unknown>);
}

/** Authority: COM:View. */
export async function listAiQuotationSuggestionsForOpportunity(client: AiQuotationQueryRpcClient, input: ListAiQuotationSuggestionsForOpportunityInput): Promise<AiQuotationSuggestionDetail[]> {
  const parsedInput = ListAiQuotationSuggestionsForOpportunityInputSchema.parse(input);
  const { data, error } = await client.rpc("list_ai_quotation_suggestions_for_opportunity", {
    p_tenant_id: parsedInput.tenantId,
    p_opportunity_id: parsedInput.opportunityId,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_limit: parsedInput.limit,
  });
  if (error) {
    throw new AiQuotationQueryError(error.message);
  }
  if (!Array.isArray(data)) {
    throw new AiQuotationQueryError("list_ai_quotation_suggestions_for_opportunity returned a non-array result");
  }
  return data.map((row) => parseAiQuotationSuggestionDetail(row as Record<string, unknown>));
}
