import { test, describe } from "node:test";
import assert from "node:assert/strict";
import { computeJobBackoffSeconds, BackgroundJobQueryError, type BackgroundJobQueryRpcClient } from "./background-job.ts";

function fakeClient(
  response: { data: unknown; error: { message: string } | null },
): BackgroundJobQueryRpcClient & { calls: { fn: string; args: Record<string, unknown> }[] } {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];
  return {
    calls,
    async rpc(fn, args) {
      calls.push({ fn, args });
      return response;
    },
  };
}

describe("computeJobBackoffSeconds", () => {
  test("calls compute_job_backoff_seconds with the exact snake_case params", async () => {
    const client = fakeClient({ data: 42, error: null });
    const seconds = await computeJobBackoffSeconds(client, 3);

    assert.deepEqual(client.calls[0]?.args, { p_attempts: 3 });
    assert.equal(seconds, 42);
  });

  test("propagates an RPC error as a query error", async () => {
    const client = fakeClient({ data: null, error: { message: "unexpected failure" } });
    await assert.rejects(() => computeJobBackoffSeconds(client, 1), BackgroundJobQueryError);
  });
});
