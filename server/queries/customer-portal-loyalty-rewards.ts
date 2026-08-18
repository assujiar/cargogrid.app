/**
 * Reward Catalogue read queries (CPL-320, CG-S13-CPL-022). Thin, typed
 * wrappers around every read RPC in supabase/migrations/20260801220000_
 * create_customer_portal_loyalty_reward_catalogue.sql -- both the
 * tenant-internal, staff-gated (LYL:View) admin reads and the customer-
 * facing (Layer 4) catalogue/detail reads. Mirrors server/queries/
 * customer-portal-loyalty-tier.ts's own wrapper shape exactly.
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import {
  parseLoyaltyReward,
  parseCustomerPortalLoyaltyReward,
  parseCustomerPortalLoyaltyRewardDetail,
  type LoyaltyReward,
  type LoyaltyRewardStatus,
  type CustomerPortalLoyaltyReward,
  type CustomerPortalLoyaltyRewardDetail,
} from "../contracts/customer-portal-loyalty-rewards/customer-portal-loyalty-rewards.ts";

export type LoyaltyRewardQueryClient = Pick<SupabaseClient, "rpc">;

const KNOWN_QUERY_ERROR_CODES = ["record_not_found", "actor_identity_mismatch", "invalid_cursor", "insufficient_authority", "loyalty_reward_not_found"] as const;
type KnownQueryErrorCode = (typeof KNOWN_QUERY_ERROR_CODES)[number];
export type LoyaltyRewardQueryErrorCode = KnownQueryErrorCode | "query_failed";

export class LoyaltyRewardQueryError extends Error {
  readonly code: LoyaltyRewardQueryErrorCode;

  constructor(message: string) {
    super(message);
    this.name = "LoyaltyRewardQueryError";
    const prefix = message.split(":")[0]?.trim();
    this.code = (KNOWN_QUERY_ERROR_CODES as readonly string[]).includes(prefix ?? "") ? (prefix as KnownQueryErrorCode) : "query_failed";
  }
}

function firstRow(data: unknown): Record<string, unknown> | null {
  const row = Array.isArray(data) ? data[0] : data;
  return row && typeof row === "object" ? (row as Record<string, unknown>) : null;
}

export interface LoyaltyRewardUpdatedAtCursorOptions {
  cursorUpdatedAt?: string | null;
  cursorId?: string | null;
  limit?: number;
}

// ===========================================================================
// Staff (tenant-internal, LYL:View)
// ===========================================================================

export async function getLoyaltyReward(client: LoyaltyRewardQueryClient, tenantId: string, rewardId: string, actorAuthUserId: string): Promise<LoyaltyReward> {
  const { data, error } = await client.rpc("get_loyalty_reward", { p_tenant_id: tenantId, p_reward_id: rewardId, p_actor_auth_user_id: actorAuthUserId });
  if (error) throw new LoyaltyRewardQueryError(error.message);
  const row = firstRow(data);
  if (!row) throw new LoyaltyRewardQueryError("query_failed: get_loyalty_reward returned no row");
  return parseLoyaltyReward(row);
}

export async function listLoyaltyRewards(
  client: LoyaltyRewardQueryClient,
  tenantId: string,
  actorAuthUserId: string,
  options?: LoyaltyRewardUpdatedAtCursorOptions & { programId?: string | null; status?: LoyaltyRewardStatus | null },
): Promise<LoyaltyReward[]> {
  const { data, error } = await client.rpc("list_loyalty_rewards", {
    p_tenant_id: tenantId,
    p_actor_auth_user_id: actorAuthUserId,
    p_program_id: options?.programId ?? null,
    p_status: options?.status ?? null,
    p_cursor_updated_at: options?.cursorUpdatedAt ?? null,
    p_cursor_id: options?.cursorId ?? null,
    p_limit: options?.limit ?? 50,
  });
  if (error) throw new LoyaltyRewardQueryError(error.message);
  return ((data as Record<string, unknown>[] | null) ?? []).map(parseLoyaltyReward);
}

// ===========================================================================
// Customer-facing (Layer 4, ADR-0024 Part A)
// ===========================================================================

/** The customer's own reward catalogue for ONE loyalty account -- deny-by-default (empty, never an error, for an out-of-scope/nonexistent/non-active account). */
export async function listCustomerPortalLoyaltyRewards(
  client: LoyaltyRewardQueryClient,
  tenantId: string,
  loyaltyAccountId: string,
  actorAuthUserId: string,
  options?: LoyaltyRewardUpdatedAtCursorOptions,
): Promise<CustomerPortalLoyaltyReward[]> {
  const { data, error } = await client.rpc("list_customer_portal_loyalty_rewards", {
    p_tenant_id: tenantId,
    p_loyalty_account_id: loyaltyAccountId,
    p_actor_auth_user_id: actorAuthUserId,
    p_cursor_updated_at: options?.cursorUpdatedAt ?? null,
    p_cursor_id: options?.cursorId ?? null,
    p_limit: options?.limit ?? 50,
  });
  if (error) throw new LoyaltyRewardQueryError(error.message);
  return ((data as Record<string, unknown>[] | null) ?? []).map(parseCustomerPortalLoyaltyReward);
}

/** A single reward's own customer-safe detail, including a malware-scan-gated terms file reference -- anti-enumerating (loyalty_reward_not_found for any of: nonexistent, out-of-scope account, cross-program, not-yet-effective/expired/archived/superseded/draft). */
export async function getCustomerPortalLoyaltyReward(client: LoyaltyRewardQueryClient, tenantId: string, rewardId: string, loyaltyAccountId: string, actorAuthUserId: string): Promise<CustomerPortalLoyaltyRewardDetail> {
  const { data, error } = await client.rpc("get_customer_portal_loyalty_reward", {
    p_tenant_id: tenantId,
    p_reward_id: rewardId,
    p_loyalty_account_id: loyaltyAccountId,
    p_actor_auth_user_id: actorAuthUserId,
  });
  if (error) throw new LoyaltyRewardQueryError(error.message);
  const row = firstRow(data);
  if (!row) throw new LoyaltyRewardQueryError("query_failed: get_customer_portal_loyalty_reward returned no row");
  return parseCustomerPortalLoyaltyRewardDetail(row);
}
