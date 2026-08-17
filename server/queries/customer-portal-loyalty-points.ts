/**
 * Points Ledger read queries (CPL-318, CG-S13-CPL-020). Thin, typed wrappers
 * around every read RPC in supabase/migrations/20260801200000_create_
 * customer_portal_loyalty_points_ledger.sql -- both the tenant-internal,
 * staff-gated (LYL:View) admin reads and the customer-facing (Layer 4)
 * balance/ledger-history/expiry-schedule reads. Mirrors server/queries/
 * customer-portal-loyalty-tier.ts's own wrapper shape exactly (this
 * repository's own established convention: sibling server/queries/*.ts +
 * server/mutations/*.ts files, not one combined file).
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import {
  parseLoyaltyPointLot,
  parseLoyaltyPointLedgerEntry,
  parseLoyaltyPointBalance,
  parseLoyaltyPointAdjustmentRequest,
  parseCustomerPortalLoyaltyPointBalance,
  parseCustomerPortalLoyaltyPointLedgerEntry,
  parseCustomerPortalLoyaltyPointExpiryScheduleEntry,
  type LoyaltyPointLot,
  type LoyaltyPointLotStatus,
  type LoyaltyPointLedgerEntry,
  type LoyaltyPointLedgerEventType,
  type LoyaltyPointBalance,
  type LoyaltyPointAdjustmentRequest,
  type LoyaltyPointAdjustmentStatus,
  type CustomerPortalLoyaltyPointBalance,
  type CustomerPortalLoyaltyPointLedgerEntry,
  type CustomerPortalLoyaltyPointExpiryScheduleEntry,
} from "../contracts/customer-portal-loyalty-points/customer-portal-loyalty-points.ts";

export type LoyaltyPointsQueryClient = Pick<SupabaseClient, "rpc">;

const KNOWN_QUERY_ERROR_CODES = [
  "insufficient_authority",
  "invalid_cursor",
  "loyalty_point_balance_not_found",
  "loyalty_point_lot_not_found",
  "loyalty_point_adjustment_request_not_found",
  "actor_identity_mismatch",
] as const;
type KnownQueryErrorCode = (typeof KNOWN_QUERY_ERROR_CODES)[number];
export type LoyaltyPointsQueryErrorCode = KnownQueryErrorCode | "query_failed";

export class LoyaltyPointsQueryError extends Error {
  readonly code: LoyaltyPointsQueryErrorCode;

  constructor(message: string) {
    super(message);
    this.name = "LoyaltyPointsQueryError";
    const prefix = message.split(":")[0]?.trim();
    this.code = (KNOWN_QUERY_ERROR_CODES as readonly string[]).includes(prefix ?? "") ? (prefix as KnownQueryErrorCode) : "query_failed";
  }
}

function firstRow(data: unknown): Record<string, unknown> | null {
  const row = Array.isArray(data) ? data[0] : data;
  return row && typeof row === "object" ? (row as Record<string, unknown>) : null;
}

export interface LoyaltyPointUpdatedAtCursorOptions {
  cursorUpdatedAt?: string | null;
  cursorId?: string | null;
  limit?: number;
}

export interface LoyaltyPointCreatedAtCursorOptions {
  cursorCreatedAt?: string | null;
  cursorId?: string | null;
  limit?: number;
}

export interface LoyaltyPointExpiresAtCursorOptions {
  cursorExpiresAt?: string | null;
  cursorId?: string | null;
  limit?: number;
}

// ===========================================================================
// Staff (tenant-internal, LYL:View)
// ===========================================================================

export async function getLoyaltyPointBalance(client: LoyaltyPointsQueryClient, tenantId: string, loyaltyAccountId: string, actorAuthUserId: string): Promise<LoyaltyPointBalance> {
  const { data, error } = await client.rpc("get_loyalty_point_balance", { p_tenant_id: tenantId, p_loyalty_account_id: loyaltyAccountId, p_actor_auth_user_id: actorAuthUserId });
  if (error) throw new LoyaltyPointsQueryError(error.message);
  const row = firstRow(data);
  if (!row) throw new LoyaltyPointsQueryError("query_failed: get_loyalty_point_balance returned no row");
  return parseLoyaltyPointBalance(row);
}

export async function listLoyaltyPointBalances(client: LoyaltyPointsQueryClient, tenantId: string, actorAuthUserId: string, options?: LoyaltyPointUpdatedAtCursorOptions): Promise<LoyaltyPointBalance[]> {
  const { data, error } = await client.rpc("list_loyalty_point_balances", {
    p_tenant_id: tenantId,
    p_actor_auth_user_id: actorAuthUserId,
    p_cursor_updated_at: options?.cursorUpdatedAt ?? null,
    p_cursor_id: options?.cursorId ?? null,
    p_limit: options?.limit ?? 50,
  });
  if (error) throw new LoyaltyPointsQueryError(error.message);
  return ((data as Record<string, unknown>[] | null) ?? []).map(parseLoyaltyPointBalance);
}

export async function getLoyaltyPointLot(client: LoyaltyPointsQueryClient, tenantId: string, lotId: string, actorAuthUserId: string): Promise<LoyaltyPointLot> {
  const { data, error } = await client.rpc("get_loyalty_point_lot", { p_tenant_id: tenantId, p_lot_id: lotId, p_actor_auth_user_id: actorAuthUserId });
  if (error) throw new LoyaltyPointsQueryError(error.message);
  const row = firstRow(data);
  if (!row) throw new LoyaltyPointsQueryError("query_failed: get_loyalty_point_lot returned no row");
  return parseLoyaltyPointLot(row);
}

export async function listLoyaltyPointLots(
  client: LoyaltyPointsQueryClient,
  tenantId: string,
  actorAuthUserId: string,
  options?: LoyaltyPointUpdatedAtCursorOptions & { loyaltyAccountId?: string | null; status?: LoyaltyPointLotStatus | null },
): Promise<LoyaltyPointLot[]> {
  const { data, error } = await client.rpc("list_loyalty_point_lots", {
    p_tenant_id: tenantId,
    p_actor_auth_user_id: actorAuthUserId,
    p_loyalty_account_id: options?.loyaltyAccountId ?? null,
    p_status: options?.status ?? null,
    p_cursor_updated_at: options?.cursorUpdatedAt ?? null,
    p_cursor_id: options?.cursorId ?? null,
    p_limit: options?.limit ?? 50,
  });
  if (error) throw new LoyaltyPointsQueryError(error.message);
  return ((data as Record<string, unknown>[] | null) ?? []).map(parseLoyaltyPointLot);
}

export async function listLoyaltyPointLedgerEntries(
  client: LoyaltyPointsQueryClient,
  tenantId: string,
  actorAuthUserId: string,
  options?: LoyaltyPointCreatedAtCursorOptions & { loyaltyAccountId?: string | null; eventType?: LoyaltyPointLedgerEventType | null },
): Promise<LoyaltyPointLedgerEntry[]> {
  const { data, error } = await client.rpc("list_loyalty_point_ledger_entries", {
    p_tenant_id: tenantId,
    p_actor_auth_user_id: actorAuthUserId,
    p_loyalty_account_id: options?.loyaltyAccountId ?? null,
    p_event_type: options?.eventType ?? null,
    p_cursor_created_at: options?.cursorCreatedAt ?? null,
    p_cursor_id: options?.cursorId ?? null,
    p_limit: options?.limit ?? 50,
  });
  if (error) throw new LoyaltyPointsQueryError(error.message);
  return ((data as Record<string, unknown>[] | null) ?? []).map(parseLoyaltyPointLedgerEntry);
}

export async function getLoyaltyPointAdjustmentRequest(client: LoyaltyPointsQueryClient, tenantId: string, adjustmentId: string, actorAuthUserId: string): Promise<LoyaltyPointAdjustmentRequest> {
  const { data, error } = await client.rpc("get_loyalty_point_adjustment_request", { p_tenant_id: tenantId, p_adjustment_id: adjustmentId, p_actor_auth_user_id: actorAuthUserId });
  if (error) throw new LoyaltyPointsQueryError(error.message);
  const row = firstRow(data);
  if (!row) throw new LoyaltyPointsQueryError("query_failed: get_loyalty_point_adjustment_request returned no row");
  return parseLoyaltyPointAdjustmentRequest(row);
}

export async function listLoyaltyPointAdjustmentRequests(
  client: LoyaltyPointsQueryClient,
  tenantId: string,
  actorAuthUserId: string,
  options?: LoyaltyPointUpdatedAtCursorOptions & { loyaltyAccountId?: string | null; status?: LoyaltyPointAdjustmentStatus | null },
): Promise<LoyaltyPointAdjustmentRequest[]> {
  const { data, error } = await client.rpc("list_loyalty_point_adjustment_requests", {
    p_tenant_id: tenantId,
    p_actor_auth_user_id: actorAuthUserId,
    p_loyalty_account_id: options?.loyaltyAccountId ?? null,
    p_status: options?.status ?? null,
    p_cursor_updated_at: options?.cursorUpdatedAt ?? null,
    p_cursor_id: options?.cursorId ?? null,
    p_limit: options?.limit ?? 50,
  });
  if (error) throw new LoyaltyPointsQueryError(error.message);
  return ((data as Record<string, unknown>[] | null) ?? []).map(parseLoyaltyPointAdjustmentRequest);
}

// ===========================================================================
// Customer-facing (Layer 4, ADR-0024 Part A)
// ===========================================================================

/** A customer's own point balance(s) -- deny-by-default (empty, never an error, for an out-of-scope account or zero point activity). */
export async function listCustomerPortalLoyaltyPointBalances(
  client: LoyaltyPointsQueryClient,
  tenantId: string,
  actorAuthUserId: string,
  options?: LoyaltyPointUpdatedAtCursorOptions & { customerAccountId?: string | null },
): Promise<CustomerPortalLoyaltyPointBalance[]> {
  const { data, error } = await client.rpc("list_customer_portal_loyalty_point_balances", {
    p_tenant_id: tenantId,
    p_actor_auth_user_id: actorAuthUserId,
    p_customer_account_id: options?.customerAccountId ?? null,
    p_cursor_updated_at: options?.cursorUpdatedAt ?? null,
    p_cursor_id: options?.cursorId ?? null,
    p_limit: options?.limit ?? 50,
  });
  if (error) throw new LoyaltyPointsQueryError(error.message);
  return ((data as Record<string, unknown>[] | null) ?? []).map(parseCustomerPortalLoyaltyPointBalance);
}

