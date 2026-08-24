/** HDN-376 (API Compatibility Audit, ISS-2026-147 item 1): route-level HTTP-layer coverage for POST /api/v1/customer/bookings/{bookingRequestId}/submit. */
import { test, describe } from "node:test";
import assert from "node:assert/strict";
import { installRpcFetchStub, okAuthRow, deniedAuthRow } from "./support/rpc-fetch-stub.ts";
import { POST } from "../../../app/api/v1/customer/bookings/[bookingRequestId]/submit/route.ts";

const BOOKING_ID = "66666666-6666-4666-8666-666666666666";
const params = Promise.resolve({ bookingRequestId: BOOKING_ID });

function fullBookingRow(overrides: Record<string, unknown> = {}) {
  return {
    id: BOOKING_ID,
    tenant_id: "22222222-2222-4222-8222-222222222222",
    account_id: "77777777-7777-4777-8777-777777777777",
    requested_by_auth_user_id: "33333333-3333-4333-8333-333333333333",
    status: "submitted",
    record_version: 2,
    linked_quote_request_id: null,
    cargo_description: null,
    pickup: {},
    delivery: {},
    requested_pickup_at: null,
    requested_delivery_at: null,
    special_instructions: null,
    idempotency_key: null,
    linked_job_order_id: null,
    linked_shipment_order_id: null,
    created_by: null,
    created_at: "2026-08-24T00:00:00.000Z",
    updated_at: "2026-08-24T00:00:00.000Z",
    submitted_at: "2026-08-24T00:00:00.000Z",
    cancelled_at: null,
    cancelled_reason: null,
    reschedule_requested_pickup_at: null,
    reschedule_requested_delivery_at: null,
    reschedule_reason: null,
    reschedule_requested_at: null,
    ...overrides,
  };
}

describe("POST /api/v1/customer/bookings/{bookingRequestId}/submit", () => {
  test("missing Authorization header -> 401 unauthenticated", async () => {
    const stub = installRpcFetchStub({});
    try {
      const response = await POST(new Request(`http://localhost/api/v1/customer/bookings/${BOOKING_ID}/submit`, { method: "POST", body: "{}" }), { params });
      assert.equal(response.status, 401);
    } finally {
      stub.restore();
    }
  });

  test("malformed expectedVersion (missing) -> 400 invalid_expected_version, never reaches the mutation RPC (HDN-376 Defect B regression: previously the wrong code stale_version, indistinguishable from a real 409 conflict)", async () => {
    const stub = installRpcFetchStub({ authenticate_and_authorize_api_request: { data: okAuthRow() } });
    try {
      const response = await POST(new Request(`http://localhost/api/v1/customer/bookings/${BOOKING_ID}/submit`, { method: "POST", headers: { authorization: "Bearer cgk_test_valid" }, body: "{}" }), { params });
      assert.equal(response.status, 400);
      const body = (await response.json()) as { error: { code: string } };
      assert.equal(body.error.code, "invalid_expected_version");
      assert.equal(stub.calls.some((c) => c.fn === "submit_customer_booking_request"), false);
    } finally {
      stub.restore();
    }
  });

  test("malformed expectedVersion (zero/negative) -> 400 invalid_expected_version", async () => {
    const stub = installRpcFetchStub({ authenticate_and_authorize_api_request: { data: okAuthRow() } });
    try {
      const response = await POST(
        new Request(`http://localhost/api/v1/customer/bookings/${BOOKING_ID}/submit`, { method: "POST", headers: { authorization: "Bearer cgk_test_valid" }, body: JSON.stringify({ expectedVersion: -1 }) }),
        { params },
      );
      assert.equal(response.status, 400);
    } finally {
      stub.restore();
    }
  });

  test("a genuine optimistic-concurrency conflict -> 409 stale_version, distinct HTTP class from the 400 malformed-input case (HDN-376 Defect B: these two must never share one error code)", async () => {
    const stub = installRpcFetchStub({
      authenticate_and_authorize_api_request: { data: okAuthRow() },
      submit_customer_booking_request: { error: { message: "stale_version: booking request expected version 2 but found 3" } },
    });
    try {
      const response = await POST(
        new Request(`http://localhost/api/v1/customer/bookings/${BOOKING_ID}/submit`, { method: "POST", headers: { authorization: "Bearer cgk_test_valid" }, body: JSON.stringify({ expectedVersion: 2 }) }),
        { params },
      );
      assert.equal(response.status, 409);
      const body = (await response.json()) as { error: { code: string } };
      assert.equal(body.error.code, "stale_version");
    } finally {
      stub.restore();
    }
  });

  test("a valid submit returns 200 with the updated booking", async () => {
    const stub = installRpcFetchStub({
      authenticate_and_authorize_api_request: { data: okAuthRow() },
      submit_customer_booking_request: { data: [fullBookingRow()] },
    });
    try {
      const response = await POST(
        new Request(`http://localhost/api/v1/customer/bookings/${BOOKING_ID}/submit`, { method: "POST", headers: { authorization: "Bearer cgk_test_valid" }, body: JSON.stringify({ expectedVersion: 1 }) }),
        { params },
      );
      assert.equal(response.status, 200);
      const body = (await response.json()) as { booking: { status: string } };
      assert.equal(body.booking.status, "submitted");
    } finally {
      stub.restore();
    }
  });
});
