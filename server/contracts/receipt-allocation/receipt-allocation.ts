/**
 * Receipt and Payment Allocation contract (FIN-198, CG-S9-FIN-009). Mirrors
 * supabase/migrations/20260729120000_create_finance_receipt_allocation.sql's
 * app.finance_receipts / app.finance_receipt_allocations shapes and their RPCs.
 */

import { z } from "zod";

export const FINANCE_RECEIPT_STATUSES = ["captured", "void"] as const;
export const FinanceReceiptStatusSchema = z.enum(FINANCE_RECEIPT_STATUSES);
export type FinanceReceiptStatus = z.infer<typeof FinanceReceiptStatusSchema>;

export const FinanceReceiptSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  companyId: z.string().uuid().nullable(),
  customerAccountId: z.string().uuid(),
  receiptReference: z.string().nullable(),
  receiptDate: z.string(),
  payerName: z.string().nullable(),
  bankAccountLabel: z.string().nullable(),
  currency: z.string(),
  amount: z.number(),
  allocatedAmount: z.number(),
  unappliedAmount: z.number(),
  status: FinanceReceiptStatusSchema,
  idempotencyKey: z.string(),
  postingPeriodId: z.string().uuid().nullable(),
  recordVersion: z.number().int().positive(),
  createdBy: z.string().nullable(),
  createdAt: z.string(),
  updatedAt: z.string(),
});
export type FinanceReceipt = z.infer<typeof FinanceReceiptSchema>;

export const FinanceReceiptAllocationStatusSchema = z.enum(["applied", "reversed"]);
export type FinanceReceiptAllocationStatus = z.infer<typeof FinanceReceiptAllocationStatusSchema>;

export const FinanceReceiptAllocationSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  receiptId: z.string().uuid(),
  batchId: z.string().uuid(),
  arOpenItemId: z.string().uuid(),
  amount: z.number(),
  status: FinanceReceiptAllocationStatusSchema,
  reason: z.string().nullable(),
  reversedBy: z.string().nullable(),
  reversedAt: z.string().nullable(),
  createdBy: z.string().nullable(),
  createdAt: z.string(),
});
export type FinanceReceiptAllocation = z.infer<typeof FinanceReceiptAllocationSchema>;

export const CaptureFinanceReceiptInputSchema = z.object({
  tenantId: z.string().uuid(),
  companyId: z.string().uuid().nullable().default(null),
  customerAccountId: z.string().uuid(),
  receiptReference: z.string().nullable().default(null),
  receiptDate: z.string(),
  payerName: z.string().nullable().default(null),
  bankAccountLabel: z.string().nullable().default(null),
  currency: z.string().regex(/^[A-Z]{3}$/),
  amount: z.number().positive(),
  idempotencyKey: z.string().min(1),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type CaptureFinanceReceiptInput = z.input<typeof CaptureFinanceReceiptInputSchema>;

export const FinanceReceiptAllocationLineSchema = z.object({
  arOpenItemId: z.string().uuid(),
  amount: z.number().positive(),
});
export type FinanceReceiptAllocationLine = z.infer<typeof FinanceReceiptAllocationLineSchema>;

export const AllocateFinanceReceiptInputSchema = z.object({
  receiptId: z.string().uuid(),
  idempotencyKey: z.string().min(1),
  allocations: z.array(FinanceReceiptAllocationLineSchema).min(1),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type AllocateFinanceReceiptInput = z.input<typeof AllocateFinanceReceiptInputSchema>;

export const RequestFinanceReceiptDeallocationInputSchema = z.object({
  allocationId: z.string().uuid(),
  reason: z.string().min(1),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type RequestFinanceReceiptDeallocationInput = z.input<typeof RequestFinanceReceiptDeallocationInputSchema>;

/** Maps a raw app.finance_receipts row (snake_case) to this contract's camelCase shape. */
export function parseFinanceReceipt(row: Record<string, unknown>): FinanceReceipt {
  return FinanceReceiptSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    companyId: row.company_id,
    customerAccountId: row.customer_account_id,
    receiptReference: row.receipt_reference,
    receiptDate: row.receipt_date,
    payerName: row.payer_name,
    bankAccountLabel: row.bank_account_label,
    currency: row.currency,
    amount: typeof row.amount === "string" ? Number(row.amount) : row.amount,
    allocatedAmount: typeof row.allocated_amount === "string" ? Number(row.allocated_amount) : row.allocated_amount,
    unappliedAmount: typeof row.unapplied_amount === "string" ? Number(row.unapplied_amount) : row.unapplied_amount,
    status: row.status,
    idempotencyKey: row.idempotency_key,
    postingPeriodId: row.posting_period_id,
    recordVersion: row.record_version,
    createdBy: row.created_by,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  });
}

/** Maps a raw app.finance_receipt_allocations row (snake_case) to this contract's camelCase shape. */
export function parseFinanceReceiptAllocation(row: Record<string, unknown>): FinanceReceiptAllocation {
  return FinanceReceiptAllocationSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    receiptId: row.receipt_id,
    batchId: row.batch_id,
    arOpenItemId: row.ar_open_item_id,
    amount: typeof row.amount === "string" ? Number(row.amount) : row.amount,
    status: row.status,
    reason: row.reason,
    reversedBy: row.reversed_by,
    reversedAt: row.reversed_at,
    createdBy: row.created_by,
    createdAt: row.created_at,
  });
}
