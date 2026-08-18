import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  createCustomerBookingRequestDraft,
  updateCustomerBookingRequestDraft,
  submitCustomerBookingRequest,
  requestCustomerBookingReschedule,
  requestCustomerBookingCancellation,
  linkCustomerBookingRequestToOperationalRecords,
  CustomerBookingRequestMutationError,
  type CustomerBookingRequestMutationRpcClient,
} from "./customer-booking-request.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const ACCOUNT_ID = "323e4567-e89b-12d3-a456-426614174000";
const BOOKING_ID = "423e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "523e4567-e89b-12d3-a456-426614174000";
const JOB_ORDER_ID = "623e4567-e89b-12d3-a456-426614174000";
const SHIPMENT_ORDER_ID = "723e4567-e89b-12d3-a456-426614174000";

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
  idempotency_key: "create-1",
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
  client: CustomerBookingRequestMutationRpcClient;
  calls: { fn: string; args: Record<string, unknown> }[];
} {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];
  const client = {
    async rpc(fn: string, args: Record<string, unknown>) {
      calls.push({ fn, args });
      return response;
    },
  } as unknown as CustomerBookingRequestMutationRpcClient;
  return { client, calls };
}

describe("createCustomerBookingRequestDraft", () => {
  test("passes exact param names, defaulting pickup/delivery to {} and optional fields to null", async () => {
    const { client, calls } = fakeRpcClient({ data: [ROW], error: null });
    const result = await createCustomerBookingRequestDraft(client, { tenantId: TENANT_ID, accountId: ACCOUNT_ID, idempotencyKey: "create-1", actorAuthUserId: ACTOR_ID, actorLabel: "alpha-admin" });
    assert.equal(result.status, "draft");
    assert.deepEqual(calls[0], {
      fn: "create_customer_booking_request_draft",
      args: {
        p_tenant_id: TENANT_ID,
        p_account_id: ACCOUNT_ID,
        p_linked_quote_request_id: null,
        p_cargo_description: null,
        p_pickup: {},
        p_delivery: {},
        p_requested_pickup_at: null,
        p_requested_delivery_at: null,
        p_special_instructions: null,
        p_idempotency_key: "create-1",
        p_actor_auth_user_id: ACTOR_ID,
        p_actor_label: "alpha-admin",
      },
    });
  });

  test("classifies account_not_available for a forged/unowned account", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "account_not_available: x is not an account this identity may book a shipment for" } });
    await assert.rejects(
      () => createCustomerBookingRequestDraft(client, { tenantId: TENANT_ID, accountId: ACCOUNT_ID, actorAuthUserId: ACTOR_ID, actorLabel: "x" }),
      (err: unknown) => {
        assert.ok(err instanceof CustomerBookingRequestMutationError);
        assert.equal(err.code, "account_not_available");
        return true;
      },
    );
  });

  test("classifies quote_request_not_accepted for a still-draft linked quote request", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "quote_request_not_accepted: quote request x is draft and is not yet an accepted quotation" } });
    await assert.rejects(
      () => createCustomerBookingRequestDraft(client, { tenantId: TENANT_ID, accountId: ACCOUNT_ID, linkedQuoteRequestId: BOOKING_ID, actorAuthUserId: ACTOR_ID, actorLabel: "x" }),
      (err: unknown) => {
        assert.ok(err instanceof CustomerBookingRequestMutationError);
        assert.equal(err.code, "quote_request_not_accepted");
        return true;
      },
    );
  });
});

describe("updateCustomerBookingRequestDraft", () => {
  test("passes exact param names", async () => {
    const { client, calls } = fakeRpcClient({ data: [ROW], error: null });
    await updateCustomerBookingRequestDraft(client, { bookingRequestId: BOOKING_ID, expectedVersion: 1, cargoDescription: "General cargo", actorAuthUserId: ACTOR_ID, actorLabel: "alpha-member" });
    assert.deepEqual(calls[0]?.args, {
      p_booking_request_id: BOOKING_ID,
      p_expected_version: 1,
      p_cargo_description: "General cargo",
      p_pickup: {},
      p_delivery: {},
      p_requested_pickup_at: null,
      p_requested_delivery_at: null,
      p_special_instructions: null,
      p_actor_auth_user_id: ACTOR_ID,
      p_actor_label: "alpha-member",
    });
  });

  test("classifies stale_version", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "stale_version: booking request x expected version 1 but found 2" } });
    await assert.rejects(
      () => updateCustomerBookingRequestDraft(client, { bookingRequestId: BOOKING_ID, expectedVersion: 1, actorAuthUserId: ACTOR_ID, actorLabel: "x" }),
      (err: unknown) => {
        assert.ok(err instanceof CustomerBookingRequestMutationError);
        assert.equal(err.code, "stale_version");
        return true;
      },
    );
  });
});

