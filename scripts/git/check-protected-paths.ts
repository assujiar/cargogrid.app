/**
 * Checks a set of changed file paths against docs/git/GIT_STRATEGY.md §4's
 * protected-path table. Two severities:
 *   - FORBIDDEN: never touched by a runtime agent without the named override
 *     authority (read-only sources, applied migrations, real secrets).
 *   - CAUTION: legitimately edited, but additively/carefully only (e.g.
 *     docs/runtime/** is meant to be updated every checkpoint — this is a
 *     reminder to follow the append-only/reconciliation discipline, not a
 *     block).
 *
 * Rules are evaluated in order and the FIRST match wins, so a narrow rule may
 * be placed ahead of a broader one to override it. The only such narrowing today
 * is CON-016/ADR-0026's: five register/derived-metadata files under the otherwise
 * FORBIDDEN prompt-package tree are CAUTION, because Step 17's own prompts
 * (415-429 §20.4/§31, 429 §4) require the executing agent to correct them.
 * All 324 prompt files and all 18 step READMEs remain FORBIDDEN.
 *
 * The migrations rule is git-status-aware: a brand-new migration file (git
 * status `A`) is never flagged — only a modification to one that already
 * existed before this change (`M`, or any status other than `A`) is. A
 * caller that supplies a bare path with no status (e.g. an existing unit
 * test, or a manual single-path check) gets the previous, conservative
 * behavior — flagged regardless — since "no status" cannot prove the file
 * is new.
 *
 * CLI: node --experimental-strip-types scripts/git/check-protected-paths.ts [<git-diff-range>]
 *      Default range: staged changes (`git diff --cached --name-status`).
 */

export type PathSeverity = "FORBIDDEN" | "CAUTION";

export interface ProtectedPathRule {
  readonly pattern: RegExp;
  readonly severity: PathSeverity;
  readonly reason: string;
}

/** A migration path is exempt from the FORBIDDEN migrations rule only when its git status is known and is exactly "added". */
const MIGRATIONS_PATTERN = /^supabase\/migrations\/\d.*\.sql$/;

/**
 * The five register/derived-metadata files Step 17 (Final Package Validation) may correct, per
 * `CON-016` / `ADR-0026`. Matched LITERALLY and exactly — never by prefix or glob — so no
 * file can be brought inside the exemption by being placed next to one of these. Everything
 * else under docs/ai-agent-build-prompt-package/ stays FORBIDDEN, in particular all 324
 * prompt files and all 18 step READMEs (BUILD_EXECUTION_PROTOCOL.md §3.5, AGENTS.md).
 */
export const STEP17_CORRECTABLE_PACKAGE_PATHS: readonly string[] = [
  // 04 carries CON-016 itself. Its binding authority stays "decision-change protocol only"
  // (GIT_STRATEGY.md §4) -- a policy control a path-based gate cannot express, exactly as
  // docs/runtime/**'s append-only discipline is. CAUTION makes the write visible; the ADR,
  // not this list, is what makes it legitimate.
  "docs/ai-agent-build-prompt-package/00-control/04_CONFLICT_REGISTER.md",
  "docs/ai-agent-build-prompt-package/00-control/05_REQUIREMENT_COVERAGE_MATRIX.md",
  "docs/ai-agent-build-prompt-package/00-control/06_PACKAGE_BUILD_STATUS.md",
  "docs/ai-agent-build-prompt-package/00-control/07_PROMPT_PACKAGE_MANIFEST.md",
  "docs/ai-agent-build-prompt-package/START_HERE.md",
];

/**
 * The prompt files package revision `0.19.0` may correct, per `ADR-0028` / `CON-017`.
 *
 * `ADR-0026` kept every prompt file `FORBIDDEN` so that Step 17's audit could not edit its own
 * subject while auditing it. That audit is finished and its verdict is recorded; correcting the
 * defects it *found* is the intended next action, and the Owner column on all eight open
 * findings says `Future package revision (0.19.x)` — this is that revision.
 *
 * Enumerated by finding, matched LITERALLY, never by glob. A file is on this list because a
 * named Step 17 finding requires it, and for no other reason. Everything else under
 * docs/ai-agent-build-prompt-package/ stays FORBIDDEN.
 */
