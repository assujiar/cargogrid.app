/**
 * Customer Portal Payment Visibility contract (CPL-312, CG-S13-CPL-014,
 * Prompt 312). Mirrors supabase/migrations/
 * 20260801130000_create_customer_portal_payment_visibility.sql's read-only
 * RPC surface: app.get_customer_portal_payment_status/app.list_customer_
 * portal_receipts.
 *
 * Deliberately NOT a re-export of server/contracts/customer-portal-invoice/
 * customer-portal-invoice.ts's own CustomerPortalInvoicePaymentSchema --
 * that shape (paymentStatus/originalAmount/openAmount/isHeld, no allocation
 * detail) is CPL-311's own narrower projection; this one additionally
 * carries the applied-receipt-allocation list this migration's own RPC
 * returns, matching CPL-309/310/311's own established "duplicated here
 * rather than imported" rationale for two independently-evolving,
 * differently-gated capabilities.
 */

import { z } from "zod";

function coerceAmount(value: unknown): number | null {
  if (value === null || value === undefined) return null;
  return typeof value === "string" ? Number(value) : (value as number);
}

/** The four real payment_status values app.get_customer_portal_payment_status ever returns -- identical vocabulary to CPL-311's own CustomerPortalInvoicePaymentStatusSchema (open/partial/paid from app.finance_ar_open_items.status, plus the synthesized not_posted for a void-before-ever-issued invoice), duplicated here rather than imported (see file header). */
export const CUSTOMER_PORTAL_PAYMENT_STATUSES = ["open", "partial", "paid", "not_posted"] as const;
export const CustomerPortalPaymentStatusValueSchema = z.enum(CUSTOMER_PORTAL_PAYMENT_STATUSES);
export type CustomerPortalPaymentStatusValue = z.infer<typeof CustomerPortalPaymentStatusValueSchema>;

export const CUSTOMER_PORTAL_PAYMENT_STATUS_LABELS: Record<CustomerPortalPaymentStatusValue, string> = {
  open: "Payment due",
  partial: "Partially paid",
  paid: "Paid",
  not_posted: "Not billed to AR",
};

/**
 * One applied receipt allocation against an invoice's own AR open item --
 * never bank_account_label/payer_name (migration design decisions 5/6), and
 * never a reversed allocation (design decision 8). Nested jsonb keys are
 * already camelCase at the SQL layer (migration design decision 10), so no
 * per-element snake_case remap is needed here, unlike every other row shape
 * in this contract.
 */
export const CustomerPortalPaymentAllocationSchema = z.object({
  receiptReference: z.string().nullable(),
  receiptDate: z.string(),
  amount: z.number(),
  currency: z.string(),
});
export type CustomerPortalPaymentAllocation = z.infer<typeof CustomerPortalPaymentAllocationSchema>;

export const CustomerPortalPaymentStatusSchema = z.object({
  paymentStatus: CustomerPortalPaymentStatusValueSchema,
  originalAmount: z.number().nullable(),
  openAmount: z.number().nullable(),
  isHeld: z.boolean().nullable(),
  allocations: z.array(CustomerPortalPaymentAllocationSchema),
});
export type CustomerPortalPaymentStatus = z.infer<typeof CustomerPortalPaymentStatusSchema>;

/** Maps app.get_customer_portal_payment_status' own raw row (snake_case top-level columns, an already-camelCase nested jsonb array) to this contract's shape. */
export function parseCustomerPortalPaymentStatus(row: Record<string, unknown>): CustomerPortalPaymentStatus {
  const rawAllocations = Array.isArray(row.allocations) ? row.allocations : [];
  return CustomerPortalPaymentStatusSchema.parse({
    paymentStatus: row.payment_status,
    originalAmount: coerceAmount(row.original_amount),
    openAmount: coerceAmount(row.open_amount),
    isHeld: (row.is_held as boolean | null) ?? null,
    allocations: rawAllocations.map((entry) => {
      const allocation = entry as Record<string, unknown>;
      return {
        receiptReference: (allocation.receiptReference as string | null) ?? null,
        receiptDate: allocation.receiptDate,
        amount: coerceAmount(allocation.amount),
        currency: allocation.currency,
      };
    }),
  });
}

/** app.finance_receipts.status -- both real values are portal-visible (migration design decision 9), never a pre-capture lifecycle state (no such state exists on this table). */
export const CUSTOMER_PORTAL_RECEIPT_STATUSES = ["captured", "void"] as const;
export const CustomerPortalReceiptStatusSchema = z.enum(CUSTOMER_PORTAL_RECEIPT_STATUSES);
export type CustomerPortalReceiptStatus = z.infer<typeof CustomerPortalReceiptStatusSchema>;

export const CUSTOMER_PORTAL_RECEIPT_STATUS_LABELS: Record<CustomerPortalReceiptStatus, string> = {
  captured: "Captured",
  void: "Voided",
};

/** app.list_customer_portal_receipts -- never bank_account_label/payer_name (migration design decisions 5/6). unappliedAmount is the closest honest signal this schema has for a "pending reconciliation"-shaped UI state (migration design decision 8) -- there is no dedicated reconciliation-status column anywhere in this schema. */
export const CustomerPortalReceiptSchema = z.object({
  id: z.string().uuid(),
  customerAccountId: z.string().uuid(),
  receiptReference: z.string().nullable(),
  receiptDate: z.string(),
  currency: z.string(),
  amount: z.number(),
  allocatedAmount: z.number(),
  unappliedAmount: z.number(),
  status: CustomerPortalReceiptStatusSchema,
  recordVersion: z.number().int().positive(),
  updatedAt: z.string(),
});
export type CustomerPortalReceipt = z.infer<typeof CustomerPortalReceiptSchema>;

export function parseCustomerPortalReceipt(row: Record<string, unknown>): CustomerPortalReceipt {
  return CustomerPortalReceiptSchema.parse({
    id: row.id,
    customerAccountId: row.customer_account_id,
    receiptReference: row.receipt_reference ?? null,
    receiptDate: row.receipt_date,
    currency: row.currency,
    amount: coerceAmount(row.amount),
    allocatedAmount: coerceAmount(row.allocated_amount),
    unappliedAmount: coerceAmount(row.unapplied_amount),
    status: row.status,
    recordVersion: row.record_version,
    updatedAt: row.updated_at,
  });
}

// --- Cursor pagination ---

/**
 * The (timestamp, id) keyset pair app.list_customer_portal_receipts accepts
 * -- never OFFSET. Omit both for the first page; pass the last row's own
 * values to advance. Mirrors server/contracts/customer-portal-invoice's own
 * CustomerPortalInvoiceCursorSchema exactly (duplicated per-capability, see
 * file header).
 */
export const CustomerPortalReceiptCursorSchema = z
  .object({
    cursorUpdatedAt: z.string().nullable().optional(),
    cursorId: z.string().uuid().nullable().optional(),
  })
  .refine((cursor) => !cursor.cursorId || !!cursor.cursorUpdatedAt, {
    message: "cursorUpdatedAt is required when cursorId is supplied",
    path: ["cursorUpdatedAt"],
  });
export type CustomerPortalReceiptCursor = z.input<typeof CustomerPortalReceiptCursorSchema>;
