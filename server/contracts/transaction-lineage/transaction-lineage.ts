/**
 * Transaction Lineage contract (OPS-184, CG-S8-OPS-018). Mirrors
 * supabase/migrations/20260728170000_create_operations_transaction_lineage.sql's
 * app.transaction_lineage_edges shape and its four RPCs
 * (get_transaction_lineage/record_transaction_lineage_override/
 * detect_transaction_lineage_anomalies/backfill_transaction_lineage).
 *
 * One traceable operational transaction chain: Commercial's accepted-quote handoff ->
 * Job Order -> Shipment Order -> ePOD / Actual Cost -> Job Profitability -> Billing
 * Readiness. Six edges are captured automatically (never by this service layer directly);
 * this contract's own mutation is the one authorized correction path.
 */

import { z } from "zod";

export const TRANSACTION_LINEAGE_RELATION_TYPES = [
  "quote_to_job",
  "job_to_shipment",
  "shipment_to_epod",
  "shipment_to_cost",
  "job_to_profitability",
  "job_to_billing_readiness",
] as const;
export const TransactionLineageRelationTypeSchema = z.enum(TRANSACTION_LINEAGE_RELATION_TYPES);
export type TransactionLineageRelationType = z.infer<typeof TransactionLineageRelationTypeSchema>;

export const TRANSACTION_LINEAGE_NODE_TYPES = [
  "job_order_handoff",
  "job_order",
  "shipment_order",
  "epod_capture",
  "shipment_actual_cost",
  "job_profitability_snapshot",
  "billing_readiness_evaluation",
] as const;
export const TransactionLineageNodeTypeSchema = z.enum(TRANSACTION_LINEAGE_NODE_TYPES);
export type TransactionLineageNodeType = z.infer<typeof TransactionLineageNodeTypeSchema>;

export const TransactionLineageEdgeSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  relationType: TransactionLineageRelationTypeSchema,
  sourceType: TransactionLineageNodeTypeSchema,
  sourceId: z.string().uuid(),
  targetType: TransactionLineageNodeTypeSchema,
  targetId: z.string().uuid(),
  sourceVersionHash: z.string().nullable(),
  ownerUserId: z.string().uuid().nullable(),
  orgUnitId: z.string().uuid().nullable(),
  isOverride: z.boolean(),
  overrideReason: z.string().nullable(),
  createdByAuthUserId: z.string().uuid().nullable(),
  createdByLabel: z.string(),
  createdAt: z.string(),
});
export type TransactionLineageEdge = z.infer<typeof TransactionLineageEdgeSchema>;

export function parseTransactionLineageEdge(row: Record<string, unknown>): TransactionLineageEdge {
  return TransactionLineageEdgeSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    relationType: row.relation_type,
    sourceType: row.source_type,
    sourceId: row.source_id,
    targetType: row.target_type,
    targetId: row.target_id,
    sourceVersionHash: row.source_version_hash ?? null,
    ownerUserId: row.owner_user_id ?? null,
    orgUnitId: row.org_unit_id ?? null,
    isOverride: row.is_override,
    overrideReason: row.override_reason ?? null,
    createdByAuthUserId: row.created_by_auth_user_id ?? null,
    createdByLabel: row.created_by_label,
    createdAt: row.created_at,
  });
}

const ManifestEdgeSchema = z.object({
  id: z.string().uuid(),
  relationType: TransactionLineageRelationTypeSchema,
  sourceType: TransactionLineageNodeTypeSchema,
  sourceId: z.string().uuid(),
  targetType: TransactionLineageNodeTypeSchema,
  targetId: z.string().uuid(),
  sourceVersionHash: z.string().nullable(),
  isOverride: z.boolean(),
  overrideReason: z.string().nullable(),
  createdAt: z.string(),
});

const ManifestMilestoneSchema = z.object({
  lastMilestoneCode: z.string().nullable(),
  isDelayed: z.boolean(),
  currentEta: z.string().nullable(),
});

const ManifestEpodSchema = z.object({
  epodCaptureId: z.string().uuid(),
  status: z.string(),
  versionNumber: z.number().int().positive(),
});

