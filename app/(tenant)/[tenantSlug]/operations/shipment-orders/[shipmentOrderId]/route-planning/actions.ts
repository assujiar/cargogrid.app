"use server";

/**
 * Route and Load Planning Server Actions (ATW-224, CG-S10-ATW-005). One action per
 * governed RPC -- prepare/add-stop/add-constraint/validate/execute/run-planner/
 * select/override/replan/cancel -- mirroring the shipment-order detail page's own
 * per-mutation action convention.
 *
 * runPlannerAction directly invokes app.run_next_route_planning_job. No live
 * continuous worker process exists in this serverless deployment (disclosed
 * NOT_RUN, matching the migration's own header and ../../../../../../../server/
 * mutations/background-job.ts's identical precedent for the generic job queue) --
 * this button is this checkpoint's own honest stand-in for that worker, run
 * on demand by an authorized planner rather than polled automatically.
 */

import { revalidatePath } from "next/cache";
import { randomUUID } from "node:crypto";
import { createSupabaseServerClient } from "../../../../../../../lib/supabase/server.ts";
import { resolveOperationsAccessForRequest } from "../../../../../../../lib/portal/resolve-operations-access.server.ts";
import {
  prepareRoutePlanningScenario,
  addRoutePlanningStop,
  addRoutePlanningConstraint,
  validateRoutePlanningScenario,
  executeRoutePlanningScenario,
  runNextRoutePlanningJob,
  cancelRoutePlanningScenario,
  selectRoutePlanningPlan,
  overrideRoutePlanningSelection,
  replanRoutePlanningScenario,
  RouteLoadPlanningMutationError,
} from "../../../../../../../server/mutations/route-load-planning.ts";
import type { RoutePlanningConstraintKey, RoutePlanningConstraintType, RoutePlanningStopType } from "../../../../../../../server/contracts/route-load-planning/route-load-planning.ts";

export interface RoutePlanningFormState {
  readonly error: string | null;
}

function revalidateWorkspace(tenantSlug: string, shipmentOrderId: string) {
  revalidatePath(`/${tenantSlug}/operations/shipment-orders/${shipmentOrderId}/route-planning`);
}

export async function prepareRoutePlanningScenarioAction(
  tenantSlug: string,
  shipmentOrderId: string,
  _prevState: RoutePlanningFormState,
  formData: FormData,
): Promise<RoutePlanningFormState> {
  const access = await resolveOperationsAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    return { error: "You don't have access to this organization's Operations workspace." };
  }

  const requestedWeightRaw = String(formData.get("requestedWeightKg") ?? "").trim();
  const requestedVolumeRaw = String(formData.get("requestedVolumeCbm") ?? "").trim();

  const supabase = await createSupabaseServerClient();
  try {
    await prepareRoutePlanningScenario(supabase, {
      shipmentOrderId,
      idempotencyKey: randomUUID(),
      requestedWeightKg: requestedWeightRaw.length === 0 ? null : Number(requestedWeightRaw),
      requestedVolumeCbm: requestedVolumeRaw.length === 0 ? null : Number(requestedVolumeRaw),
      actorAuthUserId: access.authUserId,
      actorLabel: access.authUserId,
    });
  } catch (error) {
    if (error instanceof RouteLoadPlanningMutationError) {
      return { error: `Could not prepare a planning scenario: ${error.message}` };
    }
    throw error;
  }

  revalidateWorkspace(tenantSlug, shipmentOrderId);
  return { error: null };
}

