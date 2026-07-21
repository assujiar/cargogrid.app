import { test, describe } from "node:test";
import assert from "node:assert/strict";
import { parseFormRegistryEntry, parseCustomFieldValues, CustomFieldDefinitionSchema, RegisterFormInputSchema } from "./form.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const VERSION_ID = "423e4567-e89b-12d3-a456-426614174000";
const VALUES_ID = "523e4567-e89b-12d3-a456-426614174000";
const ENTITY_ID = "623e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "723e4567-e89b-12d3-a456-426614174000";

describe("parseFormRegistryEntry", () => {
  test("maps a raw snake_case row to the camelCase contract shape", () => {
    const entry = parseFormRegistryEntry({
      code: "vendor_onboarding",
      name: "Vendor Onboarding",
      owner_primitive_code: "FORM",
      registered_by: "platform-core-foundation",
      created_at: "2026-07-19T00:00:00.000Z",
    });
    assert.equal(entry.ownerPrimitiveCode, "FORM");
  });
});

describe("parseCustomFieldValues", () => {
  test("maps a raw snake_case row to the camelCase contract shape", () => {
    const values = parseCustomFieldValues({
      id: VALUES_ID,
      tenant_id: TENANT_ID,
      config_version_id: VERSION_ID,
      entity_type: "vendor",
      entity_id: ENTITY_ID,
      values: { tax_id: "123-45-6789" },
      submitted_by_auth_user_id: ACTOR_ID,
      submitted_by: "tenant user",
      idempotency_key: "form-9001",
      record_version: 1,
      created_at: "2026-07-19T00:00:00.000Z",
      updated_at: "2026-07-19T00:00:00.000Z",
    });
    assert.deepEqual(values.values, { tax_id: "123-45-6789" });
    assert.equal(values.entityType, "vendor");
  });
});

describe("CustomFieldDefinitionSchema", () => {
  test("defaults required/sensitive to false, options/condition to null, validators to []", () => {
    const parsed = CustomFieldDefinitionSchema.parse({
      code: "tax_id",
      label: "Tax ID",
      type: "text",
    });
    assert.equal(parsed.required, false);
    assert.equal(parsed.sensitive, false);
    assert.equal(parsed.options, null);
    assert.equal(parsed.condition, null);
    assert.deepEqual(parsed.validators, []);
  });

  test("rejects an unknown field type", () => {
    assert.throws(() =>
      CustomFieldDefinitionSchema.parse({
        code: "attachment",
        label: "Attachment",
        type: "file",
      }),
    );
  });
});

describe("RegisterFormInputSchema", () => {
  test("parses a well-formed input", () => {
    const parsed = RegisterFormInputSchema.parse({
      code: "vendor_onboarding",
      name: "Vendor Onboarding",
      ownerPrimitiveCode: "FORM",
      actorAuthUserId: ACTOR_ID,
      registeredBy: "tester",
    });
    assert.equal(parsed.code, "vendor_onboarding");
  });
});