const ManifestActualCostSchema = z.object({
  shipmentActualCostId: z.string().uuid(),
  status: z.string(),
  versionNumber: z.number().int().positive(),
});

const ManifestShipmentSchema = z.object({
  shipmentOrderId: z.string().uuid(),
  shipmentNumber: z.string(),
  status: z.string(),
  milestone: ManifestMilestoneSchema.nullable(),
  epod: ManifestEpodSchema.nullable(),
  actualCost: ManifestActualCostSchema.nullable(),
});

const ManifestProfitabilitySchema = z.object({
  jobProfitabilitySnapshotId: z.string().uuid(),
  status: z.string(),
  versionNumber: z.number().int().positive(),
});

const ManifestBillingReadinessSchema = z.object({
  billingReadinessEvaluationId: z.string().uuid(),
  effectiveStatus: z.string(),
  versionNumber: z.number().int().positive(),
});

export const TransactionLineageManifestSchema = z.object({
  jobOrderId: z.string().uuid(),
  jobNumber: z.string(),
  sourceHandoffId: z.string().uuid(),
  sourceQuotationId: z.string().uuid().nullable(),
  sourcePayloadHash: z.string().nullable(),
  shipments: z.array(ManifestShipmentSchema),
  profitability: ManifestProfitabilitySchema.nullable(),
  billingReadiness: ManifestBillingReadinessSchema.nullable(),
  edges: z.array(ManifestEdgeSchema),
});
export type TransactionLineageManifest = z.infer<typeof TransactionLineageManifestSchema>;

export function parseTransactionLineageManifest(payload: unknown): TransactionLineageManifest {
  return TransactionLineageManifestSchema.parse(payload);
}

export const TRANSACTION_LINEAGE_ANOMALY_TYPES = ["orphan_shipment_order", "orphan_billing_readiness", "duplicate_target", "cross_tenant_mismatch"] as const;
export const TransactionLineageAnomalyTypeSchema = z.enum(TRANSACTION_LINEAGE_ANOMALY_TYPES);
export type TransactionLineageAnomalyType = z.infer<typeof TransactionLineageAnomalyTypeSchema>;

export const TransactionLineageAnomalySchema = z.object({
  anomalyType: TransactionLineageAnomalyTypeSchema,
  relationType: TransactionLineageRelationTypeSchema,
  targetType: TransactionLineageNodeTypeSchema,
  targetId: z.string().uuid(),
  detail: z.string(),
});
export type TransactionLineageAnomaly = z.infer<typeof TransactionLineageAnomalySchema>;

export function parseTransactionLineageAnomaly(row: Record<string, unknown>): TransactionLineageAnomaly {
  return TransactionLineageAnomalySchema.parse({
    anomalyType: row.anomaly_type,
    relationType: row.relation_type,
    targetType: row.target_type,
    targetId: row.target_id,
    detail: row.detail,
  });
}

export const GetTransactionLineageInputSchema = z.object({
  jobOrderId: z.string().uuid(),
  actorAuthUserId: z.string().uuid(),
});
export type GetTransactionLineageInput = z.input<typeof GetTransactionLineageInputSchema>;

export const RecordTransactionLineageOverrideInputSchema = z.object({
  tenantId: z.string().uuid(),
  relationType: TransactionLineageRelationTypeSchema,
  sourceType: TransactionLineageNodeTypeSchema,
  sourceId: z.string().uuid(),
  targetType: TransactionLineageNodeTypeSchema,
  targetId: z.string().uuid(),
  reason: z.string().min(1),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type RecordTransactionLineageOverrideInput = z.input<typeof RecordTransactionLineageOverrideInputSchema>;

export const DetectTransactionLineageAnomaliesInputSchema = z.object({
  tenantId: z.string().uuid(),
  actorAuthUserId: z.string().uuid(),
});
export type DetectTransactionLineageAnomaliesInput = z.input<typeof DetectTransactionLineageAnomaliesInputSchema>;

export const BackfillTransactionLineageInputSchema = z.object({
  tenantId: z.string().uuid(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type BackfillTransactionLineageInput = z.input<typeof BackfillTransactionLineageInputSchema>;
