/**
 * Procurement Dashboard and Reports contract (PRC-266, CG-S11-PRC-017). Mirrors
 * supabase/migrations/20260730780000_create_procurement_dashboard_reports.sql --
 * Zod schemas + parse functions for the ten read RPCs (one per exportable metric,
 * across all 7 required groups), the metric-definition catalogue, and saved views,
 * plus one *InputSchema per write RPC. Group 7 (match variance/exception rate) has no
 * shapes of its own here -- it reuses server/contracts/vendor-invoice-matching/
 * vendor-invoice-matching.ts's own VendorBillMatchReconciliationRow verbatim (design
 * note 2 in the migration's own header).
 */

import { z } from "zod";

const numeric = (value: unknown) => (typeof value === "string" ? Number(value) : value);
const bigintCount = (value: unknown) => (typeof value === "string" ? Number(value) : value);

export const PROCUREMENT_DASHBOARD_METRIC_GROUPS = [
  "vendor_risk_compliance",
  "rate_validity_competitiveness",
  "rfq_response_cycle",
  "capacity_acceptance",
  "po_contract",
  "performance",
  "match_variance_exception",
] as const;
export const ProcurementDashboardMetricGroupSchema = z.enum(PROCUREMENT_DASHBOARD_METRIC_GROUPS);
export type ProcurementDashboardMetricGroup = z.infer<typeof ProcurementDashboardMetricGroupSchema>;

// -- Metric definition catalogue (broadly readable, plain `.from()` reads) -----------

export const PROCUREMENT_METRIC_REQUIRED_ACTIONS = ["View", "View cost", "View personal data"] as const;
export const ProcurementMetricRequiredActionSchema = z.enum(PROCUREMENT_METRIC_REQUIRED_ACTIONS);

export const ProcurementMetricDefinitionSchema = z.object({
  id: z.string().uuid(),
  code: z.string(),
  metricGroup: ProcurementDashboardMetricGroupSchema,
  versionNo: z.number().int().positive(),
  isCurrent: z.boolean(),
  supersedesDefinitionId: z.string().uuid().nullable(),
  name: z.string(),
  description: z.string().nullable(),
  sourceTables: z.array(z.string()),
  sourceColumns: z.array(z.string()),
  formula: z.string(),
  grain: z.string(),
  freshnessRule: z.string(),
  requiredAction: ProcurementMetricRequiredActionSchema,
  additionalMaskAction: ProcurementMetricRequiredActionSchema.nullable(),
  sourceFunction: z.string(),
  status: z.enum(["active", "retired"]),
  registeredBy: z.string().nullable(),
  createdAt: z.string(),
});
export type ProcurementMetricDefinition = z.infer<typeof ProcurementMetricDefinitionSchema>;

export function parseProcurementMetricDefinition(row: Record<string, unknown>): ProcurementMetricDefinition {
  return ProcurementMetricDefinitionSchema.parse({
    id: row.id,
    code: row.code,
    metricGroup: row.metric_group,
    versionNo: row.version_no,
    isCurrent: row.is_current,
    supersedesDefinitionId: row.supersedes_definition_id,
    name: row.name,
    description: row.description,
    sourceTables: row.source_tables ?? [],
    sourceColumns: row.source_columns ?? [],
    formula: row.formula,
    grain: row.grain,
    freshnessRule: row.freshness_rule,
    requiredAction: row.required_action,
    additionalMaskAction: row.additional_mask_action,
    sourceFunction: row.source_function,
    status: row.status,
    registeredBy: row.registered_by,
    createdAt: row.created_at,
  });
}

// -- Saved views -----------------------------------------------------------

export const ProcurementDashboardSavedViewSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  ownerAuthUserId: z.string().uuid(),
  metricGroup: ProcurementDashboardMetricGroupSchema,
  name: z.string(),
  description: z.string().nullable(),
  filters: z.record(z.string(), z.unknown()),
  sort: z.record(z.string(), z.unknown()),
  recordVersion: z.number().int().positive(),
  createdBy: z.string().nullable(),
  createdAt: z.string(),
  updatedAt: z.string(),
});
export type ProcurementDashboardSavedView = z.infer<typeof ProcurementDashboardSavedViewSchema>;

export function parseProcurementDashboardSavedView(row: Record<string, unknown>): ProcurementDashboardSavedView {
  return ProcurementDashboardSavedViewSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    ownerAuthUserId: row.owner_auth_user_id,
    metricGroup: row.metric_group,
    name: row.name,
    description: row.description,
    filters: row.filters ?? {},
    sort: row.sort ?? {},
    recordVersion: row.record_version,
    createdBy: row.created_by,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  });
}

