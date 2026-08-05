/**
 * Advanced Claim and Incident Operations contract (ATW-025, CG-S10-ATW-025, Prompt
 * 244). Mirrors supabase/migrations/20260730340000_create_advanced_tms_claim_
 * incident_operations.sql's app.claim_case_extensions/app.claim_items/app.
 * claim_evidence_links/app.claim_investigation_findings/app.
 * claim_responsibility_reviews/app.claim_recovery_records/app.
 * claim_settlement_readiness_evaluations/app.claim_settlement_readiness_handoffs
 * shapes and their open/itemize/evidence/investigate/propose/decide/recover/
 * evaluate/handoff/reconcile/close/reopen/read RPCs.
 */

import { z } from "zod";

export const CLAIM_CLAIMANT_TYPES = ["customer", "carrier", "vendor", "third_party", "internal"] as const;
export const ClaimClaimantTypeSchema = z.enum(CLAIM_CLAIMANT_TYPES);
export type ClaimClaimantType = z.infer<typeof ClaimClaimantTypeSchema>;

export const CLAIM_STAGES = [
  "intake",
  "evidence_gathering",
  "investigating",
  "pending_decision",
  "decided",
  "recovering",
  "finance_handoff",
  "closed",
] as const;
export const ClaimStageSchema = z.enum(CLAIM_STAGES);
export type ClaimStage = z.infer<typeof ClaimStageSchema>;

export const CLAIM_CLOSURE_BASES = ["finance_reconciled", "no_handoff_required"] as const;
export const ClaimClosureBasisSchema = z.enum(CLAIM_CLOSURE_BASES);
export type ClaimClosureBasis = z.infer<typeof ClaimClosureBasisSchema>;

export const CLAIM_ITEM_TYPES = ["inventory", "package", "cargo_general"] as const;
export const ClaimItemTypeSchema = z.enum(CLAIM_ITEM_TYPES);
export type ClaimItemType = z.infer<typeof ClaimItemTypeSchema>;

export const CLAIM_ITEM_STATUSES = ["active", "withdrawn"] as const;
export const ClaimItemStatusSchema = z.enum(CLAIM_ITEM_STATUSES);
export type ClaimItemStatus = z.infer<typeof ClaimItemStatusSchema>;

export const CLAIM_EVIDENCE_TYPES = [
  "shipment_leg",
  "shipment_leg_custody_event",
  "inventory_movement",
  "wms_outbound_shipment",
  "epod_capture",
  "file",
] as const;
export const ClaimEvidenceTypeSchema = z.enum(CLAIM_EVIDENCE_TYPES);
export type ClaimEvidenceType = z.infer<typeof ClaimEvidenceTypeSchema>;

export const CLAIM_EVIDENCE_SUFFICIENCY_VALUES = ["sufficient", "insufficient", "pending"] as const;
export const ClaimEvidenceSufficiencySchema = z.enum(CLAIM_EVIDENCE_SUFFICIENCY_VALUES);
export type ClaimEvidenceSufficiency = z.infer<typeof ClaimEvidenceSufficiencySchema>;

export const CLAIM_RESPONSIBILITY_PARTIES = ["carrier", "vendor", "customer", "internal", "unknown"] as const;
export const ClaimResponsibilityPartySchema = z.enum(CLAIM_RESPONSIBILITY_PARTIES);
export type ClaimResponsibilityParty = z.infer<typeof ClaimResponsibilityPartySchema>;

export const CLAIM_RESPONSIBILITY_REVIEW_STATUSES = ["proposed", "approved", "denied", "amended"] as const;
export const ClaimResponsibilityReviewStatusSchema = z.enum(CLAIM_RESPONSIBILITY_REVIEW_STATUSES);
export type ClaimResponsibilityReviewStatus = z.infer<typeof ClaimResponsibilityReviewStatusSchema>;

export const CLAIM_RESPONSIBILITY_DECISIONS = ["approved", "denied", "amended"] as const;
export const ClaimResponsibilityDecisionSchema = z.enum(CLAIM_RESPONSIBILITY_DECISIONS);
export type ClaimResponsibilityDecision = z.infer<typeof ClaimResponsibilityDecisionSchema>;

