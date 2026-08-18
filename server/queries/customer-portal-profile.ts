/**
 * Customer Profile read queries (CPL-314, CG-S13-CPL-016). Thin, typed
 * wrappers around every read RPC in supabase/migrations/
 * 20260801150000_create_customer_portal_customer_profile.sql, mirroring
 * server/queries/customer-quote-request.ts's own wrapper shape exactly.
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import {
  parseCustomerProfileChangeRequest,
  parseCustomerPortalAccountProfile,
  parseCustomerPortalAccountContact,
  type CustomerProfileChangeRequest,
  type CustomerProfileChangeRequestStatus,
  type CustomerPortalAccountProfile,
  type CustomerPortalAccountContact,
} from "../contracts/customer-portal-profile/customer-portal-profile.ts";

export type CustomerPortalProfileQueryClient = Pick<SupabaseClient, "rpc">;

const KNOWN_QUERY_ERROR_CODES = ["record_not_found", "actor_identity_mismatch", "invalid_cursor"] as const;
type KnownQueryErrorCode = (typeof KNOWN_QUERY_ERROR_CODES)[number];
export type CustomerPortalProfileQueryErrorCode = KnownQueryErrorCode | "query_failed";

export class CustomerPortalProfileQueryError extends Error {
  readonly code: CustomerPortalProfileQueryErrorCode;

  constructor(message: string) {
    super(message);
    this.name = "CustomerPortalProfileQueryError";
    const prefix = message.split(":")[0]?.trim();
    this.code = (KNOWN_QUERY_ERROR_CODES as readonly string[]).includes(prefix ?? "") ? (prefix as KnownQueryErrorCode) : "query_failed";
  }
}

function firstRow(data: unknown): Record<string, unknown> | null {
  const row = Array.isArray(data) ? data[0] : data;
  return row && typeof row === "object" ? (row as Record<string, unknown>) : null;
}

export interface CustomerProfileChangeRequestCursorOptions {
  cursorUpdatedAt?: string | null;
  cursorId?: string | null;
  limit?: number;
}

/**
 * Current-state projection of one permitted account's profile
 * (trade_name/billing_address, plus read-only legal_name/tax_id/
 * customer_status) and a summary of its own open change requests. Throws
 * record_not_found (anti-enumerating) if missing, out of scope, or in a
 * different tenant -- the three causes are indistinguishable by design.
 */
export async function getCustomerPortalAccountProfile(client: CustomerPortalProfileQueryClient, tenantId: string, actorAuthUserId: string, accountId: string): Promise<CustomerPortalAccountProfile> {
  const { data, error } = await client.rpc("get_customer_portal_account_profile", {
    p_tenant_id: tenantId,
    p_actor_auth_user_id: actorAuthUserId,
    p_account_id: accountId,
  });
  if (error) {
    throw new CustomerPortalProfileQueryError(error.message);
  }
  const row = firstRow(data);
  if (!row) {
    throw new CustomerPortalProfileQueryError("query_failed: get_customer_portal_account_profile returned no row");
  }
  return parseCustomerPortalAccountProfile(row);
}

/**
 * Read-only projection of this account's own linked contacts
 * (app.contact_links, related_type='account'). No customer-initiated write
 * path exists for contacts (migration design decision 4). Deny-by-default:
 * an out-of-scope or nonexistent account returns an empty array, never an
 * error.
 */
export async function listCustomerPortalAccountContacts(client: CustomerPortalProfileQueryClient, tenantId: string, actorAuthUserId: string, accountId: string): Promise<CustomerPortalAccountContact[]> {
  const { data, error } = await client.rpc("list_customer_portal_account_contacts", {
    p_tenant_id: tenantId,
    p_actor_auth_user_id: actorAuthUserId,
    p_account_id: accountId,
  });
  if (error) {
    throw new CustomerPortalProfileQueryError(error.message);
  }
  return ((data as Record<string, unknown>[] | null) ?? []).map(parseCustomerPortalAccountContact);
}

/** Bounded (default 50, hard-capped 200 server-side), account-scoped, keyset-paginated (tenant_id, updated_at desc, id desc). */
export async function listCustomerPortalProfileChangeRequests(
  client: CustomerPortalProfileQueryClient,
  tenantId: string,
  actorAuthUserId: string,
  options?: CustomerProfileChangeRequestCursorOptions & { accountId?: string | null; status?: CustomerProfileChangeRequestStatus | null },
): Promise<CustomerProfileChangeRequest[]> {
  const { data, error } = await client.rpc("list_customer_portal_profile_change_requests", {
    p_tenant_id: tenantId,
    p_actor_auth_user_id: actorAuthUserId,
    p_account_id: options?.accountId ?? null,
    p_status: options?.status ?? null,
    p_cursor_updated_at: options?.cursorUpdatedAt ?? null,
    p_cursor_id: options?.cursorId ?? null,
    p_limit: options?.limit ?? 50,
  });
  if (error) {
    throw new CustomerPortalProfileQueryError(error.message);
  }
  return ((data as Record<string, unknown>[] | null) ?? []).map(parseCustomerProfileChangeRequest);
}
