/**
 * Fraud and Risk Assistance contract (IAE-024, Prompt 352). Mirrors
 * supabase/migrations/20260806300000_create_intelligence_fraud_risk_assistance.sql's
 * app.risk_signals/app.risk_signal_reviews/app.risk_signal_actions shapes
 * and their request/record/decide/hold/release/get/list RPCs.
 */

import { z } from "zod";

export const RISK_DOMAINS = ["loyalty", "payment", "vendor", "ticket", "api_abuse"] as const;
export const RiskDomainSchema = z.enum(RISK_DOMAINS);
export type RiskDomain = z.infer<typeof RiskDomainSchema>;

export const RISK_SIGNAL_STATUSES = ["pending", "succeeded", "failed"] as const;
export const RiskSignalStatusSchema = z.enum(RISK_SIGNAL_STATUSES);
export type RiskSignalStatus = z.infer<typeof RiskSignalStatusSchema>;

export const RISK_BANDS = ["low", "medium", "high", "critical"] as const;
export const RiskBandSchema = z.enum(RISK_BANDS);
export type RiskBand = z.infer<typeof RiskBandSchema>;

export const RISK_REVIEW_DECISIONS = ["confirmed", "dismissed", "false_positive"] as const;
export const RiskReviewDecisionSchema = z.enum(RISK_REVIEW_DECISIONS);
export type RiskReviewDecision = z.infer<typeof RiskReviewDecisionSchema>;

/** The raw app.risk_signals row shape, as returned by request/record. */
export const RiskSignalSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  riskDomain: RiskDomainSchema,
  entityType: z.string(),
  entityId: z.string().uuid(),
  inputSnapshot: z.record(z.string(), z.unknown()),
  aiGovernedRequestId: z.string().uuid().nullable(),
  status: RiskSignalStatusSchema,
  score: z.coerce.number().nullable(),
  band: RiskBandSchema.nullable(),
  requestedBy: z.string().nullable(),
  createdAt: z.string(),
  completedAt: z.string().nullable(),
});
export type RiskSignal = z.infer<typeof RiskSignalSchema>;

export function parseRiskSignal(row: Record<string, unknown>): RiskSignal {
  return RiskSignalSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    riskDomain: row.risk_domain,
    entityType: row.entity_type,
    entityId: row.entity_id,
    inputSnapshot: row.input_snapshot,
    aiGovernedRequestId: row.ai_governed_request_id,
    status: row.status,
    score: row.score,
    band: row.band,
    requestedBy: row.requested_by,
    createdAt: row.created_at,
    completedAt: row.completed_at,
  });
}

export const RiskSignalReviewSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  riskSignalId: z.string().uuid(),
  decision: RiskReviewDecisionSchema,
  reviewerNote: z.string().nullable(),
  decidedBy: z.string().nullable(),
  decidedAt: z.string(),
});
export type RiskSignalReview = z.infer<typeof RiskSignalReviewSchema>;

export function parseRiskSignalReview(row: Record<string, unknown>): RiskSignalReview {
  return RiskSignalReviewSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    riskSignalId: row.risk_signal_id,
    decision: row.decision,
    reviewerNote: row.reviewer_note,
    decidedBy: row.decided_by,
    decidedAt: row.decided_at,
  });
}

export const RISK_SIGNAL_ACTION_STATUSES = ["active", "released"] as const;
export const RiskSignalActionStatusSchema = z.enum(RISK_SIGNAL_ACTION_STATUSES);
export type RiskSignalActionStatus = z.infer<typeof RiskSignalActionStatusSchema>;

export const RiskSignalActionSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  riskSignalId: z.string().uuid(),
  reason: z.string(),
  customerSafeReason: z.string(),
  status: RiskSignalActionStatusSchema,
  heldBy: z.string().nullable(),
  heldAt: z.string(),
  releasedBy: z.string().nullable(),
  releasedAt: z.string().nullable(),
  releaseReason: z.string().nullable(),
});
export type RiskSignalAction = z.infer<typeof RiskSignalActionSchema>;

export function parseRiskSignalAction(row: Record<string, unknown>): RiskSignalAction {
  return RiskSignalActionSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    riskSignalId: row.risk_signal_id,
    reason: row.reason,
    customerSafeReason: row.customer_safe_reason,
    status: row.status,
    heldBy: row.held_by,
    heldAt: row.held_at,
    releasedBy: row.released_by,
    releasedAt: row.released_at,
    releaseReason: row.release_reason,
  });
}

