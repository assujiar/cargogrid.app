/**
 * CRM Sales Plan and Pipeline contract (COM-146, CG-S7-COM-005). Mirrors
 * supabase/migrations/20260723180000_create_commercial_sales_pipeline.sql's
 * app.pipeline_categories/app.sales_plans/app.sales_targets/app.forecast_snapshots/
 * app.win_loss_reasons/app.pipeline_outcomes shape, app.commercial_pipeline_view's
 * (stage, record_count) summary shape, and their RPCs.
 */

import { z } from "zod";
import { RelatedTypeSchema, type RelatedType } from "../contact/contact.ts";

export const SALES_PLAN_STATUSES = ["draft", "published", "archived"] as const;
export const SalesPlanStatusSchema = z.enum(SALES_PLAN_STATUSES);
export type SalesPlanStatus = z.infer<typeof SalesPlanStatusSchema>;

export const SALES_TARGET_METRIC_TYPES = [
  "leads_captured",
  "leads_qualified",
  "prospects_created",
  "prospects_disqualified",
] as const;
export const SalesTargetMetricTypeSchema = z.enum(SALES_TARGET_METRIC_TYPES);
export type SalesTargetMetricType = z.infer<typeof SalesTargetMetricTypeSchema>;

export const PIPELINE_OUTCOMES = ["won", "lost"] as const;
export const PipelineOutcomeValueSchema = z.enum(PIPELINE_OUTCOMES);
export type PipelineOutcomeValue = z.infer<typeof PipelineOutcomeValueSchema>;

export const PIPELINE_STAGES = [
  "lead_new",
  "lead_contacted",
  "lead_qualified",
  "lead_lost",
  "lead_converted",
  "lead_merged",
  "prospect_active",
  "prospect_lost",
  "prospect_archived",
  "prospect_merged",
] as const;
export const PipelineStageSchema = z.enum(PIPELINE_STAGES);
export type PipelineStage = z.infer<typeof PipelineStageSchema>;

export const PipelineCategorySchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  code: z.string(),
  label: z.string(),
  sortOrder: z.number().int(),
  isActive: z.boolean(),
  recordVersion: z.number().int().positive(),
  createdBy: z.string().nullable(),
  createdAt: z.string(),
  updatedAt: z.string(),
});
export type PipelineCategory = z.infer<typeof PipelineCategorySchema>;

export const SalesPlanSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  orgUnitId: z.string().uuid().nullable(),
  name: z.string(),
  periodStart: z.string(),
  periodEnd: z.string(),
  status: SalesPlanStatusSchema,
  supersedesPlanId: z.string().uuid().nullable(),
  ownerUserId: z.string().uuid().nullable(),
  recordVersion: z.number().int().positive(),
  createdBy: z.string().nullable(),
  createdAt: z.string(),
  updatedAt: z.string(),
});
export type SalesPlan = z.infer<typeof SalesPlanSchema>;

export const SalesTargetSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  salesPlanId: z.string().uuid(),
  pipelineCategoryId: z.string().uuid().nullable(),
  metricType: SalesTargetMetricTypeSchema,
  orgUnitId: z.string().uuid().nullable(),
  ownerUserId: z.string().uuid().nullable(),
  targetValue: z.number().int().nonnegative(),
  recordVersion: z.number().int().positive(),
  createdBy: z.string().nullable(),
  createdAt: z.string(),
  updatedAt: z.string(),
});
export type SalesTarget = z.infer<typeof SalesTargetSchema>;

export const ForecastSnapshotSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  salesTargetId: z.string().uuid(),
  computedValue: z.number().int().nonnegative(),
  overrideValue: z.number().int().nonnegative().nullable(),
  overrideReason: z.string().nullable(),
  snapshotAt: z.string(),
  createdBy: z.string().nullable(),
  createdAt: z.string(),
});
export type ForecastSnapshot = z.infer<typeof ForecastSnapshotSchema>;

export const WinLossReasonSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  code: z.string(),
  label: z.string(),
  outcome: PipelineOutcomeValueSchema,
  isActive: z.boolean(),
  recordVersion: z.number().int().positive(),
  createdBy: z.string().nullable(),
  createdAt: z.string(),
  updatedAt: z.string(),
});
export type WinLossReason = z.infer<typeof WinLossReasonSchema>;

