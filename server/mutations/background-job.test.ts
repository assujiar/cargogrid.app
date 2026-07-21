import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  enqueueJob,
  claimNextJob,
  heartbeatJob,
  completeJob,
  appendEventLog,
  dispatchEventAsJob,
  markEventDispatchFailed,
  BackgroundJobMutationError,
  type BackgroundJobMutationRpcClient,
} from "./background-job.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const JOB_ID = "323e4567-e89b-12d3-a456-426614174000";
const EVENT_ID = "423e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "523e4567-e89b-12d3-a456-426614174000";

const VALID_JOB_ROW = {
  job_id: JOB_ID,
  tenant_id: TENANT_ID,
  job_type: "notification_batch",
  status: "pending",
  priority: 0,
  payload: {},
  attempts: 0,
  max_attempts: 3,
  locked_by: null,
  locked_until: null,
  error: null,
  result_url: null,
  created_by: "requester",
  created_at: "2026-07-19T00:00:00.000Z",
  completed_at: null,
  requested_by_auth_user_id: ACTOR_ID,
  idempotency_key: "idem-1",
  import_export_schema_code: null,
  source_file_id: null,
  result_file_id: null,
  total_rows: null,
  processed_rows: 0,
  valid_row_count: 0,
  invalid_row_count: 0,
  cancel_reason: null,
  updated_at: "2026-07-19T00:00:00.000Z",
};

const VALID_EVENT_ROW = {
  id: EVENT_ID,
  tenant_id: TENANT_ID,
  event_type: "shipment.dispatched",
  resource_type: "shipment",
  resource_id: null,
  payload: {},
  dispatch_status: "pending",
  related_job_id: null,
  occurred_at: "2026-07-19T00:00:00.000Z",
  dispatched_at: null,
  error: null,
  created_by: "requester",
};

function fakeClient(
  response: { data: unknown; error: { message: string } | null },
): BackgroundJobMutationRpcClient & { calls: { fn: string; args: Record<string, unknown> }[] } {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];
  return {
    calls,
    async rpc(fn, args) {
      calls.push({ fn, args });
      return response;
    },
  };
}

describe("enqueueJob", () => {
  test("calls enqueue_job with the exact snake_case params", async () => {
    const client = fakeClient({ data: VALID_JOB_ROW, error: null });
    const job = await enqueueJob(client, { tenantId: TENANT_ID, jobType: "notification_batch", actorAuthUserId: ACTOR_ID, actorLabel: "requester" });

    assert.deepEqual(client.calls[0]?.args, {
      p_tenant_id: TENANT_ID,
      p_job_type: "notification_batch",
      p_payload: {},
      p_priority: 0,
      p_idempotency_key: null,
      p_max_attempts: 3,
      p_actor_auth_user_id: ACTOR_ID,
      p_actor_label: "requester",
    });
    assert.equal(job.jobId, JOB_ID);
  });

  test("classifies job_type_requires_dedicated_entrypoint into a typed error code", async () => {
    const client = fakeClient({ data: null, error: { message: "job_type_requires_dedicated_entrypoint: import jobs must be created via app.create_import_export_job()" } });
    await assert.rejects(
      () => enqueueJob(client, { tenantId: TENANT_ID, jobType: "notification_batch", actorAuthUserId: ACTOR_ID, actorLabel: "requester" }),
      (err: unknown) => {
        assert.ok(err instanceof BackgroundJobMutationError);
        assert.equal(err.code, "job_type_requires_dedicated_entrypoint");
        return true;
      },
    );
  });
});

describe("claimNextJob", () => {
  test("calls claim_next_job with the exact snake_case params and returns the claimed job", async () => {
    const client = fakeClient({ data: { ...VALID_JOB_ROW, status: "in_progress", locked_by: "worker-1" }, error: null });
    const job = await claimNextJob(client, { workerId: "worker-1", jobTypes: ["notification_batch"] });

    assert.deepEqual(client.calls[0]?.args, { p_worker_id: "worker-1", p_job_types: ["notification_batch"], p_lease_duration_seconds: 300 });
    assert.equal(job?.status, "in_progress");
  });

  test("returns null when nothing is claimable, not an error", async () => {
    const client = fakeClient({ data: null, error: null });
    const job = await claimNextJob(client, { workerId: "worker-1", jobTypes: ["notification_batch"] });
    assert.equal(job, null);
  });
});

