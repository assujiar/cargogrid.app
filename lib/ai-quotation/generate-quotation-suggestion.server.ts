/**
 * AI-assisted quotation suggestion orchestration (IAE-020, Prompt 348). The
 * FIRST real consumer of IAE-019's own `dispatchAiGovernedRequest` -- reused
 * completely unmodified (migration design decision 6). This module's only
 * job is to assemble a real prompt from EXISTING, already-tested read
 * functions (opportunity, costing request, margin calculation) citing real,
 * versioned source ids, dispatch it, and -- only on a real, succeeded
 * outcome -- track it via `recordAiQuotationSuggestion`. It never writes to
 * `app.quotations`/`app.quotation_lines` itself; that only ever happens
 * later, when a human explicitly calls `acceptAiQuotationSuggestionAsDraft`
 * (server/mutations/ai-quotation.ts) with their own reviewed line data.
 *
 * Must be called with a service-role client: `dispatchAiGovernedRequest`'s
 * own internal `record_ai_governed_request_outcome` call is granted to
 * `service_role` only (IAE-019).
 */

import { getOpportunityById, type OpportunityQueryTableClient } from "../../server/queries/opportunity.ts";
import { listCostingRequestsForOpportunity, type CostingQueryTableClient } from "../../server/queries/costing.ts";
import { listMarginCalculationsForRequest, type MarginQueryTableClient } from "../../server/queries/margin.ts";
import { recordAiQuotationSuggestion, type AiQuotationMutationRpcClient } from "../../server/mutations/ai-quotation.ts";
import type { AiQuotationSuggestion } from "../../server/contracts/ai-quotation/ai-quotation.ts";
import { dispatchAiGovernedRequest, type DispatchAiGovernedRequestRpcClient, type AiGovernanceDispatchUrlSafetyChecker } from "../ai-governance/dispatch-ai-governed-request.server.ts";

export type GenerateAiQuotationSuggestionClient = OpportunityQueryTableClient & CostingQueryTableClient & MarginQueryTableClient & DispatchAiGovernedRequestRpcClient & AiQuotationMutationRpcClient;

export interface GenerateAiQuotationSuggestionOptions {
  readonly tenantId: string;
  readonly opportunityId: string;
  readonly actorAuthUserId: string;
  readonly actorLabel: string;
}

export interface GenerateAiQuotationSuggestionResult {
  readonly requestId: string;
  readonly success: boolean;
  /** Only set when success is true -- a real, tracked app.ai_quotation_suggestions row. */
  readonly suggestion: AiQuotationSuggestion | null;
  readonly errorMessage: string | null;
}

export class GenerateAiQuotationSuggestionError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "GenerateAiQuotationSuggestionError";
  }
}

/**
 * Real, synchronous end-to-end flow: build a sourced prompt -> dispatch ->
 * (on success) track. Never throws for a delivery-side failure (no
 * connection, HTTP error, low confidence, etc.) -- `dispatchAiGovernedRequest`
 * itself already turns those into a real, recorded `failed` outcome and a
 * `success: false` result, which this function passes through unchanged.
 * Throws only for a genuine precondition failure (opportunity not found) or
 * whatever `dispatchAiGovernedRequest` itself still throws for (no active
 * connection configured at all -- a tenant setup error, not a per-request
 * outcome, per IAE-019's own established behavior).
 */
export async function generateAiQuotationSuggestion(client: GenerateAiQuotationSuggestionClient, options: GenerateAiQuotationSuggestionOptions, checkUrlSafety?: AiGovernanceDispatchUrlSafetyChecker): Promise<GenerateAiQuotationSuggestionResult> {
  const { tenantId, opportunityId, actorAuthUserId, actorLabel } = options;

  const opportunity = await getOpportunityById(client, opportunityId);
  if (!opportunity || opportunity.tenantId !== tenantId) {
    throw new GenerateAiQuotationSuggestionError(`opportunity ${opportunityId} not found for tenant ${tenantId}`);
  }

  const costingRequests = await listCostingRequestsForOpportunity(client, opportunityId);
  const latestCostingRequest = costingRequests[0] ?? null;

  // Only CURRENT margin calculations are ever cited as source evidence --
  // a superseded calculation is never a canonical source (Prompt 348 §24).
  const marginCalculations = latestCostingRequest ? (await listMarginCalculationsForRequest(client, latestCostingRequest.id)).filter((calculation) => calculation.isCurrent) : [];

  const promptPayload: Record<string, unknown> = {
    opportunity: {
      id: opportunity.id,
      name: opportunity.name,
      stage: opportunity.stage,
      valueAmount: opportunity.valueAmount,
      valueCurrency: opportunity.valueCurrency,
      requirements: opportunity.requirements,
    },
    costingRequestId: latestCostingRequest?.id ?? null,
    // Deliberately empty when there is no current costing/margin evidence
    // yet -- never fabricated. A prompt with zero sources here is exactly
    // the real-world case the AI provider is expected to answer with a low
    // confidence label, which `acceptAiQuotationSuggestionAsDraft` then
    // structurally blocks from becoming a draft (Prompt 348 §22).
    marginCalculations: marginCalculations.map((calculation) => ({
      marginCalculationId: calculation.id,
      rateSelectionId: calculation.rateSelectionId,
      ruleVersionId: calculation.ruleVersionId,
      sellAmount: calculation.sellAmount,
      sellCurrency: calculation.sellCurrency,
      marginPct: calculation.marginPct,
    })),
  };

  const dispatch = await dispatchAiGovernedRequest(
    client,
    {
      tenantId,
      actorAuthUserId,
      actorLabel,
      featureCode: "ai_assisted_quotation",
      correlationRecordType: "opportunity",
      correlationRecordId: opportunityId,
      promptPayload,
    },
    checkUrlSafety,
  );

  if (!dispatch.success) {
    return { requestId: dispatch.requestId, success: false, suggestion: null, errorMessage: dispatch.errorMessage };
  }

  const suggestion = await recordAiQuotationSuggestion(client, {
    tenantId,
    opportunityId,
    aiGovernedRequestId: dispatch.requestId,
    actorAuthUserId,
    actorLabel,
  });

  return { requestId: dispatch.requestId, success: true, suggestion, errorMessage: null };
}
