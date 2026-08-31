import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  parseTenantScheduledTask,
  ConfigureTenantScheduledTaskInputSchema,
  SetScheduledTaskDelegationInputSchema,
} from "./task-scheduler.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "323e4567-e89b-12d3-a456-426614174000";
const SCHEDULE_ID = "423e4567-e89b-12d3-a456-426614174000";

describe("parseTenantScheduledTask", () => {
  test("maps a configured schedule's snake_case columns to camelCase", () => {
    const task = parseTenantScheduledTask({
      id: SCHEDULE_ID,
      task_code: "loyalty_expiry_sweep",
      display_name: "Loyalty expiry sweep",
      description: "Expires due loyalty point lots and benefit entitlements for the tenant.",
      tenant_admin_configurable: true,
      configurable_by_actor: true,
      enabled: true,
      interval_minutes: 1440,
      min_interval_minutes: 60,
      default_interval_minutes: 1440,
      required_params: [],
      params: {},
      authorized_by_auth_user_id: ACTOR_ID,
      authorized_at: "2026-08-31T09:00:00Z",
      next_run_at: "2026-09-01T09:00:00Z",
      last_run_at: "2026-08-31T09:00:00Z",
      last_run_status: "succeeded",
      last_run_detail: null,
      consecutive_authority_failures: 0,
      disabled_reason: null,
      record_version: 2,
    });

    assert.equal(task.taskCode, "loyalty_expiry_sweep");
    assert.equal(task.authorizedByAuthUserId, ACTOR_ID);
    assert.equal(task.lastRunStatus, "succeeded");
    assert.equal(task.intervalMinutes, 1440);
  });

  /**
   * The read returns every AVAILABLE task, so most rows on a fresh tenant have no schedule at
   * all. Those must land as a disabled row with a null id rather than throwing or, worse,
   * reading as enabled — a console that shows automation as "on" when nothing is scheduled would
   * be actively misleading.
   */
  test("an unconfigured catalogue task parses as a disabled row with no identity or schedule", () => {
    const task = parseTenantScheduledTask({
      id: null,
      task_code: "incident_escalation_sweep",
      display_name: "Incident escalation sweep",
      description: "Escalates monitoring incidents whose escalation window has elapsed.",
      tenant_admin_configurable: false,
      configurable_by_actor: false,
      enabled: null,
      interval_minutes: null,
      min_interval_minutes: 5,
      default_interval_minutes: 15,
      required_params: null,
      params: null,
      authorized_by_auth_user_id: null,
      authorized_at: null,
      next_run_at: null,
      last_run_at: null,
      last_run_status: null,
      last_run_detail: null,
      consecutive_authority_failures: null,
      disabled_reason: null,
      record_version: null,
    });

    assert.equal(task.id, null);
    assert.equal(task.enabled, false);
    assert.equal(task.intervalMinutes, null);
    assert.equal(task.authorizedByAuthUserId, null);
    assert.deepEqual(task.requiredParams, []);
    assert.deepEqual(task.params, {});
    assert.equal(task.consecutiveAuthorityFailures, 0);
  });

  test("carries the auto-disabled state through, since that is the case an admin must act on", () => {
    const task = parseTenantScheduledTask({
      id: SCHEDULE_ID,
      task_code: "leave_accrual_batch",
      display_name: "Leave accrual",
      description: "Accrues leave balances for one leave type across the tenant.",
      tenant_admin_configurable: true,
      configurable_by_actor: true,
      enabled: false,
      interval_minutes: 1440,
      min_interval_minutes: 1440,
      default_interval_minutes: 1440,
      required_params: ["leave_type_id"],
      params: { leave_type_id: TENANT_ID },
      authorized_by_auth_user_id: ACTOR_ID,
      authorized_at: "2026-08-01T09:00:00Z",
      next_run_at: "2026-09-01T09:00:00Z",
      last_run_at: "2026-08-31T09:00:00Z",
      last_run_status: "unauthorized",
      last_run_detail: "insufficient_authority: identity lacks HRS:Edit",
      consecutive_authority_failures: 3,
      disabled_reason: "auto-disabled: the authorizing identity has lacked the required authority for 3 consecutive runs",
      record_version: 5,
    });

    assert.equal(task.enabled, false);
    assert.equal(task.lastRunStatus, "unauthorized");
    assert.equal(task.consecutiveAuthorityFailures, 3);
    assert.match(task.disabledReason ?? "", /^auto-disabled/);
  });

  test("rejects an unknown run status rather than rendering it as a badge", () => {
    assert.throws(() =>
      parseTenantScheduledTask({
        id: SCHEDULE_ID,
        task_code: "loyalty_expiry_sweep",
        display_name: "Loyalty expiry sweep",
        description: "…",
        tenant_admin_configurable: true,
        configurable_by_actor: true,
        enabled: true,
        interval_minutes: 1440,
        min_interval_minutes: 60,
        default_interval_minutes: 1440,
        required_params: [],
        params: {},
        authorized_by_auth_user_id: ACTOR_ID,
        authorized_at: null,
        next_run_at: null,
        last_run_at: null,
        last_run_status: "kind-of-worked",
        last_run_detail: null,
        consecutive_authority_failures: 0,
        disabled_reason: null,
        record_version: 1,
      }),
    );
  });
});

describe("ConfigureTenantScheduledTaskInputSchema", () => {
  test("defaults intervalMinutes to null so the catalogue default applies, and params to empty", () => {
    const parsed = ConfigureTenantScheduledTaskInputSchema.parse({
      tenantId: TENANT_ID,
      taskCode: "loyalty_expiry_sweep",
      enabled: true,
      actorAuthUserId: ACTOR_ID,
      actorLabel: "admin",
    });
    assert.equal(parsed.intervalMinutes, null);
    assert.deepEqual(parsed.params, {});
  });

  test("rejects a zero or negative interval before it reaches the database", () => {
    for (const intervalMinutes of [0, -5]) {
      assert.throws(() =>
        ConfigureTenantScheduledTaskInputSchema.parse({
          tenantId: TENANT_ID,
          taskCode: "loyalty_expiry_sweep",
          enabled: true,
          intervalMinutes,
          actorAuthUserId: ACTOR_ID,
          actorLabel: "admin",
        }),
      );
    }
  });

  test("rejects an empty task code", () => {
    assert.throws(() =>
      ConfigureTenantScheduledTaskInputSchema.parse({
        tenantId: TENANT_ID,
        taskCode: "",
        enabled: true,
        actorAuthUserId: ACTOR_ID,
        actorLabel: "admin",
      }),
    );
  });
});

describe("SetScheduledTaskDelegationInputSchema", () => {
  test("requires a task code, an explicit boolean, and a real actor", () => {
    const parsed = SetScheduledTaskDelegationInputSchema.parse({
      taskCode: "loyalty_expiry_sweep",
      tenantAdminConfigurable: false,
      actorAuthUserId: ACTOR_ID,
      actorLabel: "supreme",
    });
    assert.equal(parsed.tenantAdminConfigurable, false);

    assert.throws(() =>
      SetScheduledTaskDelegationInputSchema.parse({
        taskCode: "loyalty_expiry_sweep",
        tenantAdminConfigurable: "yes",
        actorAuthUserId: ACTOR_ID,
        actorLabel: "supreme",
      }),
    );
  });
});
