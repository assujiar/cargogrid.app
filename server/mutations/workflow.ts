/**
 * Workflow engine mutation primitives (PLT-122, CG-S6-PLT-019). Thin, typed wrappers
 * around app.register_workflow_hook / app.publish_workflow_definition /
 * app.start_workflow_instance / app.transition_workflow_instance /
 * app.cancel_workflow_instance
 * (supabase/migrations/20260717140000_create_workflow_engine.sql). All
 * service_role-only (see the migration's own grant comment).
 */

import {
  RegisterWorkflowHookInputSchema,
  PublishWorkflowDefinitionInputSchema,
  StartWorkflowInstanceInputSchema,
  TransitionWorkflowInstanceInputSchema,
  CancelWorkflowInstanceInputSchema,
  ConfigVersionSchema,
  parseWorkflowHook,
  parseWorkflowInstance,
  type RegisterWorkflowHookInput,
  type PublishWorkflowDefinitionInput,
  type StartWorkflowInstanceInput,
  type TransitionWorkflowInstanceInput,
  type CancelWorkflowInstanceInput,
  type WorkflowHook,
  type WorkflowInstance,
  type ConfigVersion,
} from "../contracts/workflow/workflow.ts";
import { parseConfigVersion } from "../contracts/config/config.ts";

export interface WorkflowMutationRpcClient {
  rpc(
    fn:
      | "register_workflow_hook"
      | "publish_workflow_definition"
      | "start_workflow_instance"
      | "transition_workflow_instance"
      | "cancel_workflow_instance",
    args: Record<string, unknown>,
  ): Promise<{ data: unknown; error: { message: string } | null }>;
}

export const WORKFLOW_KNOWN_MUTATION_ERROR_CODES = [
  "insufficient_authority",
  "workflow_missing_states",
  "workflow_invalid_initial_state",
  "workflow_invalid_terminal_state",
  "workflow_invalid_transition_from",
  "workflow_invalid_transition_to",
  "workflow_unknown_guard",
  "workflow_unknown_effect",
  "workflow_unreachable_state",
  "workflow_dead_end_state",
  "workflow_definition_not_published",
  "workflow_instance_not_found",
  "workflow_instance_not_active",
  "stale_workflow_state",
  "invalid_workflow_transition",
  "workflow_guard_rejected",
  "guard_not_implemented",
] as const;
type KnownWorkflowMutationErrorCode = (typeof WORKFLOW_KNOWN_MUTATION_ERROR_CODES)[number];
export type WorkflowMutationErrorCode = KnownWorkflowMutationErrorCode | "mutation_failed" | "invalid_response";

export class WorkflowMutationError extends Error {
  readonly code: WorkflowMutationErrorCode;

  constructor(code: WorkflowMutationErrorCode, message: string) {
    super(message);
    this.name = "WorkflowMutationError";
    this.code = code;
  }
}

function classifyError(message: string): WorkflowMutationErrorCode {
  const prefix = message.split(":")[0]?.trim();
  return (WORKFLOW_KNOWN_MUTATION_ERROR_CODES as readonly string[]).includes(prefix ?? "")
    ? (prefix as KnownWorkflowMutationErrorCode)
    : "mutation_failed";
}

/** Idempotent -- Supreme-Admin-only. */
export async function registerWorkflowHook(client: WorkflowMutationRpcClient, input: RegisterWorkflowHookInput): Promise<WorkflowHook> {
  const parsedInput = RegisterWorkflowHookInputSchema.parse(input);
  const { data, error } = await client.rpc("register_workflow_hook", {
    p_code: parsedInput.code,
    p_hook_type: parsedInput.hookType,
    p_name: parsedInput.name,
    p_description: parsedInput.description,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_registered_by: parsedInput.registeredBy,
  });
  if (error) {
    throw new WorkflowMutationError(classifyError(error.message), error.message);
  }
  if (!data || typeof data !== "object") {
    throw new WorkflowMutationError("invalid_response", "register_workflow_hook returned no row");
  }
  return parseWorkflowHook(data as Record<string, unknown>);
}

