/**
 * Customer Quote Request read queries (CPL-302, CG-S13-CPL-004). Thin, typed
 * wrappers around every read RPC in supabase/migrations/
 * 20260801030000_create_customer_portal_quote_requests.sql, mirroring
 * server/queries/customer-portal-scope.ts's own wrapper shape exactly.
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import {
  parseCustomerQuoteRequest,
  parseCustomerQuoteRequestFile,
  type CustomerQuoteRequest,
  type CustomerQuoteRequestFile,
  type QuoteRequestStatus,
} from "../contracts/customer-quote-request/customer-quote-request.ts";

export type CustomerQuoteRequestQueryClient = Pick<SupabaseClient, "rpc">;

const KNOWN_QUERY_ERROR_CODES = ["record_not_found", "actor_identity_mismatch", "invalid_cursor"] as const;
type KnownQueryErrorCode = (typeof KNOWN_QUERY_ERROR_CODES)[number];
export type CustomerQuoteRequestQueryErrorCode = KnownQueryErrorCode | "query_failed";

export class CustomerQuoteRequestQueryError extends Error {
  readonly code: CustomerQuoteRequestQueryErrorCode;

  constructor(message: string) {
    super(message);
    this.name = "CustomerQuoteRequestQueryError";
    const prefix = message.split(":")[0]?.trim();
    this.code = (KNOWN_QUERY_ERROR_CODES as readonly string[]).includes(prefix ?? "") ? (prefix as KnownQueryErrorCode) : "query_failed";
  }
}

export interface CustomerQuoteRequestCursorOptions {
  cursorUpdatedAt?: string | null;
  cursorId?: string | null;
  limit?: number;
}

/**
 * Single permitted quote request by id. Throws record_not_found (anti-
 * enumerating, errcode no_data_found) whether the id genuinely does not
 * exist, belongs to another tenant, or exists but its account is outside
 * this identity's resolved scope -- the caller must not try to distinguish
 * the three from the thrown error's own content (mirrors ATW-242's own
 * documented convention).
 */
export async function getCustomerQuoteRequest(client: CustomerQuoteRequestQueryClient, tenantId: string, requestId: string, actorAuthUserId: string): Promise<CustomerQuoteRequest> {
  const { data, error } = await client.rpc("get_customer_quote_request", {
    p_tenant_id: tenantId,
    p_request_id: requestId,
    p_actor_auth_user_id: actorAuthUserId,
  });
  if (error) {
    throw new CustomerQuoteRequestQueryError(error.message);
  }
  const row = Array.isArray(data) ? data[0] : data;
  if (!row || typeof row !== "object") {
    throw new CustomerQuoteRequestQueryError("query_failed: get_customer_quote_request returned no row");
  }
  return parseCustomerQuoteRequest(row as Record<string, unknown>);
}

/**
 * Keyset-paginated (tenant_id, updated_at desc, id desc), never OFFSET,
 * hard-capped at 200 server-side. Deny-by-default: zero scope or an
 * out-of-scope accountId filter both return an empty array, never an error.
 */
export async function listCustomerQuoteRequests(
  client: CustomerQuoteRequestQueryClient,
  tenantId: string,
  actorAuthUserId: string,
  options?: CustomerQuoteRequestCursorOptions & { accountId?: string | null; status?: QuoteRequestStatus | null },
): Promise<CustomerQuoteRequest[]> {
  const { data, error } = await client.rpc("list_customer_quote_requests", {
    p_tenant_id: tenantId,
    p_actor_auth_user_id: actorAuthUserId,
    p_account_id: options?.accountId ?? null,
    p_status: options?.status ?? null,
    p_cursor_updated_at: options?.cursorUpdatedAt ?? null,
    p_cursor_id: options?.cursorId ?? null,
    p_limit: options?.limit ?? 50,
  });
  if (error) {
    throw new CustomerQuoteRequestQueryError(error.message);
  }
  return ((data as Record<string, unknown>[] | null) ?? []).map(parseCustomerQuoteRequest);
}

/**
 * Every real, active attachment metadata row for one quote request -- the
 * ONLY sanctioned customer-facing attachment read path (migration design
 * decision 4(b); app.authorize_file_access is deliberately not composed
 * from the portal). Deny-by-default: an out-of-scope or nonexistent request
 * returns an empty array, never an error.
 */
export async function listCustomerQuoteRequestFiles(client: CustomerQuoteRequestQueryClient, tenantId: string, requestId: string, actorAuthUserId: string): Promise<CustomerQuoteRequestFile[]> {
  const { data, error } = await client.rpc("list_customer_quote_request_files", {
    p_tenant_id: tenantId,
    p_request_id: requestId,
    p_actor_auth_user_id: actorAuthUserId,
  });
  if (error) {
    throw new CustomerQuoteRequestQueryError(error.message);
  }
  return ((data as Record<string, unknown>[] | null) ?? []).map(parseCustomerQuoteRequestFile);
}