describe("submitCustomerBookingRequest", () => {
  test("passes exact param names", async () => {
    const { client, calls } = fakeRpcClient({ data: [{ ...ROW, status: "submitted" }], error: null });
    const result = await submitCustomerBookingRequest(client, { bookingRequestId: BOOKING_ID, expectedVersion: 1, actorAuthUserId: ACTOR_ID, actorLabel: "alpha-admin" });
    assert.equal(result.status, "submitted");
    assert.deepEqual(calls[0], {
      fn: "submit_customer_booking_request",
      args: { p_booking_request_id: BOOKING_ID, p_expected_version: 1, p_actor_auth_user_id: ACTOR_ID, p_actor_label: "alpha-admin" },
    });
  });

  test("classifies invalid_transition", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "invalid_transition: booking request x is cancelled and cannot be submitted" } });
    await assert.rejects(
      () => submitCustomerBookingRequest(client, { bookingRequestId: BOOKING_ID, expectedVersion: 1, actorAuthUserId: ACTOR_ID, actorLabel: "x" }),
      (err: unknown) => {
        assert.ok(err instanceof CustomerBookingRequestMutationError);
        assert.equal(err.code, "invalid_transition");
        return true;
      },
    );
  });
});

describe("requestCustomerBookingReschedule", () => {
  test("passes exact param names", async () => {
    const { client, calls } = fakeRpcClient({ data: [{ ...ROW, status: "reschedule_requested" }], error: null });
    const result = await requestCustomerBookingReschedule(client, {
      bookingRequestId: BOOKING_ID,
      expectedVersion: 1,
      requestedPickupAt: "2026-09-05T08:00:00.000Z",
      reason: "warehouse delay",
      actorAuthUserId: ACTOR_ID,
      actorLabel: "alpha-admin",
    });
    assert.equal(result.status, "reschedule_requested");
    assert.deepEqual(calls[0], {
      fn: "request_customer_booking_reschedule",
      args: {
        p_booking_request_id: BOOKING_ID,
        p_expected_version: 1,
        p_requested_pickup_at: "2026-09-05T08:00:00.000Z",
        p_requested_delivery_at: null,
        p_reason: "warehouse delay",
        p_actor_auth_user_id: ACTOR_ID,
        p_actor_label: "alpha-admin",
      },
    });
  });

  test("rejects when neither new date is supplied at the schema layer before any RPC call", async () => {
    const { client, calls } = fakeRpcClient({ data: null, error: null });
    await assert.rejects(() => requestCustomerBookingReschedule(client, { bookingRequestId: BOOKING_ID, expectedVersion: 1, reason: "x", actorAuthUserId: ACTOR_ID, actorLabel: "x" }));
    assert.equal(calls.length, 0);
  });

  test("classifies invalid_transition for a draft booking (reschedule requires submitted/converted)", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "invalid_transition: booking request x is draft and cannot be rescheduled" } });
    await assert.rejects(
      () =>
        requestCustomerBookingReschedule(client, {
          bookingRequestId: BOOKING_ID,
          expectedVersion: 1,
          requestedPickupAt: "2026-09-05T08:00:00.000Z",
          reason: "x",
          actorAuthUserId: ACTOR_ID,
          actorLabel: "x",
        }),
      (err: unknown) => {
        assert.ok(err instanceof CustomerBookingRequestMutationError);
        assert.equal(err.code, "invalid_transition");
        return true;
      },
    );
  });
});

