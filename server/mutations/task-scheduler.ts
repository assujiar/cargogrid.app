/**
 * Task scheduler mutations (20260831090000).
 *
 * Neither function re-checks authority here, and that is deliberate rather than an omission:
 * `app.configure_tenant_scheduled_task` and `app.set_scheduled_task_delegation` each perform
 * their own check against the live catalogue and the caller's live principal memberships. A
 * second copy of the delegation rule in TypeScript would be a copy that drifts.
 */

import {
  ConfigureTenantScheduledTaskInputSchema,
  SetScheduledTaskDelegationInputSchema,
  parseTenantScheduledTask,
  type ConfigureTenantScheduledTaskInput,
  type SetScheduledTaskDelegationInput,
} from "../contracts/task-scheduler/task-scheduler.ts";

export interface TaskSchedulerMutationRpcClient {
  rpc(
    fn: "configure_tenant_scheduled_task" | "set_scheduled_task_delegation",
    args: Record<string, unknown>,
  ): Promise<{ data: unknown; error: { message: string } | null }>;
}

export class TaskSchedulerMutationError extends Error {
  readonly code: string;
  constructor(code: string, message: string) {
    super(message);
    this.name = "TaskSchedulerMutationError";
    this.code = code;
  }
}

function toMutationError(message: string): TaskSchedulerMutationError {
  const code = message.split(":", 1)[0]?.trim() ?? "unknown_error";
  return new TaskSchedulerMutationError(code, message);
}

/** Creates or updates one tenant's schedule for one catalogue task, and re-stamps it as authorized by this actor. */
export async function configureTenantScheduledTask(
  client: TaskSchedulerMutationRpcClient,
  input: ConfigureTenantScheduledTaskInput,
) {
  const parsedInput = ConfigureTenantScheduledTaskInputSchema.parse(input);
  const { data, error } = await client.rpc("configure_tenant_scheduled_task", {
    p_tenant_id: parsedInput.tenantId,
    p_task_code: parsedInput.taskCode,
    p_enabled: parsedInput.enabled,
    p_interval_minutes: parsedInput.intervalMinutes,
    p_params: parsedInput.params,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw toMutationError(error.message);
  }
  const row = Array.isArray(data) ? (data[0] as Record<string, unknown> | undefined) : (data as Record<string, unknown> | null);
  if (!row) {
    throw new TaskSchedulerMutationError("empty_result", "configure_tenant_scheduled_task returned no row");
  }
  // The RPC returns the app.tenant_scheduled_tasks row, which carries no catalogue columns; the
  // console re-reads the list afterwards rather than reconstructing a half-populated view here.
  return row;
}

/** Supreme-Admin-only: flips whether a tenant's own admin may configure this task type. */
export async function setScheduledTaskDelegation(
  client: TaskSchedulerMutationRpcClient,
  input: SetScheduledTaskDelegationInput,
) {
  const parsedInput = SetScheduledTaskDelegationInputSchema.parse(input);
  const { data, error } = await client.rpc("set_scheduled_task_delegation", {
    p_task_code: parsedInput.taskCode,
    p_tenant_admin_configurable: parsedInput.tenantAdminConfigurable,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw toMutationError(error.message);
  }
  const row = Array.isArray(data) ? (data[0] as Record<string, unknown> | undefined) : (data as Record<string, unknown> | null);
  if (!row) {
    throw new TaskSchedulerMutationError("empty_result", "set_scheduled_task_delegation returned no row");
  }
  return row;
}

export { parseTenantScheduledTask };
