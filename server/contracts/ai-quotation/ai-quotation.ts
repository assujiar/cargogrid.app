/**
 * AI-Assisted Quotation contract (IAE-020, Prompt 348). Mirrors
 * supabase/migrations/20260805080000_create_intelligence_ai_assisted_quotation.sql's
 * app.ai_quotation_suggestions shape and its record/get/list/dismiss/accept RPCs.
 */

import { z } from "zod";

export const AI_QUOTATION_SUGGESTION_STATUSES = ["pending", "accepted", "dismissed"] as const;
export const AiQuotationSuggestionStatusSchema = z.enum(AI_QUOTATION_SUGGESTION_STATUSES);
export type AiQuotationSuggestionStatus = z.infer<typeof AiQuotationSuggestionStatusSchema>;

/** The raw app.ai_quotation_suggestions row shape, as returned by record/dismiss. */
export const AiQuotationSuggestionSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  opportunityId: z.string().uuid(),
  aiGovernedRequestId: z.string().uuid(),
  status: AiQuotationSuggestionStatusSchema,
  acceptedQuotationId: z.string().uuid().nullable(),
  dismissReason: z.string().nullable(),
  requestedByAuthUserId: z.string().uuid().nullable(),
  requestedBy: z.string().nullable(),
  reviewedByAuthUserId: z.string().uuid().nullable(),
  reviewedBy: z.string().nullable(),
  reviewedAt: z.string().nullable(),
  createdAt: z.string(),
});
export type AiQuotationSuggestion = z.infer<typeof AiQuotationSuggestionSchema>;

export function parseAiQuotationSuggestion(row: Record<string, unknown>): AiQuotationSuggestion {
  return AiQuotationSuggestionSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    opportunityId: row.opportunity_id,
    aiGovernedRequestId: row.ai_governed_request_id,
    status: row.status,
    acceptedQuotationId: row.accepted_quotation_id,
    dismissReason: row.dismiss_reason,
    requestedByAuthUserId: row.requested_by_auth_user_id,
    requestedBy: row.requested_by,
    reviewedByAuthUserId: row.reviewed_by_auth_user_id,
    reviewedBy: row.reviewed_by,
    reviewedAt: row.reviewed_at,
    createdAt: row.created_at,
  });
}

/** The get/list read-path shape -- joins in the underlying governed request's own evidence (never editable here, IAE-019's own table). */
export const AiQuotationSuggestionDetailSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  opportunityId: z.string().uuid(),
  aiGovernedRequestId: z.string().uuid(),
  status: AiQuotationSuggestionStatusSchema,
  acceptedQuotationId: z.string().uuid().nullable(),
  dismissReason: z.string().nullable(),
  requestedBy: z.string().nullable(),
  reviewedBy: z.string().nullable(),
  reviewedAt: z.string().nullable(),
  createdAt: z.string(),
  outputPayload: z.record(z.string(), z.unknown()).nullable(),
  /** Tier C fix (IAE-020's own review): true when outputPayload was nulled out because this actor lacks COM:View cost -- mirrors app.quotation_lines_directory's own sellMasked/costMasked naming convention. */
  outputPayloadMasked: z.boolean(),
  confidenceLabel: z.enum(["high", "medium", "low"]).nullable(),
  modelVersion: z.string().nullable(),
  billedAmount: z.number().nullable(),
  requestStatus: z.string(),
});
export type AiQuotationSuggestionDetail = z.infer<typeof AiQuotationSuggestionDetailSchema>;

export function parseAiQuotationSuggestionDetail(row: Record<string, unknown>): AiQuotationSuggestionDetail {
  return AiQuotationSuggestionDetailSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    opportunityId: row.opportunity_id,
    aiGovernedRequestId: row.ai_governed_request_id,
    status: row.status,
    acceptedQuotationId: row.accepted_quotation_id,
    dismissReason: row.dismiss_reason,
    requestedBy: row.requested_by,
    reviewedBy: row.reviewed_by,
    reviewedAt: row.reviewed_at,
    createdAt: row.created_at,
    outputPayload: row.output_payload,
    outputPayloadMasked: row.output_payload_masked,
    confidenceLabel: row.confidence_label,
    modelVersion: row.model_version,
    billedAmount: row.billed_amount,
    requestStatus: row.request_status,
  });
}