/** Customer-safe ledger history -- never carries the internal reason field (structural, see contract's own comment). */
export async function listCustomerPortalLoyaltyPointLedgerEntries(
  client: LoyaltyPointsQueryClient,
  tenantId: string,
  actorAuthUserId: string,
  options?: LoyaltyPointCreatedAtCursorOptions & { customerAccountId?: string | null },
): Promise<CustomerPortalLoyaltyPointLedgerEntry[]> {
  const { data, error } = await client.rpc("list_customer_portal_loyalty_point_ledger_entries", {
    p_tenant_id: tenantId,
    p_actor_auth_user_id: actorAuthUserId,
    p_customer_account_id: options?.customerAccountId ?? null,
    p_cursor_created_at: options?.cursorCreatedAt ?? null,
    p_cursor_id: options?.cursorId ?? null,
    p_limit: options?.limit ?? 50,
  });
  if (error) throw new LoyaltyPointsQueryError(error.message);
  return ((data as Record<string, unknown>[] | null) ?? []).map(parseCustomerPortalLoyaltyPointLedgerEntry);
}

/** Soonest-expiring-first (ascending) -- the customer's own currently-active, unexhausted lots. */
export async function listCustomerPortalLoyaltyPointExpirySchedule(
  client: LoyaltyPointsQueryClient,
  tenantId: string,
  actorAuthUserId: string,
  options?: LoyaltyPointExpiresAtCursorOptions & { customerAccountId?: string | null },
): Promise<CustomerPortalLoyaltyPointExpiryScheduleEntry[]> {
  const { data, error } = await client.rpc("list_customer_portal_loyalty_point_expiry_schedule", {
    p_tenant_id: tenantId,
    p_actor_auth_user_id: actorAuthUserId,
    p_customer_account_id: options?.customerAccountId ?? null,
    p_cursor_expires_at: options?.cursorExpiresAt ?? null,
    p_cursor_id: options?.cursorId ?? null,
    p_limit: options?.limit ?? 50,
  });
  if (error) throw new LoyaltyPointsQueryError(error.message);
  return ((data as Record<string, unknown>[] | null) ?? []).map(parseCustomerPortalLoyaltyPointExpiryScheduleEntry);
}