describe("heartbeatJob", () => {
  test("calls heartbeat_job with the exact snake_case params", async () => {
    const client = fakeClient({ data: { ...VALID_JOB_ROW, status: "in_progress", locked_by: "worker-1" }, error: null });
    await heartbeatJob(client, { jobId: JOB_ID, workerId: "worker-1" });
    assert.deepEqual(client.calls[0]?.args, { p_job_id: JOB_ID, p_worker_id: "worker-1", p_lease_duration_seconds: 300 });
  });

  test("classifies job_lease_not_held into a typed error code", async () => {
    const client = fakeClient({ data: null, error: { message: "job_lease_not_held: worker worker-2 does not hold the current lease for job x" } });
    await assert.rejects(
      () => heartbeatJob(client, { jobId: JOB_ID, workerId: "worker-2" }),
      (err: unknown) => {
        assert.ok(err instanceof BackgroundJobMutationError);
        assert.equal(err.code, "job_lease_not_held");
        return true;
      },
    );
  });
});

describe("completeJob", () => {
  test("calls complete_job with the exact snake_case params", async () => {
    const client = fakeClient({ data: { ...VALID_JOB_ROW, status: "completed", locked_by: null }, error: null });
    const job = await completeJob(client, { jobId: JOB_ID, workerId: "worker-1", resultUrl: "https://example.test/r", actorLabel: "worker-1" });

    assert.deepEqual(client.calls[0]?.args, { p_job_id: JOB_ID, p_worker_id: "worker-1", p_result_url: "https://example.test/r", p_actor_label: "worker-1" });
    assert.equal(job.status, "completed");
  });
});

describe("appendEventLog", () => {
  test("calls append_event_log with the exact snake_case params", async () => {
    const client = fakeClient({ data: VALID_EVENT_ROW, error: null });
    const event = await appendEventLog(client, { tenantId: TENANT_ID, eventType: "shipment.dispatched", resourceType: "shipment", actorAuthUserId: ACTOR_ID, actorLabel: "requester" });

    assert.deepEqual(client.calls[0]?.args, {
      p_tenant_id: TENANT_ID,
      p_event_type: "shipment.dispatched",
      p_resource_type: "shipment",
      p_resource_id: null,
      p_payload: {},
      p_actor_auth_user_id: ACTOR_ID,
      p_actor_label: "requester",
    });
    assert.equal(event.eventType, "shipment.dispatched");
  });

  test("classifies event_missing_type into a typed error code", async () => {
    const client = fakeClient({ data: null, error: { message: "event_missing_type: an event_type is required" } });
    await assert.rejects(
      () => appendEventLog(client, { tenantId: TENANT_ID, eventType: "x", resourceType: "shipment", actorAuthUserId: ACTOR_ID, actorLabel: "requester" }),
      (err: unknown) => {
        assert.ok(err instanceof BackgroundJobMutationError);
        assert.equal(err.code, "event_missing_type");
        return true;
      },
    );
  });
});

describe("dispatchEventAsJob", () => {
  test("calls dispatch_event_as_job with the exact snake_case params", async () => {
    const client = fakeClient({ data: { ...VALID_JOB_ROW, job_type: "webhook_retry", requested_by_auth_user_id: null }, error: null });
    const job = await dispatchEventAsJob(client, { eventId: EVENT_ID, jobType: "webhook_retry", actorLabel: "outbox-drain" });

    assert.deepEqual(client.calls[0]?.args, {
      p_event_id: EVENT_ID,
      p_job_type: "webhook_retry",
      p_priority: 0,
      p_idempotency_key: null,
      p_max_attempts: 3,
      p_actor_label: "outbox-drain",
    });
    assert.equal(job.requestedByAuthUserId, null);
  });

  test("classifies event_invalid_job_type into a typed error code", async () => {
    const client = fakeClient({ data: null, error: { message: "event_invalid_job_type: not_a_real_type is not a dispatchable generic job type" } });
    await assert.rejects(
      () => dispatchEventAsJob(client, { eventId: EVENT_ID, jobType: "webhook_retry", actorLabel: "outbox-drain" }),
      (err: unknown) => {
        assert.ok(err instanceof BackgroundJobMutationError);
        assert.equal(err.code, "event_invalid_job_type");
        return true;
      },
    );
  });
});

describe("markEventDispatchFailed", () => {
  test("calls mark_event_dispatch_failed with the exact snake_case params", async () => {
    const client = fakeClient({ data: { ...VALID_EVENT_ROW, dispatch_status: "failed", error: "downstream unavailable" }, error: null });
    const event = await markEventDispatchFailed(client, { eventId: EVENT_ID, error: "downstream unavailable", actorAuthUserId: ACTOR_ID, actorLabel: "outbox-drain" });

    assert.deepEqual(client.calls[0]?.args, { p_event_id: EVENT_ID, p_error: "downstream unavailable", p_actor_auth_user_id: ACTOR_ID, p_actor_label: "outbox-drain" });
    assert.equal(event.dispatchStatus, "failed");
  });
});
