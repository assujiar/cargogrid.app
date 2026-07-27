import { test, describe } from "node:test";
import assert from "node:assert/strict";
import { getShipmentModeProfile, ShipmentModeBaselineQueryError, type ShipmentModeBaselineQueryTableClient } from "./shipment-mode-baseline.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const PROFILE_ID = "323e4567-e89b-12d3-a456-426614174000";
const SHIPMENT_ID = "423e4567-e89b-12d3-a456-426614174000";

const LAND_ROW = {
  id: PROFILE_ID,
  tenant_id: TENANT_ID,
  shipment_order_id: SHIPMENT_ID,
  mode: "land",
  land_vehicle_ref: "TRK-001",
  land_vendor_ref: "VENDOR-TRK-1",
  land_pickup_address: "Jl. Gudang 1",
  land_delivery_address: "Jl. Pasar 1",
  air_awb_number: null,
  air_flight_number: null,
  air_origin_airport: null,
  air_destination_airport: null,
  sea_bl_number: null,
  sea_booking_number: null,
  sea_vessel_name: null,
  sea_origin_port: null,
  sea_destination_port: null,
  sea_container_number: null,
  sea_container_type: null,
  record_version: 1,
  created_by: "rep",
  created_at: "2026-07-27T00:00:00.000Z",
  updated_at: "2026-07-27T00:00:00.000Z",
};

function fakeTableClient(response: { data: unknown; error: { message: string } | null }): ShipmentModeBaselineQueryTableClient {
  return {
    from: () => ({
      select: () => ({
        eq: () => ({
          maybeSingle: () => Promise.resolve(response),
        }),
      }),
    }),
  } as unknown as ShipmentModeBaselineQueryTableClient;
}

describe("getShipmentModeProfile", () => {
  test("returns null (never an error) when no profile has been set yet or RLS excludes it", async () => {
    const client = fakeTableClient({ data: null, error: null });
    const profile = await getShipmentModeProfile(client, SHIPMENT_ID);
    assert.equal(profile, null);
  });

  test("maps a land profile", async () => {
    const client = fakeTableClient({ data: LAND_ROW, error: null });
    const profile = await getShipmentModeProfile(client, SHIPMENT_ID);
    assert.equal(profile?.mode, "land");
  });

  test("wraps a query error", async () => {
    const client = fakeTableClient({ data: null, error: { message: "boom" } });
    await assert.rejects(
      () => getShipmentModeProfile(client, SHIPMENT_ID),
      (err: unknown) => err instanceof ShipmentModeBaselineQueryError,
    );
  });
});
