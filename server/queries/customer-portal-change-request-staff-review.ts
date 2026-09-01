/**
 * Staff-facing, tenant-wide read queries for every customer-portal change-request table
 * (ISS-2026-123). Thin, typed wrappers around the 3 RPCs in supabase/migrations/
 * 20260901100000_create_customer_portal_change_request_staff_review.sql.
 *
 * These are DELIBERATELY separate from server/queries/customer-portal-profile.ts's own
 * listCustomerPortalProfileChangeRequests (and this capability's own account-scoped list
 * queries) -- those are Layer-4 customer-scoped (app.resolve_customer_account_scope) and
 * always return empty for a staff caller, which holds no customer account scope. The
 * underlying RPCs here are COM:Approve-gated instead, and see every request tenant-wide.
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import { parseCustomerProfileChangeRequest, type CustomerProfileChangeRequest, type CustomerProfileChangeRequestStatus } from "../contracts/customer-portal-profile/customer-portal-profile.ts";
import { parseCustomerLegalIdentityChangeRequest, type CustomerLegalIdentityChangeRequest, type CustomerLegalIdentityChangeRequestStatus } from "../contracts/customer-portal-legal-identity/customer-portal-legal-identity.ts";
import { parseCustomerContactChangeRequest, type CustomerContactChangeRequest, type CustomerContactChangeRequestStatus } from "../contracts/customer-portal-contact-change/customer-portal-contact-change.ts";

export type CustomerPortalChangeRequestStaffReviewQueryClient = Pick<SupabaseClient, "rpc">;

export class CustomerPortalChangeRequestStaffReviewQueryError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "CustomerPortalChangeRequestStaffReviewQueryError";
  }
}

export interface StaffReviewCursorOptions {
  cursorUpdatedAt?: string | null;
  cursorId?: string | null;
  limit?: number;
}

/** Tenant-wide, COM:Approve-gated. An actor lacking COM:Approve gets an empty result, never an error (deny-by-default, mirrors every list RPC in this codebase). */
export async function listProfileChangeRequestsForStaffReview(
  client: CustomerPortalChangeRequestStaffReviewQueryClient,
  tenantId: string,
  actorAuthUserId: string,
  options?: StaffReviewCursorOptions & { status?: CustomerProfileChangeRequestStatus | null },
): Promise<CustomerProfileChangeRequest[]> {
  const { data, error } = await client.rpc("list_profile_change_requests_staff_review", {
    p_tenant_id: tenantId,
    p_actor_auth_user_id: actorAuthUserId,
    p_status: options?.status ?? "pending",
    p_cursor_updated_at: options?.cursorUpdatedAt ?? null,
    p_cursor_id: options?.cursorId ?? null,
    p_limit: options?.limit ?? 50,
  });
  if (error) throw new CustomerPortalChangeRequestStaffReviewQueryError(error.message);
  return ((data as Record<string, unknown>[] | null) ?? []).map(parseCustomerProfileChangeRequest);
}

export async function listLegalIdentityChangeRequestsForStaffReview(
  client: CustomerPortalChangeRequestStaffReviewQueryClient,
  tenantId: string,
  actorAuthUserId: string,
  options?: StaffReviewCursorOptions & { status?: CustomerLegalIdentityChangeRequestStatus | null },
): Promise<CustomerLegalIdentityChangeRequest[]> {
  const { data, error } = await client.rpc("list_legal_identity_change_requests_staff_review", {
    p_tenant_id: tenantId,
    p_actor_auth_user_id: actorAuthUserId,
    p_status: options?.status ?? "pending",
    p_cursor_updated_at: options?.cursorUpdatedAt ?? null,
    p_cursor_id: options?.cursorId ?? null,
    p_limit: options?.limit ?? 50,
  });
  if (error) throw new CustomerPortalChangeRequestStaffReviewQueryError(error.message);
  return ((data as Record<string, unknown>[] | null) ?? []).map(parseCustomerLegalIdentityChangeRequest);
}

export async function listContactChangeRequestsForStaffReview(
  client: CustomerPortalChangeRequestStaffReviewQueryClient,
  tenantId: string,
  actorAuthUserId: string,
  options?: StaffReviewCursorOptions & { status?: CustomerContactChangeRequestStatus | null },
): Promise<CustomerContactChangeRequest[]> {
  const { data, error } = await client.rpc("list_contact_change_requests_staff_review", {
    p_tenant_id: tenantId,
    p_actor_auth_user_id: actorAuthUserId,
    p_status: options?.status ?? "pending",
    p_cursor_updated_at: options?.cursorUpdatedAt ?? null,
    p_cursor_id: options?.cursorId ?? null,
    p_limit: options?.limit ?? 50,
  });
  if (error) throw new CustomerPortalChangeRequestStaffReviewQueryError(error.message);
  return ((data as Record<string, unknown>[] | null) ?? []).map(parseCustomerContactChangeRequest);
}
