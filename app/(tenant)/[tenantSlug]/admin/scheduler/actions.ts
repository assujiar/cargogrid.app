"use server";

import { revalidatePath } from "next/cache";

import { resolveTenantAdminAccessForRequest } from "../../../../../lib/portal/resolve-tenant-admin-access.server.ts";
import { createSupabaseServerClient } from "../../../../../lib/supabase/server.ts";
import {
  configureTenantScheduledTask,
  setScheduledTaskDelegation,
  TaskSchedulerMutationError,
  type TaskSchedulerMutationRpcClient,
} from "../../../../../server/mutations/task-scheduler.ts";

export interface SchedulerFormState {
  readonly error: string | null;
  readonly saved: boolean;
}

export const SCHEDULER_INITIAL_STATE: SchedulerFormState = { error: null, saved: false };
const NO_ACCESS: SchedulerFormState = { error: "You do not have access to this organisation's scheduler.", saved: false };

/**
 * The Supabase client is passed with the CALLER's session, not the service role, on purpose.
 * Both RPCs assert `app.assert_actor_is_session_identity` and then make their own authority
 * decision; running them as service_role would null out `auth.uid()` and quietly turn a
 * genuine authority check into a formality.
 */
function toMutationClient(client: Awaited<ReturnType<typeof createSupabaseServerClient>>): TaskSchedulerMutationRpcClient {
  return client as unknown as TaskSchedulerMutationRpcClient;
}

function messageFor(error: TaskSchedulerMutationError): string {
  switch (error.code) {
    case "insufficient_authority":
      return "You are not allowed to change this task. A Supreme Admin controls which tasks an organisation admin may configure.";
    case "scheduled_task_interval_too_short":
      return error.message.replace(/^scheduled_task_interval_too_short:\s*/, "");
    case "scheduled_task_missing_param":
      return error.message.replace(/^scheduled_task_missing_param:\s*/, "");
    case "scheduled_task_not_available":
      return "That task is no longer offered by the platform.";
    default:
      return error.message;
  }
}

export async function configureScheduledTaskAction(
  tenantSlug: string,
  _prevState: SchedulerFormState,
  formData: FormData,
): Promise<SchedulerFormState> {
  const access = await resolveTenantAdminAccessForRequest(tenantSlug);
  if (access.status !== "allowed") return NO_ACCESS;

  const taskCode = String(formData.get("taskCode") ?? "");
  const enabled = formData.get("enabled") === "on";
  const rawInterval = String(formData.get("intervalMinutes") ?? "").trim();
  const intervalMinutes = rawInterval === "" ? null : Number(rawInterval);
  if (intervalMinutes !== null && (!Number.isInteger(intervalMinutes) || intervalMinutes <= 0)) {
    return { error: "How often it runs must be a whole number of minutes.", saved: false };
  }

  // Only the parameters this task actually declares are forwarded. A hidden field naming some
  // other key would otherwise be stored verbatim on the schedule row.
  const params: Record<string, unknown> = {};
  for (const key of String(formData.get("requiredParams") ?? "").split(",").map((k) => k.trim()).filter(Boolean)) {
    const value = String(formData.get(`param_${key}`) ?? "").trim();
    if (value === "") {
      return { error: `This task needs a value for "${key}" before it can be scheduled.`, saved: false };
    }
    params[key] = key.endsWith("_days") || key.endsWith("_minutes") ? Number(value) : value;
  }

  try {
    await configureTenantScheduledTask(toMutationClient(await createSupabaseServerClient()), {
      tenantId: access.tenant.id,
      taskCode,
      enabled,
      intervalMinutes,
      params,
      actorAuthUserId: access.authUserId,
      actorLabel: access.authUserId,
    });
  } catch (error) {
    if (error instanceof TaskSchedulerMutationError) return { error: messageFor(error), saved: false };
    throw error;
  }

  revalidatePath(`/${tenantSlug}/admin/scheduler`);
  return { error: null, saved: true };
}

/** Supreme-Admin-only. The RPC enforces that; this action never pre-judges it. */
export async function setScheduledTaskDelegationAction(
  tenantSlug: string,
  _prevState: SchedulerFormState,
  formData: FormData,
): Promise<SchedulerFormState> {
  const access = await resolveTenantAdminAccessForRequest(tenantSlug);
  if (access.status !== "allowed") return NO_ACCESS;

  try {
    await setScheduledTaskDelegation(toMutationClient(await createSupabaseServerClient()), {
      taskCode: String(formData.get("taskCode") ?? ""),
      tenantAdminConfigurable: formData.get("tenantAdminConfigurable") === "on",
      actorAuthUserId: access.authUserId,
      actorLabel: access.authUserId,
    });
  } catch (error) {
    if (error instanceof TaskSchedulerMutationError) {
      return {
        error:
          error.code === "insufficient_authority"
            ? "Only a Supreme Admin can change which tasks an organisation admin is allowed to configure."
            : messageFor(error),
        saved: false,
      };
    }
    throw error;
  }

  revalidatePath(`/${tenantSlug}/admin/scheduler`);
  return { error: null, saved: true };
}
