import { test, describe } from "node:test";
import assert from "node:assert/strict";
import { createServer, type Server } from "node:http";
import { processNotificationDeliveryJob, type ProcessNotificationDeliveryJobRpcClient } from "./process-notification-delivery-job.server.ts";
import type { ImportExportJob } from "../../server/contracts/import-export/import-export.ts";

// These tests deliberately dispatch to a real local loopback server -- the
// production SSRF guard (../webhooks/ssrf-guard.server.ts) would correctly
// REFUSE any loopback address, so every test that needs a live HTTP call
// injects this permissive stub instead of the real, DNS-resolving checker.
const ALLOW_ALL_URLS = async () => ({ safe: true, reason: null });

const JOB_ID = "223e4567-e89b-12d3-a456-426614174000";
const NOTIFICATION_ID = "323e4567-e89b-12d3-a456-426614174000";
const TENANT_ID = "423e4567-e89b-12d3-a456-426614174000";
const CONNECTION_ID = "523e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "623e4567-e89b-12d3-a456-426614174000";

function baseJob(overrides: Partial<ImportExportJob> = {}): ImportExportJob {
  return {
    jobId: JOB_ID,
    tenantId: TENANT_ID,
    jobType: "notification_batch",
    status: "in_progress",
    priority: 0,
    payload: { notification_id: NOTIFICATION_ID },
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
    idempotencyKey: "notification-delivery:" + NOTIFICATION_ID,
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

function mockClient(apiUrl: string | null, dispatchOverrides: Record<string, unknown> = {}, recorded: RecordedCalls = { deliveryAttempts: [], completedJobs: [], failedJobs: [] }): ProcessNotificationDeliveryJobRpcClient {
  return {
    rpc: async (fn: string, args: Record<string, unknown>) => {
      if (fn === "get_notification_dispatch_info") {
        return {
          data: {
            notification_id: NOTIFICATION_ID,
            tenant_id: TENANT_ID,
            status: "queued",
            effective_channel: "email",
            subject: "Test subject",
            body: "Test body",
            recipient_email: "recipient@example.test",
            recipient_contact_address: null,
            connection_id: CONNECTION_ID,
            connection_status: "active",
            connection_config: apiUrl ? { apiUrl } : {},
            ...dispatchOverrides,
          },
          error: null,
        };
      }
      if (fn === "get_notification_provider_credential") {
        return { data: "test-credential-value", error: null };
      }
      if (fn === "record_notification_delivery_attempt") {
        recorded.deliveryAttempts.push(args);
        return {
          data: {
            id: "923e4567-e89b-12d3-a456-426614174000", notification_id: NOTIFICATION_ID, attempt_number: 1,
            status: args.p_status, error_message: args.p_error_message, attempted_at: "2026-08-21T00:00:00.000Z",
            provider_unit_cost_amount: args.p_provider_unit_cost_amount ?? null, currency: args.p_currency ?? null, billed_amount: null,
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
  } as unknown as ProcessNotificationDeliveryJobRpcClient;
}

function baseJobRow(): Record<string, unknown> {
  return {
    job_id: JOB_ID, tenant_id: TENANT_ID, job_type: "notification_batch", status: "in_progress", priority: 0,
    payload: { notification_id: NOTIFICATION_ID }, attempts: 0, max_attempts: 5, locked_by: "test-worker", locked_until: null,
    error: null, result_url: null, created_by: null, created_at: "2026-08-21T00:00:00.000Z", completed_at: null,
    requested_by_auth_user_id: ACTOR_ID, idempotency_key: "notification-delivery:" + NOTIFICATION_ID,
    import_export_schema_code: null, source_file_id: null, result_file_id: null, total_rows: null,
    processed_rows: 0, valid_row_count: 0, invalid_row_count: 0, cancel_reason: null, updated_at: "2026-08-21T00:00:00.000Z",
  };
}

async function startServer(handler: (req: import("node:http").IncomingMessage, res: import("node:http").ServerResponse) => void): Promise<{ server: Server; url: string }> {
  const server = createServer(handler);
  await new Promise<void>((resolve) => server.listen(0, "127.0.0.1", resolve));
  const { port } = server.address() as { port: number };
  return { server, url: `http://127.0.0.1:${port}/send` };
}

describe("processNotificationDeliveryJob", () => {
  test("a real 2xx email-provider response is recorded as success with a real placeholder cost, and completes the job", async () => {
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
      const outcome = await processNotificationDeliveryJob(client, baseJob(), "test-worker", "test-worker", ALLOW_ALL_URLS);

      assert.equal(outcome.outcome, "delivered");
      assert.equal(recorded.deliveryAttempts.length, 1);
      assert.equal(recorded.deliveryAttempts[0]?.p_status, "success");
      assert.ok((recorded.deliveryAttempts[0]?.p_provider_unit_cost_amount as number) > 0);
      assert.equal(recorded.deliveryAttempts[0]?.p_currency, "USD");
      assert.equal(recorded.completedJobs.length, 1);
      assert.equal(recorded.failedJobs.length, 0);
      assert.equal(received.length, 1);
      assert.equal(received[0]?.headers["authorization"], "Bearer test-credential-value");
      assert.deepEqual(JSON.parse(received[0]!.body), { to: "recipient@example.test", subject: "Test subject", body: "Test body" });
    } finally {
      server.close();
    }
  });

  test("a real non-2xx WhatsApp-provider response is recorded as failed and reported to app.jobs", async () => {
    const { server, url } = await startServer((_req, res) => {
      res.writeHead(503);
      res.end("provider down");
    });
    try {
      const recorded: RecordedCalls = { deliveryAttempts: [], completedJobs: [], failedJobs: [] };
      const client = mockClient(url, { effective_channel: "whatsapp", recipient_email: null, recipient_contact_address: "+15551234567" }, recorded);
      const outcome = await processNotificationDeliveryJob(client, baseJob(), "test-worker", "test-worker", ALLOW_ALL_URLS);

      assert.equal(outcome.outcome, "failed");
      assert.match(outcome.errorMessage ?? "", /HTTP 503/);
      assert.equal(recorded.deliveryAttempts[0]?.p_status, "failed");
      assert.equal(recorded.failedJobs.length, 1);
      assert.equal(recorded.completedJobs.length, 0);
    } finally {
      server.close();
    }
  });

  test("a real network-level failure (connection refused) is classified as a failure, not an uncaught throw", async () => {
    const recorded: RecordedCalls = { deliveryAttempts: [], completedJobs: [], failedJobs: [] };
    const client = mockClient("http://127.0.0.1:1/unreachable", { effective_channel: "sms", recipient_email: null, recipient_contact_address: "+15551234567" }, recorded);
    const outcome = await processNotificationDeliveryJob(client, baseJob(), "test-worker", "test-worker", ALLOW_ALL_URLS);

    assert.equal(outcome.outcome, "failed");
    assert.ok(outcome.errorMessage);
    assert.equal(recorded.failedJobs.length, 1);
  });

  test("a notification already in a terminal state (sent) completes the job without a live HTTP call", async () => {
    let called = false;
    const { server, url } = await startServer((_req, res) => {
      called = true;
      res.writeHead(200);
      res.end();
    });
    try {
      const recorded: RecordedCalls = { deliveryAttempts: [], completedJobs: [], failedJobs: [] };
      const client = mockClient(url, { status: "sent" }, recorded);
      const outcome = await processNotificationDeliveryJob(client, baseJob(), "test-worker", "test-worker", ALLOW_ALL_URLS);

      assert.equal(outcome.outcome, "already_terminal");
      assert.equal(called, false);
      assert.equal(recorded.completedJobs.length, 1);
      assert.equal(recorded.deliveryAttempts.length, 0);
    } finally {
      server.close();
    }
  });

  test("no recipient email on file fails without attempting a live HTTP call", async () => {
    let called = false;
    const { server, url } = await startServer((_req, res) => {
      called = true;
      res.writeHead(200);
      res.end();
    });
    try {
      const recorded: RecordedCalls = { deliveryAttempts: [], completedJobs: [], failedJobs: [] };
      const client = mockClient(url, { recipient_email: null }, recorded);
      const outcome = await processNotificationDeliveryJob(client, baseJob(), "test-worker", "test-worker", ALLOW_ALL_URLS);

      assert.equal(outcome.outcome, "failed");
      assert.match(outcome.errorMessage ?? "", /email address/);
      assert.equal(called, false);
      assert.equal(recorded.failedJobs.length, 1);
    } finally {
      server.close();
    }
  });

  test("no active provider connection fails without attempting a live HTTP call", async () => {
    const recorded: RecordedCalls = { deliveryAttempts: [], completedJobs: [], failedJobs: [] };
    const client = mockClient(null, { connection_id: null, connection_status: null }, recorded);
    const outcome = await processNotificationDeliveryJob(client, baseJob(), "test-worker", "test-worker", ALLOW_ALL_URLS);

    assert.equal(outcome.outcome, "failed");
    assert.match(outcome.errorMessage ?? "", /no active email provider connection/);
    assert.equal(recorded.failedJobs.length, 1);
  });

  test("the REAL (non-injected) SSRF guard refuses a literal private-IP provider apiUrl without attempting a live HTTP call", async () => {
    const recorded: RecordedCalls = { deliveryAttempts: [], completedJobs: [], failedJobs: [] };
    const client = mockClient("https://169.254.169.254/latest/meta-data/", {}, recorded);
    const outcome = await processNotificationDeliveryJob(client, baseJob(), "test-worker", "test-worker");

    assert.equal(outcome.outcome, "failed");
    assert.match(outcome.errorMessage ?? "", /refusing to dispatch/);
    assert.equal(recorded.failedJobs.length, 1);
  });

  test("a job with no requested_by_auth_user_id throws -- a notification_batch job always carries a real actor", async () => {
    const client = mockClient(null);
    await assert.rejects(() => processNotificationDeliveryJob(client, baseJob({ requestedByAuthUserId: null }), "test-worker", "test-worker"), /requested_by_auth_user_id/);
  });

  test("a job payload missing notification_id fails the job without a dispatch-info lookup", async () => {
    const recorded: RecordedCalls = { deliveryAttempts: [], completedJobs: [], failedJobs: [] };
    const client = mockClient(null, {}, recorded);
    const outcome = await processNotificationDeliveryJob(client, baseJob({ payload: {} }), "test-worker", "test-worker");

    assert.equal(outcome.outcome, "failed");
    assert.match(outcome.errorMessage ?? "", /notification_id/);
    assert.equal(recorded.failedJobs.length, 1);
  });
});
