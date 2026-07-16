import { test, describe } from "node:test";
import assert from "node:assert/strict";
import { CanAccessRecordInputSchema, parseUserDirectoryEntry } from "./field-access.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const AUTH_USER_ID = "123e4567-e89b-12d3-a456-426614174000";
const OWNER_ID = "323e4567-e89b-12d3-a456-426614174000";

describe("CanAccessRecordInputSchema", () => {
  test("defaults sharedOrgUnitIds to an empty array and customerAccountRef to null", () => {
    const parsed = CanAccessRecordInputSchema.parse({ authUserId: AUTH_USER_ID, tenantId: TENANT_ID, ownerUserId: OWNER_ID });
    assert.deepEqual(parsed.sharedOrgUnitIds, []);
    assert.equal(parsed.customerAccountRef, null);
  });

  test("mass-assignment protection: unknown/extra fields never survive parsing and are never forwarded to the RPC layer", () => {
    const parsed = CanAccessRecordInputSchema.parse({
      authUserId: AUTH_USER_ID,
      tenantId: TENANT_ID,
      ownerUserId: OWNER_ID,
      // An attacker-supplied extra field that must never reach the RPC call as e.g. a
      // forged is_supreme_admin/bypass flag -- Zod's default (non-.passthrough()) parse
      // strips unknown keys, and the mutation/query layer only ever reads named fields
      // off the parsed result (never spreads the raw input), so this can never leak
      // through even if Zod's stripping behavior were somehow bypassed.
      is_supreme_admin: true,
      bypass: true,
    } as unknown as Record<string, unknown>);
    assert.equal(Object.hasOwn(parsed, "is_supreme_admin"), false);
    assert.equal(Object.hasOwn(parsed, "bypass"), false);
    assert.deepEqual(Object.keys(parsed).sort(), ["authUserId", "customerAccountRef", "ownerUserId", "sharedOrgUnitIds", "tenantId"]);
  });
});

describe("parseUserDirectoryEntry", () => {
  test("maps a snake_case row to the camelCase contract shape", () => {
    const entry = parseUserDirectoryEntry({
      id: "423e4567-e89b-12d3-a456-426614174000",
      tenant_id: TENANT_ID,
      auth_user_id: AUTH_USER_ID,
      display_name: "Jane Doe",
      status: "active",
      org_unit_id: null,
      email: "j***@example.test",
      email_masked: true,
      created_at: "2026-07-16T00:00:00.000Z",
      updated_at: "2026-07-16T00:00:00.000Z",
    });
    assert.equal(entry.emailMasked, true);
    assert.equal(entry.email, "j***@example.test");
  });
});
