/**
 * Customer Portal Scope read queries (CPL-300, CG-S13-CPL-002). Thin, typed
 * wrappers around every read RPC in supabase/migrations/
 * 20260801010000_create_customer_portal_account_scope.sql, mirroring
 * server/queries/customer-inventory-access.ts's own wrapper shape exactly.
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import {
  parseCustomerPortalScopeContextRow,
  parseCustomerPortalAccountMembership,
  type CustomerPortalScopeContextRow,
  type CustomerPortalAccountMembership,
} from "../contracts/customer-portal-scope/customer-portal-scope.ts";

export type CustomerPortalScopeQueryClient = Pick<SupabaseClient, "rpc">;

export class CustomerPortalScopeQueryError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "CustomerPortalScopeQueryError";
  }
}

/** Common cursor options app.list_customer_portal_account_memberships accepts -- pass the previous page's last row's own updatedAt/id to advance; omit both for the first page. */
export interface CustomerPortalMembershipCursorOptions {
  cursorUpdatedAt?: string | null;
  cursorId?: string | null;
  limit?: number;
}

/**
 * The widened scope resolver -- every app.accounts id this identity may act
 * within in this tenant. Always a real, possibly-empty array, never null.
 */
export async function resolveCustomerAccountScope(client: CustomerPortalScopeQueryClient, authUserId: string, tenantId: string): Promise<string[]> {
  const { data, error } = await client.rpc("resolve_customer_account_scope", {
    p_auth_user_id: authUserId,
    p_tenant_id: tenantId,
  });
  if (error) {
    throw new CustomerPortalScopeQueryError(error.message);
  }
  return (data as string[] | null) ?? [];
}

/**
 * The shared scope-preview/session-context adapter -- every ACTIVE account
 * this customer_user may act within, with role/is_primary. Returns an empty
 * array (never throws) for a caller who does not genuinely hold an active
 * customer_user-layer principal in this tenant (deny-by-default,
 * anti-enumeration -- the RPC itself re-verifies this independently).
 */
export async function getCustomerPortalScopeContext(client: CustomerPortalScopeQueryClient, authUserId: string, tenantId: string): Promise<CustomerPortalScopeContextRow[]> {
  const { data, error } = await client.rpc("get_customer_portal_scope_context", {
    p_auth_user_id: authUserId,
    p_tenant_id: tenantId,
  });
  if (error) {
    throw new CustomerPortalScopeQueryError(error.message);
  }
  return ((data as Record<string, unknown>[] | null) ?? []).map(parseCustomerPortalScopeContextRow);
}

/**
 * "Manage my account's users" list -- account_admin-only (self-checked
 * server-side against p_account_id); bounded (default 50, hard-capped 200),
 * keyset-paginated. A non-admin caller gets an empty result, never an error.
 */
export async function listCustomerPortalAccountMemberships(
  client: CustomerPortalScopeQueryClient,
  tenantId: string,
  accountId: string,
  actorAuthUserId: string,
  options?: CustomerPortalMembershipCursorOptions,
): Promise<CustomerPortalAccountMembership[]> {
  const { data, error } = await client.rpc("list_customer_portal_account_memberships", {
    p_tenant_id: tenantId,
    p_account_id: accountId,
    p_actor_auth_user_id: actorAuthUserId,
    p_cursor_updated_at: options?.cursorUpdatedAt ?? null,
    p_cursor_id: options?.cursorId ?? null,
    p_limit: options?.limit ?? 50,
  });
  if (error) {
    throw new CustomerPortalScopeQueryError(error.message);
  }
  return ((data as Record<string, unknown>[] | null) ?? []).map(parseCustomerPortalAccountMembership);
}
