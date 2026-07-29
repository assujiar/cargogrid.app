/**
 * Vendor Bill contract (FIN-200, CG-S9-FIN-011). Mirrors
 * supabase/migrations/20260729140000_create_finance_vendor_bill.sql's
 * app.finance_vendor_bills / app.finance_vendor_bill_lines shapes and their RPCs.
 */

import { z } from "zod";

export const FINANCE_VENDOR_BILL_STATUSES = ["draft", "submitted", "approved", "posted", "void"] as const;
export const FinanceVendorBillStatusSchema = z.enum(FINANCE_VENDOR_BILL_STATUSES);
export type FinanceVendorBillStatus = z.infer<typeof FinanceVendorBillStatusSchema>;

export const FINANCE_VENDOR_BILL_VARIANCE_STATUSES = ["within_tolerance", "requires_approval"] as const;
export const FinanceVendorBillVarianceStatusSchema = z.enum(FINANCE_VENDOR_BILL_VARIANCE_STATUSES);
export type FinanceVendorBillVarianceStatus = z.infer<typeof FinanceVendorBillVarianceStatusSchema>;

export const FinanceVendorBillSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  companyId: z.string().uuid().nullable(),
  billNumber: z.string().nullable(),
  vendorMasterId: z.string().uuid(),
  vendorReference: z.string().nullable(),
  shipmentOrderId: z.string().uuid().nullable(),
  actualCostId: z.string().uuid(),
  currency: z.string(),
  status: FinanceVendorBillStatusSchema,
  subtotalAmount: z.number(),
  taxAmount: z.number(),
  totalAmount: z.number(),
  vendorStatedAmount: z.number().nullable(),
  varianceAmount: z.number(),
  varianceStatus: FinanceVendorBillVarianceStatusSchema,
  paymentTermDays: z.number().int(),
  billDate: z.string(),
  dueDate: z.string(),
  postingPeriodId: z.string().uuid().nullable(),
  apOpenItemId: z.string().uuid().nullable(),
  submittedBy: z.string().nullable(),
  submittedAt: z.string().nullable(),
  approvedBy: z.string().nullable(),
  approvedAt: z.string().nullable(),
  postedBy: z.string().nullable(),
  postedAt: z.string().nullable(),
  voidReason: z.string().nullable(),
  voidedBy: z.string().nullable(),
  voidedAt: z.string().nullable(),
  recordVersion: z.number().int().positive(),
  createdBy: z.string().nullable(),
  createdAt: z.string(),
  updatedAt: z.string(),
});
export type FinanceVendorBill = z.infer<typeof FinanceVendorBillSchema>;

export const FinanceVendorBillLineTypeSchema = z.enum(["cost", "tax"]);
export type FinanceVendorBillLineType = z.infer<typeof FinanceVendorBillLineTypeSchema>;

export const FinanceVendorBillLineSchema = z.object({
  id: z.string().uuid(),
  billId: z.string().uuid(),
  lineNumber: z.number().int(),
  lineType: FinanceVendorBillLineTypeSchema,
  description: z.string(),
  amount: z.number(),
  sourceComponentId: z.string().uuid().nullable(),
  taxCodeId: z.string().uuid().nullable(),
  taxRuleVersionId: z.string().uuid().nullable(),
  createdAt: z.string(),
});
export type FinanceVendorBillLine = z.infer<typeof FinanceVendorBillLineSchema>;

export const PrepareFinanceVendorBillFromActualCostInputSchema = z.object({
  tenantId: z.string().uuid(),
  actualCostId: z.string().uuid(),
  vendorMasterId: z.string().uuid(),
  vendorReference: z.string().nullable().default(null),
  billDate: z.string(),
  paymentTermDays: z.number().int().min(0).default(30),
  vendorStatedAmount: z.number().nullable().default(null),
  taxCode: z.string().nullable().default(null),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type PrepareFinanceVendorBillFromActualCostInput = z.input<typeof PrepareFinanceVendorBillFromActualCostInputSchema>;

export const FinanceVendorBillLifecycleInputSchema = z.object({
  billId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type FinanceVendorBillLifecycleInput = z.input<typeof FinanceVendorBillLifecycleInputSchema>;

export const DiscardFinanceVendorBillDraftInputSchema = FinanceVendorBillLifecycleInputSchema.extend({
  reason: z.string().nullable().default(null),
});
export type DiscardFinanceVendorBillDraftInput = z.input<typeof DiscardFinanceVendorBillDraftInputSchema>;

/** Maps a raw app.finance_vendor_bills row (snake_case) to this contract's camelCase shape. */
export function parseFinanceVendorBill(row: Record<string, unknown>): FinanceVendorBill {
  return FinanceVendorBillSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    companyId: row.company_id,
    billNumber: row.bill_number,
    vendorMasterId: row.vendor_master_id,
    vendorReference: row.vendor_reference,
    shipmentOrderId: row.shipment_order_id,
    actualCostId: row.actual_cost_id,
    currency: row.currency,
    status: row.status,
    subtotalAmount: typeof row.subtotal_amount === "string" ? Number(row.subtotal_amount) : row.subtotal_amount,
    taxAmount: typeof row.tax_amount === "string" ? Number(row.tax_amount) : row.tax_amount,
    totalAmount: typeof row.total_amount === "string" ? Number(row.total_amount) : row.total_amount,
    vendorStatedAmount: row.vendor_stated_amount === null || row.vendor_stated_amount === undefined
      ? null
      : (typeof row.vendor_stated_amount === "string" ? Number(row.vendor_stated_amount) : row.vendor_stated_amount),
    varianceAmount: typeof row.variance_amount === "string" ? Number(row.variance_amount) : row.variance_amount,
    varianceStatus: row.variance_status,
    paymentTermDays: row.payment_term_days,
    billDate: row.bill_date,
    dueDate: row.due_date,
    postingPeriodId: row.posting_period_id,
    apOpenItemId: row.ap_open_item_id,
    submittedBy: row.submitted_by,
    submittedAt: row.submitted_at,
    approvedBy: row.approved_by,
    approvedAt: row.approved_at,
    postedBy: row.posted_by,
    postedAt: row.posted_at,
    voidReason: row.void_reason,
    voidedBy: row.voided_by,
    voidedAt: row.voided_at,
    recordVersion: row.record_version,
    createdBy: row.created_by,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  });
}

/** Maps a raw app.finance_vendor_bill_lines row (snake_case) to this contract's camelCase shape. */
export function parseFinanceVendorBillLine(row: Record<string, unknown>): FinanceVendorBillLine {
  return FinanceVendorBillLineSchema.parse({
    id: row.id,
    billId: row.bill_id,
    lineNumber: row.line_number,
    lineType: row.line_type,
    description: row.description,
    amount: typeof row.amount === "string" ? Number(row.amount) : row.amount,
    sourceComponentId: row.source_component_id,
    taxCodeId: row.tax_code_id,
    taxRuleVersionId: row.tax_rule_version_id,
    createdAt: row.created_at,
  });
}
