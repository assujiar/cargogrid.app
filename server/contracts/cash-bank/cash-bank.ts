/**
 * Cash and Bank Baseline contract (FIN-211, CG-S9-FIN-022). Mirrors
 * supabase/migrations/20260729250000_create_finance_cash_bank.sql's
 * app.finance_bank_accounts / app.finance_bank_statement_batches /
 * app.finance_bank_transactions shapes and their RPCs.
 */

import { z } from "zod";

export const FINANCE_BANK_ACCOUNT_STATUSES = ["active", "inactive"] as const;
export const FinanceBankAccountStatusSchema = z.enum(FINANCE_BANK_ACCOUNT_STATUSES);
export type FinanceBankAccountStatus = z.infer<typeof FinanceBankAccountStatusSchema>;

export const FinanceBankAccountSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  companyId: z.string().uuid().nullable(),
  accountName: z.string(),
  bankName: z.string(),
  accountNumberLast4: z.string(),
  currency: z.string(),
  glAccountId: z.string().uuid(),
  status: FinanceBankAccountStatusSchema,
  recordVersion: z.number().int().positive(),
  createdBy: z.string().nullable(),
  createdAt: z.string(),
  updatedAt: z.string(),
});
export type FinanceBankAccount = z.infer<typeof FinanceBankAccountSchema>;

export const FinanceBankStatementBatchSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  bankAccountId: z.string().uuid(),
  sourceReference: z.string(),
  lineCount: z.number().int(),
  importedBy: z.string().nullable(),
  importedAt: z.string(),
});
export type FinanceBankStatementBatch = z.infer<typeof FinanceBankStatementBatchSchema>;

export const FINANCE_BANK_TRANSACTION_MATCH_STATUSES = ["unmatched", "matched"] as const;
export const FinanceBankTransactionMatchStatusSchema = z.enum(FINANCE_BANK_TRANSACTION_MATCH_STATUSES);
export type FinanceBankTransactionMatchStatus = z.infer<typeof FinanceBankTransactionMatchStatusSchema>;

export const FinanceBankTransactionSchema = z.object({
  id: z.string().uuid(),
  batchId: z.string().uuid(),
  tenantId: z.string().uuid(),
  bankAccountId: z.string().uuid(),
  transactionDate: z.string(),
  direction: z.enum(["debit", "credit"]),
  amount: z.number(),
  reference: z.string().nullable(),
  description: z.string().nullable(),
  matchStatus: FinanceBankTransactionMatchStatusSchema,
  matchedSourceType: z.string().nullable(),
  matchedSourceId: z.string().uuid().nullable(),
  matchedBy: z.string().nullable(),
  matchedAt: z.string().nullable(),
  unmatchReason: z.string().nullable(),
  recordVersion: z.number().int().positive(),
  createdAt: z.string(),
  updatedAt: z.string(),
});
export type FinanceBankTransaction = z.infer<typeof FinanceBankTransactionSchema>;

export const FinanceCashPositionSchema = z.object({
  bankAccountId: z.string().uuid(),
  currency: z.string(),
  statementBalance: z.number(),
  glBalance: z.number(),
  varianceAmount: z.number(),
});
export type FinanceCashPosition = z.infer<typeof FinanceCashPositionSchema>;

export const CreateFinanceBankAccountInputSchema = z.object({
  tenantId: z.string().uuid(),
  companyId: z.string().uuid().nullable().default(null),
  accountName: z.string().min(1),
  bankName: z.string().min(1),
  accountNumberLast4: z.string().min(1).max(4),
  currency: z.string().regex(/^[A-Z]{3}$/),
  glAccountId: z.string().uuid(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type CreateFinanceBankAccountInput = z.input<typeof CreateFinanceBankAccountInputSchema>;

export const FinanceBankStatementLineSchema = z.object({
  transactionDate: z.string(),
  direction: z.enum(["debit", "credit"]),
  amount: z.number().positive(),
  reference: z.string().nullable().default(null),
  description: z.string().nullable().default(null),
});
export type FinanceBankStatementLine = z.infer<typeof FinanceBankStatementLineSchema>;

export const ImportFinanceBankStatementInputSchema = z.object({
  tenantId: z.string().uuid(),
  bankAccountId: z.string().uuid(),
  sourceReference: z.string().min(1),
  lines: z.array(FinanceBankStatementLineSchema).min(1),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type ImportFinanceBankStatementInput = z.input<typeof ImportFinanceBankStatementInputSchema>;

export const MatchFinanceBankTransactionInputSchema = z.object({
  transactionId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  matchedSourceType: z.enum(["receipt", "settlement", "manual"]),
  matchedSourceId: z.string().uuid().nullable(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type MatchFinanceBankTransactionInput = z.input<typeof MatchFinanceBankTransactionInputSchema>;

export const UnmatchFinanceBankTransactionInputSchema = z.object({
  transactionId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  reason: z.string().min(1),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type UnmatchFinanceBankTransactionInput = z.input<typeof UnmatchFinanceBankTransactionInputSchema>;

/** Maps a raw app.finance_bank_accounts row (snake_case) to this contract's camelCase shape. */
export function parseFinanceBankAccount(row: Record<string, unknown>): FinanceBankAccount {
  return FinanceBankAccountSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    companyId: row.company_id,
    accountName: row.account_name,
    bankName: row.bank_name,
    accountNumberLast4: row.account_number_last4,
    currency: row.currency,
    glAccountId: row.gl_account_id,
    status: row.status,
    recordVersion: row.record_version,
    createdBy: row.created_by,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  });
}

/** Maps a raw app.finance_bank_statement_batches row (snake_case) to this contract's camelCase shape. */
export function parseFinanceBankStatementBatch(row: Record<string, unknown>): FinanceBankStatementBatch {
  return FinanceBankStatementBatchSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    bankAccountId: row.bank_account_id,
    sourceReference: row.source_reference,
    lineCount: row.line_count,
    importedBy: row.imported_by,
    importedAt: row.imported_at,
  });
}

/** Maps a raw app.finance_bank_transactions row (snake_case) to this contract's camelCase shape. */
export function parseFinanceBankTransaction(row: Record<string, unknown>): FinanceBankTransaction {
  const numeric = (value: unknown) => (typeof value === "string" ? Number(value) : value);
  return FinanceBankTransactionSchema.parse({
    id: row.id,
    batchId: row.batch_id,
    tenantId: row.tenant_id,
    bankAccountId: row.bank_account_id,
    transactionDate: row.transaction_date,
    direction: row.direction,
    amount: numeric(row.amount),
    reference: row.reference,
    description: row.description,
    matchStatus: row.match_status,
    matchedSourceType: row.matched_source_type,
    matchedSourceId: row.matched_source_id,
    matchedBy: row.matched_by,
    matchedAt: row.matched_at,
    unmatchReason: row.unmatch_reason,
    recordVersion: row.record_version,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  });
}

/** Maps a raw app.get_finance_cash_position row (snake_case) to this contract's camelCase shape. */
export function parseFinanceCashPosition(row: Record<string, unknown>): FinanceCashPosition {
  const numeric = (value: unknown) => (typeof value === "string" ? Number(value) : value);
  return FinanceCashPositionSchema.parse({
    bankAccountId: row.bank_account_id,
    currency: row.currency,
    statementBalance: numeric(row.statement_balance),
    glBalance: numeric(row.gl_balance),
    varianceAmount: numeric(row.variance_amount),
  });
}
