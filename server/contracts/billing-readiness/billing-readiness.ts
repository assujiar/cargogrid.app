/**
 * Billing Readiness contract (OPS-181, CG-S8-OPS-015). Mirrors
 * supabase/migrations/20260728140000_create_operations_billing_readiness.sql's
 * app.billing_readiness_evaluations / app.billing_readiness_handoffs shapes and their
 * RPCs.
 *
 * A versioned, deterministic, explainable billing-readiness evaluation per Job Order --
 * exact blockers when not ready, a bounded authorized-override path, and one idempotent
 * Finance handoff record. This is evidence status only, never an invoice, accounts
 * receivable (AR), general ledger (GL) entry, or journal.
 */

import { z } from "zod";

export const BILLING_READINESS_BLOCKER_CODES = [
  "job_order_not_confirmed",
  "no_shipments",
  "shipment_not_delivered",
  "documents_incomplete",
  "epod_incomplete",
  "active_exception",
  "actual_cost_not_approved",
  "billing_profile_missing",
  "billing_profile_not_cleared",
] as const;
export const BillingReadinessBlockerCodeSchema = z.enum(BILLING_READINESS_BLOCKER_CODES);
export type BillingReadinessBlockerCode = z.infer<typeof BillingReadinessBlockerCodeSchema>;

/** Blockers carry a fixed `code` plus whatever else the evaluator recorded for that code (e.g. shipmentOrderId) -- passed through verbatim for explainability, never re-typed field by field. */
export const BillingReadinessBlockerSchema = z
  .object({ code: BillingReadinessBlockerCodeSchema })
  .catchall(z.unknown());
export type BillingReadinessBlocker = z.infer<typeof BillingReadinessBlockerSchema>;

export const BillingReadinessEvidenceSchema = z.object({
  shipmentOrderIds: z.array(z.string().uuid()),
  actualCostIds: z.array(z.string().uuid()),
  epodCaptureIds: z.array(z.string().uuid()),
  creditOutcome: z.string().nullable(),
  jobOrderStatus: z.string(),
});
export type BillingReadinessEvidence = z.infer<typeof BillingReadinessEvidenceSchema>;

export const BillingReadinessEvaluationSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  jobOrderId: z.string().uuid(),
  versionNumber: z.number().int().positive(),
  isCurrent: z.boolean(),
  evaluatedStatus: z.enum(["ready", "not_ready"]),
  effectiveStatus: z.enum(["ready", "not_ready"]),
  blockers: z.array(BillingReadinessBlockerSchema),
  evidence: BillingReadinessEvidenceSchema,
  ruleVersion: z.number().int(),
  isOverridden: z.boolean(),
  overrideReason: z.string().nullable(),
  overriddenBy: z.string().nullable(),
  overriddenAt: z.string().nullable(),
  overrideRevokedReason: z.string().nullable(),
  overrideRevokedBy: z.string().nullable(),
  overrideRevokedAt: z.string().nullable(),
  reevaluationReason: z.string().nullable(),
  supersedesEvaluationId: z.string().uuid().nullable(),
  evaluatedByAuthUserId: z.string().uuid(),
  evaluatedBy: z.string().nullable(),
  recordVersion: z.number().int(),
  createdBy: z.string().nullable(),
  createdAt: z.string(),
  updatedAt: z.string(),
});
export type BillingReadinessEvaluation = z.infer<typeof BillingReadinessEvaluationSchema>;

export function parseBillingReadinessEvaluation(row: Record<string, unknown>): BillingReadinessEvaluation {
  return BillingReadinessEvaluationSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    jobOrderId: row.job_order_id,
    versionNumber: row.version_number,
    isCurrent: row.is_current,
    evaluatedStatus: row.evaluated_status,
    effectiveStatus: row.effective_status,
    blockers: row.blockers ?? [],
    evidence: row.evidence ?? {},
    ruleVersion: row.rule_version,
    isOverridden: row.is_overridden,
    overrideReason: row.override_reason ?? null,
    overriddenBy: row.overridden_by ?? null,
    overriddenAt: row.overridden_at ?? null,
    overrideRevokedReason: row.override_revoked_reason ?? null,
    overrideRevokedBy: row.override_revoked_by ?? null,
    overrideRevokedAt: row.override_revoked_at ?? null,
    reevaluationReason: row.reevaluation_reason ?? null,
    supersedesEvaluationId: row.supersedes_evaluation_id ?? null,
    evaluatedByAuthUserId: row.evaluated_by_auth_user_id,
    evaluatedBy: row.evaluated_by ?? null,
    recordVersion: row.record_version,
    createdBy: row.created_by ?? null,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  });
}

export const BillingReadinessHandoffSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  jobOrderId: z.string().uuid(),
  evaluationId: z.string().uuid(),
  idempotencyKey: z.string(),
  handedOffByAuthUserId: z.string().uuid(),
  handedOffBy: z.string().nullable(),
  handedOffAt: z.string(),
  createdAt: z.string(),
});
export type BillingReadinessHandoff = z.infer<typeof BillingReadinessHandoffSchema>;

export function parseBillingReadinessHandoff(row: Record<string, unknown>): BillingReadinessHandoff {
  return BillingReadinessHandoffSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    jobOrderId: row.job_order_id,
    evaluationId: row.evaluation_id,
    idempotencyKey: row.idempotency_key,
    handedOffByAuthUserId: row.handed_off_by_auth_user_id,
    handedOffBy: row.handed_off_by ?? null,
    handedOffAt: row.handed_off_at,
    createdAt: row.created_at,
  });
}

export const EvaluateBillingReadinessInputSchema = z.object({
  jobOrderId: z.string().uuid(),
  reevaluationReason: z.string().nullable().optional(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type EvaluateBillingReadinessInput = z.input<typeof EvaluateBillingReadinessInputSchema>;

export const OverrideBillingReadinessInputSchema = z.object({
  jobOrderId: z.string().uuid(),
  expectedVersion: z.number().int(),
  reason: z.string().min(1),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type OverrideBillingReadinessInput = z.input<typeof OverrideBillingReadinessInputSchema>;

export const RevokeBillingReadinessOverrideInputSchema = OverrideBillingReadinessInputSchema;
export type RevokeBillingReadinessOverrideInput = z.input<typeof RevokeBillingReadinessOverrideInputSchema>;

export const HandoffBillingReadinessInputSchema = z.object({
  jobOrderId: z.string().uuid(),
  idempotencyKey: z.string().min(1),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type HandoffBillingReadinessInput = z.input<typeof HandoffBillingReadinessInputSchema>;
