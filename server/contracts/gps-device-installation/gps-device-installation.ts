/**
 * GPS device installation evidence contract (ATW-226B, CG-S10-ATW-006's family, Prompt
 * 226 decomposition child). Mirrors
 * supabase/migrations/20260729350000_create_advanced_tms_device_installation_evidence.sql's
 * app.gps_device_installations shape and the app.record_gps_device_installation /
 * app.verify_gps_device_installation RPCs.
 *
 * Device/SIM/provider-mapping identity itself is not duplicated here -- see
 * server/contracts/fleet-driver-device/fleet-driver-device.ts (ATW-223). This contract
 * models only the evidence layer that closes the one real gap ATW-223 left: proof that
 * a specific device was physically installed on a specific vehicle.
 */

import { z } from "zod";

export const GpsDeviceInstallationSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  deviceId: z.string().uuid(),
  deviceVehicleAssignmentId: z.string().uuid(),
  evidenceFileId: z.string().uuid(),
  technicianLabel: z.string(),
  installationNotes: z.string().nullable(),
  installedAt: z.string(),
  verifiedByAuthUserId: z.string().uuid().nullable(),
  verifiedAt: z.string().nullable(),
  recordVersion: z.number().int().positive(),
  createdBy: z.string().nullable(),
  createdAt: z.string(),
  updatedAt: z.string(),
});
export type GpsDeviceInstallation = z.infer<typeof GpsDeviceInstallationSchema>;

/** Maps a raw app.gps_device_installations row (snake_case) to this contract's camelCase shape. */
export function parseGpsDeviceInstallation(row: Record<string, unknown>): GpsDeviceInstallation {
  return GpsDeviceInstallationSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    deviceId: row.device_id,
    deviceVehicleAssignmentId: row.device_vehicle_assignment_id,
    evidenceFileId: row.evidence_file_id,
    technicianLabel: row.technician_label,
    installationNotes: row.installation_notes ?? null,
    installedAt: row.installed_at,
    verifiedByAuthUserId: row.verified_by_auth_user_id ?? null,
    verifiedAt: row.verified_at ?? null,
    recordVersion: row.record_version,
    createdBy: row.created_by ?? null,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  });
}

export const RecordGpsDeviceInstallationInputSchema = z.object({
  deviceVehicleAssignmentId: z.string().uuid(),
  evidenceFileId: z.string().uuid(),
  technicianLabel: z.string().min(1),
  installationNotes: z.string().nullable().default(null),
  expectedDeviceVersion: z.number().int().positive(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type RecordGpsDeviceInstallationInput = z.input<typeof RecordGpsDeviceInstallationInputSchema>;

export const VerifyGpsDeviceInstallationInputSchema = z.object({
  installationId: z.string().uuid(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type VerifyGpsDeviceInstallationInput = z.infer<typeof VerifyGpsDeviceInstallationInputSchema>;
