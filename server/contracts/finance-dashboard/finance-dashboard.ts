/**
 * Finance Dashboard and Reports contract (FIN-213, CG-S9-FIN-024). Mirrors
 * supabase/migrations/20260729270000_create_finance_dashboard.sql's three
 * new composing read functions -- billing, reconciliation and cash
 * summaries. AR/AP aging and profitability sections reuse FIN-210/FIN-212's
 * own already-existing contracts verbatim; no duplicate shape is defined
 * for either here.
 */

import { z } from "zod";

const numeric = (value: unknown) => (typeof value === "string" ? Number(value) : value);

export const FinanceDashboardBillingRowSchema = z.object({
  status: z.string(),
  currency: z.string(),
  invoiceCount: z.number().int(),
  totalAmount: z.number(),
});
export type FinanceDashboardBillingRow = z.infer<typeof FinanceDashboardBillingRowSchema>;

export const FinanceDashboardReconciliationRowSchema = z.object({
  scope: z.enum(["ar", "ap"]),
  asOfDate: z.string(),
  status: z.string(),
  isWithinTolerance: z.boolean(),
  varianceAmount: z.number(),
  checkedAt: z.string(),
});
export type FinanceDashboardReconciliationRow = z.infer<typeof FinanceDashboardReconciliationRowSchema>;

export const FinanceDashboardCashRowSchema = z.object({
  currency: z.string(),
  accountCount: z.number().int(),
  statementBalance: z.number(),
  glBalance: z.number(),
  varianceAmount: z.number(),
});
export type FinanceDashboardCashRow = z.infer<typeof FinanceDashboardCashRowSchema>;

/** Maps a raw app.get_finance_dashboard_billing_summary row (snake_case) to this contract's camelCase shape. */
export function parseFinanceDashboardBillingRow(row: Record<string, unknown>): FinanceDashboardBillingRow {
  return FinanceDashboardBillingRowSchema.parse({
    status: row.status,
    currency: row.currency,
    invoiceCount: typeof row.invoice_count === "string" ? Number(row.invoice_count) : row.invoice_count,
    totalAmount: numeric(row.total_amount),
  });
}

/** Maps a raw app.get_finance_dashboard_reconciliation_summary row (snake_case) to this contract's camelCase shape. */
export function parseFinanceDashboardReconciliationRow(row: Record<string, unknown>): FinanceDashboardReconciliationRow {
  return FinanceDashboardReconciliationRowSchema.parse({
    scope: row.scope,
    asOfDate: row.as_of_date,
    status: row.status,
    isWithinTolerance: row.is_within_tolerance,
    varianceAmount: numeric(row.variance_amount),
    checkedAt: row.checked_at,
  });
}

/** Maps a raw app.get_finance_dashboard_cash_summary row (snake_case) to this contract's camelCase shape. */
export function parseFinanceDashboardCashRow(row: Record<string, unknown>): FinanceDashboardCashRow {
  return FinanceDashboardCashRowSchema.parse({
    currency: row.currency,
    accountCount: typeof row.account_count === "string" ? Number(row.account_count) : row.account_count,
    statementBalance: numeric(row.statement_balance),
    glBalance: numeric(row.gl_balance),
    varianceAmount: numeric(row.variance_amount),
  });
}
