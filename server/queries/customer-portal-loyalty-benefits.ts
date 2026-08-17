/**
 * Cashback, Discount and Voucher read queries (CPL-319, CG-S13-CPL-021).
 * Thin, typed wrappers around every read RPC in supabase/migrations/
 * 20260801210000_create_customer_portal_cashback_discount_voucher.sql --
 * both the tenant-internal, staff-gated (LYL:View) admin reads and the
 * customer-facing (Layer 4) benefit-wallet read. Mirrors server/queries/
 * customer-portal-loyalty-points.ts's own wrapper shape exactly (this
 * repository's own established convention: sibling server/queries/*.ts +
 * server/mutations/*.ts files, not one combined file).
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import {
  parseLoyaltyBenefitEntitlement,
  parseLoyaltyBenefitEntitlementEvent,
  parseCustomerPortalLoyaltyBenefitEntitlement,
  type LoyaltyBenefitEntitlement,
  type LoyaltyBenefitType,
  type LoyaltyBenefitStatus,
  type LoyaltyBenefitEntitlementEvent,
  type CustomerPortalLoyaltyBenefitEntitlement,
} from "../contracts/customer-portal-loyalty-benefits/customer-portal-loyalty-benefits.ts";

export type LoyaltyBenefitsQueryClient = Pick<SupabaseClient, "rpc">;

const KNOWN_QUERY_ERROR_CODES = ["insufficient_authority", "invalid_cursor", "loyalty_benefit_entitlement_not_found", "actor_identity_mismatch"] as const;
type KnownQueryErrorCode = (typeof KNOWN_QUERY_ERROR_CODES)[number];
export type LoyaltyBenefitsQueryErrorCode = KnownQueryErrorCode | "query_failed";

export class LoyaltyBenefitsQueryError extends Error {
  readonly code: LoyaltyBenefitsQueryErrorCode;

  constructor(message: string) {
    super(message);
    this.name = "LoyaltyBenefitsQueryError";
    const prefix = message.split(":")[0]?.trim();
    this.code = (KNOWN_QUERY_ERROR_CODES as readonly string[]).includes(prefix ?? "") ? (prefix as KnownQueryErrorCode) : "query_failed";
  }
}

function firstRow(data: unknown): Record<string, unknown> | null {
  const row = Array.isArray(data) ? data[0] : data;
  return row && typeof row === "object" ? (row as Record<string, unknown>) : null;
}

export interface LoyaltyBenefitUpdatedAtCursorOptions {
  cursorUpdatedAt?: string | null;
  cursorId?: string | null;
  limit?: number;
}

export interface LoyaltyBenefitCreatedAtCursorOptions {
  cursorCreatedAt?: string | null;
  cursorId?: string | null;
  limit?: number;
}

// ===========================================================================
// Staff (tenant-internal, LYL:View)
// ===========================================================================

export async function getLoyaltyBenefitEntitlement(client: LoyaltyBenefitsQueryClient, tenantId: string, entitlementId: string, actorAuthUserId: string): Promise<LoyaltyBenefitEntitlement> {
  const { data, error } = await client.rpc("get_loyalty_benefit_entitlement", { p_tenant_id: tenantId, p_entitlement_id: entitlementId, p_actor_auth_user_id: actorAuthUserId });
  if (error) throw new LoyaltyBenefitsQueryError(error.message);
  const row = firstRow(data);
  if (!row) throw new LoyaltyBenefitsQueryError("query_failed: get_loyalty_benefit_entitlement returned no row");
  return parseLoyaltyBenefitEntitlement(row);
}

export async function listLoyaltyBenefitEntitlements(
  client: LoyaltyBenefitsQueryClient,
  tenantId: string,
  actorAuthUserId: string,
  options?: LoyaltyBenefitUpdatedAtCursorOptions & { loyaltyAccountId?: string | null; benefitType?: LoyaltyBenefitType | null; status?: LoyaltyBenefitStatus | null },
): Promise<LoyaltyBenefitEntitlement[]> {
  const { data, error } = await client.rpc("list_loyalty_benefit_entitlements", {
    p_tenant_id: tenantId,
    p_actor_auth_user_id: actorAuthUserId,
    p_loyalty_account_id: options?.loyaltyAccountId ?? null,
    p_benefit_type: options?.benefitType ?? null,
    p_status: options?.status ?? null,
    p_cursor_updated_at: options?.cursorUpdatedAt ?? null,
    p_cursor_id: options?.cursorId ?? null,
    p_limit: options?.limit ?? 50,
  });
  if (error) throw new LoyaltyBenefitsQueryError(error.message);
  return ((data as Record<string, unknown>[] | null) ?? []).map(parseLoyaltyBenefitEntitlement);
}

export async function listLoyaltyBenefitEntitlementEvents(
  client: LoyaltyBenefitsQueryClient,
  tenantId: string,
  actorAuthUserId: string,
  options?: LoyaltyBenefitCreatedAtCursorOptions & { entitlementId?: string | null },
): Promise<LoyaltyBenefitEntitlementEvent[]> {
  const { data, error } = await client.rpc("list_loyalty_benefit_entitlement_events", {
    p_tenant_id: tenantId,
    p_actor_auth_user_id: actorAuthUserId,
    p_entitlement_id: options?.entitlementId ?? null,
    p_cursor_created_at: options?.cursorCreatedAt ?? null,
    p_cursor_id: options?.cursorId ?? null,
    p_limit: options?.limit ?? 50,
  });
  if (error) throw new LoyaltyBenefitsQueryError(error.message);
  return ((data as Record<string, unknown>[] | null) ?? []).map(parseLoyaltyBenefitEntitlementEvent);
}

// ===========================================================================
// Customer-facing (Layer 4, ADR-0024 Part A)
// ===========================================================================

/** A customer's own benefit wallet -- deny-by-default (empty, never an error, for an out-of-scope account). */
export async function listCustomerPortalLoyaltyBenefitEntitlements(
  client: LoyaltyBenefitsQueryClient,
  tenantId: string,
  actorAuthUserId: string,
  options?: LoyaltyBenefitUpdatedAtCursorOptions & { customerAccountId?: string | null; benefitType?: LoyaltyBenefitType | null },
): Promise<CustomerPortalLoyaltyBenefitEntitlement[]> {
  const { data, error } = await client.rpc("list_customer_portal_loyalty_benefit_entitlements", {
    p_tenant_id: tenantId,
    p_actor_auth_user_id: actorAuthUserId,
    p_customer_account_id: options?.customerAccountId ?? null,
    p_benefit_type: options?.benefitType ?? null,
    p_cursor_updated_at: options?.cursorUpdatedAt ?? null,
    p_cursor_id: options?.cursorId ?? null,
    p_limit: options?.limit ?? 50,
  });
  if (error) throw new LoyaltyBenefitsQueryError(error.message);
  return ((data as Record<string, unknown>[] | null) ?? []).map(parseCustomerPortalLoyaltyBenefitEntitlement);
}
