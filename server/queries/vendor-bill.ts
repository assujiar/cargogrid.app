/**
 * Vendor Bill read queries (FIN-200, CG-S9-FIN-011). Thin, typed wrappers
 * around app.list_finance_vendor_bills / app.get_finance_vendor_bill_lines
 * (supabase/migrations/20260729140000_create_finance_vendor_bill.sql).
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import { parseFinanceVendorBill, parseFinanceVendorBillLine, type FinanceVendorBill, type FinanceVendorBillLine } from "../contracts/vendor-bill/vendor-bill.ts";
import { BOUNDED_LIST_LIMIT } from "./bounded-list.ts";

export type VendorBillQueryRpcClient = Pick<SupabaseClient, "rpc">;

export class VendorBillQueryError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "VendorBillQueryError";
  }
}

/** FIN:View-gated. Bounded (200-row), server-filtered list, most-recent first. */
/** CG-AUDIT-2026-09-02 F3: `afterId`/`limit` optional and additive -- see server/queries/accounts-receivable.ts#listFinanceArOpenItems's own header comment for the full rationale. */
export async function listFinanceVendorBills(
  client: VendorBillQueryRpcClient,
  input: { tenantId: string; companyId: string | null; vendorMasterId: string | null; status: string | null; actorAuthUserId: string; limit?: number; afterId?: string | null },
): Promise<FinanceVendorBill[]> {
  const limit = input.limit ?? BOUNDED_LIST_LIMIT;
  const { data, error } = await client.rpc("list_finance_vendor_bills", {
    p_tenant_id: input.tenantId,
    p_company_id: input.companyId,
    p_vendor_master_id: input.vendorMasterId,
    p_status: input.status,
    p_actor_auth_user_id: input.actorAuthUserId,
    p_limit: limit,
    p_after_id: input.afterId ?? null,
  });
  if (error) {
    throw new VendorBillQueryError(error.message);
  }
  const rows = Array.isArray(data) ? data : [];
  return rows.slice(0, limit).map((row) => parseFinanceVendorBill(row as Record<string, unknown>));
}

/** FIN:View-gated. Every cost/tax line for one bill, ordered by line_number. */
export async function getFinanceVendorBillLines(
  client: VendorBillQueryRpcClient,
  input: { billId: string; actorAuthUserId: string },
): Promise<FinanceVendorBillLine[]> {
  const { data, error } = await client.rpc("get_finance_vendor_bill_lines", {
    p_bill_id: input.billId,
    p_actor_auth_user_id: input.actorAuthUserId,
  });
  if (error) {
    throw new VendorBillQueryError(error.message);
  }
  const rows = Array.isArray(data) ? data : [];
  return rows.map((row) => parseFinanceVendorBillLine(row as Record<string, unknown>));
}
