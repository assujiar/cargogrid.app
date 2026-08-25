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
 *
 * AMENDED 2026-08-25 (first pass), migrationSetSha256 and dbTestSetSha256 only
 * (lockfile untouched). Ruling: docs/build-log/release-go-live/RGL-BLK-002-OPTION2-REMEDIATION.md.
 * Direct, explicit operator authority ("benerin pake opsi 2 sampe tuntas dan tidak
 * tersisa tanpa membuat error regression") to fix RGL-BLK-002 (app schema unreachable
 * via PostgREST -- every server-side RPC call in the deployed application failed)
 * before Step 16's own RGL-394/395 formally run. This is not a silent edit to make
 * the gate pass: the prior digests are preserved below as history, the new migration
 * (20260826000000_create_public_api_data_wrappers.sql, 2367 wrapper functions) and
 * its own exhaustive regression test (scripts/db-tests/public-api-wrapper-regression.sql)
 * are both committed and reviewable, and the full 231-file db-test suite plus the
 * full Tier A gate suite were re-run clean against this exact amended state before
 * this file was changed.
 *
 * AMENDED 2026-08-25 (second pass), migrationSetSha256 only. Same ruling
 * document, same operator authority -- this is that authority's own Tier C
 * self-correction, not a new instruction. The first-pass migration, once
 * applied live, was found (by direct live catalog comparison, not a sample) to
 * carry two live-forced defects of its own: 140 of 2367 wrappers hardcoded
 * `security definer` against an `invoker` app.* counterpart (RLS-bypass class,
 * ISS-2026-291), and 2359 of 2367 wrappers carried an unintended anon/
 * authenticated EXECUTE grant from this Supabase project's own platform-level
 * default privileges on schema public, which the migration's `revoke ... from
 * public` cleanup does not reach (ISS-2026-292). Both are fixed, additively,
 * by supabase/migrations/20260826010000_harden_public_api_data_wrappers_tierc_fixes.sql
 * (335 files total) -- the already-applied 20260826000000 file is not edited.
 * Re-verified exhaustively live (both mismatch counts to 0) and via a fresh
 * full local db-test suite run (335 migrations, 231 files, ALL PASSED,
 * including public-api-wrapper-regression.sql's own security-mode and
 * grant-parity assertions) before this digest was changed.
 *
 * AMENDED 2026-08-25 (third pass), migrationSetSha256 and dbTestSetSha256.
 * Ruling: docs/build-log/release-go-live/RGL-394.md (CG-S16-RGL-004, Defect
 * Triage) -- this task's own charter is to fix RGL-BLK-004 directly (`_calc_
 * vendor_kpi_rate_validity`'s days-in-window arithmetic collapsed to an empty
 * series for any sub-24-hour or otherwise day-unaligned window, contradicting
 * its own documented guarantee, and failing db:test for 3 of every 24 hours).
 * Fixed additively by supabase/migrations/20260826020000_harden_vendor_kpi_
 * rate_validity_window_calc.sql (336 files total) -- the already-applied
 * 20260730740000 file is not edited. scripts/db-tests/procurement-vendor-
 * performance.sql gained a new, hardcoded (not now()-relative) regression
 * assertion pinning the exact previously-collapsing window shape, so this
 * class of defect is now caught at every hour, not only inside the historical
 * 01:00-03:59 dead band (232 files total -- no new file, the existing one
 * widened). Re-verified via a fresh full local db-test suite run (336
 * migrations, 231 runner files, ALL PASSED) before this digest was changed,
 * and applied to the live hosted project only after that local run passed.
 *
 * AMENDED 2026-08-25 (fourth pass), dbTestSetSha256 only. Ruling:
 * docs/build-log/release-go-live/RGL-395.md (CG-S16-RGL-005, CI/CD Gate
 * Validation) -- this task's own charter is the CI gate-enforcement gap that
 * produced RGL-BLK-005 (reclassified High at RGL-394): `pg_read_file()` is a
 * Postgres SERVER-side function reading the SERVER's filesystem, but the
 * concurrency-race helper scripts write their output files on the psql
 * CLIENT's filesystem. Locally client and server share a host so this
 * happened to work; in CI Postgres runs as a separate `postgis/postgis:
 * 17-3.4` Docker service container with its own filesystem, so the file
 * genuinely does not exist server-side. Fixed, structurally not
 * coincidentally, in all 6 affected files (advanced-tms-wms-outbound.sql,
 * advanced-tms-wms-packing.sql, advanced-tms-wms-picking.sql,
 * automation-rule-engine.sql, procurement-vendor-contract.sql, public-api-
 * platform.sql) by capturing each race-output file's CONTENT client-side via
 * psql's `` \set var `cat "$RACE_OUT_A" ...` `` backtick-subshell syntax
 * (which inherits psql's own process environment) instead of asking the
 * server to read a client-local path with `pg_read_file()`; bridged into
 * `do $$...$$` blocks via the pre-existing `set_config`/`current_setting`
 * GUC pattern where required. No file added or removed (232 files
 * unchanged); only these 6 files' content changed. Re-verified via a fresh
 * full local db-test suite run (336 migrations, 231 runner files, ALL
 * PASSED) before this digest was changed. See RGL-395.md for the CI-run
 * evidence obtained separately from this local run, per RGL-392's standing
 * constraint that no lane may report a CI gate as passing on the strength of
 * a local run alone.
 */
export interface FrozenCandidate {
  readonly id: string;
  readonly migrationSetSha256: string;
  readonly dbTestSetSha256: string;
  readonly lockfileSha256: string;
}

export const FROZEN_CANDIDATE: FrozenCandidate = {
  id: "RC-2026.08.25-1",
  // History: 15f6e7049105f751c6226bef49520bf035e32fad9418d2247ba2c968172a59ac
  // (333 files, RGL-392's original freeze). Superseded 2026-08-25 by the
  // RGL-BLK-002 remediation's new migration (334 files: +1,
  // 20260826000000_create_public_api_data_wrappers.sql, 2367 public.* wrapper
  // functions).
  // History: a9c11bdb1f266f90c29d3697fc3e05526b47379bf95491d1ca27f34a882b0b29
  // (334 files, first-pass amendment above). Superseded 2026-08-25 (second
  // pass) by the same remediation's own Tier C self-correction (335 files: +1,
  // 20260826010000_harden_public_api_data_wrappers_tierc_fixes.sql, closing
  // ISS-2026-291/ISS-2026-292).
  // History: be34c20ff211d741ca043414ffb4bf8d7cd7a6b17fd6d1e525ce39663cd82a4b
  // (335 files, second-pass amendment above). Superseded 2026-08-25 (third
  // pass) by RGL-394's own RGL-BLK-004 fix (336 files: +1,
  // 20260826020000_harden_vendor_kpi_rate_validity_window_calc.sql). See the
  // class-level doc comment above.
  migrationSetSha256: "5fc5907adfa0b06061b9ebd31b8019272ebecdaee2d00e9c92faf48a79726378",
  // History: 4df2ae90f01f1b67ee708efc9919d48de2bb78a76e8d1a52cf14788d508488dd
  // (231 files, RGL-393's widened freeze). Superseded 2026-08-25 by the same
  // remediation's new permanent regression test (232 files: +1,
  // public-api-wrapper-regression.sql).
  // History: 576c4aa0693173d361293df78b79f12f79ed72f5bdd502210f272d54a8a9f438
  // (232 files, prior amendment above). Superseded 2026-08-25 (third pass) by
  // RGL-394's own new regression assertion widening the existing
  // procurement-vendor-performance.sql (still 232 files -- content changed,
  // not file count).
  //
  // 232 tracked .sql files under scripts/db-tests/: the 231 the runner executes,
  // plus fixtures/auth-schema-stub.sql, which it loads into every disposable
  // database before any test runs. RGL-392 §3 originally recorded 2c3389a8...,
  // covering only the 230 top-level files; this gate's own first run caught the
  // omission and RGL-393 widened the freeze to include the fixture. See
  // RGL-393.md §4. The fixture is not incidental — HDN-369 had to correct a
  // stale, load-bearing claim inside it, and its content changes what every
  // db-test runs against.
  // History: 746030c4f93ef1f16da79f87154547cb78e9cad0c8020efadc78a184f4c7aa05
  // (232 files, prior amendment above). Superseded 2026-08-25 (fourth pass) by
  // RGL-395's own RGL-BLK-005 fix: 6 files' content changed (no file added or
  // removed, still 232 files). See the class-level doc comment above.
  dbTestSetSha256: "e531723a2160096d28c778784f53723f07afe36ff9529623964998ad4c4ca07a",
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