export const CLAIM_RECOVERED_FROM_VALUES = ["carrier", "vendor", "customer", "insurance"] as const;
export const ClaimRecoveredFromSchema = z.enum(CLAIM_RECOVERED_FROM_VALUES);
export type ClaimRecoveredFrom = z.infer<typeof ClaimRecoveredFromSchema>;

export const CLAIM_SETTLEMENT_EVALUATED_STATUSES = ["ready", "not_ready"] as const;
export const ClaimSettlementEvaluatedStatusSchema = z.enum(CLAIM_SETTLEMENT_EVALUATED_STATUSES);
export type ClaimSettlementEvaluatedStatus = z.infer<typeof ClaimSettlementEvaluatedStatusSchema>;

export const CLAIM_RECONCILIATION_STATUSES = ["reconciled", "rejected"] as const;
export const ClaimReconciliationStatusSchema = z.enum(CLAIM_RECONCILIATION_STATUSES);
export type ClaimReconciliationStatus = z.infer<typeof ClaimReconciliationStatusSchema>;

export const ClaimContactSnapshotSchema = z
  .object({
    name: z.string().optional(),
    phone: z.string().optional(),
    email: z.string().optional(),
  })
  .strict();
export type ClaimContactSnapshot = z.infer<typeof ClaimContactSnapshotSchema>;

// --- Row schemas ---

export const ClaimCaseExtensionSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  operationalExceptionId: z.string().uuid(),
  claimantType: ClaimClaimantTypeSchema,
  claimantAccountId: z.string().uuid().nullable(),
  claimantLabel: z.string().nullable(),
  contactSnapshot: ClaimContactSnapshotSchema.nullable(),
  claimStage: ClaimStageSchema,
  openedBy: z.string().nullable(),
  openedAt: z.string(),
  closureNote: z.string().nullable(),
  closureBasis: ClaimClosureBasisSchema.nullable(),
  closedAt: z.string().nullable(),
  closedBy: z.string().nullable(),
  reopenedAt: z.string().nullable(),
  reopenedBy: z.string().nullable(),
  reopenReason: z.string().nullable(),
  recordVersion: z.number().int().positive(),
  createdBy: z.string().nullable(),
  createdAt: z.string(),
  updatedAt: z.string(),
});
export type ClaimCaseExtension = z.infer<typeof ClaimCaseExtensionSchema>;

export function parseClaimCaseExtension(row: Record<string, unknown>): ClaimCaseExtension {
  return ClaimCaseExtensionSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    operationalExceptionId: row.operational_exception_id,
    claimantType: row.claimant_type,
    claimantAccountId: row.claimant_account_id ?? null,
    claimantLabel: row.claimant_label ?? null,
    contactSnapshot: row.contact_snapshot ?? null,
    claimStage: row.claim_stage,
    openedBy: row.opened_by ?? null,
    openedAt: row.opened_at,
    closureNote: row.closure_note ?? null,
    closureBasis: row.closure_basis ?? null,
    closedAt: row.closed_at ?? null,
    closedBy: row.closed_by ?? null,
    reopenedAt: row.reopened_at ?? null,
    reopenedBy: row.reopened_by ?? null,
    reopenReason: row.reopen_reason ?? null,
    recordVersion: row.record_version,
    createdBy: row.created_by ?? null,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  });
}

/** app.list_claim_cases' own joined return shape -- case columns plus denormalized exception fields. */
export const ClaimCaseListRowSchema = ClaimCaseExtensionSchema.pick({
  id: true,
  tenantId: true,
  operationalExceptionId: true,
  claimantType: true,
  claimantAccountId: true,
  claimantLabel: true,
  claimStage: true,
  openedBy: true,
  openedAt: true,
  closureBasis: true,
  closedAt: true,
  recordVersion: true,
  updatedAt: true,
}).extend({
  exceptionType: z.string(),
  exceptionSeverity: z.string(),
  exceptionStatus: z.string(),
  shipmentOrderId: z.string().uuid(),
});
export type ClaimCaseListRow = z.infer<typeof ClaimCaseListRowSchema>;

export function parseClaimCaseListRow(row: Record<string, unknown>): ClaimCaseListRow {
  return ClaimCaseListRowSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    operationalExceptionId: row.operational_exception_id,
    claimantType: row.claimant_type,
    claimantAccountId: row.claimant_account_id ?? null,
    claimantLabel: row.claimant_label ?? null,
    claimStage: row.claim_stage,
    openedBy: row.opened_by ?? null,
    openedAt: row.opened_at,
    closureBasis: row.closure_basis ?? null,
    closedAt: row.closed_at ?? null,
    recordVersion: row.record_version,
    updatedAt: row.updated_at,
    exceptionType: row.exception_type,
    exceptionSeverity: row.exception_severity,
    exceptionStatus: row.exception_status,
    shipmentOrderId: row.shipment_order_id,
  });
}

