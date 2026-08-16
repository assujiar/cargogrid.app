/**
 * Customer Booking Request mutation primitives (CPL-303, CG-S13-CPL-005).
 * Thin, typed wrappers around every write RPC in supabase/migrations/
 * 20260801040000_create_customer_portal_booking_requests.sql, mirroring
 * server/mutations/customer-quote-request.ts's own known-error-code/
 * classifyError/callRpc shape.
 *
 * app.link_customer_booking_request_to_operational_records is the ONE
 * staff-gated (OPS:Edit) function here -- every other export is Layer-4-only
 * (ADR-0024 Part B), called through the ordinary RLS-scoped `authenticated`
 * client exactly like every other export, since the RPC itself is what
 * enforces the authority split, not the transport.
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import {
  CreateCustomerBookingRequestDraftInputSchema,
  UpdateCustomerBookingRequestDraftInputSchema,
  SubmitCustomerBookingRequestInputSchema,
  RequestCustomerBookingRescheduleInputSchema,
  RequestCustomerBookingCancellationInputSchema,
  LinkCustomerBookingRequestToOperationalRecordsInputSchema,
  parseCustomerBookingRequest,
  type CreateCustomerBookingRequestDraftInput,
  type UpdateCustomerBookingRequestDraftInput,
  type SubmitCustomerBookingRequestInput,
  type RequestCustomerBookingRescheduleInput,
  type RequestCustomerBookingCancellationInput,
  type LinkCustomerBookingRequestToOperationalRecordsInput,
  type CustomerBookingRequest,
} from "../contracts/customer-booking-request/customer-booking-request.ts";

export type CustomerBookingRequestMutationRpcClient = Pick<SupabaseClient, "rpc">;

export const CUSTOMER_BOOKING_REQUEST_KNOWN_MUTATION_ERROR_CODES = [
  "account_not_available",
  "invalid_location",
  "invalid_dates",
  "quote_request_not_found",
  "quote_request_account_mismatch",
  "quote_request_not_accepted",
  "record_not_found",
  "invalid_transition",
  "stale_version",
  "reason_required",
  "reschedule_date_required",
  "booking_request_not_found",
  "job_order_id_required",
  "shipment_order_id_required",
  "job_order_not_found",
  "job_order_account_mismatch",
  "shipment_order_not_found",
  "shipment_order_job_order_mismatch",
  "shipment_order_account_mismatch",
  "already_converted",
  "insufficient_authority",
  "actor_identity_mismatch",
] as const;
export type KnownCustomerBookingRequestMutationErrorCode = (typeof CUSTOMER_BOOKING_REQUEST_KNOWN_MUTATION_ERROR_CODES)[number];
export type CustomerBookingRequestMutationErrorCode = KnownCustomerBookingRequestMutationErrorCode | "mutation_failed";

export class CustomerBookingRequestMutationError extends Error {
  readonly code: CustomerBookingRequestMutationErrorCode;

  constructor(code: CustomerBookingRequestMutationErrorCode, message: string) {
    super(message);
    this.name = "CustomerBookingRequestMutationError";
    this.code = code;
  }
}

function classifyError(message: string): CustomerBookingRequestMutationErrorCode {
  const prefix = message.split(":")[0]?.trim();
  if (prefix && (CUSTOMER_BOOKING_REQUEST_KNOWN_MUTATION_ERROR_CODES as readonly string[]).includes(prefix)) {
    return prefix as KnownCustomerBookingRequestMutationErrorCode;
  }
  return "mutation_failed";
}

async function callRpc(client: CustomerBookingRequestMutationRpcClient, fn: string, args: Record<string, unknown>): Promise<CustomerBookingRequest> {
  const { data, error } = await client.rpc(fn, args);
  if (error) {
    throw new CustomerBookingRequestMutationError(classifyError(error.message), error.message);
  }
  const row = Array.isArray(data) ? data[0] : data;
  if (!row || typeof row !== "object") {
    throw new CustomerBookingRequestMutationError("mutation_failed", `${fn} returned no row`);
  }
  return parseCustomerBookingRequest(row as Record<string, unknown>);
}

/** Creates a draft booking request, optionally originating from an already-converted (staff-accepted) quote request on the same account. accountId must already be in this identity's resolved scope -- a forged/unowned id is rejected with account_not_available. Idempotent on (tenantId, idempotencyKey) when a key is supplied. */
export async function createCustomerBookingRequestDraft(client: CustomerBookingRequestMutationRpcClient, input: CreateCustomerBookingRequestDraftInput): Promise<CustomerBookingRequest> {
  const v = CreateCustomerBookingRequestDraftInputSchema.parse(input);
  return callRpc(client, "create_customer_booking_request_draft", {
    p_tenant_id: v.tenantId,
    p_account_id: v.accountId,
    p_linked_quote_request_id: v.linkedQuoteRequestId ?? null,
    p_cargo_description: v.cargoDescription ?? null,
    p_pickup: v.pickup ?? {},
    p_delivery: v.delivery ?? {},
    p_requested_pickup_at: v.requestedPickupAt ?? null,
    p_requested_delivery_at: v.requestedDeliveryAt ?? null,
    p_special_instructions: v.specialInstructions ?? null,
    p_idempotency_key: v.idempotencyKey ?? null,
    p_actor_auth_user_id: v.actorAuthUserId,
    p_actor_label: v.actorLabel,
  });
}

