/**
 * A minimal, dependency-light Supabase RPC client for this package's own two
 * service_role-only ATW-226D entry points. Deliberately not imported from
 * server/mutations/gps-gateway-ingestion.ts -- see this package's own README.md for why
 * services/gps-gateway never depends on the main Next.js app's own server/ tree -- but
 * the wire shape (p_raw_api_key/p_imei/p_device_id/p_reports/p_gateway_instance_label)
 * is kept identical to that module's own RPC calls on purpose, since both ultimately
 * call the exact same Postgres functions.
 */

import { createClient, type SupabaseClient } from "@supabase/supabase-js";

export interface GatewayIngestReport {
  reportType: "location" | "heartbeat";
  eventAt: string;
  longitude: number | null;
  latitude: number | null;
  altitudeMeters: number | null;
  headingDegrees: number | null;
  speedKmh: number | null;
  satelliteCount: number | null;
  rawCodecId: string;
  ioElements: Record<string, string>;
}

export interface HandshakeResult {
  accepted: boolean;
  deviceId: string | null;
  tenantId: string | null;
  rejectionReason: string | null;
}

export interface IngestBatchResult {
  deviceId: string;
  tenantId: string;
  acceptedCount: number;
  deviceStatus: string;
}

export class GpsGatewayIngestClient {
  private readonly supabase: SupabaseClient;
  private readonly rawApiKey: string;
  private readonly gatewayInstanceLabel: string;

  constructor(supabaseUrl: string, supabaseServiceRoleKey: string, rawApiKey: string, gatewayInstanceLabel: string) {
    this.supabase = createClient(supabaseUrl, supabaseServiceRoleKey, { auth: { persistSession: false } });
    this.rawApiKey = rawApiKey;
    this.gatewayInstanceLabel = gatewayInstanceLabel;
  }

  async resolveHandshake(imei: string): Promise<HandshakeResult> {
    const { data, error } = await this.supabase.rpc("resolve_gps_device_for_handshake", {
      p_raw_api_key: this.rawApiKey,
      p_imei: imei,
      p_gateway_instance_label: this.gatewayInstanceLabel,
    });
    if (error) {
      throw new Error(`${error.message}`);
    }
    const row = (Array.isArray(data) ? data[0] : data) as Record<string, unknown> | undefined;
    if (!row) {
      throw new Error("resolve_gps_device_for_handshake returned no row");
    }
    return {
      accepted: Boolean(row.accepted),
      deviceId: (row.device_id as string | null) ?? null,
      tenantId: (row.tenant_id as string | null) ?? null,
      rejectionReason: (row.rejection_reason as string | null) ?? null,
    };
  }

  async ingestBatch(deviceId: string, reports: GatewayIngestReport[]): Promise<IngestBatchResult> {
    const { data, error } = await this.supabase.rpc("ingest_direct_device_telemetry_batch", {
      p_raw_api_key: this.rawApiKey,
      p_device_id: deviceId,
      p_reports: reports.map((report) => ({
        report_type: report.reportType,
        event_at: report.eventAt,
        longitude: report.longitude,
        latitude: report.latitude,
        altitude_meters: report.altitudeMeters,
        heading_degrees: report.headingDegrees,
        speed_kmh: report.speedKmh,
        satellite_count: report.satelliteCount,
        raw_codec_id: report.rawCodecId,
        io_elements: report.ioElements,
      })),
      p_gateway_instance_label: this.gatewayInstanceLabel,
    });
    if (error) {
      throw new Error(`${error.message}`);
    }
    const row = (Array.isArray(data) ? data[0] : data) as Record<string, unknown> | undefined;
    if (!row) {
      throw new Error("ingest_direct_device_telemetry_batch returned no row");
    }
    return {
      deviceId: row.device_id as string,
      tenantId: row.tenant_id as string,
      acceptedCount: row.accepted_count as number,
      deviceStatus: row.device_status as string,
    };
  }
}

/** The narrow shape src/server.ts and src/buffer.ts actually depend on -- lets tests inject a fake without constructing a real Supabase client. */
export type GpsGatewayIngestClientLike = Pick<GpsGatewayIngestClient, "resolveHandshake" | "ingestBatch">;
