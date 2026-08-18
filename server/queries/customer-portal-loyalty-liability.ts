/**
 * Liability Reconciliation Analytics read queries (CPL-323, CG-S13-CPL-025).
 * Thin, typed wrappers around every read RPC in supabase/migrations/
 * 20260801250000_create_customer_portal_loyalty_liability_reconciliation_
 * analytics.sql -- reconciliation run/exception history (staff, LYL:View),
 * the staff-gated engagement-metrics read, and the ONE customer-facing
 * (Layer 4) consolidated loyalty summary read. Mirrors server/queries/
 * customer-portal-loyalty-expiry-fraud.ts's own wrapper shape exactly.
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import {
  parseLoyaltyLiabilityReconciliationRun,
  parseLoyaltyLiabilityReconciliationException,
  parseLoyaltyEngagementMetrics,
  parseCustomerPortalLoyaltySummary,
  GetLoyaltyEngagementMetricsInputSchema,
  GetCustomerPortalLoyaltySummaryInputSchema,
  type LoyaltyLiabilityReconciliationRun,
  type LoyaltyLiabilityReconciliationRunStatus,
  type LoyaltyLiabilityReconciliationException,
  type LoyaltyLiabilityReconciliationExceptionStatus,
  type LoyaltyEngagementMetrics,
  type GetLoyaltyEngagementMetricsInput,
  type CustomerPortalLoyaltySummary,
  type GetCustomerPortalLoyaltySummaryInput,
} from "../contracts/customer-portal-loyalty-liability/customer-portal-loyalty-liability.ts";

export type LoyaltyLiabilityQueryClient = Pick<SupabaseClient, "rpc">;

const KNOWN_QUERY_ERROR_CODES = ["insufficient_authority", "invalid_cursor", "actor_identity_mismatch", "loyalty_liability_reconciliation_run_not_found", "loyalty_account_not_found", "invalid_period"] as const;
type KnownQueryErrorCode = (typeof KNOWN_QUERY_ERROR_CODES)[number];
export type LoyaltyLiabilityQueryErrorCode = KnownQueryErrorCode | "query_failed";

export class LoyaltyLiabilityQueryError extends Error {
  readonly code: LoyaltyLiabilityQueryErrorCode;

  constructor(message: string) {
    super(message);
    this.name = "LoyaltyLiabilityQueryError";
    const prefix = message.split(":")[0]?.trim();
    this.code = (KNOWN_QUERY_ERROR_CODES as readonly string[]).includes(prefix ?? "") ? (prefix as KnownQueryErrorCode) : "query_failed";
  }
}

function firstRow(data: unknown): Record<string, unknown> | null {
  const row = Array.isArray(data) ? data[0] : data;
  return row && typeof row === "object" ? (row as Record<string, unknown>) : null;
}

export interface LoyaltyLiabilityUpdatedAtCursorOptions {
  cursorUpdatedAt?: string | null;
  cursorId?: string | null;
  limit?: number;
}

// ===========================================================================
// Reconciliation runs/exceptions (staff, LYL:View)
// ===========================================================================

export async function getLoyaltyLiabilityReconciliationRun(client: LoyaltyLiabilityQueryClient, tenantId: string, runId: string, actorAuthUserId: string): Promise<LoyaltyLiabilityReconciliationRun> {
  const { data, error } = await client.rpc("get_loyalty_liability_reconciliation_run", { p_tenant_id: tenantId, p_run_id: runId, p_actor_auth_user_id: actorAuthUserId });
  if (error) throw new LoyaltyLiabilityQueryError(error.message);
  const row = firstRow(data);
  if (!row) throw new LoyaltyLiabilityQueryError("query_failed: get_loyalty_liability_reconciliation_run returned no row");
  return parseLoyaltyLiabilityReconciliationRun(row);
}

export async function listLoyaltyLiabilityReconciliationRuns(
  client: LoyaltyLiabilityQueryClient,
  tenantId: string,
  actorAuthUserId: string,
  options?: LoyaltyLiabilityUpdatedAtCursorOptions & { currency?: string | null; status?: LoyaltyLiabilityReconciliationRunStatus | null },
): Promise<LoyaltyLiabilityReconciliationRun[]> {
  const { data, error } = await client.rpc("list_loyalty_liability_reconciliation_runs", {
    p_tenant_id: tenantId,
    p_actor_auth_user_id: actorAuthUserId,
    p_currency: options?.currency ?? null,
    p_status: options?.status ?? null,
    p_cursor_updated_at: options?.cursorUpdatedAt ?? null,
    p_cursor_id: options?.cursorId ?? null,
    p_limit: options?.limit ?? 50,
  });
  if (error) throw new LoyaltyLiabilityQueryError(error.message);
  return ((data as Record<string, unknown>[] | null) ?? []).map(parseLoyaltyLiabilityReconciliationRun);
}

export async function listLoyaltyLiabilityReconciliationExceptions(
  client: LoyaltyLiabilityQueryClient,
  tenantId: string,
  runId: string,
  actorAuthUserId: string,
  options?: LoyaltyLiabilityUpdatedAtCursorOptions & { status?: LoyaltyLiabilityReconciliationExceptionStatus | null },
): Promise<LoyaltyLiabilityReconciliationException[]> {
  const { data, error } = await client.rpc("list_loyalty_liability_reconciliation_exceptions", {
    p_tenant_id: tenantId,
    p_run_id: runId,
    p_actor_auth_user_id: actorAuthUserId,
    p_status: options?.status ?? null,
    p_cursor_updated_at: options?.cursorUpdatedAt ?? null,
    p_cursor_id: options?.cursorId ?? null,
    p_limit: options?.limit ?? 50,
  });
  if (error) throw new LoyaltyLiabilityQueryError(error.message);
  return ((data as Record<string, unknown>[] | null) ?? []).map(parseLoyaltyLiabilityReconciliationException);
}

// ===========================================================================
// Engagement metrics (staff, LYL:View -- Step-13-scope basic analytics only)
// ===========================================================================

export async function getLoyaltyEngagementMetrics(client: LoyaltyLiabilityQueryClient, input: GetLoyaltyEngagementMetricsInput): Promise<LoyaltyEngagementMetrics> {
  const v = GetLoyaltyEngagementMetricsInputSchema.parse(input);
  const { data, error } = await client.rpc("get_loyalty_engagement_metrics", {
    p_tenant_id: v.tenantId,
    p_period_start: v.periodStart,
    p_period_end: v.periodEnd,
    p_actor_auth_user_id: v.actorAuthUserId,
  });
  if (error) throw new LoyaltyLiabilityQueryError(error.message);
  const row = firstRow(data);
  if (!row) throw new LoyaltyLiabilityQueryError("query_failed: get_loyalty_engagement_metrics returned no row");
  return parseLoyaltyEngagementMetrics(row);
}

// ===========================================================================
// Customer-facing (Layer 4, ADR-0024 Part A)
// ===========================================================================

/** Composes (never duplicates) the already-existing per-domain customer reads into one consolidated row for the caller's own single loyalty account. */
export async function getCustomerPortalLoyaltySummary(client: LoyaltyLiabilityQueryClient, input: GetCustomerPortalLoyaltySummaryInput): Promise<CustomerPortalLoyaltySummary> {
  const v = GetCustomerPortalLoyaltySummaryInputSchema.parse(input);
  const { data, error } = await client.rpc("get_customer_portal_loyalty_summary", {
    p_tenant_id: v.tenantId,
    p_loyalty_account_id: v.loyaltyAccountId,
    p_actor_auth_user_id: v.actorAuthUserId,
  });
  if (error) throw new LoyaltyLiabilityQueryError(error.message);
  const row = firstRow(data);
  if (!row) throw new LoyaltyLiabilityQueryError("query_failed: get_customer_portal_loyalty_summary returned no row");
  return parseCustomerPortalLoyaltySummary(row);
}
