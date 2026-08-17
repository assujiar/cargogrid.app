/**
 * Customer Portal Invoice and Billing Visibility read queries (CPL-311,
 * CG-S13-CPL-013). Thin, typed wrappers around every RPC in
 * supabase/migrations/20260801120000_create_customer_portal_invoice_billing_
 * visibility.sql, mirroring server/queries/customer-portal-warehouse-order.ts's
 * own wrapper shape exactly -- including the same anti-enumerating
 * record_not_found convention and denial-audit follow-up call on the single-
 * record get RPC only (never on the lines/payment-status RPCs, mirroring
 * listCustomerPortalOutboundOrderLines' own established "no separate denial
 * audit for a dependent read" precedent).
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import {
  parseCustomerPortalInvoice,
  parseCustomerPortalInvoiceLine,
  parseCustomerPortalInvoicePayment,
  type CustomerPortalInvoice,
  type CustomerPortalInvoiceLine,
  type CustomerPortalInvoicePayment,
  type CustomerPortalInvoiceStatus,
} from "../contracts/customer-portal-invoice/customer-portal-invoice.ts";

export type CustomerPortalInvoiceQueryClient = Pick<SupabaseClient, "rpc">;

const KNOWN_QUERY_ERROR_CODES = ["record_not_found", "actor_identity_mismatch", "invalid_cursor"] as const;
type KnownQueryErrorCode = (typeof KNOWN_QUERY_ERROR_CODES)[number];
export type CustomerPortalInvoiceQueryErrorCode = KnownQueryErrorCode | "query_failed";

export class CustomerPortalInvoiceQueryError extends Error {
  readonly code: CustomerPortalInvoiceQueryErrorCode;

  constructor(message: string) {
    super(message);
    this.name = "CustomerPortalInvoiceQueryError";
    const prefix = message.split(":")[0]?.trim();
    this.code = (KNOWN_QUERY_ERROR_CODES as readonly string[]).includes(prefix ?? "") ? (prefix as KnownQueryErrorCode) : "query_failed";
  }
}

function firstRow(data: unknown): Record<string, unknown> | null {
  const row = Array.isArray(data) ? data[0] : data;
  return row && typeof row === "object" ? (row as Record<string, unknown>) : null;
}

/**
 * Durable denial audit, issued in a NEW, separate RPC call/transaction after
 * catching app.get_customer_portal_invoice's own anti-enumerating
 * record_not_found -- reuses app.record_customer_inventory_access_denial
 * (ATW-023) exactly as-is, a genuinely generic actor/resource-type/
 * resource-id primitive not tied to any one resolver (CPL-309/310 both
 * already reuse it for their own resource types). Best-effort -- a failure
 * here must never mask or replace the original anti-enumerating error the
 * caller is about to see.
 */
async function recordCustomerPortalInvoiceAccessDenial(client: CustomerPortalInvoiceQueryClient, tenantId: string, actorAuthUserId: string, resourceId: string): Promise<void> {
  try {
    await client.rpc("record_customer_inventory_access_denial", {
      p_tenant_id: tenantId,
      p_actor_auth_user_id: actorAuthUserId,
      p_resource_type: "invoice",
      p_resource_id: resourceId,
    });
  } catch {
    // Best-effort: the original record_not_found error is what the caller must see.
  }
}

/** Common cursor options app.list_customer_portal_invoices accepts -- pass the previous page's last row's own updatedAt/id to advance; omit both for the first page. */
export interface CustomerPortalInvoiceCursorOptions {
  cursorUpdatedAt?: string | null;
  cursorId?: string | null;
  limit?: number;
}

/** Single permitted invoice by id. Throws record_not_found (anti-enumerating, .code === "record_not_found") if missing, not yet issued, or forbidden; also records a durable denial audit on that path. */
export async function getCustomerPortalInvoice(client: CustomerPortalInvoiceQueryClient, tenantId: string, actorAuthUserId: string, invoiceId: string): Promise<CustomerPortalInvoice> {
  const { data, error } = await client.rpc("get_customer_portal_invoice", {
    p_tenant_id: tenantId,
    p_actor_auth_user_id: actorAuthUserId,
    p_invoice_id: invoiceId,
  });
  if (error) {
    const wrapped = new CustomerPortalInvoiceQueryError(error.message);
    if (wrapped.code === "record_not_found") {
      await recordCustomerPortalInvoiceAccessDenial(client, tenantId, actorAuthUserId, invoiceId);
    }
    throw wrapped;
  }
  const row = firstRow(data);
  if (!row) {
    throw new CustomerPortalInvoiceQueryError("query_failed: get_customer_portal_invoice returned no row");
  }
  return parseCustomerPortalInvoice(row);
}

/** Bounded (default 50, hard-capped 200 server-side), account-scoped, keyset-paginated. Only issued/void invoices are ever returned. */
export async function listCustomerPortalInvoices(
  client: CustomerPortalInvoiceQueryClient,
  tenantId: string,
  actorAuthUserId: string,
  options?: CustomerPortalInvoiceCursorOptions & { statusFilter?: CustomerPortalInvoiceStatus | null },
): Promise<CustomerPortalInvoice[]> {
  const { data, error } = await client.rpc("list_customer_portal_invoices", {
    p_tenant_id: tenantId,
    p_actor_auth_user_id: actorAuthUserId,
    p_status_filter: options?.statusFilter ?? null,
    p_cursor_updated_at: options?.cursorUpdatedAt ?? null,
    p_cursor_id: options?.cursorId ?? null,
    p_limit: options?.limit ?? 50,
  });
  if (error) {
    throw new CustomerPortalInvoiceQueryError(error.message);
  }
  return ((data as Record<string, unknown>[] | null) ?? []).map(parseCustomerPortalInvoice);
}

/** Lines for a single permitted invoice, ordered by line_number. Reuses app.get_customer_portal_invoice's own gate internally -- record_not_found (anti-enumerating) if the invoice is missing, not yet issued, or forbidden. No separate denial audit (mirrors listCustomerPortalOutboundOrderLines' own established shape). */
export async function getCustomerPortalInvoiceLines(client: CustomerPortalInvoiceQueryClient, tenantId: string, actorAuthUserId: string, invoiceId: string): Promise<CustomerPortalInvoiceLine[]> {
  const { data, error } = await client.rpc("get_customer_portal_invoice_lines", {
    p_tenant_id: tenantId,
    p_actor_auth_user_id: actorAuthUserId,
    p_invoice_id: invoiceId,
  });
  if (error) {
    throw new CustomerPortalInvoiceQueryError(error.message);
  }
  return ((data as Record<string, unknown>[] | null) ?? []).map(parseCustomerPortalInvoiceLine);
}

/** Payment/aging status for a single permitted invoice, sourced from app.finance_ar_open_items via the invoice's own (never exposed) ar_open_item_id. No separate denial audit (mirrors the lines RPC above). */
export async function getCustomerPortalInvoicePaymentStatus(client: CustomerPortalInvoiceQueryClient, tenantId: string, actorAuthUserId: string, invoiceId: string): Promise<CustomerPortalInvoicePayment> {
  const { data, error } = await client.rpc("get_customer_portal_invoice_payment_status", {
    p_tenant_id: tenantId,
    p_actor_auth_user_id: actorAuthUserId,
    p_invoice_id: invoiceId,
  });
  if (error) {
    throw new CustomerPortalInvoiceQueryError(error.message);
  }
  const row = firstRow(data);
  if (!row) {
    throw new CustomerPortalInvoiceQueryError("query_failed: get_customer_portal_invoice_payment_status returned no row");
  }
  return parseCustomerPortalInvoicePayment(row);
}
