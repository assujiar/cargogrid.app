/**
 * Purchase Order contract (PRC-260, CG-S11-PRC-011). Mirrors
 * supabase/migrations/20260730680000_create_procurement_purchase_order.sql -- Zod
 * schemas + parse functions for PurchaseOrder (cost-masked, mirrors RfqResponseSchema's
 * partial-masking shape -- NOT VendorComparisonSchema's all-or-nothing shape, since
 * Operations/Finance viewers need non-cost fields without PRC:View cost, access rule 26),
 * PurchaseOrderLine (plain, no cost data), and PurchaseOrderEvent (reason masked), plus
 * one *InputSchema per mutation (camelCase field names, actorAuthUserId/actorLabel/
 * expectedVersion/idempotencyKey included where the corresponding RPC needs them), the
 * same shape server/contracts/vendor-comparison/vendor-comparison.ts already establishes
 * for this checkpoint's own template.
 */

import { z } from "zod";

export const PURCHASE_ORDER_STATUSES = ["draft", "submitted", "issued", "acknowledged", "cancelled", "superseded"] as const;
export const PurchaseOrderStatusSchema = z.enum(PURCHASE_ORDER_STATUSES);
export type PurchaseOrderStatus = z.infer<typeof PurchaseOrderStatusSchema>;

export const PURCHASE_ORDER_APPROVAL_STATUSES = ["not_required", "pending", "approved", "rejected"] as const;
export const PurchaseOrderApprovalStatusSchema = z.enum(PURCHASE_ORDER_APPROVAL_STATUSES);
export type PurchaseOrderApprovalStatus = z.infer<typeof PurchaseOrderApprovalStatusSchema>;

export const PURCHASE_ORDER_FULFILLMENT_STATUSES = ["not_started", "partial", "fulfilled"] as const;
export const PurchaseOrderFulfillmentStatusSchema = z.enum(PURCHASE_ORDER_FULFILLMENT_STATUSES);
export type PurchaseOrderFulfillmentStatus = z.infer<typeof PurchaseOrderFulfillmentStatusSchema>;

export const PurchaseOrderSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  orgUnitId: z.string().uuid().nullable(),
  poNumber: z.string(),
  version: z.number().int().positive(),
  revisedFromId: z.string().uuid().nullable(),
  comparisonId: z.string().uuid(),
  selectedOfferId: z.string().uuid(),
  rfqId: z.string().uuid(),
  sourcingRequestId: z.string().uuid(),
  vendorMasterId: z.string().uuid(),
  currency: z.string().nullable(),
  subtotalAmount: z.coerce.number().nullable(),
  taxCode: z.string().nullable(),
  taxAmount: z.coerce.number().nullable(),
  totalAmount: z.coerce.number().nullable(),
  paymentTermDays: z.number().int().nullable(),
  costMasked: z.boolean(),
  expectedDeliveryDate: z.string().nullable(),
  servicePeriodStart: z.string().nullable(),
  servicePeriodEnd: z.string().nullable(),
  commercialTerms: z.string().nullable(),
  notes: z.string().nullable(),
  status: PurchaseOrderStatusSchema,
  approvalStatus: PurchaseOrderApprovalStatusSchema,
  approvalRequestId: z.string().uuid().nullable(),
  fulfillmentStatus: PurchaseOrderFulfillmentStatusSchema,
  fulfillmentReference: z.string().nullable(),
  fulfillmentUpdatedAt: z.string().nullable(),
  fulfillmentUpdatedBy: z.string().nullable(),
  submittedAt: z.string().nullable(),
  submittedBy: z.string().nullable(),
  issuedAt: z.string().nullable(),
  issuedBy: z.string().nullable(),
  acknowledgedAt: z.string().nullable(),
  acknowledgedBy: z.string().nullable(),
  acknowledgementNote: z.string().nullable(),
  cancelledAt: z.string().nullable(),
  cancelReason: z.string().nullable(),
  idempotencyKey: z.string(),
  recordVersion: z.number().int().positive(),
  createdBy: z.string().nullable(),
  createdAt: z.string(),
  updatedAt: z.string(),
});
export type PurchaseOrder = z.infer<typeof PurchaseOrderSchema>;

export function parsePurchaseOrder(row: Record<string, unknown>): PurchaseOrder {
  return PurchaseOrderSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    orgUnitId: row.org_unit_id,
    poNumber: row.po_number,
    version: row.version,
    revisedFromId: row.revised_from_id,
    comparisonId: row.comparison_id,
    selectedOfferId: row.selected_offer_id,
    rfqId: row.rfq_id,
    sourcingRequestId: row.sourcing_request_id,
    vendorMasterId: row.vendor_master_id,
    currency: row.currency,
    subtotalAmount: row.subtotal_amount,
    taxCode: row.tax_code,
    taxAmount: row.tax_amount,
    totalAmount: row.total_amount,
    paymentTermDays: row.payment_term_days,
    costMasked: row.cost_masked ?? false,
    expectedDeliveryDate: row.expected_delivery_date,
    servicePeriodStart: row.service_period_start,
    servicePeriodEnd: row.service_period_end,
    commercialTerms: row.commercial_terms,
    notes: row.notes,
    status: row.status,
    approvalStatus: row.approval_status,
    approvalRequestId: row.approval_request_id,
    fulfillmentStatus: row.fulfillment_status,
    fulfillmentReference: row.fulfillment_reference,
    fulfillmentUpdatedAt: row.fulfillment_updated_at,
    fulfillmentUpdatedBy: row.fulfillment_updated_by,
    submittedAt: row.submitted_at,
    submittedBy: row.submitted_by,
    issuedAt: row.issued_at,
    issuedBy: row.issued_by,
    acknowledgedAt: row.acknowledged_at,
    acknowledgedBy: row.acknowledged_by,
    acknowledgementNote: row.acknowledgement_note,
    cancelledAt: row.cancelled_at,
    cancelReason: row.cancel_reason,
    idempotencyKey: row.idempotency_key,
    recordVersion: row.record_version,
    createdBy: row.created_by,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  });
}

