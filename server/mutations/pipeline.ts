/**
 * CRM Sales Plan and Pipeline mutation primitives (COM-146, CG-S7-COM-005). Thin, typed
 * wrappers around app.create_pipeline_category / app.update_pipeline_category /
 * app.create_sales_plan / app.publish_sales_plan / app.archive_sales_plan /
 * app.create_sales_target / app.update_sales_target / app.capture_forecast_snapshot /
 * app.create_win_loss_reason / app.update_win_loss_reason / app.record_pipeline_outcome
 * (supabase/migrations/20260723180000_create_commercial_sales_pipeline.sql).
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import {
  CreatePipelineCategoryInputSchema,
  UpdatePipelineCategoryInputSchema,
  CreateSalesPlanInputSchema,
  PublishSalesPlanInputSchema,
  ArchiveSalesPlanInputSchema,
  CreateSalesTargetInputSchema,
  UpdateSalesTargetInputSchema,
  CaptureForecastSnapshotInputSchema,
  CreateWinLossReasonInputSchema,
  UpdateWinLossReasonInputSchema,
  RecordPipelineOutcomeInputSchema,
  parsePipelineCategory,
  parseSalesPlan,
  parseSalesTarget,
  parseForecastSnapshot,
  parseWinLossReason,
  parsePipelineOutcome,
  type CreatePipelineCategoryInput,
  type UpdatePipelineCategoryInput,
  type CreateSalesPlanInput,
  type PublishSalesPlanInput,
  type ArchiveSalesPlanInput,
  type CreateSalesTargetInput,
  type UpdateSalesTargetInput,
  type CaptureForecastSnapshotInput,
  type CreateWinLossReasonInput,
  type UpdateWinLossReasonInput,
  type RecordPipelineOutcomeInput,
  type PipelineCategory,
  type SalesPlan,
  type SalesTarget,
  type ForecastSnapshot,
  type WinLossReason,
  type PipelineOutcome,
} from "../contracts/pipeline/pipeline.ts";

export type PipelineMutationRpcClient = Pick<SupabaseClient, "rpc">;

export const PIPELINE_KNOWN_MUTATION_ERROR_CODES = [
  "insufficient_authority",
  "pipeline_category_not_found",
  "sales_plan_not_found",
  "sales_target_not_found",
  "win_loss_reason_not_found",
  "superseded_plan_not_found",
  "unknown_related_type",
  "related_record_not_found",
  "cross_tenant_reason_denied",
  "reason_outcome_mismatch",
  "stale_version",
  "invalid_transition",
  "invalid_period",
  "invalid_supersede",
  "overlapping_plan",
  "invalid_target_value",
  "override_reason_required",
  "duplicate_category_code",
  "duplicate_reason_code",
  "duplicate_target",
] as const;
type KnownPipelineMutationErrorCode = (typeof PIPELINE_KNOWN_MUTATION_ERROR_CODES)[number];
export type PipelineMutationErrorCode = KnownPipelineMutationErrorCode | "mutation_failed" | "invalid_response";

export class PipelineMutationError extends Error {
  readonly code: PipelineMutationErrorCode;

  constructor(code: PipelineMutationErrorCode, message: string) {
    super(message);
    this.name = "PipelineMutationError";
    this.code = code;
  }
}

function classifyError(message: string): PipelineMutationErrorCode {
  const prefix = message.split(":")[0]?.trim();
  return (PIPELINE_KNOWN_MUTATION_ERROR_CODES as readonly string[]).includes(prefix ?? "")
    ? (prefix as KnownPipelineMutationErrorCode)
    : "mutation_failed";
}

async function callRpc(client: PipelineMutationRpcClient, fn: string, args: Record<string, unknown>): Promise<unknown> {
  const { data, error } = await client.rpc(fn, args);
  if (error) {
    throw new PipelineMutationError(classifyError(error.message), error.message);
  }
  return data;
}

async function callAndParse<T>(
  client: PipelineMutationRpcClient,
  fn: string,
  args: Record<string, unknown>,
  parse: (row: Record<string, unknown>) => T,
): Promise<T> {
  const data = await callRpc(client, fn, args);
  if (!data || typeof data !== "object") {
    throw new PipelineMutationError("invalid_response", `${fn} returned no row`);
  }
  return parse(data as Record<string, unknown>);
}

/** Duplicate code (tenant-scoped) raises duplicate_category_code. */
export async function createPipelineCategory(client: PipelineMutationRpcClient, input: CreatePipelineCategoryInput): Promise<PipelineCategory> {
  const parsedInput = CreatePipelineCategoryInputSchema.parse(input);
  return callAndParse(
    client,
    "create_pipeline_category",
    {
      p_tenant_id: parsedInput.tenantId,
      p_code: parsedInput.code,
      p_label: parsedInput.label,
      p_sort_order: parsedInput.sortOrder,
      p_actor_auth_user_id: parsedInput.actorAuthUserId,
      p_created_by: parsedInput.createdBy,
    },
    parsePipelineCategory,
  );
}

