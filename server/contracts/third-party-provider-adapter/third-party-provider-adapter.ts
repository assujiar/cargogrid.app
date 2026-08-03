/**
 * Third-party GPS platform adapter contract (ATW-226E, CG-S10-ATW-006's family, Prompt
 * 226 decomposition child). Mirrors supabase/migrations/
 * 20260729380000_create_advanced_tms_third_party_provider_adapter.sql's
 * app.third_party_provider_connections/app.third_party_telemetry_reports shapes and the
 * app.register_third_party_provider_connection / app.rotate_third_party_provider_
 * webhook_secret / app.update_third_party_provider_poll_cursor /
 * app.ingest_third_party_provider_webhook_event / app.get_third_party_telemetry_reports
 * RPCs.
 */

import { z } from "zod";

export const THIRD_PARTY_PROVIDER_INTEGRATION_MODES = ["webhook", "poll"] as const;
export const ThirdPartyProviderIntegrationModeSchema = z.enum(THIRD_PARTY_PROVIDER_INTEGRATION_MODES);
export type ThirdPartyProviderIntegrationMode = z.infer<typeof ThirdPartyProviderIntegrationModeSchema>;

export const THIRD_PARTY_PROVIDER_CONNECTION_STATUSES = ["active", "disabled"] as const;
export const ThirdPartyProviderConnectionStatusSchema = z.enum(THIRD_PARTY_PROVIDER_CONNECTION_STATUSES);
export type ThirdPartyProviderConnectionStatus = z.infer<typeof ThirdPartyProviderConnectionStatusSchema>;

export const THIRD_PARTY_TELEMETRY_REPORT_TYPES = ["location", "heartbeat"] as const;
export const ThirdPartyTelemetryReportTypeSchema = z.enum(THIRD_PARTY_TELEMETRY_REPORT_TYPES);
export type ThirdPartyTelemetryReportType = z.infer<typeof ThirdPartyTelemetryReportTypeSchema>;

export const ThirdPartyProviderConnectionSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  providerCode: z.string(),
  integrationMode: ThirdPartyProviderIntegrationModeSchema,
  pollCursor: z.record(z.string(), z.unknown()).nullable(),
  status: ThirdPartyProviderConnectionStatusSchema,
  consecutiveFailureCount: z.number().int(),
  lastSuccessfulIngestAt: z.string().nullable(),
  createdAt: z.string(),
  updatedAt: z.string(),
});
export type ThirdPartyProviderConnection = z.infer<typeof ThirdPartyProviderConnectionSchema>;

/** Never includes webhook_secret_value -- that column carries zero authenticated/anon grant, disclosed exactly once via registerThirdPartyProviderConnection/rotateThirdPartyProviderWebhookSecret's own return row. */
export function parseThirdPartyProviderConnection(row: Record<string, unknown>): ThirdPartyProviderConnection {
  return ThirdPartyProviderConnectionSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    providerCode: row.provider_code,
    integrationMode: row.integration_mode,
    pollCursor: (row.poll_cursor as Record<string, unknown> | null) ?? null,
    status: row.status,
    consecutiveFailureCount: row.consecutive_failure_count,
    lastSuccessfulIngestAt: row.last_successful_ingest_at ?? null,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  });
}

export const RegisterThirdPartyProviderConnectionResultSchema = z.object({
  connectionId: z.string().uuid(),
  providerCode: z.string(),
  integrationMode: ThirdPartyProviderIntegrationModeSchema,
  rawWebhookSecret: z.string().nullable(),
  status: ThirdPartyProviderConnectionStatusSchema,
});
export type RegisterThirdPartyProviderConnectionResult = z.infer<typeof RegisterThirdPartyProviderConnectionResultSchema>;

export function parseRegisterThirdPartyProviderConnectionResult(row: Record<string, unknown>): RegisterThirdPartyProviderConnectionResult {
  return RegisterThirdPartyProviderConnectionResultSchema.parse({
    connectionId: row.connection_id,
    providerCode: row.provider_code,
    integrationMode: row.integration_mode,
    rawWebhookSecret: row.raw_webhook_secret ?? null,
    status: row.status,
  });
}

