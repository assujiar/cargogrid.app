/**
 * The background worker supervisor — `ISS-2026-015`, and `ISS-2026-070` item 2's remaining half.
 *
 * ## What was actually missing
 *
 * Not the workers. `scripts/jobs/` already held five correct, tested, bounded-run workers for the
 * external-handoff job types, and `app.jobs` already had a complete claim/lease/backoff/
 * dead-letter framework. Each of those five says so in its own header, and says the rest plainly
 * too:
 *
 *   > *"NOT a production scheduler — no live cron/daemon/scheduler exists anywhere in this
 *   > repository for ANY app.jobs job type."*
 *
 * That was the whole gap. Every piece existed and **nothing ran them.** Jobs were enqueued from 31
 * distinct places and sat `pending` forever; `app.run_due_scheduled_tasks` had no caller either,
 * so every tenant-configured schedule was equally inert.
 *
 * This file is the thing that runs. It is one long-lived process that, on each tick:
 *
 *   1. fires every scheduled task whose next run is due (`app.run_due_scheduled_tasks`);
 *   2. claims and executes the job types Postgres can run itself (`app.run_due_jobs`);
 *   3. runs each of the five external-handoff workers for its own job type.
 *
 * ## Why one process rather than six
 *
 * Six scripts a human must remember to start is not a robot, it is a checklist. It also multiplies
 * the operational surface — six sets of credentials, six restart policies, six things to notice
 * have died. One supervisor with per-lane error isolation is a smaller thing to operate and a
 * smaller thing to get wrong.
 *
 * ## What this deliberately does NOT do
 *
 * It holds no authority of its own and makes no decision the database has not already made. Which
 * jobs are claimable, whether a failure retries or dead-letters, how long the backoff runs,
 * whether a schedule's authorizing identity still holds its rights — every one of those is decided
 * in SQL and re-checked on every run. A scheduled task executes as the person who authorized it; a
 * job executes as the person whose action enqueued it. If this supervisor were compromised it
 * could cause work to run *sooner*, never work that nobody was entitled to.
 *
 * It also does not install itself. Pointing a process manager, a container restart policy or a
 * timer at this script stays an operator decision, exactly as `ISS-2026-066` already records for
 * the scheduler half.
 *
 * CLI:
 *   node --experimental-strip-types scripts/jobs/supervisor.ts
 *     [--once] [--interval-ms=N] [--job-limit=N] [--scheduler-limit=N]
 *     [--lease-seconds=N] [--worker-id=ID] [--lanes=a,b,c]
 */

import { createSupabaseServiceRoleClient } from "../../lib/supabase/service-role.ts";
import { runDueJobs, runDueScheduledTasks, type JobRunnerRpcClient } from "../../server/mutations/job-runner.ts";
import { runExternalSyncWorker } from "./external-sync-worker.ts";
import { runFinanceBankFeedSyncWorker } from "./finance-bank-feed-sync-worker.ts";
import { runLogisticsPartnerSyncWorker } from "./logistics-partner-sync-worker.ts";
import { runNotificationDeliveryWorker } from "./notification-delivery-worker.ts";
import { runWebhookDeliveryWorker } from "./webhook-delivery-worker.ts";

export interface SupervisorOptions {
  readonly once: boolean;
  readonly intervalMs: number;
  readonly jobLimit: number;
  readonly schedulerLimit: number;
  readonly leaseSeconds: number;
  readonly workerId: string;
  readonly lanes: readonly string[];
}

/** One lane's result for a single tick. A lane that threw is reported, never allowed to end the run. */
export interface LaneResult {
  readonly lane: string;
  readonly ok: boolean;
  readonly summary: string;
  readonly error?: string;
}

export interface TickResult {
  readonly lanes: readonly LaneResult[];
  /** True when every lane succeeded. A tick with a failing lane still counts as a completed tick. */
  readonly allOk: boolean;
}

export const ALL_LANES = [
  "scheduler",
  "database-jobs",
  "webhook-delivery",
  "notification-delivery",
  "external-sync",
  "logistics-partner-sync",
  "finance-bank-feed-sync",
] as const;

