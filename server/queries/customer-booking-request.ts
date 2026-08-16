/**
 * Customer Booking Request read queries (CPL-303, CG-S13-CPL-005). Thin,
 * typed wrappers around every read RPC in supabase/migrations/
 * 20260801040000_create_customer_portal_booking_requests.sql, mirroring
 * server/queries/customer-quote-request.ts's own wrapper shape exactly.
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import { parseCustomerBookingRequest, type CustomerBookingRequest, type BookingRequestStatus } from "../contracts/customer-booking-request/customer-booking-request.ts";

export type CustomerBookingRequestQueryClient = Pick<SupabaseClient, "rpc">;

const KNOWN_QUERY_ERROR_CODES = ["record_not_found", "actor_identity_mismatch", "invalid_cursor"] as const;
type KnownQueryErrorCode = (typeof KNOWN_QUERY_ERROR_CODES)[number];
export type CustomerBookingRequestQueryErrorCode = KnownQueryErrorCode | "query_failed";

export class CustomerBookingRequestQueryError extends Error {
  readonly code: CustomerBookingRequestQueryErrorCode;

  constructor(message: string) {
    super(message);
    this.name = "CustomerBookingRequestQueryError";
    const prefix = message.split(":")[0]?.trim();
    this.code = (KNOWN_QUERY_ERROR_CODES as readonly string[]).includes(prefix ?? "") ? (prefix as KnownQueryErrorCode) : "query_failed";
  }
}

export interface CustomerBookingRequestCursorOptions {
  cursorUpdatedAt?: string | null;
  cursorId?: string | null;
  limit?: number;
}

/**
 * Single permitted booking request by id. Throws record_not_found (anti-
 * enumerating, errcode no_data_found) whether the id genuinely does not
 * exist, belongs to another tenant, or exists but its account is outside
 * this identity's resolved scope -- the caller must not try to distinguish
 * the three from the thrown error's own content (mirrors app.get_customer_
 * quote_request's own documented convention).
 */
export async function getCustomerBookingRequest(client: CustomerBookingRequestQueryClient, tenantId: string, bookingRequestId: string, actorAuthUserId: string): Promise<CustomerBookingRequest> {
  const { data, error } = await client.rpc("get_customer_booking_request", {
    p_tenant_id: tenantId,
    p_booking_request_id: bookingRequestId,
    p_actor_auth_user_id: actorAuthUserId,
  });
  if (error) {
    throw new CustomerBookingRequestQueryError(error.message);
  }
  const row = Array.isArray(data) ? data[0] : data;
  if (!row || typeof row !== "object") {
    throw new CustomerBookingRequestQueryError("query_failed: get_customer_booking_request returned no row");
  }
  return parseCustomerBookingRequest(row as Record<string, unknown>);
}

/**
 * Keyset-paginated (tenant_id, updated_at desc, id desc), never OFFSET,
 * hard-capped at 200 server-side. Deny-by-default: zero scope or an
 * out-of-scope accountId filter both return an empty array, never an error.
 */
export async function listCustomerBookingRequests(
  client: CustomerBookingRequestQueryClient,
  tenantId: string,
  actorAuthUserId: string,
  options?: CustomerBookingRequestCursorOptions & { accountId?: string | null; status?: BookingRequestStatus | null },
): Promise<CustomerBookingRequest[]> {
  const { data, error } = await client.rpc("list_customer_booking_requests", {
    p_tenant_id: tenantId,
    p_actor_auth_user_id: actorAuthUserId,
    p_account_id: options?.accountId ?? null,
    p_status: options?.status ?? null,
    p_cursor_updated_at: options?.cursorUpdatedAt ?? null,
    p_cursor_id: options?.cursorId ?? null,
    p_limit: options?.limit ?? 50,
  });
  if (error) {
    throw new CustomerBookingRequestQueryError(error.message);
  }
  return ((data as Record<string, unknown>[] | null) ?? []).map(parseCustomerBookingRequest);
}
