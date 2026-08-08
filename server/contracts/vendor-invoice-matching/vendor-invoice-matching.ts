/**
 * Vendor Invoice Matching contract (PRC-265, CG-S11-PRC-016). Mirrors
 * supabase/migrations/20260730750000_create_procurement_vendor_invoice_matching.sql --
 * Zod schemas + parse functions for VendorBillMatchTolerancePolicy, VendorBillMatchCase
 * (cost-masked: total*Amount/total*Pct are the four fields
 * app.mask_vendor_bill_match_case_cost_fields nulls for a caller without PRC:View cost),
 * VendorBillMatchLine (similarly masked), VendorBillMatchDispute,
 * VendorBillMatchExceptionApproval, VendorBillMatchEvent, and readiness/reconciliation
 * read shapes, plus one *InputSchema per mutation -- the same shape
 * server/contracts/vendor-contract/vendor-contract.ts already establishes for this
 * checkpoint's own template.
 */

import { z } from "zod";

export const VENDOR_BILL_MATCH_TOLERANCE_POLICY_STATUSES = ["draft", "active", "archived"] as const;
export const VendorBillMatchTolerancePolicyStatusSchema = z.enum(VENDOR_BILL_MATCH_TOLERANCE_POLICY_STATUSES);
export type VendorBillMatchTolerancePolicyStatus = z.infer<typeof VendorBillMatchTolerancePolicyStatusSchema>;

export const VENDOR_BILL_MATCH_MODES = ["po_three_way", "contract_two_way", "non_po"] as const;
export const VendorBillMatchModeSchema = z.enum(VENDOR_BILL_MATCH_MODES);
export type VendorBillMatchMode = z.infer<typeof VendorBillMatchModeSchema>;

export const VENDOR_BILL_MATCH_CASE_STATUSES = ["pending", "matched", "exception", "disputed", "blocked", "cancelled"] as const;
export const VendorBillMatchCaseStatusSchema = z.enum(VENDOR_BILL_MATCH_CASE_STATUSES);
export type VendorBillMatchCaseStatus = z.infer<typeof VendorBillMatchCaseStatusSchema>;

export const VENDOR_BILL_MATCH_READINESS_STATUSES = ["not_ready", "ready_for_finance", "blocked"] as const;
export const VendorBillMatchReadinessStatusSchema = z.enum(VENDOR_BILL_MATCH_READINESS_STATUSES);
export type VendorBillMatchReadinessStatus = z.infer<typeof VendorBillMatchReadinessStatusSchema>;

export const VENDOR_BILL_MATCH_LINE_STATUSES = ["matched", "variance_within_tolerance", "variance_exception", "missing_evidence", "currency_mismatch"] as const;
export const VendorBillMatchLineStatusSchema = z.enum(VENDOR_BILL_MATCH_LINE_STATUSES);
export type VendorBillMatchLineStatus = z.infer<typeof VendorBillMatchLineStatusSchema>;

export const VENDOR_BILL_MATCH_DISPUTE_STATUSES = ["open", "upheld", "rejected", "withdrawn"] as const;
export const VendorBillMatchDisputeStatusSchema = z.enum(VENDOR_BILL_MATCH_DISPUTE_STATUSES);
export type VendorBillMatchDisputeStatus = z.infer<typeof VendorBillMatchDisputeStatusSchema>;

export const VENDOR_BILL_MATCH_EXCEPTION_APPROVAL_STATUSES = ["pending", "approved", "rejected"] as const;
export const VendorBillMatchExceptionApprovalStatusSchema = z.enum(VENDOR_BILL_MATCH_EXCEPTION_APPROVAL_STATUSES);
export type VendorBillMatchExceptionApprovalStatus = z.infer<typeof VendorBillMatchExceptionApprovalStatusSchema>;

// -- Tolerance policy --------------------------------------------------------

export const VendorBillMatchTolerancePolicySchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  versionNo: z.number().int().positive(),
  status: VendorBillMatchTolerancePolicyStatusSchema,
  name: z.string(),
  quantityTolerancePct: z.number(),
  rateTolerancePct: z.number(),
  taxTolerancePct: z.number(),
  lineAmountToleranceAbs: z.number(),
  autoClearEnabled: z.boolean(),
  duplicateWindowDays: z.number().int().positive(),
  notes: z.string().nullable(),
  approvedBy: z.string().nullable(),
  approvedAt: z.string().nullable(),
  recordVersion: z.number().int().positive(),
  createdBy: z.string().nullable(),
  createdAt: z.string(),
  updatedAt: z.string(),
});
export type VendorBillMatchTolerancePolicy = z.infer<typeof VendorBillMatchTolerancePolicySchema>;

