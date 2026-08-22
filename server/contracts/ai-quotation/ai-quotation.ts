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
