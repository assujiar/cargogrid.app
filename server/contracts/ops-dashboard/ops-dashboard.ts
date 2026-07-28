/**
 * Operations Dashboard contract (OPS-182, CG-S8-OPS-016). Mirrors
 * supabase/migrations/20260728150000_create_operations_dashboard.sql's six
 * app.get_ops_dashboard_* RPC result shapes. Reuses `DashboardScopeFilterSchema`
 * directly from the Commercial Dashboard's own contract (COM-158) -- the shared
 * tenant/orgUnit/owner scope shape every app.get_*_dashboard_* function accepts is not
 * Commercial-specific despite where it was first defined.
 */

import { z } from "zod";
import { DashboardScopeFilterSchema, type DashboardScopeFilter } from "../dashboard/dashboard.ts";

export type { DashboardScopeFilter };
export { DashboardScopeFilterSchema };

export const SHIPMENT_STATUSES = ["draft", "confirmed", "planned", "assigned", "dispatched", "in_transit", "delivered", "epod", "closed", "held", "cancelled"] as const;
export const ShipmentStatusSchema = z.enum(SHIPMENT_STATUSES);
export type ShipmentStatus = z.infer<typeof ShipmentStatusSchema>;

export const MILESTONE_SLA_BUCKETS = ["on_time", "delayed", "no_projection"] as const;
export const MilestoneSlaBucketSchema = z.enum(MILESTONE_SLA_BUCKETS);
export type MilestoneSlaBucket = z.infer<typeof MilestoneSlaBucketSchema>;

export const EXCEPTION_SEVERITIES = ["low", "medium", "high", "critical"] as const;
export const ExceptionSeveritySchema = z.enum(EXCEPTION_SEVERITIES);
export type ExceptionSeverity = z.infer<typeof ExceptionSeveritySchema>;

export const EPOD_CAPTURE_STATUSES = ["draft", "submitted", "approved", "revision_requested", "completed"] as const;
export const EpodCaptureStatusSchema = z.enum(EPOD_CAPTURE_STATUSES);
export type EpodCaptureStatus = z.infer<typeof EpodCaptureStatusSchema>;

export const COST_VARIANCE_BUCKETS = ["over_budget", "under_budget", "on_budget"] as const;
export const CostVarianceBucketSchema = z.enum(COST_VARIANCE_BUCKETS);
export type CostVarianceBucket = z.infer<typeof CostVarianceBucketSchema>;

export const BILLING_READINESS_SUMMARY_BUCKETS = ["ready", "not_ready"] as const;
export const BillingReadinessSummaryBucketSchema = z.enum(BILLING_READINESS_SUMMARY_BUCKETS);
export type BillingReadinessSummaryBucket = z.infer<typeof BillingReadinessSummaryBucketSchema>;

export const ShipmentStatusEntrySchema = z.object({
  status: ShipmentStatusSchema,
  shipmentCount: z.coerce.number().int().nonnegative(),
});
export type ShipmentStatusEntry = z.infer<typeof ShipmentStatusEntrySchema>;

export function parseShipmentStatusEntry(row: Record<string, unknown>): ShipmentStatusEntry {
  return ShipmentStatusEntrySchema.parse({ status: row.status, shipmentCount: row.shipment_count });
}

export const MilestoneSlaEntrySchema = z.object({
  bucket: MilestoneSlaBucketSchema,
  shipmentCount: z.coerce.number().int().nonnegative(),
});
export type MilestoneSlaEntry = z.infer<typeof MilestoneSlaEntrySchema>;

export function parseMilestoneSlaEntry(row: Record<string, unknown>): MilestoneSlaEntry {
  return MilestoneSlaEntrySchema.parse({ bucket: row.bucket, shipmentCount: row.shipment_count });
}

export const ExceptionQueueEntrySchema = z.object({
  severity: ExceptionSeveritySchema,
  exceptionCount: z.coerce.number().int().nonnegative(),
});
export type ExceptionQueueEntry = z.infer<typeof ExceptionQueueEntrySchema>;

export function parseExceptionQueueEntry(row: Record<string, unknown>): ExceptionQueueEntry {
  return ExceptionQueueEntrySchema.parse({ severity: row.severity, exceptionCount: row.exception_count });
}

export const EpodCompletionEntrySchema = z.object({
  status: EpodCaptureStatusSchema,
  captureCount: z.coerce.number().int().nonnegative(),
});
export type EpodCompletionEntry = z.infer<typeof EpodCompletionEntrySchema>;

export function parseEpodCompletionEntry(row: Record<string, unknown>): EpodCompletionEntry {
  return EpodCompletionEntrySchema.parse({ status: row.status, captureCount: row.capture_count });
}

export const CostVarianceEntrySchema = z.object({
  bucket: CostVarianceBucketSchema,
  currency: z.string(),
  shipmentCount: z.coerce.number().int().nonnegative(),
  avgVariancePct: z.coerce.number().nullable(),
  varianceMasked: z.boolean(),
});
export type CostVarianceEntry = z.infer<typeof CostVarianceEntrySchema>;

export function parseCostVarianceEntry(row: Record<string, unknown>): CostVarianceEntry {
  return CostVarianceEntrySchema.parse({
    bucket: row.bucket,
    currency: row.currency,
    shipmentCount: row.shipment_count,
    avgVariancePct: row.avg_variance_pct,
    varianceMasked: row.variance_masked,
  });
}

export const BillingReadinessSummaryEntrySchema = z.object({
  bucket: BillingReadinessSummaryBucketSchema,
  jobCount: z.coerce.number().int().nonnegative(),
});
export type BillingReadinessSummaryEntry = z.infer<typeof BillingReadinessSummaryEntrySchema>;

export function parseBillingReadinessSummaryEntry(row: Record<string, unknown>): BillingReadinessSummaryEntry {
  return BillingReadinessSummaryEntrySchema.parse({ bucket: row.bucket, jobCount: row.job_count });
}
