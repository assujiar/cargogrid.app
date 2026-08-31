/**
 * Task scheduler contracts (`20260831090000_create_tenant_configurable_task_scheduler.sql`).
 *
 * The shape worth understanding before reading the fields: a scheduled sweep runs as the real
 * person who authorized it, not as a system account. So every row carries an authorizing
 * identity, and `configurableByActor` is computed per row for the *calling* admin — the same
 * admin may change some rows and not others, depending on which task types Supreme Admin has
 * delegated.
 */

import { z } from "zod";

export const ScheduledTaskRunStatusSchema = z.enum(["succeeded", "failed", "unauthorized"]);
export type ScheduledTaskRunStatus = z.infer<typeof ScheduledTaskRunStatusSchema>;

export const TenantScheduledTaskSchema = z.object({
  /** Null when this tenant has never configured this catalogue task — the row is the menu entry, not a schedule. */
  id: z.string().uuid().nullable(),
  taskCode: z.string(),
  displayName: z.string(),
  description: z.string(),
  /** Supreme Admin's delegation switch for this task type, tenant-independent. */
  tenantAdminConfigurable: z.boolean(),
  /** Whether THIS caller may change THIS row. Lets the UI disable controls rather than let a save fail. */
  configurableByActor: z.boolean(),
  enabled: z.boolean(),
  intervalMinutes: z.number().int().positive().nullable(),
  minIntervalMinutes: z.number().int().positive(),
  defaultIntervalMinutes: z.number().int().positive(),
  requiredParams: z.array(z.string()),
  params: z.record(z.string(), z.unknown()),
  authorizedByAuthUserId: z.string().uuid().nullable(),
  authorizedAt: z.string().nullable(),
  nextRunAt: z.string().nullable(),
  lastRunAt: z.string().nullable(),
  lastRunStatus: ScheduledTaskRunStatusSchema.nullable(),
  lastRunDetail: z.string().nullable(),
  consecutiveAuthorityFailures: z.number().int().nonnegative(),
  disabledReason: z.string().nullable(),
  recordVersion: z.number().int().positive().nullable(),
});
export type TenantScheduledTask = z.infer<typeof TenantScheduledTaskSchema>;

export function parseTenantScheduledTask(row: Record<string, unknown>): TenantScheduledTask {
  return TenantScheduledTaskSchema.parse({
    id: row.id ?? null,
    taskCode: row.task_code,
    displayName: row.display_name,
    description: row.description,
    tenantAdminConfigurable: row.tenant_admin_configurable,
    configurableByActor: row.configurable_by_actor,
    enabled: row.enabled ?? false,
    intervalMinutes: row.interval_minutes ?? null,
    minIntervalMinutes: row.min_interval_minutes,
    defaultIntervalMinutes: row.default_interval_minutes,
    requiredParams: row.required_params ?? [],
    params: row.params ?? {},
    authorizedByAuthUserId: row.authorized_by_auth_user_id ?? null,
    authorizedAt: row.authorized_at ?? null,
    nextRunAt: row.next_run_at ?? null,
    lastRunAt: row.last_run_at ?? null,
    lastRunStatus: row.last_run_status ?? null,
    lastRunDetail: row.last_run_detail ?? null,
    consecutiveAuthorityFailures: row.consecutive_authority_failures ?? 0,
    disabledReason: row.disabled_reason ?? null,
    recordVersion: row.record_version ?? null,
  });
}

export const ListTenantScheduledTasksInputSchema = z.object({
  tenantId: z.string().uuid(),
  actorAuthUserId: z.string().uuid(),
});
export type ListTenantScheduledTasksInput = z.input<typeof ListTenantScheduledTasksInputSchema>;

export const ConfigureTenantScheduledTaskInputSchema = z.object({
  tenantId: z.string().uuid(),
  taskCode: z.string().min(1),
  enabled: z.boolean(),
  /** Null means "use the catalogue default"; the RPC applies the floor either way. */
  intervalMinutes: z.number().int().positive().nullable().default(null),
  params: z.record(z.string(), z.unknown()).default({}),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type ConfigureTenantScheduledTaskInput = z.input<typeof ConfigureTenantScheduledTaskInputSchema>;

export const SetScheduledTaskDelegationInputSchema = z.object({
  taskCode: z.string().min(1),
  tenantAdminConfigurable: z.boolean(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type SetScheduledTaskDelegationInput = z.input<typeof SetScheduledTaskDelegationInputSchema>;
