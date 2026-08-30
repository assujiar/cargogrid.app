import { test, describe } from "node:test";
import assert from "node:assert/strict";
import { existsSync, readFileSync } from "node:fs";
import {
  evaluateGoDecision,
  EXIT_BUILD_PROCEEDS,
  EXIT_BUILD_SKIPPED,
  GO_DECISION_PATH,
} from "./check-go-decision.ts";

/**
 * This gate exists to close `RGL-BLK-001`, whose own entry says a gate that can be bypassed by
 * the ordinary act of merging is not a gate. So these tests are written adversarially: every one
 * asks "could a production build get through without a matching recorded decision?"
 *
 * The exit codes are asserted numerically, not via `proceed`, because Vercel's ignoreCommand
 * inverts them (1 = build, 0 = skip) and an inverted implementation would silently become an
 * auto-approve while still passing a boolean-only assertion.
 */

const SHA = "abc1234567890abcdef1234567890abcdef123456";

const decisionFile = (overrides: Record<string, unknown> = {}): string =>
  JSON.stringify({
    decision: "GO",
    authorizedCommitSha: SHA,
    releaseCandidate: "RC-2026.08.25-1",
    decidedBy: "Project owner",
    decidedAt: "2026-08-30T00:00:00Z",
    ...overrides,
  });

describe("the exit-code inversion is correct", () => {
  test("EXIT_BUILD_PROCEEDS is 1 and EXIT_BUILD_SKIPPED is 0, per Vercel ignoreCommand", () => {
    // Pinned as its own test because getting this backwards turns the gate into an auto-approve.
    assert.equal(EXIT_BUILD_PROCEEDS, 1);
    assert.equal(EXIT_BUILD_SKIPPED, 0);
  });

  test("a proceeding outcome exits 1; a skipped outcome exits 0", () => {
    const ok = evaluateGoDecision({ vercelEnv: "production", commitSha: SHA, decisionFileContents: decisionFile() });
    assert.equal(ok.proceed, true);
    assert.equal(ok.exitCode, 1, "authorized production build must exit 1 so Vercel builds it");

    const refused = evaluateGoDecision({ vercelEnv: "production", commitSha: SHA, decisionFileContents: undefined });
    assert.equal(refused.proceed, false);
    assert.equal(refused.exitCode, 0, "refused production build must exit 0 so Vercel skips it");
  });
});

describe("production builds are refused without a matching go decision", () => {
  test("no decision file at all — the RGL-BLK-001 case", () => {
    // This is the state the repository is in until a go decision is deliberately recorded, and
    // the exact scenario RGL-BLK-001 describes: a merge to main reaching production unreviewed.
    const r = evaluateGoDecision({ vercelEnv: "production", commitSha: SHA, decisionFileContents: undefined });
    assert.equal(r.exitCode, EXIT_BUILD_SKIPPED);
    assert.match(r.reason, /no go decision recorded/);
    assert.match(r.reason, new RegExp(GO_DECISION_PATH.replace(/[/.]/g, "\\$&")));
  });

  test("decision file is corrupt — fails closed rather than open", () => {
    const r = evaluateGoDecision({ vercelEnv: "production", commitSha: SHA, decisionFileContents: "{ not json" });
    assert.equal(r.exitCode, EXIT_BUILD_SKIPPED);
    assert.match(r.reason, /not valid JSON/);
  });

  test("decision is NO_GO", () => {
    const r = evaluateGoDecision({
      vercelEnv: "production",
      commitSha: SHA,
      decisionFileContents: decisionFile({ decision: "NO_GO" }),
    });
    assert.equal(r.exitCode, EXIT_BUILD_SKIPPED);
    assert.match(r.reason, /"NO_GO", not "GO"/);
  });

  test("decision names a different commit — a stale GO cannot authorize later work", () => {
    // The sharpest case: a real GO exists, but for an earlier commit. Everything merged after it
    // must not inherit that authorization.
    const r = evaluateGoDecision({
      vercelEnv: "production",
      commitSha: "9999999999999999999999999999999999999999",
      decisionFileContents: decisionFile(),
    });
    assert.equal(r.exitCode, EXIT_BUILD_SKIPPED);
    assert.match(r.reason, /authorizes abc1234/);
    assert.match(r.reason, /this build is 9999999/);
  });

  test("a SHA prefix does not satisfy the match", () => {
    // A prefix comparison would let one decision authorize any commit sharing its first chars.
    const r = evaluateGoDecision({
      vercelEnv: "production",
      commitSha: SHA.slice(0, 7),
      decisionFileContents: decisionFile(),
    });
    assert.equal(r.exitCode, EXIT_BUILD_SKIPPED);
  });

  test("decision omits authorizedCommitSha", () => {
    const r = evaluateGoDecision({
      vercelEnv: "production",
      commitSha: SHA,
      decisionFileContents: decisionFile({ authorizedCommitSha: "" }),
    });
    assert.equal(r.exitCode, EXIT_BUILD_SKIPPED);
    assert.match(r.reason, /names no authorizedCommitSha/);
  });

  test("VERCEL_GIT_COMMIT_SHA is unset — cannot prove the decision applies to this build", () => {
    const r = evaluateGoDecision({
      vercelEnv: "production",
      commitSha: undefined,
      decisionFileContents: decisionFile(),
    });
    assert.equal(r.exitCode, EXIT_BUILD_SKIPPED);
    assert.match(r.reason, /VERCEL_GIT_COMMIT_SHA is unset/);
  });
});

