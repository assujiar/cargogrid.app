/**
 * Supply-chain vulnerability gate (CG-S10-ATW-031, closes ISS-2026-007).
 *
 * ISS-2026-007 was opened at PH0-094 because `pnpm audit` failed with
 * ERR_PNPM_AUDIT_BAD_RESPONSE -- npm had retired the classic advisory endpoints
 * (410 Gone) and pnpm had not yet moved to the bulk endpoint. That checkpoint
 * correctly refused to wire a gate rather than fabricate a passing one, and the
 * repository has had NO automated dependency-vulnerability checking since.
 *
 * It works again. Re-running it during this audit found 20 real advisories --
 * 11 of them high severity, including four in Next.js itself (App Router
 * middleware/proxy bypass, SSRF in Server Actions, SSRF in rewrites, and a
 * Server Actions DoS), all fixed in 16.2.11 while this repository pinned
 * 16.2.10. Those had been sitting unseen for exactly as long as the gate was
 * missing, which is the real cost of leaving a broken gate unwired.
 *
 * OUTCOMES, and why an unreachable registry is not a pass:
 *
 *   clean       -> exit 0.
 *   findings    -> exit 1, listing every advisory at or above the threshold.
 *   unreachable -> exit 1, saying plainly that NO audit was performed.
 *
 * The third case is deliberate. `docs/build-log/phase-00/PH0-88.md` established
 * that this repository never fabricates a passing gate, and "the advisory
 * service was down so we assume clean" is exactly that. A red build that says
 * "could not audit" is honest; a green one that means the same thing is not.
 */

import { execFile } from "node:child_process";
import { promisify } from "node:util";

const execFileAsync = promisify(execFile);

/** Severities that fail the gate. Moderate/low are reported but do not block. */
const BLOCKING_SEVERITIES = new Set(["critical", "high"]);

interface Advisory {
  module_name?: string;
  severity?: string;
  title?: string;
  vulnerable_versions?: string;
  patched_versions?: string;
  url?: string;
}

interface AuditReport {
  advisories?: Record<string, Advisory>;
  metadata?: { vulnerabilities?: Record<string, number> };
}

async function runAudit(): Promise<AuditReport> {
  try {
    // `pnpm audit` exits non-zero whenever it finds anything, so a thrown error
    // here is not itself a failure -- the stdout still carries the real report.
    const { stdout } = await execFileAsync("pnpm", ["audit", "--json"], {
      maxBuffer: 32 * 1024 * 1024,
      cwd: process.cwd(),
    });
    return JSON.parse(stdout) as AuditReport;
  } catch (error) {
    const stdout = (error as { stdout?: string }).stdout ?? "";
    if (stdout.trim().length > 0) {
      try {
        return JSON.parse(stdout) as AuditReport;
      } catch {
        // fall through to the unreachable path below
      }
    }
    const stderr = (error as { stderr?: string }).stderr ?? (error as Error).message;
    throw new Error(`audit_unavailable: ${stderr.trim().split("\n").slice(0, 3).join(" | ")}`);
  }
}

async function main(): Promise<void> {
  let report: AuditReport;
  try {
    report = await runAudit();
  } catch (error) {
    console.error("✖ dependency audit could NOT be performed -- this is a failure, not a pass.");
    console.error(`  ${(error as Error).message}`);
    console.error("  A gate that cannot check must never report clean (docs/build-log/phase-00/PH0-88.md).");
    process.exit(1);
    return;
  }

  const advisories = Object.values(report.advisories ?? {});
  const counts = report.metadata?.vulnerabilities ?? {};
  const blocking = advisories.filter((a) => BLOCKING_SEVERITIES.has(a.severity ?? ""));
  const informational = advisories.filter((a) => !BLOCKING_SEVERITIES.has(a.severity ?? ""));

  const summary = Object.entries(counts)
    .filter(([, n]) => n > 0)
    .map(([severity, n]) => `${n} ${severity}`)
    .join(", ");

  if (informational.length > 0) {
    console.log(`ℹ ${informational.length} advisory/advisories below the blocking threshold (moderate/low):`);
    for (const a of informational) {
      console.log(`    ${a.severity} ${a.module_name} ${a.vulnerable_versions} -> ${a.patched_versions ?? "(no patch)"}`);
    }
  }

  if (blocking.length > 0) {
    console.error(`✖ ${blocking.length} blocking dependency vulnerability/vulnerabilities (critical/high):`);
    for (const a of blocking) {
      console.error(`    ${a.severity} ${a.module_name} ${a.vulnerable_versions} -> ${a.patched_versions ?? "(no patch)"}`);
      console.error(`      ${a.title ?? ""}`);
      if (a.url) console.error(`      ${a.url}`);
    }
    console.error("  Fix by bumping the direct dependency, or by adding a pnpm.overrides entry in package.json.");
    process.exit(1);
    return;
  }

  console.log(`✔ dependency audit passed${summary ? ` (${summary}, none at or above high)` : " (no advisories)"}.`);
}

await main();
