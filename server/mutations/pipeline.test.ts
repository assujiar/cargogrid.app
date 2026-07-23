import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  createSalesPlan,
  publishSalesPlan,
  createSalesTarget,
  captureForecastSnapshot,
  recordPipelineOutcome,
  PipelineMutationError,
  type PipelineMutationRpcClient,
} from "./pipeline.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const PLAN_ID = "323e4567-e89b-12d3-a456-426614174000";
const TARGET_ID = "423e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "523e4567-e89b-12d3-a456-426614174000";
const REASON_ID = "623e4567-e89b-12d3-a456-426614174000";
const PROSPECT_ID = "723e4567-e89b-12d3-a456-426614174000";

const VALID_PLAN_ROW = {
  id: PLAN_ID,
  tenant_id: TENANT_ID,
  org_unit_id: null,
  name: "Q3 Plan",
  period_start: "2026-07-01",
  period_end: "2026-09-30",
  status: "draft",
  supersedes_plan_id: null,
  owner_user_id: null,
  record_version: 1,
  created_by: "tester",
  created_at: "2026-07-23T00:00:00.000Z",
  updated_at: "2026-07-23T00:00:00.000Z",
};

describe("createSalesPlan", () => {
  test("calls create_sales_plan with the exact snake_case params", async () => {
    const calls: { fn: string; args: Record<string, unknown> }[] = [];
    const client = {
      async rpc(fn: string, args: Record<string, unknown>) {
        calls.push({ fn, args });
        return { data: VALID_PLAN_ROW, error: null };
      },
    } as unknown as PipelineMutationRpcClient;

    const plan = await createSalesPlan(client, {
      tenantId: TENANT_ID,
      name: "Q3 Plan",
      periodStart: "2026-07-01",
      periodEnd: "2026-09-30",
      actorAuthUserId: ACTOR_ID,
      createdBy: "tester",
    });

    assert.equal(calls[0]?.fn, "create_sales_plan");
    assert.deepEqual(calls[0]?.args, {
      p_tenant_id: TENANT_ID,
      p_org_unit_id: null,
      p_name: "Q3 Plan",
      p_period_start: "2026-07-01",
      p_period_end: "2026-09-30",
      p_owner_user_id: null,
      p_actor_auth_user_id: ACTOR_ID,
      p_created_by: "tester",
    });
    assert.equal(plan.status, "draft");
  });
});

describe("publishSalesPlan", () => {
  test("classifies a known error code", async () => {
    const client = {
      async rpc() {
        return { data: null, error: { message: "overlapping_plan: another published plan already covers an overlapping period" } };
      },
    } as unknown as PipelineMutationRpcClient;

    await assert.rejects(
      () => publishSalesPlan(client, { planId: PLAN_ID, expectedVersion: 1, actorAuthUserId: ACTOR_ID, actorLabel: "tester" }),
      (err: unknown) => {
        assert.ok(err instanceof PipelineMutationError);
        assert.equal((err as PipelineMutationError).code, "overlapping_plan");
        return true;
      },
    );
  });

  test("classifies an unrecognized error message as mutation_failed", async () => {
    const client = {
      async rpc() {
        return { data: null, error: { message: "some unexpected database error" } };
      },
    } as unknown as PipelineMutationRpcClient;

    await assert.rejects(
      () => publishSalesPlan(client, { planId: PLAN_ID, expectedVersion: 1, actorAuthUserId: ACTOR_ID, actorLabel: "tester" }),
      (err: unknown) => {
        assert.ok(err instanceof PipelineMutationError);
        assert.equal((err as PipelineMutationError).code, "mutation_failed");
        return true;
      },
    );
  });
});

describe("createSalesTarget", () => {
  test("calls create_sales_target with the exact snake_case params", async () => {
    const calls: { fn: string; args: Record<string, unknown> }[] = [];
    const client = {
      async rpc(fn: string, args: Record<string, unknown>) {
        calls.push({ fn, args });
        return {
          data: {
            id: TARGET_ID,
            tenant_id: TENANT_ID,
            sales_plan_id: PLAN_ID,
            pipeline_category_id: null,
            metric_type: "leads_captured",
            org_unit_id: null,
            owner_user_id: null,
            target_value: 5,
            record_version: 1,
            created_by: "tester",
            created_at: "2026-07-23T00:00:00.000Z",
            updated_at: "2026-07-23T00:00:00.000Z",
          },
          error: null,
        };
      },
    } as unknown as PipelineMutationRpcClient;

    const target = await createSalesTarget(client, {
      salesPlanId: PLAN_ID,
      metricType: "leads_captured",
      targetValue: 5,
      actorAuthUserId: ACTOR_ID,
      createdBy: "tester",
    });

    assert.equal(calls[0]?.fn, "create_sales_target");
    assert.equal(target.targetValue, 5);
  });
});

describe("captureForecastSnapshot", () => {
  test("classifies override_reason_required", async () => {
    const client = {
      async rpc() {
        return { data: null, error: { message: "override_reason_required: an override value requires a non-empty override reason" } };
      },
    } as unknown as PipelineMutationRpcClient;

    await assert.rejects(
      () => captureForecastSnapshot(client, { salesTargetId: TARGET_ID, overrideValue: 5, actorAuthUserId: ACTOR_ID, actorLabel: "tester" }),
      (err: unknown) => {
        assert.ok(err instanceof PipelineMutationError);
        assert.equal((err as PipelineMutationError).code, "override_reason_required");
        return true;
      },
    );
  });
});

describe("recordPipelineOutcome", () => {
  test("classifies reason_outcome_mismatch", async () => {
    const client = {
      async rpc() {
        return { data: null, error: { message: "reason_outcome_mismatch: reason x is scoped to outcome won but lost was requested" } };
      },
    } as unknown as PipelineMutationRpcClient;

    await assert.rejects(
      () =>
        recordPipelineOutcome(client, {
          relatedType: "prospect",
          relatedId: PROSPECT_ID,
          outcome: "lost",
          winLossReasonId: REASON_ID,
          actorAuthUserId: ACTOR_ID,
          actorLabel: "tester",
        }),
      (err: unknown) => {
        assert.ok(err instanceof PipelineMutationError);
        assert.equal((err as PipelineMutationError).code, "reason_outcome_mismatch");
        return true;
      },
    );
  });
});
