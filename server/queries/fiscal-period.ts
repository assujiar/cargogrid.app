/**
 * Fiscal Period read queries (FIN-193, CG-S9-FIN-004). Thin, typed wrappers
 * around app.list_finance_fiscal_periods / app.get_finance_period_close_readiness /
 * app.get_finance_period_transition_history / app.resolve_finance_period_for_date
 * (supabase/migrations/20260728220000_create_finance_fiscal_period.sql).
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import {
  parseFinanceFiscalPeriod,
  parseFinancePeriodCloseReadiness,
  parseFinancePeriodTransition,
  parseFinancePeriodDateResolution,
  parseFinancePeriodChecklistItem,
  type FinanceFiscalPeriod,
  type FinancePeriodCloseReadiness,
  type FinancePeriodTransition,
  type FinancePeriodDateResolution,
  type FinancePeriodChecklistItem,
} from "../contracts/fiscal-period/fiscal-period.ts";

export type FiscalPeriodQueryRpcClient = Pick<SupabaseClient, "rpc">;
export type FiscalPeriodChecklistTableClient = Pick<SupabaseClient, "from">;

export class FiscalPeriodQueryError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "FiscalPeriodQueryError";
  }
}

/** Bounded, authority-gated list read, ordered by sequence_number. */
export async function listFinanceFiscalPeriods(
  client: FiscalPeriodQueryRpcClient,
  input: { tenantId: string; companyId: string | null; calendarId: string | null; actorAuthUserId: string },
): Promise<FinanceFiscalPeriod[]> {
  const { data, error } = await client.rpc("list_finance_fiscal_periods", {
    p_tenant_id: input.tenantId,
    p_company_id: input.companyId,
    p_calendar_id: input.calendarId,
    p_actor_auth_user_id: input.actorAuthUserId,
  });
  if (error) {
    throw new FiscalPeriodQueryError(error.message);
  }
  const rows = Array.isArray(data) ? data : [];
  return rows.map((row) => parseFinanceFiscalPeriod(row as Record<string, unknown>));
}

/** Close readiness: whether every required checklist item is satisfied. */
export async function getFinancePeriodCloseReadiness(client: FiscalPeriodQueryRpcClient, periodId: string, actorAuthUserId: string): Promise<FinancePeriodCloseReadiness> {
  const { data, error } = await client.rpc("get_finance_period_close_readiness", { p_period_id: periodId, p_actor_auth_user_id: actorAuthUserId });
  if (error) {
    throw new FiscalPeriodQueryError(error.message);
  }
  if (!data || typeof data !== "object") {
    throw new FiscalPeriodQueryError("get_finance_period_close_readiness returned no result");
  }
  return parseFinancePeriodCloseReadiness(data as Record<string, unknown>);
}

/** Full lifecycle/reopen evidence, ordered oldest-first. */
export async function getFinancePeriodTransitionHistory(client: FiscalPeriodQueryRpcClient, periodId: string, actorAuthUserId: string): Promise<FinancePeriodTransition[]> {
  const { data, error } = await client.rpc("get_finance_period_transition_history", { p_period_id: periodId, p_actor_auth_user_id: actorAuthUserId });
  if (error) {
    throw new FiscalPeriodQueryError(error.message);
  }
  const rows = Array.isArray(data) ? data : [];
  return rows.map((row) => parseFinancePeriodTransition(row as Record<string, unknown>));
}

/** Direct RLS-scoped read of one period's own checklist items (app.finance_period_close_checklist_items carries a broad tenant-member SELECT policy, no RPC needed -- mirrors app.finance_rounding_modes' own direct-table-read convention). */
export async function listFinancePeriodChecklistItems(client: FiscalPeriodChecklistTableClient, periodId: string): Promise<FinancePeriodChecklistItem[]> {
  const { data, error } = await client.from("finance_period_close_checklist_items").select("*").eq("period_id", periodId).order("item_key", { ascending: true });
  if (error) {
    throw new FiscalPeriodQueryError(error.message);
  }
  return (data ?? []).map((row) => parseFinancePeriodChecklistItem(row as Record<string, unknown>));
}

/** Deterministic date-to-period resolution -- the forward seam later posting capabilities will call. Returns null if no generated period covers the date. */
export async function resolveFinancePeriodForDate(
  client: FiscalPeriodQueryRpcClient,
  input: { tenantId: string; companyId: string | null; transactionDate: string },
): Promise<FinancePeriodDateResolution | null> {
  const { data, error } = await client.rpc("resolve_finance_period_for_date", {
    p_tenant_id: input.tenantId,
    p_company_id: input.companyId,
    p_transaction_date: input.transactionDate,
  });
  if (error) {
    throw new FiscalPeriodQueryError(error.message);
  }
  const row = Array.isArray(data) ? data[0] : data;
  return row && typeof row === "object" ? parseFinancePeriodDateResolution(row as Record<string, unknown>) : null;
}
