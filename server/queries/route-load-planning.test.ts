import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  listRoutePlanningScenarios,
  getRoutePlanningScenario,
  listRoutePlanningStops,
  listRoutePlanningConstraints,
  listRoutePlanningCandidatePlans,
  listRoutePlanningScoreComponents,
  getCurrentRoutePlanningSelection,
  listRoutePlanningSelections,
  listRoutePlanningReplanEvents,
  getCanonicalPositionForPlanning,
  RouteLoadPlanningQueryError,
} from "./route-load-planning.ts";
import type { RouteLoadPlanningQueryTableClient } from "./route-load-planning.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const SHIPMENT_ID = "323e4567-e89b-12d3-a456-426614174000";
const SCENARIO_ID = "423e4567-e89b-12d3-a456-426614174000";
const CANDIDATE_PLAN_ID = "523e4567-e89b-12d3-a456-426614174000";
const SELECTED_PLAN_ID = "623e4567-e89b-12d3-a456-426614174000";
const CONSTRAINT_ID = "723e4567-e89b-12d3-a456-426614174000";
const REPLAN_EVENT_ID = "823e4567-e89b-12d3-a456-426614174000";

const SCENARIO_ROW = {
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
};

describe("listRoutePlanningScenarios", () => {
  test("maps rows ordered newest first", async () => {
    const client = {
      from() {
        throw new Error("not used in this fake");
      },
      async rpc(fn: string, args: Record<string, unknown>) {
        assert.equal(fn, "list_route_planning_scenarios");
        assert.equal(args.p_shipment_order_id, SHIPMENT_ID);
        return { data: [SCENARIO_ROW], error: null };
      },
    } as unknown as RouteLoadPlanningQueryTableClient;
    const scenarios = await listRoutePlanningScenarios(client, SHIPMENT_ID);
    assert.equal(scenarios.length, 1);
    assert.equal(scenarios[0]?.status, "draft");
  });

  test("surfaces a real query error as RouteLoadPlanningQueryError", async () => {
    const client = {
      from() {
        throw new Error("not used");
      },
      async rpc() {
        return { data: null, error: { message: "connection reset" } };
      },
    } as unknown as RouteLoadPlanningQueryTableClient;
    await assert.rejects(() => listRoutePlanningScenarios(client, SHIPMENT_ID), RouteLoadPlanningQueryError);
  });
});

