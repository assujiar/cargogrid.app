/**
 * Receipt and Payment Allocation read queries (FIN-198, CG-S9-FIN-009). Thin,
 * typed wrappers around app.list_finance_receipts /
 * app.get_finance_receipt_allocations / app.search_finance_ar_candidates_for_receipt
 * (supabase/migrations/20260729120000_create_finance_receipt_allocation.sql).
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import {
  parseFinanceReceipt,
  parseFinanceReceiptAllocation,
  type FinanceReceipt,
  type FinanceReceiptAllocation,
} from "../contracts/receipt-allocation/receipt-allocation.ts";
import { parseFinanceArOpenItem, type FinanceArOpenItem } from "../contracts/accounts-receivable/accounts-receivable.ts";

export type ReceiptAllocationQueryRpcClient = Pick<SupabaseClient, "rpc">;

export class ReceiptAllocationQueryError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "ReceiptAllocationQueryError";
  }
}

/** FIN:View-gated. Bounded (200-row), server-filtered list, most-recent receipt date first. */
export async function listFinanceReceipts(
  client: ReceiptAllocationQueryRpcClient,
  input: { tenantId: string; companyId: string | null; customerAccountId: string | null; status: string | null; actorAuthUserId: string },
): Promise<FinanceReceipt[]> {
  const { data, error } = await client.rpc("list_finance_receipts", {
    p_tenant_id: input.tenantId,
    p_company_id: input.companyId,
    p_customer_account_id: input.customerAccountId,
    p_status: input.status,
    p_actor_auth_user_id: input.actorAuthUserId,
  });
  if (error) {
    throw new ReceiptAllocationQueryError(error.message);
  }
  const rows = Array.isArray(data) ? data : [];
  return rows.map((row) => parseFinanceReceipt(row as Record<string, unknown>));
}

/** FIN:View-gated. Full allocation lineage (applied and reversed) for one receipt, oldest first. */
export async function getFinanceReceiptAllocations(
  client: ReceiptAllocationQueryRpcClient,
  input: { receiptId: string; actorAuthUserId: string },
): Promise<FinanceReceiptAllocation[]> {
  const { data, error } = await client.rpc("get_finance_receipt_allocations", {
    p_receipt_id: input.receiptId,
    p_actor_auth_user_id: input.actorAuthUserId,
  });
  if (error) {
    throw new ReceiptAllocationQueryError(error.message);
  }
  const rows = Array.isArray(data) ? data : [];
  return rows.map((row) => parseFinanceReceiptAllocation(row as Record<string, unknown>));
}

/** FIN:View-gated. Suggested AR open-item candidates for a receipt -- same customer/currency, not fully paid, not held, due-date ordered. */
export async function searchFinanceArCandidatesForReceipt(
  client: ReceiptAllocationQueryRpcClient,
  input: { receiptId: string; actorAuthUserId: string },
): Promise<FinanceArOpenItem[]> {
  const { data, error } = await client.rpc("search_finance_ar_candidates_for_receipt", {
    p_receipt_id: input.receiptId,
    p_actor_auth_user_id: input.actorAuthUserId,
  });
  if (error) {
    throw new ReceiptAllocationQueryError(error.message);
  }
  const rows = Array.isArray(data) ? data : [];
  return rows.map((row) => parseFinanceArOpenItem(row as Record<string, unknown>));
}
