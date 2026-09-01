/**
 * Contact Change Request read queries (ISS-2026-123 item 2). Thin, typed wrapper around
 * app.list_customer_portal_contact_change_requests in supabase/migrations/
 * 20260901090000_create_customer_portal_contact_change_requests.sql, mirroring
 * server/queries/customer-portal-profile.ts's own wrapper shape.
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import {
  parseCustomerContactChangeRequest,
  type CustomerContactChangeRequest,
  type CustomerContactChangeRequestStatus,
} from "../contracts/customer-portal-contact-change/customer-portal-contact-change.ts";

export type CustomerPortalContactChangeQueryClient = Pick<SupabaseClient, "rpc">;

const KNOWN_QUERY_ERROR_CODES = ["actor_identity_mismatch", "invalid_cursor"] as const;
type KnownQueryErrorCode = (typeof KNOWN_QUERY_ERROR_CODES)[number];
export type CustomerPortalContactChangeQueryErrorCode = KnownQueryErrorCode | "query_failed";

export class CustomerPortalContactChangeQueryError extends Error {
  readonly code: CustomerPortalContactChangeQueryErrorCode;

  constructor(message: string) {
    super(message);
    this.name = "CustomerPortalContactChangeQueryError";
    const prefix = message.split(":")[0]?.trim();
    this.code = (KNOWN_QUERY_ERROR_CODES as readonly string[]).includes(prefix ?? "") ? (prefix as KnownQueryErrorCode) : "query_failed";
  }
}

export interface CustomerContactChangeRequestCursorOptions {
  cursorUpdatedAt?: string | null;
  cursorId?: string | null;
  limit?: number;
}

/** Bounded (default 50, hard-capped 200 server-side), account-scoped, keyset-paginated (tenant_id, updated_at desc, id desc). */
export async function listCustomerPortalContactChangeRequests(
  client: CustomerPortalContactChangeQueryClient,
  tenantId: string,
  actorAuthUserId: string,
  options?: CustomerContactChangeRequestCursorOptions & { accountId?: string | null; status?: CustomerContactChangeRequestStatus | null },
): Promise<CustomerContactChangeRequest[]> {
  const { data, error } = await client.rpc("list_customer_portal_contact_change_requests", {
    p_tenant_id: tenantId,
    p_actor_auth_user_id: actorAuthUserId,
    p_account_id: options?.accountId ?? null,
    p_status: options?.status ?? null,
    p_cursor_updated_at: options?.cursorUpdatedAt ?? null,
    p_cursor_id: options?.cursorId ?? null,
    p_limit: options?.limit ?? 50,
  });
  if (error) {
    throw new CustomerPortalContactChangeQueryError(error.message);
  }
  return ((data as Record<string, unknown>[] | null) ?? []).map(parseCustomerContactChangeRequest);
}
