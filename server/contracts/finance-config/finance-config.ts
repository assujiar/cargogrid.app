/**
 * Finance Configuration contract (FIN-191, CG-S9-FIN-002). Mirrors
 * supabase/migrations/20260728200000_create_finance_configuration.sql's six
 * finance-owned `app.config_types` rows and the
 * app.create_finance_config_draft / app.set_finance_config_items /
 * app.publish_finance_config_version / app.discard_finance_config_draft /
 * app.rollback_finance_config_version / app.resolve_finance_config /
 * app.preview_finance_config_impact RPCs -- all thin, authority-checked
 * wrappers around PLT-121's own generic Configuration Engine, reused directly
 * rather than reinventing a versioned-policy state machine (this migration's
 * own header; docs/build-log/phase-04/00_FINANCE_WBS.md §6).
 *
 * Reuses PLT-121's own `ConfigVersion`/`parseConfigVersion` shape directly
 * (server/contracts/config/config.ts) -- a Finance config_version is
 * structurally identical to any other config_version, only the config_type_code
 * and the per-class item value shape differ.
 */

import { z } from "zod";
import { ConfigVersionSchema, parseConfigVersion, type ConfigVersion } from "../config/config.ts";

export const FINANCE_CONFIG_CLASSES = [
  "finance_dimensions",
  "finance_numbering",
  "finance_posting_map",
  "finance_rounding",
  "finance_recognition",
  "finance_close_policy",
] as const;
export const FinanceConfigClassSchema = z.enum(FINANCE_CONFIG_CLASSES);
export type FinanceConfigClass = z.infer<typeof FinanceConfigClassSchema>;

export const FINANCE_ROUNDING_MODES = ["round_half_up", "round_half_even", "round_down", "round_up"] as const;
export const FinanceRoundingModeSchema = z.enum(FINANCE_ROUNDING_MODES);
export type FinanceRoundingMode = z.infer<typeof FinanceRoundingModeSchema>;

export const FinanceRoundingModeInfoSchema = z.object({
  code: FinanceRoundingModeSchema,
  name: z.string(),
  description: z.string(),
});
export type FinanceRoundingModeInfo = z.infer<typeof FinanceRoundingModeInfoSchema>;

/** Maps a raw app.finance_rounding_modes row (snake_case) to this contract's camelCase shape. */
export function parseFinanceRoundingModeInfo(row: Record<string, unknown>): FinanceRoundingModeInfo {
  return FinanceRoundingModeInfoSchema.parse({ code: row.code, name: row.name, description: row.description });
}

// -- Per-class item value shapes (documented, structurally validated in the
// -- database at publish/preview time by app.validate_finance_config_version;
// -- these client-side schemas exist for form validation and typed UI
// -- consumption, never as a second source of truth for the real gate). --

export const FinanceDimensionValueSchema = z.object({
  name: z.string().min(1),
  required: z.boolean(),
  valueSourceRef: z.string().nullable().default(null),
});
export type FinanceDimensionValue = z.infer<typeof FinanceDimensionValueSchema>;

export const FinanceNumberingValueSchema = z.object({
  prefix: z.string().nullable().default(null),
  format: z.string().min(1),
  resetPeriod: z.enum(["never", "yearly", "monthly"]),
  padding: z.number().int().min(1).max(10),
});
export type FinanceNumberingValue = z.infer<typeof FinanceNumberingValueSchema>;

export const FinancePostingMapValueSchema = z.object({
  accountCodeRef: z.string().regex(/^[A-Z0-9._-]{1,20}$/),
  dimensionDefaults: z.record(z.string(), z.string()).default({}),
});
export type FinancePostingMapValue = z.infer<typeof FinancePostingMapValueSchema>;

export const FinanceRoundingValueSchema = z.object({
  mode: FinanceRoundingModeSchema,
  precision: z.number().int().min(0).max(6),
  order: z.enum(["convert_then_round", "round_then_convert"]),
});
export type FinanceRoundingValue = z.infer<typeof FinanceRoundingValueSchema>;

export const FinanceRecognitionPolicyValueSchema = z.object({
  budgetControlMode: z.enum(["none", "advisory", "hard_block"]),
  accrualMethod: z.enum(["cash", "accrual"]),
  revenueRecognitionMethod: z.enum(["invoice_date", "delivery_date", "milestone"]),
  costRecognitionMethod: z.enum(["invoice_date", "incurred_date", "milestone"]),
});
export type FinanceRecognitionPolicyValue = z.infer<typeof FinanceRecognitionPolicyValueSchema>;

export const FinanceClosePolicyValueSchema = z.object({
  label: z.string().min(1),
  required: z.boolean(),
  sourceCapability: z.string().nullable().default(null),
});
export type FinanceClosePolicyValue = z.infer<typeof FinanceClosePolicyValueSchema>;

