/**
 * The real webhook delivery worker's own runnable entrypoint (IAE-012,
 * Prompt 340). Polls app.claim_next_job for webhook_retry jobs and dispatches
 * each one to ../../lib/webhooks/process-webhook-delivery-job.server.ts.
 *
 * NOT a production scheduler -- mirrors scripts/load-tests/job-poll-worker.sh's
 * own disclosed shape exactly. No live cron/daemon/scheduler exists anywhere
 * in this repository for ANY app.jobs job type (ISS-2026-015, a standing,
 * disclosed, accepted repository-wide risk this checkpoint does not newly
 * introduce and does not purport to close). This script is real, correct,
 * bounded-iteration dispatch logic -- ready to be wired to a real scheduler
 * whenever that standing gap is addressed; running it manually or via an
 * external cron IS a genuine way to process the queue today, just not an
 * automatic one.
 *
 * CLI: node --experimental-strip-types scripts/jobs/webhook-delivery-worker.ts
 *   [--iterations=N] [--empty-poll-limit=N] [--poll-interval-ms=N] [--worker-id=ID]
 */

import { createSupabaseServiceRoleClient } from "../../lib/supabase/service-role.ts";
import { processWebhookDeliveryJob, type ProcessWebhookDeliveryJobRpcClient } from "../../lib/webhooks/process-webhook-delivery-job.server.ts";
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
    workerId: flags.get("worker-id") ?? `webhook-worker-${process.pid}`,
  };
}

function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

/** One bounded run: claim up to `options.iterations` jobs, stopping early after `options.emptyPollLimit` consecutive empty polls. Returns counts for the caller/CLI to report. */
export async function runWebhookDeliveryWorker(client: ProcessWebhookDeliveryJobRpcClient, options: WorkerOptions): Promise<{ claimed: number; delivered: number; alreadyTerminal: number; failed: number; emptyPolls: number }> {
  let claimed = 0;
  let delivered = 0;
  let alreadyTerminal = 0;
  let failed = 0;
  let consecutiveEmptyPolls = 0;

  for (let i = 0; i < options.iterations; i++) {
    const job = await claimNextJob(client, { workerId: options.workerId, jobTypes: ["webhook_retry"], leaseDurationSeconds: 300 });
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
    const result = await processWebhookDeliveryJob(client, job, options.workerId, options.workerId);
    if (result.outcome === "delivered") delivered++;
    else if (result.outcome === "already_terminal") alreadyTerminal++;
    else failed++;
  }

  return { claimed, delivered, alreadyTerminal, failed, emptyPolls: consecutiveEmptyPolls };
}

async function main(): Promise<void> {
  const options = parseArgs(process.argv.slice(2));
  const client = createSupabaseServiceRoleClient() as unknown as ProcessWebhookDeliveryJobRpcClient;
  const result = await runWebhookDeliveryWorker(client, options);
  console.log(`webhook-delivery-worker[${options.workerId}]: claimed=${result.claimed} delivered=${result.delivered} already_terminal=${result.alreadyTerminal} failed=${result.failed}`);
}

if (import.meta.url === `file://${process.argv[1]}`) {
  main().catch((error) => {
    console.error(error);
    process.exit(1);
  });
}