export const REVISION_0_19_CORRECTABLE_PROMPT_PATHS: readonly string[] = [
  // FPV-F003 (indented bodies) + FPV-F004 (legacy heading wording) + FPV-F007 (unrecorded
  // version) -- the same 14-file cluster, three independent defects from one revision pass.
  "docs/ai-agent-build-prompt-package/10-phase-05-advanced-tms-wms/222_DISPATCH_BOARD_PROMPT.md",
  "docs/ai-agent-build-prompt-package/10-phase-05-advanced-tms-wms/223_FLEET_DRIVER_PROMPT.md",
  "docs/ai-agent-build-prompt-package/10-phase-05-advanced-tms-wms/224_ROUTE_LOAD_PLANNING_PROMPT.md",
  "docs/ai-agent-build-prompt-package/10-phase-05-advanced-tms-wms/225_FIRST_MIDDLE_LAST_MILE_PROMPT.md",
  "docs/ai-agent-build-prompt-package/10-phase-05-advanced-tms-wms/226_GPS_TELEMATICS_INTEGRATION_PROMPT.md",
  "docs/ai-agent-build-prompt-package/10-phase-05-advanced-tms-wms/227_CAPACITY_UTILIZATION_PROMPT.md",
  "docs/ai-agent-build-prompt-package/10-phase-05-advanced-tms-wms/228_ADVANCED_MILESTONE_EXCEPTION_PROMPT.md",
  "docs/ai-agent-build-prompt-package/10-phase-05-advanced-tms-wms/243_HIGH_VOLUME_OPERATIONS_PROMPT.md",
  "docs/ai-agent-build-prompt-package/10-phase-05-advanced-tms-wms/245_ADVANCED_TMS_WMS_INTEGRATED_VERIFICATION_PROMPT.md",
  "docs/ai-agent-build-prompt-package/10-phase-05-advanced-tms-wms/246_ADVANCED_TMS_WMS_INTEGRITY_SECURITY_HARDENING_PROMPT.md",
  "docs/ai-agent-build-prompt-package/10-phase-05-advanced-tms-wms/247_ADVANCED_TMS_WMS_DOCUMENTATION_HANDOFF_PROMPT.md",
  "docs/ai-agent-build-prompt-package/13-phase-08-customer-portal-loyalty/305_TRACKING_PROMPT.md",
  "docs/ai-agent-build-prompt-package/13-phase-08-customer-portal-loyalty/306_SHIPMENT_MONITORING_PROMPT.md",
  "docs/ai-agent-build-prompt-package/14-phase-09-intelligence-enterprise/343_MAPS_GPS_TELEMATICS_INTEGRATIONS_PROMPT.md",
  // FPV-F007 only -- three further files in the same unrecorded revision pass that were NOT
  // indented and so were not in the FPV-F003 cluster. 219 is a step README, which ADR-0026
  // decision 2 kept FORBIDDEN alongside the prompt files; it is named here explicitly rather
  // than reached by a directory rule, because a README slipping in under a glob is exactly
  // the failure that list was written to prevent.
  "docs/ai-agent-build-prompt-package/10-phase-05-advanced-tms-wms/219_ADVANCED_TMS_WMS_README.md",
  "docs/ai-agent-build-prompt-package/10-phase-05-advanced-tms-wms/220_ADVANCED_TMS_WMS_WBS_RUNTIME_KICKOFF_PROMPT.md",
  "docs/ai-agent-build-prompt-package/10-phase-05-advanced-tms-wms/248_ADVANCED_TMS_WMS_CLOSURE_VERIFICATION_PROMPT.md",
  // FPV-F002 only -- one line each, adding the RPD id to the §6 Source requirement of the
  // prompt that already covers that decision by content. No requirement changes; the
  // traceability becomes mechanically checkable rather than only re-derivable by topic.
  "docs/ai-agent-build-prompt-package/05-phase-00-discovery-foundation/95_DATA_CLASSIFICATION_FOUNDATION_PROMPT.md",
  "docs/ai-agent-build-prompt-package/06-phase-01-platform-core/106_SUBSCRIPTION_MODULE_FEATURE_ENTITLEMENT_PROMPT.md",
  "docs/ai-agent-build-prompt-package/06-phase-01-platform-core/117_WHITE_LABEL_FOUNDATION_PROMPT.md",
  "docs/ai-agent-build-prompt-package/15-hardening/380_ACCESSIBILITY_AUDIT_PROMPT.md",
];