export const ClaimItemSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  claimCaseId: z.string().uuid(),
  itemType: ClaimItemTypeSchema,
  linkedInventoryMovementId: z.string().uuid().nullable(),
  linkedWmsOutboundShipmentId: z.string().uuid().nullable(),
  itemMasterId: z.string().uuid().nullable(),
  declaredQuantity: z.coerce.number(),
  uomCode: z.string(),
  declaredValue: z.coerce.number().nullable(),
  currency: z.string().nullable(),
  description: z.string(),
  status: ClaimItemStatusSchema,
  withdrawnAt: z.string().nullable(),
  withdrawnBy: z.string().nullable(),
  withdrawalReason: z.string().nullable(),
  recordVersion: z.number().int().positive(),
  createdBy: z.string().nullable(),
  createdAt: z.string(),
  updatedAt: z.string(),
});
export type ClaimItem = z.infer<typeof ClaimItemSchema>;

export function parseClaimItem(row: Record<string, unknown>): ClaimItem {
  return ClaimItemSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    claimCaseId: row.claim_case_id,
    itemType: row.item_type,
    linkedInventoryMovementId: row.linked_inventory_movement_id ?? null,
    linkedWmsOutboundShipmentId: row.linked_wms_outbound_shipment_id ?? null,
    itemMasterId: row.item_master_id ?? null,
    declaredQuantity: row.declared_quantity,
    uomCode: row.uom_code,
    declaredValue: row.declared_value ?? null,
    currency: row.currency ?? null,
    description: row.description,
    status: row.status,
    withdrawnAt: row.withdrawn_at ?? null,
    withdrawnBy: row.withdrawn_by ?? null,
    withdrawalReason: row.withdrawal_reason ?? null,
    recordVersion: row.record_version,
    createdBy: row.created_by ?? null,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  });
}

export const ClaimEvidenceLinkSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  claimCaseId: z.string().uuid(),
  evidenceType: ClaimEvidenceTypeSchema,
  evidenceId: z.string().uuid(),
  note: z.string().nullable(),
  addedByAuthUserId: z.string().uuid().nullable(),
  addedBy: z.string().nullable(),
  addedAt: z.string(),
});
export type ClaimEvidenceLink = z.infer<typeof ClaimEvidenceLinkSchema>;

export function parseClaimEvidenceLink(row: Record<string, unknown>): ClaimEvidenceLink {
  return ClaimEvidenceLinkSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    claimCaseId: row.claim_case_id,
    evidenceType: row.evidence_type,
    evidenceId: row.evidence_id,
    note: row.note ?? null,
    addedByAuthUserId: row.added_by_auth_user_id ?? null,
    addedBy: row.added_by ?? null,
    addedAt: row.added_at,
  });
}

export const ClaimInvestigationFindingSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  claimCaseId: z.string().uuid(),
  investigatorAuthUserId: z.string().uuid(),
  findingText: z.string(),
  evidenceSufficiency: ClaimEvidenceSufficiencySchema,
  createdBy: z.string().nullable(),
  createdAt: z.string(),
});
export type ClaimInvestigationFinding = z.infer<typeof ClaimInvestigationFindingSchema>;

export function parseClaimInvestigationFinding(row: Record<string, unknown>): ClaimInvestigationFinding {
  return ClaimInvestigationFindingSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    claimCaseId: row.claim_case_id,
    investigatorAuthUserId: row.investigator_auth_user_id,
    findingText: row.finding_text,
    evidenceSufficiency: row.evidence_sufficiency,
    createdBy: row.created_by ?? null,
    createdAt: row.created_at,
  });
}

export const ClaimResponsibilityReviewSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  claimCaseId: z.string().uuid(),
  versionNumber: z.number().int().positive(),
  isCurrent: z.boolean(),
  proposedResponsibilityParty: ClaimResponsibilityPartySchema,
  proposedReserveAmount: z.coerce.number().nullable(),
  proposedCurrency: z.string().nullable(),
  proposedRationale: z.string().nullable(),
  proposedByAuthUserId: z.string().uuid(),
  proposedBy: z.string().nullable(),
  proposedAt: z.string(),
  status: ClaimResponsibilityReviewStatusSchema,
  decidedByAuthUserId: z.string().uuid().nullable(),
  decidedBy: z.string().nullable(),
  decidedAt: z.string().nullable(),
  finalResponsibilityParty: ClaimResponsibilityPartySchema.nullable(),
  finalReserveAmount: z.coerce.number().nullable(),
  finalCurrency: z.string().nullable(),
  decisionNotes: z.string().nullable(),
  supersedesReviewId: z.string().uuid().nullable(),
  recordVersion: z.number().int().positive(),
  createdBy: z.string().nullable(),
  createdAt: z.string(),
  updatedAt: z.string(),
});
export type ClaimResponsibilityReview = z.infer<typeof ClaimResponsibilityReviewSchema>;

export function parseClaimResponsibilityReview(row: Record<string, unknown>): ClaimResponsibilityReview {
  return ClaimResponsibilityReviewSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    claimCaseId: row.claim_case_id,
    versionNumber: row.version_number,
    isCurrent: row.is_current,
    proposedResponsibilityParty: row.proposed_responsibility_party,
    proposedReserveAmount: row.proposed_reserve_amount ?? null,
    proposedCurrency: row.proposed_currency ?? null,
    proposedRationale: row.proposed_rationale ?? null,
    proposedByAuthUserId: row.proposed_by_auth_user_id,
    proposedBy: row.proposed_by ?? null,
    proposedAt: row.proposed_at,
    status: row.status,
    decidedByAuthUserId: row.decided_by_auth_user_id ?? null,
    decidedBy: row.decided_by ?? null,
    decidedAt: row.decided_at ?? null,
    finalResponsibilityParty: row.final_responsibility_party ?? null,
    finalReserveAmount: row.final_reserve_amount ?? null,
    finalCurrency: row.final_currency ?? null,
    decisionNotes: row.decision_notes ?? null,
    supersedesReviewId: row.supersedes_review_id ?? null,
    recordVersion: row.record_version,
    createdBy: row.created_by ?? null,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  });
}

export const ClaimRecoveryRecordSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  claimCaseId: z.string().uuid(),
  recoveredFrom: ClaimRecoveredFromSchema,
  recoveredAmount: z.coerce.number().nullable(),
  currency: z.string().nullable(),
  recoveredAt: z.string(),
  reference: z.string().nullable(),
  correctsRecoveryId: z.string().uuid().nullable(),
  recordedByAuthUserId: z.string().uuid().nullable(),
  recordedBy: z.string().nullable(),
  createdAt: z.string(),
});
export type ClaimRecoveryRecord = z.infer<typeof ClaimRecoveryRecordSchema>;

export function parseClaimRecoveryRecord(row: Record<string, unknown>): ClaimRecoveryRecord {
  return ClaimRecoveryRecordSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    claimCaseId: row.claim_case_id,
    recoveredFrom: row.recovered_from,
    recoveredAmount: row.recovered_amount ?? null,
    currency: row.currency ?? null,
    recoveredAt: row.recovered_at,
    reference: row.reference ?? null,
    correctsRecoveryId: row.corrects_recovery_id ?? null,
    recordedByAuthUserId: row.recorded_by_auth_user_id ?? null,
    recordedBy: row.recorded_by ?? null,
    createdAt: row.created_at,
  });
}

export const ClaimSettlementReadinessEvaluationSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  claimCaseId: z.string().uuid(),
  versionNumber: z.number().int().positive(),
  isCurrent: z.boolean(),
  evaluatedStatus: ClaimSettlementEvaluatedStatusSchema,
  blockers: z.array(z.record(z.string(), z.unknown())),
  evidence: z.record(z.string(), z.unknown()),
  reevaluationReason: z.string().nullable(),
  supersedesEvaluationId: z.string().uuid().nullable(),
  evaluatedByAuthUserId: z.string().uuid(),
  evaluatedBy: z.string().nullable(),
  recordVersion: z.number().int().positive(),
  createdBy: z.string().nullable(),
  createdAt: z.string(),
  updatedAt: z.string(),
});
export type ClaimSettlementReadinessEvaluation = z.infer<typeof ClaimSettlementReadinessEvaluationSchema>;

