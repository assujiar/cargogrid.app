/**
 * Enterprise Maps Geocoding and Routing contract (IAE-015, Prompt 343).
 * Mirrors supabase/migrations/
 * 20260805020000_create_intelligence_maps_gps_telematics_integrations.sql's
 * app.geocode_requests shape and the app.record_geocode_request /
 * app.list_geocode_requests_for_tenant / app.get_maps_provider_dispatch_info
 * RPCs. GPS/telematics provider ingestion itself is unchanged (ADR-0025 Part
 * B) -- this contract covers only the genuinely new geocoding/routing
 * capability.
 */

import { z } from "zod";

export const GEOCODE_REQUEST_TYPES = ["geocode", "route"] as const;
export const GeocodeRequestTypeSchema = z.enum(GEOCODE_REQUEST_TYPES);
export type GeocodeRequestType = z.infer<typeof GeocodeRequestTypeSchema>;

export const GEOCODE_REQUEST_STATUSES = ["success", "failed"] as const;
export const GeocodeRequestStatusSchema = z.enum(GEOCODE_REQUEST_STATUSES);
export type GeocodeRequestStatus = z.infer<typeof GeocodeRequestStatusSchema>;

export const GeocodeRequestSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  connectionId: z.string().uuid(),
  requestType: GeocodeRequestTypeSchema,
  queryPayload: z.record(z.string(), z.unknown()),
  status: GeocodeRequestStatusSchema,
  resultPayload: z.record(z.string(), z.unknown()).nullable(),
  providerUnitCostAmount: z.number().nullable(),
  currency: z.string().nullable(),
  billedAmount: z.number().nullable(),
  errorMessage: z.string().nullable(),
  requestedByAuthUserId: z.string().uuid().nullable(),
  requestedBy: z.string().nullable(),
  createdAt: z.string(),
});
export type GeocodeRequest = z.infer<typeof GeocodeRequestSchema>;

export function parseGeocodeRequest(row: Record<string, unknown>): GeocodeRequest {
  return GeocodeRequestSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    connectionId: row.connection_id,
    requestType: row.request_type,
    queryPayload: row.query_payload,
    status: row.status,
    resultPayload: row.result_payload,
    providerUnitCostAmount: row.provider_unit_cost_amount,
    currency: row.currency,
    billedAmount: row.billed_amount,
    errorMessage: row.error_message,
    requestedByAuthUserId: row.requested_by_auth_user_id,
    requestedBy: row.requested_by,
    createdAt: row.created_at,
  });
}

export const RecordGeocodeRequestInputSchema = z.object({
  tenantId: z.string().uuid(),
  connectionId: z.string().uuid(),
  requestType: GeocodeRequestTypeSchema,
  queryPayload: z.record(z.string(), z.unknown()),
  status: GeocodeRequestStatusSchema,
  resultPayload: z.record(z.string(), z.unknown()).nullable().default(null),
  providerUnitCostAmount: z.number().nonnegative().nullable().default(null),
  currency: z.string().nullable().default(null),
  errorMessage: z.string().nullable().default(null),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type RecordGeocodeRequestInput = z.input<typeof RecordGeocodeRequestInputSchema>;

export const ListGeocodeRequestsForTenantInputSchema = z.object({
  tenantId: z.string().uuid(),
  actorAuthUserId: z.string().uuid(),
  limit: z.number().int().positive().max(200).default(50),
});
export type ListGeocodeRequestsForTenantInput = z.input<typeof ListGeocodeRequestsForTenantInputSchema>;

/** IAE-015: the real outbound client's own minimal read -- never the raw credential. */
export const MapsProviderDispatchInfoSchema = z.object({
  connectionId: z.string().uuid(),
  connectionStatus: z.string(),
  connectionConfig: z.record(z.string(), z.unknown()),
});
export type MapsProviderDispatchInfo = z.infer<typeof MapsProviderDispatchInfoSchema>;

export function parseMapsProviderDispatchInfo(row: Record<string, unknown>): MapsProviderDispatchInfo {
  return MapsProviderDispatchInfoSchema.parse({
    connectionId: row.connection_id,
    connectionStatus: row.connection_status,
    connectionConfig: row.connection_config,
  });
}
