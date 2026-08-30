/**
 * Production go-decision gate — closes `RGL-BLK-001`.
 *
 * `RGL-BLK-001` recorded that the Vercel project deploys every push or merge to `main` straight
 * to `target: production`, with no approval step, defeating `390_RELEASE_GO_LIVE_README.md`'s own
 * non-negotiable gate: *"No production deployment without recorded go decision."* Its own entry
 * put the problem exactly: **"A gate that can be bypassed by the ordinary act of merging is not a
 * gate."** It was carried for weeks as an operator-accepted risk because no tool in the sessions
 * that found it could configure Vercel or GitHub.
 *
 * This script is the mechanism, and it lives in the repository rather than in a provider setting,
 * so the decision it enforces is reviewable in a diff and auditable in git history.
 *
 * It runs as Vercel's **Ignored Build Step** (`vercel.json` → `ignoreCommand`). A production build
 * proceeds only when `docs/build-log/release-go-live/GO_DECISION.json` records a `GO` for the
 * exact commit being built.
 *
 * ## The exit-code inversion, which is easy to get backwards
 *
 * Vercel's ignoreCommand semantics are the opposite of a normal check:
 *
 *   - **exit 1 → the build PROCEEDS**
 *   - **exit 0 → the build is SKIPPED**
 *
 * So "everything is fine, deploy" is a *failure* exit code here. Getting this backwards would
 * turn the gate into an auto-approve, which is worse than having no gate at all — it would look
 * like a control while permitting exactly what it exists to prevent. `GateOutcome` below is a
 * named type rather than a bare boolean for this reason, and the unit tests assert the numeric
 * exit codes, not just the decision.
 *
 * ## What this gate does and does not cover, stated plainly
 *
 * Covers: every Git-triggered production build on this Vercel project.
 *
 * Does **not** cover: a `vercel --prod` deploy from someone's laptop, or a redeploy triggered from
 * the Vercel dashboard — neither necessarily evaluates `ignoreCommand`. `vercel.json`'s
 * `git.deploymentEnabled.main = false` is the complementary control for the specific mechanism
 * `RGL-BLK-001` describes (a merge to `main` auto-deploying). Together they close the merge path
 * and the Git path; a human with Vercel credentials deploying by hand remains possible, and that
 * is a deliberate escape hatch for incident response, not an oversight. See
 * `docs/runbooks/deployment-rollback.md`.
 *
 * CLI: node --experimental-strip-types scripts/release/check-go-decision.ts
 */

export const GO_DECISION_PATH = "docs/build-log/release-go-live/GO_DECISION.json";

/** Vercel ignoreCommand exit codes, named so the inversion cannot be applied by accident. */
export const EXIT_BUILD_PROCEEDS = 1;
export const EXIT_BUILD_SKIPPED = 0;

export interface GoDecisionRecord {
  /** `GO` is the only value that permits a production build. */
  readonly decision: string;
  /** The exact commit SHA this decision authorizes for production. */
  readonly authorizedCommitSha: string;
  /** Release candidate identity, for cross-referencing RGL-392's freeze. */
  readonly releaseCandidate?: string;
  /** Who decided. A go decision without an accountable name is not a decision. */
  readonly decidedBy?: string;
  /** ISO-8601 timestamp. */
  readonly decidedAt?: string;
  /** Path to the human-readable record this JSON summarizes. */
  readonly recordPath?: string;
}

export interface GateOutcome {
  /** True only when a production build is authorized to proceed. */
  readonly proceed: boolean;
  /** Exit code to hand Vercel — already inverted correctly. */
  readonly exitCode: number;
  /** Human-readable reason, printed either way so a skipped build explains itself. */
  readonly reason: string;
}

export interface GateInputs {
  /** `production`, `preview`, or `development`. Vercel sets `VERCEL_ENV`. */
  readonly vercelEnv: string | undefined;
  /** The commit being built. Vercel sets `VERCEL_GIT_COMMIT_SHA`. */
  readonly commitSha: string | undefined;
  /** Raw file contents, or undefined when the file is absent. */
  readonly decisionFileContents: string | undefined;
}