export function parseVendorBillMatchTolerancePolicy(row: Record<string, unknown>): VendorBillMatchTolerancePolicy {
  return VendorBillMatchTolerancePolicySchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    versionNo: row.version_no,
    status: row.status,
    name: row.name,
    quantityTolerancePct: Number(row.quantity_tolerance_pct),
    rateTolerancePct: Number(row.rate_tolerance_pct),
    taxTolerancePct: Number(row.tax_tolerance_pct),
    lineAmountToleranceAbs: Number(row.line_amount_tolerance_abs),
    autoClearEnabled: row.auto_clear_enabled,
    duplicateWindowDays: row.duplicate_window_days,
    notes: row.notes,
    approvedBy: row.approved_by,
    approvedAt: row.approved_at,
    recordVersion: row.record_version,
    createdBy: row.created_by,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  });
}

// -- Match case ---------------------------------------------------------------

export const VendorBillMatchCaseSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  billId: z.string().uuid(),
  versionNo: z.number().int().positive(),
  isCurrent: z.boolean(),
  vendorMasterId: z.string().uuid(),
  currency: z.string(),
  matchMode: VendorBillMatchModeSchema,
  isPartialInvoice: z.boolean(),
  isConsolidatedInvoice: z.boolean(),
  purchaseOrderId: z.string().uuid().nullable(),
  vendorContractId: z.string().uuid().nullable(),
  tolerancePolicyId: z.string().uuid().nullable(),
  tolerancePolicyVersionNo: z.number().int().nullable(),
  quantityTolerancePctSnapshot: z.number(),
  rateTolerancePctSnapshot: z.number(),
  taxTolerancePctSnapshot: z.number(),
  lineAmountToleranceAbsSnapshot: z.number(),
  autoClearEnabledSnapshot: z.boolean(),
  totalVendorStatedAmount: z.number().nullable(),
  totalEvidenceAmount: z.number().nullable(),
  totalVarianceAmount: z.number().nullable(),
  totalVariancePct: z.number().nullable(),
  hasEpodEvidence: z.boolean(),
  hasDeliveryMilestoneEvidence: z.boolean(),
  duplicateFingerprint: z.string(),
  isDuplicateFlagged: z.boolean(),
  duplicateOfCaseId: z.string().uuid().nullable(),
  overallStatus: VendorBillMatchCaseStatusSchema,
  readinessStatus: VendorBillMatchReadinessStatusSchema,
  readinessNote: z.string().nullable(),
  cancelReason: z.string().nullable(),
  evaluatedBy: z.string().nullable(),
  evaluatedAt: z.string(),
  recordVersion: z.number().int().positive(),
  createdBy: z.string().nullable(),
  createdAt: z.string(),
  updatedAt: z.string(),
});
export type VendorBillMatchCase = z.infer<typeof VendorBillMatchCaseSchema>;

/** True whenever the four cost-shaped rollup fields are structurally masked (null) -- mirrors isVendorContractCostMasked's own derive-from-nulls shape. */
export function isVendorBillMatchCaseCostMasked(row: Record<string, unknown>): boolean {
  return row.total_vendor_stated_amount === null && row.total_evidence_amount === null && row.total_variance_amount === null;
}

