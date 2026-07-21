/**
 * Feature flag contract (PLT-133, CG-S6-PLT-030). Mirrors
 * supabase/migrations/20260721090000_create_feature_flags_platform.sql's
 * app.feature_flags shape and app.feature_flag_decision composite type, plus the
 * app.register_feature_flag / app.create_feature_flag_draft / app.set_feature_flag_items /
 * app.evaluate_feature_flag / app.kill_feature_flag / app.debug_feature_flag RPCs.
 *
 * Draft/publish/discard/rollback for a flag's target versions reuse PLT-121's own
 * app.create_config_draft-family contracts directly (server/contracts/config/config.ts)
 * with configTypeCode = `feature:${flagKey}` -- not re-declared here, the same
 * "shared mechanism, not a fork" discipline the migration's own header established.
 */

import { z } from "zod";

export const FEATURE_FLAG_ENVIRONMENTS = ["local", "development", "testing", "staging", "uat", "production", "sandbox"] as const;
export const FeatureFlagEnvironmentSchema = z.enum(FEATURE_FLAG_ENVIRONMENTS);
export type FeatureFlagEnvironment = z.infer<typeof FeatureFlagEnvironmentSchema>;

export const FEATURE_FLAG_TENANT_STATES = ["allow", "deny", "inherit"] as const;
export const FeatureFlagTenantStateSchema = z.enum(FEATURE_FLAG_TENANT_STATES);
export type FeatureFlagTenantState = z.infer<typeof FeatureFlagTenantStateSchema>;

export const FEATURE_FLAG_DECISION_REASONS = [
  "unknown_flag",
  "module_not_entitled",
  "unconfigured",
  "kill_switch",
  "environment_gate",
  "tenant_override_deny",
  "tenant_override_allow",
  "cohort_mismatch",
  "rollout_bucket",
  "default",
] as const;
export const FeatureFlagDecisionReasonSchema = z.enum(FEATURE_FLAG_DECISION_REASONS);
export type FeatureFlagDecisionReason = z.infer<typeof FeatureFlagDecisionReasonSchema>;

export const FeatureFlagSchema = z.object({
  flagKey: z.string().min(1),
  name: z.string(),
  description: z.string().nullable(),
  moduleCode: z.string().nullable(),
  registeredBy: z.string().nullable(),
  createdAt: z.string(),
});
export type FeatureFlag = z.infer<typeof FeatureFlagSchema>;

export const FeatureFlagDecisionSchema = z.object({
  enabled: z.boolean(),
  reason: FeatureFlagDecisionReasonSchema,
  resolvedScopeLevel: z.enum(["global", "tenant"]).nullable(),
  resolvedVersionId: z.string().uuid().nullable(),
  evaluatedAt: z.string(),
});
export type FeatureFlagDecision = z.infer<typeof FeatureFlagDecisionSchema>;

export const RegisterFeatureFlagInputSchema = z.object({
  flagKey: z
    .string()
    .min(2)
    .max(64)
    .regex(/^[a-z][a-z0-9_.]{1,63}$/, "must be a lowercase identifier (letters, digits, '_', '.')"),
  name: z.string().min(1),
  description: z.string().nullable().default(null),
  moduleCode: z.string().min(1).nullable().default(null),
  actorAuthUserId: z.string().uuid(),
  registeredBy: z.string().min(1),
});
export type RegisterFeatureFlagInput = z.input<typeof RegisterFeatureFlagInputSchema>;

export const CreateFeatureFlagDraftInputSchema = z.object({
  flagKey: z.string().min(1),
  tenantId: z.string().uuid().nullable(),
  scopeLevel: z.enum(["global", "tenant"]),
  actorAuthUserId: z.string().uuid(),
  createdBy: z.string().min(1),
});
export type CreateFeatureFlagDraftInput = z.infer<typeof CreateFeatureFlagDraftInputSchema>;

export const SetFeatureFlagItemsInputSchema = z.object({
  versionId: z.string().uuid(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
  killSwitch: z.boolean().nullable().default(null),
  environments: z.array(FeatureFlagEnvironmentSchema).nullable().default(null),
  rolloutPercentage: z.number().int().min(0).max(100).nullable().default(null),
  cohorts: z.array(z.string().min(1)).nullable().default(null),
  tenantState: FeatureFlagTenantStateSchema.nullable().default(null),
});
export type SetFeatureFlagItemsInput = z.input<typeof SetFeatureFlagItemsInputSchema>;

export const EvaluateFeatureFlagInputSchema = z.object({
  flagKey: z.string().min(1),
  tenantId: z.string().uuid().nullable(),
  environment: FeatureFlagEnvironmentSchema,
  cohorts: z.array(z.string().min(1)).default([]),
  now: z.string().optional(),
});
export type EvaluateFeatureFlagInput = z.input<typeof EvaluateFeatureFlagInputSchema>;

export const KillFeatureFlagInputSchema = z.object({
  flagKey: z.string().min(1),
  actorAuthUserId: z.string().uuid(),
  reason: z.string().min(1),
  actorLabel: z.string().min(1),
});
export type KillFeatureFlagInput = z.infer<typeof KillFeatureFlagInputSchema>;

export const DebugFeatureFlagInputSchema = z.object({
  flagKey: z.string().min(1),
  tenantId: z.string().uuid().nullable(),
  environment: FeatureFlagEnvironmentSchema,
  cohorts: z.array(z.string().min(1)).default([]),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type DebugFeatureFlagInput = z.input<typeof DebugFeatureFlagInputSchema>;

/** Maps a raw app.feature_flags row (snake_case) to this contract's camelCase shape. */
export function parseFeatureFlag(row: Record<string, unknown>): FeatureFlag {
  return FeatureFlagSchema.parse({
    flagKey: row.flag_key,
    name: row.name,
    description: row.description,
    moduleCode: row.module_code,
    registeredBy: row.registered_by,
    createdAt: row.created_at,
  });
}

/** Maps a raw app.feature_flag_decision row (snake_case) to this contract's camelCase shape. */
export function parseFeatureFlagDecision(row: Record<string, unknown>): FeatureFlagDecision {
  return FeatureFlagDecisionSchema.parse({
    enabled: row.enabled,
    reason: row.reason,
    resolvedScopeLevel: row.resolved_scope_level,
    resolvedVersionId: row.resolved_version_id,
    evaluatedAt: row.evaluated_at,
  });
}