export const CreateProcurementDashboardSavedViewInputSchema = z.object({
  tenantId: z.string().uuid(),
  metricGroup: ProcurementDashboardMetricGroupSchema,
  name: z.string().min(1),
  description: z.string().nullable().default(null),
  filters: z.record(z.string(), z.unknown()).nullable().default(null),
  sort: z.record(z.string(), z.unknown()).nullable().default(null),
  idempotencyKey: z.string().min(1),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type CreateProcurementDashboardSavedViewInput = z.input<typeof CreateProcurementDashboardSavedViewInputSchema>;

export const UpdateProcurementDashboardSavedViewInputSchema = z.object({
  viewId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  name: z.string().min(1),
  description: z.string().nullable().default(null),
  filters: z.record(z.string(), z.unknown()).nullable().default(null),
  sort: z.record(z.string(), z.unknown()).nullable().default(null),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type UpdateProcurementDashboardSavedViewInput = z.input<typeof UpdateProcurementDashboardSavedViewInputSchema>;

export const DeleteProcurementDashboardSavedViewInputSchema = z.object({
  viewId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type DeleteProcurementDashboardSavedViewInput = z.input<typeof DeleteProcurementDashboardSavedViewInputSchema>;

// -- Group 1: vendor risk / compliance-expiry -----------------------------------------

export const ProcurementDashboardVendorRiskSummaryRowSchema = z.object({
  lifecycleStatus: z.string(),
  vendorCount: z.number().int(),
  complianceHoldCount: z.number().int(),
  bandExcellentCount: z.number().int(),
  bandGoodCount: z.number().int(),
  bandWatchCount: z.number().int(),
  bandPoorCount: z.number().int(),
});
export type ProcurementDashboardVendorRiskSummaryRow = z.infer<typeof ProcurementDashboardVendorRiskSummaryRowSchema>;

export function parseProcurementDashboardVendorRiskSummaryRow(row: Record<string, unknown>): ProcurementDashboardVendorRiskSummaryRow {
  return ProcurementDashboardVendorRiskSummaryRowSchema.parse({
    lifecycleStatus: row.lifecycle_status,
    vendorCount: bigintCount(row.vendor_count),
    complianceHoldCount: bigintCount(row.compliance_hold_count),
    bandExcellentCount: bigintCount(row.band_excellent_count),
    bandGoodCount: bigintCount(row.band_good_count),
    bandWatchCount: bigintCount(row.band_watch_count),
    bandPoorCount: bigintCount(row.band_poor_count),
  });
}

export const ProcurementVendorRiskDashboardRowSchema = z.object({
  vendorMasterId: z.string().uuid(),
  legalName: z.string(),
  vendorCategory: z.string().nullable(),
  lifecycleStatus: z.string(),
  complianceHold: z.boolean(),
  complianceExpiringSoonCount: z.number().int(),
  complianceExpiredCount: z.number().int(),
  scorecardBand: z.enum(["excellent", "good", "watch", "poor"]).nullable(),
  scorecardCompositeScore: z.number().nullable(),
  scorecardWindowEnd: z.string().nullable(),
  createdAt: z.string(),
});
export type ProcurementVendorRiskDashboardRow = z.infer<typeof ProcurementVendorRiskDashboardRowSchema>;

export function parseProcurementVendorRiskDashboardRow(row: Record<string, unknown>): ProcurementVendorRiskDashboardRow {
  return ProcurementVendorRiskDashboardRowSchema.parse({
    vendorMasterId: row.vendor_master_id,
    legalName: row.legal_name,
    vendorCategory: row.vendor_category,
    lifecycleStatus: row.lifecycle_status,
    complianceHold: row.compliance_hold,
    complianceExpiringSoonCount: row.compliance_expiring_soon_count,
    complianceExpiredCount: row.compliance_expired_count,
    scorecardBand: row.scorecard_band,
    scorecardCompositeScore: numeric(row.scorecard_composite_score) ?? null,
    scorecardWindowEnd: row.scorecard_window_end,
    createdAt: row.created_at,
  });
}

// -- Group 2: rate validity / competitiveness -----------------------------------------

export const ProcurementDashboardRateValiditySummaryRowSchema = z.object({
  currency: z.string(),
  validityBucket: z.string(),
  rateCount: z.number().int(),
});
export type ProcurementDashboardRateValiditySummaryRow = z.infer<typeof ProcurementDashboardRateValiditySummaryRowSchema>;

export function parseProcurementDashboardRateValiditySummaryRow(row: Record<string, unknown>): ProcurementDashboardRateValiditySummaryRow {
  return ProcurementDashboardRateValiditySummaryRowSchema.parse({
    currency: row.currency,
    validityBucket: row.validity_bucket,
    rateCount: bigintCount(row.rate_count),
  });
}

export const ProcurementDashboardRateCompetitivenessSummaryRowSchema = z.object({
  competitivenessBand: z.enum(["strong", "moderate", "weak", "not_computed"]),
  vendorCount: z.number().int(),
  avgScore: z.number().nullable(),
});
export type ProcurementDashboardRateCompetitivenessSummaryRow = z.infer<typeof ProcurementDashboardRateCompetitivenessSummaryRowSchema>;

export function parseProcurementDashboardRateCompetitivenessSummaryRow(row: Record<string, unknown>): ProcurementDashboardRateCompetitivenessSummaryRow {
  return ProcurementDashboardRateCompetitivenessSummaryRowSchema.parse({
    competitivenessBand: row.competitiveness_band,
    vendorCount: bigintCount(row.vendor_count),
    avgScore: numeric(row.avg_score) ?? null,
  });
}

// -- Group 3: RFQ response rate / cycle time -----------------------------------------

export const ProcurementDashboardRfqCycleSummaryRowSchema = z.object({
  rfqStatus: z.string(),
  rfqCount: z.number().int(),
  invitationCount: z.number().int(),
  responseCount: z.number().int(),
  responseRatePct: z.number().nullable(),
  avgCycleHours: z.number().nullable(),
});
export type ProcurementDashboardRfqCycleSummaryRow = z.infer<typeof ProcurementDashboardRfqCycleSummaryRowSchema>;

export function parseProcurementDashboardRfqCycleSummaryRow(row: Record<string, unknown>): ProcurementDashboardRfqCycleSummaryRow {
  return ProcurementDashboardRfqCycleSummaryRowSchema.parse({
    rfqStatus: row.rfq_status,
    rfqCount: bigintCount(row.rfq_count),
    invitationCount: bigintCount(row.invitation_count),
    responseCount: bigintCount(row.response_count),
    responseRatePct: numeric(row.response_rate_pct) ?? null,
    avgCycleHours: numeric(row.avg_cycle_hours) ?? null,
  });
}

// -- Group 4: capacity / acceptance -----------------------------------------

export const ProcurementDashboardCapacityReservationSummaryRowSchema = z.object({
  status: z.string(),
  reservationCount: z.number().int(),
});
export type ProcurementDashboardCapacityReservationSummaryRow = z.infer<typeof ProcurementDashboardCapacityReservationSummaryRowSchema>;

export function parseProcurementDashboardCapacityReservationSummaryRow(row: Record<string, unknown>): ProcurementDashboardCapacityReservationSummaryRow {
  return ProcurementDashboardCapacityReservationSummaryRowSchema.parse({
    status: row.status,
    reservationCount: bigintCount(row.reservation_count),
  });
}

export const ProcurementDashboardAssignmentAcceptanceSummaryRowSchema = z.object({
  status: z.string(),
  invitationCount: z.number().int(),
  avgResponseHours: z.number().nullable(),
});
export type ProcurementDashboardAssignmentAcceptanceSummaryRow = z.infer<typeof ProcurementDashboardAssignmentAcceptanceSummaryRowSchema>;

export function parseProcurementDashboardAssignmentAcceptanceSummaryRow(row: Record<string, unknown>): ProcurementDashboardAssignmentAcceptanceSummaryRow {
  return ProcurementDashboardAssignmentAcceptanceSummaryRowSchema.parse({
    status: row.status,
    invitationCount: bigintCount(row.invitation_count),
    avgResponseHours: numeric(row.avg_response_hours) ?? null,
  });
}

// -- Group 5: PO / contract -----------------------------------------

export const ProcurementDashboardPoSummaryRowSchema = z.object({
  status: z.string(),
  currency: z.string(),
  poCount: z.number().int(),
  committedAmount: z.number().nullable(),
  costMasked: z.boolean(),
});
export type ProcurementDashboardPoSummaryRow = z.infer<typeof ProcurementDashboardPoSummaryRowSchema>;

export function parseProcurementDashboardPoSummaryRow(row: Record<string, unknown>): ProcurementDashboardPoSummaryRow {
  return ProcurementDashboardPoSummaryRowSchema.parse({
    status: row.status,
    currency: row.currency,
    poCount: bigintCount(row.po_count),
    committedAmount: row.committed_amount == null ? null : numeric(row.committed_amount),
    costMasked: row.cost_masked,
  });
}

export const ProcurementDashboardContractSummaryRowSchema = z.object({
  status: z.string(),
  contractCount: z.number().int(),
  expiringSoonCount: z.number().int(),
});
export type ProcurementDashboardContractSummaryRow = z.infer<typeof ProcurementDashboardContractSummaryRowSchema>;

export function parseProcurementDashboardContractSummaryRow(row: Record<string, unknown>): ProcurementDashboardContractSummaryRow {
  return ProcurementDashboardContractSummaryRowSchema.parse({
    status: row.status,
    contractCount: bigintCount(row.contract_count),
    expiringSoonCount: bigintCount(row.expiring_soon_count),
  });
}

// -- Group 6: performance -----------------------------------------

export const ProcurementDashboardPerformanceSummaryRowSchema = z.object({
  band: z.string(),
  vendorCount: z.number().int(),
  avgCompositeScore: z.number().nullable(),
});
export type ProcurementDashboardPerformanceSummaryRow = z.infer<typeof ProcurementDashboardPerformanceSummaryRowSchema>;

export function parseProcurementDashboardPerformanceSummaryRow(row: Record<string, unknown>): ProcurementDashboardPerformanceSummaryRow {
  return ProcurementDashboardPerformanceSummaryRowSchema.parse({
    band: row.band,
    vendorCount: bigintCount(row.vendor_count),
    avgCompositeScore: numeric(row.avg_composite_score) ?? null,
  });
}
