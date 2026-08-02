/**
 * Route and Load Planning Using Canonical Position mutation primitives (ATW-224,
 * CG-S10-ATW-005). Thin, typed wrappers around the RPCs in
 * supabase/migrations/20260729320000_create_advanced_tms_route_load_planning.sql.
 *
 * runNextRoutePlanningJob is the real, directly-invokable domain worker entry
 * point (app.claim_next_job -> deterministic planner -> app.complete_job /
 * app.record_job_failure under the hood) -- exposed here the same way PLT-132's
 * own claim_next_job/complete_job are exposed in ../mutations/background-job.ts,
 * even though no live continuous poller exists anywhere in this repository yet
 * (disclosed NOT_RUN, matching that module's own precedent).
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import {
  PrepareRoutePlanningScenarioInputSchema,
  AddRoutePlanningStopInputSchema,
  AddRoutePlanningConstraintInputSchema,
  ValidateRoutePlanningScenarioInputSchema,
  ExecuteRoutePlanningScenarioInputSchema,
  CancelRoutePlanningScenarioInputSchema,
  SelectRoutePlanningPlanInputSchema,
  OverrideRoutePlanningSelectionInputSchema,
  ReplanRoutePlanningScenarioInputSchema,
  RunNextRoutePlanningJobInputSchema,
  parseRoutePlanningScenario,
  parseRoutePlanningStop,
  parseRoutePlanningConstraint,
  parseRoutePlanningSelectedPlan,
  type PrepareRoutePlanningScenarioInput,
  type AddRoutePlanningStopInput,
  type AddRoutePlanningConstraintInput,
  type ValidateRoutePlanningScenarioInput,
  type ExecuteRoutePlanningScenarioInput,
  type CancelRoutePlanningScenarioInput,
  type SelectRoutePlanningPlanInput,
  type OverrideRoutePlanningSelectionInput,
  type ReplanRoutePlanningScenarioInput,
  type RunNextRoutePlanningJobInput,
  type RoutePlanningScenario,
  type RoutePlanningStop,
  type RoutePlanningConstraint,
  type RoutePlanningSelectedPlan,
} from "../contracts/route-load-planning/route-load-planning.ts";

export type RouteLoadPlanningMutationRpcClient = Pick<SupabaseClient, "rpc">;

export const ROUTE_LOAD_PLANNING_KNOWN_MUTATION_ERROR_CODES = [
  "insufficient_authority",
  "idempotency_key_required",
  "shipment_order_not_found",
  "invalid_requested_weight",
  "invalid_requested_volume",
  "invalid_stop_type",
  "invalid_sequence",
  "location_name_required",
  "scenario_not_found",
  "scenario_not_mutable",
  "invalid_constraint_type",
  "invalid_constraint_key",
  "invalid_constraint_value",
  "stale_version",
  "stops_insufficient",
  "stop_sequence_gap",
  "required_vehicle_not_found",
  "required_driver_not_found",
  "scenario_not_selectable",
  "candidate_not_found",
  "candidate_infeasible",
  "cancel_reason_required",
  "override_reason_required",
  "replan_reason_required",
  "nothing_to_replan",
] as const;
type KnownRouteLoadPlanningMutationErrorCode = (typeof ROUTE_LOAD_PLANNING_KNOWN_MUTATION_ERROR_CODES)[number];
export type RouteLoadPlanningMutationErrorCode = KnownRouteLoadPlanningMutationErrorCode | "mutation_failed" | "invalid_response";

export class RouteLoadPlanningMutationError extends Error {
  readonly code: RouteLoadPlanningMutationErrorCode;

  constructor(code: RouteLoadPlanningMutationErrorCode, message: string) {
    super(message);
    this.name = "RouteLoadPlanningMutationError";
    this.code = code;
  }
}

function classifyError(message: string): RouteLoadPlanningMutationErrorCode {
  const prefix = message.split(":")[0]?.trim();
  return (ROUTE_LOAD_PLANNING_KNOWN_MUTATION_ERROR_CODES as readonly string[]).includes(prefix ?? "")
    ? (prefix as KnownRouteLoadPlanningMutationErrorCode)
    : "mutation_failed";
}

async function callRpc(client: RouteLoadPlanningMutationRpcClient, fn: string, args: Record<string, unknown>): Promise<Record<string, unknown>> {
  const { data, error } = await client.rpc(fn, args);
  if (error) {
    throw new RouteLoadPlanningMutationError(classifyError(error.message), error.message);
  }
  if (!data || typeof data !== "object") {
    throw new RouteLoadPlanningMutationError("invalid_response", `${fn} returned no row`);
  }
  return data as Record<string, unknown>;
}

/** Idempotent on (tenantId, shipmentOrderId, idempotencyKey). Creates an empty draft scenario. */
export async function prepareRoutePlanningScenario(client: RouteLoadPlanningMutationRpcClient, input: PrepareRoutePlanningScenarioInput): Promise<RoutePlanningScenario> {
  const parsedInput = PrepareRoutePlanningScenarioInputSchema.parse(input);
  const row = await callRpc(client, "prepare_route_planning_scenario", {
    p_shipment_order_id: parsedInput.shipmentOrderId,
    p_idempotency_key: parsedInput.idempotencyKey,
    p_requested_weight_kg: parsedInput.requestedWeightKg,
    p_requested_volume_cbm: parsedInput.requestedVolumeCbm,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  return parseRoutePlanningScenario(row);
}

/** Only while the owning scenario is draft. */
export async function addRoutePlanningStop(client: RouteLoadPlanningMutationRpcClient, input: AddRoutePlanningStopInput): Promise<RoutePlanningStop> {
  const parsedInput = AddRoutePlanningStopInputSchema.parse(input);
  const row = await callRpc(client, "add_route_planning_stop", {
    p_scenario_id: parsedInput.scenarioId,
    p_stop_sequence: parsedInput.stopSequence,
    p_stop_type: parsedInput.stopType,
    p_location_name: parsedInput.locationName,
    p_address: parsedInput.address,
    p_longitude: parsedInput.longitude,
    p_latitude: parsedInput.latitude,
    p_time_window_start: parsedInput.timeWindowStart,
    p_time_window_end: parsedInput.timeWindowEnd,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  // The mutation RPC returns the raw geography-bearing row shape (not the GeoJSON
  // projection app.get_route_planning_stops provides) -- location is not surfaced
  // back on the mutation response; callers re-read via listRoutePlanningStops.
  return parseRoutePlanningStop({ ...row, location_geojson: null });
}

/** One constraint per constraint_key (upsert), only while the owning scenario is draft. */
export async function addRoutePlanningConstraint(client: RouteLoadPlanningMutationRpcClient, input: AddRoutePlanningConstraintInput): Promise<RoutePlanningConstraint> {
  const parsedInput = AddRoutePlanningConstraintInputSchema.parse(input);
  const row = await callRpc(client, "add_route_planning_constraint", {
    p_scenario_id: parsedInput.scenarioId,
    p_constraint_type: parsedInput.constraintType,
    p_constraint_key: parsedInput.constraintKey,
    p_constraint_value: parsedInput.constraintValue,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  return parseRoutePlanningConstraint(row);
}

/** Requires a contiguous 1..N stop sequence (>=2 stops); captures the canonical-position snapshot. */
export async function validateRoutePlanningScenario(client: RouteLoadPlanningMutationRpcClient, input: ValidateRoutePlanningScenarioInput): Promise<RoutePlanningScenario> {
  const parsedInput = ValidateRoutePlanningScenarioInputSchema.parse(input);
  const row = await callRpc(client, "validate_route_planning_scenario", {
    p_scenario_id: parsedInput.scenarioId,
    p_expected_version: parsedInput.expectedVersion,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  return parseRoutePlanningScenario(row);
}

/** validated -> executing. Enqueues one app.jobs row (job_type = route_load_planning). */
export async function executeRoutePlanningScenario(client: RouteLoadPlanningMutationRpcClient, input: ExecuteRoutePlanningScenarioInput): Promise<RoutePlanningScenario> {
  const parsedInput = ExecuteRoutePlanningScenarioInputSchema.parse(input);
  const row = await callRpc(client, "execute_route_planning_scenario", {
    p_scenario_id: parsedInput.scenarioId,
    p_expected_version: parsedInput.expectedVersion,
    p_idempotency_key: parsedInput.idempotencyKey,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  return parseRoutePlanningScenario(row);
}

/** Allowed from any non-terminal, non-selected status. Retains any prior selected plan on a different scenario untouched. */
export async function cancelRoutePlanningScenario(client: RouteLoadPlanningMutationRpcClient, input: CancelRoutePlanningScenarioInput): Promise<RoutePlanningScenario> {
  const parsedInput = CancelRoutePlanningScenarioInputSchema.parse(input);
  const row = await callRpc(client, "cancel_route_planning_scenario", {
    p_scenario_id: parsedInput.scenarioId,
    p_expected_version: parsedInput.expectedVersion,
    p_reason: parsedInput.reason,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  return parseRoutePlanningScenario(row);
}

/** Only a feasible candidate; an infeasible one requires overrideRoutePlanningSelection. History-preserving. */
export async function selectRoutePlanningPlan(client: RouteLoadPlanningMutationRpcClient, input: SelectRoutePlanningPlanInput): Promise<RoutePlanningSelectedPlan> {
  const parsedInput = SelectRoutePlanningPlanInputSchema.parse(input);
  const row = await callRpc(client, "select_route_planning_plan", {
    p_scenario_id: parsedInput.scenarioId,
    p_candidate_plan_id: parsedInput.candidatePlanId,
    p_expected_version: parsedInput.expectedVersion,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  return parseRoutePlanningSelectedPlan(row);
}

/** OPS:Override authority, non-empty overrideReason always required. The one path that may select an infeasible candidate. */
export async function overrideRoutePlanningSelection(client: RouteLoadPlanningMutationRpcClient, input: OverrideRoutePlanningSelectionInput): Promise<RoutePlanningSelectedPlan> {
  const parsedInput = OverrideRoutePlanningSelectionInputSchema.parse(input);
  const row = await callRpc(client, "override_route_planning_selection", {
    p_scenario_id: parsedInput.scenarioId,
    p_candidate_plan_id: parsedInput.candidatePlanId,
    p_override_reason: parsedInput.overrideReason,
    p_expected_version: parsedInput.expectedVersion,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  return parseRoutePlanningSelectedPlan(row);
}

/** Creates a fresh draft scenario copying the prior scenario's own stops/constraints. Blocked once every one of the shipment's own legs has already left planned. */
export async function replanRoutePlanningScenario(client: RouteLoadPlanningMutationRpcClient, input: ReplanRoutePlanningScenarioInput): Promise<RoutePlanningScenario> {
  const parsedInput = ReplanRoutePlanningScenarioInputSchema.parse(input);
  const row = await callRpc(client, "replan_route_planning_scenario", {
    p_scenario_id: parsedInput.scenarioId,
    p_reason: parsedInput.reason,
    p_idempotency_key: parsedInput.idempotencyKey,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  return parseRoutePlanningScenario(row);
}

/** Claims and runs the next pending route_load_planning app.jobs row, if any. Returns null when no job is due -- never throws for "no work available." */
export async function runNextRoutePlanningJob(client: RouteLoadPlanningMutationRpcClient, input: RunNextRoutePlanningJobInput): Promise<RoutePlanningScenario | null> {
  const parsedInput = RunNextRoutePlanningJobInputSchema.parse(input);
  const { data, error } = await client.rpc("run_next_route_planning_job", { p_worker_id: parsedInput.workerId });
  if (error) {
    throw new RouteLoadPlanningMutationError(classifyError(error.message), error.message);
  }
  if (data === null) {
    return null;
  }
  if (typeof data !== "object") {
    throw new RouteLoadPlanningMutationError("invalid_response", "run_next_route_planning_job returned a non-object, non-null result");
  }
  return parseRoutePlanningScenario(data as Record<string, unknown>);
}
