/**
 * Customer Portal Invoice and Billing Visibility contract (CPL-311,
 * CG-S13-CPL-013, Prompt 311). Mirrors supabase/migrations/
 * 20260801120000_create_customer_portal_invoice_billing_visibility.sql's
 * read-only RPC surface: app.get_customer_portal_invoice/app.list_customer_
 * portal_invoices/app.get_customer_portal_invoice_lines/app.get_customer_
 * portal_invoice_payment_status.
 *
 * Deliberately NOT a re-export of server/contracts/invoice/invoice.ts's own
 * FinanceInvoiceSchema -- that schema's own shape (companyId/jobOrderId/
 * billingReadinessHandoffId/postingPeriodId/arOpenItemId, every lifecycle
 * status including draft/submitted/approved) is the STAFF projection; this
 * one is the customer-safe projection the migration's own RPCs actually
 * return (narrower column set, narrower status set), matching CPL-309/310's
 * own established "duplicated here rather than imported" rationale for two
 * independently-evolving, differently-gated capabilities.
 */

import { z } from "zod";

/** The two real statuses app.get_customer_portal_invoice/app.list_customer_portal_invoices ever return -- draft/submitted/approved are filtered out server-side inside the RPC itself, never merely hidden client-side (migration design decision 4). */
export const CUSTOMER_PORTAL_INVOICE_STATUSES = ["issued", "void"] as const;
export const CustomerPortalInvoiceStatusSchema = z.enum(CUSTOMER_PORTAL_INVOICE_STATUSES);
export type CustomerPortalInvoiceStatus = z.infer<typeof CustomerPortalInvoiceStatusSchema>;

/** Customer-visible label for each real status -- presentation only, never persisted or sent to the RPC layer. */
export const CUSTOMER_PORTAL_INVOICE_STATUS_LABELS: Record<CustomerPortalInvoiceStatus, string> = {
  issued: "Issued",
  void: "Voided",
};

export const CustomerPortalInvoiceSchema = z.object({
  id: z.string().uuid(),
  /**
   * `ISS-2026-124`: which of the customer's OWN accounts this invoice belongs to. A
   * `customer_user` whose Layer 4 membership resolves to more than one account — a supported
   * shape since CPL-300 widened `app.resolve_customer_account_scope` — saw every one of their
   * invoices correctly but had nothing in the row telling them WHICH account it was for.
   *
   * The DB half landed at `20260827140000`; this is the client half. Nullable so a row from an
   * older projection degrades to "unknown account" rather than throwing — a listing must never
   * fail because one field is absent.
   */
  customerAccountId: z.string().uuid().nullable(),
  invoiceNumber: z.string().nullable(),
  currency: z.string(),
  status: CustomerPortalInvoiceStatusSchema,
  subtotalAmount: z.number(),
  taxAmount: z.number(),
  totalAmount: z.number(),
  issueDate: z.string().nullable(),
  dueDate: z.string().nullable(),
  recordVersion: z.number().int().positive(),
  updatedAt: z.string(),
});
export type CustomerPortalInvoice = z.infer<typeof CustomerPortalInvoiceSchema>;

function coerceAmount(value: unknown): number | null {
  if (value === null || value === undefined) return null;
  return typeof value === "string" ? Number(value) : (value as number);
}

/** Maps app.get_customer_portal_invoice/app.list_customer_portal_invoices' own raw row (snake_case) to this contract's camelCase shape. */
export function parseCustomerPortalInvoice(row: Record<string, unknown>): CustomerPortalInvoice {
  return CustomerPortalInvoiceSchema.parse({
    id: row.id,
    customerAccountId: row.customer_account_id ?? null,
    invoiceNumber: row.invoice_number ?? null,
    currency: row.currency,
    status: row.status,
    subtotalAmount: coerceAmount(row.subtotal_amount),
    taxAmount: coerceAmount(row.tax_amount),
    totalAmount: coerceAmount(row.total_amount),
    issueDate: row.issue_date ?? null,
    dueDate: row.due_date ?? null,
    recordVersion: row.record_version,
    updatedAt: row.updated_at,
  });
}