export function parseVendorBillMatchCase(row: Record<string, unknown>): VendorBillMatchCase {
  return VendorBillMatchCaseSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    billId: row.bill_id,
    versionNo: row.version_no,
    isCurrent: row.is_current,
    vendorMasterId: row.vendor_master_id,
    currency: row.currency,
    matchMode: row.match_mode,
    isPartialInvoice: row.is_partial_invoice,
    isConsolidatedInvoice: row.is_consolidated_invoice,
    purchaseOrderId: row.purchase_order_id,
    vendorContractId: row.vendor_contract_id,
    tolerancePolicyId: row.tolerance_policy_id,
    tolerancePolicyVersionNo: row.tolerance_policy_version_no,
    quantityTolerancePctSnapshot: Number(row.quantity_tolerance_pct_snapshot),
    rateTolerancePctSnapshot: Number(row.rate_tolerance_pct_snapshot),
    taxTolerancePctSnapshot: Number(row.tax_tolerance_pct_snapshot),
    lineAmountToleranceAbsSnapshot: Number(row.line_amount_tolerance_abs_snapshot),
    autoClearEnabledSnapshot: row.auto_clear_enabled_snapshot,
    totalVendorStatedAmount: row.total_vendor_stated_amount === null ? null : Number(row.total_vendor_stated_amount),
    totalEvidenceAmount: row.total_evidence_amount === null ? null : Number(row.total_evidence_amount),
    totalVarianceAmount: row.total_variance_amount === null ? null : Number(row.total_variance_amount),
    totalVariancePct: row.total_variance_pct === null || row.total_variance_pct === undefined ? null : Number(row.total_variance_pct),
    hasEpodEvidence: row.has_epod_evidence,
    hasDeliveryMilestoneEvidence: row.has_delivery_milestone_evidence,
    duplicateFingerprint: row.duplicate_fingerprint as string,
    isDuplicateFlagged: row.is_duplicate_flagged,
    duplicateOfCaseId: row.duplicate_of_case_id,
    overallStatus: row.overall_status,
    readinessStatus: row.readiness_status,
    readinessNote: row.readiness_note,
    cancelReason: row.cancel_reason,
    evaluatedBy: row.evaluated_by,
    evaluatedAt: row.evaluated_at,
    recordVersion: row.record_version,
    createdBy: row.created_by,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  });
}

// -- Match line ---------------------------------------------------------------

export const VendorBillMatchLineSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  matchCaseId: z.string().uuid(),
  billLineId: z.string().uuid(),
  lineNo: z.number().int().positive(),
  lineType: z.enum(["cost", "tax"]),
  vendorStatedQuantity: z.number().nullable(),
  vendorStatedUom: z.string().nullable(),
  vendorStatedRate: z.number().nullable(),
  vendorStatedAmount: z.number().nullable(),
  actualCostComponentId: z.string().uuid().nullable(),
  poLineId: z.string().uuid().nullable(),
  rateVersionId: z.string().uuid().nullable(),
  evidenceQuantity: z.number().nullable(),
  evidenceUom: z.string().nullable(),
  evidenceRate: z.number().nullable(),
  evidenceAmount: z.number().nullable(),
  evidenceCurrency: z.string().nullable(),
  contractedRateAmount: z.number().nullable(),
  contractedRateCurrency: z.string().nullable(),
  currencyMismatch: z.boolean(),
  quantityVariancePct: z.number().nullable(),
  rateVariancePct: z.number().nullable(),
  amountVarianceAmount: z.number().nullable(),
  amountVariancePct: z.number().nullable(),
  uomMismatch: z.boolean(),
  poLineQuantityVariancePct: z.number().nullable(),
  poLineUomMismatch: z.boolean(),
  lineStatus: VendorBillMatchLineStatusSchema,
  notes: z.string().nullable(),
  recordVersion: z.number().int().positive(),
  createdAt: z.string(),
  updatedAt: z.string(),
});
export type VendorBillMatchLine = z.infer<typeof VendorBillMatchLineSchema>;

export function parseVendorBillMatchLine(row: Record<string, unknown>): VendorBillMatchLine {
  const num = (v: unknown): number | null => (v === null || v === undefined ? null : Number(v));
  return VendorBillMatchLineSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    matchCaseId: row.match_case_id,
    billLineId: row.bill_line_id,
    lineNo: row.line_no,
    lineType: row.line_type,
    vendorStatedQuantity: num(row.vendor_stated_quantity),
    vendorStatedUom: row.vendor_stated_uom,
    vendorStatedRate: num(row.vendor_stated_rate),
    vendorStatedAmount: num(row.vendor_stated_amount),
    actualCostComponentId: row.actual_cost_component_id,
    poLineId: row.po_line_id,
    rateVersionId: row.rate_version_id,
    evidenceQuantity: num(row.evidence_quantity),
    evidenceUom: row.evidence_uom,
    evidenceRate: num(row.evidence_rate),
    evidenceAmount: num(row.evidence_amount),
    evidenceCurrency: row.evidence_currency,
    contractedRateAmount: num(row.contracted_rate_amount),
    contractedRateCurrency: row.contracted_rate_currency,
    currencyMismatch: row.currency_mismatch,
    quantityVariancePct: num(row.quantity_variance_pct),
    rateVariancePct: num(row.rate_variance_pct),
    amountVarianceAmount: num(row.amount_variance_amount),
    amountVariancePct: num(row.amount_variance_pct),
    uomMismatch: row.uom_mismatch,
    poLineQuantityVariancePct: num(row.po_line_quantity_variance_pct),
    poLineUomMismatch: row.po_line_uom_mismatch,
    lineStatus: row.line_status,
    notes: row.notes,
    recordVersion: row.record_version,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  });
}

