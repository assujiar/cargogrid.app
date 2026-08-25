/**
 * Release-candidate freeze enforcement — Step 16, `CG-S16-RGL-003` (Prompt 393,
 * No-New-Feature Rule), enforcing the freeze recorded by `CG-S16-RGL-002`
 * (Prompt 392) in docs/build-log/release-go-live/RGL-392.md §1-§4.
 *
 * A freeze that only exists as prose is not a control. This turns
 * `RC_FROZEN` into a mechanical check: it recomputes the digests Prompt 392
 * froze and fails closed if the candidate's shippable content has drifted.
 *
 * What it guards, and why each one:
 *
 *   - migrations   Schema is the least reversible thing a release can change,
 *                  and "never edit an applied migration" is an AGENTS.md rule
 *                  with real incident history behind it (ERR-2026-001..003).
 *   - db-tests     The evidence that the migrations are correct. Freezing the
 *                  schema while leaving its test suite mutable would let the
 *                  candidate's proof change under it.
 *   - lockfile     The resolved dependency set. Prompt 392 §2 anchors the
 *                  dependency freeze here rather than on package.json, because
 *                  six manifest entries are caret-ranged and only the lockfile
 *                  pins them.
 *
 * Deliberately NOT guarded: docs/**, which every Step 16 lane must write to by
 * charter. A freeze that forbade its own evidence trail would be unusable.
 *
 * This is a local/CI gate over repository content. It cannot police a direct
 * push to an unprotected `main`, nor the Vercel `main` -> production
 * auto-deploy — see RGL-393.md §3 for the ingress paths that remain open, and
 * RGL-BLK-001. Do not read a pass here as "the candidate is sealed".
 *
 * CLI: node --experimental-strip-types scripts/release/check-release-freeze.ts
 */

import { execFileSync } from "node:child_process";
import { createHash } from "node:crypto";
import { readFileSync } from "node:fs";

/**
 * The frozen digests, from docs/build-log/release-go-live/RGL-392.md §2-§3.
 * Changing a value here is amending the freeze and requires a release-authority
 * ruling recorded in that build log — never a quiet edit to make a gate pass.
 */
export interface FrozenCandidate {
  readonly id: string;
  readonly migrationSetSha256: string;
  readonly dbTestSetSha256: string;
  readonly lockfileSha256: string;
}

export const FROZEN_CANDIDATE: FrozenCandidate = {
  id: "RC-2026.08.25-1",
  migrationSetSha256: "15f6e7049105f751c6226bef49520bf035e32fad9418d2247ba2c968172a59ac",
  // 231 tracked .sql files under scripts/db-tests/: the 230 the runner executes,
  // plus fixtures/auth-schema-stub.sql, which it loads into every disposable
  // database before any test runs. RGL-392 §3 originally recorded 2c3389a8...,
  // covering only the 230 top-level files; this gate's own first run caught the
  // omission and RGL-393 widened the freeze to include the fixture. See
  // RGL-393.md §4. The fixture is not incidental — HDN-369 had to correct a
  // stale, load-bearing claim inside it, and its content changes what every
  // db-test runs against.
  dbTestSetSha256: "4df2ae90f01f1b67ee708efc9919d48de2bb78a76e8d1a52cf14788d508488dd",
  lockfileSha256: "feafbf67d7d3b98f1612b770c42775dd41b4aa2943f8849f19a2d3e2b450ade7",
};

export type DriftKind = "MIGRATION_SET" | "DB_TEST_SET" | "LOCKFILE";

export interface FreezeDrift {
  readonly kind: DriftKind;
  readonly expected: string;
  readonly actual: string;
  readonly detail: string;
}

function sha256(buffers: readonly Buffer[]): string {
  const hash = createHash("sha256");
  for (const b of buffers) hash.update(b);
  return hash.digest("hex");
}

/**
 * Tracked files under `dir` with the given extension, in the sorted order the
 * freeze digest was computed in. `git ls-files` is used rather than a directory
 * read so an untracked scratch file cannot silently change the digest — and so
 * a *deleted* tracked file does.
 */
export function listTrackedFiles(dir: string, extension: string): string[] {
  const output = execFileSync("git", ["ls-files", "--", `${dir}/*${extension}`], { encoding: "utf8" });
  return output
    .split("\n")
    .map((l) => l.trim())
    .filter(Boolean)
    .sort();
}

export function digestOfFileSet(files: readonly string[]): string {
  return sha256(files.map((f) => readFileSync(f)));
}

export function checkFreeze(frozen: FrozenCandidate = FROZEN_CANDIDATE): FreezeDrift[] {
  const drift: FreezeDrift[] = [];

  const migrations = listTrackedFiles("supabase/migrations", ".sql");
  const migrationDigest = digestOfFileSet(migrations);
  if (migrationDigest !== frozen.migrationSetSha256) {
    drift.push({
      kind: "MIGRATION_SET",
      expected: frozen.migrationSetSha256,
      actual: migrationDigest,
      detail: `${migrations.length} tracked migration file(s) under supabase/migrations/ no longer match the frozen set`,
    });
  }

  const dbTests = listTrackedFiles("scripts/db-tests", ".sql");
  const dbTestDigest = digestOfFileSet(dbTests);
  if (dbTestDigest !== frozen.dbTestSetSha256) {
    drift.push({
      kind: "DB_TEST_SET",
      expected: frozen.dbTestSetSha256,
      actual: dbTestDigest,
      detail: `${dbTests.length} tracked test file(s) under scripts/db-tests/ no longer match the frozen set`,
    });
  }

  const lockfileDigest = digestOfFileSet(["pnpm-lock.yaml"]);
  if (lockfileDigest !== frozen.lockfileSha256) {
    drift.push({
      kind: "LOCKFILE",
      expected: frozen.lockfileSha256,
      actual: lockfileDigest,
      detail: "pnpm-lock.yaml no longer matches the frozen resolved dependency set",
    });
  }

  return drift;
}

function main(): void {
  const drift = checkFreeze();

  if (drift.length === 0) {
    console.log(`✔ release candidate ${FROZEN_CANDIDATE.id} matches its frozen migration, db-test and lockfile digests.`);
    console.log("  (Content gate only — it does not seal direct pushes to main or the Vercel auto-deploy. See RGL-BLK-001.)");
    return;
  }

  for (const d of drift) {
    console.error(`✖ [${d.kind}] ${d.detail}`);
    console.error(`    expected ${d.expected}`);
    console.error(`    actual   ${d.actual}`);
  }
  console.error(
    `\n${drift.length} freeze violation(s) against ${FROZEN_CANDIDATE.id}. ` +
      "A change here is a change to the release candidate: it needs a release-authority ruling recorded in " +
      "docs/build-log/release-go-live/, not an edit to the expected digests.",
  );
  process.exit(1);
}

if (import.meta.url === `file://${process.argv[1]}`) {
  main();
}
