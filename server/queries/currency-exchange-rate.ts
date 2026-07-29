/**
 * Currency and Exchange Rate read queries (FIN-194, CG-S9-FIN-005). Thin,
 * typed wrappers around app.list_finance_exchange_rates /
 * app.resolve_finance_exchange_rate / app.convert_finance_amount, plus a
 * direct-table read for app.finance_currencies (mirrors
 * app.finance_rounding_modes' own direct-table-read convention -- see
 * server/queries/finance-config.ts's listFinanceRoundingModes)
 * (supabase/migrations/20260728230000_create_finance_currency_exchange_rate.sql).
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import {
  parseFinanceCurrency,
  parseFinanceExchangeRate,
  parseFinanceConvertedAmount,
  type FinanceCurrency,
  type FinanceExchangeRate,
  type FinanceConvertedAmount,
} from "../contracts/currency-exchange-rate/currency-exchange-rate.ts";

export type CurrencyExchangeRateQueryRpcClient = Pick<SupabaseClient, "rpc">;
export type FinanceCurrencyTableClient = Pick<SupabaseClient, "from">;

export class CurrencyExchangeRateQueryError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "CurrencyExchangeRateQueryError";
  }
}

/** Direct RLS-scoped read of the governed currency registry (app.finance_currencies carries a broad `to authenticated using (true)` SELECT policy, no RPC needed). */
export async function listFinanceCurrencies(client: FinanceCurrencyTableClient): Promise<FinanceCurrency[]> {
  const { data, error } = await client.from("finance_currencies").select("*").order("code", { ascending: true });
  if (error) {
    throw new CurrencyExchangeRateQueryError(error.message);
  }
  return (data ?? []).map((row) => parseFinanceCurrency(row as Record<string, unknown>));
}

/** Bounded, authority-gated list read, ordered effective_from desc. */
export async function listFinanceExchangeRates(
  client: CurrencyExchangeRateQueryRpcClient,
  input: { tenantId: string | null; rateType: string | null; sourceCurrency: string | null; targetCurrency: string | null; actorAuthUserId: string },
): Promise<FinanceExchangeRate[]> {
  const { data, error } = await client.rpc("list_finance_exchange_rates", {
    p_tenant_id: input.tenantId,
    p_rate_type: input.rateType,
    p_source_currency: input.sourceCurrency,
    p_target_currency: input.targetCurrency,
    p_actor_auth_user_id: input.actorAuthUserId,
  });
  if (error) {
    throw new CurrencyExchangeRateQueryError(error.message);
  }
  const rows = Array.isArray(data) ? data : [];
  return rows.map((row) => parseFinanceExchangeRate(row as Record<string, unknown>));
}

/**
 * Deterministic resolution (tenant-specific approved rate wins over the
 * platform-wide default). Returns null if no approved rate covers p_as_of at
 * either level -- callers must treat that as "missing rate," never assume one.
 */
export async function resolveFinanceExchangeRate(
  client: CurrencyExchangeRateQueryRpcClient,
  input: { tenantId: string | null; rateType: string; sourceCurrency: string; targetCurrency: string; asOf: string | null },
): Promise<FinanceExchangeRate | null> {
  const { data, error } = await client.rpc("resolve_finance_exchange_rate", {
    p_tenant_id: input.tenantId,
    p_rate_type: input.rateType,
    p_source_currency: input.sourceCurrency,
    p_target_currency: input.targetCurrency,
    p_as_of: input.asOf ?? undefined,
  });
  if (error) {
    throw new CurrencyExchangeRateQueryError(error.message);
  }
  const row = Array.isArray(data) ? data[0] : data;
  return row && typeof row === "object" ? parseFinanceExchangeRate(row as Record<string, unknown>) : null;
}

/**
 * Convert-preview: FIN:View-gated, same-currency short-circuit, resolves the
 * tenant's own effective finance_rounding config (FIN-191) server-side.
 * Throws (via CurrencyExchangeRateQueryError) if no approved rate covers the
 * requested instant -- never silently substitutes a stale or default rate.
 */
export async function convertFinanceAmount(
  client: CurrencyExchangeRateQueryRpcClient,
  input: { tenantId: string | null; amount: number; sourceCurrency: string; targetCurrency: string; rateType: string; asOf: string | null; actorAuthUserId: string },
): Promise<FinanceConvertedAmount> {
  const { data, error } = await client.rpc("convert_finance_amount", {
    p_tenant_id: input.tenantId,
    p_amount: input.amount,
    p_source_currency: input.sourceCurrency,
    p_target_currency: input.targetCurrency,
    p_rate_type: input.rateType,
    p_as_of: input.asOf ?? undefined,
    p_actor_auth_user_id: input.actorAuthUserId,
  });
  if (error) {
    throw new CurrencyExchangeRateQueryError(error.message);
  }
  if (!data || typeof data !== "object") {
    throw new CurrencyExchangeRateQueryError("convert_finance_amount returned no result");
  }
  return parseFinanceConvertedAmount(data as Record<string, unknown>);
}
