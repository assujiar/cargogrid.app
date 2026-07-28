/**
 * Currency and Exchange Rate contract (FIN-194, CG-S9-FIN-005). Mirrors
 * supabase/migrations/20260728230000_create_finance_currency_exchange_rate.sql's
 * app.finance_currencies / app.finance_exchange_rates /
 * app.finance_exchange_rate_import_batches shapes and their RPCs.
 */

import { z } from "zod";

export const FinanceCurrencySchema = z.object({
  code: z.string().regex(/^[A-Z]{3}$/),
  name: z.string(),
  minorUnitPrecision: z.number().int().min(0).max(6),
  isActive: z.boolean(),
});
export type FinanceCurrency = z.infer<typeof FinanceCurrencySchema>;

export const FINANCE_EXCHANGE_RATE_STATUSES = ["draft", "approved", "archived"] as const;
export const FinanceExchangeRateStatusSchema = z.enum(FINANCE_EXCHANGE_RATE_STATUSES);
export type FinanceExchangeRateStatus = z.infer<typeof FinanceExchangeRateStatusSchema>;

export const FinanceExchangeRateSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid().nullable(),
  rateType: z.string(),
  sourceCurrency: z.string(),
  targetCurrency: z.string(),
  rate: z.number(),
  source: z.string(),
  effectiveFrom: z.string(),
  effectiveTo: z.string().nullable(),
  status: FinanceExchangeRateStatusSchema,
  approvedBy: z.string().nullable(),
  approvedAt: z.string().nullable(),
  importBatchId: z.string().uuid().nullable(),
  recordVersion: z.number().int().positive(),
  createdBy: z.string().nullable(),
  createdAt: z.string(),
  updatedAt: z.string(),
});
export type FinanceExchangeRate = z.infer<typeof FinanceExchangeRateSchema>;

export const FinanceConvertedAmountSchema = z.object({
  amount: z.number(),
  sourceCurrency: z.string(),
  targetCurrency: z.string(),
  rate: z.number(),
  rateId: z.string().uuid().nullable(),
  convertedAmount: z.number(),
  roundingMode: z.string(),
  roundingOrder: z.string().nullable().optional(),
});
export type FinanceConvertedAmount = z.infer<typeof FinanceConvertedAmountSchema>;

export const CreateFinanceExchangeRateDraftInputSchema = z.object({
  tenantId: z.string().uuid().nullable().default(null),
  rateType: z.string().min(1).default("spot"),
  sourceCurrency: z.string().regex(/^[A-Z]{3}$/),
  targetCurrency: z.string().regex(/^[A-Z]{3}$/),
  rate: z.number().positive(),
  source: z.string().min(1).default("manual"),
  effectiveFrom: z.string(),
  effectiveTo: z.string().nullable().default(null),
  actorAuthUserId: z.string().uuid(),
  createdBy: z.string().min(1),
});
export type CreateFinanceExchangeRateDraftInput = z.input<typeof CreateFinanceExchangeRateDraftInputSchema>;

export const DiscardFinanceExchangeRateDraftInputSchema = z.object({
  rateId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  reason: z.string().nullable().default(null),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type DiscardFinanceExchangeRateDraftInput = z.input<typeof DiscardFinanceExchangeRateDraftInputSchema>;

export const ApproveFinanceExchangeRateInputSchema = z.object({
  rateId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type ApproveFinanceExchangeRateInput = z.input<typeof ApproveFinanceExchangeRateInputSchema>;

export const ConvertFinanceAmountInputSchema = z.object({
  tenantId: z.string().uuid().nullable(),
  amount: z.number(),
  sourceCurrency: z.string().regex(/^[A-Z]{3}$/),
  targetCurrency: z.string().regex(/^[A-Z]{3}$/),
  rateType: z.string().min(1).default("spot"),
  asOf: z.string().nullable().default(null),
  actorAuthUserId: z.string().uuid(),
});
export type ConvertFinanceAmountInput = z.input<typeof ConvertFinanceAmountInputSchema>;

/** Maps a raw app.finance_currencies row (snake_case) to this contract's camelCase shape. */
export function parseFinanceCurrency(row: Record<string, unknown>): FinanceCurrency {
  return FinanceCurrencySchema.parse({
    code: row.code,
    name: row.name,
    minorUnitPrecision: row.minor_unit_precision,
    isActive: row.is_active,
  });
}

/** Maps a raw app.finance_exchange_rates row (snake_case) to this contract's camelCase shape. */
export function parseFinanceExchangeRate(row: Record<string, unknown>): FinanceExchangeRate {
  return FinanceExchangeRateSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    rateType: row.rate_type,
    sourceCurrency: row.source_currency,
    targetCurrency: row.target_currency,
    rate: typeof row.rate === "string" ? Number(row.rate) : row.rate,
    source: row.source,
    effectiveFrom: row.effective_from,
    effectiveTo: row.effective_to,
    status: row.status,
    approvedBy: row.approved_by,
    approvedAt: row.approved_at,
    importBatchId: row.import_batch_id,
    recordVersion: row.record_version,
    createdBy: row.created_by,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  });
}

/** Maps a raw app.convert_finance_amount() jsonb result to this contract's camelCase shape. */
export function parseFinanceConvertedAmount(row: Record<string, unknown>): FinanceConvertedAmount {
  return FinanceConvertedAmountSchema.parse({
    amount: row.amount,
    sourceCurrency: row.sourceCurrency,
    targetCurrency: row.targetCurrency,
    rate: typeof row.rate === "string" ? Number(row.rate) : row.rate,
    rateId: row.rateId ?? null,
    convertedAmount: row.convertedAmount,
    roundingMode: row.roundingMode,
    roundingOrder: row.roundingOrder ?? null,
  });
}
