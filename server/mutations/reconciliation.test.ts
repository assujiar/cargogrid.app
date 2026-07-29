import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  executeFinanceReconciliationRun,
  resolveFinanceReconciliationException,
  certifyFinanceReconciliationRun,
  ReconciliationMutationError,
  type ReconciliationMutationRpcClient,
} from "./reconciliation.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const RUN_ID = "323e4567-e89b-12d3-a456-426614174001";
const EXCEPTION_ID = "323e4567-e89b-12d3-a456-426614174002";
const ACTOR_ID = "523e4567-e89b-12d3-a456-426614174000";

const RUN_ROW = {
  id: RUN_ID, tenant_id: TENANT_ID, company_id: null, scope: "ar", as_of_date: "2026-06-30",
  tolerance_amount: "0.00", control_total: "1000.00", source_total: "900.00", variance_amount: "100.00",
  is_within_tolerance: false, status: "completed", certify_reason: null, certified_by: null, certified_at: null,
  prepared_by: "fm", record_version: 1, created_at: "2026-06-30T00:00:00.000Z", updated_at: "2026-06-30T00:00:00.000Z",
};

const EXCEPTION_ROW = {
  id: EXCEPTION_ID, run_id: RUN_ID, tenant_id: TENANT_ID, item_type: "control_account_variance",
  description: "AR control account does not match", expected_amount: "900.00", actual_amount: "1000.00", variance_amount: "100.00",
  status: "open", owner: null, resolution_reason: null, resolved_by: null, resolved_at: null,
  record_version: 1, created_at: "2026-06-30T00:00:00.000Z", updated_at: "2026-06-30T00:00:00.000Z",
};

function fakeClient(response: { data: unknown; error: { message: string } | null }): ReconciliationMutationRpcClient & { calls: { fn: string; args: Record<string, unknown> }[] } {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];
  return {
    calls,
    async rpc(fn: string, args: Record<string, unknown>) {
      calls.push({ fn, args });
      return response;
    },
  } as unknown as ReconciliationMutationRpcClient & { calls: { fn: string; args: Record<string, unknown> }[] };
}

describe("executeFinanceReconciliationRun", () => {
  test("calls execute_finance_reconciliation_run with exact snake_case params", async () => {
    const client = fakeClient({ data: RUN_ROW, error: null });
    const run = await executeFinanceReconciliationRun(client, { tenantId: TENANT_ID, scope: "ar", asOfDate: "2026-06-30", actorAuthUserId: ACTOR_ID, actorLabel: "fm" });
    assert.equal(client.calls[0]?.fn, "execute_finance_reconciliation_run");
    assert.equal(run.isWithinTolerance, false);
  });

  test("wraps a finance_reconciliation_invalid_scope error", async () => {
    const client = fakeClient({ data: null, error: { message: "finance_reconciliation_invalid_scope: gl is not a supported reconciliation scope" } });
    await assert.rejects(
      () => executeFinanceReconciliationRun(client, { tenantId: TENANT_ID, scope: "ar", asOfDate: "2026-06-30", actorAuthUserId: ACTOR_ID, actorLabel: "fm" }),
      (error: unknown) => error instanceof ReconciliationMutationError && error.code === "finance_reconciliation_invalid_scope",
    );
  });
});

describe("resolveFinanceReconciliationException", () => {
  test("calls resolve_finance_reconciliation_exception and returns resolved", async () => {
    const client = fakeClient({ data: { ...EXCEPTION_ROW, status: "resolved" }, error: null });
    const exception = await resolveFinanceReconciliationException(client, { exceptionId: EXCEPTION_ID, expectedVersion: 1, resolutionReason: "timing difference, confirmed", actorAuthUserId: ACTOR_ID, actorLabel: "fe" });
    assert.equal(exception.status, "resolved");
  });

  test("wraps a finance_reconciliation_exception_not_open error", async () => {
    const client = fakeClient({ data: null, error: { message: "finance_reconciliation_exception_not_open: exception is resolved not open" } });
    await assert.rejects(
      () => resolveFinanceReconciliationException(client, { exceptionId: EXCEPTION_ID, expectedVersion: 1, resolutionReason: "already handled", actorAuthUserId: ACTOR_ID, actorLabel: "fe" }),
      (error: unknown) => error instanceof ReconciliationMutationError && error.code === "finance_reconciliation_exception_not_open",
    );
  });
});

describe("certifyFinanceReconciliationRun", () => {
  test("calls certify_finance_reconciliation_run and returns certified", async () => {
    const client = fakeClient({ data: { ...RUN_ROW, status: "certified" }, error: null });
    const run = await certifyFinanceReconciliationRun(client, { runId: RUN_ID, expectedVersion: 1, reason: "all exceptions resolved", actorAuthUserId: ACTOR_ID, actorLabel: "fm" });
    assert.equal(run.status, "certified");
  });

  test("wraps a finance_reconciliation_unexplained_variance error", async () => {
    const client = fakeClient({ data: null, error: { message: "finance_reconciliation_unexplained_variance: run has 1 unresolved exception(s)" } });
    await assert.rejects(
      () => certifyFinanceReconciliationRun(client, { runId: RUN_ID, expectedVersion: 1, reason: "attempt", actorAuthUserId: ACTOR_ID, actorLabel: "fm" }),
      (error: unknown) => error instanceof ReconciliationMutationError && error.code === "finance_reconciliation_unexplained_variance",
    );
  });
});
