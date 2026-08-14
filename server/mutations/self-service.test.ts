import { test, describe } from "node:test";
import assert from "node:assert/strict";
import { decideManagerApprovalQueueItem, SelfServiceMutationError, type SelfServiceMutationRpcClient } from "./self-service.ts";

const ACTOR_ID = "423e4567-e89b-12d3-a456-426614174000";
const ID_1 = "223e4567-e89b-12d3-a456-426614174000";

function fakeClient(response: { data: unknown; error: { message: string } | null }): { client: SelfServiceMutationRpcClient; calls: { fn: string; args: Record<string, unknown> }[] } {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];
  const client = {
    async rpc(fn: string, args: Record<string, unknown>) {
      calls.push({ fn, args });
      return response;
    },
  } as unknown as SelfServiceMutationRpcClient;
  return { client, calls };
}

describe("decideManagerApprovalQueueItem -- routes by kind to the owning capability's own canonical RPC, never a new one", () => {
  test("leave -> decide_leave_request, with the leave domain's own past-tense decision literal forwarded unchanged", async () => {
    const { client, calls } = fakeClient({ data: { id: ID_1 }, error: null });
    const result = await decideManagerApprovalQueueItem(client, {
      kind: "leave",
      requestStepId: ID_1,
      decision: "approved",
      reason: "ok",
      overrideCoverage: false,
      actorAuthUserId: ACTOR_ID,
      actorLabel: ACTOR_ID,
    });
    assert.equal(calls[0]?.fn, "decide_leave_request");
    assert.equal(calls[0]?.args.p_request_step_id, ID_1);
    assert.equal(calls[0]?.args.p_decision, "approved");
    assert.deepEqual(result, { kind: "leave", id: ID_1 });
  });

  test("overtime -> decide_overtime_request", async () => {
    const { client, calls } = fakeClient({ data: { id: ID_1 }, error: null });
    const result = await decideManagerApprovalQueueItem(client, {
      kind: "overtime",
      requestId: ID_1,
      expectedVersion: 3,
      decision: "approve",
      decidedReason: "ok",
      approvedMinutesOverride: null,
      actorAuthUserId: ACTOR_ID,
      actorLabel: ACTOR_ID,
    });
    assert.equal(calls[0]?.fn, "decide_overtime_request");
    assert.equal(calls[0]?.args.p_expected_version, 3);
    assert.deepEqual(result, { kind: "overtime", id: ID_1 });
  });

  test("timesheet_entry -> decide_timesheet_entry", async () => {
    const { client, calls } = fakeClient({ data: { id: ID_1 }, error: null });
    await decideManagerApprovalQueueItem(client, {
      kind: "timesheet_entry",
      entryId: ID_1,
      expectedVersion: 1,
      decision: "reject",
      decidedReason: "no",
      approvedMinutesOverride: null,
      actorAuthUserId: ACTOR_ID,
      actorLabel: ACTOR_ID,
    });
    assert.equal(calls[0]?.fn, "decide_timesheet_entry");
    assert.equal(calls[0]?.args.p_decision, "reject");
  });

  test("training_enrollment -> decide_training_enrollment", async () => {
    const { client, calls } = fakeClient({
      data: { id: ID_1, session_id: ID_1, course_version_id: ID_1, status: "enrolled", enrollment_source: "self", record_version: 2 },
      error: null,
    });
    const result = await decideManagerApprovalQueueItem(client, {
      kind: "training_enrollment",
      enrollmentId: ID_1,
      expectedVersion: 1,
      decision: "approve",
      decisionReason: null,
      actorAuthUserId: ACTOR_ID,
      actorLabel: ACTOR_ID,
    });
    assert.equal(calls[0]?.fn, "decide_training_enrollment");
    assert.deepEqual(result, { kind: "training_enrollment", id: ID_1 });
  });

  test("surfaces the owning capability's own RPC error as a single SelfServiceMutationError type, message preserved", async () => {
    const { client } = fakeClient({ data: null, error: { message: "insufficient_authority: identity lacks HRS:Approve" } });
    await assert.rejects(
      () =>
        decideManagerApprovalQueueItem(client, {
          kind: "overtime",
          requestId: ID_1,
          expectedVersion: 1,
          decision: "approve",
          decidedReason: "ok",
          approvedMinutesOverride: null,
          actorAuthUserId: ACTOR_ID,
          actorLabel: ACTOR_ID,
        }),
      (error: unknown) => {
        assert.ok(error instanceof SelfServiceMutationError);
        assert.match((error as Error).message, /insufficient_authority/);
        return true;
      },
    );
  });

  test("rejects malformed input before any RPC call (zod validation, no partial dispatch)", async () => {
    const { client, calls } = fakeClient({ data: null, error: null });
    await assert.rejects(() =>
      decideManagerApprovalQueueItem(client, {
        kind: "overtime",
        requestId: ID_1,
        expectedVersion: 1,
        decision: "approve",
        decidedReason: "", // empty -- schema requires min(1)
        approvedMinutesOverride: null,
        actorAuthUserId: ACTOR_ID,
        actorLabel: ACTOR_ID,
      }),
    );
    assert.equal(calls.length, 0);
  });
});