export async function addRoutePlanningStopAction(
  tenantSlug: string,
  shipmentOrderId: string,
  scenarioId: string,
  _prevState: RoutePlanningFormState,
  formData: FormData,
): Promise<RoutePlanningFormState> {
  const access = await resolveOperationsAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    return { error: "You don't have access to this organization's Operations workspace." };
  }

  const stopSequence = Number(formData.get("stopSequence") ?? 0);
  const stopType = String(formData.get("stopType") ?? "") as RoutePlanningStopType;
  const locationName = String(formData.get("locationName") ?? "");
  const address = String(formData.get("address") ?? "").trim();
  const longitudeRaw = String(formData.get("longitude") ?? "").trim();
  const latitudeRaw = String(formData.get("latitude") ?? "").trim();
  const timeWindowStartRaw = String(formData.get("timeWindowStart") ?? "").trim();
  const timeWindowEndRaw = String(formData.get("timeWindowEnd") ?? "").trim();

  const supabase = await createSupabaseServerClient();
  try {
    await addRoutePlanningStop(supabase, {
      scenarioId,
      stopSequence,
      stopType,
      locationName,
      address: address.length === 0 ? null : address,
      longitude: longitudeRaw.length === 0 ? null : Number(longitudeRaw),
      latitude: latitudeRaw.length === 0 ? null : Number(latitudeRaw),
      timeWindowStart: timeWindowStartRaw.length === 0 ? null : new Date(timeWindowStartRaw).toISOString(),
      timeWindowEnd: timeWindowEndRaw.length === 0 ? null : new Date(timeWindowEndRaw).toISOString(),
      actorAuthUserId: access.authUserId,
      actorLabel: access.authUserId,
    });
  } catch (error) {
    if (error instanceof RouteLoadPlanningMutationError) {
      return { error: `Could not add this stop: ${error.message}` };
    }
    throw error;
  }

  revalidateWorkspace(tenantSlug, shipmentOrderId);
  return { error: null };
}

export async function addRoutePlanningConstraintAction(
  tenantSlug: string,
  shipmentOrderId: string,
  scenarioId: string,
  _prevState: RoutePlanningFormState,
  formData: FormData,
): Promise<RoutePlanningFormState> {
  const access = await resolveOperationsAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    return { error: "You don't have access to this organization's Operations workspace." };
  }

  const constraintType = String(formData.get("constraintType") ?? "") as RoutePlanningConstraintType;
  const constraintKey = String(formData.get("constraintKey") ?? "") as RoutePlanningConstraintKey;
  const rawValue = String(formData.get("value") ?? "").trim();

  let constraintValue: Record<string, unknown>;
  if (constraintKey === "required_vehicle_master_id" || constraintKey === "required_driver_master_id") {
    constraintValue = { master_id: rawValue };
  } else if (constraintKey === "earliest_departure_at" || constraintKey === "latest_arrival_at") {
    constraintValue = { at: rawValue.length === 0 ? null : new Date(rawValue).toISOString() };
  } else {
    constraintValue = { value: Number(rawValue) };
  }

  const supabase = await createSupabaseServerClient();
  try {
    await addRoutePlanningConstraint(supabase, { scenarioId, constraintType, constraintKey, constraintValue, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof RouteLoadPlanningMutationError) {
      return { error: `Could not add this constraint: ${error.message}` };
    }
    throw error;
  }

  revalidateWorkspace(tenantSlug, shipmentOrderId);
  return { error: null };
}

export async function validateRoutePlanningScenarioAction(
  tenantSlug: string,
  shipmentOrderId: string,
  scenarioId: string,
  expectedVersion: number,
  _prevState: RoutePlanningFormState,
  _formData: FormData,
): Promise<RoutePlanningFormState> {
  const access = await resolveOperationsAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    return { error: "You don't have access to this organization's Operations workspace." };
  }

  const supabase = await createSupabaseServerClient();
  try {
    await validateRoutePlanningScenario(supabase, { scenarioId, expectedVersion, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof RouteLoadPlanningMutationError) {
      return { error: `Could not validate this scenario: ${error.message}` };
    }
    throw error;
  }

  revalidateWorkspace(tenantSlug, shipmentOrderId);
  return { error: null };
}

export async function executeRoutePlanningScenarioAction(
  tenantSlug: string,
  shipmentOrderId: string,
  scenarioId: string,
  expectedVersion: number,
  idempotencyKey: string,
  _prevState: RoutePlanningFormState,
  _formData: FormData,
): Promise<RoutePlanningFormState> {
  const access = await resolveOperationsAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    return { error: "You don't have access to this organization's Operations workspace." };
  }

  const supabase = await createSupabaseServerClient();
  try {
    await executeRoutePlanningScenario(supabase, { scenarioId, expectedVersion, idempotencyKey, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof RouteLoadPlanningMutationError) {
      return { error: `Could not execute this scenario: ${error.message}` };
    }
    throw error;
  }

  revalidateWorkspace(tenantSlug, shipmentOrderId);
  return { error: null };
}

