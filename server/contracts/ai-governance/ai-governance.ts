/**
 * AI Governance Provider Boundary contract (IAE-019, Prompt 347). Mirrors
 * supabase/migrations/
 * 20260805060000_create_intelligence_ai_governance_provider_boundary.sql's
 * app.ai_governed_requests shape and its request/outcome/approval/list RPCs.
 */

import { z } from "zod";

export const AI_GOVERNED_REQUEST_STATUSES = ["pending", "succeeded", "failed"] as const;
export const AiGovernedRequestStatusSchema = z.enum(AI_GOVERNED_REQUEST_STATUSES);
export type AiGovernedRequestStatus = z.infer<typeof AiGovernedRequestStatusSchema>;

export const AI_CONFIDENCE_LABELS = ["high", "medium", "low"] as const;
export const AiConfidenceLabelSchema = z.enum(AI_CONFIDENCE_LABELS);
export type AiConfidenceLabel = z.infer<typeof AiConfidenceLabelSchema>;

export const AiGovernedRequestSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  connectionId: z.string().uuid(),
  featureCode: z.string(),
  correlationRecordType: z.string().nullable(),
  correlationRecordId: z.string().uuid().nullable(),
  promptPayload: z.record(z.string(), z.unknown()),
  status: AiGovernedRequestStatusSchema,
  outputPayload: z.record(z.string(), z.unknown()).nullable(),
  confidenceLabel: AiConfidenceLabelSchema.nullable(),
  modelVersion: z.string().nullable(),
  providerUnitCostAmount: z.number().nullable(),
  currency: z.string().nullable(),
  billedAmount: z.number().nullable(),
  errorMessage: z.string().nullable(),
  approvalRequestId: z.string().uuid().nullable(),
  requestedByAuthUserId: z.string().uuid().nullable(),
  requestedBy: z.string().nullable(),
  createdAt: z.string(),
  completedAt: z.string().nullable(),
});
export type AiGovernedRequest = z.infer<typeof AiGovernedRequestSchema>;

export function parseAiGovernedRequest(row: Record<string, unknown>): AiGovernedRequest {
  return AiGovernedRequestSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    connectionId: row.connection_id,
    featureCode: row.feature_code,
    correlationRecordType: row.correlation_record_type,
    correlationRecordId: row.correlation_record_id,
    promptPayload: row.prompt_payload,
    status: row.status,
    outputPayload: row.output_payload,
    confidenceLabel: row.confidence_label,
    modelVersion: row.model_version,
    providerUnitCostAmount: row.provider_unit_cost_amount,
    currency: row.currency,
    billedAmount: row.billed_amount,
    errorMessage: row.error_message,
    approvalRequestId: row.approval_request_id,
    requestedByAuthUserId: row.requested_by_auth_user_id,
    requestedBy: row.requested_by,
    createdAt: row.created_at,
    completedAt: row.completed_at,
  });
}

export const RequestAiGovernedActionInputSchema = z.object({
  tenantId: z.string().uuid(),
  connectionId: z.string().uuid(),
  featureCode: z.string().min(1),
  correlationRecordType: z.string().nullable().default(null),
  correlationRecordId: z.string().uuid().nullable().default(null),
  promptPayload: z.record(z.string(), z.unknown()),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type RequestAiGovernedActionInput = z.input<typeof RequestAiGovernedActionInputSchema>;

export const RecordAiGovernedRequestOutcomeInputSchema = z.object({
  requestId: z.string().uuid(),
  status: z.enum(["succeeded", "failed"]),
  outputPayload: z.record(z.string(), z.unknown()).nullable().default(null),
  confidenceLabel: AiConfidenceLabelSchema.nullable().default(null),
  modelVersion: z.string().nullable().default(null),
  providerUnitCostAmount: z.number().nonnegative().nullable().default(null),
  currency: z.string().nullable().default(null),
  errorMessage: z.string().nullable().default(null),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type RecordAiGovernedRequestOutcomeInput = z.input<typeof RecordAiGovernedRequestOutcomeInputSchema>;

export const ListAiGovernedRequestsForTenantInputSchema = z.object({
  tenantId: z.string().uuid(),
  actorAuthUserId: z.string().uuid(),
  featureCode: z.string().nullable().default(null),
  limit: z.number().int().positive().max(200).default(50),
});
export type ListAiGovernedRequestsForTenantInput = z.input<typeof ListAiGovernedRequestsForTenantInputSchema>;

export const RequestAiOutputApprovalInputSchema = z.object({
  requestId: z.string().uuid(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type RequestAiOutputApprovalInput = z.input<typeof RequestAiOutputApprovalInputSchema>;

export const DecideAiOutputApprovalInputSchema = z.object({
  requestStepId: z.string().uuid(),
  decision: z.enum(["approved", "rejected"]),
  reason: z.string().nullable().default(null),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
  clientIp: z.string().nullable().default(null),
});
export type DecideAiOutputApprovalInput = z.input<typeof DecideAiOutputApprovalInputSchema>;

/** The real dispatch client's own minimal read -- never the raw credential. */
export const AiGovernedDispatchInfoSchema = z.object({
  connectionId: z.string().uuid(),
  connectionStatus: z.string(),
  connectionConfig: z.record(z.string(), z.unknown()),
});
export type AiGovernedDispatchInfo = z.infer<typeof AiGovernedDispatchInfoSchema>;

export function parseAiGovernedDispatchInfo(row: Record<string, unknown>): AiGovernedDispatchInfo {
  return AiGovernedDispatchInfoSchema.parse({
    connectionId: row.connection_id,
    connectionStatus: row.connection_status,
    connectionConfig: row.connection_config,
  });
}
