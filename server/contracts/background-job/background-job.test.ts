import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  parseEventLog,
  GenericJobTypeSchema,
  EnqueueJobInputSchema,
  ClaimNextJobInputSchema,
  DispatchEventAsJobInputSchema,
} from "./background-job.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const EVENT_ID = "323e4567-e89b-12d3-a456-426614174000";
const JOB_ID = "423e4567-e89b-12d3-a456-426614174000";
const AUTH_USER_ID = "523e4567-e89b-12d3-a456-426614174000";

describe("GenericJobTypeSchema", () => {
  test("accepts the eight generic job_type codes", () => {
    for (const jobType of [
      "report_generation",
      "notification_batch",
      "webhook_retry",
      "document_generation",
      "dashboard_refresh",
      "loyalty_expiration",
      "recurring_billing",
      "integration_sync",
    ]) {
      assert.equal(GenericJobTypeSchema.parse(jobType), jobType);
    }
  });

  test("rejects import/export -- those keep their own dedicated create_import_export_job entrypoint", () => {
    assert.throws(() => GenericJobTypeSchema.parse("import"));
    assert.throws(() => GenericJobTypeSchema.parse("export"));
  });
});

describe("parseEventLog", () => {
  test("maps a raw snake_case row to the camelCase contract shape", () => {
    const event = parseEventLog({
      id: EVENT_ID,
      tenant_id: TENANT_ID,
      event_type: "shipment.dispatched",
      resource_type: "shipment",
      resource_id: JOB_ID,
      payload: { carrier: "DHL" },
      dispatch_status: "pending",
      related_job_id: null,
      occurred_at: "2026-07-19T00:00:00.000Z",
      dispatched_at: null,
      error: null,
      created_by: "requester",
    });
    assert.equal(event.eventType, "shipment.dispatched");
    assert.equal(event.dispatchStatus, "pending");
    assert.equal(event.relatedJobId, null);
  });
});

describe("EnqueueJobInputSchema", () => {
  test("defaults payload/priority/idempotencyKey/maxAttempts", () => {
    const parsed = EnqueueJobInputSchema.parse({
      tenantId: TENANT_ID,
      jobType: "notification_batch",
      actorAuthUserId: AUTH_USER_ID,
      actorLabel: "requester",
    });
    assert.deepEqual(parsed.payload, {});
    assert.equal(parsed.priority, 0);
    assert.equal(parsed.idempotencyKey, null);
    assert.equal(parsed.maxAttempts, 3);
  });

  test("rejects import/export -- must use the dedicated import-export entrypoint instead", () => {
    assert.throws(() =>
      EnqueueJobInputSchema.parse({
        tenantId: TENANT_ID,
        jobType: "import",
        actorAuthUserId: AUTH_USER_ID,
        actorLabel: "requester",
      }),
    );
  });
});

describe("ClaimNextJobInputSchema", () => {
  test("defaults leaseDurationSeconds to 300 and requires at least one jobType", () => {
    const parsed = ClaimNextJobInputSchema.parse({ workerId: "worker-1", jobTypes: ["notification_batch"] });
    assert.equal(parsed.leaseDurationSeconds, 300);

    assert.throws(() => ClaimNextJobInputSchema.parse({ workerId: "worker-1", jobTypes: [] }));
  });
});

describe("DispatchEventAsJobInputSchema", () => {
  test("defaults priority/idempotencyKey/maxAttempts and requires a generic job_type", () => {
    const parsed = DispatchEventAsJobInputSchema.parse({ eventId: EVENT_ID, jobType: "webhook_retry", actorLabel: "outbox-drain" });
    assert.equal(parsed.priority, 0);
    assert.equal(parsed.maxAttempts, 3);

    assert.throws(() => DispatchEventAsJobInputSchema.parse({ eventId: EVENT_ID, jobType: "export", actorLabel: "outbox-drain" }));
  });
});