/** app.get_customer_portal_invoice_lines -- never tax_code_id/tax_rule_version_id (internal Finance tax-configuration references, migration design decision 6). */
export const CUSTOMER_PORTAL_INVOICE_LINE_TYPES = ["charge", "tax"] as const;
export const CustomerPortalInvoiceLineTypeSchema = z.enum(CUSTOMER_PORTAL_INVOICE_LINE_TYPES);
export type CustomerPortalInvoiceLineType = z.infer<typeof CustomerPortalInvoiceLineTypeSchema>;

export const CustomerPortalInvoiceLineSchema = z.object({
  lineNumber: z.number().int(),
  lineType: CustomerPortalInvoiceLineTypeSchema,
  description: z.string(),
  amount: z.number(),
});
export type CustomerPortalInvoiceLine = z.infer<typeof CustomerPortalInvoiceLineSchema>;

export function parseCustomerPortalInvoiceLine(row: Record<string, unknown>): CustomerPortalInvoiceLine {
  return CustomerPortalInvoiceLineSchema.parse({
    lineNumber: row.line_number,
    lineType: row.line_type,
    description: row.description,
    amount: coerceAmount(row.amount),
  });
}

/** app.get_customer_portal_invoice_payment_status -- 'not_posted' covers the rare void-before-ever-issued invoice (no AR item was ever posted), never a fabricated zero (migration design decision 7). Never exposes ar_open_item_id or the AR open item's own id. */
export const CUSTOMER_PORTAL_INVOICE_PAYMENT_STATUSES = ["open", "partial", "paid", "not_posted"] as const;
export const CustomerPortalInvoicePaymentStatusSchema = z.enum(CUSTOMER_PORTAL_INVOICE_PAYMENT_STATUSES);
export type CustomerPortalInvoicePaymentStatus = z.infer<typeof CustomerPortalInvoicePaymentStatusSchema>;

export const CUSTOMER_PORTAL_INVOICE_PAYMENT_STATUS_LABELS: Record<CustomerPortalInvoicePaymentStatus, string> = {
  open: "Payment due",
  partial: "Partially paid",
  paid: "Paid",
  not_posted: "Not billed to AR",
};

export const CustomerPortalInvoicePaymentSchema = z.object({
  paymentStatus: CustomerPortalInvoicePaymentStatusSchema,
  originalAmount: z.number().nullable(),
  openAmount: z.number().nullable(),
  isHeld: z.boolean().nullable(),
});
export type CustomerPortalInvoicePayment = z.infer<typeof CustomerPortalInvoicePaymentSchema>;

export function parseCustomerPortalInvoicePayment(row: Record<string, unknown>): CustomerPortalInvoicePayment {
  return CustomerPortalInvoicePaymentSchema.parse({
    paymentStatus: row.payment_status,
    originalAmount: coerceAmount(row.original_amount),
    openAmount: coerceAmount(row.open_amount),
    isHeld: (row.is_held as boolean | null) ?? null,
  });
}

// --- Cursor pagination ---

/**
 * The (timestamp, id) keyset pair app.list_customer_portal_invoices accepts
 * -- never OFFSET. Omit both for the first page; pass the last row's own
 * values to advance. Mirrors server/contracts/customer-portal-warehouse-order's
 * own CustomerWarehouseOrderCursorSchema exactly.
 */
export const CustomerPortalInvoiceCursorSchema = z
  .object({
    cursorUpdatedAt: z.string().nullable().optional(),
    cursorId: z.string().uuid().nullable().optional(),
  })
  .refine((cursor) => !cursor.cursorId || !!cursor.cursorUpdatedAt, {
    message: "cursorUpdatedAt is required when cursorId is supplied",
    path: ["cursorUpdatedAt"],
  });
export type CustomerPortalInvoiceCursor = z.input<typeof CustomerPortalInvoiceCursorSchema>;

/** The full, structured export shape 'download' produces client-side -- a real JSON export of the invoice + its lines + its payment status, never a fabricated PDF (migration design decision 12). */
export const CustomerPortalInvoiceExportSchema = z.object({
  exportedAt: z.string(),
  invoice: CustomerPortalInvoiceSchema,
  lines: z.array(CustomerPortalInvoiceLineSchema),
  payment: CustomerPortalInvoicePaymentSchema,
});
export type CustomerPortalInvoiceExport = z.infer<typeof CustomerPortalInvoiceExportSchema>;