/** app.get_risk_signal's own wider read-path shape -- joins in the governed request's own evidence, review, and any active hold. */
export const RiskSignalDetailSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  riskDomain: RiskDomainSchema,
  entityType: z.string(),
  entityId: z.string().uuid(),
  inputSnapshot: z.record(z.string(), z.unknown()),
  status: RiskSignalStatusSchema,
  score: z.coerce.number().nullable(),
  band: RiskBandSchema.nullable(),
  requestedBy: z.string().nullable(),
  createdAt: z.string(),
  completedAt: z.string().nullable(),
  outputPayload: z.record(z.string(), z.unknown()).nullable(),
  confidenceLabel: z.enum(["high", "medium", "low"]).nullable(),
  modelVersion: z.string().nullable(),
  requestStatus: z.string().nullable(),
  reviewDecision: RiskReviewDecisionSchema.nullable(),
  reviewerNote: z.string().nullable(),
  decidedBy: z.string().nullable(),
  decidedAt: z.string().nullable(),
  holdStatus: RiskSignalActionStatusSchema.nullable(),
  holdReason: z.string().nullable(),
  holdCustomerSafeReason: z.string().nullable(),
  heldBy: z.string().nullable(),
  heldAt: z.string().nullable(),
});
export type RiskSignalDetail = z.infer<typeof RiskSignalDetailSchema>;

export function parseRiskSignalDetail(row: Record<string, unknown>): RiskSignalDetail {
  return RiskSignalDetailSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    riskDomain: row.risk_domain,
    entityType: row.entity_type,
    entityId: row.entity_id,
    inputSnapshot: row.input_snapshot,
    status: row.status,
    score: row.score,
    band: row.band,
    requestedBy: row.requested_by,
    createdAt: row.created_at,
    completedAt: row.completed_at,
    outputPayload: row.output_payload,
    confidenceLabel: row.confidence_label,
    modelVersion: row.model_version,
    requestStatus: row.request_status,
    reviewDecision: row.review_decision,
    reviewerNote: row.reviewer_note,
    decidedBy: row.decided_by,
    decidedAt: row.decided_at,
    holdStatus: row.hold_status,
    holdReason: row.hold_reason,
    holdCustomerSafeReason: row.hold_customer_safe_reason,
    heldBy: row.held_by,
    heldAt: row.held_at,
  });
}

export const RiskSignalSummarySchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  riskDomain: RiskDomainSchema,
  entityType: z.string(),
  entityId: z.string().uuid(),
  status: RiskSignalStatusSchema,
  score: z.coerce.number().nullable(),
  band: RiskBandSchema.nullable(),
  requestedBy: z.string().nullable(),
  createdAt: z.string(),
  reviewDecision: RiskReviewDecisionSchema.nullable(),
  holdStatus: RiskSignalActionStatusSchema.nullable(),
});
export type RiskSignalSummary = z.infer<typeof RiskSignalSummarySchema>;

export function parseRiskSignalSummary(row: Record<string, unknown>): RiskSignalSummary {
  return RiskSignalSummarySchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    riskDomain: row.risk_domain,
    entityType: row.entity_type,
    entityId: row.entity_id,
    status: row.status,
    score: row.score,
    band: row.band,
    requestedBy: row.requested_by,
    createdAt: row.created_at,
    reviewDecision: row.review_decision,
    holdStatus: row.hold_status,
  });
}

export const RequestRiskSignalInputSchema = z.object({
  tenantId: z.string().uuid(),
  riskDomain: RiskDomainSchema,
  entityType: z.string().min(1),
  entityId: z.string().uuid(),
  inputSnapshot: z.record(z.string(), z.unknown()),
  idempotencyKey: z.string().min(1),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type RequestRiskSignalInput = z.input<typeof RequestRiskSignalInputSchema>;

export const RecordRiskSignalOutcomeInputSchema = z.object({
  signalId: z.string().uuid(),
  aiGovernedRequestId: z.string().uuid(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type RecordRiskSignalOutcomeInput = z.input<typeof RecordRiskSignalOutcomeInputSchema>;

export const DecideRiskSignalInputSchema = z.object({
  signalId: z.string().uuid(),
  tenantId: z.string().uuid(),
  decision: RiskReviewDecisionSchema,
  reviewerNote: z.string().nullable().default(null),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type DecideRiskSignalInput = z.input<typeof DecideRiskSignalInputSchema>;

export const HoldRiskSignalEntityInputSchema = z.object({
  signalId: z.string().uuid(),
  tenantId: z.string().uuid(),
  reason: z.string().min(1),
  customerSafeReason: z.string().min(1),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type HoldRiskSignalEntityInput = z.input<typeof HoldRiskSignalEntityInputSchema>;

export const ReleaseRiskSignalEntityInputSchema = z.object({
  actionId: z.string().uuid(),
  tenantId: z.string().uuid(),
  releaseReason: z.string().min(1),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type ReleaseRiskSignalEntityInput = z.input<typeof ReleaseRiskSignalEntityInputSchema>;

export const GetRiskSignalInputSchema = z.object({
  signalId: z.string().uuid(),
  tenantId: z.string().uuid(),
  actorAuthUserId: z.string().uuid(),
});
export type GetRiskSignalInput = z.input<typeof GetRiskSignalInputSchema>;

export const ListRiskSignalsForTenantInputSchema = z.object({
  tenantId: z.string().uuid(),
  actorAuthUserId: z.string().uuid(),
  riskDomain: RiskDomainSchema.nullable().default(null),
  status: RiskSignalStatusSchema.nullable().default(null),
  band: RiskBandSchema.nullable().default(null),
  limit: z.number().int().positive().max(200).default(50),
});
export type ListRiskSignalsForTenantInput = z.input<typeof ListRiskSignalsForTenantInputSchema>;
