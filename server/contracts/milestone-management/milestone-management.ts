/**
 * Milestone Management contract (OPS-173, CG-S8-OPS-007). Mirrors
 * supabase/migrations/20260727140000_create_operations_milestone_management.sql's
 * app.milestone_codes/app.milestone_template_versions/app.milestone_events/
 * app.shipment_milestone_projections shapes and their RPCs.
 *
 * Configurable shipment milestones (versioned, per-mode templates) plus
 * append-oriented, idempotent event capture with event/received time kept distinct,
 * and a deterministic ETA/location/status projection recalculated from the full
 * event history on every ingest -- never an incremental patch that could drift under
 * out-of-order/duplicate delivery.
 */

import { z } from "zod";

export const MILESTONE_CATEGORIES = ["pickup", "in_transit", "exception", "delivery", "administrative"] as const;
export const MilestoneCategorySchema = z.enum(MILESTONE_CATEGORIES);
export type MilestoneCategory = z.infer<typeof MilestoneCategorySchema>;

export const MILESTONE_TEMPLATE_MODES = ["land", "air", "sea"] as const;
export const MilestoneTemplateModeSchema = z.enum(MILESTONE_TEMPLATE_MODES);
export type MilestoneTemplateMode = z.infer<typeof MilestoneTemplateModeSchema>;

export const MILESTONE_TEMPLATE_STATUSES = ["draft", "published", "archived"] as const;
export const MilestoneTemplateStatusSchema = z.enum(MILESTONE_TEMPLATE_STATUSES);
export type MilestoneTemplateStatus = z.infer<typeof MilestoneTemplateStatusSchema>;

// Widened at ATW-226G (supabase/migrations/20260730090000_create_advanced_tms_geofence_
// route_deviation_signals.sql) to add 'system' -- a GPS-derived, human-confirmed
// milestone (app.confirm_milestone_candidate) is honestly neither manual/api/webhook/
// import; mirrors the same widening already applied to app.milestone_events'
// milestone_events_source_check and app.ingest_milestone_event's own internal check.
export const MILESTONE_EVENT_SOURCES = ["manual", "api", "webhook", "import", "system"] as const;
export const MilestoneEventSourceSchema = z.enum(MILESTONE_EVENT_SOURCES);
export type MilestoneEventSource = z.infer<typeof MilestoneEventSourceSchema>;

export const MilestoneCodeSchema = z.object({
  code: z.string(),
  name: z.string(),
  category: MilestoneCategorySchema,
  isCustomerVisible: z.boolean(),
  affectsEta: z.boolean(),
  isTerminal: z.boolean(),
  registeredBy: z.string().nullable(),
  createdAt: z.string(),
});
export type MilestoneCode = z.infer<typeof MilestoneCodeSchema>;

export function parseMilestoneCode(row: Record<string, unknown>): MilestoneCode {
  return MilestoneCodeSchema.parse({
    code: row.code,
    name: row.name,
    category: row.category,
    isCustomerVisible: row.is_customer_visible,
    affectsEta: row.affects_eta,
    isTerminal: row.is_terminal,
    registeredBy: row.registered_by ?? null,
    createdAt: row.created_at,
  });
}

export const MilestoneSequenceEntrySchema = z.object({ code: z.string().min(1) });
export type MilestoneSequenceEntry = z.infer<typeof MilestoneSequenceEntrySchema>;

export const MilestoneTemplateVersionSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  mode: MilestoneTemplateModeSchema,
  status: MilestoneTemplateStatusSchema,
  sequence: z.array(MilestoneSequenceEntrySchema),
  supersedesVersionId: z.string().uuid().nullable(),
  recordVersion: z.number().int().positive(),
  createdBy: z.string().nullable(),
  createdAt: z.string(),
  updatedAt: z.string(),
});
export type MilestoneTemplateVersion = z.infer<typeof MilestoneTemplateVersionSchema>;

export function parseMilestoneTemplateVersion(row: Record<string, unknown>): MilestoneTemplateVersion {
  return MilestoneTemplateVersionSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    mode: row.mode,
    status: row.status,
    sequence: row.sequence,
    supersedesVersionId: row.supersedes_version_id ?? null,
    recordVersion: row.record_version,
    createdBy: row.created_by ?? null,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  });
}

export const MilestoneLocationSchema = z.object({
  lat: z.number(),
  lng: z.number(),
  label: z.string().optional(),
});
export type MilestoneLocation = z.infer<typeof MilestoneLocationSchema>;

export const MILESTONE_EVENT_SOURCE_CLASSES = ["driver_mobile", "direct_device", "third_party_platform"] as const;
export const MilestoneEventSourceClassSchema = z.enum(MILESTONE_EVENT_SOURCE_CLASSES);
export type MilestoneEventSourceClass = z.infer<typeof MilestoneEventSourceClassSchema>;

export const MILESTONE_EVENT_FRESHNESS_STATUSES = ["healthy", "stale", "offline"] as const;
export const MilestoneEventFreshnessStatusSchema = z.enum(MILESTONE_EVENT_FRESHNESS_STATUSES);
export type MilestoneEventFreshnessStatus = z.infer<typeof MilestoneEventFreshnessStatusSchema>;

