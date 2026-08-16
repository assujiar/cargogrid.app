/**
 * Customer Portal Scope mutation primitives (CPL-300, CG-S13-CPL-002). Thin,
 * typed wrappers around every write RPC in supabase/migrations/
 * 20260801010000_create_customer_portal_account_scope.sql, mirroring
 * server/mutations/ticketing.ts's own known-error-code/classifyError/callRpc
 * shape (a real, populated error-code list, unlike server/mutations/
 * customer-inventory-access.ts's own empty one -- this capability's RPCs raise
 * several distinct, classified error prefixes).
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import {
  InviteCustomerPortalUserInputSchema,
  AcceptCustomerPortalInviteInputSchema,
  SetCustomerPortalAccountMembershipStatusInputSchema,
  GrantInitialCustomerPortalAccountAdminInputSchema,
  parseCustomerPortalAccountMembership,
  type InviteCustomerPortalUserInput,
  type AcceptCustomerPortalInviteInput,
  type SetCustomerPortalAccountMembershipStatusInput,
  type GrantInitialCustomerPortalAccountAdminInput,
  type CustomerPortalAccountMembership,
} from "../contracts/customer-portal-scope/customer-portal-scope.ts";

export type CustomerPortalScopeMutationRpcClient = Pick<SupabaseClient, "rpc">;

export const CUSTOMER_PORTAL_SCOPE_KNOWN_MUTATION_ERROR_CODES = [
  "insufficient_authority",
  "invalid_role",
  "invalid_status",
  "invalid_cpam_transition",
  "membership_revoked",
  "reason_required",
  "stale_version",
  "invalid_transition",
  "accept_required",
  "customer_portal_membership_not_found",
  "account_not_found",
  "actor_identity_mismatch",
] as const;
export type KnownCustomerPortalScopeMutationErrorCode = (typeof CUSTOMER_PORTAL_SCOPE_KNOWN_MUTATION_ERROR_CODES)[number];
export type CustomerPortalScopeMutationErrorCode = KnownCustomerPortalScopeMutationErrorCode | "mutation_failed";

export class CustomerPortalScopeMutationError extends Error {
  readonly code: CustomerPortalScopeMutationErrorCode;

  constructor(code: CustomerPortalScopeMutationErrorCode, message: string) {
    super(message);
    this.name = "CustomerPortalScopeMutationError";
    this.code = code;
  }
}

function classifyError(message: string): CustomerPortalScopeMutationErrorCode {
  const prefix = message.split(":")[0]?.trim();
  if (prefix && (CUSTOMER_PORTAL_SCOPE_KNOWN_MUTATION_ERROR_CODES as readonly string[]).includes(prefix)) {
    return prefix as KnownCustomerPortalScopeMutationErrorCode;
  }
  return "mutation_failed";
}

async function callRpc(client: CustomerPortalScopeMutationRpcClient, fn: string, args: Record<string, unknown>): Promise<CustomerPortalAccountMembership> {
  const { data, error } = await client.rpc(fn, args);
  if (error) {
    throw new CustomerPortalScopeMutationError(classifyError(error.message), error.message);
  }
  const row = Array.isArray(data) ? data[0] : data;
  if (!row || typeof row !== "object") {
    throw new CustomerPortalScopeMutationError("mutation_failed", `${fn} returned no row`);
  }
  return parseCustomerPortalAccountMembership(row as Record<string, unknown>);
}

/** Self-service invite by an existing active account_admin on the exact target account. Idempotent: a repeated invite for the same (tenant, identity, account) that is not revoked returns the existing row unchanged. */
export async function inviteCustomerPortalUser(client: CustomerPortalScopeMutationRpcClient, input: InviteCustomerPortalUserInput): Promise<CustomerPortalAccountMembership> {
  const v = InviteCustomerPortalUserInputSchema.parse(input);
  return callRpc(client, "invite_customer_portal_user", {
    p_tenant_id: v.tenantId,
    p_account_id: v.accountId,
    p_auth_user_id: v.authUserId,
    p_role: v.role,
    p_actor_auth_user_id: v.actorAuthUserId,
    p_invited_by: v.invitedBy,
  });
}

/** invited -> active only, by the invited identity itself. A forged/copied authUserId is rejected (insufficient_authority). Optimistic-concurrency (stale_version). */
export async function acceptCustomerPortalInvite(client: CustomerPortalScopeMutationRpcClient, input: AcceptCustomerPortalInviteInput): Promise<CustomerPortalAccountMembership> {
  const v = AcceptCustomerPortalInviteInputSchema.parse(input);
  return callRpc(client, "accept_customer_portal_invite", {
    p_membership_id: v.membershipId,
    p_expected_version: v.expectedVersion,
    p_auth_user_id: v.authUserId,
  });
}

/** Suspend/revoke/reactivate. Caller must hold an ACTIVE account_admin role on the same account. Mandatory non-empty reason for suspend/revoke. Revocation takes effect on scope immediately -- no caching, no separate invalidation step needed. */
export async function setCustomerPortalAccountMembershipStatus(
  client: CustomerPortalScopeMutationRpcClient,
  input: SetCustomerPortalAccountMembershipStatusInput,
): Promise<CustomerPortalAccountMembership> {
  const v = SetCustomerPortalAccountMembershipStatusInputSchema.parse(input);
  return callRpc(client, "set_customer_portal_account_membership_status", {
    p_membership_id: v.membershipId,
    p_expected_version: v.expectedVersion,
    p_to_status: v.toStatus,
    p_reason: v.reason ?? null,
    p_actor_auth_user_id: v.actorAuthUserId,
    p_actor_label: v.actorLabel,
  });
}

/** Tenant-admin-only (staff, CPT:Create) bootstrap -- seeds the first account_admin on a brand-new account, once. Idempotent no-op if called again for the same identity+account while not revoked. */
export async function grantInitialCustomerPortalAccountAdmin(
  client: CustomerPortalScopeMutationRpcClient,
  input: GrantInitialCustomerPortalAccountAdminInput,
): Promise<CustomerPortalAccountMembership> {
  const v = GrantInitialCustomerPortalAccountAdminInputSchema.parse(input);
  return callRpc(client, "grant_initial_customer_portal_account_admin", {
    p_tenant_id: v.tenantId,
    p_account_id: v.accountId,
    p_auth_user_id: v.authUserId,
    p_actor_auth_user_id: v.actorAuthUserId,
    p_actor_label: v.actorLabel,
  });
}
