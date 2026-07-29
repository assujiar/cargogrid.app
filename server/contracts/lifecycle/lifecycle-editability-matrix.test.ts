import { test, describe } from "node:test";
import assert from "node:assert/strict";
import { resolveFinanceLifecycleEditability } from "./lifecycle-editability-matrix.ts";

describe("resolveFinanceLifecycleEditability", () => {
  test("resolves every one of the 26 real (entityType, concreteStatus) pairs identically to the database seed", () => {
    const cases: Array<[Parameters<typeof resolveFinanceLifecycleEditability>[0], string, string, readonly string[]]> = [
      ["invoice", "draft", "draft", ["submit", "discard"]],
      ["invoice", "issued", "posted", []],
      ["vendor_bill", "posted", "posted", []],
      ["receipt", "captured", "posted", ["allocate", "request_deallocation"]],
      ["settlement", "approved", "approved", ["execute"]],
      ["settlement", "executed", "approved", ["post"]],
      ["settlement", "posted", "posted", ["request_reversal"]],
      ["settlement", "reversed", "corrected", []],
      ["subledger_batch", "posted", "posted", []],
      ["subledger_batch", "reversed", "corrected", []],
      ["journal", "posted", "posted", []],
    ];
    for (const [entityType, status, expectedCanonical, expectedActions] of cases) {
      const entry = resolveFinanceLifecycleEditability(entityType, status);
      assert.equal(entry.canonicalState, expectedCanonical, `${entityType}/${status} canonicalState`);
      assert.deepEqual(entry.allowedActions, expectedActions, `${entityType}/${status} allowedActions`);
    }
  });

  test("settlement's own 'approved' and 'executed' concrete statuses coarsen to the same canonical bucket but expose distinct allowed actions", () => {
    const approved = resolveFinanceLifecycleEditability("settlement", "approved");
    const executed = resolveFinanceLifecycleEditability("settlement", "executed");
    assert.equal(approved.canonicalState, executed.canonicalState);
    assert.notDeepEqual(approved.allowedActions, executed.allowedActions);
  });

  test("journal is the one entity type with postedTriggerProtected=true on its posted row", () => {
    assert.equal(resolveFinanceLifecycleEditability("journal", "posted").postedTriggerProtected, true);
    assert.equal(resolveFinanceLifecycleEditability("invoice", "issued").postedTriggerProtected, false);
    assert.equal(resolveFinanceLifecycleEditability("settlement", "posted").postedTriggerProtected, false);
  });

  test("falls back to a safe, non-actionable entry for an unrecognized (entityType, concreteStatus) pair rather than throwing", () => {
    const entry = resolveFinanceLifecycleEditability("journal", "not_a_real_status");
    assert.equal(entry.allowedActions.length, 0);
    assert.equal(entry.lockedReason, "unmapped_lifecycle_state");
  });
});
