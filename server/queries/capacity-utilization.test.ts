import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  listCapacityReservationsForLeg,
  listActiveCapacityReservationsForVehicle,
  getTenantTrackingCoverage,
  getTenantTrackingUtilizationSummary,
  CapacityUtilizationQueryError,
  type CapacityUtilizationQueryClient,
} from "./capacity-utilization.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const LEG_ID = "323e4567-e89b-12d3-a456-426614174000";
const VEHICLE_ID = "423e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "623e4567-e89b-12d3-a456-426614174000";

function fakeRpcClient(response: { data: unknown; error: { message: string } | null }): CapacityUtilizationQueryClient {
  return {
    rpc: async () => response,
    from() {
      throw new Error("not used in this fake");
    },
  } as unknown as CapacityUtilizationQueryClient;
}

function fakeTableClient(response: { data: unknown; error: { message: string } | null }): {
  client: CapacityUtilizationQueryClient;
  calls: { table: string; eqCalls: [string, unknown][]; inCalls: [string, unknown][] }[];
} {
  const calls: { table: string; eqCalls: [string, unknown][]; inCalls: [string, unknown][] }[] = [];
  const client = {
    from(table: string) {
      const record = { table, eqCalls: [] as [string, unknown][], inCalls: [] as [string, unknown][] };
      calls.push(record);
      const builder = {
        select() {
          return this;
        },
        eq(column: string, value: unknown) {
          record.eqCalls.push([column, value]);
          return this;
        },
        in(column: string, value: unknown) {
          record.inCalls.push([column, value]);
          return this;
        },
        order() {
          return response;
        },
      };
      return builder;
    },
    rpc() {
      throw new Error("not used in this fake");
    },
  } as unknown as CapacityUtilizationQueryClient;
  return { client, calls };
}

const RESERVATION_ROW = {
  id: "823e4567-e89b-12d3-a456-426614174000",
  tenant_id: TENANT_ID,
  shipment_leg_id: LEG_ID,
  vehicle_master_id: VEHICLE_ID,
  idempotency_key: "leg-1-reserve",
  requested_weight_kg: 1200,
  requested_volume_cbm: 8,
  window_start: "2026-08-03T00:00:00.000Z",
  window_end: "2026-08-04T00:00:00.000Z",
  status: "held",
  released_reason: null,
  record_version: 1,
  created_by: "dispatcher",
  created_at: "2026-08-03T00:00:00.000Z",
  updated_at: "2026-08-03T00:00:00.000Z",
};

describe("listCapacityReservationsForLeg", () => {
  test("filters by shipment_leg_id and parses rows", async () => {
    const { client, calls } = fakeTableClient({ data: [RESERVATION_ROW], error: null });
    const reservations = await listCapacityReservationsForLeg(client, LEG_ID);
    assert.equal(reservations.length, 1);
    assert.equal(reservations[0]?.shipmentLegId, LEG_ID);
    assert.deepEqual(calls[0]?.eqCalls, [["shipment_leg_id", LEG_ID]]);
  });

  test("returns an empty array when no reservation exists", async () => {
    const { client } = fakeTableClient({ data: null, error: null });
    const reservations = await listCapacityReservationsForLeg(client, LEG_ID);
    assert.deepEqual(reservations, []);
  });

  test("throws on a query error", async () => {
    const { client } = fakeTableClient({ data: null, error: { message: "boom" } });
    await assert.rejects(() => listCapacityReservationsForLeg(client, LEG_ID), CapacityUtilizationQueryError);
  });
});

describe("listActiveCapacityReservationsForVehicle", () => {
  test("filters by vehicle_master_id and held/consumed status", async () => {
    const { client, calls } = fakeTableClient({ data: [RESERVATION_ROW], error: null });
    const reservations = await listActiveCapacityReservationsForVehicle(client, VEHICLE_ID);
    assert.equal(reservations.length, 1);
    assert.deepEqual(calls[0]?.eqCalls, [["vehicle_master_id", VEHICLE_ID]]);
    assert.deepEqual(calls[0]?.inCalls, [["status", ["held", "consumed"]]]);
  });
});

describe("getTenantTrackingCoverage", () => {
  test("parses an array of coverage rows", async () => {
    const client = fakeRpcClient({
      data: [
        {
          vehicle_master_id: VEHICLE_ID,
          vehicle_code: "VEH-001",
          vehicle_name: "Box Truck 001",
          source_class: "hybrid",
          coverage_status: "tracked",
          authoritative_source_type: "direct_device",
          last_position_at: "2026-08-03T00:05:00.000Z",
          has_active_provider_mapping: true,
          capacity_weight_kg: 5000,
          capacity_volume_cbm: 30,
          reserved_weight_kg: 1200,
          reserved_volume_cbm: 8,
        },
      ],
      error: null,
    });
    const rows = await getTenantTrackingCoverage(client, TENANT_ID, ACTOR_ID);
    assert.equal(rows.length, 1);
    assert.equal(rows[0]?.coverageStatus, "tracked");
  });

  test("returns an empty array when the tenant has zero active vehicles", async () => {
    const client = fakeRpcClient({ data: [], error: null });
    const rows = await getTenantTrackingCoverage(client, TENANT_ID, ACTOR_ID);
    assert.deepEqual(rows, []);
  });

  test("throws on an insufficient_authority rpc error", async () => {
    const client = fakeRpcClient({ data: null, error: { message: "insufficient_authority: identity lacks OPS:View" } });
    await assert.rejects(() => getTenantTrackingCoverage(client, TENANT_ID, ACTOR_ID), CapacityUtilizationQueryError);
  });
});

describe("getTenantTrackingUtilizationSummary", () => {
  test("parses a scalar composite-type response", async () => {
    const client = fakeRpcClient({
      data: {
        tracking_enabled: true,
        package_code: "standard",
        max_tracked_vehicles: 50,
        max_mobile_sessions: 20,
        total_active_vehicle_count: 10,
        tracked_vehicle_count: 6,
        stale_vehicle_count: 1,
        offline_vehicle_count: 2,
        not_tracked_vehicle_count: 1,
        tracked_vehicle_limit_remaining: 44,
        device_total_count: 8,
        device_active_count: 6,
        mobile_session_active_count: 3,
        untracked_required_leg_count: 0,
      },
      error: null,
    });
    const summary = await getTenantTrackingUtilizationSummary(client, TENANT_ID, ACTOR_ID);
    assert.equal(summary.trackedVehicleCount, 6);
    assert.equal(summary.trackedVehicleLimitRemaining, 44);
  });

  test("throws when no row is returned", async () => {
    const client = fakeRpcClient({ data: null, error: null });
    await assert.rejects(() => getTenantTrackingUtilizationSummary(client, TENANT_ID, ACTOR_ID), CapacityUtilizationQueryError);
  });
});
