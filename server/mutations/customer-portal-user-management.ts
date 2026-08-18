/**
 * Customer Portal User Management mutation primitives (CPL-315,
 * CG-S13-CPL-017). Thin, typed wrappers around every write RPC in
 * supabase/migrations/20260801170000_create_customer_portal_user_management.sql,
 * mirroring server/mutations/customer-portal-scope.ts's own known-error-
 * code/classifyError/callRpc shape.
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import {
  UpdateCustomerPortalAccountMembershipRoleInputSchema,
  RecordCustomerPortalAccountMembershipAccessReviewInputSchema,
  parseCustomerPortalAccountMembership,
  parseCustomerPortalAccessReview,
  type UpdateCustomerPortalAccountMembershipRoleInput,
  type RecordCustomerPortalAccountMembershipAccessReviewInput,
  type CustomerPortalAccountMembership,
  type CustomerPortalAccessReview,
} from "../contracts/customer-portal-user-management/customer-portal-user-management.ts";

export type CustomerPortalUserManagementMutationRpcClient = Pick<SupabaseClient, "rpc">;

export const CUSTOMER_PORTAL_USER_MANAGEMENT_KNOWN_MUTATION_ERROR_CODES = [
  "invalid_role",
  "customer_portal_membership_not_found",
  "insufficient_authority",
  "invalid_transition",
  "stale_version",
  "last_account_admin",
  "invalid_review_outcome",
  "invalid_idempotency_key",
  "invalid_review_target",
  "idempotency_key_conflict",
  "actor_identity_mismatch",
] as const;
export type KnownCustomerPortalUserManagementMutationErrorCode = (typeof CUSTOMER_PORTAL_USER_MANAGEMENT_KNOWN_MUTATION_ERROR_CODES)[number];
export type CustomerPortalUserManagementMutationErrorCode = KnownCustomerPortalUserManagementMutationErrorCode | "mutation_failed";

export class CustomerPortalUserManagementMutationError extends Error {
  readonly code: CustomerPortalUserManagementMutationErrorCode;

  constructor(code: CustomerPortalUserManagementMutationErrorCode, message: string) {
    super(message);
    this.name = "CustomerPortalUserManagementMutationError";
    this.code = code;
  }
}

function classifyError(message: string): CustomerPortalUserManagementMutationErrorCode {
  const prefix = message.split(":")[0]?.trim();
  if (prefix && (CUSTOMER_PORTAL_USER_MANAGEMENT_KNOWN_MUTATION_ERROR_CODES as readonly string[]).includes(prefix)) {
    return prefix as KnownCustomerPortalUserManagementMutationErrorCode;
  }
  return "mutation_failed";
}

function firstRow(data: unknown): Record<string, unknown> | null {
  const row = Array.isArray(data) ? data[0] : data;
  return row && typeof row === "object" ? (row as Record<string, unknown>) : null;
}

/** Change role (account_admin <-> member) for an existing ACTIVE membership. Caller must hold an ACTIVE account_admin role on the same account. Rejects (last_account_admin) a demotion that would leave the account with zero active account_admins. Idempotent no-op if the target role is already in effect. */
export async function updateCustomerPortalAccountMembershipRole(
  client: CustomerPortalUserManagementMutationRpcClient,
  input: UpdateCustomerPortalAccountMembershipRoleInput,
): Promise<CustomerPortalAccountMembership> {
  const v = UpdateCustomerPortalAccountMembershipRoleInputSchema.parse(input);
  const { data, error } = await client.rpc("update_customer_portal_account_membership_role", {
    p_membership_id: v.membershipId,
    p_expected_version: v.expectedVersion,
    p_new_role: v.newRole,
    p_actor_auth_user_id: v.actorAuthUserId,
    p_actor_label: v.actorLabel,
  });
  if (error) {
    throw new CustomerPortalUserManagementMutationError(classifyError(error.message), error.message);
  }
  const row = firstRow(data);
  if (!row) {
    throw new CustomerPortalUserManagementMutationError("mutation_failed", "update_customer_portal_account_membership_role returned no row");
  }
  return parseCustomerPortalAccountMembership(row);
}

/** Records an access-review attestation for an ACTIVE membership -- an observation, never itself a role/status change. Caller must hold an ACTIVE account_admin role on the same account. Idempotent on idempotencyKey (a real, caller-supplied event key -- two distinct review occasions must use two distinct keys). */
export async function recordCustomerPortalAccountMembershipAccessReview(
  client: CustomerPortalUserManagementMutationRpcClient,
  input: RecordCustomerPortalAccountMembershipAccessReviewInput,
): Promise<CustomerPortalAccessReview> {
  const v = RecordCustomerPortalAccountMembershipAccessReviewInputSchema.parse(input);
  const { data, error } = await client.rpc("record_customer_portal_account_membership_access_review", {
    p_membership_id: v.membershipId,
    p_review_outcome: v.reviewOutcome,
    p_note: v.note ?? null,
    p_idempotency_key: v.idempotencyKey,
    p_actor_auth_user_id: v.actorAuthUserId,
    p_actor_label: v.actorLabel,
  });
  if (error) {
    throw new CustomerPortalUserManagementMutationError(classifyError(error.message), error.message);
  }
  const row = firstRow(data);
  if (!row) {
    throw new CustomerPortalUserManagementMutationError("mutation_failed", "record_customer_portal_account_membership_access_review returned no row");
  }
  return parseCustomerPortalAccessReview(row);
}
