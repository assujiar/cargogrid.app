import { test, describe } from "node:test";
import assert from "node:assert/strict";
import { ConfigValueSchema, ConfigItemInputSchema, parseConfigType, parseConfigVersion, parseResolvedConfig } from "./config.ts";

const OBJECT_ID = "323e4567-e89b-12d3-a456-426614174000";
const VERSION_ID = "423e4567-e89b-12d3-a456-426614174000";

describe("ConfigValueSchema", () => {
  test("accepts a nested object/array of primitives", () => {
    const parsed = ConfigValueSchema.parse({ threshold: 1000, approvers: ["manager", "director"], active: true, note: null });
    assert.deepEqual(parsed, { threshold: 1000, approvers: ["manager", "director"], active: true, note: null });
  });

  test("rejects a string value containing an angle bracket at any nesting depth", () => {
    assert.throws(() => ConfigValueSchema.parse({ nested: { note: "<script>alert(1)</script>" } }));
  });
});

describe("ConfigItemInputSchema", () => {
  test("defaults canonicalRef to null", () => {
    const parsed = ConfigItemInputSchema.parse({ key: "approval.threshold", value: 1000 });
    assert.equal(parsed.canonicalRef, null);
  });
});

describe("parseConfigType", () => {
  test("maps a raw snake_case row to the camelCase contract shape", () => {
    const type = parseConfigType({
      code: "approval",
      name: "Approval",
      owner_primitive_code: "APPR",
      registered_by: "platform-core-foundation",
      created_at: "2026-07-17T00:00:00.000Z",
    });
    assert.equal(type.ownerPrimitiveCode, "APPR");
  });
});

describe("parseConfigVersion", () => {
  test("maps a raw snake_case row to the camelCase contract shape", () => {
    const version = parseConfigVersion({
      id: VERSION_ID,
      config_object_id: OBJECT_ID,
      version_number: 1,
      status: "draft",
      effective_from: null,
      effective_to: null,
      cloned_from_version_id: null,
      rollback_of_version_id: null,
      created_by: "tester",
      published_by: null,
      published_at: null,
      archived_at: null,
      archived_reason: null,
      record_version: 1,
      created_at: "2026-07-17T00:00:00.000Z",
      updated_at: "2026-07-17T00:00:00.000Z",
    });
    assert.equal(version.status, "draft");
    assert.equal(version.configObjectId, OBJECT_ID);
  });
});

describe("parseResolvedConfig", () => {
  test("maps a raw app.resolve_config() row", () => {
    const resolved = parseResolvedConfig({
      config_type_code: "approval",
      resolved_scope_level: "tenant",
      resolved_version_id: VERSION_ID,
      effective_from: "2026-07-17T00:00:00.000Z",
      items: { threshold: 1000 },
    });
    assert.equal(resolved.resolvedScopeLevel, "tenant");
    assert.equal(resolved.resolvedVersionId, VERSION_ID);
    assert.deepEqual(resolved.items, { threshold: 1000 });
  });
});
