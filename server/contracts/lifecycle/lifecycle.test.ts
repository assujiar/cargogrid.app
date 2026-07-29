import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  FinanceLifecycleEntityTypeSchema,
  FinanceLifecycleCanonicalStateSchema,
  parseFinanceLifecycleRecordState,
} from "./lifecycle.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const RECORD_ID = "323e4567-e89b-12d3-a456-426614174000";

describe("FinanceLifecycleEntityTypeSchema", () => {
  test("accepts the six known entity types", () => {
    for (const entityType of ["invoice", "vendor_bill", "receipt", "settlement", "subledger_batch", "journal"]) {
      assert.doesNotThrow(() => FinanceLifecycleEntityTypeSchema.parse(entityType));
    }
  });

  test("rejects an unknown entity type", () => {
    assert.throws(() => FinanceLifecycleEntityTypeSchema.parse("purchase_order"));
  });
});

describe("FinanceLifecycleCanonicalStateSchema", () => {
  test("accepts the six canonical states", () => {
    for (const state of ["draft", "in_review", "approved", "posted", "corrected", "discarded"]) {
      assert.doesNotThrow(() => FinanceLifecycleCanonicalStateSchema.parse(state));
    }
  });

  test("rejects an unrecognized canonical state", () => {
    assert.throws(() => FinanceLifecycleCanonicalStateSchema.parse("archived"));
  });
});

describe("parseFinanceLifecycleRecordState", () => {
  test("parses the already-camelCase jsonb shape returned by app.get_finance_lifecycle_record_state", () => {
    const parsed = parseFinanceLifecycleRecordState({
      entityType: "journal",
      recordId: RECORD_ID,
      tenantId: TENANT_ID,
      concreteStatus: "posted",
      canonicalState: "posted",
      recordVersion: 3,
      isEditable: false,
      allowedActions: [],
      lockedReason: "posted_immutable_normal_role",
      postedTriggerProtected: true,
    });
    assert.equal(parsed.canonicalState, "posted");
    assert.equal(parsed.postedTriggerProtected, true);
    assert.deepEqual(parsed.allowedActions, []);
  });

  test("accepts a null recordVersion (e.g. subledger_batch, which carries no optimistic-concurrency token)", () => {
    const parsed = parseFinanceLifecycleRecordState({
      entityType: "subledger_batch",
      recordId: RECORD_ID,
      tenantId: TENANT_ID,
      concreteStatus: "posted",
      canonicalState: "posted",
      recordVersion: null,
      isEditable: false,
      allowedActions: [],
      lockedReason: "system_generated_posted_immutable_normal_role",
      postedTriggerProtected: false,
    });
    assert.equal(parsed.recordVersion, null);
  });

  test("rejects a malformed shape", () => {
    assert.throws(() => parseFinanceLifecycleRecordState({ entityType: "journal" }));
  });
});