// -- Disputes / exception approvals / events -----------------------------------

export const VendorBillMatchDisputeSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  matchCaseId: z.string().uuid(),
  matchLineId: z.string().uuid().nullable(),
  reason: z.string(),
  disputedAmount: z.number().nullable(),
  status: VendorBillMatchDisputeStatusSchema,
  raisedByAuthUserId: z.string().uuid(),
  raisedBy: z.string().nullable(),
  vendorResponse: z.string().nullable(),
  vendorResponseAt: z.string().nullable(),
  vendorResponseFileId: z.string().uuid().nullable(),
  resolvedByAuthUserId: z.string().uuid().nullable(),
  resolutionNote: z.string().nullable(),
  resolvedAt: z.string().nullable(),
  recordVersion: z.number().int().positive(),
  createdAt: z.string(),
  updatedAt: z.string(),
});
export type VendorBillMatchDispute = z.infer<typeof VendorBillMatchDisputeSchema>;

export function parseVendorBillMatchDispute(row: Record<string, unknown>): VendorBillMatchDispute {
  return VendorBillMatchDisputeSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    matchCaseId: row.match_case_id,
    matchLineId: row.match_line_id,
    reason: row.reason,
    disputedAmount: row.disputed_amount === null ? null : Number(row.disputed_amount),
    status: row.status,
    raisedByAuthUserId: row.raised_by_auth_user_id,
    raisedBy: row.raised_by,
    vendorResponse: row.vendor_response,
    vendorResponseAt: row.vendor_response_at,
    vendorResponseFileId: row.vendor_response_file_id,
    resolvedByAuthUserId: row.resolved_by_auth_user_id,
    resolutionNote: row.resolution_note,
    resolvedAt: row.resolved_at,
    recordVersion: row.record_version,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  });
}

export const VendorBillMatchExceptionApprovalSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  matchCaseId: z.string().uuid(),
  reason: z.string(),
  varianceAmount: z.number().nullable(),
  variancePct: z.number().nullable(),
  includesDuplicateFlag: z.boolean(),
  status: VendorBillMatchExceptionApprovalStatusSchema,
  requestedByAuthUserId: z.string().uuid(),
  requestedBy: z.string().nullable(),
  decidedByAuthUserId: z.string().uuid().nullable(),
  decisionNote: z.string().nullable(),
  decidedAt: z.string().nullable(),
  recordVersion: z.number().int().positive(),
  createdAt: z.string(),
  updatedAt: z.string(),
});
export type VendorBillMatchExceptionApproval = z.infer<typeof VendorBillMatchExceptionApprovalSchema>;

export function parseVendorBillMatchExceptionApproval(row: Record<string, unknown>): VendorBillMatchExceptionApproval {
  return VendorBillMatchExceptionApprovalSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    matchCaseId: row.match_case_id,
    reason: row.reason,
    varianceAmount: row.variance_amount === null ? null : Number(row.variance_amount),
    variancePct: row.variance_pct === null || row.variance_pct === undefined ? null : Number(row.variance_pct),
    includesDuplicateFlag: row.includes_duplicate_flag,
    status: row.status,
    requestedByAuthUserId: row.requested_by_auth_user_id,
    requestedBy: row.requested_by,
    decidedByAuthUserId: row.decided_by_auth_user_id,
    decisionNote: row.decision_note,
    decidedAt: row.decided_at,
    recordVersion: row.record_version,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  });
}

export const VendorBillMatchEventSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  matchCaseId: z.string().uuid(),
  eventType: z.string(),
  eventData: z.record(z.string(), z.unknown()),
  actorAuthUserId: z.string().uuid().nullable(),
  actorLabel: z.string().nullable(),
  createdAt: z.string(),
});
export type VendorBillMatchEvent = z.infer<typeof VendorBillMatchEventSchema>;

