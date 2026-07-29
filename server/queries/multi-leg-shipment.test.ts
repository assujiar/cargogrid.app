import { test, describe } from "node:test";
import assert from "node:assert/strict";
import { listShipmentLegs, listShipmentLegStops, getShipmentLegNetworkState, MultiLegShipmentQueryError } from "./multi-leg-shipment.ts";
import type { MultiLegShipmentQueryTableClient } from "./multi-leg-shipment.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const SHIPMENT_ID = "323e4567-e89b-12d3-a456-426614174000";
const LEG_ID = "423e4567-e89b-12d3-a456-426614174000";

function fakeFromClient(rows: Record<string, unknown>[]): MultiLegShipmentQueryTableClient {
  return {
    from() {
      return {
        select() {
          return this;
        },
        eq() {
          return this;
        },
        order() {
          return Promise.resolve({ data: rows, error: null });
        },
      };
    },
    async rpc() {
      throw new Error("not used in this fake");
    },
  } as unknown as MultiLegShipmentQueryTableClient;
}

describe("listShipmentLegs", () => {
  test("maps rows ordered by sequence_no", async () => {
    const client = fakeFromClient([
      {
        id: LEG_ID,
        tenant_id: TENANT_ID,
        shipment_order_id: SHIPMENT_ID,
        sequence_no: 1,
        idempotency_key: "idem-1",
        mode: "land",
        leg_status: "planned",
        is_legacy_compat: false,
        carrier_master_id: null,
        planned_departure_at: null,
        planned_arrival_at: null,
        actual_departure_at: null,
        actual_arrival_at: null,
        owner_user_id: null,
        record_version: 1,
        created_by: null,
        created_at: "2026-07-29T00:00:00.000Z",
        updated_at: "2026-07-29T00:00:00.000Z",
      },
    ]);
    const legs = await listShipmentLegs(client, SHIPMENT_ID);
    assert.equal(legs.length, 1);
    assert.equal(legs[0]?.sequenceNo, 1);
  });

  test("surfaces a real query error as MultiLegShipmentQueryError", async () => {
    const client = {
      from() {
        return {
          select() {
            return this;
          },
          eq() {
            return this;
          },
          order() {
            return Promise.resolve({ data: null, error: { message: "connection reset" } });
          },
        };
      },
      async rpc() {
        throw new Error("not used");
      },
    } as unknown as MultiLegShipmentQueryTableClient;
    await assert.rejects(() => listShipmentLegs(client, SHIPMENT_ID), MultiLegShipmentQueryError);
  });
});

describe("listShipmentLegStops", () => {
  test("calls get_shipment_leg_stops and maps the GeoJSON projection", async () => {
    const client = {
      from() {
        throw new Error("not used in this fake");
      },
      async rpc(fn: string, args: Record<string, unknown>) {
        assert.equal(fn, "get_shipment_leg_stops");
        assert.equal(args.p_shipment_leg_id, LEG_ID);
        return {
          data: [
            {
              id: LEG_ID,
              tenant_id: TENANT_ID,
              shipment_leg_id: LEG_ID,
              stop_sequence: 1,
              stop_type: "pickup",
              location_name: "Jakarta Warehouse",
              address: null,
              location_geojson: { type: "Point", coordinates: [106.8456, -6.2088] },
              planned_at: null,
              actual_at: null,
              stop_status: "pending",
              record_version: 1,
              created_at: "2026-07-29T00:00:00.000Z",
              updated_at: "2026-07-29T00:00:00.000Z",
            },
          ],
          error: null,
        };
      },
    } as unknown as MultiLegShipmentQueryTableClient;
    const stops = await listShipmentLegStops(client, LEG_ID);
    assert.equal(stops.length, 1);
    assert.equal(stops[0]?.longitude, 106.8456);
  });
});

describe("getShipmentLegNetworkState", () => {
  test("parses the returned aggregate state", async () => {
    const client = {
      from() {
        throw new Error("not used");
      },
      async rpc() {
        return { data: "in_progress", error: null };
      },
    } as unknown as MultiLegShipmentQueryTableClient;
    const state = await getShipmentLegNetworkState(client, SHIPMENT_ID);
    assert.equal(state, "in_progress");
  });
});
