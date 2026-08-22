import { test, describe } from "node:test";
import assert from "node:assert/strict";
import { createServer, type Server } from "node:http";
import { processFinanceBankFeedSyncJob, type ProcessFinanceBankFeedSyncJobRpcClient } from "./process-finance-bank-feed-sync-job.server.ts";
import type { ImportExportJob } from "../../server/contracts/import-export/import-export.ts";

const ALLOW_ALL_URLS = async () => ({ safe: true, reason: null });

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const CONNECTION_ID = "323e4567-e89b-12d3-a456-426614174000";
const BANK_ACCOUNT_ID = "323e4567-e89b-12d3-a456-426614174001";
const ACTOR_ID = "423e4567-e89b-12d3-a456-426614174000";
const JOB_ID = "523e4567-e89b-12d3-a456-426614174000";

function jobRow(): ImportExportJob {
  return {
    jobId: JOB_ID, tenantId: TENANT_ID, jobType: "finance_bank_feed_sync", status: "in_progress", priority: 0,
    payload: { connection_id: CONNECTION_ID, bank_account_id: BANK_ACCOUNT_ID }, attempts: 0, maxAttempts: 3, lockedBy: "test-worker", lockedUntil: null,
    error: null, resultUrl: null, createdBy: null, createdAt: "2026-08-21T00:00:00.000Z", completedAt: null,
    requestedByAuthUserId: ACTOR_ID, idempotencyKey: "finance-bank-feed-sync:" + BANK_ACCOUNT_ID,
    importExportSchemaCode: null, sourceFileId: null, resultFileId: null, totalRows: null,
    processedRows: 0, validRowCount: 0, invalidRowCount: 0, cancelReason: null, updatedAt: "2026-08-21T00:00:00.000Z",
  } as ImportExportJob;
}

function jobRowSnakeCase(): Record<string, unknown> {
  return {
    job_id: JOB_ID, tenant_id: TENANT_ID, job_type: "finance_bank_feed_sync", status: "in_progress", priority: 0,
    payload: { connection_id: CONNECTION_ID, bank_account_id: BANK_ACCOUNT_ID }, attempts: 0, max_attempts: 3, locked_by: "test-worker", locked_until: null,
    error: null, result_url: null, created_by: null, created_at: "2026-08-21T00:00:00.000Z", completed_at: null,
    requested_by_auth_user_id: ACTOR_ID, idempotency_key: "finance-bank-feed-sync:" + BANK_ACCOUNT_ID,
    import_export_schema_code: null, source_file_id: null, result_file_id: null, total_rows: null,
    processed_rows: 0, valid_row_count: 0, invalid_row_count: 0, cancel_reason: null, updated_at: "2026-08-21T00:00:00.000Z",
  };
}

interface RecordedCalls {
  jobFailures: Record<string, unknown>[];
}

function mockClient(pollUrl: string | null, recorded: RecordedCalls = { jobFailures: [] }, credential: string | null = "test-credential-value"): ProcessFinanceBankFeedSyncJobRpcClient {
  return {
    rpc: async (fn: string, args: Record<string, unknown>) => {
      if (fn === "get_finance_provider_connection_for_sync") {
        return { data: { tenant_id: TENANT_ID, adapter_code: "bank_feed_api", connection_status: "active", connection_config: pollUrl ? { pollUrl } : {} }, error: null };
      }
      if (fn === "get_finance_provider_credential") {
        return { data: credential, error: null };
      }
      if (fn === "import_finance_bank_statement") {
        return {
          data: {
            id: "623e4567-e89b-12d3-a456-426614174000", tenant_id: TENANT_ID, bank_account_id: BANK_ACCOUNT_ID,
            source_reference: args.p_source_reference, line_count: Array.isArray(args.p_lines) ? args.p_lines.length : 0,
            imported_by: "test", imported_at: "2026-08-21T00:00:00.000Z",
          },
          error: null,
        };
      }
      if (fn === "record_job_failure") {
        recorded.jobFailures.push(args);
        return { data: jobRowSnakeCase(), error: null };
      }
      if (fn === "complete_job") {
        return { data: jobRowSnakeCase(), error: null };
      }
      throw new Error(`unexpected rpc call: ${fn}`);
    },
  } as unknown as ProcessFinanceBankFeedSyncJobRpcClient;
}

