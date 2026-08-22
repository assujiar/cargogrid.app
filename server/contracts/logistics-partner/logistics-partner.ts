/**
 * Carrier, Port, Airport and Customs Integrations contract (IAE-016, Prompt
 * 344). Mirrors supabase/migrations/
 * 20260805030000_create_intelligence_carrier_port_airport_customs_integrations.sql's
 * app.logistics_partner_events shape and its ingest/sync/review/list RPCs.
 */

import { z } from "zod";

export const LOGISTICS_PARTNER_ADAPTER_CODES = ["carrier_status_api", "port_terminal_edi", "airport_cargo_system", "customs_broker_api"] as const;
export const LogisticsPartnerAdapterCodeSchema = z.enum(LOGISTICS_PARTNER_ADAPTER_CODES);
export type LogisticsPartnerAdapterCode = z.infer<typeof LogisticsPartnerAdapterCodeSchema>;

export const LOGISTICS_PARTNER_EVENT_TYPES = ["status_update", "milestone", "document_available", "customs_clearance"] as const;
export const LogisticsPartnerEventTypeSchema = z.enum(LOGISTICS_PARTNER_EVENT_TYPES);
export type LogisticsPartnerEventType = z.infer<typeof LogisticsPartnerEventTypeSchema>;

export const LOGISTICS_PARTNER_MATCH_STATUSES = ["matched", "unmatched", "ambiguous"] as const;
export const LogisticsPartnerMatchStatusSchema = z.enum(LOGISTICS_PARTNER_MATCH_STATUSES);
export type LogisticsPartnerMatchStatus = z.infer<typeof LogisticsPartnerMatchStatusSchema>;

export const LOGISTICS_PARTNER_PROCESSING_STATUSES = ["received", "reviewed", "dismissed"] as const;
export const LogisticsPartnerProcessingStatusSchema = z.enum(LOGISTICS_PARTNER_PROCESSING_STATUSES);
export type LogisticsPartnerProcessingStatus = z.infer<typeof LogisticsPartnerProcessingStatusSchema>;

export const LogisticsPartnerEventSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  connectionId: z.string().uuid(),
  providerEventId: z.string(),
  eventType: LogisticsPartnerEventTypeSchema,
  externalReference: z.string().nullable(),
  shipmentOrderId: z.string().uuid().nullable(),
  matchStatus: LogisticsPartnerMatchStatusSchema,
  rawPayload: z.record(z.string(), z.unknown()),
  processingStatus: LogisticsPartnerProcessingStatusSchema,
  reviewNotes: z.string().nullable(),
  reviewedByAuthUserId: z.string().uuid().nullable(),
  reviewedAt: z.string().nullable(),
  createdAt: z.string(),
});
export type LogisticsPartnerEvent = z.infer<typeof LogisticsPartnerEventSchema>;

export function parseLogisticsPartnerEvent(row: Record<string, unknown>): LogisticsPartnerEvent {
  return LogisticsPartnerEventSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    connectionId: row.connection_id,
    providerEventId: row.provider_event_id,
    eventType: row.event_type,
    externalReference: row.external_reference,
    shipmentOrderId: row.shipment_order_id,
    matchStatus: row.match_status,
    rawPayload: row.raw_payload,
    processingStatus: row.processing_status,
    reviewNotes: row.review_notes,
    reviewedByAuthUserId: row.reviewed_by_auth_user_id,
    reviewedAt: row.reviewed_at,
    createdAt: row.created_at,
  });
}

export const LOGISTICS_PARTNER_INGEST_STATUSES = ["ok", "duplicate", "invalid", "rate_limited"] as const;
export const LogisticsPartnerIngestStatusSchema = z.enum(LOGISTICS_PARTNER_INGEST_STATUSES);
export type LogisticsPartnerIngestStatus = z.infer<typeof LogisticsPartnerIngestStatusSchema>;

