/**
 * Legal Identity Change Request mutation primitives (ISS-2026-123 item 1). Thin, typed
 * wrappers around every write RPC in supabase/migrations/
 * 20260901080000_create_customer_portal_legal_identity_change_requests.sql, mirroring
 * server/mutations/customer-portal-profile.ts's own known-error-code/classifyError/callRpc
 * shape.
 *
 * decideCustomerLegalIdentityChangeRequest is the ONE staff-gated (COM:Approve, additionally
 * step-up-MFA-gated per tenant policy) export here -- every other export is Layer-4-only,
 * called through the ordinary RLS-scoped `authenticated` client exactly like every other
 * export, since the RPC itself is what enforces the authority split. It must never be called
 * from a customer-facing Server Action.
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import {
  SubmitCustomerLegalIdentityChangeRequestInputSchema,
  WithdrawCustomerLegalIdentityChangeRequestInputSchema,
  DecideCustomerLegalIdentityChangeRequestInputSchema,
  parseCustomerLegalIdentityChangeRequest,
  type SubmitCustomerLegalIdentityChangeRequestInput,
  type WithdrawCustomerLegalIdentityChangeRequestInput,
  type DecideCustomerLegalIdentityChangeRequestInput,
  type CustomerLegalIdentityChangeRequest,
} from "../contracts/customer-portal-legal-identity/customer-portal-legal-identity.ts";

export type CustomerPortalLegalIdentityMutationRpcClient = Pick<SupabaseClient, "rpc">;

export const CUSTOMER_PORTAL_LEGAL_IDENTITY_KNOWN_MUTATION_ERROR_CODES = [
  "invalid_field_name",
  "account_not_available",
  "idempotency_key_conflict",
  "invalid_proposed_value",
  "record_not_found",
  "invalid_transition",
  "stale_version",
  "legal_identity_change_request_not_found",
  "insufficient_authority",
  "mfa_step_up_required",
  "self_approval_not_permitted",
  "invalid_decision",
  "reason_required",
  "identity_fingerprint_conflict",
  "unhandled_field_name",
  "actor_identity_mismatch",
] as const;
export type KnownCustomerPortalLegalIdentityMutationErrorCode = (typeof CUSTOMER_PORTAL_LEGAL_IDENTITY_KNOWN_MUTATION_ERROR_CODES)[number];
export type CustomerPortalLegalIdentityMutationErrorCode = KnownCustomerPortalLegalIdentityMutationErrorCode | "mutation_failed";

export class CustomerPortalLegalIdentityMutationError extends Error {
  readonly code: CustomerPortalLegalIdentityMutationErrorCode;

  constructor(code: CustomerPortalLegalIdentityMutationErrorCode, message: string) {
    super(message);
    this.name = "CustomerPortalLegalIdentityMutationError";
    this.code = code;
  }
}

function classifyError(message: string): CustomerPortalLegalIdentityMutationErrorCode {
  const prefix = message.split(":")[0]?.trim();
  if (prefix && (CUSTOMER_PORTAL_LEGAL_IDENTITY_KNOWN_MUTATION_ERROR_CODES as readonly string[]).includes(prefix)) {
    return prefix as KnownCustomerPortalLegalIdentityMutationErrorCode;
  }
  return "mutation_failed";
}

async function callRpc(client: CustomerPortalLegalIdentityMutationRpcClient, fn: string, args: Record<string, unknown>): Promise<CustomerLegalIdentityChangeRequest> {
  const { data, error } = await client.rpc(fn, args);
  if (error) {
    throw new CustomerPortalLegalIdentityMutationError(classifyError(error.message), error.message);
  }
  const row = Array.isArray(data) ? data[0] : data;
  if (!row || typeof row !== "object") {
    throw new CustomerPortalLegalIdentityMutationError("mutation_failed", `${fn} returned no row`);
  }
  return parseCustomerLegalIdentityChangeRequest(row as Record<string, unknown>);
}

/** Creates a pending legal identity change request for exactly one of {legal_name, tax_id}. accountId must already be in this identity's resolved scope. Idempotent on (tenantId, idempotencyKey) when a key is supplied. */
export async function submitCustomerLegalIdentityChangeRequest(client: CustomerPortalLegalIdentityMutationRpcClient, input: SubmitCustomerLegalIdentityChangeRequestInput): Promise<CustomerLegalIdentityChangeRequest> {
  const v = SubmitCustomerLegalIdentityChangeRequestInputSchema.parse(input);
  return callRpc(client, "submit_customer_legal_identity_change_request", {
    p_tenant_id: v.tenantId,
    p_account_id: v.accountId,
    p_field_name: v.fieldName,
    p_proposed_value: v.proposedValue,
    p_idempotency_key: v.idempotencyKey ?? null,
    p_actor_auth_user_id: v.actorAuthUserId,
    p_actor_label: v.actorLabel,
  });
}

/** pending -> withdrawn only. Any active member of the request's own account may withdraw it. Optimistic concurrency (stale_version). */
export async function withdrawCustomerLegalIdentityChangeRequest(client: CustomerPortalLegalIdentityMutationRpcClient, input: WithdrawCustomerLegalIdentityChangeRequestInput): Promise<CustomerLegalIdentityChangeRequest> {
  const v = WithdrawCustomerLegalIdentityChangeRequestInputSchema.parse(input);
  return callRpc(client, "withdraw_customer_legal_identity_change_request", {
    p_request_id: v.requestId,
    p_expected_version: v.expectedVersion,
    p_actor_auth_user_id: v.actorAuthUserId,
    p_actor_label: v.actorLabel,
  });
}

/**
 * Staff-only (COM:Approve, additionally step-up-MFA-gated per tenant policy) -- pending ->
 * approved | rejected. On approve, recomputes normalized_legal_name/normalized_tax_id/
 * duplicate_fingerprint and applies the change to the REAL app.accounts row in the same
 * transaction. reviewReason is mandatory for both outcomes. Never call this from a
 * customer-facing route.
 */
export async function decideCustomerLegalIdentityChangeRequest(client: CustomerPortalLegalIdentityMutationRpcClient, input: DecideCustomerLegalIdentityChangeRequestInput): Promise<CustomerLegalIdentityChangeRequest> {
  const v = DecideCustomerLegalIdentityChangeRequestInputSchema.parse(input);
  return callRpc(client, "decide_customer_legal_identity_change_request", {
    p_request_id: v.requestId,
    p_expected_version: v.expectedVersion,
    p_decision: v.decision,
    p_review_reason: v.reviewReason,
    p_actor_auth_user_id: v.actorAuthUserId,
    p_actor_label: v.actorLabel,
  });
}
