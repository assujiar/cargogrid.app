import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  recordAttendanceClockEvent,
  requestAttendanceCorrection,
  decideAttendanceCorrection,
  waiveAttendanceException,
  AttendanceMutationError,
  type AttendanceMutationRpcClient,
} from "./attendance.ts";

const TENANT_ID = "123e4567-e89b-12d3-a456-426614174000";
const ID_1 = "223e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "323e4567-e89b-12d3-a456-426614174000";

function fakeClient(response: { data: unknown; error: { message: string } | null }): { client: AttendanceMutationRpcClient; calls: { fn: string; args: Record<string, unknown> }[] } {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];
  const client = {
    async rpc(fn: string, args: Record<string, unknown>) {
      calls.push({ fn, args });
      return response;
    },
  } as unknown as AttendanceMutationRpcClient;
  return { client, calls };
}

describe("recordAttendanceClockEvent", () => {
  test("maps input to snake_case RPC args", async () => {
    const { client, calls } = fakeClient({ data: [{ id: ID_1, event_type: "clock_in" }], error: null });
    await recordAttendanceClockEvent(client, {
      tenantId: TENANT_ID, eventType: "clock_in", sourceChannel: "mobile_web", clientReportedAt: null,
      locationGeojson: null, deviceLabel: null, idempotencyKey: "k1", actorAuthUserId: ACTOR_ID, actorLabel: "emp",
    });
    assert.equal(calls[0]?.fn, "record_attendance_clock_event");
    assert.equal(calls[0]?.args.p_source_channel, "mobile_web");
  });

  test("classifies a known error prefix", async () => {
    const { client } = fakeClient({ data: null, error: { message: "duplicate_open_session: employee already has an open session" } });
    await assert.rejects(
      () => recordAttendanceClockEvent(client, {
        tenantId: TENANT_ID, eventType: "clock_in", sourceChannel: "mobile_web", clientReportedAt: null,
        locationGeojson: null, deviceLabel: null, idempotencyKey: "k1", actorAuthUserId: ACTOR_ID, actorLabel: "emp",
      }),
      (err: unknown) => err instanceof AttendanceMutationError && err.code === "duplicate_open_session",
    );
  });

  test("falls back to mutation_failed for an unrecognized error prefix", async () => {
    const { client } = fakeClient({ data: null, error: { message: "totally_unexpected_thing: oops" } });
    await assert.rejects(
      () => recordAttendanceClockEvent(client, {
        tenantId: TENANT_ID, eventType: "clock_in", sourceChannel: "mobile_web", clientReportedAt: null,
        locationGeojson: null, deviceLabel: null, idempotencyKey: "k1", actorAuthUserId: ACTOR_ID, actorLabel: "emp",
      }),
      (err: unknown) => err instanceof AttendanceMutationError && err.code === "mutation_failed",
    );
  });
});

describe("requestAttendanceCorrection / decideAttendanceCorrection", () => {
  test("requestAttendanceCorrection rejects an empty reason at the schema layer, never reaching the RPC", async () => {
    const { client, calls } = fakeClient({ data: [{ id: ID_1 }], error: null });
    await assert.rejects(() =>
      requestAttendanceCorrection(client, {
        sessionId: ID_1, requestType: "adjust_clock_out", proposedClockInAt: null, proposedClockOutAt: "2026-08-10T10:00:00Z",
        reason: "", evidenceFileId: null, idempotencyKey: null, actorAuthUserId: ACTOR_ID, actorLabel: "emp",
      }),
    );
    assert.equal(calls.length, 0);
  });

  test("decideAttendanceCorrection surfaces self_approval_not_permitted", async () => {
    const { client } = fakeClient({ data: null, error: { message: "self_approval_not_permitted: an actor may not decide their own attendance correction request" } });
    await assert.rejects(
      () => decideAttendanceCorrection(client, { requestId: ID_1, expectedVersion: 1, decision: "approve", decidedReason: "ok", actorAuthUserId: ACTOR_ID, actorLabel: "emp" }),
      (err: unknown) => err instanceof AttendanceMutationError && err.code === "self_approval_not_permitted",
    );
  });
});

describe("waiveAttendanceException", () => {
  test("requires a non-empty waive reason at the schema layer", async () => {
    await assert.rejects(() =>
      waiveAttendanceException(fakeClient({ data: [], error: null }).client, {
        exceptionId: ID_1, expectedVersion: 1, waiveReason: "", actorAuthUserId: ACTOR_ID, actorLabel: "approver",
      }),
    );
  });
});
