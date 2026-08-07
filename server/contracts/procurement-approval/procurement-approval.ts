/**
 * Procurement Approval contract (PRC-259, CG-S11-PRC-010). Mirrors
 * supabase/migrations/20260730660000_create_procurement_approval.sql --
 * Zod schemas + parse functions for app.procurement_approval_policies,
 * app.procurement_approval_context_snapshots (masked read), and
 * app.procurement_exception_requests, plus one *InputSchema per mutation.
 *
 * Delegation/escalation/cancel/history/pending-inbox reads still go straight through
 * the already-existing Approval Engine contract (server/contracts/approval/approval.ts,
 * PLT-123) -- none of them needs a procurement-specific wrapper (mirrors
 * server/contracts/quotation/quotation-approval.ts's own header: "neither changes a
 * request's final outcome").
 *
 * Deliberately does NOT widen server/contracts/vendor-profile/vendor-profile.ts,
 * server/contracts/procurement-rate/procurement-rate.ts, or
 * server/contracts/vendor-comparison/vendor-comparison.ts -- the four domain sync
 * wrapper RPCs (app.decide_vendor_activation_approval_step /
 * app.decide_rate_version_approval_step / app.decide_vendor_selection_approval_step /
 * app.decide_procurement_exception_approval_step) return a minimal, LOCAL sync-result
 * shape here instead of the full entity row, since this capability's own unified
 * inbox/detail UI (Prompt 259 §15) never needs to duplicate another capability's own
 * detail projection -- deciding a step and viewing the governed entity's own full
 * record are two different surfaces, exactly as they already are for quotations
 * (the quotation approvals inbox links out to the quotation's own detail page rather
 * than rendering it inline).
 */

import { z } from "zod";

export const PROCUREMENT_APPROVAL_ENTITY_TYPES = [
  "vendor_activation",
  "rate_version",
  "vendor_selection",
  "purchase_order",
  "vendor_contract",
  "exception_override",
] as const;
export const ProcurementApprovalEntityTypeSchema = z.enum(PROCUREMENT_APPROVAL_ENTITY_TYPES);
export type ProcurementApprovalEntityType = z.infer<typeof ProcurementApprovalEntityTypeSchema>;

export const PROCUREMENT_APPROVAL_STATUSES = ["not_required", "pending", "approved", "rejected"] as const;
export const ProcurementApprovalStatusSchema = z.enum(PROCUREMENT_APPROVAL_STATUSES);
export type ProcurementApprovalStatus = z.infer<typeof ProcurementApprovalStatusSchema>;

export const PROCUREMENT_APPROVAL_POLICY_STATUSES = ["draft", "published", "archived"] as const;
export const ProcurementApprovalPolicyStatusSchema = z.enum(PROCUREMENT_APPROVAL_POLICY_STATUSES);
export type ProcurementApprovalPolicyStatus = z.infer<typeof ProcurementApprovalPolicyStatusSchema>;

// --- Core rows ---

export const ProcurementApprovalPolicyVersionSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  entityType: ProcurementApprovalEntityTypeSchema,
  minValueAmount: z.coerce.number().nullable(),
  alwaysRequired: z.boolean(),
  status: ProcurementApprovalPolicyStatusSchema,
  supersedesVersionId: z.string().uuid().nullable(),
  recordVersion: z.number().int().positive(),
  createdBy: z.string().nullable(),
  createdAt: z.string(),
  updatedAt: z.string(),
});
export type ProcurementApprovalPolicyVersion = z.infer<typeof ProcurementApprovalPolicyVersionSchema>;

export function parseProcurementApprovalPolicyVersion(row: Record<string, unknown>): ProcurementApprovalPolicyVersion {
  return ProcurementApprovalPolicyVersionSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    entityType: row.entity_type,
    minValueAmount: row.min_value_amount ?? null,
    alwaysRequired: row.always_required,
    status: row.status,
    supersedesVersionId: row.supersedes_version_id ?? null,
    recordVersion: row.record_version,
    createdBy: row.created_by ?? null,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  });
}

/** Maps app.evaluate_procurement_approval_requirement()'s returned row. Reason codes only, never a dollar figure. */
export const ProcurementApprovalRequirementSchema = z.object({
  required: z.boolean(),
  reasons: z.array(z.string()),
  policyVersionId: z.string().uuid().nullable(),
});
export type ProcurementApprovalRequirement = z.infer<typeof ProcurementApprovalRequirementSchema>;

export function parseProcurementApprovalRequirement(row: Record<string, unknown>): ProcurementApprovalRequirement {
  return ProcurementApprovalRequirementSchema.parse({
    required: row.required,
    reasons: row.reasons ?? [],
    policyVersionId: row.policy_version_id ?? null,
  });
}

