/**
 * Redemption Approval and Fulfillment read queries (CPL-321, CG-S13-CPL-023).
 * Thin, typed wrappers around every read RPC in supabase/migrations/
 * 20260801230000_create_customer_portal_loyalty_redemption_approval_
 * fulfillment.sql -- both the tenant-internal, staff-gated (LYL:View) admin
 * reads and the customer-facing (Layer 4) redemption status/history reads.
 * Mirrors server/queries/customer-portal-loyalty-rewards.ts's own wrapper
 * shape exactly.
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import {
  parseLoyaltyRedemption,
  parseCustomerPortalLoyaltyRedemption,
  type LoyaltyRedemption,
  type LoyaltyRedemptionStatus,
  type CustomerPortalLoyaltyRedemption,
} from "../contracts/customer-portal-loyalty-redemptions/customer-portal-loyalty-redemptions.ts";

export type LoyaltyRedemptionQueryClient = Pick<SupabaseClient, "rpc">;

const KNOWN_QUERY_ERROR_CODES = ["record_not_found", "actor_identity_mismatch", "invalid_cursor", "insufficient_authority", "loyalty_redemption_not_found"] as const;
type KnownQueryErrorCode = (typeof KNOWN_QUERY_ERROR_CODES)[number];
export type LoyaltyRedemptionQueryErrorCode = KnownQueryErrorCode | "query_failed";

export class LoyaltyRedemptionQueryError extends Error {
  readonly code: LoyaltyRedemptionQueryErrorCode;

  constructor(message: string) {
    super(message);
    this.name = "LoyaltyRedemptionQueryError";
    const prefix = message.split(":")[0]?.trim();
    this.code = (KNOWN_QUERY_ERROR_CODES as readonly string[]).includes(prefix ?? "") ? (prefix as KnownQueryErrorCode) : "query_failed";
  }
}

function firstRow(data: unknown): Record<string, unknown> | null {
  const row = Array.isArray(data) ? data[0] : data;
  return row && typeof row === "object" ? (row as Record<string, unknown>) : null;
}

export interface LoyaltyRedemptionUpdatedAtCursorOptions {
  cursorUpdatedAt?: string | null;
  cursorId?: string | null;
  limit?: number;
}

// ===========================================================================
// Staff (tenant-internal, LYL:View)
// ===========================================================================

export async function getLoyaltyRedemption(client: LoyaltyRedemptionQueryClient, tenantId: string, redemptionId: string, actorAuthUserId: string): Promise<LoyaltyRedemption> {
  const { data, error } = await client.rpc("get_loyalty_redemption", { p_tenant_id: tenantId, p_redemption_id: redemptionId, p_actor_auth_user_id: actorAuthUserId });
  if (error) throw new LoyaltyRedemptionQueryError(error.message);
  const row = firstRow(data);
  if (!row) throw new LoyaltyRedemptionQueryError("query_failed: get_loyalty_redemption returned no row");
  return parseLoyaltyRedemption(row);
}

export async function listLoyaltyRedemptions(
  client: LoyaltyRedemptionQueryClient,
  tenantId: string,
  actorAuthUserId: string,
  options?: LoyaltyRedemptionUpdatedAtCursorOptions & { status?: LoyaltyRedemptionStatus | null; loyaltyAccountId?: string | null },
): Promise<LoyaltyRedemption[]> {
  const { data, error } = await client.rpc("list_loyalty_redemptions", {
    p_tenant_id: tenantId,
    p_actor_auth_user_id: actorAuthUserId,
    p_status: options?.status ?? null,
    p_loyalty_account_id: options?.loyaltyAccountId ?? null,
    p_cursor_updated_at: options?.cursorUpdatedAt ?? null,
    p_cursor_id: options?.cursorId ?? null,
    p_limit: options?.limit ?? 50,
  });
  if (error) throw new LoyaltyRedemptionQueryError(error.message);
  return ((data as Record<string, unknown>[] | null) ?? []).map(parseLoyaltyRedemption);
}

// ===========================================================================
// Customer-facing (Layer 4, ADR-0024 Part A)
// ===========================================================================

/** The customer's own redemption history, optionally scoped to one loyalty account -- deny-by-default (empty, never an error, for an out-of-scope/empty resolved scope). */
export async function listCustomerPortalLoyaltyRedemptions(
  client: LoyaltyRedemptionQueryClient,
  tenantId: string,
  actorAuthUserId: string,
  options?: LoyaltyRedemptionUpdatedAtCursorOptions & { loyaltyAccountId?: string | null },
): Promise<CustomerPortalLoyaltyRedemption[]> {
  const { data, error } = await client.rpc("list_customer_portal_loyalty_redemptions", {
    p_tenant_id: tenantId,
    p_actor_auth_user_id: actorAuthUserId,
    p_loyalty_account_id: options?.loyaltyAccountId ?? null,
    p_cursor_updated_at: options?.cursorUpdatedAt ?? null,
    p_cursor_id: options?.cursorId ?? null,
    p_limit: options?.limit ?? 50,
  });
  if (error) throw new LoyaltyRedemptionQueryError(error.message);
  return ((data as Record<string, unknown>[] | null) ?? []).map(parseCustomerPortalLoyaltyRedemption);
}

/** A single redemption's own customer-safe detail -- anti-enumerating (loyalty_redemption_not_found for either a nonexistent redemption or an out-of-scope account). */
export async function getCustomerPortalLoyaltyRedemption(client: LoyaltyRedemptionQueryClient, tenantId: string, redemptionId: string, actorAuthUserId: string): Promise<CustomerPortalLoyaltyRedemption> {
  const { data, error } = await client.rpc("get_customer_portal_loyalty_redemption", {
    p_tenant_id: tenantId,
    p_redemption_id: redemptionId,
    p_actor_auth_user_id: actorAuthUserId,
  });
  if (error) throw new LoyaltyRedemptionQueryError(error.message);
  const row = firstRow(data);
  if (!row) throw new LoyaltyRedemptionQueryError("query_failed: get_customer_portal_loyalty_redemption returned no row");
  return parseCustomerPortalLoyaltyRedemption(row);
}
