/** HDN-376 (API Compatibility Audit, ISS-2026-147 item 1): route-level HTTP-layer coverage for GET /api/v1/customer/shipments/{shipmentOrderId}/tracking. */
import { test, describe } from "node:test";
import assert from "node:assert/strict";
import { installRpcFetchStub, okAuthRow, deniedAuthRow } from "./support/rpc-fetch-stub.ts";
import { GET } from "../../../app/api/v1/customer/shipments/[shipmentOrderId]/tracking/route.ts";

const SHIPMENT_ID = "88888888-8888-4888-8888-888888888888";
const params = Promise.resolve({ shipmentOrderId: SHIPMENT_ID });

describe("GET /api/v1/customer/shipments/{shipmentOrderId}/tracking", () => {
  test("missing Authorization header -> 401 unauthenticated", async () => {
    const stub = installRpcFetchStub({});
    try {
      const response = await GET(new Request(`http://localhost/api/v1/customer/shipments/${SHIPMENT_ID}/tracking`), { params });
      assert.equal(response.status, 401);
    } finally {
      stub.restore();
    }
  });

  test("a key lacking CPT:CustomerPortal scope -> 403 forbidden_scope", async () => {
    const stub = installRpcFetchStub({ authenticate_and_authorize_api_request: { data: deniedAuthRow("forbidden_scope") } });
    try {
      const response = await GET(new Request(`http://localhost/api/v1/customer/shipments/${SHIPMENT_ID}/tracking`, { headers: { authorization: "Bearer cgk_test_wrong_scope" } }), { params });
      assert.equal(response.status, 403);
    } finally {
      stub.restore();
    }
  });

  test("a shipment not found or not owned by this account -> 404 shipment_order_not_found (never leaks whether the id exists for another account) -- the real RPC's own record_not_found exception path, not an empty-array success", async () => {
    const stub = installRpcFetchStub({
      authenticate_and_authorize_api_request: { data: okAuthRow() },
      get_customer_shipment_tracking: { error: { message: "record_not_found: no permitted shipment order exists for the given id" } },
    });
    try {
      const response = await GET(new Request(`http://localhost/api/v1/customer/shipments/${SHIPMENT_ID}/tracking`, { headers: { authorization: "Bearer cgk_test_valid" } }), { params });
      assert.equal(response.status, 404);
      const body = (await response.json()) as { error: { code: string } };
      assert.equal(body.error.code, "shipment_order_not_found");
    } finally {
      stub.restore();
    }
  });

  test("HDN-376 Tier C regression: a genuine internal RPC failure is surfaced as 422 mutation_failed, never silently presented as the domain 404 not-found case", async () => {
    const stub = installRpcFetchStub({
      authenticate_and_authorize_api_request: { data: okAuthRow() },
      get_customer_shipment_tracking: { error: { message: "could not serialize access due to concurrent update" } },
    });
    try {
      const response = await GET(new Request(`http://localhost/api/v1/customer/shipments/${SHIPMENT_ID}/tracking`, { headers: { authorization: "Bearer cgk_test_valid" } }), { params });
      assert.equal(response.status, 422);
      const body = (await response.json()) as { error: { code: string } };
      assert.equal(body.error.code, "mutation_failed");
      assert.notEqual(body.error.code, "shipment_order_not_found");
    } finally {
      stub.restore();
    }
  });

  test("a genuine, owned shipment returns 200 with real tracking data", async () => {
    const stub = installRpcFetchStub({
      authenticate_and_authorize_api_request: { data: okAuthRow() },
      get_customer_shipment_tracking: {
        data: [
          {
            shipment_order_id: SHIPMENT_ID,
            milestones: [],
            tracking_entitled: true,
            position_unavailable_reason: null,
            vehicle_position_geojson: null,
            vehicle_position_updated_at: null,
            vehicle_position_status: null,
            eta_status: "on_time",
            eta_at: "2026-08-25T00:00:00.000Z",
          },
        ],
      },
    });
    try {
      const response = await GET(new Request(`http://localhost/api/v1/customer/shipments/${SHIPMENT_ID}/tracking`, { headers: { authorization: "Bearer cgk_test_valid" } }), { params });
      assert.equal(response.status, 200);
      const body = (await response.json()) as { tracking: { shipmentOrderId: string; trackingEntitled: boolean; milestones: unknown[] } };
      assert.equal(body.tracking.shipmentOrderId, SHIPMENT_ID);
      assert.equal(body.tracking.trackingEntitled, true);
      assert.equal(body.tracking.milestones.length, 0);
    } finally {
      stub.restore();
    }
  });
});
