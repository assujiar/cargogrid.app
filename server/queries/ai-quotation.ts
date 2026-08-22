/**
 * AI-Assisted Quotation queries (IAE-020, Prompt 348). Thin, typed wrappers
 * around app.get_ai_quotation_suggestion / app.list_ai_quotation_suggestions_for_opportunity
 * (supabase/migrations/20260805080000_create_intelligence_ai_assisted_quotation.sql).
 */

import {
  GetAiQuotationSuggestionInputSchema,
  ListAiQuotationSuggestionsForOpportunityInputSchema,
  GetAiQuotationPromptContextInputSchema,
  parseAiQuotationSuggestionDetail,
  parseAiQuotationPromptContext,
  type GetAiQuotationSuggestionInput,
  type ListAiQuotationSuggestionsForOpportunityInput,
  type GetAiQuotationPromptContextInput,
  type AiQuotationSuggestionDetail,
  type AiQuotationPromptContext,
} from "../contracts/ai-quotation/ai-quotation.ts";

export interface AiQuotationQueryRpcClient {
  rpc(
    fn: "get_ai_quotation_suggestion" | "list_ai_quotation_suggestions_for_opportunity" | "get_ai_quotation_prompt_context",
    args: Record<string, unknown>,
  ): Promise<{ data: unknown; error: { message: string } | null }>;
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

/**
 * Tier C fix (IAE-020's own review): the AI-dispatch orchestration client's own explicit-actor
 * read of opportunity/costing/margin context -- never relies on auth.uid() (NULL for the
 * service-role client that call must use per IAE-019). Authority: COM:Create (the same gate
 * recordAiQuotationSuggestion itself requires). Cost/margin fields are null unless the actor
 * holds COM:View cost. Returns null only if the opportunity does not exist/belong to the tenant.
 */
export async function getAiQuotationPromptContext(client: AiQuotationQueryRpcClient, input: GetAiQuotationPromptContextInput): Promise<AiQuotationPromptContext | null> {
  const parsedInput = GetAiQuotationPromptContextInputSchema.parse(input);
  const { data, error } = await client.rpc("get_ai_quotation_prompt_context", {
    p_tenant_id: parsedInput.tenantId,
    p_opportunity_id: parsedInput.opportunityId,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
  });
  if (error) {
    throw new AiQuotationQueryError(error.message);
  }
  if (!Array.isArray(data)) {
    throw new AiQuotationQueryError("get_ai_quotation_prompt_context returned a non-array result");
  }
  return parseAiQuotationPromptContext(data as Record<string, unknown>[]);
}
