import { test, describe } from "node:test";
import assert from "node:assert/strict";
import { runFinanceBankFeedSyncWorker } from "./finance-bank-feed-sync-worker.ts";
import type { ProcessFinanceBankFeedSyncJobRpcClient } from "../../lib/finance-integrations/process-finance-bank-feed-sync-job.server.ts";

const TENANT_ID = "423e4567-e89b-12d3-a456-426614174000";
const CONNECTION_ID = "323e4567-e89b-12d3-a456-426614174000";
const BANK_ACCOUNT_ID = "323e4567-e89b-12d3-a456-426614174001";
const ACTOR_ID = "623e4567-e89b-12d3-a456-426614174000";

function jobRow(jobId: string): Record<string, unknown> {
  return {
    job_id: jobId, tenant_id: TENANT_ID, job_type: "finance_bank_feed_sync", status: "in_progress", priority: 0,
    payload: { connection_id: CONNECTION_ID, bank_account_id: BANK_ACCOUNT_ID }, attempts: 0, max_attempts: 3, locked_by: "test-worker", locked_until: null,
    error: null, result_url: null, created_by: null, created_at: "2026-08-21T00:00:00.000Z", completed_at: null,
    requested_by_auth_user_id: ACTOR_ID, idempotency_key: "finance-bank-feed-sync:" + BANK_ACCOUNT_ID,
    import_export_schema_code: null, source_file_id: null, result_file_id: null, total_rows: null,
    processed_rows: 0, valid_row_count: 0, invalid_row_count: 0, cancel_reason: null, updated_at: "2026-08-21T00:00:00.000Z",
  };
}

describe("runFinanceBankFeedSyncWorker", () => {
  test("stops after emptyPollLimit consecutive empty claims, never looping forever", async () => {
    let claimCalls = 0;
    const client: ProcessFinanceBankFeedSyncJobRpcClient = {
      rpc: async (fn: string) => {
        if (fn === "claim_next_job") {
          claimCalls++;
          return { data: null, error: null };
        }
        throw new Error(`unexpected rpc call: ${fn}`);
      },
    } as unknown as ProcessFinanceBankFeedSyncJobRpcClient;

    const result = await runFinanceBankFeedSyncWorker(client, { iterations: 1000, emptyPollLimit: 3, pollIntervalMs: 1, workerId: "test-worker" });

    assert.equal(result.claimed, 0);
    assert.equal(claimCalls, 3);
  });

  test("processes each claimed job and aggregates outcome counts, stopping at the iteration bound", async () => {
    const jobIds = ["723e4567-e89b-12d3-a456-426614174000", "823e4567-e89b-12d3-a456-426614174000"];
    let remaining = jobIds.length;
    const client: ProcessFinanceBankFeedSyncJobRpcClient = {
      rpc: async (fn: string, args: Record<string, unknown>) => {
        if (fn === "claim_next_job") {
          if (remaining <= 0) return { data: null, error: null };
          remaining--;
          return { data: jobRow(jobIds[remaining]!), error: null };
        }
        if (fn === "get_finance_provider_connection_for_sync") {
          return { data: { tenant_id: TENANT_ID, adapter_code: "bank_feed_api", connection_status: "disabled", connection_config: {} }, error: null };
        }
        if (fn === "record_job_failure") {
          return { data: jobRow(args.p_job_id as string), error: null };
        }
        throw new Error(`unexpected rpc call in this test: ${fn}, args=${JSON.stringify(args)}`);
      },
    } as unknown as ProcessFinanceBankFeedSyncJobRpcClient;

    const result = await runFinanceBankFeedSyncWorker(client, { iterations: 5, emptyPollLimit: 2, pollIntervalMs: 1, workerId: "test-worker" });

    assert.equal(result.claimed, 2);
    assert.equal(result.synced, 0);
    assert.equal(result.failed, 2);
  });
});
