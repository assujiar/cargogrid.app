import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  createLeaveRequest,
  submitLeaveRequest,
  decideLeaveRequest,
  cancelLeaveRequest,
  adjustLeaveBalance,
  LeaveMutationError,
  type LeaveMutationRpcClient,
} from "./leave.ts";

const TENANT_ID = "123e4567-e89b-12d3-a456-426614174000";
const ID_1 = "223e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "323e4567-e89b-12d3-a456-426614174000";

function fakeClient(response: { data: unknown; error: { message: string } | null }): { client: LeaveMutationRpcClient; calls: { fn: string; args: Record<string, unknown> }[] } {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];
  const client = {
    async rpc(fn: string, args: Record<string, unknown>) {
      calls.push({ fn, args });
      return response;
    },
  } as unknown as LeaveMutationRpcClient;
  return { client, calls };
}

describe("createLeaveRequest", () => {
  test("maps input to snake_case RPC args", async () => {
    const { client, calls } = fakeClient({ data: [{ id: ID_1, status: "draft" }], error: null });
    await createLeaveRequest(client, {
      tenantId: TENANT_ID, leaveTypeId: ID_1, dateFrom: "2026-08-10", dateTo: "2026-08-10", dayPortion: "full_day",
      reason: "family event", destination: null, evidenceFileId: null, idempotencyKey: "k1", actorAuthUserId: ACTOR_ID, actorLabel: "emp",
    });
    assert.equal(calls[0]?.fn, "create_leave_request");
    assert.equal(calls[0]?.args.p_day_portion, "full_day");
  });

  test("classifies a known error prefix", async () => {
    const { client } = fakeClient({ data: null, error: { message: "leave_request_overlap: employee already has an overlapping request" } });
    await assert.rejects(
      () => createLeaveRequest(client, {
        tenantId: TENANT_ID, leaveTypeId: ID_1, dateFrom: "2026-08-10", dateTo: "2026-08-10", dayPortion: "full_day",
        reason: "family event", destination: null, evidenceFileId: null, idempotencyKey: null, actorAuthUserId: ACTOR_ID, actorLabel: "emp",
      }),
      (err: unknown) => err instanceof LeaveMutationError && err.code === "leave_request_overlap",
    );
  });

  test("falls back to mutation_failed for an unrecognized error prefix", async () => {
    const { client } = fakeClient({ data: null, error: { message: "totally_unexpected_thing: oops" } });
    await assert.rejects(
      () => createLeaveRequest(client, {
        tenantId: TENANT_ID, leaveTypeId: ID_1, dateFrom: "2026-08-10", dateTo: "2026-08-10", dayPortion: "full_day",
        reason: "family event", destination: null, evidenceFileId: null, idempotencyKey: null, actorAuthUserId: ACTOR_ID, actorLabel: "emp",
      }),
      (err: unknown) => err instanceof LeaveMutationError && err.code === "mutation_failed",
    );
  });
});

describe("submitLeaveRequest", () => {
  test("passes expectedVersion through", async () => {
    const { client, calls } = fakeClient({ data: [{ id: ID_1, status: "pending_approval" }], error: null });
    await submitLeaveRequest(client, { requestId: ID_1, expectedVersion: 1, actorAuthUserId: ACTOR_ID, actorLabel: "emp" });
    assert.equal(calls[0]?.args.p_expected_version, 1);
  });
});

describe("decideLeaveRequest", () => {
  test("passes overrideCoverage through", async () => {
    const { client, calls } = fakeClient({ data: [{ id: ID_1, status: "approved" }], error: null });
    await decideLeaveRequest(client, { requestStepId: ID_1, decision: "approved", reason: "ok", overrideCoverage: true, actorAuthUserId: ACTOR_ID, actorLabel: "mgr" });
    assert.equal(calls[0]?.args.p_override_coverage, true);
    assert.equal(calls[0]?.args.p_decision, "approved");
  });

  test("classifies coverage_below_minimum", async () => {
    const { client } = fakeClient({ data: null, error: { message: "coverage_below_minimum: approving this leave would drop coverage below minimum" } });
    await assert.rejects(
      () => decideLeaveRequest(client, { requestStepId: ID_1, decision: "approved", reason: "ok", overrideCoverage: false, actorAuthUserId: ACTOR_ID, actorLabel: "mgr" }),
      (err: unknown) => err instanceof LeaveMutationError && err.code === "coverage_below_minimum",
    );
  });
});

describe("cancelLeaveRequest", () => {
  test("classifies stale_version", async () => {
    const { client } = fakeClient({ data: null, error: { message: "stale_version: leave request target row was concurrently modified" } });
    await assert.rejects(
      () => cancelLeaveRequest(client, { requestId: ID_1, expectedVersion: 1, reason: "changed plans", actorAuthUserId: ACTOR_ID, actorLabel: "emp" }),
      (err: unknown) => err instanceof LeaveMutationError && err.code === "stale_version",
    );
  });
});

describe("adjustLeaveBalance", () => {
  test("maps a negative correction", async () => {
    const { client, calls } = fakeClient({ data: [{ id: ID_1, units: -1 }], error: null });
    await adjustLeaveBalance(client, {
      tenantId: TENANT_ID, employeeId: ID_1, leaveTypeId: ID_1, units: -1, effectiveDate: "2026-08-10",
      reason: "correction of prior over-credit", idempotencyKey: null, actorAuthUserId: ACTOR_ID, actorLabel: "hr",
    });
    assert.equal(calls[0]?.args.p_units, -1);
  });
});
