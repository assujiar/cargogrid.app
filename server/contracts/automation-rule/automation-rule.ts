/**
 * Automation Rule Engine contract (IAE-007, Prompt 335). Mirrors
 * supabase/migrations/20260803010000_create_intelligence_automation_rule_engine.sql's
 * app.automation_rules/app.automation_rule_versions/app.automation_rule_executions
 * shape.
 */

import { z } from "zod";

export const AUTOMATION_RULE_STATUSES = ["active", "paused", "archived"] as const;
export const AutomationRuleStatusSchema = z.enum(AUTOMATION_RULE_STATUSES);
export type AutomationRuleStatus = z.infer<typeof AutomationRuleStatusSchema>;

export const AUTOMATION_RULE_VERSION_STATUSES = ["draft", "published", "archived"] as const;
export const AutomationRuleVersionStatusSchema = z.enum(AUTOMATION_RULE_VERSION_STATUSES);
export type AutomationRuleVersionStatus = z.infer<typeof AutomationRuleVersionStatusSchema>;

export const AUTOMATION_RULE_EXECUTION_STATUSES = ["completed", "suppressed", "failed"] as const;
export const AutomationRuleExecutionStatusSchema = z.enum(AUTOMATION_RULE_EXECUTION_STATUSES);
export type AutomationRuleExecutionStatus = z.infer<typeof AutomationRuleExecutionStatusSchema>;

export const AUTOMATION_CONDITION_OPERATORS = ["eq", "neq", "gt", "gte", "lt", "lte", "contains"] as const;
export const AutomationConditionOperatorSchema = z.enum(AUTOMATION_CONDITION_OPERATORS);
export type AutomationConditionOperator = z.infer<typeof AutomationConditionOperatorSchema>;

export const AutomationConditionSchema = z.object({
  field: z.string().min(1),
  operator: AutomationConditionOperatorSchema,
  value: z.union([z.string(), z.number(), z.boolean(), z.null()]),
});
export type AutomationCondition = z.infer<typeof AutomationConditionSchema>;
export const AutomationConditionsSchema = z.array(AutomationConditionSchema).max(50);

export const AUTOMATION_ACTION_TYPES = ["notify", "transition_workflow", "enqueue_job"] as const;
export const AutomationActionTypeSchema = z.enum(AUTOMATION_ACTION_TYPES);
export type AutomationActionType = z.infer<typeof AutomationActionTypeSchema>;

/** A loosely-typed action -- the engine's own app.validate_automation_rule_definition is the real, authoritative structural gate; this schema only enforces action_type is one of the 3 supported values plus a generic string-keyed param bag. */
export const AutomationActionSchema = z.object({
  action_type: AutomationActionTypeSchema,
  notification_type_code: z.string().optional(),
  channel: z.string().optional(),
  locale: z.string().optional(),
  recipient_field: z.string().optional(),
  instance_id_field: z.string().optional(),
  to_state: z.string().optional(),
  reason: z.string().optional(),
  job_type: z.string().optional(),
  payload: z.record(z.string(), z.unknown()).optional(),
});
export type AutomationAction = z.infer<typeof AutomationActionSchema>;
export const AutomationActionsSchema = z.array(AutomationActionSchema).max(10);

export const AutomationRuleSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  name: z.string(),
  description: z.string().nullable(),
  status: AutomationRuleStatusSchema,
  currentVersionId: z.string().uuid().nullable(),
  cooldownSeconds: z.number().int().nonnegative(),
  maxFiresPerWindow: z.number().int().positive(),
  windowSeconds: z.number().int().positive(),
  lastFiredAt: z.string().nullable(),
  fireCountInWindow: z.number().int().nonnegative(),
  recordVersion: z.number().int().positive(),
  createdAt: z.string(),
  updatedAt: z.string(),
});
export type AutomationRule = z.infer<typeof AutomationRuleSchema>;

export function parseAutomationRule(row: Record<string, unknown>): AutomationRule {
  return AutomationRuleSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    name: row.name,
    description: row.description,
    status: row.status,
    currentVersionId: row.current_version_id,
    cooldownSeconds: row.cooldown_seconds,
    maxFiresPerWindow: row.max_fires_per_window,
    windowSeconds: row.window_seconds,
    lastFiredAt: row.last_fired_at,
    fireCountInWindow: row.fire_count_in_window,
    recordVersion: row.record_version,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  });
}