export function parseClaimSettlementReadinessEvaluation(row: Record<string, unknown>): ClaimSettlementReadinessEvaluation {
  return ClaimSettlementReadinessEvaluationSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    claimCaseId: row.claim_case_id,
    versionNumber: row.version_number,
    isCurrent: row.is_current,
    evaluatedStatus: row.evaluated_status,
    blockers: (row.blockers as Record<string, unknown>[] | null) ?? [],
    evidence: (row.evidence as Record<string, unknown>) ?? {},
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

export const ClaimSettlementReadinessHandoffSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  claimCaseId: z.string().uuid(),
  evaluationId: z.string().uuid(),
  idempotencyKey: z.string(),
  handedOffByAuthUserId: z.string().uuid(),
  handedOffBy: z.string().nullable(),
  handedOffAt: z.string(),
  /** app.claim_settlement_readiness_handoffs.handoff_seq -- a real `generated always as identity` column, never client-supplied. THE authoritative "most recent handoff" ordering app.close_claim_case itself relies on (never handedOffAt -- now() is fixed for the lifetime of one transaction in PostgreSQL, so two handoffs created inside the SAME transaction would otherwise carry identical handedOffAt values -- see the table's own migration comment). Coerced from number|string since a bigint identity column may arrive from the client as a string. */
  handoffSeq: z.coerce.number().int(),
  reconciliationStatus: ClaimReconciliationStatusSchema.nullable(),
  reconciliationNote: z.string().nullable(),
  reconciledAt: z.string().nullable(),
  updatedAt: z.string().nullable(),
  createdAt: z.string(),
});
export type ClaimSettlementReadinessHandoff = z.infer<typeof ClaimSettlementReadinessHandoffSchema>;

export function parseClaimSettlementReadinessHandoff(row: Record<string, unknown>): ClaimSettlementReadinessHandoff {
  return ClaimSettlementReadinessHandoffSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    claimCaseId: row.claim_case_id,
    evaluationId: row.evaluation_id,
    idempotencyKey: row.idempotency_key,
    handedOffByAuthUserId: row.handed_off_by_auth_user_id,
    handedOffBy: row.handed_off_by ?? null,
    handedOffAt: row.handed_off_at,
    handoffSeq: row.handoff_seq,
    reconciliationStatus: row.reconciliation_status ?? null,
    reconciliationNote: row.reconciliation_note ?? null,
    reconciledAt: row.reconciled_at ?? null,
    updatedAt: row.updated_at ?? null,
    createdAt: row.created_at,
  });
}

// --- Mutation input schemas ---

