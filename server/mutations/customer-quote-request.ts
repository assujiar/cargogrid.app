/**
 * Customer Quote Request mutation primitives (CPL-302, CG-S13-CPL-004). Thin,
 * typed wrappers around every write RPC in supabase/migrations/
 * 20260801030000_create_customer_portal_quote_requests.sql, mirroring
 * server/mutations/customer-portal-scope.ts's own known-error-code/
 * classifyError/callRpc shape.
 *
 * app.link_customer_quote_request_to_quotation is the ONE staff-gated
 * (COM:Edit) function here -- every other export is Layer-4-only (ADR-0024
 * Part B), called through the ordinary RLS-scoped `authenticated` client
 * exactly like every other export, since the RPC itself is what enforces
 * the authority split, not the transport.
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import {
  CreateCustomerQuoteRequestDraftInputSchema,
  UpdateCustomerQuoteRequestDraftInputSchema,
  SubmitCustomerQuoteRequestInputSchema,
  CancelCustomerQuoteRequestInputSchema,
  LinkCustomerQuoteRequestToQuotationInputSchema,
  parseCustomerQuoteRequest,
  type CreateCustomerQuoteRequestDraftInput,
  type UpdateCustomerQuoteRequestDraftInput,
  type SubmitCustomerQuoteRequestInput,
  type CancelCustomerQuoteRequestInput,
  type LinkCustomerQuoteRequestToQuotationInput,
  type CustomerQuoteRequest,
} from "../contracts/customer-quote-request/customer-quote-request.ts";

export type CustomerQuoteRequestMutationRpcClient = Pick<SupabaseClient, "rpc">;

export const CUSTOMER_QUOTE_REQUEST_KNOWN_MUTATION_ERROR_CODES = [
  "account_not_available",
  "invalid_location",
  "invalid_dates",
  "record_not_found",
  "invalid_transition",
  "stale_version",
  "idempotency_key_required",
  "idempotency_conflict",
  "reason_required",
  "quote_request_not_found",
  "quotation_not_found",
  "already_converted",
  "insufficient_authority",
  "actor_identity_mismatch",
] as const;
export type KnownCustomerQuoteRequestMutationErrorCode = (typeof CUSTOMER_QUOTE_REQUEST_KNOWN_MUTATION_ERROR_CODES)[number];
export type CustomerQuoteRequestMutationErrorCode = KnownCustomerQuoteRequestMutationErrorCode | "mutation_failed";

export class CustomerQuoteRequestMutationError extends Error {
  readonly code: CustomerQuoteRequestMutationErrorCode;

  constructor(code: CustomerQuoteRequestMutationErrorCode, message: string) {
    super(message);
    this.name = "CustomerQuoteRequestMutationError";
    this.code = code;
  }
}

function classifyError(message: string): CustomerQuoteRequestMutationErrorCode {
  const prefix = message.split(":")[0]?.trim();
  if (prefix && (CUSTOMER_QUOTE_REQUEST_KNOWN_MUTATION_ERROR_CODES as readonly string[]).includes(prefix)) {
    return prefix as KnownCustomerQuoteRequestMutationErrorCode;
  }
  return "mutation_failed";
}

async function callRpc(client: CustomerQuoteRequestMutationRpcClient, fn: string, args: Record<string, unknown>): Promise<CustomerQuoteRequest> {
  const { data, error } = await client.rpc(fn, args);
  if (error) {
    throw new CustomerQuoteRequestMutationError(classifyError(error.message), error.message);
  }
  const row = Array.isArray(data) ? data[0] : data;
  if (!row || typeof row !== "object") {
    throw new CustomerQuoteRequestMutationError("mutation_failed", `${fn} returned no row`);
  }
  return parseCustomerQuoteRequest(row as Record<string, unknown>);
}

/** Creates a draft quote request. accountId must already be in this identity's resolved scope -- a forged/unowned id is rejected with account_not_available. Idempotent on (tenantId, idempotencyKey) when a key is supplied. */
export async function createCustomerQuoteRequestDraft(client: CustomerQuoteRequestMutationRpcClient, input: CreateCustomerQuoteRequestDraftInput): Promise<CustomerQuoteRequest> {
  const v = CreateCustomerQuoteRequestDraftInputSchema.parse(input);
  return callRpc(client, "create_customer_quote_request_draft", {
    p_tenant_id: v.tenantId,
    p_account_id: v.accountId,
    p_cargo_description: v.cargoDescription ?? null,
    p_origin: v.origin ?? {},
    p_destination: v.destination ?? {},
    p_service_type: v.serviceType ?? null,
    p_requested_pickup_date: v.requestedPickupDate ?? null,
    p_requested_delivery_date: v.requestedDeliveryDate ?? null,
    p_notes: v.notes ?? null,
    p_idempotency_key: v.idempotencyKey ?? null,
    p_actor_auth_user_id: v.actorAuthUserId,
    p_actor_label: v.actorLabel,
  });
}

