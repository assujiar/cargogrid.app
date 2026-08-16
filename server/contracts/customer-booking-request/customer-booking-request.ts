/**
 * Customer Booking Request contract (CPL-303, CG-S13-CPL-005, Prompt 303).
 * Mirrors supabase/migrations/20260801040000_create_customer_portal_booking_
 * requests.sql's RPC surface: app.create_customer_booking_request_draft/app.
 * update_customer_booking_request_draft/app.submit_customer_booking_request/
 * app.request_customer_booking_reschedule/app.request_customer_booking_
 * cancellation/app.get_customer_booking_request/app.list_customer_booking_
 * requests/app.link_customer_booking_request_to_operational_records.
 *
 * This is a portal-owned REQUEST for a booking -- never a canonical job
 * order or shipment order itself (ADR-0024 Part B). `pickup`/`delivery` are
 * bounded, free-form address+contact SNAPSHOTS (no canonical address/contact
 * master exists yet, the migration's own design decision 2) -- reuses the
 * same permissive shape server/contracts/customer-quote-request/customer-
 * quote-request.ts's own QuoteLocationSchema established.
 */

import { z } from "zod";

export const BOOKING_REQUEST_STATUSES = ["draft", "submitted", "reschedule_requested", "cancel_requested", "cancelled", "converted"] as const;
export const BookingRequestStatusSchema = z.enum(BOOKING_REQUEST_STATUSES);
export type BookingRequestStatus = z.infer<typeof BookingRequestStatusSchema>;

/** A bounded, free-form address+contact snapshot -- never a canonical address/contact master (no such master exists yet, migration design decision 2). Every field optional; unrecognized keys pass through unchanged. */
export const BookingLocationSchema = z
  .object({
    label: z.string().optional(),
    addressLine: z.string().optional(),
    city: z.string().optional(),
    country: z.string().optional(),
    contactName: z.string().optional(),
    contactPhone: z.string().optional(),
    contactEmail: z.string().optional(),
  })
  .catchall(z.unknown());
export type BookingLocation = z.infer<typeof BookingLocationSchema>;

// --- Row schema ---

export const CustomerBookingRequestSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  accountId: z.string().uuid(),
  requestedByAuthUserId: z.string().uuid(),
  status: BookingRequestStatusSchema,
  linkedQuoteRequestId: z.string().uuid().nullable(),
  cargoDescription: z.string().nullable(),
  pickup: z.record(z.string(), z.unknown()),
  delivery: z.record(z.string(), z.unknown()),
  requestedPickupAt: z.string().nullable(),
  requestedDeliveryAt: z.string().nullable(),
  specialInstructions: z.string().nullable(),
  idempotencyKey: z.string().nullable(),
  linkedJobOrderId: z.string().uuid().nullable(),
  linkedShipmentOrderId: z.string().uuid().nullable(),
  recordVersion: z.number().int().positive(),
  createdBy: z.string().nullable(),
  createdAt: z.string(),
  updatedAt: z.string(),
  submittedAt: z.string().nullable(),
  cancelledAt: z.string().nullable(),
  cancelledReason: z.string().nullable(),
  rescheduleRequestedPickupAt: z.string().nullable(),
  rescheduleRequestedDeliveryAt: z.string().nullable(),
  rescheduleReason: z.string().nullable(),
  rescheduleRequestedAt: z.string().nullable(),
});
export type CustomerBookingRequest = z.infer<typeof CustomerBookingRequestSchema>;

export function parseCustomerBookingRequest(row: Record<string, unknown>): CustomerBookingRequest {
  return CustomerBookingRequestSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    accountId: row.account_id,
    requestedByAuthUserId: row.requested_by_auth_user_id,
    status: row.status,
    linkedQuoteRequestId: row.linked_quote_request_id ?? null,
    cargoDescription: row.cargo_description ?? null,
    pickup: row.pickup ?? {},
    delivery: row.delivery ?? {},
    requestedPickupAt: row.requested_pickup_at ?? null,
    requestedDeliveryAt: row.requested_delivery_at ?? null,
    specialInstructions: row.special_instructions ?? null,
    idempotencyKey: row.idempotency_key ?? null,
    linkedJobOrderId: row.linked_job_order_id ?? null,
    linkedShipmentOrderId: row.linked_shipment_order_id ?? null,
    recordVersion: row.record_version,
    createdBy: row.created_by ?? null,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
    submittedAt: row.submitted_at ?? null,
    cancelledAt: row.cancelled_at ?? null,
    cancelledReason: row.cancelled_reason ?? null,
    rescheduleRequestedPickupAt: row.reschedule_requested_pickup_at ?? null,
    rescheduleRequestedDeliveryAt: row.reschedule_requested_delivery_at ?? null,
    rescheduleReason: row.reschedule_reason ?? null,
    rescheduleRequestedAt: row.reschedule_requested_at ?? null,
  });
}