export function parseArgs(argv: readonly string[]): SupervisorOptions {
  const flags = new Map<string, string>();
  let once = false;
  for (const arg of argv) {
    if (arg === "--once") {
      once = true;
      continue;
    }
    const match = /^--([a-z-]+)=(.+)$/.exec(arg);
    if (match) flags.set(match[1]!, match[2]!);
  }
  const rawLanes = flags.get("lanes");
  const lanes = rawLanes ? rawLanes.split(",").map((l) => l.trim()).filter(Boolean) : [...ALL_LANES];
  const unknown = lanes.filter((l) => !(ALL_LANES as readonly string[]).includes(l));
  if (unknown.length > 0) {
    // Fail loudly rather than silently running fewer lanes than asked for: a typo in `--lanes`
    // that quietly disabled webhook delivery would be invisible until deliveries stopped.
    throw new Error(`unknown lane(s): ${unknown.join(", ")} — valid lanes are ${ALL_LANES.join(", ")}`);
  }
  return {
    once,
    intervalMs: Number(flags.get("interval-ms") ?? "30000"),
    jobLimit: Number(flags.get("job-limit") ?? "25"),
    schedulerLimit: Number(flags.get("scheduler-limit") ?? "50"),
    leaseSeconds: Number(flags.get("lease-seconds") ?? "300"),
    workerId: flags.get("worker-id") ?? `supervisor-${process.pid}`,
    lanes,
  };
}

function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function describeError(error: unknown): string {
  return error instanceof Error ? error.message : String(error);
}

/**
 * Run every enabled lane once. Each lane is isolated: a lane that throws is recorded as a failed
 * `LaneResult` and the remaining lanes still run. That isolation is the point — a webhook endpoint
 * being unreachable must not stop payroll sweeps from firing.
 */
export async function runTick(
  // Typed loosely on purpose: the five external workers each declare their own narrow RPC client
  // interface, and the real Supabase client satisfies all of them. Naming a union here would
  // couple the supervisor to five module-private types for no gain.
  client: JobRunnerRpcClient & Record<string, unknown>,
  options: SupervisorOptions,
  now: () => string,
): Promise<TickResult> {
  const enabled = (lane: string) => options.lanes.includes(lane);
  const results: LaneResult[] = [];

  const lane = async (name: string, run: () => Promise<string>): Promise<void> => {
    if (!enabled(name)) return;
    try {
      results.push({ lane: name, ok: true, summary: await run() });
    } catch (error) {
      results.push({ lane: name, ok: false, summary: "lane failed", error: describeError(error) });
    }
  };

  await lane("scheduler", async () => {
    const fired = await runDueScheduledTasks(client, { now: now(), limit: options.schedulerLimit });
    const failed = fired.filter((f) => f.status !== "success").length;
    return `${fired.length} task(s) fired, ${failed} non-success`;
  });

  await lane("database-jobs", async () => {
    const outcomes = await runDueJobs(client, {
      workerId: options.workerId,
      limit: options.jobLimit,
      leaseSeconds: options.leaseSeconds,
    });
    const failed = outcomes.filter((o) => o.outcome === "failed");
    // Name the failing job types rather than only counting them: "3 failed" sends an operator
    // digging through the jobs table, "3 failed (loyalty_expiry_sweep)" does not.
    const detail = failed.length > 0 ? ` (${[...new Set(failed.map((f) => f.jobType))].join(", ")})` : "";
    return `${outcomes.length} job(s) attempted, ${failed.length} failed${detail}`;
  });

  const externalOptions = {
    iterations: options.jobLimit,
    emptyPollLimit: 1,
    pollIntervalMs: 0,
    workerId: options.workerId,
  };

  await lane("webhook-delivery", async () => {
    const r = await runWebhookDeliveryWorker(client as never, externalOptions);
    return `${r.claimed} claimed, ${r.delivered} delivered, ${r.failed} failed`;
  });
  await lane("notification-delivery", async () => {
    const r = await runNotificationDeliveryWorker(client as never, externalOptions);
    return `${r.claimed} claimed, ${r.delivered} delivered, ${r.failed} failed`;
  });
  await lane("external-sync", async () => {
    const r = await runExternalSyncWorker(client as never, externalOptions);
    return `${r.claimed} claimed, ${r.synced} synced, ${r.failed} failed`;
  });
  await lane("logistics-partner-sync", async () => {
    const r = await runLogisticsPartnerSyncWorker(client as never, externalOptions);
    return `${r.claimed} claimed, ${r.synced} synced, ${r.failed} failed`;
  });
  await lane("finance-bank-feed-sync", async () => {
    const r = await runFinanceBankFeedSyncWorker(client as never, externalOptions);
    return `${r.claimed} claimed, ${r.synced} synced, ${r.failed} failed`;
  });

  return { lanes: results, allOk: results.every((r) => r.ok) };
}