export const MilestoneEventSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  shipmentOrderId: z.string().uuid(),
  milestoneCode: z.string(),
  eventTime: z.string(),
  receivedTime: z.string(),
  location: MilestoneLocationSchema.nullable(),
  source: MilestoneEventSourceSchema,
  reason: z.string().nullable(),
  correctsEventId: z.string().uuid().nullable(),
  idempotencyKey: z.string(),
  sequenceNo: z.number().int().positive(),
  createdBy: z.string().nullable(),
  createdAt: z.string(),
  sourceClass: MilestoneEventSourceClassSchema.nullable(),
  sourceConfidenceScore: z.coerce.number().min(0).max(1).nullable(),
  sourceFreshnessStatus: MilestoneEventFreshnessStatusSchema.nullable(),
  sourceCandidateId: z.string().uuid().nullable(),
});
export type MilestoneEvent = z.infer<typeof MilestoneEventSchema>;

/** sourceClass/sourceConfidenceScore/sourceFreshnessStatus/sourceCandidateId were added at ATW-228 -- always null for a manually-filed event or a historical row predating this widening (never backfilled, 228_*.md §19). */
export function parseMilestoneEvent(row: Record<string, unknown>): MilestoneEvent {
  return MilestoneEventSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    shipmentOrderId: row.shipment_order_id,
    milestoneCode: row.milestone_code,
    eventTime: row.event_time,
    receivedTime: row.received_time,
    location: row.location ?? null,
    source: row.source,
    reason: row.reason ?? null,
    correctsEventId: row.corrects_event_id ?? null,
    idempotencyKey: row.idempotency_key,
    sequenceNo: row.sequence_no,
    createdBy: row.created_by ?? null,
    createdAt: row.created_at,
    sourceClass: row.source_class ?? null,
    sourceConfidenceScore: row.source_confidence_score ?? null,
    sourceFreshnessStatus: row.source_freshness_status ?? null,
    sourceCandidateId: row.source_candidate_id ?? null,
  });
}

export const ShipmentMilestoneProjectionSchema = z.object({
  shipmentOrderId: z.string().uuid(),
  tenantId: z.string().uuid(),
  lastMilestoneCode: z.string().nullable(),
  lastMilestoneEventTime: z.string().nullable(),
  lastMilestoneReceivedTime: z.string().nullable(),
  currentEta: z.string().nullable(),
  currentLocation: MilestoneLocationSchema.nullable(),
  isDelayed: z.boolean(),
  eventCount: z.number().int().nonnegative(),
  recordVersion: z.number().int().positive(),
  updatedAt: z.string(),
});
export type ShipmentMilestoneProjection = z.infer<typeof ShipmentMilestoneProjectionSchema>;

export function parseShipmentMilestoneProjection(row: Record<string, unknown>): ShipmentMilestoneProjection {
  return ShipmentMilestoneProjectionSchema.parse({
    shipmentOrderId: row.shipment_order_id,
    tenantId: row.tenant_id,
    lastMilestoneCode: row.last_milestone_code ?? null,
    lastMilestoneEventTime: row.last_milestone_event_time ?? null,
    lastMilestoneReceivedTime: row.last_milestone_received_time ?? null,
    currentEta: row.current_eta ?? null,
    currentLocation: row.current_location ?? null,
    isDelayed: row.is_delayed,
    eventCount: row.event_count,
    recordVersion: row.record_version,
    updatedAt: row.updated_at,
  });
}

export const CreateMilestoneTemplateDraftInputSchema = z.object({
  tenantId: z.string().uuid(),
  mode: MilestoneTemplateModeSchema,
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type CreateMilestoneTemplateDraftInput = z.input<typeof CreateMilestoneTemplateDraftInputSchema>;

export const SetMilestoneTemplateSequenceInputSchema = z.object({
  versionId: z.string().uuid(),
  sequence: z.array(MilestoneSequenceEntrySchema),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type SetMilestoneTemplateSequenceInput = z.input<typeof SetMilestoneTemplateSequenceInputSchema>;

export const PublishMilestoneTemplateVersionInputSchema = z.object({
  versionId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  supersedesVersionId: z.string().uuid().nullable().default(null),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type PublishMilestoneTemplateVersionInput = z.input<typeof PublishMilestoneTemplateVersionInputSchema>;

export const IngestMilestoneEventInputSchema = z.object({
  shipmentOrderId: z.string().uuid(),
  milestoneCode: z.string().min(1),
  eventTime: z.string(),
  receivedTime: z.string().nullable().default(null),
  location: MilestoneLocationSchema.nullable().default(null),
  source: MilestoneEventSourceSchema,
  reason: z.string().nullable().default(null),
  correctsEventId: z.string().uuid().nullable().default(null),
  idempotencyKey: z.string().min(1),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type IngestMilestoneEventInput = z.input<typeof IngestMilestoneEventInputSchema>;

export const GetShipmentMilestoneTimelineInputSchema = z.object({
  shipmentOrderId: z.string().uuid(),
  actorAuthUserId: z.string().uuid(),
  customerVisibleOnly: z.boolean().default(false),
});
export type GetShipmentMilestoneTimelineInput = z.input<typeof GetShipmentMilestoneTimelineInputSchema>;

export const GetShipmentMilestoneProjectionInputSchema = z.object({
  shipmentOrderId: z.string().uuid(),
  actorAuthUserId: z.string().uuid(),
});
export type GetShipmentMilestoneProjectionInput = z.input<typeof GetShipmentMilestoneProjectionInputSchema>;
