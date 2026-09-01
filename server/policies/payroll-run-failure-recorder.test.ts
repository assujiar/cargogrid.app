import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  isGenuinePayrollRunCalculationFailure,
  recordPayrollRunCalculationFailure,
  observePayrollRunCalculationFailure,
  type PayrollRunFailureRecorderRpcClient,
} from "./payroll-run-failure-recorder.ts";
import { PayrollMutationError } from "../mutations/payroll.ts";

const RUN_ID = "423e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "523e4567-e89b-12d3-a456-426614174000";
const CONTEXT = { runId: RUN_ID, actorAuthUserId: ACTOR_ID, actorLabel: ACTOR_ID };

function stubClient(behaviour: { error?: string; throws?: boolean } = {}) {
  const calls: Record<string, unknown>[] = [];
  const client: PayrollRunFailureRecorderRpcClient = {
    async rpc(_fn, args) {
      calls.push(args);
      if (behaviour.throws) throw new Error("network is down");
      return { data: null, error: behaviour.error ? { message: behaviour.error } : null };
    },
  };
  return { client, calls };
}

describe("isGenuinePayrollRunCalculationFailure", () => {
  /**
   * The reason this matters: app.calculate_payroll_run raises several routine,
   * already-classified rejections (stale version, missing HRS:Edit, wrong status, ...) before it
   * does any real work. Those are the validation layer working correctly, not the crash
   * ISS-2026-079 is about -- alerting on each one would flood the on-call with noise every time
   * two HR admins click "Calculate" on the same run at once.
   */
  test("is false for a PayrollMutationError with a known, classified code", () => {
    assert.equal(isGenuinePayrollRunCalculationFailure(new PayrollMutationError("stale_version: expected 1 but found 2")), false);
    assert.equal(isGenuinePayrollRunCalculationFailure(new PayrollMutationError("insufficient_authority: identity x lacks HRS:Edit")), false);
    assert.equal(isGenuinePayrollRunCalculationFailure(new PayrollMutationError("payroll_period_inputs_not_frozen: period y")), false);
  });

  test("is true for a PayrollMutationError PAYROLL_KNOWN_MUTATION_ERROR_CODES cannot classify", () => {
    assert.equal(isGenuinePayrollRunCalculationFailure(new PayrollMutationError("statement_timeout: canceling statement due to statement timeout")), true);
  });

  test("is true for a raw, non-PayrollMutationError throw (a network failure)", () => {
    assert.equal(isGenuinePayrollRunCalculationFailure(new Error("fetch failed")), true);
    assert.equal(isGenuinePayrollRunCalculationFailure("some raw string rejection"), true);
  });
});

describe("recordPayrollRunCalculationFailure", () => {
  test("passes the run, actor and truncated error detail through under its snake_case RPC name", async () => {
    const { client, calls } = stubClient();
    const written = await recordPayrollRunCalculationFailure(client, CONTEXT, "statement_timeout: canceling statement");
    assert.equal(written, true);
    assert.equal(calls.length, 1);
    assert.equal(calls[0]?.p_run_id, RUN_ID);
    assert.equal(calls[0]?.p_actor_auth_user_id, ACTOR_ID);
    assert.equal(calls[0]?.p_error_detail, "statement_timeout: canceling statement");
  });

  test("truncates the error detail -- this column is evidence a crash happened, not a stack-trace dump", async () => {
    const { client, calls } = stubClient();
    await recordPayrollRunCalculationFailure(client, CONTEXT, "x".repeat(5000));
    assert.equal(String(calls[0]?.p_error_detail).length, 2000);
  });

  /**
   * The important guarantee, mirrored from recordAuthorityDenial: the calculation attempt has
   * already failed by the time this runs. Turning that into a SECOND, unrelated 500 because the
   * observability write itself failed would be strictly worse than losing one alert row.
   */
  test("never throws, and reports failure, when the RPC errors or the call itself blows up", async () => {
    const errored = stubClient({ error: "payroll_run_not_found: …" });
    assert.equal(await recordPayrollRunCalculationFailure(errored.client, CONTEXT, "boom"), false);

    const threw = stubClient({ throws: true });
    assert.equal(await recordPayrollRunCalculationFailure(threw.client, CONTEXT, "boom"), false);
  });
});

describe("observePayrollRunCalculationFailure", () => {
  test("records and alerts on a genuine, unclassified failure", async () => {
    const { client, calls } = stubClient();
    await observePayrollRunCalculationFailure(client, CONTEXT, new Error("connection reset by peer"));
    assert.equal(calls.length, 1);
    assert.equal(calls[0]?.p_run_id, RUN_ID);
  });

  test("stays silent for a routine, already-classified PayrollMutationError rejection", async () => {
    const { client, calls } = stubClient();
    await observePayrollRunCalculationFailure(client, CONTEXT, new PayrollMutationError("stale_version: expected 1 but found 2"));
    assert.equal(calls.length, 0);
  });

  test("handles a non-Error rejection without throwing", async () => {
    const { client, calls } = stubClient();
    await observePayrollRunCalculationFailure(client, CONTEXT, "raw string rejection");
    assert.equal(calls.length, 1);
  });
});