/**
 * The supervisor loop. Runs until `--once` completes one tick, or until a shutdown signal is
 * observed via `shouldStop`.
 *
 * A tick that throws outright — as opposed to a lane failing, which `runTick` already contains —
 * is caught here too. A supervisor that exits on the first transient database blip is a supervisor
 * somebody has to babysit, which defeats the purpose; the failure is reported and the next tick
 * runs.
 */
export async function runSupervisor(
  client: JobRunnerRpcClient & Record<string, unknown>,
  options: SupervisorOptions,
  deps: {
    readonly now: () => string;
    readonly shouldStop: () => boolean;
    readonly log: (line: string) => void;
    readonly wait: (ms: number) => Promise<void>;
  },
): Promise<{ ticks: number; failedLanes: number }> {
  let ticks = 0;
  let failedLanes = 0;

  while (!deps.shouldStop()) {
    ticks += 1;
    try {
      const result = await runTick(client, options, deps.now);
      for (const lane of result.lanes) {
        failedLanes += lane.ok ? 0 : 1;
        deps.log(`[${deps.now()}] ${lane.ok ? "ok  " : "FAIL"} ${lane.lane}: ${lane.ok ? lane.summary : lane.error}`);
      }
    } catch (error) {
      failedLanes += 1;
      deps.log(`[${deps.now()}] FAIL tick: ${describeError(error)}`);
    }

    if (options.once) break;
    if (deps.shouldStop()) break;
    await deps.wait(options.intervalMs);
  }

  return { ticks, failedLanes };
}

async function main(): Promise<void> {
  const options = parseArgs(process.argv.slice(2));
  const client = createSupabaseServiceRoleClient() as unknown as JobRunnerRpcClient & Record<string, unknown>;

  // Graceful shutdown: finish the tick in flight, then stop. Killing a worker mid-job would leave
  // that job's lease held until it expires, which the framework recovers from but only after the
  // lease duration — draining is strictly kinder to the queue.
  let stopping = false;
  const stop = (signal: string) => {
    if (stopping) return;
    stopping = true;
    process.stdout.write(`[supervisor] ${signal} received — finishing the current tick, then exiting\n`);
  };
  process.on("SIGINT", () => stop("SIGINT"));
  process.on("SIGTERM", () => stop("SIGTERM"));

  process.stdout.write(
    `[supervisor] worker=${options.workerId} lanes=${options.lanes.join(",")} ` +
      `${options.once ? "single tick" : `every ${options.intervalMs}ms`}\n`,
  );

  const { ticks, failedLanes } = await runSupervisor(client, options, {
    now: () => new Date().toISOString(),
    shouldStop: () => stopping,
    log: (line) => process.stdout.write(`${line}\n`),
    wait: sleep,
  });

  process.stdout.write(`[supervisor] ${ticks} tick(s), ${failedLanes} lane failure(s)\n`);
  // A lane failure is reported but is NOT a non-zero exit for the long-running mode: a supervisor
  // that a process manager restarts on every transient webhook timeout would flap. `--once`, which
  // is the cron-style mode where an operator or a CI step reads the exit code, does surface it.
  if (options.once && failedLanes > 0) {
    process.exitCode = 1;
  }
}

if (import.meta.url === `file://${process.argv[1]}`) {
  main().catch((error: unknown) => {
    process.stderr.write(`[supervisor] fatal: ${describeError(error)}\n`);
    process.exitCode = 1;
  });
}
