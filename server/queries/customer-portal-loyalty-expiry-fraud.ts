/**
 * Expiry and Fraud Prevention read queries (CPL-322, CG-S13-CPL-024). Thin,
 * typed wrappers around every read RPC in supabase/migrations/
 * 20260801240000_create_customer_portal_loyalty_expiry_fraud_prevention.sql
 * -- expiry-run history, the staff-gated (LYL:View) fraud review-case/
 * suppression workbench reads, and the ONE customer-facing (Layer 4)
 * account hold-status read. Mirrors server/queries/customer-portal-loyalty-
 * redemptions.ts's own wrapper shape exactly.
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import {
  parseLoyaltyExpiryRun,
  parseLoyaltyFraudReviewCase,
  parseLoyaltyFraudReviewSuppression,
  parseCustomerPortalLoyaltyAccountHoldStatus,
  type LoyaltyExpiryRun,
  type LoyaltyFraudReviewCase,
  type LoyaltyFraudReviewCaseStatus,
  type LoyaltyFraudReviewSuppression,
  type CustomerPortalLoyaltyAccountHoldStatus,
} from "../contracts/customer-portal-loyalty-expiry-fraud/customer-portal-loyalty-expiry-fraud.ts";

export type LoyaltyExpiryFraudQueryClient = Pick<SupabaseClient, "rpc">;

const KNOWN_QUERY_ERROR_CODES = ["insufficient_authority", "invalid_cursor", "actor_identity_mismatch", "loyalty_fraud_review_case_not_found"] as const;
type KnownQueryErrorCode = (typeof KNOWN_QUERY_ERROR_CODES)[number];
export type LoyaltyExpiryFraudQueryErrorCode = KnownQueryErrorCode | "query_failed";

export class LoyaltyExpiryFraudQueryError extends Error {
  readonly code: LoyaltyExpiryFraudQueryErrorCode;

  constructor(message: string) {
    super(message);
    this.name = "LoyaltyExpiryFraudQueryError";
    const prefix = message.split(":")[0]?.trim();
    this.code = (KNOWN_QUERY_ERROR_CODES as readonly string[]).includes(prefix ?? "") ? (prefix as KnownQueryErrorCode) : "query_failed";
  }
}

function firstRow(data: unknown): Record<string, unknown> | null {
  const row = Array.isArray(data) ? data[0] : data;
  return row && typeof row === "object" ? (row as Record<string, unknown>) : null;
}

export interface LoyaltyExpiryFraudUpdatedAtCursorOptions {
  cursorUpdatedAt?: string | null;
  cursorId?: string | null;
  limit?: number;
}

export interface LoyaltyExpiryFraudCreatedAtCursorOptions {
  cursorCreatedAt?: string | null;
  cursorId?: string | null;
  limit?: number;
}

// ===========================================================================
// Part A: expiry-run history (staff, LYL:View)
// ===========================================================================

export async function listLoyaltyExpiryRuns(client: LoyaltyExpiryFraudQueryClient, tenantId: string, actorAuthUserId: string, options?: LoyaltyExpiryFraudUpdatedAtCursorOptions): Promise<LoyaltyExpiryRun[]> {
  const { data, error } = await client.rpc("list_loyalty_expiry_runs", {
    p_tenant_id: tenantId,
    p_actor_auth_user_id: actorAuthUserId,
    p_cursor_updated_at: options?.cursorUpdatedAt ?? null,
    p_cursor_id: options?.cursorId ?? null,
    p_limit: options?.limit ?? 50,
  });
  if (error) throw new LoyaltyExpiryFraudQueryError(error.message);
  return ((data as Record<string, unknown>[] | null) ?? []).map(parseLoyaltyExpiryRun);
}

// ===========================================================================
// Part B: fraud review cases (staff, LYL:View)
// ===========================================================================

export async function getLoyaltyFraudReviewCase(client: LoyaltyExpiryFraudQueryClient, tenantId: string, caseId: string, actorAuthUserId: string): Promise<LoyaltyFraudReviewCase> {
  const { data, error } = await client.rpc("get_loyalty_fraud_review_case", { p_tenant_id: tenantId, p_case_id: caseId, p_actor_auth_user_id: actorAuthUserId });
  if (error) throw new LoyaltyExpiryFraudQueryError(error.message);
  const row = firstRow(data);
  if (!row) throw new LoyaltyExpiryFraudQueryError("query_failed: get_loyalty_fraud_review_case returned no row");
  return parseLoyaltyFraudReviewCase(row);
}

export async function listLoyaltyFraudReviewCases(
  client: LoyaltyExpiryFraudQueryClient,
  tenantId: string,
  actorAuthUserId: string,
  options?: LoyaltyExpiryFraudUpdatedAtCursorOptions & { loyaltyAccountId?: string | null; status?: LoyaltyFraudReviewCaseStatus | null },
): Promise<LoyaltyFraudReviewCase[]> {
  const { data, error } = await client.rpc("list_loyalty_fraud_review_cases", {
    p_tenant_id: tenantId,
    p_actor_auth_user_id: actorAuthUserId,
    p_loyalty_account_id: options?.loyaltyAccountId ?? null,
    p_status: options?.status ?? null,
    p_cursor_updated_at: options?.cursorUpdatedAt ?? null,
    p_cursor_id: options?.cursorId ?? null,
    p_limit: options?.limit ?? 50,
  });
  if (error) throw new LoyaltyExpiryFraudQueryError(error.message);
  return ((data as Record<string, unknown>[] | null) ?? []).map(parseLoyaltyFraudReviewCase);
}

// ===========================================================================
// Part B: suppressions (staff, LYL:View)
// ===========================================================================

export async function listLoyaltyFraudReviewSuppressions(
  client: LoyaltyExpiryFraudQueryClient,
  tenantId: string,
  actorAuthUserId: string,
  options?: LoyaltyExpiryFraudCreatedAtCursorOptions & { loyaltyAccountId?: string | null; activeOnly?: boolean },
): Promise<LoyaltyFraudReviewSuppression[]> {
  const { data, error } = await client.rpc("list_loyalty_fraud_review_suppressions", {
    p_tenant_id: tenantId,
    p_actor_auth_user_id: actorAuthUserId,
    p_loyalty_account_id: options?.loyaltyAccountId ?? null,
    p_active_only: options?.activeOnly ?? false,
    p_cursor_created_at: options?.cursorCreatedAt ?? null,
    p_cursor_id: options?.cursorId ?? null,
    p_limit: options?.limit ?? 50,
  });
  if (error) throw new LoyaltyExpiryFraudQueryError(error.message);
  return ((data as Record<string, unknown>[] | null) ?? []).map(parseLoyaltyFraudReviewSuppression);
}

// ===========================================================================
// Customer-facing (Layer 4, ADR-0024 Part A)
// ===========================================================================

/** Generic, customer-safe account hold status -- deny-by-default (empty, never an error, for an out-of-scope/empty resolved scope). Never risk_signal_type/risk_signal_detail/review_reason. */
export async function listCustomerPortalLoyaltyAccountHoldStatus(
  client: LoyaltyExpiryFraudQueryClient,
  tenantId: string,
  actorAuthUserId: string,
  options?: { customerAccountId?: string | null; limit?: number },
): Promise<CustomerPortalLoyaltyAccountHoldStatus[]> {
  const { data, error } = await client.rpc("list_customer_portal_loyalty_account_hold_status", {
    p_tenant_id: tenantId,
    p_actor_auth_user_id: actorAuthUserId,
    p_customer_account_id: options?.customerAccountId ?? null,
    p_limit: options?.limit ?? 50,
  });
  if (error) throw new LoyaltyExpiryFraudQueryError(error.message);
  return ((data as Record<string, unknown>[] | null) ?? []).map(parseCustomerPortalLoyaltyAccountHoldStatus);
}