export const PipelineOutcomeSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  relatedType: RelatedTypeSchema,
  relatedId: z.string().uuid(),
  outcome: PipelineOutcomeValueSchema,
  winLossReasonId: z.string().uuid(),
  notes: z.string().nullable(),
  isCurrent: z.boolean(),
  supersededById: z.string().uuid().nullable(),
  recordedBy: z.string().nullable(),
  recordedAt: z.string(),
});
export type PipelineOutcome = z.infer<typeof PipelineOutcomeSchema>;

export const PipelineStageSummaryEntrySchema = z.object({
  stage: PipelineStageSchema,
  // app.get_pipeline_summary's record_count column is bigint; PostgREST may serialize it
  // as a JSON string to avoid float precision loss, so this coerces either shape.
  recordCount: z.coerce.number().int().nonnegative(),
});
export type PipelineStageSummaryEntry = z.infer<typeof PipelineStageSummaryEntrySchema>;

export const CreatePipelineCategoryInputSchema = z.object({
  tenantId: z.string().uuid(),
  code: z.string().min(1),
  label: z.string().min(1),
  sortOrder: z.number().int().default(0),
  actorAuthUserId: z.string().uuid(),
  createdBy: z.string().min(1),
});
export type CreatePipelineCategoryInput = z.input<typeof CreatePipelineCategoryInputSchema>;

