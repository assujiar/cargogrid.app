/**
 * Customer Invoice contract (FIN-197, CG-S9-FIN-008). Mirrors
 * supabase/migrations/20260729110000_create_finance_invoice.sql's
 * app.finance_invoices / app.finance_invoice_lines shapes and their RPCs.
 */

import { z } from "zod";

export const FINANCE_INVOICE_STATUSES = ["draft", "submitted", "approved", "issued", "void"] as const;
export const FinanceInvoiceStatusSchema = z.enum(FINANCE_INVOICE_STATUSES);
export type FinanceInvoiceStatus = z.infer<typeof FinanceInvoiceStatusSchema>;

export const FinanceInvoiceSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  companyId: z.string().uuid().nullable(),
  invoiceNumber: z.string().nullable(),
  customerAccountId: z.string().uuid(),
  jobOrderId: z.string().uuid(),
  billingReadinessHandoffId: z.string().uuid(),
  currency: z.string(),
  status: FinanceInvoiceStatusSchema,
  subtotalAmount: z.number(),
  taxAmount: z.number(),
  totalAmount: z.number(),
  paymentTermDays: z.number().int(),
  issueDate: z.string().nullable(),
  dueDate: z.string().nullable(),
  postingPeriodId: z.string().uuid().nullable(),
  arOpenItemId: z.string().uuid().nullable(),
  submittedBy: z.string().nullable(),
  submittedAt: z.string().nullable(),
  approvedBy: z.string().nullable(),
  approvedAt: z.string().nullable(),
  issuedBy: z.string().nullable(),
  issuedAt: z.string().nullable(),
  voidReason: z.string().nullable(),
  voidedBy: z.string().nullable(),
  voidedAt: z.string().nullable(),
  recordVersion: z.number().int().positive(),
  createdBy: z.string().nullable(),
  createdAt: z.string(),
  updatedAt: z.string(),
});
export type FinanceInvoice = z.infer<typeof FinanceInvoiceSchema>;

export const FinanceInvoiceLineTypeSchema = z.enum(["charge", "tax"]);
export type FinanceInvoiceLineType = z.infer<typeof FinanceInvoiceLineTypeSchema>;

export const FinanceInvoiceLineSchema = z.object({
  id: z.string().uuid(),
  invoiceId: z.string().uuid(),
  lineNumber: z.number().int(),
  lineType: FinanceInvoiceLineTypeSchema,
  description: z.string(),
  amount: z.number(),
  taxCodeId: z.string().uuid().nullable(),
  taxRuleVersionId: z.string().uuid().nullable(),
  createdAt: z.string(),
});
export type FinanceInvoiceLine = z.infer<typeof FinanceInvoiceLineSchema>;

export const PrepareFinanceInvoiceFromReadinessInputSchema = z.object({
  tenantId: z.string().uuid(),
  billingReadinessHandoffId: z.string().uuid(),
  paymentTermDays: z.number().int().min(0).default(30),
  taxCode: z.string().nullable().default(null),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type PrepareFinanceInvoiceFromReadinessInput = z.input<typeof PrepareFinanceInvoiceFromReadinessInputSchema>;

export const FinanceInvoiceLifecycleInputSchema = z.object({
  invoiceId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type FinanceInvoiceLifecycleInput = z.input<typeof FinanceInvoiceLifecycleInputSchema>;

export const DiscardFinanceInvoiceDraftInputSchema = FinanceInvoiceLifecycleInputSchema.extend({
  reason: z.string().nullable().default(null),
});
export type DiscardFinanceInvoiceDraftInput = z.input<typeof DiscardFinanceInvoiceDraftInputSchema>;

export const IssueFinanceInvoiceInputSchema = FinanceInvoiceLifecycleInputSchema.extend({
  issueDate: z.string(),
});
export type IssueFinanceInvoiceInput = z.input<typeof IssueFinanceInvoiceInputSchema>;

/** Maps a raw app.finance_invoices row (snake_case) to this contract's camelCase shape. */
export function parseFinanceInvoice(row: Record<string, unknown>): FinanceInvoice {
  return FinanceInvoiceSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    companyId: row.company_id,
    invoiceNumber: row.invoice_number,
    customerAccountId: row.customer_account_id,
    jobOrderId: row.job_order_id,
    billingReadinessHandoffId: row.billing_readiness_handoff_id,
    currency: row.currency,
    status: row.status,
    subtotalAmount: typeof row.subtotal_amount === "string" ? Number(row.subtotal_amount) : row.subtotal_amount,
    taxAmount: typeof row.tax_amount === "string" ? Number(row.tax_amount) : row.tax_amount,
    totalAmount: typeof row.total_amount === "string" ? Number(row.total_amount) : row.total_amount,
    paymentTermDays: row.payment_term_days,
    issueDate: row.issue_date,
    dueDate: row.due_date,
    postingPeriodId: row.posting_period_id,
    arOpenItemId: row.ar_open_item_id,
    submittedBy: row.submitted_by,
    submittedAt: row.submitted_at,
    approvedBy: row.approved_by,
    approvedAt: row.approved_at,
    issuedBy: row.issued_by,
    issuedAt: row.issued_at,
    voidReason: row.void_reason,
    voidedBy: row.voided_by,
    voidedAt: row.voided_at,
    recordVersion: row.record_version,
    createdBy: row.created_by,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  });
}

/** Maps a raw app.finance_invoice_lines row (snake_case) to this contract's camelCase shape. */
export function parseFinanceInvoiceLine(row: Record<string, unknown>): FinanceInvoiceLine {
  return FinanceInvoiceLineSchema.parse({
    id: row.id,
    invoiceId: row.invoice_id,
    lineNumber: row.line_number,
    lineType: row.line_type,
    description: row.description,
    amount: typeof row.amount === "string" ? Number(row.amount) : row.amount,
    taxCodeId: row.tax_code_id,
    taxRuleVersionId: row.tax_rule_version_id,
    createdAt: row.created_at,
  });
}
