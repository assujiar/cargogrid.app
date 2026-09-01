/**
 * Legal Identity Change Request read queries (ISS-2026-123 item 1). Thin, typed wrapper
 * around app.list_customer_portal_legal_identity_change_requests in supabase/migrations/
 * 20260901080000_create_customer_portal_legal_identity_change_requests.sql, mirroring
 * server/queries/customer-portal-profile.ts's own wrapper shape.
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import {
  parseCustomerLegalIdentityChangeRequest,
  type CustomerLegalIdentityChangeRequest,
  type CustomerLegalIdentityChangeRequestStatus,
} from "../contracts/customer-portal-legal-identity/customer-portal-legal-identity.ts";

export type CustomerPortalLegalIdentityQueryClient = Pick<SupabaseClient, "rpc">;

const KNOWN_QUERY_ERROR_CODES = ["actor_identity_mismatch", "invalid_cursor"] as const;
type KnownQueryErrorCode = (typeof KNOWN_QUERY_ERROR_CODES)[number];
export type CustomerPortalLegalIdentityQueryErrorCode = KnownQueryErrorCode | "query_failed";

export class CustomerPortalLegalIdentityQueryError extends Error {
  readonly code: CustomerPortalLegalIdentityQueryErrorCode;

  constructor(message: string) {
    super(message);
    this.name = "CustomerPortalLegalIdentityQueryError";
    const prefix = message.split(":")[0]?.trim();
    this.code = (KNOWN_QUERY_ERROR_CODES as readonly string[]).includes(prefix ?? "") ? (prefix as KnownQueryErrorCode) : "query_failed";
  }
}

export interface CustomerLegalIdentityChangeRequestCursorOptions {
  cursorUpdatedAt?: string | null;
  cursorId?: string | null;
  limit?: number;
}

/** Bounded (default 50, hard-capped 200 server-side), account-scoped, keyset-paginated (tenant_id, updated_at desc, id desc). */
export async function listCustomerPortalLegalIdentityChangeRequests(
  client: CustomerPortalLegalIdentityQueryClient,
  tenantId: string,
  actorAuthUserId: string,
  options?: CustomerLegalIdentityChangeRequestCursorOptions & { accountId?: string | null; status?: CustomerLegalIdentityChangeRequestStatus | null },
): Promise<CustomerLegalIdentityChangeRequest[]> {
  const { data, error } = await client.rpc("list_customer_portal_legal_identity_change_requests", {
    p_tenant_id: tenantId,
    p_actor_auth_user_id: actorAuthUserId,
    p_account_id: options?.accountId ?? null,
    p_status: options?.status ?? null,
    p_cursor_updated_at: options?.cursorUpdatedAt ?? null,
    p_cursor_id: options?.cursorId ?? null,
    p_limit: options?.limit ?? 50,
  });
  if (error) {
    throw new CustomerPortalLegalIdentityQueryError(error.message);
  }
  return ((data as Record<string, unknown>[] | null) ?? []).map(parseCustomerLegalIdentityChangeRequest);
}