/**
 * FPV-F001: the one NEW file this revision authors -- the tenant merge/split capability prompt
 * carrying `RPD-020`, which no prompt anywhere in the package covered. Listed separately from
 * the corrections above because it is a different kind of act: adding an artifact, not
 * repairing one.
 */
export const REVISION_0_19_NEW_PROMPT_PATHS: readonly string[] = [
  // Numbered 431, not 137. The first draft of this list said `137_…`, from when the prompt was
  // going to be inserted at its execution position; the number changed to 431 once it was clear
  // that seating it at 137 meant renumbering 325 files and falsifying every committed citation
  // to them (ISS-2026-306). The allowlist was not updated with it, so the gate correctly
  // reported the real file as FORBIDDEN. That is the enumerate-literally design working: a glob
  // would have silently accepted either number and told us nothing.
  "docs/ai-agent-build-prompt-package/06-phase-01-platform-core/431_TENANT_MERGE_SPLIT_PROMPT.md",
];

/**
 * `FPV-F009`: the four control files that carry no package-version line at all.
 *
 * These are listed separately, and the separation is the point. `ADR-0028` decision 1 originally
 * described them as "the control files already correctable under `CON-016`". **That was wrong.**
 * `CON-016` made exactly five paths correctable — `04`, `05`, `06`, `07` and `START_HERE.md` —
 * and said in terms that `02_CONFIRMED_DECISION_REGISTER.md` and `03_ASSUMPTION_REGISTER.md`
 * "remain reachable only through the §5 decision-change protocol". These four were never
 * unlocked, and the gate blocked them on the revision's first real run, exactly as designed.
 *
 * So this is a **widening**, not an inheritance, and it is recorded as one. What it permits is a
 * single header line — `**Package version:** …` — on a file whose own rows are untouched.
 * Adding that line is not a decision change: no RPD, no assumption, no `Version:` lifecycle
 * field moves.
 *
 * **Residual risk, stated plainly:** a path-based gate cannot tell a version-line edit from a
 * decision-row edit inside `02` or `03`. The containment is not this rule — it is the `CAUTION`
 * warning surfacing the write in every gate run, the PR diff, and `package:check`. Anyone
 * reviewing a diff that touches these two files should read it as a decision change until the
 * diff proves otherwise.
 */
export const REVISION_0_19_VERSION_LINE_ONLY_PATHS: readonly string[] = [
  "docs/ai-agent-build-prompt-package/00-control/00_PACKAGE_README.md",
  "docs/ai-agent-build-prompt-package/00-control/01_SOURCE_OF_TRUTH_MATRIX.md",
  "docs/ai-agent-build-prompt-package/00-control/02_CONFIRMED_DECISION_REGISTER.md",
  "docs/ai-agent-build-prompt-package/00-control/03_ASSUMPTION_REGISTER.md",
];

