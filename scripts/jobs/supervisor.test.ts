import assert from "node:assert/strict";
import { describe, test } from "node:test";

import { ALL_LANES, parseArgs, runSupervisor, runTick, type SupervisorOptions } from "./supervisor.ts";

const NOW = "2026-09-03T00:00:00.000Z";

function options(overrides: Partial<SupervisorOptions> = {}): SupervisorOptions {
  return {
    once: true,
    intervalMs: 1,
    jobLimit: 5,
    schedulerLimit: 5,
    leaseSeconds: 300,
    workerId: "test-worker",
    lanes: [...ALL_LANES],
    ...overrides,
  };
}

/**
 * A fake Supabase client. `responses` maps an RPC name to either a result or a thrown error, so a
 * test can make exactly one lane fail and assert the others still ran.
 */
function fakeClient(responses: Record<string, unknown | (() => never)>) {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];
  const client = {
    async rpc(fn: string, args: Record<string, unknown>) {
      calls.push({ fn, args });
      const response = responses[fn];
      if (typeof response === "function") (response as () => never)();
      if (response && typeof response === "object" && "error" in (response as object)) {
        return response as { data: unknown; error: { message: string } | null };
      }
      return { data: response ?? [], error: null };
    },
  };
  return { client: client as never, calls };
}

describe("supervisor parseArgs", () => {
  test("defaults to every lane and a repeating 30s tick", () => {
    const o = parseArgs([]);
    assert.equal(o.once, false);
    assert.equal(o.intervalMs, 30_000);
    assert.deepEqual(o.lanes, [...ALL_LANES]);
  });

  test("--once switches to a single tick", () => {
    assert.equal(parseArgs(["--once"]).once, true);
  });

  test("--lanes narrows the run", () => {
    const o = parseArgs(["--lanes=scheduler,database-jobs"]);
    assert.deepEqual(o.lanes, ["scheduler", "database-jobs"]);
  });

  test("an unknown lane throws rather than silently running fewer lanes", () => {
    // The failure mode this guards: a typo in --lanes that quietly disabled webhook delivery
    // would be invisible until deliveries stopped arriving.
    assert.throws(() => parseArgs(["--lanes=scheduler,webhook-delivry"]), /unknown lane/);
  });
});

