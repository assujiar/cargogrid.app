/**
 * Customer Portal Payment Visibility read queries (CPL-312, CG-S13-CPL-014).
 * Thin, typed wrappers around both RPCs in supabase/migrations/
 * 20260801130000_create_customer_portal_payment_visibility.sql, mirroring
 * server/queries/customer-portal-invoice.ts's own wrapper shape.
 *
 * No separate denial-audit call on app.get_customer_portal_payment_status'
 * own record_not_found path -- it is a DEPENDENT read of the same invoice
 * app.get_customer_portal_invoice already audits on denial (both compose the
 * identical app._resolve_customer_portal_invoice gate), mirroring CPL-311's
 * own established "no separate denial audit for a dependent read" precedent
 * (getCustomerPortalInvoiceLines/getCustomerPortalInvoicePaymentStatus).
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import {
  parseCustomerPortalPaymentStatus,
  parseCustomerPortalReceipt,
  type CustomerPortalPaymentStatus,
  type CustomerPortalReceipt,
  type CustomerPortalReceiptStatus,
} from "../contracts/customer-portal-payment/customer-portal-payment.ts";

export type CustomerPortalPaymentQueryClient = Pick<SupabaseClient, "rpc">;

const KNOWN_QUERY_ERROR_CODES = ["record_not_found", "actor_identity_mismatch", "invalid_cursor"] as const;
type KnownQueryErrorCode = (typeof KNOWN_QUERY_ERROR_CODES)[number];
export type CustomerPortalPaymentQueryErrorCode = KnownQueryErrorCode | "query_failed";

export class CustomerPortalPaymentQueryError extends Error {
  readonly code: CustomerPortalPaymentQueryErrorCode;

  constructor(message: string) {
    super(message);
    this.name = "CustomerPortalPaymentQueryError";
    const prefix = message.split(":")[0]?.trim();
    this.code = (KNOWN_QUERY_ERROR_CODES as readonly string[]).includes(prefix ?? "") ? (prefix as KnownQueryErrorCode) : "query_failed";
  }
}

function firstRow(data: unknown): Record<string, unknown> | null {
  const row = Array.isArray(data) ? data[0] : data;
  return row && typeof row === "object" ? (row as Record<string, unknown>) : null;
}

/**
 * The invoice's own AR status (open/partial/paid/not_posted) plus its
 * applied receipt allocations. Throws record_not_found (anti-enumerating,
 * .code === "record_not_found") on the identical cases app.get_customer_
 * portal_invoice already 404s on -- missing, not yet issued, or forbidden.
 */
export async function getCustomerPortalPaymentStatus(client: CustomerPortalPaymentQueryClient, tenantId: string, actorAuthUserId: string, invoiceId: string): Promise<CustomerPortalPaymentStatus> {
  const { data, error } = await client.rpc("get_customer_portal_payment_status", {
    p_tenant_id: tenantId,
    p_actor_auth_user_id: actorAuthUserId,
    p_invoice_id: invoiceId,
  });
  if (error) {
    throw new CustomerPortalPaymentQueryError(error.message);
  }
  const row = firstRow(data);
  if (!row) {
    throw new CustomerPortalPaymentQueryError("query_failed: get_customer_portal_payment_status returned no row");
  }
  return parseCustomerPortalPaymentStatus(row);
}

/** Common cursor options app.list_customer_portal_receipts accepts -- pass the previous page's last row's own updatedAt/id to advance; omit both for the first page. */
export interface CustomerPortalReceiptCursorOptions {
  cursorUpdatedAt?: string | null;
  cursorId?: string | null;
  limit?: number;
}

/** Bounded (default 50, hard-capped 200 server-side), account-scoped, keyset-paginated. Both real receipt statuses (captured/void) are returned -- never bank_account_label/payer_name. */
export async function listCustomerPortalReceipts(
  client: CustomerPortalPaymentQueryClient,
  tenantId: string,
  actorAuthUserId: string,
  options?: CustomerPortalReceiptCursorOptions & { statusFilter?: CustomerPortalReceiptStatus | null },
): Promise<CustomerPortalReceipt[]> {
  const { data, error } = await client.rpc("list_customer_portal_receipts", {
    p_tenant_id: tenantId,
    p_actor_auth_user_id: actorAuthUserId,
    p_status_filter: options?.statusFilter ?? null,
    p_cursor_updated_at: options?.cursorUpdatedAt ?? null,
    p_cursor_id: options?.cursorId ?? null,
    p_limit: options?.limit ?? 50,
  });
  if (error) {
    throw new CustomerPortalPaymentQueryError(error.message);
  }
  return ((data as Record<string, unknown>[] | null) ?? []).map(parseCustomerPortalReceipt);
}