export const AutomationRuleVersionSchema = z.object({
  id: z.string().uuid(),
  automationRuleId: z.string().uuid(),
  versionNumber: z.number().int().positive(),
  status: AutomationRuleVersionStatusSchema,
  triggerEventType: z.string().nullable(),
  conditions: AutomationConditionsSchema,
  actions: AutomationActionsSchema,
  createdAt: z.string(),
  publishedAt: z.string().nullable(),
});
export type AutomationRuleVersion = z.infer<typeof AutomationRuleVersionSchema>;

export function parseAutomationRuleVersion(row: Record<string, unknown>): AutomationRuleVersion {
  return AutomationRuleVersionSchema.parse({
    id: row.id,
    automationRuleId: row.automation_rule_id,
    versionNumber: row.version_number,
    status: row.status,
    triggerEventType: row.trigger_event_type,
    conditions: row.conditions ?? [],
    actions: row.actions ?? [],
    createdAt: row.created_at,
    publishedAt: row.published_at,
  });
}

export const AutomationRuleExecutionSchema = z.object({
  id: z.string().uuid(),
  automationRuleId: z.string().uuid(),
  automationRuleVersionId: z.string().uuid(),
  triggerEventType: z.string(),
  sourceEventId: z.string().uuid().nullable(),
  eventPayload: z.record(z.string(), z.unknown()),
  status: AutomationRuleExecutionStatusSchema,
  suppressedReason: z.string().nullable(),
  actionsTaken: z.array(z.record(z.string(), z.unknown())),
  executedAt: z.string(),
});
export type AutomationRuleExecution = z.infer<typeof AutomationRuleExecutionSchema>;

export function parseAutomationRuleExecution(row: Record<string, unknown>): AutomationRuleExecution {
  return AutomationRuleExecutionSchema.parse({
    id: row.id,
    automationRuleId: row.automation_rule_id,
    automationRuleVersionId: row.automation_rule_version_id,
    triggerEventType: row.trigger_event_type,
    sourceEventId: row.source_event_id,
    eventPayload: row.event_payload ?? {},
    status: row.status,
    suppressedReason: row.suppressed_reason,
    actionsTaken: row.actions_taken ?? [],
    executedAt: row.executed_at,
  });
}

export const CreateAutomationRuleInputSchema = z.object({
  tenantId: z.string().uuid(),
  name: z.string().min(1),
  description: z.string().nullable().default(null),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type CreateAutomationRuleInput = z.input<typeof CreateAutomationRuleInputSchema>;

export const SetAutomationRuleDefinitionInputSchema = z.object({
  ruleId: z.string().uuid(),
  triggerEventType: z.string().min(1),
  conditions: AutomationConditionsSchema.default([]),
  actions: AutomationActionsSchema,
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type SetAutomationRuleDefinitionInput = z.input<typeof SetAutomationRuleDefinitionInputSchema>;

export const DryRunAutomationRuleInputSchema = z.object({
  ruleId: z.string().uuid(),
  sampleEventPayload: z.record(z.string(), z.unknown()).default({}),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type DryRunAutomationRuleInput = z.input<typeof DryRunAutomationRuleInputSchema>;

export const DryRunAutomationRuleResultSchema = z.object({
  matched: z.boolean(),
  triggerEventType: z.string().nullable(),
  wouldFireActions: AutomationActionsSchema,
});
export type DryRunAutomationRuleResult = z.infer<typeof DryRunAutomationRuleResultSchema>;

export function parseDryRunAutomationRuleResult(row: Record<string, unknown>): DryRunAutomationRuleResult {
  return DryRunAutomationRuleResultSchema.parse({
    matched: row.matched,
    triggerEventType: row.trigger_event_type,
    wouldFireActions: row.would_fire_actions ?? [],
  });
}

export const RequestAutomationRulePublishApprovalInputSchema = z.object({
  ruleId: z.string().uuid(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type RequestAutomationRulePublishApprovalInput = z.input<typeof RequestAutomationRulePublishApprovalInputSchema>;

export const DecideAutomationRulePublishApprovalInputSchema = z.object({
  requestStepId: z.string().uuid(),
  decision: z.enum(["approved", "rejected"]),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
  reason: z.string().nullable().default(null),
});
export type DecideAutomationRulePublishApprovalInput = z.input<typeof DecideAutomationRulePublishApprovalInputSchema>;

export const PublishAutomationRuleVersionInputSchema = z.object({
  ruleId: z.string().uuid(),
  approvalRequestId: z.string().uuid(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type PublishAutomationRuleVersionInput = z.input<typeof PublishAutomationRuleVersionInputSchema>;

export const SetAutomationRuleStatusInputSchema = z.object({
  ruleId: z.string().uuid(),
  status: AutomationRuleStatusSchema,
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type SetAutomationRuleStatusInput = z.input<typeof SetAutomationRuleStatusInputSchema>;
