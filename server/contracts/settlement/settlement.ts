/**
 * Settlement contract (FIN-201, CG-S9-FIN-012). Mirrors
 * supabase/migrations/20260729150000_create_finance_settlement.sql's
 * app.finance_settlements / app.finance_settlement_allocations shapes and their RPCs.
 */

import { z } from "zod";

export const FINANCE_SETTLEMENT_STATUSES = ["draft", "submitted", "approved", "executed", "posted", "void", "reversed"] as const;
export const FinanceSettlementStatusSchema = z.enum(FINANCE_SETTLEMENT_STATUSES);
export type FinanceSettlementStatus = z.infer<typeof FinanceSettlementStatusSchema>;

export const FinanceSettlementSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  companyId: z.string().uuid().nullable(),
  settlementNumber: z.string().nullable(),
  vendorMasterId: z.string().uuid(),
  paymentReference: z.string().nullable(),
  bankAccountLabel: z.string().nullable(),
  currency: z.string(),
  status: FinanceSettlementStatusSchema,
  allocatedAmount: z.number(),
  feeAmount: z.number(),
  totalAmount: z.number(),
  settlementDate: z.string(),
  idempotencyKey: z.string(),
  postingPeriodId: z.string().uuid().nullable(),
  executionReference: z.string().nullable(),
  submittedBy: z.string().nullable(),
  submittedAt: z.string().nullable(),
  approvedBy: z.string().nullable(),
  approvedAt: z.string().nullable(),
  executedBy: z.string().nullable(),
  executedAt: z.string().nullable(),
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
export type FinanceSettlement = z.infer<typeof FinanceSettlementSchema>;

export const FinanceSettlementAllocationStatusSchema = z.enum(["applied", "reversed"]);
export type FinanceSettlementAllocationStatus = z.infer<typeof FinanceSettlementAllocationStatusSchema>;

export const FinanceSettlementAllocationSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  settlementId: z.string().uuid(),
  apOpenItemId: z.string().uuid(),
  amount: z.number(),
  status: FinanceSettlementAllocationStatusSchema,
  reason: z.string().nullable(),
  reversedBy: z.string().nullable(),
  reversedAt: z.string().nullable(),
  createdAt: z.string(),
});
export type FinanceSettlementAllocation = z.infer<typeof FinanceSettlementAllocationSchema>;

export const FinanceSettlementAllocationLineSchema = z.object({
  apOpenItemId: z.string().uuid(),
  amount: z.number().positive(),
});
export type FinanceSettlementAllocationLine = z.infer<typeof FinanceSettlementAllocationLineSchema>;

export const PrepareFinanceSettlementInputSchema = z.object({
  tenantId: z.string().uuid(),
  companyId: z.string().uuid().nullable().default(null),
  vendorMasterId: z.string().uuid(),
  paymentReference: z.string().nullable().default(null),
  bankAccountLabel: z.string().nullable().default(null),
  currency: z.string().regex(/^[A-Z]{3}$/),
  settlementDate: z.string(),
  allocations: z.array(FinanceSettlementAllocationLineSchema).min(1),
  feeAmount: z.number().min(0).default(0),
  idempotencyKey: z.string().min(1),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type PrepareFinanceSettlementInput = z.input<typeof PrepareFinanceSettlementInputSchema>;

export const FinanceSettlementLifecycleInputSchema = z.object({
  settlementId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type FinanceSettlementLifecycleInput = z.input<typeof FinanceSettlementLifecycleInputSchema>;

export const DiscardFinanceSettlementDraftInputSchema = FinanceSettlementLifecycleInputSchema.extend({
  reason: z.string().nullable().default(null),
});
export type DiscardFinanceSettlementDraftInput = z.input<typeof DiscardFinanceSettlementDraftInputSchema>;

export const ExecuteFinanceSettlementInputSchema = FinanceSettlementLifecycleInputSchema.extend({
  executionReference: z.string().nullable().default(null),
});
export type ExecuteFinanceSettlementInput = z.input<typeof ExecuteFinanceSettlementInputSchema>;

export const RequestFinanceSettlementReversalInputSchema = z.object({
  settlementId: z.string().uuid(),
  reason: z.string().min(1),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type RequestFinanceSettlementReversalInput = z.input<typeof RequestFinanceSettlementReversalInputSchema>;

/** Maps a raw app.finance_settlements row (snake_case) to this contract's camelCase shape. */
export function parseFinanceSettlement(row: Record<string, unknown>): FinanceSettlement {
  return FinanceSettlementSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    companyId: row.company_id,
    settlementNumber: row.settlement_number,
    vendorMasterId: row.vendor_master_id,
    paymentReference: row.payment_reference,
    bankAccountLabel: row.bank_account_label,
    currency: row.currency,
    status: row.status,
    allocatedAmount: typeof row.allocated_amount === "string" ? Number(row.allocated_amount) : row.allocated_amount,
    feeAmount: typeof row.fee_amount === "string" ? Number(row.fee_amount) : row.fee_amount,
    totalAmount: typeof row.total_amount === "string" ? Number(row.total_amount) : row.total_amount,
    settlementDate: row.settlement_date,
    idempotencyKey: row.idempotency_key,
    postingPeriodId: row.posting_period_id,
    executionReference: row.execution_reference,
    submittedBy: row.submitted_by,
    submittedAt: row.submitted_at,
    approvedBy: row.approved_by,
    approvedAt: row.approved_at,
    executedBy: row.executed_by,
    executedAt: row.executed_at,
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

/** Maps a raw app.finance_settlement_allocations row (snake_case) to this contract's camelCase shape. */
export function parseFinanceSettlementAllocation(row: Record<string, unknown>): FinanceSettlementAllocation {
  return FinanceSettlementAllocationSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    settlementId: row.settlement_id,
    apOpenItemId: row.ap_open_item_id,
    amount: typeof row.amount === "string" ? Number(row.amount) : row.amount,
    status: row.status,
    reason: row.reason,
    reversedBy: row.reversed_by,
    reversedAt: row.reversed_at,
    createdAt: row.created_at,
  });
}