export const IngestLogisticsPartnerWebhookEventInputSchema = z.object({
  connectionId: z.string().uuid(),
  clientKey: z.string().min(1),
  rawPayload: z.string(),
  timestamp: z.number(),
  signature: z.string(),
});
export type IngestLogisticsPartnerWebhookEventInput = z.input<typeof IngestLogisticsPartnerWebhookEventInputSchema>;

export const IngestLogisticsPartnerWebhookEventResultSchema = z.object({
  ingestStatus: LogisticsPartnerIngestStatusSchema,
  eventId: z.string().uuid().nullable(),
});
export type IngestLogisticsPartnerWebhookEventResult = z.infer<typeof IngestLogisticsPartnerWebhookEventResultSchema>;

export function parseIngestLogisticsPartnerWebhookEventResult(row: Record<string, unknown>): IngestLogisticsPartnerWebhookEventResult {
  return IngestLogisticsPartnerWebhookEventResultSchema.parse({
    ingestStatus: row.ingest_status,
    eventId: row.event_id,
  });
}

export const TriggerLogisticsPartnerPollSyncInputSchema = z.object({
  tenantId: z.string().uuid(),
  connectionId: z.string().uuid(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type TriggerLogisticsPartnerPollSyncInput = z.input<typeof TriggerLogisticsPartnerPollSyncInputSchema>;

export const RecordLogisticsPartnerSyncEventInputSchema = z.object({
  tenantId: z.string().uuid(),
  connectionId: z.string().uuid(),
  providerEventId: z.string().min(1),
  eventType: LogisticsPartnerEventTypeSchema,
  externalReference: z.string().nullable().default(null),
  rawPayload: z.record(z.string(), z.unknown()),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type RecordLogisticsPartnerSyncEventInput = z.input<typeof RecordLogisticsPartnerSyncEventInputSchema>;

export const ReviewLogisticsPartnerEventInputSchema = z.object({
  eventId: z.string().uuid(),
  decision: z.enum(["reviewed", "dismissed"]),
  notes: z.string().nullable().default(null),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type ReviewLogisticsPartnerEventInput = z.input<typeof ReviewLogisticsPartnerEventInputSchema>;

export const ListLogisticsPartnerEventsForTenantInputSchema = z.object({
  tenantId: z.string().uuid(),
  actorAuthUserId: z.string().uuid(),
  shipmentOrderId: z.string().uuid().nullable().default(null),
  limit: z.number().int().positive().max(200).default(50),
});
export type ListLogisticsPartnerEventsForTenantInput = z.input<typeof ListLogisticsPartnerEventsForTenantInputSchema>;

/** The real outbound client's own minimal read -- never the raw credential. */
export const LogisticsPartnerDispatchInfoSchema = z.object({
  connectionId: z.string().uuid(),
  connectionStatus: z.string(),
  connectionConfig: z.record(z.string(), z.unknown()),
});
export type LogisticsPartnerDispatchInfo = z.infer<typeof LogisticsPartnerDispatchInfoSchema>;

export function parseLogisticsPartnerDispatchInfo(row: Record<string, unknown>): LogisticsPartnerDispatchInfo {
  return LogisticsPartnerDispatchInfoSchema.parse({
    connectionId: row.connection_id,
    connectionStatus: row.connection_status,
    connectionConfig: row.connection_config,
  });
}

/** The real poll worker's own connection read -- no actor authority check (already-authorized background job). */
export const LogisticsPartnerConnectionForSyncSchema = z.object({
  tenantId: z.string().uuid(),
  adapterCode: z.string(),
  connectionStatus: z.string(),
  connectionConfig: z.record(z.string(), z.unknown()),
});
export type LogisticsPartnerConnectionForSync = z.infer<typeof LogisticsPartnerConnectionForSyncSchema>;

export function parseLogisticsPartnerConnectionForSync(row: Record<string, unknown>): LogisticsPartnerConnectionForSync {
  return LogisticsPartnerConnectionForSyncSchema.parse({
    tenantId: row.tenant_id,
    adapterCode: row.adapter_code,
    connectionStatus: row.connection_status,
    connectionConfig: row.connection_config,
  });
}
