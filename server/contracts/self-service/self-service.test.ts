import { test, describe } from "node:test";
import assert from "node:assert/strict";
import { DecideManagerApprovalQueueItemInputSchema } from "./self-service.ts";

const ACTOR_ID = "423e4567-e89b-12d3-a456-426614174000";
const ID_1 = "223e4567-e89b-12d3-a456-426614174000";

describe("DecideManagerApprovalQueueItemInputSchema", () => {
  test("accepts a valid leave decision (past-tense decision literal)", () => {
    const parsed = DecideManagerApprovalQueueItemInputSchema.parse({
      kind: "leave",
      requestStepId: ID_1,
      decision: "approved",
      reason: "looks fine",
      overrideCoverage: false,
      actorAuthUserId: ACTOR_ID,
      actorLabel: ACTOR_ID,
    });
    assert.equal(parsed.kind, "leave");
  });

  test("rejects a leave decision using the imperative literal from another domain", () => {
    assert.throws(() =>
      DecideManagerApprovalQueueItemInputSchema.parse({
        kind: "leave",
        requestStepId: ID_1,
        decision: "approve",
        reason: "x",
        overrideCoverage: false,
        actorAuthUserId: ACTOR_ID,
        actorLabel: ACTOR_ID,
      }),
    );
  });

  test("accepts a valid overtime decision (imperative decision literal)", () => {
    const parsed = DecideManagerApprovalQueueItemInputSchema.parse({
      kind: "overtime",
      requestId: ID_1,
      expectedVersion: 1,
      decision: "approve",
      decidedReason: "ok",
      approvedMinutesOverride: null,
      actorAuthUserId: ACTOR_ID,
      actorLabel: ACTOR_ID,
    });
    assert.equal(parsed.kind, "overtime");
  });

  test("rejects an overtime decision missing a reason", () => {
    assert.throws(() =>
      DecideManagerApprovalQueueItemInputSchema.parse({
        kind: "overtime",
        requestId: ID_1,
        expectedVersion: 1,
        decision: "approve",
        decidedReason: "",
        approvedMinutesOverride: null,
        actorAuthUserId: ACTOR_ID,
        actorLabel: ACTOR_ID,
      }),
    );
  });

  test("accepts a valid timesheet_entry decision", () => {
    const parsed = DecideManagerApprovalQueueItemInputSchema.parse({
      kind: "timesheet_entry",
      entryId: ID_1,
      expectedVersion: 2,
      decision: "reject",
      decidedReason: "not eligible",
      approvedMinutesOverride: null,
      actorAuthUserId: ACTOR_ID,
      actorLabel: ACTOR_ID,
    });
    assert.equal(parsed.kind, "timesheet_entry");
  });

  test("accepts a valid training_enrollment decision with a nullable decisionReason", () => {
    const parsed = DecideManagerApprovalQueueItemInputSchema.parse({
      kind: "training_enrollment",
      enrollmentId: ID_1,
      expectedVersion: 1,
      decision: "approve",
      decisionReason: null,
      actorAuthUserId: ACTOR_ID,
      actorLabel: ACTOR_ID,
    });
    assert.equal(parsed.kind, "training_enrollment");
  });

  test("rejects an unknown kind", () => {
    assert.throws(() =>
      DecideManagerApprovalQueueItemInputSchema.parse({
        kind: "attendance_correction",
        requestId: ID_1,
        actorAuthUserId: ACTOR_ID,
        actorLabel: ACTOR_ID,
      }),
    );
  });
});
