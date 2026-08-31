/**
 * Task scheduler read queries. A thin, typed wrapper around
 * `app.list_tenant_scheduled_tasks` (20260831090000), which is authority-gated to
 * Supreme Admin or the tenant's own active tenant_admin.
 */

import {
  ListTenantScheduledTasksInputSchema,
  parseTenantScheduledTask,
  type ListTenantScheduledTasksInput,
  type TenantScheduledTask,
} from "../contracts/task-scheduler/task-scheduler.ts";

export interface TaskSchedulerQueryRpcClient {
  rpc(fn: "list_tenant_scheduled_tasks", args: Record<string, unknown>): Promise<{ data: unknown; error: { message: string } | null }>;
}

export class TaskSchedulerQueryError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "TaskSchedulerQueryError";
  }
}

/**
 * Returns every ACTIVE catalogue task, configured or not — an unconfigured task comes back as a
 * disabled row rather than being absent, so the console shows what automation is available
 * instead of only what is already switched on.
 */
export async function listTenantScheduledTasks(
  client: TaskSchedulerQueryRpcClient,
  input: ListTenantScheduledTasksInput,
): Promise<TenantScheduledTask[]> {
  const parsedInput = ListTenantScheduledTasksInputSchema.parse(input);
  const { data, error } = await client.rpc("list_tenant_scheduled_tasks", {
    p_tenant_id: parsedInput.tenantId,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
  });
  if (error) {
    throw new TaskSchedulerQueryError(error.message);
  }
  return ((data as Record<string, unknown>[] | null) ?? []).map(parseTenantScheduledTask);
}