/** Runs the structural/reachability/dead-end validation gate, then supersedes the prior published definition (PLT-121's app.publish_config_version() composed underneath). */
export async function publishWorkflowDefinition(client: WorkflowMutationRpcClient, input: PublishWorkflowDefinitionInput): Promise<ConfigVersion> {
  const parsedInput = PublishWorkflowDefinitionInputSchema.parse(input);
  const { data, error } = await client.rpc("publish_workflow_definition", {
    p_version_id: parsedInput.versionId,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_effective_from: parsedInput.effectiveFrom,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new WorkflowMutationError(classifyError(error.message), error.message);
  }
  if (!data || typeof data !== "object") {
    throw new WorkflowMutationError("invalid_response", "publish_workflow_definition returned no row");
  }
  return ConfigVersionSchema.parse(parseConfigVersion(data as Record<string, unknown>));
}

/** Idempotent on (tenantId, idempotencyKey) -- a repeated call with the same key returns the existing instance rather than starting a second one. */
export async function startWorkflowInstance(client: WorkflowMutationRpcClient, input: StartWorkflowInstanceInput): Promise<WorkflowInstance> {
  const parsedInput = StartWorkflowInstanceInputSchema.parse(input);
  const { data, error } = await client.rpc("start_workflow_instance", {
    p_config_version_id: parsedInput.configVersionId,
    p_tenant_id: parsedInput.tenantId,
    p_entity_type: parsedInput.entityType,
    p_entity_id: parsedInput.entityId,
    p_idempotency_key: parsedInput.idempotencyKey,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_started_by: parsedInput.startedBy,
  });
  if (error) {
    throw new WorkflowMutationError(classifyError(error.message), error.message);
  }
  if (!data || typeof data !== "object") {
    throw new WorkflowMutationError("invalid_response", "start_workflow_instance returned no row");
  }
  return parseWorkflowInstance(data as Record<string, unknown>);
}

/** Optimistic concurrency via expectedCurrentState -- rejects a stale transition attempt (stale_workflow_state) rather than silently overwriting. */
export async function transitionWorkflowInstance(client: WorkflowMutationRpcClient, input: TransitionWorkflowInstanceInput): Promise<WorkflowInstance> {
  const parsedInput = TransitionWorkflowInstanceInputSchema.parse(input);
  const { data, error } = await client.rpc("transition_workflow_instance", {
    p_instance_id: parsedInput.instanceId,
    p_expected_current_state: parsedInput.expectedCurrentState,
    p_to_state: parsedInput.toState,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
    p_reason: parsedInput.reason,
  });
  if (error) {
    throw new WorkflowMutationError(classifyError(error.message), error.message);
  }
  if (!data || typeof data !== "object") {
    throw new WorkflowMutationError("invalid_response", "transition_workflow_instance returned no row");
  }
  return parseWorkflowInstance(data as Record<string, unknown>);
}

/** active -> cancelled; no-op-safe only via a prior read -- calling this on an already-terminal instance raises workflow_instance_not_active. */
export async function cancelWorkflowInstance(client: WorkflowMutationRpcClient, input: CancelWorkflowInstanceInput): Promise<WorkflowInstance> {
  const parsedInput = CancelWorkflowInstanceInputSchema.parse(input);
  const { data, error } = await client.rpc("cancel_workflow_instance", {
    p_instance_id: parsedInput.instanceId,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
    p_reason: parsedInput.reason,
  });
  if (error) {
    throw new WorkflowMutationError(classifyError(error.message), error.message);
  }
  if (!data || typeof data !== "object") {
    throw new WorkflowMutationError("invalid_response", "cancel_workflow_instance returned no row");
  }
  return parseWorkflowInstance(data as Record<string, unknown>);
}
