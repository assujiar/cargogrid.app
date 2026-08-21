import { test, describe } from "node:test";
import assert from "node:assert/strict";
import { createServer, type Server } from "node:http";
import { processWebhookDeliveryJob, type ProcessWebhookDeliveryJobRpcClient } from "./process-webhook-delivery-job.server.ts";
import type { ImportExportJob } from "../../server/contracts/import-export/import-export.ts";

const JOB_ID = "223e4567-e89b-12d3-a456-426614174000";
const DELIVERY_ID = "323e4567-e89b-12d3-a456-426614174000";
const TENANT_ID = "423e4567-e89b-12d3-a456-426614174000";
const ENDPOINT_ID = "523e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "623e4567-e89b-12d3-a456-426614174000";

function baseJob(overrides: Partial<ImportExportJob> = {}): ImportExportJob {
  return {
    jobId: JOB_ID,
    tenantId: TENANT_ID,
    jobType: "webhook_retry",
    status: "in_progress",
    priority: 0,
    payload: { delivery_id: DELIVERY_ID },
    attempts: 0,
    maxAttempts: 5,
    lockedBy: "test-worker",
    lockedUntil: null,
    error: null,
    resultUrl: null,
    createdBy: null,
    createdAt: "2026-08-21T00:00:00.000Z",
    completedAt: null,
    requestedByAuthUserId: ACTOR_ID,
    idempotencyKey: "webhook-delivery:" + DELIVERY_ID,
    importExportSchemaCode: null,
    sourceFileId: null,
    resultFileId: null,
    totalRows: null,
    processedRows: 0,
    validRowCount: 0,
    invalidRowCount: 0,
    cancelReason: null,
    updatedAt: "2026-08-21T00:00:00.000Z",
    ...overrides,
  };
}

interface RecordedCalls {
  deliveryAttempts: Record<string, unknown>[];
  completedJobs: Record<string, unknown>[];
  failedJobs: Record<string, unknown>[];
}

function mockClient(endpointUrl: string, deliveryOverrides: Record<string, unknown> = {}, recorded: RecordedCalls = { deliveryAttempts: [], completedJobs: [], failedJobs: [] }): ProcessWebhookDeliveryJobRpcClient {
  return {
    rpc: async (fn: string, args: Record<string, unknown>) => {
      if (fn === "get_webhook_delivery_dispatch_info") {
        return {
          data: {
            delivery_id: DELIVERY_ID,
            tenant_id: TENANT_ID,
            status: "pending",
            event_type_code: "webhook.test",
            payload: { hello: "world" },
            webhook_endpoint_id: ENDPOINT_ID,
            endpoint_url: endpointUrl,
            endpoint_status: "active",
            ...deliveryOverrides,
          },
          error: null,
        };
      }
      if (fn === "compute_webhook_signature") {
        return { data: "deadbeefsignature", error: null };
      }
      if (fn === "record_webhook_delivery_attempt") {
        recorded.deliveryAttempts.push(args);
        return {
          data: {
            id: DELIVERY_ID, tenant_id: TENANT_ID, webhook_endpoint_id: ENDPOINT_ID, event_type_code: "webhook.test",
            event_id: "923e4567-e89b-12d3-a456-426614174000", payload: { hello: "world" }, idempotency_key: "webhook-delivery:" + DELIVERY_ID,
            status: args.p_status === "success" ? "delivered" : "pending", attempts: 1, max_attempts: 5, next_attempt_at: null,
            created_at: "2026-08-21T00:00:00.000Z", updated_at: "2026-08-21T00:00:00.000Z",
          },
          error: null,
        };
      }
      if (fn === "complete_job") {
        recorded.completedJobs.push(args);
        return { data: { ...baseJobRow(), status: "completed" }, error: null };
      }
      if (fn === "record_job_failure") {
        recorded.failedJobs.push(args);
        return { data: { ...baseJobRow(), status: "pending" }, error: null };
      }
      throw new Error(`unexpected rpc call: ${fn}`);
    },
  } as unknown as ProcessWebhookDeliveryJobRpcClient;
}

function baseJobRow(): Record<string, unknown> {
  return {
    job_id: JOB_ID, tenant_id: TENANT_ID, job_type: "webhook_retry", status: "in_progress", priority: 0,
    payload: { delivery_id: DELIVERY_ID }, attempts: 0, max_attempts: 5, locked_by: "test-worker", locked_until: null,
    error: null, result_url: null, created_by: null, created_at: "2026-08-21T00:00:00.000Z", completed_at: null,
    requested_by_auth_user_id: ACTOR_ID, idempotency_key: "webhook-delivery:" + DELIVERY_ID,
    import_export_schema_code: null, source_file_id: null, result_file_id: null, total_rows: null,
    processed_rows: 0, valid_row_count: 0, invalid_row_count: 0, cancel_reason: null, updated_at: "2026-08-21T00:00:00.000Z",
  };
}

async function startServer(handler: (req: import("node:http").IncomingMessage, res: import("node:http").ServerResponse) => void): Promise<{ server: Server; url: string }> {
  const server = createServer(handler);
  await new Promise<void>((resolve) => server.listen(0, "127.0.0.1", resolve));
  const { port } = server.address() as { port: number };
  return { server, url: `http://127.0.0.1:${port}/webhook` };
}