describe("the gate applies to production only", () => {
  test("preview and development builds proceed without any decision", () => {
    // Previews are how a candidate is verified before anyone decides to promote it. Gating them
    // would remove the evidence the go decision is supposed to rest on.
    for (const env of ["preview", "development", undefined]) {
      const r = evaluateGoDecision({ vercelEnv: env, commitSha: SHA, decisionFileContents: undefined });
      assert.equal(r.exitCode, EXIT_BUILD_PROCEEDS, `VERCEL_ENV=${env} must not be gated`);
      assert.match(r.reason, /gate does not apply/);
    }
  });
});

describe("the authorized path works", () => {
  test("a GO for this exact commit proceeds, and says who decided and when", () => {
    const r = evaluateGoDecision({ vercelEnv: "production", commitSha: SHA, decisionFileContents: decisionFile() });
    assert.equal(r.exitCode, EXIT_BUILD_PROCEEDS);
    assert.match(r.reason, /GO recorded by Project owner at 2026-08-30T00:00:00Z/);
    assert.match(r.reason, /production build authorized/);
  });

  test("a GO with no decidedBy still proceeds but reads plainly", () => {
    const r = evaluateGoDecision({
      vercelEnv: "production",
      commitSha: SHA,
      decisionFileContents: decisionFile({ decidedBy: undefined, decidedAt: undefined }),
    });
    assert.equal(r.exitCode, EXIT_BUILD_PROCEEDS);
    assert.match(r.reason, /GO recorded for/);
  });
});

describe("current repository state", () => {
  test("no go decision is recorded yet, so a production build would be refused today", () => {
    // Pins the honest current state: the gate is armed and nothing has been authorized. When a
    // real GO_DECISION.json lands, this test is expected to be updated in that same change.
    if (!existsSync(GO_DECISION_PATH)) {
      const r = evaluateGoDecision({ vercelEnv: "production", commitSha: SHA, decisionFileContents: undefined });
      assert.equal(r.exitCode, EXIT_BUILD_SKIPPED);
    } else {
      // A decision exists — assert it is at least well-formed, so a malformed one cannot sit
      // unnoticed in the repository.
      const parsed = JSON.parse(readFileSync(GO_DECISION_PATH, "utf8")) as { authorizedCommitSha?: string };
      assert.ok(parsed.authorizedCommitSha, "a recorded go decision must name an authorized commit SHA");
    }
  });
});
