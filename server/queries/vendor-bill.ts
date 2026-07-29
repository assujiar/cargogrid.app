/**
 * Vendor Bill read queries (FIN-200, CG-S9-FIN-011). Thin, typed wrappers
 * around app.list_finance_vendor_bills / app.get_finance_vendor_bill_lines
 * (supabase/migrations/20260729140000_create_finance_vendor_bill.sql).
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import { parseFinanceVendorBill, parseFinanceVendorBillLine, type FinanceVendorBill, type FinanceVendorBillLine } from "../contracts/vendor-bill/vendor-bill.ts";

export type VendorBillQueryRpcClient = Pick<SupabaseClient, "rpc">;

export class VendorBillQueryError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "VendorBillQueryError";
  }
}

/** FIN:View-gated. Bounded (200-row), server-filtered list, most-recent first. */
export async function listFinanceVendorBills(
  client: VendorBillQueryRpcClient,
  input: { tenantId: string; companyId: string | null; vendorMasterId: string | null; status: string | null; actorAuthUserId: string },
): Promise<FinanceVendorBill[]> {
  const { data, error } = await client.rpc("list_finance_vendor_bills", {
    p_tenant_id: input.tenantId,
    p_company_id: input.companyId,
    p_vendor_master_id: input.vendorMasterId,
    p_status: input.status,
    p_actor_auth_user_id: input.actorAuthUserId,
  });
  if (error) {
    throw new VendorBillQueryError(error.message);
  }
  const rows = Array.isArray(data) ? data : [];
  return rows.map((row) => parseFinanceVendorBill(row as Record<string, unknown>));
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
