/**
 * The real external accounting/HR sync worker's own runnable entrypoint
 * (IAE-018, Prompt 346). Polls app.claim_next_job for external_sync jobs
 * and dispatches each one to
 * ../../lib/external-integrations/process-external-sync-job.server.ts.
 *
 * NOT a production scheduler -- mirrors ../../scripts/jobs/finance-bank-feed-sync-worker.ts's
 * own disclosed shape exactly. No live cron/daemon/scheduler exists anywhere
 * in this repository for ANY app.jobs job type (ISS-2026-015, a standing,
 * disclosed, accepted repository-wide risk this checkpoint does not newly
 * introduce).
 *
 * CLI: node --experimental-strip-types scripts/jobs/external-sync-worker.ts
 *   [--iterations=N] [--empty-poll-limit=N] [--poll-interval-ms=N] [--worker-id=ID]
 */

import { createSupabaseServiceRoleClient } from "../../lib/supabase/service-role.ts";
import { processExternalSyncJob, type ProcessExternalSyncJobRpcClient } from "../../lib/external-integrations/process-external-sync-job.server.ts";
import { claimNextJob } from "../../server/mutations/background-job.ts";

interface WorkerOptions {
  readonly iterations: number;
  readonly emptyPollLimit: number;
  readonly pollIntervalMs: number;
  readonly workerId: string;
}

function parseArgs(argv: readonly string[]): WorkerOptions {
  const flags = new Map<string, string>();
  for (const arg of argv) {
    const match = /^--([a-z-]+)=(.+)$/.exec(arg);
    if (match) {
      flags.set(match[1]!, match[2]!);
    }
  }
  return {
    iterations: Number(flags.get("iterations") ?? "100"),
    emptyPollLimit: Number(flags.get("empty-poll-limit") ?? "5"),
    pollIntervalMs: Number(flags.get("poll-interval-ms") ?? "1000"),
    workerId: flags.get("worker-id") ?? `external-sync-worker-${process.pid}`,
  };
}

function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

/** One bounded run: claim up to `options.iterations` jobs, stopping early after `options.emptyPollLimit` consecutive empty polls. Returns counts for the caller/CLI to report. */
export async function runExternalSyncWorker(client: ProcessExternalSyncJobRpcClient, options: WorkerOptions): Promise<{ claimed: number; synced: number; failed: number; recordedRecords: number; skippedRecords: number; emptyPolls: number }> {
  let claimed = 0;
  let synced = 0;
  let failed = 0;
  let recordedRecords = 0;
  let skippedRecords = 0;
  let consecutiveEmptyPolls = 0;

  for (let i = 0; i < options.iterations; i++) {
    const job = await claimNextJob(client, { workerId: options.workerId, jobTypes: ["external_sync"], leaseDurationSeconds: 300 });
    if (!job) {
      consecutiveEmptyPolls++;
      if (consecutiveEmptyPolls >= options.emptyPollLimit) {
        break;
      }
      await sleep(options.pollIntervalMs);
      continue;
    }

    consecutiveEmptyPolls = 0;
    claimed++;
    const result = await processExternalSyncJob(client, job, options.workerId, options.workerId);
    if (result.outcome === "synced") synced++;
    else failed++;
    recordedRecords += result.recordedCount;
    skippedRecords += result.skippedCount;
  }

  return { claimed, synced, failed, recordedRecords, skippedRecords, emptyPolls: consecutiveEmptyPolls };
}

async function main(): Promise<void> {
  const options = parseArgs(process.argv.slice(2));
  const client = createSupabaseServiceRoleClient() as unknown as ProcessExternalSyncJobRpcClient;
  const result = await runExternalSyncWorker(client, options);
  console.log(`external-sync-worker[${options.workerId}]: claimed=${result.claimed} synced=${result.synced} failed=${result.failed} recorded_records=${result.recordedRecords} skipped_records=${result.skippedRecords}`);
}

if (import.meta.url === `file://${process.argv[1]}`) {
  main().catch((error) => {
    console.error(error);
    process.exit(1);
  });
}
