import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  parseNumberingCounter,
  parseNumberingAllocation,
  AllocateNumberInputSchema,
  BootstrapNumberingCounterInputSchema,
  VoidNumberAllocationInputSchema,
} from "./numbering.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const VERSION_ID = "423e4567-e89b-12d3-a456-426614174000";
const COUNTER_ID = "523e4567-e89b-12d3-a456-426614174000";
const ALLOCATION_ID = "623e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "723e4567-e89b-12d3-a456-426614174000";

describe("parseNumberingCounter", () => {
  test("maps a raw snake_case row to the camelCase contract shape", () => {
    const counter = parseNumberingCounter({
      id: COUNTER_ID,
      config_version_id: VERSION_ID,
      scope_key: "default",
      period_key: "2026",
      next_seq: 42,
      created_at: "2026-07-19T00:00:00.000Z",
      updated_at: "2026-07-19T00:00:00.000Z",
    });
    assert.equal(counter.nextSeq, 42);
    assert.equal(counter.periodKey, "2026");
  });
});

describe("parseNumberingAllocation", () => {
  test("maps a raw snake_case row to the camelCase contract shape", () => {
    const allocation = parseNumberingAllocation({
      id: ALLOCATION_ID,
      tenant_id: TENANT_ID,
      config_version_id: VERSION_ID,
      scope_key: "default",
      period_key: "2026",
      seq: 1,
      formatted_number: "INV-2026-000001",
      entity_type: "generic",
      entity_id: null,
      status: "allocated",
      idempotency_key: "num-9001",
      allocated_by: "tenant user",
      allocated_at: "2026-07-19T00:00:00.000Z",
      voided_at: null,
      voided_reason: null,
      record_version: 1,
      created_at: "2026-07-19T00:00:00.000Z",
      updated_at: "2026-07-19T00:00:00.000Z",
    });
    assert.equal(allocation.formattedNumber, "INV-2026-000001");
    assert.equal(allocation.status, "allocated");
  });
});

describe("AllocateNumberInputSchema", () => {
  test("defaults scopeKey to default, entityType to generic, entityId to null", () => {
    const parsed = AllocateNumberInputSchema.parse({
      configVersionId: VERSION_ID,
      tenantId: TENANT_ID,
      idempotencyKey: "num-9001",
      actorAuthUserId: ACTOR_ID,
      allocatedBy: "tenant user",
    });
    assert.equal(parsed.scopeKey, "default");
    assert.equal(parsed.entityType, "generic");
    assert.equal(parsed.entityId, null);
  });
});

describe("BootstrapNumberingCounterInputSchema", () => {
  test("rejects a negative startingSeq", () => {
    assert.throws(() =>
      BootstrapNumberingCounterInputSchema.parse({
        configVersionId: VERSION_ID,
        periodKey: "2026",
        startingSeq: -1,
        actorAuthUserId: ACTOR_ID,
        actorLabel: "tenant admin",
      }),
    );
  });
});

describe("VoidNumberAllocationInputSchema", () => {
  test("requires a non-empty reason", () => {
    assert.throws(() =>
      VoidNumberAllocationInputSchema.parse({
        allocationId: ALLOCATION_ID,
        actorAuthUserId: ACTOR_ID,
        actorLabel: "tenant admin",
        reason: "",
      }),
    );
  });
});
