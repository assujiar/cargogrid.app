/**
 * Finance Dashboard contract (FIN-213, CG-S9-FIN-024). Mirrors
 * supabase/migrations/20260729270000_create_finance_dashboard.sql's three
 * genuinely new app.get_finance_dashboard_* RPCs. AR/AP aging and
 * profitability widgets reuse `server/contracts/aging/aging.ts` and
 * `server/contracts/profitability/profitability.ts` directly -- no shape
 * duplication here.
 */

import { z } from "zod";

const numeric = (value: unknown) => (typeof value === "string" ? Number(value) : value);
const bigintCount = (value: unknown) => (typeof value === "string" ? Number(value) : value);

export const FinanceDashboardBillingSummaryRowSchema = z.object({
  status: z.string(),
  currency: z.string(),
  invoiceCount: z.number().int(),
  totalAmount: z.number().nullable(),
  openAmount: z.number(),
});
export type FinanceDashboardBillingSummaryRow = z.infer<typeof FinanceDashboardBillingSummaryRowSchema>;

export function parseFinanceDashboardBillingSummaryRow(row: Record<string, unknown>): FinanceDashboardBillingSummaryRow {
  return FinanceDashboardBillingSummaryRowSchema.parse({
    status: row.status,
    currency: row.currency,
    invoiceCount: bigintCount(row.invoice_count),
    totalAmount: numeric(row.total_amount) ?? null,
    openAmount: numeric(row.open_amount) ?? 0,
  });
}

export const FinanceDashboardCashSummaryRowSchema = z.object({
  bankAccountId: z.string().uuid(),
  accountName: z.string(),
  currency: z.string(),
  statementBalance: z.number(),
  glBalance: z.number(),
  varianceAmount: z.number(),
});
export type FinanceDashboardCashSummaryRow = z.infer<typeof FinanceDashboardCashSummaryRowSchema>;

export function parseFinanceDashboardCashSummaryRow(row: Record<string, unknown>): FinanceDashboardCashSummaryRow {
  return FinanceDashboardCashSummaryRowSchema.parse({
    bankAccountId: row.bank_account_id,
    accountName: row.account_name,
    currency: row.currency,
    statementBalance: numeric(row.statement_balance),
    glBalance: numeric(row.gl_balance),
    varianceAmount: numeric(row.variance_amount),
  });
}

export const FinanceDashboardCloseStatusRowSchema = z.object({
  periodId: z.string().uuid(),
  periodCode: z.string(),
  periodName: z.string(),
  endDate: z.string(),
  periodStatus: z.string(),
  lockStatus: z.string().nullable(),
  reconciliationStatus: z.string().nullable(),
  reconciliationWithinTolerance: z.boolean().nullable(),
});
export type FinanceDashboardCloseStatusRow = z.infer<typeof FinanceDashboardCloseStatusRowSchema>;

export function parseFinanceDashboardCloseStatusRow(row: Record<string, unknown>): FinanceDashboardCloseStatusRow {
  return FinanceDashboardCloseStatusRowSchema.parse({
    periodId: row.period_id,
    periodCode: row.period_code,
    periodName: row.period_name,
    endDate: row.end_date,
    periodStatus: row.period_status,
    lockStatus: row.lock_status ?? null,
    reconciliationStatus: row.reconciliation_status ?? null,
    reconciliationWithinTolerance: row.reconciliation_within_tolerance ?? null,
  });
}
