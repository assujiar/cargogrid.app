/**
 * Customer Profile mutation primitives (CPL-314, CG-S13-CPL-016). Thin,
 * typed wrappers around every write RPC in supabase/migrations/
 * 20260801150000_create_customer_portal_customer_profile.sql, mirroring
 * server/mutations/customer-quote-request.ts's own known-error-code/
 * classifyError/callRpc shape.
 *
 * decideCustomerProfileChangeRequest is the ONE staff-gated (COM:Approve)
 * export here -- every other export is Layer-4-only (ADR-0024 Part B),
 * called through the ordinary RLS-scoped `authenticated` client exactly
 * like every other export, since the RPC itself is what enforces the
 * authority split, not the transport. It must never be called from a
 * customer-facing Server Action.
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import {
  SubmitCustomerProfileChangeRequestInputSchema,
  WithdrawCustomerProfileChangeRequestInputSchema,
  DecideCustomerProfileChangeRequestInputSchema,
  parseCustomerProfileChangeRequest,
  type SubmitCustomerProfileChangeRequestInput,
  type WithdrawCustomerProfileChangeRequestInput,
  type DecideCustomerProfileChangeRequestInput,
  type CustomerProfileChangeRequest,
} from "../contracts/customer-portal-profile/customer-portal-profile.ts";

export type CustomerPortalProfileMutationRpcClient = Pick<SupabaseClient, "rpc">;

export const CUSTOMER_PORTAL_PROFILE_KNOWN_MUTATION_ERROR_CODES = [
  "invalid_field_name",
  "account_not_available",
  "idempotency_key_conflict",
  "invalid_proposed_value",
  "record_not_found",
  "invalid_transition",
  "stale_version",
  "profile_change_request_not_found",
  "insufficient_authority",
  "self_approval_not_permitted",
  "invalid_decision",
  "reason_required",
  "actor_identity_mismatch",
] as const;
export type KnownCustomerPortalProfileMutationErrorCode = (typeof CUSTOMER_PORTAL_PROFILE_KNOWN_MUTATION_ERROR_CODES)[number];
export type CustomerPortalProfileMutationErrorCode = KnownCustomerPortalProfileMutationErrorCode | "mutation_failed";

export class CustomerPortalProfileMutationError extends Error {
  readonly code: CustomerPortalProfileMutationErrorCode;

  constructor(code: CustomerPortalProfileMutationErrorCode, message: string) {
    super(message);
    this.name = "CustomerPortalProfileMutationError";
    this.code = code;
  }
}

function classifyError(message: string): CustomerPortalProfileMutationErrorCode {
  const prefix = message.split(":")[0]?.trim();
  if (prefix && (CUSTOMER_PORTAL_PROFILE_KNOWN_MUTATION_ERROR_CODES as readonly string[]).includes(prefix)) {
    return prefix as KnownCustomerPortalProfileMutationErrorCode;
  }
  return "mutation_failed";
}

async function callRpc(client: CustomerPortalProfileMutationRpcClient, fn: string, args: Record<string, unknown>): Promise<CustomerProfileChangeRequest> {
  const { data, error } = await client.rpc(fn, args);
  if (error) {
    throw new CustomerPortalProfileMutationError(classifyError(error.message), error.message);
  }
  const row = Array.isArray(data) ? data[0] : data;
  if (!row || typeof row !== "object") {
    throw new CustomerPortalProfileMutationError("mutation_failed", `${fn} returned no row`);
  }
  return parseCustomerProfileChangeRequest(row as Record<string, unknown>);
}

/** Creates a pending profile change request for exactly one of {trade_name, billing_address}. accountId must already be in this identity's resolved scope -- a forged/unowned id is rejected with account_not_available. Idempotent on (tenantId, idempotencyKey) when a key is supplied. */
export async function submitCustomerProfileChangeRequest(client: CustomerPortalProfileMutationRpcClient, input: SubmitCustomerProfileChangeRequestInput): Promise<CustomerProfileChangeRequest> {
  const v = SubmitCustomerProfileChangeRequestInputSchema.parse(input);
  return callRpc(client, "submit_customer_profile_change_request", {
    p_tenant_id: v.tenantId,
    p_account_id: v.accountId,
    p_field_name: v.fieldName,
    p_proposed_value: v.proposedValue,
    p_idempotency_key: v.idempotencyKey ?? null,
    p_actor_auth_user_id: v.actorAuthUserId,
    p_actor_label: v.actorLabel,
  });
}

/** pending -> withdrawn only. Any active member of the request's own account may withdraw it, not only its original requester. Optimistic concurrency (stale_version). */
export async function withdrawCustomerProfileChangeRequest(client: CustomerPortalProfileMutationRpcClient, input: WithdrawCustomerProfileChangeRequestInput): Promise<CustomerProfileChangeRequest> {
  const v = WithdrawCustomerProfileChangeRequestInputSchema.parse(input);
  return callRpc(client, "withdraw_customer_profile_change_request", {
    p_request_id: v.requestId,
    p_expected_version: v.expectedVersion,
    p_actor_auth_user_id: v.actorAuthUserId,
    p_actor_label: v.actorLabel,
  });
}

/**
 * Staff-only (COM:Approve) -- pending -> approved | rejected. On approve,
 * applies the change to the REAL app.accounts row in the same transaction.
 * reviewReason is mandatory for both outcomes. Never call this from a
 * customer-facing route -- the RPC itself enforces COM:Approve, but this
 * wrapper exists only for a staff/internal workspace caller.
 */
export async function decideCustomerProfileChangeRequest(client: CustomerPortalProfileMutationRpcClient, input: DecideCustomerProfileChangeRequestInput): Promise<CustomerProfileChangeRequest> {
  const v = DecideCustomerProfileChangeRequestInputSchema.parse(input);
  return callRpc(client, "decide_customer_profile_change_request", {
    p_request_id: v.requestId,
    p_expected_version: v.expectedVersion,
    p_decision: v.decision,
    p_review_reason: v.reviewReason,
    p_actor_auth_user_id: v.actorAuthUserId,
    p_actor_label: v.actorLabel,
  });
}
