/**
 * Customer Portal User Management read queries (CPL-315, CG-S13-CPL-017).
 * Thin, typed wrappers around every read RPC in supabase/migrations/
 * 20260801170000_create_customer_portal_user_management.sql, mirroring
 * server/queries/customer-portal-scope.ts's own wrapper shape exactly.
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import {
  parseCustomerPortalAccessReview,
  parseCustomerPortalAccessReviewMembershipRow,
  type CustomerPortalAccessReview,
  type CustomerPortalAccessReviewMembershipRow,
} from "../contracts/customer-portal-user-management/customer-portal-user-management.ts";

export type CustomerPortalUserManagementQueryClient = Pick<SupabaseClient, "rpc">;

export class CustomerPortalUserManagementQueryError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "CustomerPortalUserManagementQueryError";
  }
}

export interface CustomerPortalAccessReviewCursorOptions {
  cursorReviewedAt?: string | null;
  cursorId?: string | null;
  limit?: number;
}

export interface CustomerPortalAccessReviewMembershipCursorOptions {
  cursorUpdatedAt?: string | null;
  cursorId?: string | null;
  limit?: number;
}

/**
 * Access-review history for one account, optionally filtered to one
 * membership. account_admin-only, deny-by-default: a non-admin caller (self-
 * checked server-side against p_account_id) gets an empty result, never an
 * error. Keyset-paginated (reviewed_at desc, id desc).
 */
export async function listCustomerPortalAccountMembershipAccessReviews(
  client: CustomerPortalUserManagementQueryClient,
  tenantId: string,
  accountId: string,
  actorAuthUserId: string,
  options?: CustomerPortalAccessReviewCursorOptions & { membershipId?: string | null },
): Promise<CustomerPortalAccessReview[]> {
  const { data, error } = await client.rpc("list_customer_portal_account_membership_access_reviews", {
    p_tenant_id: tenantId,
    p_account_id: accountId,
    p_actor_auth_user_id: actorAuthUserId,
    p_membership_id: options?.membershipId ?? null,
    p_cursor_reviewed_at: options?.cursorReviewedAt ?? null,
    p_cursor_id: options?.cursorId ?? null,
    p_limit: options?.limit ?? 50,
  });
  if (error) {
    throw new CustomerPortalUserManagementQueryError(error.message);
  }
  return ((data as Record<string, unknown>[] | null) ?? []).map(parseCustomerPortalAccessReview);
}

/**
 * The "admin-facing view of active memberships in scope" the access-review
 * screen composes -- active-only, pre-joined with each membership's own MOST
 * RECENT review (null fields for a never-reviewed membership). account_admin
 * -only, deny-by-default. Keyset-paginated (updated_at desc, id desc).
 */
export async function listCustomerPortalAccountMembershipsForAccessReview(
  client: CustomerPortalUserManagementQueryClient,
  tenantId: string,
  accountId: string,
  actorAuthUserId: string,
  options?: CustomerPortalAccessReviewMembershipCursorOptions,
): Promise<CustomerPortalAccessReviewMembershipRow[]> {
  const { data, error } = await client.rpc("list_customer_portal_account_memberships_for_access_review", {
    p_tenant_id: tenantId,
    p_account_id: accountId,
    p_actor_auth_user_id: actorAuthUserId,
    p_cursor_updated_at: options?.cursorUpdatedAt ?? null,
    p_cursor_id: options?.cursorId ?? null,
    p_limit: options?.limit ?? 50,
  });
  if (error) {
    throw new CustomerPortalUserManagementQueryError(error.message);
  }
  return ((data as Record<string, unknown>[] | null) ?? []).map(parseCustomerPortalAccessReviewMembershipRow);
}