// --- Cursor pagination ---

/** The (timestamp, id) keyset pair app.list_customer_booking_requests accepts -- never OFFSET. Mirrors server/contracts/customer-quote-request's own CustomerQuoteRequestCursorSchema exactly. */
export const CustomerBookingRequestCursorSchema = z
  .object({
    cursorUpdatedAt: z.string().nullable().optional(),
    cursorId: z.string().uuid().nullable().optional(),
  })
  .refine((cursor) => !cursor.cursorId || !!cursor.cursorUpdatedAt, {
    message: "cursorUpdatedAt is required when cursorId is supplied",
    path: ["cursorUpdatedAt"],
  });
export type CustomerBookingRequestCursor = z.input<typeof CustomerBookingRequestCursorSchema>;

// --- Mutation input schemas ---

const locationInputShape = z.union([BookingLocationSchema, z.record(z.string(), z.unknown())]).nullable().optional();

export const CreateCustomerBookingRequestDraftInputSchema = z.object({
  tenantId: z.string().uuid(),
  accountId: z.string().uuid(),
  linkedQuoteRequestId: z.string().uuid().nullable().optional(),
  cargoDescription: z.string().nullable().optional(),
  pickup: locationInputShape,
  delivery: locationInputShape,
  requestedPickupAt: z.string().nullable().optional(),
  requestedDeliveryAt: z.string().nullable().optional(),
  specialInstructions: z.string().nullable().optional(),
  idempotencyKey: z.string().nullable().optional(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type CreateCustomerBookingRequestDraftInput = z.input<typeof CreateCustomerBookingRequestDraftInputSchema>;

export const UpdateCustomerBookingRequestDraftInputSchema = z.object({
  bookingRequestId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  cargoDescription: z.string().nullable().optional(),
  pickup: locationInputShape,
  delivery: locationInputShape,
  requestedPickupAt: z.string().nullable().optional(),
  requestedDeliveryAt: z.string().nullable().optional(),
  specialInstructions: z.string().nullable().optional(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type UpdateCustomerBookingRequestDraftInput = z.input<typeof UpdateCustomerBookingRequestDraftInputSchema>;

export const SubmitCustomerBookingRequestInputSchema = z.object({
  bookingRequestId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type SubmitCustomerBookingRequestInput = z.input<typeof SubmitCustomerBookingRequestInputSchema>;

export const RequestCustomerBookingRescheduleInputSchema = z
  .object({
    bookingRequestId: z.string().uuid(),
    expectedVersion: z.number().int().positive(),
    requestedPickupAt: z.string().nullable().optional(),
    requestedDeliveryAt: z.string().nullable().optional(),
    reason: z.string().min(1),
    actorAuthUserId: z.string().uuid(),
    actorLabel: z.string().min(1),
  })
  .refine((v) => !!v.requestedPickupAt || !!v.requestedDeliveryAt, {
    message: "at least one of requestedPickupAt or requestedDeliveryAt is required",
    path: ["requestedPickupAt"],
  });
export type RequestCustomerBookingRescheduleInput = z.input<typeof RequestCustomerBookingRescheduleInputSchema>;

export const RequestCustomerBookingCancellationInputSchema = z.object({
  bookingRequestId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  reason: z.string().min(1),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type RequestCustomerBookingCancellationInput = z.input<typeof RequestCustomerBookingCancellationInputSchema>;

export const LinkCustomerBookingRequestToOperationalRecordsInputSchema = z.object({
  bookingRequestId: z.string().uuid(),
  jobOrderId: z.string().uuid(),
  shipmentOrderId: z.string().uuid(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type LinkCustomerBookingRequestToOperationalRecordsInput = z.input<typeof LinkCustomerBookingRequestToOperationalRecordsInputSchema>;