/** Draft-only edit. Any active member of the request's own account may edit it, not only its original requester. Optimistic concurrency (stale_version). */
export async function updateCustomerBookingRequestDraft(client: CustomerBookingRequestMutationRpcClient, input: UpdateCustomerBookingRequestDraftInput): Promise<CustomerBookingRequest> {
  const v = UpdateCustomerBookingRequestDraftInputSchema.parse(input);
  return callRpc(client, "update_customer_booking_request_draft", {
    p_booking_request_id: v.bookingRequestId,
    p_expected_version: v.expectedVersion,
    p_cargo_description: v.cargoDescription ?? null,
    p_pickup: v.pickup ?? {},
    p_delivery: v.delivery ?? {},
    p_requested_pickup_at: v.requestedPickupAt ?? null,
    p_requested_delivery_at: v.requestedDeliveryAt ?? null,
    p_special_instructions: v.specialInstructions ?? null,
    p_actor_auth_user_id: v.actorAuthUserId,
    p_actor_label: v.actorLabel,
  });
}

/** draft -> submitted. Idempotent no-op if already submitted -- no separate idempotency key needed (design decision 4 of the migration). */
export async function submitCustomerBookingRequest(client: CustomerBookingRequestMutationRpcClient, input: SubmitCustomerBookingRequestInput): Promise<CustomerBookingRequest> {
  const v = SubmitCustomerBookingRequestInputSchema.parse(input);
  return callRpc(client, "submit_customer_booking_request", {
    p_booking_request_id: v.bookingRequestId,
    p_expected_version: v.expectedVersion,
    p_actor_auth_user_id: v.actorAuthUserId,
    p_actor_label: v.actorLabel,
  });
}

/** submitted or converted -> reschedule_requested. Mandatory non-empty reason and at least one new proposed pickup/delivery date/time. This is a REQUEST only -- the real schedule and any linked job/shipment order are never mutated here. */
export async function requestCustomerBookingReschedule(client: CustomerBookingRequestMutationRpcClient, input: RequestCustomerBookingRescheduleInput): Promise<CustomerBookingRequest> {
  const v = RequestCustomerBookingRescheduleInputSchema.parse(input);
  return callRpc(client, "request_customer_booking_reschedule", {
    p_booking_request_id: v.bookingRequestId,
    p_expected_version: v.expectedVersion,
    p_requested_pickup_at: v.requestedPickupAt ?? null,
    p_requested_delivery_at: v.requestedDeliveryAt ?? null,
    p_reason: v.reason,
    p_actor_auth_user_id: v.actorAuthUserId,
    p_actor_label: v.actorLabel,
  });
}

/** Mandatory non-empty reason. draft/submitted cancel directly to cancelled; converted becomes cancel_requested (staff review required once operational records exist). A terminal (cancelled/reschedule_requested/cancel_requested) request correctly refuses with invalid_transition. */
export async function requestCustomerBookingCancellation(client: CustomerBookingRequestMutationRpcClient, input: RequestCustomerBookingCancellationInput): Promise<CustomerBookingRequest> {
  const v = RequestCustomerBookingCancellationInputSchema.parse(input);
  return callRpc(client, "request_customer_booking_cancellation", {
    p_booking_request_id: v.bookingRequestId,
    p_expected_version: v.expectedVersion,
    p_reason: v.reason,
    p_actor_auth_user_id: v.actorAuthUserId,
    p_actor_label: v.actorLabel,
  });
}

/** Staff-only (OPS:Edit) conversion acknowledgement -- submitted -> converted, linkedJobOrderId/linkedShipmentOrderId set together, exactly once. Idempotent for the SAME pair; a different pair on an already-converted request is a real already_converted conflict, never a silent overwrite. */
export async function linkCustomerBookingRequestToOperationalRecords(
  client: CustomerBookingRequestMutationRpcClient,
  input: LinkCustomerBookingRequestToOperationalRecordsInput,
): Promise<CustomerBookingRequest> {
  const v = LinkCustomerBookingRequestToOperationalRecordsInputSchema.parse(input);
  return callRpc(client, "link_customer_booking_request_to_operational_records", {
    p_booking_request_id: v.bookingRequestId,
    p_job_order_id: v.jobOrderId,
    p_shipment_order_id: v.shipmentOrderId,
    p_actor_auth_user_id: v.actorAuthUserId,
    p_actor_label: v.actorLabel,
  });
}
