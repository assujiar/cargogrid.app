import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  createMilestoneTemplateDraft,
  setMilestoneTemplateSequence,
  publishMilestoneTemplateVersion,
  ingestMilestoneEvent,
  MilestoneManagementMutationError,
  type MilestoneManagementMutationRpcClient,
} from "./milestone-management.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const VERSION_ID = "323e4567-e89b-12d3-a456-426614174000";
const SHIPMENT_ID = "423e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "523e4567-e89b-12d3-a456-426614174000";
const EVENT_ID = "623e4567-e89b-12d3-a456-426614174000";

function fakeRpcClient(response: { data: unknown; error: { message: string } | null }): {
  client: MilestoneManagementMutationRpcClient;
  calls: { fn: string; args: Record<string, unknown> }[];
} {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];
  const client = {
    async rpc(fn: string, args: Record<string, unknown>) {
      calls.push({ fn, args });
      return response;
    },
  } as unknown as MilestoneManagementMutationRpcClient;
  return { client, calls };
}

const TEMPLATE_ROW = {
  id: VERSION_ID,
  tenant_id: TENANT_ID,
  mode: "sea",
  status: "draft",
  sequence: [],
  supersedes_version_id: null,
  record_version: 1,
  created_by: "rep",
  created_at: "2026-07-27T00:00:00.000Z",
  updated_at: "2026-07-27T00:00:00.000Z",
};

const EVENT_ROW = {
  id: EVENT_ID,
  tenant_id: TENANT_ID,
  shipment_order_id: SHIPMENT_ID,
  milestone_code: "picked_up",
  event_time: "2026-07-27T08:00:00.000Z",
  received_time: "2026-07-27T08:05:00.000Z",
  location: null,
  source: "manual",
  reason: null,
  corrects_event_id: null,
  idempotency_key: "idem-1",
  sequence_no: 1,
  created_by: "rep",
  created_at: "2026-07-27T08:05:00.000Z",
};

describe("createMilestoneTemplateDraft", () => {
  test("calls create_milestone_template_draft with the exact snake_case params", async () => {
    const { client, calls } = fakeRpcClient({ data: TEMPLATE_ROW, error: null });
    const version = await createMilestoneTemplateDraft(client, { tenantId: TENANT_ID, mode: "sea", actorAuthUserId: ACTOR_ID, actorLabel: "rep" });
    assert.equal(calls[0]?.fn, "create_milestone_template_draft");
    assert.deepEqual(calls[0]?.args, { p_tenant_id: TENANT_ID, p_mode: "sea", p_actor_auth_user_id: ACTOR_ID, p_actor_label: "rep" });
    assert.equal(version.status, "draft");
  });
});

describe("setMilestoneTemplateSequence", () => {
  test("classifies milestone_unknown_code", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "milestone_unknown_code: not_a_real_code is not a registered milestone code" } });
    await assert.rejects(
      () => setMilestoneTemplateSequence(client, { versionId: VERSION_ID, sequence: [{ code: "not_a_real_code" }], actorAuthUserId: ACTOR_ID, actorLabel: "rep" }),
      (err: unknown) => {
        assert.ok(err instanceof MilestoneManagementMutationError);
        assert.equal(err.code, "milestone_unknown_code");
        return true;
      },
    );
  });
});

describe("publishMilestoneTemplateVersion", () => {
  test("calls publish_milestone_template_version with the exact snake_case params", async () => {
    const { client, calls } = fakeRpcClient({ data: { ...TEMPLATE_ROW, status: "published" }, error: null });
    const version = await publishMilestoneTemplateVersion(client, { versionId: VERSION_ID, expectedVersion: 1, actorAuthUserId: ACTOR_ID, actorLabel: "rep" });
    assert.equal(calls[0]?.fn, "publish_milestone_template_version");
    assert.deepEqual(calls[0]?.args, {
      p_version_id: VERSION_ID,
      p_expected_version: 1,
      p_supersedes_version_id: null,
      p_actor_auth_user_id: ACTOR_ID,
      p_actor_label: "rep",
    });
    assert.equal(version.status, "published");
  });

  test("classifies milestone_invalid_sequence", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "milestone_invalid_sequence: a milestone template cannot publish with an empty sequence" } });
    await assert.rejects(
      () => publishMilestoneTemplateVersion(client, { versionId: VERSION_ID, expectedVersion: 1, actorAuthUserId: ACTOR_ID, actorLabel: "rep" }),
      (err: unknown) => {
        assert.ok(err instanceof MilestoneManagementMutationError);
        assert.equal(err.code, "milestone_invalid_sequence");
        return true;
      },
    );
  });
});