export const OpenClaimCaseInputSchema = z.object({
  operationalExceptionId: z.string().uuid(),
  claimantType: ClaimClaimantTypeSchema,
  claimantAccountId: z.string().uuid().nullable().optional(),
  claimantLabel: z.string().nullable().optional(),
  contactSnapshot: ClaimContactSnapshotSchema.nullable().optional(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type OpenClaimCaseInput = z.input<typeof OpenClaimCaseInputSchema>;

export const AddClaimItemInputSchema = z.object({
  caseId: z.string().uuid(),
  itemType: ClaimItemTypeSchema,
  linkedInventoryMovementId: z.string().uuid().nullable().optional(),
  linkedWmsOutboundShipmentId: z.string().uuid().nullable().optional(),
  itemMasterId: z.string().uuid().nullable().optional(),
  declaredQuantity: z.number().positive(),
  uomCode: z.string().min(1),
  declaredValue: z.number().nonnegative().nullable().optional(),
  currency: z.string().nullable().optional(),
  description: z.string().min(1),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type AddClaimItemInput = z.input<typeof AddClaimItemInputSchema>;

export const WithdrawClaimItemInputSchema = z.object({
  itemId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  reason: z.string().min(1),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type WithdrawClaimItemInput = z.input<typeof WithdrawClaimItemInputSchema>;

export const LinkClaimEvidenceInputSchema = z.object({
  caseId: z.string().uuid(),
  evidenceType: ClaimEvidenceTypeSchema,
  evidenceId: z.string().uuid(),
  note: z.string().nullable().optional(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type LinkClaimEvidenceInput = z.input<typeof LinkClaimEvidenceInputSchema>;

export const RecordClaimInvestigationFindingInputSchema = z.object({
  caseId: z.string().uuid(),
  findingText: z.string().min(1),
  evidenceSufficiency: ClaimEvidenceSufficiencySchema,
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type RecordClaimInvestigationFindingInput = z.input<typeof RecordClaimInvestigationFindingInputSchema>;

export const ProposeClaimResponsibilityInputSchema = z.object({
  caseId: z.string().uuid(),
  proposedResponsibilityParty: ClaimResponsibilityPartySchema,
  proposedReserveAmount: z.number().nonnegative().nullable().optional(),
  proposedCurrency: z.string().nullable().optional(),
  proposedRationale: z.string().min(1),
  /** Optimistic concurrency: null iff no current review exists yet for this case, else must equal the current review's own recordVersion (see app.propose_claim_responsibility's own comment). Required, not optional -- a caller must always be explicit about which state it is proposing on top of. */
  expectedVersion: z.number().int().positive().nullable(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type ProposeClaimResponsibilityInput = z.input<typeof ProposeClaimResponsibilityInputSchema>;

export const DecideClaimResponsibilityInputSchema = z.object({
  reviewId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  decision: ClaimResponsibilityDecisionSchema,
  finalResponsibilityParty: ClaimResponsibilityPartySchema.nullable().optional(),
  finalReserveAmount: z.number().nonnegative().nullable().optional(),
  finalCurrency: z.string().nullable().optional(),
  decisionNotes: z.string().min(1),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type DecideClaimResponsibilityInput = z.input<typeof DecideClaimResponsibilityInputSchema>;

export const RecordClaimRecoveryInputSchema = z.object({
  caseId: z.string().uuid(),
  recoveredFrom: ClaimRecoveredFromSchema,
  recoveredAmount: z.number().positive(),
  currency: z.string().length(3),
  recoveredAt: z.string().nullable().optional(),
  reference: z.string().nullable().optional(),
  correctsRecoveryId: z.string().uuid().nullable().optional(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type RecordClaimRecoveryInput = z.input<typeof RecordClaimRecoveryInputSchema>;

export const EvaluateClaimSettlementReadinessInputSchema = z.object({
  caseId: z.string().uuid(),
  reevaluationReason: z.string().nullable().optional(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type EvaluateClaimSettlementReadinessInput = z.input<typeof EvaluateClaimSettlementReadinessInputSchema>;

export const HandoffClaimSettlementReadinessInputSchema = z.object({
  caseId: z.string().uuid(),
  idempotencyKey: z.string().min(1),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type HandoffClaimSettlementReadinessInput = z.input<typeof HandoffClaimSettlementReadinessInputSchema>;

/** service_role only -- a Finance-side worker callback, never a client action (no authenticated grant at all). */
export const RecordClaimFinanceReconciliationOutcomeInputSchema = z.object({
  handoffId: z.string().uuid(),
  status: ClaimReconciliationStatusSchema,
  note: z.string().min(1),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type RecordClaimFinanceReconciliationOutcomeInput = z.input<typeof RecordClaimFinanceReconciliationOutcomeInputSchema>;

export const CloseClaimCaseInputSchema = z.object({
  caseId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  exceptionExpectedVersion: z.number().int().positive(),
  closureNote: z.string().min(1),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type CloseClaimCaseInput = z.input<typeof CloseClaimCaseInputSchema>;

export const ReopenClaimCaseInputSchema = z.object({
  caseId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  exceptionExpectedVersion: z.number().int().positive(),
  reason: z.string().min(1),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type ReopenClaimCaseInput = z.input<typeof ReopenClaimCaseInputSchema>;

// --- Read input schemas ---

export const ListClaimCasesInputSchema = z.object({
  tenantId: z.string().uuid(),
  actorAuthUserId: z.string().uuid(),
  claimStageFilter: ClaimStageSchema.nullable().optional(),
  exceptionTypeFilter: z.string().nullable().optional(),
  exceptionSeverityFilter: z.string().nullable().optional(),
  exceptionStatusFilter: z.string().nullable().optional(),
  shipmentOrderIdFilter: z.string().uuid().nullable().optional(),
  cursorUpdatedAt: z.string().nullable().optional(),
  cursorId: z.string().uuid().nullable().optional(),
  limit: z.number().int().positive().optional(),
});
export type ListClaimCasesInput = z.input<typeof ListClaimCasesInputSchema>;
