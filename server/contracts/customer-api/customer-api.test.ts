import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  parseCustomerApiKey,
  parseCreatedCustomerApiKey,
  CreateCustomerApiKeyInputSchema,
  ListCustomerApiKeysForAccountInputSchema,
} from "./customer-api.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const ACCOUNT_ID = "323e4567-e89b-12d3-a456-426614174000";
const KEY_ID = "423e4567-e89b-12d3-a456-426614174000";
const ADMIN_ID = "523e4567-e89b-12d3-a456-426614174000";

const ROW = {
  id: KEY_ID,
  tenant_id: TENANT_ID,
  name: "Ops Integration",
  key_prefix: "cgk_abcd1234",
  scopes: ["CPT:CustomerPortal"],
  status: "active",
  rate_limit_per_minute: 60,
  expires_at: null,
  last_used_at: null,
  created_at: "2026-08-21T00:00:00.000Z",
  updated_at: "2026-08-21T00:00:00.000Z",
  customer_account_id: ACCOUNT_ID,
  customer_actor_auth_user_id: ADMIN_ID,
};

describe("parseCustomerApiKey", () => {
  test("maps snake_case columns to camelCase, including the customer binding", () => {
    const key = parseCustomerApiKey(ROW);
    assert.equal(key.id, KEY_ID);
    assert.equal(key.customerAccountId, ACCOUNT_ID);
    assert.equal(key.customerActorAuthUserId, ADMIN_ID);
    assert.deepEqual(key.scopes, ["CPT:CustomerPortal"]);
  });

  test("rejects a row missing the customer binding -- a tenant-staff key is never a CustomerApiKey", () => {
    const { customer_account_id, customer_actor_auth_user_id, ...staffRow } = ROW;
    assert.throws(() => parseCustomerApiKey(staffRow as Record<string, unknown>));
  });
});

describe("parseCreatedCustomerApiKey", () => {
  test("carries the one-time raw_key alongside the mapped row", () => {
    const created = parseCreatedCustomerApiKey({ ...ROW, raw_key: "cgk_abcd1234deadbeef" });
    assert.equal(created.rawKey, "cgk_abcd1234deadbeef");
    assert.equal(created.customerAccountId, ACCOUNT_ID);
  });
});

describe("CreateCustomerApiKeyInputSchema", () => {
  test("defaults expiresAt and rateLimitPerMinute to null", () => {
    const parsed = CreateCustomerApiKeyInputSchema.parse({
      tenantId: TENANT_ID,
      accountId: ACCOUNT_ID,
      customerActorAuthUserId: ADMIN_ID,
      name: "Ops Integration",
      actorAuthUserId: ADMIN_ID,
      actorLabel: "self-service",
    });
    assert.equal(parsed.expiresAt, null);
    assert.equal(parsed.rateLimitPerMinute, null);
  });

  test("rejects an empty name", () => {
    assert.throws(() =>
      CreateCustomerApiKeyInputSchema.parse({
        tenantId: TENANT_ID,
        accountId: ACCOUNT_ID,
        customerActorAuthUserId: ADMIN_ID,
        name: "",
        actorAuthUserId: ADMIN_ID,
        actorLabel: "self-service",
      }),
    );
  });
});

describe("ListCustomerApiKeysForAccountInputSchema", () => {
  test("requires tenantId, accountId and actorAuthUserId as real UUIDs", () => {
    const parsed = ListCustomerApiKeysForAccountInputSchema.parse({ tenantId: TENANT_ID, accountId: ACCOUNT_ID, actorAuthUserId: ADMIN_ID });
    assert.equal(parsed.accountId, ACCOUNT_ID);
  });

  test("rejects a non-UUID accountId", () => {
    assert.throws(() => ListCustomerApiKeysForAccountInputSchema.parse({ tenantId: TENANT_ID, accountId: "not-a-uuid", actorAuthUserId: ADMIN_ID }));
  });
});
