/**
 * Optimization Assistance contract (IAE-023, Prompt 351). Mirrors
 * supabase/migrations/20260806200000_create_intelligence_optimization_assistance.sql's
 * app.optimization_scenarios/app.optimization_scenario_decisions shapes and
 * their request/record/stale/decide/acknowledge/get/list RPCs.
 */

import { z } from "zod";

export const OPTIMIZATION_SCOPE_TYPES = ["route", "dispatch", "warehouse_slotting", "picking"] as const;
export const OptimizationScopeTypeSchema = z.enum(OPTIMIZATION_SCOPE_TYPES);
export type OptimizationScopeType = z.infer<typeof OptimizationScopeTypeSchema>;

export const OPTIMIZATION_SCENARIO_STATUSES = ["pending", "succeeded", "failed"] as const;
export const OptimizationScenarioStatusSchema = z.enum(OPTIMIZATION_SCENARIO_STATUSES);
export type OptimizationScenarioStatus = z.infer<typeof OptimizationScenarioStatusSchema>;

export const OPTIMIZATION_DECISIONS = ["accepted", "rejected"] as const;
export const OptimizationDecisionSchema = z.enum(OPTIMIZATION_DECISIONS);
export type OptimizationDecision = z.infer<typeof OptimizationDecisionSchema>;

/** The raw app.optimization_scenarios row shape, as returned by request/record. */
export const OptimizationScenarioSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  scopeType: OptimizationScopeTypeSchema,
  inputSnapshot: z.record(z.string(), z.unknown()),
  constraintSet: z.record(z.string(), z.unknown()),
  aiGovernedRequestId: z.string().uuid().nullable(),
  status: OptimizationScenarioStatusSchema,
  isStale: z.boolean(),
  staleReason: z.string().nullable(),
  requestedBy: z.string().nullable(),
  createdAt: z.string(),
  completedAt: z.string().nullable(),
});
export type OptimizationScenario = z.infer<typeof OptimizationScenarioSchema>;

export function parseOptimizationScenario(row: Record<string, unknown>): OptimizationScenario {
  return OptimizationScenarioSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    scopeType: row.scope_type,
    inputSnapshot: row.input_snapshot,
    constraintSet: row.constraint_set,
    aiGovernedRequestId: row.ai_governed_request_id,
    status: row.status,
    isStale: row.is_stale,
    staleReason: row.stale_reason,
    requestedBy: row.requested_by,
    createdAt: row.created_at,
    completedAt: row.completed_at,
  });
}

/** The raw app.optimization_scenario_decisions row shape. */
export const OptimizationScenarioDecisionSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  scenarioId: z.string().uuid(),
  decision: OptimizationDecisionSchema,
  selectedOptionIndex: z.number().int().nullable(),
  decisionNote: z.string().nullable(),
  decidedBy: z.string().nullable(),
  decidedAt: z.string(),
  appliedAcknowledged: z.boolean(),
  appliedReference: z.string().nullable(),
  appliedAcknowledgedBy: z.string().nullable(),
  appliedAcknowledgedAt: z.string().nullable(),
});
export type OptimizationScenarioDecision = z.infer<typeof OptimizationScenarioDecisionSchema>;

export function parseOptimizationScenarioDecision(row: Record<string, unknown>): OptimizationScenarioDecision {
  return OptimizationScenarioDecisionSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    scenarioId: row.scenario_id,
    decision: row.decision,
    selectedOptionIndex: row.selected_option_index,
    decisionNote: row.decision_note,
    decidedBy: row.decided_by,
    decidedAt: row.decided_at,
    appliedAcknowledged: row.applied_acknowledged,
    appliedReference: row.applied_reference,
    appliedAcknowledgedBy: row.applied_acknowledged_by,
    appliedAcknowledgedAt: row.applied_acknowledged_at,
  });
}

/** app.get_optimization_scenario's own wider read-path shape -- joins in the governed request's own (possibly masked) evidence plus any decision. */
export const OptimizationScenarioDetailSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  scopeType: OptimizationScopeTypeSchema,
  inputSnapshot: z.record(z.string(), z.unknown()),
  constraintSet: z.record(z.string(), z.unknown()),
  status: OptimizationScenarioStatusSchema,
  isStale: z.boolean(),
  staleReason: z.string().nullable(),
  requestedBy: z.string().nullable(),
  createdAt: z.string(),
  completedAt: z.string().nullable(),
  outputPayload: z.record(z.string(), z.unknown()).nullable(),
  outputPayloadMasked: z.boolean(),
  confidenceLabel: z.enum(["high", "medium", "low"]).nullable(),
  modelVersion: z.string().nullable(),
  requestStatus: z.string().nullable(),
  decision: OptimizationDecisionSchema.nullable(),
  selectedOptionIndex: z.number().int().nullable(),
  decisionNote: z.string().nullable(),
  decidedBy: z.string().nullable(),
  decidedAt: z.string().nullable(),
  appliedAcknowledged: z.boolean().nullable(),
  appliedReference: z.string().nullable(),
});
export type OptimizationScenarioDetail = z.infer<typeof OptimizationScenarioDetailSchema>;

