/**
 * Loyalty Program and Earning read queries (CPL-316, CG-S13-CPL-018). Thin,
 * typed wrappers around every read RPC in supabase/migrations/
 * 20260801180000_create_customer_portal_loyalty_program_earning.sql --
 * both the tenant-internal, staff-gated (LYL:View) admin reads and the
 * customer-facing (Layer 4) reads of a customer's own loyalty account(s)
 * and earning history. Mirrors server/queries/customer-portal-invoice.ts's
 * own wrapper shape exactly.
 *
 * This repository's own established convention splits "queries+mutations"
 * into two sibling files (server/queries/*.ts, server/mutations/*.ts) --
 * see e.g. CPL-315's server/queries/customer-portal-user-management.ts --
 * rather than one combined file, followed here for consistency.
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import {
  parseLoyaltyProgram,
  parseLoyaltyProgramRuleVersion,
  parseLoyaltyAccount,
  parseLoyaltyEarningEvent,
  parseCustomerPortalLoyaltyAccount,
  parseCustomerPortalLoyaltyEarningEvent,
  type LoyaltyProgram,
  type LoyaltyProgramStatus,
  type LoyaltyProgramRuleVersion,
  type LoyaltyProgramRuleVersionStatus,
  type LoyaltyAccount,
  type LoyaltyAccountStatus,
  type LoyaltyEarningEvent,
  type CustomerPortalLoyaltyAccount,
  type CustomerPortalLoyaltyEarningEvent,
} from "../contracts/customer-portal-loyalty-program/customer-portal-loyalty-program.ts";

export type LoyaltyProgramQueryClient = Pick<SupabaseClient, "rpc">;

const KNOWN_QUERY_ERROR_CODES = [
  "record_not_found",
  "actor_identity_mismatch",
  "invalid_cursor",
  "insufficient_authority",
  "loyalty_program_not_found",
  "loyalty_program_rule_version_not_found",
  "loyalty_account_not_found",
  "loyalty_earning_event_not_found",
] as const;
type KnownQueryErrorCode = (typeof KNOWN_QUERY_ERROR_CODES)[number];
export type LoyaltyProgramQueryErrorCode = KnownQueryErrorCode | "query_failed";

export class LoyaltyProgramQueryError extends Error {
  readonly code: LoyaltyProgramQueryErrorCode;

  constructor(message: string) {
    super(message);
    this.name = "LoyaltyProgramQueryError";
    const prefix = message.split(":")[0]?.trim();
    this.code = (KNOWN_QUERY_ERROR_CODES as readonly string[]).includes(prefix ?? "") ? (prefix as KnownQueryErrorCode) : "query_failed";
  }
}

function firstRow(data: unknown): Record<string, unknown> | null {
  const row = Array.isArray(data) ? data[0] : data;
  return row && typeof row === "object" ? (row as Record<string, unknown>) : null;
}

export interface LoyaltyUpdatedAtCursorOptions {
  cursorUpdatedAt?: string | null;
  cursorId?: string | null;
  limit?: number;
}

export interface LoyaltyCreatedAtCursorOptions {
  cursorCreatedAt?: string | null;
  cursorId?: string | null;
  limit?: number;
}

// ===========================================================================
// Staff (tenant-internal, LYL:View)
// ===========================================================================

export async function getLoyaltyProgram(client: LoyaltyProgramQueryClient, tenantId: string, programId: string, actorAuthUserId: string): Promise<LoyaltyProgram> {
  const { data, error } = await client.rpc("get_loyalty_program", { p_tenant_id: tenantId, p_program_id: programId, p_actor_auth_user_id: actorAuthUserId });
  if (error) throw new LoyaltyProgramQueryError(error.message);
  const row = firstRow(data);
  if (!row) throw new LoyaltyProgramQueryError("query_failed: get_loyalty_program returned no row");
  return parseLoyaltyProgram(row);
}

export async function listLoyaltyPrograms(
  client: LoyaltyProgramQueryClient,
  tenantId: string,
  actorAuthUserId: string,
  options?: LoyaltyUpdatedAtCursorOptions & { status?: LoyaltyProgramStatus | null },
): Promise<LoyaltyProgram[]> {
  const { data, error } = await client.rpc("list_loyalty_programs", {
    p_tenant_id: tenantId,
    p_actor_auth_user_id: actorAuthUserId,
    p_status: options?.status ?? null,
    p_cursor_updated_at: options?.cursorUpdatedAt ?? null,
    p_cursor_id: options?.cursorId ?? null,
    p_limit: options?.limit ?? 50,
  });
  if (error) throw new LoyaltyProgramQueryError(error.message);
  return ((data as Record<string, unknown>[] | null) ?? []).map(parseLoyaltyProgram);
}

export async function getLoyaltyProgramRuleVersion(client: LoyaltyProgramQueryClient, tenantId: string, ruleVersionId: string, actorAuthUserId: string): Promise<LoyaltyProgramRuleVersion> {
  const { data, error } = await client.rpc("get_loyalty_program_rule_version", { p_tenant_id: tenantId, p_rule_version_id: ruleVersionId, p_actor_auth_user_id: actorAuthUserId });
  if (error) throw new LoyaltyProgramQueryError(error.message);
  const row = firstRow(data);
  if (!row) throw new LoyaltyProgramQueryError("query_failed: get_loyalty_program_rule_version returned no row");
  return parseLoyaltyProgramRuleVersion(row);
}

export async function listLoyaltyProgramRuleVersions(
  client: LoyaltyProgramQueryClient,
  tenantId: string,
  programId: string | null,
  actorAuthUserId: string,
  options?: LoyaltyUpdatedAtCursorOptions & { status?: LoyaltyProgramRuleVersionStatus | null },
): Promise<LoyaltyProgramRuleVersion[]> {
  const { data, error } = await client.rpc("list_loyalty_program_rule_versions", {
    p_tenant_id: tenantId,
    p_program_id: programId,
    p_actor_auth_user_id: actorAuthUserId,
    p_status: options?.status ?? null,
    p_cursor_updated_at: options?.cursorUpdatedAt ?? null,
    p_cursor_id: options?.cursorId ?? null,
    p_limit: options?.limit ?? 50,
  });
  if (error) throw new LoyaltyProgramQueryError(error.message);
  return ((data as Record<string, unknown>[] | null) ?? []).map(parseLoyaltyProgramRuleVersion);
}

export async function getLoyaltyAccount(client: LoyaltyProgramQueryClient, tenantId: string, accountId: string, actorAuthUserId: string): Promise<LoyaltyAccount> {
  const { data, error } = await client.rpc("get_loyalty_account", { p_tenant_id: tenantId, p_account_id: accountId, p_actor_auth_user_id: actorAuthUserId });
  if (error) throw new LoyaltyProgramQueryError(error.message);
  const row = firstRow(data);
  if (!row) throw new LoyaltyProgramQueryError("query_failed: get_loyalty_account returned no row");
  return parseLoyaltyAccount(row);
}

export async function listLoyaltyAccounts(
  client: LoyaltyProgramQueryClient,
  tenantId: string,
  actorAuthUserId: string,
  options?: LoyaltyUpdatedAtCursorOptions & { programId?: string | null; customerAccountId?: string | null; status?: LoyaltyAccountStatus | null },
): Promise<LoyaltyAccount[]> {
  const { data, error } = await client.rpc("list_loyalty_accounts", {
    p_tenant_id: tenantId,
    p_actor_auth_user_id: actorAuthUserId,
    p_program_id: options?.programId ?? null,
    p_customer_account_id: options?.customerAccountId ?? null,
    p_status: options?.status ?? null,
    p_cursor_updated_at: options?.cursorUpdatedAt ?? null,
    p_cursor_id: options?.cursorId ?? null,
    p_limit: options?.limit ?? 50,
  });
  if (error) throw new LoyaltyProgramQueryError(error.message);
  return ((data as Record<string, unknown>[] | null) ?? []).map(parseLoyaltyAccount);
}

export async function getLoyaltyEarningEvent(client: LoyaltyProgramQueryClient, tenantId: string, eventId: string, actorAuthUserId: string): Promise<LoyaltyEarningEvent> {
  const { data, error } = await client.rpc("get_loyalty_earning_event", { p_tenant_id: tenantId, p_event_id: eventId, p_actor_auth_user_id: actorAuthUserId });
  if (error) throw new LoyaltyProgramQueryError(error.message);
  const row = firstRow(data);
  if (!row) throw new LoyaltyProgramQueryError("query_failed: get_loyalty_earning_event returned no row");
  return parseLoyaltyEarningEvent(row);
}

export async function listLoyaltyEarningEvents(
  client: LoyaltyProgramQueryClient,
  tenantId: string,
  actorAuthUserId: string,
  options?: LoyaltyCreatedAtCursorOptions & { loyaltyAccountId?: string | null; programId?: string | null },
): Promise<LoyaltyEarningEvent[]> {
  const { data, error } = await client.rpc("list_loyalty_earning_events", {
    p_tenant_id: tenantId,
    p_actor_auth_user_id: actorAuthUserId,
    p_loyalty_account_id: options?.loyaltyAccountId ?? null,
    p_program_id: options?.programId ?? null,
    p_cursor_created_at: options?.cursorCreatedAt ?? null,
    p_cursor_id: options?.cursorId ?? null,
    p_limit: options?.limit ?? 50,
  });
  if (error) throw new LoyaltyProgramQueryError(error.message);
  return ((data as Record<string, unknown>[] | null) ?? []).map(parseLoyaltyEarningEvent);
}

// ===========================================================================
// Customer-facing (Layer 4, ADR-0024 Part A)
// ===========================================================================

/** A customer's own loyalty enrollment(s) -- any status, deny-by-default (empty, never an error, for an out-of-scope account or zero enrollment). */
export async function listCustomerPortalLoyaltyAccounts(
  client: LoyaltyProgramQueryClient,
  tenantId: string,
  actorAuthUserId: string,
  options?: LoyaltyUpdatedAtCursorOptions & { customerAccountId?: string | null },
): Promise<CustomerPortalLoyaltyAccount[]> {
  const { data, error } = await client.rpc("list_customer_portal_loyalty_accounts", {
    p_tenant_id: tenantId,
    p_actor_auth_user_id: actorAuthUserId,
    p_customer_account_id: options?.customerAccountId ?? null,
    p_cursor_updated_at: options?.cursorUpdatedAt ?? null,
    p_cursor_id: options?.cursorId ?? null,
    p_limit: options?.limit ?? 50,
  });
  if (error) throw new LoyaltyProgramQueryError(error.message);
  return ((data as Record<string, unknown>[] | null) ?? []).map(parseCustomerPortalLoyaltyAccount);
}

/** A customer's own earning history -- customer-safe projection (rule version's own human-readable earning_basis/rate, never internal config JSON). Deny-by-default. */
export async function listCustomerPortalLoyaltyEarningEvents(
  client: LoyaltyProgramQueryClient,
  tenantId: string,
  actorAuthUserId: string,
  options?: LoyaltyCreatedAtCursorOptions & { customerAccountId?: string | null },
): Promise<CustomerPortalLoyaltyEarningEvent[]> {
  const { data, error } = await client.rpc("list_customer_portal_loyalty_earning_events", {
    p_tenant_id: tenantId,
    p_actor_auth_user_id: actorAuthUserId,
    p_customer_account_id: options?.customerAccountId ?? null,
    p_cursor_created_at: options?.cursorCreatedAt ?? null,
    p_cursor_id: options?.cursorId ?? null,
    p_limit: options?.limit ?? 50,
  });
  if (error) throw new LoyaltyProgramQueryError(error.message);
  return ((data as Record<string, unknown>[] | null) ?? []).map(parseCustomerPortalLoyaltyEarningEvent);
}