export const PurchaseOrderLineSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  purchaseOrderId: z.string().uuid(),
  lineNo: z.number().int().positive(),
  sourceRequirementLineId: z.string().uuid().nullable(),
  description: z.string(),
  quantity: z.coerce.number().nullable(),
  uom: z.string().nullable(),
  notes: z.string().nullable(),
  createdAt: z.string(),
});
export type PurchaseOrderLine = z.infer<typeof PurchaseOrderLineSchema>;

export function parsePurchaseOrderLine(row: Record<string, unknown>): PurchaseOrderLine {
  return PurchaseOrderLineSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    purchaseOrderId: row.purchase_order_id,
    lineNo: row.line_no,
    sourceRequirementLineId: row.source_requirement_line_id,
    description: row.description,
    quantity: row.quantity,
    uom: row.uom,
    notes: row.notes,
    createdAt: row.created_at,
  });
}

export const PurchaseOrderEventSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  purchaseOrderId: z.string().uuid(),
  fromStatus: z.string().nullable(),
  toStatus: z.string(),
  reason: z.string().nullable(),
  costMasked: z.boolean(),
  actorAuthUserId: z.string().uuid().nullable(),
  actorLabel: z.string().nullable(),
  occurredAt: z.string(),
});
export type PurchaseOrderEvent = z.infer<typeof PurchaseOrderEventSchema>;

export function parsePurchaseOrderEvent(row: Record<string, unknown>): PurchaseOrderEvent {
  return PurchaseOrderEventSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    purchaseOrderId: row.purchase_order_id,
    fromStatus: row.from_status,
    toStatus: row.to_status,
    reason: row.reason,
    costMasked: row.cost_masked ?? false,
    actorAuthUserId: row.actor_auth_user_id,
    actorLabel: row.actor_label,
    occurredAt: row.occurred_at,
  });
}

// -- Mutation inputs -------------------------------------------------------

export const DraftPurchaseOrderFromSelectionInputSchema = z.object({
  tenantId: z.string().uuid(),
  comparisonId: z.string().uuid(),
  taxCode: z.string().nullable().default(null),
  paymentTermDays: z.number().int().nonnegative().nullable().default(null),
  expectedDeliveryDate: z.string().nullable().default(null),
  servicePeriodStart: z.string().nullable().default(null),
  servicePeriodEnd: z.string().nullable().default(null),
  commercialTerms: z.string().nullable().default(null),
  notes: z.string().nullable().default(null),
  idempotencyKey: z.string().min(1),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type DraftPurchaseOrderFromSelectionInput = z.input<typeof DraftPurchaseOrderFromSelectionInputSchema>;

export const SubmitPurchaseOrderForApprovalInputSchema = z.object({
  purchaseOrderId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type SubmitPurchaseOrderForApprovalInput = z.input<typeof SubmitPurchaseOrderForApprovalInputSchema>;

export const IssuePurchaseOrderInputSchema = z.object({
  purchaseOrderId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type IssuePurchaseOrderInput = z.input<typeof IssuePurchaseOrderInputSchema>;

export const AcknowledgePurchaseOrderInputSchema = z.object({
  purchaseOrderId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  acknowledgementNote: z.string().min(1),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type AcknowledgePurchaseOrderInput = z.input<typeof AcknowledgePurchaseOrderInputSchema>;

export const RecordPurchaseOrderFulfillmentStatusInputSchema = z.object({
  purchaseOrderId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  fulfillmentStatus: z.enum(["partial", "fulfilled"]),
  fulfillmentReference: z.string().min(1),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type RecordPurchaseOrderFulfillmentStatusInput = z.input<typeof RecordPurchaseOrderFulfillmentStatusInputSchema>;

export const AmendPurchaseOrderInputSchema = z.object({
  purchaseOrderId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  reason: z.string().min(1),
  idempotencyKey: z.string().min(1),
  paymentTermDays: z.number().int().nonnegative().nullable().default(null),
  expectedDeliveryDate: z.string().nullable().default(null),
  servicePeriodStart: z.string().nullable().default(null),
  servicePeriodEnd: z.string().nullable().default(null),
  commercialTerms: z.string().nullable().default(null),
  notes: z.string().nullable().default(null),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type AmendPurchaseOrderInput = z.input<typeof AmendPurchaseOrderInputSchema>;

export const CancelPurchaseOrderInputSchema = z.object({
  purchaseOrderId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  reason: z.string().min(1),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type CancelPurchaseOrderInput = z.input<typeof CancelPurchaseOrderInputSchema>;
