/**
 * Production job-supervisor tick endpoint (CG-AUDIT-2026-09-02 A5).
 * `scripts/jobs/supervisor.ts`'s own header already discloses the honest limit: "it
 * also does not install itself... pointing a process manager, a container restart
 * policy or a timer at this script stays an operator decision." On this repository's
 * actual deploy target that decision has no long-lived host to land on at all — the
 * audit's own finding names exactly that gap: "no Vercel crons, no Edge Functions, no
 * scheduled workflow, and `pg_cron` is never created in any migration — on a
 * serverless deploy target with no long-lived host."
 *
 * This route is the CODE half of closing that gap: one HTTP entry point an external
 * scheduler can call to run exactly one tick — `runTick`, the same function
 * `supervisor.ts --once` already calls, reused verbatim rather than reimplemented, so
 * every lane (scheduler, database-jobs, and the five external-handoff workers) keeps
 * the identical per-lane isolation and authority model `supervisor.ts`'s own header
 * already documents. `vercel.json`'s `crons` entry is committed alongside this route
 * so the schedule itself ships with the code; the one remaining INFRA step — setting
 * `CRON_SECRET` on the live Vercel project — is a deployment-owner action this
 * repository cannot perform for itself (`docs/runbooks/human-execution-pack.md` §6).
 *
 * Authorization mirrors Vercel's own documented Cron Jobs contract: once `CRON_SECRET`
 * is set on the project, Vercel signs its own invocations with
 * `Authorization: Bearer <CRON_SECRET>`. `crypto.timingSafeEqual` (not `===`) compares
 * it, so a byte-by-byte mismatch never leaks how many leading bytes matched. An unset
 * `CRON_SECRET` — any tier that has not completed the operator step yet — fails every
 * request closed, never open: there is no "unauthenticated but allowed" mode for a
 * route that runs privileged, service-role-authenticated writes.
 */

import { timingSafeEqual } from "node:crypto";
import { createSupabaseServiceRoleClient } from "../../../../lib/supabase/service-role.ts";
import type { JobRunnerRpcClient } from "../../../../server/mutations/job-runner.ts";
import { parseArgs, runTick } from "../../../../scripts/jobs/supervisor.ts";

export const dynamic = "force-dynamic";
export const maxDuration = 60;

function isAuthorized(request: Request): boolean {
  const secret = process.env.CRON_SECRET;
  if (!secret) return false;

  const header = request.headers.get("authorization") ?? "";
  const expected = `Bearer ${secret}`;
  const headerBuf = Buffer.from(header);
  const expectedBuf = Buffer.from(expected);
  // timingSafeEqual throws on a length mismatch rather than returning false -- check first.
  if (headerBuf.length !== expectedBuf.length) return false;
  return timingSafeEqual(headerBuf, expectedBuf);
}

export async function GET(request: Request): Promise<Response> {
  if (!isAuthorized(request)) {
    return Response.json({ error: "unauthorized" }, { status: 401 });
  }

  const client = createSupabaseServiceRoleClient() as unknown as JobRunnerRpcClient & Record<string, unknown>;
  const options = parseArgs(["--once"]);

  try {
    const result = await runTick(client, options, () => new Date().toISOString());
    // A failing lane is still a successfully-run tick (runTick's own per-lane isolation) --
    // 207 Multi-Status distinguishes "ran, something failed" from 200's "ran clean" for
    // whatever alerts on this endpoint's response code, without treating either as a 5xx.
    return Response.json(result, { status: result.allOk ? 200 : 207 });
  } catch (error) {
    // A tick that throws outright (as opposed to a lane failure, which runTick already
    // contains) must not read as a silent success to whatever is polling this endpoint.
    return Response.json({ error: error instanceof Error ? error.message : String(error) }, { status: 500 });
  }
}
