import { test, describe } from "node:test";
import assert from "node:assert/strict";
import { getCustomFieldValues, validateCustomFieldValuesPreview, FormQueryError, type FormQueryRpcClient } from "./form.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const VERSION_ID = "423e4567-e89b-12d3-a456-426614174000";
const VALUES_ID = "523e4567-e89b-12d3-a456-426614174000";
const ENTITY_ID = "623e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "723e4567-e89b-12d3-a456-426614174000";

function fakeClient(
  response: { data: unknown; error: { message: string } | null },
): FormQueryRpcClient & { calls: { fn: string; args: Record<string, unknown> }[] } {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];
  return {
    calls,
    async rpc(fn, args) {
      calls.push({ fn, args });
      return response;
    },
  };
}

describe("getCustomFieldValues", () => {
  test("calls get_custom_field_values with the exact snake_case params and maps the row", async () => {
    const client = fakeClient({
      data: {
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
      },
      error: null,
    });

    const values = await getCustomFieldValues(client, { tenantId: TENANT_ID, entityType: "vendor", entityId: ENTITY_ID, actorAuthUserId: ACTOR_ID });
    assert.deepEqual(client.calls[0]?.args, { p_tenant_id: TENANT_ID, p_entity_type: "vendor", p_entity_id: ENTITY_ID, p_actor_auth_user_id: ACTOR_ID });
    assert.deepEqual(values.values, { tax_id: "123-45-6789" });
  });

  test("throws FormQueryError on an rpc error", async () => {
    const client = fakeClient({ data: null, error: { message: "insufficient_authority: identity x may not read a sensitive custom-field values row they did not submit" } });
    await assert.rejects(() => getCustomFieldValues(client, { tenantId: TENANT_ID, entityId: ENTITY_ID, actorAuthUserId: ACTOR_ID }));
  });
});

describe("validateCustomFieldValuesPreview", () => {
  test("calls validate_custom_field_values with the exact snake_case params", async () => {
    const client = fakeClient({ data: true, error: null });
    const valid = await validateCustomFieldValuesPreview(client, VERSION_ID, { tax_id: "123-45-6789" });

    assert.deepEqual(client.calls[0]?.args, { p_config_version_id: VERSION_ID, p_values: { tax_id: "123-45-6789" } });
    assert.equal(valid, true);
  });

  test("throws FormQueryError on a validation failure", async () => {
    const client = fakeClient({ data: null, error: { message: "custom_field_invalid_value: field tax_id expects a string value" } });
    await assert.rejects(() => validateCustomFieldValuesPreview(client, VERSION_ID, { tax_id: 12345 }));
  });
});