/** Maps app.get_procurement_approval_context_snapshot()'s returned row -- valueAmount/currency are masked (null, costMasked=true) for a caller without PRC:View cost. reasons/entityType/context are always visible regardless. */
export const ProcurementApprovalContextSnapshotSchema = z.object({
  id: z.string().uuid(),
  approvalRequestId: z.string().uuid(),
  tenantId: z.string().uuid(),
  entityType: ProcurementApprovalEntityTypeSchema,
  entityId: z.string().uuid().nullable(),
  valueAmount: z.coerce.number().nullable(),
  currency: z.string().nullable(),
  costMasked: z.boolean(),
  reasons: z.array(z.string()),
  policyVersionId: z.string().uuid().nullable(),
  context: z.record(z.string(), z.unknown()),
  sourceRecordVersion: z.number().int().nullable(),
  createdBy: z.string().nullable(),
  createdAt: z.string(),
});
export type ProcurementApprovalContextSnapshot = z.infer<typeof ProcurementApprovalContextSnapshotSchema>;

export function parseProcurementApprovalContextSnapshot(row: Record<string, unknown>): ProcurementApprovalContextSnapshot {
  return ProcurementApprovalContextSnapshotSchema.parse({
    id: row.id,
    approvalRequestId: row.approval_request_id,
    tenantId: row.tenant_id,
    entityType: row.entity_type,
    entityId: row.entity_id ?? null,
    valueAmount: row.value_amount ?? null,
    currency: row.currency ?? null,
    costMasked: row.cost_masked,
    reasons: row.reasons ?? [],
    policyVersionId: row.policy_version_id ?? null,
    context: (row.context as Record<string, unknown>) ?? {},
    sourceRecordVersion: row.source_record_version ?? null,
    createdBy: row.created_by ?? null,
    createdAt: row.created_at,
  });
}

export const PROCUREMENT_EXCEPTION_REQUEST_STATUSES = ["submitted", "approved", "rejected", "cancelled"] as const;
export const ProcurementExceptionRequestStatusSchema = z.enum(PROCUREMENT_EXCEPTION_REQUEST_STATUSES);
export type ProcurementExceptionRequestStatus = z.infer<typeof ProcurementExceptionRequestStatusSchema>;

export const ProcurementExceptionRequestSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  relatedEntityType: z.string().nullable(),
  relatedEntityId: z.string().uuid().nullable(),
  exceptionType: z.string(),
  reason: z.string(),
  requestedOutcome: z.string().nullable(),
  status: ProcurementExceptionRequestStatusSchema,
  approvalStatus: ProcurementApprovalStatusSchema,
  approvalRequestId: z.string().uuid().nullable(),
  idempotencyKey: z.string(),
  recordVersion: z.number().int().positive(),
  createdBy: z.string().nullable(),
  createdAt: z.string(),
  updatedAt: z.string(),
});
export type ProcurementExceptionRequest = z.infer<typeof ProcurementExceptionRequestSchema>;

export function parseProcurementExceptionRequest(row: Record<string, unknown>): ProcurementExceptionRequest {
  return ProcurementExceptionRequestSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    relatedEntityType: row.related_entity_type ?? null,
    relatedEntityId: row.related_entity_id ?? null,
    exceptionType: row.exception_type,
    reason: row.reason,
    requestedOutcome: row.requested_outcome ?? null,
    status: row.status,
    approvalStatus: row.approval_status,
    approvalRequestId: row.approval_request_id ?? null,
    idempotencyKey: row.idempotency_key,
    recordVersion: row.record_version,
    createdBy: row.created_by ?? null,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  });
}

// --- Domain sync wrapper results (minimal -- see file header) ---

export const VendorActivationApprovalSyncResultSchema = z.object({
  masterRecordId: z.string().uuid(),
  approvalStatus: ProcurementApprovalStatusSchema,
});
export type VendorActivationApprovalSyncResult = z.infer<typeof VendorActivationApprovalSyncResultSchema>;

export function parseVendorActivationApprovalSyncResult(row: Record<string, unknown>): VendorActivationApprovalSyncResult {
  return VendorActivationApprovalSyncResultSchema.parse({
    masterRecordId: row.master_record_id,
    approvalStatus: row.approval_status,
  });
}

export const RateVersionApprovalSyncResultSchema = z.object({
  id: z.string().uuid(),
  governanceApprovalStatus: ProcurementApprovalStatusSchema,
});
export type RateVersionApprovalSyncResult = z.infer<typeof RateVersionApprovalSyncResultSchema>;

export function parseRateVersionApprovalSyncResult(row: Record<string, unknown>): RateVersionApprovalSyncResult {
  return RateVersionApprovalSyncResultSchema.parse({
    id: row.id,
    governanceApprovalStatus: row.governance_approval_status,
  });
}

export const VendorSelectionApprovalSyncResultSchema = z.object({
  id: z.string().uuid(),
  approvalStatus: ProcurementApprovalStatusSchema,
});
export type VendorSelectionApprovalSyncResult = z.infer<typeof VendorSelectionApprovalSyncResultSchema>;

