/**
 * Settlement read queries (FIN-201, CG-S9-FIN-012). Thin, typed wrappers
 * around app.list_finance_settlements / app.get_finance_settlement_allocations /
 * app.search_finance_ap_candidates_for_settlement
 * (supabase/migrations/20260729150000_create_finance_settlement.sql).
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import { parseFinanceSettlement, parseFinanceSettlementAllocation, type FinanceSettlement, type FinanceSettlementAllocation } from "../contracts/settlement/settlement.ts";
import { parseFinanceApOpenItem, type FinanceApOpenItem } from "../contracts/accounts-payable/accounts-payable.ts";

export type SettlementQueryRpcClient = Pick<SupabaseClient, "rpc">;

export class SettlementQueryError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "SettlementQueryError";
  }
}

/** FIN:View-gated. Bounded (200-row), server-filtered list, most-recent first. */
export async function listFinanceSettlements(
  client: SettlementQueryRpcClient,
  input: { tenantId: string; companyId: string | null; vendorMasterId: string | null; status: string | null; actorAuthUserId: string },
): Promise<FinanceSettlement[]> {
  const { data, error } = await client.rpc("list_finance_settlements", {
    p_tenant_id: input.tenantId,
    p_company_id: input.companyId,
    p_vendor_master_id: input.vendorMasterId,
    p_status: input.status,
    p_actor_auth_user_id: input.actorAuthUserId,
  });
  if (error) {
    throw new SettlementQueryError(error.message);
  }
  const rows = Array.isArray(data) ? data : [];
  return rows.map((row) => parseFinanceSettlement(row as Record<string, unknown>));
}

/** FIN:View-gated. Every allocation line for one settlement, oldest first. */
export async function getFinanceSettlementAllocations(
  client: SettlementQueryRpcClient,
  input: { settlementId: string; actorAuthUserId: string },
): Promise<FinanceSettlementAllocation[]> {
  const { data, error } = await client.rpc("get_finance_settlement_allocations", {
    p_settlement_id: input.settlementId,
    p_actor_auth_user_id: input.actorAuthUserId,
  });
  if (error) {
    throw new SettlementQueryError(error.message);
  }
  const rows = Array.isArray(data) ? data : [];
  return rows.map((row) => parseFinanceSettlementAllocation(row as Record<string, unknown>));
}

/** FIN:View-gated. Suggested AP open-item candidates for a vendor/currency pair: not held, not fully settled, due-date ordered. */
export async function searchFinanceApCandidatesForSettlement(
  client: SettlementQueryRpcClient,
  input: { tenantId: string; vendorMasterId: string; currency: string; actorAuthUserId: string },
): Promise<FinanceApOpenItem[]> {
  const { data, error } = await client.rpc("search_finance_ap_candidates_for_settlement", {
    p_tenant_id: input.tenantId,
    p_vendor_master_id: input.vendorMasterId,
    p_currency: input.currency,
    p_actor_auth_user_id: input.actorAuthUserId,
  });
  if (error) {
    throw new SettlementQueryError(error.message);
  }
  const rows = Array.isArray(data) ? data : [];
  return rows.map((row) => parseFinanceApOpenItem(row as Record<string, unknown>));
}
