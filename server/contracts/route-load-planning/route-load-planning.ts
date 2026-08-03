/**
 * Route and Load Planning Using Canonical Position contract (ATW-224, CG-S10-ATW-005).
 * Mirrors
 * supabase/migrations/20260729320000_create_advanced_tms_route_load_planning.sql's
 * app.route_planning_scenarios / app.route_planning_stops /
 * app.route_planning_constraints / app.route_planning_candidate_plans /
 * app.route_planning_score_components / app.route_planning_selected_plans /
 * app.route_planning_replan_events shapes, their RPCs, and the canonical-position
 * read contract.
 *
 * Planning is decision support only -- no shape here ever mutates
 * app.shipment_legs. The canonical-position snapshot captured on a scenario is
 * honest, not optimistic: until ATW-226F ships a live telemetry writer, every
 * snapshot reports not_tracked/unusable (see the migration's own header).
 */

import { z } from "zod";

export const ROUTE_PLANNING_SCENARIO_STATUSES = ["draft", "validated", "executing", "ready", "selected", "cancelled", "failed"] as const;
export const RoutePlanningScenarioStatusSchema = z.enum(ROUTE_PLANNING_SCENARIO_STATUSES);
export type RoutePlanningScenarioStatus = z.infer<typeof RoutePlanningScenarioStatusSchema>;

export const ROUTE_PLANNING_STOP_TYPES = ["pickup", "transfer", "delivery"] as const;
export const RoutePlanningStopTypeSchema = z.enum(ROUTE_PLANNING_STOP_TYPES);
export type RoutePlanningStopType = z.infer<typeof RoutePlanningStopTypeSchema>;

export const ROUTE_PLANNING_CONSTRAINT_TYPES = ["hard", "soft"] as const;
export const RoutePlanningConstraintTypeSchema = z.enum(ROUTE_PLANNING_CONSTRAINT_TYPES);
export type RoutePlanningConstraintType = z.infer<typeof RoutePlanningConstraintTypeSchema>;

export const ROUTE_PLANNING_CONSTRAINT_KEYS = [
  "max_weight_kg",
  "max_volume_cbm",
  "max_distance_km",
  "required_vehicle_master_id",
  "required_driver_master_id",
  "earliest_departure_at",
  "latest_arrival_at",
] as const;
export const RoutePlanningConstraintKeySchema = z.enum(ROUTE_PLANNING_CONSTRAINT_KEYS);
export type RoutePlanningConstraintKey = z.infer<typeof RoutePlanningConstraintKeySchema>;

export const ROUTE_PLANNING_SCORE_COMPONENT_KEYS = ["total_distance_km", "estimated_duration_minutes", "capacity_utilization_pct"] as const;
export const RoutePlanningScoreComponentKeySchema = z.enum(ROUTE_PLANNING_SCORE_COMPONENT_KEYS);
export type RoutePlanningScoreComponentKey = z.infer<typeof RoutePlanningScoreComponentKeySchema>;

export const CanonicalPositionForPlanningSchema = z.object({
  trackingStatus: z.string(),
  freshnessStatus: z.string().nullable(),
  accuracyMeters: z.coerce.number().nullable(),
  lastPositionAt: z.string().nullable(),
  authoritativeSourceType: z.string().nullable(),
  trackingEntitled: z.boolean(),
  isUsable: z.boolean(),
});
export type CanonicalPositionForPlanning = z.infer<typeof CanonicalPositionForPlanningSchema>;

export function parseCanonicalPositionForPlanning(row: Record<string, unknown>): CanonicalPositionForPlanning {
  return CanonicalPositionForPlanningSchema.parse({
    trackingStatus: row.tracking_status,
    freshnessStatus: row.freshness_status ?? null,
    accuracyMeters: row.accuracy_meters ?? null,
    lastPositionAt: row.last_position_at ?? null,
    authoritativeSourceType: row.authoritative_source_type ?? null,
    trackingEntitled: row.tracking_entitled,
    isUsable: row.is_usable,
  });
}

export const RoutePlanningScenarioSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  shipmentOrderId: z.string().uuid(),
  idempotencyKey: z.string(),
  status: RoutePlanningScenarioStatusSchema,
  requestedWeightKg: z.coerce.number().nullable(),
  requestedVolumeCbm: z.coerce.number().nullable(),
  jobId: z.string().uuid().nullable(),
  canonicalPositionSnapshot: z.record(z.string(), z.unknown()).nullable(),
  canonicalPositionCapturedAt: z.string().nullable(),
  ownerUserId: z.string().uuid().nullable(),
  recordVersion: z.number().int().positive(),
  createdBy: z.string().nullable(),
  createdAt: z.string(),
  updatedAt: z.string(),
});
export type RoutePlanningScenario = z.infer<typeof RoutePlanningScenarioSchema>;

