/**
 * Membership Tier read queries (CPL-317, CG-S13-CPL-019). Thin, typed
 * wrappers around every read RPC in supabase/migrations/20260801190000_
 * create_customer_portal_loyalty_membership_tier.sql -- both the
 * tenant-internal, staff-gated (LYL:View) admin reads and the customer-
 * facing (Layer 4) tier-card read. Mirrors server/queries/customer-portal-
 * loyalty-program.ts's own wrapper shape exactly (this repository's own
 * established convention: sibling server/queries/*.ts + server/mutations/
 * *.ts files, not one combined file).
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import {
  parseLoyaltyTierDefinition,
  parseLoyaltyAccountTierMovement,
  parseLoyaltyAccountTierState,
  parseCustomerPortalLoyaltyTierCard,
  type LoyaltyTierDefinition,
  type LoyaltyTierDefinitionStatus,
  type LoyaltyAccountTierMovement,
  type LoyaltyAccountTierState,
  type CustomerPortalLoyaltyTierCard,
} from "../contracts/customer-portal-loyalty-tier/customer-portal-loyalty-tier.ts";

export type LoyaltyTierQueryClient = Pick<SupabaseClient, "rpc">;

const KNOWN_QUERY_ERROR_CODES = [
  "record_not_found",
  "actor_identity_mismatch",
  "invalid_cursor",
  "insufficient_authority",
  "loyalty_tier_definition_not_found",
  "loyalty_account_not_found",
] as const;
type KnownQueryErrorCode = (typeof KNOWN_QUERY_ERROR_CODES)[number];
export type LoyaltyTierQueryErrorCode = KnownQueryErrorCode | "query_failed";

export class LoyaltyTierQueryError extends Error {
  readonly code: LoyaltyTierQueryErrorCode;

  constructor(message: string) {
    super(message);
    this.name = "LoyaltyTierQueryError";
    const prefix = message.split(":")[0]?.trim();
    this.code = (KNOWN_QUERY_ERROR_CODES as readonly string[]).includes(prefix ?? "") ? (prefix as KnownQueryErrorCode) : "query_failed";
  }
}

function firstRow(data: unknown): Record<string, unknown> | null {
  const row = Array.isArray(data) ? data[0] : data;
  return row && typeof row === "object" ? (row as Record<string, unknown>) : null;
}

export interface LoyaltyTierUpdatedAtCursorOptions {
  cursorUpdatedAt?: string | null;
  cursorId?: string | null;
  limit?: number;
}

export interface LoyaltyTierCreatedAtCursorOptions {
  cursorCreatedAt?: string | null;
  cursorId?: string | null;
  limit?: number;
}

// ===========================================================================
// Staff (tenant-internal, LYL:View)
// ===========================================================================

export async function getLoyaltyTierDefinition(client: LoyaltyTierQueryClient, tenantId: string, tierDefinitionId: string, actorAuthUserId: string): Promise<LoyaltyTierDefinition> {
  const { data, error } = await client.rpc("get_loyalty_tier_definition", { p_tenant_id: tenantId, p_tier_definition_id: tierDefinitionId, p_actor_auth_user_id: actorAuthUserId });
  if (error) throw new LoyaltyTierQueryError(error.message);
  const row = firstRow(data);
  if (!row) throw new LoyaltyTierQueryError("query_failed: get_loyalty_tier_definition returned no row");
  return parseLoyaltyTierDefinition(row);
}

export async function listLoyaltyTierDefinitions(
  client: LoyaltyTierQueryClient,
  tenantId: string,
  programId: string,
  actorAuthUserId: string,
  options?: LoyaltyTierUpdatedAtCursorOptions & { status?: LoyaltyTierDefinitionStatus | null },
): Promise<LoyaltyTierDefinition[]> {
  const { data, error } = await client.rpc("list_loyalty_tier_definitions", {
    p_tenant_id: tenantId,
    p_program_id: programId,
    p_actor_auth_user_id: actorAuthUserId,
    p_status: options?.status ?? null,
    p_cursor_updated_at: options?.cursorUpdatedAt ?? null,
    p_cursor_id: options?.cursorId ?? null,
    p_limit: options?.limit ?? 50,
  });
  if (error) throw new LoyaltyTierQueryError(error.message);
  return ((data as Record<string, unknown>[] | null) ?? []).map(parseLoyaltyTierDefinition);
}

export async function getLoyaltyAccountTierState(client: LoyaltyTierQueryClient, tenantId: string, loyaltyAccountId: string, actorAuthUserId: string): Promise<LoyaltyAccountTierState> {
  const { data, error } = await client.rpc("get_loyalty_account_tier_state", { p_tenant_id: tenantId, p_loyalty_account_id: loyaltyAccountId, p_actor_auth_user_id: actorAuthUserId });
  if (error) throw new LoyaltyTierQueryError(error.message);
  const row = firstRow(data);
  if (!row) throw new LoyaltyTierQueryError("query_failed: get_loyalty_account_tier_state returned no row");
  return parseLoyaltyAccountTierState(row);
}

export async function listLoyaltyAccountTierMovements(
  client: LoyaltyTierQueryClient,
  tenantId: string,
  actorAuthUserId: string,
  options?: LoyaltyTierCreatedAtCursorOptions & { loyaltyAccountId?: string | null },
): Promise<LoyaltyAccountTierMovement[]> {
  const { data, error } = await client.rpc("list_loyalty_account_tier_movements", {
    p_tenant_id: tenantId,
    p_actor_auth_user_id: actorAuthUserId,
    p_loyalty_account_id: options?.loyaltyAccountId ?? null,
    p_cursor_created_at: options?.cursorCreatedAt ?? null,
    p_cursor_id: options?.cursorId ?? null,
    p_limit: options?.limit ?? 50,
  });
  if (error) throw new LoyaltyTierQueryError(error.message);
  return ((data as Record<string, unknown>[] | null) ?? []).map(parseLoyaltyAccountTierMovement);
}

// ===========================================================================
// Customer-facing (Layer 4, ADR-0024 Part A)
// ===========================================================================

/** A customer's own active loyalty tier card(s) -- deny-by-default (empty, never an error, for an out-of-scope account or zero active enrollment). */
export async function listCustomerPortalLoyaltyTierCards(
  client: LoyaltyTierQueryClient,
  tenantId: string,
  actorAuthUserId: string,
  options?: { customerAccountId?: string | null; limit?: number },
): Promise<CustomerPortalLoyaltyTierCard[]> {
  const { data, error } = await client.rpc("list_customer_portal_loyalty_tier_cards", {
    p_tenant_id: tenantId,
    p_actor_auth_user_id: actorAuthUserId,
    p_customer_account_id: options?.customerAccountId ?? null,
    p_limit: options?.limit ?? 50,
  });
  if (error) throw new LoyaltyTierQueryError(error.message);
  return ((data as Record<string, unknown>[] | null) ?? []).map(parseCustomerPortalLoyaltyTierCard);
}