async function startServer(handler: (req: import("node:http").IncomingMessage, res: import("node:http").ServerResponse) => void): Promise<{ server: Server; url: string }> {
  const server = createServer(handler);
  await new Promise<void>((resolve) => server.listen(0, "127.0.0.1", resolve));
  const { port } = server.address() as { port: number };
  return { server, url: `http://127.0.0.1:${port}/poll` };
}

describe("processFinanceBankFeedSyncJob", () => {
  test("a real 2xx provider response with valid lines imports the batch and completes the job", async () => {
    const { server, url } = await startServer((_req, res) => {
      res.writeHead(200, { "content-type": "application/json" });
      res.end(JSON.stringify({ sourceReference: "provider-batch-001", lines: [{ transactionDate: "2026-08-01", direction: "credit", amount: 100, reference: "REF-1", description: "test" }] }));
    });
    try {
      const client = mockClient(url);
      const result = await processFinanceBankFeedSyncJob(client, jobRow(), "test-worker", "test-worker", ALLOW_ALL_URLS);

      assert.equal(result.outcome, "synced");
      assert.equal(result.lineCount, 1);
    } finally {
      server.close();
    }
  });

  test("a real non-2xx provider response fails the job cleanly", async () => {
    const { server, url } = await startServer((_req, res) => {
      res.writeHead(503);
      res.end("provider down");
    });
    try {
      const recorded: RecordedCalls = { jobFailures: [] };
      const client = mockClient(url, recorded);
      const result = await processFinanceBankFeedSyncJob(client, jobRow(), "test-worker", "test-worker", ALLOW_ALL_URLS);

      assert.equal(result.outcome, "failed");
      assert.match(result.errorMessage ?? "", /HTTP 503/);
      assert.equal(recorded.jobFailures.length, 1);
    } finally {
      server.close();
    }
  });

  test("a response missing sourceReference/lines fails cleanly without calling import_finance_bank_statement", async () => {
    const { server, url } = await startServer((_req, res) => {
      res.writeHead(200, { "content-type": "application/json" });
      res.end(JSON.stringify({ lines: [] }));
    });
    try {
      const client = mockClient(url);
      const result = await processFinanceBankFeedSyncJob(client, jobRow(), "test-worker", "test-worker", ALLOW_ALL_URLS);

      assert.equal(result.outcome, "failed");
      assert.match(result.errorMessage ?? "", /sourceReference/);
    } finally {
      server.close();
    }
  });

  test("no active connection fails without attempting a live HTTP call", async () => {
    let called = false;
    const { server, url } = await startServer((_req, res) => {
      called = true;
      res.writeHead(200);
      res.end();
    });
    try {
      const client: ProcessFinanceBankFeedSyncJobRpcClient = {
        rpc: async (fn: string, args: Record<string, unknown>) => {
          if (fn === "get_finance_provider_connection_for_sync") {
            return { data: { tenant_id: TENANT_ID, adapter_code: "bank_feed_api", connection_status: "disabled", connection_config: { pollUrl: url } }, error: null };
          }
          if (fn === "record_job_failure") {
            return { data: jobRowSnakeCase(), error: null };
          }
          throw new Error(`unexpected rpc call: ${fn}, args=${JSON.stringify(args)}`);
        },
      } as unknown as ProcessFinanceBankFeedSyncJobRpcClient;
      const result = await processFinanceBankFeedSyncJob(client, jobRow(), "test-worker", "test-worker", ALLOW_ALL_URLS);

      assert.equal(result.outcome, "failed");
      assert.match(result.errorMessage ?? "", /no active bank_feed_api connection/);
      assert.equal(called, false);
    } finally {
      server.close();
    }
  });

  test("the REAL (non-injected) SSRF guard refuses a literal private-IP provider pollUrl without attempting a live HTTP call", async () => {
    const client = mockClient("https://169.254.169.254/latest/meta-data/");
    const result = await processFinanceBankFeedSyncJob(client, jobRow(), "test-worker", "test-worker");

    assert.equal(result.outcome, "failed");
    assert.match(result.errorMessage ?? "", /refusing to poll/);
  });

  test("throws for a malformed job payload this repository's own trigger never produces", async () => {
    const client = mockClient("http://127.0.0.1:1/unreachable");
    const badJob = jobRow();
    (badJob as unknown as { requestedByAuthUserId: string | null }).requestedByAuthUserId = null;
    await assert.rejects(() => processFinanceBankFeedSyncJob(client, badJob, "test-worker", "test-worker", ALLOW_ALL_URLS), /requested_by_auth_user_id/);
  });
});
