/** CG-AUDIT-2026-09-02 A5: route-level coverage for GET /api/cron/supervisor-tick. */
import { test, describe, afterEach } from "node:test";
import assert from "node:assert/strict";
import { installRpcFetchStub } from "../v1/support/rpc-fetch-stub.ts";
import { GET } from "../../../app/api/cron/supervisor-tick/route.ts";

const ORIGINAL_CRON_SECRET = process.env.CRON_SECRET;

afterEach(() => {
  if (ORIGINAL_CRON_SECRET === undefined) {
    delete process.env.CRON_SECRET;
  } else {
    process.env.CRON_SECRET = ORIGINAL_CRON_SECRET;
  }
});

function get(headers: Record<string, string> = {}) {
  return GET(new Request("http://localhost/api/cron/supervisor-tick", { headers }));
}

/** An empty-but-successful tick: every lane's own RPC reports no work available. */
function emptyTickStub() {
  return installRpcFetchStub({
    run_due_scheduled_tasks: { data: [] },
    run_due_jobs: { data: [] },
    claim_next_job: { data: null },
  });
}

describe("GET /api/cron/supervisor-tick", () => {
  test("CRON_SECRET unset -> 401, and the tick never runs (fails closed, not open)", async () => {
    delete process.env.CRON_SECRET;
    const stub = emptyTickStub();
    try {
      const response = await get({ authorization: "Bearer anything" });
      assert.equal(response.status, 401);
      assert.equal(stub.calls.length, 0);
    } finally {
      stub.restore();
    }
  });

  test("missing Authorization header -> 401, tick never runs", async () => {
    process.env.CRON_SECRET = "test-cron-secret";
    const stub = emptyTickStub();
    try {
      const response = await get();
      assert.equal(response.status, 401);
      assert.equal(stub.calls.length, 0);
    } finally {
      stub.restore();
    }
  });

  test("wrong Authorization value -> 401, tick never runs", async () => {
    process.env.CRON_SECRET = "test-cron-secret";
    const stub = emptyTickStub();
    try {
      const response = await get({ authorization: "Bearer wrong-value" });
      assert.equal(response.status, 401);
      assert.equal(stub.calls.length, 0);
    } finally {
      stub.restore();
    }
  });

  test("correct Authorization -> runs a real tick and reports 200 when every lane succeeds", async () => {
    process.env.CRON_SECRET = "test-cron-secret";
    const stub = emptyTickStub();
    try {
      const response = await get({ authorization: "Bearer test-cron-secret" });
      assert.equal(response.status, 200);
      const body = (await response.json()) as { allOk: boolean; lanes: Array<{ lane: string; ok: boolean }> };
      assert.equal(body.allOk, true);
      // scheduler + database-jobs + the 5 external-handoff workers, matching supervisor.ts's own ALL_LANES.
      assert.equal(body.lanes.length, 7);
      assert.ok(body.lanes.every((l) => l.ok));
      assert.ok(stub.calls.some((c) => c.fn === "run_due_scheduled_tasks"));
      assert.ok(stub.calls.some((c) => c.fn === "run_due_jobs"));
      assert.ok(stub.calls.some((c) => c.fn === "claim_next_job"));
    } finally {
      stub.restore();
    }
  });

  test("a failing lane still reports the tick as run -> 207, never a 500 (runTick's own per-lane isolation)", async () => {
    process.env.CRON_SECRET = "test-cron-secret";
    const stub = installRpcFetchStub({
      run_due_scheduled_tasks: { data: [] },
      run_due_jobs: { error: { message: "simulated database-jobs lane failure" } },
      claim_next_job: { data: null },
    });
    try {
      const response = await get({ authorization: "Bearer test-cron-secret" });
      assert.equal(response.status, 207);
      const body = (await response.json()) as { allOk: boolean; lanes: Array<{ lane: string; ok: boolean; error?: string }> };
      assert.equal(body.allOk, false);
      const dbJobsLane = body.lanes.find((l) => l.lane === "database-jobs");
      assert.equal(dbJobsLane?.ok, false);
      assert.ok(dbJobsLane?.error?.includes("simulated database-jobs lane failure"));
      // Every other lane still ran despite this one's failure.
      assert.ok(body.lanes.filter((l) => l.lane !== "database-jobs").every((l) => l.ok));
    } finally {
      stub.restore();
    }
  });
});
