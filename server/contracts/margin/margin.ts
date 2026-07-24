/**
 * Margin Calculation contract (COM-150, CG-S7-COM-009). Mirrors
 * supabase/migrations/20260724180000_create_commercial_margin_calculation.sql's
 * app.margin_rule_versions/app.margin_calculations/app.margin_calculations_directory
 * shape and their RPCs.
 */

import { z } from "zod";

export const MARGIN_RULE_STATUSES = ["draft", "published", "archived"] as const;
export const MarginRuleStatusSchema = z.enum(MARGIN_RULE_STATUSES);
export type MarginRuleStatus = z.infer<typeof MarginRuleStatusSchema>;

export const ROUNDING_MODES = ["half_up", "half_even", "floor", "ceiling"] as const;
export const RoundingModeSchema = z.enum(ROUNDING_MODES);
export type RoundingMode = z.infer<typeof RoundingModeSchema>;

export const THRESHOLD_OUTCOMES = ["pass", "requires_approval"] as const;
export const ThresholdOutcomeSchema = z.enum(THRESHOLD_OUTCOMES);
export type ThresholdOutcome = z.infer<typeof ThresholdOutcomeSchema>;

/** Maps a raw app.margin_rule_versions row (snake_case) to this contract's camelCase shape. Tenant-wide reference/policy data -- never field-masked (COM-150 migration header). */
export const MarginRuleVersionSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  minimumMarginPct: z.coerce.number(),
  roundingMode: RoundingModeSchema,
  status: MarginRuleStatusSchema,
  supersedesVersionId: z.string().uuid().nullable(),
  recordVersion: z.number().int().positive(),
  createdBy: z.string().nullable(),
  createdAt: z.string(),
  updatedAt: z.string(),
});
export type MarginRuleVersion = z.infer<typeof MarginRuleVersionSchema>;

export function parseMarginRuleVersion(row: Record<string, unknown>): MarginRuleVersion {
  return MarginRuleVersionSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    minimumMarginPct: row.minimum_margin_pct,
    roundingMode: row.rounding_mode,
    status: row.status,
    supersedesVersionId: row.supersedes_version_id,
    recordVersion: row.record_version,
    createdBy: row.created_by,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  });
}

/** Maps a raw app.margin_calculations_directory row (snake_case) to this contract's camelCase shape -- two independent masking dimensions (cost_masked for cost/margin/markup, sell_masked for sell/discount/net-sell). */
export const MarginCalculationSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  costingRequestId: z.string().uuid(),
  rateSelectionId: z.string().uuid(),
  costAmount: z.coerce.number().nullable(),
  costCurrency: z.string(),
  sellAmount: z.coerce.number().nullable(),
  sellCurrency: z.string(),
  discountPct: z.coerce.number().nullable(),
  discountAmount: z.coerce.number().nullable(),
  netSellAmount: z.coerce.number().nullable(),
  marginAmount: z.coerce.number().nullable(),
  marginPct: z.coerce.number().nullable(),
  markupPct: z.coerce.number().nullable(),
  costMasked: z.boolean(),
  sellMasked: z.boolean(),
  ruleVersionId: z.string().uuid(),
  minimumMarginPctSnapshot: z.coerce.number(),
  roundingModeSnapshot: RoundingModeSchema,
  thresholdOutcome: ThresholdOutcomeSchema,
  isOverridden: z.boolean(),
  overrideReason: z.string().nullable(),
  overrideBy: z.string().nullable(),
  overrideAt: z.string().nullable(),
  isCurrent: z.boolean(),
  supersededById: z.string().uuid().nullable(),
  recordVersion: z.number().int().positive(),
  createdBy: z.string().nullable(),
  createdAt: z.string(),
  updatedAt: z.string(),
});
export type MarginCalculation = z.infer<typeof MarginCalculationSchema>;

export function parseMarginCalculation(row: Record<string, unknown>): MarginCalculation {
  return MarginCalculationSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    costingRequestId: row.costing_request_id,
    rateSelectionId: row.rate_selection_id,
    costAmount: row.cost_amount,
    costCurrency: row.cost_currency,
    sellAmount: row.sell_amount,
    sellCurrency: row.sell_currency,
    discountPct: row.discount_pct,
    discountAmount: row.discount_amount,
    netSellAmount: row.net_sell_amount,
    marginAmount: row.margin_amount,
    marginPct: row.margin_pct,
    markupPct: row.markup_pct,
    costMasked: row.cost_masked,
    sellMasked: row.sell_masked,
    ruleVersionId: row.rule_version_id,
    minimumMarginPctSnapshot: row.minimum_margin_pct_snapshot,
    roundingModeSnapshot: row.rounding_mode_snapshot,
    thresholdOutcome: row.threshold_outcome,
    isOverridden: row.is_overridden,
    overrideReason: row.override_reason,
    overrideBy: row.override_by,
    overrideAt: row.override_at,
    isCurrent: row.is_current,
    supersededById: row.superseded_by_id,
    recordVersion: row.record_version,
    createdBy: row.created_by,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  });
}

export const CreateMarginRuleVersionInputSchema = z.object({
  tenantId: z.string().uuid(),
  minimumMarginPct: z.number().min(0).max(100),
  roundingMode: RoundingModeSchema.default("half_up"),
  actorAuthUserId: z.string().uuid(),
  createdBy: z.string().min(1),
});
export type CreateMarginRuleVersionInput = z.input<typeof CreateMarginRuleVersionInputSchema>;

export const PublishMarginRuleVersionInputSchema = z.object({
  ruleVersionId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  supersedesVersionId: z.string().uuid().nullable().default(null),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type PublishMarginRuleVersionInput = z.input<typeof PublishMarginRuleVersionInputSchema>;

export const CalculateMarginInputSchema = z.object({
  rateSelectionId: z.string().uuid(),
  sellAmount: z.number().nonnegative(),
  sellCurrency: z.string().regex(/^[A-Z]{3}$/),
  discountPct: z.number().min(0).max(100).default(0),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type CalculateMarginInput = z.input<typeof CalculateMarginInputSchema>;

export const OverrideMarginThresholdInputSchema = z.object({
  marginCalculationId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  reason: z.string().min(1),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type OverrideMarginThresholdInput = z.input<typeof OverrideMarginThresholdInputSchema>;
