import { test, describe } from "node:test";
import assert from "node:assert/strict";
import { MasterAttributesSchema, MasterAliasesSchema, parseMasterType, parseMasterRecord } from "./master-data.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const RECORD_ID = "323e4567-e89b-12d3-a456-426614174000";

describe("MasterAttributesSchema", () => {
  test("accepts string/number/boolean/null leaf values", () => {
    const parsed = MasterAttributesSchema.parse({ a: "x", b: 1, c: true, d: null });
    assert.equal(parsed.a, "x");
  });

  test("rejects a string value containing an angle bracket", () => {
    assert.throws(() => MasterAttributesSchema.parse({ a: "<script>" }));
  });
});

describe("MasterAliasesSchema", () => {
  test("accepts a bounded plain-text array", () => {
    assert.deepEqual(MasterAliasesSchema.parse(["Alt Name"]), ["Alt Name"]);
  });

  test("rejects more than 20 aliases", () => {
    assert.throws(() => MasterAliasesSchema.parse(Array.from({ length: 21 }, (_, i) => `alias-${i}`)));
  });

  test("rejects an alias containing an angle bracket", () => {
    assert.throws(() => MasterAliasesSchema.parse(["<b>x</b>"]));
  });
});

describe("parseMasterType", () => {
  test("maps a raw snake_case row to the camelCase contract shape", () => {
    const type = parseMasterType({
      code: "vendor_rate",
      name: "Vendor Rate",
      scope: "tenant",
      owner_module_code: "PRC",
      registered_by: "platform-core-foundation",
      created_at: "2026-07-17T00:00:00.000Z",
    });
    assert.equal(type.scope, "tenant");
    assert.equal(type.ownerModuleCode, "PRC");
  });
});

describe("parseMasterRecord", () => {
  test("maps a raw snake_case row to the camelCase contract shape", () => {
    const record = parseMasterRecord({
      id: RECORD_ID,
      master_type_code: "vendor_rate",
      tenant_id: TENANT_ID,
      code: "VR-001",
      name: "Sample Vendor Rate",
      aliases: [],
      attributes: {},
      canonical_status: "active",
      merged_into_id: null,
      effective_from: "2026-07-17T00:00:00.000Z",
      effective_to: null,
      created_by: "tester",
      deactivated_at: null,
      deactivated_by: null,
      deactivated_reason: null,
      merged_at: null,
      merged_by: null,
      record_version: 1,
      created_at: "2026-07-17T00:00:00.000Z",
      updated_at: "2026-07-17T00:00:00.000Z",
    });
    assert.equal(record.canonicalStatus, "active");
    assert.equal(record.tenantId, TENANT_ID);
  });

  test("accepts a global-scoped record with a null tenantId", () => {
    const record = parseMasterRecord({
      id: RECORD_ID,
      master_type_code: "some_global_type",
      tenant_id: null,
      code: "G-001",
      name: "Global Record",
      aliases: [],
      attributes: {},
      canonical_status: "active",
      merged_into_id: null,
      effective_from: "2026-07-17T00:00:00.000Z",
      effective_to: null,
      created_by: "tester",
      deactivated_at: null,
      deactivated_by: null,
      deactivated_reason: null,
      merged_at: null,
      merged_by: null,
      record_version: 1,
      created_at: "2026-07-17T00:00:00.000Z",
      updated_at: "2026-07-17T00:00:00.000Z",
    });
    assert.equal(record.tenantId, null);
  });
});