describe("supervisor runTick", () => {
  test("drives the scheduler and the database job runner with the configured limits", async () => {
    const { client, calls } = fakeClient({
      run_due_scheduled_tasks: [{ scheduled_task_id: "s1", status: "success", detail: null }],
      run_due_jobs: [{ job_id: "j1", tenant_id: "t1", job_type: "loyalty_expiry_sweep", outcome: "completed", detail: null }],
    });
    const result = await runTick(client, options({ lanes: ["scheduler", "database-jobs"] }), () => NOW);

    assert.equal(result.allOk, true);
    const scheduler = calls.find((c) => c.fn === "run_due_scheduled_tasks");
    assert.equal(scheduler?.args.p_now, NOW);
    assert.equal(scheduler?.args.p_limit, 5);
    const jobs = calls.find((c) => c.fn === "run_due_jobs");
    assert.equal(jobs?.args.p_worker_id, "test-worker");
    assert.equal(jobs?.args.p_limit, 5);
    assert.equal(jobs?.args.p_lease_seconds, 300);
  });

  test("a lane that throws is reported and the remaining lanes still run", async () => {
    // This is the property the whole supervisor design turns on: an unreachable webhook endpoint
    // must never stop payroll or loyalty sweeps from firing.
    const { client, calls } = fakeClient({
      run_due_scheduled_tasks: () => {
        throw new Error("scheduler exploded");
      },
      run_due_jobs: [{ job_id: "j1", tenant_id: "t1", job_type: "kb_article_expiry", outcome: "completed", detail: null }],
    });
    const result = await runTick(client, options({ lanes: ["scheduler", "database-jobs"] }), () => NOW);

    assert.equal(result.allOk, false);
    const scheduler = result.lanes.find((l) => l.lane === "scheduler");
    assert.equal(scheduler?.ok, false);
    assert.match(scheduler?.error ?? "", /scheduler exploded/);

    const jobs = result.lanes.find((l) => l.lane === "database-jobs");
    assert.equal(jobs?.ok, true, "the database-jobs lane must still have run after the scheduler lane threw");
    assert.ok(calls.some((c) => c.fn === "run_due_jobs"));
  });

  test("names the failing job types rather than only counting them", async () => {
    const { client } = fakeClient({
      run_due_jobs: [
        { job_id: "j1", tenant_id: "t1", job_type: "loyalty_expiry_sweep", outcome: "failed", detail: "insufficient_authority" },
        { job_id: "j2", tenant_id: "t1", job_type: "loyalty_expiry_sweep", outcome: "failed", detail: "insufficient_authority" },
        { job_id: "j3", tenant_id: "t1", job_type: "kb_article_expiry", outcome: "completed", detail: null },
      ],
    });
    const result = await runTick(client, options({ lanes: ["database-jobs"] }), () => NOW);
    const jobs = result.lanes.find((l) => l.lane === "database-jobs");
    assert.equal(jobs?.ok, true, "failed JOBS are a normal outcome; only a failed LANE is a lane failure");
    assert.match(jobs?.summary ?? "", /3 job\(s\) attempted, 2 failed/);
    // De-duplicated: two failures of the same type name it once.
    assert.match(jobs?.summary ?? "", /\(loyalty_expiry_sweep\)/);
  });

  test("a quiet tick is not an error", async () => {
    const { client } = fakeClient({ run_due_scheduled_tasks: [], run_due_jobs: [] });
    const result = await runTick(client, options({ lanes: ["scheduler", "database-jobs"] }), () => NOW);
    assert.equal(result.allOk, true);
    assert.match(result.lanes.find((l) => l.lane === "database-jobs")?.summary ?? "", /0 job\(s\) attempted/);
  });

  test("disabled lanes are not called at all", async () => {
    const { client, calls } = fakeClient({ run_due_jobs: [] });
    await runTick(client, options({ lanes: ["database-jobs"] }), () => NOW);
    assert.equal(calls.some((c) => c.fn === "run_due_scheduled_tasks"), false);
  });
});

describe("supervisor loop", () => {
  test("--once runs exactly one tick", async () => {
    const { client } = fakeClient({ run_due_scheduled_tasks: [], run_due_jobs: [] });
    const lines: string[] = [];
    const result = await runSupervisor(client, options({ once: true, lanes: ["database-jobs"] }), {
      now: () => NOW,
      shouldStop: () => false,
      log: (l) => lines.push(l),
      wait: async () => {},
    });
    assert.equal(result.ticks, 1);
    assert.equal(result.failedLanes, 0);
    assert.equal(lines.length, 1);
  });

  test("keeps ticking until asked to stop, and drains rather than stopping mid-tick", async () => {
    const { client } = fakeClient({ run_due_jobs: [] });
    let ticks = 0;
    const result = await runSupervisor(client, options({ once: false, lanes: ["database-jobs"] }), {
      now: () => NOW,
      // Stop after the third tick has begun; the loop must still finish that tick's lanes.
      shouldStop: () => ticks >= 3,
      log: () => {
        ticks += 1;
      },
      wait: async () => {},
    });
    assert.equal(result.ticks, 3);
  });

  test("a tick that throws outright does not end the loop", async () => {
    // A supervisor that exits on the first transient database blip is one somebody has to
    // babysit, which defeats the point of having it.
    let calls = 0;
    const client = {
      async rpc() {
        calls += 1;
        if (calls === 1) throw new Error("transient connection reset");
        return { data: [], error: null };
      },
    } as never;
    const lines: string[] = [];
    let seen = 0;
    const result = await runSupervisor(client, options({ once: false, lanes: ["database-jobs"] }), {
      now: () => NOW,
      shouldStop: () => seen >= 2,
      log: (l) => {
        lines.push(l);
        seen += 1;
      },
      wait: async () => {},
    });
    assert.equal(result.ticks, 2);
    assert.equal(result.failedLanes, 1, "the first tick's failure is recorded");
    assert.match(lines[0] ?? "", /FAIL database-jobs: transient connection reset/);
    assert.match(lines[1] ?? "", /ok\s+database-jobs/, "the loop recovered on the next tick");
  });
});