export function parseOptimizationScenarioDetail(row: Record<string, unknown>): OptimizationScenarioDetail {
  return OptimizationScenarioDetailSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    scopeType: row.scope_type,
    inputSnapshot: row.input_snapshot,
    constraintSet: row.constraint_set,
    status: row.status,
    isStale: row.is_stale,
    staleReason: row.stale_reason,
    requestedBy: row.requested_by,
    createdAt: row.created_at,
    completedAt: row.completed_at,
    outputPayload: row.output_payload,
    outputPayloadMasked: row.output_payload_masked,
    confidenceLabel: row.confidence_label,
    modelVersion: row.model_version,
    requestStatus: row.request_status,
    decision: row.decision,
    selectedOptionIndex: row.selected_option_index,
    decisionNote: row.decision_note,
    decidedBy: row.decided_by,
    decidedAt: row.decided_at,
    appliedAcknowledged: row.applied_acknowledged,
    appliedReference: row.applied_reference,
  });
}

export const OptimizationScenarioSummarySchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  scopeType: OptimizationScopeTypeSchema,
  status: OptimizationScenarioStatusSchema,
  isStale: z.boolean(),
  requestedBy: z.string().nullable(),
  createdAt: z.string(),
  confidenceLabel: z.enum(["high", "medium", "low"]).nullable(),
  decision: OptimizationDecisionSchema.nullable(),
});
export type OptimizationScenarioSummary = z.infer<typeof OptimizationScenarioSummarySchema>;

export function parseOptimizationScenarioSummary(row: Record<string, unknown>): OptimizationScenarioSummary {
  return OptimizationScenarioSummarySchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    scopeType: row.scope_type,
    status: row.status,
    isStale: row.is_stale,
    requestedBy: row.requested_by,
    createdAt: row.created_at,
    confidenceLabel: row.confidence_label,
    decision: row.decision,
  });
}

export const RequestOptimizationScenarioInputSchema = z.object({
  tenantId: z.string().uuid(),
  scopeType: OptimizationScopeTypeSchema,
  inputSnapshot: z.record(z.string(), z.unknown()),
  constraintSet: z.record(z.string(), z.unknown()),
  idempotencyKey: z.string().min(1),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type RequestOptimizationScenarioInput = z.input<typeof RequestOptimizationScenarioInputSchema>;

export const RecordOptimizationScenarioOutcomeInputSchema = z.object({
  scenarioId: z.string().uuid(),
  aiGovernedRequestId: z.string().uuid(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type RecordOptimizationScenarioOutcomeInput = z.input<typeof RecordOptimizationScenarioOutcomeInputSchema>;

export const MarkOptimizationScenarioStaleInputSchema = z.object({
  scenarioId: z.string().uuid(),
  tenantId: z.string().uuid(),
  reason: z.string().min(1),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type MarkOptimizationScenarioStaleInput = z.input<typeof MarkOptimizationScenarioStaleInputSchema>;

export const DecideOptimizationScenarioInputSchema = z.object({
  scenarioId: z.string().uuid(),
  tenantId: z.string().uuid(),
  decision: OptimizationDecisionSchema,
  selectedOptionIndex: z.number().int().nonnegative().nullable().default(null),
  decisionNote: z.string().nullable().default(null),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type DecideOptimizationScenarioInput = z.input<typeof DecideOptimizationScenarioInputSchema>;

export const AcknowledgeOptimizationRecommendationAppliedInputSchema = z.object({
  decisionId: z.string().uuid(),
  tenantId: z.string().uuid(),
  appliedReference: z.string().min(1),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type AcknowledgeOptimizationRecommendationAppliedInput = z.input<typeof AcknowledgeOptimizationRecommendationAppliedInputSchema>;

export const GetOptimizationScenarioInputSchema = z.object({
  scenarioId: z.string().uuid(),
  tenantId: z.string().uuid(),
  actorAuthUserId: z.string().uuid(),
});
export type GetOptimizationScenarioInput = z.input<typeof GetOptimizationScenarioInputSchema>;

export const ListOptimizationScenariosForTenantInputSchema = z.object({
  tenantId: z.string().uuid(),
  actorAuthUserId: z.string().uuid(),
  scopeType: OptimizationScopeTypeSchema.nullable().default(null),
  status: OptimizationScenarioStatusSchema.nullable().default(null),
  limit: z.number().int().positive().max(200).default(50),
});
export type ListOptimizationScenariosForTenantInput = z.input<typeof ListOptimizationScenariosForTenantInputSchema>;
