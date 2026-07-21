import { test, describe } from "node:test";
import assert from "node:assert/strict";
import { registerForm, publishFormDefinition, setCustomFieldValues, FormMutationError, type FormMutationRpcClient } from "./form.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const OBJECT_ID = "323e4567-e89b-12d3-a456-426614174000";
const VERSION_ID = "423e4567-e89b-12d3-a456-426614174000";
const VALUES_ID = "523e4567-e89b-12d3-a456-426614174000";
const ENTITY_ID = "623e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "723e4567-e89b-12d3-a456-426614174000";

const VALID_FORM_ROW = {
  code: "vendor_onboarding",
  name: "Vendor Onboarding",
  owner_primitive_code: "FORM",
  registered_by: "platform-core-foundation",
  created_at: "2026-07-19T00:00:00.000Z",
};

const VALID_VERSION_ROW = {
  id: VERSION_ID,
  config_object_id: OBJECT_ID,
  version_number: 1,
  status: "published",
  effective_from: "2026-07-19T00:00:00.000Z",
  effective_to: null,
  cloned_from_version_id: null,
  rollback_of_version_id: null,
  created_by: "tenant admin",
  published_by: "tenant admin",
  published_at: "2026-07-19T00:00:00.000Z",
  archived_at: null,
  archived_reason: null,
  record_version: 2,
  created_at: "2026-07-19T00:00:00.000Z",
  updated_at: "2026-07-19T00:00:00.000Z",
};

const VALID_VALUES_ROW = {
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
};

function fakeClient(
  response: { data: unknown; error: { message: string } | null },
): FormMutationRpcClient & { calls: { fn: string; args: Record<string, unknown> }[] } {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];
  return {
    calls,
    async rpc(fn, args) {
      calls.push({ fn, args });
      return response;
    },
  };
}

describe("registerForm", () => {
  test("calls register_form with the exact snake_case params", async () => {
    const client = fakeClient({ data: VALID_FORM_ROW, error: null });
    await registerForm(client, { code: "vendor_onboarding", name: "Vendor Onboarding", ownerPrimitiveCode: "FORM", actorAuthUserId: ACTOR_ID, registeredBy: "tester" });

    assert.deepEqual(client.calls[0]?.args, {
      p_code: "vendor_onboarding",
      p_name: "Vendor Onboarding",
      p_owner_primitive_code: "FORM",
      p_actor_auth_user_id: ACTOR_ID,
      p_registered_by: "tester",
    });
  });

  test("wraps an insufficient_authority error", async () => {
    const client = fakeClient({ data: null, error: { message: "insufficient_authority: only Supreme Admin may register a form" } });
    await assert.rejects(
      () => registerForm(client, { code: "x", name: "X", ownerPrimitiveCode: "FORM", actorAuthUserId: ACTOR_ID, registeredBy: "tester" }),
      (err: unknown) => {
        assert.ok(err instanceof FormMutationError);
        assert.equal(err.code, "insufficient_authority");
        return true;
      },
    );
  });
});

describe("publishFormDefinition", () => {
  test("calls publish_form_definition and returns the published version row", async () => {
    const client = fakeClient({ data: VALID_VERSION_ROW, error: null });
    const version = await publishFormDefinition(client, { versionId: VERSION_ID, actorAuthUserId: ACTOR_ID, actorLabel: "tenant admin" });
    assert.equal(version.status, "published");
  });

  test("wraps a custom_field_duplicate_code error", async () => {
    const client = fakeClient({ data: null, error: { message: "custom_field_duplicate_code: field code tax_id is declared more than once" } });
    await assert.rejects(
      () => publishFormDefinition(client, { versionId: VERSION_ID, actorAuthUserId: ACTOR_ID, actorLabel: "tenant admin" }),
      (err: unknown) => {
        assert.ok(err instanceof FormMutationError);
        assert.equal(err.code, "custom_field_duplicate_code");
        return true;
      },
    );
  });

  test("wraps a custom_field_invalid_condition_reference error", async () => {
    const client = fakeClient({ data: null, error: { message: "custom_field_invalid_condition_reference: field x's condition references y which is not an earlier-declared field" } });
    await assert.rejects(
      () => publishFormDefinition(client, { versionId: VERSION_ID, actorAuthUserId: ACTOR_ID, actorLabel: "tenant admin" }),
      (err: unknown) => {
        assert.ok(err instanceof FormMutationError);
        assert.equal(err.code, "custom_field_invalid_condition_reference");
        return true;
      },
    );
  });
});

describe("setCustomFieldValues", () => {
  test("calls set_custom_field_values with the exact snake_case params", async () => {
    const client = fakeClient({ data: VALID_VALUES_ROW, error: null });
    const values = await setCustomFieldValues(client, {
      configVersionId: VERSION_ID,
      tenantId: TENANT_ID,
      entityType: "vendor",
      entityId: ENTITY_ID,
      values: { tax_id: "123-45-6789" },
      idempotencyKey: "form-9001",
      actorAuthUserId: ACTOR_ID,
      submittedBy: "tenant user",
    });

    assert.deepEqual(client.calls[0]?.args, {
      p_config_version_id: VERSION_ID,
      p_tenant_id: TENANT_ID,
      p_entity_type: "vendor",
      p_entity_id: ENTITY_ID,
      p_values: { tax_id: "123-45-6789" },
      p_idempotency_key: "form-9001",
      p_actor_auth_user_id: ACTOR_ID,
      p_submitted_by: "tenant user",
    });
    assert.deepEqual(values.values, { tax_id: "123-45-6789" });
  });

  test("wraps a custom_field_required_missing error", async () => {
    const client = fakeClient({ data: null, error: { message: "custom_field_required_missing: field tax_id is required and currently visible, but no value was provided" } });
    await assert.rejects(
      () =>
        setCustomFieldValues(client, {
          configVersionId: VERSION_ID,
          tenantId: TENANT_ID,
          entityId: ENTITY_ID,
          values: {},
          idempotencyKey: "form-9001",
          actorAuthUserId: ACTOR_ID,
          submittedBy: "tenant user",
        }),
      (err: unknown) => {
        assert.ok(err instanceof FormMutationError);
        assert.equal(err.code, "custom_field_required_missing");
        return true;
      },
    );
  });

  test("wraps a custom_field_unknown_field error", async () => {
    const client = fakeClient({ data: null, error: { message: "custom_field_unknown_field: bogus_field is not a declared field on this form" } });
    await assert.rejects(
      () =>
        setCustomFieldValues(client, {
          configVersionId: VERSION_ID,
          tenantId: TENANT_ID,
          entityId: ENTITY_ID,
          values: { bogus_field: "x" },
          idempotencyKey: "form-9002",
          actorAuthUserId: ACTOR_ID,
          submittedBy: "tenant user",
        }),
      (err: unknown) => {
        assert.ok(err instanceof FormMutationError);
        assert.equal(err.code, "custom_field_unknown_field");
        return true;
      },
    );
  });
});
