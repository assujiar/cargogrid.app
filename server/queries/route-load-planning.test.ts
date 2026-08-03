import { test, describe } from "node:test";
import assert from "node:assert/strict";
import { listRoutePlanningScenarios, listRoutePlanningStops, getCanonicalPositionForPlanning, RouteLoadPlanningQueryError } from "./route-load-planning.ts";
import type { RouteLoadPlanningQueryTableClient } from "./route-load-planning.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const SHIPMENT_ID = "323e4567-e89b-12d3-a456-426614174000";
const SCENARIO_ID = "423e4567-e89b-12d3-a456-426614174000";

describe("listRoutePlanningScenarios", () => {
  test("maps rows ordered newest first", async () => {
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
            return Promise.resolve({
              data: [
                {
                  id: SCENARIO_ID,
                  tenant_id: TENANT_ID,
                  shipment_order_id: SHIPMENT_ID,
                  idempotency_key: "idem-scenario-1",
                  status: "draft",
                  requested_weight_kg: null,
                  requested_volume_cbm: null,
                  job_id: null,
                  canonical_position_snapshot: null,
                  canonical_position_captured_at: null,
                  owner_user_id: null,
                  record_version: 1,
                  created_by: null,
                  created_at: "2026-08-01T00:00:00.000Z",
                  updated_at: "2026-08-01T00:00:00.000Z",
                },
              ],
              error: null,
            });
          },
        };
      },
      async rpc() {
        throw new Error("not used in this fake");
      },
    } as unknown as RouteLoadPlanningQueryTableClient;
    const scenarios = await listRoutePlanningScenarios(client, SHIPMENT_ID);
    assert.equal(scenarios.length, 1);
    assert.equal(scenarios[0]?.status, "draft");
  });

  test("surfaces a real query error as RouteLoadPlanningQueryError", async () => {
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
    } as unknown as RouteLoadPlanningQueryTableClient;
    await assert.rejects(() => listRoutePlanningScenarios(client, SHIPMENT_ID), RouteLoadPlanningQueryError);
  });
});

describe("listRoutePlanningStops", () => {
  test("calls get_route_planning_stops and maps the GeoJSON projection", async () => {
    const client = {
      from() {
        throw new Error("not used in this fake");
      },
      async rpc(fn: string, args: Record<string, unknown>) {
        assert.equal(fn, "get_route_planning_stops");
        assert.equal(args.p_scenario_id, SCENARIO_ID);
        return {
          data: [
            {
              id: SCENARIO_ID,
              tenant_id: TENANT_ID,
              scenario_id: SCENARIO_ID,
              stop_sequence: 1,
              stop_type: "pickup",
              location_name: "Jakarta Warehouse",
              address: null,
              location_geojson: { type: "Point", coordinates: [106.8456, -6.2088] },
              time_window_start: null,
              time_window_end: null,
              created_at: "2026-08-01T00:00:00.000Z",
            },
          ],
          error: null,
        };
      },
    } as unknown as RouteLoadPlanningQueryTableClient;
    const stops = await listRoutePlanningStops(client, SCENARIO_ID);
    assert.equal(stops.length, 1);
    assert.equal(stops[0]?.longitude, 106.8456);
  });
});

describe("getCanonicalPositionForPlanning", () => {
  test("parses the honest not_tracked/unusable projection", async () => {
    const client = {
      from() {
        throw new Error("not used");
      },
      async rpc() {
        return {
          data: [
            {
              tracking_status: "not_tracked",
              freshness_status: null,
              accuracy_meters: null,
              last_position_at: null,
              authoritative_source_type: null,
              tracking_entitled: false,
              is_usable: false,
            },
          ],
          error: null,
        };
      },
    } as unknown as RouteLoadPlanningQueryTableClient;
    const position = await getCanonicalPositionForPlanning(client, SHIPMENT_ID);
    assert.equal(position?.trackingStatus, "not_tracked");
    assert.equal(position?.isUsable, false);
  });

  test("returns null when the shipment order itself does not resolve", async () => {
    const client = {
      from() {
        throw new Error("not used");
      },
      async rpc() {
        return { data: [], error: null };
      },
    } as unknown as RouteLoadPlanningQueryTableClient;
    const position = await getCanonicalPositionForPlanning(client, SHIPMENT_ID);
    assert.equal(position, null);
  });
});
