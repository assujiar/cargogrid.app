import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  startEpodCapture,
  setEpodEvidence,
  submitEpodCapture,
  reviewEpodCapture,
  reviseEpodCapture,
  completeEpodCapture,
  EpodCaptureReviewMutationError,
  type EpodCaptureReviewMutationRpcClient,
} from "./epod-capture-review.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const SHIPMENT_ID = "323e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "423e4567-e89b-12d3-a456-426614174000";
const CAPTURE_ID = "523e4567-e89b-12d3-a456-426614174000";
const FILE_ID = "623e4567-e89b-12d3-a456-426614174000";

function fakeRpcClient(response: { data: unknown; error: { message: string } | null }): {
  client: EpodCaptureReviewMutationRpcClient;
  calls: { fn: string; args: Record<string, unknown> }[];
} {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];
  const client = {
    async rpc(fn: string, args: Record<string, unknown>) {
      calls.push({ fn, args });
      return response;
    },
  } as unknown as EpodCaptureReviewMutationRpcClient;
  return { client, calls };
}

const CAPTURE_ROW = {
  id: CAPTURE_ID,
  tenant_id: TENANT_ID,
  shipment_order_id: SHIPMENT_ID,
  milestone_event_id: null,
  version_group_id: CAPTURE_ID,
  version_number: 1,
  is_latest_version: true,
  status: "draft",
  receiver_name: null,
  receiver_position: null,
  signature_file_id: null,
  photo_file_ids: [],
  delivery_geog: null,
  captured_at: null,
  server_received_at: "2026-07-28T09:00:00.000Z",
  reviewed_by_auth_user_id: null,
  reviewed_at: null,
  review_notes: null,
  record_version: 1,
  created_by: "rep",
  created_at: "2026-07-28T09:00:00.000Z",
  updated_at: "2026-07-28T09:00:00.000Z",
};

describe("startEpodCapture", () => {
  test("calls start_epod_capture with the exact snake_case params", async () => {
    const { client, calls } = fakeRpcClient({ data: CAPTURE_ROW, error: null });
    const capture = await startEpodCapture(client, { tenantId: TENANT_ID, shipmentOrderId: SHIPMENT_ID, idempotencyKey: "idem-epod-1", actorAuthUserId: ACTOR_ID, actorLabel: "rep" });
    assert.equal(calls[0]?.fn, "start_epod_capture");
    assert.deepEqual(calls[0]?.args, {
      p_tenant_id: TENANT_ID,
      p_shipment_order_id: SHIPMENT_ID,
      p_milestone_event_id: null,
      p_idempotency_key: "idem-epod-1",
      p_actor_auth_user_id: ACTOR_ID,
      p_actor_label: "rep",
    });
    assert.equal(capture.status, "draft");
  });

  test("classifies epod_shipment_not_delivered", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "epod_shipment_not_delivered: shipment order is confirmed" } });
    await assert.rejects(
      () => startEpodCapture(client, { tenantId: TENANT_ID, shipmentOrderId: SHIPMENT_ID, idempotencyKey: "idem-epod-1", actorAuthUserId: ACTOR_ID, actorLabel: "rep" }),
      (err: unknown) => {
        assert.ok(err instanceof EpodCaptureReviewMutationError);
        assert.equal(err.code, "epod_shipment_not_delivered");
        return true;
      },
    );
  });
});

describe("setEpodEvidence", () => {
  test("calls set_epod_evidence with defaults for optional fields", async () => {
    const { client, calls } = fakeRpcClient({ data: { ...CAPTURE_ROW, receiver_name: "Budi Santoso" }, error: null });
    const capture = await setEpodEvidence(client, { captureId: CAPTURE_ID, receiverName: "Budi Santoso", actorAuthUserId: ACTOR_ID, actorLabel: "rep" });
    assert.equal(calls[0]?.fn, "set_epod_evidence");
    assert.deepEqual(calls[0]?.args, {
      p_capture_id: CAPTURE_ID,
      p_receiver_name: "Budi Santoso",
      p_receiver_position: null,
      p_signature_file_id: null,
      p_photo_file_ids: [],
      p_delivery_geojson: null,
      p_captured_at: null,
      p_actor_auth_user_id: ACTOR_ID,
      p_actor_label: "rep",
    });
    assert.equal(capture.receiverName, "Budi Santoso");
  });

  test("classifies epod_evidence_file_mismatch", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "epod_evidence_file_mismatch: signature file does not belong to shipment order" } });
    await assert.rejects(
      () => setEpodEvidence(client, { captureId: CAPTURE_ID, receiverName: "Budi", signatureFileId: FILE_ID, actorAuthUserId: ACTOR_ID, actorLabel: "rep" }),
      (err: unknown) => {
        assert.ok(err instanceof EpodCaptureReviewMutationError);
        assert.equal(err.code, "epod_evidence_file_mismatch");
        return true;
      },
    );
  });
});