/** Escapes a literal path so it can anchor an exact-match RegExp. */
function exactPathPattern(paths: readonly string[]): RegExp {
  const alternation = paths.map((p) => p.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")).join("|");
  return new RegExp(`^(?:${alternation})$`);
}

const STEP17_CORRECTABLE_PATTERN = exactPathPattern(STEP17_CORRECTABLE_PACKAGE_PATHS);
const REVISION_0_19_PATTERN = exactPathPattern([
  ...REVISION_0_19_CORRECTABLE_PROMPT_PATHS,
  ...REVISION_0_19_NEW_PROMPT_PATHS,
]);
const REVISION_0_19_VERSION_LINE_PATTERN = exactPathPattern(REVISION_0_19_VERSION_LINE_ONLY_PATHS);

export const PROTECTED_PATH_RULES: readonly ProtectedPathRule[] = [
  { pattern: /^docs\/blueprint\//, severity: "FORBIDDEN", reason: "read-only authoritative source (decision-change protocol only)" },
  // Ordered BEFORE the blanket package rule below: first match wins for these four paths
  // (see the loop in checkProtectedPaths, which breaks on the first matching rule).
  { pattern: STEP17_CORRECTABLE_PATTERN, severity: "CAUTION", reason: "package metadata correctable by Step 17 only, mechanical/source-safe corrections with cited evidence (CON-016, ADR-0026) — re-verify with `pnpm run package:check`" },
  { pattern: REVISION_0_19_PATTERN, severity: "CAUTION", reason: "prompt file unlocked by package revision 0.19.0 for one named Step 17 finding only (CON-017, ADR-0028) — re-verify with `pnpm run package:check`" },
  { pattern: REVISION_0_19_VERSION_LINE_PATTERN, severity: "CAUTION", reason: "control file unlocked by package revision 0.19.0 for the `**Package version:**` header line ONLY (FPV-F009, CON-017, ADR-0028) — any other change to 02/03 is a decision change needing the §5 protocol; re-verify with `pnpm run package:check`" },
  { pattern: /^docs\/ai-agent-build-prompt-package\//, severity: "FORBIDDEN", reason: "read-only execution plan — never edited by a runtime agent" },
  { pattern: MIGRATIONS_PATTERN, severity: "FORBIDDEN", reason: "applied migration — never edit, add a new migration instead (AGENTS.md)" },
  { pattern: /(^|\/)\.env(\.(?!example$|sample$|template$)[^/]*)?$/, severity: "FORBIDDEN", reason: "real environment/secret file — must never be committed (.env.example/.sample/.template are the safe, allowed exception)" },
  { pattern: /^docs\/architecture\//, severity: "CAUTION", reason: "VERIFIED once closed — amend with a visible supersession blockquote, never a silent edit" },
  { pattern: /^docs\/runtime\//, severity: "CAUTION", reason: "additive/append-only ledger — historical rows are evidence, never deleted" },
];

export interface PathCheckFinding {
  readonly path: string;
  readonly severity: PathSeverity;
  readonly reason: string;
}

export type ChangedPathEntry = string | { readonly path: string; readonly status?: string };

export function checkProtectedPaths(changedPaths: readonly ChangedPathEntry[]): readonly PathCheckFinding[] {
  const findings: PathCheckFinding[] = [];
  for (const entry of changedPaths) {
    const path = typeof entry === "string" ? entry : entry.path;
    const status = typeof entry === "string" ? undefined : entry.status;
    for (const rule of PROTECTED_PATH_RULES) {
      if (!rule.pattern.test(path)) continue;
      if (rule.pattern === MIGRATIONS_PATTERN && status === "A") continue;
      findings.push({ path, severity: rule.severity, reason: rule.reason });
      // First match wins, so a narrowing rule placed ahead of a broader one (CON-016's four
      // Step 17 metadata paths ahead of the blanket package rule) genuinely overrides it
      // instead of both firing and the FORBIDDEN one still blocking.
      break;
    }
  }
  return findings;
}

async function changedPathsFromGit(range?: string): Promise<{ path: string; status: string }[]> {
  const { execFileSync } = await import("node:child_process");
  const args = range ? ["diff", "--name-status", range] : ["diff", "--cached", "--name-status"];
  const output = execFileSync("git", args, { encoding: "utf8" });
  return output
    .split("\n")
    .map((line) => line.trim())
    .filter(Boolean)
    .map((line) => {
      const [status, ...pathParts] = line.split("\t");
      // Rename/copy lines are "R100\told\tnew" — the changed path is the last field.
      return { status: (status ?? "").charAt(0), path: pathParts[pathParts.length - 1] ?? "" };
    })
    .filter((entry) => entry.path.length > 0);
}

async function main(): Promise<void> {
  const range = process.argv[2];
  const entries = await changedPathsFromGit(range);
  const findings = checkProtectedPaths(entries);

  const forbidden = findings.filter((f) => f.severity === "FORBIDDEN");
  const caution = findings.filter((f) => f.severity === "CAUTION");

  for (const f of caution) console.warn(`⚠ CAUTION ${f.path}: ${f.reason}`);
  for (const f of forbidden) console.error(`✖ FORBIDDEN ${f.path}: ${f.reason}`);

  if (forbidden.length > 0) {
    console.error(`\n${forbidden.length} forbidden path(s) touched — see docs/git/GIT_STRATEGY.md §4 for override authority.`);
    process.exit(1);
  }

  console.log(`✔ no forbidden paths touched (${entries.length} file(s) checked, ${caution.length} caution flag(s)).`);
}

if (import.meta.url === `file://${process.argv[1]}`) {
  main();
}