/** Draft-only edit. Any active member of the request's own account may edit it, not only its original requester. Optimistic concurrency (stale_version). */
export async function updateCustomerQuoteRequestDraft(client: CustomerQuoteRequestMutationRpcClient, input: UpdateCustomerQuoteRequestDraftInput): Promise<CustomerQuoteRequest> {
  const v = UpdateCustomerQuoteRequestDraftInputSchema.parse(input);
  return callRpc(client, "update_customer_quote_request_draft", {
    p_request_id: v.requestId,
    p_expected_version: v.expectedVersion,
    p_cargo_description: v.cargoDescription ?? null,
    p_origin: v.origin ?? {},
    p_destination: v.destination ?? {},
    p_service_type: v.serviceType ?? null,
    p_requested_pickup_date: v.requestedPickupDate ?? null,
    p_requested_delivery_date: v.requestedDeliveryDate ?? null,
    p_notes: v.notes ?? null,
    p_actor_auth_user_id: v.actorAuthUserId,
    p_actor_label: v.actorLabel,
  });
}

/** draft -> submitted. idempotencyKey is mandatory and unique per (tenant, account) -- a genuine retry with the SAME key on the SAME row is an idempotent no-op; the same key against a different request on the same account is a real idempotency_conflict. */
export async function submitCustomerQuoteRequest(client: CustomerQuoteRequestMutationRpcClient, input: SubmitCustomerQuoteRequestInput): Promise<CustomerQuoteRequest> {
  const v = SubmitCustomerQuoteRequestInputSchema.parse(input);
  return callRpc(client, "submit_customer_quote_request", {
    p_request_id: v.requestId,
    p_expected_version: v.expectedVersion,
    p_idempotency_key: v.idempotencyKey,
    p_actor_auth_user_id: v.actorAuthUserId,
    p_actor_label: v.actorLabel,
  });
}

/** draft or submitted -> cancelled. Mandatory non-empty reason. A terminal (cancelled/converted) request correctly refuses with invalid_transition. */
export async function cancelCustomerQuoteRequest(client: CustomerQuoteRequestMutationRpcClient, input: CancelCustomerQuoteRequestInput): Promise<CustomerQuoteRequest> {
  const v = CancelCustomerQuoteRequestInputSchema.parse(input);
  return callRpc(client, "cancel_customer_quote_request", {
    p_request_id: v.requestId,
    p_expected_version: v.expectedVersion,
    p_reason: v.reason,
    p_actor_auth_user_id: v.actorAuthUserId,
    p_actor_label: v.actorLabel,
  });
}

/** Staff-only (COM:Edit) conversion acknowledgement -- submitted -> converted, linked_quotation_id set exactly once. Idempotent for the SAME (request, quotation) pair; a different quotation on an already-converted request is a real already_converted conflict, never a silent overwrite. */
export async function linkCustomerQuoteRequestToQuotation(client: CustomerQuoteRequestMutationRpcClient, input: LinkCustomerQuoteRequestToQuotationInput): Promise<CustomerQuoteRequest> {
  const v = LinkCustomerQuoteRequestToQuotationInputSchema.parse(input);
  return callRpc(client, "link_customer_quote_request_to_quotation", {
    p_request_id: v.requestId,
    p_quotation_id: v.quotationId,
    p_actor_auth_user_id: v.actorAuthUserId,
    p_actor_label: v.actorLabel,
  });
}