describe("requestCustomerBookingCancellation", () => {
  test("passes exact param names", async () => {
    const { client, calls } = fakeRpcClient({ data: [{ ...ROW, status: "cancelled", cancelled_reason: "no longer needed" }], error: null });
    const result = await requestCustomerBookingCancellation(client, { bookingRequestId: BOOKING_ID, expectedVersion: 1, reason: "no longer needed", actorAuthUserId: ACTOR_ID, actorLabel: "alpha-admin" });
    assert.equal(result.status, "cancelled");
    assert.deepEqual(calls[0], {
      fn: "request_customer_booking_cancellation",
      args: { p_booking_request_id: BOOKING_ID, p_expected_version: 1, p_reason: "no longer needed", p_actor_auth_user_id: ACTOR_ID, p_actor_label: "alpha-admin" },
    });
  });

  test("rejects an empty reason at the schema layer before any RPC call", async () => {
    const { client, calls } = fakeRpcClient({ data: null, error: null });
    await assert.rejects(() => requestCustomerBookingCancellation(client, { bookingRequestId: BOOKING_ID, expectedVersion: 1, reason: "", actorAuthUserId: ACTOR_ID, actorLabel: "x" }));
    assert.equal(calls.length, 0);
  });

  test("classifies a converted booking's cancellation as cancel_requested (not cancelled)", async () => {
    const { client } = fakeRpcClient({ data: [{ ...ROW, status: "cancel_requested", cancelled_reason: "customer request" }], error: null });
    const result = await requestCustomerBookingCancellation(client, { bookingRequestId: BOOKING_ID, expectedVersion: 3, reason: "customer request", actorAuthUserId: ACTOR_ID, actorLabel: "x" });
    assert.equal(result.status, "cancel_requested");
  });
});

describe("linkCustomerBookingRequestToOperationalRecords", () => {
  test("passes exact param names", async () => {
    const { client, calls } = fakeRpcClient({ data: [{ ...ROW, status: "converted", linked_job_order_id: JOB_ORDER_ID, linked_shipment_order_id: SHIPMENT_ORDER_ID }], error: null });
    const result = await linkCustomerBookingRequestToOperationalRecords(client, {
      bookingRequestId: BOOKING_ID,
      jobOrderId: JOB_ORDER_ID,
      shipmentOrderId: SHIPMENT_ORDER_ID,
      actorAuthUserId: ACTOR_ID,
      actorLabel: "operations-staff",
    });
    assert.equal(result.status, "converted");
    assert.equal(result.linkedJobOrderId, JOB_ORDER_ID);
    assert.equal(result.linkedShipmentOrderId, SHIPMENT_ORDER_ID);
    assert.deepEqual(calls[0], {
      fn: "link_customer_booking_request_to_operational_records",
      args: { p_booking_request_id: BOOKING_ID, p_job_order_id: JOB_ORDER_ID, p_shipment_order_id: SHIPMENT_ORDER_ID, p_actor_auth_user_id: ACTOR_ID, p_actor_label: "operations-staff" },
    });
  });

  test("classifies insufficient_authority for a staff actor lacking OPS:Edit", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "insufficient_authority: identity x lacks OPS:Edit (no_granting_role) for tenant y" } });
    await assert.rejects(
      () =>
        linkCustomerBookingRequestToOperationalRecords(client, { bookingRequestId: BOOKING_ID, jobOrderId: JOB_ORDER_ID, shipmentOrderId: SHIPMENT_ORDER_ID, actorAuthUserId: ACTOR_ID, actorLabel: "x" }),
      (err: unknown) => {
        assert.ok(err instanceof CustomerBookingRequestMutationError);
        assert.equal(err.code, "insufficient_authority");
        return true;
      },
    );
  });

  test("classifies already_converted for re-linking to a different pair", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "already_converted: booking request x is already linked to job order y/shipment order z, not a/b" } });
    await assert.rejects(
      () =>
        linkCustomerBookingRequestToOperationalRecords(client, { bookingRequestId: BOOKING_ID, jobOrderId: JOB_ORDER_ID, shipmentOrderId: SHIPMENT_ORDER_ID, actorAuthUserId: ACTOR_ID, actorLabel: "x" }),
      (err: unknown) => {
        assert.ok(err instanceof CustomerBookingRequestMutationError);
        assert.equal(err.code, "already_converted");
        return true;
      },
    );
  });
});
