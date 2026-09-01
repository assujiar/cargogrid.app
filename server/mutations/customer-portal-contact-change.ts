/**
 * Contact Change Request mutation primitives (ISS-2026-123 item 2). Thin, typed wrappers
 * around every write RPC in supabase/migrations/
 * 20260901090000_create_customer_portal_contact_change_requests.sql, mirroring
 * server/mutations/customer-portal-profile.ts's own known-error-code/classifyError/callRpc
 * shape.
 *
 * decideCustomerContactChangeRequest is the ONE staff-gated (COM:Approve, additionally
 * step-up-MFA-gated per tenant policy) export here. It must never be called from a
 * customer-facing Server Action.
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import {
  SubmitCustomerContactChangeRequestInputSchema,
  WithdrawCustomerContactChangeRequestInputSchema,
  DecideCustomerContactChangeRequestInputSchema,
  parseCustomerContactChangeRequest,
  type SubmitCustomerContactChangeRequestInput,
  type WithdrawCustomerContactChangeRequestInput,
  type DecideCustomerContactChangeRequestInput,
  type CustomerContactChangeRequest,
} from "../contracts/customer-portal-contact-change/customer-portal-contact-change.ts";

export type CustomerPortalContactChangeMutationRpcClient = Pick<SupabaseClient, "rpc">;

export const CUSTOMER_PORTAL_CONTACT_CHANGE_KNOWN_MUTATION_ERROR_CODES = [
  "invalid_change_kind",
  "account_not_available",
  "invalid_target_contact",
  "contact_not_available",
  "invalid_proposed_value",
  "invalid_role",
  "idempotency_key_conflict",
  "record_not_found",
  "invalid_transition",
  "stale_version",
  "contact_change_request_not_found",
  "insufficient_authority",
  "mfa_step_up_required",
  "self_approval_not_permitted",
  "invalid_decision",
  "reason_required",
  "contact_link_conflict",
  "unhandled_change_kind",
  "actor_identity_mismatch",
] as const;
export type KnownCustomerPortalContactChangeMutationErrorCode = (typeof CUSTOMER_PORTAL_CONTACT_CHANGE_KNOWN_MUTATION_ERROR_CODES)[number];
export type CustomerPortalContactChangeMutationErrorCode = KnownCustomerPortalContactChangeMutationErrorCode | "mutation_failed";

export class CustomerPortalContactChangeMutationError extends Error {
  readonly code: CustomerPortalContactChangeMutationErrorCode;

  constructor(code: CustomerPortalContactChangeMutationErrorCode, message: string) {
    super(message);
    this.name = "CustomerPortalContactChangeMutationError";
    this.code = code;
  }
}

function classifyError(message: string): CustomerPortalContactChangeMutationErrorCode {
  const prefix = message.split(":")[0]?.trim();
  if (prefix && (CUSTOMER_PORTAL_CONTACT_CHANGE_KNOWN_MUTATION_ERROR_CODES as readonly string[]).includes(prefix)) {
    return prefix as KnownCustomerPortalContactChangeMutationErrorCode;
  }
  return "mutation_failed";
}

async function callRpc(client: CustomerPortalContactChangeMutationRpcClient, fn: string, args: Record<string, unknown>): Promise<CustomerContactChangeRequest> {
  const { data, error } = await client.rpc(fn, args);
  if (error) {
    throw new CustomerPortalContactChangeMutationError(classifyError(error.message), error.message);
  }
  const row = Array.isArray(data) ? data[0] : data;
  if (!row || typeof row !== "object") {
    throw new CustomerPortalContactChangeMutationError("mutation_failed", `${fn} returned no row`);
  }
  return parseCustomerContactChangeRequest(row as Record<string, unknown>);
}

/** Creates a pending contact change request (add/update/remove) for an account this identity holds real scope over. For update/remove, targetContactId must be genuinely linked to THIS account. Idempotent on (tenantId, idempotencyKey) when a key is supplied. */
export async function submitCustomerContactChangeRequest(client: CustomerPortalContactChangeMutationRpcClient, input: SubmitCustomerContactChangeRequestInput): Promise<CustomerContactChangeRequest> {
  const v = SubmitCustomerContactChangeRequestInputSchema.parse(input);
  return callRpc(client, "submit_customer_contact_change_request", {
    p_tenant_id: v.tenantId,
    p_account_id: v.accountId,
    p_change_kind: v.changeKind,
    p_target_contact_id: v.targetContactId ?? null,
    p_full_name: v.fullName ?? null,
    p_title: v.title ?? null,
    p_email: v.email ?? null,
    p_phone: v.phone ?? null,
    p_role: v.role ?? null,
    p_is_primary: v.isPrimary ?? null,
    p_idempotency_key: v.idempotencyKey ?? null,
    p_actor_auth_user_id: v.actorAuthUserId,
    p_actor_label: v.actorLabel,
  });
}

/** pending -> withdrawn only. Any active member of the request's own account may withdraw it. Optimistic concurrency (stale_version). */
export async function withdrawCustomerContactChangeRequest(client: CustomerPortalContactChangeMutationRpcClient, input: WithdrawCustomerContactChangeRequestInput): Promise<CustomerContactChangeRequest> {
  const v = WithdrawCustomerContactChangeRequestInputSchema.parse(input);
  return callRpc(client, "withdraw_customer_contact_change_request", {
    p_request_id: v.requestId,
    p_expected_version: v.expectedVersion,
    p_actor_auth_user_id: v.actorAuthUserId,
    p_actor_label: v.actorLabel,
  });
}

/**
 * Staff-only (COM:Approve, additionally step-up-MFA-gated per tenant policy) -- pending ->
 * approved | rejected. On approve: add calls app.create_contact + app.link_contact_to_record;
 * remove calls app.unlink_contact_from_record; update issues a direct UPDATE. reviewReason is
 * mandatory for both outcomes. Never call this from a customer-facing route.
 */
export async function decideCustomerContactChangeRequest(client: CustomerPortalContactChangeMutationRpcClient, input: DecideCustomerContactChangeRequestInput): Promise<CustomerContactChangeRequest> {
  const v = DecideCustomerContactChangeRequestInputSchema.parse(input);
  return callRpc(client, "decide_customer_contact_change_request", {
    p_request_id: v.requestId,
    p_expected_version: v.expectedVersion,
    p_decision: v.decision,
    p_review_reason: v.reviewReason,
    p_actor_auth_user_id: v.actorAuthUserId,
    p_actor_label: v.actorLabel,
  });
}