export function parseVendorSelectionApprovalSyncResult(row: Record<string, unknown>): VendorSelectionApprovalSyncResult {
  return VendorSelectionApprovalSyncResultSchema.parse({
    id: row.id,
    approvalStatus: row.approval_status,
  });
}

export const PurchaseOrderApprovalSyncResultSchema = z.object({
  id: z.string().uuid(),
  approvalStatus: ProcurementApprovalStatusSchema,
});
export type PurchaseOrderApprovalSyncResult = z.infer<typeof PurchaseOrderApprovalSyncResultSchema>;

export function parsePurchaseOrderApprovalSyncResult(row: Record<string, unknown>): PurchaseOrderApprovalSyncResult {
  return PurchaseOrderApprovalSyncResultSchema.parse({
    id: row.id,
    approvalStatus: row.approval_status,
  });
}

// --- Mutation input schemas ---

export const CreateProcurementApprovalPolicyVersionInputSchema = z
  .object({
    tenantId: z.string().uuid(),
    entityType: ProcurementApprovalEntityTypeSchema,
    minValueAmount: z.coerce.number().min(0).nullable().default(null),
    alwaysRequired: z.boolean().default(false),
    actorAuthUserId: z.string().uuid(),
    createdBy: z.string().min(1),
  })
  .refine((input) => input.minValueAmount !== null || input.alwaysRequired, {
    message: "At least one of minValueAmount/alwaysRequired is required",
  });
export type CreateProcurementApprovalPolicyVersionInput = z.input<typeof CreateProcurementApprovalPolicyVersionInputSchema>;

export const PublishProcurementApprovalPolicyVersionInputSchema = z.object({
  policyVersionId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  supersedesVersionId: z.string().uuid().nullable().default(null),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type PublishProcurementApprovalPolicyVersionInput = z.input<typeof PublishProcurementApprovalPolicyVersionInputSchema>;

export const EvaluateProcurementApprovalRequirementInputSchema = z.object({
  entityType: ProcurementApprovalEntityTypeSchema,
  tenantId: z.string().uuid(),
  valueAmount: z.coerce.number().nullable().default(null),
  actorAuthUserId: z.string().uuid(),
});
export type EvaluateProcurementApprovalRequirementInput = z.input<typeof EvaluateProcurementApprovalRequirementInputSchema>;

export const GetProcurementApprovalContextSnapshotInputSchema = z.object({
  approvalRequestId: z.string().uuid(),
  actorAuthUserId: z.string().uuid(),
});
export type GetProcurementApprovalContextSnapshotInput = z.input<typeof GetProcurementApprovalContextSnapshotInputSchema>;

/** Shared input shape for all four domain sync wrapper mutations -- the same approved/rejected verb the Approval Engine itself supports (mirrors DecideQuotationApprovalStepInputSchema, COM-153: "request revision" is not a fourth decision value). Batch 257-259 review (C-18, HIGH): reauthConfirmedAt is now required -- must be within the last 5 minutes (each app.decide_*_approval_step wrapper's own server-side freshness check, reusing the exact PRC-254/COM-157 p_reauth_confirmed_at pattern) -- Prompt 259 §16's MFA-for-privileged-approvers gate. No live MFA challenge UI exists yet anywhere in this repository (the same disclosed boundary COM-157 already carries) -- the UI captures the current timestamp as the caller's own attestation, which the server independently re-validates for freshness on every call, never trusted blindly. */
export const DecideProcurementApprovalStepInputSchema = z.object({
  requestStepId: z.string().uuid(),
  decision: z.enum(["approved", "rejected"]),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
  reauthConfirmedAt: z.string(),
  reason: z.string().nullable().default(null),
});
export type DecideProcurementApprovalStepInput = z.input<typeof DecideProcurementApprovalStepInputSchema>;

export const CreateProcurementExceptionRequestInputSchema = z.object({
  tenantId: z.string().uuid(),
  relatedEntityType: z.string().nullable().default(null),
  relatedEntityId: z.string().uuid().nullable().default(null),
  exceptionType: z.string().min(1),
  reason: z.string().min(1),
  requestedOutcome: z.string().nullable().default(null),
  idempotencyKey: z.string().min(1),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type CreateProcurementExceptionRequestInput = z.input<typeof CreateProcurementExceptionRequestInputSchema>;

export const CancelProcurementExceptionRequestInputSchema = z.object({
  id: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  reason: z.string().min(1),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type CancelProcurementExceptionRequestInput = z.input<typeof CancelProcurementExceptionRequestInputSchema>;

export const ListProcurementExceptionRequestsInputSchema = z.object({
  tenantId: z.string().uuid(),
  actorAuthUserId: z.string().uuid(),
  statusFilter: ProcurementExceptionRequestStatusSchema.nullable().default(null),
  limit: z.number().int().positive().max(200).default(100),
});
export type ListProcurementExceptionRequestsInput = z.input<typeof ListProcurementExceptionRequestsInputSchema>;