/** Directly claims and runs the next pending job for this tenant's worker pool -- see this file's own header. */
export async function runRoutePlanningJobAction(tenantSlug: string, shipmentOrderId: string, _prevState: RoutePlanningFormState, _formData: FormData): Promise<RoutePlanningFormState> {
  const access = await resolveOperationsAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    return { error: "You don't have access to this organization's Operations workspace." };
  }

  const supabase = await createSupabaseServerClient();
  try {
    const ran = await runNextRoutePlanningJob(supabase, { workerId: `manual:${access.authUserId}` });
    if (!ran) {
      revalidateWorkspace(tenantSlug, shipmentOrderId);
      return { error: "No planning job is currently due -- it may already have run, or nothing has been executed yet." };
    }
  } catch (error) {
    if (error instanceof RouteLoadPlanningMutationError) {
      return { error: `Could not run the planner: ${error.message}` };
    }
    throw error;
  }

  revalidateWorkspace(tenantSlug, shipmentOrderId);
  return { error: null };
}

export async function cancelRoutePlanningScenarioAction(
  tenantSlug: string,
  shipmentOrderId: string,
  scenarioId: string,
  expectedVersion: number,
  _prevState: RoutePlanningFormState,
  formData: FormData,
): Promise<RoutePlanningFormState> {
  const access = await resolveOperationsAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    return { error: "You don't have access to this organization's Operations workspace." };
  }

  const reason = String(formData.get("reason") ?? "");
  const supabase = await createSupabaseServerClient();
  try {
    await cancelRoutePlanningScenario(supabase, { scenarioId, expectedVersion, reason, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof RouteLoadPlanningMutationError) {
      return { error: `Could not cancel this scenario: ${error.message}` };
    }
    throw error;
  }

  revalidateWorkspace(tenantSlug, shipmentOrderId);
  return { error: null };
}

export async function selectRoutePlanningPlanAction(
  tenantSlug: string,
  shipmentOrderId: string,
  scenarioId: string,
  candidatePlanId: string,
  expectedVersion: number,
  _prevState: RoutePlanningFormState,
  _formData: FormData,
): Promise<RoutePlanningFormState> {
  const access = await resolveOperationsAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    return { error: "You don't have access to this organization's Operations workspace." };
  }

  const supabase = await createSupabaseServerClient();
  try {
    await selectRoutePlanningPlan(supabase, { scenarioId, candidatePlanId, expectedVersion, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof RouteLoadPlanningMutationError) {
      return { error: `Could not select this plan: ${error.message}` };
    }
    throw error;
  }

  revalidateWorkspace(tenantSlug, shipmentOrderId);
  return { error: null };
}

export async function overrideRoutePlanningSelectionAction(
  tenantSlug: string,
  shipmentOrderId: string,
  scenarioId: string,
  candidatePlanId: string,
  expectedVersion: number,
  _prevState: RoutePlanningFormState,
  formData: FormData,
): Promise<RoutePlanningFormState> {
  const access = await resolveOperationsAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    return { error: "You don't have access to this organization's Operations workspace." };
  }

  const overrideReason = String(formData.get("overrideReason") ?? "");
  const supabase = await createSupabaseServerClient();
  try {
    await overrideRoutePlanningSelection(supabase, { scenarioId, candidatePlanId, overrideReason, expectedVersion, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof RouteLoadPlanningMutationError) {
      return { error: `Could not override the selection: ${error.message}` };
    }
    throw error;
  }

  revalidateWorkspace(tenantSlug, shipmentOrderId);
  return { error: null };
}

export async function replanRoutePlanningScenarioAction(
  tenantSlug: string,
  shipmentOrderId: string,
  scenarioId: string,
  _prevState: RoutePlanningFormState,
  formData: FormData,
): Promise<RoutePlanningFormState> {
  const access = await resolveOperationsAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    return { error: "You don't have access to this organization's Operations workspace." };
  }

  const reason = String(formData.get("reason") ?? "");
  const supabase = await createSupabaseServerClient();
  try {
    await replanRoutePlanningScenario(supabase, { scenarioId, reason, idempotencyKey: randomUUID(), actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof RouteLoadPlanningMutationError) {
      return { error: `Could not replan this scenario: ${error.message}` };
    }
    throw error;
  }

  revalidateWorkspace(tenantSlug, shipmentOrderId);
  return { error: null };
}