/** Partial update (label/sortOrder/isActive) with optimistic concurrency -- pass null to leave a field unchanged. */
export async function updatePipelineCategory(client: PipelineMutationRpcClient, input: UpdatePipelineCategoryInput): Promise<PipelineCategory> {
  const parsedInput = UpdatePipelineCategoryInputSchema.parse(input);
  return callAndParse(
    client,
    "update_pipeline_category",
    {
      p_category_id: parsedInput.categoryId,
      p_expected_version: parsedInput.expectedVersion,
      p_label: parsedInput.label,
      p_sort_order: parsedInput.sortOrder,
      p_is_active: parsedInput.isActive,
      p_actor_auth_user_id: parsedInput.actorAuthUserId,
      p_actor_label: parsedInput.actorLabel,
    },
    parsePipelineCategory,
  );
}

/** Always creates a new plan in draft status. */
export async function createSalesPlan(client: PipelineMutationRpcClient, input: CreateSalesPlanInput): Promise<SalesPlan> {
  const parsedInput = CreateSalesPlanInputSchema.parse(input);
  return callAndParse(
    client,
    "create_sales_plan",
    {
      p_tenant_id: parsedInput.tenantId,
      p_org_unit_id: parsedInput.orgUnitId,
      p_name: parsedInput.name,
      p_period_start: parsedInput.periodStart,
      p_period_end: parsedInput.periodEnd,
      p_owner_user_id: parsedInput.ownerUserId,
      p_actor_auth_user_id: parsedInput.actorAuthUserId,
      p_created_by: parsedInput.createdBy,
    },
    parseSalesPlan,
  );
}

/** draft -> published. supersedesPlanId, when set, atomically archives that prior published plan -- the "versioned plan" mechanism. */
export async function publishSalesPlan(client: PipelineMutationRpcClient, input: PublishSalesPlanInput): Promise<SalesPlan> {
  const parsedInput = PublishSalesPlanInputSchema.parse(input);
  return callAndParse(
    client,
    "publish_sales_plan",
    {
      p_plan_id: parsedInput.planId,
      p_expected_version: parsedInput.expectedVersion,
      p_supersedes_plan_id: parsedInput.supersedesPlanId,
      p_actor_auth_user_id: parsedInput.actorAuthUserId,
      p_actor_label: parsedInput.actorLabel,
    },
    parseSalesPlan,
  );
}

/** draft or published -> archived. */
export async function archiveSalesPlan(client: PipelineMutationRpcClient, input: ArchiveSalesPlanInput): Promise<SalesPlan> {
  const parsedInput = ArchiveSalesPlanInputSchema.parse(input);
  return callAndParse(
    client,
    "archive_sales_plan",
    {
      p_plan_id: parsedInput.planId,
      p_expected_version: parsedInput.expectedVersion,
      p_actor_auth_user_id: parsedInput.actorAuthUserId,
      p_actor_label: parsedInput.actorLabel,
    },
    parseSalesPlan,
  );
}

/** Only allowed while the parent plan is draft. Duplicate (plan, metric, org unit, owner) raises duplicate_target. */
export async function createSalesTarget(client: PipelineMutationRpcClient, input: CreateSalesTargetInput): Promise<SalesTarget> {
  const parsedInput = CreateSalesTargetInputSchema.parse(input);
  return callAndParse(
    client,
    "create_sales_target",
    {
      p_sales_plan_id: parsedInput.salesPlanId,
      p_pipeline_category_id: parsedInput.pipelineCategoryId,
      p_metric_type: parsedInput.metricType,
      p_org_unit_id: parsedInput.orgUnitId,
      p_owner_user_id: parsedInput.ownerUserId,
      p_target_value: parsedInput.targetValue,
      p_actor_auth_user_id: parsedInput.actorAuthUserId,
      p_created_by: parsedInput.createdBy,
    },
    parseSalesTarget,
  );
}

