/**
 * The real carrier/port/airport/customs poll-sync worker's own runnable
 * entrypoint (IAE-016, Prompt 344). Polls app.claim_next_job for
 * logistics_partner_sync jobs and dispatches each one to
 * ../../lib/logistics-partners/process-logistics-partner-sync-job.server.ts.
 *
 * NOT a production scheduler -- mirrors ../../scripts/jobs/notification-delivery-worker.ts's
 * own disclosed shape exactly. No live cron/daemon/scheduler exists anywhere
 * in this repository for ANY app.jobs job type (ISS-2026-015, a standing,
 * disclosed, accepted repository-wide risk this checkpoint does not newly
 * introduce).
 *
 * CLI: node --experimental-strip-types scripts/jobs/logistics-partner-sync-worker.ts
 *   [--iterations=N] [--empty-poll-limit=N] [--poll-interval-ms=N] [--worker-id=ID]
 */

import { createSupabaseServiceRoleClient } from "../../lib/supabase/service-role.ts";
import { processLogisticsPartnerSyncJob, type ProcessLogisticsPartnerSyncJobRpcClient } from "../../lib/logistics-partners/process-logistics-partner-sync-job.server.ts";
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
    workerId: flags.get("worker-id") ?? `logistics-partner-sync-worker-${process.pid}`,
  };
}

function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

/** One bounded run: claim up to `options.iterations` jobs, stopping early after `options.emptyPollLimit` consecutive empty polls. Returns counts for the caller/CLI to report. */
export async function runLogisticsPartnerSyncWorker(client: ProcessLogisticsPartnerSyncJobRpcClient, options: WorkerOptions): Promise<{ claimed: number; synced: number; failed: number; recordedEvents: number; skippedEvents: number; emptyPolls: number }> {
  let claimed = 0;
  let synced = 0;
  let failed = 0;
  let recordedEvents = 0;
  let skippedEvents = 0;
  let consecutiveEmptyPolls = 0;

  for (let i = 0; i < options.iterations; i++) {
    const job = await claimNextJob(client, { workerId: options.workerId, jobTypes: ["logistics_partner_sync"], leaseDurationSeconds: 300 });
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
    const result = await processLogisticsPartnerSyncJob(client, job, options.workerId, options.workerId);
    if (result.outcome === "synced") synced++;
    else failed++;
    recordedEvents += result.recordedCount;
    skippedEvents += result.skippedCount;
  }

  return { claimed, synced, failed, recordedEvents, skippedEvents, emptyPolls: consecutiveEmptyPolls };
}

async function main(): Promise<void> {
  const options = parseArgs(process.argv.slice(2));
  const client = createSupabaseServiceRoleClient() as unknown as ProcessLogisticsPartnerSyncJobRpcClient;
  const result = await runLogisticsPartnerSyncWorker(client, options);
  console.log(`logistics-partner-sync-worker[${options.workerId}]: claimed=${result.claimed} synced=${result.synced} failed=${result.failed} recorded_events=${result.recordedEvents} skipped_events=${result.skippedEvents}`);
}

if (import.meta.url === `file://${process.argv[1]}`) {
  main().catch((error) => {
    console.error(error);
    process.exit(1);
  });
}
