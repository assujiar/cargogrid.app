/**
 * Settlement read queries (FIN-201, CG-S9-FIN-012). Thin, typed wrappers
 * around app.list_finance_settlements / app.get_finance_settlement_allocations /
 * app.search_finance_ap_candidates_for_settlement
 * (supabase/migrations/20260729150000_create_finance_settlement.sql).
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import { parseFinanceSettlement, parseFinanceSettlementAllocation, type FinanceSettlement, type FinanceSettlementAllocation } from "../contracts/settlement/settlement.ts";
import { BOUNDED_LIST_LIMIT } from "./bounded-list.ts";
import { parseFinanceApOpenItem, type FinanceApOpenItem } from "../contracts/accounts-payable/accounts-payable.ts";

export type SettlementQueryRpcClient = Pick<SupabaseClient, "rpc">;

export class SettlementQueryError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "SettlementQueryError";
  }
}

/** FIN:View-gated. Bounded (200-row), server-filtered list, most-recent first. */
/** CG-AUDIT-2026-09-02 F3: `afterId`/`limit` optional and additive -- see server/queries/accounts-receivable.ts#listFinanceArOpenItems's own header comment for the full rationale. */
export async function listFinanceSettlements(
  client: SettlementQueryRpcClient,
  input: { tenantId: string; companyId: string | null; vendorMasterId: string | null; status: string | null; actorAuthUserId: string; limit?: number; afterId?: string | null },
): Promise<FinanceSettlement[]> {
  const limit = input.limit ?? BOUNDED_LIST_LIMIT;
  const { data, error } = await client.rpc("list_finance_settlements", {
    p_tenant_id: input.tenantId,
    p_company_id: input.companyId,
    p_vendor_master_id: input.vendorMasterId,
    p_status: input.status,
    p_actor_auth_user_id: input.actorAuthUserId,
    p_limit: limit,
    p_after_id: input.afterId ?? null,
  });
  if (error) {
    throw new SettlementQueryError(error.message);
  }
  const rows = Array.isArray(data) ? data : [];
  return rows.slice(0, limit).map((row) => parseFinanceSettlement(row as Record<string, unknown>));
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