export const UpdatePipelineCategoryInputSchema = z.object({
  categoryId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  label: z.string().min(1).nullable().default(null),
  sortOrder: z.number().int().nullable().default(null),
  isActive: z.boolean().nullable().default(null),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type UpdatePipelineCategoryInput = z.input<typeof UpdatePipelineCategoryInputSchema>;

export const CreateSalesPlanInputSchema = z.object({
  tenantId: z.string().uuid(),
  orgUnitId: z.string().uuid().nullable().default(null),
  name: z.string().min(1),
  periodStart: z.string(),
  periodEnd: z.string(),
  ownerUserId: z.string().uuid().nullable().default(null),
  actorAuthUserId: z.string().uuid(),
  createdBy: z.string().min(1),
});
export type CreateSalesPlanInput = z.input<typeof CreateSalesPlanInputSchema>;

export const PublishSalesPlanInputSchema = z.object({
  planId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  supersedesPlanId: z.string().uuid().nullable().default(null),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type PublishSalesPlanInput = z.input<typeof PublishSalesPlanInputSchema>;

export const ArchiveSalesPlanInputSchema = z.object({
  planId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type ArchiveSalesPlanInput = z.input<typeof ArchiveSalesPlanInputSchema>;

export const CreateSalesTargetInputSchema = z.object({
  salesPlanId: z.string().uuid(),
  pipelineCategoryId: z.string().uuid().nullable().default(null),
  metricType: SalesTargetMetricTypeSchema,
  orgUnitId: z.string().uuid().nullable().default(null),
  ownerUserId: z.string().uuid().nullable().default(null),
  targetValue: z.number().int().nonnegative(),
  actorAuthUserId: z.string().uuid(),
  createdBy: z.string().min(1),
});
export type CreateSalesTargetInput = z.input<typeof CreateSalesTargetInputSchema>;

export const UpdateSalesTargetInputSchema = z.object({
  targetId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  targetValue: z.number().int().nonnegative(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type UpdateSalesTargetInput = z.input<typeof UpdateSalesTargetInputSchema>;

export const CaptureForecastSnapshotInputSchema = z.object({
  salesTargetId: z.string().uuid(),
  overrideValue: z.number().int().nonnegative().nullable().default(null),
  overrideReason: z.string().min(1).nullable().default(null),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type CaptureForecastSnapshotInput = z.input<typeof CaptureForecastSnapshotInputSchema>;

export const CreateWinLossReasonInputSchema = z.object({
  tenantId: z.string().uuid(),
  code: z.string().min(1),
  label: z.string().min(1),
  outcome: PipelineOutcomeValueSchema,
  actorAuthUserId: z.string().uuid(),
  createdBy: z.string().min(1),
});
export type CreateWinLossReasonInput = z.input<typeof CreateWinLossReasonInputSchema>;

export const UpdateWinLossReasonInputSchema = z.object({
  reasonId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  label: z.string().min(1).nullable().default(null),
  isActive: z.boolean().nullable().default(null),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type UpdateWinLossReasonInput = z.input<typeof UpdateWinLossReasonInputSchema>;

export const RecordPipelineOutcomeInputSchema = z.object({
  relatedType: RelatedTypeSchema,
  relatedId: z.string().uuid(),
  outcome: PipelineOutcomeValueSchema,
  winLossReasonId: z.string().uuid(),
  notes: z.string().nullable().default(null),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type RecordPipelineOutcomeInput = z.input<typeof RecordPipelineOutcomeInputSchema>;

export const GetPipelineSummaryInputSchema = z.object({
  tenantId: z.string().uuid(),
  orgUnitId: z.string().uuid().nullable().default(null),
});
export type GetPipelineSummaryInput = z.input<typeof GetPipelineSummaryInputSchema>;

/** Maps a raw app.pipeline_categories row (snake_case) to this contract's camelCase shape. */
export function parsePipelineCategory(row: Record<string, unknown>): PipelineCategory {
  return PipelineCategorySchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    code: row.code,
    label: row.label,
    sortOrder: row.sort_order,
    isActive: row.is_active,
    recordVersion: row.record_version,
    createdBy: row.created_by,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  });
}

/** Maps a raw app.sales_plans row (snake_case) to this contract's camelCase shape. */
export function parseSalesPlan(row: Record<string, unknown>): SalesPlan {
  return SalesPlanSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    orgUnitId: row.org_unit_id,
    name: row.name,
    periodStart: row.period_start,
    periodEnd: row.period_end,
    status: row.status,
    supersedesPlanId: row.supersedes_plan_id,
    ownerUserId: row.owner_user_id,
    recordVersion: row.record_version,
    createdBy: row.created_by,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  });
}

/** Maps a raw app.sales_targets row (snake_case) to this contract's camelCase shape. */
export function parseSalesTarget(row: Record<string, unknown>): SalesTarget {
  return SalesTargetSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    salesPlanId: row.sales_plan_id,
    pipelineCategoryId: row.pipeline_category_id,
    metricType: row.metric_type,
    orgUnitId: row.org_unit_id,
    ownerUserId: row.owner_user_id,
    targetValue: row.target_value,
    recordVersion: row.record_version,
    createdBy: row.created_by,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  });
}

/** Maps a raw app.forecast_snapshots row (snake_case) to this contract's camelCase shape. */
export function parseForecastSnapshot(row: Record<string, unknown>): ForecastSnapshot {
  return ForecastSnapshotSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    salesTargetId: row.sales_target_id,
    computedValue: row.computed_value,
    overrideValue: row.override_value,
    overrideReason: row.override_reason,
    snapshotAt: row.snapshot_at,
    createdBy: row.created_by,
    createdAt: row.created_at,
  });
}

/** Maps a raw app.win_loss_reasons row (snake_case) to this contract's camelCase shape. */
export function parseWinLossReason(row: Record<string, unknown>): WinLossReason {
  return WinLossReasonSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    code: row.code,
    label: row.label,
    outcome: row.outcome,
    isActive: row.is_active,
    recordVersion: row.record_version,
    createdBy: row.created_by,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  });
}

/** Maps a raw app.pipeline_outcomes row (snake_case) to this contract's camelCase shape. */
export function parsePipelineOutcome(row: Record<string, unknown>): PipelineOutcome {
  return PipelineOutcomeSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    relatedType: row.related_type,
    relatedId: row.related_id,
    outcome: row.outcome,
    winLossReasonId: row.win_loss_reason_id,
    notes: row.notes,
    isCurrent: row.is_current,
    supersededById: row.superseded_by_id,
    recordedBy: row.recorded_by,
    recordedAt: row.recorded_at,
  });
}

/** Maps a raw app.get_pipeline_summary row (stage, record_count) to this contract's camelCase shape. */
export function parsePipelineStageSummaryEntry(row: Record<string, unknown>): PipelineStageSummaryEntry {
  return PipelineStageSummaryEntrySchema.parse({
    stage: row.stage,
    recordCount: row.record_count,
  });
}

export type { RelatedType };
