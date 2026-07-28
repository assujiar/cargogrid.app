/**
 * Actual Cost contract (OPS-178, CG-S8-OPS-012). Mirrors
 * supabase/migrations/20260728110000_create_operations_actual_cost.sql's
 * app.shipment_actual_costs/app.shipment_actual_cost_components shapes and their RPCs.
 *
 * Componentized, exact (numeric, never float) actual-cost capture with vendor/internal
 * source and assignment/document lineage, approval, and estimated-versus-actual
 * variance -- operational cost recording only, no Finance/AP posting.
 */

import { z } from "zod";

export const ActualCostCategorySchema = z.enum(["freight", "trucking", "fuel_surcharge", "handling", "customs", "warehousing", "other"]);
export type ActualCostCategory = z.infer<typeof ActualCostCategorySchema>;

export const ActualCostSourceTypeSchema = z.enum(["vendor", "internal"]);
export type ActualCostSourceType = z.infer<typeof ActualCostSourceTypeSchema>;

export const ShipmentActualCostSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  shipmentOrderId: z.string().uuid(),
  versionNumber: z.number().int().positive(),
  isCurrent: z.boolean(),
  supersedesVersionId: z.string().uuid().nullable(),
  status: z.enum(["draft", "submitted", "approved", "rejected"]),
  currency: z.string(),
  estimatedAmount: z.number().nullable(),
  totalAmount: z.number(),
  approvedByAuthUserId: z.string().uuid().nullable(),
  approvedAt: z.string().nullable(),
  rejectionReason: z.string().nullable(),
  adjustmentReason: z.string().nullable(),
  recordVersion: z.number().int(),
  createdBy: z.string().nullable(),
  createdAt: z.string(),
  updatedAt: z.string(),
});
export type ShipmentActualCost = z.infer<typeof ShipmentActualCostSchema>;

export function parseShipmentActualCost(row: Record<string, unknown>): ShipmentActualCost {
  return ShipmentActualCostSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    shipmentOrderId: row.shipment_order_id,
    versionNumber: row.version_number,
    isCurrent: row.is_current,
    supersedesVersionId: row.supersedes_version_id ?? null,
    status: row.status,
    currency: row.currency,
    estimatedAmount: row.estimated_amount === null || row.estimated_amount === undefined ? null : Number(row.estimated_amount),
    totalAmount: Number(row.total_amount),
    approvedByAuthUserId: row.approved_by_auth_user_id ?? null,
    approvedAt: row.approved_at ?? null,
    rejectionReason: row.rejection_reason ?? null,
    adjustmentReason: row.adjustment_reason ?? null,
    recordVersion: row.record_version,
    createdBy: row.created_by ?? null,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  });
}

/** app.shipment_actual_costs_directory's own row shape -- total_amount/estimated_amount are null (costMasked=true) for an actor lacking OPS:View cost. */
export const ShipmentActualCostDirectoryRowSchema = ShipmentActualCostSchema.omit({ estimatedAmount: true, totalAmount: true }).extend({
  estimatedAmount: z.number().nullable(),
  totalAmount: z.number().nullable(),
  costMasked: z.boolean(),
});
export type ShipmentActualCostDirectoryRow = z.infer<typeof ShipmentActualCostDirectoryRowSchema>;

export function parseShipmentActualCostDirectoryRow(row: Record<string, unknown>): ShipmentActualCostDirectoryRow {
  return ShipmentActualCostDirectoryRowSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    shipmentOrderId: row.shipment_order_id,
    versionNumber: row.version_number,
    isCurrent: row.is_current,
    supersedesVersionId: row.supersedes_version_id ?? null,
    status: row.status,
    currency: row.currency,
    estimatedAmount: row.estimated_amount === null || row.estimated_amount === undefined ? null : Number(row.estimated_amount),
    totalAmount: row.total_amount === null || row.total_amount === undefined ? null : Number(row.total_amount),
    costMasked: row.cost_masked,
    approvedByAuthUserId: row.approved_by_auth_user_id ?? null,
    approvedAt: row.approved_at ?? null,
    rejectionReason: row.rejection_reason ?? null,
    adjustmentReason: row.adjustment_reason ?? null,
    recordVersion: row.record_version,
    createdBy: row.created_by ?? null,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  });
}

export const ShipmentActualCostComponentSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  actualCostId: z.string().uuid(),
  category: ActualCostCategorySchema,
  sourceType: ActualCostSourceTypeSchema,
  vendorId: z.string().uuid().nullable(),
  assignmentId: z.string().uuid().nullable(),
  documentFileId: z.string().uuid().nullable(),
  description: z.string().nullable(),
  quantity: z.number(),
  uom: z.string().nullable(),
  rate: z.number(),
  minimumCharge: z.number().nullable(),
  surcharge: z.number(),
  amount: z.number(),
  currency: z.string(),
  idempotencyKey: z.string().nullable(),
  createdBy: z.string().nullable(),
  createdAt: z.string(),
});
export type ShipmentActualCostComponent = z.infer<typeof ShipmentActualCostComponentSchema>;

export function parseShipmentActualCostComponent(row: Record<string, unknown>): ShipmentActualCostComponent {
  return ShipmentActualCostComponentSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    actualCostId: row.actual_cost_id,
    category: row.category,
    sourceType: row.source_type,
    vendorId: row.vendor_id ?? null,
    assignmentId: row.assignment_id ?? null,
    documentFileId: row.document_file_id ?? null,
    description: row.description ?? null,
    quantity: Number(row.quantity),
    uom: row.uom ?? null,
    rate: Number(row.rate),
    minimumCharge: row.minimum_charge === null || row.minimum_charge === undefined ? null : Number(row.minimum_charge),
    surcharge: Number(row.surcharge),
    amount: Number(row.amount),
    currency: row.currency,
    idempotencyKey: row.idempotency_key ?? null,
    createdBy: row.created_by ?? null,
    createdAt: row.created_at,
  });
}

export const ActualCostVarianceSchema = z.object({
  totalAmount: z.number(),
  estimatedAmount: z.number().nullable(),
  varianceAmount: z.number().nullable(),
  varianceAvailable: z.boolean(),
});
export type ActualCostVariance = z.infer<typeof ActualCostVarianceSchema>;

export function parseActualCostVariance(row: Record<string, unknown>): ActualCostVariance {
  return ActualCostVarianceSchema.parse({
    totalAmount: Number(row.total_amount),
    estimatedAmount: row.estimated_amount === null || row.estimated_amount === undefined ? null : Number(row.estimated_amount),
    varianceAmount: row.variance_amount === null || row.variance_amount === undefined ? null : Number(row.variance_amount),
    varianceAvailable: row.variance_available,
  });
}

export const CreateActualCostDraftInputSchema = z.object({
  tenantId: z.string().uuid(),
  shipmentOrderId: z.string().uuid(),
  currency: z.string().min(1),
  estimatedAmount: z.number().nullable().optional(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type CreateActualCostDraftInput = z.input<typeof CreateActualCostDraftInputSchema>;

export const AddActualCostComponentInputSchema = z.object({
  actualCostId: z.string().uuid(),
  category: ActualCostCategorySchema,
  sourceType: ActualCostSourceTypeSchema,
  vendorId: z.string().uuid().nullable().optional(),
  assignmentId: z.string().uuid().nullable().optional(),
  documentFileId: z.string().uuid().nullable().optional(),
  description: z.string().nullable().optional(),
  quantity: z.number().positive(),
  uom: z.string().nullable().optional(),
  rate: z.number().nonnegative(),
  minimumCharge: z.number().nonnegative().nullable().optional(),
  surcharge: z.number().nonnegative().optional(),
  idempotencyKey: z.string().min(1),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type AddActualCostComponentInput = z.input<typeof AddActualCostComponentInputSchema>;

export const RemoveActualCostComponentInputSchema = z.object({
  componentId: z.string().uuid(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type RemoveActualCostComponentInput = z.input<typeof RemoveActualCostComponentInputSchema>;

export const SubmitActualCostInputSchema = z.object({
  actualCostId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type SubmitActualCostInput = z.input<typeof SubmitActualCostInputSchema>;

export const DecideActualCostInputSchema = z.object({
  actualCostId: z.string().uuid(),
  decision: z.enum(["approved", "rejected"]),
  reason: z.string().nullable().optional(),
  expectedVersion: z.number().int().positive(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type DecideActualCostInput = z.input<typeof DecideActualCostInputSchema>;

export const CreateActualCostAdjustmentInputSchema = z.object({
  previousActualCostId: z.string().uuid(),
  adjustmentReason: z.string().min(1),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type CreateActualCostAdjustmentInput = z.input<typeof CreateActualCostAdjustmentInputSchema>;

export const ActualCostRecordInputSchema = z.object({
  actualCostId: z.string().uuid(),
  actorAuthUserId: z.string().uuid(),
});
export type ActualCostRecordInput = z.input<typeof ActualCostRecordInputSchema>;
