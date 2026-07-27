import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  setShipmentModeProfile,
  changeShipmentMode,
  ShipmentModeBaselineMutationError,
  type ShipmentModeBaselineMutationRpcClient,
} from "./shipment-mode-baseline.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const PROFILE_ID = "323e4567-e89b-12d3-a456-426614174000";
const SHIPMENT_ID = "423e4567-e89b-12d3-a456-426614174000";
const JOB_ORDER_ID = "523e4567-e89b-12d3-a456-426614174000";
const ACCOUNT_ID = "623e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "723e4567-e89b-12d3-a456-426614174000";

function fakeRpcClient(response: { data: unknown; error: { message: string } | null }): {
  client: ShipmentModeBaselineMutationRpcClient;
  calls: { fn: string; args: Record<string, unknown> }[];
} {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];
  const client = {
    async rpc(fn: string, args: Record<string, unknown>) {
      calls.push({ fn, args });
      return response;
    },
  } as unknown as ShipmentModeBaselineMutationRpcClient;
  return { client, calls };
}

const LAND_PROFILE_ROW = {
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

const SHIPMENT_ROW = {
  id: SHIPMENT_ID,
  tenant_id: TENANT_ID,
  job_order_id: JOB_ORDER_ID,
  shipment_number: "SHP-2026-000001",
  idempotency_key: "idem-1",
  status: "draft",
  shipper_account_id: ACCOUNT_ID,
  consignee_snapshot: {},
  notify_party_snapshot: null,
  cargo_service_snapshot: {},
  service_type: "ocean_freight",
  mode: "air",
  origin: "Jakarta",
  destination: "Denpasar",
  planned_pickup_at: null,
  planned_delivery_at: null,
  basis_quantity: null,
  basis_weight_kg: null,
  basis_volume_cbm: null,
  allocated_quantity: null,
  allocated_weight_kg: null,
  allocated_volume_cbm: null,
  split_reason: null,
  owner_user_id: ACTOR_ID,
  org_unit_id: null,
  record_version: 2,
  created_by: "rep",
  created_at: "2026-07-27T00:00:00.000Z",
  updated_at: "2026-07-27T00:00:00.000Z",
};

describe("setShipmentModeProfile", () => {
  test("calls set_shipment_mode_profile with land fields populated and air/sea fields explicitly null", async () => {
    const { client, calls } = fakeRpcClient({ data: LAND_PROFILE_ROW, error: null });
    const profile = await setShipmentModeProfile(client, {
      shipmentOrderId: SHIPMENT_ID,
      mode: "land",
      vehicleRef: "TRK-001",
      vendorRef: "VENDOR-TRK-1",
      pickupAddress: "Jl. Gudang 1",
      deliveryAddress: "Jl. Pasar 1",
      actorAuthUserId: ACTOR_ID,
      actorLabel: "rep",
    });

    assert.equal(calls[0]?.fn, "set_shipment_mode_profile");
    assert.equal(calls[0]?.args.p_land_vehicle_ref, "TRK-001");
    assert.equal(calls[0]?.args.p_air_awb_number, null);
    assert.equal(calls[0]?.args.p_sea_bl_number, null);
    assert.equal(profile.mode, "land");
  });

  test("classifies missing_required_reference", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "missing_required_reference: land mode requires vehicle_ref, vendor_ref, pickup_address and delivery_address" } });
    await assert.rejects(
      () =>
        setShipmentModeProfile(client, {
          shipmentOrderId: SHIPMENT_ID,
          mode: "land",
          vehicleRef: "TRK-001",
          vendorRef: "VENDOR-TRK-1",
          pickupAddress: "Jl. Gudang 1",
          deliveryAddress: "Jl. Pasar 1",
          actorAuthUserId: ACTOR_ID,
          actorLabel: "rep",
        }),
      (err: unknown) => {
        assert.ok(err instanceof ShipmentModeBaselineMutationError);
        assert.equal(err.code, "missing_required_reference");
        return true;
      },
    );
  });

  test("classifies invalid_transition (a cancelled shipment)", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "invalid_transition: shipment order is cancelled and its mode profile can no longer be set" } });
    await assert.rejects(
      () =>
        setShipmentModeProfile(client, {
          shipmentOrderId: SHIPMENT_ID,
          mode: "air",
          awbNumber: "AWB-1",
          flightNumber: "GA-1",
          originAirport: "CGK",
          destinationAirport: "DPS",
          actorAuthUserId: ACTOR_ID,
          actorLabel: "rep",
        }),
      (err: unknown) => {
        assert.ok(err instanceof ShipmentModeBaselineMutationError);
        assert.equal(err.code, "invalid_transition");
        return true;
      },
    );
  });

  test("falls back to mutation_failed for an unrecognized error message", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "boom, something unrelated broke" } });
    await assert.rejects(
      () =>
        setShipmentModeProfile(client, {
          shipmentOrderId: SHIPMENT_ID,
          mode: "sea",
          blNumber: "BL-1",
          bookingNumber: "BOOK-1",
          vesselName: "MV Test",
          originPort: "IDJKT",
          destinationPort: "SGSIN",
          actorAuthUserId: ACTOR_ID,
          actorLabel: "rep",
        }),
      (err: unknown) => {
        assert.ok(err instanceof ShipmentModeBaselineMutationError);
        assert.equal(err.code, "mutation_failed");
        return true;
      },
    );
  });
});

describe("changeShipmentMode", () => {
  test("calls change_shipment_mode with the exact snake_case params", async () => {
    const { client, calls } = fakeRpcClient({ data: SHIPMENT_ROW, error: null });
    const shipment = await changeShipmentMode(client, { shipmentOrderId: SHIPMENT_ID, newMode: "air", expectedVersion: 1, actorAuthUserId: ACTOR_ID, actorLabel: "rep" });

    assert.deepEqual(calls[0]?.args, { p_shipment_order_id: SHIPMENT_ID, p_new_mode: "air", p_expected_version: 1, p_actor_auth_user_id: ACTOR_ID, p_actor_label: "rep" });
    assert.equal(shipment.mode, "air");
  });

  test("classifies confirmed_mode_change_blocked", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "confirmed_mode_change_blocked: shipment order is confirmed -- mode may only change while draft" } });
    await assert.rejects(
      () => changeShipmentMode(client, { shipmentOrderId: SHIPMENT_ID, newMode: "sea", expectedVersion: 1, actorAuthUserId: ACTOR_ID, actorLabel: "rep" }),
      (err: unknown) => {
        assert.ok(err instanceof ShipmentModeBaselineMutationError);
        assert.equal(err.code, "confirmed_mode_change_blocked");
        return true;
      },
    );
  });

  test("rejects an unsupported mode at the schema layer, before ever calling the RPC", async () => {
    const { client, calls } = fakeRpcClient({ data: SHIPMENT_ROW, error: null });
    await assert.rejects(() =>
      changeShipmentMode(client, { shipmentOrderId: SHIPMENT_ID, newMode: "rail" as never, expectedVersion: 1, actorAuthUserId: ACTOR_ID, actorLabel: "rep" }),
    );
    assert.equal(calls.length, 0);
  });
});
