/**
 * Customer Document Center read query (CPL-308, CG-S13-CPL-010). Thin, typed
 * wrapper around app.list_customer_documents (supabase/migrations/
 * 20260801090000_create_customer_portal_document_center.sql), mirroring
 * server/queries/customer-shipment-order.ts's own wrapper shape exactly.
 *
 * A plain, unaudited read -- only the per-document access/download action
 * (server/mutations/customer-document.ts, app.get_customer_document) writes
 * an audit trail, matching every other Phase 8 list RPC's own established
 * "list RPCs are not individually audited" precedent (migration design
 * decision 7).
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import { parseCustomerDocument, type CustomerDocument, type CustomerDocumentSourceModule } from "../contracts/customer-document/customer-document.ts";

export type CustomerDocumentQueryClient = Pick<SupabaseClient, "rpc">;

const KNOWN_QUERY_ERROR_CODES = ["actor_identity_mismatch", "invalid_cursor", "invalid_source_module", "invalid_date_range"] as const;
type KnownQueryErrorCode = (typeof KNOWN_QUERY_ERROR_CODES)[number];
export type CustomerDocumentQueryErrorCode = KnownQueryErrorCode | "query_failed";

export class CustomerDocumentQueryError extends Error {
  readonly code: CustomerDocumentQueryErrorCode;

  constructor(message: string) {
    super(message);
    this.name = "CustomerDocumentQueryError";
    const prefix = message.split(":")[0]?.trim();
    this.code = (KNOWN_QUERY_ERROR_CODES as readonly string[]).includes(prefix ?? "") ? (prefix as KnownQueryErrorCode) : "query_failed";
  }
}

export interface CustomerDocumentCursorOptions {
  cursorCreatedAt?: string | null;
  cursorId?: string | null;
  limit?: number;
}

export interface CustomerDocumentFilterOptions {
  accountId?: string | null;
  shipmentOrderId?: string | null;
  sourceModule?: CustomerDocumentSourceModule | null;
  dateFrom?: string | null;
  dateTo?: string | null;
}

/**
 * Keyset-paginated (tenant_id, created_at desc, document_id desc), never
 * OFFSET, hard-capped at 200 server-side. Deny-by-default: zero scope, or an
 * out-of-scope accountId filter, both return an empty array, never an error.
 * `sourceModule: "invoice" | "ticket"` are recognized filter values that
 * always return an empty array today (no live backing source yet, migration
 * design decision 2) -- never an error.
 */
export async function listCustomerDocuments(
  client: CustomerDocumentQueryClient,
  tenantId: string,
  actorAuthUserId: string,
  options?: CustomerDocumentCursorOptions & CustomerDocumentFilterOptions,
): Promise<CustomerDocument[]> {
  const { data, error } = await client.rpc("list_customer_documents", {
    p_tenant_id: tenantId,
    p_actor_auth_user_id: actorAuthUserId,
    p_account_id: options?.accountId ?? null,
    p_shipment_order_id: options?.shipmentOrderId ?? null,
    p_source_module: options?.sourceModule ?? null,
    p_date_from: options?.dateFrom ?? null,
    p_date_to: options?.dateTo ?? null,
    p_cursor_created_at: options?.cursorCreatedAt ?? null,
    p_cursor_id: options?.cursorId ?? null,
    p_limit: options?.limit ?? 50,
  });
  if (error) {
    throw new CustomerDocumentQueryError(error.message);
  }
  return ((data as Record<string, unknown>[] | null) ?? []).map(parseCustomerDocument);
}