export const RecordAiQuotationSuggestionInputSchema = z.object({
  tenantId: z.string().uuid(),
  opportunityId: z.string().uuid(),
  aiGovernedRequestId: z.string().uuid(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type RecordAiQuotationSuggestionInput = z.input<typeof RecordAiQuotationSuggestionInputSchema>;

export const GetAiQuotationSuggestionInputSchema = z.object({
  suggestionId: z.string().uuid(),
  actorAuthUserId: z.string().uuid(),
});
export type GetAiQuotationSuggestionInput = z.input<typeof GetAiQuotationSuggestionInputSchema>;

export const ListAiQuotationSuggestionsForOpportunityInputSchema = z.object({
  tenantId: z.string().uuid(),
  opportunityId: z.string().uuid(),
  actorAuthUserId: z.string().uuid(),
  limit: z.number().int().positive().max(200).default(50),
});
export type ListAiQuotationSuggestionsForOpportunityInput = z.input<typeof ListAiQuotationSuggestionsForOpportunityInputSchema>;

export const DismissAiQuotationSuggestionInputSchema = z.object({
  suggestionId: z.string().uuid(),
  reason: z.string().min(1),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type DismissAiQuotationSuggestionInput = z.input<typeof DismissAiQuotationSuggestionInputSchema>;

/** One human-reviewed line -- explicitly typed, never derived by parsing the AI's own output_payload (migration design decision 1). */
export const AcceptedQuotationLineSchema = z.object({
  lineType: z.enum(["service", "surcharge", "fee", "discount"]),
  description: z.string().min(1),
  marginCalculationId: z.string().uuid(),
  quantity: z.number().nonnegative(),
  unitPrice: z.number().nonnegative(),
  discountPct: z.number().min(0).max(100).default(0),
  taxPct: z.number().min(0).max(100).default(0),
});
export type AcceptedQuotationLine = z.input<typeof AcceptedQuotationLineSchema>;

export const AcceptAiQuotationSuggestionAsDraftInputSchema = z.object({
  suggestionId: z.string().uuid(),
  currency: z.string().regex(/^[A-Z]{3}$/),
  validityTo: z.string(),
  contactId: z.string().uuid().nullable().default(null),
  ownerUserId: z.string().uuid().nullable().default(null),
  orgUnitId: z.string().uuid().nullable().default(null),
  acceptedLines: z.array(AcceptedQuotationLineSchema).min(1),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type AcceptAiQuotationSuggestionAsDraftInput = z.input<typeof AcceptAiQuotationSuggestionAsDraftInputSchema>;

export const GetAiQuotationPromptContextInputSchema = z.object({
  tenantId: z.string().uuid(),
  opportunityId: z.string().uuid(),
  actorAuthUserId: z.string().uuid(),
});
export type GetAiQuotationPromptContextInput = z.input<typeof GetAiQuotationPromptContextInputSchema>;

/** One row per current margin calculation for the opportunity's own latest costing request -- the real, versioned source evidence handed to the AI provider. Tier C fix (IAE-020's own review): reads via an explicit actor, never auth.uid() (NULL for the service-role client this capability's own dispatch must use). */
export const AiQuotationMarginSourceSchema = z.object({
  marginCalculationId: z.string().uuid(),
  rateSelectionId: z.string().uuid(),
  ruleVersionId: z.string().uuid(),
  sellAmount: z.coerce.number().nullable(),
  sellCurrency: z.string().nullable(),
  marginPct: z.coerce.number().nullable(),
});
export type AiQuotationMarginSource = z.infer<typeof AiQuotationMarginSourceSchema>;

export const AiQuotationPromptContextSchema = z.object({
  opportunityName: z.string(),
  opportunityStage: z.string(),
  opportunityValueAmount: z.coerce.number().nullable(),
  opportunityValueCurrency: z.string().nullable(),
  opportunityRequirements: z.record(z.string(), z.unknown()),
  costingRequestId: z.string().uuid().nullable(),
  marginSources: z.array(AiQuotationMarginSourceSchema),
});
export type AiQuotationPromptContext = z.infer<typeof AiQuotationPromptContextSchema>;

export function parseAiQuotationPromptContext(rows: Record<string, unknown>[]): AiQuotationPromptContext | null {
  if (rows.length === 0) {
    return null;
  }
  const [header] = rows;
  return AiQuotationPromptContextSchema.parse({
    opportunityName: header!.opportunity_name,
    opportunityStage: header!.opportunity_stage,
    opportunityValueAmount: header!.opportunity_value_amount,
    opportunityValueCurrency: header!.opportunity_value_currency,
    opportunityRequirements: header!.opportunity_requirements ?? {},
    costingRequestId: header!.costing_request_id,
    marginSources: rows
      .filter((row) => row.margin_calculation_id !== null)
      .map((row) => ({
        marginCalculationId: row.margin_calculation_id,
        rateSelectionId: row.rate_selection_id,
        ruleVersionId: row.rule_version_id,
        sellAmount: row.sell_amount,
        sellCurrency: row.sell_currency,
        marginPct: row.margin_pct,
      })),
  });
}
