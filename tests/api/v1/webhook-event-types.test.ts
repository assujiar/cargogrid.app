/** HDN-376 (API Compatibility Audit, ISS-2026-147 item 1): route-level HTTP-layer coverage for GET /api/v1/webhook-event-types. */
import { test, describe } from "node:test";
import assert from "node:assert/strict";
import { installRpcFetchStub, okAuthRow, deniedAuthRow } from "./support/rpc-fetch-stub.ts";
import { GET } from "../../../app/api/v1/webhook-event-types/route.ts";

describe("GET /api/v1/webhook-event-types", () => {
  test("missing Authorization header -> 401 unauthenticated", async () => {
    const stub = installRpcFetchStub({});
    try {
      const response = await GET(new Request("http://localhost/api/v1/webhook-event-types"));
      assert.equal(response.status, 401);
    } finally {
      stub.restore();
    }
  });

  test("a key lacking INTHUB:View scope -> 403 forbidden_scope, never reaches list_webhook_event_types", async () => {
    const stub = installRpcFetchStub({
      authenticate_and_authorize_api_request: { data: deniedAuthRow("forbidden_scope") },
    });
    try {
      const response = await GET(new Request("http://localhost/api/v1/webhook-event-types", { headers: { authorization: "Bearer cgk_test_wrong_scope" } }));
      assert.equal(response.status, 403);
      assert.equal(stub.calls.some((c) => c.fn === "list_webhook_event_types"), false);
    } finally {
      stub.restore();
    }
  });

  test("a valid key returns 200 with the documented, normal empty-registry shape (zero real domain event types seeded yet)", async () => {
    const stub = installRpcFetchStub({
      authenticate_and_authorize_api_request: { data: okAuthRow() },
      list_webhook_event_types: { data: [] },
    });
    try {
      const response = await GET(new Request("http://localhost/api/v1/webhook-event-types", { headers: { authorization: "Bearer cgk_test_valid" } }));
      assert.equal(response.status, 200);
      const body = (await response.json()) as { eventTypes: unknown[] };
      assert.deepEqual(body.eventTypes, []);
    } finally {
      stub.restore();
    }
  });

  test("a valid key with real registered event types returns them shaped {code, name, ownerPrimitiveCode}", async () => {
    const stub = installRpcFetchStub({
      authenticate_and_authorize_api_request: { data: okAuthRow() },
      list_webhook_event_types: {
        data: [{ code: "customer.booking.created", name: "Booking Created", owner_primitive_code: "IAE-010", registered_by: null, created_at: "2026-08-04T00:00:00.000Z" }],
      },
    });
    try {
      const response = await GET(new Request("http://localhost/api/v1/webhook-event-types", { headers: { authorization: "Bearer cgk_test_valid" } }));
      assert.equal(response.status, 200);
      const body = (await response.json()) as { eventTypes: Array<{ code: string; name: string; ownerPrimitiveCode: string }> };
      assert.equal(body.eventTypes.length, 1);
      assert.equal(body.eventTypes[0]?.code, "customer.booking.created");
      assert.equal(body.eventTypes[0]?.ownerPrimitiveCode, "IAE-010");
    } finally {
      stub.restore();
    }
  });
});
