/**
 * Route and Load Planning Using Canonical Position read queries (ATW-224,
 * CG-S10-ATW-005). CG-AUDIT-2026-09-02 O1 remediation (cluster 3 batch 3,
 * 20260911030000_close_o1_query_layer_cluster3_batch3_route_planning.sql):
 * every read in this file now goes through a thin, security-invoker RPC
 * wrapper (app is not exposed to PostgREST, so a `.from()` call against any
 * `app.*` table has never worked in production) -- scenarios, constraints,
 * candidate plans, score components, selections, and replan events via that
 * migration, plus the pre-existing app.get_route_planning_stops (a computed
 * GeoJSON projection) and app.get_canonical_position_for_planning (a computed
 * projection over app.shipment_tracking_health).
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import {
  parseRoutePlanningScenario,
  parseRoutePlanningStop,
  parseRoutePlanningConstraint,
  parseRoutePlanningCandidatePlan,
  parseRoutePlanningScoreComponent,
  parseRoutePlanningSelectedPlan,
  parseRoutePlanningReplanEvent,
  parseCanonicalPositionForPlanning,
  type RoutePlanningScenario,
  type RoutePlanningStop,
  type RoutePlanningConstraint,
  type RoutePlanningCandidatePlan,
  type RoutePlanningScoreComponent,
  type RoutePlanningSelectedPlan,
  type RoutePlanningReplanEvent,
  type CanonicalPositionForPlanning,
} from "../contracts/route-load-planning/route-load-planning.ts";

export type RouteLoadPlanningQueryTableClient = Pick<SupabaseClient, "from" | "rpc">;

export class RouteLoadPlanningQueryError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "RouteLoadPlanningQueryError";
  }
}

/** Every planning scenario for one Shipment Order, newest first. */
export async function listRoutePlanningScenarios(client: RouteLoadPlanningQueryTableClient, shipmentOrderId: string): Promise<RoutePlanningScenario[]> {
  const { data, error } = await client.rpc("list_route_planning_scenarios", { p_shipment_order_id: shipmentOrderId });
  if (error) {
    throw new RouteLoadPlanningQueryError(error.message);
  }
  return (data ?? []).map((row: Record<string, unknown>) => parseRoutePlanningScenario(row));
}

export async function getRoutePlanningScenario(client: RouteLoadPlanningQueryTableClient, scenarioId: string): Promise<RoutePlanningScenario | null> {
  const { data, error } = await client.rpc("get_route_planning_scenario", { p_scenario_id: scenarioId });
  if (error) {
    throw new RouteLoadPlanningQueryError(error.message);
  }
  const row = Array.isArray(data) ? data[0] : data;
  return row ? parseRoutePlanningScenario(row as Record<string, unknown>) : null;
}

/** Every stop for one scenario, ordered by stop_sequence ascending, with location serialized as GeoJSON. */
export async function listRoutePlanningStops(client: RouteLoadPlanningQueryTableClient, scenarioId: string): Promise<RoutePlanningStop[]> {
  const { data, error } = await client.rpc("get_route_planning_stops", { p_scenario_id: scenarioId });
  if (error) {
    throw new RouteLoadPlanningQueryError(error.message);
  }
  return (data ?? []).map((row: Record<string, unknown>) => parseRoutePlanningStop(row));
}

/** Every constraint for one scenario. */
export async function listRoutePlanningConstraints(client: RouteLoadPlanningQueryTableClient, scenarioId: string): Promise<RoutePlanningConstraint[]> {
  const { data, error } = await client.rpc("list_route_planning_constraints", { p_scenario_id: scenarioId });
  if (error) {
    throw new RouteLoadPlanningQueryError(error.message);
  }
  return (data ?? []).map((row: Record<string, unknown>) => parseRoutePlanningConstraint(row));
}

/** Every candidate plan for one scenario, ranked best-first -- the "compare" read (Prompt 224 §14). */
export async function listRoutePlanningCandidatePlans(client: RouteLoadPlanningQueryTableClient, scenarioId: string): Promise<RoutePlanningCandidatePlan[]> {
  const { data, error } = await client.rpc("list_route_planning_candidate_plans", { p_scenario_id: scenarioId });
  if (error) {
    throw new RouteLoadPlanningQueryError(error.message);
  }
  return (data ?? []).map((row: Record<string, unknown>) => parseRoutePlanningCandidatePlan(row));
}

/** The explainability breakdown for one candidate plan. */
export async function listRoutePlanningScoreComponents(client: RouteLoadPlanningQueryTableClient, candidatePlanId: string): Promise<RoutePlanningScoreComponent[]> {
  const { data, error } = await client.rpc("list_route_planning_score_components", { p_candidate_plan_id: candidatePlanId });
  if (error) {
    throw new RouteLoadPlanningQueryError(error.message);
  }
  return (data ?? []).map((row: Record<string, unknown>) => parseRoutePlanningScoreComponent(row));
}

/** The current selection for one scenario, if any human decision has been recorded yet. */
export async function getCurrentRoutePlanningSelection(client: RouteLoadPlanningQueryTableClient, scenarioId: string): Promise<RoutePlanningSelectedPlan | null> {
  const { data, error } = await client.rpc("get_current_route_planning_selection", { p_scenario_id: scenarioId });
  if (error) {
    throw new RouteLoadPlanningQueryError(error.message);
  }
  const row = Array.isArray(data) ? data[0] : data;
  return row ? parseRoutePlanningSelectedPlan(row as Record<string, unknown>) : null;
}

/** Full selection history for one scenario, newest first (never overwritten in place -- is_current/superseded_by_id). */
export async function listRoutePlanningSelections(client: RouteLoadPlanningQueryTableClient, scenarioId: string): Promise<RoutePlanningSelectedPlan[]> {
  const { data, error } = await client.rpc("list_route_planning_selections", { p_scenario_id: scenarioId });
  if (error) {
    throw new RouteLoadPlanningQueryError(error.message);
  }
  return (data ?? []).map((row: Record<string, unknown>) => parseRoutePlanningSelectedPlan(row));
}

/** Replan lineage for one scenario (rows where this scenario is the freshly created one). */
export async function listRoutePlanningReplanEvents(client: RouteLoadPlanningQueryTableClient, scenarioId: string): Promise<RoutePlanningReplanEvent[]> {
  const { data, error } = await client.rpc("list_route_planning_replan_events", { p_scenario_id: scenarioId });
  if (error) {
    throw new RouteLoadPlanningQueryError(error.message);
  }
  return (data ?? []).map((row: Record<string, unknown>) => parseRoutePlanningReplanEvent(row));
}

/** The one canonical-position read path for planning (Prompt 224 §6/§14). Honest: reports not_tracked/unusable until ATW-226F ships a live writer. */
export async function getCanonicalPositionForPlanning(client: RouteLoadPlanningQueryTableClient, shipmentOrderId: string): Promise<CanonicalPositionForPlanning | null> {
  const { data, error } = await client.rpc("get_canonical_position_for_planning", { p_shipment_order_id: shipmentOrderId });
  if (error) {
    throw new RouteLoadPlanningQueryError(error.message);
  }
  const rows = (data ?? []) as Record<string, unknown>[];
  const row = rows[0];
  if (!row) {
    return null;
  }
  return parseCanonicalPositionForPlanning(row);
}