describe("submitEpodCapture", () => {
  test("classifies epod_missing_evidence", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "epod_missing_evidence: at least one of a signature or a photo is required" } });
    await assert.rejects(
      () => submitEpodCapture(client, { captureId: CAPTURE_ID, expectedVersion: 1, actorAuthUserId: ACTOR_ID, actorLabel: "rep" }),
      (err: unknown) => {
        assert.ok(err instanceof EpodCaptureReviewMutationError);
        assert.equal(err.code, "epod_missing_evidence");
        return true;
      },
    );
  });

  test("classifies epod_unsafe_evidence for an unscanned file", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "epod_unsafe_evidence: signature file has scan status pending" } });
    await assert.rejects(
      () => submitEpodCapture(client, { captureId: CAPTURE_ID, expectedVersion: 1, actorAuthUserId: ACTOR_ID, actorLabel: "rep" }),
      (err: unknown) => {
        assert.ok(err instanceof EpodCaptureReviewMutationError);
        assert.equal(err.code, "epod_unsafe_evidence");
        return true;
      },
    );
  });
});

describe("reviewEpodCapture", () => {
  test("calls review_epod_capture with the exact snake_case params", async () => {
    const { client, calls } = fakeRpcClient({ data: { ...CAPTURE_ROW, status: "approved" }, error: null });
    const capture = await reviewEpodCapture(client, { captureId: CAPTURE_ID, decision: "approved", expectedVersion: 1, actorAuthUserId: ACTOR_ID, actorLabel: "rep" });
    assert.equal(calls[0]?.fn, "review_epod_capture");
    assert.deepEqual(calls[0]?.args, {
      p_capture_id: CAPTURE_ID,
      p_decision: "approved",
      p_notes: null,
      p_expected_version: 1,
      p_actor_auth_user_id: ACTOR_ID,
      p_actor_label: "rep",
    });
    assert.equal(capture.status, "approved");
  });

  test("classifies epod_revision_reason_required", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "epod_revision_reason_required: notes are required" } });
    await assert.rejects(
      () => reviewEpodCapture(client, { captureId: CAPTURE_ID, decision: "revision_requested", expectedVersion: 1, actorAuthUserId: ACTOR_ID, actorLabel: "rep" }),
      (err: unknown) => {
        assert.ok(err instanceof EpodCaptureReviewMutationError);
        assert.equal(err.code, "epod_revision_reason_required");
        return true;
      },
    );
  });
});

describe("reviseEpodCapture", () => {
  test("calls revise_epod_capture and returns the new version", async () => {
    const { client, calls } = fakeRpcClient({ data: { ...CAPTURE_ROW, version_number: 2 }, error: null });
    const capture = await reviseEpodCapture(client, { previousCaptureId: CAPTURE_ID, actorAuthUserId: ACTOR_ID, actorLabel: "rep" });
    assert.equal(calls[0]?.fn, "revise_epod_capture");
    assert.deepEqual(calls[0]?.args, { p_previous_capture_id: CAPTURE_ID, p_actor_auth_user_id: ACTOR_ID, p_actor_label: "rep" });
    assert.equal(capture.versionNumber, 2);
  });
});

describe("completeEpodCapture", () => {
  test("calls complete_epod_capture with the exact snake_case params", async () => {
    const { client, calls } = fakeRpcClient({ data: { ...CAPTURE_ROW, status: "completed" }, error: null });
    const capture = await completeEpodCapture(client, {
      captureId: CAPTURE_ID,
      expectedCaptureVersion: 1,
      shipmentExpectedVersion: 5,
      idempotencyKey: "idem-epod-complete-1",
      actorAuthUserId: ACTOR_ID,
      actorLabel: "rep",
    });
    assert.equal(calls[0]?.fn, "complete_epod_capture");
    assert.deepEqual(calls[0]?.args, {
      p_capture_id: CAPTURE_ID,
      p_expected_capture_version: 1,
      p_shipment_expected_version: 5,
      p_idempotency_key: "idem-epod-complete-1",
      p_actor_auth_user_id: ACTOR_ID,
      p_actor_label: "rep",
    });
    assert.equal(capture.status, "completed");
  });

  test("classifies invalid_transition when the capture is not yet approved", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "invalid_transition: ePOD capture is draft and cannot be completed" } });
    await assert.rejects(
      () =>
        completeEpodCapture(client, {
          captureId: CAPTURE_ID,
          expectedCaptureVersion: 1,
          shipmentExpectedVersion: 5,
          idempotencyKey: "idem-epod-complete-1",
          actorAuthUserId: ACTOR_ID,
          actorLabel: "rep",
        }),
      (err: unknown) => {
        assert.ok(err instanceof EpodCaptureReviewMutationError);
        assert.equal(err.code, "invalid_transition");
        return true;
      },
    );
  });
});
