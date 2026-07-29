/**
 * Customer Invoice read queries (FIN-197, CG-S9-FIN-008). Thin, typed
 * wrappers around app.list_finance_invoices / app.get_finance_invoice_lines
 * (supabase/migrations/20260729110000_create_finance_invoice.sql).
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import { parseFinanceInvoice, parseFinanceInvoiceLine, type FinanceInvoice, type FinanceInvoiceLine } from "../contracts/invoice/invoice.ts";

export type InvoiceQueryRpcClient = Pick<SupabaseClient, "rpc">;

export class InvoiceQueryError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "InvoiceQueryError";
  }
}

/** FIN:View-gated. Bounded (200-row), server-filtered list, most-recent first. */
export async function listFinanceInvoices(
  client: InvoiceQueryRpcClient,
  input: { tenantId: string; companyId: string | null; customerAccountId: string | null; status: string | null; actorAuthUserId: string },
): Promise<FinanceInvoice[]> {
  const { data, error } = await client.rpc("list_finance_invoices", {
    p_tenant_id: input.tenantId,
    p_company_id: input.companyId,
    p_customer_account_id: input.customerAccountId,
    p_status: input.status,
    p_actor_auth_user_id: input.actorAuthUserId,
  });
  if (error) {
    throw new InvoiceQueryError(error.message);
  }
  const rows = Array.isArray(data) ? data : [];
  return rows.map((row) => parseFinanceInvoice(row as Record<string, unknown>));
}

/** FIN:View-gated. Every charge/tax line for one invoice, ordered by line_number. */
export async function getFinanceInvoiceLines(
  client: InvoiceQueryRpcClient,
  input: { invoiceId: string; actorAuthUserId: string },
): Promise<FinanceInvoiceLine[]> {
  const { data, error } = await client.rpc("get_finance_invoice_lines", {
    p_invoice_id: input.invoiceId,
    p_actor_auth_user_id: input.actorAuthUserId,
  });
  if (error) {
    throw new InvoiceQueryError(error.message);
  }
  const rows = Array.isArray(data) ? data : [];
  return rows.map((row) => parseFinanceInvoiceLine(row as Record<string, unknown>));
}