export const RegisterThirdPartyProviderConnectionInputSchema = z.object({
  tenantId: z.string().uuid(),
  providerCode: z.string().min(1),
  integrationMode: ThirdPartyProviderIntegrationModeSchema,
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type RegisterThirdPartyProviderConnectionInput = z.infer<typeof RegisterThirdPartyProviderConnectionInputSchema>;

export const RotateThirdPartyProviderWebhookSecretResultSchema = z.object({
  connectionId: z.string().uuid(),
  rawWebhookSecret: z.string(),
});
export type RotateThirdPartyProviderWebhookSecretResult = z.infer<typeof RotateThirdPartyProviderWebhookSecretResultSchema>;

export function parseRotateThirdPartyProviderWebhookSecretResult(row: Record<string, unknown>): RotateThirdPartyProviderWebhookSecretResult {
  return RotateThirdPartyProviderWebhookSecretResultSchema.parse({
    connectionId: row.connection_id,
    rawWebhookSecret: row.raw_webhook_secret,
  });
}

export const RotateThirdPartyProviderWebhookSecretInputSchema = z.object({
  connectionId: z.string().uuid(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type RotateThirdPartyProviderWebhookSecretInput = z.infer<typeof RotateThirdPartyProviderWebhookSecretInputSchema>;

export const UpdateThirdPartyProviderPollCursorInputSchema = z.object({
  connectionId: z.string().uuid(),
  cursor: z.record(z.string(), z.unknown()),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type UpdateThirdPartyProviderPollCursorInput = z.infer<typeof UpdateThirdPartyProviderPollCursorInputSchema>;

export const ThirdPartyTelemetryReportSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  connectionId: z.string().uuid(),
  vehicleMasterId: z.string().uuid(),
  providerEventId: z.string(),
  reportType: ThirdPartyTelemetryReportTypeSchema,
  eventAt: z.string(),
  receivedAt: z.string(),
  latitude: z.number().nullable(),
  longitude: z.number().nullable(),
  speedKmh: z.number().nullable(),
  headingDegrees: z.number().nullable(),
  rawFields: z.record(z.string(), z.unknown()),
  createdAt: z.string(),
});
export type ThirdPartyTelemetryReport = z.infer<typeof ThirdPartyTelemetryReportSchema>;

/** location arrives from PostGIS as GeoJSON (via ST_AsGeoJSON in app.get_third_party_telemetry_reports) or null -- never a raw WKB string surfaced to a caller. */
export function parseThirdPartyTelemetryReport(row: Record<string, unknown>): ThirdPartyTelemetryReport {
  const location = row.location_geojson as { coordinates?: [number, number] } | null | undefined;
  return ThirdPartyTelemetryReportSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    connectionId: row.connection_id,
    vehicleMasterId: row.vehicle_master_id,
    providerEventId: row.provider_event_id,
    reportType: row.report_type,
    eventAt: row.event_at,
    receivedAt: row.received_at,
    latitude: location?.coordinates ? location.coordinates[1] : null,
    longitude: location?.coordinates ? location.coordinates[0] : null,
    speedKmh: row.speed_kmh ?? null,
    headingDegrees: row.heading_degrees ?? null,
    rawFields: (row.raw_fields as Record<string, unknown>) ?? {},
    createdAt: row.created_at,
  });
}

export const IngestThirdPartyProviderWebhookEventResultSchema = z.object({
  ingestStatus: z.enum(["ok", "invalid", "rate_limited", "duplicate", "quarantined"]),
  reportId: z.string().uuid().nullable(),
});
export type IngestThirdPartyProviderWebhookEventResult = z.infer<typeof IngestThirdPartyProviderWebhookEventResultSchema>;

export function parseIngestThirdPartyProviderWebhookEventResult(row: Record<string, unknown>): IngestThirdPartyProviderWebhookEventResult {
  return IngestThirdPartyProviderWebhookEventResultSchema.parse({
    ingestStatus: row.ingest_status,
    reportId: row.report_id ?? null,
  });
}

export const IngestThirdPartyProviderWebhookEventInputSchema = z.object({
  connectionId: z.string().uuid(),
  clientKey: z.string().min(1),
  rawPayload: z.string().min(1),
  timestamp: z.number().int(),
  signature: z.string().min(1),
});
export type IngestThirdPartyProviderWebhookEventInput = z.input<typeof IngestThirdPartyProviderWebhookEventInputSchema>;

/** The repository-owned reference webhook JSON contract app.ingest_third_party_provider_webhook_event's own p_raw_payload is validated against (design note 3 of the migration's own header) -- a representative example, never a claim that any named real-world vendor's actual payload shape matches this exactly. */
export const ThirdPartyProviderReferenceWebhookPayloadSchema = z.object({
  event_id: z.string().min(1),
  vehicle_id: z.string().min(1),
  event_type: ThirdPartyTelemetryReportTypeSchema,
  timestamp: z.string(),
  latitude: z.number().min(-90).max(90).optional(),
  longitude: z.number().min(-180).max(180).optional(),
  speed_kmh: z.number().nonnegative().optional(),
  heading_degrees: z.number().min(0).max(360).optional(),
});
export type ThirdPartyProviderReferenceWebhookPayload = z.infer<typeof ThirdPartyProviderReferenceWebhookPayloadSchema>;