export const FinanceConfigItemInputSchema = z.object({
  key: z.string().min(1),
  value: z.record(z.string(), z.unknown()),
});
export type FinanceConfigItemInput = z.input<typeof FinanceConfigItemInputSchema>;

const ScopeFieldsSchema = z.object({
  configTypeCode: FinanceConfigClassSchema,
  tenantId: z.string().uuid().nullable(),
  scopeLevel: z.enum(["global", "tenant", "company", "branch", "role", "user"]),
  scopeId: z.string().uuid().nullable(),
});

export const CreateFinanceConfigDraftInputSchema = ScopeFieldsSchema.extend({
  actorAuthUserId: z.string().uuid(),
  createdBy: z.string().min(1),
});
export type CreateFinanceConfigDraftInput = z.infer<typeof CreateFinanceConfigDraftInputSchema>;

export const SetFinanceConfigItemsInputSchema = z.object({
  versionId: z.string().uuid(),
  items: z.array(FinanceConfigItemInputSchema).default([]),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type SetFinanceConfigItemsInput = z.input<typeof SetFinanceConfigItemsInputSchema>;

export const PublishFinanceConfigVersionInputSchema = z.object({
  versionId: z.string().uuid(),
  actorAuthUserId: z.string().uuid(),
  effectiveFrom: z.string().nullable().default(null),
  actorLabel: z.string().min(1),
});
export type PublishFinanceConfigVersionInput = z.input<typeof PublishFinanceConfigVersionInputSchema>;

export const DiscardFinanceConfigDraftInputSchema = z.object({
  versionId: z.string().uuid(),
  actorAuthUserId: z.string().uuid(),
  reason: z.string().nullable().default(null),
  actorLabel: z.string().min(1),
});
export type DiscardFinanceConfigDraftInput = z.input<typeof DiscardFinanceConfigDraftInputSchema>;

export const RollbackFinanceConfigVersionInputSchema = z.object({
  targetVersionId: z.string().uuid(),
  actorAuthUserId: z.string().uuid(),
  reason: z.string().nullable().default(null),
  actorLabel: z.string().min(1),
});
export type RollbackFinanceConfigVersionInput = z.input<typeof RollbackFinanceConfigVersionInputSchema>;

const PrecedenceScopeSchema = z.object({
  configTypeCode: FinanceConfigClassSchema,
  tenantId: z.string().uuid().nullable(),
  companyId: z.string().uuid().nullable().default(null),
  branchId: z.string().uuid().nullable().default(null),
  roleId: z.string().uuid().nullable().default(null),
  userId: z.string().uuid().nullable().default(null),
});

export const ResolveFinanceConfigInputSchema = PrecedenceScopeSchema;
export type ResolveFinanceConfigInput = z.input<typeof ResolveFinanceConfigInputSchema>;

export const ResolvedFinanceConfigSchema = z.object({
  configTypeCode: FinanceConfigClassSchema,
  resolvedScopeLevel: z.enum(["global", "tenant", "company", "branch", "role", "user"]),
  resolvedVersionId: z.string().uuid(),
  effectiveFrom: z.string(),
  items: z.record(z.string(), z.unknown()),
});
export type ResolvedFinanceConfig = z.infer<typeof ResolvedFinanceConfigSchema>;

export const FinanceConfigImpactPreviewSchema = z.object({
  configTypeCode: FinanceConfigClassSchema,
  valid: z.boolean(),
  error: z.string().nullable(),
  itemCount: z.number().int(),
  pendingChartOfAccountsRefs: z.array(z.string()).nullable(),
});
export type FinanceConfigImpactPreview = z.infer<typeof FinanceConfigImpactPreviewSchema>;

export { ConfigVersionSchema, parseConfigVersion };
export type { ConfigVersion };

/** Maps a raw app.resolve_finance_config() row (snake_case) to this contract's camelCase shape. */
export function parseResolvedFinanceConfig(row: Record<string, unknown>): ResolvedFinanceConfig {
  return ResolvedFinanceConfigSchema.parse({
    configTypeCode: row.config_type_code,
    resolvedScopeLevel: row.resolved_scope_level,
    resolvedVersionId: row.resolved_version_id,
    effectiveFrom: row.effective_from,
    items: row.items,
  });
}

/** Maps a raw app.preview_finance_config_impact() jsonb result to this contract's camelCase shape. */
export function parseFinanceConfigImpactPreview(row: Record<string, unknown>): FinanceConfigImpactPreview {
  return FinanceConfigImpactPreviewSchema.parse({
    configTypeCode: row.configTypeCode,
    valid: row.valid,
    error: row.error ?? null,
    itemCount: row.itemCount,
    pendingChartOfAccountsRefs: row.pendingChartOfAccountsRefs ?? null,
  });
}