describe("getRoutePlanningScenario", () => {
  test("unwraps a one-row setof result to the parsed scenario", async () => {
    const client = {
      from() {
        throw new Error("not used in this fake");
      },
      async rpc(fn: string, args: Record<string, unknown>) {
        assert.equal(fn, "get_route_planning_scenario");
        assert.equal(args.p_scenario_id, SCENARIO_ID);
        return { data: [SCENARIO_ROW], error: null };
      },
    } as unknown as RouteLoadPlanningQueryTableClient;
    const scenario = await getRoutePlanningScenario(client, SCENARIO_ID);
    assert.equal(scenario?.id, SCENARIO_ID);
  });

  test("returns null on a genuinely empty setof result (nonexistent id or RLS denial)", async () => {
    const client = {
      from() {
        throw new Error("not used");
      },
      async rpc() {
        return { data: [], error: null };
      },
    } as unknown as RouteLoadPlanningQueryTableClient;
    const scenario = await getRoutePlanningScenario(client, SCENARIO_ID);
    assert.equal(scenario, null);
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

describe("listRoutePlanningConstraints", () => {
  test("maps every constraint row for one scenario", async () => {
    const client = {
      from() {
        throw new Error("not used in this fake");
      },
      async rpc(fn: string, args: Record<string, unknown>) {
        assert.equal(fn, "list_route_planning_constraints");
        assert.equal(args.p_scenario_id, SCENARIO_ID);
        return {
          data: [
            {
              id: CONSTRAINT_ID,
              tenant_id: TENANT_ID,
              scenario_id: SCENARIO_ID,
              constraint_type: "hard",
              constraint_key: "max_weight_kg",
              constraint_value: { max: 5000 },
              created_by: null,
              created_at: "2026-08-01T00:00:00.000Z",
            },
          ],
          error: null,
        };
      },
    } as unknown as RouteLoadPlanningQueryTableClient;
    const constraints = await listRoutePlanningConstraints(client, SCENARIO_ID);
    assert.equal(constraints.length, 1);
    assert.equal(constraints[0]?.constraintKey, "max_weight_kg");
  });
});

describe("listRoutePlanningCandidatePlans", () => {
  test("maps every candidate plan, ranked best-first", async () => {
    const client = {
      from() {
        throw new Error("not used in this fake");
      },
      async rpc(fn: string, args: Record<string, unknown>) {
        assert.equal(fn, "list_route_planning_candidate_plans");
        assert.equal(args.p_scenario_id, SCENARIO_ID);
        return {
          data: [
            {
              id: CANDIDATE_PLAN_ID,
              tenant_id: TENANT_ID,
              scenario_id: SCENARIO_ID,
              plan_rank: 1,
              algorithm_version: "v1",
              feasible: true,
              infeasibility_reasons: null,
              vehicle_master_id: null,
              driver_master_id: null,
              total_distance_km: "120.5",
              estimated_duration_minutes: 90,
              capacity_utilization_pct: "0.75",
              generated_at: "2026-08-01T00:00:00.000Z",
            },
          ],
          error: null,
        };
      },
    } as unknown as RouteLoadPlanningQueryTableClient;
    const candidates = await listRoutePlanningCandidatePlans(client, SCENARIO_ID);
    assert.equal(candidates.length, 1);
    assert.equal(candidates[0]?.planRank, 1);
  });
});

describe("listRoutePlanningScoreComponents", () => {
  test("maps every score component for one candidate plan", async () => {
    const client = {
      from() {
        throw new Error("not used in this fake");
      },
      async rpc(fn: string, args: Record<string, unknown>) {
        assert.equal(fn, "list_route_planning_score_components");
        assert.equal(args.p_candidate_plan_id, CANDIDATE_PLAN_ID);
        return {
          data: [
            {
              id: "923e4567-e89b-12d3-a456-426614174000",
              tenant_id: TENANT_ID,
              candidate_plan_id: CANDIDATE_PLAN_ID,
              component_key: "total_distance_km",
              component_value: "120.5",
              created_at: "2026-08-01T00:00:00.000Z",
            },
          ],
          error: null,
        };
      },
    } as unknown as RouteLoadPlanningQueryTableClient;
    const components = await listRoutePlanningScoreComponents(client, CANDIDATE_PLAN_ID);
    assert.equal(components.length, 1);
    assert.equal(components[0]?.componentKey, "total_distance_km");
  });
});

describe("getCurrentRoutePlanningSelection", () => {
  test("unwraps a one-row setof result to the parsed selection", async () => {
    const client = {
      from() {
        throw new Error("not used in this fake");
      },
      async rpc(fn: string, args: Record<string, unknown>) {
        assert.equal(fn, "get_current_route_planning_selection");
        assert.equal(args.p_scenario_id, SCENARIO_ID);
        return {
          data: [
            {
              id: SELECTED_PLAN_ID,
              tenant_id: TENANT_ID,
              scenario_id: SCENARIO_ID,
              candidate_plan_id: CANDIDATE_PLAN_ID,
              is_current: true,
              superseded_by_id: null,
              is_override: false,
              override_reason: null,
              selected_by: "user-1",
              selected_at: "2026-08-01T00:00:00.000Z",
            },
          ],
          error: null,
        };
      },
    } as unknown as RouteLoadPlanningQueryTableClient;
    const selection = await getCurrentRoutePlanningSelection(client, SCENARIO_ID);
    assert.equal(selection?.id, SELECTED_PLAN_ID);
    assert.equal(selection?.isCurrent, true);
  });

  test("returns null on a genuinely empty setof result (no current selection yet)", async () => {
    const client = {
      from() {
        throw new Error("not used");
      },
      async rpc() {
        return { data: [], error: null };
      },
    } as unknown as RouteLoadPlanningQueryTableClient;
    const selection = await getCurrentRoutePlanningSelection(client, SCENARIO_ID);
    assert.equal(selection, null);
  });
});

describe("listRoutePlanningSelections", () => {
  test("maps the full selection history, newest first", async () => {
    const client = {
      from() {
        throw new Error("not used in this fake");
      },
      async rpc(fn: string, args: Record<string, unknown>) {
        assert.equal(fn, "list_route_planning_selections");
        assert.equal(args.p_scenario_id, SCENARIO_ID);
        return {
          data: [
            {
              id: SELECTED_PLAN_ID,
              tenant_id: TENANT_ID,
              scenario_id: SCENARIO_ID,
              candidate_plan_id: CANDIDATE_PLAN_ID,
              is_current: true,
              superseded_by_id: null,
              is_override: false,
              override_reason: null,
              selected_by: "user-1",
              selected_at: "2026-08-01T00:00:00.000Z",
            },
          ],
          error: null,
        };
      },
    } as unknown as RouteLoadPlanningQueryTableClient;
    const selections = await listRoutePlanningSelections(client, SCENARIO_ID);
    assert.equal(selections.length, 1);
    assert.equal(selections[0]?.selectedBy, "user-1");
  });
});

describe("listRoutePlanningReplanEvents", () => {
  test("maps every replan event where this scenario is the freshly created one", async () => {
    const client = {
      from() {
        throw new Error("not used in this fake");
      },
      async rpc(fn: string, args: Record<string, unknown>) {
        assert.equal(fn, "list_route_planning_replan_events");
        assert.equal(args.p_scenario_id, SCENARIO_ID);
        return {
          data: [
            {
              id: REPLAN_EVENT_ID,
              tenant_id: TENANT_ID,
              scenario_id: SCENARIO_ID,
              previous_scenario_id: "a23e4567-e89b-12d3-a456-426614174000",
              trigger_reason: "manual",
              canonical_position_snapshot: null,
              triggered_by: "user-1",
              triggered_at: "2026-08-01T00:00:00.000Z",
            },
          ],
          error: null,
        };
      },
    } as unknown as RouteLoadPlanningQueryTableClient;
    const events = await listRoutePlanningReplanEvents(client, SCENARIO_ID);
    assert.equal(events.length, 1);
    assert.equal(events[0]?.triggerReason, "manual");
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