describe("processWebhookDeliveryJob", () => {
  test("a real 2xx HTTP response is recorded as success and completes the job", async () => {
    const received: { headers: Record<string, string | string[] | undefined>; body: string }[] = [];
    const { server, url } = await startServer((req, res) => {
      let body = "";
      req.on("data", (chunk) => (body += chunk));
      req.on("end", () => {
        received.push({ headers: req.headers, body });
        res.writeHead(200, { "content-type": "application/json" });
        res.end(JSON.stringify({ ok: true }));
      });
    });
    try {
      const recorded: RecordedCalls = { deliveryAttempts: [], completedJobs: [], failedJobs: [] };
      const client = mockClient(url, {}, recorded);
      const outcome = await processWebhookDeliveryJob(client, baseJob(), "test-worker", "test-worker");

      assert.equal(outcome.outcome, "delivered");
      assert.equal(outcome.httpStatusCode, 200);
      assert.equal(recorded.deliveryAttempts.length, 1);
      assert.equal(recorded.deliveryAttempts[0]?.p_status, "success");
      assert.equal(recorded.completedJobs.length, 1);
      assert.equal(recorded.failedJobs.length, 0);
      assert.equal(received.length, 1);
      assert.equal(received[0]?.headers["x-cargogrid-webhook-signature"], "deadbeefsignature");
      assert.equal(received[0]?.headers["x-cargogrid-webhook-delivery-id"], DELIVERY_ID);
      assert.deepEqual(JSON.parse(received[0]!.body), { hello: "world" });
    } finally {
      server.close();
    }
  });

  test("a real non-2xx HTTP response is recorded as failed and reported to app.jobs", async () => {
    const { server, url } = await startServer((_req, res) => {
      res.writeHead(500);
      res.end("internal error");
    });
    try {
      const recorded: RecordedCalls = { deliveryAttempts: [], completedJobs: [], failedJobs: [] };
      const client = mockClient(url, {}, recorded);
      const outcome = await processWebhookDeliveryJob(client, baseJob(), "test-worker", "test-worker");

      assert.equal(outcome.outcome, "failed");
      assert.equal(outcome.httpStatusCode, 500);
      assert.match(outcome.errorMessage ?? "", /HTTP 500/);
      assert.equal(recorded.deliveryAttempts[0]?.p_status, "failed");
      assert.equal(recorded.failedJobs.length, 1);
      assert.equal(recorded.completedJobs.length, 0);
    } finally {
      server.close();
    }
  });

  test("a real network-level failure (connection refused) is classified as a failure, not an uncaught throw", async () => {
    const recorded: RecordedCalls = { deliveryAttempts: [], completedJobs: [], failedJobs: [] };
    const client = mockClient("http://127.0.0.1:1/unreachable", {}, recorded);
    const outcome = await processWebhookDeliveryJob(client, baseJob(), "test-worker", "test-worker");

    assert.equal(outcome.outcome, "failed");
    assert.equal(outcome.httpStatusCode, null);
    assert.ok(outcome.errorMessage);
    assert.equal(recorded.failedJobs.length, 1);
  });

  test("a delivery already in a terminal state completes the job without a live HTTP call", async () => {
    let called = false;
    const { server, url } = await startServer((_req, res) => {
      called = true;
      res.writeHead(200);
      res.end();
    });
    try {
      const recorded: RecordedCalls = { deliveryAttempts: [], completedJobs: [], failedJobs: [] };
      const client = mockClient(url, { status: "delivered" }, recorded);
      const outcome = await processWebhookDeliveryJob(client, baseJob(), "test-worker", "test-worker");

      assert.equal(outcome.outcome, "already_terminal");
      assert.equal(called, false);
      assert.equal(recorded.completedJobs.length, 1);
      assert.equal(recorded.deliveryAttempts.length, 0);
    } finally {
      server.close();
    }
  });

  test("a disabled endpoint fails without attempting a live HTTP call", async () => {
    let called = false;
    const { server, url } = await startServer((_req, res) => {
      called = true;
      res.writeHead(200);
      res.end();
    });
    try {
      const recorded: RecordedCalls = { deliveryAttempts: [], completedJobs: [], failedJobs: [] };
      const client = mockClient(url, { endpoint_status: "disabled" }, recorded);
      const outcome = await processWebhookDeliveryJob(client, baseJob(), "test-worker", "test-worker");

      assert.equal(outcome.outcome, "failed");
      assert.match(outcome.errorMessage ?? "", /disabled/);
      assert.equal(called, false);
      assert.equal(recorded.failedJobs.length, 1);
    } finally {
      server.close();
    }
  });

  test("a job with no requested_by_auth_user_id throws -- a webhook_retry job always carries a real actor", async () => {
    const client = mockClient("http://127.0.0.1:1/unused");
    await assert.rejects(() => processWebhookDeliveryJob(client, baseJob({ requestedByAuthUserId: null }), "test-worker", "test-worker"), /requested_by_auth_user_id/);
  });

  test("a job payload missing delivery_id fails the job without a dispatch-info lookup", async () => {
    const recorded: RecordedCalls = { deliveryAttempts: [], completedJobs: [], failedJobs: [] };
    const client = mockClient("http://127.0.0.1:1/unused", {}, recorded);
    const outcome = await processWebhookDeliveryJob(client, baseJob({ payload: {} }), "test-worker", "test-worker");

    assert.equal(outcome.outcome, "failed");
    assert.match(outcome.errorMessage ?? "", /delivery_id/);
    assert.equal(recorded.failedJobs.length, 1);
  });
});
