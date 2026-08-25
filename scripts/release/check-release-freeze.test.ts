import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  FROZEN_CANDIDATE,
  checkFreeze,
  digestOfFileSet,
  listTrackedFiles,
  type FrozenCandidate,
} from "./check-release-freeze.ts";

describe("check-release-freeze", () => {
  test("the frozen candidate's own digests match this repository's current content", () => {
    // The load-bearing assertion: if this fails, the release candidate has
    // drifted from what CG-S16-RGL-002 froze, and that is the finding.
    const drift = checkFreeze();
    assert.deepEqual(
      drift.map((d) => d.kind),
      [],
      `release candidate ${FROZEN_CANDIDATE.id} has drifted: ${drift.map((d) => d.detail).join("; ")}`,
    );
  });

  test("fails closed when a frozen digest does not match (never silently passes)", () => {
    const tampered: FrozenCandidate = { ...FROZEN_CANDIDATE, migrationSetSha256: "0".repeat(64) };
    const drift = checkFreeze(tampered);
    assert.ok(
      drift.some((d) => d.kind === "MIGRATION_SET"),
      "a mismatched migration-set digest must be reported as drift",
    );
  });

  test("reports every drifting axis, not just the first", () => {
    const tampered: FrozenCandidate = {
      ...FROZEN_CANDIDATE,
      migrationSetSha256: "0".repeat(64),
      dbTestSetSha256: "1".repeat(64),
      lockfileSha256: "2".repeat(64),
    };
    const drift = checkFreeze(tampered);
    assert.deepEqual(new Set(drift.map((d) => d.kind)), new Set(["MIGRATION_SET", "DB_TEST_SET", "LOCKFILE"]));
  });

  test("drift entries carry both the expected and the actual digest, so a report is actionable", () => {
    const tampered: FrozenCandidate = { ...FROZEN_CANDIDATE, lockfileSha256: "3".repeat(64) };
    const [entry] = checkFreeze(tampered).filter((d) => d.kind === "LOCKFILE");
    assert.ok(entry);
    assert.equal(entry.expected, "3".repeat(64));
    assert.match(entry.actual, /^[0-9a-f]{64}$/);
    assert.notEqual(entry.actual, entry.expected);
  });

  test("the migration set is non-empty and enumerated from git, not from a directory read", () => {
    const migrations = listTrackedFiles("supabase/migrations", ".sql");
    assert.ok(migrations.length > 300, `expected the full migration set, got ${migrations.length}`);
    assert.ok(migrations.every((f) => f.startsWith("supabase/migrations/") && f.endsWith(".sql")));
  });

  test("the db-test set is non-empty and enumerated the same way", () => {
    const dbTests = listTrackedFiles("scripts/db-tests", ".sql");
    assert.ok(dbTests.length > 200, `expected the full db-test set, got ${dbTests.length}`);
  });

  test("file ordering is stable, so the digest is reproducible across runs", () => {
    const first = listTrackedFiles("supabase/migrations", ".sql");
    const second = listTrackedFiles("supabase/migrations", ".sql");
    assert.deepEqual(first, second);
    assert.deepEqual(first, [...first].sort());
  });

  test("the digest is order-sensitive — a reordered set must not produce the same hash", () => {
    const files = listTrackedFiles("scripts/db-tests", ".sql");
    const reversed = [...files].reverse();
    assert.notEqual(digestOfFileSet(files), digestOfFileSet(reversed));
  });
});
