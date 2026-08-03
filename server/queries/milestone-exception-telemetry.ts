/**
 * Dependency-aware live ETA read query (ATW-228, CG-S10-ATW-009). Thin, typed wrapper
 * around app.get_shipment_leg_eta_projection
 * (supabase/migrations/20260730130000_create_advanced_tms_milestone_exception_telemetry.sql).
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import { parseShipmentLegEtaProjection, type ShipmentLegEtaProjection } from "../contracts/milestone-exception-telemetry/milestone-exception-telemetry.ts";

export type MilestoneExceptionTelemetryQueryClient = Pick<SupabaseClient, "rpc">;

export class MilestoneExceptionTelemetryQueryError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "MilestoneExceptionTelemetryQueryError";
  }
}

function firstRow(data: unknown): Record<string, unknown> | null {
  const row = Array.isArray(data) ? data[0] : data;
  return row && typeof row === "object" ? (row as Record<string, unknown>) : null;
}

/** computable=false with a named reason (never a fabricated estimate) whenever no live position, an offline position, or no remaining stop exists for the leg. */
export async function getShipmentLegEtaProjection(client: MilestoneExceptionTelemetryQueryClient, shipmentLegId: string, actorAuthUserId: string): Promise<ShipmentLegEtaProjection> {
  const { data, error } = await client.rpc("get_shipment_leg_eta_projection", { p_shipment_leg_id: shipmentLegId, p_actor_auth_user_id: actorAuthUserId });
  if (error) {
    throw new MilestoneExceptionTelemetryQueryError(error.message);
  }
  const row = firstRow(data);
  if (!row) {
    throw new MilestoneExceptionTelemetryQueryError("get_shipment_leg_eta_projection returned no row");
  }
  return parseShipmentLegEtaProjection(row);
}
