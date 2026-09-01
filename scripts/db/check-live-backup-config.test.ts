import { test, describe } from "node:test";
import assert from "node:assert/strict";
import { assessBackupPosture, DECLARED_RPO_MINUTES, type LiveBackupPosture } from "./check-live-backup-config.ts";

function posture(overrides: Partial<LiveBackupPosture> = {}): LiveBackupPosture {
  return {
    pitrEnabled: true,
    walgEnabled: true,
    backupCount: 3,
    newestBackupAgeMinutes: 5,
    organizationPlan: "pro",
    ...overrides,
  };
}

const kinds = (p: LiveBackupPosture) => assessBackupPosture(p).map((f) => f.kind);

describe("assessBackupPosture", () => {
  test("a healthy posture produces no findings", () => {
    assert.deepEqual(assessBackupPosture(posture()), []);
  });

  test("THE LIVE 2026-09-01 SHAPE: PITR off, zero backups, free plan — three distinct findings, not one", () => {
    // Verified against the real project awdlicmwzdxquopwtcfd on 2026-09-01:
    // {"pitr_enabled":false,"walg_enabled":true,"backups":[]} and organization plan "free".
    // Three findings rather than one because the remedies differ: upgrade the plan, buy the
    // add-on, and then have a backup actually exist.
    assert.deepEqual(
      kinds(posture({ pitrEnabled: false, walgEnabled: true, backupCount: 0, newestBackupAgeMinutes: null, organizationPlan: "free" })),
      ["pitr_disabled", "no_restorable_backup", "plan_gated"],
    );
  });

  test("WAL-G running is never allowed to stand in for a customer RPO", () => {
    const finding = assessBackupPosture(posture({ backupCount: 0, newestBackupAgeMinutes: null, walgEnabled: true })).find(
      (f) => f.kind === "no_restorable_backup",
    );
    // The platform's own internal safety net is not something this account can restore from on
    // demand. Reporting it as an RPO would be the most tempting wrong answer here.
    assert.match(finding?.detail ?? "", /not something this account can restore from/i);
  });

  test("zero backups does NOT also raise rpo_exceeded — one problem must not be counted twice", () => {
    const found = kinds(posture({ backupCount: 0, newestBackupAgeMinutes: null }));
    assert.ok(found.includes("no_restorable_backup"));
    assert.ok(!found.includes("rpo_exceeded"));
  });

  test("a backup older than the declared RPO is reported even when everything else is healthy", () => {
    assert.deepEqual(kinds(posture({ newestBackupAgeMinutes: DECLARED_RPO_MINUTES + 1 })), ["rpo_exceeded"]);
  });

  test("a backup exactly at the declared RPO is not a finding — the boundary is inclusive", () => {
    assert.deepEqual(kinds(posture({ newestBackupAgeMinutes: DECLARED_RPO_MINUTES })), []);
  });

  test("an unknown backup age is never treated as fresh", () => {
    // The live API does not always carry a timestamp. Guessing 0 there would silently claim
    // the RPO is met, which is the one failure mode this check exists to prevent.
    assert.deepEqual(kinds(posture({ newestBackupAgeMinutes: null })), []);
    assert.deepEqual(kinds(posture({ backupCount: 0, newestBackupAgeMinutes: null })), ["no_restorable_backup"]);
  });

  test("a paid plan with PITR on and a fresh backup is the only fully clean state", () => {
    assert.deepEqual(kinds(posture({ organizationPlan: "team" })), []);
    assert.deepEqual(kinds(posture({ organizationPlan: "free" })), ["plan_gated"]);
  });

  test("the declared RPO is stated once and asserted here, so a doc change cannot drift from the check", () => {
    assert.equal(DECLARED_RPO_MINUTES, 15);
  });
});