describe("ingestMilestoneEvent", () => {
  test("calls ingest_milestone_event with the exact snake_case params", async () => {
    const { client, calls } = fakeRpcClient({ data: EVENT_ROW, error: null });
    const event = await ingestMilestoneEvent(client, {
      shipmentOrderId: SHIPMENT_ID,
      milestoneCode: "picked_up",
      eventTime: "2026-07-27T08:00:00.000Z",
      source: "manual",
      idempotencyKey: "idem-1",
      actorAuthUserId: ACTOR_ID,
      actorLabel: "rep",
    });
    assert.equal(calls[0]?.fn, "ingest_milestone_event");
    assert.deepEqual(calls[0]?.args, {
      p_shipment_order_id: SHIPMENT_ID,
      p_milestone_code: "picked_up",
      p_event_time: "2026-07-27T08:00:00.000Z",
      p_received_time: null,
      p_location: null,
      p_source: "manual",
      p_reason: null,
      p_corrects_event_id: null,
      p_idempotency_key: "idem-1",
      p_actor_auth_user_id: ACTOR_ID,
      p_actor_label: "rep",
    });
    assert.equal(event.milestoneCode, "picked_up");
  });

  test("classifies reason_required for a correction with no reason", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "reason_required: a correction requires a non-empty reason" } });
    await assert.rejects(
      () =>
        ingestMilestoneEvent(client, {
          shipmentOrderId: SHIPMENT_ID,
          milestoneCode: "picked_up",
          eventTime: "2026-07-27T08:00:00.000Z",
          source: "manual",
          correctsEventId: EVENT_ID,
          idempotencyKey: "idem-2",
          actorAuthUserId: ACTOR_ID,
          actorLabel: "rep",
        }),
      (err: unknown) => {
        assert.ok(err instanceof MilestoneManagementMutationError);
        assert.equal(err.code, "reason_required");
        return true;
      },
    );
  });

  test("classifies invalid_transition for a cancelled shipment", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "invalid_transition: shipment order X is cancelled and can no longer receive milestone events" } });
    await assert.rejects(
      () =>
        ingestMilestoneEvent(client, {
          shipmentOrderId: SHIPMENT_ID,
          milestoneCode: "picked_up",
          eventTime: "2026-07-27T08:00:00.000Z",
          source: "manual",
          idempotencyKey: "idem-3",
          actorAuthUserId: ACTOR_ID,
          actorLabel: "rep",
        }),
      (err: unknown) => {
        assert.ok(err instanceof MilestoneManagementMutationError);
        assert.equal(err.code, "invalid_transition");
        return true;
      },
    );
  });

  test("falls back to mutation_failed for an unrecognized error message", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "boom, something unrelated broke" } });
    await assert.rejects(
      () =>
        ingestMilestoneEvent(client, {
          shipmentOrderId: SHIPMENT_ID,
          milestoneCode: "picked_up",
          eventTime: "2026-07-27T08:00:00.000Z",
          source: "manual",
          idempotencyKey: "idem-4",
          actorAuthUserId: ACTOR_ID,
          actorLabel: "rep",
        }),
      (err: unknown) => {
        assert.ok(err instanceof MilestoneManagementMutationError);
        assert.equal(err.code, "mutation_failed");
        return true;
      },
    );
  });
});
