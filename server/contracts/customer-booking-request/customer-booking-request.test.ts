import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  parseCustomerBookingRequest,
  CustomerBookingRequestCursorSchema,
  CreateCustomerBookingRequestDraftInputSchema,
  RequestCustomerBookingRescheduleInputSchema,
  BOOKING_REQUEST_STATUSES,
} from "./customer-booking-request.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const ACCOUNT_ID = "323e4567-e89b-12d3-a456-426614174000";
const BOOKING_ID = "423e4567-e89b-12d3-a456-426614174000";
const AUTH_USER_ID = "523e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "623e4567-e89b-12d3-a456-426614174000";

const ROW = {
  id: BOOKING_ID,
  tenant_id: TENANT_ID,
  account_id: ACCOUNT_ID,
  requested_by_auth_user_id: AUTH_USER_ID,
  status: "draft",
  linked_quote_request_id: null,
  cargo_description: "General cargo",
  pickup: { label: "Jakarta warehouse" },
  delivery: { label: "Surabaya port" },
  requested_pickup_at: "2026-09-01T08:00:00.000Z",
  requested_delivery_at: "2026-09-10T08:00:00.000Z",
  special_instructions: "Handle with care",
  idempotency_key: "create-1",
  linked_job_order_id: null,
  linked_shipment_order_id: null,
  record_version: 1,
  created_by: AUTH_USER_ID,
  created_at: "2026-08-16T00:00:00.000Z",
  updated_at: "2026-08-16T00:00:00.000Z",
  submitted_at: null,
  cancelled_at: null,
  cancelled_reason: null,
  reschedule_requested_pickup_at: null,
  reschedule_requested_delivery_at: null,
  reschedule_reason: null,
  reschedule_requested_at: null,
};

describe("parseCustomerBookingRequest", () => {
  test("maps every column, camelCased", () => {
    const parsed = parseCustomerBookingRequest(ROW);
    assert.equal(parsed.id, BOOKING_ID);
    assert.equal(parsed.accountId, ACCOUNT_ID);
    assert.equal(parsed.status, "draft");
    assert.deepEqual(parsed.pickup, { label: "Jakarta warehouse" });
    assert.equal(parsed.linkedQuoteRequestId, null);
    assert.equal(parsed.linkedJobOrderId, null);
  });

  test("defaults missing pickup/delivery to an empty object, nullable fields to null", () => {
    const parsed = parseCustomerBookingRequest({ ...ROW, pickup: undefined, delivery: undefined, cargo_description: undefined });
    assert.deepEqual(parsed.pickup, {});
    assert.deepEqual(parsed.delivery, {});
    assert.equal(parsed.cargoDescription, null);
  });

  test("rejects an unrecognized status", () => {
    assert.throws(() => parseCustomerBookingRequest({ ...ROW, status: "not_a_real_status" }));
  });

  test("every real status is exactly the migration's 6-value set", () => {
    assert.deepEqual([...BOOKING_REQUEST_STATUSES], ["draft", "submitted", "reschedule_requested", "cancel_requested", "cancelled", "converted"]);
  });

  test("maps a converted row's linked job/shipment order ids", () => {
    const parsed = parseCustomerBookingRequest({ ...ROW, status: "converted", linked_job_order_id: BOOKING_ID, linked_shipment_order_id: ACCOUNT_ID });
    assert.equal(parsed.linkedJobOrderId, BOOKING_ID);
    assert.equal(parsed.linkedShipmentOrderId, ACCOUNT_ID);
  });
});

describe("CustomerBookingRequestCursorSchema", () => {
  test("accepts an empty cursor (first page)", () => {
    assert.doesNotThrow(() => CustomerBookingRequestCursorSchema.parse({}));
  });

  test("rejects a cursorId supplied without cursorUpdatedAt", () => {
    assert.throws(() => CustomerBookingRequestCursorSchema.parse({ cursorId: BOOKING_ID }));
  });
});

describe("CreateCustomerBookingRequestDraftInputSchema", () => {
  test("accepts a minimal input with every optional field omitted", () => {
    const parsed = CreateCustomerBookingRequestDraftInputSchema.parse({ tenantId: TENANT_ID, accountId: ACCOUNT_ID, actorAuthUserId: ACTOR_ID, actorLabel: "alpha-admin" });
    assert.equal(parsed.tenantId, TENANT_ID);
  });

  test("rejects a non-uuid accountId", () => {
    assert.throws(() => CreateCustomerBookingRequestDraftInputSchema.parse({ tenantId: TENANT_ID, accountId: "not-a-uuid", actorAuthUserId: ACTOR_ID, actorLabel: "x" }));
  });

  test("accepts a linkedQuoteRequestId", () => {
    const parsed = CreateCustomerBookingRequestDraftInputSchema.parse({ tenantId: TENANT_ID, accountId: ACCOUNT_ID, linkedQuoteRequestId: BOOKING_ID, actorAuthUserId: ACTOR_ID, actorLabel: "x" });
    assert.equal(parsed.linkedQuoteRequestId, BOOKING_ID);
  });
});

describe("RequestCustomerBookingRescheduleInputSchema", () => {
  test("requires at least one of requestedPickupAt/requestedDeliveryAt", () => {
    assert.throws(() =>
      RequestCustomerBookingRescheduleInputSchema.parse({ bookingRequestId: BOOKING_ID, expectedVersion: 1, reason: "delay", actorAuthUserId: ACTOR_ID, actorLabel: "x" }),
    );
  });

  test("accepts a real reschedule input with only a new pickup date", () => {
    const parsed = RequestCustomerBookingRescheduleInputSchema.parse({
      bookingRequestId: BOOKING_ID,
      expectedVersion: 1,
      requestedPickupAt: "2026-09-05T08:00:00.000Z",
      reason: "delay",
      actorAuthUserId: ACTOR_ID,
      actorLabel: "x",
    });
    assert.equal(parsed.requestedPickupAt, "2026-09-05T08:00:00.000Z");
  });

  test("rejects an empty reason", () => {
    assert.throws(() =>
      RequestCustomerBookingRescheduleInputSchema.parse({
        bookingRequestId: BOOKING_ID,
        expectedVersion: 1,
        requestedPickupAt: "2026-09-05T08:00:00.000Z",
        reason: "",
        actorAuthUserId: ACTOR_ID,
        actorLabel: "x",
      }),
    );
  });
});