export function parseVendorBillMatchEvent(row: Record<string, unknown>): VendorBillMatchEvent {
  return VendorBillMatchEventSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    matchCaseId: row.match_case_id,
    eventType: row.event_type,
    eventData: (row.event_data as Record<string, unknown>) ?? {},
    actorAuthUserId: row.actor_auth_user_id,
    actorLabel: row.actor_label,
    createdAt: row.created_at,
  });
}

// -- Readiness / reconciliation read shapes -------------------------------------

export const VendorBillMatchReadinessSchema = z.object({
  billId: z.string().uuid(),
  matchCaseId: z.string().uuid().nullable(),
  overallStatus: VendorBillMatchCaseStatusSchema.nullable(),
  readinessStatus: VendorBillMatchReadinessStatusSchema.nullable(),
  readinessNote: z.string().nullable(),
  isDuplicateFlagged: z.boolean().nullable(),
  totalVariancePct: z.number().nullable(),
  evaluatedAt: z.string().nullable(),
});
export type VendorBillMatchReadiness = z.infer<typeof VendorBillMatchReadinessSchema>;

export function parseVendorBillMatchReadiness(billId: string, row: Record<string, unknown> | null): VendorBillMatchReadiness {
  if (!row) {
    return { billId, matchCaseId: null, overallStatus: null, readinessStatus: null, readinessNote: null, isDuplicateFlagged: null, totalVariancePct: null, evaluatedAt: null };
  }
  return VendorBillMatchReadinessSchema.parse({
    billId: row.bill_id ?? billId,
    matchCaseId: row.match_case_id,
    overallStatus: row.overall_status,
    readinessStatus: row.readiness_status,
    readinessNote: row.readiness_note,
    isDuplicateFlagged: row.is_duplicate_flagged,
    totalVariancePct: row.total_variance_pct === null || row.total_variance_pct === undefined ? null : Number(row.total_variance_pct),
    evaluatedAt: row.evaluated_at,
  });
}

export const VendorBillMatchReconciliationRowSchema = z.object({
  overallStatus: VendorBillMatchCaseStatusSchema,
  readinessStatus: VendorBillMatchReadinessStatusSchema,
  caseCount: z.number().int().nonnegative(),
  totalVarianceAmount: z.number().nullable(),
  oldestPendingEvaluatedAt: z.string().nullable(),
});
export type VendorBillMatchReconciliationRow = z.infer<typeof VendorBillMatchReconciliationRowSchema>;

export function parseVendorBillMatchReconciliationRow(row: Record<string, unknown>): VendorBillMatchReconciliationRow {
  return VendorBillMatchReconciliationRowSchema.parse({
    overallStatus: row.overall_status,
    readinessStatus: row.readiness_status,
    caseCount: Number(row.case_count),
    totalVarianceAmount: row.total_variance_amount === null || row.total_variance_amount === undefined ? null : Number(row.total_variance_amount),
    oldestPendingEvaluatedAt: row.oldest_pending_evaluated_at,
  });
}

// -- Mutation inputs -------------------------------------------------------

export const LineInputSchema = z.object({
  billLineId: z.string().uuid(),
  vendorStatedQuantity: z.number().nullable().default(null),
  vendorStatedUom: z.string().nullable().default(null),
  vendorStatedRate: z.number().nullable().default(null),
  vendorStatedAmount: z.number(),
});
export type LineInput = z.input<typeof LineInputSchema>;

