/**
 * Workflow engine contract (PLT-122, CG-S6-PLT-019). Mirrors
 * supabase/migrations/20260717140000_create_workflow_engine.sql's
 * app.workflow_hooks/app.workflow_instances/app.workflow_transition_history shape and
 * the app.register_workflow_hook / app.publish_workflow_definition /
 * app.start_workflow_instance / app.transition_workflow_instance /
 * app.cancel_workflow_instance / app.get_workflow_instance_history RPCs.
 *
 * A workflow *definition* is not modeled here as its own row type -- it is PLT-121's own
 * ConfigVersion/config_items (config_type_code='workflow'), reused directly (this
 * migration's own header). `publishWorkflowDefinition` therefore still returns a
 * `ConfigVersion` (server/contracts/config/config.ts), not a bespoke type.
 */

import { z } from "zod";
import { ConfigVersionSchema, type ConfigVersion } from "../config/config.ts";

export const WORKFLOW_HOOK_TYPES = ["guard", "effect"] as const;
export const WorkflowHookTypeSchema = z.enum(WORKFLOW_HOOK_TYPES);
export type WorkflowHookType = z.infer<typeof WorkflowHookTypeSchema>;

export const WORKFLOW_INSTANCE_STATUSES = ["active", "completed", "cancelled", "failed"] as const;
export const WorkflowInstanceStatusSchema = z.enum(WORKFLOW_INSTANCE_STATUSES);
export type WorkflowInstanceStatus = z.infer<typeof WorkflowInstanceStatusSchema>;

export const WORKFLOW_TRANSITION_EVENT_TYPES = ["start", "transition", "cancel", "fail"] as const;
export const WorkflowTransitionEventTypeSchema = z.enum(WORKFLOW_TRANSITION_EVENT_TYPES);
export type WorkflowTransitionEventType = z.infer<typeof WorkflowTransitionEventTypeSchema>;

export const WorkflowHookSchema = z.object({
  code: z.string(),
  hookType: WorkflowHookTypeSchema,
  name: z.string(),
  description: z.string().nullable(),
  registeredBy: z.string().nullable(),
  createdAt: z.string(),
});
export type WorkflowHook = z.infer<typeof WorkflowHookSchema>;

export const WorkflowInstanceSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  configVersionId: z.string().uuid(),
  entityType: z.string(),
  entityId: z.string().uuid().nullable(),
  currentState: z.string(),
  status: WorkflowInstanceStatusSchema,
  idempotencyKey: z.string(),
  startedBy: z.string().nullable(),
  startedAt: z.string(),
  endedAt: z.string().nullable(),
  endedReason: z.string().nullable(),
  recordVersion: z.number().int().positive(),
  createdAt: z.string(),
  updatedAt: z.string(),
});
export type WorkflowInstance = z.infer<typeof WorkflowInstanceSchema>;

export const WorkflowTransitionHistoryEntrySchema = z.object({
  id: z.string().uuid(),
  instanceId: z.string().uuid(),
  eventType: WorkflowTransitionEventTypeSchema,
  fromState: z.string().nullable(),
  toState: z.string().nullable(),
  actorAuthUserId: z.string().uuid().nullable(),
  actorLabel: z.string().nullable(),
  reason: z.string().nullable(),
  occurredAt: z.string(),
});
export type WorkflowTransitionHistoryEntry = z.infer<typeof WorkflowTransitionHistoryEntrySchema>;

export const RegisterWorkflowHookInputSchema = z.object({
  code: z.string().min(1),
  hookType: WorkflowHookTypeSchema,
  name: z.string().min(1),
  description: z.string().nullable().default(null),
  actorAuthUserId: z.string().uuid(),
  registeredBy: z.string().min(1),
});
export type RegisterWorkflowHookInput = z.input<typeof RegisterWorkflowHookInputSchema>;

/** versionId must reference a draft config_version with config_type_code='workflow' -- app.publish_workflow_definition() runs the structural/reachability/dead-end gate before ever calling app.publish_config_version(). */
export const PublishWorkflowDefinitionInputSchema = z.object({
  versionId: z.string().uuid(),
  actorAuthUserId: z.string().uuid(),
  effectiveFrom: z.string().nullable().default(null),
  actorLabel: z.string().min(1),
});
export type PublishWorkflowDefinitionInput = z.input<typeof PublishWorkflowDefinitionInputSchema>;

export const StartWorkflowInstanceInputSchema = z.object({
  configVersionId: z.string().uuid(),
  tenantId: z.string().uuid(),
  entityType: z.string().min(1).default("generic"),
  entityId: z.string().uuid().nullable().default(null),
  idempotencyKey: z.string().min(1),
  actorAuthUserId: z.string().uuid(),
  startedBy: z.string().min(1),
});
export type StartWorkflowInstanceInput = z.input<typeof StartWorkflowInstanceInputSchema>;

export const TransitionWorkflowInstanceInputSchema = z.object({
  instanceId: z.string().uuid(),
  expectedCurrentState: z.string().min(1),
  toState: z.string().min(1),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
  reason: z.string().nullable().default(null),
});
export type TransitionWorkflowInstanceInput = z.input<typeof TransitionWorkflowInstanceInputSchema>;

export const CancelWorkflowInstanceInputSchema = z.object({
  instanceId: z.string().uuid(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
  reason: z.string().nullable().default(null),
});
export type CancelWorkflowInstanceInput = z.input<typeof CancelWorkflowInstanceInputSchema>;

export const GetWorkflowInstanceHistoryInputSchema = z.object({
  instanceId: z.string().uuid(),
  actorAuthUserId: z.string().uuid(),
});
export type GetWorkflowInstanceHistoryInput = z.input<typeof GetWorkflowInstanceHistoryInputSchema>;

/** Re-exported so callers of publishWorkflowDefinition don't need a separate import from ../config/config.ts. */
export { ConfigVersionSchema };
export type { ConfigVersion };

/** Maps a raw app.workflow_hooks row (snake_case) to this contract's camelCase shape. */
export function parseWorkflowHook(row: Record<string, unknown>): WorkflowHook {
  return WorkflowHookSchema.parse({
    code: row.code,
    hookType: row.hook_type,
    name: row.name,
    description: row.description,
    registeredBy: row.registered_by,
    createdAt: row.created_at,
  });
}

/** Maps a raw app.workflow_instances row (snake_case) to this contract's camelCase shape. */
export function parseWorkflowInstance(row: Record<string, unknown>): WorkflowInstance {
  return WorkflowInstanceSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    configVersionId: row.config_version_id,
    entityType: row.entity_type,
    entityId: row.entity_id,
    currentState: row.current_state,
    status: row.status,
    idempotencyKey: row.idempotency_key,
    startedBy: row.started_by,
    startedAt: row.started_at,
    endedAt: row.ended_at,
    endedReason: row.ended_reason,
    recordVersion: row.record_version,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  });
}

/** Maps a raw app.workflow_transition_history row (snake_case) to this contract's camelCase shape. */
export function parseWorkflowTransitionHistoryEntry(row: Record<string, unknown>): WorkflowTransitionHistoryEntry {
  return WorkflowTransitionHistoryEntrySchema.parse({
    id: row.id,
    instanceId: row.instance_id,
    eventType: row.event_type,
    fromState: row.from_state,
    toState: row.to_state,
    actorAuthUserId: row.actor_auth_user_id,
    actorLabel: row.actor_label,
    reason: row.reason,
    occurredAt: row.occurred_at,
  });
}
