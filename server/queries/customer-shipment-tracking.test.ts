import { test, describe } from "node:test";
import assert from "node:assert/strict";
import { getCustomerShipmentTracking, CustomerShipmentTrackingQueryError, type CustomerShipmentTrackingQueryClient } from "./customer-shipment-tracking.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const SHIPMENT_ID = "423e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "623e4567-e89b-12d3-a456-426614174000";

const TRACKING_ROW = {
  shipment_order_id: SHIPMENT_ID,
  milestones: [],
  tracking_entitled: true,
  position_unavailable_reason: "no_active_leg",
  vehicle_position_geojson: null,
  vehicle_position_updated_at: null,
  vehicle_position_status: null,
  eta_status: null,
  eta_at: null,
};

function fakeRpcClient(response: { data: unknown; error: { message: string } | null }): {
  client: CustomerShipmentTrackingQueryClient;
  calls: { fn: string; args: Record<string, unknown> }[];
} {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];
  const client = {
    async rpc(fn: string, args: Record<string, unknown>) {
      calls.push({ fn, args });
      return response;
    },
  } as unknown as CustomerShipmentTrackingQueryClient;
  return { client, calls };
}

describe("getCustomerShipmentTracking", () => {
  test("maps a single-object response (the RPC returns a composite row, not a set) and passes exact param names", async () => {
    const { client, calls } = fakeRpcClient({ data: TRACKING_ROW, error: null });
    const result = await getCustomerShipmentTracking(client, TENANT_ID, ACTOR_ID, SHIPMENT_ID);
    assert.equal(result.shipmentOrderId, SHIPMENT_ID);
    assert.equal(result.positionUnavailableReason, "no_active_leg");
    assert.deepEqual(calls[0], {
      fn: "get_customer_shipment_tracking",
      args: { p_tenant_id: TENANT_ID, p_actor_auth_user_id: ACTOR_ID, p_shipment_order_id: SHIPMENT_ID },
    });
  });

  test("also accepts an array-wrapped response (PostgREST array shape), taking the first row", async () => {
    const { client } = fakeRpcClient({ data: [TRACKING_ROW], error: null });
    const result = await getCustomerShipmentTracking(client, TENANT_ID, ACTOR_ID, SHIPMENT_ID);
    assert.equal(result.shipmentOrderId, SHIPMENT_ID);
  });

  test("classifies record_not_found (anti-enumeration -- same code for nonexistent and out-of-scope)", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "record_not_found: no permitted shipment order exists for x" } });
    await assert.rejects(
      () => getCustomerShipmentTracking(client, TENANT_ID, ACTOR_ID, SHIPMENT_ID),
      (err: unknown) => {
        assert.ok(err instanceof CustomerShipmentTrackingQueryError);
        assert.equal(err.code, "record_not_found");
        return true;
      },
    );
  });

  test("classifies actor_identity_mismatch", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "actor_identity_mismatch: session identity does not match the claimed actor" } });
    await assert.rejects(
      () => getCustomerShipmentTracking(client, TENANT_ID, ACTOR_ID, SHIPMENT_ID),
      (err: unknown) => {
        assert.ok(err instanceof CustomerShipmentTrackingQueryError);
        assert.equal(err.code, "actor_identity_mismatch");
        return true;
      },
    );
  });

  test("classifies an unrecognized error prefix as query_failed", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "some_unexpected_db_error: boom" } });
    await assert.rejects(
      () => getCustomerShipmentTracking(client, TENANT_ID, ACTOR_ID, SHIPMENT_ID),
      (err: unknown) => {
        assert.ok(err instanceof CustomerShipmentTrackingQueryError);
        assert.equal(err.code, "query_failed");
        return true;
      },
    );
  });

  test("throws query_failed when the RPC returns no row at all", async () => {
    const { client } = fakeRpcClient({ data: null, error: null });
    await assert.rejects(() => getCustomerShipmentTracking(client, TENANT_ID, ACTOR_ID, SHIPMENT_ID), (err: unknown) => {
      assert.ok(err instanceof CustomerShipmentTrackingQueryError);
      assert.equal(err.code, "query_failed");
      return true;
    });
  });
});