/** Only allowed while the parent plan is draft. */
export async function updateSalesTarget(client: PipelineMutationRpcClient, input: UpdateSalesTargetInput): Promise<SalesTarget> {
  const parsedInput = UpdateSalesTargetInputSchema.parse(input);
  return callAndParse(
    client,
    "update_sales_target",
    {
      p_target_id: parsedInput.targetId,
      p_expected_version: parsedInput.expectedVersion,
      p_target_value: parsedInput.targetValue,
      p_actor_auth_user_id: parsedInput.actorAuthUserId,
      p_actor_label: parsedInput.actorLabel,
    },
    parseSalesTarget,
  );
}

/** Recomputes the target's actual from canonical Lead/Prospect data and captures a point-in-time snapshot. An overrideValue requires a non-empty overrideReason. */
export async function captureForecastSnapshot(client: PipelineMutationRpcClient, input: CaptureForecastSnapshotInput): Promise<ForecastSnapshot> {
  const parsedInput = CaptureForecastSnapshotInputSchema.parse(input);
  return callAndParse(
    client,
    "capture_forecast_snapshot",
    {
      p_sales_target_id: parsedInput.salesTargetId,
      p_override_value: parsedInput.overrideValue,
      p_override_reason: parsedInput.overrideReason,
      p_actor_auth_user_id: parsedInput.actorAuthUserId,
      p_actor_label: parsedInput.actorLabel,
    },
    parseForecastSnapshot,
  );
}

/** Duplicate code (tenant-scoped) raises duplicate_reason_code. */
export async function createWinLossReason(client: PipelineMutationRpcClient, input: CreateWinLossReasonInput): Promise<WinLossReason> {
  const parsedInput = CreateWinLossReasonInputSchema.parse(input);
  return callAndParse(
    client,
    "create_win_loss_reason",
    {
      p_tenant_id: parsedInput.tenantId,
      p_code: parsedInput.code,
      p_label: parsedInput.label,
      p_outcome: parsedInput.outcome,
      p_actor_auth_user_id: parsedInput.actorAuthUserId,
      p_created_by: parsedInput.createdBy,
    },
    parseWinLossReason,
  );
}

/** Partial update (label/isActive) with optimistic concurrency -- pass null to leave a field unchanged. */
export async function updateWinLossReason(client: PipelineMutationRpcClient, input: UpdateWinLossReasonInput): Promise<WinLossReason> {
  const parsedInput = UpdateWinLossReasonInputSchema.parse(input);
  return callAndParse(
    client,
    "update_win_loss_reason",
    {
      p_reason_id: parsedInput.reasonId,
      p_expected_version: parsedInput.expectedVersion,
      p_label: parsedInput.label,
      p_is_active: parsedInput.isActive,
      p_actor_auth_user_id: parsedInput.actorAuthUserId,
      p_actor_label: parsedInput.actorLabel,
    },
    parseWinLossReason,
  );
}

/** Additive win/loss categorization -- never mutates the source lead/prospect row. Superseding a prior current outcome preserves it, it is never overwritten. */
export async function recordPipelineOutcome(client: PipelineMutationRpcClient, input: RecordPipelineOutcomeInput): Promise<PipelineOutcome> {
  const parsedInput = RecordPipelineOutcomeInputSchema.parse(input);
  return callAndParse(
    client,
    "record_pipeline_outcome",
    {
      p_related_type: parsedInput.relatedType,
      p_related_id: parsedInput.relatedId,
      p_outcome: parsedInput.outcome,
      p_win_loss_reason_id: parsedInput.winLossReasonId,
      p_notes: parsedInput.notes,
      p_actor_auth_user_id: parsedInput.actorAuthUserId,
      p_actor_label: parsedInput.actorLabel,
    },
    parsePipelineOutcome,
  );
}
