/** HDN-376 (API Compatibility Audit, ISS-2026-147 item 1): route-level HTTP-layer coverage for POST /api/v1/customer/bookings. */
import { test, describe } from "node:test";
import assert from "node:assert/strict";
import { installRpcFetchStub, okAuthRow, deniedAuthRow } from "./support/rpc-fetch-stub.ts";
import { POST } from "../../../app/api/v1/customer/bookings/route.ts";

const VALID_AUTH = { authorization: "Bearer cgk_test_valid", "idempotency-key": "idem-key-001", "content-type": "application/json" };

describe("POST /api/v1/customer/bookings", () => {
  test("missing Authorization header -> 401 unauthenticated", async () => {
    const stub = installRpcFetchStub({});
    try {
      const response = await POST(new Request("http://localhost/api/v1/customer/bookings", { method: "POST", body: "{}" }));
      assert.equal(response.status, 401);
    } finally {
      stub.restore();
    }
  });

  test("missing Idempotency-Key header -> 400 missing_idempotency_key (HDN-376 Defect A regression: previously the wrong-domain code webhook_missing_idempotency_key)", async () => {
    const stub = installRpcFetchStub({ authenticate_and_authorize_api_request: { data: okAuthRow() } });
    try {
      const response = await POST(new Request("http://localhost/api/v1/customer/bookings", { method: "POST", headers: { authorization: "Bearer cgk_test_valid" }, body: "{}" }));
      assert.equal(response.status, 400);
      const body = (await response.json()) as { error: { code: string } };
      assert.equal(body.error.code, "missing_idempotency_key");
    } finally {
      stub.restore();
    }
  });

  test("a key lacking CPT:CustomerPortal scope -> 403 forbidden_scope, never reaches the mutation RPC", async () => {
    const stub = installRpcFetchStub({ authenticate_and_authorize_api_request: { data: deniedAuthRow("forbidden_scope") } });
    try {
      const response = await POST(new Request("http://localhost/api/v1/customer/bookings", { method: "POST", headers: VALID_AUTH, body: "{}" }));
      assert.equal(response.status, 403);
      assert.equal(stub.calls.some((c) => c.fn === "create_customer_booking_request_draft"), false);
    } finally {
      stub.restore();
    }
  });

  test("a forged/unowned accountId -> 422 account_not_available, real RPC error code surfaced in the response body", async () => {
    const stub = installRpcFetchStub({
      authenticate_and_authorize_api_request: { data: okAuthRow() },
      create_customer_booking_request_draft: { error: { message: "account_not_available: account does not belong to this identity's resolved scope" } },
    });
    try {
      const response = await POST(new Request("http://localhost/api/v1/customer/bookings", { method: "POST", headers: VALID_AUTH, body: JSON.stringify({ accountId: "99999999-9999-4999-8999-999999999999" }) }));
      assert.equal(response.status, 422);
      const body = (await response.json()) as { error: { code: string } };
      assert.equal(body.error.code, "account_not_available");
    } finally {
      stub.restore();
    }
  });

  test("malformed JSON body is tolerated (falls through to an empty body, not a 500)", async () => {
    const stub = installRpcFetchStub({
      authenticate_and_authorize_api_request: { data: okAuthRow() },
      create_customer_booking_request_draft: { error: { message: "invalid_input: accountId is required" } },
    });
    try {
      const response = await POST(new Request("http://localhost/api/v1/customer/bookings", { method: "POST", headers: VALID_AUTH, body: "{not valid json" }));
      assert.equal(response.status, 422);
    } finally {
      stub.restore();
    }
  });

  test("a valid request returns 201 with the created draft, and the real idempotency key is forwarded to the RPC", async () => {
    const stub = installRpcFetchStub({
      authenticate_and_authorize_api_request: { data: okAuthRow() },
      create_customer_booking_request_draft: {
        data: [
          {
            id: "66666666-6666-4666-8666-666666666666",
            tenant_id: "22222222-2222-4222-8222-222222222222",
            account_id: "77777777-7777-4777-8777-777777777777",
            requested_by_auth_user_id: "33333333-3333-4333-8333-333333333333",
            status: "draft",
            record_version: 1,
            linked_quote_request_id: null,
            cargo_description: null,
            pickup: {},
            delivery: {},
            requested_pickup_at: null,
            requested_delivery_at: null,
            special_instructions: null,
            idempotency_key: "idem-key-001",
            linked_job_order_id: null,
            linked_shipment_order_id: null,
            created_by: null,
            created_at: "2026-08-24T00:00:00.000Z",
            updated_at: "2026-08-24T00:00:00.000Z",
            submitted_at: null,
            cancelled_at: null,
            cancelled_reason: null,
            reschedule_requested_pickup_at: null,
            reschedule_requested_delivery_at: null,
            reschedule_reason: null,
            reschedule_requested_at: null,
          },
        ],
      },
    });
    try {
      const response = await POST(
        new Request("http://localhost/api/v1/customer/bookings", { method: "POST", headers: VALID_AUTH, body: JSON.stringify({ accountId: "77777777-7777-4777-8777-777777777777" }) }),
      );
      assert.equal(response.status, 201);
      const body = (await response.json()) as { booking: { id: string; status: string } };
      assert.equal(body.booking.status, "draft");
      const mutationCall = stub.calls.find((c) => c.fn === "create_customer_booking_request_draft");
      assert.equal(mutationCall?.body.p_idempotency_key, "idem-key-001");
    } finally {
      stub.restore();
    }
  });
});
