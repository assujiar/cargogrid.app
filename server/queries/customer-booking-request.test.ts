import { test, describe } from "node:test";
import assert from "node:assert/strict";
import { getCustomerBookingRequest, listCustomerBookingRequests, CustomerBookingRequestQueryError, type CustomerBookingRequestQueryClient } from "./customer-booking-request.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const ACCOUNT_ID = "323e4567-e89b-12d3-a456-426614174000";
const BOOKING_ID = "423e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "523e4567-e89b-12d3-a456-426614174000";

const ROW = {
  id: BOOKING_ID,
  tenant_id: TENANT_ID,
  account_id: ACCOUNT_ID,
  requested_by_auth_user_id: ACTOR_ID,
  status: "draft",
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
  record_version: 1,
  created_by: ACTOR_ID,
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

function fakeRpcClient(response: { data: unknown; error: { message: string } | null }): {
  client: CustomerBookingRequestQueryClient;
  calls: { fn: string; args: Record<string, unknown> }[];
} {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];
  const client = {
    async rpc(fn: string, args: Record<string, unknown>) {
      calls.push({ fn, args });
      return response;
    },
  } as unknown as CustomerBookingRequestQueryClient;
  return { client, calls };
}

describe("getCustomerBookingRequest", () => {
  test("maps the returned row and passes exact param names", async () => {
    const { client, calls } = fakeRpcClient({ data: [ROW], error: null });
    const result = await getCustomerBookingRequest(client, TENANT_ID, BOOKING_ID, ACTOR_ID);
    assert.equal(result.id, BOOKING_ID);
    assert.deepEqual(calls[0], {
      fn: "get_customer_booking_request",
      args: { p_tenant_id: TENANT_ID, p_booking_request_id: BOOKING_ID, p_actor_auth_user_id: ACTOR_ID },
    });
  });

  test("classifies record_not_found (anti-enumeration -- same code for nonexistent and out-of-scope)", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "record_not_found: no permitted booking request exists for x" } });
    await assert.rejects(
      () => getCustomerBookingRequest(client, TENANT_ID, BOOKING_ID, ACTOR_ID),
      (err: unknown) => {
        assert.ok(err instanceof CustomerBookingRequestQueryError);
        assert.equal(err.code, "record_not_found");
        return true;
      },
    );
  });

  test("classifies an unrecognized error prefix as query_failed", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "some_unexpected_db_error: boom" } });
    await assert.rejects(
      () => getCustomerBookingRequest(client, TENANT_ID, BOOKING_ID, ACTOR_ID),
      (err: unknown) => {
        assert.ok(err instanceof CustomerBookingRequestQueryError);
        assert.equal(err.code, "query_failed");
        return true;
      },
    );
  });
});

describe("listCustomerBookingRequests", () => {
  test("defaults cursor to null and limit to 50", async () => {
    const { client, calls } = fakeRpcClient({ data: [ROW], error: null });
    const result = await listCustomerBookingRequests(client, TENANT_ID, ACTOR_ID);
    assert.equal(result.length, 1);
    assert.deepEqual(calls[0]?.args, {
      p_tenant_id: TENANT_ID,
      p_actor_auth_user_id: ACTOR_ID,
      p_account_id: null,
      p_status: null,
      p_cursor_updated_at: null,
      p_cursor_id: null,
      p_limit: 50,
    });
  });

  test("forwards account/status filters and cursor overrides", async () => {
    const { client, calls } = fakeRpcClient({ data: [], error: null });
    await listCustomerBookingRequests(client, TENANT_ID, ACTOR_ID, { accountId: ACCOUNT_ID, status: "submitted", cursorUpdatedAt: "2026-08-16T00:00:00.000Z", cursorId: BOOKING_ID, limit: 10 });
    assert.deepEqual(calls[0]?.args, {
      p_tenant_id: TENANT_ID,
      p_actor_auth_user_id: ACTOR_ID,
      p_account_id: ACCOUNT_ID,
      p_status: "submitted",
      p_cursor_updated_at: "2026-08-16T00:00:00.000Z",
      p_cursor_id: BOOKING_ID,
      p_limit: 10,
    });
  });

  test("returns an empty array (never throws) for a deny-by-default response", async () => {
    const { client } = fakeRpcClient({ data: [], error: null });
    const result = await listCustomerBookingRequests(client, TENANT_ID, ACTOR_ID);
    assert.deepEqual(result, []);
  });
});
