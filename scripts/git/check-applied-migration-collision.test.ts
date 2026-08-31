import { test, describe } from "node:test";
import assert from "node:assert/strict";
import { findAppliedMigrationCollisions, type MigrationComparison } from "./check-applied-migration-collision.ts";

const APPLIED = "supabase/migrations/20260729270000_create_finance_dashboard.sql";
const NEW = "supabase/migrations/20260831240000_something_new.sql";

describe("findAppliedMigrationCollisions", () => {
  test("a migration the base branch does not have is fine -- that is every normal new migration", () => {
    const comparisons: MigrationComparison[] = [{ path: NEW, baseContent: null, headContent: "create table x();" }];
    assert.deepEqual(findAppliedMigrationCollisions(comparisons), []);
  });

  test("an identical copy of an applied migration is fine -- the overwhelming majority of files on any branch", () => {
    const body = "create function app.f() returns void language sql as $$ select 1 $$;";
    assert.deepEqual(findAppliedMigrationCollisions([{ path: APPLIED, baseContent: body, headContent: body }]), []);
  });

  test("THE ISS-2026-288 SHAPE: same filename, different content, flagged -- regardless of what git status would call it", () => {
    const findings = findAppliedMigrationCollisions([
      { path: APPLIED, baseContent: "create view app.finance_dashboard as select 1;", headContent: "create view app.finance_dashboard as select 2;" },
    ]);
    assert.equal(findings.length, 1);
    assert.equal(findings[0]?.path, APPLIED);
    // The message has to explain the ADDED-status trap, because the person reading it will
    // very likely have just seen git call this file "added" and concluded it was safe.
    assert.match(findings[0]?.reason ?? "", /ADDED/);
    assert.match(findings[0]?.reason ?? "", /corrective migration/);
  });

  test("a whitespace-only difference is still a collision -- normalising would mean deciding which differences are harmless", () => {
    const findings = findAppliedMigrationCollisions([
      { path: APPLIED, baseContent: "select 1;\n", headContent: "select 1;\n\n" },
    ]);
    assert.equal(findings.length, 1);
  });

  test("every colliding file is reported, not just the first -- a stale branch usually carries several", () => {
    const other = "supabase/migrations/20260729280000_create_finance_reports.sql";
    const findings = findAppliedMigrationCollisions([
      { path: APPLIED, baseContent: "a", headContent: "b" },
      { path: NEW, baseContent: null, headContent: "c" },
      { path: other, baseContent: "d", headContent: "e" },
    ]);
    assert.deepEqual(
      findings.map((f) => f.path),
      [APPLIED, other],
    );
  });

  test("an empty comparison set is clean, not an error", () => {
    assert.deepEqual(findAppliedMigrationCollisions([]), []);
  });
});