const proceed = (reason: string): GateOutcome => ({ proceed: true, exitCode: EXIT_BUILD_PROCEEDS, reason });
const skip = (reason: string): GateOutcome => ({ proceed: false, exitCode: EXIT_BUILD_SKIPPED, reason });

/**
 * Decides whether a build may proceed. Pure, so the decision is testable without a Vercel
 * environment — the whole point of a gate is that you can prove what it does.
 */
export function evaluateGoDecision(inputs: GateInputs): GateOutcome {
  // Non-production builds are unaffected. Previews are how a candidate gets verified before
  // anyone decides to promote it; gating them would remove the evidence the decision rests on.
  if (inputs.vercelEnv !== "production") {
    return proceed(`VERCEL_ENV is "${inputs.vercelEnv ?? "(unset)"}", not "production" — gate does not apply`);
  }

  if (inputs.decisionFileContents === undefined) {
    return skip(`no go decision recorded (${GO_DECISION_PATH} is absent) — production build refused`);
  }

  let record: GoDecisionRecord;
  try {
    record = JSON.parse(inputs.decisionFileContents) as GoDecisionRecord;
  } catch (error) {
    // Fail closed. An unreadable decision file is not a decision.
    return skip(`${GO_DECISION_PATH} is not valid JSON (${(error as Error).message}) — production build refused`);
  }

  if (record.decision !== "GO") {
    return skip(`recorded decision is "${record.decision ?? "(missing)"}", not "GO" — production build refused`);
  }

  if (!record.authorizedCommitSha) {
    return skip(`go decision names no authorizedCommitSha — production build refused`);
  }

  if (!inputs.commitSha) {
    // Without knowing which commit is being built, the SHA match cannot be performed, so the
    // decision cannot be shown to apply to it.
    return skip(`VERCEL_GIT_COMMIT_SHA is unset, so the go decision cannot be matched to this build — refused`);
  }

  // Full-length comparison. A prefix match would let a decision for one commit authorize another
  // sharing its first characters.
  if (record.authorizedCommitSha !== inputs.commitSha) {
    return skip(
      `go decision authorizes ${record.authorizedCommitSha} but this build is ${inputs.commitSha} — production build refused`,
    );
  }

  const who = record.decidedBy ? ` by ${record.decidedBy}` : "";
  const when = record.decidedAt ? ` at ${record.decidedAt}` : "";
  return proceed(`GO recorded${who}${when} for ${record.authorizedCommitSha} — production build authorized`);
}

async function main(): Promise<void> {
  const { readFile } = await import("node:fs/promises");

  let contents: string | undefined;
  try {
    contents = await readFile(GO_DECISION_PATH, "utf8");
  } catch {
    contents = undefined;
  }

  const outcome = evaluateGoDecision({
    vercelEnv: process.env.VERCEL_ENV,
    commitSha: process.env.VERCEL_GIT_COMMIT_SHA,
    decisionFileContents: contents,
  });

  // Printed on both paths: a skipped production build must say why, or the next person will
  // assume the deployment is broken rather than deliberately withheld.
  console.log(`${outcome.proceed ? "▶ BUILD PROCEEDS" : "⛔ BUILD SKIPPED"}: ${outcome.reason}`);
  if (!outcome.proceed) {
    console.log(
      `\nTo authorize a production deployment, record the decision in ${GO_DECISION_PATH} ` +
        `naming this exact commit, and commit it. See docs/build-log/release-go-live/GO_NO_GO_REPORT.md ` +
        `and RGL-BLK-001 in BLOCKER_LEDGER.md.`,
    );
  }
  process.exit(outcome.exitCode);
}

if (import.meta.url === `file://${process.argv[1]}`) {
  main();
}