export function parseRoutePlanningScenario(row: Record<string, unknown>): RoutePlanningScenario {
  return RoutePlanningScenarioSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    shipmentOrderId: row.shipment_order_id,
    idempotencyKey: row.idempotency_key,
    status: row.status,
    requestedWeightKg: row.requested_weight_kg ?? null,
    requestedVolumeCbm: row.requested_volume_cbm ?? null,
    jobId: row.job_id ?? null,
    canonicalPositionSnapshot: row.canonical_position_snapshot ?? null,
    canonicalPositionCapturedAt: row.canonical_position_captured_at ?? null,
    ownerUserId: row.owner_user_id ?? null,
    recordVersion: row.record_version,
    createdBy: row.created_by ?? null,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  });
}

export const RoutePlanningStopSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  scenarioId: z.string().uuid(),
  stopSequence: z.number().int().positive(),
  stopType: RoutePlanningStopTypeSchema,
  locationName: z.string(),
  address: z.string().nullable(),
  longitude: z.number().nullable(),
  latitude: z.number().nullable(),
  timeWindowStart: z.string().nullable(),
  timeWindowEnd: z.string().nullable(),
  createdAt: z.string(),
});
export type RoutePlanningStop = z.infer<typeof RoutePlanningStopSchema>;

function extractGeojsonPoint(geojson: unknown): { longitude: number | null; latitude: number | null } {
  if (!geojson || typeof geojson !== "object") {
    return { longitude: null, latitude: null };
  }
  const coordinates = (geojson as { coordinates?: unknown }).coordinates;
  if (!Array.isArray(coordinates) || coordinates.length !== 2) {
    return { longitude: null, latitude: null };
  }
  return { longitude: Number(coordinates[0]), latitude: Number(coordinates[1]) };
}

export function parseRoutePlanningStop(row: Record<string, unknown>): RoutePlanningStop {
  const { longitude, latitude } = extractGeojsonPoint(row.location_geojson);
  return RoutePlanningStopSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    scenarioId: row.scenario_id,
    stopSequence: row.stop_sequence,
    stopType: row.stop_type,
    locationName: row.location_name,
    address: row.address ?? null,
    longitude,
    latitude,
    timeWindowStart: row.time_window_start ?? null,
    timeWindowEnd: row.time_window_end ?? null,
    createdAt: row.created_at,
  });
}

export const RoutePlanningConstraintSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  scenarioId: z.string().uuid(),
  constraintType: RoutePlanningConstraintTypeSchema,
  constraintKey: RoutePlanningConstraintKeySchema,
  constraintValue: z.record(z.string(), z.unknown()),
  createdAt: z.string(),
});
export type RoutePlanningConstraint = z.infer<typeof RoutePlanningConstraintSchema>;

export function parseRoutePlanningConstraint(row: Record<string, unknown>): RoutePlanningConstraint {
  return RoutePlanningConstraintSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    scenarioId: row.scenario_id,
    constraintType: row.constraint_type,
    constraintKey: row.constraint_key,
    constraintValue: row.constraint_value,
    createdAt: row.created_at,
  });
}

export const RoutePlanningCandidatePlanSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  scenarioId: z.string().uuid(),
  planRank: z.number().int().positive(),
  algorithmVersion: z.string(),
  feasible: z.boolean(),
  infeasibilityReasons: z.array(z.string()).nullable(),
  vehicleMasterId: z.string().uuid().nullable(),
  driverMasterId: z.string().uuid().nullable(),
  totalDistanceKm: z.coerce.number().nullable(),
  estimatedDurationMinutes: z.coerce.number().nullable(),
  capacityUtilizationPct: z.coerce.number().nullable(),
  generatedAt: z.string(),
});
export type RoutePlanningCandidatePlan = z.infer<typeof RoutePlanningCandidatePlanSchema>;

export function parseRoutePlanningCandidatePlan(row: Record<string, unknown>): RoutePlanningCandidatePlan {
  return RoutePlanningCandidatePlanSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    scenarioId: row.scenario_id,
    planRank: row.plan_rank,
    algorithmVersion: row.algorithm_version,
    feasible: row.feasible,
    infeasibilityReasons: row.infeasibility_reasons ?? null,
    vehicleMasterId: row.vehicle_master_id ?? null,
    driverMasterId: row.driver_master_id ?? null,
    totalDistanceKm: row.total_distance_km ?? null,
    estimatedDurationMinutes: row.estimated_duration_minutes ?? null,
    capacityUtilizationPct: row.capacity_utilization_pct ?? null,
    generatedAt: row.generated_at,
  });
}

export const RoutePlanningScoreComponentSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  candidatePlanId: z.string().uuid(),
  componentKey: RoutePlanningScoreComponentKeySchema,
  componentValue: z.coerce.number().nullable(),
  createdAt: z.string(),
});
export type RoutePlanningScoreComponent = z.infer<typeof RoutePlanningScoreComponentSchema>;

export function parseRoutePlanningScoreComponent(row: Record<string, unknown>): RoutePlanningScoreComponent {
  return RoutePlanningScoreComponentSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    candidatePlanId: row.candidate_plan_id,
    componentKey: row.component_key,
    componentValue: row.component_value ?? null,
    createdAt: row.created_at,
  });
}

export const RoutePlanningSelectedPlanSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  scenarioId: z.string().uuid(),
  candidatePlanId: z.string().uuid(),
  isCurrent: z.boolean(),
  supersededById: z.string().uuid().nullable(),
  isOverride: z.boolean(),
  overrideReason: z.string().nullable(),
  selectedBy: z.string().nullable(),
  selectedAt: z.string(),
});
export type RoutePlanningSelectedPlan = z.infer<typeof RoutePlanningSelectedPlanSchema>;

export function parseRoutePlanningSelectedPlan(row: Record<string, unknown>): RoutePlanningSelectedPlan {
  return RoutePlanningSelectedPlanSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    scenarioId: row.scenario_id,
    candidatePlanId: row.candidate_plan_id,
    isCurrent: row.is_current,
    supersededById: row.superseded_by_id ?? null,
    isOverride: row.is_override,
    overrideReason: row.override_reason ?? null,
    selectedBy: row.selected_by ?? null,
    selectedAt: row.selected_at,
  });
}

export const RoutePlanningReplanEventSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  scenarioId: z.string().uuid(),
  previousScenarioId: z.string().uuid(),
  triggerReason: z.string(),
  canonicalPositionSnapshot: z.record(z.string(), z.unknown()).nullable(),
  triggeredBy: z.string().nullable(),
  triggeredAt: z.string(),
});
export type RoutePlanningReplanEvent = z.infer<typeof RoutePlanningReplanEventSchema>;

export function parseRoutePlanningReplanEvent(row: Record<string, unknown>): RoutePlanningReplanEvent {
  return RoutePlanningReplanEventSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    scenarioId: row.scenario_id,
    previousScenarioId: row.previous_scenario_id,
    triggerReason: row.trigger_reason,
    canonicalPositionSnapshot: row.canonical_position_snapshot ?? null,
    triggeredBy: row.triggered_by ?? null,
    triggeredAt: row.triggered_at,
  });
}

// --- Mutation input schemas ---

export const PrepareRoutePlanningScenarioInputSchema = z.object({
  shipmentOrderId: z.string().uuid(),
  idempotencyKey: z.string().min(1),
  requestedWeightKg: z.number().min(0).nullable(),
  requestedVolumeCbm: z.number().min(0).nullable(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type PrepareRoutePlanningScenarioInput = z.input<typeof PrepareRoutePlanningScenarioInputSchema>;

export const AddRoutePlanningStopInputSchema = z.object({
  scenarioId: z.string().uuid(),
  stopSequence: z.number().int().positive(),
  stopType: RoutePlanningStopTypeSchema,
  locationName: z.string().min(1),
  address: z.string().nullable(),
  longitude: z.number().min(-180).max(180).nullable(),
  latitude: z.number().min(-90).max(90).nullable(),
  timeWindowStart: z.string().nullable(),
  timeWindowEnd: z.string().nullable(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type AddRoutePlanningStopInput = z.input<typeof AddRoutePlanningStopInputSchema>;

export const AddRoutePlanningConstraintInputSchema = z.object({
  scenarioId: z.string().uuid(),
  constraintType: RoutePlanningConstraintTypeSchema,
  constraintKey: RoutePlanningConstraintKeySchema,
  constraintValue: z.record(z.string(), z.unknown()),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type AddRoutePlanningConstraintInput = z.input<typeof AddRoutePlanningConstraintInputSchema>;

export const ValidateRoutePlanningScenarioInputSchema = z.object({
  scenarioId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type ValidateRoutePlanningScenarioInput = z.input<typeof ValidateRoutePlanningScenarioInputSchema>;

export const ExecuteRoutePlanningScenarioInputSchema = z.object({
  scenarioId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  idempotencyKey: z.string().min(1),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type ExecuteRoutePlanningScenarioInput = z.input<typeof ExecuteRoutePlanningScenarioInputSchema>;

export const CancelRoutePlanningScenarioInputSchema = z.object({
  scenarioId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  reason: z.string().min(1),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type CancelRoutePlanningScenarioInput = z.input<typeof CancelRoutePlanningScenarioInputSchema>;

export const SelectRoutePlanningPlanInputSchema = z.object({
  scenarioId: z.string().uuid(),
  candidatePlanId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type SelectRoutePlanningPlanInput = z.input<typeof SelectRoutePlanningPlanInputSchema>;

export const OverrideRoutePlanningSelectionInputSchema = z.object({
  scenarioId: z.string().uuid(),
  candidatePlanId: z.string().uuid(),
  overrideReason: z.string().min(1),
  expectedVersion: z.number().int().positive(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type OverrideRoutePlanningSelectionInput = z.input<typeof OverrideRoutePlanningSelectionInputSchema>;

export const ReplanRoutePlanningScenarioInputSchema = z.object({
  scenarioId: z.string().uuid(),
  reason: z.string().min(1),
  idempotencyKey: z.string().min(1),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type ReplanRoutePlanningScenarioInput = z.input<typeof ReplanRoutePlanningScenarioInputSchema>;

export const RunNextRoutePlanningJobInputSchema = z.object({
  workerId: z.string().min(1),
});
export type RunNextRoutePlanningJobInput = z.input<typeof RunNextRoutePlanningJobInputSchema>;