export const CreateVendorBillMatchTolerancePolicyDraftInputSchema = z.object({
  tenantId: z.string().uuid(),
  name: z.string().min(1),
  quantityTolerancePct: z.number().min(0).max(100).default(0),
  rateTolerancePct: z.number().min(0).max(100).default(0),
  taxTolerancePct: z.number().min(0).max(100).default(0),
  lineAmountToleranceAbs: z.number().min(0).default(0),
  autoClearEnabled: z.boolean().default(false),
  duplicateWindowDays: z.number().int().positive().default(30),
  notes: z.string().nullable().default(null),
  idempotencyKey: z.string().min(1),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type CreateVendorBillMatchTolerancePolicyDraftInput = z.input<typeof CreateVendorBillMatchTolerancePolicyDraftInputSchema>;

export const UpdateVendorBillMatchTolerancePolicyDraftInputSchema = z.object({
  policyId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  name: z.string().min(1),
  quantityTolerancePct: z.number().min(0).max(100).default(0),
  rateTolerancePct: z.number().min(0).max(100).default(0),
  taxTolerancePct: z.number().min(0).max(100).default(0),
  lineAmountToleranceAbs: z.number().min(0).default(0),
  autoClearEnabled: z.boolean().default(false),
  duplicateWindowDays: z.number().int().positive().default(30),
  notes: z.string().nullable().default(null),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type UpdateVendorBillMatchTolerancePolicyDraftInput = z.input<typeof UpdateVendorBillMatchTolerancePolicyDraftInputSchema>;

export const ActivateVendorBillMatchTolerancePolicyInputSchema = z.object({
  policyId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type ActivateVendorBillMatchTolerancePolicyInput = z.input<typeof ActivateVendorBillMatchTolerancePolicyInputSchema>;

export const CreateVendorBillMatchCaseInputSchema = z.object({
  tenantId: z.string().uuid(),
  billId: z.string().uuid(),
  purchaseOrderId: z.string().uuid().nullable().default(null),
  isPartialInvoice: z.boolean().default(false),
  isConsolidatedInvoice: z.boolean().default(false),
  lineInputs: z.array(LineInputSchema),
  idempotencyKey: z.string().min(1),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type CreateVendorBillMatchCaseInput = z.input<typeof CreateVendorBillMatchCaseInputSchema>;

export const ReEvaluateVendorBillMatchCaseInputSchema = z.object({
  matchCaseId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  purchaseOrderId: z.string().uuid().nullable().default(null),
  lineInputs: z.array(LineInputSchema),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type ReEvaluateVendorBillMatchCaseInput = z.input<typeof ReEvaluateVendorBillMatchCaseInputSchema>;

export const MapVendorBillMatchLineInputSchema = z.object({
  matchLineId: z.string().uuid(),
  expectedCaseVersion: z.number().int().positive(),
  poLineId: z.string().uuid().nullable().default(null),
  rateVersionId: z.string().uuid().nullable().default(null),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type MapVendorBillMatchLineInput = z.input<typeof MapVendorBillMatchLineInputSchema>;

export const AcceptVendorBillMatchWithinToleranceInputSchema = z.object({
  matchCaseId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type AcceptVendorBillMatchWithinToleranceInput = z.input<typeof AcceptVendorBillMatchWithinToleranceInputSchema>;

export const RaiseVendorBillMatchDisputeInputSchema = z.object({
  matchCaseId: z.string().uuid(),
  matchLineId: z.string().uuid().nullable().default(null),
  reason: z.string().min(1),
  disputedAmount: z.number().nullable().default(null),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type RaiseVendorBillMatchDisputeInput = z.input<typeof RaiseVendorBillMatchDisputeInputSchema>;

export const RecordVendorBillMatchDisputeResponseInputSchema = z.object({
  disputeId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  vendorResponse: z.string().min(1),
  vendorResponseFileId: z.string().uuid().nullable().default(null),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type RecordVendorBillMatchDisputeResponseInput = z.input<typeof RecordVendorBillMatchDisputeResponseInputSchema>;

export const ResolveVendorBillMatchDisputeInputSchema = z.object({
  disputeId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  decision: z.enum(["upheld", "rejected", "withdrawn"]),
  resolutionNote: z.string().min(1),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type ResolveVendorBillMatchDisputeInput = z.input<typeof ResolveVendorBillMatchDisputeInputSchema>;

export const RequestVendorBillMatchExceptionApprovalInputSchema = z.object({
  matchCaseId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  reason: z.string().min(1),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type RequestVendorBillMatchExceptionApprovalInput = z.input<typeof RequestVendorBillMatchExceptionApprovalInputSchema>;

export const DecideVendorBillMatchExceptionApprovalInputSchema = z.object({
  approvalId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  decision: z.enum(["approved", "rejected"]),
  decisionNote: z.string().min(1),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type DecideVendorBillMatchExceptionApprovalInput = z.input<typeof DecideVendorBillMatchExceptionApprovalInputSchema>;

export const CancelVendorBillMatchCaseInputSchema = z.object({
  matchCaseId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  reason: z.string().min(1),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type CancelVendorBillMatchCaseInput = z.input<typeof CancelVendorBillMatchCaseInputSchema>;
